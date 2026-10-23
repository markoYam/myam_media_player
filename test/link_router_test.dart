import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/data/direct_links.dart';
import 'package:video_downloader/features/links/link_router.dart';

void main() {
  test('video de YouTube dentro de un texto compartido', () {
    final t = classifyLink('Escucha esto: https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=abc');
    expect(t, isA<YouTubeVideoLink>().having((x) => x.id, 'id', 'dQw4w9WgXcQ'));
  });

  test('youtu.be sin esquema', () {
    expect(classifyLink('youtu.be/dQw4w9WgXcQ'), isA<YouTubeVideoLink>());
  });

  test('lista y canal', () {
    expect(classifyLink('https://youtube.com/playlist?list=PL1234567890abcdef'), isA<YouTubePlaylistLink>());
    expect(classifyLink('https://youtube.com/@canalprueba'), isA<YouTubeChannelLink>().having((x) => x.handle, 'handle', 'canalprueba'));
  });

  test('Internet Archive', () {
    expect(classifyLink('https://archive.org/details/concierto_1977'), isA<ArchiveLink>().having((x) => x.id, 'id', 'concierto_1977'));
  });

  test('enlace directo de audio y de video', () {
    expect(classifyLink('https://ejemplo.com/rola.mp3'), isA<DirectLink>().having((x) => x.kind, 'kind', DirectMediaKind.audio));
    expect(classifyLink('https://ejemplo.com/v.mp4'), isA<DirectLink>().having((x) => x.kind, 'kind', DirectMediaKind.video));
  });

  test('otro enlace queda para revisar en la red', () {
    expect(classifyLink('https://ejemplo.com/stream'), isA<UnknownLink>());
  });

  test('texto sin enlace → null', () {
    expect(classifyLink('corridos tumbados'), isNull);
  });
}
