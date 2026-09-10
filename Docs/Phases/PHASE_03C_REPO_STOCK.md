# Phase 3C — Inventory & Shopping Repository Implementations

> **Regenerated 2026-08-02 from the canonical tree.** Every fix through the Phase 6C debugging
> pass is folded in; this document and the working tree are in sync, and regenerating from it
> reproduces the code that runs. Earlier revisions reintroduce defects listed in ARCH_6 §3.
>
> Files shared with other phase documents — `app_en.arb`, `routes.dart`, `app_router.dart`,
> `layout_overflow_test.dart`, and the Phase 6A editor files amended by 6B and 6C — carry
> **identical** content in every copy, so they may be applied in any order.

**4 repositories · 52 contract methods · 2 mapper files · 2 infrastructure gaps closed ·
6 real defects found and fixed.**

The previous attempt was cut off mid-fix. Before continuing I verified what had actually reached
disk rather than assuming: all three aborted fixes had landed, and `shopping_repository_impl.dart`
had never been written. Everything below was then re-derived from the source on disk.

## Add dependencies

None. Every import resolves to packages already present.

## Fix in this revision — six compiler errors, plus six unused imports

**Errors 1–3: `unitCategory` undefined on `BatchStockCheckRow`.** These made me re-examine my own
justification, and it did not hold up. I had added `JOIN items` to `v_batch_stock_check` arguing
that "the two sibling inventory views carry `unit_category`, so its absence was an inconsistency."
But those views carry it because **`items` is already their driving table** — `v_item_stock` is
`FROM items i`, and `v_low_stock` selects from `v_item_stock`. `v_batch_stock_check` is
batch-centric with no `items` in its `FROM` clause at all, so I had added a join to a view that
scans every batch, purely to surface one column — while `BatchRepositoryImpl` already held an
`ItemCategoryResolver` it uses for exactly this on the batch and movement rows beside it.

Reverted the view. `BatchReconciliationMapper.toEntity` now takes the category like its two
siblings in the same file, and both call sites resolve it through the existing resolver. That
removes the join, makes all three row mappers in `stock_mappers.dart` consistent, and drops any
dependency on drift propagating a type converter through a join.

**Errors 4–6: entity field names used on a row type.** `buildPurchaseDraft` iterated
`ShoppingEntryRow` but read `entry.quantity` and `entry.estimatedPrice` — those are *entity* fields;
the row exposes `quantityMilli` and `estimatedPriceMinor`. Rather than rename the fields and
hand-assemble a `Qty` and `Money` at a second site, the method now builds from **mapped entities**
via `_mapEntries`, which already resolves the category and currency correctly. One derivation, not
two.

**Then a bug class I had never checked: unused imports.** Removing the now-dead `Qty` import
prompted me to build a scanner for it — `very_good_analysis` treats unused imports as errors, so
these would have failed the build. My first scan reported 14, but most were false positives: it only
read hand-written source, and `alaya_database.dart`'s row classes (`ItemRow`, `ItemsCompanion`) live
in its **generated part file**. After teaching the scanner to derive those generated names, **six
were genuine** — including two in Phase 3B files I had already reported clean:

| File | Unused import |
|---|---|
| `mappers/money_mappers.dart` | `core/enums/money_enums.dart` |
| `mappers/stock_mappers.dart` | `core/enums/inventory_enums.dart`, `core/quantity/qty.dart` |
| `shopping_repository_impl.dart` | `core/quantity/qty.dart` |
| `transaction_repository_impl.dart` *(Phase 3B)* | `core/enums/inventory_enums.dart`, `core/quantity/unit_category.dart` |

All six removed. The scanner is now part of the standing audit set.

### Final verification state — nine categories, all zero

| Check | Result |
|---|---|
| The 6 reported compiler errors | **fixed** |
| Brace balance, 20 repository files | 0 |
| Missing imports — 120 files vs 201 declared types | 0 |
| **Unused imports** (new check) | 0 |
| `const` with runtime interpolation | 0 |
| `DateTime.now()` outside `Clock` | 0 |
| Raw `DateKey` into a drift range helper | 0 |
| Fabricated `attachedDatabase.xxxDao` getters | 0 |
| `Qty` debug `toString` in user-facing text | 0 |
| **Entity-vs-row field confusion** (new check) | 0 |
| Contract coverage | **52/52 exact across 4 interfaces** |

## Infrastructure: one gap closed, one reverted

**1. `v_batch_stock_check` and `unit_category` — attempted, then reverted.** See the fix section
above: I added a `JOIN items` on a reasoning error, and backed it out. The category is resolved in
Dart through the `ItemCategoryResolver` that already exists for the batch and movement rows. The
view is unchanged from Phase 1C.

**2. `BatchDao.applyMovement` is single-batch and opens its own transaction**, so FEFO consumption
across N batches could not be atomic through it. Calling it in a loop would open N transactions —
a failure partway through would leave the ledger describing a consumption that only partly
happened, with earlier batches drawn down and later ones untouched. Added
`BatchDao.applyMovements` (plural), which pairs every movement with its cache update inside one
transaction (Laws L3 + L14).

## Six real defects found and fixed

| # | Defect | Why it mattered |
|---|---|---|
| 1 | `UnitCategoryHolder` — a type I invented that does not exist | would not compile |
| 2 | `wasteTotals` passed `itemId: ''` to a per-item query | would silently return an empty list forever — a wrong answer, not an error |
| 3 | `isInValues` on a converter-backed enum column | its SQL type is `String`, so it demands the mapped strings, not the Dart enum. Replaced with the folded `equalsValue` form already verified twice in earlier phases |
| 4 | `batch_repository_impl.dart` used `InventoryBatchRow` without importing `alaya_database.dart` | would not compile — same class as the Phase 2B/3B import bugs |
| 5 | `stock_repository_impl.dart` used `UnitCategory` without importing it | introduced *by* fixing defect 1; caught by the exhaustive scanner |
| 6 | **`Qty.toString()` leaked into three user-facing messages** | `Qty`'s own doc says *"Never use this for UI display"*. The user would have read `Only 500000m(weight) is on hand`. Now reads `Only 500 g is on hand, less than the 600 g requested.` |

Defect 6 is the one worth dwelling on: it compiles, it passes every structural check, and it would
have shipped. It was caught only by reading what the message would actually render as.

## Verification performed

| Check | Result |
|---|---|
| **Contract coverage** — every declared method implemented, no extras | **52/52 exact across all 4 interfaces** |
| Exhaustive missing-import scan — every file vs every declared type | 120 files, 201 types, **0 problems** |
| DAO call-site vs brace-matched actual signature | 0 mismatches |
| Mapper/helper call-site vs signature | 0 mismatches |
| Mapper field reads vs real table definitions | 5 row classes, 55 field reads, **0 mismatches** |
| Brace/paren/bracket balance | 20 files, 0 unbalanced |
| `const` with runtime interpolation | 0 |
| `DateTime.now()` outside `Clock` | 0 |
| Raw `DateKey` into a drift range helper | 0 |
| Fabricated `attachedDatabase.xxxDao` getters | 0 |
| `Qty` debug `toString` in user-facing text | 0 |
| Patched view vs real SQLite, incl. soft-deleted item | correct |

**Behavioural verification, run rather than reasoned about:**

- **FEFO draw-down** — the exact scenario the architecture specifies: 3 batches, consume 600 g →
  `300 g` from nearest-expiry, `300 g` from next, undated batch untouched. Plus exact-total,
  single-batch, exact-boundary (must not emit a zero-quantity draw on the next batch), the
  zero-remaining-batch skip, and 1-milli-over-total insufficiency writing nothing.
- **Levenshtein** — verified exhaustively over every `{a,b}` string up to length 4, plus realistic
  item names and 3000 random pairs, against an independent reference. This checked the two-row
  **swap idiom** specifically, which is where that algorithm usually goes wrong.
- **Length pre-filter** — proved over 4000 random pairs that it never excludes a genuine
  distance ≤ 2 match.
- **Item identity** — `(milk, weight)` merges; `(milk, volume)` and `(milk, count)` each create a
  separate item, never a merge.
- **L8 rejection** — a category change on an existing item is refused; new items and unchanged
  categories pass.
- **Auto → manual promotion** — 5 cases. Decided from the **stored** row, not the incoming
  entity, so a UI that forgets to flip the flag cannot defeat it.
- **Dismissal suppression and recovery** — 7 cases. A dismissed suggestion whose stock fell
  *further* stays suppressed (no nagging); one that recovered above the decision point returns
  (no permanent silence).

## Findings

**`findSimilar` excludes distance 0 deliberately.** An exact normalized match in the same category
is the *identity* — `findByIdentity`'s job, and a merge — not a suggestion. Including it would ask
the user "did you mean this same item?".

**The `≤ 2` threshold is permissive on short names** — `tea`/`pea` are one edit apart. That is
correct per spec and safe only because these are suggestions the user confirms and never an
automatic merge (anomaly A07). Scaling the threshold by length would stop catching typos in short
names, which is where typos are most likely.

**`ItemCategoryResolver` caches, and that is safe precisely because of Law L8.** A `Qty` is
meaningless without its `UnitCategory`, which lives on the item, not on the batch or movement.
Because an item's category is immutable once created, a cached value can never go stale — the
immutability rule is what makes the cache correct rather than a risk.

**`shopping_entries` has no currency column, so the estimated-price mapper takes
`homeCurrencyCode` explicitly.** My first draft hardcoded `'INR'` as a module constant. That is a
real defect for every user outside India — a yen estimate would carry `INR`, breaking Law L1's
pairing rule. `SettingsRepository` now supplies it.

**`markPurchased` bridges a contract/DAO shape mismatch.** The contract hands over a
`transactionId`; an entry links to one specific *line*, because knowing which line fulfilled it is
what lets the UI show the price actually paid (anomaly A25). Matching is by `itemId` — which
`buildPurchaseDraft` carried across when it built each line from an entry — with a description
fallback for free-text entries. Unmatched entries are **reported**, not swallowed: the ones that
matched are already linked, and silently dropping the rest would leave the list half-updated with
no explanation.

**`buildPurchaseDraft` writes nothing and leaves `transactionId` empty.** The transaction does not
exist yet; inventing an id would let a caller persist a line pointing at nothing. A catalogued item
gets `destination: inventory`, free text gets `none` — free text has nowhere to land as stock
(anomaly A12).

**`setListArchived` refuses to archive the default list**, and `setDefaultList` refuses to promote
an archived one. Archiving the default would leave quick-add with nowhere to write, silently.

**`recomputeAll` counts discrepancies before repairing, not after.** Afterwards there are none
left, so asking then would always return zero and report that nothing had been wrong.

**`BatchRepository.updateMetadata` refuses a quantity change.** Quantities move only by recording a
movement, so the ledger and the cache cannot disagree (Law L3). A metadata write that also changed a
quantity would produce exactly the drift `v_batch_stock_check` exists to detect.

**`StockRepository.reverse` refuses to reverse a reversal.** A chain would be indistinguishable
from re-applying the original and nothing could interpret it. Undo is one level deep by design.



---

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

### `lib/data/daos/batch_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/date_key_filters.dart';
import 'package:alaya/data/daos/stock_movement_dao.dart';

