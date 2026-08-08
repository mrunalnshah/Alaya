import 'package:intl/intl.dart';

import '../result/failure.dart';
import '../result/result.dart';
import 'qty.dart';
import 'unit_category.dart';

/// Parses user-typed quantity text into [Qty] — Law L2's counterpart to `MoneyParser`.
///
/// **No `double` is involved at any point.** The typed decimal is converted to milli-base units by
/// exact integer arithmetic, which is what L2 requires and what makes the precision rule honest: a
/// value finer than the chosen unit can represent is **rejected**, never silently rounded. That is
/// the whole difference from a `double.parse` followed by `.round()`, which turned `0.501` of a
/// factor-1 unit into a whole one and reported success.
///
/// Never throws. Every outcome, including a string the user is still halfway through typing, comes
/// back as a [Result] so the field can decide what to surface.
final class QtyParser {
  /// Creates a parser. Stateless — safe to use as a `const` singleton.
  const QtyParser();

  static const int _maxInputLength = 18;

  /// The largest quantity this parser will produce, in milli-base units.
  ///
  /// 1e15 milli-base is a thousand tonnes of a weight item. The cap exists to keep
  /// `magnitude × factorToBaseMilli` inside a 64-bit int rather than to express a domain rule, and
  /// it is checked *before* the multiplication for exactly that reason.
  static const int maxMilliBase = 1000000000000000;

  /// Parses [input] as a quantity in the unit whose factor is [factorToBaseMilli].
  ///
  /// [factorToBaseMilli] comes from the `units` row, so `kg` is 1000000, `g` is 1000 and `pc` is
  /// 1000. [localeTag] decides which characters are the decimal point and the grouping separator.
  /// Negative input is rejected unless [allowNegative]: a movement is a positive quantity plus a
  /// `kind`, so a negative quantity is a bug at almost every call site.
  ///
  /// A fractional value is accepted whenever the unit can express it exactly — `0.5` of a `pc`
  /// is 500 milli-base, which ARCH_1 §4.2 requires — and returns
  /// [ParseFailure.tooManyDecimalDigits] when it cannot.
  Result<Qty, ParseFailure> parse(
    String input, {
    required UnitCategory category,
    required int factorToBaseMilli,
    String localeTag = 'en',
    bool allowNegative = false,
  }) {
    if (factorToBaseMilli <= 0)
      return const Result.failure(ParseFailure.malformed);

    var text = input.trim();
    if (text.isEmpty) return const Result.failure(ParseFailure.empty);
    if (text.length > _maxInputLength)
      return const Result.failure(ParseFailure.tooLarge);

    var sign = 1;
    if (text.startsWith('-')) {
      if (!allowNegative)
        return const Result.failure(ParseFailure.negativeNotAllowed);
      sign = -1;
      text = text.substring(1);
    } else if (text.startsWith('+')) {
      text = text.substring(1);
    }
    if (text.isEmpty) return const Result.failure(ParseFailure.malformed);

    final symbols = NumberFormat.decimalPattern(localeTag).symbols;
    final groupSeparator = symbols.GROUP_SEP;
    final decimalSeparator = symbols.DECIMAL_SEP;

    if (groupSeparator.isNotEmpty) {
      text = text.replaceAll(groupSeparator, '');
    }
    if (text.isEmpty) return const Result.failure(ParseFailure.malformed);

    final parts = decimalSeparator.isEmpty
        ? [text]
        : text.split(decimalSeparator);
    if (parts.length > 2) return const Result.failure(ParseFailure.malformed);

    final wholePart = parts[0];
    final fractionPart = parts.length == 2 ? parts[1] : '';

    if (wholePart.isEmpty && fractionPart.isEmpty) {
      return const Result.failure(ParseFailure.malformed);
    }
    if (!_isDigitsOnly(wholePart) || !_isDigitsOnly(fractionPart)) {
      return const Result.failure(ParseFailure.invalidCharacter);
    }

    final digits = '${wholePart.isEmpty ? '0' : wholePart}$fractionPart';
    if (digits.length > _maxInputLength)
      return const Result.failure(ParseFailure.tooLarge);

    final magnitude = int.parse(digits);
    if (magnitude > maxMilliBase ~/ factorToBaseMilli) {
      return const Result.failure(ParseFailure.tooLarge);
    }

    final scaled = magnitude * factorToBaseMilli;
    final divisor = _pow10(fractionPart.length);
    if (scaled % divisor != 0) {
      return const Result.failure(ParseFailure.tooManyDecimalDigits);
    }

    return Result.ok(Qty(sign * (scaled ~/ divisor), category));
  }

  /// Renders [qty] as plain editable digits in the unit whose factor is [factorToBaseMilli].
  ///
  /// The inverse of [parse] for a text field's initial value: plain digits with a decimal point and
  /// no grouping separators, because separators in an editable field fight the cursor.
  ///
  /// Integer arithmetic throughout, and it **truncates** at [maxFractionDigits] rather than
  /// rounding. Truncation matters because this text is what the user then edits: rounding up would
  /// let a save commit a larger quantity than the one stored, which nobody typed. A unit whose
  /// factor is not a power of ten (`dozen` is 12000) can hold values with no terminating decimal, so
  /// a bound is unavoidable.
  String format(
    Qty qty, {
    required int factorToBaseMilli,
    int maxFractionDigits = 6,
  }) {
    if (factorToBaseMilli <= 0) return '';
    final negative = qty.isNegative;
    final magnitude = negative ? -qty.milliBase : qty.milliBase;
    final sign = negative ? '-' : '';
    final whole = magnitude ~/ factorToBaseMilli;
    final remainder = magnitude % factorToBaseMilli;
    if (remainder == 0) return '$sign$whole';

    final scaled = remainder * _pow10(maxFractionDigits) ~/ factorToBaseMilli;
    var fraction = scaled.toString().padLeft(maxFractionDigits, '0');
    while (fraction.endsWith('0')) {
      fraction = fraction.substring(0, fraction.length - 1);
    }
    return fraction.isEmpty ? '$sign$whole' : '$sign$whole.$fraction';
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  static bool _isDigitsOnly(String value) {
    for (final codeUnit in value.codeUnits) {
      if (codeUnit < 0x30 || codeUnit > 0x39) return false;
    }
    return true;
  }
}
