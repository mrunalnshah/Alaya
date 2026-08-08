import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/stock_movement.dart';

/// One batch's share of a consumption run, and how much came out of it.
class ConsumptionDraw {
  /// Creates a draw.
  const ConsumptionDraw({required this.batchId, required this.quantity});

  /// The batch drawn from.
  final String batchId;

  /// How much came out of it.
  final Qty quantity;
}

/// What a waste query totalled, in both quantity and money.
///
/// The differentiating insight of ARCH_3 §5.1 query 14 — costs are grouped by currency rather than
/// summed across them (anomaly A34).
class WasteTotal {
  /// Creates a waste total.
  const WasteTotal({
    required this.itemId,
    required this.quantity,
    required this.costByCurrency,
  });

  /// The item wasted.
  final String itemId;

  /// How much was wasted.
  final Qty quantity;

  /// What it cost, per currency code.
  final Map<String, Money> costByCurrency;
}

/// Records stock movements and reads the ledger.
///
/// Every write here pairs a movement with the batch cache update in one transaction (Laws L3, L14).
/// There is deliberately **no delete and no edit**: a correction is a reversing movement, because a
/// ledger you can edit is not a ledger (Law L6's stated exception).
abstract interface class StockRepository {
  /// Consumes [quantity] of [itemId] in FEFO order, across as many batches as needed.
  ///
  /// Returns which batches were drawn from and by how much, so the UI can show that 600 g came out
  /// of two batches *before* confirming (anomaly A08).
  ///
  /// Fails with a [BusinessRuleFailure] when total stock is insufficient, writing nothing — a
  /// partial consumption would leave the ledger describing something that did not happen.
  Future<Result<List<ConsumptionDraw>, Failure>> consume({
    required String itemId,
    required Qty quantity,
    required StockMovementKind kind,
    String? reason,
    String? note,
  });

  /// Consumes [quantity] from one specific batch, overriding FEFO for when the user knows better.
  Future<Result<void, Failure>> consumeFromBatch({
    required String batchId,
    required Qty quantity,
    required StockMovementKind kind,
    String? reason,
    String? note,
  });

  /// Adds stock to an existing batch.
  Future<Result<void, Failure>> addStock({
    required String batchId,
    required Qty quantity,
    required StockMovementKind kind,
    String? note,
  });

  /// Reverses [movementId] by recording a compensating movement that points at it.
  ///
  /// This is what undo does. The user sees "removed"; the audit trail keeps both rows, so waste
  /// analytics stays honest.
  Future<Result<void, Failure>> reverse({
    required String movementId,
    String? reason,
  });

  /// Emits the movements for [batchId], oldest first — a batch's full history.
  Stream<List<StockMovement>> watchForBatch(String batchId);

  /// Emits the movements for [itemId] within `[from, to]`, newest first.
  Stream<List<StockMovement>> watchForItemInRange({
    required String itemId,
    required DateKey from,
    required DateKey to,
  });

  /// Totals waste and expiry for every item within `[from, to]`.
  Future<List<WasteTotal>> wasteTotals({
    required DateKey from,
    required DateKey to,
  });
}