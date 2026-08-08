import 'package:intl/intl.dart';

import 'qty.dart';
import 'unit_category.dart';

/// Controls how [QtyFormatter] renders a quantity. See ARCH_1 §5.2.
enum UnitStyle {
  /// Decomposes weight/volume into their carry pair (`"4 kg 450 g"`) and leaves `count` as a
  /// single number (`"3 pc"`). The default; used for item rows and batch chips.
  mixed,

  /// A single decimal number in the bigger unit for weight/volume, rounded to 2 decimal
  /// places (`"4.45 kg"`); identical to [mixed] for `count`. Used for dense chart axes and
  /// narrow chips only.
  compact,

  /// The raw base unit with no decomposition (`"4450 g"`); identical to [mixed] for `count`.
  /// Used for debug output and export.
  base,
}

/// Renders a [Qty] as a human-readable string per ARCH_1 §5.2. Pure and stateless: the same
/// [Qty] and [UnitStyle] always produce the same string. The unit vocabulary (`kg`, `g`,
/// `L`, `ml`, `pc`) is always these English abbreviations regardless of locale; [localeTag]
/// controls only the decimal separator character used in [UnitStyle.compact].
final class QtyFormatter {
  /// Creates a formatter. Stateless — safe to use as a `const` singleton.
  const QtyFormatter();

  static const int _milliPerBaseUnit = 1000;
  static const int _milliPerBigUnit = _milliPerBaseUnit * 1000; // 1 kg or 1 L, in milliBase

  /// Formats [qty] according to [style].
  String format(Qty qty, {UnitStyle style = UnitStyle.mixed, String localeTag = 'en'}) {
    final isNegative = qty.isNegative;
    final magnitude = isNegative ? -qty.milliBase : qty.milliBase;
    final sign = isNegative ? '-' : '';
    final body = switch (style) {
      UnitStyle.mixed => _formatMixed(magnitude, qty.category),
      UnitStyle.compact => _formatCompact(magnitude, qty.category, localeTag),
      UnitStyle.base => _formatBase(magnitude, qty.category),
    };
    return '$sign$body';
  }

  String _formatMixed(int magnitude, UnitCategory category) {
    return switch (category) {
      UnitCategory.count => '${_formatThousandths(magnitude)} pc',
      UnitCategory.weight => _formatCarryPair(magnitude, smallUnit: 'g', bigUnit: 'kg'),
      UnitCategory.volume => _formatCarryPair(magnitude, smallUnit: 'ml', bigUnit: 'L'),
    };
  }

  String _formatCarryPair(int magnitude, {required String smallUnit, required String bigUnit}) {
    final bigWhole = magnitude ~/ _milliPerBigUnit;
    final remainderMilli = magnitude % _milliPerBigUnit;

    if (bigWhole == 0) {
      return '${_formatThousandths(remainderMilli)} $smallUnit';
    }
    if (remainderMilli == 0) {
      return '$bigWhole $bigUnit';
    }
    return '$bigWhole $bigUnit ${_formatThousandths(remainderMilli)} $smallUnit';
  }

  String _formatCompact(int magnitude, UnitCategory category, String localeTag) {
    if (category == UnitCategory.count) return '${_formatThousandths(magnitude)} pc';

    final bigUnit = category == UnitCategory.weight ? 'kg' : 'L';
    // Half-up rounding to 2 decimal places of the big-unit value, via pure integer math:
    // hundredths = round(magnitude * 100 / 1_000_000).
    final hundredths = (magnitude * 100 + _milliPerBigUnit ~/ 2) ~/ _milliPerBigUnit;
    final whole = hundredths ~/ 100;
    final frac = hundredths % 100;
    final fracStr = frac.toString().padLeft(2, '0');
    return '$whole${_decimalSeparator(localeTag)}$fracStr $bigUnit';
  }

  String _formatBase(int magnitude, UnitCategory category) {
    final unit = category.baseUnitCode;
    return '${_formatThousandths(magnitude)} $unit';
  }

  /// Formats [valueMilli] (a count of thousandths of some unit) as that unit's exact
  /// decimal value, e.g. `450_000` → `"450"`, `500` → `"0.5"`, `5` → `"0.005"`, `0` → `"0"`.
  static String _formatThousandths(int valueMilli) {
    final whole = valueMilli ~/ _milliPerBaseUnit;
    final frac = valueMilli % _milliPerBaseUnit;
    if (frac == 0) return '$whole';

    var fracStr = frac.toString().padLeft(3, '0');
    while (fracStr.endsWith('0')) {
      fracStr = fracStr.substring(0, fracStr.length - 1);
    }
    return '$whole.$fracStr';
  }

  /// The locale's decimal-point character. Looked up from `intl`'s locale data rather than
  /// guessed from the language subtag — that would get exceptions like `de_CH` wrong, which
  /// uses a period unlike the rest of German-speaking locales.
  static String _decimalSeparator(String localeTag) =>
      NumberFormat.decimalPattern(localeTag).symbols.DECIMAL_SEP;
}