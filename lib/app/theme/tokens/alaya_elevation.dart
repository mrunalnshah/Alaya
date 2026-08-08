import 'package:flutter/widgets.dart';

/// The elevation scale (ARCH_3 §8).
///
/// Expressed as shadow lists rather than Material `elevation` doubles, because the same numeric
/// elevation reads very differently against a light and a dark surface — and in dark mode a
/// shadow is nearly invisible, so depth has to come from surface tiers instead. `AlayaTheme`
/// selects between [light] and [dark] accordingly, which is why both live here.
///
/// **The hex literals below are the one intentional exception to "no hex colours outside the
/// palette", and they are not palette colours.** A shadow is occlusion — light that a raised
/// surface blocked — so it is always neutral black and only its opacity changes. Deriving it from
/// the palette would tint the shadow, which is a different visual effect (a coloured glow) and one
/// no preset here asks for. The values are alpha steps, and the palette has no say in them.
abstract final class AlayaElevation {
  /// Flat. A surface that sits directly on its parent.
  static const List<BoxShadow> none = [];

  /// A card at rest, on a light background.
  static const List<BoxShadow> lightRaised = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 3)),
  ];

  /// A pressed or dragged card, a menu, on a light background.
  static const List<BoxShadow> lightFloating = [
    BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x0F000000), blurRadius: 18, offset: Offset(0, 8)),
  ];

  /// A sheet or dialog, on a light background.
  static const List<BoxShadow> lightOverlay = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, -4)),
  ];

  /// A card at rest, on a dark background.
  ///
  /// Darker and tighter than its light counterpart. A soft black shadow on a near-black surface is
  /// invisible, so the shadow's job in dark mode is only to separate an edge, and the sense of
  /// height comes from the palette's surface tiers.
  static const List<BoxShadow> darkRaised = [
    BoxShadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  /// A pressed or dragged card, on a dark background.
  static const List<BoxShadow> darkFloating = [
    BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3)),
  ];

  /// A sheet or dialog, on a dark background.
  static const List<BoxShadow> darkOverlay = [
    BoxShadow(color: Color(0x59000000), blurRadius: 20, offset: Offset(0, -2)),
  ];

  /// The raised shadow for [isDark].
  static List<BoxShadow> raised({required bool isDark}) =>
      isDark ? darkRaised : lightRaised;

  /// The floating shadow for [isDark].
  static List<BoxShadow> floating({required bool isDark}) =>
      isDark ? darkFloating : lightFloating;

  /// The overlay shadow for [isDark].
  static List<BoxShadow> overlay({required bool isDark}) =>
      isDark ? darkOverlay : lightOverlay;
}
