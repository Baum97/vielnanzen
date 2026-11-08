import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/engine/contracts.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../charts.dart';
import '../theme.dart';
import '../widgets.dart';
import 'transaction_detail.dart';

String intervalLabel(ContractInterval i) => switch (i) {
      ContractInterval.woechentlich => 'wöchentlich',
      ContractInterval.zweiwoechentlich => 'alle 2 Wochen',
      ContractInterval.monatlich => 'monatlich',
      ContractInterval.quartalsweise => 'vierteljährlich',
      ContractInterval.halbjahrlich => 'halbjährlich',
      ContractInterval.jaehrlich => 'jährlich',
      ContractInterval.individuell => 'individuell',
    };

String intervalShort(ContractInterval i) => switch (i) {
      ContractInterval.woechentlich => '/Woche',
      ContractInterval.zweiwoechentlich => '/2 Wo.',
      ContractInterval.monatlich => '/Monat',
      ContractInterval.quartalsweise => '/Quartal',
      ContractInterval.halbjahrlich => '/Halbjahr',
      ContractInterval.jaehrlich => '/Jahr',
      ContractInterval.individuell => '',
    };

String statusLabel(ContractStatus s) => switch (s) {
      ContractStatus.vorschlag => 'Vorschlag',
      ContractStatus.aktiv => 'aktiv',
      ContractStatus.gekuendigt => 'gekündigt',
      ContractStatus.beendet => 'beendet',
      ContractStatus.ignoriert => 'kein Vertrag',
    };

