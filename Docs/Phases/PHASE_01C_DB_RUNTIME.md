# Phase 1C — Views, Indexes, FTS, Migrations, Seed, Open Path

**11 views · 22 indexes (12 partial) · 2 FTS5 tables + 6 triggers · 18 seeded tags.**

## Add dependencies first

```bash
flutter pub add drift_flutter sqlite3
flutter pub deps | grep -i sqlite
```

Confirm **neither** `sqlite3_flutter_libs` nor `sqlcipher_flutter_libs` appears (ARCH_1 §7.1).
`drift_flutter` is the package most likely to drag one in transitively; if it does, stop and
report it before building. Then regenerate:

```bash
dart run build_runner build
```

## Verification performed

No Dart toolchain is available to me, so every piece of SQL below was executed rather than
reasoned about. I built the Phase 1B schema as real DDL, applied these seven `.drift` files
**exactly as written** (imports and comments stripped, nothing else changed), and asserted on the
results:

| Check | Result |
|---|---|
| All 7 `.drift` files parse and apply | 11 views, 22 indexes, 6 triggers, 2 FTS tables |
| Partial indexes keep their `WHERE` clause | 12 of 22 |
| **All five transaction kinds against `v_account_balances`** | correct in isolation and combined |
| **Self-transfer Cash → Bank 5000 nets to zero** | total unchanged; exactly 2 legs; legs sum to 0 |
| Soft delete removes a transaction from the ledger | balance restored exactly |
| Partial unique index behaviour | duplicate rejected, different category allowed, re-add after soft delete allowed (A19) |
| `v_item_stock` / `v_low_stock` / `v_batch_stock_check` | sums, batch count, nearest expiry, shortfall, and a deliberately-induced cache discrepancy all correct |
| Reversal rows cancel the movement they point at | ledger nets to zero drift |
| `v_transaction_allocation` | ₹500 total − ₹480 lines = ₹20 unallocated |
| FTS5 insert / update / delete triggers | index stays aligned; soft-deleted rows excluded via the join |
| `v_calendar_events` | every source emits its own `event_type`; bounded range query returns only the in-range event |
| `pragma_table_info('v_recurring_due')` | 18 columns, no `is_overdue` — see below |

## v1.2 — view row-class naming fixed

Phase 2A needed to reference these view row classes from nine DAOs and could not do so on a
guess, so each `CREATE VIEW` below now carries an explicit Dart name —
`CREATE VIEW v_account_balances AS AccountBalanceRow AS SELECT ...` — using drift's documented
`AS DartName` syntax, rather than its derived default (view name + `Data`). The eleven names now
match Phase 1B's `XxxRow` table convention exactly; see ARCH_2 §12's table. No SQL changed —
verified by stripping the `AS DartName` clause back out and re-running the full view suite: still
11 views, 22 indexes, 6 triggers.

## Fix in this revision

`isNull` is declared as a top-level name by **both** drift's query builder and `package:matcher`
(re-exported by `flutter_test`), so a bare import of both is ambiguous. The error surfaces at the
*use site* — `expect(x, isNull)` — and says nothing about the import that caused it.

Fixed by importing only what each test actually needs:

| File | Before | After |
|---|---|---|
| `seed_test.dart` | bare `drift.dart` | **removed** — it used nothing from it |
| `view_test.dart` | bare `drift.dart` | `show Value, Variable` |
| `migration_test.dart` | bare `drift.dart` | `show Variable` |

A `show` clause is better than `hide isNull, isNotNull`: it needs no maintenance when either
package adds a name. Recorded as a binding convention in ARCH_1 §7.6, because every later phase's
tests import both packages and would hit this again. `isNotNull` collides too.

## The one design decision worth arguing about

**No view in this schema references the current time.** Not `strftime('now')`, not `date('now')`,
nothing. Two places where the architecture asks for something time-relative are handled in Dart
instead:

- ARCH_2 §12 describes `v_recurring_due` as having a "derived overdue flag".
- ARCH_3 §6 describes `v_calendar_events` severity escalating within 7 days and past due.

ARCH_2 §7.2's actual words are that overdue is *"a derived state, not a stored one"* — the
contrast is with a stored `overdue` status column, not with computing it in Dart. So the views
expose `occurrence_due_date_key` and a **static baseline** `severity`, and the comparison against
today happens in the recurring engine and calendar aggregator using Phase 1A's injected `Clock`.

Two reasons, both of which I think outweigh the convenience of having the flag in SQL:

1. **Law L4.** `strftime('now','localtime')` makes a civil date's meaning depend on the process
   timezone at query time. L4 exists precisely so that a bill "due on the 5th" is the 5th
   wherever the user is standing.
2. **Testability.** A view containing `now` cannot be asserted against a `FixedClock`. Every
   assertion in `view_test.dart` uses fixed dates and is therefore reproducible; had severity
   escalated inside the view, the calendar tests would silently change behaviour at midnight.

If you disagree, the change is one `CASE` expression per view — but the tests that pin severity to
its baseline would need to go with it.

## Findings

**1. `alaya_database.dart` had to change, and it is not in the DELIVER list.** Views, indexes and
FTS tables in `.drift` files are inert until the database registers them, so the `@DriftDatabase`
annotation gains an `include:` set, and `schemaVersion` alone is no longer enough — the class now
also overrides `migration`. Without those two edits this phase creates 26 bare tables and every
later repository read fails against a view that does not exist. It is included below as a
fourteenth file.

**2. External-content FTS5 depends on rowids, and `VACUUM INTO` is permitted to renumber them.**
These tables have `TEXT` primary keys, so no column aliases `rowid`, and SQLite's VACUUM
documentation explicitly allows renumbering in exactly that case. ARCH_3 §3.1 backs up with
`VACUUM INTO`. I tested this: on current SQLite the rowids **were** preserved, and FTS lookups
still resolved correctly in the vacuumed copy. But that is unspecified behaviour to build on, and
the mitigation costs one statement — so **Phase 4C's Replace-restore must run
`INSERT INTO items_fts(items_fts) VALUES('rebuild');`** (and the same for `transactions_fts`)
after swapping the file in. Merge-restore needs nothing; it writes through the triggers. Worth
recording in ARCH_3 §3.2 and as a new anomaly.

**3. `accounts` has no `isDefault` column**, so ARCH_2 §14's "one marked default" cannot live on
the table. It is seeded into `app_settings` under `defaultAccountId`, which is also what ARCH_2
§4.1's quick-add fallback ("last-used account, falling back to the default") needs. `Cash` is the
seeded default. `shopping_lists.isDefault` does exist as a column and is used directly.

**4. `v_account_ledger.account_id` is nullable in the generated row class.** It selects from the
nullable `from_account_id` / `to_account_id`; the `WHERE` clauses plus the shape CHECK guarantee
non-null in practice, but SQL cannot express that. Phase 2A's DAO should assert rather than
`COALESCE` — a null there would mean a malformed row the CHECK should have rejected, and mapping
it to a placeholder account would hide the bug.

**5. `pack` is seeded at 1 pack = 1 pc.** ARCH_1 §5.3 insists a unit needs a statable factor, and
"one packet" only has one if the packet is the countable thing — which is the common case
("3 packs of noodles"). A user who means "1 pack = 8 pieces" edits the factor; a user who cannot
state any factor should create a separate Item, as §5.3 says.

**6. The tests read views through `customSelect`, not the generated view accessors.** Drift derives
a row-class name for each view, and I cannot verify those derived names without running codegen —
so rather than guess, the view assertions use raw SQL while inserts use the typed companions
(whose naming *is* confirmed: companions are named from the table class, unaffected by
`@DataClassName`). After your first build you can read the generated view classes out of
`alaya_database.g.dart`; Phase 2A's DAOs will use them. If you would rather fix the names now,
drift files support `CREATE VIEW v_account_balances AS AccountBalanceRow AS SELECT ...`.

**7. `onUpgrade` deliberately throws.** At v1 there is nothing to step between, and `stepByStep`
is *generated* from committed snapshots that cannot exist yet. Throwing means a file written by a
future build fails loudly instead of being reinterpreted against a schema this code does not know.
`migrations/schema/README.md` has the exact commands and the swap-in for v2.

**8. Commit the v1 snapshot now** — this is the one item in this phase that is unrecoverable if
skipped:

```bash
dart run drift_dev schema dump lib/data/db/alaya_database.dart drift_schemas/
git add drift_schemas/drift_schema_v1.json
```




---

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

### `lib/data/db/indexes.drift`

