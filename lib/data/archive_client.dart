/// Internet Archive (archive.org): leer un item con su API pública de metadatos y quedarse con los
/// archivos que el teléfono puede reproducir.
///
/// API: https://archive.org/metadata/<id> → {metadata: {...}, files: [...]}. Cada archivo se baja de
/// https://archive.org/download/<id>/<nombre>.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'youtube_service.dart' show AppException;

enum ArchiveKind { audio, video }

class ArchiveFile {
  const ArchiveFile({
    required this.name,
    required this.title,
    required this.kind,
    required this.format,
    required this.url,
    this.sizeBytes,
    this.duration,
    this.track,
  });

  /// Nombre en el item (puede tener subcarpetas: "disco 1/01 canción.mp3").
  final String name;
  final String title;
  final ArchiveKind kind;

  /// Formato según archive.org ("VBR MP3", "h.264"…).
  final String format;
  final Uri url;
  final int? sizeBytes;
  final Duration? duration;
  final int? track;

  /// Extensión en minúsculas, sin punto ("mp3").
  String get extension => extensionOf(name);
}

class ArchiveItem {
  const ArchiveItem({required this.id, required this.title, required this.creator, required this.files});

  final String id;
  final String title;
  final String creator;
  final List<ArchiveFile> files;

  Uri get thumbnail => Uri.parse('https://archive.org/services/img/${Uri.encodeComponent(id)}');
  List<ArchiveFile> get audio => files.where((f) => f.kind == ArchiveKind.audio).toList();
  List<ArchiveFile> get video => files.where((f) => f.kind == ArchiveKind.video).toList();
}

/// Id de un enlace de archive.org: /details/<id>, /download/<id>/…, /embed/<id>. Null si no es.
String? archiveIdFromUrl(String input) {
  final text = input.trim();
  if (text.isEmpty || text.contains(' ')) return null;
  final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return null;
  final host = uri.host.toLowerCase();
  if (host != 'archive.org' && host != 'www.archive.org' && host != 'm.archive.org') return null;
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.length < 2 || !const {'details', 'download', 'embed'}.contains(segs.first)) return null;
  final id = segs[1];
  // Los ids de archive.org son letras, números, punto, guion y guion bajo.
  return RegExp(r'^[A-Za-z0-9._-]{1,100}$').hasMatch(id) ? id : null;
}

/// "mp3" de "carpeta/01 Canción.MP3"; "" si no tiene.
String extensionOf(String name) {
  final base = name.split('/').last;
  final dot = base.lastIndexOf('.');
  return dot <= 0 || dot == base.length - 1 ? '' : base.substring(dot + 1).toLowerCase();
}

const _audioExt = {'mp3', 'm4a', 'aac', 'flac', 'ogg', 'opus'};
const _videoExt = {'mp4', 'm4v', 'mov'};

/// Preferencia entre copias del mismo archivo (archive.org guarda el original y derivados):
/// menor = mejor. MP3 primero (funciona en todos lados y se descarga tal cual).
int _rank(String ext, String format) {
  final f = format.toLowerCase();
  switch (ext) {
    case 'mp3':
      return f.contains('vbr') ? 0 : 1;
    case 'm4a':
      return 2;
    case 'aac':
      return 3;
    case 'flac':
      return 4;
    case 'ogg':
    case 'opus':
      return 5;
    case 'mp4':
      return f.contains('h.264') ? 0 : 1;
    case 'm4v':
      return 2;
    case 'mov':
      return 3;
  }
  return 9;
}

/// Raíz del nombre para reconocer copias: "01 Canción" de "01 Canción_vbr.mp3" o "x.ia.mp4".
String _stem(String name) {
  var s = name.toLowerCase();
  final dot = s.lastIndexOf('.');
  if (dot > 0) s = s.substring(0, dot);
  return s.replaceAll(RegExp(r'(\.ia|_512kb|_64kb|_128kb|_vbr|_sample)$'), '');
}

Duration? _parseLength(Object? raw) {
  if (raw == null) return null;
  final text = '$raw'.trim();
  final seconds = double.tryParse(text);
  if (seconds != null) return seconds > 0 ? Duration(milliseconds: (seconds * 1000).round()) : null;
  // "3:35" o "1:02:05"
  final parts = text.split(':').map(int.tryParse).toList();
  if (parts.isEmpty || parts.length > 3 || parts.any((p) => p == null)) return null;
  var total = 0;
  for (final p in parts) {
    total = total * 60 + p!;
  }
  return total > 0 ? Duration(seconds: total) : null;
}

