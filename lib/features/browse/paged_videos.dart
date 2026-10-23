import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../data/history.dart';
import '../../data/models.dart';
import '../../data/youtube_service.dart';
import '../../providers.dart';
import '../library/mixtape.dart';
import '../watch/watch_screen.dart';

/// De dónde salen los videos de una lista paginada.
///
/// - `search:<consulta>` · `channel:<id>:new` · `channel:<id>:popular` · `playlist:<id>` · `foryou`
typedef FeedKey = String;

class PagedVideos {
  const PagedVideos({this.items = const [], this.loading = true, this.loadingMore = false, this.error, this.page});
  final List<VideoSummary> items;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final PagedResult<VideoSummary>? page;

  bool get canLoadMore => (page?.hasMore ?? false) && !loading && !loadingMore;
}

class PagedVideosNotifier extends Notifier<PagedVideos> {
  PagedVideosNotifier(this.key);
  final FeedKey key;

  @override
  PagedVideos build() {
    Future.microtask(load);
    return const PagedVideos();
  }

  Future<PagedResult<VideoSummary>> _first() async {
    final yt = ref.read(youtubeServiceProvider);
    final parts = key.split(':');
    switch (parts.first) {
      case 'search':
        return yt.search(key.substring('search:'.length));
      case 'channel':
        return yt.channelVideos(parts[1], popular: parts.length > 2 && parts[2] == 'popular');
      case 'playlist':
        return yt.playlistVideos(parts[1]);
      case 'foryou':
        final history = ref.read(historyProvider);
        final seeds = history.take(3).map((e) => e.videoId).toList();
        final items = await yt.recommendations(seeds, exclude: history.map((e) => e.videoId).toSet());
        return PagedResult(items);
      default:
        throw AppException('Lista desconocida: $key');
    }
  }

  Future<void> load() async {
    state = const PagedVideos();
    try {
      final page = await _first();
      if (!ref.mounted) return;
      state = PagedVideos(items: page.items, loading: false, page: page);
    } on AppException catch (e) {
      if (!ref.mounted) return;
      state = PagedVideos(loading: false, error: e.message);
    }
  }

  Future<void> loadMore() async {
    final s = state;
    final page = s.page;
    if (!s.canLoadMore || page == null) return;
    state = PagedVideos(items: s.items, loading: false, loadingMore: true, page: page);
    try {
      final next = await page.next();
      if (!ref.mounted) return;
      final known = s.items.map((v) => v.id).toSet();
      state = PagedVideos(items: [...s.items, ...next.items.where((v) => known.add(v.id))], loading: false, page: next);
    } on AppException {
      if (!ref.mounted) return;
      state = PagedVideos(items: s.items, loading: false);
    }
  }
}

final pagedVideosProvider =
    NotifierProvider.autoDispose.family<PagedVideosNotifier, PagedVideos, FeedKey>(PagedVideosNotifier.new);

/// Lista con scroll infinito, "tirar para recargar", estados de carga/error/vacío y una cabecera.
class PagedVideoList extends ConsumerStatefulWidget {
  const PagedVideoList({
    super.key,
    required this.feed,
    this.header,
    this.compact = false,
    this.emptyMessage = 'No hay videos aquí.',
    this.onOpen,
  });

  final FeedKey feed;
  final Widget? header;

  /// Filas compactas (listas, canales) en vez de tarjetas grandes.
  final bool compact;
  final String emptyMessage;

  /// Al tocar un video. Por defecto abre "ver video".
  final void Function(List<VideoSummary> items, int index)? onOpen;

  @override
  ConsumerState<PagedVideoList> createState() => _PagedVideoListState();
}

class _PagedVideoListState extends ConsumerState<PagedVideoList> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 800) ref.read(pagedVideosProvider(widget.feed).notifier).loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(pagedVideosProvider(widget.feed));
    final notifier = ref.read(pagedVideosProvider(widget.feed).notifier);
    final header = widget.header;
    final children = <Widget>[if (header != null) header];

    Widget body;
    if (s.loading) {
      body = const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
    } else if (s.error != null) {
      final offline = s.error!.contains('conexión');
      body = Column(
        children: [
          ErrorView(message: s.error!, onRetry: notifier.load),
          if (offline)
            FilledButton.icon(
              onPressed: () => playMixtape(context, ref, shuffle: true),
              icon: const Icon(Icons.offline_bolt),
              label: const Text('Escuchar mi mixtape sin conexión'),
            ),
        ],
      );
    } else if (s.items.isEmpty) {
      body = Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(widget.emptyMessage)));
    } else {
      body = const SizedBox.shrink();
    }

    final count = s.loading || s.error != null || s.items.isEmpty ? 0 : s.items.length;
    return RefreshIndicator(
      onRefresh: notifier.load,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: children.length + 1 + count + (s.loadingMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i < children.length) return children[i];
          if (i == children.length) return body;
          final index = i - children.length - 1;
          if (index >= count) {
            return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
          }
          final v = s.items[index];
          void open() => widget.onOpen != null ? widget.onOpen!(s.items, index) : openWatch(context, v.id);
          if (widget.compact) {
            return CompactRow(
              thumbnailUrl: v.thumbnailUrl,
              title: v.title,
              subtitle: [v.author, videoMeta(views: v.viewCount, uploaded: v.uploadedText)].where((x) => x.isNotEmpty).join('\n'),
              duration: v.duration,
              onTap: open,
            );
          }
          return VideoCard(video: v, onTap: open);
        },
      ),
    );
  }
}
