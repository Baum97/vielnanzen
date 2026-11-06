import 'package:fints/fints.dart' as fints;

import '../data/models.dart';
import 'fints_mapping.dart';

/// Rückfragen an den Nutzer während eines Bankabrufs (TAN, Verfahren, Medium).
/// Die UI implementiert diese Schnittstelle mit Dialogen.
abstract class FintsPrompts {
  /// TAN eingeben oder App-Freigabe bestätigen.
  Future<fints.TanAnswer> tan(fints.TanChallenge challenge);

  /// Auswahl des TAN-Verfahrens (pushTAN, photoTAN, …).
  Future<fints.TanMethod?> tanMethod(List<fints.TanMethod> methods);

  /// Auswahl des TAN-Mediums (z. B. welches Smartphone).
  Future<fints.TanMedium?> tanMedium(List<fints.TanMedium> media);

  /// Hinweise der Bank anzeigen.
  void bankMessage(String subject, String text);
}

/// Ergebnis eines Abrufs über eine Bankverbindung.
class FintsSyncResult {
  final List<Account> accounts;
  final Map<String, List<Transaction>> transactions;
  final String state;
  final List<String> warnings;
  final String? newUserId;

  const FintsSyncResult({
    required this.accounts,
    required this.transactions,
    required this.state,
    this.warnings = const [],
    this.newUserId,
  });
}

class FintsSyncException implements Exception {
  final String message;
  final bool pinWrong;
  final String? state;
  const FintsSyncException(this.message, {this.pinWrong = false, this.state});
  @override
  String toString() => message;
}

/// FinTS 3.0 direkt zur Bank – kein eigener Server dazwischen.
///
/// Voraussetzung ist eine (kostenlose) Produktregistrierung bei der Deutschen
/// Kreditwirtschaft: https://www.fints.org/de/hersteller/produktregistrierung
/// Die ID kann in den Einstellungen eingetragen oder beim Bauen per
/// `--dart-define=FINTS_PRODUCT_ID=…` mitgegeben werden.
class FintsConnector {
  FintsConnector({
    required this.connection,
    required this.pin,
    required this.productId,
    required this.prompts,
    this.onNetwork,
    this.transport,
  });

  static const buildProductId = String.fromEnvironment('FINTS_PRODUCT_ID');

  final BankConnection connection;
  final String pin;
  final String productId;
  final FintsPrompts prompts;
  final void Function(String host, String purpose)? onNetwork;
  /// Für Tests: eigener Transport statt HTTP.
  final fints.FinTsTransport? transport;

  fints.FinTsClient _client() {
    final config = fints.FinTsConfig(
      url: Uri.parse(connection.fintsUrl.trim()),
      bankCode: connection.blz.trim(),
      userId: connection.userId.trim(),
      customerId: (connection.customerId?.trim().isEmpty ?? true) ? null : connection.customerId!.trim(),
      productId: productId.trim(),
      productVersion: '1.1',
    );
    return fints.FinTs3Client(
      config: config,
      pin: pin,
      options: fints.FinTsClientOptions(
        state: connection.fintsState,
        transport: transport,
        tanCallback: prompts.tan,
        tanMethodSelector: prompts.tanMethod,
        tanMediumSelector: prompts.tanMedium,
        onBankMessage: (m) => prompts.bankMessage(m.subject, m.text),
      ),
    );
  }

  static AccountType mapType(fints.AccountCategory c) => switch (c) {
        fints.AccountCategory.creditCard => AccountType.kreditkarte,
        fints.AccountCategory.savings || fints.AccountCategory.fixedDeposit => AccountType.tagesgeld,
        fints.AccountCategory.securities || fints.AccountCategory.fund => AccountType.depot,
        _ => AccountType.giro,
      };

  static String accountIdFor(fints.Account a) =>
      'acc_${(a.iban ?? '${a.bankCode}_${a.accountNumber}_${a.subAccount ?? ''}').replaceAll(RegExp(r'[^A-Za-z0-9_]'), '')}';

