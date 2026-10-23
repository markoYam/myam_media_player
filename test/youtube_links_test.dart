import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/core/youtube_links.dart';

void main() {
  const id = 'dQw4w9WgXcQ';

  group('videos', () {
    test('watch?v=', () => expect(videoIdFromInput('https://www.youtube.com/watch?v=$id&t=10s'), id));
    test('youtu.be', () => expect(videoIdFromInput('https://youtu.be/$id?si=abc'), id));
    test('shorts', () => expect(videoIdFromInput('https://youtube.com/shorts/$id'), id));
    test('móvil y música', () {
      expect(videoIdFromInput('https://m.youtube.com/watch?v=$id'), id);
      expect(videoIdFromInput('https://music.youtube.com/watch?v=$id'), id);
    });
    test('sin esquema', () => expect(videoIdFromInput('youtu.be/$id'), id));
    test('id inválido', () => expect(videoIdFromInput('https://youtu.be/abc'), isNull));
    test('dominio que imita a YouTube', () => expect(videoIdFromInput('https://youtube.com.evil.example/watch?v=$id'), isNull));
  });

  group('listas', () {
    const list = 'PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI';
    test('playlist?list=', () => expect(playlistIdFromInput('https://www.youtube.com/playlist?list=$list'), list));
    test('un video dentro de una lista abre el video, no la lista', () {
      expect(playlistIdFromInput('https://www.youtube.com/watch?v=$id&list=$list'), isNull);
      expect(videoIdFromInput('https://www.youtube.com/watch?v=$id&list=$list'), id);
    });
  });

  group('canales', () {
    test('/channel/UC…', () {
      final c = channelFromInput('https://www.youtube.com/channel/UC_x5XG1OV2P6uZZ5FSM9Ttw');
      expect(c?.id, 'UC_x5XG1OV2P6uZZ5FSM9Ttw');
    });
    test('/@handle', () => expect(channelFromInput('https://youtube.com/@GoogleDevelopers')?.handle, 'GoogleDevelopers'));
    test('otra ruta no es canal', () => expect(channelFromInput('https://youtube.com/feed/trending'), isNull));
  });

  test('texto normal no es enlace', () {
    expect(videoIdFromInput('musica para estudiar'), isNull);
    expect(looksLikeUrl('musica para estudiar'), isFalse);
    expect(looksLikeUrl('example.com/video.mp4'), isTrue);
  });
}
