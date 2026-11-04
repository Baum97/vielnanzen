import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';

class TransactionDetailScreen extends ConsumerWidget {
  final String transactionId;
  const TransactionDetailScreen({super.key, required this.transactionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final store = app.store;
    final engine = ref.read(engineProvider);
    final theme = Theme.of(context);
    final discreet = store.settings['discreetMode'] == true;
    final t = (app.result?.transactions ?? store.transactions).where((e) => e.id == transactionId).firstOrNull;
    if (t == null) return const Scaffold(body: Center(child: Text('Umsatz nicht gefunden')));

    final cat = engine.categoryById(t.categoryId);
    final accountName = store.accounts.where((a) => a.id == t.accountId).map((a) => a.name).firstOrNull ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Umsatz')),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: AmountText(t.amountCents, signed: true, discreet: discreet, style: theme.textTheme.displaySmall)),
            Center(child: Text(t.counterpartyName.isEmpty ? 'Unbekannt' : t.counterpartyName, style: theme.textTheme.titleLarge, textAlign: TextAlign.center)),
            const SizedBox(height: 24),
            _row('Datum', AmountFormat.date.format(t.bookingDate)),
            _row('Konto', accountName),
            _row('Kategorie', cat?.name ?? 'Unkategorisiert'),
            if (t.categoryReason != null) _row('Erkannt durch', t.categoryReason!),
            if (t.purpose.isNotEmpty) _row('Verwendungszweck', t.purpose),
            if (t.counterpartyIban != null) _row('IBAN', t.counterpartyIban!),
            if (t.creditorId != null) _row('Gläubiger-ID', t.creditorId!),
            if (t.mandateRef != null) _row('Mandatsreferenz', t.mandateRef!),
            if (t.endToEndRef != null) _row('End-to-End-Ref', t.endToEndRef!),
            _row('Status', t.pending ? 'vorgemerkt' : 'gebucht'),
            const SizedBox(height: 24),
            Text('Kategorie ändern', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in engine.categories.where((c) => c.kind == CategoryKind.ausgabe))
                  FilterChip(
                    label: Text(c.name),
                    selected: t.categoryId == c.id,
                    onSelected: (_) {
                      store.upsertTransaction(t.copyWith(categoryId: c.id));
                      ref.read(appStateProvider.notifier).runAnalysis();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Von Auswertung ausschließen'),
              value: t.excluded,
              onChanged: (v) {
                store.upsertTransaction(t.copyWith(excluded: v));
                ref.read(appStateProvider.notifier).runAnalysis();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Umbuchung (Transfer)'),
              value: t.isTransfer,
              onChanged: (v) {
                store.upsertTransaction(t.copyWith(isTransfer: v));
                ref.read(appStateProvider.notifier).runAnalysis();
              },
            ),
            const SizedBox(height: 40),
          ]),
        ),
      ]),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 140, child: Text(k, style: const TextStyle(fontSize: 13, color: Colors.grey))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 15))),
        ]),
      );
}
