import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/core/id3.dart';

void main() {
  test('cabecera ID3v2.3 con tamaño syncsafe', () {
    final tag = Id3v2.build(title: 'Canción', artist: 'Artista');
    expect(String.fromCharCodes(tag.sublist(0, 3)), 'ID3');
    expect(tag.sublist(3, 6), [3, 0, 0]);
    final size = (tag[6] << 21) | (tag[7] << 14) | (tag[8] << 7) | tag[9];
    expect(size, tag.length - 10);
    expect(tag.sublist(6, 10).every((b) => b < 0x80), isTrue);
  });

  test('frames de título y artista en UTF-16 con BOM', () {
    final tag = Id3v2.build(title: 'Ñandú', artist: null);
    expect(String.fromCharCodes(tag.sublist(10, 14)), 'TIT2');
    final frameSize = (tag[14] << 24) | (tag[15] << 16) | (tag[16] << 8) | tag[17];
    // 1 (codificación) + 2 (BOM) + 5 letras × 2 + 2 (fin)
    expect(frameSize, 1 + 2 + 10 + 2);
    expect(tag.sublist(20, 23), [1, 0xFF, 0xFE]);
    expect(tag.sublist(23, 25), [0xD1, 0x00]); // 'Ñ' en UTF-16LE
  });

  test('sin datos no hay etiqueta', () => expect(Id3v2.build(title: '  ', artist: null), isEmpty));
  test('syncsafe', () => expect(Id3v2.syncSafe(257), [0, 0, 2, 1]));
}
