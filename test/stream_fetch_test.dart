import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/data/stream_fetch.dart';

void main() {
  test('User-Agent según el cliente de la URL', () {
    expect(userAgentFor(Uri.parse('https://rr1.googlevideo.com/videoplayback?c=ANDROID&itag=140')), contains('com.google.android.youtube'));
    expect(userAgentFor(Uri.parse('https://rr1.googlevideo.com/videoplayback?c=ANDROID_VR')), contains('vr.oculus'));
    expect(userAgentFor(Uri.parse('https://rr1.googlevideo.com/videoplayback?c=IOS')), contains('com.google.ios.youtube'));
    expect(userAgentFor(Uri.parse('https://rr1.googlevideo.com/videoplayback?c=WEB')), startsWith('Mozilla/5.0'));
  });

  test('bloque con range sin re-codificar la firma', () {
    final url = Uri.parse('https://rr1.googlevideo.com/videoplayback?c=ANDROID&sig=AB%2FCD%3D&sparams=a%2Cb');
    final chunk = chunkUrl(url, 0, 1023).toString();
    expect(chunk, endsWith('&range=0-1023'));
    expect(chunk, contains('sig=AB%2FCD%3D'));
    expect(chunk, contains('sparams=a%2Cb'));
  });

  test('fin del bloque', () {
    expect(chunkEnd(0, 100, chunk: 30), 29);
    expect(chunkEnd(90, 100, chunk: 30), 99);
    expect(chunkEnd(0, 25 * 1024 * 1024), streamChunkBytes - 1);
  });
}
