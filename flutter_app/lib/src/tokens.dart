import 'package:flutter/material.dart';

/// Every colour and type size the viewport chrome paints with.
///
/// The chrome is a set of translucent panels floating over a live 3D canvas, so its colours cannot
/// come from `ColorScheme` — they are compositing decisions against whatever the viewport happens
/// to be showing, and the viewport background is user-settable (Display ▸ Background) all the way
/// to white. Every value below was chosen by compositing it over all five background presets and
/// taking the worst-case WCAG ratio, not by eye.
///
/// Deliberately NOT a `ThemeExtension`: there is one theme and no animation between themes, so
/// `copyWith`/`lerp` would be ceremony around static data. If a light theme ever lands, that is the
/// upgrade path — the call sites already read through a single name each.
///
/// Colours derived from the theme are NOT here and should not move here: `manual_page.dart` and the
/// Display menu's section label modulate `theme.textTheme` / `colorScheme`, which is correct and
/// keeps tracking the theme.
abstract final class ChromeTokens {
  // MARK: - Surfaces

  /// The viewport behind everything, and the Scaffold under it.
  ///
  /// Also spelled as the 'Dark' entry in `backgroundPresets` (models.dart) and five times in
  /// `MolApp/Resources/viewer.html`. The JS side cannot import this; keep them in step by hand.
  static const Color viewport = Color(0xFF0B0F14);

  /// Okabe-Ito blue, the seed the whole `ColorScheme` is generated from (main.dart).
  static const Color seed = Color(0xFF0072B2);

  /// The one scrim behind every floating panel — menu bar, info card, objects panel, command bar,
  /// hover tooltip.
  ///
  /// Was five values (0.55 / 0.65 / 0.68 / 0.75 / 0.8) for this one concept. On the default
  /// `viewport` they composite to (5,7,9) … (2,3,4) — indistinguishable, which is why the spread
  /// survived review. On the White preset they composite to 115 / 89 / 82 / 64 / 51, i.e. the drift
  /// was invisible exactly where the app is normally used and glaring where it is not.
  ///
  /// 0.85 is the top of the old range, so no panel got lighter. It keeps white text at 15.1:1 on
  /// the worst background instead of the 1.2:1 the info card's old 0.55 produced on white.
  static final Color scrim = Colors.black.withValues(alpha: 0.85);

  // MARK: - Content on the chrome
  //
  // Three levels, down from six (1.0 / 0.75 / 0.6 / 0.45 / 0.4 / 0.35 / 0.3). The old scale put
  // four of its steps below WCAG AA on the default viewport and every step below it on white.
  // Icons ride the same scale as text.

  /// Titles, menu labels, field text, and the eye on a visible object. 15.1:1 worst case.
  static const Color textPrimary = Colors.white;

  /// Everything supporting: the status line, unselected representation chips, the command bar's
  /// icons and placeholder, "No objects", an object's type line. 7.2:1 worst case.
  static final Color textSecondary = Colors.white.withValues(alpha: 0.65);

  /// Deliberately receded: the eye on a hidden object, the run button with nothing typed. 4.2:1
  /// worst case — above the 3:1 floor these need as non-text affordances, and 3.6:1 apart from
  /// [textPrimary] so the hidden state stays legible as a state.
  static final Color textDisabled = Colors.white.withValues(alpha: 0.45);

  // MARK: - Lines and fills

  /// Object-row dividers and the command bar's outline.
  static final Color hairline = Colors.white.withValues(alpha: 0.15);

  /// The fill behind the selected representation chip.
  static final Color chipSelectedFill = Colors.white.withValues(alpha: 0.25);

  /// Ring around a colour dot, in the objects row and in the picker grid alike. The two were 0.3
  /// and 0.35 with nothing to distinguish the cases.
  static final Color dotBorder = Colors.white.withValues(alpha: 0.35);

  /// Stands in for a colour dot with no colour assigned.
  static final Color dotFallback = Colors.grey.withValues(alpha: 0.4);

  /// An object with no colour override, in the objects row (models.dart's `swatchColor`).
  static final Color swatchFallback = Colors.white.withValues(alpha: 0.3);

  /// Ring around the background-preset squares in the Display menu.
  static final Color presetSwatchBorder = Colors.grey.withValues(alpha: 0.6);

  // MARK: - Semantic
  //
  // NOT consolidated, and both still have findings against them: `accent` is Material's stock blue
  // while the ColorScheme is seeded from Okabe-Ito `seed` — two unrelated blues on screen at once —
  // and white on `banner` is 4.1:1 on the default viewport and 2.6:1 on white, which no alpha can
  // fix because white on Material blue is 3.1:1 at full opacity. Both need a hue decision, not a
  // token one.

  /// The armed-measure banner.
  static final Color banner = Colors.blue.withValues(alpha: 0.85);

  /// The run button once something is typed.
  static const Color accent = Colors.blue;

  /// Error text in the info card. Colour is the only error signal, which is a finding in itself.
  static final Color error = Colors.red.withValues(alpha: 0.9);

  /// Menu items that throw work away — today only File ▸ Reset All.
  static const Color destructive = Colors.red;

  // MARK: - Type
  //
  // NOT consolidated: seven sizes in 1pt steps is accumulation rather than a ramp, but re-spacing
  // them reflows every panel, which is a layout change and not a palette one.

  /// Info card title.
  static const double sizeTitle = 17;

  /// Menu bar labels.
  static const double sizeMenu = 15;

  /// Text fields and the command bar.
  static const double sizeField = 14;

  /// The info card's status line.
  static const double sizeStatus = 13;

  /// Hover tooltip, measure banner, object names, the colour popup's heading.
  static const double sizeBody = 12;

  /// Menu section labels and "No objects".
  static const double sizeSmall = 11;

  /// Representation chips and an object's type line.
  static const double sizeMicro = 10;
}
