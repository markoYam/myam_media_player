import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../data/download_manager.dart';
import '../../data/models.dart';
import '../../data/settings.dart';
import '../../data/youtube_service.dart';
import '../../playback/video_session.dart';
import '../player/player_screen.dart';
import '../browse/channel_playlist_screens.dart';
import '../playlists/add_to_playlist.dart';

/// Abre "ver video". Con [upNext] (una lista de reproducción o la cola de audio), "A continuación"
/// sigue esa lista en vez de los relacionados. [startAt] empieza en ese punto (al pasar de
/// "Canción" a "Video").
void openWatch(BuildContext context, String videoId, {bool replace = false, List<VideoSummary>? upNext, Duration? startAt}) {
  final container = ProviderScope.containerOf(context, listen: false);
  unawaited(container.read(videoSessionProvider.notifier).load(videoId, queue: upNext, startAt: startAt));
  final route = watchRoute();
  if (replace) {
    Navigator.of(context).pushReplacement(route);
  } else {
    Navigator.of(context).push(route);
  }
}

/// Pantalla del video que ya se está viendo (al tocar el mini reproductor).
Route<void> watchRoute() => MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const WatchScreen());

/// Selector "Canción | Video" (como YouTube Music).
class SongVideoToggle extends StatelessWidget {
  const SongVideoToggle({super.key, required this.isVideo, required this.onChanged});
  final bool isVideo;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(value: false, label: Text('Canción'), icon: Icon(Icons.music_note, size: 18)),
        ButtonSegment(value: true, label: Text('Video'), icon: Icon(Icons.videocam_outlined, size: 18)),
      ],
      selected: {isVideo},
      onSelectionChanged: onChanged == null ? null : (v) => onChanged!(v.first),
    );
  }
}

class WatchScreen extends ConsumerWidget {
  const WatchScreen({super.key});

  /// Pasa a "Canción": el audio sigue desde el mismo punto en el reproductor de música.
  static Future<void> switchToSong(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(videoSessionProvider.notifier);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const PlayerScreen()),
    );
    try {
      await notifier.toSong();
    } on AppException catch (e) {
      if (context.mounted) showMessage(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(videoSessionProvider);
    ref.listen(videoSessionProvider.select((s) => (s?.videoId, s?.resumedAt)), (prev, next) {
      final at = next.$2;
      if (at != null && prev != next) showMessage(context, 'Continuando donde te quedaste (${formatDuration(at)}).');
    });
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Minimizar',
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: SongVideoToggle(
          isVideo: true,
          onChanged: s?.video == null
              ? null
              : (video) {
                  if (!video) unawaited(switchToSong(context, ref));
                },
        ),
      ),
      body: switch (s) {
        null => const Center(child: CircularProgressIndicator()),
        VideoSession(error: final String error) =>
          ErrorView(message: error, onRetry: ref.read(videoSessionProvider.notifier).retry),
        VideoSession(info: null) => const Center(child: CircularProgressIndicator()),
        final VideoSession session => _WatchBody(key: ValueKey(session.videoId), session: session),
      },
    );
  }
}

class _WatchBody extends ConsumerStatefulWidget {
  const _WatchBody({super.key, required this.session});
  final VideoSession session;

  @override
  ConsumerState<_WatchBody> createState() => _WatchBodyState();
}

class _WatchBodyState extends ConsumerState<_WatchBody> {
  bool _showDescription = false;

  VideoSession get s => widget.session;
  WatchInfo get info => s.info!;
  VideoSessionNotifier get _session => ref.read(videoSessionProvider.notifier);

