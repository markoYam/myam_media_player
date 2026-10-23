import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../../core/art_colors.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../playback/audio_controller.dart';
import '../../playback/video_session.dart';
import '../watch/watch_screen.dart';
import '../playlists/add_to_playlist.dart';
import 'equalizer_screen.dart';

/// Tag del Hero de la portada: vuela del mini reproductor al reproductor completo.
const _artHero = 'now-playing-art';

/// Alto del mini reproductor: 60 o lo que pidan dos líneas de texto con la letra del sistema.
double miniPlayerHeight(BuildContext context) {
  final needed = MediaQuery.textScalerOf(context).scale(38) + 16;
  return needed > 60 ? needed : 60;
}

/// Fondo cuando la portada aún no da color.
const _defaultTone = Color(0xFF2A2A33);

/// Tono oscuro de la portada de [item] (o el gris por defecto).
Color _toneOf(WidgetRef ref, MediaItem? item) {
  final uri = item?.artUri;
  if (uri == null) return _defaultTone;
  return ref.watch(artToneProvider(uri.toString())).value ?? _defaultTone;
}

/// Mini reproductor flotante sobre la navegación (estilo Spotify): teñido con el color de la
/// portada, portada, título, pausa, siguiente y cerrar; la línea de progreso va abajo.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Un video minimizado ocupa el lugar del mini reproductor de música.
    if (ref.watch(videoSessionProvider.select((s) => s != null))) return const VideoMiniPlayer();
    final item = ref.watch(nowPlayingProvider).value;
    if (item == null) return const SizedBox.shrink();
    final controller = ref.read(audioControllerProvider);
    final playing = ref.watch(playerStateProvider).value?.playing ?? false;
    final tone = _toneOf(ref, item);

    return Theme(
      data: darkAppTheme,
      child: Builder(builder: (context) {
        final text = Theme.of(context).textTheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(10)),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const PlayerScreen()),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      // Crece con la letra grande (Dynamic Type) para que título y artista quepan.
                      height: miniPlayerHeight(context),
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          Hero(tag: _artHero, child: _Art(item: item, size: 44, radius: 6)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                                if (item.artist != null)
                                  Text(
                                    item.artist!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: playing ? 'Pausar' : 'Reproducir',
                            icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 30),
                            onPressed: controller.toggle,
                          ),
                          IconButton(
                            tooltip: 'Siguiente',
                            icon: const Icon(Icons.skip_next_rounded),
                            onPressed: controller.player.hasNext ? controller.player.seekToNext : null,
                          ),
                          IconButton(tooltip: 'Detener', icon: const Icon(Icons.close_rounded), onPressed: controller.stop),
                        ],
                      ),
                    ),
                    StreamBuilder<Duration>(
                      stream: controller.player.positionStream,
                      builder: (_, snap) {
                        final total = controller.player.duration ?? Duration.zero;
                        final pos = snap.data ?? Duration.zero;
                        final value = total.inMilliseconds > 0 ? (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0) : 0.0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: 2,
                            color: Colors.white,
                            backgroundColor: Colors.white24,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _Art extends StatelessWidget {
  const _Art({required this.item, required this.size, this.radius});
  final MediaItem item;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final uri = item.artUri;
    final placeholder = ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest, child: const Icon(Icons.music_note_rounded));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? size / 6),
      child: SizedBox(
        width: size,
        height: size,
        child: uri == null
            ? placeholder
            : uri.isScheme('file')
                // Portada guardada en el teléfono (funciona sin internet).
                ? Image.file(File(uri.toFilePath()), fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder)
                : CachedNetworkImage(imageUrl: uri.toString(), fit: BoxFit.cover, errorWidget: (_, __, ___) => placeholder),
      ),
    );
  }
}

