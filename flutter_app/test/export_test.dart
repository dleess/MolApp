import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:molapp/src/export.dart';
import 'package:molapp/src/models.dart';

/// A 4×3 PNG, the smallest thing the encoders will accept as a captured viewport.
Uint8List _samplePng() => img.encodePng(img.Image(width: 4, height: 3));

void main() {
  group('encodeExport', () {
    // Every branch was previously unexercised, and the PDF one threw a cast error at runtime.
    // Magic bytes are enough: they prove the container is the one the extension claims.
    test('produces the container each format promises', () async {
      final png = _samplePng();

      expect(await encodeExport(png, ExportFormat.png), png);
      expect((await encodeExport(png, ExportFormat.jpeg)).sublist(0, 2), <int>[0xFF, 0xD8]);
      expect(String.fromCharCodes((await encodeExport(png, ExportFormat.gif)).sublist(0, 3)), 'GIF');
      expect(
        String.fromCharCodes((await encodeExport(png, ExportFormat.svg)).sublist(0, 4)),
        '<svg',
      );
      expect(
        String.fromCharCodes((await encodeExport(png, ExportFormat.pdf)).sublist(0, 4)),
        '%PDF',
      );
    });

    test('rejects bytes that are not a decodable image', () async {
      expect(
        () => encodeExport(Uint8List.fromList(<int>[1, 2, 3]), ExportFormat.pdf),
        throwsA(isA<ExportException>()),
      );
    });
  });

  group('bytesFromDataUrl', () {
    test('decodes a base64 data URL and rejects a malformed one', () {
      expect(bytesFromDataUrl('data:image/png;base64,QUJD'), <int>[65, 66, 67]);
      expect(bytesFromDataUrl('no-comma-here'), isNull);
      expect(bytesFromDataUrl('data:image/png;base64,!!!'), isNull);
    });
  });
}
