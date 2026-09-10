# Alaya · PROMPTS — Execution Playbook

Your working file. **Never attach this to a prompt** — it is for you, not the model.

Contents: phase plan (§1), dependency gates (§2), the preamble (§3), all 23 prompts (§4),
definition of done (§5), release checklist (§6), quota tactics (§7).

---

## 1. Phase plan

23 code phases. Each is sized to fit one conversation and to produce **complete files you
never revisit**, except explicitly-marked placeholders.

Effort: **T+** = extended thinking on · **T−** = off.

| Phase  | Output file                  | Contents                                                                                | Files | Attach       | Model / effort                   |
| ------ | ---------------------------- | --------------------------------------------------------------------------------------- | ----- | ------------ | -------------------------------- |
| **1A** | `PHASE_01A_CORE.md`          | pubspec, analysis_options, all `core/` value objects + tests                            | ~22   | A1           | Sonnet 5 · **T+**                |
| **1B** | `PHASE_01B_DATABASE.md`      | all 31 drift tables, converters, CHECKs, database class                                 | ~13   | A1 A2        | **Opus 5** if available · **T+** |
| **1C** | `PHASE_01C_DB_RUNTIME.md`    | 11 views, indexes, FTS, migrations, seed, open path                                     | ~14   | A1 A2        | Sonnet 5 · **T+**                |
| 2A     | `PHASE_02A_DAO_MONEY.md`     | DAOs: settings, currencies, units, tags, accounts, methods, payees, transactions, lines | ~10   | A1 A2        | Sonnet 5 · T+                    |
| 2B     | `PHASE_02B_DAO_STOCK.md`     | DAOs: items, batches, movements, shopping                                               | ~6    | A1 A2        | Sonnet 5 · T−                    |
| 2C     | `PHASE_02C_DAO_REST.md`      | DAOs: recurring, assets, service, ops                                                   | ~8    | A1 A2        | Sonnet 5 · T−                    |
| 3A     | `PHASE_03A_DOMAIN.md`        | pure entities + all repository contracts                                                | ~26   | A1 A2        | Sonnet 5 · T+                    |
| 3B     | `PHASE_03B_REPO_MONEY.md`    | money + tag repo impls, mappers                                                         | ~10   | A1 A2 A3     | Sonnet 5 · T+                    |
| 3C     | `PHASE_03C_REPO_STOCK.md`    | inventory + shopping repo impls                                                         | ~8    | A1 A2 A3     | Sonnet 5 · T+                    |
| 3D     | `PHASE_03D_REPO_REST.md`     | recurring + service repo impls                                                          | ~8    | A1 A2        | Sonnet 5 · T−                    |
| 4A     | `PHASE_04A_ENGINE_MONEY.md`  | unit engine, balance, currency service + API client, network policy                     | ~8    | A1 A3        | Sonnet 5 · **T+**                |
| 4B     | `PHASE_04B_ENGINE_STOCK.md`  | FEFO consumption, reconciler, low-stock engine, recurring engine, purchase fan-out      | ~7    | A1 A3        | Sonnet 5 · **T+**                |
| 4C     | `PHASE_04C_ENGINE_REST.md`   | calendar aggregator, 24 analytics queries, backup/restore, app lock                     | ~11   | A1 A3        | Sonnet 5 · **T+**                |
| 5      | `PHASE_05_SHELL.md`          | theme system, router, drawer, l10n, ~18 shared widgets, Theme Lab                       | ~42   | A1 A3        | Sonnet 5 · T+                    |
| **5F** | `PHASE_05_FIXES.md`          | audit fixes: bottom sheet, QtyParser, scroll-safe states, FAB, ink, routes, overflow test | 20  | A1 A3        | **applied — gate for 6A**        |
| 6A     | `PHASE_06A_UI_EXPENSE.md`    | shared UI kit, quick-add, subtype forms, list, filters, detail, line editor              | ~26   | A1 A5 P3A P5 | Sonnet 5 · **T+**                |
| 6B     | `PHASE_06B_UI_INVENTORY.md`  | item list, detail, editors, consume sheet, movement timeline                             | ~16   | A1 A5 P3A P5 | Sonnet 5 · T+                    |
| 6C     | `PHASE_06C_UI_SHOPPING.md`   | grouped list, editor, generate, snooze, convert-to-purchase                              | ~10   | A1 A5 P3A    | Sonnet 5 · T+                    |
| 6D     | `PHASE_06D_UI_RECURRING.md`  | template list, frequency builder, pay sheet, history                                     | ~11   | A1 A5 P3A    | Sonnet 5 · T+                    |
| 6E     | `PHASE_06E_UI_SERVICE.md`    | asset list, detail, warranty/service editors, dispose flow                               | ~12   | A1 A5 P3A    | Sonnet 5 · T+                    |
| 6F     | `PHASE_06F_UI_DASHBOARD.md`  | funds header, insight card, range rows, module grid, FAB wiring                          | ~11   | A1 A3 A5 P3A | Sonnet 5 · **T+**                |
| 7A     | `PHASE_07A_UI_CALENDAR.md`   | `CalendarRepository` impl, month grid, day sheet, event cards                            | ~9    | A1 A2 A3 A5  | Sonnet 5 · T+                    |
| 7B     | `PHASE_07B_UI_ANALYTICS.md`  | `AnalyticsPort` adapter, cache repo, analytics home, charts, drill-downs                 | ~20   | A1 A2 A3 A5  | Sonnet 5 · **T+**                |
| 8A     | `PHASE_08A_SETTINGS_LOCK.md` | onboarding, settings tree, PIN setup, recovery, lock screen                              | ~18   | A1 A3 A5     | Sonnet 5 · **T+**                |
| 8B     | `PHASE_08B_OPS.md`           | backup/restore UI, attachments, Support Us, notifications, trash                         | ~15   | A1 A3 A5     | Sonnet 5 · T+                    |
| 9      | `PHASE_09_POLISH.md`         | animation pass, perf, a11y sweep, release config                                         | ~12   | A1 A5        | Sonnet 5 · T+                    |

`A1` = ARCH_1_FOUNDATION · `A2` = ARCH_2_DATABASE · `A3` = ARCH_3_SUBSYSTEMS ·
`A5` = ARCH_5_UIUX · `P3A` = PHASE_03A_DOMAIN · `P5` = PHASE_05_SHELL (shared widgets +
`lib/app/providers/` sections only)

**`A5` is not optional on any phase from 6A.** A UI phase without it invents a design system in its
first file, and eleven phases of that is not a product (ARCH_4 R24).

`A1` = ARCH_1_FOUNDATION · `A2` = ARCH_2_DATABASE · `A3` = ARCH_3_SUBSYSTEMS

Plus the immediately-preceding phase output where the task says so. **Attaching more than
listed wastes quota; attaching less produces guesses.**

---

## 2. Dependency gates

```
1A ─> 1B ─> 1C ─> 2A,2B,2C ─> 3A ─> 3B,3C,3D ─> 4A,4B,4C ─> 5 ─> 5F ─┬─> 6A ─> 6B,6F ──> SHIP v1
                                                                      ├─> 6C,6D,6E
                                                                      ├─> 7A,7B
                                                                      └─> 8A,8B ─> 9
```

Phases not listed with an ADD DEPENDENCIES block need **no new packages** — 2A-2C, 3A-3D, 4B, 6A-6F.
If a prompt seems to want one, that is a signal the design drifted.

Never start a phase whose gate is unfinished. **Phase 1B is the one place where slowing down
pays for itself ten times over** — everything after it inherits its shape.

**Two gates are new.** `5F` is the Phase 5 fix pack and is a hard gate: without
`alaya_bottom_sheet.dart` the project does not compile, and without `ScrollSafeCenter` and
`layout_overflow_test.dart` every UI phase inherits the overflow class. **6A now gates 6B–6F**
rather than running beside them, because 6A builds the nine shared UI pieces in ARCH_5 §4.2 that the
other five consume — building them in parallel is how one widget becomes three (ARCH_4 R25).

The `SHIP v1` branch is deliberate. See ARCH_4 R9.

---

## 3. The preamble

Prepend this to every prompt in §4. If you use a **Project**, paste it once into the project's
custom instructions and then only paste the numbered prompt — that removes the repetition
entirely and is the workflow I'd recommend.

``` text

You are a senior Flutter/Dart engineer, system architect and UI/UX designer building
"Alaya", an Android-only finance and home management app.

ARCH_1_FOUNDATION.md §2 (The Laws L1-L14) and §7 (Tech stack) are binding.
ARCH_5_UIUX.md §1 (The UI Laws U1-U20) is binding on every phase from 6A.
Read both before writing anything. Do not deviate from the pinned versions and do not
"upgrade" them. Never add sqlite3_flutter_libs or sqlcipher_flutter_libs. The database
is PLAINTEXT — no encryption, no PRAGMA key, anywhere. Never touch a file under
android/ unless the task explicitly says to.

drift_dev is the ONLY build_runner codegen package in this project (ARCH_1 §7.3). Never
add a second one, and never use @riverpod or go_router_builder — write providers and
routes by hand. A second codegen package makes the whole project unresolvable.
Repository and service providers ALREADY EXIST in lib/app/providers/ (delivered in Phase 5).
A feature's providers/*.dart holds view-model and screen-state providers only — it must
never redeclare a repository or an engine. Watch the existing provider instead.

UI PHASES (6A onward)
- Start every screen from its ARCH_5 §3 archetype. Do not invent a seventh.
- Every screen implements loading, empty, error and populated. All four, every time.
- Every sheet goes through AlayaBottomSheet; every centred full-height state through
  ScrollSafeCenter; every editor through AlayaFormScaffold. Add each new sheet and
  full-height state to test/shared/layout_overflow_test.dart in THIS phase.
- No string literal, no raw colour, spacing, radius, duration, icon size or text style.
- Money through AmountText, Qty through QtyText, DateKey through DateText. Never toString().
- Close every ARCH_5 §7 coverage row assigned to this phase, and say which rows you closed.
- The phase is not done until ARCH_5 §9.1 passes for every screen and §9.2 passes for the
  phase.

Dependencies: NEVER write a version constraint by hand and NEVER use `any` (ARCH_1 §7.4).
If a phase needs a new package, state the `flutter pub add` command and nothing else.
Only add packages that this phase's code actually imports.

An API is verified by compiling against it, not by reading about it (ARCH_4 R22).
If a task appears to conflict with a Law, stop and say so instead of improvising.

OUTPUT CONTRACT
- One markdown file, named exactly as the task specifies.
- For each source file: a heading containing the exact path, then ONE fenced code
  block with the COMPLETE file. Never a fragment. Never "...rest unchanged".
- Code only. No explanation or commentary between files. One exception: a phase from 6A
  ends with a COVERAGE table listing the ARCH_5 §7 rows it closed.
- A file needed by a later phase is created as a minimal compiling placeholder with
  `// PLACEHOLDER: PHASE_XX` on line 1.
