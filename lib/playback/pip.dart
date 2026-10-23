import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Imagen en imagen (canal "com.marcoyam/pip" del plugin media_tools: MTPip.m y PipHandler.java).
///
/// - iOS: el video de Flutter no sabe hacer imagen en imagen, así que se pasa al reproductor
///   nativo de iOS (AVPlayerViewController) con la misma URL y en el mismo segundo.
/// - Android: la actividad entra en modo imagen en imagen; la app avisa del cambio de modo para
///   que la pantalla muestre solo el video.
class Pip {
  Pip._();

  static const _channel = MethodChannel('com.marcoyam/pip');
  static final _modes = StreamController<bool>.broadcast();
  static bool _listening = false;
  static bool _inPip = false;

  /// iOS usa el reproductor nativo; Android encoge la app entera.
  static bool get usesNativePlayer => !kIsWeb && Platform.isIOS;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'modeChanged') {
        _inPip = call.arguments == true;
        _modes.add(_inPip);
      }
      return null;
    });
  }

  /// Si el teléfono admite imagen en imagen.
  static Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// iOS: abre el reproductor nativo y espera a que lo cierres. Devuelve dónde quedó el video
  /// (null si no se pudo abrir).
  static Future<Duration?> presentNative({
    required Uri url,
    required Map<String, String> headers,
    required Duration position,
    required String title,
  }) async {
    try {
      final ms = await _channel.invokeMethod<int>('present', {
        'url': url.toString(),
        'headers': headers,
        'positionMs': position.inMilliseconds,
        'title': title,
      });
      return ms == null ? null : Duration(milliseconds: ms);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Android: entra a imagen en imagen ahora mismo (16:9).
  static Future<bool> enter() async {
    _listen();
    try {
      return await _channel.invokeMethod<bool>('enter') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Android 12+: entrar solo a imagen en imagen al salir de la app (mientras suena un video).
  static Future<void> setAutoEnter(bool enabled) async {
    if (kIsWeb || !Platform.isAndroid) return;
    _listen();
    try {
      await _channel.invokeMethod<void>('setAutoEnter', {'enabled': enabled});
    } on PlatformException {
      // Versiones viejas de Android: solo con el botón.
    } on MissingPluginException {
      // Sin el plugin (pruebas): nada.
    }
  }

  /// Cambios de modo en Android (true = la app está en la ventanita).
  static Stream<bool> get modeChanges {
    _listen();
    return _modes.stream;
  }

  static bool get isInPip => _inPip;
}

/// Si la app está ahora en la ventanita de imagen en imagen (solo Android; en iOS siempre false).
final pipModeProvider = StreamProvider<bool>((ref) async* {
  yield Pip.isInPip;
  yield* Pip.modeChanges;
});
