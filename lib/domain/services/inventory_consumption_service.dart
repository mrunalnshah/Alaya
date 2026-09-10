import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/repositories/stock_repository.dart';
import 'package:alaya/domain/services/draw_policy.dart';

export 'package:alaya/domain/services/draw_policy.dart' show DrawPolicy;

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

  /// True when this batch has passed its expiry as of [today].
  ///
  /// **Strict: `expiry < today`.** A use-by of the 14th is usable on the 14th, which is what
  /// `v_calendar_events` already assumes — a batch expiring today appears as an upcoming event rather
  /// than as history.
  ///
  /// Deliberately the same one-line predicate as `Batch.isExpired`, and it must stay that way. This
  /// type cannot delegate to it because it holds four fields rather than a batch, and a projection
  /// that could not answer for itself would push the question back onto every caller.
  bool isExpired(DateKey today) {
    final expiry = expiryDateKey;
    return expiry != null && expiry < today;
  }
}

/// A consumption that can be carried out: which batches to draw from, and how much from each.
class ConsumptionPlan {
  /// Creates a plan.
  const ConsumptionPlan({
    required this.draws,
    required this.totalAvailable,
    required this.fromExpired,
  });

  /// The draws, in the order they should be applied.
  final List<ConsumptionDraw> draws;

  /// Everything that was on hand when the plan was made, for the caller's messaging.
  ///
  /// Counts only what the policy would consider: under a policy excluding expired stock this is the
  /// good stock alone, which is what makes the `insufficientStock` message match the refusal.
  final Qty totalAvailable;

  /// How much of this plan comes out of batches that are past their date.
  ///
  /// **What a confirmation prompt hangs on**, and a fact about the plan rather than about the shelf:
  /// there may be expired stock the plan never reaches, and warning about that would be warning about
  /// nothing. Always zero under a policy that is not expiry-aware, because that policy does not ask.
  final Qty fromExpired;

  /// How many movement rows applying this plan will write — exactly one per draw.
  int get movementCount => draws.length;

  /// Every batch this plan touches.
  Iterable<String> get touchedBatchIds => draws.map((d) => d.batchId);

  /// Whether any of this plan comes from stock past its date.
  bool get usesExpired => fromExpired.isPositive;
}

