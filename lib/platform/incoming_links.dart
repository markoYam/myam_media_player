import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Esquema propio con el que la extensión "Compartir" de iOS abre la app:
/// `videodownloader://open?url=<enlace codificado>`.
const appLinkScheme = 'videodownloader';

/// Lo que llega de "Compartir" (o del esquema propio) convertido en el enlace a abrir.
///
/// - `videodownloader://open?url=…` → el `url` de adentro (o `text` si viene texto).
/// - Texto compartido con título y enlace ("Mira esto https://youtu.be/xyz") → el primer enlace.
/// - Texto sin enlace → el texto tal cual (puede ser un id o una búsqueda); vacío → null.
String? linkFromIncoming(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri != null && uri.scheme == appLinkScheme) {
    final inner = uri.queryParameters['url'] ?? uri.queryParameters['text'];
    return inner == null || inner.trim().isEmpty ? null : linkFromIncoming(inner);
  }
  final match = RegExp(r'https?://[^\s<>"]+', caseSensitive: false).firstMatch(text);
  if (match == null) return text;
  // Quita puntuación pegada al final ("…mira https://youtu.be/xyz).").
  return match.group(0)!.replaceFirst(RegExp(r'[).,;!?»”]+$'), '');
}

/// Enlaces que llegan desde fuera (canal "com.marcoyam/share": MTShare.m y ShareHandler.java).
///
/// El enlace con el que se abrió la app se guarda hasta que alguien escucha [links], así no se
/// pierde aunque la pantalla principal tarde en estar lista.
class IncomingLinks {
  IncomingLinks() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'link' && call.arguments is String) _add(call.arguments as String);
      return null;
    });
    unawaited(_initial());
  }

  static const _channel = MethodChannel('com.marcoyam/share');

  // Sin "broadcast": guarda lo que llegue antes de que alguien escuche.
  final _controller = StreamController<String>();

  Stream<String> get links => _controller.stream;

  void _add(String raw) {
    final link = linkFromIncoming(raw);
    if (link != null) _controller.add(link);
  }

  Future<void> _initial() async {
    try {
      final first = await _channel.invokeMethod<String>('getInitial');
      if (first != null) _add(first);
    } on MissingPluginException {
      // Pruebas o plataforma sin el plugin.
    } on PlatformException {
      // Nada que abrir.
    }
  }

  /// iOS: si la extensión "Compartir" no pudo abrir la app, deja el enlace copiado con una marca
  /// propia (caduca en 10 min). Revisar la marca no muestra el aviso de "pegar" de iOS.
  Future<bool> hasSharedClipboardLink() async {
    if (kIsWeb || !Platform.isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('hasClipboardLink') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Lee el enlace copiado por la extensión y borra la marca (aquí iOS sí puede preguntar si
  /// dejas pegar).
  Future<String?> takeSharedClipboardLink() async {
    try {
      final raw = await _channel.invokeMethod<String>('takeClipboardLink');
      return raw == null ? null : linkFromIncoming(raw);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  void dispose() => _controller.close();
}

final incomingLinksProvider = Provider<IncomingLinks>((ref) {
  final links = IncomingLinks();
  ref.onDispose(links.dispose);
  return links;
});
