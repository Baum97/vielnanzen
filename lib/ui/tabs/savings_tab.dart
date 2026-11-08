import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/time_range.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../screens/category_detail.dart';
import '../screens/contract_screens.dart';
import '../theme.dart';
import '../widgets.dart';

/// Sparen: konkretes Sparpotenzial aus den eigenen Daten, größte Hebel und Budgets.
class SavingsTab extends ConsumerWidget {
  const SavingsTab({super.key});

  static IconData insightIcon(InsightType t) => switch (t) {
        InsightType.preiserhoehung => Icons.trending_up,
        InsightType.doppelteDienst => Icons.copy_all_outlined,
        InsightType.bankgebuehren => Icons.account_balance_outlined,
        InsightType.doppelteAbbuchung => Icons.repeat_on_outlined,
        InsightType.trotzKuendigung => Icons.warning_amber_outlined,
        InsightType.verguenstigeresAngebot => Icons.local_offer_outlined,
        InsightType.hoehererGiroSaldo => Icons.savings_outlined,
        InsightType.kategorieAuffaellig => Icons.insights_outlined,
        InsightType.aboKosten => Icons.subscriptions_outlined,
        InsightType.kleinvieh => Icons.local_cafe_outlined,
        InsightType.lieferdienst => Icons.delivery_dining_outlined,
        InsightType.versicherungCheck => Icons.shield_outlined,
        InsightType.energieCheck => Icons.bolt_outlined,
        InsightType.ungenutztesAbo => Icons.hourglass_empty,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appStateProvider.select((s) => s.revision));
    final store = ref.read(storeProvider);
    final engine = ref.read(engineProvider);
    final analytics = ref.read(analyticsProvider);
    final theme = Theme.of(context);
    final open = store.insights.where((i) => !i.dismissed).toList()
      ..sort((a, b) => (b.potentialCentsPerYear ?? 0).compareTo(a.potentialCentsPerYear ?? 0));
    final dismissedCount = store.insights.where((i) => i.dismissed).length;
    final potential = open.fold<int>(0, (a, i) => a + (i.potentialCentsPerYear ?? 0));

    // Größte variable Ausgabenbereiche (ohne Fixkosten) der letzten 3 Monate
    final quarter = ref.watch(periodProvider(TimeRange.m3));
    final variable = quarter.categories
        .where((c) => !const {'wohnen', 'versicherungen', 'steuern', 'gebuehren'}.contains(c.categoryId))
        .take(4)
        .toList();
    final now = DateTime.now();

