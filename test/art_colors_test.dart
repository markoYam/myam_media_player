import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/core/art_colors.dart';

Uint8List pixels(List<Color> colors) => Uint8List.fromList([
      for (final c in colors) ...[(c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round(), 255],
    ]);

void main() {
  test('el color de la portada gana a negros y blancos', () {
    const red = Color(0xFFD02020);
    final c = dominantColorFromRgba(pixels([
      ...List.filled(10, const Color(0xFF000000)),
      ...List.filled(10, const Color(0xFFFFFFFF)),
      ...List.filled(5, red),
    ]))!;
    final hsl = HSLColor.fromColor(c);
    expect(hsl.hue, closeTo(0, 15), reason: 'debe salir rojizo, no gris');
    expect(hsl.saturation, greaterThan(0.4));
  });

  test('imagen vacía o transparente → null', () {
    expect(dominantColorFromRgba(Uint8List(0)), isNull);
    expect(dominantColorFromRgba(Uint8List.fromList([255, 0, 0, 0])), isNull);
  });

  test('el tono oscuro deja leer texto blanco y blanco al 80 % en cualquier color', () {
    for (var hue = 0.0; hue < 360; hue += 15) {
      for (final light in [0.3, 0.5, 0.8, 0.95]) {
        final tone = darkTone(HSLColor.fromAHSL(1, hue, 1, light).toColor());
        const white = Color(0xFFFFFFFF);
        final muted = Color.alphaBlend(white.withValues(alpha: 0.8), tone);
        expect(contrastRatio(white, tone), greaterThanOrEqualTo(4.5), reason: 'tono $hue/$light');
        expect(contrastRatio(muted, tone), greaterThanOrEqualTo(4.5), reason: 'secundario $hue/$light');
      }
    }
  });
}
