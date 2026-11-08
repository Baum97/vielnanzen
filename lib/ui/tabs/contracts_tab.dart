import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/time_range.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../screens/contract_screens.dart';
import '../theme.dart';
import '../widgets.dart';

/// Abos & Verträge: was regelmäßig abgeht, wann, und was es im Jahr kostet.
class ContractsTab extends ConsumerStatefulWidget {
  const ContractsTab({super.key});

  @override
  ConsumerState<ContractsTab> createState() => _ContractsTabState();
}

class _ContractsTabState extends ConsumerState<ContractsTab> {
  bool _perYear = false;
  bool _calendar = false;
  bool _showEnded = false;

  @override
  Widget build(BuildContext context) {
    ref.watch(appStateProvider.select((s) => s.revision));
    final store = ref.read(storeProvider);
    final engine = ref.read(engineProvider);
    final analytics = ref.read(analyticsProvider);
    final theme = Theme.of(context);

    final proposals = store.contracts.where((c) => c.status == ContractStatus.vorschlag).toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final active = store.contracts.where((c) => c.status == ContractStatus.aktiv).toList();
    final ended = store.contracts.where((c) => c.status == ContractStatus.gekuendigt || c.status == ContractStatus.beendet).toList();
    final monthly = active.fold<double>(0, (a, c) => a + c.monthlyCents).round();
    final year = ref.watch(periodProvider(TimeRange.y1)).summary;
    final incomeMonthly = year.days > 0 ? (year.incomeCents / year.days * 30.44).round() : 0;
    final share = incomeMonthly > 0 ? monthly / incomeMonthly : null;

    // Gruppiert nach Oberkategorie
    final groups = <String, List<Contract>>{};
    for (final c in active) {
      final top = analytics.topCategory(c.categoryId);
      groups.putIfAbsent(top?.name ?? 'Sonstiges', () => []).add(c);
    }
    final groupList = groups.entries.toList()
      ..sort((a, b) => b.value.fold<double>(0, (s, c) => s + c.monthlyCents).compareTo(a.value.fold<double>(0, (s, c) => s + c.monthlyCents)));
    final increases = active.where((c) => c.previousCents != null && c.previousCents! < c.expectedCents).length;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ContractEditScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Vertrag'),
      ),
      body: CustomScrollView(slivers: [
        SliverAppBar(
          title: const Text('Abos & Verträge'),
          floating: true,
          actions: [
            IconButton(
              icon: Icon(_calendar ? Icons.view_list_outlined : Icons.calendar_month_outlined),
              tooltip: _calendar ? 'Liste' : 'Kalender',
              onPressed: () => setState(() => _calendar = !_calendar),
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          sliver: SliverList.list(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Fixkosten ${_perYear ? 'pro Jahr' : 'pro Monat'}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: AmountText(_perYear ? monthly * 12 : monthly, style: theme.textTheme.displaySmall),
                  ),
                ]),
              ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [ButtonSegment(value: false, label: Text('Monat')), ButtonSegment(value: true, label: Text('Jahr'))],
                selected: {_perYear},
                onSelectionChanged: (s) => setState(() => _perYear = s.first),
              ),
            ]),
            Text(
              [
                '${active.length} aktive Verträge',
                if (share != null) '${AmountFormat.percent(share)} deines Einkommens',
                if (increases > 0) '$increases mit Preiserhöhung',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary),
            ),
            const SizedBox(height: 16),
            if (proposals.isNotEmpty) ...[
              AppCard(
                title: 'Erkannt – bitte prüfen',
                subtitle: 'Regelmäßige Zahlungen, die ein Abo oder Vertrag sein könnten',
                child: Column(children: [
                  for (final c in proposals.take(8))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Avatar(label: c.name, color: parseHexColor(engine.categoryById(c.categoryId)?.color), size: 36),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c.name, style: theme.textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text('${intervalLabel(c.interval)} · ${AmountFormat.format(c.expectedCents)} · ${c.transactionIds.length} Zahlungen',
                                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.secondary)),
                          ]),
                        ),
                        IconButton(
                          tooltip: 'Kein Vertrag',
                          icon: Icon(Icons.close, color: AppColors.neg(context)),
                          onPressed: () => store.setContractStatus(c.id, ContractStatus.ignoriert),
                        ),
                        IconButton(
                          tooltip: 'Ist ein Vertrag',
                          icon: Icon(Icons.check, color: AppColors.pos(context)),
                          onPressed: () => store.setContractStatus(c.id, ContractStatus.aktiv),
                        ),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            if (active.isEmpty)
              const AppCard(child: EmptyState(icon: Icons.autorenew, text: 'Noch keine Verträge erkannt. Sie erscheinen, sobald sich Zahlungen wiederholen.'))
            else if (_calendar)
              _CalendarView(contracts: active)
            else
              for (final g in groupList) ...[
                AppCard(
                  title: g.key,
                  trailing: AmountText(
                    (_perYear ? g.value.fold<double>(0, (a, c) => a + c.monthlyCents) * 12 : g.value.fold<double>(0, (a, c) => a + c.monthlyCents)).round(),
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  child: Column(children: [
                    for (final c in (g.value..sort((a, b) => b.monthlyCents.compareTo(a.monthlyCents)))) _ContractRow(c: c, perYear: _perYear),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
            if (ended.isNotEmpty) ...[
              TextButton.icon(
                onPressed: () => setState(() => _showEnded = !_showEnded),
                icon: Icon(_showEnded ? Icons.expand_less : Icons.expand_more),
                label: Text('${ended.length} gekündigt / beendet'),
              ),
              if (_showEnded)
                AppCard(child: Column(children: [for (final c in ended) _ContractRow(c: c, perYear: _perYear)])),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _ContractRow extends ConsumerWidget {
  final Contract c;
  final bool perYear;
  const _ContractRow({required this.c, required this.perYear});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final engine = ref.read(engineProvider);
    final increased = c.previousCents != null && c.previousCents! < c.expectedCents;
    final sub = [
      intervalLabel(c.interval),
      if (c.status == ContractStatus.gekuendigt) 'gekündigt',
      if (c.status == ContractStatus.beendet) 'beendet',
      if (c.status == ContractStatus.aktiv && c.nextDue != null) 'nächste ${AmountFormat.dateShort.format(c.nextDue!)}',
    ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContractDetailScreen(contractId: c.id))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Avatar(label: c.name, color: parseHexColor(engine.categoryById(c.categoryId)?.color), size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(c.name, style: theme.textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (increased) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.warn(context).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                    child: Text('teurer', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.warn(context))),
                  ),
                ],
              ]),
              Text(sub, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.secondary)),
            ]),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              AmountText(perYear ? c.yearlyCents : c.monthlyCents.round(), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text(
                perYear || c.interval == ContractInterval.monatlich
                    ? (perYear ? 'pro Jahr' : 'pro Monat')
                    : '${AmountFormat.format(c.expectedCents)} ${intervalShort(c.interval)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.secondary),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Kalender: Fälligkeiten im aktuellen und nächsten Monat.
class _CalendarView extends ConsumerWidget {
  final List<Contract> contracts;
  const _CalendarView({required this.contracts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    return Column(children: [
      for (var offset = 0; offset < 2; offset++) ...[
        _month(context, DateTime(now.year, now.month + offset, 1)),
        const SizedBox(height: 12),
      ],
    ]);
  }

  Widget _month(BuildContext context, DateTime month) {
    final theme = Theme.of(context);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final byDay = <int, List<Contract>>{};
    for (final c in contracts) {
      if (c.nextDue == null) continue;
      // Fälligkeiten in diesem Monat aus nextDue und Intervall hochrechnen
      var d = c.nextDue!;
      final step = Contract.daysOf(c.interval);
      while (d.isAfter(month)) {
        d = d.subtract(Duration(days: step));
      }
      while (d.isBefore(DateTime(month.year, month.month + 1, 1))) {
        if (d.year == month.year && d.month == month.month) byDay.putIfAbsent(d.day, () => []).add(c);
        d = d.add(Duration(days: step));
      }
    }
    final total = byDay.values.expand((l) => l).fold<int>(0, (a, c) => a + c.expectedCents);
    final leading = DateTime(month.year, month.month, 1).weekday - 1;
    return AppCard(
      title: AmountFormat.monthYear.format(month),
      trailing: AmountText(-total, style: theme.textTheme.bodyMedium),
      child: Column(children: [
        Row(children: [
          for (final d in const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'])
            Expanded(child: Center(child: Text(d, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.secondary)))),
        ]),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 0.9),
          itemCount: leading + daysInMonth,
          itemBuilder: (context, i) {
            if (i < leading) return const SizedBox.shrink();
            final day = i - leading + 1;
            final list = byDay[day] ?? const <Contract>[];
            final isToday = DateTime.now().year == month.year && DateTime.now().month == month.month && DateTime.now().day == day;
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: list.isEmpty
                  ? null
                  : () => showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        builder: (ctx) => SafeArea(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            for (final c in list)
                              ListTile(title: Text(c.name), subtitle: Text(intervalLabel(c.interval)), trailing: AmountText(-c.expectedCents)),
                          ]),
                        ),
                      ),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isToday ? theme.colorScheme.primary.withValues(alpha: 0.12) : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('$day', style: theme.textTheme.bodySmall?.copyWith(fontWeight: list.isEmpty ? null : FontWeight.w700)),
                  if (list.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                    ),
                ]),
              ),
            );
          },
        ),
      ]),
    );
  }
}
