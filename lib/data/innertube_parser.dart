import '../core/format.dart';
import 'models.dart';

/// Lector tolerante de respuestas de la API interna de YouTube (InnerTube): recorre todo el JSON
/// y saca los videos de cualquiera de los formatos que YouTube ha usado para listas:
///
/// - `playlistVideoRenderer` (página de la lista)
/// - `playlistPanelVideoRenderer` (panel de la lista en "ver video")
/// - `videoRenderer`
/// - `lockupViewModel` (formato nuevo de 2024-2026)
///
/// No descarta videos sin canal (la librería sí lo hace, y por eso algunas listas salían vacías).
class InnerTubeParser {
  InnerTubeParser._();

  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final _durationPattern = RegExp(r'^\d{1,2}(:\d{2}){1,2}$');

  static List<VideoSummary> videos(Object? json) {
    final out = <VideoSummary>[];
    final seen = <String>{};
    void add(VideoSummary? v) {
      if (v != null && seen.add(v.id)) out.add(v);
    }

    void walk(Object? node) {
      if (node is Map) {
        for (final entry in node.entries) {
          final value = entry.value;
          switch (entry.key) {
            case 'playlistVideoRenderer' || 'playlistPanelVideoRenderer' || 'videoRenderer' || 'compactVideoRenderer':
              if (value is Map) add(_fromRenderer(value));
            case 'lockupViewModel':
              if (value is Map) add(_fromLockup(value));
            default:
              walk(value);
          }
        }
      } else if (node is List) {
        for (final item in node) {
          walk(item);
        }
      }
    }

    walk(json);
    return out;
  }

  /// Primer token de continuación (siguiente página), o null.
  static String? continuation(Object? json) {
    if (json is Map) {
      final command = json['continuationCommand'];
      if (command is Map && command['token'] is String) return command['token'] as String;
      final next = json['nextContinuationData'];
      if (next is Map && next['continuation'] is String) return next['continuation'] as String;
      for (final value in json.values) {
        final found = continuation(value);
        if (found != null) return found;
      }
    } else if (json is List) {
      for (final item in json) {
        final found = continuation(item);
        if (found != null) return found;
      }
    }
    return null;
  }

  static VideoSummary? _fromRenderer(Map<dynamic, dynamic> r) {
    final id = r['videoId'];
    if (id is! String || !_idPattern.hasMatch(id)) return null;
    final byline = r['shortBylineText'] ?? r['ownerText'] ?? r['longBylineText'];
    final seconds = int.tryParse('${r['lengthSeconds'] ?? ''}');
    return VideoSummary(
      id: id,
      title: text(r['title']) ?? '',
      author: text(byline) ?? '',
      channelId: _browseId(byline),
      duration: seconds != null ? Duration(seconds: seconds) : parseClock(text(r['lengthText'])),
      viewCount: _digits(text(r['viewCountText'])),
      uploadedText: text(r['publishedTimeText']),
    );
  }

  static VideoSummary? _fromLockup(Map<dynamic, dynamic> l) {
    final id = l['contentId'];
    final type = '${l['contentType'] ?? ''}';
    if (id is! String || !_idPattern.hasMatch(id) || (type.isNotEmpty && !type.contains('VIDEO'))) return null;
    final meta = _path(l, ['metadata', 'lockupMetadataViewModel']);
    final rows = _path(meta, ['metadata', 'contentMetadataViewModel', 'metadataRows']);
    String? author;
    if (rows is List && rows.isNotEmpty) {
      final parts = _path(rows.first, ['metadataParts']);
      if (parts is List && parts.isNotEmpty) author = text(_path(parts.first, ['text']));
    }
    return VideoSummary(
      id: id,
      title: text(_path(meta, ['title'])) ?? '',
      author: author ?? '',
      duration: _firstClock(l['contentImage']),
    );
  }

  /// Texto de un nodo de YouTube: `simpleText`, `runs` o `content`.
  static String? text(Object? node) {
    if (node is String) return node;
    if (node is! Map) return null;
    if (node['simpleText'] is String) return node['simpleText'] as String;
    if (node['content'] is String) return node['content'] as String;
    final runs = node['runs'];
    if (runs is List) {
      final s = runs.map((r) => r is Map ? '${r['text'] ?? ''}' : '').join();
      return s.isEmpty ? null : s;
    }
    return null;
  }

  /// "3:45" o "1:02:03" → Duration.
  static Duration? parseClock(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (!_durationPattern.hasMatch(t)) return null;
    var seconds = 0;
    for (final part in t.split(':')) {
      seconds = seconds * 60 + int.parse(part);
    }
    return Duration(seconds: seconds);
  }

  static Duration? _firstClock(Object? node) {
    if (node is Map) {
      for (final v in node.values) {
        if (v is String) {
          final d = parseClock(v);
          if (d != null) return d;
        } else {
          final d = _firstClock(v);
          if (d != null) return d;
        }
      }
    } else if (node is List) {
      for (final v in node) {
        final d = _firstClock(v);
        if (d != null) return d;
      }
    }
    return null;
  }

  static String? _browseId(Object? byline) {
    final runs = byline is Map ? byline['runs'] : null;
    if (runs is! List || runs.isEmpty) return null;
    final id = _path(runs.first, ['navigationEndpoint', 'browseEndpoint', 'browseId']);
    return id is String && id.startsWith('UC') ? id : null;
  }

  static int? _digits(String? s) {
    if (s == null) return null;
    final d = s.replaceAll(RegExp(r'[^0-9]'), '');
    return d.isEmpty ? null : int.tryParse(d);
  }

  static Object? _path(Object? node, List<String> keys) {
    var current = node;
    for (final k in keys) {
      if (current is! Map) return null;
      current = current[k];
    }
    return current;
  }

  /// Para mensajes de depuración: cuántos videos y de qué formato.
  static String describe(List<VideoSummary> items) => '${items.length} videos'
      '${items.isEmpty ? '' : ' (primero: "${items.first.title}", ${items.first.duration == null ? 's/d' : formatDuration(items.first.duration!)})'}';
}
