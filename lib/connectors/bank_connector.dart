import '../data/models.dart';

/// Schnittstelle für alle Konto-Anbindungswege.
/// FinTS direkt zur Bank (Hauptweg), Datei-Import (Fallback), manuell (Bargeld).
abstract class BankConnector {
  String get id;
  String get label;
  Future<ConnectorResult> fetchAccounts();
  Future<ConnectorResult> fetchTransactions(Account account, {DateTime? from});
}

class ConnectorResult {
  final List<Account>? accounts;
  final List<Transaction>? transactions;
  final String? error;
  final bool needsTan;
  final String? tanChallenge;

  const ConnectorResult({this.accounts, this.transactions, this.error, this.needsTan = false, this.tanChallenge});

  bool get ok => error == null;
}
