import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../core/diag_log.dart';
import 'innertube_parser.dart';
import 'js_solver.dart';
import 'visionos_client.dart';
import 'models.dart';
import 'stream_fetch.dart';
import 'stream_selection.dart';

/// Error con un mensaje listo para mostrar.
class AppException implements Exception {
  const AppException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Una página de resultados y cómo pedir la siguiente.
class PagedResult<T> {
  const PagedResult(this.items, [this._next]);
  final List<T> items;
  final Future<PagedResult<T>> Function()? _next;

  bool get hasMore => _next != null;

  /// Página siguiente (vacía y sin más si no hay).
  Future<PagedResult<T>> next() => _next?.call() ?? Future.value(PagedResult<T>(const []));
}

/// Qué se busca en la pestaña Buscar.
enum SearchKind { videos, playlists, channels }

/// Acceso a YouTube con youtube_explode_dart (sin API key).
///
/// Usa el cliente por defecto de la librería (androidSdkless), que no necesita resolver el
/// desafío JavaScript de YouTube. Si YouTube cambia y deja de funcionar, actualizar la librería.
class YouTubeService {
  YouTubeService() : _http = _UserAgentHttpClient() {
    _yt = yt.YoutubeExplode(httpClient: _http);
  }

  final yt.YoutubeHttpClient _http;
  late final yt.YoutubeExplode _yt;

  /// Manifiestos recientes por video: las URL de YouTube caducan en unas horas.
  final _manifests = <String, ({DateTime at, yt.StreamManifest manifest})>{};

  /// Clientes de YouTube para pedir los bytes, en orden. Desde 2025 YouTube exige un token
  /// anti-bots (PO token) a los clientes Android/iOS; los clientes web (Safari) y TV no lo piden
  /// pero necesitan resolver un reto JavaScript ([MobileEJSSolver]).
  /// null en `clients` = el cliente por defecto de la librería (androidSdkless).
  static final _clients = <({String name, List<yt.YoutubeApiClient>? clients, bool solver})>[
    (name: 'Safari (web)', clients: [yt.YoutubeApiClient.safari], solver: true),
    (name: 'TV', clients: [yt.YoutubeApiClient.tv], solver: true),
    (name: 'Android', clients: null, solver: false),
    (name: 'Android VR', clients: [yt.YoutubeApiClient.androidVr], solver: false),
    (name: 'iOS', clients: [yt.YoutubeApiClient.ios], solver: false),
  ];

  /// Cliente para la información (calidades disponibles, tamaños): rápido y sin reto JavaScript.
  static const _infoClient = 2;

  /// Instancia de la librería con el solucionador JS (se prepara la primera vez que hace falta).
  Future<yt.YoutubeExplode?>? _solverYtFuture;
  MobileEJSSolver? _solver;
  DateTime? _solverFailedAt;

  /// Último cliente que funcionó por video (para no repetir los que fallan).
  /// [_visionOsIndex] = visionOS; 0.. = índice en [_clients].
  final _workingClient = <String, int>{};
  static const _visionOsIndex = -1;

  /// Cliente visionOS, el que usa NewPipe (ver visionos_client.dart).
  late final VisionOsClient _visionOs = VisionOsClient(_bytesClient);
  final _visionPlayers = <String, ({DateTime at, VisionOsPlayer player})>{};
  int _requestNumber = 0;

  /// Cliente HTTP propio para los bytes (con el User-Agent correcto por petición).
  final _bytesClient = http.Client();
  static const _manifestTtl = Duration(minutes: 30);
  static const _playlistPage = 50;

  // ---- búsqueda ----

