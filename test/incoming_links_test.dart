import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/platform/incoming_links.dart';

void main() {
  group('linkFromIncoming', () {
    test('enlace solo', () => expect(linkFromIncoming('https://youtu.be/dQw4w9WgXcQ'), 'https://youtu.be/dQw4w9WgXcQ'));
    test('texto de "Compartir" con título y enlace', () {
      expect(linkFromIncoming('Mira esto: Que Onda [Official Video] https://youtu.be/abc123?si=XyZ'), 'https://youtu.be/abc123?si=XyZ');
    });
    test('quita puntuación pegada al final', () {
      expect(linkFromIncoming('(https://www.youtube.com/watch?v=abc).'), 'https://www.youtube.com/watch?v=abc');
    });
    test('esquema propio de la extensión de iOS', () {
      final raw = Uri(scheme: 'videodownloader', host: 'open', queryParameters: {'url': 'Mira https://youtu.be/xyz'}).toString();
      expect(linkFromIncoming(raw), 'https://youtu.be/xyz');
    });
    test('esquema propio con texto sin enlace', () {
      final raw = Uri(scheme: 'videodownloader', host: 'open', queryParameters: {'url': 'dQw4w9WgXcQ'}).toString();
      expect(linkFromIncoming(raw), 'dQw4w9WgXcQ');
    });
    test('esquema propio vacío → nada', () => expect(linkFromIncoming('videodownloader://open'), isNull));
    test('texto vacío → nada', () => expect(linkFromIncoming('   '), isNull));
    test('archive.org y enlaces directos pasan tal cual', () {
      expect(linkFromIncoming('https://archive.org/details/algo'), 'https://archive.org/details/algo');
      expect(linkFromIncoming('Escucha http://ejemplo.com/cancion.mp3'), 'http://ejemplo.com/cancion.mp3');
    });
  });
}
