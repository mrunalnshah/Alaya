import 'package:intl/intl.dart';

import 'fraction.dart';
import 'measure.dart';

/// Which question a rendered measure is answering.
///
/// The two exist because the answers genuinely differ, and conflating them is how a screen ends up
/// asserting something false. See [MeasureStyle.kitchen].
enum MeasureStyle {
  /// What the amount *is*.
  ///
  /// Renders a fraction when one would have stored as exactly this value, and a decimal otherwise. Used
  /// wherever the amount is the one the cook typed — the editor, and any row shown at the recipe's own
  /// serving count. Never approximates, so `RenderedMeasure.isApproximate` is always false.
  exact,

  /// What the cook should *reach for*.
  ///
  /// Snaps to [kMeasuringSet], so 222 thousandths of a cup reads as a quarter cup rather than as `2/9` —
  /// which is the honest fraction, and useless, because no drawer contains a ninth.
  ///
  /// **Only for a derived amount, and always marked.** Snapping means the text no longer equals the
  /// stored value, and a screen that showed the snapped figure as though it were the real one would be
  /// telling the same kind of lie the reminders screen told for months: internally consistent, plausible,
  /// and wrong. `RenderedMeasure.isApproximate` is how the caller knows to say so.
  kitchen,
}

/// A measure ready to display, and enough for the caller to be honest about it.
final class RenderedMeasure {
  /// Creates a rendered measure.
  const RenderedMeasure({
    required this.text,
    required this.whole,
    required this.fraction,
    required this.isApproximate,
    required this.measure,
  });

  /// What to show: `2`, `3/4`, `1 1/2`, or `0.137` when nothing simpler fits.
  final String text;

  /// The whole part, for a caller that wants to lay the two out separately.
  final int whole;

  /// The fractional part, or null when the amount is whole or has no simple fraction.
  final Fraction? fraction;

  /// True when [text] is not the stored amount.
  ///
  /// **The caller must show this**, conventionally as a leading `≈`. One character is the whole cost of
  /// not lying, and it appears only when snapping actually changed something — so at a recipe's own
  /// serving count no glyph appears anywhere, and the moment the servings dial moves it earns its place.
  final bool isApproximate;

  /// The value [text] describes. Equals the input under [MeasureStyle.exact]; the snapped value under
  /// [MeasureStyle.kitchen]. Kept so a caller can show the exact figure alongside, or in a tooltip.
  final Measure measure;
}

/// Renders a [Measure] the way a cook writes it.
///
/// **Replaces a nine-entry lookup table, and the table was the ceiling.** The previous renderer knew
/// `1/8` through `7/8` and rendered everything else as a decimal — so a chip list of five fractions was
/// never the real limit, and adding `1/16` to it would have produced `0.062` on screen. Recognition is
/// now derived: a fraction is offered when it round-trips, which needs no table and no additions.
///
/// **ASCII output, deliberately.** `1/2` rather than `½`. The vulgar-fraction characters are prettier and
/// a font that lacks one renders nothing at all — an amount that silently disappears is worse than an
/// amount that is merely plain, and this app ships one font family it does not control the coverage of.
/// `MeasureParser` accepts the glyphs on input, where the risk runs the other way.
final class MeasureFormatter {
  /// Creates a formatter. Stateless — safe to use as a `const` singleton.
  const MeasureFormatter({this.maxDenominator = 16});

  /// The finest gradation to offer as a fraction. See [fractionForMilli].
  final int maxDenominator;

  /// Renders [measure].
  ///
  /// [localeTag] affects only the decimal fallback's separator, matching `QtyFormatter`, because a
  /// fraction has no locale-dependent characters and the unit vocabulary is not this class's business.
  RenderedMeasure format(
    Measure measure, {
    MeasureStyle style = MeasureStyle.exact,
    String localeTag = 'en',
  }) {
    final target = style == MeasureStyle.kitchen
        ? measure.snapToMeasuringSet()
        : measure;
    final approximate = target != measure;

    if (target.isZero) {
      return RenderedMeasure(
        text: '0',
        whole: 0,
        fraction: null,
        isApproximate: approximate,
        measure: target,
      );
    }

    final fraction = fractionForMilli(
      target.remainderMilli,
      maxDenominator: maxDenominator,
    );

    // No fraction and a leftover: a real number that is not any simple fraction. `0.137` is the honest
    // rendering, and reaching for `2/15` to avoid a decimal would be inventing precision.
    if (fraction == null && !target.isWhole) {
      return RenderedMeasure(
        text: _decimal(target.milliOfUnit, localeTag),
        whole: target.whole,
        fraction: null,
        isApproximate: approximate,
        measure: target,
      );
    }

    final text = switch ((target.whole, fraction)) {
      (final whole, null) => '$whole',
      (0, final Fraction f) => '$f',
      (final whole, final Fraction f) => '$whole $f',
    };

    return RenderedMeasure(
      text: text,
      whole: target.whole,
      fraction: fraction,
      isApproximate: approximate,
      measure: target,
    );
  }

  /// The chips to offer for [current].
  ///
  /// **[kMeasuringSet] plus whatever is already set, which is how a custom fraction becomes a chip.**
  /// Somebody who types `5/16` gets a lit `5/16` chip they can tap to clear, without a "custom" button, a
  /// picker, or anything remembered between sessions. The set is the drawer plus the present tense.
  ///
  /// Returns the drawer alone when [current] has no fraction, or when its fraction is already in it.
  List<Fraction> chipsFor(Measure current) {
    final fraction = fractionForMilli(
      current.remainderMilli,
      maxDenominator: maxDenominator,
    );
    if (fraction == null || kMeasuringSet.contains(fraction)) {
      return kMeasuringSet;
    }
    return [...kMeasuringSet, fraction]..sort();
  }

  String _decimal(int milliOfUnit, String localeTag) {
    final format = NumberFormat.decimalPattern(localeTag)
      ..minimumFractionDigits = 0
      ..maximumFractionDigits = 3;
    // Constructed from integers and formatted immediately: the double exists for the length of this
    // expression and never reaches a stored value, which is the only place Law L1 permits one.
    return format.format(milliOfUnit / 1000);
  }
}
