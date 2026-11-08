import '../../data/models.dart';
import 'normalize.dart';

/// Ergebnis der Kategorisierung einer Buchung.
class Categorization {
  final String? categoryId;
  final String? merchantId;
  final String reason;
  final bool transfer;
  final bool exclude;

  const Categorization({this.categoryId, this.merchantId, required this.reason, this.transfer = false, this.exclude = false});
}

class _Pattern {
  final String text;
  final RegExp regex;
  final Merchant merchant;
  _Pattern(this.text, this.merchant) : regex = RegExp('(?<![A-Z0-9])${RegExp.escape(text)}(?![A-Z0-9])');
}

/// Schritt 3 der Pipeline: Kategorie- und Händler-Zuordnung.
/// Reihenfolge: eigene Regeln → Umbuchung zwischen eigenen Konten → Gläubiger-ID →
/// Händler-Datenbank (Name, dann Verwendungszweck) → Stichwörter → Einnahme/unkategorisiert.
class Categorizer {
  Categorizer({
    required this.categories,
    required this.merchants,
    this.creditorCategories = const {},
    this.creditorMerchants = const {},
    this.rules = const [],
    this.ownIbans = const {},
  }) {
    for (final c in categories) {
      _categories[c.id] = c;
    }
    for (final m in merchants) {
      _merchants[m.id] = m;
      for (final p in m.patterns) {
        _patterns.add(_Pattern(p, m));
      }
    }
    // Längere Muster zuerst: "AMAZON PRIME" vor "AMAZON".
    _patterns.sort((a, b) => b.text.length.compareTo(a.text.length));
  }

  final List<Category> categories;
  final List<Merchant> merchants;
  final Map<String, String> creditorCategories;
  final Map<String, String> creditorMerchants;
  final List<Rule> rules;
  final Set<String> ownIbans;

  final Map<String, Category> _categories = {};
  final Map<String, Merchant> _merchants = {};
  final List<_Pattern> _patterns = [];

