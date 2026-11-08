import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connectors/fints_connector.dart';
import '../core/import/file_import.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../state/app_state.dart';

/// Zusammenfassung eines Abrufs für die Anzeige.
class SyncSummary {
  final int accounts;
  final int newTransactions;
  final List<String> warnings;
  const SyncSummary(this.accounts, this.newTransactions, this.warnings);

  String get message =>
      '$accounts ${accounts == 1 ? 'Konto' : 'Konten'} aktualisiert · $newTransactions neue Umsätze${warnings.isEmpty ? '' : ' · ${warnings.length} Hinweis(e)'}';
}

final bankSyncProvider = Provider<BankSyncService>(BankSyncService.new);

/// Holt Konten und Umsätze über FinTS und spielt sie in den Store ein.
class BankSyncService {
  BankSyncService(this.ref);
  final Ref ref;

  Store get _store => ref.read(storeProvider);

  String get productId {
    final fromSettings = (_store.settings['fintsProductId'] as String? ?? '').trim();
    return fromSettings.isNotEmpty ? fromSettings : FintsConnector.buildProductId;
  }

  Future<String?> savedPin(BankConnection c) async => c.pinSaved ? _store.keyStore.read(Store.pinKeyFor(c.id)) : null;

  /// Ab wann neu abgerufen wird: 14 Tage vor dem jüngsten bekannten Umsatz (Nachbuchungen),
  /// beim ersten Abruf so weit zurück wie möglich.
  DateTime? _since(BankConnection c) {
    final ids = _store.accounts.where((a) => a.connectionId == c.id).map((a) => a.id).toSet();
    DateTime? latest;
    for (final t in _store.transactions) {
      if (!ids.contains(t.accountId)) continue;
      if (latest == null || t.bookingDate.isAfter(latest)) latest = t.bookingDate;
    }
    return latest?.subtract(const Duration(days: 14));
  }

  Future<SyncSummary> sync(
    BankConnection connection, {
    required String pin,
    required FintsPrompts prompts,
    bool savePin = false,
    bool freshPin = true,
  }) async {
    if (productId.isEmpty) {
      throw const FintsSyncException(
          'Für den Bankabruf wird eine FinTS-Produkt-ID benötigt. Sie ist kostenlos bei der Deutschen Kreditwirtschaft '
          '(fints.org → Produktregistrierung) erhältlich und wird unter Einstellungen → Bankverbindung eingetragen.');
    }
    final notifier = ref.read(appStateProvider.notifier);
    notifier.setSyncing(true);
    try {
      final result = await FintsConnector(
        connection: connection,
        pin: pin,
        productId: productId,
        prompts: prompts,
        onNetwork: _store.addNetworkLog,
      ).sync(since: _since(connection), freshPin: freshPin);

      var added = 0;
      final now = DateTime.now();
      _store.batch(() {
        for (final acc in result.accounts) {
          final existing = _store.accountById(acc.id);
          _store.upsertAccount(existing == null
              ? acc
              : acc.copyWith(
                  name: existing.name,
                  color: existing.color,
                  hidden: existing.hidden,
                  includeInTotal: existing.includeInTotal,
                ));
        }
        for (final list in result.transactions.values) {
          added += _store.upsertTransactions(withOccurrenceHashes(list));
        }
        _store.upsertConnection(connection.copyWith(
          fintsState: result.state,
          lastSync: now,
          clearError: true,
          pinSaved: savePin || connection.pinSaved,
          lastScaDate: now,
          scaValidUntil: now.add(const Duration(days: 180)),
        ));
      });
      if (savePin) await _store.keyStore.write(Store.pinKeyFor(connection.id), pin);
      await _store.save();
      await notifier.runAnalysis();
      return SyncSummary(result.accounts.length, added, result.warnings);
    } on FintsSyncException catch (e) {
      var c = connection.copyWith(lastError: e.message, fintsState: e.state);
      if (e.pinWrong && connection.pinSaved) {
        await _store.keyStore.write(Store.pinKeyFor(connection.id), null);
        c = c.copyWith(pinSaved: false);
      }
      _store.upsertConnection(c);
      rethrow;
    } finally {
      notifier.setSyncing(false);
    }
  }

  /// Entfernt eine Bankverbindung mit allen Konten, Umsätzen und der gespeicherten PIN.
  Future<void> removeConnection(BankConnection c) async {
    await _store.keyStore.write(Store.pinKeyFor(c.id), null);
    for (final a in _store.accounts.where((a) => a.connectionId == c.id).toList()) {
      _store.removeAccount(a.id);
    }
    _store.connections.removeWhere((x) => x.id == c.id);
    _store.updateSettings({});
    await ref.read(appStateProvider.notifier).runAnalysis();
  }
}
