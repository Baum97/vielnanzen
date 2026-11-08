import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_state.dart';
import '../app_lock.dart';
import '../bank/sync_ui.dart';
import '../widgets.dart';
import 'accounts_screen.dart';
import 'bank_connect.dart';
import 'import_screen.dart';

/// Onboarding: Willkommen → App schützen → erstes Konto hinzufügen.
/// Sobald ein Konto existiert, wechselt die App automatisch zur Übersicht.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: switch (_step) {
              0 => _welcome(theme),
              1 => _protect(theme),
              _ => _addAccount(theme),
            },
          ),
        ),
      ),
    );
  }

  Widget _welcome(ThemeData theme) => Column(key: const ValueKey(0), crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Spacer(),
        Icon(Icons.insights, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 20),
        Text('Wissen, wo dein Geld hingeht.', style: theme.textTheme.displaySmall),
        const SizedBox(height: 20),
        _point(Icons.account_balance_outlined, 'Konten verbinden – Einnahmen und Ausgaben automatisch im Blick.'),
        _point(Icons.donut_large_outlined, 'Wofür, wo und wann: Kategorien, Firmen und Verläufe von 1 Woche bis 5 Jahre.'),
        _point(Icons.savings_outlined, 'Abos, Preiserhöhungen und Sparpotenzial automatisch erkannt.'),
        _point(Icons.lock_outline, 'Alles bleibt verschlüsselt auf deinem Gerät – kein Konto, keine Cloud, kein Tracking.'),
        const Spacer(),
        PrimaryButton(label: "Los geht's", onPressed: () => setState(() => _step = 1)),
      ]);

  Widget _point(IconData icon, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
      ]),
    );
  }

  Widget _protect(ThemeData theme) => Column(key: const ValueKey(1), crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Spacer(),
        Icon(Icons.fingerprint, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 20),
        Text('App schützen', style: theme.textTheme.displaySmall),
        const SizedBox(height: 12),
        Text('Mit Face ID, Fingerabdruck oder Geräte-PIN sieht niemand außer dir deine Finanzen.', style: theme.textTheme.bodyLarge),
        const Spacer(),
        PrimaryButton(
          label: 'App-Sperre aktivieren',
          icon: Icons.lock_outline,
          onPressed: () async {
            final store = ref.read(storeProvider);
            if (await DeviceAuth.available() && await DeviceAuth.authenticate('App-Sperre aktivieren')) {
              store.updateSettings({'appLock': true});
            } else if (mounted) {
              showSnack(context, 'Keine Displaysperre verfügbar – du kannst sie später in den Einstellungen aktivieren.');
            }
            if (mounted) setState(() => _step = 2);
          },
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: () => setState(() => _step = 2), child: const Center(child: Text('Später'))),
      ]);

  Widget _addAccount(ThemeData theme) => ListView(key: const ValueKey(2), children: [
        const SizedBox(height: 24),
        Text('Erstes Konto hinzufügen', style: theme.textTheme.displaySmall),
        const SizedBox(height: 20),
        _option(
          Icons.account_balance_outlined,
          'Bank verbinden',
          bankingSupported ? 'FinTS – direkt zur Bank, kein Server dazwischen' : 'nur in der Android-/iOS-App',
          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BankConnectScreen())),
        ),
        _option(
          Icons.file_upload_outlined,
          'Kontoauszug importieren',
          'CSV, CAMT oder MT940 aus dem Online-Banking',
          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportScreen())),
        ),
        _option(Icons.auto_awesome_outlined, 'Erst mal ausprobieren', '5 Jahre Demo-Daten – rein lokal', () async {
          setState(() => _busy = true);
          await loadDemoData(ref);
          if (mounted) setState(() => _busy = false);
        }),
        _option(Icons.payments_outlined, 'Bargeld / manuelles Konto', 'Ohne Bankverbindung', () => addManualAccount(context, ref)),
        if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        const SizedBox(height: 12),
        TextButton(onPressed: () => setState(() => _step = 1), child: const Text('Zurück')),
      ]);

  Widget _option(IconData icon, String title, String subtitle, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : onTap,
          ),
        ),
      );
}
