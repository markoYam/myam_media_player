import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:media_tools/media_tools.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/diag_log.dart';

/// Ecualizador del reproductor de música.
///
/// - Android: el ecualizador del propio teléfono (AndroidEqualizer de just_audio). Las bandas
///   (normalmente 5) y el rango en dB los da el teléfono, y solo se conocen cuando ya sonó algo.
/// - iOS: filtros propios en el plugin media_tools (MTEqualizer.m), 6 bandas de −12 a +12 dB.
///
/// Los presets se definen como una curva (frecuencia → dB) y se evalúan en las bandas que haya,
/// así se oyen igual con 5 bandas de Android que con 6 de iOS.
enum EqPreset {
  flat('Plano', []),
  bass('Más graves', [(60.0, 6.0), (170.0, 4.0), (470.0, 1.0), (1300.0, 0.0), (3600.0, 0.0), (10000.0, 0.0)]),
  treble('Más agudos', [(60.0, 0.0), (170.0, 0.0), (470.0, 0.0), (1300.0, 1.0), (3600.0, 4.0), (10000.0, 6.0)]),
  vocal('Voz', [(60.0, -3.0), (170.0, -2.0), (470.0, 1.0), (1300.0, 3.0), (3600.0, 4.0), (10000.0, 1.0)]),
  regional('Regional', [(60.0, 4.0), (170.0, 3.0), (470.0, 0.0), (1300.0, 2.0), (3600.0, 3.0), (10000.0, 2.0)]),
  rock('Rock', [(60.0, 5.0), (170.0, 3.0), (470.0, -1.0), (1300.0, 1.0), (3600.0, 3.0), (10000.0, 5.0)]),
  pop('Pop', [(60.0, -1.0), (170.0, 2.0), (470.0, 4.0), (1300.0, 3.0), (3600.0, 1.0), (10000.0, -1.0)]),
  electronic('Electrónica', [(60.0, 5.0), (170.0, 4.0), (470.0, 0.0), (1300.0, -1.0), (3600.0, 2.0), (10000.0, 5.0)]),
  acoustic('Acústica', [(60.0, 3.0), (170.0, 2.0), (470.0, 1.0), (1300.0, 2.0), (3600.0, 2.0), (10000.0, 3.0)]),
  custom('Personalizado', []);

  const EqPreset(this.label, this.points);
  final String label;

  /// Puntos de la curva: (frecuencia en Hz, ganancia en dB). Es lista y no mapa porque Dart no
  /// admite claves double en mapas constantes.
  final List<(double, double)> points;

  /// La curva como mapa frecuencia → dB.
  Map<double, double> get curve => {for (final (hz, db) in points) hz: db};
}

/// Ganancia de una curva en [hz]: interpolación lineal en escala logarítmica de frecuencia (como
/// se oye); fuera de los extremos se mantiene el valor del extremo. Curva vacía = 0 dB.
double curveGain(Map<double, double> curve, double hz) {
  if (curve.isEmpty || hz <= 0) return 0;
  final points = curve.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  if (hz <= points.first.key) return points.first.value;
  if (hz >= points.last.key) return points.last.value;
  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i], b = points[i + 1];
    if (hz >= a.key && hz <= b.key) {
      final t = (math.log(hz) - math.log(a.key)) / (math.log(b.key) - math.log(a.key));
      return a.value + (b.value - a.value) * t;
    }
  }
  return points.last.value;
}

/// "60 Hz", "1.3 kHz", "10 kHz".
String formatFrequency(double hz) {
  if (hz < 1000) return '${hz.round()} Hz';
  final k = hz / 1000;
  final text = k >= 10 || k == k.roundToDouble() ? k.round().toString() : k.toStringAsFixed(1);
  return '$text kHz';
}

/// "+3 dB", "−2 dB", "0 dB" (con el signo menos tipográfico).
String formatGain(double db) {
  final r = (db * 10).round() / 10;
  if (r == 0) return '0 dB';
  final text = r == r.roundToDouble() ? r.abs().round().toString() : r.abs().toStringAsFixed(1);
  return '${r > 0 ? '+' : '−'}$text dB';
}

