import 'package:flutter/material.dart';

import '../../core/import/csv_mapping.dart';
import '../theme.dart';
import '../widgets.dart';

/// Spalten einer unbekannten CSV-Datei zuordnen. Gibt die Zuordnung zurück (oder null bei Abbruch).
class CsvMapperScreen extends StatefulWidget {
  const CsvMapperScreen({super.key, required this.fileName, required this.rows, this.initial, this.guessedHeaderRow = 0});

  final String fileName;
  final List<List<String>> rows;
  final CsvMapping? initial;
  final int guessedHeaderRow;

  @override
  State<CsvMapperScreen> createState() => _CsvMapperScreenState();
}

class _CsvMapperScreenState extends State<CsvMapperScreen> {
  late int _headerRow = widget.initial?.headerRow ?? widget.guessedHeaderRow;
  late CsvMapping _m;
  late bool _split;

  CsvTable get _table => CsvTable(widget.rows, headerRow: _headerRow);

  @override
  void initState() {
    super.initState();
    _m = widget.initial ?? CsvMapping.guess(_table) ?? CsvMapping(headerRow: _headerRow, date: 0);
    _split = _m.debit != null && _m.credit != null && _m.amount == null;
  }

  void _setHeaderRow(int row) {
    final guessed = CsvMapping.guess(CsvTable(widget.rows, headerRow: row));
    setState(() {
      _headerRow = row;
      _m = guessed ?? _m.copyWith(headerRow: row);
      _split = _m.debit != null && _m.credit != null && _m.amount == null;
    });
  }

  String _label(int i) {
    final h = i < _table.headers.length ? _table.headers[i].trim() : '';
    return 'Spalte ${i + 1}${h.isEmpty ? '' : ': $h'}';
  }

  Widget _picker(String label, int? value, ValueChanged<int?> onChanged, {bool optional = true}) {
    final cols = _table.columns;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<int?>(
        key: ValueKey('$label-$value-$_headerRow'),
        initialValue: value != null && value < cols ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          if (optional) const DropdownMenuItem<int?>(value: null, child: Text('– nicht vorhanden –')),
          for (var i = 0; i < cols; i++) DropdownMenuItem<int?>(value: i, child: Text(_label(i), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final table = _table;
    final preview = _m.preview(table, count: 4);
    final good = preview.where((p) => p.date != null && p.cents != null).length;
    final canSave = _m.isValid && good > 0;
    final sample = table.dataRows.take(4).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Spalten zuordnen')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Text('Klarblick kennt das Format von „${widget.fileName}“ noch nicht. Sage ihm einmal, welche Spalte was enthält – '
            'beim nächsten Import derselben Art läuft es automatisch.',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        AppCard(
          title: 'So sieht die Datei aus',
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 40,
              columnSpacing: 20,
              columns: [for (var i = 0; i < table.columns; i++) DataColumn(label: Text('${i + 1}: ${table.headers[i]}', style: theme.textTheme.labelSmall))],
              rows: [
                for (final r in sample)
                  DataRow(cells: [
                    for (var i = 0; i < table.columns; i++)
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(i < r.length ? r[i] : '', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                      )),
                  ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          key: ValueKey('header-$_headerRow'),
          initialValue: _headerRow,
          decoration: const InputDecoration(labelText: 'Kopfzeile (Überschriften)'),
          items: [for (var i = 0; i < widget.rows.length.clamp(1, 12); i++) DropdownMenuItem(value: i, child: Text('Zeile ${i + 1}'))],
          onChanged: (v) => _setHeaderRow(v ?? 0),
        ),
        const SizedBox(height: 12),
        _picker('Datum *', _m.date, (v) => setState(() => _m = _m.copyWith(date: v ?? 0)), optional: false),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('Ein Betrag')),
            ButtonSegment(value: true, label: Text('Soll / Haben')),
          ],
          selected: {_split},
          onSelectionChanged: (s) => setState(() {
            _split = s.first;
            _m = _split ? _m.copyWith(amount: null) : _m.copyWith(debit: null, credit: null);
          }),
        ),
        const SizedBox(height: 12),
        if (!_split)
          _picker('Betrag *', _m.amount, (v) => setState(() => _m = _m.copyWith(amount: v)))
        else ...[
          _picker('Ausgaben (Soll / Abgang) *', _m.debit, (v) => setState(() => _m = _m.copyWith(debit: v))),
          _picker('Einnahmen (Haben / Zugang) *', _m.credit, (v) => setState(() => _m = _m.copyWith(credit: v))),
        ],
        _picker('Empfänger / Name', _m.name, (v) => setState(() => _m = _m.copyWith(name: v))),
        _picker('Verwendungszweck / Beschreibung', _m.purpose, (v) => setState(() => _m = _m.copyWith(purpose: v))),
        _picker('IBAN der Gegenseite', _m.iban, (v) => setState(() => _m = _m.copyWith(iban: v))),
        if (!_split)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Vorzeichen umkehren'),
            subtitle: const Text('Wenn Ausgaben in der Datei positive Zahlen sind'),
            value: _m.invertSign,
            onChanged: (v) => setState(() => _m = _m.copyWith(invertSign: v)),
          ),
        const SizedBox(height: 8),
        AppCard(
          title: 'Vorschau mit dieser Zuordnung',
          child: preview.isEmpty || !_m.isValid
              ? Text('Wähle Datum und Betrag, dann siehst du hier die ersten Umsätze.', style: theme.textTheme.bodySmall)
              : Column(children: [
                  for (final p in preview)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.name.isEmpty ? (p.purpose.isEmpty ? '–' : p.purpose) : p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(p.date == null ? 'Datum nicht lesbar' : AmountFormat.date.format(p.date!)),
                      trailing: p.cents == null
                          ? Text('Betrag nicht lesbar', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.neg(context)))
                          : AmountText(p.cents!, signed: true),
                    ),
                ]),
        ),
        const SizedBox(height: 16),
        PrimaryButton(label: 'Zuordnung übernehmen', onPressed: canSave ? () => Navigator.pop(context, _m) : null),
      ]),
    );
  }
}
