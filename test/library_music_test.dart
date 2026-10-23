import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/data/download_manager.dart';
import 'package:video_downloader/data/models.dart';
import 'package:video_downloader/features/library/library_screen.dart';

DownloadTask task(int id, String title, String author, {OutputKind kind = OutputKind.m4a, bool mixtape = false}) => DownloadTask(
      id: id,
      videoId: 'vid$id',
      title: title,
      author: author,
      kind: kind,
      tag: 140,
      fileName: title,
      status: DownloadStatus.completed,
      downloadedBytes: 1,
      totalBytes: 1,
      createdAt: id,
      isMixtape: mixtape,
    );

LibraryEntry entry(DownloadTask t) => (task: t, file: File('/tmp/${t.id}'));

void main() {
  test('artista: limpia " - Topic" y "VEVO"', () {
    expect(artistOf(task(1, 'a', 'Maná - Topic')), 'Maná');
    expect(artistOf(task(2, 'a', 'ManaVEVO')), 'Mana');
    expect(artistOf(task(3, 'a', '  ')), 'Desconocido');
  });

  test('agrupa por artista, de más canciones a menos', () {
    final groups = groupByArtist([
      entry(task(1, 'Rayando el sol', 'Maná')),
      entry(task(2, 'Oye mi amor', 'Maná - Topic')),
      entry(task(3, 'La cantina', 'Pipe Bueno')),
    ]);
    expect(groups.map((g) => g.artist), ['Maná', 'Pipe Bueno']);
    expect(groups.first.items.length, 2);
  });

  test('buscar sin acentos ni mayúsculas', () {
    expect(foldText('Canción ÑANDÚ'), 'cancion nandu');
    expect(foldText('De Pies a Cabeza').contains(foldText('pies')), isTrue);
  });

  test('marca de mixtape: ida y vuelta a la base de datos', () {
    final t = task(9, 'x', 'y', mixtape: true);
    expect(DownloadTask.fromRow(t.toRow()).isMixtape, isTrue);
    expect(DownloadTask.fromRow(t.copyWith(isMixtape: false).toRow()).isMixtape, isFalse);
    // Filas de versiones anteriores (sin la columna) no son mixtape.
    expect(DownloadTask.fromRow(t.toRow()..remove('auto_mixtape')).isMixtape, isFalse);
  });

  group('isMixtapeLength', () {
    test('una canción entra', () => expect(isMixtapeLength(const Duration(minutes: 3, seconds: 19)), isTrue));
    test('15 minutos justos entra', () => expect(isMixtapeLength(const Duration(minutes: 15)), isTrue));
    test('un podcast de una hora no', () => expect(isMixtapeLength(const Duration(hours: 1)), isFalse));
    test('duración desconocida entra', () => expect(isMixtapeLength(null), isTrue));
    test('directo (duración cero) no', () => expect(isMixtapeLength(Duration.zero), isFalse));
  });
}
