import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:klarblick/core/engine/engine.dart';
import 'package:klarblick/core/seed/demo_data.dart';
import 'package:klarblick/data/store.dart';
import 'package:klarblick/main.dart';
import 'package:klarblick/state/app_state.dart';
import 'package:klarblick/ui/app_shell.dart';
import 'package:klarblick/ui/screens/onboarding.dart';
import 'package:klarblick/ui/tabs/savings_tab.dart';
import 'package:klarblick/ui/widgets.dart';

import 'helpers.dart';

Future<Store> _demoStore(SeedData seed) async {
  final store = memoryStore();
  await store.load();
  final demo = DemoData.generate();
  final result = Engine(seed).run(transactions: demo.transactions, accounts: demo.accounts, rules: const [], existingContracts: const []);
  for (final a in demo.accounts) {
    store.upsertAccount(a);
  }
  store.upsertTransactions(result.transactions);
  store.contracts.addAll(result.contracts);
  store.replaceInsights(result.insights);
  return store;
}

Future<void> _pumpApp(WidgetTester tester, Store store, SeedData seed, {Size size = const Size(1170, 2532), double ratio = 3}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [storeProvider.overrideWithValue(store), seedProvider.overrideWithValue(seed)],
    child: const KlarblickApp(),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  final seed = loadSeed();
  analysisInIsolate = false;

  setUpAll(() async => initializeDateFormatting('de_DE'));

  testWidgets('Onboarding ohne Konten', (tester) async {
    final store = memoryStore();
    await store.load();
    await _pumpApp(tester, store, seed);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    await tester.tap(find.text("Los geht's"));
    await tester.pumpAndSettle();
    expect(find.text('App schützen'), findsOneWidget);
    await tester.tap(find.text('Später'));
    await tester.pumpAndSettle();
    expect(find.text('Erstes Konto hinzufügen'), findsOneWidget);
    expect(find.text('Bank verbinden'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Alle Tabs und Zeiträume rendern mit 5 Jahren Daten', (tester) async {
    final store = await _demoStore(seed);
    await _pumpApp(tester, store, seed);
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text('Gesamtsaldo'), findsOneWidget);

    // Zeiträume durchschalten
    for (final r in ['1W', '1M', '3M', '6M', 'YTD', '1J', '5J', 'Max']) {
      await tester.tap(find.text(r).first);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'Zeitraum $r');
    }

    // Tabs
    for (final tab in ['Ausgaben', 'Umsätze', 'Abos', 'Sparen', 'Übersicht']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Tab $tab');
    }

    // Ausgaben: Wo / Wann
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Ausgaben')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wo'));
    await tester.pumpAndSettle();
    expect(find.text('REWE'), findsWidgets);
    await tester.tap(find.text('Wann'));
    await tester.pumpAndSettle();
    expect(find.text('Nach Wochentag'), findsOneWidget);

    // Sparen zeigt Hinweise
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Sparen')));
    await tester.pumpAndSettle();
    expect(find.text('Sparpotenzial'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Abos parallel'),
      300,
      scrollable: find.descendant(of: find.byType(SavingsTab), matching: find.byType(Scrollable)).first,
    );
    expect(find.textContaining('Abos parallel'), findsWidgets);

    // Abos zeigt Fixkosten
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Abos')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fixkosten'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    store.dispose();
  });

  testWidgets('Dunkles Design und Diskret-Modus', (tester) async {
    final store = await _demoStore(seed);
    store.updateSettings({'darkMode': 'dark', 'discreetMode': true});
    await _pumpApp(tester, store, seed);
    expect(find.textContaining('•••'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
    store.dispose();
  });

  testWidgets('Kleiner Android-Bildschirm: Detailseiten öffnen', (tester) async {
    final store = await _demoStore(seed);
    await _pumpApp(tester, store, seed, size: const Size(720, 1280), ratio: 2);
    final nav = find.byType(NavigationBar);

    Future<void> toTop() async {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 5000));
      await tester.pumpAndSettle();
    }

    // tester.pageBack() sucht den englischen Tooltip „Back“ – die App ist deutsch.
    Future<void> back() async {
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
    }

    Future<void> reveal(Finder f) async {
      for (var i = 0; i < 30 && f.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
        await tester.pump();
      }
      await tester.scrollUntilVisible(f.last, 100, scrollable: find.byType(Scrollable).first, maxScrolls: 1).catchError((_) {});
      await Scrollable.ensureVisible(tester.element(f.last), alignment: 0.5);
      await tester.pumpAndSettle();
    }

    // Letzter Treffer = Listeneintrag (erster ist ggf. Legende/Überschrift)
    Future<void> openFirst(Finder f) async {
      await reveal(f);
      await tester.tap(f.last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await back();
    }

    // Übersicht → Firma
    await tester.tap(find.text('1J').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Ausgaben → Kategorie-Detail, Firmen-Detail
    await tester.tap(find.descendant(of: nav, matching: find.text('Ausgaben')));
    await tester.pumpAndSettle();
    await openFirst(find.text('Lebensmittel'));
    await toTop();
    await tester.tap(find.text('Wo'));
    await tester.pumpAndSettle();
    await openFirst(find.text('REWE'));
    await toTop();
    await tester.tap(find.text('Wann'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Umsätze → Detail
    await tester.tap(find.descendant(of: nav, matching: find.text('Umsätze')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ausgaben').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TransactionRow).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await back();

    // Abos → Vertrag → Kündigungshilfe
    await tester.tap(find.descendant(of: nav, matching: find.text('Abos')));
    await tester.pumpAndSettle();
    await reveal(find.text('Netflix'));
    await tester.tap(find.text('Netflix').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Kündigungsschreiben erstellen'), 300, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Kündigungsschreiben erstellen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sonderkündigung'), findsWidgets);
    await back();
    await back();

    // Kalender
    await toTop();
    await tester.tap(find.byTooltip('Kalender'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Sparen
    await tester.tap(find.descendant(of: nav, matching: find.text('Sparen')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Einstellungen & Konten
    await tester.tap(find.descendant(of: nav, matching: find.text('Übersicht')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Einstellungen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konten & Banken'));
    await tester.pumpAndSettle();
    expect(find.text('Girokonto (Demo)'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 1));
    store.dispose();
  });
}
