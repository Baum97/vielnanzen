
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Eine Datei, die per „Teilen“ oder „Öffnen mit“ an Klarblick übergeben wurde.
class IncomingFile {
  const IncomingFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Wartende Dateien. Die Oberfläche übernimmt sie erst, wenn die App entsperrt ist –
/// so umgeht eine geteilte Datei nie die App-Sperre.
final incomingFilesProvider = NotifierProvider<IncomingFilesNotifier, List<IncomingFile>>(IncomingFilesNotifier.new);

class IncomingFilesNotifier extends Notifier<List<IncomingFile>> {
  @override
  List<IncomingFile> build() => const [];

  void add(List<IncomingFile> files) {
    if (files.isNotEmpty) state = [...state, ...files];
  }

  /// Liefert die wartenden Dateien und leert die Warteschlange.
  List<IncomingFile> take() {
    final files = state;
    state = const [];
    return files;
  }
}

/// Wandelt die Antwort des nativen Kanals (Liste von {name, bytes}) in Dateien um.
List<IncomingFile> decodeIncoming(Object? raw) {
  if (raw is! List) return const [];
  final out = <IncomingFile>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final bytes = e['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) continue;
    out.add(IncomingFile((e['name'] as String?)?.trim().isNotEmpty == true ? e['name'] as String : 'Datei', bytes));
  }
  return out;
}

/// Verbindung zum nativen Teil (Android): Dateien beim Start und während die App läuft.
class IncomingFilesService {
  IncomingFilesService(this.ref, {MethodChannel? channel}) : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'de.klarblick.klarblick/incoming';

  final Ref ref;
  final MethodChannel _channel;

  Future<void> start() async {
    if (kIsWeb) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'incomingFiles') ref.read(incomingFilesProvider.notifier).add(decodeIncoming(call.arguments));
      return null;
    });
    try {
      ref.read(incomingFilesProvider.notifier).add(decodeIncoming(await _channel.invokeMethod<Object>('takeInitialFiles')));
    } on MissingPluginException {
      // iOS/Desktop: kein nativer Teil – Dateien werden dort über „Datei wählen“ geladen.
    } on PlatformException catch (e) {
      debugPrint('Geteilte Datei konnte nicht gelesen werden: ${e.message}');
    }
  }
}

final incomingFilesServiceProvider = Provider<IncomingFilesService>(IncomingFilesService.new);
