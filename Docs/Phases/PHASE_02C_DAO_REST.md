# Phase 2C — Data Access Objects: Recurring, Service & Ops

> **Regenerated from the canonical tree.** Every fix through Phase 6E is folded in; regenerating from
> this document reproduces the code that runs. Shared files carry identical content in every copy.

**7 DAOs · idempotent occurrence materialisation · dispose-not-delete · 2 pre-existing runtime
crashes found and fixed.**

## Add dependencies

None. Every import resolves to packages already present.

## Two real bugs in already-delivered phases, found by testing this one

Implementing `upsertForDue` meant answering a question I had been assuming the answer to: **can a
partial unique index serve as an `ON CONFLICT` target?** Tested against real SQLite, the answer is
no — and that invalidated claims I had written in Phase 2A and Phase 2B.

```
ON CONFLICT(template_id, due_date_key) DO UPDATE ...
  -> ON CONFLICT clause does not match any PRIMARY KEY or UNIQUE constraint
```

SQLite requires a partial index's `WHERE` predicate to be repeated inside the conflict target.
Drift's `DoUpdate.target` takes a `List<Column>` with nowhere to put a predicate, so **no drift
upsert can dedupe against a partial index at all.** And separately: `insertOnConflictUpdate`
targets the **primary key** by default, which for a UUID PK is a fresh value that never conflicts —
so the row inserts and only *then* trips the unique index.

| Bug | Phase | What happened |
|---|---|---|
| `currency_dao.upsertRates` | 2A | Doc claimed `idx_rates_point` deduped. It didn't — the second rate fetch of any given day threw `UNIQUE constraint failed`. **The currency service fetches daily, so this would fire on ordinary use.** |
| `shopping_entry_dao.upsert` | 2B | Doc claimed `idx_shopping_auto` deduped. It didn't — the second low-stock regeneration threw. **This broke the exact idempotency anomaly A22 requires.** |

Both are fixed and included below:

- **`currency_dao.upsertRates`** — `idx_rates_point` is *not* partial, so an explicit
  `target: [baseCode, quoteCode, rateDateKey]` works. Verified: three consecutive same-day fetches
  now leave one row with the latest rate, no crash.
- **`shopping_entry_dao`** — `idx_shopping_auto` *is* partial, so no target can work. Added
  `upsertAutoEntry(...)`, read-then-write in one transaction, and corrected `upsert`'s doc to say
  plainly that it upserts by primary key only. Verified: three consecutive regenerations leave one
  entry with a stable id and a refreshed quantity.

I then audited **every** `insertOnConflictUpdate` in the project against the actual unique indexes.
The rest are correct: `app_settings`, `currencies`, `units` and `analytics_cache` have natural
primary keys that *are* the logical key, and `items` / `accounts` / `tags` / `payees` are
upsert-on-PK by design because Phase 3B resolves identity via `findByIdentity` /
`byNormalizedName` first — their doc comments already said so.

## Verification performed

| Check | Result |
|---|---|
| Partial index as `ON CONFLICT` target | **fails to compile** — the finding above, tested four ways (plain insert, target without predicate, target with predicate, `INSERT OR IGNORE`) |
| `upsertForDue` idempotency | read-then-insert in a transaction; repeated calls return the same id, no crash |
| `upsertRates` after fix | 3 same-day fetches → 1 row, latest rate, no crash |
| `upsertAutoEntry` after fix | 3 regenerations → 1 entry, stable id, refreshed quantity |
| Missing-import scan (the Phase 2B bug class) | 0 across all 63 project files, 14 types checked |
| Fabricated `attachedDatabase.xxxDao` getters (Phase 2B bug class) | 0 |
| Raw `DateKey` into a drift range helper (Phase 2A bug class) | 0 |
| Every `insertOnConflictUpdate` vs its table's real unique indexes | audited, table above |
| Brace/paren/bracket balance, all 9 changed files | balanced |

One typo caught in passing: a malformed dartdoc reference, `[beforeUtcMillis\`` instead of
`[beforeUtcMillis]`.

## Findings

**1. `upsertForDue` is read-then-insert, not an upsert, and that is a correctness requirement.**
Documented in the method itself so nobody "simplifies" it back into an upsert later.
`InsertMode.insertOrIgnore` would also avoid the crash and is rejected for a different reason: it
swallows *every* constraint violation, so a bad `templateId` would silently insert nothing rather
than surfacing the foreign-key error.

**2. `asset_dao` has no delete method of any kind — not even a soft one.** `dispose()` is the only
removal path. The `deletedAt` column exists on `assets` and nothing here writes it: it is reserved
for Phase 8B's trash screen, and a method to set it belongs there, deliberately, rather than sitting
in this class waiting to be called by mistake. `setStatus` additionally **throws** on
`AssetStatus.disposed` rather than silently accepting it, because a caller reaching for it to
dispose something has misunderstood the model — a disposal needs a reason and a date.

**3. `service_record_dao.lifetimeCostByCurrency` returns a map, not a number.**
`service_records.currencyCode` is per-row, so a vehicle serviced in two countries has costs in two
currencies and adding them is exactly anomaly A34. Summed in SQL and grouped by currency
(ARCH_3 §5.2); converting to the home currency is the currency service's job, above this layer.

**4. `notification_schedule_dao`'s cancel and replace methods return the superseded
`androidNotificationId`s, and that return value is the point.** Cancelling a row in the database
does nothing to the notification already registered with Android. Returning the ids makes the
OS-level cancel impossible to overlook; discovering it later means orphaned reminders pointing at
records that no longer exist. `nextAndroidNotificationId` also deliberately scans **all** rows
including cancelled and soft-deleted ones — reusing a cancelled id risks the OS dismissing the
wrong reminder.

