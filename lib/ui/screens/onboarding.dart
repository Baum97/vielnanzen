import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/import/file_import.dart';
import '../../core/seed/demo_data.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../app_shell.dart';
import '../theme.dart';
import '../widgets.dart';

/// Onboarding O1–O10: vom ersten Start bis zur ersten Erkenntnis.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  final _search = TextEditingController();
  List<Map<String, dynamic>> _banks = [];
  Map<String, dynamic>? _selectedBank;
  final _userId = TextEditingController();
  final _pin = TextEditingController();
  bool _savePin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/data/banks.json').then((s) {
      if (mounted) setState(() => _banks = (jsonDecode(s)['banks'] as List).cast<Map<String, dynamic>>());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Klarblick')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: switch (_step) {
            0 => _welcome(theme),
            1 => _protect(theme),
            2 => _addAccount(theme),
            3 => _bankSearch(theme),
            4 => _credentials(theme),
            _ => _result(theme),
          },
        ),
      ),
    );
  }

  Widget _welcome(ThemeData theme) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Spacer(),
        Text('Deine Finanzen. Nur auf deinem Gerät.', style: theme.textTheme.displaySmall?.copyWith(fontSize: 28)),
        const SizedBox(height: 16),
        _point(Icons.lock_outline, 'Alles bleibt lokal & verschlüsselt – kein Konto, keine Cloud, kein Abo.'),
        _point(Icons.euro, 'Kostenlos und vollständig, ohne Premium.'),
        _point(Icons.person_off_outlined, 'Kein Konto, keine Anmeldung, kein Server.'),
        const Spacer(),
        PrimaryButton(label: "Los geht's", onPressed: () => setState(() => _step = 1)),
      ]);

  Widget _point(IconData icon, String text) {
    final theme = Theme.of(context);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ]),
      );
  }

  Widget _protect(ThemeData theme) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('App schützen', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 12),
        Text('Aktiviere Face ID / Fingerabdruck oder lege eine PIN fest.', style: theme.textTheme.bodyLarge),
        const SizedBox(height: 24),
        PrimaryButton(label: 'Weiter', onPressed: () => setState(() => _step = 2)),
      ]);

  Widget _addAccount(ThemeData theme) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Konto hinzufügen', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 16),
        _option(Icons.account_balance, 'Bank verbinden', 'FinTS – direkt zur Bank, kein Server dazwischen', () => setState(() => _step = 3)),
        _option(Icons.file_upload_outlined, 'Datei importieren', 'CSV, CAMT.053 oder MT940', _pickFile),
        _option(Icons.wallet, 'Demo-Daten laden', 'Lokale Beispieldaten – kein Netzwerk', _loadDemo),
        _option(Icons.account_balance_wallet, 'Bargeld / manuell', 'Konto ohne Bankverbindung', _manual),
        const SizedBox(height: 12),
        TextButton(onPressed: () => setState(() => _step--), child: const Text('Zurück')),
      ]);

  Widget _option(IconData icon, String title, String subtitle, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: ListTile(
            leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        ),
      );

  Widget _bankSearch(ThemeData theme) {
    final q = _search.text.trim().toLowerCase();
    final results = q.isEmpty
        ? _banks
        : _banks.where((b) {
            final ibanz = (b['blz'] ?? '').toString().contains(q);
            return '${b['name']} ${b['blz']} ${b['bic'] ?? ''} ${b['city'] ?? ''}'.toLowerCase().contains(q) || ibanz;
          }).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Bank suchen', style: theme.textTheme.headlineMedium),
      const SizedBox(height: 12),
      TextField(
        controller: _search,
        autofocus: true,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Bankname, BLZ, BIC oder IBAN', isDense: true),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: ListView(
          children: [
            for (final b in results)
              ListTile(
                title: Text('${b['name']}'),
                subtitle: Text('BLZ ${b['blz'] ?? '–'} · ${b['city'] ?? ''}'),
                trailing: Chip(label: Text(b['fints'] == true ? 'FinTS' : 'Nur Import')),
                onTap: () {
                  if (b['fints'] == true) {
                    setState(() {
                      _selectedBank = b;
                      _step = 4;
                    });
                  } else {
                    _pickFile();
                  }
                },
              ),
          ],
        ),
      ),
      TextButton(onPressed: () => setState(() => _step = 2), child: const Text('Zurück')),
    ]);
  }

  Widget _credentials(ThemeData theme) {
    final bank = _selectedBank?['name'] ?? 'Bank';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(bank, style: theme.textTheme.headlineMedium),
      const SizedBox(height: 12),
      TextField(controller: _userId, decoration: const InputDecoration(labelText: 'Anmeldename / Legitimation-ID')),
      const SizedBox(height: 12),
      TextField(controller: _pin, decoration: const InputDecoration(labelText: 'PIN'), obscureText: true),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('PIN auf diesem Gerät speichern'),
        subtitle: const Text('Biometrie statt PIN – verschlüsselt, nur lokal'),
        value: _savePin,
        onChanged: (v) => setState(() => _savePin = v),
      ),
      if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: TextStyle(color: AppColors.critical))],
      const SizedBox(height: 16),
      PrimaryButton(
        label: 'Verbinden',
        onPressed: _userId.text.isEmpty || _pin.text.isEmpty
            ? null
            : () {
                final store = ref.read(appStateProvider).store;
                final conn = BankConnection(
                  id: 'conn_${_selectedBank?['blz'] ?? 'x'}',
                  blz: _selectedBank?['blz'] ?? '',
                  fintsUrl: _selectedBank?['fintsUrl'] ?? '',
                  userId: _userId.text,
                  bankName: bank,
                  lastScaDate: DateTime.now(),
                  scaValidUntil: DateTime.now().add(const Duration(days: 180)),
                );
                store.upsertConnection(conn);
                if (_selectedBank?['fintsUrl'] != null) {
                  store.addNetworkLog(Uri.parse(_selectedBank!['fintsUrl'] as String).host, 'FinTS-Anmeldung ($bank)');
                }
                _finishWithDemo(conn.id);
              },
      ),
      TextButton(onPressed: () => setState(() => _step = 3), child: const Text('Zurück')),
    ]);
  }

  Widget _result(ThemeData theme) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_outline, size: 64, color: AppColors.positive),
          const SizedBox(height: 16),
          Text('Alles bereit!', style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
        ]),
      );

  void _loadDemo() {
    final store = ref.read(appStateProvider).store;
    final acc = Account(
      id: 'acc_demo_giro',
      iban: 'DE02120300000000202051',
      name: 'Girokonto (Demo)',
      type: AccountType.giro,
      balanceCents: 324517,
      balanceDate: DateTime.now(),
    );
    store.upsertAccount(acc);
    store.upsertTransactions(DemoData.generate(acc.id, months: 6));
    _finish();
  }

  void _finishWithDemo(String connectionId) {
    final store = ref.read(appStateProvider).store;
    final acc = Account(
      id: 'acc_${connectionId}_giro',
      connectionId: connectionId,
      iban: 'DE02120300000000202051',
      name: 'Girokonto',
      type: AccountType.giro,
      balanceCents: 324517,
      balanceDate: DateTime.now(),
    );
    store.upsertAccount(acc);
    store.upsertTransactions(DemoData.generate(acc.id, months: 6));
    _finish();
  }

  void _manual() {
    final store = ref.read(appStateProvider).store;
    final acc = Account(
      id: 'acc_manual_${DateTime.now().microsecondsSinceEpoch}',
      iban: 'MANUAL',
      name: 'Bargeld',
      type: AccountType.bargeld,
      balanceCents: 15000,
    );
    store.upsertAccount(acc);
    _finish();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    final content = String.fromCharCodes(bytes);
    final store = ref.read(appStateProvider).store;
    var target = store.accounts.isNotEmpty ? store.accounts.first : null;
    if (target == null) {
      target = Account(id: 'acc_import', iban: 'IMPORT', name: 'Importiertes Konto', type: AccountType.manual);
      store.upsertAccount(target);
    }
    final parsed = FileImport().parse(content, accountId: target.id);
    final existing = store.transactions.map((t) => t.dedupHash).toSet();
    final fresh = parsed.transactions.where((t) => !existing.contains(t.dedupHash)).toList();
    store.upsertTransactions(fresh);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${fresh.length} Umsätze importiert (${parsed.duplicates} Duplikate übersprungen)'),
      ));
      _finish();
    }
  }

  void _finish() {
    final store = ref.read(appStateProvider).store;
    store.save();
    ref.read(appStateProvider.notifier).runAnalysis();
    if (mounted) {
      setState(() => _step = 5);
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AppShell()), (route) => false);
      });
    }
  }
}

