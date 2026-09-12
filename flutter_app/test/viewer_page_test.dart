import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:molapp/src/molstar_bridge.dart';
import 'package:molapp/src/viewer_page.dart';

/// Stands in for the platform webview, and hands back the bridge the page built so a test can
/// push viewer events into the page from the outside.
class _ViewportStub extends StatelessWidget {
  const _ViewportStub();

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Color(0xFF0B0F14));
}

Future<MolStarBridge> pumpViewer(WidgetTester tester, {Size size = const Size(1200, 900)}) async {
  tester.view
    ..physicalSize = size * tester.view.devicePixelRatio
    ..devicePixelRatio = tester.view.devicePixelRatio;
  addTearDown(tester.view.reset);

  late MolStarBridge captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: MoleculeViewerPage(
        viewportBuilder: (bridge) {
          captured = bridge;
          return const _ViewportStub();
        },
      ),
    ),
  );
  await tester.pump();
  return captured;
}

void main() {
  testWidgets('renders the menu bar, info card, objects panel and command bar', (tester) async {
    await pumpViewer(tester);

    for (final menu in <String>['File', 'Edit', 'Display', 'Calculation', 'Measure', 'Help']) {
      expect(find.text(menu), findsOneWidget, reason: menu);
    }
    expect(find.text('Molecule Viewer'), findsOneWidget);
    expect(find.text('Ready for structure loading'), findsOneWidget);
    expect(find.text('Open Structure'), findsOneWidget);
    expect(find.text('Objects'), findsOneWidget);
    expect(find.text('No objects'), findsOneWidget);
    expect(find.text('Enter command (e.g. load 1crn, repr surface)...'), findsOneWidget);
  });

  testWidgets('the structure loading card starts open and can be closed', (tester) async {
    await pumpViewer(tester);

    expect(find.text('Molecule Viewer'), findsOneWidget);
    expect(find.byTooltip('Close structure loading'), findsOneWidget);

    await tester.tap(find.byTooltip('Close structure loading'));
    await tester.pump();

    expect(find.text('Molecule Viewer'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    expect(find.text('Open Structure'), findsOneWidget);
  });

  testWidgets('File menu reopens the closed structure loading card', (tester) async {
    await pumpViewer(tester);

    await tester.tap(find.byTooltip('Close structure loading'));
    await tester.pump();
    expect(find.text('Molecule Viewer'), findsNothing);

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Structure'));
    await tester.pumpAndSettle();
    expect(find.text('Molecule Viewer'), findsOneWidget);

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    expect(find.text('Load PDB ID'), findsNothing);
  });

  testWidgets('Display menu groups background presets in a submenu', (tester) async {
    await pumpViewer(tester);

    await tester.tap(find.text('Display'));
    await tester.pumpAndSettle();

    expect(
      find.ancestor(of: find.text('Background'), matching: find.byType(SubmenuButton)),
      findsOneWidget,
    );
    expect(find.text('White'), findsNothing);

    await tester.tap(find.text('Background'));
    await tester.pumpAndSettle();
    expect(find.text('White'), findsOneWidget);

    await tester.tap(find.text('White'));
    await tester.pumpAndSettle();
    expect(find.text('Background: White'), findsOneWidget);
  });

  testWidgets('the command bar runs what was typed', (tester) async {
    final bridge = await pumpViewer(tester);
    bridge.receiveMessage(<String, dynamic>{'event': 'viewerReady'});

    final commandField = find.widgetWithText(TextField, 'Enter command (e.g. load 1crn, repr surface)...');
    await tester.enterText(commandField, 'load 1crn');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('Loading 1CRN'), findsOneWidget);
    // The bar clears itself so the next command starts from empty.
    expect(tester.widget<TextField>(commandField).controller!.text, isEmpty);
  });

  testWidgets('the command bar clears even when the command changes nothing', (tester) async {
    final bridge = await pumpViewer(tester);
    bridge.receiveMessage(<String, dynamic>{'event': 'viewerReady'});

    final commandField =
        find.widgetWithText(TextField, 'Enter command (e.g. load 1crn, repr surface)...');
    // Arming angle mode twice: the second run is a no-op inside the controller, and a no-op still
    // has to leave the bar empty — otherwise the text sits there while the run button greys out.
    for (var i = 0; i < 2; i++) {
      await tester.enterText(commandField, 'measure angle');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }

    expect(tester.widget<TextField>(commandField).controller!.text, isEmpty);
  });

  testWidgets('an invalid command surfaces its error in the info card', (tester) async {
    await pumpViewer(tester);

    await tester.enterText(find.byType(TextField).last, 'frobnicate');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('Unknown command: frobnicate'), findsOneWidget);
  });

  testWidgets('the objects panel lists what the viewer reports', (tester) async {
    final bridge = await pumpViewer(tester);
    bridge.receiveMessage(<String, dynamic>{
      'event': 'objectsReplaced',
      'objects': <dynamic>[
        <String, dynamic>{'name': '1CRN', 'type': 'structure', 'representation': 'surface'},
        <String, dynamic>{'name': 'NAP', 'type': 'selection', 'isVisible': false},
      ],
    });
    await tester.pump();

    expect(find.text('No objects'), findsNothing);
    expect(find.text('1CRN'), findsOneWidget);
    expect(find.text('NAP'), findsOneWidget);
    expect(find.text('structure'), findsOneWidget);
    expect(find.text('selection'), findsOneWidget);
    // A hidden object shows the struck-through eye.
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsOneWidget);
  });

  testWidgets('tapping the eye asks the viewer to hide that object', (tester) async {
    final bridge = await pumpViewer(tester);
    bridge
      ..receiveMessage(<String, dynamic>{'event': 'viewerReady'})
      ..receiveMessage(<String, dynamic>{
        'event': 'objectsReplaced',
        'objects': <dynamic>[
          <String, dynamic>{'name': '1CRN', 'type': 'structure'},
        ],
      });
    await tester.pump();

    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();

    // JS is the authority on visibility, so the row only flips once the viewer says so.
    expect(bridge.objects.single.isVisible, isTrue);
    bridge.receiveMessage(<String, dynamic>{
      'event': 'objectsVisibility',
      'items': <dynamic>[
        <String, dynamic>{'name': '1CRN', 'isVisible': false},
      ],
    });
    await tester.pump();
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
  });

  testWidgets('the measure banner appears with the mode and pick count', (tester) async {
    await pumpViewer(tester);

    await tester.enterText(find.byType(TextField).last, 'measure dihedral');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('Dihedral mode — pick 4 atoms'), findsOneWidget);
  });

  // The on-canvas pick marks are easy to miss on a large structure, so the banner has to name the
  // atoms already armed — otherwise a leftover pick is invisible and reads as the app remembering
  // an atom the user thought they had left behind.
  testWidgets('the measure banner names the atoms already picked', (tester) async {
    final bridge = await pumpViewer(tester);

    await tester.enterText(find.byType(TextField).last, 'measure');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Distance mode — pick 2 atoms'), findsOneWidget);

    bridge.receiveMessage(<String, dynamic>{
      'event': 'measurePending',
      'count': 1,
      'target': 2,
      'labels': <String>['ALA A 1 CA'],
    });
    await tester.pump();
    expect(find.text('Distance mode — ALA A 1 CA (pick 1 more)'), findsOneWidget);

    bridge.receiveMessage(<String, dynamic>{
      'event': 'measurePending',
      'count': 0,
      'target': 2,
      'labels': <String>[],
    });
    await tester.pump();
    expect(find.text('Distance mode — pick 2 atoms'), findsOneWidget);
  });

  testWidgets('the hover tooltip shows only once both label and point are known', (tester) async {
    final bridge = await pumpViewer(tester);

    bridge.receiveMessage(<String, dynamic>{'event': 'pencilHover', 'label': 'GLY A 1 CA'});
    await tester.pump();
    expect(find.text('GLY A 1 CA'), findsNothing);

    bridge.updateHoverPoint(const Offset(300, 400));
    await tester.pump();
    expect(find.text('GLY A 1 CA'), findsOneWidget);
  });

  testWidgets('long measurement labels fit a narrow viewport', (tester) async {
    final bridge = await pumpViewer(tester, size: const Size(320, 700));
    await tester.enterText(find.byType(TextField).last, 'measure dihedral');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    bridge.receiveMessage(<String, dynamic>{
      'event': 'measurePending',
      'count': 3,
      'target': 4,
      'labels': <String>['ALA A 100 CA', 'GLY A 101 CA', 'LYS A 102 CA'],
    });
    await tester.pump();

    expect(tester.takeException(), isNull);
    final label = find.textContaining('ALA A 100 CA, GLY A 101 CA, LYS A 102 CA');
    expect(tester.getRect(label).right, lessThanOrEqualTo(320));
  });

  testWidgets('choosing an object color closes its menu', (tester) async {
    final bridge = await pumpViewer(tester);
    bridge.receiveMessage(<String, dynamic>{
      'event': 'objectsReplaced',
      'objects': <dynamic>[
        <String, dynamic>{'name': 'mini.pdb', 'type': 'structure'},
      ],
    });
    await tester.pump();
    await tester.tap(find.byType(MenuAnchor).last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('red'), findsOneWidget);
    await tester.tap(find.byTooltip('red'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('red'), findsNothing);
    expect(find.text('mini.pdb'), findsOneWidget);
  });

  testWidgets('the chrome clears the status-bar inset while the viewport stays full-bleed',
      (tester) async {
    // Without SafeArea the menu bar's `top: 8` put the whole row inside the iPhone's 59pt inset,
    // where the Dynamic Island covered Display outright and the system swallowed every tap in the
    // upper 46pt of each button. The hover tooltip must NOT move with it: its coordinates come
    // from the webview, which fills the un-inset window.
    const inset = 59.0;
    tester.view.padding = FakeViewPadding(top: inset * tester.view.devicePixelRatio);
    final bridge = await pumpViewer(tester);

    expect(tester.getTopLeft(find.widgetWithText(TextButton, 'File')).dy,
        greaterThanOrEqualTo(inset));

    bridge.receiveMessage(<String, dynamic>{'event': 'pencilHover', 'label': 'GLY A 1 CA'});
    bridge.updateHoverPoint(const Offset(300, 400));
    await tester.pump();
    expect(tester.getTopLeft(find.text('GLY A 1 CA')).dy, lessThan(400 - 28 + inset));
  });

  testWidgets('on an iPad the menu bar starts below the window-control pill', (tester) async {
    // iPadOS 26 draws the pill inside the app's content and reports no inset for it, so SafeArea
    // alone still left File and Edit buried under it. The display, not the window, is what says
    // "iPad": in windowed mode MediaQuery reports a window that can be phone-sized.
    tester.view.display
      ..size = const Size(2048, 2732)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.display.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await pumpViewer(tester, size: const Size(600, 800));
    await tester.enterText(find.byType(TextField).last, 'measure dihedral');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    final file = tester.getRect(find.widgetWithText(TextButton, 'File'));
    final banner = tester.getRect(find.text('Dihedral mode — pick 4 atoms'));
    // Must be cleared inside the body: the framework asserts on leftover debug vars before
    // addTearDown callbacks run.
    debugDefaultTargetPlatformOverride = null;

    expect(file.top, greaterThanOrEqualTo(44));
    // The banner is the last child of the overlay Stack, so it wins the paint. Left at an absolute
    // offset it printed straight over the menu labels once the bar moved down on iPad.
    expect(banner.top, greaterThanOrEqualTo(file.bottom));
  });

  testWidgets('the menu bar scrolls instead of clipping on a narrow window', (tester) async {
    await pumpViewer(tester, size: const Size(420, 900));
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.text('Help'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the File menu opens and disables the actions that need a structure',
      (tester) async {
    await pumpViewer(tester);
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();

    expect(find.text('Open Structure'), findsNWidgets(2)); // info card + menu item
    expect(find.text('Save State (.molapp)'), findsOneWidget);
    expect(find.text('Export Display'), findsOneWidget);

    final print = tester.widget<MenuItemButton>(
      find.ancestor(of: find.text('Print'), matching: find.byType(MenuItemButton)),
    );
    expect(print.onPressed, isNull, reason: 'nothing loaded yet, so there is nothing to print');
  });

  testWidgets('closing the info card frees its spot for viewport touches', (tester) async {
    // The left rail's scrollable used to hit-test opaque over its whole strip, so after closing
    // the structure-loading card the empty 340pt column still swallowed every touch meant for the
    // molecule underneath.
    var viewportTaps = 0;
    tester.view
      ..physicalSize = const Size(1200, 900) * tester.view.devicePixelRatio
      ..devicePixelRatio = tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: MoleculeViewerPage(
          viewportBuilder: (bridge) => Listener(
            onPointerDown: (_) => viewportTaps++,
            child: const _ViewportStub(),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Close structure loading'));
    await tester.pump();
    expect(find.text('Molecule Viewer'), findsNothing);

    // Middle of where the card used to sit: left rail starts at x16, card was 340 wide, top ~100.
    await tester.tapAt(const Offset(180, 200));
    expect(viewportTaps, 1, reason: 'the tap must fall through to the viewport');
  });

  testWidgets('the info card and the objects panel do not collide in landscape', (tester) async {
    // 874x402 is an iPhone 17 Pro rotated. The two overlays are anchored independently — the card
    // from the top, the panel from the bottom — so on a short viewport they used to overlap by
    // 88pt, with the panel painting over Open Structure, the PDB field and Load PDB.
    await pumpViewer(tester, size: const Size(874, 402));

    final cardBottom = tester.getRect(find.text('Load PDB')).bottom;
    final panelTop = tester.getRect(find.text('Objects')).top;

    expect(panelTop, greaterThanOrEqualTo(cardBottom),
        reason: 'objects panel starts $panelTop, info card still runs to $cardBottom');
  });

}
