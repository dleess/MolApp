// Regression test for the measure-mode pick lifecycle, against the real Mol* click path.
//
//   flutter test integration_test/measure_pick_test.dart -d macos
//
// Two bugs this pins down, both of which read to the user as the viewer hanging onto atoms they
// thought they had left behind:
//
//  1. A pick that never completed a pair stayed armed forever, because a click on empty space
//     returned early instead of cancelling it. Abandon a pick, select the pair you actually want,
//     and the stale atom silently pairs with the first of them — every later measurement off by one.
//  2. Mol* focuses whatever you left-click and draws that residue plus its surroundings in its own
//     visual. That is a different manager from the selection marks, so nothing cleared it: it
//     survived into measure mode and came back on every pick.
//
// See handleMeasurePick / clearFocusVisual in MolApp/Resources/viewer.html.
//
// The clicks here carry button and modifier keys on purpose. Mol*'s own behaviors only run when
// the event matches their bindings, so an event without them skips focus and select entirely and
// quietly tests far less of the real click path than it appears to.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:molapp/src/models.dart';
import 'package:molapp/src/molstar_bridge.dart';
import 'package:molapp/src/molstar_web_view.dart';

/// Four alanines with distinct CA positions, so CA1..CA4 are unambiguous pick targets.
const String _pdb = '''
ATOM      1  N   ALA A   1      -0.677  -1.230  -0.491  1.00  0.00           N
ATOM      2  CA  ALA A   1      -0.001   0.064  -0.491  1.00  0.00           C
ATOM      3  C   ALA A   1       1.499  -0.110  -0.491  1.00  0.00           C
ATOM      4  O   ALA A   1       2.030  -1.227  -0.494  1.00  0.00           O
ATOM      5  CB  ALA A   1      -0.509   0.856   0.708  1.00  0.00           C
ATOM      6  N   ALA A   2       2.193   1.024  -0.487  1.00  0.00           N
ATOM      7  CA  ALA A   2       3.648   1.084  -0.483  1.00  0.00           C
ATOM      8  C   ALA A   2       4.137   2.235   0.394  1.00  0.00           C
ATOM      9  O   ALA A   2       3.435   3.234   0.585  1.00  0.00           O
ATOM     10  CB  ALA A   2       4.207   1.208  -1.899  1.00  0.00           C
ATOM     11  N   ALA A   3       5.354   2.098   0.923  1.00  0.00           N
ATOM     12  CA  ALA A   3       5.951   3.128   1.771  1.00  0.00           C
ATOM     13  C   ALA A   3       7.451   2.917   1.949  1.00  0.00           C
ATOM     14  O   ALA A   3       7.980   1.800   1.951  1.00  0.00           O
ATOM     15  CB  ALA A   3       5.269   3.161   3.137  1.00  0.00           C
ATOM     16  N   ALA A   4       8.146   4.051   2.096  1.00  0.00           N
ATOM     17  CA  ALA A   4       9.601   4.111   2.275  1.00  0.00           C
ATOM     18  C   ALA A   4      10.089   5.262   3.152  1.00  0.00           C
ATOM     19  O   ALA A   4       9.387   6.261   3.343  1.00  0.00           O
ATOM     20  CB  ALA A   4      10.160   4.235   0.859  1.00  0.00           C
TER      21      ALA A   4
END
''';

