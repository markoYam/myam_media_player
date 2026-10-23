import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Cliente "VISIONOS" de YouTube (la app para Apple Vision Pro), portado de NewPipeExtractor
/// (TeamNewPipe/NewPipeExtractor, `YoutubeStreamHelper.getVisionOsPlayerResponse`,
/// `ClientsConstants`, `YoutubeParsingHelper`; versión del 21-oct-2026, GPLv3).
///
/// Es el cliente con el que NewPipe obtiene hoy los flujos: no necesita token anti-bots (PO token)
/// ni resolver retos JavaScript. Pasos:
/// 1. `visitor_id` → visitorData (obligatorio para respuestas válidas).
/// 2. `player` con ese visitorData y un `cpn` aleatorio.
/// 3. Las URL de los formatos se usan con `&cpn=…` y se piden por **POST** (cuerpo `0x78 0x00`)
///    con el User-Agent de visionOS y los parámetros `rn` y `range`.
class VisionOsClient {
  VisionOsClient(this._http);
  final http.Client _http;

  static const clientName = 'VISIONOS';
  static const clientVersion = '1.04';
  static const deviceModel = 'RealityDevice17,1';
  static const osVersion = '26.6.0.23O770';
  static const _userAgentOsVersion = '26_6_0';
  static const _apiBase = 'https://youtubei.googleapis.com/youtubei/v1/';
  static const _nonceAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

  /// User-Agent exacto de NewPipe (sin espacio antes del paréntesis).
  static String userAgent({String country = 'US'}) =>
      'com.google.visionos.youtube/$clientVersion($deviceModel; U; CPU visionOS $_userAgentOsVersion like Mac OS X; $country)';

  /// Cuerpo de las peticiones de bytes (igual que el reproductor de NewPipe).
  static const postBody = [0x78, 0x00];

  static final _random = Random.secure();
  static String randomNonce(int length) =>
      String.fromCharCodes(List.generate(length, (_) => _nonceAlphabet.codeUnitAt(_random.nextInt(_nonceAlphabet.length))));

  String? _visitorData;
  DateTime? _visitorAt;

  Map<String, String> get _headers => {
        'User-Agent': userAgent(),
        'X-Goog-Api-Format-Version': '2',
        'Content-Type': 'application/json',
      };

  /// Contexto InnerTube (`prepareJsonBuilder` de NewPipe).
  static Map<String, Object?> context({String? visitorData, String hl = 'es', String gl = 'US'}) => {
        'client': {
          'clientName': clientName,
          'clientVersion': clientVersion,
          'clientScreen': 'WATCH',
          'platform': 'MOBILE',
          if (visitorData != null) 'visitorData': visitorData,
          'deviceMake': 'Apple',
          'deviceModel': deviceModel,
          'osName': 'visionOS',
          'osVersion': osVersion,
          'hl': hl,
          'gl': gl,
          'utcOffsetMinutes': 0,
        },
        'request': {'internalExperimentFlags': <Object>[], 'useSsl': true},
        'user': {'lockedSafetyMode': false},
      };

  Future<String> visitorData() async {
    final cached = _visitorData;
    final at = _visitorAt;
    if (cached != null && at != null && DateTime.now().difference(at) < const Duration(hours: 6)) return cached;
    final response = await _http
        .post(
          Uri.parse('${_apiBase}visitor_id?prettyPrint=false'),
          headers: _headers,
          body: jsonEncode({'context': context()}),
        )
        .timeout(const Duration(seconds: 20));
    final value = ((jsonDecode(response.body) as Map)['responseContext'] as Map?)?['visitorData'] as String?;
    if (value == null || value.isEmpty) {
      throw VisionOsException('YouTube no dio visitorData (HTTP ${response.statusCode})');
    }
    _visitorData = value;
    _visitorAt = DateTime.now();
    return value;
  }

  /// Respuesta de `player` ya validada.
  Future<VisionOsPlayer> player(String videoId) async {
    final visitor = await visitorData();
    final cpn = randomNonce(16);
    final url = Uri.parse('${_apiBase}player?prettyPrint=false&t=${randomNonce(12)}&id=$videoId');
    final response = await _http
        .post(
          url,
          headers: _headers,
          body: jsonEncode({
            'context': context(visitorData: visitor),
            'videoId': videoId,
            'cpn': cpn,
            'contentCheckOk': true,
            'racyCheckOk': true,
          }),
        )
        .timeout(const Duration(seconds: 20));
    final json = jsonDecode(response.body);
    if (json is! Map) throw VisionOsException('respuesta inesperada (HTTP ${response.statusCode})');
    return VisionOsPlayer.parse(json, cpn: cpn, videoId: videoId);
  }
}

