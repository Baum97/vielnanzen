import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import '../screens/transaction_detail.dart';

class TransactionsTab extends ConsumerStatefulWidget {
  const TransactionsTab({super.key});

  @override
  ConsumerState<TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends ConsumerState<TransactionsTab> {
  final _search = TextEditingController();
  String? _categoryFilter;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final store = app.store;
    final engine = ref.read(engineProvider);
    final discreet = store.settings['discreetMode'] == true;
    var txs = app.result?.transactions ?? store.transactions;

    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      txs = txs.where((t) =>
          t.counterpartyName.toLowerCase().contains(q) ||
          t.purpose.toLowerCase().contains(q) ||
          (t.counterpartyIban?.toLowerCase().contains(q) ?? false) ||
          (t.note?.toLowerCase().contains(q) ?? false)).toList();
    }
    if (_categoryFilter != null) txs = txs.where((t) => t.categoryId == _categoryFilter).toList();
    txs = [...txs]..sort((a, b) => b.bookingDate.compareTo(a.bookingDate));

    final byDay = <DateTime, List<Transaction>>{};
    for (final t in txs) {
      byDay.putIfAbsent(DateTime(t.bookingDate.year, t.bookingDate.month, t.bookingDate.day), () => []).add(t);
    }
    final days = byDay.entries.toList()..sort((a, b) => b.key.compareTo(a.key));

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          title: const Text('Umsätze'),
          floating: true,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(110),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(children: [
                TextField(
                  controller: _search,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Suche…', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final c in engine.categories.where((c) => c.kind == CategoryKind.ausgabe && c.parentId == null))
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(c.name),
                            selected: _categoryFilter == c.id,
                            onSelected: (_) => setState(() => _categoryFilter = _categoryFilter == c.id ? null : c.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
        if (days.isEmpty)
          const SliverFillRemaining(child: EmptyState(icon: Icons.receipt_long_outlined, text: 'Noch keine Umsätze.'))
        else
          for (final day in days)
            SliverMainAxisGroup(slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(AmountFormat.date.format(day.key), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.secondary)),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final t = day.value[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TransactionRow(
                        t: t,
                        category: engine.categoryById(t.categoryId),
                        accountName: store.accounts.where((a) => a.id == t.accountId).map((a) => a.name).firstOrNull ?? '',
                        discreet: discreet,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TransactionDetailScreen(transactionId: t.id))),
                      ),
                    );
                  },
                  childCount: day.value.length,
                ),
              ),
            ]),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ]),
    );
  }
}
