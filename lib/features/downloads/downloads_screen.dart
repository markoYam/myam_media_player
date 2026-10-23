import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../data/download_manager.dart';
import '../../data/models.dart';

/// Descargas en curso, en cola, fallidas y canceladas. Las completadas están en la Biblioteca.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(downloadsProvider).where((t) => t.status != DownloadStatus.completed).toList();
    final notifier = ref.read(downloadsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Descargas')),
      body: tasks.isEmpty
          ? const EmptyState(
              icon: Icons.download_done,
              title: 'Nada descargando',
              message: 'Abre un video y toca "Descargar". Lo terminado aparece en la Biblioteca.',
            )
          : ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (_, i) {
                final t = tasks[i];
                return CompactRow(
                  thumbnailUrl: t.thumbnailUrl,
                  title: t.title,
                  subtitle: '${t.isMixtape ? 'Mixtape (automático)' : [t.kind.label, if (t.qualityLabel != null) t.qualityLabel!].join(' ')} · ${_statusLine(t)}',
                  bottom: t.isActive
                      ? LinearProgressIndicator(value: t.status == DownloadStatus.running ? t.progress : null)
                      : null,
                  trailing: _actions(context, t, notifier),
                  // Tocar una descarga fallida muestra el error completo (en la fila se corta).
                  onTap: t.status == DownloadStatus.failed && t.error != null
                      ? () => showDialog<void>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('No se pudo descargar'),
                              content: SelectableText(t.error!),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar')),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(c);
                                    notifier.retry(t.id);
                                  },
                                  child: const Text('Reintentar'),
                                ),
                              ],
                            ),
                          )
                      : null,
                );
              },
            ),
    );
  }

  Widget _actions(BuildContext context, DownloadTask t, DownloadsNotifier n) {
    if (t.isActive) {
      return IconButton(tooltip: 'Cancelar', icon: const Icon(Icons.close), onPressed: () => n.cancel(t.id));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(tooltip: 'Reintentar', icon: const Icon(Icons.refresh), onPressed: () => n.retry(t.id)),
        IconButton(tooltip: 'Quitar de la lista', icon: const Icon(Icons.delete_outline), onPressed: () => n.remove(t.id)),
      ],
    );
  }

  static String _statusLine(DownloadTask t) {
    switch (t.status) {
      case DownloadStatus.pending:
        return 'En cola';
      case DownloadStatus.running:
        final total = t.totalBytes;
        final parts = <String>[
          total != null ? '${formatBytes(t.downloadedBytes)} de ${formatBytes(total)}' : formatBytes(t.downloadedBytes),
          if ((t.bytesPerSecond ?? 0) > 0) formatSpeed(t.bytesPerSecond!),
          if ((t.bytesPerSecond ?? 0) > 0 && total != null) 'faltan ${formatDuration(Duration(seconds: ((total - t.downloadedBytes) / t.bytesPerSecond!).ceil()))}',
        ];
        return parts.join(' · ');
      case DownloadStatus.processing:
        return t.audioTag != null ? 'Uniendo video y audio…' : 'Convirtiendo a MP3…';
      case DownloadStatus.failed:
        return t.error ?? 'Falló';
      case DownloadStatus.cancelled:
        return 'Cancelada';
      case DownloadStatus.completed:
        return 'Completada';
    }
  }
}
