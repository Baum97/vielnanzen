import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/normalize.dart';
import '../../core/seed/demo_data.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../../services/bank_sync.dart';
import '../../state/app_state.dart';
import '../bank/sync_ui.dart';
import '../theme.dart';
import '../widgets.dart';
import 'bank_connect.dart';
import 'import_screen.dart';

/// Lädt den Demo-Datensatz (5 Jahre, 2 Konten) – rein lokal.
Future<void> loadDemoData(WidgetRef ref) async {
  final store = ref.read(storeProvider);
  final demo = DemoData.generate();
  store.batch(() {
    for (final a in demo.accounts) {
      store.upsertAccount(a);
    }
    store.upsertTransactions(demo.transactions);
  });
  await ref.read(appStateProvider.notifier).runAnalysis();
  await store.save();
}

/// Konto ohne Bankverbindung (Bargeld, Sparschwein, …).
Future<bool> addManualAccount(BuildContext context, WidgetRef ref) async {
  final name = TextEditingController(text: 'Bargeld');
  final balance = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Manuelles Konto'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 12),
        TextField(
          controller: balance,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: const InputDecoration(labelText: 'Aktueller Bestand', suffixText: '€'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Anlegen')),
      ],
    ),
  );
  if (ok != true) return false;
  ref.read(storeProvider).upsertAccount(Account(
        id: 'acc_manual_${DateTime.now().microsecondsSinceEpoch}',
        iban: '',
        name: name.text.trim().isEmpty ? 'Bargeld' : name.text.trim(),
        type: AccountType.bargeld,
        balanceCents: parseAmountCents(balance.text) ?? 0,
        balanceDate: DateTime.now(),
        color: '#7A8A6F',
      ));
  return true;
}

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appStateProvider.select((s) => s.revision));
    final store = ref.read(storeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Konten & Banken')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        if (store.connections.isNotEmpty) ...[
          const SectionTitle('Bankverbindungen'),
          for (final c in store.connections) ...[
            Card(
              child: Column(children: [
                ListTile(
                  leading: Avatar(label: c.bankName, color: theme.colorScheme.primary, size: 38),
                  title: Text(c.bankName),
                  subtitle: Text([
                    'BLZ ${c.blz} · ${c.userId}',
                    c.lastSync != null ? 'zuletzt ${AmountFormat.date.format(c.lastSync!)}' : 'noch nicht abgerufen',
                    if (c.pinSaved) 'PIN gespeichert',
                  ].join('\n')),
                  isThreeLine: true,
                ),
                if (c.lastError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: InfoBanner(text: c.lastError!, color: AppColors.neg(context), icon: Icons.error_outline),
                  ),
                OverflowBar(alignment: MainAxisAlignment.end, children: [
                  if (c.pinSaved)
                    TextButton(
                      onPressed: () async {
                        await store.keyStore.write(Store.pinKeyFor(c.id), null);
                        store.upsertConnection(c.copyWith(pinSaved: false));
                      },
                      child: const Text('PIN vergessen'),
                    ),
                  TextButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('${c.bankName} entfernen?'),
                          content: const Text('Die Konten dieser Verbindung und ihre Umsätze werden von diesem Gerät gelöscht.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Entfernen')),
                          ],
                        ),
                      );
                      if (ok == true) await ref.read(bankSyncProvider).removeConnection(c);
                    },
                    child: Text('Entfernen', style: TextStyle(color: AppColors.neg(context))),
                  ),
                  if (bankingSupported)
                    FilledButton.tonalIcon(
                      onPressed: () => syncConnectionInteractive(context, ref, c),
                      icon: const Icon(Icons.sync, size: 18),
                      label: const Text('Abrufen'),
                    ),
                ]),
              ]),
            ),
            const SizedBox(height: 8),
          ],
        ],
        const SectionTitle('Konten'),
        if (store.accounts.isEmpty) Text('Noch keine Konten.', style: theme.textTheme.bodySmall),
        for (final a in store.accounts)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Avatar(label: a.name, color: parseHexColor(a.color), size: 38),
              title: Text(a.name),
              subtitle: Text([
                if (a.iban.isNotEmpty) a.iban,
                a.connectionId != null ? 'per FinTS' : 'manuell / Import',
                if (!a.includeInTotal) 'nicht im Gesamtsaldo',
                if (a.hidden) 'ausgeblendet',
              ].join(' · ')),
              trailing: AmountText(a.balanceCents),
              onTap: () => _editAccount(context, ref, a),
            ),
          ),
        const SectionTitle('Hinzufügen'),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: const Text('Bank verbinden'),
              subtitle: Text(bankingSupported ? 'FinTS – direkt zur Bank' : 'nur in der Android-/iOS-App'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BankConnectScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('Kontoauszug importieren'),
              subtitle: const Text('CSV, CAMT oder MT940'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Bargeld / manuelles Konto'),
              onTap: () => addManualAccount(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Demo-Daten laden'),
              subtitle: const Text('5 Jahre Beispielumsätze zum Ausprobieren'),
              onTap: () async {
                await loadDemoData(ref);
                if (context.mounted) showSnack(context, 'Demo-Daten geladen');
              },
            ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _editAccount(BuildContext context, WidgetRef ref, Account a) async {
    final store = ref.read(storeProvider);
    final name = TextEditingController(text: a.name);
    final balance = TextEditingController(text: (a.balanceCents / 100).toStringAsFixed(2).replaceAll('.', ','));
    var include = a.includeInTotal;
    var hidden = a.hidden;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Konto bearbeiten'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              if (a.isManual) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: balance,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Kontostand', suffixText: '€'),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Im Gesamtsaldo'),
                value: include,
                onChanged: (v) => setState(() => include = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ausblenden'),
                value: hidden,
                onChanged: (v) => setState(() => hidden = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: Text('Löschen', style: TextStyle(color: AppColors.neg(ctx)))),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Speichern')),
          ],
        ),
      ),
    );
    if (result == 'save') {
      store.upsertAccount(a.copyWith(
        name: name.text.trim().isEmpty ? a.name : name.text.trim(),
        balanceCents: a.isManual ? (parseAmountCents(balance.text) ?? a.balanceCents) : null,
        includeInTotal: include,
        hidden: hidden,
      ));
    } else if (result == 'delete' && context.mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('„${a.name}“ löschen?'),
          content: const Text('Das Konto und alle zugehörigen Umsätze werden von diesem Gerät gelöscht.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
          ],
        ),
      );
      if (ok == true) {
        store.removeAccount(a.id);
        await ref.read(appStateProvider.notifier).runAnalysis();
      }
    }
  }
}
