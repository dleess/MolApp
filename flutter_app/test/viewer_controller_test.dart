import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:molapp/src/models.dart';
import 'package:molapp/src/molstar_bridge.dart';
import 'package:molapp/src/viewer_controller.dart';

import 'molstar_bridge_test.dart' show FakeJsRunner;

class _Harness {
  _Harness() {
    runner = FakeJsRunner();
    bridge = MolStarBridge()..attach(runner);
    bridge.receiveMessage(<String, dynamic>{'event': 'viewerReady'});
    controller = ViewerController(bridge);
  }

  late final FakeJsRunner runner;
  late final MolStarBridge bridge;
  late final ViewerController controller;

  void run(String command) {
    controller
      ..setCommandText(command)
      ..executeCommand();
  }

  Map<String, dynamic> get lastEnvelope => runner.envelopeAt(runner.evaluated.length - 1);
  String? get lastCommand => lastEnvelope['command'] as String?;
  Map<String, dynamic> get lastPayload => lastEnvelope['payload'] as Map<String, dynamic>;

  void loadStructures(List<String> visible, {List<String> hidden = const <String>[]}) {
    bridge.receiveMessage(<String, dynamic>{
      'event': 'objectsReplaced',
      'objects': <dynamic>[
        for (final name in visible)
          <String, dynamic>{'name': name, 'type': 'structure', 'isVisible': true},
        for (final name in hidden)
          <String, dynamic>{'name': name, 'type': 'structure', 'isVisible': false},
      ],
    });
  }
}

