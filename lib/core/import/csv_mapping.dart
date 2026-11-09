import 'dart:math' as math;

import '../engine/contracts.dart' show stableId;
import '../engine/normalize.dart';

String _norm(String h) => h
    .toLowerCase()
    .replaceAll('ä', 'ae')
    .replaceAll('ö', 'oe')
    .replaceAll('ü', 'ue')
    .replaceAll('ß', 'ss')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

/// Eine eingelesene CSV-Datei mit geschätzter Kopfzeile.
class CsvTable {
  CsvTable(this.rows, {int? headerRow}) : headerRow = headerRow ?? guessHeaderRow(rows);

  final List<List<String>> rows;
  final int headerRow;

  List<String> get headers => rows.isEmpty ? const [] : rows[headerRow];
  List<List<String>> get dataRows => rows.length > headerRow + 1 ? rows.sublist(headerRow + 1) : const [];
  int get columns => headers.length;

  /// Erkennt Dateien mit gleichem Aufbau wieder (für gemerkte Spaltenzuordnungen).
  String get signature => stableId('$columns:${headers.map(_norm).join('|')}');

  /// Kopfzeile = erste Zeile mit überwiegend Text, direkt gefolgt von einer Zeile mit Datum.
  static int guessHeaderRow(List<List<String>> rows) {
    for (var i = 0; i < math.min(rows.length - 1, 40); i++) {
      final r = rows[i];
      if (r.length < 3) continue;
      final filled = r.where((c) => c.trim().isNotEmpty).toList();
      if (filled.length < 3) continue;
      final texty = filled.where((c) => parseDate(c) == null && parseAmountCents(c) == null).length;
      if (texty / filled.length < 0.6) continue;
      if (rows[i + 1].any((c) => parseDate(c) != null)) return i;
    }
    return 0;
  }
}

/// Zuordnung der Spalten einer CSV-Datei zu den Feldern eines Umsatzes.
class CsvMapping {
  const CsvMapping({
    required this.headerRow,
    required this.date,
    this.amount,
    this.debit,
    this.credit,
    this.name,
    this.purpose,
    this.iban,
    this.invertSign = false,
  });

  final int headerRow;
  final int date;

  /// Ein Betragsspalte mit Vorzeichen – oder getrennte Soll-/Haben-Spalten.
  final int? amount;
  final int? debit;
  final int? credit;
  final int? name;
  final int? purpose;
  final int? iban;

  /// Manche Exporte führen Ausgaben als positive Zahlen.
  final bool invertSign;

  bool get isValid => amount != null || (debit != null && credit != null);

  /// Die ersten Zeilen, wie sie mit dieser Zuordnung gelesen würden (für die Vorschau).
  List<({DateTime? date, int? cents, String name, String purpose})> preview(CsvTable table, {int count = 3}) {
    String cell(List<String> r, int? c) => c == null || c < 0 || c >= r.length ? '' : r[c].trim();
    final out = <({DateTime? date, int? cents, String name, String purpose})>[];
    for (final r in table.rows.skip(headerRow + 1)) {
      int? cents;
      if (amount != null) {
        cents = parseAmountCents(cell(r, amount));
      } else if (debit != null && credit != null) {
        final d = parseAmountCents(cell(r, debit)) ?? 0;
        final c = parseAmountCents(cell(r, credit)) ?? 0;
        cents = c != 0 ? c.abs() : (d != 0 ? -d.abs() : null);
      }
      if (cents != null && invertSign) cents = -cents;
      out.add((date: parseDate(cell(r, date)), cents: cents, name: cell(r, name), purpose: cell(r, purpose)));
      if (out.length >= count) break;
    }
    return out;
  }

