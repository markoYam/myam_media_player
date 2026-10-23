import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/data/background_download.dart';
import 'package:video_downloader/data/stream_fetch.dart';

void main() {
  group('planChunks', () {
    test('parte el archivo en bloques contiguos que cubren todo', () {
      const total = 25 * 1024 * 1024 + 7;
      final chunks = planChunks(0, total);
      expect(chunks.length, 3);
      expect(chunks.first.from, 0);
      for (var i = 1; i < chunks.length; i++) {
        expect(chunks[i].from, chunks[i - 1].to! + 1);
      }
      expect(chunks.last.to, total - 1);
      expect(chunks.fold<int>(0, (a, c) => a + expectedLength(c)), total);
    });
    test('empieza donde iba el archivo parcial', () {
      final chunks = planChunks(1000, 5000, chunk: 2000);
      expect(chunks.map((c) => (c.from, c.to)).toList(), [(1000, 2999), (3000, 4999)]);
      expect(chunks.map((c) => c.index).toList(), [0, 1]);
    });
    test('un archivo chico es un solo bloque', () {
      final chunks = planChunks(0, 4473115);
      expect(chunks.length, 1);
      expect(expectedLength(chunks.single), 4473115);
    });
    test('tamaño desconocido: un bloque sin fin', () {
      final chunks = planChunks(0, 0);
      expect(chunks.single.to, isNull);
      expect(expectedLength(chunks.single), -1);
    });
    test('ya completo: nada que bajar', () => expect(planChunks(5000, 5000), isEmpty));
    test('usa el tamaño de bloque de las descargas normales', () {
      expect(expectedLength(planChunks(0, streamChunkBytes * 2).first), streamChunkBytes);
    });
  });

  group('decideChunk', () {
    const c = (index: 0, from: 0, to: 99);
    ChunkAction d({int length = 0, String? state, int? http, int failures = 0, bool recent = false}) =>
        decideChunk(chunk: c, fileLength: length, state: state, http: http, failures: failures, justEnqueued: recent);

    test('archivo del tamaño justo = listo, diga lo que diga el sistema', () {
      expect(d(length: 100), ChunkAction.done);
      expect(d(length: 100, state: 'failed'), ChunkAction.done);
    });
    test('en curso = esperar', () => expect(d(state: 'running'), ChunkAction.wait));
    test('desconocido = pedirlo', () => expect(d(), ChunkAction.enqueue));
    test('recién pedido = esperar aunque aún se vea el intento fallido anterior', () {
      expect(d(recent: true), ChunkAction.wait);
      expect(d(state: 'failed', http: 403, recent: true), ChunkAction.wait);
    });
    test('403 o 410 = URL nueva', () {
      expect(d(state: 'failed', http: 403), ChunkAction.renew);
      expect(d(state: 'failed', http: 410), ChunkAction.renew);
    });
    test('otro fallo o perdido = pedirlo otra vez', () {
      expect(d(state: 'failed', http: 500), ChunkAction.enqueue);
      expect(d(state: 'lost'), ChunkAction.enqueue);
    });
    test('demasiados fallos = rendirse', () => expect(d(state: 'failed', failures: maxChunkFailures), ChunkAction.giveUp));
    test('"listo" con tamaño equivocado = pedirlo y cuenta como fallo', () {
      expect(d(length: 40, state: 'done'), ChunkAction.enqueue);
      expect(countsAsFailure('done', fileLength: 40, chunk: c), isTrue);
    });
    test('pedirlo por primera vez no cuenta como fallo', () {
      expect(countsAsFailure(null, fileLength: 0, chunk: c), isFalse);
      expect(countsAsFailure('lost', fileLength: 0, chunk: c), isTrue);
    });
    test('tamaño desconocido: listo cuando el sistema dice listo', () {
      const open = (index: 0, from: 0, to: null);
      expect(decideChunk(chunk: open, fileLength: 1234, state: 'done', failures: 0), ChunkAction.done);
      expect(decideChunk(chunk: open, fileLength: 0, state: 'running', failures: 0), ChunkAction.wait);
    });
  });

  test('los ids de una descarga no se confunden con los de otra', () {
    expect(chunkTransferId(1, 140, 0).startsWith(transferPrefix(1)), isTrue);
    expect(chunkTransferId(12, 140, 0).startsWith(transferPrefix(1)), isFalse);
  });
}
