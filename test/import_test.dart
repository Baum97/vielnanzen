import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klarblick/core/import/csv.dart';
import 'package:klarblick/core/import/file_import.dart';

void main() {
  final imp = FileImport();

  test('CSV-Parser: Anführungszeichen, Trenner, Zeilenumbrüche', () {
    final rows = parseCsv('a;"b;c";"d ""x"""\n1;"zwei\nzeilen";3\n');
    expect(rows, [
      ['a', 'b;c', 'd "x"'],
      ['1', 'zwei\nzeilen', '3'],
    ]);
    expect(detectDelimiter('a,b,c\n1,2,3'), ',');
  });

  test('Sparkasse (CSV-CAMT)', () {
    const csv = '"Auftragskonto";"Buchungstag";"Valutadatum";"Buchungstext";"Verwendungszweck";"Glaeubiger ID";"Mandatsreferenz";'
        '"Kundenreferenz (End-to-End)";"Sammlerreferenz";"Lastschrift Ursprungsbetrag";"Auslagenersatz Ruecklastschrift";'
        '"Beguenstigter/Zahlungspflichtiger";"Kontonummer/IBAN";"BIC (SWIFT-Code)";"Betrag";"Waehrung";"Info"\n'
        '"DE123";"03.11.26";"03.11.26";"FOLGELASTSCHRIFT";"Netflix Abo";"DE26ZZZ00000000001";"NF-77";"E2E-1";"";"";"";'
        '"Netflix International B.V.";"NL12INGB0001234567";"INGBNL2A";"-15,99";"EUR";"Umsatz gebucht"\n'
        '"DE123";"01.11.26";"01.11.26";"GUTSCHR. UEBERWEISUNG";"Gehalt 10/26";"";"";"";"";"";"";"Firma GmbH";"DE44500105175407324931";"";"3.150,00";"EUR";""\n';
    final r = imp.parse(csv, accountId: 'acc');
    expect(r.error, isNull);
    expect(r.transactions, hasLength(2));
    final n = r.transactions.first;
    expect(n.amountCents, -1599);
    expect(n.bookingDate, DateTime(2026, 11, 3));
    expect(n.counterpartyName, 'Netflix International B.V.');
    expect(n.creditorId, 'DE26ZZZ00000000001');
    expect(n.mandateRef, 'NF-77');
    expect(n.counterpartyIban, 'NL12INGB0001234567');
    expect(r.transactions.last.amountCents, 315000);
  });

  test('ING mit Vorspann', () {
    const csv = 'Umsatzanzeige;Datei erstellt am: 06.11.2026\n'
        'IBAN;DE12 5001 0517 0000 0000 00\n'
        'Kontoname;Girokonto\n'
        '\n'
        'Buchung;Wertstellungsdatum;Auftraggeber/Empfänger;Buchungstext;Verwendungszweck;Saldo;Währung;Betrag;Währung\n'
        '05.11.2026;05.11.2026;REWE Markt GmbH;Lastschrift;Einkauf;1.234,56;EUR;-45,10;EUR\n'
        '04.11.2026;04.11.2026;Spotify AB;Lastschrift;Premium;1.279,66;EUR;-12,99;EUR\n';
    final r = imp.parse(csv, accountId: 'acc');
    expect(r.transactions, hasLength(2));
    expect(r.transactions.first.counterpartyName, 'REWE Markt GmbH');
    expect(r.transactions.first.amountCents, -4510);
  });

  test('N26 (Komma, Englisch)', () {
    const csv = '"Booking Date","Value Date","Partner Name","Partner Iban",Type,"Payment Reference","Account Name","Amount (EUR)","Original Amount","Original Currency","Exchange Rate"\n'
        '2026-11-02,2026-11-02,"Lieferando.de",,"Debit Transfer","Bestellung 123","Main Account",-27.90,,,\n'
        '2026-11-01,2026-11-01,"Max Muster",DE89370400440532013000,"Credit Transfer","Danke","Main Account",50.00,,,\n';
    final r = imp.parse(csv, accountId: 'acc');
    expect(r.transactions.map((t) => t.amountCents), [-2790, 5000]);
    expect(r.transactions.first.bookingDate, DateTime(2026, 11, 2));
    expect(r.transactions.last.counterpartyIban, 'DE89370400440532013000');
  });

  test('Soll/Haben-Spalten', () {
    const csv = 'Datum;Empfänger;Verwendungszweck;Soll;Haben\n'
        '01.10.2026;Vermieter;Miete;1.050,00;\n'
        '02.10.2026;Firma;Lohn;;2.000,00\n';
    final r = imp.parse(csv, accountId: 'acc');
    expect(r.transactions.map((t) => t.amountCents), [-105000, 200000]);
  });

  test('Latin-1 kodierte Datei', () {
    final bytes = Uint8List.fromList(latin1.encode('Datum;Empfänger;Verwendungszweck;Betrag\n01.10.2026;Bäckerei Müller;Brötchen;-3,50\n'));
    final r = imp.parseBytes(bytes, accountId: 'acc');
    expect(r.transactions.single.counterpartyName, 'Bäckerei Müller');
  });

  test('gleiche Buchungen am selben Tag bleiben getrennt, Re-Import erkennt sie', () {
    const csv = 'Datum;Empfänger;Verwendungszweck;Betrag\n01.10.2026;Café;Kaffee;-3,20\n01.10.2026;Café;Kaffee;-3,20\n';
    final a = imp.parse(csv, accountId: 'acc').transactions;
    final b = imp.parse(csv, accountId: 'acc').transactions;
    expect(a, hasLength(2));
    expect(a[0].dedupHash, isNot(a[1].dedupHash));
    expect(a.map((t) => t.dedupHash), b.map((t) => t.dedupHash));
  });

  test('MT940', () {
    const mt940 = ':20:STARTUMS\r\n'
        ':25:12030000/1234567890\r\n'
        ':28C:1/1\r\n'
        ':60F:C261101EUR1000,00\r\n'
        ':61:2611031103DR15,99NDDTNONREF\r\n'
        ':86:105?00FOLGELASTSCHRIFT?20EREF+NF123?21MREF+NF-77?22CRED+DE26ZZZ00000000001?23SVWZ+Netflix Abo?32NETFLIX INTERNATIONAL B.V.\r\n'
        ':61:2611041104CR50,00NTRFNONREF\r\n'
        ':86:166?00GUTSCHRIFT?20SVWZ+Danke?32Max Muster\r\n'
        ':62F:C261104EUR1034,01\r\n'
        '-\r\n';
    final r = imp.parse(mt940, accountId: 'acc');
    expect(r.error, isNull);
    expect(r.format, 'MT940');
    expect(r.transactions.map((t) => t.amountCents), [-1599, 5000]);
    expect(r.transactions.first.counterpartyName.toUpperCase(), contains('NETFLIX'));
    expect(r.closingBalanceCents, 103401);
  });

  test('CAMT.053', () {
    const camt = '''<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.02">
 <BkToCstmrStmt>
  <GrpHdr><MsgId>1</MsgId><CreDtTm>2026-11-05T10:00:00</CreDtTm></GrpHdr>
  <Stmt>
   <Id>1</Id>
   <CreDtTm>2026-11-05T10:00:00</CreDtTm>
   <Acct><Id><IBAN>DE02120300000000202051</IBAN></Id><Ccy>EUR</Ccy></Acct>
   <Ntry>
    <Amt Ccy="EUR">12.99</Amt>
    <CdtDbtInd>DBIT</CdtDbtInd>
    <Sts>BOOK</Sts>
    <BookgDt><Dt>2026-11-04</Dt></BookgDt>
    <ValDt><Dt>2026-11-04</Dt></ValDt>
    <NtryDtls><TxDtls>
     <RltdPties><Cdtr><Nm>Spotify AB</Nm></Cdtr></RltdPties>
     <RmtInf><Ustrd>Spotify Premium</Ustrd></RmtInf>
    </TxDtls></NtryDtls>
   </Ntry>
  </Stmt>
 </BkToCstmrStmt>
</Document>''';
    final r = imp.parse(camt, accountId: 'acc');
    expect(r.error, isNull);
    expect(r.format, 'CAMT');
    final t = r.transactions.single;
    expect(t.amountCents, -1299);
    expect(t.counterpartyName, 'Spotify AB');
    expect(t.bookingDate, DateTime(2026, 11, 4));
  });

  test('unbekanntes Format liefert verständlichen Fehler', () {
    final r = imp.parse('hallo welt\nnichts hier', accountId: 'acc');
    expect(r.transactions, isEmpty);
    expect(r.error, isNotNull);
  });
}