class VisionOsException implements Exception {
  VisionOsException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Un formato de `streamingData` con su URL lista para pedir (con `cpn`).
class VisionOsFormat {
  const VisionOsFormat({
    required this.itag,
    required this.url,
    required this.mimeType,
    required this.bitrate,
    required this.contentLength,
    this.width,
    this.height,
    this.qualityLabel,
  });

  final int itag;
  final Uri url;

  /// `video/mp4; codecs="avc1.640028"`
  final String mimeType;
  final int bitrate;
  final int contentLength;
  final int? width;
  final int? height;
  final String? qualityLabel;

  String get container => mimeType.split(';').first.split('/').last; // mp4, webm
  String get codecs {
    final m = RegExp(r'codecs="([^"]+)"').firstMatch(mimeType);
    return m?.group(1) ?? '';
  }

  bool get hasVideo => mimeType.startsWith('video/');
  bool get hasAudio => mimeType.startsWith('audio/') || codecs.contains('mp4a') || codecs.contains('opus');
  String get videoCodec => hasVideo ? codecs.split(',').first.trim() : '';
  String get audioCodec => mimeType.startsWith('audio/') ? codecs : (codecs.contains(',') ? codecs.split(',').last.trim() : '');
}

class VisionOsPlayer {
  const VisionOsPlayer({required this.formats, this.hlsManifestUrl, this.loudnessDb});

  final List<VisionOsFormat> formats;

  /// Volumen de la canción respecto a la referencia de YouTube (`playerConfig.audioConfig.loudnessDb`):
  /// +5 = suena 5 dB más fuerte que lo normal. Null si no viene.
  final double? loudnessDb;

  /// Manifiesto HLS (video con audio en varias calidades), si YouTube lo da.
  final Uri? hlsManifestUrl;

  /// Valida `playabilityStatus` (como `checkPlayabilityStatus` de NewPipe) y lee los formatos.
  static VisionOsPlayer parse(Map<dynamic, dynamic> json, {required String cpn, required String videoId}) {
    final status = json['playabilityStatus'];
    final state = status is Map ? '${status['status'] ?? ''}' : '';
    if (state.isNotEmpty && state.toUpperCase() != 'OK') {
      final reason = status is Map ? '${status['reason'] ?? ''}' : '';
      if (reason.contains('a bot')) {
        throw VisionOsException('YouTube bloqueó temporalmente el acceso anónimo desde esta red ($state: $reason)');
      }
      throw VisionOsException('$state: $reason');
    }
    final details = json['videoDetails'];
    if (details is Map && details['videoId'] != null && details['videoId'] != videoId) {
      throw VisionOsException('la respuesta es de otro video');
    }
    final data = json['streamingData'];
    if (data is! Map) throw VisionOsException('la respuesta no trae streamingData');

    final formats = <VisionOsFormat>[];
    for (final key in const ['formats', 'adaptiveFormats']) {
      final list = data[key];
      if (list is! List) continue;
      for (final f in list) {
        if (f is! Map || f['url'] is! String) continue; // los cifrados (signatureCipher) no se usan
        final itag = f['itag'];
        if (itag is! int) continue;
        formats.add(VisionOsFormat(
          itag: itag,
          url: Uri.parse('${f['url']}&cpn=$cpn'),
          mimeType: '${f['mimeType'] ?? ''}',
          bitrate: (f['bitrate'] as num?)?.toInt() ?? 0,
          contentLength: int.tryParse('${f['contentLength'] ?? ''}') ?? 0,
          width: (f['width'] as num?)?.toInt(),
          height: (f['height'] as num?)?.toInt(),
          qualityLabel: f['qualityLabel'] as String?,
        ));
      }
    }
    final hls = data['hlsManifestUrl'];
    final config = json['playerConfig'];
    final audioConfig = config is Map ? config['audioConfig'] : null;
    final loudness = audioConfig is Map ? audioConfig['loudnessDb'] : null;
    return VisionOsPlayer(
      formats: formats,
      hlsManifestUrl: hls is String ? Uri.tryParse(hls) : null,
      loudnessDb: loudness is num && loudness.isFinite ? loudness.toDouble() : null,
    );
  }
}
