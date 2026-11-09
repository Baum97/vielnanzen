import 'dart:convert';

/// Eine Bank aus dem Verzeichnis (nur Banken mit bekannter FinTS-Adresse).
class BankEntry {
  final String blz;
  final String name;
  final String city;
  final String bic;
  final String url;

  const BankEntry({required this.blz, required this.name, required this.city, required this.bic, required this.url});

  /// Anzeigename mit Ort, wenn der Ort nicht schon im Namen steht.
  String get title => city.isNotEmpty && !BankDirectory.fold(name).contains(BankDirectory.fold(city.split(',').first)) ? '$name · $city' : name;
}

/// Verzeichnis deutscher Banken mit FinTS-Adresse (Quelle: `assets/data/bank_directory.json`,
/// erzeugt von `tool/build_bank_directory.py`). Suche nach Name, Ort, BLZ, BIC oder IBAN.
class BankDirectory {
  BankDirectory(this.banks) {
    for (final b in banks) {
      _byBlz[b.blz] = b;
      _haystack[b.blz] = fold('${b.name} ${b.city} ${b.bic}');
    }
  }

  factory BankDirectory.fromJsonString(String source) {
    final j = jsonDecode(source) as Map<String, dynamic>;
    final urls = (j['urls'] as List).cast<String>();
    return BankDirectory([
      for (final e in j['banks'] as List)
        BankEntry(blz: e[0] as String, name: e[1] as String, city: e[2] as String, bic: e[3] as String, url: urls[e[4] as int]),
    ]);
  }

  final List<BankEntry> banks;
  final Map<String, BankEntry> _byBlz = {};
  final Map<String, String> _haystack = {};

  BankEntry? byBlz(String blz) => _byBlz[blz.replaceAll(' ', '')];

  /// Kleinbuchstaben ohne Umlaute/Akzente – „Köln“, „koeln“ und „KOELN“ passen zusammen.
  static String fold(String s) => s
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss')
      .replaceAll(RegExp('[éèê]'), 'e')
      .replaceAll(RegExp('[áàâ]'), 'a');

  /// Bankleitzahl aus einer deutschen IBAN (Stellen 5–12), sonst null.
  static String? blzFromIban(String input) {
    final iban = input.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (iban.length < 12 || !iban.startsWith('DE') || !RegExp(r'^DE\d{2}\d{8}').hasMatch(iban)) return null;
    return iban.substring(4, 12);
  }

  /// Name der Bank zu einer deutschen IBAN, falls bekannt.
  BankEntry? forIban(String iban) {
    final blz = blzFromIban(iban);
    return blz == null ? null : _byBlz[blz];
  }

  /// Sucht Banken. Eine IBAN findet die zugehörige Bank, Ziffern suchen in der BLZ,
  /// Text in Name, Ort und BIC (alle Wörter müssen vorkommen).
  List<BankEntry> search(String query, {int limit = 60}) {
    final q = fold(query.trim());
    if (q.isEmpty) return const [];
    final compact = q.replaceAll(RegExp(r'\s+'), '');

    final ibanBlz = blzFromIban(compact);
    if (ibanBlz != null) {
      final hit = _byBlz[ibanBlz];
      return hit == null ? const [] : [hit];
    }
    if (RegExp(r'^\d{3,}$').hasMatch(compact)) {
      final r = banks.where((b) => b.blz.startsWith(compact)).toList();
      return r.length > limit ? r.sublist(0, limit) : r;
    }

    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final scored = <(int, BankEntry)>[];
    for (final b in banks) {
      final hay = _haystack[b.blz]!;
      if (!tokens.every(hay.contains)) continue;
      final name = fold(b.name);
      final score = name.startsWith(tokens.first) ? 0 : (name.contains(q) ? 1 : 2);
      scored.add((score, b));
    }
    scored.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      if (c != 0) return c;
      final l = a.$2.name.length.compareTo(b.$2.name.length);
      return l != 0 ? l : a.$2.name.compareTo(b.$2.name);
    });
    return [for (final s in scored.take(limit)) s.$2];
  }
}