  /// Sugerencias mientras escribes (las mismas que da YouTube). Sin internet, lista vacía.
  Future<List<String>> suggestions(String query) async {
    if (query.trim().isEmpty) return const [];
    try {
      return (await _yt.search.getQuerySuggestions(query.trim())).take(8).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Volumen de la canción según YouTube (ver [VisionOsPlayer.loudnessDb]); null si no se sabe.
  /// Usa la misma respuesta de visionOS que la reproducción (en caché), así no gasta otra petición.
  Future<double?> loudnessDb(String videoId) async {
    try {
      return (await _visionPlayer(videoId)).loudnessDb;
    } catch (_) {
      return null;
    }
  }

  Future<PagedResult<VideoSummary>> search(String query) => _guard(() async => _videoPage(await _yt.search.search(query)));

  PagedResult<VideoSummary> _videoPage(yt.VideoSearchList list) => PagedResult(
        list.map(_summary).toList(),
        list.isEmpty ? null : () => _guard(() async {
              final next = await list.nextPage();
              return next == null ? const PagedResult<VideoSummary>([]) : _videoPage(next);
            }),
      );

  Future<PagedResult<PlaylistSummary>> searchPlaylists(String query) => _guard(() async =>
      _contentPage(await _yt.search.searchContent(query, filter: yt.TypeFilters.playlist), (r) => r is yt.SearchPlaylist ? _playlistSummary(r) : null));

  Future<PagedResult<ChannelSummary>> searchChannels(String query) => _guard(() async =>
      _contentPage(await _yt.search.searchContent(query, filter: yt.TypeFilters.channel), (r) => r is yt.SearchChannel ? _channelSummary(r) : null));

  PagedResult<T> _contentPage<T>(yt.SearchList list, T? Function(yt.SearchResult) map) => PagedResult(
        list.map(map).whereType<T>().toList(),
        list.isEmpty ? null : () => _guard(() async {
              final next = await list.nextPage();
              return next == null ? PagedResult<T>(const []) : _contentPage(next, map);
            }),
      );

  // ---- ver video ----

  Future<WatchInfo> watch(String videoId, {int? maxHeight, int mp3Kbps = 192}) => _guard(() async {
        final video = await _yt.videos.get(videoId);
        final manifest = await _manifest(videoId);
        final candidates = manifest.streams.map(_candidate).toList();
        final playable = pickPlayableMuxed(candidates);
        List<VideoSummary> related = const [];
        try {
          final list = await _yt.videos.getRelatedVideos(video);
          related = list?.map(_summary).where((v) => v.id != videoId).toList() ?? const [];
        } catch (_) {
          // Los relacionados son opcionales: si fallan, la pantalla funciona igual.
        }
        return WatchInfo(
          video: _summary(video),
          description: video.description,
          likeCount: video.engagement.likeCount,
          related: related,
          playableUrl: playable == null ? null : _byTag(manifest, playable.tag)?.url,
          downloadOptions: buildDownloadOptions(candidates, maxHeight: maxHeight, mp3Kbps: mp3Kbps),
        );
      });

  /// Flujo de audio (M4A) para escuchar: su itag y tamaño total.
  Future<({int tag, int size})> bestAudio(String videoId) => _guard(() async {
        final manifest = await _manifest(videoId);
        final audio = pickBestAudio(manifest.streams.map(_candidate).toList());
        if (audio == null) throw const AppException('Este video no tiene audio disponible.');
        return (tag: audio.tag, size: audio.sizeBytes);
      });

  /// Bytes del flujo [tag] desde [start], pedidos por bloques de 10 MB con el User-Agent del
  /// cliente que generó la URL.
  ///
  /// Si YouTube rechaza la URL (403), se prueba con otro cliente (Android → Android VR → iOS).
  /// Si caduca a mitad de la descarga, se pide un manifiesto nuevo y se sigue donde iba.
  /// Nunca se queda esperando para siempre: cada petición tiene tiempo límite y los errores se
  /// muestran (la librería reintentaba los 403 sin fin y la descarga se quedaba en 0 B).
  Future<({Stream<List<int>> bytes, int total})> open(String videoId, int tag, {int start = 0}) => _guard(() async {
        yt.StreamInfo? original;
        try {
          original = _byTag(await _manifest(videoId), tag);
        } catch (e) {
          DiagLog.write('[$videoId itag $tag] manifiesto de información falló: $e');
        }
        final problems = <String>[];
        // 1. visionOS, como NewPipe (sin token anti-bots ni reto JavaScript).
        final remembered = _workingClient[videoId];
        if (remembered == null || remembered == _visionOsIndex) {
          try {
            final opened = await _openVisionOs(videoId, tag, start, original);
            if (opened != null) return opened;
            problems.add('visionOS: sin esa calidad');
          } catch (e) {
            problems.add('visionOS: $e');
            DiagLog.write('[$videoId itag $tag] visionOS falló: $e');
          }
        }
        // 2. Los demás clientes.
        final firstClient = remembered == null || remembered < 0 ? 0 : remembered;
        for (var c = firstClient; c < _clients.length; c++) {
          yt.StreamInfo? info;
          try {
            final manifest = await _manifest(videoId, client: c);
            info = _byTag(manifest, tag);
            // Otro cliente puede no tener el mismo itag: se busca uno equivalente (solo si se empieza
            // de cero; para reanudar hace falta exactamente el mismo archivo).
            if (info == null && start == 0 && original != null) info = _equivalent(manifest, original);
            if (info != null && start > 0 && original != null && info.size.totalBytes != original.size.totalBytes) info = null;
          } catch (e, st) {
            problems.add('${_clients[c].name}: $e');
            final where = st.toString().split('\n').take(6).join(' | ');
            DiagLog.write('[$videoId itag $tag] manifiesto ${_clients[c].name} falló: $e · en: $where');
            continue;
          }
          if (info == null) {
            problems.add('${_clients[c].name}: sin esa calidad');
            DiagLog.write('[$videoId itag $tag] ${_clients[c].name}: el manifiesto no tiene esa calidad');
            continue;
          }
          final total = info.size.totalBytes;
          final response = await _requestChunk(info.url, start, total);
          DiagLog.write('[$videoId itag $tag] ${_clients[c].name}: HTTP ${response.statusCode} '
              'type=${response.headers['content-type']} len=${response.contentLength} desde=$start · ${DiagLog.describeUrl(info.url)}');
          if (response.statusCode == 200 || response.statusCode == 206) {
            _workingClient[videoId] = c;
            final itag = info.tag;
            return (
              bytes: _chunks(videoId, itag, info.url, response, start, total,
                  () async => _byTag(await _manifest(videoId, client: c, refresh: true), itag)?.url),
              total: total,
            );
          }
          final body = await response.stream.bytesToString().catchError((_) => '');
          problems.add('${_clients[c].name}: HTTP ${response.statusCode}');
          DiagLog.write('[$videoId itag $tag] ${_clients[c].name}: respuesta ${body.length > 200 ? body.substring(0, 200) : body}');
        }
        throw AppException('YouTube rechazó la descarga (${problems.join('; ')}). '
            'Inténtalo más tarde o actualiza youtube_explode_dart.');
      });

  /// Sigue pidiendo bloques hasta completar [total].
  Stream<List<int>> _chunks(String videoId, int tag, Uri url, http.StreamedResponse first, int start, int total,
      Future<Uri?> Function() renewUrl) async* {
    var position = start;
    var response = first;
    var currentUrl = url;
    var failures = 0;
    while (true) {
      try {
        // Si deja de llegar información 30 s, se corta y se pide de nuevo desde donde iba.
        await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
          position += chunk.length;
          yield chunk;
        }
      } catch (e) {
        if (++failures > 3) rethrow;
        DiagLog.write('[$videoId itag $tag] bloque cortado en $position: $e');
      }
      if (total <= 0 || position >= total) return;
      response = await _requestChunk(currentUrl, position, total);
      if (response.statusCode == 403) {
        // La URL caducó: se pide una nueva al mismo cliente.
        DiagLog.write('[$videoId itag $tag] 403 a mitad de la descarga en $position; se renueva la URL');
        await response.stream.drain<void>();
        final renewed = await renewUrl();
        if (renewed == null) throw const AppException('Esa calidad ya no está disponible. Elige otra.');
        currentUrl = renewed;
        response = await _requestChunk(currentUrl, position, total);
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        DiagLog.write('[$videoId itag $tag] bloque en $position: HTTP ${response.statusCode}');
        await response.stream.drain<void>();
        throw AppException('YouTube cortó la descarga (HTTP ${response.statusCode}). Toca reintentar para continuar.');
      }
    }
  }

  Future<http.StreamedResponse> _requestChunk(Uri url, int from, int total) {
    final spec = chunkRequest(url, from, total > 0 ? chunkEnd(from, total) : null);
    final request = http.Request(spec.method, spec.url)..headers.addAll(spec.headers);
    if (spec.body != null) request.bodyBytes = spec.body!;
    return _bytesClient.send(request).timeout(const Duration(seconds: 30));
  }

  /// Petición de los bytes [from]..[to] (inclusive; [to] null = hasta el final) de [url], tal como
  /// la quiere el cliente que generó la URL. La usan las descargas normales y las de segundo plano.
  ///
  /// visionOS: como el reproductor de NewPipe, POST con cuerpo 0x78 0x00 y parámetro `rn`.
  ({Uri url, String method, Map<String, String> headers, List<int>? body}) chunkRequest(Uri url, int from, int? to) {
    var target = to != null ? chunkUrl(url, from, to) : url;
    final visionOs = url.queryParameters['c'] == VisionOsClient.clientName;
    if (visionOs) target = Uri.parse('$target&rn=${++_requestNumber}');
    return (
      url: target,
      method: visionOs ? 'POST' : 'GET',
      headers: {
        'User-Agent': userAgentFor(url),
        'Accept': '*/*',
        if (visionOs) ...{'Accept-Encoding': 'identity', 'TE': 'trailers'},
      },
      body: visionOs ? VisionOsClient.postBody : null,
    );
  }

  /// URL que YouTube sí entrega para el flujo [tag] y su tamaño, para descargarlo por bloques en
  /// segundo plano. Prueba visionOS y luego los demás clientes (con una petición de 2 bytes).
  /// Con [refresh] pide URL nuevas (la anterior caducó: HTTP 403).
  Future<({Uri url, int total, int tag})> streamUrl(String videoId, int tag, {bool refresh = false}) => _guard(() async {
        final problems = <String>[];
        try {
          final player = await _visionPlayer(videoId, refresh: refresh);
          final format = _visionFormat(player, tag);
          if (format != null && format.contentLength > 0 && await _probe(format.url)) {
            _workingClient[videoId] = _visionOsIndex;
            return (url: format.url, total: format.contentLength, tag: format.itag);
          }
          problems.add('visionOS: ${format == null ? 'sin esa calidad' : 'no respondió'}');
        } catch (e) {
          problems.add('visionOS: $e');
        }
        for (var c = 0; c < _clients.length; c++) {
          try {
            final info = _byTag(await _manifest(videoId, client: c, refresh: refresh), tag);
            if (info == null) {
              problems.add('${_clients[c].name}: sin esa calidad');
              continue;
            }
            if (await _probe(info.url)) {
              _workingClient[videoId] = c;
              return (url: info.url, total: info.size.totalBytes, tag: info.tag);
            }
            problems.add('${_clients[c].name}: no respondió');
          } catch (e) {
            problems.add('${_clients[c].name}: $e');
          }
        }
        DiagLog.write('[$videoId itag $tag] sin URL para segundo plano: ${problems.join(' · ')}');
        throw AppException('YouTube no entregó este archivo (${problems.join('; ')}).');
      });

  /// ¿La URL responde? Pide solo 2 bytes.
  Future<bool> _probe(Uri url) async {
    final spec = chunkRequest(url, 0, 1);
    final request = http.Request(spec.method, spec.url)..headers.addAll(spec.headers);
    if (spec.body != null) request.bodyBytes = spec.body!;
    try {
      final response = await _bytesClient.send(request).timeout(const Duration(seconds: 20));
      await response.stream.drain<void>();
      return response.statusCode == 200 || response.statusCode == 206;
    } catch (_) {
      return false;
    }
  }

  // ---- visionOS (portado de NewPipe) ----

  Future<VisionOsPlayer> _visionPlayer(String videoId, {bool refresh = false}) async {
    final cached = _visionPlayers[videoId];
    if (!refresh && cached != null && DateTime.now().difference(cached.at) < _manifestTtl) return cached.player;
    final player = await _visionOs.player(videoId);
    DiagLog.write('[$videoId] visionOS: ${player.formats.length} formatos, HLS=${player.hlsManifestUrl != null}');
    _visionPlayers[videoId] = (at: DateTime.now(), player: player);
    if (_visionPlayers.length > 50) _visionPlayers.remove(_visionPlayers.keys.first);
    return player;
  }

  static VisionOsFormat? _visionFormat(VisionOsPlayer p, int itag) {
    for (final f in p.formats) {
      if (f.itag == itag) return f;
    }
    return null;
  }

  /// Formato equivalente al [original] de otro cliente: mismo tipo, contenedor y altura.
  VisionOsFormat? _visionEquivalent(VisionOsPlayer p, yt.StreamInfo original) {
    final c = _candidate(original);
    final matches = p.formats
        .where((f) => f.hasVideo == c.hasVideo && f.hasAudio == c.hasAudio && f.container == c.container && f.height == c.height)
        .toList()
      ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    return matches.isEmpty ? null : matches.first;
  }

  Future<({Stream<List<int>> bytes, int total})?> _openVisionOs(String videoId, int tag, int start, yt.StreamInfo? original) async {
    final player = await _visionPlayer(videoId);
    var format = _visionFormat(player, tag);
    if (format == null && start == 0 && original != null) format = _visionEquivalent(player, original);
    if (format != null && start > 0 && original != null && format.contentLength != original.size.totalBytes) format = null;
    if (format == null) {
      DiagLog.write('[$videoId itag $tag] visionOS no tiene esa calidad');
      return null;
    }
    final total = format.contentLength > 0 ? format.contentLength : (original?.size.totalBytes ?? 0);
    final response = await _requestChunk(format.url, start, total);
    DiagLog.write('[$videoId itag $tag] visionOS: HTTP ${response.statusCode} '
        'type=${response.headers['content-type']} len=${response.contentLength} desde=$start · ${DiagLog.describeUrl(format.url)}');
    if (response.statusCode == 200 || response.statusCode == 206) {
      _workingClient[videoId] = _visionOsIndex;
      final itag = format.itag;
      return (
        bytes: _chunks(videoId, itag, format.url, response, start, total,
            () async => _visionFormat(await _visionPlayer(videoId, refresh: true), itag)?.url),
        total: total,
      );
    }
    final body = await response.stream.bytesToString().catchError((_) => '');
    DiagLog.write('[$videoId itag $tag] visionOS: respuesta ${body.length > 200 ? body.substring(0, 200) : body}');
    throw VisionOsException('HTTP ${response.statusCode}');
  }

  /// Flujo equivalente en otro manifiesto: mismo tipo, contenedor y altura (o el mejor audio).
  yt.StreamInfo? _equivalent(yt.StreamManifest m, yt.StreamInfo original) {
    final c = _candidate(original);
    final candidates = m.streams.where((s) {
      final x = _candidate(s);
      return x.hasVideo == c.hasVideo && x.hasAudio == c.hasAudio && x.container == c.container && x.height == c.height;
    }).toList()
      ..sort((a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
    return candidates.isEmpty ? null : candidates.first;
  }

  /// Cabeceras para que el reproductor de video pida la URL como el cliente que la generó.
  static Map<String, String> playbackHeaders(Uri url) => {'User-Agent': userAgentFor(url)};

  /// "Para ti": relacionados de los últimos videos vistos ([seedIds]), intercalados y sin repetir
  /// lo ya visto ([exclude]). Si no hay historial, videos populares.
  Future<List<VideoSummary>> recommendations(List<String> seedIds, {Set<String> exclude = const {}}) => _guard(() async {
        if (seedIds.isEmpty) return (await search('videos populares')).items;
        final lists = await Future.wait(seedIds.map((id) async {
          try {
            final video = await _yt.videos.get(id);
            final related = await _yt.videos.getRelatedVideos(video);
            return related?.map(_summary).toList() ?? const <VideoSummary>[];
          } catch (_) {
            return const <VideoSummary>[];
          }
        }));
        final seen = <String>{...exclude, ...seedIds};
        final out = <VideoSummary>[];
        final longest = lists.fold<int>(0, (m, l) => l.length > m ? l.length : m);
        for (var i = 0; i < longest; i++) {
          for (final l in lists) {
            if (i < l.length && seen.add(l[i].id)) out.add(l[i]);
          }
        }
        return out.isEmpty ? (await search('videos populares')).items : out;
      });

  // ---- canales ----

  /// Id del canal (UC…) a partir de un @handle.
  Future<String> channelIdForHandle(String handle) => _guard(() async => (await _yt.channels.getByHandle(handle.startsWith('@') ? handle : '@$handle')).id.value);

  Future<ChannelInfo> channel(String channelId) => _guard(() async {
        final c = await _yt.channels.get(channelId);
        return ChannelInfo(
          id: c.id.value,
          name: c.title,
          avatarUrl: _absolute(c.logoUrl),
          bannerUrl: _absolute(c.bannerUrl),
          subscribers: c.subscribersCount,
        );
      });

  /// Videos del canal: más nuevos o más populares.
  Future<PagedResult<VideoSummary>> channelVideos(String channelId, {bool popular = false}) => _guard(() async {
        final list = await _yt.channels.getUploadsFromPage(
          channelId,
          videoSorting: popular ? yt.VideoSorting.popularity : yt.VideoSorting.newest,
        );
        return _uploadsPage(list);
      });

  PagedResult<VideoSummary> _uploadsPage(yt.ChannelUploadsList list) => PagedResult(
        list.map(_summary).toList(),
        list.isEmpty ? null : () => _guard(() async {
              final next = await list.nextPage();
              return next == null ? const PagedResult<VideoSummary>([]) : _uploadsPage(next);
            }),
      );

  // ---- listas de reproducción ----

  Future<PlaylistInfo> playlist(String playlistId) => _guard(() async {
        final p = await _yt.playlists.get(playlistId);
        return PlaylistInfo(
          id: p.id.value,
          title: p.title,
          author: p.author,
          description: p.description,
          videoCount: p.videoCount,
        );
      });

  /// Videos de la lista, de 50 en 50.
  ///
  /// Primero con la librería; si devuelve 0 (YouTube cambia el formato de la página de listas y la
  /// librería descarta videos sin canal), se pide la lista directo a la API interna:
  /// 1. `browse` VL<id> (la página de la lista, con continuaciones);
  /// 2. `next` con playlistId (el panel de la lista en "ver video", hasta ~200 videos).
  Future<PagedResult<VideoSummary>> playlistVideos(String playlistId) => _guard(() async {
        try {
          final first = await _playlistChunk(StreamIterator(_yt.playlists.getVideos(playlistId)));
          if (first.items.isNotEmpty) return first;
        } on AppException {
          rethrow;
        } catch (e) {
          developer.log('getVideos falló, se usa el respaldo: $e', name: 'YouTubeService');
        }
        return _playlistFallback(playlistId);
      });

  Future<PagedResult<VideoSummary>> _playlistFallback(String playlistId) async {
    try {
      final browse = await _http.sendPost('browse', {'browseId': 'VL$playlistId'});
      final items = InnerTubeParser.videos(browse);
      developer.log('browse VL$playlistId: ${InnerTubeParser.describe(items)}', name: 'YouTubeService');
      if (items.isNotEmpty) return _browsePage(items, InnerTubeParser.continuation(browse));
    } catch (e) {
      developer.log('browse falló: $e', name: 'YouTubeService');
    }
    final next = await _http.sendPost('next', {'playlistId': playlistId});
    final items = InnerTubeParser.videos(next);
    developer.log('next $playlistId: ${InnerTubeParser.describe(items)}', name: 'YouTubeService');
    return PagedResult(items);
  }

  PagedResult<VideoSummary> _browsePage(List<VideoSummary> items, String? token) => PagedResult(
        items,
        token == null
            ? null
            : () => _guard(() async {
                  final json = await _http.sendContinuation('browse', token);
                  final more = InnerTubeParser.videos(json);
                  final nextToken = InnerTubeParser.continuation(json);
                  // Sin videos nuevos o el mismo token: se terminó.
                  return _browsePage(more, more.isEmpty || nextToken == token ? null : nextToken);
                }),
      );

  Future<PagedResult<VideoSummary>> _playlistChunk(StreamIterator<yt.Video> it) async {
    final items = <VideoSummary>[];
    var more = false;
    while (items.length < _playlistPage) {
      if (!await it.moveNext()) break;
      items.add(_summary(it.current));
      more = items.length == _playlistPage;
    }
    if (!more) await it.cancel();
    return PagedResult(items, more ? () => _guard(() => _playlistChunk(it)) : null);
  }

  void close() {
    _bytesClient.close();
    _solver?.dispose();
    _yt.close();
  }

  /// La librería con el solucionador. Si no se pudo preparar, null (se reintenta en 5 minutos).
  Future<yt.YoutubeExplode?> _solverYt() {
    final failed = _solverFailedAt;
    if (failed != null && DateTime.now().difference(failed) < const Duration(minutes: 5)) return Future.value(null);
    return _solverYtFuture ??= () async {
      try {
        final solver = _solver = await MobileEJSSolver.init();
        _solverFailedAt = null;
        return yt.YoutubeExplode(httpClient: _http, jsSolver: solver);
      } catch (e) {
        DiagLog.write('solucionador JS no disponible: $e');
        _solverFailedAt = DateTime.now();
        _solverYtFuture = null;
        return null;
      }
    }();
  }

  /// URL de video con audio (para ver en la app) que YouTube sí entregue: se prueba cada cliente
  /// con una petición mínima. null si ninguno funciona.
  Future<Uri?> playableUrl(String videoId) async {
    // visionOS primero: su manifiesto HLS (video con audio, varias calidades) o un MP4 con audio.
    try {
      final p = await _visionPlayer(videoId);
      final candidates = <Uri>[
        if (p.hlsManifestUrl != null) p.hlsManifestUrl!,
        ...(p.formats.where((f) => f.hasVideo && f.hasAudio && f.container == 'mp4').toList()
              ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0)))
            .map((f) => f.url),
      ];
      for (final url in candidates) {
        // El reproductor de video pide con GET: se prueba igual.
        final probe = await _bytesClient
            .send(http.Request('GET', url.path.contains('/hls') ? url : chunkUrl(url, 0, 1))..headers.addAll(playbackHeaders(url)))
            .timeout(const Duration(seconds: 20));
        await probe.stream.drain<void>();
        DiagLog.write('[$videoId ver] visionOS: HTTP ${probe.statusCode} · ${url.host}${url.path.length > 40 ? url.path.substring(0, 40) : url.path}');
        if (probe.statusCode == 200 || probe.statusCode == 206) return url;
      }
    } catch (e) {
      DiagLog.write('[$videoId ver] visionOS falló: $e');
    }
    final remembered = _workingClient[videoId];
    for (var c = remembered == null || remembered < 0 ? 0 : remembered; c < _clients.length; c++) {
      try {
        final manifest = await _manifest(videoId, client: c);
        final muxed = pickPlayableMuxed(manifest.streams.map(_candidate).toList());
        final info = muxed == null ? null : _byTag(manifest, muxed.tag);
        if (info == null) continue;
        final probe = await _requestChunk(info.url, 0, 2);
        await probe.stream.drain<void>();
        DiagLog.write('[$videoId ver] ${_clients[c].name}: HTTP ${probe.statusCode} · ${DiagLog.describeUrl(info.url)}');
        if (probe.statusCode == 200 || probe.statusCode == 206) {
          _workingClient[videoId] = c;
          return info.url;
        }
      } catch (e) {
        DiagLog.write('[$videoId ver] ${_clients[c].name} falló: $e');
      }
    }
    return null;
  }

  // ---- privados ----

  Future<yt.StreamManifest> _manifest(String videoId, {bool refresh = false, int client = _infoClient}) async {
    final key = '$videoId#$client';
    final cached = _manifests[key];
    if (!refresh && cached != null && DateTime.now().difference(cached.at) < _manifestTtl) return cached.manifest;
    final spec = _clients[client];
    var lib = _yt;
    if (spec.solver) {
      final withSolver = await _solverYt();
      if (withSolver == null) throw const AppException('no se pudo preparar el solucionador de YouTube');
      lib = withSolver;
    }
    final clients = spec.clients;
    final manifest = clients == null
        ? await lib.videos.streams.getManifest(videoId)
        : await lib.videos.streams.getManifest(videoId, ytClients: clients);
    _manifests[key] = (at: DateTime.now(), manifest: manifest);
    if (_manifests.length > 60) _manifests.remove(_manifests.keys.first);
    return manifest;
  }


  yt.StreamInfo? _byTag(yt.StreamManifest m, int tag) {
    for (final s in m.streams) {
      if (s.tag == tag) return s;
    }
    return null;
  }

  static String? _absolute(String url) {
    if (url.isEmpty) return null;
    return url.startsWith('//') ? 'https:$url' : url;
  }

  static StreamCandidate _candidate(yt.StreamInfo s) => StreamCandidate(
        tag: s.tag,
        container: s.container.name,
        hasVideo: s is yt.VideoStreamInfo,
        hasAudio: s is yt.AudioStreamInfo,
        bitrate: s.bitrate.bitsPerSecond,
        sizeBytes: s.size.totalBytes,
        height: s is yt.VideoStreamInfo ? s.videoResolution.height : null,
        qualityLabel: s is yt.VideoStreamInfo ? s.qualityLabel : '',
        videoCodec: s is yt.VideoStreamInfo ? s.videoCodec : '',
        audioCodec: s is yt.AudioStreamInfo ? s.audioCodec : '',
      );

  static VideoSummary _summary(yt.Video v) => VideoSummary(
        id: v.id.value,
        title: v.title,
        author: v.author,
        channelId: v.channelId.value,
        duration: v.duration,
        viewCount: v.engagement.viewCount,
        uploadedText: v.uploadDateRaw,
        isLive: v.isLive,
      );

  static PlaylistSummary _playlistSummary(yt.SearchPlaylist p) => PlaylistSummary(
        id: p.id.value,
        title: p.title,
        videoCount: p.videoCount,
        thumbnailUrl: p.thumbnails.isEmpty ? null : _absolute(p.thumbnails.last.url.toString()),
      );

  static ChannelSummary _channelSummary(yt.SearchChannel c) => ChannelSummary(
        id: c.id.value,
        name: c.name,
        description: c.description,
        videoCount: c.videoCount,
        avatarUrl: c.thumbnails.isEmpty ? null : _absolute(c.thumbnails.last.url.toString()),
      );

  /// Convierte los errores de red y de la librería en mensajes para el usuario.
  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on AppException {
      rethrow;
    } on SocketException {
      throw const AppException('Sin conexión a internet. Revisa tu red e inténtalo de nuevo.');
    } on TimeoutException {
      throw const AppException('YouTube tardó demasiado en responder.');
    } on yt.RequestLimitExceededException {
      throw const AppException('YouTube está limitando las solicitudes desde tu red. Espera unos minutos o cambia de red.');
    } on yt.VideoUnplayableException catch (e) {
      throw AppException('Este video no se puede reproducir: ${e.message}');
    } on yt.YoutubeExplodeException catch (e) {
      throw AppException('No se pudo leer la información de YouTube. Puede que haya que actualizar '
          'youtube_explode_dart (${e.message}).');
    } on ArgumentError {
      throw const AppException('Ese enlace o identificador de YouTube no es válido.');
    }
  }
}

/// Cliente HTTP de la librería que, para las URL de googlevideo, usa el User-Agent del cliente de
/// YouTube que las generó (Android, iOS…). La librería usaba el de Chrome de escritorio, y YouTube
/// respondía 403 tanto a su comprobación del manifiesto como a las descargas.
class _UserAgentHttpClient extends yt.YoutubeHttpClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.host.endsWith('googlevideo.com')) {
      request.headers['User-Agent'] = userAgentFor(request.url);
    }
    return super.send(request);
  }
}
