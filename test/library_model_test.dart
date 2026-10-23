import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/data/models.dart';
import 'package:video_downloader/features/library/library_model.dart';

DownloadTask task(int id, String title, String author, {OutputKind kind = OutputKind.m4a, int done = 0}) => DownloadTask(
      id: id,
      videoId: 'vid$id',
      title: title,
      author: author,
      kind: kind,
      tag: 140,
      fileName: title,
      status: DownloadStatus.completed,
      downloadedBytes: 0,
      totalBytes: null,
      createdAt: 0,
      completedAt: done,
    );

LibraryEntry entry(DownloadTask t) => (task: t, file: File('/tmp/${t.id}'));

LibraryCollection col(CollectionKind kind, String title, {int recency = 0, String creator = 'Tú'}) =>
    (kind: kind, id: title.hashCode, title: title, subtitle: '', creator: creator, recency: recency, coverIds: const <String>[]);

void main() {
  final songs = [
    entry(task(1, 'Ojalá', 'Silvio Rodríguez', done: 10)),
    entry(task(2, 'Abrázame', 'Camilo - Topic', done: 30)),
    entry(task(3, 'Calle 24', 'Fuerza Regida', kind: OutputKind.mp4, done: 20)),
  ];

  group('visibleEntries', () {
    test('Canciones = solo audio, Videos = solo video', () {
      expect(visibleEntries(songs, chip: LibraryChip.songs, sort: LibrarySort.alpha).map((e) => e.task.id), [2, 1]);
      expect(visibleEntries(songs, chip: LibraryChip.videos, sort: LibrarySort.alpha).map((e) => e.task.id), [3]);
    });
    test('busca sin acentos en título y artista', () {
      expect(visibleEntries(songs, query: 'ojala', sort: LibrarySort.recent).single.task.id, 1);
      expect(visibleEntries(songs, query: 'RODRIGUEZ', sort: LibrarySort.recent).single.task.id, 1);
    });
    test('recientes = lo último descargado primero', () {
      expect(visibleEntries(songs, sort: LibrarySort.recent).map((e) => e.task.id), [2, 3, 1]);
    });
    test('creador = por artista limpio (sin "- Topic")', () {
      expect(visibleEntries(songs, sort: LibrarySort.creator).map((e) => artistOf(e.task)), ['Camilo', 'Fuerza Regida', 'Silvio Rodríguez']);
    });
  });

  group('visibleCollections', () {
    final playlists = [col(CollectionKind.playlist, 'Para el camino', recency: 50)];
    final folders = [col(CollectionKind.folder, 'Banda', recency: 80)];
    final artists = [col(CollectionKind.artist, 'Camilo', recency: 90, creator: 'Camilo')];

    test('sin chip: listas y carpetas, sin artistas (tienen su chip)', () {
      final out = visibleCollections(playlists: playlists, folders: folders, artists: artists, chip: null, sort: LibrarySort.recent);
      expect(out.map((c) => c.title), ['Banda', 'Para el camino']);
    });
    test('al buscar sin chip también salen artistas', () {
      final out = visibleCollections(playlists: playlists, folders: folders, artists: artists, chip: null, sort: LibrarySort.recent, query: 'camilo');
      expect(out.single.kind, CollectionKind.artist);
    });
    test('chip Listas = solo listas; Canciones = ninguna colección', () {
      expect(visibleCollections(playlists: playlists, folders: folders, artists: artists, chip: LibraryChip.playlists, sort: LibrarySort.alpha).single.title,
          'Para el camino');
      expect(visibleCollections(playlists: playlists, folders: folders, artists: artists, chip: LibraryChip.songs, sort: LibrarySort.alpha), isEmpty);
    });
    test('alfabético ignora acentos y mayúsculas', () {
      final out = sortCollections([col(CollectionKind.folder, 'éxitos'), col(CollectionKind.folder, 'Banda'), col(CollectionKind.folder, 'cumbias')], LibrarySort.alpha);
      expect(out.map((c) => c.title), ['Banda', 'cumbias', 'éxitos']);
    });
  });

  test('carpeta: conteo, lo más reciente y hasta 4 portadas', () {
    final c = folderCollection(const LibraryFolder(id: 7, name: 'Viaje'), songs);
    expect(c.subtitle, 'Carpeta · 3 archivos');
    expect(c.recency, 30);
    expect(c.coverIds, ['vid1', 'vid2', 'vid3']);
    expect(folderCollection(const LibraryFolder(id: 8, name: 'Vacía'), const []).recency, 0);
  });

  test('el orden se rota: Recientes → Alfabético → Creador → Recientes', () {
    expect(LibrarySort.recent.next, LibrarySort.alpha);
    expect(LibrarySort.creator.next, LibrarySort.recent);
  });

  test('countLabel', () {
    expect(countLabel(1, one: 'canción', many: 'canciones'), '1 canción');
    expect(countLabel(3), '3 archivos');
  });
}
