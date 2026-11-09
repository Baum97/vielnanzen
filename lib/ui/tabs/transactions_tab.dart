import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/tx_filter.dart';
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
  final _chipScroll = ScrollController();
  String _lastSelection = '';

  @override
  void dispose() {
    _search.dispose();
    _chipScroll.dispose();
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
    final ctx = TxFilterContext(
      categoryOf: engine.categoryById,
      merchantKey: analytics.merchantKey,
      merchantName: analytics.merchantDisplay,
      accountName: (id) => accountNames[id] ?? 'Konto',
      accountCount: store.accounts.length,
      rangeFrom: range.start(now, earliest: analytics.earliest),
      rangeLabel: range.label,
      searchText: (t) => '${t.counterpartyName} ${t.purpose} ${t.note ?? ''} ${t.counterpartyIban ?? ''} ${analytics.merchantDisplay(t)} '
              '${engine.categoryById(t.categoryId)?.name ?? ''} ${(t.amountCents.abs() / 100).toStringAsFixed(2).replaceAll('.', ',')}'
          .toLowerCase(),
    );
    final txs = filterTransactions(store.transactions, filter, ctx)..sort((a, b) => b.bookingDate.compareTo(a.bookingDate));

    // Filterleiste: Gewähltes vorn, danach nur noch sinnvolle Optionen.
    final bar = computeFilterBar(store.transactions, filter, ctx);
    final selection = bar.selected.map((c) => '${c.dim.name}:${c.id}').join('|');
    if (selection != _lastSelection) {
      _lastSelection = selection;
      // Die Leiste springt an den Anfang, damit das Gewählte und die nachrückenden Optionen sichtbar sind.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chipScroll.hasClients) _chipScroll.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      });
    }

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
                  child: SingleChildScrollView(
                    controller: _chipScroll,
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final c in bar.selected) _chip(c, filter, ctx),
                      if (bar.selected.isNotEmpty && bar.options.isNotEmpty)
                        const Padding(padding: EdgeInsets.only(right: 6), child: SizedBox(height: 20, child: VerticalDivider(width: 8, thickness: 1))),
                      for (final c in bar.options) _chip(c, filter, ctx),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
            child: Row(children: [
              Expanded(
                child: Text(
                  '${txs.length} Umsätze · +${AmountFormat.format(income, discreet: ref.watch(discreetProvider), round: true)} / −${AmountFormat.format(expense, discreet: ref.watch(discreetProvider), round: true)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary),
                ),
              ),
              if (!filter.isEmpty)
                TextButton(
                  onPressed: () => ref.read(txFilterProvider.notifier).reset(),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Zurücksetzen'),
                ),
            ]),
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

  Widget _chip(FilterChipSpec c, TxFilter filter, TxFilterContext ctx) => Padding(
        key: ValueKey('${c.dim.name}:${c.id}'),
        padding: const EdgeInsets.only(right: 6),
        child: FilterChip(
          label: Text(c.label),
          selected: c.selected,
          onSelected: (_) => ref.read(txFilterProvider.notifier).set(applyChip(filter, c, ctx)),
          visualDensity: VisualDensity.compact,
        ),
      );
}
