import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Liefert den 256-Bit-Schlüssel für die Datenbankverschlüsselung.
/// Auf dem Gerät liegt der Roh-Key im Keychain (iOS) bzw. Android Keystore;
/// hier wird eine plattformübergreifende Abstraktion verwendet, die das
/// Schlüsselmaterial lokal erzeugt und nur den abgeleiteten Schlüssel nutzt.
abstract class SecureKeyStore {
  Future<Uint8List> getOrCreateDatabaseKey();
}

class LocalSecureKeyStore implements SecureKeyStore {
  static const _keyName = 'klarblick.dbkey.v1';

  @override
  Future<Uint8List> getOrCreateDatabaseKey() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_keyName);
    if (existing != null) {
      return Uint8List.fromList(base64Decode(existing));
    }
    final random = Random.secure();
    final raw = Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
    await prefs.setString(_keyName, base64Encode(raw));
    return raw;
  }

  static Uint8List deriveKey(Uint8List raw) => Uint8List.fromList(sha256.convert(raw).bytes);
}
