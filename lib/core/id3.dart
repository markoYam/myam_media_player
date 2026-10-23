import 'dart:io';
import 'dart:typed_data';

/// Etiqueta ID3v2.3 mínima (título y artista) para los MP3 generados, en UTF-16 con BOM para
/// admitir acentos, emojis y cualquier alfabeto (port de Id3v2.kt de la versión Android).
class Id3v2 {
  Id3v2._();

  static const _maxText = 250;

  static Uint8List build({String? title, String? artist}) {
    final frames = BytesBuilder();
    if (title != null && title.trim().isNotEmpty) _frame(frames, 'TIT2', _clip(title));
    if (artist != null && artist.trim().isNotEmpty) _frame(frames, 'TPE1', _clip(artist));
    if (frames.isEmpty) return Uint8List(0);
    final body = frames.takeBytes();
    return (BytesBuilder()
          ..add('ID3'.codeUnits)
          ..add(const [3, 0, 0]) // versión 2.3.0, sin flags
          ..add(syncSafe(body.length))
          ..add(body))
        .takeBytes();
  }

  /// Recorta por runas para no partir un emoji.
  static String _clip(String s) => s.runes.length <= _maxText ? s : String.fromCharCodes(s.runes.take(_maxText));

  static void _frame(BytesBuilder out, String id, String text) {
    // Codificación 1 = UTF-16 con BOM (little endian); termina en 0x00 0x00.
    final payload = BytesBuilder()..add(const [1, 0xFF, 0xFE]);
    for (final unit in text.codeUnits) {
      payload.add([unit & 0xFF, (unit >> 8) & 0xFF]);
    }
    payload.add(const [0, 0]);
    final bytes = payload.takeBytes();
    out
      ..add(id.codeUnits)
      ..add(_bigEndian32(bytes.length)) // en v2.3 el tamaño de frame NO es syncsafe
      ..add(const [0, 0])
      ..add(bytes);
  }

  /// Entero de 28 bits repartido en 4 bytes de 7 bits (cabecera ID3v2).
  static List<int> syncSafe(int v) => [(v >> 21) & 0x7F, (v >> 14) & 0x7F, (v >> 7) & 0x7F, v & 0x7F];

  static List<int> _bigEndian32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

  /// Escribe en [output] la etiqueta seguida del contenido de [mp3].
  static Future<void> writeTagged(File mp3, File output, {String? title, String? artist}) async {
    final sink = output.openWrite();
    try {
      sink.add(build(title: title, artist: artist));
      await sink.addStream(mp3.openRead());
    } finally {
      await sink.close();
    }
  }
}
