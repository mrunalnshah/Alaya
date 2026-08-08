# Phase 1B — The Complete Drift Schema

**26 tables · 327 columns · 51 foreign keys · 4 CHECK constraints · 23 enum converters.**

## Add dependencies first

Phase 1A's `pubspec.yaml` deliberately carries only `intl` and `uuid` (ARCH_1 §7.4 rule 2), so
Phase 1B is the first phase that adds anything back. It needs exactly one runtime package:

```bash
flutter pub add drift
flutter pub add --dev drift_dev build_runner
```

Then generate, before anything else:

```bash
dart run build_runner build
```

**`drift_flutter` and `sqlite3` are deliberately NOT added here.** Nothing in these 14 files
imports them — every one imports only `package:drift/drift.dart`. They are first needed by
`open_database.dart` in Phase 1C. The payoff is that Phase 1B is verifiable end-to-end through
codegen and `dart test` with **no Android build involved**: a schema error shows up in seconds
rather than behind a Gradle failure.

Confirm `drift` resolved at or above 2.34.2 (ARCH_1 §7), and that nothing unexpected arrived:

```bash
flutter pub deps | grep -i -E 'drift|sqlite'
```

Neither `sqlite3_flutter_libs` nor `sqlcipher_flutter_libs` may appear (ARCH_1 §7.1). Neither
should at this phase, since `drift` alone has no Flutter plugin dependencies — if one does show
up, stop and report it rather than building.

---

## Schema acceptance test — the 24 analytics queries (ARCH_3 §5.1)

Not asserted — **executed**. I built the schema below as real DDL in SQLite, created ARCH_2
§12.1's `v_account_ledger`, and ran all 24 queries against it. All 24 execute. No schema change
was needed.

| # | Question | Answered by | ✓ |
|---|---|---|---|
| 1 | Spend by subtype, per month | `transactions.subtype` + `month_key` | ✓ |
| 2 | Spend by tag, per month | `transaction_tags` ⋈ `transactions.month_key` | ✓ |
| 3 | Spend by payment method | `transactions.payment_method_id` | ✓ |
| 4 | Top 10 payees by spend | `transactions.payee_id` | ✓ |
| 5 | Income vs expense, 12-month trend | `transactions.kind` + `month_key` | ✓ |
| 6 | Net cash flow per month | `v_account_ledger.signed_minor` grouped by `date_key/100` | ✓ |
| 7 | Balance trend per account | `v_account_ledger` + `accounts.opening_balance_minor` / `opening_balance_date_key` | ✓ |
| 8 | Grocery share of total spend | `transactions.subtype` | ✓ |
| 9 | **Top items by spend** | `transaction_lines.item_id` + `line_amount_minor` | ✓ |
| 10 | **Top items by quantity bought** | `transaction_lines.quantity_milli` | ✓ |
| 11 | **Most expensive single purchase of an item** | `transaction_lines.unit_price_minor` | ✓ |
| 12 | **Unit-price trend for one item** | `transaction_lines.unit_price_minor` ⋈ `transactions.date_key` | ✓ |
| 13 | Inventory value on hand | `inventory_batches.remaining_quantity_milli` × `unit_cost_minor` | ✓ |
| 14 | **Food waste — quantity and money** | `stock_movements.kind IN ('waste','expired')` ⋈ `inventory_batches.unit_cost_minor` via `batch_id` | ✓ |
| 15 | Items expiring in N days | `inventory_batches.expiry_date_key` + `remaining_quantity_milli > 0` | ✓ |
| 16 | Low-stock count over time | `items.low_stock_threshold_milli` vs summed batch remainder | ✓ * |
| 17 | Fixed monthly commitment total | `recurring_templates` amount / `interval_unit` / `interval_count` / `is_paused` / `direction` | ✓ |
| 18 | Recurring vs discretionary split | `transactions.recurring_template_id IS NULL` | ✓ |
| 19 | Lifetime service cost per asset | `service_records.cost_minor` grouped by `asset_id` | ✓ |
| 20 | Warranty coverage timeline | `assets.warranty_start_date_key` / `warranty_end_date_key` | ✓ |
| 21 | Day-of-week / day-of-month heatmap | `date_key % 100`; weekday via `strftime` over the split `date_key` | ✓ ** |
| 22 | Category concentration (top-3 share) | `transactions.subtype` + `transaction_tags` | ✓ |
| 23 | Average grocery basket size | `transactions` ⋈ `count(transaction_lines)` | ✓ |
| 24 | **Price per base unit across purchases** | `line_amount_minor ÷ (quantity_milli / 1000)` | ✓ |

Two honest caveats, neither requiring a schema change:

**\* Query 16** is answerable, but thresholds are not historised. `items.low_stock_threshold_milli`
holds one current value, so a "low-stock count over time" series reconstructs past stock from
`stock_movements` (which is complete) and compares it against **today's** threshold. If the user
raises a threshold, history shifts retroactively. Versioning thresholds would mean a
`item_threshold_history` table earning its keep only for one chart — not worth it. Label the
chart accordingly in Phase 7B.

**\*\* Query 21** needs day-of-week, and no weekday column is stored. In SQL that means
`strftime('%w', substr(date_key,1,4)||'-'||substr(date_key,5,2)||'-'||substr(date_key,7,2))`,
verified working above; in Dart it is simply `DateKey.weekday`. Adding a stored `weekday` column
would be a denormalisation earning its keep only for one heatmap, so it is deliberately absent.

Two things worth knowing about queries 10 and 24: every quantity column already stores
**base-milli units**, never the purchased unit (ARCH_2 §4.2, Law L2), so neither query needs any
unit conversion — `unit_code` exists purely so a line renders as `2 kg` rather than `2000 g`.
And because milli-grams and milli-pieces are not comparable, both must group **by item**, which
is always sound since an item's category is immutable (Law L8).

## Confirmed by a real build

`dart run build_runner build` completed on Dart 3.12.2 / drift_dev with analyzer 13.0.0 and
wrote 78 outputs, no errors. `build.yaml` below now also sets `generate_manager: false`, which
removes the two "Duplicate orderings/filters" warnings at their cause — see the comment in that
file. Note `--delete-conflicting-outputs` was removed in build_runner 2.15; pass just
`dart run build_runner build`.

## Verification performed

Since no Dart toolchain is available to me, everything below was checked mechanically:

- **Column-by-column diff against ARCH_2 §3–§9** — 26 tables, 327 columns, **0 mismatches**,
  0 missing, 0 extra.
- **All 4 CHECK constraints executed against real SQLite** — 19 cases. Every shape ARCH_2
  §4.1 requires is accepted and every malformed one rejected, including self-transfer
  (`from = to`), zero and negative amounts, and a `month_key` inconsistent with `date_key`.
- **The keystone view proven** — built `v_account_ledger` and `v_account_balances` verbatim from
  ARCH_2 §12.1 on top of this schema and confirmed a self-transfer leaves the grand total
  unchanged, produces exactly 2 legs, and those legs sum to zero.
- **All 24 analytics queries executed**, not merely reasoned about.
- 51 foreign keys, each verified to target that table's actual primary key column
  (`#code` for `currencies`/`units`, `#id` elsewhere). No `ON DELETE CASCADE` anywhere.
- No `dateTime()` column anywhere (Law L4). 21 `*DateKey` columns all carry `DateKeyConverter`;
  `month_key` correctly does **not** (it is `yyyymm`, not a date).
- 23 enum converters: all defined, all used, none orphaned.
- Every table and column name confirmed to snake_case exactly as ARCH_2's views, indexes and
  CHECK constraints expect.

## Findings you need to decide on

**1. There are 26 tables, not 31.** ARCH_2's header says "31 tables" and this task says "All 31
tables", but §3–§9 specify exactly 26 by column, and the DELIVER list enumerates exactly those
26. I built 26 and did not invent five. The count in ARCH_2's header is wrong — possibly it once
counted the 2 FTS tables and some views. Worth correcting in the doc so a later phase doesn't go
hunting for missing tables.

**2. `money_converter.dart` and `qty_converter.dart` are not drift `TypeConverter`s, and cannot
be.** A `TypeConverter` maps exactly one column. Every monetary value in ARCH_2 is *two* columns
(`original_amount_minor` + `original_currency_code`), and a `Qty` needs a `UnitCategory` that
lives on `items.unit_category` or `units.category` — not on the row at all. So both ship as
column-pair mappers with the pairing rules documented, to be consumed by the Phase 3B–3D mappers.
The amount columns stay plain `integer()`, which is also what lets ARCH_3 §5.2's "aggregate in
SQL, never in Dart" rule work.

**3. One constraint beyond spec: `CHECK (quantity_milli > 0)` on `stock_movements`.** ARCH_2 §5.3
states this invariant in prose only. I declared it, because Law L3 makes every derived stock
figure depend on it and a zero or negative row would silently corrupt both `recomputeRemaining`
and the waste analytics. One line to delete if you disagree.

**4. `build.yaml` is included though not in DELIVER.** It pins `case_from_dart_to_sql: snake_case`
— currently drift's default, but every CHECK, index and view is written against snake_case
identifiers, so if that default ever changed the entire schema would break at once and the cause
would be near-invisible. It also declares the `fts5` module Phase 1C needs for its virtual tables
to pass drift's compile-time analysis.

