import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/nav.dart';
import 'tabs/contracts_tab.dart';
import 'tabs/home_tab.dart';
import 'tabs/savings_tab.dart';
import 'tabs/spending_tab.dart';
import 'tabs/transactions_tab.dart';

/// Haupt-Navigation: 5 Tabs (Material-Empfehlung für Bottom-Navigation).
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _tabs = [
    (AppTab.home, 'Übersicht', Icons.space_dashboard_outlined, Icons.space_dashboard),
    (AppTab.spending, 'Ausgaben', Icons.donut_large_outlined, Icons.donut_large),
    (AppTab.transactions, 'Umsätze', Icons.receipt_long_outlined, Icons.receipt_long),
    (AppTab.contracts, 'Abos', Icons.autorenew_outlined, Icons.autorenew),
    (AppTab.savings, 'Sparen', Icons.savings_outlined, Icons.savings),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabProvider);
    final index = _tabs.indexWhere((t) => t.$1 == tab);
    return PopScope(
      canPop: tab == AppTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(tabProvider.notifier).go(AppTab.home);
      },
      child: Scaffold(
        body: IndexedStack(
          index: index,
          children: const [HomeTab(), SpendingTab(), TransactionsTab(), ContractsTab(), SavingsTab()],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => ref.read(tabProvider.notifier).go(_tabs[i].$1),
          destinations: [
            for (final t in _tabs) NavigationDestination(icon: Icon(t.$3), selectedIcon: Icon(t.$4), label: t.$2),
          ],
        ),
      ),
    );
  }
}
