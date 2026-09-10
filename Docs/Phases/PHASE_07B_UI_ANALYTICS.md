# PHASE 7B — AnalyticsPort adapter, AnalyticsCacheRepository & the Analytics UI

`AnalyticsPort` was declared in `domain/` by Phase 4C and implemented by no phase;
`AnalyticsCacheRepository` was declared in Phase 3A and implemented by no phase. Between them they
left `AnalyticsService` and `AnalyticsCacheService` without providers (ARCH_4 §5.1 item 15). Both are
closed first, because no chart can be drawn over an engine that cannot be constructed.

## Dependency

```
flutter pub add fl_chart
```

Pinned for 7B by ARCH_1 §7 (`Charts | fl_chart | resolver | 7B`). The only package this phase adds,
and it is imported by `chart_card.dart` and the chart surfaces alone — no `fl_chart` type appears
anywhere under `domain/` (ARCH_3 §5.2).

## Files carried here that other documents own

| File | Owner | Why it is here |
|---|---|---|
| `currency_dao.dart` | 2A, then 2C | Gains `watchAllRates()`; see below |
| `currency_repository_impl.dart` | 5 | The `Stream.value(0)` stub replaced |
| `repository_providers.dart` | 5, 7A | Gains `analyticsCacheRepositoryProvider`, `analyticsPortProvider` |
| `service_providers.dart` | 5, 7A | Gains `analyticsServiceProvider`, `analyticsCacheServiceProvider` |

`app_router.dart`, `app_en.arb` and `layout_overflow_test.dart` are carried by seven documents each
and must stay byte-identical across all of them (ARCH_6 §2). They arrive in the UI instalment.
Verified before writing: the copies in PHASE_06F and PHASE_07A are already identical — 365, 1865 and
896 lines respectively — so 7A's are the base this phase edits.

**`routes.dart` gains two entries** (`insightsDrillDownPattern`, `insightsDrillDown`), unlike 7A
which needed none.

## One file beyond the DELIVER list

`lib/data/repositories/unconverted_count.dart`. `CurrencyRepositoryImpl` holds a `CurrencyDao`, a
`Clock`, a `SettingsRepository` and a `CurrencyRateService` — nothing that can see `transactions`,
and the count is a property of the transactions being totalled rather than of the rate subsystem
(ARCH_3 §1.5's own table says so). Putting a transaction query on `CurrencyDao` would have been the
wrong aggregate; injecting `TransactionDao` into the currency repository would have coupled two
modules for one figure. A named collaborator the repository delegates to keeps both boundaries and
is testable on its own.

## Three findings from reading the DAOs rather than assuming them

**`AnalyticsCacheDao` and `AnalyticsCacheRepository` disagree about time, deliberately.** The DAO
takes `nowUtcMillis`, `computedAtUtcMillis` and `staleAfterUtcMillis` so it stays deterministic under
a `FixedClock` — the same rule the views follow (ARCH_2 §12.2). The contract takes a `Duration ttl`
and no clock at all. The impl is where those meet, so it holds the `Clock` and does the one addition.
`invalidateAll` also returns `Future<int>` on the DAO against `Future<void>` on the contract, which
needs an `await` rather than a bare return.

**ARCH_4 §5.1 item 12 is already closed and I have not reopened it.** Both the DAO's doc comment and
the contract's warn that `cacheKey` is the sole primary key, so caching July evicts June, and both
defer the fix to a caller folding the params hash into the key. Phase 4C's `AnalyticsCacheService`
already does exactly that: `keyFor` returns `'$queryName:${hashParams(params)}'`. Nothing in this
phase needs to change, and the row is recorded as closed rather than left looking open.

**`CurrencyDao` had no stream over `currency_rates`.** `allRates`, `rateOnOrBefore`, `earliestRate`
and `newestRateDate` are all futures, and `watchEnabled` / `watchAll` are over `currencies`. So
nothing existed that could re-emit when the rate cache changed — which is the one thing ARCH_3 §1.5
requires of a real `watchUnconvertedCount`: *"a real implementation must re-evaluate every active
transaction's convertibility whenever the rate cache changes"*. `watchAllRates()` is that stream,
three lines following `watchAll()`'s own shape. It is not used by the count directly — `readsFrom`
does that job more cheaply — but it is the honest read for any future consumer, and its absence was
the gap.

## The R18 arithmetic, and one row further than R18 reached

`valuedBatches` and `wasteMovements` join `units` on `unit_code_at_purchase` and return
`factor_to_base_milli`, as ARCH_4 R18 requires. Two things about those joins:

**Neither filters `units.deleted_at`.** A retired unit's factor is still the correct factor for a
batch bought in it, and filtering would silently drop every such batch from the valuation while the
figure still looked complete — the same failure mode R18 describes, arrived at from the other side.

**`dearestPurchase` had the same defect and nobody had named it.** Query 11 orders by
`unit_price_minor`, which is per `transaction_lines.unit_code` — so ₹50/kg loses to ₹1/g and the
"most expensive purchase" is whichever line happened to use the smallest unit. It now orders by
`unit_price_minor * 1000 / factor_to_base_milli` and still *returns* the recorded figure, because
"the most I ever paid" is a fact about that purchase in the unit it was recorded in. R18 closed two
call sites; this is the third.

## Deliberate exceptions to L7, each with a reason

Eight queries read `v_active_transactions` and get `deleted_at IS NULL` plus the payee and
payment-method names for free. `v_account_ledger`, `v_monthly_totals` and `v_low_stock` serve three
more. The rest cannot:

| Query | Reads | Why no view serves it |
|---|---|---|
| 9-12, 24 | `transaction_lines` | No view aggregates lines by item; `v_transaction_allocation` sums them per transaction |
| 13 | `inventory_batches` ⋈ `units` | `v_item_stock` sums quantity and drops cost and purchase unit entirely |
| 14 | `stock_movements` | Append-only, no `deletedAt` at all (ARCH_2 §5.3); no view carries movement kind |
| 17 | `recurring_templates` | `v_recurring_due` LEFT JOINs occurrences, so a template with two `due` rows appears twice and its commitment would be counted twice |
| 20 | `assets` | `v_asset_alerts` carries `warranty_end_date_key` but not `warranty_start_date_key` |
| 7's opening | `accounts` | `v_account_balances` gives the *current* balance; a trend must start from the opening figure |

Every one of those declares `deleted_at IS NULL` on both the row and its parent, and the parent join
goes through `v_active_transactions` wherever a transaction is involved, so the filter that matters
most is still the view's job.

## Query 5 uses date bounds, not `v_monthly_totals`

ARCH_3 §5.1 names `v_monthly_totals` for the monthly queries, and it is the right read for a
whole-month figure. It carries `month_key` and no `date_key`, so bounding it by an
`AnalyticsWindow` means `month_key BETWEEN from.monthKey AND to.monthKey` — which silently widens a
30-day window into two whole months. The window is a `DateKey` range, so the queries bound on
`date_key` and `GROUP BY month_key`, and a partial month at either edge stays partial.

## Two ranking artefacts SQL cannot fix, and what the adapter does about them

**Money.** SQL cannot order across currencies: ¥10,000 outranks ₹5,000 on raw minor units alone, and
`AnalyticsService.topPayeesBySpend` already re-sorts after conversion and takes `limit`. A `LIMIT ?`
bound to `limit` would therefore have cut rows the service was about to promote. The adapter
over-fetches by `_currencySpread` and lets the service rank, which is where the rates are.

**Quantity.** Law L8 makes grams and pieces incomparable, so `quantityByItem` orders by
`unit_category` first and over-fetches, rather than producing a top-ten that is ten weights because
weights carry bigger numbers. `AnalyticsService.topItemsByQuantity` deliberately does not re-sort;
the UI groups by category.

---

## The data layer

### `lib/data/repositories/analytics_port_impl.dart`

```dart
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
    final rows = await _database.customSelect(
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
    ).get();
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
    final rows = await _database.customSelect(
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
    ).get();
    return rows.map(_moneyRow).toList();
  }

  @override
  Future<List<RawMoneyRow>> spendByPaymentMethod(AnalyticsWindow window) async {
    final rows = await _database.customSelect(
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
    ).get();
    return rows.map(_moneyRow).toList();
  }

  @override
  Future<List<RawMoneyRow>> spendByPayee(AnalyticsWindow window, {int limit = 10}) async {
    final rows = await _database.customSelect(
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
    ).get();
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
    final rows = await _database.customSelect(
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
    ).get();
    return rows.map(_monthRow).toList();
  }

  @override
  Future<List<RawMonthRow>> netFlowByMonth(AnalyticsWindow window) async {
    // `v_account_ledger` expands a transfer into two legs with opposite signs, so a self-transfer
    // nets to zero here without this query knowing anything about transfers (ARCH_2 §12.1). That
    // property is the whole reason net flow reads the ledger rather than the transactions.
    final rows = await _database.customSelect(
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
    ).get();
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
    final carried = await _database.customSelect(
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
    ).getSingle();

    final legs = await _database.customSelect(
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
    ).get();

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
  Future<({int minor, String currencyCode})?> openingBalance(String accountId) async {
    // The base table, not `v_account_balances`: that view returns opening *plus* every leg, which is
    // the current balance. A running trend has to start before the legs it is about to add.
    final row = await _database.customSelect(
      '''
      SELECT a.opening_balance_minor AS minor,
             a.currency_code AS currency_code
        FROM accounts a
       WHERE a.id = ?
         AND a.deleted_at IS NULL
      ''',
      variables: [Variable<String>(accountId)],
    ).getSingleOrNull();
    if (row == null) return null;
    return (
      minor: row.read<int>('minor'),
      currencyCode: row.read<String>('currency_code'),
    );
  }

  @override
  Future<List<RawMoneyRow>> totalSpend(AnalyticsWindow window) async {
    final rows = await _database.customSelect(
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
    ).get();
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
    const weekdayBucket = "((CAST(strftime('%w', printf('%04d-%02d-%02d', "
        't.date_key / 10000, (t.date_key / 100) % 100, t.date_key % 100)) '
        'AS INTEGER) + 6) % 7) + 1';
    const dayOfMonthBucket = 't.date_key % 100';
    final bucket = byWeekday ? weekdayBucket : dayOfMonthBucket;

    final rows = await _database.customSelect(
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
    ).get();
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
  Future<List<({int amountMinor, String currencyCode, int lineCount})>> groceryBaskets(
    AnalyticsWindow window,
  ) async {
    // One row per basket, not an aggregate: `AnalyticsService.averageGroceryBasket` averages over the
    // baskets that *converted*, which it cannot do from a pre-summed total.
    final rows = await _database.customSelect(
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
    ).get();
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
  Future<List<RawMoneyRow>> spendByItem(AnalyticsWindow window, {int limit = 10}) async {
    // The line's currency is the parent transaction's `original_currency_code`: a line has no
    // currency column of its own (ARCH_2 §1.x). Joining `v_active_transactions` rather than
    // `transactions` is what supplies the parent's `deleted_at IS NULL` — L7 doing its job even in a
    // query the views do not otherwise serve.
    final rows = await _database.customSelect(
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
    ).get();
    return rows.map(_moneyRow).toList();
  }

  @override
  Future<List<RawQuantityRow>> quantityByItem(AnalyticsWindow window, {int limit = 10}) async {
    // `transaction_lines.quantity_milli` is already base-milli (Law L2), so no unit join is needed
    // here — unlike the batch queries, where the *cost* is per purchase unit. `unit_code` records
    // what the user typed; the quantity is stored normalised.
    //
    // Ordered by category first: Law L8 makes grams and pieces incomparable, so a single
    // `ORDER BY milli_base DESC` would return ten weights and drop the most-bought item in the
    // house because pieces carry smaller numbers. The service does not re-rank; the UI groups.
    final rows = await _database.customSelect(
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
    ).get();
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
  Future<({int unitPriceMinor, String currencyCode, int dateKey, String transactionId})?>
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
    final row = await _database.customSelect(
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
    ).getSingleOrNull();
    if (row == null) return null;
    return (
      unitPriceMinor: row.read<int>('unit_price_minor'),
      currencyCode: row.read<String>('currency_code'),
      dateKey: row.read<int>('date_key'),
      transactionId: row.read<String>('transaction_id'),
    );
  }

  @override
  Future<List<({int dateKey, int lineAmountMinor, String currencyCode, int milliBase, String category})>>
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
    final rows = await _database.customSelect(
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
    ).get();
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
  Future<List<({int remainingMilli, int unitCostMinor, String currencyCode, int unitFactorToBaseMilli})>>
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
  Future<List<({String itemId, String itemName, int milliBase, String category, int? unitCostMinor, String? currencyCode, int? unitFactorToBaseMilli})>>
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
    final rows = await _database.customSelect(
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
    ).get();
    return rows
        .map(
          (row) => (
            itemId: row.read<String>('item_id'),
            itemName: row.read<String>('item_name'),
            milliBase: row.read<int>('milli_base'),
            category: row.read<String>('category'),
            unitCostMinor: row.readNullable<int>('unit_cost_minor'),
            currencyCode: row.readNullable<String>('currency_code'),
            unitFactorToBaseMilli: row.readNullable<int>('unit_factor_to_base_milli'),
          ),
        )
        .toList();
  }

  @override
  Future<List<({String batchId, String itemId, String itemName, int remainingMilli, String category, int expiryDateKey})>>
      expiringBatches(AnalyticsWindow window) async {
    final rows = await _database.customSelect(
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
    ).get();
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
    final row = await _database.customSelect(
      'SELECT COUNT(*) AS row_count FROM v_low_stock',
    ).getSingle();
    return row.read<int>('row_count');
  }

  // ── 17-20: commitments and assets ─────────────────────────────────────────────────────

  @override
  Future<List<({int defaultAmountMinor, String currencyCode, String intervalUnit, int intervalCount})>>
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
    final rows = await _database.customSelect(
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
    ).get();
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
    final rows = await _database.customSelect(
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
    ).get();
    return rows.map(_moneyRow).toList();
  }

  @override
  Future<List<({String assetId, String assetName, int costMinor, String currencyCode, int count})>>
      serviceCostByAsset(AnalyticsWindow window) async {
    // Disposed assets are included, and that is the point of `status = disposed` rather than a
    // delete (ARCH_2 §8.1): the ₹45,000 of servicing you put into a TV stays in the analytics after
    // you sell it. "Lifetime" would be a strange word for a figure that vanished on disposal.
    final rows = await _database.customSelect(
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
    ).get();
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
  Future<List<({String assetId, String assetName, int? startDateKey, int? endDateKey})>>
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
```

### `lib/data/repositories/analytics_cache_repository_impl.dart`

```dart
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/analytics_cache_dao.dart';
import 'package:alaya/domain/repositories/analytics_cache_repository.dart';

/// `AnalyticsCacheRepository` backed by `AnalyticsCacheDao`.
///
/// **This is where the contract's `Duration` meets the DAO's absolute millis.** The DAO takes
/// `nowUtcMillis` and `staleAfterUtcMillis` so it stays assertable under a `FixedClock` — the rule
/// every read in this schema follows (ARCH_2 §12.2) — while the domain contract speaks a TTL and
/// knows nothing about a clock. Holding the `Clock` here is the whole of this class's job, and it is
/// why it is worth existing rather than having `AnalyticsCacheService` talk to the DAO directly:
/// that would put a `data/` import in `domain/` and break Law L12.
///
/// **The eviction problem the DAO's own doc comment warns about is already solved upstream.** Both
/// the DAO and the contract note that `cacheKey` is the sole primary key, so caching July would
/// evict June, and both defer the fix to a caller folding the params hash into the key.
/// `AnalyticsCacheService.keyFor` returns `'$queryName:$paramsHash'`, which is exactly that — so each
/// parameter set already owns a row and no schema change is needed (ARCH_4 §5.1 item 12).
final class AnalyticsCacheRepositoryImpl implements AnalyticsCacheRepository {
  /// Creates the repository over [dao], stamping and expiring entries with [clock].
  const AnalyticsCacheRepositoryImpl(this._dao, this._clock);

  final AnalyticsCacheDao _dao;
  final Clock _clock;

  @override
  Future<String?> read({
    required String cacheKey,
    required String paramsHash,
  }) {
    return _dao.read(
      cacheKey: cacheKey,
      paramsHash: paramsHash,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
  }

  @override
  Future<void> write({
    required String cacheKey,
    required String paramsHash,
    required String payloadJson,
    required Duration ttl,
  }) {
    final now = _clock.nowUtcMillis();
    return _dao.write(
      cacheKey: cacheKey,
      paramsHash: paramsHash,
      payloadJson: payloadJson,
      computedAtUtcMillis: now,
      // One clock reading for both, not two calls: a `computedAt` and a `staleAfter` derived from
      // different instants would drift by however long the write took, which is invisible and
      // pointless.
      staleAfterUtcMillis: now + ttl.inMilliseconds,
    );
  }

  @override
  Future<void> invalidate(String cacheKey) {
    return _dao.invalidate(cacheKey: cacheKey, nowUtcMillis: _clock.nowUtcMillis());
  }

  @override
  Future<void> invalidateAll() async {
    // `await`ed rather than returned: the DAO reports how many rows it tombstoned and the contract
    // returns nothing, so `Future<int>` does not satisfy `Future<void>` without this.
    await _dao.invalidateAll(nowUtcMillis: _clock.nowUtcMillis());
  }
}
```

### `lib/data/repositories/unconverted_count.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// Counts the active transactions whose currency no cached rate can convert (ARCH_3 §1.5).
///
/// **The count belongs with whatever is being totalled, not with the rate subsystem** — ARCH_3 §1.5
/// says so outright, and lists this half as Phase 7B's. `CurrencyRepositoryImpl` returned
/// `Stream.value(0)` because it holds a `CurrencyDao` and nothing that can see `transactions`;
/// adding a transaction query to that DAO would have been the wrong aggregate, and injecting
/// `TransactionDao` into the currency repository would have coupled two modules for one figure. So
/// the query lives here and the repository delegates.
///
/// **Built over the same `RateTable`, never a second lookup path.** §1.5 asks for exactly that: the
/// weekend-gap rule and the approximate fallback have one implementation (ARCH_3 §1.3), and a count
/// that disagreed with the totals it annotates would be worse than no count.
final class UnconvertedCounter {
  /// Creates a counter over [database], converting through [rates].
  const UnconvertedCounter({
    required AlayaDatabase database,
    required CurrencyRateService rates,
    required SettingsRepository settings,
    String fallbackHomeCurrencyCode = 'INR',
  })  : _database = database,
        _rates = rates,
        _settings = settings,
        _fallbackHome = fallbackHomeCurrencyCode;

  final AlayaDatabase _database;
  final CurrencyRateService _rates;
  final SettingsRepository _settings;
  final String _fallbackHome;

  /// Emits how many active transactions cannot be converted into the home currency.
  ///
  /// **Re-emits when the rate cache changes, which is the requirement.** ARCH_3 §1.5 rejects a
  /// static implementation precisely because convertibility has to be re-evaluated whenever a rate
  /// arrives — a fetch that fills in last Tuesday's missing rate must drop the chip's count without
  /// anyone touching a transaction. The query does not read `currency_rates`, so `readsFrom` names
  /// that table anyway: it is the set of tables whose writes invalidate the stream, not a claim
  /// about what was selected.
  ///
  /// **Affordable because it excludes the home currency in SQL.** An unbounded aggregate is
  /// ARCH_4 R7's risk, and this one has no window to bound it by — an unconvertible transaction from
  /// four years ago is still unconvertible. Filtering `<> home` means the common case, a household
  /// with one currency, returns **zero rows** however large the ledger is; a household with two
  /// returns one row per distinct date in the second currency.
  Stream<int> watch() async* {
    final home = await _settings.readHomeCurrencyCode() ?? _fallbackHome;

    yield* _database
        .customSelect(
          '''
          SELECT t.original_currency_code AS currency_code,
                 t.date_key AS date_key,
                 COUNT(*) AS row_count
            FROM v_active_transactions t
           WHERE t.original_currency_code <> ?
           GROUP BY t.original_currency_code, t.date_key
          ''',
          variables: [Variable<String>(home)],
          readsFrom: {_database.transactions, _database.currencyRates},
        )
        .watch()
        .asyncMap((rows) async {
          if (rows.isEmpty) return 0;
          final table = await _rates.table();
          var unconverted = 0;
          for (final row in rows) {
            final result = table.convert(
              // One probe per (currency, date) group rather than per transaction: convertibility is
              // a property of that pair, so a thousand rupee-denominated rows on one day ask the
              // same question once. The amount is a single minor unit because only the *quality*
              // of the answer is read.
              amount: Money(1, row.read<String>('currency_code')),
              toCurrencyCode: home,
              on: DateKey(row.read<int>('date_key')),
            );
            if (result.isExcludedFromTotals) unconverted += row.read<int>('row_count');
          }
          return unconverted;
        });
  }
}
```

### `lib/data/daos/currency_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/date_key_filters.dart';

/// Typed access to `currencies` and the `currency_rates` cache.
class CurrencyDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  CurrencyDao(super.db);

  $CurrenciesTable get _currencies => attachedDatabase.currencies;
  $CurrencyRatesTable get _rates => attachedDatabase.currencyRates;

  SimpleSelectStatement<$CurrenciesTable, CurrencyRow> _activeCurrencies() =>
      select(_currencies)..where((t) => t.deletedAt.isNull());

  SimpleSelectStatement<$CurrencyRatesTable, CurrencyRateRow> _activeRates() =>
      select(_rates)..where((t) => t.deletedAt.isNull());

  /// Emits enabled currencies in display order, for pickers.
  Stream<List<CurrencyRow>> watchEnabled() {
    return (_activeCurrencies()
          ..where((t) => t.isEnabled.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Emits every active currency, enabled or not, for the settings screen.
  Stream<List<CurrencyRow>> watchAll() {
    return (_activeCurrencies()..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Reads one currency by ISO code.
  Future<CurrencyRow?> byCode(String code) =>
      (_activeCurrencies()..where((t) => t.code.equals(code))).getSingleOrNull();

  /// Reads `code -> decimalDigits` for every active currency.
  ///
  /// This is the lookup that keeps `100` out of the codebase (ARCH_1 §4.1): callers cache it once
  /// at startup rather than hardcoding a currency's precision. JPY resolves to 0.
  Future<Map<String, int>> decimalDigitsByCode() async {
    final rows = await _activeCurrencies().get();
    return {for (final row in rows) row.code: row.decimalDigits};
  }

  /// Inserts or updates a currency.
  Future<void> upsert(CurrenciesCompanion currency) =>
      into(_currencies).insertOnConflictUpdate(currency);

  /// Enables or disables a currency without deleting it.
  Future<void> setEnabled({
    required String code,
    required bool isEnabled,
    required int nowUtcMillis,
  }) {
    return (update(_currencies)..where((t) => t.code.equals(code))).write(
      CurrenciesCompanion(isEnabled: Value(isEnabled), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Replaces the cached rates for one fetch, in a single transaction (Law L14).
  ///
  /// The conflict target is stated explicitly, and must be. `idx_rates_point` makes
  /// `(baseCode, quoteCode, rateDateKey)` unique, but drift's `insertOnConflictUpdate` targets the
  /// **primary key** by default — and `id` is a fresh UUID on every fetch, so it never conflicts.
  /// The row would insert and only then trip the unique index, meaning the second rate fetch of any
  /// given day threw `UNIQUE constraint failed`. Verified against SQLite: with the target named,
  /// the row updates in place; without it, the insert fails.
  ///
  /// A named target works here only because `idx_rates_point` is **not** a partial index. SQLite
  /// rejects a partial index as a conflict target unless its `WHERE` predicate is repeated in the
  /// target clause, which drift's column-list API cannot express — see
  /// `RecurringOccurrenceDao.upsertForDue` for how that case has to be handled instead.
  Future<void> upsertRates(List<CurrencyRatesCompanion> rates) {
    return transaction(() async {
      for (final rate in rates) {
        await into(_rates).insert(
          rate,
          onConflict: DoUpdate(
            (_) => CurrencyRatesCompanion(
              rate: rate.rate,
              rateRaw: rate.rateRaw,
              source: rate.source,
              fetchedAt: rate.fetchedAt,
              updatedAt: rate.updatedAt,
              deletedAt: const Value(null),
            ),
            target: [_rates.baseCode, _rates.quoteCode, _rates.rateDateKey],
          ),
        );
      }
    });
  }

  /// Reads every cached rate, for building the in-memory `RateTable`.
  ///
  /// One query rather than two per conversion. `RateTable` applies ARCH_3 §1.3's lookup rule in
  /// memory, so converting a month of transactions costs a single read here instead of two round
  /// trips per amount — which is what makes ARCH_3 §1.5's synchronous `toHome` possible at all.
  ///
  /// Every row is USD-based by construction (ARCH_3 §1.2 — `currency_rates` never stores another
  /// base), so no filter on `baseCode` is needed and none is applied.
  Future<List<CurrencyRateRow>> allRates() {
    return (_activeRates()
          ..orderBy([(t) => OrderingTerm(expression: t.rateDateKey)]))
        .get();
  }

  /// Emits every cached rate, re-emitting whenever the rate cache is written.
  ///
  /// The streaming counterpart to [allRates], added in Phase 7B. Nothing here could previously
  /// observe a rate arriving: every rate read on this DAO is a `Future`, and [watchEnabled] and
  /// [watchAll] are over `currencies`. That left `CurrencyRepository.watchUnconvertedCount` unable to
  /// meet ARCH_3 §1.5's actual requirement — re-evaluate convertibility **whenever the rate cache
  /// changes** — so it stayed a `Stream.value(0)` stub for three phases.
  Stream<List<CurrencyRateRow>> watchAllRates() {
    return (_activeRates()
          ..orderBy([(t) => OrderingTerm(expression: t.rateDateKey)]))
        .watch();
  }

  /// The most recent cached rate for `base -> quote` dated on or before [on].
  ///
  /// This is only the SQL shape of ARCH_3 §1.3's lookup rule — "greatest `rateDateKey <= D`".
  /// The policy that follows from a miss (fall back to the earliest row and mark the result
  /// approximate) is a decision for the currency service, not for a DAO.
  Future<CurrencyRateRow?> rateOnOrBefore({
    required String baseCode,
    required String quoteCode,
    required DateKey on,
  }) {
    return (_activeRates()
          ..where((t) =>
              t.baseCode.equals(baseCode) &
              t.quoteCode.equals(quoteCode) &
              t.rateDateKey.isDateOnOrBefore(on))
          ..orderBy([(t) => OrderingTerm(expression: t.rateDateKey, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// The earliest cached rate for `base -> quote`, for the approximate-rate fallback path.
  Future<CurrencyRateRow?> earliestRate({
    required String baseCode,
    required String quoteCode,
  }) {
    return (_activeRates()
          ..where((t) => t.baseCode.equals(baseCode) & t.quoteCode.equals(quoteCode))
          ..orderBy([(t) => OrderingTerm(expression: t.rateDateKey)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// The newest `rateDateKey` held for [baseCode], so a caller can decide whether to fetch.
  Future<DateKey?> newestRateDate(String baseCode) async {
    final row = await (_activeRates()
          ..where((t) => t.baseCode.equals(baseCode))
          ..orderBy([(t) => OrderingTerm(expression: t.rateDateKey, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return row?.rateDateKey;
  }
}
```

### `lib/data/repositories/currency_repository_impl.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/currency_dao.dart';
import 'package:alaya/data/repositories/mappers/currency_mapper.dart';
import 'package:alaya/data/repositories/mappers/rate_mappers.dart';
import 'package:alaya/data/repositories/unconverted_count.dart';
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/domain/repositories/currency_repository.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// `CurrencyRepository` backed by `CurrencyDao`.
///
/// A thin adapter over two owners. [convert] and [convertToHome] build a `RateTable` from the cached
/// rows and let it apply ARCH_3 §1.2's pivot and §1.3's lookup rule — no network access, and no
/// second copy of that arithmetic living here. [syncDailyRates] delegates to `CurrencyRateService`,
/// which owns the once-daily skip and the fetch ladder.
///
/// Phase 3B implemented both inline, because neither service existed yet. Phase 4A moved them, so
/// there is exactly one definition of each rule — the same reason `v_batch_stock_check` exists to
/// catch a second definition of a stock total.
final class CurrencyRepositoryImpl implements CurrencyRepository {
  /// Creates the repository over [dao], resolving the home currency through [settings].
  ///
  /// [rateService] is null until Phase 5 wires one; a null service makes [syncDailyRates] a
  /// documented no-op rather than a runtime error.
  ///
  /// [unconvertedCounter] is **required**, unlike [rateService], and the asymmetry is deliberate. A
  /// null rate service degrades a *write* to a no-op, which Law L11 permits outright — a rate that
  /// never arrives costs nothing. A null counter would degrade a *read* to `0`, and zero
  /// unconverted amounts is a claim that everything converted rather than an admission that nobody
  /// checked. Three phases of `Stream.value(0)` is exactly what an optional parameter here buys.
  const CurrencyRepositoryImpl(
    this._dao,
    this._clock,
    this._settings, {
    required UnconvertedCounter unconvertedCounter,
    CurrencyRateService? rateService,
  })  : _unconvertedCounter = unconvertedCounter,
        _rateService = rateService;

  final CurrencyDao _dao;
  final Clock _clock;
  final SettingsRepository _settings;
  final CurrencyRateService? _rateService;
  final UnconvertedCounter _unconvertedCounter;

  /// Used only if the seeded `homeCurrencyCode` setting is somehow absent — Phase 1C's seed data
  /// always writes it, so this is a defensive fallback, never the expected path.
  static const String _fallbackHomeCurrencyCode = 'INR';

  @override
  Stream<List<Currency>> watchEnabled() =>
      _dao.watchEnabled().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Currency>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Currency?> byCode(String code) async => (await _dao.byCode(code))?.toEntity();

  @override
  Future<Map<String, int>> decimalDigitsByCode() => _dao.decimalDigitsByCode();

  @override
  Future<Result<void, Failure>> setEnabled({
    required String code,
    required bool isEnabled,
  }) async {
    await _dao.setEnabled(
      code: code,
      isEnabled: isEnabled,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<ConvertedMoney> convert({
    required Money amount,
    required String toCurrencyCode,
    required DateKey on,
  }) async {
    final table = await _rateTable();
    return table.convert(amount: amount, toCurrencyCode: toCurrencyCode, on: on);
  }

  @override
  Future<ConvertedMoney> convertToHome({
    required Money amount,
    required DateKey on,
  }) async {
    final homeCode = await _settings.readHomeCurrencyCode() ?? _fallbackHomeCurrencyCode;
    return convert(amount: amount, toCurrencyCode: homeCode, on: on);
  }

  @override
  /// Delegates to [UnconvertedCounter], which owns the query and the re-evaluation.
  ///
  /// **This replaced a `Stream.value(0)` stub that had stood since Phase 3B** (ARCH_3 §1.5, ARCH_5
  /// §7.3). The stub was correct to exist: a real count re-evaluates every active transaction's
  /// convertibility whenever the rate cache changes, which is analytics work, and guessing at a
  /// query would have shipped a wrong number instead of an unimplemented one.
  ///
  /// It lives in a collaborator rather than here because ARCH_3 §1.5 is explicit that the count
  /// belongs with whatever is being totalled rather than with the rate subsystem — this repository
  /// holds a `CurrencyDao` and cannot see `transactions` at all. The counter converts through the
  /// same `RateTable` this class does, so the chip and the totals it annotates cannot disagree.
  Stream<int> watchUnconvertedCount() => _unconvertedCounter.watch();

  @override
  /// Delegates to `CurrencyRateService.syncDailyRates`, which is the only implementation.
  ///
  /// This method used to fetch directly. It was replaced because the service adds the two things
  /// that make ARCH_3 §1.2's "one request per day for the entire app, forever" true rather than
  /// aspirational — it skips the fetch when the cache already holds today's date, and refuses to
  /// overwrite a working cache with an empty snapshot. A caller wiring the old version to a
  /// foreground hook would have re-fetched on every resume.
  ///
  /// Still never throws: the service swallows every failure path (Law L11).
  Future<void> syncDailyRates() async {
    await _rateService?.syncDailyRates();
  }

  /// Builds the in-memory rate table `RateTable` needs, from the cached USD rows.
  ///
  /// The pivot and lookup rules live in `CurrencyRateService`'s `RateTable` (ARCH_3 §1.2, §1.3) —
  /// this method only supplies the data. Phase 3B originally hand-rolled the same cross-rating here;
  /// Phase 4A moved it, because two implementations of one rule drift apart and the schema's own
  /// reconciliation view is a standing reminder of what that costs.
  Future<RateTable> _rateTable() async {
    final rows = await _dao.allRates();
    // Delegates to RateMappers so this mapping has one definition — Phase 5 needed the same map in
    // the provider graph, and a second copy is how the two drift apart.
    return RateMappers.tableFrom(
      rows: rows,
      decimalDigitsByCode: await _dao.decimalDigitsByCode(),
    );
  }
}
```

### `lib/app/providers/repository_providers.dart`

```dart
/// One provider per repository contract, typed as the **contract** and never the implementation.
///
/// Typing them as the interface is what makes the layering rule enforceable: a feature that declares
/// `ref.watch(accountRepositoryProvider)` receives an `AccountRepository` and cannot reach into
/// `AccountRepositoryImpl` for a method the contract does not expose.
///
/// **All seventeen of Phase 3A's contracts now have an implementation.** `CalendarRepository` was the
/// last but one, wired in Phase 7A; `AnalyticsCacheRepository` was the last, wired here. The note
/// that used to stand in this paragraph — two contracts unimplemented, three engines unreachable — is
/// closed (ARCH_4 §5.1 item 15).
///
/// `analyticsPortProvider` sits with the repositories rather than with the engines despite not being
/// a repository, because it has a repository's shape exactly: a contract declared in `domain/`, one
/// implementation in `data/`, and a provider typed as the contract so no feature can reach past it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/data/repositories/analytics_cache_repository_impl.dart';
import 'package:alaya/data/repositories/analytics_port_impl.dart';
import 'package:alaya/data/repositories/calendar_repository_impl.dart';
import 'package:alaya/data/repositories/account_repository_impl.dart';
import 'package:alaya/data/repositories/asset_repository_impl.dart';
import 'package:alaya/data/repositories/batch_repository_impl.dart';
import 'package:alaya/data/repositories/currency_repository_impl.dart';
import 'package:alaya/data/repositories/item_category_resolver.dart';
import 'package:alaya/data/repositories/item_repository_impl.dart';
import 'package:alaya/data/repositories/payee_repository_impl.dart';
import 'package:alaya/data/repositories/payment_method_repository_impl.dart';
import 'package:alaya/data/repositories/recurring_repository_impl.dart';
import 'package:alaya/data/repositories/service_record_repository_impl.dart';
import 'package:alaya/data/repositories/settings_repository_impl.dart';
import 'package:alaya/data/repositories/shopping_repository_impl.dart';
import 'package:alaya/data/repositories/stock_repository_impl.dart';
import 'package:alaya/data/repositories/tag_repository_impl.dart';
import 'package:alaya/data/repositories/transaction_repository_impl.dart';
import 'package:alaya/data/repositories/unconverted_count.dart';
import 'package:alaya/data/repositories/unit_repository_impl.dart';
import 'package:alaya/domain/repositories/analytics_cache_repository.dart';
import 'package:alaya/domain/repositories/calendar_repository.dart';
import 'package:alaya/domain/repositories/account_repository.dart';
import 'package:alaya/domain/repositories/asset_repository.dart';
import 'package:alaya/domain/repositories/batch_repository.dart';
import 'package:alaya/domain/repositories/currency_repository.dart';
import 'package:alaya/domain/repositories/item_repository.dart';
import 'package:alaya/domain/repositories/payee_repository.dart';
import 'package:alaya/domain/repositories/payment_method_repository.dart';
import 'package:alaya/domain/repositories/recurring_repository.dart';
import 'package:alaya/domain/repositories/service_record_repository.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/repositories/shopping_repository.dart';
import 'package:alaya/domain/repositories/stock_repository.dart';
import 'package:alaya/domain/repositories/tag_repository.dart';
import 'package:alaya/domain/repositories/transaction_repository.dart';
import 'package:alaya/domain/repositories/unit_repository.dart';
import 'package:alaya/domain/services/analytics/analytics_port.dart';


/// Resolves an item's unit category, with a per-instance cache.
///
/// A single provider rather than one per consumer, because three repositories need it and its whole
/// value is the cache: constructing it twice halves the hit rate for no reason.
final itemCategoryResolverProvider =
    Provider<ItemCategoryResolver>((ref) => ItemCategoryResolver(ref.watch(itemDaoProvider)));

/// Key-value app settings.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepositoryImpl(ref.watch(settingsDaoProvider), ref.watch(clockProvider)),
);

/// Currencies, rates and conversion.
///
/// Takes `CurrencyRateService` so `syncDailyRates` has one implementation. Phase 3B's
/// `DailyRateFetch` typedef is gone — the repository delegates rather than reimplementing the
/// once-daily check, which the earlier version omitted entirely.
final currencyRepositoryProvider = Provider<CurrencyRepository>(
  (ref) => CurrencyRepositoryImpl(
    ref.watch(currencyDaoProvider),
    ref.watch(clockProvider),
    ref.watch(settingsRepositoryProvider),
    rateService: ref.watch(currencyRateServiceProvider),
    // Phase 7B: `watchUnconvertedCount` was a `Stream.value(0)` stub until this arrived, so the
    // `+N unconverted` chip could never report anything (ARCH_3 §1.5, ARCH_5 §7.3).
    unconvertedCounter: ref.watch(unconvertedCounterProvider),
  ),
);

/// Counts the transactions no cached rate can convert, for the `+N unconverted` chip.
///
/// Not a repository, and not in `service_providers.dart` either: it is the collaborator
/// `CurrencyRepositoryImpl` delegates one method to, so it belongs beside the repository that owns
/// it. It takes `CurrencyRateService` for the same reason that service takes closures over the DAO —
/// depending on `currencyRepositoryProvider` from here would be a cycle.
final unconvertedCounterProvider = Provider<UnconvertedCounter>(
  (ref) => UnconvertedCounter(
    database: ref.watch(databaseProvider),
    rates: ref.watch(currencyRateServiceProvider),
    settings: ref.watch(settingsRepositoryProvider),
  ),
);

/// Units and conversion factors.
final unitRepositoryProvider = Provider<UnitRepository>(
  (ref) => UnitRepositoryImpl(ref.watch(unitDaoProvider), ref.watch(clockProvider)),
);

/// Accounts and balances.
final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepositoryImpl(
    ref.watch(accountDaoProvider),
    ref.watch(transactionDaoProvider),
    ref.watch(currencyRepositoryProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// Payment methods.
final paymentMethodRepositoryProvider = Provider<PaymentMethodRepository>(
  (ref) => PaymentMethodRepositoryImpl(
    ref.watch(paymentMethodDaoProvider),
    ref.watch(clockProvider),
  ),
);

/// Payees.
final payeeRepositoryProvider = Provider<PayeeRepository>(
  (ref) => PayeeRepositoryImpl(ref.watch(payeeDaoProvider), ref.watch(clockProvider)),
);

/// Tags.
final tagRepositoryProvider = Provider<TagRepository>(
  (ref) => TagRepositoryImpl(ref.watch(tagDaoProvider), ref.watch(clockProvider)),
);

/// Transactions, with their lines and stock side effects.
final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepositoryImpl(
    ref.watch(transactionDaoProvider),
    ref.watch(transactionLineDaoProvider),
    ref.watch(accountDaoProvider),
    ref.watch(unitDaoProvider),
    ref.watch(batchDaoProvider),
    ref.watch(stockMovementDaoProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(currencyRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// The item catalogue.
final itemRepositoryProvider = Provider<ItemRepository>(
  (ref) => ItemRepositoryImpl(ref.watch(itemDaoProvider), ref.watch(clockProvider)),
);

/// Inventory batches.
final batchRepositoryProvider = Provider<BatchRepository>(
  (ref) => BatchRepositoryImpl(
    ref.watch(batchDaoProvider),
    ref.watch(itemCategoryResolverProvider),
    ref.watch(clockProvider),
  ),
);

/// Stock levels and movements.
final stockRepositoryProvider = Provider<StockRepository>(
  (ref) => StockRepositoryImpl(
    ref.watch(batchDaoProvider),
    ref.watch(stockMovementDaoProvider),
    ref.watch(itemCategoryResolverProvider),
    ref.watch(uidGeneratorProvider),
    ref.watch(clockProvider),
  ),
);

/// Shopping lists and entries.
final shoppingRepositoryProvider = Provider<ShoppingRepository>(
  (ref) => ShoppingRepositoryImpl(
    ref.watch(shoppingListDaoProvider),
    ref.watch(shoppingEntryDaoProvider),
    ref.watch(itemDaoProvider),
    ref.watch(transactionLineDaoProvider),
    ref.watch(itemCategoryResolverProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(uidGeneratorProvider),
    ref.watch(clockProvider),
  ),
);

/// Recurring templates and occurrences.
final recurringRepositoryProvider = Provider<RecurringRepository>(
  (ref) => RecurringRepositoryImpl(
    ref.watch(recurringTemplateDaoProvider),
    ref.watch(recurringOccurrenceDaoProvider),
    ref.watch(transactionRepositoryProvider),
    ref.watch(uidGeneratorProvider),
    ref.watch(clockProvider),
  ),
);

/// Assets.
final assetRepositoryProvider = Provider<AssetRepository>(
  (ref) => AssetRepositoryImpl(ref.watch(assetDaoProvider), ref.watch(clockProvider)),
);

/// Service records.
final serviceRecordRepositoryProvider = Provider<ServiceRecordRepository>(
  (ref) => ServiceRecordRepositoryImpl(
    ref.watch(serviceRecordDaoProvider),
    ref.watch(assetDaoProvider),
    ref.watch(transactionRepositoryProvider),
    ref.watch(uidGeneratorProvider),
    ref.watch(clockProvider),
  ),
);

/// The calendar feed. Phase 3A declared the contract and no phase implemented it until 7A
/// (ARCH_4 §5.1 item 15), which is why `calendarAggregatorProvider` could not exist.
final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => CalendarRepositoryImpl(ref.watch(calendarDaoProvider)),
);

/// Memoised analytics results. Phase 3A declared the contract and no phase implemented it until 7B
/// (ARCH_4 §5.1 item 15), which is why `analyticsCacheServiceProvider` could not exist.
///
/// The `Clock` is the impl's own, not the DAO's: `AnalyticsCacheDao` takes absolute millis so it
/// stays assertable under a `FixedClock`, and the contract takes a `Duration`.
final analyticsCacheRepositoryProvider = Provider<AnalyticsCacheRepository>(
  (ref) => AnalyticsCacheRepositoryImpl(
    ref.watch(analyticsCacheDaoProvider),
    ref.watch(clockProvider),
  ),
);

/// The raw aggregates behind ARCH_3 §5.1's twenty-four queries.
///
/// Typed as the **port**, so `AnalyticsService` cannot reach into the adapter for a query the
/// contract does not declare — and so a fake in a test substitutes without the service noticing
/// (ARCH_4 R19).
final analyticsPortProvider = Provider<AnalyticsPort>(
  (ref) => AnalyticsPortImpl(ref.watch(databaseProvider), ref.watch(clockProvider)),
);
```

### `lib/app/providers/service_providers.dart`

```dart
/// One provider per engine.
///
/// The stateless engines are `const` and could in principle be constructed at each use site. They get
/// providers anyway so that every dependency in the app arrives the same way — a codebase where some
/// collaborators are injected and others are constructed inline is one where you cannot tell, from a
/// widget, what it actually depends on.
///
/// ## Every engine now has a provider
///
/// Three did not, for five phases. `CalendarAggregator` was blocked on `CalendarRepository` and was
/// wired in 7A; `AnalyticsService` was blocked on an `AnalyticsPort` adapter and `AnalyticsCacheService`
/// on `AnalyticsCacheRepository`, and both are wired here (ARCH_4 §5.1 item 15).
///
/// **The decision to omit them rather than stub them was the right one, and it is worth keeping the
/// reasoning after the fact.** A port returning empty rows makes an unfinished analytics screen
/// indistinguishable from a working one that found no data — there is no way to tell those apart from
/// the UI, and no test that would have failed. An absent provider is a compile error at the first use
/// site, which names the problem where someone can act on it. Phase 6F's insight card is the proof:
/// its spending side shipped as an honest inline empty state naming what it waited for, rather than
/// as a chart of zeroes.
///
/// `analyticsServiceProvider` is the one `FutureProvider` among the engines, because `AnalyticsService`
/// takes a **loaded** `RateTable` rather than the service that loads it. That is ARCH_3 §1.5's design
/// working as intended: conversion is synchronous so a month of data costs one table load instead of
/// two cache round trips per amount, and somebody has to await the load. Here it is a provider.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/data/backup/backup_service.dart';
import 'package:alaya/data/backup/restore_service.dart';
import 'package:alaya/data/remote/currency_api_client.dart';
import 'package:alaya/data/repositories/mappers/rate_mappers.dart';
import 'package:alaya/data/security/app_lock_store.dart';
import 'package:alaya/data/security/pin_service.dart';
import 'package:alaya/data/security/recovery_code.dart';
import 'package:alaya/domain/services/analytics/analytics_cache_service.dart';
import 'package:alaya/domain/services/analytics/analytics_service.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';
import 'package:alaya/domain/services/date_range_service.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';
import 'package:alaya/domain/services/low_stock_suggestion_engine.dart';
import 'package:alaya/domain/services/purchase_fan_out_service.dart';
import 'package:alaya/domain/services/recurring_engine.dart';
import 'package:alaya/domain/services/stock_reconciler.dart';
import 'package:alaya/domain/services/unit_engine.dart';


// ── stateless engines ───────────────────────────────────────────────────────────────────

/// Unit conversion within a category.
final unitEngineProvider = Provider<UnitEngine>((ref) => const UnitEngine());

/// Date-range presets for filters and analytics.
final dateRangeServiceProvider = Provider<DateRangeService>((ref) => const DateRangeService());

/// Net worth and per-account balances.
final balanceServiceProvider = Provider<BalanceService>((ref) => const BalanceService());

/// FEFO consumption planning.
final inventoryConsumptionServiceProvider =
    Provider<InventoryConsumptionService>((ref) => const InventoryConsumptionService());

/// Cache-versus-ledger reconciliation and repair.
final stockReconcilerProvider = Provider<StockReconciler>((ref) => const StockReconciler());

/// Idempotent low-stock suggestion decisions.
final lowStockSuggestionEngineProvider =
    Provider<LowStockSuggestionEngine>((ref) => const LowStockSuggestionEngine());

/// Recurring schedule arithmetic — next due, materialisation, settlement.
final recurringEngineProvider = Provider<RecurringEngine>((ref) => const RecurringEngine());

// ── engines with dependencies ───────────────────────────────────────────────────────────

/// Turns a purchase line into a batch, an asset or a template.
final purchaseFanOutServiceProvider = Provider<PurchaseFanOutService>(
  (ref) => PurchaseFanOutService(normalizer: ref.watch(normalizerProvider)),
);

/// The exchange-rate HTTP client.
final currencyApiClientProvider = Provider<CurrencyApiClient>(
  (ref) => CurrencyApiClient(
    dio: ref.watch(dioProvider),
    logger: ref.watch(loggerProvider),
  ),
);

/// Rate lookup, cross-rate pivoting and the once-daily fetch.
///
/// Its four collaborators are closures over the DAO rather than the repository, which is what keeps
/// this out of a cycle: `CurrencyRepository` depends on this service, so a service depending on the
/// repository would not resolve.
final currencyRateServiceProvider = Provider<CurrencyRateService>((ref) {
  final dao = ref.watch(currencyDaoProvider);
  final client = ref.watch(currencyApiClientProvider);
  final clock = ref.watch(clockProvider);
  final uids = ref.watch(uidGeneratorProvider);
  return CurrencyRateService(
    loadTable: () async => RateMappers.tableFrom(
      rows: await dao.allRates(),
      decimalDigitsByCode: await dao.decimalDigitsByCode(),
    ),
    saveSnapshot: (snapshot) => dao.upsertRates(
      RateMappers.companionsFrom(snapshot: snapshot, uids: uids, clock: clock),
    ),
    fetchSnapshot: client.fetchLatest,
    // `newestRateDate` takes the base code; a snapshot is always USD-pivoted (ARCH_3 §1.2).
    newestCachedDate: () => dao.newestRateDate(RateTable.pivotCode),
    clock: clock,
  );
});

// ── security ────────────────────────────────────────────────────────────────────────────

/// Recovery-code generation and normalisation.
final recoveryCodeProvider = Provider<RecoveryCode>((ref) => RecoveryCode());

/// The app-lock secret store.
///
/// Reads and writes secure storage only, never the database — which is what makes a restore unable
/// to change the lock (ARCH_3 §2.1).
final appLockStoreProvider = Provider<AppLockStore>(
  (ref) => AppLockStore(storage: ref.watch(secureKeyValueStoreProvider)),
);

/// PIN verification, change, enable, disable and the failure throttle.
final pinServiceProvider = Provider<PinService>(
  (ref) => PinService(
    store: ref.watch(appLockStoreProvider),
    clock: ref.watch(clockProvider),
    recoveryCode: ref.watch(recoveryCodeProvider),
  ),
);

// ── backup ──────────────────────────────────────────────────────────────────────────────

/// Database export via `VACUUM INTO`.
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    database: ref.watch(databaseProvider),
    historyDao: ref.watch(backupHistoryDaoProvider),
    clock: ref.watch(clockProvider),
    uids: ref.watch(uidGeneratorProvider),
  ),
);

/// Merge and Replace restore.
final restoreServiceProvider = Provider<RestoreService>(
  (ref) => RestoreService(database: ref.watch(databaseProvider)),
);

/// The calendar aggregator, which applies ARCH_3 §6's per-type severity thresholds.
///
/// Stateless and `const`-constructible, but it takes a repository, so it gets a provider like every
/// other engine — no widget constructs it.
final calendarAggregatorProvider = Provider<CalendarAggregator>(
  (ref) => CalendarAggregator(ref.watch(calendarRepositoryProvider)),
);

// ── analytics ───────────────────────────────────────────────────────────────────────────

/// The home currency every converted analytics figure is expressed in.
///
/// `'INR'` is a data fallback for a setting Phase 1C's seed always writes, not a user-visible string,
/// so Law U5 does not reach it. It is named rather than inlined because three files now need the same
/// answer and three literals is how they start disagreeing.
const String analyticsFallbackHomeCurrencyCode = 'INR';

/// Memoisation for analytics results slower than roughly 200 ms (ARCH_3 §5.2).
final analyticsCacheServiceProvider = Provider<AnalyticsCacheService>(
  (ref) => AnalyticsCacheService(ref.watch(analyticsCacheRepositoryProvider)),
);

/// ARCH_3 §5.1's twenty-four queries, over the SQL adapter and a loaded rate table.
///
/// **A `FutureProvider`, because the `RateTable` has to be in hand before the service is built.**
/// Every conversion in `AnalyticsService` is synchronous by design (ARCH_3 §1.5) — that is what makes
/// converting a month of transactions one table load rather than a thousand — so the awaiting happens
/// once, here, instead of per amount.
///
/// Re-created when the rate cache is written, because `CurrencyRateService.table()` is watched rather
/// than read: a rate arriving must change the figures it feeds, not just the unconverted count beside
/// them.
final analyticsServiceProvider = FutureProvider<AnalyticsService>((ref) async {
  final rates = await ref.watch(currencyRateServiceProvider).table();
  final home = await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      analyticsFallbackHomeCurrencyCode;
  return AnalyticsService(
    port: ref.watch(analyticsPortProvider),
    rates: rates,
    homeCurrencyCode: home,
  );
});
```

## The shared addition, the routes and the view-model state

`ChartCard` is the one widget ARCH_5 §8 permits this phase to add to `shared/`. Nothing else here is
shared: the chart surfaces are analytics-only and live in `features/analytics/presentation/widgets/`.

### `lib/shared/widgets/chart_card.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One analytics figure in a card, owning all four of its states (ARCH_5 §7's `ChartCard`).
///
/// **The reason this is shared rather than written per surface is Law U4.** Twenty-four figures each
/// needing loading, empty, error and populated is ninety-six states, and the failure mode ARCH_5 §0
/// names — "a screen that is nearly a screen" — is what happens when the twenty-fourth author is
/// bored. Here they are written once and every surface inherits them.
///
/// **A failing card costs the reader that card and nothing else** (ARCH_5 §3 archetype F). The error
/// branch renders inside the card, so an unreachable rate table blanks one figure rather than the
/// screen.
///
/// This *is* the tier-1 surface, so nothing handed to [builder] may be another [AlayaCard]
/// (ARCH_5 §2.5). Group inside it with space and a `SectionHeader`.
///
/// **A `StatelessWidget` that imports `flutter_riverpod` for `AsyncValue` and nothing else.** It reads
/// no provider and takes no `WidgetRef` — the caller watches, this renders. `shared/tag_picker.dart`
/// already imports the package for the same reason, and Law L12's layering is about `core` → `domain`
/// → `data` → `features`, which a state-management type does not cross.
class ChartCard<T> extends StatelessWidget {
  /// Creates a card for [value], titled [title].
  const ChartCard({
    required this.title,
    required this.value,
    required this.isEmpty,
    required this.emptyMessage,
    required this.builder,
    required this.onRetry,
    this.subtitle,
    this.approximateCount = 0,
    this.unconvertedCount = 0,
    this.onTap,
    this.trailing,
    super.key,
  });

  /// What this figure answers, already localised. Sentence case (ARCH_5 §2.8).
  final String title;

  /// An optional line under the title — the window, the unit, the caveat.
  final String? subtitle;

  /// The figure, consumed with all three branches (Law U4).
  final AsyncValue<T> value;

  /// Whether the loaded figure holds nothing.
  ///
  /// Required rather than inferred: "empty" is different for every result type — an empty slice
  /// list, a zero total, a trend with one point — and a widget guessing at it would show a chart
  /// axis with no data and call that populated.
  final bool Function(T data) isEmpty;

  /// What to say when there is nothing yet. Names the next action where there is one (ARCH_5 §2.8).
  final String emptyMessage;

  /// Renders the populated figure.
  final Widget Function(BuildContext context, T data) builder;

  /// Recomputes this figure. Wired to `ref.invalidate` of the provider behind it.
  final VoidCallback onRetry;

  /// How many of this figure's data points converted only approximately (ARCH_3 §1.3).
  final int approximateCount;

  /// How many could not be converted at all, and are therefore **excluded** from the figure.
  ///
  /// Surfaced rather than hidden, because a total that silently omitted an unconvertible amount
  /// would look complete while under-reporting (anomaly A15, A34).
  final int unconvertedCount;

  /// Opens the drill-down behind this figure.
  final VoidCallback? onTap;

  /// A rendered value beside the title — an `AmountText` carrying the figure's headline.
  final Widget? trailing;

  /// Above this text scale the header stacks instead of sharing a row (Law U21).
  static const double _stackAboveScale = 1.5;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final scale = MediaQuery.textScalerOf(context).scale(1);

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.md),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            title: title,
            subtitle: subtitle,
            trailing: trailing,
            showChevron: onTap != null,
            stacked: scale >= _stackAboveScale,
          ),
          const SizedBox(height: AlayaSpacing.sm),
          value.when(
            // Not a spinner: a card that is about to hold a chart reads as "slow" behind one
            // (ARCH_5 §5.2). A muted line naming what is coming says more and costs no layout.
            loading: () => Text(
              strings.chartLoading,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            // The repository's own message, never a generic body (Law U9). A figure that fails
            // identically for every cause is a bug nobody can find.
            error: (error, stack) => _CardError(
              message: error.toString(),
              retryLabel: strings.actionRetry,
              onRetry: onRetry,
            ),
            // **The builder is never wrapped in a fixed height.** A card sizes to its own content and
            // the screen's `SliverList` scrolls; a chart inside it asks for its own height through
            // `AnalyticsPlotBox`. Bounding the whole builder here squeezed the title and the subtitle of
            // any card that put chrome above its plot.
            data: (data) => isEmpty(data)
                ? Text(
                    emptyMessage,
                    style: AlayaTypography.body.copyWith(color: semantic.muted),
                  )
                : builder(context, data),
          ),
          if (approximateCount > 0 || unconvertedCount > 0) ...[
            const SizedBox(height: AlayaSpacing.sm),
            Wrap(
              spacing: AlayaSpacing.xs,
              runSpacing: AlayaSpacing.xxs,
              children: [
                if (unconvertedCount > 0)
                  StatusChip(
                    label: strings.chartUnconverted(unconvertedCount),
                    tone: StatusTone.warning,
                  ),
                if (approximateCount > 0)
                  StatusChip(
                    label: strings.chartApproximate(approximateCount),
                    tone: StatusTone.info,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The title, its subtitle, and whatever sits opposite them.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.showChevron,
    required this.stacked,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool showChevron;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;

    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: AlayaTypography.cardTitle.copyWith(color: theme.colorScheme.onSurface),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            subtitle!,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ],
      ],
    );

    final chevron = showChevron
        ? Padding(
            padding: const EdgeInsets.only(left: AlayaSpacing.xs),
            child: Icon(Icons.chevron_right, size: AlayaIconSize.md, color: semantic.muted),
          )
        : null;

    // **Stacked above 1.5x, and `Flexible` on the value is not the fix** (Law U21). `trailing` is
    // usually an `AmountText`, which clips rather than ellipsises — so a clipped figure is a wrong
    // figure, and it must be given its own row rather than squeezed. Against a tight `Expanded` the
    // two would split evenly and the *title* would truncate at scale 1 instead.
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: label),
              if (chevron != null) chevron,
            ],
          ),
          if (trailing != null) ...[
            const SizedBox(height: AlayaSpacing.xs),
            Align(alignment: Alignment.centerLeft, child: trailing),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: label),
        if (trailing != null) ...[
          const SizedBox(width: AlayaSpacing.sm),
          trailing!,
        ],
        if (chevron != null) chevron,
      ],
    );
  }
}

/// An inline failure, sized for a card rather than for a screen.
///
/// Not `ErrorState`: that one is a full-height state with a 40px glyph and its own
/// `ScrollSafeCenter`, which inside a card would push every sibling off the screen.
class _CardError extends StatelessWidget {
  const _CardError({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: AlayaIconSize.md, color: semantic.danger),
            const SizedBox(width: AlayaSpacing.xs),
            Expanded(
              child: Text(
                message,
                style: AlayaTypography.caption.copyWith(color: semantic.danger),
              ),
            ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onRetry,
            child: Text(retryLabel, style: AlayaTypography.button),
          ),
        ),
      ],
    );
  }
}
```

### `lib/app/router/routes.dart`

```dart
/// Every route path in the app, in one place.
///
/// Hand-written: `go_router_builder` cannot resolve alongside `drift_dev` (ARCH_1 §7.1). A literal
/// path anywhere else is a route that drifts silently when this file changes.
abstract final class Routes {
  /// Where the app opens.
  static const String initial = dashboard;

  // ── top level, inside the drawer shell ──

  /// The dashboard.
  static const String dashboard = '/';

  /// The transaction ledger.
  static const String expenses = '/expenses';

  /// The inventory catalogue.
  static const String inventory = '/inventory';

  /// The shopping lists.
  static const String shopping = '/shopping';

  /// The recurring templates.
  static const String recurring = '/recurring';

  /// The assets and service records.
  static const String services = '/services';

  /// The calendar.
  static const String calendar = '/calendar';

  /// The insights.
  static const String insights = '/insights';

  /// The settings.
  static const String settings = '/settings';

  // ── outside the shell: full-screen editors and the lock ──

  /// The PIN gate.
  static const String lock = '/lock';

  /// The palette workbench.
  static const String themeLab = '/settings/theme-lab';

  /// A new transaction.
  static const String transactionNew = '/expenses/new';

  /// The line items of a new transaction.
  static const String transactionLinesNew = '/expenses/new/lines';

  /// A new item.
  static const String itemNew = '/inventory/new';

  /// A new recurring template.
  static const String recurringNew = '/recurring/new';

  /// A new asset.
  static const String assetNew = '/services/new';

  // ── parameterised ──

  /// Path pattern for one transaction.
  static const String transactionDetailPattern = '/expenses/:transactionId';

  /// Path pattern for editing one transaction.
  static const String transactionEditPattern = '/expenses/:transactionId/edit';

  /// Path pattern for the line items of one transaction.
  static const String transactionLinesPattern = '/expenses/:transactionId/lines';

  /// Path pattern for one item.
  static const String itemDetailPattern = '/inventory/:itemId';

  /// Path pattern for editing one item.
  static const String itemEditPattern = '/inventory/:itemId/edit';

  /// Path pattern for adding a batch to one item.
  static const String batchNewPattern = '/inventory/:itemId/batch/new';

  /// Path pattern for editing one batch.
  static const String batchEditPattern = '/inventory/:itemId/batch/:batchId';

  /// Path pattern for one batch's movement history.
  static const String batchHistoryPattern = '/inventory/:itemId/batch/:batchId/history';

  /// Path pattern for one shopping list.
  static const String shoppingListPattern = '/shopping/:listId';

  /// Path pattern for turning a shopping list's ticked entries into a purchase.
  static const String shoppingConvertPattern = '/shopping/:listId/convert';

  /// Path pattern for editing one recurring template.
  static const String recurringEditPattern = '/recurring/:templateId/edit';

  /// Path pattern for one template's occurrence history.
  static const String recurringHistoryPattern = '/recurring/:templateId/history';

  /// Path pattern for one recurring template.
  static const String recurringDetailPattern = '/recurring/:templateId';

  /// Path pattern for editing one asset.
  static const String assetEditPattern = '/services/:assetId/edit';

  /// Path pattern for a new service record against one asset.
  static const String serviceNewPattern = '/services/:assetId/service/new';

  /// Path pattern for editing one service record.
  static const String serviceEditPattern = '/services/:assetId/service/:recordId';

  /// Path pattern for one asset.
  static const String assetDetailPattern = '/services/:assetId';

  /// Path pattern for one calendar day.
  static const String calendarDayPattern = '/calendar/:dateKey';

  /// Path pattern for one analytics drill-down.
  ///
  /// **Outside the shell**, unlike `calendarDayPattern`. A day is a view *of* the month, so it keeps
  /// the drawer and the grid stays behind it (Law U27); a drill-down leaves analytics for the ledger
  /// and needs a back arrow, which a shell owning a drawer can never imply (Law U18).
  ///
  /// **The window is deliberately absent from the path.** ARCH_5 §5.7 keeps a selected range in the
  /// view-model — the URL is the record's identity and nothing else — so a drill-down inherits
  /// whatever range the analytics screen is showing.
  static const String insightsDrillDownPattern = '/insights/drill/:drillKind/:drillValue';

  // ── param names, so a builder reading them cannot misspell one ──

  /// The transaction id parameter.
  static const String pTransactionId = 'transactionId';

  /// The item id parameter.
  static const String pItemId = 'itemId';

  /// The batch id parameter.
  static const String pBatchId = 'batchId';

  /// The shopping list id parameter.
  static const String pListId = 'listId';

  /// The recurring template id parameter.
  static const String pTemplateId = 'templateId';

  /// The asset id parameter.
  static const String pAssetId = 'assetId';

  /// The service record id parameter.
  static const String pRecordId = 'recordId';

  /// The calendar date parameter.
  static const String pDateKey = 'dateKey';

  /// The drill-down axis parameter.
  static const String pDrillKind = 'drillKind';

  /// The drill-down value parameter.
  static const String pDrillValue = 'drillValue';

  // ── builders ──

  /// The location for transaction [id].
  static String transactionDetail(String id) => '$expenses/$id';

  /// The location for editing transaction [id].
  static String transactionEdit(String id) => '$expenses/$id/edit';

  /// The location for the line items of transaction [id], or of a new one when null.
  static String transactionLines(String? id) =>
      id == null ? transactionLinesNew : '$expenses/$id/lines';

  /// The location for item [id].
  static String itemDetail(String id) => '$inventory/$id';

  /// The location for editing item [id].
  static String itemEdit(String id) => '$inventory/$id/edit';

  /// The location for adding a batch to item [itemId].
  static String batchNew(String itemId) => '$inventory/$itemId/batch/new';

  /// The location for editing batch [batchId] of item [itemId].
  static String batchEdit(String itemId, String batchId) =>
      '$inventory/$itemId/batch/$batchId';

  /// The location for batch [batchId]'s movement history.
  static String batchHistory(String itemId, String batchId) =>
      '$inventory/$itemId/batch/$batchId/history';

  /// The location for shopping list [id].
  static String shoppingList(String id) => '$shopping/$id';

  /// The location for converting shopping list [id] into a purchase.
  static String shoppingConvert(String id) => '$shopping/$id/convert';

  /// The location for recurring template [id].
  static String recurringDetail(String id) => '$recurring/$id';

  /// The location for editing recurring template [id], or for a new one when null.
  static String recurringEdit(String? id) =>
      id == null ? recurringNew : '$recurring/$id/edit';

  /// The location for template [id]'s occurrence history.
  static String recurringHistory(String id) => '$recurring/$id/history';

  /// The location for asset [id].
  static String assetDetail(String id) => '$services/$id';

  /// The location for editing asset [id], or for a new one when null.
  static String assetEdit(String? id) => id == null ? assetNew : '$services/$id/edit';

  /// The location for a new service record against asset [assetId].
  static String serviceNew(String assetId) => '$services/$assetId/service/new';

  /// The location for editing service record [recordId] of asset [assetId].
  static String serviceEdit(String assetId, String recordId) =>
      '$services/$assetId/service/$recordId';

  /// The location for the calendar on [dateKey].
  static String calendarDay(int dateKey) => '$calendar/$dateKey';

  /// The location for the analytics drill-down on [kind] with [value].
  static String insightsDrillDown(String kind, String value) =>
      '$insights/drill/$kind/$value';

  /// The nine drawer destinations, in drawer order.
  ///
  /// Named for the drawer rather than the shell because `AlayaDrawer` reads it by this name — a route
  /// cannot exist in the router and be missing from the drawer without this list disagreeing.
  static const List<String> drawerDestinations = [
    dashboard,
    expenses,
    inventory,
    shopping,
    recurring,
    services,
    calendar,
    insights,
    settings,
  ];
}
```

### `lib/features/analytics/state/analytics_range.dart`

```dart
import 'package:alaya/core/enums/date_range_preset.dart';

/// Which reporting window the analytics screen is showing, and how it is remembered.
///
/// Wraps `DateRangePreset` rather than declaring a second enum: `DateRangeService` already resolves
/// every preset, and a parallel enum would need a mapping that drifts. The preset itself is never
/// stored in the database — only as an `app_settings` string — so Law L13 does not reach it
/// (`date_range_preset.dart` says as much).
abstract final class AnalyticsRange {
  /// The `app_settings` key the chosen preset is stored under.
  static const String settingsKey = 'analytics.range';

  /// The default window: the current calendar month to date.
  ///
  /// A month is the unit a household budgets in, and it is the only preset that is both bounded and
  /// non-empty on the day the app is installed.
  static const DateRangePreset fallback = DateRangePreset.thisMonth;

  /// The presets the range row offers, in the order they appear.
  ///
  /// [DateRangePreset.today] is omitted: a one-day window makes every trend a single point, and the
  /// calendar already answers "what happened today" better than a chart can.
  /// [DateRangePreset.custom] is omitted because `DateRangeService.resolve` returns null for it by
  /// design — the caller supplies the dates — and 7B ships no date-range picker. Recorded as a
  /// deferral rather than silently absent.
  static const List<DateRangePreset> presets = [
    DateRangePreset.last7Days,
    DateRangePreset.last30Days,
    DateRangePreset.thisMonth,
    DateRangePreset.lastMonth,
    DateRangePreset.thisYear,
    DateRangePreset.allTime,
  ];

  /// Parses a stored value, falling back to [fallback] for anything this build cannot offer.
  ///
  /// Defaults rather than throws, for the same reason `SafeEnumConverter` does (Law L13): a settings
  /// row is user data, a later version may write a preset this one has never heard of, and that is
  /// not a reason to fail the analytics screen. A stored `custom` or `today` also lands here, which
  /// is why the check is against [presets] and not against `DateRangePreset.values`.
  static DateRangePreset parse(String? stored) {
    for (final preset in presets) {
      if (preset.name == stored) return preset;
    }
    return fallback;
  }

  /// The value written back to `app_settings`.
  static String stored(DateRangePreset preset) => preset.name;
}
```

### `lib/features/analytics/state/drill_down_spec.dart`

```dart
/// What an analytics drill-down filters the ledger by.
///
/// The **kind** is a closed set because each arm is a different query against
/// `TransactionRepository`, and the **value** is an id or an enum name that the view-model resolves
/// to a display label. Neither carries the window: ARCH_5 §5.7 keeps a selected range in the
/// view-model rather than in the route, so a drill-down inherits whatever the analytics screen is
/// showing and the URL stays the record's identity.
///
/// **There is deliberately no `tag` arm, and the cause is one missing read rather than a design
/// choice.** Every kind here is answerable from what `TransactionRepository` already exposes — four
/// from fields the `Transaction` entity carries, and `item` from `watchLinesForItem`. A tag is not:
/// the link lives in `transaction_tags`, `Transaction` carries no tag ids, and
/// `TagRepository.watchForTransaction` is per-transaction, so filtering a window by tag would be one
/// query per row. The same gap is why 6A's `TransactionFilter` has no tag axis either — this phase
/// inherits it rather than introducing it.
///
/// So the tag surface drills **within analytics**, parent tag to child tags, which is exactly what
/// ARCH_5 §7.2 assigns to this phase. Closing the ledger path needs
/// `TagRepository.watchTransactionIdsFor(tagId)` over `transaction_tags` — one DAO query, one
/// contract method, one impl — and is recorded in this phase's coverage table with its owner.
enum DrillDownKind {
  /// One `TransactionSubtype` — the closed structural flow type.
  subtype,

  /// One payment method, by id.
  paymentMethod,

  /// One payee, by id.
  payee,

  /// One item, by id — the transactions whose lines reference it.
  item,

  /// Whether spending settled a recurring template. The value is `recurring` or `discretionary`.
  recurring;

  /// Parses a path parameter, or null when it names no kind this build knows.
  ///
  /// Null rather than a fallback, because a drill-down route is deep-linkable and guessing at the
  /// kind would filter by the wrong axis while looking like it worked.
  static DrillDownKind? parse(String? raw) {
    for (final kind in DrillDownKind.values) {
      if (kind.name == raw) return kind;
    }
    return null;
  }
}

/// One drill-down: an axis and the value on it.
class DrillDownSpec {
  /// Creates a spec.
  const DrillDownSpec({required this.kind, required this.value});

  /// Parses a spec from its two path parameters, or null when either is unusable.
  static DrillDownSpec? parse({String? kind, String? value}) {
    final parsed = DrillDownKind.parse(kind);
    if (parsed == null || value == null || value.isEmpty) return null;
    return DrillDownSpec(kind: parsed, value: value);
  }

  /// Which axis is filtered.
  final DrillDownKind kind;

  /// The id or enum name filtered on.
  final String value;

  /// Value equality, so a Riverpod family keyed on this caches one provider per drill-down rather
  /// than rebuilding on every navigation.
  @override
  bool operator ==(Object other) =>
      other is DrillDownSpec && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => 'DrillDownSpec(${kind.name}, $value)';
}
```

### `lib/features/analytics/providers/analytics_providers.dart`

```dart
/// View-model state for the analytics screens (ARCH_5 U19).
///
/// **Nothing here declares a repository or an engine.** The range, the resolved window, the display
/// precision and the cache action are screen state; `analyticsServiceProvider`,
/// `analyticsCacheServiceProvider` and every repository live in `lib/app/providers/` and are watched
/// from here (ARCH_1 §7.3, Law U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/state/analytics_range.dart';

/// The window every figure on the analytics screen is bounded by, restored from `app_settings`.
final analyticsRangeProvider = NotifierProvider<AnalyticsRangeNotifier, DateRangePreset>(
  AnalyticsRangeNotifier.new,
);

/// Holds and persists the chosen reporting window.
///
/// The same shape as 6F's `InsightSideNotifier`: a synchronous default so the first frame has a
/// window, then an unawaited restore. A `FutureProvider` here would make every chart on the screen
/// wait on a settings read to learn which month it is showing.
class AnalyticsRangeNotifier extends Notifier<DateRangePreset> {
  @override
  DateRangePreset build() {
    unawaited(_restore());
    return AnalyticsRange.fallback;
  }

  Future<void> _restore() async {
    final stored = await ref.read(settingsRepositoryProvider).readValue(AnalyticsRange.settingsKey);
    final restored = AnalyticsRange.parse(stored);
    if (restored != state) state = restored;
  }

  /// Shows [preset] and remembers it.
  ///
  /// The write is not awaited: the charts should recompute on the frame the chip is tapped, and a
  /// settings row landing a millisecond later changes nothing the reader can see.
  void show(DateRangePreset preset) {
    state = preset;
    unawaited(
      ref.read(settingsRepositoryProvider).writeValue(
            key: AnalyticsRange.settingsKey,
            value: AnalyticsRange.stored(preset),
            valueType: 'string',
          ),
    );
  }
}

/// The chosen preset resolved against today.
///
/// **`DateRange` and `AnalyticsWindow` are the same record type** — both are
/// `({DateKey from, DateKey to})` — so this needs no conversion and none is written. They are
/// declared separately because `DateRangeService` and the analytics layer were built in different
/// phases, and Dart's structural records make that free rather than a mapping to maintain.
///
/// `resolve` returns null only for [DateRangePreset.custom], which `AnalyticsRange.presets` does not
/// offer; the fallback covers a preset restored from a future version's settings row.
final analyticsWindowProvider = Provider<AnalyticsWindow>((ref) {
  final today = ref.watch(clockProvider).today();
  final preset = ref.watch(analyticsRangeProvider);
  final service = ref.watch(dateRangeServiceProvider);
  return service.resolve(preset, today) ??
      service.resolve(AnalyticsRange.fallback, today)!;
});

/// The window immediately before [analyticsWindowProvider], for a period-over-period comparison.
///
/// `precedingWindowOf` rather than `previousWholeMonth`: the honest comparison for "last 30 days" is
/// the 30 days before those, not a calendar month of a different length.
final analyticsPreviousWindowProvider = Provider<AnalyticsWindow>((ref) {
  return ref.watch(dateRangeServiceProvider).precedingWindowOf(ref.watch(analyticsWindowProvider));
});

/// The home currency every converted figure is expressed in.
final analyticsCurrencyProvider = FutureProvider<String>((ref) async {
  return await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      analyticsFallbackHomeCurrencyCode;
});

/// The home currency's minor-unit precision (ARCH_1 §4.1).
///
/// Read rather than assumed, because `AmountText` defaults to 2 and JPY has none — rendering
/// `¥1,200.00` is wrong, and hardcoding `100` anywhere is what the `currencies` table exists to
/// prevent.
final analyticsDigitsProvider = FutureProvider<int>((ref) async {
  final code = await ref.watch(analyticsCurrencyProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// One named currency's minor-unit precision.
///
/// **Needed because not every figure on this screen is in the home currency.** A balance trend stays in
/// its account's own currency — converting each point at its own date would make the line move when
/// rates moved rather than when money did — and rendering a yen balance with the home currency's two
/// digits would print `¥1,200.00` for `¥1,200`. `AmountText` defaults to 2 and says a screen holding
/// the currency should pass the real value; this is how it gets it.
final analyticsDigitsForCurrencyProvider =
    FutureProvider.autoDispose.family<int, String>((ref, currencyCode) async {
  final currency = await ref.watch(currencyRepositoryProvider).byCode(currencyCode);
  return currency?.decimalDigits ?? 2;
});

/// How many amounts currently cannot be converted into the home currency.
///
/// The stream Phase 7B implemented over `UnconvertedCounter`; it was `Stream.value(0)` until this
/// phase (ARCH_3 §1.5, ARCH_5 §7.3). Watched here so the screen's header can report a partial total
/// once, rather than every card repeating the same caveat.
final analyticsUnconvertedProvider = StreamProvider<int>(
  (ref) => ref.watch(currencyRepositoryProvider).watchUnconvertedCount(),
);

/// Clears the memoised analytics results and reports the outcome.
///
/// **This is the whole of `analytics_cache`'s user-facing surface** (ARCH_5 §7.1, §7.3: "invisible by
/// design; only 'clear cache' ever surfaces").
///
/// ARCH_5 §7.1 assigns the control to Settings, and Settings is a `PlaceholderScreen` until Phase 8A
/// — so it ships on the analytics screen itself, as a quiet row after the figures in the manner of
/// archetype E's destructive actions. It could not go in the app bar: `Routes.insights` is a shell
/// destination and the app bar belongs to `_ShellScaffold`, so an action added there would appear on
/// all nine destinations. Phase 8A's Settings entry must call this same notifier rather than the
/// service directly (Law U22).
final analyticsCacheControllerProvider =
    NotifierProvider<AnalyticsCacheController, AsyncValue<DateKey?>>(
  AnalyticsCacheController.new,
);

/// Owns the clear-cache action and the date it last succeeded on.
///
/// The state is an `AsyncValue` so the row can disable itself while clearing and render the
/// repository's own message on failure (Laws U4, U9) — not because the value itself is fetched.
class AnalyticsCacheController extends Notifier<AsyncValue<DateKey?>> {
  @override
  AsyncValue<DateKey?> build() => const AsyncData<DateKey?>(null);

  /// Invalidates every cached result, then recomputes what is on screen.
  ///
  /// Returns whether it succeeded, so the caller can choose between a result snack and a failure
  /// snack; the message stays in [state] for the row to render in place.
  ///
  /// **Coarse by design.** `AnalyticsCacheService.invalidateOnWrite` drops everything rather than
  /// tracking which of the twenty-four queries a row touches — that dependency graph is a thing to
  /// maintain and get wrong, and recomputing on the next open is cheap by comparison.
  Future<bool> clear() async {
    state = const AsyncLoading<DateKey?>();
    try {
      await ref.read(analyticsCacheServiceProvider).invalidateOnWrite();
      state = AsyncData<DateKey?>(ref.read(clockProvider).today());
      // Dropping the rows is not enough on its own: a provider that already resolved is holding the
      // figure it computed, and without this the screen would show the same numbers over an empty
      // cache and the action would look like it did nothing (Law U9).
      ref.invalidate(analyticsServiceProvider);
      return true;
    } catch (error, stackTrace) {
      // The service swallows its own read and write failures, so reaching here means the delete
      // itself failed. Surfaced rather than ignored: the alternative is a button that silently does
      // nothing, which U9 calls the worst outcome available.
      state = AsyncError<DateKey?>(error, stackTrace);
      return false;
    }
  }
}
```

### `lib/features/analytics/providers/chart_providers.dart`

```dart
/// One view-model provider per ARCH_3 §5.1 query (ARCH_5 U19).
///
/// **Every figure is its own provider, and that is what makes archetype F's "one failing card never
/// blanks the screen" true rather than aspirational.** A single provider returning all twenty-four
/// results would fail as a unit.
///
/// All of them watch `analyticsWindowProvider`, so changing the range chip recomputes the screen with
/// no per-card plumbing. All are `autoDispose`: leaving the screen should release a month of
/// aggregates rather than hold them for a session.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/services/analytics/analytics_cache_service.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';

/// An item named for a family key, so a provider caches per item rather than per rebuild.
///
/// A record, so Riverpod compares by value. The name travels with the id because
/// `AnalyticsService.unitPriceTrend` takes both — the port returns ids and the service will not guess
/// a label it was not given.
typedef AnalyticsItemRef = ({String id, String name});

// ── the headline ──────────────────────────────────────────────────────────────────────────

/// Total spend in the window and how concentrated it is — queries 8 and 22.
///
/// **One query serves the headline figure and the concentration card**, because
/// `Concentration.total` *is* total spend in the home currency. `AnalyticsPort.totalSpend` exists and
/// `AnalyticsService` never calls it: the service derives the total from `spendBySubtype` instead, so
/// asking the port again would be a second read for a number already in hand.
final analyticsHeadlineProvider = FutureProvider.autoDispose<Concentration>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.categoryConcentration(ref.watch(analyticsWindowProvider));
});

/// The same figure over the preceding window of equal length, for a period-over-period line.
final analyticsPreviousHeadlineProvider =
    FutureProvider.autoDispose<Concentration>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.categoryConcentration(ref.watch(analyticsPreviousWindowProvider));
});

// ── 1-4: where it went ────────────────────────────────────────────────────────────────────

/// Query 1 — spend by subtype.
///
/// The slices carry the **enum name** as both key and label, because that is what SQL grouped by. A
/// surface renders `slice.key` through an ARB lookup and never `slice.label`, or an untranslated
/// `grocery` reaches the screen (Law U5).
final spendBySubtypeProvider = FutureProvider.autoDispose<MoneySeries>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.spendBySubtype(ref.watch(analyticsWindowProvider));
});

/// Query 2 — spend by tag. Labels here **are** data, so they render directly.
///
/// A transaction carrying two tags contributes to both slices, so these do not sum to total spend.
/// The surface says so rather than presenting them as a partition.
final spendByTagProvider = FutureProvider.autoDispose<MoneySeries>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.spendByTag(ref.watch(analyticsWindowProvider));
});

/// Query 3 — spend by payment method.
final spendByPaymentMethodProvider = FutureProvider.autoDispose<MoneySeries>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.spendByPaymentMethod(ref.watch(analyticsWindowProvider));
});

/// Query 4 — the top payees by spend, ranked after conversion.
final topPayeesProvider = FutureProvider.autoDispose<MoneySeries>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.topPayeesBySpend(ref.watch(analyticsWindowProvider));
});

/// Query 8 — grocery's share of total spend, or null when nothing was spent on groceries.
final groceryShareProvider = FutureProvider.autoDispose<ShareOfTotal?>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.groceryShareOfSpend(ref.watch(analyticsWindowProvider));
});

// ── the tag hierarchy, for the one-level drill ARCH_5 §7.2 assigns ────────────────────────

/// Every tag by id, so a slice can be rolled up to its parent.
///
/// `watchAll` rather than `watchRoots` plus `watchChildren`: the rollup needs the whole
/// `id -> parentTagId` map in one place, and the tag table is small enough that two streams would be
/// more work than one map.
final analyticsTagsByIdProvider = StreamProvider.autoDispose<Map<String, Tag>>(
  (ref) => ref
      .watch(tagRepositoryProvider)
      .watchAll()
      .map((tags) => {for (final tag in tags) tag.id: tag}),
);

/// One tag's spend and the spend of its children, for the tag card's two levels.
class TagSpendNode {
  /// Creates a node.
  const TagSpendNode({
    required this.tag,
    required this.own,
    required this.rolledUp,
    required this.children,
  });

  /// The tag itself. May be soft-deleted, which still labels old transactions (anomaly A36).
  final Tag tag;

  /// What was spent against this tag alone.
  final Money own;

  /// [own] plus every child's spend — what the top level shows.
  final Money rolledUp;

  /// This tag's children that have spend in the window, largest first.
  final List<TagSpendNode> children;

  /// Whether drilling into this node would show anything new.
  bool get canDrill => children.isNotEmpty;
}

/// Root tags with their children rolled up, largest first — the tag card's feed.
///
/// **This is the whole of `tags.parentTagId`'s analytics surface** (ARCH_5 §7.2). One level, because
/// the schema permits exactly one and the repository enforces it (ARCH_2 §3).
///
/// A slice whose tag is missing from the map is dropped rather than shown parentless: it means the
/// tag stream and the spend query disagreed for a frame, and inventing a row for it would flicker.
final tagSpendTreeProvider =
    FutureProvider.autoDispose<List<TagSpendNode>>((ref) async {
  final series = await ref.watch(spendByTagProvider.future);
  final tags = await ref.watch(analyticsTagsByIdProvider.future);
  final code = await ref.watch(analyticsCurrencyProvider.future);

  final own = <String, Money>{};
  for (final slice in series.slices) {
    own[slice.key] = slice.amount;
  }

  final childrenOf = <String, List<TagSpendNode>>{};
  final roots = <String, Money>{};
  for (final entry in own.entries) {
    final tag = tags[entry.key];
    if (tag == null) continue;
    final parentId = tag.parentTagId;
    if (parentId == null) continue;
    (childrenOf[parentId] ??= <TagSpendNode>[]).add(
      TagSpendNode(
        tag: tag,
        own: entry.value,
        rolledUp: entry.value,
        children: const <TagSpendNode>[],
      ),
    );
  }

  for (final entry in own.entries) {
    final tag = tags[entry.key];
    if (tag == null || tag.isChild) continue;
    roots[entry.key] = entry.value;
  }
  // A parent with no spend of its own but children that do spend still belongs at the top level:
  // "Grocery ₹0" would be wrong and hiding it would lose the children entirely.
  for (final parentId in childrenOf.keys) {
    if (tags.containsKey(parentId)) roots.putIfAbsent(parentId, () => Money.zero(code));
  }

  final nodes = <TagSpendNode>[];
  for (final entry in roots.entries) {
    final children = (childrenOf[entry.key] ?? const <TagSpendNode>[]).toList()
      ..sort((a, b) => b.rolledUp.minor.compareTo(a.rolledUp.minor));
    final rolled = children.fold<int>(entry.value.minor, (sum, c) => sum + c.rolledUp.minor);
    nodes.add(
      TagSpendNode(
        tag: tags[entry.key]!,
        own: entry.value,
        rolledUp: Money(rolled, code),
        children: children,
      ),
    );
  }
  nodes.sort((a, b) => b.rolledUp.minor.compareTo(a.rolledUp.minor));
  return nodes;
});

// ── 5-7, 21: over time ────────────────────────────────────────────────────────────────────

/// Query 5 — income against expense, month by month.
final incomeVsExpenseProvider = FutureProvider.autoDispose<IncomeVsExpense>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.incomeVsExpense(ref.watch(analyticsWindowProvider));
});

/// Query 6 — net cash flow per month, from the signed ledger.
final netCashFlowProvider = FutureProvider.autoDispose<NetCashFlow>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.netCashFlowByMonth(ref.watch(analyticsWindowProvider));
});

/// Query 7 — one account's running balance, in that account's own currency.
///
/// Never converted: converting each point at its own date would make the line move when rates moved
/// rather than when money did.
final balanceTrendProvider =
    FutureProvider.autoDispose.family<BalanceTrend, String>((ref, accountId) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.balanceTrend(accountId, ref.watch(analyticsWindowProvider));
});

/// The accounts the balance-trend card can offer.
final analyticsAccountsProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// Query 21 — spend bucketed by weekday or day of month, **through the cache**.
///
/// **One of exactly two cached queries in this phase, and the gate is
/// `AnalyticsCacheService.shouldCache` rather than a preference.** This one earns it: the bucket is
/// `strftime` over a rebuilt date string, so no index in ARCH_2 §11 can serve the grouping and the
/// cost grows with the whole window rather than with the number of buckets.
///
/// The other twenty-two are computed live. §5.2 asks for a cache "for anything over ~200 ms", and the
/// service's own doc comment says why the rest are not: a cache on a query that already runs in 5 ms
/// costs a read, a write, an invalidation path and a staleness bug and buys nothing.
final spendHeatmapProvider =
    FutureProvider.autoDispose.family<SpendHeatmap, bool>((ref, byWeekday) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  final cache = ref.watch(analyticsCacheServiceProvider);
  final window = ref.watch(analyticsWindowProvider);

  if (!cache.shouldCache(heatmapEstimatedCost)) {
    return service.spendHeatmap(window, byWeekday: byWeekday);
  }
  // Encoded then decoded even on a miss, deliberately: the cache stores strings, so one path through
  // the codec is simpler than two and guarantees a hit and a miss return the same shape.
  final payload = await cache.readOrCompute(
    queryName: 'spendHeatmap',
    params: {...cache.windowParams(window), 'byWeekday': byWeekday},
    compute: () async =>
        _encodeHeatmap(await service.spendHeatmap(window, byWeekday: byWeekday)),
  );
  return _decodeHeatmap(payload);
});

/// What query 21 is estimated to cost, measured against `AnalyticsCacheService.cacheThreshold`.
const Duration heatmapEstimatedCost = Duration(milliseconds: 250);

/// What query 13 is estimated to cost.
const Duration inventoryValueEstimatedCost = Duration(milliseconds: 220);

// ── 9-12, 23, 24: items and prices ────────────────────────────────────────────────────────

/// Query 9 — the top items by spend, ranked after conversion.
final topItemsBySpendProvider =
    FutureProvider.autoDispose<List<ItemSpend>>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.topItemsBySpend(ref.watch(analyticsWindowProvider));
});

/// Query 10 — the top items by quantity bought, per unit category.
///
/// Not ranked across categories and not converted: grams and pieces are not comparable at all
/// (Law L8), so the surface groups by category rather than producing a single ordering that would
/// mean nothing.
final topItemsByQuantityProvider =
    FutureProvider.autoDispose<List<ItemQuantity>>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.topItemsByQuantity(ref.watch(analyticsWindowProvider));
});

/// Query 11 — the dearest single purchase of one item, in the currency it was bought in.
final dearestPurchaseProvider = FutureProvider.autoDispose
    .family<DearestPurchase?, AnalyticsItemRef>((ref, item) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.dearestPurchaseOfItem(item.id, item.name, ref.watch(analyticsWindowProvider));
});

/// Queries 12 and 24 — one item's unit-price trend and the change across it.
///
/// **One provider for both queries, because query 24 is query 12's data.**
/// `AnalyticsService.unitPriceTrend` calls `pricePerBaseUnitHistory` and returns its points
/// alongside the percentage change, so a second provider would run the same read twice. The surface
/// draws the points (24) and states the change (12).
final unitPriceTrendProvider = FutureProvider.autoDispose
    .family<UnitPriceTrend, AnalyticsItemRef>((ref, item) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.unitPriceTrend(item.id, item.name, ref.watch(analyticsWindowProvider));
});

/// The item whose unit price moved most across the window — the personal-inflation headline.
///
/// **This is the screenshot** (ARCH_3 §5.1: *"your potatoes cost 34% more than in January"*). It is
/// derived rather than asked for: no query returns "the most interesting item", so the candidates are
/// the top items by spend — the ones the reader actually buys — and the winner is the largest
/// absolute change among them.
///
/// Capped at [inflationCandidateCount] queries. Uncapped this would be one read per item in the
/// house, on a card that shows one line.
///
/// Null when nothing has two priced purchases in the window, which is the ordinary case for a new
/// install and reads as an absence rather than as a failure.
final personalInflationProvider =
    FutureProvider.autoDispose<UnitPriceTrend?>((ref) async {
  final items = await ref.watch(topItemsBySpendProvider.future);
  UnitPriceTrend? best;
  for (final item in items.take(inflationCandidateCount)) {
    final trend = await ref.watch(
      unitPriceTrendProvider((id: item.itemId, name: item.itemName)).future,
    );
    final change = trend.percentChange;
    if (change == null) continue;
    final bestChange = best?.percentChange;
    if (bestChange == null || change.abs() > bestChange.abs()) best = trend;
  }
  return best;
});

/// How many of the top-spend items are probed for a price trend.
const int inflationCandidateCount = 5;

/// Query 23 — the average grocery basket.
final averageBasketProvider = FutureProvider.autoDispose<BasketStats>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.averageGroceryBasket(ref.watch(analyticsWindowProvider));
});

// ── 13-16: the home ───────────────────────────────────────────────────────────────────────

/// Query 13 — inventory value on hand, per currency, **through the cache**.
///
/// The second of the two cached queries. It is unbounded by design — stock on hand has no window —
/// so its cost grows with the shelf rather than with the range, and it is the one figure on the
/// screen that a narrower range cannot make cheaper.
///
/// Per currency rather than one total: batch cost currency is per row, and a single figure would be
/// adding rupees to yen (anomaly A34).
final inventoryValueProvider =
    FutureProvider.autoDispose<InventoryValue>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  final cache = ref.watch(analyticsCacheServiceProvider);
  if (!cache.shouldCache(inventoryValueEstimatedCost)) {
    return service.inventoryValueOnHand();
  }
  final payload = await cache.readOrCompute(
    queryName: 'inventoryValueOnHand',
    // No window: the figure is "right now", so the parameter set is empty and the entry is a
    // singleton. `hashParams({})` is stable, so this still gets its own row.
    params: const <String, Object?>{},
    compute: () async => _encodeInventoryValue(await service.inventoryValueOnHand()),
  );
  return _decodeInventoryValue(payload);
});

/// Query 14 — food waste, in quantity and money.
///
/// Reversed movements are already excluded by the adapter, so this reports what was wasted and not
/// what was wasted and then corrected.
final wasteTotalsProvider =
    FutureProvider.autoDispose<List<ItemWasteTotal>>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.wasteTotals(ref.watch(analyticsWindowProvider));
});

/// Query 15 — batches expiring within [days] of today, soonest first.
///
/// Keyed on days rather than on the window: expiry is about the future and the reporting range is
/// about the past, so tying the two would make "last month" show nothing expiring.
final expiringBatchesProvider =
    FutureProvider.autoDispose.family<List<ExpiringBatch>, int>((ref, days) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.itemsExpiringWithin(days);
});

/// The expiry horizon the home section shows.
const int expiryHorizonDays = 14;

/// Query 16 — how many items are low on stock, as one point.
///
/// One point and not a history: `v_low_stock` reflects the present and stock is not versioned, so
/// "how many were low last Tuesday" would mean replaying the movement ledger against thresholds that
/// may since have changed.
final lowStockTodayProvider = FutureProvider.autoDispose<LowStockPoint>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.lowStockCountToday();
});

// ── 17-20: commitments and assets ─────────────────────────────────────────────────────────

/// Query 17 — the fixed monthly commitment total, every interval normalised to a month.
final monthlyCommitmentProvider =
    FutureProvider.autoDispose<MonthlyCommitment>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.monthlyCommitmentTotal();
});

/// Query 18 — the recurring against discretionary split.
final recurringSplitProvider = FutureProvider.autoDispose<RecurringSplit>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.recurringVsDiscretionary(ref.watch(analyticsWindowProvider));
});

/// Query 19 — lifetime service cost per asset, per currency.
///
/// Disposed assets are included: the money you put into a TV stays in the analytics after you sell
/// it, which is the point of `status = disposed` rather than a delete.
final serviceCostByAssetProvider =
    FutureProvider.autoDispose<List<AssetServiceCost>>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.lifetimeServiceCostByAsset(ref.watch(analyticsWindowProvider));
});

/// Query 20 — the warranty coverage timeline.
final warrantyCoverageProvider =
    FutureProvider.autoDispose<List<WarrantyCoverage>>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.warrantyCoverage();
});

// ── cache codecs ──────────────────────────────────────────────────────────────────────────
//
// Two, not twenty-four. `AnalyticsCacheService` stores strings, so caching a result type means a
// codec for it — and writing twenty-four to satisfy the letter of ARCH_3 §5.2 would contradict its
// reasoning, which is that a cache is only worth its invalidation path above roughly 200 ms.
//
// `Money` encodes as minor units plus its code and never as a decimal (Law L1): a JSON number for
// `12.34` would be a double crossing a persistence boundary, which is exactly what L1 forbids.

String _encodeHeatmap(SpendHeatmap heatmap) => jsonEncode({
      'cells': [
        for (final cell in heatmap.cells)
          {
            'b': cell.bucket,
            'm': cell.amount.minor,
            'c': cell.amount.currencyCode,
            'n': cell.transactionCount,
          },
      ],
      'approx': heatmap.quality.approximateCount,
      'unconv': heatmap.quality.unconvertedCount,
    });

SpendHeatmap _decodeHeatmap(String payload) {
  final root = jsonDecode(payload) as Map<String, Object?>;
  final raw = root['cells'] as List<Object?>? ?? const <Object?>[];
  // `const <HeatmapCell>[]` and never a bare `const []`: a record field takes the literal's inferred
  // type verbatim, so `List<dynamic>` would not satisfy `List<HeatmapCell>` (ARCH_4 R17).
  final cells = <HeatmapCell>[];
  for (final entry in raw) {
    final cell = entry as Map<String, Object?>;
    cells.add((
      bucket: cell['b']! as int,
      amount: Money(cell['m']! as int, cell['c']! as String),
      transactionCount: cell['n']! as int,
    ));
  }
  return (
    cells: cells.isEmpty ? const <HeatmapCell>[] : cells,
    quality: (
      approximateCount: root['approx'] as int? ?? 0,
      unconvertedCount: root['unconv'] as int? ?? 0,
    ),
  );
}

String _encodeInventoryValue(InventoryValue value) => jsonEncode({
      'by': {
        for (final entry in value.byCurrency.entries) entry.key: entry.value.minor,
      },
      'valued': value.batchesValued,
      'noCost': value.batchesNoCost,
    });

InventoryValue _decodeInventoryValue(String payload) {
  final root = jsonDecode(payload) as Map<String, Object?>;
  final by = root['by'] as Map<String, Object?>? ?? const <String, Object?>{};
  return (
    byCurrency: {
      for (final entry in by.entries) entry.key: Money(entry.value! as int, entry.key),
    },
    batchesValued: root['valued'] as int? ?? 0,
    batchesNoCost: root['noCost'] as int? ?? 0,
  );
}
```

### `lib/features/analytics/providers/drill_down_providers.dart`

```dart
/// View-model state for the analytics drill-down (ARCH_5 U19).
///
/// **Every axis here is answerable from what `TransactionRepository` already exposes.** Four come
/// from fields the `Transaction` entity carries, so the window's indexed query does the narrowing and
/// the predicate runs over a page of rows rather than the table. `item` needs one extra stream and
/// gets it. `tag` has no arm at all — see `drill_down_spec.dart` for the missing read and its owner.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';

/// The transaction ids whose lines reference one item.
///
/// Only the `item` arm needs this. A line-level read cannot be folded into the predicate below,
/// because a `Transaction` does not know what its lines bought — so the ids are gathered once and the
/// windowed list is filtered against the set.
final drillDownItemTransactionIdsProvider =
    StreamProvider.autoDispose.family<Set<String>, String>((ref, itemId) {
  return ref
      .watch(transactionRepositoryProvider)
      .watchLinesForItem(itemId)
      .map((lines) => {for (final line in lines) line.transactionId});
});

/// The transactions behind one analytics slice, newest first.
///
/// **The window comes from the analytics screen, not from the route** (ARCH_5 §5.7). A reader who set
/// the range to "this year" and tapped a slice expects this year's transactions; putting the dates in
/// the path would have made the two disagree the moment either changed.
///
/// Withdrawals only, matching every spend query in the adapter: a drill-down that showed the deposits
/// too would not add up to the slice it came from.
final drillDownTransactionsProvider = StreamProvider.autoDispose
    .family<List<Transaction>, DrillDownSpec>((ref, spec) {
  final window = ref.watch(analyticsWindowProvider);
  final rows = ref
      .watch(transactionRepositoryProvider)
      .watchByDateRange(from: window.from, to: window.to);

  if (spec.kind == DrillDownKind.item) {
    final ids = ref.watch(drillDownItemTransactionIdsProvider(spec.value));
    // Until the id set resolves the list stays loading rather than briefly showing every
    // transaction in the window — a flash of the unfiltered ledger reads as a broken filter.
    return ids.when(
      loading: Stream<List<Transaction>>.empty,
      error: (error, stack) => Stream<List<Transaction>>.error(error, stack),
      data: (set) => rows.map(
        (all) => [
          for (final row in all)
            if (row.kind == TransactionKind.withdrawal && set.contains(row.id)) row,
        ],
      ),
    );
  }

  return rows.map(
    (all) => [
      for (final row in all)
        if (row.kind == TransactionKind.withdrawal && _admits(spec, row)) row,
    ],
  );
});

bool _admits(DrillDownSpec spec, Transaction row) => switch (spec.kind) {
      DrillDownKind.subtype => row.subtype.name == spec.value,
      DrillDownKind.paymentMethod => row.paymentMethodId == spec.value,
      DrillDownKind.payee => row.payeeId == spec.value,
      DrillDownKind.recurring => spec.value == _recurringValue
          ? row.recurringTemplateId != null
          : row.recurringTemplateId == null,
      // Handled above, before the predicate: an item cannot be judged from the transaction alone.
      DrillDownKind.item => false,
    };

/// The `recurring` side of query 18's split, spelled as the adapter's SQL spells it.
const String _recurringValue = 'recurring';

/// One day's transactions in a drill-down, for archetype C's sticky date header.
class DrillDownDayGroup {
  /// Creates a day group.
  const DrillDownDayGroup({required this.date, required this.transactions});

  /// The civil date these share.
  final DateKey date;

  /// The transactions on [date], newest first.
  final List<Transaction> transactions;
}

/// The drill-down's transactions grouped into days, newest day first.
///
/// **Grouped by day because archetype C requires it**: a finance ledger without date grouping is
/// unreadable past twenty rows (ARCH_5 §3 C). The same shape 6A's `transactionDaysProvider` produces,
/// deliberately — a drill-down that grouped differently from the ledger it drills into would read as
/// a different screen.
final drillDownDaysProvider = Provider.autoDispose
    .family<AsyncValue<List<DrillDownDayGroup>>, DrillDownSpec>((ref, spec) {
  return ref.watch(drillDownTransactionsProvider(spec)).whenData(_groupByDay);
});

List<DrillDownDayGroup> _groupByDay(List<Transaction> rows) {
  final groups = <int, List<Transaction>>{};
  for (final row in rows) {
    groups.putIfAbsent(row.dateKey.value, () => <Transaction>[]).add(row);
  }
  final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final date in dates)
      DrillDownDayGroup(date: DateKey(date), transactions: groups[date]!),
  ];
}

/// What the drill-down totals to, **per currency**, so its header can be checked against the slice it
/// came from.
///
/// **Per currency and not one figure** (anomaly A34). These are `originalAmount`s, each in whatever
/// currency it was recorded in, and folding them into a single int would add rupees to yen — which is
/// the defect this project has a whole anomaly number for. Converting instead would need the rate table
/// and would still disagree with the slice above by whatever the slice excluded, so the honest answer is
/// one subtotal per currency, which for almost every household is one line.
final drillDownTotalsProvider = Provider.autoDispose
    .family<AsyncValue<Map<String, int>>, DrillDownSpec>((ref, spec) {
  return ref.watch(drillDownTransactionsProvider(spec)).whenData((rows) {
    final byCurrency = <String, int>{};
    for (final row in rows) {
      byCurrency.update(
        row.originalAmount.currencyCode,
        (minor) => minor + row.originalAmount.minor,
        ifAbsent: () => row.originalAmount.minor,
      );
    }
    return byCurrency;
  });
});

/// The label for one drill-down, resolved from the id the route carried.
///
/// **Resolved rather than passed.** `go_router`'s `extra` does not survive a deep link or a process
/// death, so a label carried that way would render blank on the one path where the route is reached
/// from outside the app. Returns null for the kinds whose label is an ARB string rather than data —
/// `subtype` and `recurring` — which the screen localises itself (Law U5).
final drillDownLabelProvider =
    FutureProvider.autoDispose.family<String?, DrillDownSpec>((ref, spec) async {
  switch (spec.kind) {
    case DrillDownKind.subtype:
    case DrillDownKind.recurring:
      return null;
    case DrillDownKind.payee:
      final payee = await ref.watch(payeeRepositoryProvider).byId(spec.value);
      return payee?.name;
    case DrillDownKind.item:
      final item = await ref.watch(itemRepositoryProvider).byId(spec.value);
      return item?.name;
    case DrillDownKind.paymentMethod:
      final method = await ref.watch(paymentMethodRepositoryProvider).byId(spec.value);
      return method?.name;
  }
});
```

## The chart vocabulary

Four surfaces, and only two of them touch `fl_chart`. `SliceBarList` carries every ranked
breakdown — subtype, tag, payment method, payee, item, waste, service cost — because a ranked list of
figures is what somebody deciding where their money went can actually read at a doubled text scale and
tap into, and a pie is none of those things. The package earns its place for the two shapes a list
cannot express: a trend over time, and a fixed ordered set of buckets.

### `lib/features/analytics/presentation/widgets/analytics_labels.dart`

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';

/// Turns the keys `AnalyticsPort` grouped by into labels a reader can understand.
///
/// **The adapter groups by enum name, so `slice.label` for a subtype is `grocery`.** Rendering it
/// would put an untranslated identifier on screen (Law U5). Every key whose label is *not* data goes
/// through here; keys whose labels are data — a payee, a tag, an item — render their label directly.
abstract final class AnalyticsLabels {
  /// The localised name for a `TransactionSubtype` key.
  ///
  /// **Delegates to `TransactionRow.subtypeLabel`, which is public for exactly this reason.** A tenth
  /// switch over nine subtypes is a tenth thing to update when one is renamed, and ARCH_5 §10's
  /// objection to re-deriving a rule at a call site does not stop at colours.
  ///
  /// Falls back to the raw key rather than throwing: an unrecognised name means the database holds a
  /// value this build does not know, which is what Law L13's fallback-safe storage exists to survive.
  /// A cosmetic label is not worth a crash on the analytics screen.
  static String subtype(AlayaStrings strings, String key) {
    for (final value in TransactionSubtype.values) {
      if (value.name == key) return TransactionRow.subtypeLabel(strings, value);
    }
    return key;
  }

  /// The localised name for query 18's two sides.
  static String recurringSide(AlayaStrings strings, String key) =>
      key == 'recurring' ? strings.analyticsRecurring : strings.analyticsDiscretionary;

  /// The localised name of a reporting window.
  ///
  /// Exhaustive over `DateRangePreset` on purpose: adding a preset to `AnalyticsRange.presets`
  /// without labelling it should be a compile error here, not a chip rendering its own enum name.
  /// Every key already exists in the ARB from earlier phases — this phase adds none.
  static String range(AlayaStrings strings, DateRangePreset preset) => switch (preset) {
        DateRangePreset.today => strings.rangeToday,
        DateRangePreset.last7Days => strings.rangeLast7Days,
        DateRangePreset.last30Days => strings.rangeLast30Days,
        DateRangePreset.thisMonth => strings.rangeThisMonth,
        DateRangePreset.lastMonth => strings.rangeLastMonth,
        DateRangePreset.thisYear => strings.rangeThisYear,
        DateRangePreset.allTime => strings.rangeAllTime,
        DateRangePreset.custom => strings.rangeCustom,
      };

  /// The short axis label for a heatmap bucket.
  ///
  /// **Weekdays come from `MaterialLocalizations.narrowWeekdays`, not from the ARB**, which is how
  /// 7A's month grid labels its own weekday row — locale-correct in every locale Flutter ships
  /// without seven strings a translator has to be asked for.
  ///
  /// That list is Sunday-first while ARCH_3 §5.1's buckets are 1-7 Monday-first, so `bucket % 7` maps
  /// between them: Monday's 1 lands on index 1 and Sunday's 7 wraps to index 0. It is the same
  /// expression 7A uses for a `DateTime.weekday`, for the same reason.
  ///
  /// A day-of-month bucket is its own number and needs no translation.
  static String bucket(BuildContext context, int bucket, {required bool byWeekday}) {
    if (!byWeekday) return '$bucket';
    return MaterialLocalizations.of(context).narrowWeekdays[bucket % DateTime.daysPerWeek];
  }

  /// The localised name of a `UnitCategory`.
  ///
  /// **A third copy of this switch, and that is worth recording rather than hiding.** 6B already holds
  /// two private ones — `_categoryLabel` in its line-item editor and again in its item editor — so the
  /// mapping had drifted into duplication before this phase arrived. Reaching either would mean making
  /// a private helper public in a file this phase has no other reason to carry.
  ///
  /// It cannot live on `UnitCategory` itself: that is in `core/`, and `AlayaStrings` is in `app/`
  /// (Law L12). The right home is one helper in `shared/`, which ARCH_5 §8 does not permit this phase
  /// to add without a record — so it is filed as a finding for Phase 9's sweep instead of taken here.
  static String unitCategory(AlayaStrings strings, UnitCategory category) => switch (category) {
        UnitCategory.weight => strings.unitCategoryWeight,
        UnitCategory.volume => strings.unitCategoryVolume,
        UnitCategory.count => strings.unitCategoryCount,
      };

  /// [share] as a whole-number percentage in the active locale.
  ///
  /// One definition, because five surfaces state a share and five `NumberFormat` calls is five places
  /// for the decimal count to drift — the same objection ARCH_5 §10 raises to re-deriving red/green at
  /// a call site.
  ///
  /// Whole numbers: "34%" is the insight, and "33.7%" implies a precision a ratio of two rounded
  /// totals does not have.
  static String percent(BuildContext context, double share) =>
      NumberFormat.decimalPercentPattern(
        locale: Localizations.localeOf(context).toLanguageTag(),
        decimalDigits: 0,
      ).format(share);
}
```

### `lib/features/analytics/presentation/widgets/slice_bar_list.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// One row of a [SliceBarList].
class SliceBar {
  /// Creates a row.
  const SliceBar({
    required this.label,
    required this.value,
    required this.share,
    this.detail,
    this.onTap,
    this.swatch,
  });

  /// What this slice is, already localised.
  final String label;

  /// The figure, **already rendered by its own widget** — an `AmountText` or a `QtyText`.
  ///
  /// A `Money` field would have hardcoded `AmountText` here and made this list unable to show a
  /// quantity, which query 10 needs; formatting either into a `String` at the call site would bypass
  /// the only path from a `Money` or a `Qty` to pixels (Law U7). The same reasoning gives
  /// `KeyValueRow` its `valueWidget`.
  final Widget value;

  /// Its share of the largest slice, `0.0`-`1.0`, which sets the bar's length.
  final double share;

  /// An optional second line — a count, a unit, a date.
  final String? detail;

  /// Opens this slice's drill-down.
  final VoidCallback? onTap;

  /// The colour of this slice's wedge, when a donut sits above the list.
  ///
  /// Present only where a ring is showing. It is what ties a row to its arc, and it is why the ring can
  /// use a single-hue ramp instead of categorical colours — identity lives here, in text, beside a
  /// figure (Law U17: colour is never the only signal).
  final Color? swatch;
}

/// A ranked breakdown as labelled bars, largest first.
///
/// **This is the workhorse surface and it deliberately uses no chart library.** A pie is unreadable
/// at a doubled text scale, cannot label eight slices, and gives the reader nothing to tap; a ranked
/// list of figures is what somebody deciding where their money went actually needs, and every row is
/// a 48dp target into the ledger behind it (Laws U3, U13, U15).
///
/// `fl_chart` earns its place for the two shapes a list genuinely cannot express — a trend over time
/// and a bucketed heatmap — and nowhere else.
class SliceBarList extends StatelessWidget {
  /// Creates a breakdown of [slices].
  const SliceBarList({
    required this.slices,
    this.maxRows = 6,
    this.showBars = true,
    super.key,
  });

  /// The slices, already ordered.
  final List<SliceBar> slices;

  /// Whether each row draws its proportional bar.
  ///
  /// False where a donut sits above the list: the ring already carries the proportion, and a bar
  /// repeating it is the second accessory to remove. The swatch and the figure stay.
  final bool showBars;

  /// How many rows to show before stopping.
  ///
  /// A card is a shortlist, not a second screen: the drill-down holds the rest. Six is what fits
  /// above the fold on the narrowest supported phone.
  final int maxRows;

  /// Above this text scale a row stacks its figure under its label (Law U21).
  static const double _stackAboveScale = 1.5;

  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= _stackAboveScale;
    // A plain Column, not a ListView: this is a bounded shortlist of at most [maxRows] inside a card
    // that is already inside the screen's scroll view. Law U13 is about lists fed by a repository
    // stream, and a nested scrollable here would put two gestures in one arena (ARCH_6 P2).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final slice in slices.take(maxRows))
          _SliceRow(slice: slice, stacked: stacked, showBar: showBars),
      ],
    );
  }
}

class _SliceRow extends StatelessWidget {
  const _SliceRow({
    required this.slice,
    required this.stacked,
    required this.showBar,
  });

  final SliceBar slice;
  final bool stacked;
  final bool showBar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;

    final text = Text(
      slice.label,
      style: AlayaTypography.body.copyWith(color: theme.colorScheme.onSurface),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    final label = slice.swatch == null
        ? text
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Decorative: the arc it matches is already excluded from semantics, and the label beside
              // it carries the identity.
              ExcludeSemantics(child: _Swatch(color: slice.swatch!)),
              const SizedBox(width: AlayaSpacing.xs),
              Flexible(child: text),
            ],
          );
    final amount = slice.value;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stacked) ...[
          label,
          const SizedBox(height: AlayaSpacing.xxs),
          Align(alignment: Alignment.centerLeft, child: amount),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: label),
              const SizedBox(width: AlayaSpacing.sm),
              amount,
            ],
          ),
        if (slice.detail != null) ...[
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            slice.detail!,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ],
        if (showBar) ...[
          const SizedBox(height: AlayaSpacing.xs),
          ExcludeSemantics(child: _Bar(share: slice.share)),
        ],
      ],
    );

    // One semantics node per row, so a screen reader reads "Groceries, 4,200 rupees" as one thing
    // rather than three fragments and an unlabelled bar (ARCH_5 §6).
    //
    // **`container: true` with no `label`, deliberately.** A hand-written label would replace the
    // children's own semantics — including `AmountText`'s, which is the only thing that knows how to
    // say a `Money` out loud. Building that string here would mean formatting minor units at the call
    // site, which is the Law U7 violation the widget exists to prevent. Only the bar is excluded: it
    // carries nothing the figure beside it does not.
    final semantics = Semantics(
      container: true,
      button: slice.onTap != null,
      child: body,
    );

    final padded = Padding(
      padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.xs),
      child: semantics,
    );

    if (slice.onTap == null) return padded;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: slice.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget),
          child: padded,
        ),
      ),
    );
  }
}

/// The dot tying a row to its wedge.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  /// On the spacing scale, like every other dimension (Law U6).
  static const double _size = AlayaSpacing.sm;

  @override
  Widget build(BuildContext context) => Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// The proportional bar under a row.
class _Bar extends StatelessWidget {
  const _Bar({required this.share});

  final double share;

  /// The bar's thickness. On the spacing scale because Law U6 admits no other source of a dimension.
  static const double _thickness = AlayaSpacing.xs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Clamped, because `share` is a ratio computed from sums and a rounding artefact above 1 would
    // hand `FractionallySizedBox` a factor it asserts on.
    final factor = share.isFinite ? share.clamp(0.0, 1.0) : 0.0;
    return ClipRRect(
      borderRadius: AlayaRadii.borderXs,
      child: SizedBox(
        height: _thickness,
        child: ColoredBox(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: factor,
            child: ColoredBox(color: theme.colorScheme.primary),
          ),
        ),
      ),
    );
  }
}
```

### `lib/features/analytics/presentation/widgets/analytics_donut_chart.dart`

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_line_chart.dart';

/// One wedge of an [AnalyticsDonutChart], and one row of the list beneath it.
///
/// **The same object feeds the ring and the rows**, which is the point: build them from two sources and
/// they drift, so the fifth-largest wedge ends up a different colour from the fifth row.
class AnalyticsSlice {
  /// Creates a slice.
  const AnalyticsSlice({
    required this.label,
    required this.value,
    required this.color,
    this.key,
  });

  /// What it is, already localised.
  final String label;

  /// Its magnitude — minor units or base-milli. Only the ratio between slices is used.
  final int value;

  /// Its colour in both the ring and the row's swatch.
  final Color color;

  /// The drill-down key, or null for a slice that is not a filterable axis.
  final String? key;
}

/// The palette a donut's wedges take, largest first.
///
/// **A single-hue ramp, not a set of categorical colours.** Alaya's palette is data — five presets the
/// user chooses between (ARCH_5 §2.1) — so a hand-picked categorical set would clash under at least one
/// of them, and `warning`/`danger`/`success` are reserved for state and never for emphasis (§2.4).
/// Stepping the alpha on `primary` cannot clash with anything, and it reads in the right order: the
/// biggest share is the darkest.
///
/// Identity comes from the row beneath, whose swatch is this same colour. The ring carries proportion
/// only, which is the one thing a list genuinely cannot show.
List<Color> analyticsSliceColors(BuildContext context, int count) {
  final base = Theme.of(context).colorScheme.primary;
  const steps = [1.0, 0.78, 0.60, 0.45, 0.33, 0.24, 0.17];
  return [
    for (var i = 0; i < count; i++)
      base.withValues(alpha: steps[i < steps.length ? i : steps.length - 1]),
  ];
}

/// Builds the slices for a donut and its list, grouping the tail into one remainder wedge.
///
/// **Grouped because a ring of twelve slivers is not readable.** Past six wedges the arcs are thinner
/// than the gaps between them and the ordering stops being legible, so the tail becomes one wedge that
/// says what it is. [remainder] lets a caller supply a known total — the concentration card knows what
/// the top three leave behind — instead of it being derived from the slices given.
///
/// Zero and negative magnitudes are dropped: `PieChart` divides by the total and a zero wedge draws a
/// seam with no area, which reads as a rendering fault rather than as nothing.
List<AnalyticsSlice> analyticsSlices(
  BuildContext context,
  List<({String label, int value, String? key})> input, {
  required String otherLabel,
  int maxSlices = 6,
  int remainder = 0,
}) {
  final positive = [for (final row in input) if (row.value > 0) row];
  final head = positive.take(maxSlices).toList();
  final tail = positive.skip(maxSlices).fold<int>(0, (sum, row) => sum + row.value) + remainder;
  final colors = analyticsSliceColors(context, head.length + (tail > 0 ? 1 : 0));

  return [
    for (var i = 0; i < head.length; i++)
      AnalyticsSlice(
        label: head[i].label,
        value: head[i].value,
        color: colors[i],
        key: head[i].key,
      ),
    // No key: "everything else" is not an axis anything can be filtered by, so the row it produces is
    // deliberately not tappable (ARCH_5 §10's objection to a control that looks live and is not).
    if (tail > 0)
      AnalyticsSlice(label: otherLabel, value: tail, color: colors[head.length]),
  ];
}

/// A ring showing how a total divides, with a figure in the middle.
///
/// **Used only where the data is a genuine partition of one whole.** Spend by kind, the fixed-against-
/// chosen split and the concentration of spending all are. Tags are not — one purchase can carry two, so
/// the slices sum past the total and a ring would assert a whole that does not exist. Ranked lists
/// (payees, items) are not either: the top ten is not everything. Those stay as bars.
///
/// **The ring never carries a number.** Wedge titles are off: a `Money` in a 40dp arc is the clipping U7
/// forbids, and a percentage there duplicates what the rows already say. Touch is off for the same reason
/// as the other charts — a tooltip is a timed surface, and ARCH_5 §6 requires nothing live only there.
///
/// **Excluded from semantics.** The list beneath is the accessible rendering of the same slices, so
/// describing both makes a screen reader read the card twice.
class AnalyticsDonutChart extends StatelessWidget {
  /// Creates a ring of [slices].
  const AnalyticsDonutChart({
    required this.slices,
    this.centreTop,
    this.centreBottom,
    super.key,
  });

  /// The wedges, largest first, from [analyticsSlices].
  final List<AnalyticsSlice> slices;

  /// The emphasised line in the hole — usually a percentage.
  final String? centreTop;

  /// The quiet line under it — usually what that percentage is of.
  final String? centreBottom;

  /// How much of the box the hole takes. Two fifths leaves an arc thick enough to compare by eye and a
  /// hole wide enough for a percentage at a doubled text scale.
  static const double _holeFraction = 0.4;

  /// The gap between wedges, on the spacing scale (Law U6).
  static const double _gap = AlayaSpacing.xxs / 2;

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) return const SizedBox.shrink();
    final semantic = context.semantic;

    return ExcludeSemantics(
      child: AnalyticsPlotBox(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Sized from the box's own shorter side rather than from a constant, so the ring stays a
            // ring at any text scale: `AnalyticsPlotBox` grows the height and a fixed radius would
            // then be an ellipse cropped by the width.
            final extent = constraints.biggest.shortestSide;
            final hole = extent * _holeFraction / 2;
            final ring = extent / 2 - hole;

            return Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: _gap,
                    centerSpaceRadius: hole,
                    // From the top, clockwise: the largest wedge starts where a reader looks first.
                    startDegreeOffset: -90,
                    // Not `const`: `PieTouchData` has no const constructor, unlike `LineTouchData` and
                    // `BarTouchData`. Three sibling APIs, two of them const — exactly the inconsistency
                    // ARCH_4 R22 means by "verified by compiling, not by reading about it".
                    pieTouchData: PieTouchData(enabled: false),
                    sections: [
                      for (final slice in slices)
                        PieChartSectionData(
                          // `toDouble()` on a magnitude that is an int everywhere else — the same
                          // boundary the line chart's `FlSpot` crosses, and legal for the same reason:
                          // an arc sweep is geometry, not money (Law L1).
                          value: slice.value.toDouble(),
                          color: slice.color,
                          radius: ring,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
                if (centreTop != null || centreBottom != null)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (centreTop != null)
                        Text(centreTop!, style: AlayaTypography.amountSmall),
                      if (centreBottom != null)
                        Text(
                          centreBottom!,
                          style: AlayaTypography.overline.copyWith(color: semantic.muted),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
```

### `lib/features/analytics/presentation/widgets/analytics_line_chart.dart`

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// A chart sized to the standard plot height, scaled from the text scaler.
///
/// **This replaced `ChartCard.chartHeight`, which was wrong in a way worth recording.** That parameter
/// wrapped the *whole* builder output in a fixed box, so a card whose builder returned chrome above its
/// chart — a title, a legend, a segmented control — had that chrome squeezed into the height meant for
/// the plot, and `Expanded` was then mandatory because only a bounded box makes it legal. Four of the
/// six chart cards were built that way and `InflationCard` overflowed by 44px at scale 1.
///
/// Sizing only the plot is the fix: the surrounding `Column` grows naturally inside the screen's
/// `SliverList`, and the card can be as tall as its own text needs.
///
/// **Measured from the text scaler and clamped** (Law U26). A plot is a graphic and does not grow with
/// type, but its axis labels do, so the box has to give them room; unclamped, a tripled scale produces a
/// card nobody can scroll past.
class AnalyticsPlotBox extends StatelessWidget {
  /// Sizes [child] to the scaled plot height.
  const AnalyticsPlotBox({required this.child, this.height = defaultHeight, super.key});

  /// The plot.
  final Widget child;

  /// The unscaled height.
  final double height;

  /// One height for every chart on the screen, so eight cards cannot each pick their own and leave the
  /// scroll rhythm uneven.
  static const double defaultHeight = AlayaSpacing.xxxl * 2;

  /// The most a plot grows by under text scale.
  static const double maxScale = 2;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, maxScale);
    return SizedBox(height: height * scale, child: child);
  }
}

/// Which semantic role a series carries.
enum AnalyticsSeriesTone {
  /// Money arriving.
  income,

  /// Money leaving.
  expense,

  /// Neither — a balance, a unit price, a count.
  neutral,
}

/// One plotted observation.
class AnalyticsPoint {
  /// Creates a point at [x] worth [value] minor units.
  const AnalyticsPoint({required this.x, required this.value, this.axisLabel});

  /// The horizontal position — a month index, a day offset, a purchase ordinal.
  final double x;

  /// The figure, in **minor units** (Law L1). Never a decimal.
  final int value;

  /// The tick label at [x], already localised. Null on ticks that should stay unlabelled.
  final String? axisLabel;
}

/// One line on the chart.
class AnalyticsSeries {
  /// Creates a series.
  const AnalyticsSeries({required this.points, required this.tone, this.filled = false});

  /// Its observations, ascending by [AnalyticsPoint.x].
  final List<AnalyticsPoint> points;

  /// Which semantic colour it takes.
  final AnalyticsSeriesTone tone;

  /// Whether to shade the area beneath it. One series may; two would obscure each other.
  final bool filled;
}

/// A trend over time, and one of the two surfaces `fl_chart` is used for.
///
/// **`fl_chart` is confined to this file and `analytics_bar_chart.dart`.** Its API could not be
/// verified against the installed package in the session that wrote this — the same position 7A was
/// in with `table_calendar` — so ARCH_4 R22 says to contain it rather than trust a changelog. Every
/// colour, gap and text style comes from Alaya's own tokens through the parameters below; the package
/// supplies path geometry and nothing a token would otherwise own. If its API differs, two files
/// change rather than the phase.
///
/// **There are no Y-axis number labels, and that is Law U7 rather than a style choice.** An axis is
/// exactly where a `Money` gets clipped, `AmountText` clips rather than ellipsises, and a clipped
/// figure is a wrong figure. The grid lines carry the shape; the card's headline carries the number;
/// the drill-down carries the rest.
///
/// **Touch is off.** A tooltip is a timed surface, and ARCH_5 §6 requires that nothing be available
/// *only* there.
class AnalyticsLineChart extends StatelessWidget {
  /// Creates a chart of [series].
  const AnalyticsLineChart({
    required this.series,
    this.gridLineCount = 4,
    super.key,
  });

  /// The lines to draw. Empty renders nothing — the caller's `ChartCard` owns the empty state.
  final List<AnalyticsSeries> series;

  /// How many horizontal grid lines to draw behind the lines.
  final int gridLineCount;

  /// The plotted line's thickness.
  static const double _barWidth = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    if (series.isEmpty) return const SizedBox.shrink();

    final all = [for (final s in series) ...s.points];
    if (all.isEmpty) return const SizedBox.shrink();

    var minValue = all.first.value;
    var maxValue = all.first.value;
    for (final point in all) {
      if (point.value < minValue) minValue = point.value;
      if (point.value > maxValue) maxValue = point.value;
    }
    // A flat line needs a band or the plot collapses to zero height and fl_chart divides by it.
    if (minValue == maxValue) {
      maxValue += 1;
      minValue -= 1;
    }
    // Zero is included whenever the data straddles or approaches it, so a bar of spending is not
    // drawn from an arbitrary floor that exaggerates every difference.
    if (minValue > 0) minValue = 0;

    final labels = <double, String>{
      for (final point in all)
        if (point.axisLabel != null) point.x: point.axisLabel!,
    };

    return LineChart(
      LineChartData(
        minY: minValue.toDouble(),
        maxY: maxValue.toDouble(),
        // Touch disabled: see the class doc. A tooltip would be the only place a figure lived.
        lineTouchData: const LineTouchData(enabled: false),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxValue - minValue) / gridLineCount,
          getDrawingHorizontalLine: (value) => FlLine(
            color: theme.colorScheme.outlineVariant,
            // A literal `1`, and the one dimension in this phase that has no token. ARCH_5 §2.2
            // defines a dividing line as 1px at divider weight and `AlayaSpacing` starts at 4, so
            // there is nothing to reach for — 6F's `range_row.dart` sets the same literal for its
            // rule. `outlineVariant` is Material 3's divider role, which keeps the weight consistent
            // across every palette preset.
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          // No numbers on the left, per Law U7 — see the class doc.
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              // Measured from the text scaler rather than fixed, so a doubled scale gets the room it
              // needs instead of clipping the tick (Law U26).
              reservedSize: MediaQuery.textScalerOf(context).scale(AlayaSpacing.lg),
              getTitlesWidget: (value, meta) {
                final label = labels[value];
                if (label == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: AlayaSpacing.xxs),
                  child: Text(
                    label,
                    style: AlayaTypography.overline.copyWith(color: semantic.muted),
                    maxLines: 1,
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          for (final s in series)
            LineChartBarData(
              // **`toDouble()` here is the one legitimate place a money figure becomes a double.**
              // Law L1 forbids a `double` storing money or crossing a repository boundary; a plot
              // coordinate is neither. The int is what was read, summed and cached.
              spots: [for (final p in s.points) FlSpot(p.x, p.value.toDouble())],
              isCurved: false,
              barWidth: _barWidth,
              color: _colorFor(s.tone, semantic),
              dotData: FlDotData(show: s.points.length <= _dotThreshold),
              belowBarData: BarAreaData(
                show: s.filled,
                color: _colorFor(s.tone, semantic).withValues(alpha: 0.12),
              ),
            ),
        ],
      ),
    );
  }

  /// Above this many points the dots merge into the line and are dropped.
  static const int _dotThreshold = 14;

  Color _colorFor(AnalyticsSeriesTone tone, AlayaSemanticColors semantic) => switch (tone) {
        AnalyticsSeriesTone.income => semantic.income,
        AnalyticsSeriesTone.expense => semantic.expense,
        AnalyticsSeriesTone.neutral => semantic.transfer,
      };
}
```

### `lib/features/analytics/presentation/widgets/analytics_bar_chart.dart`

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// One bucket on an [AnalyticsBarChart].
class AnalyticsBucket {
  /// Creates a bucket.
  const AnalyticsBucket({required this.bucket, required this.value, required this.label});

  /// Its position — 1-7 for a weekday, 1-31 for a day of month (ARCH_3 §5.1 query 21).
  final int bucket;

  /// The figure, in **minor units** (Law L1).
  final int value;

  /// The tick label, already localised.
  final String label;
}

/// A bucketed comparison, and the second of the two surfaces `fl_chart` is used for.
///
/// **The same containment as `AnalyticsLineChart`**: unverified package API confined to one file,
/// every colour and gap from Alaya's tokens, no Y-axis numbers (Law U7), touch off (ARCH_5 §6).
///
/// A bar chart rather than a `SliceBarList` because the buckets are a **fixed ordered set** — seven
/// weekdays, thirty-one days — and their order carries the information. Ranking them largest-first
/// would destroy the only thing the reader is looking for, which is the shape of the week.
class AnalyticsBarChart extends StatelessWidget {
  /// Creates a chart of [buckets], in bucket order.
  const AnalyticsBarChart({required this.buckets, this.labelEvery = 1, super.key});

  /// The buckets, ascending. Empty renders nothing — the caller's `ChartCard` owns the empty state.
  final List<AnalyticsBucket> buckets;

  /// Label every nth bucket. Thirty-one day labels do not fit on a phone; seven weekdays do.
  final int labelEvery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    if (buckets.isEmpty) return const SizedBox.shrink();

    var maxValue = 0;
    for (final bucket in buckets) {
      if (bucket.value > maxValue) maxValue = bucket.value;
    }
    // A window where nothing was spent still draws its axis rather than collapsing, so the reader can
    // see that the buckets exist and are all zero.
    final top = maxValue == 0 ? 1.0 : maxValue.toDouble();

    return BarChart(
      BarChartData(
        maxY: top,
        minY: 0,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: const BarTouchData(enabled: false),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: MediaQuery.textScalerOf(context).scale(AlayaSpacing.lg),
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                final match = buckets.where((b) => b.bucket == index);
                if (match.isEmpty) return const SizedBox.shrink();
                if (labelEvery > 1 && index % labelEvery != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: AlayaSpacing.xxs),
                  child: Text(
                    match.first.label,
                    style: AlayaTypography.overline.copyWith(color: semantic.muted),
                    maxLines: 1,
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (final bucket in buckets)
            BarChartGroupData(
              x: bucket.bucket,
              barRods: [
                BarChartRodData(
                  // The same L1 boundary as the line chart: an int figure becomes a double only to
                  // become a coordinate.
                  toY: bucket.value.toDouble(),
                  color: theme.colorScheme.primary,
                  width: AlayaSpacing.sm,
                  borderRadius: AlayaRadii.borderXs,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
```

### `lib/features/analytics/presentation/widgets/analytics_range_row.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/state/analytics_range.dart';

/// The reporting window, as chips.
///
/// **Every range is labelled with what it means** (anomaly A33). "Last month" is ambiguous between
/// the previous calendar month and the preceding thirty days, and no figure on the screen can
/// disambiguate itself — so the chip states the window and `DateRangeService` resolves exactly that.
///
/// Chips rather than a dropdown: six options, one tap each, and the current choice is visible without
/// opening anything (ARCH_5 §3 archetype A's reasoning, which holds wherever a choice is small and
/// frequent).
class AnalyticsRangeRow extends ConsumerWidget {
  /// Creates the row.
  const AnalyticsRangeRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final selected = ref.watch(analyticsRangeProvider);

    // A `Wrap`, not a horizontal scroller: a scroller needs a fixed height and a fixed height
    // overflows the moment the text scale is raised (Law U15). Six chips wrap to two rows at 2x and
    // stay reachable.
    return Semantics(
      label: strings.analyticsRangeLabel,
      child: Wrap(
        spacing: AlayaSpacing.xs,
        runSpacing: AlayaSpacing.xs,
        children: [
          for (final preset in AnalyticsRange.presets)
            ChoiceChip(
              label: Text(
                AnalyticsLabels.range(strings, preset),
                style: AlayaTypography.button,
              ),
              selected: preset == selected,
              onSelected: (_) => ref.read(analyticsRangeProvider.notifier).show(preset),
            ),
        ],
      ),
    );
  }
}
```

### `lib/features/analytics/presentation/widgets/analytics_header.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Total spend in the window — the one `displayAmount` on this screen (ARCH_5 §3 archetype F).
///
/// **One headline figure, because two headline numbers is no headline number.** Every other figure on
/// the analytics screen is `AmountSize.small` or smaller, exactly as the dashboard's hierarchy works.
///
/// **The comparison is against a window of equal length, not against a calendar month.** "Last 30
/// days" compared with the previous calendar month would be comparing 30 days against 28, 30 or 31,
/// and the resulting percentage would be an artefact of the calendar rather than a fact about
/// spending (`DateRangeService.precedingWindowOf` exists for this).
class AnalyticsHeader extends ConsumerWidget {
  /// Creates the header.
  const AnalyticsHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final async = ref.watch(analyticsHeadlineProvider);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final preset = ref.watch(analyticsRangeProvider);
    final unconverted = ref.watch(analyticsUnconvertedProvider).valueOrNull ?? 0;

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.analyticsTotalSpent,
            style: AlayaTypography.label.copyWith(color: semantic.muted),
          ),
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            AnalyticsLabels.range(strings, preset),
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          const SizedBox(height: AlayaSpacing.xs),
          async.when(
            loading: () => Text(
              strings.chartLoading,
              style: AlayaTypography.body.copyWith(color: semantic.muted),
            ),
            error: (error, stack) => ErrorState(
              title: strings.errorTitleGeneric,
              body: error.toString(),
              retryLabel: strings.actionRetry,
              onRetry: () => ref.invalidate(analyticsHeadlineProvider),
            ),
            data: (concentration) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AmountText(
                  concentration.total,
                  size: AmountSize.display,
                  // The card is headed "Spent", so a minus in front of the figure restates the
                  // heading rather than adding to it.
                  showSign: false,
                  decimalDigits: digits,
                ),
                const _Comparison(),
                if (unconverted > 0 || concentration.quality.unconvertedCount > 0) ...[
                  const SizedBox(height: AlayaSpacing.sm),
                  Wrap(
                    spacing: AlayaSpacing.xs,
                    runSpacing: AlayaSpacing.xxs,
                    children: [
                      if (concentration.quality.unconvertedCount > 0)
                        StatusChip(
                          label: strings.chartUnconverted(
                            concentration.quality.unconvertedCount,
                          ),
                          tone: StatusTone.warning,
                        ),
                      // The app-wide count, distinct from this figure's own exclusions: a
                      // transaction outside the window can still be unconvertible, and Settings is
                      // where a reader fixes that. Said once here rather than on every card.
                      if (unconverted > 0)
                        StatusChip(
                          label: strings.analyticsUnconvertedTotal(unconverted),
                          tone: StatusTone.neutral,
                        ),
                    ],
                  ),
                  const SizedBox(height: AlayaSpacing.xs),
                  Text(
                    strings.fundsWhyExcluded,
                    style: AlayaTypography.caption.copyWith(color: semantic.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How this window compares with the one before it, of the same length.
class _Comparison extends ConsumerWidget {
  const _Comparison();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final now = ref.watch(analyticsHeadlineProvider).valueOrNull;
    final before = ref.watch(analyticsPreviousHeadlineProvider).valueOrNull;

    // Renders nothing until both windows have resolved, and nothing when the earlier one held zero.
    // A percentage against zero is infinite, and "up ∞%" is not a fact about spending.
    if (now == null || before == null || before.total.minor == 0) return const SizedBox.shrink();

    final delta = (now.total.minor - before.total.minor) / before.total.minor;
    final formatted = AnalyticsLabels.percent(context, delta.abs());

    // **Colour is not the only signal** (Law U17): the word carries the direction and the hue only
    // reinforces it. Spending more is `warning` rather than `danger` — it is worth noticing, not
    // wrong.
    final rose = delta > 0;
    return Padding(
      padding: const EdgeInsets.only(top: AlayaSpacing.xs),
      child: Text(
        rose
            ? strings.analyticsComparisonUp(formatted)
            : strings.analyticsComparisonDown(formatted),
        style: AlayaTypography.caption.copyWith(
          color: rose ? semantic.warning : semantic.success,
        ),
      ),
    );
  }
}
```

### `lib/features/analytics/presentation/widgets/inflation_card.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_line_chart.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';
import 'package:alaya/shared/widgets/date_text.dart';

/// The personal-inflation card — queries 12 and 24.
///
/// **This is the differentiating surface** (ARCH_3 §5.1: *"your potatoes cost 34% more than in
/// January"*). It is the one figure on this screen that no mainstream expense app can produce, and it
/// falls out of `transaction_lines` for free: a line records what was bought, how much of it, and for
/// how much, so price per base unit is a division rather than a feature.
///
/// **Comparable across purchases because it is per *base* unit.** 2 kg and 500 g are the same
/// measurement once both are per gram, which is why the trend can put a sack and a handful on one
/// line.
///
/// The item is chosen rather than asked for: `personalInflationProvider` takes the largest absolute
/// change among the items the reader actually spends on.
class InflationCard extends ConsumerWidget {
  /// Creates the card.
  const InflationCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(personalInflationProvider);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;

    return ChartCard<UnitPriceTrend?>(
      title: strings.analyticsInflationTitle,
      subtitle: strings.analyticsInflationSubtitle,
      value: async,
      // Null *and* a trend with fewer than two points both read as empty: one observation is a price,
      // not a trend, and drawing a single dot and calling it inflation would be a claim the data does
      // not support.
      isEmpty: (trend) => trend == null || trend.points.length < 2,
      emptyMessage: strings.analyticsInflationEmpty,
      onRetry: () => ref.invalidate(personalInflationProvider),
      builder: (context, trend) => _Trend(trend: trend!, decimalDigits: digits),
    );
  }
}

class _Trend extends StatelessWidget {
  const _Trend({required this.trend, required this.decimalDigits});

  final UnitPriceTrend trend;
  final int decimalDigits;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final theme = Theme.of(context);
    final change = trend.percentChange;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          trend.itemName,
          style: AlayaTypography.cardTitle.copyWith(color: theme.colorScheme.onSurface),
        ),
        if (change != null) ...[
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            _sentence(context, strings, change),
            style: AlayaTypography.bodyEmphasis.copyWith(
              // Paying more for the same thing is `warning`: worth noticing, not wrong. Colour is
              // never the only signal — the sentence says "more" or "less" (Law U17).
              color: change > 0 ? semantic.warning : semantic.success,
            ),
          ),
        ],
        const SizedBox(height: AlayaSpacing.xxs),
        // **The date goes through `DateText`, so the sentence above cannot contain it** (Law U7).
        // Interpolating a formatted date into an ARB string would bypass the one path from a `DateKey`
        // to pixels, and a `Wrap` lets the label and the date reflow rather than starving each other
        // at a raised text scale (Law U21).
        Wrap(
          spacing: AlayaSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              strings.analyticsInflationSince,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            DateText(trend.points.first.on, style: DateTextStyle.medium, muted: true),
            AmountText(
              trend.points.last.lineAmount,
              size: AmountSize.small,
              showSign: false,
              decimalDigits: decimalDigits,
            ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.sm),
        AnalyticsPlotBox(
          child: AnalyticsLineChart(
            series: [
              AnalyticsSeries(
                tone: AnalyticsSeriesTone.neutral,
                filled: true,
                points: _points(context, trend),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The observations, oldest first, as plot points.
  ///
  /// `x` is the purchase *ordinal* rather than the date, deliberately. Spacing the points by date
  /// would compress a cluster of weekly shops into an unreadable smear and stretch a six-month gap
  /// across the card; the question is "how has the price moved across my purchases", and each
  /// purchase is one step.
  ///
  /// `pricePerBaseUnit` is a `double` of minor units — a derived ratio, which is why
  /// `analytics_types.dart` refuses to make it a `Money`. It is rounded to whole minor units here
  /// because a pixel cannot express a fraction of a paisa, and only the first and last ticks are
  /// labelled so the axis stays legible at any purchase count.
  List<AnalyticsPoint> _points(BuildContext context, UnitPriceTrend trend) {
    final last = trend.points.length - 1;
    return [
      for (var i = 0; i <= last; i++)
        AnalyticsPoint(
          x: i.toDouble(),
          value: trend.points[i].pricePerBaseUnit.round(),
          axisLabel: i == 0 || i == last
              ? DateFormat.MMMd(Localizations.localeOf(context).toLanguageTag())
                  .format(trend.points[i].on.toUtcMidnight())
              : null,
        ),
    ];
  }

  String _sentence(BuildContext context, AlayaStrings strings, double change) {
    final formatted = AnalyticsLabels.percent(context, change.abs());
    return change > 0
        ? strings.analyticsInflationUp(formatted)
        : strings.analyticsInflationDown(formatted);
  }
}
```

### `lib/features/analytics/presentation/widgets/spend_cards.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_amount.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_donut_chart.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/presentation/widgets/slice_bar_list.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';

/// Query 1 — spend by subtype, tapping through to the ledger.
class SubtypeSpendCard extends ConsumerWidget {
  /// Creates the card.
  const SubtypeSpendCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;

    return ChartCard<MoneySeries>(
      title: strings.analyticsBySubtype,
      value: ref.watch(spendBySubtypeProvider),
      isEmpty: (series) => series.slices.isEmpty,
      emptyMessage: strings.analyticsNothingSpent,
      onRetry: () => ref.invalidate(spendBySubtypeProvider),
      approximateCount: ref.watch(spendBySubtypeProvider).valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: ref.watch(spendBySubtypeProvider).valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, series) {
        // **A partition, so a ring is honest here.** Subtypes are mutually exclusive — every withdrawal
        // has exactly one — so the wedges really do add up to the total in the header. The same
        // `analyticsSlices` call feeds the ring and the rows, so the fifth wedge and the fifth row
        // cannot end up different colours.
        final slices = analyticsSlices(
          context,
          [
            for (final slice in series.slices)
              (
                // `slice.key`, never `slice.label`: SQL grouped by the enum name, so the label is
                // `grocery` and rendering it would put an identifier on screen (Law U5).
                label: AnalyticsLabels.subtype(strings, slice.key),
                value: slice.amount.minor,
                key: slice.key,
              ),
          ],
          otherLabel: strings.analyticsOtherSlices,
        );
        final byKey = {for (final slice in series.slices) slice.key: slice.amount};
        final leader = slices.isEmpty ? null : slices.first;
        final total = slices.fold<int>(0, (sum, slice) => sum + slice.value);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnalyticsDonutChart(
              slices: slices,
              centreTop: leader == null || total == 0
                  ? null
                  : AnalyticsLabels.percent(context, leader.value / total),
              centreBottom: leader?.label,
            ),
            const SizedBox(height: AlayaSpacing.sm),
            SliceBarList(
              // The ring carries the proportion, so the rows drop their bars and keep the swatch.
              showBars: false,
              slices: [
                for (final slice in slices)
                  SliceBar(
                    label: slice.label,
                    // The grouped remainder has no single amount of its own, so it is rebuilt from the
                    // magnitudes that went into it, in the home currency they were converted to.
                    value: analyticsAmount(
                      byKey[slice.key] ?? Money(slice.value, series.slices.first.amount.currencyCode),
                      digits,
                    ),
                    share: total == 0 ? 0 : slice.value / total,
                    // **The share as a figure, not only as an arc.** Dropping the bar cost each row its
                    // sense of relative size, so the percentage replaces it — and a number is what a
                    // reader can act on, which a bar length never was.
                    detail: total == 0
                        ? null
                        : AnalyticsLabels.percent(context, slice.value / total),
                    swatch: slice.color,
                    onTap: slice.key == null
                        ? null
                        : () => context.push(
                              Routes.insightsDrillDown(
                                DrillDownKind.subtype.name,
                                slice.key!,
                              ),
                            ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Query 2 — spend by tag, with the one level of nesting the schema allows.
///
/// **This closes `tags.parentTagId`'s analytics half** (ARCH_5 §7.2). The drill is in place rather
/// than a route: a parent tag's children are a *view of the same figure*, so pushing a screen for
/// them would lose the total they roll up to.
class TagSpendCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const TagSpendCard({super.key});

  @override
  ConsumerState<TagSpendCard> createState() => _TagSpendCardState();
}

class _TagSpendCardState extends ConsumerState<TagSpendCard> {
  String? _openParentId;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final async = ref.watch(tagSpendTreeProvider);
    final quality = ref.watch(spendByTagProvider).valueOrNull?.quality;

    return ChartCard<List<TagSpendNode>>(
      title: strings.analyticsByTag,
      // The caveat belongs on the card rather than in a footnote: a transaction with two tags is in
      // both slices, so these do not add up to the headline and a reader comparing them deserves to
      // know why.
      subtitle: strings.analyticsByTagNote,
      value: async,
      isEmpty: (nodes) => nodes.isEmpty,
      emptyMessage: strings.analyticsNoTaggedSpend,
      onRetry: () => ref.invalidate(tagSpendTreeProvider),
      // `tagSpendTreeProvider` rolls slices into a tree and drops the series' quality on the way, so the
      // counts come from the series itself. No second query: `tagSpendTreeProvider` already watches it,
      // so Riverpod hands over the cached result.
      approximateCount: quality?.approximateCount ?? 0,
      unconvertedCount: quality?.unconvertedCount ?? 0,
      builder: (context, nodes) {
        // A plain loop rather than `firstOrNull`: that extension lives in `package:collection`,
        // which this project does not declare — importing a transitive dependency directly is what
        // `depend_on_referenced_packages` exists to catch (ARCH_1 §7.4's rule 2, from the other end).
        TagSpendNode? open;
        if (_openParentId != null) {
          for (final node in nodes) {
            if (node.tag.id == _openParentId) {
              open = node;
              break;
            }
          }
        }
        if (open == null) {
          final peak = analyticsPeak(nodes.map((n) => n.rolledUp));
          return SliceBarList(
            slices: [
              for (final node in nodes)
                SliceBar(
                  label: node.tag.name,
                  value: analyticsAmount(node.rolledUp, digits),
                  share: analyticsShare(node.rolledUp, peak),
                  detail: node.canDrill
                      ? strings.analyticsTagChildren(node.children.length)
                      : null,
                  // A leaf has nothing to open, so it gets no tap at all rather than a tap that does
                  // nothing — ARCH_5 §10's objection to a control that looks live and is not.
                  onTap: node.canDrill
                      ? () => setState(() => _openParentId = node.tag.id)
                      : null,
                ),
            ],
          );
        }

        final children = open.children;
        final peak = analyticsPeak([open.own, ...children.map((c) => c.rolledUp)]);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DrillHeader(
              label: open.tag.name,
              total: open.rolledUp,
              decimalDigits: digits,
              onBack: () => setState(() => _openParentId = null),
            ),
            const SizedBox(height: AlayaSpacing.xs),
            SliceBarList(
              slices: [
                // The parent's own spend is a sibling of its children, not their sum: "Grocery
                // directly" and "Grocery > Vegetables" are different rows, and folding the first into
                // the second would misattribute it.
                if (open.own.minor > 0)
                  SliceBar(
                    label: strings.analyticsTagDirect(open.tag.name),
                    value: analyticsAmount(open.own, digits),
                    share: analyticsShare(open.own, peak),
                  ),
                for (final child in children)
                  SliceBar(
                    label: child.tag.name,
                    value: analyticsAmount(child.rolledUp, digits),
                    share: analyticsShare(child.rolledUp, peak),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The in-place drill's header: where you are, what it totals, and the way back.
class _DrillHeader extends StatelessWidget {
  const _DrillHeader({
    required this.label,
    required this.total,
    required this.decimalDigits,
    required this.onBack,
  });

  final String label;
  final Money total;
  final int decimalDigits;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    return Row(
      children: [
        // A labelled icon button, because "back" is one of the six glyphs ARCH_5 §2.7 lets stand
        // alone — but it still carries a tooltip so a screen reader names it.
        IconButton(
          onPressed: onBack,
          tooltip: strings.analyticsTagBack,
          icon: const Icon(Icons.arrow_back, size: AlayaIconSize.md),
        ),
        Expanded(
          child: Text(
            label,
            style: AlayaTypography.bodyEmphasis.copyWith(color: semantic.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        AmountText(
          total,
          size: AmountSize.small,
          showSign: false,
          decimalDigits: decimalDigits,
        ),
      ],
    );
  }
}

/// Query 3 — spend by payment method.
class PaymentMethodSpendCard extends ConsumerWidget {
  /// Creates the card.
  const PaymentMethodSpendCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final async = ref.watch(spendByPaymentMethodProvider);

    return ChartCard<MoneySeries>(
      title: strings.analyticsByMethod,
      value: async,
      isEmpty: (series) => series.slices.isEmpty,
      emptyMessage: strings.analyticsNoMethodSpend,
      onRetry: () => ref.invalidate(spendByPaymentMethodProvider),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, series) {
        final peak = analyticsPeak(series.slices.map((s) => s.amount));
        return SliceBarList(
          slices: [
            for (final slice in series.slices)
              SliceBar(
                // A payment method's name **is** data, so it renders directly.
                label: slice.label,
                value: analyticsAmount(slice.amount, digits),
                share: analyticsShare(slice.amount, peak),
                onTap: () => context.push(
                  Routes.insightsDrillDown(DrillDownKind.paymentMethod.name, slice.key),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Queries 8 and 22 — how concentrated spending is, and groceries' share of it.
///
/// One card for both, because they answer the same question at two grains: "is my spending spread or
/// clustered", then "and is the cluster food". Two cards would put the same total on screen twice.
class ConcentrationCard extends ConsumerWidget {
  /// Creates the card.
  const ConcentrationCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final async = ref.watch(analyticsHeadlineProvider);
    final grocery = ref.watch(groceryShareProvider).valueOrNull;

    return ChartCard<Concentration>(
      title: strings.analyticsConcentration,
      value: async,
      isEmpty: (c) => c.top.isEmpty,
      emptyMessage: strings.analyticsNothingSpent,
      onRetry: () => ref.invalidate(analyticsHeadlineProvider),
      // `Concentration` carries a quality and this card read neither count. A concentration figure that
      // silently excluded an unconvertible amount would report a household as more concentrated than it
      // is, because the excluded slice is missing from the denominator too (anomaly A15).
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, concentration) {
        // **The remainder is supplied rather than derived.** This card knows the whole — the header's
        // total — and shows only the top three, so what the ring needs is the difference. Deriving it
        // from the three slices would draw a ring of three wedges that filled the circle and asserted
        // that three kinds were all of the spending.
        final top = concentration.top.fold<int>(0, (sum, s) => sum + s.amount.minor);
        final slices = analyticsSlices(
          context,
          [
            for (final slice in concentration.top)
              (
                label: AnalyticsLabels.subtype(strings, slice.key),
                value: slice.amount.minor,
                key: slice.key,
              ),
          ],
          otherLabel: strings.analyticsOtherSlices,
          remainder: concentration.total.minor - top,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnalyticsDonutChart(
              slices: slices,
              centreTop: _percent(context, concentration.topShare),
              centreBottom: strings.analyticsTopThree,
            ),
            const SizedBox(height: AlayaSpacing.sm),
            Text(
              strings.analyticsTopShare(_percent(context, concentration.topShare)),
              style: AlayaTypography.bodyEmphasis,
            ),
            const SizedBox(height: AlayaSpacing.sm),
            SliceBarList(
              showBars: false,
              slices: [
                for (var i = 0; i < concentration.top.length; i++)
                  SliceBar(
                    label: AnalyticsLabels.subtype(strings, concentration.top[i].key),
                    value: analyticsAmount(concentration.top[i].amount, digits),
                    share: concentration.top[i].share,
                    detail: _percent(context, concentration.top[i].share),
                    swatch: i < slices.length ? slices[i].color : null,
                  ),
              ],
            ),
            if (grocery != null) ...[
              const SizedBox(height: AlayaSpacing.sm),
              Text(
                strings.analyticsGroceryShare(_percent(context, grocery.share)),
                style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
              ),
            ],
          ],
        );
      },
    );
  }

  String _percent(BuildContext context, double share) =>
      AnalyticsLabels.percent(context, share);
}
```

### `lib/features/analytics/presentation/widgets/time_cards.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_bar_chart.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_line_chart.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';

/// A `yyyymm` month key as a short localised month name.
///
/// `DateKey.fromYmd(y, m, 1)` rather than arithmetic on the key: `fromYmd` **validates**, so a
/// malformed month key throws here rather than rendering a nonsense label (ARCH_2's 7A amendment).
String _monthLabel(BuildContext context, int monthKey) {
  final date = DateKey.fromYmd(monthKey ~/ 100, monthKey % 100, 1);
  return DateFormat.MMM(Localizations.localeOf(context).toLanguageTag())
      .format(date.toUtcMidnight());
}

/// Only the first and last tick are labelled, and every tick when there are few enough.
///
/// Twelve month labels do not fit across a phone; two do, and the shape between them is what the card
/// is for.
bool _labelTick(int index, int last) => index == 0 || index == last || last <= _denseTickLimit;

const int _denseTickLimit = 4;

/// Query 5 — income against expense, month by month.
class IncomeVsExpenseCard extends ConsumerWidget {
  /// Creates the card.
  const IncomeVsExpenseCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(incomeVsExpenseProvider);

    return ChartCard<IncomeVsExpense>(
      title: strings.analyticsIncomeVsExpense,
      value: async,
      isEmpty: (data) => data.points.length < 2,
      // Fewer than two months is not a trend, and a single pair of dots presented as one would invite
      // a comparison the data cannot support.
      emptyMessage: strings.analyticsNeedTwoMonths,
      onRetry: () => ref.invalidate(incomeVsExpenseProvider),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, data) {
        final last = data.points.length - 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Legend(
              entries: [
                (label: strings.rangeMoneyIn, tone: AnalyticsSeriesTone.income),
                (label: strings.rangeMoneyOut, tone: AnalyticsSeriesTone.expense),
              ],
            ),
            const SizedBox(height: AlayaSpacing.xs),
            AnalyticsPlotBox(
              child: AnalyticsLineChart(
                series: [
                  AnalyticsSeries(
                    tone: AnalyticsSeriesTone.income,
                    points: [
                      for (var i = 0; i <= last; i++)
                        AnalyticsPoint(
                          x: i.toDouble(),
                          value: data.points[i].income.minor,
                          axisLabel: _labelTick(i, last)
                              ? _monthLabel(context, data.points[i].monthKey)
                              : null,
                        ),
                    ],
                  ),
                  AnalyticsSeries(
                    tone: AnalyticsSeriesTone.expense,
                    points: [
                      for (var i = 0; i <= last; i++)
                        AnalyticsPoint(
                          x: i.toDouble(),
                          value: data.points[i].expense.minor,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Query 6 — net cash flow per month, from the signed ledger.
class NetCashFlowCard extends ConsumerWidget {
  /// Creates the card.
  const NetCashFlowCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(netCashFlowProvider);

    return ChartCard<NetCashFlow>(
      title: strings.analyticsNetFlow,
      // Worth stating: a reader who moves money between their own accounts every month would
      // otherwise wonder why it is absent. `v_account_ledger` nets a transfer to zero across its two
      // legs, so it never reaches this line.
      subtitle: strings.analyticsNetFlowNote,
      value: async,
      isEmpty: (data) => data.points.isEmpty,
      emptyMessage: strings.analyticsNoFlow,
      onRetry: () => ref.invalidate(netCashFlowProvider),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, data) {
        final last = data.points.length - 1;
        return AnalyticsPlotBox(
          child: AnalyticsLineChart(
            series: [
              AnalyticsSeries(
                // Neutral, not income or expense: a net figure crosses zero, and colouring the whole
                // line by one direction would assert something half of it contradicts. The chart
                // includes zero in its band so the crossing is visible.
                tone: AnalyticsSeriesTone.neutral,
                filled: true,
                points: [
                  for (var i = 0; i <= last; i++)
                    AnalyticsPoint(
                      x: i.toDouble(),
                      value: data.points[i].amount.minor,
                      axisLabel: _labelTick(i, last)
                          ? _monthLabel(context, data.points[i].monthKey)
                          : null,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Query 7 — one account's running balance, in that account's own currency.
class BalanceTrendCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const BalanceTrendCard({super.key});

  @override
  ConsumerState<BalanceTrendCard> createState() => _BalanceTrendCardState();
}

class _BalanceTrendCardState extends ConsumerState<BalanceTrendCard> {
  String? _accountId;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final accounts = ref.watch(analyticsAccountsProvider).valueOrNull ?? const <Account>[];
    if (accounts.isEmpty) return const SizedBox.shrink();

    // **The account is resolved, not asked for** (Law U23). A household with one account is never
    // shown a picker; the first selectable account is the answer, and the picker appears only when
    // there is a genuine choice.
    final selected = _resolve(accounts);
    final async = ref.watch(balanceTrendProvider(selected.id));
    final digits =
        ref.watch(analyticsDigitsForCurrencyProvider(selected.currencyCode)).valueOrNull ?? 2;

    return ChartCard<BalanceTrend>(
      title: strings.analyticsBalanceTrend,
      // The currency is named because this is the one card not in the home currency, and an
      // unlabelled figure in a second currency is a wrong figure.
      subtitle: strings.analyticsBalanceIn(selected.name, selected.currencyCode),
      value: async,
      isEmpty: (trend) => trend.points.length < 2,
      emptyMessage: strings.analyticsNoBalanceMovement,
      onRetry: () => ref.invalidate(balanceTrendProvider(selected.id)),
      trailing: async.valueOrNull != null && async.valueOrNull!.points.isNotEmpty
          ? AmountText(
              async.valueOrNull!.points.last.balance,
              size: AmountSize.small,
              showSign: false,
              decimalDigits: digits,
            )
          : null,
      builder: (context, trend) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (accounts.length > 1)
            _AccountPicker(
              accounts: accounts,
              selectedId: selected.id,
              onChanged: (id) => setState(() => _accountId = id),
            ),
          AnalyticsPlotBox(
            child: AnalyticsLineChart(
              series: [
                AnalyticsSeries(
                  tone: AnalyticsSeriesTone.neutral,
                  points: [
                    for (var i = 0; i < trend.points.length; i++)
                      AnalyticsPoint(
                        x: i.toDouble(),
                        value: trend.points[i].balance.minor,
                        axisLabel: _labelTick(i, trend.points.length - 1)
                            ? DateFormat.MMMd(Localizations.localeOf(context).toLanguageTag())
                                .format(trend.points[i].date.toUtcMidnight())
                            : null,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Account _resolve(List<Account> accounts) {
    final id = _accountId;
    if (id != null) {
      for (final account in accounts) {
        if (account.id == id) return account;
      }
    }
    return accounts.first;
  }
}

/// Which account the balance trend is showing.
class _AccountPicker extends StatelessWidget {
  const _AccountPicker({
    required this.accounts,
    required this.selectedId,
    required this.onChanged,
  });

  final List<Account> accounts;
  final String selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
      child: DropdownButtonFormField<String>(
        // **`isExpanded` is not optional** (ARCH_5 §10): without it the field lays out at the widest
        // item's natural width and overflows a narrow card.
        isExpanded: true,
        initialValue: selectedId,
        decoration: InputDecoration(labelText: strings.analyticsAccount),
        items: [
          for (final account in accounts)
            DropdownMenuItem(value: account.id, child: Text(account.name)),
        ],
        onChanged: (id) {
          if (id != null) onChanged(id);
        },
      ),
    );
  }
}

/// Query 21 — the spend heatmap, by weekday or by day of month.
class SpendHeatmapCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const SpendHeatmapCard({super.key});

  @override
  ConsumerState<SpendHeatmapCard> createState() => _SpendHeatmapCardState();
}

class _SpendHeatmapCardState extends ConsumerState<SpendHeatmapCard> {
  bool _byWeekday = true;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(spendHeatmapProvider(_byWeekday));

    return ChartCard<SpendHeatmap>(
      title: strings.analyticsHeatmap,
      value: async,
      isEmpty: (data) => data.cells.isEmpty,
      emptyMessage: strings.analyticsNothingSpent,
      onRetry: () => ref.invalidate(spendHeatmapProvider(_byWeekday)),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, data) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(strings.analyticsByWeekday)),
              ButtonSegment(value: false, label: Text(strings.analyticsByDayOfMonth)),
            ],
            selected: {_byWeekday},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => _byWeekday = selection.first),
          ),
          const SizedBox(height: AlayaSpacing.sm),
          AnalyticsPlotBox(
            child: AnalyticsBarChart(
              // Thirty-one labels do not fit across a phone; seven do. Every fifth day is enough to
              // orient the reader without the axis becoming a smear.
              labelEvery: _byWeekday ? 1 : _dayOfMonthLabelEvery,
              buckets: [
                for (final cell in data.cells)
                  AnalyticsBucket(
                    bucket: cell.bucket,
                    value: cell.amount.minor,
                    label: AnalyticsLabels.bucket(
                      context,
                      cell.bucket,
                      byWeekday: _byWeekday,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const int _dayOfMonthLabelEvery = 5;
}

/// A key for a multi-series chart, since colour alone cannot say which line is which (Law U17).
class _Legend extends StatelessWidget {
  const _Legend({required this.entries});

  final List<({String label, AnalyticsSeriesTone tone})> entries;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Wrap(
      spacing: AlayaSpacing.sm,
      runSpacing: AlayaSpacing.xxs,
      children: [
        for (final entry in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Swatch(tone: entry.tone),
              const SizedBox(width: AlayaSpacing.xxs),
              Text(
                entry.label,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
            ],
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.tone});

  final AnalyticsSeriesTone tone;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final color = switch (tone) {
      AnalyticsSeriesTone.income => semantic.income,
      AnalyticsSeriesTone.expense => semantic.expense,
      AnalyticsSeriesTone.neutral => semantic.transfer,
    };
    return SizedBox(
      width: AlayaSpacing.sm,
      height: AlayaSpacing.xxs,
      child: ColoredBox(color: color),
    );
  }
}
```

### `lib/features/analytics/presentation/widgets/items_cards.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_formatter.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_amount.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/presentation/widgets/slice_bar_list.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/qty_text.dart';

/// Query 4 — the top payees by spend.
class TopPayeesCard extends ConsumerWidget {
  /// Creates the card.
  const TopPayeesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final async = ref.watch(topPayeesProvider);

    return ChartCard<MoneySeries>(
      title: strings.analyticsTopPayees,
      value: async,
      isEmpty: (series) => series.slices.isEmpty,
      emptyMessage: strings.analyticsNoPayees,
      onRetry: () => ref.invalidate(topPayeesProvider),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, series) {
        final peak = analyticsPeak(series.slices.map((s) => s.amount));
        return SliceBarList(
          slices: [
            for (final slice in series.slices)
              SliceBar(
                label: slice.label,
                value: analyticsAmount(slice.amount, digits),
                share: analyticsShare(slice.amount, peak),
                onTap: () => context.push(
                  Routes.insightsDrillDown(DrillDownKind.payee.name, slice.key),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Query 9 — the top items by spend.
class TopItemsBySpendCard extends ConsumerWidget {
  /// Creates the card.
  const TopItemsBySpendCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final async = ref.watch(topItemsBySpendProvider);

    return ChartCard<List<ItemSpend>>(
      title: strings.analyticsTopItems,
      value: async,
      isEmpty: (items) => items.isEmpty,
      emptyMessage: strings.analyticsNoItemisedSpend,
      onRetry: () => ref.invalidate(topItemsBySpendProvider),
      builder: (context, items) {
        final peak = analyticsPeak(items.map((i) => i.amount));
        return SliceBarList(
          slices: [
            for (final item in items)
              SliceBar(
                label: item.itemName,
                value: analyticsAmount(item.amount, digits),
                share: analyticsShare(item.amount, peak),
                detail: strings.analyticsPurchaseCount(item.purchaseCount),
                onTap: () => context.push(
                  Routes.insightsDrillDown(DrillDownKind.item.name, item.itemId),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Query 10 — the top items by quantity bought, grouped by measure.
///
/// **Grouped rather than ranked, because Law L8 makes the categories incomparable.** There is no
/// gram-to-piece conversion anywhere in this app, so a single ordering would put 4 kg of potatoes above
/// 30 eggs and mean nothing at all. Each measure gets its own bars, each measured against its own peak.
class TopItemsByQuantityCard extends ConsumerWidget {
  /// Creates the card.
  const TopItemsByQuantityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(topItemsByQuantityProvider);

    return ChartCard<List<ItemQuantity>>(
      title: strings.analyticsTopByQuantity,
      subtitle: strings.analyticsTopByQuantityNote,
      value: async,
      isEmpty: (items) => items.isEmpty,
      emptyMessage: strings.analyticsNoQuantities,
      onRetry: () => ref.invalidate(topItemsByQuantityProvider),
      builder: (context, items) {
        final byCategory = <UnitCategory, List<ItemQuantity>>{};
        for (final item in items) {
          byCategory.putIfAbsent(item.quantity.category, () => <ItemQuantity>[]).add(item);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in byCategory.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: AlayaSpacing.xs),
                child: Text(
                  AnalyticsLabels.unitCategory(strings, entry.key),
                  style: AlayaTypography.sectionHeader.copyWith(
                    color: context.semantic.muted,
                  ),
                ),
              ),
              SliceBarList(
                maxRows: _rowsPerCategory,
                slices: [
                  for (final item in entry.value)
                    SliceBar(
                      label: item.itemName,
                      // A `Qty` through `QtyText` and never `toString()` (Law U7). `mixed` is the
                      // default style — "4 kg 450 g" — which is what an item row wants; `compact` is
                      // for a chart axis.
                      value: QtyText(item.quantity, style: UnitStyle.mixed),
                      share: _quantityShare(item.quantity, entry.value),
                      detail: strings.analyticsPurchaseCount(item.purchaseCount),
                      onTap: () => context.push(
                        Routes.insightsDrillDown(DrillDownKind.item.name, item.itemId),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  /// Four per measure: three measures at six rows each would make this the longest card on the screen.
  static const int _rowsPerCategory = 4;

  double _quantityShare(Qty quantity, List<ItemQuantity> withinCategory) {
    var peak = 0;
    for (final item in withinCategory) {
      if (item.quantity.milliBase > peak) peak = item.quantity.milliBase;
    }
    return peak == 0 ? 0 : quantity.milliBase / peak;
  }
}

/// Query 11 — the dearest single purchase of the item spent most on.
///
/// **The figure is in the currency it was bought in, unconverted.** "The most I ever paid" is a fact
/// about that purchase, and restating it at today's rate would silently change a historical number.
class DearestPurchaseCard extends ConsumerWidget {
  /// Creates the card.
  const DearestPurchaseCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final top = ref.watch(topItemsBySpendProvider).valueOrNull;
    if (top == null || top.isEmpty) return const SizedBox.shrink();

    final item = top.first;
    final ref0 = (id: item.itemId, name: item.itemName);
    final async = ref.watch(dearestPurchaseProvider(ref0));
    final digits = ref
            .watch(analyticsDigitsForCurrencyProvider(item.amount.currencyCode))
            .valueOrNull ??
        2;

    return ChartCard<DearestPurchase?>(
      title: strings.analyticsDearest,
      value: async,
      isEmpty: (purchase) => purchase == null,
      emptyMessage: strings.analyticsNoUnitPrices,
      onRetry: () => ref.invalidate(dearestPurchaseProvider(ref0)),
      builder: (context, purchase) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyValueRow(
            label: strings.analyticsDearestItem,
            value: purchase!.itemName,
          ),
          KeyValueRow(
            label: strings.analyticsDearestPrice,
            valueWidget: AmountText(
              purchase.unitPrice,
              size: AmountSize.small,
              showSign: false,
              decimalDigits: digits,
            ),
          ),
          KeyValueRow(
            label: strings.analyticsDearestWhen,
            valueWidget: DateText(purchase.on, style: DateTextStyle.medium),
          ),
        ],
      ),
    );
  }
}

/// Query 23 — the average grocery basket.
class AverageBasketCard extends ConsumerWidget {
  /// Creates the card.
  const AverageBasketCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final async = ref.watch(averageBasketProvider);

    return ChartCard<BasketStats>(
      title: strings.analyticsAverageBasket,
      value: async,
      isEmpty: (stats) => stats.basketCount == 0,
      emptyMessage: strings.analyticsNoBaskets,
      onRetry: () => ref.invalidate(averageBasketProvider),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, stats) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyValueRow(
            label: strings.analyticsBasketValue,
            valueWidget: AmountText(
              stats.averageValue,
              size: AmountSize.small,
              showSign: false,
              decimalDigits: digits,
            ),
          ),
          KeyValueRow(
            label: strings.analyticsBasketLines,
            // One decimal: "4.3 items" is the answer, and rounding it to 4 would lose the only thing
            // an average adds over a count.
            value: stats.averageLineCount.toStringAsFixed(1),
          ),
          KeyValueRow(
            label: strings.analyticsBasketCount,
            // **Baskets that CONVERTED, not all of them.** `AnalyticsService` divides by the ones it
            // could convert, so reporting the full count beside that average would describe a
            // different calculation.
            value: '${stats.basketCount}',
          ),
        ],
      ),
    );
  }
}
```

### `lib/features/analytics/presentation/widgets/analytics_amount.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';

/// The largest amount in a breakdown, which every bar's length is measured against.
///
/// Share of the *largest* rather than of the total, because a breakdown whose bars are shares of a
/// total is nearly all whitespace the moment there are eight slices — and the figures beside them
/// already say what the totals are.
int analyticsPeak(Iterable<Money> amounts) {
  var peak = 0;
  for (final amount in amounts) {
    if (amount.minor > peak) peak = amount.minor;
  }
  return peak;
}

/// [amount] as a fraction of [peak], for a bar's length.
double analyticsShare(Money amount, int peak) => peak == 0 ? 0 : amount.minor / peak;

/// A breakdown row's figure, rendered once for every card that has one.
///
/// `AmountSize.small` because this screen has exactly one headline (ARCH_5 §3 archetype F), and
/// `showSign: false` because a column that is already a breakdown of spending does not need a minus in
/// front of every row.
Widget analyticsAmount(Money amount, int decimalDigits) => AmountText(
      amount,
      size: AmountSize.small,
      showSign: false,
      decimalDigits: decimalDigits,
    );

/// An amount that resolves its **own** currency's precision.
///
/// **For the figures on this screen that are not in the home currency**: an inventory valuation, a
/// waste cost and a service history are all per-currency, because a batch's cost currency is per row
/// and summing them would add rupees to yen (anomaly A34). Passing the home currency's precision to a
/// yen figure prints `¥1,200.00` for `¥1,200`.
///
/// A widget rather than a lookup at the call site, because the precision arrives asynchronously and a
/// card rendering four currencies would otherwise need four watches interleaved with its layout.
class AnalyticsCurrencyAmount extends ConsumerWidget {
  /// Renders [amount] with its own currency's precision.
  const AnalyticsCurrencyAmount(this.amount, {this.size = AmountSize.small, super.key});

  /// The amount, in whatever currency it was recorded in.
  final Money amount;

  /// How large to render it.
  final AmountSize size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Two while the precision loads is the right guess for four of the app's five seeded currencies,
    // and it is corrected on the next frame rather than showing a placeholder where a figure goes.
    final digits =
        ref.watch(analyticsDigitsForCurrencyProvider(amount.currencyCode)).valueOrNull ?? 2;
    return AmountText(amount, size: size, showSign: false, decimalDigits: digits);
  }
}
```

### `lib/features/analytics/presentation/widgets/home_cards.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty_formatter.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_amount.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Query 13 — what the stock on hand is worth, per currency.
///
/// **Per currency and never one figure** (anomaly A34): a batch's cost currency is its own column, so a
/// single total would be adding rupees to yen. Uncosted stock is counted and said out loud rather than
/// omitted, because a valuation that quietly skipped it would look complete while understating the
/// shelf.
class InventoryValueCard extends ConsumerWidget {
  /// Creates the card.
  const InventoryValueCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(inventoryValueProvider);

    return ChartCard<InventoryValue>(
      title: strings.analyticsInventoryValue,
      // Stated because this is the one figure on the screen the range chip does not change: stock on
      // hand is "right now", and a reader who narrowed the window would otherwise wonder why.
      subtitle: strings.analyticsInventoryValueNote,
      value: async,
      isEmpty: (value) => value.byCurrency.isEmpty && value.batchesNoCost == 0,
      emptyMessage: strings.analyticsNoStockValue,
      onRetry: () => ref.invalidate(inventoryValueProvider),
      builder: (context, value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in value.byCurrency.entries)
            KeyValueRow(
              label: entry.key,
              valueWidget: AnalyticsCurrencyAmount(entry.value),
            ),
          const SizedBox(height: AlayaSpacing.xs),
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xxs,
            children: [
              StatusChip(label: strings.analyticsBatchesValued(value.batchesValued)),
              if (value.batchesNoCost > 0)
                StatusChip(
                  label: strings.analyticsBatchesNoCost(value.batchesNoCost),
                  tone: StatusTone.info,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Query 14 — food waste, in quantity and money.
///
/// **One of the app's three differentiating insights** (ARCH_3 §5.1). It exists because
/// `stock_movements` records *why* stock left — `waste` and `expired` are their own kinds — so throwing
/// food away is a fact the ledger holds rather than an absence to be inferred.
///
/// Reversed movements are already excluded by the adapter, so this counts what was wasted and not what
/// was wasted and then undone.
class WasteCard extends ConsumerWidget {
  /// Creates the card.
  const WasteCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(wasteTotalsProvider);

    return ChartCard<List<ItemWasteTotal>>(
      title: strings.analyticsWaste,
      value: async,
      isEmpty: (totals) => totals.isEmpty,
      // The empty state here is good news, and it should read that way rather than as an absence of
      // data (ARCH_5 §2.8: never apologise, name what is true).
      emptyMessage: strings.analyticsNoWaste,
      onRetry: () => ref.invalidate(wasteTotalsProvider),
      builder: (context, totals) {
        // Totalled **per currency**, not across them. Where a household records everything in one
        // currency — which is the ordinary case — this is the headline: "you threw away ₹340 of food".
        // Where it does not, each currency gets its own line rather than a sum that would be wrong.
        final byCurrency = <String, int>{};
        for (final total in totals) {
          for (final cost in total.costByCurrency.entries) {
            byCurrency.update(
              cost.key,
              (minor) => minor + cost.value.minor,
              ifAbsent: () => cost.value.minor,
            );
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in byCurrency.entries)
              AnalyticsCurrencyAmount(
                Money(entry.value, entry.key),
                size: AmountSize.large,
              ),
            const SizedBox(height: AlayaSpacing.sm),
            for (final total in totals.take(_maxItems))
              Padding(
                padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
                child: Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(total.itemName, style: AlayaTypography.body),
                    QtyText(total.quantity, style: UnitStyle.mixed, muted: true),
                    for (final cost in total.costByCurrency.values)
                      AnalyticsCurrencyAmount(cost),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  static const int _maxItems = 5;
}

/// Query 15 — what is about to expire.
class ExpiringCard extends ConsumerWidget {
  /// Creates the card.
  const ExpiringCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(expiringBatchesProvider(expiryHorizonDays));

    return ChartCard<List<ExpiringBatch>>(
      title: strings.analyticsExpiring(expiryHorizonDays),
      value: async,
      isEmpty: (batches) => batches.isEmpty,
      emptyMessage: strings.analyticsNothingExpiring,
      onRetry: () => ref.invalidate(expiringBatchesProvider(expiryHorizonDays)),
      builder: (context, batches) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final batch in batches.take(_maxRows))
            Padding(
              padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
              // A `Wrap`, so the name, the quantity, the date and the chip reflow among themselves
              // rather than starving each other at a raised text scale (Law U21).
              child: Wrap(
                spacing: AlayaSpacing.xs,
                runSpacing: AlayaSpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(batch.itemName, style: AlayaTypography.body),
                  QtyText(batch.remaining, style: UnitStyle.mixed, muted: true),
                  DateText(batch.expiry, style: DateTextStyle.dayMonth, muted: true),
                  // Colour is never the only signal (Law U17): the chip carries the day count in
                  // words as well as the tone.
                  StatusChip(
                    label: batch.daysLeft <= 0
                        ? strings.analyticsExpiredAlready
                        : strings.analyticsDaysLeft(batch.daysLeft),
                    tone: batch.daysLeft <= 0
                        ? StatusTone.danger
                        : batch.daysLeft <= _urgentDays
                            ? StatusTone.warning
                            : StatusTone.neutral,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static const int _maxRows = 6;

  /// Inside this many days an expiry is amber rather than neutral, matching ARCH_3 §6's own threshold
  /// for `batchExpiry` so the calendar and this card agree about what "soon" means.
  static const int _urgentDays = 7;
}

/// Query 16 — how many items are low on stock, right now.
class LowStockCard extends ConsumerWidget {
  /// Creates the card.
  const LowStockCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(lowStockTodayProvider);

    return ChartCard<LowStockPoint>(
      title: strings.analyticsLowStock,
      // **One point, not a history, and the card says so.** `v_low_stock` reflects the present and
      // stock is not versioned, so "how many were low last Tuesday" would mean replaying the movement
      // ledger against thresholds that may since have changed.
      subtitle: strings.analyticsLowStockNote,
      value: async,
      isEmpty: (point) => point.itemCount == 0,
      emptyMessage: strings.analyticsNothingLow,
      onRetry: () => ref.invalidate(lowStockTodayProvider),
      builder: (context, point) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.analyticsLowStockCount(point.itemCount),
            style: AlayaTypography.bodyEmphasis.copyWith(color: context.semantic.warning),
          ),
          const SizedBox(height: AlayaSpacing.xxs),
          Row(
            children: [
              Text(
                strings.analyticsAsOf,
                style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
              ),
              const SizedBox(width: AlayaSpacing.xxs),
              DateText(point.date, style: DateTextStyle.medium, muted: true),
            ],
          ),
        ],
      ),
    );
  }
}
```

### `lib/features/analytics/presentation/widgets/commitment_cards.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_amount.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_donut_chart.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/presentation/widgets/slice_bar_list.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Query 17 — what is owed every month before anything discretionary happens.
///
/// Every interval is normalised to a month so a weekly bill and an annual one are comparable, and the
/// integer division truncates — so the figure is slightly conservative rather than optimistic, which is
/// the right direction for a number somebody budgets against.
class MonthlyCommitmentCard extends ConsumerWidget {
  /// Creates the card.
  const MonthlyCommitmentCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final async = ref.watch(monthlyCommitmentProvider);

    return ChartCard<MonthlyCommitment>(
      title: strings.analyticsCommitment,
      // Outflow only. Netting salary against rent would report a household with a surplus as having no
      // fixed costs at all, which is the opposite of what the figure is for.
      subtitle: strings.analyticsCommitmentNote,
      value: async,
      isEmpty: (data) => data.templateCount == 0,
      emptyMessage: strings.analyticsNoCommitments,
      onRetry: () => ref.invalidate(monthlyCommitmentProvider),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AmountText(
            data.total,
            size: AmountSize.large,
            showSign: false,
            decimalDigits: digits,
          ),
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            strings.analyticsCommitmentCount(data.templateCount),
            style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
          ),
        ],
      ),
    );
  }
}

/// Query 18 — the recurring against discretionary split.
///
/// Both sides tap through to the ledger, because "where did the discretionary half go" is the obvious
/// next question and the answer is a filtered list rather than another chart.
class RecurringSplitCard extends ConsumerWidget {
  /// Creates the card.
  const RecurringSplitCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final async = ref.watch(recurringSplitProvider);

    return ChartCard<RecurringSplit>(
      title: strings.analyticsRecurringSplit,
      value: async,
      isEmpty: (split) => split.recurring.isZero && split.discretionary.isZero,
      emptyMessage: strings.analyticsNothingSpent,
      onRetry: () => ref.invalidate(recurringSplitProvider),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, split) {
        // **Two wedges of one whole — the shape a ring is actually for.** Every withdrawal is on exactly
        // one side of this split, so the circle is the figure: how much of the month was decided before
        // it started.
        final slices = analyticsSlices(
          context,
          [
            (label: strings.analyticsRecurring, value: split.recurring.minor, key: 'recurring'),
            (
              label: strings.analyticsDiscretionary,
              value: split.discretionary.minor,
              key: 'discretionary',
            ),
          ],
          otherLabel: strings.analyticsOtherSlices,
        );
        final amounts = {
          'recurring': split.recurring,
          'discretionary': split.discretionary,
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnalyticsDonutChart(
              slices: slices,
              centreTop: AnalyticsLabels.percent(context, split.recurringShare),
              centreBottom: strings.analyticsRecurring,
            ),
            const SizedBox(height: AlayaSpacing.sm),
            Text(
              strings.analyticsRecurringShare(
                AnalyticsLabels.percent(context, split.recurringShare),
              ),
              style: AlayaTypography.bodyEmphasis,
            ),
            const SizedBox(height: AlayaSpacing.sm),
            SliceBarList(
              showBars: false,
              slices: [
                for (final slice in slices)
                  SliceBar(
                    label: slice.label,
                    value: analyticsAmount(amounts[slice.key] ?? split.recurring, digits),
                    // The real share, not a placeholder: the rows drop their bars while a ring is above
                    // them, but a `share` of zero would draw an empty bar the moment anyone turned them
                    // back on.
                    share: slice.key == 'recurring'
                        ? split.recurringShare
                        : 1 - split.recurringShare,
                    detail: AnalyticsLabels.percent(
                      context,
                      slice.key == 'recurring' ? split.recurringShare : 1 - split.recurringShare,
                    ),
                    swatch: slice.color,
                    onTap: slice.key == null
                        ? null
                        // The literals the adapter's SQL emits for the two sides, reached through the
                        // same constants the predicate compares against.
                        : () => context.push(
                              Routes.insightsDrillDown(
                                DrillDownKind.recurring.name,
                                slice.key!,
                              ),
                            ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Query 19 — what each asset has cost to keep, per currency.
///
/// **Disposed assets are included**, which is the point of `status = disposed` rather than a delete: the
/// ₹45,000 of servicing you put into a TV stays here after you sell it, and "lifetime" would be a
/// strange word for a figure that vanished on disposal.
class ServiceCostCard extends ConsumerWidget {
  /// Creates the card.
  const ServiceCostCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(serviceCostByAssetProvider);

    return ChartCard<List<AssetServiceCost>>(
      title: strings.analyticsServiceCost,
      value: async,
      isEmpty: (costs) => costs.isEmpty,
      emptyMessage: strings.analyticsNoServiceCost,
      onRetry: () => ref.invalidate(serviceCostByAssetProvider),
      builder: (context, costs) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final cost in costs.take(_maxRows))
            Padding(
              padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
              child: Wrap(
                spacing: AlayaSpacing.xs,
                runSpacing: AlayaSpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(cost.assetName, style: AlayaTypography.body),
                  Text(
                    strings.analyticsServiceCount(cost.serviceCount),
                    style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
                  ),
                  // Per currency, unconverted: a service history spanning a move abroad holds two
                  // currencies and summing them would be wrong (anomaly A34).
                  for (final amount in cost.byCurrency.values)
                    AnalyticsCurrencyAmount(amount),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static const int _maxRows = 6;
}

/// Query 20 — the warranty coverage timeline.
class WarrantyCard extends ConsumerWidget {
  /// Creates the card.
  const WarrantyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(warrantyCoverageProvider);

    return ChartCard<List<WarrantyCoverage>>(
      title: strings.analyticsWarranty,
      value: async,
      isEmpty: (rows) => rows.isEmpty,
      emptyMessage: strings.analyticsNoWarranties,
      onRetry: () => ref.invalidate(warrantyCoverageProvider),
      builder: (context, rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows.take(_maxRows))
            KeyValueRow(
              label: row.assetName,
              // `KeyValueRow` renders nothing when the value is null, which is why the end date is
              // handed over as a widget rather than a formatted string: an asset with a start and no
              // end has no coverage window to state, and the row disappears rather than showing a dash.
              valueWidget: row.end == null
                  ? null
                  : Wrap(
                      spacing: AlayaSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DateText(row.end!, style: DateTextStyle.medium, muted: true),
                        StatusChip(
                          label: row.isCovered
                              ? strings.analyticsCovered
                              : strings.analyticsCoverageEnded,
                          // `warning` for a coverage window inside 30 days, matching ARCH_3 §6's own
                          // `warrantyEnd` threshold so this card and the calendar agree.
                          tone: !row.isCovered
                              ? StatusTone.neutral
                              : (row.daysLeft ?? _warrantyWarningDays + 1) <=
                                      _warrantyWarningDays
                                  ? StatusTone.warning
                                  : StatusTone.success,
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }

  static const int _maxRows = 6;

  /// ARCH_3 §6's `warrantyEnd` threshold: 30 days, where expiry and service warn at 7.
  static const int _warrantyWarningDays = 30;
}
```

### `lib/features/analytics/presentation/widgets/cache_row.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/date_text.dart';

/// The clear-cache action — the whole of `analytics_cache`'s user-facing surface (ARCH_5 §7.1, §7.3).
///
/// **It is here rather than in Settings, and the reason is structural.** ARCH_5 §7.1 assigns the control
/// to Settings, which is a `PlaceholderScreen` until Phase 8A. It could not go in the app bar either:
/// `Routes.insights` is a shell destination, so the bar belongs to `_ShellScaffold` and an action added
/// there would appear on all nine destinations. So it sits last on the screen, quiet, in the manner of
/// archetype E's destructive actions. **Phase 8A's Settings entry must call
/// `analyticsCacheControllerProvider` rather than the service**, or one action gets two write paths
/// (Law U22).
///
/// **No `ConfirmSheet`.** Clearing a cache costs the reader a recomputation and nothing else, and
/// ARCH_5 §5.5 reserves confirmation for consequences — a confirm dialog on a harmless action trains
/// people to tap through the ones that matter.
class CacheRow extends ConsumerWidget {
  /// Creates the row.
  const CacheRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final state = ref.watch(analyticsCacheControllerProvider);
    final clearing = state.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The button is disabled while clearing rather than hidden, so the row does not move under the
        // reader's thumb (ARCH_5 §5.2: an in-place action disables, it does not throw up a barrier).
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: clearing ? null : () => _clear(context, ref),
            icon: const Icon(Icons.refresh, size: AlayaIconSize.md),
            label: Text(
              clearing ? strings.analyticsCacheClearing : strings.analyticsCacheClear,
              style: AlayaTypography.button,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.sm),
          child: Text(
            strings.analyticsCacheExplain,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ),
        // The repository's own message, in place and not only in a snack (Law U9): a snack is a timed
        // surface, and a failure the reader looked away from is a failure they never saw.
        state.when(
          data: (clearedOn) => clearedOn == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(
                    left: AlayaSpacing.sm,
                    top: AlayaSpacing.xxs,
                  ),
                  child: Row(
                    children: [
                      Text(
                        strings.analyticsCacheCleared,
                        style: AlayaTypography.caption.copyWith(color: semantic.success),
                      ),
                      const SizedBox(width: AlayaSpacing.xxs),
                      DateText(clearedOn, style: DateTextStyle.medium, muted: true),
                    ],
                  ),
                ),
          loading: () => const SizedBox.shrink(),
          error: (error, stack) => Padding(
            padding: const EdgeInsets.only(left: AlayaSpacing.sm, top: AlayaSpacing.xxs),
            child: Text(
              error.toString(),
              style: AlayaTypography.caption.copyWith(color: semantic.danger),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final ok = await ref.read(analyticsCacheControllerProvider.notifier).clear();
    if (!context.mounted) return;
    // **Every write reports its outcome** (Law U9). No Undo: there is nothing to restore, and the
    // figures are already recomputing.
    if (ok) {
      showResultSnack(context, message: strings.analyticsCacheClearedSnack);
    } else {
      showFailureSnack(context, message: strings.analyticsCacheFailed);
    }
  }
}
```

## The two screens

### `lib/features/analytics/presentation/screens/analytics_home_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_header.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_range_row.dart';
import 'package:alaya/features/analytics/presentation/widgets/cache_row.dart';
import 'package:alaya/features/analytics/presentation/widgets/commitment_cards.dart';
import 'package:alaya/features/analytics/presentation/widgets/home_cards.dart';
import 'package:alaya/features/analytics/presentation/widgets/inflation_card.dart';
import 'package:alaya/features/analytics/presentation/widgets/items_cards.dart';
import 'package:alaya/features/analytics/presentation/widgets/spend_cards.dart';
import 'package:alaya/features/analytics/presentation/widgets/time_cards.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// The analytics overview (ARCH_5 §3 archetype F).
///
/// **No `Scaffold` and no app bar.** `Routes.insights` sits inside the drawer shell, which owns both —
/// the same shape `CalendarScreen` takes. That is also why the clear-cache action is a row at the foot of
/// this screen rather than an app-bar item: a bar action would belong to `_ShellScaffold` and appear on
/// all nine destinations.
///
/// **No FAB either**, unlike the dashboard. Archetype F lists one, and nothing on an analytics screen is
/// a capture action — the drawer and the dashboard own adding money. A FAB whose only job is to leave the
/// screen it floats over is decoration.
///
/// **One `displayAmount`**, in `AnalyticsHeader`. Every other figure here is `AmountSize.small` or
/// `large`, and that hierarchy is the only reason a glance works.
///
/// **Twenty-two cards, twenty-two independent failures.** Each owns its loading, empty and error state
/// inline through `ChartCard`, so an unreachable rate table costs the reader one figure rather than the
/// screen (archetype F).
///
/// **The sections are a lazy sliver list, and that is a performance decision rather than a style one.**
/// A `SliverToBoxAdapter` holding a `Column` builds every child on mount, which here would fire
/// twenty-two SQL aggregates the moment the drawer closed — precisely the risk ARCH_4 R7 names. A
/// `SliverList` builds only what is on screen, so the commitment queries do not run until somebody
/// scrolls to them.
class AnalyticsHomeScreen extends ConsumerWidget {
  /// Creates the screen.
  const AnalyticsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final headline = ref.watch(analyticsHeadlineProvider);
    // Empty only once the headline has actually resolved: treating a pending read as empty would flash
    // the empty state on every range change (Law U4 — loading and empty are different states).
    final nothingSpent = headline.valueOrNull?.top.isEmpty ?? false;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AlayaSpacing.screenEdge,
            AlayaSpacing.md,
            AlayaSpacing.screenEdge,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AnalyticsHeader(),
                const SizedBox(height: AlayaSpacing.sm),
                const AnalyticsRangeRow(),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              nothingSpent
                  ? _emptySections(context, strings)
                  : _sections(strings),
            ),
          ),
        ),
      ],
    );
  }

  /// The full screen, in the order somebody reads it: the signature insight, then where the money went,
  /// then how it moved, then what it bought, then the house, then what is already committed.
  List<Widget> _sections(AlayaStrings strings) => [
        const SizedBox(height: AlayaSpacing.sm),
        const InflationCard(),
        _header(strings.analyticsSectionSpend),
        const SubtypeSpendCard(),
        _gap,
        const TagSpendCard(),
        _gap,
        const PaymentMethodSpendCard(),
        _gap,
        const ConcentrationCard(),
        _header(strings.analyticsSectionTime),
        const IncomeVsExpenseCard(),
        _gap,
        const NetCashFlowCard(),
        _gap,
        const BalanceTrendCard(),
        _gap,
        const SpendHeatmapCard(),
        _header(strings.analyticsSectionWhat),
        const TopPayeesCard(),
        _gap,
        const TopItemsBySpendCard(),
        _gap,
        const TopItemsByQuantityCard(),
        _gap,
        const DearestPurchaseCard(),
        _gap,
        const AverageBasketCard(),
        ..._homeSections(strings),
      ];

  /// What survives an empty window.
  ///
  /// **The house section is not range-dependent and stays.** Stock on hand, what is expiring and what is
  /// low are all "right now" figures, so hiding them because nothing was *spent* in the chosen range
  /// would withhold the answers that are still true. Only the spend-driven sections are replaced.
  List<Widget> _emptySections(BuildContext context, AlayaStrings strings) => [
        const SizedBox(height: AlayaSpacing.xl),
        EmptyState(
          title: strings.analyticsEmptyTitle,
          // Names both ways out — widen the window, or record something — because on a fresh install
          // the second is the answer and on a quiet month the first is (ARCH_5 §2.8).
          body: strings.analyticsEmptyBody,
          icon: Icons.insights_outlined,
          actionLabel: strings.addExpense,
          onAction: () => context.push(Routes.transactionNew),
        ),
        const SizedBox(height: AlayaSpacing.xl),
        ..._homeSections(strings),
      ];

  List<Widget> _homeSections(AlayaStrings strings) => [
        _header(strings.analyticsSectionHome),
        const InventoryValueCard(),
        _gap,
        const WasteCard(),
        _gap,
        const ExpiringCard(),
        _gap,
        const LowStockCard(),
        _header(strings.analyticsSectionCommitments),
        const MonthlyCommitmentCard(),
        _gap,
        const RecurringSplitCard(),
        _gap,
        const ServiceCostCard(),
        _gap,
        const WarrantyCard(),
        const SizedBox(height: AlayaSpacing.xl),
        const CacheRow(),
        // Clears the bottom of the viewport so the last row is not flush against the edge.
        const SizedBox(height: AlayaSpacing.xxxl),
      ];

  /// `xl` above a section header and `xs` below it, per ARCH_5 §2.2.
  static Widget _header(String label) => Padding(
        padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
        child: SectionHeader(label: label, padding: EdgeInsets.zero),
      );

  /// Between two cards. `sm` is the between-related-rows step (ARCH_5 §2.2).
  static const Widget _gap = SizedBox(height: AlayaSpacing.sm);
}
```

### `lib/features/analytics/presentation/screens/drill_down_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_amount.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/drill_down_providers.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';

/// The transactions behind one analytics slice (ARCH_5 §3 archetype C).
///
/// **Outside the drawer shell, so it owns its `Scaffold` and gets a back arrow.** `AppBar` resolves its
/// leading slot by checking `hasDrawer` before `canPop`, so a drill-down rendered inside the shell would
/// show a hamburger where back belongs (Law U18) — and a drill-down pushes rather than switching, which
/// is the half of Law U27 that applies here.
///
/// **Grouped by day with sticky headers**, exactly as the expense ledger is: a finance list without date
/// grouping is unreadable past twenty rows, and a drill-down that grouped differently from the ledger it
/// drills into would read as a different app.
///
/// **The window is inherited, never in the route** (ARCH_5 §5.7). Somebody who set the range to "this
/// year" and tapped a slice expects this year's transactions; a date in the path would let the two
/// disagree the moment either changed.
///
/// **No pull-to-refresh** (archetype C): the data is local and streamed, and a refresh gesture that
/// cannot do anything teaches the reader the app is slow.
class DrillDownScreen extends ConsumerWidget {
  /// Creates the screen for [spec], or an explanatory state when the route could not be parsed.
  const DrillDownScreen({required this.spec, super.key});

  /// What is filtered. Null when the path parameters named no axis this build knows.
  final DrillDownSpec? spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final resolved = spec;

    if (resolved == null) {
      // A drill-down route is deep-linkable, so a malformed one is reachable from outside the app. It
      // explains itself and offers the way on rather than throwing (Law U9, ARCH_5 §2.8).
      return Scaffold(
        appBar: AppBar(title: Text(strings.analyticsDrillTitle)),
        body: EmptyState(
          title: strings.analyticsDrillUnknownTitle,
          body: strings.analyticsDrillUnknownBody,
          icon: Icons.filter_alt_off_outlined,
          actionLabel: strings.navInsights,
          onAction: () => context.go(Routes.insights),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_title(strings, resolved, ref))),
      body: Column(
        children: [
          _ActiveFilter(spec: resolved),
          Expanded(child: _GroupedList(spec: resolved)),
        ],
      ),
    );
  }

  /// The screen's title: the resolved name where the label is data, an ARB string where it is not.
  String _title(AlayaStrings strings, DrillDownSpec spec, WidgetRef ref) {
    final resolved = ref.watch(drillDownLabelProvider(spec)).valueOrNull;
    if (resolved != null) return resolved;
    return switch (spec.kind) {
      DrillDownKind.subtype => AnalyticsLabels.subtype(strings, spec.value),
      DrillDownKind.recurring => AnalyticsLabels.recurringSide(strings, spec.value),
      // Still loading, or the record is gone. The generic title is honest for one frame and for a
      // payee that was deleted since the chart was drawn.
      _ => strings.analyticsDrillTitle,
    };
  }
}

/// The one filter narrowing this list, and the way out of it.
class _ActiveFilter extends ConsumerWidget {
  const _ActiveFilter({required this.spec});

  final DrillDownSpec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final preset = ref.watch(analyticsRangeProvider);

    // **Removing the only filter means leaving the drill-down**, so the chip pops rather than clearing
    // something in place. A chip that removed itself and left an unfiltered ledger would silently
    // duplicate the expense list on a route that is not it.
    return FilterChipBar(
      filters: [
        ActiveFilter(
          label: AnalyticsLabels.range(strings, preset),
          onRemove: () => context.canPop() ? context.pop() : context.go(Routes.insights),
        ),
      ],
    );
  }
}

/// The rows, grouped by day.
class _GroupedList extends ConsumerWidget {
  const _GroupedList({required this.spec});

  final DrillDownSpec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final days = ref.watch(drillDownDaysProvider(spec));
    final totals = ref.watch(drillDownTotalsProvider(spec)).valueOrNull ??
        const <String, int>{};

    return days.when(
      // A skeleton, not a spinner: the shape of what is arriving beats a spinner in a space that is
      // about to be a list (ARCH_5 §5.2).
      loading: () => AlayaListSkeleton(label: strings.analyticsDrillLoading),
      // **The repository's own message, not `errorBodyGeneric`** (Law U9). A figure that fails
      // identically for every cause is a failure nobody can diagnose.
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: error.toString(),
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(drillDownTransactionsProvider(spec)),
      ),
      data: (groups) {
        if (groups.isEmpty) {
          return EmptyState(
            title: strings.analyticsDrillEmptyTitle,
            // Names the likely cause — the window, not the filter — because the filter is the thing
            // the reader just chose and the window is the thing they may have forgotten.
            body: strings.analyticsDrillEmptyBody,
            icon: Icons.filter_alt_outlined,
          );
        }
        final clock = ref.watch(clockProvider);
        final background = Theme.of(context).scaffoldBackgroundColor;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _TotalsRow(totals: totals)),
            for (final group in groups)
              SliverMainAxisGroup(
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _DayHeader(
                      date: group.date,
                      clock: clock,
                      background: background,
                    ),
                  ),
                  // Virtualised (Law U13). A drill-down over "all time" on one subtype is not a short
                  // list, and mapping it into a `Column` would build every row.
                  SliverList.builder(
                    itemCount: group.transactions.length,
                    itemBuilder: (context, index) => _Row(
                      transaction: group.transactions[index],
                    ),
                  ),
                ],
              ),
            const SliverToBoxAdapter(child: SizedBox(height: AlayaSpacing.xxxl)),
          ],
        );
      },
    );
  }
}

/// What the filtered list comes to, one line per currency.
class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.totals});

  final Map<String, int> totals;

  @override
  Widget build(BuildContext context) {
    if (totals.isEmpty) return const SizedBox.shrink();
    final strings = AlayaStrings.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
        AlayaSpacing.screenEdge,
        AlayaSpacing.sm,
      ),
      child: Wrap(
        spacing: AlayaSpacing.xs,
        runSpacing: AlayaSpacing.xxs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            strings.analyticsDrillTotal,
            style: AlayaTypography.label.copyWith(color: context.semantic.muted),
          ),
          // Per currency, each with its own precision. This figure can legitimately differ from the
          // slice it came from: the slice excluded whatever could not be converted, and this one
          // excludes nothing (anomaly A15).
          for (final entry in totals.entries)
            AnalyticsCurrencyAmount(Money(entry.value, entry.key)),
        ],
      ),
    );
  }
}

/// One transaction, rendered by the ledger's own row so the two screens cannot drift apart.
class _Row extends ConsumerWidget {
  const _Row({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The expense feature's maps, watched rather than re-declared: a second `accountsByIdProvider`
    // would be a second stream over the same table (Law U19, ARCH_1 §6's 7A amendment).
    final accounts = ref.watch(accountsByIdProvider).valueOrNull ?? const <String, Account>{};
    final payees = ref.watch(payeesByIdProvider).valueOrNull ?? const <String, Payee>{};
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final from = transaction.fromAccountId;
    final to = transaction.toAccountId;
    final payeeId = transaction.payeeId;

    return TransactionRow(
      transaction: transaction,
      decimalDigits: digits,
      payee: payeeId == null ? null : payees[payeeId],
      fromAccount: from == null ? null : accounts[from],
      toAccount: to == null ? null : accounts[to],
      onTap: () => context.push(Routes.transactionDetail(transaction.id)),
    );
  }
}

/// The sticky day header, identical to the expense ledger's.
class _DayHeader extends SliverPersistentHeaderDelegate {
  const _DayHeader({
    required this.date,
    required this.clock,
    required this.background,
  });

  final DateKey date;
  final Clock clock;
  final Color background;

  // The tap-target floor rather than a hand-picked figure: it is the one height token that stays
  // legible when the text scale doubles.
  @override
  double get minExtent => AlayaSpacing.minTapTarget;

  @override
  double get maxExtent => AlayaSpacing.minTapTarget;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => ColoredBox(
        color: background,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlayaSpacing.screenEdge,
            vertical: AlayaSpacing.xs,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: DateText.relative(
              date,
              clock: clock,
              textStyle: AlayaTypography.sectionHeader,
            ),
          ),
        ),
      );

  @override
  bool shouldRebuild(_DayHeader oldDelegate) =>
      oldDelegate.date != date || oldDelegate.background != background;
}
```

## Wiring

`app_router.dart` and `app_en.arb` are each carried by seven documents and must stay byte-identical
across all of them (ARCH_6 §2), so both edits below oblige a regeneration of PHASE_05 and 06A–06F
alongside 07A.

**108 ARB keys, 969 to 1,077.** No range or weekday strings among them: `DateRangePreset`'s labels
already existed from earlier phases, and weekday initials come from
`MaterialLocalizations.narrowWeekdays` the way 7A's month grid gets them.

### `lib/app/router/app_router.dart`

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/placeholder_screen.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/analytics/presentation/screens/analytics_home_screen.dart';
import 'package:alaya/features/analytics/presentation/screens/drill_down_screen.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_detail_screen.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_editor_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_editor_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_history_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_detail_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_editor_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/occurrence_history_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_builder_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_detail_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_editor_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/service_editor_screen.dart';
import 'package:alaya/features/settings/presentation/theme_lab_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/convert_to_purchase_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/shopping_list_screen.dart';
import 'package:alaya/shared/widgets/alaya_drawer.dart';

/// Whether the app is currently locked, consulted on every navigation.
typedef LockGate = bool Function();

/// The app's `go_router` configuration — hand-written, per ARCH_1 §7.3.
///
/// **The nine drawer destinations sit inside the shell; every detail and editor route sits outside
/// it** (U18). `AppBar` resolves its leading slot by checking `hasDrawer` *before* `canPop`, so a
/// detail screen rendered inside the drawer shell gets a hamburger where a back arrow belongs.
///
/// Literal-path segments are declared before their parameterised siblings, because go_router walks
/// its route list in order and `:itemId` would otherwise swallow the word `new`.
///
/// **Phase 7B: `/insights` is now a real screen and `/insights/drill/...` is its drill-down.** The
/// drill-down is a top-level route rather than a child of `/insights`, unlike the calendar's day route:
/// a day is a view *of* the month and keeps the drawer (Law U27), while a drill-down leaves analytics
/// for the ledger and needs a back arrow, which a shell owning a drawer can never imply (Law U18).
///
/// **`_detail` was removed in 7B.** It had been declared since 6F and called by nothing, so
/// `very_good_analysis` reports `unused_element` on it — and every remaining placeholder is a shell
/// destination, which `_destination` covers. Noted because this file is carried by seven documents and
/// the deletion has to be applied to all of them.
abstract final class AppRouter {
  /// Builds the router.
  static GoRouter build({
    LockGate? isLocked,
    String initialLocation = Routes.initial,
    GlobalKey<NavigatorState>? navigatorKey,
  }) {
    final locked = isLocked ?? () => false;
    return GoRouter(
      initialLocation: initialLocation,
      navigatorKey: navigatorKey,
      debugLogDiagnostics: false,
      redirect: (context, state) {
        final atLock = state.matchedLocation == Routes.lock;
        if (locked() && !atLock) return Routes.lock;
        if (!locked() && atLock) return Routes.dashboard;
        return null;
      },
      routes: [
        GoRoute(
          path: Routes.lock,
          builder: (context, state) =>
              const PlaceholderScreen(owningPhase: 'Phase 8A'),
        ),
        ShellRoute(
          // No `location` passed: `_ShellScaffold` reads it from the router, because the state handed to a
          // pathless `ShellRoute`'s builder reports `/` for every screen inside it.
          builder: (context, state, child) => _ShellScaffold(child: child),
          routes: [
            GoRoute(
              path: Routes.dashboard,
              builder: (context, state) => const DashboardScreen(),
            ),
            GoRoute(
              path: Routes.expenses,
              builder: (context, state) => const TransactionListScreen(),
            ),
            GoRoute(
              path: Routes.inventory,
              builder: (context, state) => const InventoryListScreen(),
            ),
            GoRoute(
              path: Routes.shopping,
              builder: (context, state) => const ShoppingListScreen(),
            ),
            GoRoute(
              path: Routes.recurring,
              builder: (context, state) => const TemplateListScreen(),
            ),
            GoRoute(
              path: Routes.services,
              builder: (context, state) => const AssetListScreen(),
            ),
            GoRoute(
              path: Routes.calendar,
              builder: (context, state) => const CalendarScreen(),
              routes: [
                // A sub-route rather than a sibling detail route: a day is a view of the month, so it
                // keeps the drawer shell and the month stays behind it (Law U27).
                GoRoute(
                  path: ':${Routes.pDateKey}',
                  builder: (context, state) => CalendarScreen(
                    initialDay: _dateKeyParam(
                      state.pathParameters[Routes.pDateKey],
                    ),
                  ),
                ),
              ],
            ),
            GoRoute(
              path: Routes.insights,
              builder: (context, state) => const AnalyticsHomeScreen(),
            ),
            _destination(Routes.settings, 'Phase 8A'),
          ],
        ),
        GoRoute(
          path: Routes.transactionNew,
          builder: (context, state) => const TransactionEditorScreen(),
        ),
        GoRoute(
          path: Routes.transactionLinesNew,
          builder: (context, state) => const LineItemsScreen(),
        ),
        GoRoute(
          path: Routes.transactionLinesPattern,
          builder: (context, state) => LineItemsScreen(
            transactionId: state.pathParameters[Routes.pTransactionId],
          ),
        ),
        GoRoute(
          path: Routes.transactionEditPattern,
          builder: (context, state) => TransactionEditorScreen(
            transactionId: state.pathParameters[Routes.pTransactionId],
          ),
        ),
        GoRoute(
          path: Routes.transactionDetailPattern,
          builder: (context, state) => TransactionDetailScreen(
            transactionId: state.pathParameters[Routes.pTransactionId]!,
          ),
        ),
        GoRoute(
          path: Routes.itemNew,
          builder: (context, state) => const ItemEditorScreen(),
        ),
        GoRoute(
          path: Routes.batchNewPattern,
          builder: (context, state) => BatchEditorScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
          ),
        ),
        GoRoute(
          path: Routes.batchHistoryPattern,
          builder: (context, state) => BatchHistoryScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
            batchId: state.pathParameters[Routes.pBatchId]!,
          ),
        ),
        GoRoute(
          path: Routes.batchEditPattern,
          builder: (context, state) => BatchEditorScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
            batchId: state.pathParameters[Routes.pBatchId],
          ),
        ),
        GoRoute(
          path: Routes.itemEditPattern,
          builder: (context, state) => ItemEditorScreen(
            itemId: state.pathParameters[Routes.pItemId],
          ),
        ),
        GoRoute(
          path: Routes.itemDetailPattern,
          builder: (context, state) => ItemDetailScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingConvertPattern,
          builder: (context, state) => ConvertToPurchaseScreen(
            listId: state.pathParameters[Routes.pListId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingListPattern,
          builder: (context, state) => ShoppingListScreen(
            listId: state.pathParameters[Routes.pListId],
          ),
        ),
        GoRoute(
          path: Routes.recurringNew,
          builder: (context, state) => const TemplateBuilderScreen(),
        ),
        GoRoute(
          path: Routes.recurringHistoryPattern,
          builder: (context, state) => OccurrenceHistoryScreen(
            templateId: state.pathParameters[Routes.pTemplateId]!,
          ),
        ),
        GoRoute(
          path: Routes.recurringEditPattern,
          builder: (context, state) => TemplateBuilderScreen(
            templateId: state.pathParameters[Routes.pTemplateId],
          ),
        ),
        GoRoute(
          path: Routes.recurringDetailPattern,
          builder: (context, state) => OccurrenceHistoryScreen(
            templateId: state.pathParameters[Routes.pTemplateId]!,
          ),
        ),
        GoRoute(
          path: Routes.assetNew,
          builder: (context, state) => const AssetEditorScreen(),
        ),
        GoRoute(
          path: Routes.serviceNewPattern,
          builder: (context, state) => ServiceEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
          ),
        ),
        GoRoute(
          path: Routes.serviceEditPattern,
          builder: (context, state) => ServiceEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
            recordId: state.pathParameters[Routes.pRecordId],
          ),
        ),
        GoRoute(
          path: Routes.assetEditPattern,
          builder: (context, state) => AssetEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId],
          ),
        ),
        GoRoute(
          path: Routes.assetDetailPattern,
          builder: (context, state) => AssetDetailScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
          ),
        ),
        GoRoute(
          path: Routes.insightsDrillDownPattern,
          builder: (context, state) => DrillDownScreen(
            // Parsed rather than trusted: this route is deep-linkable, so an unknown axis has to reach
            // the screen as null and be explained there rather than throwing in a builder.
            spec: DrillDownSpec.parse(
              kind: state.pathParameters[Routes.pDrillKind],
              value: state.pathParameters[Routes.pDrillValue],
            ),
          ),
        ),
        GoRoute(
          path: Routes.themeLab,
          builder: (context, state) => _DetailScaffold(
            title: AlayaStrings.of(context).navThemeLab,
            child: const ThemeLabScreen(),
          ),
        ),
      ],
    );
  }

  /// A top-level drawer destination, rendered inside the shell.
  static GoRoute _destination(String path, String owningPhase) => GoRoute(
    path: path,
    builder: (context, state) => PlaceholderScreen(owningPhase: owningPhase),
  );
}

class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // `AppBar` resolves its implied leading by checking `hasDrawer` **before** `canPop`, so a shell that
    // owns a drawer can never show a back arrow no matter how it was reached. That is fine for a drawer
    // destination switched into as a peer, and wrong for one pushed as a drill-down — and both happen
    // here: the drawer `go`es, the dashboard's module grid `push`es.
    //
    // So the slot is stated rather than implied. Pushed: a back arrow that pops the shell's own navigator
    // (`context.pop`, not `Navigator.maybePop`, which from above the shell navigator would target the root
    // one and do nothing). Switched into: null, which lets the hamburger be implied as before.
    //
    // The drawer stays attached either way, so the edge swipe still opens it on a pushed screen.
    final strings = AlayaStrings.of(context);

    // **Read from the router, not from the builder's `state`.** `ShellRoute` declares no `path`, so the
    // `GoRouterState` handed to its builder describes the *shell's* match rather than the leaf's — and a
    // pathless route's `matchedLocation` is its parent's, which here is `/`. Every screen inside the shell
    // therefore looked like the dashboard: `atDashboard` was permanently true so the home action never
    // rendered, `AlayaDrawer` highlighted Dashboard wherever you were, and `titleFor` named it too.
    //
    // `currentConfiguration` is the delegate's live `RouteMatchList`, so its `uri` is the leaf location no
    // matter which builder asks.
    final here = GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;

    // **`context.canPop()` cannot answer this question from here.** This widget is the `ShellRoute`
    // builder, so its context sits *above* the shell's own `Navigator`; `canPop` resolves against the
    // root navigator, which only ever holds the shell itself. It therefore returns false however the
    // screen was reached, `leading` was always null, and the back arrow this once tried to show could
    // never appear. The drawer's hamburger was the only leading widget users ever saw, and from a module
    // the sole way home was the system back gesture.
    //
    // So the way home is stated outright instead of inferred from a stack this context cannot see: every
    // shell screen except the dashboard carries a home action. It pops when there is something to pop and
    // navigates otherwise, so arriving by the module grid's `push` and by the drawer's `go` both end up
    // in the same place — and the hamburger keeps its slot, because the drawer is still how you move
    // between peers (Law U27).
    return Scaffold(
      drawer: AlayaDrawer(currentLocation: here),
      appBar: AppBar(
        title: Text(AlayaDrawer.titleFor(context, here)),
        // **Unconditional, deliberately.** This was `if (!atDashboard)` and never appeared, and rather
        // than reason about why a condition is false I would rather the button exist and be seen. It
        // shows on the dashboard too, where it is merely redundant — a redundant button is a far smaller
        // fault than a missing one, and its presence there is also the proof that this file is live.
        //
        // Once it is confirmed visible, `if (!atDashboard)` can come back.
        actions: [
          IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(Routes.dashboard),
            tooltip: strings.navBackToDashboard,
            icon: const Icon(Icons.home_outlined, size: AlayaIconSize.md),
          ),
        ],
      ),
      body: child,
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: child,
  );
}

/// Parses a `:dateKey` path parameter, or null when it is absent or not a date key.
///
/// A malformed deep link opens the calendar on today rather than throwing — the route is reachable
/// from outside the app.
DateKey? _dateKeyParam(String? raw) {
  final value = int.tryParse(raw ?? '');
  if (value == null) return null;

  final year = value ~/ 10000;
  final month = (value ~/ 100) % 100;
  final day = value % 100;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  // Round-trip through `fromYmd`, which normalises overflow through `DateTime.utc`: 20260230 comes
  // back as 20260302 and fails this check, where a digit-range test alone would accept it.
  final probe = DateKey.fromYmd(year, month, day);
  return probe.value == value ? probe : null;
}
```

### `lib/app/l10n/app_en.arb`

```json
{
  "@@locale": "en",
  "appName": "Alaya",
  "@appName": {
    "description": "The app's name, shown in the drawer header."
  },
  "navDashboard": "Dashboard",
  "navExpenses": "Expenses",
  "navInventory": "Inventory",
  "navShopping": "Shopping",
  "navRecurring": "Recurring",
  "navServices": "Services",
  "navCalendar": "Calendar",
  "navInsights": "Insights",
  "navSettings": "Settings",
  "navThemeLab": "Theme Lab",
  "actionSave": "Save",
  "@actionSave": {
    "description": "Commits an edit. Active voice, and the same word appears in the resulting confirmation."
  },
  "actionSaved": "Saved",
  "actionCancel": "Cancel",
  "actionDelete": "Delete",
  "actionDeleted": "Deleted",
  "actionUndo": "Undo",
  "actionRetry": "Try again",
  "actionAdd": "Add",
  "actionEdit": "Edit",
  "actionDone": "Done",
  "actionClose": "Close",
  "actionSelect": "Select",
  "actionClear": "Clear",
  "actionClearAll": "Clear all",
  "actionSearch": "Search",
  "actionConfirm": "Confirm",
  "actionDiscard": "Discard",
  "actionKeepEditing": "Keep editing",
  "actionRemoveTag": "Remove tag",
  "@actionRemoveTag": {
    "description": "Accessibility label for the dismiss affordance on a removable tag chip."
  },
  "actionClearSearch": "Clear search",
  "@actionClearSearch": {
    "description": "Accessibility label for the clear button inside AlayaSearchField."
  },
  "addExpense": "Add expense",
  "addIncome": "Add income",
  "addTransfer": "Add transfer",
  "addItem": "Add item",
  "addToShoppingList": "Add to shopping list",
  "dateToday": "Today",
  "@dateToday": {
    "description": "DateText.relative, when the date is the clock's today. Sentence case; it can begin a row."
  },
  "dateYesterday": "Yesterday",
  "dateTomorrow": "Tomorrow",
  "emptyTitleNoTransactions": "No transactions yet",
  "emptyBodyNoTransactions": "Add your first expense and it will appear here.",
  "@emptyBodyNoTransactions": {
    "description": "An empty screen is an invitation to act, so this names the action rather than describing the emptiness."
  },
  "emptyTitleNoItems": "Nothing in your inventory",
  "emptyBodyNoItems": "Add an item to start tracking what you have at home.",
  "emptyTitleNoShopping": "Your list is empty",
  "emptyBodyNoShopping": "Add something, or let Alaya suggest items you are low on.",
  "emptyTitleNoRecurring": "No recurring bills",
  "emptyBodyNoRecurring": "Set up a bill or subscription and Alaya will remind you when it is due.",
  "emptyTitleNoResults": "No matches",
  "emptyBodyNoResults": "Try a shorter search, or check the spelling.",
  "loadingLabel": "Loading",
  "loadingTransactions": "Loading transactions",
  "errorTitleGeneric": "That did not work",
  "@errorTitleGeneric": {
    "description": "Errors do not apologise and are never vague. This pairs with a specific body message."
  },
  "errorBodyGeneric": "Something went wrong on our side. Try again.",
  "errorTitleNotFound": "Not found",
  "errorBodyNotFound": "This item may have been deleted.",
  "errorBodyNoConnection": "You are offline. Alaya works offline, but rates will not refresh.",
  "errorFieldRequired": "This is required",
  "errorAmountInvalid": "Enter an amount",
  "errorAmountZero": "Enter an amount greater than zero",
  "errorAmountInvalidCharacter": "Digits only",
  "errorAmountNegativeNotAllowed": "Enter a positive amount",
  "errorAmountTooManyDecimals": "Too many decimal places",
  "errorAmountTooLarge": "That amount is too large",
  "errorQuantityTooLarge": "That quantity is too large",
  "errorQuantityInvalid": "Enter a quantity",
  "errorQuantityInvalidCharacter": "Digits only",
  "errorQuantityNegativeNotAllowed": "Enter a positive quantity",
  "errorQuantityTooPrecise": "Too precise for this unit",
  "@errorQuantityTooPrecise": {
    "description": "The typed quantity is finer than the chosen unit can express exactly. Shown rather than rounded, because rounding a quantity silently changes what the user recorded."
  },
  "errorDateInvalid": "Choose a date",
  "confirmDeleteTitle": "Delete this?",
  "confirmDeleteBody": "You can undo this for the next few seconds.",
  "confirmDiscardTitle": "Discard your changes?",
  "confirmDiscardBody": "What you have typed will not be saved.",
  "labelAmount": "Amount",
  "labelQuantity": "Quantity",
  "labelUnit": "Unit",
  "labelDate": "Date",
  "labelAccount": "Account",
  "labelPaymentMethod": "Payment method",
  "labelPayee": "Payee",
  "labelCategory": "Category",
  "labelTags": "Tags",
  "labelNote": "Note",
  "labelFrom": "From",
  "labelTo": "To",
  "labelItem": "Item",
  "labelExpiry": "Expiry",
  "labelTotal": "Total",
  "hintSelectAccount": "Choose an account",
  "hintSelectUnit": "Choose a unit",
  "hintSelectTags": "Choose tags",
  "hintSelectDate": "Choose a date",
  "hintSearchItems": "Search items",
  "hintNote": "Add a note",
  "amountUnconverted": "{count, plural, =1{1 amount not converted} other{{count} amounts not converted}}",
  "@amountUnconverted": {
    "description": "The chip beside a total when some amounts had no exchange rate. Surfaced rather than hidden, because a total missing a row is otherwise indistinguishable from a complete one.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "amountApproximate": "Approximate rate",
  "@amountApproximate": {
    "description": "Shown when a conversion used the nearest earlier rate rather than the exact date's."
  },
  "tagCountMore": "+{count}",
  "@tagCountMore": {
    "description": "Overflow indicator when a row cannot show every tag.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "statusNeedsReview": "Needs details",
  "@statusNeedsReview": {
    "description": "StatusChip on a transaction saved by quick-add. Names what is missing, not that a flag is set."
  },
  "statusUnallocated": "Unallocated",
  "@statusUnallocated": {
    "description": "StatusChip label when a transaction's lines do not sum to its amount. The figure is a separate AmountText (U7); never auto-balanced (anomaly A11)."
  },
  "statusDetached": "Receipt deleted",
  "@statusDetached": {
    "description": "StatusChip on a batch whose source transaction was deleted. The food did not un-exist."
  },
  "statusApproximate": "Approximate",
  "lowStockLabel": "Low",
  "expiringSoonLabel": "Expiring soon",
  "expiredLabel": "Expired",
  "overdueLabel": "Overdue",
  "dueTodayLabel": "Due today",
  "paidLabel": "Paid",
  "skippedLabel": "Skipped",
  "kindDeposit": "Money in",
  "kindWithdrawal": "Money out",
  "kindTransfer": "Transfer",
  "kindAdjustmentIncrease": "Correction up",
  "kindAdjustmentDecrease": "Correction down",
  "subtypeGrocery": "Groceries",
  "subtypeHousehold": "Household",
  "subtypeElectronics": "Electronics",
  "subtypeBill": "Bill",
  "subtypeTransferSelf": "Between my accounts",
  "subtypeTransferOut": "Sent to someone",
  "subtypeSalaryIn": "Salary",
  "subtypeOtherIn": "Other income",
  "subtypeOtherOut": "Other spending",
  "needsReviewBanner": "{count, plural, =1{1 transaction needs details} other{{count} transactions need details}}",
  "@needsReviewBanner": {
    "description": "Surfaces transactions.needsReview. Quick-add saves an amount and nothing else by design; without this row that deliberate shortcut becomes silent data rot.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "needsReviewAction": "Review",
  "filterTitle": "Filter",
  "filterDateRange": "Date range",
  "filterKind": "Type",
  "filterSubtype": "Category",
  "filterApply": "Show results",
  "filterReset": "Reset",
  "filterChipAccount": "Account: {name}",
  "@filterChipAccount": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "filterChipPayee": "Payee: {name}",
  "@filterChipPayee": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "filterChipRange": "{label}",
  "@filterChipRange": {
    "placeholders": {
      "label": {
        "type": "String"
      }
    }
  },
  "rangeToday": "Today",
  "rangeLast7Days": "Last 7 days",
  "rangeLast30Days": "Last 30 days",
  "rangeThisMonth": "This month",
  "rangeLastMonth": "Last month",
  "rangeThisYear": "This year",
  "rangeAllTime": "All time",
  "rangeCustom": "Custom",
  "searchTransactionsHint": "Search notes",
  "transactionDeleted": "Transaction deleted",
  "quickAddTitle": "Quick add",
  "quickAddMoneyIn": "Money in",
  "quickAddMoneyOut": "Money out",
  "quickAddSave": "Save",
  "actionAddDetails": "Add details",
  "editorTitleNew": "New transaction",
  "editorTitleEdit": "Edit transaction",
  "sectionWhatAndHowMuch": "What and how much",
  "sectionWhereItCameFrom": "Where it came from",
  "sectionWhereItWent": "Where it went",
  "sectionWhatYouBought": "What you bought",
  "sectionWarranty": "Warranty",
  "sectionSchedule": "Schedule",
  "transferOwnAccount": "To my own account",
  "transferSomeoneElse": "To someone else",
  "transferOwnAccountHelp": "Moves money between your accounts. Your total does not change.",
  "transferSomeoneElseHelp": "Money leaves your accounts. This is a withdrawal.",
  "alsoAddToInventory": "Also add to inventory",
  "destinationNone": "Just an expense",
  "destinationInventory": "Save to Inventory",
  "destinationAsset": "Save to Services",
  "destinationRecurring": "Save to Recurring",
  "lineAdd": "Add item",
  "lineDescription": "Item",
  "lineUnitPrice": "Unit price",
  "lineAmount": "Line total",
  "lineCreatedLink": "Created: {name}",
  "@lineCreatedLink": {
    "description": "Surfaces transaction_lines.created*Id — the artefact this line produced, tappable through to it.",
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "payeeCreate": "New payee “{name}”",
  "@payeeCreate": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "saveExpense": "Save expense",
  "saveIncome": "Save income",
  "saveTransfer": "Save transfer",
  "detailSectionLines": "Items",
  "detailSectionDetails": "Details",
  "actionFreezeConversion": "Show in another currency",
  "frozenConversionNote": "Frozen on {date} at {rate}",
  "@frozenConversionNote": {
    "description": "Surfaces transactions.converted*/conversionRateRaw. A separate artefact that is never recomputed (Law L9).",
    "placeholders": {
      "date": {
        "type": "String"
      },
      "rate": {
        "type": "String"
      }
    }
  },
  "deleteReasonHint": "Why? (optional)",
  "actionDeleteTransaction": "Delete transaction",
  "labelSubtype": "Category",
  "labelKind": "Type",
  "themeLabTitle": "Theme Lab",
  "themeLabSubtitle": "Every token, component and semantic colour, light and dark.",
  "themeLabSectionSpacing": "Spacing",
  "themeLabSectionRadii": "Radii",
  "themeLabSectionTypography": "Typography",
  "themeLabSectionElevation": "Elevation",
  "themeLabSectionSemantic": "Semantic colours",
  "themeLabSectionSurfaces": "Surface tiers",
  "themeLabSectionComponents": "Components",
  "themeLabSectionPalettes": "Palettes",
  "themeLabLight": "Light",
  "themeLabDark": "Dark",
  "semanticIncome": "Income",
  "semanticExpense": "Expense",
  "semanticTransfer": "Transfer",
  "semanticWarning": "Warning",
  "semanticDanger": "Danger",
  "semanticSuccess": "Success",
  "semanticMuted": "Muted",
  "drawerSectionMoney": "Money",
  "drawerSectionHome": "Home",
  "drawerSectionMore": "More",
  "inventoryGroupFavourites": "Favourites",
  "@inventoryGroupFavourites": {
    "description": "Phase 6B — inventory."
  },
  "inventoryGroupUntagged": "Everything else",
  "@inventoryGroupUntagged": {
    "description": "Phase 6B — inventory."
  },
  "itemKindGeneric": "General",
  "@itemKindGeneric": {
    "description": "Phase 6B — inventory."
  },
  "itemKindFood": "Food",
  "@itemKindFood": {
    "description": "Phase 6B — inventory."
  },
  "itemKindMedicine": "Medicine",
  "@itemKindMedicine": {
    "description": "Phase 6B — inventory."
  },
  "itemKindBeauty": "Beauty",
  "@itemKindBeauty": {
    "description": "Phase 6B — inventory."
  },
  "itemKindHousehold": "Household",
  "@itemKindHousehold": {
    "description": "Phase 6B — inventory."
  },
  "itemKindOther": "Other",
  "@itemKindOther": {
    "description": "Phase 6B — inventory."
  },
  "filterFavouritesOnly": "Favourites only",
  "@filterFavouritesOnly": {
    "description": "Phase 6B — inventory."
  },
  "actionFavourite": "Add to favourites",
  "@actionFavourite": {
    "description": "Phase 6B — inventory."
  },
  "actionUnfavourite": "Remove from favourites",
  "@actionUnfavourite": {
    "description": "Phase 6B — inventory."
  },
  "outOfStockLabel": "Out of stock",
  "@outOfStockLabel": {
    "description": "Phase 6B — inventory."
  },
  "itemBatchCount": "{count, plural, =1{1 batch} other{{count} batches}}",
  "@itemBatchCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "loadingInventory": "Loading inventory",
  "@loadingInventory": {
    "description": "Phase 6B — inventory."
  },
  "detailSectionBatches": "Batches",
  "@detailSectionBatches": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginPurchase": "From a purchase",
  "@batchOriginPurchase": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginManual": "Added by hand",
  "@batchOriginManual": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginImported": "Imported",
  "@batchOriginImported": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginAdjustment": "From an adjustment",
  "@batchOriginAdjustment": {
    "description": "Phase 6B — inventory."
  },
  "labelPurchased": "Purchased",
  "@labelPurchased": {
    "description": "Phase 6B — inventory."
  },
  "labelStorageLocation": "Stored in",
  "@labelStorageLocation": {
    "description": "Phase 6B — inventory."
  },
  "labelUnitCost": "Unit cost",
  "@labelUnitCost": {
    "description": "Phase 6B — inventory."
  },
  "labelInitial": "Bought",
  "@labelInitial": {
    "description": "Phase 6B — inventory."
  },
  "labelNearestExpiry": "Nearest expiry",
  "@labelNearestExpiry": {
    "description": "Phase 6B — inventory."
  },
  "labelDisplayUnit": "Shown in",
  "@labelDisplayUnit": {
    "description": "Phase 6B — inventory."
  },
  "labelItemKind": "Kind",
  "@labelItemKind": {
    "description": "Phase 6B — inventory."
  },
  "labelLowStockThreshold": "Low-stock level",
  "@labelLowStockThreshold": {
    "description": "Phase 6B — inventory."
  },
  "labelExpiryNotifyDays": "Warn before expiry",
  "@labelExpiryNotifyDays": {
    "description": "Phase 6B — inventory."
  },
  "actionConsume": "Use some",
  "@actionConsume": {
    "description": "Phase 6B — inventory."
  },
  "actionAddBatch": "Add a batch",
  "@actionAddBatch": {
    "description": "Phase 6B — inventory."
  },
  "actionViewHistory": "Movement history",
  "@actionViewHistory": {
    "description": "Phase 6B — inventory."
  },
  "actionDeleteItem": "Delete item",
  "@actionDeleteItem": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteItemTitle": "Delete this item?",
  "@confirmDeleteItemTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteItemBody": "Its {count, plural, =1{1 batch} other{{count} batches}} go with it. The movement history stays, so what you already used is still recorded.",
  "@confirmDeleteItemBody": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "itemDeleted": "Item deleted",
  "@itemDeleted": {
    "description": "Phase 6B — inventory."
  },
  "expiresInDays": "{days, plural, =0{Expires today} =1{Expires tomorrow} other{Expires in {days} days}}",
  "@expiresInDays": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "expiredDaysAgo": "{days, plural, =1{Expired yesterday} other{Expired {days} days ago}}",
  "@expiredDaysAgo": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "sectionWhatItIs": "What it is",
  "@sectionWhatItIs": {
    "description": "Phase 6B — inventory."
  },
  "sectionStockRules": "Stock rules",
  "@sectionStockRules": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryWeight": "Weight",
  "@unitCategoryWeight": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryVolume": "Volume",
  "@unitCategoryVolume": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryCount": "Count",
  "@unitCategoryCount": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryLocked": "Measured in {category}",
  "@unitCategoryLocked": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "category": {}
    }
  },
  "unitCategoryLockedHelp": "This cannot change. Every batch and movement already recorded is stored in this measure, and there is no conversion between weight, volume and count.",
  "@unitCategoryLockedHelp": {
    "description": "Phase 6B — inventory."
  },
  "expiryNotifyDaysHelp": "Days of warning before a batch expires.",
  "@expiryNotifyDaysHelp": {
    "description": "Phase 6B — inventory."
  },
  "labelFavourite": "Favourite",
  "@labelFavourite": {
    "description": "Phase 6B — inventory."
  },
  "saveItem": "Save item",
  "@saveItem": {
    "description": "Phase 6B — inventory."
  },
  "sectionHowMuch": "How much",
  "@sectionHowMuch": {
    "description": "Phase 6B — inventory."
  },
  "sectionBatchDetails": "Batch details",
  "@sectionBatchDetails": {
    "description": "Phase 6B — inventory."
  },
  "saveBatch": "Save batch",
  "@saveBatch": {
    "description": "Phase 6B — inventory."
  },
  "batchSaved": "Batch saved",
  "@batchSaved": {
    "description": "Phase 6B — inventory."
  },
  "hintStorageLocation": "Freezer, pantry, bathroom shelf…",
  "@hintStorageLocation": {
    "description": "Phase 6B — inventory."
  },
  "consumeTitle": "Use stock",
  "@consumeTitle": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindConsume": "Used",
  "@consumeKindConsume": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindWaste": "Thrown away",
  "@consumeKindWaste": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindExpired": "Expired",
  "@consumeKindExpired": {
    "description": "Phase 6B — inventory."
  },
  "consumeRecorded": "Recorded",
  "@consumeRecorded": {
    "description": "Phase 6B — inventory."
  },
  "consumeFromLabel": "Taking from",
  "@consumeFromLabel": {
    "description": "Phase 6B — inventory."
  },
  "consumeFefoNote": "Oldest expiry first.",
  "@consumeFefoNote": {
    "description": "Phase 6B — inventory."
  },
  "consumeSpansBatches": "{count, plural, =1{Takes all of 1 batch} other{Spans {count} batches, writing {count} movements}}",
  "@consumeSpansBatches": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "consumeOverAvailable": "More than you have on hand",
  "@consumeOverAvailable": {
    "description": "Phase 6B — inventory."
  },
  "historyTitle": "Movement history",
  "@historyTitle": {
    "description": "Phase 6B — inventory."
  },
  "movementKindOpeningIn": "Opening stock",
  "@movementKindOpeningIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindPurchaseIn": "Bought",
  "@movementKindPurchaseIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindManualIn": "Added by hand",
  "@movementKindManualIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindConsume": "Used",
  "@movementKindConsume": {
    "description": "Phase 6B — inventory."
  },
  "movementKindWaste": "Thrown away",
  "@movementKindWaste": {
    "description": "Phase 6B — inventory."
  },
  "movementKindExpired": "Expired",
  "@movementKindExpired": {
    "description": "Phase 6B — inventory."
  },
  "movementKindAdjustIn": "Adjusted up",
  "@movementKindAdjustIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindAdjustOut": "Adjusted down",
  "@movementKindAdjustOut": {
    "description": "Phase 6B — inventory."
  },
  "movementReversed": "Reversed",
  "@movementReversed": {
    "description": "Phase 6B — inventory."
  },
  "movementIsReversal": "Reverses an earlier movement",
  "@movementIsReversal": {
    "description": "Phase 6B — inventory."
  },
  "actionReverse": "Reverse",
  "@actionReverse": {
    "description": "Phase 6B — inventory."
  },
  "confirmReverseTitle": "Reverse this movement?",
  "@confirmReverseTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmReverseBody": "An opposite movement is appended. Nothing is erased — both entries stay in the history.",
  "@confirmReverseBody": {
    "description": "Phase 6B — inventory."
  },
  "movementReversedSnack": "Movement reversed",
  "@movementReversedSnack": {
    "description": "Phase 6B — inventory."
  },
  "emptyTitleNoMovements": "Nothing recorded yet",
  "@emptyTitleNoMovements": {
    "description": "Phase 6B — inventory."
  },
  "emptyBodyNoMovements": "Using, wasting or adjusting this batch will show up here.",
  "@emptyBodyNoMovements": {
    "description": "Phase 6B — inventory."
  },
  "emptyBodyNoBatches": "Add a batch and it will appear here with its expiry.",
  "@emptyBodyNoBatches": {
    "description": "Phase 6B — inventory."
  },
  "batchQuantityLockedHelp": "How much is left is worked out from the movement history. Use, waste or adjust the batch to change it.",
  "@batchQuantityLockedHelp": {
    "description": "Phase 6B — inventory."
  },
  "daysCount": "{days, plural, =1{1 day} other{{days} days}}",
  "@daysCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "groupByFavourites": "Group favourites first",
  "@groupByFavourites": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitUsed": "Record as used",
  "@consumeCommitUsed": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitWaste": "Record as thrown away",
  "@consumeCommitWaste": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitExpired": "Record as expired",
  "@consumeCommitExpired": {
    "description": "Phase 6B — inventory."
  },
  "lowStockWithCount": "Low · {count}",
  "@lowStockWithCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "actionDeleteBatch": "Delete batch",
  "@actionDeleteBatch": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteBatchTitle": "Delete this batch?",
  "@confirmDeleteBatchTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteBatchBody": "The stock it still holds disappears from your on-hand total. What you already used stays in the movement history.",
  "@confirmDeleteBatchBody": {
    "description": "Phase 6B — inventory."
  },
  "batchDeleted": "Batch deleted",
  "@batchDeleted": {
    "description": "Phase 6B — inventory."
  },
  "itemCreate": "New item",
  "@itemCreate": {
    "description": "Creates a catalogued item inline while itemising a receipt."
  },
  "itemCreateHint": "No items yet — create one so this line becomes stock.",
  "@itemCreateHint": {
    "description": "Shown in the line editor when the item catalogue is empty."
  },
  "itemCreateCategoryPrompt": "How is it measured? This cannot change later.",
  "@itemCreateCategoryPrompt": {
    "description": "Prompt for unitCategory on inline creation; immutable after create (Law L8)."
  },
  "itemDuplicateBody": "You already have this item, measured the same way. Open the one you have instead of adding a second.",
  "@itemDuplicateBody": {
    "description": "Shown when an item with the same normalized name and unit category exists."
  },
  "itemUnitsMissingBody": "No units are set up for this measure yet. Pick a different measure, or add units in Settings first.",
  "@itemUnitsMissingBody": {
    "description": "Shown when the chosen UnitCategory has no rows in units."
  },
  "itemSimilarNote": "You also have this name under a different measure. That is fine — weight, volume and count never convert into each other.",
  "@itemSimilarNote": {
    "description": "Informational note, never a block: Law L8 makes same-name/different-category distinct items."
  },
  "actionOpenExisting": "Open the one I have",
  "@actionOpenExisting": {
    "description": "Opens the existing item a duplicate collides with."
  },
  "shoppingEstimate": "Estimated",
  "@shoppingEstimate": {
    "description": "Running total of estimated prices on a shopping list."
  },
  "shoppingSwitchList": "Switch list",
  "@shoppingSwitchList": {
    "description": "Opens the list manager from the app bar."
  },
  "shoppingCheckedCount": "{checked} of {total} ticked",
  "@shoppingCheckedCount": {
    "description": "Progress line above a shopping list.",
    "placeholders": {
      "checked": {},
      "total": {}
    }
  },
  "emptyTitleNoEntries": "Nothing on this list yet",
  "@emptyTitleNoEntries": {
    "description": "Shopping list empty state."
  },
  "emptyBodyNoEntries": "Add what you need, or pull in suggestions from what is running low.",
  "@emptyBodyNoEntries": {
    "description": "Shopping list empty state body."
  },
  "addEntry": "Add",
  "@addEntry": {
    "description": "Adds one entry to a shopping list."
  },
  "shoppingGroupUntagged": "Everything else",
  "@shoppingGroupUntagged": {
    "description": "Header for entries with no tag."
  },
  "actionUncheckAll": "Untick everything",
  "@actionUncheckAll": {
    "description": "Clears every tick on a shopping list."
  },
  "entryEditorTitle": "What do you need?",
  "@entryEditorTitle": {
    "description": "Entry editor sheet title."
  },
  "entryFreeTextLabel": "Name it",
  "@entryFreeTextLabel": {
    "description": "Free-text label for a shopping entry."
  },
  "entryFreeTextHint": "Television, birthday card, light bulbs…",
  "@entryFreeTextHint": {
    "description": "Hint showing that an entry need not be an inventory item."
  },
  "entryLinkItem": "Link to an item",
  "@entryLinkItem": {
    "description": "Optional link from a shopping entry to a catalogued item."
  },
  "entryNoItem": "Not in my inventory",
  "@entryNoItem": {
    "description": "Dropdown option leaving itemId null."
  },
  "labelEstimatedPrice": "Estimated price",
  "@labelEstimatedPrice": {
    "description": "Optional per-entry price estimate."
  },
  "entryNeedsSomething": "Give it a name, or link it to an item",
  "@entryNeedsSomething": {
    "description": "Rejection when neither freeText nor itemId is set."
  },
  "originAutoLowStock": "Suggested",
  "@originAutoLowStock": {
    "description": "Chip marking an auto-generated low-stock entry."
  },
  "originPromoted": "Yours now",
  "@originPromoted": {
    "description": "Chip shown once an auto entry has been edited into a manual one."
  },
  "actionSnooze": "Snooze a week",
  "@actionSnooze": {
    "description": "Hides an auto suggestion until a later date."
  },
  "actionDismiss": "Not now",
  "@actionDismiss": {
    "description": "Dismisses an auto suggestion until stock recovers and drops again."
  },
  "snoozedUntilLabel": "Snoozed until",
  "@snoozedUntilLabel": {
    "description": "Precedes a DateText on a snoozed entry."
  },
  "generateTitle": "Running low",
  "@generateTitle": {
    "description": "Low-stock suggestion sheet title."
  },
  "generateBody": "These are below the level you set. Add the ones you want.",
  "@generateBody": {
    "description": "Low-stock suggestion sheet body."
  },
  "generateShortBy": "Short by",
  "@generateShortBy": {
    "description": "Precedes a QtyText giving threshold minus stock on hand."
  },
  "generateRefresh": "Check again",
  "@generateRefresh": {
    "description": "Re-runs low-stock generation."
  },
  "generateEmptyTitle": "Nothing is running low",
  "@generateEmptyTitle": {
    "description": "Generate sheet empty state."
  },
  "generateEmptyBody": "Set a low-stock level on an item and it will show up here when it drops.",
  "@generateEmptyBody": {
    "description": "Generate sheet empty state body."
  },
  "generateAdded": "{count, plural, =1{1 suggestion added} other{{count} suggestions added}}",
  "@generateAdded": {
    "description": "Result snack after regeneration.",
    "placeholders": {
      "count": {}
    }
  },
  "convertTitle": "Turn into a purchase",
  "@convertTitle": {
    "description": "Convert-to-purchase screen title."
  },
  "convertBody": "Each ticked entry becomes one line, marked for inventory. You confirm the amount and account next.",
  "@convertBody": {
    "description": "Explains the handoff to the expense editor."
  },
  "convertConfirm": "Open the expense",
  "@convertConfirm": {
    "description": "Primary action; hands off to the 6A editor."
  },
  "convertNothingTitle": "Nothing is ticked",
  "@convertNothingTitle": {
    "description": "Convert screen empty state."
  },
  "convertNothingBody": "Tick what you actually bought, then come back.",
  "@convertNothingBody": {
    "description": "Convert screen empty state body."
  },
  "convertLineCount": "{count, plural, =1{1 line} other{{count} lines}}",
  "@convertLineCount": {
    "description": "How many lines the draft will carry.",
    "placeholders": {
      "count": {}
    }
  },
  "listManagerTitle": "Your lists",
  "@listManagerTitle": {
    "description": "List manager sheet title."
  },
  "listNameLabel": "List name",
  "@listNameLabel": {
    "description": "Field label when creating or renaming a list."
  },
  "listCreate": "New list",
  "@listCreate": {
    "description": "Creates a shopping list."
  },
  "listRename": "Rename",
  "@listRename": {
    "description": "Renames a shopping list."
  },
  "listSetDefault": "Make default",
  "@listSetDefault": {
    "description": "Marks a list as the one that opens by default."
  },
  "listDefaultBadge": "Default",
  "@listDefaultBadge": {
    "description": "Chip on the default list."
  },
  "listArchive": "Archive",
  "@listArchive": {
    "description": "Archives a shopping list."
  },
  "listUnarchive": "Restore",
  "@listUnarchive": {
    "description": "Un-archives a shopping list."
  },
  "listArchivedBadge": "Archived",
  "@listArchivedBadge": {
    "description": "Chip on an archived list."
  },
  "listArchivedSection": "Archived",
  "@listArchivedSection": {
    "description": "Section header for archived lists."
  },
  "emptyTitleNoLists": "No lists yet",
  "@emptyTitleNoLists": {
    "description": "List manager empty state."
  },
  "emptyBodyNoLists": "Create one and it becomes your default.",
  "@emptyBodyNoLists": {
    "description": "List manager empty state body."
  },
  "loadingShopping": "Loading your list",
  "@loadingShopping": {
    "description": "Skeleton label for shopping surfaces."
  },
  "actionAddToList": "Add to my list",
  "@actionAddToList": {
    "description": "Accepts a low-stock suggestion, promoting it to origin=manual so regeneration leaves it alone."
  },
  "suggestionDismissed": "Turned down",
  "@suggestionDismissed": {
    "description": "Chip on a dismissed suggestion; it stays listed so it can be accepted later."
  },
  "lineItemsTitle": "What you bought",
  "@lineItemsTitle": {
    "description": "Title of the dedicated line-items page."
  },
  "lineItemsManage": "Add or edit items",
  "@lineItemsManage": {
    "description": "Opens the line-items page from the transaction editor."
  },
  "lineItemsAdd": "Add an item",
  "@lineItemsAdd": {
    "description": "Adds one line from the line-items page."
  },
  "lineItemsSaveAndAnother": "Save & add another",
  "@lineItemsSaveAndAnother": {
    "description": "Commits the line and reopens the editor blank, so a receipt is entered without leaving the sheet."
  },
  "lineItemsCount": "{count, plural, =0{No items yet} =1{1 item} other{{count} items}}",
  "@lineItemsCount": {
    "description": "Running count on the line-items page.",
    "placeholders": {
      "count": {}
    }
  },
  "emptyTitleNoLineItems": "Nothing itemised yet",
  "@emptyTitleNoLineItems": {
    "description": "Line-items page empty state."
  },
  "emptyBodyNoLineItems": "Add what was on the receipt. Anything you leave out still counts toward the total.",
  "@emptyBodyNoLineItems": {
    "description": "Line-items page empty state body."
  },
  "actionRemove": "Remove",
  "@actionRemove": {
    "description": "Removes one line from a transaction."
  },
  "lineRemoved": "Item removed",
  "@lineRemoved": {
    "description": "Snack after removing a line."
  },
  "lineItemsAllocated": "Itemised",
  "@lineItemsAllocated": {
    "description": "Precedes the summed line total on the line-items page."
  },
  "recurringOutflow": "Going out",
  "@recurringOutflow": {
    "description": "Group header for outflow templates."
  },
  "recurringInflow": "Coming in",
  "@recurringInflow": {
    "description": "Group header for inflow templates — salary reads as income, not a negative bill."
  },
  "recurringNextDue": "Next",
  "@recurringNextDue": {
    "description": "Precedes a DateText giving the next due date."
  },
  "recurringOverdue": "Overdue",
  "@recurringOverdue": {
    "description": "Chip on an occurrence past its due date. Derived from the clock, never stored."
  },
  "recurringPaused": "Paused",
  "@recurringPaused": {
    "description": "Chip on a paused template."
  },
  "recurringDueToday": "Due today",
  "@recurringDueToday": {
    "description": "Chip when the next occurrence falls today."
  },
  "emptyTitleNoTemplates": "Nothing recurring yet",
  "@emptyTitleNoTemplates": {
    "description": "Template list empty state."
  },
  "emptyBodyNoTemplates": "Add a bill, a subscription or a salary and it will appear here when it is next due.",
  "@emptyBodyNoTemplates": {
    "description": "Template list empty state body."
  },
  "addTemplate": "Add",
  "@addTemplate": {
    "description": "Adds a recurring template."
  },
  "actionPause": "Pause",
  "@actionPause": {
    "description": "Pauses a template."
  },
  "actionResume": "Resume",
  "@actionResume": {
    "description": "Resumes a paused template."
  },
  "loadingRecurring": "Loading your schedule",
  "@loadingRecurring": {
    "description": "Skeleton label for recurring surfaces."
  },
  "builderSectionWhat": "What it is",
  "@builderSectionWhat": {
    "description": "First section of the template builder."
  },
  "builderSectionWhen": "How often",
  "@builderSectionWhen": {
    "description": "Frequency section of the template builder."
  },
  "builderSectionDefaults": "Defaults",
  "@builderSectionDefaults": {
    "description": "Amount and account section of the template builder."
  },
  "labelTemplateName": "Name",
  "@labelTemplateName": {
    "description": "Template name field."
  },
  "labelRecurringKind": "Kind",
  "@labelRecurringKind": {
    "description": "Bill, subscription, rent or salary."
  },
  "labelDirection": "Direction",
  "@labelDirection": {
    "description": "Whether money goes out or comes in."
  },
  "directionOutflow": "Money out",
  "@directionOutflow": {
    "description": "RecurringDirection.outflow."
  },
  "directionInflow": "Money in",
  "@directionInflow": {
    "description": "RecurringDirection.inflow."
  },
  "kindBill": "Bill",
  "@kindBill": {
    "description": "RecurringKind.bill."
  },
  "kindSubscription": "Subscription",
  "@kindSubscription": {
    "description": "RecurringKind.subscription."
  },
  "kindRent": "Rent",
  "@kindRent": {
    "description": "RecurringKind.rent."
  },
  "kindSalary": "Salary",
  "@kindSalary": {
    "description": "RecurringKind.salary."
  },
  "labelEvery": "Every",
  "@labelEvery": {
    "description": "Precedes the interval count and unit."
  },
  "unitDay": "{count, plural, =1{day} other{days}}",
  "@unitDay": {
    "description": "RecurringIntervalUnit.day.",
    "placeholders": {
      "count": {}
    }
  },
  "unitWeek": "{count, plural, =1{week} other{weeks}}",
  "@unitWeek": {
    "description": "RecurringIntervalUnit.week.",
    "placeholders": {
      "count": {}
    }
  },
  "unitMonth": "{count, plural, =1{month} other{months}}",
  "@unitMonth": {
    "description": "RecurringIntervalUnit.month.",
    "placeholders": {
      "count": {}
    }
  },
  "unitYear": "{count, plural, =1{year} other{years}}",
  "@unitYear": {
    "description": "RecurringIntervalUnit.year.",
    "placeholders": {
      "count": {}
    }
  },
  "labelAnchorDay": "On day of the month",
  "@labelAnchorDay": {
    "description": "anchorDayOfMonth. Stored once, clamped at render (anomaly A13)."
  },
  "anchorDayHelp": "Kept as you set it. Anchored on the 31st, a short month falls on its last day and the next long month returns to the 31st.",
  "@anchorDayHelp": {
    "description": "Explains that the anchor never walks backwards."
  },
  "labelStartDate": "Starts",
  "@labelStartDate": {
    "description": "startDateKey."
  },
  "labelEndDate": "Ends",
  "@labelEndDate": {
    "description": "endDateKey, optional."
  },
  "labelDefaultAmount": "Usual amount",
  "@labelDefaultAmount": {
    "description": "defaultAmount — a default, not a fixed figure."
  },
  "labelRemindBefore": "Remind me",
  "@labelRemindBefore": {
    "description": "remindDaysBefore."
  },
  "saveTemplate": "Save",
  "@saveTemplate": {
    "description": "Commits the template."
  },
  "previewTitle": "Next three",
  "@previewTitle": {
    "description": "Header of the frequency preview."
  },
  "previewEmpty": "Set a start date to see when this lands.",
  "@previewEmpty": {
    "description": "Frequency preview with nothing to show."
  },
  "previewClamped": "Shortened to fit the month",
  "@previewClamped": {
    "description": "Marks a previewed date the anchor could not reach."
  },
  "payTitle": "Record this payment",
  "@payTitle": {
    "description": "Pay sheet title."
  },
  "payTitleInflow": "Record this receipt",
  "@payTitleInflow": {
    "description": "Pay sheet title for an inflow."
  },
  "labelActualAmount": "Amount actually paid",
  "@labelActualAmount": {
    "description": "The real figure, which may differ from the default."
  },
  "labelActualAmountInflow": "Amount actually received",
  "@labelActualAmountInflow": {
    "description": "Inflow wording for the same field."
  },
  "payUsualWas": "Usually",
  "@payUsualWas": {
    "description": "Precedes the default amount when the actual differs from it."
  },
  "labelPaidOn": "Paid on",
  "@labelPaidOn": {
    "description": "paidDateKey."
  },
  "payCommit": "Record it",
  "@payCommit": {
    "description": "Commits the payment and creates the transaction."
  },
  "payRecorded": "Recorded",
  "@payRecorded": {
    "description": "Result snack after paying."
  },
  "payNeedsAccount": "Choose which account it came from",
  "@payNeedsAccount": {
    "description": "Rejection when no account is selected."
  },
  "payUndoTitle": "Undo this payment?",
  "@payUndoTitle": {
    "description": "Confirmation before undoing."
  },
  "payUndoBody": "The obligation goes back to due and the transaction it created is deleted. Anything that transaction produced — stock, an asset — goes with it.",
  "@payUndoBody": {
    "description": "Says exactly what undo reverses, in the order it happens (ARCH_5 §5.4)."
  },
  "payUndone": "Payment undone",
  "@payUndone": {
    "description": "Result snack after undoing."
  },
  "actionSkip": "Skip this one",
  "@actionSkip": {
    "description": "Marks an occurrence deliberately skipped."
  },
  "occurrenceSkipped": "Skipped",
  "@occurrenceSkipped": {
    "description": "Chip on a skipped occurrence, and the snack after skipping."
  },
  "historyRecurringTitle": "Payment history",
  "@historyRecurringTitle": {
    "description": "Occurrence history screen title."
  },
  "historyDefaultVsActual": "Differed from the usual amount",
  "@historyDefaultVsActual": {
    "description": "Badge when paidAmount != defaultAmount."
  },
  "emptyTitleNoOccurrences": "Nothing due yet",
  "@emptyTitleNoOccurrences": {
    "description": "Occurrence history empty state."
  },
  "emptyBodyNoOccurrences": "Occurrences appear as their due dates arrive. Nothing is ever paid for you.",
  "@emptyBodyNoOccurrences": {
    "description": "Empty state body, stating anomaly A14 plainly."
  },
  "statusDue": "Due",
  "@statusDue": {
    "description": "RecurringOccurrenceStatus.due."
  },
  "statusPaid": "Paid",
  "@statusPaid": {
    "description": "RecurringOccurrenceStatus.paid."
  },
  "statusDismissed": "Dismissed",
  "@statusDismissed": {
    "description": "RecurringOccurrenceStatus.dismissed."
  },
  "kindServiceFee": "Service fee",
  "@kindServiceFee": {
    "description": "RecurringKind.serviceFee — a recurring charge tied to an asset."
  },
  "kindOther": "Something else",
  "@kindOther": {
    "description": "RecurringKind.other — anything the named kinds do not cover."
  },
  "billDueSection": "Due now",
  "@billDueSection": {
    "description": "Header above the recurring bills a payment can settle."
  },
  "billSetUpAction": "Set up a recurring bill",
  "@billSetUpAction": {
    "description": "Opens the template builder from the bill form."
  },
  "billNothingDue": "Nothing is due right now.",
  "@billNothingDue": {
    "description": "Shown in the bill form when no occurrence is outstanding."
  },
  "recurringScheduleNext": "Saved. Now set how often it repeats.",
  "@recurringScheduleNext": {
    "description": "Snack after a line asked to become recurring."
  },
  "recurringNotYetDue": "Not due yet",
  "@recurringNotYetDue": {
    "description": "Chip when the next occurrence has not materialised."
  },
  "billSettlesLabel": "Settling",
  "@billSettlesLabel": {
    "description": "Precedes the recurring bill this payment will settle."
  },
  "billSettleNone": "Not a recurring bill",
  "@billSettleNone": {
    "description": "Option that leaves the payment unlinked to any template."
  },
  "billSettleHelp": "Pick one and the amount below becomes what you actually paid. Saving records it once.",
  "@billSettleHelp": {
    "description": "Explains that the editor is the single write path for a bill payment."
  },
  "billAmountBecomesPaid": "This amount is what gets recorded",
  "@billAmountBecomesPaid": {
    "description": "Helper under the amount when a bill is selected."
  },
  "billAccountAuto": "Paid from",
  "@billAccountAuto": {
    "description": "Precedes the account resolved automatically for a bill payment."
  },
  "billAccountAskOnce": "Which account does this come from? Alaya remembers it on the bill.",
  "@billAccountAskOnce": {
    "description": "Shown only when no template default, no app default and more than one account exist."
  },
  "assetGroupAppliance": "Appliances",
  "@assetGroupAppliance": {
    "description": "AssetType.appliance group header."
  },
  "assetGroupElectronics": "Electronics",
  "@assetGroupElectronics": {
    "description": "AssetType.electronics."
  },
  "assetGroupVehicle": "Vehicles",
  "@assetGroupVehicle": {
    "description": "AssetType.vehicle."
  },
  "assetGroupFurniture": "Furniture",
  "@assetGroupFurniture": {
    "description": "AssetType.furniture."
  },
  "assetGroupProperty": "Property",
  "@assetGroupProperty": {
    "description": "AssetType.property."
  },
  "assetGroupServiceProvider": "People",
  "@assetGroupServiceProvider": {
    "description": "AssetType.serviceProvider — a maid or gardener lives here, not in a second system."
  },
  "assetGroupSubscription": "Subscriptions",
  "@assetGroupSubscription": {
    "description": "AssetType.subscription."
  },
  "assetGroupOther": "Other",
  "@assetGroupOther": {
    "description": "AssetType.other."
  },
  "assetUnderWarranty": "In warranty",
  "@assetUnderWarranty": {
    "description": "Chip when warrantyEndDateKey is still ahead."
  },
  "assetWarrantyEnding": "Warranty ending",
  "@assetWarrantyEnding": {
    "description": "Chip when the warranty ends soon."
  },
  "assetWarrantyExpired": "Out of warranty",
  "@assetWarrantyExpired": {
    "description": "Chip when the warranty has passed."
  },
  "assetServiceDue": "Service due",
  "@assetServiceDue": {
    "description": "Chip when nextServiceDueDateKey has passed."
  },
  "assetServiceSoon": "Service soon",
  "@assetServiceSoon": {
    "description": "Chip when a service is close."
  },
  "assetDisposedChip": "Disposed",
  "@assetDisposedChip": {
    "description": "Chip on a disposed asset."
  },
  "assetUnderRepair": "Being repaired",
  "@assetUnderRepair": {
    "description": "AssetStatus.underRepair."
  },
  "filterShowDisposed": "Include disposed",
  "@filterShowDisposed": {
    "description": "Filter that brings disposed assets back into the list."
  },
  "emptyTitleNoAssets": "Nothing tracked yet",
  "@emptyTitleNoAssets": {
    "description": "Asset list empty state."
  },
  "emptyBodyNoAssets": "Add an appliance, a vehicle, or the person who helps around the house — they all live here.",
  "@emptyBodyNoAssets": {
    "description": "Asset list empty state body, stating the serviceProvider case plainly."
  },
  "addAsset": "Add",
  "@addAsset": {
    "description": "Adds an asset."
  },
  "loadingAssets": "Loading your things",
  "@loadingAssets": {
    "description": "Skeleton label for service surfaces."
  },
  "assetSectionIdentity": "Details",
  "@assetSectionIdentity": {
    "description": "Identity section on the detail screen."
  },
  "assetSectionWarranty": "Warranty",
  "@assetSectionWarranty": {
    "description": "Warranty section."
  },
  "assetSectionContact": "Contact",
  "@assetSectionContact": {
    "description": "Contact block."
  },
  "assetSectionService": "Service history",
  "@assetSectionService": {
    "description": "Service records section."
  },
  "assetSectionSalary": "Salary history",
  "@assetSectionSalary": {
    "description": "Service records section for a serviceProvider."
  },
  "assetLifetimeCost": "Spent on service so far",
  "@assetLifetimeCost": {
    "description": "Sum of every service record cost."
  },
  "assetLifetimeSalary": "Paid so far",
  "@assetLifetimeSalary": {
    "description": "The same figure for a serviceProvider."
  },
  "labelBrand": "Brand",
  "@labelBrand": {
    "description": "assets.brand."
  },
  "labelModelNo": "Model",
  "@labelModelNo": {
    "description": "assets.modelNo."
  },
  "labelSerialNo": "Serial",
  "@labelSerialNo": {
    "description": "assets.serialNo."
  },
  "labelPurchasePrice": "Bought for",
  "@labelPurchasePrice": {
    "description": "assets.purchasePrice."
  },
  "labelWarrantyStart": "Warranty from",
  "@labelWarrantyStart": {
    "description": "assets.warrantyStartDateKey."
  },
  "labelWarrantyEnd": "Warranty until",
  "@labelWarrantyEnd": {
    "description": "assets.warrantyEndDateKey."
  },
  "labelWarrantyProvider": "Covered by",
  "@labelWarrantyProvider": {
    "description": "assets.warrantyProvider."
  },
  "labelServiceInterval": "Service every",
  "@labelServiceInterval": {
    "description": "assets.serviceIntervalDays."
  },
  "labelNextService": "Next service",
  "@labelNextService": {
    "description": "assets.nextServiceDueDateKey."
  },
  "labelContactName": "Name",
  "@labelContactName": {
    "description": "assets.primaryContactName."
  },
  "labelContactPhone": "Phone",
  "@labelContactPhone": {
    "description": "assets.primaryContactPhone."
  },
  "labelLocation": "Kept in",
  "@labelLocation": {
    "description": "assets.location."
  },
  "actionCall": "Call",
  "@actionCall": {
    "description": "Dials primaryContactPhone."
  },
  "callFailed": "No app on this phone can place that call.",
  "@callFailed": {
    "description": "Shown when the tel: intent finds no handler."
  },
  "actionAddService": "Record a service",
  "@actionAddService": {
    "description": "Adds a service record."
  },
  "actionAddSalary": "Record a payment",
  "@actionAddSalary": {
    "description": "The same action for a serviceProvider."
  },
  "actionDispose": "Dispose of it",
  "@actionDispose": {
    "description": "Opens the dispose sheet."
  },
  "actionUndispose": "Bring it back",
  "@actionUndispose": {
    "description": "Reverses a disposal."
  },
  "assetLinkedRecurring": "Paid on a schedule",
  "@assetLinkedRecurring": {
    "description": "Chip when linkedRecurringTemplateId is set."
  },
  "emptyBodyNoServices": "Nothing recorded against this yet.",
  "@emptyBodyNoServices": {
    "description": "Empty service history."
  },
  "labelAssetName": "What is it?",
  "@labelAssetName": {
    "description": "assets.name."
  },
  "labelAssetType": "Kind",
  "@labelAssetType": {
    "description": "assets.type."
  },
  "assetTypeHelpPerson": "A person you pay regularly belongs here too — their payments become service records.",
  "@assetTypeHelpPerson": {
    "description": "Explains AssetType.serviceProvider when it is chosen."
  },
  "saveAsset": "Save",
  "@saveAsset": {
    "description": "Commits an asset."
  },
  "serviceIntervalHelp": "Days between services. The next due date moves on each time you record one.",
  "@serviceIntervalHelp": {
    "description": "Explains serviceIntervalDays."
  },
  "labelServiceType": "What happened",
  "@labelServiceType": {
    "description": "service_records.type."
  },
  "serviceTypeService": "Serviced",
  "@serviceTypeService": {
    "description": "ServiceRecordType.service."
  },
  "serviceTypeRepair": "Repaired",
  "@serviceTypeRepair": {
    "description": "ServiceRecordType.repair."
  },
  "serviceTypeMaintenance": "Maintenance",
  "@serviceTypeMaintenance": {
    "description": "ServiceRecordType.maintenance."
  },
  "serviceTypeInspection": "Inspection",
  "@serviceTypeInspection": {
    "description": "ServiceRecordType.inspection."
  },
  "serviceTypeSalaryPaid": "Salary paid",
  "@serviceTypeSalaryPaid": {
    "description": "ServiceRecordType.salaryPaid — the maid case."
  },
  "serviceTypeOther": "Something else",
  "@serviceTypeOther": {
    "description": "ServiceRecordType.other."
  },
  "labelProviderName": "Who did it",
  "@labelProviderName": {
    "description": "service_records.providerName."
  },
  "labelProviderPhone": "Their number",
  "@labelProviderPhone": {
    "description": "service_records.providerPhone."
  },
  "labelServiceDate": "When",
  "@labelServiceDate": {
    "description": "service_records.serviceDateKey."
  },
  "labelServiceCost": "Cost",
  "@labelServiceCost": {
    "description": "service_records.cost."
  },
  "labelNextDue": "Next one due",
  "@labelNextDue": {
    "description": "service_records.nextDueDateKey."
  },
  "alsoRecordAsExpense": "Also record it as an expense",
  "@alsoRecordAsExpense": {
    "description": "The alsoRecordAsExpense toggle."
  },
  "alsoRecordHelp": "Writes a withdrawal for the cost as well, so it shows in your ledger.",
  "@alsoRecordHelp": {
    "description": "Explains what the toggle writes."
  },
  "alsoRecordNeedsAccount": "Choose which account it comes from",
  "@alsoRecordNeedsAccount": {
    "description": "Rejection when the toggle is on with no account."
  },
  "alsoRecordNeedsCost": "Add a cost first",
  "@alsoRecordNeedsCost": {
    "description": "Rejection when the toggle is on with no cost."
  },
  "saveService": "Save",
  "@saveService": {
    "description": "Commits a service record."
  },
  "disposeTitle": "What happened to it?",
  "@disposeTitle": {
    "description": "Dispose sheet title."
  },
  "disposeBody": "It stays in your records either way — what you spent on it still counts. This just stops it appearing as something you own.",
  "@disposeBody": {
    "description": "States anomaly A30 plainly: an asset is never deleted."
  },
  "disposeReasonSold": "Sold it",
  "@disposeReasonSold": {
    "description": "AssetDisposalReason.sold."
  },
  "disposeReasonExpired": "Wore out",
  "@disposeReasonExpired": {
    "description": "AssetDisposalReason.expired."
  },
  "disposeReasonDamaged": "Broke",
  "@disposeReasonDamaged": {
    "description": "AssetDisposalReason.damaged."
  },
  "disposeReasonGifted": "Gave it away",
  "@disposeReasonGifted": {
    "description": "AssetDisposalReason.gifted."
  },
  "disposeReasonLost": "Lost it",
  "@disposeReasonLost": {
    "description": "AssetDisposalReason.lost."
  },
  "disposeReasonReplaced": "Replaced it",
  "@disposeReasonReplaced": {
    "description": "AssetDisposalReason.replaced."
  },
  "disposeReasonOther": "Something else",
  "@disposeReasonOther": {
    "description": "AssetDisposalReason.other."
  },
  "labelDisposalAmount": "Got back",
  "@labelDisposalAmount": {
    "description": "assets.disposalAmount — what the disposal recovered."
  },
  "labelDisposalDate": "When",
  "@labelDisposalDate": {
    "description": "assets.disposedAtDateKey."
  },
  "disposeCommit": "Record it",
  "@disposeCommit": {
    "description": "Commits the disposal."
  },
  "disposeDone": "Recorded",
  "@disposeDone": {
    "description": "Snack after disposing."
  },
  "undisposeDone": "Back in your list",
  "@undisposeDone": {
    "description": "Snack after un-disposing."
  },
  "disposeNeedsReason": "Pick what happened",
  "@disposeNeedsReason": {
    "description": "Rejection when no reason is chosen."
  },
  "hintSearchAssets": "Search your things and people",
  "@hintSearchAssets": {
    "description": "Search hint on the asset list."
  },
  "errorWarrantyBackwards": "The warranty cannot end before it starts",
  "@errorWarrantyBackwards": {
    "description": "Field error when warrantyEndDateKey precedes warrantyStartDateKey."
  },
  "sectionMoney": "Money",
  "@sectionMoney": {
    "description": "Header above the cost and expense controls on the service editor."
  },
  "assetCreatedFromPurchase": "Saved. Now say what it is and how long it is covered.",
  "@assetCreatedFromPurchase": {
    "description": "Snack after a purchase line created an asset."
  },
  "destinationHelpNone": "Recorded as spending and nothing else.",
  "@destinationHelpNone": {
    "description": "Explains destination none."
  },
  "destinationHelpInventory": "Groceries, refills, anything measured and consumed. Needs an item and a quantity, and creates stock you can run down.",
  "@destinationHelpInventory": {
    "description": "Explains destination inventory."
  },
  "destinationHelpAsset": "A phone, a fridge, a chair. Creates something you own, with its own warranty and service history.",
  "@destinationHelpAsset": {
    "description": "Explains destination asset."
  },
  "destinationHelpRecurring": "Sets up a schedule so this comes back every month.",
  "@destinationHelpRecurring": {
    "description": "Explains destination recurring."
  },
  "assetSameNameNote": "You already have one called this. That is fine — this will be a separate one, with its own warranty and service history.",
  "@assetSameNameNote": {
    "description": "Informational note when an asset name repeats. Never a block: five iPhones are five assets."
  },
  "@destinationNone": {
    "description": "No artefact. Recorded as spending and nothing else."
  },
  "@destinationInventory": {
    "description": "Creates stock. Names the Inventory module, matching navInventory."
  },
  "@destinationAsset": {
    "description": "Creates an asset. Names the Services module, matching navServices."
  },
  "@destinationRecurring": {
    "description": "Hands off to the template builder. Matches navRecurring."
  },
  "actionSetWarranty": "Set the warranty",
  "@actionSetWarranty": {
    "description": "Snack action opening the asset a purchase line created."
  },
  "labelPaymentMethodOptional": "How you paid (optional)",
  "@labelPaymentMethodOptional": {
    "description": "Optional payment method on the service editor. Travels to the expense, never onto the record."
  },
  "dashboardTitle": "Home",
  "@dashboardTitle": {
    "description": "Dashboard screen title."
  },
  "fundsAvailable": "Total available funds",
  "@fundsAvailable": {
    "description": "Label above the one headline figure on the dashboard."
  },
  "fundsUnconverted": "{count, plural, =1{1 balance not converted} other{{count} balances not converted}}",
  "@fundsUnconverted": {
    "description": "Chip when BalanceService could not convert some accounts. Excluded from the headline, never summed (anomaly A34).",
    "placeholders": {
      "count": {}
    }
  },
  "fundsApproximate": "Rate is older than today",
  "@fundsApproximate": {
    "description": "Chip when the conversion used the most recent rate on or before today."
  },
  "fundsWhyExcluded": "Balances Alaya has no rate for are left out rather than guessed at.",
  "@fundsWhyExcluded": {
    "description": "Explains why the headline may be lower than the sum of every account."
  },
  "rangeLast30": "Last 30 days",
  "@rangeLast30": {
    "description": "Range label. Always stated, never implied (anomaly A33)."
  },
  "rangeMoneyIn": "In",
  "@rangeMoneyIn": {
    "description": "Deposits over the labelled range."
  },
  "rangeMoneyOut": "Out",
  "@rangeMoneyOut": {
    "description": "Withdrawals over the labelled range."
  },
  "rangeNothingYet": "Nothing yet",
  "@rangeNothingYet": {
    "description": "Shown in place of a figure when a range holds no transactions."
  },
  "rangeExcluded": "{count, plural, =1{1 left out} other{{count} left out}}",
  "@rangeExcluded": {
    "description": "Chip when transactions in a foreign currency could not be converted into the range total.",
    "placeholders": {
      "count": {}
    }
  },
  "insightUpcoming": "Coming up",
  "@insightUpcoming": {
    "description": "The calendar side of the switchable insight card."
  },
  "insightSpending": "Where it went",
  "@insightSpending": {
    "description": "The analytics side of the switchable insight card."
  },
  "insightSwitchLabel": "Show",
  "@insightSwitchLabel": {
    "description": "Semantics label for the insight card switch."
  },
  "insightNothingUpcoming": "Nothing needs attention in the next fortnight.",
  "@insightNothingUpcoming": {
    "description": "Empty state for the upcoming side."
  },
  "insightBillDue": "Bill due",
  "@insightBillDue": {
    "description": "Upcoming row for a recurring occurrence."
  },
  "insightServiceDue": "Service due",
  "@insightServiceDue": {
    "description": "Upcoming row for an asset needing service."
  },
  "insightWarrantyEnding": "Warranty ending",
  "@insightWarrantyEnding": {
    "description": "Upcoming row for an expiring warranty."
  },
  "insightBatchExpiring": "Expiring",
  "@insightBatchExpiring": {
    "description": "Upcoming row for a batch past or near its expiry."
  },
  "moduleGridTitle": "Where to next",
  "@moduleGridTitle": {
    "description": "Header above the navigation tiles."
  },
  "moduleExpenses": "{count, plural, =0{none this month} =1{1 this month} other{{count} this month}}",
  "@moduleExpenses": {
    "description": "Live number on the Expenses tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleInventory": "{count, plural, =0{nothing tracked} =1{1 running low} other{{count} running low}}",
  "@moduleInventory": {
    "description": "Live number on the Inventory tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleShopping": "{count, plural, =0{list is clear} =1{1 to buy} other{{count} to buy}}",
  "@moduleShopping": {
    "description": "Live number on the Shopping tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleRecurring": "{count, plural, =0{all settled} =1{1 due} other{{count} due}}",
  "@moduleRecurring": {
    "description": "Live number on the Recurring tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleServices": "{count, plural, =0{nothing needs doing} =1{1 needs attention} other{{count} need attention}}",
  "@moduleServices": {
    "description": "Live number on the Services tile.",
    "placeholders": {
      "count": {}
    }
  },
  "fabAddIncome": "Money in",
  "@fabAddIncome": {
    "description": "FAB action opening the editor as a deposit."
  },
  "fabAddItem": "New item",
  "@fabAddItem": {
    "description": "FAB action opening the item editor."
  },
  "loadingDashboard": "Adding it up",
  "@loadingDashboard": {
    "description": "Skeleton label for the dashboard."
  },
  "fabOpenLabel": "Add something",
  "@fabOpenLabel": {
    "description": "Semantics label for the closed expandable FAB."
  },
  "fabCloseLabel": "Close",
  "@fabCloseLabel": {
    "description": "Semantics label for the open expandable FAB."
  },
  "eventTypeTransaction": "Transaction",
  "eventTypeRecurringDue": "Recurring bill",
  "eventTypeBatchExpiry": "Expiring",
  "eventTypeWarrantyEnd": "Warranty ending",
  "eventTypeServiceDue": "Service due",
  "eventTypeShoppingTarget": "Shopping target",
  "calendarSeverityWarning": "Needs attention",
  "calendarSeverityDanger": "Past its date",
  "calendarLoadingDay": "Loading this day…",
  "calendarDayErrorTitle": "Could not load this day",
  "calendarDayEmptyTitle": "Nothing on this day",
  "calendarDayEmptyBody": "No transactions, bills, expiries or services fall here.",
  "calendarRetry": "Try again",
  "calendarLoadingMonth": "Loading this month…",
  "calendarErrorTitle": "Could not load the calendar",
  "calendarPreviousMonth": "Previous month",
  "calendarNextMonth": "Next month",
  "calendarOnDay": "On this day",
  "calendarRangeOn": "Select a range",
  "calendarRangeOff": "Stop selecting a range",
  "calendarRangePickEnd": "From {start} — tap another day to finish.",
  "calendarInRange": "{count, plural, =1{1 day} other{{count} days}}",
  "calendarRangeEmptyTitle": "Nothing in these days",
  "calendarRangeEmptyBody": "No transactions, bills, expiries or services fall inside the range.",
  "@calendarRangePickEnd": {
    "description": "Prompt after the range start is chosen.",
    "placeholders": {
      "start": {
        "type": "String"
      }
    }
  },
  "@calendarInRange": {
    "description": "How many days the chosen range spans.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "calendarBackToToday": "Back to this month",
  "calendarTotalOut": "Spent",
  "calendarTotalIn": "Received",
  "dashboardOpenCalendar": "Open calendar",
  "dashboardCalendarSemantics": "{month} at a glance. Opens the calendar.",
  "@dashboardCalendarSemantics": {
    "description": "Screen-reader label for the dashboard month card where days are too narrow to tap.",
    "placeholders": {
      "month": {
        "type": "String"
      }
    }
  },
  "navBackToDashboard": "Back to dashboard",
  "chartLoading": "Working it out\u2026",
  "@chartLoading": {
    "description": "Shown in a ChartCard while its figure computes. A line rather than a spinner: a card about to hold a chart reads as slow behind one (ARCH_5 \u00a75.2)."
  },
  "chartApproximate": "{count, plural, =1{1 figure is indicative} other{{count} figures are indicative}}",
  "@chartApproximate": {
    "description": "How many of a series' data points converted against a rate from a different day (ARCH_3 \u00a71.3). Says what it means rather than naming the rate quality.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "chartUnconverted": "{count, plural, =1{1 amount left out} other{{count} amounts left out}}",
  "@chartUnconverted": {
    "description": "How many amounts had no usable rate and are excluded from the figure, never counted as zero (anomaly A15).",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsTotalSpent": "Spent",
  "@analyticsTotalSpent": {
    "description": "Label above the analytics screen's one displayAmount."
  },
  "analyticsRangeLabel": "Reporting window",
  "@analyticsRangeLabel": {
    "description": "Semantics label for the range chip row."
  },
  "analyticsComparisonUp": "{percent} more than the window before",
  "@analyticsComparisonUp": {
    "description": "Period-over-period comparison, rising. The window compared against is the same length, not a calendar month.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsComparisonDown": "{percent} less than the window before",
  "@analyticsComparisonDown": {
    "description": "Period-over-period comparison, falling.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsUnconvertedTotal": "{count, plural, =1{1 amount needs a rate} other{{count} amounts need a rate}}",
  "@analyticsUnconvertedTotal": {
    "description": "The app-wide unconverted count, distinct from one figure's own exclusions. A transaction outside the window can still be unconvertible.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsInflationTitle": "Your own inflation",
  "@analyticsInflationTitle": {
    "description": "Title of the personal-inflation card, queries 12 and 24."
  },
  "analyticsInflationSubtitle": "What one thing costs you, purchase by purchase",
  "@analyticsInflationSubtitle": {
    "description": "Explains that the trend is per base unit, so 2 kg and 500 g are comparable."
  },
  "analyticsInflationUp": "{percent} more than the first time in this window",
  "@analyticsInflationUp": {
    "description": "The personal-inflation sentence, rising. The date is rendered separately through DateText (Law U7).",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsInflationDown": "{percent} less than the first time in this window",
  "@analyticsInflationDown": {
    "description": "The personal-inflation sentence, falling.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsInflationSince": "First bought",
  "@analyticsInflationSince": {
    "description": "Precedes a DateText giving the earliest purchase in the window."
  },
  "analyticsInflationEmpty": "Buy something twice and its price trend appears here. Widen the window if you have.",
  "@analyticsInflationEmpty": {
    "description": "Empty state: fewer than two priced purchases means there is no trend to draw. Names both ways out."
  },
  "analyticsSectionSpend": "Where it went",
  "@analyticsSectionSpend": {
    "description": "Section header over the spend breakdowns."
  },
  "analyticsSectionTime": "Over time",
  "@analyticsSectionTime": {
    "description": "Section header over the trends."
  },
  "analyticsSectionWhat": "Who and what",
  "@analyticsSectionWhat": {
    "description": "Section header over payees and items."
  },
  "analyticsSectionHome": "Your home",
  "@analyticsSectionHome": {
    "description": "Section header over stock, waste and expiry."
  },
  "analyticsSectionCommitments": "Already committed",
  "@analyticsSectionCommitments": {
    "description": "Section header over recurring commitments and assets."
  },
  "analyticsBySubtype": "By kind",
  "@analyticsBySubtype": {
    "description": "Query 1. \"Kind\" rather than \"subtype\": the schema's word is not the user's."
  },
  "analyticsByTag": "By tag",
  "@analyticsByTag": {
    "description": "Query 2."
  },
  "analyticsByTagNote": "A purchase with two tags counts in both, so these add up to more than the total",
  "@analyticsByTagNote": {
    "description": "The caveat belongs on the card: a reader comparing tag figures against the headline deserves to know why they differ."
  },
  "analyticsByMethod": "By payment method",
  "@analyticsByMethod": {
    "description": "Query 3."
  },
  "analyticsConcentration": "How concentrated",
  "@analyticsConcentration": {
    "description": "Query 22, with query 8's grocery share beneath it."
  },
  "analyticsTopShare": "{percent} of your spending sits in three kinds",
  "@analyticsTopShare": {
    "description": "Query 22's headline.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsGroceryShare": "Groceries are {percent} of it",
  "@analyticsGroceryShare": {
    "description": "Query 8, stated beneath the concentration figure.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsTagChildren": "{count, plural, =1{1 tag inside} other{{count} tags inside}}",
  "@analyticsTagChildren": {
    "description": "Marks a parent tag that can be opened. One level only, which is all the schema permits.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsTagDirect": "{tag} on its own",
  "@analyticsTagDirect": {
    "description": "The parent tag's own spending, as a sibling of its children rather than folded into them.",
    "placeholders": {
      "tag": {}
    }
  },
  "analyticsTagBack": "Back to all tags",
  "@analyticsTagBack": {
    "description": "Tooltip on the in-place drill's back button."
  },
  "analyticsNothingSpent": "Nothing spent in this window",
  "@analyticsNothingSpent": {
    "description": "Empty state for a spend breakdown."
  },
  "analyticsNoTaggedSpend": "Tag a purchase and it will appear here",
  "@analyticsNoTaggedSpend": {
    "description": "Empty state for the tag breakdown: names the action, not the absence."
  },
  "analyticsNoMethodSpend": "Record how you paid and it will appear here",
  "@analyticsNoMethodSpend": {
    "description": "Empty state for the payment-method breakdown."
  },
  "analyticsIncomeVsExpense": "In and out",
  "@analyticsIncomeVsExpense": {
    "description": "Query 5."
  },
  "analyticsNeedTwoMonths": "Two months of records and the trend appears here",
  "@analyticsNeedTwoMonths": {
    "description": "Empty state: one month is a pair of figures, not a trend."
  },
  "analyticsNetFlow": "What you kept",
  "@analyticsNetFlow": {
    "description": "Query 6. Named for what the figure means rather than for the ledger it comes from."
  },
  "analyticsNetFlowNote": "Moving money between your own accounts does not count",
  "@analyticsNetFlowNote": {
    "description": "Explains why a transfer is absent: the ledger nets it to zero across its two legs."
  },
  "analyticsNoFlow": "Nothing moved in this window",
  "@analyticsNoFlow": {
    "description": "Empty state for net flow."
  },
  "analyticsBalanceTrend": "Balance over time",
  "@analyticsBalanceTrend": {
    "description": "Query 7."
  },
  "analyticsBalanceIn": "{account}, in {currency}",
  "@analyticsBalanceIn": {
    "description": "Names the account and its currency: this is the one figure on the screen not in the home currency, because converting each point would make the line move when rates moved.",
    "placeholders": {
      "account": {},
      "currency": {}
    }
  },
  "analyticsAccount": "Account",
  "@analyticsAccount": {
    "description": "Label on the balance-trend account picker."
  },
  "analyticsNoBalanceMovement": "No movement on this account in this window",
  "@analyticsNoBalanceMovement": {
    "description": "Empty state for the balance trend."
  },
  "analyticsHeatmap": "When you spend",
  "@analyticsHeatmap": {
    "description": "Query 21."
  },
  "analyticsByWeekday": "By day of week",
  "@analyticsByWeekday": {
    "description": "Heatmap segment."
  },
  "analyticsByDayOfMonth": "By date",
  "@analyticsByDayOfMonth": {
    "description": "Heatmap segment."
  },
  "analyticsTopPayees": "Who you paid most",
  "@analyticsTopPayees": {
    "description": "Query 4."
  },
  "analyticsNoPayees": "Name who you paid and they will appear here",
  "@analyticsNoPayees": {
    "description": "Empty state for top payees."
  },
  "analyticsTopItems": "What cost you most",
  "@analyticsTopItems": {
    "description": "Query 9."
  },
  "analyticsNoItemisedSpend": "Itemise a purchase and it will appear here",
  "@analyticsNoItemisedSpend": {
    "description": "Empty state for top items by spend."
  },
  "analyticsTopByQuantity": "What you buy most of",
  "@analyticsTopByQuantity": {
    "description": "Query 10."
  },
  "analyticsTopByQuantityNote": "Grouped by measure, because weight and count cannot be compared",
  "@analyticsTopByQuantityNote": {
    "description": "Explains the grouping: Law L8 makes cross-category comparison meaningless."
  },
  "analyticsNoQuantities": "Record how much you bought and it will appear here",
  "@analyticsNoQuantities": {
    "description": "Empty state for top items by quantity."
  },
  "analyticsPurchaseCount": "{count, plural, =1{1 purchase} other{{count} purchases}}",
  "@analyticsPurchaseCount": {
    "description": "How many times an item was bought in the window.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsDearest": "The most you have paid",
  "@analyticsDearest": {
    "description": "Query 11."
  },
  "analyticsDearestItem": "Item",
  "@analyticsDearestItem": {
    "description": "Key on the dearest-purchase card."
  },
  "analyticsDearestPrice": "Unit price",
  "@analyticsDearestPrice": {
    "description": "Key on the dearest-purchase card. The figure is in the currency it was bought in, unconverted."
  },
  "analyticsDearestWhen": "When",
  "@analyticsDearestWhen": {
    "description": "Key on the dearest-purchase card, paired with a DateText."
  },
  "analyticsNoUnitPrices": "Record a unit price and this appears here",
  "@analyticsNoUnitPrices": {
    "description": "Empty state for the dearest purchase."
  },
  "analyticsAverageBasket": "Your average shop",
  "@analyticsAverageBasket": {
    "description": "Query 23."
  },
  "analyticsBasketValue": "Average value",
  "@analyticsBasketValue": {
    "description": "Key on the basket card."
  },
  "analyticsBasketLines": "Average items",
  "@analyticsBasketLines": {
    "description": "Key on the basket card."
  },
  "analyticsBasketCount": "Shops counted",
  "@analyticsBasketCount": {
    "description": "Key on the basket card. Counts the baskets that converted, which is what the average divides by."
  },
  "analyticsNoBaskets": "Record a grocery shop and it will appear here",
  "@analyticsNoBaskets": {
    "description": "Empty state for the basket card."
  },
  "analyticsInventoryValue": "What is on your shelves",
  "@analyticsInventoryValue": {
    "description": "Query 13."
  },
  "analyticsInventoryValueNote": "Right now, whatever window you have chosen",
  "@analyticsInventoryValueNote": {
    "description": "Explains why the range chip does not change this figure."
  },
  "analyticsBatchesValued": "{count, plural, =1{1 batch valued} other{{count} batches valued}}",
  "@analyticsBatchesValued": {
    "description": "How many batches had both a cost and a resolvable purchase unit.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsBatchesNoCost": "{count, plural, =1{1 batch has no cost} other{{count} batches have no cost}}",
  "@analyticsBatchesNoCost": {
    "description": "Uncosted stock, reported rather than omitted: a valuation that skipped it would look complete while understating the shelf.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsNoStockValue": "Record what a batch cost and its value appears here",
  "@analyticsNoStockValue": {
    "description": "Empty state for the inventory valuation."
  },
  "analyticsWaste": "What you threw away",
  "@analyticsWaste": {
    "description": "Query 14, one of the app's differentiating insights."
  },
  "analyticsNoWaste": "Nothing wasted in this window",
  "@analyticsNoWaste": {
    "description": "Empty state, and it is good news: worded as a fact rather than as missing data."
  },
  "analyticsExpiring": "Expiring within {days} days",
  "@analyticsExpiring": {
    "description": "Query 15.",
    "placeholders": {
      "days": {
        "type": "int"
      }
    }
  },
  "analyticsNothingExpiring": "Nothing expires soon",
  "@analyticsNothingExpiring": {
    "description": "Empty state for the expiry card."
  },
  "analyticsDaysLeft": "{days, plural, =1{1 day left} other{{days} days left}}",
  "@analyticsDaysLeft": {
    "description": "How long a batch has. Paired with a tone, because colour is never the only signal (Law U17).",
    "placeholders": {
      "days": {
        "type": "num"
      }
    }
  },
  "analyticsExpiredAlready": "Past its date",
  "@analyticsExpiredAlready": {
    "description": "Chip on a batch whose expiry has passed and still holds stock."
  },
  "analyticsLowStock": "Running low",
  "@analyticsLowStock": {
    "description": "Query 16."
  },
  "analyticsLowStockNote": "A count for today, not a history: stock levels are not kept over time",
  "@analyticsLowStockNote": {
    "description": "Explains why this is one figure rather than a trend."
  },
  "analyticsLowStockCount": "{count, plural, =1{1 item below its threshold} other{{count} items below their threshold}}",
  "@analyticsLowStockCount": {
    "description": "Query 16's figure.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsAsOf": "As of",
  "@analyticsAsOf": {
    "description": "Precedes a DateText on the low-stock count."
  },
  "analyticsNothingLow": "Nothing is running low",
  "@analyticsNothingLow": {
    "description": "Empty state for the low-stock card."
  },
  "analyticsCommitment": "Every month, before anything else",
  "@analyticsCommitment": {
    "description": "Query 17."
  },
  "analyticsCommitmentNote": "Bills and subscriptions only. Income is not netted off",
  "@analyticsCommitmentNote": {
    "description": "Explains the outflow-only filter: netting salary against rent would report a household as having no fixed costs."
  },
  "analyticsCommitmentCount": "{count, plural, =1{from 1 commitment} other{from {count} commitments}}",
  "@analyticsCommitmentCount": {
    "description": "How many active templates the monthly figure covers.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsNoCommitments": "Add a bill or subscription and it will appear here",
  "@analyticsNoCommitments": {
    "description": "Empty state for the commitment total."
  },
  "analyticsRecurringSplit": "Fixed against chosen",
  "@analyticsRecurringSplit": {
    "description": "Query 18."
  },
  "analyticsRecurring": "Fixed",
  "@analyticsRecurring": {
    "description": "Query 18's recurring side. The user's word, not the schema's."
  },
  "analyticsDiscretionary": "Chosen",
  "@analyticsDiscretionary": {
    "description": "Query 18's discretionary side."
  },
  "analyticsRecurringShare": "{percent} of your spending was already committed",
  "@analyticsRecurringShare": {
    "description": "Query 18's headline.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsServiceCost": "What your things cost to keep",
  "@analyticsServiceCost": {
    "description": "Query 19. Includes disposed assets, which is the point of a status change rather than a delete."
  },
  "analyticsServiceCount": "{count, plural, =1{1 visit} other{{count} visits}}",
  "@analyticsServiceCount": {
    "description": "How many service records an asset has in the window.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsNoServiceCost": "Record a service or repair and it will appear here",
  "@analyticsNoServiceCost": {
    "description": "Empty state for the service-cost card."
  },
  "analyticsWarranty": "Warranties",
  "@analyticsWarranty": {
    "description": "Query 20."
  },
  "analyticsCovered": "Covered",
  "@analyticsCovered": {
    "description": "Chip on an asset still inside its warranty window."
  },
  "analyticsCoverageEnded": "Cover ended",
  "@analyticsCoverageEnded": {
    "description": "Chip on an asset whose warranty has run out."
  },
  "analyticsNoWarranties": "Add a warranty date and it will appear here",
  "@analyticsNoWarranties": {
    "description": "Empty state for the warranty card."
  },
  "analyticsEmptyTitle": "Nothing to show for this window",
  "@analyticsEmptyTitle": {
    "description": "Screen-level empty state. The house section stays visible beneath it, because stock is a \"right now\" figure."
  },
  "analyticsEmptyBody": "Widen the window above, or record something and it will appear here.",
  "@analyticsEmptyBody": {
    "description": "Names both ways out: on a fresh install the second is the answer, on a quiet month the first is."
  },
  "analyticsCacheClear": "Recalculate everything",
  "@analyticsCacheClear": {
    "description": "The clear-cache action, named for what the reader gets rather than for the table it empties."
  },
  "analyticsCacheClearing": "Recalculating\u2026",
  "@analyticsCacheClearing": {
    "description": "The action's in-progress label."
  },
  "analyticsCacheExplain": "Some figures are kept between visits so this screen opens quickly. Clear them if a number looks stale.",
  "@analyticsCacheExplain": {
    "description": "Explains what the action does. The only place analytics_cache is ever visible (ARCH_5 \u00a77.3)."
  },
  "analyticsCacheCleared": "Recalculated",
  "@analyticsCacheCleared": {
    "description": "Precedes a DateText giving when the cache was last cleared."
  },
  "analyticsCacheClearedSnack": "Figures recalculated",
  "@analyticsCacheClearedSnack": {
    "description": "Success snack. Same word as the button, per ARCH_5 \u00a72.8."
  },
  "analyticsCacheFailed": "Could not clear the saved figures",
  "@analyticsCacheFailed": {
    "description": "Failure snack. Names what failed rather than apologising."
  },
  "analyticsDrillTitle": "Behind this figure",
  "@analyticsDrillTitle": {
    "description": "Fallback title for the drill-down while its label resolves."
  },
  "analyticsDrillTotal": "These come to",
  "@analyticsDrillTotal": {
    "description": "Precedes the drill-down's per-currency subtotals."
  },
  "analyticsDrillLoading": "Loading these transactions\u2026",
  "@analyticsDrillLoading": {
    "description": "Semantics label on the drill-down's skeleton."
  },
  "analyticsDrillEmptyTitle": "Nothing here in this window",
  "@analyticsDrillEmptyTitle": {
    "description": "Drill-down empty state."
  },
  "analyticsDrillEmptyBody": "The window is set on the insights screen. Widen it and these may appear.",
  "@analyticsDrillEmptyBody": {
    "description": "Names the likely cause: the filter is what the reader just chose, the window is what they may have forgotten."
  },
  "analyticsDrillUnknownTitle": "This link does not point anywhere",
  "@analyticsDrillUnknownTitle": {
    "description": "Shown when the route's parameters name no filter this version knows."
  },
  "analyticsDrillUnknownBody": "Open insights and choose a figure to look behind.",
  "analyticsOtherSlices": "Everything else",
  "@analyticsOtherSlices": {
    "description": "The grouped remainder wedge of a donut, past the sixth slice. A ring of twelve slivers is not readable, so the tail becomes one wedge that says what it is."
  },
  "analyticsTopThree": "in three kinds",
  "@analyticsTopThree": {
    "description": "The quiet line under the percentage in the concentration donut's centre, saying what that percentage is of."
  },
  "@analyticsDrillUnknownBody": {
    "description": "Offers the way on rather than throwing: the route is reachable from outside the app."
  }
}
```

## Tests

The adapter's test runs against **real SQLite in memory, not a fake**, because every defect it exists to
catch lives in the SQL: a unit factor that is joined or not, a reversed movement excluded or not, a
`strftime` expression that maps Sunday to 7 or to 0. A fake would have agreed with whatever the adapter
did — which is how ARCH_4 R18 survived a written audit.

Two API errors surfaced while writing it, both the kind R22 is about: `FixedClock` has no `const`
constructor, and the destination enum is `TransactionLineDestination` rather than the `LineDestination`
I first wrote.

### `test/data/analytics_port_impl_test.dart`

```dart
// Per ARCH_1 §7.6: drift is imported with an explicit `show` clause, never bare alongside
// `flutter_test`. Both declare `isNull`/`isNotNull`, and a bare import makes the collision surface at
// `expect(x, isNull)` with an error that says nothing about the import.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/analytics_port_impl.dart';

/// `AnalyticsPortImpl` against real SQLite.
///
/// **Not against a fake, and that is the point.** Every defect this file exists to catch lives in the
/// SQL: a unit factor that is joined or not, a reversed movement that is excluded or not, a `strftime`
/// expression that maps Sunday to 7 or to 0. A fake would have agreed with whatever the adapter did.
void main() {
  late AlayaDatabase db;
  late AnalyticsPortImpl port;

  // A Monday, verified against the calendar rather than assumed — the weekday-bucket test is
  // meaningless if the anchor's own weekday is guessed.
  const monday = DateKey(20260810);
  const sunday = DateKey(20260816);
  const window = (from: DateKey(20260801), to: DateKey(20260831));
  const stamp = 1786000000000;

  setUp(() async {
    db = AlayaDatabase(NativeDatabase.memory());
    port = AnalyticsPortImpl(db, FixedClock(DateTime.utc(2026, 8, 10)));

    // Foreign keys are enforced from `beforeOpen` (Phase 1C), so referenced rows come first.
    for (final currency in [
      ('INR', '₹', 2),
      ('JPY', '¥', 0),
    ]) {
      await db.into(db.currencies).insert(
            CurrenciesCompanion.insert(
              code: currency.$1,
              name: currency.$1,
              symbol: currency.$2,
              decimalDigits: currency.$3,
              isEnabled: true,
              sortOrder: 0,
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
    }
    // `factorToBaseMilli` is the base unit times 1000 (ARCH_1 §4.2): a gram is 1,000 and a kilogram is
    // 1,000,000. Those two numbers are the whole of ARCH_4 R18.
    for (final unit in [
      ('g', UnitCategory.weight, 1000),
      ('kg', UnitCategory.weight, 1000000),
      ('pc', UnitCategory.count, 1000),
    ]) {
      await db.into(db.units).insert(
            UnitsCompanion.insert(
              code: unit.$1,
              category: unit.$2,
              factorToBaseMilli: unit.$3,
              displayName: unit.$1,
              isSystem: true,
              sortOrder: 0,
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
    }
    for (final account in [('ac-1', 'INR'), ('ac-2', 'INR')]) {
      await db.into(db.accounts).insert(
            AccountsCompanion.insert(
              id: account.$1,
              name: account.$1,
              normalizedName: account.$1,
              kind: AccountKind.bank,
              currencyCode: account.$2,
              openingBalanceMinor: 100000,
              openingBalanceDateKey: const DateKey(20260101),
              isArchived: false,
              includeInNetWorth: true,
              sortOrder: 0,
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
    }
    await db.into(db.items).insert(
          ItemsCompanion.insert(
            id: 'it-1',
            name: 'Potatoes',
            normalizedName: 'potatoes',
            unitCategory: UnitCategory.weight,
            defaultDisplayUnitCode: 'kg',
            itemKind: ItemKind.food,
            isFavorite: false,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
  });

  tearDown(() => db.close());

  Future<void> insertWithdrawal({
    required String id,
    required int minor,
    String currencyCode = 'INR',
    DateKey on = monday,
    TransactionSubtype subtype = TransactionSubtype.grocery,
    String? recurringTemplateId,
  }) {
    return db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            kind: TransactionKind.withdrawal,
            subtype: subtype,
            occurredAt: stamp,
            dateKey: on,
            monthKey: on.monthKey,
            originalAmountMinor: minor,
            originalCurrencyCode: currencyCode,
            needsReview: false,
            createdAt: stamp,
            updatedAt: stamp,
            // The shape CHECK on `transactions` requires a withdrawal to name `from_account_id` and
            // leave `to_account_id` null. The generated companion says what is NOT NULL; it does not
            // say what the table considers coherent.
            fromAccountId: const Value('ac-1'),
            recurringTemplateId: Value(recurringTemplateId),
          ),
        );
  }

  Future<void> insertBatch({
    required String id,
    required int remainingMilli,
    required String unitCode,
    int? unitCostMinor,
    String? costCurrencyCode,
    bool deleted = false,
  }) {
    return db.into(db.inventoryBatches).insert(
          InventoryBatchesCompanion.insert(
            id: id,
            itemId: 'it-1',
            initialQuantityMilli: remainingMilli,
            remainingQuantityMilli: remainingMilli,
            unitCodeAtPurchase: unitCode,
            purchasedDateKey: monday,
            origin: BatchOrigin.purchase,
            createdAt: stamp,
            updatedAt: stamp,
            unitCostMinor: Value(unitCostMinor),
            costCurrencyCode: Value(costCurrencyCode),
            deletedAt: Value(deleted ? stamp : null),
          ),
        );
  }

  group('query 13 — the R18 arithmetic', () {
    test('a 2 kg batch at ₹50 per kg is worth ₹100, not ₹100,000', () async {
      await insertBatch(
        id: 'ba-kg',
        // 2 kg, in base-milli: 2 x 1000 g x 1000.
        remainingMilli: 2000000,
        unitCode: 'kg',
        unitCostMinor: 5000,
        costCurrencyCode: 'INR',
      );

      final rows = await port.valuedBatches();
      expect(rows, hasLength(1));
      expect(rows.single.unitFactorToBaseMilli, 1000000,
          reason: 'the kg factor must come from the units join, not from a constant');

      // The service's formula, asserted on a specific figure rather than on a shape. This is the exact
      // computation Phase 4C got wrong, and the reason a spot check could not find it: dividing by
      // 1000 instead of the factor gives 10,000,000 minor — ₹100,000 for two kilos of potatoes.
      final value = (rows.single.unitCostMinor *
              rows.single.remainingMilli /
              rows.single.unitFactorToBaseMilli)
          .truncate();
      expect(value, 10000, reason: '₹100.00 in paise');
      expect(
        (rows.single.unitCostMinor * rows.single.remainingMilli / 1000).truncate(),
        10000000,
        reason: 'the wrong formula, kept here so the difference is visible rather than argued about',
      );
    });

    test('the same batch priced per gram values identically, which is why the bug hid', () async {
      // The same 2 kg recorded in grams at **5 paise per gram** — 2000 g x 5 = 10,000 paise = ₹100,
      // the identical batch value. Dividing by 1000 is *correct* here, which is how the defect survived
      // a written audit: a spot check of this row confirms the wrong formula.
      await insertBatch(
        id: 'ba-g',
        remainingMilli: 2000000,
        unitCode: 'g',
        unitCostMinor: 5,
        costCurrencyCode: 'INR',
      );
      final row = (await port.valuedBatches()).single;
      expect(row.unitFactorToBaseMilli, 1000);
      final correct =
          (row.unitCostMinor * row.remainingMilli / row.unitFactorToBaseMilli).truncate();
      final naive = (row.unitCostMinor * row.remainingMilli / 1000).truncate();
      expect(correct, 10000);
      expect(naive, correct, reason: 'identical for a gram-denominated purchase — the trap');
    });

    test('a soft-deleted unit still values its batch', () async {
      await insertBatch(
        id: 'ba-kg',
        remainingMilli: 1000000,
        unitCode: 'kg',
        unitCostMinor: 5000,
        costCurrencyCode: 'INR',
      );
      await db.customStatement(
        'UPDATE units SET deleted_at = ? WHERE code = ?',
        [stamp, 'kg'],
      );
      // Filtering `units.deleted_at` would drop every batch bought in a retired unit from the
      // valuation while the figure still looked complete — R18's failure mode from the other side.
      expect(await port.valuedBatches(), hasLength(1));
    });

    test('valued and uncosted batches are exact complements', () async {
      await insertBatch(
        id: 'ba-priced',
        remainingMilli: 1000000,
        unitCode: 'kg',
        unitCostMinor: 5000,
        costCurrencyCode: 'INR',
      );
      await insertBatch(id: 'ba-no-cost', remainingMilli: 500000, unitCode: 'kg');
      await insertBatch(
        id: 'ba-deleted',
        remainingMilli: 500000,
        unitCode: 'kg',
        unitCostMinor: 5000,
        costCurrencyCode: 'INR',
        deleted: true,
      );

      expect(await port.valuedBatches(), hasLength(1));
      expect(await port.batchesWithoutCost(), 1,
          reason: 'the uncosted one only — the soft-deleted batch is in neither set');
    });
  });

  group('query 14 — waste', () {
    Future<void> insertMovement({
      required String id,
      required StockMovementKind kind,
      required int quantityMilli,
      String? reverses,
    }) {
      return db.into(db.stockMovements).insert(
            StockMovementsCompanion.insert(
              id: id,
              batchId: 'ba-1',
              itemId: 'it-1',
              kind: kind,
              quantityMilli: quantityMilli,
              occurredAt: stamp,
              dateKey: monday,
              createdAt: stamp,
              updatedAt: stamp,
              reversesMovementId: Value(reverses),
            ),
          );
    }

    setUp(() async {
      await insertBatch(
        id: 'ba-1',
        remainingMilli: 2000000,
        unitCode: 'kg',
        unitCostMinor: 5000,
        costCurrencyCode: 'INR',
      );
    });

    test('carries the batch cost and its purchase-unit factor', () async {
      await insertMovement(
        id: 'mv-1',
        kind: StockMovementKind.waste,
        quantityMilli: 500000,
      );
      final row = (await port.wasteMovements(window)).single;
      expect(row.unitCostMinor, 5000);
      expect(row.unitFactorToBaseMilli, 1000000);
      // Half a kilo at ₹50/kg is ₹25 — the same per-purchase-unit rule as query 13.
      expect(
        (row.unitCostMinor! * row.milliBase / row.unitFactorToBaseMilli!).truncate(),
        2500,
      );
    });

    test('a reversed waste movement is excluded', () async {
      await insertMovement(
        id: 'mv-1',
        kind: StockMovementKind.waste,
        quantityMilli: 500000,
      );
      expect(await port.wasteMovements(window), hasLength(1));

      // Undo writes a reversing row rather than deleting the original (ARCH_2 §5.3), so counting the
      // original would report waste the user already corrected.
      await insertMovement(
        id: 'mv-2',
        kind: StockMovementKind.adjustIn,
        quantityMilli: 500000,
        reverses: 'mv-1',
      );
      expect(await port.wasteMovements(window), isEmpty);
    });

    test('expired counts as waste and consume does not', () async {
      await insertMovement(
        id: 'mv-exp',
        kind: StockMovementKind.expired,
        quantityMilli: 100000,
      );
      await insertMovement(
        id: 'mv-eat',
        kind: StockMovementKind.consume,
        quantityMilli: 100000,
      );
      expect(await port.wasteMovements(window), hasLength(1));
    });
  });

  group('query 11 — the dearest purchase', () {
    Future<void> insertLine({
      required String id,
      required String transactionId,
      required String unitCode,
      required int unitPriceMinor,
    }) {
      return db.into(db.transactionLines).insert(
            TransactionLinesCompanion.insert(
              id: id,
              transactionId: transactionId,
              lineNo: 1,
              description: 'Potatoes',
              destination: TransactionLineDestination.none,
              createdAt: stamp,
              updatedAt: stamp,
              itemId: const Value('it-1'),
              unitCode: Value(unitCode),
              unitPriceMinor: Value(unitPriceMinor),
              quantityMilli: const Value(1000000),
              lineAmountMinor: const Value(5000),
            ),
          );
    }

    test('ranks by price per base unit, not by the recorded number', () async {
      await insertWithdrawal(id: 'tx-kg', minor: 5000);
      await insertWithdrawal(id: 'tx-g', minor: 100);
      // ₹50 per kilogram normalises to 5 paise per gram.
      await insertLine(
        id: 'ln-kg',
        transactionId: 'tx-kg',
        unitCode: 'kg',
        unitPriceMinor: 5000,
      );
      // ₹1 per gram normalises to 100 paise per gram — twenty times dearer, and twenty times *smaller*
      // as a recorded figure. Ordering by `unit_price_minor` alone picks the kilogram line.
      await insertLine(
        id: 'ln-g',
        transactionId: 'tx-g',
        unitCode: 'g',
        unitPriceMinor: 100,
      );

      final row = await port.dearestPurchase('it-1', window);
      expect(row!.transactionId, 'tx-g');
      expect(row.unitPriceMinor, 100,
          reason: 'the figure returned is the recorded one, in the unit it was bought in');
    });
  });

  group('currency is never summed away', () {
    test('spend by subtype groups by currency', () async {
      await insertWithdrawal(id: 'tx-inr', minor: 100000);
      await insertWithdrawal(id: 'tx-jpy', minor: 999999, currencyCode: 'JPY');

      final rows = await port.spendBySubtype(window);
      expect(rows, hasLength(2));
      expect(rows.map((r) => r.currencyCode).toSet(), {'INR', 'JPY'});
      // A SQL-side SUM across currencies would have destroyed the information `AnalyticsService` needs
      // to convert per data point, and produced one meaningless figure of 1,099,999.
      expect(rows.every((r) => r.key == TransactionSubtype.grocery.name), isTrue);
    });

    test('a transfer nets to zero in net flow', () async {
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-move',
              kind: TransactionKind.transfer,
              subtype: TransactionSubtype.transferSelf,
              occurredAt: stamp,
              dateKey: monday,
              monthKey: monday.monthKey,
              originalAmountMinor: 250000,
              originalCurrencyCode: 'INR',
              needsReview: false,
              createdAt: stamp,
              updatedAt: stamp,
              fromAccountId: const Value('ac-1'),
              toAccountId: const Value('ac-2'),
            ),
          );

      final rows = await port.netFlowByMonth(window);
      // `v_account_ledger` expands a transfer into two signed legs, so this is zero by construction
      // rather than by the query knowing anything about transfers (ARCH_2 §12.1).
      expect(rows.fold<int>(0, (sum, r) => sum + r.amountMinor), 0);
    });
  });

  group('query 7 — the carried leg', () {
    test('a window that starts mid-history opens with the balance carried into it', () async {
      await insertWithdrawal(id: 'tx-old', minor: 30000, on: const DateKey(20260715));
      await insertWithdrawal(id: 'tx-in', minor: 10000);

      final legs = await port.ledgerLegsForAccount('ac-1', window);
      expect(legs, hasLength(2), reason: 'one carried leg plus the one inside the window');
      expect(legs.first.dateKey, window.from.value);
      expect(legs.first.amountMinor, -30000,
          reason: 'the pre-window withdrawal, condensed');
      expect(legs.first.count, 1, reason: 'how many legs the carried row stands for');
      expect(legs.last.amountMinor, -10000);
    });

    test('an account whose history starts inside the window carries nothing', () async {
      await insertWithdrawal(id: 'tx-in', minor: 10000);
      final legs = await port.ledgerLegsForAccount('ac-1', window);
      expect(legs, hasLength(1));
      expect(legs.single.dateKey, monday.value);
    });
  });

  group('query 21 — the weekday bucket', () {
    test('Monday is 1 and Sunday is 7', () async {
      await insertWithdrawal(id: 'tx-mon', minor: 10000);
      await insertWithdrawal(id: 'tx-sun', minor: 20000, on: sunday);

      final rows = await port.spendByBucket(window, byWeekday: true);
      final byBucket = {for (final row in rows) row.bucket: row.amountMinor};
      // SQLite's `strftime('%w')` returns 0 for Sunday; ARCH_3 §5.1 wants 1-7 Monday first. If the
      // `(w + 6) % 7 + 1` mapping were wrong this would put Monday on 2 and Sunday on 1.
      expect(byBucket[1], 10000);
      expect(byBucket[7], 20000);
    });

    test('day of month buckets by the date itself', () async {
      await insertWithdrawal(id: 'tx-10', minor: 10000);
      final rows = await port.spendByBucket(window, byWeekday: false);
      expect(rows.single.bucket, 10);
    });
  });

  group('query 17 — commitments', () {
    Future<void> insertTemplate({
      required String id,
      required RecurringDirection direction,
      bool isPaused = false,
      DateKey? endDateKey,
    }) {
      return db.into(db.recurringTemplates).insert(
            RecurringTemplatesCompanion.insert(
              id: id,
              name: id,
              normalizedName: id,
              kind: RecurringKind.bill,
              direction: direction,
              defaultAmountMinor: 64900,
              currencyCode: 'INR',
              intervalUnit: RecurringIntervalUnit.month,
              intervalCount: 1,
              startDateKey: const DateKey(20260101),
              nextDueDateKey: monday,
              isPaused: isPaused,
              autoRemind: false,
              remindDaysBefore: 0,
              createdAt: stamp,
              updatedAt: stamp,
              endDateKey: Value(endDateKey),
            ),
          );
    }

    test('counts active outflows and excludes paused, inflow and ended ones', () async {
      await insertTemplate(id: 'rt-live', direction: RecurringDirection.outflow);
      await insertTemplate(
        id: 'rt-paused',
        direction: RecurringDirection.outflow,
        isPaused: true,
      );
      await insertTemplate(id: 'rt-salary', direction: RecurringDirection.inflow);
      await insertTemplate(
        id: 'rt-ended',
        direction: RecurringDirection.outflow,
        endDateKey: const DateKey(20260601),
      );

      final rows = await port.activeCommitments();
      expect(rows, hasLength(1));
      expect(rows.single.defaultAmountMinor, 64900);
    });

    test('a template with two outstanding occurrences is counted once', () async {
      await insertTemplate(id: 'rt-live', direction: RecurringDirection.outflow);
      for (final due in [const DateKey(20260810), const DateKey(20260910)]) {
        await db.into(db.recurringOccurrences).insert(
              RecurringOccurrencesCompanion.insert(
                id: 'oc-${due.value}',
                templateId: 'rt-live',
                dueDateKey: due,
                status: RecurringOccurrenceStatus.due,
                createdAt: stamp,
                updatedAt: stamp,
              ),
            );
      }
      // This is why the query reads `recurring_templates` and not `v_recurring_due`: that view LEFT
      // JOINs occurrences, so this template would appear twice and its ₹649 would be counted twice.
      expect(await port.activeCommitments(), hasLength(1));
    });
  });

  group('soft deletes are respected everywhere', () {
    test('a deleted transaction leaves every money query', () async {
      await insertWithdrawal(id: 'tx-1', minor: 10000);
      expect(await port.spendBySubtype(window), hasLength(1));

      await db.customStatement(
        'UPDATE transactions SET deleted_at = ? WHERE id = ?',
        [stamp, 'tx-1'],
      );
      // Reading `v_active_transactions` rather than the base table is what makes this impossible to
      // forget (Law L7).
      expect(await port.spendBySubtype(window), isEmpty);
      expect(await port.totalSpend(window), isEmpty);
      expect(await port.spendByBucket(window, byWeekday: true), isEmpty);
    });
  });
}
```

### `test/data/seed_test.dart`

```dart
// `show` clause per ARCH_1 §7.6, and for one symbol only: `driftRuntimeOptions`. A bare drift import
// beside `flutter_test` collides on `isNull`.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/seed/seed_data.dart';

void main() {
  // **Silences drift's multiple-database warning, which this file earns honestly.** Several tests here
  // open a second `AlayaDatabase` on purpose — the non-default-home-currency case and the determinism
  // case both need a fresh, independently seeded database to compare against. Drift cannot tell that
  // apart from the mistake it is warning about, which is two databases over *one* `QueryExecutor`; each
  // of these has its own `NativeDatabase.memory()`, so there is nothing to race.
  //
  // Set here rather than suppressed globally, so a genuine double-open elsewhere still reports.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AlayaDatabase db;

  setUp(() async {
    final seed = SeedData(
      uids: SequentialUidGenerator(prefix: 'seed'),
      clock: FixedClock(DateTime(2026, 7, 28, 9)),
    );
    db = AlayaDatabase(NativeDatabase.memory(), seeder: seed.insertAll);
    // Force onCreate to run.
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() => db.close());

  group('currencies', () {
    test('five currencies with the correct decimal digits', () async {
      final rows = await db.select(db.currencies).get();
      expect(rows.map((r) => r.code).toSet(), {'INR', 'USD', 'EUR', 'JPY', 'CNY'});

      final digits = {for (final r in rows) r.code: r.decimalDigits};
      expect(digits['INR'], 2);
      expect(digits['USD'], 2);
      expect(digits['EUR'], 2);
      expect(digits['CNY'], 2);
      expect(digits['JPY'], 0, reason: 'yen has no minor unit — this is why nothing hardcodes 100');
    });

    test('all seeded currencies are enabled', () async {
      final rows = await db.select(db.currencies).get();
      expect(rows.every((r) => r.isEnabled), isTrue);
    });
  });

  group('units', () {
    test('eight units across the three fixed categories', () async {
      final rows = await db.select(db.units).get();
      expect(rows, hasLength(8));
      final byCategory = <UnitCategory, List<String>>{};
      for (final r in rows) {
        byCategory.putIfAbsent(r.category, () => []).add(r.code);
      }
      expect(byCategory[UnitCategory.weight]!.toSet(), {'mg', 'g', 'kg'});
      expect(byCategory[UnitCategory.volume]!.toSet(), {'ml', 'l'});
      expect(byCategory[UnitCategory.count]!.toSet(), {'pc', 'dozen', 'pack'});
    });

    test('factors are exact integers relative to the milli-base unit', () async {
      final rows = await db.select(db.units).get();
      final factor = {for (final r in rows) r.code: r.factorToBaseMilli};
      expect(factor['mg'], 1);
      expect(factor['g'], 1000);
      expect(factor['kg'], 1000000);
      expect(factor['ml'], 1000);
      expect(factor['l'], 1000000);
      expect(factor['pc'], 1000);
      expect(factor['dozen'], 12000, reason: 'a dozen is exactly 12 pieces');
      expect(factor['pack'], 1000);
    });

    test('every unit is a system unit', () async {
      final rows = await db.select(db.units).get();
      expect(rows.every((r) => r.isSystem), isTrue);
    });
  });

  group('payment methods', () {
    test('the five rails from ARCH_2 §14', () async {
      final rows = await db.select(db.paymentMethods).get();
      expect(rows.map((r) => r.name).toSet(),
          {'Cash', 'UPI', 'Bank Transfer', 'Card', 'Cheque'});
      expect(rows.every((r) => r.isSystem), isTrue);
    });
  });

  group('tags — the exact ARCH_2 §14 scoping matrix', () {
    test('eighteen system tags', () async {
      final rows = await db.select(db.tags).get();
      expect(rows, hasLength(18));
      expect(rows.every((r) => r.isSystem), isTrue);
    });

    test('THE SPEC TEST CASE: Kitchen is inventory + shopping only', () async {
      final kitchen =
          await (db.select(db.tags)..where((t) => t.name.equals('Kitchen'))).getSingle();

      expect(kitchen.allowedInInventory, isTrue);
      expect(kitchen.allowedInShopping, isTrue);

      expect(kitchen.allowedInDeposit, isFalse,
          reason: 'Kitchen must NOT appear in the deposit tag picker — visible on first launch');
      expect(kitchen.allowedInWithdrawal, isFalse);
      expect(kitchen.allowedInRecurring, isFalse);
      expect(kitchen.allowedInService, isFalse);
    });

    test('every row of the matrix, exactly', () async {
      // (name, deposit, withdrawal, inventory, shopping, recurring, service)
      const expected = <(String, bool, bool, bool, bool, bool, bool)>[
        ('Salary', true, false, false, false, true, false),
        ('Gift', true, true, false, false, false, false),
        ('Refund', true, false, false, false, false, false),
        ('Business', true, true, false, false, false, false),
        ('Grocery', false, true, true, true, false, false),
        ('Vegetables', false, true, true, true, false, false),
        ('Household', false, true, true, true, false, false),
        ('Kitchen', false, false, true, true, false, false),
        ('Beauty', false, true, true, true, false, false),
        ('Medicine', false, true, true, true, false, false),
        ('Electronics', false, true, true, true, false, true),
        ('Utilities', false, true, false, false, true, true),
        ('Rent', false, true, false, false, true, false),
        ('Subscription', false, true, false, false, true, true),
        ('Transport', false, true, false, false, true, false),
        ('Health', false, true, false, false, true, true),
        ('Education', false, true, false, false, true, false),
        ('Maintenance', false, true, false, false, true, true),
      ];

      final rows = await db.select(db.tags).get();
      final byName = {for (final r in rows) r.name: r};
      expect(byName.keys.toSet(), expected.map((e) => e.$1).toSet());

      for (final (name, dep, wdr, inv, shop, rec, svc) in expected) {
        final tag = byName[name]!;
        expect(
          [
            tag.allowedInDeposit,
            tag.allowedInWithdrawal,
            tag.allowedInInventory,
            tag.allowedInShopping,
            tag.allowedInRecurring,
            tag.allowedInService,
          ],
          [dep, wdr, inv, shop, rec, svc],
          reason: 'scoping mismatch for "$name"',
        );
      }
    });

    test('the deposit picker shows exactly four tags', () async {
      final rows =
          await (db.select(db.tags)..where((t) => t.allowedInDeposit.equals(true))).get();
      expect(rows.map((r) => r.name).toSet(), {'Salary', 'Gift', 'Refund', 'Business'});
    });

    test('Vegetables is nested exactly one level under Grocery', () async {
      final grocery =
          await (db.select(db.tags)..where((t) => t.name.equals('Grocery'))).getSingle();
      final vegetables =
          await (db.select(db.tags)..where((t) => t.name.equals('Vegetables'))).getSingle();

      expect(vegetables.parentTagId, grocery.id);
      expect(grocery.parentTagId, isNull, reason: 'nesting is capped at one level');

      final nested = await (db.select(db.tags)..where((t) => t.parentTagId.isNotNull())).get();
      expect(nested.map((r) => r.name), ['Vegetables']);
    });

    test('normalized names match what the Normalizer would produce', () async {
      final rows = await db.select(db.tags).get();
      for (final r in rows) {
        expect(r.normalizedName, r.name.toLowerCase());
      }
    });
  });

  group('accounts', () {
    test('Cash and Bank, zero opening balance, home currency', () async {
      final rows = await db.select(db.accounts).get();
      expect(rows.map((r) => r.name).toSet(), {'Cash', 'Bank'});
      for (final r in rows) {
        expect(r.openingBalanceMinor, 0);
        expect(r.currencyCode, 'INR');
        expect(r.isArchived, isFalse);
        expect(r.includeInNetWorth, isTrue);
      }
    });

    test('the opening balance date is the seed date, not an absent value', () async {
      final rows = await db.select(db.accounts).get();
      for (final r in rows) {
        expect(r.openingBalanceDateKey.value, 20260728);
      }
    });

    test('honours a non-default home currency', () async {
      final other = AlayaDatabase(
        NativeDatabase.memory(),
        seeder: SeedData(
          uids: SequentialUidGenerator(),
          clock: FixedClock(DateTime(2026, 7, 28)),
          homeCurrencyCode: 'JPY',
        ).insertAll,
      );
      addTearDown(other.close);
      final rows = await other.select(other.accounts).get();
      expect(rows.every((r) => r.currencyCode == 'JPY'), isTrue);
    });
  });

  group('shopping list', () {
    test('exactly one, marked default', () async {
      final rows = await db.select(db.shoppingLists).get();
      expect(rows, hasLength(1));
      expect(rows.single.isDefault, isTrue);
      expect(rows.single.isArchived, isFalse);
    });
  });

  group('app settings', () {
    test('homeCurrencyCode is stored', () async {
      final row = await (db.select(db.appSettings)
            ..where((t) => t.key.equals('homeCurrencyCode')))
          .getSingle();
      expect(row.value, 'INR');
      expect(row.valueType, 'string');
    });

    test('defaultAccountId points at a real account', () async {
      final setting = await (db.select(db.appSettings)
            ..where((t) => t.key.equals('defaultAccountId')))
          .getSingle();
      final account = await (db.select(db.accounts)
            ..where((t) => t.id.equals(setting.value)))
          .getSingle();
      expect(account.name, 'Cash',
          reason: 'accounts has no isDefault column, so the default lives in app_settings');
    });
  });

  group('determinism', () {
    test('seeding twice with the same generator and clock produces identical ids', () async {
      Future<List<String>> seedIds() async {
        final fresh = AlayaDatabase(
          NativeDatabase.memory(),
          seeder: SeedData(
            uids: SequentialUidGenerator(prefix: 'seed'),
            clock: FixedClock(DateTime(2026, 7, 28, 9)),
          ).insertAll,
        );
        addTearDown(fresh.close);
        final tags = await fresh.select(fresh.tags).get();
        return tags.map((t) => t.id).toList();
      }

      expect(await seedIds(), await seedIds());
    });
  });

  group('referential integrity', () {
    test('foreign keys are enforced after beforeOpen ran', () async {
      final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(row.data.values.first, 1,
          reason: 'SQLite defaults this OFF per connection — beforeOpen must turn it on');
    });

    test('an account referencing an unknown currency is rejected', () async {
      expect(
        () => db.customStatement(
          'INSERT INTO accounts (id, name, normalized_name, kind, currency_code, '
          'opening_balance_minor, opening_balance_date_key, is_archived, include_in_net_worth, '
          "sort_order, created_at, updated_at) VALUES ('x','X','x','cash','ZZZ',0,20260728,0,1,0,0,0)",
        ),
        throwsA(anything),
      );
    });
  });
}
```

### `test/support/analytics_harness.dart`

```dart
/// Shared scaffolding for the analytics widget tests.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/features/analytics/providers/drill_down_providers.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';

import 'fake_settings_repository.dart';

/// The narrowest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so every derived date is the same on every machine.
final Clock kAnalyticsClock = FixedClock(DateTime(2026, 8, 10, 9, 30));

/// Today, according to [kAnalyticsClock].
const DateKey kAnalyticsToday = DateKey(20260810);

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// A stream that never emits and never closes, for the loading branch of a `StreamProvider`.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

Money _inr(int minor) => Money(minor, 'INR');

/// A spend breakdown with [count] slices, largest first.
MoneySeries series({int count = 3, int approximate = 0, int unconverted = 0}) => (
      slices: [
        for (var i = 0; i < count; i++)
          (
            label: 'grocery',
            key: i == 0 ? 'grocery' : 'household',
            amount: _inr(100000 - i * 10000),
          ),
      ],
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );

/// Total spend and its top three kinds.
Concentration concentration({int total = 300000, int top = 3}) => (
      top: [
        for (var i = 0; i < top; i++)
          (
            key: 'grocery',
            label: 'grocery',
            amount: _inr(100000),
            share: 1 / (top == 0 ? 1 : top),
          ),
      ],
      topShare: top == 0 ? 0.0 : 0.9,
      total: _inr(total),
      quality: exactConversion,
    );

/// A unit-price trend with [points] observations and a [change] across them.
UnitPriceTrend trend({int points = 3, double? change = 0.34}) => (
      itemId: 'it-1',
      itemName: 'Potatoes',
      points: [
        for (var i = 0; i < points; i++)
          (
            on: DateKey(20260801 + i),
            lineAmount: _inr(5000 + i * 500),
            quantity: Qty(1000000, UnitCategory.weight),
            pricePerBaseUnit: 5.0 + i,
          ),
      ],
      percentChange: change,
    );

/// One transaction for a drill-down list.
Transaction transaction({String id = 'tx-1', int minor = 45900}) => Transaction(
      id: id,
      kind: TransactionKind.withdrawal,
      subtype: TransactionSubtype.grocery,
      occurredAtUtc: DateTime.utc(2026, 8, 10, 9),
      dateKey: kAnalyticsToday,
      originalAmount: _inr(minor),
      needsReview: false,
      fromAccountId: 'ac-1',
    );

/// Overrides every analytics provider to a settled, harmless value.
///
/// **Fixed length, always.** A conditional entry changes the override count between scopes and Riverpod
/// refuses it outright — and two `pumpWidget` calls in one test silently reuse the first scope, so a
/// varying list fails in both directions (ARCH_6 P5).
///
/// Every provider is overridden even where a test does not care, because an un-overridden repository
/// provider reaches a real database, which a widget test has no business opening (P6). The screen's
/// sections are a lazy sliver, so a narrow viewport builds only the first few cards — but an override
/// for a card that never builds costs nothing, and omitting one costs a thrown `databaseProvider`.
///
/// `analyticsRangeProvider` and `analyticsCacheControllerProvider` are `NotifierProvider`s and cannot be
/// overridden as instances (P5), so the repositories beneath them are the seam:
/// `AnalyticsRangeNotifier.build` reads settings on the first frame and would otherwise resolve
/// `databaseProvider`, which throws by design (Law L10).
List<Override> analyticsOverrides({
  AsyncValue<Concentration>? headline,
  AsyncValue<UnitPriceTrend?>? inflation,
  AsyncValue<MoneySeries>? subtypeSpend,
  AsyncValue<List<TagSpendNode>>? tagTree,
  AsyncValue<List<Transaction>>? drillRows,
  int unconverted = 0,
}) =>
    [
      clockProvider.overrideWithValue(kAnalyticsClock),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      analyticsCurrencyProvider.overrideWith((ref) async => 'INR'),
      analyticsDigitsProvider.overrideWith((ref) async => 2),
      analyticsDigitsForCurrencyProvider.overrideWith(
        (ref, code) async => code == 'JPY' ? 0 : 2,
      ),
      analyticsUnconvertedProvider.overrideWith((ref) => Stream.value(unconverted)),
      analyticsHeadlineProvider.overrideWith(
        (ref) => _future(headline ?? AsyncValue.data(concentration())),
      ),
      analyticsPreviousHeadlineProvider.overrideWith(
        (ref) => _future(AsyncValue.data(concentration(total: 250000))),
      ),
      personalInflationProvider.overrideWith(
        (ref) => _future(inflation ?? AsyncValue<UnitPriceTrend?>.data(trend())),
      ),
      spendBySubtypeProvider.overrideWith(
        (ref) => _future(subtypeSpend ?? AsyncValue.data(series())),
      ),
      spendByTagProvider.overrideWith((ref) => _future(AsyncValue.data(series()))),
      spendByPaymentMethodProvider.overrideWith((ref) => _future(AsyncValue.data(series()))),
      topPayeesProvider.overrideWith((ref) => _future(AsyncValue.data(series()))),
      groceryShareProvider.overrideWith(
        (ref) => _future(
          AsyncValue<ShareOfTotal?>.data(
            (key: 'grocery', label: 'grocery', amount: _inr(100000), share: 0.4),
          ),
        ),
      ),
      analyticsTagsByIdProvider.overrideWith(
        (ref) => Stream.value(<String, Tag>{}),
      ),
      tagSpendTreeProvider.overrideWith(
        (ref) => _future(tagTree ?? const AsyncValue.data(<TagSpendNode>[])),
      ),
      incomeVsExpenseProvider.overrideWith(
        (ref) => _future(
          AsyncValue.data((
            points: [
              (monthKey: 202607, income: _inr(500000), expense: _inr(320000)),
              (monthKey: 202608, income: _inr(500000), expense: _inr(410000)),
            ],
            quality: exactConversion,
          )),
        ),
      ),
      netCashFlowProvider.overrideWith(
        (ref) => _future(
          AsyncValue.data((
            points: [
              (monthKey: 202607, amount: _inr(180000)),
              (monthKey: 202608, amount: _inr(90000)),
            ],
            quality: exactConversion,
          )),
        ),
      ),
      analyticsAccountsProvider.overrideWith((ref) => Stream.value(<Account>[])),
      balanceTrendProvider.overrideWith(
        (ref, id) => _future(
          AsyncValue.data((accountId: id, points: const <BalancePoint>[])),
        ),
      ),
      spendHeatmapProvider.overrideWith(
        (ref, byWeekday) => _future(
          AsyncValue.data((cells: const <HeatmapCell>[], quality: exactConversion)),
        ),
      ),
      topItemsBySpendProvider.overrideWith(
        (ref) => _future(const AsyncValue.data(<ItemSpend>[])),
      ),
      topItemsByQuantityProvider.overrideWith(
        (ref) => _future(const AsyncValue.data(<ItemQuantity>[])),
      ),
      dearestPurchaseProvider.overrideWith(
        (ref, item) => _future(const AsyncValue<DearestPurchase?>.data(null)),
      ),
      unitPriceTrendProvider.overrideWith((ref, item) => _future(AsyncValue.data(trend()))),
      averageBasketProvider.overrideWith(
        (ref) => _future(
          AsyncValue.data((
            averageValue: _inr(140000),
            averageLineCount: 4.3,
            basketCount: 7,
            quality: exactConversion,
          )),
        ),
      ),
      inventoryValueProvider.overrideWith(
        (ref) => _future(
          AsyncValue.data((
            byCurrency: {'INR': _inr(320000)},
            batchesValued: 9,
            batchesNoCost: 2,
          )),
        ),
      ),
      wasteTotalsProvider.overrideWith(
        (ref) => _future(const AsyncValue.data(<ItemWasteTotal>[])),
      ),
      expiringBatchesProvider.overrideWith(
        (ref, days) => _future(const AsyncValue.data(<ExpiringBatch>[])),
      ),
      lowStockTodayProvider.overrideWith(
        (ref) => _future(AsyncValue.data((date: kAnalyticsToday, itemCount: 0))),
      ),
      monthlyCommitmentProvider.overrideWith(
        (ref) => _future(
          AsyncValue.data((total: _inr(649000), templateCount: 4, quality: exactConversion)),
        ),
      ),
      recurringSplitProvider.overrideWith(
        (ref) => _future(
          AsyncValue.data((
            recurring: _inr(649000),
            discretionary: _inr(320000),
            recurringShare: 0.67,
            quality: exactConversion,
          )),
        ),
      ),
      serviceCostByAssetProvider.overrideWith(
        (ref) => _future(const AsyncValue.data(<AssetServiceCost>[])),
      ),
      warrantyCoverageProvider.overrideWith(
        (ref) => _future(const AsyncValue.data(<WarrantyCoverage>[])),
      ),
      // The drill-down's own feed, plus the two maps its rows read from the expense feature.
      drillDownTransactionsProvider.overrideWith(
        (ref, spec) => _stream(drillRows ?? AsyncValue.data([transaction()])),
      ),
      drillDownLabelProvider.overrideWith((ref, spec) async => 'Corner Shop'),
      accountsByIdProvider.overrideWith((ref) => Stream.value(<String, Account>{})),
      payeesByIdProvider.overrideWith((ref) => Stream.value(<String, Payee>{})),
    ];

/// Turns an [AsyncValue] back into the future a `FutureProvider` override expects.
Future<T> _future<T>(AsyncValue<T> value) => value.when(
      data: Future.value,
      loading: pendingFuture<T>,
      error: (error, stack) => Future<T>.error(error, stack),
    );

/// Turns an [AsyncValue] back into the stream a `StreamProvider` override expects.
Stream<T> _stream<T>(AsyncValue<T> value) => value.when(
      data: Stream.value,
      loading: pendingStream<T>,
      error: (error, stack) => Stream<T>.error(error, stack),
    );

/// A drill-down spec for the tests to share.
const DrillDownSpec kDrillSpec =
    DrillDownSpec(kind: DrillDownKind.payee, value: 'pay-1');

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
///
/// Wrapped in a `Scaffold` by default, standing in for the drawer shell. A shell destination declares
/// no `Scaffold` of its own, and Material widgets — `ChoiceChip`, `InkWell`, `SegmentedButton` — assert
/// without a `Material` ancestor.
///
/// The text scaler goes through `MaterialApp.builder`, not a `MediaQuery` above the app:
/// `WidgetsApp` re-establishes `MediaQuery` from the view, so an override placed above it never
/// arrives (ARCH_5 §10).
Future<void> pumpAnalytics(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
  bool dark = false,
  bool wrapInShell = true,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark
            ? AlayaTheme.dark(AlayaPresets.activePreset)
            : AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        // **`MaterialApp` inserts no `Material` and no `Scaffold`.** In the app the drawer shell
        // supplies both, and `AnalyticsHomeScreen` deliberately declares neither — so a shell
        // destination pumped bare has no `Material` ancestor and every `ChoiceChip` in the range row
        // asserts. This `Scaffold` stands in for `_ShellScaffold`.
        //
        // `wrapInShell: false` for a screen that owns its own `Scaffold`, so `DrillDownScreen` is not
        // nested inside a second one.
        home: wrapInShell ? Scaffold(body: child) : child,
      ),
    ),
  );
  await tester.pump();
}
```

### `test/features/analytics/analytics_home_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/presentation/screens/analytics_home_screen.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_header.dart';
import 'package:alaya/features/analytics/presentation/widgets/inflation_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';

import '../../support/analytics_harness.dart';

/// `AnalyticsHomeScreen` — archetype F, all four states (Law U4, ARCH_5 §9.1).
void main() {
  group('the four states', () {
    testWidgets('loading shows no figure and no error', (tester) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(
          headline: const AsyncValue<Concentration>.loading(),
          inflation: const AsyncValue<UnitPriceTrend?>.loading(),
        ),
      );

      // No `AmountText` at all: a pending read must not resolve to a zero, which would read as a real
      // figure of nothing spent.
      expect(find.byType(AmountText), findsNothing);
      expect(find.byType(EmptyState), findsNothing);
    });

    testWidgets('populated shows exactly one displayAmount', (tester) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(),
      );
      await tester.pumpAndSettle();

      // **One headline, and the test asserts the count rather than its presence.** Two `display`
      // amounts is no headline at all (ARCH_5 §3 archetype F), and it is the kind of regression a
      // "finds one widget" assertion would let through.
      final display = tester
          .widgetList<AmountText>(find.byType(AmountText))
          .where((widget) => widget.size == AmountSize.display);
      expect(display, hasLength(1));
    });

    testWidgets('empty replaces the spend sections and keeps the house', (tester) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(
          headline: AsyncValue.data(concentration(total: 0, top: 0)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsOneWidget);
      // The signature card is a spend surface and goes; the house section is a "right now" figure and
      // stays, which is the whole point of splitting them.
      expect(find.byType(InflationCard), findsNothing);
    });

    testWidgets('a failed headline costs the header and nothing else', (tester) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(
          headline: AsyncValue<Concentration>.error(
            Exception('rate table unreachable'),
            StackTrace.empty,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // **The repository's own message, not a generic body** (Law U9), and the screen survives: the
      // range row and the header are both still mounted. One failing card never blanks an overview.
      expect(find.textContaining('rate table unreachable'), findsOneWidget);
      expect(find.byType(AnalyticsHeader), findsOneWidget);
    });
  });

  group('the gate', () {
    testWidgets('renders at 320x640 with a doubled text scale', (tester) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(),
        textScale: 2,
      );
      await tester.pumpAndSettle();
      // No exception is the assertion (Law U15). An overflow throws in a test binding, so reaching
      // here at all is the pass.
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders at a tripled scale, past what U15 asks for', (tester) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(),
        textScale: 3,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('every target is large enough and named', (tester) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(),
      );
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    testWidgets('adds no chrome of its own; the shell owns it', (tester) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(),
      );
      await tester.pumpAndSettle();

      // Exactly one `Scaffold` — the harness's stand-in for `_ShellScaffold` — so the screen added
      // none, and **no `AppBar`**, because `Routes.insights` is a shell destination and a bar declared
      // here would be a second one inside the shell (Law U18).
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });
}
```

### `test/features/analytics/drill_down_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/features/analytics/presentation/screens/drill_down_screen.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';

import '../../support/analytics_harness.dart';

/// `DrillDownScreen` — archetype C, all four states (Law U4, ARCH_5 §9.1).
void main() {
  group('the four states', () {
    testWidgets('loading is a skeleton, not a spinner', (tester) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(
          drillRows: const AsyncValue<List<Transaction>>.loading(),
        ),
        wrapInShell: false,
      );

      // The shape of what is arriving, in a space that is about to be a list (ARCH_5 §5.2).
      expect(find.byType(AlayaListSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('populated groups rows under a sticky day header', (tester) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(),
        wrapInShell: false,
      );
      await tester.pumpAndSettle();

      expect(find.byType(TransactionRow), findsOneWidget);
      expect(find.byType(SliverPersistentHeader), findsOneWidget);
    });

    testWidgets('empty names the window rather than the filter', (tester) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(
          drillRows: const AsyncValue.data(<Transaction>[]),
        ),
        wrapInShell: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('error carries the repository message', (tester) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(
          drillRows: AsyncValue<List<Transaction>>.error(
            Exception('payee lookup failed'),
            StackTrace.empty,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      // **Not `errorBodyGeneric`** (Law U9): a list that fails identically for every cause is a
      // failure nobody can diagnose.
      expect(find.textContaining('payee lookup failed'), findsOneWidget);
    });
  });

  group('archetype C obligations', () {
    testWidgets('the active filter is visible and removable', (tester) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(),
        wrapInShell: false,
      );
      await tester.pumpAndSettle();

      // A filter the reader cannot see is a bug report waiting to happen (ARCH_5 §3 archetype C).
      expect(find.byType(FilterChipBar), findsOneWidget);
    });

    testWidgets('it owns its Scaffold and app bar, outside the shell', (tester) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(),
        wrapInShell: false,
      );
      await tester.pumpAndSettle();

      // The opposite assertion to the home screen's, and why every pump here passes
      // `wrapInShell: false`: this screen brings its own `Scaffold`. `AppBar` resolves `hasDrawer`
      // before `canPop`, so a drill-down inside the shell would show a hamburger where back belongs
      // (Law U18).
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(Drawer), findsNothing);
    });

    testWidgets('an unparseable route explains itself instead of throwing', (tester) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: null),
        overrides: analyticsOverrides(),
        wrapInShell: false,
      );
      await tester.pumpAndSettle();

      // This route is deep-linkable, so a malformed one is reachable from outside the app.
      expect(find.byType(EmptyState), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the gate', () {
    testWidgets('renders at 320x640 with a doubled text scale', (tester) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(),
        wrapInShell: false,
        textScale: 2,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('every target is large enough and named', (tester) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(),
        wrapInShell: false,
      );
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });
}
```

`layout_overflow_test.dart` grows by two groups and 286 lines. **No sheet cases, because 7B adds no
sheet**: the tag drill happens in place inside its card and the clear-cache action is a row, so U2's
sheet clause has nothing to cover here. What it does add is one shared widget, two chart surfaces and
four full-height states.

Its import block was rebuilt rather than appended to — the file already carried `qty.dart` and
`unit_category.dart`, and a blind insertion duplicated both.

### `test/shared/golden/chart_card_golden_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/analytics/presentation/widgets/analytics_line_chart.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';

import '../../support/analytics_harness.dart';

/// Goldens for `ChartCard`, light and dark (ARCH_5 §9.2).
///
/// **Dark is the half that matters here.** Depth in this app is a palette step rather than a shadow
/// (ARCH_3 §8, ARCH_5 §2.5), so a surface-tier mistake is invisible in light mode and obvious in dark —
/// which is exactly why §9.2 asks for both and for one pass on a real device in dark.
///
/// Four states, not one: a golden of the populated card alone would let the loading, empty and error
/// branches drift, and those are three quarters of what this widget is for.
void main() {
  Widget card(AsyncValue<int> value, {Widget? trailing}) => Center(
        child: SizedBox(
          width: 320,
          child: ChartCard<int>(
            title: 'Where it went',
            subtitle: 'Last 30 days',
            value: value,
            isEmpty: (data) => data == 0,
            emptyMessage: 'Nothing spent in this window',
            onRetry: () {},
            approximateCount: 2,
            unconvertedCount: 1,
            trailing: trailing,
            builder: (context, data) => const AnalyticsPlotBox(
              child: ColoredBox(color: Color(0x11000000)),
            ),
          ),
        ),
      );

  final states = <String, AsyncValue<int>>{
    'populated': const AsyncValue.data(1),
    'loading': const AsyncValue.loading(),
    'empty': const AsyncValue.data(0),
    'error': AsyncValue.error(
      Exception('No rate for JPY on 2026-08-10, and none earlier'),
      StackTrace.empty,
    ),
  };

  for (final entry in states.entries) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('ChartCard ${entry.key} in $mode', (tester) async {
        await pumpAnalytics(
          tester,
          card(
            entry.value,
            trailing: entry.key == 'populated'
                ? const AmountText(
                    Money(432100, 'INR'),
                    size: AmountSize.small,
                    showSign: false,
                  )
                : null,
          ),
          overrides: analyticsOverrides(),
          dark: dark,
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(ChartCard<int>),
          matchesGoldenFile('goldens/chart_card_${entry.key}_$mode.png'),
        );
      });
    }
  }
}
```

### `test/shared/layout_overflow_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_bar_chart.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_donut_chart.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_line_chart.dart';
import 'package:alaya/features/analytics/presentation/widgets/slice_bar_list.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/features/calendar/presentation/widgets/day_sheet.dart';
import 'package:alaya/features/dashboard/presentation/widgets/funds_header.dart';
import 'package:alaya/features/dashboard/presentation/widgets/insight_card.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/presentation/sheets/delete_transaction_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/freeze_conversion_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/line_item_editor.dart';
import 'package:alaya/features/expense/presentation/sheets/quick_add_sheet.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_filter_sheet.dart';
import 'package:alaya/features/expense/providers/quick_add_providers.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/features/inventory/presentation/sheets/consume_sheet.dart';
import 'package:alaya/features/inventory/providers/consume_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/recurring/presentation/sheets/pay_sheet.dart';
import 'package:alaya/features/recurring/providers/pay_providers.dart';
import 'package:alaya/features/service/presentation/sheets/dispose_sheet.dart';
import 'package:alaya/features/service/presentation/widgets/contact_action.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/shopping/presentation/sheets/entry_editor_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/generate_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/list_manager_sheet.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_expandable_fab.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';
import 'package:alaya/shared/widgets/frequency_preview.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/loading_state.dart';
import 'package:alaya/shared/widgets/module_tile.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

import '../support/calendar_harness.dart' as cal;
import '../support/expense_harness.dart';
import '../support/fake_settings_repository.dart';

/// The only thing in this project that catches a layout overflow (ARCH_3 §8.3, ARCH_5 U2).
///
/// **Every sheet and every full-height state belongs here.** These defects are invisible to
/// `dart analyze`, to a file-by-file scan and to looking at the screen, because the missing
/// affordance is always an *ancestor*: the widget under review is locally correct and the parent
/// that should have given it room, or a way to scroll, is the one at fault.
///
/// They are also invisible to an ordinary widget test. A `RenderFlex` overflow reports through
/// `FlutterError.onError` rather than throwing at the site, so a test only fails on one if something
/// asks — which is exactly how an overflow hides in a suite that otherwise looks green. Every case
/// below asks, via `tester.takeException()`.
void main() {
  /// Roughly what a software keyboard takes from a phone in portrait.
  const double keyboardInset = 320;

  /// Roughly the room a list area has left on a small phone with a keyboard up.
  const Size squeezed = Size(320, 140);

  Widget host(
    Widget child, {
    double bottomInset = 0,
    double textScale = 1,
    List<Override> overrides = const [],
  }) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AlayaTheme.light(AlayaPresets.activePreset),
          // Every expense sheet reads `AlayaStrings.of(context)`, which unwraps a null without a
          // delegate installed. The Phase 5 groups pass literal strings, so this file went without
          // one until real screens arrived — and then failed as a null-check rather than as a
          // missing translation, which is why it read like five separate defects.
          localizationsDelegates: const [
            AlayaStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AlayaStrings.supportedLocales,
          // Inside the app rather than above it. `WidgetsApp` re-establishes `MediaQuery` from the
          // view, so an outer one is discarded before anything under test can read it — and a test
          // that believes it has simulated a keyboard when it has not is worse than no test.
          builder: (context, inner) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewInsets: EdgeInsets.only(bottom: bottomInset),
              textScaler: TextScaler.linear(textScale),
            ),
            child: inner!,
          ),
          home: Scaffold(body: child),
        ),
      );

  /// Content taller than the room a keyboard leaves, so the assertions are about the scaffold rather
  /// than about how long a particular string happens to be.
  Widget tallContent() => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [SizedBox(width: 200, height: 400)],
      );

  group('AlayaBottomSheet', () {
    testWidgets('scrolls rather than overflowing with a keyboard up', (tester) async {
      await tester.pumpWidget(
        host(AlayaBottomSheet(child: tallContent()), bottomInset: keyboardInset),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('still fits when there is no keyboard', (tester) async {
      await tester.pumpWidget(host(AlayaBottomSheet(child: tallContent())));
      expect(tester.takeException(), isNull);
    });

    // The bug, reproduced deliberately. `Padding(bottom: viewInsets)` around a `MainAxisSize.min`
    // Column is correct in each half and broken together: the padding shrinks the space and the
    // Column has no way to give up the room it already took. **If this ever stops overflowing, the
    // guard above has stopped testing anything** — and the reason AlayaBottomSheet exists has
    // quietly gone away.
    testWidgets('the un-scaffolded shape it replaces still overflows', (tester) async {
      await tester.pumpWidget(
        host(
          Padding(
            padding: const EdgeInsets.only(bottom: keyboardInset),
            child: tallContent(),
          ),
        ),
      );
      expect(tester.takeException(), isA<FlutterError>());
    });
  });

  group('ConfirmSheet', () {
    testWidgets('survives a keyboard and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => ConfirmSheet.show(
                context,
                title: 'Delete this transaction?',
                body: 'You can undo this for the next few seconds.',
                confirmLabel: 'Delete',
                cancelLabel: 'Cancel',
                destructive: true,
              ),
              child: const Text('open'),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('AlayaFormScaffold', () {
    Widget form({bool submitting = false}) => AlayaFormScaffold(
          primaryLabel: 'Save expense',
          onPrimary: () {},
          secondaryLabel: 'Cancel',
          onSecondary: () {},
          isDirty: true,
          isSubmitting: submitting,
          discardTitle: 'Discard your changes?',
          discardBody: 'What you have typed will not be saved.',
          discardConfirmLabel: 'Discard',
          discardCancelLabel: 'Keep editing',
          child: const Column(
            children: [SizedBox(height: 300), TextField(), SizedBox(height: 300)],
          ),
        );

    testWidgets('body scrolls and the footer stays above the keyboard', (tester) async {
      await tester.pumpWidget(host(form(), bottomInset: keyboardInset));
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a doubled text scale with a keyboard up', (tester) async {
      await tester.pumpWidget(host(form(), bottomInset: keyboardInset, textScale: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the submitting footer does not grow the row past its box', (tester) async {
      await tester.pumpWidget(host(form(submitting: true), textScale: 2));
      expect(tester.takeException(), isNull);
    });
  });

  // Every sheet Phase 6A adds, at a keyboard inset and a doubled text scale — the two conditions
  // under which each of them is first used and least likely to have been looked at.
  group('expense sheets', () {
    final expenseOverrides = <Override>[
      homeCurrencyCodeProvider.overrideWith((ref) => 'INR'),
      homeDecimalDigitsProvider.overrideWith((ref) => 2),
      selectableAccountsProvider.overrideWith((ref) => Stream.value(const [kAccount])),
      quickAddTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      accountsByIdProvider
          .overrideWith((ref) => Stream.value(<String, Account>{kAccount.id: kAccount})),
      lineEditorItemsProvider.overrideWith((ref) => Stream.value(const <Item>[])),
      enabledCurrenciesProvider.overrideWith(
        (ref) => Stream.value(const [
          Currency(
            code: 'USD',
            name: 'US Dollar',
            symbol: r'$',
            decimalDigits: 2,
            isEnabled: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: expenseOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets('QuickAddSheet', (tester) => pumpSheet(tester, const QuickAddSheet()));

    testWidgets(
      'TransactionFilterSheet',
      (tester) => pumpSheet(tester, const TransactionFilterSheet()),
    );

    testWidgets(
      'LineItemEditor',
      (tester) => pumpSheet(
        tester,
        const LineItemEditor(
          currencyCode: 'INR',
          decimalDigits: 2,
          defaultDestination: TransactionLineDestination.inventory,
        ),
      ),
    );

    testWidgets(
      'DeleteTransactionSheet',
      (tester) => pumpSheet(tester, const DeleteTransactionSheet()),
    );

    testWidgets(
      'FreezeConversionSheet',
      (tester) => pumpSheet(tester, const FreezeConversionSheet(excludeCode: 'INR')),
    );
  });

  // Phase 6B's sheet, at a keyboard inset and a doubled text scale — the two conditions under
  // which it is first used and least likely to have been looked at (U2).
  group('inventory sheets', () {
    final inventoryOverrides = <Override>[
      consumeFefoProvider('item-1').overrideWith((ref) => Stream.value(const <Batch>[])),
      unitsInCategoryProvider(UnitCategory.weight).overrideWith(
        (ref) => Stream.value(const [
          Unit(
            code: 'kg',
            category: UnitCategory.weight,
            factorToBaseMilli: 1000000,
            displayName: 'kilogram',
            isSystem: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    testWidgets('ConsumeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: ConsumeSheet(
              itemId: 'item-1',
              unitCode: 'kg',
              category: UnitCategory.weight,
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: inventoryOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6C's three sheets, at a keyboard inset and a doubled text scale — the two conditions under
  // which each is first used and least likely to have been looked at (U2).
  group('shopping sheets', () {
    final shoppingOverrides = <Override>[
      entryItemsProvider.overrideWith((ref) => Stream.value(const <Item>[])),
      entryTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      entryCurrencyProvider.overrideWith((ref) async => 'INR'),
      entryDecimalDigitsProvider.overrideWith((ref) async => 2),
      entriesProvider('list-1').overrideWith((ref) => Stream.value(const <ShoppingEntry>[])),
      shoppingItemsByIdProvider.overrideWith((ref) => Stream.value(const <String, Item>{})),
      allListsProvider.overrideWith((ref) => Stream.value(const <ShoppingList>[])),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: shoppingOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets(
      'EntryEditorSheet',
      (tester) => pumpSheet(tester, const EntryEditorSheet(listId: 'list-1')),
    );

    testWidgets(
      'GenerateSheet',
      (tester) => pumpSheet(tester, const GenerateSheet(listId: 'list-1')),
    );

    testWidgets(
      'ListManagerSheet',
      (tester) => pumpSheet(tester, const ListManagerSheet()),
    );
  });

  // Phase 6D's pay sheet, at a keyboard inset and a doubled text scale — an amount field, a date
  // field, an account dropdown and a two-line note, all growing at once.
  group('recurring sheets', () {
    final recurringOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      payAccountsProvider.overrideWith((ref) => Stream.value(const <Account>[])),
      payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
    ];

    testWidgets('PaySheet', (tester) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(
            child: PaySheet(
              occurrenceId: 'occ-1',
              template: RecurringTemplate(
                id: 'tpl-1',
                name: 'A rent template with a name long enough to wrap at a doubled scale',
                normalizedName: 'rent',
                kind: RecurringKind.rent,
                direction: RecurringDirection.outflow,
                defaultAmount: const Money(120000, 'INR'),
                intervalUnit: RecurringIntervalUnit.month,
                intervalCount: 1,
                startDateKey: const DateKey(20260131),
                nextDueDateKey: const DateKey(20260831),
                isPaused: false,
                autoRemind: true,
                remindDaysBefore: 3,
                anchorDayOfMonth: 31,
              ),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: recurringOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6D adds, with a clamp note on every row.
  group('FrequencyPreview at a doubled text scale', () {
    testWidgets('three dates, two of them clamped', (tester) async {
      await tester.pumpWidget(
        host(
          const FrequencyPreview(
            dates: [
              PreviewedDate(dateKey: DateKey(20260131)),
              PreviewedDate(dateKey: DateKey(20260228), clamped: true),
              PreviewedDate(dateKey: DateKey(20260331)),
            ],
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6E's dispose sheet: seven choice chips, a date field, an optional amount and a note, all
  // growing at once under a keyboard inset.
  group('service sheets', () {
    final serviceOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('DisposeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: DisposeSheet(assetId: 'asset-1', currencyCode: 'INR'),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: serviceOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The contact block: a name, a number and a call button, none of them flexible.
  group('ContactAction at a doubled text scale', () {
    testWidgets('a long name beside a long number', (tester) async {
      await tester.pumpWidget(
        host(
          const ContactAction(
            phone: '+91 98765 43210',
            name: 'A service centre with a name long enough to wrap',
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6F's dashboard sections. Each is a card whose figures, chips and labels all grow at once, and
  // the funds header carries the only display-sized amount in the app.
  group('dashboard sections', () {
    final dashOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      // InsightCard's notifier restores its side from `app_settings` on the first frame, which
      // resolves `databaseProvider` unless this is here — the failure reads as a database bug in a
      // test that never mentions one (ARCH_6 P6).
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      dashboardCurrencyProvider.overrideWith((ref) async => 'INR'),
      dashboardDigitsProvider.overrideWith((ref) async => 2),
      totalFundsProvider.overrideWith(
        (ref) async => const NetWorth(
          total: Money(98765432, 'INR'),
          unconvertedCount: 3,
          isApproximate: true,
        ),
      ),
      upcomingProvider.overrideWith((ref) async => const <UpcomingEntry>[]),
    ];

    testWidgets('FundsHeader with both chips at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const FundsHeader(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('InsightCard with its switch at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const InsightCard(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6F adds. Two lines of text and a glyph inside a fixed aspect ratio is
  // exactly the shape that overflows when the text doubles and the box does not.
  group('ModuleTile at a doubled text scale', () {
    testWidgets('a long label beside a long count', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 160,
            height: 108,
            child: ModuleTile(
              label: 'Recurring commitments',
              icon: Icons.event_repeat,
              detail: '17 need attention before the end of the month',
              onTap: () {},
            ),
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 7A. Both shapes here are the ones that have already cost this project rounds: a sheet whose
  // content outgrows the viewport, and a grid of text cells whose row height does not move with the text.
  // Zero width, which is not a hypothetical: Android reports it on the first frame of every launch
  // ("D/FlutterRenderer: Width is zero. 0,0") and the FAB's slot subtracted padding from it, producing a
  // negative width and a red screen on startup. Every widget harness sets a real viewport before pumping,
  // which is exactly why nothing here caught it — so the degenerate viewport is now stated outright.
  group('degenerate viewports', () {
    testWidgets('the expandable FAB survives a zero-width first frame', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size.zero),
            child: Scaffold(
              floatingActionButton: AlayaExpandableFab(
                openLabel: 'Add',
                closeLabel: 'Close',
                actions: [
                  FabAction(label: 'One', icon: Icons.add, onPressed: () {}),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('calendar', () {
    List<Override> calOverrides({List<CalendarEvent> events = const []}) =>
        cal.calendarOverrides(cal.FakeCalendarRepository(events: events));

    final busyDay = <CalendarEvent>[
      cal.event(title: 'A payee with a name long enough to wrap at a doubled scale', amountMinor: 98765432),
      cal.event(
        type: CalendarEventType.serviceDue,
        refType: 'asset',
        refId: 'as-1',
        title: 'The boiler in the upstairs cupboard',
        baseSeverity: CalendarSeverity.warning,
      ),
      cal.event(
        type: CalendarEventType.batchExpiry,
        refType: 'inventoryBatch',
        refId: 'ba-1',
        title: 'Yoghurt, the large tub',
        baseSeverity: CalendarSeverity.warning,
      ),
    ];

    testWidgets('DaySheet with three grouped entries at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('DaySheet with a keyboard up as well', (tester) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // U26: `TableCalendar` takes a fixed `rowHeight`, so the grid computes one from the text scaler. If
    // that computation is ever replaced by a constant, this is the test that says so.
    testWidgets('the month grid at a doubled scale on the narrowest phone', (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 2, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the month grid at a tripled scale, which is past what U15 asks for',
        (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 3, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // The range header prints two formatted dates and a dash, which is the longest single string this
    // screen can produce — and it appears only in a mode the other cases never enter.
    testWidgets('the range header at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 2, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('22'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    // The screen's own composition, which the shared full-height group cannot reach: six measured rows
    // plus a header are taller than a squeezed list area on their own, so the grid and the state beneath
    // it have to share a scroll rather than compete for a fixed box.
    for (final scale in [1.0, 2.0]) {
      testWidgets('the whole screen in a squeezed viewport at ${scale}x', (tester) async {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: scale,
            overrides: calOverrides(events: busyDay),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    // Each of the three states in turn, in the same squeezed box. Loading and error sit in the sliver
    // that fills the remainder, and that remainder is negative here.
    testWidgets('loading, empty and error all survive the squeezed box', (tester) async {
      for (final repo in [
        cal.FakeCalendarRepository(pending: true),
        cal.FakeCalendarRepository(),
        cal.FakeCalendarRepository(error: 'view unavailable'),
      ]) {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: 2,
            overrides: cal.calendarOverrides(repo),
          ),
        );
        // `pump`, not `pumpAndSettle`: the loading case holds a `CircularProgressIndicator`, which
        // animates forever, so `pumpAndSettle` times out rather than settling. Two frames is enough to
        // resolve the completed futures in the other two cases.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('full-height states in a squeezed viewport', () {
    Widget inSqueezedBox(Widget child) => host(
          Center(
            child: SizedBox(width: squeezed.width, height: squeezed.height, child: child),
          ),
        );

    testWidgets('EmptyState with an icon, body and action', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          EmptyState(
            title: 'No transactions yet',
            body: 'Add your first expense and it will appear here.',
            icon: Icons.receipt_long_outlined,
            actionLabel: 'Add expense',
            onAction: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ErrorState with a retry — the tallest of the three', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          ErrorState(
            title: 'That did not work',
            body: 'Something went wrong on our side. Try again.',
            retryLabel: 'Try again',
            onRetry: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('LoadingState', (tester) async {
      await tester.pumpWidget(inSqueezedBox(const LoadingState(label: 'Loading')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('AlayaListSkeleton clips rather than overflowing', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(const AlayaListSkeleton(label: 'Loading transactions')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('EmptyState at a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: EmptyState(
                title: 'No transactions yet',
                body: 'Add your first expense and it will appear here.',
                icon: Icons.receipt_long_outlined,
                actionLabel: 'Add expense',
                onAction: () {},
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    // The states are also the shape the Theme Lab renders inside a half-width pane, which is where
    // the 150px `SizedBox` around an EmptyState used to overflow by roughly 58px.
    testWidgets('EmptyState in a half-width pane', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          const SizedBox(
            width: 134,
            child: EmptyState(title: 'No matches', body: 'Try a shorter search.'),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6A's line-items page: a full-height screen whose summary row, list rows and footer all
  // grow under text scale at once. Squeezed and doubled, which is the pair U21 exists for.
  group('the line items page', () {
    final editorOverrides = <Override>[
      transactionEditorProvider.overrideWith(
        () => _FixedEditor(
          AsyncValue.data(
            TransactionEditorState(
              currencyCode: 'INR',
              dateKey: const DateKey(20260801),
              amount: const Money(20000, 'INR'),
              lines: [
                TransactionLine(
                  id: 'l1',
                  transactionId: '',
                  lineNo: 1,
                  description: 'A description long enough to need two lines at a doubled scale',
                  destination: TransactionLineDestination.inventory,
                  quantity: const Qty(500000, UnitCategory.weight),
                  lineAmount: const Money(4000, 'INR'),
                ),
              ],
            ),
          ),
        ),
      ),
      homeDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('populated at 320dp and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(const LineItemsScreen(), textScale: 2, overrides: editorOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('kit rows at a doubled text scale', () {
    testWidgets('KeyValueRow wraps a long value instead of overflowing', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            child: KeyValueRow(
              label: 'Payment method',
              value: 'Bank transfer from HDFC Savings ending 4417',
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('FilterChipBar wraps rather than clipping a row of chips', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: FilterChipBar(
              clearAllLabel: 'Clear all',
              onClearAll: () {},
              filters: [
                ActiveFilter(label: 'Account: HDFC Savings', onRemove: () {}),
                ActiveFilter(label: 'Tag: Groceries', onRemove: () {}),
                ActiveFilter(label: 'Jan 2026 – Aug 2026', onRemove: () {}),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('StatusChip ellipsises a long label in a narrow box', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 96,
            child: StatusChip(label: 'Needs details', tone: StatusTone.info),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── Phase 7B ──────────────────────────────────────────────────────────────────────────
  //
  // **No sheets, so no sheet cases.** 7B adds no `AlayaBottomSheet`: the tag drill happens in place
  // inside its card and the clear-cache action is a row, so there is nothing here for U2's sheet
  // clause to cover. What it does add is one shared widget, two chart surfaces and four full-height
  // states, and those are below.
  group('analytics surfaces', () {
    // **Wrapped in a scroll view, because that is the only place a `ChartCard` ever lives** — the
    // analytics screen puts every card in a `SliverList`. Handed a tight viewport height instead, its
    // `Column` has nowhere to go and reports an overflow the real screen cannot produce. What these
    // cases are for is the *horizontal* axis: a header that starves, a chip row that will not wrap, a
    // plot box that outgrows its card.
    Widget card({
      Widget? trailing,
      Widget child = const Text('body'),
      AsyncValue<int> value = const AsyncValue.data(1),
    }) =>
        SingleChildScrollView(
            child: ChartCard<int>(
          title: 'Price per kilogram across every purchase this year',
          subtitle: 'What one thing costs you, purchase by purchase',
          value: value,
          isEmpty: (data) => data == 0,
          emptyMessage: 'Nothing yet',
          onRetry: () {},
          approximateCount: 3,
          unconvertedCount: 2,
          trailing: trailing,
          builder: (context, data) => child,
        ));

    testWidgets('ChartCard stacks its header above 1.5x rather than clipping the figure',
        (tester) async {
      // The `trailing` slot is an `AmountText`, which clips rather than ellipsises — so a clipped
      // figure is a wrong figure and the header has to stack instead of sharing a row (Law U21).
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              trailing: const AmountText(
                Money(123456789, 'INR'),
                size: AmountSize.small,
                showSign: false,
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ChartCard keeps both quality chips at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(SizedBox(width: 320, child: card()), textScale: 2),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ChartCard renders its error branch in a narrow box', (tester) async {
      // The inline failure, not `ErrorState`: that one is a full-height state with a 40px glyph and
      // its own `ScrollSafeCenter`, which inside a card would push every sibling off the screen.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              value: AsyncValue<int>.error(
                Exception('No rate for JPY on 2026-08-10, and none earlier'),
                StackTrace.empty,
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a plot area grows with the text scaler and stays inside its card',
        (tester) async {
      // `AnalyticsPlotBox` scales from the text scaler and clamps (Laws U26, U28's clamping lesson).
      // Unclamped, a tripled scale would produce a card taller than the viewport — and the box sizes
      // only the plot, so the card's own title and subtitle grow beside it rather than being squeezed
      // into the plot's height.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              child: const AnalyticsPlotBox(
                child: AnalyticsLineChart(
                  series: [
                    AnalyticsSeries(
                      tone: AnalyticsSeriesTone.expense,
                      points: [
                        AnalyticsPoint(x: 0, value: 100000, axisLabel: 'Jan'),
                        AnalyticsPoint(x: 1, value: 90000),
                        AnalyticsPoint(x: 2, value: 140000, axisLabel: 'Aug'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a flat series does not collapse its own plot band', (tester) async {
      // Every point equal makes `maxY - minY` zero, which fl_chart divides by. The chart widens the
      // band by one minor unit rather than handing it a zero.
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            height: 120,
            child: AnalyticsLineChart(
              series: [
                AnalyticsSeries(
                  tone: AnalyticsSeriesTone.neutral,
                  points: [
                    AnalyticsPoint(x: 0, value: 5000),
                    AnalyticsPoint(x: 1, value: 5000),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a bar chart of thirty-one buckets survives a doubled scale at 320dp',
        (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            height: 160,
            child: AnalyticsBarChart(
              labelEvery: 5,
              buckets: [
                for (var day = 1; day <= 31; day++)
                  AnalyticsBucket(bucket: day, value: day * 1000, label: '$day'),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an all-zero bar chart still draws its axis', (tester) async {
      // A window where nothing was spent must show that the buckets exist and are empty, rather than
      // dividing by a zero maximum.
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            height: 160,
            child: AnalyticsBarChart(
              buckets: [
                AnalyticsBucket(bucket: 1, value: 0, label: 'M'),
                AnalyticsBucket(bucket: 7, value: 0, label: 'S'),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a donut stays a ring at a tripled scale', (tester) async {
      // `AnalyticsDonutChart` sizes its radius from the box's shorter side, so a taller box at a raised
      // scale must not produce a cropped ellipse — and the centre text has to fit the hole.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              child: Builder(
                builder: (context) => AnalyticsDonutChart(
                  slices: analyticsSlices(
                    context,
                    const [
                      (label: 'Groceries', value: 400000, key: 'grocery'),
                      (label: 'Household', value: 220000, key: 'household'),
                      (label: 'Bills', value: 180000, key: 'bill'),
                    ],
                    otherLabel: 'Everything else',
                    remainder: 90000,
                  ),
                  centreTop: '85%',
                  centreBottom: 'in three kinds',
                ),
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a donut groups its tail rather than drawing twelve slivers', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              child: Builder(
                builder: (context) {
                  final slices = analyticsSlices(
                    context,
                    [
                      for (var i = 0; i < 12; i++)
                        (label: 'Kind $i', value: 12000 - i * 500, key: 'k$i'),
                    ],
                    otherLabel: 'Everything else',
                  );
                  // Six wedges plus one remainder, whatever it was handed.
                  expect(slices, hasLength(7));
                  return AnalyticsDonutChart(slices: slices);
                },
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an all-zero donut renders nothing rather than dividing by zero',
        (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              child: Builder(
                builder: (context) {
                  final slices = analyticsSlices(
                    context,
                    const [(label: 'Groceries', value: 0, key: 'grocery')],
                    otherLabel: 'Everything else',
                  );
                  expect(slices, isEmpty);
                  return AnalyticsDonutChart(slices: slices);
                },
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a swatched list without bars stacks above 1.5x', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: SliceBarList(
              showBars: false,
              slices: [
                SliceBar(
                  label: 'Between my accounts and everywhere else',
                  value: const AmountText(
                    Money(98765432, 'INR'),
                    size: AmountSize.small,
                    showSign: false,
                  ),
                  share: 0.8,
                  detail: '34%',
                  swatch: const Color(0xFF3F51B5),
                  onTap: () {},
                ),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('SliceBarList stacks its rows above 1.5x', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: SliceBarList(
              slices: [
                SliceBar(
                  label: 'Between my accounts and everywhere else',
                  value: const AmountText(
                    Money(98765432, 'INR'),
                    size: AmountSize.small,
                    showSign: false,
                  ),
                  share: 1,
                  detail: '12 purchases',
                  onTap: () {},
                ),
                SliceBar(
                  label: 'Household',
                  value: const QtyText(Qty(4450000, UnitCategory.weight)),
                  share: 0.4,
                ),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a share above one does not assert', (tester) async {
      // `share` is a ratio of two sums, so a rounding artefact can exceed one and
      // `FractionallySizedBox` asserts on a factor greater than one. It is clamped.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: SliceBarList(
              slices: [
                SliceBar(
                  label: 'Groceries',
                  value: const Text('x'),
                  share: 1.0000001,
                ),
                SliceBar(label: 'Bills', value: const Text('y'), share: double.nan),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('analytics full-height states in a squeezed viewport', () {
    Future<void> pumpSqueezed(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(
        host(Center(child: SizedBox.fromSize(size: squeezed, child: child))),
      );
    }

    testWidgets('the drill-down skeleton clips rather than overflowing', (tester) async {
      await pumpSqueezed(tester, const AlayaListSkeleton(label: 'Loading these transactions…'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the drill-down empty state scrolls instead of overflowing', (tester) async {
      await pumpSqueezed(
        tester,
        const EmptyState(
          title: 'Nothing here in this window',
          body: 'The window is set on the insights screen. Widen it and these may appear.',
          icon: Icons.filter_alt_outlined,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the screen-level empty state scrolls with its action', (tester) async {
      // The tallest of the three: icon, two text blocks and a 48dp button (ARCH_5 §4.1).
      await pumpSqueezed(
        tester,
        EmptyState(
          title: 'Nothing to show for this window',
          body: 'Widen the window above, or record something and it will appear here.',
          icon: Icons.insights_outlined,
          actionLabel: 'Add expense',
          onAction: () {},
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the drill-down error state survives with a retry', (tester) async {
      await pumpSqueezed(
        tester,
        ErrorState(
          title: 'Could not work that out',
          body: 'No rate for JPY on 2026-08-10, and none earlier',
          retryLabel: 'Try again',
          onRetry: () {},
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// A transaction editor reporting a fixed state, so a layout can be pumped without a database.
class _FixedEditor extends TransactionEditorNotifier {
  _FixedEditor(this._value);

  final AsyncValue<TransactionEditorState> _value;

  @override
  AsyncValue<TransactionEditorState> build(String? arg) => _value;
}
```

---

## COVERAGE — ARCH_5 §7 rows closed by Phase 7B

| Row | Status |
|---|---|
| **Dashboard insight card, spending side** | **Closed.** Reads `AnalyticsService` over the dashboard's own 30-day window; `insightAnalyticsPending` deleted. See the addendum |
| **Implements `AnalyticsPort` adapter** | **Closed.** `analytics_port_impl.dart`, all 25 methods over real SQL, `analyticsPortProvider` typed as the port |
| **Implements `AnalyticsCacheRepository`** | **Closed.** `analytics_cache_repository_impl.dart` over the existing DAO, `analyticsCacheRepositoryProvider` |
| `analytics_cache` — engine writes | **Closed.** Two queries go through the cache: the heatmap and the inventory valuation |
| `analytics_cache` — "clear cache" | **Closed**, on the analytics screen rather than in Settings. See the deviation below |
| `tags.parentTagId` — drill-down in analytics | **Closed.** `TagSpendCard` rolls children into their parent and opens one level in place |
| `CurrencyRepository.watchUnconvertedCount` | **Closed.** `UnconvertedCounter` over the same `RateTable`; the `Stream.value(0)` stub is deleted |
| AnalyticsHome (F) · 24 query surfaces · DrillDown (C) | **Closed.** Every one of ARCH_3 §5.1's queries is watched by a card |
| `ChartCard` in `shared/` | **Closed.** The one shared addition §8 permits this phase, with goldens in both modes |

ARCH_4 §5.1 item 15 closes here: all seventeen of Phase 3A's repository contracts now have an
implementation, and all twelve engines have a provider.
---

## Addendum — the dashboard row this phase also owned

ARCH_5 §7 assigns the dashboard insight card's **spending side** to 7B, not just the `/insights`
destination. The route was wired; the card was still rendering *"Spending breakdowns arrive with the
analytics module."* That state was right while `AnalyticsService` had no adapter — aggregating spending in
the dashboard would have left this phase a competing implementation to reconcile (ARCH_4 P7) — and it is
wrong now.

The side reads `AnalyticsService.categoryConcentration` over `last30Provider`: **the dashboard's own
window, not `analyticsWindowProvider`**. Sharing the analytics screen's range would make the dashboard
change when nothing on the dashboard was touched.

No new ARB keys — it reuses `rangeLast30Days`, `chartLoading` and `analyticsNothingSpent`.
`insightAnalyticsPending` is **deleted**, so `app_en.arb` is 1,076 keys rather than 1,077.

### `lib/features/dashboard/providers/insight_providers.dart`

```dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/calendar/providers/calendar_providers.dart';
import 'package:alaya/features/dashboard/providers/range_providers.dart';
import 'package:alaya/features/dashboard/state/insight_side.dart';

/// One thing that needs attention, and when.
class UpcomingEntry {
  /// Creates an entry.
  const UpcomingEntry({
    required this.kind,
    required this.title,
    required this.dueDateKey,
    this.route,
  });

  /// Which sort of obligation this is, which decides its wording and glyph.
  final UpcomingKind kind;

  /// What it is called.
  final String title;

  /// When it falls due.
  final DateKey dueDateKey;

  /// Where tapping it goes, when there is somewhere useful.
  final String? route;

  /// Whether it is already past its date, derived from the clock and never stored (ARCH_2 §12.2).
  bool isOverdue(DateKey today) => dueDateKey < today;
}

/// The four sorts of thing the upcoming side collects.
enum UpcomingKind {
  /// A recurring occurrence that is due.
  bill,

  /// An asset whose service interval has come round.
  service,

  /// A warranty about to lapse.
  warranty,

  /// A batch at or near its expiry date.
  batch,
}

/// How far ahead the upcoming side looks.
///
/// A fortnight: long enough that a monthly bill appears before it is late, short enough that the card
/// stays a shortlist rather than a second ledger.
const int upcomingHorizonDays = 14;

/// Spend by kind over the dashboard's own thirty-day window — the insight card's spending side.
///
/// **Added in Phase 7B, which closed the gap this side was built around.** 6F shipped it as an inline
/// empty state naming what it waited for, because `AnalyticsService` had no `AnalyticsPort` adapter and
/// aggregating spending in the dashboard would have left 7B a competing implementation to reconcile
/// (ARCH_4 P7, ARCH_5 §7). The adapter now exists, so the side reads the engine.
///
/// **Its own window, not the analytics screen's.** `last30Provider` is fixed; `analyticsWindowProvider`
/// follows a chip the user last touched on another screen. Sharing it would make the dashboard change
/// when nothing on the dashboard was touched.
final spendingInsightProvider = FutureProvider<Concentration>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.categoryConcentration(ref.watch(last30Provider));
});

/// Which face of the insight card is showing, restored from `app_settings`.
final insightSideProvider = NotifierProvider<InsightSideNotifier, InsightSide>(
  InsightSideNotifier.new,
);

/// Holds and persists the insight card's side.
class InsightSideNotifier extends Notifier<InsightSide> {
  @override
  InsightSide build() {
    unawaited(_restore());
    return InsightSide.upcoming;
  }

  Future<void> _restore() async {
    final stored = await ref
        .read(settingsRepositoryProvider)
        .readValue(InsightSide.settingsKey);
    final restored = InsightSide.parse(stored);
    if (restored != state) state = restored;
  }

  /// Shows [side] and remembers it.
  ///
  /// The write is not awaited: the card should flip on the frame the user taps, and a settings row that
  /// lands a millisecond later changes nothing they can see.
  void show(InsightSide side) {
    state = side;
    unawaited(
      ref
          .read(settingsRepositoryProvider)
          .writeValue(
            key: InsightSide.settingsKey,
            value: side.stored,
            // `app_settings` stores its own type alongside the value, and every row this app writes is a
            // string. An enum's name is a string; declaring it anything else would be a claim the reader
            // has to unpick.
            valueType: 'string',
          ),
    );
  }
}

/// Everything falling due inside [upcomingHorizonDays], soonest first.
///
/// **Now `CalendarAggregator`, which is what the previous version said it could not be.** It read four
/// repositories directly because `CalendarRepository` had no implementation until Phase 7A
/// (ARCH_4 §5.1 item 15); it does now, so the stand-in retires rather than drifting alongside the real
/// engine. Three things were wrong with it, and none were visible from here:
///
/// 1. Its own doc comment claimed five reads including `ServiceRecordRepository.watchWithNextDueInRange`.
///    The body performed four and never called it, so a service due recorded against a **service record**
///    rather than against the asset never reached this card (ARCH_6 P18 — a comment asserting what the
///    code does not do).
/// 2. Batches were titled `batch.id`, so an expiring item showed a **UUID** where the calendar, whose
///    view `COALESCE`s the item name, showed "Yoghurt".
/// 3. Severity was nobody's job here. `CalendarAggregator` applies ARCH_3 §6's per-type thresholds
///    against the injected clock, so "needs attention" now means the same thing on both screens.
///
/// **Transactions and shopping targets are filtered out, deliberately.** Every kind this card carries is
/// consequential if ignored: a bill goes late, a service lapses, a warranty dies, food spoils. A past
/// transaction is not an obligation, and a shopping target is self-imposed — missing it costs nothing,
/// and a weekly shop would land in almost every fortnight, so it would be the one row always present and
/// therefore the one carrying no signal. The calendar is where plans belong; this card is for obligations.
final upcomingProvider = FutureProvider.autoDispose<List<UpcomingEntry>>((
  ref,
) async {
  // The same materialisation the calendar waits on. Without it this card cannot show a bill that is
  // not already overdue, which was true of the version it replaced too.
  await ref.watch(recurringHorizonProvider.future);

  final today = ref.watch(clockProvider).today();
  final horizon = today.addDays(upcomingHorizonDays);

  // A year back, not `DateRangeFloor.past`. Overdue still matters more than upcoming, but a floor in
  // 1900 makes the range nominally bounded and practically a full scan of seven tables — and nothing
  // outstanding for over a year is going to be actioned from a fortnight's shortlist.
  final days = await ref
      .watch(calendarAggregatorProvider)
      .watchDays(from: today.addDays(-overdueLookbackDays), to: horizon, today: today)
      .first;

  final entries = <UpcomingEntry>[];
  for (final day in days) {
    for (final event in day.events) {
      final kind = _kindOf(event.type);
      if (kind == null) continue;
      entries.add(
        UpcomingEntry(
          kind: kind,
          title: event.title,
          dueDateKey: event.dateKey,
        ),
      );
    }
  }

  entries.sort((a, b) => a.dueDateKey.compareTo(b.dueDateKey));
  return entries;
});

/// The [UpcomingKind] for [type], or null where the type is not an obligation.
UpcomingKind? _kindOf(CalendarEventType type) => switch (type) {
      CalendarEventType.recurringDue => UpcomingKind.bill,
      CalendarEventType.serviceDue => UpcomingKind.service,
      CalendarEventType.warrantyEnd => UpcomingKind.warranty,
      CalendarEventType.batchExpiry => UpcomingKind.batch,
      CalendarEventType.transaction => null,
      CalendarEventType.shoppingTarget => null,
    };

/// How far back the card reaches for things still outstanding.
const int overdueLookbackDays = 365;

/// The lower bound for a read that should include things already overdue.
///
/// Overdue matters more than upcoming, so the floor reaches back rather than starting at today — a
/// service three weeks late must not fall off the card for being too late.
abstract final class DateRangeFloor {
  /// Far enough back to catch anything still outstanding.
  static final DateKey past = DateKey.fromYmd(1900, 1, 1);
}
```

### `lib/features/dashboard/presentation/widgets/insight_card.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/dashboard/state/insight_side.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// A switchable card: what is coming up, or where the money went.
///
/// **Each side owns its own loading, empty and error state, inline.** That is the whole reason this is one
/// card with a switch rather than two cards: a failing rate table or an unreachable engine must cost the
/// user this card and nothing else. One failing card never blanks the dashboard (ARCH_5 §3 archetype F).
///
/// **The spending side has no data, and says so rather than pretending.** `AnalyticsService` has no
/// `AnalyticsPort` adapter and `CalendarAggregator` has no `CalendarRepository`, both assigned to Phase 7B
/// and 7A (ARCH_4 §5.1 item 15). Aggregating spending here instead would leave 7B a competing
/// implementation to reconcile, so the side is built, switchable and honest — and 7B supplies data to a
/// card that already exists.
///
/// The choice is stored in `app_settings`, so it survives a restart.
class InsightCard extends ConsumerWidget {
  /// Creates the card.
  const InsightCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final side = ref.watch(insightSideProvider);
    final notifier = ref.read(insightSideProvider.notifier);

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: strings.insightSwitchLabel,
            child: SegmentedButton<InsightSide>(
              segments: [
                ButtonSegment(
                  value: InsightSide.upcoming,
                  label: Text(strings.insightUpcoming),
                ),
                ButtonSegment(
                  value: InsightSide.spending,
                  label: Text(strings.insightSpending),
                ),
              ],
              selected: {side},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => notifier.show(selection.first),
            ),
          ),
          const SizedBox(height: AlayaSpacing.md),
          switch (side) {
            InsightSide.upcoming => const _Upcoming(),
            InsightSide.spending => const _Spending(),
          },
        ],
      ),
    );
  }
}

class _Upcoming extends ConsumerWidget {
  const _Upcoming();

  static IconData _glyph(UpcomingKind kind) => switch (kind) {
        UpcomingKind.bill => Icons.event_repeat,
        UpcomingKind.service => Icons.build_outlined,
        UpcomingKind.warranty => Icons.verified_outlined,
        UpcomingKind.batch => Icons.inventory_2_outlined,
      };

  static String _label(AlayaStrings strings, UpcomingKind kind) => switch (kind) {
        UpcomingKind.bill => strings.insightBillDue,
        UpcomingKind.service => strings.insightServiceDue,
        UpcomingKind.warranty => strings.insightWarrantyEnding,
        UpcomingKind.batch => strings.insightBatchExpiring,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final async = ref.watch(upcomingProvider);
    final today = ref.watch(clockProvider).today();

    return async.when(
      loading: () => Text(
        strings.loadingDashboard,
        style: AlayaTypography.caption.copyWith(color: semantic.muted),
      ),
      error: (error, stack) => Text(
        error.toString(),
        style: AlayaTypography.caption.copyWith(color: semantic.danger),
      ),
      data: (entries) => entries.isEmpty
          ? Text(
              strings.insightNothingUpcoming,
              style: AlayaTypography.body.copyWith(color: semantic.muted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Capped, not scrolled: a card inside a `CustomScrollView` that scrolls on its own is two
                // scroll gestures competing for the same drag. Five is a shortlist; the modules behind it
                // hold the rest.
                for (final entry in entries.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AlayaSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _glyph(entry.kind),
                          size: AlayaIconSize.md,
                          color: entry.isOverdue(today) ? semantic.danger : semantic.muted,
                        ),
                        const SizedBox(width: AlayaSpacing.sm),
                        Expanded(
                          // The title, its sort and its date all grow with text scale, so they wrap
                          // among themselves rather than starving the icon's neighbour (Law U21).
                          child: Wrap(
                            spacing: AlayaSpacing.xs,
                            runSpacing: AlayaSpacing.xxs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                entry.title,
                                style: AlayaTypography.body
                                    .copyWith(color: theme.colorScheme.onSurface),
                              ),
                              Text(
                                _label(strings, entry.kind),
                                style: AlayaTypography.caption
                                    .copyWith(color: semantic.muted),
                              ),
                              DateText(
                                entry.dueDateKey,
                                style: DateTextStyle.dayMonth,
                                muted: true,
                              ),
                              if (entry.isOverdue(today))
                                StatusChip(
                                  label: strings.recurringOverdue,
                                  tone: StatusTone.danger,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// The spending side, reading the analytics engine Phase 7B wired.
///
/// **This replaced the "waiting on the analytics module" state 6F shipped.** That state was correct
/// while `AnalyticsService` had no adapter; aggregating spending here instead would have left 7B a
/// competing implementation to reconcile (ARCH_4 P7). The row it closed is ARCH_5 §7's, assigned to 7B.
///
/// A shortlist and not a chart: the card is one of four things on a dashboard, and the analytics screen
/// is one tap away for anyone who wants the breakdown.
class _Spending extends ConsumerWidget {
  const _Spending();

  /// How many kinds the card names before it stops. `Concentration.top` is already the top three.
  static const int _maxRows = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final async = ref.watch(spendingInsightProvider);
    final digits = ref.watch(dashboardDigitsProvider).valueOrNull ?? 2;

    return async.when(
      loading: () => Text(
        strings.chartLoading,
        style: AlayaTypography.body.copyWith(color: semantic.muted),
      ),
      // The repository's own message, never a generic body (Law U9).
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: error.toString(),
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(spendingInsightProvider),
      ),
      data: (concentration) {
        if (concentration.top.isEmpty) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.insights_outlined, size: AlayaIconSize.md, color: semantic.muted),
              const SizedBox(width: AlayaSpacing.sm),
              Expanded(
                child: Text(
                  strings.analyticsNothingSpent,
                  style: AlayaTypography.body.copyWith(color: semantic.muted),
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // **The window is labelled** (anomaly A33). "Spending" alone does not say over what, and no
            // figure on the card can disambiguate itself.
            Text(
              strings.rangeLast30Days,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            const SizedBox(height: AlayaSpacing.xxs),
            AmountText(
              concentration.total,
              size: AmountSize.medium,
              showSign: false,
              decimalDigits: digits,
            ),
            const SizedBox(height: AlayaSpacing.sm),
            for (final slice in concentration.top.take(_maxRows))
              KeyValueRow(
                // `slice.key` through the ARB, never `slice.label`: the adapter grouped by the enum
                // name, so the label is `grocery` (Law U5).
                label: AnalyticsLabels.subtype(strings, slice.key),
                valueWidget: AmountText(
                  slice.amount,
                  size: AmountSize.small,
                  showSign: false,
                  decimalDigits: digits,
                ),
              ),
          ],
        );
      },
    );
  }
}
```

### `test/support/dashboard_harness.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/dashboard/providers/module_providers.dart';
import 'package:alaya/features/dashboard/providers/range_providers.dart';

import 'dart:async';
import 'fake_settings_repository.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so every derived date is the same on every machine.
final Clock kDashClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kDashClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// A headline total, with however many balances it could not convert.
NetWorth netWorth({
  int minor = 12345678,
  int unconverted = 0,
  bool approximate = false,
}) =>
    NetWorth(
      total: Money(minor, 'INR'),
      unconvertedCount: unconverted,
      isApproximate: approximate,
    );

/// Totals over one window.
RangeTotals totals({int inMinor = 500000, int outMinor = 320000, int excluded = 0}) =>
    RangeTotals(
      moneyIn: Money(inMinor, 'INR'),
      moneyOut: Money(outMinor, 'INR'),
      excludedCount: excluded,
    );

/// One thing needing attention.
UpcomingEntry upcoming({
  UpcomingKind kind = UpcomingKind.bill,
  String title = 'Rent',
  DateKey on = const DateKey(20260805),
}) =>
    UpcomingEntry(kind: kind, title: title, dueDateKey: on);

/// Spend by kind over the dashboard's thirty-day window.
Concentration spendByKind({int total = 320000, int kinds = 3}) => (
      top: [
        for (var i = 0; i < kinds; i++)
          (
            key: 'grocery',
            label: 'grocery',
            amount: Money(100000 - i * 10000, 'INR'),
            share: 0.3 - i * 0.05,
          ),
      ],
      topShare: kinds == 0 ? 0.0 : 0.85,
      total: Money(total, 'INR'),
      quality: exactConversion,
    );

/// Overrides every dashboard provider to a settled, harmless value.
///
/// **Fixed length, always.** A conditional entry changes the override count between scopes and Riverpod
/// refuses it outright — and two `pumpWidget` calls in one test silently reuse the first scope, so a
/// varying list fails in both directions (ARCH_4 P5).
///
/// Every provider is overridden even where a test does not care, because an un-overridden repository
/// provider reaches a real database, which a widget test has no business opening (P6).
List<Override> dashboardOverrides({
  AsyncValue<NetWorth>? funds,
  AsyncValue<RangeTotals>? last30,
  AsyncValue<RangeTotals>? allTime,
  AsyncValue<List<UpcomingEntry>>? upcomingEntries,
  int inventory = 0,
  int services = 0,
  AsyncValue<int>? expenses,
  AsyncValue<int>? shopping,
  AsyncValue<int>? recurring,
  AsyncValue<Concentration>? spending,
}) =>
    [
      clockProvider.overrideWithValue(kDashClock),
      // `InsightSideNotifier.build` reads settings during the first frame, so this is not optional
      // even for a test that never touches the insight card: without it the notifier resolves
      // `databaseProvider`, which throws by design (Law L10). A `NotifierProvider` instance cannot be
      // overridden (ARCH_6 P5), so the repository beneath it is the only seam.
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      dashboardCurrencyProvider.overrideWith((ref) async => 'INR'),
      dashboardDigitsProvider.overrideWith((ref) async => 2),
      totalFundsProvider.overrideWith(
        (ref) => _resolve(funds ?? AsyncValue.data(netWorth())),
      ),
      rangeTotalsProvider.overrideWith(
        (ref, range) => _resolve(
          (range == (from: DateKey(20260703), to: kToday) ? last30 : allTime) ??
              AsyncValue.data(totals()),
        ),
      ),
      upcomingProvider.overrideWith(
        (ref) => _resolve(upcomingEntries ?? const AsyncValue.data(<UpcomingEntry>[])),
      ),
      inventoryCountProvider.overrideWith((ref) => inventory),
      serviceCountProvider.overrideWith((ref) => services),
      expenseCountProvider.overrideWith((ref) => _resolve(expenses ?? const AsyncValue.data(0))),
      shoppingCountProvider.overrideWith((ref) => _resolve(shopping ?? const AsyncValue.data(0))),
      recurringCountProvider.overrideWith((ref) => _resolve(recurring ?? const AsyncValue.data(0))),
      // Phase 7B. Unconditional like every other entry: a conditional override changes the list's
      // length between scopes and Riverpod refuses it outright (ARCH_6 P5). Without it the spending
      // side resolves `analyticsServiceProvider`, which reaches `databaseProvider` and throws by
      // design (Law L10).
      spendingInsightProvider.overrideWith(
        (ref) => _resolve(spending ?? AsyncValue.data(spendByKind())),
      ),
    ];

/// Turns an [AsyncValue] back into the future a `FutureProvider` override expects.
Future<T> _resolve<T>(AsyncValue<T> value) => value.when(
      data: Future.value,
      loading: pendingFuture<T>,
      error: (error, stack) => Future<T>.error(error, stack),
    );

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
Future<void> pumpDashboard(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pump();
}
```

### `test/features/dashboard/insight_card_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/dashboard/presentation/widgets/insight_card.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/dashboard/state/insight_side.dart';

import '../../support/dashboard_harness.dart';

/// Both sides, both empty states, and the switch. One failing card never blanks the dashboard.
void main() {
  // Inside a scroll view, because that is the only place the app ever puts this card: `DashboardScreen`
  // mounts it in a `CustomScrollView`, and the card's own contract is that it must not scroll on its own
  // — two scroll gestures competing for one drag. A bare `Scaffold` body bounds the main axis at the
  // viewport, so at a doubled scale this failed the card for being tall, which is what a card full of
  // wrapped text at 2x is supposed to be.
  //
  // This does not weaken the assertions. The cross axis stays tight at 320dp, and that is where the
  // overflow class this suite exists for actually lives (Law U21) — a starved `Expanded`, or a `Row`
  // that will not stack, still throws here.
  Widget host() => const Scaffold(
        body: SingleChildScrollView(child: InsightCard()),
      );

  testWidgets('it opens on what is coming up', (tester) async {
    await pumpDashboard(tester, host(), overrides: dashboardOverrides());
    await tester.pumpAndSettle();
    expect(find.text('Coming up'), findsOneWidget);
    expect(find.text('Where it went'), findsOneWidget);
  });

  testWidgets('loading the upcoming side says so, inline', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(upcomingEntries: const AsyncValue.loading()),
    );
    // Inline, inside the card: the header and the module grid above and below must stay usable.
    expect(find.text('Adding it up'), findsOneWidget);
  });

  testWidgets('a failed upcoming read shows its reason inline', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        upcomingEntries: AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('nothing upcoming is good news, and reads like it', (tester) async {
    await pumpDashboard(tester, host(), overrides: dashboardOverrides());
    await tester.pumpAndSettle();
    expect(
      find.text('Nothing needs attention in the next fortnight.'),
      findsOneWidget,
    );
  });

  testWidgets('populated lists what is due, soonest first', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        upcomingEntries: AsyncValue.data([
          upcoming(title: 'Rent'),
          upcoming(
            kind: UpcomingKind.service,
            title: 'Living room TV',
            on: const DateKey(20260810),
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Bill due'), findsOneWidget);
    expect(find.text('Living room TV'), findsOneWidget);
    expect(find.text('Service due'), findsOneWidget);
  });

  testWidgets('something already late says so', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        // Due in July against a clock fixed to 1 August. Derived from the clock, never stored.
        upcomingEntries: AsyncValue.data([upcoming(on: const DateKey(20260715))]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Overdue'), findsOneWidget);
  });

  testWidgets('the spending side shows a labelled total and its top kinds', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: [
        ...dashboardOverrides(),
        insightSideProvider.overrideWith(() => _FixedSide(InsightSide.spending)),
      ],
    );
    await tester.pumpAndSettle();
    // **Phase 7B replaced the "waiting on the analytics module" assertion this test used to make.**
    // The side reads `AnalyticsService` now; what is asserted is that the window is labelled
    // (anomaly A33) and that the subtype key was localised rather than rendered raw (Law U5).
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text('Groceries'), findsWidgets);
    expect(find.text('grocery'), findsNothing);
    expect(find.text('Nothing needs attention in the next fortnight.'), findsNothing);
  });

  testWidgets('the spending side reports its own failure and keeps the switch', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: [
        ...dashboardOverrides(
          spending: AsyncValue<Concentration>.error(
            Exception('rate table unreachable'),
            StackTrace.empty,
          ),
        ),
        insightSideProvider.overrideWith(() => _FixedSide(InsightSide.spending)),
      ],
    );
    await tester.pumpAndSettle();
    // The repository's own message, not a generic body (Law U9), and the segmented control survives so
    // the reader can switch back to the side that works.
    expect(find.textContaining('rate table unreachable'), findsOneWidget);
    expect(find.byType(SegmentedButton<InsightSide>), findsOneWidget);
  });

  testWidgets('an empty window reads as a fact rather than a failure', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: [
        ...dashboardOverrides(spending: AsyncValue.data(spendByKind(total: 0, kinds: 0))),
        insightSideProvider.overrideWith(() => _FixedSide(InsightSide.spending)),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing spent in this window'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        upcomingEntries: AsyncValue.data([
          upcoming(title: 'A bill with a name long enough to wrap at a doubled scale'),
          upcoming(kind: UpcomingKind.batch, on: const DateKey(20260710)),
        ]),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        upcomingEntries: AsyncValue.data([upcoming()]),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('the stored side', () {
    test('an unknown value falls back to upcoming rather than throwing', () {
      // A settings row is user data, and a future version may write a value this one has never heard of.
      expect(InsightSide.parse('spending'), InsightSide.spending);
      expect(InsightSide.parse('upcoming'), InsightSide.upcoming);
      expect(InsightSide.parse('something-else'), InsightSide.upcoming);
      expect(InsightSide.parse(null), InsightSide.upcoming);
    });

    test('what is stored round-trips', () {
      for (final side in InsightSide.values) {
        expect(InsightSide.parse(side.stored), side);
      }
    });
  });
}

/// A notifier reporting a fixed side, so each face can be pumped directly.
class _FixedSide extends InsightSideNotifier {
  _FixedSide(this._value);

  final InsightSide _value;

  @override
  InsightSide build() => _value;
}
```

### The 24 queries and where each one surfaces

| # | Query | Surface |
|---|---|---|
| 1 | Spend by subtype | `SubtypeSpendCard` → drill-down |
| 2 | Spend by tag | `TagSpendCard`, one level of nesting |
| 3 | Spend by payment method | `PaymentMethodSpendCard` → drill-down |
| 4 | Top payees | `TopPayeesCard` → drill-down |
| 5 | Income vs expense | `IncomeVsExpenseCard` |
| 6 | Net cash flow | `NetCashFlowCard` |
| 7 | Balance trend | `BalanceTrendCard`, in the account's own currency |
| 8 | Grocery share | stated inside `ConcentrationCard` |
| 9 | Top items by spend | `TopItemsBySpendCard` → drill-down |
| 10 | Top items by quantity | `TopItemsByQuantityCard`, grouped by measure |
| 11 | Dearest single purchase | `DearestPurchaseCard` |
| 12 | **Unit-price trend** | `InflationCard` — the headline |
| 13 | Inventory value | `InventoryValueCard`, cached |
| 14 | **Food waste** | `WasteCard` |
| 15 | Expiring soon | `ExpiringCard` |
| 16 | Low-stock count | `LowStockCard` |
| 17 | Monthly commitment | `MonthlyCommitmentCard` |
| 18 | Recurring vs discretionary | `RecurringSplitCard` → drill-down, both sides |
| 19 | Lifetime service cost | `ServiceCostCard` |
| 20 | Warranty coverage | `WarrantyCard` |
| 21 | Spend heatmap | `SpendHeatmapCard`, cached |
| 22 | Category concentration | `ConcentrationCard` |
| 23 | Average grocery basket | `AverageBasketCard` |
| 24 | **Price per base unit** | `InflationCard`'s points — query 12's own data |

Archetypes: AnalyticsHome is **F**, DrillDown is **C**. Both implement loading, empty, error and
populated, and both have a widget test per state.

### Deviations, each deliberate

| Deviation | Why |
|---|---|
| **"Clear cache" is on the analytics screen, not in Settings** | §7.1 assigns it to Settings, which is a `PlaceholderScreen` until 8A. It could not go in the app bar either: `/insights` is a shell destination, so the bar belongs to `_ShellScaffold` and an action there would appear on all nine destinations. **8A's Settings entry must call `analyticsCacheControllerProvider`, not the service** (Law U22) |
| **No FAB, where archetype F lists one** | Nothing on an analytics screen is a capture action. A FAB whose only job is to leave the screen it floats over is decoration |
| **No Y-axis number labels on either chart** | An axis is where a `Money` gets clipped, `AmountText` clips rather than ellipsises, and a clipped figure is a wrong figure (Law U7). Grid lines carry the shape; the card's headline carries the number |
| **Chart touch disabled** | A tooltip is a timed surface, and ARCH_5 §6 requires that nothing be available *only* there |
| **Two queries cached, not twenty-four** | `AnalyticsCacheService` stores strings, so caching a result type costs a codec. Its own doc says a cache on a 5 ms query buys nothing, and `shouldCache` is the gate. The heatmap groups by `strftime` and can use no index; the valuation is unbounded over batches |
| **Most breakdowns are bars, not rings** | A ring is unreadable at a doubled text scale past six wedges, labels nothing, and offers no target. `SliceBarList` carries every ranked breakdown. Rings were added afterwards for the three figures that *are* a partition — see below |

### Where a ring earns its place, and where it would lie

Three of the twenty-four figures divide one whole, and for those a ring shows what a list cannot: the shape
of the division at a glance. The rest stay as bars.

| Card | Ring? | Why |
|---|---|---|
| Spend by kind (1) | **Yes** | Subtypes are mutually exclusive — every withdrawal has exactly one |
| Concentration (22) | **Yes** | The card *is* about proportion. Its remainder is supplied from the known total rather than derived, so three wedges never fill the circle and imply three kinds were all the spending |
| Recurring vs discretionary (18) | **Yes** | Two wedges of one whole — the shape a ring is for |
| Spend by tag (2) | No | **Not a partition.** One purchase can carry two tags, so wedges would sum past the total and assert a whole that does not exist |
| Top payees, top items (4, 9) | No | Ranked, not a partition — the top ten is not everything |
| Top items by quantity (10) | No | Law L8: grams and pieces share no whole |
| Warranty coverage (20) | Not yet | A coverage timeline needs a start date, and `WarrantyCoverage` was only ever read here for `end`, `isCovered` and `daysLeft`. Drawing "days out of 365" would invent the denominator (ARCH_4 R22) |

Four things hold for every ring:

- **A single-hue alpha ramp, not categorical colours.** The palette is data — five presets the user picks
  between (ARCH_5 §2.1) — so a hand-chosen set would clash under at least one, and `warning`/`danger`/
  `success` are reserved for state (§2.4). Stepping alpha on `primary` cannot clash and reads in order:
  biggest is darkest.
- **Identity lives in the list, not the ring.** Each row carries the wedge's colour as a swatch beside its
  label, so colour is never the only signal (Law U17). One `analyticsSlices` call feeds both, so the fifth
  wedge and the fifth row cannot end up different colours.
- **No wedge carries a number.** A `Money` in a 40dp arc is the clipping Law U7 forbids, and a percentage
  there duplicates the rows. Touch is off, like every other chart (ARCH_5 §6).
- **`ExcludeSemantics` on the ring.** The swatched list is the same slices in text; describing both makes a
  screen reader read the card twice.

The rows drop their bars where a ring sits above them — the ring already carries the proportion, and the bar
repeating it is the second accessory to remove.

### Two things this phase changed outside its own files

**`_detail` deleted from `app_router.dart`.** Declared since 6F, called by nothing, so
`very_good_analysis` reports `unused_element`. `app_router.dart`, `app_en.arb` and
`layout_overflow_test.dart` are carried by seven documents each and must stay byte-identical
(ARCH_6 §2), so this phase obliges a regeneration of PHASE_05 and 06A–06F alongside 07A.

**Four dashboard files change**, so PHASE_06F regenerates: `insight_providers.dart`,
`insight_card.dart`, `dashboard_harness.dart` and `insight_card_test.dart`. The harness's override list
grows by one entry — unconditionally, because a conditional one changes the list's length between scopes
and Riverpod refuses it (P5) — and the test that asserted the pending copy now asserts a labelled window,
a localised subtype key, an error carrying its own message and a genuine empty state.

**`CurrencyDao` gains `watchAllRates()`**, which means PHASE_02C regenerates too. Nothing could
previously observe a rate arriving — every rate read on that DAO is a `Future` — which is why
`watchUnconvertedCount` stayed a stub for three phases rather than because the query was hard.

### Open, with owners

| Item | Why it is open | Owner |
|---|---|---|
| **No ledger drill-down from a tag** | The link lives in `transaction_tags`, `Transaction` carries no tag ids, and `TagRepository.watchForTransaction` is per-transaction — so filtering a window by tag would be one query per row. 6A's `TransactionFilter` has no tag axis for the same reason, so this is inherited rather than introduced. The fix is `TagRepository.watchTransactionIdsFor(tagId)`: one DAO query, one contract method, one impl | 8A, with Settings › Tags |
| `parent_ref_id` on `v_calendar_events` | 7A recorded that three event types cannot deep-link for want of it. 7B wants the same column, so it is worth doing once | a 2A pass |
| `UnitCategory` label duplicated three ways | 6B already holds two private copies; `AnalyticsLabels.unitCategory` is a third. It cannot live on `UnitCategory` (that is `core/`, `AlayaStrings` is `app/`), and one helper in `shared/` needs an ARCH_5 §8 record | 9 |
| A custom date range | `DateRangeService.resolve` returns null for `custom` by design and 7B ships no picker. `AnalyticsRange.presets` omits it rather than offering a chip that resolves to nothing | 9 |
| `AnalyticsPort.totalSpend` is implemented and uncalled | `AnalyticsService` derives the total from `spendBySubtype`, so asking the port again would be a second read for a figure already in hand. Recorded so it is not deleted as dead | — |
| `fl_chart`'s API is unverified | No compiler in the session that wrote this (ARCH_4 R22). Confined to `analytics_line_chart.dart` and `analytics_bar_chart.dart`; every colour, gap and text style comes from Alaya's tokens, so if the API differs two files change rather than the phase | first build |
| **Eight cards dropped the engine's approximate-rate signal** | Six passed `unconvertedCount` and not `approximateCount`; `ConcentrationCard` and `TagSpendCard` read neither. `AnalyticsService` computes both (ARCH_3 §1.3) and the cards discarded half of it, so a figure converted against a stale weekend rate looked exact. All eight now pass both. `tagSpendTreeProvider` drops the series' quality when it builds the tree, so that card reads it from the cached `spendByTagProvider` | fixed here |
| **`PieTouchData` has no `const` constructor** | Its siblings `LineTouchData` and `BarTouchData` do, so `const` on all three compiled in two files and failed in the third. Precisely what ARCH_4 R22 means by verifying against the compiler | fixed here |
| **`ChartCard.chartHeight` bounded the whole builder, not the plot** | It wrapped everything the builder returned in a fixed box, so a card putting chrome above its chart — a title, a legend, a segmented control — had that chrome squeezed into the plot's height, and `Expanded` became mandatory because only a bounded box makes it legal. `InflationCard` overflowed by 44px at scale 1 and four of the six chart cards were built that way. Replaced by `AnalyticsPlotBox`, which sizes only the plot; the card grows with its own text inside the screen's `SliverList` | fixed here |
| **`insight_card_test.dart` did not compile as shipped in 6F** | It uses `AsyncValue` in six code positions with no `flutter_riverpod` import. 7B adds the import while editing the file, so this is fixed rather than merely reported — but it means 6F's test suite never ran green | fixed here |
| `repository_providers.dart`, `service_providers.dart`, `app_router.dart` have unsorted imports | Pre-existing in 7A and earlier, so `directives_ordering` is either not in the enabled lint set or those files carry warnings. Not corrected here: the alphabetical fix would enlarge a diff already spanning seven documents, and it is worth deciding once for the whole tree | a lint pass |
| `seed_test.dart` warned about multiple databases on every run | Several of its tests open a second `AlayaDatabase` deliberately — the non-default-home-currency and determinism cases both need an independently seeded one to compare against — and each has its own `NativeDatabase.memory()`, so there is nothing to race. `driftRuntimeOptions.dontWarnAboutMultipleDatabases` is set in that file's `main` rather than globally, so a genuine double-open elsewhere still reports. PHASE_01C carries the file | fixed here |
| `insight_providers.dart` and `insight_card.dart` imported `core/time/clock.dart` unused | `ref.watch(clockProvider)` never names `Clock`, and type inference does not require the import. Both removed while the files were open | fixed here |
| §9.1 / §9.2 sign-off | Both need a green run. `flutter pub add fl_chart && flutter gen-l10n && dart run build_runner build && flutter test` is the gate; `fl_chart`'s `LineChartData` and `BarChartData` parameter lists are the two things most likely to fail first, and the goldens need `--update-goldens` on their first run | first build |
