import 'package:drift/drift.dart';

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `units` — system and user-defined units, each with an exact integer factor to
/// its category base (ARCH_1 §5.3).
class UnitDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  UnitDao(super.db);

  $UnitsTable get _table => attachedDatabase.units;

  SimpleSelectStatement<$UnitsTable, UnitRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits every active unit in display order.
  Stream<List<UnitRow>> watchAll() =>
      (_activeRows()..orderBy([(t) => OrderingTerm(expression: t.sortOrder)])).watch();

  /// Emits the active units measuring [category].
  ///
  /// A quantity picker must never offer a unit from another category — cross-category conversion
  /// does not exist (Law L8), so offering `ml` for a weight item would produce a value nothing
  /// can convert.
  Stream<List<UnitRow>> watchByCategory(UnitCategory category) {
    return (_activeRows()
      ..where((t) => t.category.equalsValue(category))
      ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Reads one unit by code.
  Future<UnitRow?> byCode(String code) =>
      (_activeRows()..where((t) => t.code.equals(code))).getSingleOrNull();

  /// Reads `code -> factorToBaseMilli` for every active unit.
  ///
  /// The map `UnitConverter` needs. Integer factors only: no step of a unit conversion in this
  /// app touches a double (Law L2).
  Future<Map<String, int>> factorsByCode() async {
    final rows = await _activeRows().get();
    return {for (final row in rows) row.code: row.factorToBaseMilli};
  }

  /// Reads `code -> category`, which is what lets a mapper resolve a `Qty`'s category from a bare
  /// unit code when the row has no linked item (see `qty_converter.dart`).
  Future<Map<String, UnitCategory>> categoriesByCode() async {
    final rows = await _activeRows().get();
    return {for (final row in rows) row.code: row.category};
  }

  /// Inserts or updates a unit.
  Future<void> upsert(UnitsCompanion unit) => into(_table).insertOnConflictUpdate(unit);

  /// Soft-deletes a user-defined unit.
  ///
  /// Returns the number of rows changed, which is 0 when the unit is a system unit — those cannot
  /// be deleted, and the guard is expressed here as a `WHERE` clause so no caller can bypass it
  /// by forgetting to check.
  Future<int> softDeleteUserUnit({required String code, required int nowUtcMillis}) {
    return (update(_table)
      ..where((t) => t.code.equals(code) & t.isSystem.equals(false)))
        .write(
      UnitsCompanion(deletedAt: Value(nowUtcMillis), updatedAt: Value(nowUtcMillis)),
    );
  }
}