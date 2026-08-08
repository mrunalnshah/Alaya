import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// How reliable a currency conversion is (ARCH_3 §1.3).
enum RateQuality {
  /// A rate was cached for the requested date, or the most recent one on or before it.
  exact,

  /// No rate on or before the requested date existed, so the earliest available one was used.
  /// The figure is indicative and the UI must say so.
  approximate,

  /// No rate existed at all. [ConvertedMoney.converted] is null and the amount must be excluded
  /// from any total rather than counted as zero.
  unconverted,
}

/// An original amount paired with its conversion into another currency, and how much to trust it.
///
/// Never replaces the original (Law L9). This is a read-time view: the display layer aggregates
/// these, and only the explicit per-transaction freeze action writes a converted figure back to
/// the database.
class ConvertedMoney {
  /// Creates a conversion result.
  const ConvertedMoney({
    required this.original,
    required this.quality,
    this.converted,
    this.rate,
    this.rateDateKey,
  });

  /// A result for an amount that could not be converted at all.
  const ConvertedMoney.unconverted(this.original)
      : quality = RateQuality.unconverted,
        converted = null,
        rate = null,
        rateDateKey = null;

  /// The amount as stored, in its own currency. Immutable (Law L9).
  final Money original;

  /// How reliable [converted] is.
  final RateQuality quality;

  /// The converted amount, or null when [quality] is [RateQuality.unconverted].
  final Money? converted;

  /// The rate used, or null when nothing was converted.
  final double? rate;

  /// The civil date the applied rate was quoted for, or null when nothing was converted.
  final DateKey? rateDateKey;

  /// True when a converted figure is available, whatever its quality.
  bool get hasConversion => converted != null;

  /// True when this amount must be excluded from a converted total (anomaly A15).
  bool get isExcludedFromTotals => quality == RateQuality.unconverted;

  /// The amount to display: [converted] when available, otherwise [original].
  Money get display => converted ?? original;

  @override
  bool operator ==(Object other) =>
      other is ConvertedMoney &&
          other.original == original &&
          other.quality == quality &&
          other.converted == converted &&
          other.rate == rate &&
          other.rateDateKey == rateDateKey;

  @override
  int get hashCode => Object.hashAll([original, quality, converted, rate, rateDateKey]);

  @override
  String toString() => 'ConvertedMoney($original -> $converted, ${quality.name})';
}