/// Reconoce enlaces de YouTube pegados o compartidos.
///
/// Acepta youtube.com (también m. y music.), youtu.be, /watch?v=, /shorts/, /live/, /embed/,
/// /playlist?list=, /channel/UC… y /@handle. Solo http(s) o sin esquema; los ids se validan.
library;

const _idPattern = r'^[A-Za-z0-9_-]{11}$';

Uri? _youtubeUri(String input) {
  final text = input.trim();
  if (text.isEmpty || text.contains(' ')) return null;
  final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return null;
  final host = uri.host.toLowerCase();
  final isYouTube = host == 'youtu.be' || host == 'youtube.com' || host.endsWith('.youtube.com');
  return isYouTube ? uri : null;
}

/// Id del video, o null.
String? videoIdFromInput(String input) {
  final uri = _youtubeUri(input);
  if (uri == null) return null;
  String? candidate;
  final segs = uri.pathSegments;
  if (uri.host.toLowerCase() == 'youtu.be') {
    candidate = segs.isNotEmpty ? segs.first : null;
  } else if (segs.isNotEmpty && segs.first == 'watch') {
    candidate = uri.queryParameters['v'];
  } else if (segs.length >= 2 && const {'shorts', 'live', 'embed', 'v'}.contains(segs.first)) {
    candidate = segs[1];
  }
  return candidate != null && RegExp(_idPattern).hasMatch(candidate) ? candidate : null;
}

/// Id de una lista (youtube.com/playlist?list=…), o null. Un watch?v=…&list=… abre el video.
String? playlistIdFromInput(String input) {
  final uri = _youtubeUri(input);
  if (uri == null || uri.pathSegments.isEmpty || uri.pathSegments.first != 'playlist') return null;
  final list = uri.queryParameters['list'];
  return list != null && RegExp(r'^[A-Za-z0-9_-]{10,64}$').hasMatch(list) ? list : null;
}

/// Canal: id "UC…" (youtube.com/channel/UC…) o handle sin @ (youtube.com/@nombre).
({String? id, String? handle})? channelFromInput(String input) {
  final uri = _youtubeUri(input);
  if (uri == null || uri.pathSegments.isEmpty) return null;
  final segs = uri.pathSegments;
  if (segs.first == 'channel' && segs.length >= 2 && RegExp(r'^UC[A-Za-z0-9_-]{22}$').hasMatch(segs[1])) {
    return (id: segs[1], handle: null);
  }
  if (segs.first.startsWith('@') && RegExp(r'^@[A-Za-z0-9._-]{3,30}$').hasMatch(segs.first)) {
    return (id: null, handle: segs.first.substring(1));
  }
  return null;
}

/// ¿Parece un enlace (en vez de una búsqueda)?
bool looksLikeUrl(String input) {
  final t = input.trim();
  if (t.contains(' ')) return false;
  return t.contains('://') || RegExp(r'^[\w.-]+\.[a-z]{2,}(/.*)?$', caseSensitive: false).hasMatch(t);
}
