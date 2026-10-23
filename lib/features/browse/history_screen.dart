import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../data/history.dart';
import '../../data/models.dart';
import '../watch/watch_screen.dart';

/// Historial de reproducción: tocar reanuda donde te quedaste.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(historyProvider);
    final notifier = ref.read(historyProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial'),
        actions: [
          if (entries.isNotEmpty)
            IconButton(
              tooltip: 'Borrar historial',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('¿Borrar el historial?'),
                    content: const Text('Se olvidará lo que has visto y "Seguir viendo". Las descargas no se tocan.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Borrar')),
                    ],
                  ),
                );
                if (ok == true) await notifier.clear();
              },
            ),
        ],
      ),
      body: entries.isEmpty
          ? const EmptyState(icon: Icons.history, title: 'Aún no has visto nada', message: 'Lo que veas o escuches aparecerá aquí.')
          : ListView.builder(
              itemCount: entries.length,
              itemBuilder: (_, i) {
                final e = entries[i];
                return CompactRow(
                  thumbnailUrl: e.thumbnailUrl,
                  title: e.title,
                  subtitle: [e.author, _when(e)].where((s) => s.isNotEmpty).join('\n'),
                  duration: e.duration,
                  bottom: e.isResumable && e.progress != null
                      ? LinearProgressIndicator(value: e.progress, color: Colors.red, minHeight: 3)
                      : null,
                  onTap: () => openWatch(context, e.videoId),
                  trailing: IconButton(
                    tooltip: 'Quitar del historial',
                    icon: const Icon(Icons.close),
                    onPressed: () => notifier.remove(e.videoId),
                  ),
                );
              },
            ),
    );
  }

  static String _when(WatchHistoryEntry e) {
    final ago = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(e.watchedAt));
    final when = ago.inMinutes < 60
        ? 'hace ${ago.inMinutes.clamp(1, 59)} min'
        : ago.inHours < 24
            ? 'hace ${ago.inHours} h'
            : 'hace ${ago.inDays} d';
    return e.isResumable ? '$when · visto ${formatDuration(e.position)}' : when;
  }
}
