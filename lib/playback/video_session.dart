import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../data/download_manager.dart';
import '../data/history.dart';
import '../data/models.dart';
import '../data/settings.dart';
import '../data/youtube_service.dart';
import '../providers.dart';
import 'audio_controller.dart';
import 'pip.dart';

/// Máximo de videos que se ponen en cola al pasar a "Canción".
const maxUpNext = 20;

/// El video que se está viendo. Vive fuera de la pantalla: al minimizarla sigue sonando en el
/// mini reproductor (como YouTube) y al volver se retoma sin recargar.
@immutable
class VideoSession {
  const VideoSession({
    required this.videoId,
    required this.autoplay,
    this.queue,
    this.info,
    this.error,
    this.controller,
    this.videoFailed = false,
    this.resumedAt,
    this.url,
  });

  final String videoId;

  /// Lista explícita (una lista de reproducción o la cola de audio); null = relacionados.
  final List<VideoSummary>? queue;
  final WatchInfo? info;
  final String? error;
  final VideoPlayerController? controller;

  /// URL que reproduce [controller] (para pasar el video al reproductor nativo de imagen en imagen).
  final Uri? url;
  final bool videoFailed;
  final bool autoplay;

  /// Si se retomó donde te quedaste, desde qué punto (para avisar).
  final Duration? resumedAt;

  bool get isPlaylist => queue != null;
  List<VideoSummary> get upNext => queue ?? info?.related ?? const [];
  bool get isReady => controller?.value.isInitialized ?? false;

  /// Título y autor aunque la información completa no haya llegado.
  VideoSummary? get video => info?.video;

  VideoSession copyWith({
    WatchInfo? info,
    String? error,
    VideoPlayerController? controller,
    bool? videoFailed,
    bool? autoplay,
    Duration? resumedAt,
    Uri? url,
  }) =>
      VideoSession(
        videoId: videoId,
        queue: queue,
        info: info ?? this.info,
        error: error ?? this.error,
        controller: controller ?? this.controller,
        videoFailed: videoFailed ?? this.videoFailed,
        autoplay: autoplay ?? this.autoplay,
        resumedAt: resumedAt ?? this.resumedAt,
        url: url ?? this.url,
      );
}

class VideoSessionNotifier extends Notifier<VideoSession?> {
  /// Cada carga nueva sube el número; las cargas viejas que terminan tarde se descartan.
  int _generation = 0;
  Timer? _timer;
  bool _advanced = false;
  bool _mixtaped = false;

  @override
  VideoSession? build() {
    // Si empieza a sonar audio (mixtape, biblioteca, "Canción"), el video se cierra: no se
    // oyen dos cosas a la vez ni quedan dos mini reproductores.
    final sub = ref.read(audioControllerProvider).player.playingStream.listen((playing) {
      if (playing && state != null) close();
    });
    ref.onDispose(() {
      sub.cancel();
      _timer?.cancel();
      state?.controller?.dispose();
    });
    return null;
  }

  /// Abre [videoId]. Si ya es el que se está viendo (p. ej. al tocar el mini reproductor) no se
  /// recarga.
  Future<void> load(String videoId, {List<VideoSummary>? queue, Duration? startAt, bool force = false}) async {
    final current = state;
    if (!force && current != null && current.videoId == videoId && current.error == null && queue == null && startAt == null) {
      return;
    }
    final generation = ++_generation;
    _release();
    _advanced = false;
    _mixtaped = false;
    final settings = ref.read(settingsProvider);
    state = VideoSession(videoId: videoId, queue: queue, autoplay: current?.autoplay ?? settings.autoplayNext);

    final yt = ref.read(youtubeServiceProvider);
    final WatchInfo info;
    try {
      info = await yt.watch(videoId, maxHeight: settings.maxVideoHeight, mp3Kbps: settings.mp3BitrateKbps);
    } catch (e) {
      if (generation == _generation) state = state?.copyWith(error: e is AppException ? e.message : '$e');
      return;
    }
    if (generation != _generation || state == null) return;
    state = state!.copyWith(info: info);
    unawaited(ref.read(historyProvider.notifier).record(info.video));

    // Busca una URL que YouTube sí entregue (visionOS primero; HLS con buena calidad).
    final url = await yt.playableUrl(videoId);
    if (generation != _generation || state == null) return;
    if (url == null) {
      state = state!.copyWith(videoFailed: true);
      return;
    }
    // Mismo User-Agent que el cliente que generó la URL; si no, YouTube responde 403.
    final c = VideoPlayerController.networkUrl(url, httpHeaders: YouTubeService.playbackHeaders(url));
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      if (generation == _generation) state = state?.copyWith(videoFailed: true);
      return;
    }
    if (generation != _generation || state == null) {
      await c.dispose();
      return;
    }

