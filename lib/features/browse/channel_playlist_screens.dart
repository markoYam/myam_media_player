import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/youtube_service.dart';
import '../../playback/audio_controller.dart';
import '../../providers.dart';
import '../player/player_screen.dart';
import '../watch/watch_screen.dart';
import 'paged_videos.dart';

final channelInfoProvider = FutureProvider.autoDispose.family<ChannelInfo, String>(
  (ref, id) => ref.read(youtubeServiceProvider).channel(id),
  retry: (_, __) => null,
);

final playlistInfoProvider = FutureProvider.autoDispose.family<PlaylistInfo, String>(
  (ref, id) => ref.read(youtubeServiceProvider).playlist(id),
  retry: (_, __) => null,
);

void openChannel(BuildContext context, String channelId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChannelScreen(channelId: channelId)));

void openPlaylist(BuildContext context, String playlistId, {String? title}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaylistScreen(playlistId: playlistId, initialTitle: title)));

/// Canal: cabecera y pestañas "Recientes" / "Populares".
class ChannelScreen extends ConsumerWidget {
  const ChannelScreen({super.key, required this.channelId});
  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(channelInfoProvider(channelId));
    final c = info.value;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(c?.name ?? 'Canal'),
          actions: [
            IconButton(
              tooltip: 'Compartir',
              icon: const Icon(Icons.share),
              onPressed: () => SharePlus.instance.share(ShareParams(text: 'https://www.youtube.com/channel/$channelId')),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Recientes'), Tab(text: 'Populares')]),
        ),
        body: info.hasError
            ? ErrorView(
                message: info.error is AppException ? (info.error! as AppException).message : '${info.error}',
                onRetry: () => ref.invalidate(channelInfoProvider(channelId)),
              )
            : TabBarView(
                children: [
                  PagedVideoList(feed: 'channel:$channelId:new', header: c == null ? null : _ChannelHeader(info: c), compact: true),
                  PagedVideoList(feed: 'channel:$channelId:popular', compact: true),
                ],
              ),
      ),
    );
  }
}

class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({required this.info});
  final ChannelInfo info;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        if (info.bannerUrl != null)
          AspectRatio(
            aspectRatio: 6,
            child: CachedNetworkImage(imageUrl: info.bannerUrl!, fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox()),
          ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            radius: 28,
            backgroundImage: info.avatarUrl == null ? null : CachedNetworkImageProvider(info.avatarUrl!),
            child: info.avatarUrl == null ? Text(info.name.isEmpty ? '?' : info.name.characters.first) : null,
          ),
          title: Text(info.name, style: text.titleLarge),
          subtitle: info.subscribers == null ? null : Text('${compactCount(info.subscribers!)} suscriptores'),
        ),
      ],
    );
  }
}

/// Lista de reproducción: cabecera, "Reproducir todo" / "Aleatorio" y sus videos.
class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key, required this.playlistId, this.initialTitle});
  final String playlistId;
  final String? initialTitle;

  FeedKey get _feed => 'playlist:$playlistId';

  Future<void> _play(BuildContext context, WidgetRef ref, {required bool shuffle, int index = 0, bool listen = false}) async {
    final loaded = ref.read(pagedVideosProvider(_feed)).items;
    if (loaded.isEmpty) return;
    // Aleatorio: se baraja la lista y se empieza por el primero del nuevo orden.
    final items = shuffle ? ([...loaded]..shuffle()) : loaded;
    final start = shuffle ? 0 : index.clamp(0, items.length - 1);
    final player = ref.read(audioControllerProvider);
    try {
      if (listen) {
        await player.playYouTube(items, startIndex: start);
        if (context.mounted) {
          await Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const PlayerScreen()));
        }
      } else if (context.mounted) {
        // Ver: abre el video y "Sigue en la lista" continúa en ese orden.
        openWatch(context, items[start].id, upNext: items.sublist(start + 1));
      }
    } on AppException catch (e) {
      if (context.mounted) showMessage(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(playlistInfoProvider(playlistId));
    final p = info.value;
    final loaded = ref.watch(pagedVideosProvider(_feed).select((s) => s.items.length));
    final hasMore = ref.watch(pagedVideosProvider(_feed).select((s) => s.page?.hasMore ?? false));
    final text = Theme.of(context).textTheme;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p?.title ?? initialTitle ?? 'Lista de reproducción', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            [if (p != null && p.author.isNotEmpty) p.author, if (p?.videoCount != null) '${p!.videoCount} videos'].join(' · '),
            style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: loaded == 0 ? null : () => _play(context, ref, shuffle: false),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Reproducir todo'),
              ),
              FilledButton.tonalIcon(
                onPressed: loaded == 0 ? null : () => _play(context, ref, shuffle: true),
                icon: const Icon(Icons.shuffle),
                label: const Text('Aleatorio'),
              ),
              OutlinedButton.icon(
                onPressed: loaded == 0 ? null : () => _play(context, ref, shuffle: false, listen: true),
                icon: const Icon(Icons.headphones),
                label: const Text('Escuchar'),
              ),
            ],
          ),
          if (hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Se reproducen los videos cargados; baja para cargar más.', style: text.labelMedium),
            ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Compartir',
            icon: const Icon(Icons.share),
            onPressed: () => SharePlus.instance.share(ShareParams(text: 'https://www.youtube.com/playlist?list=$playlistId')),
          ),
        ],
      ),
      body: info.hasError
          ? ErrorView(
              message: info.error is AppException ? (info.error! as AppException).message : '${info.error}',
              onRetry: () => ref.invalidate(playlistInfoProvider(playlistId)),
            )
          : PagedVideoList(
              feed: _feed,
              header: header,
              compact: true,
              emptyMessage: 'Esta lista está vacía o es privada.',
              onOpen: (items, i) => _play(context, ref, shuffle: false, index: i),
            ),
    );
  }
}

/// Fila de una lista en los resultados de búsqueda.
class PlaylistRow extends StatelessWidget {
  const PlaylistRow({super.key, required this.playlist});
  final PlaylistSummary playlist;

  @override
  Widget build(BuildContext context) {
    return CompactRow(
      thumbnailUrl: playlist.thumbnailUrl ?? '',
      title: playlist.title,
      subtitle: [
        if (playlist.author != null) playlist.author!,
        if (playlist.videoCount != null) '${playlist.videoCount} videos',
        'Lista de reproducción',
      ].join(' · '),
      onTap: () => openPlaylist(context, playlist.id, title: playlist.title),
    );
  }
}

/// Fila de un canal en los resultados de búsqueda.
class ChannelRow extends StatelessWidget {
  const ChannelRow({super.key, required this.channel});
  final ChannelSummary channel;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        radius: 26,
        backgroundImage: channel.avatarUrl == null ? null : CachedNetworkImageProvider(channel.avatarUrl!),
        child: channel.avatarUrl == null ? Text(channel.name.isEmpty ? '?' : channel.name.characters.first) : null,
      ),
      title: Text(channel.name),
      subtitle: Text(
        [if ((channel.videoCount ?? 0) > 0) '${channel.videoCount} videos', if ((channel.description ?? '').isNotEmpty) channel.description!]
            .join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => openChannel(context, channel.id),
    );
  }
}
