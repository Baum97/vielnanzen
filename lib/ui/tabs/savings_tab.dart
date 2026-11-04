import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';

class SavingsTab extends ConsumerWidget {
  const SavingsTab({super.key});

  IconData _insightIcon(InsightType t) => switch (t) {
        InsightType.preiserhoehung => Icons.trending_up,
        InsightType.doppelteDienst => Icons.content_copy,
        InsightType.bankgebuehren => Icons.account_balance,
        InsightType.doppelteAbbuchung => Icons.repeat_on,
        InsightType.trotzKuendigung => Icons.warning_amber_outlined,
        InsightType.verguenstigeresAngebot => Icons.local_offer_outlined,
        InsightType.hoehererGiroSaldo => Icons.savings_outlined,
        InsightType.kategorieAuffaellig => Icons.category_outlined,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final store = app.store;
    final theme = Theme.of(context);
    final discreet = store.settings['discreetMode'] == true;
    final open = store.insights.where((i) => !i.dismissed).toList()
      ..sort((a, b) => (b.potentialCentsPerYear ?? 0).compareTo(a.potentialCentsPerYear ?? 0));
    final potential = open.fold<int>(0, (a, i) => a + (i.potentialCentsPerYear ?? 0));

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(title: const Text('Sparen'), floating: true),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('übriges Sparpotenzial', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary)),
              AmountText(potential, style: theme.textTheme.displayLarge?.copyWith(fontSize: 32), discreet: discreet),
              Text('im Jahr – alles aus deinen eigenen Daten berechnet', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary)),
              const SizedBox(height: 16),
              if (open.isEmpty)
                const AppCard(child: EmptyState(icon: Icons.savings_outlined, text: 'Keine offenen Spar-Chancen. Alles im Blick!'))
              else
                for (final i in open)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Dismissible(
                      key: ValueKey(i.id),
                      background: Container(
                        color: AppColors.positive.withValues(alpha: 0.2),
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 16),
                        child: const Text('Erledigt'),
                      ),
                      secondaryBackground: Container(
                        color: theme.colorScheme.secondary.withValues(alpha: 0.15),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        child: const Text('Ignorieren'),
                      ),
                      onDismissed: (_) => store.dismissInsight(i.id),
                      child: AppCard(
                        child: Row(children: [
                          Icon(_insightIcon(i.type), color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(i.title, style: theme.textTheme.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                              Text(i.detail, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                            ]),
                          ),
                          if (i.potentialCentsPerYear != null) ...[
                            const SizedBox(width: 8),
                            Text('≈ ${AmountFormat.format((i.potentialCentsPerYear! / 12).round(), discreet: discreet)}/Monat', style: theme.textTheme.bodySmall),
                          ],
                        ]),
                      ),
                    ),
                  ),
              const SizedBox(height: 8),
              AppCard(
                title: 'Budgets',
                child: store.budgets.isEmpty
                    ? const Text('Noch keine Budgets festgelegt.')
                    : Column(children: [
                        for (final b in store.budgets)
                          Builder(builder: (context) {
                            final engine = ref.read(engineProvider);
                            final cat = engine.categoryById(b.categoryId);
                            final now = DateTime.now();
                            final spent = store.transactions
                                .where((t) => t.categoryId == b.categoryId && t.amountCents < 0 && !t.excluded && t.bookingDate.year == now.year && t.bookingDate.month == now.month)
                                .fold<int>(0, (a, t) => a + t.amountCents.abs());
                            final frac = b.monthlyCents > 0 ? (spent / b.monthlyCents).clamp(0.0, 1.0) : 0.0;
                            final color = frac >= 1.0 ? AppColors.critical : frac >= 0.8 ? AppColors.warning : AppColors.positive;
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: parseHexColor(cat?.color ?? '#9A9EA5').withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.category_outlined, size: 20),
                              ),
                              title: Text(cat?.name ?? b.categoryId),
                              subtitle: LinearProgressIndicator(value: frac, color: color, backgroundColor: color.withValues(alpha: 0.15)),
                              trailing: Text(
                                '${AmountFormat.format(spent, discreet: discreet)} von ${AmountFormat.format(b.monthlyCents, discreet: discreet)}',
                                style: theme.textTheme.bodySmall,
                              ),
                            );
                          }),
                      ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
