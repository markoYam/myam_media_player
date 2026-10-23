import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/playlists.dart';
import '../../data/youtube_service.dart';
import 'playlist_screen.dart';

/// Hoja "Guardar en una lista": "Nueva lista" arriba y luego tus listas. Al elegir una, se
/// agregan [videos] (los que ya estaban no se repiten).
Future<void> showAddToPlaylistSheet(BuildContext context, WidgetRef ref, List<VideoSummary> videos) async {
  // Solo videos de YouTube: los enlaces directos no se pueden volver a reproducir sin el archivo.
  final usable = [for (final v in videos) if (!v.id.contains(':')) v];
  if (usable.isEmpty) {
    showMessage(context, 'Esto no se puede agregar a una lista.');
    return;
  }
  final picked = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _AddToPlaylistSheet(count: usable.length),
  );
  if (picked == null || !context.mounted) return;
  final notifier = ref.read(playlistsProvider.notifier);
  if (picked == _newPlaylist) {
    final id = await showCreatePlaylistDialog(context, ref, initial: usable);
    if (id != null && context.mounted) {
      final name = ref.read(playlistsProvider).where((p) => p.id == id).firstOrNull?.name ?? 'la lista';
      showMessage(context, 'Agregada a $name');
    }
    return;
  }
  final name = ref.read(playlistsProvider).where((p) => p.id == picked).firstOrNull?.name ?? 'la lista';
  try {
    final added = await notifier.addVideos(picked, usable);
    if (!context.mounted) return;
    showMessage(
      context,
      added == 0
          ? (usable.length == 1 ? 'Ya estaba en $name' : 'Ya estaban en $name')
          : (usable.length == 1 || added == usable.length ? 'Agregada a $name' : 'Se agregaron $added a $name (las demás ya estaban)'),
    );
  } on AppException catch (e) {
    if (context.mounted) showMessage(context, e.message);
  }
}

/// Valor de la hoja para "Nueva lista".
const _newPlaylist = -1;

class _AddToPlaylistSheet extends ConsumerWidget {
  const _AddToPlaylistSheet({required this.count});
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(playlistsProvider);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(count == 1 ? 'Guardar en una lista' : 'Guardar $count en una lista', style: text.titleLarge),
            ),
            ListTile(
              leading: SizedBox(
                width: 48,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.add_rounded),
                ),
              ),
              title: const Text('Nueva lista'),
              onTap: () => Navigator.of(context).pop(_newPlaylist),
            ),
            for (final p in lists)
              ListTile(
                leading: PlaylistCover(playlist: p, size: 48),
                title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(p.count == 1 ? '1 canción' : '${p.count} canciones'),
                onTap: () => Navigator.of(context).pop(p.id),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Pide el nombre y crea la lista (con [initial] si se da). Devuelve el id o null si se canceló.
Future<int?> showCreatePlaylistDialog(BuildContext context, WidgetRef ref, {List<VideoSummary> initial = const []}) async {
  final name = await showPlaylistNameDialog(context, ref, title: 'Nueva lista', confirm: 'Crear');
  if (name == null) return null;
  try {
    return await ref.read(playlistsProvider.notifier).create(name, videos: initial);
  } on AppException catch (e) {
    if (context.mounted) showMessage(context, e.message);
    return null;
  }
}

/// Diálogo con el nombre de una lista; valida mientras escribes. Devuelve el nombre o null.
Future<String?> showPlaylistNameDialog(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String confirm,
  String initial = '',
  int? exceptId,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _PlaylistNameDialog(
        title: title,
        confirm: confirm,
        initial: initial,
        existing: ref.read(playlistsProvider),
        exceptId: exceptId,
      ),
    );

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({required this.title, required this.confirm, required this.initial, required this.existing, this.exceptId});
  final String title;
  final String confirm;
  final String initial;
  final List<Playlist> existing;
  final int? exceptId;

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;
  bool _touched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = playlistNameError(_controller.text, widget.existing, exceptId: widget.exceptId);
    if (error != null) {
      setState(() {
        _touched = true;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(normalizePlaylistName(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: maxPlaylistName,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: 'Nombre de la lista', errorText: _touched ? _error : null),
        onChanged: (v) {
          if (_touched) setState(() => _error = playlistNameError(v, widget.existing, exceptId: widget.exceptId));
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: Text(widget.confirm)),
      ],
    );
  }
}
