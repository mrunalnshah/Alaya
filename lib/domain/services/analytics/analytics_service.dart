import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/domain/services/analytics/analytics_port.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// ARCH_3 §5.1's twenty-four queries, each a named function returning plain records.
///
/// **No chart-library types anywhere** (§5.2, Law L12). Everything returned is a Dart record or an
/// entity, so the presentation layer maps to whatever chart package it likes and this layer stays
/// unit-testable without a widget tree.
///
/// Aggregation happens in SQL, behind [AnalyticsPort]. What happens here is the part SQL cannot do
/// correctly: **converting each data point separately** before summing. A query that let SQL add
/// across currencies would already have destroyed the information needed to convert — so every raw
/// row arrives as one currency's subtotal, and each is converted against the rate for its own date
/// before it joins a total.
final class AnalyticsService {
  /// Creates the service over [port], converting through [rates].
  const AnalyticsService({
    required AnalyticsPort port,
    required RateTable rates,
    required String homeCurrencyCode,
  }) : _port = port,
       _rates = rates,
       _home = homeCurrencyCode;

  final AnalyticsPort _port;
  final RateTable _rates;
  final String _home;

  // ── 1-8, 21-23: money ─────────────────────────────────────────────────────────────────

  /// Query 1 — spend by subtype within [window].
  Future<MoneySeries> spendBySubtype(AnalyticsWindow window) async =>
      _toSeries(await _port.spendBySubtype(window), window.to);

  /// Query 2 — spend by tag.
  Future<MoneySeries> spendByTag(AnalyticsWindow window) async =>
      _toSeries(await _port.spendByTag(window), window.to);

  /// Query 3 — spend by payment method.
  Future<MoneySeries> spendByPaymentMethod(AnalyticsWindow window) async =>
      _toSeries(await _port.spendByPaymentMethod(window), window.to);

  /// Query 4 — the top [limit] payees by spend.
  ///
  /// SQL orders and limits, so this does not sort in Dart. It re-sorts only after conversion,
  /// because a mixed-currency list ordered by raw minor units is ordered by the wrong thing —
  /// ¥10,000 outranking ₹5,000 is an artefact of the unit, not the amount.
  Future<MoneySeries> topPayeesBySpend(
    AnalyticsWindow window, {
    int limit = 10,
  }) async {
    final series = _toSeries(
      await _port.spendByPayee(window, limit: limit),
      window.to,
    );
    final sorted = series.slices.toList()
      ..sort((a, b) => b.amount.minor.compareTo(a.amount.minor));
    return (slices: sorted.take(limit).toList(), quality: series.quality);
  }

  /// Query 5 — income against expense, month by month.
  Future<IncomeVsExpense> incomeVsExpense(AnalyticsWindow window) async {
    final income = await _port.totalsByMonthAndKind(
      window,
      TransactionKind.deposit,
    );
    final expense = await _port.totalsByMonthAndKind(
      window,
      TransactionKind.withdrawal,
    );

    final byMonth = <int, ({int income, int expense})>{};
    var approximate = 0;
    var unconverted = 0;

    void fold(List<RawMonthRow> rows, {required bool isIncome}) {
      for (final row in rows) {
        final converted = _convert(
          row.amountMinor,
          row.currencyCode,
          _monthEnd(row.monthKey),
        );
        if (converted == null) {
          unconverted++;
          continue;
        }
        if (converted.quality == RateQuality.approximate) approximate++;
        final current = byMonth[row.monthKey] ?? (income: 0, expense: 0);
        byMonth[row.monthKey] = isIncome
            ? (
                income: current.income + converted.converted!.minor,
                expense: current.expense,
              )
            : (
                income: current.income,
                expense: current.expense + converted.converted!.minor,
              );
      }
    }

    fold(income, isIncome: true);
    fold(expense, isIncome: false);

    final points =
        byMonth.entries
            .map(
              (e) => (
                monthKey: e.key,
                income: Money(e.value.income, _home),
                expense: Money(e.value.expense, _home),
              ),
            )
            .toList()
          ..sort((a, b) => a.monthKey.compareTo(b.monthKey));

    return (
      points: points,
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );
  }

