import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../data/models.dart';
import '../analytics/analytics.dart';
import 'categorize.dart';
import 'contracts.dart';
import 'insights.dart';

/// Stammdaten: Kategorien, Händler, Gläubiger-IDs.
class SeedData {
  final List<Category> categories;
  final List<Merchant> merchants;
  final Map<String, String> creditorCategories;
  final Map<String, String> creditorMerchants;

  const SeedData({
    this.categories = const [],
    this.merchants = const [],
    this.creditorCategories = const {},
    this.creditorMerchants = const {},
  });

  factory SeedData.fromJsonStrings({required String categories, required String merchants, required String creditors}) {
    final flat = <Category>[];
    void walk(List<dynamic> list, String? parent) {
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        flat.add(Category.fromJson({...m, 'parentId': parent}));
        final children = m['children'] as List?;
        if (children != null) walk(children, m['id'] as String);
      }
    }

    walk((jsonDecode(categories) as Map<String, dynamic>)['categories'] as List, null);
    final merch = ((jsonDecode(merchants) as Map<String, dynamic>)['merchants'] as List)
        .map((e) => Merchant.fromJson(e as Map<String, dynamic>))
        .toList();
    final cred = (jsonDecode(creditors) as Map<String, dynamic>)['creditorIds'] as List;
    return SeedData(
      categories: flat,
      merchants: merch,
      creditorCategories: {for (final e in cred) (e as Map<String, dynamic>)['id'] as String: e['category'] as String},
      creditorMerchants: {
        for (final e in cred)
          if ((e as Map<String, dynamic>)['merchant'] != null) e['id'] as String: e['merchant'] as String,
      },
    );
  }

  static Future<SeedData> loadFromAssets() async {
    try {
      return SeedData.fromJsonStrings(
        categories: await rootBundle.loadString('assets/data/categories.json'),
        merchants: await rootBundle.loadString('assets/data/merchants.json'),
        creditors: await rootBundle.loadString('assets/data/creditor_ids.json'),
      );
    } catch (_) {
      return const SeedData();
    }
  }
}

/// Ergebnis eines Analyse-Laufs.
class EngineResult {
  final List<Transaction> transactions;
  final List<Contract> contracts;
  final List<Insight> insights;
  final int uncategorizedCount;

  const EngineResult({
    required this.transactions,
    required this.contracts,
    required this.insights,
    required this.uncategorizedCount,
  });
}

/// Analyse-Engine: kategorisiert Umsätze, erkennt Verträge und leitet Spar-Hinweise ab.
class Engine {
  Engine([this.seed = const SeedData()]) {
    for (final c in seed.categories) {
      _categories[c.id] = c;
    }
    for (final m in seed.merchants) {
      _merchants[m.id] = m;
    }
  }

  final SeedData seed;
  final Map<String, Category> _categories = {};
  final Map<String, Merchant> _merchants = {};

  List<Category> get categories => seed.categories;
  List<Merchant> get merchants => seed.merchants;

  Category? categoryById(String? id) => id == null ? null : _categories[id];
  Merchant? merchantById(String? id) => id == null ? null : _merchants[id];

  Analytics analytics({required List<Transaction> transactions, required List<Account> accounts, DateTime? now}) => Analytics(
        transactions: transactions,
        accounts: accounts,
        categoryOf: categoryById,
        merchantNameOf: (id) => merchantById(id)?.displayName,
        now: now,
      );

