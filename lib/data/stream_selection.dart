import '../core/format.dart';
import 'models.dart';

/// Vista mínima de un flujo de YouTube, para elegir calidad sin depender de la librería (y probarlo).
class StreamCandidate {
  const StreamCandidate({
    required this.tag,
    required this.container,
    required this.hasVideo,
    required this.hasAudio,
    required this.bitrate,
    required this.sizeBytes,
    this.height,
    this.qualityLabel = '',
    this.videoCodec = '',
    this.audioCodec = '',
  });

  final int tag;

  /// "mp4", "webm"…
  final String container;
  final bool hasVideo;
  final bool hasAudio;

  /// bits por segundo
  final int bitrate;
  final int sizeBytes;
  final int? height;
  final String qualityLabel;
  final String videoCodec;
  final String audioCodec;

  bool get isMuxed => hasVideo && hasAudio;
  bool get isAudioOnly => hasAudio && !hasVideo;
  bool get isVideoOnly => hasVideo && !hasAudio;

  /// H.264: lo único que Android (MediaMuxer) e iPhone (AVFoundation) unen y reproducen en todos los equipos.
  bool get isH264 => videoCodec.toLowerCase().startsWith('avc1');
}

/// Límite de las calidades que se ofrecen para unir: por encima YouTube ya no da H.264.
const maxMergeHeight = 1080;

/// Mejor flujo con video y audio juntos para reproducir (MP4, la mayor altura disponible).
StreamCandidate? pickPlayableMuxed(List<StreamCandidate> streams) {
  final muxed = streams.where((s) => s.isMuxed && s.container == 'mp4').toList()
    ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
  return muxed.isEmpty ? null : muxed.first;
}

/// Mejor audio para escuchar o descargar: AAC en contenedor MP4, mayor bitrate.
StreamCandidate? pickBestAudio(List<StreamCandidate> streams) {
  final audio = streams.where((s) => s.isAudioOnly && s.container == 'mp4').toList()
    ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
  return audio.isEmpty ? null : audio.first;
}

String _sizeLabel(int bytes) => bytes > 0 ? formatBytes(bytes) : '';

/// Opciones de descarga, de mayor a menor calidad:
///
/// - **MP4**: video H.264 sin audio (hasta [maxHeight] o 1080p) + el mejor AAC, unidos sin
///   recodificar. Si YouTube trae video+audio juntos en una altura (360p), se usa ese.
/// - **M4A**: el mejor AAC tal cual (sin pérdida).
/// - **MP3**: ese mismo AAC convertido con LAME a [mp3Kbps] (con pérdida).
List<DownloadOption> buildDownloadOptions(List<StreamCandidate> streams, {int? maxHeight, int mp3Kbps = 192}) {
  final limit = maxHeight == null ? maxMergeHeight : (maxHeight < maxMergeHeight ? maxHeight : maxMergeHeight);
  final audio = pickBestAudio(streams);
  final byHeight = <int, DownloadOption>{};

  // Video + audio juntos (no hay que unir nada).
  for (final s in streams.where((s) => s.isMuxed && s.container == 'mp4')) {
    final h = s.height ?? 0;
    if (h > limit) continue;
    final current = byHeight[h];
    if (current != null && current.sizeBytes >= s.sizeBytes) continue;
    byHeight[h] = DownloadOption(
      kind: OutputKind.mp4,
      label: [s.qualityLabel.isNotEmpty ? s.qualityLabel : '${h}p', _sizeLabel(s.sizeBytes)].where((x) => x.isNotEmpty).join(' · '),
      tag: s.tag,
      sizeBytes: s.sizeBytes,
      height: h,
    );
  }

  // Video H.264 sin audio + mejor AAC.
  if (audio != null) {
    final videos = streams.where((s) => s.isVideoOnly && s.container == 'mp4' && s.isH264 && (s.height ?? 0) <= limit).toList()
      ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    for (final v in videos) {
      final h = v.height ?? 0;
      if (byHeight.containsKey(h)) continue; // ya hay una opción para esa altura (muxed o de más bitrate)
      final size = v.sizeBytes > 0 && audio.sizeBytes > 0 ? v.sizeBytes + audio.sizeBytes : 0;
      byHeight[h] = DownloadOption(
        kind: OutputKind.mp4,
        label: [v.qualityLabel.isNotEmpty ? v.qualityLabel : '${h}p', _sizeLabel(size)].where((x) => x.isNotEmpty).join(' · '),
        tag: v.tag,
        audioTag: audio.tag,
        sizeBytes: size,
        height: h,
      );
    }
  }

  final options = byHeight.values.toList()..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));

  if (audio != null) {
    final kbps = (audio.bitrate / 1000).round();
    options.add(DownloadOption(
      kind: OutputKind.m4a,
      label: ['$kbps kbps', _sizeLabel(audio.sizeBytes)].where((x) => x.isNotEmpty).join(' · '),
      tag: audio.tag,
      sizeBytes: audio.sizeBytes,
    ));
    // Tamaño aproximado del MP3: duración (de tamaño/bitrate del AAC) × bitrate del MP3.
    final seconds = audio.bitrate > 0 ? audio.sizeBytes * 8 / audio.bitrate : 0;
    final mp3Size = (seconds * mp3Kbps * 1000 / 8).round();
    options.add(DownloadOption(
      kind: OutputKind.mp3,
      label: ['$mp3Kbps kbps', if (mp3Size > 0) '≈ ${formatBytes(mp3Size)}', 'convertido'].join(' · '),
      tag: audio.tag,
      sizeBytes: audio.sizeBytes,
      isLossy: true,
    ));
  }
  return options;
}
