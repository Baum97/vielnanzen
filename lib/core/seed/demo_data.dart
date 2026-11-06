import 'dart:math';

import '../../data/models.dart';
import '../engine/normalize.dart';

/// Demo-Datensatz: synthetische, lokal erzeugte Umsätze über bis zu 5 Jahre.
/// Ausschließlich lokal generiert – es findet kein Netzwerkverkehr statt.
class DemoData {
  static const giroId = 'acc_demo_giro';
  static const savingsId = 'acc_demo_tagesgeld';
  static const giroIban = 'DE02120300000000202051';
  static const savingsIban = 'DE89370400440532013000';

  /// Erzeugt Konten + Umsätze. Die Kontostände ergeben sich aus den Buchungen.
  static ({List<Account> accounts, List<Transaction> transactions}) generate({int months = 60, DateTime? now, int seed = 7}) {
    final today = now ?? DateTime.now();
    final rnd = Random(seed);
    final giro = <Transaction>[];
    final savings = <Transaction>[];
    var n = 0;

    void add(List<Transaction> into, String accountId, DateTime date, int cents, String name, String purpose,
        {String? creditorId, String? mandateRef, String? iban}) {
      if (date.isAfter(today)) return;
      final e2e = 'DEMO-${n++}';
      into.add(Transaction(
        id: 'demo_${accountId}_$n',
        accountId: accountId,
        bookingDate: date,
        valueDate: date,
        amountCents: cents,
        counterpartyName: name,
        counterpartyIban: iban,
        purpose: purpose,
        creditorId: creditorId,
        mandateRef: mandateRef,
        endToEndRef: e2e,
        dedupHash: dedupHash(accountId, date, cents, e2e, '$name $purpose'),
      ));
    }

    void g(DateTime d, int cents, String name, String purpose, {String? cred, String? mref, String? iban}) =>
        add(giro, giroId, d, cents, name, purpose, creditorId: cred, mandateRef: mref, iban: iban);

    int r(int min, int max) => min + rnd.nextInt(max - min + 1);
    DateTime day(DateTime month, int d) {
      final last = DateTime(month.year, month.month + 1, 0).day;
      return DateTime(month.year, month.month, d.clamp(1, last));
    }

    final startMonth = DateTime(today.year, today.month - (months - 1), 1);
    for (var i = 0; i < months; i++) {
      final m = DateTime(startMonth.year, startMonth.month + i, 1);
      final yearsAgo = (today.year - m.year) + (today.month - m.month) / 12;

      // --- Einnahmen
      final salary = (315000 * pow(1.03, (5 - yearsAgo).clamp(0, 5))).round();
      g(day(m, 28), salary, 'Muster Technik GmbH', 'LOHN/GEHALT ${m.month.toString().padLeft(2, '0')}/${m.year}');
      if (m.month == 11) g(day(m, 28), (salary * 0.55).round(), 'Muster Technik GmbH', 'Weihnachtsgeld ${m.year}');
      if (m.month == 8) g(day(m, 14), r(35000, 95000), 'Finanzamt Musterstadt', 'Steuererstattung ${m.year - 1}');

      // --- Wohnen & Verträge (Lastschriften mit festem Mandat)
      final rent = yearsAgo > 2 ? 105000 : 110500;
      g(day(m, 1), -rent, 'Hausverwaltung Schmidt', 'Miete Whg. 3 OG links', iban: 'DE44500105175407324931');
      g(day(m, 3), -(yearsAgo > 2 ? 1299 : yearsAgo > 1 ? 1399 : 1599), 'Netflix International B.V.', 'NETFLIX.COM ABO',
          cred: 'DE26ZZZ00000000001', mref: 'NFLX-0047-1182');
      if (yearsAgo < 2) g(day(m, 9), -999, 'Disney Plus', 'DISNEY PLUS MONATSABO', cred: 'NL41ZZZ000000000003', mref: 'DSNY-77812');
      if (yearsAgo > 1.2 && yearsAgo < 3.5) g(day(m, 12), -2500, 'Sky Deutschland GmbH', 'Sky Abo Kundennr 5541', cred: 'DE07ZZZ00000012345', mref: 'SKY-5541');
      g(day(m, 4), -(yearsAgo > 2 ? 1099 : yearsAgo > 0.5 ? 1199 : 1299), 'Spotify AB', 'Spotify Premium', cred: 'SE21ZZZ00000000077', mref: 'SPOT-23-998');
      g(day(m, 5), -3995, 'Telekom Deutschland GmbH', 'Festnetz/Internet Rg. ${m.month}/${m.year}', cred: 'DE98ZZZ09999999999X', mref: 'TKOM-1-55120');
      g(day(m, 6), -(yearsAgo > 1.5 ? 7400 : 8900), 'Stadtwerke Musterstadt', 'Abschlag Strom', cred: 'DE12ZZZ00000556677', mref: 'SW-STROM-1001');
      if (m.month % 3 == 1) g(day(m, 15), -7500, 'Stadtwerke Musterstadt', 'Abschlag Wasser/Abwasser', cred: 'DE12ZZZ00000556677', mref: 'SW-WASSER-1001');
      if (m.month % 3 == 2) {
        g(day(m, 15), -5508, 'ARD ZDF Deutschlandradio Beitragsservice', 'Rundfunkbeitrag 3 Monate', cred: 'DE98ZZZ09999999999', mref: 'RBS-449812771');
      }
      g(day(m, 7), -1890, 'HanseMerkur Krankenversicherung', 'Zusatzversicherung Zahn', cred: 'DE33ZZZ00000004411', mref: 'HM-ZAHN-889');
      g(day(m, 2), -2490, 'RSG Group GmbH McFIT', 'Mitgliedsbeitrag McFIT', cred: 'DE11ZZZ00000330011', mref: 'MCFIT-77120');
      if (yearsAgo < 1.5) g(day(m, 2), -2900, 'Urban Sports GmbH', 'Urban Sports Club S', cred: 'DE55ZZZ00000990022', mref: 'USC-1122');
      if (yearsAgo < 3) {
        g(day(m, 1), -(yearsAgo > 1.9 ? 4900 : yearsAgo > 0.9 ? 5800 : 6300), 'Verkehrsverbund Musterstadt', 'Deutschlandticket ${m.month}/${m.year}',
            cred: 'DE66ZZZ00000123123', mref: 'DTICKET-4411');
      }
      g(day(m, 30), -495, 'Sparkasse Musterstadt', 'Entgelt Kontoführung ${m.month}/${m.year}');
      if (m.month == 1) g(day(m, 2), -(yearsAgo > 1 ? 49800 : 56400), 'HUK-COBURG', 'Kfz-Versicherung MU-KB 123', cred: 'DE44ZZZ00000111222', mref: 'HUK-KFZ-123');
      if (m.month == 3) g(day(m, 1), -8900, 'Allianz Versicherungs-AG', 'Privathaftpflicht Jahresbeitrag', cred: 'DE77ZZZ00000004321', mref: 'ALZ-PHV-9');
      if (m.month == 6) g(day(m, 10), -8990, 'Amazon EU S.a.r.l.', 'AMAZON PRIME JAHRESMITGLIEDSCHAFT', cred: 'DE24ZZZ00000561652', mref: 'PRIME-1');
      if (m.month == 5) g(day(m, 20), -14000, 'Bundeskasse Kfz-Steuer', 'KFZ-STEUER MU-KB 123');

      // --- Sparen & Umbuchungen
      g(day(m, 2), -20000, 'Trade Republic Bank GmbH', 'Sparplan ETF', iban: 'DE10100123450000000001');
      if (i % 2 == 0) {
        g(day(m, 29), -15000, 'Max Mustermann', 'Umbuchung Tagesgeld', iban: savingsIban);
        add(savings, savingsId, day(m, 29), 15000, 'Max Mustermann', 'Umbuchung Tagesgeld', iban: giroIban);
      }
      if (m.month == 12) add(savings, savingsId, day(m, 31), r(800, 4500), 'Bank', 'Zinsen ${m.year}');

      // --- Variable Ausgaben
      const grocers = ['REWE SAGT DANKE', 'ALDI SUED', 'LIDL DIENSTL. GMBH', 'EDEKA CENTER', 'NETTO MARKEN-DISCOUNT'];
      final shops = r(9, 13);
      for (var k = 0; k < shops; k++) {
        final name = grocers[rnd.nextInt(grocers.length)];
        g(day(m, r(1, 28)), -r(1200, 9500), '$name ${r(1000, 9999)}', 'KARTENZAHLUNG GIROCARD');
      }
      for (var k = 0; k < r(8, 14); k++) {
        g(day(m, r(1, 28)), -r(240, 690), 'Bäckerei Wagner', 'KARTENZAHLUNG');
      }
      for (var k = 0; k < r(2, 5); k++) {
        g(day(m, r(1, 28)), -r(450, 790), 'STARBUCKS COFFEE ${r(100, 999)}', 'KARTENZAHLUNG');
      }
      final deliveries = yearsAgo < 1 ? r(4, 7) : r(1, 4);
      for (var k = 0; k < deliveries; k++) {
        g(day(m, r(1, 28)), -r(1800, 3900), 'Lieferando.de', 'Bestellung ${r(100000, 999999)}');
      }
      for (var k = 0; k < r(2, 4); k++) {
        const restaurants = ['Ristorante Da Marco', 'Sushi Bar Sakura', 'Gasthaus Zur Linde', 'Burger Werk'];
        g(day(m, r(1, 28)), -r(2200, 8400), restaurants[rnd.nextInt(restaurants.length)], 'KARTENZAHLUNG');
      }
      if (yearsAgo > 2.5 || rnd.nextBool()) {
        for (var k = 0; k < r(1, 3); k++) {
          g(day(m, r(1, 28)), -r(4800, 7600), rnd.nextBool() ? 'ARAL STATION ${r(1000, 9999)}' : 'SHELL ${r(10000, 99999)}', 'KARTENZAHLUNG');
        }
      }
      for (var k = 0; k < r(1, 4); k++) {
        g(day(m, r(1, 28)), -r(990, 12900), 'AMAZON EU S.A R.L.', 'AMZN Mktp DE ${r(100, 999)}-${r(1000000, 9999999)}');
      }
      for (var k = 0; k < r(1, 3); k++) {
        g(day(m, r(1, 28)), -r(890, 3490), rnd.nextBool() ? 'DM-DROGERIE MARKT' : 'ROSSMANN ${r(1000, 9999)}', 'KARTENZAHLUNG');
      }
      if (rnd.nextInt(3) == 0) g(day(m, r(1, 28)), -r(2990, 11990), rnd.nextBool() ? 'Zalando SE' : 'H&M', 'Online-Bestellung');
      if (rnd.nextInt(4) == 0) g(day(m, r(1, 28)), -r(1990, 8990), 'DB Fernverkehr AG', 'BAHN.DE Ticket');
      if (rnd.nextInt(3) == 0) g(day(m, r(1, 28)), -r(590, 3290), 'Stadt-Apotheke', 'KARTENZAHLUNG');
      g(day(m, r(1, 28)), -(r(1, 3) * 5000), 'GA NR${r(10000000, 99999999)}', 'Bargeldauszahlung GELDAUTOMAT');
      if (m.month == 7) {
        g(day(m, r(1, 10)), -r(60000, 120000), 'Booking.com B.V.', 'Hotel Sommerurlaub');
        g(day(m, r(1, 10)), -r(12000, 34000), 'Ryanair DAC', 'Flug');
      }
      if (m.month == 12) {
        for (var k = 0; k < r(3, 6); k++) {
          g(day(m, r(1, 22)), -r(1990, 8990), 'AMAZON EU S.A R.L.', 'Weihnachtsgeschenk ${r(100, 999)}');
        }
      }
      if (m.month == 4 && i % 2 == 0) g(day(m, r(5, 20)), -r(18000, 42000), 'A.T.U Auto-Teile-Unger', 'Inspektion');
    }

    // Eine doppelte Lieferando-Buchung vor wenigen Tagen
    final dupDay = today.subtract(const Duration(days: 4));
    g(dupDay, -2790, 'Lieferando.de', 'Bestellung 551203');
    g(dupDay, -2790, 'Lieferando.de', 'Bestellung 551203 ');

    int sum(List<Transaction> l) => l.fold(0, (a, t) => a + t.amountCents);
    final accounts = [
      Account(
        id: giroId,
        iban: giroIban,
        name: 'Girokonto (Demo)',
        type: AccountType.giro,
        balanceCents: 250000 + sum(giro),
        balanceDate: today,
        color: '#2F5BEA',
      ),
      Account(
        id: savingsId,
        iban: savingsIban,
        name: 'Tagesgeld (Demo)',
        type: AccountType.tagesgeld,
        balanceCents: 500000 + sum(savings),
        balanceDate: today,
        color: '#1F9D6B',
      ),
    ];
    return (accounts: accounts, transactions: [...giro, ...savings]);
  }
}
