import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'database.dart';
import 'models.dart';
import 'youtube_service.dart';

/// Listas de reproducción propias: videos de YouTube en el orden que quieras. Suenan por
/// streaming o, si ya están descargados (o en el mixtape), desde el archivo.
@immutable
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.count,
    required this.coverVideoIds,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final int count;

  /// Hasta 4 videoId (los primeros de la lista), para el mosaico de la portada.
  final List<String> coverVideoIds;

  /// Milisegundos desde epoch.
  final int createdAt;
  final int updatedAt;
}

@immutable
class PlaylistItem {
  const PlaylistItem({required this.id, required this.playlistId, required this.position, required this.video, required this.addedAt});

  final int id;
  final int playlistId;
  final int position;
  final VideoSummary video;
  final int addedAt;

  static PlaylistItem fromRow(Map<String, Object?> r) => PlaylistItem(
        id: r['id']! as int,
        playlistId: r['playlist_id']! as int,
        position: (r['position'] as int?) ?? 0,
        addedAt: (r['added_at'] as int?) ?? 0,
        video: VideoSummary(
          id: r['video_id']! as String,
          title: (r['title'] as String?) ?? '',
          author: (r['author'] as String?) ?? '',
          channelId: r['channel_id'] as String?,
          duration: (r['duration_ms'] as int?) == null ? null : Duration(milliseconds: r['duration_ms']! as int),
        ),
      );
}

/// Fila de la base para un video de la lista.
Map<String, Object?> playlistItemRow(VideoSummary v) => {
      'video_id': v.id,
      'title': v.title,
      'author': v.author,
      'channel_id': v.channelId,
      'duration_ms': v.duration?.inMilliseconds,
    };

const maxPlaylistName = 60;

String normalizePlaylistName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

/// null si el nombre sirve; si no, el motivo (como en las carpetas).
String? playlistNameError(String name, List<Playlist> existing, {int? exceptId}) {
  final n = normalizePlaylistName(name);
  if (n.isEmpty) return 'Escribe un nombre.';
  if (n.length > maxPlaylistName) return 'Máximo $maxPlaylistName caracteres.';
  final lower = n.toLowerCase();
  if (existing.any((p) => p.id != exceptId && p.name.toLowerCase() == lower)) return 'Ya tienes una lista con ese nombre.';
  return null;
}

/// Nuevo orden de los ids al mover el elemento [from] a la posición [to] (índices ya ajustados:
/// [to] es la posición final del elemento).
List<int> reorderedIds(List<int> ids, int from, int to) {
  if (from < 0 || from >= ids.length) return List.of(ids);
  final out = List.of(ids);
  final moved = out.removeAt(from);
  out.insert(to.clamp(0, out.length), moved);
  return out;
}

/// Duración total de la lista (las que no tienen duración no cuentan).
Duration totalDuration(Iterable<PlaylistItem> items) =>
    items.fold(Duration.zero, (sum, i) => sum + (i.video.duration ?? Duration.zero));

class PlaylistsNotifier extends Notifier<List<Playlist>> {
  AppDatabase? _db;

  @override
  List<Playlist> build() {
    unawaited(_reload());
    return const [];
  }

  Future<AppDatabase> _database() async {
    final cached = _db;
    if (cached != null) return cached;
    final AppDatabase db = await ref.read(databaseProvider.future);
    return _db = db;
  }

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  Future<void> _reload() async {
    final db = await _database();
    final rows = await db.playlistRows();
    final lists = <Playlist>[
      for (final r in rows)
        Playlist(
          id: r['id']! as int,
          name: r['name']! as String,
          count: (r['item_count'] as int?) ?? 0,
          coverVideoIds: await db.playlistCoverIds(r['id']! as int),
          createdAt: (r['created_at'] as int?) ?? 0,
          updatedAt: (r['updated_at'] as int?) ?? 0,
        ),
    ];
    if (!ref.mounted) return;
    state = lists;
  }

  void _changed(int id) {
    ref.invalidate(playlistItemsProvider(id));
  }

  /// Crea la lista (con [videos] si se dan) y devuelve su id. Lanza [AppException] si el nombre
  /// no sirve.
  Future<int> create(String name, {List<VideoSummary> videos = const []}) async {
    final error = playlistNameError(name, state);
    if (error != null) throw AppException(error);
    final db = await _database();
    final now = _now;
    final id = await db.createPlaylist(normalizePlaylistName(name), now);
    if (videos.isNotEmpty) await db.addPlaylistItems(id, [for (final v in videos) playlistItemRow(v)], now);
    await _reload();
    _changed(id);
    return id;
  }

  Future<void> rename(int id, String name) async {
    final error = playlistNameError(name, state, exceptId: id);
    if (error != null) throw AppException(error);
    await (await _database()).renamePlaylist(id, normalizePlaylistName(name), _now);
    await _reload();
  }

  Future<void> delete(int id) async {
    await (await _database()).deletePlaylist(id);
    await _reload();
    _changed(id);
  }

  /// Agrega al final los que no estén ya en la lista. Devuelve cuántos agregó.
  Future<int> addVideos(int id, List<VideoSummary> videos) async {
    if (videos.isEmpty) return 0;
    final added = await (await _database()).addPlaylistItems(id, [for (final v in videos) playlistItemRow(v)], _now);
    await _reload();
    _changed(id);
    return added;
  }

  Future<void> removeItem(int playlistId, int itemId) async {
    await (await _database()).removePlaylistItem(playlistId, itemId, _now);
    await _reload();
    _changed(playlistId);
  }

  /// Mueve el elemento de la posición [from] a la [to] (posición final, ya ajustada).
  Future<void> move(int playlistId, int from, int to) async {
    final db = await _database();
    final current = [for (final r in await db.playlistItemRows(playlistId)) r['id']! as int];
    await db.reorderPlaylist(playlistId, reorderedIds(current, from, to), _now);
    await _reload();
    _changed(playlistId);
  }

  Future<List<PlaylistItem>> items(int id) async =>
      [for (final r in await (await _database()).playlistItemRows(id)) PlaylistItem.fromRow(r)];
}

final playlistsProvider = NotifierProvider<PlaylistsNotifier, List<Playlist>>(PlaylistsNotifier.new);

/// Canciones de una lista, en orden. Se invalida sola cada vez que la lista cambia.
final playlistItemsProvider = FutureProvider.family<List<PlaylistItem>, int>(
  (ref, id) => ref.read(playlistsProvider.notifier).items(id),
);
