import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../core/diag_log.dart';
import '../data/download_manager.dart';
import '../data/history.dart';
import '../data/models.dart';
import '../data/settings.dart';
import '../data/youtube_service.dart';
import '../providers.dart';
import 'equalizer.dart';
import 'loudness.dart';

/// Audio de YouTube que se resuelve solo cuando el reproductor llega a él: así una cola de 20
/// relacionados no pide 20 manifiestos de golpe y las URL no caducan esperando.
///
/// Va por el proxy local de just_audio, que pide los bytes a la librería (por bloques, con
/// renovación de URL caducadas).
// StreamAudioSource está marcado como experimental en just_audio, pero es estable en la práctica.
// ignore: experimental_member_use
class YouTubeAudioSource extends StreamAudioSource {
  YouTubeAudioSource(this.videoId, this._service, {required MediaItem tag}) : super(tag: tag);

  final String videoId;
  final YouTubeService _service;
  ({int tag, int size})? _audio;

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final audio = _audio ??= await _service.bestAudio(videoId);
    final from = start ?? 0;
    final opened = await _service.open(videoId, audio.tag, start: from);
    final total = opened.total > 0 ? opened.total : audio.size;
    final until = end ?? total;
    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: total,
      contentLength: until - from,
      offset: from,
      stream: end == null ? opened.bytes : _limit(opened.bytes, until - from),
      contentType: 'audio/mp4',
    );
  }

  static Stream<List<int>> _limit(Stream<List<int>> source, int count) async* {
    var left = count;
    await for (final chunk in source) {
      if (chunk.length >= left) {
        yield chunk.sublist(0, left);
        return;
      }
      left -= chunk.length;
      yield chunk;
    }
  }
}

/// Reproductor de audio único de la app (sigue sonando con la app minimizada o la pantalla apagada).
class AudioController {
  AudioController(
    this._service, {
    required this.localAudio,
    AndroidEqualizer? androidEqualizer,
    this.loudnessEnhancer,
  }) : player = AudioPlayer(
          // Android: el ecualizador y el refuerzo de volumen del teléfono van dentro del
          // reproductor. En iOS el ecualizador se engancha desde el plugin media_tools.
          audioPipeline: androidEqualizer == null && loudnessEnhancer == null
              ? null
              : AudioPipeline(androidAudioEffects: [
                  if (androidEqualizer != null) androidEqualizer,
                  if (loudnessEnhancer != null) loudnessEnhancer,
                ]),
        );

  final YouTubeService _service;
  final AudioPlayer player;

  /// Android: sube las canciones bajas (volumen parejo con "Subir las canciones bajas").
  final AndroidLoudnessEnhancer? loudnessEnhancer;

  /// Archivo local (descarga o mixtape) con el audio de un video, si existe.
  final Future<File?> Function(String videoId) localAudio;

  /// Portada guardada en el teléfono (funciona sin internet en la pantalla de bloqueo) o la de internet.
  static Future<Uri> _art(String videoId) async {
    final cover = await coverFileFor(videoId);
    return await cover.exists() ? Uri.file(cover.path) : Uri.parse('https://i.ytimg.com/vi/$videoId/hqdefault.jpg');
  }

  /// Portada de una descarga: la guardada en el teléfono, o la de internet (YouTube o la
  /// miniatura propia del enlace directo).
  static Future<Uri?> _artFor(DownloadTask t) async {
    final cover = await coverFileFor(t.videoId);
    if (await cover.exists()) return Uri.file(cover.path);
    if (t.isDirect) return t.thumbnail == null ? null : Uri.tryParse(t.thumbnail!);
    return Uri.parse('https://i.ytimg.com/vi/${t.videoId}/hqdefault.jpg');
  }

  static Future<MediaItem> _itemFor(VideoSummary v) async => MediaItem(
        id: 'yt:${v.id}',
        title: v.title,
        artist: v.author,
        duration: v.duration,
        artUri: await _art(v.id),
        extras: {'videoId': v.id, if (v.channelId != null) 'channelId': v.channelId},
      );

