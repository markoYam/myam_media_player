/// Detalles de cómo pedir los bytes de un flujo de googlevideo (separado para probarlo).
library;

import 'visionos_client.dart';

/// Tamaño de cada petición. YouTube limita la velocidad de las peticiones grandes sin `range`.
const streamChunkBytes = 10 * 1024 * 1024;

/// User-Agent que corresponde al cliente que generó la URL (parámetro `c`). Si no coincide,
/// YouTube suele responder 403: es lo que dejaba las descargas en "0 B".
String userAgentFor(Uri url) => switch (url.queryParameters['c'] ?? (url.path.contains('/c/VISIONOS/') ? 'VISIONOS' : null)) {
      'VISIONOS' => VisionOsClient.userAgent(),
      'ANDROID' || 'ANDROID_MUSIC' => 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
      'ANDROID_VR' =>
        'com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
      'IOS' => 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
      'TVHTML5' => 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version',
      _ => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15',
    };

/// URL de un bloque `[from, to]` (inclusive) con el parámetro `range` de googlevideo. Se agrega
/// al texto tal cual para no re-codificar la firma de la URL.
Uri chunkUrl(Uri url, int from, int to) {
  final base = url.toString();
  final sep = url.hasQuery ? '&' : '?';
  return Uri.parse('$base${sep}range=$from-$to');
}

/// Fin (inclusive) del bloque que empieza en [from] para un archivo de [total] bytes.
int chunkEnd(int from, int total, {int chunk = streamChunkBytes}) {
  final end = from + chunk - 1;
  return end < total - 1 ? end : total - 1;
}
