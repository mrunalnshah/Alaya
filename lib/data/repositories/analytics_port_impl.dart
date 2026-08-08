import 'package:drift/drift.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/services/analytics/analytics_port.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';

/// `AnalyticsPort` over SQL — the adapter Law L12 requires and ARCH_3 §5.2 demands.
///
/// **Aggregation happens here and nowhere else.** §5.2's rule is that nothing is loaded into Dart to
/// be summed, while L12 forbids `domain/` importing drift; the port declared in `domain/` is what
/// lets both hold, and this is its one implementation.
///
/// Every method returns rows **grouped by currency, unconverted**. A SQL-side `SUM` across
/// currencies would already have destroyed the information `AnalyticsService` needs to convert per
/// data point, so a query that looks like it is missing a total is doing the one thing that keeps
/// the total correct.
///
/// Written as `customSelect` rather than as a DAO of generated queries because the twenty-four
/// aggregates share almost no shape with one another and several need SQL the query builder cannot
/// express — a weekday bucket, a unit-normalised ordering, a `NOT EXISTS` against the same table.
/// `readsFrom` is omitted throughout: every method returns a `Future` through `.get()`, and that set
/// only affects which writes re-trigger a `.watch()`.
final class AnalyticsPortImpl implements AnalyticsPort {
  /// Creates the adapter over [database], taking "today" from [clock].
  const AnalyticsPortImpl(this._database, this._clock);

  final AlayaDatabase _database;
  final Clock _clock;

  /// How far past [limit] a ranked query fetches before `AnalyticsService` re-ranks.
  ///
  /// SQL orders by raw minor units, which is the wrong order across currencies — so a query that
  /// limited to exactly [limit] would discard rows the service is about to promote. Four covers a
  /// household holding four currencies, which is more than the app's seeded five allows for in
  /// practice.
  static const int _currencySpread = 4;

  /// Spend is `withdrawal` and only `withdrawal`, in every query in this file.
  ///
  /// A transfer moves money between the user's own accounts and an adjustment is a bookkeeping
  /// correction; counting either as spending would double the first and invent the second
  /// (anomaly A33, and the same rule 6F's range rows apply).
  static const String _spendKind = 'withdrawal';

  // ── 1-8, 21-23: money over transactions ───────────────────────────────────────────────

