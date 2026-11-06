import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics/analytics.dart';
import '../core/analytics/time_range.dart';
import '../core/engine/engine.dart';
import '../data/models.dart';
import '../data/store.dart';

/// Wird in `main()` mit dem geladenen Store überschrieben.
final storeProvider = Provider<Store>((ref) => throw UnimplementedError('storeProvider muss überschrieben werden'));

/// Stammdaten (Kategorien, Händler) – in `main()` aus den Assets geladen.
final seedProvider = Provider<SeedData>((ref) => const SeedData());

final engineProvider = Provider<Engine>((ref) => Engine(ref.watch(seedProvider)));

/// Globaler App-Zustand: Revision (steigt bei jeder Datenänderung) + Status-Flags.
class AppState {
  final int revision;
  final bool analyzing;
  final bool syncing;
  final int uncategorized;

  const AppState({this.revision = 0, this.analyzing = false, this.syncing = false, this.uncategorized = 0});

  AppState copyWith({int? revision, bool? analyzing, bool? syncing, int? uncategorized}) => AppState(
        revision: revision ?? this.revision,
        analyzing: analyzing ?? this.analyzing,
        syncing: syncing ?? this.syncing,
        uncategorized: uncategorized ?? this.uncategorized,
      );
}

final appStateProvider = NotifierProvider<AppStateNotifier, AppState>(AppStateNotifier.new);

class AppStateNotifier extends Notifier<AppState> {
  Store get store => ref.read(storeProvider);

  @override
  AppState build() {
    final s = ref.watch(storeProvider);
    void listener() => state = state.copyWith(revision: state.revision + 1);
    s.addListener(listener);
    ref.onDispose(() => s.removeListener(listener));
    return const AppState();
  }

  void setSyncing(bool v) => state = state.copyWith(syncing: v);

  bool _queued = false;

  /// Kategorisiert alle Umsätze, erkennt Verträge und Spar-Hinweise.
  Future<void> runAnalysis() async {
    if (state.analyzing) {
      _queued = true;
      return;
    }
    state = state.copyWith(analyzing: true);
    try {
      final engine = ref.read(engineProvider);
      final txs = List<Transaction>.of(store.transactions);
      final accounts = List<Account>.of(store.accounts);
      final rules = List<Rule>.of(store.rules);
      final contracts = List<Contract>.of(store.contracts);
      final result = await runEngine(engine, txs, accounts, rules, contracts);
      // Nur übernehmen, wenn sich die Umsatzliste währenddessen nicht verändert hat.
      if (store.transactions.length == txs.length) {
        // Während der Analyse geänderte Umsätze (z. B. neue Kategorie) behalten –
        // der nachfolgende Lauf wertet sie aus.
        final merged = List<Transaction>.of(result.transactions);
        for (var i = 0; i < txs.length; i++) {
          if (!identical(store.transactions[i], txs[i])) {
            merged[i] = store.transactions[i];
            _queued = true;
          }
        }
        store.batch(() {
          store.replaceAnalyzedTransactions(merged);
          store.contracts
            ..clear()
            ..addAll(result.contracts);
          store.replaceInsights(result.insights);
        });
      } else {
        _queued = true;
      }
      state = state.copyWith(analyzing: false, uncategorized: result.uncategorizedCount);
    } catch (e, st) {
      debugPrint('Analyse fehlgeschlagen: $e\n$st');
      state = state.copyWith(analyzing: false);
    }
    if (_queued) {
      _queued = false;
      await runAnalysis();
    }
  }
}

/// In Widget-Tests abschaltbar (Isolates laufen dort nicht in der Test-Zone).
bool analysisInIsolate = true;

/// Führt die Analyse aus – bei vielen Umsätzen in einem Hintergrund-Isolate,
/// damit die Oberfläche flüssig bleibt. Eigene Funktion, damit die Closure
/// nur übertragbare Werte enthält.
Future<EngineResult> runEngine(Engine engine, List<Transaction> txs, List<Account> accounts, List<Rule> rules, List<Contract> contracts) async {
  EngineResult compute() => engine.run(transactions: txs, accounts: accounts, rules: rules, existingContracts: contracts);
  if (kIsWeb || !analysisInIsolate || txs.length < 300) return compute();
  try {
    return await Isolate.run(compute);
  } catch (e) {
    debugPrint('Isolate nicht verfügbar, rechne im Haupt-Thread: $e');
    return compute();
  }
}

/// Gewählter Zeitraum (1W … 5J), gilt für alle Tabs und wird gespeichert.
final rangeProvider = NotifierProvider<RangeNotifier, TimeRange>(RangeNotifier.new);

class RangeNotifier extends Notifier<TimeRange> {
  @override
  TimeRange build() => TimeRange.fromName(ref.read(storeProvider).settings['timeRange'] as String?);

  void set(TimeRange r) {
    state = r;
    ref.read(storeProvider).updateSettings({'timeRange': r.name});
  }
}

/// Auswertungs-Helfer über alle Umsätze (neu bei jeder Datenänderung).
final analyticsProvider = Provider<Analytics>((ref) {
  ref.watch(appStateProvider.select((s) => s.revision));
  final store = ref.read(storeProvider);
  return ref.read(engineProvider).analytics(transactions: store.transactions, accounts: store.accounts);
});

final periodProvider = Provider.family<PeriodAnalysis, TimeRange>((ref, range) => ref.watch(analyticsProvider).analyze(range));

/// Auswertung des aktuell gewählten Zeitraums.
final currentPeriodProvider = Provider<PeriodAnalysis>((ref) => ref.watch(periodProvider(ref.watch(rangeProvider))));

/// Diskret-Modus (Beträge verbergen).
final discreetProvider = Provider<bool>((ref) {
  ref.watch(appStateProvider.select((s) => s.revision));
  return ref.read(storeProvider).settings['discreetMode'] == true;
});