**5. `analytics_cache` has a schema/spec conflict I could not resolve here, only document.**
ARCH_2 §9 gives the table a primary key of `cacheKey` alone; ARCH_3 §5.2 describes keying by
`(queryName, paramsHash)`. Both cannot hold — with `cacheKey` as the sole key, caching "spend by
subtype for July" evicts "…for June". `read()` treats a `paramsHash` mismatch as a **miss**, which
is safe (a stale entry for different parameters is never returned) but means switching date ranges
recomputes each time. If Phase 7B finds that costly, the caller can compose `cacheKey` as
`'queryName:paramsHash'` and get a row per parameter set with no schema change. That is a Phase 7B
decision, so this DAO does not impose it.

**6. No method in `recurring_template_dao` writes the anchor columns except `upsert`.**
`advanceNextDue` moves `nextDueDateKey` and nothing else, which is precisely why a bill anchored on
the 31st stays anchored on the 31st instead of walking backwards to the 28th after one February
(anomaly A13). Stated in the class doc so the constraint is visible before someone adds a
convenience method that breaks it.

**7. `v_recurring_due` has no `isOverdue` column and `unlinkDeletedTransaction` returns an
occurrence to `due`.** The first is ARCH_2 §12.2's rule — overdue is derived in Dart against the
injected `Clock`. The second matters because deleting the transaction that paid a bill must make
the obligation reappear rather than leave it silently marked settled.



---

### `lib/data/daos/recurring_template_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/date_key_filters.dart';

