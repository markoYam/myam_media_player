import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/data/models.dart';
import 'package:video_downloader/data/stream_selection.dart';

StreamCandidate muxed(int tag, int h, {String c = 'mp4'}) => StreamCandidate(
    tag: tag, container: c, hasVideo: true, hasAudio: true, bitrate: h * 1000, sizeBytes: h * 10000, height: h, qualityLabel: '${h}p', videoCodec: 'avc1.42001E');
StreamCandidate audio(int tag, int kbps, {String c = 'mp4'}) =>
    StreamCandidate(tag: tag, container: c, hasVideo: false, hasAudio: true, bitrate: kbps * 1000, sizeBytes: kbps * 30000, audioCodec: 'mp4a.40.2');
StreamCandidate videoOnly(int tag, int h, {String codec = 'avc1.640028', int bitrate = 0}) => StreamCandidate(
    tag: tag, container: 'mp4', hasVideo: true, hasAudio: false, bitrate: bitrate == 0 ? h * 5000 : bitrate, sizeBytes: h * 50000, height: h, qualityLabel: '${h}p', videoCodec: codec);

void main() {
  final streams = [
    muxed(18, 360),
    videoOnly(137, 1080),
    videoOnly(399, 1080, codec: 'av01.0.08M.08'), // AV1: no se puede unir en todos los equipos
    videoOnly(136, 720),
    videoOnly(298, 720, bitrate: 1), // misma altura, menos bitrate: no se ofrece
    videoOnly(313, 2160, codec: 'vp9'),
    audio(140, 128),
    audio(251, 160, c: 'webm'),
    muxed(43, 360, c: 'webm'),
  ];

  test('reproduce el muxed MP4 más alto', () => expect(pickPlayableMuxed(streams)?.tag, 18));
  test('sin muxed no hay video reproducible', () => expect(pickPlayableMuxed([videoOnly(137, 1080), audio(140, 128)]), isNull));
  test('audio: el mejor AAC en MP4 (ignora webm/opus)', () => expect(pickBestAudio(streams)?.tag, 140));

  test('MP4: 1080p y 720p unidos con el AAC, 360p ya viene con audio; nada de AV1/VP9', () {
    final mp4 = buildDownloadOptions(streams).where((o) => o.kind == OutputKind.mp4).toList();
    expect(mp4.map((o) => o.height), [1080, 720, 360]);
    expect(mp4.map((o) => o.tag), [137, 136, 18]);
    expect(mp4[0].audioTag, 140);
    expect(mp4[0].needsMerge, isTrue);
    expect(mp4[2].needsMerge, isFalse);
    expect(mp4[0].sizeBytes, 1080 * 50000 + 128 * 30000);
  });

  test('respeta la calidad máxima de Ajustes', () {
    final mp4 = buildDownloadOptions(streams, maxHeight: 720).where((o) => o.kind == OutputKind.mp4);
    expect(mp4.map((o) => o.height), [720, 360]);
  });

  test('M4A sin pérdida y MP3 convertido del mismo AAC', () {
    final options = buildDownloadOptions(streams, mp3Kbps: 320);
    final m4a = options.singleWhere((o) => o.kind == OutputKind.m4a);
    final mp3 = options.singleWhere((o) => o.kind == OutputKind.mp3);
    expect(m4a.tag, 140);
    expect(m4a.isLossy, isFalse);
    expect(mp3.tag, 140);
    expect(mp3.isLossy, isTrue);
    expect(mp3.label, startsWith('320 kbps'));
  });

  test('sin audio AAC no se ofrece unir ni MP3', () {
    final options = buildDownloadOptions([videoOnly(137, 1080), muxed(18, 360)]);
    expect(options.map((o) => o.tag), [18]);
  });
}
