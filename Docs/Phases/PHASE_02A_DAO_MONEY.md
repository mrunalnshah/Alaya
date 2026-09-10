# Phase 2A — Data Access Objects, Money Side

> **Regenerated from the canonical tree.** Every fix through Phase 6E is folded in; regenerating from
> this document reproduces the code that runs. Shared files carry identical content in every copy.

**9 DAOs · 30 Stream methods · 5 multi-table writes, each in one `transaction {}`.**

## Add dependencies

None. Every import resolves to packages already present.

```bash
dart run build_runner build
dart analyze
```

## Fix in this revision

`DateKey` deliberately does not `implement int` (ARCH_1 §4.3) — that is what stops `dateKey + 1`
compiling, since `20260731 + 1` is not a date. The same protection means drift's range helpers
reject it: `isBetweenValues` and `isSmallerOrEqualValue` take a column's **SQL** type,
`Expression<int>`, even when a type converter is attached. Two call sites broke (three errors,
because `isBetweenValues` takes two arguments).

Rather than sprinkle `.value` unwraps, this adds **`lib/data/db/date_key_filters.dart`** — a
`DateKeyColumnFilters` extension crossing that boundary once:

| Was | Now |
|---|---|
| `t.rateDateKey.isSmallerOrEqualValue(on)` | `t.rateDateKey.isDateOnOrBefore(on)` |
| `t.dateKey.isBetweenValues(from, to)` | `t.dateKey.isInDateRange(from, to)` |