/// Pushes real per-atom loci through the same click subject `handleMeasurePick` subscribes to, and
/// reports the pick/measurement state. Driving Mol*'s own event stream is what makes this a test of
/// the shipped path rather than of a reimplementation of it.
const String _installHarness = r'''
window.__probe = {
  clickCA: function (resSeq) {
    var lib = window.molstar.lib.structure;
    var SE = lib.StructureElement, Q = lib.Queries, P = lib.StructureProperties;
    var plugin = window.molapp.viewer.plugin;
    var structure = plugin.managers.structure.hierarchy.current.structures[0].cell.obj.data;
    var loci = SE.Loci.fromQuery(structure, Q.generators.atoms({
      residueTest: function (ctx) { return P.residue.auth_seq_id(ctx.element) === resSeq; },
      atomTest: function (ctx) { return P.atom.label_atom_id(ctx.element) === 'CA'; }
    }));
    if (SE.Loci.size(loci) !== 1) throw new Error('expected exactly one CA for residue ' + resSeq);
    plugin.behaviors.interaction.click.next(window.__probe.clickEvent(loci));
    return 1;
  },
  // Mol*'s own behaviors (focus, select) only run when the event carries the button and modifier
  // keys their bindings match on. An event without them silently skips every one of them, which
  // makes a synthetic click a far weaker test than a real one.
  clickEvent: function (loci) {
    return {
      current: { loci: loci },
      button: 1, buttons: 1,
      modifiers: { alt: false, control: false, meta: false, shift: false }
    };
  },
  // Widens the window in which addMeasurement is still awaiting, so the "pick made while the
  // previous measurement is still being drawn" race is deterministic instead of timing-dependent.
  slowDownAddDistance: function (ms) {
    var m = window.molapp.viewer.plugin.managers.structure.measurement;
    var original = m.addDistance.bind(m);
    m.addDistance = function () {
      var args = Array.prototype.slice.call(arguments);
      return new Promise(function (resolve) { setTimeout(resolve, ms); })
        .then(function () { return original.apply(null, args); });
    };
    return 'patched';
  },
  clickEmpty: function () {
    var plugin = window.molapp.viewer.plugin;
    plugin.behaviors.interaction.click.next(window.__probe.clickEvent({ kind: 'empty-loci' }));
    return 1;
  },
  // A tap that lands on a bond instead of an atom — what happens when you aim between two atoms
  // in stick mode. Not an atom, but not empty space either.
  clickBond: function () {
    var plugin = window.molapp.viewer.plugin;
    var structure = plugin.managers.structure.hierarchy.current.structures[0].cell.obj.data;
    var Bond = window.molstar.lib.structure.Bond;
    var unit = structure.units[0];
    plugin.behaviors.interaction.click.next(window.__probe.clickEvent(
      Bond.Loci(structure, [{ aUnit: unit, aIndex: 0, bUnit: unit, bIndex: 1 }])));
    return 1;
  },
  // Measurements are built as their own transforms with the visual params flat on them, so read
  // the manager's own list rather than guessing at cell shapes.
  measurementColors: function () {
    var m = window.molapp.viewer.plugin.managers.structure.measurement.state;
    var out = [];
    function hex(c) {
      return (c === undefined || c === null) ? null
        : '#' + ('000000' + c.toString(16)).slice(-6).toUpperCase();
    }
    ['distances', 'angles', 'dihedrals'].forEach(function (key) {
      (m[key] || []).forEach(function (cell) {
        var p = (cell.transform && cell.transform.params) || {};
        out.push({
          kind: key,
          text: hex(p.textColor),
          line: hex(p.linesColor === undefined ? p.color : p.linesColor)
        });
      });
    });
    return out;
  },
  state: function () {
    var plugin = window.molapp.viewer.plugin;
    var m = plugin.managers.structure.measurement.state;
    var selection = plugin.managers.structure.selection;
    return JSON.stringify({
      pending: (window.molapp.measurePending || []).length,
      pendingLabels: (window.molapp.measurePending || []).map(function (p) { return p.label; }),
      distances: (m.distances || []).length,
      // Atoms still carrying the pick overlay — what a user reads as "still selected".
      selectedAtoms: selection.stats ? selection.stats.elementCount : -1,
      appSelection: window.molapp.selection ? window.molapp.selection.label : null,
      granularity: plugin.managers.interactivity.props.granularity,
      // Mol*'s own click-focus layer: a separate manager from lociSelects, with its own
      // ball-and-stick visual of the clicked residue and everything around it.
      focus: plugin.managers.structure.focus.current
        ? plugin.managers.structure.focus.current.label : null,
      // Colours the drawn measurements actually carry, as hex, so the assertions read like the
      // palette they come from rather than like Mol*'s packed integers.
      measurementColors: window.__probe.measurementColors()
    });
  }
};
return 'installed';
''';