- One-line doc comment on every public API. No other comments unless the logic is
  genuinely non-obvious.
- If you run low on room, STOP after a complete file and end with
  `<!-- CONTINUE: next file is lib/... -->`. Never truncate mid-file.
```

That last rule matters more than it looks: a truncated file costs a whole re-run, a clean stop
costs one `continue`.

---

## 4. The 23 prompts

### 1A — Core primitives

```
Attached: ARCH_1_FOUNDATION.md

TASK — PHASE 1A: Project skeleton and core value objects.
Output file: PHASE_01A_CORE.md

ADD DEPENDENCIES FIRST (ARCH_1 §7.4 — never hand-write a version):
  flutter pub add intl uuid
  flutter pub add --dev very_good_analysis

DELIVER
  pubspec.yaml                              ONLY intl + uuid (+ dev very_good_analysis).
                                            No hooks: block. No `any`. Nothing this phase
                                            does not import — see ARCH_1 §7.4.
  analysis_options.yaml                     very_good_analysis + the §6 import-boundary rule
  lib/main.dart                             PLACEHOLDER: PHASE_05. A smoke screen rendering
                                            the critical formatter cases on-device, so the
                                            build is verifiable before Phase 5 exists.
  android/app/src/main/AndroidManifest.xml   allowBackup="false" + dataExtractionRules.
                                            MANDATORY (A42) — the DB lands in Phase 1B.
  android/app/src/main/res/xml/data_extraction_rules.xml
  lib/core/ids/uid.dart                     UUIDv7
  lib/core/time/date_key.dart               extension type, yyyymmdd, monthKey, add/diff days
  lib/core/time/clock.dart                  injectable now(), so time is testable
  lib/core/money/money.dart                 §4.1 — int minor; cross-currency ops throw
  lib/core/money/rounding.dart              MoneyRounding, halfUp default
  lib/core/money/money_parser.dart          locale-aware, returns Result, never throws
  lib/core/money/money_formatter.dart       intl; en_IN lakh/crore grouping
  lib/core/quantity/unit_category.dart      weight | volume | count, with base unit + factor
  lib/core/quantity/qty.dart                §4.2 — int milliBase; cross-category ops throw
  lib/core/quantity/unit_converter.dart     integer factors only, no double anywhere
  lib/core/quantity/qty_formatter.dart      mixed | compact | base styles
  lib/core/text/normalizer.dart             casefold, trim, collapse whitespace, strip
                                            diacritics + punctuation. Exact-match only:
                                            no stemming, no singularisation.
  lib/core/result/result.dart
  lib/core/result/failure.dart
  lib/core/enums/*.dart                     every enum named in ARCH_2, one file per group
  lib/core/enums/safe_enum_converter.dart   unknown string -> declared fallback, never throws
  lib/core/logging/logger.dart
  test/core/money_test.dart
  test/core/qty_test.dart
  test/core/qty_formatter_test.dart
  test/core/date_key_test.dart
  test/core/normalizer_test.dart

CRITICAL — these exact formatter cases must be tests:
  250_000 + 2_000_000 + 1_500_000 + 700_000 = 4_450_000 weight -> "4 kg 450 g"
  2_000_000 weight   -> "2 kg"        (NOT "2 kg 0 g")
  1_200_000 volume   -> "1 L 200 ml"
  500 count          -> "0.5 pc"
  3_000 count        -> "3 pc"
And: Money(100, 'INR') + Money(100, 'USD') must throw.
And: Qty(1000, weight) + Qty(1000, volume) must throw.

NOTE: this phase is permitted to touch android/, and ONLY for those two backup files.

Model: Claude Sonnet 5 · extended thinking ON.
```

### 1B — The database

```
Attached: ARCH_1_FOUNDATION.md, ARCH_2_DATABASE.md, PHASE_01A_CORE.md

TASK — PHASE 1B: The complete drift schema. All 31 tables. Nothing deferred.
Output file: PHASE_01B_DATABASE.md

ADD DEPENDENCIES FIRST (ARCH_1 §7.4 — never hand-write a version):
  flutter pub add drift
  flutter pub add --dev drift_dev build_runner
  # drift_flutter and sqlite3 are NOT needed here — nothing in 1B imports them.
  # They arrive in 1C with open_database.dart. This keeps 1B verifiable with no
  # Android build at all.

DELIVER
  lib/data/db/tables/meta_tables.dart       app_settings, currencies, currency_rates,
                                            units, attachments
  lib/data/db/tables/tag_tables.dart        tags, transaction_tags, item_tags, asset_tags
  lib/data/db/tables/money_tables.dart      accounts, payment_methods, payees,
                                            transactions, transaction_lines
  lib/data/db/tables/inventory_tables.dart  items, inventory_batches, stock_movements
  lib/data/db/tables/shopping_tables.dart   shopping_lists, shopping_entries
  lib/data/db/tables/recurring_tables.dart  recurring_templates, recurring_occurrences
  lib/data/db/tables/service_tables.dart    assets, service_records
  lib/data/db/tables/ops_tables.dart        notification_schedule, backup_history,
                                            analytics_cache
  lib/data/db/converters/money_converter.dart
  lib/data/db/converters/qty_converter.dart
  lib/data/db/converters/date_key_converter.dart
  lib/data/db/converters/enum_converters.dart
  lib/data/db/alaya_database.dart           @DriftDatabase, schemaVersion = 1

HARD REQUIREMENTS
- Every column exactly as ARCH_2 §3-§9 specifies. Do not add, rename or omit columns.
- id TEXT PK + createdAt/updatedAt/deletedAt on every table EXCEPT the four noted in
  ARCH_2 §2, and stock_movements which has NO deletedAt.
- All enums TEXT via SafeEnumConverter from Phase 1A.
- No drift DateTime columns. Instants = int millis UTC. Dates = int dateKey.
- The three CHECK constraints on `transactions` (ARCH_2 §4.1) verbatim in customConstraints.
- Foreign keys via references(). NO ON DELETE CASCADE anywhere.
- Do NOT write views, indexes, FTS, migrations or seed data. That is 1C.

BEFORE the code, output one checklist confirming each of the 24 analytics queries in
ARCH_3 §5.1 is answerable from these tables. If any is not, fix the schema and state
what you changed and why.

Model: Claude Opus 5 if you have access, else Claude Sonnet 5 · extended thinking ON.
This is the highest-value single prompt of the project.
```

### 1C — Database runtime

```
Attached: ARCH_1_FOUNDATION.md, ARCH_2_DATABASE.md, PHASE_01B_DATABASE.md

TASK — PHASE 1C: Views, indexes, FTS, migrations, seed data, and the single open path.
Output file: PHASE_01C_DB_RUNTIME.md

ADD DEPENDENCIES FIRST (ARCH_1 §7.4 — never hand-write a version):
  flutter pub add drift_flutter sqlite3
  # First phase that opens a real database, so first phase that needs a SQLite binary.
  # IMMEDIATELY AFTER: flutter pub deps | grep -i sqlite
  # Confirm NEITHER sqlite3_flutter_libs NOR sqlcipher_flutter_libs appears (ARCH_1 §7.1).
  # If one is pulled in transitively by drift_flutter, stop and report it before building.

Every `CREATE VIEW` must carry an explicit Dart row-class name — `CREATE VIEW v_account_ledger
AS AccountLedgerRow AS SELECT ...` — using the exact names in ARCH_2 §12's table. Never rely on
drift's derived default (view name + `Data`); Phase 2A's nine DAOs reference these names directly.

DELIVER
  lib/data/db/views/account_views.drift      v_account_ledger, v_account_balances
                                             (EXACTLY as written in ARCH_2 §12.1)
  lib/data/db/views/transaction_views.drift  v_active_transactions,
                                             v_transaction_allocation, v_monthly_totals
  lib/data/db/views/inventory_views.drift    v_item_stock, v_batch_stock_check, v_low_stock
  lib/data/db/views/schedule_views.drift     v_recurring_due, v_asset_alerts
  lib/data/db/views/calendar_view.drift      v_calendar_events, 6-source UNION ALL
                                             per ARCH_3 §6
  lib/data/db/indexes.drift                  ARCH_2 §11 verbatim, partial indexes as raw SQL
  lib/data/db/fts.drift                      items_fts + transactions_fts, external content,
                                             3 triggers each
  lib/data/db/migrations/migration_strategy.dart
                                             stepByStep; beforeOpen runs
                                             PRAGMA foreign_keys = ON and, in debug only,
                                             asserts PRAGMA compile_options has ENABLE_FTS5
  lib/data/db/migrations/schema/README.md    how to run drift_dev schema dump / generate
  lib/data/db/seed/seed_data.dart            ARCH_2 §14 in full, including the exact
                                             tag scoping matrix
  lib/data/db/connection/open_database.dart  THE only open path (L10). driftDatabase() with
                                             DriftNativeOptions(shareAcrossIsolates: true).
                                             PLAINTEXT — no PRAGMA key, no cipher check.
  test/data/migration_test.dart              v1 -> v1 passes
  test/data/seed_test.dart
  test/data/view_test.dart

CRITICAL
- view_test.dart MUST prove a self-transfer nets to zero across v_account_balances.
  Insert Cash->Bank 5000, assert total across all accounts is unchanged.
- view_test.dart MUST cover all five transaction kinds against v_account_balances.
- Seeded tag scoping must be exact. A "Kitchen" tag is allowedInInventory + allowedInShopping
  and must NOT appear in the deposit picker. This is visible on first launch.
- Commit a v1 schema snapshot. Without it, step-by-step migrations are impossible later.

Model: Claude Sonnet 5 · extended thinking ON.
```

### 2A — DAOs: money

```
Attached: ARCH_1_FOUNDATION.md, ARCH_2_DATABASE.md, PHASE_01B_DATABASE.md

TASK — PHASE 2A: Data access objects for the money side.
Output file: PHASE_02A_DAO_MONEY.md

DELIVER  lib/data/daos/ : settings_dao, currency_dao, unit_dao, tag_dao, account_dao,
         payment_method_dao, payee_dao, transaction_dao, transaction_line_dao

RULES
- All reads go through the views from 1C, never base tables (L7).
- Anything the UI watches is exposed as a Stream, not a Future.
- Writes touching two tables use a single transaction {} (L14).
- transaction_dao exposes: insert (with lines + tags atomically), softDelete,
  watchByDateRange, watchByAccount, watchBySubtype, monthlyTotals, search via FTS.
- No business rules here. DAOs are typed SQL, nothing more.

Model: Claude Sonnet 5 · extended thinking ON.
```

### 2B — DAOs: stock

```
Attached: ARCH_1_FOUNDATION.md, ARCH_2_DATABASE.md, PHASE_01B_DATABASE.md

TASK — PHASE 2B: Data access objects for inventory and shopping.
Output file: PHASE_02B_DAO_STOCK.md

DELIVER  lib/data/daos/ : item_dao, batch_dao, stock_movement_dao,
         shopping_list_dao, shopping_entry_dao

CRITICAL
- Date filtering uses the DateKeyColumnFilters extension from
  lib/data/db/date_key_filters.dart (isInDateRange, isDateOnOrBefore, ...), never
  isBetweenValues with a raw DateKey — DateKey is not an int (ARCH_1 §4.3).
  Applies to expiry_date_key and purchased_date_key here.
- Every stock write is one transaction {} that inserts a movement AND updates the
  cached remainingQuantityMilli (L3 + L14). Never one without the other.
- stock_movement_dao has NO delete method. Corrections insert a reversing row with
  reversesMovementId set.
- batch_dao.recomputeRemaining(batchId) rebuilds the cache from movements — the L3
  repair path. Also recomputeAll() for the Settings "repair stock" action.
- item_dao.findByIdentity(normalizedName, unitCategory) for the merge decision.

Model: Claude Sonnet 5 · extended thinking OFF.
```

### 2C — DAOs: rest

```
Attached: ARCH_1_FOUNDATION.md, ARCH_2_DATABASE.md, PHASE_01B_DATABASE.md

TASK — PHASE 2C: Data access objects for recurring, service and ops.
Output file: PHASE_02C_DAO_REST.md

DELIVER  lib/data/daos/ : recurring_template_dao, recurring_occurrence_dao, asset_dao,
         service_record_dao, notification_schedule_dao, backup_history_dao,
         analytics_cache_dao

RULES
- Date filtering uses the DateKeyColumnFilters extension from
  lib/data/db/date_key_filters.dart (ARCH_1 §4.3). Applies to due_date_key,
  warranty_end_date_key, next_service_due_date_key and service_records.next_due_date_key.
- recurring_occurrence_dao.upsertForDue(templateId, dueDateKey) must be idempotent —
  the partial unique index makes double-materialisation a no-op, not a crash.
- asset_dao has no delete. dispose(assetId, reason, dateKey, amountMinor) instead.
- Reads via views where a view exists (v_recurring_due, v_asset_alerts).

Model: Claude Sonnet 5 · extended thinking OFF.
```

### 3A — Domain layer

```
Attached: ARCH_1_FOUNDATION.md, ARCH_2_DATABASE.md, PHASE_01A_CORE.md

TASK — PHASE 3A: Pure domain entities and all abstract repository contracts.
Output file: PHASE_03A_DOMAIN.md

DELIVER
  lib/domain/entities/     one file per concept in ARCH_1 §3: Account, PaymentMethod,
                           Payee, Transaction, TransactionLine, Tag, Item, Batch,
                           StockMovement, ShoppingList, ShoppingEntry,
                           RecurringTemplate, RecurringOccurrence, Asset,
                           ServiceRecord, Currency, Unit, CalendarEvent,
                           AccountBalance, ItemStock, ConvertedMoney
  lib/domain/repositories/ abstract contracts, one per aggregate

HARD REQUIREMENTS
- ZERO imports of drift, flutter, or anything under data/ (L12). Pure Dart only.
- Entities use Money, Qty, DateKey — never raw int for an amount or quantity.
- Immutable: final fields, const constructors where possible, copyWith, == and hashCode.
- Repository methods return Future/Stream of entities or Result<T, Failure>.
  No drift row types cross this boundary.
- Derived state is a getter, not a field: Transaction.signedAmount,
  RecurringOccurrence.isOverdue(today), Batch.isExpired(today), Asset.warrantyDaysLeft.

Model: Claude Sonnet 5 · extended thinking ON.
```

### 3B — Repositories: money

```
Attached: ARCH_1_FOUNDATION.md, ARCH_2_DATABASE.md, ARCH_3_SUBSYSTEMS.md,
          PHASE_02A_DAO_MONEY.md, PHASE_03A_DOMAIN.md

TASK — PHASE 3B: Money and tag repository implementations, plus mappers.
Output file: PHASE_03B_REPO_MONEY.md

DELIVER  lib/data/repositories/ : account_repository_impl, payment_method_repository_impl,
         payee_repository_impl, transaction_repository_impl, tag_repository_impl,
         currency_repository_impl, unit_repository_impl, settings_repository_impl
         + lib/data/repositories/mappers/*.dart

Only `accounts` and `transactions` have a Phase 1C view; the other 7 tables these repositories
wrap (`payment_methods`, `payees`, `tags`, `currencies`, `units`, `app_settings`,
`transaction_lines`) do not (ARCH_4 R13). Phase 2A's DAOs already filter `deletedAt` structurally
for those — do not add pass-through views to force a literal L7 reading.

BUSINESS RULES TO ENFORCE HERE
- Transaction shape by kind (ARCH_2 §4.1 CHECKs) validated in Dart too, with a clear
  Failure — do not let users hit a raw SQLite constraint error.
- Quick-add fills accountId from last-used, else the default account. Never null.
- monthKey always derived from dateKey. Never passed in separately. This is the repository's
  job specifically: Phase 2A's TransactionDao takes monthKey as a required field and relies on
  the CHECK constraint to reject a mismatch — it does not derive it, so this layer must.
- Deleting an account with any live transaction returns a Failure.accountInUse.
  Archive is the offered alternative (ARCH_3 §4.1).
- Deleting a transaction: soft-delete, and detach any created batches/assets — never
  cascade-delete them. Return which artefacts were detached so the UI can offer removal
  only when a batch is provably untouched.
- Tag scoping: a tag repository query always takes a scope
  (deposit/withdrawal/inventory/shopping/recurring/service) and filters on allowedIn*.
- Tag nesting depth is capped at 2.

Model: Claude Sonnet 5 · extended thinking ON.
```

### 3C — Repositories: stock

```
Attached: ARCH_1_FOUNDATION.md, ARCH_2_DATABASE.md, ARCH_3_SUBSYSTEMS.md,
          PHASE_02B_DAO_STOCK.md, PHASE_03A_DOMAIN.md

TASK — PHASE 3C: Inventory and shopping repository implementations.
Output file: PHASE_03C_REPO_STOCK.md

DELIVER  lib/data/repositories/ : item_repository_impl, batch_repository_impl,
         stock_repository_impl, shopping_repository_impl + mappers

BUSINESS RULES TO ENFORCE HERE
- Item identity: exact normalized match on (name, unitCategory) merges into the existing
  Item as a new Batch. Different category = a different Item, never a merge.
- Near-matches (edit distance <= 2 on normalizedName, same category) are RETURNED as
  suggestions from findSimilar(). Never auto-merged.
- unitCategory is rejected on update — it is immutable (L8).
- Auto shopping entries: upsert keyed on (listId, itemId, origin='autoLowStock') so
  regeneration is idempotent. Editing an auto entry promotes origin to 'manual' and it is
  then never auto-removed. Dismissing sets autoState + generatedAtStockMilli.
- Shopping entry may have itemId OR freeText, and quantity is optional.

Model: Claude Sonnet 5 · extended thinking ON.
```

### 3D — Repositories: rest

```
Attached: ARCH_1_FOUNDATION.md, ARCH_2_DATABASE.md, PHASE_02C_DAO_REST.md,
          PHASE_03A_DOMAIN.md

TASK — PHASE 3D: Recurring and service repository implementations.
Output file: PHASE_03D_REPO_REST.md

DELIVER  lib/data/repositories/ : recurring_repository_impl, asset_repository_impl,
         service_record_repository_impl + mappers

BUSINESS RULES TO ENFORCE HERE
- direction determines the transaction kind created on pay/receive: outflow -> withdrawal,
  inflow -> deposit.
- Paying stores the ACTUAL amount on the occurrence; the template default is untouched.
- Deleting a template is soft; paid occurrences and their transactions survive.
- Assets are never deleted. dispose() sets status + reason + date + optional amount.
- Creating a service record with a cost may optionally create a linked withdrawal —
  return both IDs so the caller can link them.

Model: Claude Sonnet 5 · extended thinking OFF.
```

### 4A — Engines: money & currency

```
Attached: ARCH_1_FOUNDATION.md, ARCH_3_SUBSYSTEMS.md, PHASE_03A_DOMAIN.md

TASK — PHASE 4A: Unit engine, balance service, and the whole currency subsystem.
Output file: PHASE_04A_ENGINE_MONEY.md

ADD DEPENDENCIES FIRST (ARCH_1 §7.4 — never hand-write a version):
  flutter pub add dio

DELIVER
  lib/domain/services/unit_engine.dart          convert within category, integer only,
                                                validate user-defined unit factors
  lib/domain/services/balance_service.dart      per-account balance; totalInHome() with
                                                unconvertedCount; excludes archived accounts
                                                where includeInNetWorth is false
  lib/domain/services/currency_rate_service.dart  ARCH_3 §1.2 USD pivot, §1.3 lookup rule,
                                                  local cross-rating, RateQuality
  lib/data/remote/currency_api_client.dart      the 3-URL ladder; normalises BOTH response
                                                shapes into one RateSnapshot; stores rateRaw
  lib/data/remote/network_policy.dart           3-entry allowlist, ARCH_3 §1.4
  lib/domain/services/date_range_service.dart   DateRangePreset -> (from,to) DateKeys
  test/domain/currency_rate_service_test.dart
  test/domain/balance_service_test.dart

CRITICAL
- Rate lookup: greatest rateDateKey <= target. Test the weekend gap explicitly — a
  Saturday transaction must resolve to Friday's rate, not fail.
- No rate cached at all -> ConvertedMoney.unconverted, and the transaction is EXCLUDED
  from the converted total rather than counted as zero.
- syncDailyRates() never throws and never blocks. Test it with a client that always fails.
- Cross-rate INR->JPY via the USD pivot and assert the result within rounding tolerance.

Model: Claude Sonnet 5 · extended thinking ON.
```

### 4B — Engines: stock & recurring

```
Attached: ARCH_1_FOUNDATION.md, ARCH_3_SUBSYSTEMS.md, PHASE_03A_DOMAIN.md,
          PHASE_03C_REPO_STOCK.md

TASK — PHASE 4B: Stock consumption, low-stock suggestions, recurring schedule,
and the purchase fan-out.
Output file: PHASE_04B_ENGINE_STOCK.md

DELIVER
  lib/domain/services/inventory_consumption_service.dart  FEFO across batches
  lib/domain/services/stock_reconciler.dart               cache vs ledger, repair
  lib/domain/services/low_stock_suggestion_engine.dart    idempotent generation
  lib/domain/services/recurring_engine.dart               nextDue, materialise, pay, skip
  lib/domain/services/purchase_fan_out_service.dart       line -> batch | asset | template
  test/domain/consumption_test.dart
  test/domain/recurring_engine_test.dart

CRITICAL — these are the exact tests I want
- FEFO: 3 batches (exp 10 Aug 500g, no expiry 1kg, exp 05 Aug 300g). Consume 600 g.
  Must draw 300 from the 05 Aug batch, then 300 from the 10 Aug batch, and leave the
  no-expiry batch untouched. Two movement rows.
- Consume more than total stock -> Failure, no partial writes.
- Month-end clamp: monthly template anchored on day 31, starting 31 Jan.
  Due dates must be 31 Jan, 28 Feb, 31 Mar, 30 Apr — NOT 28 Feb, 28 Mar, 28 Apr.
  Test a leap year too.
- Lazy materialise: template last paid 3 months ago -> exactly 3 'due' occurrences,
  zero transactions created.
- Low-stock idempotency: run generation 5 times, assert exactly one auto entry.
  Then edit it, run again, assert it was not touched.
- Fan-out: a line with destination=asset creates an Asset and writes createdAssetId back,
  and creates NO batch.

Model: Claude Sonnet 5 · extended thinking ON.
```

### 4C — Engines: calendar, analytics, backup, lock

```
Attached: ARCH_1_FOUNDATION.md, ARCH_3_SUBSYSTEMS.md, PHASE_03A_DOMAIN.md

TASK — PHASE 4C: Calendar aggregation, the analytics query layer, backup/restore,
and the app lock.
Output file: PHASE_04C_ENGINE_REST.md

ADD DEPENDENCIES FIRST (ARCH_1 §7.4 — never hand-write a version):
  flutter pub add flutter_secure_storage cryptography path_provider file_picker share_plus archive

DELIVER
  lib/domain/services/calendar_aggregator.dart      bounded-range query over
                                                    v_calendar_events, severity mapping
  lib/domain/services/analytics/                    all 24 queries from ARCH_3 §5.1 as
                                                    individually-named, testable functions
                                                    returning plain records
  lib/domain/services/analytics/analytics_cache_service.dart
  lib/data/backup/backup_service.dart               VACUUM INTO; zip only if attachments
                                                    exist; log to backup_history
  lib/data/backup/restore_service.dart              ATTACH + user_version gate; Replace and
                                                    Merge modes; rollback snapshot
  lib/data/security/app_lock_store.dart             PBKDF2-HMAC-SHA256 310k; pinHash, salt,
                                                    recoveryHash in flutter_secure_storage.
                                                    NEVER the database.
  lib/data/security/pin_service.dart                verify, change, enable, disable,
                                                    throttle table from ARCH_3 §2.3
  lib/data/security/recovery_code.dart              10-char base32, no 0/O/1/I
  test/domain/analytics_test.dart
  test/data/restore_test.dart
  test/data/pin_service_test.dart

CRITICAL
- No encryption anywhere in this phase. No PRAGMA key, no key wrapping, no DEK.
- The whole Merge restore runs inside ONE transaction {}, with DETACH in a finally.
  A partially-applied merge must be impossible.
- Refuse a backup whose user_version exceeds the app's schemaVersion.
- restore_test.dart: export, mutate, merge back, assert last-write-wins by updatedAt and
  that rows absent from the backup survived.
- pin_service_test.dart: 5 wrong attempts triggers the 30 s delay; recovery code resets
  the PIN; the lock is unaffected by a restore.
- Analytics functions return plain Dart records. NO fl_chart types in domain/ (L12).

Model: Claude Sonnet 5 · extended thinking ON.
```

### 5 — App shell

```
Attached: ARCH_1_FOUNDATION.md, ARCH_3_SUBSYSTEMS.md, PHASE_03A_DOMAIN.md

TASK — PHASE 5: Theme system, routing, localisation scaffold, and shared widgets.
No feature screens.
Output file: PHASE_05_SHELL.md

ADD DEPENDENCIES FIRST (ARCH_1 §7.4 — never hand-write a version):
  flutter pub add flutter_riverpod go_router

DELIVER
  lib/app/theme/tokens/     alaya_spacing, alaya_radii, alaya_durations,
                            alaya_typography, alaya_elevation
  lib/app/theme/palettes/   palette.dart (the data class), presets.dart (4 complete
                            palettes as const data)
  lib/app/theme/semantic_colors.dart   ThemeExtension: income, expense, transfer, warning,
                            danger, success, muted, 4 surface tiers,
                            + forAmount(Money) -> Color
  lib/app/theme/alaya_theme.dart       palette + tokens -> light and dark ThemeData
  lib/app/router/           app_router.dart, routes.dart — go_router shell + drawer.
                            Routes are HAND-WRITTEN (no go_router_builder — ARCH_1 §7.3).
                            Every path literal and every param-building helper lives in
                            routes.dart; no other file contains a route string.
  lib/app/l10n/app_en.arb   + l10n.yaml
  lib/app/app.dart, lib/app/bootstrap.dart, lib/main.dart
  lib/shared/widgets/       AlayaCard, AmountText, QtyText, TagChip, SectionHeader,
                            EmptyState, LoadingState, ErrorState, ConfirmSheet,
                            ShakeOnError, AlayaExpandableFab, AlayaDrawer,
                            DatePickerField, AmountField, QtyField, UnitPicker,
                            TagPicker, AccountPicker
  lib/features/settings/presentation/theme_lab_screen.dart   debug-only; renders every
                            token, component and semantic colour, light and dark, on one
                            scrollable page
  test/shared/golden/       goldens for AmountText, QtyText, TagChip, AlayaCard,
                            EmptyState, in light and dark

RULES
- No widget contains a hex colour, a raw EdgeInsets number, or a raw Duration.
- Every user-visible string comes from the ARB file. Zero literals in widgets.
- The red/green rule lives ONLY in SemanticColors.forAmount.
- AmountField uses MoneyParser and never rejects intermediate typing states.
- Switching the whole app's look must be one constant change in presets.dart.

NOTE — added after Phase 4C, resolved in Phase 5
- **Phase 5 owns the provider graph.** Delivered as `lib/app/providers/`: three files holding the
  database, the 21 DAOs, the ambient singletons, the 15 repository providers and the engines. Every
  one is typed as the domain **contract**, never the implementation. Feature-local view-model
  providers still belong in `features/*/providers/` (ARCH_1 §6). **Phase 6A onwards consumes these
  and declares no repository or service provider of its own** — that is what stops one repository
  acquiring three providers and `ItemCategoryResolver`, which caches, being constructed once per
  feature.
- **Two constructor signatures changed after their phase shipped.**
  `CurrencyRepositoryImpl` now takes `CurrencyRateService? rateService` — the `DailyRateFetch`
  typedef is gone (see ARCH_4 §5.1 and the Phase 4A consolidation). `AppLockStore` now takes a
  `SecureKeyValueStore`, not a `FlutterSecureStorage`.
- **`AnalyticsService` cannot be wired yet.** `AnalyticsPort` is declared in `domain/` and its
  `data/` adapter is Phase 7B's work, so any provider for `AnalyticsService` has nothing to
  construct it with. Leave it out rather than stubbing the port — a stub returning empty rows would
  make an unfinished analytics screen look finished.

Model: Claude Sonnet 5 · extended thinking ON.
```

