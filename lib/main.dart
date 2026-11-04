import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/store.dart';
import 'state/app_state.dart';
import 'ui/app_shell.dart';
import 'ui/screens/onboarding.dart';
import 'ui/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store();
  await store.load();
  runApp(ProviderScope(child: KlarblickApp(store: store)));
}

class KlarblickApp extends ConsumerStatefulWidget {
  final Store store;
  const KlarblickApp({super.key, required this.store});

  @override
  ConsumerState<KlarblickApp> createState() => _KlarblickAppState();
}

class _KlarblickAppState extends ConsumerState<KlarblickApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appStateProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(appStateProvider).store.settings['darkMode'] as String? ?? 'system';
    final themeMode = switch (mode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return MaterialApp(
      title: 'Klarblick',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('de', 'DE')],
      locale: const Locale('de', 'DE'),
      home: _HomeGate(store: widget.store),
    );
  }
}

class _HomeGate extends ConsumerWidget {
  final Store store;
  const _HomeGate({required this.store});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = store.isLoaded || ref.watch(appStateProvider).store.isLoaded;
    if (!loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return store.accounts.isEmpty ? const OnboardingScreen() : const AppShell();
  }
}
