/// Strategies for rounding a fractional minor-unit amount to an integer. Used only at the
/// single sanctioned rounding boundary in the app, [Money.convert] — nowhere else rounds
/// money (Law L1's spirit: the stored and returned amounts are always exact integers; only
/// a currency conversion, which multiplies by an inherently inexact market rate, ever needs
/// to round the result back down to one).
enum MoneyRounding {
  /// Rounds half away from zero (`2.5 → 3`, `-2.5 → -3`). The "school rounding" most people
  /// expect, and this app's default.
  halfUp,

  /// Rounds half toward zero (`2.5 → 2`, `-2.5 → -2`).
  halfDown,

  /// Rounds half to the nearest even integer (banker's rounding; `2.5 → 2`, `3.5 → 4`).
  halfEven,

  /// Always rounds toward positive infinity.
  ceiling,

  /// Always rounds toward negative infinity.
  floor;

  /// Rounds [value] to the nearest integer per this strategy.
  int apply(double value) => switch (this) {
    MoneyRounding.ceiling => value.ceil(),
    MoneyRounding.floor => value.floor(),
    MoneyRounding.halfUp =>
    value.isNegative ? -_halfUpMagnitude(-value) : _halfUpMagnitude(value),
    MoneyRounding.halfDown =>
    value.isNegative ? -_halfDownMagnitude(-value) : _halfDownMagnitude(value),
    MoneyRounding.halfEven => _halfEven(value),
  };

  static int _halfUpMagnitude(double magnitude) => (magnitude + 0.5).floor();

  static int _halfDownMagnitude(double magnitude) {
    final flooredValue = magnitude.floor();
    final fraction = magnitude - flooredValue;
    return fraction > 0.5 ? flooredValue + 1 : flooredValue;
  }

  static int _halfEven(double value) {
    final flooredValue = value.floor();
    final fraction = value - flooredValue;
    if (fraction < 0.5) return flooredValue;
    if (fraction > 0.5) return flooredValue + 1;
    return flooredValue.isEven ? flooredValue : flooredValue + 1;
  }
}