Also provides `isDateOnOrAfter`, `isDateBefore`, `isDateAfter`, `isOnDate`. Worth a file because
the same error is waiting in 2B (`expiry_date_key`), 2C (due, warranty and service dates), 4C (the
calendar's bounded range) and 7B (every analytics window) — roughly a dozen more sites. Recorded in
ARCH_1 §4.3 next to the sorting consequence of the same design decision, and in the 2B/2C prompts.

The `Date` in each name is load-bearing: the extension necessarily applies to any
`Expression<int>`, so `originalAmountMinor.isInDateRange(...)` should read as obviously wrong.
`month_key` is `yyyymm`, has no wrapper type, and keeps comparing with plain ints.

I re-scanned all nine DAOs for the same mismatch: **two sites, both fixed, none remaining.**

## One thing to check in your generated code

The helper works whether or not view columns inherit their source column's type converter, so it
was safe to write without knowing. But that answer determines whether `ActiveTransactionRow.dateKey`
is a `DateKey` or a plain `int`, and **Phase 3B's mappers depend on it**. One command tells you:

```bash
grep -n "final .* dateKey" lib/data/db/alaya_database.g.dart | head
```

`DateKey dateKey` means converters propagate into views and 3B maps them directly. `int dateKey`
means 3B wraps with `DateKey(...)` at the mapper boundary. Either is fine — worth knowing before
3B rather than during it.

## Two things I had to resolve before writing a line

### 1. This phase's "all reads go through the views" rule cannot be followed literally

Of the eleven money-side tables, **only two have views**. ARCH_2 §12 defines eleven views; nine of
them serve inventory, scheduling and the calendar. The money side gets `v_account_ledger`,
`v_account_balances`, `v_active_transactions`, `v_transaction_allocation` and `v_monthly_totals`
— covering `accounts` and `transactions`, and nothing else:

| Table | View |
|---|---|
| `accounts`, `transactions` | ✅ covered |
| `app_settings`, `currencies`, `currency_rates`, `units`, `tags`, `transaction_tags`, `payment_methods`, `payees`, `transaction_lines` | ❌ none exists |

So seven of the nine DAOs have no view to read from. I considered adding pass-through views
(`v_active_currencies` and friends) to make the rule literally true, and rejected it: each would
generate a **second row class with fields identical to the table's**, so every Phase 3B mapper
would have to know whether it holds a `CurrencyRow` or an `ActiveCurrencyRow`, and every schema
snapshot would carry nine objects answering no question a `WHERE` clause does not. That is worse
code, not better compliance.

What I did instead — **satisfy L7's stated purpose structurally**. L7 exists so that
`deletedAt IS NULL` "cannot be forgotten". In every DAO here, reads funnel through one private
`_activeRows()` builder, and the only methods returning unfiltered rows are named
`byIdIncludingDeleted` so the exception is impossible to use by accident. Repositories never write
SQL, so they cannot bypass it. **Where a view exists it is used, without exception** —
`transaction_dao` never selects the base table for a read (verified: zero occurrences), and
balances and ledger legs are never recomputed in Dart.

The `byIdIncludingDeleted` methods are deliberate, not laziness: a deleted tag or payee must still
render a name on an old transaction, or history shows blank chips (anomaly A36).

If you would rather have the pass-through views, say so — it is nine short views and a rename pass.

### 2. Generated view class names — resolved by fixing them explicitly

Phase 1C left this open: I used `customSelect` in the 1C tests because I could not verify what
drift names a view's row class. Nine DAOs cannot be written on a guess, so I looked it up. Drift
files support explicit naming:

```sql
CREATE VIEW v_account_balances AS AccountBalanceRow AS SELECT ...
```

All eleven view declarations in the five `.drift` files now carry it, following Phase 1B's
`XxxRow` convention. Those five files are included below because they changed. The upside reaches
past this phase: 3B's mappers and every UI phase now reference names chosen deliberately rather
than derived by a rule none of us can see.

The generated names this phase depends on, and how much each is worth trusting:

| Kind | Example | Basis |
|---|---|---|
| Table classes | `$TransactionsTable` | drift's documented, long-stable convention |
| View row classes | `AccountBalanceRow` | **fixed by me** in the `.drift` files |
| View DB getters | `attachedDatabase.vAccountBalances` | snake_case → lowerCamelCase, same rule as tables |
| View *table* classes | — | never named; `late final _active = ...` infers it |

That last row is the one remaining unknown, and it is now unnameable rather than guessed.

## Verification performed

| Check | Result |
|---|---|
| All 5 patched `.drift` files still emit valid SQL | 11 views created after stripping the drift-only `AS DartName` |
| L14 — every genuinely multi-table write wrapped | 5 / 5 inside one `transaction {}` |
| L7 — `transaction_dao` base-table reads | 0 |
| No business rules — no `throw`, no `Failure` in any DAO | 0 violations |
| FTS search SQL run against a real FTS5 index | correct results, ranked, soft-deleted rows excluded |
| FTS query escaping | see below |

**The FTS escaping is necessary, not defensive.** I ran the naive version against a real index:

| Input | Unescaped | Escaped |
|---|---|---|
| `rent (July) - paid` | **throws** `fts5: syntax error near "rent"` | `['t1']` |
| `AND` | **throws** `fts5: syntax error near "AND"` | `[]` |
| `foo"bar` | **throws** `unterminated string` | `[]` |
| `***` | **throws** `unknown special query: **` | `[]` without querying |

Every one of those is something a user can type into a search box.

**A bug caught while testing that escaping.** My first pattern was `[\p{L}\p{N}]+`, and it splits
`टमाटर` into `टम` and `टर` — Devanagari and Gujarati vowel signs are Unicode category **M**, not L.
Search would have quietly stopped working for exactly the languages this app's first users type in.
Fixed to `[\p{L}\p{N}\p{M}]+` and verified: `टमाटर` → `['t1']`, `શાકભાજી` → `['t3']`. This is the
same bug class as the one fixed in Phase 1A's `Normalizer`, which is worth noting as a pattern —
any Unicode character-class in this codebase needs `\p{M}` unless there is a reason not to.

## Design notes worth knowing before Phase 3B

**`monthKey` is not derived in the DAO.** It is a required companion field, and the schema's third
CHECK enforces `date_key / 100 = month_key`. A caller that gets it wrong is rejected by the
database rather than silently writing a transaction invisible to monthly analytics. Deriving it
here would hide that error.

**`freezeConversion` cannot rewrite the original amount.** `originalAmountMinor` and
`originalCurrencyCode` are not parameters, so Law L9 is enforced by the method signature rather
than by remembering.

**`softDelete` on a transaction cascades to its lines and stops there.** Batches and assets a line
created are untouched — you deleted a receipt, not the groceries (A10). Detaching them is 3B's job
via `TransactionLineDao.clearCreatedArtefacts`.

**`replaceLines` soft-deletes rather than removing.** A line may already have created a batch, and
`createdBatchId` is the only record of that link.

**System-row guards are `WHERE` clauses, not caller-side checks.** `softDeleteUserTag`,
`softDeleteUserUnit` and `softDeleteUserMethod` return the rows-changed count and match on
`isSystem = false`, so a caller that forgets to check simply changes nothing.

**One new file outside the DELIVER list: `lib/core/enums/tag_scope.dart`.** `TagDao.watchByScope`
needs a scope vocabulary, and Phase 3B's abstract `TagRepository` needs the same one. Law L12
forbids `domain/` importing from `data/`, so defining it beside the DAO would force either an L12
violation or a duplicated enum with a mapping function. `core/` is the one layer both may import.



---

### `lib/core/enums/tag_scope.dart`

```dart
/// Which module's tag picker a query is asking about, mapping one-to-one onto the six
/// `allowedIn*` columns on `tags` (ARCH_2 §3).
///
/// Lives in `core/` rather than beside the tag DAO deliberately. Phase 3B's abstract
/// `TagRepository` needs this vocabulary too, and Law L12 forbids `domain/` importing anything
/// from `data/` — so a scope type defined next to the DAO would either force an L12 violation or
/// a duplicated enum with a mapping function between the two. `core/` is the one layer both sides
/// may import.
enum TagScope {
  /// The deposit editor's tag picker.
  deposit,

  /// The withdrawal editor's tag picker.
  withdrawal,

  /// The inventory item editor's tag picker.
  inventory,

  /// The shopping list's group headers.
  shopping,

  /// The recurring template editor's tag picker.
  recurring,

  /// The service manager's tag picker.
  service,
}
```

### `lib/data/db/date_key_filters.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/time/date_key.dart';

/// `DateKey`-typed comparison helpers for the `INTEGER yyyymmdd` columns that store civil dates.
///
/// Exists because [DateKey] deliberately does **not** `implement int` (ARCH_1 §4.3): that is what
/// stops `dateKey + 1` compiling, since `20260731 + 1` is not a date. The same protection means a
/// `DateKey` cannot be handed to drift's `isBetweenValues` / `isSmallerOrEqualValue`, which operate
/// on a column's *SQL* type — `Expression<int>` — even when a type converter is attached. So every
/// date comparison needs an explicit `.value`, and doing that inline at each call site spreads the
/// unwrapping across every DAO that filters by date: batch expiry in 2B, due and warranty dates in
/// 2C, the calendar's bounded range in 4C, every analytics window in 7B.
///
/// These methods cross that boundary once, here, where it is visible and testable.
///
/// The `Date` in each name is load-bearing. This extension necessarily applies to any
/// `Expression<int>`, including `month_key` and every minor-unit amount column, so the names are
/// chosen to make `originalAmountMinor.isInDateRange(...)` read as obviously wrong. `month_key` is
/// `yyyymm`, not `yyyymmdd`, and has no wrapper type — compare it with plain ints.
extension DateKeyColumnFilters on Expression<int> {
  /// True where this date column is on or before [date] — inclusive.
  Expression<bool> isDateOnOrBefore(DateKey date) => isSmallerOrEqualValue(date.value);

  /// True where this date column is on or after [date] — inclusive.
  Expression<bool> isDateOnOrAfter(DateKey date) => isBiggerOrEqualValue(date.value);

  /// True where this date column is strictly before [date].
  Expression<bool> isDateBefore(DateKey date) => isSmallerThanValue(date.value);

  /// True where this date column is strictly after [date].
  Expression<bool> isDateAfter(DateKey date) => isBiggerThanValue(date.value);

  /// True where this date column falls within `[from, to]` — inclusive at both ends.
  ///
  /// The form every bounded range query should use, so it hits the date indexes from ARCH_2 §11
  /// rather than scanning.
  Expression<bool> isInDateRange(DateKey from, DateKey to) =>
      isBetweenValues(from.value, to.value);

  /// True where this date column is exactly [date].
  Expression<bool> isOnDate(DateKey date) => equals(date.value);
}
```

### `lib/data/db/views/account_views.drift`

```sql
import '../tables/money_tables.dart';

-- The keystone of the read model (ARCH_2 §12.1), reproduced verbatim. Every transaction becomes
-- signed per-account legs, and a `transfer` appears TWICE with opposite signs — which is why a
-- self-transfer nets to zero across v_account_balances by construction, rather than by any Dart
-- code getting it right (anomaly A02).
--
-- `account_id` is nullable in the generated row class because it selects from the nullable
-- `from_account_id` / `to_account_id`. The WHERE clauses plus the shape CHECK on `transactions`
-- guarantee non-null in practice, but SQL cannot express that. Do not "fix" it with COALESCE: a
-- null here would mean a malformed row the CHECK should have rejected, and mapping it to a
-- placeholder account would hide exactly that.
CREATE VIEW v_account_ledger AS AccountLedgerRow AS
  SELECT id AS tx_id, to_account_id   AS account_id,
         original_amount_minor        AS signed_minor,
         original_currency_code AS currency_code, date_key, kind
    FROM transactions
   WHERE deleted_at IS NULL AND kind IN ('deposit','adjustmentIncrease')
  UNION ALL
  SELECT id, from_account_id, -original_amount_minor,
         original_currency_code, date_key, kind
    FROM transactions
   WHERE deleted_at IS NULL AND kind IN ('withdrawal','adjustmentDecrease')
  UNION ALL
  SELECT id, from_account_id, -original_amount_minor,
         original_currency_code, date_key, kind
    FROM transactions
   WHERE deleted_at IS NULL AND kind = 'transfer'
  UNION ALL
  SELECT id, to_account_id,   original_amount_minor,
         original_currency_code, date_key, kind
    FROM transactions
   WHERE deleted_at IS NULL AND kind = 'transfer';

-- Opening balance plus that account's ledger legs, in the account's own currency
-- (ARCH_2 §12.1, verbatim). Never SUM `balance_minor` across accounts without converting first:
-- accounts may hold different currencies (anomaly A34).
CREATE VIEW v_account_balances AS AccountBalanceRow AS
  SELECT a.id            AS account_id,
         a.currency_code AS currency_code,
         a.opening_balance_minor
           + COALESCE((SELECT SUM(l.signed_minor)
                         FROM v_account_ledger l
                        WHERE l.account_id = a.id), 0) AS balance_minor
    FROM accounts a
   WHERE a.deleted_at IS NULL;

```

### `lib/data/db/views/transaction_views.drift`

```sql
import '../tables/money_tables.dart';

-- Active transactions joined to the display names a repository would otherwise fetch per row.
-- Reading this rather than the base table is what makes forgetting `deleted_at IS NULL`
-- impossible (Law L7, anomaly A20).
CREATE VIEW v_active_transactions AS ActiveTransactionRow AS
  SELECT t.id AS tx_id, t.kind, t.subtype, t.occurred_at, t.date_key, t.month_key,
         t.original_amount_minor, t.original_currency_code,
         t.from_account_id, fa.name AS from_account_name,
         t.to_account_id,   ta.name AS to_account_name,
         t.payment_method_id, pm.name AS payment_method_name,
         t.payee_id, p.name AS payee_name,
         t.note, t.needs_review, t.recurring_template_id, t.recurring_occurrence_id,
         t.converted_amount_minor, t.converted_currency_code
    FROM transactions t
    LEFT JOIN accounts        fa ON fa.id = t.from_account_id
    LEFT JOIN accounts        ta ON ta.id = t.to_account_id
    LEFT JOIN payment_methods pm ON pm.id = t.payment_method_id
    LEFT JOIN payees          p  ON p.id  = t.payee_id
   WHERE t.deleted_at IS NULL;

-- The "unallocated ₹20" chip (anomaly A11). The transaction amount is the source of truth and the
-- lines are optional detail, so a mismatch is surfaced, never auto-balanced.
--
-- With no lines at all, `allocated_minor` is 0 and `unallocated_minor` equals the full amount.
-- Check `line_count` to tell "no lines yet" apart from "lines that happen to sum exactly" — the
-- UI must not show an unallocated chip for a transaction nobody has itemised.
CREATE VIEW v_transaction_allocation AS TransactionAllocationRow AS
  SELECT t.id AS tx_id,
         t.original_amount_minor AS amount_minor,
         COALESCE((SELECT SUM(l.line_amount_minor) FROM transaction_lines l
                    WHERE l.transaction_id = t.id AND l.deleted_at IS NULL), 0) AS allocated_minor,
         t.original_amount_minor
           - COALESCE((SELECT SUM(l.line_amount_minor) FROM transaction_lines l
                        WHERE l.transaction_id = t.id AND l.deleted_at IS NULL), 0)
           AS unallocated_minor,
         (SELECT COUNT(*) FROM transaction_lines l
           WHERE l.transaction_id = t.id AND l.deleted_at IS NULL) AS line_count
    FROM transactions t
   WHERE t.deleted_at IS NULL;

-- Grouped by currency as well as month and kind, so nothing here can add rupees to yen
-- (anomaly A34). Conversion to the home currency happens per data point in the currency service.
CREATE VIEW v_monthly_totals AS MonthlyTotalRow AS
  SELECT month_key, kind, original_currency_code AS currency_code,
         SUM(original_amount_minor) AS sum_minor,
         COUNT(*) AS tx_count
    FROM transactions
   WHERE deleted_at IS NULL
   GROUP BY month_key, kind, original_currency_code;

```

### `lib/data/db/views/inventory_views.drift`

```sql
import '../tables/inventory_tables.dart';

-- Per-item stock rollup. `total_remaining_milli` is the SUMMED mixed-unit figure the item row
-- displays ("4 kg 450 g"); the individual batches are shown only when the row is expanded
-- (ARCH_1 §5.4, anomaly A21).
--
-- Batches with zero remaining are excluded from every aggregate here, which is why
-- `batch_count` means "batches still holding stock" and `nearest_expiry_date_key` cannot be
-- dragged earlier by an empty batch. MIN() ignores NULLs, so a no-expiry batch never wins the
-- nearest-expiry slot either.
CREATE VIEW v_item_stock AS ItemStockRow AS
  SELECT i.id AS item_id, i.unit_category, i.low_stock_threshold_milli,
         COALESCE(SUM(b.remaining_quantity_milli), 0) AS total_remaining_milli,
         COUNT(b.id) AS batch_count,
         MIN(b.expiry_date_key) AS nearest_expiry_date_key,
         CASE WHEN i.low_stock_threshold_milli IS NOT NULL
               AND COALESCE(SUM(b.remaining_quantity_milli), 0) < i.low_stock_threshold_milli
              THEN 1 ELSE 0 END AS is_low_stock
    FROM items i
    LEFT JOIN inventory_batches b
           ON b.item_id = i.id AND b.deleted_at IS NULL AND b.remaining_quantity_milli > 0
   WHERE i.deleted_at IS NULL
   GROUP BY i.id;

-- The reconciliation probe for Law L3. `inventory_batches.remaining_quantity_milli` is the
-- schema's only stored total, and this view is how you prove it still matches the append-only
-- ledger: `discrepancy_milli` must be 0 for every row, always.
--
-- The direction of each movement comes from its `kind`, since `quantity_milli` is always
-- positive. Reversal rows need no special handling — a reversing `adjustIn` cancels the
-- `consume` it points at simply by being summed with the opposite sign.
CREATE VIEW v_batch_stock_check AS BatchStockCheckRow AS
  SELECT b.id AS batch_id, b.item_id,
         b.remaining_quantity_milli AS cached_remaining_milli,
         COALESCE((SELECT SUM(CASE WHEN m.kind IN ('openingIn','purchaseIn','manualIn','adjustIn')
                                   THEN m.quantity_milli ELSE -m.quantity_milli END)
                     FROM stock_movements m WHERE m.batch_id = b.id), 0) AS ledger_remaining_milli,
         b.remaining_quantity_milli
           - COALESCE((SELECT SUM(CASE WHEN m.kind IN ('openingIn','purchaseIn','manualIn','adjustIn')
                                       THEN m.quantity_milli ELSE -m.quantity_milli END)
                         FROM stock_movements m WHERE m.batch_id = b.id), 0)
           AS discrepancy_milli
    FROM inventory_batches b
   WHERE b.deleted_at IS NULL;

-- Feeds the low-stock suggestion engine. `shortfall_milli` is how much to buy to reach the
-- threshold, which the generated shopping entry uses as its quantity.
CREATE VIEW v_low_stock AS LowStockRow AS
  SELECT s.item_id, s.unit_category, s.total_remaining_milli, s.low_stock_threshold_milli,
         s.low_stock_threshold_milli - s.total_remaining_milli AS shortfall_milli,
         s.nearest_expiry_date_key
    FROM v_item_stock s
   WHERE s.is_low_stock = 1;

```

### `lib/data/db/views/schedule_views.drift`

```sql
import '../tables/recurring_tables.dart';
import '../tables/service_tables.dart';

-- Active, unpaused templates joined to their outstanding `due` occurrence.
--
-- NOTE ON "overdue": this view deliberately does NOT compute an overdue flag. ARCH_2 §7.2's
-- requirement is that overdue is *derived rather than stored*, and it is — from
-- `occurrence_due_date_key` compared against today. That comparison happens in Dart with the
-- injected Clock, not here, for two reasons. A view containing `strftime('now','localtime')`
-- would be non-deterministic (impossible to test against a FixedClock) and would make a civil
-- date's meaning depend on the process timezone at query time, which is precisely what Law L4
-- exists to prevent. No view in this schema references the current time.
CREATE VIEW v_recurring_due AS RecurringDueRow AS
  SELECT t.id AS template_id, t.name, t.kind, t.direction,
         t.default_amount_minor, t.currency_code,
         t.next_due_date_key, t.interval_unit, t.interval_count,
         t.payee_id, t.default_account_id, t.default_payment_method_id, t.tag_id,
         t.auto_remind, t.remind_days_before,
         o.id AS occurrence_id, o.due_date_key AS occurrence_due_date_key, o.status
    FROM recurring_templates t
    LEFT JOIN recurring_occurrences o
           ON o.template_id = t.id AND o.deleted_at IS NULL AND o.status = 'due'
   WHERE t.deleted_at IS NULL AND t.is_paused = 0;

-- Assets carrying a warranty end or a next-service date, excluding disposed ones.
--
-- ARCH_2 §12 describes this as "within N days", but a view takes no parameters, so the window is
-- applied by the caller: `WHERE warranty_end_date_key BETWEEN ? AND ?`. That is also what lets
-- the query hit idx_asset_warranty / idx_asset_service instead of scanning.
CREATE VIEW v_asset_alerts AS AssetAlertRow AS
  SELECT a.id AS asset_id, a.name, a.type, a.status,
         a.warranty_end_date_key, a.next_service_due_date_key,
         a.service_interval_days, a.primary_contact_name, a.primary_contact_phone
    FROM assets a
   WHERE a.deleted_at IS NULL
     AND a.status <> 'disposed'
     AND (a.warranty_end_date_key IS NOT NULL OR a.next_service_due_date_key IS NOT NULL);

```

### `lib/data/db/views/calendar_view.drift`

```sql
import '../tables/inventory_tables.dart';
import '../tables/money_tables.dart';
import '../tables/recurring_tables.dart';
import '../tables/service_tables.dart';
import '../tables/shopping_tables.dart';

-- The heterogeneous calendar feed (ARCH_3 §6). A view, not a physical events table: six
-- subsystems writing into one events table would be a permanent synchronisation-bug factory, and
-- a UNION ALL has no synchronisation code to get wrong (anomaly A37).
--
-- Six event types across seven arms — `serviceDue` has two sources, `assets.next_service_due_date_key`
-- and `service_records.next_due_date_key`, exactly as ARCH_3 §6 specifies.
--
-- `severity` here is the STATIC baseline for each type. The date-relative escalation ARCH_3 §6
-- describes (warning within 7 days, danger once past) is applied in Dart by the calendar
-- aggregator using the injected Clock — see the note in schedule_views.drift for why no view in
-- this schema references the current time.
--
-- ALWAYS query with a bounded range (`WHERE date_key BETWEEN ? AND ?`). Unbounded, this scans
-- seven tables; bounded, each arm uses its own date index.
--
-- "Medicine expiry" needs no arm of its own: it is a `batchExpiry` on an item whose `item_kind`
-- is `medicine`, which is the whole reason `item_kind` exists.
CREATE VIEW v_calendar_events AS CalendarEventRow AS
  SELECT t.date_key AS date_key, 'transaction' AS event_type,
         'transaction' AS ref_type, t.id AS ref_id,
         COALESCE(p.name, t.note, t.subtype) AS title,
         t.original_amount_minor AS amount_minor,
         t.original_currency_code AS currency_code,
         'info' AS severity
    FROM transactions t
    LEFT JOIN payees p ON p.id = t.payee_id
   WHERE t.deleted_at IS NULL
  UNION ALL
  SELECT o.due_date_key, 'recurringDue', 'recurringOccurrence', o.id,
         rt.name, COALESCE(o.paid_amount_minor, rt.default_amount_minor), rt.currency_code,
         'warning'
    FROM recurring_occurrences o
    JOIN recurring_templates rt ON rt.id = o.template_id
   WHERE o.deleted_at IS NULL AND o.status = 'due' AND rt.deleted_at IS NULL
  UNION ALL
  SELECT b.expiry_date_key, 'batchExpiry', 'inventoryBatch', b.id,
         i.name, NULL, NULL, 'warning'
    FROM inventory_batches b
    JOIN items i ON i.id = b.item_id
   WHERE b.deleted_at IS NULL AND b.expiry_date_key IS NOT NULL
     AND b.remaining_quantity_milli > 0 AND i.deleted_at IS NULL
  UNION ALL
  SELECT a.warranty_end_date_key, 'warrantyEnd', 'asset', a.id,
         a.name, NULL, NULL, 'warning'
    FROM assets a
   WHERE a.deleted_at IS NULL AND a.warranty_end_date_key IS NOT NULL
     AND a.status <> 'disposed'
  UNION ALL
  SELECT a.next_service_due_date_key, 'serviceDue', 'asset', a.id,
         a.name, NULL, NULL, 'warning'
    FROM assets a
   WHERE a.deleted_at IS NULL AND a.next_service_due_date_key IS NOT NULL
     AND a.status <> 'disposed'
  UNION ALL
  SELECT sr.next_due_date_key, 'serviceDue', 'serviceRecord', sr.id,
         a.name, NULL, NULL, 'warning'
    FROM service_records sr
    JOIN assets a ON a.id = sr.asset_id
   WHERE sr.deleted_at IS NULL AND sr.next_due_date_key IS NOT NULL AND a.deleted_at IS NULL
  UNION ALL
  SELECT sl.target_date_key, 'shoppingTarget', 'shoppingList', sl.id,
         sl.name, NULL, NULL, 'info'
    FROM shopping_lists sl
   WHERE sl.deleted_at IS NULL AND sl.target_date_key IS NOT NULL AND sl.is_archived = 0;

```

### `lib/data/daos/settings_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `app_settings`, the single key/value store for everything user-configurable
/// (ARCH_2 §3).
///
/// No view exists for this table, so [_activeRows] is the one place the soft-delete filter is
/// applied and every read routes through it — see the note at the top of `account_dao.dart` for
/// why that is the mechanism here rather than a view.
class SettingsDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  SettingsDao(super.db);

  $AppSettingsTable get _table => attachedDatabase.appSettings;

  SimpleSelectStatement<$AppSettingsTable, AppSettingRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits the value for [key], or null when it is unset or soft-deleted.
  Stream<String?> watchValue(String key) =>
      (_activeRows()..where((t) => t.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => row?.value);

  /// Reads the value for [key] once, or null when unset or soft-deleted.
  Future<String?> readValue(String key) async {
    final row = await (_activeRows()..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// Emits every active setting as a key/value map.
  Stream<Map<String, String>> watchAll() => _activeRows().watch().map(
        (rows) => {for (final row in rows) row.key: row.value},
      );

  /// Reads every active setting once.
  Future<Map<String, String>> readAll() async {
    final rows = await _activeRows().get();
    return {for (final row in rows) row.key: row.value};
  }

  /// Inserts or replaces [key].
  ///
  /// Clears `deletedAt` on write so re-setting a previously deleted key revives it rather than
  /// leaving an invisible row that [_activeRows] would keep filtering out.
  Future<void> writeValue({
    required String key,
    required String value,
    required String valueType,
    required int nowUtcMillis,
  }) {
    return into(_table).insertOnConflictUpdate(
      AppSettingsCompanion.insert(
        key: key,
        value: value,
        valueType: valueType,
        createdAt: nowUtcMillis,
        updatedAt: nowUtcMillis,
        deletedAt: const Value(null),
      ),
    );
  }

  /// Soft-deletes [key].
  Future<void> softDelete({required String key, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.key.equals(key))).write(
      AppSettingsCompanion(
        deletedAt: Value(nowUtcMillis),
        updatedAt: Value(nowUtcMillis),
      ),
    );
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

### `lib/data/daos/unit_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `units` — system and user-defined units, each with an exact integer factor to
/// its category base (ARCH_1 §5.3).
class UnitDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  UnitDao(super.db);

  $UnitsTable get _table => attachedDatabase.units;

  SimpleSelectStatement<$UnitsTable, UnitRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits every active unit in display order.
  Stream<List<UnitRow>> watchAll() =>
      (_activeRows()..orderBy([(t) => OrderingTerm(expression: t.sortOrder)])).watch();

  /// Emits the active units measuring [category].
  ///
  /// A quantity picker must never offer a unit from another category — cross-category conversion
  /// does not exist (Law L8), so offering `ml` for a weight item would produce a value nothing
  /// can convert.
  Stream<List<UnitRow>> watchByCategory(UnitCategory category) {
    return (_activeRows()
          ..where((t) => t.category.equalsValue(category))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Reads one unit by code.
  Future<UnitRow?> byCode(String code) =>
      (_activeRows()..where((t) => t.code.equals(code))).getSingleOrNull();

  /// Reads `code -> factorToBaseMilli` for every active unit.
  ///
  /// The map `UnitConverter` needs. Integer factors only: no step of a unit conversion in this
  /// app touches a double (Law L2).
  Future<Map<String, int>> factorsByCode() async {
    final rows = await _activeRows().get();
    return {for (final row in rows) row.code: row.factorToBaseMilli};
  }

  /// Reads `code -> category`, which is what lets a mapper resolve a `Qty`'s category from a bare
  /// unit code when the row has no linked item (see `qty_converter.dart`).
  Future<Map<String, UnitCategory>> categoriesByCode() async {
    final rows = await _activeRows().get();
    return {for (final row in rows) row.code: row.category};
  }

  /// Inserts or updates a unit.
  Future<void> upsert(UnitsCompanion unit) => into(_table).insertOnConflictUpdate(unit);

  /// Soft-deletes a user-defined unit.
  ///
  /// Returns the number of rows changed, which is 0 when the unit is a system unit — those cannot
  /// be deleted, and the guard is expressed here as a `WHERE` clause so no caller can bypass it
  /// by forgetting to check.
  Future<int> softDeleteUserUnit({required String code, required int nowUtcMillis}) {
    return (update(_table)
          ..where((t) => t.code.equals(code) & t.isSystem.equals(false)))
        .write(
      UnitsCompanion(deletedAt: Value(nowUtcMillis), updatedAt: Value(nowUtcMillis)),
    );
  }
}
```

### `lib/data/daos/tag_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `tags` and the `transaction_tags` link table.
class TagDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  TagDao(super.db);

  $TagsTable get _tags => attachedDatabase.tags;
  $TransactionTagsTable get _links => attachedDatabase.transactionTags;
  $ItemTagsTable get _itemLinks => attachedDatabase.itemTags;
  $AssetTagsTable get _assetLinks => attachedDatabase.assetTags;

  SimpleSelectStatement<$TagsTable, TagRow> _activeRows() =>
      select(_tags)..where((t) => t.deletedAt.isNull());

  /// Maps a [TagScope] onto the matching `allowedIn*` column.
  ///
  /// The single place the scope vocabulary meets the schema. Six near-identical query methods
  /// would be the alternative, and each would be a chance to filter on the wrong column — which
  /// is exactly the bug that would put "Kitchen" in the deposit picker (ARCH_2 §14).
  Expression<bool> _scopeColumn($TagsTable t, TagScope scope) => switch (scope) {
        TagScope.deposit => t.allowedInDeposit,
        TagScope.withdrawal => t.allowedInWithdrawal,
        TagScope.inventory => t.allowedInInventory,
        TagScope.shopping => t.allowedInShopping,
        TagScope.recurring => t.allowedInRecurring,
        TagScope.service => t.allowedInService,
      };

  /// Emits every active tag in display order.
  Stream<List<TagRow>> watchAll() =>
      (_activeRows()..orderBy([(t) => OrderingTerm(expression: t.sortOrder)])).watch();

  /// Emits the active tags offered in [scope]'s picker.
  Stream<List<TagRow>> watchByScope(TagScope scope) {
    return (_activeRows()
          ..where((t) => _scopeColumn(t, scope).equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Reads one tag by id, including a soft-deleted one.
  ///
  /// Deliberately unfiltered: a deleted tag's links survive so history stays readable, and the UI
  /// renders it greyed with `(deleted)` (anomaly A36). Every *listing* query filters; this
  /// single-row lookup must not, or old transactions would show a blank chip.
  Future<TagRow?> byIdIncludingDeleted(String id) =>
      (select(_tags)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads one active tag by its normalized name, for the merge-or-create decision.
  Future<TagRow?> byNormalizedName(String normalizedName) =>
      (_activeRows()..where((t) => t.normalizedName.equals(normalizedName))).getSingleOrNull();

  /// Emits the active children of [parentTagId].
  Stream<List<TagRow>> watchChildrenOf(String parentTagId) {
    return (_activeRows()
          ..where((t) => t.parentTagId.equals(parentTagId))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Emits the active top-level tags — those with no parent.
  Stream<List<TagRow>> watchRoots() {
    return (_activeRows()
          ..where((t) => t.parentTagId.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Inserts or updates a tag.
  Future<void> upsert(TagsCompanion tag) => into(_tags).insertOnConflictUpdate(tag);

  /// Soft-deletes a user-created tag.
  ///
  /// Returns 0 rows changed for a system tag; like [UnitDao.softDeleteUserUnit] the guard is a
  /// `WHERE` clause rather than a caller-side check, so it cannot be forgotten (ARCH_3 §4.1).
  Future<int> softDeleteUserTag({required String id, required int nowUtcMillis}) {
    return (update(_tags)..where((t) => t.id.equals(id) & t.isSystem.equals(false))).write(
      TagsCompanion(deletedAt: Value(nowUtcMillis), updatedAt: Value(nowUtcMillis)),
    );
  }

  // ── transaction_tags links ─────────────────────────────────────────────────────────────

  /// Emits the tags attached to [transactionId], soft-deleted ones included.
  ///
  /// Includes deleted tags for the same reason as [byIdIncludingDeleted]: the link is history.
  Stream<List<TagRow>> watchForTransaction(String transactionId) {
    final query = select(_links).join([
      innerJoin(_tags, _tags.id.equalsExp(_links.tagId)),
    ])
      ..where(_links.transactionId.equals(transactionId))
      ..orderBy([OrderingTerm(expression: _tags.sortOrder)]);
    return query.watch().map((rows) => rows.map((row) => row.readTable(_tags)).toList());
  }

  /// Replaces the whole tag set for [transactionId], in one transaction (Law L14).
  ///
  /// Delete-then-insert rather than a diff: `transaction_tags` has no soft delete, so removing a
  /// link is a real delete and a set replacement is the honest operation. Both statements are in
  /// one transaction so a failure cannot leave a transaction with no tags at all.
  Future<void> setTransactionTags({
    required String transactionId,
    required List<String> tagIds,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      await (delete(_links)..where((t) => t.transactionId.equals(transactionId))).go();
      for (final tagId in tagIds) {
        await into(_links).insert(
          TransactionTagsCompanion.insert(
            transactionId: transactionId,
            tagId: tagId,
            createdAt: nowUtcMillis,
            updatedAt: nowUtcMillis,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  /// Emits the tags attached to [itemId], in tag sort order.
  ///
  /// **`item_tags` was created in Phase 2C and had no reader until now.** Phase 6B needed it to group a
  /// catalogue and shipped grouping by `itemKind` instead; the row has been open in ARCH_5 §7.3 ever
  /// since. The shape is `watchForTransaction`'s exactly — one join, ordered by the tag rather than the
  /// link, so the ordering a user set in Settings is the ordering they see everywhere.
  Stream<List<TagRow>> watchForItem(String itemId) {
    final query = select(_itemLinks).join([
      innerJoin(_tags, _tags.id.equalsExp(_itemLinks.tagId)),
    ])
      ..where(_itemLinks.itemId.equals(itemId))
      ..orderBy([OrderingTerm(expression: _tags.sortOrder)]);
    return query.watch().map((rows) => rows.map((row) => row.readTable(_tags)).toList());
  }

  /// Replaces the tags attached to [itemId] with [tagIds].
  ///
  /// **Delete-then-insert inside one transaction, as `setTransactionTags` does.** A diff would be fewer
  /// writes and more code, and the link table carries nothing worth preserving — no id of its own, no
  /// audit trail anyone reads, and a composite primary key that makes re-insertion idempotent. Law L6's
  /// soft-delete rule governs entities, not the join rows that associate them.
  Future<void> setItemTags({
    required String itemId,
    required List<String> tagIds,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      await (delete(_itemLinks)..where((t) => t.itemId.equals(itemId))).go();
      for (final tagId in tagIds) {
        await into(_itemLinks).insert(
          ItemTagsCompanion.insert(
            itemId: itemId,
            tagId: tagId,
            createdAt: nowUtcMillis,
            updatedAt: nowUtcMillis,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  /// Emits the tags attached to [assetId], in tag sort order.
  ///
  /// `asset_tags` has been open since Phase 6E for the same reason `item_tags` was: the table existed and
  /// the contract did not, so the asset list groups by `type` instead.
  Stream<List<TagRow>> watchForAsset(String assetId) {
    final query = select(_assetLinks).join([
      innerJoin(_tags, _tags.id.equalsExp(_assetLinks.tagId)),
    ])
      ..where(_assetLinks.assetId.equals(assetId))
      ..orderBy([OrderingTerm(expression: _tags.sortOrder)]);
    return query.watch().map((rows) => rows.map((row) => row.readTable(_tags)).toList());
  }

  /// Replaces the tags attached to [assetId] with [tagIds].
  Future<void> setAssetTags({
    required String assetId,
    required List<String> tagIds,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      await (delete(_assetLinks)..where((t) => t.assetId.equals(assetId))).go();
      for (final tagId in tagIds) {
        await into(_assetLinks).insert(
          AssetTagsCompanion.insert(
            assetId: assetId,
            tagId: tagId,
            createdAt: nowUtcMillis,
            updatedAt: nowUtcMillis,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  /// Counts how many active transactions carry [tagId], for the "in use" check before deleting.
  Future<int> activeTransactionCount(String tagId) async {
    final count = countAll();
    final row = await (selectOnly(_links).join([
      innerJoin(
        attachedDatabase.transactions,
        attachedDatabase.transactions.id.equalsExp(_links.transactionId),
      ),
    ])
          ..addColumns([count])
          ..where(_links.tagId.equals(tagId) &
              attachedDatabase.transactions.deletedAt.isNull()))
        .getSingle();
    return row.read(count) ?? 0;
  }
}
```

### `lib/data/daos/account_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `accounts`, plus the two views that derive money from them.
///
/// **On Law L7 and this phase's "all reads go through views" rule.** Of the eleven money-side
/// tables, only `accounts` and `transactions` have views (ARCH_2 §12) — the nine reference and
/// link tables have none. Adding a pass-through `v_active_currencies` and friends would satisfy
/// the rule's letter and make the codebase worse: each would generate a *second* row class with
/// fields identical to the table's, so every Phase 3B mapper would have to know which of
/// `CurrencyRow` and `ActiveCurrencyRow` it holds, and every schema snapshot would carry nine
/// objects that answer no question a `WHERE` clause does not.
///
/// So L7's stated purpose — that `deletedAt IS NULL` "cannot be forgotten" — is met here by
/// structure rather than by a view: every DAO in this phase funnels its reads through one private
/// `_activeRows()` builder, and no public method returns unfiltered rows except the explicitly
/// named `byIdIncludingDeleted`. Repositories never write SQL, so they cannot bypass it. Where a
/// view *does* exist it is used, always — balances and ledger legs below are never recomputed in
/// Dart.
class AccountDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  AccountDao(super.db);

  $AccountsTable get _table => attachedDatabase.accounts;

  SimpleSelectStatement<$AccountsTable, AccountRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits active, unarchived accounts in display order — the picker list.
  Stream<List<AccountRow>> watchSelectable() {
    return (_activeRows()
          ..where((t) => t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Emits every active account, archived included.
  ///
  /// Archived accounts still count toward totals and net worth — they have simply left the
  /// pickers. Conflating archive with delete is the distinction ARCH_3 §4 exists to preserve.
  Stream<List<AccountRow>> watchAllIncludingArchived() {
    return (_activeRows()
          ..orderBy([
            (t) => OrderingTerm(expression: t.isArchived),
            (t) => OrderingTerm(expression: t.sortOrder),
          ]))
        .watch();
  }

  /// Reads one account by id, including a soft-deleted one.
  Future<AccountRow?> byIdIncludingDeleted(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads one active account by normalized name, for the duplicate check.
  Future<AccountRow?> byNormalizedName(String normalizedName) =>
      (_activeRows()..where((t) => t.normalizedName.equals(normalizedName))).getSingleOrNull();

  // ── derived money: always from the views ───────────────────────────────────────────────

  /// Emits every active account's balance, each in its own currency.
  ///
  /// Reads `v_account_balances`, which is `openingBalanceMinor + Σ ledger legs`. Never sum these
  /// across accounts without converting first — they may be in different currencies (A34).
  Stream<List<AccountBalanceRow>> watchBalances() =>
      select(attachedDatabase.vAccountBalances).watch();

  /// Emits one account's balance.
  Stream<AccountBalanceRow?> watchBalanceOf(String accountId) {
    return (select(attachedDatabase.vAccountBalances)
          ..where((t) => t.accountId.equals(accountId)))
        .watchSingleOrNull();
  }

  /// Reads one account's balance once.
  Future<AccountBalanceRow?> balanceOf(String accountId) {
    return (select(attachedDatabase.vAccountBalances)
          ..where((t) => t.accountId.equals(accountId)))
        .getSingleOrNull();
  }

  /// Emits the signed ledger legs touching [accountId], newest first.
  ///
  /// A `transfer` contributes two legs across two accounts, so filtering by account correctly
  /// yields only that account's side of it (ARCH_2 §12.1).
  Stream<List<AccountLedgerRow>> watchLedger(String accountId) {
    return (select(attachedDatabase.vAccountLedger)
          ..where((t) => t.accountId.equals(accountId))
          ..orderBy([(t) => OrderingTerm(expression: t.dateKey, mode: OrderingMode.desc)]))
        .watch();
  }

  /// Emits `(accountId, currencyCode, balanceMinor)` for every active account with
  /// `includeInNetWorth = true`.
  ///
  /// A single joined query rather than combining two separate streams in Dart.
  /// `v_account_balances` carries no `includeInNetWorth` column — the view's own `SELECT` list is
  /// exactly what a balance needs, nothing more — so this reads the view and `accounts` together
  /// in one `customSelect`, with `readsFrom` stated explicitly since a raw SQL string cannot be
  /// statically analysed for its table dependencies the way a query-builder call can.
  Stream<List<({String accountId, String currencyCode, int balanceMinor})>>
      watchNetWorthEligibleBalances() {
    return customSelect(
      'SELECT b.account_id, b.currency_code, b.balance_minor '
      'FROM v_account_balances b JOIN accounts a ON a.id = b.account_id '
      'WHERE a.include_in_net_worth = 1',
      readsFrom: {attachedDatabase.vAccountBalances, _table},
    ).watch().map(
          (rows) => rows
              .map(
                (row) => (
                  accountId: row.read<String>('account_id'),
                  currencyCode: row.read<String>('currency_code'),
                  balanceMinor: row.read<int>('balance_minor'),
                ),
              )
              .toList(),
        );
  }

  // ── writes ────────────────────────────────────────────────────────────────────────────

  /// Inserts or updates an account.
  Future<void> upsert(AccountsCompanion account) => into(_table).insertOnConflictUpdate(account);

  /// Archives or unarchives an account.
  Future<void> setArchived({
    required String id,
    required bool isArchived,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(isArchived: Value(isArchived), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Soft-deletes an account.
  ///
  /// Deliberately unguarded here. ARCH_3 §4.1 requires deleting an account with live transactions
  /// to be *blocked* with Archive offered instead — but that is a business rule, and this layer
  /// holds none. Phase 3B's repository calls [activeTransactionCount] first and returns a failure.
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(deletedAt: Value(nowUtcMillis), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Counts active transactions on either side of [accountId] — the input to that block.
  Future<int> activeTransactionCount(String accountId) async {
    final transactions = attachedDatabase.transactions;
    final count = countAll();
    final row = await (selectOnly(transactions)
          ..addColumns([count])
          ..where(transactions.deletedAt.isNull() &
              (transactions.fromAccountId.equals(accountId) |
                  transactions.toAccountId.equals(accountId))))
        .getSingle();
    return row.read(count) ?? 0;
  }
}
```

### `lib/data/daos/payment_method_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `payment_methods` — the rail money travelled on, which never holds a balance
/// (ARCH_1 §3.1).
class PaymentMethodDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  PaymentMethodDao(super.db);

  $PaymentMethodsTable get _table => attachedDatabase.paymentMethods;

  SimpleSelectStatement<$PaymentMethodsTable, PaymentMethodRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits every active payment method in display order.
  Stream<List<PaymentMethodRow>> watchAll() =>
      (_activeRows()..orderBy([(t) => OrderingTerm(expression: t.sortOrder)])).watch();

  /// Reads one payment method by id, including a soft-deleted one, so historical transactions
  /// still render a name.
  Future<PaymentMethodRow?> byIdIncludingDeleted(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Inserts or updates a payment method.
  Future<void> upsert(PaymentMethodsCompanion method) =>
      into(_table).insertOnConflictUpdate(method);

  /// Soft-deletes a user-created payment method; 0 rows changed for a system one.
  Future<int> softDeleteUserMethod({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id) & t.isSystem.equals(false))).write(
      PaymentMethodsCompanion(
        deletedAt: Value(nowUtcMillis),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Counts active transactions using [methodId], for the "in use" check.
  Future<int> activeTransactionCount(String methodId) async {
    final transactions = attachedDatabase.transactions;
    final count = countAll();
    final row = await (selectOnly(transactions)
          ..addColumns([count])
          ..where(transactions.paymentMethodId.equals(methodId) &
              transactions.deletedAt.isNull()))
        .getSingle();
    return row.read(count) ?? 0;
  }
}
```

### `lib/data/daos/payee_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `payees` — the counterparty, used for both `From` on deposits and `To` on
/// withdrawals (ARCH_1 §3.1).
class PayeeDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  PayeeDao(super.db);

  $PayeesTable get _table => attachedDatabase.payees;

  SimpleSelectStatement<$PayeesTable, PayeeRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits every active payee, alphabetically.
  Stream<List<PayeeRow>> watchAll() =>
      (_activeRows()..orderBy([(t) => OrderingTerm(expression: t.normalizedName)])).watch();

  /// Reads one payee by id, including a soft-deleted one.
  Future<PayeeRow?> byIdIncludingDeleted(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads one active payee by normalized name, for the merge-or-create decision.
  ///
  /// `idx_payees_name` is a partial unique index on this column, so at most one active row can
  /// match — which is why this returns a single row rather than a list.
  Future<PayeeRow?> byNormalizedName(String normalizedName) =>
      (_activeRows()..where((t) => t.normalizedName.equals(normalizedName))).getSingleOrNull();

  /// Emits active payees whose normalized name contains [term], for the picker's search field.
  Stream<List<PayeeRow>> watchMatching(String term) {
    final needle = '%${term.toLowerCase()}%';
    return (_activeRows()
          ..where((t) => t.normalizedName.like(needle))
          ..orderBy([(t) => OrderingTerm(expression: t.normalizedName)])
          ..limit(50))
        .watch();
  }

  /// Inserts or updates a payee.
  Future<void> upsert(PayeesCompanion payee) => into(_table).insertOnConflictUpdate(payee);

  /// Soft-deletes a payee.
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      PayeesCompanion(deletedAt: Value(nowUtcMillis), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Counts active transactions naming [payeeId], for the "in use" check.
  Future<int> activeTransactionCount(String payeeId) async {
    final transactions = attachedDatabase.transactions;
    final count = countAll();
    final row = await (selectOnly(transactions)
          ..addColumns([count])
          ..where(transactions.payeeId.equals(payeeId) & transactions.deletedAt.isNull()))
        .getSingle();
    return row.read(count) ?? 0;
  }
}
```

### `lib/data/daos/transaction_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/date_key_filters.dart';

/// Typed access to `transactions`, its lines and tags, and the three views derived from them.
///
/// Every read here goes through `v_active_transactions`, `v_monthly_totals` or
/// `v_transaction_allocation` (Law L7) — the base table is touched only by writes and by the
/// `rowid` join full-text search needs.
class TransactionDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  TransactionDao(super.db);

  $TransactionsTable get _table => attachedDatabase.transactions;
  // Type inferred deliberately. The row class name is fixed by `AS ActiveTransactionRow`
  // in transaction_views.drift, but drift's name for a view's *table* class is not
  // something this file should assert; inference gets it right whatever it is called.
  late final _active = attachedDatabase.vActiveTransactions;

  // ── writes ────────────────────────────────────────────────────────────────────────────

  /// Inserts a transaction together with its lines and tags, atomically (Law L14).
  ///
  /// Three tables in one `transaction {}`. Without it a crash between statements would leave a
  /// transaction whose lines are missing — and `v_transaction_allocation` would then report the
  /// whole amount as unallocated, which looks exactly like a user who has not itemised yet.
  ///
  /// `monthKey` is *not* derived here. It is a required column on the companion and the schema's
  /// third CHECK constraint enforces `date_key / 100 = month_key`, so a caller that gets it wrong
  /// is rejected by the database rather than silently producing a transaction that is invisible to
  /// monthly analytics. Deriving it here would hide that error.
  Future<void> insertWithDetails({
    required TransactionsCompanion header,
    List<TransactionLinesCompanion> lines = const [],
    List<String> tagIds = const [],
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      await into(_table).insert(header);
      for (final line in lines) {
        await into(attachedDatabase.transactionLines).insert(line);
      }
      for (final tagId in tagIds) {
        await into(attachedDatabase.transactionTags).insert(
          TransactionTagsCompanion.insert(
            transactionId: header.id.value,
            tagId: tagId,
            createdAt: nowUtcMillis,
            updatedAt: nowUtcMillis,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  /// Updates a transaction's own columns. Lines and tags are replaced separately.
  Future<void> updateTransaction(TransactionsCompanion header) =>
      update(_table).replace(header);

  /// Soft-deletes a transaction and its lines, atomically (Law L14).
  ///
  /// Cascades to `transaction_lines` and nothing else. Batches and assets a line created are
  /// deliberately untouched: you deleted a receipt, not the groceries (anomaly A10). Detaching
  /// those artefacts is the repository's job, via
  /// [TransactionLineDao.clearCreatedArtefacts].
  ///
  /// `transaction_tags` links are left in place too — they carry no soft-delete column and the
  /// transaction they point at is already filtered out of every view.
  Future<void> softDelete({
    required String id,
    String? reason,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      await (update(_table)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
          deleteReason: reason == null ? const Value.absent() : Value(reason),
        ),
      );
      await (update(attachedDatabase.transactionLines)
            ..where((t) => t.transactionId.equals(id) & t.deletedAt.isNull()))
          .write(
        TransactionLinesCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );
    });
  }

  /// Clears `needsReview` once the user has filled in the details quick-add skipped.
  Future<void> markReviewed({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(needsReview: const Value(false), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Writes the frozen conversion snapshot for one transaction.
  ///
  /// Only ever writes the `converted*` columns. `originalAmountMinor` and
  /// `originalCurrencyCode` are immutable once saved (Law L9) and are not parameters here, so this
  /// method cannot rewrite them even by mistake.
  Future<void> freezeConversion({
    required String id,
    required int convertedAmountMinor,
    required String convertedCurrencyCode,
    required double conversionRate,
    required String conversionRateRaw,
    required DateKey conversionDateKey,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        convertedAmountMinor: Value(convertedAmountMinor),
        convertedCurrencyCode: Value(convertedCurrencyCode),
        conversionRate: Value(conversionRate),
        conversionRateRaw: Value(conversionRateRaw),
        conversionDateKey: Value(conversionDateKey),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  // ── reads: all through the views ──────────────────────────────────────────────────────

  /// Reads one active transaction by id.
  Future<ActiveTransactionRow?> byId(String id) =>
      (select(_active)..where((t) => t.txId.equals(id))).getSingleOrNull();

  /// Emits active transactions whose civil date falls in `[from, to]`, newest first.
  ///
  /// Inclusive at both ends, and always bounded so the query uses `idx_tx_date`.
  Stream<List<ActiveTransactionRow>> watchByDateRange({
    required DateKey from,
    required DateKey to,
  }) {
    return (select(_active)
          ..where((t) => t.dateKey.isInDateRange(from, to))
          ..orderBy([
            (t) => OrderingTerm(expression: t.dateKey, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.occurredAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  /// Emits active transactions touching [accountId] on either side, newest first.
  ///
  /// Matches both `fromAccountId` and `toAccountId`, so a transfer appears in both accounts'
  /// lists — once as an outflow and once as an inflow, which is what the user expects to see.
  Stream<List<ActiveTransactionRow>> watchByAccount(String accountId) {
    return (select(_active)
          ..where((t) =>
              t.fromAccountId.equals(accountId) | t.toAccountId.equals(accountId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.dateKey, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.occurredAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  /// Emits active transactions of [subtype], newest first, optionally bounded by month.
  Stream<List<ActiveTransactionRow>> watchBySubtype(
    TransactionSubtype subtype, {
    int? fromMonthKey,
    int? toMonthKey,
  }) {
    final query = select(_active)..where((t) => t.subtype.equalsValue(subtype));
    if (fromMonthKey != null) {
      query.where((t) => t.monthKey.isBiggerOrEqualValue(fromMonthKey));
    }
    if (toMonthKey != null) {
      query.where((t) => t.monthKey.isSmallerOrEqualValue(toMonthKey));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.dateKey, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.occurredAt, mode: OrderingMode.desc),
    ]);
    return query.watch();
  }

  /// Emits active transactions still flagged `needsReview`, for the dashboard nudge.
  Stream<List<ActiveTransactionRow>> watchNeedingReview() {
    return (select(_active)
          ..where((t) => t.needsReview.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.dateKey, mode: OrderingMode.desc)]))
        .watch();
  }

  /// Emits the count of transactions needing review.
  Stream<int> watchNeedsReviewCount() {
    final count = countAll();
    return (selectOnly(_active)
          ..addColumns([count])
          ..where(_active.needsReview.equals(true)))
        .map((row) => row.read(count) ?? 0)
        .watchSingle();
  }

  /// Emits `(monthKey, kind, currencyCode) -> (sumMinor, txCount)` from `v_monthly_totals`.
  ///
  /// Grouped by currency, so nothing here can add rupees to yen (anomaly A34) — conversion to the
  /// home currency happens per data point in the currency service, above this layer.
  Stream<List<MonthlyTotalRow>> watchMonthlyTotals({
    int? fromMonthKey,
    int? toMonthKey,
  }) {
    final view = attachedDatabase.vMonthlyTotals;
    final query = select(view);
    if (fromMonthKey != null) {
      query.where((t) => t.monthKey.isBiggerOrEqualValue(fromMonthKey));
    }
    if (toMonthKey != null) {
      query.where((t) => t.monthKey.isSmallerOrEqualValue(toMonthKey));
    }
    query.orderBy([(t) => OrderingTerm(expression: t.monthKey, mode: OrderingMode.desc)]);
    return query.watch();
  }

  /// Reads the monthly totals once.
  Future<List<MonthlyTotalRow>> monthlyTotals({int? fromMonthKey, int? toMonthKey}) {
    final view = attachedDatabase.vMonthlyTotals;
    final query = select(view);
    if (fromMonthKey != null) {
      query.where((t) => t.monthKey.isBiggerOrEqualValue(fromMonthKey));
    }
    if (toMonthKey != null) {
      query.where((t) => t.monthKey.isSmallerOrEqualValue(toMonthKey));
    }
    query.orderBy([(t) => OrderingTerm(expression: t.monthKey, mode: OrderingMode.desc)]);
    return query.get();
  }

  // ── full-text search ──────────────────────────────────────────────────────────────────

  /// Full-text search over transaction notes, best match first.
  ///
  /// Two steps by design. FTS5 returns `rowid`s ranked by relevance, so the first query resolves
  /// those to transaction ids and the second reads the matching rows from `v_active_transactions`
  /// — which is what keeps soft-deleted transactions out of the results, since the FTS index knows
  /// nothing about `deletedAt`. Rank order is then restored in Dart, because a typed `WHERE id IN
  /// (...)` cannot preserve it.
  Future<List<ActiveTransactionRow>> search(String query, {int limit = 50}) async {
    final ids = await searchIds(query, limit: limit);
    if (ids.isEmpty) return const [];

    final rows = await (select(_active)..where((t) => t.txId.isIn(ids))).get();
    final byId = {for (final row in rows) row.txId: row};
    return [
      for (final id in ids)
        if (byId[id] case final row?) row,
    ];
  }

  /// The ranked transaction ids matching [query], most relevant first.
  ///
  /// Returns an empty list for input with no usable characters rather than running a MATCH that
  /// would throw — see [_toFtsMatchQuery].
  Future<List<String>> searchIds(String query, {int limit = 50}) async {
    final match = _toFtsMatchQuery(query);
    if (match == null) return const [];

    final rows = await customSelect(
      'SELECT base.id AS id FROM transactions_fts f '
      'JOIN transactions base ON base.rowid = f.rowid '
      'WHERE transactions_fts MATCH ? AND base.deleted_at IS NULL '
      'ORDER BY rank LIMIT ?',
      variables: [Variable<String>(match), Variable<int>(limit)],
      readsFrom: {_table},
    ).get();
    return rows.map((row) => row.read<String>('id')).toList();
  }

  /// Turns raw user input into a safe FTS5 MATCH expression, or null if nothing is searchable.
  ///
  /// Necessary rather than defensive. FTS5's MATCH grammar treats `"`, `*`, `:`, `^`, `-`, `(`,
  /// `)` and the bare words `AND`/`OR`/`NOT`/`NEAR` as syntax, so raw input raises a syntax error
  /// inside what the user thinks is a search box. Verified against a real FTS5 index: `rent (July)
  /// - paid`, `AND` and `foo"bar` all throw unescaped, and `***` fails with "unknown special
  /// query". Each run of letters, digits and combining marks becomes one double-quoted term with a
  /// trailing `*` for prefix matching, space-joined, which FTS5 reads as implicit AND.
  ///
  /// `\p{M}` matters as much as `\p{L}` here. Devanagari and Gujarati vowel signs are Unicode
  /// category M, not L, so `[\p{L}\p{N}]+` alone splits `टमाटर` into `टम` and `टर` — search would
  /// quietly stop working for exactly the languages this app's first users type in. Same bug class
  /// as the one fixed in Phase 1A's `Normalizer`.
  String? _toFtsMatchQuery(String raw) {
    final tokens = RegExp(r'[\p{L}\p{N}\p{M}]+', unicode: true)
        .allMatches(raw)
        .map((m) => m.group(0)!)
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return null;
    return tokens.map((t) => '"$t"*').join(' ');
  }
}
```

### `lib/data/daos/transaction_line_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `transaction_lines` and the allocation view derived from them.
class TransactionLineDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  TransactionLineDao(super.db);

  $TransactionLinesTable get _table => attachedDatabase.transactionLines;

  SimpleSelectStatement<$TransactionLinesTable, TransactionLineRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits the active lines of [transactionId], in entry order.
  Stream<List<TransactionLineRow>> watchForTransaction(String transactionId) {
    return (_activeRows()
          ..where((t) => t.transactionId.equals(transactionId))
          ..orderBy([(t) => OrderingTerm(expression: t.lineNo)]))
        .watch();
  }

  /// Reads the active lines of [transactionId] once.
  Future<List<TransactionLineRow>> forTransaction(String transactionId) {
    return (_activeRows()
          ..where((t) => t.transactionId.equals(transactionId))
          ..orderBy([(t) => OrderingTerm(expression: t.lineNo)]))
        .get();
  }

  /// Emits the allocation summary for [transactionId] from `v_transaction_allocation`.
  ///
  /// Check `lineCount` before showing an unallocated chip: with no lines at all
  /// `unallocatedMinor` equals the full amount, which is not the same thing as a mismatch
  /// (anomaly A11).
  Stream<TransactionAllocationRow?> watchAllocation(String transactionId) {
    return (select(attachedDatabase.vTransactionAllocation)
          ..where((t) => t.txId.equals(transactionId)))
        .watchSingleOrNull();
  }

  /// Emits every active line referencing [itemId], newest first — an item's purchase history.
  ///
  /// The basis of the unit-price trend and price-per-base-unit insights (ARCH_3 §5.1 queries 12
  /// and 24). `quantityMilli` is already in base-milli units, so no conversion is needed.
  Stream<List<TransactionLineRow>> watchForItem(String itemId) {
    return (_activeRows()
          ..where((t) => t.itemId.equals(itemId))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]))
        .watch();
  }

  /// Replaces every line of [transactionId] in one transaction (Law L14).
  ///
  /// Existing lines are soft-deleted rather than removed, because a line may already have created
  /// a batch or an asset and `created*Id` is the only record of that link (anomaly A12). Deleting
  /// the row would orphan the artefact silently.
  Future<void> replaceLines({
    required String transactionId,
    required List<TransactionLinesCompanion> lines,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      await (update(_table)
            ..where((t) => t.transactionId.equals(transactionId) & t.deletedAt.isNull()))
          .write(
        TransactionLinesCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );
      for (final line in lines) {
        await into(_table).insert(line);
      }
    });
  }

  /// Inserts one line.
  Future<void> insertLine(TransactionLinesCompanion line) => into(_table).insert(line);

  /// Soft-deletes one line.
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      TransactionLinesCompanion(
        deletedAt: Value(nowUtcMillis),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Records which artefact a line produced, after the fan-out service created it.
  ///
  /// Exactly one of the three ids is ever set for a given line, matching its `destination`
  /// (ARCH_2 §4.2) — this method writes whichever was supplied and leaves the others untouched.
  Future<void> setCreatedArtefact({
    required String lineId,
    required int nowUtcMillis,
    String? createdBatchId,
    String? createdAssetId,
    String? createdRecurringTemplateId,
  }) {
    return (update(_table)..where((t) => t.id.equals(lineId))).write(
      TransactionLinesCompanion(
        createdBatchId:
            createdBatchId == null ? const Value.absent() : Value(createdBatchId),
        createdAssetId:
            createdAssetId == null ? const Value.absent() : Value(createdAssetId),
        createdRecurringTemplateId: createdRecurringTemplateId == null
            ? const Value.absent()
            : Value(createdRecurringTemplateId),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Clears the link from [lineId] to whatever it created, without touching the artefact.
  ///
  /// The detach half of anomaly A10: deleting a receipt must not delete food already eaten, so the
  /// pointer is nulled and the batch's `origin` becomes `detached` by the caller.
  Future<void> clearCreatedArtefacts({
    required String lineId,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(lineId))).write(
      TransactionLinesCompanion(
        createdBatchId: const Value(null),
        createdAssetId: const Value(null),
        createdRecurringTemplateId: const Value(null),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }
}
```