class ContractDetailScreen extends ConsumerWidget {
  final String contractId;
  const ContractDetailScreen({super.key, required this.contractId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appStateProvider.select((s) => s.revision));
    final store = ref.read(storeProvider);
    final engine = ref.read(engineProvider);
    final theme = Theme.of(context);
    final c = store.contractById(contractId);
    if (c == null) return const Scaffold(body: Center(child: Text('Vertrag nicht gefunden')));
    final ids = c.transactionIds.toSet();
    final payments = store.transactions.where((t) => ids.contains(t.id)).toList()..sort((a, b) => b.bookingDate.compareTo(a.bookingDate));
    final totalPaid = payments.fold<int>(0, (a, t) => a + t.amountCents.abs());
    final increased = c.previousCents != null && c.previousCents! < c.expectedCents;
    final history = payments.reversed.toList();

    void setStatus(ContractStatus s) {
      store.setContractStatus(c.id, s);
      Navigator.pop(context);
      ref.read(appStateProvider.notifier).runAnalysis();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(c.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Bearbeiten',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContractEditScreen(contract: c))),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
        Center(child: AmountText(c.expectedCents, style: theme.textTheme.displaySmall)),
        Center(
          child: Text('${intervalLabel(c.interval)} · ${statusLabel(c.status)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary)),
        ),
        if (c.nextDue != null && c.status == ContractStatus.aktiv)
          Center(child: Text('nächste Zahlung ${AmountFormat.date.format(c.nextDue!)}', style: theme.textTheme.bodySmall)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: StatTile(label: 'pro Monat', cents: c.monthlyCents.round())),
          const SizedBox(width: 8),
          Expanded(child: StatTile(label: 'pro Jahr', cents: c.yearlyCents)),
          const SizedBox(width: 8),
          Expanded(child: StatTile(label: 'bisher bezahlt', cents: totalPaid)),
        ]),
        if (increased) ...[
          const SizedBox(height: 12),
          InfoBanner(
            text: 'Preis gestiegen: ${AmountFormat.format(c.previousCents!)} → ${AmountFormat.format(c.expectedCents)}. '
                'Bei Preiserhöhungen besteht meist ein Sonderkündigungsrecht.',
            color: AppColors.warn(context),
            icon: Icons.trending_up,
          ),
        ],
        if (history.length >= 2) ...[
          const SizedBox(height: 12),
          AppCard(
            title: 'Preisverlauf',
            child: BalanceChart(points: [for (final t in history) (t.bookingDate, t.amountCents.abs())], height: 90),
          ),
        ],
        const SizedBox(height: 12),
        AppCard(
          title: 'Details',
          child: Column(children: [
            _kv(context, 'Kategorie', engine.categoryById(c.categoryId)?.name ?? '–'),
            _kv(context, 'Konto', c.accountId != null ? (store.accountById(c.accountId!)?.name ?? '–') : '–'),
            if (c.lastPayment != null) _kv(context, 'Letzte Zahlung', AmountFormat.date.format(c.lastPayment!)),
            if (c.reason != null) _kv(context, 'Erkannt durch', c.reason!),
            _kv(context, 'Sicherheit', AmountFormat.percent(c.confidence)),
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          title: 'Zahlungen (${payments.length})',
          child: payments.isEmpty
              ? Text('Manuell angelegt – noch keine zugeordneten Zahlungen.', style: theme.textTheme.bodySmall)
              : Column(children: [
                  for (final t in payments.take(36))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(AmountFormat.date.format(t.bookingDate)),
                      trailing: AmountText(t.amountCents, signed: true),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TransactionDetailScreen(transactionId: t.id))),
                    ),
                ]),
        ),
        const SizedBox(height: 16),
        if (c.status == ContractStatus.aktiv || c.status == ContractStatus.vorschlag) ...[
          PrimaryButton(
            label: 'Kündigungsschreiben erstellen',
            icon: Icons.edit_document,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CancelHelpScreen(contract: c))),
          ),
          const SizedBox(height: 8),
          SecondaryButton(label: 'Als gekündigt markieren', onPressed: () => setStatus(ContractStatus.gekuendigt)),
          const SizedBox(height: 8),
        ],
        if (c.status == ContractStatus.vorschlag) ...[
          SecondaryButton(label: 'Ist ein Vertrag', onPressed: () => setStatus(ContractStatus.aktiv)),
          const SizedBox(height: 8),
        ],
        if (c.status != ContractStatus.aktiv && c.status != ContractStatus.vorschlag) ...[
          SecondaryButton(label: 'Wieder als aktiv führen', onPressed: () => setStatus(ContractStatus.aktiv)),
          const SizedBox(height: 8),
        ],
        if (c.status != ContractStatus.ignoriert)
          TextButton(onPressed: () => setStatus(ContractStatus.ignoriert), child: const Text('Kein Vertrag – ausblenden')),
        if (c.transactionIds.isEmpty)
          TextButton(
            onPressed: () {
              store.removeContract(c.id);
              Navigator.pop(context);
            },
            child: Text('Löschen', style: TextStyle(color: AppColors.neg(context))),
          ),
      ]),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Text(k, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary))),
        Flexible(child: Text(v, style: theme.textTheme.bodyMedium, textAlign: TextAlign.right)),
      ]),
    );
  }
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
  final _notice = TextEditingController();
  ContractInterval _interval = ContractInterval.monatlich;
  String? _categoryId;
  DateTime? _nextDue;

  @override
  void initState() {
    super.initState();
    final c = widget.contract;
    if (c != null) {
      _name.text = c.name;
      _amount.text = (c.expectedCents / 100).toStringAsFixed(2).replaceAll('.', ',');
      _interval = c.interval;
      _categoryId = c.categoryId;
      _nextDue = c.nextDue;
      _notice.text = c.noticePeriod ?? '';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _notice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = ref.read(engineProvider);
    final cats = engine.categories.where((c) => c.kind == CategoryKind.ausgabe).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.contract == null ? 'Vertrag anlegen' : 'Vertrag bearbeiten')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name (z. B. Handyvertrag)')),
        const SizedBox(height: 12),
        TextField(
          controller: _amount,
          decoration: const InputDecoration(labelText: 'Betrag pro Zahlung', suffixText: '€'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ContractInterval>(
          initialValue: _interval,
          decoration: const InputDecoration(labelText: 'Intervall'),
          items: [for (final i in ContractInterval.values) DropdownMenuItem(value: i, child: Text(intervalLabel(i)))],
          onChanged: (v) => setState(() => _interval = v ?? ContractInterval.monatlich),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: cats.any((c) => c.id == _categoryId) ? _categoryId : null,
          decoration: const InputDecoration(labelText: 'Kategorie'),
          isExpanded: true,
          items: [for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.parentId == null ? c.name : '   ${c.name}'))],
          onChanged: (v) => setState(() => _categoryId = v),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Nächste Zahlung'),
          subtitle: Text(_nextDue == null ? 'nicht gesetzt' : AmountFormat.date.format(_nextDue!)),
          trailing: const Icon(Icons.event),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _nextDue ?? DateTime.now(),
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 730)),
            );
            if (d != null) setState(() => _nextDue = d);
          },
        ),
        TextField(controller: _notice, decoration: const InputDecoration(labelText: 'Kündigungsfrist (optional, z. B. 1 Monat)')),
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'Speichern',
          onPressed: () {
            final euros = double.tryParse(_amount.text.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
            final store = ref.read(storeProvider);
            final old = widget.contract;
            final name = _name.text.trim().isEmpty ? 'Vertrag' : _name.text.trim();
            store.upsertContract(Contract(
              id: old?.id ?? 'c_manual_${stableId('$name${DateTime.now().microsecondsSinceEpoch}')}',
              merchantId: old?.merchantId,
              name: name,
              interval: _interval,
              expectedCents: (euros * 100).round(),
              previousCents: old?.previousCents,
              nextDue: _nextDue ?? old?.nextDue ?? DateTime.now().add(Duration(days: Contract.daysOf(_interval))),
              lastPayment: old?.lastPayment,
              confidence: 1,
              status: old?.status == ContractStatus.vorschlag || old == null ? ContractStatus.aktiv : old.status,
              noticePeriod: _notice.text.trim().isEmpty ? null : _notice.text.trim(),
              categoryId: _categoryId,
              accountId: old?.accountId,
              reason: old?.reason ?? 'Manuell angelegt',
              transactionIds: old?.transactionIds ?? const [],
              userConfirmed: true,
            ));
            Navigator.pop(context);
          },
        ),
      ]),
    );
  }
}

