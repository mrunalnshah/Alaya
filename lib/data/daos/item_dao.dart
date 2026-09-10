import 'package:drift/drift.dart';

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/data/db/alaya_database.dart';

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
      (_activeRows()
            ..orderBy([(t) => OrderingTerm(expression: t.normalizedName)]))
          .watch();

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
    return (_activeRows()..where(
          (t) =>
              t.normalizedName.equals(normalizedName) &
              t.unitCategory.equalsValue(unitCategory),
        ))
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
  Future<void> upsert(ItemsCompanion item) =>
      into(_table).insertOnConflictUpdate(item);

  /// How many live items are filed under [kindTagId] as their kind.
  ///
  /// **A `COUNT`, not a list the caller measures.** Settings asks this to say *"12 items will move to Other"*
  /// before deleting a kind, and loading twelve rows to learn there are twelve would read every column of
  /// every one of them for a number.
  ///
  /// Deleted items are excluded. An item in the trash has no kind worth reassigning, and counting it would
  /// overstate the consequence in the one sentence whose entire job is to be accurate.
  Future<int> countByKind(String kindTagId) async {
    final total = _table.id.count();
    final row =
        await (selectOnly(_table)
              ..addColumns([total])
              ..where(
                _table.kindTagId.equals(kindTagId) & _table.deletedAt.isNull(),
              ))
            .getSingle();
    return row.read(total) ?? 0;
  }

  /// Moves every live item from [fromTagId] to [toTagId], returning how many moved.
  ///
  /// **One `UPDATE`, not a read-modify-write loop.** A loop that failed half way would leave some items on the
  /// old kind and some on the new — and the caller deletes the old kind immediately afterwards, so the ones it
  /// missed would point at a soft-deleted row with no way to tell which they were. A single statement moves all
  /// of them or none.
  ///
  /// Returns the count so Settings can report what it actually changed rather than what it counted a moment
  /// earlier. The two differ if anything wrote in between, and the number in a confirmation should be the
  /// number that happened.
  Future<int> reassignKind({
    required String fromTagId,
    required String toTagId,
    required int nowUtcMillis,
  }) =>
      (update(_table)..where(
            (t) => t.kindTagId.equals(fromTagId) & t.deletedAt.isNull(),
          ))
          .write(
            ItemsCompanion(
              kindTagId: Value(toTagId),
              updatedAt: Value(nowUtcMillis),
            ),
          );

  /// Toggles the favourite flag.
  Future<void> setFavorite({
    required String id,
    required bool isFavorite,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      ItemsCompanion(
        isFavorite: Value(isFavorite),
        updatedAt: Value(nowUtcMillis),
      ),
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
        ItemsCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );
      await (update(
        attachedDatabase.inventoryBatches,
      )..where((t) => t.itemId.equals(id) & t.deletedAt.isNull())).write(
        InventoryBatchesCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );
    });
  }

  // ── derived stock: always from the views ───────────────────────────────────────────────

  /// Emits every active item's stock rollup from `v_item_stock`.
  Stream<List<ItemStockRow>> watchAllStock() =>
      select(attachedDatabase.vItemStock).watch();

  /// Emits one item's stock rollup.
  Stream<ItemStockRow?> watchStockOf(String itemId) {
    return (select(
      attachedDatabase.vItemStock,
    )..where((t) => t.itemId.equals(itemId))).watchSingleOrNull();
  }

  /// Reads one item's stock rollup once.
  Future<ItemStockRow?> stockOf(String itemId) {
    return (select(
      attachedDatabase.vItemStock,
    )..where((t) => t.itemId.equals(itemId))).getSingleOrNull();
  }

  /// Emits every item currently below its low-stock threshold, from `v_low_stock`.
  Stream<List<LowStockRow>> watchLowStock() =>
      select(attachedDatabase.vLowStock).watch();
}
