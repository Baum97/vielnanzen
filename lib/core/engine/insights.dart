import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../analytics/analytics.dart';
import 'contracts.dart';
import 'normalize.dart';

/// Schritt 8: Spar-Hinweise aus den eigenen Daten ableiten.
/// Jede Regel liefert eine konservative Schätzung des Sparpotenzials pro Jahr.
class InsightEngine {
  InsightEngine({
    required this.now,
    required this.analytics,
    required this.merchantOf,
  });

  final DateTime now;
  final Analytics analytics;
  final Merchant? Function(String? id) merchantOf;

  static final _fmt2 = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
  static final _fmt0 = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);
  static String _eur(int cents) => (cents.abs() >= 100000 ? _fmt0 : _fmt2).format(cents / 100);

  /// Preiserhöhungen, die man nicht durch Kündigung/Wechsel vermeiden kann.
  static const _unavoidable = {'miete', 'steuern', 'kfz-steuer', 'rundfunk', 'krankenversicherung', 'gebuehren'};

  Insight _make(InsightType type, String key, String title, String detail,
          {int? potential, String? action, String? contractId, String? merchantName, String? categoryId}) =>
      Insight(
        id: 'ins_${type.name}_${stableId(key)}',
        type: type,
        title: title,
        detail: detail,
        action: action,
        potentialCentsPerYear: potential,
        createdAt: now,
        contractId: contractId,
        merchantName: merchantName,
        categoryId: categoryId,
      );

  List<Insight> run(List<Transaction> txs, List<Contract> contracts) {
    final out = <Insight>[];
    final running = contracts.where((c) => c.status == ContractStatus.aktiv || c.status == ContractStatus.vorschlag).toList();

    // 1) Doppelte Dienste (z. B. mehrere Video-Streaming-Abos)
    final byGroup = <String, List<Contract>>{};
    for (final c in running) {
      final g = merchantOf(c.merchantId)?.group;
      if (g != null) byGroup.putIfAbsent(g, () => []).add(c);
    }
    const groupLabel = {'video': 'Video-Streaming', 'music': 'Musik-Streaming', 'gym': 'Fitness'};
    for (final e in byGroup.entries) {
      if (e.value.length < 2) continue;
      final list = e.value..sort((a, b) => a.yearlyCents.compareTo(b.yearlyCents));
      final names = list.map((c) => c.name).join(', ');
      final label = groupLabel[e.key] ?? e.key;
      out.add(_make(
        InsightType.doppelteDienst,
        'group:${e.key}:${list.map((c) => c.id).join(',')}',
        '${list.length} $label-Abos parallel',
        'Du zahlst für $names (zusammen ${_eur(list.fold(0, (a, c) => a + c.yearlyCents))}/Jahr). '
            'Abwechselnd statt gleichzeitig abonnieren spart mindestens ${list.first.name}.',
        potential: list.first.yearlyCents,
        action: 'Abos vergleichen',
        contractId: list.first.id,
      ));
    }

    // 2) Preiserhöhungen bei Verträgen
    for (final c in running) {
      final prev = c.previousCents;
      if (prev == null || prev >= c.expectedCents || _unavoidable.contains(c.categoryId)) continue;
      if (c.lastPayment != null && now.difference(c.lastPayment!).inDays > 400) continue;
      final perYear = ((c.expectedCents - prev) * (c.yearlyCents / math.max(c.expectedCents, 1))).round();
      final pct = ((c.expectedCents - prev) / prev * 100).round();
      out.add(_make(
        InsightType.preiserhoehung,
        'price:${c.id}:$prev:${c.expectedCents}',
        'Preiserhöhung bei ${c.name} (+$pct %)',
        'Von ${_eur(prev)} auf ${_eur(c.expectedCents)} gestiegen – ${_eur(perYear)} mehr pro Jahr. '
            'Bei Preiserhöhungen hast du meist ein Sonderkündigungsrecht.',
        potential: perYear,
        action: 'Kündigen oder Tarif wechseln',
        contractId: c.id,
      ));
    }

    // 3) Bankgebühren der letzten 12 Monate
    final yearAgo = DateTime(now.year - 1, now.month, now.day);
    final fees = txs.where((t) =>
        t.amountCents < 0 &&
        !t.excluded &&
        t.bookingDate.isAfter(yearAgo) &&
        (t.categoryId == 'gebuehren' ||
            RegExp(r'(KONTOFÜHRUNG|KONTOFUEHRUNG|KONTOFUEHRUNGSENTGELT|ENTGELT FÜR|JAHRESGEBÜHR|JAHRESGEBUEHR|DISPOZINS|SOLLZINS)', caseSensitive: false)
                .hasMatch('${t.counterpartyName} ${t.purpose}')));
    if (fees.isNotEmpty) {
      final total = fees.fold<int>(0, (a, t) => a - t.amountCents);
      if (total >= 500) {
        out.add(_make(
          InsightType.bankgebuehren,
          'fees',
          'Bankgebühren: ${_eur(total)} in 12 Monaten',
          '${fees.length} Gebühren- oder Zinsbuchungen. Viele Girokonten sind dauerhaft kostenlos – ein Wechsel lohnt sich meist.',
          potential: total,
          action: 'Kostenloses Konto suchen',
          categoryId: 'gebuehren',
        ));
      }
    }

    // 4) Mögliche doppelte Abbuchung (gleicher Empfänger, Betrag, ≤ 3 Tage, letzte 60 Tage)
    final recent = txs
        .where((t) => t.amountCents <= -500 && !t.excluded && !t.isTransfer && now.difference(t.bookingDate).inDays <= 60)
        .toList()
      ..sort((a, b) => a.bookingDate.compareTo(b.bookingDate));
    final seenDup = <String>{};
    for (var i = 0; i < recent.length; i++) {
      for (var j = i + 1; j < recent.length; j++) {
        final a = recent[i], b = recent[j];
        if (b.bookingDate.difference(a.bookingDate).inDays > 3) break;
        if (a.amountCents != b.amountCents) continue;
        if (normalizeMerchantName(a.counterpartyName) != normalizeMerchantName(b.counterpartyName)) continue;
        if (a.endToEndRef != null && a.endToEndRef == b.endToEndRef) continue;
        final key = 'dup:${a.id}:${b.id}';
        if (!seenDup.add(a.id) || !seenDup.add(b.id)) continue;
        out.add(_make(
          InsightType.doppelteAbbuchung,
          key,
          'Doppelt abgebucht? ${analytics.merchantDisplay(a)}',
          '2× ${_eur(-a.amountCents)} innerhalb von ${b.bookingDate.difference(a.bookingDate).inDays + 1} Tagen. '
              'Eine unberechtigte Lastschrift kannst du 8 Wochen lang zurückgeben.',
          potential: -a.amountCents,
          action: 'Buchungen prüfen',
          merchantName: analytics.merchantDisplay(a),
        ));
      }
    }

    // Monatsdurchschnitte (letzte 3 volle Monate)
    int avg3(Set<String> cats) => analytics.averageMonthly((t) => cats.contains(t.categoryId));

    // 5) Lieferdienste & Essen gehen
    final delivery = avg3({'lieferdienst'});
    if (delivery >= 4000) {
      out.add(_make(
        InsightType.lieferdienst,
        'delivery',
        'Lieferdienste: Ø ${_eur(delivery)} im Monat',
        'Wer die Hälfte der Bestellungen selbst kocht, spart rund ${_eur((delivery * 0.5 * 12).round())} im Jahr.',
        potential: (delivery * 0.5 * 12).round(),
        action: 'Öfter selbst kochen',
        categoryId: 'lieferdienst',
      ));
    }
    final eatingOut = avg3({'restaurant'});
    if (eatingOut >= 15000) {
      out.add(_make(
        InsightType.kategorieAuffaellig,
        'restaurant',
        'Restaurants & Cafés: Ø ${_eur(eatingOut)} im Monat',
        'Schon 25 % weniger auswärts essen spart ${_eur((eatingOut * 0.25 * 12).round())} im Jahr.',
        potential: (eatingOut * 0.25 * 12).round(),
        action: 'Budget festlegen',
        categoryId: 'restaurant',
      ));
    }

    // 6) „Kleinvieh“: viele kleine Käufe (Bäcker, Café, Kiosk) unter 10 €
    final threeMonthsAgo = DateTime(now.year, now.month - 3, now.day);
    final small = txs.where((t) =>
        analytics.isExpense(t) &&
        t.amountCents > -1000 &&
        t.bookingDate.isAfter(threeMonthsAgo) &&
        const {'baecker', 'restaurant', 'lieferdienst'}.contains(t.categoryId));
    final smallSum = small.fold<int>(0, (a, t) => a - t.amountCents);
    if (small.length >= 20 && smallSum >= 9000) {
      final monthly = (smallSum / 3).round();
      out.add(_make(
        InsightType.kleinvieh,
        'small',
        '${small.length} Kleinstkäufe in 3 Monaten',
        'Coffee-to-go, Snacks & Co. summieren sich auf Ø ${_eur(monthly)} im Monat. Die Hälfte davon wären ${_eur((monthly * 6).round())} im Jahr.',
        potential: monthly * 6,
        action: 'Kleinausgaben bewusst reduzieren',
      ));
    }

    // 7) Versicherungen prüfen
    final insurance = running.where((c) => const {'kfz-versicherung', 'haftpflicht', 'sonstige-versicherung'}.contains(c.categoryId)).toList();
    final kfz = insurance.where((c) => c.categoryId == 'kfz-versicherung').toList();
    if (kfz.isNotEmpty) {
      final yearly = kfz.fold<int>(0, (a, c) => a + c.yearlyCents);
      final nov = now.month >= 9 && now.month <= 11;
      out.add(_make(
        InsightType.versicherungCheck,
        'kfz:${kfz.map((c) => c.id).join(',')}',
        'Kfz-Versicherung vergleichen',
        'Du zahlst ${_eur(yearly)} im Jahr. ${nov ? 'Stichtag für den Wechsel ist meist der 30. November! ' : ''}'
            'Ein Vergleich spart oft 15 % und mehr.',
        potential: (yearly * 0.15).round(),
        action: 'Tarife vergleichen',
        contractId: kfz.first.id,
      ));
    }
    final otherIns = insurance.where((c) => c.categoryId != 'kfz-versicherung').toList();
    final otherInsYearly = otherIns.fold<int>(0, (a, c) => a + c.yearlyCents);
    if (otherIns.length >= 2 && otherInsYearly >= 30000) {
      out.add(_make(
        InsightType.versicherungCheck,
        'ins:${otherIns.map((c) => c.id).join(',')}',
        '${otherIns.length} Versicherungen: ${_eur(otherInsYearly)}/Jahr',
        'Prüfe Doppelversicherungen (z. B. Haftpflicht über Partner) und vergleiche Tarife – oft sind 10 % drin.',
        potential: (otherInsYearly * 0.10).round(),
        action: 'Versicherungen prüfen',
      ));
    }

    // 8) Strom & Gas
    final energy = running.where((c) => c.categoryId == 'strom-gas').toList();
    final energyYearly = energy.fold<int>(0, (a, c) => a + c.yearlyCents);
    if (energyYearly >= 60000) {
      out.add(_make(
        InsightType.energieCheck,
        'energy:${energy.map((c) => c.id).join(',')}',
        'Strom & Gas: ${_eur(energyYearly)} im Jahr',
        'Ein Anbieterwechsel spart häufig 10–20 %. Achte auf Preisgarantie und kurze Laufzeit.',
        potential: (energyYearly * 0.12).round(),
        action: 'Anbieter vergleichen',
        contractId: energy.first.id,
      ));
    }

    // 9) Anhaltend gestiegene Kategorien: Ø der letzten 3 vollen Monate vs. Ø der 9 Monate davor
    final recentStart = DateTime(now.year, now.month - 3, 1);
    final monthStart = DateTime(now.year, now.month, 1);
    final baseStart = DateTime(now.year, now.month - 12, 1);
    final recentByCat = <String, int>{};
    final baseByCat = <String, int>{};
    for (final t in txs.where(analytics.isExpense)) {
      final top = analytics.topCategory(t.categoryId)?.id;
      if (top == null || const {'wohnen', 'versicherungen', 'steuern', 'gebuehren', 'sonstiges'}.contains(top)) continue;
      if (!t.bookingDate.isBefore(recentStart) && t.bookingDate.isBefore(monthStart)) {
        recentByCat[top] = (recentByCat[top] ?? 0) - t.amountCents;
      } else if (!t.bookingDate.isBefore(baseStart) && t.bookingDate.isBefore(recentStart)) {
        baseByCat[top] = (baseByCat[top] ?? 0) - t.amountCents;
      }
    }
    for (final e in recentByCat.entries) {
      final recentAvg = e.value / 3;
      final base = (baseByCat[e.key] ?? 0) / 9;
      if (base < 3000) continue;
      final diff = recentAvg - base;
      if (diff < 3000 || recentAvg < base * 1.25) continue;
      if (e.key == 'freizeit' && out.any((i) => i.categoryId == 'restaurant' || i.categoryId == 'lieferdienst')) continue;
      final cat = analytics.categoryOf(e.key);
      out.add(_make(
        InsightType.kategorieAuffaellig,
        'trend:${e.key}',
        '${cat?.name ?? e.key}: +${((recentAvg / base - 1) * 100).round()} % in den letzten 3 Monaten',
        'Ø ${_eur(recentAvg.round())} statt ${_eur(base.round())} im Monat. Zurück auf dein früheres Niveau wären ${_eur((diff * 12).round())} im Jahr.',
        potential: (diff * 12).round(),
        action: 'Budget festlegen',
        categoryId: e.key,
      ));
    }

    // 10) Hoher Kontostand ohne Zinsen
    final giro = analytics.accounts.where((a) => a.type == AccountType.giro && a.includeInTotal).toList();
    final giroBalance = giro.fold<int>(0, (a, acc) => a + acc.balanceCents);
    final monthlyExpenses = analytics.averageMonthly((_) => true);
    final buffer = math.max(monthlyExpenses * 2, 100000);
    if (giroBalance - buffer >= 300000) {
      final idle = giroBalance - buffer;
      out.add(_make(
        InsightType.hoehererGiroSaldo,
        'idle',
        '${_eur(idle)} liegen zinslos auf dem Girokonto',
        'Zwei Monatsausgaben als Puffer reichen. Auf einem Tagesgeldkonto brächte der Rest bei z. B. 2 % Zinsen ${_eur((idle * 0.02).round())} im Jahr.',
        potential: (idle * 0.02).round(),
        action: 'Tagesgeld eröffnen',
      ));
    }

    // 11) Abo-Summe (Info): Streaming, Software, Presse, Fitness, Gaming
    final aboCats = {'streaming-video', 'streaming-audio', 'software', 'presse', 'fitness', 'gaming'};
    final abos = running.where((c) => aboCats.contains(c.categoryId)).toList();
    final abosYearly = abos.fold<int>(0, (a, c) => a + c.yearlyCents);
    if (abos.length >= 3 && abosYearly >= 30000) {
      final cheapest = (abos..sort((a, b) => a.yearlyCents.compareTo(b.yearlyCents))).first;
      out.add(_make(
        InsightType.aboKosten,
        'abos:${abos.length}',
        '${abos.length} Abos kosten ${_eur(abosYearly)} im Jahr',
        'Geh die Liste einmal durch: Was hast du im letzten Monat nicht genutzt? Schon ein Abo weniger (z. B. ${cheapest.name}) spart ${_eur(cheapest.yearlyCents)}.',
        action: 'Abos durchgehen',
      ));
    }

    out.sort((a, b) => (b.potentialCentsPerYear ?? 0).compareTo(a.potentialCentsPerYear ?? 0));
    return out;
  }
}
