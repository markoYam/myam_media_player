import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Registro de diagnóstico en `Documentos/diagnostico.log` (visible en la app Archivos).
/// Sirve para saber qué responde YouTube sin conectar el teléfono a la computadora.
/// Nunca guarda firmas ni tokens de las URL.
class DiagLog {
  DiagLog._();

  static const _maxBytes = 512 * 1024;
  static Future<void> _queue = Future.value();

  static void write(String message) {
    developer.log(message, name: 'Diagnóstico');
    _queue = _queue.then((_) => _append(message)).catchError((_) {});
  }

  static Future<void> _append(String message) async {
    final docs = await getApplicationDocumentsDirectory();
    final file = File(p.join(docs.path, 'diagnostico.log'));
    if (await file.exists() && await file.length() > _maxBytes) {
      await file.writeAsString(''); // se vacía para no crecer sin límite
    }
    await file.writeAsString('${DateTime.now().toIso8601String()}  $message\n', mode: FileMode.append, flush: true);
  }

  /// Resumen seguro de una URL de googlevideo: host, cliente, itag, tamaño. Sin firmas.
  static String describeUrl(Uri url) {
    final q = url.queryParameters;
    return '${url.host} c=${q['c']} itag=${q['itag']} clen=${q['clen']} mime=${q['mime']} '
        'pot=${q.containsKey('pot')} n=${q.containsKey('n')} sig=${q.containsKey('sig') || q.containsKey('signature')}';
  }
}
