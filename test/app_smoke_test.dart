import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klarblick/data/models.dart';
import 'package:klarblick/data/store.dart';
import 'package:klarblick/main.dart';
import 'package:klarblick/ui/app_shell.dart';
import 'package:klarblick/ui/screens/onboarding.dart';

void main() {
  testWidgets('Onboarding rendert und erreichbar', (tester) async {
    final store = Store();
    store.settings['loaded'] = true;
    store.forceLoadedForTest();
    await tester.pumpWidget(ProviderScope(child: KlarblickApp(store: store)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text("Los geht's"), findsOneWidget);
  });

  testWidgets('AppShell rendert alle 5 Tabs bei vorhandenen Konten', (tester) async {
    final store = Store();
    store.accounts.add(const Account(id: 'a1', iban: 'DE00', name: 'Giro', type: AccountType.giro, balanceCents: 1000));
    store.settings['loaded'] = true;
    store.forceLoadedForTest();
    await tester.pumpWidget(ProviderScope(child: KlarblickApp(store: store)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byType(AppShell), findsOneWidget);
    for (final label in ['Übersicht', 'Umsätze', 'Analyse', 'Verträge', 'Sparen']) {
      expect(find.text(label), findsWidgets);
    }
  });
}
