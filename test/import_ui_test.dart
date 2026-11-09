import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:klarblick/core/seed/demo_data.dart';
import 'package:klarblick/data/bank_directory.dart';
import 'package:klarblick/data/models.dart';
import 'package:klarblick/data/store.dart';
import 'package:klarblick/main.dart';
import 'package:klarblick/services/import_service.dart';
import 'package:klarblick/services/incoming_files.dart';
import 'package:klarblick/state/app_state.dart';
import 'package:klarblick/state/bank_directory_provider.dart';
import 'package:klarblick/ui/app_shell.dart';
import 'package:klarblick/ui/screens/bank_connect.dart';
import 'package:klarblick/ui/screens/import_screen.dart';

import 'helpers.dart';

const dkb = 'DE02120300000000202051';

IncomingFile _file(String name, String content) => IncomingFile(name, Uint8List.fromList(utf8.encode(content)));

Future<ProviderContainer> _openImport(WidgetTester tester, Store store, List<IncomingFile> files) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final directory = BankDirectory.fromJsonString(File('assets/data/bank_directory.json').readAsStringSync());
  await tester.pumpWidget(ProviderScope(
    overrides: [
      storeProvider.overrideWithValue(store),
      bankDirectoryProvider.overrideWith((ref) => directory),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => ImportScreen(initialFiles: files))),
            child: const Text('öffnen'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('öffnen'));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(ImportScreen)));
}

