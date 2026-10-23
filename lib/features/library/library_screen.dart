import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../core/widgets.dart';
import '../../data/download_manager.dart';
import '../../data/folders.dart';
import '../../data/media_store.dart';
import '../../data/models.dart';
import '../../data/playlists.dart';
import '../../data/youtube_service.dart';
import '../../playback/audio_controller.dart';
import '../player/player_screen.dart';
import '../playlists/add_to_playlist.dart';
import '../playlists/playlist_screen.dart';
import '../watch/watch_screen.dart';
import 'collection_header.dart';
import 'library_model.dart';
import 'mixtape.dart';

export 'library_model.dart';

/// Agregar = queda también en sus otras carpetas. Mover = sale de la carpeta actual (o de todas).
enum FolderAction {
  add('Agregar a carpeta'),
  move('Mover a carpeta');

  const FolderAction(this.title);
  final String title;
}

/// Archivos descargados que siguen existiendo. Solo se recalcula cuando cambia el conjunto de
/// completadas (no en cada tic de progreso).
final libraryFilesProvider = FutureProvider<List<LibraryEntry>>((ref) async {
  ref.watch(downloadsProvider.select(
    (all) => all.where((t) => t.status == DownloadStatus.completed).map((t) => '${t.id}:${t.filePath}').join('|'),
  ));
  final completed = ref.read(downloadsProvider).where((t) => t.status == DownloadStatus.completed).toList()
    ..sort((a, b) => (b.completedAt ?? 0).compareTo(a.completedAt ?? 0));
  final out = <LibraryEntry>[];
  for (final t in completed) {
    final f = await fileOf(t);
    if (f != null) out.add((task: t, file: f));
  }
  return out;
});

/// Video para las listas a partir de un archivo descargado.
VideoSummary summaryOf(DownloadTask t) => VideoSummary(id: t.videoId, title: t.title, author: t.author);

