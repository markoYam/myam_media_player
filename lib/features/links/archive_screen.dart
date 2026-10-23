import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../data/archive_client.dart';
import '../../data/download_manager.dart';
import '../../data/direct_links.dart';
import '../../data/youtube_service.dart' show AppException;
import 'direct_playback.dart';

/// OGG/Opus: el reproductor de Android los abre; el de iOS no.
bool get _allowOgg => !kIsWeb && Platform.isAndroid;

final archiveItemProvider = FutureProvider.autoDispose.family<ArchiveItem, String>(
  (ref, id) => fetchArchiveItem(id, allowOgg: _allowOgg),
  retry: (_, __) => null,
);

void openArchiveItem(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ArchiveItemScreen(id: id)));

/// Item de Internet Archive: portada, título, creador y sus audios y videos (reproducir o descargar).
class ArchiveItemScreen extends ConsumerWidget {
  const ArchiveItemScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(archiveItemProvider(id));
    return Scaffold(
      appBar: AppBar(title: const Text('Internet Archive')),
      body: item.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: e is AppException ? e.message : 'No se pudo abrir ese enlace de Internet Archive.',
          onRetry: () => ref.invalidate(archiveItemProvider(id)),
        ),
        data: (it) => _ArchiveBody(item: it),
      ),
    );
  }
}

class _ArchiveBody extends ConsumerWidget {
  const _ArchiveBody({required this.item});
  final ArchiveItem item;

  DirectMedia _media(ArchiveFile f) =>
      (id: 'ia:${item.id}/${f.name}', title: f.title, author: item.creator.isEmpty ? 'Internet Archive' : item.creator, url: f.url, art: item.thumbnail);

  Future<void> _download(BuildContext context, WidgetRef ref, ArchiveFile f) async {
    final kind = outputKindForExtension(f.extension);
    if (kind == null) return;
    await downloadDirect(
      context,
      ref,
      id: 'ia:${item.id}/${f.name}',
      title: f.title,
      author: item.creator.isEmpty ? 'Internet Archive' : item.creator,
      url: f.url,
      kind: kind,
      thumbnail: item.thumbnail.toString(),
      sizeBytes: f.sizeBytes,
      qualityLabel: f.format,
    );
  }

  Future<void> _downloadAll(BuildContext context, WidgetRef ref, List<ArchiveFile> files) async {
    var added = 0;
    for (final f in files) {
      final kind = outputKindForExtension(f.extension);
      if (kind == null) continue;
      try {
        await ref.read(downloadsProvider.notifier).enqueueDirect(
              id: 'ia:${item.id}/${f.name}',
              title: f.title,
              author: item.creator.isEmpty ? 'Internet Archive' : item.creator,
              url: f.url,
              kind: kind,
              thumbnail: item.thumbnail.toString(),
              sizeBytes: f.sizeBytes,
              qualityLabel: f.format,
            );
        added++;
      } on AppException {
        // Ya descargado o en curso: se salta.
      }
    }
    if (context.mounted) {
      showMessage(context, added == 0 ? 'Ya tenías todo descargado o en curso.' : 'Se agregaron $added descargas. Míralas en la pestaña Descargas.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final audio = item.audio;
    final video = item.video;
    final downloadableAudio = audio.where((f) => outputKindForExtension(f.extension) != null).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 112,
                  height: 112,
                  child: CachedNetworkImage(
                    imageUrl: item.thumbnail.toString(),
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.account_balance_outlined, size: 40),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: text.titleLarge),
                    if (item.creator.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(item.creator, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(color: muted)),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      [if (audio.isNotEmpty) '${audio.length} audios', if (video.isNotEmpty) '${video.length} videos'].join(' · '),
                      style: text.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (audio.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => playDirectAudio(context, ref, [for (final f in audio) _media(f)], 0),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Reproducir todo'),
                ),
                if (downloadableAudio.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: () => _downloadAll(context, ref, downloadableAudio),
                    icon: const Icon(Icons.download),
                    label: Text(downloadableAudio.length == 1 ? 'Descargar' : 'Descargar todo (${downloadableAudio.length})'),
                  ),
              ],
            ),
          ),
        if (audio.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 4), child: Text('Audio', style: text.titleMedium)),
          for (var i = 0; i < audio.length; i++)
            _FileRow(
              file: audio[i],
              thumbnail: item.thumbnail.toString(),
              onTap: () => playDirectAudio(context, ref, [for (final f in audio) _media(f)], i),
              onDownload: outputKindForExtension(audio[i].extension) == null ? null : () => _download(context, ref, audio[i]),
            ),
        ],
        if (video.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 4), child: Text('Video', style: text.titleMedium)),
          for (final f in video)
            _FileRow(
              file: f,
              thumbnail: item.thumbnail.toString(),
              onTap: () => openDirectVideo(context, ref, url: f.url, title: f.title),
              onDownload: outputKindForExtension(f.extension) == null ? null : () => _download(context, ref, f),
            ),
        ],
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.thumbnail, required this.onTap, required this.onDownload});
  final ArchiveFile file;
  final String thumbnail;
  final VoidCallback onTap;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final size = file.sizeBytes;
    return CompactRow(
      thumbnailUrl: thumbnail,
      title: file.title,
      subtitle: [file.format, if (size != null && size > 0) formatBytes(size)].join(' · '),
      duration: file.duration,
      onTap: onTap,
      trailing: onDownload == null
          ? null
          : IconButton(tooltip: 'Descargar', icon: const Icon(Icons.download_outlined), onPressed: onDownload),
    );
  }
}
