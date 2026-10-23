import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Base de datos local (SQLite). Solo en el teléfono; no se sincroniza con nada.
///
/// Versiones:
/// - v1: descargas.
/// - v2: historial de reproducción, carpetas de la biblioteca y pertenencias.
/// - v3: marca de "mixtape" (audio guardado automáticamente de lo que escuchas).
/// - v4: enlaces directos y volumen de cada canción.
/// - v5: listas de reproducción propias.
class AppDatabase {
  AppDatabase._(this._db);
  final Database _db;

  static const _name = 'video_downloader.db';
  static const _version = 5;

  static Future<AppDatabase> open() async {
    final db = await openDatabase(
      p.join(await getDatabasesPath(), _name),
      version: _version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await _createV1(db);
        await _createV2(db);
        await _createV3(db);
        await _createV4(db);
        await _createV5(db);
      },
      onUpgrade: (db, from, to) async {
        if (from < 2) await _createV2(db);
        if (from < 3) await _createV3(db);
        if (from < 4) await _createV4(db);
        if (from < 5) await _createV5(db);
      },
    );
    return AppDatabase._(db);
  }

  static Future<void> _createV1(Database db) async {
    await db.execute('''
      CREATE TABLE downloads (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        video_id TEXT NOT NULL,
        title TEXT NOT NULL,
        author TEXT,
        kind TEXT NOT NULL,
        tag INTEGER NOT NULL,
        file_name TEXT NOT NULL,
        status TEXT NOT NULL,
        downloaded_bytes INTEGER NOT NULL DEFAULT 0,
        total_bytes INTEGER,
        error TEXT,
        file_path TEXT,
        created_at INTEGER NOT NULL,
        completed_at INTEGER
      )''');
    await db.execute('CREATE INDEX idx_downloads_status ON downloads(status)');
    await db.execute('CREATE INDEX idx_downloads_video ON downloads(video_id, tag)');
  }

  static Future<void> _createV2(Database db) async {
    // Columnas nuevas de descargas: pista de audio aparte (MP4 HD) y calidad elegida.
    await db.execute('ALTER TABLE downloads ADD COLUMN audio_tag INTEGER');
    await db.execute('ALTER TABLE downloads ADD COLUMN quality_label TEXT');
    await db.execute('''
      CREATE TABLE watch_history (
        video_id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        author TEXT,
        channel_id TEXT,
        duration_ms INTEGER,
        position_ms INTEGER NOT NULL DEFAULT 0,
        watched_at INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_history_watched ON watch_history(watched_at)');
    await db.execute('''
      CREATE TABLE library_folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE folder_items (
        folder_id INTEGER NOT NULL REFERENCES library_folders(id) ON DELETE CASCADE,
        download_id INTEGER NOT NULL REFERENCES downloads(id) ON DELETE CASCADE,
        added_at INTEGER NOT NULL,
        PRIMARY KEY (folder_id, download_id)
      )''');
    await db.execute('CREATE INDEX idx_folder_items_download ON folder_items(download_id)');
  }

  static Future<void> _createV3(Database db) async {
    await db.execute('ALTER TABLE downloads ADD COLUMN auto_mixtape INTEGER NOT NULL DEFAULT 0');
  }

  /// v4: enlaces directos (Internet Archive, .mp4/.mp3) y volumen de cada canción.
  static Future<void> _createV4(Database db) async {
    await db.execute('ALTER TABLE downloads ADD COLUMN source_url TEXT');
    await db.execute('ALTER TABLE downloads ADD COLUMN thumbnail TEXT');
    await db.execute('ALTER TABLE downloads ADD COLUMN loudness_db REAL');
  }

  /// v5: listas de reproducción propias (videos de YouTube; suenan desde el archivo si ya está
  /// descargado).
  static Future<void> _createV5(Database db) async {
    await db.execute('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at INTEGER,
        updated_at INTEGER
      )''');
    await db.execute('''
      CREATE TABLE playlist_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        video_id TEXT NOT NULL,
        title TEXT,
        author TEXT,
        channel_id TEXT,
        duration_ms INTEGER,
        added_at INTEGER
      )''');
    await db.execute('CREATE INDEX idx_playlist_items_order ON playlist_items(playlist_id, position)');
  }

  // ---- descargas ----

  Future<List<DownloadTask>> all() async =>
      (await _db.query('downloads', orderBy: 'created_at DESC')).map(DownloadTask.fromRow).toList();

  Future<int> insert(DownloadTask t) => _db.insert('downloads', t.toRow()..remove('id'));

  Future<void> update(DownloadTask t) => _db.update('downloads', t.toRow(), where: 'id = ?', whereArgs: [t.id]);

  Future<void> delete(int id) => _db.delete('downloads', where: 'id = ?', whereArgs: [id]);

  // ---- historial ----

  Future<List<WatchHistoryEntry>> history({int limit = 500}) async =>
      (await _db.query('watch_history', orderBy: 'watched_at DESC', limit: limit)).map(WatchHistoryEntry.fromRow).toList();

  Future<WatchHistoryEntry?> historyEntry(String videoId) async {
    final rows = await _db.query('watch_history', where: 'video_id = ?', whereArgs: [videoId], limit: 1);
    return rows.isEmpty ? null : WatchHistoryEntry.fromRow(rows.first);
  }

  Future<void> upsertHistory(WatchHistoryEntry e) =>
      _db.insert('watch_history', e.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> updatePosition(String videoId, int positionMs) =>
      _db.update('watch_history', {'position_ms': positionMs}, where: 'video_id = ?', whereArgs: [videoId]);

  Future<void> deleteHistory(String videoId) => _db.delete('watch_history', where: 'video_id = ?', whereArgs: [videoId]);

  Future<void> clearHistory() => _db.delete('watch_history');

  /// Conserva solo las [keep] entradas más recientes.
  Future<void> trimHistory(int keep) => _db.rawDelete(
        'DELETE FROM watch_history WHERE video_id NOT IN (SELECT video_id FROM watch_history ORDER BY watched_at DESC LIMIT ?)',
        [keep],
      );

  // ---- carpetas ----

  Future<List<LibraryFolder>> folders() async =>
      (await _db.query('library_folders', orderBy: 'name COLLATE NOCASE')).map(LibraryFolder.fromRow).toList();

  /// downloadId → carpetas en las que está.
  Future<Map<int, Set<int>>> memberships() async {
    final rows = await _db.query('folder_items', orderBy: 'added_at DESC');
    final out = <int, Set<int>>{};
    for (final r in rows) {
      out.putIfAbsent(r['download_id']! as int, () => <int>{}).add(r['folder_id']! as int);
    }
    return out;
  }

  Future<int> createFolder(String name) =>
      _db.insert('library_folders', {'name': name, 'created_at': DateTime.now().millisecondsSinceEpoch});

  Future<void> renameFolder(int id, String name) =>
      _db.update('library_folders', {'name': name}, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteFolder(int id) => _db.transaction((tx) async {
        await tx.delete('folder_items', where: 'folder_id = ?', whereArgs: [id]);
        await tx.delete('library_folders', where: 'id = ?', whereArgs: [id]);
      });

  Future<void> addToFolder(int folderId, Iterable<int> downloadIds) => _db.transaction((tx) async {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final id in downloadIds) {
          await tx.insert('folder_items', {'folder_id': folderId, 'download_id': id, 'added_at': now},
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      });

  /// Mueve a [toFolderId]: desde [fromFolderId], o desde todas sus carpetas si es null.
  Future<void> moveToFolder(Iterable<int> downloadIds, {int? fromFolderId, required int toFolderId}) =>
      _db.transaction((tx) async {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final id in downloadIds) {
          if (fromFolderId == null) {
            await tx.delete('folder_items', where: 'download_id = ?', whereArgs: [id]);
          } else {
            await tx.delete('folder_items', where: 'folder_id = ? AND download_id = ?', whereArgs: [fromFolderId, id]);
          }
          await tx.insert('folder_items', {'folder_id': toFolderId, 'download_id': id, 'added_at': now},
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      });

  Future<void> removeFromFolder(int folderId, Iterable<int> downloadIds) => _db.transaction((tx) async {
        for (final id in downloadIds) {
          await tx.delete('folder_items', where: 'folder_id = ? AND download_id = ?', whereArgs: [folderId, id]);
        }
      });

  // ---- listas de reproducción ----

  /// Listas con su número de canciones y hasta 4 videoId (los primeros) para la portada.
  Future<List<Map<String, Object?>>> playlistRows() => _db.rawQuery('''
      SELECT p.id, p.name, p.created_at, p.updated_at,
             (SELECT COUNT(*) FROM playlist_items i WHERE i.playlist_id = p.id) AS item_count
      FROM playlists p
      ORDER BY p.updated_at DESC, p.id DESC''');

  Future<List<String>> playlistCoverIds(int playlistId, {int limit = 4}) async => [
        for (final r in await _db.query('playlist_items',
            columns: ['video_id'], where: 'playlist_id = ?', whereArgs: [playlistId], orderBy: 'position', limit: limit))
          r['video_id']! as String,
      ];

  Future<int> createPlaylist(String name, int now) =>
      _db.insert('playlists', {'name': name, 'created_at': now, 'updated_at': now});

  Future<void> renamePlaylist(int id, String name, int now) =>
      _db.update('playlists', {'name': name, 'updated_at': now}, where: 'id = ?', whereArgs: [id]);

  Future<void> deletePlaylist(int id) => _db.transaction((tx) async {
        await tx.delete('playlist_items', where: 'playlist_id = ?', whereArgs: [id]);
        await tx.delete('playlists', where: 'id = ?', whereArgs: [id]);
      });

  Future<List<Map<String, Object?>>> playlistItemRows(int playlistId) =>
      _db.query('playlist_items', where: 'playlist_id = ?', whereArgs: [playlistId], orderBy: 'position, id');

  /// Agrega al final los videos que aún no están en la lista. Devuelve cuántos agregó.
  Future<int> addPlaylistItems(int playlistId, List<Map<String, Object?>> rows, int now) => _db.transaction((tx) async {
        final existing = {
          for (final r in await tx.query('playlist_items', columns: ['video_id'], where: 'playlist_id = ?', whereArgs: [playlistId]))
            r['video_id']! as String,
        };
        final last = await tx.rawQuery('SELECT MAX(position) AS m FROM playlist_items WHERE playlist_id = ?', [playlistId]);
        var position = ((last.first['m'] as int?) ?? -1) + 1;
        var added = 0;
        for (final r in rows) {
          final id = r['video_id']! as String;
          if (!existing.add(id)) continue;
          await tx.insert('playlist_items', {...r, 'playlist_id': playlistId, 'position': position++, 'added_at': now});
          added++;
        }
        if (added > 0) await tx.update('playlists', {'updated_at': now}, where: 'id = ?', whereArgs: [playlistId]);
        return added;
      });

  Future<void> removePlaylistItem(int playlistId, int itemId, int now) => _db.transaction((tx) async {
        await tx.delete('playlist_items', where: 'id = ? AND playlist_id = ?', whereArgs: [itemId, playlistId]);
        await tx.update('playlists', {'updated_at': now}, where: 'id = ?', whereArgs: [playlistId]);
      });

  /// Guarda el nuevo orden: [orderedItemIds] de la primera a la última.
  Future<void> reorderPlaylist(int playlistId, List<int> orderedItemIds, int now) => _db.transaction((tx) async {
        for (var i = 0; i < orderedItemIds.length; i++) {
          await tx.update('playlist_items', {'position': i},
              where: 'id = ? AND playlist_id = ?', whereArgs: [orderedItemIds[i], playlistId]);
        }
        await tx.update('playlists', {'updated_at': now}, where: 'id = ?', whereArgs: [playlistId]);
      });
}
