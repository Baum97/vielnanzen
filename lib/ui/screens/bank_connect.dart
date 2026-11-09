import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connectors/fints_connector.dart';
import '../../core/engine/contracts.dart';
import '../../data/bank_directory.dart';
import '../../data/models.dart';
import '../../services/bank_sync.dart';
import '../../state/app_state.dart';
import '../../state/bank_directory_provider.dart';
import '../bank/sync_ui.dart';
import '../theme.dart';
import '../widgets.dart';
import 'import_screen.dart';

/// Bank verbinden: Bank suchen → Zugangsdaten → Abruf (FinTS, direkt zur Bank).
/// Gibt `true` zurück, wenn Konten abgerufen wurden.
class BankConnectScreen extends ConsumerStatefulWidget {
  const BankConnectScreen({super.key});

  @override
  ConsumerState<BankConnectScreen> createState() => _BankConnectScreenState();
}

class _BankConnectScreenState extends ConsumerState<BankConnectScreen> {
  final _search = TextEditingController();
  Map<String, dynamic>? _bank;

  final _blz = TextEditingController();
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _customer = TextEditingController();
  final _pin = TextEditingController();
  final _product = TextEditingController();
  bool _savePin = false;
  bool _busy = false;
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    _product.text = ref.read(bankSyncProvider).productId;
  }

  @override
  void dispose() {
    for (final c in [_search, _blz, _url, _user, _customer, _pin, _product]) {
      c.dispose();
    }
    super.dispose();
  }

  void _selectEntry(BankEntry e) => _select({'name': e.name, 'blz': e.blz, 'fintsUrl': e.url, 'city': e.city});

  void _select(Map<String, dynamic> b) {
    setState(() {
      _bank = b;
      _blz.text = (b['blz'] as String?) ?? '';
      _url.text = (b['fintsUrl'] as String?) ?? '';
      _advanced = (b['urlRequired'] == true) || _url.text.isEmpty;
    });
  }

  Future<void> _connect() async {
    final store = ref.read(storeProvider);
    if (_product.text.trim() != (store.settings['fintsProductId'] as String? ?? '') && _product.text.trim().isNotEmpty) {
      store.updateSettings({'fintsProductId': _product.text.trim()});
    }
    final blz = _blz.text.replaceAll(' ', '');
    final conn = BankConnection(
      id: 'conn_${blz}_${stableId(_user.text.trim())}',
      blz: blz,
      fintsUrl: _url.text.trim(),
      userId: _user.text.trim(),
      customerId: _customer.text.trim().isEmpty ? null : _customer.text.trim(),
      bankName: (_bank?['name'] as String?) ?? 'Bank $blz',
    );
    final existed = store.connectionById(conn.id) != null;
    if (!existed) store.upsertConnection(conn);
    setState(() => _busy = true);
    final ok = await syncConnectionInteractive(context, ref, store.connectionById(conn.id) ?? conn, pin: _pin.text, savePin: _savePin);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Navigator.of(context).pop(true);
    } else if (!existed && !store.accounts.any((a) => a.connectionId == conn.id)) {
      // Fehlgeschlagene Ersteinrichtung nicht als Leiche zurücklassen
      store.connections.removeWhere((c) => c.id == conn.id);
      store.updateSettings({});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_bank == null ? 'Bank verbinden' : (_bank!['name'] as String)),
        leading: _bank == null ? null : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _bank = null)),
      ),
      body: !bankingSupported
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                InfoBanner(
                  text: 'Die direkte Bankverbindung (FinTS) funktioniert nur in der Android- und iOS-App – Browser blockieren '
                      'die Verbindung zur Bank. Im Web kannst du Kontoauszüge als Datei importieren.',
                  color: AppColors.warn(context),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Datei importieren',
                  onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ImportScreen())),
                ),
              ]),
            )
          : _bank == null
              ? _searchView(theme)
              : _credentialsView(theme),
    );
  }

  Widget _searchView(ThemeData theme) {
    final directory = ref.watch(bankDirectoryProvider);
    final noFints = ref.watch(noFintsBanksProvider).value ?? const <NoFintsBank>[];
    final q = _search.text.trim();
    final fold = BankDirectory.fold(q);
    final dir = directory.value;
    final results = dir == null ? const <BankEntry>[] : dir.search(q);
    final noFintsHits = q.isEmpty ? noFints : noFints.where((b) => BankDirectory.fold(b.name).contains(fold)).toList();
    final looksLikeBlz = RegExp(r'^\d{8}$').hasMatch(q.replaceAll(' ', ''));

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: TextField(
          controller: _search,
          autofocus: true,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Bankname, Ort, BLZ oder IBAN', isDense: true),
          onChanged: (_) => setState(() {}),
        ),
      ),
      Expanded(
        child: directory.isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(children: [
                if (q.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text(
                      'Tippe den Namen deiner Bank ein oder füge deine IBAN ein – Klarblick findet die Bank und trägt die '
                      'FinTS-Adresse automatisch ein.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                for (final b in results)
                  ListTile(
                    leading: Avatar(label: b.name, color: theme.colorScheme.primary, size: 36),
                    title: Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('BLZ ${b.blz}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _selectEntry(b),
                  ),
                for (final b in noFintsHits)
                  ListTile(
                    leading: Avatar(label: b.name, color: theme.colorScheme.secondary, size: 36),
                    title: Text(b.name),
                    subtitle: const Text('Kein FinTS – Datei-Import'),
                    trailing: const Chip(label: Text('Datei'), visualDensity: VisualDensity.compact),
                    onTap: () => _noFints(b),
                  ),
                if (q.isNotEmpty && results.isEmpty && noFintsHits.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: InfoBanner(
                      text: looksLikeBlz
                          ? 'Zu dieser BLZ ist keine FinTS-Adresse bekannt. Du kannst sie selbst eintragen oder die Umsätze als Datei importieren.'
                          : 'Keine Bank gefunden. Versuche den Ort, die BLZ oder deine IBAN – oder trage die Daten selbst ein.',
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Daten selbst eintragen'),
                  subtitle: const Text('BLZ und FinTS-Adresse manuell'),
                  onTap: () => _select({'name': 'Meine Bank', 'blz': looksLikeBlz ? q.replaceAll(' ', '') : '', 'fintsUrl': '', 'urlRequired': true}),
                ),
                ListTile(
                  leading: const Icon(Icons.upload_file_outlined),
                  title: const Text('Stattdessen Datei importieren'),
                  subtitle: const Text('Funktioniert mit jeder Bank'),
                  onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ImportScreen())),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Klarblick verbindet sich per FinTS direkt mit deiner Bank – ohne Server dazwischen. '
                    'Deine Zugangsdaten verlassen das Gerät nur in Richtung deiner Bank. '
                    'Bankenliste: hbci4java (LGPL-2.1); Adressen können veraltet sein und sind änderbar.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary),
                  ),
                ),
              ]),
      ),
    ]);
  }

  void _noFints(NoFintsBank bank) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(bank.name),
        content: Text('${bank.note}\n\nExportiere deine Umsätze in der Bank-App als CSV (oder CAMT/MT940) und teile die Datei '
            'direkt an Klarblick („Teilen → Klarblick“) oder wähle sie hier aus.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ImportScreen()));
            },
            child: const Text('Datei auswählen'),
          ),
        ],
      ),
    );
  }

  Widget _credentialsView(ThemeData theme) {
    final hint = _bank?['hint'] as String?;
    final needsProduct = _product.text.trim().isEmpty && FintsConnector.buildProductId.isEmpty;
    final canConnect = !_busy &&
        _user.text.trim().isNotEmpty &&
        _pin.text.isNotEmpty &&
        RegExp(r'^\d{8}$').hasMatch(_blz.text.replaceAll(' ', '')) &&
        _url.text.trim().startsWith('https://') &&
        _product.text.trim().isNotEmpty;
    return ListView(padding: const EdgeInsets.all(20), children: [
      if (hint != null) ...[InfoBanner(text: hint, color: theme.colorScheme.primary), const SizedBox(height: 12)],
      TextField(
        controller: _user,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Anmeldename / Legitimations-ID'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _pin,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Online-Banking-PIN'),
        onChanged: (_) => setState(() {}),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('PIN sicher auf dem Gerät speichern'),
        subtitle: const Text('Im Keychain/Keystore – für Abrufe ohne erneute Eingabe'),
        value: _savePin,
        onChanged: (v) => setState(() => _savePin = v),
      ),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: _advanced || needsProduct,
        title: const Text('Bankdaten & FinTS'),
        subtitle: Text('BLZ ${_blz.text.isEmpty ? '–' : _blz.text}', style: theme.textTheme.bodySmall),
        children: [
          TextField(
            controller: _blz,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Bankleitzahl (8 Ziffern)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'FinTS-Adresse (https://…)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(controller: _customer, decoration: const InputDecoration(labelText: 'Kunden-ID (nur falls von der Bank verlangt)')),
          const SizedBox(height: 12),
          TextField(
            controller: _product,
            decoration: const InputDecoration(
              labelText: 'FinTS-Produkt-ID',
              helperText: 'Kostenlose Registrierung: fints.org → Produktregistrierung',
              helperMaxLines: 2,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
        ],
      ),
      const SizedBox(height: 16),
      PrimaryButton(label: _busy ? 'Verbinde …' : 'Verbinden & Umsätze abrufen', onPressed: canConnect ? _connect : null),
      const SizedBox(height: 12),
      Text(
        'Beim ersten Abruf fragt deine Bank meist eine Freigabe ab (pushTAN, photoTAN …). '
        'Es werden bis zu 5 Jahre Umsätze geladen – so weit deine Bank sie bereitstellt.',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary),
      ),
    ]);
  }
}
