import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets.dart';
import '../../core/youtube_links.dart';
import '../../data/models.dart';
import '../../data/search_history.dart';
import '../../data/youtube_service.dart';
import '../../providers.dart';
import '../browse/channel_playlist_screens.dart';
import '../links/link_router.dart';
import '../watch/watch_screen.dart';

class SearchState {
  const SearchState({
    this.query = '',
    this.kind = SearchKind.videos,
    this.items = const [],
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.page,
  });

  final String query;
  final SearchKind kind;

  /// VideoSummary, PlaylistSummary o ChannelSummary según [kind].
  final List<Object> items;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final PagedResult<Object>? page;

  bool get canLoadMore => (page?.hasMore ?? false) && !loading && !loadingMore;
}

class SearchNotifier extends Notifier<SearchState> {
  int _generation = 0;

  @override
  SearchState build() => const SearchState();

  Future<PagedResult<Object>> _first(String q, SearchKind kind) async {
    final yt = ref.read(youtubeServiceProvider);
    return switch (kind) {
      SearchKind.videos => _erase(await yt.search(q)),
      SearchKind.playlists => _erase(await yt.searchPlaylists(q)),
      SearchKind.channels => _erase(await yt.searchChannels(q)),
    };
  }

  /// Convierte PagedResult<T> en PagedResult<Object> manteniendo la paginación.
  static PagedResult<Object> _erase<T extends Object>(PagedResult<T> page) =>
      PagedResult<Object>(page.items, page.hasMore ? () async => _erase(await page.next()) : null);

  Future<void> search(String query, {SearchKind? kind}) async {
    final q = query.trim();
    final k = kind ?? state.kind;
    if (q.isEmpty) {
      state = SearchState(kind: k);
      return;
    }
    final gen = ++_generation;
    state = SearchState(query: q, kind: k, loading: true);
    try {
      final page = await _first(q, k);
      if (gen != _generation) return;
      state = SearchState(query: q, kind: k, items: page.items, page: page);
    } on AppException catch (e) {
      if (gen != _generation) return;
      state = SearchState(query: q, kind: k, error: e.message);
    }
  }

  void setKind(SearchKind kind) {
    if (kind == state.kind) return;
    search(state.query, kind: kind);
  }

  Future<void> loadMore() async {
    final s = state;
    final page = s.page;
    if (!s.canLoadMore || page == null) return;
    final gen = _generation;
    state = SearchState(query: s.query, kind: s.kind, items: s.items, loadingMore: true, page: page);
    try {
      final next = await page.next();
      if (gen != _generation) return;
      state = SearchState(query: s.query, kind: s.kind, items: [...s.items, ...next.items], page: next);
    } on AppException {
      if (gen != _generation) return;
      state = SearchState(query: s.query, kind: s.kind, items: s.items);
    }
  }
}