/// Curva personalizada guardada como "60:3,170:-1.5".
String encodeCurve(Map<double, double> curve) =>
    (curve.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${e.key}:${e.value}').join(',');

Map<double, double> decodeCurve(String? text) {
  final out = <double, double>{};
  for (final part in (text ?? '').split(',')) {
    final kv = part.split(':');
    if (kv.length != 2) continue;
    final f = double.tryParse(kv[0]), g = double.tryParse(kv[1]);
    if (f != null && g != null && f > 0 && g.isFinite) out[f] = g;
  }
  return out;
}

@immutable
class EqBand {
  const EqBand(this.frequency, this.gain);
  final double frequency;
  final double gain;
}

@immutable
class EqState {
  const EqState({
    this.enabled = false,
    this.preset = EqPreset.flat,
    this.bands = const [],
    this.minDb = -12,
    this.maxDb = 12,
    this.custom = const {},
  });

  final bool enabled;
  final EqPreset preset;

  /// Vacío en Android hasta que suena algo (el teléfono aún no dio sus bandas).
  final List<EqBand> bands;
  final double minDb;
  final double maxDb;

  /// Curva "Personalizado" (lo último que moviste a mano).
  final Map<double, double> custom;

  bool get ready => bands.isNotEmpty;

  EqState copyWith({bool? enabled, EqPreset? preset, List<EqBand>? bands, double? minDb, double? maxDb, Map<double, double>? custom}) =>
      EqState(
        enabled: enabled ?? this.enabled,
        preset: preset ?? this.preset,
        bands: bands ?? this.bands,
        minDb: minDb ?? this.minDb,
        maxDb: maxDb ?? this.maxDb,
        custom: custom ?? this.custom,
      );
}

/// Ganancias de [preset] en [frequencies], recortadas al rango del ecualizador.
List<EqBand> bandsFor(EqPreset preset, List<double> frequencies, {Map<double, double> custom = const {}, double minDb = -12, double maxDb = 12}) {
  final curve = preset == EqPreset.custom ? custom : preset.curve;
  return [for (final f in frequencies) EqBand(f, curveGain(curve, f).clamp(minDb, maxDb).toDouble())];
}

/// Ecualizador de Android: tiene que existir antes de crear el reproductor (va en su "pipeline").
final androidEqualizerProvider = Provider<AndroidEqualizer?>((ref) => !kIsWeb && Platform.isAndroid ? AndroidEqualizer() : null);

class EqualizerNotifier extends Notifier<EqState> {
  /// Bandas del ecualizador propio de iOS (~1.4 octavas entre una y otra).
  static const iosFrequencies = [60.0, 170.0, 470.0, 1300.0, 3600.0, 10000.0];

  static const _kEnabled = 'eq_enabled';
  static const _kPreset = 'eq_preset';
  static const _kCustom = 'eq_custom';

  AndroidEqualizer? get _android => ref.read(androidEqualizerProvider);

  @override
  EqState build() {
    unawaited(_load());
    return _android == null ? EqState(bands: bandsFor(EqPreset.flat, iosFrequencies)) : const EqState();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final preset = EqPreset.values.firstWhere((e) => e.name == p.getString(_kPreset), orElse: () => EqPreset.flat);
    final custom = decodeCurve(p.getString(_kCustom));
    final enabled = p.getBool(_kEnabled) ?? false;
    if (!ref.mounted) return;
    state = state.copyWith(enabled: enabled, preset: preset, custom: custom);
    final android = _android;
    if (android == null) {
      state = state.copyWith(bands: bandsFor(preset, iosFrequencies, custom: custom));
      await _apply();
      return;
    }
    // Android: las bandas llegan cuando el reproductor ya cargó algo.
    await android.setEnabled(enabled);
    unawaited(android.parameters.then((params) async {
      if (!ref.mounted) return;
      state = state.copyWith(
        minDb: params.minDecibels,
        maxDb: params.maxDecibels,
        bands: bandsFor(state.preset, [for (final b in params.bands) b.centerFrequency],
            custom: state.custom, minDb: params.minDecibels, maxDb: params.maxDecibels),
      );
      await _apply();
    }));
  }

  Future<void> setEnabled(bool on) async {
    state = state.copyWith(enabled: on);
    await _save();
    await _apply();
  }

  Future<void> selectPreset(EqPreset preset) async {
    state = state.copyWith(
      preset: preset,
      enabled: true,
      bands: bandsFor(preset, [for (final b in state.bands) b.frequency], custom: state.custom, minDb: state.minDb, maxDb: state.maxDb),
    );
    await _save();
    await _apply();
  }

  /// Mover una banda a mano pasa a "Personalizado".
  Future<void> setBandGain(int index, double gain) async {
    if (index < 0 || index >= state.bands.length) return;
    final bands = [
      for (var i = 0; i < state.bands.length; i++)
        i == index ? EqBand(state.bands[i].frequency, gain.clamp(state.minDb, state.maxDb).toDouble()) : state.bands[i],
    ];
    state = state.copyWith(
      bands: bands,
      preset: EqPreset.custom,
      enabled: true,
      custom: {for (final b in bands) b.frequency: b.gain},
    );
    await _apply(onlyBand: index);
  }

  /// Al soltar el control se guarda (no en cada movimiento).
  Future<void> commit() => _save();

  Future<void> reset() => selectPreset(EqPreset.flat);

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, state.enabled);
    await p.setString(_kPreset, state.preset.name);
    await p.setString(_kCustom, encodeCurve(state.custom));
  }

  Future<void> _apply({int? onlyBand}) async {
    final s = state;
    try {
      final android = _android;
      if (android != null) {
        await android.setEnabled(s.enabled);
        if (!s.ready) return;
        final params = await android.parameters;
        for (var i = 0; i < params.bands.length && i < s.bands.length; i++) {
          if (onlyBand == null || onlyBand == i) await params.bands[i].setGain(s.bands[i].gain);
        }
        return;
      }
      await MediaTools.setEqualizer(
        enabled: s.enabled,
        frequencies: [for (final b in s.bands) b.frequency],
        gains: [for (final b in s.bands) b.gain],
      );
    } catch (e) {
      DiagLog.write('ecualizador: no se pudo aplicar: $e');
    }
  }
}

final equalizerProvider = NotifierProvider<EqualizerNotifier, EqState>(EqualizerNotifier.new);
