import 'package:intl/intl.dart';

import '../result/failure.dart';
import '../result/result.dart';

/// Converts between a user-typed decimal quantity in some unit and the canonical integer
/// milliBase representation, using only integer arithmetic (Law L2). Unlike a currency's
/// exchange rate, a unit's `factorToBaseMilli` is always exact (e.g. `1 kg = 1_000_000`
/// milliBase, exactly), so this converter never needs the rate-multiplication tolerance
/// [Money.convert] does — the rare factor/precision combination that doesn't divide evenly
/// is resolved with half-up integer rounding, never a `double`.
final class UnitConverter {
  /// Creates a converter. Stateless — safe to use as a `const` singleton.
  const UnitConverter();

  static const int _maxInputLength = 24;

  /// Parses [input] — a decimal quantity in some unit — into milliBase, where one unit of
  /// the input equals [unitFactorMilliBase] milliBase units (e.g. `1_000_000` for `kg`).
  /// [localeTag] determines the decimal and grouping separator characters. Rounds half up
  /// on the rare factor/input combination that doesn't divide evenly.
  Result<int, ParseFailure> parseToMilliBase(
      String input, {
        required int unitFactorMilliBase,
        String localeTag = 'en',
        bool allowNegative = false,
      }) {
    var text = input.trim();
    if (text.isEmpty) return const Result.failure(ParseFailure.empty);
    if (text.length > _maxInputLength) return const Result.failure(ParseFailure.tooLarge);

    var sign = 1;
    if (text.startsWith('-')) {
      if (!allowNegative) return const Result.failure(ParseFailure.negativeNotAllowed);
      sign = -1;
      text = text.substring(1);
    } else if (text.startsWith('+')) {
      text = text.substring(1);
    }
    if (text.isEmpty) return const Result.failure(ParseFailure.malformed);

    final symbols = NumberFormat.decimalPattern(localeTag).symbols;
    final groupSep = symbols.GROUP_SEP;
    final decimalSep = symbols.DECIMAL_SEP;

    if (groupSep.isNotEmpty) {
      text = text.replaceAll(groupSep, '');
    }
    if (text.isEmpty) return const Result.failure(ParseFailure.malformed);

    final parts = decimalSep.isEmpty ? [text] : text.split(decimalSep);
    if (parts.length > 2) return const Result.failure(ParseFailure.malformed);

    final wholePart = parts[0];
    final fracPart = parts.length == 2 ? parts[1] : '';

    if (wholePart.isEmpty && fracPart.isEmpty) {
      return const Result.failure(ParseFailure.malformed);
    }
    if (!_isDigitsOnly(wholePart) || !_isDigitsOnly(fracPart)) {
      return const Result.failure(ParseFailure.invalidCharacter);
    }

    final numerator = int.parse('${wholePart.isEmpty ? '0' : wholePart}$fracPart');
    final denominator = _pow10(fracPart.length);
    final product = numerator * unitFactorMilliBase;
    final milliBase = (product + denominator ~/ 2) ~/ denominator;

    return Result.ok(sign * milliBase);
  }

  /// Splits [milliBase] into a whole count of units (each equal to [unitFactorMilliBase]
  /// milliBase) and the milliBase remainder. Intended for non-negative, already-stored
  /// quantities; see [Qty] for arithmetic on values that might be negative.
  ({int wholeUnits, int remainderMilliBase}) decompose(int milliBase, int unitFactorMilliBase) {
    return (
    wholeUnits: milliBase ~/ unitFactorMilliBase,
    remainderMilliBase: milliBase % unitFactorMilliBase,
    );
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