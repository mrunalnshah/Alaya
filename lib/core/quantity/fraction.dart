/// Exact fractions, and the vocabulary a kitchen drawer actually contains.
library;

/// An exact, reduced, non-negative fraction.
///
/// **A separate type from a `double` because Law L1 has no doubles anywhere.** A fraction here is two
/// integers and stays two integers; the only place it becomes an approximation is [milliOfUnit], where
/// it is quantised to thousandths on purpose and the quantisation is the thing this file exists to make
/// visible rather than to hide.
final class Fraction implements Comparable<Fraction> {
  /// A fraction that is already reduced. Library-private so no unreduced instance can exist.
  const Fraction._(this.numerator, this.denominator);

  /// Creates the reduced form of `numerator / denominator`.
  ///
  /// Reduces, so `Fraction(2, 4)` and `Fraction(1, 2)` are the same value and compare equal — which
  /// matters because the approximation search below finds `2/4` before it would find `1/2` for some
  /// inputs, and a reader shown "2/4 cup" would rightly wonder what the app was doing.
  factory Fraction(int numerator, int denominator) {
    if (denominator <= 0) {
      throw ArgumentError.value(denominator, 'denominator', 'must be positive');
    }
    if (numerator < 0) {
      throw ArgumentError.value(numerator, 'numerator', 'must not be negative');
    }
    if (numerator == 0) return zero;
    final divisor = _gcd(numerator, denominator);
    return Fraction._(numerator ~/ divisor, denominator ~/ divisor);
  }

  /// Zero, as `0/1`.
  static const Fraction zero = Fraction._(0, 1);

  /// One, as `1/1`.
  static const Fraction one = Fraction._(1, 1);

  /// The top of the fraction.
  final int numerator;

  /// The bottom of the fraction. Always positive, always coprime with [numerator].
  final int denominator;

  /// True when this is exactly zero.
  bool get isZero => numerator == 0;

  /// True when this is a whole number — `1/1`, `2/1`.
  bool get isWhole => denominator == 1;

  /// This fraction in thousandths, rounded half up.
  ///
  /// **The lossy step, and it is deliberate.** A thousandth of a teaspoon is five thousandths of a
  /// millilitre, which no kitchen can measure, so quantising here costs nothing real and buys integer
  /// arithmetic end to end. `1/3` becomes 333 and `1/16` becomes 63; both round-trip back to the same
  /// fraction through [fractionForMilli], which is the property that matters.
  int get milliOfUnit => roundDiv(numerator * 1000, denominator);

  @override
  int compareTo(Fraction other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);

  @override
  bool operator ==(Object other) =>
      other is Fraction &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  /// `1/2`, `3/4`. ASCII on purpose — see `MeasureFormatter` for why output is not `½`.
  @override
  String toString() => '$numerator/$denominator';

  static int _gcd(int a, int b) {
    var x = a;
    var y = b;
    while (y != 0) {
      final next = x % y;
      x = y;
      y = next;
    }
    return x == 0 ? 1 : x;
  }
}

/// Integer division rounded half up. Positive operands only.
///
/// **Half up, never truncating.** ARCH_M §7 records the failure this prevents: half a tablespoon is
/// 7393.5 milli-millilitres, and truncating on the way back gave 499 rather than 500 — so a field
/// showed `0.499` and a chip never lit. Every division in this file and in `Measure` goes through here
/// so there is one rounding rule rather than one per call site.
int roundDiv(int numerator, int denominator) =>
    (numerator + denominator ~/ 2) ~/ denominator;

/// The fractions a measuring set can actually produce.
///
/// **A human fact, not a derivable one.** It cannot be computed from the `units` table: a tablespoon's
/// factor of 14787 is divisible by 3 and not by 2, which would offer thirds and refuse halves — the
/// opposite of what is in the drawer. So this is a stated list, and stating it is more honest than
/// deriving something plausible from the wrong input.
///
/// Six, being the union of a spoon set (quarter, half) and a cup set (quarter, third, half, two
/// thirds, three quarters), plus the eighth that a half-of-a-quarter teaspoon gives you. Eighths like
/// `3/8` are reachable by typing and deliberately not offered here: "5/8 cup" is a worse sentence than
/// "2/3 cup" and a cook reading it has to think.
const List<Fraction> kMeasuringSet = [
  Fraction._(1, 8),
  Fraction._(1, 4),
  Fraction._(1, 3),
  Fraction._(1, 2),
  Fraction._(2, 3),
  Fraction._(3, 4),
];

/// The simplest fraction that would have been stored as exactly [milli] thousandths.
///
/// **The round trip is the acceptance test, and that is the whole idea.** Rather than a table of known
/// thousandths — the previous approach, which held nine entries and rendered anything else as a decimal
/// — a candidate `p/q` is accepted if and only if `Fraction(p, q).milliOfUnit == milli`. So the question
/// "is this a fraction?" becomes "could this have come from one?", which is exactly the property a user
/// cares about: they typed `2/3`, and `2/3` is what they should be shown.
///
/// Denominators are tried in ascending order, so the first match is the simplest: `500` returns `1/2`
/// rather than `2/4`, and `250` returns `1/4` rather than `3/12`.
///
/// [milli] must be a remainder — strictly between 0 and 1000. Whole parts are [Measure]'s business.
/// Returns null when nothing within [maxDenominator] round-trips, and a null is a real answer: `137`
/// thousandths is not any simple fraction, and rendering it as `2/15` would be a worse lie than
/// rendering it as `0.137`.
///
/// [maxDenominator] defaults to 16 because that is the finest gradation any kitchen tool has. Above it
/// the answers stop being useful before they stop being correct — nobody owns a nineteenth of a cup.
Fraction? fractionForMilli(int milli, {int maxDenominator = 16}) {
  if (milli <= 0 || milli >= 1000) return null;
  for (var denominator = 2; denominator <= maxDenominator; denominator++) {
    final numerator = roundDiv(milli * denominator, 1000);
    if (numerator <= 0 || numerator >= denominator) continue;
    if (roundDiv(numerator * 1000, denominator) != milli) continue;
    return Fraction(numerator, denominator);
  }
  return null;
}

/// The nearest thousandths value a measuring set can produce, and whether snapping changed anything.
///
/// **Ties round up**, matching `CookabilityEngine.scaleMilli`'s direction and for the same reason it
/// gives: overstating an amount is a shrug and understating one ruins the dish. A cook told to use a
/// little more flour adds a little more flour.
///
/// [milli] must be a remainder — strictly between 0 and 1000 — or zero. A snap to 1000 means the
/// remainder became a whole unit, and the caller carries it.
({int milli, bool changed}) snapRemainderToMeasuringSet(int milli) {
  if (milli <= 0) return (milli: 0, changed: false);
  var best = 0;
  var bestDistance = milli;
  for (final candidate in [
    0,
    for (final fraction in kMeasuringSet) fraction.milliOfUnit,
    1000,
  ]) {
    final distance = (candidate - milli).abs();
    // `<=` rather than `<`, so a tie is won by the later — and therefore larger — candidate.
    if (distance <= bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return (milli: best, changed: best != milli);
}
