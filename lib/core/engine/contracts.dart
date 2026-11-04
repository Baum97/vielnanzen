import '../../data/models.dart';
import 'normalize.dart';

/// Schritt 7: Vertragserkennung – wiederkehrende Abbuchungen gleicher Höhe.

class ContractDetector {
  /// Gruppiert Transaktionen nach Gläubiger-ID + Mandatsreferenz (falls vorhanden), sonst nach normalisiertem Händler.
  Map<String, List<Transaction>> group(List<Transaction> txs) {
    final map = <String, List<Transaction>>{};
    for (final t in txs.where((t) => t.amountCents < 0 && !t.isTransfer && !t.excluded)) {
      final key = t.creditorId != null
          ? 'cred:${t.creditorId}'
          : 'name:${normalizeMerchantName(t.counterpartyName)}';
      map.putIfAbsent(key, () => []).add(t);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.bookingDate.compareTo(b.bookingDate));
    }
    return map;
  }

  static const intervals = <ContractInterval, int>{
    ContractInterval.woechentlich: 7,
    ContractInterval.zweiwoechentlich: 14,
    ContractInterval.monatlich: 30,
    ContractInterval.quartalsweise: 91,
    ContractInterval.halbjahrlich: 182,
    ContractInterval.jaehrlich: 365,
  };

  /// Erkennt aus einer Gruppe wiederkehrender Buchungen einen Vertrag.
  Contract? detect(String key, List<Transaction> list) {
    if (list.length < 2) return null;
    final amounts = list.map((t) => t.amountCents.abs()).toSet();
    if (amounts.length > 2) return null; // zu unterschiedliche Beträge
    final amount = list.map((t) => t.amountCents.abs()).reduce((a, b) => a + b) ~/ list.length;

    // Abstände analysieren
    final gaps = <int>[];
    for (var i = 1; i < list.length; i++) {
      gaps.add(list[i].bookingDate.difference(list[i - 1].bookingDate).inDays);
    }
    if (gaps.isEmpty) return null;
    final avgGap = gaps.reduce((a, b) => a + b) / gaps.length;

    ContractInterval interval;
    double confidence;
    if (avgGap <= 10) {
      interval = ContractInterval.woechentlich;
      confidence = 0.9;
    } else if (avgGap <= 20) {
      interval = ContractInterval.zweiwoechentlich;
      confidence = 0.85;
    } else if (avgGap <= 40) {
      interval = ContractInterval.monatlich;
      confidence = 0.95;
    } else if (avgGap <= 100) {
      interval = ContractInterval.quartalsweise;
      confidence = 0.8;
    } else if (avgGap <= 200) {
      interval = ContractInterval.halbjahrlich;
      confidence = 0.8;
    } else if (avgGap <= 380) {
      interval = ContractInterval.jaehrlich;
      confidence = 0.85;
    } else {
      return null;
    }
    // Regelmäßigkeit senkt/hebt Konfidenz
    final regular = gaps.every((g) => (g - avgGap).abs() <= 4);
    if (!regular) confidence -= 0.15;
    if (list.length >= 3) confidence += 0.05;
    confidence = confidence.clamp(0.3, 0.99);

    final name = normalizeMerchantName(list.first.counterpartyName);
    final nextDue = list.last.bookingDate.add(Duration(days: avgGap.round()));
    return Contract(
      id: 'c_${key.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}',
      name: name.isEmpty ? list.first.counterpartyName : name,
      interval: interval,
      expectedCents: amount,
      nextDue: nextDue,
      confidence: confidence,
      status: ContractStatus.vorschlag,
      transactionIds: list.map((t) => t.id).toList(),
    );
  }
}
