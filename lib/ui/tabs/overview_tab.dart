import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/normalize.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Überblick: Ausgaben pro Firma (Händler) in wählbarer Zeitspanne.
enum OverviewRange { month, threeMonths, ytd, all }

class OverviewTab extends ConsumerStatefulWidget {
  const OverviewTab({super.key});

  @override
  ConsumerState<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends ConsumerState<OverviewTab> {
  OverviewRange _range = OverviewRange.month;

  /// Liefert (von, bis) für die gewählte Spanne. `bis` ist exklusiv-null bei "all".
  ({DateTime? from, DateTime? to, String label}) _bounds(OverviewRange r, DateTime now) {
    switch (r) {
      case OverviewRange.month:
        final from = DateTime(now.year, now.month, 1);
        final to = DateTime(now.year, now.month + 1, 1);
        return (from: from, to: to, label: 'Aktueller Monat');
      case OverviewRange.threeMonths:
        final from = DateTime(now.year, now.month - 2, 1);
        final to = DateTime(now.year, now.month + 1, 1);
        return (from: from, to: to, label: 'Letzte 3 Monate');
      case OverviewRange.ytd:
        final from = DateTime(now.year, 1, 1);
        final to = DateTime(now.year + 1, 1, 1);
        return (from: from, to: to, label: 'Year to Date ${now.year}');
      case OverviewRange.all:
        return (from: null, to: null, label: 'Insgesamt');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final store = app.store;
    final engine = ref.read(engineProvider);
    final theme = Theme.of(context);
    final discreet = store.settings['discreetMode'] == true;
    final now = DateTime.now();
    final b = _bounds(_range, now);

    final txs = app.result?.transactions ?? store.transactions;
    final spend = txs.where((t) {
      if (t.amountCents >= 0 || t.excluded || t.isTransfer) return false;
      if (b.from != null && t.bookingDate.isBefore(b.from!)) return false;
      if (b.to != null && !t.bookingDate.isBefore(b.to!)) return false;
      return true;
    }).toList();

    // Gruppieren nach Firma: merchantId -> displayName, sonst normalisierter Name
    final byMerchant = <String, ({String name, int cents, int count})>{};
    for (final t in spend) {
      final m = engine.merchantById(t.merchantId);
      final name = m?.displayName ?? (normalizeMerchantName(t.counterpartyName).isEmpty ? t.counterpartyName : normalizeMerchantName(t.counterpartyName));
      final key = m?.id ?? name.toLowerCase();
      final cur = byMerchant[key] ?? (name: name, cents: 0, count: 0);
      byMerchant[key] = (name: name, cents: cur.cents + t.amountCents.abs(), count: cur.count + 1);
    }
    final rows = byMerchant.entries.toList()..sort((a, b) => b.value.cents.compareTo(a.value.cents));
    final total = rows.fold<int>(0, (a, e) => a + e.value.cents);

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(title: const Text('Überblick'), floating: true),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Zeitraum-Auswahl
              SegmentedButton<OverviewRange>(
                segments: const [
                  ButtonSegment(value: OverviewRange.month, label: Text('Monat')),
                  ButtonSegment(value: OverviewRange.threeMonths, label: Text('3 Monate')),
                  ButtonSegment(value: OverviewRange.ytd, label: Text('YTD')),
                  ButtonSegment(value: OverviewRange.all, label: Text('Gesamt')),
                ],
                selected: {_range},
                onSelectionChanged: (s) => setState(() => _range = s.first),
              ),
              const SizedBox(height: 20),
              Text(b.label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary)),
              AmountText(-total, style: theme.textTheme.displayLarge?.copyWith(fontSize: 32), discreet: discreet),
              Text(
                '${rows.length} ${rows.length == 1 ? 'Firma' : 'Firmen'} · ${spend.length} Ausgaben im Zeitraum',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary),
              ),
              const SizedBox(height: 16),
              if (rows.isEmpty)
                const AppCard(child: EmptyState(icon: Icons.receipt_long_outlined, text: 'Keine Ausgaben in diesem Zeitraum.'))
              else
                AppCard(
                  title: 'Ausgaben pro Firma',
                  child: Column(children: [
                    for (final e in rows) _MerchantRow(
                      name: e.value.name,
                      cents: e.value.cents,
                      count: e.value.count,
                      share: total > 0 ? e.value.cents / total : 0,
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

class _MerchantRow extends StatelessWidget {
  final String name;
  final int cents;
  final int count;
  final double share;
  final bool discreet;

  const _MerchantRow({required this.name, required this.cents, required this.count, required this.share, required this.discreet});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final letters = name.replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '').trim();
    final initials = letters.isEmpty ? '?' : letters.split(RegExp(r'\s+')).map((p) => p[0]).take(2).join().toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Center(child: Text(initials, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: theme.textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 6,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          AmountText(-cents, style: theme.textTheme.bodyMedium, discreet: discreet),
          Text('$count× · ${(share * 100).toStringAsFixed(0)} %', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary)),
        ]),
      ]),
    );
  }
}
