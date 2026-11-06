import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/normalize.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'contract_screens.dart';

class TransactionDetailScreen extends ConsumerWidget {
  final String transactionId;
  const TransactionDetailScreen({super.key, required this.transactionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appStateProvider.select((s) => s.revision));
    final store = ref.read(storeProvider);
    final engine = ref.read(engineProvider);
    final analytics = ref.read(analyticsProvider);
    final theme = Theme.of(context);
    final t = store.transactionById(transactionId);
    if (t == null) return const Scaffold(body: Center(child: Text('Umsatz nicht gefunden')));

    final cat = engine.categoryById(t.categoryId);
    final account = store.accountById(t.accountId);
    final contract = t.contractId != null ? store.contractById(t.contractId!) : null;
    final title = analytics.merchantDisplay(t);

    return Scaffold(
      appBar: AppBar(title: const Text('Umsatz')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
        Center(child: Avatar(icon: cat != null ? categoryIcon(cat.icon) : null, label: title, color: parseHexColor(cat?.color), size: 60)),
        const SizedBox(height: 12),
        Center(child: AmountText(t.amountCents, signed: true, style: theme.textTheme.displaySmall)),
        Center(child: Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center)),
        if (title != t.counterpartyName)
          Center(child: Text(t.counterpartyName, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary))),
        const SizedBox(height: 20),
        AppCard(
          child: Column(children: [
            _row(context, 'Datum', AmountFormat.date.format(t.bookingDate)),
            _row(context, 'Konto', account?.name ?? '–'),
            _row(context, 'Kategorie', cat?.name ?? 'Unkategorisiert'),
            if (t.categoryReason != null) _row(context, 'Erkannt durch', t.manualCategory ? 'Von dir festgelegt' : t.categoryReason!),
            if (t.purpose.isNotEmpty) _row(context, 'Verwendungszweck', t.purpose, copy: true),
            if (t.counterpartyIban != null) _row(context, 'IBAN', t.counterpartyIban!, copy: true),
            if (t.creditorId != null) _row(context, 'Gläubiger-ID', t.creditorId!, copy: true),
            if (t.mandateRef != null) _row(context, 'Mandatsreferenz', t.mandateRef!, copy: true),
            if (t.endToEndRef != null) _row(context, 'End-to-End-Ref', t.endToEndRef!),
            _row(context, 'Status', t.pending ? 'vorgemerkt' : 'gebucht'),
          ]),
        ),
        if (contract != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.autorenew),
              title: Text('Teil von „${contract.name}“'),
              subtitle: Text('${intervalLabel(contract.interval)} · ${AmountFormat.format(contract.yearlyCents)} pro Jahr'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContractDetailScreen(contractId: contract.id))),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text('Kategorie', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Avatar(icon: categoryIcon(cat?.icon), color: parseHexColor(cat?.color), size: 34),
            title: Text(cat?.name ?? 'Kategorie wählen'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _pickCategory(context, ref, t),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            SwitchListTile(
              title: const Text('Umbuchung zwischen eigenen Konten'),
              subtitle: const Text('Zählt nicht als Einnahme/Ausgabe'),
              value: t.isTransfer,
              onChanged: (v) {
                store.upsertTransaction(t.copyWith(isTransfer: v, manualCategory: true, categoryId: v ? 'umbuchung' : t.categoryId));
                ref.read(appStateProvider.notifier).runAnalysis();
              },
            ),
            SwitchListTile(
              title: const Text('Von Auswertungen ausschließen'),
              subtitle: const Text('z. B. einmalige Sonderausgaben'),
              value: t.excluded,
              onChanged: (v) {
                store.upsertTransaction(t.copyWith(excluded: v));
                ref.read(appStateProvider.notifier).runAnalysis();
              },
            ),
            ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: Text(t.note?.isNotEmpty == true ? t.note! : 'Notiz hinzufügen'),
              onTap: () => _editNote(context, ref, t),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _row(BuildContext context, String k, String v, {bool copy = false}) {
    final theme = Theme.of(context);
    return InkWell(
      onLongPress: copy ? () => copyToClipboard(context, v) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary))),
          Expanded(child: Text(v, style: theme.textTheme.bodyMedium)),
        ]),
      ),
    );
  }

  Future<void> _editNote(BuildContext context, WidgetRef ref, Transaction t) async {
    final ctrl = TextEditingController(text: t.note);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notiz'),
        content: TextField(controller: ctrl, autofocus: true, maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Speichern')),
        ],
      ),
    );
    if (r != null) ref.read(storeProvider).upsertTransaction(t.copyWith(note: r));
  }

  Future<void> _pickCategory(BuildContext context, WidgetRef ref, Transaction t) async {
    final engine = ref.read(engineProvider);
    final kinds = t.isIncome ? {CategoryKind.einnahme, CategoryKind.umbuchung} : {CategoryKind.ausgabe, CategoryKind.umbuchung};
    final tops = engine.categories.where((c) => c.parentId == null && kinds.contains(c.kind)).toList();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (ctx, scroll) => ListView(controller: scroll, children: [
          for (final top in tops) ...[
            ListTile(
              leading: Avatar(icon: categoryIcon(top.icon), color: parseHexColor(top.color), size: 32),
              title: Text(top.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              selected: t.categoryId == top.id,
              onTap: () => Navigator.pop(ctx, top.id),
            ),
            for (final c in engine.categories.where((c) => c.parentId == top.id))
              ListTile(
                contentPadding: const EdgeInsets.only(left: 72, right: 16),
                dense: true,
                title: Text(c.name),
                selected: t.categoryId == c.id,
                onTap: () => Navigator.pop(ctx, c.id),
              ),
          ],
        ]),
      ),
    );
    if (picked == null || !context.mounted) return;
    final store = ref.read(storeProvider);
    store.upsertTransaction(t.copyWith(
      categoryId: picked,
      manualCategory: true,
      categoryReason: 'Manuell',
      isTransfer: picked == 'umbuchung',
    ));

    // Für alle Umsätze dieser Firma übernehmen?
    final analytics = ref.read(analyticsProvider);
    final name = analytics.merchantDisplay(t);
    final key = t.merchantId ?? normalizeMerchantName(t.counterpartyName);
    final others = store.transactions.where((x) => x.id != t.id && analytics.merchantKey(x) == analytics.merchantKey(t)).length;
    if (others > 0 && key.isNotEmpty) {
      final all = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Für alle übernehmen?'),
          content: Text('Auch die $others anderen Umsätze von „$name“ und künftige so einordnen?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nur diesen')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Alle')),
          ],
        ),
      );
      if (all == true) {
        store.upsertRule(Rule(
          id: 'r_${key.hashCode.toRadixString(16)}',
          field: 'merchant',
          operator: 'equals',
          value: key,
          action: picked == 'umbuchung' ? 'transfer' : 'category',
          actionValue: picked,
          priority: 10,
        ));
      }
    }
    await ref.read(appStateProvider.notifier).runAnalysis();
  }
}