**5. Drift's built-in `textEnum()` is deliberately unused.** It throws on an unrecognised value;
Law L13 requires the opposite. Hence 23 hand-written converters wrapping Phase 1A's
`SafeEnumConverter`. Each fallback is a real decision — documented per converter — following two
rules: prefer the member that *understates* (money, stock), and never fall back to a member
meaning "already handled" (`paid`, `disposed`), because silently marking an obligation settled is
the one degradation a user cannot detect.

**6. Row classes are named `XxxRow`** via `@DataClassName`. Phase 3A defines domain entities
called `Transaction`, `Account`, `Item`, `Currency`, and Phase 3B's mappers import both sides —
without a suffix every mapper would need an import prefix. It also avoids drift's default
singularisation turning `Currencies` into `Currencie`.

**7. Deliberate literal readings**, flagged so you can overrule cheaply:
`transaction_tags` / `item_tags` / `asset_tags` carry `created_at` **and** `updated_at` (ARCH_2 §2
applies them to every table; §4 removes only `id` and `deleted_at`) — `updated_at` on an immutable
link row is dead weight, and merge-restore should use `INSERT OR IGNORE` for these rather than the
`updated_at` comparison. `analytics_cache` likewise carries `deleted_at`, which nothing will ever
set. `app_settings`, `currencies`, `units`, `analytics_cache` keep the timestamp columns and only
swap the UUID `id` for a natural key, as §2 states.

**8. Four columns are plain `TEXT` with no enum**, because Phase 1A declares none for them:
`app_settings.value_type`, `attachments.owner_type`, `notification_schedule.ref_type`,
`currency_rates.source`. The two `*_type` columns are intentionally polymorphic discriminators
(anomaly A35's fix was to avoid polymorphic FKs *elsewhere*, via join tables — an attachment
genuinely can belong to any owner). Inventing enums here would create schema contracts under
Law L13 out of guesswork.

**9. The table files import each other circularly** — `money_tables` ↔ `inventory_tables` ↔
`service_tables` ↔ `recurring_tables`. This is unavoidable given DELIVER's 8-file split and the
requirement that foreign keys use `references()`, since `transaction_lines` → `assets` and
`assets` → `transaction_lines` both exist. Dart permits import cycles between libraries, so this
is legal; it is only worth knowing about.

**10. `PRAGMA foreign_keys = ON` is not set yet.** It arrives with the `MigrationStrategy` in
Phase 1C. Until then the 51 foreign keys are declared but unenforced at runtime — expected, and
the reason 1C's `view_test.dart` matters.



---

### `build.yaml`

```yaml
targets:
  $default:
    builders:
      drift_dev:
        options:
          # PINNED DELIBERATELY. snake_case is drift's current default, but every CHECK
          # constraint in money_tables.dart, every index in Phase 1C's indexes.drift and
          # every view in ARCH_2 §12 is written against snake_case SQL identifiers. If a
          # future drift release changed this default, the whole schema would break at once
          # and the cause would be very hard to see. Stating it costs nothing.
          case_from_dart_to_sql: snake_case

          # Drift's Manager API (`db.managers.x`) is never used in this project: Law L7 requires
          # repositories to read from views, and the Phase 2A-2C DAOs are typed SQL and nothing
          # more. Generating it produces a large amount of dead code for 26 tables, and it is
          # also the sole source of the "Duplicate orderings/filters detected" warnings — drift
          # cannot auto-name a reverse relation when two foreign keys point at the same table,
          # which happens twice here by design:
          #   currency_rates.base_code + quote_code  -> currencies
          #   transactions.from_account_id + to_account_id -> accounts   (the L02/A02 transfer shape)
          # Turning the feature off addresses the cause rather than silencing the symptom. If you
          # ever do want managers, re-enable this and add @ReferenceName('...') to those four
          # columns instead.
          generate_manager: false

          sql:
            dialect: sqlite
            options:
              # Conservative floor, well below what `sqlite3` 3.x bundles. Raise only with a
              # reason — declaring a version the bundled library does not have would let
              # drift's analyzer accept SQL that fails at runtime.
              version: "3.38"
              # Required so Phase 1C's items_fts / transactions_fts virtual tables and their
              # sync triggers pass drift's compile-time SQL analysis (ARCH_2 §10).
              modules:
                - fts5

```

### `lib/data/db/tables/meta_tables.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/data/db/converters/date_key_converter.dart';
import 'package:alaya/data/db/converters/enum_converters.dart';

/// Key/value store for everything user-configurable (ARCH_2 §3). Natural text key, no UUID.
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  /// Setting identifier, e.g. `homeCurrencyCode`.
  TextColumn get key => text()();

  /// The setting value, always serialised to text; [valueType] says how to read it.
  TextColumn get value => text()();

  /// How to interpret [value] — e.g. `string`, `int`, `bool`, `json`. Free text rather than an
  /// enum: Phase 1A declares no enum for it, and inventing one here would be a schema contract
  /// (Law L13) created by guesswork.
  TextColumn get valueType => text()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Supported currencies, extensible with no migration (ARCH_2 §3). Natural text key.
@DataClassName('CurrencyRow')
class Currencies extends Table {
  /// ISO 4217 code, e.g. `INR`.
  TextColumn get code => text()();

  /// Display name, e.g. `Indian Rupee`.
  TextColumn get name => text()();

  /// Display symbol, e.g. `₹`.
  TextColumn get symbol => text()();

  /// Minor units per major unit as a power of ten — 2 for INR/USD/EUR/CNY, 0 for JPY. The
  /// reason nothing in the app hardcodes `100` (ARCH_1 §4.1).
  IntColumn get decimalDigits => integer()();

  /// Whether this currency is offered in pickers.
  BoolColumn get isEnabled => boolean()();

  /// Manual ordering within pickers.
  IntColumn get sortOrder => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {code};
}

