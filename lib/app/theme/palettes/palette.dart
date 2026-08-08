import 'package:flutter/widgets.dart';

/// A complete palette as **data**, which is the whole point of ARCH_3 §8.
///
/// Every colour the app can render is a field here. Nothing is computed from a seed and nothing is
/// derived at use time, because both make "change the palette later, easily" false: a seeded scheme
/// means you cannot adjust one colour without moving others, and a derived colour means the value
/// you see on screen exists in no file you can edit.
///
/// A preset supplies light **and** dark in one object rather than two, so a half-migrated palette —
/// light updated, dark forgotten — cannot compile.
@immutable
class AlayaPalette {
  /// Creates a palette.
  const AlayaPalette({
    required this.name,
    required this.description,
    required this.light,
    required this.dark,
  });

  /// The identifier shown in Settings and the Theme Lab.
  final String name;

  /// One line on what this palette is for — read by a human choosing between them.
  final String description;

  /// The light-mode colours.
  final AlayaColorSet light;

  /// The dark-mode colours.
  final AlayaColorSet dark;

  /// The set for [isDark].
  AlayaColorSet forMode({required bool isDark}) => isDark ? dark : light;
}

/// One mode's complete colour set.
///
/// The four surface tiers are the structural idea. Rather than one background colour plus shadows,
/// depth is expressed by stepping through tiers — which is what makes dark mode legible, since a
/// shadow on a near-black surface conveys nothing.
@immutable
class AlayaColorSet {
  /// Creates a colour set.
  const AlayaColorSet({
    required this.surfaceBase,
    required this.surfaceRaised,
    required this.surfaceOverlay,
    required this.surfaceSunken,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.onAccent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.divider,
    required this.income,
    required this.expense,
    required this.transfer,
    required this.warning,
    required this.danger,
    required this.success,
    required this.onStatus,
  });

  /// Tier 0 — the screen behind everything.
  final Color surfaceBase;

  /// Tier 1 — a card sitting on the base.
  final Color surfaceRaised;

  /// Tier 2 — a sheet, dialog or menu above a card.
  final Color surfaceOverlay;

  /// Tier -1 — an inset well: a text field's fill, a disabled row, a chart's plot area.
  ///
  /// Below the base rather than above it, which is why it is not simply "tier 3". An input needs to
  /// read as a hole you type into, not a card you might tap.
  final Color surfaceSunken;

  /// The brand colour. App bar accents, selected states, the primary button.
  final Color primary;

  /// Text and icons on [primary].
  final Color onPrimary;

  /// The interactive accent, used sparingly — the FAB, a focused field's border.
  ///
  /// Separate from [primary] so that "the brand" and "the thing you tap" can differ. When they are
  /// the same colour, every branded surface looks tappable.
  final Color accent;

  /// Text and icons on [accent].
  final Color onAccent;

  /// Primary reading colour.
  final Color textPrimary;

  /// Supporting text — an account name beneath a payee.
  final Color textSecondary;

  /// De-emphasised text — a timestamp, a disabled label, placeholder text.
  final Color textMuted;

  /// Hairlines and borders.
  final Color divider;

  /// Money arriving.
  final Color income;

  /// Money leaving.
  final Color expense;

  /// Money moving between the user's own accounts — neither a gain nor a loss.
  final Color transfer;

  /// Something needs attention soon.
  final Color warning;

  /// Something is wrong or overdue.
  final Color danger;

  /// Something completed.
  final Color success;

  /// Text and icons on any of [warning], [danger] or [success] used as a fill.
  final Color onStatus;
}
