import 'package:flutter_test/flutter_test.dart';

import 'package:klarblick/core/engine/contracts.dart';
import 'package:klarblick/core/engine/normalize.dart';
import 'package:klarblick/data/models.dart';

Transaction _tx(String id, DateTime date, int cents, String name, {String? creditorId, String? mandateRef}) => Transaction(
      id: id,
      accountId: 'a1',
      bookingDate: date,
      amountCents: cents,
      counterpartyName: name,
      creditorId: creditorId,
      mandateRef: mandateRef,
      dedupHash: dedupHash('a1', date, cents, null, name),
    );

void main() {
  group('normalize', () {
    test('Händlername wird bereinigt', () {
      expect(normalizeMerchantName('REWE SAGT DANKE 4711 STUTTGART'), 'REWE SAGT DANKE');
      expect(normalizeMerchantName('KARTENZAHLUNG NETFLIX 12345'), 'NETFLIX');
    });

    test('Betrag parsen', () {
      expect(parseAmountCents('1.234,56'), 123456);
      expect(parseAmountCents('-12,90 €'), -1290);
      expect(parseAmountCents('0,00'), 0);
    });

    test('Datum parsen', () {
      expect(parseDate('05.11.2026'), DateTime(2026, 11, 5));
      expect(parseDate('2026-11-05'), DateTime(2026, 11, 5));
    });
  });

  group('ContractDetector', () {
    test('monatliches Abo wird erkannt', () {
      final txs = [
        for (var m = 0; m < 6; m++) _tx('t$m', DateTime(2026, 1 + m, 3), -4999, 'Netflix International', creditorId: 'DE26ZZZ00000000001'),
      ];
      final detector = ContractDetector();
      final groups = detector.group(txs);
      final c = detector.detect(groups.keys.first, groups.values.first);
      expect(c, isNotNull);
      expect(c!.interval, ContractInterval.monatlich);
      expect(c.expectedCents, 4999);
      expect(c.confidence, greaterThan(0.5));
    });

    test('Einmalbuchung ist kein Vertrag', () {
      final detector = ContractDetector();
      final groups = detector.group([_tx('t0', DateTime(2026, 1, 3), -1000, 'REWE')]);
      expect(detector.detect(groups.keys.first, groups.values.first), isNull);
    });
  });

  group('models', () {
    test('Betrag in Cent bleibt Ganzzahl', () {
      final t = _tx('x', DateTime(2026, 1, 1), -12345, 'Test');
      expect(t.toJson()['amountCents'], -12345);
      expect(Transaction.fromJson(t.toJson()).amountCents, -12345);
    });

    test('Contract.monthlyCents', () {
      final c = Contract(id: 'c', name: 'Abo', interval: ContractInterval.jaehrlich, expectedCents: 12000);
      expect(c.monthlyCents, 1000);
    });
  });
}
