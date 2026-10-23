import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/data/js_solver.dart';

void main() {
  const good = 'https://www.youtube.com/s/player/74edf1a3/player_ias.vflset/en_US/base.js';
  test('URL ya correcta', () => expect(MobileEJSSolver.normalizePlayerUrl(good), good));
  test('URL duplicada por la librería', () {
    expect(MobileEJSSolver.normalizePlayerUrl('https://youtube.comhttps://www.youtube.com/s/player/74edf1a3/player_ias.vflset/en_US/base.js'), good);
  });
  test('ruta relativa', () {
    expect(MobileEJSSolver.normalizePlayerUrl('https://youtube.com/s/player/74edf1a3/player_ias.vflset/en_US/base.js'), good);
    expect(MobileEJSSolver.normalizePlayerUrl('/s/player/74edf1a3/player_ias.vflset/en_US/base.js'), good);
  });
}
