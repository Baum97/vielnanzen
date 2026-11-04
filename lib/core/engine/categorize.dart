import '../../data/models.dart';
import 'normalize.dart';

/// Schritt 3 der Pipeline: Kategorie-Zuordnung.
/// Reihenfolge: eigene Regeln -> Creditor-ID -> Händler-Default -> Keyword -> unkategorisiert.

class Categorizer {
  Categorizer({required this.categories, required this.merchants, required this.creditorCategories});

  final List<Category> categories;
  final List<Merchant> merchants;
  final Map<String, String> creditorCategories; // creditorId -> categoryId

  final Map<String, Merchant> _byNormalized = {};
  final Map<String, String> _keywords = {
    'REWE': 'supermarkt',
    'EDEKA': 'supermarkt',
    'ALDI': 'supermarkt',
    'LIDL': 'supermarkt',
    'NETTO': 'supermarkt',
    'KAUFland': 'supermarkt',
    'ROSSMANN': 'drogerie',
    'DM ': 'drogerie',
    'BAECKER': 'baecker',
    'BAKER': 'baecker',
    'NETFLIX': 'streaming-video',
    'SPOTIFY': 'streaming-audio',
    'DISNEY': 'streaming-video',
    'AMAZON PRIME': 'streaming-video',
    'TELEKOM': 'internet-tel',
    'VODAFONE': 'internet-tel',
    'O2': 'internet-tel',
    '1&1': 'internet-tel',
    'TK ': 'krankenversicherung',
    'TECHNIKER': 'krankenversicherung',
    'STADTWERKE': 'strom-gas',
    'E.ON': 'strom-gas',
    'ENTEGA': 'strom-gas',
    'VERMIETER': 'miete',
    'MIETE': 'miete',
    'ARBEITGEBER': 'gehalt',
    'GEHALT': 'gehalt',
    'ARGE': 'gehalt',
    'SPARKASSE': 'bankgebuehren',
    'BANK': 'bankgebuehren',
    'ARZ': 'arzt',
    'APOTHEKE': 'apotheke',
    'TANKE': 'tanken',
    'SHELL': 'tanken',
    'ESSO': 'tanken',
    'TOTAL': 'tanken',
    'DB BAHN': 'oepnv',
    'BAHNx': 'oepnv',
    'UBER': 'taxi',
    'MCDONALDS': 'restaurant',
    'BURGER': 'restaurant',
    'RESTAURANT': 'restaurant',
    'CAFE': 'cafe',
    'KINO': 'freizeit',
    'MUSEUM': 'freizeit',
  };

  void index() {
    for (final m in merchants) {
      _byNormalized[m.normalizedName.toUpperCase()] = m;
    }
  }

  Category? categoryById(String? id) {
    if (id == null) return null;
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Liefert (categoryId, merchantId, reason).
  ({String? categoryId, String? merchantId, String reason}) categorize(Transaction t) {
    // 1) Creditor-ID
    if (t.creditorId != null && creditorCategories.containsKey(t.creditorId)) {
      return (categoryId: creditorCategories[t.creditorId], merchantId: null, reason: 'Gläubiger-ID ${t.creditorId}');
    }
    // 2) Händler-Default
    final norm = normalizeMerchantName(t.counterpartyName);
    final m = _byNormalized[norm];
    if (m != null) {
      return (categoryId: m.defaultCategoryId, merchantId: m.id, reason: 'Händler ${m.displayName}');
    }
    // 3) Keyword im Namen/Zweck
    final hay = '${t.counterpartyName} ${t.purpose}'.toUpperCase();
    for (final entry in _keywords.entries) {
      if (hay.contains(entry.key)) {
        return (categoryId: entry.value, merchantId: null, reason: 'Stichwort ${entry.key.trim()}');
      }
    }
    // 4) Einnahmen immer "Einnahme"
    if (t.isIncome) {
      final ein = categories.where((c) => c.kind == CategoryKind.einnahme).toList();
      if (ein.isNotEmpty) return (categoryId: ein.first.id, merchantId: null, reason: 'Einnahme');
    }
    return (categoryId: null, merchantId: null, reason: 'Unkategorisiert');
  }
}
