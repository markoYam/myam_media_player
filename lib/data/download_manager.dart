import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:media_tools/media_tools.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/format.dart';
import '../core/diag_log.dart';
import '../core/id3.dart';
import '../providers.dart';
import 'background_download.dart';
import 'database.dart';
import 'folders.dart';
import 'models.dart';
import 'settings.dart';
import 'youtube_service.dart';

/// Carpeta de la app donde se guardan las descargas.
///
/// - iOS: "Documentos" de la app, visible en la app Archivos (En mi iPhone → Video Downloader).
/// - Android: almacenamiento propio de la app.
Future<Directory> downloadsRoot() async {
  final docs = await getApplicationDocumentsDirectory();
  return Directory(p.join(docs.path, 'Video Downloader'));
}

/// Portada guardada del video (para la pantalla de bloqueo y la biblioteca sin internet).
///
/// Los ids de enlaces directos ("ia:<id>/<archivo>") llevan ':' y '/': se cambian por '_'.
Future<File> coverFileFor(String videoId) async =>
    File(p.join((await downloadsRoot()).path, '.portadas', '${videoId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.jpg'));

/// Archivo absoluto de una descarga completada (la ruta guardada es relativa: en iOS la carpeta
/// de la app cambia de ubicación entre actualizaciones).
Future<File?> fileOf(DownloadTask t) async {
  final rel = t.filePath;
  if (rel == null) return null;
  final f = File(p.join((await downloadsRoot()).path, rel));
  return await f.exists() ? f : null;
}

/// Gestor de descargas: cola persistente, progreso, cancelar, reintentar y reanudar.
///
/// - MP4 hasta 360p y M4A: un solo flujo, se guarda tal cual.
/// - MP4 HD: video H.264 y audio AAC por separado; se unen sin recodificar (plugin media_tools).
/// - MP3: se descarga el AAC y se convierte con LAME.
///
/// Las descargas van en segundo plano (ver background_download.dart): el sistema baja los bloques
/// aunque la app esté minimizada o cerrada, y al volver se unen y se procesan. Si el sistema no
/// puede (o un bloque falla varias veces), se sigue con la descarga normal dentro de la app.
///
/// Enlaces directos ([DownloadTask.isDirect]): se bajan tal cual, sin YouTube ni conversión.
class DownloadsNotifier extends Notifier<List<DownloadTask>> {
  static const _uiInterval = Duration(milliseconds: 400);
  static const _dbInterval = Duration(seconds: 3);

  YouTubeService get _yt => ref.read(youtubeServiceProvider);
  int get _maxConcurrent => ref.read(settingsProvider).maxConcurrentDownloads;

  /// Bloques simultáneos por archivo en segundo plano.
  static const _parallelChunks = 3;

  /// Navegador común para enlaces directos (algunos servidores rechazan clientes desconocidos).
  static const _directHeaders = {
    'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
  };

  final _directClient = http.Client();

  /// Falso si el sistema no admite descargas en segundo plano (se usa la descarga normal).
  bool _backgroundOk = true;

  final _jobs = <int, _Job>{};
  final _busy = <int>{};
  AppDatabase? _db;
  bool _loaded = false;

  @override
  List<DownloadTask> build() {
    ref.onDispose(() {
      for (final id in _jobs.keys.toList()) {
        unawaited(_stopJob(id));
      }
    });
    unawaited(_load());
    return const [];
  }

  Future<AppDatabase> get _database async {
    final cached = _db;
    if (cached != null) return cached;
    final AppDatabase db = await ref.read(databaseProvider.future);
    return _db = db;
  }

  Future<void> _load() async {
    final db = await _database;
    var tasks = await db.all();
    // Lo que quedó a medias al cerrar la app vuelve a la cola (se reanuda con los archivos parciales).
    tasks = [
      for (final t in tasks)
        if (t.status == DownloadStatus.running || t.status == DownloadStatus.processing)
          t.copyWith(status: DownloadStatus.pending, clearSpeed: true)
        else
          t,
    ];
    state = tasks;
    _loaded = true;
    _pump();
  }

