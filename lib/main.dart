import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/engine/engine.dart';
import 'data/store.dart';
import 'services/incoming_files.dart';
import 'state/app_state.dart';
import 'ui/app_lock.dart';
import 'ui/app_shell.dart';
import 'ui/nav_key.dart';
import 'ui/screens/import_screen.dart';
import 'ui/screens/onboarding.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE');
  final store = Store();
  final results = await Future.wait([store.load(), SeedData.loadFromAssets()]);
  runApp(ProviderScope(
    overrides: [
      storeProvider.overrideWithValue(store),
      seedProvider.overrideWithValue(results[1] as SeedData),
    ],
    child: const KlarblickApp(),
  ));
}

class KlarblickApp extends ConsumerStatefulWidget {
  const KlarblickApp({super.key});

  @override
  ConsumerState<KlarblickApp> createState() => _KlarblickAppState();
}

class _KlarblickAppState extends ConsumerState<KlarblickApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(storeProvider).transactions.isNotEmpty) ref.read(appStateProvider.notifier).runAnalysis();
      // „Teilen → Klarblick“ / „Öffnen mit“ (Android)
      ref.read(incomingFilesServiceProvider).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appStateProvider.select((s) => s.revision));
    final mode = ref.read(storeProvider).settings['darkMode'] as String? ?? 'system';
    return MaterialApp(
      title: 'Klarblick',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: switch (mode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('de', 'DE')],
      locale: const Locale('de', 'DE'),
      home: const AppLockGate(child: HomeGate()),
    );
  }
}

/// Ohne Konten → Onboarding, sonst die App. Übernimmt außerdem per „Teilen“ übergebene Dateien –
/// erst hier, also nachdem die App-Sperre entsperrt wurde.
class HomeGate extends ConsumerStatefulWidget {
  const HomeGate({super.key});

  @override
  ConsumerState<HomeGate> createState() => _HomeGateState();
}

class _HomeGateState extends ConsumerState<HomeGate> {
  void _openIncoming() {
    if (!mounted) return;
    final files = ref.read(incomingFilesProvider.notifier).take();
    if (files.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => ImportScreen(initialFiles: files)));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openIncoming());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(incomingFilesProvider, (_, next) {
      if (next.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _openIncoming());
    });
    ref.watch(appStateProvider.select((s) => s.revision));
    final store = ref.read(storeProvider);
    if (!store.isLoaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return store.accounts.isEmpty ? const OnboardingScreen() : const AppShell();
  }
}
