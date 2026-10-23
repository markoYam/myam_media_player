import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/data/models.dart';
import 'package:video_downloader/data/playlists.dart';

Playlist list(int id, String name) =>
    Playlist(id: id, name: name, count: 0, coverVideoIds: const [], createdAt: 0, updatedAt: 0);

void main() {
  group('playlistNameError', () {
    final existing = [list(1, 'Corridos'), list(2, 'Para correr')];
    test('vacío', () => expect(playlistNameError('   ', existing), isNotNull));
    test('muy largo', () => expect(playlistNameError('a' * (maxPlaylistName + 1), existing), isNotNull));
    test('repetido sin importar mayúsculas', () => expect(playlistNameError('  corridos ', existing), isNotNull));
    test('al renombrar puede conservar su propio nombre', () => expect(playlistNameError('Corridos', existing, exceptId: 1), isNull));
    test('nuevo nombre válido', () => expect(playlistNameError('Mana viejitas', existing), isNull));
  });

  test('normaliza espacios', () => expect(normalizePlaylistName('  Maná   viejitas '), 'Maná viejitas'));

  group('reorderedIds', () {
    test('bajar un elemento', () => expect(reorderedIds([1, 2, 3, 4], 0, 2), [2, 3, 1, 4]));
    test('subir un elemento', () => expect(reorderedIds([1, 2, 3, 4], 3, 0), [4, 1, 2, 3]));
    test('mismo lugar', () => expect(reorderedIds([1, 2, 3], 1, 1), [1, 2, 3]));
    test('índice fuera de rango no rompe', () => expect(reorderedIds([1, 2], 5, 0), [1, 2]));
    test('destino más allá del final va al final', () => expect(reorderedIds([1, 2, 3], 0, 9), [2, 3, 1]));
  });

  test('duración total ignora las desconocidas', () {
    PlaylistItem item(int id, Duration? d) =>
        PlaylistItem(id: id, playlistId: 1, position: id, addedAt: 0, video: VideoSummary(id: 'v$id', title: 't', author: 'a', duration: d));
    expect(totalDuration([item(1, const Duration(minutes: 3)), item(2, null), item(3, const Duration(seconds: 30))]),
        const Duration(minutes: 3, seconds: 30));
  });

  test('fila de la base ida y vuelta', () {
    const v = VideoSummary(id: 'abc', title: 'Que Onda', author: 'Calle 24', channelId: 'UC1', duration: Duration(seconds: 199));
    final row = {...playlistItemRow(v), 'id': 7, 'playlist_id': 3, 'position': 2, 'added_at': 99};
    final item = PlaylistItem.fromRow(row);
    expect(item.id, 7);
    expect(item.playlistId, 3);
    expect(item.position, 2);
    expect(item.video.id, 'abc');
    expect(item.video.title, 'Que Onda');
    expect(item.video.channelId, 'UC1');
    expect(item.video.duration, const Duration(seconds: 199));
  });
}
