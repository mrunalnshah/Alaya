import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';

/// One batch, and how much this plan would take from it.
final class DrawLine {
  /// Creates a line.
  const DrawLine({
    required this.batch,
    required this.amount,
    required this.isExpired,
  });

  /// The batch drawn from.
  final Batch batch;

  /// How much comes out of it. Never more than the batch holds.
  final Qty amount;

  /// Whether this batch was past its date on the day the plan was made.
  ///
  /// Carried on the line rather than recomputed by the reader, so a screen showing the plan and the
  /// repository executing it cannot disagree about which batches were the expired ones — the reader
  /// would need `today` to work it out again, and a second `today` is a second answer.
  final bool isExpired;
}

/// What a consumption would actually do, before it does it.
///
/// **The read that anomaly A08 asked for and the contract could not provide.**
/// `StockRepository.consume` already returns which batches it drew from — but *after* writing, so
/// "show that 600 g came out of two batches before confirming" was unimplementable. A plan is that
/// same answer, computed from batches and taking nothing.
final class DrawPlan {
  /// Creates a plan.
  const DrawPlan({
    required this.needed,
    required this.lines,
    required this.drawnMilli,
    required this.fromExpiredMilli,
    required this.expiredUntouchedMilli,
  });

  /// A plan that draws nothing, for a request of zero or less.
  const DrawPlan.nothing(this.needed)
    : lines = const [],
      drawnMilli = 0,
      fromExpiredMilli = 0,
      expiredUntouchedMilli = 0;

  /// How much was asked for.
  final Qty needed;

  /// The batches to draw from, in the order to draw them.
  final List<DrawLine> lines;

  /// How much the lines add up to.
  final int drawnMilli;

  /// How much of [drawnMilli] comes out of expired batches.
  final int fromExpiredMilli;

  /// Expired stock this plan does **not** touch.
  ///
  /// The headroom that makes [couldCompleteWithExpired] answerable: when a plan falls short with
  /// expired stock excluded, this is what saying yes would unlock. Without it the caller would have
  /// to re-scan the batches to find out, which is the second opinion this type exists to prevent.
  final int expiredUntouchedMilli;

  /// How much the lines add up to.
  Qty get drawn => Qty(drawnMilli, needed.category);

  /// How much comes from expired batches.
  Qty get fromExpired => Qty(fromExpiredMilli, needed.category);

  /// How much is still missing. Zero when the plan is complete.
  Qty get shortfall => Qty(
    drawnMilli >= needed.milliBase ? 0 : needed.milliBase - drawnMilli,
    needed.category,
  );

  /// Whether this plan covers what was asked for.
  bool get isComplete => drawnMilli >= needed.milliBase;

  /// Whether any of it comes from expired stock.
  ///
  /// **This is what a confirmation prompt hangs on**, and it is a fact about the plan rather than a
  /// question about the shelf: there may be expired stock the plan never reaches, and warning about
  /// that would be warning about nothing.
  bool get usesExpired => fromExpiredMilli > 0;

  /// Whether saying yes to expired stock would make this plan complete.
  ///
  /// False when the plan already works, and false when even the expired stock is not enough — in
  /// which case there is nothing to offer and the honest answer is a shortfall.
  bool get couldCompleteWithExpired =>
      !isComplete && expiredUntouchedMilli >= shortfall.milliBase;
}

/// Decides which batches a consumption should draw from, and in what order.
///
/// Pure: entities in, a plan out. No repository, no clock, no Flutter — the same shape as
/// `CookabilityEngine`, and for the same reason. Three callers need this answer and they must not
/// each derive it: the engine to judge a recipe, a confirmation sheet to describe what will happen,
/// and the repository to carry it out. **Two of those disagreeing about the same recipe is the
/// failure ARCH_M §6 names** — no value displayed from a second source.
///
/// ## Why this is not FEFO
///
/// `BatchRepository.watchByItemFefo` orders by nearest expiry first, undated last — and an expired
/// date *is* the nearest date, so FEFO hands out expired stock before anything else. That is right
/// for a waste write-off and wrong for cooking, which is the whole of the reported problem: the
/// deduction was not misbehaving, it was following a policy chosen for a different purpose.
///
/// So the order here is:
///
/// 1. **Unexpired, soonest expiry first**, undated last — FEFO among the food that is still good, so
///    cooking still burns down what is about to go off.
/// 2. **Expired, least spoiled first**, and only when the caller permits it. Strict FEFO would reach
///    for the *oldest* expired batch, which is the most spoiled thing in the house; among food that
///    is already past its date, nearest-to-fresh is the only defensible order.
///
/// **The existing FEFO path is deliberately untouched.** A waste or expiry movement should still
/// take the worst batch first, and nothing here changes that — there is no policy enum because
/// nothing needs a second order yet.
final class DrawPlanner {
  /// Creates the planner. Stateless.
  const DrawPlanner();

