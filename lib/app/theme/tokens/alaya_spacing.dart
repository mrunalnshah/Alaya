/// The spacing scale (ARCH_3 §8) — the only source of padding and gap values in the app.
///
/// Eight steps on a 4-point grid. A widget writing `EdgeInsets.all(13)` is a bug, not a preference:
/// once one exists, nothing keeps the next screen's rhythm consistent with this one.
///
/// The names are sizes rather than roles (`md`, not `cardPadding`) because a role-named scale
/// invites a ninth value the moment a role appears that does not fit — and then the grid is gone.
abstract final class AlayaSpacing {
  /// 4 — hairline separation, icon-to-label.
  static const double xxs = 4;

  /// 8 — inside a chip, between stacked labels.
  static const double xs = 8;

  /// 12 — between related rows.
  static const double sm = 12;

  /// 16 — the default. Card padding, screen margin.
  static const double md = 16;

  /// 20 — a slightly generous card.
  static const double lg = 20;

  /// 24 — between sections.
  static const double xl = 24;

  /// 32 — around a section header.
  static const double xxl = 32;

  /// 48 — empty-state breathing room, above a primary action.
  static const double xxxl = 48;

  /// The screen edge margin, named because it must not drift between screens.
  static const double screenEdge = md;

  /// The minimum tap target, per Material's accessibility floor.
  ///
  /// Not a spacing value so much as a constraint, but it belongs on the scale because every
  /// icon-button-sized widget in the app needs to reach it and there must be one number to reach.
  static const double minTapTarget = 48;
}
