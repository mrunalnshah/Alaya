/// View-model state for the dashboard's range rows (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/date_range_service.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';

/// Money in and money out over one labelled window, with what could not be converted.
class RangeTotals {
  /// Creates a set of totals.
  const RangeTotals({
    required this.moneyIn,
    required this.moneyOut,
    required this.excludedCount,
  });

  /// Deposits, converted into the home currency.
  final Money moneyIn;

  /// Withdrawals, converted into the home currency.
  final Money moneyOut;

  /// How many transactions held a currency no rate could convert.
  ///
  /// Excluded from both figures rather than summed at face value (anomaly A34), and surfaced so the row
  /// can say the total is partial instead of quietly under-reporting.
  final int excludedCount;

  /// Whether the window held nothing at all, which reads differently from holding zero.
  bool get isEmpty => moneyIn.isZero && moneyOut.isZero && excludedCount == 0;
}

/// The last thirty days, ending today.
///
/// **Always labelled with what it means** (anomaly A33). A row reading "last month" is ambiguous between
/// the previous calendar month and the preceding thirty days, and a user cannot tell which they are
/// looking at from the number alone — so the label states the window and the code computes exactly that.
final last30Provider = Provider<DateRange>((ref) {
  final today = ref.watch(clockProvider).today();
  return (from: today.addDays(-29), to: today);
});

/// Everything on record, from the earliest date this app treats as real.
final allTimeProvider = Provider<DateRange>((ref) {
  return (
    from: DateRangeService.earliest,
    to: ref.watch(clockProvider).today(),
  );
});

/// Totals over one window.
///
/// Converted through `RateTable` once for the whole window rather than per transaction, because
/// `CurrencyRateService.toHome` reloads the table on every call and a year of transactions would reload it
/// a thousand times.
final rangeTotalsProvider = FutureProvider.autoDispose.family<RangeTotals, DateRange>((
  ref,
  range,
) async {
  final code = await ref.watch(dashboardCurrencyProvider.future);
  final rows = await ref
      .watch(transactionRepositoryProvider)
      .watchByDateRange(from: range.from, to: range.to)
      .first;
  final table = await ref.watch(currencyRateServiceProvider).table();

  var moneyIn = Money.zero(code);
  var moneyOut = Money.zero(code);
  var excluded = 0;
  for (final transaction in rows) {
    // **Transfers and adjustments are neither in nor out.** A transfer moves money between the user's own
    // accounts, so counting it as both would double every figure and net to a lie. An adjustment is a
    // bookkeeping correction — presenting one as income would tell the user they earned their own
    // reconciliation. The rows are labelled "In" and "Out" and must contain only what those words mean
    // (anomaly A33).
    if (transaction.kind == TransactionKind.transfer ||
        transaction.kind == TransactionKind.adjustmentIncrease ||
        transaction.kind == TransactionKind.adjustmentDecrease) {
      continue;
    }

    final converted = table.convert(
      amount: transaction.originalAmount,
      toCurrencyCode: code,
      on: transaction.dateKey,
    );
    final value = converted.converted;
    if (value == null) {
      excluded++;
      continue;
    }
    switch (transaction.kind) {
      case TransactionKind.deposit:
        moneyIn = moneyIn + value;
      case TransactionKind.withdrawal:
        moneyOut = moneyOut + value;
      case TransactionKind.transfer:
      case TransactionKind.adjustmentIncrease:
      case TransactionKind.adjustmentDecrease:
        break;
    }
  }
  return RangeTotals(
    moneyIn: moneyIn,
    moneyOut: moneyOut,
    excludedCount: excluded,
  );
});
