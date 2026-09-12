import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:molapp/src/models.dart';
import 'package:molapp/src/molstar_bridge.dart';

/// Captures the scripts the bridge would have evaluated, so command encoding and the pending-script
/// queue can be asserted without a webview.
class FakeJsRunner implements MolStarJsRunner {
  final List<String> evaluated = <String>[];
  Object? asyncResult;
  Object? asyncError;
  Object? evaluateError;

  @override
  Future<void> evaluate(String source) async {
    if (evaluateError != null) throw StateError(evaluateError.toString());
    evaluated.add(source);
  }

  @override
  Future<Object?> callAsync(String source) async {
    if (asyncError != null) throw StateError(asyncError.toString());
    return asyncResult;
  }

  /// The `payload` of the nth `handleNativeCommand(...)` script, decoded.
  Map<String, dynamic> envelopeAt(int index) {
    final script = evaluated[index];
    final start = script.indexOf('(') + 1;
    final end = script.lastIndexOf('); void 0;');
    return jsonDecode(script.substring(start, end)) as Map<String, dynamic>;
  }
}

MolStarBridge readyBridge(FakeJsRunner runner) {
  final bridge = MolStarBridge()..attach(runner);
  bridge.receiveMessage(<String, dynamic>{'event': 'viewerReady'});
  return bridge;
}

