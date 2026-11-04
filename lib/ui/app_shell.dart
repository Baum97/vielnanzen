import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tabs/home_tab.dart';
import 'tabs/overview_tab.dart';
import 'tabs/transactions_tab.dart';
import 'tabs/analysis_tab.dart';
import 'tabs/contracts_tab.dart';
import 'tabs/savings_tab.dart';
import 'screens/settings_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  static const _tabs = [
    ('Übersicht', Icons.home_outlined, Icons.home),
    ('Überblick', Icons.bar_chart_outlined, Icons.bar_chart),
    ('Umsätze', Icons.list_alt_outlined, Icons.list_alt),
    ('Analyse', Icons.pie_chart_outline, Icons.pie_chart),
    ('Verträge', Icons.repeat_outlined, Icons.repeat),
    ('Sparen', Icons.savings_outlined, Icons.savings),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeTab(onOpenSettings: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
      const OverviewTab(),
      const TransactionsTab(),
      const AnalysisTab(),
      const ContractsTab(),
      const SavingsTab(),
    ];
    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(icon: Icon(t.$2), selectedIcon: Icon(t.$3), label: t.$1),
        ],
      ),
    );
  }
}
