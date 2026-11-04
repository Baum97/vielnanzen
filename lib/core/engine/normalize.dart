import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Schritt 1+2 der Analyse-Pipeline: Normalisieren und Deduplizieren.

/// Zerlegt SEPA-Schlüsselwörter (EREF+, MREF+, CRED+, SVWZ+ ...) aus dem Verwendungszweck.
Map<String, String> parseSepaPurpose(String purpose) {
  final result = <String, String>{};
  final regex = RegExp(r'(EREF|MREF|CRED|SVWZ|ABVA|ABWE|ABWZ|RKTO|DBET|KREF|RREF|OAMT)\+([^\s]+)', caseSensitive: false);
  for (final m in regex.allMatches(purpose)) {
    result[m.group(1)!.toUpperCase()] = m.group(2)!.trim();
  }
  return result;
}

/// Bereinigt Händlernamen: Rechtsformen, Filialnummern, Kartenzahlungs-Präfixe,
/// Ortsangaben und Zufallskennungen entfernen.
/// Beispiel: "REWE SAGT DANKE 4711 STUTTGART" -> "REWE"
String normalizeMerchantName(String raw) {
  var s = raw.toUpperCase().trim();
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  const prefixes = [
    'KARTENZAHLUNG',
    'POS-ZAHLUNG',
    'POS ZAHLUNG',
    'LASTSCHRIFT',
    'ELV',
    'SEPA-LASTSCHRIFT',
    'DAUERAUFTRAG',
    'UEBERWEISUNG',
    'UEBERW.',
    'GUTSCHRIFT',
    'EINZAHLAUTOMAT',
    'AUSZAHLAUTOMAT',
  ];
  for (final p in prefixes) {
    if (s.startsWith('$p ')) s = s.substring(p.length + 1);
  }
  s = s.replaceAll(RegExp(r'\b(GMBH|AG|KG|OHG|SE|UG|E\.? ?V\.?|V\.? ?V\.? ?V\.?)\b\.?'), ' ');
  s = s.replaceAll(RegExp(r'\b\d{3,}\b'), ' ');
  s = s.replaceAll(RegExp(r'\b(DE|DEU|DEUTSCHLAND|STUTTGART|MUENCHEN|MÜNCHEN|BERLIN|HAMBURG|KOELN|KÖLN|FRANKFURT|LEIPZIG|DUESSELDORF|DÜSSELDORF)\b'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

/// Stabile Dedup-Hash für eine Buchung (SHA-256, hex).
String dedupHash(String accountId, DateTime date, int amountCents, String? endToEndRef, String text) {
  final input = '$accountId|${date.toIso8601String()}|$amountCents|${endToEndRef ?? ''}|$text';
  return sha256.convert(utf8.encode(input)).toString();
}

/// Parst einen de-DE Geldbetrag ("1.234,56" oder "-12,90") in Cent.
int? parseAmountCents(String raw) {
  var s = raw.trim().replaceAll('€', '').replaceAll('EUR', '').trim();
  s = s.replaceAll('.', '').replaceAll(',', '.');
  final v = double.tryParse(s);
  if (v == null) return null;
  return (v * 100).round();
}

/// Parst ein de-DE Datum ("dd.MM.yyyy" oder ISO).
DateTime? parseDate(String raw) {
  final s = raw.trim();
  final m = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{2,4})$').firstMatch(s);
  if (m != null) {
    var y = int.parse(m.group(3)!);
    if (y < 100) y += 2000;
    return DateTime(y, int.parse(m.group(2)!), int.parse(m.group(1)!));
  }
  return DateTime.tryParse(s);
}
