import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/core/format.dart';

void main() {
  group('compactCount', () {
    test('menos de mil queda igual', () => expect(compactCount(950), '950'));
    test('miles con un decimal', () => expect(compactCount(12300), '12.3 K'));
    test('trunca, no redondea (1.25 M → 1.2 M)', () => expect(compactCount(1250000), '1.2 M'));
    test('quita el .0', () => expect(compactCount(2000000), '2 M'));
    test('cientos sin decimal', () => expect(compactCount(456789), '456 K'));
    test('miles de millones', () => expect(compactCount(3100000000), '3.1 MM'));
  });

  group('formatDuration', () {
    test('minutos', () => expect(formatDuration(const Duration(seconds: 65)), '1:05'));
    test('horas', () => expect(formatDuration(const Duration(seconds: 3725)), '1:02:05'));
    test('cero', () => expect(formatDuration(Duration.zero), '0:00'));
  });

  group('formatBytes', () {
    test('bytes', () => expect(formatBytes(512), '512 B'));
    test('KB', () => expect(formatBytes(1536), '1.5 KB'));
    test('MB', () => expect(formatBytes(5 * 1024 * 1024), '5.0 MB'));
  });

  group('sanitizeFileName', () {
    test('quita separadores y reservados', () => expect(sanitizeFileName('AC/DC: Back <in> Black?'), 'AC DC Back in Black'));
    test('quita puntos al inicio y al final', () => expect(sanitizeFileName('...oculto...'), 'oculto'));
    test('vacío usa el respaldo', () => expect(sanitizeFileName('///'), 'video'));
    test('limita la longitud', () => expect(sanitizeFileName('a' * 300).length, 120));
    test('quita caracteres de control', () => expect(sanitizeFileName('hola\u0000\nmundo'), 'hola mundo'));
  });

  test('videoMeta une vistas y fecha', () {
    expect(videoMeta(views: 1250000, uploaded: 'hace 3 días'), '1.2 M vistas · hace 3 días');
    expect(videoMeta(), '');
  });

  group('uploadedLabel', () {
    final now = DateTime.utc(2026, 10, 21, 12);
    test('fecha exacta → hace N años', () => expect(uploadedLabel('2023-10-31 02:37:01.000Z', now: now), 'hace 2 años'));
    test('fecha exacta → meses', () => expect(uploadedLabel('2026-07-01T00:00:00Z', now: now), 'hace 3 meses'));
    test('fecha exacta → días', () => expect(uploadedLabel('2026-10-20T10:00:00Z', now: now), 'hace 1 día'));
    test('abreviado de YouTube', () => expect(uploadedLabel('10mo ago'), 'hace 10 meses'));
    test('en inglés completo', () => expect(uploadedLabel('3 weeks ago'), 'hace 3 semanas'));
    test('transmitido', () => expect(uploadedLabel('Streamed 1 year ago'), 'hace 1 año'));
    test('ya en español se deja igual', () => expect(uploadedLabel('hace 3 días'), 'hace 3 días'));
    test('videoMeta lo aplica', () => expect(videoMeta(views: 68, uploaded: '10mo ago'), '68 vistas · hace 10 meses'));
  });

  group('greetingFor', () {
    test('mañana', () => expect(greetingFor(DateTime(2026, 10, 22, 8)), 'Buenos días'));
    test('mediodía', () => expect(greetingFor(DateTime(2026, 10, 22, 12, 33)), 'Buenas tardes'));
    test('noche', () => expect(greetingFor(DateTime(2026, 10, 22, 21)), 'Buenas noches'));
    test('madrugada', () => expect(greetingFor(DateTime(2026, 10, 22, 3)), 'Buenas noches'));
  });
}
