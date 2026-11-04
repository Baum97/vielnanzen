import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_state.dart';
import '../theme.dart';
import 'onboarding.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(appStateProvider).store;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(children: [
        const SizedBox(height: 8),
        _section(theme, 'Darstellung'),
        SwitchListTile(
          title: const Text('Diskret-Modus'),
          subtitle: const Text('Beträge werden als •••,•• € angezeigt'),
          value: store.settings['discreetMode'] == true,
          onChanged: (v) => _patch(ref, {'discreetMode': v}),
        ),
        ListTile(
          title: const Text('Farbschema'),
          trailing: DropdownButton<String>(
            value: store.settings['darkMode'] as String? ?? 'system',
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'system', child: Text('System')),
              DropdownMenuItem(value: 'light', child: Text('Hell')),
              DropdownMenuItem(value: 'dark', child: Text('Dunkel')),
            ],
            onChanged: (v) => _patch(ref, {'darkMode': v}),
          ),
        ),
        const Divider(),
        _section(theme, 'Sicherheit'),
        SwitchListTile(
          title: const Text('App-Sperre (Biometrie/PIN)'),
          value: store.settings['appLock'] == true,
          onChanged: (v) => _patch(ref, {'appLock': v}),
        ),
        SwitchListTile(
          title: const Text('Im App-Switcher verbergen'),
          value: store.settings['hideInSwitcher'] == true,
          onChanged: (v) => _patch(ref, {'hideInSwitcher': v}),
        ),
        const Divider(),
        _section(theme, 'Daten'),
        ListTile(
          leading: const Icon(Icons.file_upload_outlined),
          title: const Text('Datei importieren'),
          subtitle: const Text('CSV, CAMT.053 oder MT940'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('Analyse neu ausführen'),
          onTap: () => ref.read(appStateProvider.notifier).runAnalysis(),
        ),
        ListTile(
          leading: Icon(Icons.delete_outline, color: AppColors.critical),
          title: Text('Alle Daten löschen', style: TextStyle(color: AppColors.critical)),
          onTap: () => _confirmReset(context, ref),
        ),
        const Divider(),
        _section(theme, 'Rechtliches'),
        ListTile(
          title: const Text('Datenschutzerklärung'),
          subtitle: const Text('Alle Daten bleiben lokal & verschlüsselt auf diesem Gerät.'),
          onTap: () => showAboutDialog(
            context: context,
            applicationName: 'Klarblick',
            applicationVersion: '1.0.0',
            children: const [Text('Klarblick verarbeitet alle Daten ausschließlich lokal und AES-256-GCM-verschlüsselt. Es gibt keine Konten, keine Cloud und keine Tracker. Netzwerkverkehr findet nur bei expliziter Bankverbindung (FinTS) statt und wird im Netzwerk-Log protokolliert.')],
          ),
        ),
        ListTile(
          title: const Text('Lizenz (GPL-3.0)'),
          onTap: () => showLicensePage(context: context, applicationName: 'Klarblick'),
        ),
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _section(ThemeData theme, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(title, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
      );

  void _patch(WidgetRef ref, Map<String, dynamic> patch) {
    final store = ref.read(appStateProvider).store;
    store.updateSettings(patch);
    store.save();
  }

  void _confirmReset(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alle Daten löschen?'),
        content: const Text('Konten, Umsätze, Verträge und Einstellungen werden unwiderruflich gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.critical),
            onPressed: () {
              final store = ref.read(appStateProvider).store;
              store.accounts.clear();
              store.transactions.clear();
              store.contracts.clear();
              store.insights.clear();
              store.budgets.clear();
              store.save();
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }
}