  /// Query 6 — net cash flow per month, from the signed ledger.
  Future<NetCashFlow> netCashFlowByMonth(AnalyticsWindow window) async =>
      _toMonthSeries(await _port.netFlowByMonth(window));

  /// Query 7 — one account's running balance.
  ///
  /// Returned in the **account's own currency**, never converted. A balance trend is about one
  /// account, and converting each point at its own date would make the line move when rates moved
  /// rather than when money did.
  Future<BalanceTrend> balanceTrend(
    String accountId,
    AnalyticsWindow window,
  ) async {
    final opening = await _port.openingBalance(accountId);
    // `const <BalancePoint>[]` and not `const []`: a record field takes the literal's inferred
    // type verbatim, so a bare `const []` is `List<dynamic>` and will not match `BalanceTrend`.
    if (opening == null)
      return (accountId: accountId, points: const <BalancePoint>[]);

    final legs = await _port.ledgerLegsForAccount(accountId, window);
    var running = opening.minor;
    final points = <BalancePoint>[];
    for (final leg in legs) {
      running += leg.amountMinor;
      points.add((
        date: DateKey(leg.dateKey),
        balance: Money(running, opening.currencyCode),
      ));
    }
    return (accountId: accountId, points: points);
  }

  /// Query 8 — grocery's share of total spend.
  Future<ShareOfTotal?> groceryShareOfSpend(AnalyticsWindow window) async {
    final series = await spendBySubtype(window);
    return _shareOf(series, TransactionSubtype.grocery.name);
  }

  /// Query 21 — spend by weekday (1-7, Monday first) or day of month (1-31).
  Future<SpendHeatmap> spendHeatmap(
    AnalyticsWindow window, {
    bool byWeekday = true,
  }) async {
    final rows = await _port.spendByBucket(window, byWeekday: byWeekday);
    final byBucket = <int, ({int minor, int count})>{};
    var approximate = 0;
    var unconverted = 0;

    for (final row in rows) {
      final converted = _convert(row.amountMinor, row.currencyCode, window.to);
      if (converted == null) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate++;
      final current = byBucket[row.bucket] ?? (minor: 0, count: 0);
      byBucket[row.bucket] = (
        minor: current.minor + converted.converted!.minor,
        count: current.count + row.count,
      );
    }

    final cells =
        byBucket.entries
            .map(
              (e) => (
                bucket: e.key,
                amount: Money(e.value.minor, _home),
                transactionCount: e.value.count,
              ),
            )
            .toList()
          ..sort((a, b) => a.bucket.compareTo(b.bucket));

    return (
      cells: cells,
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );
  }

  /// Query 22 — how concentrated spending is in its top [topCount] categories.
  Future<Concentration> categoryConcentration(
    AnalyticsWindow window, {
    int topCount = 3,
  }) async {
    final series = await spendBySubtype(window);
    final total = series.slices.fold<int>(0, (sum, s) => sum + s.amount.minor);
    final sorted = series.slices.toList()
      ..sort((a, b) => b.amount.minor.compareTo(a.amount.minor));

    final top = sorted.take(topCount).map((slice) {
      return (
        key: slice.key,
        label: slice.label,
        amount: slice.amount,
        share: total == 0 ? 0.0 : slice.amount.minor / total,
      );
    }).toList();

    return (
      top: top,
      topShare: total == 0
          ? 0.0
          : top.fold<int>(0, (s, t) => s + t.amount.minor) / total,
      total: Money(total, _home),
      quality: series.quality,
    );
  }

  /// Query 23 — the average grocery basket.
  Future<BasketStats> averageGroceryBasket(AnalyticsWindow window) async {
    final baskets = await _port.groceryBaskets(window);
    if (baskets.isEmpty) {
      return (
        averageValue: Money.zero(_home),
        // `0.0`, not `0`. A record field does not widen int to double the way a direct parameter
        // does, so an int literal here is a type error rather than a promoted zero.
        averageLineCount: 0.0,
        basketCount: 0,
        quality: exactConversion,
      );
    }

    var totalMinor = 0;
    var totalLines = 0;
    var counted = 0;
    var approximate = 0;
    var unconverted = 0;

    for (final basket in baskets) {
      final converted = _convert(
        basket.amountMinor,
        basket.currencyCode,
        window.to,
      );
      if (converted == null) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate++;
      totalMinor += converted.converted!.minor;
      totalLines += basket.lineCount;
      counted++;
    }

    return (
      // Averaged over the baskets that CONVERTED, not over all of them. Dividing a partial total by
      // the full count would understate every basket by the share that was excluded.
      averageValue: Money(counted == 0 ? 0 : totalMinor ~/ counted, _home),
      // Both branches must be double or the conditional infers `num`, which no more satisfies
      // `double` than `int` did.
      averageLineCount: counted == 0 ? 0.0 : totalLines / counted,
      basketCount: counted,
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );
  }

