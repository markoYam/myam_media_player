import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/art_colors.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../data/download_manager.dart';
import '../../data/models.dart';
import '../../data/playlists.dart';
import '../../data/youtube_service.dart';
import '../../playback/audio_controller.dart';
import '../../providers.dart';
import '../player/player_screen.dart';
import '../watch/watch_screen.dart';
import 'add_to_playlist.dart';

/// Ruta de la pantalla de una lista.
Route<void> playlistRoute(int playlistId) =>
    MaterialPageRoute<void>(builder: (_) => MyPlaylistScreen(playlistId: playlistId));

/// Portada de un video para usar sin internet: la guardada al descargar o la de YouTube.
/// Los ids que no son de YouTube (enlaces directos) sin portada guardada no tienen imagen ('').
final _coverUriProvider = FutureProvider.family<String, String>((ref, videoId) async {
  final file = await coverFileFor(videoId);
  if (await file.exists()) return Uri.file(file.path).toString();
  return videoId.contains(':') ? '' : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
});

/// Portada cuadrada de un video (recortada al centro, como un álbum).
class _SquareCover extends ConsumerWidget {
  const _SquareCover({required this.videoId});
  final String videoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uri = ref.watch(_coverUriProvider(videoId)).value;
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.music_note_rounded)),
    );
    if (uri == null || uri.isEmpty) return placeholder;
    final parsed = Uri.parse(uri);
    if (parsed.isScheme('file')) {
      return Image.file(File(parsed.toFilePath()), fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder);
    }
    return CachedNetworkImage(imageUrl: uri, fit: BoxFit.cover, placeholder: (_, __) => placeholder, errorWidget: (_, __, ___) => placeholder);
  }
}

/// Portada de una lista: mosaico 2×2 con las primeras portadas (1 = completa; 0 = nota sobre
/// degradado). Funciona sin internet con las portadas guardadas.
class PlaylistCover extends StatelessWidget {
  const PlaylistCover({super.key, required this.playlist, required this.size, this.radius = 6});
  final Playlist playlist;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ids = playlist.coverVideoIds;
    final scheme = Theme.of(context).colorScheme;
    Widget content;
    if (ids.isEmpty) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary, scheme.tertiary],
          ),
        ),
        child: Center(child: Icon(Icons.queue_music_rounded, size: size * 0.45, color: scheme.onPrimary)),
      );
    } else if (ids.length < 4) {
      content = _SquareCover(videoId: ids.first);
    } else {
      content = Column(
        children: [
          for (final row in [ids.sublist(0, 2), ids.sublist(2, 4)])
            Expanded(
              child: Row(children: [for (final id in row) Expanded(child: SizedBox.expand(child: _SquareCover(videoId: id)))]),
            ),
        ],
      );
    }
    return Semantics(
      label: 'Portada de ${playlist.name}',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(width: size, height: size, child: content),
      ),
    );
  }
}

/// Lista de reproducción (estilo Spotify): cabecera con el color de la portada, botón grande de
/// reproducir, aleatorio, descargar todo; canciones que se reordenan arrastrando y se quitan
/// deslizando.
class MyPlaylistScreen extends ConsumerWidget {
  const MyPlaylistScreen({super.key, required this.playlistId});
  final int playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Theme(data: darkAppTheme, child: _PlaylistBody(playlistId: playlistId));
  }
}

class _PlaylistBody extends ConsumerStatefulWidget {
  const _PlaylistBody({required this.playlistId});
  final int playlistId;

  @override
  ConsumerState<_PlaylistBody> createState() => _PlaylistBodyState();
}

class _PlaylistBodyState extends ConsumerState<_PlaylistBody> {
  /// Orden mostrado mientras se guarda un cambio (para que no "salte" al soltar).
  List<PlaylistItem>? _pending;
  bool _downloading = false;

  int get _id => widget.playlistId;

  Playlist? _playlist(List<Playlist> all) => all.where((p) => p.id == _id).firstOrNull;

