import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';

/// One batch's cached remaining quantity against what its movement ledger says.
///
/// [discrepancy] must be zero for every batch, always. A non-zero one means the Law L3 cache has
/// drifted and needs repairing.
class BatchReconciliation {
  /// Creates a reconciliation result.
  const BatchReconciliation({
    required this.batchId,
    required this.cached,
    required this.fromLedger,
    required this.discrepancy,
  });

  /// The batch this describes.
  final String batchId;

  /// What the batch row currently claims is left.
  final Qty cached;

  /// What summing the movement ledger says is left.
  final Qty fromLedger;

  /// [cached] less [fromLedger].
  final Qty discrepancy;

  /// True when the cache agrees with the ledger.
  bool get isConsistent => discrepancy.isZero;
}

/// Reads and writes inventory batches.
abstract interface class BatchRepository {
  /// Emits the batches of [itemId] in FEFO order — nearest expiry first, undated batches last.
  ///
  /// The order stock is drawn down in (anomaly A08). Only batches with stock appear.
  Stream<List<Batch>> watchByItemFefo(String itemId);

  /// Reads the same FEFO-ordered list once — what a consumption run walks.
  Future<List<Batch>> byItemFefo(String itemId);

  /// Emits the batches of [itemId] in purchase order, for the expanded item detail which itemises
  /// rather than sums (ARCH_1 §5.4).
  Stream<List<Batch>> watchByItem(String itemId);

  /// Emits batches with stock expiring within `[from, to]`.
  Stream<List<Batch>> watchExpiringInRange({
    required DateKey from,
    required DateKey to,
  });

  /// Reads one batch by id, soft-deleted ones included.
  Future<Batch?> byId(String id);

  /// Creates a batch together with its founding movement.
  ///
  /// A batch never exists without one, or the reconciliation probe would report the new row as a
  /// permanent discrepancy of its own initial quantity.
  Future<Result<Batch, Failure>> create(Batch batch);

  /// Updates a batch's display metadata — location, note, expiry, cost.
  ///
  /// Cannot change the quantity: that only ever moves by recording a movement, so
  /// `StockRepository` owns it.
  Future<Result<Batch, Failure>> updateMetadata(Batch batch);

  /// Marks a batch detached when its source transaction is deleted (anomaly A10).
  Future<Result<void, Failure>> detachFromDeletedTransaction(String batchId);

  /// Soft-deletes a batch. Its movements are untouched.
  Future<Result<void, Failure>> delete(String id);

  /// Emits every batch's cache-versus-ledger reconciliation.
  Stream<List<BatchReconciliation>> watchReconciliation();

  /// Reads only the batches whose cache disagrees with their ledger — the Settings screen's
  /// "N batches need repair" count.
  Future<List<BatchReconciliation>> findDiscrepancies();

  /// Rebuilds one batch's cached quantity from its movement history — the Law L3 repair path.
  Future<Result<void, Failure>> recompute(String batchId);

  /// Rebuilds every batch's cached quantity — the Settings "repair stock" action.
  Future<Result<int, Failure>> recomputeAll();
}