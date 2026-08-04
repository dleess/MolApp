import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:molapp/src/molstar_web_view.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Android leaves scroll enabled so touchmove reaches the Mol* canvas', () {
    // The Android plugin consumes every ACTION_MOVE when both disable*Scroll flags are set,
    // which kills one-finger rotation. viewer.html pins scrolling itself.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final settings = viewerWebViewSettings();
    expect(settings.disableVerticalScroll, isFalse);
    expect(settings.disableHorizontalScroll, isFalse);
  });

  test('iOS keeps the scroll-disable flags (scrollView path, touches still delivered)', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final settings = viewerWebViewSettings();
    expect(settings.disableVerticalScroll, isTrue);
    expect(settings.disableHorizontalScroll, isTrue);
  });
}
