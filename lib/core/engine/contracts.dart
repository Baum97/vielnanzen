import 'dart:math' as math;

import '../../data/models.dart';
import 'normalize.dart';

/// Schritt 7: Vertrags- und Abo-Erkennung aus wiederkehrenden Abbuchungen.
class ContractDetector {
  ContractDetector({DateTime? now, this.merchantName, this.excludedCategories = defaultExcluded})
      : now = now ?? DateTime.now();

  final DateTime now;

  /// Anzeigename eines Händlers (merchantId → Name).
  final String? Function(String? merchantId)? merchantName;

  /// Kategorien mit regelmäßigen, aber nicht vertraglichen Einkäufen.
  final Set<String> excludedCategories;

  static const defaultExcluded = {
    'supermarkt',
    'baecker',
    'drogerie',
    'markt',
    'tanken',
    'restaurant',
    'lieferdienst',
    'online-shopping',
    'kleidung',
    'bargeld',
    'taxi',
    'parken',
    'umbuchung',
    'sparen',
    'apotheke',
    'reisen',
    'werkstatt',
    'elektronik',
    'moebel',
    'hobby',
    'kino',
    'spenden',
  };

  static const _intervals = <(ContractInterval, int days, int tolerance)>[
    (ContractInterval.woechentlich, 7, 2),
    (ContractInterval.zweiwoechentlich, 14, 3),
    (ContractInterval.monatlich, 30, 6),
    (ContractInterval.quartalsweise, 91, 15),
    (ContractInterval.halbjahrlich, 182, 20),
    (ContractInterval.jaehrlich, 365, 30),
  ];