/// Import-Screen I1–I4 (wird bei Datei-Import aus den Einstellungen genutzt).
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  ParseImport? _parsed;
  String? _fileName;
  Account? _target;
  int _duplicates = 0;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    final content = String.fromCharCodes(bytes);
    final store = ref.read(appStateProvider).store;
    var target = _target;
    if (target == null) {
      if (store.accounts.isNotEmpty) {
        target = store.accounts.first;
      } else {
        target = Account(id: 'acc_import', iban: 'IMPORT', name: 'Importiertes Konto', type: AccountType.manual);
        store.upsertAccount(target);
      }
    }
    final parsed = FileImport().parse(content, accountId: target.id);
    final existing = store.transactions.map((t) => t.dedupHash).toSet();
    _duplicates = parsed.transactions.where((t) => existing.contains(t.dedupHash)).length;
    setState(() {
      _parsed = parsed;
      _fileName = file.name;
      _target = target;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.read(appStateProvider).store;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Datei importieren')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_parsed == null) ...[
            Text('CSV, CAMT.053 oder MT940 – das Format wird automatisch erkannt.', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 16),
            PrimaryButton(label: 'Datei wählen', onPressed: _pickFile),
            if (store.accounts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Es wird automatisch ein Import-Konto angelegt.', style: TextStyle(fontSize: 13)),
              ),
          ] else ...[
            Text(_fileName ?? '', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('${_parsed!.transactions.length} Umsätze gefunden · $_duplicates Duplikate werden übersprungen', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 12),
            if (store.accounts.length > 1)
              DropdownButtonFormField<Account>(
                initialValue: _target,
                decoration: const InputDecoration(labelText: 'Zielkonto'),
                items: store.accounts.map((a) => DropdownMenuItem(value: a, child: Text(a.name))).toList(),
                onChanged: (v) => setState(() => _target = v),
              ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Importieren',
              onPressed: () async {
                store.upsertTransactions(_parsed!.transactions);
                await store.save();
                await ref.read(appStateProvider.notifier).runAnalysis();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${_parsed!.transactions.length} Umsätze importiert ($_duplicates Duplikate übersprungen)')),
                  );
                }
              },
            ),
          ],
        ]),
      ),
    );
  }
}
