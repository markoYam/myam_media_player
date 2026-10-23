import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/data/models.dart';

void main() {
  const task = DownloadTask(
    id: 7,
    videoId: 'dQw4w9WgXcQ',
    title: 'Canción',
    author: 'Artista',
    kind: OutputKind.m4a,
    tag: 140,
    fileName: 'Canción',
    status: DownloadStatus.running,
    downloadedBytes: 50,
    totalBytes: 200,
    createdAt: 1000,
  );

  test('ida y vuelta a la base de datos', () {
    final back = DownloadTask.fromRow(task.toRow());
    expect(back.id, 7);
    expect(back.kind, OutputKind.m4a);
    expect(back.status, DownloadStatus.running);
    expect(back.totalBytes, 200);
  });

  test('MP4 HD guarda la pista de audio y la calidad', () {
    final hd = DownloadTask.fromRow({...task.toRow(), 'kind': 'mp4', 'audio_tag': 140, 'quality_label': '1080p'});
    expect(hd.audioTag, 140);
    expect(hd.qualityLabel, '1080p');
    expect(DownloadTask.fromRow(hd.copyWith(status: DownloadStatus.processing).toRow()).status, DownloadStatus.processing);
  });

  test('progreso', () {
    expect(task.progress, 0.25);
    expect(task.copyWith(totalBytes: 0).progress, isNull);
  });

  test('copyWith limpia error y velocidad', () {
    final failed = task.copyWith(error: 'x', bytesPerSecond: 10);
    expect(failed.copyWith(clearError: true, clearSpeed: true).error, isNull);
    expect(failed.copyWith(clearError: true, clearSpeed: true).bytesPerSecond, isNull);
  });

  test('valores desconocidos en la base no rompen', () {
    final row = task.toRow()..['kind'] = 'flac'..['status'] = '???';
    final t = DownloadTask.fromRow(row);
    expect(t.kind, OutputKind.mp4);
    expect(t.status, DownloadStatus.failed);
  });
}
