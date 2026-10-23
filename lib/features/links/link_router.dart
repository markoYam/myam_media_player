import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../core/youtube_links.dart';
import '../../data/archive_client.dart';
import '../../data/direct_links.dart';
import '../../data/youtube_service.dart' show AppException;
import '../../providers.dart';
import '../browse/channel_playlist_screens.dart';
import '../watch/watch_screen.dart';
import 'archive_screen.dart';
import 'direct_playback.dart';

/// Qué es un enlace (sin tocar la red).
sealed class LinkTarget {
  const LinkTarget();
}

class YouTubeVideoLink extends LinkTarget {
  const YouTubeVideoLink(this.id);
  final String id;
}

class YouTubePlaylistLink extends LinkTarget {
  const YouTubePlaylistLink(this.id);
  final String id;
}

class YouTubeChannelLink extends LinkTarget {
  const YouTubeChannelLink({this.id, this.handle});
  final String? id;
  final String? handle;
}

class ArchiveLink extends LinkTarget {
  const ArchiveLink(this.id);
  final String id;
}

class DirectLink extends LinkTarget {
  const DirectLink(this.uri, this.kind);
  final Uri uri;
  final DirectMediaKind kind;
}

/// Un enlace http(s) que no se reconoce por sí solo (puede ser audio/video sin extensión).
class UnknownLink extends LinkTarget {
  const UnknownLink(this.uri);
  final Uri uri;
}

/// Saca la URL de un texto (los textos compartidos traen "mira esto https://…"); si el texto es
/// solo un enlace sin esquema ("youtu.be/abc") también vale.
String? extractLink(String text) {
  final found = firstUrl(text);
  if (found != null) return found;
  final t = text.trim();
  return looksLikeUrl(t) ? t : null;
}

/// Clasifica el primer enlace de [text]; null si no hay enlace.
LinkTarget? classifyLink(String text) {
  final link = extractLink(text);
  if (link == null) return null;
  final videoId = videoIdFromInput(link);
  if (videoId != null) return YouTubeVideoLink(videoId);
  final playlistId = playlistIdFromInput(link);
  if (playlistId != null) return YouTubePlaylistLink(playlistId);
  final channel = channelFromInput(link);
  if (channel != null) return YouTubeChannelLink(id: channel.id, handle: channel.handle);
  final archive = archiveIdFromUrl(link);
  if (archive != null) return ArchiveLink(archive);
  final uri = Uri.tryParse(link.contains('://') ? link : 'https://$link');
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) return null;
  final kind = directKindFromUrl(uri);
  return kind != null ? DirectLink(uri, kind) : UnknownLink(uri);
}

/// Abre el primer enlace de [text]: YouTube (video, lista, canal), Internet Archive o un archivo
/// de audio/video directo. Devuelve false si no hay enlace o no es nada de eso (quien llama decide
/// qué hacer: p. ej. buscar el texto o avisar).
Future<bool> openLink(BuildContext context, WidgetRef ref, String text) async {
  final target = classifyLink(text);
  switch (target) {
    case null:
      return false;
    case YouTubeVideoLink(:final id):
      openWatch(context, id);
      return true;
    case YouTubePlaylistLink(:final id):
      openPlaylist(context, id);
      return true;
    case YouTubeChannelLink(:final id, :final handle):
      var channelId = id;
      if (channelId == null) {
        try {
          channelId = await ref.read(youtubeServiceProvider).channelIdForHandle(handle!);
        } on AppException catch (e) {
          if (context.mounted) showMessage(context, e.message);
          return true;
        }
      }
      if (context.mounted) openChannel(context, channelId);
      return true;
    case ArchiveLink(:final id):
      openArchiveItem(context, id);
      return true;
    case DirectLink(:final uri, :final kind):
      showDirectLinkSheet(context, ref, uri: uri, kind: kind);
      return true;
    case UnknownLink(:final uri):
      // Puede ser un archivo sin extensión: se pregunta al servidor qué es.
      final probe = await probeDirectLink(uri);
      if (probe == null || !context.mounted) return false;
      showDirectLinkSheet(context, ref, uri: uri, kind: probe.kind, contentType: probe.contentType, sizeBytes: probe.sizeBytes);
      return true;
  }
}

/// Hoja de un enlace directo: título, tipo, reproducir y descargar.
void showDirectLinkSheet(
  BuildContext context,
  WidgetRef ref, {
  required Uri uri,
  required DirectMediaKind kind,
  String? contentType,
  int? sizeBytes,
}) {
  final title = titleFromUrl(uri);
  final id = 'url:${stableHash(uri.toString())}';
  final output = outputKindForExtension(extensionOf(uri.path)) ?? outputKindForContentType(contentType);
  final isAudio = kind == DirectMediaKind.audio;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) {
      final text = Theme.of(sheet).textTheme;
      final muted = Theme.of(sheet).colorScheme.onSurfaceVariant;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(isAudio ? Icons.music_note_rounded : Icons.movie_outlined, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleMedium),
                        Text(
                          [
                            isAudio ? 'Audio' : 'Video',
                            uri.host,
                            if (sizeBytes != null && sizeBytes > 0) formatBytes(sizeBytes),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(sheet).pop();
                        if (isAudio) {
                          playDirectAudio(context, ref, [(id: id, title: title, author: uri.host, url: uri, art: null)], 0);
                        } else {
                          openDirectVideo(context, ref, url: uri, title: title);
                        }
                      },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Reproducir'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: output == null
                          ? null
                          : () {
                              Navigator.of(sheet).pop();
                              downloadDirect(context, ref,
                                  id: id, title: title, author: uri.host, url: uri, kind: output, sizeBytes: sizeBytes);
                            },
                      icon: const Icon(Icons.download),
                      label: const Text('Descargar'),
                    ),
                  ),
                ],
              ),
              if (output == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Este formato se puede reproducir pero no descargar.', style: text.bodySmall?.copyWith(color: muted)),
                ),
            ],
          ),
        ),
      );
    },
  );
}
