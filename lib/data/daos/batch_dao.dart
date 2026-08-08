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