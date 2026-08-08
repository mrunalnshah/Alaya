import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/domain/entities/currency.dart';

/// Reads currencies and the cached exchange rates.
abstract interface class CurrencyRepository {
  /// Emits the currencies offered in pickers.
  Stream<List<Currency>> watchEnabled();

  /// Emits every currency, enabled or not.
  Stream<List<Currency>> watchAll();

  /// Reads one currency by ISO code.
  Future<Currency?> byCode(String code);

  /// Reads `code -> decimalDigits` for every currency — the lookup that keeps `100` out of the
  /// codebase (ARCH_1 §4.1).
  Future<Map<String, int>> decimalDigitsByCode();

  /// Enables or disables a currency without deleting it.
  Future<Result<void, Failure>> setEnabled({
    required String code,
    required bool isEnabled,
  });

  /// Converts [amount] into [toCurrencyCode] using the rate for [on].
  ///
  /// Returns a [ConvertedMoney] rather than a bare [Money] so the caller cannot lose track of how
  /// reliable the figure is — an unconverted amount must be excluded from a total rather than
  /// counted as zero (anomaly A15).
  Future<ConvertedMoney> convert({
    required Money amount,
    required String toCurrencyCode,
    required DateKey on,
  });

  /// Converts [amount] into the user's home currency.
  Future<ConvertedMoney> convertToHome({
    required Money amount,
    required DateKey on,
  });

  /// Emits how many amounts currently cannot be converted, for the `+N unconverted` chip.
  Stream<int> watchUnconvertedCount();

  /// Fetches today's rates if the network allows. Never throws and never blocks a write
  /// (Law L11) — a failure is a no-op.
  Future<void> syncDailyRates();
}