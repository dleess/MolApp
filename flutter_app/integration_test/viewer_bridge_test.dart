// End-to-end check of the one seam unit tests cannot cover: Dart → platform webview → viewer.html
// → Mol* → back. Runs the real viewer against the real asset bundle.
//
//   flutter test integration_test/viewer_bridge_test.dart -d macos
//
// Swap -d for windows / linux / <android device> / <ios device> to prove a platform is wired up.
// Deliberately offline: a structure is pushed in as text, so no RCSB fetch and no file picker.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:molapp/src/models.dart';
import 'package:molapp/src/molstar_bridge.dart';
import 'package:molapp/src/molstar_web_view.dart';

/// Five atoms of one alanine — enough for Mol* to build a structure, small enough to inline.
const String _miniPdb = '''
ATOM      1  N   ALA A   1      11.104   6.134  -6.504  1.00  0.00           N
ATOM      2  CA  ALA A   1      11.639   6.071  -5.147  1.00  0.00           C
ATOM      3  C   ALA A   1      13.140   6.246  -5.153  1.00  0.00           C
ATOM      4  O   ALA A   1      13.665   7.062  -5.898  1.00  0.00           O
ATOM      5  CB  ALA A   1      11.006   7.144  -4.278  1.00  0.00           C
TER       6      ALA A   1
END
''';

// Mol* chooses its polymer/ligand preset at 10 residues; smaller fixtures use one "All" component.
final String _ligandPdb = <String>[
  for (var residue = 0; residue < 12; residue++)
    for (final line in _miniPdb.split('\n').where((line) => line.startsWith('ATOM')))
      '${line.substring(0, 6)}${(int.parse(line.substring(6, 11)) + residue * 5).toString().padLeft(5)}'
      '${line.substring(11, 22)}${(residue + 1).toString().padLeft(4)}${line.substring(26, 30)}'
      '${(double.parse(line.substring(30, 38)) + residue * 3.3).toStringAsFixed(3).padLeft(8)}'
      '${line.substring(38)}',
  'TER',
  'HETATM   61  P   ATP B  20      18.000  10.000  -5.000  1.00  0.00           P',
  'HETATM   62  O1P ATP B  20      19.400  10.000  -5.000  1.00  0.00           O',
  'HETATM   63 MG    MG B  21      22.000  10.000  -5.000  1.00  0.00          MG',
  'END',
  '',
].join('\n');

class _InspectBridge extends MolStarBridge {
  late MolStarJsRunner runner;

  @override
  void attach(MolStarJsRunner jsRunner) {
    runner = jsRunner;
    super.attach(jsRunner);
  }
}