### 6A — Expense UI

```
Attached: ARCH_1_FOUNDATION.md, ARCH_5_UIUX.md, PHASE_03A_DOMAIN.md,
          PHASE_05_SHELL.md (shared widgets + lib/app/providers/ sections)

TASK — PHASE 6A: The shared UI kit, then the Expense module.
Output file: PHASE_06A_UI_EXPENSE.md

PART 1 — the shared kit (ARCH_5 §4.2). Nine files, written FIRST, because 6B-6F all
consume them and building them per-feature is how one widget becomes three.
  lib/app/theme/tokens/alaya_icon_size.dart   sm 16, md 20, lg 24, xl 40
  lib/shared/widgets/date_text.dart           the only DateKey -> pixels path.
                                              full | medium | dayMonth | relative.
                                              Takes Clock for `relative`.
  lib/shared/widgets/key_value_row.dart       renders NOTHING when the value is null
  lib/shared/widgets/status_chip.dart         needsReview, unallocated, detached,
                                              overdue, expiring, low, approximate
  lib/shared/widgets/alaya_form_scaffold.dart scroll body + sticky footer above the
                                              keyboard + PopScope unsaved guard +
                                              submitting state
  lib/shared/widgets/alaya_list_skeleton.dart placeholder rows, no shimmer
  lib/shared/widgets/alaya_search_field.dart  debounced, clearable, semantics label
  lib/shared/widgets/filter_chip_bar.dart     active filters as removable chips;
                                              renders nothing when empty
  lib/shared/feedback/undo_snack.dart         showUndoSnack(context, message, onUndo)
  + goldens for date_text, key_value_row, status_chip, light and dark

PART 2 — the Expense module
  quick_add_sheet.dart          ARCHETYPE A. Amount is the ONLY required field.
                                Deposit/withdrawal toggle, account CHIP ROW (not a
                                dropdown), optional tag. Saves needsReview = true.
  transaction_editor_screen.dart  ARCHETYPE B, route OUTSIDE the shell. AlayaFormScaffold.
                                Sections group by decision, not by table. The visible
                                sub-form switches on subtype and PRESERVES every field
                                the new shape still has.
  subtype_forms/                grocery_form, household_form (line items),
                                electronics_form (warranty -> asset), bill_form
                                (recurring picker), transfer_form (own account vs
                                someone else), other_form (destination chooser),
                                deposit_form
  line_item_editor.dart         ARCHETYPE A. description, qty + unit, unit price,
                                line amount, destination
  transaction_list_screen.dart  ARCHETYPE C. Sticky day headers, SliverList.builder,
                                FilterChipBar, no pull-to-refresh
  transaction_filter_sheet.dart ARCHETYPE A. date range, kind, subtype, account, tag, payee
  transaction_detail_screen.dart ARCHETYPE E, route OUTSIDE the shell. Hero card,
                                KeyValueRows, lines list, destructive actions last
  needs_review_banner.dart      "3 transactions need details" nudge
  providers/*.dart              view-model providers only (ARCH_5 U19)
  + one widget test per screen covering all four states, at 320dp and textScaler 2.0
  + every new sheet added to test/shared/layout_overflow_test.dart

COVERAGE — ARCH_5 §7 rows this phase closes
  transactions · transaction_lines · transaction_tags · payees (inline create)
  §7.2: needsReview banner+chip · converted*/conversionRateRaw via a "Freeze
  conversion" action · deleteReason on the delete sheet · line destination chooser ·
  created*Id as a tappable "Created: LG TV" link · unallocatedMinor chip

CRITICAL
- Transfer form: "to my own account" -> kind=transfer. "to someone else" -> kind=withdrawal
  with subtype=transferOut and a payee. This distinction is the whole point of A02 —
  get the copy unambiguous.
- Electronics form collects warranty dates and creates an Asset, NOT an inventory batch,
  with an explicit "also add to inventory" opt-in.
- Grocery/household line items default destination=inventory.
- Unallocated amount chip when line sums != transaction amount. Never auto-balance.
- Delete is reversible: do it, snack with Undo, no confirmation dialog (ARCH_5 §5.5).
  Undo restores the fan-out link; it never re-creates a batch.
- Empty amount on submit -> ShakeOnError, inline message, focus moves there.
- update() must REJECT a currency change and ALLOW an amount change (ARCH_4 §5.1 item 18).
- saveWithFanOut is idempotent, not atomic (ARCH_4 §5.1 item 17). Re-running is a no-op.

Model: Claude Sonnet 5 · extended thinking ON.
```

