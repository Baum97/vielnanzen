import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Schritt 1+2 der Analyse-Pipeline: Normalisieren und Deduplizieren.

/// Zerlegt SEPA-Schlüsselwörter (EREF+, MREF+, CRED+, SVWZ+ ...) aus dem Verwendungszweck.
Map<String, String> parseSepaPurpose(String purpose) {
  final result = <String, String>{};
  final regex = RegExp(r'(EREF|MREF|CRED|SVWZ|ABWA|ABWE|ABWZ|RKTO|DBET|KREF|RREF|OAMT|COAM|IBAN|BIC)\+', caseSensitive: false);
  final matches = regex.allMatches(purpose).toList();
  for (var i = 0; i < matches.length; i++) {
    final m = matches[i];
    final end = i + 1 < matches.length ? matches[i + 1].start : purpose.length;
    final value = purpose.substring(m.end, end).trim();
    if (value.isNotEmpty) result[m.group(1)!.toUpperCase()] = value;
  }
  return result;
}

const _prefixes = [
  'KARTENZAHLUNG',
  'KARTENZAHLUNG GIROCARD',
  'GIROCARD',
  'POS-ZAHLUNG',
  'POS ZAHLUNG',
  'POS',
  'LASTSCHRIFT',
  'SEPA-LASTSCHRIFT',
  'SEPA LASTSCHRIFT',
  'FOLGELASTSCHRIFT',
  'ERSTLASTSCHRIFT',
  'ELV',
  'DAUERAUFTRAG',
  'UEBERWEISUNG',
  'ÜBERWEISUNG',
  'UEBERW.',
  'GUTSCHRIFT',
  'EINZAHLAUTOMAT',
  'AUSZAHLAUTOMAT',
  'VISA',
  'MASTERCARD',
  'DEBITK.',
  'APPLE PAY',
  'GOOGLE PAY',
];

final _legalForms = RegExp(r'\b(GMBH(?: & CO\.? KG)?|MBH|AG|KGAA|KG|OHG|SE|UG|LTD|LIMITED|INC|B\.?V\.?|S\.?A\.?R\.?L|E\.? ?K\.?|E\.? ?V\.?|CO\.?)(?=\s|$|[.,])');
final _cities = RegExp(
    r'\b(DE|DEU|DEUTSCHLAND|GERMANY|STUTTGART|MUENCHEN|MÜNCHEN|BERLIN|HAMBURG|KOELN|KÖLN|FRANKFURT|LEIPZIG|DUESSELDORF|DÜSSELDORF|DRESDEN|HANNOVER|NUERNBERG|NÜRNBERG|BREMEN|ESSEN|DORTMUND|BONN|MANNHEIM|KARLSRUHE|LUXEMBOURG|LUXEMBURG|DUBLIN|AMSTERDAM)\b');
final _processorPrefix = RegExp(r'^(SUMUP|SQ|ZETTLE|IZ|PP|PAYPAL|STRIPE)\s*\*\s*');

/// Bereinigt Händlernamen: Kartenzahlungs-Präfixe, Rechtsformen, Filialnummern,
/// Ortsangaben und Zufallskennungen entfernen.
/// Beispiel: "KARTENZAHLUNG NETFLIX 12345" -> "NETFLIX"
String normalizeMerchantName(String raw) {
  var s = raw.toUpperCase().trim();
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  var changed = true;
  while (changed) {
    changed = false;
    for (final p in _prefixes) {
      if (s.startsWith('$p ')) {
        s = s.substring(p.length + 1).trimLeft();
        changed = true;
      }
    }
  }
  s = s.replaceFirst(_processorPrefix, '');
  s = s.replaceAll(RegExp(r'\d{2}\.\d{2}(\.\d{2,4})?( \d{2}[.:]\d{2}(:\d{2})?)?'), ' '); // Datum/Uhrzeit
  s = s.replaceAll(RegExp(r'//.*$'), ' ');
  s = s.replaceAll(_legalForms, ' ');
  s = s.replaceAll(RegExp(r'\b[A-Z]*\d[A-Z\d]{5,}\b'), ' '); // Referenzen wie 4711X9Z2
  s = s.replaceAll(RegExp(r'\b\d{3,}\b'), ' ');
  s = s.replaceAll(_cities, ' ');
  s = s.replaceAll(RegExp(r'[,;]+'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceAll(RegExp(r'^[.\-*/ ]+|[.\-*/ ]+$'), '');
  return s;
}

/// "REWE MARKT" -> "Rewe Markt" (für Anzeige unbekannter Händler).
String prettifyName(String normalized) {
  if (normalized.isEmpty) return normalized;
  return normalized.split(' ').map((w) {
    if (w.length <= 3 && !RegExp(r'[AEIOUÄÖÜ]').hasMatch(w)) return w; // Abkürzungen (DB, HUK)
    return w[0] + w.substring(1).toLowerCase();
  }).join(' ');
}

/// Stabile Dedup-Hash für eine Buchung (SHA-256, hex).
String dedupHash(String accountId, DateTime date, int amountCents, String? endToEndRef, String text) {
  final day = '${date.year}-${date.month}-${date.day}';
  final ref = (endToEndRef == null || endToEndRef.toUpperCase() == 'NOTPROVIDED') ? '' : endToEndRef;
  final input = '$accountId|$day|$amountCents|$ref|${text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ')}';
  return sha256.convert(utf8.encode(input)).toString();
}

/// Parst einen Geldbetrag in Cent: "1.234,56", "-12,90 €", "1,234.56", "+5", "12.5".
int? parseAmountCents(String raw) {
  var s = raw.trim().replaceAll(RegExp(r'(€|EUR|\s| )'), '');
  if (s.isEmpty) return null;
  var negative = false;
  if (s.startsWith('-') || s.startsWith('−')) {
    negative = true;
    s = s.substring(1);
  } else if (s.startsWith('+')) {
    s = s.substring(1);
  }
  if (s.endsWith('-')) {
    negative = true;
    s = s.substring(0, s.length - 1);
  }
  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    // Das spätere Zeichen ist das Dezimaltrennzeichen.
    if (lastComma > lastDot) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else {
      s = s.replaceAll(',', '');
    }
  } else if (lastComma >= 0) {
    s = s.replaceAll(',', '.');
  } else if (lastDot >= 0) {
    // "1.234" (Tausender) vs. "12.50" (Dezimal): genau 3 Nachkommastellen → Tausender
    final decimals = s.length - lastDot - 1;
    if (decimals == 3 && RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(s)) s = s.replaceAll('.', '');
  }
  final v = double.tryParse(s);
  if (v == null) return null;
  final cents = (v * 100).round();
  return negative ? -cents : cents;
}

/// Parst ein Datum: "dd.MM.yyyy", "dd.MM.yy", "dd/MM/yyyy", ISO "yyyy-MM-dd".
DateTime? parseDate(String raw) {
  final s = raw.trim().replaceAll('"', '');
  final m = RegExp(r'^(\d{1,2})[./](\d{1,2})[./](\d{2,4})').firstMatch(s);
  if (m != null) {
    var y = int.parse(m.group(3)!);
    if (y < 100) y += 2000;
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(1)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(y, month, day);
  }
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (iso != null) {
    return DateTime(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
  }
  return null;
}