  /// Reproduce [videos] desde [startIndex]; "siguiente" avanza por la lista.
  ///
  /// Lo que ya está guardado en el teléfono (descargas o mixtape) suena desde el archivo: no gasta
  /// datos y funciona sin internet.
  Future<void> playYouTube(List<VideoSummary> videos, {int startIndex = 0, Duration? position, bool shuffle = false}) async {
    if (videos.isEmpty) return;
    final sources = <AudioSource>[];
    var start = 0;
    var startKept = false;
    for (var i = 0; i < videos.length; i++) {
      final v = videos[i];
      final local = await localAudio(v.id);
      // Un id que no es de YouTube (enlace directo, "ia:…") solo puede sonar desde su archivo.
      if (local == null && v.id.contains(':')) continue;
      if (i == startIndex) {
        start = sources.length;
        startKept = true;
      } else if (i < startIndex) {
        start = sources.length + 1; // si la elegida se omite, empieza en la siguiente que quede
      }
      final item = await _itemFor(v);
      sources.add(local != null ? AudioSource.file(local.path, tag: item) : YouTubeAudioSource(v.id, _service, tag: item));
    }
    if (sources.isEmpty) throw const AppException('Estas canciones ya no están en el teléfono y no son de YouTube.');
    await _play(sources, start.clamp(0, sources.length - 1), startKept ? position : null, shuffle: shuffle);
  }

  /// Reproduce enlaces directos (Internet Archive, un .mp3 suelto): [items] con id propio, título,
  /// autor, URL y portada opcional. No pasan por YouTube.
  Future<void> playDirect(List<({String id, String title, String author, Uri url, Uri? art})> items, {int startIndex = 0}) async {
    if (items.isEmpty) return;
    final sources = <AudioSource>[
      for (final i in items)
        AudioSource.uri(
          i.url,
          tag: MediaItem(id: 'url:${i.id}', title: i.title, artist: i.author, artUri: i.art, extras: {'directId': i.id}),
        ),
    ];
    await _play(sources, startIndex, null);
  }

  /// Reproduce archivos descargados (audio o video; de los videos solo suena el audio).
  Future<void> playFiles(List<({DownloadTask task, File file})> files, {int startIndex = 0, bool shuffle = false}) async {
    if (files.isEmpty) return;
    final sources = <AudioSource>[
      for (final f in files)
        AudioSource.file(
          f.file.path,
          tag: MediaItem(
            id: 'file:${f.task.id}',
            title: f.task.title,
            artist: f.task.author,
            artUri: await _artFor(f.task),
            extras: {
              // Los enlaces directos no son de YouTube: sin videoId (no hay "Video" ni historial).
              if (!f.task.isDirect) 'videoId': f.task.videoId,
              // Volumen guardado al descargar: el volumen parejo funciona sin internet.
              if (f.task.loudnessDb != null) 'loudnessDb': f.task.loudnessDb,
            },
          ),
        ),
    ];
    await _play(sources, startIndex, null, shuffle: shuffle);
  }

  Future<void> _play(List<AudioSource> sources, int startIndex, Duration? position, {bool shuffle = false}) async {
    try {
      await player.setAudioSources(sources, initialIndex: startIndex.clamp(0, sources.length - 1), initialPosition: position);
      if (shuffle) await player.shuffle();
      await player.setShuffleModeEnabled(shuffle);
      unawaited(player.play());
    } on PlayerInterruptedException {
      // Se pidió otra reproducción antes de que esta cargara: no es un error.
    } on PlayerException catch (e) {
      throw AppException('No se pudo reproducir: ${e.message ?? 'error del reproductor'}');
    }
  }

  Future<void> toggle() => player.playing ? player.pause() : player.play();

  Future<void> stop() async {
    await player.stop();
    await player.clearAudioSources();
  }

  Future<void> dispose() => player.dispose();
}

