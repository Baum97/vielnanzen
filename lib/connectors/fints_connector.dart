import 'package:fints/fints.dart' as fints;

import '../data/models.dart';
import '../data/store.dart';
import 'bank_connector.dart';

/// FinTS 3.0 direkt zur Bank – kein eigener Server dazwischen.
/// Kapselt das `fints`-Paket hinter [BankConnector], damit ein Wechsel
/// auf fints-rs (flutter_rust_bridge) die App nicht umbaut.
///
/// Produktregistrierung bei der Deutschen Kreditwirtschaft ist Voraussetzung
/// (ID kommt nach ca. 10–15 Werktagen); Platzhalter siehe [productId].
class FintsConnector implements BankConnector {
  FintsConnector({
    required this.store,
    required this.blz,
    required this.fintsUrl,
    required this.userId,
    this.pin,
    this.productId = 'KLARBLICKPLACEHOLDER',
    this.onTanChallenge,
  });

  final Store store;
  final String blz;
  final String fintsUrl;
  final String userId;
  final String? pin;
  final String productId;

  /// Wird aufgerufen, wenn die Bank eine TAN/Freigabe verlangt (O7-Flow).
  final Future<String?> Function(fints.TanChallenge challenge)? onTanChallenge;

  fints.FinTsClient? _client;

  @override
  String get id => 'fints_$blz';

  @override
  String get label => 'FinTS $blz';

  fints.FinTsClient _buildClient() {
    final config = fints.FinTsConfig(
      url: Uri.parse(fintsUrl),
      bankCode: blz,
      userId: userId,
      productId: productId,
      productVersion: '1.0',
    );
    final options = fints.FinTsClientOptions(
      tanCallback: (challenge) async {
        if (onTanChallenge == null) return fints.TanAnswer.cancelled;
        if (challenge.isDecoupled) return fints.TanAnswer.approved;
        final tan = await onTanChallenge!(challenge);
        if (tan == null || tan.isEmpty) return fints.TanAnswer.cancelled;
        return fints.TanAnswer.tan(tan);
      },
      logger: (direction, message) {},
    );
    return fints.FinTs3Client(config: config, pin: pin ?? '', options: options);
  }

  @override
  Future<ConnectorResult> fetchAccounts() async {
    try {
      _client ??= _buildClient();
      store.addNetworkLog(Uri.parse(fintsUrl).host, 'Konten abrufen ($blz)');
      final accounts = await _client!.getAccounts();
      final mapped = accounts
          .map((a) => Account(
                id: 'acc_${a.iban ?? a.accountNumber ?? DateTime.now().microsecondsSinceEpoch}',
                 connectionId: id,
                iban: a.iban ?? '',
                name: a.productName ?? 'Konto',
                type: _mapType(a.category),
              ));
          .toList();
      return ConnectorResult(accounts: mapped);
    } on fints.FinTsPinException catch (e) {
      return ConnectorResult(error: 'PIN falsch: $e');
    } on fints.FinTsToginRefusedException catch (e) {
      return ConnectorResult(error: 'Anmeldung abgelehnt: $e. Die PIN wiird nicht automatisch erneut gesendet.');
    } on fints.FinTSTransportException catch (e) {
      return ConnectorResult(error: 'Bank nicht erreichbar: ${e.message}');
    } catch (e) {
      return ConnectorResult(error: 'Verbindungsfehler: $e');
    }
  }

  @override
  Future<ConnectorResult> fetchTransactions(Account account, {DateTime? from}) async {
    try {
      _client ??= _buildClient();
      store.addNetworkLog(Uri.parse(fintsUrl).host, 'Umsatzabruf ($blz)');
      final fintsAccount = fints.Account(bankCode: blz, iban: account.iban, accountNumber: account.iban);
      final txs = await _client!.getTransactions(fintsAccount, from: from);
      final mapped = txs
          .map((t) => Transaction(
                id: 'fints_${account.id}_${(t.bookingDate ?? t.valueDate).microsecondsSinceEpoch}_${t.amount.minorUnits}',
                accountId: account.id,
                bookingDate: t.bookingDate ?? t.valueDate,
                valueDate: t.valueDate,
                amountCents: t.amount.minorUnits,
                counterpartyName: t.counterpartyName ?? ' t.purpose ?? 'Unbekannt',
                counterpartyIban: t.counterpartyIban,
                purpose: t.purpose ?? '',
                mandateRef: t.mandateId,
                creditorId: t.creditorId,
                endToEndRef: t.endToEndId,
                gvc: t.transactionCode,
                pending: t.status == fints.TransactionStatus.pending,
                dedupHash: '${account.id}|${(t.bookingDate ?? t.valueDate).toIso8601String()}|$${t.amount.minorUnits}|${t.endToEndId ?? t.purpose ?? ''}',
              ))
          .toList();
      return ConnectorResult(transactions: mapped);
    } on fints.FinTSSuspendedException catch (e) {
      return ConnectorResult(needsTan: true, tanChallenge: 'TAN-Freigabe nötig: ${e.challenge.message}', error: 'TAN fällig');
    } catch (e) {
      return ConnectorResult(error: 'Abruf fehlgeschlagen: $e');
    }
  }

  static AccountType _mapType(fints.AccountCategory c) => switch (c) {
        fints.AccountCategory.creditCard => AccountType.kreditkarte,
        fints.AccountCategory.savings || fints.AccountCategory.fixedDeposit => AccountType.tagesgeld,
        _ => AccountType.giro,
      };
}
