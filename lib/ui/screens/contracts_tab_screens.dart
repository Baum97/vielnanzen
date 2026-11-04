import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';

class ContractsTabScreen extends ConsumerStatefulWidget {
  final int initialSegment;
  const ContractsTabScreen({super.key, this.initialSegment = 0});

  @override
  ConsumerState<ContractsTabScreen> createState() => _ContractsTabScreenState();
}

class _ContractsTabScreenState extends ConsumerState<ContractsTabScreen> {
  late int _segment;
  bool _perYear = false;

  @override
  void initState() {
    super.initState();
    _segment = widget.initialSegment;
  }

  static String _intervalLabel(ContractInterval i) => switch (i) {
        ContractInterval.woechentlich => 'wöchentlich',
        ContractInterval.zweiwoechentlich => 'alle 2 Wochen',
        ContractInterval.monatlich => 'monatlich',
        ContractInterval.quartalsweise => 'quartalsweise',
        ContractInterval.halbjahrlich => 'halbjährlich',
        ContractInterval.jaehrlich => 'jährlich',
        ContractInterval.individuell => 'individuell',
      };

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final store = app.store;
    final theme = Theme.of(context);
    final discreet = store.settings['discreetMode'] == true;

    final proposals = store.contracts.where((c) => c.status == ContractStatus.vorschlag).toList();
    final active = store.contracts.where((c) => c.status == ContractStatus.aktiv || c.status == ContractStatus.gekuendigt).toList();
    final monthlyTotal = active.where((c) => c.status == ContractStatus.aktiv).fold<double>(0, (a, c) => a + c.monthlyCents);

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          title: const Text('Verträge'),
          floating: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ContractEditScreen())),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(120),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AmountText(
                  _perYear ? (monthlyTotal * 12).round() : monthlyTotal.round(),
                  discreet: discreet,
                  style: theme.textTheme.displaySmall?.copyWith(fontSize: 32),
                ),
                Text('${active.where((c) => c.status == ContractStatus.aktiv).length} aktive Verträge · ${_perYear ? 'im Jahr' : 'im Monat'}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary)),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Liste')),
                    ButtonSegment(value: 1, label: Text('Kalendar')),
                  ],
                  selected: {_segment},
                  onSelectionChanged: (s) => setState(() => _segment = s.first),
                ),
                const SizedBox(height: 4),
                ToggleButtons(
                  isSelected: [_perYear == false, _perYear == true],
                  onPressed: (i) => setState(() => _perYear = i == 1),
                  borderRadius: BorderRadius.circular(10),
                  children: const [Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('Monat')), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('Jahr'))],
                ),
              ]),
            ),
          ),
        ),
        if (proposals.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Vorschläge prüfen', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: proposals.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final c = proposals[i];
                      return Dismissible(
                        key: ValueKey(c.id),
                        background: Container(color: AppColors.positive.withValues(alpha: 0.2), alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 16), child: const Text('Ist ein Vertrag')),
                        secondaryBackground: Container(color: AppColors.critical.withValues(alpha: 0.2), alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), child: const Text('Kein Vertrag')),
                        onDismissed: (dir) {
                          store.upsertContract(Contract(
                            id: c.id,
                            merchantId: c.merchantId,
                            name: c.name,
                            interval: c.interval,
                            expectedCents: c.expectedCents,
                            nextDue: c.nextDue,
                            confidence: c.confidence,
                            status: dir == DismissDirection.startToEnd ? ContractStatus.aktiv : ContractStatus.ignoriert,
                            categoryId: c.categoryId,
                            accountId: c.accountId,
                            reason: c.reason,
                            transactionIds: c.transactionIds,
                          ));
                        },
                        child: SizedBox(
                          width: 220,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                                Text('${_intervalLabel(c.interval)} · ${c.transactionIds.length} Zahlungen', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary)),
                                const Spacer(),
                                Row(children: [
                                  Expanded(child: LinearProgressIndicator(value: c.confidence)),
                                  const SizedBox(width: 8),
                                  AmountText(-c.expectedCents, discreet: discreet, style: theme.textTheme.bodyMedium),
                                ]),
                              ]),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ]),
            ),
          ),
        if (_segment == 0)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final sorted = active.toList()..sort((a, b) => b.monthlyCents.compareTo(a.monthlyCents));
                final c = sorted[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    dense: true,
                    tileColor: theme.colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    leading: CircleAvatar(radius: 18, child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?', style: theme.textTheme.bodyMedium)),
                    title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${_intervalLabel(c.interval)} · ${c.status == ContractStatus.aktiv ? 'aktiv' : 'gekündigt'}${c.nextDue != null ? ' · nächste ${AmountFormat.dateShort.format(c.nextDue!)}' : ''}'),
                    trailing: AmountText(-(_perYear ? (c.monthlyCents * 12).round() : c.expectedCents), discreet: discreet),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContractDetailScreen(contractId: c.id))),
                  ),
                );
              },
              childCount: active.length,
            ),
          )
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _CalendarView(contracts: active, discreet: discreet),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ]),
    );
  }
}