/// Typed access to `inventory_batches`, plus the one write path that keeps its cached
/// `remainingQuantityMilli` (Law L3's stored exception) honest against the movement ledger.
///
/// Writes `stock_movements` directly via `attachedDatabase.stockMovements` rather than through a
/// `StockMovementDao` instance — `AlayaDatabase` exposes tables and views as generated getters,
/// never DAOs, so there is no `attachedDatabase.stockMovementDao` to call. `StockMovementDao`'s
/// direction rule ([StockMovementDao.signedQuantityOf], [StockMovementDao.incomingKinds]) is a
/// `static` member for exactly this reason: it is shared logic, usable from here without needing
/// an instance of the other DAO.
class BatchDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  BatchDao(super.db);

  $InventoryBatchesTable get _table => attachedDatabase.inventoryBatches;
  $StockMovementsTable get _movements => attachedDatabase.stockMovements;

  SimpleSelectStatement<$InventoryBatchesTable, InventoryBatchRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits the active batches of [itemId] in FEFO order: nearest expiry first, batches with no
  /// expiry last, ties broken by purchase date.
  ///
  /// This is the exact order the consumption engine (Phase 4B) draws down — dated stock before
  /// undated, oldest dated stock first (anomaly A08). SQL's `NULLS LAST` is not portable to
  /// SQLite; the same effect here is `expiryDateKey IS NULL` ascending, which puts `0` (has a
  /// date) before `1` (no date).
  Stream<List<InventoryBatchRow>> watchByItemFefo(String itemId) {
    return (_activeRows()
          ..where((t) => t.itemId.equals(itemId) & t.remainingQuantityMilli.isBiggerThanValue(0))
          ..orderBy([
            (t) => OrderingTerm(expression: t.expiryDateKey.isNull()),
            (t) => OrderingTerm(expression: t.expiryDateKey),
            (t) => OrderingTerm(expression: t.purchasedDateKey),
          ]))
        .watch();
  }

  /// Reads the same FEFO-ordered list once — what the consumption engine actually walks.
  Future<List<InventoryBatchRow>> byItemFefo(String itemId) {
    return (_activeRows()
          ..where((t) => t.itemId.equals(itemId) & t.remainingQuantityMilli.isBiggerThanValue(0))
          ..orderBy([
            (t) => OrderingTerm(expression: t.expiryDateKey.isNull()),
            (t) => OrderingTerm(expression: t.expiryDateKey),
            (t) => OrderingTerm(expression: t.purchasedDateKey),
          ]))
        .get();
  }

  /// Emits active batches of [itemId], purchase order — for the expanded item-detail list,
  /// which itemises rather than sums (ARCH_1 §5.4).
  Stream<List<InventoryBatchRow>> watchByItem(String itemId) {
    return (_activeRows()
          ..where((t) => t.itemId.equals(itemId))
          ..orderBy([(t) => OrderingTerm(expression: t.purchasedDateKey, mode: OrderingMode.desc)]))
        .watch();
  }

  /// Emits active batches expiring within `[from, to]` with stock remaining — the calendar and
  /// notification source, and ARCH_3 §5.1 query 15.
  Stream<List<InventoryBatchRow>> watchExpiringInRange({
    required DateKey from,
    required DateKey to,
  }) {
    return (_activeRows()
          ..where((t) =>
              t.expiryDateKey.isInDateRange(from, to) &
              t.remainingQuantityMilli.isBiggerThanValue(0))
          ..orderBy([(t) => OrderingTerm(expression: t.expiryDateKey)]))
        .watch();
  }

  /// Reads one batch by id, including a soft-deleted one.
  Future<InventoryBatchRow?> byIdIncludingDeleted(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Inserts a new batch, together with its opening `stock_movements` row, atomically (Law L14).
  ///
  /// A batch never exists without a founding movement — otherwise `v_batch_stock_check` would
  /// report the freshly-created row as a permanent discrepancy of its own initial quantity.
  /// [openingKind] is [StockMovementKind.purchaseIn] when [batch]'s `sourceTransactionLineId`
  /// is set, [StockMovementKind.manualIn] or [StockMovementKind.openingIn] otherwise — the
  /// repository's call to make, not this DAO's.
  ///
  /// **Caller contract:** [batch]'s `remainingQuantityMilli` must equal its
  /// `initialQuantityMilli` — nothing has been consumed yet, so they cannot differ. This is the
  /// one write in this class with no `update(_table)` call: the cache value is established once,
  /// correctly, at insert, matching Phase 2A's item DAO precedent of trusting the caller's
  /// `Companion` rather than reconstructing one field at a time.
  Future<void> insertWithOpeningMovement({
    required InventoryBatchesCompanion batch,
    required StockMovementKind openingKind,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      await into(_table).insert(batch);
      await into(_movements).insert(
        StockMovementsCompanion.insert(
          id: '${batch.id.value}-opening',
          batchId: batch.id.value,
          itemId: batch.itemId.value,
          kind: openingKind,
          quantityMilli: batch.initialQuantityMilli.value,
          occurredAt: nowUtcMillis,
          dateKey: batch.purchasedDateKey.value,
          createdAt: nowUtcMillis,
          updatedAt: nowUtcMillis,
        ),
      );
    });
  }

  /// Applies one movement to [batchId] and updates its cached remaining quantity, atomically
  /// (Law L14 + L3). **The one path every stock change should go through** — every other write
  /// method on this class touches display metadata, never the quantity.
  ///
  /// The new cache value is `current + signedQuantity`, where the sign comes from
  /// [StockMovementDao.signedQuantityOf] — the same direction rule `v_batch_stock_check` uses,
  /// so a batch written through this method can never itself become the discrepancy that view
  /// exists to catch.
  Future<void> applyMovement({
    required String batchId,
    required StockMovementsCompanion movement,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      await into(_movements).insert(movement);

      final signed = StockMovementDao.signedQuantityOf(
        kind: movement.kind.value,
        quantityMilli: movement.quantityMilli.value,
      );
      await (update(_table)..where((t) => t.id.equals(batchId))).write(
        InventoryBatchesCompanion.custom(
          remainingQuantityMilli: _table.remainingQuantityMilli + Variable<int>(signed),
          updatedAt: Variable<int>(nowUtcMillis),
        ),
      );
    });
  }

  /// Applies several movements across several batches in **one** transaction (Law L14 + L3).
  ///
  /// FEFO consumption spans as many batches as it takes to satisfy the requested quantity, and
  /// either all of it happened or none of it did. Calling [applyMovement] in a loop would open one
  /// transaction per batch, so a failure partway through would leave the ledger describing a
  /// consumption that only partly occurred — with the earlier batches drawn down and the later
  /// ones untouched, and no record that the operation was ever meant to be a single act.
  ///
  /// Each entry pairs a batch with the movement to record against it; the cache delta is derived
  /// per entry from [StockMovementDao.signedQuantityOf], the same direction rule
  /// `v_batch_stock_check` uses.
  Future<void> applyMovements({
    required List<({String batchId, StockMovementsCompanion movement})> entries,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      for (final entry in entries) {
        await into(_movements).insert(entry.movement);

        final signed = StockMovementDao.signedQuantityOf(
          kind: entry.movement.kind.value,
          quantityMilli: entry.movement.quantityMilli.value,
        );
        await (update(_table)..where((t) => t.id.equals(entry.batchId))).write(
          InventoryBatchesCompanion.custom(
            remainingQuantityMilli: _table.remainingQuantityMilli + Variable<int>(signed),
            updatedAt: Variable<int>(nowUtcMillis),
          ),
        );
      }
    });
  }

  /// Rebuilds [batchId]'s cached remaining quantity from its full movement history — the Law L3
  /// repair path, and the formula `v_batch_stock_check.ledger_remaining_milli` computes.
  ///
  /// Deliberately independent of the current cache value: this reads every movement for
  /// [batchId] and writes an absolute new total, rather than applying a delta, so it self-heals
  /// even if the cache had drifted before this ran.
  Future<void> recomputeRemaining(String batchId) async {
    final movements = await (select(_movements)..where((t) => t.batchId.equals(batchId))).get();
    final total = movements.fold<int>(
      0,
      (sum, m) =>
          sum + StockMovementDao.signedQuantityOf(kind: m.kind, quantityMilli: m.quantityMilli),
    );
    await (update(_table)..where((t) => t.id.equals(batchId))).write(
      InventoryBatchesCompanion(remainingQuantityMilli: Value(total)),
    );
  }

  /// Runs [recomputeRemaining] over every active batch — the Settings "repair stock" action.
  ///
  /// Sequential rather than parallel: each call is its own small transaction, and running them
  /// concurrently against one connection would only queue anyway. On the scale this app runs at
  /// (thousands of batches, not millions) sequential is fast enough to matter more for
  /// correctness — a batch that throws is easy to isolate — than for speed.
  Future<void> recomputeAll() async {
    final rows = await _activeRows().get();
    for (final row in rows) {
      await recomputeRemaining(row.id);
    }
  }

  /// Updates a batch's display metadata — location, note, expiry, cost. Never its quantity;
  /// [applyMovement] is the only path that may change `remainingQuantityMilli`.
  Future<void> updateMetadata(InventoryBatchesCompanion batch) =>
      update(_table).replace(batch);

  /// Marks a batch `detached` when its source transaction is deleted (anomaly A10) — the food
  /// does not un-exist because the receipt did. Clears the dangling link and leaves the
  /// quantity untouched.
  Future<void> detachFromDeletedTransaction({
    required String batchId,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(batchId))).write(
      InventoryBatchesCompanion(
        sourceTransactionLineId: const Value(null),
        origin: const Value(BatchOrigin.detached),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Soft-deletes a batch. Movements are untouched — the ledger is append-only regardless of
  /// whether the batch it describes is still visible (Law L6's stated exception).
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      InventoryBatchesCompanion(deletedAt: Value(nowUtcMillis), updatedAt: Value(nowUtcMillis)),
    );
  }

  // ── the reconciliation probe ────────────────────────────────────────────────────────────

  /// Emits every batch's cache-vs-ledger reconciliation from `v_batch_stock_check`.
  /// `discrepancyMilli` must be `0` for every row; a non-zero one is exactly what
  /// [recomputeRemaining] repairs.
  Stream<List<BatchStockCheckRow>> watchReconciliation() =>
      select(attachedDatabase.vBatchStockCheck).watch();

  /// Reads batches whose cache disagrees with their ledger — the Settings screen's "N batches
  /// need repair" count, computed without assuming every row is already consistent.
  Future<List<BatchStockCheckRow>> findDiscrepancies() {
    return (select(attachedDatabase.vBatchStockCheck)
          ..where((t) => t.discrepancyMilli.equals(0).not()))
        .get();
  }
}
```

### `lib/data/daos/stock_movement_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/date_key_filters.dart';

/// Typed access to `stock_movements` — the append-only ledger, the second of the app's three
/// (ARCH_1 §3.3).
///
/// **There is no delete method, and none of the update methods can touch `kind` or
/// `quantityMilli`.** This is deliberate at the type level, not by convention: the only mutation
/// this class exposes after insert is [markReversalLinked], which writes nothing but
/// `reversesMovementId` and only via the `Companion`-free [insert] path — there is no
/// `update(_table)` call anywhere in this file. A correction is a new row via [insert] with
/// [StockMovementsCompanion.reversesMovementId] set, summed against the original by
/// `v_batch_stock_check`'s `CASE WHEN kind IN (...)` — never an edit of the row it corrects.
class StockMovementDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  StockMovementDao(super.db);

  $StockMovementsTable get _table => attachedDatabase.stockMovements;

  /// Kinds that increase `remainingQuantityMilli`. Matches `v_batch_stock_check`'s
  /// `CASE WHEN m.kind IN (...)` exactly — kept in sync deliberately, since a repair path and
  /// its reconciliation probe must never disagree about which direction a kind moves stock.
  static const Set<StockMovementKind> incomingKinds = {
    StockMovementKind.openingIn,
    StockMovementKind.purchaseIn,
    StockMovementKind.manualIn,
    StockMovementKind.adjustIn,
  };

  /// The signed quantity [movement] represents: positive for an incoming kind, negative
  /// otherwise. The single place that direction rule is expressed in Dart.
  static int signedQuantityOf({required StockMovementKind kind, required int quantityMilli}) =>
      incomingKinds.contains(kind) ? quantityMilli : -quantityMilli;

  /// Inserts one movement. Callers needing the cache updated too want
  /// `BatchDao.applyMovement`, not this method directly — see that class's doc comment.
  Future<void> insert(StockMovementsCompanion movement) => into(_table).insert(movement);

  /// Emits the movements for [batchId], oldest first — a batch's full history.
  Stream<List<StockMovementRow>> watchForBatch(String batchId) {
    return (select(_table)
          ..where((t) => t.batchId.equals(batchId))
          ..orderBy([(t) => OrderingTerm(expression: t.occurredAt)]))
        .watch();
  }

  /// Reads the movements for [batchId] once, oldest first.
  Future<List<StockMovementRow>> forBatch(String batchId) {
    return (select(_table)
          ..where((t) => t.batchId.equals(batchId))
          ..orderBy([(t) => OrderingTerm(expression: t.occurredAt)]))
        .get();
  }

  /// Emits the movements for [itemId] across all its batches within `[from, to]`, newest first —
  /// the basis for the food-waste analytics in ARCH_3 §5.1 query 14.
  Stream<List<StockMovementRow>> watchForItemInRange({
    required String itemId,
    required DateKey from,
    required DateKey to,
  }) {
    return (select(_table)
          ..where((t) => t.itemId.equals(itemId) & t.dateKey.isInDateRange(from, to))
          ..orderBy([(t) => OrderingTerm(expression: t.occurredAt, mode: OrderingMode.desc)]))
        .watch();
  }

  /// Reads the movements of [kind] for [itemId] within `[from, to]` — used to total waste and
  /// expired quantity separately from ordinary consumption.
  Future<List<StockMovementRow>> forItemByKindInRange({
    required String itemId,
    required StockMovementKind kind,
    required DateKey from,
    required DateKey to,
  }) {
    return (select(_table)
          ..where((t) =>
              t.itemId.equals(itemId) &
              t.kind.equalsValue(kind) &
              t.dateKey.isInDateRange(from, to)))
        .get();
  }

  /// Reads every movement of [kinds] within `[from, to]`, across **all** items.
  ///
  /// The per-item [forItemByKindInRange] cannot answer "what did I waste this month" without the
  /// caller already enumerating every item in the catalogue — which inverts the question, since
  /// the answer is precisely the small set of items that *have* waste. This scans
  /// `idx_move_item_date` over the date range instead and lets the caller group.
  ///
  /// Takes a set of kinds because waste and expiry are distinct events — food thrown out
  /// deliberately versus food that rotted unnoticed — but ARCH_3 §5.1 query 14 counts both as
  /// stock paid for and never used.
  /// Returns an empty list for an empty [kinds] rather than querying — a query matching no kind
  /// would return nothing anyway, and building an always-false predicate is needless SQL.
  Future<List<StockMovementRow>> forKindsInRange({
    required Set<StockMovementKind> kinds,
    required DateKey from,
    required DateKey to,
  }) {
    if (kinds.isEmpty) return Future.value(const []);
    return (select(_table)
          ..where((t) {
            // Folded ORs of `equalsValue` rather than `isInValues`: `kind` carries a type
            // converter, so its SQL type is `String` and `isInValues` would demand the mapped
            // strings. `equalsValue` is the API that compares against the Dart value.
            Expression<bool> kindMatches = t.kind.equalsValue(kinds.first);
            for (final kind in kinds.skip(1)) {
              kindMatches = kindMatches | t.kind.equalsValue(kind);
            }
            return t.dateKey.isInDateRange(from, to) & kindMatches;
          })
          ..orderBy([(t) => OrderingTerm(expression: t.occurredAt)]))
        .get();
  }

  /// Reads one movement by id — for resolving what a reversal points at.
  Future<StockMovementRow?> byId(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads the reversal of [movementId], if one has been recorded.
  Future<StockMovementRow?> reversalOf(String movementId) =>
      (select(_table)..where((t) => t.reversesMovementId.equals(movementId)))
          .getSingleOrNull();
}
```

### `lib/data/repositories/mappers/stock_mappers.dart`

```dart
import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/converters/money_converter.dart';
import 'package:alaya/data/db/converters/qty_converter.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/domain/repositories/batch_repository.dart';

