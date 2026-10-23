import 'package:media_tools/media_tools.dart';
import 'package:youtube_explode_dart/js_challenge.dart';

import '../core/diag_log.dart';

/// Resuelve los retos JavaScript de YouTube (firma `sig` y parámetro `n`) con el motor del propio
/// teléfono, en vez de Deno (que no existe en Android ni iOS).
///
/// Usa los mismos módulos que yt-dlp (`yt-dlp/ejs`), que la librería descarga de GitHub y
/// verifica por hash. La primera vez que se usa con un reproductor nuevo de YouTube tarda unos
/// segundos (analiza el JavaScript del reproductor); después queda en caché.
class MobileEJSSolver extends BaseEJSSolver {
  MobileEJSSolver._(this._engine);
  final JsEngine _engine;

  static Future<MobileEJSSolver> init() async {
    final started = DateTime.now();
    final modules = await EJSBuilder.getJSModules();
    final engine = await JsEngine.create();
    try {
      await engine.evaluate(modules);
    } on MediaToolsException catch (e) {
      await engine.dispose();
      throw StateError('Los módulos del solucionador no cargaron: ${e.message}');
    }
    final type = await engine.evaluate('typeof jsc');
    if (type != 'function') {
      await engine.dispose();
      throw StateError('El solucionador no quedó listo (typeof jsc = $type)');
    }
    DiagLog.write('solucionador JS listo en ${DateTime.now().difference(started).inMilliseconds} ms');
    return MobileEJSSolver._(engine);
  }

  /// La librería arma la URL del reproductor como `'https://youtube.com' + src`; si YouTube ya
  /// da `src` completo queda `https://youtube.comhttps://…` ("No host specified in URI").
  /// Se normaliza a `https://www.youtube.com/s/player/…`.
  static String normalizePlayerUrl(String url) {
    final i = url.indexOf('/s/player/');
    if (i >= 0) return 'https://www.youtube.com${url.substring(i)}';
    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) return url;
    return url.startsWith('/') ? 'https://www.youtube.com$url' : url;
  }

  @override
  Future<Map<String, String?>> solveBulk(String playerUrl, Map<JSChallengeType, List<String>> requests) {
    final fixed = normalizePlayerUrl(playerUrl);
    if (fixed != playerUrl) DiagLog.write('URL del reproductor corregida: $playerUrl → $fixed');
    return super.solveBulk(fixed, requests);
  }

  @override
  Future<String> executeJavaScript(String jsCode) async {
    final started = DateTime.now();
    final wrapped = '(function(){ try { return $jsCode; } catch (e) { return "ERR:" + ((e && e.stack) || e); } })()';
    final result = await _engine.evaluate(wrapped);
    DiagLog.write('reto JS resuelto en ${DateTime.now().difference(started).inMilliseconds} ms');
    if (result == null) throw Exception('el solucionador no devolvió nada');
    if (result.startsWith('ERR:')) throw Exception('el solucionador falló: ${result.substring(4)}');
    return result;
  }

  @override
  void dispose() {
    _engine.dispose();
  }
}