  CsvMapping copyWith({
    int? headerRow,
    int? date,
    Object? amount = _keep,
    Object? debit = _keep,
    Object? credit = _keep,
    Object? name = _keep,
    Object? purpose = _keep,
    Object? iban = _keep,
    bool? invertSign,
  }) =>
      CsvMapping(
        headerRow: headerRow ?? this.headerRow,
        date: date ?? this.date,
        amount: identical(amount, _keep) ? this.amount : amount as int?,
        debit: identical(debit, _keep) ? this.debit : debit as int?,
        credit: identical(credit, _keep) ? this.credit : credit as int?,
        name: identical(name, _keep) ? this.name : name as int?,
        purpose: identical(purpose, _keep) ? this.purpose : purpose as int?,
        iban: identical(iban, _keep) ? this.iban : iban as int?,
        invertSign: invertSign ?? this.invertSign,
      );

  static const _keep = Object();

  Map<String, dynamic> toJson() => {
        'headerRow': headerRow,
        'date': date,
        'amount': amount,
        'debit': debit,
        'credit': credit,
        'name': name,
        'purpose': purpose,
        'iban': iban,
        'invertSign': invertSign,
      };

  factory CsvMapping.fromJson(Map<String, dynamic> j) => CsvMapping(
        headerRow: (j['headerRow'] as num?)?.toInt() ?? 0,
        date: (j['date'] as num).toInt(),
        amount: (j['amount'] as num?)?.toInt(),
        debit: (j['debit'] as num?)?.toInt(),
        credit: (j['credit'] as num?)?.toInt(),
        name: (j['name'] as num?)?.toInt(),
        purpose: (j['purpose'] as num?)?.toInt(),
        iban: (j['iban'] as num?)?.toInt(),
        invertSign: j['invertSign'] as bool? ?? false,
      );

