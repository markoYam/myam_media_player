/// Color de la portada para teñir el reproductor (como Spotify / YouTube Music).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Color representativo de una imagen en RGBA crudo: promedio ponderado por saturación (los
/// grises, negros y blancos casi no cuentan, así sale el color "de la portada" y no un gris).
Color? dominantColorFromRgba(Uint8List rgba) {
  double r = 0, g = 0, b = 0, total = 0;
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final c = Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]);
    final hsl = HSLColor.fromColor(c);
    // Peso: saturación, sin extremos de luz (negros y blancos no definen el color).
    final light = hsl.lightness;
    final weight = 0.05 + hsl.saturation * (light < 0.08 || light > 0.92 ? 0.1 : 1.0);
    r += rgba[i] * weight;
    g += rgba[i + 1] * weight;
    b += rgba[i + 2] * weight;
    total += weight;
  }
  if (total == 0) return null;
  return Color.fromARGB(255, (r / total).round(), (g / total).round(), (b / total).round());
}

/// Lleva el color a un tono oscuro sobre el que el texto blanco se lee bien (contraste ≥ 4.5:1).
Color darkTone(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness(hsl.lightness.clamp(0.12, 0.22)).withSaturation(hsl.saturation.clamp(0.0, 0.65)).toColor();
}

/// Contraste WCAG entre dos colores (1 a 21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Future<Color?> _colorOf(ImageProvider provider) async {
  final stream = ResizeImage(provider, width: 24, height: 24).resolve(ImageConfiguration.empty);
  final completer = Completer<ui.Image>();
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info.image.clone());
      info.image.dispose();
      stream.removeListener(listener);
    },
    onError: (e, s) {
      if (!completer.isCompleted) completer.completeError(e, s);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  final image = await completer.future.timeout(const Duration(seconds: 10));
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data == null ? null : dominantColorFromRgba(data.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

/// Tono oscuro de la portada [uri] (file:// o https://); null si no se pudo leer. Se guarda en
/// memoria: cada portada se analiza una sola vez.
final artToneProvider = FutureProvider.family<Color?, String>((ref, uri) async {
  try {
    final u = Uri.parse(uri);
    final ImageProvider provider = u.isScheme('file') ? FileImage(File(u.toFilePath())) : CachedNetworkImageProvider(uri);
    final c = await _colorOf(provider);
    return c == null ? null : darkTone(c);
  } catch (_) {
    return null;
  }
});