  @override
  Future<List<RawMoneyRow>> spendBySubtype(AnalyticsWindow window) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT t.subtype AS group_key,
             t.subtype AS group_label,
             SUM(t.original_amount_minor) AS amount_minor,
             t.original_currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM v_active_transactions t
       WHERE t.kind = ?
         AND t.date_key BETWEEN ? AND ?
       GROUP BY t.subtype, t.original_currency_code
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows.map(_moneyRow).toList();
  }

  @override
  Future<List<RawMoneyRow>> spendByTag(AnalyticsWindow window) async {
    // `tags.deleted_at` is deliberately not filtered: a deleted tag still labels the transactions it
    // was on (anomaly A36), and excluding it would shrink a historical total with no visible cause.
    // `transaction_tags` has no `deleted_at` to filter — it is a composite-key link table
    // (ARCH_2 §4).
    //
    // A transaction carrying two tags contributes to both slices, so these slices do not sum to
    // total spend. That is inherent to grouping by a many-to-many label, and the UI says so rather
    // than presenting the slices as a partition.
    final rows = await _database
        .customSelect(
          '''
      SELECT tg.id AS group_key,
             tg.name AS group_label,
             SUM(t.original_amount_minor) AS amount_minor,
             t.original_currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM v_active_transactions t
        JOIN transaction_tags tt ON tt.transaction_id = t.tx_id
        JOIN tags tg ON tg.id = tt.tag_id
       WHERE t.kind = ?
         AND t.date_key BETWEEN ? AND ?
       GROUP BY tg.id, t.original_currency_code
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows.map(_moneyRow).toList();
  }

  @override
  Future<List<RawMoneyRow>> spendByPaymentMethod(AnalyticsWindow window) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT t.payment_method_id AS group_key,
             t.payment_method_name AS group_label,
             SUM(t.original_amount_minor) AS amount_minor,
             t.original_currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM v_active_transactions t
       WHERE t.kind = ?
         AND t.payment_method_id IS NOT NULL
         AND t.date_key BETWEEN ? AND ?
       GROUP BY t.payment_method_id, t.original_currency_code
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows.map(_moneyRow).toList();
  }

  @override
  Future<List<RawMoneyRow>> spendByPayee(
    AnalyticsWindow window, {
    int limit = 10,
  }) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT t.payee_id AS group_key,
             t.payee_name AS group_label,
             SUM(t.original_amount_minor) AS amount_minor,
             t.original_currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM v_active_transactions t
       WHERE t.kind = ?
         AND t.payee_id IS NOT NULL
         AND t.date_key BETWEEN ? AND ?
       GROUP BY t.payee_id, t.original_currency_code
       ORDER BY amount_minor DESC
       LIMIT ?
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
            Variable<int>(limit * _currencySpread),
          ],
        )
        .get();
    return rows.map(_moneyRow).toList();
  }

  @override
  Future<List<RawMonthRow>> totalsByMonthAndKind(
    AnalyticsWindow window,
    TransactionKind kind,
  ) async {
    // Bounded on `date_key` and grouped by `month_key`, rather than read from `v_monthly_totals`.
    // That view carries no `date_key`, so bounding it means comparing month keys — which turns a
    // 30-day window into two whole months and reports spending from outside the window the caller
    // asked for. Enum *name*, not index: Law L13 makes the name the schema contract.
    final rows = await _database
        .customSelect(
          '''
      SELECT t.month_key AS month_key,
             SUM(t.original_amount_minor) AS amount_minor,
             t.original_currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM v_active_transactions t
       WHERE t.kind = ?
         AND t.date_key BETWEEN ? AND ?
       GROUP BY t.month_key, t.original_currency_code
       ORDER BY t.month_key
      ''',
          variables: [
            Variable<String>(kind.name),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows.map(_monthRow).toList();
  }

  @override
  Future<List<RawMonthRow>> netFlowByMonth(AnalyticsWindow window) async {
    // `v_account_ledger` expands a transfer into two legs with opposite signs, so a self-transfer
    // nets to zero here without this query knowing anything about transfers (ARCH_2 §12.1). That
    // property is the whole reason net flow reads the ledger rather than the transactions.
    final rows = await _database
        .customSelect(
          '''
      SELECT (l.date_key / 100) AS month_key,
             SUM(l.signed_minor) AS amount_minor,
             l.currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM v_account_ledger l
       WHERE l.date_key BETWEEN ? AND ?
       GROUP BY month_key, l.currency_code
       ORDER BY month_key
      ''',
          variables: [
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows.map(_monthRow).toList();
  }

  @override
  Future<List<RawDateRow>> ledgerLegsForAccount(
    String accountId,
    AnalyticsWindow window,
  ) async {
    // **The first row is synthetic, and it is what makes a windowed trend correct.**
    // `openingBalance` takes no window, so a trend over anything narrower than all time would
    // otherwise start at the account's opening figure and jump on the first in-window leg. This row
    // carries the sum of every leg strictly before the window, dated at the window's start, with
    // `count` reporting how many legs it condenses — which is what `count` is for on this record.
    //
    // Emitted only when there is something to carry, so an account whose history starts inside the
    // window is unaffected.
    final carried = await _database
        .customSelect(
          '''
      SELECT COALESCE(SUM(l.signed_minor), 0) AS amount_minor,
             COUNT(*) AS row_count
        FROM v_account_ledger l
       WHERE l.account_id = ?
         AND l.date_key < ?
      ''',
          variables: [
            Variable<String>(accountId),
            Variable<int>(window.from.value),
          ],
        )
        .getSingle();

    final legs = await _database
        .customSelect(
          '''
      SELECT l.date_key AS date_key,
             l.signed_minor AS amount_minor,
             l.currency_code AS currency_code,
             1 AS row_count
        FROM v_account_ledger l
       WHERE l.account_id = ?
         AND l.date_key BETWEEN ? AND ?
       ORDER BY l.date_key, l.tx_id
      ''',
          variables: [
            Variable<String>(accountId),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();

    final carriedCount = carried.read<int>('row_count');
    final mapped = legs.map(_dateRow).toList();
    if (carriedCount == 0) return mapped;

    // The currency comes from the account rather than from the carried legs: `SUM` across a mixed
    // set would be meaningless, and an account holds exactly one currency (ARCH_2 §4).
    final account = await openingBalance(accountId);
    return [
      (
        dateKey: window.from.value,
        amountMinor: carried.read<int>('amount_minor'),
        currencyCode: account?.currencyCode ?? '',
        count: carriedCount,
      ),
      ...mapped,
    ];
  }

  @override
  Future<({int minor, String currencyCode})?> openingBalance(
    String accountId,
  ) async {
    // The base table, not `v_account_balances`: that view returns opening *plus* every leg, which is
    // the current balance. A running trend has to start before the legs it is about to add.
    final row = await _database
        .customSelect(
          '''
      SELECT a.opening_balance_minor AS minor,
             a.currency_code AS currency_code
        FROM accounts a
       WHERE a.id = ?
         AND a.deleted_at IS NULL
      ''',
          variables: [Variable<String>(accountId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return (
      minor: row.read<int>('minor'),
      currencyCode: row.read<String>('currency_code'),
    );
  }

  @override
  Future<List<RawMoneyRow>> totalSpend(AnalyticsWindow window) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT 'total' AS group_key,
             'total' AS group_label,
             SUM(t.original_amount_minor) AS amount_minor,
             t.original_currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM v_active_transactions t
       WHERE t.kind = ?
         AND t.date_key BETWEEN ? AND ?
       GROUP BY t.original_currency_code
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows.map(_moneyRow).toList();
  }

  @override
  Future<List<RawBucketRow>> spendByBucket(
    AnalyticsWindow window, {
    required bool byWeekday,
  }) async {
    // The bucket expression is chosen in Dart and interpolated, because it appears in both `SELECT`
    // and `GROUP BY` and SQLite will not group by a bound parameter. Neither branch contains
    // anything a caller supplied, so there is nothing to inject.
    //
    // `date_key` is an `INTEGER yyyymmdd`, so a weekday needs a real date first: `printf` rebuilds
    // the ISO string and `strftime('%w')` reads it. That returns 0 for Sunday, and ARCH_3 §5.1 wants
    // 1-7 Monday first, hence `(w + 6) % 7 + 1` — which maps Sunday's 0 to 7 and Monday's 1 to 1.
    //
    // No current time is involved, so ARCH_2 §12.2's ban on `now` in a read is untouched.
    const weekdayBucket =
        "((CAST(strftime('%w', printf('%04d-%02d-%02d', "
        't.date_key / 10000, (t.date_key / 100) % 100, t.date_key % 100)) '
        'AS INTEGER) + 6) % 7) + 1';
    const dayOfMonthBucket = 't.date_key % 100';
    final bucket = byWeekday ? weekdayBucket : dayOfMonthBucket;

    final rows = await _database
        .customSelect(
          '''
      SELECT $bucket AS bucket,
             SUM(t.original_amount_minor) AS amount_minor,
             t.original_currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM v_active_transactions t
       WHERE t.kind = ?
         AND t.date_key BETWEEN ? AND ?
       GROUP BY bucket, t.original_currency_code
       ORDER BY bucket
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows
        .map(
          (row) => (
            bucket: row.read<int>('bucket'),
            amountMinor: row.read<int>('amount_minor'),
            currencyCode: row.read<String>('currency_code'),
            count: row.read<int>('row_count'),
          ),
        )
        .toList();
  }

  @override
  Future<List<({int amountMinor, String currencyCode, int lineCount})>>
  groceryBaskets(
    AnalyticsWindow window,
  ) async {
    // One row per basket, not an aggregate: `AnalyticsService.averageGroceryBasket` averages over the
    // baskets that *converted*, which it cannot do from a pre-summed total.
    final rows = await _database
        .customSelect(
          '''
      SELECT t.original_amount_minor AS amount_minor,
             t.original_currency_code AS currency_code,
             (SELECT COUNT(*) FROM transaction_lines l
               WHERE l.transaction_id = t.tx_id AND l.deleted_at IS NULL) AS line_count
        FROM v_active_transactions t
       WHERE t.kind = ?
         AND t.subtype = ?
         AND t.date_key BETWEEN ? AND ?
       ORDER BY t.date_key
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<String>(TransactionSubtype.grocery.name),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows
        .map(
          (row) => (
            amountMinor: row.read<int>('amount_minor'),
            currencyCode: row.read<String>('currency_code'),
            lineCount: row.read<int>('line_count'),
          ),
        )
        .toList();
  }

  // ── 9-12, 24: items and prices ────────────────────────────────────────────────────────

  @override
  Future<List<RawMoneyRow>> spendByItem(
    AnalyticsWindow window, {
    int limit = 10,
  }) async {
    // The line's currency is the parent transaction's `original_currency_code`: a line has no
    // currency column of its own (ARCH_2 §1.x). Joining `v_active_transactions` rather than
    // `transactions` is what supplies the parent's `deleted_at IS NULL` — L7 doing its job even in a
    // query the views do not otherwise serve.
    final rows = await _database
        .customSelect(
          '''
      SELECT l.item_id AS group_key,
             i.name AS group_label,
             SUM(l.line_amount_minor) AS amount_minor,
             t.original_currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM transaction_lines l
        JOIN v_active_transactions t ON t.tx_id = l.transaction_id
        JOIN items i ON i.id = l.item_id
       WHERE l.deleted_at IS NULL
         AND i.deleted_at IS NULL
         AND l.line_amount_minor IS NOT NULL
         AND t.kind = ?
         AND t.date_key BETWEEN ? AND ?
       GROUP BY l.item_id, t.original_currency_code
       ORDER BY amount_minor DESC
       LIMIT ?
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
            Variable<int>(limit * _currencySpread),
          ],
        )
        .get();
    return rows.map(_moneyRow).toList();
  }

  @override
  Future<List<RawQuantityRow>> quantityByItem(
    AnalyticsWindow window, {
    int limit = 10,
  }) async {
    // `transaction_lines.quantity_milli` is already base-milli (Law L2), so no unit join is needed
    // here — unlike the batch queries, where the *cost* is per purchase unit. `unit_code` records
    // what the user typed; the quantity is stored normalised.
    //
    // Ordered by category first: Law L8 makes grams and pieces incomparable, so a single
    // `ORDER BY milli_base DESC` would return ten weights and drop the most-bought item in the
    // house because pieces carry smaller numbers. The service does not re-rank; the UI groups.
    final rows = await _database
        .customSelect(
          '''
      SELECT l.item_id AS group_key,
             i.name AS group_label,
             SUM(l.quantity_milli) AS milli_base,
             i.unit_category AS category,
             COUNT(*) AS row_count
        FROM transaction_lines l
        JOIN v_active_transactions t ON t.tx_id = l.transaction_id
        JOIN items i ON i.id = l.item_id
       WHERE l.deleted_at IS NULL
         AND i.deleted_at IS NULL
         AND l.quantity_milli IS NOT NULL
         AND l.quantity_milli > 0
         AND t.kind = ?
         AND t.date_key BETWEEN ? AND ?
       GROUP BY l.item_id
       ORDER BY i.unit_category, milli_base DESC
       LIMIT ?
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
            Variable<int>(limit * _currencySpread),
          ],
        )
        .get();
    return rows
        .map(
          (row) => (
            key: row.read<String>('group_key'),
            label: row.read<String>('group_label'),
            milliBase: row.read<int>('milli_base'),
            category: row.read<String>('category'),
            count: row.read<int>('row_count'),
          ),
        )
        .toList();
  }

  @override
  Future<
    ({
      int unitPriceMinor,
      String currencyCode,
      int dateKey,
      String transactionId,
    })?
  >
  dearestPurchase(String itemId, AnalyticsWindow window) async {
    // **Ordered by the unit-normalised price, returning the recorded one.** `unit_price_minor` is per
    // `transaction_lines.unit_code`, so ordering by it directly makes ₹1/g beat ₹50/kg and the
    // "dearest purchase" becomes whichever line used the smallest unit. This is ARCH_4 R18's defect
    // one row over: R18 closed `inventoryValueOnHand` and `wasteTotals`, and query 11 has it too.
    //
    // The figure returned is still the recorded one, because "the most I ever paid" is a fact about
    // that purchase expressed in the unit it was bought in — restating it per gram would answer a
    // different question.
    //
    // `LEFT JOIN` with a base-unit fallback: a line with no `unit_code` is priced per base unit by
    // definition, and excluding it would hide a purchase rather than rank it.
    final row = await _database
        .customSelect(
          '''
      SELECT l.unit_price_minor AS unit_price_minor,
             t.original_currency_code AS currency_code,
             t.date_key AS date_key,
             t.tx_id AS transaction_id
        FROM transaction_lines l
        JOIN v_active_transactions t ON t.tx_id = l.transaction_id
        LEFT JOIN units u ON u.code = l.unit_code
       WHERE l.deleted_at IS NULL
         AND l.item_id = ?
         AND l.unit_price_minor IS NOT NULL
         AND t.date_key BETWEEN ? AND ?
       ORDER BY (CAST(l.unit_price_minor AS REAL) * 1000.0
                 / COALESCE(NULLIF(u.factor_to_base_milli, 0), 1000)) DESC
       LIMIT 1
      ''',
          variables: [
            Variable<String>(itemId),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return (
      unitPriceMinor: row.read<int>('unit_price_minor'),
      currencyCode: row.read<String>('currency_code'),
      dateKey: row.read<int>('date_key'),
      transactionId: row.read<String>('transaction_id'),
    );
  }

  @override
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
  itemPurchaseHistory(String itemId, AnalyticsWindow window) async {
    // Oldest first, because `AnalyticsService.unitPriceTrend` takes the percentage change from the
    // first and last observation and reversing the order inverts the sign of the headline insight.
    //
    // `quantity_milli` is base-milli, so the service's `lineAmountMinor / (milliBase / 1000)` is
    // already price per base unit and needs no factor. That is the opposite of the batch case, and
    // the difference is that a line stores its quantity normalised while a batch stores its *cost*
    // per purchase unit.
    //
    // Zero-quantity and unpriced lines are excluded rather than sent through as zero: a zero price
    // would drag the trend down and read as a bargain that never happened.
    final rows = await _database
        .customSelect(
          '''
      SELECT t.date_key AS date_key,
             l.line_amount_minor AS line_amount_minor,
             t.original_currency_code AS currency_code,
             l.quantity_milli AS milli_base,
             i.unit_category AS category
        FROM transaction_lines l
        JOIN v_active_transactions t ON t.tx_id = l.transaction_id
        JOIN items i ON i.id = l.item_id
       WHERE l.deleted_at IS NULL
         AND l.item_id = ?
         AND l.line_amount_minor IS NOT NULL
         AND l.quantity_milli IS NOT NULL
         AND l.quantity_milli > 0
         AND t.date_key BETWEEN ? AND ?
       ORDER BY t.date_key, t.occurred_at
      ''',
          variables: [
            Variable<String>(itemId),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows
        .map(
          (row) => (
            dateKey: row.read<int>('date_key'),
            lineAmountMinor: row.read<int>('line_amount_minor'),
            currencyCode: row.read<String>('currency_code'),
            milliBase: row.read<int>('milli_base'),
            category: row.read<String>('category'),
          ),
        )
        .toList();
  }

  // ── 13-16: inventory ──────────────────────────────────────────────────────────────────

  @override
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
  valuedBatches() async {
    // **The R18 join.** `unit_cost_minor` is cost per `unit_code_at_purchase` — ₹50 per *kilogram*,
    // not per gram — so valuing a batch needs that unit's `factor_to_base_milli`, and dividing by
    // 1000 instead values a 2 kg batch at ₹100,000 (ARCH_2 §5.2). The factor is returned rather than
    // the value so the arithmetic stays in the service, where it is unit-tested against literals.
    //
    // **`units.deleted_at` is not filtered, deliberately.** A retired unit's factor is still the
    // correct factor for a batch bought in it, and filtering would drop every such batch from the
    // valuation while the figure still looked complete — R18's failure mode from the other side.
    //
    // `factor_to_base_milli > 0` here and its complement in `batchesWithoutCost` make the two
    // methods exact opposites, so `batchesValued` counts only batches that really were valued.
    final rows = await _database.customSelect(
      '''
      SELECT b.remaining_quantity_milli AS remaining_milli,
             b.unit_cost_minor AS unit_cost_minor,
             b.cost_currency_code AS currency_code,
             u.factor_to_base_milli AS unit_factor_to_base_milli
        FROM inventory_batches b
        JOIN units u ON u.code = b.unit_code_at_purchase
       WHERE b.deleted_at IS NULL
         AND b.remaining_quantity_milli > 0
         AND b.unit_cost_minor IS NOT NULL
         AND b.cost_currency_code IS NOT NULL
         AND u.factor_to_base_milli > 0
      ''',
    ).get();
    return rows
        .map(
          (row) => (
            remainingMilli: row.read<int>('remaining_milli'),
            unitCostMinor: row.read<int>('unit_cost_minor'),
            currencyCode: row.read<String>('currency_code'),
            unitFactorToBaseMilli: row.read<int>('unit_factor_to_base_milli'),
          ),
        )
        .toList();
  }

  @override
  Future<int> batchesWithoutCost() async {
    // The exact complement of `valuedBatches`, including the unresolvable-unit case. A batch whose
    // unit cannot be resolved has no computable value, so counting it as valued would understate the
    // total while reporting a complete valuation.
    final row = await _database.customSelect(
      '''
      SELECT COUNT(*) AS row_count
        FROM inventory_batches b
        LEFT JOIN units u ON u.code = b.unit_code_at_purchase
       WHERE b.deleted_at IS NULL
         AND b.remaining_quantity_milli > 0
         AND (b.unit_cost_minor IS NULL
              OR b.cost_currency_code IS NULL
              OR u.factor_to_base_milli IS NULL
              OR u.factor_to_base_milli <= 0)
      ''',
    ).getSingle();
    return row.read<int>('row_count');
  }

  @override
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
  wasteMovements(AnalyticsWindow window) async {
    // **Reversed movements are excluded, and that is `reverses_movement_id` earning its column.**
    // Undo on a waste entry writes a reversing row rather than deleting the original (ARCH_2 §5.3,
    // ARCH_5 §5.4), so counting the original would report waste the user already corrected — and
    // food-waste analytics that overstates itself is worse than none.
    //
    // No `deleted_at` filter on `stock_movements`: the table has none at all, which is L6's one
    // explicit exception. `inventory_batches.deleted_at` is not filtered either — the waste happened
    // whether or not the batch row was later removed, and its cost is still the cost.
    //
    // The same per-purchase-unit factor as `valuedBatches`, nullable because a movement's batch may
    // carry no cost. All three cost fields travel together so the service can tell "no cost
    // recorded" from "cost of zero".
    final rows = await _database
        .customSelect(
          '''
      SELECT m.item_id AS item_id,
             i.name AS item_name,
             m.quantity_milli AS milli_base,
             i.unit_category AS category,
             b.unit_cost_minor AS unit_cost_minor,
             b.cost_currency_code AS currency_code,
             u.factor_to_base_milli AS unit_factor_to_base_milli
        FROM stock_movements m
        JOIN items i ON i.id = m.item_id
        LEFT JOIN inventory_batches b ON b.id = m.batch_id
        LEFT JOIN units u ON u.code = b.unit_code_at_purchase
       WHERE m.kind IN ('waste', 'expired')
         AND i.deleted_at IS NULL
         AND m.date_key BETWEEN ? AND ?
         AND NOT EXISTS (SELECT 1 FROM stock_movements r
                          WHERE r.reverses_movement_id = m.id)
       ORDER BY m.date_key
      ''',
          variables: [
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows
        .map(
          (row) => (
            itemId: row.read<String>('item_id'),
            itemName: row.read<String>('item_name'),
            milliBase: row.read<int>('milli_base'),
            category: row.read<String>('category'),
            unitCostMinor: row.readNullable<int>('unit_cost_minor'),
            currencyCode: row.readNullable<String>('currency_code'),
            unitFactorToBaseMilli: row.readNullable<int>(
              'unit_factor_to_base_milli',
            ),
          ),
        )
        .toList();
  }

  @override
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
  expiringBatches(AnalyticsWindow window) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT b.id AS batch_id,
             b.item_id AS item_id,
             i.name AS item_name,
             b.remaining_quantity_milli AS remaining_milli,
             i.unit_category AS category,
             b.expiry_date_key AS expiry_date_key
        FROM inventory_batches b
        JOIN items i ON i.id = b.item_id
       WHERE b.deleted_at IS NULL
         AND i.deleted_at IS NULL
         AND b.remaining_quantity_milli > 0
         AND b.expiry_date_key IS NOT NULL
         AND b.expiry_date_key BETWEEN ? AND ?
       ORDER BY b.expiry_date_key
      ''',
          variables: [
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows
        .map(
          (row) => (
            batchId: row.read<String>('batch_id'),
            itemId: row.read<String>('item_id'),
            itemName: row.read<String>('item_name'),
            remainingMilli: row.read<int>('remaining_milli'),
            category: row.read<String>('category'),
            expiryDateKey: row.read<int>('expiry_date_key'),
          ),
        )
        .toList();
  }

  @override
  Future<int> lowStockCount() async {
    // `v_low_stock` reflects the present and stock is not versioned, which is why query 16 is one
    // point rather than a history (ARCH_3 §5.2's note, and the service says the same).
    final row = await _database
        .customSelect(
          'SELECT COUNT(*) AS row_count FROM v_low_stock',
        )
        .getSingle();
    return row.read<int>('row_count');
  }

  // ── 17-20: commitments and assets ─────────────────────────────────────────────────────

  @override
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
  activeCommitments() async {
    // **The base table, not `v_recurring_due`.** That view LEFT JOINs occurrences where
    // `status = 'due'`, and `idx_recurring_occ` is unique on `(template_id, due_date_key)` rather
    // than on the template — so a template with two outstanding dues appears twice and its
    // commitment would be counted twice. The view is right for a due list and wrong for a total.
    //
    // `direction = 'outflow'` because query 17 is a *commitment* total: netting salary against rent
    // would report a household with a surplus as having no fixed costs.
    //
    // An ended template is excluded, which needs today — from the injected clock, never
    // `DateTime.now()`.
    final rows = await _database
        .customSelect(
          '''
      SELECT rt.default_amount_minor AS default_amount_minor,
             rt.currency_code AS currency_code,
             rt.interval_unit AS interval_unit,
             rt.interval_count AS interval_count
        FROM recurring_templates rt
       WHERE rt.deleted_at IS NULL
         AND rt.is_paused = 0
         AND rt.direction = 'outflow'
         AND (rt.end_date_key IS NULL OR rt.end_date_key >= ?)
      ''',
          variables: [Variable<int>(_clock.today().value)],
        )
        .get();
    return rows
        .map(
          (row) => (
            defaultAmountMinor: row.read<int>('default_amount_minor'),
            currencyCode: row.read<String>('currency_code'),
            intervalUnit: row.read<String>('interval_unit'),
            intervalCount: row.read<int>('interval_count'),
          ),
        )
        .toList();
  }

  @override
  Future<List<RawMoneyRow>> spendByRecurringFlag(AnalyticsWindow window) async {
    // The keys are the literals `AnalyticsService.recurringVsDiscretionary` compares against, so
    // they are spelled here exactly as it reads them. A rename on either side silently routes every
    // rupee into `discretionary`, which is why they are worth stating rather than deriving.
    final rows = await _database
        .customSelect(
          '''
      SELECT CASE WHEN t.recurring_template_id IS NULL THEN 'discretionary' ELSE 'recurring' END
               AS group_key,
             CASE WHEN t.recurring_template_id IS NULL THEN 'discretionary' ELSE 'recurring' END
               AS group_label,
             SUM(t.original_amount_minor) AS amount_minor,
             t.original_currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM v_active_transactions t
       WHERE t.kind = ?
         AND t.date_key BETWEEN ? AND ?
       GROUP BY group_key, t.original_currency_code
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows.map(_moneyRow).toList();
  }

  @override
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
  serviceCostByAsset(AnalyticsWindow window) async {
    // Disposed assets are included, and that is the point of `status = disposed` rather than a
    // delete (ARCH_2 §8.1): the ₹45,000 of servicing you put into a TV stays in the analytics after
    // you sell it. "Lifetime" would be a strange word for a figure that vanished on disposal.
    final rows = await _database
        .customSelect(
          '''
      SELECT sr.asset_id AS asset_id,
             a.name AS asset_name,
             SUM(sr.cost_minor) AS cost_minor,
             sr.currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM service_records sr
        JOIN assets a ON a.id = sr.asset_id
       WHERE sr.deleted_at IS NULL
         AND a.deleted_at IS NULL
         AND sr.cost_minor IS NOT NULL
         AND sr.currency_code IS NOT NULL
         AND sr.service_date_key BETWEEN ? AND ?
       GROUP BY sr.asset_id, sr.currency_code
      ''',
          variables: [
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows
        .map(
          (row) => (
            assetId: row.read<String>('asset_id'),
            assetName: row.read<String>('asset_name'),
            costMinor: row.read<int>('cost_minor'),
            currencyCode: row.read<String>('currency_code'),
            count: row.read<int>('row_count'),
          ),
        )
        .toList();
  }

  @override
  Future<
    List<
      ({String assetId, String assetName, int? startDateKey, int? endDateKey})
    >
  >
  warrantyWindows() async {
    // `v_asset_alerts` carries `warranty_end_date_key` and not `warranty_start_date_key`, so a
    // coverage *timeline* cannot be built from it. Disposed assets are excluded here — unlike the
    // service-cost query — because a warranty on something you no longer own covers nothing, which
    // is the same judgement the view makes.
    final rows = await _database.customSelect(
      '''
      SELECT a.id AS asset_id,
             a.name AS asset_name,
             a.warranty_start_date_key AS start_date_key,
             a.warranty_end_date_key AS end_date_key
        FROM assets a
       WHERE a.deleted_at IS NULL
         AND a.status <> 'disposed'
         AND (a.warranty_start_date_key IS NOT NULL OR a.warranty_end_date_key IS NOT NULL)
       ORDER BY a.warranty_end_date_key
      ''',
    ).get();
    return rows
        .map(
          (row) => (
            assetId: row.read<String>('asset_id'),
            assetName: row.read<String>('asset_name'),
            startDateKey: row.readNullable<int>('start_date_key'),
            endDateKey: row.readNullable<int>('end_date_key'),
          ),
        )
        .toList();
  }

  @override
  DateKey today() => _clock.today();

  // ── row mappers ───────────────────────────────────────────────────────────────────────
  //
  // One per raw record shape. Named rather than inlined because ARCH_4 R19 makes an inline record
  // type structurally matched and nothing else — so a field added to `RawMoneyRow` should break in
  // one place here, not in eleven query bodies.

  RawMoneyRow _moneyRow(QueryRow row) => (
    key: row.read<String>('group_key'),
    // `group_label` is nullable wherever it comes from a LEFT JOIN in the view — a payee or a
    // payment method the transaction did not name. The key is filtered NOT NULL in those
    // queries, so an empty label means the joined row is gone rather than absent.
    label: row.readNullable<String>('group_label') ?? '',
    amountMinor: row.read<int>('amount_minor'),
    currencyCode: row.read<String>('currency_code'),
    count: row.read<int>('row_count'),
  );

  RawMonthRow _monthRow(QueryRow row) => (
    monthKey: row.read<int>('month_key'),
    amountMinor: row.read<int>('amount_minor'),
    currencyCode: row.read<String>('currency_code'),
    count: row.read<int>('row_count'),
  );

  RawDateRow _dateRow(QueryRow row) => (
    dateKey: row.read<int>('date_key'),
    amountMinor: row.read<int>('amount_minor'),
    currencyCode: row.read<String>('currency_code'),
    count: row.read<int>('row_count'),
  );
}
