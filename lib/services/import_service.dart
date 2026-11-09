import '../core/import/csv_mapping.dart';
import '../core/import/file_import.dart';
import '../core/import/iban.dart';
import '../data/bank_directory.dart';
import '../data/models.dart';
import '../data/store.dart';

/// Findet das vorhandene Konto, zu dem die Datei gehört (IBAN oder BLZ/Kontonummer).
Account? matchAccount(List<Account> accounts, DetectedAccount? detected) {
  final key = detected?.key;
  if (detected == null || detected.isEmpty) return null;
  if (detected.iban != null) {
    final byIban = accounts.where((a) => a.iban.isNotEmpty && normalizeIban(a.iban) == detected.iban).firstOrNull;
    if (byIban != null) return byIban;
  }
  if (key == null) return null;
  for (final a in accounts) {
    String? k;
    final parts = a.iban.isEmpty ? null : germanParts(a.iban);
    if (parts != null) {
      k = accountKey(parts.blz, parts.account);
    } else if (a.bankCode != null && a.accountNumber != null) {
      k = accountKey(a.bankCode!, a.accountNumber!);
    }
    if (k == key) return a;
  }
  return null;
}

/// Vorschlag für Name und Kennung eines neuen Kontos aus dem erkannten Konto.
({String name, String id, String iban}) suggestNewAccount(DetectedAccount? detected, BankDirectory? directory, {String fallbackName = 'Importiertes Konto'}) {
  final iban = detected?.iban ?? '';
  BankEntry? bank;
  if (iban.isNotEmpty) bank = directory?.forIban(iban);
  bank ??= detected?.bankCode == null ? null : directory?.byBlz(detected!.bankCode!);
  final tail = iban.length >= 4 ? iban.substring(iban.length - 4) : (detected?.accountNumber ?? '');
  final base = bank?.name ?? fallbackName;
  final name = tail.isEmpty || bank == null ? base : '$base …$tail';
  final slug = iban.isNotEmpty
      ? iban
      : (detected?.key ?? fallbackName).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
  return (name: name, id: 'acc_$slug', iban: iban);
}

/// Was beim Import mit einer Datei passieren soll.
class ImportPlan {
  const ImportPlan({
    required this.parsed,
    required this.accountId,
    this.newAccountName,
    this.newAccountIban = '',
    this.balanceCents,
  });

  final ParseImport parsed;

  /// Ziel-Konto (existierend oder neu).
  final String accountId;

  /// Gesetzt → das Konto wird neu angelegt.
  final String? newAccountName;
  final String newAccountIban;

  /// Aktueller Kontostand, falls bekannt (sonst bleibt der alte).
  final int? balanceCents;
}

const _targetsKey = 'importTargets';

/// Gemerktes Zielkonto je CSV-Format (Tabellen-Signatur) – für Exporte ohne IBAN.
String? savedTarget(Store store, String signature) {
  final raw = store.settings[_targetsKey];
  if (raw is! Map) return null;
  final id = raw[signature];
  return id is String && store.accountById(id) != null ? id : null;
}

void rememberTarget(Store store, String signature, String accountId) {
  final map = {...((store.settings[_targetsKey] as Map?) ?? const {}), signature: accountId};
  store.updateSettings({_targetsKey: map});
}

class ImportOutcome {
  final int added;
  final int duplicates;
  const ImportOutcome(this.added, this.duplicates);
}

/// Spielt geparste Dateien in den Store ein und merkt sich vom Nutzer gewählte Spaltenzuordnungen.
ImportOutcome applyImport(Store store, List<ImportPlan> plans) {
  var added = 0, total = 0;
  store.batch(() {
    for (final plan in plans) {
      final existing = store.accountById(plan.accountId);
      if (existing == null) {
        store.upsertAccount(Account(
          id: plan.accountId,
          iban: plan.newAccountIban,
          name: (plan.newAccountName?.trim().isEmpty ?? true) ? 'Importiertes Konto' : plan.newAccountName!.trim(),
          type: AccountType.giro,
          balanceCents: plan.balanceCents ?? plan.parsed.transactions.fold<int>(0, (a, t) => a + t.amountCents),
          balanceDate: DateTime.now(),
          lastSync: DateTime.now(),
        ));
      } else if (plan.balanceCents != null) {
        store.upsertAccount(existing.copyWith(balanceCents: plan.balanceCents, balanceDate: DateTime.now(), lastSync: DateTime.now()));
      } else {
        store.upsertAccount(existing.copyWith(lastSync: DateTime.now()));
      }
      total += plan.parsed.transactions.length;
      added += store.upsertTransactions(plan.parsed.transactions);

      final m = plan.parsed.usedMapping;
      final table = plan.parsed.table;
      if (plan.parsed.mappingFromUser && m != null && table != null) rememberMapping(store, table.signature, m);
      if (table != null && plan.parsed.account == null) rememberTarget(store, table.signature, plan.accountId);
    }
  });
  return ImportOutcome(added, total - added);
}

const _profilesKey = 'csvProfiles';

/// Gemerkte Spaltenzuordnungen (Tabellen-Signatur → Zuordnung).
Map<String, CsvMapping> savedMappings(Store store) {
  final raw = store.settings[_profilesKey];
  if (raw is! Map) return const {};
  final out = <String, CsvMapping>{};
  raw.forEach((k, v) {
    try {
      out[k as String] = CsvMapping.fromJson(Map<String, dynamic>.from(v as Map));
    } catch (_) {}
  });
  return out;
}

void rememberMapping(Store store, String signature, CsvMapping mapping) {
  final profiles = {
    ...((store.settings[_profilesKey] as Map?) ?? const {}),
    signature: mapping.toJson(),
  };
  store.updateSettings({_profilesKey: profiles});
}
