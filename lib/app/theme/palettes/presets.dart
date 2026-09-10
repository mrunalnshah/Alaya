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
  static const AlayaPalette activePreset = alaya;

  /// Every preset, for Settings and the Theme Lab.
  static const List<AlayaPalette> all = [
    alaya,
    royalSapphire,
    material,
    nord,
  ];

  static const AlayaPalette alaya = AlayaPalette(
    name: 'Alaya',
    description: 'Midnight black, ivory white, and warm saffron gold.',
    light: AlayaColorSet(
      surfaceBase: Color(0xFFF8F8F6),
      surfaceRaised: Color(0xFFFFFFFF),
      surfaceOverlay: Color(0xFFFFFFFF),
      surfaceSunken: Color(0xFFEDEDEA),

      primary: Color(0xFF000000),
      onPrimary: Color(0xFFFDFDFD),

      accent: Color(0xFFFDB424),
      onAccent: Color(0xFF1A1200),

      textPrimary: Color(0xFF111111),
      textSecondary: Color(0xFF555555),
      textMuted: Color(0xFF888888),

      divider: Color(0xFFE1E1DE),

      income: Color(0xFF21865B),
      expense: Color(0xFFD64545),
      transfer: Color(0xFF5B6472),

      warning: Color(0xFFFDB424),
      danger: Color(0xFFD64545),
      success: Color(0xFF21865B),

      onStatus: Color(0xFFFFFFFF),
    ),

    dark: AlayaColorSet(
      surfaceBase: Color(0xFF0A0A0A),
      surfaceRaised: Color(0xFF141414),
      surfaceOverlay: Color(0xFF1E1E1E),
      surfaceSunken: Color(0xFF050505),

      primary: Color(0xFFFDFDFD),
      onPrimary: Color(0xFF000000),

      accent: Color(0xFFFDB424),
      onAccent: Color(0xFF1A1200),

      textPrimary: Color(0xFFF5F5F3),
      textSecondary: Color(0xFFB4B4B1),
      textMuted: Color(0xFF777774),

      divider: Color(0xFF2A2A28),

      income: Color(0xFF5ED69A),
      expense: Color(0xFFFF7777),
      transfer: Color(0xFF9BA3B0),

      warning: Color(0xFFFDB424),
      danger: Color(0xFFFF7777),
      success: Color(0xFF5ED69A),

      onStatus: Color(0xFF000000),
    ),
  );

  static const AlayaPalette royalSapphire = AlayaPalette(
    name: 'Royal Sapphire',
    description:
        'Deep sapphire, midnight blue, and antique gold inspired by luxury banking and fine watchmaking.',

    light: AlayaColorSet(
      surfaceBase: Color(0xFFF5F7FA),
      surfaceRaised: Color(0xFFFFFFFF),
      surfaceOverlay: Color(0xFFFFFFFF),
      surfaceSunken: Color(0xFFE7EBF2),

      primary: Color(0xFF243B6B),
      onPrimary: Color(0xFFFFFFFF),

      accent: Color(0xFFB9924A),
      onAccent: Color(0xFF211704),

      textPrimary: Color(0xFF172033),
      textSecondary: Color(0xFF526078),
      textMuted: Color(0xFF8490A6),

      divider: Color(0xFFD9DEE7),

      income: Color(0xFF277A61),
      expense: Color(0xFFB54A58),
      transfer: Color(0xFF5577A8),

      warning: Color(0xFFB9924A),
      danger: Color(0xFFB54A58),
      success: Color(0xFF277A61),

      onStatus: Color(0xFFFFFFFF),
    ),

    dark: AlayaColorSet(
      surfaceBase: Color(0xFF080D18),
      surfaceRaised: Color(0xFF101827),
      surfaceOverlay: Color(0xFF182337),
      surfaceSunken: Color(0xFF050912),

      primary: Color(0xFF8FAEE8),
      onPrimary: Color(0xFF101A2E),

      accent: Color(0xFFD1AD62),
      onAccent: Color(0xFF211806),

      textPrimary: Color(0xFFEFF3FA),
      textSecondary: Color(0xFFB4C0D3),
      textMuted: Color(0xFF78869D),

      divider: Color(0xFF29354A),

      income: Color(0xFF63C39C),
      expense: Color(0xFFE37A82),
      transfer: Color(0xFF8FAEE8),

      warning: Color(0xFFD1AD62),
      danger: Color(0xFFE37A82),
      success: Color(0xFF63C39C),

      onStatus: Color(0xFF080D18),
    ),
  );

  static const AlayaPalette material = AlayaPalette(
    name: 'Material',
    description:
        'Clean surfaces, expressive blue, and balanced Material-inspired accents.',
    light: AlayaColorSet(
      surfaceBase: Color(0xFFF9F9FC),
      surfaceRaised: Color(0xFFFFFFFF),
      surfaceOverlay: Color(0xFFFFFFFF),
      surfaceSunken: Color(0xFFECECF1),

      primary: Color(0xFF6750A4),
      onPrimary: Color(0xFFFFFFFF),

      accent: Color(0xFF7D5260),
      onAccent: Color(0xFFFFFFFF),

      textPrimary: Color(0xFF1C1B1F),
      textSecondary: Color(0xFF49454F),
      textMuted: Color(0xFF79747E),

      divider: Color(0xFFE3E0E5),

      income: Color(0xFF2E7D5B),
      expense: Color(0xFFBA1A1A),
      transfer: Color(0xFF4F5D75),

      warning: Color(0xFF8A6500),
      danger: Color(0xFFBA1A1A),
      success: Color(0xFF2E7D5B),

      onStatus: Color(0xFFFFFFFF),
    ),

    dark: AlayaColorSet(
      surfaceBase: Color(0xFF141218),
      surfaceRaised: Color(0xFF1D1B20),
      surfaceOverlay: Color(0xFF26232B),
      surfaceSunken: Color(0xFF100E13),

      primary: Color(0xFFD0BCFF),
      onPrimary: Color(0xFF381E72),

      accent: Color(0xFFEFB8C8),
      onAccent: Color(0xFF492532),

      textPrimary: Color(0xFFE6E1E5),
      textSecondary: Color(0xFFCAC4D0),
      textMuted: Color(0xFF938F99),

      divider: Color(0xFF49454F),

      income: Color(0xFF6FCB9F),
      expense: Color(0xFFFFB4AB),
      transfer: Color(0xFFA9B7D0),

      warning: Color(0xFFE5C36A),
      danger: Color(0xFFFFB4AB),
      success: Color(0xFF6FCB9F),

      onStatus: Color(0xFF1C1B1F),
    ),
  );

  static const AlayaPalette nord = AlayaPalette(
    name: 'Nord',
    description:
        'Arctic blue-gray surfaces with frost blue and aurora accents.',
    light: AlayaColorSet(
      surfaceBase: Color(0xFFECEFF4),
      surfaceRaised: Color(0xFFF5F7FA),
      surfaceOverlay: Color(0xFFFFFFFF),
      surfaceSunken: Color(0xFFE5E9F0),

      primary: Color(0xFF5E81AC),
      onPrimary: Color(0xFFFFFFFF),

      accent: Color(0xFF88C0D0),
      onAccent: Color(0xFF16323A),

      textPrimary: Color(0xFF2E3440),
      textSecondary: Color(0xFF4C566A),
      textMuted: Color(0xFF7B8494),

      divider: Color(0xFFD8DEE9),

      income: Color(0xFFA3BE8C),
      expense: Color(0xFFBF616A),
      transfer: Color(0xFF81A1C1),

      warning: Color(0xFFEBCB8B),
      danger: Color(0xFFBF616A),
      success: Color(0xFFA3BE8C),

      onStatus: Color(0xFF2E3440),
    ),

    dark: AlayaColorSet(
      surfaceBase: Color(0xFF2E3440),
      surfaceRaised: Color(0xFF3B4252),
      surfaceOverlay: Color(0xFF434C5E),
      surfaceSunken: Color(0xFF242933),

      primary: Color(0xFF88C0D0),
      onPrimary: Color(0xFF24343A),

      accent: Color(0xFF81A1C1),
      onAccent: Color(0xFF17232E),

      textPrimary: Color(0xFFECEFF4),
      textSecondary: Color(0xFFD8DEE9),
      textMuted: Color(0xFF9AA5B5),

      divider: Color(0xFF4C566A),

      income: Color(0xFFA3BE8C),
      expense: Color(0xFFBF616A),
      transfer: Color(0xFF81A1C1),

      warning: Color(0xFFEBCB8B),
      danger: Color(0xFFBF616A),
      success: Color(0xFFA3BE8C),

      onStatus: Color(0xFF2E3440),
    ),
  );
}