  // ── 9-12, 24: items and prices ────────────────────────────────────────────────────────

  /// Query 9 — the top [limit] items by spend.
  Future<List<ItemSpend>> topItemsBySpend(
    AnalyticsWindow window, {
    int limit = 10,
  }) async {
    final rows = await _port.spendByItem(window, limit: limit);
    final out = <ItemSpend>[];
    for (final row in rows) {
      final converted = _convert(row.amountMinor, row.currencyCode, window.to);
      if (converted == null) continue;
      out.add((
        itemId: row.key,
        itemName: row.label,
        amount: converted.converted!,
        purchaseCount: row.count,
      ));
    }
    out.sort((a, b) => b.amount.minor.compareTo(a.amount.minor));
    return out.take(limit).toList();
  }

  /// Query 10 — the top [limit] items by quantity bought.
  ///
  /// Not converted and not cross-compared: quantities in different categories are not comparable at
  /// all (Law L8), so this returns each item's own `Qty` and leaves ranking within a category to the
  /// caller. Sorting grams against pieces would produce a chart that means nothing.
  Future<List<ItemQuantity>> topItemsByQuantity(
    AnalyticsWindow window, {
    int limit = 10,
  }) async {
    final rows = await _port.quantityByItem(window, limit: limit);
    return rows
        .map(
          (row) => (
            itemId: row.key,
            itemName: row.label,
            quantity: Qty(row.milliBase, _categoryFrom(row.category)),
            purchaseCount: row.count,
          ),
        )
        .toList();
  }

  /// Query 11 — the dearest single purchase of [itemId].
  Future<DearestPurchase?> dearestPurchaseOfItem(
    String itemId,
    String itemName,
    AnalyticsWindow window,
  ) async {
    final row = await _port.dearestPurchase(itemId, window);
    if (row == null) return null;
    return (
      itemId: itemId,
      itemName: itemName,
      // The original currency, not converted: "the most I ever paid" is a fact about that purchase,
      // and restating it at today's rate would change a historical figure.
      unitPrice: Money(row.unitPriceMinor, row.currencyCode),
      on: DateKey(row.dateKey),
      transactionId: row.transactionId,
    );
  }

  /// Query 12 — one item's unit-price trend, and the percentage change across it.
  ///
  /// The personal-inflation insight: *"your potatoes cost 34% more than in January"*. The change is
  /// computed from the first and last observation of **price per base unit**, which is what makes it
  /// comparable across purchases made in different units — 2 kg and 500 g are the same measurement
  /// once both are per gram.
  Future<UnitPriceTrend> unitPriceTrend(
    String itemId,
    String itemName,
    AnalyticsWindow window,
  ) async {
    final points = await pricePerBaseUnitHistory(itemId, window);
    double? change;
    if (points.length >= 2) {
      final first = points.first.pricePerBaseUnit;
      final last = points.last.pricePerBaseUnit;
      if (first > 0) change = (last - first) / first;
    }
    return (
      itemId: itemId,
      itemName: itemName,
      points: points,
      percentChange: change,
    );
  }

  /// Query 24 — price per base unit for [itemId], oldest first.
  ///
  /// `lineAmountMinor / (quantityMilli / 1000)`, exactly as ARCH_3 §5.1 specifies. Lines with no
  /// amount or no quantity are skipped rather than treated as zero — a zero price would drag the
  /// trend down and read as a bargain that never happened.
  Future<List<UnitPricePoint>> pricePerBaseUnitHistory(
    String itemId,
    AnalyticsWindow window,
  ) async {
    final rows = await _port.itemPurchaseHistory(itemId, window);
    final points = <UnitPricePoint>[];
    for (final row in rows) {
      if (row.milliBase <= 0) continue;
      final baseUnits = row.milliBase / 1000;
      points.add((
        on: DateKey(row.dateKey),
        lineAmount: Money(row.lineAmountMinor, row.currencyCode),
        quantity: Qty(row.milliBase, _categoryFrom(row.category)),
        pricePerBaseUnit: row.lineAmountMinor / baseUnits,
      ));
    }
    return points;
  }

