import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics/tx_filter.dart';

export '../core/analytics/tx_filter.dart' show TxFilter, TxKind;

/// Tabs der App.
enum AppTab { home, spending, transactions, contracts, savings }

final tabProvider = NotifierProvider<TabNotifier, AppTab>(TabNotifier.new);

class TabNotifier extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.home;
  void go(AppTab t) => state = t;
}

final txFilterProvider = NotifierProvider<TxFilterNotifier, TxFilter>(TxFilterNotifier.new);

class TxFilterNotifier extends Notifier<TxFilter> {
  @override
  TxFilter build() => const TxFilter();
  void set(TxFilter f) => state = f;
  void reset() => state = const TxFilter();
}

/// Ansicht im Ausgaben-Tab: Wofür (Kategorien), Wo (Firmen), Wann (Zeit).
enum SpendingView { categories, merchants, time }

final spendingViewProvider = NotifierProvider<SpendingViewNotifier, SpendingView>(SpendingViewNotifier.new);

class SpendingViewNotifier extends Notifier<SpendingView> {
  @override
  SpendingView build() => SpendingView.categories;
  void set(SpendingView v) => state = v;
}