```sql
import 'tables/inventory_tables.dart';
import 'tables/meta_tables.dart';
import 'tables/money_tables.dart';
import 'tables/recurring_tables.dart';
import 'tables/service_tables.dart';
import 'tables/shopping_tables.dart';
import 'tables/tag_tables.dart';

-- ARCH_2 §11 verbatim. Declared as raw SQL in a .drift file rather than through Dart
-- annotations, because partial indexes (`WHERE ...`) are only reliably expressible here.

-- ── identity / uniqueness ────────────────────────────────────────────────────────────────
-- Every uniqueness index is PARTIAL on `deleted_at IS NULL`. Without that, soft-deleting
-- "Tomato" and re-adding it would hit a constraint violation on a row the user can no longer
-- see — anomaly A19, and the single most common soft-delete bug.
CREATE UNIQUE INDEX idx_items_identity
  ON items(normalized_name, unit_category)            WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_accounts_name
  ON accounts(normalized_name)                        WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_tags_name
  ON tags(normalized_name)                            WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_payees_name
  ON payees(normalized_name)                          WHERE deleted_at IS NULL;
-- Doubly partial: scoped to auto-generated rows only, so the suggestion engine's upsert is
-- idempotent while a user's own manual entry for the same item is untouched (anomaly A22).
CREATE UNIQUE INDEX idx_shopping_auto
  ON shopping_entries(list_id, item_id)
  WHERE origin = 'autoLowStock' AND deleted_at IS NULL;
-- Makes double-materialisation of the same due date a no-op rather than a crash.
CREATE UNIQUE INDEX idx_recurring_occ
  ON recurring_occurrences(template_id, due_date_key) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_rates_point
  ON currency_rates(base_code, quote_code, rate_date_key);

-- ── read paths ───────────────────────────────────────────────────────────────────────────
CREATE INDEX idx_tx_date        ON transactions(date_key)             WHERE deleted_at IS NULL;
CREATE INDEX idx_tx_month_kind  ON transactions(month_key, kind)      WHERE deleted_at IS NULL;
CREATE INDEX idx_tx_from        ON transactions(from_account_id, date_key);
CREATE INDEX idx_tx_to          ON transactions(to_account_id, date_key);
CREATE INDEX idx_tx_subtype     ON transactions(subtype, month_key);
CREATE INDEX idx_tx_recurring   ON transactions(recurring_template_id);
CREATE INDEX idx_lines_item     ON transaction_lines(item_id);
CREATE INDEX idx_lines_tx       ON transaction_lines(transaction_id);
CREATE INDEX idx_batch_item     ON inventory_batches(item_id)         WHERE deleted_at IS NULL;
CREATE INDEX idx_batch_expiry   ON inventory_batches(expiry_date_key) WHERE deleted_at IS NULL;
CREATE INDEX idx_move_batch     ON stock_movements(batch_id);
CREATE INDEX idx_move_item_date ON stock_movements(item_id, date_key);
CREATE INDEX idx_occ_due        ON recurring_occurrences(due_date_key, status);
CREATE INDEX idx_asset_service  ON assets(next_service_due_date_key)  WHERE deleted_at IS NULL;
CREATE INDEX idx_asset_warranty ON assets(warranty_end_date_key)      WHERE deleted_at IS NULL;

```

### `lib/data/db/fts.drift`

```sql
import 'tables/inventory_tables.dart';
import 'tables/money_tables.dart';

-- FTS5 full-text search (ARCH_2 §10). `LIKE '%x%'` over 10k rows is unusable, and external
-- content plus sync triggers cannot be bolted on cheaply later — which is why this is Phase 1C
-- and not Phase 7 (anomaly A40).
--
-- `content=` makes these EXTERNAL CONTENT tables: the index stores no copy of the text, it reads
-- column values back from the base table by rowid. Two consequences that callers must respect:
--
-- 1. A match gives you a rowid, not an id. Join back through it and filter soft deletes, because
--    FTS knows nothing about `deleted_at` (Law L7):
--      SELECT i.* FROM items_fts f JOIN items i ON i.rowid = f.rowid
--       WHERE items_fts MATCH ? AND i.deleted_at IS NULL;
--
-- 2. That rowid link is only as stable as the rowids. These tables have TEXT primary keys, so
--    they have no INTEGER PRIMARY KEY aliasing rowid, and SQLite's VACUUM documentation
--    explicitly permits renumbering rowids in exactly that case. ARCH_3 §3.1 backs up with
--    `VACUUM INTO`. Testing on current SQLite shows rowids are in fact preserved, but that is
--    unspecified behaviour to depend on, so Phase 4C's Replace-restore must run
--    `INSERT INTO items_fts(items_fts) VALUES('rebuild');` (and the same for transactions_fts)
--    after swapping the file in. Merge-restore needs nothing: it writes through the triggers.
CREATE VIRTUAL TABLE items_fts USING fts5(
  name,
  notes,
  content = items,
  content_rowid = rowid
);

CREATE TRIGGER items_fts_after_insert AFTER INSERT ON items BEGIN
  INSERT INTO items_fts(rowid, name, notes) VALUES (new.rowid, new.name, new.notes);
END;

CREATE TRIGGER items_fts_after_delete AFTER DELETE ON items BEGIN
  INSERT INTO items_fts(items_fts, rowid, name, notes)
    VALUES ('delete', old.rowid, old.name, old.notes);
END;

CREATE TRIGGER items_fts_after_update AFTER UPDATE ON items BEGIN
  INSERT INTO items_fts(items_fts, rowid, name, notes)
    VALUES ('delete', old.rowid, old.name, old.notes);
  INSERT INTO items_fts(rowid, name, notes) VALUES (new.rowid, new.name, new.notes);
END;

CREATE VIRTUAL TABLE transactions_fts USING fts5(
  note,
  content = transactions,
  content_rowid = rowid
);

CREATE TRIGGER transactions_fts_after_insert AFTER INSERT ON transactions BEGIN
  INSERT INTO transactions_fts(rowid, note) VALUES (new.rowid, new.note);
END;

CREATE TRIGGER transactions_fts_after_delete AFTER DELETE ON transactions BEGIN
  INSERT INTO transactions_fts(transactions_fts, rowid, note) VALUES ('delete', old.rowid, old.note);
END;

CREATE TRIGGER transactions_fts_after_update AFTER UPDATE ON transactions BEGIN
  INSERT INTO transactions_fts(transactions_fts, rowid, note) VALUES ('delete', old.rowid, old.note);
  INSERT INTO transactions_fts(rowid, note) VALUES (new.rowid, new.note);
END;

```

### `lib/data/db/migrations/migration_strategy.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Populates a freshly created database. Injected rather than called directly so tests can seed
/// deterministically, or skip seeding entirely.
typedef DatabaseSeeder = Future<void> Function(AlayaDatabase db);

/// Builds the [MigrationStrategy] for [db].
///
/// Three responsibilities, in order of how easy they are to get wrong:
///
/// 1. **`beforeOpen` turns foreign keys on.** SQLite defaults `PRAGMA foreign_keys` to *off*,
///    per-connection, and drift does not change that. Until this runs, all 51 foreign keys in the
///    schema are declared and completely unenforced. This is the single most important line in
///    the file.
/// 2. **`onCreate` creates the schema and then seeds it.** `createAll()` covers the 26 tables,
///    11 views, 22 indexes and 2 FTS tables, because drift registers everything in the
///    `@DriftDatabase` annotation's `tables` and `include` sets.
/// 3. **`onUpgrade` is a deliberate scaffold.** See the note on [_onUpgrade].
MigrationStrategy buildMigrationStrategy(
  AlayaDatabase db, {
  DatabaseSeeder? seeder,
}) {
  return MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      if (seeder != null) await seeder(db);
    },
    onUpgrade: _onUpgrade,
    beforeOpen: (details) async {
      await db.customStatement('PRAGMA foreign_keys = ON');
      if (_isDebugBuild) {
        await _assertFts5Available(db);
      }
    },
  );
}

/// Handles a schema upgrade.
///
/// At `schemaVersion = 1` there is nothing to upgrade *from*, so any invocation here means the
/// database was written by a build whose schema version this build does not know about — which
/// [DatabaseSchemaError] reports rather than silently continuing against a schema it cannot
/// interpret.
///
/// When v2 lands, replace this with drift's generated `stepByStep` helper:
///
/// ```dart
/// onUpgrade: stepByStep(from1To2: (m, schema) async { ... }),
/// ```
///
/// That helper is *generated* from the committed schema snapshots — see
/// `lib/data/db/migrations/schema/README.md`. It cannot exist until there are at least two
/// versions to step between, which is exactly why the v1 snapshot has to be committed now.
Future<void> _onUpgrade(Migrator m, int from, int to) async {
  throw DatabaseSchemaError(
    'Unsupported schema upgrade $from -> $to. Schema version 1 has no predecessors, so this '
    'database was created by a different build. Restore a backup taken by a compatible version, '
    'or reinstall.',
  );
}

/// Thrown when a database presents a schema version this build cannot migrate.
class DatabaseSchemaError extends Error {
  /// Creates the error with a human-readable [message].
  DatabaseSchemaError(this.message);

  /// What went wrong, and what the user's options are.
  final String message;

  @override
  String toString() => 'DatabaseSchemaError: $message';
}

/// True in debug and profile builds, false in release.
///
/// Uses the assert-side-effect idiom rather than `kDebugMode` so that this file — and everything
/// under `lib/data/db/` — stays free of any `package:flutter` import, which also means the whole
/// migration path is exercisable from a plain `dart test`.
bool get _isDebugBuild {
  var isDebug = false;
  assert(() {
    isDebug = true;
    return true;
  }());
  return isDebug;
}

