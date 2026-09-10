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

  /// Splits this amount into parts proportional to [weights], losing nothing.
  ///
  /// **The parts always sum to exactly this amount.** That guarantee is the entire point:
  /// ₹1,000 shared three ways is not ₹333.33 three times, and an app that shows three equal
  /// thirds has quietly lost two paise that somebody is owed. Here it is
  /// `[₹333.34, ₹333.33, ₹333.33]`, and the sum is ₹1,000.
  ///
  /// **This is not a second rounding site.** [convert] documents itself as the one sanctioned
  /// place that rounds money, and that stays true: nothing here is rounded. Allocation
  /// *distributes* an exact integer across parts by the largest-remainder method — every minor
  /// unit of the input lands in exactly one part, and none is created or discarded. There is no
  /// [MoneyRounding] parameter because there is no rounding decision to make.
  ///
  /// The leftover units go to the parts with the largest fractional remainders, ties broken by
  /// position, so the same weights always produce the same answer. Determinism matters more than
  /// it looks: a split shown to a user and the same split recomputed on the next screen must
  /// assign the stray paise to the same person, or the two screens disagree about who owes what.
  ///
  /// A weight of `0` yields exactly `Money.zero` and **never** receives a leftover unit — the
  /// guest who did not eat pays nothing. That holds because the leftover count is always strictly
  /// less than the number of parts with a non-zero remainder, so the sort never reaches a zero.
  ///
  /// Negative amounts are allocated by magnitude and then negated, so splitting a refund behaves
  /// as splitting a charge does.
  ///
  /// Throws [ArgumentError] when [weights] is empty, contains a negative, or sums to zero — each
  /// is a programming error rather than a state a user can reach.
  List<Money> allocate(List<int> weights) {
    if (weights.isEmpty) {
      throw ArgumentError.value(weights, 'weights', 'must not be empty');
    }
    var totalWeight = 0;
    for (final weight in weights) {
      if (weight < 0) {
        throw ArgumentError.value(weight, 'weights', 'must not be negative');
      }
      totalWeight += weight;
    }
    if (totalWeight == 0) {
      throw ArgumentError.value(
        weights,
        'weights',
        'must not all be zero — there would be nothing to allocate against',
      );
    }

    // Allocated by magnitude, then re-signed. A refund split behaves as a charge split, and the
    // largest-remainder comparison stays a comparison of positive fractions.
    final negative = isNegative;
    final magnitude = negative ? -minor : minor;

    final parts = List<int>.filled(weights.length, 0);
    final remainders = List<int>.filled(weights.length, 0);
    var distributed = 0;
    for (var i = 0; i < weights.length; i++) {
      // Multiply before dividing so the integer division loses nothing recoverable (Law L1).
      // 64-bit headroom is ample: the largest realistic amount times the largest basis-point
      // weight is around 1e16, against a ceiling near 9.2e18.
      final numerator = magnitude * weights[i];
      parts[i] = numerator ~/ totalWeight;
      remainders[i] = numerator % totalWeight;
      distributed += parts[i];
    }

    // Each part lost strictly less than one unit to truncation, so the leftover is at least zero
    // and strictly less than the number of parts. It therefore always fits inside [order].
    final leftover = magnitude - distributed;
    assert(
      leftover >= 0 && leftover < weights.length,
      'largest-remainder leftover out of range: $leftover for ${weights.length} parts',
    );

    final order = List<int>.generate(weights.length, (i) => i)
      ..sort((a, b) {
        final byRemainder = remainders[b].compareTo(remainders[a]);
        return byRemainder != 0 ? byRemainder : a.compareTo(b);
      });
    for (var given = 0; given < leftover; given++) {
      parts[order[given]] += 1;
    }

    return [
      for (final part in parts) Money(negative ? -part : part, currencyCode),
    ];
  }

  /// Splits this amount into [parts] equal shares, losing nothing.
  ///
  /// Shorthand for [allocate] with equal weights, and it carries the same guarantee: the shares
  /// sum to exactly this amount, with the leftover units going to the earliest parts.
  ///
  /// Throws [ArgumentError] when [parts] is not positive.
  List<Money> allocateEvenly(int parts) {
    if (parts <= 0) {
      throw ArgumentError.value(parts, 'parts', 'must be greater than zero');
    }
    return allocate(List<int>.filled(parts, 1));
  }

  void _assertSameCurrency(Money other) {
    if (other.currencyCode != currencyCode) {
      throw CurrencyMismatchError(currencyCode, other.currencyCode);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minor == minor &&
      other.currencyCode == currencyCode;

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
  String toString() =>
      'CurrencyMismatchError: cannot combine $first with $second directly '
      '— convert explicitly first.';
}
