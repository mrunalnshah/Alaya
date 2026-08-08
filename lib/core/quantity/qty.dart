import 'unit_category.dart';

/// An exact physical quantity: integer milli-base-units (the category's base unit × 1000)
/// plus a [UnitCategory]. Never backed by a `double` (Law L2). The ×1000 scale exists so a
/// half-piece or a fraction-of-a-gram spice measurement is still an exact integer — plain
/// base units would satisfy every whole-number example and then fail the first time someone
/// records `0.5 pc` or `0.25 g`. Arithmetic across categories throws
/// [UnitCategoryMismatchError] (Law L8) — there is no gram↔millilitre conversion.
final class Qty implements Comparable<Qty> {
  /// Creates a [Qty] directly from already-computed milli-base-units.
  const Qty(this.milliBase, this.category);

  /// A zero quantity in [category].
  const Qty.zero(UnitCategory category) : this(0, category);

  /// The quantity in milli-base-units, e.g. milli-grams-of-the-base-gram for weight.
  final int milliBase;

  /// Which of the three fixed categories this quantity belongs to.
  final UnitCategory category;

  /// True if [milliBase] is less than zero.
  bool get isNegative => milliBase < 0;

  /// True if [milliBase] is greater than zero.
  bool get isPositive => milliBase > 0;

  /// True if [milliBase] is exactly zero.
  bool get isZero => milliBase == 0;

  /// Adds [other]. Throws [UnitCategoryMismatchError] if the categories differ.
  Qty operator +(Qty other) {
    _assertSameCategory(other);
    return Qty(milliBase + other.milliBase, category);
  }

  /// Subtracts [other]. Throws [UnitCategoryMismatchError] if the categories differ.
  Qty operator -(Qty other) {
    _assertSameCategory(other);
    return Qty(milliBase - other.milliBase, category);
  }

  /// Scales this quantity by the integer [factor].
  Qty operator *(int factor) => Qty(milliBase * factor, category);

  /// The negation of this quantity, in the same category.
  Qty operator -() => Qty(-milliBase, category);

  @override
  int compareTo(Qty other) {
    _assertSameCategory(other);
    return milliBase.compareTo(other.milliBase);
  }

  /// True if this quantity is strictly less than [other]. Throws [UnitCategoryMismatchError]
  /// if the categories differ.
  bool operator <(Qty other) {
    _assertSameCategory(other);
    return milliBase < other.milliBase;
  }

  /// True if this quantity is less than or equal to [other]. Throws
  /// [UnitCategoryMismatchError] if the categories differ.
  bool operator <=(Qty other) {
    _assertSameCategory(other);
    return milliBase <= other.milliBase;
  }

  /// True if this quantity is strictly greater than [other]. Throws
  /// [UnitCategoryMismatchError] if the categories differ.
  bool operator >(Qty other) {
    _assertSameCategory(other);
    return milliBase > other.milliBase;
  }

  /// True if this quantity is greater than or equal to [other]. Throws
  /// [UnitCategoryMismatchError] if the categories differ.
  bool operator >=(Qty other) {
    _assertSameCategory(other);
    return milliBase >= other.milliBase;
  }

  void _assertSameCategory(Qty other) {
    if (other.category != category) {
      throw UnitCategoryMismatchError(category, other.category);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Qty && other.milliBase == milliBase && other.category == category;

  @override
  int get hashCode => Object.hash(milliBase, category);

  /// A debug-only representation, e.g. `2500000m(weight)`. Never use this for UI display —
  /// use [QtyFormatter] instead.
  @override
  String toString() => '${milliBase}m(${category.name})';
}

/// Thrown when an operation combines two [Qty] values from different [UnitCategory]s. There
/// is no gram↔millilitre conversion anywhere in this type — indicates a programming error,
/// not a recoverable user-facing condition.
final class UnitCategoryMismatchError extends Error {
  /// Records the two categories that could not be combined.
  UnitCategoryMismatchError(this.first, this.second);

  /// The category of the left-hand operand.
  final UnitCategory first;

  /// The category of the right-hand operand.
  final UnitCategory second;

  @override
  String toString() =>
      'UnitCategoryMismatchError: cannot combine ${first.name} with ${second.name}.';
}