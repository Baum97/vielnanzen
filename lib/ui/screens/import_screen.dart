import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/normalize.dart';
import '../../core/import/file_import.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Datei-Import: CSV (alle gängigen Bank-Exporte), CAMT.052/053 oder MT940.
/// Gibt `true` zurück, wenn Umsätze importiert wurden.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  static const _newAccount = '__new__';
  ParseImport? _parsed;
  String? _fileName;
  String? _content;
  String _target = _newAccount;
  String? _error;
  bool _busy = false;
  final _accountName = TextEditingController(text: 'Girokonto');
  final _balance = TextEditingController();

  @override
  void initState() {
    super.initState();
    final accounts = ref.read(storeProvider).accounts;
    if (accounts.isNotEmpty) _target = accounts.first.id;
  }

  @override
  void dispose() {
    _accountName.dispose();
    _balance.dispose();
    super.dispose();
  }

  String get _targetId => _target == _newAccount ? 'acc_import_${stableHashFor(_accountName.text)}' : _target;

  static String stableHashFor(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

  Future<void> _pick() async {
    setState(() => _error = null);
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;
      final f = files.first;
      final bytes = await f.readAsBytes();
      _content = FileImport.decode(bytes);
      _fileName = f.name;
      _reparse();
    } catch (e) {
      setState(() => _error = 'Datei konnte nicht geöffnet werden: $e');
    }
  }

  void _reparse() {
    if (_content == null) return;
    final parsed = FileImport().parse(_content!, accountId: _targetId);
    setState(() {
      _parsed = parsed;
      _error = parsed.error;
      if (parsed.closingBalanceCents != null && _balance.text.isEmpty) {
        _balance.text = (parsed.closingBalanceCents! / 100).toStringAsFixed(2).replaceAll('.', ',');
      }
    });
  }

  Future<void> _import() async {
    final store = ref.read(storeProvider);
    final parsed = _parsed;
    if (parsed == null || parsed.transactions.isEmpty) return;
    setState(() => _busy = true);
    final balance = parseAmountCents(_balance.text);
    var added = 0;
    store.batch(() {
      if (_target == _newAccount) {
        store.upsertAccount(Account(
          id: _targetId,
          iban: '',
          name: _accountName.text.trim().isEmpty ? 'Importiertes Konto' : _accountName.text.trim(),
          type: AccountType.manual,
          balanceCents: balance ?? parsed.transactions.fold<int>(0, (a, t) => a + t.amountCents),
          balanceDate: DateTime.now(),
          lastSync: DateTime.now(),
        ));
      } else if (balance != null) {
        final acc = store.accountById(_target);
        if (acc != null) store.upsertAccount(acc.copyWith(balanceCents: balance, balanceDate: DateTime.now(), lastSync: DateTime.now()));
      }
      added = store.upsertTransactions(parsed.transactions);
    });
    await store.save();
    await ref.read(appStateProvider.notifier).runAnalysis();
    if (!mounted) return;
    showSnack(context, '$added neue Umsätze importiert (${parsed.transactions.length - added} bereits vorhanden)');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.read(storeProvider);
    final theme = Theme.of(context);
    final p = _parsed;
    final txs = p?.transactions ?? const <Transaction>[];
    final dups = txs.where((t) => store.hasTransactionHash(t.dedupHash)).length;
    DateTime? first, last;
    for (final t in txs) {
      if (first == null || t.bookingDate.isBefore(first)) first = t.bookingDate;
      if (last == null || t.bookingDate.isAfter(last)) last = t.bookingDate;
    }
    final inSum = txs.where((t) => t.amountCents > 0).fold<int>(0, (a, t) => a + t.amountCents);
    final outSum = txs.where((t) => t.amountCents < 0).fold<int>(0, (a, t) => a - t.amountCents);

    return Scaffold(
      appBar: AppBar(title: const Text('Datei importieren')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('So geht’s: Im Online-Banking deiner Bank die Umsätze als CSV, CAMT oder MT940 exportieren und hier auswählen. '
            'Das Format wird automatisch erkannt. Die Datei verlässt dein Gerät nicht.',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        PrimaryButton(label: _fileName == null ? 'Datei wählen' : 'Andere Datei wählen', icon: Icons.folder_open, onPressed: _pick),
        if (_error != null) ...[
          const SizedBox(height: 12),
          InfoBanner(text: _error!, color: AppColors.neg(context), icon: Icons.error_outline),
        ],
        if (p != null && txs.isNotEmpty) ...[
          const SizedBox(height: 20),
          AppCard(
            title: _fileName,
            subtitle: 'Format: ${p.format}',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${txs.length} Umsätze · ${AmountFormat.date.format(first!)} – ${AmountFormat.date.format(last!)}', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text('Eingänge ${AmountFormat.format(inSum)} · Ausgänge ${AmountFormat.format(outSum)}', style: theme.textTheme.bodySmall),
              if (dups > 0) Text('$dups bereits vorhanden – werden übersprungen', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.warn(context))),
              if (p.skippedRows > 0)
                Text('${p.skippedRows} Zeilen ohne Datum/Betrag ignoriert', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary)),
            ]),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _target,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Zielkonto'),
            items: [
              for (final a in store.accounts) DropdownMenuItem(value: a.id, child: Text(a.name)),
              const DropdownMenuItem(value: _newAccount, child: Text('+ Neues Konto anlegen')),
            ],
            onChanged: (v) {
              setState(() => _target = v ?? _newAccount);
              _reparse();
            },
          ),
          if (_target == _newAccount) ...[
            const SizedBox(height: 12),
            TextField(controller: _accountName, decoration: const InputDecoration(labelText: 'Name des Kontos'), onChanged: (_) => _reparse()),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _balance,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(
              labelText: 'Aktueller Kontostand (optional)',
              suffixText: '€',
              helperText: 'Damit der Saldoverlauf stimmt',
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(label: _busy ? 'Importiere …' : '${txs.length - dups} Umsätze importieren', onPressed: _busy || txs.length == dups ? null : _import),
        ],
      ]),
    );
  }
}
