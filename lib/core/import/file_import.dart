import 'dart:convert';
import 'dart:typed_data';

import 'package:fints/fints.dart' as fints;

import '../../connectors/fints_mapping.dart';
import '../../data/models.dart';
import '../engine/normalize.dart';
import 'csv.dart';
import 'csv_mapping.dart';
import 'iban.dart';

/// Das in der Datei erkannte eigene Konto.
class DetectedAccount {
  const DetectedAccount({this.iban, this.bankCode, this.accountNumber});

  /// IBAN ohne Leerzeichen, Großbuchstaben.
  final String? iban;
  final String? bankCode;
  final String? accountNumber;

  bool get isEmpty => iban == null && (bankCode == null || accountNumber == null);

  /// „BLZ/Konto“ – aus IBAN oder BLZ + Kontonummer, zum Vergleichen mit vorhandenen Konten.
  String? get key {
    final p = iban == null ? null : germanParts(iban!);
    if (p != null) return accountKey(p.blz, p.account);
    if (bankCode != null && accountNumber != null) return accountKey(bankCode!, accountNumber!);
    return null;
  }

  /// Kennung aus einem MT940-:25:-Feld oder CAMT-Konto („BLZ/Konto“ oder IBAN).
  static DetectedAccount? fromStatementId(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    final text = id.trim();
    final iban = findIban(text);
    if (iban != null) return DetectedAccount(iban: iban);
    final m = RegExp(r'^(\d{8})\s*/\s*(\d{1,12})').firstMatch(text);
    if (m != null) return DetectedAccount(bankCode: m.group(1), accountNumber: m.group(2));
    return null;
  }
}

/// Ergebnis eines Datei-Imports.
class ParseImport {
  final List<Transaction> transactions;
  final String format;
  final int skippedRows;
  final String? error;

  /// Kontostand laut Datei (MT940 Schlusssaldo), falls vorhanden.
  final int? closingBalanceCents;

  /// In der Datei erkanntes eigenes Konto (IBAN o. Ä.).
  final DetectedAccount? account;

  /// Bei CSV: die Tabelle (für die Spaltenzuordnung) und die verwendete Zuordnung.
  final CsvTable? table;
  final CsvMapping? usedMapping;

  /// true, wenn die Zuordnung vom Nutzer stammt (dann merkt sich die App sie).
  final bool mappingFromUser;

  const ParseImport(
    this.transactions, {
    this.format = '',
    this.skippedRows = 0,
    this.error,
    this.closingBalanceCents,
    this.account,
    this.table,
    this.usedMapping,
    this.mappingFromUser = false,
  });

  /// CSV, das nicht erkannt wurde: der Nutzer kann die Spalten selbst zuordnen.
  bool get needsMapping => error != null && table != null;
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

  ParseImport parseBytes(Uint8List bytes, {required String accountId, CsvMapping? mapping, Map<String, CsvMapping> profiles = const {}}) =>
      parse(decode(bytes), accountId: accountId, mapping: mapping, profiles: profiles);