  void _openDownloads() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _DownloadSheet(
        options: info.downloadOptions,
        preferred: ref.read(settingsProvider).preferredOutput,
        onPick: (option) async {
          Navigator.of(sheetContext).pop();
          try {
            await ref.read(downloadsProvider.notifier).enqueue(info.video, option);
            if (mounted) showMessage(context, 'Descarga agregada. Mírala en la pestaña Descargas.');
          } on AppException catch (e) {
            if (mounted) showMessage(context, e.message);
          }
        },
      ),
    );
  }

  Future<void> _pictureInPicture() async {
    final problem = await _session.pictureInPicture();
    if (problem != null && mounted) showMessage(context, problem);
  }

  Future<void> _fullscreen() async {
    final c = s.controller;
    if (c == null || !c.value.isInitialized) return;
    await Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (_, __, ___) => FullscreenVideo(controller: c),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final v = info.video;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final next = s.upNext;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // Deslizar el video hacia abajo lo minimiza (como YouTube).
        GestureDetector(
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 500) Navigator.of(context).pop();
          },
          child: _player(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(v.title, style: text.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            [
              videoMeta(views: v.viewCount, uploaded: v.uploadedText),
              if ((info.likeCount ?? 0) > 0) '${compactCount(info.likeCount!)} me gusta',
            ].where((s) => s.isNotEmpty).join(' · '),
            style: text.bodySmall?.copyWith(color: muted),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: () => WatchScreen.switchToSong(context, ref),
                icon: const Icon(Icons.headphones),
                label: const Text('Escuchar'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: info.downloadOptions.isEmpty ? null : _openDownloads,
                icon: const Icon(Icons.download),
                label: const Text('Descargar'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => showAddToPlaylistSheet(context, ref, [v]),
                icon: const Icon(Icons.playlist_add),
                label: const Text('Guardar'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => SharePlus.instance.share(ShareParams(text: v.watchUrl)),
                icon: const Icon(Icons.share),
                label: const Text('Compartir'),
              ),
            ],
          ),
        ),
        ListTile(
          leading: CircleAvatar(child: Text(v.author.isEmpty ? '?' : v.author.characters.first.toUpperCase())),
          title: Text(v.author),
          trailing: v.channelId == null ? null : const Icon(Icons.chevron_right),
          onTap: v.channelId == null ? null : () => openChannel(context, v.channelId!),
        ),
        if (info.description.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card.filled(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _showDescription = !_showDescription),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    info.description,
                    maxLines: _showDescription ? null : 3,
                    overflow: _showDescription ? null : TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        if (next.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
            child: Row(
              children: [
                Expanded(child: Text(s.isPlaylist ? 'Sigue en la lista' : 'A continuación', style: text.titleMedium)),
                const Text('Automático'),
                Switch(value: s.autoplay, onChanged: _session.setAutoplay),
              ],
            ),
          ),
          for (var i = 0; i < next.length; i++)
            CompactRow(
              thumbnailUrl: next[i].thumbnailUrl,
              title: next[i].title,
              subtitle: [next[i].author, videoMeta(views: next[i].viewCount, uploaded: next[i].uploadedText)]
                  .where((s) => s.isNotEmpty)
                  .join('\n'),
              duration: next[i].duration,
              onTap: () => _session.playNext(i),
            ),
        ],
      ],
    );
  }

  Widget _player() {
    final c = s.controller;
    Widget content;
    if (s.videoFailed) {
      content = Stack(
        fit: StackFit.expand,
        children: [
          VideoThumb(url: info.video.thumbnailUrl, radius: 0),
          ColoredBox(
            color: Colors.black54,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Este video no se puede ver aquí. Cambia a "Canción" o descárgalo.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      );
    } else if (c == null || !c.value.isInitialized) {
      content = const ColoredBox(color: Colors.black, child: Center(child: CircularProgressIndicator()));
    } else {
      content = VideoSurface(controller: c, onFullscreen: _fullscreen, onPictureInPicture: _pictureInPicture);
    }
    return AspectRatio(aspectRatio: 16 / 9, child: content);
  }
}

/// Mini reproductor del video minimizado: se ve el video, pausa y cerrar; tocarlo lo agranda.
class VideoMiniPlayer extends ConsumerWidget {
  const VideoMiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(videoSessionProvider);
    if (s == null) return const SizedBox.shrink();
    final c = s.isReady ? s.controller : null;
    final video = s.video;
    return Theme(
      data: darkAppTheme,
      child: Builder(builder: (context) {
        final text = Theme.of(context).textTheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
        onTap: () => Navigator.of(context).push(watchRoute()),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c != null)
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: c,
                builder: (_, v, __) => LinearProgressIndicator(
                  minHeight: 2,
                  color: Colors.white,
                  backgroundColor: Colors.white24,
                  value: v.duration.inMilliseconds > 0 ? (v.position.inMilliseconds / v.duration.inMilliseconds).clamp(0.0, 1.0) : 0,
                ),
              )
            else
              const LinearProgressIndicator(minHeight: 2),
            SizedBox(
              height: miniPlayerHeight(context) + 4,
              child: Row(
                children: [
                  SizedBox(
                    width: 64 * 16 / 9,
                    child: ColoredBox(
                      color: Colors.black,
                      child: c != null
                          ? Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)))
                          : VideoThumb(url: 'https://i.ytimg.com/vi/${s.videoId}/hqdefault.jpg', radius: 0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(video?.title ?? 'Cargando…', maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                        if (video != null)
                          Text(video.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
                      ],
                    ),
                  ),
                  if (c != null)
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: c,
                      builder: (_, v, __) => IconButton(
                        tooltip: v.isPlaying ? 'Pausar' : 'Reproducir',
                        icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow),
                        onPressed: () => v.isPlaying ? c.pause() : c.play(),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Cerrar video',
                    icon: const Icon(Icons.close),
                    onPressed: ref.read(videoSessionProvider.notifier).close,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
          ),
        );
      }),
    );
  }
}

