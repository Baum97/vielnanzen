import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../charts.dart';
import '../theme.dart';
import '../widgets.dart';
import 'contract_screens.dart';
import 'transaction_detail.dart';

/// Firma/Händler: wie viel, wie oft, wann – über alle Zeit und im Zeitraum.
class MerchantDetailScreen extends ConsumerWidget {
  final MerchantStat stat;
  const MerchantDetailScreen({super.key, required this.stat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(analyticsProvider);
    final engine = ref.read(engineProvider);
    final store = ref.read(storeProvider);
    final theme = Theme.of(context);
    final p = ref.watch(currentPeriodProvider);

    bool isThis(Transaction t) => analytics.merchantKey(t) == stat.key;
    final all = store.transactions.where((t) => isThis(t) && analytics.isExpense(t)).toList()
      ..sort((a, b) => b.bookingDate.compareTo(a.bookingDate));
    final refunds = store.transactions.where((t) => isThis(t) && t.amountCents > 0).fold<int>(0, (a, t) => a + t.amountCents);
    final allTotal = all.fold<int>(0, (a, t) => a - t.amountCents);
    final monthly = analytics.monthlyFor(isThis);
    final yearAgo = DateTime.now().subtract(const Duration(days: 365));
    final last12 = all.where((t) => t.bookingDate.isAfter(yearAgo)).fold<int>(0, (a, t) => a - t.amountCents);
    final contracts = store.contracts.where((c) => all.any((t) => t.contractId == c.id)).toList();
    final color = parseHexColor(engine.categoryById(stat.categoryId)?.color, fallback: theme.colorScheme.primary);

    return Scaffold(
      appBar: AppBar(title: Text(stat.name, overflow: TextOverflow.ellipsis)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Row(children: [
          Avatar(label: stat.name, color: color, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.range.label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary)),
              AmountText(stat.cents, style: theme.textTheme.displaySmall),
              Text('${stat.count} Zahlungen · Ø ${AmountFormat.format(stat.avgCents)}', style: theme.textTheme.bodySmall),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: StatTile(label: 'Letzte 12 Monate', cents: last12)),
          const SizedBox(width: 8),
          Expanded(child: StatTile(label: 'Insgesamt', cents: allTotal)),
          const SizedBox(width: 8),
          Expanded(child: StatTile(label: 'Ø pro Monat', cents: (last12 / 12).round())),
        ]),
        const SizedBox(height: 12),
        AppCard(title: 'Monatsverlauf', subtitle: 'Letzte 12 Monate', child: MiniBars(values: monthly, color: color, height: 64)),
        if (contracts.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppCard(
            title: 'Vertrag / Abo',
            child: Column(children: [
              for (final c in contracts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.autorenew),
                  title: Text(c.name),
                  subtitle: Text('${intervalLabel(c.interval)} · ${AmountFormat.format(c.yearlyCents)} pro Jahr'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContractDetailScreen(contractId: c.id))),
                ),
            ]),
          ),
        ],
        if (refunds > 0) ...[
          const SizedBox(height: 12),
          InfoBanner(text: 'Erstattungen/Gutschriften von dieser Firma: ${AmountFormat.format(refunds)}', color: AppColors.pos(context), icon: Icons.undo),
        ],
        const SizedBox(height: 12),
        AppCard(
          title: 'Alle Zahlungen (${all.length})',
          child: Column(children: [
            for (final t in all.take(150))
              TransactionRow(
                t: t,
                title: t.purpose.isNotEmpty ? t.purpose : analytics.merchantDisplay(t),
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
