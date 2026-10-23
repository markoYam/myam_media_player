import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'dart:typed_data';

/// Error de una operación nativa, con un mensaje para el usuario.
class MediaToolsException implements Exception {
  const MediaToolsException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Operaciones de audio y video que no se pueden hacer bien en Dart.
///
/// - Android: MediaExtractor + MediaMuxer (unir) y MediaCodec + LAME (MP3).
/// - iOS: AVMutableComposition + AVAssetExportSession (unir) y AVAssetReader + LAME (MP3).
class MediaTools {
  MediaTools._();

  static const _channel = MethodChannel('com.marcoyam/media_tools');

  /// Une la pista de video H.264 de [video] (MP4) con la pista AAC de [audio] (M4A) en [output]
  /// (MP4), sin recodificar: es rápido y no pierde calidad.
  static Future<void> mergeAudioVideo({required String video, required String audio, required String output}) =>
      _call('mergeAudioVideo', {'video': video, 'audio': audio, 'output': output});

  /// Decodifica el audio de [input] y lo codifica a MP3 CBR de [bitrateKbps] en [output]
  /// (sin etiqueta ID3; se agrega aparte).
  static Future<void> transcodeToMp3({required String input, required String output, int bitrateKbps = 192}) =>
      _call('transcodeToMp3', {'input': input, 'output': output, 'bitrateKbps': bitrateKbps});

  /// Ecualizador de iOS para el audio de just_audio (ver MTEqualizer.m): [frequencies] en Hz y
  /// [gains] en dB, banda por banda. En Android se usa el AndroidEqualizer de just_audio.
  static Future<void> setEqualizer({required bool enabled, required List<double> frequencies, required List<double> gains}) =>
      _call('setEqualizer', {'enabled': enabled, 'frequencies': frequencies, 'gains': gains});

  static Future<void> _call(String method, Map<String, Object?> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException catch (e) {
      throw MediaToolsException(e.message ?? e.code);
    } on MissingPluginException {
      throw const MediaToolsException('esta plataforma no lo admite');
    }
  }
}


/// Motor JavaScript nativo: JavaScriptCore en iOS y un WebView invisible (V8) en Android.
/// Se usa para resolver los retos JavaScript de YouTube sin Deno ni Node.
class JsEngine {
  JsEngine._(this._id);
  final String _id;

  static const _channel = MethodChannel('com.marcoyam/media_tools');

  static Future<JsEngine> create() async {
    try {
      final id = await _channel.invokeMethod<String>('jsCreate');
      if (id == null) throw const MediaToolsException('no se pudo crear el motor JavaScript');
      return JsEngine._(id);
    } on PlatformException catch (e) {
      throw MediaToolsException(e.message ?? e.code);
    } on MissingPluginException {
      throw const MediaToolsException('esta plataforma no tiene motor JavaScript');
    }
  }

  /// Ejecuta [code] como script y devuelve el valor de la última expresión como texto
  /// (null si es undefined o null). Si el script lanza un error, lanza [MediaToolsException]
  /// en iOS; en Android el WebView devuelve null (conviene envolver el código en try/catch).
  Future<String?> evaluate(String code) async {
    try {
      final raw = await _channel.invokeMethod<String>('jsEval', {'id': _id, 'code': code});
      if (!Platform.isAndroid) return raw;
      // Android entrega el valor codificado como JSON.
      if (raw == null || raw == 'null' || raw == 'undefined') return null;
      final decoded = jsonDecode(raw);
      return decoded is String ? decoded : jsonEncode(decoded);
    } on PlatformException catch (e) {
      throw MediaToolsException(e.message ?? e.code);
    }
  }

  Future<void> dispose() async {
    try {
      await _channel.invokeMethod<void>('jsDispose', {'id': _id});
    } catch (_) {}
  }
}


/// Estado de una transferencia en segundo plano (ver [BackgroundTransfers]).
class TransferStatus {
  const TransferStatus({required this.state, this.bytes = 0, this.http, this.error});

  /// "running" (en curso o en cola), "done", "failed" o "lost" (se perdió: volver a pedirla).
  final String state;
  final int bytes;
  final int? http;
  final String? error;

  static TransferStatus fromMap(Map<Object?, Object?> m) => TransferStatus(
        state: '${m['state'] ?? 'lost'}',
        bytes: (m['bytes'] as num?)?.toInt() ?? 0,
        http: (m['http'] as num?)?.toInt(),
        error: m['error'] as String?,
      );
}

/// Descargas del sistema que siguen con la app minimizada o cerrada: NSURLSession en segundo
/// plano (iOS) y WorkManager (Android). Cada petición baja a un archivo [destination].
class BackgroundTransfers {
  BackgroundTransfers._();

  static const _channel = MethodChannel('com.marcoyam/media_tools');

  static Future<void> enqueue({
    required String id,
    required Uri url,
    required String destination,
    String method = 'GET',
    Map<String, String> headers = const {},
    List<int>? body,
  }) =>
      MediaTools._call('bgEnqueue', {
        'id': id,
        'url': url.toString(),
        'destination': destination,
        'method': method,
        'headers': headers,
        if (body != null) 'body': Uint8List.fromList(body),
      });

  /// Estado de las transferencias cuyo id empieza con [prefix].
  static Future<Map<String, TransferStatus>> status(String prefix) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('bgStatus', {'prefix': prefix});
      return {
        for (final e in (raw ?? const {}).entries)
          if (e.value is Map) '${e.key}': TransferStatus.fromMap(e.value! as Map<Object?, Object?>),
      };
    } on PlatformException catch (e) {
      throw MediaToolsException(e.message ?? e.code);
    } on MissingPluginException {
      throw const MediaToolsException('esta plataforma no lo admite');
    }
  }

  static Future<void> cancel(String prefix) => MediaTools._call('bgCancel', {'prefix': prefix});
}
