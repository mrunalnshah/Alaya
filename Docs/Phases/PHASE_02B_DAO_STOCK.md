# Phase 2B — Data Access Objects, Inventory & Shopping

**5 DAOs · FEFO-ordered reads · every stock write atomically pairs a movement with its cache
update · no delete method on the ledger.**

## Add dependencies

None. Every import resolves to packages already present.

## Fix in this revision

`shopping_list_dao.dart` used `DateKey` as a parameter type but only imported
`date_key_filters.dart` — the extension file that *uses* `DateKey` internally, not the file that
*declares* it. Dart doesn't re-export transitively, so the type was genuinely out of scope. Added
`import 'package:alaya/core/time/date_key.dart';`.

This prompted a full re-scan, not just a spot fix: every file in the project (63 total, `lib/` and
`test/`) checked for the same shape of mistake — a type used in real code (not a doc comment,
not a string) without a resolved import, correctly handling both `package:alaya/...` and relative
imports. **One real instance, now fixed.** The first pass of that scanner flagged 16 files, every
one a false positive from a cruder check (Phase 1A's `core/` files use relative imports like
`import 'money.dart';`, which resolve correctly but don't match a `package:` string match; several
others were dartdoc `[CrossReferences]` inside `///` comments, which don't require an import at
all).

## A real bug caught before delivery, not just tested for

`batch_dao.dart`'s first draft called `attachedDatabase.stockMovementDao.insert(...)` and
`.forBatch(...)`. **That getter does not exist.** `AlayaDatabase` exposes tables and views as
generated getters — `attachedDatabase.stockMovements`, `attachedDatabase.vItemStock` — because
`@DriftDatabase`'s codegen only knows about the `tables:` and `include:` sets. A DAO is a plain
`DatabaseAccessor` subclass I instantiate myself; the database class has no idea `StockMovementDao`
exists, and adding that wiring wasn't asked for in this phase.

Fixed by having `BatchDao` write `stock_movements` directly through
`attachedDatabase.stockMovements`, the real generated table getter. `StockMovementDao`'s direction
rule — [`incomingKinds`], [`signedQuantityOf`] — is a `static` member for exactly this reason: it's
shared logic usable from `BatchDao` without needing an instance of the other DAO. I then scanned
every DAO in the project (all 14, Phase 2A included) for the same
`attachedDatabase.xxxDao`-that-doesn't-exist pattern: this was the only occurrence, now fixed.

## Verification performed

Since no Dart toolchain is available to me, everything below was checked mechanically or against
real SQLite, not reasoned about:

| Check | Result |
|---|---|
| FEFO ordering — nearest expiry first, undated batches last | verified against real SQLite: `['b3','b2','b4','b1']` for a 4-batch mixed set |
| **The exact FEFO consumption scenario** — 3 batches, consume 600g | draws `300g` from nearest-expiry, `300g` from next, undated batch untouched — matches PROMPTS.md's required test precisely |
| `recomputeRemaining`'s formula vs `v_batch_stock_check.ledger_remaining_milli`'s formula | identical `CASE WHEN kind IN (openingIn, purchaseIn, manualIn, adjustIn)` direction rule, both computed by hand and cross-checked: `2,000,000 − 300,000 − 100,000 + 50,000 = 1,650,000` |
| `findDiscrepancies`' `WHERE NOT (discrepancy = 0)` | catches both positive and negative discrepancies, verified against real SQLite |
| Every `DateKey` filter site | uses `DateKeyColumnFilters` from Phase 2A; zero raw `DateKey` arguments to any drift range helper across all 5 files |
| `equalsValue` on enum-converted columns | confirmed the correct drift API from `GeneratedColumnWithTypeConverter`'s own docs (also used, and already verified, in Phase 2A) |
| `Companion.custom(... + Variable<int>(signed))` | confirmed against drift's own upsert example; `Variable` is drift's **recommended** choice for a runtime-computed value — the docs' example uses `Constant(1)` only because `1` there is a compile-time literal, which `signed` is not |
| Every generated table class (`$ItemsTable`, `$InventoryBatchesTable`, ...) | cross-checked against the actual `class Items extends Table` declarations in `tables/inventory_tables.dart` and `shopping_tables.dart` |
| Every view row class (`ItemStockRow`, `BatchStockCheckRow`, `LowStockRow`) | cross-checked against the `AS DartName` in `inventory_views.drift` |
| Brace/paren/bracket balance, all 5 files | balanced |
| Every `package:alaya/...` import | resolves to a real file |

