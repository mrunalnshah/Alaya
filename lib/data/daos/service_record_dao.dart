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