### 6B — Inventory UI

```
Attached: ARCH_1_FOUNDATION.md, ARCH_5_UIUX.md, PHASE_03A_DOMAIN.md,
          PHASE_05_SHELL.md (shared widgets + lib/app/providers/ sections)

TASK — PHASE 6B: The Inventory module UI.
Output file: PHASE_06B_UI_INVENTORY.md

DELIVER
  inventory_list_screen.dart    ARCHETYPE D. AlayaSearchField pinned, grouped by tag,
                                row = icon + name + total on hand (QtyText) + status chip
  item_detail_screen.dart       ARCHETYPE E, outside the shell. Hero = summed mixed-unit
                                total; batch list below, each with expiry and origin
  item_editor_screen.dart       ARCHETYPE B. unitCategory is IMMUTABLE after create (L8) —
                                render it read-only on edit and say why
  batch_editor_screen.dart      ARCHETYPE B. expiry, purchased, unit cost, storageLocation
  consume_sheet.dart            ARCHETYPE A. FEFO pre-selected with the batch named and
                                overridable; consume | waste | expired as distinct kinds
  batch_history.dart            ARCHETYPE C. Movement timeline, reversals marked
  unit_picker usage             category-filtered; L8 means never offer a cross-category unit
  providers/*.dart              view-model providers only
  + AlayaTimeline in shared/widgets (the one shared addition this phase may make)
  + one widget test per screen, all four states, 320dp × textScaler 2.0
  + new sheets added to layout_overflow_test.dart

COVERAGE — ARCH_5 §7 rows this phase closes
  items · inventory_batches · stock_movements · item_tags
  §7.2: expiryNotifyDays · isFavorite (star + filter) · lowStockThresholdMilli + "low"
  chip · origin=detached status chip explaining the receipt was deleted ·
  storageLocation · reversesMovementId marked in the timeline · waste|expired as
  distinct consume kinds

CRITICAL
- Item row shows the SUMMED mixed-unit total ("4 kg 450 g"); expanding shows individual
  batches with expiries (ARCH_1 §5.4). The spec's own arithmetic is wrong; 250+2000+1500+700
  is 4 kg 450 g.
- Every operation acts on a BATCH. Display sums.
- Deleting an item cascade-soft-deletes its batches and leaves movements untouched.
- A consume that spans batches writes multiple movements and the sheet says so before
  committing.

Model: Claude Sonnet 5 · extended thinking ON.
```