    // Si sonaba música, se pausa.
    await ref.read(audioControllerProvider).player.pause();
    var start = startAt;
    Duration? resumed;
    if (start == null) {
      final saved = await ref.read(historyProvider.notifier).entry(videoId);
      if (saved != null && saved.isResumable) start = resumed = saved.position;
    }
    if (generation != _generation || state == null) {
      await c.dispose();
      return;
    }
    if (start != null) await c.seekTo(start);
    c.addListener(_onVideoTick);
    state = state!.copyWith(controller: c, resumedAt: resumed, url: url);
    await c.play();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _periodic());
  }

  Future<void> retry() async {
    final s = state;
    if (s != null) await load(s.videoId, queue: s.queue, force: true);
  }

  /// Pasa al video [index] de "A continuación".
  Future<void> playNext(int index) async {
    final s = state;
    if (s == null) return;
    final next = s.upNext;
    if (index < 0 || index >= next.length) return;
    await load(next[index].id, queue: s.isPlaylist ? next.sublist(index + 1) : null);
  }

  void setAutoplay(bool on) => state = state?.copyWith(autoplay: on);

  /// Cambia a "Canción": sigue con el audio desde el mismo punto, con "A continuación" en la cola.
  Future<void> toSong() async {
    final s = state;
    final video = s?.video;
    if (s == null || video == null) return;
    final position = s.controller?.value.position;
    final items = [video, ...s.upNext.take(maxUpNext)];
    close();
    await ref.read(audioControllerProvider).playYouTube(items, position: position);
  }

  /// Imagen en imagen. Devuelve un mensaje si no se pudo (null si todo bien).
  ///
  /// - iOS: el video pasa al reproductor nativo de iOS (que es el que sabe hacer imagen en imagen)
  ///   en el mismo segundo; al cerrarlo, sigue aquí donde quedó.
  /// - Android: la app entera se encoge a una ventanita (la pantalla muestra solo el video).
  Future<String?> pictureInPicture() async {
    final s = state;
    final c = s?.controller;
    final url = s?.url;
    if (s == null || c == null || url == null || !c.value.isInitialized) return 'Espera a que cargue el video.';
    if (!await Pip.isSupported()) return 'Este teléfono no admite imagen en imagen.';
    if (Pip.usesNativePlayer) {
      final position = c.value.position;
      await c.pause();
      final back = await Pip.presentNative(
        url: url,
        headers: YouTubeService.playbackHeaders(url),
        position: position,
        title: s.video?.title ?? '',
      );
      // Si mientras tanto se abrió otro video, no se toca.
      if (state?.controller != c) return null;
      if (back != null) await c.seekTo(back);
      await c.play();
      return null;
    }
    return await Pip.enter() ? null : 'No se pudo abrir la ventanita de imagen en imagen.';
  }

  /// Cierra el video (botón X del mini reproductor).
  void close() {
    _generation++;
    _release();
    state = null;
  }

  void _savePosition() {
    final s = state;
    final v = s?.controller?.value;
    if (s == null || v == null || !v.isInitialized) return;
    unawaited(ref.read(historyProvider.notifier).savePosition(s.videoId, v.position, v.duration));
  }

  /// Cada 10 s: guarda la posición y, pasados 30 s, guarda la canción en el mixtape.
  void _periodic() {
    final s = state;
    final v = s?.controller?.value;
    if (s == null || v == null || !v.isPlaying) return;
    _savePosition();
    final video = s.video;
    if (!_mixtaped && video != null && v.position >= mixtapeAfter) {
      _mixtaped = true;
      unawaited(ref.read(downloadsProvider.notifier).addToMixtape(video));
    }
  }

  /// Último valor enviado a Android para entrar solo a imagen en imagen al salir de la app.
  bool _autoPip = false;

  void _setAutoPip(bool on) {
    if (on == _autoPip) return;
    _autoPip = on;
    unawaited(Pip.setAutoEnter(on));
  }

  /// Al terminar, pasa al siguiente (aunque la pantalla esté minimizada).
  void _onVideoTick() {
    final s = state;
    final c = s?.controller;
    // Android 12+: si sales de la app con el video sonando, entra solo a imagen en imagen.
    if (c != null) _setAutoPip(c.value.isPlaying);
    if (s == null || c == null || _advanced || !s.autoplay || s.upNext.isEmpty) return;
    final v = c.value;
    if (v.isInitialized && !v.isPlaying && v.duration > Duration.zero && v.position >= v.duration - const Duration(milliseconds: 300)) {
      _advanced = true;
      unawaited(playNext(0));
    }
  }

  /// Suelta el controlador actual. Se libera un poco después para que la pantalla deje de
  /// dibujarlo antes (usar un controlador liberado es un error).
  void _release() {
    _timer?.cancel();
    _timer = null;
    _savePosition();
    _setAutoPip(false);
    final old = state?.controller;
    if (old == null) return;
    old.removeListener(_onVideoTick);
    unawaited(old.pause());
    Future<void>.delayed(const Duration(seconds: 1), old.dispose);
  }
}

final videoSessionProvider = NotifierProvider<VideoSessionNotifier, VideoSession?>(VideoSessionNotifier.new);
