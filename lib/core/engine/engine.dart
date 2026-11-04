import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../data/models.dart';
import '../../data/store.dart';
import 'categorize.dart';
import 'contracts.dart';
import 'insights.dart';
import 'normalize.dart';

/// Ergebnis einer Analyse-Lauf.
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

/// Analyse-Engine: lädt Seed-Daten (Kategorien, Händler, Gläubiger-IDs),
/// kategorisiert Umsätze, erkennt Verträge und leitet Insights ab.
class Engine {
  Engine(this.store);

  final Store store;

  List<Category> categories = [];
  List<Merchant> merchants = [];
  Map<String, String> creditorCategories = {};
  Categorizer? _categorizer;

  Category? categoryById(String? id) => _categorizer?.categoryById(id);

  Merchant? merchantById(String? id) {
    if (id == null) return null;
    for (final m in merchants) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> loadSeedData() async {
    try {
      final catJson = jsonDecode(await rootBundle.loadString('assets/data/categories.json')) as Map<String, dynamic>;
      final flat = <Category>[];
      void walk(List<dynamic> list, String? parent) {
        for (final e in list) {
          final m = e as Map<String, dynamic>;
          flat.add(Category.fromJson({...m, 'parentId': parent}));
          final children = m['children'] as List?;
          if (children != null) walk(children, m['id'] as String);
        }
      }
      walk(catJson['categories'] as List, null);
      categories = flat;
    } catch (_) {
      categories = [];
    }

    try {
      final merchJson = jsonDecode(await rootBundle.loadString('assets/data/merchants.json')) as Map<String, dynamic>;
      merchants = (merchJson['merchants'] as List)
          .map((e) => Merchant(
                id: (e as Map<String, dynamic>)['id'] as String,
                normalizedName: e['normalizedName'] as String,
                displayName: e['displayName'] as String,
                defaultCategoryId: e['category'] as String?,
              ))
          .toList();
    } catch (_) {
      merchants = [];
    }

    try {
      final credJson = jsonDecode(await rootBundle.loadString('assets/data/creditor_ids.json')) as Map<String, dynamic>;
      creditorCategories = {
        for (final e in credJson['creditorIds'] as List)
          (e as Map<String, dynamic>)['id'] as String: e['category'] as String,
      };
    } catch (_) {
      creditorCategories = {};
    }

    _categorizer = Categorizer(categories: categories, merchants: merchants, creditorCategories: creditorCategories)..index();
  }

  /// Führt die Analyse über alle gespeicherten Umsätze aus.
  Future<EngineResult> run() async {
    if (_categorizer == null) await loadSeedData();
    final cat = _categorizer!;

    final txs = store.transactions.map((t) {
      if (t.categoryId != null && t.categoryId!.isNotEmpty) return t;
      final r = cat.categorize(t);
      return t.copyWith(categoryId: r.categoryId, merchantId: r.merchantId, categoryReason: r.reason);
    }).toList();

    final detector = ContractDetector();
    final contracts = <Contract>[];
    for (final entry in detector.group(txs).entries) {
      final c = detector.detect(entry.key, entry.value);
      if (c != null) contracts.add(c);
    }

    // Vertrags-IDs an Transaktionen hängen
    final withContracts = txs.map((t) {
      for (final c in contracts) {
        if (c.transactionIds.contains(t.id)) return t.copyWith(contractId: c.id);
      }
      return t;
    }).toList();

    final insights = InsightEngine(DateTime.now()).run(withContracts, contracts);
    final uncategorized = withContracts.where((t) => (t.categoryId ?? '').isEmpty && !t.isTransfer && !t.excluded).length;

    return EngineResult(
      transactions: withContracts,
      contracts: contracts,
      insights: insights,
      uncategorizedCount: uncategorized,
    );
  }

  /// Lädt Demo-Daten, falls noch keine Bank verbunden ist (rein lokal, kein Netzwerk).
  Future<void> loadSeedDemoIfEmpty() async {
    if (store.transactions.isNotEmpty || store.accounts.isEmpty) return;
    // Wird vom Onboarding selbst aufgerufen – hier nur Platzhalter.
  }
}
