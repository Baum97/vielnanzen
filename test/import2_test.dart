import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klarblick/core/import/csv_mapping.dart';
import 'package:klarblick/core/import/file_import.dart';
import 'package:klarblick/core/import/iban.dart';
import 'package:klarblick/data/bank_directory.dart';
import 'package:klarblick/data/models.dart';
import 'package:klarblick/services/import_service.dart';

import 'helpers.dart';

// Gültige Beispiel-IBANs (Prüfsumme stimmt).
const dkb = 'DE02120300000000202051';
const commerz = 'DE89370400440532013000';

void main() {
  final imp = FileImport();
  final directory = BankDirectory.fromJsonString(File('assets/data/bank_directory.json').readAsStringSync());

  group('IBAN', () {
    test('Prüfsumme', () {
      expect(isValidIban(dkb), isTrue);
      expect(isValidIban('DE89 3704 0044 0532 0130 00'), isTrue);
      expect(isValidIban('DE89370400440532013001'), isFalse);
      expect(isValidIban('hallo'), isFalse);
    });

    test('IBAN im Text finden', () {
      expect(findIban('Konto: DE89 3704 0044 0532 0130 00 (Giro)'), commerz);
      expect(findIban('IBAN;DE02 1203 0000 0000 2020 51 EUR'), dkb);
      expect(findIban('Rechnung 123456789 vom 05.11.'), isNull);
    });
  });

  group('Konto erkennen', () {
    test('CSV mit IBAN im Vorspann (ING-Stil)', () {
      const csv = 'Umsatzanzeige;Datei erstellt am: 06.11.2026\n'
          'IBAN;DE89 3704 0044 0532 0130 00\n'
          'Kontoname;Girokonto\n\n'
          'Buchung;Wertstellungsdatum;Auftraggeber/Empfänger;Buchungstext;Verwendungszweck;Saldo;Währung;Betrag;Währung\n'
          '05.11.2026;05.11.2026;REWE Markt GmbH;Lastschrift;Einkauf;1.234,56;EUR;-45,10;EUR\n';
      final r = imp.parse(csv, accountId: 'x');
      expect(r.account?.iban, commerz);
      expect(r.transactions, hasLength(1));
    });

    test('CSV mit Spalte „Auftragskonto“ (Sparkasse-Stil)', () {
      const csv = 'Auftragskonto;Buchungstag;Verwendungszweck;Beguenstigter/Zahlungspflichtiger;Betrag\n'
          '$dkb;03.11.26;Netflix Abo;Netflix International B.V.;-15,99\n';
      final r = imp.parse(csv, accountId: 'x');
      expect(r.account?.iban, dkb);
      expect(r.transactions.single.counterpartyName, 'Netflix International B.V.');
    });

    test('MT940: BLZ/Konto', () {
      const mt940 = ':20:STARTUMS\r\n:25:37040044/532013000\r\n:28C:1/1\r\n:60F:C261101EUR1000,00\r\n'
          ':61:2611031103DR15,99NDDTNONREF\r\n:86:105?00FOLGELASTSCHRIFT?20SVWZ+Abo?32NETFLIX\r\n'
          ':62F:C261103EUR984,01\r\n-\r\n';
      final r = imp.parse(mt940, accountId: 'x');
      expect(r.account?.bankCode, '37040044');
      expect(r.account?.key, '37040044/532013000');
      // passt zu einem Konto mit der IBAN derselben BLZ/Kontonummer
      final acc = const Account(id: 'a', iban: commerz, name: 'Giro', type: AccountType.giro);
      expect(matchAccount([acc], r.account), acc);
    });

    test('CAMT: IBAN', () {
      const camt = '''<?xml version="1.0"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.02"><BkToCstmrStmt>
<GrpHdr><MsgId>1</MsgId><CreDtTm>2026-11-05T10:00:00</CreDtTm></GrpHdr>
<Stmt><Id>1</Id><CreDtTm>2026-11-05T10:00:00</CreDtTm><Acct><Id><IBAN>$dkb</IBAN></Id><Ccy>EUR</Ccy></Acct>
<Ntry><Amt Ccy="EUR">12.99</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts>BOOK</Sts><BookgDt><Dt>2026-11-04</Dt></BookgDt><ValDt><Dt>2026-11-04</Dt></ValDt>
<NtryDtls><TxDtls><RltdPties><Cdtr><Nm>Spotify AB</Nm></Cdtr></RltdPties><RmtInf><Ustrd>Premium</Ustrd></RmtInf></TxDtls></NtryDtls></Ntry>
</Stmt></BkToCstmrStmt></Document>''';
      final r = imp.parse(camt, accountId: 'x');
      expect(r.account?.iban, dkb);
    });

    test('Zuordnung zu vorhandenem Konto über IBAN, sonst keins', () {
      const giro = Account(id: 'a1', iban: dkb, name: 'DKB', type: AccountType.giro);
      const other = Account(id: 'a2', iban: commerz, name: 'Commerzbank', type: AccountType.giro);
      expect(matchAccount([other, giro], const DetectedAccount(iban: dkb)), giro);
      expect(matchAccount([other], const DetectedAccount(iban: dkb)), isNull);
      expect(matchAccount([giro], null), isNull);
      expect(matchAccount([giro], const DetectedAccount()), isNull);
    });

    test('Vorschlag für neues Konto nennt die Bank', () {
      final s = suggestNewAccount(const DetectedAccount(iban: dkb), directory);
      expect(s.name, contains('Kredit'));
      expect(s.name, endsWith('…2051'));
      expect(s.id, 'acc_$dkb');
      expect(suggestNewAccount(null, directory).name, 'Importiertes Konto');
    });
  });

  group('Unbekannte CSV-Formate', () {
    const unknown = 'Datum;Typ;Name;Wert;Kontostand\n'
        '05.11.2026;Kartentransaktion;REWE Markt;-45,10;1.000,00\n'
        '04.11.2026;Überweisung;Max Muster;50,00;1.045,10\n'
        '03.11.2026;Kartentransaktion;Starbucks;-4,80;995,10\n';

    test('wird nicht geraten, sondern zur Zuordnung angeboten', () {
      final r = imp.parse(unknown, accountId: 'x');
      expect(r.transactions, isEmpty);
      expect(r.needsMapping, isTrue);
      expect(r.table!.headers, ['Datum', 'Typ', 'Name', 'Wert', 'Kontostand']);
    });

    test('Vorschlag aus Inhalt und Überschriften', () {
      final m = CsvMapping.guess(imp.parse(unknown, accountId: 'x').table!)!;
      expect(m.date, 0);
      expect(m.amount, 3, reason: 'Wert statt Kontostand');
      expect(m.name, 2);
      expect(m.purpose, 1);
    });

    test('mit Zuordnung werden die Umsätze gelesen; Vorzeichen umkehrbar', () {
      final table = imp.parse(unknown, accountId: 'x').table!;
      final m = CsvMapping.guess(table)!;
      final r = imp.parse(unknown, accountId: 'x', mapping: m);
      expect(r.transactions.map((t) => t.amountCents), [-4510, 5000, -480]);
      expect(r.mappingFromUser, isTrue);
      expect(r.transactions.first.counterpartyName, 'REWE Markt');
      final inverted = imp.parse(unknown, accountId: 'x', mapping: m.copyWith(invertSign: true));
      expect(inverted.transactions.map((t) => t.amountCents), [4510, -5000, 480]);
    });

    test('gemerkte Zuordnung erkennt dieselbe Datei beim nächsten Mal', () {
      final first = imp.parse(unknown, accountId: 'x');
      final m = CsvMapping.guess(first.table!)!;
      final next = '${unknown}02.11.2026;Kartentransaktion;Lidl;-12,00;983,10\n';
      final r = imp.parse(next, accountId: 'x', profiles: {first.table!.signature: m});
      expect(r.error, isNull);
      expect(r.transactions, hasLength(4));
    });

    test('Mapping-JSON-Rundlauf', () {
      final m = CsvMapping.guess(imp.parse(unknown, accountId: 'x').table!)!.copyWith(invertSign: true, iban: null);
      final back = CsvMapping.fromJson(m.toJson());
      expect(back.toJson(), m.toJson());
    });

    test('getrennte Abgang-/Zugang-Spalten werden als Paar erkannt', () {
      const csv = 'Tag;Gegenpartei;Text;Abgang;Zugang\n'
          '01.10.2026;Vermieter;Miete;1.050,00;\n'
          '02.10.2026;Firma;Lohn;;2.000,00\n'
          '03.10.2026;Rewe;Einkauf;42,10;\n';
      final r = imp.parse(csv, accountId: 'x');
      expect(r.needsMapping, isTrue);
      final m = CsvMapping.guess(r.table!)!;
      expect(m.isValid, isTrue);
      expect([m.debit, m.credit], [3, 4]);
      final ok = imp.parse(csv, accountId: 'x', mapping: m);
      expect(ok.transactions.map((t) => t.amountCents), [-105000, 200000, -4210]);
    });

    test('ohne eindeutige Überschriften wird nicht geraten, welche Spalte Soll und Haben ist', () {
      const csv = 'Tag;Gegenpartei;Text;A;B\n01.10.2026;Vermieter;Miete;1.050,00;\n02.10.2026;Firma;Lohn;;2.000,00\n';
      final m = CsvMapping.guess(imp.parse(csv, accountId: 'x').table!)!;
      expect(m.date, 0);
      expect(m.isValid, isFalse, reason: 'der Nutzer entscheidet im Zuordnungsdialog');
    });
  });

  group('Import anwenden', () {
    test('neues Konto, Duplikate, gemerkte Zuordnung', () async {
      final store = memoryStore();
      await store.load();
      const csv = 'Datum;Typ;Name;Wert;Kontostand\n05.11.2026;Karte;REWE;-45,10;1.000,00\n04.11.2026;Karte;Netto;-10,00;1.045,10\n';
      final table = imp.parse(csv, accountId: 'x').table!;
      final mapping = CsvMapping.guess(table)!;

      ImportPlan plan() => ImportPlan(
            parsed: imp.parse(csv, accountId: 'acc_test', mapping: mapping),
            accountId: 'acc_test',
            newAccountName: 'Trade Republic',
            balanceCents: 100000,
          );

      final first = applyImport(store, [plan()]);
      expect(first.added, 2);
      expect(store.accountById('acc_test')!.name, 'Trade Republic');
      expect(store.accountById('acc_test')!.balanceCents, 100000);
      expect(savedMappings(store)[table.signature]!.amount, mapping.amount);

      final second = applyImport(store, [plan()]);
      expect(second.added, 0);
      expect(second.duplicates, 2);
      expect(store.accounts, hasLength(1));
      store.dispose();
    });
  });
}
