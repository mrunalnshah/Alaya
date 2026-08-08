import 'package:intl/intl.dart';

import '../result/failure.dart';
import '../result/result.dart';
import 'money.dart';

/// Parses user-typed monetary text into [Money], honouring locale-specific decimal and
/// grouping separators. Never throws — every outcome, including a still-being-typed or
/// malformed string, comes back as a [Result] so the UI can decide how to react instead of
/// crashing. Converts the decimal text to minor units using exact string/integer
/// manipulation only; a `double` is never involved (Law L1), which also means this parser
/// never silently rounds a typed value — a currency's precision is enforced by rejecting
/// extra digits (see [ParseFailure.tooManyDecimalDigits]), not by discarding them.
final class MoneyParser {
  /// Creates a parser. Stateless — safe to use as a `const` singleton.
  const MoneyParser();

  static const int _maxInputLength = 24;

  /// Parses [input] as an amount in [currencyCode] with [decimalDigits] decimal places.
  /// [localeTag] (e.g. `'en_IN'`, `'de_DE'`) determines which characters are the decimal
  /// point and the grouping separator. Negative input is rejected unless [allowNegative].
  Result<Money, ParseFailure> parse(
      String input, {
        required String currencyCode,
        required int decimalDigits,
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

    final decimalParts = decimalSep.isEmpty ? [text] : text.split(decimalSep);
    if (decimalParts.length > 2) return const Result.failure(ParseFailure.malformed);

    final wholePart = decimalParts[0];
    final fracPart = decimalParts.length == 2 ? decimalParts[1] : '';

    if (wholePart.isEmpty && fracPart.isEmpty) {
      return const Result.failure(ParseFailure.malformed);
    }
    if (!_isDigitsOnly(wholePart) || !_isDigitsOnly(fracPart)) {
      return const Result.failure(ParseFailure.invalidCharacter);
    }
    if (fracPart.length > decimalDigits) {
      return const Result.failure(ParseFailure.tooManyDecimalDigits);
    }

    final paddedFrac = fracPart.padRight(decimalDigits, '0');
    final digitString = '${wholePart.isEmpty ? '0' : wholePart}$paddedFrac';
    final magnitude = int.parse(digitString);

    return Result.ok(Money(sign * magnitude, currencyCode));
  }

  static bool _isDigitsOnly(String value) {
    for (final codeUnit in value.codeUnits) {
      if (codeUnit < 0x30 || codeUnit > 0x39) return false;
    }
    return true;
  }
}