/// Daily exchange-rate cache. Only ever holds rows with `baseCode = 'USD'` — every other pair
/// is cross-rated locally from the USD pivot (ARCH_3 §1.2), which is what keeps the app to one
/// HTTP request per day.
@DataClassName('CurrencyRateRow')
class CurrencyRates extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Base currency of the quote. Always `USD` in practice.
  TextColumn get baseCode => text().references(Currencies, #code)();

  /// Quoted currency.
  TextColumn get quoteCode => text().references(Currencies, #code)();

  /// Civil date the rate applies to.
  IntColumn get rateDateKey => integer().map(const DateKeyConverter())();

  /// The rate as a double, for display and arithmetic.
  RealColumn get rate => real()();

  /// The exact string the API returned, so any number a user questions can be reproduced
  /// (ARCH_3 §1.3).
  TextColumn get rateRaw => text()();

  /// Which endpoint supplied it, for debugging the fallback ladder.
  TextColumn get source => text()();

  /// Fetch instant, epoch millis UTC.
  IntColumn get fetchedAt => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// System and user-defined units, each an exact integer factor to its category base
/// (ARCH_1 §5.3). Natural text key.
@DataClassName('UnitRow')
class Units extends Table {
  /// Unit code, e.g. `kg`, `ml`, `dozen`.
  TextColumn get code => text()();

  /// Which of the three fixed categories this unit measures.
  TextColumn get category => text().map(const UnitCategoryConverter())();

  /// Exact integer milli-base units per one of this unit — `kg` is `1000000`, `dozen` is
  /// `12000`. Integer by design: unit conversion never touches a double (Law L2).
  IntColumn get factorToBaseMilli => integer()();

  /// Human-readable name for pickers.
  TextColumn get displayName => text()();

  /// Whether this unit was seeded rather than user-created; system units cannot be deleted.
  BoolColumn get isSystem => boolean()();

  /// Manual ordering within pickers.
  IntColumn get sortOrder => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {code};
}

/// Receipt and warranty images. Defined in Phase 1B with no UI until Phase 8B, purely so that
/// adding attachments later is not a migration (ARCH_2 §3).
@DataClassName('AttachmentRow')
class Attachments extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Which kind of record owns this attachment, e.g. `transaction`, `asset`. Free text rather
  /// than a real foreign key: this is the one intentionally polymorphic pointer in the schema,
  /// and anomaly A35's fix was to avoid polymorphic FKs elsewhere by using join tables — an
  /// attachment genuinely can belong to any owner type, so integrity is enforced in the
  /// repository instead.
  TextColumn get ownerType => text()();

  /// The owning record's id.
  TextColumn get ownerId => text()();

  /// Path relative to the app's attachment directory, never absolute — absolute paths break
  /// on restore to a different device.
  TextColumn get relativePath => text()();

  /// MIME type, e.g. `image/jpeg`.
  TextColumn get mimeType => text()();

  /// File size in bytes, for the backup size estimate.
  IntColumn get sizeBytes => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

```

### `lib/data/db/tables/tag_tables.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/data/db/tables/inventory_tables.dart';
import 'package:alaya/data/db/tables/money_tables.dart';
import 'package:alaya/data/db/tables/service_tables.dart';

/// The single tag table, scoped per module by the six `allowedIn*` flags (ARCH_2 §3).
///
/// One table as the spec requires, but linked through separate join tables per entity rather
/// than a polymorphic owner column — that is anomaly A35's resolution: real foreign keys with
/// real integrity, which codegen makes free.
@DataClassName('TagRow')
class Tags extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Display name as the user typed it.
  TextColumn get name => text()();

  /// Normalised form used for identity matching only, never displayed
  /// (Phase 1A `Normalizer`).
  TextColumn get normalizedName => text()();

  /// Optional ARGB colour for the chip.
  IntColumn get colorArgb => integer().nullable()();

  /// Optional icon identifier.
  TextColumn get iconKey => text().nullable()();

  /// Parent tag, permitting exactly **one** level of nesting (`Grocery > Vegetables`). Depth is
  /// capped in the repository, not here. This single column is what makes drill-down analytics
  /// possible (ARCH_2 §3).
  TextColumn get parentTagId => text().nullable().references(Tags, #id)();

  /// Offered in the deposit tag picker.
  BoolColumn get allowedInDeposit => boolean()();

  /// Offered in the withdrawal tag picker.
  BoolColumn get allowedInWithdrawal => boolean()();

  /// Offered in the inventory tag picker.
  BoolColumn get allowedInInventory => boolean()();

  /// Offered in the shopping tag picker, where it also acts as the group header.
  BoolColumn get allowedInShopping => boolean()();

  /// Offered in the recurring tag picker.
  BoolColumn get allowedInRecurring => boolean()();

  /// Offered in the service tag picker.
  BoolColumn get allowedInService => boolean()();

  /// Whether this tag was seeded; system tags cannot be deleted (ARCH_3 §4.1).
  BoolColumn get isSystem => boolean()();

  /// Manual ordering within pickers.
  IntColumn get sortOrder => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active — a deleted tag keeps its links
  /// so history stays readable (anomaly A36).
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Links a transaction to a tag. Composite primary key, no UUID, no soft delete (ARCH_2 §4).
@DataClassName('TransactionTagRow')
class TransactionTags extends Table {
  /// The tagged transaction.
  TextColumn get transactionId => text().references(Transactions, #id)();

  /// The applied tag.
  TextColumn get tagId => text().references(Tags, #id)();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC. Retained for uniformity with ARCH_2 §2's
  /// common columns; a link row is only ever inserted or removed, so merge-restore reconciles
  /// these tables with `INSERT OR IGNORE` rather than the `updatedAt` comparison used elsewhere
  /// (ARCH_3 §3.2).
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {transactionId, tagId};
}

/// Links an inventory item to a tag. Composite primary key, no UUID, no soft delete.
@DataClassName('ItemTagRow')
class ItemTags extends Table {
  /// The tagged item.
  TextColumn get itemId => text().references(Items, #id)();

  /// The applied tag.
  TextColumn get tagId => text().references(Tags, #id)();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {itemId, tagId};
}

/// Links a service-manager asset to a tag. Composite primary key, no UUID, no soft delete.
@DataClassName('AssetTagRow')
class AssetTags extends Table {
  /// The tagged asset.
  TextColumn get assetId => text().references(Assets, #id)();

  /// The applied tag.
  TextColumn get tagId => text().references(Tags, #id)();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {assetId, tagId};
}

```

### `lib/data/db/tables/money_tables.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/data/db/converters/date_key_converter.dart';
import 'package:alaya/data/db/converters/enum_converters.dart';
import 'package:alaya/data/db/tables/inventory_tables.dart';
import 'package:alaya/data/db/tables/meta_tables.dart';
import 'package:alaya/data/db/tables/recurring_tables.dart';
import 'package:alaya/data/db/tables/service_tables.dart';

/// A container that holds money and has a balance — `Cash in hand`, `HDFC Savings`,
/// `Paytm Wallet`. Exactly one currency each (ARCH_1 §3.1).
///
/// Distinct from [PaymentMethods] (the rail money travelled on) and [Payees] (the
/// counterparty). Collapsing those three into one list is anomaly A01, and it is what makes
/// "Total Available Funds" unanswerable.
@DataClassName('AccountRow')
class Accounts extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Display name as the user typed it.
  TextColumn get name => text()();

  /// Normalised form used for identity matching only, never displayed.
  TextColumn get normalizedName => text()();

  /// What kind of container this is, for grouping and iconography.
  TextColumn get kind => text().map(const AccountKindConverter())();

  /// The single currency this account is denominated in.
  TextColumn get currencyCode => text().references(Currencies, #code)();

  /// Balance already present when tracking began, in minor units. Without this a user's real
  /// existing cash is invisible forever (anomaly A03).
  IntColumn get openingBalanceMinor => integer()();

  /// Civil date the opening balance was true on. Not nullable: a balance without a date cannot
  /// be placed on the balance-trend series (ARCH_3 §5.1 query 7).
  IntColumn get openingBalanceDateKey => integer().map(const DateKeyConverter())();

  /// Optional ARGB colour.
  IntColumn get colorArgb => integer().nullable()();

  /// Optional icon identifier.
  TextColumn get iconKey => text().nullable()();

  /// Retired but historical. Archived accounts stay in net worth and totals but leave the
  /// pickers — the distinction from soft delete that ARCH_3 §4 exists to preserve.
  BoolColumn get isArchived => boolean()();

  /// Whether this account contributes to the net-worth headline.
  BoolColumn get includeInNetWorth => boolean()();

  /// Manual ordering within pickers.
  IntColumn get sortOrder => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The rail money travelled on — `Cash`, `UPI`, `Card`, `Bank Transfer`, `Cheque`. Metadata
/// only: a payment method never holds a balance (ARCH_1 §3.1).
@DataClassName('PaymentMethodRow')
class PaymentMethods extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Display name as the user typed it.
  TextColumn get name => text()();

  /// Which rail this represents.
  TextColumn get kind => text().map(const PaymentMethodKindConverter())();

  /// Whether this method was seeded rather than user-created.
  BoolColumn get isSystem => boolean()();

  /// Manual ordering within pickers.
  IntColumn get sortOrder => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The counterparty on a transaction, used for both `From` (deposits) and `To` (withdrawals).
@DataClassName('PayeeRow')
class Payees extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Display name as the user typed it.
  TextColumn get name => text()();

  /// Normalised form used for identity matching only, never displayed.
  TextColumn get normalizedName => text()();

  /// What kind of counterparty this is.
  TextColumn get kind => text().map(const PayeeKindConverter())();

  /// Optional contact number.
  TextColumn get phone => text().nullable()();

  /// Optional free-text note.
  TextColumn get note => text().nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One movement of money — the first of the app's three append-only truths (ARCH_1 §3.3).
///
/// A `transfer` is **one row**, not a pair: Phase 1C's `v_account_ledger` expands it into two
/// signed legs, which is why a self-transfer nets to zero by construction and cannot drift
/// (anomaly A02). The three table-level CHECK constraints below are what make that view sound —
/// without them a malformed row could produce a leg with a null account.
@DataClassName('TransactionRow')
class Transactions extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Which direction money moved and how it affects balances.
  TextColumn get kind => text().map(const TransactionKindConverter())();

  /// The structural flow subtype: decides which editor form appears and which analytics bucket
  /// this lands in. Closed enum by design, unlike the open [Tags] (ARCH_1 §3.1).
  TextColumn get subtype => text().map(const TransactionSubtypeConverter())();

  /// When it happened, epoch millis UTC.
  IntColumn get occurredAt => integer()();

  /// The local civil date it happened on.
  IntColumn get dateKey => integer().map(const DateKeyConverter())();

  /// `yyyymm`, denormalised from [dateKey] so monthly analytics never compute it per row. Kept
  /// consistent by the third CHECK constraint rather than by discipline.
  IntColumn get monthKey => integer()();

  /// The amount as stored, always positive — the sign comes from [kind] (Law L1).
  IntColumn get originalAmountMinor => integer()();

  /// Currency of [originalAmountMinor]. Immutable once saved, together with the amount (Law L9).
  TextColumn get originalCurrencyCode => text().references(Currencies, #code)();

  /// Source account for withdrawals, decreases and transfers.
  TextColumn get fromAccountId => text().nullable().references(Accounts, #id)();

  /// Destination account for deposits, increases and transfers.
  TextColumn get toAccountId => text().nullable().references(Accounts, #id)();

  /// The rail money travelled on.
  TextColumn get paymentMethodId => text().nullable().references(PaymentMethods, #id)();

  /// The counterparty.
  TextColumn get payeeId => text().nullable().references(Payees, #id)();

  /// Optional free-text note. Indexed for full-text search in Phase 1C.
  TextColumn get note => text().nullable()();

  /// Set by quick-add when only an amount was supplied; drives the "add details" nudge.
  BoolColumn get needsReview => boolean()();

  /// The recurring template this settled, if any. Also the discriminator for ARCH_3 §5.1
  /// query 18's recurring-versus-discretionary split.
  TextColumn get recurringTemplateId =>
      text().nullable().references(RecurringTemplates, #id)();

  /// The specific occurrence this settled, if any.
  TextColumn get recurringOccurrenceId =>
      text().nullable().references(RecurringOccurrences, #id)();

  /// Frozen converted amount, written only by the explicit per-transaction freeze action. Never
  /// recomputed and never a substitute for [originalAmountMinor] (Law L9).
  IntColumn get convertedAmountMinor => integer().nullable()();

  /// Currency of [convertedAmountMinor].
  TextColumn get convertedCurrencyCode => text().nullable()();

  /// The rate used at freeze time.
  RealColumn get conversionRate => real().nullable()();

  /// The exact rate string the API returned, so a questioned number can be reproduced.
  TextColumn get conversionRateRaw => text().nullable()();

  /// The civil date the frozen rate was quoted for.
  IntColumn get conversionDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// Why the user deleted this, captured at soft-delete time.
  TextColumn get deleteReason => text().nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (original_amount_minor > 0)',
        'CHECK ('
            "(kind IN ('deposit','adjustmentIncrease')"
            ' AND to_account_id IS NOT NULL AND from_account_id IS NULL)'
            ' OR '
            "(kind IN ('withdrawal','adjustmentDecrease')"
            ' AND from_account_id IS NOT NULL AND to_account_id IS NULL)'
            ' OR '
            "(kind = 'transfer'"
            ' AND from_account_id IS NOT NULL AND to_account_id IS NOT NULL'
            ' AND from_account_id <> to_account_id)'
            ')',
        'CHECK (date_key / 100 = month_key)',
      ];
}

/// One purchased thing inside a [Transactions] row (ARCH_2 §4.2).
///
/// Optional detail: `transactions.original_amount_minor` remains the source of truth, and when
/// the lines do not sum to it the difference surfaces as an "unallocated" chip rather than being
/// auto-balanced (anomaly A11). These columns are also what make ARCH_3 §5.1's differentiating
/// queries 9-12 and 24 possible at all.
@DataClassName('TransactionLineRow')
class TransactionLines extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// The owning transaction.
  TextColumn get transactionId => text().references(Transactions, #id)();

  /// Position within the transaction, 1-based.
  IntColumn get lineNo => integer()();

  /// What was bought, as free text.
  TextColumn get description => text()();

  /// The catalogued item, when this line refers to one. Nullable so buying something never
  /// catalogued still records a line.
  TextColumn get itemId => text().nullable().references(Items, #id)();

  /// Quantity in **base-milli units**, not in [unitCode] (Law L2). Aggregating this column
  /// directly is valid and needs no unit conversion.
  IntColumn get quantityMilli => integer().nullable()();

  /// The unit the user actually typed, kept only so the line renders as `2 kg` rather than
  /// `2000 g`.
  TextColumn get unitCode => text().nullable().references(Units, #code)();

  /// Price per [unitCode], in minor units. Drives the personal-inflation series (query 12).
  IntColumn get unitPriceMinor => integer().nullable()();

  /// Total for this line, in minor units.
  IntColumn get lineAmountMinor => integer().nullable()();

  /// What this line produced elsewhere in the app — the single field that removes the
  /// electronics/inventory/service ambiguity (anomaly A12). One line produces at most one
  /// artefact, and the matching `created*Id` records which.
  TextColumn get destination => text().map(const TransactionLineDestinationConverter())();

  /// The inventory batch this line created, if [destination] was inventory.
  TextColumn get createdBatchId => text().nullable().references(InventoryBatches, #id)();

  /// The asset this line created, if [destination] was asset.
  TextColumn get createdAssetId => text().nullable().references(Assets, #id)();

  /// The recurring template this line created, if [destination] was recurring.
  TextColumn get createdRecurringTemplateId =>
      text().nullable().references(RecurringTemplates, #id)();

  /// Optional free-text note.
  TextColumn get note => text().nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

```

### `lib/data/db/tables/inventory_tables.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/data/db/converters/date_key_converter.dart';
import 'package:alaya/data/db/converters/enum_converters.dart';
import 'package:alaya/data/db/tables/meta_tables.dart';
import 'package:alaya/data/db/tables/money_tables.dart';

/// The *kind* of consumable thing, as opposed to one acquisition of it (ARCH_1 §3.2).
///
/// Identity is `(normalizedName, unitCategory)`, enforced by the partial unique index in
/// Phase 1C: same category means the same item and a new batch, a different category means a
/// genuinely different item shown as `Milk (Volume)` / `Milk (Weight)` (anomaly A06).
@DataClassName('ItemRow')
class Items extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Display name as the user typed it.
  TextColumn get name => text()();

  /// Normalised form used for identity matching only, never displayed. Exact matches merge;
  /// near matches are only ever *suggested* (anomaly A07).
  TextColumn get normalizedName => text()();

  /// Which of the three fixed categories this item is measured in. **Immutable after creation**
  /// (Law L8) — rejected on update in the repository, since changing it would silently
  /// reinterpret every quantity ever recorded against the item.
  TextColumn get unitCategory => text().map(const UnitCategoryConverter())();

  /// The unit this item's quantities are rendered in by default.
  TextColumn get defaultDisplayUnitCode => text().references(Units, #code)();

  /// Rough classification. `medicine` is what makes medicine expiry appear on the calendar with
  /// no extra table (ARCH_3 §6).
  TextColumn get itemKind => text().map(const ItemKindConverter())();

  /// Below this total remaining quantity the item is low on stock and the suggestion engine may
  /// generate a shopping entry. In base-milli units. Null means no threshold set.
  IntColumn get lowStockThresholdMilli => integer().nullable()();

  /// How many days before a batch's expiry to remind. Null falls back to the global setting.
  IntColumn get expiryNotifyDays => integer().nullable()();

  /// Optional free-text notes. Indexed for full-text search in Phase 1C.
  TextColumn get notes => text().nullable()();

  /// Pinned to the top of the inventory list.
  BoolColumn get isFavorite => boolean()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One acquisition of an [Items] row: a quantity, an expiry, a cost and a source
/// (ARCH_1 §3.2). Every stock operation acts on batches; the item row only sums them.
@DataClassName('InventoryBatchRow')
class InventoryBatches extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// The item this batch is an acquisition of.
  TextColumn get itemId => text().references(Items, #id)();

  /// Quantity acquired, in base-milli units.
  IntColumn get initialQuantityMilli => integer()();

  /// Quantity still on hand, in base-milli units.
  ///
  /// **The schema's only stored total, and the sole exception to Law L3.** It is a cache,
  /// reconstructible at any time by summing this batch's [StockMovements] — Phase 1C's
  /// `v_batch_stock_check` is the reconciliation probe and Phase 2B's `recomputeRemaining` is
  /// the repair path. Every write that changes it must insert the matching movement row in the
  /// same transaction (Law L14).
  IntColumn get remainingQuantityMilli => integer()();

  /// The unit the user actually purchased in, kept for display fidelity only.
  TextColumn get unitCodeAtPurchase => text().references(Units, #code)();

  /// Civil expiry date. Null means this batch does not expire, which also excludes it from FEFO
  /// ordering until the dated batches are exhausted (anomaly A08).
  IntColumn get expiryDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// Civil date acquired.
  IntColumn get purchasedDateKey => integer().map(const DateKeyConverter())();

  /// Cost per [unitCodeAtPurchase], in minor units. Paired with [costCurrencyCode]; the two are
  /// composed into a `Money` by `MoneyColumns`, never separately.
  IntColumn get unitCostMinor => integer().nullable()();

  /// Currency of [unitCostMinor].
  TextColumn get costCurrencyCode => text().nullable().references(Currencies, #code)();

  /// The transaction line that created this batch, if it came from a purchase. Nulled rather
  /// than cascaded when that transaction is deleted (anomaly A10).
  TextColumn get sourceTransactionLineId =>
      text().nullable().references(TransactionLines, #id)();

  /// Where this batch came from. Becomes `detached` when its source transaction is deleted —
  /// the food does not un-exist because the receipt did.
  TextColumn get origin => text().map(const BatchOriginConverter())();

  /// Optional free-text location, e.g. `Top shelf`.
  TextColumn get storageLocation => text().nullable()();

  /// Optional free-text note.
  TextColumn get note => text().nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// An immutable event changing a batch's remaining quantity — the second of the app's three
/// append-only truths (ARCH_1 §3.3).
///
/// **Explicit exception to Law L6: this table has no `deletedAt`.** Corrections insert a
/// *reversing* row pointing at the original through [reversesMovementId]. A ledger you can edit
/// is not a ledger: undo in the UI writes a reversal, so the user sees "removed", the audit
/// trail survives, and the food-waste analytics in ARCH_3 §5.1 query 14 stay honest.
@DataClassName('StockMovementRow')
class StockMovements extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// The batch this movement applies to.
  TextColumn get batchId => text().references(InventoryBatches, #id)();

  /// The owning item, denormalised from the batch purely so per-item analytics never need the
  /// join (ARCH_2 §5.3).
  TextColumn get itemId => text().references(Items, #id)();

  /// What kind of event this was. [quantityMilli] is always positive; this column carries the
  /// direction.
  TextColumn get kind => text().map(const StockMovementKindConverter())();

  /// Quantity moved, in base-milli units, always positive.
  IntColumn get quantityMilli => integer()();

  /// When it happened, epoch millis UTC.
  IntColumn get occurredAt => integer()();

  /// The local civil date it happened on.
  IntColumn get dateKey => integer().map(const DateKeyConverter())();

  /// Optional structured reason, e.g. why something was wasted.
  TextColumn get reason => text().nullable()();

  /// Optional free-text note.
  TextColumn get note => text().nullable()();

  /// The transaction that caused this movement, for purchase-driven stock increases.
  TextColumn get linkedTransactionId => text().nullable().references(Transactions, #id)();

  /// The movement this row reverses. Non-null exactly on correction rows.
  TextColumn get reversesMovementId => text().nullable().references(StockMovements, #id)();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC. Present for uniformity with ARCH_2 §2; an
  /// append-only row is never updated in practice.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        // Beyond ARCH_2's literal spec, which states this invariant in prose only
        // ("always > 0"). Declared here because Law L3 makes every derived stock figure depend
        // on it: a zero or negative row would corrupt both `recomputeRemaining` and the waste
        // analytics, and neither would report an error. See the deviation note in the phase
        // report.
        'CHECK (quantity_milli > 0)',
      ];
}

```

### `lib/data/db/tables/shopping_tables.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/data/db/converters/date_key_converter.dart';
import 'package:alaya/data/db/converters/enum_converters.dart';
import 'package:alaya/data/db/tables/inventory_tables.dart';
import 'package:alaya/data/db/tables/meta_tables.dart';
import 'package:alaya/data/db/tables/money_tables.dart';
import 'package:alaya/data/db/tables/tag_tables.dart';

/// A shopping list. Multiple lists are supported, with one marked default so the app still
/// feels like it has just one (ARCH_4 open decision 5).
@DataClassName('ShoppingListRow')
class ShoppingLists extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Display name.
  TextColumn get name => text()();

  /// The list quick-add writes to when the user does not choose one.
  BoolColumn get isDefault => boolean()();

  /// Retired but kept for history.
  BoolColumn get isArchived => boolean()();

  /// Optional civil date the user intends to shop on; surfaces on the calendar.
  IntColumn get targetDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// An intent to buy something. May or may not link to a catalogued [Items] row.
///
/// [origin], [autoState] and [generatedAtStockMilli] together are what make low-stock
/// auto-generation idempotent *and* dismissible without the entry reappearing on the next run
/// (anomalies A22 and A23) — the hardest behaviour in the shopping module to get right, and it
/// is carried entirely by these three columns plus Phase 1C's partial unique index.
@DataClassName('ShoppingEntryRow')
class ShoppingEntries extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// The list this entry belongs to.
  TextColumn get listId => text().references(ShoppingLists, #id)();

  /// The catalogued item, when this entry refers to one. Nullable so `TV ☐` works without
  /// inventing an inventory item (anomaly A24).
  TextColumn get itemId => text().nullable().references(Items, #id)();

  /// What to buy, when there is no [itemId].
  TextColumn get freeText => text().nullable()();

  /// How much to buy, in base-milli units. Null renders as no quantity at all rather than `0`.
  IntColumn get quantityMilli => integer().nullable()();

  /// The unit the user typed, for display.
  TextColumn get unitCode => text().nullable().references(Units, #code)();

  /// The group header this entry appears under — `Grocery`, `Beauty`, `Electronics`. A direct
  /// column rather than a join table, because unlike the other modules an entry belongs to
  /// exactly one group (ARCH_2 §6).
  TextColumn get tagId => text().nullable().references(Tags, #id)();

  /// Optional expected price in minor units, for the running list estimate.
  IntColumn get estimatedPriceMinor => integer().nullable()();

  /// Ticked off in the list.
  BoolColumn get isChecked => boolean()();

  /// When it was ticked, epoch millis UTC.
  IntColumn get checkedAt => integer().nullable()();

  /// How this entry came to exist. Editing an `autoLowStock` entry promotes it to `manual`,
  /// after which the suggestion engine never removes it.
  TextColumn get origin => text().map(const ShoppingEntryOriginConverter())();

  /// Lifecycle of an auto-generated entry, so a dismissal survives the next regeneration.
  TextColumn get autoState => text().map(const ShoppingEntryAutoStateConverter())();

  /// Hide an auto entry until this civil date.
  IntColumn get snoozeUntilDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// The item's total remaining stock at the moment this entry was auto-generated, in
  /// base-milli units. The comparison point that stops a dismissed suggestion from returning
  /// until stock has genuinely risen above the threshold and fallen again.
  IntColumn get generatedAtStockMilli => integer().nullable()();

  /// The transaction line that fulfilled this entry, set by convert-to-purchase (anomaly A25).
  TextColumn get purchasedTransactionLineId =>
      text().nullable().references(TransactionLines, #id)();

  /// Manual ordering within its group.
  IntColumn get sortOrder => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

```

### `lib/data/db/tables/recurring_tables.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/data/db/converters/date_key_converter.dart';
import 'package:alaya/data/db/converters/enum_converters.dart';
import 'package:alaya/data/db/tables/meta_tables.dart';
import 'package:alaya/data/db/tables/money_tables.dart';
import 'package:alaya/data/db/tables/service_tables.dart';
import 'package:alaya/data/db/tables/tag_tables.dart';

/// A repeating obligation or income (ARCH_1 §3.2).
///
/// [direction] is what lets salary live here rather than needing a second, parallel system
/// (anomaly A27).
@DataClassName('RecurringTemplateRow')
class RecurringTemplates extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Display name as the user typed it.
  TextColumn get name => text()();

  /// Normalised form used for identity matching only, never displayed.
  TextColumn get normalizedName => text()();

  /// Rough classification, for grouping and iconography.
  TextColumn get kind => text().map(const RecurringKindConverter())();

  /// Whether settling an occurrence creates a withdrawal or a deposit.
  TextColumn get direction => text().map(const RecurringDirectionConverter())();

  /// The usual amount in minor units. An occurrence may be settled for a different amount, which
  /// is recorded on the occurrence rather than overwriting this (anomaly A29).
  IntColumn get defaultAmountMinor => integer()();

  /// Currency of [defaultAmountMinor].
  TextColumn get currencyCode => text().references(Currencies, #code)();

  /// Who is billed or who pays.
  TextColumn get payeeId => text().nullable().references(Payees, #id)();

  /// The account settlement defaults to.
  TextColumn get defaultAccountId => text().nullable().references(Accounts, #id)();

  /// The rail settlement defaults to.
  TextColumn get defaultPaymentMethodId =>
      text().nullable().references(PaymentMethods, #id)();

  /// The tag applied to transactions this template creates.
  TextColumn get tagId => text().nullable().references(Tags, #id)();

  /// The unit the repeat interval is counted in.
  TextColumn get intervalUnit => text().map(const RecurringIntervalUnitConverter())();

  /// How many [intervalUnit]s between occurrences.
  IntColumn get intervalCount => integer()();

  /// Day of month, 1-31, for monthly and yearly intervals.
  ///
  /// **Stored once and clamped at render, never mutated** (anomaly A13). A bill anchored on the
  /// 31st renders as 28, 29 or 30 in short months but stays anchored on the 31st, instead of
  /// walking backwards to the 28th permanently after one February — which is what happens if the
  /// clamped value is written back.
  IntColumn get anchorDayOfMonth => integer().nullable()();

  /// Month of year, 1-12, for yearly intervals.
  IntColumn get anchorMonth => integer().nullable()();

  /// ISO weekday, 1-7, for weekly intervals.
  IntColumn get anchorWeekday => integer().nullable()();

  /// First civil date this template is active from.
  IntColumn get startDateKey => integer().map(const DateKeyConverter())();

  /// Last civil date this template is active until. Null means indefinite.
  IntColumn get endDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// The next civil date an occurrence is due on.
  IntColumn get nextDueDateKey => integer().map(const DateKeyConverter())();

  /// Suspended without being deleted; no new occurrences materialise.
  BoolColumn get isPaused => boolean()();

  /// Whether to schedule a local notification before each due date.
  BoolColumn get autoRemind => boolean()();

  /// How many days before the due date to remind.
  IntColumn get remindDaysBefore => integer()();

  /// The asset this template pays for — the link that lets a house maid's monthly salary hang
  /// off an [Assets] row (ARCH_2 §8.1).
  TextColumn get linkedAssetId => text().nullable().references(Assets, #id)();

  /// Optional free-text note.
  TextColumn get note => text().nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active. Deleting a template is soft, and
  /// settled occurrences with their transactions survive it (ARCH_3 §4.1).
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One dated instance of a [RecurringTemplates] row — the third of the app's three append-only
/// truths (ARCH_1 §3.3).
///
/// Rows are **materialised lazily** up to today, never in advance and never automatically
/// settled: money is only ever created by an explicit user tap (anomaly A14). A `due` row whose
/// [dueDateKey] has passed renders as *overdue*, which is derived at read time and deliberately
/// not a stored status.
@DataClassName('RecurringOccurrenceRow')
class RecurringOccurrences extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// The template this instance belongs to.
  TextColumn get templateId => text().references(RecurringTemplates, #id)();

  /// The civil date this instance is due on.
  IntColumn get dueDateKey => integer().map(const DateKeyConverter())();

  /// Settlement state. Never `paid` without [paidTransactionId].
  TextColumn get status => text().map(const RecurringOccurrenceStatusConverter())();

  /// The transaction that settled this occurrence.
  TextColumn get paidTransactionId => text().nullable().references(Transactions, #id)();

  /// The amount actually paid, in minor units, which may differ from the template default.
  /// Analytics uses this rather than the default (anomaly A29).
  IntColumn get paidAmountMinor => integer().nullable()();

  /// The civil date it was actually paid on, which may differ from [dueDateKey].
  IntColumn get paidDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// Optional free-text note.
  TextColumn get note => text().nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

```

### `lib/data/db/tables/service_tables.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/data/db/converters/date_key_converter.dart';
import 'package:alaya/data/db/converters/enum_converters.dart';
import 'package:alaya/data/db/tables/meta_tables.dart';
import 'package:alaya/data/db/tables/money_tables.dart';
import 'package:alaya/data/db/tables/recurring_tables.dart';

/// A durable, serviceable, non-consumable thing **or person** (ARCH_1 §3.2).
///
/// [type] `serviceProvider` is how a house maid lives in the same table as a TV: an asset, plus a
/// linked [RecurringTemplates] row for monthly salary, plus a [ServiceRecords] row per payment.
/// No second system (anomaly A30).
///
/// There is no delete path. [status] `disposed` plus [disposalReason] implements "delete my TV by
/// selecting a reason" as a status change, so the money spent on it stays in analytics
/// (ARCH_3 §4.1).
@DataClassName('AssetRow')
class Assets extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Display name as the user typed it.
  TextColumn get name => text()();

  /// Normalised form used for identity matching only, never displayed.
  TextColumn get normalizedName => text()();

  /// What kind of asset — or person — this is.
  TextColumn get type => text().map(const AssetTypeConverter())();

  /// Manufacturer or brand.
  TextColumn get brand => text().nullable()();

  /// Model number.
  TextColumn get modelNo => text().nullable()();

  /// Serial number.
  TextColumn get serialNo => text().nullable()();

  /// Civil date acquired.
  IntColumn get purchaseDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// Purchase price in minor units, paired with [purchaseCurrencyCode].
  IntColumn get purchasePriceMinor => integer().nullable()();

  /// Currency of [purchasePriceMinor].
  TextColumn get purchaseCurrencyCode => text().nullable().references(Currencies, #code)();

  /// The transaction line that created this asset, if it came from a purchase.
  TextColumn get sourceTransactionLineId =>
      text().nullable().references(TransactionLines, #id)();

  /// Civil date warranty cover begins.
  IntColumn get warrantyStartDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// Civil date warranty cover ends. Drives the warranty timeline (ARCH_3 §5.1 query 20) and the
  /// calendar's `warrantyEnd` events.
  IntColumn get warrantyEndDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// Who provides the warranty.
  TextColumn get warrantyProvider => text().nullable()();

  /// Free-text warranty detail.
  TextColumn get warrantyNote => text().nullable()();

  /// Nominal days between services, used to propose [nextServiceDueDateKey].
  IntColumn get serviceIntervalDays => integer().nullable()();

  /// Civil date the next service is due.
  IntColumn get nextServiceDueDateKey =>
      integer().map(const DateKeyConverter()).nullable()();

  /// Primary contact name, e.g. the technician or the person themselves.
  TextColumn get primaryContactName => text().nullable()();

  /// Primary contact phone number, made tappable in the UI.
  TextColumn get primaryContactPhone => text().nullable()();

  /// Where the asset physically is.
  TextColumn get location => text().nullable()();

  /// The recurring template that pays for this asset, e.g. a monthly salary or subscription fee.
  TextColumn get linkedRecurringTemplateId =>
      text().nullable().references(RecurringTemplates, #id)();

  /// Current lifecycle state. Never silently `disposed`.
  TextColumn get status => text().map(const AssetStatusConverter())();

  /// Civil date of disposal.
  IntColumn get disposedAtDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// Why it was disposed of. Non-null exactly when [status] is `disposed`.
  TextColumn get disposalReason =>
      text().map(const AssetDisposalReasonConverter()).nullable()();

  /// Free-text disposal detail.
  TextColumn get disposalNote => text().nullable()();

  /// Sale proceeds in minor units, if sold. Uses the asset's [purchaseCurrencyCode].
  IntColumn get disposalAmountMinor => integer().nullable()();

  /// Optional free-text notes.
  TextColumn get notes => text().nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active. Reserved for the trash screen;
  /// ordinary removal is disposal, not deletion.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One service, repair or payment event against an [Assets] row. Also the payment log for a
/// `serviceProvider` asset, via [type] `salaryPaid`.
@DataClassName('ServiceRecordRow')
class ServiceRecords extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// The asset this record belongs to.
  TextColumn get assetId => text().references(Assets, #id)();

  /// The civil date of the event.
  IntColumn get serviceDateKey => integer().map(const DateKeyConverter())();

  /// What kind of event this was.
  TextColumn get type => text().map(const ServiceRecordTypeConverter())();

  /// Who performed it.
  TextColumn get providerName => text().nullable()();

  /// Their contact number.
  TextColumn get providerPhone => text().nullable()();

  /// Cost in minor units, paired with [currencyCode]. Drives lifetime-service-cost per asset
  /// (ARCH_3 §5.1 query 19).
  IntColumn get costMinor => integer().nullable()();

  /// Currency of [costMinor].
  TextColumn get currencyCode => text().nullable().references(Currencies, #code)();

  /// The withdrawal this cost was booked as, when the user chose to record it as an expense.
  TextColumn get linkedTransactionId => text().nullable().references(Transactions, #id)();

  /// The civil date the next service was scheduled for at the time of this one.
  IntColumn get nextDueDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// Optional free-text notes.
  TextColumn get notes => text().nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

```

### `lib/data/db/tables/ops_tables.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/data/db/converters/enum_converters.dart';

/// One scheduled local notification (ARCH_3 §7).
///
/// Exists so every Android notification has a stable id that can be cancelled when the
/// underlying record changes. Without it you get orphaned reminders for food already eaten.
@DataClassName('NotificationScheduleRow')
class NotificationSchedule extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// What kind of event this reminder is for.
  TextColumn get kind => text().map(const NotificationKindConverter())();

  /// Which kind of record this points at, e.g. `inventoryBatch`, `asset`. Free text and
  /// deliberately not a foreign key: like [Attachments] this is genuinely polymorphic, and
  /// [refId] may outlive the row it names.
  TextColumn get refType => text()();

  /// The referenced record's id.
  TextColumn get refId => text()();

  /// When the OS should fire it, epoch millis UTC.
  IntColumn get scheduledAtUtcMillis => integer()();

  /// The stable id handed to Android, so this reminder can be cancelled later.
  IntColumn get androidNotificationId => integer()();

  /// Lifecycle state. `cancelled` rows are retained so a re-schedule can reuse the id.
  TextColumn get status => text().map(const NotificationStatusConverter())();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A log of exports the user has taken, for their own reference (ARCH_3 §3.1).
@DataClassName('BackupHistoryRow')
class BackupHistory extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Where the file was written. Recorded for display only — the path may since have moved or
  /// been deleted, and nothing reads from it.
  TextColumn get filePath => text()();

  /// Size of the produced file in bytes.
  IntColumn get sizeBytes => integer()();

  /// The schema version at export time, so a restore can refuse a newer file (anomaly A32).
  IntColumn get schemaVersion => integer()();

  /// The app version at export time.
  TextColumn get appVersion => text()();

  /// Whether the user triggered it or a background job did.
  TextColumn get kind => text().map(const BackupKindConverter())();

  /// Per-table row counts as JSON, so a restore can be sanity-checked against the export.
  TextColumn get recordCountsJson => text().nullable()();

  /// Optional free-text note.
  TextColumn get note => text().nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Memoised results for analytics queries slower than roughly 200 ms (ARCH_3 §5.2). Defined in
/// Phase 1B and unused until Phase 7B purely so that adding it later is not a migration.
/// Natural text key.
@DataClassName('AnalyticsCacheRow')
class AnalyticsCache extends Table {
  /// The query's name, e.g. `spendBySubtype`.
  TextColumn get cacheKey => text()();

  /// Hash of the query parameters, so the same query with different arguments does not collide.
  TextColumn get paramsHash => text()();

  /// The memoised result as JSON.
  TextColumn get payloadJson => text()();

  /// When it was computed, epoch millis UTC.
  IntColumn get computedAt => integer()();

  /// After this instant the entry is stale, epoch millis UTC. Invalidation on write to a
  /// contributing table is the primary mechanism; this is the backstop.
  IntColumn get staleAfter => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active. Present for uniformity with
  /// ARCH_2 §2 only — a cache entry is evicted rather than soft-deleted, so this is a candidate
  /// for removal if you would rather the schema not carry a column nothing will set.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {cacheKey};
}

```

### `lib/data/db/converters/money_converter.dart`

```dart
import 'package:alaya/core/money/money.dart';

/// Composes and decomposes [Money] across the two-column pairs the schema stores it in.
///
/// **This is deliberately not a drift `TypeConverter`.** A `TypeConverter` maps exactly one
/// column to one Dart value, and every monetary value in ARCH_2 is stored as *two* columns — an
/// `INTEGER` minor-unit amount plus a sibling `TEXT` currency code (Law L1, and ARCH_2 §4.1's
/// `original_amount_minor` / `original_currency_code`). A converter cannot read a sibling
/// column, so the composition has to happen one level up, in the mappers of Phases 3B-3D.
///
/// Keeping the pairing in one place matters because the pairs are not uniformly named:
/// `(originalAmountMinor, originalCurrencyCode)`, `(convertedAmountMinor,
/// convertedCurrencyCode)`, `(unitCostMinor, costCurrencyCode)`, `(purchasePriceMinor,
/// purchaseCurrencyCode)`, `(costMinor, currencyCode)`. Every one of those is a chance to
/// silently pair an amount with the wrong currency, which is exactly the class of bug Law L1
/// exists to prevent.
///
/// The amount columns are plain `integer()` in the table definitions, so the raw minor units
/// stay directly available to SQL aggregation (ARCH_3 §5.2 requires summing in SQL, never in
/// Dart) — a per-column type converter would not have prevented that, but it is worth stating
/// that the absence of one costs nothing here.
abstract final class MoneyColumns {
  /// Builds [Money] from a non-null amount/currency column pair.
  static Money read(int minorUnits, String currencyCode) => Money(minorUnits, currencyCode);

  /// Builds [Money] from a nullable pair, returning `null` when either column is null.
  ///
  /// Both columns are required to be null or non-null together; a half-populated pair means an
  /// amount whose currency is unknown, which cannot be represented and must not be guessed.
  /// Throws [ArgumentError] on a half-populated pair so the inconsistency surfaces at the
  /// mapper rather than as a wrong number on a dashboard.
  static Money? readNullable(int? minorUnits, String? currencyCode) {
    if (minorUnits == null && currencyCode == null) return null;
    if (minorUnits == null || currencyCode == null) {
      throw ArgumentError(
        'Half-populated money pair: minorUnits=$minorUnits, currencyCode=$currencyCode. '
        'An amount and its currency must be stored and cleared together.',
      );
    }
    return Money(minorUnits, currencyCode);
  }

  /// The value for the `INTEGER` minor-unit column.
  static int minorOf(Money money) => money.minor;

  /// The value for the sibling `TEXT` currency-code column.
  static String codeOf(Money money) => money.currencyCode;

  /// The minor-unit column value for a nullable [Money].
  static int? minorOfNullable(Money? money) => money?.minor;

  /// The currency-code column value for a nullable [Money].
  static String? codeOfNullable(Money? money) => money?.currencyCode;
}

```

### `lib/data/db/converters/qty_converter.dart`

```dart
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';

/// Composes and decomposes [Qty] from the quantity columns the schema stores it in.
///
/// **This is deliberately not a drift `TypeConverter`**, and for a stronger reason than
/// [MoneyColumns]. A [Qty] needs a [UnitCategory], and no table stores one next to its
/// quantity — the category lives on `items.unit_category` (for anything item-linked) or
/// `units.category` (for a bare unit code). So building a [Qty] requires a **join or a cached
/// unit lookup**, not just two columns of the same row:
///
/// | Quantity column | Category comes from |
/// |---|---|
/// | `transaction_lines.quantity_milli` | `items.unit_category` via `item_id`, else `units.category` via `unit_code` |
/// | `inventory_batches.initial_quantity_milli` / `remaining_quantity_milli` | `items.unit_category` via `item_id` |
/// | `stock_movements.quantity_milli` | `items.unit_category` via `item_id` |
/// | `shopping_entries.quantity_milli` | `items.unit_category` via `item_id`, else `units.category` via `unit_code` |
/// | `items.low_stock_threshold_milli` | `items.unit_category` on the same row |
///
/// The two rows with an "else" are the ones to watch: a `transaction_lines` or
/// `shopping_entries` row may have a quantity and a unit but **no** `item_id` (buying something
/// never catalogued, ARCH_2 §4.2 and §6), in which case the category must come from the unit.
/// A row with a quantity but neither an item nor a unit has no recoverable category at all;
/// [readOrNull] returns `null` for that case rather than inventing one.
///
/// Every quantity column already stores **base-milli units**, never the purchased unit
/// (ARCH_2 §4.2: "Qty base x 1000"). `unit_code` and `unit_code_at_purchase` exist only to
/// render what the user originally typed — `2 kg` rather than `2000 g`. That is why ARCH_3
/// §5.1's queries 10 and 24 need no unit conversion: they aggregate `quantity_milli` directly.
/// Comparisons remain valid only *within* one item, since an item's category is immutable
/// (Law L8) but milli-grams and milli-pieces are not comparable across items.
abstract final class QtyColumns {
  /// Builds [Qty] from a non-null quantity column and a category resolved by the caller.
  static Qty read(int quantityMilli, UnitCategory category) => Qty(quantityMilli, category);

  /// Builds [Qty] when either the quantity or the resolved category may be absent.
  ///
  /// Returns `null` if [quantityMilli] is null (the row simply has no quantity — a `TV ☐`
  /// shopping entry) or if [category] could not be resolved from an item or a unit.
  static Qty? readOrNull(int? quantityMilli, UnitCategory? category) {
    if (quantityMilli == null || category == null) return null;
    return Qty(quantityMilli, category);
  }

  /// The value for the `INTEGER` base-milli quantity column.
  static int milliOf(Qty qty) => qty.milliBase;

  /// The base-milli column value for a nullable [Qty].
  static int? milliOfNullable(Qty? qty) => qty?.milliBase;
}

```

### `lib/data/db/converters/date_key_converter.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/time/date_key.dart';

/// Maps a [DateKey] to the single `INTEGER` column that stores it as `yyyymmdd` (Law L4).
/// Applied to every civil-date column in the schema; instants stay plain `int` epoch millis
/// and are never routed through this converter.
///
/// Uses the non-validating `DateKey(int)` constructor on read by design: a stored row is
/// already-validated data, and re-running [DateKey.fromYmd]'s calendar check on every row of
/// every query would cost a `DateTime` allocation per value for no benefit. Values enter the
/// database only through [DateKey.fromYmd] or [DateKey.fromDateTime], both of which validate.
final class DateKeyConverter extends TypeConverter<DateKey, int> {
  /// Creates the converter.
  const DateKeyConverter();

  @override
  DateKey fromSql(int fromDb) => DateKey(fromDb);

  @override
  int toSql(DateKey value) => value.value;
}

```

### `lib/data/db/converters/enum_converters.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/enums/safe_enum_converter.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';

/// Bridges Phase 1A's [SafeEnumConverter] into drift's [TypeConverter], so every enum column
/// in the schema stores `Enum.name` as `TEXT` and degrades an unrecognised value to a declared
/// fallback instead of throwing (Law L13).
///
/// Drift's own `textEnum()` column type is deliberately **not** used: it throws on a value
/// that matches no current member, which would make a database written by a newer build
/// unreadable by an older one. L13 requires the opposite behaviour.
///
/// Choosing a fallback is a real decision, not a formality — it is the value the app will show
/// for a row it cannot interpret. Two principles applied throughout below: prefer the member
/// that **understates** rather than overstates (money and stock), and never pick a member whose
/// meaning is "already handled" (`paid`, `disposed`, `dismissed`), because silently marking an
/// obligation settled is the one failure a user cannot detect.
abstract class SafeEnumTypeConverter<T extends Enum> extends TypeConverter<T, String> {
  /// Creates the converter.
  const SafeEnumTypeConverter();

  /// The Phase 1A converter holding this enum's members and its fallback.
  SafeEnumConverter<T> get delegate;

  @override
  T fromSql(String fromDb) => delegate.fromSql(fromDb);

  @override
  String toSql(T value) => delegate.toSql(value);
}

// ── Money ────────────────────────────────────────────────────────────────────────────────

/// Stores [TransactionKind]. Falls back to [TransactionKind.withdrawal]: it is the only choice
/// that understates available funds, and an unreadable `kind` must never inflate a balance.
final class TransactionKindConverter extends SafeEnumTypeConverter<TransactionKind> {
  /// Creates the converter.
  const TransactionKindConverter();

  @override
  SafeEnumConverter<TransactionKind> get delegate =>
      const SafeEnumConverter(TransactionKind.values, TransactionKind.withdrawal);
}

/// Stores [TransactionSubtype]. Falls back to [TransactionSubtype.otherOut], the catch-all
/// outflow bucket.
final class TransactionSubtypeConverter extends SafeEnumTypeConverter<TransactionSubtype> {
  /// Creates the converter.
  const TransactionSubtypeConverter();

  @override
  SafeEnumConverter<TransactionSubtype> get delegate =>
      const SafeEnumConverter(TransactionSubtype.values, TransactionSubtype.otherOut);
}

/// Stores [AccountKind]. Falls back to [AccountKind.other].
final class AccountKindConverter extends SafeEnumTypeConverter<AccountKind> {
  /// Creates the converter.
  const AccountKindConverter();

  @override
  SafeEnumConverter<AccountKind> get delegate =>
      const SafeEnumConverter(AccountKind.values, AccountKind.other);
}

/// Stores [PaymentMethodKind]. Falls back to [PaymentMethodKind.other].
final class PaymentMethodKindConverter extends SafeEnumTypeConverter<PaymentMethodKind> {
  /// Creates the converter.
  const PaymentMethodKindConverter();

  @override
  SafeEnumConverter<PaymentMethodKind> get delegate =>
      const SafeEnumConverter(PaymentMethodKind.values, PaymentMethodKind.other);
}

/// Stores [PayeeKind]. Falls back to [PayeeKind.other].
final class PayeeKindConverter extends SafeEnumTypeConverter<PayeeKind> {
  /// Creates the converter.
  const PayeeKindConverter();

  @override
  SafeEnumConverter<PayeeKind> get delegate =>
      const SafeEnumConverter(PayeeKind.values, PayeeKind.other);
}

/// Stores [TransactionLineDestination]. Falls back to [TransactionLineDestination.none] —
/// claiming a line produced no artefact is safe, whereas claiming it produced one would send
/// the fan-out service looking for a batch or asset that does not exist.
final class TransactionLineDestinationConverter
    extends SafeEnumTypeConverter<TransactionLineDestination> {
  /// Creates the converter.
  const TransactionLineDestinationConverter();

  @override
  SafeEnumConverter<TransactionLineDestination> get delegate => const SafeEnumConverter(
        TransactionLineDestination.values,
        TransactionLineDestination.none,
      );
}

// ── Quantity ─────────────────────────────────────────────────────────────────────────────

/// Stores [UnitCategory]. Falls back to [UnitCategory.count], the only category the formatter
/// never decomposes into a big/small unit pair, so a misread category cannot render a
/// nonsensical `"4 kg 450 g"` for something that was never a weight.
final class UnitCategoryConverter extends SafeEnumTypeConverter<UnitCategory> {
  /// Creates the converter.
  const UnitCategoryConverter();

  @override
  SafeEnumConverter<UnitCategory> get delegate =>
      const SafeEnumConverter(UnitCategory.values, UnitCategory.count);
}

// ── Inventory ────────────────────────────────────────────────────────────────────────────

/// Stores [ItemKind]. Falls back to [ItemKind.generic], the declared "no classification" value.
final class ItemKindConverter extends SafeEnumTypeConverter<ItemKind> {
  /// Creates the converter.
  const ItemKindConverter();

  @override
  SafeEnumConverter<ItemKind> get delegate =>
      const SafeEnumConverter(ItemKind.values, ItemKind.generic);
}

/// Stores [BatchOrigin]. Falls back to [BatchOrigin.manual] — a neutral provenance that claims
/// no link to a transaction, so nothing downstream tries to follow a source that isn't there.
final class BatchOriginConverter extends SafeEnumTypeConverter<BatchOrigin> {
  /// Creates the converter.
  const BatchOriginConverter();

  @override
  SafeEnumConverter<BatchOrigin> get delegate =>
      const SafeEnumConverter(BatchOrigin.values, BatchOrigin.manual);
}

/// Stores [StockMovementKind]. Falls back to [StockMovementKind.adjustOut].
///
/// This fallback is the most consequential in the schema, because an unreadable movement kind
/// means the *direction* of a stock change is unknown. `adjustOut` is chosen for two reasons:
/// it understates stock (the user re-adds food rather than trusting food they do not have), and
/// it is not `waste` or `expired`, so the food-waste analytics in ARCH_3 §5.1 query 14 stay
/// honest rather than absorbing unclassifiable rows.
final class StockMovementKindConverter extends SafeEnumTypeConverter<StockMovementKind> {
  /// Creates the converter.
  const StockMovementKindConverter();

  @override
  SafeEnumConverter<StockMovementKind> get delegate =>
      const SafeEnumConverter(StockMovementKind.values, StockMovementKind.adjustOut);
}

// ── Shopping ─────────────────────────────────────────────────────────────────────────────

/// Stores [ShoppingEntryOrigin]. Falls back to [ShoppingEntryOrigin.manual], which the
/// suggestion engine never auto-removes — losing a user's own entry is worse than keeping a
/// stale generated one.
final class ShoppingEntryOriginConverter extends SafeEnumTypeConverter<ShoppingEntryOrigin> {
  /// Creates the converter.
  const ShoppingEntryOriginConverter();

  @override
  SafeEnumConverter<ShoppingEntryOrigin> get delegate =>
      const SafeEnumConverter(ShoppingEntryOrigin.values, ShoppingEntryOrigin.manual);
}

/// Stores [ShoppingEntryAutoState]. Falls back to [ShoppingEntryAutoState.active] — a visible
/// entry the user can dismiss, rather than a hidden one they cannot discover.
final class ShoppingEntryAutoStateConverter
    extends SafeEnumTypeConverter<ShoppingEntryAutoState> {
  /// Creates the converter.
  const ShoppingEntryAutoStateConverter();

  @override
  SafeEnumConverter<ShoppingEntryAutoState> get delegate => const SafeEnumConverter(
        ShoppingEntryAutoState.values,
        ShoppingEntryAutoState.active,
      );
}

// ── Recurring ────────────────────────────────────────────────────────────────────────────

/// Stores [RecurringKind]. Falls back to [RecurringKind.other].
final class RecurringKindConverter extends SafeEnumTypeConverter<RecurringKind> {
  /// Creates the converter.
  const RecurringKindConverter();

  @override
  SafeEnumConverter<RecurringKind> get delegate =>
      const SafeEnumConverter(RecurringKind.values, RecurringKind.other);
}

/// Stores [RecurringDirection]. Falls back to [RecurringDirection.outflow]: presenting an
/// unreadable obligation as something owed is safer than presenting it as income.
final class RecurringDirectionConverter extends SafeEnumTypeConverter<RecurringDirection> {
  /// Creates the converter.
  const RecurringDirectionConverter();

  @override
  SafeEnumConverter<RecurringDirection> get delegate =>
      const SafeEnumConverter(RecurringDirection.values, RecurringDirection.outflow);
}

/// Stores [RecurringIntervalUnit]. Falls back to [RecurringIntervalUnit.month], by far the most
/// common real interval, so a misread row lands on the most probable schedule and the user can
/// see and correct it on the template screen.
final class RecurringIntervalUnitConverter extends SafeEnumTypeConverter<RecurringIntervalUnit> {
  /// Creates the converter.
  const RecurringIntervalUnitConverter();

  @override
  SafeEnumConverter<RecurringIntervalUnit> get delegate => const SafeEnumConverter(
        RecurringIntervalUnit.values,
        RecurringIntervalUnit.month,
      );
}

/// Stores [RecurringOccurrenceStatus]. Falls back to [RecurringOccurrenceStatus.due], never
/// `paid` — silently reporting a bill as settled is the one degradation a user cannot notice
/// until it costs them a late fee.
final class RecurringOccurrenceStatusConverter
    extends SafeEnumTypeConverter<RecurringOccurrenceStatus> {
  /// Creates the converter.
  const RecurringOccurrenceStatusConverter();

  @override
  SafeEnumConverter<RecurringOccurrenceStatus> get delegate => const SafeEnumConverter(
        RecurringOccurrenceStatus.values,
        RecurringOccurrenceStatus.due,
      );
}

// ── Service ──────────────────────────────────────────────────────────────────────────────

/// Stores [AssetType]. Falls back to [AssetType.other].
final class AssetTypeConverter extends SafeEnumTypeConverter<AssetType> {
  /// Creates the converter.
  const AssetTypeConverter();

  @override
  SafeEnumConverter<AssetType> get delegate =>
      const SafeEnumConverter(AssetType.values, AssetType.other);
}

/// Stores [AssetStatus]. Falls back to [AssetStatus.active], never `disposed` — an asset must
/// never disappear from the user's list because one column could not be read.
final class AssetStatusConverter extends SafeEnumTypeConverter<AssetStatus> {
  /// Creates the converter.
  const AssetStatusConverter();

  @override
  SafeEnumConverter<AssetStatus> get delegate =>
      const SafeEnumConverter(AssetStatus.values, AssetStatus.active);
}

/// Stores [AssetDisposalReason]. Falls back to [AssetDisposalReason.other].
final class AssetDisposalReasonConverter extends SafeEnumTypeConverter<AssetDisposalReason> {
  /// Creates the converter.
  const AssetDisposalReasonConverter();

  @override
  SafeEnumConverter<AssetDisposalReason> get delegate =>
      const SafeEnumConverter(AssetDisposalReason.values, AssetDisposalReason.other);
}

/// Stores [ServiceRecordType]. Falls back to [ServiceRecordType.other].
final class ServiceRecordTypeConverter extends SafeEnumTypeConverter<ServiceRecordType> {
  /// Creates the converter.
  const ServiceRecordTypeConverter();

  @override
  SafeEnumConverter<ServiceRecordType> get delegate =>
      const SafeEnumConverter(ServiceRecordType.values, ServiceRecordType.other);
}

// ── Ops ──────────────────────────────────────────────────────────────────────────────────

/// Stores [NotificationKind]. Falls back to [NotificationKind.expiry]. Low stakes: these rows
/// are transient scheduling records, rebuilt by the daily job in Phase 8B.
final class NotificationKindConverter extends SafeEnumTypeConverter<NotificationKind> {
  /// Creates the converter.
  const NotificationKindConverter();

  @override
  SafeEnumConverter<NotificationKind> get delegate =>
      const SafeEnumConverter(NotificationKind.values, NotificationKind.expiry);
}

/// Stores [NotificationStatus]. Falls back to [NotificationStatus.cancelled], so a row whose
/// state cannot be read is never re-fired at the user.
final class NotificationStatusConverter extends SafeEnumTypeConverter<NotificationStatus> {
  /// Creates the converter.
  const NotificationStatusConverter();

  @override
  SafeEnumConverter<NotificationStatus> get delegate =>
      const SafeEnumConverter(NotificationStatus.values, NotificationStatus.cancelled);
}

/// Stores [BackupKind]. Falls back to [BackupKind.manual].
final class BackupKindConverter extends SafeEnumTypeConverter<BackupKind> {
  /// Creates the converter.
  const BackupKindConverter();

  @override
  SafeEnumConverter<BackupKind> get delegate =>
      const SafeEnumConverter(BackupKind.values, BackupKind.manual);
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
/// This class is intentionally minimal in Phase 1B — it declares the 26 tables and the schema
/// version, nothing else. Phase 1C adds the 11 views, the indexes, the FTS5 tables, the
/// [MigrationStrategy] (including `PRAGMA foreign_keys = ON`, which is **not** on until then)
/// and the seed data. Phases 2A-2C add the DAOs.
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
)
class AlayaDatabase extends _$AlayaDatabase {
  /// Opens the database over [executor].
  ///
  /// Never construct this directly outside `open_database.dart` — Law L10 requires exactly one
  /// open path, and that file is it (arriving in Phase 1C).
  AlayaDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}

```