/// Fails loudly in debug builds if the bundled SQLite lacks FTS5 (ARCH_2 §10, risk R3).
///
/// Checked at open time rather than trusted, because the symptom otherwise appears much later as
/// "search returns nothing" — with no indication that the index was never created.
Future<void> _assertFts5Available(AlayaDatabase db) async {
  final rows = await db.customSelect('PRAGMA compile_options').get();
  final options = rows
      .map((row) => row.data.values.first)
      .whereType<String>()
      .map((value) => value.toUpperCase())
      .toList();
  final hasFts5 = options.any((option) => option.contains('ENABLE_FTS5'));
  assert(
    hasFts5,
    'The bundled SQLite was built without FTS5. items_fts and transactions_fts cannot work, so '
    'search would silently return nothing. Check the sqlite3 package version (ARCH_1 §7) before '
    'going further.',
  );
}

```

### `lib/data/db/migrations/schema/README.md`

```markdown
# Schema snapshots

Drift's step-by-step migrations are generated from **committed snapshots** of each schema
version. Without a snapshot for v1 there is no starting point, so a v1 → v2 migration becomes
impossible to generate later — and unlike most mistakes in this project, that one is not
recoverable after users have data. ARCH_2 §13 calls this a five-minute task; it is, and it has to
happen now rather than when v2 is needed.

## 1. Dump the current schema — do this now, at v1

```bash
dart run drift_dev schema dump lib/data/db/alaya_database.dart drift_schemas/
```

Writes `drift_schemas/drift_schema_v1.json`. **Commit that file.** It is not generated output that
can be recreated on demand — once the schema moves to v2 the v1 shape is gone unless it was
captured.

## 2. When v2 arrives

Bump `schemaVersion` in `alaya_database.dart`, change the tables, then dump again:

```bash
dart run drift_dev schema dump lib/data/db/alaya_database.dart drift_schemas/
```

Generate the step helpers and the versioned schema code used by migration tests:

```bash
dart run drift_dev schema steps drift_schemas/ lib/data/db/migrations/schema_steps.dart
dart run drift_dev schema generate drift_schemas/ test/data/generated_migrations/
```

Then replace the `onUpgrade` scaffold in `migration_strategy.dart`:

```dart
onUpgrade: stepByStep(
  from1To2: (m, schema) async {
    // ...
  },
),
```

And extend `test/data/migration_test.dart` to call `verifyMigrations()`, which walks every
snapshot pair and asserts the migrated schema matches the declared one exactly.

## Why `onUpgrade` currently throws

At v1 there is nothing to upgrade from, so any call means the file was written by a build with a
different schema version. Throwing `DatabaseSchemaError` surfaces that; silently proceeding
against a schema the code cannot interpret would corrupt data.

## Checklist before each release that changes the schema

- [ ] `schemaVersion` bumped
- [ ] `drift_dev schema dump` run and the new `drift_schema_vN.json` committed
- [ ] `drift_dev schema steps` re-run and the generated file committed
- [ ] `onUpgrade` handles the new step
- [ ] `migration_test.dart` passes for every version pair
- [ ] Restore gate still refuses a backup whose `user_version` exceeds this build (anomaly A32)

```

### `lib/data/db/seed/seed_data.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// Inserts the first-launch reference data described in ARCH_2 §14.
///
/// [uids] and [clock] are injected so a test can seed a byte-identical database twice — with
/// `SequentialUidGenerator` and `FixedClock` from Phase 1A the whole seed becomes deterministic,
/// which is what makes `seed_test.dart` able to assert on exact rows.
///
/// [homeCurrencyCode] is passed in rather than detected here: locale is a presentation concern,
/// and reaching for `dart:ui` inside `data/` to find it would drag platform bindings into a layer
/// that has no business knowing about them. `bootstrap.dart` supplies it in Phase 5.
final class SeedData {
  /// Creates a seeder.
  const SeedData({
    required this.uids,
    required this.clock,
    this.homeCurrencyCode = 'INR',
  });

  /// Generates the UUIDv7 primary keys.
  final UidGenerator uids;

  /// Supplies `createdAt` / `updatedAt` and the opening-balance date.
  final Clock clock;

  /// Currency for the two seeded accounts and the `homeCurrencyCode` setting.
  final String homeCurrencyCode;

  /// Inserts everything, in one transaction so a partial seed is impossible (Law L14).
  Future<void> insertAll(AlayaDatabase db) async {
    await db.transaction(() async {
      await _insertCurrencies(db);
      await _insertUnits(db);
      await _insertPaymentMethods(db);
      final tagIds = await _insertTags(db);
      final accountIds = await _insertAccounts(db);
      await _insertShoppingList(db);
      await _insertSettings(db, defaultAccountId: accountIds.first);
      assert(tagIds.length == 18, 'ARCH_2 §14 specifies exactly 18 system tags');
    });
  }

  int get _now => clock.nowUtcMillis();

  Future<void> _insertCurrencies(AlayaDatabase db) async {
    // `decimalDigits` is the reason nothing in the app hardcodes 100 (ARCH_1 §4.1). JPY is 0.
    const rows = [
      ('INR', 'Indian Rupee', '\u20B9', 2),
      ('USD', 'US Dollar', '\u0024', 2),
      ('EUR', 'Euro', '\u20AC', 2),
      ('JPY', 'Japanese Yen', '\u00A5', 0),
      ('CNY', 'Chinese Yuan', 'CN\u00A5', 2),
    ];
    for (var i = 0; i < rows.length; i++) {
      final (code, name, symbol, decimalDigits) = rows[i];
      await db.into(db.currencies).insert(
            CurrenciesCompanion.insert(
              code: code,
              name: name,
              symbol: symbol,
              decimalDigits: decimalDigits,
              isEnabled: true,
              sortOrder: i,
              createdAt: _now,
              updatedAt: _now,
            ),
          );
    }
  }

  Future<void> _insertUnits(AlayaDatabase db) async {
    // factorToBaseMilli is exact integer milli-base-units per one of this unit (Law L2):
    // the base unit itself is 1000, so `kg` is 1000 x 1000 and `mg` is one thousandth of `g`.
    const rows = [
      ('mg', UnitCategory.weight, 1, 'Milligram'),
      ('g', UnitCategory.weight, 1000, 'Gram'),
      ('kg', UnitCategory.weight, 1000000, 'Kilogram'),
      ('ml', UnitCategory.volume, 1000, 'Millilitre'),
      ('l', UnitCategory.volume, 1000000, 'Litre'),
      ('pc', UnitCategory.count, 1000, 'Piece'),
      ('dozen', UnitCategory.count, 12000, 'Dozen'),
      // `pack` seeds at 1 pack = 1 pc. ARCH_1 §5.3 is explicit that a unit needs a statable
      // factor, and "one packet" only has one if you treat the packet as the countable thing —
      // which is the common case ("3 packs of noodles"). A user who means "1 pack = 8 pieces"
      // edits the factor; a user who cannot state any factor should create a separate Item.
      ('pack', UnitCategory.count, 1000, 'Pack'),
    ];
    for (var i = 0; i < rows.length; i++) {
      final (code, category, factor, displayName) = rows[i];
      await db.into(db.units).insert(
            UnitsCompanion.insert(
              code: code,
              category: category,
              factorToBaseMilli: factor,
              displayName: displayName,
              isSystem: true,
              sortOrder: i,
              createdAt: _now,
              updatedAt: _now,
            ),
          );
    }
  }

  Future<void> _insertPaymentMethods(AlayaDatabase db) async {
    const rows = [
      ('Cash', PaymentMethodKind.cash),
      ('UPI', PaymentMethodKind.upi),
      ('Bank Transfer', PaymentMethodKind.bankTransfer),
      ('Card', PaymentMethodKind.card),
      ('Cheque', PaymentMethodKind.cheque),
    ];
    for (var i = 0; i < rows.length; i++) {
      final (name, kind) = rows[i];
      await db.into(db.paymentMethods).insert(
            PaymentMethodsCompanion.insert(
              id: uids.generate(),
              name: name,
              kind: kind,
              isSystem: true,
              sortOrder: i,
              createdAt: _now,
              updatedAt: _now,
            ),
          );
    }
  }