final audioControllerProvider = Provider<AudioController>((ref) {
  // read, no watch: si el controlador se reconstruyera, el ecualizador quedaría atado al reproductor viejo.
  final service = ref.read(youtubeServiceProvider);
  final controller = AudioController(
    service,
    localAudio: (id) => ref.read(downloadsProvider.notifier).localAudioFor(id),
    androidEqualizer: ref.read(androidEqualizerProvider),
    loudnessEnhancer: !kIsWeb && Platform.isAndroid ? AndroidLoudnessEnhancer() : null,
  );
  // Carga el ajuste guardado del ecualizador desde el principio (en iOS se aplica antes de sonar).
  ref.read(equalizerProvider);
  final history = ref.read(historyProvider.notifier);
  final player = controller.player;

  // Historial: se registra cada video de YouTube que empieza a sonar y se guarda la posición
  // cada 10 s y al pausar, para "Seguir viendo" y reanudar.
  String? currentId;
  final mixtaped = <String>{};
  ({String id, MediaItem item})? current() {
    final item = player.sequenceState.currentSource?.tag;
    if (item is! MediaItem || !item.id.startsWith('yt:')) return null;
    final id = item.extras?['videoId'] as String?;
    return id == null ? null : (id: id, item: item);
  }

  void savePosition() {
    final c = current();
    if (c != null) unawaited(history.savePosition(c.id, player.position, player.duration ?? c.item.duration));
  }

  // Volumen parejo: al cambiar de canción (o el ajuste) se ajusta el volumen según su loudnessDb.
  final loudnessCache = <String, double?>{};
  var loudnessGeneration = 0;
  Object? lastLoudnessItem;

  Future<double?> loudnessOf(MediaItem item) async {
    final stored = item.extras?['loudnessDb'];
    if (stored is num) return stored.toDouble();
    final id = item.extras?['videoId'];
    if (id is! String) return null; // enlaces directos: sin dato
    // Descarga con el dato guardado (sirve sin internet) o, si no, la respuesta de YouTube.
    final saved = ref.read(downloadsProvider).firstWhereOrNull((t) => t.videoId == id && t.loudnessDb != null)?.loudnessDb;
    if (saved != null) return saved;
    if (loudnessCache.containsKey(id)) return loudnessCache[id];
    final value = await service.loudnessDb(id);
    loudnessCache[id] = value;
    if (loudnessCache.length > 200) loudnessCache.remove(loudnessCache.keys.first);
    return value;
  }

  Future<void> applyLoudness() async {
    final generation = ++loudnessGeneration;
    final settings = ref.read(settingsProvider);
    final item = player.sequenceState.currentSource?.tag;
    final loudness = item is MediaItem && settings.loudnessMode != LoudnessMode.off ? await loudnessOf(item) : null;
    if (generation != loudnessGeneration) return; // ya cambió de canción
    try {
      await player.setVolume(playerVolumeFor(loudness, settings.loudnessMode));
      final enhancer = controller.loudnessEnhancer;
      if (enhancer != null) {
        final boost = boostDbFor(loudness, settings.loudnessMode, boostQuiet: settings.boostQuiet);
        await enhancer.setTargetGain(boost);
        await enhancer.setEnabled(boost > 0);
      }
    } catch (e) {
      DiagLog.write('volumen parejo: $e');
    }
  }

  ref.listen(settingsProvider.select((s) => (s.loudnessMode, s.boostQuiet)), (_, __) => unawaited(applyLoudness()));

  final subs = <StreamSubscription<Object?>>[
    player.sequenceStateStream.listen((state) {
      final tag = state.currentSource?.tag;
      if (!identical(tag, lastLoudnessItem)) {
        lastLoudnessItem = tag;
        unawaited(applyLoudness());
      }
    }),
    player.sequenceStateStream.listen((_) {
      final c = current();
      if (c == null || c.id == currentId) return;
      currentId = c.id;
      unawaited(history.record(VideoSummary(
        id: c.id,
        title: c.item.title,
        author: c.item.artist ?? '',
        channelId: c.item.extras?['channelId'] as String?,
        duration: c.item.duration,
      )));
    }),
    player.playingStream.listen((playing) {
      if (!playing) savePosition();
    }),
    Stream<void>.periodic(const Duration(seconds: 10)).listen((_) {
      if (!player.playing) return;
      savePosition();
      // Mixtape: lo que escuchas más de 30 s se guarda para oírlo sin internet.
      final c = current();
      if (c != null && player.position >= mixtapeAfter && mixtaped.add(c.id)) {
        unawaited(ref.read(downloadsProvider.notifier).addToMixtape(VideoSummary(
          id: c.id,
          title: c.item.title,
          author: c.item.artist ?? '',
          channelId: c.item.extras?['channelId'] as String?,
          duration: c.item.duration,
        )));
      }
    }),
  ];

  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
    controller.dispose();
  });
  return controller;
});

/// Tiempo de escucha a partir del cual una canción entra al mixtape.
const mixtapeAfter = Duration(seconds: 30);

/// Elemento que suena ahora (null si no hay nada).
final nowPlayingProvider = StreamProvider<MediaItem?>((ref) {
  final player = ref.watch(audioControllerProvider).player;
  return player.sequenceStateStream.map((s) => s.currentSource?.tag as MediaItem?);
});

final playerStateProvider = StreamProvider<PlayerState>((ref) => ref.watch(audioControllerProvider).player.playerStateStream);
