import 'dart:math' as math;

import '../../data/models.dart';
import '../engine/normalize.dart';
import 'time_range.dart';

/// Kennzahlen eines Zeitraums.
class PeriodSummary {
  final int incomeCents;
  final int expenseCents; // positiv
  final int savedCents; // Umbuchungen auf Spar-/Depotkonten (positiv)
  final int fixedCents; // Anteil der Ausgaben aus erkannten Verträgen
  final int expenseCount;
  final int incomeCount;
  final int days;

  const PeriodSummary({
    required this.incomeCents,
    required this.expenseCents,
    required this.savedCents,
    required this.fixedCents,
    required this.expenseCount,
    required this.incomeCount,
    required this.days,
  });

  int get netCents => incomeCents - expenseCents;
  int get variableCents => expenseCents - fixedCents;

  /// Sparquote: (Einnahmen − Ausgaben) / Einnahmen.
  double? get savingsRate => incomeCents > 0 ? netCents / incomeCents : null;
  int get avgPerDayCents => days > 0 ? (expenseCents / days).round() : 0;
  int get avgPerMonthCents => days > 0 ? (expenseCents / days * 30.44).round() : 0;
}

class CategoryStat {
  final String categoryId;
  final String name;
  final String color;
  final int cents;
  final int count;
  final double share;
  final int previousCents;
  final List<CategoryStat> children;

  const CategoryStat({
    required this.categoryId,
    required this.name,
    required this.color,
    required this.cents,
    required this.count,
    required this.share,
    required this.previousCents,
    this.children = const [],
  });

  /// Veränderung ggü. Vorperiode in Prozent (null, wenn keine Vorperiode).
  double? get changePct => previousCents > 0 ? (cents - previousCents) / previousCents : null;
}

class MerchantStat {
  final String key;
  final String name;
  final String? merchantId;
  final String? categoryId;
  final int cents;
  final int count;
  final double share;
  final int previousCents;
  final DateTime first;
  final DateTime last;
  final bool recurring;

  const MerchantStat({
    required this.key,
    required this.name,
    this.merchantId,
    this.categoryId,
    required this.cents,
    required this.count,
    required this.share,
    required this.previousCents,
    required this.first,
    required this.last,
    required this.recurring,
  });

  int get avgCents => count > 0 ? (cents / count).round() : 0;
  double? get changePct => previousCents > 0 ? (cents - previousCents) / previousCents : null;
}

class CashflowBucket {
  final DateTime start;
  final int incomeCents;
  final int expenseCents;
  const CashflowBucket(this.start, this.incomeCents, this.expenseCents);
  int get netCents => incomeCents - expenseCents;
}

/// Vollständige Auswertung eines Zeitraums.
class PeriodAnalysis {
  final TimeRange range;
  final DateTime from;
  final DateTime to;
  final Bucket bucket;
  final PeriodSummary summary;
  final PeriodSummary previous;
  final List<CategoryStat> categories; // Oberkategorien, absteigend
  final List<CategoryStat> incomeCategories;
  final List<MerchantStat> merchants; // absteigend
  final List<CashflowBucket> cashflow;
  final List<(DateTime, int)> balance;
  final List<int> weekdayCents; // Mo..So
  final List<int> weekdayCounts;
  final List<int> monthPhaseCents; // Anfang (1–10), Mitte (11–20), Ende (21–31)
  final List<Transaction> largest;
  final List<Transaction> expenses;
  final List<Transaction> incomes;

  const PeriodAnalysis({
    required this.range,
    required this.from,
    required this.to,
    required this.bucket,
    required this.summary,
    required this.previous,
    required this.categories,
    required this.incomeCategories,
    required this.merchants,
    required this.cashflow,
    required this.balance,
    required this.weekdayCents,
    required this.weekdayCounts,
    required this.monthPhaseCents,
    required this.largest,
    required this.expenses,
    required this.incomes,
  });

  double? get expenseChangePct =>
      previous.expenseCents > 0 ? (summary.expenseCents - previous.expenseCents) / previous.expenseCents : null;
  double? get incomeChangePct =>
      previous.incomeCents > 0 ? (summary.incomeCents - previous.incomeCents) / previous.incomeCents : null;
}

