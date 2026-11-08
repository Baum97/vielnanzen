import 'dart:convert';
import 'dart:typed_data';

import 'package:fints/fints.dart' as fints;

import '../../connectors/fints_mapping.dart';
import '../../data/models.dart';
import '../engine/normalize.dart';
import 'csv.dart';

/// Ergebnis eines Datei-Imports.
class ParseImport {
  final List<Transaction> transactions;
  final String format;
  final int skippedRows;
  final String? error;

  /// Kontostand laut Datei (MT940 Schlusssaldo), falls vorhanden.
  final int? closingBalanceCents;

  const ParseImport(this.transactions, {this.format = '', this.skippedRows = 0, this.error, this.closingBalanceCents});

  /// Kompatibilität: Anzahl Duplikate wird erst beim Einspielen bestimmt.
  int get duplicates => 0;
}

/// Liest Kontoauszugs-Dateien: CSV (alle gängigen deutschen Bank-Exporte),
/// MT940/MT942 und CAMT.052/053/054. Das Format wird am Inhalt erkannt.
class FileImport {
  /// Dekodiert Dateibytes: UTF-8 (mit/ohne BOM), sonst Latin-1/Windows-1252.
  static String decode(Uint8List bytes) {
    var b = bytes;
    if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) b = b.sublist(3);
    try {
      return utf8.decode(b);
    } on FormatException {
      return latin1.decode(b);
    }
  }

  ParseImport parseBytes(Uint8List bytes, {required String accountId}) => parse(decode(bytes), accountId: accountId);

  ParseImport parse(String content, {required String accountId}) {
    final text = content.trim();
    if (text.isEmpty) return const ParseImport([], error: 'Die Datei ist leer.');
    try {
      if (text.startsWith('<') || text.contains('<Document') || text.contains('camt.05')) {
        final txs = fints.Camt.parseTransactions(text).map((t) => mapFintsTransaction(t, accountId)).toList();
        return ParseImport(withOccurrenceHashes(txs), format: 'CAMT');
      }
      if (RegExp(r'(^|\n)\s*:(20|25|28C|60F|61):').hasMatch(text)) {
        final statements = fints.Mt940.parse(text);
        final txs = [
          for (final s in statements)
            for (final t in s.transactions) mapFintsTransaction(t, accountId),
        ];
        final closing = statements.isNotEmpty ? statements.last.closingBalance : null;
        return ParseImport(
          withOccurrenceHashes(txs),
          format: 'MT940',
          closingBalanceCents: closing == null ? null : amountToCents(closing),
        );
      }
    } on FormatException catch (e) {
      return ParseImport([], error: 'Datei konnte nicht gelesen werden: ${e.message}');
    } catch (e) {
      return ParseImport([], error: 'Datei konnte nicht gelesen werden: $e');
    }
    return _parseCsv(text, accountId);
  }

  // ---------------------------------------------------------------------------
  // CSV

  static String _norm(String h) => h
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  static int _find(List<String> headers, List<String> candidates, {bool exact = false}) {
    for (final c in candidates) {
      final i = headers.indexWhere((h) => h == c);
      if (i >= 0) return i;
    }
    if (exact) return -1;
    for (final c in candidates) {
      final i = headers.indexWhere((h) => h.contains(c));
      if (i >= 0) return i;
    }
    return -1;
  }

  static const _dateCols = ['buchungstag', 'buchungsdatum', 'buchung', 'datum', 'date', 'booking date', 'transaktionsdatum', 'valutadatum', 'wertstellung', 'valuta'];
  static const _amountCols = ['betrag eur', 'betrag', 'amount eur', 'amount', 'umsatz in eur', 'umsatz', 'betrag in eur'];
  static const _nameCols = [
    'beguenstigter zahlungspflichtiger',
    'name zahlungsbeteiligter',
    'zahlungsempfaenger in',
    'zahlungspflichtige r',
    'auftraggeber beguenstigter',
    'auftraggeber empfaenger',
    'empfaenger',
    'auftraggeber',
    'payee',
    'partner name',
    'name',
    'gegenseite',
  ];
  static const _purposeCols = ['verwendungszweck', 'vorgang verwendungszweck', 'payment reference', 'beschreibung', 'buchungsdetails', 'reference', 'text'];
  static const _typeCols = ['buchungstext', 'umsatzart', 'transaction type', 'vorgang', 'art'];
  static const _ibanCols = ['iban zahlungsbeteiligter', 'kontonummer iban', 'iban', 'account number', 'gegenkonto', 'kontonummer'];
  static const _credCols = ['glaeubiger id', 'glaeubiger identifikation', 'creditor id', 'glaeubigerid'];
  static const _mandCols = ['mandatsreferenz', 'mandate reference', 'mandat'];
  static const _e2eCols = ['kundenreferenz end to end', 'end to end referenz', 'end to end', 'kundenreferenz'];
  static const _debitCols = ['soll', 'ausgang', 'debit', 'belastung'];
  static const _creditCols = ['haben', 'eingang', 'credit', 'gutschrift'];

  ParseImport _parseCsv(String text, String accountId) {
    final rows = parseCsv(text);
    if (rows.isEmpty) return const ParseImport([], error: 'Keine Daten gefunden.');

    // Kopfzeile suchen (manche Banken haben Vorspann-Zeilen mit Kontoinfos).
    var headerIdx = -1;
    for (var i = 0; i < rows.length && i < 40; i++) {
      final h = rows[i].map(_norm).toList();
      final hasDate = _find(h, _dateCols) >= 0;
      final hasAmount = _find(h, _amountCols) >= 0 || (_find(h, _debitCols, exact: true) >= 0 && _find(h, _creditCols, exact: true) >= 0);
      if (hasDate && hasAmount && rows[i].length >= 3) {
        headerIdx = i;
        break;
      }
    }

    final out = <Transaction>[];
    var skipped = 0;

    if (headerIdx < 0) {
      // Fallback: feste Reihenfolge Datum;Name;Zweck;Betrag
      for (final r in rows) {
        if (r.length < 4) continue;
        final date = parseDate(r[0]);
        final amount = parseAmountCents(r[3]);
        if (date == null || amount == null) {
          skipped++;
          continue;
        }
        out.add(_tx(accountId, date, amount, r[1], r[2], null, null, null, null));
      }
      if (out.isEmpty) {
        return const ParseImport([], error: 'Format nicht erkannt. Erwartet werden Spalten wie Buchungstag, Empfänger, Verwendungszweck und Betrag.');
      }
      return ParseImport(withOccurrenceHashes(out), format: 'CSV', skippedRows: skipped);
    }

    final h = rows[headerIdx].map(_norm).toList();
    final iDate = _find(h, _dateCols);
    final iAmount = _find(h, _amountCols);
    final iDebit = iAmount < 0 ? _find(h, _debitCols, exact: true) : -1;
    final iCredit = iAmount < 0 ? _find(h, _creditCols, exact: true) : -1;
    final iName = _find(h, _nameCols);
    final iPurpose = _find(h, _purposeCols);
    final iType = _find(h, _typeCols);
    final iIban = _find(h, _ibanCols);
    final iCred = _find(h, _credCols);
    final iMand = _find(h, _mandCols);
    final iE2e = _find(h, _e2eCols);
    final iSign = h.indexWhere((x) => x == 's h' || x == 'soll haben' || x == 'sh');

    String col(List<String> r, int i) => i >= 0 && i < r.length ? r[i].trim() : '';

    for (var i = headerIdx + 1; i < rows.length; i++) {
      final r = rows[i];
      final date = parseDate(col(r, iDate));
      int? amount;
      if (iAmount >= 0) {
        amount = parseAmountCents(col(r, iAmount));
        final sign = col(r, iSign).toUpperCase();
        if (amount != null && (sign == 'S' || sign == 'D')) amount = -amount.abs();
      } else {
        final debit = parseAmountCents(col(r, iDebit));
        final credit = parseAmountCents(col(r, iCredit));
        if ((debit ?? 0) != 0) amount = -(debit!.abs());
        if ((credit ?? 0) != 0) amount = credit!.abs();
        if (debit != null || credit != null) amount ??= 0;
      }
      if (date == null || amount == null || amount == 0) {
        skipped++;
        continue;
      }
      var purpose = col(r, iPurpose);
      final type = col(r, iType);
      if (purpose.isEmpty) purpose = type;
      final sepa = parseSepaPurpose(purpose);
      var name = col(r, iName);
      if (name.isEmpty) name = sepa['ABWA'] ?? sepa['ABWE'] ?? (type.isNotEmpty ? type : 'Unbekannt');
      final iban = col(r, iIban).replaceAll(' ', '');
      out.add(_tx(
        accountId,
        date,
        amount,
        name,
        purpose,
        RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{10,30}$').hasMatch(iban.toUpperCase()) ? iban.toUpperCase() : null,
        col(r, iCred).isNotEmpty ? col(r, iCred) : sepa['CRED'],
        col(r, iMand).isNotEmpty ? col(r, iMand) : sepa['MREF'],
        col(r, iE2e).isNotEmpty ? col(r, iE2e) : sepa['EREF'],
      ));
    }
    if (out.isEmpty) {
      return ParseImport([], format: 'CSV', skippedRows: skipped, error: 'Keine Umsätze in der Datei gefunden.');
    }
    return ParseImport(withOccurrenceHashes(out), format: 'CSV', skippedRows: skipped);
  }

  Transaction _tx(String accountId, DateTime date, int amount, String name, String purpose, String? iban, String? cred, String? mref, String? e2e) {
    final ref = (e2e == null || e2e.isEmpty || e2e.toUpperCase() == 'NOTPROVIDED') ? null : e2e;
    final hash = dedupHash(accountId, date, amount, ref, '$name $purpose');
    return Transaction(
      id: 'imp_${hash.substring(0, 20)}',
      accountId: accountId,
      bookingDate: date,
      amountCents: amount,
      counterpartyName: name.replaceAll('"', '').trim(),
      counterpartyIban: iban,
      purpose: purpose.replaceAll('"', '').trim(),
      creditorId: (cred?.isEmpty ?? true) ? null : cred,
      mandateRef: (mref?.isEmpty ?? true) ? null : mref,
      endToEndRef: ref,
      dedupHash: hash,
    );
  }
}

/// Identische Buchungen innerhalb einer Lieferung (z. B. zwei gleiche Kaffees am selben Tag)
/// bekommen eine laufende Nummer im Hash – so gehen sie nicht als „Duplikat“ verloren,
/// erneutes Einspielen derselben Datei bleibt aber erkennbar.
List<Transaction> withOccurrenceHashes(List<Transaction> list) {
  final seen = <String, int>{};
  return [
    for (final t in list)
      () {
        final k = seen[t.dedupHash] = (seen[t.dedupHash] ?? 0) + 1;
        if (k == 1) return t;
        final hash = '${t.dedupHash}#$k';
        return Transaction(
          id: '${t.id}_$k',
          accountId: t.accountId,
          bookingDate: t.bookingDate,
          valueDate: t.valueDate,
          amountCents: t.amountCents,
          counterpartyName: t.counterpartyName,
          counterpartyIban: t.counterpartyIban,
          purpose: t.purpose,
          mandateRef: t.mandateRef,
          creditorId: t.creditorId,
          endToEndRef: t.endToEndRef,
          gvc: t.gvc,
          pending: t.pending,
          dedupHash: hash,
        );
      }(),
  ];
}