  // ── 13-16: inventory ──────────────────────────────────────────────────────────────────

  /// Query 13 — inventory value on hand, per currency.
  ///
  /// `unitCostMinor x (remainingMilli / unitFactorToBaseMilli)`, truncated.
  ///
  /// **Dividing by the unit's factor and not by 1000 is the whole of this calculation.**
  /// `Batch.unitCost` is cost per `unitCodeAtPurchase` — ₹50 per *kilogram*, not per gram — so the
  /// quantity has to be expressed in that same unit before multiplying. Dividing by 1000 instead
  /// happens to be right when the purchase unit is the base unit and is wrong by a factor of a
  /// thousand for kilograms or litres, which is the kind of error that looks plausible on screen.
  Future<InventoryValue> inventoryValueOnHand() async {
    final batches = await _port.valuedBatches();
    final byCode = <String, int>{};
    for (final batch in batches) {
      // A zero or missing factor would divide by zero; skipping is right because a batch whose unit
      // cannot be resolved has no computable value, and counting it as zero would understate the total
      // while looking complete.
      if (batch.unitFactorToBaseMilli <= 0) continue;
      final value =
          (batch.unitCostMinor *
                  batch.remainingMilli /
                  batch.unitFactorToBaseMilli)
              .truncate();
      byCode.update(
        batch.currencyCode,
        (v) => v + value,
        ifAbsent: () => value,
      );
    }
    return (
      byCurrency: {
        for (final e in byCode.entries) e.key: Money(e.value, e.key),
      },
      batchesValued: batches.length,
      // Reported rather than hidden: a valuation that silently omitted uncosted stock would look
      // complete while understating what is on the shelf.
      batchesNoCost: await _port.batchesWithoutCost(),
    );
  }

  /// Query 14 — food waste, in quantity and money.
  Future<List<ItemWasteTotal>> wasteTotals(AnalyticsWindow window) async {
    final movements = await _port.wasteMovements(window);
    final byItem =
        <
          String,
          ({String name, int milli, String category, Map<String, int> cost})
        >{};

    for (final m in movements) {
      final current =
          byItem[m.itemId] ??
          (
            name: m.itemName,
            milli: 0,
            category: m.category,
            cost: <String, int>{},
          );
      final cost = current.cost;
      final unitCost = m.unitCostMinor;
      final code = m.currencyCode;
      final factor = m.unitFactorToBaseMilli;
      if (unitCost != null && code != null && factor != null && factor > 0) {
        // Same per-purchase-unit rule as query 13.
        final value = (unitCost * m.milliBase / factor).truncate();
        cost.update(code, (v) => v + value, ifAbsent: () => value);
      }
      byItem[m.itemId] = (
        name: current.name,
        milli: current.milli + m.milliBase,
        category: current.category,
        cost: cost,
      );
    }

    return byItem.entries
        .map(
          (e) => (
            itemId: e.key,
            itemName: e.value.name,
            quantity: Qty(e.value.milli, _categoryFrom(e.value.category)),
            costByCurrency: {
              for (final c in e.value.cost.entries)
                c.key: Money(c.value, c.key),
            },
          ),
        )
        .toList();
  }

  /// Query 15 — batches expiring within [days] of today.
  Future<List<ExpiringBatch>> itemsExpiringWithin(int days) async {
    final today = _port.today();
    final rows = await _port.expiringBatches((
      from: today,
      to: today.addDays(days),
    ));
    return rows
        .map(
          (row) => (
            batchId: row.batchId,
            itemId: row.itemId,
            itemName: row.itemName,
            remaining: Qty(row.remainingMilli, _categoryFrom(row.category)),
            expiry: DateKey(row.expiryDateKey),
            daysLeft: DateKey(row.expiryDateKey).diffDays(today),
          ),
        )
        .toList()
      ..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
  }

