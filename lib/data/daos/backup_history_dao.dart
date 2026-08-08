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