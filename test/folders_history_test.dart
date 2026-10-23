import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/data/folders.dart';
import 'package:video_downloader/data/models.dart';

void main() {
  group('nombres de carpeta', () {
    test('normaliza espacios', () => expect(normalizeFolderName('  Rock   en  español '), 'Rock en español'));
    test('vacío no vale', () => expect(folderNameError('   ', const []), isNotNull));
    test('largo máximo', () {
      expect(folderNameError('a' * (maxFolderName + 1), const []), isNotNull);
      expect(folderNameError('a' * maxFolderName, const []), isNull);
    });
    test('duplicado sin distinguir mayúsculas', () {
      expect(folderNameError(' favoritos ', ['Favoritos']), isNotNull);
      expect(folderNameError('Favoritos 2', ['Favoritos']), isNull);
    });
  });

  test('FoldersState cuenta y nombra', () {
    const s = FoldersState(
      folders: [LibraryFolder(id: 1, name: 'Rock'), LibraryFolder(id: 2, name: 'Favoritos')],
      memberships: {10: {1, 2}, 11: {1}},
    );
    expect(s.countOf(1), 2);
    expect(s.countOf(2), 1);
    expect(s.namesOf(10), ['Rock', 'Favoritos']);
    expect(s.foldersOf(99), isEmpty);
  });

  group('historial', () {
    const e = WatchHistoryEntry(
      videoId: 'dQw4w9WgXcQ',
      title: 'Video',
      author: 'Canal',
      watchedAt: 1,
      duration: Duration(minutes: 4),
      position: Duration(minutes: 1),
    );
    test('progreso y reanudar', () {
      expect(e.progress, 0.25);
      expect(e.isResumable, isTrue);
      const fresh = WatchHistoryEntry(videoId: 'x', title: 't', author: 'a', watchedAt: 1, position: Duration(seconds: 5));
      expect(fresh.isResumable, isFalse);
      expect(fresh.progress, isNull);
    });
    test('ida y vuelta a la base de datos', () {
      final back = WatchHistoryEntry.fromRow(e.toRow());
      expect(back.position, e.position);
      expect(back.duration, e.duration);
      expect(back.author, 'Canal');
    });
  });
}