  /// Gruppiert Abbuchungen: Mandat (stabil pro Vertrag) → Gläubiger-ID → Händler → Name.
  Map<String, List<Transaction>> group(List<Transaction> txs) {
    final map = <String, List<Transaction>>{};
    for (final t in txs) {
      if (t.amountCents >= 0 || t.isTransfer || t.excluded) continue;
      final mandated = t.mandateRef != null && t.mandateRef!.isNotEmpty;
      if (!mandated && excludedCategories.contains(t.categoryId)) continue;
      final String key;
      if (mandated) {
        key = 'mref:${t.creditorId ?? normalizeMerchantName(t.counterpartyName)}|${t.mandateRef}';
      } else if (t.creditorId != null) {
        key = 'cred:${t.creditorId}';
      } else if (t.merchantId != null) {
        key = 'm:${t.merchantId}';
      } else {
        key = 'name:${normalizeMerchantName(t.counterpartyName)}';
      }
      map.putIfAbsent(key, () => []).add(t);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.bookingDate.compareTo(b.bookingDate));
    }
    return map;
  }

  /// Teilt eine Gruppe in Betragsklassen (z. B. Strom 79 € und Wasser 25 € beim selben Versorger).
  /// Preisänderungen bis ±35 % bleiben in derselben Klasse.
  List<List<Transaction>> _clusters(List<Transaction> list) {
    final clusters = <List<Transaction>>[];
    for (final t in list) {
      final a = t.amountCents.abs();
      List<Transaction>? best;
      var bestDiff = double.infinity;
      for (final c in clusters) {
        final ref = c.last.amountCents.abs();
        final diff = (a - ref).abs() / math.max(ref, 1);
        if (diff <= 0.35 && diff < bestDiff) {
          best = c;
          bestDiff = diff;
        }
      }
      if (best != null) {
        best.add(t);
      } else {
        clusters.add([t]);
      }
    }
    return clusters;
  }

  List<Contract> detectAll(List<Transaction> txs) {
    final out = <Contract>[];
    for (final e in group(txs).entries) {
      final clusters = _clusters(e.value);
      final found = <Contract>[];
      for (var i = 0; i < clusters.length; i++) {
        final c = detect(clusters.length == 1 ? e.key : '${e.key}#${_amountBand(clusters[i])}', clusters[i]);
        if (c != null) found.add(c);
      }
      // Mehrere Verträge beim selben Anbieter unterscheidbar benennen
      if (found.length > 1) {
        for (var i = 0; i < found.length; i++) {
          final last = clusters.firstWhere((cl) => cl.any((t) => t.id == found[i].transactionIds.last)).last;
          final hint = _purposeHint(last.purpose);
          found[i] = hint == null ? found[i] : found[i].copyWith(name: '${found[i].name} · $hint');
        }
      }
      out.addAll(found);
    }
    // Gleichnamige Verträge (z. B. Strom und Wasser beim Stadtwerk) unterscheidbar machen
    final byName = <String, List<int>>{};
    for (var i = 0; i < out.length; i++) {
      if (!out[i].name.contains(' · ')) byName.putIfAbsent(out[i].name, () => []).add(i);
    }
    final byId = {for (final t in txs) t.id: t};
    for (final idx in byName.values.where((l) => l.length > 1)) {
      for (final i in idx) {
        final hint = _purposeHint(byId[out[i].transactionIds.last]?.purpose ?? '');
        if (hint != null) out[i] = out[i].copyWith(name: '${out[i].name} · $hint');
      }
    }
    return out;
  }

  static String? _purposeHint(String purpose) {
    final cleaned = purpose
        .replaceAll(RegExp(r'(EREF|MREF|CRED|SVWZ|KREF)\+\S*', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\d[\d./-]*'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return null;
    return cleaned.length > 24 ? '${cleaned.substring(0, 23)}…' : cleaned;
  }

  static int _amountBand(List<Transaction> list) => (list.first.amountCents.abs() / 500).round();

  /// Erkennt aus einer Reihe gleichartiger Buchungen einen Vertrag – oder null.
  Contract? detect(String key, List<Transaction> list) {
    if (list.length < 2) return null;
    final sorted = [...list]..sort((a, b) => a.bookingDate.compareTo(b.bookingDate));

    final gaps = <int>[
      for (var i = 1; i < sorted.length; i++) sorted[i].bookingDate.difference(sorted[i - 1].bookingDate).inDays,
    ];
    final sortedGaps = [...gaps]..sort();
    final median = sortedGaps[sortedGaps.length ~/ 2];
    if (median < 5) return null; // mehrfach pro Woche → Alltagseinkauf

    (ContractInterval, int, int)? match;
    for (final iv in _intervals) {
      if ((median - iv.$2).abs() <= iv.$3) {
        match = iv;
        break;
      }
    }
    if (match == null) return null;
    final (interval, days, tolerance) = match;

    final regularShare = gaps.where((g) => (g - days).abs() <= tolerance).length / gaps.length;
    final mandated = sorted.any((t) => t.mandateRef != null && t.mandateRef!.isNotEmpty);
    final minCount = (days >= 91 || mandated) ? 2 : 3;
    if (sorted.length < minCount) return null;
    if (regularShare < 0.6) return null;

    // Betragsstabilität (Variationskoeffizient)
    final amounts = sorted.map((t) => t.amountCents.abs()).toList();
    final mean = amounts.reduce((a, b) => a + b) / amounts.length;
    final variance = amounts.map((a) => (a - mean) * (a - mean)).reduce((a, b) => a + b) / amounts.length;
    final cv = mean == 0 ? 1.0 : math.sqrt(variance) / mean;
    if (cv > (mandated ? 0.5 : 0.15)) return null;

    var confidence = 0.5;
    confidence += 0.25 * regularShare;
    if (mandated) confidence += 0.15;
    if (sorted.first.creditorId != null) confidence += 0.05;
    if (sorted.length >= 4) confidence += 0.05;
    if (cv < 0.05) confidence += 0.05;
    confidence = confidence.clamp(0.3, 0.99);

    final last = sorted.last;
    final current = last.amountCents.abs();
    int? previous;
    for (var i = sorted.length - 2; i >= 0; i--) {
      final a = sorted[i].amountCents.abs();
      if (a != current) {
        previous = a;
        break;
      }
    }

    var next = last.bookingDate.add(Duration(days: days));
    final overdue = now.difference(next).inDays;
    final ended = overdue > math.max(tolerance * 2, days ~/ 2);
    if (!ended) {
      while (next.isBefore(DateTime(now.year, now.month, now.day))) {
        next = next.add(Duration(days: days));
      }
    }

    final normalized = normalizeMerchantName(last.counterpartyName);
    final display = merchantName?.call(last.merchantId) ??
        (normalized.isEmpty ? (last.counterpartyName.isEmpty ? 'Vertrag' : last.counterpartyName) : prettifyName(normalized));

    final reason = mandated
        ? 'Lastschrift-Mandat · ${sorted.length} Zahlungen'
        : last.creditorId != null
            ? 'Gläubiger-ID · ${sorted.length} Zahlungen'
            : '${sorted.length} regelmäßige Zahlungen';

    return Contract(
      id: 'c_${_stableHash(key)}',
      merchantId: last.merchantId,
      name: display,
      interval: interval,
      expectedCents: current,
      previousCents: previous != null && previous < current ? previous : null,
      nextDue: next,
      lastPayment: last.bookingDate,
      confidence: confidence,
      status: ended ? ContractStatus.beendet : ContractStatus.vorschlag,
      categoryId: last.categoryId,
      accountId: last.accountId,
      reason: reason,
      transactionIds: sorted.map((t) => t.id).toList(),
    );
  }

  /// FNV-1a – plattformunabhängig stabil (anders als String.hashCode im Web).
  static String _stableHash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}

/// Stabiler Kurz-Hash für IDs.
String stableId(String s) => ContractDetector._stableHash(s);
