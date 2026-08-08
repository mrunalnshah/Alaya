import 'package:flutter/widgets.dart';

/// The corner-radius scale (ARCH_3 §8).
///
/// Four steps, deliberately shallow. A finance app is read in columns, and a heavily rounded card
/// fights the vertical alignment that makes a column of amounts scannable — so the radius is enough
/// to soften a surface and not enough to make it feel like a separate object floating away.
abstract final class AlayaRadii {
  /// 4 — chips, tags, small inline surfaces.
  static const double xs = 4;

  /// 8 — inputs, buttons.
  static const double sm = 8;

  /// 12 — cards, sheets' inner surfaces. The default.
  static const double md = 12;

  /// 20 — bottom sheets and dialogs, where the corner is a large visible arc.
  static const double lg = 20;

  /// A fully round shape, for avatars and the expandable FAB's collapsed state.
  static const double full = 999;

  /// [xs] as a [BorderRadius].
  static const BorderRadius borderXs = BorderRadius.all(Radius.circular(xs));

  /// [sm] as a [BorderRadius].
  static const BorderRadius borderSm = BorderRadius.all(Radius.circular(sm));

  /// [md] as a [BorderRadius].
  static const BorderRadius borderMd = BorderRadius.all(Radius.circular(md));

  /// [lg] as a [BorderRadius].
  static const BorderRadius borderLg = BorderRadius.all(Radius.circular(lg));

  /// A sheet's top-only radius, since its bottom edge meets the screen.
  static const BorderRadius sheetTop = BorderRadius.only(
    topLeft: Radius.circular(lg),
    topRight: Radius.circular(lg),
  );
}