/// "Tu biblioteca" (como Spotify): chips de filtro, orden, lista o cuadrícula; arriba lo fijado
/// (mixtape y descargas) y luego tus listas, carpetas y artistas. Dentro de una carpeta, un
/// artista o un filtro de Canciones/Videos se ven los archivos, con selección múltiple.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  static const _kSort = 'library_sort';
  static const _kGrid = 'library_grid';

  LibraryChip? _chip;
  LibrarySort _sort = LibrarySort.recent;
  bool _grid = false;
  int? _folderId;
  String? _artist;
  final Set<int> _selected = {};

  bool _searching = false;
  final _search = TextEditingController();

  bool get _selecting => _selected.isNotEmpty;
  String get _query => _searching ? _search.text : '';

  /// Se ven archivos (no colecciones): dentro de carpeta/artista o con chip Canciones/Videos.
  bool get _showsFiles => _folderId != null || _artist != null || (_chip?.showsFiles ?? false);

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _sort = LibrarySort.values.firstWhere((s) => s.name == p.getString(_kSort), orElse: () => LibrarySort.recent);
        _grid = p.getBool(_kGrid) ?? false;
      });
    } catch (_) {}
  }

  Future<void> _savePrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kSort, _sort.name);
      await p.setBool(_kGrid, _grid);
    } catch (_) {}
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ---- reproducir ----

  Future<void> _playAudio(List<LibraryEntry> items, int index, {bool shuffle = false}) async {
    if (items.isEmpty) return;
    try {
      await ref.read(audioControllerProvider).playFiles(items, startIndex: index, shuffle: shuffle);
      if (mounted) {
        await Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const PlayerScreen()));
      }
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  Future<void> _open(List<LibraryEntry> items, int index) async {
    final entry = items[index];
    if (!entry.task.kind.isAudio) {
      await ref.read(audioControllerProvider).player.pause();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LocalVideoScreen(entry: entry)));
    } else {
      // Solo los audios entran en la cola, para que "siguiente" no salte a un video.
      final audios = items.where((e) => e.task.kind.isAudio).toList();
      await _playAudio(audios, audios.indexOf(entry));
    }
  }

  /// Android: copia el archivo a Música/Video Downloader o Películas/Video Downloader.
  Future<void> _exportToMediaStore(LibraryEntry e) async {
    try {
      await MediaStoreSaver.save(file: e.file, task: e.task);
      if (mounted) {
        showMessage(context, e.task.kind.isAudio ? 'Guardado en Música › Video Downloader' : 'Guardado en Películas › Video Downloader');
      }
    } on AppException catch (err) {
      if (mounted) showMessage(context, err.message);
    }
  }

  // ---- crear ----

  Future<void> _createMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: const Text('Lista de reproducción'),
              subtitle: const Text('Canciones de YouTube o descargadas, en el orden que quieras'),
              onTap: () => Navigator.pop(c, 'playlist'),
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Carpeta'),
              subtitle: const Text('Para ordenar tus archivos descargados'),
              onTap: () => Navigator.pop(c, 'folder'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'folder') {
      await _createFolder();
    } else {
      final id = await showCreatePlaylistDialog(context, ref);
      if (id != null && mounted) await Navigator.of(context).push(playlistRoute(id));
    }
  }

  // ---- carpetas ----

  Future<String?> _askFolderName({required String title, String initial = '', int? renaming}) {
    final existing = ref.read(foldersProvider).folders.where((f) => f.id != renaming).map((f) => f.name).toList();
    return showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(title: title, initial: initial, validate: (name) => folderNameError(name, existing), maxLength: maxFolderName),
    );
  }

  Future<void> _createFolder({bool open = false}) async {
    final name = await _askFolderName(title: 'Nueva carpeta');
    if (name == null) return;
    try {
      final id = await ref.read(foldersProvider.notifier).create(name);
      if (open && mounted) setState(() => _folderId = id);
      if (mounted) showMessage(context, 'Carpeta creada');
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  Future<void> _pickFolder(FolderAction action, Set<int> ids) async {
    final folders = ref.read(foldersProvider);
    final choices = folders.folders.where((f) => action == FolderAction.add || f.id != _folderId).toList();
    final alreadyIn = action == FolderAction.add
        ? ids.map(folders.foldersOf).fold<Set<int>?>(null, (acc, s) => acc == null ? {...s} : acc.intersection(s)) ?? <int>{}
        : <int>{};
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Text(action.title + (ids.length > 1 ? ' (${ids.length})' : ''), style: Theme.of(c).textTheme.titleLarge),
              ),
              if (action == FolderAction.move)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text('Sale de su carpeta actual y queda solo en la que elijas.'),
                ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('Nueva carpeta'),
                onTap: () => Navigator.pop(c, -1),
              ),
              const Divider(),
              for (final f in choices)
                ListTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: Text(f.name),
                  subtitle: Text(alreadyIn.contains(f.id) ? 'Ya está en esta carpeta' : countLabel(folders.countOf(f.id))),
                  trailing: alreadyIn.contains(f.id) ? const Icon(Icons.check) : null,
                  enabled: !alreadyIn.contains(f.id),
                  onTap: () => Navigator.pop(c, f.id),
                ),
              if (choices.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Aún no tienes otras carpetas.')),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    var target = picked;
    final notifier = ref.read(foldersProvider.notifier);
    try {
      if (picked == -1) {
        final name = await _askFolderName(title: 'Nueva carpeta');
        if (name == null) return;
        target = await notifier.create(name);
      }
      if (action == FolderAction.add) {
        await notifier.add(target, ids);
      } else {
        await notifier.move(ids, fromFolderId: _folderId, toFolderId: target);
      }
      final name = ref.read(foldersProvider).folders.firstWhere((f) => f.id == target).name;
      if (!mounted) return;
      setState(_selected.clear);
      showMessage(context, '${countLabel(ids.length)} ${action == FolderAction.add ? 'agregado(s) a' : 'movido(s) a'} "$name"');
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  Future<void> _removeFromFolder(Set<int> ids) async {
    final id = _folderId;
    if (id == null) return;
    await ref.read(foldersProvider.notifier).remove(id, ids);
    if (!mounted) return;
    setState(_selected.clear);
    showMessage(context, 'Quitado(s) de la carpeta. Siguen en la biblioteca.');
  }

  Future<void> _renameFolder(LibraryFolder folder) async {
    final name = await _askFolderName(title: 'Renombrar carpeta', initial: folder.name, renaming: folder.id);
    if (name == null) return;
    try {
      await ref.read(foldersProvider.notifier).rename(folder.id, name);
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  Future<void> _deleteFolder(LibraryFolder folder) async {
    final ok = await _confirm('¿Eliminar carpeta?', 'Se eliminará "${folder.name}". Los archivos no se borran: siguen en la biblioteca.', 'Eliminar carpeta');
    if (!ok) return;
    setState(() => _folderId = null);
    await ref.read(foldersProvider.notifier).delete(folder.id);
  }

  // ---- listas ----

  Future<void> _renamePlaylist(Playlist p) async {
    final others = ref.read(playlistsProvider);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: 'Renombrar lista',
        initial: p.name,
        validate: (name) => playlistNameError(name, others, exceptId: p.id),
        maxLength: maxFolderName,
      ),
    );
    if (name == null) return;
    try {
      await ref.read(playlistsProvider.notifier).rename(p.id, name);
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  Future<void> _deletePlaylist(Playlist p) async {
    final ok = await _confirm('¿Eliminar lista?', 'Se eliminará "${p.name}". Las canciones descargadas no se borran.', 'Eliminar lista');
    if (ok) await ref.read(playlistsProvider.notifier).delete(p.id);
  }

  Future<void> _collectionMenu(LibraryCollection c, {Playlist? playlist, LibraryFolder? folder}) async {
    if (c.kind == CollectionKind.artist) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(c.title, style: Theme.of(s).textTheme.titleMedium), subtitle: Text(c.subtitle)),
            const Divider(),
            ListTile(leading: const Icon(Icons.drive_file_rename_outline), title: const Text('Renombrar'), onTap: () => Navigator.pop(s, 'rename')),
            ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Eliminar'), onTap: () => Navigator.pop(s, 'delete')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (playlist != null) {
      choice == 'rename' ? await _renamePlaylist(playlist) : await _deletePlaylist(playlist);
    } else if (folder != null) {
      choice == 'rename' ? await _renameFolder(folder) : await _deleteFolder(folder);
    }
  }

  // ---- archivos ----

  Future<void> _deleteFile(DownloadTask t) async {
    final ok = await _confirm('¿Eliminar archivo?', 'Se borrará "${t.title}" del teléfono. No se puede deshacer.', 'Eliminar');
    if (!ok) return;
    await ref.read(downloadsProvider.notifier).remove(t.id, deleteFile: true);
    if (mounted) showMessage(context, 'Archivo eliminado');
  }

  Future<void> _addToPlaylist(Iterable<DownloadTask> tasks) async {
    await showAddToPlaylistSheet(context, ref, [for (final t in tasks) summaryOf(t)]);
    if (mounted) setState(_selected.clear);
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
          ],
        ),
      ) ==
      true;

  void _toggle(int id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  void _back() => setState(() {
        if (_selecting) {
          _selected.clear();
        } else if (_searching) {
          _searching = false;
          _search.clear();
        } else if (_artist != null) {
          _artist = null;
        } else if (_folderId != null) {
          _folderId = null;
        } else {
          _chip = null;
        }
      });

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final files = ref.watch(libraryFilesProvider);
    final folders = ref.watch(foldersProvider);
    final playlists = ref.watch(playlistsProvider);
    final mixtape = ref.watch(mixtapeProvider).value ?? const <LibraryEntry>[];
    final all = files.value ?? const <LibraryEntry>[];
    final folder = folders.folders.where((f) => f.id == _folderId).firstOrNull;
    if (_folderId != null && folder == null && folders.folders.isNotEmpty) _folderId = null;

    // Archivos dentro del alcance actual (carpeta / artista / todo).
    var scope = all;
    if (_folderId != null) scope = scope.where((e) => folders.foldersOf(e.task.id).contains(_folderId)).toList();
    if (_artist != null) scope = scope.where((e) => artistOf(e.task) == _artist).toList();
    final fileChip = _folderId != null || _artist != null ? null : _chip;
    final visibleFiles = visibleEntries(scope, chip: fileChip, query: _query, sort: _sort);
    _selected.removeWhere((id) => !visibleFiles.any((e) => e.task.id == id));

    return PopScope(
      canPop: !_selecting && !_searching && _folderId == null && _artist == null && _chip == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: _appBar(folder, visibleFiles),
        body: files.isLoading && files.value == null
            ? const Center(child: CircularProgressIndicator())
            : _folderId != null || _artist != null
                ? _scopeView(folder, visibleFiles, folders)
                : _rootView(all, folders, playlists, mixtape, visibleFiles),
      ),
    );
  }

  PreferredSizeWidget _appBar(LibraryFolder? folder, List<LibraryEntry> visible) {
    if (_selecting) {
      final tasks = visible.where((e) => _selected.contains(e.task.id)).map((e) => e.task).toList();
      return AppBar(
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        leading: IconButton(tooltip: 'Cancelar selección', icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
        title: Text(_selected.length == 1 ? '1 seleccionado' : '${_selected.length} seleccionados'),
        actions: [
          IconButton(
            tooltip: 'Seleccionar todo',
            icon: const Icon(Icons.select_all),
            onPressed: () => setState(() => _selected.addAll(visible.map((e) => e.task.id))),
          ),
          IconButton(tooltip: 'Agregar a una lista', icon: const Icon(Icons.playlist_add_rounded), onPressed: () => _addToPlaylist(tasks)),
          IconButton(
            tooltip: 'Agregar a carpeta',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => _pickFolder(FolderAction.add, {..._selected}),
          ),
          IconButton(
            tooltip: 'Mover a carpeta',
            icon: const Icon(Icons.drive_file_move_outline),
            onPressed: () => _pickFolder(FolderAction.move, {..._selected}),
          ),
          if (_folderId != null)
            IconButton(
              tooltip: 'Quitar de la carpeta',
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => _removeFromFolder({..._selected}),
            ),
        ],
      );
    }
    if (_searching) {
      return AppBar(
        leading: IconButton(tooltip: 'Cerrar búsqueda', icon: const Icon(Icons.arrow_back), onPressed: _back),
        title: TextField(
          controller: _search,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: 'Buscar en tu biblioteca', border: InputBorder.none),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          if (_search.text.isNotEmpty)
            IconButton(tooltip: 'Borrar', icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
        ],
      );
    }
    if (folder != null) {
      return AppBar(
        leading: IconButton(tooltip: 'Volver', icon: const Icon(Icons.arrow_back), onPressed: _back),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Opciones de la carpeta',
            onSelected: (v) => v == 'rename' ? _renameFolder(folder) : _deleteFolder(folder),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.drive_file_rename_outline), title: Text('Renombrar'))),
              PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Eliminar carpeta'))),
            ],
          ),
        ],
      );
    }
    if (_artist != null) {
      return AppBar(leading: IconButton(tooltip: 'Volver', icon: const Icon(Icons.arrow_back), onPressed: _back));
    }
    return AppBar(
      centerTitle: false,
      title: const Text('Tu biblioteca'),
      actions: [
        IconButton(tooltip: 'Buscar en tu biblioteca', icon: const Icon(Icons.search_rounded), onPressed: () => setState(() => _searching = true)),
        IconButton(tooltip: 'Crear lista o carpeta', icon: const Icon(Icons.add_rounded), onPressed: _createMenu),
      ],
    );
  }

  /// Chips (con ✕ para quitar el filtro, como Spotify) y la fila de orden / vista.
  Widget _filters({required bool collections}) {
    final scheme = Theme.of(context).colorScheme;
    final chip = _chip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              if (chip != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton.filledTonal(
                    tooltip: 'Quitar filtro',
                    style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() => _chip = null),
                  ),
                ),
              for (final c in chip == null ? LibraryChip.values : [chip])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c.label),
                    selected: _chip == c,
                    onSelected: (on) => setState(() {
                      _chip = on ? c : null;
                      _selected.clear();
                    }),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Row(
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: scheme.onSurface),
                onPressed: () {
                  setState(() => _sort = _sort.next);
                  _savePrefs();
                },
                icon: const Icon(Icons.swap_vert_rounded, size: 20),
                label: Text(_sort.label),
              ),
              const Spacer(),
              if (collections)
                IconButton(
                  tooltip: _grid ? 'Ver como lista' : 'Ver como cuadrícula',
                  icon: Icon(_grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
                  onPressed: () {
                    setState(() => _grid = !_grid);
                    _savePrefs();
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rootView(
    List<LibraryEntry> all,
    FoldersState folders,
    List<Playlist> playlists,
    List<LibraryEntry> mixtape,
    List<LibraryEntry> visibleFiles,
  ) {
    if (all.isEmpty && folders.folders.isEmpty && playlists.isEmpty && mixtape.isEmpty && !_searching) {
      return ListView(
        children: [
          _pinnedMixtape(mixtape),
          EmptyState(
            icon: Icons.library_music_outlined,
            title: 'Tu biblioteca está vacía',
            message: Platform.isIOS
                ? 'Crea una lista con +, o descarga algo: aparece aquí y en la app Archivos (En mi iPhone → Video Downloader).'
                : 'Crea una lista con +, o descarga algo para escucharlo aquí sin internet.',
          ),
        ],
      );
    }

    final playlistById = {for (final p in playlists) p.id: p};
    final folderById = {for (final f in folders.folders) f.id: f};
    final playlistItems = [
      for (final p in playlists)
        (
          kind: CollectionKind.playlist,
          id: p.id,
          title: p.name,
          subtitle: 'Lista · ${countLabel(p.count, one: 'canción', many: 'canciones')}',
          creator: 'Tú',
          recency: p.updatedAt,
          coverIds: p.coverVideoIds,
        ),
    ];
    final folderItems = [
      for (final f in folders.folders) folderCollection(f, all.where((e) => folders.foldersOf(e.task.id).contains(f.id)).toList()),
    ];
    final artistItems = [for (final g in groupByArtist(all)) artistCollection(g.artist, g.items)];
    final collections = visibleCollections(
      playlists: playlistItems,
      folders: folderItems,
      artists: artistItems,
      chip: _chip,
      sort: _sort,
      query: _query,
    );
    final thumbs = {for (final e in all) if (e.task.thumbnail != null) e.task.videoId: e.task.thumbnail!};
    final showFiles = (_chip?.showsFiles ?? false) || _query.trim().isNotEmpty;
    final pinned = _chip == null && _query.trim().isEmpty;
    final songs = all.where((e) => e.task.kind.isAudio).toList();
    final videos = all.where((e) => !e.task.kind.isAudio).toList();

    Widget collectionTile(LibraryCollection c) {
      final playlist = c.kind == CollectionKind.playlist ? playlistById[c.id] : null;
      final folder = c.kind == CollectionKind.folder ? folderById[c.id] : null;
      void open() {
        switch (c.kind) {
          case CollectionKind.playlist:
            Navigator.of(context).push(playlistRoute(c.id!));
          case CollectionKind.folder:
            setState(() => _folderId = c.id);
          case CollectionKind.artist:
            setState(() => _artist = c.title);
        }
      }

      final art = playlist != null
          ? PlaylistCover(playlist: playlist, size: _grid ? 400 : 64)
          : CoverMosaic(
              videoIds: c.coverIds,
              size: _grid ? 400 : 64,
              circle: c.kind == CollectionKind.artist,
              icon: c.kind == CollectionKind.artist ? Icons.person_rounded : Icons.folder_rounded,
              fallbackUrls: thumbs,
            );
      return _grid
          ? _GridTile(art: art, title: c.title, subtitle: c.subtitle, circle: c.kind == CollectionKind.artist, onTap: open,
              onLongPress: () => _collectionMenu(c, playlist: playlist, folder: folder))
          : _ListTile(art: art, title: c.title, subtitle: c.subtitle, onTap: open,
              onLongPress: () => _collectionMenu(c, playlist: playlist, folder: folder));
    }

    final pinnedTiles = <Widget>[
      if (pinned) _pinnedMixtape(mixtape),
      if (pinned && songs.isNotEmpty)
        _ListTile(
          art: CoverMosaic(videoIds: [for (final e in songs.take(4)) e.task.videoId], size: 64, icon: Icons.music_note_rounded, fallbackUrls: thumbs),
          title: 'Canciones descargadas',
          subtitle: 'Fijado · ${countLabel(songs.length, one: 'canción', many: 'canciones')}',
          pinned: true,
          onTap: () => setState(() => _chip = LibraryChip.songs),
        ),
      if (pinned && videos.isNotEmpty)
        _ListTile(
          art: CoverMosaic(videoIds: [for (final e in videos.take(4)) e.task.videoId], size: 64, icon: Icons.movie_rounded, fallbackUrls: thumbs),
          title: 'Videos descargados',
          subtitle: 'Fijado · ${countLabel(videos.length, one: 'video', many: 'videos')}',
          pinned: true,
          onTap: () => setState(() => _chip = LibraryChip.videos),
        ),
    ];

    final width = MediaQuery.sizeOf(context).width;
    return CustomScrollView(
      slivers: [
        if (!_searching) SliverToBoxAdapter(child: _filters(collections: !(_chip?.showsFiles ?? false))),
        SliverList.list(children: pinnedTiles),
        if (collections.isNotEmpty)
          _grid
              ? SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  sliver: SliverGrid.count(
                    crossAxisCount: width >= 600 ? 4 : 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.72,
                    children: [for (final c in collections) collectionTile(c)],
                  ),
                )
              : SliverList.list(children: [for (final c in collections) collectionTile(c)]),
        if (showFiles) ...[
          if (_query.trim().isNotEmpty && visibleFiles.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Archivos', style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
          SliverList.builder(itemCount: visibleFiles.length, itemBuilder: (_, i) => _fileRow(visibleFiles, i)),
        ],
        if (collections.isEmpty && (!showFiles || visibleFiles.isEmpty) && !pinned)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _query.trim().isNotEmpty ? 'Nada coincide con "${_query.trim()}".' : _emptyChipMessage(),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  String _emptyChipMessage() => switch (_chip) {
        LibraryChip.playlists => 'Aún no tienes listas. Crea una con + o con "Guardar" en un video.',
        LibraryChip.folders => 'Aún no tienes carpetas. Crea una con +.',
        LibraryChip.artists => 'Los artistas aparecen cuando descargas canciones.',
        LibraryChip.songs => 'No hay canciones descargadas.',
        LibraryChip.videos => 'No hay videos descargados.',
        null => '',
      };

  Widget _pinnedMixtape(List<LibraryEntry> mixtape) => _ListTile(
        art: const MixtapeArt(size: 64),
        title: 'Tu mixtape sin conexión',
        subtitle: 'Fijado · ${mixtape.isEmpty ? 'se llena solo con lo que escuchas' : countLabel(mixtape.length, one: 'canción', many: 'canciones')}',
        pinned: true,
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MixtapeScreen())),
        trailing: mixtape.isEmpty
            ? null
            : IconButton(
                tooltip: 'Mixtape en aleatorio',
                icon: const Icon(Icons.shuffle_rounded),
                onPressed: () => playMixtape(context, ref, shuffle: true),
              ),
      );

  /// Dentro de una carpeta o de un artista: cabecera estilo Spotify y sus archivos.
  Widget _scopeView(LibraryFolder? folder, List<LibraryEntry> visible, FoldersState folders) {
    final audios = visible.where((e) => e.task.kind.isAudio).toList();
    final artist = _artist;
    final ids = [for (final e in visible.take(4)) e.task.videoId];
    final thumbs = {for (final e in visible) if (e.task.thumbnail != null) e.task.videoId: e.task.thumbnail!};
    final header = CollectionHeader(
      art: CoverMosaic(
        videoIds: ids,
        size: 180,
        circle: artist != null,
        icon: artist != null ? Icons.person_rounded : Icons.folder_rounded,
        fallbackUrls: thumbs,
      ),
      toneVideoId: ids.isEmpty ? null : ids.first,
      title: artist ?? folder?.name ?? '',
      subtitle: [
        artist != null ? 'Artista' : 'Carpeta',
        countLabel(visible.length),
      ].join(' · '),
      onShuffle: audios.isEmpty ? null : () => _playAudio(audios, 0, shuffle: true),
      onPlay: audios.isEmpty ? null : () => _playAudio(audios, 0),
      actions: [
        TextButton.icon(
          onPressed: () {
            setState(() => _sort = _sort.next);
            _savePrefs();
          },
          icon: const Icon(Icons.swap_vert_rounded, size: 20),
          label: Text(_sort.label),
        ),
      ],
    );
    return ListView(
      children: [
        header,
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(folder != null
                ? 'Esta carpeta está vacía. En Canciones o Videos, abre ⋮ en un archivo (o mantenlo presionado para elegir varios) y usa "Agregar a carpeta".'
                : 'No hay archivos de este artista.'),
          ),
        for (var i = 0; i < visible.length; i++) _fileRow(visible, i),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _fileRow(List<LibraryEntry> visible, int i) {
    final e = visible[i];
    final t = e.task;
    final folders = ref.read(foldersProvider);
    final selected = _selected.contains(t.id);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final names = _folderId == null ? folders.namesOf(t.id) : const <String>[];
    final details = [
      t.kind.isAudio ? 'Canción' : 'Video',
      if (!t.kind.isAudio && t.qualityLabel != null) t.qualityLabel!,
      if (t.author.isNotEmpty) artistOf(t),
    ].join(' · ');

    return Material(
      color: selected ? scheme.secondaryContainer.withValues(alpha: 0.6) : Colors.transparent,
      child: InkWell(
        onLongPress: () => _toggle(t.id),
        onTap: _selecting ? () => _toggle(t.id) : () => _open(visible, i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              if (_selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(selected ? Icons.check_circle : Icons.circle_outlined, color: selected ? scheme.primary : scheme.outline),
                ),
              // Canciones: portada cuadrada; videos: miniatura 16:9 con ▶ (como en Spotify).
              t.kind.isAudio
                  ? SizedBox(width: 52, height: 52, child: LocalCover(videoId: t.videoId, radius: 4, fallbackUrl: t.thumbnail))
                  : SizedBox(
                      width: 92,
                      height: 52,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          LocalCover(videoId: t.videoId, radius: 4, fallbackUrl: t.thumbnail),
                          const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 22)),
                        ],
                      ),
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (t.isMixtape) ...[
                          Icon(Icons.offline_bolt_rounded, size: 14, color: scheme.primary, semanticLabel: 'Mixtape'),
                          const SizedBox(width: 4),
                        ] else ...[
                          Icon(Icons.download_done_rounded, size: 14, color: scheme.primary, semanticLabel: 'Descargado'),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        ),
                      ],
                    ),
                    if (names.isNotEmpty)
                      Text(
                        names.join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelSmall?.copyWith(color: scheme.primary),
                      ),
                  ],
                ),
              ),
              if (!_selecting) _fileMenu(e),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fileMenu(LibraryEntry e) {
    final t = e.task;
    return PopupMenuButton<String>(
      tooltip: 'Opciones',
      onSelected: (action) {
        switch (action) {
          case 'playlist':
            _addToPlaylist([t]);
          case 'add':
            _pickFolder(FolderAction.add, {t.id});
          case 'move':
            _pickFolder(FolderAction.move, {t.id});
          case 'remove':
            _removeFromFolder({t.id});
          case 'listen':
            _playAudio([e], 0);
          case 'watch':
            openWatch(context, t.videoId);
          case 'keep':
            ref.read(downloadsProvider.notifier).keep(t.id).then((_) {
              if (mounted) showMessage(context, 'Fijada en la Biblioteca: ya no se borrará sola.');
            });
          case 'share':
            SharePlus.instance.share(ShareParams(files: [XFile(e.file.path)]));
          case 'export':
            _exportToMediaStore(e);
          case 'delete':
            _deleteFile(t);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'playlist', child: ListTile(leading: Icon(Icons.playlist_add_rounded), title: Text('Agregar a una lista'))),
        const PopupMenuItem(value: 'add', child: ListTile(leading: Icon(Icons.create_new_folder_outlined), title: Text('Agregar a carpeta'))),
        const PopupMenuItem(value: 'move', child: ListTile(leading: Icon(Icons.drive_file_move_outline), title: Text('Mover a carpeta'))),
        if (_folderId != null)
          const PopupMenuItem(value: 'remove', child: ListTile(leading: Icon(Icons.remove_circle_outline), title: Text('Quitar de la carpeta'))),
        const PopupMenuDivider(),
        if (!t.kind.isAudio)
          const PopupMenuItem(value: 'listen', child: ListTile(leading: Icon(Icons.headphones), title: Text('Escuchar solo el audio'))),
        // Los enlaces directos (Internet Archive, archivos sueltos) no son de YouTube.
        if (!t.isDirect)
          const PopupMenuItem(value: 'watch', child: ListTile(leading: Icon(Icons.smart_display_outlined), title: Text('Ver en YouTube (streaming)'))),
        if (t.isMixtape)
          const PopupMenuItem(value: 'keep', child: ListTile(leading: Icon(Icons.push_pin_outlined), title: Text('Fijar (no borrar sola)'))),
        const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share), title: Text('Compartir'))),
        if (MediaStoreSaver.isSupported)
          PopupMenuItem(
            value: 'export',
            child: ListTile(
              leading: Icon(t.kind.isAudio ? Icons.library_music_outlined : Icons.video_library_outlined),
              title: Text(t.kind.isAudio ? 'Guardar en Música' : 'Guardar en Películas'),
            ),
          ),
        const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Eliminar del teléfono'))),
      ],
    );
  }
}