/// Reproductor de música a pantalla completa (estilo YouTube Music / Spotify): fondo degradado
/// con el color de la portada, portada grande, título a la izquierda, barra fina y botón de
/// reproducir grande. Siempre oscuro, como esas apps.
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(nowPlayingProvider).value;
    final controller = ref.read(audioControllerProvider);
    final player = controller.player;
    final state = ref.watch(playerStateProvider).value;
    final tone = _toneOf(ref, item);
    final dark = darkAppTheme;
    final bottom = dark.colorScheme.surface;
    const muted = Color(0xCCFFFFFF); // blanco al 80 %: contraste ≥ 4.5:1 sobre el tono

    return Theme(
      data: dark,
      child: Builder(builder: (context) {
        final text = Theme.of(context).textTheme;
        return Scaffold(
          backgroundColor: bottom,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            leading: IconButton(
              tooltip: 'Cerrar',
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
              onPressed: () => Navigator.of(context).pop(),
            ),
            centerTitle: true,
            actions: [
              if (item?.extras?['videoId'] case final String videoId when !videoId.contains(':'))
                IconButton(
                  tooltip: 'Agregar a una lista',
                  icon: const Icon(Icons.playlist_add_rounded),
                  onPressed: () => showAddToPlaylistSheet(context, ref, [
                    VideoSummary(
                      id: videoId,
                      title: item?.title ?? '',
                      author: item?.artist ?? '',
                      channelId: item?.extras?['channelId'] as String?,
                      duration: item?.duration,
                    ),
                  ]),
                ),
              IconButton(
                tooltip: 'Ecualizador',
                icon: const Icon(Icons.equalizer_rounded),
                onPressed: () => Navigator.of(context).push(EqualizerScreen.route()),
              ),
            ],
            title: SongVideoToggle(
              isVideo: false,
              onChanged: item?.extras?['videoId'] == null
                  ? null
                  : (video) {
                      if (video) unawaited(switchToVideo(context, ref));
                    },
            ),
          ),
          body: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 450),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [tone, Color.lerp(tone, bottom, 0.6)!, bottom],
                stops: const [0, 0.55, 1],
              ),
            ),
            child: item == null
                ? const Center(child: Text('No hay nada en reproducción.'))
                : SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      // La portada ocupa lo que sobra: ancho completo en teléfonos altos, más chica
                      // en pantallas bajas o con letra grande (nunca desborda).
                      child: LayoutBuilder(builder: (context, box) => Column(
                        children: [
                          const Spacer(),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 32, offset: Offset(0, 16))],
                            ),
                            child: Hero(
                              tag: _artHero,
                              child: _Art(
                                item: item,
                                size: [box.maxWidth, box.maxHeight - MediaQuery.textScalerOf(context).scale(330), 380.0]
                                    .reduce((a, b) => a < b ? a : b)
                                    .clamp(96.0, 380.0),
                                radius: 12,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleLarge),
                                    if (item.artist != null) ...[
                                      const SizedBox(height: 4),
                                      Text(item.artist!, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyLarge?.copyWith(color: muted)),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _SeekBar(player: player),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              StreamBuilder<bool>(
                                stream: player.shuffleModeEnabledStream,
                                builder: (_, s) {
                                  final on = s.data ?? false;
                                  return IconButton(
                                    tooltip: on ? 'Aleatorio activado' : 'Aleatorio',
                                    isSelected: on,
                                    color: muted,
                                    selectedIcon: Icon(Icons.shuffle_on_rounded, color: Theme.of(context).colorScheme.primary),
                                    icon: const Icon(Icons.shuffle_rounded),
                                    onPressed: () async {
                                      if (!on) await player.shuffle();
                                      await player.setShuffleModeEnabled(!on);
                                    },
                                  );
                                },
                              ),
                              IconButton(
                                tooltip: 'Anterior',
                                iconSize: 44,
                                icon: const Icon(Icons.skip_previous_rounded),
                                onPressed: () => player.position > const Duration(seconds: 3) || !player.hasPrevious
                                    ? player.seek(Duration.zero)
                                    : player.seekToPrevious(),
                              ),
                              _PlayButton(playing: state?.playing ?? false, loading: _isLoading(state), onPressed: controller.toggle),
                              IconButton(
                                tooltip: 'Siguiente',
                                iconSize: 44,
                                icon: const Icon(Icons.skip_next_rounded),
                                onPressed: player.hasNext ? player.seekToNext : null,
                              ),
                              StreamBuilder<LoopMode>(
                                stream: player.loopModeStream,
                                builder: (_, s) {
                                  final mode = s.data ?? LoopMode.off;
                                  final accent = Theme.of(context).colorScheme.primary;
                                  return IconButton(
                                    tooltip: switch (mode) { LoopMode.off => 'Repetir', LoopMode.all => 'Repitiendo todo', LoopMode.one => 'Repitiendo una' },
                                    color: muted,
                                    // La forma del ícono cambia con el modo: no depende solo del color.
                                    icon: switch (mode) {
                                      LoopMode.off => const Icon(Icons.repeat_rounded),
                                      LoopMode.all => Icon(Icons.repeat_on_rounded, color: accent),
                                      LoopMode.one => Icon(Icons.repeat_one_on_rounded, color: accent),
                                    },
                                    onPressed: () => player.setLoopMode(switch (mode) {
                                      LoopMode.off => LoopMode.all,
                                      LoopMode.all => LoopMode.one,
                                      LoopMode.one => LoopMode.off,
                                    }),
                                  );
                                },
                              ),
                            ],
                          ),
                          const Spacer(),
                          TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(48, 48)),
                            onPressed: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              showDragHandle: true,
                              builder: (_) => QueueSheet(player: player),
                            ),
                            icon: const Icon(Icons.queue_music_rounded),
                            label: const Text('A continuación'),
                          ),
                          const SizedBox(height: 8),
                        ],
                      )),
                    ),
                  ),
          ),
        );
      }),
    );
  }

  /// Pasa a "Video": abre el video de la canción actual en el mismo punto; lo que seguía en la
  /// cola pasa a "Sigue en la lista".
  static Future<void> switchToVideo(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(audioControllerProvider);
    final player = controller.player;
    final seq = player.sequenceState;
    final current = seq.currentSource?.tag;
    final videoId = current is MediaItem ? (current.extras?['videoId'] as String?) : null;
    if (videoId == null) return;
    final position = player.position;
    final order = seq.shuffleModeEnabled ? seq.shuffleIndices : List<int>.generate(seq.sequence.length, (i) => i);
    final at = order.indexOf(seq.currentIndex ?? 0);
    final rest = <VideoSummary>[
      for (final i in order.skip(at + 1))
        if (seq.sequence[i].tag case final MediaItem m when m.extras?['videoId'] is String)
          VideoSummary(
            id: m.extras!['videoId'] as String,
            title: m.title,
            author: m.artist ?? '',
            channelId: m.extras?['channelId'] as String?,
            duration: m.duration,
          ),
    ].take(maxUpNext).toList();
    await controller.stop();
    if (!context.mounted) return;
    openWatch(context, videoId, replace: true, upNext: rest.isEmpty ? null : rest, startAt: position);
    if (rest.isEmpty) return;
    showMessage(context, 'Lo que seguía en la cola está en "Sigue en la lista".');
  }

  static bool _isLoading(PlayerState? s) =>
      s != null && (s.processingState == ProcessingState.loading || s.processingState == ProcessingState.buffering);
}