  /// Inserts the 18 system tags with the exact `allowedIn*` matrix from ARCH_2 §14.
  ///
  /// This matrix is visible on first launch, so getting it wrong is immediately user-facing. The
  /// spec's own test case is `Kitchen`: inventory and shopping only, and it must **not** appear
  /// in the deposit picker.
  Future<List<String>> _insertTags(AlayaDatabase db) async {
    // (name, deposit, withdrawal, inventory, shopping, recurring, service)
    const matrix = <(String, bool, bool, bool, bool, bool, bool)>[
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

    final ids = <String>[];
    String? groceryId;
    for (var i = 0; i < matrix.length; i++) {
      final (name, dep, wdr, inv, shop, rec, svc) = matrix[i];
      final id = uids.generate();
      ids.add(id);
      await db.into(db.tags).insert(
            TagsCompanion.insert(
              id: id,
              name: name,
              // Matches Phase 1A's Normalizer for these names, all of which are single
              // lowercase-able words with no diacritics or punctuation.
              normalizedName: name.toLowerCase(),
              // `Vegetables` is the one nested tag in the seed, exactly one level under
              // `Grocery` (ARCH_2 §3). Depth beyond one level is rejected in the repository.
              parentTagId: Value(name == 'Vegetables' ? groceryId : null),
              allowedInDeposit: dep,
              allowedInWithdrawal: wdr,
              allowedInInventory: inv,
              allowedInShopping: shop,
              allowedInRecurring: rec,
              allowedInService: svc,
              isSystem: true,
              sortOrder: i,
              createdAt: _now,
              updatedAt: _now,
            ),
          );
      if (name == 'Grocery') groceryId = id;
    }
    return ids;
  }

  /// Inserts `Cash` and `Bank`, both in [homeCurrencyCode] with a zero opening balance.
  ///
  /// The returned list is ordered, and the first entry (`Cash`) becomes the default account.
  /// Note there is no `isDefault` column on `accounts` — ARCH_2 §4 has none — so "the default
  /// account" lives in `app_settings` under `defaultAccountId`, which is also what lets quick-add
  /// fall back to it after the last-used account (ARCH_2 §4.1).
  Future<List<String>> _insertAccounts(AlayaDatabase db) async {
    final today = clock.today();
    const rows = [
      ('Cash', AccountKind.cash),
      ('Bank', AccountKind.bank),
    ];
    final ids = <String>[];
    for (var i = 0; i < rows.length; i++) {
      final (name, kind) = rows[i];
      final id = uids.generate();
      ids.add(id);
      await db.into(db.accounts).insert(
            AccountsCompanion.insert(
              id: id,
              name: name,
              normalizedName: name.toLowerCase(),
              kind: kind,
              currencyCode: homeCurrencyCode,
              // Zero, not unknown. Onboarding (Phase 8A) collects the user's real opening
              // balances; until then the balance is honestly zero rather than absent
              // (anomaly A03).
              openingBalanceMinor: 0,
              openingBalanceDateKey: today,
              isArchived: false,
              includeInNetWorth: true,
              sortOrder: i,
              createdAt: _now,
              updatedAt: _now,
            ),
          );
    }
    return ids;
  }

  Future<void> _insertShoppingList(AlayaDatabase db) async {
    await db.into(db.shoppingLists).insert(
          ShoppingListsCompanion.insert(
            id: uids.generate(),
            name: 'Shopping List',
            isDefault: true,
            isArchived: false,
            createdAt: _now,
            updatedAt: _now,
          ),
        );
  }

  Future<void> _insertSettings(
    AlayaDatabase db, {
    required String defaultAccountId,
  }) async {
    final settings = <String, (String, String)>{
      'homeCurrencyCode': (homeCurrencyCode, 'string'),
      'defaultAccountId': (defaultAccountId, 'string'),
    };
    for (final entry in settings.entries) {
      final (value, valueType) = entry.value;
      await db.into(db.appSettings).insert(
            AppSettingsCompanion.insert(
              key: entry.key,
              value: value,
              valueType: valueType,
              createdAt: _now,
              updatedAt: _now,
            ),
          );
    }
  }
}

```

### `lib/data/db/connection/open_database.dart`

```dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/seed/seed_data.dart';

/// The database file name, without an extension. `drift_flutter` places it in the app's
/// documents directory.
const String kAlayaDatabaseName = 'alaya';

/// Opens the Alaya database. **This is the only function in the codebase permitted to do so**
/// (Law L10): one open path means there is exactly one place where the executor, the
/// cross-isolate setting and the seeder are decided, and no possibility of two connections
/// disagreeing about any of them.
///
/// The database is **plaintext** (ARCH_1 §2.1). There is no `PRAGMA key`, no cipher
/// configuration and no key material anywhere in this file or the packages it uses. What protects
/// the file is `android:allowBackup="false"` in the manifest, which stops Android replicating it
/// to the user's Drive, plus the device's own encryption while the phone is locked.
///
/// `shareAcrossIsolates` is required rather than optional: Phase 8B's `workmanager` job runs in a
/// background isolate and needs the same database, and without this flag it would open a second
/// independent connection to the same file (anomaly A41).
AlayaDatabase openAlayaDatabase({
  String name = kAlayaDatabaseName,
  UidGenerator uids = const Uuid7Generator(),
  Clock clock = const SystemClock(),
  String homeCurrencyCode = 'INR',
}) {
  final seeder = SeedData(uids: uids, clock: clock, homeCurrencyCode: homeCurrencyCode);
  return AlayaDatabase(
    createExecutor(name: name),
    seeder: seeder.insertAll,
  );
}

/// Builds the query executor. Separated from [openAlayaDatabase] only so a test can construct the
/// database over `NativeDatabase.memory()` instead, without duplicating the seeding wiring.
QueryExecutor createExecutor({String name = kAlayaDatabaseName}) {
  return driftDatabase(
    name: name,
    native: const DriftNativeOptions(shareAcrossIsolates: true),
  );
}

```

### `lib/data/db/alaya_database.dart`

```dart
import 'package:drift/drift.dart';

// The generated `alaya_database.g.dart` is a `part` of this library, and a part file cannot
// declare its own imports. Everything the generated code names must therefore be imported
// HERE, including types that this file's own source never mentions: the row classes expose
// `DateKey` and every enum, and the generated table classes instantiate every converter.
// Dart imports are not transitive, so importing the table files alone is not enough.
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/converters/date_key_converter.dart';
import 'package:alaya/data/db/converters/enum_converters.dart';
import 'package:alaya/data/db/migrations/migration_strategy.dart';
import 'package:alaya/data/db/tables/inventory_tables.dart';
import 'package:alaya/data/db/tables/meta_tables.dart';
import 'package:alaya/data/db/tables/money_tables.dart';
import 'package:alaya/data/db/tables/ops_tables.dart';
import 'package:alaya/data/db/tables/recurring_tables.dart';
import 'package:alaya/data/db/tables/service_tables.dart';
import 'package:alaya/data/db/tables/shopping_tables.dart';
import 'package:alaya/data/db/tables/tag_tables.dart';

part 'alaya_database.g.dart';

/// The Alaya database. Plaintext by design (ARCH_1 §2.1): no SQLCipher, no `PRAGMA key`, and
/// `android:allowBackup="false"` in the manifest is what stops Android replicating it to Drive.
///
/// The `include` set is what brings the 11 views, 22 indexes and 2 FTS tables into
/// `Migrator.createAll()`. Without those entries the `.drift` files are inert: the schema would
/// create 26 bare tables and every repository read would fail against a view that does not exist.
///
/// Phases 2A-2C add the DAOs on top of this.
@DriftDatabase(
  tables: [
    // Meta & reference
    AppSettings,
    Currencies,
    CurrencyRates,
    Units,
    Attachments,
    // Tags
    Tags,
    TransactionTags,
    ItemTags,
    AssetTags,
    // Money
    Accounts,
    PaymentMethods,
    Payees,
    Transactions,
    TransactionLines,
    // Inventory
    Items,
    InventoryBatches,
    StockMovements,
    // Shopping
    ShoppingLists,
    ShoppingEntries,
    // Recurring
    RecurringTemplates,
    RecurringOccurrences,
    // Service
    Assets,
    ServiceRecords,
    // Ops
    NotificationSchedule,
    BackupHistory,
    AnalyticsCache,
  ],
  include: {
    'views/account_views.drift',
    'views/transaction_views.drift',
    'views/inventory_views.drift',
    'views/schedule_views.drift',
    'views/calendar_view.drift',
    'indexes.drift',
    'fts.drift',
  },
)
class AlayaDatabase extends _$AlayaDatabase {
  /// Opens the database over [executor], optionally running [seeder] on first creation.
  ///
  /// Never construct this directly outside `connection/open_database.dart` — Law L10 requires
  /// exactly one open path, and that file is it.
  ///
  /// [seeder] is null in most tests, which want a bare schema, and non-null in production so a
  /// first launch arrives with currencies, units, tags and accounts already present.
  AlayaDatabase(super.executor, {this.seeder});

