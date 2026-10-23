import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/data/stream_fetch.dart';
import 'package:video_downloader/data/visionos_client.dart';

void main() {
  test('User-Agent igual al de NewPipe', () {
    expect(VisionOsClient.userAgent(),
        'com.google.visionos.youtube/1.04(RealityDevice17,1; U; CPU visionOS 26_6_0 like Mac OS X; US)');
    expect(userAgentFor(Uri.parse('https://rr1.googlevideo.com/videoplayback?c=VISIONOS&itag=140')), VisionOsClient.userAgent());
  });

  test('contexto InnerTube', () {
    final c = VisionOsClient.context(visitorData: 'abc');
    final client = c['client']! as Map;
    expect(client['clientName'], 'VISIONOS');
    expect(client['clientVersion'], '1.04');
    expect(client['deviceModel'], 'RealityDevice17,1');
    expect(client['visitorData'], 'abc');
    expect((c['request']! as Map)['useSsl'], isTrue);
    expect(VisionOsClient.context()['client'], isNot(contains('visitorData')));
  });

  test('nonce: alfabeto y largo', () {
    final n = VisionOsClient.randomNonce(16);
    expect(n.length, 16);
    expect(RegExp(r'^[A-Za-z0-9_-]{16}$').hasMatch(n), isTrue);
  });

  test('lee formatos, agrega cpn y descarta los cifrados', () {
    final p = VisionOsPlayer.parse({
      'playabilityStatus': {'status': 'OK'},
      'videoDetails': {'videoId': 'kzMyk9AITdE'},
      'streamingData': {
        'adaptiveFormats': [
          {'itag': 140, 'url': 'https://rr2.googlevideo.com/videoplayback?c=VISIONOS&itag=140', 'mimeType': 'audio/mp4; codecs="mp4a.40.2"', 'bitrate': 130000, 'contentLength': '4473115'},
          {'itag': 137, 'url': 'https://rr2.googlevideo.com/videoplayback?c=VISIONOS&itag=137', 'mimeType': 'video/mp4; codecs="avc1.640028"', 'bitrate': 4000000, 'contentLength': '90000000', 'width': 1920, 'height': 1080, 'qualityLabel': '1080p'},
          {'itag': 251, 'signatureCipher': 's=abc&url=x', 'mimeType': 'audio/webm; codecs="opus"'},
        ],
        'hlsManifestUrl': 'https://manifest.googlevideo.com/api/manifest/hls_variant/c/VISIONOS/index.m3u8',
      },
    }, cpn: 'CPN123', videoId: 'kzMyk9AITdE');
    expect(p.formats.map((f) => f.itag), [140, 137]);
    expect(p.formats.first.url.toString(), endsWith('&cpn=CPN123'));
    expect(p.formats.first.hasAudio, isTrue);
    expect(p.formats.first.hasVideo, isFalse);
    expect(p.formats.first.contentLength, 4473115);
    expect(p.formats.last.videoCodec, 'avc1.640028');
    expect(p.formats.last.height, 1080);
    expect(p.hlsManifestUrl, isNotNull);
  });

  test('errores de reproducción', () {
    expect(
      () => VisionOsPlayer.parse({
        'playabilityStatus': {'status': 'LOGIN_REQUIRED', 'reason': 'Sign in to confirm you’re not a bot'},
      }, cpn: 'x', videoId: 'v'),
      throwsA(isA<VisionOsException>().having((e) => e.message, 'message', contains('bloqueó'))),
    );
    expect(() => VisionOsPlayer.parse({'playabilityStatus': {'status': 'OK'}}, cpn: 'x', videoId: 'v'), throwsA(isA<VisionOsException>()));
  });
}
