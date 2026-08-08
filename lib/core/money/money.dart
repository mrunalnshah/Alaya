import 'dart:math' as math;

import 'rounding.dart';

/// An exact monetary amount: integer minor units (e.g. paise, cents) plus a currency code.
/// Never backed by a `double` (Law L1). This type deliberately does not know how many
/// decimal digits its own currency uses — that comes from the `currencies` table at the
/// call site (never hardcode `100`; see ARCH_1 §4.1) — so every operation that needs to
/// interpret [minor] as a decimal amount takes `decimalDigits` as an explicit parameter.
final class Money implements Comparable<Money> {
  /// Creates a [Money] directly from already-computed minor units. Prefer [MoneyParser] to
  /// build one from user-typed text.
  const Money(this.minor, this.currencyCode);

  /// A zero amount in [currencyCode].
  const Money.zero(String currencyCode) : this(0, currencyCode);

  /// The amount in minor units (e.g. paise, cents). Always a whole number.
  final int minor;

  /// The currency code, e.g. `'INR'`. Matches a row in the `currencies` table.
  final String currencyCode;

  /// True if [minor] is less than zero.
  bool get isNegative => minor < 0;

  /// True if [minor] is greater than zero.
  bool get isPositive => minor > 0;

  /// True if [minor] is exactly zero.
  bool get isZero => minor == 0;

  /// Adds [other]. Throws [CurrencyMismatchError] if the currencies differ.
  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(minor + other.minor, currencyCode);
  }

  /// Subtracts [other]. Throws [CurrencyMismatchError] if the currencies differ.
  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(minor - other.minor, currencyCode);
  }

  /// Scales this amount by the integer [factor].
  Money operator *(int factor) => Money(minor * factor, currencyCode);

  /// The negation of this amount, in the same currency.
  Money operator -() => Money(-minor, currencyCode);

  /// The absolute value of this amount, in the same currency.
  Money abs() => isNegative ? -this : this;

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return minor.compareTo(other.minor);
  }

  /// True if this amount is strictly less than [other]. Throws [CurrencyMismatchError] if
  /// the currencies differ.
  bool operator <(Money other) {
    _assertSameCurrency(other);
    return minor < other.minor;
  }

  /// True if this amount is less than or equal to [other]. Throws [CurrencyMismatchError]
  /// if the currencies differ.
  bool operator <=(Money other) {
    _assertSameCurrency(other);
    return minor <= other.minor;
  }

  /// True if this amount is strictly greater than [other]. Throws [CurrencyMismatchError]
  /// if the currencies differ.
  bool operator >(Money other) {
    _assertSameCurrency(other);
    return minor > other.minor;
  }

  /// True if this amount is greater than or equal to [other]. Throws [CurrencyMismatchError]
  /// if the currencies differ.
  bool operator >=(Money other) {
    _assertSameCurrency(other);
    return minor >= other.minor;
  }

  /// Converts this amount into [toCurrencyCode] using [rate] (units of [toCurrencyCode] per
  /// 1 unit of this currency), accounting for each currency's own decimal precision. This is
  /// the one sanctioned place in the app that rounds money; [rounding] defaults to
  /// [MoneyRounding.halfUp]. The result is a frozen, independent [Money] — this call never
  /// mutates `this` (Law L9: the original amount is immutable).
  Money convert({
    required double rate,
    required String toCurrencyCode,
    required int fromDecimalDigits,
    required int toDecimalDigits,
    MoneyRounding rounding = MoneyRounding.halfUp,
  }) {
    final scale = math.pow(10, toDecimalDigits - fromDecimalDigits).toDouble();
    final rawValue = minor * rate * scale;
    return Money(rounding.apply(rawValue), toCurrencyCode);
  }

  void _assertSameCurrency(Money other) {
    if (other.currencyCode != currencyCode) {
      throw CurrencyMismatchError(currencyCode, other.currencyCode);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(minor, currencyCode);

  /// A debug-only representation, e.g. `INR 12345mu`. Never use this for UI display — use
  /// [MoneyFormatter] instead.
  @override
  String toString() => '$currencyCode ${minor}mu';
}

/// Thrown when an operation combines two [Money] values in different currencies. There is
/// no implicit conversion anywhere in this type — indicates a programming error, not a
/// recoverable user-facing condition.
final class CurrencyMismatchError extends Error {
  /// Records the two currency codes that could not be combined.
  CurrencyMismatchError(this.first, this.second);

  /// The currency code of the left-hand operand.
  final String first;

  /// The currency code of the right-hand operand.
  final String second;

  @override
  String toString() => 'CurrencyMismatchError: cannot combine $first with $second directly '
      '— convert explicitly first.';
}