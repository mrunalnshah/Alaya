import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';

/// One aggregate row as SQL returns it: a key, a label, a **minor-unit amount and its currency**.
///
/// Money arrives unconverted and paired with its own code, because ARCH_3 §5.2 requires conversion
/// **per data point** — a query that summed across currencies in SQL would have already lost the
/// information needed to convert correctly.
typedef RawMoneyRow = ({
  String key,
  String label,
  int amountMinor,
  String currencyCode,
  int count,
});

/// One aggregate row carrying a quantity in base-milli units.
typedef RawQuantityRow = ({
  String key,
  String label,
  int milliBase,
  String category,
  int count,
});

/// One monthly aggregate row.
typedef RawMonthRow = ({
  int monthKey,
  int amountMinor,
  String currencyCode,
  int count,
});

/// One dated aggregate row.
typedef RawDateRow = ({
  int dateKey,
  int amountMinor,
  String currencyCode,
  int count,
});

/// One bucketed aggregate row, for the heatmap.
typedef RawBucketRow = ({
  int bucket,
  int amountMinor,
  String currencyCode,
  int count,
});

/// The raw aggregates every analytics query is built from.
///
/// **Declared here, in `domain/`, and implemented in `data/`.** ARCH_3 §5.2 requires the aggregation
/// to happen in SQL over indexed columns — "nothing is loaded into Dart to be summed" — while Law L12
/// forbids `domain/` from importing drift. A port resolves that: the SQL lives in the adapter, the
/// interpretation lives in `AnalyticsService`, and neither has to compromise.
///
/// Every method is bounded by a window, because an unbounded aggregate over 50k transactions is the
/// performance risk ARCH_4 R7 is about.
abstract interface class AnalyticsPort {
  /// Query 1 — spend per subtype within [window], grouped by currency.
  Future<List<RawMoneyRow>> spendBySubtype(AnalyticsWindow window);

  /// Query 2 — spend per tag.
  Future<List<RawMoneyRow>> spendByTag(AnalyticsWindow window);

  /// Query 3 — spend per payment method.
  Future<List<RawMoneyRow>> spendByPaymentMethod(AnalyticsWindow window);

  /// Query 4 — spend per payee, already ordered descending by SQL.
  Future<List<RawMoneyRow>> spendByPayee(AnalyticsWindow window, {int limit});

  /// Query 5 — totals per month split by [kind].
  Future<List<RawMonthRow>> totalsByMonthAndKind(
    AnalyticsWindow window,
    TransactionKind kind,
  );

  /// Query 6 — signed ledger sum per month, from `v_account_ledger`.
  Future<List<RawMonthRow>> netFlowByMonth(AnalyticsWindow window);

  /// Query 7 — one account's signed legs in date order, for a running balance.
  Future<List<RawDateRow>> ledgerLegsForAccount(
    String accountId,
    AnalyticsWindow window,
  );

  /// Query 7's starting point — the account's opening balance.
  Future<({int minor, String currencyCode})?> openingBalance(String accountId);

  /// Queries 8 and 22 — total spend within [window].
  Future<List<RawMoneyRow>> totalSpend(AnalyticsWindow window);

  /// Query 9 — spend per item from transaction lines.
  Future<List<RawMoneyRow>> spendByItem(AnalyticsWindow window, {int limit});

  /// Query 10 — quantity bought per item.
  Future<List<RawQuantityRow>> quantityByItem(
    AnalyticsWindow window, {
    int limit,
  });

  /// Query 11 — the highest unit price recorded for [itemId].
  Future<
    ({
      int unitPriceMinor,
      String currencyCode,
      int dateKey,
      String transactionId,
    })?
  >
  dearestPurchase(String itemId, AnalyticsWindow window);

  /// Queries 12 and 24 — every priced line for [itemId], oldest first.
  Future<
    List<
      ({
        int dateKey,
        int lineAmountMinor,
        String currencyCode,
        int milliBase,
        String category,
      })
    >
  >
  itemPurchaseHistory(String itemId, AnalyticsWindow window);

  /// Query 13 — every batch with stock and a recorded cost.
  ///
  /// [unitFactorToBaseMilli] is `units.factor_to_base_milli` for the batch's `unit_code_at_purchase`,
  /// and it is **required rather than convenient**: `Batch.unitCost` is cost per
  /// `unitCodeAtPurchase`, not per base unit, so valuing a batch without the factor is off by exactly
  /// that unit's magnitude — a thousandfold for a purchase recorded in kilograms.
  Future<
    List<
      ({
        int remainingMilli,
        int unitCostMinor,
        String currencyCode,
        int unitFactorToBaseMilli,
      })
    >
  >
  valuedBatches();

  /// Query 13's counterpart — batches holding stock with no cost recorded.
  Future<int> batchesWithoutCost();

  /// Query 14 — waste and expiry movements with their batch cost.
  Future<
    List<
      ({
        String itemId,
        String itemName,
        int milliBase,
        String category,
        int? unitCostMinor,
        String? currencyCode,
        int? unitFactorToBaseMilli,
      })
    >
  >
  wasteMovements(AnalyticsWindow window);

  /// Query 15 — batches expiring within [window] that still hold stock.
  Future<
    List<
      ({
        String batchId,
        String itemId,
        String itemName,
        int remainingMilli,
        String category,
        int expiryDateKey,
      })
    >
  >
  expiringBatches(AnalyticsWindow window);

  /// Query 16 — how many items are low on stock right now.
  Future<int> lowStockCount();

  /// Query 17 — active unpaused templates and their default amounts.
  Future<
    List<
      ({
        int defaultAmountMinor,
        String currencyCode,
        String intervalUnit,
        int intervalCount,
      })
    >
  >
  activeCommitments();

  /// Query 18 — spend split by whether a transaction settled a recurring template.
  Future<List<RawMoneyRow>> spendByRecurringFlag(AnalyticsWindow window);

  /// Query 19 — service cost per asset.
  Future<
    List<
      ({
        String assetId,
        String assetName,
        int costMinor,
        String currencyCode,
        int count,
      })
    >
  >
  serviceCostByAsset(AnalyticsWindow window);

  /// Query 20 — warranty windows for assets that have one.
  Future<
    List<
      ({String assetId, String assetName, int? startDateKey, int? endDateKey})
    >
  >
  warrantyWindows();

  /// Query 21 — spend bucketed by weekday (1-7) or day of month (1-31).
  Future<List<RawBucketRow>> spendByBucket(
    AnalyticsWindow window, {
    required bool byWeekday,
  });

  /// Query 23 — grocery transactions with their line counts.
  Future<List<({int amountMinor, String currencyCode, int lineCount})>>
  groceryBaskets(
    AnalyticsWindow window,
  );

  /// Today, for the queries whose answer depends on it. Supplied by the adapter's clock so nothing
  /// in `domain/` reads the time itself.
  DateKey today();
}
