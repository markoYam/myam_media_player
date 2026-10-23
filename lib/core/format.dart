/// Utilidades de formato (mismas reglas que la versión Android en Kotlin).
library;

/// 950 → "950"; 12 300 → "12.3 K"; 1 250 000 → "1.2 M"; 3 100 000 000 → "3.1 MM".
/// Se trunca como YouTube (1.25 M → "1.2 M"), nunca se redondea hacia arriba.
String compactCount(int value) {
  if (value < 1000) return '$value';
  if (value < 1000000) return '${_trim(value / 1000)} K';
  if (value < 1000000000) return '${_trim(value / 1000000)} M';
  return '${_trim(value / 1000000000)} MM';
}

String _trim(double v) {
  if (v >= 100) return v.floor().toString();
  final truncated = (v * 10).floor() / 10;
  final s = truncated.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// 3725 s → "1:02:05"; 65 s → "1:05".
String formatDuration(Duration d) {
  final total = d.inSeconds.abs();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

const _units = ['B', 'KB', 'MB', 'GB', 'TB'];

/// 1536 → "1.5 KB".
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  var value = bytes.toDouble();
  var i = 0;
  while (value >= 1024 && i < _units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(1)} ${_units[i]}';
}

String formatSpeed(int bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';

/// "1.2 M vistas · hace 3 días".
String videoMeta({int? views, String? uploaded}) {
  final parts = <String>[
    if (views != null && views > 0) '${compactCount(views)} vistas',
    if (uploaded != null && uploaded.isNotEmpty) uploadedLabel(uploaded),
  ];
  return parts.join(' · ');
}

const _maxFileName = 120;

/// Nombre de archivo seguro en Android e iOS: sin separadores de ruta, caracteres reservados ni
/// de control; sin puntos al inicio o al final; longitud limitada.
String sanitizeFileName(String raw, {String fallback = 'video'}) {
  var name = raw
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  name = name.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
  if (name.isEmpty) name = fallback;
  if (name.length > _maxFileName) name = name.substring(0, _maxFileName).trim();
  return name;
}


/// Fecha de publicación legible en español:
/// - "2023-10-31 02:37:01.000Z" (fecha exacta) → "hace 2 años";
/// - "10mo ago", "3 weeks ago", "Streamed 2 days ago" (textos de YouTube en inglés) → "hace 10 meses"…;
/// - lo que no se reconoce se deja igual.
String uploadedLabel(String raw, {DateTime? now}) {
  final text = raw.trim();
  final date = DateTime.tryParse(text);
  if (date != null) return _ago((now ?? DateTime.now()).difference(date));

  final m = RegExp(r'^(?:streamed\s+)?(\d+)\s*([a-z]+)\s+ago$', caseSensitive: false).firstMatch(text);
  if (m == null) return text;
  final n = int.parse(m.group(1)!);
  final unit = m.group(2)!.toLowerCase();
  final es = switch (unit) {
    's' || 'sec' || 'second' || 'seconds' => _plural(n, 'segundo', 'segundos'),
    'm' || 'min' || 'minute' || 'minutes' => _plural(n, 'minuto', 'minutos'),
    'h' || 'hr' || 'hour' || 'hours' => _plural(n, 'hora', 'horas'),
    'd' || 'day' || 'days' => _plural(n, 'día', 'días'),
    'w' || 'wk' || 'week' || 'weeks' => _plural(n, 'semana', 'semanas'),
    'mo' || 'month' || 'months' => _plural(n, 'mes', 'meses'),
    'y' || 'yr' || 'year' || 'years' => _plural(n, 'año', 'años'),
    _ => null,
  };
  return es == null ? text : 'hace $es';
}

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

String _ago(Duration d) {
  if (d.isNegative || d.inMinutes < 1) return 'hace un momento';
  if (d.inHours < 1) return 'hace ${_plural(d.inMinutes, 'minuto', 'minutos')}';
  if (d.inDays < 1) return 'hace ${_plural(d.inHours, 'hora', 'horas')}';
  if (d.inDays < 7) return 'hace ${_plural(d.inDays, 'día', 'días')}';
  if (d.inDays < 30) return 'hace ${_plural(d.inDays ~/ 7, 'semana', 'semanas')}';
  if (d.inDays < 365) return 'hace ${_plural(d.inDays ~/ 30, 'mes', 'meses')}';
  return 'hace ${_plural(d.inDays ~/ 365, 'año', 'años')}';
}

/// Saludo de Inicio según la hora (como Spotify): "Buenos días", "Buenas tardes", "Buenas noches".
String greetingFor(DateTime t) => switch (t.hour) {
      >= 5 && < 12 => 'Buenos días',
      >= 12 && < 19 => 'Buenas tardes',
      _ => 'Buenas noches',
    };