/// Kündigungshilfe: Schreiben erzeugen und über das System teilen (E-Mail, Messenger, Drucken …).
class CancelHelpScreen extends StatefulWidget {
  final Contract contract;
  const CancelHelpScreen({super.key, required this.contract});

  @override
  State<CancelHelpScreen> createState() => _CancelHelpScreenState();
}

class _CancelHelpScreenState extends State<CancelHelpScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _customerNo = TextEditingController();
  bool _extraordinary = false;

  @override
  void initState() {
    super.initState();
    _extraordinary = widget.contract.previousCents != null && widget.contract.previousCents! < widget.contract.expectedCents;
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _customerNo.dispose();
    super.dispose();
  }

  String get _letter {
    final today = AmountFormat.date.format(DateTime.now());
    final reason = _extraordinary
        ? 'hiermit kündige ich den o. g. Vertrag außerordentlich aufgrund der angekündigten bzw. erfolgten Preiserhöhung, '
            'hilfsweise ordentlich zum nächstmöglichen Termin.'
        : 'hiermit kündige ich den o. g. Vertrag fristgerecht zum nächstmöglichen Termin.';
    return '''${_name.text}
${_address.text}

$today

Kündigung: ${widget.contract.name}
Kundennummer/Vertragsnummer: ${_customerNo.text.isEmpty ? '–' : _customerNo.text}

Sehr geehrte Damen und Herren,

$reason

Bitte bestätigen Sie mir die Kündigung sowie das Vertragsende schriftlich. Einer weiteren Nutzung meiner Daten zu Werbezwecken widerspreche ich. Eine erteilte Einzugsermächtigung (SEPA-Lastschriftmandat) widerrufe ich zum Vertragsende.

Mit freundlichen Grüßen
${_name.text}''';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Kündigungshilfe')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Die App versendet nichts selbst. Du kannst das Schreiben teilen (E-Mail, Drucken, Messenger) – '
            'bei Online-Verträgen gibt es außerdem den gesetzlichen „Verträge hier kündigen“-Button des Anbieters.',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Dein Name'), onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        TextField(controller: _address, decoration: const InputDecoration(labelText: 'Deine Adresse'), maxLines: 2, onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        TextField(controller: _customerNo, decoration: const InputDecoration(labelText: 'Kunden-/Vertragsnummer'), onChanged: (_) => setState(() {})),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sonderkündigung wegen Preiserhöhung'),
          value: _extraordinary,
          onChanged: (v) => setState(() => _extraordinary = v),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
          child: SelectableText(_letter, style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Teilen',
          icon: Icons.ios_share,
          onPressed: () => SharePlus.instance.share(ShareParams(text: _letter, subject: 'Kündigung ${widget.contract.name}')),
        ),
        const SizedBox(height: 8),
        SecondaryButton(label: 'Kopieren', icon: Icons.copy, onPressed: () => copyToClipboard(context, _letter)),
      ]),
    );
  }
}