/// Captures the JS runner the webview hands the bridge, so the test can talk to the page directly.
/// `attach` is public API, so this needs no production seam.
class SpyBridge extends MolStarBridge {
  MolStarJsRunner? runner;

  @override
  void attach(MolStarJsRunner jsRunner) {
    runner = jsRunner;
    super.attach(jsRunner);
  }

  Future<Object?> js(String source) => runner!.callAsync(source);

  Future<Map<String, dynamic>> probe() async {
    final raw = (await js('return window.__probe.state();')).toString();
    return (jsonDecode(raw) as Map).cast<String, dynamic>();
  }
}

Future<bool> pumpUntil(WidgetTester tester, bool Function() condition,
    {Duration timeout = const Duration(seconds: 60)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await tester.pump(const Duration(milliseconds: 50));
  }
  return condition();
}

/// Mol* completes a measurement asynchronously, so give the page real time rather than pumping
/// Flutter frames and assuming the webview kept up.
Future<void> settle(WidgetTester tester, [Duration duration = const Duration(milliseconds: 900)]) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<SpyBridge> bootViewer(WidgetTester tester, {bool measure = true}) async {
  final bridge = SpyBridge();
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: MolStarWebView(bridge: bridge))));
  expect(await pumpUntil(tester, () => bridge.isViewerReady), isTrue,
      reason: 'viewer never became ready: ${bridge.lastErrorMessage}');

  bridge.loadLocalStructure(data: _pdb, format: 'pdb', label: 'helix.pdb');
  expect(await pumpUntil(tester, () => bridge.objects.isNotEmpty), isTrue,
      reason: 'structure never loaded: ${bridge.lastErrorMessage}');

  await bridge.js(_installHarness);
  if (measure) {
    bridge.setMeasureMode(true, kind: 'distance');
    await settle(tester, const Duration(milliseconds: 600));
  }
  return bridge;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('consecutive pairs measure the atoms actually picked', (tester) async {
    final bridge = await bootViewer(tester);

    await bridge.js('return window.__probe.clickCA(1);');
    await settle(tester);
    expect((await bridge.probe())['pending'], 1);

    await bridge.js('return window.__probe.clickCA(2);');
    await settle(tester);
    var state = await bridge.probe();
    expect(state['pending'], 0);
    expect(state['distances'], 1);
    expect(state['selectedAtoms'], 0, reason: 'pick marks must clear once the measurement is drawn');
    expect(bridge.lastMeasurement, 'ALA A 1 CA — ALA A 2 CA');

    // The second pair must stand alone, not chain off the first.
    await bridge.js('return window.__probe.clickCA(3);');
    await settle(tester);
    await bridge.js('return window.__probe.clickCA(4);');
    await settle(tester);
    state = await bridge.probe();
    expect(state['pending'], 0);
    expect(state['distances'], 2);
    expect(bridge.lastMeasurement, 'ALA A 3 CA — ALA A 4 CA');
  });

  testWidgets('clicking empty space cancels a half-finished pick', (tester) async {
    final bridge = await bootViewer(tester);

    await bridge.js('return window.__probe.clickCA(1);');
    await settle(tester);
    expect((await bridge.probe())['pending'], 1);

    await bridge.js('return window.__probe.clickEmpty();');
    await settle(tester, const Duration(milliseconds: 500));
    final cancelled = await bridge.probe();
    expect(cancelled['pending'], 0, reason: 'the abandoned pick must not stay armed');
    expect(cancelled['selectedAtoms'], 0, reason: 'and its mark must go with it');

    // The user now picks the pair they actually want; it must not include the abandoned atom.
    await bridge.js('return window.__probe.clickCA(3);');
    await settle(tester);
    await bridge.js('return window.__probe.clickCA(4);');
    await settle(tester);
    final state = await bridge.probe();
    expect(state['distances'], 1);
    expect(state['pending'], 0);
    expect(bridge.lastMeasurement, 'ALA A 3 CA — ALA A 4 CA');
  });

  testWidgets('rapid picks still pair up in order', (tester) async {
    final bridge = await bootViewer(tester);

    for (final residue in <int>[1, 2, 3, 4]) {
      await bridge.js('return window.__probe.clickCA($residue);');
      await tester.pump(const Duration(milliseconds: 16));
    }
    await settle(tester, const Duration(milliseconds: 2000));

    final state = await bridge.probe();
    expect(state['distances'], 2, reason: 'four fast picks are two measurements, not one');
    expect(state['pending'], 0);
    expect(bridge.lastMeasurement, 'ALA A 3 CA — ALA A 4 CA');
  });

  // A pick made while the previous measurement is still being drawn must survive. On a large
  // structure addDistance takes long enough for a normal click to land inside that window.
  testWidgets('a pick made while the previous measurement is still drawing is kept', (tester) async {
    final bridge = await bootViewer(tester);
    await bridge.js('return window.__probe.slowDownAddDistance(2500);');

    await bridge.js('return window.__probe.clickCA(1);');
    await settle(tester, const Duration(milliseconds: 300));
    await bridge.js('return window.__probe.clickCA(2);'); // starts the slow measurement
    await settle(tester, const Duration(milliseconds: 300));

    // Still inside addDistance's await: the user picks the first atom of their next pair.
    await bridge.js('return window.__probe.clickCA(3);');
    await settle(tester, const Duration(milliseconds: 400));
    expect((await bridge.probe())['pending'], 1, reason: 'the new pick should be armed');

    // Let the first measurement finish and clean up after itself.
    await settle(tester, const Duration(milliseconds: 3000));
    final afterDraw = await bridge.probe();
    expect(afterDraw['distances'], 1);
    expect(afterDraw['pending'], 1, reason: 'CA3 must not be swallowed by the finished measurement');
    expect(afterDraw['pendingLabels'], <String>['ALA A 3 CA']);

    await bridge.js('return window.__probe.clickCA(4);');
    await settle(tester, const Duration(milliseconds: 3500));
    final state = await bridge.probe();
    expect(state['distances'], 2);
    expect(bridge.lastMeasurement, 'ALA A 3 CA — ALA A 4 CA');
  });

  // Selection visuals and pick marks are the same overlay: a `select` command mid-pick used to
  // wipe the marks while leaving the picks armed and invisible.
  testWidgets('a selection command mid-pick drops the pending picks with their marks',
      (tester) async {
    final bridge = await bootViewer(tester);

    await bridge.js('return window.__probe.clickCA(1);');
    await settle(tester);
    expect((await bridge.probe())['pending'], 1);

    bridge.setSelection(const MoleculeSelection(
      type: 'expression',
      label: 'sele: chain A',
      ast: SelectionAST(kind: SelectionASTKind.chain, value: 'A'),
    ));
    await settle(tester);
    expect((await bridge.probe())['pending'], 0,
        reason: 'picks must not survive invisibly behind a new selection');

    await bridge.js('return window.__probe.clickCA(3);');
    await settle(tester);
    await bridge.js('return window.__probe.clickCA(4);');
    await settle(tester);
    expect(bridge.lastMeasurement, 'ALA A 3 CA — ALA A 4 CA');
  });

  // Entering measure mode must start from a blank slate: an atom selected beforehand is a normal
  // selection, not the first half of a measurement, and it carries the same overlay a pick does.
  testWidgets('a selection made before measure mode does not join the first measurement',
      (tester) async {
    final bridge = await bootViewer(tester, measure: false);

    await bridge.js('return window.__probe.clickCA(1);');
    await settle(tester);
    final selected = await bridge.probe();
    expect(selected['appSelection'], 'ALA A 1 CA', reason: 'precondition: CA1 is selected');
    expect(selected['selectedAtoms'], greaterThan(0), reason: 'precondition: and it is marked');

    bridge.setMeasureMode(true, kind: 'distance');
    await settle(tester, const Duration(milliseconds: 600));
    final entered = await bridge.probe();
    expect(entered['pending'], 0, reason: 'the standing selection is not a pending pick');
    expect(entered['selectedAtoms'], 0, reason: 'and its mark must not linger as a pick mark');
    expect(entered['appSelection'], isNull);

    // The user now picks the pair they want; CA1 must play no part in it.
    await bridge.js('return window.__probe.clickCA(3);');
    await settle(tester);
    expect((await bridge.probe())['pending'], 1);
    await bridge.js('return window.__probe.clickCA(4);');
    await settle(tester);
    final state = await bridge.probe();
    expect(state['distances'], 1);
    expect(state['pending'], 0);
    expect(bridge.lastMeasurement, 'ALA A 3 CA — ALA A 4 CA');
  });

  // Same thing one level up: a `select` expression run before measure mode leaves a whole chain
  // marked, which is the loudest possible version of "it remembered what I had selected".
  testWidgets('a selection expression run before measure mode is cleared on entry', (tester) async {
    final bridge = await bootViewer(tester, measure: false);

    bridge.setSelection(const MoleculeSelection(
      type: 'expression',
      label: 'chain A',
      ast: SelectionAST(kind: SelectionASTKind.chain, value: 'A'),
    ));
    await settle(tester);
    expect((await bridge.probe())['selectedAtoms'], greaterThan(1),
        reason: 'precondition: the whole chain is marked');

    bridge.setMeasureMode(true, kind: 'distance');
    await settle(tester, const Duration(milliseconds: 600));
    final entered = await bridge.probe();
    expect(entered['selectedAtoms'], 0);
    expect(entered['pending'], 0);

    await bridge.js('return window.__probe.clickCA(2);');
    await settle(tester);
    await bridge.js('return window.__probe.clickCA(3);');
    await settle(tester);
    expect(bridge.lastMeasurement, 'ALA A 2 CA — ALA A 3 CA');
    expect((await bridge.probe())['distances'], 1);
  });

  // Leaving and re-entering measure mode must not carry a half-finished pick across, and must put
  // the residue-level picking granularity back so normal selection behaves as it did before.
  testWidgets('leaving measure mode with a pick armed does not carry it into the next session',
      (tester) async {
    final bridge = await bootViewer(tester);

    await bridge.js('return window.__probe.clickCA(1);');
    await settle(tester);
    expect((await bridge.probe())['pending'], 1);

    bridge.setMeasureMode(false);
    await settle(tester, const Duration(milliseconds: 600));
    final off = await bridge.probe();
    expect(off['pending'], 0, reason: 'the armed pick must not outlive measure mode');
    expect(off['selectedAtoms'], 0);
    expect(off['granularity'], 'residue', reason: 'atom-level picking is measure-mode only');

    bridge.setMeasureMode(true, kind: 'distance');
    await settle(tester, const Duration(milliseconds: 600));
    await bridge.js('return window.__probe.clickCA(3);');
    await settle(tester);
    await bridge.js('return window.__probe.clickCA(4);');
    await settle(tester);
    expect(bridge.lastMeasurement, 'ALA A 3 CA — ALA A 4 CA');
    expect((await bridge.probe())['distances'], 1);
  });

  // The armed picks have to reach the shell, because the on-canvas pick marks are easy to miss:
  // an invisible leftover pick is exactly what "it remembered what I had selected" feels like.
  testWidgets('the shell is told how many atoms are armed', (tester) async {
    final bridge = await bootViewer(tester, measure: false);

    await bridge.js('return window.__probe.clickCA(1);');
    await settle(tester);

    bridge.setMeasureMode(true, kind: 'distance');
    await settle(tester, const Duration(milliseconds: 600));
    expect(bridge.measurePendingCount, 0, reason: 'measure mode starts from a blank slate');
    expect(bridge.measurePendingLabels, isEmpty);
    expect(bridge.measureTargetCount, 2);

    await bridge.js('return window.__probe.clickCA(3);');
    await settle(tester);
    expect(bridge.measurePendingCount, 1);
    expect(bridge.measurePendingLabels, <String>['ALA A 3 CA']);

    await bridge.js('return window.__probe.clickCA(4);');
    await settle(tester);
    expect(bridge.measurePendingCount, 0, reason: 'the drawn measurement consumed both picks');
    expect(bridge.measurePendingLabels, isEmpty);

    // Abandoning a pick must be reported too, or the banner keeps claiming an atom is armed.
    await bridge.js('return window.__probe.clickCA(1);');
    await settle(tester);
    expect(bridge.measurePendingCount, 1);
    await bridge.js('return window.__probe.clickEmpty();');
    await settle(tester, const Duration(milliseconds: 500));
    expect(bridge.measurePendingCount, 0);
  });

  testWidgets('switching measure kind reports the new atom target', (tester) async {
    final bridge = await bootViewer(tester);
    expect(bridge.measureTargetCount, 2);

    bridge.setMeasureMode(true, kind: 'dihedral');
    await settle(tester, const Duration(milliseconds: 600));
    expect(bridge.measureTargetCount, 4, reason: 'a dihedral needs four atoms, not two');
    expect(bridge.measurePendingCount, 0);
  });

  // Aiming between two atoms in stick mode hits a bond. That is a miss, not an abandonment —
  // throwing the pick away there would make picks feel like they randomly vanish.
  testWidgets('clicking a bond leaves the pending pick alone', (tester) async {
    final bridge = await bootViewer(tester);

    await bridge.js('return window.__probe.clickCA(1);');
    await settle(tester);
    expect((await bridge.probe())['pending'], 1);

    await bridge.js('return window.__probe.clickBond();');
    await settle(tester, const Duration(milliseconds: 500));
    expect((await bridge.probe())['pending'], 1, reason: 'a bond tap is a miss, not a cancel');
    expect(bridge.measurePendingLabels, <String>['ALA A 1 CA']);

    await bridge.js('return window.__probe.clickCA(2);');
    await settle(tester);
    expect(bridge.lastMeasurement, 'ALA A 1 CA — ALA A 2 CA');
  });


  // Mol* focuses whatever you left-click and draws that residue plus its surroundings in its own
  // ball-and-stick visual — a different manager from the selection marks, so nothing used to clear
  // it. It survived into measure mode and reappeared on every pick, which is exactly what "it
  // remembers what I selected before" and "something else keeps getting selected" look like.
  testWidgets('choosing a measurement mode clears Mol* click focus', (tester) async {
    final bridge = await bootViewer(tester, measure: false);

    await bridge.js('return window.__probe.clickCA(1);');
    await settle(tester);
    expect((await bridge.probe())['focus'], 'ALA 1 | A',
        reason: 'precondition: a plain click focuses the residue');

    bridge.setMeasureMode(true, kind: 'distance');
    await settle(tester, const Duration(milliseconds: 600));
    final entered = await bridge.probe();
    expect(entered['focus'], isNull, reason: 'the focused residue must not survive into measuring');
    expect(entered['selectedAtoms'], 0);
    expect(entered['pending'], 0);
  });

  testWidgets('a measure pick does not light up the rest of the residue', (tester) async {
    final bridge = await bootViewer(tester);

    await bridge.js('return window.__probe.clickCA(1);');
    await settle(tester);
    final picked = await bridge.probe();
    expect(picked['focus'], isNull, reason: 'only the picked atom should be marked');
    expect(picked['selectedAtoms'], 1, reason: 'the atom, not its whole residue');

    await bridge.js('return window.__probe.clickCA(2);');
    await settle(tester);
    final done = await bridge.probe();
    expect(done['focus'], isNull);
    expect(done['selectedAtoms'], 0);
    expect(bridge.lastMeasurement, 'ALA A 1 CA — ALA A 2 CA');
  });

  // Switching kinds mid-session goes down the already-in-measure-mode path, which used to skip the
  // reset entirely.
  testWidgets('switching measurement kind also resets everything', (tester) async {
    final bridge = await bootViewer(tester);

    await bridge.js('return window.__probe.clickCA(1);');
    await settle(tester);
    expect((await bridge.probe())['pending'], 1);

    bridge.setMeasureMode(true, kind: 'angle');
    await settle(tester, const Duration(milliseconds: 600));
    final switched = await bridge.probe();
    expect(switched['pending'], 0, reason: 'a distance pick must not carry into an angle');
    expect(switched['selectedAtoms'], 0);
    expect(switched['focus'], isNull);
    expect(bridge.measureTargetCount, 3);
  });


  // Stick used to drop the atom-sphere visual entirely, leaving only bond cylinders. With nothing
  // atom-shaped on screen, every click identified a bond and picking an atom did nothing at all in
  // stick — while the identical gesture worked in ball-and-stick.
  testWidgets('stick representation still draws atoms the user can pick', (tester) async {
    final bridge = await bootViewer(tester, measure: false);
    bridge.setRepresentation('stick', targets: <String>[bridge.objects.first.name]);
    await settle(tester, const Duration(milliseconds: 2000));

    final raw = (await bridge.js(r"""
      var plugin = window.molapp.viewer.plugin;
      var found = [];
      plugin.state.data.cells.forEach(function (cell) {
        var p = cell.transform && cell.transform.params;
        if (p && p.type && p.type.name === 'ball-and-stick') found.push(p.type.params.visuals || []);
      });
      return JSON.stringify({ reprs: found, representation: window.molapp.representation });
    """)).toString();
    final state = (jsonDecode(raw) as Map).cast<String, dynamic>();
    expect(state['representation'], 'stick');
    final reprs = (state['reprs'] as List).cast<List<dynamic>>();
    expect(reprs, isNotEmpty, reason: 'stick should build ball-and-stick representations');
    for (final visuals in reprs) {
      expect(visuals, contains('element-sphere'),
          reason: 'without the sphere visual there is no atom geometry to click');
      expect(visuals, contains('intra-bond'));
    }

    // And picking still works there, atom-to-atom.
    bridge.setMeasureMode(true, kind: 'distance');
    await settle(tester, const Duration(milliseconds: 600));
    await bridge.js('return window.__probe.clickCA(1);');
    await settle(tester);
    await bridge.js('return window.__probe.clickCA(2);');
    await settle(tester);
    expect(bridge.lastMeasurement, 'ALA A 1 CA — ALA A 2 CA');
    expect((await bridge.probe())['distances'], 1);
  });

  // Mol* draws measurement text in black by default, which is unreadable on this near-black
  // viewport. The value has to come out in the palette the rest of the app uses.
  testWidgets('measurements are drawn in Okabe-Ito colours', (tester) async {
    final bridge = await bootViewer(tester);

    await bridge.js('return window.__probe.clickCA(1);');
    await settle(tester);
    await bridge.js('return window.__probe.clickCA(2);');
    await settle(tester);
    expect(bridge.lastMeasurement, 'ALA A 1 CA — ALA A 2 CA');

    final drawn = ((await bridge.probe())['measurementColors'] as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    expect(drawn, hasLength(1));
    expect(drawn.single['kind'], 'distances');
    expect(drawn.single['text'], '#F0E442', reason: 'Okabe-Ito yellow — the readable one on dark');
    expect(drawn.single['line'], '#E69F00', reason: 'Okabe-Ito orange');

    bridge.setMeasureMode(true, kind: 'angle');
    await settle(tester, const Duration(milliseconds: 600));
    for (final residue in <int>[1, 2, 3]) {
      await bridge.js('return window.__probe.clickCA($residue);');
      await settle(tester);
    }
    final withAngle = ((await bridge.probe())['measurementColors'] as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    final angle = withAngle.firstWhere((m) => m['kind'] == 'angles');
    expect(angle['text'], '#F0E442');
    expect(angle['line'], '#E69F00', reason: 'angle colours its vectors, arc and sector as one');
  });

  testWidgets('measuring the same pair twice reports both times', (tester) async {
    final bridge = await bootViewer(tester);

    await bridge.js('return window.__probe.clickCA(1);');
    await settle(tester);
    await bridge.js('return window.__probe.clickCA(2);');
    await settle(tester);
    final firstSeq = bridge.measurementSeq;
    expect(bridge.lastMeasurement, 'ALA A 1 CA — ALA A 2 CA');

    await bridge.js('return window.__probe.clickCA(1);');
    await settle(tester);
    await bridge.js('return window.__probe.clickCA(2);');
    await settle(tester);
    // Same label, genuinely new measurement: the sequence must advance so the status line updates.
    expect(bridge.measurementSeq, greaterThan(firstSeq));
    expect((await bridge.probe())['distances'], 2);
  });
}