### 6C — Shopping UI

```
Attached: ARCH_1_FOUNDATION.md, ARCH_5_UIUX.md, PHASE_03A_DOMAIN.md

TASK — PHASE 6C: The Shopping module UI.
Output file: PHASE_06C_UI_SHOPPING.md

DELIVER
  shopping_list_screen.dart     ARCHETYPE D. Grouped by tag header, checkbox rows,
                                running estimated total, list switcher in the app bar
  entry_editor_sheet.dart       ARCHETYPE A. free text OR an item, qty + unit, tag,
                                estimated price
  generate_sheet.dart           ARCHETYPE A. Low-stock suggestions with the shortfall
                                shown, each individually accept/snooze/dismiss
  convert_to_purchase.dart      ARCHETYPE B. Checked entries -> a pre-filled withdrawal,
                                one line per entry, destination=inventory
  list_manager_sheet.dart       ARCHETYPE A. create, rename, set default, archive
  providers/*.dart              view-model providers only
  + tests and layout_overflow_test.dart additions

COVERAGE — ARCH_5 §7 rows this phase closes
  shopping_lists · shopping_entries
  §7.2: autoState + snoozeUntilDateKey as snooze/dismiss actions · estimatedPriceMinor
  inline plus a running list estimate · origin=autoLowStock chip distinguishing
  suggested from manual

CRITICAL
- Auto-generation is idempotent: a dismissed suggestion does not reappear until stock
  rises above the threshold and drops again (A22, A23).
- Editing an auto entry promotes it to origin=manual and it is never auto-removed.
- itemId is nullable — "TV" must work without inventing an inventory Item.
- Convert-to-purchase is the loop closing. It hands off to 6A's editor; it does not
  reimplement it.

Model: Claude Sonnet 5 · extended thinking ON.
```

### 6D — Recurring UI

```
Attached: ARCH_1_FOUNDATION.md, ARCH_5_UIUX.md, PHASE_03A_DOMAIN.md

TASK — PHASE 6D: The Recurring module UI.
Output file: PHASE_06D_UI_RECURRING.md

DELIVER
  template_list_screen.dart     ARCHETYPE D. Grouped outflow/inflow, next due date,
                                overdue chip, paused state visible
  template_builder_screen.dart  ARCHETYPE B. The frequency builder previews the NEXT
                                THREE dates as the user changes it — that preview is the
                                only way a user can tell a clamp is doing what they meant
  pay_sheet.dart                ARCHETYPE A. Pre-fills defaultAmountMinor, lets the user
                                enter the ACTUAL paid amount, records both
  occurrence_history.dart       ARCHETYPE C. Per template, showing default vs actual
                                where they differ
  providers/*.dart              view-model providers only
  + FrequencyPreview in shared/widgets (the one shared addition this phase may make)
  + tests and layout_overflow_test.dart additions

COVERAGE — ARCH_5 §7 rows this phase closes
  recurring_templates · recurring_occurrences
  §7.2: anchorDayOfMonth/Month/Weekday through the frequency builder ·
  direction=inflow rendering salary as income not a negative bill ·
  paidAmountMinor shown against the default when they differ

CRITICAL
- Occurrences materialise LAZILY up to today and are never auto-paid. Money is only ever
  created by an explicit tap (A14).
- anchorDayOfMonth is stored once and clamped at render. A bill anchored on the 31st stays
  anchored on the 31st — Jan 31 -> Feb 28 -> Mar 31, never walking backwards (A13).
- Paying is undoable, and undo reverses the occurrence AND the transaction it created, in
  that order. The confirmation says so (ARCH_5 §5.4).
- An overdue occurrence is DERIVED from clock.today(), never a stored flag (ARCH_2 §12.2).

Model: Claude Sonnet 5 · extended thinking ON.
```

