import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../data/download_manager.dart';
import '../../data/history.dart';
import '../../data/models.dart';
import '../../data/settings.dart';
import '../../data/youtube_service.dart';
import '../../playback/audio_controller.dart';
import '../player/player_screen.dart';
import 'collection_header.dart';
import 'library_model.dart';
import 'library_screen.dart';

/// Mixtape sin conexión: todo el audio que tienes en el teléfono (lo guardado solo al escuchar y
/// tus descargas de audio), de lo más reciente que escuchaste a lo más antiguo.
final mixtapeProvider = FutureProvider<List<LibraryEntry>>((ref) async {
  final files = await ref.watch(libraryFilesProvider.future);
  final lastHeard = {for (final h in ref.watch(historyProvider)) h.videoId: h.watchedAt};
  final songs = files.where((e) => e.task.kind.isAudio || e.task.isMixtape).toList()
    ..sort((a, b) {
      final ha = lastHeard[a.task.videoId] ?? a.task.completedAt ?? 0;
      final hb = lastHeard[b.task.videoId] ?? b.task.completedAt ?? 0;
      return hb.compareTo(ha);
    });
  return songs;
});

/// Reproduce el mixtape (no necesita internet).
Future<void> playMixtape(BuildContext context, WidgetRef ref, {bool shuffle = false, int index = 0}) async {
  final songs = await ref.read(mixtapeProvider.future);
  if (!context.mounted) return;
  if (songs.isEmpty) {
    showMessage(context, 'Tu mixtape está vacío. Escucha algo con internet y se irá llenando solo.');
    return;
  }
  try {
    await ref.read(audioControllerProvider).playFiles(songs, startIndex: index, shuffle: shuffle);
    if (context.mounted) {
      await Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const PlayerScreen()));
    }
  } on AppException catch (e) {
    if (context.mounted) showMessage(context, e.message);
  }
}

/// Tarjeta del mixtape en la Biblioteca.
class MixtapeCard extends ConsumerWidget {
  const MixtapeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(mixtapeProvider).value ?? const <LibraryEntry>[];
    final enabled = ref.watch(settingsProvider.select((s) => s.mixtapeEnabled));
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MixtapeScreen())),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.offline_bolt, size: 44, color: scheme.onPrimary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tu mixtape sin conexión', style: text.titleMedium?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.bold)),
                        Text(
                          songs.isEmpty
                              ? (enabled ? 'Se llena solo con lo que escuchas' : 'Desactivado en Ajustes')
                              : '${songs.length} canciones · funciona sin internet',
                          style: text.bodySmall?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.9)),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Reproducir mixtape en aleatorio',
                    style: IconButton.styleFrom(backgroundColor: scheme.onPrimary, foregroundColor: scheme.primary),
                    onPressed: songs.isEmpty ? null : () => playMixtape(context, ref, shuffle: true),
                    icon: const Icon(Icons.shuffle),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Portada del mixtape: degradado del color de la app con el ícono de sin conexión.
class MixtapeArt extends StatelessWidget {
  const MixtapeArt({super.key, required this.size, this.radius = 6});
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [brandIndigo, scheme.tertiary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Icon(Icons.offline_bolt_rounded, size: size * 0.45, color: Colors.white),
        ),
      ),
    );
  }
}

/// Lista del mixtape: reproducir, aleatorio, fijar en la biblioteca o quitar.
class MixtapeScreen extends ConsumerWidget {
  const MixtapeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(mixtapeProvider);
    final settings = ref.watch(settingsProvider);
    final list = songs.value ?? const <LibraryEntry>[];
    final size = list.fold<int>(0, (sum, e) => sum + (e.task.totalBytes ?? 0));
    return Scaffold(
      appBar: AppBar(),
      body: songs.isLoading && songs.value == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? EmptyState(
                  icon: Icons.offline_bolt_outlined,
                  title: 'Aún no hay nada',
                  message: settings.mixtapeEnabled
                      ? 'Lo que escuches más de 30 segundos se guarda solo${settings.mixtapeWifiOnly ? ' (con Wi-Fi)' : ''}. '
                          'Así lo puedes oír cuando no tengas internet.'
                      : 'Actívalo en Ajustes → Mixtape sin conexión.',
                )
              : ListView(
                  children: [
                    // Cabecera como "Tus me gusta" de Spotify: portada propia y botón grande.
                    CollectionHeader(
                      art: const MixtapeArt(size: 200),
                      tone: Theme.of(context).colorScheme.primary.withValues(alpha: 0.55),
                      title: 'Tu mixtape sin conexión',
                      subtitle: '${countLabel(list.length, one: 'canción', many: 'canciones')} · ${formatBytes(size)} · '
                          '${settings.mixtapeEnabled ? 'guarda hasta ${settings.mixtapeMax} solo' : 'guardado automático desactivado'}',
                      onShuffle: () => playMixtape(context, ref, shuffle: true),
                      onPlay: () => playMixtape(context, ref),
                    ),
                    for (var i = 0; i < list.length; i++) _MixtapeRow(entry: list[i], onTap: () => playMixtape(context, ref, index: i)),
                  ],
                ),
    );
  }
}

class _MixtapeRow extends ConsumerWidget {
  const _MixtapeRow({required this.entry, required this.onTap});
  final LibraryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = entry.task;
    return ListTile(
      onTap: onTap,
      leading: SizedBox(width: 52, height: 52, child: LocalCover(videoId: t.videoId, radius: 4, fallbackUrl: t.thumbnail)),
      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([t.author, if (t.isMixtape) 'Guardada sola' else 'Descargada'].where((s) => s.isNotEmpty).join(' · ')),
      trailing: !t.isMixtape
          ? null
          : PopupMenuButton<String>(
              onSelected: (v) async {
                final n = ref.read(downloadsProvider.notifier);
                if (v == 'keep') {
                  await n.keep(t.id);
                  if (context.mounted) showMessage(context, 'Fijada en la Biblioteca: ya no se borrará sola.');
                } else {
                  await n.remove(t.id, deleteFile: true);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'keep', child: ListTile(leading: Icon(Icons.push_pin_outlined), title: Text('Fijar en la Biblioteca'))),
                PopupMenuItem(value: 'remove', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Quitar del mixtape'))),
              ],
            ),
    );
  }
}

/// Portada guardada en el teléfono (sin internet) o la de YouTube.
class LocalCover extends StatelessWidget {
  const LocalCover({super.key, required this.videoId, this.radius = 8, this.fit = BoxFit.cover, this.fallbackUrl});
  final String videoId;
  final double radius;
  final BoxFit fit;

  /// Miniatura de internet si no hay portada guardada (enlaces directos); null = la de YouTube.
  final String? fallbackUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: FutureBuilder<File>(
        future: coverFileFor(videoId),
        builder: (context, snap) {
          final file = snap.data;
          if (file != null && file.existsSync()) return Image.file(file, fit: fit);
          return VideoThumb(url: fallbackUrl ?? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg', radius: 0);
        },
      ),
    );
  }
}