void main() {
  analysisInIsolate = false;
  setUpAll(() async => initializeDateFormatting('de_DE'));

  testWidgets('Import: Konto wird aus der Datei erkannt und vorausgewählt', (tester) async {
    final store = memoryStore();
    await store.load();
    store.upsertAccount(const Account(id: 'acc1', iban: dkb, name: 'Mein DKB', type: AccountType.giro, balanceCents: 1000));
    store.upsertAccount(const Account(id: 'acc2', iban: 'DE89370400440532013000', name: 'Anderes Konto', type: AccountType.giro));

    await _openImport(tester, store, [
      _file(
        'auszug.csv',
        'Auftragskonto;Buchungstag;Verwendungszweck;Beguenstigter/Zahlungspflichtiger;Betrag\n'
            '$dkb;03.11.26;Netflix Abo;Netflix International B.V.;-15,99\n'
            '$dkb;04.11.26;Gehalt;Firma GmbH;2.000,00\n',
      ),
    ]);

    expect(find.textContaining('Konto in der Datei erkannt: $dkb'), findsOneWidget);
    expect(find.text('Mein DKB'), findsWidgets);
    final button = find.text('2 neue Umsätze importieren');
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(store.transactions, hasLength(2));
    expect(store.transactions.every((t) => t.accountId == 'acc1'), isTrue, reason: 'ohne Rückfrage dem erkannten Konto zugeordnet');
    expect(store.accounts, hasLength(2), reason: 'kein neues Konto angelegt');
    store.dispose();
  });

  testWidgets('Import: unbekannte Datei → Spalten zuordnen → gemerkt', (tester) async {
    final store = memoryStore();
    await store.load();
    store.upsertAccount(const Account(id: 'tr', iban: '', name: 'Trade Republic', type: AccountType.giro));
    const csv = 'Datum;Typ;Name;Wert;Kontostand\n'
        '05.11.2026;Kartentransaktion;REWE Markt;-45,10;1.000,00\n'
        '04.11.2026;Überweisung;Max Muster;50,00;1.045,10\n'
        '03.11.2026;Kartentransaktion;Starbucks;-4,80;995,10\n';

    await _openImport(tester, store, [_file('export.csv', csv)]);
    expect(find.textContaining('unbekannt'), findsWidgets);
    await tester.tap(find.text('Spalten zuordnen'));
    await tester.pumpAndSettle();

    // Der Vorschlag passt bereits: übernehmen.
    await tester.scrollUntilVisible(find.text('Zuordnung übernehmen'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Vorschau mit dieser Zuordnung'), findsOneWidget);
    await tester.tap(find.text('Zuordnung übernehmen'));
    await tester.pumpAndSettle();

    final button = find.text('3 neue Umsätze importieren');
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(store.transactions.map((t) => t.amountCents).toSet(), {-4510, 5000, -480});
    expect(savedMappings(store), hasLength(1), reason: 'Zuordnung für das nächste Mal gemerkt');
    store.dispose();
  });

  testWidgets('Import: neues Konto bekommt Namen der Bank aus der IBAN', (tester) async {
    final store = memoryStore();
    await store.load();
    await _openImport(tester, store, [
      _file('mt940.sta', ':20:X\r\n:25:$dkb\r\n:28C:1/1\r\n:60F:C261101EUR100,00\r\n:61:2611031103DR15,99NDDTNONREF\r\n:86:105?00FOLGELASTSCHRIFT?20SVWZ+Abo?32NETFLIX\r\n:62F:C261103EUR84,01\r\n-\r\n'),
    ]);
    expect(find.text('+ Neues Konto anlegen'), findsWidgets);
    final nameField = tester.widget<TextField>(find.widgetWithText(TextField, 'Name des neuen Kontos'));
    expect(nameField.controller!.text, contains('Kredit'));
    expect(nameField.controller!.text, endsWith('…2051'));
    await tester.ensureVisible(find.text('1 neue Umsätze importieren'));
    await tester.tap(find.text('1 neue Umsätze importieren'));
    await tester.pumpAndSettle();
    expect(store.accounts.single.iban, dkb);
    expect(store.accounts.single.balanceCents, 8401, reason: 'Schlusssaldo aus der Datei');
    store.dispose();
  });

  testWidgets('Banksuche füllt die FinTS-Adresse automatisch', (tester) async {
    final store = memoryStore();
    await store.load();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final directory = BankDirectory.fromJsonString(File('assets/data/bank_directory.json').readAsStringSync());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        bankDirectoryProvider.overrideWith((ref) => directory),
        noFintsBanksProvider.overrideWith((ref) => const [NoFintsBank('Trade Republic Bank', 'Berlin', 'Kein FinTS.')]),
      ],
      child: const MaterialApp(home: BankConnectScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ING');
    await tester.pumpAndSettle();
    expect(find.textContaining('ING-DiBa'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'trade');
    await tester.pumpAndSettle();
    expect(find.text('Trade Republic Bank'), findsOneWidget);
    expect(find.text('Kein FinTS – Datei-Import'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'DE02 1203 0000 0000 2020 51');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Kredit').first);
    await tester.pumpAndSettle();
    // Ohne Produkt-ID ist der Bereich „Bankdaten & FinTS“ bereits aufgeklappt.
    expect(find.text('12030000'), findsOneWidget);
    expect(find.text('https://fints.dkb.de/fints'), findsOneWidget);
    store.dispose();
  });

  test('Geteilte Dateien kommen vom nativen Kanal an', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final store = memoryStore();
    final container = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel(IncomingFilesService.channelName), (call) async {
      if (call.method == 'takeInitialFiles') {
        return [
          {'name': 'start.csv', 'bytes': Uint8List.fromList([65, 66])},
          {'name': 'leer.csv', 'bytes': Uint8List(0)},
          'kaputt',
        ];
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(const MethodChannel(IncomingFilesService.channelName), null));

    await container.read(incomingFilesServiceProvider).start();
    expect(container.read(incomingFilesProvider).map((f) => f.name), ['start.csv'], reason: 'leere und ungültige Einträge werden verworfen');

    // Später: die App läuft schon, eine weitere Datei wird geteilt.
    const codec = StandardMethodCodec();
    await messenger.handlePlatformMessage(
      IncomingFilesService.channelName,
      codec.encodeMethodCall(MethodCall('incomingFiles', [
        {'name': 'zweite.csv', 'bytes': Uint8List.fromList([67])},
      ])),
      (_) {},
    );
    expect(container.read(incomingFilesProvider).map((f) => f.name), ['start.csv', 'zweite.csv']);
    expect(container.read(incomingFilesProvider.notifier).take(), hasLength(2));
    expect(container.read(incomingFilesProvider), isEmpty);
  });

  testWidgets('Geteilte Datei öffnet in der laufenden App den Import', (tester) async {
    final store = memoryStore();
    await store.load();
    final demo = DemoData.generate();
    for (final a in demo.accounts) {
      store.upsertAccount(a);
    }
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final seed = loadSeed();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        seedProvider.overrideWithValue(seed),
        bankDirectoryProvider.overrideWith((ref) => BankDirectory.fromJsonString(File('assets/data/bank_directory.json').readAsStringSync())),
      ],
      child: const KlarblickApp(),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AppShell), findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    container.read(incomingFilesProvider.notifier).add([_file('neu.csv', 'Datum;Name;Zweck;Betrag\n01.11.2026;Kiosk;Zeitung;-2,50\n')]);
    await tester.pumpAndSettle();
    expect(find.byType(ImportScreen), findsOneWidget);
    expect(find.text('neu.csv'), findsOneWidget);
    expect(container.read(incomingFilesProvider), isEmpty);
    store.dispose();
  });
}