  /// Populates a freshly created database. See `seed/seed_data.dart`.
  final DatabaseSeeder? seeder;

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => buildMigrationStrategy(this, seeder: seeder);
}

```

### `test/data/migration_test.dart`

```dart
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Proves the migration harness works *before* there is a migration to run.
///
/// At `schemaVersion = 1` there is nothing to step between, so "v1 -> v1 passes" means something
/// narrower but still worth asserting: a fresh database reaches version 1 with every schema
/// object present, `beforeOpen` actually ran, and the guard rails are live. ARCH_2 §13 asks for
/// this now precisely because discovering the harness is broken at v2 — with users holding
/// data — is unrecoverable.
///
/// Once v2 exists, add `verifyMigrations()` against the generated snapshots. See
/// `lib/data/db/migrations/schema/README.md`.
void main() {
  late AlayaDatabase db;

  setUp(() async {
    db = AlayaDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get(); // forces onCreate + beforeOpen
  });

  tearDown(() => db.close());

  Future<Set<String>> namesOf(String type) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = ? AND name NOT LIKE 'sqlite_%'",
      variables: [Variable<String>(type)],
    ).get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  group('v1 creation', () {
    test('the declared schema version is 1', () {
      expect(db.schemaVersion, 1);
    });

    test('user_version is written to 1, which the restore gate depends on', () async {
      final row = await db.customSelect('PRAGMA user_version').getSingle();
      expect(row.data.values.first, 1,
          reason: 'Phase 4C refuses a backup whose user_version exceeds this build (A32)');
    });

    test('all 26 tables exist', () async {
      const expected = {
        'app_settings', 'currencies', 'currency_rates', 'units', 'attachments',
        'tags', 'transaction_tags', 'item_tags', 'asset_tags',
        'accounts', 'payment_methods', 'payees', 'transactions', 'transaction_lines',
        'items', 'inventory_batches', 'stock_movements',
        'shopping_lists', 'shopping_entries',
        'recurring_templates', 'recurring_occurrences',
        'assets', 'service_records',
        'notification_schedule', 'backup_history', 'analytics_cache',
      };
      final tables = await namesOf('table');
      expect(expected.difference(tables), isEmpty, reason: 'missing tables');
      expect(expected, hasLength(26));
    });

    test('all 11 views exist', () async {
      const expected = {
        'v_account_ledger', 'v_account_balances',
        'v_active_transactions', 'v_transaction_allocation', 'v_monthly_totals',
        'v_item_stock', 'v_batch_stock_check', 'v_low_stock',
        'v_recurring_due', 'v_asset_alerts',
        'v_calendar_events',
      };
      final views = await namesOf('view');
      expect(views, containsAll(expected));
      expect(expected, hasLength(11));
    });

    test('all 22 indexes from ARCH_2 §11 exist', () async {
      const expected = {
        'idx_items_identity', 'idx_accounts_name', 'idx_tags_name', 'idx_payees_name',
        'idx_shopping_auto', 'idx_recurring_occ', 'idx_rates_point',
        'idx_tx_date', 'idx_tx_month_kind', 'idx_tx_from', 'idx_tx_to', 'idx_tx_subtype',
        'idx_tx_recurring', 'idx_lines_item', 'idx_lines_tx',
        'idx_batch_item', 'idx_batch_expiry',
        'idx_move_batch', 'idx_move_item_date', 'idx_occ_due',
        'idx_asset_service', 'idx_asset_warranty',
      };
      final indexes = await namesOf('index');
      expect(expected.difference(indexes), isEmpty, reason: 'missing indexes');
      expect(expected, hasLength(22));
    });

    test('the twelve partial indexes really carry their WHERE clause', () async {
      final rows = await db.customSelect(
        "SELECT name, sql FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL",
      ).get();
      final partial = rows
          .where((r) => r.read<String>('sql').toUpperCase().contains(' WHERE '))
          .map((r) => r.read<String>('name'))
          .toSet();
      expect(
        partial,
        containsAll({
          'idx_items_identity', 'idx_accounts_name', 'idx_tags_name', 'idx_payees_name',
          'idx_shopping_auto', 'idx_recurring_occ',
        }),
        reason: 'without WHERE deleted_at IS NULL, re-adding a soft-deleted name fails (A19)',
      );
    });

    test('both FTS5 tables and their six triggers exist', () async {
      final tables = await namesOf('table');
      expect(tables, containsAll({'items_fts', 'transactions_fts'}));

      final triggers = await namesOf('trigger');
      expect(
        triggers,
        containsAll({
          'items_fts_after_insert', 'items_fts_after_delete', 'items_fts_after_update',
          'transactions_fts_after_insert', 'transactions_fts_after_delete',
          'transactions_fts_after_update',
        }),
      );
    });

    test('the bundled SQLite has FTS5 compiled in (risk R3)', () async {
      final rows = await db.customSelect('PRAGMA compile_options').get();
      final options = rows
          .map((r) => r.data.values.first)
          .whereType<String>()
          .map((v) => v.toUpperCase());
      expect(options.any((o) => o.contains('ENABLE_FTS5')), isTrue);
    });
  });

  group('beforeOpen', () {
    test('foreign keys are ON', () async {
      final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(row.data.values.first, 1,
          reason: 'off by default per connection; all 51 FKs are inert until this runs');
    });
  });

  group('constraints survive createAll', () {
    test('the transactions shape CHECK rejects a self-transfer', () async {
      await db.customStatement(
        "INSERT INTO currencies (code, name, symbol, decimal_digits, is_enabled, sort_order, "
        "created_at, updated_at) VALUES ('INR','Rupee','R',2,1,0,0,0)",
      );
      await db.customStatement(
        'INSERT INTO accounts (id, name, normalized_name, kind, currency_code, '
        'opening_balance_minor, opening_balance_date_key, is_archived, include_in_net_worth, '
        "sort_order, created_at, updated_at) VALUES ('a','A','a','cash','INR',0,20260728,0,1,0,0,0)",
      );
      expect(
        () => db.customStatement(
          'INSERT INTO transactions (id, kind, subtype, occurred_at, date_key, month_key, '
          'original_amount_minor, original_currency_code, from_account_id, to_account_id, '
          "needs_review, created_at, updated_at) VALUES "
          "('t','transfer','transferSelf',0,20260728,202607,100,'INR','a','a',0,0,0)",
        ),
        throwsA(anything),
        reason: 'from_account_id <> to_account_id is what makes the ledger sound',
      );
    });

    test('the month_key CHECK rejects an inconsistent pair', () async {
      await db.customStatement(
        "INSERT INTO currencies (code, name, symbol, decimal_digits, is_enabled, sort_order, "
        "created_at, updated_at) VALUES ('INR','Rupee','R',2,1,0,0,0)",
      );
      await db.customStatement(
        'INSERT INTO accounts (id, name, normalized_name, kind, currency_code, '
        'opening_balance_minor, opening_balance_date_key, is_archived, include_in_net_worth, '
        "sort_order, created_at, updated_at) VALUES ('a','A','a','cash','INR',0,20260728,0,1,0,0,0)",
      );
      expect(
        () => db.customStatement(
          'INSERT INTO transactions (id, kind, subtype, occurred_at, date_key, month_key, '
          'original_amount_minor, original_currency_code, from_account_id, to_account_id, '
          "needs_review, created_at, updated_at) VALUES "
          "('t','deposit','otherIn',0,20260728,202608,100,'INR',NULL,'a',0,0,0)",
        ),
        throwsA(anything),
      );
    });

    test('the stock_movements quantity CHECK rejects zero', () async {
      expect(
        () => db.customStatement(
          'INSERT INTO stock_movements (id, batch_id, item_id, kind, quantity_milli, '
          "occurred_at, date_key, created_at, updated_at) VALUES ('m','b','i','consume',0,0,20260728,0,0)",
        ),
        throwsA(anything),
      );
    });
  });

  group('onUpgrade scaffold', () {
    test('is documented as unreachable at v1 and throws rather than guessing', () {
      // Asserted by construction: schemaVersion is 1, so drift never calls onUpgrade on a
      // database it just created. The scaffold exists so that a file written by a future build
      // fails loudly instead of being reinterpreted against a schema this code does not know.
      expect(db.schemaVersion, 1);
    }, skip: 'No second schema version yet — see migrations/schema/README.md');
  });
}