/// Reine Auswertungsfunktionen über Umsätze – ohne Flutter, gut testbar.
class Analytics {
  Analytics({
    required this.transactions,
    required this.accounts,
    required this.categoryOf,
    required this.merchantNameOf,
    DateTime? now,
  }) : now = now ?? DateTime.now();

  final List<Transaction> transactions;
  final List<Account> accounts;
  final Category? Function(String? id) categoryOf;
  final String? Function(String? merchantId) merchantNameOf;
  final DateTime now;

  CategoryKind? _kind(Transaction t) => categoryOf(t.categoryId)?.kind;

  bool isExpense(Transaction t) =>
      t.amountCents < 0 && !t.excluded && !t.isTransfer && _kind(t) != CategoryKind.umbuchung;

  bool isIncome(Transaction t) =>
      t.amountCents > 0 && !t.excluded && !t.isTransfer && _kind(t) != CategoryKind.umbuchung;

  bool isSaving(Transaction t) => t.amountCents < 0 && !t.excluded && t.categoryId == 'sparen';

  DateTime? get earliest {
    DateTime? e;
    for (final t in transactions) {
      if (e == null || t.bookingDate.isBefore(e)) e = t.bookingDate;
    }
    return e;
  }

  String merchantKey(Transaction t) => t.merchantId ?? 'n:${normalizeMerchantName(t.counterpartyName)}';

  String merchantDisplay(Transaction t) {
    final known = merchantNameOf(t.merchantId);
    if (known != null) return known;
    final n = normalizeMerchantName(t.counterpartyName);
    if (n.isNotEmpty) return prettifyName(n);
    return t.counterpartyName.isEmpty ? 'Unbekannt' : t.counterpartyName;
  }

  /// Oberkategorie (für Donut/Liste); Unterkategorien werden aufgerollt.
  Category? topCategory(String? id) {
    var c = categoryOf(id);
    var guard = 0;
    while (c != null && c.parentId != null && guard++ < 5) {
      c = categoryOf(c.parentId);
    }
    return c;
  }

  List<Transaction> inRange(DateTime from, DateTime to) =>
      transactions.where((t) => !t.bookingDate.isBefore(from) && t.bookingDate.isBefore(to)).toList();

  PeriodSummary summarize(List<Transaction> txs, int days) {
    var inc = 0, exp = 0, saved = 0, fixed = 0, ec = 0, ic = 0;
    for (final t in txs) {
      if (isExpense(t)) {
        exp -= t.amountCents;
        ec++;
        if (t.contractId != null) fixed -= t.amountCents;
      } else if (isIncome(t)) {
        inc += t.amountCents;
        ic++;
      } else if (isSaving(t)) {
        saved -= t.amountCents;
      }
    }
    return PeriodSummary(
      incomeCents: inc,
      expenseCents: exp,
      savedCents: saved,
      fixedCents: fixed,
      expenseCount: ec,
      incomeCount: ic,
      days: days,
    );
  }

  List<CategoryStat> categoryStats(List<Transaction> txs, List<Transaction> prev, {bool income = false}) {
    bool take(Transaction t) => income ? isIncome(t) : isExpense(t);
    final cur = <String, Map<String, (int, int)>>{}; // top -> sub -> (cents, count)
    final prevTop = <String, int>{};
    final prevSub = <String, int>{};
    var total = 0;
    for (final t in txs.where(take)) {
      final a = t.amountCents.abs();
      final top = topCategory(t.categoryId)?.id ?? 'sonstiges';
      final sub = t.categoryId ?? 'sonstiges';
      final m = cur.putIfAbsent(top, () => {});
      final v = m[sub] ?? (0, 0);
      m[sub] = (v.$1 + a, v.$2 + 1);
      total += a;
    }
    for (final t in prev.where(take)) {
      final a = t.amountCents.abs();
      final top = topCategory(t.categoryId)?.id ?? 'sonstiges';
      prevTop[top] = (prevTop[top] ?? 0) + a;
      final sub = t.categoryId ?? 'sonstiges';
      prevSub[sub] = (prevSub[sub] ?? 0) + a;
    }
    final out = <CategoryStat>[];
    for (final e in cur.entries) {
      final cat = categoryOf(e.key);
      final topCents = e.value.values.fold<int>(0, (a, v) => a + v.$1);
      final topCount = e.value.values.fold<int>(0, (a, v) => a + v.$2);
      final children = <CategoryStat>[
        for (final s in e.value.entries)
          CategoryStat(
            categoryId: s.key,
            name: categoryOf(s.key)?.name ?? 'Unkategorisiert',
            color: categoryOf(s.key)?.color ?? cat?.color ?? '#9A9EA5',
            cents: s.value.$1,
            count: s.value.$2,
            share: topCents > 0 ? s.value.$1 / topCents : 0,
            previousCents: prevSub[s.key] ?? 0,
          ),
      ]..sort((a, b) => b.cents.compareTo(a.cents));
      out.add(CategoryStat(
        categoryId: e.key,
        name: cat?.name ?? 'Unkategorisiert',
        color: cat?.color ?? '#9A9EA5',
        cents: topCents,
        count: topCount,
        share: total > 0 ? topCents / total : 0,
        previousCents: prevTop[e.key] ?? 0,
        children: children,
      ));
    }
    out.sort((a, b) => b.cents.compareTo(a.cents));
    return out;
  }

