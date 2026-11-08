import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/nav.dart';
import '../screens/import_screen.dart';
import '../screens/transaction_detail.dart';
import '../theme.dart';
import '../widgets.dart';

class TransactionsTab extends ConsumerStatefulWidget {
  const TransactionsTab({super.key});

  @override
  ConsumerState<TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends ConsumerState<TransactionsTab> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appStateProvider.select((s) => s.revision));
    final store = ref.read(storeProvider);
    final engine = ref.read(engineProvider);
    final analytics = ref.watch(analyticsProvider);
    final filter = ref.watch(txFilterProvider);
    final range = ref.watch(rangeProvider);
    final theme = Theme.of(context);
    if (_search.text != filter.query) _search.text = filter.query;

    final accountNames = {for (final a in store.accounts) a.id: a.name};
    final now = DateTime.now();
    final from = range.start(now, earliest: analytics.earliest);
    final q = filter.query.trim().toLowerCase();

    final txs = store.transactions.where((t) {
      if (filter.onlyRange && t.bookingDate.isBefore(from)) return false;
      if (filter.kind == TxKind.expenses && t.amountCents >= 0) return false;
      if (filter.kind == TxKind.income && t.amountCents <= 0) return false;
      if (filter.categoryId != null && t.categoryId != filter.categoryId && analytics.topCategory(t.categoryId)?.id != filter.categoryId) {
        return false;
      }
      if (filter.merchantKey != null && analytics.merchantKey(t) != filter.merchantKey) return false;
      if (q.isNotEmpty) {
        final hay = '${t.counterpartyName} ${t.purpose} ${t.note ?? ''} ${t.counterpartyIban ?? ''} ${analytics.merchantDisplay(t)} '
                '${engine.categoryById(t.categoryId)?.name ?? ''} ${(t.amountCents.abs() / 100).toStringAsFixed(2).replaceAll('.', ',')}'
            .toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.bookingDate.compareTo(a.bookingDate));

    // Flache Liste: Tagesüberschriften + Zeilen (schnell auch bei Tausenden Umsätzen)
    final items = <Object>[];
    DateTime? currentDay;
    var daySum = 0;
    var headerIndex = -1;
    for (final t in txs) {
      final d = DateTime(t.bookingDate.year, t.bookingDate.month, t.bookingDate.day);
      if (d != currentDay) {
        if (headerIndex >= 0) items[headerIndex] = (currentDay!, daySum);
        currentDay = d;
        daySum = 0;
        headerIndex = items.length;
        items.add((d, 0));
      }
      if (!t.isTransfer && !t.excluded) daySum += t.amountCents;
      items.add(t);
    }
    if (headerIndex >= 0) items[headerIndex] = (currentDay!, daySum);

    final income = txs.where(analytics.isIncome).fold<int>(0, (a, t) => a + t.amountCents);
    final expense = txs.where(analytics.isExpense).fold<int>(0, (a, t) => a - t.amountCents);

    final topCats = engine.categories.where((c) => c.parentId == null && c.kind != CategoryKind.umbuchung).toList();

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          title: const Text('Umsätze'),
          floating: true,
          snap: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.file_upload_outlined),
              tooltip: 'Datei importieren',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportScreen())),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(108),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(children: [
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Firma, Zweck, Betrag …',
                    isDense: true,
                    suffixIcon: filter.query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => ref.read(txFilterProvider.notifier).set(filter.copyWith(query: '')),
                          ),
                  ),
                  onChanged: (v) => ref.read(txFilterProvider.notifier).set(filter.copyWith(query: v)),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    _chip('Alle', filter.kind == TxKind.all, () => ref.read(txFilterProvider.notifier).set(filter.copyWith(kind: TxKind.all))),
                    _chip('Ausgaben', filter.kind == TxKind.expenses,
                        () => ref.read(txFilterProvider.notifier).set(filter.copyWith(kind: TxKind.expenses))),
                    _chip('Einnahmen', filter.kind == TxKind.income,
                        () => ref.read(txFilterProvider.notifier).set(filter.copyWith(kind: TxKind.income))),
                    _chip(range.label, filter.onlyRange,
                        () => ref.read(txFilterProvider.notifier).set(filter.copyWith(onlyRange: !filter.onlyRange)),
                        icon: Icons.date_range),
                    if (filter.merchantName != null)
                      _chip(filter.merchantName!, true, () => ref.read(txFilterProvider.notifier).set(filter.copyWith(clearMerchant: true)),
                          icon: Icons.close),
                    for (final c in topCats)
                      _chip(c.name, filter.categoryId == c.id, () {
                        ref.read(txFilterProvider.notifier).set(filter.categoryId == c.id ? filter.copyWith(clearCategory: true) : filter.copyWith(categoryId: c.id));
                      }),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              '${txs.length} Umsätze · +${AmountFormat.format(income, discreet: ref.watch(discreetProvider), round: true)} / −${AmountFormat.format(expense, discreet: ref.watch(discreetProvider), round: true)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary),
            ),
          ),
        ),
        if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              text: filter.isEmpty ? 'Noch keine Umsätze.' : 'Keine Umsätze für diesen Filter.',
              buttonLabel: filter.isEmpty ? null : 'Filter zurücksetzen',
              onButton: () => ref.read(txFilterProvider.notifier).reset(),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
            sliver: SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                if (item is (DateTime, int)) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
                    child: Row(children: [
                      Expanded(
                        child: Text(AmountFormat.weekdayDate.format(item.$1),
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary, fontWeight: FontWeight.w600)),
                      ),
                      AmountText(item.$2, signed: true, colorize: false, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary)),
                    ]),
                  );
                }
                final t = item as Transaction;
                return TransactionRow(
                  t: t,
                  title: analytics.merchantDisplay(t),
                  category: engine.categoryById(t.categoryId),
                  accountName: store.accounts.length > 1 ? (accountNames[t.accountId] ?? '') : '',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TransactionDetailScreen(transactionId: t.id))),
                );
              },
            ),
          ),
      ]),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {IconData? icon}) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilterChip(
          label: Text(label),
          avatar: icon != null && !selected ? Icon(icon, size: 16) : null,
          selected: selected,
          onSelected: (_) => onTap(),
          visualDensity: VisualDensity.compact,
        ),
      );
}