  /// [mapping]: vom Nutzer gewählte Spalten (hat Vorrang), [profiles]: gemerkte Zuordnungen
  /// nach Tabellen-Signatur.
  ParseImport parse(String content, {required String accountId, CsvMapping? mapping, Map<String, CsvMapping> profiles = const {}}) {
    final text = content.trim();
    if (text.isEmpty) return const ParseImport([], error: 'Die Datei ist leer.');
    try {
      if (text.startsWith('<') || text.contains('<Document') || text.contains('camt.05')) {
        final statements = fints.Camt.parse(text);
        final ids = statements.map((s) => s.accountId).whereType<String>().toSet();
        if (ids.length > 1) {
          return const ParseImport([], format: 'CAMT', error: 'Die Datei enthält mehrere Konten. Bitte exportiere jedes Konto einzeln.');
        }
        final txs = [
          for (final s in statements)
            for (final t in s.transactions) mapFintsTransaction(t, accountId),
        ];
        return ParseImport(
          withOccurrenceHashes(txs),
          format: 'CAMT',
          account: DetectedAccount.fromStatementId(ids.firstOrNull),
        );
      }
      if (RegExp(r'(^|\n)\s*:(20|25|28C|60F|61):').hasMatch(text)) {
        final statements = fints.Mt940.parse(text);
        final ids = statements.map((s) => s.accountId).whereType<String>().toSet();
        if (ids.length > 1) {
          return const ParseImport([], format: 'MT940', error: 'Die Datei enthält mehrere Konten. Bitte exportiere jedes Konto einzeln.');
        }
        final txs = [
          for (final s in statements)
            for (final t in s.transactions) mapFintsTransaction(t, accountId),
        ];
        final closing = statements.isNotEmpty ? statements.last.closingBalance : null;
        return ParseImport(
          withOccurrenceHashes(txs),
          format: 'MT940',
          closingBalanceCents: closing == null ? null : amountToCents(closing),
          account: DetectedAccount.fromStatementId(ids.firstOrNull),
        );
      }
    } on FormatException catch (e) {
      return ParseImport([], error: 'Datei konnte nicht gelesen werden: ${e.message}');
    } catch (e) {
      return ParseImport([], error: 'Datei konnte nicht gelesen werden: $e');
    }
    return _parseCsv(text, accountId, mapping, profiles);
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
  static const _ownAccountCols = ['auftragskonto', 'eigene iban', 'konto iban'];
  static const _credCols = ['glaeubiger id', 'glaeubiger identifikation', 'creditor id', 'glaeubigerid'];
  static const _mandCols = ['mandatsreferenz', 'mandate reference', 'mandat'];
  static const _e2eCols = ['kundenreferenz end to end', 'end to end referenz', 'end to end', 'kundenreferenz'];
  static const _debitCols = ['soll', 'ausgang', 'debit', 'belastung'];
  static const _creditCols = ['haben', 'eingang', 'credit', 'gutschrift'];

  ParseImport _parseCsv(String text, String accountId, CsvMapping? userMapping, Map<String, CsvMapping> profiles) {
    final rows = parseCsv(text);
    if (rows.isEmpty) return const ParseImport([], error: 'Keine Daten gefunden.');
    final table = CsvTable(rows);

    // Automatische Kopfzeilen-Erkennung (bekannte Bank-Exporte).
    var autoHeader = -1;
    for (var i = 0; i < rows.length && i < 40; i++) {
      final h = rows[i].map(_norm).toList();
      final hasDate = _find(h, _dateCols) >= 0;
      final hasAmount = _find(h, _amountCols) >= 0 || (_find(h, _debitCols, exact: true) >= 0 && _find(h, _creditCols, exact: true) >= 0);
      if (hasDate && hasAmount && rows[i].length >= 3) {
        autoHeader = i;
        break;
      }
    }

    // Vorrang: Auswahl des Nutzers > gemerkte Zuordnung > automatische Erkennung.
    final mapping = userMapping ?? profiles[table.signature];
    final fromUser = mapping != null;

    if (mapping == null && autoHeader < 0) {
      return ParseImport(
        const [],
        format: 'CSV',
        table: table,
        error: 'Das Format dieser CSV-Datei ist unbekannt. Ordne die Spalten einmal selbst zu – Klarblick merkt sich das.',
      );
    }

    final headerIdx = mapping?.headerRow ?? autoHeader;
    final cols = mapping != null ? _Cols.fromMapping(mapping) : _Cols.auto(rows[headerIdx].map(_norm).toList());
    if (headerIdx >= rows.length) {
      return ParseImport(const [], format: 'CSV', table: table, error: 'Die gewählte Kopfzeile gibt es in der Datei nicht.');
    }

    String col(List<String> r, int i) => i >= 0 && i < r.length ? r[i].trim() : '';
    final out = <Transaction>[];
    var skipped = 0;

    for (var i = headerIdx + 1; i < rows.length; i++) {
      final r = rows[i];
      final date = parseDate(col(r, cols.date));
      int? amount;
      if (cols.amount >= 0) {
        amount = parseAmountCents(col(r, cols.amount));
        final sign = col(r, cols.sign).toUpperCase();
        if (amount != null && (sign == 'S' || sign == 'D')) amount = -amount.abs();
      } else {
        final debit = parseAmountCents(col(r, cols.debit));
        final credit = parseAmountCents(col(r, cols.credit));
        if ((debit ?? 0) != 0) amount = -(debit!.abs());
        if ((credit ?? 0) != 0) amount = credit!.abs();
      }
      if (amount != null && cols.invert) amount = -amount;
      if (date == null || amount == null || amount == 0) {
        skipped++;
        continue;
      }
      var purpose = col(r, cols.purpose);
      final type = col(r, cols.type);
      if (purpose.isEmpty) purpose = type;
      final sepa = parseSepaPurpose(purpose);
      var name = col(r, cols.name);
      if (name.isEmpty) name = sepa['ABWA'] ?? sepa['ABWE'] ?? (type.isNotEmpty ? type : 'Unbekannt');
      final iban = col(r, cols.iban).replaceAll(' ', '').toUpperCase();
      out.add(_tx(
        accountId,
        date,
        amount,
        name,
        purpose,
        RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{10,30}$').hasMatch(iban) ? iban : null,
        col(r, cols.cred).isNotEmpty ? col(r, cols.cred) : sepa['CRED'],
        col(r, cols.mand).isNotEmpty ? col(r, cols.mand) : sepa['MREF'],
        col(r, cols.e2e).isNotEmpty ? col(r, cols.e2e) : sepa['EREF'],
      ));
    }

    // Eigenes Konto: Spalte „Auftragskonto“ oder IBAN im Vorspann vor der Kopfzeile.
    String? ownIban;
    if (cols.ownAccount >= 0) {
      for (final r in rows.skip(headerIdx + 1).take(5)) {
        ownIban = findIban(col(r, cols.ownAccount));
        if (ownIban != null) break;
      }
    }
    ownIban ??= headerIdx > 0 ? findIban(rows.take(headerIdx).map((r) => r.join(' ')).join('\n')) : null;
    final account = ownIban == null ? null : DetectedAccount(iban: ownIban);

    if (out.isEmpty) {
      return ParseImport(
        const [],
        format: 'CSV',
        skippedRows: skipped,
        table: table,
        account: account,
        error: 'Keine Umsätze erkannt – stimmen Datum- und Betrag-Spalte? Du kannst die Spalten selbst zuordnen.',
      );
    }
    return ParseImport(
      withOccurrenceHashes(out),
      format: 'CSV',
      skippedRows: skipped,
      table: table,
      account: account,
      usedMapping: mapping,
      mappingFromUser: fromUser,
    );
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

/// Spaltenindizes (−1 = nicht vorhanden).
class _Cols {
  _Cols({
    required this.date,
    this.amount = -1,
    this.debit = -1,
    this.credit = -1,
    this.name = -1,
    this.purpose = -1,
    this.type = -1,
    this.iban = -1,
    this.ownAccount = -1,
    this.cred = -1,
    this.mand = -1,
    this.e2e = -1,
    this.sign = -1,
    this.invert = false,
  });

  final int date, amount, debit, credit, name, purpose, type, iban, ownAccount, cred, mand, e2e, sign;
  final bool invert;

  factory _Cols.fromMapping(CsvMapping m) => _Cols(
        date: m.date,
        amount: m.amount ?? -1,
        debit: m.debit ?? -1,
        credit: m.credit ?? -1,
        name: m.name ?? -1,
        purpose: m.purpose ?? -1,
        iban: m.iban ?? -1,
        invert: m.invertSign,
      );

  factory _Cols.auto(List<String> h) {
    final iAmount = FileImport._find(h, FileImport._amountCols);
    return _Cols(
      date: FileImport._find(h, FileImport._dateCols),
      amount: iAmount,
      debit: iAmount < 0 ? FileImport._find(h, FileImport._debitCols, exact: true) : -1,
      credit: iAmount < 0 ? FileImport._find(h, FileImport._creditCols, exact: true) : -1,
      name: FileImport._find(h, FileImport._nameCols),
      purpose: FileImport._find(h, FileImport._purposeCols),
      type: FileImport._find(h, FileImport._typeCols),
      iban: FileImport._find(h, FileImport._ibanCols),
      ownAccount: FileImport._find(h, FileImport._ownAccountCols, exact: true),
      cred: FileImport._find(h, FileImport._credCols),
      mand: FileImport._find(h, FileImport._mandCols),
      e2e: FileImport._find(h, FileImport._e2eCols),
      sign: h.indexWhere((x) => x == 's h' || x == 'soll haben' || x == 'sh'),
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