  /// Holt Konten, Salden und Umsätze. [since] = ab wann (null: so weit die Bank liefert, max. 5 Jahre).
  /// [freshPin]: die PIN wurde gerade neu eingegeben – eine gespeicherte Anmeldesperre wird dann aufgehoben.
  Future<FintsSyncResult> sync({DateTime? since, bool freshPin = false}) async {
    final host = Uri.tryParse(connection.fintsUrl)?.host ?? connection.fintsUrl;
    final fints.FinTsClient client;
    try {
      client = _client();
    } on ArgumentError catch (e) {
      throw FintsSyncException('Ungültige Angaben: ${e.message} (${e.name ?? ''})');
    }
    final warnings = <String>[];
    try {
      if (freshPin && client.loginRefusal != null) await client.clearLoginRefusal(pin);
      onNetwork?.call(host, 'Konten abrufen (${connection.bankName})');
      final remote = await client.getAccounts();
      final accounts = <Account>[];
      final txs = <String, List<Transaction>>{};
      for (final a in remote) {
        final type = mapType(a.category);
        if (type == AccountType.depot || a.category == fints.AccountCategory.loan) continue;
        final id = accountIdFor(a);
        var balance = 0;
        DateTime? balanceDate;
        try {
          onNetwork?.call(host, 'Saldo (${a.iban ?? a.accountNumber})');
          final b = await client.getBalance(a);
          balance = amountToCents(b.booked);
          balanceDate = b.bookedAsOf;
        } on fints.FinTsUnsupportedException {
          warnings.add('Saldo für ${a.productName ?? a.iban} nicht verfügbar.');
        }
        accounts.add(Account(
          id: id,
          connectionId: connection.id,
          iban: a.iban ?? '',
          accountNumber: a.accountNumber,
          bankCode: a.bankCode,
          name: (a.productName?.trim().isNotEmpty ?? false) ? a.productName!.trim() : _defaultName(type),
          type: type,
          currency: a.currency ?? 'EUR',
          balanceCents: balance,
          balanceDate: balanceDate ?? DateTime.now(),
          lastSync: DateTime.now(),
        ));
        txs[id] = await _transactions(client, a, id, since, host, warnings);
      }
      return FintsSyncResult(accounts: accounts, transactions: txs, state: client.state, warnings: warnings);
    } on FintsSyncException {
      rethrow;
    } on fints.FinTsLoginDataChangedException catch (e) {
      throw FintsSyncException('Die Bank hat neue Zugangsdaten mitgeteilt (Anmeldename: ${e.userId ?? e.loginName ?? '–'}). Bitte Verbindung neu einrichten.',
          state: _safeState(client));
    } on fints.FinTsPinException catch (e) {
      throw FintsSyncException('PIN falsch oder Zugang gesperrt: ${e.message}', pinWrong: true, state: _safeState(client));
    } on fints.FinTsLoginRefusedException catch (e) {
      throw FintsSyncException(
          'Anmeldung abgelehnt: ${e.message.isEmpty ? 'ohne Begründung' : e.message}. '
          'Zum Schutz vor einer Sperre wird die PIN nicht automatisch erneut gesendet.',
          state: _safeState(client));
    } on fints.FinTsTanCancelledException {
      throw FintsSyncException('Freigabe abgebrochen.', state: _safeState(client));
    } on fints.FinTsDecoupledTimeoutException {
      throw FintsSyncException('Die Freigabe in der Banking-App kam nicht rechtzeitig.', state: _safeState(client));
    } on fints.FinTsTanException catch (e) {
      throw FintsSyncException('TAN abgelehnt: ${e.message}', state: _safeState(client));
    } on fints.FinTsTanSetupException catch (e) {
      throw FintsSyncException('Kein passendes TAN-Verfahren: ${e.message}', state: _safeState(client));
    } on fints.FinTsTransportException catch (e) {
      throw FintsSyncException('Bank nicht erreichbar (${e.statusCode ?? 'keine Verbindung'}). Prüfe Internet und FinTS-Adresse.',
          state: _safeState(client));
    } on fints.FinTsBankException catch (e) {
      final codes = e.codes.toSet();
      final hint = codes.contains('9078') || codes.contains('9079') || e.message.toLowerCase().contains('produkt')
          ? ' Die FinTS-Produkt-ID fehlt oder ist nicht registriert (Einstellungen → Bankverbindung).'
          : '';
      throw FintsSyncException('Die Bank meldet: ${e.message}$hint', state: _safeState(client));
    } on fints.FinTsException catch (e) {
      throw FintsSyncException('FinTS-Fehler: ${e.message}', state: _safeState(client));
    } on ArgumentError catch (e) {
      throw FintsSyncException('Ungültige Angaben: ${e.message} (${e.name ?? ''})');
    } catch (e) {
      throw FintsSyncException('Abruf fehlgeschlagen: $e', state: _safeState(client));
    } finally {
      try {
        await client.close();
      } catch (_) {}
    }
  }

  static String? _safeState(fints.FinTsClient c) {
    try {
      return c.state;
    } catch (_) {
      return null;
    }
  }

  /// Umsätze mit Rückfall auf kürzere Zeiträume, falls die Bank lange Zeiträume ablehnt.
  Future<List<Transaction>> _transactions(
      fints.FinTsClient client, fints.Account a, String accountId, DateTime? since, String host, List<String> warnings) async {
    final now = DateTime.now();
    final tries = <DateTime>[
      since ?? DateTime(now.year - 5, now.month, now.day),
      if (since == null) ...[DateTime(now.year - 2, now.month, now.day), DateTime(now.year - 1, now.month, now.day), now.subtract(const Duration(days: 90))],
    ];
    Object? lastError;
    for (final from in tries) {
      try {
        onNetwork?.call(host, 'Umsätze seit ${from.day}.${from.month}.${from.year}');
        final list = await client.getTransactions(a, from: from);
        return list.map((t) => mapFintsTransaction(t, accountId)).toList();
      } on fints.FinTsIncompleteResultException catch (e) {
        final partial = e.partialResult;
        if (partial is List<fints.Transaction>) {
          warnings.add('Die Bank hat nicht alle Umsätze geliefert.');
          return partial.map((t) => mapFintsTransaction(t, accountId)).toList();
        }
        lastError = e;
      } on fints.FinTsUnsupportedException catch (e) {
        warnings.add('Umsatzabruf für ${a.productName ?? a.iban} nicht unterstützt: ${e.message}');
        return const [];
      } on fints.FinTsBankException catch (e) {
        if (e is fints.FinTsLoginRefusedException || e is fints.FinTsTanException) rethrow;
        lastError = e; // z. B. Zeitraum zu groß → kürzer versuchen
      }
    }
    if (lastError != null) warnings.add('Umsätze für ${a.productName ?? a.iban} nicht abrufbar: $lastError');
    return const [];
  }

  static String _defaultName(AccountType t) => switch (t) {
        AccountType.kreditkarte => 'Kreditkarte',
        AccountType.tagesgeld => 'Tagesgeld',
        _ => 'Girokonto',
      };
}
