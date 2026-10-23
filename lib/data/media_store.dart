import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'models.dart';
import 'youtube_service.dart' show AppException;

/// Copia una descarga a las carpetas públicas de Android (como la versión Kotlin):
/// audio → Música/Video Downloader, video → Películas/Video Downloader. Así aparece en otras apps
/// de música y en la galería. Nativo: MediaStoreSaver.java (plugin media_tools).
class MediaStoreSaver {
  MediaStoreSaver._();

  static const _channel = MethodChannel('com.marcoyam/media_store');

  /// Solo Android: en iOS los archivos ya se ven en la app Archivos.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static String mimeFor(OutputKind kind) => switch (kind) {
        OutputKind.mp3 => 'audio/mpeg',
        OutputKind.m4a => 'audio/mp4',
        OutputKind.mp4 => 'video/mp4',
      };

  /// Tipo según la extensión real del archivo (null si no se reconoce).
  static String? mimeForFile(String path) => switch (p.extension(path).toLowerCase()) {
        '.mp3' => 'audio/mpeg',
        '.m4a' => 'audio/mp4',
        '.aac' => 'audio/aac',
        '.mp4' => 'video/mp4',
        '.m4v' => 'video/x-m4v',
        '.mov' => 'video/quicktime',
        _ => null,
      };

  /// Guarda una copia de [file]. Lanza [AppException] con el motivo.
  static Future<void> save({required File file, required DownloadTask task}) async {
    try {
      await _channel.invokeMethod<String>('save', {
        'path': file.path,
        // Nombre y tipo del archivo real (los enlaces directos pueden ser .m4v, .mov o .aac).
        'displayName': p.basename(file.path),
        'title': task.title,
        'artist': task.author,
        'isAudio': task.kind.isAudio,
        'mimeType': mimeForFile(file.path) ?? mimeFor(task.kind),
      });
    } on PlatformException catch (e) {
      throw AppException(e.message ?? 'No se pudo guardar la copia.');
    } on MissingPluginException {
      throw const AppException('Esta versión de la app aún no puede guardar en Música/Películas.');
    }
  }
}
