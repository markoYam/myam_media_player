/// Enlaces directos a un archivo de audio o video (un .mp3 o .mp4 suelto en cualquier sitio).
library;

import 'package:http/http.dart' as http;

import 'archive_client.dart' show extensionOf;
import 'models.dart';

enum DirectMediaKind { audio, video }

const _audioExt = {'mp3', 'm4a', 'aac'};
const _videoExt = {'mp4', 'm4v', 'mov'};

/// Primera URL http(s) dentro de un texto ("Mira esto https://… 🔥"). Quita la puntuación final
/// que suele pegarse al compartir (punto, coma, paréntesis, comillas).
String? firstUrl(String text) {
  final m = RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false).firstMatch(text);
  if (m == null) return null;
  var url = m.group(0)!;
  while (url.isNotEmpty && '.,;:!?)]}»”’'.contains(url[url.length - 1])) {
    url = url.substring(0, url.length - 1);
  }
  return url.isEmpty ? null : url;
}

/// Tipo por la extensión del camino (sin contar la consulta: "a.mp3?x=1" es audio).
DirectMediaKind? directKindFromUrl(Uri uri) {
  final ext = extensionOf(uri.path);
  if (_audioExt.contains(ext)) return DirectMediaKind.audio;
  if (_videoExt.contains(ext)) return DirectMediaKind.video;
  return null;
}

/// Tipo por el Content-Type de la respuesta ("audio/mpeg; charset=…").
DirectMediaKind? directKindFromContentType(String? contentType) {
  final ct = (contentType ?? '').toLowerCase().trim();
  if (ct.startsWith('audio/')) return DirectMediaKind.audio;
  if (ct.startsWith('video/')) return DirectMediaKind.video;
  return null;
}

/// Formato en el que se guarda al descargar, según la extensión; null si no se puede guardar con
/// un formato que la app maneje (p. ej. FLAC u OGG: solo se reproducen).
OutputKind? outputKindForExtension(String ext) => switch (ext.toLowerCase()) {
      'mp3' => OutputKind.mp3,
      'm4a' => OutputKind.m4a,
      'mp4' || 'm4v' => OutputKind.mp4,
      _ => null,
    };

/// Formato de descarga para un enlace sin extensión conocida (por Content-Type).
OutputKind? outputKindForContentType(String? contentType) {
  final ct = (contentType ?? '').toLowerCase();
  if (ct.startsWith('audio/mpeg') || ct.startsWith('audio/mp3')) return OutputKind.mp3;
  if (ct.startsWith('audio/mp4') || ct.startsWith('audio/x-m4a') || ct.startsWith('audio/m4a')) return OutputKind.m4a;
  if (ct.startsWith('video/mp4') || ct.startsWith('video/x-m4v')) return OutputKind.mp4;
  return null;
}

/// Huella estable de un texto (FNV-1a de 32 bits dos veces, 16 hex): la misma URL da siempre el
/// mismo id, así no se descarga dos veces.
String stableHash(String text) {
  String fnv(int seed) {
    var h = seed;
    for (final unit in text.codeUnits) {
      h ^= unit;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  return fnv(0x811C9DC5) + fnv(0x01000193 ^ 0x5BD1E995);
}

/// Título a partir de la URL: el nombre del archivo sin extensión ("Mi canción" de
/// ".../Mi%20canci%C3%B3n.mp3"); si no hay, el dominio.
String titleFromUrl(Uri uri) {
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty) return uri.host;
  var name = segs.last;
  try {
    name = Uri.decodeComponent(name);
  } catch (_) {}
  final dot = name.lastIndexOf('.');
  if (dot > 0) name = name.substring(0, dot);
  name = name.replaceAll('_', ' ').trim();
  return name.isEmpty ? uri.host : name;
}

/// Resultado de revisar un enlace en la red.
typedef DirectProbe = ({DirectMediaKind kind, String? contentType, int? sizeBytes});

/// Pregunta al servidor qué es el enlace (HEAD; si no lo admite, GET del primer byte).
/// Null si no es audio ni video o no responde.
Future<DirectProbe?> probeDirectLink(Uri uri, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final head = await c.send(http.Request('HEAD', uri)).timeout(const Duration(seconds: 10));
    await head.stream.drain<void>();
    http.BaseResponse response = head;
    if (response.statusCode == 405 || response.statusCode == 403 || response.statusCode >= 500) {
      final get = http.Request('GET', uri)..headers['Range'] = 'bytes=0-0';
      final streamed = await c.send(get).timeout(const Duration(seconds: 10));
      await streamed.stream.drain<void>();
      response = streamed;
    }
    if (response.statusCode >= 400) return null;
    final ct = response.headers['content-type'];
    final kind = directKindFromContentType(ct);
    if (kind == null) return null;
    int? size;
    final range = response.headers['content-range']; // "bytes 0-0/12345"
    if (range != null && range.contains('/')) size = int.tryParse(range.split('/').last);
    size ??= response.statusCode == 200 ? response.contentLength : null;
    return (kind: kind, contentType: ct, sizeBytes: size);
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}
