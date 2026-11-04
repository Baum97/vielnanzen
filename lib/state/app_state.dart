import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/engine/engine.dart';
import '../data/models.dart';
import '../data/store.dart';

final storeProvider = Provider<Store>((ref) => Store());

final engineProvider = Provider<Engine>((ref) => Engine(ref.watch(storeProvider)));

/// Geladener Zustand: Store + Engine-Ergebnis.
class AppState {
  final Store store;
  final EngineResult? result;
  final bool analyzing;

  const AppState({required this.store, this.result, this.analyzing = false});

  AppState copyWith({Store? store, EngineResult? result, bool? analyzing}) =>       AppState(store: store ?? this.store, result: result ?? this.result, analyzing: analyzing ?? this.analyzing);
}

final appStateProvider = StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  return AppStateNotifier(ref);
});

class AppStateNotifier extends StateNotifier<AppState> {
  AppStateNotifier(this.ref) : super(AppState(store: ref.read(storeProvider)));

  final Ref ref;

  Future<void> load() async {
    await state.store.load();
    await ref.read(engineProvider).loadSeedData();
    await runAnalysis();
  }

  Future<void> runAnalysis() async {
    state = state.copyWith(analyzing: true);
    final engine = ref.read(engineProvider);
    final result = await engine.run();
    state.store.upsertTransactions(result.transactions);
    for (final c in result.contracts) {
      final existing = state.store.contracts.where((e) == e.name == c.name && e.status != ContractStatus.ignoriert).toList();
      if (existing.isEmpty) state.store.upsertContract(c);
    }
    for (final i in result.insights) {
      final dup = state.store.insights.any((e) == !e.dismissed && e.title == i.title);
      if (!dup) state.store.upsertInsight(i);
    }
    state = state.copyWith(result: result, analyzing: false);
  }
}
