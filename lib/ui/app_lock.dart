import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../state/app_state.dart';
import 'widgets.dart';

/// Biometrie/Geräte-PIN über das Betriebssystem (Face ID, Touch ID, Fingerabdruck).
class DeviceAuth {
  static final _auth = LocalAuthentication();

  static Future<bool> available() async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate(String reason) async {
    if (kIsWeb) return true;
    try {
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } catch (e) {
      debugPrint('Authentifizierung fehlgeschlagen: $e');
      return false;
    }
  }
}

/// Sperrt die App beim Start und nach 60 s im Hintergrund, wenn „App-Sperre“ aktiv ist.
class AppLockGate extends ConsumerStatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _authenticating = false;
  DateTime? _backgroundSince;

  bool get _enabled => ref.read(storeProvider).settings['appLock'] == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _unlocked = !_enabled;
    if (!_unlocked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _backgroundSince ??= DateTime.now();
      ref.read(storeProvider).save();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundSince;
      _backgroundSince = null;
      if (_enabled && !_authenticating && since != null && DateTime.now().difference(since).inSeconds > 60) {
        setState(() => _unlocked = false);
        _unlock();
      }
    }
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    _authenticating = true;
    final ok = await DeviceAuth.authenticate('Klarblick entsperren');
    _authenticating = false;
    if (mounted && ok) setState(() => _unlocked = true);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appStateProvider.select((s) => s.revision));
    if (_unlocked || !_enabled) return widget.child;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Klarblick ist gesperrt', style: theme.textTheme.titleMedium),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Entsperren', icon: Icons.fingerprint, onPressed: _unlock),
            ]),
          ),
        ),
      ),
    );
  }
}