### 6E — Service UI

```
Attached: ARCH_1_FOUNDATION.md, ARCH_5_UIUX.md, PHASE_03A_DOMAIN.md

TASK — PHASE 6E: The Service Manager module UI.
Output file: PHASE_06E_UI_SERVICE.md

DELIVER
  asset_list_screen.dart        ARCHETYPE D. Grouped by type, warranty/service chips,
                                a filter that includes disposed assets
  asset_detail_screen.dart      ARCHETYPE E, outside the shell. Hero = purchase price +
                                warranty state; contact block with a CALL action; service
                                history; lifetime service cost
  asset_editor_screen.dart      ARCHETYPE B. identity, warranty, service interval, contact
  service_editor_screen.dart    ARCHETYPE B. type incl. salaryPaid, provider, cost, next due,
                                "also record as an expense" toggle
  dispose_sheet.dart            ARCHETYPE A. reason picker + optional amount + note
  providers/*.dart              view-model providers only
  + tests and layout_overflow_test.dart additions

COVERAGE — ARCH_5 §7 rows this phase closes
  assets · service_records · asset_tags
  §7.2: type=serviceProvider (the maid case — a person in the asset list with salary
  history) · disposal* + status=disposed with disposed assets visible behind a filter ·
  serviceIntervalDays / nextServiceDueDateKey + the serviceDue chip ·
  primaryContactPhone as a call action · service type=salaryPaid

CRITICAL
- An asset is NEVER deleted. Disposal is a status change plus a reason, so the ₹45,000 you
  spent stays in your analytics (A30, ARCH_3 §4.1).
- type=serviceProvider is how a house maid lives in the same table as a TV: asset + linked
  recurring template + a service_records row per payment. No second system.
- "Also record as an expense" writes through the repository, which is internally
  transactional but not atomic across aggregates (ARCH_4 R21). Ordered writes, idempotent
  retry.

Model: Claude Sonnet 5 · extended thinking ON.
```

### 6F — Dashboard

```
Attached: ARCH_1_FOUNDATION.md, ARCH_3_SUBSYSTEMS.md, ARCH_5_UIUX.md,
          PHASE_03A_DOMAIN.md

TASK — PHASE 6F: The Dashboard.
Output file: PHASE_06F_UI_DASHBOARD.md

DELIVER
  dashboard_screen.dart         ARCHETYPE F. Exactly ONE displayAmount on the screen.
  funds_header.dart             BalanceService.totalInHome() + an "+N unconverted" chip
  range_row.dart                last-30-days and all-time deposit/withdrawal rows, each
                                ALWAYS labelled with what the range means (A33)
  insight_card.dart             switchable calendar <-> analytics preview, choice stored
                                in app_settings; each side renders its own empty and error
                                state inline so one failing card never blanks the dashboard
  module_grid.dart              navigation tiles, each carrying a LIVE number
  fab wiring                    AlayaExpandableFab: add expense, add income, add item
  providers/*.dart              view-model providers only
  + ModuleTile in shared/widgets (the one shared addition this phase may make)
  + tests and layout_overflow_test.dart additions

COVERAGE — ARCH_5 §7 rows this phase closes
  funds header · range rows · module grid · the approximate/unconverted chips over
  currency_rates

CRITICAL
- "Total available funds" comes from BalanceService.totalInHome() and nothing else.
  AccountRepository.watchTotalInHomeCurrency is the interloper and should be dropped from
  the contract while you are here (ARCH_4 §5.1 item 13).
- A self-transfer nets to zero. If the header moves when the user transfers between their
  own accounts, v_account_ledger is being bypassed.
- Unconvertible amounts are EXCLUDED from the headline and surfaced as a chip. Never
  silently summed (A34).
- DECIDE and record: whether AlayaExpandableFab needs a real scrim (ARCH_4 §5.1 item 19).
  This is the phase where it is first used for real.

Model: Claude Sonnet 5 · extended thinking ON.
```

### 7A — Calendar UI

```
Attached: ARCH_1_FOUNDATION.md, ARCH_2_DATABASE.md, ARCH_3_SUBSYSTEMS.md,
          ARCH_5_UIUX.md

TASK — PHASE 7A: CalendarRepository + the Calendar UI.
Output file: PHASE_07A_UI_CALENDAR.md

ADD DEPENDENCIES FIRST (ARCH_1 §7.4 — never hand-write a version):
  flutter pub add table_calendar

FIRST — the missing repository. Phase 3A declared CalendarRepository and no phase
implemented it, so CalendarAggregator has no provider and cannot be wired
(ARCH_4 §5.1 item 15). Implement it over v_calendar_events, add its provider to
lib/app/providers/repository_providers.dart, and add calendarAggregatorProvider to
service_providers.dart. Do this before any screen.

DELIVER
  data/repositories/calendar_repository_impl.dart
  calendar_screen.dart          ARCHETYPE F. Month grid, per-day severity dots
  day_sheet.dart                ARCHETYPE A. The day's events grouped by type, each
                                tappable through to its record
  event_card.dart               one card per event_type, severity-coloured AND labelled
  providers/*.dart              view-model providers only
  + tests and layout_overflow_test.dart additions

COVERAGE — ARCH_5 §7 rows this phase closes
  v_calendar_events surfaces: transaction, recurringDue, batchExpiry, warrantyEnd,
  serviceDue, shoppingTarget

CRITICAL
- Severity escalation happens in DART, in CalendarAggregator.severityFor, using the
  injected Clock. No view references the current time (ARCH_2 §12.2), and the per-type
  table in ARCH_3 §6 is the correct one — warranty warns at 30 days, only batchExpiry
  reaches danger once past.
- Delete CalendarEvent.severityAsOf while you are in that file: it applies one generic rule
  to every type and contradicts §6 (ARCH_4 §5.1 item 14).
- Always query a BOUNDED date range so it hits the per-source indexes and never scans.
- "Medicine expiry" needs no special handling — it is batchExpiry on an item with
  itemKind=medicine.

Model: Claude Sonnet 5 · extended thinking ON.
```

### 7B — Analytics UI

```
Attached: ARCH_1_FOUNDATION.md, ARCH_2_DATABASE.md, ARCH_3_SUBSYSTEMS.md,
          ARCH_5_UIUX.md, PHASE_04C_ENGINE_REST.md

TASK — PHASE 7B: AnalyticsPort adapter + AnalyticsCacheRepository + the Analytics UI.
Output file: PHASE_07B_UI_ANALYTICS.md

ADD DEPENDENCIES FIRST (ARCH_1 §7.4 — never hand-write a version):
  flutter pub add fl_chart

FIRST — the missing data layer. AnalyticsService and AnalyticsCacheService have no
providers because AnalyticsPort has no data/ adapter and AnalyticsCacheRepository has no
implementation (ARCH_4 §5.1 item 15). Build both, wire all three services, then build
screens.

DELIVER
  data/repositories/analytics_port_impl.dart
  data/repositories/analytics_cache_repository_impl.dart
  analytics_home_screen.dart    ARCHETYPE F. The 24-query catalogue, grouped
  chart surfaces                spend by subtype / tag / method, income vs expense trend,
                                balance trend, top payees, top items, UNIT-PRICE TREND
                                (personal inflation), food waste, inventory value
  drill_down_screen.dart        ARCHETYPE C, outside the shell
  providers/*.dart              view-model providers only
  + ChartCard in shared/widgets (the one shared addition this phase may make)
  + tests and layout_overflow_test.dart additions

COVERAGE — ARCH_5 §7 rows this phase closes
  analytics_cache (including "clear cache" in Settings) · tags.parentTagId drill-down ·
  CurrencyRepository.watchUnconvertedCount — replace the Stream.value(0) stub with a real
  implementation over the same RateTable, then delete the stub (ARCH_3 §1.5)

CRITICAL
- unitCostMinor is per unit_code_at_purchase, NOT per base unit. Join units on
  unit_code_at_purchase and divide by factor_to_base_milli. Phase 4C valued a 2 kg batch at
  ₹100,000 instead of ₹100, and the error is invisible for gram-denominated purchases —
  which is why it survived a written audit (ARCH_4 R18).
- Every analytics result type is a RECORD. A field declared double rejects 0 and rejects
  `cond ? 0 : a / b` (that is num); a field declared List<T> rejects a bare const []
  (ARCH_4 R17). Write 0.0 and const <T>[].
- A port's inline record fields must match every fake, field for field (ARCH_4 R19).
- Multi-currency series convert PER DATA POINT and every series returns its approximate
  and unconverted counts alongside the data.
- Queries 12, 14 and 24 are the differentiators. "Your potatoes cost 34% more than in
  January" is the screenshot.
- No chart library type crosses into domain/.

Model: Claude Sonnet 5 · extended thinking ON.
```

### 8A — Settings, onboarding, lock

