import 'package:flutter_test/flutter_test.dart';
import 'package:klarblick/core/analytics/tx_filter.dart';
import 'package:klarblick/core/engine/engine.dart';
import 'package:klarblick/data/models.dart';

import 'helpers.dart';

var _n = 0;
Transaction _t(String cat, int cents, String name, {String account = 'a1', DateTime? date}) => Transaction(
      id: 't${_n++}',
      accountId: account,
      bookingDate: date ?? DateTime(2026, 10, 15),
      amountCents: cents,
      counterpartyName: name,
      categoryId: cat,
      dedupHash: 'h$_n',
    );

void main() {
  final engine = Engine(loadSeed());

  // 11 verschiedene Kategorien (2 Einnahmen, 9 Ausgaben) → bei „Alle“ wird nach Oberkategorien gruppiert.
  final txs = [
    for (var i = 0; i < 3; i++) _t('gehalt', 300000, 'Firma GmbH'),
    _t('erstattung', 20000, 'Finanzamt'),
    for (var i = 0; i < 5; i++) _t('supermarkt', -4000, 'REWE'),
    for (var i = 0; i < 2; i++) _t('baecker', -500, 'Bäckerei Wagner'),
    _t('drogerie', -1500, 'dm'),
    for (var i = 0; i < 2; i++) _t('restaurant', -3000, 'Pizzeria'),
    _t('miete', -90000, 'Vermieter', account: 'a2'),
    _t('strom-gas', -7000, 'Stadtwerke', account: 'a2'),
    _t('tanken', -6000, 'Aral'),
    _t('kino', -1800, 'Kino'),
    _t('arzt', -2500, 'Praxis'),
    _t('supermarkt', -3500, 'Netto', date: DateTime(2026, 9, 3)),
    _t('umbuchung', 15000, 'Max Mustermann', account: 'a2'), // Umbuchung zwischen eigenen Konten
    _t('sparen', -20000, 'Trade Republic'), // Sparplan
  ];

  TxFilterContext ctx({int accounts = 1, DateTime? from}) => TxFilterContext(
        categoryOf: engine.categoryById,
        merchantKey: (t) => t.counterpartyName,
        merchantName: (t) => t.counterpartyName,
        accountName: (id) => id == 'a1' ? 'Girokonto' : 'Tagesgeld',
        accountCount: accounts,
        rangeFrom: from ?? DateTime(2026, 10, 1),
        rangeLabel: 'Letzter Monat',
        searchText: (t) => '${t.counterpartyName} ${engine.categoryById(t.categoryId)?.name ?? ''}'.toLowerCase(),
      );

  List<String> labels(List<FilterChipSpec> l, [FilterDim? dim]) => [for (final c in l) if (dim == null || c.dim == dim) c.label];

  // Tippt die Chips nacheinander an (Auswahl oder Abwahl) und gibt den Filter zurück.
  TxFilter tap(TxFilter f, String label, {FilterDim? dim, TxFilterContext? context}) {
    final c = context ?? ctx();
    final bar = computeFilterBar(txs, f, c);
    final chip = [...bar.selected, ...bar.options].firstWhere((x) => x.label == label && (dim == null || x.dim == dim), orElse: () => throw StateError('Chip „$label“ nicht vorhanden. Leiste: ${labels(bar.selected)} | ${labels(bar.options)}'));
    return applyChip(f, chip, c);
  }

  test('ohne Auswahl: Art und Oberkategorien, größte zuerst', () {
    final bar = computeFilterBar(txs, const TxFilter(), ctx());
    expect(bar.selected, isEmpty);
    expect(labels(bar.options, FilterDim.kind), ['Ausgaben', 'Einnahmen']);
    final cats = labels(bar.options, FilterDim.category);
    expect(cats, containsAll(['Einkommen', 'Wohnen & Energie', 'Lebensmittel', 'Mobilität', 'Freizeit & Ausgehen', 'Gesundheit']));
    expect(cats.first, 'Einkommen', reason: 'nach Betrag sortiert');
    expect(cats, isNot(contains('Supermarkt')), reason: 'Unterkategorien erst nach Wahl der Oberkategorie');
  });

  test('Einnahmen gewählt: nur Kategorien, die unter Einnahmen laufen – direkt als Chips', () {
    final f = tap(const TxFilter(), 'Einnahmen');
    final bar = computeFilterBar(txs, f, ctx());
    expect(labels(bar.selected), ['Einnahmen']);
    expect(labels(bar.options, FilterDim.category), unorderedEquals(['Gehalt & Lohn', 'Erstattungen & Gutschriften']));
    expect(labels(bar.options, FilterDim.kind), isEmpty, reason: 'Ausgaben schließen sich aus');
    expect(labels(bar.options), isNot(contains('Lebensmittel')));
    expect(labels(bar.options), isNot(contains('Umbuchung (eigene Konten)')), reason: 'Umbuchungen sind keine Einnahmen');
    expect(filterTransactions(txs, f, ctx()), hasLength(4));
  });

  test('Umbuchungen und Sparpläne gehören weder zu Einnahmen noch zu Ausgaben, sind aber bei „Alle“ wählbar', () {
    final all = computeFilterBar(txs, const TxFilter(), ctx());
    expect(labels(all.options, FilterDim.category), containsAll(['Umbuchung (eigene Konten)', 'Sparen & Investieren']));
    final expenses = filterTransactions(txs, const TxFilter(kind: TxKind.expenses), ctx());
    expect(expenses.any((t) => t.categoryId == 'sparen'), isFalse);
    expect(labels(computeFilterBar(txs, const TxFilter(kind: TxKind.expenses), ctx()).options, FilterDim.category), isNot(contains('Sparen & Investieren')));
  });

  test('Gewähltes bleibt vorn, die übrigen gültigen Optionen rücken auf', () {
    var f = tap(const TxFilter(), 'Einnahmen');
    f = tap(f, 'Gehalt & Lohn');
    final bar = computeFilterBar(txs, f, ctx());
    expect(labels(bar.selected), ['Einnahmen', 'Einkommen', 'Gehalt & Lohn']);
    expect(labels(bar.options, FilterDim.category), isEmpty);
    expect(labels(bar.options), isNot(contains('Erstattungen & Gutschriften')));
  });

  test('Art abwählen: Kategorien werden mit abgewählt, alle Optionen sind wieder da', () {
    var f = tap(const TxFilter(), 'Einnahmen');
    f = tap(f, 'Gehalt & Lohn');
    f = tap(f, 'Einnahmen'); // Einnahmen ist gewählt → abwählen
    expect(f.kind, TxKind.all);
    expect(f.categoryId, isNull);
    final bar = computeFilterBar(txs, f, ctx());
    expect(bar.selected, isEmpty);
    expect(labels(bar.options, FilterDim.kind), ['Ausgaben', 'Einnahmen']);
    expect(labels(bar.options, FilterDim.category), contains('Lebensmittel'));
  });

  test('Oberkategorie → Unterkategorie; Abwählen der Oberkategorie nimmt die Unterkategorie mit', () {
    var f = tap(const TxFilter(), 'Ausgaben');
    f = tap(f, 'Lebensmittel');
    var bar = computeFilterBar(txs, f, ctx());
    expect(labels(bar.selected), ['Ausgaben', 'Lebensmittel']);
    expect(labels(bar.options, FilterDim.category), ['Supermarkt', 'Drogerie', 'Bäcker'], reason: 'nur Unterkategorien von Lebensmittel, nach Betrag');
    expect(labels(bar.options, FilterDim.category), isNot(contains('Mobilität')));

    f = tap(f, 'Supermarkt');
    bar = computeFilterBar(txs, f, ctx());
    expect(labels(bar.selected), ['Ausgaben', 'Lebensmittel', 'Supermarkt']);
    expect(labels(bar.options, FilterDim.category), isEmpty, reason: 'gleichrangige Unterkategorien erst nach Abwahl');

    // Unterkategorie abwählen → Oberkategorie bleibt
    final back = tap(f, 'Supermarkt');
    expect(back.categoryId, 'lebensmittel');
    // Oberkategorie abwählen → Unterkategorie ist ebenfalls weg
    final up = tap(f, 'Lebensmittel');
    expect(up.categoryId, isNull);
    expect(up.kind, TxKind.expenses, reason: 'die Art darüber bleibt');
    expect(labels(computeFilterBar(txs, up, ctx()).options, FilterDim.category), contains('Mobilität'));
  });

  test('Optionen ohne Treffer oder ohne Wirkung erscheinen nicht', () {
    // „rewe“ → nur Supermarkt-Ausgaben: weder Art noch Kategorie grenzen weiter ein
    const f = TxFilter(query: 'rewe');
    final bar = computeFilterBar(txs, f, ctx());
    expect(labels(bar.options, FilterDim.kind), isEmpty);
    expect(labels(bar.options, FilterDim.category), isEmpty);
    expect(filterTransactions(txs, f, ctx()), hasLength(5));

    // „Gehalt“-Suche → nur Einnahmen: „Einnahmen“ grenzt nicht mehr ein
    final b2 = computeFilterBar(txs, const TxFilter(query: 'firma'), ctx());
    expect(labels(b2.options, FilterDim.kind), isEmpty);
  });

  test('Firmen erst nach Eingrenzung, nur passende', () {
    expect(labels(computeFilterBar(txs, const TxFilter(), ctx()).options, FilterDim.merchant), isEmpty);
    var f = tap(const TxFilter(), 'Ausgaben');
    f = tap(f, 'Lebensmittel');
    final merchants = labels(computeFilterBar(txs, f, ctx()).options, FilterDim.merchant);
    expect(merchants, containsAll(['REWE', 'Bäckerei Wagner', 'dm']));
    expect(merchants, isNot(contains('Aral')));
    f = tap(f, 'REWE');
    expect(f.merchantKey, 'REWE');
    expect(filterTransactions(txs, f, ctx()), hasLength(5));
    // Kategorie abwählen → Firma darunter wird mit abgewählt
    final up = tap(f, 'Lebensmittel');
    expect(up.merchantKey, isNull);
  });

  test('Zeitraum-Chip nur, wenn er die Liste verändert', () {
    expect(labels(computeFilterBar(txs, const TxFilter(), ctx()).options, FilterDim.range), ['Letzter Monat']);
    expect(labels(computeFilterBar(txs, const TxFilter(), ctx(from: DateTime(2026, 1, 1))).options, FilterDim.range), isEmpty, reason: 'alles liegt im Zeitraum');
    final f = tap(const TxFilter(), 'Letzter Monat');
    expect(f.onlyRange, isTrue);
    expect(filterTransactions(txs, f, ctx()), hasLength(txs.length - 1), reason: 'nur der Umsatz aus dem September fällt heraus');
    expect(labels(computeFilterBar(txs, f, ctx()).selected), ['Letzter Monat']);
  });

  test('Konto-Chips nur bei mehreren Konten und nur mit Treffern', () {
    expect(labels(computeFilterBar(txs, const TxFilter(), ctx()).options, FilterDim.account), isEmpty);
    expect(labels(computeFilterBar(txs, const TxFilter(), ctx(accounts: 2)).options, FilterDim.account), ['Girokonto', 'Tagesgeld']);
    // Einnahmen gibt es nur auf dem Girokonto → Konto grenzt nicht mehr ein
    final f = tap(const TxFilter(), 'Einnahmen', context: ctx(accounts: 2));
    expect(labels(computeFilterBar(txs, f, ctx(accounts: 2)).options, FilterDim.account), isEmpty);
    // Konto wählen: bleibt vorn, Abwählen lässt Art/Kategorie unberührt
    var g = tap(const TxFilter(), 'Tagesgeld', context: ctx(accounts: 2));
    expect(filterTransactions(txs, g, ctx(accounts: 2)), hasLength(3), reason: 'Miete, Strom und die Umbuchung');
    // Auf dem Tagesgeld liegen nur Miete und Strom → nur diese beiden Kategorien sind noch sinnvoll.
    final onlyA2 = computeFilterBar(txs, g, ctx(accounts: 2));
    expect(labels(onlyA2.selected), ['Tagesgeld']);
    expect(labels(onlyA2.options, FilterDim.category), unorderedEquals(['Miete / Kreditrate', 'Strom & Gas', 'Umbuchung (eigene Konten)']));
    expect(labels(onlyA2.options, FilterDim.kind), ['Ausgaben'], reason: 'Einnahmen gibt es hier nicht');
    g = tap(g, 'Tagesgeld', context: ctx(accounts: 2));
    expect(g.accountId, isNull);
  });

  test('Suche und Chips zusammen', () {
    var f = const TxFilter(query: 'a');
    f = tap(f, 'Ausgaben');
    final list = filterTransactions(txs, f, ctx());
    expect(list.every((t) => t.amountCents < 0), isTrue);
    expect(list.every((t) => ctx().searchText(t).contains('a')), isTrue);
  });

  test('copyWith kann Felder gezielt auf null setzen', () {
    const f = TxFilter(categoryId: 'x', accountId: 'a', merchantKey: 'm', merchantName: 'M');
    expect(f.copyWith(categoryId: null).categoryId, isNull);
    expect(f.copyWith(query: 'q').categoryId, 'x');
    expect(f.copyWith(accountId: null, merchantKey: null, merchantName: null).hasChipSelection, isTrue, reason: 'Kategorie bleibt');
    expect(const TxFilter().isEmpty, isTrue);
  });
}