String _text(Object? v) {
  if (v is List) return v.isEmpty ? '' : '${v.first}'.trim();
  return v == null ? '' : '$v'.trim();
}

/// URL de descarga de un archivo; cada parte del nombre se codifica (espacios, acentos, #).
Uri archiveFileUrl(String id, String name) =>
    Uri.parse('https://archive.org/download/${Uri.encodeComponent(id)}/${name.split('/').map(Uri.encodeComponent).join('/')}');

/// Título legible: el del archivo, o su nombre sin extensión ni guiones bajos.
String _fileTitle(Map<dynamic, dynamic> f, String name) {
  final t = _text(f['title']);
  if (t.isNotEmpty) return t;
  var base = name.split('/').last;
  final dot = base.lastIndexOf('.');
  if (dot > 0) base = base.substring(0, dot);
  return base.replaceAll('_', ' ').trim();
}

/// Lee la respuesta de /metadata/<id>. [allowOgg]: OGG/Opus solo se reproducen en Android.
/// Lanza [FormatException] si el item no existe o no trae datos.
ArchiveItem parseArchiveMetadata(Map<dynamic, dynamic> json, {required String id, bool allowOgg = false}) {
  final meta = json['metadata'];
  final files = json['files'];
  if (meta is! Map || files is! List) throw const FormatException('El item no existe o no tiene archivos');
  final itemId = _text(meta['identifier']).isNotEmpty ? _text(meta['identifier']) : id;

  // Mejor copia de cada archivo.
  final best = <String, ({ArchiveFile file, int rank})>{};
  for (final f in files) {
    if (f is! Map) continue;
    final name = _text(f['name']);
    if (name.isEmpty) continue;
    final ext = extensionOf(name);
    final ArchiveKind kind;
    if (_audioExt.contains(ext)) {
      if ((ext == 'ogg' || ext == 'opus') && !allowOgg) continue;
      kind = ArchiveKind.audio;
    } else if (_videoExt.contains(ext)) {
      kind = ArchiveKind.video;
    } else {
      continue;
    }
    final format = _text(f['format']);
    if (format.toLowerCase().contains('ogg video')) continue;
    final file = ArchiveFile(
      name: name,
      title: _fileTitle(f, name),
      kind: kind,
      format: format.isEmpty ? ext.toUpperCase() : format,
      url: archiveFileUrl(itemId, name),
      sizeBytes: int.tryParse(_text(f['size'])),
      duration: _parseLength(f['length']),
      track: int.tryParse(_text(f['track']).split('/').first),
    );
    final key = '${kind.name}:${_stem(name)}';
    final rank = _rank(ext, format);
    final current = best[key];
    final better = current == null ||
        rank < current.rank ||
        (rank == current.rank && kind == ArchiveKind.video && (file.sizeBytes ?? 0) > (current.file.sizeBytes ?? 0));
    if (better) best[key] = (file: file, rank: rank);
  }

  final list = best.values.map((e) => e.file).toList()
    ..sort((a, b) {
      final ta = a.track, tb = b.track;
      if (ta != null && tb != null && ta != tb) return ta.compareTo(tb);
      if (ta != null && tb == null) return -1;
      if (ta == null && tb != null) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  final title = _text(meta['title']);
  return ArchiveItem(id: itemId, title: title.isEmpty ? itemId : title, creator: _text(meta['creator']), files: list);
}

/// Baja y lee un item. Errores en español como [AppException].
Future<ArchiveItem> fetchArchiveItem(String id, {bool allowOgg = false, http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final response = await c.get(Uri.parse('https://archive.org/metadata/${Uri.encodeComponent(id)}')).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw AppException('No se pudo abrir ese enlace de Internet Archive (HTTP ${response.statusCode}).');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map) throw const AppException('No se pudo abrir ese enlace de Internet Archive.');
    final item = parseArchiveMetadata(json, id: id, allowOgg: allowOgg);
    if (item.files.isEmpty) throw const AppException('Ese item de Internet Archive no tiene audio ni video que se pueda reproducir.');
    return item;
  } on AppException {
    rethrow;
  } on FormatException {
    throw const AppException('Ese item de Internet Archive no existe o no tiene archivos.');
  } catch (_) {
    throw const AppException('No se pudo abrir ese enlace de Internet Archive. Revisa tu conexión.');
  } finally {
    if (client == null) c.close();
  }
}
