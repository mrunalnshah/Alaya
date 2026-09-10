import 'package:flutter/material.dart';

import 'package:alaya/app/theme/palettes/palette.dart';
import 'package:alaya/app/theme/palettes/presets.dart';

/// How the appearance choices are stored, and how a stored string becomes a choice again.
///
/// **This closes ARCH_4 §5.1 item 23.** `activePaletteProvider` and `themeModeProvider` shipped in
/// Phase 5 as bare `StateProvider`s with no `app_settings` backing, so a user's dark-mode choice was
/// lost on every restart. The audit recorded it as 8A's work rather than a Phase 5 defect; this is the
/// storage half of the fix.
///
/// Both parsers **fall back rather than throw**, for the reason Law L13 gives about enums in the
/// database: a settings row is user data, a later version may write a palette name this build has
/// never heard of, and a theme choice is not worth failing app startup over.
abstract final class AppearanceSettings {
  /// The `app_settings` key holding the chosen palette's name.
  static const String paletteKey = 'appearance.palette';

  /// The `app_settings` key holding the chosen theme mode.
  static const String themeModeKey = 'appearance.themeMode';

  /// The palette a fresh install uses.
  ///
  /// `AlayaPresets.activePreset` and not a name of its own, so ARCH_3 §8.1's promise that one constant
  /// switches the shipped look survives the arrival of a picker.
  static AlayaPalette get fallbackPalette => AlayaPresets.activePreset;

  /// The theme mode a fresh install uses.
  ///
  /// Following the system is the only defensible default: a finance app opened at midnight should not
  /// be the one bright thing on the phone, and nobody should have to choose before they have seen it.
  static const ThemeMode fallbackThemeMode = ThemeMode.system;

  /// Parses a stored palette name, falling back for anything this build cannot offer.
  static AlayaPalette parsePalette(String? stored) {
    for (final palette in AlayaPresets.all) {
      if (palette.name == stored) return palette;
    }
    return fallbackPalette;
  }

  /// The value written back for [palette].
  static String storedPalette(AlayaPalette palette) => palette.name;

  /// Parses a stored theme mode, falling back for anything unrecognised.
  static ThemeMode parseThemeMode(String? stored) {
    for (final mode in ThemeMode.values) {
      if (mode.name == stored) return mode;
    }
    return fallbackThemeMode;
  }

  /// The value written back for [mode].
  static String storedThemeMode(ThemeMode mode) => mode.name;
}