  /// Query 16 — how many items are low on stock, as one point in a series.
  ///
  /// One point, not a history. `v_low_stock` reflects the present, and stock levels are not
  /// versioned — reconstructing "how many were low last Tuesday" would mean replaying the movement
  /// ledger against thresholds that may since have changed, which would be a different query and a
  /// far more expensive one. The caller samples this daily and stores the series if it wants a trend.
  Future<LowStockPoint> lowStockCountToday() async =>
      (date: _port.today(), itemCount: await _port.lowStockCount());

  // ── 17-20: commitments and assets ─────────────────────────────────────────────────────

  /// Query 17 — the fixed monthly commitment total.
  ///
  /// Normalises every interval to a monthly figure so a weekly bill and an annual one are comparable:
  /// weekly x 52/12, yearly / 12, daily x 365/12. Integer division truncates, so the total is
  /// slightly conservative rather than optimistic — which is the right direction for a number a user
  /// budgets against.
  Future<MonthlyCommitment> monthlyCommitmentTotal() async {
    final templates = await _port.activeCommitments();
    var total = 0;
    var counted = 0;
    var approximate = 0;
    var unconverted = 0;
    final today = _port.today();

    for (final t in templates) {
      final monthly = _toMonthlyMinor(
        amountMinor: t.defaultAmountMinor,
        intervalUnit: t.intervalUnit,
        intervalCount: t.intervalCount,
      );
      final converted = _convert(monthly, t.currencyCode, today);
      if (converted == null) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate++;
      total += converted.converted!.minor;
      counted++;
    }

    return (
      total: Money(total, _home),
      templateCount: counted,
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );
  }

  /// Query 18 — the recurring against discretionary split.
  Future<RecurringSplit> recurringVsDiscretionary(
    AnalyticsWindow window,
  ) async {
    final rows = await _port.spendByRecurringFlag(window);
    var recurring = 0;
    var discretionary = 0;
    var approximate = 0;
    var unconverted = 0;

    for (final row in rows) {
      final converted = _convert(row.amountMinor, row.currencyCode, window.to);
      if (converted == null) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate++;
      if (row.key == 'recurring') {
        recurring += converted.converted!.minor;
      } else {
        discretionary += converted.converted!.minor;
      }
    }

    final total = recurring + discretionary;
    return (
      recurring: Money(recurring, _home),
      discretionary: Money(discretionary, _home),
      recurringShare: total == 0 ? 0.0 : recurring / total,
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );
  }

  /// Query 19 — lifetime service cost per asset, per currency.
  Future<List<AssetServiceCost>> lifetimeServiceCostByAsset(
    AnalyticsWindow window,
  ) async {
    final rows = await _port.serviceCostByAsset(window);
    final byAsset =
        <String, ({String name, Map<String, int> cost, int count})>{};

    for (final row in rows) {
      final current =
          byAsset[row.assetId] ??
          (name: row.assetName, cost: <String, int>{}, count: 0);
      current.cost.update(
        row.currencyCode,
        (v) => v + row.costMinor,
        ifAbsent: () => row.costMinor,
      );
      byAsset[row.assetId] = (
        name: current.name,
        cost: current.cost,
        count: current.count + row.count,
      );
    }

    return byAsset.entries
        .map(
          (e) => (
            assetId: e.key,
            assetName: e.value.name,
            byCurrency: {
              for (final c in e.value.cost.entries)
                c.key: Money(c.value, c.key),
            },
            serviceCount: e.value.count,
          ),
        )
        .toList();
  }

  /// Query 20 — the warranty coverage timeline.
  Future<List<WarrantyCoverage>> warrantyCoverage() async {
    final rows = await _port.warrantyWindows();
    final today = _port.today();
    return rows.map((row) {
      final end = row.endDateKey == null ? null : DateKey(row.endDateKey!);
      final start = row.startDateKey == null
          ? null
          : DateKey(row.startDateKey!);
      final daysLeft = end?.diffDays(today);
      return (
        assetId: row.assetId,
        assetName: row.assetName,
        start: start,
        end: end,
        daysLeft: daysLeft,
        isCovered:
            end != null &&
            !end.isBefore(today) &&
            (start == null || !today.isBefore(start)),
      );
    }).toList();
  }

