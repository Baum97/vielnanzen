import 'package:flutter_test/flutter_test.dart';
import 'package:klarblick/core/analytics/time_range.dart';
import 'package:klarblick/core/engine/categorize.dart';
import 'package:klarblick/core/engine/contracts.dart';
import 'package:klarblick/core/engine/engine.dart';
import 'package:klarblick/core/engine/normalize.dart';
import 'package:klarblick/core/seed/demo_data.dart';
import 'package:klarblick/data/models.dart';

import 'helpers.dart';

var _n = 0;
Transaction _tx(DateTime date, int cents, String name,
        {String? creditorId, String? mandateRef, String purpose = '', String? iban, String? merchantId, String? categoryId, String account = 'a1'}) =>
    Transaction(
      id: 't${_n++}',
      accountId: account,
      bookingDate: date,
      amountCents: cents,
      counterpartyName: name,
      counterpartyIban: iban,
      purpose: purpose,
      creditorId: creditorId,
      mandateRef: mandateRef,
      merchantId: merchantId,
      categoryId: categoryId,
      dedupHash: dedupHash(account, date, cents, '${_n}x', name),
    );

void main() {
  final seed = loadSeed();

  group('normalize', () {
    test('Händlername wird bereinigt', () {
      expect(normalizeMerchantName('REWE SAGT DANKE 4711 STUTTGART'), 'REWE SAGT DANKE');
      expect(normalizeMerchantName('KARTENZAHLUNG NETFLIX 12345'), 'NETFLIX');
      expect(normalizeMerchantName('SUMUP *Cafe Glück'), 'CAFE GLÜCK');
      expect(normalizeMerchantName('Lidl Dienstl. GmbH & Co. KG'), 'LIDL DIENSTL');
    });

    test('Beträge in allen gängigen Schreibweisen', () {
      expect(parseAmountCents('1.234,56'), 123456);
      expect(parseAmountCents('-12,90 €'), -1290);
      expect(parseAmountCents('0,00'), 0);
      expect(parseAmountCents('1,234.56'), 123456);
      expect(parseAmountCents('-45.99'), -4599);
      expect(parseAmountCents('12,5'), 1250);
      expect(parseAmountCents('2.500'), 250000);
      expect(parseAmountCents('100,00-'), -10000);
      expect(parseAmountCents('abc'), isNull);
    });

    test('Datum parsen', () {
      expect(parseDate('05.11.2026'), DateTime(2026, 11, 5));
      expect(parseDate('05.11.26'), DateTime(2026, 11, 5));
      expect(parseDate('2026-11-05'), DateTime(2026, 11, 5));
      expect(parseDate('31/12/2025'), DateTime(2025, 12, 31));
      expect(parseDate('32.13.2026'), isNull);
    });

    test('SEPA-Felder aus dem Verwendungszweck', () {
      final p = parseSepaPurpose('EREF+ABC 123 MREF+M-77 CRED+DE98ZZZ09999999999 SVWZ+Beitrag Juli');
      expect(p['EREF'], 'ABC 123');
      expect(p['MREF'], 'M-77');
      expect(p['CRED'], 'DE98ZZZ09999999999');
      expect(p['SVWZ'], 'Beitrag Juli');
    });
  });

  group('Categorizer', () {
    final cat = Categorizer(
      categories: seed.categories,
      merchants: seed.merchants,
      creditorCategories: seed.creditorCategories,
      creditorMerchants: seed.creditorMerchants,
      ownIbans: {'DE89370400440532013000'},
      rules: const [Rule(id: 'r', field: 'counterparty', operator: 'contains', value: 'OMA ERNA', action: 'category', actionValue: 'spenden')],
    );

    test('Händler-Datenbank fasst Filialen zusammen', () {
      final a = cat.categorize(_tx(DateTime(2026), -1234, 'REWE SAGT DANKE 4711'));
      final b = cat.categorize(_tx(DateTime(2026), -999, 'REWE Markt GmbH'));
      expect(a.merchantId, 'm_rewe');
      expect(b.merchantId, 'm_rewe');
      expect(a.categoryId, 'supermarkt');
    });

    test('Spezifischeres Muster gewinnt (Amazon Prime vor Amazon)', () {
      final r = cat.categorize(_tx(DateTime(2026), -8990, 'Amazon EU S.a.r.l.', purpose: 'AMAZON PRIME JAHRESMITGLIEDSCHAFT'));
      expect(r.merchantId, 'm_prime');
      expect(r.categoryId, 'streaming-video');
    });

    test('PayPal: eigentlicher Händler aus dem Zweck', () {
      final r = cat.categorize(_tx(DateTime(2026), -4999, 'PayPal Europe S.a.r.l.', purpose: 'Ihr Einkauf bei Zalando SE'));
      expect(r.merchantId, 'm_zalando');
    });

    test('Umbuchung zwischen eigenen Konten', () {
      final r = cat.categorize(_tx(DateTime(2026), -15000, 'Max Mustermann', iban: 'DE89 3704 0044 0532 0130 00'));
      expect(r.transfer, isTrue);
      expect(r.categoryId, 'umbuchung');
    });

    test('Eigene Regel hat Vorrang', () {
      expect(cat.categorize(_tx(DateTime(2026), -5000, 'Oma Erna')).categoryId, 'spenden');
    });

    test('Stichwörter: Wasser-Abschlag ist nicht Strom', () {
      expect(cat.categorize(_tx(DateTime(2026), -2500, 'Zweckverband XY', purpose: 'Wasser Abschlag')).categoryId, 'wasser');
      expect(cat.categorize(_tx(DateTime(2026), -6000, 'Grün Energie', purpose: 'Strom Abschlag')).categoryId, 'strom-gas');
    });

    test('Gutschrift eines Händlers ist Erstattung, Gehalt ist Einkommen', () {
      expect(cat.categorize(_tx(DateTime(2026), 2999, 'Zalando SE', purpose: 'Retoure')).categoryId, 'erstattung');
      expect(cat.categorize(_tx(DateTime(2026), 300000, 'Firma GmbH', purpose: 'LOHN/GEHALT 10/2026')).categoryId, 'gehalt');
    });
  });

  group('ContractDetector', () {
    final now = DateTime(2026, 11, 6);

    test('monatliches Abo mit Preiserhöhung', () {
      final txs = [
        for (var m = 0; m < 10; m++)
          _tx(DateTime(2026, 1 + m, 3), m < 6 ? -1299 : -1599, 'Netflix International', creditorId: 'DE26ZZZ00000000001', mandateRef: 'NF-1'),
      ];
      final list = ContractDetector(now: now).detectAll(txs);
      expect(list, hasLength(1));
      final c = list.single;
      expect(c.interval, ContractInterval.monatlich);
      expect(c.expectedCents, 1599);
      expect(c.previousCents, 1299);
      expect(c.confidence, greaterThan(0.8));
      expect(c.nextDue!.isAfter(now), isTrue);
    });

    test('zwei Verträge beim selben Gläubiger werden getrennt', () {
      final txs = [
        for (var m = 0; m < 6; m++) _tx(DateTime(2026, 4 + m, 6), -7900, 'Stadtwerke', creditorId: 'DE12', mandateRef: 'STROM'),
        for (var m = 0; m < 6; m++) _tx(DateTime(2026, 4 + m, 15), -2500, 'Stadtwerke', creditorId: 'DE12', mandateRef: 'WASSER'),
      ];
      final list = ContractDetector(now: now).detectAll(txs);
      expect(list.map((c) => c.expectedCents).toSet(), {7900, 2500});
    });

    test('jährlicher Vertrag wird erkannt', () {
      final txs = [for (var y = 2023; y <= 2026; y++) _tx(DateTime(y, 1, 2), -49800, 'HUK-COBURG', mandateRef: 'KFZ')];
      final c = ContractDetector(now: now).detectAll(txs).single;
      expect(c.interval, ContractInterval.jaehrlich);
      expect(c.yearlyCents, 49800);
    });

    test('beendetes Abo wird als beendet markiert', () {
      final txs = [for (var m = 0; m < 6; m++) _tx(DateTime(2025, 1 + m, 12), -2500, 'Sky', mandateRef: 'SKY')];
      expect(ContractDetector(now: now).detectAll(txs).single.status, ContractStatus.beendet);
    });

    test('Einmalbuchung und Supermarkt sind keine Verträge', () {
      final detector = ContractDetector(now: now);
      expect(detector.detectAll([_tx(DateTime(2026, 1, 3), -1000, 'Shop')]), isEmpty);
      final groceries = [
        for (var d = 0; d < 60; d += 3) _tx(DateTime(2026, 9, 1).add(Duration(days: d)), -3000 - d * 10, 'REWE', categoryId: 'supermarkt'),
      ];
      expect(detector.detectAll(groceries), isEmpty);
    });
  });

  group('TimeRange', () {
    final now = DateTime(2026, 3, 31, 15);
    test('Startzeitpunkte', () {
      expect(TimeRange.w1.start(now), DateTime(2026, 3, 25));
      expect(TimeRange.m1.start(now), DateTime(2026, 3, 1));
      expect(TimeRange.m3.start(now), DateTime(2026, 1, 1));
      expect(TimeRange.ytd.start(now), DateTime(2026, 1, 1));
      expect(TimeRange.y1.start(now), DateTime(2025, 4, 1));
      expect(TimeRange.y5.start(now), DateTime(2021, 4, 1));
      expect(TimeRange.max.start(now, earliest: DateTime(2019, 5, 5, 10)), DateTime(2019, 5, 5));
      expect(TimeRange.m1.end(now), DateTime(2026, 4, 1));
    });

    test('Vorperiode', () {
      final p = TimeRange.ytd.previous(now);
      expect(p.from, DateTime(2025, 1, 1));
      expect(p.to, DateTime(2025, 4, 1));
      final m = TimeRange.m1.previous(now);
      expect(m.to, DateTime(2026, 3, 1));
    });

    test('Balken-Granularität', () {
      expect(TimeRange.w1.bucketFor(7), Bucket.day);
      expect(TimeRange.m3.bucketFor(90), Bucket.week);
      expect(TimeRange.y1.bucketFor(365), Bucket.month);
      expect(TimeRange.y5.bucketFor(1826), Bucket.quarter);
    });
  });

  group('Gesamtanalyse mit Demo-Daten (5 Jahre)', () {
    final now = DateTime(2026, 11, 6);
    final demo = DemoData.generate(now: now);
    final engine = Engine(seed);
    final result = engine.run(transactions: demo.transactions, accounts: demo.accounts, rules: const [], existingContracts: const [], now: now);
    final analytics = engine.analytics(transactions: result.transactions, accounts: demo.accounts, now: now);

    test('fast alles ist kategorisiert', () {
      expect(result.uncategorizedCount / result.transactions.length, lessThan(0.05));
    });

    test('Abos und Verträge werden erkannt', () {
      final names = result.contracts.where((c) => c.status != ContractStatus.beendet).map((c) => c.name).toSet();
      expect(names, containsAll(['Netflix', 'Spotify', 'Telekom', 'Disney+', 'McFIT / RSG', 'HUK-COBURG']));
      final sky = result.contracts.firstWhere((c) => c.name.contains('Sky'));
      expect(sky.status, ContractStatus.beendet);
      expect(result.contracts.any((c) => c.name.contains('REWE') || c.name.contains('Lieferando')), isFalse);
    });

    test('Spar-Hinweise: Doppel-Abos, Preiserhöhung, Gebühren, Doppelabbuchung', () {
      final types = result.insights.map((i) => i.type).toSet();
      expect(types, containsAll([InsightType.doppelteDienst, InsightType.preiserhoehung, InsightType.bankgebuehren, InsightType.doppelteAbbuchung]));
      expect(result.insights.every((i) => i.id.startsWith('ins_')), isTrue);
      // Stabil: zweiter Lauf erzeugt dieselben IDs
      final again = engine.run(transactions: demo.transactions, accounts: demo.accounts, rules: const [], existingContracts: result.contracts, now: now);
      expect(again.insights.map((i) => i.id).toSet(), result.insights.map((i) => i.id).toSet());
    });

    test('Umbuchungen und Sparpläne zählen nicht als Ausgaben', () {
      final p = analytics.analyze(TimeRange.y1);
      expect(p.expenses.any((t) => t.isTransfer), isFalse);
      expect(p.expenses.any((t) => t.categoryId == 'sparen'), isFalse);
      expect(p.summary.savedCents, greaterThan(0));
    });

    test('alle Zeiträume liefern konsistente Zahlen', () {
      for (final r in TimeRange.values) {
        final p = analytics.analyze(r);
        final fromBuckets = p.cashflow.fold<int>(0, (a, b) => a + b.expenseCents);
        expect(fromBuckets, p.summary.expenseCents, reason: r.name);
        final fromCats = p.categories.fold<int>(0, (a, c) => a + c.cents);
        expect(fromCats, p.summary.expenseCents, reason: r.name);
        final fromMerchants = p.merchants.fold<int>(0, (a, m) => a + m.cents);
        expect(fromMerchants, p.summary.expenseCents, reason: r.name);
        expect(p.balance.length, greaterThanOrEqualTo(2), reason: r.name);
        final total = demo.accounts.fold<int>(0, (a, acc) => a + acc.balanceCents);
        expect(p.balance.last.$2, total, reason: r.name);
      }
      expect(analytics.analyze(TimeRange.y5).summary.incomeCents, greaterThan(analytics.analyze(TimeRange.y1).summary.incomeCents));
    });

    test('Saldoverlauf passt zum Anfangssaldo', () {
      final p = analytics.analyze(TimeRange.max);
      // Demo: Startsaldo 2.500 € (Giro) + 5.000 € (Tagesgeld)
      expect(p.balance.first.$2, 750000);
    });

    test('Firmen: REWE-Filialen sind eine Firma', () {
      final p = analytics.analyze(TimeRange.y1);
      expect(p.merchants.where((m) => m.name == 'REWE'), hasLength(1));
      expect(p.merchants.first.cents, greaterThan(0));
    });
  });

  group('models', () {
    test('Betrag in Cent bleibt Ganzzahl', () {
      final t = _tx(DateTime(2026, 1, 1), -12345, 'Test');
      expect(Transaction.fromJson(t.toJson()).amountCents, -12345);
    });

    test('Contract.monthlyCents', () {
      const c = Contract(id: 'c', name: 'Abo', interval: ContractInterval.jaehrlich, expectedCents: 12000);
      expect(c.monthlyCents, 1000);
      expect(c.yearlyCents, 12000);
    });
  });
}
