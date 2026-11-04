import '../../data/models.dart';
import '../engine/normalize.dart';

/// Demo-Datensatz: synthetische, lokal erzeugte Umsätze für den ersten Start,
/// wenn noch keine Bank verbunden ist. Ausschließlich lokal generiert –
/// es findet kein Netzwerkverkehr statt.
class DemoData {
  static List<Transaction> generate(String accountId, {int months = 6}) {
    final out = <Transaction>[];
    final now = DateTime.now();
    var n = 0;
    String id() => 'demo_${accountId}_${n++}';

    void add(DateTime date, int cents, String name, String purpose, {String? creditorId, String? mandateRef, String? endToEnd}) {
      out.add(Transaction(
        id: id(),
        accountId: accountId,
        bookingDate: date,
        amountCents: cents,
        counterpartyName: name,
        purpose: purpose,
        creditorId: creditorId,
        mandateRef: mandateRef,
        endToEndRef: endToEnd,
        dedupHash: dedupHash(accountId, date, cents, endToEnd, '$name $purpose'),
      ));
    }

    for (var m = months - 1; m >= 0; m--) {
      final ms = DateTime(now.year, now.month - m, 1);
      add(DateTime(ms.year, ms.month, 1), 285000, 'Arbeitgeber GmbH', 'Gehalt', endToEnd: 'E$m');
      add(DateTime(ms.year, ms.month, 2), -120000, 'Vermieter Schmidt', 'Miete', endToEnd: 'M$m');
      add(DateTime(ms.year, ms.month, 3), -4999, 'Netflix International', 'SVWZ+ABO NETFLIX', creditorId: 'DE26ZZZ00000000001', mandateRef: 'MAND-NFLX-$m');
      add(DateTime(ms.year, ms.month, 3), -999, 'Spotify AB', 'SVWZ+ABO SPOTIFY', mandateRef: 'MAND-SPO-$m');
      add(DateTime(ms.year, ms.month, 5), -5599, 'Telekom Deutschland', 'SVWZ+Mobilfunk', creditorId: 'DE98ZZZ09999999999', mandateRef: 'MAND-TEL-$m');
      add(DateTime(ms.year, ms.month, 5), -1099, 'TK Techniker Krankenkasse', 'Beitrag', mandateRef: 'MAND-TK-$m');
      add(DateTime(ms.year, ms.month, 7), -1799, 'Stadtwerke Beispielstadt', 'Strom Abschlag', mandateRef: 'MAND-SW-$m');
      add(DateTime(ms.year, ms.month, 10), -3200, 'Allianz Versicherung', 'SVWZ+Beitrag KFZ', mandateRef: 'MAND-ALL-$m');
      add(DateTime(ms.year, ms.month, 12), -899, 'ARD ZDF Deutschlandradio', 'SVWZ+Rundfunk', creditorId: 'DE98ZZZ09999999998', mandateRef: 'MAND-ARD-$m');
      add(DateTime(ms.year, ms.month, 15), -4590, 'REWE Sagt Danke', 'KARTENZAHLUNG 4711', endToEnd: 'K$m-1');
      add(DateTime(ms.year, ms.month, 18), -1250, 'REWE Markt GmbH', 'KARTENZAHLUNG 0042', endToEnd: 'K$m-2');
      add(DateTime(ms.year, ms.month, 20), -2499, 'Stadtwerke Beispielstadt', 'Wasser Abschlag', mandateRef: 'MAND-SW2-$m');
      add(DateTime(ms.year, ms.month, 22), -799, 'Fitness First GmbH', 'SVWZ+MITGLIED', mandateRef: 'MAND-FF-$m');
      add(DateTime(ms.year, ms.month, 25), -1500, 'KFZ Steuer', 'SEPA-LASTSCHRIFT', endToEnd: 'S$m');
      add(DateTime(ms.year, ms.month, 26), -890, 'HanseMerkur Krankenkasse', 'Beitrag Zusatz', mandateRef: 'MAND-HMK-$m');
    }
    return out;
  }
}