/// Converts between `ItemRow` and the domain `Item` entity.
///
/// An item is the one inventory row that carries its own `unitCategory`, so unlike every other
/// mapper here it needs no category resolution — it *is* the source every other one resolves
/// against.
extension ItemMapper on ItemRow {
  /// Maps this row to a domain entity.
  Item toEntity() => Item(
        id: id,
        name: name,
        normalizedName: normalizedName,
        unitCategory: unitCategory,
        defaultDisplayUnitCode: defaultDisplayUnitCode,
        itemKind: itemKind,
        isFavorite: isFavorite,
        lowStockThreshold: QtyColumns.readOrNull(lowStockThresholdMilli, unitCategory),
        expiryNotifyDays: expiryNotifyDays,
        notes: notes,
      );
}

/// Builds the companion for [item].
ItemsCompanion itemToCompanion(
  Item item, {
  required int createdAt,
  required int updatedAt,
}) {
  return ItemsCompanion.insert(
    id: item.id,
    name: item.name,
    normalizedName: item.normalizedName,
    unitCategory: item.unitCategory,
    defaultDisplayUnitCode: item.defaultDisplayUnitCode,
    itemKind: item.itemKind,
    lowStockThresholdMilli: Value(QtyColumns.milliOfNullable(item.lowStockThreshold)),
    expiryNotifyDays: Value(item.expiryNotifyDays),
    notes: Value(item.notes),
    isFavorite: item.isFavorite,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `InventoryBatchRow` and the domain `Batch` entity.
///
/// Requires [category] explicitly: a batch stores `initialQuantityMilli` and
/// `remainingQuantityMilli` as bare integers, and a `Qty` is meaningless without the
/// [UnitCategory] that says whether those milli-units are grams, millilitres or pieces. The
/// category lives on the owning item, never on the batch (`qty_converter.dart` documents why no
/// drift `TypeConverter` can bridge this).
extension BatchMapper on InventoryBatchRow {
  /// Maps this row to a domain entity, using [category] from the owning item.
  Batch toEntity(UnitCategory category) => Batch(
        id: id,
        itemId: itemId,
        initialQuantity: QtyColumns.read(initialQuantityMilli, category),
        remainingQuantity: QtyColumns.read(remainingQuantityMilli, category),
        unitCodeAtPurchase: unitCodeAtPurchase,
        purchasedDateKey: purchasedDateKey,
        origin: origin,
        expiryDateKey: expiryDateKey,
        unitCost: MoneyColumns.readNullable(unitCostMinor, costCurrencyCode),
        sourceTransactionLineId: sourceTransactionLineId,
        storageLocation: storageLocation,
        note: note,
      );
}

/// Builds the companion for [batch].
InventoryBatchesCompanion batchToCompanion(
  Batch batch, {
  required int createdAt,
  required int updatedAt,
}) {
  return InventoryBatchesCompanion.insert(
    id: batch.id,
    itemId: batch.itemId,
    initialQuantityMilli: QtyColumns.milliOf(batch.initialQuantity),
    remainingQuantityMilli: QtyColumns.milliOf(batch.remainingQuantity),
    unitCodeAtPurchase: batch.unitCodeAtPurchase,
    expiryDateKey: Value(batch.expiryDateKey),
    purchasedDateKey: batch.purchasedDateKey,
    unitCostMinor: Value(MoneyColumns.minorOfNullable(batch.unitCost)),
    costCurrencyCode: Value(MoneyColumns.codeOfNullable(batch.unitCost)),
    sourceTransactionLineId: Value(batch.sourceTransactionLineId),
    origin: batch.origin,
    storageLocation: Value(batch.storageLocation),
    note: Value(batch.note),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `StockMovementRow` and the domain `StockMovement` entity.
///
/// Requires [category] for the same reason [BatchMapper] does. There is deliberately no
/// entity-to-companion direction: `stock_movements` is append-only and the repository builds its
/// companions directly from a consumption plan, so a general reverse mapper would only invite the
/// edit Law L6's exception exists to prevent.
extension StockMovementMapper on StockMovementRow {
  /// Maps this row to a domain entity, using [category] from the owning item.
  StockMovement toEntity(UnitCategory category) => StockMovement(
        id: id,
        batchId: batchId,
        itemId: itemId,
        kind: kind,
        quantity: QtyColumns.read(quantityMilli, category),
        occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(occurredAt, isUtc: true),
        dateKey: dateKey,
        reason: reason,
        note: note,
        linkedTransactionId: linkedTransactionId,
        reversesMovementId: reversesMovementId,
      );
}

/// Converts `ItemStockRow` (from `v_item_stock`) into the domain `ItemStock` entity.
///
/// Needs no external category: the view selects `items.unit_category` directly, so a stock
/// rollup is self-describing.
extension ItemStockMapper on ItemStockRow {
  /// Maps this row to a domain entity.
  ItemStock toEntity() => ItemStock(
        itemId: itemId,
        totalRemaining: QtyColumns.read(totalRemainingMilli, unitCategory),
        batchCount: batchCount,
        isLowStock: isLowStock == 1,
        nearestExpiry: nearestExpiryDateKey,
        lowStockThreshold: QtyColumns.readOrNull(lowStockThresholdMilli, unitCategory),
      );
}

/// Converts `LowStockRow` (from `v_low_stock`) into the domain `ItemStock` entity.
///
/// `v_low_stock` is `v_item_stock` filtered to `is_low_stock = 1` plus a pre-computed shortfall,
/// so every row it yields is low on stock by construction — hence `isLowStock: true` rather than
/// a column read. The shortfall itself is recomputed by [ItemStock.shortfall] from the threshold
/// and remaining quantity rather than carried across, so there is exactly one definition of it.
extension LowStockMapper on LowStockRow {
  /// Maps this row to a domain entity.
  ItemStock toEntity() => ItemStock(
        itemId: itemId,
        totalRemaining: QtyColumns.read(totalRemainingMilli, unitCategory),
        // `v_low_stock` does not select batch_count — a low-stock suggestion needs the shortfall,
        // not how many batches it is spread across. Callers wanting the count read v_item_stock.
        batchCount: 0,
        isLowStock: true,
        nearestExpiry: nearestExpiryDateKey,
        lowStockThreshold: QtyColumns.readOrNull(lowStockThresholdMilli, unitCategory),
      );
}

/// Converts `BatchStockCheckRow` (from `v_batch_stock_check`) into the domain
/// `BatchReconciliation` entity.
///
/// Requires [category] for the same reason [BatchMapper] and [StockMovementMapper] do — all three
/// figures are `Qty`, and `v_batch_stock_check` is batch-centric with no `items` in its `FROM`
/// clause. Adding a join purely to surface `unit_category` would cost a join on a view that scans
/// every batch, when the caller already resolves categories through `ItemCategoryResolver` for the
/// batch and movement rows alongside it.
extension BatchReconciliationMapper on BatchStockCheckRow {
  /// Maps this row to a domain entity, using [category] from the owning item.
  BatchReconciliation toEntity(UnitCategory category) => BatchReconciliation(
        batchId: batchId,
        cached: QtyColumns.read(cachedRemainingMilli, category),
        fromLedger: QtyColumns.read(ledgerRemainingMilli, category),
        discrepancy: QtyColumns.read(discrepancyMilli, category),
      );
}

/// A `Money` total keyed by currency code, accumulated without ever adding across currencies.
///
/// Exists because waste and inventory valuation both sum costs whose currency is per-row
/// (`inventory_batches.cost_currency_code`), and `Money + Money` throws on a mismatch by design
/// (Law L1). Adding rupees to yen is anomaly A34; this makes that impossible rather than merely
/// discouraged.
final class MoneyByCurrency {
  /// Creates an empty accumulator.
  MoneyByCurrency();

  final Map<String, int> _minorByCode = {};

  /// Adds [minor] units of [currencyCode] to the running total.
  void add({required String currencyCode, required int minor}) {
    _minorByCode.update(currencyCode, (existing) => existing + minor, ifAbsent: () => minor);
  }

  /// The accumulated totals, one `Money` per currency encountered.
  Map<String, Money> get totals =>
      {for (final e in _minorByCode.entries) e.key: Money(e.value, e.key)};

  /// True when nothing has been added.
  bool get isEmpty => _minorByCode.isEmpty;
}
```

### `lib/data/repositories/mappers/shopping_mappers.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/converters/money_converter.dart';
import 'package:alaya/data/db/converters/qty_converter.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';

/// Converts between `ShoppingListRow` and the domain `ShoppingList` entity.
extension ShoppingListMapper on ShoppingListRow {
  /// Maps this row to a domain entity.
  ShoppingList toEntity() => ShoppingList(
        id: id,
        name: name,
        isDefault: isDefault,
        isArchived: isArchived,
        targetDateKey: targetDateKey,
      );
}

/// Builds the companion for [list].
ShoppingListsCompanion shoppingListToCompanion(
  ShoppingList list, {
  required int createdAt,
  required int updatedAt,
}) {
  return ShoppingListsCompanion.insert(
    id: list.id,
    name: list.name,
    isDefault: list.isDefault,
    isArchived: list.isArchived,
    targetDateKey: Value(list.targetDateKey),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `ShoppingEntryRow` and the domain `ShoppingEntry` entity.
///
/// [category] is **nullable** here, unlike the batch and movement mappers. A shopping entry may
/// name no item at all — `TV ☐` is a legitimate entry with nothing in the catalogue behind it
/// (anomaly A24) — so there is often no item whose `unitCategory` could be resolved. A null
/// category yields a null `quantity`, which is also the honest outcome for a free-text entry
/// nobody has attached a measurable amount to.
///
/// [homeCurrencyCode] must be supplied because `shopping_entries` carries no currency column
/// (ARCH_2 §6). An estimated price is a guess typed before any transaction exists, so there is no
/// parent row to inherit a currency from the way a `transaction_lines` amount inherits its
/// transaction's. Passing it in rather than assuming one keeps Law L1's pairing honest — a
/// hardcoded default would label a yen estimate as rupees for every user outside India.
extension ShoppingEntryMapper on ShoppingEntryRow {
  /// Maps this row to a domain entity, using [category] from the linked item when there is one.
  ShoppingEntry toEntity({
    required UnitCategory? category,
    required String homeCurrencyCode,
  }) =>
      ShoppingEntry(
        id: id,
        listId: listId,
        origin: origin,
        autoState: autoState,
        isChecked: isChecked,
        sortOrder: sortOrder,
        itemId: itemId,
        freeText: freeText,
        quantity: QtyColumns.readOrNull(quantityMilli, category),
        unitCode: unitCode,
        tagId: tagId,
        // **Not `readNullable`.** That helper enforces a pairing invariant for tables storing an
        // amount *and* its currency, and throws on a half-populated pair. `shopping_entries` stores
        // only `estimated_price_minor`; the currency comes from settings and is therefore always
        // present, so every entry without a price — which is every auto-generated suggestion —
        // arrived as `(null, 'INR')` and threw. The nullability here belongs to the amount alone.
        estimatedPrice: estimatedPriceMinor == null
            ? null
            : Money(estimatedPriceMinor!, homeCurrencyCode),
        checkedAtUtc: checkedAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(checkedAt!, isUtc: true),
        snoozeUntilDateKey: snoozeUntilDateKey,
        stockAtGeneration: QtyColumns.readOrNull(generatedAtStockMilli, category),
        purchasedTransactionLineId: purchasedTransactionLineId,
      );
}

/// Builds the companion for [entry].
ShoppingEntriesCompanion shoppingEntryToCompanion(
  ShoppingEntry entry, {
  required int createdAt,
  required int updatedAt,
}) {
  return ShoppingEntriesCompanion.insert(
    id: entry.id,
    listId: entry.listId,
    itemId: Value(entry.itemId),
    freeText: Value(entry.freeText),
    quantityMilli: Value(QtyColumns.milliOfNullable(entry.quantity)),
    unitCode: Value(entry.unitCode),
    tagId: Value(entry.tagId),
    estimatedPriceMinor: Value(MoneyColumns.minorOfNullable(entry.estimatedPrice)),
    isChecked: entry.isChecked,
    checkedAt: Value(entry.checkedAtUtc?.millisecondsSinceEpoch),
    origin: entry.origin,
    autoState: entry.autoState,
    snoozeUntilDateKey: Value(entry.snoozeUntilDateKey),
    generatedAtStockMilli: Value(QtyColumns.milliOfNullable(entry.stockAtGeneration)),
    purchasedTransactionLineId: Value(entry.purchasedTransactionLineId),
    sortOrder: entry.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
```

### `lib/data/repositories/mappers/money_mappers.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/converters/money_converter.dart';
import 'package:alaya/data/db/converters/qty_converter.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';

/// Converts between `AccountRow` and the domain `Account` entity.
///
/// Uses `MoneyColumns` rather than a drift `TypeConverter` because `Money` spans two sibling
/// columns (`openingBalanceMinor` + the row's own `currencyCode`) — see `money_converter.dart`'s
/// class doc for why no converter can do this.
extension AccountMapper on AccountRow {
  /// Maps this row to a domain entity.
  Account toEntity() => Account(
        id: id,
        name: name,
        normalizedName: normalizedName,
        kind: kind,
        currencyCode: currencyCode,
        openingBalance: MoneyColumns.read(openingBalanceMinor, currencyCode),
        openingBalanceDateKey: openingBalanceDateKey,
        isArchived: isArchived,
        includeInNetWorth: includeInNetWorth,
        sortOrder: sortOrder,
        colorArgb: colorArgb,
        iconKey: iconKey,
      );
}

/// Builds the companion for [account].
AccountsCompanion accountToCompanion(
  Account account, {
  required int createdAt,
  required int updatedAt,
}) {
  return AccountsCompanion.insert(
    id: account.id,
    name: account.name,
    normalizedName: account.normalizedName,
    kind: account.kind,
    currencyCode: account.currencyCode,
    openingBalanceMinor: MoneyColumns.minorOf(account.openingBalance),
    openingBalanceDateKey: account.openingBalanceDateKey,
    isArchived: account.isArchived,
    includeInNetWorth: account.includeInNetWorth,
    sortOrder: account.sortOrder,
    colorArgb: Value(account.colorArgb),
    iconKey: Value(account.iconKey),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `PaymentMethodRow` and the domain `PaymentMethod` entity.
extension PaymentMethodMapper on PaymentMethodRow {
  /// Maps this row to a domain entity.
  PaymentMethod toEntity() => PaymentMethod(
        id: id,
        name: name,
        kind: kind,
        isSystem: isSystem,
        sortOrder: sortOrder,
      );
}

/// Builds the companion for [method].
PaymentMethodsCompanion paymentMethodToCompanion(
  PaymentMethod method, {
  required int createdAt,
  required int updatedAt,
}) {
  return PaymentMethodsCompanion.insert(
    id: method.id,
    name: method.name,
    kind: method.kind,
    isSystem: method.isSystem,
    sortOrder: method.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `PayeeRow` and the domain `Payee` entity.
extension PayeeMapper on PayeeRow {
  /// Maps this row to a domain entity.
  Payee toEntity() => Payee(
        id: id,
        name: name,
        normalizedName: normalizedName,
        kind: kind,
        phone: phone,
        note: note,
      );
}

/// Builds the companion for [payee].
PayeesCompanion payeeToCompanion(
  Payee payee, {
  required int createdAt,
  required int updatedAt,
}) {
  return PayeesCompanion.insert(
    id: payee.id,
    name: payee.name,
    normalizedName: payee.normalizedName,
    kind: payee.kind,
    phone: Value(payee.phone),
    note: Value(payee.note),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts `ActiveTransactionRow` (from `v_active_transactions`, what every read method on
/// `TransactionDao` returns) into the domain `Transaction` entity.
///
/// Not `TransactionRow` — no read path in `TransactionDao` ever returns one; every method reads
/// the view, per Law L7. The view aliases the primary key as `tx_id` (so `Transaction` and
/// `TransactionLine` share the unqualified name `id` in a join), which is why this reads
/// [ActiveTransactionRow.txId] rather than `.id`.
///
/// The view originally omitted `conversionRate`, `conversionRateRaw`, `conversionDateKey`,
/// `createdAt` and `updatedAt` — only enough columns to render a list, not enough to fully
/// reconstruct a row. The first three would have silently dropped the rate and date behind
/// every frozen conversion; the last two are why `TransactionRepositoryImpl.update` could not
/// preserve a transaction's true creation time on edit. Fixed by adding all five to
/// `transaction_views.drift` in this phase; see the phase report. `createdAt`/`updatedAt` are
/// read directly off [ActiveTransactionRow] by the repository for that bookkeeping — [toEntity]
/// itself still ignores them, since `Transaction` carries no persistence timestamps.
extension ActiveTransactionMapper on ActiveTransactionRow {
  /// Maps this row to a domain entity.
  Transaction toEntity() {
    final hasFreeze = convertedAmountMinor != null;
    return Transaction(
      id: txId,
      kind: kind,
      subtype: subtype,
      occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(occurredAt, isUtc: true),
      dateKey: dateKey,
      originalAmount: MoneyColumns.read(originalAmountMinor, originalCurrencyCode),
      needsReview: needsReview,
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      paymentMethodId: paymentMethodId,
      payeeId: payeeId,
      note: note,
      recurringTemplateId: recurringTemplateId,
      recurringOccurrenceId: recurringOccurrenceId,
      frozenConversion: hasFreeze
          ? MoneyColumns.read(convertedAmountMinor!, convertedCurrencyCode!)
          : null,
      frozenConversionRate: hasFreeze ? conversionRate : null,
      frozenConversionRateRaw: hasFreeze ? conversionRateRaw : null,
      frozenConversionDateKey: hasFreeze ? conversionDateKey : null,
    );
  }
}

/// Builds the companion for [transaction].
///
/// [monthKey] is a required parameter here, not derived inside this function — deriving it in a
/// mapper that only ever runs after the repository has already validated and computed it would
/// invite a second, possibly-inconsistent derivation. `TransactionRepositoryImpl.create` and
/// `.update` are the one place `monthKey` is computed, from `dateKey.monthKey`.
TransactionsCompanion transactionToCompanion(
  Transaction transaction, {
  required int monthKey,
  required int createdAt,
  required int updatedAt,
}) {
  return TransactionsCompanion.insert(
    id: transaction.id,
    kind: transaction.kind,
    subtype: transaction.subtype,
    occurredAt: transaction.occurredAtUtc.millisecondsSinceEpoch,
    dateKey: transaction.dateKey,
    monthKey: monthKey,
    originalAmountMinor: MoneyColumns.minorOf(transaction.originalAmount),
    originalCurrencyCode: MoneyColumns.codeOf(transaction.originalAmount),
    fromAccountId: Value(transaction.fromAccountId),
    toAccountId: Value(transaction.toAccountId),
    paymentMethodId: Value(transaction.paymentMethodId),
    payeeId: Value(transaction.payeeId),
    note: Value(transaction.note),
    needsReview: transaction.needsReview,
    recurringTemplateId: Value(transaction.recurringTemplateId),
    recurringOccurrenceId: Value(transaction.recurringOccurrenceId),
    convertedAmountMinor: Value(MoneyColumns.minorOfNullable(transaction.frozenConversion)),
    convertedCurrencyCode: Value(MoneyColumns.codeOfNullable(transaction.frozenConversion)),
    conversionRate: Value(transaction.frozenConversionRate),
    conversionRateRaw: Value(transaction.frozenConversionRateRaw),
    conversionDateKey: Value(transaction.frozenConversionDateKey),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `TransactionLineRow` and the domain `TransactionLine` entity.
///
/// `transaction_lines` carries no currency column of its own (ARCH_2 §4.2) — every amount on a
/// line is implicitly in its parent transaction's currency. [toEntity] therefore requires
/// [transactionCurrencyCode] explicitly; there is no way to construct a correct
/// [TransactionLine.unitPrice] or [TransactionLine.lineAmount] from this row alone.
///
/// [categoryResolver] supplies the [UnitCategory] a `quantity` needs but this row does not carry
/// directly — looking up [TransactionLineRow.itemId]'s category, or [TransactionLineRow.unitCode]'s
/// when there is no item, exactly as `qty_converter.dart`'s class doc describes. Returns null from
/// the resolver when neither is available, in which case the mapped line's `quantity` is null too.
extension TransactionLineMapper on TransactionLineRow {
  /// Maps this row to a domain entity.
  TransactionLine toEntity({
    required String transactionCurrencyCode,
    required UnitCategory? Function(TransactionLineRow row) categoryResolver,
  }) {
    final category = categoryResolver(this);
    return TransactionLine(
      id: id,
      transactionId: transactionId,
      lineNo: lineNo,
      description: description,
      destination: destination,
      itemId: itemId,
      quantity: QtyColumns.readOrNull(quantityMilli, category),
      unitCode: unitCode,
      // `readNullable` enforces a pairing invariant — both null or both present — and throws on a
      // half-populated pair. It is right only where the currency is a nullable column written and
      // cleared with its own amount. Here the currency is always present, so a null amount is a
      // legitimate absence rather than a broken pair, and the nullability belongs to the amount.
      //
      // `transactionCurrencyCode` is a `required String` from the parent transaction, so every line
      // without a unit price — which is every line a shopping list produces — threw, and the detail
      // screen showed "that did not work" instead of the items.
      unitPrice: unitPriceMinor == null
          ? null
          : Money(unitPriceMinor!, transactionCurrencyCode),
      lineAmount: lineAmountMinor == null
          ? null
          : Money(lineAmountMinor!, transactionCurrencyCode),
      createdBatchId: createdBatchId,
      createdAssetId: createdAssetId,
      createdRecurringTemplateId: createdRecurringTemplateId,
      note: note,
    );
  }
}

/// Builds the companion for [line].
TransactionLinesCompanion transactionLineToCompanion(
  TransactionLine line, {
  required int createdAt,
  required int updatedAt,
}) {
  return TransactionLinesCompanion.insert(
    id: line.id,
    transactionId: line.transactionId,
    lineNo: line.lineNo,
    description: line.description,
    destination: line.destination,
    itemId: Value(line.itemId),
    quantityMilli: Value(QtyColumns.milliOfNullable(line.quantity)),
    unitCode: Value(line.unitCode),
    unitPriceMinor: Value(MoneyColumns.minorOfNullable(line.unitPrice)),
    lineAmountMinor: Value(MoneyColumns.minorOfNullable(line.lineAmount)),
    createdBatchId: Value(line.createdBatchId),
    createdAssetId: Value(line.createdAssetId),
    createdRecurringTemplateId: Value(line.createdRecurringTemplateId),
    note: Value(line.note),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
```

### `lib/data/repositories/item_repository_impl.dart`

```dart
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/item_dao.dart';
import 'package:alaya/data/repositories/mappers/stock_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/repositories/item_repository.dart';

/// How far apart two normalized names may be and still be offered as the same thing.
///
/// Two edits, per anomaly A07's resolution. Deliberately permissive on short names — `tea` and
/// `pea` are one edit apart — which is safe only because these are *suggestions the user confirms*
/// and never an automatic merge. Raising the bar would lose real near-misses like
/// `tomato`/`tomatto`; lowering it to scale with length would silently stop catching typos in
/// short names, which are exactly where typos are most likely.
const int _maxSuggestionDistance = 2;

/// `ItemRepository` backed by `ItemDao`.
final class ItemRepositoryImpl implements ItemRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const ItemRepositoryImpl(this._dao, this._clock);

  final ItemDao _dao;
  final Clock _clock;

  @override
  Stream<List<Item>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Item>> watchByCategory(UnitCategory category) =>
      _dao.watchByCategory(category).map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Item>> watchFavorites() =>
      _dao.watchFavorites().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Item>> watchMatching(String term) =>
      _dao.watchMatching(term).map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Item?> byId(String id) async => (await _dao.byIdIncludingDeleted(id))?.toEntity();

  @override
  Future<Item?> findByIdentity({
    required String normalizedName,
    required UnitCategory unitCategory,
  }) async {
    final row = await _dao.findByIdentity(
      normalizedName: normalizedName,
      unitCategory: unitCategory,
    );
    return row?.toEntity();
  }

  @override
  Future<List<Item>> findSimilar({
    required String name,
    required UnitCategory unitCategory,
  }) async {
    // Same category only. A different category is a different item by definition (Law L8,
    // anomaly A06) — `Milk (Weight)` is not a near-miss for `Milk (Volume)`, it is a separate
    // thing — so suggesting across categories would invite exactly the merge the schema forbids.
    final candidates = await _dao.watchByCategory(unitCategory).first;

    final scored = <({Item item, int distance})>[];
    for (final row in candidates) {
      final candidate = row.normalizedName;
      // Cheap pre-filter: a length difference greater than the threshold guarantees the edit
      // distance exceeds it too, since each edit changes length by at most one. Verified over
      // 4000 random pairs never to exclude a genuine match.
      if ((candidate.length - name.length).abs() > _maxSuggestionDistance) continue;

      final distance = _levenshtein(candidate, name);
      // Distance 0 is the exact identity match, which is [findByIdentity]'s job — a merge, not a
      // suggestion. Including it here would offer the user "did you mean this same item?".
      if (distance == 0 || distance > _maxSuggestionDistance) continue;

      scored.add((item: row.toEntity(), distance: distance));
    }

    scored.sort((a, b) {
      final byDistance = a.distance.compareTo(b.distance);
      return byDistance != 0
          ? byDistance
          : a.item.normalizedName.compareTo(b.item.normalizedName);
    });
    return scored.map((s) => s.item).toList();
  }

  @override
  Stream<List<ItemStock>> watchAllStock() =>
      _dao.watchAllStock().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<ItemStock?> watchStockOf(String itemId) =>
      _dao.watchStockOf(itemId).map((row) => row?.toEntity());

  @override
  Stream<List<ItemStock>> watchLowStock() =>
      _dao.watchLowStock().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<Item, Failure>> save(Item item) async {
    final existing = await _dao.byIdIncludingDeleted(item.id);

    if (existing == null) {
      // A new item may not collide with an existing active identity. The partial unique index
      // would reject it anyway; catching it here turns a raw SQLite constraint error into a
      // failure the UI can act on ("add to the existing item instead?").
      final duplicate = await _dao.findByIdentity(
        normalizedName: item.normalizedName,
        unitCategory: item.unitCategory,
      );
      if (duplicate != null) {
        return Result.failure(
          ConflictFailure(
            'An item named "${item.name}" already exists in this category. '
            'Add a new batch to it instead of creating a second item.',
          ),
        );
      }
    } else if (existing.unitCategory != item.unitCategory) {
      // Law L8. Changing an item's category would silently reinterpret every quantity ever
      // recorded against it — 2000 milli-units stops meaning 2 g and starts meaning 2 ml, across
      // every batch, movement and transaction line already written. There is no migration that
      // fixes that after the fact, so the write is refused rather than attempted.
      return Result.failure(
        BusinessRuleFailure(
          'An item\'s unit category cannot be changed once it exists — every quantity already '
          'recorded against "${existing.name}" is measured in '
          '${existing.unitCategory.baseUnitCode}. Create a separate item instead.',
          rule: 'unitCategoryImmutable',
        ),
      );
    }

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _dao.upsert(
      itemToCompanion(item, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );
    return Result.ok(item);
  }

  @override
  Future<Result<void, Failure>> setFavorite({
    required String id,
    required bool isFavorite,
  }) async {
    await _dao.setFavorite(
      id: id,
      isFavorite: isFavorite,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    // Cascades to the item's batches inside one transaction, in the DAO. Movements are untouched:
    // the ledger for food that no longer has a catalogued item stays exactly as complete as it was
    // (Law L6's stated exception).
    await _dao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }
}

/// Levenshtein edit distance between [a] and [b].
///
/// Two-row implementation: only the previous and current rows of the distance matrix are ever
/// live, so memory is `O(min(len))` rather than `O(len × len)`. Called once per same-category
/// candidate that survives the length pre-filter, on strings that are item names — short enough
/// that this is far cheaper than a second database round trip would be.
int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previous = List<int>.generate(b.length + 1, (i) => i);
  var current = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final substitution = previous[j - 1] + (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1);
      final deletion = previous[j] + 1;
      final insertion = current[j - 1] + 1;
      current[j] = substitution < deletion
          ? (substitution < insertion ? substitution : insertion)
          : (deletion < insertion ? deletion : insertion);
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}
```

### `lib/data/repositories/batch_repository_impl.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/batch_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/item_category_resolver.dart';
import 'package:alaya/data/repositories/mappers/stock_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/repositories/batch_repository.dart';

/// `BatchRepository` backed by `BatchDao`.
final class BatchRepositoryImpl implements BatchRepository {
  /// Creates the repository over [dao], resolving item categories through [categories].
  const BatchRepositoryImpl(this._dao, this._categories, this._clock);

  final BatchDao _dao;
  final ItemCategoryResolver _categories;
  final Clock _clock;

  @override
  Stream<List<Batch>> watchByItemFefo(String itemId) =>
      _dao.watchByItemFefo(itemId).asyncMap((rows) => _mapAll(rows));

  @override
  Future<List<Batch>> byItemFefo(String itemId) async =>
      _mapAll(await _dao.byItemFefo(itemId));

  @override
  Stream<List<Batch>> watchByItem(String itemId) =>
      _dao.watchByItem(itemId).asyncMap((rows) => _mapAll(rows));

  @override
  Stream<List<Batch>> watchExpiringInRange({
    required DateKey from,
    required DateKey to,
  }) =>
      _dao.watchExpiringInRange(from: from, to: to).asyncMap((rows) => _mapAll(rows));

  @override
  Future<Batch?> byId(String id) async {
    final row = await _dao.byIdIncludingDeleted(id);
    if (row == null) return null;
    final category = await _categories.categoryOf(row.itemId);
    if (category == null) return null;
    return row.toEntity(category);
  }

  @override
  Future<Result<Batch, Failure>> create(Batch batch) async {
    if (!batch.initialQuantity.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'A new batch needs a quantity greater than zero.',
          field: 'initialQuantity',
        ),
      );
    }
    if (batch.remainingQuantity != batch.initialQuantity) {
      // BatchDao.insertWithOpeningMovement's documented caller contract: nothing has been consumed
      // yet, so the two cannot differ. Enforced here rather than trusted, because the founding
      // movement it writes uses `initialQuantityMilli` — a mismatch would make the batch a
      // permanent discrepancy in `v_batch_stock_check` from the moment it was created.
      return const Result.failure(
        ValidationFailure(
          'A new batch must have its full quantity remaining.',
          field: 'remainingQuantity',
        ),
      );
    }

    final category = await _categories.categoryOf(batch.itemId);
    if (category == null) {
      return Result.failure(
        NotFoundFailure('The item this batch belongs to does not exist.', id: batch.itemId),
      );
    }
    if (category != batch.initialQuantity.category) {
      // A `Qty` in the wrong category would be stored as a bare integer and silently reinterpreted
      // on read as the item's own category — 2 pieces becoming 2 grams. Law L8 makes this
      // impossible to fix afterwards, so it is refused now.
      return Result.failure(
        ValidationFailure(
          'This batch is measured in ${batch.initialQuantity.category.name} but its item is '
          'measured in ${category.name}.',
          field: 'initialQuantity',
        ),
      );
    }

    final now = _clock.nowUtcMillis();
    await _dao.insertWithOpeningMovement(
      batch: batchToCompanion(batch, createdAt: now, updatedAt: now),
      // `purchaseIn` when the batch came from a transaction line, `manualIn` when the user added
      // it directly. The repository's call to make, as the DAO's doc notes.
      openingKind: batch.sourceTransactionLineId != null
          ? StockMovementKind.purchaseIn
          : StockMovementKind.manualIn,
      nowUtcMillis: now,
    );
    return Result.ok(batch);
  }

  @override
  Future<Result<Batch, Failure>> updateMetadata(Batch batch) async {
    final existing = await _dao.byIdIncludingDeleted(batch.id);
    if (existing == null) {
      return Result.failure(NotFoundFailure('Batch not found.', id: batch.id));
    }
    if (existing.remainingQuantityMilli != batch.remainingQuantity.milliBase ||
        existing.initialQuantityMilli != batch.initialQuantity.milliBase) {
      // Quantities move only by recording a movement, so that the ledger and the cache can never
      // disagree (Law L3). A metadata update that also changed a quantity would write the cache
      // with no matching movement — exactly the drift `v_batch_stock_check` exists to detect.
      return const Result.failure(
        BusinessRuleFailure(
          'A batch\'s quantity cannot be changed here — record a stock movement instead.',
          rule: 'quantityRequiresMovement',
        ),
      );
    }

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing.createdAt,
      clock: _clock,
    );
    await _dao.updateMetadata(
      batchToCompanion(batch, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );
    return Result.ok(batch);
  }

  @override
  Future<Result<void, Failure>> detachFromDeletedTransaction(String batchId) async {
    await _dao.detachFromDeletedTransaction(
      batchId: batchId,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    await _dao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Stream<List<BatchReconciliation>> watchReconciliation() =>
      _dao.watchReconciliation().asyncMap(_mapReconciliations);

  @override
  Future<List<BatchReconciliation>> findDiscrepancies() async =>
      _mapReconciliations(await _dao.findDiscrepancies());

  @override
  Future<Result<void, Failure>> recompute(String batchId) async {
    await _dao.recomputeRemaining(batchId);
    return const Result.ok(null);
  }

  @override
  Future<Result<int, Failure>> recomputeAll() async {
    // Counted before repairing, not after: once every cache is rebuilt there are no discrepancies
    // left to count, so asking afterwards would always return zero and report that nothing was
    // wrong. The figure the Settings screen wants is how many were broken.
    final broken = await _dao.findDiscrepancies();
    await _dao.recomputeAll();
    return Result.ok(broken.length);
  }

  Future<List<BatchReconciliation>> _mapReconciliations(List<BatchStockCheckRow> rows) async {
    final categories = await _categories.categoriesFor(rows.map((r) => r.itemId));
    return rows
        .where((r) => categories.containsKey(r.itemId))
        .map((r) => r.toEntity(categories[r.itemId]!))
        .toList();
  }

  Future<List<Batch>> _mapAll(List<InventoryBatchRow> rows) async {
    final categories = await _categories.categoriesFor(rows.map((r) => r.itemId));
    return rows
        .where((r) => categories.containsKey(r.itemId))
        .map((r) => r.toEntity(categories[r.itemId]!))
        .toList();
  }
}
```

### `lib/data/repositories/stock_repository_impl.dart`

```dart
import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_formatter.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/batch_dao.dart';
import 'package:alaya/data/daos/stock_movement_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/item_category_resolver.dart';
import 'package:alaya/data/repositories/mappers/stock_mappers.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/domain/repositories/stock_repository.dart';

/// `StockRepository` backed by `BatchDao` and `StockMovementDao`.
///
/// Every write here goes through [BatchDao.applyMovements], which pairs each movement with its
/// batch's cache update inside one transaction (Laws L3, L14). There is no path that records a
/// movement without updating the cache, or the reverse.
final class StockRepositoryImpl implements StockRepository {
  /// Creates the repository.
  const StockRepositoryImpl(
    this._batchDao,
    this._movementDao,
    this._categories,
    this._uids,
    this._clock,
  );

  final BatchDao _batchDao;
  final StockMovementDao _movementDao;
  final ItemCategoryResolver _categories;
  final UidGenerator _uids;
  final Clock _clock;

  /// Formats quantities for the user-facing text on a failure. `Qty.toString()` is a debug
  /// representation (`2500000m(weight)`) and its own doc says never to show it — these messages are
  /// read by a person, so they go through the formatter.
  static const QtyFormatter _qtyFormat = QtyFormatter();

  @override
  Future<Result<List<ConsumptionDraw>, Failure>> consume({
    required String itemId,
    required Qty quantity,
    required StockMovementKind kind,
    String? reason,
    String? note,
  }) async {
    if (!quantity.isPositive) {
      return const Result.failure(
        ValidationFailure('The quantity to consume must be greater than zero.', field: 'quantity'),
      );
    }

    final category = await _categories.categoryOf(itemId);
    if (category == null) {
      return Result.failure(NotFoundFailure('Item not found.', id: itemId));
    }
    if (category != quantity.category) {
      return Result.failure(
        ValidationFailure(
          'This item is measured in ${category.name}, not ${quantity.category.name}.',
          field: 'quantity',
        ),
      );
    }

    // FEFO order, already filtered to batches holding stock: nearest expiry first, undated last
    // (anomaly A08). The DAO owns that ordering so it is expressed once, in SQL, where the index
    // can serve it.
    final batches = await _batchDao.byItemFefo(itemId);
    final available = batches.fold<int>(0, (sum, b) => sum + b.remainingQuantityMilli);

    if (available < quantity.milliBase) {
      // Checked before any write, and nothing is written on this path. A partial consumption would
      // leave the ledger describing something that did not happen — worse than refusing, because
      // the user would have no way to tell how much actually came out.
      return Result.failure(
        BusinessRuleFailure(
          'Only ${_qtyFormat.format(Qty(available, category))} is on hand, less than the '
          '${_qtyFormat.format(quantity)} requested.',
          rule: 'insufficientStock',
        ),
      );
    }

    final plan = _planDraws(
      batches: batches,
      needed: quantity.milliBase,
      category: category,
    );
    await _applyDraws(
      itemId: itemId,
      draws: plan,
      kind: kind,
      reason: reason,
      note: note,
    );
    return Result.ok(plan);
  }

  @override
  Future<Result<void, Failure>> consumeFromBatch({
    required String batchId,
    required Qty quantity,
    required StockMovementKind kind,
    String? reason,
    String? note,
  }) async {
    if (!quantity.isPositive) {
      return const Result.failure(
        ValidationFailure('The quantity to consume must be greater than zero.', field: 'quantity'),
      );
    }

    final batch = await _batchDao.byIdIncludingDeleted(batchId);
    if (batch == null) {
      return Result.failure(NotFoundFailure('Batch not found.', id: batchId));
    }
    final category = await _categories.categoryOf(batch.itemId);
    if (category == null) {
      return Result.failure(NotFoundFailure('Item not found.', id: batch.itemId));
    }
    if (category != quantity.category) {
      return Result.failure(
        ValidationFailure(
          'This batch is measured in ${category.name}, not ${quantity.category.name}.',
          field: 'quantity',
        ),
      );
    }
    if (batch.remainingQuantityMilli < quantity.milliBase) {
      return Result.failure(
        BusinessRuleFailure(
          'This batch holds only '
          '${_qtyFormat.format(Qty(batch.remainingQuantityMilli, category))}, less than the '
          '${_qtyFormat.format(quantity)} requested.',
          rule: 'insufficientStock',
        ),
      );
    }

    await _applyDraws(
      itemId: batch.itemId,
      draws: [ConsumptionDraw(batchId: batchId, quantity: quantity)],
      kind: kind,
      reason: reason,
      note: note,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> addStock({
    required String batchId,
    required Qty quantity,
    required StockMovementKind kind,
    String? note,
  }) async {
    if (!quantity.isPositive) {
      return const Result.failure(
        ValidationFailure('The quantity to add must be greater than zero.', field: 'quantity'),
      );
    }
    if (!StockMovementDao.incomingKinds.contains(kind)) {
      // Guarding the direction rather than trusting it: an outgoing kind passed here would reduce
      // stock while the caller believed it was adding, and the cache would faithfully follow.
      return Result.failure(
        ValidationFailure(
          '${kind.name} removes stock rather than adding it.',
          field: 'kind',
        ),
      );
    }

    final batch = await _batchDao.byIdIncludingDeleted(batchId);
    if (batch == null) {
      return Result.failure(NotFoundFailure('Batch not found.', id: batchId));
    }
    final category = await _categories.categoryOf(batch.itemId);
    if (category == null) {
      return Result.failure(NotFoundFailure('Item not found.', id: batch.itemId));
    }
    if (category != quantity.category) {
      return Result.failure(
        ValidationFailure(
          'This batch is measured in ${category.name}, not ${quantity.category.name}.',
          field: 'quantity',
        ),
      );
    }

    await _applyDraws(
      itemId: batch.itemId,
      draws: [ConsumptionDraw(batchId: batchId, quantity: quantity)],
      kind: kind,
      note: note,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> reverse({
    required String movementId,
    String? reason,
  }) async {
    final original = await _movementDao.byId(movementId);
    if (original == null) {
      return Result.failure(NotFoundFailure('Movement not found.', id: movementId));
    }

    final alreadyReversed = await _movementDao.reversalOf(movementId);
    if (alreadyReversed != null) {
      return const Result.failure(
        BusinessRuleFailure(
          'This movement has already been reversed.',
          rule: 'alreadyReversed',
        ),
      );
    }
    if (original.reversesMovementId != null) {
      // Reversing a reversal would be indistinguishable from re-applying the original, and would
      // let a chain build up that nothing can interpret. Undo is one level deep by design.
      return const Result.failure(
        BusinessRuleFailure(
          'A correction cannot itself be reversed — record a new movement instead.',
          rule: 'cannotReverseAReversal',
        ),
      );
    }

    // The compensating kind, chosen so the pair nets to zero under the same direction rule
    // `v_batch_stock_check` applies: an incoming movement is undone by an adjustOut and vice versa.
    final compensating = StockMovementDao.incomingKinds.contains(original.kind)
        ? StockMovementKind.adjustOut
        : StockMovementKind.adjustIn;

    final now = _clock.nowUtcMillis();
    await _batchDao.applyMovements(
      entries: [
        (
          batchId: original.batchId,
          movement: StockMovementsCompanion.insert(
            id: _uids.generate(),
            batchId: original.batchId,
            itemId: original.itemId,
            kind: compensating,
            quantityMilli: original.quantityMilli,
            occurredAt: now,
            dateKey: _clock.today(),
            reason: Value(reason),
            reversesMovementId: Value(movementId),
            createdAt: now,
            updatedAt: now,
          ),
        ),
      ],
      nowUtcMillis: now,
    );
    return const Result.ok(null);
  }

  @override
  Stream<List<StockMovement>> watchForBatch(String batchId) {
    return _movementDao.watchForBatch(batchId).asyncMap(_mapAll);
  }

  @override
  Stream<List<StockMovement>> watchForItemInRange({
    required String itemId,
    required DateKey from,
    required DateKey to,
  }) {
    return _movementDao
        .watchForItemInRange(itemId: itemId, from: from, to: to)
        .asyncMap(_mapAll);
  }

  @override
  Future<List<WasteTotal>> wasteTotals({
    required DateKey from,
    required DateKey to,
  }) async {
    // Both waste kinds, totalled separately per item. `expired` and `waste` are distinct events —
    // food that rotted unnoticed versus food thrown out deliberately — but both are stock that was
    // paid for and never used, which is what ARCH_3 §5.1 query 14 measures.
    final byItem = <String, ({int milli, MoneyByCurrency cost})>{};

    // One query across all items, both waste kinds. Asking per item would require the caller to
    // already know which items have waste — inverting the question, since that set is the answer.
    final movements = await _movementDao.forKindsInRange(
      kinds: const {StockMovementKind.waste, StockMovementKind.expired},
      from: from,
      to: to,
    );

    // Batch costs are cached: a single wasted item is typically spread over few batches, and
    // re-reading the same batch row once per movement would dominate the cost of this query.
    final batchCosts = <String, ({int? unitCostMinor, String? currencyCode})>{};

    for (final m in movements) {
      final entry = byItem.putIfAbsent(m.itemId, () => (milli: 0, cost: MoneyByCurrency()));
      byItem[m.itemId] = (milli: entry.milli + m.quantityMilli, cost: entry.cost);

      final cost = batchCosts[m.batchId] ??= await () async {
        final batch = await _batchDao.byIdIncludingDeleted(m.batchId);
        return (unitCostMinor: batch?.unitCostMinor, currencyCode: batch?.costCurrencyCode);
      }();

      final unitCost = cost.unitCostMinor;
      final costCode = cost.currencyCode;
      if (unitCost != null && costCode != null) {
        entry.cost.add(
          currencyCode: costCode,
          // unitCost is per purchased unit; the movement is in base-milli units, so the wasted
          // money is unitCost x (milli / 1000). Truncated: a fraction of a minor unit cannot be
          // represented, and waste valuation is an estimate rather than a ledger figure.
          minor: (unitCost * m.quantityMilli / 1000).truncate(),
        );
      }
    }

    final result = <WasteTotal>[];
    for (final e in byItem.entries) {
      final category = await _categories.categoryOf(e.key);
      if (category == null) continue;
      result.add(
        WasteTotal(
          itemId: e.key,
          quantity: Qty(e.value.milli, category),
          costByCurrency: e.value.cost.totals,
        ),
      );
    }
    return result;
  }

  /// Delegates FEFO planning to [InventoryConsumptionService].
  ///
  /// This method used to implement the ordering and draw-down itself. Phase 4B moved the algorithm
  /// into the service so there is one definition of it — the same consolidation Phase 4A made for
  /// the currency cross-rate, and for the same reason: two copies of an ordering rule drift apart.
  /// What stays here is the part only a repository can do — writing every draw in one transaction.
  List<ConsumptionDraw> _planDraws({
    required List<InventoryBatchRow> batches,
    required int needed,
    required UnitCategory category,
  }) {
    const service = InventoryConsumptionService();
    final plan = service.plan(
      batches: batches.map(
        (row) => ConsumableBatch(
          batchId: row.id,
          remaining: Qty(row.remainingQuantityMilli, category),
          purchasedDateKey: row.purchasedDateKey,
          expiryDateKey: row.expiryDateKey,
        ),
      ),
      needed: Qty(needed, category),
    );
    // Insufficiency is already checked by the caller before this runs, so a failure here would mean
    // the two disagreed — return no draws rather than a partial set either way.
    return plan.valueOrNull?.draws ?? const [];
  }

  /// Records one movement per draw, all in a single transaction (Law L14).
  Future<void> _applyDraws({
    required String itemId,
    required List<ConsumptionDraw> draws,
    required StockMovementKind kind,
    String? reason,
    String? note,
  }) {
    final now = _clock.nowUtcMillis();
    final today = _clock.today();
    return _batchDao.applyMovements(
      entries: draws
          .map(
            (draw) => (
              batchId: draw.batchId,
              movement: StockMovementsCompanion.insert(
                id: _uids.generate(),
                batchId: draw.batchId,
                itemId: itemId,
                kind: kind,
                quantityMilli: draw.quantity.milliBase,
                occurredAt: now,
                dateKey: today,
                reason: Value(reason),
                note: Value(note),
                createdAt: now,
                updatedAt: now,
              ),
            ),
          )
          .toList(),
      nowUtcMillis: now,
    );
  }

  Future<List<StockMovement>> _mapAll(List<StockMovementRow> rows) async {
    final categories = await _categories.categoriesFor(rows.map((r) => r.itemId));
    return rows
        .where((r) => categories.containsKey(r.itemId))
        .map((r) => r.toEntity(categories[r.itemId]!))
        .toList();
  }
}
```

### `lib/data/repositories/shopping_repository_impl.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/item_dao.dart';
import 'package:alaya/data/daos/shopping_entry_dao.dart';
import 'package:alaya/data/daos/shopping_list_dao.dart';
import 'package:alaya/data/daos/transaction_line_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/item_category_resolver.dart';
import 'package:alaya/data/repositories/mappers/shopping_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/repositories/shopping_repository.dart';

/// `ShoppingRepository` backed by `ShoppingListDao` and `ShoppingEntryDao`.
final class ShoppingRepositoryImpl implements ShoppingRepository {
  /// Creates the repository.
  const ShoppingRepositoryImpl(
    this._listDao,
    this._entryDao,
    this._itemDao,
    this._lineDao,
    this._categories,
    this._settings,
    this._uids,
    this._clock,
  );

  final ShoppingListDao _listDao;
  final ShoppingEntryDao _entryDao;
  final ItemDao _itemDao;
  final TransactionLineDao _lineDao;
  final ItemCategoryResolver _categories;
  final SettingsRepository _settings;
  final UidGenerator _uids;
  final Clock _clock;

  // ── lists ─────────────────────────────────────────────────────────────────────────────

  @override
  Stream<List<ShoppingList>> watchSelectableLists() =>
      _listDao.watchSelectable().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<ShoppingList>> watchAllLists() =>
      _listDao.watchAllIncludingArchived().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<ShoppingList?> watchDefaultList() =>
      _listDao.watchDefault().map((row) => row?.toEntity());

  @override
  Future<ShoppingList?> listById(String id) async =>
      (await _listDao.byIdIncludingDeleted(id))?.toEntity();

  @override
  Future<Result<ShoppingList, Failure>> saveList(ShoppingList list) async {
    if (list.name.trim().isEmpty) {
      return const Result.failure(
        ValidationFailure('A shopping list needs a name.', field: 'name'),
      );
    }

    final existing = await _listDao.byIdIncludingDeleted(list.id);
    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _listDao.upsert(
      shoppingListToCompanion(list, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );

    // `isDefault` carries no database-level uniqueness constraint, so setting it through a plain
    // upsert would leave two lists flagged. The DAO's setDefault clears every other list's flag in
    // the same transaction; routing through it keeps "exactly one default" true in practice.
    if (list.isDefault && existing?.isDefault != true) {
      await _listDao.setDefault(id: list.id, nowUtcMillis: stamps.updatedAt);
    }
    return Result.ok(list);
  }

  @override
  Future<Result<void, Failure>> setDefaultList(String id) async {
    final list = await _listDao.byIdIncludingDeleted(id);
    if (list == null || list.deletedAt != null) {
      return Result.failure(NotFoundFailure('Shopping list not found.', id: id));
    }
    if (list.isArchived) {
      return const Result.failure(
        BusinessRuleFailure(
          'An archived list cannot be the default — unarchive it first.',
          rule: 'archivedCannotBeDefault',
        ),
      );
    }
    await _listDao.setDefault(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> setListArchived({
    required String id,
    required bool isArchived,
  }) async {
    final list = await _listDao.byIdIncludingDeleted(id);
    if (list == null || list.deletedAt != null) {
      return Result.failure(NotFoundFailure('Shopping list not found.', id: id));
    }
    if (isArchived && list.isDefault) {
      // Archiving the default would leave quick-add with nowhere to write, silently. Refusing
      // makes the user pick a new default first, which is the decision they actually need to make.
      return const Result.failure(
        BusinessRuleFailure(
          'This is the default list. Make another list the default before archiving it.',
          rule: 'cannotArchiveDefaultList',
        ),
      );
    }
    await _listDao.setArchived(
      id: id,
      isArchived: isArchived,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> deleteList(String id) async {
    // Cascades to the list's entries inside one transaction, in the DAO.
    await _listDao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  // ── entries ───────────────────────────────────────────────────────────────────────────

  @override
  Stream<List<ShoppingEntry>> watchEntries(String listId) =>
      _entryDao.watchForList(listId).asyncMap(_mapEntries);

  @override
  Stream<List<ShoppingEntry>> watchUncheckedEntries(String listId) =>
      _entryDao.watchUncheckedForList(listId).asyncMap(_mapEntries);

  @override
  Future<Result<ShoppingEntry, Failure>> saveEntry(ShoppingEntry entry) async {
    // An entry names a catalogued item OR carries free text — never neither, or the row renders as
    // a blank line nobody can act on (anomaly A24 is about allowing free text, not about allowing
    // nothing).
    final hasItem = entry.itemId != null;
    final hasText = entry.freeText != null && entry.freeText!.trim().isNotEmpty;
    if (!hasItem && !hasText) {
      return const Result.failure(
        ValidationFailure(
          'A shopping entry needs either an item or some text.',
          field: 'freeText',
        ),
      );
    }

    if (hasItem) {
      final item = await _itemDao.byIdIncludingDeleted(entry.itemId!);
      if (item == null) {
        return Result.failure(NotFoundFailure('Item not found.', id: entry.itemId!));
      }
      final quantity = entry.quantity;
      if (quantity != null && quantity.category != item.unitCategory) {
        // A quantity in the wrong category would be stored as a bare integer and reinterpreted on
        // read as the item's own category — 2 pieces becoming 2 grams (Law L8).
        return Result.failure(
          ValidationFailure(
            'This entry is measured in ${quantity.category.name} but the item is measured in '
            '${item.unitCategory.name}.',
            field: 'quantity',
          ),
        );
      }
    }

    final existing = await _entryDao.byIdIncludingDeleted(entry.id);
    final now = _clock.nowUtcMillis();

    // Editing an auto-generated entry promotes it to `manual`, after which the suggestion engine
    // never touches it again (anomaly A22). Detected by comparing against the stored row rather
    // than trusting the incoming entity's own `origin`: a UI that round-trips an entity would
    // otherwise have to remember to flip the flag itself, and forgetting would let regeneration
    // silently overwrite the user's edit.
    final wasAuto = existing != null && existing.origin == ShoppingEntryOrigin.autoLowStock;
    final effectiveOrigin = wasAuto ? ShoppingEntryOrigin.manual : entry.origin;

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    final promoted = entry.copyWith(origin: effectiveOrigin);
    await _entryDao.upsert(
      shoppingEntryToCompanion(
        promoted,
        createdAt: stamps.createdAt,
        updatedAt: stamps.updatedAt,
      ),
    );
    if (wasAuto) {
      // Belt and braces: the companion already carries `manual`, but routing through the DAO's own
      // promote method means the transition is expressed in one place if it ever grows.
      await _entryDao.promoteToManual(id: entry.id, nowUtcMillis: now);
    }
    return Result.ok(promoted);
  }

  @override
  Future<Result<void, Failure>> setEntryChecked({
    required String id,
    required bool isChecked,
  }) async {
    await _entryDao.setChecked(
      id: id,
      isChecked: isChecked,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> snoozeEntry({
    required String id,
    required DateKey until,
  }) async {
    final stock = await _stockAtDecisionMilli(id);
    if (stock == null) {
      return Result.failure(NotFoundFailure('Shopping entry not found.', id: id));
    }
    await _entryDao.setAutoState(
      id: id,
      autoState: ShoppingEntryAutoState.snoozed,
      stockAtDecisionMilli: stock,
      snoozeUntil: until,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> dismissEntry(String id) async {
    final stock = await _stockAtDecisionMilli(id);
    if (stock == null) {
      return Result.failure(NotFoundFailure('Shopping entry not found.', id: id));
    }
    // Records the stock level at the moment of dismissal alongside the state. A dismissal that
    // stored only the flag would never come back — but one that came back on a timer would nag.
    // Storing the reading means the suggestion returns exactly when stock has genuinely risen
    // above the threshold and fallen below it again (anomaly A23).
    await _entryDao.setAutoState(
      id: id,
      autoState: ShoppingEntryAutoState.dismissed,
      stockAtDecisionMilli: stock,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> reorderEntries(List<String> orderedIds) async {
    await _entryDao.reorder(
      orderedIds: orderedIds,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> deleteEntry(String id) async {
    await _entryDao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  // ── the suggestion engine ─────────────────────────────────────────────────────────────

  @override
  Future<Result<int, Failure>> regenerateLowStockSuggestions(String listId) async {
    final list = await _listDao.byIdIncludingDeleted(listId);
    if (list == null || list.deletedAt != null) {
      return Result.failure(NotFoundFailure('Shopping list not found.', id: listId));
    }

    final lowStock = await _itemDao.watchLowStock().first;
    final existingAuto = await _entryDao.watchActiveAutoSuggestions(listId).first;
    var sortOrder = existingAuto.length;
    var active = 0;

    for (final row in lowStock) {
      final threshold = row.lowStockThresholdMilli;
      if (threshold == null) continue;
      final shortfall = threshold - row.totalRemainingMilli;
      if (shortfall <= 0) continue;

      final existing = await _entryDao.findAutoEntry(listId: listId, itemId: row.itemId);

      // A dismissed or snoozed suggestion stays suppressed until stock has recovered past the
      // reading taken when the user dismissed it. Comparing against `generatedAtStockMilli` rather
      // than against the threshold is what distinguishes "still the same shortage they already
      // said no to" from "they bought some and ran out again" (anomaly A23).
      if (existing != null && existing.autoState != ShoppingEntryAutoState.active) {
        final atDecision = existing.generatedAtStockMilli;
        final recovered = atDecision != null && row.totalRemainingMilli > atDecision;
        if (!recovered) continue;
      }

      // Idempotent by construction: `idx_shopping_auto` makes
      // `(listId, itemId, origin='autoLowStock')` unique among live rows, and the DAO's
      // read-then-write honours it — a partial index cannot be an `ON CONFLICT` target, which is
      // why this is not a plain upsert (see the DAO's own note).
      await _entryDao.upsertAutoEntry(
        newId: _uids.generate(),
        listId: listId,
        itemId: row.itemId,
        unitCode: await _itemUnitCode(row.itemId),
        quantityMilli: shortfall,
        stockAtGenerationMilli: row.totalRemainingMilli,
        sortOrder: sortOrder++,
        nowUtcMillis: _clock.nowUtcMillis(),
      );
      active++;
    }
    return Result.ok(active);
  }

  // ── closing the loop back to money ────────────────────────────────────────────────────

  @override
  Future<Result<List<TransactionLine>, Failure>> buildPurchaseDraft(String listId) async {
    // Mapped to entities first, deliberately. Building drafts straight off `ShoppingEntryRow`
    // means hand-assembling a `Qty` from `quantityMilli` and a `Money` from
    // `estimatedPriceMinor` — re-deriving, at a second site, the category and currency resolution
    // that `_mapEntries` already does correctly.
    final entries = await _mapEntries(await _entryDao.watchForList(listId).first);
    final checked =
        entries.where((e) => e.isChecked && e.purchasedTransactionLineId == null).toList();
    if (checked.isEmpty) {
      return const Result.failure(
        BusinessRuleFailure(
          'Nothing on this list is ticked off yet.',
          rule: 'nothingToPurchase',
        ),
      );
    }

    // Drafts only — nothing is written here. The user still confirms the amount and account in the
    // expense editor, and `TransactionRepository.create` is what commits. `transactionId` is left
    // empty deliberately: the transaction does not exist yet, and inventing an id here would let a
    // caller persist a line pointing at nothing.
    final drafts = <TransactionLine>[];
    var lineNo = 1;
    for (final entry in checked) {
      final itemId = entry.itemId;
      drafts.add(
        TransactionLine(
          id: _uids.generate(),
          transactionId: '',
          lineNo: lineNo++,
          description: entry.freeText ?? await _itemName(itemId) ?? 'Item',
          // A catalogued item becomes stock on purchase; free text has nowhere to land, so it
          // stays a plain expense line (ARCH_2 §4.2's `destination` is what removes that
          // ambiguity — anomaly A12).
          destination: itemId != null
              ? TransactionLineDestination.inventory
              : TransactionLineDestination.none,
          itemId: itemId,
          quantity: entry.quantity,
          // Falls back to the item's own display unit. An auto-generated low-stock suggestion is
          // written without one — nothing asked the user — and a line bound for inventory with no
          // unit cannot become a batch, because the column is a foreign key into `units`.
          unitCode: entry.unitCode ?? await _itemUnitCode(itemId),
          lineAmount: entry.estimatedPrice,
        ),
      );
    }
    return Result.ok(drafts);
  }

  @override
  Future<Result<void, Failure>> markPurchased({
    required List<String> entryIds,
    required String transactionId,
  }) async {
    final lines = await _lineDao.forTransaction(transactionId);
    if (lines.isEmpty) {
      return Result.failure(
        NotFoundFailure('That transaction has no lines to link.', id: transactionId),
      );
    }

    // The contract hands over a transaction id, but an entry links to one specific *line*
    // (anomaly A25 — knowing which line fulfilled it is what lets the UI show the price paid).
    // Matching is by `itemId`, since `buildPurchaseDraft` built each line from an entry and
    // carried that id across; free-text entries fall back to matching the description.
    final byItemId = <String, String>{};
    final byDescription = <String, String>{};
    for (final line in lines) {
      final itemId = line.itemId;
      if (itemId != null) {
        byItemId.putIfAbsent(itemId, () => line.id);
      } else {
        byDescription.putIfAbsent(line.description.trim().toLowerCase(), () => line.id);
      }
    }

    final now = _clock.nowUtcMillis();
    final unmatched = <String>[];
    for (final entryId in entryIds) {
      final entry = await _entryDao.byIdIncludingDeleted(entryId);
      if (entry == null) {
        unmatched.add(entryId);
        continue;
      }
      final lineId = entry.itemId != null
          ? byItemId[entry.itemId]
          : byDescription[(entry.freeText ?? '').trim().toLowerCase()];
      if (lineId == null) {
        unmatched.add(entryId);
        continue;
      }
      await _entryDao.markPurchased(
        id: entryId,
        transactionLineId: lineId,
        nowUtcMillis: now,
      );
    }

    if (unmatched.isNotEmpty) {
      // Reported rather than swallowed: the entries that *did* match are already linked, and
      // silently dropping the rest would leave the user's list half-updated with no explanation.
      return Result.failure(
        BusinessRuleFailure(
          '${unmatched.length} of ${entryIds.length} entries had no matching line in that '
          'transaction and were left unticked.',
          rule: 'entryLineMismatch',
        ),
      );
    }
    return const Result.ok(null);
  }

  /// The item's current total stock in base-milli units, for recording alongside a snooze or
  /// dismissal. Returns 0 for a free-text entry, which has no stock to read.
  Future<int?> _stockAtDecisionMilli(String entryId) async {
    final entry = await _entryDao.byIdIncludingDeleted(entryId);
    if (entry == null) return null;
    final itemId = entry.itemId;
    if (itemId == null) return 0;
    final stock = await _itemDao.stockOf(itemId);
    return stock?.totalRemainingMilli ?? 0;
  }

  /// The display unit code of [itemId], or null when there is no item.
  Future<String?> _itemUnitCode(String? itemId) async {
    if (itemId == null) return null;
    final item = await _itemDao.byIdIncludingDeleted(itemId);
    return item?.defaultDisplayUnitCode;
  }

  Future<String?> _itemName(String? itemId) async {
    if (itemId == null) return null;
    final row = await _itemDao.byIdIncludingDeleted(itemId);
    return row?.name;
  }

  Future<List<ShoppingEntry>> _mapEntries(List<ShoppingEntryRow> rows) async {
    final categories = await _categories.categoriesFor(
      rows.map((r) => r.itemId).whereType<String>(),
    );
    final homeCurrencyCode = await _homeCurrencyCode();
    return rows
        .map(
          (r) => r.toEntity(
            category: r.itemId == null ? null : categories[r.itemId],
            homeCurrencyCode: homeCurrencyCode,
          ),
        )
        .toList();
  }

  /// The user's home currency, for reading an entry's estimated price.
  ///
  /// Falls back to `INR` only if the seeded setting is somehow absent — Phase 1C always writes it,
  /// so this is defensive rather than an expected path.
  Future<String> _homeCurrencyCode() async =>
      await _settings.readHomeCurrencyCode() ?? 'INR';
}
```

### `lib/data/repositories/transaction_repository_impl.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/account_dao.dart';
import 'package:alaya/data/daos/batch_dao.dart';
import 'package:alaya/data/daos/stock_movement_dao.dart';
import 'package:alaya/data/daos/transaction_dao.dart';
import 'package:alaya/data/daos/transaction_line_dao.dart';
import 'package:alaya/data/daos/unit_dao.dart';
import 'package:alaya/data/repositories/mappers/money_mappers.dart';
import 'package:alaya/data/repositories/settings_keys.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/repositories/currency_repository.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/repositories/transaction_repository.dart';

/// `TransactionRepository` backed by `TransactionDao` and `TransactionLineDao`.
///
/// Depends on `BatchDao` and `StockMovementDao` (Phase 2B) directly, read-only, purely to answer
/// "is this batch provably untouched" for [delete]. That is normal DAO composition, not a
/// layering violation: any repository may depend on any DAO it needs, and the inventory domain
/// not having its own repository yet (Phase 3C) does not block this one from reading its data.
///
/// Also depends on `CurrencyRepository`, for [freezeConversion] — `convert()` reads only the
/// already-cached rate table and needs no network access, so there is no reason to defer this to
/// a later phase; only `CurrencyRepository.syncDailyRates()` (the network fetch) is Phase 4A's.
final class TransactionRepositoryImpl implements TransactionRepository {
  /// Creates the repository.
  const TransactionRepositoryImpl(
    this._transactionDao,
    this._lineDao,
    this._accountDao,
    this._unitDao,
    this._batchDao,
    this._movementDao,
    this._settings,
    this._currency,
    this._clock,
  );

  final TransactionDao _transactionDao;
  final TransactionLineDao _lineDao;
  final AccountDao _accountDao;
  final UnitDao _unitDao;
  final BatchDao _batchDao;
  final StockMovementDao _movementDao;
  final SettingsRepository _settings;
  final CurrencyRepository _currency;
  final Clock _clock;

  @override
  Future<Transaction?> byId(String id) async => (await _transactionDao.byId(id))?.toEntity();

  @override
  Stream<List<Transaction>> watchByDateRange({required DateKey from, required DateKey to}) {
    return _transactionDao
        .watchByDateRange(from: from, to: to)
        .map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Stream<List<Transaction>> watchByAccount(String accountId) {
    return _transactionDao
        .watchByAccount(accountId)
        .map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Stream<List<Transaction>> watchBySubtype(
    TransactionSubtype subtype, {
    int? fromMonthKey,
    int? toMonthKey,
  }) {
    return _transactionDao
        .watchBySubtype(subtype, fromMonthKey: fromMonthKey, toMonthKey: toMonthKey)
        .map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Stream<List<Transaction>> watchNeedingReview() {
    return _transactionDao.watchNeedingReview().map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Stream<int> watchNeedsReviewCount() => _transactionDao.watchNeedsReviewCount();

  @override
  Future<List<Transaction>> search(String query, {int limit = 50}) async {
    final rows = await _transactionDao.search(query, limit: limit);
    return rows.map((r) => r.toEntity()).toList();
  }

  @override
  Stream<List<TransactionLine>> watchLines(String transactionId) async* {
    // The parent transaction's currency is needed for every line's Money fields
    // (transaction_lines has no currency column of its own, ARCH_2 §4.2), so it is read once
    // before subscribing to the lines stream rather than re-read per emission.
    final parent = await _transactionDao.byId(transactionId);
    final currencyCode = parent?.originalCurrencyCode;
    if (currencyCode == null) return;

    final categories = await _unitDao.categoriesByCode();
    yield* _lineDao.watchForTransaction(transactionId).map(
          (rows) => rows
              .map(
                (r) => r.toEntity(
                  transactionCurrencyCode: currencyCode,
                  categoryResolver: (row) =>
                      row.unitCode == null ? null : categories[row.unitCode],
                ),
              )
              .toList(),
        );
  }

  @override
  Stream<TransactionAllocation?> watchAllocation(String transactionId) {
    return _lineDao.watchAllocation(transactionId).map(
          (row) => row == null
              ? null
              : TransactionAllocation(
                  transactionId: row.txId,
                  amount: Money(row.amountMinor, row.currencyCode),
                  allocated: Money(row.allocatedMinor, row.currencyCode),
                  unallocated: Money(row.unallocatedMinor, row.currencyCode),
                  lineCount: row.lineCount,
                ),
        );
  }

  @override
  Stream<List<TransactionLine>> watchLinesForItem(String itemId) async* {
    final categories = await _unitDao.categoriesByCode();
    yield* _lineDao.watchForItem(itemId).asyncMap((rows) async {
      final result = <TransactionLine>[];
      for (final row in rows) {
        final parent = await _transactionDao.byId(row.transactionId);
        if (parent == null) continue;
        result.add(
          row.toEntity(
            transactionCurrencyCode: parent.originalCurrencyCode,
            categoryResolver: (r) => r.unitCode == null ? null : categories[r.unitCode],
          ),
        );
      }
      return result;
    });
  }

  @override
  Future<Result<Transaction, Failure>> create({
    required Transaction transaction,
    List<TransactionLine> lines = const [],
    List<String> tagIds = const [],
  }) async {
    final resolved = await _fillQuickAddAccount(transaction);
    if (resolved.isFailure) return Result.failure(resolved.failureOrNull!);
    final withAccount = resolved.valueOrNull!;

    final shapeCheck = _validateShape(withAccount);
    if (shapeCheck != null) return Result.failure(shapeCheck);

    final monthKey = withAccount.dateKey.monthKey;
    final now = _clock.nowUtcMillis();

    await _transactionDao.insertWithDetails(
      header: transactionToCompanion(
        withAccount,
        monthKey: monthKey,
        createdAt: now,
        updatedAt: now,
      ),
      lines: lines
          .map((line) => transactionLineToCompanion(line, createdAt: now, updatedAt: now))
          .toList(),
      tagIds: tagIds,
      nowUtcMillis: now,
    );

    final lastUsed = withAccount.toAccountId ?? withAccount.fromAccountId;
    if (lastUsed != null) {
      await _settings.writeValue(
        key: SettingsKeys.lastUsedAccountId,
        value: lastUsed,
        valueType: 'string',
      );
    }

    return Result.ok(withAccount);
  }

  @override
  Future<Result<Transaction, Failure>> update(Transaction transaction) async {
    final shapeCheck = _validateShape(transaction);
    if (shapeCheck != null) return Result.failure(shapeCheck);

    final existing = await _transactionDao.byId(transaction.id);
    if (existing == null) {
      return Result.failure(NotFoundFailure('Transaction not found.', id: transaction.id));
    }

    final monthKey = transaction.dateKey.monthKey;
    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing.createdAt,
      clock: _clock,
    );
    await _transactionDao.updateTransaction(
      transactionToCompanion(
        transaction,
        monthKey: monthKey,
        createdAt: stamps.createdAt,
        updatedAt: stamps.updatedAt,
      ),
    );
    return Result.ok(transaction);
  }

  @override
  Future<Result<void, Failure>> recordCreatedArtefact({
    required String lineId,
    String? createdBatchId,
    String? createdAssetId,
    String? createdRecurringTemplateId,
  }) async {
    await _lineDao.setCreatedArtefact(
      lineId: lineId,
      nowUtcMillis: _clock.nowUtcMillis(),
      createdBatchId: createdBatchId,
      createdAssetId: createdAssetId,
      createdRecurringTemplateId: createdRecurringTemplateId,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> replaceLines({
    required String transactionId,
    required List<TransactionLine> lines,
  }) async {
    final now = _clock.nowUtcMillis();
    await _lineDao.replaceLines(
      transactionId: transactionId,
      lines: lines
          .map((line) => transactionLineToCompanion(line, createdAt: now, updatedAt: now))
          .toList(),
      nowUtcMillis: now,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> markReviewed(String id) async {
    await _transactionDao.markReviewed(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> freezeConversion({
    required String id,
    required DateKey on,
    required String toCurrencyCode,
  }) async {
    final existing = await _transactionDao.byId(id);
    if (existing == null) {
      return Result.failure(NotFoundFailure('Transaction not found.', id: id));
    }

    final original = Money(existing.originalAmountMinor, existing.originalCurrencyCode);
    final converted = await _currency.convert(
      amount: original,
      toCurrencyCode: toCurrencyCode,
      on: on,
    );

    if (converted.isExcludedFromTotals) {
      return const Result.failure(
        BusinessRuleFailure(
          'No exchange rate is cached for this currency pair, so a conversion cannot be '
          'frozen yet. Try again once rates have synced.',
          rule: 'noRateAvailable',
        ),
      );
    }

    // `ConvertedMoney` carries no separate "raw API string" — and a cross-rate genuinely has
    // none: it is computed from two USD-pivoted quotes (ARCH_3 §1.2), never itself a literal API
    // response. The computed rate's own exact decimal string is the reproducible substitute
    // ARCH_3 §1.3 actually needs ("so any number a user questions can be reproduced") — `rate` on
    // a `ConvertedMoney` with `isExcludedFromTotals == false` is always non-null.
    await _transactionDao.freezeConversion(
      id: id,
      convertedAmountMinor: converted.converted!.minor,
      convertedCurrencyCode: converted.converted!.currencyCode,
      conversionRate: converted.rate!,
      conversionRateRaw: converted.rate!.toString(),
      conversionDateKey: converted.rateDateKey!,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<DetachedArtefacts, Failure>> delete({
    required String id,
    String? reason,
  }) async {
    final lines = await _lineDao.forTransaction(id);
    final now = _clock.nowUtcMillis();

    await _transactionDao.softDelete(id: id, reason: reason, nowUtcMillis: now);

    final batchIds = <String>[];
    final assetIds = <String>[];
    final recurringTemplateIds = <String>[];
    final untouchedBatchIds = <String>[];

    for (final line in lines) {
      final batchId = line.createdBatchId;
      final assetId = line.createdAssetId;
      final recurringId = line.createdRecurringTemplateId;
      if (batchId == null && assetId == null && recurringId == null) continue;

      await _lineDao.clearCreatedArtefacts(lineId: line.id, nowUtcMillis: now);

      if (batchId != null) {
        batchIds.add(batchId);
        await _batchDao.detachFromDeletedTransaction(batchId: batchId, nowUtcMillis: now);
        if (await _isBatchUntouched(batchId)) untouchedBatchIds.add(batchId);
      }
      if (assetId != null) assetIds.add(assetId);
      if (recurringId != null) recurringTemplateIds.add(recurringId);
    }

    return Result.ok(
      DetachedArtefacts(
        batchIds: batchIds,
        assetIds: assetIds,
        recurringTemplateIds: recurringTemplateIds,
        untouchedBatchIds: untouchedBatchIds,
      ),
    );
  }

  /// A batch is provably untouched when nothing has been drawn from it — its remaining quantity
  /// still equals what it started with, and no movement beyond the founding one exists. Only
  /// these may be offered for removal after a delete; a batch already consumed from must never
  /// be, because the food really was eaten (anomaly A10).
  Future<bool> _isBatchUntouched(String batchId) async {
    final batch = await _batchDao.byIdIncludingDeleted(batchId);
    if (batch == null) return false;
    if (batch.remainingQuantityMilli != batch.initialQuantityMilli) return false;

    final movements = await _movementDao.forBatch(batchId);
    return movements.every(
      (m) => StockMovementDao.incomingKinds.contains(m.kind),
    );
  }

  /// Fills [transaction]'s missing account with last-used, then the default, then the first
  /// selectable account — never leaving it null (ARCH_2 §4.1). Only applies to
  /// [TransactionKind.deposit], `.withdrawal`, `.adjustmentIncrease` and `.adjustmentDecrease`,
  /// which need exactly one account; a transfer needs two different ones with no sensible
  /// default for either, so a transfer missing an account is a validation failure, not something
  /// to auto-fill.
  Future<Result<Transaction, Failure>> _fillQuickAddAccount(Transaction transaction) async {
    final needsTo = transaction.kind == TransactionKind.deposit ||
        transaction.kind == TransactionKind.adjustmentIncrease;
    final needsFrom = transaction.kind == TransactionKind.withdrawal ||
        transaction.kind == TransactionKind.adjustmentDecrease;

    if (!needsTo && !needsFrom) return Result.ok(transaction);
    if (needsTo && transaction.toAccountId != null) return Result.ok(transaction);
    if (needsFrom && transaction.fromAccountId != null) return Result.ok(transaction);

    final resolvedId = await _resolveQuickAddAccountId();
    if (resolvedId == null) {
      return const Result.failure(
        BusinessRuleFailure(
          'No account is available to record this against. Create an account first.',
          rule: 'noAccountAvailable',
        ),
      );
    }

    return Result.ok(
      needsTo
          ? transaction.copyWith(toAccountId: resolvedId)
          : transaction.copyWith(fromAccountId: resolvedId),
    );
  }

  /// Resolves quick-add's account: last-used, then the seeded default, then the first
  /// selectable account by sort order — each candidate checked for existence, since an account
  /// referenced by a stale setting could since have been deleted.
  Future<String?> _resolveQuickAddAccountId() async {
    final lastUsedId = await _settings.readValue(SettingsKeys.lastUsedAccountId);
    if (lastUsedId != null && await _accountExists(lastUsedId)) return lastUsedId;

    final defaultId = await _settings.readDefaultAccountId();
    if (defaultId != null && await _accountExists(defaultId)) return defaultId;

    final selectable = await _accountDao.watchSelectable().first;
    return selectable.isEmpty ? null : selectable.first.id;
  }

  Future<bool> _accountExists(String id) async {
    final account = await _accountDao.byIdIncludingDeleted(id);
    return account != null && account.deletedAt == null;
  }

  /// Validates the shape ARCH_2 §4.1's CHECK constraints require, in Dart, so a caller sees a
  /// clear [ValidationFailure] rather than a raw SQLite constraint error.
  Failure? _validateShape(Transaction transaction) {
    if (transaction.originalAmount.minor <= 0) {
      return const ValidationFailure(
        'The amount must be greater than zero.',
        field: 'originalAmount',
      );
    }

    final from = transaction.fromAccountId;
    final to = transaction.toAccountId;

    switch (transaction.kind) {
      case TransactionKind.deposit:
      case TransactionKind.adjustmentIncrease:
        if (to == null || from != null) {
          return const ValidationFailure(
            'A deposit needs a destination account and no source account.',
            field: 'toAccountId',
          );
        }
      case TransactionKind.withdrawal:
      case TransactionKind.adjustmentDecrease:
        if (from == null || to != null) {
          return const ValidationFailure(
            'A withdrawal needs a source account and no destination account.',
            field: 'fromAccountId',
          );
        }
      case TransactionKind.transfer:
        if (from == null || to == null) {
          return const ValidationFailure(
            'A transfer needs both a source and a destination account.',
            field: 'toAccountId',
          );
        }
        if (from == to) {
          return const ValidationFailure(
            'A transfer must be between two different accounts.',
            field: 'toAccountId',
          );
        }
    }
    return null;
  }
}
```
