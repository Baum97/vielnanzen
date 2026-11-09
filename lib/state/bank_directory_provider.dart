import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/bank_directory.dart';

/// Banken ohne FinTS (N26, Trade Republic …) mit Hinweis.
class NoFintsBank {
  final String name;
  final String city;
  final String note;
  const NoFintsBank(this.name, this.city, this.note);
}

final bankDirectoryProvider = FutureProvider<BankDirectory>((ref) async {
  return BankDirectory.fromJsonString(await rootBundle.loadString('assets/data/bank_directory.json'));
});

final noFintsBanksProvider = FutureProvider<List<NoFintsBank>>((ref) async {
  final j = jsonDecode(await rootBundle.loadString('assets/data/banks.json')) as Map<String, dynamic>;
  return [
    for (final b in j['banks'] as List)
      NoFintsBank(b['name'] as String, (b['city'] ?? '') as String, (b['note'] ?? '') as String),
  ];
});