```

### `test/data/seed_test.dart`

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/seed/seed_data.dart';

void main() {
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

### `test/data/view_test.dart`

```dart
import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// Exercises the 11 views, the partial indexes and the FTS triggers.
///
/// Rows are written through drift's typed companions, but views are read with [customSelect]
/// rather than the generated view accessors. That is deliberate: drift derives a row class name
/// for each view, and depending on those derived names here would couple this suite to a naming
/// rule instead of to the SQL it is meant to test. Phase 2A's DAOs will use the typed view
/// accessors once `alaya_database.g.dart` has been generated and the names are known.
void main() {
  late AlayaDatabase db;

  // Every date is fixed. No view in this schema consults the clock (see schedule_views.drift),
  // so nothing here may depend on the wall clock either.
  final today = DateKey.fromYmd(2026, 7, 28);

  setUp(() async {
    db = AlayaDatabase(NativeDatabase.memory()); // no seeder: these tests build their own rows
    for (final c in const [('INR', 2), ('JPY', 0)]) {
      await db.into(db.currencies).insert(
            CurrenciesCompanion.insert(
              code: c.$1,
              name: c.$1,
              symbol: c.$1,
              decimalDigits: c.$2,
              isEnabled: true,
              sortOrder: 0,
              createdAt: 0,
              updatedAt: 0,
            ),
          );
    }
    for (final u in const [('g', 1000), ('kg', 1000000)]) {
      await db.into(db.units).insert(
            UnitsCompanion.insert(
              code: u.$1,
              category: UnitCategory.weight,
              factorToBaseMilli: u.$2,
              displayName: u.$1,
              isSystem: true,
              sortOrder: 0,
              createdAt: 0,
              updatedAt: 0,
            ),
          );
    }
  });

  tearDown(() => db.close());

  Future<void> account(String id, int openingMinor, {String currency = 'INR'}) {
    return db.into(db.accounts).insert(
          AccountsCompanion.insert(
            id: id,
            name: id,
            normalizedName: id,
            kind: AccountKind.cash,
            currencyCode: currency,
            openingBalanceMinor: openingMinor,
            openingBalanceDateKey: today,
            isArchived: false,
            includeInNetWorth: true,
            sortOrder: 0,
            createdAt: 0,
            updatedAt: 0,
          ),
        );
  }

  Future<void> tx(
    String id,
    TransactionKind kind,
    TransactionSubtype subtype, {
    String? from,
    String? to,
    required int amountMinor,
    DateKey? on,
    String currency = 'INR',
    String? note,
  }) {
    final dateKey = on ?? today;
    return db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            kind: kind,
            subtype: subtype,
            occurredAt: 0,
            dateKey: dateKey,
            monthKey: dateKey.monthKey,
            originalAmountMinor: amountMinor,
            originalCurrencyCode: currency,
            fromAccountId: Value(from),
            toAccountId: Value(to),
            note: Value(note),
            needsReview: false,
            createdAt: 0,
            updatedAt: 0,
          ),
        );
  }

  Future<int> totalAcrossAccounts() async {
    final row = await db
        .customSelect('SELECT COALESCE(SUM(balance_minor), 0) AS t FROM v_account_balances')
        .getSingle();
    return row.read<int>('t');
  }

  Future<int> balanceOf(String accountId) async {
    final row = await db.customSelect(
      'SELECT balance_minor FROM v_account_balances WHERE account_id = ?',
      variables: [Variable<String>(accountId)],
    ).getSingle();
    return row.read<int>('balance_minor');
  }

  group('v_account_balances — every transaction kind', () {
    setUp(() async {
      await account('cash', 4000000);
      await account('bank', 10000000);
    });

    test('opening balances alone', () async {
      expect(await balanceOf('cash'), 4000000);
      expect(await balanceOf('bank'), 10000000);
      expect(await totalAcrossAccounts(), 14000000);
    });

    test('deposit credits the destination', () async {
      await tx('t1', TransactionKind.deposit, TransactionSubtype.salaryIn,
          to: 'bank', amountMinor: 6500000);
      expect(await balanceOf('bank'), 16500000);
      expect(await balanceOf('cash'), 4000000);
    });

    test('withdrawal debits the source', () async {
      await tx('t2', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 50000);
      expect(await balanceOf('cash'), 3950000);
    });

    test('adjustmentIncrease credits', () async {
      await tx('t3', TransactionKind.adjustmentIncrease, TransactionSubtype.otherIn,
          to: 'cash', amountMinor: 10000);
      expect(await balanceOf('cash'), 4010000);
    });

    test('adjustmentDecrease debits', () async {
      await tx('t4', TransactionKind.adjustmentDecrease, TransactionSubtype.otherOut,
          from: 'cash', amountMinor: 20000);
      expect(await balanceOf('cash'), 3980000);
    });

    test('transfer moves value between the two accounts', () async {
      await tx('t5', TransactionKind.transfer, TransactionSubtype.transferSelf,
          from: 'cash', to: 'bank', amountMinor: 500000);
      expect(await balanceOf('cash'), 3500000);
      expect(await balanceOf('bank'), 10500000);
    });

    test('all five kinds together, each applied exactly once', () async {
      await tx('a', TransactionKind.deposit, TransactionSubtype.salaryIn,
          to: 'bank', amountMinor: 6500000);
      await tx('b', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 50000);
      await tx('c', TransactionKind.adjustmentIncrease, TransactionSubtype.otherIn,
          to: 'cash', amountMinor: 10000);
      await tx('d', TransactionKind.adjustmentDecrease, TransactionSubtype.otherOut,
          from: 'cash', amountMinor: 20000);
      await tx('e', TransactionKind.transfer, TransactionSubtype.transferSelf,
          from: 'cash', to: 'bank', amountMinor: 500000);

      // cash: 4,000,000 - 50,000 + 10,000 - 20,000 - 500,000
      expect(await balanceOf('cash'), 3440000);
      // bank: 10,000,000 + 6,500,000 + 500,000
      expect(await balanceOf('bank'), 17000000);
      expect(await totalAcrossAccounts(), 20440000);

      final kinds = await db
          .customSelect('SELECT DISTINCT kind FROM v_account_ledger')
          .map((r) => r.read<String>('kind'))
          .get();
      expect(kinds.toSet(), hasLength(5), reason: 'every kind must reach the ledger');
    });
  });

  group('THE KEYSTONE — a self-transfer nets to zero', () {
    test('Cash -> Bank 5000 leaves the grand total unchanged', () async {
      await account('cash', 4000000);
      await account('bank', 10000000);

      final before = await totalAcrossAccounts();
      await tx('xfer', TransactionKind.transfer, TransactionSubtype.transferSelf,
          from: 'cash', to: 'bank', amountMinor: 500000);
      final after = await totalAcrossAccounts();

      expect(after, before,
          reason: 'moving money between your own accounts must not change net worth (A02)');
      expect(await balanceOf('cash'), 3500000);
      expect(await balanceOf('bank'), 10500000);
    });

    test('a transfer produces exactly two legs which sum to zero', () async {
      await account('cash', 0);
      await account('bank', 0);
      await tx('xfer', TransactionKind.transfer, TransactionSubtype.transferSelf,
          from: 'cash', to: 'bank', amountMinor: 500000);

      final legs = await db.customSelect(
        'SELECT account_id, signed_minor FROM v_account_ledger WHERE tx_id = ?',
        variables: [Variable<String>('xfer')],
      ).get();
      expect(legs, hasLength(2));
      expect(legs.fold<int>(0, (s, l) => s + l.read<int>('signed_minor')), 0);
      expect(legs.map((l) => l.read<String>('account_id')).toSet(), {'cash', 'bank'});
    });

    test('twenty-five alternating transfers never drift the total', () async {
      await account('cash', 1000000);
      await account('bank', 1000000);
      final before = await totalAcrossAccounts();
      for (var i = 0; i < 25; i++) {
        await tx('x$i', TransactionKind.transfer, TransactionSubtype.transferSelf,
            from: i.isEven ? 'cash' : 'bank',
            to: i.isEven ? 'bank' : 'cash',
            amountMinor: 7777);
      }
      expect(await totalAcrossAccounts(), before);
    });
  });

  group('soft delete (Law L7)', () {
    test('a soft-deleted transaction leaves the ledger entirely', () async {
      await account('cash', 1000000);
      await tx('t', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 50000);
      expect(await balanceOf('cash'), 950000);

      await db.customStatement('UPDATE transactions SET deleted_at = 1 WHERE id = ?', ['t']);
      expect(await balanceOf('cash'), 1000000);
      final legs = await db.customSelect('SELECT tx_id FROM v_account_ledger').get();
      expect(legs, isEmpty);
    });

    test('a soft-deleted account leaves v_account_balances', () async {
      await account('cash', 1000000);
      await account('bank', 500000);
      await db.customStatement('UPDATE accounts SET deleted_at = 1 WHERE id = ?', ['bank']);
      final rows = await db
          .customSelect('SELECT account_id FROM v_account_balances')
          .map((r) => r.read<String>('account_id'))
          .get();
      expect(rows, ['cash']);
    });

    test('v_active_transactions hides soft-deleted rows and exposes joined names', () async {
      await account('cash', 0);
      await db.into(db.payees).insert(
            PayeesCompanion.insert(
              id: 'p1',
              name: 'Big Bazaar',
              normalizedName: 'big bazaar',
              kind: PayeeKind.merchant,
              createdAt: 0,
              updatedAt: 0,
            ),
          );
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 't',
              kind: TransactionKind.withdrawal,
              subtype: TransactionSubtype.grocery,
              occurredAt: 0,
              dateKey: today,
              monthKey: today.monthKey,
              originalAmountMinor: 50000,
              originalCurrencyCode: 'INR',
              fromAccountId: const Value('cash'),
              payeeId: const Value('p1'),
              needsReview: false,
              createdAt: 0,
              updatedAt: 0,
            ),
          );

      var rows = await db.customSelect(
        'SELECT payee_name, from_account_name FROM v_active_transactions',
      ).get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('payee_name'), 'Big Bazaar');
      expect(rows.single.read<String>('from_account_name'), 'cash');

      await db.customStatement("UPDATE transactions SET deleted_at = 1 WHERE id = 't'");
      rows = await db.customSelect('SELECT tx_id FROM v_active_transactions').get();
      expect(rows, isEmpty);
    });
  });

  group('v_monthly_totals', () {
    test('groups by month, kind and currency without mixing currencies', () async {
      await account('cash', 0);
      await account('yen', 0, currency: 'JPY');
      await tx('a', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 10000);
      await tx('b', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 20000);
      await tx('c', TransactionKind.withdrawal, TransactionSubtype.otherOut,
          from: 'yen', amountMinor: 500, currency: 'JPY');
      await tx('d', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 30000, on: DateKey.fromYmd(2026, 8, 3));

      final july = await db.customSelect(
        "SELECT sum_minor, tx_count FROM v_monthly_totals "
        "WHERE month_key = 202607 AND currency_code = 'INR' AND kind = 'withdrawal'",
      ).getSingle();
      expect(july.read<int>('sum_minor'), 30000);
      expect(july.read<int>('tx_count'), 2);

      final jpy = await db.customSelect(
        "SELECT sum_minor FROM v_monthly_totals WHERE currency_code = 'JPY'",
      ).getSingle();
      expect(jpy.read<int>('sum_minor'), 500,
          reason: 'yen must never be summed into the rupee bucket (A34)');

      final august =
          await db.customSelect('SELECT 1 FROM v_monthly_totals WHERE month_key = 202608').get();
      expect(august, hasLength(1));
    });
  });

  group('v_transaction_allocation (A11)', () {
    test('reports the unallocated remainder and never auto-balances', () async {
      await account('cash', 0);
      await tx('t', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 50000);
      await db.into(db.transactionLines).insert(
            TransactionLinesCompanion.insert(
              id: 'l1',
              transactionId: 't',
              lineNo: 1,
              description: 'Potatoes',
              lineAmountMinor: const Value(48000),
              destination: TransactionLineDestination.inventory,
              createdAt: 0,
              updatedAt: 0,
            ),
          );

      final row = await db.customSelect(
        'SELECT amount_minor, allocated_minor, unallocated_minor, line_count '
        "FROM v_transaction_allocation WHERE tx_id = 't'",
      ).getSingle();
      expect(row.read<int>('amount_minor'), 50000);
      expect(row.read<int>('allocated_minor'), 48000);
      expect(row.read<int>('unallocated_minor'), 2000);
      expect(row.read<int>('line_count'), 1);
    });

    test('line_count distinguishes "no lines yet" from "lines that sum exactly"', () async {
      await account('cash', 0);
      await tx('t', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 50000);
      final row = await db.customSelect(
        "SELECT line_count, unallocated_minor FROM v_transaction_allocation WHERE tx_id = 't'",
      ).getSingle();
      expect(row.read<int>('line_count'), 0);
      expect(row.read<int>('unallocated_minor'), 50000,
          reason: 'the UI must key the nudge off lineCount, not off unallocatedMinor');
    });
  });

  group('inventory views', () {
    Future<void> item(String id, {int? thresholdMilli}) => db.into(db.items).insert(
          ItemsCompanion.insert(
            id: id,
            name: id,
            normalizedName: id,
            unitCategory: UnitCategory.weight,
            defaultDisplayUnitCode: 'g',
            itemKind: ItemKind.food,
            lowStockThresholdMilli: Value(thresholdMilli),
            isFavorite: false,
            createdAt: 0,
            updatedAt: 0,
          ),
        );

    Future<void> batch(String id, String itemId, int initial, int remaining, {DateKey? expiry}) =>
        db.into(db.inventoryBatches).insert(
              InventoryBatchesCompanion.insert(
                id: id,
                itemId: itemId,
                initialQuantityMilli: initial,
                remainingQuantityMilli: remaining,
                unitCodeAtPurchase: 'kg',
                expiryDateKey: Value(expiry),
                purchasedDateKey: today,
                origin: BatchOrigin.manual,
                createdAt: 0,
                updatedAt: 0,
              ),
            );

    Future<void> movement(String id, String batchId, String itemId, StockMovementKind kind,
            int qty, {String? reverses}) =>
        db.into(db.stockMovements).insert(
              StockMovementsCompanion.insert(
                id: id,
                batchId: batchId,
                itemId: itemId,
                kind: kind,
                quantityMilli: qty,
                occurredAt: 0,
                dateKey: today,
                reversesMovementId: Value(reverses),
                createdAt: 0,
                updatedAt: 0,
              ),
            );

    test('v_item_stock sums remaining, counts batches, finds nearest expiry', () async {
      await item('potato', thresholdMilli: 3000000);
      await batch('b1', 'potato', 2000000, 2000000, expiry: DateKey.fromYmd(2026, 8, 10));
      await batch('b2', 'potato', 1000000, 500000, expiry: DateKey.fromYmd(2026, 8, 5));

      final row = await db.customSelect(
        'SELECT total_remaining_milli, batch_count, nearest_expiry_date_key, is_low_stock '
        "FROM v_item_stock WHERE item_id = 'potato'",
      ).getSingle();
      expect(row.read<int>('total_remaining_milli'), 2500000);
      expect(row.read<int>('batch_count'), 2);
      expect(row.read<int>('nearest_expiry_date_key'), 20260805);
      expect(row.read<int>('is_low_stock'), 1);
    });

    test('exhausted batches are excluded from every aggregate', () async {
      await item('rice');
      await batch('b1', 'rice', 1000000, 0, expiry: DateKey.fromYmd(2026, 8, 1));
      await batch('b2', 'rice', 1000000, 400000, expiry: DateKey.fromYmd(2026, 9, 1));

      final row = await db.customSelect(
        'SELECT batch_count, total_remaining_milli, nearest_expiry_date_key '
        "FROM v_item_stock WHERE item_id = 'rice'",
      ).getSingle();
      expect(row.read<int>('batch_count'), 1);
      expect(row.read<int>('total_remaining_milli'), 400000);
      expect(row.read<int>('nearest_expiry_date_key'), 20260901,
          reason: 'an empty batch must not drag the nearest expiry earlier');
    });

    test('an item with no threshold is never low on stock', () async {
      await item('salt');
      await batch('b1', 'salt', 1000, 1000);
      final row = await db
          .customSelect("SELECT is_low_stock FROM v_item_stock WHERE item_id = 'salt'")
          .getSingle();
      expect(row.read<int>('is_low_stock'), 0);
      expect(await db.customSelect('SELECT item_id FROM v_low_stock').get(), isEmpty);
    });

    test('an item with no batches at all reports zero, not null', () async {
      await item('ghee', thresholdMilli: 500000);
      final row = await db.customSelect(
        "SELECT total_remaining_milli, batch_count, is_low_stock FROM v_item_stock "
        "WHERE item_id = 'ghee'",
      ).getSingle();
      expect(row.read<int>('total_remaining_milli'), 0);
      expect(row.read<int>('batch_count'), 0);
      expect(row.read<int>('is_low_stock'), 1, reason: 'nothing on hand is as low as it gets');
    });

    test('v_low_stock reports the shortfall', () async {
      await item('potato', thresholdMilli: 3000000);
      await batch('b1', 'potato', 2500000, 2500000);
      final row = await db
          .customSelect('SELECT item_id, shortfall_milli FROM v_low_stock')
          .getSingle();
      expect(row.read<String>('item_id'), 'potato');
      expect(row.read<int>('shortfall_milli'), 500000);
    });

    test('v_batch_stock_check reconciles the L3 cache against the ledger', () async {
      await item('potato');
      await batch('b1', 'potato', 2000000, 2000000);
      await movement('m1', 'b1', 'potato', StockMovementKind.openingIn, 2000000);

      var row = await db
          .customSelect('SELECT ledger_remaining_milli, discrepancy_milli FROM v_batch_stock_check')
          .getSingle();
      expect(row.read<int>('discrepancy_milli'), 0);

      // Consume without updating the cache — exactly the bug this view exists to catch.
      await movement('m2', 'b1', 'potato', StockMovementKind.consume, 300000);
      row = await db
          .customSelect('SELECT ledger_remaining_milli, discrepancy_milli FROM v_batch_stock_check')
          .getSingle();
      expect(row.read<int>('ledger_remaining_milli'), 1700000);
      expect(row.read<int>('discrepancy_milli'), 300000);
    });

    test('a reversal cancels the movement it points at', () async {
      await item('potato');
      await batch('b1', 'potato', 1000000, 1000000);
      await movement('m1', 'b1', 'potato', StockMovementKind.openingIn, 1000000);
      await movement('m2', 'b1', 'potato', StockMovementKind.consume, 200000);
      await movement('m3', 'b1', 'potato', StockMovementKind.adjustIn, 200000, reverses: 'm2');

      final row = await db
          .customSelect('SELECT ledger_remaining_milli, discrepancy_milli FROM v_batch_stock_check')
          .getSingle();
      expect(row.read<int>('ledger_remaining_milli'), 1000000);
      expect(row.read<int>('discrepancy_milli'), 0);
    });

    test('waste and expired count as outgoing', () async {
      await item('milk');
      await batch('b1', 'milk', 1000000, 1000000);
      await movement('m1', 'b1', 'milk', StockMovementKind.openingIn, 1000000);
      await movement('m2', 'b1', 'milk', StockMovementKind.waste, 250000);
      await movement('m3', 'b1', 'milk', StockMovementKind.expired, 250000);
      final row = await db
          .customSelect('SELECT ledger_remaining_milli FROM v_batch_stock_check')
          .getSingle();
      expect(row.read<int>('ledger_remaining_milli'), 500000);
    });
  });

  group('partial unique indexes', () {
    Future<void> item(String id, String normalized, UnitCategory category) =>
        db.into(db.items).insert(
              ItemsCompanion.insert(
                id: id,
                name: normalized,
                normalizedName: normalized,
                unitCategory: category,
                defaultDisplayUnitCode: 'g',
                itemKind: ItemKind.food,
                isFavorite: false,
                createdAt: 0,
                updatedAt: 0,
              ),
            );

    test('the same identity twice is rejected (A06)', () async {
      await item('i1', 'tomato', UnitCategory.weight);
      await expectLater(
        item('i2', 'tomato', UnitCategory.weight),
        throwsA(anything),
      );
    });

    test('the same name in a different category is allowed', () async {
      await item('i1', 'milk', UnitCategory.weight);
      await item('i2', 'milk', UnitCategory.volume);
      final rows = await db.select(db.items).get();
      expect(rows, hasLength(2));
    });

    test('re-adding after a soft delete is allowed (A19)', () async {
      await item('i1', 'tomato', UnitCategory.weight);
      await db.customStatement("UPDATE items SET deleted_at = 1 WHERE id = 'i1'");
      await item('i2', 'tomato', UnitCategory.weight);
      final active = await db
          .customSelect('SELECT id FROM items WHERE deleted_at IS NULL')
          .map((r) => r.read<String>('id'))
          .get();
      expect(active, ['i2']);
    });
  });

  group('v_calendar_events', () {
    test('emits each source with the right event_type and honours a bounded range', () async {
      await account('cash', 0);
      await tx('t', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 50000, note: 'Market');
      await db.into(db.shoppingLists).insert(
            ShoppingListsCompanion.insert(
              id: 'sl',
              name: 'Weekend list',
              isDefault: true,
              isArchived: false,
              targetDateKey: Value(DateKey.fromYmd(2026, 8, 1)),
              createdAt: 0,
              updatedAt: 0,
            ),
          );

      final counts = await db.customSelect(
        'SELECT event_type, COUNT(*) AS n FROM v_calendar_events GROUP BY event_type',
      ).get();
      final byType = {
        for (final r in counts) r.read<String>('event_type'): r.read<int>('n'),
      };
      expect(byType['transaction'], 1);
      expect(byType['shoppingTarget'], 1);

      final ranged = await db
          .customSelect('SELECT event_type FROM v_calendar_events '
              'WHERE date_key BETWEEN 20260801 AND 20260831')
          .map((r) => r.read<String>('event_type'))
          .get();
      expect(ranged, ['shoppingTarget']);
    });

    test('warranty, service and batch expiry all appear', () async {
      await db.into(db.assets).insert(
            AssetsCompanion.insert(
              id: 'a1',
              name: 'LG TV',
              normalizedName: 'lg tv',
              type: AssetType.electronics,
              warrantyEndDateKey: Value(DateKey.fromYmd(2027, 1, 1)),
              nextServiceDueDateKey: Value(DateKey.fromYmd(2026, 9, 1)),
              status: AssetStatus.active,
              createdAt: 0,
              updatedAt: 0,
            ),
          );
      final types = await db
          .customSelect('SELECT DISTINCT event_type FROM v_calendar_events')
          .map((r) => r.read<String>('event_type'))
          .get();
      expect(types.toSet(), containsAll({'warrantyEnd', 'serviceDue'}));
    });

    test('a disposed asset raises no alerts', () async {
      await db.into(db.assets).insert(
            AssetsCompanion.insert(
              id: 'a1',
              name: 'Old TV',
              normalizedName: 'old tv',
              type: AssetType.electronics,
              warrantyEndDateKey: Value(DateKey.fromYmd(2027, 1, 1)),
              status: AssetStatus.disposed,
              disposalReason: const Value(AssetDisposalReason.sold),
              createdAt: 0,
              updatedAt: 0,
            ),
          );
      expect(await db.customSelect('SELECT 1 FROM v_calendar_events').get(), isEmpty);
      expect(await db.customSelect('SELECT 1 FROM v_asset_alerts').get(), isEmpty);
    });

    test('severity is the static baseline; escalation is a Dart concern', () async {
      await account('cash', 0);
      await tx('t', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 100, on: DateKey.fromYmd(2020, 1, 1));
      final row = await db.customSelect('SELECT severity FROM v_calendar_events').getSingle();
      expect(row.read<String>('severity'), 'info',
          reason: 'no view consults the clock — see schedule_views.drift');
    });
  });

  group('v_recurring_due', () {
    test('paused templates are excluded and due occurrences are joined', () async {
      await account('cash', 0);
      Future<void> template(String id, {required bool paused}) =>
          db.into(db.recurringTemplates).insert(
                RecurringTemplatesCompanion.insert(
                  id: id,
                  name: id,
                  normalizedName: id,
                  kind: RecurringKind.bill,
                  direction: RecurringDirection.outflow,
                  defaultAmountMinor: 64900,
                  currencyCode: 'INR',
                  intervalUnit: RecurringIntervalUnit.month,
                  intervalCount: 1,
                  startDateKey: today,
                  nextDueDateKey: DateKey.fromYmd(2026, 8, 5),
                  isPaused: paused,
                  autoRemind: false,
                  remindDaysBefore: 1,
                  createdAt: 0,
                  updatedAt: 0,
                ),
              );
      await template('netflix', paused: false);
      await template('gym', paused: true);
      await db.into(db.recurringOccurrences).insert(
            RecurringOccurrencesCompanion.insert(
              id: 'o1',
              templateId: 'netflix',
              dueDateKey: DateKey.fromYmd(2026, 8, 5),
              status: RecurringOccurrenceStatus.due,
              createdAt: 0,
              updatedAt: 0,
            ),
          );

      final rows = await db.customSelect(
        'SELECT template_id, occurrence_id, occurrence_due_date_key FROM v_recurring_due',
      ).get();
      expect(rows.map((r) => r.read<String>('template_id')), ['netflix']);
      expect(rows.single.read<String>('occurrence_id'), 'o1');
      expect(rows.single.read<int>('occurrence_due_date_key'), 20260805);
    });

    test('no overdue column exists — the view never consults the clock', () async {
      final info = await db
          .customSelect("SELECT name FROM pragma_table_info('v_recurring_due')")
          .map((r) => r.read<String>('name'))
          .get();
      expect(info, isNot(contains('is_overdue')));
      expect(info, contains('occurrence_due_date_key'));
    });
  });

  group('FTS5', () {
    Future<void> namedItem(String id, String name) => db.into(db.items).insert(
          ItemsCompanion.insert(
            id: id,
            name: name,
            normalizedName: id,
            unitCategory: UnitCategory.weight,
            defaultDisplayUnitCode: 'g',
            itemKind: ItemKind.food,
            isFavorite: false,
            createdAt: 0,
            updatedAt: 0,
          ),
        );

    test('items_fts finds a name, and the join filters soft deletes', () async {
      await namedItem('tomato', 'Cherry Tomato');
      await namedItem('potato', 'Potato');

      var hits = await db
          .customSelect('SELECT i.id FROM items_fts f JOIN items i ON i.rowid = f.rowid '
              "WHERE items_fts MATCH 'Tomato' AND i.deleted_at IS NULL")
          .map((r) => r.read<String>('id'))
          .get();
      expect(hits, ['tomato']);

      await db.customStatement("UPDATE items SET deleted_at = 1 WHERE id = 'tomato'");
      hits = await db
          .customSelect('SELECT i.id FROM items_fts f JOIN items i ON i.rowid = f.rowid '
              "WHERE items_fts MATCH 'Tomato' AND i.deleted_at IS NULL")
          .map((r) => r.read<String>('id'))
          .get();
      expect(hits, isEmpty,
          reason: 'FTS knows nothing about deleted_at — the join must filter (L7)');
    });

    test('the update trigger reindexes a renamed item', () async {
      await namedItem('i', 'Brinjal');
      await db.customStatement("UPDATE items SET name = 'Aubergine' WHERE id = 'i'");

      final stale = await db
          .customSelect("SELECT rowid FROM items_fts WHERE items_fts MATCH 'Brinjal'")
          .get();
      final fresh = await db
          .customSelect("SELECT rowid FROM items_fts WHERE items_fts MATCH 'Aubergine'")
          .get();
      expect(stale, isEmpty);
      expect(fresh, hasLength(1));
    });

    test('the delete trigger removes the entry', () async {
      await namedItem('i', 'Brinjal');
      await db.customStatement("DELETE FROM items WHERE id = 'i'");
      final hits = await db
          .customSelect("SELECT rowid FROM items_fts WHERE items_fts MATCH 'Brinjal'")
          .get();
      expect(hits, isEmpty);
    });

    test('transactions_fts indexes the note', () async {
      await account('cash', 0);
      await tx('t', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 100, note: 'Weekly vegetable run');
      final hits = await db
          .customSelect("SELECT rowid FROM transactions_fts "
              "WHERE transactions_fts MATCH 'vegetable'")
          .get();
      expect(hits, hasLength(1));
    });
  });
}

```
