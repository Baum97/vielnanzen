import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Geheimnisspeicher der App: Datenbankschlüssel und (optional) Bank-PINs.
///
/// Auf dem Gerät liegt alles im iOS-Keychain bzw. Android-Keystore
/// (über `flutter_secure_storage`). Im Browser verschlüsselt das Plugin mit
/// WebCrypto. Für Tests gibt es [MemorySecureKeyStore].
abstract class SecureKeyStore {
  Future<Uint8List> getOrCreateDatabaseKey();
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
  Future<void> deleteAll();
}

class DeviceSecureKeyStore implements SecureKeyStore {
  DeviceSecureKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  static const _dbKeyName = 'klarblick.dbkey.v2';

  /// Alter Speicherort (v1: SharedPreferences, unsicher) – wird einmalig migriert.
  static const _legacyPrefsKey = 'klarblick.dbkey.v1';

  final FlutterSecureStorage _storage;
  Uint8List? _cached;

  @override
  Future<Uint8List> getOrCreateDatabaseKey() async {
    if (_cached != null) return _cached!;
    String? existing;
    try {
      existing = await _storage.read(key: _dbKeyName);
    } catch (e) {
      // Keystore nicht mehr lesbar (z. B. nach Neuinstallation/Gerätewechsel):
      // Einträge verwerfen und neu beginnen – der alte Datencontainer wäre ohnehin
      // nicht mehr zu entschlüsseln und wird vom Store gesichert.
      debugPrint('Sicherer Speicher nicht lesbar, setze zurück: $e');
      await _storage.deleteAll();
    }
    if (existing != null) return _cached = Uint8List.fromList(base64Decode(existing));

    // Migration aus SharedPreferences (Version 1.0)
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_legacyPrefsKey);
      if (legacy != null) {
        await _storage.write(key: _dbKeyName, value: legacy);
        await prefs.remove(_legacyPrefsKey);
        return _cached = Uint8List.fromList(base64Decode(legacy));
      }
    } catch (e) {
      debugPrint('Schlüssel-Migration übersprungen: $e');
    }

    final raw = randomBytes(32);
    await _storage.write(key: _dbKeyName, value: base64Encode(raw));
    return _cached = raw;
  }

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) =>
      value == null ? _storage.delete(key: key) : _storage.write(key: key, value: value);

  @override
  Future<void> deleteAll() async {
    _cached = null;
    await _storage.deleteAll();
  }
}

class MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> _values = {};
  Uint8List? _key;

  @override
  Future<Uint8List> getOrCreateDatabaseKey() async => _key ??= randomBytes(32);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<void> deleteAll() async {
    _values.clear();
    _key = null;
  }
}

Uint8List randomBytes(int n) {
  final random = Random.secure();
  return Uint8List.fromList(List<int>.generate(n, (_) => random.nextInt(256)));
}

/// Leitet aus dem Rohschlüssel den AES-256-Schlüssel ab.
Uint8List deriveDatabaseKey(Uint8List raw) => Uint8List.fromList(sha256.convert(raw).bytes);
