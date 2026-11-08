import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'blob_storage.dart';

BlobStorage createPlatformBlobStorage() => FileBlobStorage();

/// Atomares Schreiben: erst in eine temporäre Datei, dann umbenennen –
/// ein Absturz mitten im Speichern zerstört so nie den letzten Stand.
class FileBlobStorage implements BlobStorage {
  static const fileName = 'klarblick.db.enc';
  File? _file;

  Future<File> _target() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final file = File('${dir.path}/$fileName');
    // Migration: 1.0 hat im Dokumente-Ordner gespeichert (auf iOS für den Nutzer sichtbar).
    if (!await file.exists()) {
      try {
        final legacyDir = await getApplicationDocumentsDirectory();
        final legacy = File('${legacyDir.path}/$fileName');
        if (await legacy.exists()) await legacy.rename(file.path);
      } catch (_) {}
    }
    return _file = file;
  }

  @override
  Future<String?> read() async {
    final f = await _target();
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String data) async {
    final f = await _target();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete() async {
    final f = await _target();
    if (await f.exists()) await f.delete();
  }

  @override
  Future<void> backupCorrupt(String data) async {
    final f = await _target();
    await File('${f.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}').writeAsString(data);
  }
}