/// Fila de colección (lista, carpeta, artista o fijado), como en Spotify.
class _ListTile extends StatelessWidget {
  const _ListTile({
    required this.art,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
    this.pinned = false,
    this.trailing,
  });

  final Widget art;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool pinned;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 64, height: 64, child: art),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (pinned) ...[
                        Icon(Icons.push_pin_rounded, size: 14, color: scheme.primary, semanticLabel: 'Fijado'),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          pinned ? subtitle.replaceFirst('Fijado · ', '') : subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// Celda de la cuadrícula: portada cuadrada (redonda para artistas), título y detalle.
class _GridTile extends StatelessWidget {
  const _GridTile({required this.art, required this.title, required this.subtitle, required this.onTap, this.onLongPress, this.circle = false});
  final Widget art;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: circle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          AspectRatio(aspectRatio: 1, child: FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox(width: 400, height: 400, child: art))),
          const SizedBox(height: 8),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall, textAlign: circle ? TextAlign.center : TextAlign.start),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: circle ? TextAlign.center : TextAlign.start,
          ),
        ],
      ),
    );
  }
}

/// Diálogo para el nombre de una carpeta o lista, con validación en vivo.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial, required this.validate, required this.maxLength});
  final String title;
  final String initial;
  final String? Function(String name) validate;
  final int maxLength;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  bool _touched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.validate(_controller.text);
    void submit() {
      setState(() => _touched = true);
      if (error == null) Navigator.pop(context, normalizeFolderName(_controller.text));
    }

    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        maxLength: widget.maxLength,
        decoration: InputDecoration(labelText: 'Nombre', errorText: _touched ? error : null),
        onChanged: (_) => setState(() => _touched = true),
        onSubmitted: (_) => submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(onPressed: error == null ? submit : null, child: Text(widget.initial.isEmpty ? 'Crear' : 'Guardar')),
      ],
    );
  }
}

/// Video descargado, con los mismos controles que "ver video" y pantalla completa.
class LocalVideoScreen extends StatefulWidget {
  const LocalVideoScreen({super.key, required this.entry});
  final LibraryEntry entry;

  @override
  State<LocalVideoScreen> createState() => _LocalVideoScreenState();
}

class _LocalVideoScreenState extends State<LocalVideoScreen> {
  late final VideoPlayerController _c = VideoPlayerController.file(widget.entry.file);

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _c.play();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.entry.task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: !_c.value.isInitialized
            ? const CircularProgressIndicator()
            : AspectRatio(
                aspectRatio: 16 / 9,
                child: VideoSurface(
                  controller: _c,
                  onFullscreen: () => Navigator.of(context).push(PageRouteBuilder<void>(
                    pageBuilder: (_, __, ___) => FullscreenVideo(controller: _c),
                    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
                  )),
                ),
              ),
      ),
    );
  }
}
