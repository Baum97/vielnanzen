import 'package:shared_preferences/shared_preferences.dart';

import 'blob_storage.dart';

BlobStorage createPlatformBlobStorage() => PrefsBlobStorage();

/// Web: verschlüsselter Container im localStorage des Browsers.
class PrefsBlobStorage implements BlobStorage {
  static const _key = 'klarblick.db.enc';

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String data) async => (await SharedPreferences.getInstance()).setString(_key, data);

  @override
  Future<void> delete() async => (await SharedPreferences.getInstance()).remove(_key);

  @override
  Future<void> backupCorrupt(String data) async =>
      (await SharedPreferences.getInstance()).setString('$_key.corrupt', data);
}