final searchProvider = NotifierProvider<SearchNotifier, SearchState>(SearchNotifier.new);

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  /// Sugerencias de YouTube para el texto actual (vacías sin internet).
  List<String> _suggestions = const [];
  Timer? _debounce;
  int _suggestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(searchProvider).query;
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) ref.read(searchProvider.notifier).loadMore();
    });
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Pide sugerencias ~250 ms después de dejar de escribir; las respuestas viejas se descartan.
  void _onChanged(String text) {
    setState(() {});
    _debounce?.cancel();
    final q = text.trim();
    if (q.isEmpty || looksLikeUrl(q)) {
      _suggestGeneration++;
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final generation = ++_suggestGeneration;
      final list = await ref.read(youtubeServiceProvider).suggestions(q);
      if (!mounted || generation != _suggestGeneration) return;
      setState(() => _suggestions = list);
    });
  }

  /// Pasa [text] al campo sin buscar (la flecha ↖, como en YouTube).
  void _fill(String text) {
    _controller.value = TextEditingValue(text: '$text ', selection: TextSelection.collapsed(offset: text.length + 1));
    _onChanged(_controller.text);
  }

  void _searchFor(String text) {
    _controller.text = text;
    _submit(text);
  }

  Future<void> _submit(String text) async {
    _focus.unfocus();
    _debounce?.cancel();
    _suggestGeneration++;
    final q = text.trim();
    if (q.isEmpty) return;
    // Enlaces: YouTube (video, lista, canal), Internet Archive y archivos directos.
    if (looksLikeUrl(q)) {
      if (await openLink(context, ref, q)) return;
      if (!mounted) return;
    }
    // Respaldo para lo que no es URL completa (p. ej. un id de video suelto).
    final videoId = videoIdFromInput(q);
    if (videoId != null) {
      openWatch(context, videoId);
      return;
    }
    final playlistId = playlistIdFromInput(q);
    if (playlistId != null) {
      openPlaylist(context, playlistId);
      return;
    }
    final channel = channelFromInput(q);
    if (channel != null) {
      var id = channel.id;
      if (id == null) {
        try {
          id = await ref.read(youtubeServiceProvider).channelIdForHandle(channel.handle!);
        } on AppException catch (e) {
          if (mounted) showMessage(context, e.message);
          return;
        }
      }
      if (mounted) openChannel(context, id);
      return;
    }
    if (looksLikeUrl(q)) {
      showMessage(context, 'No se puede abrir ese enlace (YouTube, Internet Archive o un archivo .mp4/.mp3).');
      return;
    }
    unawaited(ref.read(searchHistoryProvider.notifier).add(q));
    await ref.read(searchProvider.notifier).search(q);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchProvider);
    // Con el campo enfocado se muestran recientes y sugerencias en lugar de los resultados.
    final showPanel = _focus.hasFocus;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SearchBar(
                controller: _controller,
                focusNode: _focus,
                hintText: 'Buscar en YouTube o pegar un enlace',
                leading: const Icon(Icons.search),
                trailing: [
                  if (_controller.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Borrar',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                        _focus.requestFocus();
                      },
                    ),
                ],
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: _submit,
              ),
            ),
            if (!showPanel) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<SearchKind>(
                  segments: const [
                    ButtonSegment(value: SearchKind.videos, label: Text('Videos'), icon: Icon(Icons.smart_display_outlined)),
                    ButtonSegment(value: SearchKind.playlists, label: Text('Listas'), icon: Icon(Icons.playlist_play)),
                    ButtonSegment(value: SearchKind.channels, label: Text('Canales'), icon: Icon(Icons.person_outline)),
                  ],
                  selected: {state.kind},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => ref.read(searchProvider.notifier).setKind(s.first),
                ),
              ),
              const SizedBox(height: 4),
            ],
            Expanded(child: showPanel ? _panel() : _body(state)),
          ],
        ),
      ),
    );
  }

  /// Recientes (que coinciden con lo escrito) y sugerencias de YouTube.
  Widget _panel() {
    final typed = _controller.text;
    final recents = matchingRecents(ref.watch(searchHistoryProvider), typed);
    final recentKeys = recents.map(foldSearch).toSet();
    final suggestions = typed.trim().isEmpty ? const <String>[] : _suggestions.where((s) => !recentKeys.contains(foldSearch(s))).toList();
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    if (recents.isEmpty && suggestions.isEmpty) {
      return typed.trim().isEmpty
          ? const EmptyState(
              icon: Icons.history,
              title: 'Sin búsquedas recientes',
              message: 'Lo que busques aparece aquí. También puedes pegar un enlace de YouTube, Internet Archive o un archivo.',
            )
          : const SizedBox.shrink();
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (recents.isNotEmpty && typed.trim().isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Expanded(child: Text('Recientes', style: text.titleMedium)),
                TextButton(
                  onPressed: () => ref.read(searchHistoryProvider.notifier).clear(),
                  child: const Text('Borrar todo'),
                ),
              ],
            ),
          ),
        for (final r in recents)
          ListTile(
            leading: Icon(Icons.history, color: muted),
            title: Text(r, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _searchFor(r),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(tooltip: 'Usar "$r" sin buscar', icon: const Icon(Icons.north_west), onPressed: () => _fill(r)),
                IconButton(
                  tooltip: 'Quitar "$r" de recientes',
                  icon: const Icon(Icons.close),
                  onPressed: () => ref.read(searchHistoryProvider.notifier).remove(r),
                ),
              ],
            ),
          ),
        for (final sug in suggestions)
          ListTile(
            leading: Icon(Icons.search, color: muted),
            title: Text(sug, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _searchFor(sug),
            trailing: IconButton(tooltip: 'Usar "$sug" sin buscar', icon: const Icon(Icons.north_west), onPressed: () => _fill(sug)),
          ),
      ],
    );
  }

  Widget _body(SearchState state) {
    if (state.loading) return const Center(child: CircularProgressIndicator());
    if (state.error != null) {
      return ErrorView(message: state.error!, onRetry: () => ref.read(searchProvider.notifier).search(state.query));
    }
    if (state.query.isEmpty) {
      return const EmptyState(
        icon: Icons.smart_display_outlined,
        title: 'Busca en YouTube',
        message: 'Videos, listas de reproducción o canales. También puedes pegar un enlace de un video, una lista o un canal.',
      );
    }
    if (state.items.isEmpty) {
      return const EmptyState(icon: Icons.search_off, title: 'Sin resultados', message: 'Prueba con otras palabras.');
    }
    return ListView.builder(
      controller: _scroll,
      itemCount: state.items.length + (state.loadingMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= state.items.length) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        }
        final item = state.items[i];
        return switch (item) {
          VideoSummary v => VideoCard(video: v, onTap: () => openWatch(context, v.id)),
          PlaylistSummary p => PlaylistRow(playlist: p),
          ChannelSummary c => ChannelRow(channel: c),
          _ => const SizedBox.shrink(),
        };
      },
    );
  }
}
