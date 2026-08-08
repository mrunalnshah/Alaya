import 'package:alaya/core/money/money.dart';

/// Composes and decomposes [Money] across the two-column pairs the schema stores it in.
///
/// **This is deliberately not a drift `TypeConverter`.** A `TypeConverter` maps exactly one
/// column to one Dart value, and every monetary value in ARCH_2 is stored as *two* columns — an
/// `INTEGER` minor-unit amount plus a sibling `TEXT` currency code (Law L1, and ARCH_2 §4.1's
/// `original_amount_minor` / `original_currency_code`). A converter cannot read a sibling
/// column, so the composition has to happen one level up, in the mappers of Phases 3B-3D.
///
/// Keeping the pairing in one place matters because the pairs are not uniformly named:
/// `(originalAmountMinor, originalCurrencyCode)`, `(convertedAmountMinor,
/// convertedCurrencyCode)`, `(unitCostMinor, costCurrencyCode)`, `(purchasePriceMinor,
/// purchaseCurrencyCode)`, `(costMinor, currencyCode)`. Every one of those is a chance to
/// silently pair an amount with the wrong currency, which is exactly the class of bug Law L1
/// exists to prevent.
///
/// The amount columns are plain `integer()` in the table definitions, so the raw minor units
/// stay directly available to SQL aggregation (ARCH_3 §5.2 requires summing in SQL, never in
/// Dart) — a per-column type converter would not have prevented that, but it is worth stating
/// that the absence of one costs nothing here.
abstract final class MoneyColumns {
  /// Builds [Money] from a non-null amount/currency column pair.
  static Money read(int minorUnits, String currencyCode) => Money(minorUnits, currencyCode);

  /// Builds [Money] from a nullable pair, returning `null` when either column is null.
  ///
  /// Both columns are required to be null or non-null together; a half-populated pair means an
  /// amount whose currency is unknown, which cannot be represented and must not be guessed.
  /// Throws [ArgumentError] on a half-populated pair so the inconsistency surfaces at the
  /// mapper rather than as a wrong number on a dashboard.
  static Money? readNullable(int? minorUnits, String? currencyCode) {
    if (minorUnits == null && currencyCode == null) return null;
    if (minorUnits == null || currencyCode == null) {
      throw ArgumentError(
        'Half-populated money pair: minorUnits=$minorUnits, currencyCode=$currencyCode. '
            'An amount and its currency must be stored and cleared together.',
      );
    }
    return Money(minorUnits, currencyCode);
  }

  /// The value for the `INTEGER` minor-unit column.
  static int minorOf(Money money) => money.minor;

  /// The value for the sibling `TEXT` currency-code column.
  static String codeOf(Money money) => money.currencyCode;

  /// The minor-unit column value for a nullable [Money].
  static int? minorOfNullable(Money? money) => money?.minor;

  /// The currency-code column value for a nullable [Money].
  static String? codeOfNullable(Money? money) => money?.currencyCode;
}