/// Plans stock consumption.
///
/// **Pure.** No I/O, no clock, no database — given a list of batches and a quantity it returns the
/// draws, and the caller writes them. That split is what lets `StockRepository.consume` guarantee
/// atomicity (all draws in one transaction) while this class guarantees correctness.
///
/// Phase 3C originally held this logic inside `StockRepositoryImpl._planDraws`, because no service
/// existed yet. It lives here now so there is one definition — the same consolidation Phase 4A made
/// for the currency cross-rate, and for the same reason: two copies of an ordering rule drift apart
/// and the second one is always the one that is wrong.
///
/// **The expiry-aware order was very nearly the third copy.** A separate `DrawPlanner` was written for
/// the cookability engine before this service was found, which is exactly the outcome the paragraph
/// above warns about. It lives here instead, as a [DrawPolicy] on the one definition.
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
      ..sort(_byNearestExpiry);
    return ordered;
  }

  /// Orders [batches] so good stock is spent before anything past its date on [today].
  ///
  /// Unexpired batches first in [orderFefo]'s own order, so cooking still burns down what is about to
  /// go off. Expired batches follow, least spoiled first. Batches holding nothing are dropped, as in
  /// [orderFefo].
  ///
  /// Returns every batch including the expired ones — excluding them is [plan]'s decision, because a
  /// caller needs to know how much expired stock exists in order to offer it.
  List<ConsumableBatch> orderFreshFirst(
    Iterable<ConsumableBatch> batches,
    DateKey today,
  ) {
    final fresh = <ConsumableBatch>[];
    final stale = <ConsumableBatch>[];
    for (final batch in batches) {
      if (!batch.remaining.isPositive) continue;
      (batch.isExpired(today) ? stale : fresh).add(batch);
    }
    fresh.sort(_byNearestExpiry);
    stale.sort(_byLeastSpoiled);
    return [...fresh, ...stale];
  }

  /// Orders [batches] according to [policy].
  List<ConsumableBatch> orderFor(
    Iterable<ConsumableBatch> batches,
    DrawPolicy policy,
  ) {
    final today = policy.today;
    return today == null ? orderFefo(batches) : orderFreshFirst(batches, today);
  }

  /// How much of [batches] a plan under [policy] could actually draw, in [category].
  ///
  /// **The number a refusal is allowed to quote.** A message naming a total the policy could not have
  /// reached would be arithmetic the user cannot reproduce — "only 250 g is on hand" beside a cupboard
  /// holding 550 g of which 300 g is off.
  Qty availableUnder(
    Iterable<ConsumableBatch> batches, {
    required DrawPolicy policy,
    required Qty ofCategory,
  }) {
    var milli = 0;
    for (final batch in batches) {
      if (!batch.remaining.isPositive) continue;
      if (!policy.admits(batch)) continue;
      milli += batch.remaining.milliBase;
    }
    return Qty(milli, ofCategory.category);
  }

  /// Plans drawing [needed] from [batches] under [policy].
  ///
  /// Fails with a [BusinessRuleFailure] carrying rule `insufficientStock` when the total on hand is
  /// less than [needed] — and returns **no draws at all** in that case, so a caller cannot
  /// accidentally apply a partial consumption. A ledger describing a consumption that only half
  /// happened is worse than one describing none of it, because nothing tells the user which half.
  ///
  /// Fails with a [ValidationFailure] on a non-positive quantity, and on a category mismatch
  /// between [needed] and any batch — a `Qty` in the wrong category is a bare integer that would be
  /// reinterpreted on read (Law L8).
  ///
  /// **The refusal is how a caller learns that consent would help.** Planning under
  /// `DrawPolicy.freshFirst(today: t)` and getting `insufficientStock`, then planning again with
  /// `allowExpired: true` and succeeding, is the difference between "you are short" and "you are short
  /// of good stock" — two answers rather than three states on one object, so nothing has to carry a
  /// partial plan nobody may apply.
  Result<ConsumptionPlan, Failure> plan({
    required Iterable<ConsumableBatch> batches,
    required Qty needed,
    DrawPolicy policy = const DrawPolicy.fefo(),
  }) {
    if (!needed.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'The quantity to consume must be greater than zero.',
          field: 'needed',
        ),
      );
    }

    final ordered = orderFor(batches, policy);
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

    // Excluded rather than merely ordered last: a plan that must not touch expired stock must not
    // count it as available either, or the shortfall would quote a total the plan cannot reach.
    final usable = ordered.where(policy.admits).toList();
    final available = availableUnder(
      usable,
      policy: policy,
      ofCategory: needed,
    );
    if (available.milliBase < needed.milliBase) {
      return Result.failure(
        BusinessRuleFailure(
          'Not enough stock on hand to consume this quantity.',
          rule: 'insufficientStock',
        ),
      );
    }

    final today = policy.today;
    final draws = <ConsumptionDraw>[];
    var remaining = needed.milliBase;
    var expiredMilli = 0;
    for (final batch in usable) {
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
      if (today != null && batch.isExpired(today)) expiredMilli += take;
      remaining -= take;
    }

    return Result.ok(
      ConsumptionPlan(
        draws: draws,
        totalAvailable: available,
        fromExpired: Qty(expiredMilli, needed.category),
      ),
    );
  }

  /// Plans consuming everything left in [batches] — for "used it all up".
  ///
  /// Always FEFO: emptying a shelf has no reason to prefer good stock, and every batch is drawn
  /// regardless of order.
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

  /// Nearest expiry first, undated last, ties broken by purchase date.
  static int _byNearestExpiry(ConsumableBatch a, ConsumableBatch b) {
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
  }

  /// Most recent expiry first — least spoiled among batches already past their date.
  ///
  /// A null expiry cannot reach here: a batch with no date is never expired. The purchase tiebreak
  /// keeps the order deterministic, which matters because a plan shown in a confirmation and the plan
  /// applied a moment later must list equally-spoiled batches identically.
  static int _byLeastSpoiled(ConsumableBatch a, ConsumableBatch b) {
    final left = a.expiryDateKey;
    final right = b.expiryDateKey;
    if (left == null || right == null) {
      return DateKey.compare(a.purchasedDateKey, b.purchasedDateKey);
    }
    final byExpiry = DateKey.compare(right, left);
    return byExpiry != 0
        ? byExpiry
        : DateKey.compare(a.purchasedDateKey, b.purchasedDateKey);
  }
}
