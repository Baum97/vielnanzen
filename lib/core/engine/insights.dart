import '../../data/models.dart';
import 'normalize.dart';

/// Schritt 8: Spar-Hinweise (Insights) aus den Daten ableiten.

class InsightEngine {
  InsightEngine(this.now);
  final DateTime now;

  String _id(String s) => 'i_${s.hashCode.toRadixString(16)}_${now.microsecondsSinceEpoch}';

  List<Insight> run(List<Transaction> txs, List<Contract> contracts) {
    final out = <Insight>[];

    // 1) Doppelte Abbuchung im selben Monat (gleicher Händler + Betrag, kein Mandat)
    final byMonth = <String, List<Transaction>>{};
    for (final t in txs.where((t) => t.amountCents < 0 && !t.excluded)) {
      final key = '${normalizeMerchantName(t.counterpartyName)}|${t.bookingDate.year}-${t.bookingDate.month}|${t.amountCents}';
      byMonth.putIfAbsent(key, () => []).add(t);
    }
    for (final entry in byMonth.entries) {
      if (entry.value.length >= 2 && entry.value.any((t) => t.mandateRef == null)) {
        final t = entry.value.first;
        out.add(Insight(
          id: _id('dup${entry.key}'),
          type: InsightType.doppelteAbbuchung,
          title: 'Mögliche doppelte Abbuchung: ${t.counterpartyName}',
          detail: '${entry.value.length}× ${(-t.amountCents / 100).toStringAsFixed(2)} € im selben Monat gebucht.',
          potentialCentsPerYear: (-t.amountCents) * 12,
          createdAt: now,
        ));
      }
    }

    // 2) Preiserhöhung bei erkannten Verträgen (letzter Betrag > erster Betrag)
    for (final c in contracts) {
      final related = txs.where((t) => c.transactionIds.contains(t.id)).toList()
        ..sort((a, b) => a.bookingDate.compareTo(b.bookingDate));
      if (related.length >= 2) {
        final first = related.first.amountCents.abs();
        final last = related.last.amountCents.abs();
        if (last > first) {
          out.add(Insight(
            id: _id('price${c.id}'),
            type: InsightType.preiserhoehung,
            title: 'Preiserhöhung bei ${c.name}',
            detail: 'Von ${(first / 100).toStringAsFixed(2)} € auf ${(last / 100).toStringAsFixed(2)} € gestiegen.',
            potentialCentsPerYear: (last - first) * 12,
            createdAt: now,
          ));
        }
      }
    }

    // 3) Bankgebühren über 5 €/Jahr
    final bankFees = txs.where((t) =>
        t.amountCents < 0 &&
        !t.excluded &&
        (t.bookingDate.year == now.year) &&
        RegExp(r'(KONTOFÜHRUNG|GEBÜHR|ENTGELT|PREIS)', caseSensitive: false).hasMatch('${t.counterpartyName} ${t.purpose}'));
    if (bankFees.isNotEmpty) {
      final total = bankFees.fold<int>(0, (a, t) => a - t.amountCents);
      out.add(Insight(
        id: _id('bankfees$now.year'),
        type: InsightType.bankgebuehren,
        title: 'Bankgebühren dieses Jahr: ${(total / 100).toStringAsFixed(2)} €',
        detail: '${bankFees.length} Gebührenbuchungen. Prüfe, ob ein kostenloses Konto günstiger wäre.',
        potentialCentsPerYear: total,
        createdAt: now,
      ));
    }

    return out;
  }
}
