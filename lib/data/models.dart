/// Modelos de la app, independientes de youtube_explode_dart.
library;

/// Elemento de una lista de videos (búsqueda, relacionados).
class VideoSummary {
  const VideoSummary({
    required this.id,
    required this.title,
    required this.author,
    this.channelId,
    this.duration,
    this.viewCount,
    this.uploadedText,
    this.isLive = false,
  });

  final String id;
  final String title;
  final String author;
  final String? channelId;
  final Duration? duration;
  final int? viewCount;
  final String? uploadedText;
  final bool isLive;

  String get thumbnailUrl => 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
  String get watchUrl => 'https://www.youtube.com/watch?v=$id';
}

/// Información de la pantalla "ver video".
class WatchInfo {
  const WatchInfo({
    required this.video,
    required this.description,
    required this.likeCount,
    required this.related,
    required this.playableUrl,
    required this.downloadOptions,
  });

  final VideoSummary video;
  final String description;
  final int? likeCount;
  final List<VideoSummary> related;

  /// URL de un flujo con video y audio juntos (normalmente 360p) para el reproductor; null si no hay.
  final Uri? playableUrl;

  final List<DownloadOption> downloadOptions;
}

enum OutputKind {
  mp4('Video MP4', 'mp4'),
  m4a('Audio M4A (AAC)', 'm4a'),
  mp3('Audio MP3', 'mp3');

  const OutputKind(this.label, this.extension);
  final String label;
  final String extension;

  bool get isAudio => this != OutputKind.mp4;
}

/// Una opción concreta de descarga, elegida de los flujos de YouTube.
class DownloadOption {
  const DownloadOption({
    required this.kind,
    required this.label,
    required this.tag,
    required this.sizeBytes,
    this.audioTag,
    this.height,
    this.isLossy = false,
  });

  final OutputKind kind;

  /// "1080p · 120 MB" o "128 kbps · 4.1 MB".
  final String label;

  /// itag del flujo de YouTube; se vuelve a pedir al descargar porque las URL caducan.
  final int tag;

  /// Pista de audio que se une al video (MP4 en alta calidad: YouTube los entrega por separado).
  final int? audioTag;
  final int? height;
  final int sizeBytes;

  /// MP3: se recodifica el audio (con pérdida).
  final bool isLossy;

  bool get needsMerge => audioTag != null;
}

enum DownloadStatus {
  pending,
  running,

  /// Uniendo video y audio, o convirtiendo a MP3.
  processing,
  completed,
  failed,
  cancelled,
}

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.videoId,
    required this.title,
    required this.author,
    required this.kind,
    required this.tag,
    required this.fileName,
    required this.status,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.createdAt,
    this.bytesPerSecond,
    this.error,
    this.filePath,
    this.completedAt,
    this.audioTag,
    this.qualityLabel,
    this.isMixtape = false,
    this.sourceUrl,
    this.thumbnail,
    this.loudnessDb,
  });

  final int id;
  final String videoId;
  final String title;
  final String author;
  final OutputKind kind;
  final int tag;
  final String fileName;
  final DownloadStatus status;
  final int downloadedBytes;
  final int? totalBytes;
  final int? bytesPerSecond;
  final String? error;

  /// Ruta relativa a la carpeta de documentos de la app (en iOS cambia al reinstalar).
  final String? filePath;
  final int createdAt;
  final int? completedAt;

  /// Pista de audio a unir (MP4 HD) o null.
  final int? audioTag;

  /// "1080p", "192 kbps"…
  final String? qualityLabel;

  /// Guardado automáticamente para el mixtape sin conexión (no lo pidió el usuario): se puede
  /// borrar solo cuando el mixtape pasa del límite.
  final bool isMixtape;

  /// Enlace directo (Internet Archive, un .mp4/.mp3 suelto): se descarga tal cual, sin YouTube.
  /// Con esto, [videoId] es un identificador propio (p. ej. "ia:<id>/<archivo>") y [tag] = 0.
  final String? sourceUrl;

  /// Miniatura propia (enlaces directos); null = la de YouTube.
  final String? thumbnail;

  /// Volumen de la canción según YouTube (loudnessDb; positivo = más fuerte que la referencia),
  /// para el volumen parejo sin internet. Null si no se conoce.
  final double? loudnessDb;

  bool get isDirect => sourceUrl != null;

  bool get isActive => status == DownloadStatus.pending || status == DownloadStatus.running || status == DownloadStatus.processing;
  double? get progress => (totalBytes ?? 0) > 0 ? (downloadedBytes / totalBytes!).clamp(0.0, 1.0) : null;
  String get thumbnailUrl => thumbnail ?? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

  DownloadTask copyWith({
    DownloadStatus? status,
    int? downloadedBytes,
    int? totalBytes,
    int? bytesPerSecond,
    bool clearSpeed = false,
    String? error,
    bool clearError = false,
    String? filePath,
    int? completedAt,
    bool? isMixtape,
    double? loudnessDb,
  }) =>
      DownloadTask(
        id: id,
        videoId: videoId,
        title: title,
        author: author,
        kind: kind,
        tag: tag,
        fileName: fileName,
        status: status ?? this.status,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        bytesPerSecond: clearSpeed ? null : (bytesPerSecond ?? this.bytesPerSecond),
        error: clearError ? null : (error ?? this.error),
        filePath: filePath ?? this.filePath,
        createdAt: createdAt,
        completedAt: completedAt ?? this.completedAt,
        audioTag: audioTag,
        qualityLabel: qualityLabel,
        isMixtape: isMixtape ?? this.isMixtape,
        sourceUrl: sourceUrl,
        thumbnail: thumbnail,
        loudnessDb: loudnessDb ?? this.loudnessDb,
      );

  Map<String, Object?> toRow() => {
        if (id > 0) 'id': id,
        'video_id': videoId,
        'title': title,
        'author': author,
        'kind': kind.name,
        'tag': tag,
        'file_name': fileName,
        'status': status.name,
        'downloaded_bytes': downloadedBytes,
        'total_bytes': totalBytes,
        'error': error,
        'file_path': filePath,
        'created_at': createdAt,
        'completed_at': completedAt,
        'audio_tag': audioTag,
        'quality_label': qualityLabel,
        'auto_mixtape': isMixtape ? 1 : 0,
        'source_url': sourceUrl,
        'thumbnail': thumbnail,
        'loudness_db': loudnessDb,
      };

  static DownloadTask fromRow(Map<String, Object?> r) => DownloadTask(
        id: r['id']! as int,
        videoId: r['video_id']! as String,
        title: r['title']! as String,
        author: (r['author'] as String?) ?? '',
        kind: OutputKind.values.firstWhere((k) => k.name == r['kind'], orElse: () => OutputKind.mp4),
        tag: r['tag']! as int,
        fileName: r['file_name']! as String,
        status: DownloadStatus.values.firstWhere((s) => s.name == r['status'], orElse: () => DownloadStatus.failed),
        downloadedBytes: (r['downloaded_bytes'] as int?) ?? 0,
        totalBytes: r['total_bytes'] as int?,
        error: r['error'] as String?,
        filePath: r['file_path'] as String?,
        createdAt: r['created_at']! as int,
        completedAt: r['completed_at'] as int?,
        audioTag: r['audio_tag'] as int?,
        qualityLabel: r['quality_label'] as String?,
        isMixtape: (r['auto_mixtape'] as int?) == 1,
        sourceUrl: r['source_url'] as String?,
        thumbnail: r['thumbnail'] as String?,
        loudnessDb: (r['loudness_db'] as num?)?.toDouble(),
      );
}