    return Scaffold(
      body: CustomScrollView(slivers: [
        const SliverAppBar(title: Text('Sparen'), floating: true),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          sliver: SliverList.list(children: [
            Text('Sparpotenzial', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AmountText(potential, style: theme.textTheme.displaySmall?.copyWith(color: AppColors.pos(context)), round: true),
            ),
            Text(
              'pro Jahr · ≈ ${AmountFormat.format((potential / 12).round(), discreet: ref.watch(discreetProvider), round: true)} im Monat – aus deinen eigenen Umsätzen berechnet',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary),
            ),
            const SizedBox(height: 16),
            if (open.isEmpty)
              const AppCard(child: EmptyState(icon: Icons.savings_outlined, text: 'Keine offenen Spar-Hinweise. Alles im Blick!'))
            else
              for (final i in open) ...[
                _InsightCard(insight: i),
                const SizedBox(height: 10),
              ],
            if (dismissedCount > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: store.restoreInsights,
                  icon: const Icon(Icons.restore),
                  label: Text('$dismissedCount ausgeblendete Hinweise wieder anzeigen'),
                ),
              ),
            if (variable.isNotEmpty) ...[
              const SectionTitle('Deine größten Hebel'),
              AppCard(
                subtitle: 'Variable Ausgaben der letzten 3 Monate – hier lässt sich am leichtesten sparen',
                child: Column(children: [
                  for (final c in variable)
                    Builder(builder: (context) {
                      final monthly = (c.cents / 3).round();
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Avatar(icon: categoryIcon(engine.categoryById(c.categoryId)?.icon), color: parseHexColor(c.color), size: 36),
                        title: Text(c.name),
                        subtitle: Text('Ø ${AmountFormat.format(monthly, round: true)}/Monat · 10 % weniger = ${AmountFormat.format((monthly * 0.1 * 12).round(), round: true)}/Jahr'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CategoryDetailScreen(categoryId: c.categoryId))),
                      );
                    }),
                ]),
              ),
            ],
            SectionTitle(
              'Budgets',
              trailing: TextButton.icon(
                onPressed: () => _addBudget(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Neu'),
              ),
            ),
            AppCard(
              child: store.budgets.isEmpty
                  ? Text('Lege Monatsbudgets für Bereiche fest, in denen du sparen willst – z. B. Restaurants oder Shopping.',
                      style: theme.textTheme.bodySmall)
                  : Column(children: [
                      for (final b in store.budgets)
                        Builder(builder: (context) {
                          final cat = engine.categoryById(b.categoryId);
                          bool inCat(Transaction t) => t.categoryId == b.categoryId || analytics.topCategory(t.categoryId)?.id == b.categoryId;
                          final spent = analytics.currentMonth(inCat);
                          final frac = b.monthlyCents > 0 ? spent / b.monthlyCents : 0.0;
                          final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day;
                          final color = frac >= 1 ? AppColors.neg(context) : frac >= b.alertAtPercent / 100 ? AppColors.warn(context) : AppColors.pos(context);
                          return InkWell(
                            onTap: () => editBudget(context, ref, b.categoryId),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(children: [
                                Avatar(icon: categoryIcon(cat?.icon), color: parseHexColor(cat?.color), size: 36),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Row(children: [
                                      Expanded(child: Text(cat?.name ?? b.categoryId, style: theme.textTheme.bodyMedium)),
                                      Text('${AmountFormat.format(spent, round: true)} / ${AmountFormat.format(b.monthlyCents, round: true)}',
                                          style: theme.textTheme.bodySmall),
                                    ]),
                                    const SizedBox(height: 5),
                                    ShareBar(share: frac, color: color, height: 7),
                                    const SizedBox(height: 3),
                                    Text(
                                      frac >= 1
                                          ? 'Budget um ${AmountFormat.format(spent - b.monthlyCents, round: true)} überschritten'
                                          : 'Noch ${AmountFormat.format(b.monthlyCents - spent, round: true)} für $daysLeft Tage',
                                      style: theme.textTheme.labelSmall?.copyWith(color: color),
                                    ),
                                  ]),
                                ),
                              ]),
                            ),
                          );
                        }),
                    ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _addBudget(BuildContext context, WidgetRef ref) async {
    final engine = ref.read(engineProvider);
    final analytics = ref.read(analyticsProvider);
    final store = ref.read(storeProvider);
    final cats = engine.categories
        .where((c) => c.kind == CategoryKind.ausgabe && !store.budgets.any((b) => b.categoryId == c.id))
        .toList();
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, scroll) => ListView(controller: scroll, children: [
          for (final c in cats)
            ListTile(
              contentPadding: EdgeInsets.only(left: c.parentId == null ? 16 : 48, right: 16),
              leading: c.parentId == null ? Avatar(icon: categoryIcon(c.icon), color: parseHexColor(c.color), size: 30) : null,
              title: Text(c.name, style: TextStyle(fontWeight: c.parentId == null ? FontWeight.w600 : null)),
              onTap: () => Navigator.pop(ctx, c.id),
            ),
        ]),
      ),
    );
    if (picked == null || !context.mounted) return;
    final avg = analytics.averageMonthly((t) => t.categoryId == picked || analytics.topCategory(t.categoryId)?.id == picked);
    await editBudget(context, ref, picked, suggestion: avg);
  }
}

class _InsightCard extends ConsumerWidget {
  final Insight insight;
  const _InsightCard({required this.insight});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final store = ref.read(storeProvider);
    final i = insight;
    VoidCallback? action;
    if (i.contractId != null && store.contractById(i.contractId!) != null) {
      action = () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContractDetailScreen(contractId: i.contractId!)));
    } else if (i.categoryId != null) {
      action = () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CategoryDetailScreen(categoryId: i.categoryId!)));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Avatar(icon: SavingsTab.insightIcon(i.type), color: theme.colorScheme.primary, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(i.title, style: theme.textTheme.headlineMedium?.copyWith(fontSize: 15)),
                const SizedBox(height: 4),
                Text(i.detail, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary)),
              ]),
            ),
            const SizedBox(width: 8),
            if ((i.potentialCentsPerYear ?? 0) > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.pos(context).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Column(children: [
                  AmountText(i.potentialCentsPerYear!, round: true, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.pos(context), fontWeight: FontWeight.w700)),
                  Text(i.type == InsightType.doppelteAbbuchung ? 'einmalig' : '/Jahr',
                      style: theme.textTheme.labelSmall?.copyWith(color: AppColors.pos(context), fontSize: 10)),
                ]),
              ),
          ]),
          // OverflowBar bricht bei langen Aktionstexten in eine zweite Zeile um.
          OverflowBar(alignment: MainAxisAlignment.end, overflowAlignment: OverflowBarAlignment.end, children: [
            TextButton(onPressed: () => store.dismissInsight(i.id), child: const Text('Ausblenden')),
            if (action != null) TextButton(onPressed: action, child: Text(i.action ?? 'Ansehen')),
          ]),
        ]),
      ),
    );
  }
}