  List<MerchantStat> merchantStats(List<Transaction> txs, List<Transaction> prev) {
    final groups = <String, List<Transaction>>{};
    var total = 0;
    for (final t in txs.where(isExpense)) {
      groups.putIfAbsent(merchantKey(t), () => []).add(t);
      total -= t.amountCents;
    }
    final prevSum = <String, int>{};
    for (final t in prev.where(isExpense)) {
      final k = merchantKey(t);
      prevSum[k] = (prevSum[k] ?? 0) - t.amountCents;
    }
    final out = <MerchantStat>[];
    for (final e in groups.entries) {
      final list = e.value..sort((a, b) => a.bookingDate.compareTo(b.bookingDate));
      final cents = list.fold<int>(0, (a, t) => a - t.amountCents);
      // Häufigste Kategorie
      final catCount = <String, int>{};
      for (final t in list) {
        if (t.categoryId != null) catCount[t.categoryId!] = (catCount[t.categoryId!] ?? 0) + 1;
      }
      final cat = catCount.entries.isEmpty ? null : (catCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
      out.add(MerchantStat(
        key: e.key,
        name: merchantDisplay(list.last),
        merchantId: list.last.merchantId,
        categoryId: cat,
        cents: cents,
        count: list.length,
        share: total > 0 ? cents / total : 0,
        previousCents: prevSum[e.key] ?? 0,
        first: list.first.bookingDate,
        last: list.last.bookingDate,
        recurring: list.any((t) => t.contractId != null),
      ));
    }
    out.sort((a, b) => b.cents.compareTo(a.cents));
    return out;
  }

  List<CashflowBucket> cashflow(List<Transaction> txs, DateTime from, DateTime to, Bucket b) {
    final buckets = <DateTime, (int, int)>{};
    for (var d = bucketStart(from, b); d.isBefore(to); d = nextBucket(d, b)) {
      buckets[d] = (0, 0);
    }
    for (final t in txs) {
      final k = bucketStart(t.bookingDate, b);
      final v = buckets[k];
      if (v == null) continue;
      if (isIncome(t)) {
        buckets[k] = (v.$1 + t.amountCents, v.$2);
      } else if (isExpense(t)) {
        buckets[k] = (v.$1, v.$2 - t.amountCents);
      }
    }
    return [for (final e in buckets.entries) CashflowBucket(e.key, e.value.$1, e.value.$2)];
  }

  /// Saldoverlauf aller in die Summe einbezogenen Konten (rückwärts aus dem aktuellen Saldo).
  List<(DateTime, int)> balanceSeries(DateTime from, DateTime to) {
    final included = accounts.where((a) => a.includeInTotal && !a.hidden).toList();
    final ids = included.map((a) => a.id).toSet();
    final total = included.fold<int>(0, (a, acc) => a + acc.balanceCents);
    final txs = transactions.where((t) => ids.contains(t.accountId) && !t.pending).toList()
      ..sort((a, b) => b.bookingDate.compareTo(a.bookingDate));

    final span = to.difference(from).inDays;
    final step = span <= 93 ? 1 : (span <= 2 * 366 ? 7 : 30);
    final points = <(DateTime, int)>[];
    var bal = total;
    var i = 0;
    // Punkte von heute rückwärts; Saldo am Tagesende.
    for (var d = DateTime(to.year, to.month, to.day - 1); !d.isBefore(from); d = DateTime(d.year, d.month, d.day - step)) {
      final dayEnd = DateTime(d.year, d.month, d.day + 1);
      while (i < txs.length && !txs[i].bookingDate.isBefore(dayEnd)) {
        bal -= txs[i].amountCents;
        i++;
      }
      points.add((d, bal));
    }
    // Startpunkt exakt am Periodenbeginn
    if (points.isEmpty || points.last.$1.isAfter(from)) {
      while (i < txs.length && !txs[i].bookingDate.isBefore(from)) {
        bal -= txs[i].amountCents;
        i++;
      }
      points.add((from, bal));
    }
    return points.reversed.toList();
  }

  PeriodAnalysis analyze(TimeRange range) {
    final early = earliest;
    var from = range.start(now, earliest: early);
    final to = range.end(now);
    final prevBounds = range.previous(now, earliest: early);
    final days = math.max(1, to.difference(from).inDays);
    final txs = inRange(from, to);
    final prev = range == TimeRange.max ? <Transaction>[] : inRange(prevBounds.from, prevBounds.to);
    final bucket = range.bucketFor(days);

    final expenses = txs.where(isExpense).toList()..sort((a, b) => b.bookingDate.compareTo(a.bookingDate));
    final incomes = txs.where(isIncome).toList()..sort((a, b) => b.bookingDate.compareTo(a.bookingDate));

    final weekday = List<int>.filled(7, 0);
    final weekdayCount = List<int>.filled(7, 0);
    final phase = List<int>.filled(3, 0);
    for (final t in expenses) {
      weekday[t.bookingDate.weekday - 1] -= t.amountCents;
      weekdayCount[t.bookingDate.weekday - 1]++;
      final d = t.bookingDate.day;
      phase[d <= 10 ? 0 : (d <= 20 ? 1 : 2)] -= t.amountCents;
    }
    final largest = [...expenses]..sort((a, b) => a.amountCents.compareTo(b.amountCents));

    return PeriodAnalysis(
      range: range,
      from: from,
      to: to,
      bucket: bucket,
      summary: summarize(txs, days),
      previous: summarize(prev, days),
      categories: categoryStats(txs, prev),
      incomeCategories: categoryStats(txs, prev, income: true),
      merchants: merchantStats(txs, prev),
      cashflow: cashflow(txs, from, to, bucket),
      balance: balanceSeries(from, to),
      weekdayCents: weekday,
      weekdayCounts: weekdayCount,
      monthPhaseCents: phase,
      largest: largest.take(10).toList(),
      expenses: expenses,
      incomes: incomes,
    );
  }

  /// Monatliche Ausgaben einer Kategorie (für Budget-Vorschläge), Durchschnitt der letzten [months] vollen Monate.
  int averageMonthly(bool Function(Transaction t) where, {int months = 3}) {
    final end = DateTime(now.year, now.month, 1);
    final start = DateTime(now.year, now.month - months, 1);
    final sum = transactions
        .where((t) => isExpense(t) && where(t) && !t.bookingDate.isBefore(start) && t.bookingDate.isBefore(end))
        .fold<int>(0, (a, t) => a - t.amountCents);
    return (sum / months).round();
  }

  /// Ausgaben im laufenden Monat für eine Bedingung.
  int currentMonth(bool Function(Transaction t) where) {
    final start = DateTime(now.year, now.month, 1);
    return transactions
        .where((t) => isExpense(t) && where(t) && !t.bookingDate.isBefore(start))
        .fold<int>(0, (a, t) => a - t.amountCents);
  }

  /// Monatssummen für einen Händler (letzte [months] Monate, älteste zuerst).
  List<(DateTime, int)> monthlyFor(bool Function(Transaction t) where, {int months = 12}) {
    final out = <(DateTime, int)>[];
    for (var i = months - 1; i >= 0; i--) {
      final s = DateTime(now.year, now.month - i, 1);
      final e = DateTime(s.year, s.month + 1, 1);
      final sum = transactions
          .where((t) => isExpense(t) && where(t) && !t.bookingDate.isBefore(s) && t.bookingDate.isBefore(e))
          .fold<int>(0, (a, t) => a - t.amountCents);
      out.add((s, sum));
    }
    return out;
  }
}
