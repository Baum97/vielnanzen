import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/contracts.dart' show stableId;
import '../../core/engine/normalize.dart';
import '../../core/import/csv_mapping.dart';
import '../../core/import/file_import.dart';
import '../../data/bank_directory.dart';
import '../../data/store.dart';
import '../../services/import_service.dart';
import '../../services/incoming_files.dart';
import '../../state/app_state.dart';
import '../../state/bank_directory_provider.dart';
import '../theme.dart';
import '../widgets.dart';
import 'csv_mapper_screen.dart';

/// Eine ausgewählte Datei mit ihrem Ziel.
class _Job {
  _Job(this.name, this.content);

  final String name;
  final String content;
  ParseImport parsed = const ParseImport([]);
  DetectedAccount? detected;

  /// Ziel: ID eines vorhandenen Kontos, [ImportScreenState.newAccount] oder null (noch nicht gewählt).
  String? target;
  bool targetFromUser = false;
  CsvMapping? mapping;

  String newId = '';
  String newIban = '';
  final nameCtrl = TextEditingController();
  final balanceCtrl = TextEditingController();
  bool balanceTouched = false;

  void dispose() {
    nameCtrl.dispose();
    balanceCtrl.dispose();
  }
}

/// Datei-Import: CSV (alle gängigen Bank-Exporte), CAMT.052/053 oder MT940.
/// Das Konto wird aus der Datei erkannt (IBAN); unbekannte CSV-Formate lassen sich einmal
/// zuordnen und werden gemerkt. Dateien, die per „Teilen“ ankommen, werden direkt geladen.
/// Gibt `true` zurück, wenn Umsätze importiert wurden.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key, this.initialFiles = const []});

  final List<IncomingFile> initialFiles;

  @override
  ConsumerState<ImportScreen> createState() => ImportScreenState();
}

class ImportScreenState extends ConsumerState<ImportScreen> {
  static const newAccount = '__new__';
  final _jobs = <_Job>[];
  bool _busy = false;
  BankDirectory? _directory;

