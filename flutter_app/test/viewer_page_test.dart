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
}