## Findings

**1. `stock_movement_dao.dart` enforces "no delete" at the type level, not by convention.** There
is no `Future<void> delete(...)` method, and — more importantly — **no `update(_table)` call
anywhere in the file**. The only mutation exposed after [`insert`] is a new row via `insert` with
`reversesMovementId` set. A correction cannot edit the row it corrects because the method to do
that does not exist.

**2. `applyMovement` is the one path every stock change should go through**, and it is the only
method on `BatchDao` that can change `remainingQuantityMilli` — [`updateMetadata`] explicitly
cannot, by scope (location, note, expiry, cost). The signed delta it applies —
`current + signedQuantity` — uses the exact same direction rule
(`StockMovementDao.signedQuantityOf`, mirroring `v_batch_stock_check`'s `CASE WHEN`) that the
reconciliation view uses, so a batch written through this method cannot become the discrepancy that
view exists to catch.

**3. `insertWithOpeningMovement` has no `update(_table)` call, and that's correct, not a gap.** A
fresh `INSERT` establishes the cache value once; there's no prior row to update. The caller
contract — `remainingQuantityMilli` must equal `initialQuantityMilli`, since nothing has been
consumed yet — is now explicit in the doc comment rather than silently assumed, matching how
Phase 2A's `item_dao.upsert` already documents the `unitCategory`-immutability check it can't itself
enforce.

**4. `recomputeRemaining` reads the full movement history and writes an absolute total**, never a
delta — so it self-heals even if the cache had already drifted before it ran. `recomputeAll` calls
it sequentially over every active batch rather than in parallel: each call is its own small
transaction, concurrent runs against one connection would only queue anyway, and at this app's
scale (thousands of batches, not millions) isolating which batch throws matters more than shaving
milliseconds off a Settings-screen repair action.

**5. `item_dao.findByIdentity` matches on the pair, not the name alone.** `idx_items_identity` is a
partial unique index on `(normalizedName, unitCategory)` together, so `Milk (Weight)` and
`Milk (Volume)` are two different rows and this method correctly returns `null` for a category with
no match yet, even when the name matches a *different* category's item.

**6. `shopping_entry_dao.upsert` gets its idempotency from the schema, not from DAO logic.**
`idx_shopping_auto` makes `(listId, itemId, origin='autoLowStock')` unique, so
`insertOnConflictUpdate` naturally updates the one active auto-suggestion for an item instead of
duplicating it — anomaly A22's requirement, carried by the index rather than by a
check-then-insert-or-update dance in Dart.

**7. `shopping_list_dao.setDefault` clears every other list's flag in the same transaction it sets
the new one** (Law L14), because `shopping_lists.isDefault` carries no database-level uniqueness
constraint — nothing stops two rows both being `true` except this write path. `watchDefault()`'s
doc comment says "if any" rather than assuming exactly one, precisely because that guarantee lives
in this method, not in the schema.

**8. `item_dao.softDelete` cascades to active batches; `stock_movements` is deliberately
untouched.** The cascade is real and intentional here — unlike `transaction_dao.softDelete` in
Phase 2A, which explicitly does *not* cascade to created batches or assets (anomaly A10). The
difference: deleting an *item* removes the thing the batches describe, so soft-deleting them too is
correct; deleting a *transaction* removes only a receipt, and the food it bought still exists. The
ledger itself is untouched in both cases — Law L6's stated exception for `stock_movements` holds
regardless of which direction triggered the cascade.



---

### `lib/data/daos/item_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/date_key_filters.dart';

/// Typed access to `items` and the three views derived from its stock.
///
/// Every stock figure — remaining quantity, batch count, nearest expiry, low-stock status —
/// comes from `v_item_stock` or `v_low_stock`. This DAO never sums `inventory_batches` itself
/// (Law L7): that sum is one view's entire reason to exist, and a second copy of it here would
/// be a second place for the zero-remaining-batch exclusion rule to be gotten wrong.
class ItemDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  ItemDao(super.db);

  $ItemsTable get _table => attachedDatabase.items;

  SimpleSelectStatement<$ItemsTable, ItemRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits every active item, alphabetically.
  Stream<List<ItemRow>> watchAll() =>
      (_activeRows()..orderBy([(t) => OrderingTerm(expression: t.normalizedName)])).watch();

  /// Emits active items measuring [category] — a picker must never offer a cross-category item,
  /// since cross-category conversion does not exist (Law L8).
  Stream<List<ItemRow>> watchByCategory(UnitCategory category) {
    return (_activeRows()
          ..where((t) => t.unitCategory.equalsValue(category))
          ..orderBy([(t) => OrderingTerm(expression: t.normalizedName)]))
        .watch();
  }

  /// Emits favourited items, for a dashboard shortcut.
  Stream<List<ItemRow>> watchFavorites() {
    return (_activeRows()
          ..where((t) => t.isFavorite.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.normalizedName)]))
        .watch();
  }

  /// Reads one item by id, including a soft-deleted one — so a historical transaction line or
  /// batch that still points at it can render a name.
  Future<ItemRow?> byIdIncludingDeleted(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads the active item whose identity is `(normalizedName, category)`, or null if none
  /// exists — the merge-or-create decision (anomaly A06).
  ///
  /// Identity is the pair, not the name alone: `idx_items_identity` is a partial unique index on
  /// both columns together, so `Milk (Weight)` and `Milk (Volume)` are two different rows and
  /// this correctly returns null for a category that has no match yet, even when the name does.
  Future<ItemRow?> findByIdentity({
    required String normalizedName,
    required UnitCategory unitCategory,
  }) {
    return (_activeRows()
          ..where((t) =>
              t.normalizedName.equals(normalizedName) &
              t.unitCategory.equalsValue(unitCategory)))
        .getSingleOrNull();
  }

  /// Emits active items whose normalized name contains [term], for the item picker's search
  /// field — exact-substring only; near-match suggestion is a repository concern (anomaly A07).
  Stream<List<ItemRow>> watchMatching(String term) {
    final needle = '%${term.toLowerCase()}%';
    return (_activeRows()
          ..where((t) => t.normalizedName.like(needle))
          ..orderBy([(t) => OrderingTerm(expression: t.normalizedName)])
          ..limit(50))
        .watch();
  }

  /// Inserts or updates an item.
  ///
  /// Does not, and cannot, guard `unitCategory` immutability (Law L8) — a `Companion` carries no
  /// memory of the row it is replacing. That check belongs to the repository, which reads the
  /// existing row first and rejects a companion that changes it.
  Future<void> upsert(ItemsCompanion item) => into(_table).insertOnConflictUpdate(item);

  /// Toggles the favourite flag.
  Future<void> setFavorite({
    required String id,
    required bool isFavorite,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      ItemsCompanion(isFavorite: Value(isFavorite), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Soft-deletes an item and its active batches, in one transaction (Law L14).
  ///
  /// Cascades to batches — deliberately, and only here. `stock_movements` is append-only and is
  /// never soft-deleted (Law L6's stated exception): the ledger for food that no longer has a
  /// catalogued item stays exactly as complete as it was.
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return transaction(() async {
      await (update(_table)..where((t) => t.id.equals(id))).write(
        ItemsCompanion(deletedAt: Value(nowUtcMillis), updatedAt: Value(nowUtcMillis)),
      );
      await (update(attachedDatabase.inventoryBatches)
            ..where((t) => t.itemId.equals(id) & t.deletedAt.isNull()))
          .write(
        InventoryBatchesCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );
    });
  }

  // ── derived stock: always from the views ───────────────────────────────────────────────

  /// Emits every active item's stock rollup from `v_item_stock`.
  Stream<List<ItemStockRow>> watchAllStock() => select(attachedDatabase.vItemStock).watch();

  /// Emits one item's stock rollup.
  Stream<ItemStockRow?> watchStockOf(String itemId) {
    return (select(attachedDatabase.vItemStock)..where((t) => t.itemId.equals(itemId)))
        .watchSingleOrNull();
  }

  /// Reads one item's stock rollup once.
  Future<ItemStockRow?> stockOf(String itemId) {
    return (select(attachedDatabase.vItemStock)..where((t) => t.itemId.equals(itemId)))
        .getSingleOrNull();
  }

  /// Emits every item currently below its low-stock threshold, from `v_low_stock`.
  Stream<List<LowStockRow>> watchLowStock() => select(attachedDatabase.vLowStock).watch();
}

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

  /// Reads one movement by id — for resolving what a reversal points at.
  Future<StockMovementRow?> byId(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads the reversal of [movementId], if one has been recorded.
  Future<StockMovementRow?> reversalOf(String movementId) =>
      (select(_table)..where((t) => t.reversesMovementId.equals(movementId)))
          .getSingleOrNull();
}

```

### `lib/data/daos/shopping_list_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/date_key_filters.dart';

/// Typed access to `shopping_lists`.
class ShoppingListDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  ShoppingListDao(super.db);

  $ShoppingListsTable get _table => attachedDatabase.shoppingLists;

  SimpleSelectStatement<$ShoppingListsTable, ShoppingListRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits active, unarchived lists in name order.
  Stream<List<ShoppingListRow>> watchSelectable() {
    return (_activeRows()
          ..where((t) => t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch();
  }

  /// Emits every active list, archived included.
  Stream<List<ShoppingListRow>> watchAllIncludingArchived() {
    return (_activeRows()..orderBy([(t) => OrderingTerm(expression: t.name)])).watch();
  }

  /// Emits the one list marked default, if any.
  ///
  /// "If any" rather than assuming exactly one: `isDefault` carries no database-level
  /// uniqueness constraint, so this is a query result, not a guarantee. The repository's write
  /// path is what keeps it single by clearing every other list's flag in the same transaction —
  /// see [setDefault].
  Stream<ShoppingListRow?> watchDefault() {
    return (_activeRows()..where((t) => t.isDefault.equals(true))).watchSingleOrNull();
  }

  /// Emits lists with a target shopping date in `[from, to]` — the calendar's `shoppingTarget`
  /// source, ARCH_3 §6.
  Stream<List<ShoppingListRow>> watchWithTargetInRange({
    required DateKey from,
    required DateKey to,
  }) {
    return (_activeRows()..where((t) => t.targetDateKey.isInDateRange(from, to))).watch();
  }

  /// Reads one list by id, including a soft-deleted one.
  Future<ShoppingListRow?> byIdIncludingDeleted(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Inserts or updates a list.
  Future<void> upsert(ShoppingListsCompanion list) => into(_table).insertOnConflictUpdate(list);

  /// Marks [id] as the one default list, clearing the flag on every other active list, in one
  /// transaction (Law L14) — the write path that keeps [watchDefault]'s "if any" true in
  /// practice.
  Future<void> setDefault({required String id, required int nowUtcMillis}) {
    return transaction(() async {
      await (update(_table)
            ..where((t) => t.isDefault.equals(true) & t.id.equals(id).not()))
          .write(ShoppingListsCompanion(isDefault: const Value(false), updatedAt: Value(nowUtcMillis)));
      await (update(_table)..where((t) => t.id.equals(id))).write(
        ShoppingListsCompanion(isDefault: const Value(true), updatedAt: Value(nowUtcMillis)),
      );
    });
  }

  /// Archives or unarchives a list.
  Future<void> setArchived({
    required String id,
    required bool isArchived,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      ShoppingListsCompanion(isArchived: Value(isArchived), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Soft-deletes a list and its active entries, in one transaction (Law L14).
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return transaction(() async {
      await (update(_table)..where((t) => t.id.equals(id))).write(
        ShoppingListsCompanion(deletedAt: Value(nowUtcMillis), updatedAt: Value(nowUtcMillis)),
      );
      await (update(attachedDatabase.shoppingEntries)
            ..where((t) => t.listId.equals(id) & t.deletedAt.isNull()))
          .write(
        ShoppingEntriesCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );
    });
  }
}

```

### `lib/data/daos/shopping_entry_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/date_key_filters.dart';

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

  /// Inserts or updates an entry.
  ///
  /// Safe to call for an auto-generated entry too: `idx_shopping_auto` makes
  /// `(listId, itemId, origin='autoLowStock')` unique, so `insertOnConflictUpdate` naturally
  /// upserts the one active auto-suggestion for an item rather than duplicating it — the
  /// idempotency anomaly A22 asks for, carried by the schema rather than by DAO logic.
  Future<void> upsert(ShoppingEntriesCompanion entry) =>
      into(_table).insertOnConflictUpdate(entry);

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