/// Cola de reproducción: tocar salta a esa canción, arrastrar reordena, deslizar quita.
/// En modo aleatorio se muestra el orden aleatorio y no se puede reordenar.
class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key, required this.player});
  final AudioPlayer player;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.7;
    return SizedBox(
      height: height,
      child: StreamBuilder<SequenceState>(
        stream: player.sequenceStateStream,
        initialData: player.sequenceState,
        builder: (context, snap) {
          final state = snap.data;
          if (state == null || state.sequence.isEmpty) {
            return const Center(child: Text('La cola está vacía.'));
          }
          final shuffled = state.shuffleModeEnabled;
          final order = shuffled ? state.shuffleIndices : List<int>.generate(state.sequence.length, (i) => i);
          final current = state.currentIndex;
          final text = Theme.of(context).textTheme;

          Widget tile(int position) {
            final index = order[position];
            final item = state.sequence[index].tag as MediaItem;
            final playing = index == current;
            return Dismissible(
              key: ValueKey('q-${item.id}-$index'),
              direction: playing ? DismissDirection.none : DismissDirection.endToStart,
              background: Container(
                color: Theme.of(context).colorScheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                child: const Icon(Icons.delete_outline),
              ),
              onDismissed: (_) => player.removeAudioSourceAt(index),
              child: ListTile(
                leading: _Art(item: item, size: 44),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: playing ? TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold) : null,
                ),
                subtitle: item.artist == null ? null : Text(item.artist!, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: playing
                    ? const Icon(Icons.graphic_eq)
                    : shuffled
                        ? null
                        : ReorderableDragStartListener(index: position, child: const Icon(Icons.drag_handle)),
                onTap: () => player.seek(Duration.zero, index: index),
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Row(
                  children: [
                    Expanded(child: Text('Cola · ${state.sequence.length}', style: text.titleLarge)),
                    if (shuffled) Text('Aleatorio', style: text.labelMedium),
                  ],
                ),
              ),
              Expanded(
                child: shuffled
                    ? ListView.builder(itemCount: order.length, itemBuilder: (_, i) => tile(i))
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: order.length,
                        onReorder: (from, to) => player.moveAudioSource(from, to > from ? to - 1 : to),
                        itemBuilder: (_, i) => tile(i),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Botón circular grande blanco (como Spotify / YouTube Music).
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.loading, required this.onPressed});
  final bool playing;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: playing ? 'Pausar' : 'Reproducir',
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 72,
            height: 72,
            child: Center(
              child: loading
                  ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black))
                  : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 44, color: Colors.black),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.player});
  final AudioPlayer player;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.player.positionStream,
      builder: (context, snap) {
        final total = widget.player.duration ?? Duration.zero;
        final pos = snap.data ?? Duration.zero;
        final max = total.inMilliseconds.toDouble();
        final value = (_dragging ?? pos.inMilliseconds.toDouble()).clamp(0.0, max > 0 ? max : 1.0);
        final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xCCFFFFFF));
        return Column(
          children: [
            // Barra fina blanca; el punto crece al arrastrar.
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayColor: Colors.white24,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: _dragging == null ? 6 : 9),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                trackShape: const RoundedRectSliderTrackShape(),
              ),
              child: Slider(
                max: max > 0 ? max : 1,
                value: value,
                onChanged: max > 0 ? (v) => setState(() => _dragging = v) : null,
                onChangeEnd: (v) {
                  widget.player.seek(Duration(milliseconds: v.round()));
                  setState(() => _dragging = null);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatDuration(Duration(milliseconds: value.round())), style: small),
                  Text(formatDuration(total), style: small),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
