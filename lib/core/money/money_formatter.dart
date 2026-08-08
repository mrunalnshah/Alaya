import 'package:intl/intl.dart';

import 'money.dart';

/// Renders [Money] as a locale-correct display string, including digit grouping. Deliberately
/// does not delegate grouping to `intl`'s `NumberFormat`: that class only supports a single,
/// uniform group size, so it cannot produce Indian lakh/crore grouping (2-2-3 digits) —
/// see dart-lang/i18n#349, an open feature request for exactly this. Instead, this formatter
/// uses `NumberFormat` only to look up which characters a locale uses as its decimal point
/// and group separator, and performs the actual digit grouping itself with exact integer and
/// string operations (never a `double`, consistent with Law L1). A purely display-layer
/// concern: it never mutates or rounds the underlying integer minor units.
final class MoneyFormatter {
  /// Creates a formatter. Stateless — safe to use as a `const` singleton.
  const MoneyFormatter();

  /// Formats [money] for display. [decimalDigits] and [symbol] must come from the
  /// `currencies` table (never hardcoded — see ARCH_1 §4.1); [localeTag] controls only
  /// digit grouping and the decimal separator character.
  String format(
      Money money, {
        required int decimalDigits,
        required String symbol,
        String localeTag = 'en_IN',
        bool showPlusSign = false,
      }) {
    final magnitude = money.minor.abs();
    final divisor = _pow10(decimalDigits);
    final whole = magnitude ~/ divisor;
    final frac = magnitude % divisor;

    final symbols = NumberFormat.decimalPattern(localeTag).symbols;
    final groupedWhole = _groupDigits(
      whole.toString(),
      groupSeparator: symbols.GROUP_SEP,
      useIndianGrouping: _isIndianLocale(localeTag),
    );

    final fracStr = decimalDigits == 0
        ? ''
        : '${symbols.DECIMAL_SEP}${frac.toString().padLeft(decimalDigits, '0')}';

    final sign = money.isNegative ? '-' : (showPlusSign && money.isPositive ? '+' : '');

    return '$sign$symbol$groupedWhole$fracStr';
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  /// True for locales whose region subtag is India, which use 2-2-3 grouping (lakh/crore)
  /// rather than the 3-3-3 grouping most other locales use.
  static bool _isIndianLocale(String localeTag) {
    final region = localeTag.split(RegExp('[_-]')).last.toUpperCase();
    return region == 'IN';
  }

  /// Groups [digits] (a plain non-negative integer string) into the target locale's scheme:
  /// a final group of 3 digits, then repeating groups of 2 (Indian) or 3 (Western) moving
  /// left, joined by [groupSeparator].
  static String _groupDigits(
      String digits, {
        required String groupSeparator,
        required bool useIndianGrouping,
      }) {
    if (groupSeparator.isEmpty || digits.length <= 3) return digits;

    final secondaryGroupSize = useIndianGrouping ? 2 : 3;
    final primaryGroup = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);

    final groups = <String>[];
    while (rest.length > secondaryGroupSize) {
      groups.insert(0, rest.substring(rest.length - secondaryGroupSize));
      rest = rest.substring(0, rest.length - secondaryGroupSize);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    groups.add(primaryGroup);

    return groups.join(groupSeparator);
  }
}