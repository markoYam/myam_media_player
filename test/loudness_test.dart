import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/playback/loudness.dart';

void main() {
  group('playerVolumeFor', () {
    test('apagado o sin dato: volumen completo', () {
      expect(playerVolumeFor(6, LoudnessMode.off), 1);
      expect(playerVolumeFor(null, LoudnessMode.normal), 1);
      expect(playerVolumeFor(double.nan, LoudnessMode.normal), 1);
    });
    test('una canción 6 dB más fuerte baja a la mitad (≈0.5)', () {
      expect(playerVolumeFor(6, LoudnessMode.normal), closeTo(0.501, 0.001));
    });
    test('una canción baja no se sube con el volumen (máximo 1)', () {
      expect(playerVolumeFor(-5, LoudnessMode.normal), 1);
    });
    test('Suave lleva todo 6 dB más abajo', () {
      expect(playerVolumeFor(0, LoudnessMode.soft), closeTo(0.501, 0.001));
      expect(playerVolumeFor(6, LoudnessMode.soft), closeTo(0.251, 0.001));
    });
    test('el recorte tiene un límite (datos raros)', () {
      expect(playerVolumeFor(60, LoudnessMode.normal), closeTo(0.126, 0.001)); // −18 dB
    });
  });

  group('boostDbFor', () {
    test('solo con la opción activada y para canciones bajas', () {
      expect(boostDbFor(-5, LoudnessMode.normal, boostQuiet: false), 0);
      expect(boostDbFor(-5, LoudnessMode.normal, boostQuiet: true), 5);
      expect(boostDbFor(3, LoudnessMode.normal, boostQuiet: true), 0);
      expect(boostDbFor(-5, LoudnessMode.off, boostQuiet: true), 0);
    });
    test('el refuerzo tiene un máximo', () {
      expect(boostDbFor(-30, LoudnessMode.normal, boostQuiet: true), maxBoostDb);
    });
  });
}
