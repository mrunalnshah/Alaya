/// The icon size scale (ARCH_5 §2.7) — the last literal class the token rules did not cover.
///
/// Phase 5 shipped 18, 20, 22 and 40 as raw numbers across six files (ARCH_4 A52). Four steps is
/// enough for every icon in the app, and having exactly four is what stops a fifth appearing.
abstract final class AlayaIconSize {
  /// 16 — inline with `caption` or `overline` text: a chip's dismiss, a status glyph.
  static const double sm = 16;

  /// 20 — the default. List-row leading icons, field affixes, app-bar actions.
  static const double md = 20;

  /// 24 — a primary action's icon, a FAB, a drawer destination.
  static const double lg = 24;

  /// 40 — the single illustrative icon on an empty or error state.
  static const double xl = 40;
}
