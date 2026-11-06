import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics.dart';
import '../../state/app_state.dart';
import '../../state/nav.dart';
import '../charts.dart';
import '../screens/category_detail.dart';
import '../screens/merchant_detail.dart';
import '../screens/transaction_detail.dart';
import '../theme.dart';
import '../widgets.dart';

/// Ausgaben: Wofür (Kategorien), Wo (Firmen), Wann (zeitliche Muster) – im gewählten Zeitraum.
class SpendingTab extends ConsumerWidget {
  const SpendingTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(currentPeriodProvider);
    final view = ref.watch(spendingViewProvider);
    final theme = Theme.of(context);
    final discreet = ref.watch(discreetProvider);

    return Scaffold(
      body: CustomScrollView(slivers: [
        const SliverAppBar(title: Text('Ausgaben'), floating: true),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          sliver: SliverList.list(children: [
            const RangeSelector(),
            const SizedBox(height: 16),
            Text(p.range.label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary)),
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, children: [
              AmountText(p.summary.expenseCents, style: theme.textTheme.displaySmall),
              DeltaChip(p.expenseChangePct, suffix: ' ggü. Vorperiode'),
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 14, runSpacing: 4, children: [
              _kv(theme, 'Ø pro Tag', AmountFormat.format(p.summary.avgPerDayCents, discreet: discreet)),
              _kv(theme, 'Ø pro Monat', AmountFormat.format(p.summary.avgPerMonthCents, discreet: discreet, round: true)),
              _kv(theme, 'Buchungen', '${p.summary.expenseCount}'),
              _kv(theme, 'davon fix', AmountFormat.format(p.summary.fixedCents, discreet: discreet, round: true)),
            ]),
            const SizedBox(height: 16),
            SegmentedButton<SpendingView>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: SpendingView.categories, label: Text('Wofür'), icon: Icon(Icons.donut_small_outlined)),
                ButtonSegment(value: SpendingView.merchants, label: Text('Wo'), icon: Icon(Icons.storefront_outlined)),
                ButtonSegment(value: SpendingView.time, label: Text('Wann'), icon: Icon(Icons.calendar_month_outlined)),
              ],
              selected: {view},
              onSelectionChanged: (s) => ref.read(spendingViewProvider.notifier).set(s.first),
            ),
            const SizedBox(height: 12),
            if (p.expenses.isEmpty)
              const AppCard(child: EmptyState(icon: Icons.receipt_long_outlined, text: 'Keine Ausgaben in diesem Zeitraum.'))
            else
              switch (view) {
                SpendingView.categories => _CategoriesView(p: p),
                SpendingView.merchants => _MerchantsView(p: p),
                SpendingView.time => _TimeView(p: p),
              },
          ]),
        ),
      ]),
    );
  }

  static Widget _kv(ThemeData theme, String k, String v) => Text.rich(TextSpan(children: [
        TextSpan(text: '$k ', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary)),
        TextSpan(text: v, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
      ]));
}

class _CategoriesView extends ConsumerWidget {
  final PeriodAnalysis p;
  const _CategoriesView({required this.p});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final engine = ref.read(engineProvider);
    final segments = [for (final c in p.categories) (c.name, c.cents, parseHexColor(c.color))];
    return Column(children: [
      AppCard(
        child: LayoutBuilder(builder: (context, c) {
          final donut = DonutChart(segments: segments, size: c.maxWidth < 360 ? 140 : 170);
          final legend = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final s in DonutChart.condense(segments))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: s.$3, borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.$1, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text(AmountFormat.percent(p.summary.expenseCents > 0 ? s.$2 / p.summary.expenseCents : 0),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary)),
                ]),
              ),
          ]);
          return Row(children: [donut, const SizedBox(width: 16), Expanded(child: legend)]);
        }),
      ),
      const SizedBox(height: 12),
      AppCard(
        title: 'Nach Kategorie',
        subtitle: 'Antippen für Details und Unterkategorien',
        child: Column(children: [
          for (final c in p.categories)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CategoryDetailScreen(categoryId: c.categoryId))),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Avatar(icon: categoryIcon(engine.categoryById(c.categoryId)?.icon), color: parseHexColor(c.color), size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(c.name, style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
                        AmountText(c.cents, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 5),
                      ShareBar(share: c.share, color: parseHexColor(c.color)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Expanded(
                          child: Text('${AmountFormat.percent(c.share)} · ${c.count} Buchungen',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.secondary)),
                        ),
                        DeltaChip(c.changePct),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ),
        ]),
      ),
      if (p.incomeCategories.isNotEmpty) ...[
        const SizedBox(height: 12),
        AppCard(
          title: 'Einnahmen nach Quelle',
          child: Column(children: [
            for (final c in p.incomeCategories)
              for (final s in c.children)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Avatar(icon: categoryIcon(engine.categoryById(s.categoryId)?.icon), color: parseHexColor(s.color), size: 34),
                  title: Text(s.name),
                  subtitle: Text('${s.count} Eingänge'),
                  trailing: AmountText(s.cents, signed: true, style: theme.textTheme.bodyMedium),
                ),
          ]),
        ),
      ],
    ]);
  }
}

