import 'package:flutter/widgets.dart';

import 'package:alaya/app/theme/palettes/palette.dart';

/// The palettes that ship, and the one constant that switches the app's entire look (ARCH_3 §8).
///
/// **Deliberate constraint on income and expense: they differ in lightness as well as hue.** Roughly
/// eight percent of men have some red-green deficiency, and a finance app that encodes gain and loss
/// in hue alone is unreadable for them. In every preset below, income is the lighter of the pair —
/// so even with hue removed the two remain distinguishable, and `AmountText` additionally renders an
/// explicit sign rather than relying on colour at all.
abstract final class AlayaPresets {
  /// The palette the app boots with.
  ///
  /// **Changing this one constant changes the entire app's look**, which is the requirement ARCH_3 §8
  /// exists to satisfy. Nothing else needs editing.
  static const AlayaPalette activePreset = indigoKhata;

  /// Every preset, for Settings and the Theme Lab.
  static const List<AlayaPalette> all = [
    indigoKhata,
    slateSage,
    midnightBrass,
    monsoonTeal,
  ];

  /// Indigo ink on bone paper, with brass for anything you touch.
  ///
  /// The default. Drawn from the bound household ledger this app replaces — indigo dye and the brass
  /// of a ledger clasp — rather than from a generic finance blue. The background is bone rather than
  /// cream: cream with a serif and a terracotta accent has become the default look of generated
  /// interfaces, and picking it would say nothing about this app.
  static const AlayaPalette indigoKhata = AlayaPalette(
    name: 'Indigo Khata',
    description: 'Indigo ink on bone paper, brass for anything you touch.',
    light: AlayaColorSet(
      surfaceBase: Color(0xFFF6F5F1),
      surfaceRaised: Color(0xFFFFFFFF),
      surfaceOverlay: Color(0xFFFFFFFF),
      surfaceSunken: Color(0xFFECEAE3),
      primary: Color(0xFF2A3A6B),
      onPrimary: Color(0xFFFFFFFF),
      accent: Color(0xFF9A6A1E),
      onAccent: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF1B2033),
      textSecondary: Color(0xFF515873),
      textMuted: Color(0xFF868CA3),
      divider: Color(0xFFDDDAD1),
      income: Color(0xFF2E7D5B),
      expense: Color(0xFF9E2A2B),
      transfer: Color(0xFF4A5578),
      warning: Color(0xFF9A6A1E),
      danger: Color(0xFF9E2A2B),
      success: Color(0xFF2E7D5B),
      onStatus: Color(0xFFFFFFFF),
    ),
    dark: AlayaColorSet(
      surfaceBase: Color(0xFF14161F),
      surfaceRaised: Color(0xFF1D202C),
      surfaceOverlay: Color(0xFF262A38),
      surfaceSunken: Color(0xFF0E1017),
      primary: Color(0xFF98AEE8),
      onPrimary: Color(0xFF121727),
      accent: Color(0xFFD9A650),
      onAccent: Color(0xFF231803),
      textPrimary: Color(0xFFECEDF2),
      textSecondary: Color(0xFFA8AEC4),
      textMuted: Color(0xFF767D93),
      divider: Color(0xFF2E3342),
      income: Color(0xFF6FCB9F),
      expense: Color(0xFFE58A87),
      transfer: Color(0xFF98A4C8),
      warning: Color(0xFFD9A650),
      danger: Color(0xFFE58A87),
      success: Color(0xFF6FCB9F),
      onStatus: Color(0xFF121727),
    ),
  );

  /// Cool grey with sage, for when the app should disappear.
  ///
  /// The quiet option. Almost no saturation outside the semantic colours, so the only thing with any
  /// chroma on screen is a number that means something.
  static const AlayaPalette slateSage = AlayaPalette(
    name: 'Slate Sage',
    description:
        'Cool grey with sage. Nothing has colour except the numbers that matter.',
    light: AlayaColorSet(
      surfaceBase: Color(0xFFF4F5F5),
      surfaceRaised: Color(0xFFFFFFFF),
      surfaceOverlay: Color(0xFFFFFFFF),
      surfaceSunken: Color(0xFFE9EBEB),
      primary: Color(0xFF3D4A47),
      onPrimary: Color(0xFFFFFFFF),
      accent: Color(0xFF5E8B72),
      onAccent: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF1E2422),
      textSecondary: Color(0xFF56605D),
      textMuted: Color(0xFF8B9491),
      divider: Color(0xFFD9DDDC),
      income: Color(0xFF2F7A57),
      expense: Color(0xFF98342F),
      transfer: Color(0xFF4F5F5B),
      warning: Color(0xFF8A6516),
      danger: Color(0xFF98342F),
      success: Color(0xFF2F7A57),
      onStatus: Color(0xFFFFFFFF),
    ),
    dark: AlayaColorSet(
      surfaceBase: Color(0xFF161918),
      surfaceRaised: Color(0xFF1F2322),
      surfaceOverlay: Color(0xFF282D2B),
      surfaceSunken: Color(0xFF101312),
      primary: Color(0xFFA7BCB4),
      onPrimary: Color(0xFF15201C),
      accent: Color(0xFF86B79A),
      onAccent: Color(0xFF102016),
      textPrimary: Color(0xFFE9ECEB),
      textSecondary: Color(0xFFA6AFAC),
      textMuted: Color(0xFF757E7B),
      divider: Color(0xFF2F3533),
      income: Color(0xFF74C79C),
      expense: Color(0xFFE0908B),
      transfer: Color(0xFF9DA9A5),
      warning: Color(0xFFD3AC5F),
      danger: Color(0xFFE0908B),
      success: Color(0xFF74C79C),
      onStatus: Color(0xFF15201C),
    ),
  );

  /// Brass and copper on blue-black. Dark-first.
  ///
  /// Designed dark and then given a light mode, rather than the reverse. The base is a blue-black
  /// rather than pure black: on OLED, `#000000` makes the surface tiers collapse into one another,
  /// so the sense of depth that replaces shadow in dark mode disappears exactly where it is needed.
  static const AlayaPalette midnightBrass = AlayaPalette(
    name: 'Midnight Brass',
    description: 'Brass and copper on blue-black. Built dark first.',
    light: AlayaColorSet(
      surfaceBase: Color(0xFFF2F1EE),
      surfaceRaised: Color(0xFFFCFBF9),
      surfaceOverlay: Color(0xFFFFFFFF),
      surfaceSunken: Color(0xFFE6E4DF),
      primary: Color(0xFF2B2E3A),
      onPrimary: Color(0xFFF7F3EA),
      accent: Color(0xFF8A6220),
      onAccent: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF1A1C24),
      textSecondary: Color(0xFF4F5361),
      textMuted: Color(0xFF848897),
      divider: Color(0xFFD8D5CE),
      income: Color(0xFF2C7355),
      expense: Color(0xFF973027),
      transfer: Color(0xFF4A4E5E),
      warning: Color(0xFF8A6220),
      danger: Color(0xFF973027),
      success: Color(0xFF2C7355),
      onStatus: Color(0xFFFFFFFF),
    ),
    dark: AlayaColorSet(
      surfaceBase: Color(0xFF0F1118),
      surfaceRaised: Color(0xFF181B25),
      surfaceOverlay: Color(0xFF212530),
      surfaceSunken: Color(0xFF090A0F),
      primary: Color(0xFFE2C79A),
      onPrimary: Color(0xFF1B1607),
      accent: Color(0xFFC98B4B),
      onAccent: Color(0xFF1D1104),
      textPrimary: Color(0xFFF0EDE6),
      textSecondary: Color(0xFFB0ACA1),
      textMuted: Color(0xFF7B776D),
      divider: Color(0xFF2A2E3A),
      income: Color(0xFF79C9A2),
      expense: Color(0xFFE0897E),
      transfer: Color(0xFFA9A79E),
      warning: Color(0xFFDFB264),
      danger: Color(0xFFE0897E),
      success: Color(0xFF79C9A2),
      onStatus: Color(0xFF1B1607),
    ),
  );

  /// Cool teal on pale grey-blue, for high ambient light.
  ///
  /// The deliberate counter-proposal to a warm off-white. A phone used at a market stall in
  /// daylight needs the highest text contrast of any preset here, and a cool background holds
  /// contrast better than a warm one under a bright sky.
  static const AlayaPalette monsoonTeal = AlayaPalette(
    name: 'Monsoon Teal',
    description:
        'Cool teal on pale grey-blue. The highest contrast, for bright daylight.',
    light: AlayaColorSet(
      surfaceBase: Color(0xFFEFF3F4),
      surfaceRaised: Color(0xFFFFFFFF),
      surfaceOverlay: Color(0xFFFFFFFF),
      surfaceSunken: Color(0xFFE1E8EA),
      primary: Color(0xFF11555F),
      onPrimary: Color(0xFFFFFFFF),
      accent: Color(0xFF0D7A85),
      onAccent: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF0C1F23),
      textSecondary: Color(0xFF3E5A60),
      textMuted: Color(0xFF74898E),
      divider: Color(0xFFCFDADC),
      income: Color(0xFF1F6F4A),
      expense: Color(0xFF8E2622),
      transfer: Color(0xFF3B5B62),
      warning: Color(0xFF8A5B0F),
      danger: Color(0xFF8E2622),
      success: Color(0xFF1F6F4A),
      onStatus: Color(0xFFFFFFFF),
    ),
    dark: AlayaColorSet(
      surfaceBase: Color(0xFF0D1518),
      surfaceRaised: Color(0xFF152125),
      surfaceOverlay: Color(0xFF1D2C31),
      surfaceSunken: Color(0xFF080E10),
      primary: Color(0xFF7FC8D2),
      onPrimary: Color(0xFF062226),
      accent: Color(0xFF4FB3BF),
      onAccent: Color(0xFF042023),
      textPrimary: Color(0xFFE7EFF0),
      textSecondary: Color(0xFF9FB6BA),
      textMuted: Color(0xFF6D8388),
      divider: Color(0xFF25373C),
      income: Color(0xFF6DC79B),
      expense: Color(0xFFE28A83),
      transfer: Color(0xFF93AFB5),
      warning: Color(0xFFD9AE63),
      danger: Color(0xFFE28A83),
      success: Color(0xFF6DC79B),
      onStatus: Color(0xFF062226),
    ),
  );
}
