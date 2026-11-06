import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connectors/fints_connector.dart';
import '../../state/app_state.dart';
import '../app_lock.dart';
import '../theme.dart';
import '../widgets.dart';
import 'accounts_screen.dart';
import 'import_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appStateProvider.select((s) => s.revision));
    final store = ref.read(storeProvider);
    final theme = Theme.of(context);
    final productId = (store.settings['fintsProductId'] as String? ?? '');

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(children: [
        _section(theme, 'Konten'),
        ListTile(
          leading: const Icon(Icons.account_balance_outlined),
          title: const Text('Konten & Banken'),
          subtitle: Text('${store.accounts.length} Konten · ${store.connections.length} Bankverbindungen'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountsScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.file_upload_outlined),
          title: const Text('Kontoauszug importieren'),
          subtitle: const Text('CSV, CAMT oder MT940'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.key_outlined),
          title: const Text('FinTS-Produkt-ID'),
          subtitle: Text(productId.isNotEmpty
              ? productId
              : FintsConnector.buildProductId.isNotEmpty
                  ? 'in der App hinterlegt'
                  : 'nicht gesetzt – nötig für die direkte Bankverbindung'),
          onTap: () => _editProductId(context, ref),
        ),
        const Divider(),
        _section(theme, 'Darstellung'),
        SwitchListTile(
          secondary: const Icon(Icons.visibility_off_outlined),
          title: const Text('Diskret-Modus'),
          subtitle: const Text('Beträge werden als •••,•• € angezeigt'),
          value: store.settings['discreetMode'] == true,
          onChanged: (v) => store.updateSettings({'discreetMode': v}),
        ),
        ListTile(
          leading: const Icon(Icons.dark_mode_outlined),
          title: const Text('Farbschema'),
          trailing: DropdownButton<String>(
            value: store.settings['darkMode'] as String? ?? 'system',
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'system', child: Text('System')),
              DropdownMenuItem(value: 'light', child: Text('Hell')),
              DropdownMenuItem(value: 'dark', child: Text('Dunkel')),
            ],
            onChanged: (v) => store.updateSettings({'darkMode': v}),
          ),
        ),
        const Divider(),
        _section(theme, 'Sicherheit'),
        SwitchListTile(
          secondary: const Icon(Icons.fingerprint),
          title: const Text('App-Sperre'),
          subtitle: const Text('Face ID / Fingerabdruck / Geräte-PIN beim Öffnen'),
          value: store.settings['appLock'] == true,
          onChanged: (v) async {
            if (v) {
              if (!await DeviceAuth.available()) {
                if (context.mounted) showSnack(context, 'Auf diesem Gerät ist keine Displaysperre eingerichtet.');
                return;
              }
              if (!await DeviceAuth.authenticate('App-Sperre aktivieren')) return;
            }
            store.updateSettings({'appLock': v});
          },
        ),
        const Divider(),
        _section(theme, 'Daten'),
        ListTile(
          leading: const Icon(Icons.rule),
          title: const Text('Eigene Kategorie-Regeln'),
          subtitle: Text('${store.rules.length} Regeln'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RulesScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('Analyse neu ausführen'),
          onTap: () async {
            await ref.read(appStateProvider.notifier).runAnalysis();
            if (context.mounted) showSnack(context, 'Analyse abgeschlossen');
          },
        ),
        ListTile(
          leading: const Icon(Icons.public),
          title: const Text('Netzwerk-Protokoll'),
          subtitle: Text('${store.networkLog.length} Verbindungen – nur zu deiner Bank'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NetworkLogScreen())),
        ),
        ListTile(
          leading: Icon(Icons.delete_outline, color: AppColors.neg(context)),
          title: Text('Alle Daten löschen', style: TextStyle(color: AppColors.neg(context))),
          onTap: () => _confirmReset(context, ref),
        ),
        const Divider(),
        _section(theme, 'Rechtliches'),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Datenschutz'),
          subtitle: const Text('Alle Daten bleiben verschlüsselt auf diesem Gerät.'),
          onTap: () => showAboutDialog(
            context: context,
            applicationName: 'Klarblick',
            applicationVersion: '1.1.0',
            children: const [
              Text('Klarblick verarbeitet alle Daten ausschließlich lokal und AES-256-GCM-verschlüsselt; der Schlüssel liegt im '
                  'Keychain bzw. Android-Keystore. Es gibt keine Konten, keine Cloud und keine Tracker. Netzwerkverkehr findet nur '
                  'bei der Bankverbindung (FinTS) statt – direkt zwischen App und Bank – und wird im Netzwerk-Protokoll aufgeführt.'),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.gavel_outlined),
          title: const Text('Lizenzen (GPL-3.0)'),
          onTap: () => showLicensePage(context: context, applicationName: 'Klarblick'),
        ),
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _section(ThemeData theme, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
      );

  Future<void> _editProductId(BuildContext context, WidgetRef ref) async {
    final store = ref.read(storeProvider);
    final ctrl = TextEditingController(text: store.settings['fintsProductId'] as String? ?? '');
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('FinTS-Produkt-ID'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Banken akzeptieren seit 2019 nur registrierte FinTS-Programme. Die Registrierung bei der Deutschen '
              'Kreditwirtschaft ist kostenlos (fints.org → Produktregistrierung, ca. 2 Wochen).'),
          const SizedBox(height: 12),
          TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Produkt-ID')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Speichern')),
        ],
      ),
    );
    if (r != null) store.updateSettings({'fintsProductId': r});
  }

  void _confirmReset(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alle Daten löschen?'),
        content: const Text('Konten, Umsätze, Verträge, gespeicherte PINs und Einstellungen werden unwiderruflich von diesem Gerät gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.neg(context)),
            onPressed: () async {
              await ref.read(storeProvider).wipe();
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            },
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }
}

class RulesScreen extends ConsumerWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appStateProvider.select((s) => s.revision));
    final store = ref.read(storeProvider);
    final engine = ref.read(engineProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Kategorie-Regeln')),
      body: store.rules.isEmpty
          ? const EmptyState(
              icon: Icons.rule,
              text: 'Noch keine Regeln. Ändere bei einem Umsatz die Kategorie und wähle „Alle“ – dann gilt sie auch für künftige Umsätze dieser Firma.',
            )
          : ListView(children: [
              for (final r in store.rules)
                ListTile(
                  title: Text(r.value),
                  subtitle: Text(r.action == 'transfer' ? '→ Umbuchung' : '→ ${engine.categoryById(r.actionValue)?.name ?? r.actionValue}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      store.removeRule(r.id);
                      ref.read(appStateProvider.notifier).runAnalysis();
                    },
                  ),
                ),
            ]),
    );
  }
}

class NetworkLogScreen extends ConsumerWidget {
  const NetworkLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(storeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Netzwerk-Protokoll')),
      body: store.networkLog.isEmpty
          ? const EmptyState(icon: Icons.public_off, text: 'Bisher keine Netzwerkverbindungen.')
          : ListView(children: [
              for (final e in store.networkLog)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.lock_outline, size: 18),
                  title: Text(e.host),
                  subtitle: Text('${AmountFormat.date.format(e.timestamp)} ${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')} · ${e.purpose}'),
                ),
            ]),
    );
  }
}