  @override
  void initState() {
    super.initState();
    if (widget.initialFiles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addFiles([for (final f in widget.initialFiles) (f.name, f.bytes)]));
    }
  }

  @override
  void dispose() {
    for (final j in _jobs) {
      j.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;
      await _addFiles([for (final f in files) (f.name, await f.readAsBytes())]);
    } catch (e) {
      if (mounted) showSnack(context, 'Datei konnte nicht geöffnet werden: $e');
    }
  }

  Future<void> _addFiles(List<(String, Uint8List)> files) async {
    try {
      _directory ??= await ref.read(bankDirectoryProvider.future);
    } catch (_) {}
    for (final (name, bytes) in files) {
      final job = _Job(name, FileImport.decode(bytes));
      _analyse(job);
      if (mounted) setState(() => _jobs.add(job));
    }
  }

  /// Datei lesen, Konto erkennen, Ziel vorschlagen und mit dem Ziel neu einlesen.
  void _analyse(_Job job, {bool keepTarget = false}) {
    final store = ref.read(storeProvider);
    final profiles = savedMappings(store);
    final probe = FileImport().parse(job.content, accountId: '_', mapping: job.mapping, profiles: profiles);
    job.detected = probe.account;

    if (!keepTarget) {
      final matched = matchAccount(store.accounts, probe.account);
      String? target = matched?.id;
      if (target == null && probe.table != null && probe.account == null) target = savedTarget(store, probe.table!.signature);
      if (target == null && probe.account != null) target = newAccount; // erkannt, aber noch nicht vorhanden
      if (target == null && store.accounts.isEmpty) target = newAccount;
      if (target == null && store.accounts.length == 1) target = store.accounts.first.id;
      job.target = target;
    }

    if (job.target == newAccount) {
      final s = suggestNewAccount(job.detected, _directory, fallbackName: _guessName(job.name));
      if (job.nameCtrl.text.isEmpty) job.nameCtrl.text = s.name;
      job.newIban = s.iban;
      job.newId = s.iban.isNotEmpty ? s.id : (job.newId.isNotEmpty ? job.newId : 'acc_import_${stableId('${job.name}${DateTime.now().microsecondsSinceEpoch}')}');
    }

    final accountId = job.target == newAccount ? job.newId : (job.target ?? '_');
    job.parsed = FileImport().parse(job.content, accountId: accountId, mapping: job.mapping, profiles: profiles);
    final closing = job.parsed.closingBalanceCents;
    if (closing != null && !job.balanceTouched) job.balanceCtrl.text = (closing / 100).toStringAsFixed(2).replaceAll('.', ',');
  }

  /// Kontoname aus dem Dateinamen, falls er eine bekannte Bank nennt (z. B. „trade_republic.csv“).
  static String _guessName(String file) {
    final f = file.toLowerCase();
    if (f.contains('trade') && f.contains('republic') || f.contains('traderepublic')) return 'Trade Republic';
    if (f.contains('n26')) return 'N26';
    if (f.contains('revolut')) return 'Revolut';
    if (f.contains('c24')) return 'C24';
    if (f.contains('bunq')) return 'bunq';
    return 'Importiertes Konto';
  }

  Future<void> _mapColumns(_Job job) async {
    final table = job.parsed.table;
    if (table == null) return;
    final result = await Navigator.of(context).push<CsvMapping>(MaterialPageRoute(
      builder: (_) => CsvMapperScreen(
        fileName: job.name,
        rows: table.rows,
        initial: job.mapping ?? job.parsed.usedMapping,
        guessedHeaderRow: table.headerRow,
      ),
    ));
    if (result == null || !mounted) return;
    setState(() {
      job.mapping = result;
      _analyse(job, keepTarget: job.target != null && job.targetFromUser);
    });
  }

  void _setTarget(_Job job, String? target) {
    setState(() {
      job.target = target;
      job.targetFromUser = true;
      job.balanceTouched = false;
      _analyse(job, keepTarget: true);
    });
  }

  int _newCount(_Job job) {
    final store = ref.read(storeProvider);
    return job.parsed.transactions.where((t) => !store.hasTransactionHash(t.dedupHash)).length;
  }

  bool _ready(_Job job) => job.parsed.error == null && job.parsed.transactions.isNotEmpty && job.target != null;

  Future<void> _import() async {
    final store = ref.read(storeProvider);
    final plans = [
      for (final j in _jobs.where(_ready))
        ImportPlan(
          parsed: j.parsed,
          accountId: j.target == newAccount ? j.newId : j.target!,
          newAccountName: j.target == newAccount ? j.nameCtrl.text : null,
          newAccountIban: j.newIban,
          balanceCents: j.balanceCtrl.text.trim().isEmpty ? null : parseAmountCents(j.balanceCtrl.text),
        ),
    ];
    if (plans.isEmpty) return;
    setState(() => _busy = true);
    final outcome = applyImport(store, plans);
    await store.save();
    await ref.read(appStateProvider.notifier).runAnalysis();
    if (!mounted) return;
    showSnack(context, '${outcome.added} neue Umsätze importiert (${outcome.duplicates} bereits vorhanden)');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = ref.read(storeProvider);
    final ready = _jobs.where(_ready).toList();
    final totalNew = ready.fold<int>(0, (a, j) => a + _newCount(j));

    return Scaffold(
      appBar: AppBar(title: const Text('Kontoauszug importieren')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        if (_jobs.isEmpty) ...[
          Text('Lade die Umsätze deiner Bank als Datei – Klarblick erkennt das Format und das Konto selbst.', style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          PrimaryButton(label: 'Dateien auswählen', icon: Icons.folder_open, onPressed: _pick),
          const SizedBox(height: 20),
          AppCard(
            title: 'Am schnellsten: direkt teilen',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '1. In der Bank-App oder im Online-Banking die Umsätze exportieren (CSV, CAMT oder MT940).\n'
                '2. Auf „Teilen“ tippen und Klarblick wählen.\n'
                '3. Prüfen und auf „Importieren“ tippen – fertig.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                kIsWeb || defaultTargetPlatform != TargetPlatform.android
                    ? 'Das Teilen an Klarblick ist derzeit nur auf Android möglich. Auf anderen Geräten wählst du die Datei hier aus.'
                    : 'Das klappt auch bei Banken ohne FinTS, z. B. Trade Republic, N26 oder Revolut – sofern die Bank-App einen Export anbietet.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          AppCard(
            title: 'Was erkannt wird',
            child: Text(
              '• CSV der gängigen Banken (Sparkasse, ING, DKB, comdirect, N26, Volksbank …)\n'
              '• CAMT.052 / CAMT.053 (XML)\n'
              '• MT940 / MT942\n'
              '• Unbekannte CSV-Formate: Du ordnest die Spalten einmal zu, danach läuft es automatisch.\n'
              '• Mehrere Dateien auf einmal, doppelte Umsätze werden übersprungen.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ] else ...[
          for (final job in _jobs) ...[
            _jobCard(context, job, store),
            const SizedBox(height: 12),
          ],
          TextButton.icon(onPressed: _pick, icon: const Icon(Icons.add), label: const Text('Weitere Datei hinzufügen')),
          const SizedBox(height: 8),
          PrimaryButton(
            label: _busy ? 'Importiere …' : (ready.isEmpty ? 'Importieren' : '$totalNew neue Umsätze importieren'),
            onPressed: _busy || ready.isEmpty || totalNew == 0 ? null : _import,
          ),
          if (ready.isNotEmpty && totalNew == 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Alle Umsätze sind bereits vorhanden – es gibt nichts zu importieren.',
                  style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            ),
        ],
      ]),
    );
  }

  Widget _jobCard(BuildContext context, _Job job, Store store) {
    final theme = Theme.of(context);
    final p = job.parsed;
    final txs = p.transactions;
    DateTime? first, last;
    for (final t in txs) {
      if (first == null || t.bookingDate.isBefore(first)) first = t.bookingDate;
      if (last == null || t.bookingDate.isAfter(last)) last = t.bookingDate;
    }
    final fresh = _newCount(job);
    final detectedLabel = job.detected?.iban ?? job.detected?.key;
    final accountItems = [
      for (final a in store.accounts) DropdownMenuItem<String>(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis)),
      const DropdownMenuItem<String>(value: newAccount, child: Text('+ Neues Konto anlegen')),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(job.name, style: theme.textTheme.headlineMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
            IconButton(
              tooltip: 'Entfernen',
              icon: const Icon(Icons.close),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() {
                _jobs.remove(job);
                job.dispose();
              }),
            ),
          ]),
          if (p.error != null) ...[
            InfoBanner(text: p.error!, color: AppColors.neg(context), icon: Icons.error_outline),
            if (p.needsMapping) ...[
              const SizedBox(height: 8),
              PrimaryButton(label: 'Spalten zuordnen', icon: Icons.view_column_outlined, onPressed: () => _mapColumns(job)),
            ],
          ] else ...[
            Text(
              '${p.format} · ${txs.length} Umsätze · ${AmountFormat.date.format(first!)} – ${AmountFormat.date.format(last!)}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 2),
            Text(
              '$fresh neu${txs.length - fresh > 0 ? ' · ${txs.length - fresh} bereits vorhanden' : ''}'
              '${p.skippedRows > 0 ? ' · ${p.skippedRows} Zeilen übersprungen' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(color: fresh == 0 ? AppColors.warn(context) : theme.colorScheme.secondary),
            ),
            if (detectedLabel != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  Icon(Icons.verified_outlined, size: 16, color: AppColors.pos(context)),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Konto in der Datei erkannt: $detectedLabel', style: theme.textTheme.bodySmall)),
                ]),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('target-${job.name}-${job.target}'),
              initialValue: job.target,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Konto'),
              hint: const Text('Konto wählen'),
              items: accountItems,
              onChanged: (v) => _setTarget(job, v),
            ),
            if (job.target == newAccount) ...[
              const SizedBox(height: 10),
              TextField(controller: job.nameCtrl, decoration: const InputDecoration(labelText: 'Name des neuen Kontos')),
            ],
            if (job.target != null) ...[
              const SizedBox(height: 10),
              TextField(
                controller: job.balanceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                onChanged: (_) => job.balanceTouched = true,
                decoration: InputDecoration(
                  labelText: 'Aktueller Kontostand (optional)',
                  suffixText: '€',
                  helperText: job.target == newAccount ? 'Damit der Saldoverlauf stimmt' : 'Leer lassen, um den bisherigen Stand zu behalten',
                ),
              ),
            ],
            if (p.table != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: () => _mapColumns(job), child: const Text('Spalten anpassen')),
              ),
          ],
        ]),
      ),
    );
  }
}