  /// Plans a draw of [needed] from [batches] as of [today].
  ///
  /// [batches] may arrive in any order; this sorts. Batches holding nothing are skipped, so a caller
  /// can pass an item's whole history without filtering.
  ///
  /// [allowExpired] false is the default and the safe one: the plan then reports a shortfall it could
  /// have covered, which is exactly the state a confirmation prompt needs to describe.
  ///
  /// Throws when a batch's category differs from [needed]'s. That means the caller skipped the
  /// volume-to-weight bridge, and quietly dropping the batch would report a shortfall for stock that
  /// is sitting on the shelf.
  DrawPlan plan({
    required List<Batch> batches,
    required Qty needed,
    required DateKey today,
    bool allowExpired = false,
  }) {
    if (needed.milliBase <= 0) return DrawPlan.nothing(needed);

    final fresh = <Batch>[];
    final stale = <Batch>[];
    for (final batch in batches) {
      if (!batch.hasStock) continue;
      if (batch.remainingQuantity.category != needed.category) {
        throw ArgumentError.value(
          batch.id,
          'batches',
          'batch is ${batch.remainingQuantity.category.name} but '
              '${needed.category.name} was asked for — bridge the requirement first',
        );
      }
      (batch.isExpired(today) ? stale : fresh).add(batch);
    }

    fresh.sort(_soonestFirst);
    stale.sort(_leastSpoiledFirst);

    final lines = <DrawLine>[];
    var drawn = 0;
    var fromExpired = 0;

    for (final batch in [...fresh, if (allowExpired) ...stale]) {
      final outstanding = needed.milliBase - drawn;
      if (outstanding <= 0) break;
      final available = batch.remainingQuantity.milliBase;
      final take = available < outstanding ? available : outstanding;
      final expired = batch.isExpired(today);
      lines.add(
        DrawLine(
          batch: batch,
          amount: Qty(take, needed.category),
          isExpired: expired,
        ),
      );
      drawn += take;
      if (expired) fromExpired += take;
    }

    var expiredTotal = 0;
    for (final batch in stale) {
      expiredTotal += batch.remainingQuantity.milliBase;
    }

    return DrawPlan(
      needed: needed,
      lines: lines,
      drawnMilli: drawn,
      fromExpiredMilli: fromExpired,
      expiredUntouchedMilli: expiredTotal - fromExpired,
    );
  }

  /// Soonest expiry first, undated last — the order `watchByItemFefo` documents.
  ///
  /// A batch with no expiry sorts last because it is the one thing that cannot go off: spending it
  /// ahead of something dated would waste the dated one.
  static int _soonestFirst(Batch a, Batch b) {
    final left = a.expiryDateKey;
    final right = b.expiryDateKey;
    if (left == null && right == null) return a.id.compareTo(b.id);
    if (left == null) return 1;
    if (right == null) return -1;
    final byExpiry = left.compareTo(right);
    // **Ties break on id, and the tie-break is not cosmetic.** Two batches expiring on the same day
    // are equally good choices, but a plan shown to the user and a plan executed a second later must
    // list them in the same order or the confirmation described something else.
    return byExpiry != 0 ? byExpiry : a.id.compareTo(b.id);
  }

  /// Least spoiled first — the most recent expiry among batches already past it.
  ///
  /// The reverse of [_soonestFirst], and deliberately not FEFO. A null expiry cannot appear here: a
  /// batch with no date is never expired.
  static int _leastSpoiledFirst(Batch a, Batch b) {
    final left = a.expiryDateKey;
    final right = b.expiryDateKey;
    if (left == null || right == null) return a.id.compareTo(b.id);
    final byExpiry = right.compareTo(left);
    return byExpiry != 0 ? byExpiry : a.id.compareTo(b.id);
  }
}
