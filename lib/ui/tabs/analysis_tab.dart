import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Analyse: Ausgaben nach Kategorie im gewählten Monat + Abo-Übersicht.
class AnalysisTab extends ConsumerStatefulWidget {
  const AnalysisTab({super.key});

  @override
  ConsumerState<AnalysisTab> createState() => _AnalysisTabState();
}

class _AnalysisTabState extends ConsumerState<AnalysisTab> {
  int _monthOffset = 0;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final store = app.store;
    final engine = ref.read(engineProvider);
    final theme = Theme.of(context);
    final discreet = store.settings['discreetMode'] == true;
    final now = DateTime.now();
    final month = DateTime(now.year, now.month - _monthOffset, 1);
    final next = DateTime(month.year, month.month + 1, 1);

    final txs = (app.result?.transactions ?? store.transactions)
        .where((t) => t.amountCents < 0 && !t.excluded && !t.isTransfer && !t.bookingDate.isBefore(month) && t.bookingDate.isBefore(next))
        .toList();

    final byCat = <String, int>{};
    for (final t in txs) {
      final key = t.categoryId ?? 'sonstiges';
      byCat[key] = (byCat[key] ?? 0) + t.amountCents.abs();
    }
    final rows = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = rows.fold<int>(0, (a, e) => a + e.value);

    final monthlyContracts = store.contracts
        .where((c) => c.status == ContractStatus.aktiv || c.status == ContractStatus.gekuendigt)
        .fold<double>(0, (a, c) => a + c.monthlyCents);

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          title: const Text('Analyse'),
          floating: true,
          actions: [
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _monthOffset++)),
            IconButton(icon: const Icon(Icons.chevron_right), onPressed: _monthOffset == 0 ? null : () => setState(() => _monthOffset--)),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(AmountFormat.monthYear.format(month), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary)),
              AmountText(-total, style: theme.textTheme.displayLarge?.copyWith(fontSize: 32), discreet: discreet),
              Text('Ausgaben im Monat', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary)),
              const SizedBox(height: 16),
              AppCard(
                title: 'Nach Kategorie',
                child: rows.isEmpty
                    ? const Text('Keine Ausgaben in diesem Monat.')
                    : Column(children: [
                        for (final e in rows)
                          Builder(builder: (context) {
                            final cat = engine.categoryById(e.key);
                            final share = total > 0 ? e.value / total : 0;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: parseHexColor(cat?.color ?? '#9A9EA5').withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.category_outlined, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(cat?.name ?? 'Sonstiges', style: theme.textTheme.bodyMedium),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(value: share, minHeight: 5),
                                    ),
                                  ]),
                                ),
                                const SizedBox(width: 12),
                                AmountText(-e.value, style: theme.textTheme.bodyMedium, discreet: discreet),
                              ]),
                            );
                          }),
                      ]),
              ),
              const SizedBox(height: 12),
              AppCard(
                title: 'Monatliche Abos gesamt',
                child: AmountText(-monthlyContracts.round(), style: theme.textTheme.headlineMedium, discreet: discreet),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