```
Attached: ARCH_1_FOUNDATION.md, ARCH_3_SUBSYSTEMS.md, ARCH_5_UIUX.md,
          PHASE_03A_DOMAIN.md

TASK — PHASE 8A: Onboarding, the settings tree, and the app lock UI.
Output file: PHASE_08A_SETTINGS_LOCK.md

ADD DEPENDENCIES FIRST (ARCH_1 §7.4 — never hand-write a version):
  flutter pub add local_auth path_provider file_picker share_plus

DELIVER
  onboarding_flow.dart          ARCHETYPE B. Home currency, first accounts WITH OPENING
                                BALANCES AND DATES, optional lock. Skippable, resumable.
  settings_screen.dart          ARCHETYPE D. Tree: Accounts, Payment methods, Payees,
                                Tags, Units, Currencies, Appearance, Security, Data, About
  accounts_settings.dart        create/edit/archive, includeInNetWorth toggle explained
  tags_settings.dart            the allowedIn* scoping matrix, one level of nesting
  units_settings.dart           user units with an integer factor; if the user cannot state
                                a factor, the UI says "make it a new item" and offers to
  appearance_settings.dart      palette picker + theme mode, PERSISTED to app_settings
  pin_setup_flow.dart           ARCHETYPE B. PIN twice -> recovery code shown -> one
                                confirm checkbox -> "Make a backup now?"
  lock_screen.dart              ARCHETYPE A, outside the shell. ShakeOnError on failure,
                                throttle countdown visible, biometric shortcut
  recovery_flow.dart            enter recovery code -> set a new PIN
  providers/*.dart              view-model providers only
  + tests and layout_overflow_test.dart additions

COVERAGE — ARCH_5 §7 rows this phase closes
  app_settings · accounts (create/edit/archive) · payment_methods · payees (manage) ·
  tags (manage) · units · currencies
  §7.2: includeInNetWorth · openingBalance* captured in onboarding · tags.parentTagId ·
  tags.allowedIn* — "Kitchen" must not appear in the deposit picker
  Also closes ARCH_4 §5.1 item 23 (theme choice persisted).

CRITICAL
- HONEST COPY (ARCH_3 §2.5). The lock screen says, in plain words, that this PIN stops
  someone who picks up your unlocked phone and does NOT encrypt your data. No
  "bank-grade", no "military-grade", no padlock iconography implying encryption.
- The PIN, its hash and the recovery code NEVER touch the database — secure storage only,
  so restoring a backup cannot change who can open the app (A43).
- "Forgot both" offers to export a backup first, then requires typing ERASE.
- Wire the router's LockGate to the real PinService and give GoRouter a refreshListenable
  so a lock state change actually redirects.
- Auto-erase after 10 failures exists, defaults OFF, behind a scary confirm.

Model: Claude Sonnet 5 · extended thinking ON.
```

### 8B — Ops

```
Attached: ARCH_1_FOUNDATION.md, ARCH_3_SUBSYSTEMS.md, ARCH_5_UIUX.md,
          PHASE_03A_DOMAIN.md

TASK — PHASE 8B: Backup/restore UI, attachments, notifications, trash, Support Us.
Output file: PHASE_08B_OPS.md

ADD DEPENDENCIES FIRST (ARCH_1 §7.4 — never hand-write a version):
  flutter pub add flutter_local_notifications timezone workmanager
  flutter pub add google_mobile_ads in_app_purchase

DELIVER
  backup_screen.dart            ARCHETYPE D. Export via SAF, share, backup_history list
  restore_flow.dart             ARCHETYPE B. Merge vs Replace, gated on user_version,
                                Replace requires typing REPLACE and snapshots a rollback
  attachments.dart              attach/view/delete receipt and warranty photos
  reminders_screen.dart         ARCHETYPE D. Per-type toggles, digest time picker,
                                shows what is currently scheduled
  trash_screen.dart             ARCHETYPE C. 30-day retention, per-item restore, empty now
  support_screen.dart           ARCHETYPE F. Rewarded ads + one-time tip, LAZY-LOADED
  providers/*.dart              view-model providers only
  + tests and layout_overflow_test.dart additions

COVERAGE — ARCH_5 §7 rows this phase closes
  attachments · notification_schedule · backup_history

CRITICAL
- THE EXPORT WARNING APPEARS EVERY TIME, on the confirmation sheet, not in settings and
  not as a tooltip: "This backup is not encrypted. Anyone who opens this file can read
  every transaction, balance and account name." (ARCH_3 §3.4)
- SAF only. No WRITE_EXTERNAL_STORAGE, no MANAGE_EXTERNAL_STORAGE.
- The lock is NOT restored — PIN and recovery hashes live in secure storage.
- POST_NOTIFICATIONS is requested CONTEXTUALLY, when the user first enables a reminder.
  Never on first launch. All reminders default OFF.
- ONE daily digest at a user-chosen time, not a stream of pings. Inexact scheduling only —
  no SCHEDULE_EXACT_ALARM.
- Purge is the ONLY hard delete in the codebase and lives in exactly one function.
- Ads load only when the Support screen opens. The rest of the app makes zero ad calls.

Model: Claude Sonnet 5 · extended thinking ON.
```

### 9 — Polish & release

```
Attached: ARCH_1_FOUNDATION.md, ARCH_5_UIUX.md

TASK — PHASE 9: Animation, performance, accessibility and release configuration.
Output file: PHASE_09_POLISH.md

ADD DEPENDENCIES FIRST, only if the animation pass actually imports it:
  flutter pub add flutter_animate

DELIVER
  animation pass                Only the four things ARCH_5 §2.6 permits. Remove anything
                                else that crept in. Verify every animation is skipped under
                                MediaQuery.disableAnimationsOf.
  perf pass                     Seed 50k transactions. Dashboard first frame < 500 ms.
                                No frame over 16 ms scrolling a 5k-row list, profile mode,
                                real device. Confirm every list is virtualised (U13).
  a11y sweep                    Run the full ARCH_5 §6 table over every screen. Fix, do not
                                waive.
  AlayaDurations.page           wire it or delete it (ARCH_4 §5.1 item 22)
  bootstrap error path          a minimal MaterialApp whose home is an ErrorState, so a
                                failed database open is not a blank screen
                                (ARCH_4 §5.1 item 25)
  release config                --obfuscate --split-debug-info, Play App Signing, AD_ID,
                                UMP consent

GATE — the phase does not end until
- ARCH_5 §7 has no unticked row and no entry in §7.3 without an owner
- Full offline pass: airplane mode, every screen, zero errors
- Backup -> wipe -> restore round trip, record counts identical
- allowBackup="false" verified in the BUILT APK's manifest, not just the source
- Release AAB size recorded and justified

Model: Claude Sonnet 5 · extended thinking ON.
```
---

## 5. Definition of done

A phase is not done until every box is ticked. No "I'll come back to it."

**Every phase**
- [ ] `dart analyze` clean, zero warnings
- [ ] `dart format` applied
- [ ] `dart run build_runner build` clean — applies to phases
      containing drift code (1B onward). `drift_dev` is the **only** generator in the project
      (ARCH_1 §7.3), so there is nothing to generate in Phase 1A and no `@riverpod` or
      `go_router_builder` output anywhere. Note `--delete-conflicting-outputs` was **removed**
      in build_runner 2.15 and is now ignored with a warning — do not pass it.
- [ ] `dart run tool/check_layering.dart` exits 0
- [ ] **Presence checks run against stripped source.** Strip comments and string literals before
      asserting that code exists. A doc comment describes the code beneath it, so a raw-text match
      confirms anything documented whether or not it was written — this produced a false all-clear that
      hid a broken feature for two rounds (ARCH_4 R39).
- [ ] **One fix folder per phase, consolidated after every round.** Overlapping round folders give
      several candidate bases for one file and guarantee a stale-base rebuild; it silently reverted two
      fixes in Phase 6E alone (ARCH_4 R43).
- [ ] **Enums read whole, switches counted.** Extract a declaration with
      `sed -n '/^enum X/,/^}/p'`, never `grep -A n`, and assert the number of `case` arms equals the
      number of values. A truncated window cost two round trips on `RecurringKind` alone (ARCH_4 R38).
- [ ] **Swept for the pattern, not the instance.** Every fix to a shape named in ARCH_4 §4 — R32 a
      non-flexible trailing element, R33 a dropdown value sourced from state, R30 a generic error
      message — ends with a grep for its siblings across the whole tree. Four rounds of the Phase 6C
      pass were spent fixing one occurrence at a time of a defect already in the ledger.
- [ ] **Applied to the canonical tree, not the nearest copy.** A fix goes into the extracted tree and
      the phase document is regenerated from it. Patching whichever local file was closest silently
      reverted an entire feature — `transaction_editor_providers.dart` lost Part 0's draft channel and
      `markPurchased` — and cost two rounds diagnosing a feature that was already built. Shared files
      must be byte-identical in every document that carries them.
- [ ] **A diagnostic is verified working, not merely compiling.** Confirm the error path renders the
      message. Two attempts to surface a real failure produced nothing because the state field holding
      it was being cleared, and both were assumed correct because they type-checked.
- [ ] **`dart analyze` exits 0.** `build_runner` succeeding is not the gate — it will happily
      generate code for a file that does not compile. Every error reported across Phases 2A–4A was
      an analyze error, never a codegen one.
- [ ] No **unused imports**. `very_good_analysis` treats these as errors, so they fail the build.
      Four genuine ones survived undetected until Phase 3C because nothing looked for them. Note
      `data/db/alaya_database.dart` is the one legitimate exception: its imports serve the generated
      `part` file, which cannot declare its own.
- [ ] Every named argument at a call site matches the callee's **current** signature. A parameter
      renamed in one phase silently invalidates call sites written in a later one — that is what
      `insertWithDetails(transaction:)` versus `header:` was.
- [ ] **Record literals type-check field by field.** A field declared `double` rejects `0` and
      rejects `cond ? 0 : x / y` (that is `num`); a field declared `List<T>` rejects a bare
      `const []`. See ARCH_4 R17 — this has been hit three times and is always a compile error, so
      it is pure wasted round trips.