  /// Analysiert alle Umsätze. Nutzerentscheidungen (manuelle Kategorien) bleiben unangetastet.
  EngineResult run({
    required List<Transaction> transactions,
    required List<Account> accounts,
    required List<Rule> rules,
    required List<Contract> existingContracts,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final cat = Categorizer(
      categories: seed.categories,
      merchants: seed.merchants,
      creditorCategories: seed.creditorCategories,
      creditorMerchants: seed.creditorMerchants,
      rules: rules,
      ownIbans: accounts.map((a) => a.iban.replaceAll(' ', '').toUpperCase()).where((i) => i.length > 10).toSet(),
    );

    final txs = transactions.map((t) {
      final r = cat.categorize(t);
      if (t.manualCategory) {
        return t.copyWith(merchantId: r.merchantId, clearContract: true);
      }
      return t.copyWith(
        categoryId: r.categoryId ?? '',
        merchantId: r.merchantId,
        clearMerchant: r.merchantId == null,
        categoryReason: r.reason,
        isTransfer: r.transfer || t.isTransfer,
        excluded: r.exclude || t.excluded,
        clearContract: true,
      );
    }).toList();

    // Verträge erkennen
    final detected = ContractDetector(now: at, merchantName: (id) => merchantById(id)?.displayName).detectAll(txs);
    final contracts = _mergeContracts(existingContracts, detected);

    // Vertrags-IDs an Umsätze hängen (nur laufende/bestätigte Verträge)
    final txToContract = <String, String>{};
    for (final c in contracts) {
      if (c.status == ContractStatus.ignoriert) continue;
      for (final id in c.transactionIds) {
        txToContract[id] = c.id;
      }
    }
    final linked = [
      for (final t in txs) txToContract.containsKey(t.id) ? t.copyWith(contractId: txToContract[t.id]) : t,
    ];

    final insights = InsightEngine(
      now: at,
      analytics: analytics(transactions: linked, accounts: accounts, now: at),
      merchantOf: merchantById,
    ).run(linked, contracts);

    final uncategorized = linked.where((t) => (t.categoryId ?? '').isEmpty && !t.isTransfer && !t.excluded).length;

    return EngineResult(transactions: linked, contracts: contracts, insights: insights, uncategorizedCount: uncategorized);
  }

  /// Führt erkannte Verträge mit den gespeicherten zusammen:
  /// Status und Namen des Nutzers bleiben, Zahlungsdaten werden aktualisiert.
  List<Contract> _mergeContracts(List<Contract> existing, List<Contract> detected) {
    final byId = {for (final c in existing) c.id: c};
    final out = <Contract>[];
    final seen = <String>{};
    for (final d in detected) {
      seen.add(d.id);
      final old = byId[d.id];
      if (old == null) {
        // Sehr sichere Erkennungen gleich als aktiv übernehmen, Rest als Vorschlag.
        final autoActive = d.status != ContractStatus.beendet && d.confidence >= 0.85;
        out.add(autoActive ? d.copyWith(status: ContractStatus.aktiv) : d);
        continue;
      }
      var status = old.status;
      if (d.status == ContractStatus.beendet && (status == ContractStatus.aktiv || status == ContractStatus.vorschlag || status == ContractStatus.gekuendigt)) {
        status = ContractStatus.beendet;
      } else if (d.status != ContractStatus.beendet && status == ContractStatus.beendet && !old.userConfirmed) {
        status = ContractStatus.aktiv; // Zahlungen laufen wieder
      }
      out.add(Contract(
        id: old.id,
        merchantId: d.merchantId ?? old.merchantId,
        name: old.userConfirmed ? old.name : d.name,
        interval: old.userConfirmed ? old.interval : d.interval,
        expectedCents: d.expectedCents,
        previousCents: d.previousCents,
        nextDue: d.nextDue,
        lastPayment: d.lastPayment,
        confidence: d.confidence,
        status: status,
        noticePeriod: old.noticePeriod,
        minTermEnd: old.minTermEnd,
        reminder: old.reminder,
        categoryId: old.userConfirmed && old.categoryId != null ? old.categoryId : d.categoryId,
        accountId: d.accountId,
        reason: d.reason,
        transactionIds: d.transactionIds,
        userConfirmed: old.userConfirmed,
      ));
    }
    // Manuell angelegte oder bestätigte Verträge ohne aktuelle Erkennung behalten.
    for (final c in existing) {
      if (seen.contains(c.id)) continue;
      if (c.userConfirmed || c.transactionIds.isEmpty || c.status == ContractStatus.ignoriert) out.add(c);
    }
    return out;
  }
}
