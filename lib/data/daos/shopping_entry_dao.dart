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