class _CalendarView extends StatelessWidget {
  final List<Contract> contracts;
  final bool discreet;
  const _CalendarView({required this.contracts, required this.discreet});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final month = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final byDay = <int, List<Contract>>{};
    for (final c in contracts) {
      if (c.nextDue == null) continue;
      byDay.putIfAbsent(c.nextDue!.day, () => []).add(c);
    }
    return AppCard(
      title: '${AmountFormat.monthYear.format(month)}',
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 0.85),
        itemCount: daysInMonth,
        itemBuilder: (context, i) {
          final day = i + 1;
          final list = byDay[day] ?? const [];
          return InkWell(
            onTap: list.isEmpty ? null : () => showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [for (final c in list) ListTile(title: Text(c.name), trailing: AmountText(-c.expectedCents, discreet: discreet))]))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$day', style: theme.textTheme.bodySmall),
              if (list.isNotEmpty)
                Container(margin: const EdgeInsets.only(top: 4), width: 6, height: 6, decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle)),
            ]),
          );
        },
      ),
    );
  }
}

class ContractDetailScreen extends ConsumerWidget {
  final String contractId;
  const ContractDetailScreen({super.key, required this.contractId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(appStateProvider).store;
    final theme = Theme.of(context);
    final discreet = store.settings['discreetMode'] == true;
    final c = store.contracts.where((e) => e.id == contractId).firstOrNull;
    if (c == null) return const Scaffold(body: Center(child: Text('Vertrag nicht gefunden')));
    final payments = store.transactions.where((t) => c.transactionIds.contains(t.id)).toList()
      ..sort((a, b) => b.bookingDate.compareTo(a.bookingDate));
    final totalPaid = payments.fold<int>(0, (a, t) => a + t.amountCents.abs());

    return Scaffold(
      appBar: AppBar(title: Text(c.name, overflow: TextOverflow.ellipsis)),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: AmountText(-c.expectedCents, style: theme.textTheme.displaySmall, discreet: discreet)),
            Center(child: Text('${_ContractsTabScreenState._intervalLabel(c.interval)} · ${c.status == ContractStatus.aktiv ? 'aktiv' : c.status.name}', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary))),
            if (c.nextDue != null) Center(child: Text('nächste Zahlung ${AmountFormat.date.format(c.nextDue!)}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary))),
            const SizedBox(height: 16),
            AppCard(title: 'Kennzahlen', child: Column(children: [
              _kv('Zahlungen gesamt', '${payments.length} · ${AmountFormat.format(totalPaid, discreet: discreet)} insgesamt'),
              _kv('Monatlich (Ø)', AmountFormat.format(c.monthlyCents.round(), discreet: discreet)),
              if (c.reason != null) _kv('Erkannt durch', c.reason!),
            ])),
            const SizedBox(height: 12),
            AppCard(
              title: 'Zahlungen',
              child: Column(children: [for (final t in payments.take(20)) ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(AmountFormat.date.format(t.bookingDate)), trailing: AmountText(t.amountCents, signed: true, discreet: discreet))]),
            ),
            const SizedBox(height: 12),
            PrimaryButton(label: 'Kündigungshilfe', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CancelHelpScreen(contract: c)))),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Als gekündigt markieren',
              onPressed: () {
                store.upsertContract(Contract(
                  id: c.id, merchantId: c.merchantId, name: c.name, interval: c.interval, expectedCents: c.expectedCents,
                  nextDue: c.nextDue, confidence: c.confidence, status: ContractStatus.gekuendigt,
                  categoryId: c.categoryId, accountId: c.accountId, reason: c.reason, transactionIds: c.transactionIds,
                ));
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Kein Vertrag',
              onPressed: () {
                store.upsertContract(Contract(
                  id: c.id, merchantId: c.merchantId, name: c.name, interval: c.interval, expectedCents: c.expectedCents,
                  nextDue: c.nextDue, confidence: c.confidence, status: ContractStatus.ignoriert,
                  categoryId: c.categoryId, accountId: c.accountId, reason: c.reason, transactionIds: c.transactionIds,
                ));
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 40),
          ]),
        ),
      ]),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(fontSize: 13))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}

