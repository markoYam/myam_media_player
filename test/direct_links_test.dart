import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/data/direct_links.dart';
import 'package:video_downloader/data/models.dart';

void main() {
  group('firstUrl', () {
    test('saca el enlace de un texto compartido', () {
      expect(firstUrl('Mira esta rola 🔥 https://youtu.be/abcdefghijk?si=xyz.'), 'https://youtu.be/abcdefghijk?si=xyz');
    });
    test('quita paréntesis y comillas finales', () {
      expect(firstUrl('(ver "https://x.com/a.mp3")'), 'https://x.com/a.mp3');
    });
    test('sin enlace', () => expect(firstUrl('hola mundo'), isNull));
  });

  group('directKindFromUrl', () {
    test('audio', () => expect(directKindFromUrl(Uri.parse('https://x.com/a/b.MP3?token=1')), DirectMediaKind.audio));
    test('video', () => expect(directKindFromUrl(Uri.parse('https://x.com/v.m4v')), DirectMediaKind.video));
    test('página', () => expect(directKindFromUrl(Uri.parse('https://x.com/page.html')), isNull));
  });

  test('Content-Type', () {
    expect(directKindFromContentType('audio/mpeg; charset=binary'), DirectMediaKind.audio);
    expect(directKindFromContentType('video/mp4'), DirectMediaKind.video);
    expect(directKindFromContentType('text/html'), isNull);
    expect(outputKindForContentType('audio/mpeg'), OutputKind.mp3);
    expect(outputKindForContentType('audio/ogg'), isNull);
  });

  test('formato de descarga por extensión', () {
    expect(outputKindForExtension('mp3'), OutputKind.mp3);
    expect(outputKindForExtension('M4A'), OutputKind.m4a);
    expect(outputKindForExtension('m4v'), OutputKind.mp4);
    expect(outputKindForExtension('flac'), isNull);
  });

  test('stableHash: estable, 16 hex y distinto entre URLs', () {
    const a = 'https://x.com/a.mp3';
    expect(stableHash(a), stableHash(a));
    expect(stableHash(a), matches(RegExp(r'^[0-9a-f]{16}$')));
    expect(stableHash(a), isNot(stableHash('https://x.com/b.mp3')));
  });

  test('titleFromUrl', () {
    expect(titleFromUrl(Uri.parse('https://x.com/m%C3%BAsica/Mi_canci%C3%B3n.mp3')), 'Mi canción');
    expect(titleFromUrl(Uri.parse('https://x.com/')), 'x.com');
  });
}
