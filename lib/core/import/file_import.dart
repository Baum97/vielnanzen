import 'dart:convert';

import '../../data/models.dart';
import '../engine/normalize.dart';

/// Ergebnis eines Datei-Imports.
class ParseImport {
  final List<Transaction> transactions;
  final int duplicates;
  const ParseImport(this.transactions, this.duplicates);
}

/// Importiert CSV (Semikolon, de-DE) und MT940/CAMT-ähnliche Exporte.
/// Erkennt das Format automatisch am Inhalt.
class FileImport {
  ParseImport parse(String content, {required String accountId}) {
    final lines = const LineSplitter().convert(content).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return const ParseImport([], 0);

    if (content.contains(':20:') || content.contains(':25:') || RegExp(r'^:61:').hasMatch(content)) {
      return _parseMt940(content, accountId);
    }
    return _parseCsv(lines, accountId);
  }

  /// CSV: erwartet Kopfzeile mit Spalten wie Datum;Gegenkonto;Verwendungszweck;Betrag
  ParseImport _parseCsv(List<String> lines, String accountId) {
    final header = lines.first.toLowerCase();
    int iDate = header.indexOf('datum');
    int iName = header.indexOf('gegenkonto');
    if (iName < 0) iName = header.indexOf('empfänger');
    int iPurpose = header.indexOf('verwendungszweck');
    int iAmount = header.indexOf('betrag');
    if (iDate < 0 || iAmount < 0) {
      // Fallback: feste Reihenfolge Datum;Name;Zweck;Betrag
      iDate = 0; iName = 1; iPurpose = 2; iAmount = 3;
    }
    final out = <Transaction>[];
    var dups = 0;
    var n = 0;
    for (var i = 1; i < lines.length; i++) {
      final cols = lines[i].split(';');
      if (cols.length <= iAmount) continue;
      final date = parseDate(cols[iDate]);
      final amount = parseAmountCents(cols[iAmount]);
      if (date == null || amount == null) continue;
      final name = iName < cols.length ? cols[iName].replaceAll('"', '').trim() : '';
      final purpose = iPurpose >= 0 && iPurpose < cols.length ? cols[iPurpose].replaceAll('"', '').trim() : '';
      final sepa = parseSepaPurpose(purpose);
      final hash = dedupHash(accountId, date, amount, sepa['EREF'], '$name $purpose');
      out.add(Transaction(
        id: 'imp_${accountId}_${n++}',
        accountId: accountId,
        bookingDate: date,
        amountCents: amount,
        counterpartyName: name,
        purpose: purpose,
        creditorId: sepa['CRED'],
        mandateRef: sepa['MREF'],
        endToEndRef: sepa['EREF'],
        dedupHash: hash,
      ));
    }
    return ParseImport(out, dups);
  }

  /// MT940: :61: Buchungen und :86: Verwendungszweck.
  ParseImport _parseMt940(String content, String accountId) {
    final out = <Transaction>[];
    var n = 0;
    final stmt = RegExp(r':61:([^\r\n]+)(?:\r?\n:86:([^\r\n]+))?').allMatches(content);
    for (final m in stmt) {
      final f61 = m.group(1) ?? '';
      final f86 = (m.group(2) ?? '').replaceAll('?', '');
      // Format: Valuta[Buchung]C/DBetragNenzi...Buchungstext
      final dm = RegExp(r'^(\d{6})(\d{4})?(C|D)([\d.,]+)').firstMatch(f61);
      if (dm == null) continue;
      final valuta = dm.group(1)!;
      final date = DateTime(2000 + int.parse(valuta.substring(0, 2)), int.parse(valuta.substring(2, 4)), int.parse(valuta.substring(4, 6)));
      final debit = dm.group(3) == 'D';
      final amount = parseAmountCents(dm.group(4)!) ?? 0;
      final cents = debit ? -amount.abs() : amount.abs();
      final purpose = f86.trim();
      final sepa = parseSepaPurpose(purpose);
      out.add(Transaction(
        id: 'imp_${accountId}_${n++}',
        accountId: accountId,
        bookingDate: date,
        amountCents: cents,
        counterpartyName: sepa['ABWE'] ?? sepa['RKTO'] ?? 'Unbekannt',
        purpose: purpose,
        creditorId: sepa['CRED'],
        mandateRef: sepa['MREF'],
        endToEndRef: sepa['EREF'],
        dedupHash: dedupHash(accountId, date, cents, sepa['EREF'], purpose),
      ));
    }
    return ParseImport(out, 0);
  }
}