  /// Generische Stichwörter, wenn kein Händler bekannt ist (Großbuchstaben).
  /// Die Reihenfolge ist die Priorität: spezifische Begriffe zuerst.
  static const keywords = <String, String>{
    'MIETE': 'miete',
    'KALTMIETE': 'miete',
    'WARMMIETE': 'miete',
    'NEBENKOSTEN': 'miete',
    'HAUSGELD': 'miete',
    'DARLEHEN': 'miete',
    'KREDITRATE': 'miete',
    'GEHALT': 'gehalt',
    'LOHN': 'gehalt',
    'BEZUEGE': 'gehalt',
    'BEZÜGE': 'gehalt',
    'ENTGELTABRECHNUNG': 'gehalt',
    'KINDERGELD': 'staat',
    'ELTERNGELD': 'staat',
    'BAFOEG': 'staat',
    'BAFÖG': 'staat',
    'RENTE': 'staat',
    'STEUERERSTATTUNG': 'erstattung',
    'ERSTATTUNG': 'erstattung',
    'RUECKERSTATTUNG': 'erstattung',
    'RÜCKERSTATTUNG': 'erstattung',
    'GUTSCHRIFT RETOURE': 'erstattung',
    'ZINSEN': 'zinsen-dividenden',
    'DIVIDENDE': 'zinsen-dividenden',
    'KONTOFUEHRUNG': 'gebuehren',
    'KONTOFÜHRUNG': 'gebuehren',
    'KONTOFUEHRUNGSENTGELT': 'gebuehren',
    'GEBUEHR': 'gebuehren',
    'GEBÜHR': 'gebuehren',
    'JAHRESGEBUEHR': 'gebuehren',
    'DISPOZINSEN': 'gebuehren',
    'SOLLZINSEN': 'gebuehren',
    'GELDAUTOMAT': 'bargeld',
    'BARGELDAUSZAHLUNG': 'bargeld',
    'GA ': 'bargeld',
    'BARGELD': 'bargeld',
    'STROM': 'strom-gas',
    'GAS ABSCHLAG': 'strom-gas',
    'WASSER': 'wasser',
    'ABWASSER': 'wasser',
    'MUELL': 'wasser',
    'MÜLL': 'wasser',
    'ABFALL': 'wasser',
    'GRUNDSTEUER': 'steuern',
    'HUNDESTEUER': 'steuern',
    'KFZ STEUER': 'kfz-steuer',
    'HAFTPFLICHT': 'haftpflicht',
    'HAUSRAT': 'haftpflicht',
    'KFZ-VERSICHERUNG': 'kfz-versicherung',
    'KRANKENKASSE': 'krankenversicherung',
    'KRANKENVERSICHERUNG': 'krankenversicherung',
    'APOTHEKE': 'apotheke',
    'ZAHNARZT': 'arzt',
    'PRAXIS': 'arzt',
    'ARZT': 'arzt',
    'KLINIK': 'arzt',
    'OPTIK': 'brille',
    'TANKSTELLE': 'tanken',
    'TANKSTELLEN': 'tanken',
    'PARKHAUS': 'parken',
    'PARKEN': 'parken',
    'PARKSCHEIN': 'parken',
    'TAXI': 'taxi',
    'WERKSTATT': 'werkstatt',
    'AUTOHAUS': 'werkstatt',
    'FAHRKARTE': 'oepnv',
    'VERKEHRSBETRIEBE': 'oepnv',
    'RESTAURANT': 'restaurant',
    'RISTORANTE': 'restaurant',
    'PIZZERIA': 'restaurant',
    'TRATTORIA': 'restaurant',
    'GASTHAUS': 'restaurant',
    'GASTSTAETTE': 'restaurant',
    'IMBISS': 'restaurant',
    'DOENER': 'restaurant',
    'DÖNER': 'restaurant',
    'SUSHI': 'restaurant',
    'BURGER': 'restaurant',
    'CAFE': 'restaurant',
    'CAFÉ': 'restaurant',
    'KAFFEE': 'restaurant',
    'KIOSK': 'restaurant',
    'BAECKEREI': 'baecker',
    'BÄCKEREI': 'baecker',
    'KONDITOREI': 'baecker',
    'METZGEREI': 'supermarkt',
    'GETRAENKE': 'supermarkt',
    'GETRÄNKE': 'supermarkt',
    'BIOMARKT': 'supermarkt',
    'HOTEL': 'reisen',
    'FERIENWOHNUNG': 'reisen',
    'FLUG': 'reisen',
    'KITA': 'kinder',
    'KINDERGARTEN': 'kinder',
    'SCHULE': 'bildung',
    'VOLKSHOCHSCHULE': 'bildung',
    'TIERARZT': 'haustier',
    'FITNESS': 'fitness',
    'GYM': 'fitness',
    'SPORTVEREIN': 'fitness',
    'STREAMING': 'streaming-video',
    'SPARPLAN': 'sparen',
    'DEPOT': 'sparen',
    'WERTPAPIER': 'sparen',
    'TAGESGELD': 'sparen',
    'UMBUCHUNG': 'umbuchung',
    'EIGENUEBERTRAG': 'umbuchung',
    'ÜBERTRAG': 'umbuchung',
    // Generische Wörter zuletzt
    'ABSCHLAG': 'strom-gas',
    'STEUER': 'steuern',
    'VERSICHERUNG': 'sonstige-versicherung',
    'ENTGELT': 'gebuehren',
    'ABO': 'software',
    'BAR': 'restaurant',
    'AUSZAHLUNG': 'bargeld',
    'ABSCHLUSS': 'gebuehren',
  };

  static final List<(RegExp, String, String)> _keywordRegexes = [
    for (final e in keywords.entries)
      (RegExp('(?<![A-ZÄÖÜ])${RegExp.escape(e.key.trim())}(?![A-ZÄÖÜ])'), e.value, e.key.trim()),
  ];

  Category? categoryById(String? id) => id == null ? null : _categories[id];

  String? _parentOf(String id) => _categories[id]?.parentId;

  bool _kindFits(String cat, Transaction t) {
    final kind = _categories[cat]?.kind;
    if (t.isIncome && kind == CategoryKind.ausgabe) return false;
    if (t.isExpense && kind == CategoryKind.einnahme) return false;
    return true;
  }

  /// Zu allgemeine Wörter verfeinern keine Händler-Kategorie.
  static const _generic = {'ABSCHLAG', 'STEUER', 'VERSICHERUNG', 'ENTGELT', 'ABO', 'BAR', 'AUSZAHLUNG', 'ABSCHLUSS', 'STREAMING'};

  String? _keywordCategory(String hay, Transaction t) {
    for (final (regex, cat, word) in _keywordRegexes) {
      if (_generic.contains(word)) continue;
      if (regex.hasMatch(hay) && _kindFits(cat, t)) return cat;
    }
    return null;
  }
  Merchant? merchantById(String? id) => id == null ? null : _merchants[id];

