import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:molapp/src/export.dart';
import 'package:molapp/src/models.dart';

/// A 4×3 PNG, the smallest thing the encoders will accept as a captured viewport.
Uint8List _samplePng() => img.encodePng(img.Image(width: 4, height: 3));

void main() {
  group('desktop file delivery', () {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    const writeChannel = MethodChannel('molapp/files');
    late File destination;
    late FileSelectorPlatform originalSelector;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final directory = await Directory.systemTemp.createTemp('molapp-save-test-');
      destination = File('${directory.path}/molecule.molapp');
      await destination.writeAsString('previous session');
      originalSelector = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = _SaveFileSelector(destination.path);
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      FileSelectorPlatform.instance = originalSelector;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(writeChannel, null);
    });

    Future<String?> save() => deliverFile(
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      suggestedName: 'molecule.molapp',
      mimeType: 'application/json',
      shareTitle: 'MolApp state',
    );

    test('macOS delegates the selected path and bytes to native and preserves native errors', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      MethodCall? write;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(writeChannel, (call) async {
        write = call;
        return null;
      });

      expect(await save(), 'Saved molecule.molapp');
      expect(write?.method, 'writeAtomically');
      expect(write?.arguments, <String, Object>{
        'path': destination.path,
        'bytes': Uint8List.fromList(<int>[1, 2, 3]),
      });
      // This stub writes nothing: Dart must leave the selected file to the native writer.
      expect(await destination.readAsString(), 'previous session');

      binding.defaultBinaryMessenger.setMockMethodCallHandler(writeChannel, (_) async {
        throw PlatformException(code: 'write_failed', message: 'Disk full');
      });
      await expectLater(save(), throwsA(isA<PlatformException>()));
      expect(await destination.readAsString(), 'previous session');
    });

    test('an interrupted overwrite preserves the existing session', () async {
      await IOOverrides.runZoned(() async {
        await expectLater(save(), throwsA(isA<FileSystemException>()));
      }, createFile: (path) => _InterruptedWriteFile(path, destination));
      expect(await destination.readAsString(), 'previous session');
    });

    test('a completed overwrite replaces the session with all bytes', () async {
      expect(await save(), 'Saved molecule.molapp');
      expect(await destination.readAsBytes(), <int>[1, 2, 3]);
      expect(await destination.parent.list().length, 1);
    });
  });

  group('mobile file delivery', () {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    Map<Object?, Object?>? shared;
    String shareResult = '';

    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final directory = await Directory.systemTemp.createTemp('molapp-share-test-');
      binding.defaultBinaryMessenger.setMockMethodCallHandler(pathChannel, (_) async => directory.path);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(shareChannel, (call) async {
        shared = call.arguments as Map<Object?, Object?>;
        return shareResult;
      });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(pathChannel, null);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(shareChannel, null);
    });

    test('passes the nonempty iPad popover origin and the written file to native', () async {
      shareResult = 'com.apple.UIKit.activity.SaveToFiles';
      const origin = Rect.fromLTWH(10, 20, 200, 100);
      final status = await deliverFile(
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        suggestedName: 'molecule.molapp',
        mimeType: 'application/json',
        shareTitle: 'MolApp state',
        sharePositionOrigin: origin,
      );
      expect(shared!['originX'], origin.left);
      expect(shared!['originY'], origin.top);
      expect(shared!['originWidth'], origin.width);
      expect(shared!['originHeight'], origin.height);
      final path = (shared!['paths'] as List).single as String;
      expect(await File(path).readAsBytes(), <int>[1, 2, 3]);
      expect(status, 'Shared molecule.molapp');
    });

    test('dismissed share sheet does not claim the file was shared', () async {
      shareResult = '';
      expect(await deliverFile(
        bytes: Uint8List.fromList(<int>[1]),
        suggestedName: 'molecule.png',
        mimeType: 'image/png',
        shareTitle: 'MolApp PNG',
      ), isNull);
    });
  });

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

class _SaveFileSelector extends FileSelectorPlatform {
  _SaveFileSelector(this.path);
  final String path;

  @override
  Future<FileSaveLocation?> getSaveLocation({
    SaveDialogOptions? options,
    List<XTypeGroup>? acceptedTypeGroups,
  }) async => FileSaveLocation(path);
}

class _InterruptedWriteFile implements File {
  _InterruptedWriteFile(this.path, this.destination);

  @override
  final String path;
  final File destination;

  @override
  Directory get parent => destination.parent;

  @override
  Future<File> writeAsBytes(List<int> bytes, {FileMode mode = FileMode.write, bool flush = false}) async {
    if (path == destination.path) await destination.writeAsBytes(bytes.take(1).toList());
    throw FileSystemException('Interrupted write', path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
