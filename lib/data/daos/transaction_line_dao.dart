import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `transaction_lines` and the allocation view derived from them.
class TransactionLineDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  TransactionLineDao(super.db);

  $TransactionLinesTable get _table => attachedDatabase.transactionLines;

  SimpleSelectStatement<$TransactionLinesTable, TransactionLineRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits the active lines of [transactionId], in entry order.
  Stream<List<TransactionLineRow>> watchForTransaction(String transactionId) {
    return (_activeRows()
      ..where((t) => t.transactionId.equals(transactionId))
      ..orderBy([(t) => OrderingTerm(expression: t.lineNo)]))
        .watch();
  }

  /// Reads the active lines of [transactionId] once.
  Future<List<TransactionLineRow>> forTransaction(String transactionId) {
    return (_activeRows()
      ..where((t) => t.transactionId.equals(transactionId))
      ..orderBy([(t) => OrderingTerm(expression: t.lineNo)]))
        .get();
  }

  /// Emits the allocation summary for [transactionId] from `v_transaction_allocation`.
  ///
  /// Check `lineCount` before showing an unallocated chip: with no lines at all
  /// `unallocatedMinor` equals the full amount, which is not the same thing as a mismatch
  /// (anomaly A11).
  Stream<TransactionAllocationRow?> watchAllocation(String transactionId) {
    return (select(attachedDatabase.vTransactionAllocation)
      ..where((t) => t.txId.equals(transactionId)))
        .watchSingleOrNull();
  }

  /// Emits every active line referencing [itemId], newest first — an item's purchase history.
  ///
  /// The basis of the unit-price trend and price-per-base-unit insights (ARCH_3 §5.1 queries 12
  /// and 24). `quantityMilli` is already in base-milli units, so no conversion is needed.
  Stream<List<TransactionLineRow>> watchForItem(String itemId) {
    return (_activeRows()
      ..where((t) => t.itemId.equals(itemId))
      ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]))
        .watch();
  }

  /// Replaces every line of [transactionId] in one transaction (Law L14).
  ///
  /// Existing lines are soft-deleted rather than removed, because a line may already have created
  /// a batch or an asset and `created*Id` is the only record of that link (anomaly A12). Deleting
  /// the row would orphan the artefact silently.
  Future<void> replaceLines({
    required String transactionId,
    required List<TransactionLinesCompanion> lines,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      await (update(_table)
        ..where((t) => t.transactionId.equals(transactionId) & t.deletedAt.isNull()))
          .write(
        TransactionLinesCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );
      for (final line in lines) {
        await into(_table).insert(line);
      }
    });
  }

  /// Inserts one line.
  Future<void> insertLine(TransactionLinesCompanion line) => into(_table).insert(line);

  /// Soft-deletes one line.
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      TransactionLinesCompanion(
        deletedAt: Value(nowUtcMillis),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Records which artefact a line produced, after the fan-out service created it.
  ///
  /// Exactly one of the three ids is ever set for a given line, matching its `destination`
  /// (ARCH_2 §4.2) — this method writes whichever was supplied and leaves the others untouched.
  Future<void> setCreatedArtefact({
    required String lineId,
    required int nowUtcMillis,
    String? createdBatchId,
    String? createdAssetId,
    String? createdRecurringTemplateId,
  }) {
    return (update(_table)..where((t) => t.id.equals(lineId))).write(
      TransactionLinesCompanion(
        createdBatchId:
        createdBatchId == null ? const Value.absent() : Value(createdBatchId),
        createdAssetId:
        createdAssetId == null ? const Value.absent() : Value(createdAssetId),
        createdRecurringTemplateId: createdRecurringTemplateId == null
            ? const Value.absent()
            : Value(createdRecurringTemplateId),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Clears the link from [lineId] to whatever it created, without touching the artefact.
  ///
  /// The detach half of anomaly A10: deleting a receipt must not delete food already eaten, so the
  /// pointer is nulled and the batch's `origin` becomes `detached` by the caller.
  Future<void> clearCreatedArtefacts({
    required String lineId,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(lineId))).write(
      TransactionLinesCompanion(
        createdBatchId: const Value(null),
        createdAssetId: const Value(null),
        createdRecurringTemplateId: const Value(null),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }
}