  Merchant? matchMerchant(String text) {
    final hay = text.toUpperCase();
    for (final p in _patterns) {
      if (hay.contains(p.text) && p.regex.hasMatch(hay)) return p.merchant;
    }
    return null;
  }

  bool _ruleMatches(Rule r, Transaction t, String normalized, Merchant? merchant) {
    final value = r.value.toUpperCase();
    final String field = switch (r.field) {
      'merchant' => merchant?.id ?? normalized,
      'purpose' => t.purpose.toUpperCase(),
      'iban' => (t.counterpartyIban ?? '').toUpperCase(),
      _ => '${t.counterpartyName.toUpperCase()} $normalized',
    };
    if (r.field == 'merchant') return field.toUpperCase() == value || normalized == value;
    return r.operator == 'equals' ? field == value : field.contains(value);
  }

  Categorization categorize(Transaction t) {
    final normalized = normalizeMerchantName(t.counterpartyName);

    // Händler früh bestimmen (für Regeln und Firmenansicht)
    Merchant? merchant;
    final credMerchant = t.creditorId != null ? creditorMerchants[t.creditorId] : null;
    if (credMerchant != null) merchant = _merchants[credMerchant];
    merchant ??= matchMerchant(t.counterpartyName) ?? matchMerchant(normalized);
    if (merchant == null || merchant.aggregator) {
      merchant = matchMerchant(t.purpose) ?? merchant;
    }

    // 1) Eigene Regeln (höchste Priorität zuerst)
    if (rules.isNotEmpty) {
      final sorted = [...rules]..sort((a, b) => b.priority.compareTo(a.priority));
      for (final r in sorted) {
        if (_ruleMatches(r, t, normalized, merchant)) {
          switch (r.action) {
            case 'transfer':
              return Categorization(categoryId: 'umbuchung', merchantId: merchant?.id, reason: 'Eigene Regel', transfer: true);
            case 'exclude':
              return Categorization(categoryId: t.categoryId, merchantId: merchant?.id, reason: 'Eigene Regel', exclude: true);
            default:
              return Categorization(categoryId: r.actionValue, merchantId: merchant?.id, reason: 'Eigene Regel');
          }
        }
      }
    }

    // 2) Umbuchung zwischen eigenen Konten
    final iban = t.counterpartyIban?.replaceAll(' ', '').toUpperCase();
    if (iban != null && iban.isNotEmpty && ownIbans.contains(iban)) {
      return const Categorization(categoryId: 'umbuchung', reason: 'Eigenes Konto', transfer: true);
    }

    // 3) Gläubiger-ID (SEPA-Lastschrift)
    if (t.creditorId != null && creditorCategories.containsKey(t.creditorId)) {
      return Categorization(categoryId: creditorCategories[t.creditorId], merchantId: merchant?.id, reason: 'Gläubiger-ID ${t.creditorId}');
    }

    // 4) Händler-Datenbank (verfeinert durch Stichwörter derselben Oberkategorie,
    //    z. B. Stadtwerke + „Wasser“ → Wasser statt Strom)
    if (merchant != null && merchant.defaultCategoryId != null) {
      var cat = merchant.defaultCategoryId!;
      final refined = _keywordCategory(t.purpose.toUpperCase(), t);
      if (refined != null && refined != cat && _parentOf(refined) != null && _parentOf(refined) == _parentOf(cat)) cat = refined;
      // Gutschriften eines Händlers sind Erstattungen, keine Ausgaben.
      if (t.isIncome && _categories[cat]?.kind == CategoryKind.ausgabe) {
        return Categorization(categoryId: 'erstattung', merchantId: merchant.id, reason: 'Gutschrift ${merchant.displayName}');
      }
      return Categorization(categoryId: cat, merchantId: merchant.id, reason: 'Händler ${merchant.displayName}');
    }

    // 5) Stichwörter in Name/Zweck
    final hay = '$normalized ${t.purpose}'.toUpperCase();
    for (final (regex, cat, word) in _keywordRegexes) {
      if (!regex.hasMatch(hay) || !_kindFits(cat, t)) continue;
      return Categorization(categoryId: cat, merchantId: merchant?.id, reason: 'Stichwort „$word“', transfer: cat == 'umbuchung');
    }

    // 6) Fallback
    if (t.isIncome) {
      return Categorization(categoryId: 'sonstiges-einkommen', merchantId: merchant?.id, reason: 'Eingang');
    }
    return Categorization(merchantId: merchant?.id, reason: 'Unkategorisiert');
  }
}
