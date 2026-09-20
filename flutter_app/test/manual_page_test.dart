import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:molapp/src/manual_page.dart';

void main() {
  Future<void> pumpToEnd(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ManualPage()));
    for (var i = 0; i < 20; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pump();
    }
  }

  testWidgets('desktop shows the support link', (tester) async {
    await pumpToEnd(tester);
    expect(find.text('Buy me a coffee'), findsOneWidget);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  }));

  testWidgets('store builds hide the support link', (tester) async {
    await pumpToEnd(tester);
    expect(find.text('Buy me a coffee'), findsNothing);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{
    TargetPlatform.iOS,
    TargetPlatform.android,
  }));
}