- [ ] **No type-name collisions across `domain/`.** Phase 4C's analytics `WasteTotal` collided with
      Phase 3A's `WasteTotal` on `StockRepository`; both are legal alone and any file importing both
      fails. Grep every new public type name against the existing tree before delivering.
- [ ] Every named argument matches the callee's **current** signature, and every required column of
      a table appears in each `XCompanion.insert` for it. Check the table declaration rather than a
      nearby call site — `defaultDisplayUnitCode` and `isFavorite` were missed that way in 4C.
- [ ] **A `library;` directive precedes every import.** Dart requires it first; a file-level doc
      comment placed after the imports with `library;` under it reads naturally and does not compile.
      This cost three errors in Phase 5.
- [ ] **A port's inline record fields match every fake, field for field.** Structural matching is the
      only binding, so adding a field breaks each fake silently until edited (ARCH_4 R19). Scan the
      port's field set against each implementation's in one pass.
- [ ] **Codegen ran in order before analyzing**: `flutter pub get` -> `flutter gen-l10n` ->
      `dart run build_runner build` -> `dart analyze`. Analyzing before `gen-l10n` reports every
      string-reading widget as broken, which looks like a code fault and is not (ARCH_1 §7.5).
- [ ] **Every provider a `features/` file reads is imported from the file that declares it.** Providers are
      `lowerCamelCase`, so an import scan that checks only capitalised identifiers misses every one — that
      is how `clockProvider` shipped unimported. `app/providers/infrastructure_providers.dart` is the usual
      omission, because the obvious import is `repository_providers.dart`: it holds `clockProvider`,
      `uidGeneratorProvider`, `databaseProvider`, `dioProvider` and the 21 DAO providers.
- [ ] **Every bottom sheet goes through `AlayaBottomSheet`** (ARCH_3 §8.3). A `MainAxisSize.min` Column
      inside a `Padding` keyed to `viewInsets.bottom` overflows the instant a keyboard opens and never
      otherwise — it passes `dart analyze`, every scanner, and a look at the screen.
- [ ] **A widget in `Scaffold.floatingActionButton` sizes itself to its content.** No `Positioned.fill`,
      no expanding `Stack`. One made the FAB's actions render on the opposite side of the screen from the
      button.
- [ ] **New sheets and full-height states are added to `test/shared/layout_overflow_test.dart`.** That test
      is the only thing in this project that catches an overflow, because the missing affordance is always
      an ancestor and a per-file scan cannot see it.
- [ ] **An API is verified by compiling against it, not by reading about it.** Three delivered defects came
      from applying a changelog or a doc page without writing one line first — a Riverpod notifier shape, a
      `StateProvider` deprecation, and a float-precision claim that was simply false. If a version note
      says an API changed, write it and let `dart analyze` answer (ARCH_4 R22).
- [ ] **A golden's canvas fits its widget.** A `RenderFlex` overflow inside a golden bakes the
      overflow stripe in as expected output. Size the canvas against measured content height, not a
      guess — `EmptyState` overflowed a 140px box by 95px in Phase 5.
- [ ] No `DateKey` passed to a drift range helper — use `DateKeyColumnFilters`
      (ARCH_1 §4.3). `dart analyze` catches this; `build_runner` does not.
- [ ] Every test file importing `package:drift/drift.dart` uses an explicit `show` clause
      (ARCH_1 §7.6) — a bare import collides with matcher's `isNull` / `isNotNull`
- [ ] No import crosses an ARCH_1 §6 boundary
- [ ] No `TODO` without a `PHASE_XX` reference
- [ ] Every file in the phase md is complete and compiles
**Every phase from 6A — UI**

- [ ] Every screen declares its ARCH_5 §3 archetype in its file doc comment
- [ ] **Every screen implements loading, empty, error and populated**, and each has a widget test.
      `AsyncValue.value!` and `?? []` on a repository stream are rejects (U4)
- [ ] Every new sheet and full-height state is in `test/shared/layout_overflow_test.dart` (U2)
- [ ] One test per screen at **320 × 640 with `textScaler` 2.0**, asserting no exception (U15)
- [ ] `meetsGuideline(androidTapTargetGuideline)` and `meetsGuideline(labeledTapTargetGuideline)`
      pass for every screen (U3)
- [ ] Zero user-visible string literals under `features/` and `shared/` (U5)
- [ ] Zero raw colours, spacings, radii, durations, **icon sizes** and text styles (U6)
- [ ] Every `Money` through `AmountText`, `Qty` through `QtyText`, `DateKey` through `DateText` (U7)
- [ ] Every write produces a snack bar or an inline error — no silent success (U9)
- [ ] Every editor has an unsaved-changes guard (U10)
- [ ] Destructive actions follow ARCH_5 §5.5's tier. **An undoable action is not gated behind a
      confirmation dialog**
- [ ] No feature file declares a repository or engine provider (U19)
- [ ] Detail and editor routes are outside the `ShellRoute` (U18)
- [ ] **The phase's ARCH_5 §7 coverage rows are closed**, and the phase output ends with a table
      saying which (U20)
- [ ] One pass on a real device in **dark mode**, and one in **airplane mode**
**1A**
- [ ] `flutter pub deps | grep -i file_picker` returns nothing — no plugin this phase does not
      import may appear in the tree (R11)
- [ ] `android:allowBackup="false"` present in the manifest, `res/xml/data_extraction_rules.xml`
      exists (A42)
- [ ] App launches on a real device and every row on the smoke screen is a green tick
- 100% branch coverage on `Money`, `Qty`, `DateKey`, `Normalizer`, `QtyFormatter`.
Five files that every other file depends on: the cheapest place in the project to buy
correctness.

**1B / 1C**
- [ ] v1 schema snapshot committed (`drift_dev schema dump`)
- [ ] v1→v1 migration test passes
- [ ] Seed produces a valid, queryable database
- [ ] `v_account_balances` correct across all five transaction kinds
- [ ] **A self-transfer nets to zero** — the single most important assertion in the codebase
- [ ] `v_batch_stock_check` shows zero drift after 100 random movements
- [ ] Tag scoping matrix matches ARCH_2 §14 exactly; "Kitchen" absent from deposits
- [ ] FTS5 confirmed available; search returns hits

**3–4** — one unit test per business rule against an **in-memory** drift DB
(`NativeDatabase.memory()`), no device needed. Specifically: FEFO across mixed expiries;
Jan 31 → Feb 28 → Mar 31 clamp; rate lookup across a weekend gap; transaction delete leaving
a consumed batch intact; auto-entry idempotency over 5 regenerations; merge restore
last-write-wins.

**5–8** — goldens for the shared widgets in light and dark; one widget test per screen
covering empty, loading, error and populated. Not exhaustive goldens for every screen — that
is a maintenance tax with poor return.

**9**
- [ ] Dashboard first frame < 500 ms on the seeded 50k dataset
- [ ] No frame over 16 ms scrolling a 5k-row list (profile mode, real device)
- [ ] Full offline pass: airplane mode, every screen, zero errors
- [ ] Backup → wipe → restore round trip, record counts identical
- [ ] `allowBackup="false"` verified in the built APK's manifest
- [ ] Release AAB size recorded and justified

---

## 6. Release checklist

Items 1, 2 and 5 must exist **before your first upload**, not at launch.

1. **Privacy policy** at a public URL. Required because of ads. Must state: financial data
   stays on the device; currency rates are fetched from a CDN with no personal data attached;
   AdMob collects advertising identifiers.
2. **Data safety form.** No data collected or shared by the app itself; AdMob collects
   device/advertising IDs. Be precise — mismatches get apps pulled.
3. **`AD_ID` permission** (`com.google.android.gms.permission.AD_ID`) declared, required for
   AdMob on Android 13+.
4. **UMP consent** for EEA/UK users. You target multiple countries, so this is not optional.
5. **`android:allowBackup="false"`** verified in the release manifest. With a plaintext
   database this is a genuine privacy obligation, not a nicety.
6. **Play Financial Services policy** — a personal expense tracker with no lending, investing
   or payment initiation sits outside the restricted categories. Keep it that way; do not add
   "connect your bank" later without re-reading that policy.
7. Play App Signing configured; release build with `--obfuscate --split-debug-info`.
8. Target API 36 (already set). Play enforces a rolling minimum.
9. **No `MANAGE_EXTERNAL_STORAGE`.** SAF only. That permission needs a declaration form and
   is routinely rejected.
10. Screenshots from the **demo seed**, not an empty app.
11. The in-app tip must be a Play Billing product. External payment links violate policy.

---

## 7. Quota tactics

- **One phase per conversation.** A 40-message thread re-reads its whole history every turn.
  Starting fresh is cheaper and produces better output.
- **Attach exactly what the §1 table lists — no more, no less.** `A5` is mandatory from 6A and is
  the second-largest file you will attach; that cost is deliberate and is cheaper than eleven
  phases each inventing a design system (ARCH_4 R24). `PHASE_05_SHELL.md` is the largest and is
  almost never needed whole — attach the shared-widgets and `lib/app/providers/` sections only.
- **Extended thinking is now ON for every UI phase.** The earlier plan turned it off for 6C, 6D,
  6E and 7A on the grounds that they are pattern application. That was true when a prompt only had
  to place widgets; with ARCH_5's four-state requirement, coverage rows and accessibility gates
  they are design work, and a T− run produces a screen that looks finished and fails §9.1.
- **Spend your best model on 1B.** Everything downstream inherits the schema. If you have
  Opus access for exactly one prompt in this project, use it there.
- **On truncation, reply only `continue`.** The `<!-- CONTINUE -->` rule in the preamble makes
  the model resume at a file boundary instead of restarting.
- Use a **Project** with the preamble in custom instructions and ARCH_1 in project knowledge.
  Then each prompt is a short paste.
- Message and usage limits vary by plan and change over time — check
  <https://support.claude.com> for what currently applies to yours.
