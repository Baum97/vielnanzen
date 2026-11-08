import 'blob_storage_stub.dart'
    if (dart.library.io) 'blob_storage_io.dart'
    if (dart.library.js_interop) 'blob_storage_web.dart' as impl;

/// Ablage für den verschlüsselten Datencontainer (ein einzelner String).
abstract class BlobStorage {
  Future<String?> read();
  Future<void> write(String data);
  Future<void> delete();

  /// Sichert einen nicht lesbaren Container, statt ihn zu überschreiben.
  Future<void> backupCorrupt(String data);

  /// Plattform-Standard: Datei im App-Verzeichnis (Android/iOS) bzw. localStorage (Web).
  factory BlobStorage.platform() => impl.createPlatformBlobStorage();
}

class MemoryBlobStorage implements BlobStorage {
  String? data;
  String? corrupt;

  @override
  Future<String?> read() async => data;

  @override
  Future<void> write(String value) async => data = value;

  @override
  Future<void> delete() async => data = null;

  @override
  Future<void> backupCorrupt(String value) async => corrupt = value;
}