void main() {
  group('objectsReplaced', () {
    test('survives a non-string representation from a hand-edited state file', () {
      // .molapp files are user-editable and viewer.html echoes `representation` back unvalidated,
      // so the message boundary has to type-check it the way it already does name and type.
      final bridge = readyBridge(FakeJsRunner());
      bridge.receiveMessage(<String, dynamic>{
        'event': 'objectsReplaced',
        'objects': <dynamic>[
          <String, dynamic>{
            'name': '1CRN',
            'type': 'structure',
            'representation': 5,
            'colorHex': 7,
          },
        ],
      });
      expect(bridge.objects.single.representation, ObjectRepresentation.ribbon);
      expect(bridge.objects.single.colorHex, isNull);
    });
  });

  group('MolStarCommandResult', () {
    test('decodes a known command', () {
      final result = MolStarCommandResult.fromJson(
        jsonDecode('{"id":"1","command":"loadPdbId","success":true,"label":"1ABC"}')
            as Map<String, dynamic>,
      );
      expect(result.id, '1');
      expect(result.command, MolStarCommand.loadPdbId);
      expect(result.success, isTrue);
      expect(result.error, isNull);
      expect(result.label, '1ABC');
    });

    test('keeps the failure message for an unknown command', () {
      final result = MolStarCommandResult.fromJson(
        jsonDecode('{"id":"2","command":"unknownCommand","success":false,'
            '"error":"Unknown MolApp command: unknownCommand"}') as Map<String, dynamic>,
      );
      expect(result.id, '2');
      expect(result.command, isNull);
      expect(result.success, isFalse);
      expect(result.error, 'Unknown MolApp command: unknownCommand');
      expect(result.label, isNull);
    });
  });

  group('viewer lifecycle', () {
    test('tracks ready and error events', () {
      final bridge = MolStarBridge();
      expect(bridge.isViewerReady, isFalse);

      bridge.receiveMessage(<String, dynamic>{'event': 'viewerReady'});
      expect(bridge.isViewerReady, isTrue);

      bridge.receiveMessage(
        <String, dynamic>{'event': 'viewerError', 'message': 'Recoverable', 'fatal': false},
      );
      expect(bridge.isViewerReady, isTrue);
      expect(bridge.lastErrorMessage, 'Recoverable');

      bridge.receiveMessage(
        <String, dynamic>{'event': 'viewerError', 'message': 'Fatal', 'fatal': true},
      );
      expect(bridge.isViewerReady, isFalse);
      expect(bridge.lastErrorMessage, 'Fatal');
    });

    test('a new page clears state from the previous scene', () {
      final bridge = readyBridge(FakeJsRunner());
      bridge.addObject(const MolAppObject(name: '1CRN', type: MolAppObjectType.structure));
      bridge.receiveMessage(<String, dynamic>{
        'event': 'selectionChanged',
        'selection': <String, dynamic>{'type': 'atom', 'label': 'CA'},
      });
      bridge.receiveMessage(<String, dynamic>{
        'event': 'featureVisibility', 'feature': 'water', 'isVisible': false,
      });
      bridge.updateHoverPoint(const Offset(2, 3));
      bridge.receiveMessage(<String, dynamic>{'event': 'pencilHover', 'label': 'CA'});
      bridge.receiveMessage(<String, dynamic>{
        'event': 'measurePending', 'count': 1, 'target': 3, 'labels': <String>['CA'],
      });

      bridge.attach(FakeJsRunner());

      expect(bridge.isViewerReady, isFalse);
      expect(bridge.objects, isEmpty);
      expect(bridge.currentSelection, isNull);
      expect(bridge.featureVisibility, isEmpty);
      expect(bridge.hoverPoint, isNull);
      expect(bridge.hoverLabel, isNull);
      expect(bridge.measurePendingCount, 0);
      expect(bridge.measurePendingLabels, isEmpty);
    });

    test('holds commands until the viewer is ready, then flushes in order', () {
      final runner = FakeJsRunner();
      final bridge = MolStarBridge()..attach(runner);

      bridge.loadPdbId('1CRN');
      bridge.focusSelection();
      expect(runner.evaluated, isEmpty);

      bridge.receiveMessage(<String, dynamic>{'event': 'viewerReady'});
      expect(runner.evaluated, hasLength(2));
      expect(runner.envelopeAt(0)['command'], 'loadPdbId');
      expect(runner.envelopeAt(1)['command'], 'focusSelection');
    });

    test('drops queued commands after a fatal error instead of growing forever', () {
      final runner = FakeJsRunner();
      final bridge = MolStarBridge()..attach(runner);

      bridge.loadPdbId('1CRN');
      bridge.receiveMessage(
        <String, dynamic>{'event': 'viewerError', 'message': 'Fatal', 'fatal': true},
      );
      bridge.loadLocalStructure(data: 'ATOM', format: 'pdb', label: 'x.pdb');

      bridge.receiveMessage(<String, dynamic>{'event': 'viewerReady'});
      expect(runner.evaluated, isEmpty);
    });
  });

  group('command encoding', () {
    test('wraps every command in an id/command/payload envelope', () {
      final runner = FakeJsRunner();
      final bridge = readyBridge(runner);

      bridge.setRepresentation('surface', targets: <String>['1CRN']);
      final envelope = runner.envelopeAt(0);

      expect(envelope['command'], 'setRepresentation');
      expect(envelope['id'], isA<String>());
      expect(envelope['payload'], <String, dynamic>{
        'representation': 'surface',
        'targets': <String>['1CRN'],
      });
      expect(runner.evaluated.first, startsWith('window.molapp.handleNativeCommand('));
    });

    test('gives each command a distinct id', () {
      final runner = FakeJsRunner();
      final bridge = readyBridge(runner);
      bridge.undo();
      bridge.redo();
      expect(runner.envelopeAt(0)['id'], isNot(runner.envelopeAt(1)['id']));
    });

    test('sends a null colorHex explicitly so JS resets to chain colouring', () {
      final runner = FakeJsRunner();
      final bridge = readyBridge(runner);
      bridge.setObjectColor(name: '1CRN', colorHex: null);
      final payload = runner.envelopeAt(0)['payload'] as Map<String, dynamic>;
      expect(payload.containsKey('colorHex'), isTrue);
      expect(payload['colorHex'], isNull);
    });

    test('omits the measure kind when leaving measure mode', () {
      final runner = FakeJsRunner();
      final bridge = readyBridge(runner);
      bridge.setMeasureMode(false);
      final payload = runner.envelopeAt(0)['payload'] as Map<String, dynamic>;
      expect(payload, <String, dynamic>{'enabled': false});
    });

    test('encodes an expression selection with its AST', () {
      final runner = FakeJsRunner();
      final bridge = readyBridge(runner);
      bridge.setSelection(const MoleculeSelection(
        type: 'expression',
        label: 'sele: chain A',
        ast: SelectionAST(kind: SelectionASTKind.chain, value: 'A'),
      ));
      expect(runner.envelopeAt(0)['payload'], <String, dynamic>{
        'type': 'expression',
        'label': 'sele: chain A',
        'ast': <String, dynamic>{'kind': 'chain', 'value': 'A'},
      });
    });

    test('escapes structure text so a quote cannot break out of the script', () {
      final runner = FakeJsRunner();
      final bridge = readyBridge(runner);
      bridge.loadLocalStructure(data: 'REMARK "quoted"\nATOM', format: 'pdb', label: 'a"b.pdb');
      final payload = runner.envelopeAt(0)['payload'] as Map<String, dynamic>;
      expect(payload['data'], 'REMARK "quoted"\nATOM');
      expect(payload['label'], 'a"b.pdb');
    });
  });

  group('feature visibility', () {
    test('accumulates single toggles and is replaced wholesale by objectsReplaced', () {
      final bridge = MolStarBridge();
      bridge.receiveMessage(
        <String, dynamic>{'event': 'featureVisibility', 'feature': 'water', 'isVisible': false},
      );
      bridge.receiveMessage(
        <String, dynamic>{'event': 'featureVisibility', 'feature': 'ligand', 'isVisible': false},
      );
      expect(bridge.featureVisibility, <String, bool>{'water': false, 'ligand': false});

      bridge.receiveMessage(<String, dynamic>{
        'event': 'objectsReplaced',
        'objects': <dynamic>[],
        'visibility': <String, dynamic>{},
      });
      expect(bridge.featureVisibility, isEmpty);
    });
  });

  group('selection events', () {
    test('receives a selectionChanged event', () {
      final bridge = MolStarBridge();
      bridge.receiveMessage(<String, dynamic>{
        'event': 'selectionChanged',
        'selection': <String, dynamic>{
          'type': 'atom',
          'label': 'GLY A 1 CA',
          'model': 1,
          'chain': 'A',
          'residueNumber': 1,
          'atomName': 'CA',
        },
      });

      final selection = bridge.currentSelection!;
      expect(selection.type, 'atom');
      expect(selection.label, 'GLY A 1 CA');
      expect(selection.model, 1);
      expect(selection.chain, 'A');
      expect(selection.residueNumber, 1);
      expect(selection.atomName, 'CA');
    });

    test('clears the selection when JS reports a null selection', () {
      final bridge = MolStarBridge();
      bridge.receiveMessage(<String, dynamic>{
        'event': 'selectionChanged',
        'selection': <String, dynamic>{'type': 'atom', 'label': 'GLY A 1 CA'},
      });
      bridge.receiveMessage(<String, dynamic>{'event': 'selectionChanged', 'selection': null});
      expect(bridge.currentSelection, isNull);
    });
  });

  group('objects', () {
    test('appends a new object', () {
      final bridge = MolStarBridge()
        ..addObject(const MolAppObject(name: '1crn', type: MolAppObjectType.structure));
      expect(bridge.objects, hasLength(1));
      expect(bridge.objects[0].name, '1crn');
    });

    test('updates an existing object rather than duplicating it', () {
      final bridge = MolStarBridge()
        ..addObject(const MolAppObject(name: '1crn', type: MolAppObjectType.structure))
        ..addObject(const MolAppObject(
          name: '1crn',
          type: MolAppObjectType.structure,
          representation: ObjectRepresentation.surface,
        ));
      expect(bridge.objects, hasLength(1));
      expect(bridge.objects[0].representation, ObjectRepresentation.surface);
    });

    test('keeps the selection type', () {
      final bridge = MolStarBridge()
        ..addObject(const MolAppObject(name: 'mysel', type: MolAppObjectType.selection));
      expect(bridge.objects[0].type, MolAppObjectType.selection);
    });

    test('objectsReplaced rebuilds the panel with defaults per object type', () {
      final bridge = MolStarBridge();
      bridge.receiveMessage(<String, dynamic>{
        'event': 'objectsReplaced',
        'objects': <dynamic>[
          <String, dynamic>{'name': '1CRN', 'type': 'structure'},
          <String, dynamic>{
            'name': 'NAP',
            'type': 'selection',
            'isVisible': false,
            'colorHex': '#D55E00',
          },
        ],
        'visibility': <String, dynamic>{'water': false},
      });

      expect(bridge.objects, hasLength(2));
      expect(bridge.objects[0].representation, ObjectRepresentation.ribbon);
      expect(bridge.objects[1].representation, ObjectRepresentation.ballAndStick);
      expect(bridge.objects[1].isVisible, isFalse);
      expect(bridge.objects[1].colorHex, '#D55E00');
      expect(bridge.featureVisibility, <String, bool>{'water': false});
    });

    test('objectsVisibility mirrors the master ligand toggle onto the rows', () {
      final bridge = MolStarBridge()
        ..addObject(const MolAppObject(name: 'NAP', type: MolAppObjectType.selection));
      bridge.receiveMessage(<String, dynamic>{
        'event': 'objectsVisibility',
        'items': <dynamic>[
          <String, dynamic>{'name': 'NAP', 'isVisible': false},
        ],
      });
      expect(bridge.objects[0].isVisible, isFalse);
    });

    test('visibleStructureNames scopes global actions to shown structures', () {
      final bridge = MolStarBridge();
      bridge.receiveMessage(<String, dynamic>{
        'event': 'objectsReplaced',
        'objects': <dynamic>[
          <String, dynamic>{'name': '1CRN', 'type': 'structure', 'isVisible': true},
          <String, dynamic>{'name': '4HHB', 'type': 'structure', 'isVisible': false},
          <String, dynamic>{'name': 'sele', 'type': 'selection', 'isVisible': true},
        ],
      });
      expect(bridge.visibleStructureNames, <String>['1CRN']);
    });
  });

  test('gesture evaluation reports failures instead of leaking unhandled futures', () async {
    final runner = FakeJsRunner()..evaluateError = 'page unavailable';
    final bridge = readyBridge(runner);
    for (final send in <Future<void> Function()>[
      () => bridge.sendHover(1, 2),
      bridge.sendHoverEnd,
      () => bridge.sendPinch(1.1, 1, 2),
    ]) {
      bridge.clearError();
      await send();
      expect(bridge.lastErrorMessage, contains('page unavailable'));
    }
  });

  group('async calls', () {
    test('state and image reads preserve strings and null and report invalid results', () async {
      final runner = FakeJsRunner();
      final bridge = readyBridge(runner);
      for (final read in [bridge.serializeState, bridge.captureImageDataURL]) {
        for (final result in <String?>['captured value', null]) {
          runner.asyncResult = result;
          expect(await read(), result);
          expect(bridge.lastErrorMessage, isNull);
        }
        runner.asyncResult = 42;
        expect(await read(), isNull);
        expect(bridge.lastErrorMessage, isNotNull);
        bridge.clearError();
      }
    });

    test('ignores async results and errors from a detached or replaced page', () async {
      for (final replace in <bool>[false, true]) {
        for (final fail in <bool>[false, true]) {
          final pending = Completer<Object?>();
          final bridge = MolStarBridge()..attach(_DeferredJsRunner(pending));
          final read = bridge.serializeState();
          if (replace) {
            bridge.attach(FakeJsRunner());
          } else {
            bridge.detach();
          }
          if (fail) {
            pending.completeError(StateError('old page failed'));
          } else {
            pending.complete('old scene');
          }
          expect(await read, isNull);
          expect(bridge.lastErrorMessage, isNull);
        }
      }
    });

    test('does not notify a disposed bridge when async work fails', () async {
      final pending = Completer<Object?>();
      final bridge = MolStarBridge()..attach(_DeferredJsRunner(pending));
      final read = bridge.captureImageDataURL();
      bridge.dispose();
      pending.completeError(StateError('page closed'));
      expect(await read, isNull);
    });

    test('serializeState returns null without a runner', () async {
      expect(await MolStarBridge().serializeState(), isNull);
    });

    test('captureImageDataURL surfaces a JS error instead of throwing', () async {
      final runner = FakeJsRunner()..asyncError = 'canvas is gone';
      final bridge = readyBridge(runner);
      expect(await bridge.captureImageDataURL(), isNull);
      expect(bridge.lastErrorMessage, contains('canvas is gone'));
    });
  });
}

class _DeferredJsRunner implements MolStarJsRunner {
  _DeferredJsRunner(this.result);

  final Completer<Object?> result;

  @override
  Future<void> evaluate(String source) async {}

  @override
  Future<Object?> callAsync(String source) => result.future;
}
