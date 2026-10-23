/// Reglas de las descargas en segundo plano (separadas para probarlas sin plugins).
///
/// Un archivo se baja en bloques de [streamChunkBytes]; cada bloque es una transferencia del
/// sistema (NSURLSession en iOS, WorkManager en Android) que escribe su propio archivo. La app,
/// cuando está abierta, revisa cada segundo qué bloques ya están (por su tamaño), pide los que
/// faltan y al final los une. Si la app se cerró, al abrirla retoma con lo que ya bajó.
library;

import 'stream_fetch.dart';

/// Bloque [from]..[to] (inclusive). [to] null = hasta el final (tamaño desconocido).
typedef Chunk = ({int index, int from, int? to});

/// Bloques para bajar desde [start] un archivo de [total] bytes. Con [total] desconocido (≤ 0)
/// es un solo bloque con todo el archivo.
List<Chunk> planChunks(int start, int total, {int chunk = streamChunkBytes}) {
  if (total <= 0) return const [(index: 0, from: 0, to: null)];
  final out = <Chunk>[];
  var from = start;
  var i = 0;
  while (from < total) {
    final to = chunkEnd(from, total, chunk: chunk);
    out.add((index: i++, from: from, to: to));
    from = to + 1;
  }
  return out;
}

/// Bytes que debe tener el archivo del bloque; -1 si no se sabe (tamaño total desconocido).
int expectedLength(Chunk c) => c.to == null ? -1 : c.to! - c.from + 1;

enum ChunkAction {
  /// Ya está completo.
  done,

  /// Se está bajando (o se acaba de pedir): esperar.
  wait,

  /// Pedirlo (por primera vez o de nuevo).
  enqueue,

  /// La URL caducó (403/410): pedir una URL nueva y volver a pedirlo.
  renew,

  /// Falló demasiadas veces: rendirse (la descarga sigue por el método normal).
  giveUp,
}

/// Máximo de reintentos por bloque antes de rendirse.
const maxChunkFailures = 4;

/// Qué hacer con un bloque, según su archivo y lo que dice el sistema.
///
/// - [fileLength]: tamaño del archivo del bloque (0 si no existe).
/// - [state]: "running", "done", "failed", "lost" o null (el sistema no sabe de él).
/// - [justEnqueued]: se pidió hace poco (WorkManager tarda un momento en reportarlo).
ChunkAction decideChunk({
  required Chunk chunk,
  required int fileLength,
  required String? state,
  int? http,
  required int failures,
  bool justEnqueued = false,
}) {
  final expected = expectedLength(chunk);
  if (expected > 0 && fileLength == expected) return ChunkAction.done;
  if (expected < 0 && state == 'done' && fileLength > 0) return ChunkAction.done;
  if (state == 'running') return ChunkAction.wait;
  // Recién pedido: WorkManager puede seguir mostrando el intento anterior (fallido) un momento.
  if (justEnqueued) return ChunkAction.wait;
  if (failures >= maxChunkFailures) return ChunkAction.giveUp;
  if (state == 'failed' && (http == 403 || http == 410)) return ChunkAction.renew;
  return ChunkAction.enqueue;
}

/// ¿Este estado cuenta como un intento fallido? (pedirlo por primera vez no cuenta).
bool countsAsFailure(String? state, {required int fileLength, required Chunk chunk}) {
  if (state == 'failed' || state == 'lost') return true;
  // "done" pero con el tamaño equivocado: bajó algo raro (p. ej. una página de error).
  return state == 'done' && expectedLength(chunk) > 0 && fileLength != expectedLength(chunk);
}

/// Id de la transferencia del bloque [index] de la pista [tag] de la descarga [taskId].
String chunkTransferId(int taskId, int tag, int index) => '${transferPrefix(taskId)}$tag:$index';

/// Prefijo de todas las transferencias de una descarga (para consultar o cancelar todas).
String transferPrefix(int taskId) => 'dl$taskId:';