  Future<void> _play(List<PlaylistItem> items, {int index = 0, bool shuffle = false}) async {
    if (items.isEmpty) return;
    try {
      await ref.read(audioControllerProvider).playYouTube([for (final i in items) i.video], startIndex: index, shuffle: shuffle);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const PlayerScreen()));
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  /// Encola el mejor audio de lo que aún no está descargado (para escuchar sin internet).
  Future<void> _downloadAll(List<PlaylistItem> items) async {
    final downloads = ref.read(downloadsProvider);
    final todo = [
      for (final i in items)
        if (!i.video.id.contains(':') &&
            !downloads.any((t) => t.videoId == i.video.id && (t.isActive || (t.status == DownloadStatus.completed && t.kind.isAudio))))
          i.video,
    ];
    if (todo.isEmpty) {
      showMessage(context, 'Ya tienes todas para escuchar sin conexión.');
      return;
    }
    setState(() => _downloading = true);
    showMessage(context, 'Descargando ${todo.length} ${todo.length == 1 ? 'canción' : 'canciones'}… Míralas en Descargas.');
    var failed = 0;
    for (final v in todo) {
      try {
        final audio = await ref.read(youtubeServiceProvider).bestAudio(v.id);
        await ref.read(downloadsProvider.notifier).enqueue(
              v,
              DownloadOption(kind: OutputKind.m4a, label: 'M4A', tag: audio.tag, sizeBytes: audio.size),
            );
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _downloading = false);
    if (failed > 0) showMessage(context, '$failed no se pudieron agregar a Descargas.');
  }

  Future<void> _rename(Playlist p) async {
    final name = await showPlaylistNameDialog(context, ref, title: 'Renombrar lista', confirm: 'Guardar', initial: p.name, exceptId: p.id);
    if (name == null) return;
    try {
      await ref.read(playlistsProvider.notifier).rename(p.id, name);
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  Future<void> _delete(Playlist p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('¿Eliminar "${p.name}"?'),
        content: const Text('Se borra la lista. Las canciones descargadas siguen en tu Biblioteca.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(playlistsProvider.notifier).delete(p.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _reorder(List<PlaylistItem> items, int from, int to) async {
    final target = to > from ? to - 1 : to;
    if (target == from) return;
    final next = List.of(items);
    next.insert(target, next.removeAt(from));
    setState(() => _pending = next);
    await ref.read(playlistsProvider.notifier).move(_id, from, target);
  }

  Future<void> _remove(List<PlaylistItem> items, int index) async {
    final item = items[index];
    final next = List.of(items)..removeAt(index);
    setState(() => _pending = next);
    final notifier = ref.read(playlistsProvider.notifier);
    await notifier.removeItem(_id, item.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Se quitó "${item.video.title}"'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () async {
            // Vuelve al final y luego a su lugar.
            await notifier.addVideos(_id, [item.video]);
            final count = (await notifier.items(_id)).length;
            if (count - 1 != index) await notifier.move(_id, count - 1, index);
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final playlist = _playlist(ref.watch(playlistsProvider));
    final async = ref.watch(playlistItemsProvider(_id));
    // Al llegar el orden guardado, se deja de mostrar el provisional.
    ref.listen(playlistItemsProvider(_id), (_, next) {
      // Ojo: al invalidarse, el provider sigue dando el valor viejo mientras carga.
      if (next.hasValue && !next.isLoading && _pending != null) setState(() => _pending = null);
    });
    final items = _pending ?? async.value;
    final text = Theme.of(context).textTheme;
    const muted = Color(0xCCFFFFFF);

    final firstCover = playlist == null || playlist.coverVideoIds.isEmpty ? null : playlist.coverVideoIds.first;
    final coverUri = firstCover == null ? null : ref.watch(_coverUriProvider(firstCover)).value;
    final tone = (coverUri == null || coverUri.isEmpty ? null : ref.watch(artToneProvider(coverUri)).value) ?? const Color(0xFF2A2A33);
    final background = Theme.of(context).colorScheme.surface;
    final downloads = ref.watch(downloadsProvider);
    bool downloaded(String videoId) =>
        downloads.any((t) => t.videoId == videoId && t.status == DownloadStatus.completed && t.kind.isAudio);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(playlist?.name ?? ''),
        actions: [
          if (playlist != null)
            PopupMenuButton<String>(
              tooltip: 'Más opciones',
              onSelected: (v) => v == 'rename' ? _rename(playlist) : _delete(playlist),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Renombrar'))),
                PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Eliminar lista'))),
              ],
            ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: playlist == null
          ? const Center(child: Text('Esta lista ya no existe.'))
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: AnimatedContainer(
                    duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 450),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [tone, background],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, kToolbarHeight + 8, 20, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 12))],
                                ),
                                child: PlaylistCover(playlist: playlist, size: 220, radius: 8),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(playlist.name, style: text.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text(
                              [
                                playlist.count == 1 ? '1 canción' : '${playlist.count} canciones',
                                if (items != null && totalDuration(items) > Duration.zero) formatDuration(totalDuration(items)),
                              ].join(' · '),
                              style: text.bodyMedium?.copyWith(color: muted),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                IconButton(
                                  tooltip: 'Descargar para escuchar sin conexión',
                                  onPressed: items == null || items.isEmpty || _downloading ? null : () => _downloadAll(items),
                                  icon: _downloading
                                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                      : Icon(
                                          items != null && items.isNotEmpty && items.every((i) => downloaded(i.video.id))
                                              ? Icons.download_done_rounded
                                              : Icons.download_for_offline_outlined,
                                        ),
                                ),
                                IconButton(
                                  tooltip: 'Agregar canciones a otra lista',
                                  onPressed: items == null || items.isEmpty
                                      ? null
                                      : () => showAddToPlaylistSheet(context, ref, [for (final i in items) i.video]),
                                  icon: const Icon(Icons.playlist_add_rounded),
                                ),
                                const Spacer(),
                                IconButton(
                                  tooltip: 'Reproducir en aleatorio',
                                  iconSize: 30,
                                  onPressed: items == null || items.isEmpty ? null : () => _play(items, shuffle: true),
                                  icon: const Icon(Icons.shuffle_rounded),
                                ),
                                const SizedBox(width: 8),
                                _BigPlayButton(onPressed: items == null || items.isEmpty ? null : () => _play(items)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (items == null && async.hasError)
                  SliverFillRemaining(hasScrollBody: false, child: ErrorView(message: '${async.error}', onRetry: () => ref.invalidate(playlistItemsProvider(_id))))
                else if (items == null)
                  const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
                else if (items.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.queue_music_rounded,
                      title: 'Lista vacía',
                      message: 'Agrega canciones desde un video con "Guardar", o desde el reproductor.',
                    ),
                  )
                else
                  SliverReorderableList(
                    itemCount: items.length,
                    onReorder: (from, to) => _reorder(items, from, to),
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final v = item.video;
                      return Dismissible(
                        key: ValueKey('pl-item-${item.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Theme.of(context).colorScheme.errorContainer,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: const Icon(Icons.delete_outline),
                        ),
                        onDismissed: (_) => _remove(items, i),
                        child: Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                            contentPadding: const EdgeInsets.only(left: 16, right: 4),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: SizedBox(width: 48, height: 48, child: _SquareCover(videoId: v.id)),
                            ),
                            title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Row(
                              children: [
                                if (downloaded(v.id)) ...[
                                  Icon(Icons.download_done_rounded, size: 14, color: Theme.of(context).colorScheme.primary, semanticLabel: 'Descargada'),
                                  const SizedBox(width: 4),
                                ],
                                Expanded(
                                  child: Text(
                                    [v.author, if (v.duration != null) formatDuration(v.duration!)].where((s) => s.isNotEmpty).join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            onTap: () => _play(items, index: i),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PopupMenuButton<String>(
                                  tooltip: 'Opciones de la canción',
                                  onSelected: (action) {
                                    if (action == 'watch') openWatch(context, v.id);
                                    if (action == 'remove') _remove(items, i);
                                  },
                                  itemBuilder: (_) => [
                                    if (!v.id.contains(':'))
                                      const PopupMenuItem(value: 'watch', child: ListTile(leading: Icon(Icons.smart_display_outlined), title: Text('Ver video'))),
                                    const PopupMenuItem(value: 'remove', child: ListTile(leading: Icon(Icons.remove_circle_outline), title: Text('Quitar de la lista'))),
                                  ],
                                ),
                                ReorderableDragStartListener(
                                  index: i,
                                  child: const Tooltip(
                                    message: 'Arrastra para cambiar el orden',
                                    child: SizedBox(width: 48, height: 48, child: Icon(Icons.drag_handle_rounded)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
    );
  }
}

/// Botón circular grande blanco (como el del reproductor).
class _BigPlayButton extends StatelessWidget {
  const _BigPlayButton({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: 'Reproducir lista',
      child: Material(
        color: onPressed == null ? Colors.white38 : Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: const SizedBox(width: 56, height: 56, child: Icon(Icons.play_arrow_rounded, size: 36, color: Colors.black)),
        ),
      ),
    );
  }
}
