import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/batch_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/item_category_resolver.dart';
import 'package:alaya/data/repositories/mappers/stock_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/repositories/batch_repository.dart';

/// `BatchRepository` backed by `BatchDao`.
final class BatchRepositoryImpl implements BatchRepository {
  /// Creates the repository over [dao], resolving item categories through [categories].
  const BatchRepositoryImpl(this._dao, this._categories, this._clock);

  final BatchDao _dao;
  final ItemCategoryResolver _categories;
  final Clock _clock;

  @override
  Stream<List<Batch>> watchByItemFefo(String itemId) =>
      _dao.watchByItemFefo(itemId).asyncMap((rows) => _mapAll(rows));

  @override
  Future<List<Batch>> byItemFefo(String itemId) async =>
      _mapAll(await _dao.byItemFefo(itemId));

  @override
  Stream<List<Batch>> watchByItem(String itemId) =>
      _dao.watchByItem(itemId).asyncMap((rows) => _mapAll(rows));

  @override
  Stream<List<Batch>> watchExpiringInRange({
    required DateKey from,
    required DateKey to,
  }) =>
      _dao.watchExpiringInRange(from: from, to: to).asyncMap((rows) => _mapAll(rows));

  @override
  Future<Batch?> byId(String id) async {
    final row = await _dao.byIdIncludingDeleted(id);
    if (row == null) return null;
    final category = await _categories.categoryOf(row.itemId);
    if (category == null) return null;
    return row.toEntity(category);
  }

  @override
  Future<Result<Batch, Failure>> create(Batch batch) async {
    if (!batch.initialQuantity.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'A new batch needs a quantity greater than zero.',
          field: 'initialQuantity',
        ),
      );
    }
    if (batch.remainingQuantity != batch.initialQuantity) {
      // BatchDao.insertWithOpeningMovement's documented caller contract: nothing has been consumed
      // yet, so the two cannot differ. Enforced here rather than trusted, because the founding
      // movement it writes uses `initialQuantityMilli` — a mismatch would make the batch a
      // permanent discrepancy in `v_batch_stock_check` from the moment it was created.
      return const Result.failure(
        ValidationFailure(
          'A new batch must have its full quantity remaining.',
          field: 'remainingQuantity',
        ),
      );
    }

    final category = await _categories.categoryOf(batch.itemId);
    if (category == null) {
      return Result.failure(
        NotFoundFailure('The item this batch belongs to does not exist.', id: batch.itemId),
      );
    }
    if (category != batch.initialQuantity.category) {
      // A `Qty` in the wrong category would be stored as a bare integer and silently reinterpreted
      // on read as the item's own category — 2 pieces becoming 2 grams. Law L8 makes this
      // impossible to fix afterwards, so it is refused now.
      return Result.failure(
        ValidationFailure(
          'This batch is measured in ${batch.initialQuantity.category.name} but its item is '
              'measured in ${category.name}.',
          field: 'initialQuantity',
        ),
      );
    }

    final now = _clock.nowUtcMillis();
    await _dao.insertWithOpeningMovement(
      batch: batchToCompanion(batch, createdAt: now, updatedAt: now),
      // `purchaseIn` when the batch came from a transaction line, `manualIn` when the user added
      // it directly. The repository's call to make, as the DAO's doc notes.
      openingKind: batch.sourceTransactionLineId != null
          ? StockMovementKind.purchaseIn
          : StockMovementKind.manualIn,
      nowUtcMillis: now,
    );
    return Result.ok(batch);
  }

  @override
  Future<Result<Batch, Failure>> updateMetadata(Batch batch) async {
    final existing = await _dao.byIdIncludingDeleted(batch.id);
    if (existing == null) {
      return Result.failure(NotFoundFailure('Batch not found.', id: batch.id));
    }
    if (existing.remainingQuantityMilli != batch.remainingQuantity.milliBase ||
        existing.initialQuantityMilli != batch.initialQuantity.milliBase) {
      // Quantities move only by recording a movement, so that the ledger and the cache can never
      // disagree (Law L3). A metadata update that also changed a quantity would write the cache
      // with no matching movement — exactly the drift `v_batch_stock_check` exists to detect.
      return const Result.failure(
        BusinessRuleFailure(
          'A batch\'s quantity cannot be changed here — record a stock movement instead.',
          rule: 'quantityRequiresMovement',
        ),
      );
    }

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing.createdAt,
      clock: _clock,
    );
    await _dao.updateMetadata(
      batchToCompanion(batch, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );
    return Result.ok(batch);
  }

  @override
  Future<Result<void, Failure>> detachFromDeletedTransaction(String batchId) async {
    await _dao.detachFromDeletedTransaction(
      batchId: batchId,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    await _dao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Stream<List<BatchReconciliation>> watchReconciliation() =>
      _dao.watchReconciliation().asyncMap(_mapReconciliations);

  @override
  Future<List<BatchReconciliation>> findDiscrepancies() async =>
      _mapReconciliations(await _dao.findDiscrepancies());

  @override
  Future<Result<void, Failure>> recompute(String batchId) async {
    await _dao.recomputeRemaining(batchId);
    return const Result.ok(null);
  }

  @override
  Future<Result<int, Failure>> recomputeAll() async {
    // Counted before repairing, not after: once every cache is rebuilt there are no discrepancies
    // left to count, so asking afterwards would always return zero and report that nothing was
    // wrong. The figure the Settings screen wants is how many were broken.
    final broken = await _dao.findDiscrepancies();
    await _dao.recomputeAll();
    return Result.ok(broken.length);
  }

  Future<List<BatchReconciliation>> _mapReconciliations(List<BatchStockCheckRow> rows) async {
    final categories = await _categories.categoriesFor(rows.map((r) => r.itemId));
    return rows
        .where((r) => categories.containsKey(r.itemId))
        .map((r) => r.toEntity(categories[r.itemId]!))
        .toList();
  }

  Future<List<Batch>> _mapAll(List<InventoryBatchRow> rows) async {
    final categories = await _categories.categoriesFor(rows.map((r) => r.itemId));
    return rows
        .where((r) => categories.containsKey(r.itemId))
        .map((r) => r.toEntity(categories[r.itemId]!))
        .toList();
  }
}
