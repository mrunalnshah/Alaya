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