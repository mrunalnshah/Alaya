import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `app_settings`, the single key/value store for everything user-configurable
/// (ARCH_2 §3).
///
/// No view exists for this table, so [_activeRows] is the one place the soft-delete filter is
/// applied and every read routes through it — see the note at the top of `account_dao.dart` for
/// why that is the mechanism here rather than a view.
class SettingsDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  SettingsDao(super.db);

  $AppSettingsTable get _table => attachedDatabase.appSettings;

  SimpleSelectStatement<$AppSettingsTable, AppSettingRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits the value for [key], or null when it is unset or soft-deleted.
  Stream<String?> watchValue(String key) =>
      (_activeRows()..where((t) => t.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => row?.value);

  /// Reads the value for [key] once, or null when unset or soft-deleted.
  Future<String?> readValue(String key) async {
    final row = await (_activeRows()..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// Emits every active setting as a key/value map.
  Stream<Map<String, String>> watchAll() => _activeRows().watch().map(
        (rows) => {for (final row in rows) row.key: row.value},
  );

  /// Reads every active setting once.
  Future<Map<String, String>> readAll() async {
    final rows = await _activeRows().get();
    return {for (final row in rows) row.key: row.value};
  }

  /// Inserts or replaces [key].
  ///
  /// Clears `deletedAt` on write so re-setting a previously deleted key revives it rather than
  /// leaving an invisible row that [_activeRows] would keep filtering out.
  Future<void> writeValue({
    required String key,
    required String value,
    required String valueType,
    required int nowUtcMillis,
  }) {
    return into(_table).insertOnConflictUpdate(
      AppSettingsCompanion.insert(
        key: key,
        value: value,
        valueType: valueType,
        createdAt: nowUtcMillis,
        updatedAt: nowUtcMillis,
        deletedAt: const Value(null),
      ),
    );
  }

  /// Soft-deletes [key].
  Future<void> softDelete({required String key, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.key.equals(key))).write(
      AppSettingsCompanion(
        deletedAt: Value(nowUtcMillis),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }
}