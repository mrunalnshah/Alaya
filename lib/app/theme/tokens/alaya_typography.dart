import 'dart:ui' show FontFeature;

import 'package:flutter/widgets.dart';

/// The type scale (ARCH_3 §8) — one scale, semantic names, no colours.
///
/// Every style here is colourless on purpose. Colour arrives from the palette through
/// `AlayaTheme`, so a widget that needs a warning-coloured label composes
/// `AlayaTypography.label.copyWith(color: semantic.warning)` rather than reaching for a second
/// style that happens to be the right colour. One axis per token.
///
/// **The scale carries this app's personality, because no custom font can.** Bundling a display
/// face needs either a font package or assets declared under `android/`, and this phase may do
/// neither — so the character comes from weight, size and figure treatment instead. That turns out
/// to suit the subject: a household ledger is read in columns, and what makes a column legible is
/// that the digits line up, not that the headings are expressive.
abstract final class AlayaTypography {
  /// Amounts and any figure that appears in a column.
  ///
  /// **Tabular figures are the one deliberate typographic risk in this design.** By default most
  /// fonts render proportional digits, so `1` is narrower than `8` and a column of amounts jitters
  /// left and right as the values change. `FontFeature.tabularFigures()` forces every digit to the
  /// same advance width, so a ledger column aligns on the decimal without a monospace font — and
  /// with Indian grouping (`2,50,000`) that matters more than usual, because the group widths differ
  /// from Western grouping and the eye has fewer landmarks.
  static const List<FontFeature> figures = [FontFeature.tabularFigures()];

  /// Slashed zero, where a zero could be misread as an O — account numbers, recovery codes.
  static const List<FontFeature> slashedZero = [
    FontFeature.tabularFigures(),
    FontFeature.slashedZero(),
  ];

  /// The dashboard's headline figure. One per screen, at most.
  static const TextStyle displayAmount = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w300,
    height: 1.1,
    // Negative tracking at display size: default tracking is set for body text and looks loose
    // once the glyphs are this large.
    letterSpacing: -1.2,
    fontFeatures: figures,
  );

  /// A card's primary amount.
  static const TextStyle amountLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: -0.4,
    fontFeatures: figures,
  );

  /// A ledger row's amount. The most-rendered style in the app.
  static const TextStyle amountMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.25,
    letterSpacing: -0.1,
    fontFeatures: figures,
  );

  /// A secondary or converted amount, shown beneath the original.
  static const TextStyle amountSmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.3,
    fontFeatures: figures,
  );

  /// A quantity, which is a figure and so shares the tabular treatment.
  static const TextStyle quantity = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.3,
    fontFeatures: figures,
  );

  /// An app-bar or screen title.
  static const TextStyle screenTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: -0.2,
  );

  /// A section header inside a scrolling screen.
  static const TextStyle sectionHeader = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
    // Positive tracking and upper case in the widget: at this size a header needs to read as a
    // label rather than as small body text, and tracking does that without another weight.
    letterSpacing: 0.8,
  );

  /// A card's title.
  static const TextStyle cardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// Default running text.
  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  /// Running text that needs emphasis without becoming a heading.
  static const TextStyle bodyEmphasis = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.45,
  );

  /// A form field's label.
  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  /// Metadata — a date, an account name beneath a title, a unit suffix.
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  /// A small eyebrow above a section, and a chip's text.
  static const TextStyle overline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.6,
  );

  /// A button's label.
  static const TextStyle button = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.1,
  );

  /// Every style, for the Theme Lab to enumerate without a hand-maintained list going stale.
  static const Map<String, TextStyle> all = {
    'displayAmount': displayAmount,
    'amountLarge': amountLarge,
    'amountMedium': amountMedium,
    'amountSmall': amountSmall,
    'quantity': quantity,
    'screenTitle': screenTitle,
    'sectionHeader': sectionHeader,
    'cardTitle': cardTitle,
    'body': body,
    'bodyEmphasis': bodyEmphasis,
    'label': label,
    'caption': caption,
    'overline': overline,
    'button': button,
  };
}
