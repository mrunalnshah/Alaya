import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/domain/repositories/batch_repository.dart';

/// Decides whether a batch's cached quantity still matches its movement ledger, and what the cache
/// should be set to when it does not.
///
/// Law L3 permits exactly one stored derived total in the schema —
/// `inventory_batches.remaining_quantity_milli` — on the condition that it is reconstructible from
/// the append-only ledger at any time. This class is that reconstruction, and
/// `v_batch_stock_check` is the database's own independent statement of the same sum.
///
/// **The formula is duplicated on purpose, and that is the whole point.** Two independent
/// computations that must agree is a check; one computation used twice is not. If they ever diverge,
/// the view is authoritative for *detection* and this class for *repair* — and a divergence between
/// them is itself a bug worth failing a test over. `StockMovementDao.incomingKinds` is the single
/// shared definition of direction, so the two can only differ by arithmetic, not by disagreeing
/// about which way a `waste` moves stock.
final class StockReconciler {
  /// Creates the reconciler.
  const StockReconciler();

  /// Whether [kind] increases stock.
  ///
  /// Mirrors `v_batch_stock_check`'s `CASE WHEN m.kind IN ('openingIn','purchaseIn','manualIn',
  /// 'adjustIn')` exactly. A reversal needs no special case: a reversing `adjustIn` cancels the
  /// `consume` it points at simply by summing with the opposite sign.
  bool isIncoming(StockMovementKind kind) => switch (kind) {
    StockMovementKind.openingIn ||
    StockMovementKind.purchaseIn ||
    StockMovementKind.manualIn ||
    StockMovementKind.adjustIn => true,
    StockMovementKind.consume ||
    StockMovementKind.waste ||
    StockMovementKind.expired ||
    StockMovementKind.adjustOut => false,
  };

  /// The remaining quantity [movements] imply, in milli-base units.
  ///
  /// Absolute rather than a delta: it reads the whole history and returns what the cache *should*
  /// be, so a repair self-heals even if the cache had already drifted before the repair ran.
  int remainingFromLedgerMilli(Iterable<StockMovement> movements) {
    var total = 0;
    for (final movement in movements) {
      total += isIncoming(movement.kind)
          ? movement.quantity.milliBase
          : -movement.quantity.milliBase;
    }
    return total;
  }

  /// Reconciles one batch's [cached] quantity against [movements].
  BatchReconciliation reconcile({
    required String batchId,
    required Qty cached,
    required Iterable<StockMovement> movements,
  }) {
    final fromLedgerMilli = remainingFromLedgerMilli(movements);
    final category = cached.category;
    return BatchReconciliation(
      batchId: batchId,
      cached: cached,
      fromLedger: Qty(fromLedgerMilli, category),
      discrepancy: Qty(cached.milliBase - fromLedgerMilli, category),
    );
  }

  /// The batches among [reconciliations] whose cache disagrees with their ledger.
  ///
  /// Both signs count. A cache *below* the ledger is as wrong as one above it — it would hide stock
  /// the user actually has, which is the harder error to notice.
  List<BatchReconciliation> discrepancies(
    Iterable<BatchReconciliation> reconciliations,
  ) => reconciliations.where((r) => !r.isConsistent).toList();

  /// A one-line summary for the Settings repair screen.
  ReconciliationSummary summarise(
    Iterable<BatchReconciliation> reconciliations,
  ) {
    final all = reconciliations.toList();
    final broken = discrepancies(all);
    return ReconciliationSummary(
      batchesChecked: all.length,
      batchesNeedingRepair: broken.length,
      largestDiscrepancy: broken.isEmpty
          ? null
          : broken
                .map((r) => r.discrepancy)
                .reduce(
                  (a, b) => a.milliBase.abs() >= b.milliBase.abs() ? a : b,
                ),
    );
  }

  /// A zero quantity in [category], for reconciling a batch with no movements at all.
  Qty zeroIn(UnitCategory category) => Qty(0, category);
}

/// What a reconciliation pass found.
class ReconciliationSummary {
  /// Creates a summary.
  const ReconciliationSummary({
    required this.batchesChecked,
    required this.batchesNeedingRepair,
    this.largestDiscrepancy,
  });

  /// How many batches were examined.
  final int batchesChecked;

  /// How many disagreed with their ledger.
  final int batchesNeedingRepair;

  /// The biggest disagreement by absolute size, or null when everything agreed.
  final Qty? largestDiscrepancy;

  /// True when every batch's cache matched its ledger.
  bool get isHealthy => batchesNeedingRepair == 0;
}