/// Typed access to `recurring_templates`, plus `v_recurring_due` for the due-list read.
///
/// **No method here ever writes `anchorDayOfMonth`, `anchorMonth` or `anchorWeekday` except
/// [upsert].** Those columns are stored once and clamped at *render* (anomaly A13): a bill
/// anchored on the 31st must stay anchored on the 31st, not walk backwards to the 28th
/// permanently after one February. [advanceNextDue] moves `nextDueDateKey` and nothing else,
/// which is exactly why the anchor survives.
class RecurringTemplateDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  RecurringTemplateDao(super.db);

  $RecurringTemplatesTable get _table => attachedDatabase.recurringTemplates;

  SimpleSelectStatement<$RecurringTemplatesTable, RecurringTemplateRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits every active template, paused included, in name order.
  Stream<List<RecurringTemplateRow>> watchAll() =>
      (_activeRows()..orderBy([(t) => OrderingTerm(expression: t.normalizedName)])).watch();

  /// Emits active templates in [direction] — the split that lets salary live in the same system
  /// as bills rather than needing a second one (anomaly A27).
  Stream<List<RecurringTemplateRow>> watchByDirection(RecurringDirection direction) {
    return (_activeRows()
          ..where((t) => t.direction.equalsValue(direction))
          ..orderBy([(t) => OrderingTerm(expression: t.nextDueDateKey)]))
        .watch();
  }

  /// Emits active, unpaused templates whose next due date falls in `[from, to]`.
  Stream<List<RecurringTemplateRow>> watchDueInRange({
    required DateKey from,
    required DateKey to,
  }) {
    return (_activeRows()
          ..where((t) => t.isPaused.equals(false) & t.nextDueDateKey.isInDateRange(from, to))
          ..orderBy([(t) => OrderingTerm(expression: t.nextDueDateKey)]))
        .watch();
  }

  /// Reads active, unpaused templates whose next due date is on or before [asOf] — what the
  /// recurring engine walks to materialise occurrences lazily up to today (anomaly A14).
  Future<List<RecurringTemplateRow>> needingMaterialisation(DateKey asOf) {
    return (_activeRows()
          ..where((t) => t.isPaused.equals(false) & t.nextDueDateKey.isDateOnOrBefore(asOf))
          ..orderBy([(t) => OrderingTerm(expression: t.nextDueDateKey)]))
        .get();
  }

  /// Reads one template by id, including a soft-deleted one — a settled occurrence and its
  /// transaction outlive the template, so the history still needs a name to render.
  Future<RecurringTemplateRow?> byIdIncludingDeleted(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads one active template by normalized name, for the merge-or-create decision.
  Future<RecurringTemplateRow?> byNormalizedName(String normalizedName) =>
      (_activeRows()..where((t) => t.normalizedName.equals(normalizedName))).getSingleOrNull();

  /// Emits active templates linked to [assetId] — the house-maid salary case, where a service
  /// provider's monthly payment hangs off an `assets` row (ARCH_2 §8.1).
  Stream<List<RecurringTemplateRow>> watchForAsset(String assetId) =>
      (_activeRows()..where((t) => t.linkedAssetId.equals(assetId))).watch();

  /// Inserts or updates a template.
  ///
  /// Upserts on the primary key, so the repository must resolve identity first via
  /// [byNormalizedName] and pass the existing row's `id` to update rather than create. Drift's
  /// default conflict target is the primary key, and `recurring_templates` has no other unique
  /// index, so there is nothing subtler happening here.
  Future<void> upsert(RecurringTemplatesCompanion template) =>
      into(_table).insertOnConflictUpdate(template);

  /// Moves `nextDueDateKey` forward after an occurrence is settled or skipped.
  ///
  /// Writes that one column and `updatedAt`. The anchor columns are untouched by construction —
  /// see this class's doc comment.
  Future<void> advanceNextDue({
    required String id,
    required DateKey nextDueDateKey,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      RecurringTemplatesCompanion(
        nextDueDateKey: Value(nextDueDateKey),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Pauses or resumes a template. A paused template materialises no new occurrences and leaves
  /// `v_recurring_due` entirely.
  Future<void> setPaused({
    required String id,
    required bool isPaused,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      RecurringTemplatesCompanion(isPaused: Value(isPaused), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Soft-deletes a template. Settled occurrences and the transactions they created survive
  /// untouched (ARCH_3 §4.1) — deleting a subscription does not un-pay last month's bill.
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      RecurringTemplatesCompanion(
        deletedAt: Value(nowUtcMillis),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  // ── the view ──────────────────────────────────────────────────────────────────────────

  /// Emits `v_recurring_due` — active, unpaused templates joined to their outstanding `due`
  /// occurrence.
  ///
  /// The view has no `isOverdue` column, deliberately: overdue is
  /// `occurrenceDueDateKey < clock.today()`, computed in Dart with the injected `Clock` so it
  /// stays deterministic and timezone-independent (ARCH_2 §12.2, Law L4).
  Stream<List<RecurringDueRow>> watchDue() => select(attachedDatabase.vRecurringDue).watch();

  /// Reads `v_recurring_due` once.
  Future<List<RecurringDueRow>> due() => select(attachedDatabase.vRecurringDue).get();
}
```

### `lib/data/daos/recurring_occurrence_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/date_key_filters.dart';

/// Typed access to `recurring_occurrences` — the third of the app's three append-only truths
/// (ARCH_1 §3.3).
class RecurringOccurrenceDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  RecurringOccurrenceDao(super.db);

  $RecurringOccurrencesTable get _table => attachedDatabase.recurringOccurrences;

  SimpleSelectStatement<$RecurringOccurrencesTable, RecurringOccurrenceRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Materialises the occurrence for `(templateId, dueDateKey)` if it does not already exist,
  /// and returns its id either way. Calling this twice is a no-op, never a crash.
  ///
  /// Implemented as read-then-insert inside one transaction rather than as an upsert, and that is
  /// a correctness requirement, not a style choice. `idx_recurring_occ` is a **partial** unique
  /// index (`... WHERE deleted_at IS NULL`), and SQLite rejects a partial index as an
  /// `ON CONFLICT` target unless the predicate is repeated in the target clause —
  /// `ON CONFLICT(template_id, due_date_key)` fails to compile with *"ON CONFLICT clause does not
  /// match any PRIMARY KEY or UNIQUE constraint"*. Drift's `DoUpdate.target` takes a column list
  /// with nowhere to put that predicate, so no drift upsert can dedupe against this index.
  /// Verified directly against SQLite.
  ///
  /// [InsertMode.insertOrIgnore] would also avoid the crash, and is rejected for a different
  /// reason: it swallows *every* constraint violation, so a bad `templateId` would silently
  /// insert nothing instead of surfacing the foreign-key error.
  ///
  /// Never creates money. A materialised occurrence is always `due`; only an explicit
  /// [markPaid] moves it, driven by a user tap (anomaly A14).
  Future<String> upsertForDue({
    required String id,
    required String templateId,
    required DateKey dueDateKey,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      final existing = await (_activeRows()
            ..where((t) => t.templateId.equals(templateId) & t.dueDateKey.isOnDate(dueDateKey)))
          .getSingleOrNull();
      if (existing != null) return existing.id;

      await into(_table).insert(
        RecurringOccurrencesCompanion.insert(
          id: id,
          templateId: templateId,
          dueDateKey: dueDateKey,
          status: RecurringOccurrenceStatus.due,
          createdAt: nowUtcMillis,
          updatedAt: nowUtcMillis,
        ),
      );
      return id;
    });
  }

  /// Emits the active occurrences of [templateId], newest due date first — the payment history.
  Stream<List<RecurringOccurrenceRow>> watchForTemplate(String templateId) {
    return (_activeRows()
          ..where((t) => t.templateId.equals(templateId))
          ..orderBy([(t) => OrderingTerm(expression: t.dueDateKey, mode: OrderingMode.desc)]))
        .watch();
  }

  /// Emits active occurrences due within `[from, to]`, whatever their status — the calendar's
  /// `recurringDue` source once filtered to `due` by the caller.
  Stream<List<RecurringOccurrenceRow>> watchDueInRange({
    required DateKey from,
    required DateKey to,
  }) {
    return (_activeRows()
          ..where((t) => t.dueDateKey.isInDateRange(from, to))
          ..orderBy([(t) => OrderingTerm(expression: t.dueDateKey)]))
        .watch();
  }

  /// Reads active occurrences still `due` on or before [asOf] — the overdue set, with the
  /// comparison supplied by the caller's `Clock` rather than by SQL (ARCH_2 §12.2).
  Future<List<RecurringOccurrenceRow>> outstandingAsOf(DateKey asOf) {
    return (_activeRows()
          ..where((t) =>
              t.status.equalsValue(RecurringOccurrenceStatus.due) &
              t.dueDateKey.isDateOnOrBefore(asOf))
          ..orderBy([(t) => OrderingTerm(expression: t.dueDateKey)]))
        .get();
  }

  /// Reads one occurrence by id.
  Future<RecurringOccurrenceRow?> byId(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Records that [id] was settled by [transactionId] for [paidAmountMinor] on [paidDateKey].
  ///
  /// The paid amount is stored on the occurrence, never written back to the template's default
  /// (anomaly A29): paying ₹520 against a ₹499 template records ₹520 here and leaves ₹499 as the
  /// template's expectation, so analytics uses actuals without corrupting the schedule.
  Future<void> markPaid({
    required String id,
    required String transactionId,
    required int paidAmountMinor,
    required DateKey paidDateKey,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      RecurringOccurrencesCompanion(
        status: const Value(RecurringOccurrenceStatus.paid),
        paidTransactionId: Value(transactionId),
        paidAmountMinor: Value(paidAmountMinor),
        paidDateKey: Value(paidDateKey),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Marks [id] as deliberately skipped — the user chose not to pay this one.
  Future<void> markSkipped({
    required String id,
    String? note,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      RecurringOccurrencesCompanion(
        status: const Value(RecurringOccurrenceStatus.skipped),
        note: note == null ? const Value.absent() : Value(note),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Marks [id] as dismissed — it was never meaningfully due, e.g. the template was paused
  /// retroactively.
  Future<void> markDismissed({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      RecurringOccurrencesCompanion(
        status: const Value(RecurringOccurrenceStatus.dismissed),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Clears the settlement link when the transaction that paid this occurrence is deleted,
  /// returning it to `due` so the obligation reappears rather than silently vanishing.
  Future<void> unlinkDeletedTransaction({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      RecurringOccurrencesCompanion(
        status: const Value(RecurringOccurrenceStatus.due),
        paidTransactionId: const Value(null),
        paidAmountMinor: const Value(null),
        paidDateKey: const Value(null),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Soft-deletes an occurrence.
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      RecurringOccurrencesCompanion(
        deletedAt: Value(nowUtcMillis),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }
}
```

### `lib/data/daos/asset_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/date_key_filters.dart';

/// Typed access to `assets`, plus `v_asset_alerts` for the warranty/service read.
///
/// **There is no delete method of any kind — not even a soft one.** Removing an asset is
/// [dispose], which sets `status = disposed` plus a reason, so the ₹45,000 spent on the TV stays
/// in analytics after the TV is gone (ARCH_3 §4.1). The `deletedAt` column exists on the table and
/// nothing in this class writes it: it is reserved for Phase 8B's trash screen, and a method to
/// set it should be added there, deliberately, rather than sitting here waiting to be called by
/// mistake.
class AssetDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  AssetDao(super.db);

  $AssetsTable get _table => attachedDatabase.assets;

  SimpleSelectStatement<$AssetsTable, AssetRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits assets that are not disposed, in name order — the main list.
  Stream<List<AssetRow>> watchInUse() {
    return (_activeRows()
          ..where((t) => t.status.equalsValue(AssetStatus.disposed).not())
          ..orderBy([(t) => OrderingTerm(expression: t.normalizedName)]))
        .watch();
  }

  /// Emits non-disposed assets of [type] — including `serviceProvider`, which is how a house maid
  /// lives in the same table as a TV (anomaly A30).
  Stream<List<AssetRow>> watchByType(AssetType type) {
    return (_activeRows()
          ..where((t) =>
              t.type.equalsValue(type) & t.status.equalsValue(AssetStatus.disposed).not())
          ..orderBy([(t) => OrderingTerm(expression: t.normalizedName)]))
        .watch();
  }

  /// Emits disposed assets, most recently disposed first — still viewable with their full
  /// history, because the money spent on them has not stopped being real.
  Stream<List<AssetRow>> watchDisposed() {
    return (_activeRows()
          ..where((t) => t.status.equalsValue(AssetStatus.disposed))
          ..orderBy([
            (t) => OrderingTerm(expression: t.disposedAtDateKey, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  /// Reads one asset by id, disposed or not.
  Future<AssetRow?> byId(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads one non-deleted asset by normalized name, for the merge-or-create decision.
  Future<AssetRow?> byNormalizedName(String normalizedName) =>
      (_activeRows()..where((t) => t.normalizedName.equals(normalizedName))).getSingleOrNull();

  /// Emits non-disposed assets whose warranty ends within `[from, to]`.
  Stream<List<AssetRow>> watchWarrantyEndingInRange({
    required DateKey from,
    required DateKey to,
  }) {
    return (_activeRows()
          ..where((t) =>
              t.warrantyEndDateKey.isInDateRange(from, to) &
              t.status.equalsValue(AssetStatus.disposed).not())
          ..orderBy([(t) => OrderingTerm(expression: t.warrantyEndDateKey)]))
        .watch();
  }

  /// Emits non-disposed assets whose next service falls within `[from, to]`.
  Stream<List<AssetRow>> watchServiceDueInRange({
    required DateKey from,
    required DateKey to,
  }) {
    return (_activeRows()
          ..where((t) =>
              t.nextServiceDueDateKey.isInDateRange(from, to) &
              t.status.equalsValue(AssetStatus.disposed).not())
          ..orderBy([(t) => OrderingTerm(expression: t.nextServiceDueDateKey)]))
        .watch();
  }

  /// Inserts or updates an asset.
  ///
  /// Upserts on the primary key; `assets` has no other unique index, so the repository resolves
  /// identity via [byNormalizedName] first and passes the existing `id` to update.
  Future<void> upsert(AssetsCompanion asset) => into(_table).insertOnConflictUpdate(asset);

  /// Moves an asset between `active` and `underRepair`.
  ///
  /// Deliberately cannot set `disposed`: that transition needs a reason and a date, so it goes
  /// through [dispose] instead. [ArgumentError] rather than a silent no-op, because a caller
  /// reaching for this to dispose something has misunderstood the model.
  Future<void> setStatus({
    required String id,
    required AssetStatus status,
    required int nowUtcMillis,
  }) {
    if (status == AssetStatus.disposed) {
      throw ArgumentError.value(
        status,
        'status',
        'Use dispose() — a disposal requires a reason and a date (ARCH_3 §4.1).',
      );
    }
    return (update(_table)..where((t) => t.id.equals(id))).write(
      AssetsCompanion(status: Value(status), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Retires an asset. **The only removal path** — this is what "delete my TV by selecting a
  /// reason" actually does (ARCH_3 §4.1).
  ///
  /// [amountMinor] is the sale proceeds when [reason] is [AssetDisposalReason.sold], and null
  /// otherwise. It is denominated in the asset's own `purchaseCurrencyCode`, since `assets` has no
  /// separate disposal currency column — pairing it with any other currency would silently
  /// misstate the figure (Law L1's pairing rule, as `MoneyColumns` documents).
  Future<void> dispose({
    required String assetId,
    required AssetDisposalReason reason,
    required DateKey dateKey,
    int? amountMinor,
    String? note,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(assetId))).write(
      AssetsCompanion(
        status: const Value(AssetStatus.disposed),
        disposalReason: Value(reason),
        disposedAtDateKey: Value(dateKey),
        disposalAmountMinor: amountMinor == null ? const Value.absent() : Value(amountMinor),
        disposalNote: note == null ? const Value.absent() : Value(note),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Returns a disposed asset to service, clearing the disposal fields — the undo for a
  /// mis-tapped [dispose].
  Future<void> undispose({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      AssetsCompanion(
        status: const Value(AssetStatus.active),
        disposalReason: const Value(null),
        disposedAtDateKey: const Value(null),
        disposalAmountMinor: const Value(null),
        disposalNote: const Value(null),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Moves `nextServiceDueDateKey` forward after a service is recorded.
  Future<void> advanceNextService({
    required String id,
    required DateKey nextServiceDueDateKey,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      AssetsCompanion(
        nextServiceDueDateKey: Value(nextServiceDueDateKey),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Clears the link from this asset to the transaction line that created it, when that
  /// transaction is deleted (anomaly A10) — the TV does not un-exist because the receipt did.
  Future<void> detachFromDeletedTransaction({
    required String id,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      AssetsCompanion(
        sourceTransactionLineId: const Value(null),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  // ── the view ──────────────────────────────────────────────────────────────────────────

  /// Emits `v_asset_alerts` — non-disposed assets carrying a warranty end or a next-service date.
  ///
  /// The view applies no time window, because a view takes no parameters; filter it with
  /// [watchWarrantyEndingInRange] or [watchServiceDueInRange], which hit `idx_asset_warranty` and
  /// `idx_asset_service` rather than scanning.
  Stream<List<AssetAlertRow>> watchAlerts() => select(attachedDatabase.vAssetAlerts).watch();

  /// Reads `v_asset_alerts` once.
  Future<List<AssetAlertRow>> alerts() => select(attachedDatabase.vAssetAlerts).get();
}
```

### `lib/data/daos/service_record_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/date_key_filters.dart';

/// Typed access to `service_records` — one service, repair or payment event against an asset.
class ServiceRecordDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  ServiceRecordDao(super.db);

  $ServiceRecordsTable get _table => attachedDatabase.serviceRecords;

  SimpleSelectStatement<$ServiceRecordsTable, ServiceRecordRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits the active records for [assetId], most recent first — the service timeline.
  Stream<List<ServiceRecordRow>> watchForAsset(String assetId) {
    return (_activeRows()
          ..where((t) => t.assetId.equals(assetId))
          ..orderBy([(t) => OrderingTerm(expression: t.serviceDateKey, mode: OrderingMode.desc)]))
        .watch();
  }

  /// Emits the active records of [type] for [assetId] — e.g. only `salaryPaid` rows, which is the
  /// payment log for a `serviceProvider` asset.
  Stream<List<ServiceRecordRow>> watchForAssetByType({
    required String assetId,
    required ServiceRecordType type,
  }) {
    return (_activeRows()
          ..where((t) => t.assetId.equals(assetId) & t.type.equalsValue(type))
          ..orderBy([(t) => OrderingTerm(expression: t.serviceDateKey, mode: OrderingMode.desc)]))
        .watch();
  }

  /// Emits active records whose scheduled next service falls within `[from, to]` — the second of
  /// the two `serviceDue` sources on the calendar, alongside `assets.nextServiceDueDateKey`
  /// (ARCH_3 §6).
  Stream<List<ServiceRecordRow>> watchWithNextDueInRange({
    required DateKey from,
    required DateKey to,
  }) {
    return (_activeRows()
          ..where((t) => t.nextDueDateKey.isInDateRange(from, to))
          ..orderBy([(t) => OrderingTerm(expression: t.nextDueDateKey)]))
        .watch();
  }

  /// Reads one record by id.
  Future<ServiceRecordRow?> byId(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads the most recent active record for [assetId], for the "last serviced" line.
  Future<ServiceRecordRow?> mostRecentForAsset(String assetId) {
    return (_activeRows()
          ..where((t) => t.assetId.equals(assetId))
          ..orderBy([(t) => OrderingTerm(expression: t.serviceDateKey, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Totals lifetime service cost for [assetId], **grouped by currency** (ARCH_3 §5.1 query 19).
  ///
  /// Returns a `currencyCode -> summed minor units` map rather than one number, because
  /// `service_records.currencyCode` is per-row: a vehicle serviced in two countries has costs in
  /// two currencies, and adding them would be exactly the mistake anomaly A34 describes.
  /// Converting to the home currency is the currency service's job, above this layer.
  ///
  /// Summed in SQL, not in Dart (ARCH_3 §5.2). Rows with a null `costMinor` contribute nothing,
  /// which `SUM` handles by ignoring them.
  Future<Map<String, int>> lifetimeCostByCurrency(String assetId) async {
    final total = _table.costMinor.sum();
    final rows = await (selectOnly(_table)
          ..addColumns([_table.currencyCode, total])
          ..where(_table.assetId.equals(assetId) &
              _table.deletedAt.isNull() &
              _table.costMinor.isNotNull())
          ..groupBy([_table.currencyCode]))
        .get();

    final result = <String, int>{};
    for (final row in rows) {
      final code = row.read(_table.currencyCode);
      final sum = row.read(total);
      if (code != null && sum != null) result[code] = sum;
    }
    return result;
  }

  /// Inserts a record.
  Future<void> insertRecord(ServiceRecordsCompanion record) => into(_table).insert(record);

  /// Inserts or updates a record.
  Future<void> upsert(ServiceRecordsCompanion record) =>
      into(_table).insertOnConflictUpdate(record);

  /// Clears the link to a transaction that has been deleted, leaving the service record itself
  /// intact — the repair happened whether or not the expense row survives.
  Future<void> unlinkDeletedTransaction({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      ServiceRecordsCompanion(
        linkedTransactionId: const Value(null),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Soft-deletes a record.
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      ServiceRecordsCompanion(
        deletedAt: Value(nowUtcMillis),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }
}
```

### `lib/data/daos/notification_schedule_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `notification_schedule` (ARCH_3 §7).
///
/// The table exists so every OS-level notification has a stable integer id that can be cancelled
/// when the record behind it changes — without it you get reminders for food already eaten.
class NotificationScheduleDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  NotificationScheduleDao(super.db);

  $NotificationScheduleTable get _table => attachedDatabase.notificationSchedule;

  SimpleSelectStatement<$NotificationScheduleTable, NotificationScheduleRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits every row still `scheduled`, soonest first.
  Stream<List<NotificationScheduleRow>> watchScheduled() {
    return (_activeRows()
          ..where((t) => t.status.equalsValue(NotificationStatus.scheduled))
          ..orderBy([(t) => OrderingTerm(expression: t.scheduledAtUtcMillis)]))
        .watch();
  }

  /// Reads rows still `scheduled` at or before [beforeUtcMillis] — what the daily `workmanager`
  /// job collects to hand to the OS.
  Future<List<NotificationScheduleRow>> scheduledDueBefore(int beforeUtcMillis) {
    return (_activeRows()
          ..where((t) =>
              t.status.equalsValue(NotificationStatus.scheduled) &
              t.scheduledAtUtcMillis.isSmallerOrEqualValue(beforeUtcMillis))
          ..orderBy([(t) => OrderingTerm(expression: t.scheduledAtUtcMillis)]))
        .get();
  }

  /// Reads the active rows pointing at `(refType, refId)`.
  Future<List<NotificationScheduleRow>> forRef({
    required String refType,
    required String refId,
  }) {
    return (_activeRows()..where((t) => t.refType.equals(refType) & t.refId.equals(refId))).get();
  }

  /// The next free `androidNotificationId`, one past the highest ever used.
  ///
  /// Deliberately reads across **every** row including cancelled and soft-deleted ones, rather
  /// than only live ones: reusing the id of a cancelled reminder risks colliding with a
  /// notification the OS has not actually dropped yet, and the user would see the wrong reminder
  /// dismissed. Starts at 1 — Android treats 0 as a valid id but some launchers handle it oddly,
  /// and starting at 1 costs nothing.
  Future<int> nextAndroidNotificationId() async {
    final highest = _table.androidNotificationId.max();
    final row = await (selectOnly(_table)..addColumns([highest])).getSingle();
    return (row.read(highest) ?? 0) + 1;
  }

  /// Replaces the schedule for `(refType, refId)` with [replacement], in one transaction
  /// (Law L14), and **returns the `androidNotificationId`s it superseded**.
  ///
  /// Those returned ids are the point of this method. Cancelling a reminder in the database does
  /// nothing to the notification already registered with Android, so the caller must cancel each
  /// returned id through `flutter_local_notifications` too. Returning them makes that step
  /// impossible to overlook; discovering it later means orphaned reminders that no longer
  /// correspond to anything.
  Future<List<int>> replaceForRef({
    required String refType,
    required String refId,
    required NotificationScheduleCompanion replacement,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      final superseded = await forRef(refType: refType, refId: refId);
      await (update(_table)
            ..where((t) =>
                t.refType.equals(refType) &
                t.refId.equals(refId) &
                t.status.equalsValue(NotificationStatus.scheduled)))
          .write(
        NotificationScheduleCompanion(
          status: const Value(NotificationStatus.cancelled),
          updatedAt: Value(nowUtcMillis),
        ),
      );
      await into(_table).insert(replacement);
      return superseded.map((row) => row.androidNotificationId).toList();
    });
  }

  /// Marks [id] as delivered.
  Future<void> markFired({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      NotificationScheduleCompanion(
        status: const Value(NotificationStatus.fired),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Cancels every scheduled row for `(refType, refId)` and returns the superseded Android ids,
  /// for the same reason [replaceForRef] does — used when the underlying record is deleted or
  /// resolved and no replacement reminder is wanted.
  Future<List<int>> cancelForRef({
    required String refType,
    required String refId,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      final cancelled = await (_activeRows()
            ..where((t) =>
                t.refType.equals(refType) &
                t.refId.equals(refId) &
                t.status.equalsValue(NotificationStatus.scheduled)))
          .get();
      await (update(_table)
            ..where((t) =>
                t.refType.equals(refType) &
                t.refId.equals(refId) &
                t.status.equalsValue(NotificationStatus.scheduled)))
          .write(
        NotificationScheduleCompanion(
          status: const Value(NotificationStatus.cancelled),
          updatedAt: Value(nowUtcMillis),
        ),
      );
      return cancelled.map((row) => row.androidNotificationId).toList();
    });
  }

  /// Cancels every scheduled row and returns their Android ids — what "turn all reminders off"
  /// in Settings calls.
  Future<List<int>> cancelAll({required int nowUtcMillis}) {
    return transaction(() async {
      final cancelled = await (_activeRows()
            ..where((t) => t.status.equalsValue(NotificationStatus.scheduled)))
          .get();
      await (update(_table)
            ..where((t) => t.status.equalsValue(NotificationStatus.scheduled)))
          .write(
        NotificationScheduleCompanion(
          status: const Value(NotificationStatus.cancelled),
          updatedAt: Value(nowUtcMillis),
        ),
      );
      return cancelled.map((row) => row.androidNotificationId).toList();
    });
  }

  /// Inserts one scheduled row.
  Future<void> insertSchedule(NotificationScheduleCompanion schedule) =>
      into(_table).insert(schedule);

  /// Soft-deletes rows that have already fired or been cancelled and are older than
  /// [olderThanUtcMillis] — housekeeping so the table does not grow without bound.
  Future<int> pruneSettled({
    required int olderThanUtcMillis,
    required int nowUtcMillis,
  }) {
    return (update(_table)
          ..where((t) =>
              t.deletedAt.isNull() &
              t.scheduledAtUtcMillis.isSmallerThanValue(olderThanUtcMillis) &
              t.status.equalsValue(NotificationStatus.scheduled).not()))
        .write(
      NotificationScheduleCompanion(
        deletedAt: Value(nowUtcMillis),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }
}
```

### `lib/data/daos/backup_history_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `backup_history` — a log of exports the user has taken (ARCH_3 §3.1).
class BackupHistoryDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  BackupHistoryDao(super.db);

  $BackupHistoryTable get _table => attachedDatabase.backupHistory;

  SimpleSelectStatement<$BackupHistoryTable, BackupHistoryRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits the most recent exports first, capped at [limit].
  ///
  /// `filePath` is recorded for display only and nothing reads from it — the file may since have
  /// been moved or deleted from outside the app, so the UI should present these as history rather
  /// than as openable links (ARCH_3 §3.1).
  Stream<List<BackupHistoryRow>> watchRecent({int limit = 20}) {
    return (_activeRows()
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)])
          ..limit(limit))
        .watch();
  }

  /// Reads the most recent export, for the "last backed up N days ago" line.
  Future<BackupHistoryRow?> latest() {
    return (_activeRows()
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Records one export.
  Future<void> insertEntry(BackupHistoryCompanion entry) => into(_table).insert(entry);

  /// Soft-deletes one history entry. Does not touch the file it describes — this app never
  /// deletes a file the user chose the location for.
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      BackupHistoryCompanion(deletedAt: Value(nowUtcMillis), updatedAt: Value(nowUtcMillis)),
    );
  }
}
```

### `lib/data/daos/analytics_cache_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `analytics_cache` — memoised results for analytics queries slower than roughly
/// 200 ms (ARCH_3 §5.2). Defined in Phase 1B, first used in Phase 7B.
///
/// **One entry per query name, not per parameter set.** ARCH_2 §9 gives this table a natural
/// primary key of `cacheKey` alone, while ARCH_3 §5.2 describes keying by
/// `(queryName, paramsHash)`. Those cannot both hold: with `cacheKey` as the sole key, storing
/// "spend by subtype for July" evicts "spend by subtype for June". [read] therefore treats a
/// `paramsHash` mismatch as a **miss**, which is correct and safe — a stale entry for different
/// parameters is never returned — but means switching date ranges back and forth recomputes each
/// time rather than hitting the cache.
///
/// If Phase 7B finds that costly, the fix is for the caller to compose `cacheKey` as
/// `'queryName:paramsHash'`, which makes each parameter set its own row with no schema change.
/// That is a Phase 7B decision, so this DAO does not impose it.
class AnalyticsCacheDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  AnalyticsCacheDao(super.db);

  $AnalyticsCacheTable get _table => attachedDatabase.analyticsCache;

  /// Reads the cached payload for [cacheKey], or null on any kind of miss.
  ///
  /// Returns null when the entry is absent, soft-deleted, was computed for a different
  /// [paramsHash], or is stale as of [nowUtcMillis]. Staleness is passed in rather than read from
  /// a clock here, so a caller with an injected `Clock` stays deterministic in tests — the same
  /// rule the views follow (ARCH_2 §12.2).
  Future<String?> read({
    required String cacheKey,
    required String paramsHash,
    required int nowUtcMillis,
  }) async {
    final row = await (select(_table)
          ..where((t) => t.cacheKey.equals(cacheKey) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) return null;
    if (row.paramsHash != paramsHash) return null;
    if (row.staleAfter <= nowUtcMillis) return null;
    return row.payloadJson;
  }

  /// Stores or replaces the cached payload for [cacheKey].
  ///
  /// Upserts on `cacheKey`, which is this table's primary key — so unlike most tables in this
  /// project, drift's default conflict target is exactly the logical key and no explicit target is
  /// needed. Clears `deletedAt` so writing over an invalidated entry revives the row rather than
  /// leaving one [read] will keep filtering out.
  Future<void> write({
    required String cacheKey,
    required String paramsHash,
    required String payloadJson,
    required int computedAtUtcMillis,
    required int staleAfterUtcMillis,
  }) {
    return into(_table).insertOnConflictUpdate(
      AnalyticsCacheCompanion.insert(
        cacheKey: cacheKey,
        paramsHash: paramsHash,
        payloadJson: payloadJson,
        computedAt: computedAtUtcMillis,
        staleAfter: staleAfterUtcMillis,
        createdAt: computedAtUtcMillis,
        updatedAt: computedAtUtcMillis,
        deletedAt: const Value(null),
      ),
    );
  }

  /// Invalidates one cached query by soft-deleting its row.
  ///
  /// Soft rather than hard so the purge job remains the only hard delete in the codebase
  /// (ARCH_3 §4.2), and so [write] can revive the same row instead of accumulating tombstones.
  Future<void> invalidate({required String cacheKey, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.cacheKey.equals(cacheKey))).write(
      AnalyticsCacheCompanion(deletedAt: Value(nowUtcMillis), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Invalidates every cached query — what a write to any contributing table triggers, since
  /// tracking which queries depend on which tables is not worth the bookkeeping at this scale.
  Future<int> invalidateAll({required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.deletedAt.isNull())).write(
      AnalyticsCacheCompanion(deletedAt: Value(nowUtcMillis), updatedAt: Value(nowUtcMillis)),
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

### `lib/data/daos/shopping_entry_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `shopping_entries`.
class ShoppingEntryDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  ShoppingEntryDao(super.db);

  $ShoppingEntriesTable get _table => attachedDatabase.shoppingEntries;

  SimpleSelectStatement<$ShoppingEntriesTable, ShoppingEntryRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits the active, unchecked entries of [listId], grouped by [ShoppingEntryRow.tagId] in the
  /// UI (the group header, ARCH_2 §6) — this DAO returns the flat, sorted list; grouping is a
  /// presentation concern.
  Stream<List<ShoppingEntryRow>> watchForList(String listId) {
    return (_activeRows()
          ..where((t) => t.listId.equals(listId))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Emits only the unchecked active entries of [listId] — what the shopping screen shows by
  /// default, before "show completed" is toggled.
  Stream<List<ShoppingEntryRow>> watchUncheckedForList(String listId) {
    return (_activeRows()
          ..where((t) => t.listId.equals(listId) & t.isChecked.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Emits the currently visible auto-generated suggestions for [listId] — `active`, not
  /// `snoozed` or `dismissed` (anomaly A23).
  Stream<List<ShoppingEntryRow>> watchActiveAutoSuggestions(String listId) {
    return (_activeRows()
          ..where((t) =>
              t.listId.equals(listId) &
              t.origin.equalsValue(ShoppingEntryOrigin.autoLowStock) &
              t.autoState.equalsValue(ShoppingEntryAutoState.active))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Reads one entry by id, including a soft-deleted one.
  Future<ShoppingEntryRow?> byIdIncludingDeleted(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads the active auto-generated entry for `(listId, itemId)`, if one exists — the read side
  /// of `idx_shopping_auto`'s partial unique index, and what the suggestion engine checks before
  /// deciding whether to insert, update or leave an entry alone.
  Future<ShoppingEntryRow?> findAutoEntry({
    required String listId,
    required String itemId,
  }) {
    return (_activeRows()
          ..where((t) =>
              t.listId.equals(listId) &
              t.itemId.equals(itemId) &
              t.origin.equalsValue(ShoppingEntryOrigin.autoLowStock)))
        .getSingleOrNull();
  }

  /// Inserts or updates an entry **by primary key**.
  ///
  /// For a manual entry that is all you need: the repository holds the row's `id`, or generates a
  /// new one. For an auto-generated suggestion use [upsertAutoEntry] instead — this method will
  /// **not** dedupe against `idx_shopping_auto`, for the reason documented there.
  Future<void> upsert(ShoppingEntriesCompanion entry) =>
      into(_table).insertOnConflictUpdate(entry);

  /// Inserts or updates the single active auto-generated suggestion for `(listId, itemId)`,
  /// idempotently (anomaly A22). Calling it repeatedly is a no-op, never a crash.
  ///
  /// Read-then-write inside one transaction, and it has to be. `idx_shopping_auto` is a
  /// **partial** unique index (`WHERE origin = 'autoLowStock' AND deleted_at IS NULL`), and SQLite
  /// refuses a partial index as an `ON CONFLICT` target unless the predicate is repeated in the
  /// target clause — which drift's column-list `DoUpdate.target` has nowhere to put. Verified
  /// against SQLite: `ON CONFLICT(list_id, item_id)` fails to compile with *"ON CONFLICT clause
  /// does not match any PRIMARY KEY or UNIQUE constraint"*, and `insertOnConflictUpdate` targets
  /// the primary key, so a fresh `id` would insert and only then trip the index. Regenerating
  /// low-stock suggestions a second time threw `UNIQUE constraint failed` before this fix.
  ///
  /// [newId] is used only when no auto entry exists yet, so a caller can generate a UUID
  /// unconditionally without leaking an unused row.
  Future<void> upsertAutoEntry({
    required String newId,
    required String listId,
    required String itemId,
    required int quantityMilli,
    String? unitCode,
    String? tagId,
    required int stockAtGenerationMilli,
    required int sortOrder,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      final existing = await findAutoEntry(listId: listId, itemId: itemId);
      if (existing == null) {
        await into(_table).insert(
          ShoppingEntriesCompanion.insert(
            id: newId,
            listId: listId,
            itemId: Value(itemId),
            quantityMilli: Value(quantityMilli),
            unitCode: Value(unitCode),
            tagId: Value(tagId),
            isChecked: false,
            origin: ShoppingEntryOrigin.autoLowStock,
            autoState: ShoppingEntryAutoState.active,
            generatedAtStockMilli: Value(stockAtGenerationMilli),
            sortOrder: sortOrder,
            createdAt: nowUtcMillis,
            updatedAt: nowUtcMillis,
          ),
        );
        return;
      }
      // Refresh the suggested quantity and the stock reading it was based on. `origin` and
      // `autoState` are left alone: an entry the user has edited was already promoted to `manual`
      // and would not be found by findAutoEntry, and one they dismissed keeps that state.
      await (update(_table)..where((t) => t.id.equals(existing.id))).write(
        ShoppingEntriesCompanion(
          quantityMilli: Value(quantityMilli),
          generatedAtStockMilli: Value(stockAtGenerationMilli),
          updatedAt: Value(nowUtcMillis),
        ),
      );
    });
  }

  /// Promotes an auto-generated entry to `manual`, so the suggestion engine never removes it
  /// after the user has edited it (anomaly A22).
  Future<void> promoteToManual({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      ShoppingEntriesCompanion(
        origin: const Value(ShoppingEntryOrigin.manual),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Snoozes or dismisses an auto-generated suggestion, recording the stock level at the moment
  /// of the decision so it does not reappear until stock has genuinely changed (anomaly A23).
  Future<void> setAutoState({
    required String id,
    required ShoppingEntryAutoState autoState,
    required int stockAtDecisionMilli,
    DateKey? snoozeUntil,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      ShoppingEntriesCompanion(
        autoState: Value(autoState),
        generatedAtStockMilli: Value(stockAtDecisionMilli),
        snoozeUntilDateKey:
            snoozeUntil == null ? const Value.absent() : Value(snoozeUntil),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Ticks or unticks an entry.
  Future<void> setChecked({
    required String id,
    required bool isChecked,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      ShoppingEntriesCompanion(
        isChecked: Value(isChecked),
        checkedAt: isChecked ? Value(nowUtcMillis) : const Value(null),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Records which transaction line fulfilled this entry — the write half of convert-to-purchase
  /// (anomaly A25). Does not itself tick the entry; the repository does both in one call so
  /// "purchased" and "checked" cannot disagree.
  Future<void> markPurchased({
    required String id,
    required String transactionLineId,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      ShoppingEntriesCompanion(
        purchasedTransactionLineId: Value(transactionLineId),
        isChecked: const Value(true),
        checkedAt: Value(nowUtcMillis),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Reorders entries within a list by writing each id's new `sortOrder` in one transaction
  /// (Law L14), so a drag-reorder can never leave the list half-renumbered.
  Future<void> reorder({
    required List<String> orderedIds,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (update(_table)..where((t) => t.id.equals(orderedIds[i]))).write(
          ShoppingEntriesCompanion(sortOrder: Value(i), updatedAt: Value(nowUtcMillis)),
        );
      }
    });
  }

  /// Soft-deletes an entry.
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      ShoppingEntriesCompanion(deletedAt: Value(nowUtcMillis), updatedAt: Value(nowUtcMillis)),
    );
  }
}
```
