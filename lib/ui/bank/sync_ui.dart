import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connectors/fints_connector.dart';
import '../../data/models.dart';
import '../../services/bank_sync.dart';
import '../../state/app_state.dart';
import '../widgets.dart';
import 'tan_prompts.dart';

/// FinTS aus dem Browser scheitert an CORS – Bankabruf nur in der App.
bool get bankingSupported => !kIsWeb;

/// PIN-Abfrage. Liefert (PIN, speichern?) oder null bei Abbruch.
Future<(String, bool)?> askPin(BuildContext context, BankConnection c, {bool offerSave = true}) {
  final ctrl = TextEditingController();
  var save = c.pinSaved;
  return showDialog<(String, bool)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('PIN für ${c.bankName}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Anmeldename: ${c.userId}', style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Online-Banking-PIN'),
            onSubmitted: (v) => Navigator.pop(ctx, (v, save)),
          ),
          if (offerSave)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: save,
              onChanged: (v) => setState(() => save = v ?? false),
              title: const Text('PIN sicher auf diesem Gerät speichern'),
              subtitle: const Text('Keychain / Keystore – verlässt das Gerät nie'),
            ),
        ]),
      actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, (ctrl.text, save)), child: const Text('Abrufen')),
        ],
      ),
    ),
  );
}

/// Ruft eine Verbindung interaktiv ab. Gibt true bei Erfolg zurück.
Future<bool> syncConnectionInteractive(BuildContext context, WidgetRef ref, BankConnection c, {String? pin, bool? savePin}) async {
  final service = ref.read(bankSyncProvider);
  var thePin = pin;
  var save = savePin ?? c.pinSaved;
  var fresh = pin != null;
  if (thePin == null) {
    thePin = await service.savedPin(c);
    if (thePin == null) {
      if (!context.mounted) return false;
      final r = await askPin(context, c);
      if (r == null || r.$1.isEmpty) return false;
      thePin = r.$1;
      save = r.$2;
      fresh = true;
    }
  }
  try {
    final summary = await service.sync(c, pin: thePin, prompts: DialogPrompts(), savePin: save, freshPin: fresh);
    if (context.mounted) showSnack(context, summary.message);
    return true;
  } on FintsSyncException catch (e) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Abruf ${c.bankName} fehlgeschlagen'),
          content: SingleChildScrollView(child: Text(e.message)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
    return false;
  }
}

/// Alle Bankverbindungen nacheinander abrufen; ohne Verbindungen nur neu analysieren.
Future<void> refreshAll(BuildContext context, WidgetRef ref) async {
  final store = ref.read(storeProvider);
  if (!bankingSupported || store.connections.isEmpty) {
    await ref.read(appStateProvider.notifier).runAnalysis();
    return;
  }
  for (final c in List.of(store.connections)) {
    if (!context.mounted) return;
    await syncConnectionInteractive(context, ref, c);
  }
}