/// Pumps until [condition] holds or the deadline passes. `pumpAndSettle` is no use here: the
/// webview drives itself outside Flutter's frame scheduling.
Future<bool> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await tester.pump(const Duration(milliseconds: 100));
  }
  return condition();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('viewer boots, accepts a structure and reports it back', (tester) async {
    final bridge = MolStarBridge();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: MolStarWebView(bridge: bridge))),
    );

    // 1. viewer.html loaded from the asset bundle, molstar.js resolved, and the transport hook
    //    carried the viewerReady event back to Dart.
    expect(
      await pumpUntil(tester, () => bridge.isViewerReady),
      isTrue,
      reason: 'viewerReady never arrived: ${bridge.lastErrorMessage}',
    );

    // 2. A command envelope survives the round trip and Mol* builds the structure.
    bridge.loadLocalStructure(data: _miniPdb, format: 'pdb', label: 'mini.pdb');
    expect(
      await pumpUntil(tester, () => bridge.objects.isNotEmpty),
      isTrue,
      reason: 'no object was reported: ${bridge.lastErrorMessage}',
    );
    expect(bridge.objects.single.name, 'mini.pdb');
    expect(bridge.objects.single.type, MolAppObjectType.structure);
    expect(bridge.lastErrorMessage, isNull);

    // 3. A per-object command lands and JS republishes the panel from its own state.
    bridge.setObjectRepresentation(
      name: 'mini.pdb',
      representation: ObjectRepresentation.sphere,
    );
    expect(
      await pumpUntil(
        tester,
        () => bridge.objects.single.representation == ObjectRepresentation.sphere,
      ),
      isTrue,
      reason: 'representation never changed: ${bridge.lastErrorMessage}',
    );

    // 4. The request/response path (used by Save State and every image export).
    final state = await bridge.serializeState();
    expect(state, isNotNull);
    expect(state, contains('mini.pdb'));

    final dataUrl = await bridge.captureImageDataURL();
    expect(dataUrl, startsWith('data:image/png;base64,'));

    // 5. Reset clears the scene and the panel with it.
    bridge.resetAll();
    expect(
      await pumpUntil(tester, () => bridge.objects.isEmpty),
      isTrue,
      reason: 'reset left objects behind: ${bridge.lastErrorMessage}',
    );
  });

  testWidgets('two complexes keep independent ligands after edits and state restore', (tester) async {
    final bridge = _InspectBridge();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MolStarWebView(bridge: bridge))));
    expect(await pumpUntil(tester, () => bridge.isViewerReady), isTrue);

    Future<void> command(MolStarCommand name, VoidCallback send) async {
      final previous = bridge.lastCommandResult;
      send();
      expect(await pumpUntil(tester, () => bridge.lastCommandResult != previous &&
          bridge.lastCommandResult?.command == name), isTrue);
      expect(bridge.lastCommandResult!.success, isTrue, reason: bridge.lastErrorMessage);
    }

    for (final label in ['first.pdb', 'second.pdb']) {
      await command(MolStarCommand.loadLocalStructure,
          () => bridge.loadLocalStructure(data: _ligandPdb, format: 'pdb', label: label));
      if (label == 'first.pdb') {
        await command(MolStarCommand.setObjectColor,
            () => bridge.setObjectColor(name: label, colorHex: '#FF0000'));
      }
    }
    final components = await bridge.runner.callAsync('''
      return JSON.stringify(window.molapp.viewer.plugin.managers.structure.hierarchy.current.structures
        .map(s => s.components.map(c => ({ label: c.cell.obj.label, tags: c.cell.transform.tags }))));
    ''');
    expect(bridge.objects.where((o) => o.type == MolAppObjectType.selection).map((o) => o.name),
        containsAll(['ATP', 'second.pdb/ATP']), reason: components.toString());

    Future<void> expectLigandOwners() async {
      final raw = await bridge.runner.callAsync('''
        return JSON.stringify(window.molapp.viewer.plugin.managers.structure.hierarchy.current.structures
          .map(function(s) {
            return s.components.filter(function(c) {
              return c.cell.obj && /ATP\$/.test(c.cell.obj.label);
            }).map(function(c) { return c.cell.obj.label; });
          }));
      ''');
      expect(jsonDecode(raw! as String), [['ATP'], ['second.pdb/ATP']]);
      final colors = await bridge.runner.callAsync('''
        return JSON.stringify(window.molapp.viewer.plugin.managers.structure.hierarchy.current.structures[0]
          .components.filter(c => c.cell.obj.label === 'ATP')
          .flatMap(c => c.representations.map(r => r.cell.params.values.colorTheme.params.value)));
      ''');
      expect(jsonDecode(colors! as String), [0xFF0000]);
    }

    await expectLigandOwners();
    await command(MolStarCommand.setObjectVisibility,
        () => bridge.setObjectVisibility(name: 'first.pdb', isVisible: false));
    expect(bridge.objects.singleWhere((o) => o.name == 'second.pdb/ATP').isVisible, isTrue);
    await command(MolStarCommand.setObjectVisibility,
        () => bridge.setObjectVisibility(name: 'first.pdb', isVisible: true));
    await command(MolStarCommand.setObjectRepresentation, () => bridge.setObjectRepresentation(
        name: 'second.pdb/ATP', representation: ObjectRepresentation.sphere));
    await expectLigandOwners();

    final saved = await bridge.serializeState();
    expect(saved, isNotNull);
    await command(MolStarCommand.resetAll, bridge.resetAll);
    await command(MolStarCommand.loadState, () => bridge.loadState(saved!));
    await command(MolStarCommand.setObjectRepresentation, () => bridge.setObjectRepresentation(
        name: 'first.pdb', representation: ObjectRepresentation.stick));
    await expectLigandOwners();
    expect(bridge.objects.singleWhere((o) => o.name == 'second.pdb/ATP').representation,
        ObjectRepresentation.sphere);
    expect(await bridge.captureImageDataURL(), startsWith('data:image/png;base64,'));
  });
}
