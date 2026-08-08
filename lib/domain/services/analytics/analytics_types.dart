import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';

/// The window every analytics query is bounded by.
typedef AnalyticsWindow = ({DateKey from, DateKey to});

/// How much of a converted series could not be stated exactly.
///
/// Carried alongside every money series per ARCH_3 §5.2. A total presented without it would be
/// quietly wrong whenever a rate was missing; presented with it, the UI can say so.
typedef ConversionQuality = ({int approximateCount, int unconvertedCount});

/// A conversion quality with nothing to report.
const ConversionQuality exactConversion = (
  approximateCount: 0,
  unconvertedCount: 0,
);

/// One labelled money figure — the shape most charts consume.
typedef MoneySlice = ({String label, String key, Money amount});

/// One labelled quantity figure.
typedef QuantitySlice = ({String label, String key, Qty quantity});

/// A money series plus how reliable its conversions were.
typedef MoneySeries = ({List<MoneySlice> slices, ConversionQuality quality});

/// One point in a monthly series, keyed by `yyyymm`.
typedef MonthPoint = ({int monthKey, Money amount});

/// A monthly series plus its conversion quality.
typedef MonthSeries = ({List<MonthPoint> points, ConversionQuality quality});

/// One point in a daily series.
typedef DayPoint = ({DateKey date, Money amount});

/// Query 1 — spend by subtype for one month.
typedef SubtypeSpend = ({int monthKey, MoneySeries series});

/// Query 5 — income against expense over a rolling window.
typedef IncomeVsExpensePoint = ({int monthKey, Money income, Money expense});

/// Query 5's series.
typedef IncomeVsExpense = ({
  List<IncomeVsExpensePoint> points,
  ConversionQuality quality,
});

/// Query 6 — net cash flow per month.
typedef NetCashFlow = ({List<MonthPoint> points, ConversionQuality quality});

/// Query 7 — one account's running balance.
typedef BalancePoint = ({DateKey date, Money balance});

/// Query 7's series, in the account's own currency so no conversion is involved.
typedef BalanceTrend = ({String accountId, List<BalancePoint> points});

/// Query 8 and 22 — one slice's share of a total.
typedef ShareOfTotal = ({String key, String label, Money amount, double share});

/// Query 22's result: the top slices and what they add up to.
typedef Concentration = ({
  List<ShareOfTotal> top,
  double topShare,
  Money total,
  ConversionQuality quality,
});

/// Query 9 — one item's total spend.
typedef ItemSpend = ({
  String itemId,
  String itemName,
  Money amount,
  int purchaseCount,
});

/// Query 10 — one item's total quantity bought.
typedef ItemQuantity = ({
  String itemId,
  String itemName,
  Qty quantity,
  int purchaseCount,
});

/// Query 11 — the dearest single purchase of an item.
typedef DearestPurchase = ({
  String itemId,
  String itemName,
  Money unitPrice,
  DateKey on,
  String transactionId,
});

/// Queries 12 and 24 — one observation of what an item cost per base unit.
///
/// [pricePerBaseUnit] is a `double` of minor units, not a `Money`: it is a derived ratio for
/// comparison, and Law L1 governs amounts that are stored. Storing it would imply a precision the
/// division does not have.
typedef UnitPricePoint = ({
  DateKey on,
  Money lineAmount,
  Qty quantity,
  double pricePerBaseUnit,
});

/// Query 12's series, plus the change across it — the personal-inflation number.
typedef UnitPriceTrend = ({
  String itemId,
  String itemName,
  List<UnitPricePoint> points,
  double? percentChange,
});

/// Query 13 — inventory value on hand, per currency.
///
/// Per currency rather than one figure: batch cost currency is per row, so a single total would be
/// adding rupees to yen (anomaly A34).
typedef InventoryValue = ({
  Map<String, Money> byCurrency,
  int batchesValued,
  int batchesNoCost,
});

/// Query 14 — what was wasted, in quantity and money.
///
/// Named `ItemWasteTotal` rather than `WasteTotal` because Phase 3A already declares a `WasteTotal`
/// class on `StockRepository`. They answer different questions — that one is a repository read for a
/// single item, this one is an analytics rollup carrying cost per currency — and a file importing both
/// would not compile.
typedef ItemWasteTotal = ({
  String itemId,
  String itemName,
  Qty quantity,
  Map<String, Money> costByCurrency,
});

/// Query 15 — a batch expiring soon.
typedef ExpiringBatch = ({
  String batchId,
  String itemId,
  String itemName,
  Qty remaining,
  DateKey expiry,
  int daysLeft,
});

/// Query 16 — how many items were low on stock on one date.
typedef LowStockPoint = ({DateKey date, int itemCount});

/// Query 17 — the fixed monthly commitment total.
typedef MonthlyCommitment = ({
  Money total,
  int templateCount,
  ConversionQuality quality,
});

/// Query 18 — the recurring against discretionary split.
typedef RecurringSplit = ({
  Money recurring,
  Money discretionary,
  double recurringShare,
  ConversionQuality quality,
});

/// Query 19 — one asset's lifetime service cost, per currency.
typedef AssetServiceCost = ({
  String assetId,
  String assetName,
  Map<String, Money> byCurrency,
  int serviceCount,
});

/// Query 20 — one asset's warranty window.
typedef WarrantyCoverage = ({
  String assetId,
  String assetName,
  DateKey? start,
  DateKey? end,
  int? daysLeft,
  bool isCovered,
});

/// Query 21 — one cell of the spend heatmap.
///
/// [bucket] is 1-7 for a weekday series (Monday first) or 1-31 for a day-of-month series.
typedef HeatmapCell = ({int bucket, Money amount, int transactionCount});

/// Query 21's result.
typedef SpendHeatmap = ({List<HeatmapCell> cells, ConversionQuality quality});

/// Query 23 — the average basket.
typedef BasketStats = ({
  Money averageValue,
  double averageLineCount,
  int basketCount,
  ConversionQuality quality,
});