  // ── shared ────────────────────────────────────────────────────────────────────────────

  /// Converts one raw subtotal, or null when it cannot be converted at all.
  ConvertedMoney? _convert(int minor, String currencyCode, DateKey on) {
    final result = _rates.convert(
      amount: Money(minor, currencyCode),
      toCurrencyCode: _home,
      on: on,
    );
    return result.isExcludedFromTotals ? null : result;
  }

  MoneySeries _toSeries(List<RawMoneyRow> rows, DateKey on) {
    final byKey = <String, ({String label, int minor})>{};
    var approximate = 0;
    var unconverted = 0;

    for (final row in rows) {
      final converted = _convert(row.amountMinor, row.currencyCode, on);
      if (converted == null) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate++;
      final current = byKey[row.key] ?? (label: row.label, minor: 0);
      byKey[row.key] = (
        label: current.label,
        minor: current.minor + converted.converted!.minor,
      );
    }

    final slices =
        byKey.entries
            .map(
              (e) => (
                label: e.value.label,
                key: e.key,
                amount: Money(e.value.minor, _home),
              ),
            )
            .toList()
          ..sort((a, b) => b.amount.minor.compareTo(a.amount.minor));

    return (
      slices: slices,
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );
  }

  MonthSeries _toMonthSeries(List<RawMonthRow> rows) {
    final byMonth = <int, int>{};
    var approximate = 0;
    var unconverted = 0;

    for (final row in rows) {
      final converted = _convert(
        row.amountMinor,
        row.currencyCode,
        _monthEnd(row.monthKey),
      );
      if (converted == null) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate++;
      byMonth.update(
        row.monthKey,
        (v) => v + converted.converted!.minor,
        ifAbsent: () => converted.converted!.minor,
      );
    }

    final points =
        byMonth.entries
            .map((e) => (monthKey: e.key, amount: Money(e.value, _home)))
            .toList()
          ..sort((a, b) => a.monthKey.compareTo(b.monthKey));

    return (
      points: points,
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );
  }

  ShareOfTotal? _shareOf(MoneySeries series, String key) {
    final total = series.slices.fold<int>(0, (sum, s) => sum + s.amount.minor);
    for (final slice in series.slices) {
      if (slice.key != key) continue;
      return (
        key: slice.key,
        label: slice.label,
        amount: slice.amount,
        share: total == 0 ? 0.0 : slice.amount.minor / total,
      );
    }
    return null;
  }

  /// A month's last day, used as the conversion date for a monthly subtotal.
  ///
  /// A month's spend is not one instant, so no single rate is exactly right. The month end is the
  /// defensible choice: it is the date by which every transaction in the bucket had happened, and it
  /// is stable — using "today" would make a closed month's figure drift every time it was reopened.
  DateKey _monthEnd(int monthKey) {
    final year = monthKey ~/ 100;
    final month = monthKey % 100;
    return DateKey.fromYmd(year, month, DateTime.utc(year, month + 1, 0).day);
  }

  /// Normalises a recurring amount to a monthly equivalent in minor units.
  int _toMonthlyMinor({
    required int amountMinor,
    required String intervalUnit,
    required int intervalCount,
  }) {
    final perInterval = intervalCount <= 0 ? 1 : intervalCount;
    switch (intervalUnit) {
      case 'day':
        return (amountMinor * 365 / (12 * perInterval)).truncate();
      case 'week':
        return (amountMinor * 52 / (12 * perInterval)).truncate();
      case 'month':
        return amountMinor ~/ perInterval;
      case 'year':
        return amountMinor ~/ (12 * perInterval);
      default:
        return amountMinor;
    }
  }

  /// Maps a stored category name back to its enum, defaulting to `count`.
  ///
  /// Defaulting rather than throwing: an unrecognised name means the database holds a value this
  /// build does not know, which is exactly what `SafeEnumConverter` exists to survive (Law L13). A
  /// wrong category on an analytics label is a cosmetic error; a crash on the analytics screen is not.
  UnitCategory _categoryFrom(String name) {
    for (final category in UnitCategory.values) {
      if (category.name == name) return category;
    }
    return UnitCategory.count;
  }
}