/// Lo visto en streaming (se guarda solo en el teléfono).
class WatchHistoryEntry {
  const WatchHistoryEntry({
    required this.videoId,
    required this.title,
    required this.author,
    required this.watchedAt,
    this.channelId,
    this.duration,
    this.position = Duration.zero,
  });

  final String videoId;
  final String title;
  final String author;
  final String? channelId;
  final Duration? duration;
  final Duration position;
  final int watchedAt;

  String get thumbnailUrl => 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

  /// 0..1 para la barra roja de "Seguir viendo".
  double? get progress {
    final d = duration;
    if (d == null || d.inMilliseconds <= 0) return null;
    return (position.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Vale la pena ofrecer "reanudar": más de 10 s vistos y sin terminar.
  bool get isResumable => position > const Duration(seconds: 10);

  VideoSummary toSummary() => VideoSummary(id: videoId, title: title, author: author, channelId: channelId, duration: duration);

  Map<String, Object?> toRow() => {
        'video_id': videoId,
        'title': title,
        'author': author,
        'channel_id': channelId,
        'duration_ms': duration?.inMilliseconds,
        'position_ms': position.inMilliseconds,
        'watched_at': watchedAt,
      };

  static WatchHistoryEntry fromRow(Map<String, Object?> r) => WatchHistoryEntry(
        videoId: r['video_id']! as String,
        title: r['title']! as String,
        author: (r['author'] as String?) ?? '',
        channelId: r['channel_id'] as String?,
        duration: (r['duration_ms'] as int?) == null ? null : Duration(milliseconds: r['duration_ms']! as int),
        position: Duration(milliseconds: (r['position_ms'] as int?) ?? 0),
        watchedAt: r['watched_at']! as int,
      );
}

/// Carpeta de la biblioteca: agrupación dentro de la app (los archivos no se mueven en el teléfono).
class LibraryFolder {
  const LibraryFolder({required this.id, required this.name});
  final int id;
  final String name;

  static LibraryFolder fromRow(Map<String, Object?> r) => LibraryFolder(id: r['id']! as int, name: r['name']! as String);
}

/// Resultado de búsqueda de una lista de reproducción.
class PlaylistSummary {
  const PlaylistSummary({required this.id, required this.title, this.author, this.videoCount, this.thumbnailUrl});
  final String id;
  final String title;
  final String? author;
  final int? videoCount;
  final String? thumbnailUrl;
  String get url => 'https://www.youtube.com/playlist?list=$id';
}

/// Resultado de búsqueda de un canal.
class ChannelSummary {
  const ChannelSummary({required this.id, required this.name, this.avatarUrl, this.videoCount, this.description});
  final String id;
  final String name;
  final String? avatarUrl;
  final int? videoCount;
  final String? description;
}

/// Cabecera de un canal.
class ChannelInfo {
  const ChannelInfo({required this.id, required this.name, this.avatarUrl, this.bannerUrl, this.subscribers});
  final String id;
  final String name;
  final String? avatarUrl;
  final String? bannerUrl;
  final int? subscribers;
}

/// Cabecera de una lista de reproducción.
class PlaylistInfo {
  const PlaylistInfo({required this.id, required this.title, required this.author, this.description, this.videoCount});
  final String id;
  final String title;
  final String author;
  final String? description;
  final int? videoCount;
}
