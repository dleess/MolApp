import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'models.dart';
import 'structure_file.dart';

class ExportException implements Exception {
  const ExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Mol* hands us a `data:image/png;base64,...` URI from the WebGL viewport; decode it to bytes.
Uint8List? bytesFromDataUrl(String dataUrl) {
  final comma = dataUrl.indexOf(',');
  if (comma < 0) return null;
  try {
    return base64Decode(dataUrl.substring(comma + 1));
  } on FormatException {
    return null;
  }
}

/// The PNG from JS is the source of truth; re-encode it into the requested container.
Future<Uint8List> encodeExport(Uint8List png, ExportFormat format) async {
  switch (format) {
    case ExportFormat.png:
      return png;
    case ExportFormat.jpeg:
      return img.encodeJpg(_decode(png), quality: 95);
    case ExportFormat.gif:
      // Single frame: the viewport is a still, matching the native apps' GIF export.
      return img.encodeGif(_decode(png));
    case ExportFormat.svg:
      return _svgWrapping(png);
    case ExportFormat.pdf:
      return _pdfWrapping(png);
  }
}

img.Image _decode(Uint8List png) {
  final decoded = img.decodePng(png);
  if (decoded == null) throw const ExportException('Could not decode the captured image.');
  return decoded;
}

/// A WebGL viewport is raster, so a true vector SVG is not possible — wrap the PNG in an SVG
/// `<image>` so the .svg opens anywhere an SVG is expected. Known ceiling: raster inside vector.
Uint8List _svgWrapping(Uint8List png) {
  final decoded = _decode(png);
  final width = decoded.width;
  final height = decoded.height;
  final base64 = base64Encode(png);
  final svg = '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
      'width="$width" height="$height" viewBox="0 0 $width $height">\n'
      '<image width="$width" height="$height" xlink:href="data:image/png;base64,$base64"/>\n'
      '</svg>\n';
  return utf8.encode(svg);
}

Future<Uint8List> _pdfWrapping(Uint8List png) {
  final decoded = _decode(png);
  final document = pw.Document();
  final image = pw.MemoryImage(png);
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(decoded.width.toDouble(), decoded.height.toDouble()),
      build: (context) => pw.FullPage(ignoreMargins: true, child: pw.Image(image)),
    ),
  );
  return document.save();
}

/// Hands finished bytes to the user: a Save-as dialog on desktop, the share sheet on mobile.
/// Returns a short status line, or null if the user cancelled.
Future<String?> deliverFile({
  required Uint8List bytes,
  required String suggestedName,
  required String mimeType,
  required String shareTitle,
  Rect? sharePositionOrigin,
}) async {
  if (platformHasSaveDialog) {
    final location = await getSaveLocation(suggestedName: suggestedName);
    if (location == null) return null;
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      // NSSavePanel grants the selected file, not its parent directory for Dart staging.
      await const MethodChannel('molapp/files').invokeMethod<void>(
        'writeAtomically',
        <String, Object>{'path': location.path, 'bytes': bytes},
      );
    } else {
      final staging = await File(location.path).parent.createTemp('.molapp-save-');
      final file = File('${staging.path}/${_basename(location.path)}');
      await file.writeAsBytes(bytes, flush: true);
      await file.rename(location.path);
      await staging.delete(); // Empty after a successful rename; retain staged data on failure.
    }
    return 'Saved ${_basename(location.path)}';
  }

  final directory = await getTemporaryDirectory();
  final path = '${directory.path}/$suggestedName';
  await File(path).writeAsBytes(bytes, flush: true);
  final result = await SharePlus.instance.share(
    ShareParams(
      files: <XFile>[XFile(path, mimeType: mimeType)],
      title: shareTitle,
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
  return result.status == ShareResultStatus.dismissed ? null : 'Shared $suggestedName';
}

/// Sends the captured viewport to a printer through the platform print dialog.
Future<void> printImage(Uint8List png) async {
  await Printing.layoutPdf(
    name: 'MolApp',
    onLayout: (format) async {
      final document = pw.Document();
      final image = pw.MemoryImage(png);
      document.addPage(
        pw.Page(
          pageFormat: format,
          build: (context) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
      return document.save();
    },
  );
}

String _basename(String path) {
  final index = path.lastIndexOf(Platform.pathSeparator);
  return index < 0 ? path : path.substring(index + 1);
}
