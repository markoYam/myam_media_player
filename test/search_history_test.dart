import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/data/search_history.dart';

void main() {
  group('addRecentSearch', () {
    test('lo nuevo va primero', () {
      expect(addRecentSearch(['rock'], 'maná'), ['maná', 'rock']);
    });
    test('sin repetidos ignorando acentos y mayúsculas', () {
      expect(addRecentSearch(['Mana', 'rock'], 'maná'), ['maná', 'rock']);
    });
    test('quita espacios de sobra y no guarda vacíos', () {
      expect(addRecentSearch(const [], '  fuerza   regida '), ['fuerza regida']);
      expect(addRecentSearch(['a'], '   '), ['a']);
    });
    test('máximo 20', () {
      final many = [for (var i = 0; i < 25; i++) 'b$i'];
      final out = addRecentSearch(many, 'nuevo');
      expect(out.length, maxRecentSearches);
      expect(out.first, 'nuevo');
    });
  });

  group('matchingRecents', () {
    const recents = ['Maná en vivo', 'peso pluma', 'corridos tumbados'];
    test('campo vacío: todas', () => expect(matchingRecents(recents, ''), recents));
    test('por inicio sin acentos', () => expect(matchingRecents(recents, 'mana'), ['Maná en vivo']));
    test('por palabra', () => expect(matchingRecents(recents, 'tumb'), ['corridos tumbados']));
    test('no coincide a mitad de palabra', () => expect(matchingRecents(recents, 'luma'), isEmpty));
  });

  test('foldSearch', () => expect(foldSearch('  Canción   ÑANDÚ '), 'cancion nandu'));
}
