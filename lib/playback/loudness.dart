/// Volumen parejo entre canciones, como lo hace YouTube.
///
/// YouTube da por canción un `loudnessDb`: cuántos dB suena por encima (+) o por debajo (−) de su
/// volumen de referencia. Para que todas suenen parecido se aplica `referencia − loudnessDb`:
/// - las canciones fuertes se BAJAN con el volumen del reproductor (funciona en Android e iOS);
/// - las bajas solo se SUBEN si se activa "Subir las canciones bajas" (Android, con
///   LoudnessEnhancer; el volumen del reproductor no puede pasar de 1).
library;

import 'dart:math' as math;

enum LoudnessMode {
  off('Apagado', 'Cada canción suena con su volumen original.', 0.0),
  normal('Normal', 'Baja las canciones fuertes al nivel de YouTube.', 0.0),
  soft('Suave', 'Todo un poco más bajo y parejo; ideal para escuchar de noche.', -6.0);

  const LoudnessMode(this.label, this.description, this.referenceDb);
  final String label;
  final String description;

  /// Nivel al que se lleva cada canción, relativo a la referencia de YouTube.
  final double referenceDb;
}

/// Máximo que se baja o se sube una canción (evita extremos por datos raros).
const maxCutDb = 18.0;
const maxBoostDb = 8.0;

/// Ganancia en dB para una canción con [loudnessDb] (null = desconocido → 0).
double loudnessGainDb(double? loudnessDb, LoudnessMode mode) {
  if (mode == LoudnessMode.off || loudnessDb == null || !loudnessDb.isFinite) return 0;
  return (mode.referenceDb - loudnessDb).clamp(-maxCutDb, maxBoostDb).toDouble();
}

/// Volumen del reproductor (0–1): solo baja, nunca sube.
double playerVolumeFor(double? loudnessDb, LoudnessMode mode) {
  final gain = loudnessGainDb(loudnessDb, mode);
  return math.pow(10, math.min(0, gain) / 20).toDouble();
}

/// Refuerzo en dB para LoudnessEnhancer de Android (0 si está apagado o la canción no es baja).
double boostDbFor(double? loudnessDb, LoudnessMode mode, {required bool boostQuiet}) {
  if (!boostQuiet) return 0;
  return math.max(0, loudnessGainDb(loudnessDb, mode)).toDouble();
}
