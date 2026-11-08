import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tabs der App.
enum AppTab { home, spending, transactions, contracts, savings }

final tabProvider = NotifierProvider<TabNotifier, AppTab>(TabNotifier.new);

class TabNotifier extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.home;
  void go(AppTab t) => state = t;
}

enum TxKind { all, expenses, income }

/// Filter der Umsatzliste (auch von anderen Tabs aus gesetzt).
class TxFilter {
  final String query;
  final TxKind kind;
  final String? categoryId;
  final String? merchantKey;
  final String? merchantName;
  final bool onlyRange;

  const TxFilter({this.query = '', this.kind = TxKind.all, this.categoryId, this.merchantKey, this.merchantName, this.onlyRange = false});

  bool get isEmpty => query.isEmpty && kind == TxKind.all && categoryId == null && merchantKey == null && !onlyRange;

  TxFilter copyWith({String? query, TxKind? kind, String? categoryId, bool clearCategory = false, bool clearMerchant = false, bool? onlyRange}) =>
      TxFilter(
        query: query ?? this.query,
        kind: kind ?? this.kind,
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        merchantKey: clearMerchant ? null : merchantKey,
        merchantName: clearMerchant ? null : merchantName,
        onlyRange: onlyRange ?? this.onlyRange,
      );
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
