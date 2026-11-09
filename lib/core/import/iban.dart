// IBAN-Hilfen für den Import.

String normalizeIban(String s) => s.replaceAll(RegExp(r'\s+'), '').toUpperCase();

/// Prüft Aufbau und Prüfsumme (ISO 13616, Modulo 97).
bool isValidIban(String input) {
  final iban = normalizeIban(input);
  if (!RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$').hasMatch(iban)) return false;
  final rearranged = iban.substring(4) + iban.substring(0, 4);
  var remainder = 0;
  for (final unit in rearranged.codeUnits) {
    final int digits;
    if (unit >= 48 && unit <= 57) {
      digits = unit - 48;
      remainder = (remainder * 10 + digits) % 97;
    } else {
      digits = unit - 55; // A=10 … Z=35
      remainder = (remainder * 100 + digits) % 97;
    }
  }
  return remainder == 1;
}

final _ibanLike = RegExp(r'\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]{4}){2,7}(?:\s?[A-Z0-9]{1,4})?\b');

/// Erste gültige IBAN im Text (Leerzeichen entfernt), sonst null.
String? findIban(String text) {
  for (final m in _ibanLike.allMatches(text.toUpperCase())) {
    final candidate = normalizeIban(m.group(0)!);
    if (isValidIban(candidate)) return candidate;
    // Manchmal hängt direkt ein weiteres Wort an („… 51 EUR“): schrittweise kürzen.
    for (var len = candidate.length - 1; len >= 15; len--) {
      final cut = candidate.substring(0, len);
      if (isValidIban(cut)) return cut;
    }
  }
  return null;
}

/// Bankleitzahl und Kontonummer aus einer deutschen IBAN.
({String blz, String account})? germanParts(String iban) {
  final i = normalizeIban(iban);
  if (!RegExp(r'^DE\d{20}$').hasMatch(i)) return null;
  return (blz: i.substring(4, 12), account: i.substring(12, 22));
}

/// Vergleichsschlüssel „BLZ/Kontonummer ohne führende Nullen“.
String accountKey(String blz, String account) => '$blz/${account.replaceFirst(RegExp(r'^0+'), '')}';