class _MerchantsView extends ConsumerStatefulWidget {
  final PeriodAnalysis p;
  const _MerchantsView({required this.p});

  @override
  ConsumerState<_MerchantsView> createState() => _MerchantsViewState();
}

enum _MerchantSort { amount, count, change }

class _MerchantsViewState extends ConsumerState<_MerchantsView> {
  _MerchantSort _sort = _MerchantSort.amount;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final engine = ref.read(engineProvider);
    final discreet = ref.watch(discreetProvider);
    final list = [...widget.p.merchants];
    switch (_sort) {
      case _MerchantSort.amount:
        break;
      case _MerchantSort.count:
        list.sort((a, b) => b.count.compareTo(a.count));
      case _MerchantSort.change:
        list.sort((a, b) => (b.cents - b.previousCents).compareTo(a.cents - a.previousCents));
    }
    final shown = _all ? list : list.take(25).toList();
    final top3 = widget.p.merchants.take(3).fold<int>(0, (a, m) => a + m.cents);
    final top3Share = widget.p.summary.expenseCents > 0 ? top3 / widget.p.summary.expenseCents : 0.0;

    return AppCard(
      title: '${list.length} Firmen',
      subtitle: 'Top 3 = ${AmountFormat.percent(top3Share)} deiner Ausgaben',
      trailing: PopupMenuButton<_MerchantSort>(
        icon: const Icon(Icons.sort),
        tooltip: 'Sortieren',
        initialValue: _sort,
        onSelected: (s) => setState(() => _sort = s),
        itemBuilder: (_) => const [
          PopupMenuItem(value: _MerchantSort.amount, child: Text('Nach Betrag')),
          PopupMenuItem(value: _MerchantSort.count, child: Text('Nach Häufigkeit')),
          PopupMenuItem(value: _MerchantSort.change, child: Text('Größter Anstieg')),
        ],
      ),
      child: Column(children: [
        for (final m in shown)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MerchantDetailScreen(stat: m))),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Avatar(label: m.name, color: parseHexColor(engine.categoryById(m.categoryId)?.color, fallback: theme.colorScheme.primary)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(m.name, style: theme.textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (m.recurring)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(Icons.autorenew, size: 14, color: theme.colorScheme.primary),
                        ),
                      AmountText(m.cents, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 4),
                    ShareBar(share: m.share, color: theme.colorScheme.primary, height: 5),
                    const SizedBox(height: 3),
                    Row(children: [
                      Expanded(
                        child: Text(
                          '${m.count}× · Ø ${AmountFormat.format(m.avgCents, discreet: discreet)} · ${engine.categoryById(m.categoryId)?.name ?? 'Unkategorisiert'}',
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.secondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DeltaChip(m.changePct),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        if (!_all && list.length > shown.length)
          TextButton(onPressed: () => setState(() => _all = true), child: Text('Alle ${list.length} anzeigen')),
      ]),
    );
  }
}

class _TimeView extends ConsumerWidget {
  final PeriodAnalysis p;
  const _TimeView({required this.p});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final engine = ref.read(engineProvider);
    final analytics = ref.read(analyticsProvider);
    const days = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final maxDay = p.weekdayCents.indexOf(p.weekdayCents.reduce((a, b) => a > b ? a : b));
    const dayNames = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
    final phaseTotal = p.monthPhaseCents.fold<int>(0, (a, b) => a + b);
    return Column(children: [
      AppCard(
        title: 'Ausgaben im Verlauf',
        subtitle: switch (p.bucket.name) { 'day' => 'pro Tag', 'week' => 'pro Woche', 'month' => 'pro Monat', 'quarter' => 'pro Quartal', _ => 'pro Jahr' },
        child: CashflowChart(buckets: p.cashflow, bucket: p.bucket, showIncome: false),
      ),
      const SizedBox(height: 12),
      AppCard(
        title: 'Nach Wochentag',
        subtitle: 'Am meisten am ${dayNames[maxDay]}',
        child: LabeledBars(bars: [for (var i = 0; i < 7; i++) (days[i], p.weekdayCents[i])]),
      ),
      const SizedBox(height: 12),
      AppCard(
        title: 'Im Monatsverlauf',
        subtitle: 'Wann im Monat das Geld abfließt',
        child: Column(children: [
          for (final (i, label) in const ['Anfang (1.–10.)', 'Mitte (11.–20.)', 'Ende (21.–31.)'].indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                SizedBox(width: 120, child: Text(label, style: theme.textTheme.bodySmall)),
                Expanded(child: ShareBar(share: phaseTotal > 0 ? p.monthPhaseCents[i] / phaseTotal : 0, color: theme.colorScheme.primary)),
                const SizedBox(width: 10),
                SizedBox(width: 80, child: Align(alignment: Alignment.centerRight, child: AmountText(p.monthPhaseCents[i], style: theme.textTheme.bodySmall, round: true))),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      AppCard(
        title: 'Größte Einzelausgaben',
        child: Column(children: [
          for (final t in p.largest)
            TransactionRow(
              t: t,
              title: analytics.merchantDisplay(t),
              category: engine.categoryById(t.categoryId),
              showDate: true,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TransactionDetailScreen(transactionId: t.id))),
            ),
        ]),
      ),
    ]);
  }
}
