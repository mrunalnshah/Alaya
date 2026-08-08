import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/repositories/stock_repository.dart';

/// The facts consumption needs about one batch, and nothing else.
///
/// A narrow input rather than the full `Batch` entity: FEFO needs four fields, and taking twelve
/// would couple the algorithm to every unrelated change to a batch. It also means the whole engine
/// is exercisable from literals — which is why `consumption_test.dart` needs no database.
class ConsumableBatch {
  /// Creates an input row.
  const ConsumableBatch({
    required this.batchId,
    required this.remaining,
    required this.purchasedDateKey,
    this.expiryDateKey,
  });

  /// Builds an input row from a domain [Batch].
  factory ConsumableBatch.fromBatch(Batch batch) => ConsumableBatch(
    batchId: batch.id,
    remaining: batch.remainingQuantity,
    purchasedDateKey: batch.purchasedDateKey,
    expiryDateKey: batch.expiryDateKey,
  );

  /// The batch.
  final String batchId;

  /// How much is left in it.
  final Qty remaining;

  /// When it was acquired — the tiebreaker between two batches expiring on the same date.
  final DateKey purchasedDateKey;

  /// When it expires, or null if it does not.
  final DateKey? expiryDateKey;
}

/// A consumption that can be carried out: which batches to draw from, and how much from each.
class ConsumptionPlan {
  /// Creates a plan.
  const ConsumptionPlan({required this.draws, required this.totalAvailable});

  /// The draws, in the order they should be applied.
  final List<ConsumptionDraw> draws;

  /// Everything that was on hand when the plan was made, for the caller's messaging.
  final Qty totalAvailable;

  /// How many movement rows applying this plan will write — exactly one per draw.
  int get movementCount => draws.length;

  /// Every batch this plan touches.
  Iterable<String> get touchedBatchIds => draws.map((d) => d.batchId);
}

/// Plans stock consumption in FEFO order.
///
/// **Pure.** No I/O, no clock, no database — given a list of batches and a quantity it returns the
/// draws, and the caller writes them. That split is what lets `StockRepository.consume` guarantee
/// atomicity (all draws in one transaction) while this class guarantees correctness.
///
/// Phase 3C originally held this logic inside `StockRepositoryImpl._planDraws`, because no service
/// existed yet. It lives here now so there is one definition — the same consolidation Phase 4A made
/// for the currency cross-rate, and for the same reason: two copies of an ordering rule drift apart
/// and the second one is always the one that is wrong.
final class InventoryConsumptionService {
  /// Creates the service.
  const InventoryConsumptionService();

  /// Orders [batches] as stock should be drawn down: nearest expiry first, undated batches last,
  /// ties broken by purchase date.
  ///
  /// Undated stock goes last rather than first because it is the stock that *cannot* spoil on a
  /// deadline — drawing it down first would leave the dated stock to expire, which is precisely the
  /// waste this ordering exists to prevent (anomaly A08). Batches holding nothing are dropped: a
  /// zero draw would trip `stock_movements`' `CHECK (quantity_milli > 0)` and, worse, would record
  /// that nothing moved.
  ///
  /// Sorting happens here rather than being assumed of the caller. The DAO also returns FEFO order
  /// from SQL, where an index can serve it — but a pure function that trusts its input's order is a
  /// function whose correctness depends on something it cannot see.
  List<ConsumableBatch> orderFefo(Iterable<ConsumableBatch> batches) {
    final ordered = batches.where((b) => b.remaining.isPositive).toList()
      ..sort((a, b) {
        // `expiryDateKey == null` sorts after any date. SQLite's NULLS LAST is not portable, so the
        // DAO expresses this as `expiry IS NULL` ascending; this is the Dart twin of that.
        final aUndated = a.expiryDateKey == null;
        final bUndated = b.expiryDateKey == null;
        if (aUndated != bUndated) return aUndated ? 1 : -1;
        if (!aUndated) {
          final byExpiry = DateKey.compare(a.expiryDateKey!, b.expiryDateKey!);
          if (byExpiry != 0) return byExpiry;
        }
        return DateKey.compare(a.purchasedDateKey, b.purchasedDateKey);
      });
    return ordered;
  }

  /// Plans drawing [needed] from [batches].
  ///
  /// Fails with a [BusinessRuleFailure] carrying rule `insufficientStock` when the total on hand is
  /// less than [needed] — and returns **no draws at all** in that case, so a caller cannot
  /// accidentally apply a partial consumption. A ledger describing a consumption that only half
  /// happened is worse than one describing none of it, because nothing tells the user which half.
  ///
  /// Fails with a [ValidationFailure] on a non-positive quantity, and on a category mismatch
  /// between [needed] and any batch — a `Qty` in the wrong category is a bare integer that would be
  /// reinterpreted on read (Law L8).
  Result<ConsumptionPlan, Failure> plan({
    required Iterable<ConsumableBatch> batches,
    required Qty needed,
  }) {
    if (!needed.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'The quantity to consume must be greater than zero.',
          field: 'needed',
        ),
      );
    }

    final ordered = orderFefo(batches);
    for (final batch in ordered) {
      if (batch.remaining.category != needed.category) {
        return Result.failure(
          ValidationFailure(
            'Batch ${batch.batchId} is measured in ${batch.remaining.category.name}, not '
            '${needed.category.name}.',
            field: 'needed',
          ),
        );
      }
    }

    final availableMilli = ordered.fold<int>(
      0,
      (sum, batch) => sum + batch.remaining.milliBase,
    );
    final available = Qty(availableMilli, needed.category);
    if (availableMilli < needed.milliBase) {
      return Result.failure(
        BusinessRuleFailure(
          'Not enough stock on hand to consume this quantity.',
          rule: 'insufficientStock',
        ),
      );
    }

    final draws = <ConsumptionDraw>[];
    var remaining = needed.milliBase;
    for (final batch in ordered) {
      if (remaining <= 0) break;
      final take = remaining < batch.remaining.milliBase
          ? remaining
          : batch.remaining.milliBase;
      if (take <= 0) continue;
      draws.add(
        ConsumptionDraw(
          batchId: batch.batchId,
          quantity: Qty(take, needed.category),
        ),
      );
      remaining -= take;
    }

    return Result.ok(ConsumptionPlan(draws: draws, totalAvailable: available));
  }

  /// Plans consuming everything left in [batches] — for "used it all up".
  Result<ConsumptionPlan, Failure> planAll({
    required Iterable<ConsumableBatch> batches,
    required Qty zeroOfCategory,
  }) {
    final ordered = orderFefo(batches);
    final total = ordered.fold<int>(0, (sum, b) => sum + b.remaining.milliBase);
    if (total <= 0) {
      return const Result.failure(
        BusinessRuleFailure(
          'There is nothing on hand to consume.',
          rule: 'insufficientStock',
        ),
      );
    }
    return plan(batches: ordered, needed: Qty(total, zeroOfCategory.category));
  }
}
