import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klarblick/data/bank_directory.dart';

void main() {
  final dir = BankDirectory.fromJsonString(File('assets/data/bank_directory.json').readAsStringSync());

  test('Verzeichnis ist gefüllt und enthält die großen Banken mit FinTS-Adresse', () {
    expect(dir.banks.length, greaterThan(2000));
    for (final blz in ['50010517', '12030000', '50040000', '10010010', '20041177', '76030080']) {
      final b = dir.byBlz(blz);
      expect(b, isNotNull, reason: blz);
      expect(b!.url, startsWith('https://'), reason: blz);
    }
    expect(dir.byBlz('10090000')!.url, 'https://fints2.atruvia.de/cgi-bin/hbciservlet');
  });

  test('Suche nach Namen, Ort, BLZ, BIC und IBAN', () {
    expect(dir.search('ing').first.name, contains('ING'));
    expect(dir.search('Sparkasse KölnBonn').first.blz, '37050198');
    expect(dir.search('sparkasse koelnbonn').first.blz, '37050198', reason: 'ö/oe gleichwertig');
    expect(dir.search('37050198').map((b) => b.blz), contains('37050198'));
    expect(dir.search('12030').every((b) => b.blz.startsWith('12030')), isTrue);
    expect(dir.search('DE02 1203 0000 0000 2020 51').single.blz, '12030000');
    expect(dir.search('de02120300000000202051').single.name, contains('Kredit'));
    expect(dir.search('COBADEFFXXX').map((b) => b.blz), contains('50040000'));
    expect(dir.search('volksbank berlin').first.name.toLowerCase(), contains('volksbank'));
    expect(dir.search('zzzzqqq'), isEmpty);
    expect(dir.search(''), isEmpty);
  });

  test('BLZ aus IBAN', () {
    expect(BankDirectory.blzFromIban('DE02 1203 0000 0000 2020 51'), '12030000');
    expect(BankDirectory.blzFromIban('NL12INGB0001234567'), isNull);
    expect(BankDirectory.blzFromIban('abc'), isNull);
    expect(dir.forIban('DE02120300000000202051')!.name, contains('Kredit'));
  });
}
