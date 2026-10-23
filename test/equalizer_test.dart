import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/playback/equalizer.dart';

void main() {
  group('curveGain', () {
    final curve = {60.0: 6.0, 1000.0: 0.0, 10000.0: -6.0};
    test('en los puntos da su valor', () {
      expect(curveGain(curve, 60), 6);
      expect(curveGain(curve, 1000), 0);
      expect(curveGain(curve, 10000), -6);
    });
    test('fuera de los extremos mantiene el extremo', () {
      expect(curveGain(curve, 20), 6);
      expect(curveGain(curve, 18000), -6);
    });
    test('interpola en escala logarítmica', () {
      // 3162 Hz está a la mitad (en log) entre 1 kHz y 10 kHz → −3 dB.
      expect(curveGain(curve, 3162.28), closeTo(-3, 0.01));
    });
    test('curva vacía = plano', () => expect(curveGain(const {}, 500), 0));
  });

  group('bandsFor', () {
    test('las 6 bandas de iOS toman el preset tal cual', () {
      final bands = bandsFor(EqPreset.bass, EqualizerNotifier.iosFrequencies);
      expect(bands.map((b) => b.gain).toList(), [6, 4, 1, 0, 0, 0]);
    });
    test('las 5 bandas típicas de Android (60, 230, 910 Hz, 3.6, 14 kHz) siguen la misma curva', () {
      final bands = bandsFor(EqPreset.bass, const [60, 230, 910, 3600, 14000]);
      expect(bands.first.gain, 6);
      expect(bands[1].gain, inInclusiveRange(1, 4));
      expect(bands.last.gain, 0);
    });
    test('se recorta al rango del teléfono', () {
      final bands = bandsFor(EqPreset.rock, const [60, 14000], minDb: -3, maxDb: 3);
      expect(bands.every((b) => b.gain >= -3 && b.gain <= 3), isTrue);
    });
    test('Personalizado usa la curva guardada', () {
      final bands = bandsFor(EqPreset.custom, const [100, 1000], custom: {100.0: 2.0, 1000.0: -4.0});
      expect(bands.map((b) => b.gain).toList(), [2, -4]);
    });
    test('todos los presets están dentro de ±12 dB', () {
      for (final p in EqPreset.values) {
        for (final g in p.curve.values) {
          expect(g.abs(), lessThanOrEqualTo(12), reason: p.label);
        }
      }
    });
  });

  test('formatos', () {
    expect(formatFrequency(60), '60 Hz');
    expect(formatFrequency(1300), '1.3 kHz');
    expect(formatFrequency(1000), '1 kHz');
    expect(formatFrequency(10000), '10 kHz');
    expect(formatGain(3), '+3 dB');
    expect(formatGain(-2.5), '−2.5 dB');
    expect(formatGain(0.01), '0 dB');
  });

  test('la curva personalizada se guarda y se recupera', () {
    final curve = {60.0: 3.0, 1300.0: -1.5};
    expect(decodeCurve(encodeCurve(curve)), curve);
    expect(decodeCurve(null), isEmpty);
    expect(decodeCurve('basura,60:x,:3,-5:2'), isEmpty);
  });
}