/// Video con controles simples: tocar para pausar/reanudar, barra arrastrable, pantalla completa.
class VideoSurface extends StatelessWidget {
  const VideoSurface({super.key, required this.controller, this.onFullscreen, this.onPictureInPicture, this.isFullscreen = false});
  final VideoPlayerController controller;
  final VoidCallback? onFullscreen;

  /// Botón de imagen en imagen (sigue viéndose en una ventanita fuera de la app).
  final VoidCallback? onPictureInPicture;
  final bool isFullscreen;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(child: AspectRatio(aspectRatio: controller.value.aspectRatio, child: VideoPlayer(controller))),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => controller.value.isPlaying ? controller.pause() : controller.play(),
              onDoubleTapDown: (d) {
                // Doble toque: ±10 s según el lado (como YouTube).
                final width = context.size?.width ?? 1;
                final delta = d.localPosition.dx < width / 2 ? -10 : 10;
                controller.seekTo(controller.value.position + Duration(seconds: delta));
              },
              onDoubleTap: () {},
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (_, value, __) => AnimatedOpacity(
                  opacity: value.isPlaying ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: const Center(
                    child: CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.black54,
                      child: Icon(Icons.play_arrow, color: Colors.white, size: 36),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Row(
              children: [
                const SizedBox(width: 8),
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: controller,
                  builder: (_, v, __) => Text(
                    '${formatDuration(v.position)} / ${formatDuration(v.duration)}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                    colors: const VideoProgressColors(playedColor: Colors.red, bufferedColor: Colors.white38),
                  ),
                ),
                if (onPictureInPicture != null)
                  IconButton(
                    tooltip: 'Imagen en imagen',
                    color: Colors.white,
                    icon: const Icon(Icons.picture_in_picture_alt_rounded),
                    onPressed: onPictureInPicture,
                  ),
                if (onFullscreen != null)
                  IconButton(
                    tooltip: isFullscreen ? 'Salir de pantalla completa' : 'Pantalla completa',
                    color: Colors.white,
                    icon: Icon(isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
                    onPressed: onFullscreen,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Orientación de la app fuera de la pantalla completa: vertical.
const appOrientations = [DeviceOrientation.portraitUp];

/// Pantalla completa en horizontal con el mismo controlador (no se corta la reproducción).
class FullscreenVideo extends StatefulWidget {
  const FullscreenVideo({super.key, required this.controller});
  final VideoPlayerController controller;

  @override
  State<FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<FullscreenVideo> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Volver a vertical. Permitir "todas" no basta: iOS se queda en horizontal hasta que giras
    // el teléfono; hay que pedir vertical explícitamente.
    SystemChrome.setPreferredOrientations(appOrientations);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: VideoSurface(controller: widget.controller, isFullscreen: true, onFullscreen: () => Navigator.of(context).pop()),
    );
  }
}

class _DownloadSheet extends StatelessWidget {
  const _DownloadSheet({required this.options, required this.preferred, required this.onPick});

  final List<DownloadOption> options;
  final OutputKind preferred;
  final ValueChanged<DownloadOption> onPick;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // El formato preferido (Ajustes) va primero.
    final kinds = [preferred, ...OutputKind.values.where((k) => k != preferred)];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 8), child: Text('Descargar', style: text.titleLarge)),
            for (final kind in kinds) ...[
              if (options.any((o) => o.kind == kind))
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Text(kind.label, style: text.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
                ),
              for (final o in options.where((o) => o.kind == kind))
                ListTile(
                  leading: Icon(switch (o.kind) {
                    OutputKind.mp4 => Icons.movie_outlined,
                    OutputKind.m4a => Icons.music_note_outlined,
                    OutputKind.mp3 => Icons.audio_file_outlined,
                  }),
                  title: Text(o.label),
                  subtitle: Text(switch (o.kind) {
                    OutputKind.mp4 => o.needsMerge ? 'Video y audio se unen sin perder calidad' : 'Video con audio',
                    OutputKind.m4a => 'Audio original, sin pérdida',
                    OutputKind.mp3 => 'Compatible con todo; se recodifica (con pérdida)',
                  }),
                  onTap: () => onPick(o),
                ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
