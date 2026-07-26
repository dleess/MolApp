import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

class StructureFileException implements Exception {
  const StructureFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

@immutable
class LocalStructureFile {
  const LocalStructureFile({required this.data, required this.format, required this.label});

  final String data;
  final String format;
  final String label;
}

/// Opening structure and `.molapp` state files. Accepted extensions and the Mol* data-format
/// strings live here rather than in the UI, exactly as they did in the Swift original.
abstract final class LocalStructureFileLoader {
  /// The payload is copied several times downstream (JSON encode → script → webview IPC), so a
  /// large file peaks at several times its size. Cap the input rather than moving the read
  /// off-thread; raise the cap if a real structure is ever rejected.
  static const int maxFileSize = 64 * 1024 * 1024;

  static const List<String> structureExtensions = <String>['pdb', 'cif', 'mmcif'];
  static const List<String> stateExtensions = <String>['molapp'];

  static String formatFor(String fileName) {
    switch (_extensionOf(fileName)) {
      case 'pdb':
        return 'pdb';
      case 'cif':
      case 'mmcif':
        return 'mmcif';
      default:
        final extension = _extensionOf(fileName);
        final suffix = extension.isEmpty ? 'selected file' : '.$extension';
        throw StructureFileException('Unsupported structure file type: $suffix.');
    }
  }

  /// Presents the platform file picker and reads the chosen structure. Returns null if the user
  /// cancelled. Throws [StructureFileException] for an unreadable, oversized or unsupported file.
  static Future<LocalStructureFile?> open() async {
    final file = await _pickFile(structureExtensions, 'Structures');
    if (file == null) return null;

    final label = file.name;
    final format = formatFor(label);
    final bytes = await _readCapped(file, label);
    // Lossy on purpose: Mol* decodes with a non-fatal TextDecoder, so rejecting a file for one
    // stray Latin-1 byte in a REMARK would be stricter than the viewer that consumes it.
    return LocalStructureFile(
      data: const Utf8Decoder(allowMalformed: true).convert(bytes),
      format: format,
      label: label,
    );
  }

  /// Presents the picker for a saved `.molapp` session and returns its JSON.
  static Future<String?> openStateJson() async {
    final file = await _pickFile(stateExtensions, 'MolApp state');
    if (file == null) return null;
    // Saved state embeds the structure text, so it is the same size class as a raw file and needs
    // the same cap.
    final bytes = await _readCapped(file, file.name);
    return const Utf8Decoder(allowMalformed: true).convert(bytes);
  }

  static Future<XFile?> _pickFile(List<String> extensions, String label) {
    // Android and iOS filter by MIME type / UTI, and .pdb / .cif / .molapp have neither. Filtering
    // by extension there would grey out every file, so open the picker unfiltered and validate the
    // extension after the fact — the same thing the native Android app did with its `*/*` picker.
    final filtersApply = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    return openFile(
      acceptedTypeGroups: filtersApply
          ? <XTypeGroup>[XTypeGroup(label: label, extensions: extensions)]
          : const <XTypeGroup>[],
    );
  }

  static Future<Uint8List> _readCapped(XFile file, String label) async {
    // Check the reported length before reading, so an oversized file is rejected instead of
    // OOM-crashing the read itself.
    final reported = await file.length();
    if (reported > maxFileSize) throw _tooLarge(reported);

    final bytes = await file.readAsBytes();
    // Some providers report a bogus length; re-check the bytes actually read.
    if (bytes.length > maxFileSize) throw _tooLarge(bytes.length);
    if (bytes.isEmpty) throw StructureFileException('Could not read $label.');
    return bytes;
  }

  static StructureFileException _tooLarge(int size) {
    final limit = maxFileSize ~/ (1024 * 1024);
    final actual = size ~/ (1024 * 1024);
    return StructureFileException('Structure file is too large: $actual MB (limit $limit MB).');
  }

  static String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }
}

/// True where a native "Save as…" dialog exists. Mobile has none, so exports go out through the
/// system share sheet instead.
bool get platformHasSaveDialog =>
    !kIsWeb &&
    (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