class ContractEditScreen extends ConsumerStatefulWidget {
  final Contract? contract;
  const ContractEditScreen({super.key, this.contract});

  @override
  ConsumerState<ContractEditScreen> createState() => _ContractEditScreenState();
}

class _ContractEditScreenState extends ConsumerState<ContractEditScreen> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  ContractInterval _interval = ContractInterval.monatlich;

  @override
  void initState() {
    super.initState();
    if (widget.contract != null) {
      _name.text = widget.contract!.name;
      _amount.text = (widget.contract!.expectedCents / 100).toStringAsFixed(2).replaceAll('.', ',');
      _interval = widget.contract!.interval;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.read(appStateProvider).store;
    return Scaffold(
      appBar: AppBar(title: Text(widget.contract == null ? 'Vertrag anlegen' : 'Vertrag bearbeiten')),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              decoration: const InputDecoration(labelText: 'Betrag (€)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ContractInterval>(
              initialValue: _interval,
              decoration: const InputDecoration(labelText: 'Intervall'),
              items: ContractInterval.values
                  .map((i) => DropdownMenuItem(value: i, child: Text(_ContractsTabScreenState._intervalLabel(i))))
                  .toList(),
              onChanged: (v) => setState(() => _interval = v ?? ContractInterval.monatlich),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Speichern',
              onPressed: () {
                final euros = double.tryParse(_amount.text.replaceAll(',', '.')) ?? 0;
                store.upsertContract(Contract(
                  id: widget.contract?.id ?? 'c_${DateTime.now().microsecondsSinceEpoch}',
                  name: _name.text.isEmpty ? 'Vertrag' : _name.text,
                  interval: _interval,
                  expectedCents: (euros * 100).round(),
                  confidence: 1,
                  status: widget.contract?.status ?? ContractStatus.aktiv,
                  nextDue: DateTime.now().add(const Duration(days: 30)),
                ));
                Navigator.pop(context);
              },
            ),
          ]),
        ),
      ]),
    );
  }
}

class CancelHelpScreen extends StatefulWidget {
  final Contract contract;
  const CancelHelpScreen({super.key, required this.contract});

  @override
  State<CancelHelpScreen> createState() => _CancelHelpScreenState();
}

class _CancelHelpScreenState extends State<CancelHelpScreen> {
  int _step = 0;
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _customerNo = TextEditingController();

  String get _letter => '''Sehr geehrte Damen und Herren,

hiermit kündige ich den Vertrag „${widget.contract.name}“ (Kundennummer: ${_customerNo.text.isEmpty ? '–' : _customerNo.text})
zum nächstmöglichen Termin.

Bitte bestätigen Sie mir die Kündigung schriftlich.

Mit freundlichen Grüßen
${_name.text}${_address.text}''';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Kündigungshilfe')),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Schritt ${_step + 1} von 3', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            if (_step == 0) ...[
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Dein Name')),
              const SizedBox(height: 12),
              TextField(controller: _address, decoration: const InputDecoration(labelText: 'Adresse')),
              const SizedBox(height: 12),
              TextField(controller: _customerNo, decoration: InputDecoration(labelText: 'Kundennummer (${widget.contract.name})')),
            ],
            if (_step == 1)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
                child: Text(_letter, style: theme.textTheme.bodyLarge),
              ),
            if (_step == 2) ...[
              Text('Die App versendet nichts selbst. Teile das Schreiben als Text oder PDF – oder nutze den Kündigungsbutton des Anbieters (bei Online-Verträgen Pflicht).', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              SelectableText(_letter, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 24),
            Row(children: [
              if (_step > 0) Expanded(child: SecondaryButton(label: 'Zurück', onPressed: () => setState(() => _step--))),
              if (_step > 0) const SizedBox(width: 12),
              Expanded(child: PrimaryButton(label: _step == 2 ? 'Fertig' : 'Weiter', onPressed: () { if (_step < 2) setState(() => _step++); else Navigator.pop(context); })),
            ]),
          ]),
        ),
      ]),
    );
  }
}
