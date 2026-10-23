import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/data/archive_client.dart';

Map<String, Object?> sample() => {
      'metadata': {'identifier': 'grateful-dead-1977', 'title': 'Concierto 1977', 'creator': ['Grateful Dead', 'Otro']},
      'files': [
        {'name': '01 Intro.flac', 'format': 'Flac', 'size': '30000000', 'length': '95.5', 'track': '1', 'source': 'original'},
        {'name': '01 Intro.mp3', 'format': 'VBR MP3', 'size': '3000000', 'length': '95.5', 'track': '1', 'title': 'Intro'},
        {'name': '01 Intro.ogg', 'format': 'Ogg Vorbis', 'size': '2000000', 'track': '1'},
        {'name': '02 Canción #2.mp3', 'format': 'VBR MP3', 'size': '4000000', 'length': '3:35', 'track': '2/10'},
        {'name': 'pelicula.mp4', 'format': 'MPEG4', 'size': '50000000'},
        {'name': 'pelicula.ia.mp4', 'format': 'h.264 IA', 'size': '40000000'},
        {'name': 'pelicula.ogv', 'format': 'Ogg Video'},
        {'name': 'portada.jpg', 'format': 'JPEG'},
        {'name': 'grateful-dead-1977_meta.xml', 'format': 'Metadata'},
      ],
    };

void main() {
  group('archiveIdFromUrl', () {
    test('details', () => expect(archiveIdFromUrl('https://archive.org/details/grateful-dead-1977'), 'grateful-dead-1977'));
    test('download con archivo', () => expect(archiveIdFromUrl('https://archive.org/download/abc_123/01%20x.mp3'), 'abc_123'));
    test('sin esquema y con www', () => expect(archiveIdFromUrl('www.archive.org/details/x.y-z'), 'x.y-z'));
    test('embed', () => expect(archiveIdFromUrl('https://archive.org/embed/abc'), 'abc'));
    test('otros dominios no', () => expect(archiveIdFromUrl('https://archive.org.evil.com/details/abc'), isNull));
    test('otras rutas no', () => expect(archiveIdFromUrl('https://archive.org/search?query=x'), isNull));
    test('texto con espacios no', () => expect(archiveIdFromUrl('mira archive.org/details/abc'), isNull));
  });

  group('parseArchiveMetadata', () {
    final item = parseArchiveMetadata(sample(), id: 'grateful-dead-1977');

    test('título, primer creador y portada', () {
      expect(item.title, 'Concierto 1977');
      expect(item.creator, 'Grateful Dead');
      expect(item.thumbnail.toString(), 'https://archive.org/services/img/grateful-dead-1977');
    });

    test('de cada pista queda una copia: el MP3 gana al FLAC y al OGG', () {
      expect(item.audio.map((f) => f.name).toList(), ['01 Intro.mp3', '02 Canción #2.mp3']);
    });

    test('ordena por número de pista ("2/10" cuenta como 2) y lee la duración', () {
      expect(item.audio.first.title, 'Intro');
      expect(item.audio.first.duration, const Duration(milliseconds: 95500));
      expect(item.audio[1].track, 2);
      expect(item.audio[1].duration, const Duration(minutes: 3, seconds: 35));
      expect(item.audio[1].title, '02 Canción #2');
    });

    test('video: el h.264 gana al MPEG4; sin Ogg Video, imágenes ni metadatos', () {
      expect(item.video.map((f) => f.name).toList(), ['pelicula.ia.mp4']);
    });

    test('la URL de descarga codifica espacios, acentos y #', () {
      expect(item.audio[1].url.toString(), 'https://archive.org/download/grateful-dead-1977/02%20Canci%C3%B3n%20%232.mp3');
    });

    test('OGG solo si se permite (Android)', () {
      final onlyOgg = {
        'metadata': {'identifier': 'x'},
        'files': [
          {'name': 'a.ogg', 'format': 'Ogg Vorbis'},
        ],
      };
      expect(parseArchiveMetadata(onlyOgg, id: 'x').files, isEmpty);
      expect(parseArchiveMetadata(onlyOgg, id: 'x', allowOgg: true).files.single.name, 'a.ogg');
    });

    test('item inexistente (respuesta {}) → FormatException', () {
      expect(() => parseArchiveMetadata({}, id: 'nada'), throwsFormatException);
    });

    test('sin título usa el id; subcarpetas se codifican por parte', () {
      final it = parseArchiveMetadata({
        'metadata': {'identifier': 'y'},
        'files': [
          {'name': 'disco 1/01_mi_cancion.mp3', 'format': 'MP3'},
        ],
      }, id: 'y');
      expect(it.title, 'y');
      expect(it.files.single.title, '01 mi cancion');
      expect(it.files.single.url.toString(), 'https://archive.org/download/y/disco%201/01_mi_cancion.mp3');
    });
  });

  test('extensionOf', () {
    expect(extensionOf('a/b/C.MP3'), 'mp3');
    expect(extensionOf('sin'), '');
    expect(extensionOf('.oculto'), '');
  });
}