void main() {
  group('command bar', () {
    test('load sends a normalized PDB id', () {
      final h = _Harness()..run('load 1crn');
      expect(h.lastCommand, 'loadPdbId');
      expect(h.lastPayload['pdbId'], '1CRN');
      expect(h.controller.statusMessage, 'Loading 1CRN');
    });

    test('load without an argument reports usage', () {
      final h = _Harness()..run('load');
      expect(h.controller.errorMessage, 'Usage: load [PDB_ID]');
    });

    test('repr with a name targets that object and preserves its case', () {
      final h = _Harness()..run('repr surface My Structure.pdb');
      expect(h.lastCommand, 'setObjectRepresentation');
      expect(h.lastPayload['name'], 'My Structure.pdb');
      expect(h.lastPayload['representation'], 'surface');
    });

    test('repr accepts the mixed-case ballAndStick raw value from a lowercased command', () {
      final h = _Harness()..run('repr ballandstick 1CRN');
      expect(h.lastPayload['representation'], 'ballAndStick');
    });

    test('repr without a name applies to the visible structures', () {
      final h = _Harness()..loadStructures(<String>['1CRN'], hidden: <String>['4HHB']);
      h.run('repr surface');
      expect(h.lastCommand, 'setRepresentation');
      expect(h.lastPayload['targets'], <String>['1CRN']);
    });

    test('repr rejects an unknown representation', () {
      final h = _Harness()..run('repr blobby');
      expect(h.controller.errorMessage, startsWith('Invalid representation.'));
    });

    test('hide of a feature toggles the scene-wide visibility', () {
      final h = _Harness()..run('hide water');
      expect(h.lastCommand, 'toggleVisibility');
      expect(h.lastPayload, <String, dynamic>{'feature': 'water', 'isVisible': false});
      expect(h.controller.visibilityStates[MoleculeVisibilityFeature.water], isFalse);
    });

    test('hide of an unknown word is treated as an object name', () {
      final h = _Harness()..run('hide 1CRN');
      expect(h.lastCommand, 'setObjectVisibility');
      expect(h.lastPayload, <String, dynamic>{'name': '1CRN', 'isVisible': false});
    });

    test('show of an already-shown feature is a no-op', () {
      final h = _Harness()..run('show water');
      expect(h.runner.evaluated, isEmpty);
    });

    test('select parses an expression into an AST payload', () {
      final h = _Harness()..run('select mysel chain A & resn ala');
      expect(h.lastCommand, 'setSelection');
      expect(h.lastPayload['label'], 'mysel: chain A & resn ala');
      final ast = h.lastPayload['ast'] as Map<String, dynamic>;
      expect(ast['kind'], 'and');
      expect((ast['left'] as List).first, <String, dynamic>{'kind': 'chain', 'value': 'A'});
    });

    test('select reports a parse error without sending anything', () {
      final h = _Harness()..run('select chain');
      expect(h.runner.evaluated, isEmpty);
      expect(h.controller.errorMessage, 'Missing value for chain');
    });

    test('select with no expression reports usage', () {
      final h = _Harness()..run('select');
      expect(h.controller.errorMessage, startsWith('Usage: select'));
    });

    test('color maps a named color to its Okabe-Ito hex', () {
      final h = _Harness()..run('color red 1CRN');
      expect(h.lastCommand, 'setObjectColor');
      expect(h.lastPayload['colorHex'], namedColors['red']);
    });

    test('color default clears the override', () {
      final h = _Harness()..run('color default 1CRN');
      expect(h.lastPayload['colorHex'], isNull);
    });

    // A typo must report usage, not silently paint the object white.
    test('color rejects an unknown color name', () {
      final h = _Harness()..run('color gren 1CRN');
      expect(h.runner.evaluated, isEmpty);
      expect(h.controller.errorMessage, startsWith('Usage: color'));
    });

    test('color rejects a malformed hex instead of sending NaN to the viewer', () {
      // hexToMolStarColor in viewer.html is a bare parseInt, so a bad hex paints the object NaN
      // (black) with no error anywhere — the same reason `background` validates its argument.
      final h = _Harness()..run('color #12345 1CRN');
      expect(h.controller.errorMessage, startsWith('Usage: color'));
      expect(h.runner.evaluated, isEmpty);
    });

    test('background accepts a preset name and a raw hex', () {
      final h = _Harness()..run('background white');
      expect(h.lastPayload['colorHex'], '#FFFFFF');
      h.run('bg #123abc');
      expect(h.lastPayload['colorHex'], '#123ABC');
    });

    test('background rejects a malformed hex', () {
      final h = _Harness()..run('background #12345');
      expect(h.controller.errorMessage, startsWith('Usage: background'));
    });

    test('superpose needs two visible structures', () {
      final h = _Harness()..loadStructures(<String>['1CRN']);
      h.run('super');
      expect(h.runner.evaluated, isEmpty);
      expect(h.controller.errorMessage, 'Show at least two structures to superpose.');

      h.loadStructures(<String>['1CRN', '4HHB']);
      h.run('super');
      expect(h.lastCommand, 'superpose');
      expect(h.lastPayload['targets'], <String>['1CRN', '4HHB']);
    });

    test('morph loop is opt-in', () {
      final h = _Harness()..run('morph');
      expect(h.lastPayload['loop'], isFalse);
      h.run('morph loop');
      expect(h.lastPayload['loop'], isTrue);
      h.run('morph stop');
      expect(h.lastCommand, 'stopMorph');
    });

    test('measure enters, switches and leaves modes', () {
      final h = _Harness()..run('measure');
      expect(h.controller.measureKind, MeasureKind.distance);
      expect(h.lastPayload, <String, dynamic>{'enabled': true, 'kind': 'distance'});

      h.run('measure dihedral');
      expect(h.controller.measureKind, MeasureKind.dihedral);

      h.run('measure off');
      expect(h.controller.measureKind, isNull);
      expect(h.lastPayload, <String, dynamic>{'enabled': false});

      h.run('measure clear');
      expect(h.lastCommand, 'clearMeasurements');
    });

    test('an unknown command is reported and sends nothing', () {
      final h = _Harness()..run('frobnicate');
      expect(h.runner.evaluated, isEmpty);
      expect(h.controller.errorMessage, 'Unknown command: frobnicate');
    });

    test('running a command clears the input', () {
      final h = _Harness()..run('focus');
      expect(h.controller.commandText, isEmpty);
    });

    test('an empty command does nothing', () {
      final h = _Harness()..run('   ');
      expect(h.runner.evaluated, isEmpty);
    });
  });

  group('status line', () {
    test('advances only when a command succeeds', () {
      final h = _Harness()..run('load 1crn');
      expect(h.controller.statusMessage, 'Loading 1CRN');

      h.bridge.receiveMessage(<String, dynamic>{
        'id': 'x',
        'command': 'loadPdbId',
        'success': true,
        'label': '1CRN',
      });
      expect(h.controller.statusMessage, 'Loaded 1CRN');
    });

    // A rejected command must not leave the status claiming "Loading …" next to the error banner.
    test('falls back to idle when an in-flight command fails', () {
      final h = _Harness()..run('load 1crn');
      h.bridge.receiveMessage(<String, dynamic>{
        'id': 'x',
        'command': 'loadPdbId',
        'success': false,
        'error': 'Network is unreachable.',
      });
      expect(h.controller.statusMessage, kIdleStatus);
      expect(h.controller.errorMessage, 'Network is unreachable.');
    });

    // measureKind is set optimistically; a failed setMeasureMode must not leave the banner up with
    // taps doing nothing.
    test('clears measure mode when the viewer rejects it', () {
      final h = _Harness()..run('measure');
      expect(h.controller.measureKind, MeasureKind.distance);
      h.bridge.receiveMessage(<String, dynamic>{
        'id': 'x',
        'command': 'setMeasureMode',
        'success': false,
        'error': 'Mol* viewer is not ready.',
      });
      expect(h.controller.measureKind, isNull);
    });

    // JS is the authority: it reports the moment it drops these modes, so a command that clears
    // them and then fails cannot leave the UI claiming a mode the viewer no longer has.
    test('transientModesStopped clears measure and morph', () {
      final h = _Harness()..run('measure angle');
      h.bridge.receiveMessage(<String, dynamic>{
        'id': 'y',
        'command': 'startMorph',
        'success': true,
      });
      expect(h.controller.isMorphing, isTrue);

      h.bridge.receiveMessage(<String, dynamic>{
        'id': 'z',
        'command': 'transientModesStopped',
        'success': true,
      });
      expect(h.controller.measureKind, isNull);
      expect(h.controller.isMorphing, isFalse);
    });

    test('a measurement is reported with the active mode name', () {
      final h = _Harness()..run('measure angle');
      h.bridge.receiveMessage(<String, dynamic>{'event': 'measurement', 'label': 'CA — CB — CG'});
      expect(h.controller.statusMessage, 'Angle: CA — CB — CG');
    });

    test('feature visibility pushed by JS updates the menu labels', () {
      final h = _Harness();
      expect(h.controller.visibilityStates[MoleculeVisibilityFeature.water], isTrue);
      h.bridge.receiveMessage(
        <String, dynamic>{'event': 'featureVisibility', 'feature': 'water', 'isVisible': false},
      );
      expect(h.controller.visibilityStates[MoleculeVisibilityFeature.water], isFalse);
    });
  });

  group('encoding', () {
    test('the envelope is valid JSON embedded in a JS call', () {
      final h = _Harness()..run('load 1crn');
      final script = h.runner.evaluated.last;
      expect(script, startsWith('window.molapp.handleNativeCommand('));
      expect(script, endsWith('); void 0;'));
      final json = script.substring(
        script.indexOf('(') + 1,
        script.lastIndexOf('); void 0;'),
      );
      expect(() => jsonDecode(json), returnsNormally);
    });
  });
}
