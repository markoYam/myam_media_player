import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../data/history.dart';
import '../../data/models.dart';
import '../watch/watch_screen.dart';
import 'history_screen.dart';
import 'paged_videos.dart';

/// Secciones de Inicio (como la versión Kotlin). YouTube ya no expone las tendencias por API
/// abierta, así que cada sección es una búsqueda; "Para ti" sale de lo que has visto.
enum FeedSection {
  forYou('Para ti', null),
  music('Música', 'música nueva'),
  gaming('Gaming', 'gaming'),
  movies('Películas y series', 'tráiler oficial'),
  podcasts('Podcasts', 'podcast episodio completo'),
  news('Noticias', 'noticias de hoy'),
  sports('Deportes', 'deportes resumen'),
  comedy('Comedia', 'comedia'),
  learn('Aprender', 'tutorial');

  const FeedSection(this.label, this.query);
  final String label;
  final String? query;

  FeedKey get feed => query == null ? 'foryou' : 'search:$query';
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  FeedSection _section = FeedSection.forYou;

  @override
  Widget build(BuildContext context) {
    final continueWatching = ref.watch(continueWatchingProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Text(greetingFor(DateTime.now())),
        actions: [
          IconButton(
            tooltip: 'Historial',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HistoryScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final s in FeedSection.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(label: Text(s.label), selected: _section == s, onSelected: (_) => setState(() => _section = s)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PagedVideoList(
              key: ValueKey(_section),
              feed: _section.feed,
              header: _section == FeedSection.forYou && continueWatching.isNotEmpty
                  ? _ContinueWatching(entries: continueWatching)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueWatching extends StatelessWidget {
  const _ContinueWatching({required this.entries});
  final List<WatchHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text('Seguir viendo', style: Theme.of(context).textTheme.titleMedium),
        ),
        SizedBox(
          // Miniatura 16:9 + título de 2 líneas + "Quedan…", con margen para letra grande.
          height: 200 * 9 / 16 + 6 + MediaQuery.textScalerOf(context).scale(64),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => ContinueCard(entry: entries[i]),
          ),
        ),
        const Divider(height: 24),
      ],
    );
  }
}

/// Miniatura con la barra roja de progreso y lo que falta.
class ContinueCard extends StatelessWidget {
  const ContinueCard({super.key, required this.entry, this.width = 200});
  final WatchHistoryEntry entry;
  final double width;

  @override
  Widget build(BuildContext context) {
    final left = entry.duration == null ? null : entry.duration! - entry.position;
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openWatch(context, entry.videoId),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                VideoThumb(url: entry.thumbnailUrl, duration: entry.duration),
                if (entry.progress != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                      child: LinearProgressIndicator(value: entry.progress, minHeight: 4, color: Colors.red, backgroundColor: Colors.white24),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // Flexible: si el texto no cabe se corta con "…" en vez de desbordar.
            Flexible(
              child: Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
            ),
            if (left != null && left > Duration.zero)
              Text('Quedan ${formatDuration(left)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