  /// Encola [option] de [video]. Lanza [AppException] si ya está descargado o en curso.
  ///
  /// [mixtape]: guardado automático de lo que escuchas (se puede borrar solo al pasar el límite).
  Future<void> enqueue(VideoSummary video, DownloadOption option, {bool mixtape = false}) async {
    final dup = state.firstWhereOrNull((t) =>
        t.videoId == video.id &&
        t.tag == option.tag &&
        t.kind == option.kind &&
        t.audioTag == option.audioTag &&
        (t.isActive || t.status == DownloadStatus.completed));
    if (dup != null) {
      if (mixtape) return;
      if (dup.isMixtape) {
        // Ya estaba en el mixtape: ahora el usuario la quiere, así que ya no se borra sola.
        await _save(dup.copyWith(isMixtape: false), persist: true);
        throw const AppException('Ya estaba guardada en tu mixtape; ahora queda fija en la Biblioteca.');
      }
      throw AppException(dup.isActive ? 'Esta descarga ya está en curso.' : 'Ya descargaste este archivo; está en tu Biblioteca.');
    }
    final draft = DownloadTask(
      id: 0,
      videoId: video.id,
      title: video.title,
      author: video.author,
      kind: option.kind,
      tag: option.tag,
      audioTag: option.audioTag,
      qualityLabel: option.label.split(' · ').first,
      fileName: sanitizeFileName(video.title),
      isMixtape: mixtape,
      status: DownloadStatus.pending,
      downloadedBytes: 0,
      totalBytes: option.sizeBytes > 0 ? option.sizeBytes : null,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    final db = await _database;
    final id = await db.insert(draft);
    state = [DownloadTask.fromRow({...draft.toRow(), 'id': id}), ...state];
    _pump();
    // Volumen de la canción (para el volumen parejo sin internet); sale de la respuesta en caché.
    unawaited(_yt.loudnessDb(video.id).then((loudness) async {
      final t = _find(id);
      if (loudness != null && t != null) await _save(t.copyWith(loudnessDb: loudness), persist: true);
    }));
  }

  /// Encola un enlace directo (Internet Archive, .mp4/.mp3/.m4a suelto): se descarga tal cual.
  /// [id] identifica el archivo (p. ej. "ia:<id>/<archivo>") y sirve para no repetirlo.
  Future<void> enqueueDirect({
    required String id,
    required String title,
    required String author,
    required Uri url,
    required OutputKind kind,
    String? thumbnail,
    int? sizeBytes,
    String? qualityLabel,
  }) async {
    final dup = state.firstWhereOrNull((t) => t.videoId == id && (t.isActive || t.status == DownloadStatus.completed));
    if (dup != null) {
      throw AppException(dup.isActive ? 'Esta descarga ya está en curso.' : 'Ya descargaste este archivo; está en tu Biblioteca.');
    }
    final draft = DownloadTask(
      id: 0,
      videoId: id,
      title: title,
      author: author,
      kind: kind,
      tag: 0,
      qualityLabel: qualityLabel,
      fileName: sanitizeFileName(title),
      status: DownloadStatus.pending,
      downloadedBytes: 0,
      totalBytes: (sizeBytes ?? 0) > 0 ? sizeBytes : null,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      sourceUrl: url.toString(),
      thumbnail: thumbnail,
    );
    final db = await _database;
    final newId = await db.insert(draft);
    state = [DownloadTask.fromRow({...draft.toRow(), 'id': newId}), ...state];
    _pump();
  }

  Future<void> cancel(int id) async {
    await _stopJob(id);
    await _cancelTransfers(id);
    final t = _find(id);
    if (t == null || !t.isActive) return;
    await _deletePartials(t);
    await _save(t.copyWith(status: DownloadStatus.cancelled, downloadedBytes: 0, clearSpeed: true), persist: true);
    _pump();
  }

  Future<void> retry(int id) async {
    final t = _find(id);
    if (t == null || t.isActive || t.status == DownloadStatus.completed) return;
    await _save(t.copyWith(status: DownloadStatus.pending, clearError: true), persist: true);
    _pump();
  }

  /// Quita la tarea de la lista; si [deleteFile], también borra el archivo del teléfono.
  Future<void> remove(int id, {bool deleteFile = false}) async {
    await _stopJob(id);
    await _cancelTransfers(id);
    final t = _find(id);
    if (t == null) return;
    if (deleteFile) {
      final f = await fileOf(t);
      if (f != null) await f.delete();
    }
    await _deletePartials(t);
    await (await _database).delete(id);
    state = state.where((x) => x.id != id).toList();
    await ref.read(foldersProvider.notifier).refresh();
  }

  // ---- motor ----

  DownloadTask? _find(int id) => state.firstWhereOrNull((t) => t.id == id);

  Future<Directory> _partialsDir() async {
    final dir = Directory(p.join((await downloadsRoot()).path, '.parciales'));
    await dir.create(recursive: true);
    return dir;
  }

  /// Archivos parciales con extensión real: AVFoundation (iOS) reconoce el formato por ella.
  Future<File> _partial(DownloadTask t, {bool audio = false}) async {
    final dir = (await _partialsDir()).path;
    if (audio) return File(p.join(dir, '${t.id}.audio.m4a'));
    return File(p.join(dir, t.kind == OutputKind.mp4 ? '${t.id}.video.mp4' : '${t.id}.source.m4a'));
  }

  Future<void> _deletePartials(DownloadTask t) async {
    final dir = await _partialsDir();
    await for (final e in dir.list()) {
      if (p.basename(e.path).startsWith('${t.id}.')) await e.delete();
    }
  }

  void _pump() {
    if (!_loaded) return;
    final free = _maxConcurrent - _busy.length;
    if (free <= 0) return;
    // La cola se atiende en orden de llegada (la lista está de más nueva a más vieja).
    final next = state.reversed.where((t) => t.status == DownloadStatus.pending && !_busy.contains(t.id)).take(free).toList();
    for (final t in next) {
      unawaited(_run(t));
    }
  }

  bool _stillRunning(int id) => _find(id)?.status == DownloadStatus.running;

  Future<void> _run(DownloadTask task) async {
    _busy.add(task.id);
    try {
      var t = task.copyWith(status: DownloadStatus.running, clearError: true);
      await _save(t, persist: true);

      final video = await _partial(task);
      final audio = task.audioTag == null ? null : await _partial(task, audio: true);

      // 1. Descargar (video y, si hace falta, el audio aparte). El progreso es la suma de ambos.
      final first = await _downloadPart(t, task.tag, video, baseBytes: 0);
      if (first == null) return;
      t = first.task;
      if (audio != null) {
        final second = await _downloadPart(t, task.audioTag!, audio, baseBytes: first.bytes);
        if (second == null) return;
        t = second.task;
      }

      // 2. Procesar y guardar.
      if (!_stillRunning(task.id)) return;
      final out = File(p.join((await _partialsDir()).path, '${task.id}.out.${task.kind.extension}'));
      // Los enlaces directos ya vienen en su formato final: no se unen ni se convierten.
      if (audio != null || (task.kind == OutputKind.mp3 && !task.isDirect)) {
        t = t.copyWith(status: DownloadStatus.processing, clearSpeed: true);
        await _save(t, persist: true);
        try {
          if (audio != null) {
            await MediaTools.mergeAudioVideo(video: video.path, audio: audio.path, output: out.path);
          } else {
            final raw = File(p.join((await _partialsDir()).path, '${task.id}.raw.mp3'));
            await MediaTools.transcodeToMp3(
              input: video.path,
              output: raw.path,
              bitrateKbps: ref.read(settingsProvider).mp3BitrateKbps,
            );
            // Título y artista en UTF-16 (acentos y emojis), como la versión Android.
            await Id3v2.writeTagged(raw, out, title: task.title, artist: task.author);
            await raw.delete();
          }
        } on MediaToolsException catch (e) {
          if (await out.exists()) await out.delete();
          await _fail(t, AppException(audio != null ? 'No se pudo unir video y audio: ${e.message}' : 'No se pudo convertir a MP3: ${e.message}'));
          return;
        }
        if (_find(task.id)?.status != DownloadStatus.processing) {
          if (await out.exists()) await out.delete();
          return;
        }
        await _finish(t, out);
        await video.delete();
        if (audio != null && await audio.exists()) await audio.delete();
      } else {
        await _finish(t, video);
      }
    } catch (e) {
      final current = _find(task.id);
      if (current != null && current.isActive) await _fail(current, e);
    } finally {
      _busy.remove(task.id);
      _pump();
    }
  }

  /// Descarga el flujo [tag] en [file] (reanudando lo que ya tenga). Devuelve la tarea actualizada
  /// y los bytes acumulados, o null si se canceló o falló (en ese caso la tarea ya quedó marcada).
  ///
  /// Primero en segundo plano; si el sistema no puede, con la descarga normal.
  Future<({DownloadTask task, int bytes})?> _downloadPart(DownloadTask start, int tag, File file, {required int baseBytes}) async {
    if (_backgroundOk) {
      try {
        return await _downloadPartInBackground(start, tag, file, baseBytes: baseBytes);
      } on _GaveUp catch (e) {
        DiagLog.write('[${start.videoId}] segundo plano: $e; sigue con la descarga normal');
        // En iOS el sistema podría no mandar el cuerpo del POST de visionOS en segundo plano:
        // si se rinde una vez, el resto de la sesión va directo a la descarga normal.
        if (Platform.isIOS) _backgroundOk = false;
      } on MediaToolsException catch (e) {
        DiagLog.write('descargas en segundo plano no disponibles ($e); se usa la descarga normal');
        _backgroundOk = false;
      }
      await _deleteChunkFiles(file);
      await _cancelTransfers(start.id);
      if (!_stillRunning(start.id)) return null;
    }
    return _downloadPartStreaming(start, tag, file, baseBytes: baseBytes);
  }

  // ---- en segundo plano ----

  String _chunkPath(File file, int index) => '${file.path}.b$index';

  Future<void> _deleteChunkFiles(File file) async {
    final dir = file.parent;
    if (!await dir.exists()) return;
    final prefix = '${p.basename(file.path)}.b';
    await for (final e in dir.list()) {
      if (p.basename(e.path).startsWith(prefix)) await e.delete();
    }
  }

  Future<void> _cancelTransfers(int taskId) async {
    try {
      await BackgroundTransfers.cancel(transferPrefix(taskId));
    } catch (_) {
      // Sin soporte del sistema no hay nada que cancelar.
    }
  }

  /// De dónde salen los bytes: tamaño (0 = desconocido) y cómo pedir un rango.
  Future<_Source> _sourceFor(DownloadTask t, int tag, {bool refresh = false}) async {
    if (!t.isDirect) {
      final s = await _yt.streamUrl(t.videoId, tag, refresh: refresh);
      return _Source(s.total, (from, to) => _yt.chunkRequest(s.url, from, to));
    }
    final url = Uri.parse(t.sourceUrl!);
    var total = 0;
    var ranges = false;
    try {
      final head = await _directClient.head(url, headers: _directHeaders).timeout(const Duration(seconds: 20));
      if (head.statusCode < 400) {
        total = int.tryParse(head.headers['content-length'] ?? '') ?? 0;
        ranges = (head.headers['accept-ranges'] ?? '').contains('bytes');
      }
    } catch (_) {}
    // Sin rangos no se puede partir ni reanudar: un solo bloque con todo el archivo.
    if (!ranges) total = 0;
    return _Source(
      total,
      (from, to) => (url: url, method: 'GET', headers: {..._directHeaders, if (to != null) 'Range': 'bytes=$from-$to'}, body: null),
    );
  }

  Future<({DownloadTask task, int bytes})?> _downloadPartInBackground(DownloadTask start, int tag, File file, {required int baseBytes}) async {
    var t = start;
    _Source source;
    try {
      source = await _sourceFor(t, tag);
    } catch (e) {
      await _fail(t, e);
      return null;
    }
    var already = await file.exists() ? await file.length() : 0;
    if (source.total <= 0 && already > 0) {
      // Tamaño desconocido: no se puede saber dónde seguir; se empieza de nuevo.
      await file.delete();
      already = 0;
    }
    if (source.total > 0 && already >= source.total) return (task: t, bytes: baseBytes + already);

    final chunks = planChunks(already, source.total);
    final prefix = '${transferPrefix(t.id)}$tag:';
    final failures = <int, int>{};
    final enqueuedAt = <int, DateTime>{};
    var lastDb = DateTime.now();
    DateTime? lastAt;
    var lastBytes = 0;
    var speed = 0;

    while (true) {
      if (!_stillRunning(t.id)) {
        await _cancelTransfers(t.id);
        return null;
      }
      final status = await BackgroundTransfers.status(prefix);
      var have = 0;
      var running = 0;
      var complete = true;
      var renew = false;
      final pending = <Chunk>[];
      for (final c in chunks) {
        final f = File(_chunkPath(file, c.index));
        final length = await f.exists() ? await f.length() : 0;
        final st = status['$prefix${c.index}'];
        final at = enqueuedAt[c.index];
        final action = decideChunk(
          chunk: c,
          fileLength: length,
          state: st?.state,
          http: st?.http,
          failures: failures[c.index] ?? 0,
          justEnqueued: at != null && DateTime.now().difference(at) < const Duration(seconds: 8),
        );
        switch (action) {
          case ChunkAction.done:
            have += length;
          case ChunkAction.wait:
            complete = false;
            running++;
            have += st?.bytes ?? 0;
          case ChunkAction.renew:
            complete = false;
            renew = true;
            failures[c.index] = (failures[c.index] ?? 0) + 1;
            pending.add(c);
          case ChunkAction.enqueue:
            complete = false;
            if (countsAsFailure(st?.state, fileLength: length, chunk: c)) failures[c.index] = (failures[c.index] ?? 0) + 1;
            pending.add(c);
          case ChunkAction.giveUp:
            throw _GaveUp('el bloque ${c.index} falló $maxChunkFailures veces (${st?.error ?? 'HTTP ${st?.http}'})');
        }
      }
      if (complete) break;

      if (renew) {
        DiagLog.write('[${t.videoId} itag $tag] segundo plano: URL caducada; se pide otra');
        try {
          final fresh = await _sourceFor(t, tag, refresh: true);
          if (source.total > 0 && fresh.total != source.total) {
            throw const AppException('Esa calidad ya no está disponible. Elige otra.');
          }
          source = fresh;
        } catch (e) {
          await _cancelTransfers(t.id);
          await _fail(t, e);
          return null;
        }
      }
      for (final c in pending.take(math.max(0, _parallelChunks - running))) {
        final spec = source.request(c.from, c.to);
        await BackgroundTransfers.enqueue(
          id: '$prefix${c.index}',
          url: spec.url,
          destination: _chunkPath(file, c.index),
          method: spec.method,
          headers: spec.headers,
          body: spec.body,
        );
        enqueuedAt[c.index] = DateTime.now();
      }

      final now = DateTime.now();
      final received = already + have;
      if (lastAt != null) {
        final ms = now.difference(lastAt).inMilliseconds;
        if (ms > 0 && received >= lastBytes) speed = ((received - lastBytes) * 1000 / ms).round();
      }
      lastAt = now;
      lastBytes = received;
      final persist = now.difference(lastDb) >= _dbInterval;
      if (persist) lastDb = now;
      t = t.copyWith(downloadedBytes: baseBytes + received, bytesPerSecond: speed);
      await _save(t, persist: persist);
      await Future<void>.delayed(const Duration(seconds: 1));
    }

    // Unir los bloques en orden al archivo parcial.
    final sink = file.openWrite(mode: FileMode.append);
    try {
      for (final c in chunks) {
        await sink.addStream(File(_chunkPath(file, c.index)).openRead());
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    await _deleteChunkFiles(file);
    await _cancelTransfers(t.id);
    final length = await file.length();
    if (source.total > 0 && length != source.total) {
      await file.delete();
      await _fail(t, const AppException('La descarga quedó incompleta. Toca reintentar.'));
      return null;
    }
    return (task: t.copyWith(downloadedBytes: baseBytes + length), bytes: baseBytes + length);
  }

  // ---- dentro de la app (respaldo) ----

  /// Enlace directo desde [start] (con Range si se puede). Si el servidor ignora el rango, se
  /// saltan los bytes que ya se tienen.
  Future<({Stream<List<int>> bytes, int total})> _openDirect(Uri url, int start) async {
    final request = http.Request('GET', url)..headers.addAll(_directHeaders);
    if (start > 0) request.headers['Range'] = 'bytes=$start-';
    final response = await _directClient.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200 && response.statusCode != 206) {
      await response.stream.drain<void>();
      throw AppException('El enlace respondió HTTP ${response.statusCode}.');
    }
    final length = response.contentLength ?? 0;
    if (response.statusCode == 206) return (bytes: response.stream, total: length > 0 ? start + length : 0);
    return (bytes: start > 0 ? _skip(response.stream, start) : response.stream, total: length);
  }

  static Stream<List<int>> _skip(Stream<List<int>> source, int count) async* {
    var left = count;
    await for (final chunk in source) {
      if (left <= 0) {
        yield chunk;
      } else if (chunk.length <= left) {
        left -= chunk.length;
      } else {
        yield chunk.sublist(left);
        left = 0;
      }
    }
  }

  Future<({DownloadTask task, int bytes})?> _downloadPartStreaming(DownloadTask start, int tag, File file, {required int baseBytes}) async {
    var t = start;
    final already = await file.exists() ? await file.length() : 0;
    final ({Stream<List<int>> bytes, int total}) opened;
    try {
      opened = t.isDirect ? await _openDirect(Uri.parse(t.sourceUrl!), already) : await _yt.open(t.videoId, tag, start: already);
    } catch (e) {
      await _fail(t.copyWith(downloadedBytes: baseBytes + already), e);
      return null;
    }
    if (!_stillRunning(t.id)) return null;
    if (opened.total > 0 && already >= opened.total) return (task: t, bytes: baseBytes + already);

    final sink = file.openWrite(mode: FileMode.append);
    final done = Completer<bool>();
    var received = already;
    var lastUi = DateTime.now();
    var lastDb = DateTime.now();
    var windowStart = DateTime.now();
    var windowBytes = 0;
    var speed = 0;

    final sub = opened.bytes.listen(
      (chunk) {
        sink.add(chunk);
        received += chunk.length;
        windowBytes += chunk.length;
        final now = DateTime.now();
        final elapsed = now.difference(windowStart).inMilliseconds;
        if (elapsed >= 1000) {
          speed = (windowBytes * 1000 / elapsed).round();
          windowStart = now;
          windowBytes = 0;
        }
        if (now.difference(lastUi) >= _uiInterval) {
          lastUi = now;
          final persist = now.difference(lastDb) >= _dbInterval;
          if (persist) lastDb = now;
          t = t.copyWith(downloadedBytes: baseBytes + received, bytesPerSecond: speed);
          unawaited(_save(t, persist: persist));
        }
      },
      onError: (Object e) {
        if (!done.isCompleted) done.completeError(e);
      },
      onDone: () {
        if (!done.isCompleted) done.complete(true);
      },
      cancelOnError: true,
    );
    _jobs[t.id] = _Job(sub, sink, done);

    try {
      final completed = await done.future;
      if (!completed) return null; // cancelada
    } catch (e) {
      await _closeJob(t.id);
      await _fail(t.copyWith(downloadedBytes: baseBytes + received), e);
      return null;
    }
    await _closeJob(t.id);
    if (opened.total > 0 && received < opened.total) {
      await _fail(t.copyWith(downloadedBytes: baseBytes + received),
          const AppException('La descarga se cortó. Toca reintentar para continuar donde iba.'));
      return null;
    }
    return (task: t.copyWith(downloadedBytes: baseBytes + received), bytes: baseBytes + received);
  }

  Future<void> _closeJob(int id) async {
    final job = _jobs.remove(id);
    if (job == null) return;
    try {
      await job.sink.flush();
      await job.sink.close();
    } catch (_) {}
  }

  /// Detiene una descarga en curso y cierra su archivo parcial.
  Future<void> _stopJob(int id) async {
    final job = _jobs.remove(id);
    if (job == null) return;
    await job.sub.cancel();
    if (!job.done.isCompleted) job.done.complete(false);
    try {
      await job.sink.close();
    } catch (_) {}
  }

  Future<void> _finish(DownloadTask t, File result) async {
    final root = await downloadsRoot();
    final sub = t.kind.isAudio ? 'Audio' : 'Videos';
    final dir = Directory(p.join(root.path, sub));
    await dir.create(recursive: true);
    final ext = _extensionFor(t);
    var name = '${t.fileName}.$ext';
    var n = 2;
    while (await File(p.join(dir.path, name)).exists()) {
      name = '${t.fileName} ($n).$ext';
      n++;
    }
    await result.rename(p.join(dir.path, name));
    await _save(
      t.copyWith(
        status: DownloadStatus.completed,
        filePath: p.join(sub, name),
        completedAt: DateTime.now().millisecondsSinceEpoch,
        clearSpeed: true,
        clearError: true,
      ),
      persist: true,
    );
    unawaited(_saveCover(t.videoId, url: t.thumbnail));
    if (t.isMixtape) unawaited(_trimMixtape());
  }

  /// Extensión del archivo final: la del enlace directo si es conocida (p. ej. .m4v, .aac);
  /// si no, la del formato.
  static String _extensionFor(DownloadTask t) {
    final source = t.sourceUrl;
    if (source != null) {
      final ext = p.extension(Uri.parse(source).path).replaceFirst('.', '').toLowerCase();
      if (const {'mp3', 'm4a', 'aac', 'mp4', 'm4v', 'mov'}.contains(ext)) return ext;
    }
    return t.kind.extension;
  }

  Future<void> _saveCover(String videoId, {String? url}) async {
    try {
      final file = await coverFileFor(videoId);
      if (await file.exists()) return;
      if (url == null && videoId.contains(':')) return; // enlace directo sin miniatura
      final response = await http.get(Uri.parse(url ?? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg')).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return;
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);
    } catch (_) {
      // Sin portada no pasa nada: se usa la de internet cuando haya conexión.
    }
  }

  // ---- mixtape sin conexión ----

  /// Archivo local con el audio de [videoId] (M4A/MP3, o el MP4 si solo hay video), o null.
  Future<File?> localAudioFor(String videoId) async {
    final done = state.where((t) => t.videoId == videoId && t.status == DownloadStatus.completed).toList()
      ..sort((a, b) => (a.kind.isAudio ? 0 : 1).compareTo(b.kind.isAudio ? 0 : 1));
    for (final t in done) {
      final f = await fileOf(t);
      if (f != null) return f;
    }
    return null;
  }

  /// Guarda en el mixtape el audio de algo que estás escuchando (si está activado, hay Wi-Fi
  /// cuando se pide, y no está guardado ya).
  Future<void> addToMixtape(VideoSummary video) async {
    final settings = ref.read(settingsProvider);
    if (!settings.mixtapeEnabled) return;
    if (!isMixtapeLength(video.duration)) {
      DiagLog.write('[${video.id}] mixtape: dura ${video.duration}, no parece canción; no se guarda');
      return;
    }
    if (state.any((t) => t.videoId == video.id && (t.isActive || t.status == DownloadStatus.completed))) return;
    if (settings.mixtapeWifiOnly) {
      final net = await Connectivity().checkConnectivity();
      if (!net.contains(ConnectivityResult.wifi) && !net.contains(ConnectivityResult.ethernet)) {
        DiagLog.write('[${video.id}] mixtape: sin Wi-Fi, no se guarda');
        return;
      }
    }
    try {
      final audio = await _yt.bestAudio(video.id);
      await enqueue(
        video,
        DownloadOption(kind: OutputKind.m4a, label: 'Mixtape', tag: audio.tag, sizeBytes: audio.size),
        mixtape: true,
      );
      DiagLog.write('[${video.id}] mixtape: guardando "${video.title}"');
    } catch (e) {
      DiagLog.write('[${video.id}] mixtape: no se pudo guardar: $e');
    }
  }

  /// Si el mixtape pasa del límite, borra las canciones guardadas solas más antiguas.
  Future<void> _trimMixtape() async {
    final max = ref.read(settingsProvider).mixtapeMax;
    final auto = state.where((t) => t.isMixtape && t.status == DownloadStatus.completed).toList()
      ..sort((a, b) => (b.completedAt ?? 0).compareTo(a.completedAt ?? 0));
    for (final old in auto.skip(max)) {
      await remove(old.id, deleteFile: true);
    }
  }

  /// Fija en la biblioteca algo que se guardó solo: ya no se borra al pasar el límite.
  Future<void> keep(int id) async {
    final t = _find(id);
    if (t != null && t.isMixtape) await _save(t.copyWith(isMixtape: false), persist: true);
  }

  /// Borra todo lo que se guardó solo para el mixtape (no toca tus descargas).
  Future<int> clearMixtape() async {
    final auto = state.where((t) => t.isMixtape).toList();
    for (final t in auto) {
      await remove(t.id, deleteFile: true);
    }
    return auto.length;
  }

  Future<void> _fail(DownloadTask t, Object e) => _save(
        t.copyWith(status: DownloadStatus.failed, error: e is AppException ? e.message : 'Error al descargar: $e', clearSpeed: true),
        persist: true,
      );

  Future<void> _save(DownloadTask t, {required bool persist}) async {
    // Si se canceló o se quitó mientras tanto, no revivir la tarea.
    final current = _find(t.id);
    if (current == null) return;
    if (current.status == DownloadStatus.cancelled && t.status != DownloadStatus.pending) return;
    // Campos que cambian fuera de la descarga en curso (volumen que llegó después, "fijar" del
    // mixtape): la copia vieja que lleva el trabajo no debe pisarlos.
    if (t.loudnessDb == null && current.loudnessDb != null) t = t.copyWith(loudnessDb: current.loudnessDb);
    if (!current.isMixtape && t.isMixtape) t = t.copyWith(isMixtape: false);
    state = [for (final x in state) if (x.id == t.id) t else x];
    if (persist) await (await _database).update(t);
  }
}

/// Bytes de un archivo: tamaño (0 = desconocido) y cómo pedir el rango [from]..[to].
class _Source {
  _Source(this.total, this.request);
  final int total;
  final ({Uri url, String method, Map<String, String> headers, List<int>? body}) Function(int from, int? to) request;
}

/// El segundo plano no pudo con un bloque: se sigue con la descarga normal.
class _GaveUp implements Exception {
  _GaveUp(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

class _Job {
  _Job(this.sub, this.sink, this.done);
  final StreamSubscription<List<int>> sub;
  final IOSink sink;
  final Completer<bool> done;
}

/// El mixtape guarda canciones, no podcasts ni transmisiones: hasta 15 minutos (o duración
/// desconocida). Los directos no tienen archivo que guardar.
const mixtapeMaxLength = Duration(minutes: 15);

bool isMixtapeLength(Duration? d) => d == null || (d > Duration.zero && d <= mixtapeMaxLength);

final downloadsProvider = NotifierProvider<DownloadsNotifier, List<DownloadTask>>(DownloadsNotifier.new);