  /// Rät die Zuordnung aus Überschriften und Inhalt der Spalten. Null, wenn keine Datumsspalte
  /// gefunden wird; sonst ein Vorschlag, der mit [isValid] auf Vollständigkeit geprüft wird.
  static CsvMapping? guess(CsvTable table) {
    final headers = table.headers.map(_norm).toList();
    final data = table.dataRows.take(200).toList();
    if (headers.isEmpty || data.isEmpty) return null;
    final cols = headers.length;

    String cell(List<String> r, int c) => c < r.length ? r[c].trim() : '';
    double share(int c, bool Function(String) test) {
      var filled = 0, ok = 0;
      for (final r in data) {
        final v = cell(r, c);
        if (v.isEmpty) continue;
        filled++;
        if (test(v)) ok++;
      }
      return filled == 0 ? 0 : ok / filled;
    }

    bool hint(int c, List<String> words) => words.any((w) => headers[c].contains(w));
    bool isDate(String v) => parseDate(v) != null;
    bool isAmount(String v) => parseDate(v) == null && parseAmountCents(v) != null && RegExp(r'\d').hasMatch(v);

    final dateShare = [for (var c = 0; c < cols; c++) share(c, isDate)];
    final amountShare = [for (var c = 0; c < cols; c++) share(c, isAmount)];

    int? best(double Function(int c) score, {double min = 0.0}) {
      int? bestC;
      var bestScore = min;
      for (var c = 0; c < cols; c++) {
        final s = score(c);
        if (s > bestScore) {
          bestScore = s;
          bestC = c;
        }
      }
      return bestC;
    }

    final date = best((c) {
      if (dateShare[c] < 0.7) return -1;
      var s = dateShare[c];
      if (hint(c, ['buchung'])) s += 0.3;
      if (hint(c, ['datum', 'date'])) s += 0.2;
      if (hint(c, ['valuta', 'wertstellung', 'value'])) s -= 0.2;
      return s;
    });
    if (date == null) return null;

    const debitWords = ['soll', 'ausgang', 'abgang', 'debit', 'belastung', 'ausgabe'];
    const creditWords = ['haben', 'eingang', 'zugang', 'credit', 'gutschrift', 'einnahme'];
    const balanceWords = ['saldo', 'kontostand', 'balance', 'kurs', 'anteil', 'stueck', 'price', 'preis', 'gebuehr', 'fee', 'steuer', 'tax'];

    bool nonZero(List<String> r, int c) {
      final v = parseAmountCents(cell(r, c));
      return v != null && v != 0;
    }

    // Getrennte Soll-/Haben-Spalten: zwei Zahlenspalten, die sich nie überschneiden und zusammen
    // fast alle Zeilen abdecken. Welche welche ist, entscheidet die Überschrift – sonst wird nicht geraten.
    int? debit, credit, amount;
    var pairFound = false;
    final numeric = [
      for (var c = 0; c < cols; c++)
        if (c != date && amountShare[c] >= 0.7 && !hint(c, balanceWords)) c,
    ];
    for (var i = 0; i < numeric.length && !pairFound; i++) {
      for (var j = i + 1; j < numeric.length; j++) {
        final a = numeric[i], b = numeric[j];
        final both = data.where((r) => nonZero(r, a) && nonZero(r, b)).length;
        final covered = data.where((r) => nonZero(r, a) || nonZero(r, b)).length;
        final onlyA = data.where((r) => nonZero(r, a)).length;
        final onlyB = data.where((r) => nonZero(r, b)).length;
        if (both == 0 && covered >= data.length * 0.8 && onlyA >= data.length * 0.1 && onlyB >= data.length * 0.1) {
          pairFound = true;
          if (hint(a, debitWords) && hint(b, creditWords)) {
            debit = a;
            credit = b;
          } else if (hint(b, debitWords) && hint(a, creditWords)) {
            debit = b;
            credit = a;
          }
          break;
        }
      }
    }
    // Ein Spaltenpaar ohne eindeutige Überschriften bleibt offen (kein Raten, keine Einzelspalte).
    if (!pairFound) {
      amount = best((c) {
        if (c == date || amountShare[c] < 0.7) return -1;
        var s = amountShare[c];
        if (hint(c, ['betrag', 'amount', 'umsatz', 'summe', 'wert', 'value'])) s += 0.3;
        if (hint(c, balanceWords)) s -= 0.6;
        final hasNegative = data.any((r) => cell(r, c).startsWith('-') || cell(r, c).startsWith('−') || cell(r, c).endsWith('-'));
        if (hasNegative) s += 0.15;
        return s;
      });
    }

    final taken = {date, ?amount, ?debit, ?credit};
    bool textual(int c) => !taken.contains(c) && amountShare[c] < 0.5 && dateShare[c] < 0.5;

    final iban = best((c) => textual(c) && hint(c, ['iban']) && !hint(c, ['bic']) ? 1 : -1);
    final name = best((c) {
      if (!textual(c) || c == iban) return -1;
      var s = 0.1 + math.min(0.3, data.map((r) => cell(r, c)).toSet().length / math.max(1, data.length));
      if (hint(c, ['empfaenger', 'zahlungsempfaenger', 'auftraggeber', 'beguenstigter', 'payee', 'partner', 'gegenseite', 'haendler', 'merchant', 'name'])) s += 0.6;
      if (hint(c, ['iban', 'bic', 'konto', 'referenz', 'reference', 'typ', 'art', 'status', 'waehrung', 'currency', 'zweck'])) s -= 0.4;
      return s;
    });
    final purpose = best((c) {
      if (!textual(c) || c == iban || c == name) return -1;
      var s = 0.1;
      if (hint(c, ['verwendungszweck', 'zweck', 'beschreibung', 'description', 'reference', 'buchungstext', 'text', 'notiz', 'details', 'memo', 'typ'])) s += 0.5;
      if (hint(c, ['iban', 'bic', 'status', 'waehrung', 'currency'])) s -= 0.4;
      return s;
    });

    return CsvMapping(
      headerRow: table.headerRow,
      date: date,
      amount: amount,
      debit: debit,
      credit: credit,
      name: name,
      purpose: purpose,
      iban: iban,
    );
  }
}
