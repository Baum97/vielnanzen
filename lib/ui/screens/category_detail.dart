import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../charts.dart';
import '../theme.dart';
import '../widgets.dart';
import 'merchant_detail.dart';
import 'transaction_detail.dart';

/// Kategorie im gewählten Zeitraum: Unterkategorien, Firmen, Monatsverlauf, Umsätze, Budget.
class CategoryDetailScreen extends ConsumerWidget {
  final String categoryId;
  const CategoryDetailScreen({super.key, required this.categoryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(currentPeriodProvider);
    final analytics = ref.watch(analyticsProvider);
    final engine = ref.read(engineProvider);
    final store = ref.read(storeProvider);
    final theme = Theme.of(context);
    final cat = engine.categoryById(categoryId);
    final color = parseHexColor(cat?.color);

    bool inCat(Transaction t) => t.categoryId == categoryId || analytics.topCategory(t.categoryId)?.id == categoryId;
    final stat = p.categories.where((c) => c.categoryId == categoryId).firstOrNull;
    final txs = p.expenses.where(inCat).toList();
    final merchants = analytics.merchantStats(txs, const []);
    final monthly = analytics.monthlyFor(inCat);
    final avg = analytics.averageMonthly(inCat, months: 6);
    final budget = store.budgets.where((b) => b.categoryId == categoryId).firstOrNull;
    final thisMonth = analytics.currentMonth(inCat);

    return Scaffold(
      appBar: AppBar(title: Text(cat?.name ?? 'Kategorie')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Text(p.range.label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary)),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, children: [
          AmountText(stat?.cents ?? 0, style: theme.textTheme.displaySmall),
          DeltaChip(stat?.changePct, suffix: ' ggü. Vorperiode'),
        ]),
        Text('${AmountFormat.percent(stat?.share ?? 0)} deiner Ausgaben · Ø ${AmountFormat.format(avg, round: true)} pro Monat',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary)),
        const SizedBox(height: 16),
        AppCard(title: 'Letzte 12 Monate', child: MiniBars(values: monthly, color: color, height: 64)),
        const SizedBox(height: 12),
        AppCard(
          title: 'Budget',
          subtitle: budget == null ? 'Lege eine monatliche Obergrenze fest' : 'Diesen Monat',
          trailing: TextButton(
            onPressed: () => editBudget(context, ref, categoryId, suggestion: avg),
            child: Text(budget == null ? 'Festlegen' : 'Ändern'),
          ),
          child: budget == null
              ? Text('Vorschlag aus deinen Daten: ${AmountFormat.format((avg * 0.9).round(), round: true)} (10 % unter deinem Schnitt).',
                  style: theme.textTheme.bodySmall)
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ShareBar(
                    share: budget.monthlyCents > 0 ? thisMonth / budget.monthlyCents : 0,
                    color: thisMonth > budget.monthlyCents ? AppColors.neg(context) : (thisMonth > budget.monthlyCents * 0.8 ? AppColors.warn(context) : AppColors.pos(context)),
                    height: 8,
                  ),
                  const SizedBox(height: 6),
                  Text('${AmountFormat.format(thisMonth)} von ${AmountFormat.format(budget.monthlyCents)}', style: theme.textTheme.bodySmall),
                ]),
        ),
        if (stat != null && stat.children.length > 1) ...[
          const SizedBox(height: 12),
          AppCard(
            title: 'Unterkategorien',
            child: Column(children: [
              for (final s in stat.children)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(flex: 3, child: Text(s.name, style: theme.textTheme.bodyMedium)),
                    Expanded(flex: 2, child: ShareBar(share: s.share, color: parseHexColor(s.color))),
                    const SizedBox(width: 10),
                    AmountText(s.cents, style: theme.textTheme.bodyMedium, round: true),
                  ]),
                ),
            ]),
          ),
        ],
        if (merchants.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppCard(
            title: 'Firmen',
            child: Column(children: [
              for (final m in merchants.take(10))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Avatar(label: m.name, color: color, size: 34),
                  title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${m.count}× · ${AmountFormat.percent(m.share)}'),
                  trailing: AmountText(m.cents, style: theme.textTheme.bodyMedium),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MerchantDetailScreen(stat: m))),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        AppCard(
          title: 'Umsätze (${txs.length})',
          child: Column(children: [
            for (final t in txs.take(100))
              TransactionRow(
                t: t,
                title: analytics.merchantDisplay(t),
                category: engine.categoryById(t.categoryId),
                showDate: true,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TransactionDetailScreen(transactionId: t.id))),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Budget anlegen/ändern/entfernen.
Future<void> editBudget(BuildContext context, WidgetRef ref, String categoryId, {int suggestion = 0}) async {
  final store = ref.read(storeProvider);
  final existing = store.budgets.where((b) => b.categoryId == categoryId).firstOrNull;
  final ctrl = TextEditingController(
    text: ((existing?.monthlyCents ?? (suggestion * 0.9).round()) / 100).toStringAsFixed(0),
  );
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Monatsbudget'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Betrag pro Monat', suffixText: '€'),
      ),
      actions: [
        if (existing != null) TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('Entfernen')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Speichern')),
      ],
    ),
  );
  if (result == null) return;
  if (result == 'delete') {
    store.removeBudget(existing!.id);
    return;
  }
  final euros = double.tryParse(result.replaceAll('.', '').replaceAll(',', '.'));
  if (euros == null || euros <= 0) return;
  store.upsertBudget(Budget(id: existing?.id ?? 'b_$categoryId', categoryId: categoryId, monthlyCents: (euros * 100).round()));
}
