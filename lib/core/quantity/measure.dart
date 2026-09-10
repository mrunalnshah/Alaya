import 'fraction.dart';
import 'qty.dart';
import 'unit_category.dart';

/// An amount expressed in thousandths of some chosen unit — half a tablespoon, two thirds of a cup.
///
/// **The missing middle of the recipe module.** A [Qty] is canonical and unit-free: half a tablespoon is
/// `Qty(7393, volume)`, which is correct, comparable, and unable to say what the cook wrote. The unit
/// they chose is stored separately, and until this type existed there was nothing that held the two
/// together — so the editor kept the pairing in local widget state and the detail screen, having no
/// pairing to read, rendered `7 ml` for a line that said half a tablespoon.
///
/// **Thousandths rather than a [Fraction], and the choice is load-bearing.** A fraction is exact but
/// only closed under multiplication by other fractions; the moment servings scale an amount by 2/3 and
/// the engine takes a ceiling, the result is not a fraction of anything in a drawer. Thousandths absorb
/// that — every arithmetic result is representable, and `MeasureFormatter` decides afterwards whether
/// what came out can be *called* a fraction. Representation stays total; presentation does the judging.
///
/// **No unit lives here.** `Unit` is a domain entity and `B1_CORE` depends on nothing (Law L12), so
/// every conversion takes the raw `factorToBaseMilli` from the `units` row. That is not a workaround —
/// it is what keeps this arithmetic testable with three integer literals and no database.
final class Measure implements Comparable<Measure> {
  /// Creates a measure of [milliOfUnit] thousandths of a unit. `1500` is one and a half.
  const Measure(this.milliOfUnit);

  /// Nothing.
  const Measure.zero() : milliOfUnit = 0;

  /// [whole] units plus [fraction] of one.
  ///
  /// The shape a cook dictates: a number, then a fraction. "3 1/2 tablespoons" is three tablespoons and
  /// then the half, which is literally the sequence of actions at the counter.
  factory Measure.of(int whole, [Fraction? fraction]) =>
      Measure(whole * 1000 + (fraction?.milliOfUnit ?? 0));

  /// Re-expresses [quantity] in the unit whose factor is [factorToBaseMilli].
  ///
  /// **Rounded, not truncated** (ARCH_M §7). Half a tablespoon is 7393.5 milli-millilitres; truncating
  /// on the way back gives 499 rather than 500, so the field showed `0.499` and the fraction chip never
  /// lit. That bug was reported as a missing feature.
  factory Measure.fromQty(Qty quantity, {required int factorToBaseMilli}) {
    if (factorToBaseMilli <= 0) {
      throw ArgumentError.value(
        factorToBaseMilli,
        'factorToBaseMilli',
        'must be positive',
      );
    }
    return Measure(roundDiv(quantity.milliBase * 1000, factorToBaseMilli));
  }

  /// Thousandths of the chosen unit.
  final int milliOfUnit;

  /// The whole part — the `3` in `3 1/2`.
  int get whole => milliOfUnit ~/ 1000;

  /// The leftover thousandths — the `500` in `3 1/2`.
  int get remainderMilli => milliOfUnit % 1000;

  /// True when there is nothing to measure.
  bool get isZero => milliOfUnit <= 0;

  /// True when this is a whole number of units, with nothing left over.
  bool get isWhole => remainderMilli == 0;

  /// Converts to the canonical [Qty] the engine and the database use.
  ///
  /// Rounded in this direction too, so [Measure.fromQty] undoes it. That round trip is exact for every
  /// unit whose factor is at least 1000 — which is every unit in the seed, the smallest being `mg` at 1
  /// and every vessel being far larger: `tsp` 4929, `tbsp` 14787, `cup` 240000.
  Qty toQty({
    required int factorToBaseMilli,
    required UnitCategory category,
  }) => Qty(roundDiv(milliOfUnit * factorToBaseMilli, 1000), category);

  /// The nearest amount a measuring set can produce, carrying a full unit if the snap reaches one.
  ///
  /// **For a derived amount only.** At a recipe's own serving count an amount is what the cook typed and
  /// needs no snapping; it is scaling that produces 222 thousandths of a cup, which is a real number and
  /// not a thing anybody owns a scoop for. `MeasureFormatter` is what decides when to call this, and it
  /// marks the result so the screen never claims a snapped amount is the stored one.
  Measure snapToMeasuringSet() {
    final snapped = snapRemainderToMeasuringSet(remainderMilli);
    if (!snapped.changed) return this;
    return Measure(whole * 1000 + snapped.milli);
  }

  /// A copy with the whole part replaced, keeping the fraction.
  ///
  /// Clearing the number keeps the fraction, because "1/2 tsp" is a real amount and deleting the zero in
  /// front of it should not delete the half as well.
  Measure withWhole(int value) => Measure(value * 1000 + remainderMilli);

  /// A copy with the fraction replaced, keeping the whole part.
  ///
  /// Passing null clears the fraction, so `3 1/2` and `3` are one tap apart in both directions.
  Measure withFraction(Fraction? fraction) =>
      Measure(whole * 1000 + (fraction?.milliOfUnit ?? 0));

  /// This measure scaled from [fromServings] to [toServings].
  ///
  /// **Delegates the direction to the engine's rule rather than restating it.** `CookabilityEngine`
  /// takes a ceiling because a false "you have enough" ruins dinner. A display that rounded the other
  /// way would show less than the verdict demands, and the two disagreeing about the same recipe is the
  /// class of bug this whole type exists to close — so this rounds up too, and the arithmetic is here
  /// only because `B1_CORE` cannot import a domain service.
  Measure scaled({required int fromServings, required int toServings}) {
    if (fromServings <= 0) {
      throw ArgumentError.value(
        fromServings,
        'fromServings',
        'must be positive',
      );
    }
    if (toServings == fromServings) return this;
    final numerator = milliOfUnit * toServings;
    return Measure((numerator + fromServings - 1) ~/ fromServings);
  }

  @override
  int compareTo(Measure other) => milliOfUnit.compareTo(other.milliOfUnit);

  @override
  bool operator ==(Object other) =>
      other is Measure && other.milliOfUnit == milliOfUnit;

  @override
  int get hashCode => milliOfUnit.hashCode;

  /// Debug only. Never show this to anybody — use `MeasureFormatter`.
  @override
  String toString() => '${milliOfUnit}m/unit';
}
