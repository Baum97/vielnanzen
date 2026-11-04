import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import '../charts.dart';

class HomeTab extends ConsumerWidget {
  final VoidCallback? onOpenSettings;
  const HomeTab({super.key, this.onOpenSettings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final store = app.store;
    final theme = Theme.of(context);
    final discreet = store.settings['discreetMode'] == true;

    final visible = store.accounts.where((a) => a.includeInTotal && !a.hidden).toList();
    final total = visible.fold<int>(0, (a, acc) => a + acc.balanceCents);

    final txs = (app.result?.transactions ?? store.transactions).toList()
      ..sort((a, b) => b.bookingDate.compareTo(a.bookingDate));
    final upcoming = store.contracts.where((c) => c.status == ContractStatus.aktiv).toList()
      ..sort((a, b) => (a.nextDue ?? DateTime(2100)).compareTo(b.nextDue ?? DateTime(2100)));
    final monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final monthSpend = txs
        .where((t) => t.amountCents < 0 && !t.excluded && !t.isTransfer && !t.bookingDate.isBefore(monthStart))
        .fold<int>(0, (a, t) => a - t.amountCents);

    // Verlauf für Mini-Chart
    final points = <(DateTime, int)>[];
    var bal = total;
    for (var i = txs.length - 1; i >= 0; i--) {
      points.add((txs[i].bookingDate, bal));
      bal -= txs[i].amountCents;
    }
    if (points.isNotEmpty) points.add((DateTime.now(), total));

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          title: const Text('Klarblick'),
          floating: true,
          actions: [
            IconButton(icon: const Icon(Icons.settings_outlined), onPressed: onOpenSettings, tooltip: 'Einstellungen'),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Gesamtsaldo', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary)),
              AmountText(total, style: theme.textTheme.displayLarge?.copyWith(fontSize: 36), discreet: discreet),
              const SizedBox(height: 16),
              if (points.length >= 2) AppCard(title: 'Verlauf', child: LineChart(points: points)),
              const SizedBox(height: 12),
              AppCard(
                title: 'Diesen Monat ausgegeben',
                child: AmountText(-monthSpend, style: theme.textTheme.headlineMedium, discreet: discreet),
              ),
              const SizedBox(height: 12),
              AppCard(
                title: 'Konten',
                child: Column(children: [
                  for (final a in store.accounts)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: parseHexColor(a.color).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.account_balance, size: 20),
                      ),
                      title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(a.iban, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: AmountText(a.balanceCents, signed: true, discreet: discreet, style: theme.textTheme.bodyMedium),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              AppCard(
                title: 'Anstehende Verträge',
                child: upcoming.isEmpty
                    ? const Text('Keine aktiven Verträge erkannt.')
                    : Column(children: [
                        for (final c in upcoming.take(4))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(c.nextDue != null ? 'nächste Zahlung ${AmountFormat.date.format(c.nextDue!)}' : ''),
                            trailing: AmountText(-c.expectedCents, discreet: discreet),
                          ),
                      ]),
              ),
              const SizedBox(height: 12),
              AppCard(
                title: 'Letzte Umsätze',
                child: Column(children: [
                  for (final t in txs.take(5))
                    TransactionRow(
                      t: t,
                      category: ref.read(engineProvider).categoryById(t.categoryId),
                      accountName: store.accounts.where((a) => a.id == t.accountId).map((a) => a.name).firstOrNull ?? '',
                      discreet: discreet,
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
