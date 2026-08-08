# Phase 4B — Stock Consumption, Low-Stock Suggestions, Recurring Schedule & Purchase Fan-Out

> **Regenerated 2026-08-02 from the canonical tree.** Every fix through the Phase 6C debugging
> pass is folded in; this document and the working tree are in sync, and regenerating from it
> reproduces the code that runs. Earlier revisions reintroduce defects listed in ARCH_6 §3.
>
> Files shared with other phase documents — `app_en.arb`, `routes.dart`, `app_router.dart`,
> `layout_overflow_test.dart`, and the Phase 6A editor files amended by 6B and 6C — carry
> **identical** content in every copy, so they may be applied in any order.

**5 services · 2 test files · 1185 lines of tests · 2 more duplications removed · 1 genuinely new
subsystem.**

## Add dependencies

None. Every import resolves to packages already present.

## Note on my sandbox, not your project

My working copy had lost files between sessions — all of Phase 4A's services, three 3C/3D
repositories, and every `.drift` view. **Your project is unaffected**; the delivered markdown is what
you applied. I restored 173 files from it before writing anything, because auditing an incomplete
tree gives false confidence rather than none. Post-restore the Phase 4A audit reproduced exactly
(142 files, zero import/balance/L12 problems), so the restore was faithful. Last turn's
`syncDailyRates` patch post-dates that assembly, so I re-applied it too.

## Two more duplications removed

Same pattern as Phase 4A's currency cross-rate, and the same reason. Phases 3C and 3D put this
logic in repositories because no services existed yet:

| Logic | Was | Now |
|---|---|---|
| FEFO ordering and draw-down | `StockRepositoryImpl._planDraws` | `InventoryConsumptionService`, repository delegates |
| Interval arithmetic + month-end clamp | `RecurringRepositoryImpl._advance` / `_clampDay` | `RecurringEngine.nextDue` / `clampDayOfMonth`, repository delegates |
| The 240-occurrence safety bound | a private `_maxOccurrencesPerPass` const | `RecurringEngine.maxOccurrencesPerPass` |

The clamp is the one that mattered most to consolidate. Anomaly A13 is precisely the kind of rule
that must not exist twice, because the second copy is the one that walks a bill permanently backwards
after a single February — and nothing would notice until March.

**`PurchaseFanOutService` is genuinely new.** The `created*Id` columns existed from Phase 1B and the
*detach* path from 3B, but nothing ever populated them. A purchase line's `destination` had no
consumer until now.

## The required tests, and what each actually asserts

Every service is **pure**, so both test files run with no database, no mocks and no fakes.

**FEFO — the three batches given exactly as specified, and deliberately in an order where neither
the nearest expiry nor the undated batch is first**, so a service that trusted input order would
fail. Consuming 600 g draws `300 g` from the 05 Aug batch then `300 g` from the 10 Aug batch,
`movementCount == 2`, and the no-expiry batch is asserted absent from `touchedBatchIds`. I verified my
actual comparator against every one of those assertions, plus two tiebreaks the spec did not name:
two batches expiring the same day order by purchase date, and two *undated* batches do too rather
than being left arbitrary.

**Over-consumption fails with no partial writes.** One milli-gram beyond the 1800 g on hand returns a
`BusinessRuleFailure` with rule `insufficientStock` — and `valueOrNull` is `null`, so there is no
draw list a caller could apply half of. That is asserted separately from the failure itself, because
"it failed" and "it produced nothing to apply" are different guarantees.

**Month-end clamp: `20260131 → 20260228 → 20260331 → 20260430`.** There is a test whose only job is
the mechanism — it advances *from the clamped 28th* and asserts the result is the 31st, which is what
proves the anchor is clamped rather than the current day. Plus the leap year (`20240229`), a full
twelve-month walk asserting every 31-day month gets its 31st back, and a yearly template anchored on
29 Feb that clamps for three years and recovers on the fourth.

**Lazy materialisation: exactly 3 occurrences, zero transactions.** The zero-transactions guarantee
is structural rather than asserted — `MaterialisationPlan` has no field a transaction could go in, so
a materialisation pass cannot create money even by mistake. Re-running with those dates present plans
nothing *and leaves the cursor identical*, which is the assertion that actually proves idempotency.

**Low-stock idempotency: five runs, one entry.** The loop feeds each run's would-be write back as the
next run's input, so run 1 creates and runs 2–5 refresh — never a second create. Then the entry is
promoted to `manual` and a sixth run returns `leaveAlone` with `suggestedQuantity == null`, so there
is nothing that *could* overwrite the user's edit.

**Fan-out: `destination=asset` creates an Asset and `batch` is asserted `null`.** Plus the converse
(`inventory` creates a batch and no asset), `none` creating neither, and `planAll` skipping lines that
already carry a `created*Id` so a retry after a partial failure is safe.

## Verification performed

| Check | Result |
|---|---|
| The six specified scenarios, verified numerically before writing | 6/6 |
| FEFO comparator vs every required assertion | verified, plus 2 unnamed tiebreaks |
| Brace balance | 149 files, 0 |
| Missing imports — exhaustive, 149 files vs 238 types | 0 |
| Unused imports | 0 |
| `final` double-init | 0 |
| `const` with runtime interpolation | 0 |
| `DateTime.now()` in a service | 0 |
| **L12** — `domain/` importing flutter, drift or `data/` | 0 |
| `Qty` debug `toString` in user-facing text | 0 |
| Sandbox restore fidelity | Phase 4A audit reproduced exactly |

## Findings

**`orderFefo` sorts rather than trusting its caller, even though the DAO also returns FEFO order.**
The DAO's ordering is where an index can serve it and stays; but a pure function whose correctness
depends on the order of input it cannot see is a function that will eventually be called with
something else. The test passes the batches deliberately unsorted for that reason.

**Undated stock is drawn down *last*, and that is the non-obvious direction.** It is the stock that
cannot spoil on a deadline, so taking it first would leave the dated stock to expire — which is the
waste the ordering exists to prevent (anomaly A08).

**`StockReconciler` duplicates `v_batch_stock_check`'s formula on purpose.** Two independent
computations that must agree is a check; one computation used twice is not. The view is authoritative
for *detection* and the reconciler for *repair*, and a divergence between them is itself a bug worth
failing a test over. They share only `StockMovementDao.incomingKinds`, so they can differ by
arithmetic but never by disagreeing about which way a `waste` moves stock. The kind-classification
test is exhaustive against `StockMovementKind.values.length`, so adding a kind fails the suite until
it is classified.

**A cache *below* the ledger is treated as a discrepancy too**, and there is a test for it. It hides
stock the user actually has, which is the harder error to notice than a phantom surplus.

**A dismissal is not a timer, and a snooze is.** Dismissed-and-stock-fell-further stays suppressed —
they declined this shortage, and a worse one is the same shortage. It returns only once stock rises
*above* the reading taken at dismissal, which can only happen if they bought some (anomaly A23). A
snooze genuinely is a date, because the user asked to be reminded later rather than saying no. Both
paths have tests.

**A dismissed entry with no stored stock reading stays suppressed.** The recovery condition cannot be
evaluated, and a suggestion that never returns is a missing nudge whereas one returning on every
foreground is the nag the rule exists to prevent.

**Fan-out refuses rather than guesses.** An inventory line without a quantity fails — a batch with a
guessed quantity is stock the user never bought. An asset gets `AssetType.other` rather than a keyword
guess from the description; classifying "LG 55 inch" as `electronics` would be wrong often enough to
matter, and the asset editor asks anyway.

**`destination=recurring` returns a *name*, not a template.** A schedule needs an interval and an
anchor that a receipt line does not contain, and defaulting to monthly-on-the-1st would create
obligations the user never agreed to. The caller opens the editor pre-filled.

**`FanOutPlan.isWellFormed` exists because "at most one artefact" is the invariant the class is
for.** A line producing both a batch and an asset would make "what did this purchase create"
unanswerable — anomaly A12 — so the plan can assert its own shape.



---

### `lib/domain/services/inventory_consumption_service.dart`

```dart
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
        ValidationFailure('The quantity to consume must be greater than zero.', field: 'needed'),
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

    final availableMilli =
        ordered.fold<int>(0, (sum, batch) => sum + batch.remaining.milliBase);
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
      final take = remaining < batch.remaining.milliBase ? remaining : batch.remaining.milliBase;
      if (take <= 0) continue;
      draws.add(
        ConsumptionDraw(batchId: batch.batchId, quantity: Qty(take, needed.category)),
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
        BusinessRuleFailure('There is nothing on hand to consume.', rule: 'insufficientStock'),
      );
    }
    return plan(batches: ordered, needed: Qty(total, zeroOfCategory.category));
  }
}
```

### `lib/domain/services/stock_reconciler.dart`

```dart
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
        StockMovementKind.adjustIn =>
          true,
        StockMovementKind.consume ||
        StockMovementKind.waste ||
        StockMovementKind.expired ||
        StockMovementKind.adjustOut =>
          false,
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
  List<BatchReconciliation> discrepancies(Iterable<BatchReconciliation> reconciliations) =>
      reconciliations.where((r) => !r.isConsistent).toList();

  /// A one-line summary for the Settings repair screen.
  ReconciliationSummary summarise(Iterable<BatchReconciliation> reconciliations) {
    final all = reconciliations.toList();
    final broken = discrepancies(all);
    return ReconciliationSummary(
      batchesChecked: all.length,
      batchesNeedingRepair: broken.length,
      largestDiscrepancy: broken.isEmpty
          ? null
          : broken
              .map((r) => r.discrepancy)
              .reduce((a, b) => a.milliBase.abs() >= b.milliBase.abs() ? a : b),
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
```

### `lib/domain/services/low_stock_suggestion_engine.dart`

```dart
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';

/// What the engine decided to do about one item.
enum SuggestionAction {
  /// No auto entry exists and stock is low — create one.
  create,

  /// An active auto entry exists — refresh its quantity and stock reading.
  refresh,

  /// Leave the entry entirely alone.
  ///
  /// Either the user has taken ownership of it (`origin` promoted to `manual`), or they dismissed or
  /// snoozed it and the condition that would bring it back has not been met.
  leaveAlone,
}

/// One decision, ready for the caller to write.
class SuggestionDecision {
  /// Creates a decision.
  const SuggestionDecision({
    required this.itemId,
    required this.action,
    required this.reason,
    this.existingEntryId,
    this.suggestedQuantity,
    this.stockAtDecision,
  });

  /// The item this concerns.
  final String itemId;

  /// What to do.
  final SuggestionAction action;

  /// Why, in words — surfaced in logs and useful when a user asks why something reappeared.
  final String reason;

  /// The entry to update, when [action] is [SuggestionAction.refresh].
  final String? existingEntryId;

  /// How much to buy — the shortfall against the threshold.
  final Qty? suggestedQuantity;

  /// The stock reading at the moment of the decision, stored so a later dismissal can be compared
  /// against it.
  final Qty? stockAtDecision;

  /// True when the caller needs to write something.
  bool get requiresWrite => action != SuggestionAction.leaveAlone;
}

/// Decides which low-stock shopping suggestions should exist.
///
/// **Pure and idempotent.** Given the same stock and the same existing entries it returns the same
/// decisions, however many times it runs — which is what makes regeneration safe to call from a
/// foreground hook. The idempotency is a property of this function, not of the database: the partial
/// unique index `idx_shopping_auto` is a backstop, and one that cannot serve as an `ON CONFLICT`
/// target anyway (ARCH_2 §11.1), so correctness has to live here.
///
/// Phase 3C held this inside `ShoppingRepositoryImpl.regenerateLowStockSuggestions`. It lives here
/// now so the rule has one definition and can be tested without a database.
final class LowStockSuggestionEngine {
  /// Creates the engine.
  const LowStockSuggestionEngine();

  /// Decides what to do for every item in [lowStock].
  ///
  /// [existingAutoEntries] should be every entry on the list already keyed to an item, whatever its
  /// origin or state — including ones promoted to `manual`, because those are precisely the ones
  /// that must be recognised and left alone.
  List<SuggestionDecision> decide({
    required Iterable<ItemStock> lowStock,
    required Iterable<ShoppingEntry> existingAutoEntries,
    required DateKey today,
  }) {
    final byItem = <String, ShoppingEntry>{};
    for (final entry in existingAutoEntries) {
      final itemId = entry.itemId;
      if (itemId != null) byItem[itemId] = entry;
    }

    final decisions = <SuggestionDecision>[];
    for (final stock in lowStock) {
      decisions.add(_decideFor(stock: stock, existing: byItem[stock.itemId], today: today));
    }
    return decisions;
  }

  SuggestionDecision _decideFor({
    required ItemStock stock,
    required ShoppingEntry? existing,
    required DateKey today,
  }) {
    final shortfall = stock.shortfall;
    if (shortfall == null || !shortfall.isPositive) {
      return SuggestionDecision(
        itemId: stock.itemId,
        action: SuggestionAction.leaveAlone,
        reason: 'Not low on stock, or no threshold set.',
      );
    }

    if (existing == null) {
      return SuggestionDecision(
        itemId: stock.itemId,
        action: SuggestionAction.create,
        reason: 'Low on stock and nothing suggested yet.',
        suggestedQuantity: shortfall,
        stockAtDecision: stock.totalRemaining,
      );
    }

    // The user has taken ownership. Editing an auto entry promotes its origin, and from that moment
    // the engine never touches it again — not its quantity, not its state (anomaly A22). Any other
    // behaviour would silently overwrite a deliberate edit on the next foreground.
    if (existing.origin != ShoppingEntryOrigin.autoLowStock) {
      return SuggestionDecision(
        itemId: stock.itemId,
        action: SuggestionAction.leaveAlone,
        reason: 'The user edited this entry, so it is theirs now.',
        existingEntryId: existing.id,
      );
    }

    if (existing.autoState != ShoppingEntryAutoState.active) {
      return _decideSuppressed(stock: stock, existing: existing, today: today, shortfall: shortfall);
    }

    return SuggestionDecision(
      itemId: stock.itemId,
      action: SuggestionAction.refresh,
      reason: 'Still low on stock; refreshing the suggested quantity.',
      existingEntryId: existing.id,
      suggestedQuantity: shortfall,
      stockAtDecision: stock.totalRemaining,
    );
  }

  /// Whether a dismissed or snoozed suggestion has earned its way back.
  ///
  /// A dismissal is not a timer. Bringing the entry back after N days would nag about a shortage the
  /// user already declined; never bringing it back would mean they stop being told after they
  /// restock and run out again. The condition is therefore the stock itself: it returns only once
  /// stock has risen **above** the reading taken when they dismissed it — which can only happen if
  /// they bought some — and then fallen below the threshold again (anomaly A23).
  ///
  /// A snooze additionally has a date, and that date genuinely is a timer: the user asked to be
  /// reminded later, rather than saying no.
  SuggestionDecision _decideSuppressed({
    required ItemStock stock,
    required ShoppingEntry existing,
    required DateKey today,
    required Qty shortfall,
  }) {
    if (existing.autoState == ShoppingEntryAutoState.snoozed) {
      final until = existing.snoozeUntilDateKey;
      if (until != null && today.isBefore(until)) {
        return SuggestionDecision(
          itemId: stock.itemId,
          action: SuggestionAction.leaveAlone,
          reason: 'Snoozed until ${until.toIso()}.',
          existingEntryId: existing.id,
        );
      }
      return SuggestionDecision(
        itemId: stock.itemId,
        action: SuggestionAction.refresh,
        reason: 'The snooze has expired and stock is still low.',
        existingEntryId: existing.id,
        suggestedQuantity: shortfall,
        stockAtDecision: stock.totalRemaining,
      );
    }

    final atDecision = existing.stockAtGeneration;
    if (atDecision == null) {
      // No reading was stored, so the recovery condition cannot be evaluated. Staying suppressed is
      // the safer default: a suggestion that never returns is a missing nudge, whereas one that
      // returns on every foreground is the nag this rule exists to prevent.
      return SuggestionDecision(
        itemId: stock.itemId,
        action: SuggestionAction.leaveAlone,
        reason: 'Dismissed, with no stock reading to compare against.',
        existingEntryId: existing.id,
      );
    }

    final recovered = stock.totalRemaining.milliBase > atDecision.milliBase;
    if (!recovered) {
      return SuggestionDecision(
        itemId: stock.itemId,
        action: SuggestionAction.leaveAlone,
        reason: 'Dismissed, and stock has not been replenished since.',
        existingEntryId: existing.id,
      );
    }
    return SuggestionDecision(
      itemId: stock.itemId,
      action: SuggestionAction.refresh,
      reason: 'Restocked after being dismissed, and low again.',
      existingEntryId: existing.id,
      suggestedQuantity: shortfall,
      stockAtDecision: stock.totalRemaining,
    );
  }
}
```

### `lib/domain/services/recurring_engine.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';

/// One occurrence a materialisation pass would create.
class PlannedOccurrence {
  /// Creates a planned occurrence.
  const PlannedOccurrence({required this.templateId, required this.dueDateKey});

  /// The template it belongs to.
  final String templateId;

  /// The civil date it is due on.
  final DateKey dueDateKey;
}

/// What one template's materialisation pass produced.
class MaterialisationPlan {
  /// Creates a plan.
  const MaterialisationPlan({
    required this.templateId,
    required this.occurrences,
    required this.nextDueDateKey,
    required this.stoppedAtSafetyBound,
  });

  /// The template.
  final String templateId;

  /// The occurrences to create, oldest first. **Every one is `due`** — never paid.
  final List<PlannedOccurrence> occurrences;

  /// Where `nextDueDateKey` should be left afterwards.
  final DateKey nextDueDateKey;

  /// True when the pass hit [RecurringEngine.maxOccurrencesPerPass] rather than reaching the target
  /// date, which means the template is almost certainly misconfigured.
  final bool stoppedAtSafetyBound;

  /// True when nothing needs writing.
  bool get isEmpty => occurrences.isEmpty;
}

/// The transaction shape settling an occurrence should create.
///
/// Returned rather than written, so the caller commits it through `TransactionRepository` and
/// inherits its shape validation and `monthKey` derivation instead of this service reimplementing
/// them.
class SettlementIntent {
  /// Creates an intent.
  const SettlementIntent({
    required this.kind,
    required this.subtype,
    required this.amount,
    required this.dateKey,
    required this.fromAccountId,
    required this.toAccountId,
    required this.templateId,
    required this.occurrenceId,
    this.payeeId,
    this.tagId,
    this.note,
  });

  /// Withdrawal for an outflow, deposit for an inflow.
  final TransactionKind kind;

  /// The analytics bucket.
  final TransactionSubtype subtype;

  /// The amount actually paid, which may differ from the template's default.
  final Money amount;

  /// The civil date it was paid on.
  final DateKey dateKey;

  /// Source account — set for an outflow, null for an inflow.
  final String? fromAccountId;

  /// Destination account — set for an inflow, null for an outflow.
  final String? toAccountId;

  /// The template being settled.
  final String templateId;

  /// The occurrence being settled.
  final String occurrenceId;

  /// The counterparty, carried from the template.
  final String? payeeId;

  /// The tag to apply, carried from the template.
  final String? tagId;

  /// The note to put on the transaction.
  final String? note;
}

/// Computes recurring schedules: the next due date, what to materialise, and what settling implies.
///
/// **Pure.** No clock, no database — every method takes the dates it needs. That is what makes the
/// month-end clamp testable against a fixed calendar rather than against whenever the suite happens
/// to run.
///
/// Phase 3D held `nextDue` and the materialisation loop inside `RecurringRepositoryImpl`. They live
/// here now for one definition, consolidated the same way Phase 4A consolidated the currency
/// cross-rate.
final class RecurringEngine {
  /// Creates the engine.
  const RecurringEngine();

  /// How many occurrences one pass will create per template before stopping.
  ///
  /// Twenty years of monthly, or eight months of daily, is past any honest backlog. Beyond it the
  /// template is misconfigured, and a device left unopened for two years should not materialise 700
  /// rows inside the startup path. The bound engages instead, and [MaterialisationPlan] says so.
  static const int maxOccurrencesPerPass = 240;

  /// The next due date after [from], per [template]'s interval.
  ///
  /// Day and week intervals are plain day arithmetic. Month and year intervals do calendar
  /// arithmetic and then clamp **the stored anchor** into the target month's real length — never the
  /// current day, which may itself already be clamped.
  ///
  /// That distinction is the whole of anomaly A13. A bill anchored on the 31st renders as the 28th in
  /// February and returns to the 31st in March. Advancing from the clamped 28th instead would walk it
  /// permanently backwards after a single February, and no later month would ever recover it.
  DateKey nextDue({required DateKey from, required RecurringTemplate template}) {
    final count = template.intervalCount;
    switch (template.intervalUnit) {
      case RecurringIntervalUnit.day:
        return from.addDays(count);
      case RecurringIntervalUnit.week:
        return from.addDays(7 * count);
      case RecurringIntervalUnit.month:
        final total = from.year * 12 + (from.month - 1) + count;
        final year = total ~/ 12;
        final month = total % 12 + 1;
        return DateKey.fromYmd(
          year,
          month,
          clampDayOfMonth(template.anchorDayOfMonth ?? from.day, year, month),
        );
      case RecurringIntervalUnit.year:
        final year = from.year + count;
        return DateKey.fromYmd(
          year,
          from.month,
          clampDayOfMonth(template.anchorDayOfMonth ?? from.day, year, from.month),
        );
    }
  }

  /// [day] limited to the last real day of `year-month`.
  ///
  /// Day zero of the following month is the last day of this one, which resolves February in both
  /// leap and non-leap years without a lookup table.
  int clampDayOfMonth(int day, int year, int month) {
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    return day < lastDay ? day : lastDay;
  }

  /// Plans every occurrence [template] owes up to and including [asOf].
  ///
  /// **Creates no money.** Every planned occurrence is `due`; only an explicit user tap settles one.
  /// An app unopened for three months plans three occurrences and zero transactions (anomaly A14).
  ///
  /// [alreadyMaterialised] makes the pass idempotent: dates already present are skipped while the
  /// cursor still advances past them, so running twice plans nothing the second time and leaves
  /// `nextDueDateKey` in the same place either way.
  MaterialisationPlan planMaterialisation({
    required RecurringTemplate template,
    required DateKey asOf,
    Iterable<DateKey> alreadyMaterialised = const [],
  }) {
    final existing = alreadyMaterialised.map((d) => d.value).toSet();
    final planned = <PlannedOccurrence>[];
    var cursor = template.nextDueDateKey;
    var guard = 0;
    var hitBound = false;

    while (!cursor.isAfter(asOf)) {
      if (guard >= maxOccurrencesPerPass) {
        hitBound = true;
        break;
      }
      guard++;

      final end = template.endDateKey;
      if (end != null && cursor.isAfter(end)) break;

      if (!existing.contains(cursor.value)) {
        planned.add(PlannedOccurrence(templateId: template.id, dueDateKey: cursor));
      }
      cursor = nextDue(from: cursor, template: template);
    }

    return MaterialisationPlan(
      templateId: template.id,
      occurrences: planned,
      nextDueDateKey: cursor,
      stoppedAtSafetyBound: hitBound,
    );
  }

  /// Whether [template] should be materialising at all as of [asOf].
  bool isActive({required RecurringTemplate template, required DateKey asOf}) =>
      template.isActiveAsOf(asOf);

  /// What settling [occurrence] implies, without writing anything.
  ///
  /// [template]'s `direction` decides the kind: an outflow settles by taking money out, an inflow by
  /// putting it in. That single field is what lets salary share the recurring system with bills
  /// rather than needing a second, parallel one (anomaly A27).
  ///
  /// [amount] is the amount **actually** paid and is recorded on the occurrence by the caller. The
  /// template's default is never touched — paying ₹520 against a ₹499 subscription records ₹520 and
  /// leaves ₹499 as the expectation, so analytics uses actuals without corrupting the schedule
  /// (anomaly A29).
  Result<SettlementIntent, Failure> planSettlement({
    required RecurringTemplate template,
    required RecurringOccurrence occurrence,
    required Money amount,
    required DateKey paidOn,
    required String accountId,
  }) {
    if (!amount.isPositive) {
      return const Result.failure(
        ValidationFailure('The amount paid must be greater than zero.', field: 'amount'),
      );
    }
    if (occurrence.status != RecurringOccurrenceStatus.due) {
      return Result.failure(
        BusinessRuleFailure(
          'This occurrence is already ${occurrence.status.name}.',
          rule: 'occurrenceNotDue',
        ),
      );
    }
    if (occurrence.templateId != template.id) {
      return const Result.failure(
        ValidationFailure(
          'That occurrence belongs to a different template.',
          field: 'occurrence',
        ),
      );
    }
    if (amount.currencyCode != template.defaultAmount.currencyCode) {
      // `recurring_occurrences` has no currency column: a paid amount is denominated in its
      // template's currency (ARCH_2 §7). Accepting another would store the number against the wrong
      // code on read — Law L1's pairing rule, broken silently.
      return Result.failure(
        ValidationFailure(
          'This template is in ${template.defaultAmount.currencyCode}, so the payment cannot be '
          'in ${amount.currencyCode}.',
          field: 'amount',
        ),
      );
    }

    final isOutflow = template.direction == RecurringDirection.outflow;
    return Result.ok(
      SettlementIntent(
        kind: isOutflow ? TransactionKind.withdrawal : TransactionKind.deposit,
        subtype: isOutflow ? TransactionSubtype.bill : TransactionSubtype.salaryIn,
        amount: amount,
        dateKey: paidOn,
        fromAccountId: isOutflow ? accountId : null,
        toAccountId: isOutflow ? null : accountId,
        templateId: template.id,
        occurrenceId: occurrence.id,
        payeeId: template.payeeId,
        tagId: template.tagId,
        note: template.name,
      ),
    );
  }

  /// Validates skipping [occurrence].
  ///
  /// A settled occurrence cannot be skipped: the money already moved, and marking it skipped would
  /// leave a transaction with nothing explaining it. Unsettle it first.
  Result<void, Failure> planSkip(RecurringOccurrence occurrence) {
    if (occurrence.status == RecurringOccurrenceStatus.paid) {
      return const Result.failure(
        BusinessRuleFailure(
          'A settled occurrence cannot be skipped — unsettle it first.',
          rule: 'cannotSkipPaid',
        ),
      );
    }
    return const Result.ok(null);
  }

  /// Whether [occurrence] is overdue as of [today].
  ///
  /// Derived, never stored — which is why `v_recurring_due` has no `is_overdue` column
  /// (ARCH_2 §12.2).
  bool isOverdue({required RecurringOccurrence occurrence, required DateKey today}) =>
      occurrence.isOverdue(today);
}
```

### `lib/domain/services/purchase_fan_out_service.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/text/normalizer.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';

/// Which artefact a purchase line produces, if any.
enum FanOutTarget {
  /// Nothing — a plain expense line.
  none,

  /// An `inventory_batches` row.
  batch,

  /// An `assets` row.
  asset,

  /// A `recurring_templates` row.
  recurringTemplate,
}

/// Exactly one artefact to create, and the line to write its id back to.
///
/// **At most one of [batch] and [asset] is ever non-null.** That is the invariant the whole class
/// exists to enforce: a line has one `destination`, so it produces one artefact, and
/// `transaction_lines` has three separate `created*Id` columns precisely so a reader can tell which
/// (ARCH_2 §4.2). A line that produced both a batch and an asset would make "what did this purchase
/// create" unanswerable — which is anomaly A12.
class FanOutPlan {
  /// Creates a plan.
  const FanOutPlan({
    required this.lineId,
    required this.target,
    this.batch,
    this.asset,
    this.recurringTemplateName,
  });

  /// A plan that creates nothing.
  const FanOutPlan.none(this.lineId)
      : target = FanOutTarget.none,
        batch = null,
        asset = null,
        recurringTemplateName = null;

  /// The line this plan came from, and where the created id is written back.
  final String lineId;

  /// What to create.
  final FanOutTarget target;

  /// The batch to create, when [target] is [FanOutTarget.batch].
  final Batch? batch;

  /// The asset to create, when [target] is [FanOutTarget.asset].
  final Asset? asset;

  /// The name for a template the user will finish configuring, when [target] is
  /// [FanOutTarget.recurringTemplate].
  ///
  /// A name rather than a whole `RecurringTemplate`: a schedule needs an interval and an anchor that
  /// a receipt line simply does not contain, and inventing a monthly-on-the-1st default would create
  /// obligations the user never agreed to. The caller opens the template editor pre-filled instead.
  final String? recurringTemplateName;

  /// True when the caller must create something.
  bool get createsArtefact => target != FanOutTarget.none;

  /// Sanity invariant: never more than one artefact.
  bool get isWellFormed {
    final count = [batch != null, asset != null, recurringTemplateName != null]
        .where((set) => set)
        .length;
    return target == FanOutTarget.none ? count == 0 : count == 1;
  }
}

/// Turns a saved transaction line into the one artefact its `destination` calls for.
///
/// **Pure.** It builds entities and returns them; the caller writes them and calls
/// `TransactionLineDao.setCreatedArtefact` to record the link. Nothing here touches a database, so
/// the "asset destination creates no batch" guarantee is testable directly rather than inferred from
/// what a repository happened to do.
///
/// This is the only service in Phase 4B with no prior implementation — the `created*Id` columns and
/// the *detach* path existed from Phase 1B and 3B, but nothing ever populated them.
final class PurchaseFanOutService {
  /// Creates the service.
  const PurchaseFanOutService({Normalizer normalizer = const Normalizer()})
      : _normalizer = normalizer;

  final Normalizer _normalizer;

  /// Plans the artefact [line] should produce.
  ///
  /// [newArtefactId] is used only when something is actually created, so a caller may generate a
  /// UUID unconditionally without leaking an unused one.
  ///
  /// Fails with a [ValidationFailure] when the destination needs data the line lacks — an inventory
  /// line without a quantity, or without a catalogued item to attach the batch to. Refusing is the
  /// point: a batch with a guessed quantity is stock the user never bought.
  Result<FanOutPlan, Failure> plan({
    required TransactionLine line,
    required Transaction transaction,
    required String newArtefactId,
  }) {
    switch (line.destination) {
      case TransactionLineDestination.none:
        return Result.ok(FanOutPlan.none(line.id));

      case TransactionLineDestination.inventory:
        return _planBatch(line: line, transaction: transaction, newId: newArtefactId);

      case TransactionLineDestination.asset:
        return _planAsset(line: line, transaction: transaction, newId: newArtefactId);

      case TransactionLineDestination.recurring:
        return Result.ok(
          FanOutPlan(
            lineId: line.id,
            target: FanOutTarget.recurringTemplate,
            recurringTemplateName: line.description,
          ),
        );
    }
  }

  /// Plans every artefact a transaction's lines produce, skipping lines that already have one.
  ///
  /// [newArtefactIds] must supply one id per line in [lines]; ids for lines that create nothing go
  /// unused. Re-running over a transaction whose lines already carry a `created*Id` produces no
  /// plans, which is what makes the fan-out safe to retry after a partial failure.
  Result<List<FanOutPlan>, Failure> planAll({
    required List<TransactionLine> lines,
    required Transaction transaction,
    required List<String> newArtefactIds,
  }) {
    if (newArtefactIds.length < lines.length) {
      return const Result.failure(
        ValidationFailure(
          'One artefact id is needed per line.',
          field: 'newArtefactIds',
        ),
      );
    }

    final plans = <FanOutPlan>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.hasArtefact) continue;
      final planned = plan(
        line: line,
        transaction: transaction,
        newArtefactId: newArtefactIds[i],
      );
      if (planned.isFailure) return Result.failure(planned.failureOrNull!);
      final value = planned.valueOrNull!;
      if (value.createsArtefact) plans.add(value);
    }
    return Result.ok(plans);
  }

  Result<FanOutPlan, Failure> _planBatch({
    required TransactionLine line,
    required Transaction transaction,
    required String newId,
  }) {
    // **A missing unit code is refused, not defaulted to `''`.**
    // `inventory_batches.unit_code_at_purchase` is a foreign key into `units`, and the empty string
    // matches no row — so the old `?? ''` did not paper over the gap, it turned a legible rejection
    // into `FOREIGN KEY constraint failed` several layers away, after the transaction had already
    // been written.
    final unitCode = line.unitCode;
    if (unitCode == null || unitCode.isEmpty) {
      return Result.failure(
        ValidationFailure(
          'This line is marked for inventory but has no unit, so the stock it would create could '
          'not be measured.',
          field: 'unitCode',
        ),
      );
    }
    final itemId = line.itemId;
    if (itemId == null) {
      return const Result.failure(
        ValidationFailure(
          'An inventory line needs a catalogued item for its batch to belong to.',
          field: 'itemId',
        ),
      );
    }
    final quantity = line.quantity;
    if (quantity == null || !quantity.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'An inventory line needs a quantity greater than zero.',
          field: 'quantity',
        ),
      );
    }

    return Result.ok(
      FanOutPlan(
        lineId: line.id,
        target: FanOutTarget.batch,
        batch: Batch(
          id: newId,
          itemId: itemId,
          initialQuantity: quantity,
          // Nothing has been consumed yet, so remaining equals initial. `BatchRepository.create`
          // enforces this and writes the founding movement from it.
          remainingQuantity: quantity,
          unitCodeAtPurchase: unitCode,
          purchasedDateKey: transaction.dateKey,
          origin: BatchOrigin.purchase,
          unitCost: line.unitPrice,
          sourceTransactionLineId: line.id,
        ),
      ),
    );
  }

  Result<FanOutPlan, Failure> _planAsset({
    required TransactionLine line,
    required Transaction transaction,
    required String newId,
  }) {
    final name = line.description.trim();
    if (name.isEmpty) {
      return const Result.failure(
        ValidationFailure('An asset line needs a description to name the asset.', field: 'description'),
      );
    }

    return Result.ok(
      FanOutPlan(
        lineId: line.id,
        target: FanOutTarget.asset,
        // No batch, deliberately and unconditionally. Electronics defaulting to the Service Manager
        // rather than Inventory is the resolution of anomaly A12: a television is serviced and has a
        // warranty, it is not consumed in portions. A user who also wants it in inventory adds it
        // there explicitly, which creates a second line with its own destination.
        asset: Asset(
          id: newId,
          name: name,
          normalizedName: _normalizer.normalize(name),
          // `other` rather than a guess from the description. Classifying "LG 55 inch" as
          // `electronics` by keyword would be wrong often enough to matter, and the asset editor
          // asks for the type anyway.
          type: AssetType.other,
          status: AssetStatus.active,
          purchaseDateKey: transaction.dateKey,
          purchasePrice: line.lineAmount,
          sourceTransactionLineId: line.id,
        ),
      ),
    );
  }

  /// The quantity a fanned-out batch should hold, for a caller checking before it writes.
  Qty? batchQuantityFor(TransactionLine line) =>
      line.destination == TransactionLineDestination.inventory ? line.quantity : null;

  /// The price a fanned-out asset should record, for the same reason.
  Money? assetPriceFor(TransactionLine line) =>
      line.destination == TransactionLineDestination.asset ? line.lineAmount : null;

  /// The civil date any artefact from [transaction] is dated.
  DateKey artefactDateFor(Transaction transaction) => transaction.dateKey;
}
```

### `lib/data/repositories/stock_repository_impl.dart`

```dart
import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_formatter.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/batch_dao.dart';
import 'package:alaya/data/daos/stock_movement_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/item_category_resolver.dart';
import 'package:alaya/data/repositories/mappers/stock_mappers.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/domain/repositories/stock_repository.dart';

/// `StockRepository` backed by `BatchDao` and `StockMovementDao`.
///
/// Every write here goes through [BatchDao.applyMovements], which pairs each movement with its
/// batch's cache update inside one transaction (Laws L3, L14). There is no path that records a
/// movement without updating the cache, or the reverse.
final class StockRepositoryImpl implements StockRepository {
  /// Creates the repository.
  const StockRepositoryImpl(
    this._batchDao,
    this._movementDao,
    this._categories,
    this._uids,
    this._clock,
  );

  final BatchDao _batchDao;
  final StockMovementDao _movementDao;
  final ItemCategoryResolver _categories;
  final UidGenerator _uids;
  final Clock _clock;

  /// Formats quantities for the user-facing text on a failure. `Qty.toString()` is a debug
  /// representation (`2500000m(weight)`) and its own doc says never to show it — these messages are
  /// read by a person, so they go through the formatter.
  static const QtyFormatter _qtyFormat = QtyFormatter();

  @override
  Future<Result<List<ConsumptionDraw>, Failure>> consume({
    required String itemId,
    required Qty quantity,
    required StockMovementKind kind,
    String? reason,
    String? note,
  }) async {
    if (!quantity.isPositive) {
      return const Result.failure(
        ValidationFailure('The quantity to consume must be greater than zero.', field: 'quantity'),
      );
    }

    final category = await _categories.categoryOf(itemId);
    if (category == null) {
      return Result.failure(NotFoundFailure('Item not found.', id: itemId));
    }
    if (category != quantity.category) {
      return Result.failure(
        ValidationFailure(
          'This item is measured in ${category.name}, not ${quantity.category.name}.',
          field: 'quantity',
        ),
      );
    }

    // FEFO order, already filtered to batches holding stock: nearest expiry first, undated last
    // (anomaly A08). The DAO owns that ordering so it is expressed once, in SQL, where the index
    // can serve it.
    final batches = await _batchDao.byItemFefo(itemId);
    final available = batches.fold<int>(0, (sum, b) => sum + b.remainingQuantityMilli);

    if (available < quantity.milliBase) {
      // Checked before any write, and nothing is written on this path. A partial consumption would
      // leave the ledger describing something that did not happen — worse than refusing, because
      // the user would have no way to tell how much actually came out.
      return Result.failure(
        BusinessRuleFailure(
          'Only ${_qtyFormat.format(Qty(available, category))} is on hand, less than the '
          '${_qtyFormat.format(quantity)} requested.',
          rule: 'insufficientStock',
        ),
      );
    }

    final plan = _planDraws(
      batches: batches,
      needed: quantity.milliBase,
      category: category,
    );
    await _applyDraws(
      itemId: itemId,
      draws: plan,
      kind: kind,
      reason: reason,
      note: note,
    );
    return Result.ok(plan);
  }

  @override
  Future<Result<void, Failure>> consumeFromBatch({
    required String batchId,
    required Qty quantity,
    required StockMovementKind kind,
    String? reason,
    String? note,
  }) async {
    if (!quantity.isPositive) {
      return const Result.failure(
        ValidationFailure('The quantity to consume must be greater than zero.', field: 'quantity'),
      );
    }

    final batch = await _batchDao.byIdIncludingDeleted(batchId);
    if (batch == null) {
      return Result.failure(NotFoundFailure('Batch not found.', id: batchId));
    }
    final category = await _categories.categoryOf(batch.itemId);
    if (category == null) {
      return Result.failure(NotFoundFailure('Item not found.', id: batch.itemId));
    }
    if (category != quantity.category) {
      return Result.failure(
        ValidationFailure(
          'This batch is measured in ${category.name}, not ${quantity.category.name}.',
          field: 'quantity',
        ),
      );
    }
    if (batch.remainingQuantityMilli < quantity.milliBase) {
      return Result.failure(
        BusinessRuleFailure(
          'This batch holds only '
          '${_qtyFormat.format(Qty(batch.remainingQuantityMilli, category))}, less than the '
          '${_qtyFormat.format(quantity)} requested.',
          rule: 'insufficientStock',
        ),
      );
    }

    await _applyDraws(
      itemId: batch.itemId,
      draws: [ConsumptionDraw(batchId: batchId, quantity: quantity)],
      kind: kind,
      reason: reason,
      note: note,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> addStock({
    required String batchId,
    required Qty quantity,
    required StockMovementKind kind,
    String? note,
  }) async {
    if (!quantity.isPositive) {
      return const Result.failure(
        ValidationFailure('The quantity to add must be greater than zero.', field: 'quantity'),
      );
    }
    if (!StockMovementDao.incomingKinds.contains(kind)) {
      // Guarding the direction rather than trusting it: an outgoing kind passed here would reduce
      // stock while the caller believed it was adding, and the cache would faithfully follow.
      return Result.failure(
        ValidationFailure(
          '${kind.name} removes stock rather than adding it.',
          field: 'kind',
        ),
      );
    }

    final batch = await _batchDao.byIdIncludingDeleted(batchId);
    if (batch == null) {
      return Result.failure(NotFoundFailure('Batch not found.', id: batchId));
    }
    final category = await _categories.categoryOf(batch.itemId);
    if (category == null) {
      return Result.failure(NotFoundFailure('Item not found.', id: batch.itemId));
    }
    if (category != quantity.category) {
      return Result.failure(
        ValidationFailure(
          'This batch is measured in ${category.name}, not ${quantity.category.name}.',
          field: 'quantity',
        ),
      );
    }

    await _applyDraws(
      itemId: batch.itemId,
      draws: [ConsumptionDraw(batchId: batchId, quantity: quantity)],
      kind: kind,
      note: note,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> reverse({
    required String movementId,
    String? reason,
  }) async {
    final original = await _movementDao.byId(movementId);
    if (original == null) {
      return Result.failure(NotFoundFailure('Movement not found.', id: movementId));
    }

    final alreadyReversed = await _movementDao.reversalOf(movementId);
    if (alreadyReversed != null) {
      return const Result.failure(
        BusinessRuleFailure(
          'This movement has already been reversed.',
          rule: 'alreadyReversed',
        ),
      );
    }
    if (original.reversesMovementId != null) {
      // Reversing a reversal would be indistinguishable from re-applying the original, and would
      // let a chain build up that nothing can interpret. Undo is one level deep by design.
      return const Result.failure(
        BusinessRuleFailure(
          'A correction cannot itself be reversed — record a new movement instead.',
          rule: 'cannotReverseAReversal',
        ),
      );
    }

    // The compensating kind, chosen so the pair nets to zero under the same direction rule
    // `v_batch_stock_check` applies: an incoming movement is undone by an adjustOut and vice versa.
    final compensating = StockMovementDao.incomingKinds.contains(original.kind)
        ? StockMovementKind.adjustOut
        : StockMovementKind.adjustIn;

    final now = _clock.nowUtcMillis();
    await _batchDao.applyMovements(
      entries: [
        (
          batchId: original.batchId,
          movement: StockMovementsCompanion.insert(
            id: _uids.generate(),
            batchId: original.batchId,
            itemId: original.itemId,
            kind: compensating,
            quantityMilli: original.quantityMilli,
            occurredAt: now,
            dateKey: _clock.today(),
            reason: Value(reason),
            reversesMovementId: Value(movementId),
            createdAt: now,
            updatedAt: now,
          ),
        ),
      ],
      nowUtcMillis: now,
    );
    return const Result.ok(null);
  }

  @override
  Stream<List<StockMovement>> watchForBatch(String batchId) {
    return _movementDao.watchForBatch(batchId).asyncMap(_mapAll);
  }

  @override
  Stream<List<StockMovement>> watchForItemInRange({
    required String itemId,
    required DateKey from,
    required DateKey to,
  }) {
    return _movementDao
        .watchForItemInRange(itemId: itemId, from: from, to: to)
        .asyncMap(_mapAll);
  }

  @override
  Future<List<WasteTotal>> wasteTotals({
    required DateKey from,
    required DateKey to,
  }) async {
    // Both waste kinds, totalled separately per item. `expired` and `waste` are distinct events —
    // food that rotted unnoticed versus food thrown out deliberately — but both are stock that was
    // paid for and never used, which is what ARCH_3 §5.1 query 14 measures.
    final byItem = <String, ({int milli, MoneyByCurrency cost})>{};

    // One query across all items, both waste kinds. Asking per item would require the caller to
    // already know which items have waste — inverting the question, since that set is the answer.
    final movements = await _movementDao.forKindsInRange(
      kinds: const {StockMovementKind.waste, StockMovementKind.expired},
      from: from,
      to: to,
    );

    // Batch costs are cached: a single wasted item is typically spread over few batches, and
    // re-reading the same batch row once per movement would dominate the cost of this query.
    final batchCosts = <String, ({int? unitCostMinor, String? currencyCode})>{};

    for (final m in movements) {
      final entry = byItem.putIfAbsent(m.itemId, () => (milli: 0, cost: MoneyByCurrency()));
      byItem[m.itemId] = (milli: entry.milli + m.quantityMilli, cost: entry.cost);

      final cost = batchCosts[m.batchId] ??= await () async {
        final batch = await _batchDao.byIdIncludingDeleted(m.batchId);
        return (unitCostMinor: batch?.unitCostMinor, currencyCode: batch?.costCurrencyCode);
      }();

      final unitCost = cost.unitCostMinor;
      final costCode = cost.currencyCode;
      if (unitCost != null && costCode != null) {
        entry.cost.add(
          currencyCode: costCode,
          // unitCost is per purchased unit; the movement is in base-milli units, so the wasted
          // money is unitCost x (milli / 1000). Truncated: a fraction of a minor unit cannot be
          // represented, and waste valuation is an estimate rather than a ledger figure.
          minor: (unitCost * m.quantityMilli / 1000).truncate(),
        );
      }
    }

    final result = <WasteTotal>[];
    for (final e in byItem.entries) {
      final category = await _categories.categoryOf(e.key);
      if (category == null) continue;
      result.add(
        WasteTotal(
          itemId: e.key,
          quantity: Qty(e.value.milli, category),
          costByCurrency: e.value.cost.totals,
        ),
      );
    }
    return result;
  }

  /// Delegates FEFO planning to [InventoryConsumptionService].
  ///
  /// This method used to implement the ordering and draw-down itself. Phase 4B moved the algorithm
  /// into the service so there is one definition of it — the same consolidation Phase 4A made for
  /// the currency cross-rate, and for the same reason: two copies of an ordering rule drift apart.
  /// What stays here is the part only a repository can do — writing every draw in one transaction.
  List<ConsumptionDraw> _planDraws({
    required List<InventoryBatchRow> batches,
    required int needed,
    required UnitCategory category,
  }) {
    const service = InventoryConsumptionService();
    final plan = service.plan(
      batches: batches.map(
        (row) => ConsumableBatch(
          batchId: row.id,
          remaining: Qty(row.remainingQuantityMilli, category),
          purchasedDateKey: row.purchasedDateKey,
          expiryDateKey: row.expiryDateKey,
        ),
      ),
      needed: Qty(needed, category),
    );
    // Insufficiency is already checked by the caller before this runs, so a failure here would mean
    // the two disagreed — return no draws rather than a partial set either way.
    return plan.valueOrNull?.draws ?? const [];
  }

  /// Records one movement per draw, all in a single transaction (Law L14).
  Future<void> _applyDraws({
    required String itemId,
    required List<ConsumptionDraw> draws,
    required StockMovementKind kind,
    String? reason,
    String? note,
  }) {
    final now = _clock.nowUtcMillis();
    final today = _clock.today();
    return _batchDao.applyMovements(
      entries: draws
          .map(
            (draw) => (
              batchId: draw.batchId,
              movement: StockMovementsCompanion.insert(
                id: _uids.generate(),
                batchId: draw.batchId,
                itemId: itemId,
                kind: kind,
                quantityMilli: draw.quantity.milliBase,
                occurredAt: now,
                dateKey: today,
                reason: Value(reason),
                note: Value(note),
                createdAt: now,
                updatedAt: now,
              ),
            ),
          )
          .toList(),
      nowUtcMillis: now,
    );
  }

  Future<List<StockMovement>> _mapAll(List<StockMovementRow> rows) async {
    final categories = await _categories.categoriesFor(rows.map((r) => r.itemId));
    return rows
        .where((r) => categories.containsKey(r.itemId))
        .map((r) => r.toEntity(categories[r.itemId]!))
        .toList();
  }
}
```

### `lib/data/repositories/recurring_repository_impl.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/recurring_occurrence_dao.dart';
import 'package:alaya/data/daos/recurring_template_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/mappers/schedule_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/repositories/recurring_repository.dart';
import 'package:alaya/domain/repositories/transaction_repository.dart';
import 'package:alaya/domain/services/recurring_engine.dart';

/// `RecurringRepository` backed by `RecurringTemplateDao` and `RecurringOccurrenceDao`.
///
/// Depends on `TransactionRepository` — the domain interface — so [payOccurrence] reuses its shape
/// validation and `monthKey` derivation rather than reimplementing them.
final class RecurringRepositoryImpl implements RecurringRepository {
  /// Creates the repository.
  const RecurringRepositoryImpl(
    this._templateDao,
    this._occurrenceDao,
    this._transactions,
    this._uids,
    this._clock,
  );

  final RecurringTemplateDao _templateDao;
  final RecurringOccurrenceDao _occurrenceDao;
  final TransactionRepository _transactions;
  final UidGenerator _uids;
  final Clock _clock;

  /// Owns the interval arithmetic, the month-end clamp and the materialisation bound.
  static const RecurringEngine _engine = RecurringEngine();

  // ── templates ─────────────────────────────────────────────────────────────────────────

  @override
  Stream<List<RecurringTemplate>> watchAllTemplates() =>
      _templateDao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<RecurringTemplate>> watchTemplatesByDirection(RecurringDirection direction) =>
      _templateDao
          .watchByDirection(direction)
          .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<RecurringTemplate>> watchTemplatesForAsset(String assetId) =>
      _templateDao.watchForAsset(assetId).map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<RecurringTemplate?> templateById(String id) async =>
      (await _templateDao.byIdIncludingDeleted(id))?.toEntity();

  /// Emits the due list: unpaused templates paired with their outstanding occurrence.
  ///
  /// Built from two typed queries rather than from `v_recurring_due`, deliberately. That view is a
  /// presentation-shaped projection of 18 columns; a full `RecurringTemplate` needs nine more
  /// (`normalizedName`, `startDateKey`, `isPaused`, the three anchors, `endDateKey`,
  /// `linkedAssetId`, `note`) and a full `RecurringOccurrence` four more (`paidTransactionId`,
  /// `paidAmount`, `paidDateKey`, `note`). Widening the view to carry all thirteen — with `note`
  /// needing an alias on both sides — would leave it a bare join whose only remaining value is a
  /// filter these two queries already express. Two queries, no per-template round trip.
  ///
  /// `RecurringTemplateDao.watchDue()` still reads the view and is the right call for a caller
  /// that only needs the projection, such as a dashboard count.
  @override
  Stream<List<RecurringDue>> watchDue() {
    return _templateDao.watchAll().asyncMap((templateRows) async {
      final today = _clock.today();
      // Materialisation never runs ahead of today, so every `due` occurrence has a due date on or
      // before it — this is the whole outstanding set, in one query rather than one per template.
      final outstanding = await _occurrenceDao.outstandingAsOf(today);
      final byTemplate = <String, RecurringOccurrenceRow>{};
      for (final row in outstanding) {
        final existing = byTemplate[row.templateId];
        // Oldest outstanding occurrence wins: that is the one the user owes next.
        if (existing == null || row.dueDateKey < existing.dueDateKey) {
          byTemplate[row.templateId] = row;
        }
      }

      final due = <RecurringDue>[];
      for (final templateRow in templateRows) {
        if (templateRow.isPaused) continue;
        final template = templateRow.toEntity();
        if (template.hasEnded(today)) continue;
        final occurrenceRow = byTemplate[templateRow.id];
        due.add(
          RecurringDue(
            template: template,
            occurrence: occurrenceRow?.toEntity(templateRow.currencyCode),
          ),
        );
      }
      due.sort((a, b) => DateKey.compare(a.template.nextDueDateKey, b.template.nextDueDateKey));
      return due;
    });
  }

  @override
  Future<Result<RecurringTemplate, Failure>> saveTemplate(RecurringTemplate template) async {
    final validation = _validateTemplate(template);
    if (validation != null) return Result.failure(validation);

    final existing = await _templateDao.byIdIncludingDeleted(template.id);
    if (existing == null) {
      final duplicate = await _templateDao.byNormalizedName(template.normalizedName);
      if (duplicate != null) {
        return Result.failure(
          ConflictFailure('A recurring template named "${template.name}" already exists.'),
        );
      }
    }

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _templateDao.upsert(
      recurringTemplateToCompanion(
        template,
        createdAt: stamps.createdAt,
        updatedAt: stamps.updatedAt,
      ),
    );
    return Result.ok(template);
  }

  @override
  Future<Result<void, Failure>> setTemplatePaused({
    required String id,
    required bool isPaused,
  }) async {
    final existing = await _templateDao.byIdIncludingDeleted(id);
    if (existing == null || existing.deletedAt != null) {
      return Result.failure(NotFoundFailure('Recurring template not found.', id: id));
    }
    await _templateDao.setPaused(
      id: id,
      isPaused: isPaused,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> deleteTemplate(String id) async {
    // Soft, and it cascades to nothing. Paid occurrences and the transactions they created survive
    // untouched (ARCH_3 §4.1): deleting a subscription does not un-pay last month's bill, and the
    // money that left the account really left it.
    await _templateDao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  // ── occurrences ───────────────────────────────────────────────────────────────────────

  @override
  Stream<List<RecurringOccurrence>> watchOccurrences(String templateId) {
    return _occurrenceDao.watchForTemplate(templateId).asyncMap((rows) async {
      final template = await _templateDao.byIdIncludingDeleted(templateId);
      if (template == null) return const <RecurringOccurrence>[];
      return rows.map((r) => r.toEntity(template.currencyCode)).toList();
    });
  }

  @override
  Stream<List<RecurringOccurrence>> watchOccurrencesInRange({
    required DateKey from,
    required DateKey to,
  }) {
    return _occurrenceDao.watchDueInRange(from: from, to: to).asyncMap(_mapWithTemplateCurrency);
  }

  @override
  Future<Result<int, Failure>> materialiseUpTo(DateKey asOf) async {
    final templates = await _templateDao.needingMaterialisation(asOf);
    final now = _clock.nowUtcMillis();
    var created = 0;

    for (final row in templates) {
      final template = row.toEntity();
      var cursor = template.nextDueDateKey;
      var guard = 0;

      while (!cursor.isAfter(asOf) && guard < RecurringEngine.maxOccurrencesPerPass) {
        guard++;
        final end = template.endDateKey;
        if (end != null && cursor.isAfter(end)) break;

        // Idempotent: the DAO reads before inserting, because `idx_recurring_occ` is a partial
        // unique index and SQLite rejects a partial index as an ON CONFLICT target. Running this
        // twice creates nothing the second time.
        await _occurrenceDao.upsertForDue(
          id: _uids.generate(),
          templateId: template.id,
          dueDateKey: cursor,
          nowUtcMillis: now,
        );
        created++;
        cursor = _advance(cursor, template);
      }

      if (cursor != template.nextDueDateKey) {
        await _templateDao.advanceNextDue(
          id: template.id,
          nextDueDateKey: cursor,
          nowUtcMillis: now,
        );
      }
    }
    // Every occurrence created here is `due`. Nothing is paid, and no transaction exists — money is
    // only ever created by an explicit user tap (anomaly A14). An app unopened for three months
    // produces three due rows and zero transactions.
    return Result.ok(created);
  }

  @override
  Future<Result<Transaction, Failure>> payOccurrence({
    required String occurrenceId,
    required Money amount,
    required DateKey paidOn,
    required String accountId,
    String? paymentMethodId,
  }) async {
    if (!amount.isPositive) {
      return const Result.failure(
        ValidationFailure('The amount paid must be greater than zero.', field: 'amount'),
      );
    }

    final occurrence = await _occurrenceDao.byId(occurrenceId);
    if (occurrence == null) {
      return Result.failure(NotFoundFailure('Occurrence not found.', id: occurrenceId));
    }
    if (occurrence.status != RecurringOccurrenceStatus.due) {
      return Result.failure(
        BusinessRuleFailure(
          'This occurrence is already ${occurrence.status.name}.',
          rule: 'occurrenceNotDue',
        ),
      );
    }

    final templateRow = await _templateDao.byIdIncludingDeleted(occurrence.templateId);
    if (templateRow == null) {
      return Result.failure(
        NotFoundFailure('The template this occurrence belongs to does not exist.',
            id: occurrence.templateId),
      );
    }
    if (amount.currencyCode != templateRow.currencyCode) {
      // `recurring_occurrences` has no currency column: a paid amount is denominated in its
      // template's currency (ARCH_2 §7). Accepting a different one would store the number against
      // the wrong code on read — Law L1's pairing rule, broken silently.
      return Result.failure(
        ValidationFailure(
          'This template is in ${templateRow.currencyCode}, so the payment cannot be in '
          '${amount.currencyCode}.',
          field: 'amount',
        ),
      );
    }

    // `direction` decides the kind: an outflow settles by taking money out, an inflow by putting it
    // in. This is what lets salary share the recurring system with bills instead of needing a
    // second, parallel one (anomaly A27).
    final isOutflow = templateRow.direction == RecurringDirection.outflow;
    final created = await _transactions.create(
      transaction: Transaction(
        id: _uids.generate(),
        kind: isOutflow ? TransactionKind.withdrawal : TransactionKind.deposit,
        subtype: isOutflow ? TransactionSubtype.bill : TransactionSubtype.salaryIn,
        // **Now when the date is today, midnight only when it is not.**
        //
        // The ledger orders by `dateKey DESC, occurredAt DESC`. Stamping midnight unconditionally sent
        // every same-day entry to the *bottom* of today's group, behind hand-entered expenses stamped
        // with the real clock — so two records made seconds apart appeared in an order with no
        // relationship to anything the user did.
        //
        // Midnight stays right for a back-dated payment: nobody knows what time last Tuesday's plumber
        // came, and inventing one would be a worse lie than admitting the day is all we have.
        occurredAtUtc:
            paidOn == _clock.today() ? _clock.now().toUtc() : paidOn.toUtcMidnight(),
        dateKey: paidOn,
        originalAmount: amount,
        needsReview: false,
        fromAccountId: isOutflow ? accountId : null,
        toAccountId: isOutflow ? null : accountId,
        paymentMethodId: paymentMethodId,
        payeeId: templateRow.payeeId,
        note: templateRow.name,
        recurringTemplateId: templateRow.id,
        recurringOccurrenceId: occurrenceId,
      ),
      tagIds: templateRow.tagId == null ? const [] : [templateRow.tagId!],
    );
    if (created.isFailure) return Result.failure(created.failureOrNull!);
    final transaction = created.valueOrNull!;

    // The ACTUAL amount is recorded on the occurrence. The template's `defaultAmountMinor` is not
    // touched — paying ₹520 against a ₹499 subscription records ₹520 here and leaves ₹499 as the
    // template's expectation, so analytics uses actuals without corrupting the schedule
    // (anomaly A29).
    await _occurrenceDao.markPaid(
      id: occurrenceId,
      transactionId: transaction.id,
      paidAmountMinor: amount.minor,
      paidDateKey: paidOn,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return Result.ok(transaction);
  }

  @override
  Future<Result<void, Failure>> skipOccurrence({
    required String occurrenceId,
    String? note,
  }) async {
    final occurrence = await _occurrenceDao.byId(occurrenceId);
    if (occurrence == null) {
      return Result.failure(NotFoundFailure('Occurrence not found.', id: occurrenceId));
    }
    if (occurrence.status == RecurringOccurrenceStatus.paid) {
      return const Result.failure(
        BusinessRuleFailure(
          'A settled occurrence cannot be skipped — unsettle it first.',
          rule: 'cannotSkipPaid',
        ),
      );
    }
    await _occurrenceDao.markSkipped(
      id: occurrenceId,
      note: note,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> unsettleOccurrence(String occurrenceId) async {
    final occurrence = await _occurrenceDao.byId(occurrenceId);
    if (occurrence == null) {
      return Result.failure(NotFoundFailure('Occurrence not found.', id: occurrenceId));
    }
    // Returns it to `due` and clears the settlement fields, so the obligation reappears rather than
    // staying silently marked paid after the transaction behind it is gone. The transaction itself
    // is not touched — this is called *because* it was deleted.
    await _occurrenceDao.unlinkDeletedTransaction(
      id: occurrenceId,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  // ── interval arithmetic ───────────────────────────────────────────────────────────────

  /// Delegates to [RecurringEngine.nextDue].
  ///
  /// The interval arithmetic and the month-end anchor clamp used to live here. Phase 4B moved them
  /// into the engine so the clamp has one definition — anomaly A13 is exactly the kind of rule that
  /// must not exist twice, because the second copy is the one that walks a bill backwards.
  DateKey _advance(DateKey from, RecurringTemplate template) =>
      _engine.nextDue(from: from, template: template);

  /// Validates a template's interval and anchor coherence.
  Failure? _validateTemplate(RecurringTemplate template) {
    if (template.name.trim().isEmpty) {
      return const ValidationFailure('A recurring template needs a name.', field: 'name');
    }
    if (!template.defaultAmount.isPositive) {
      return const ValidationFailure(
        'A recurring template needs a positive default amount.',
        field: 'defaultAmount',
      );
    }
    if (template.intervalCount < 1) {
      return const ValidationFailure(
        'The interval must be at least 1.',
        field: 'intervalCount',
      );
    }
    final end = template.endDateKey;
    if (end != null && end.isBefore(template.startDateKey)) {
      return const ValidationFailure(
        'The end date cannot be before the start date.',
        field: 'endDateKey',
      );
    }

    final anchorDay = template.anchorDayOfMonth;
    if (anchorDay != null && (anchorDay < 1 || anchorDay > 31)) {
      return const ValidationFailure(
        'The day of the month must be between 1 and 31.',
        field: 'anchorDayOfMonth',
      );
    }
    final anchorWeekday = template.anchorWeekday;
    if (anchorWeekday != null && (anchorWeekday < 1 || anchorWeekday > 7)) {
      return const ValidationFailure(
        'The weekday must be between 1 (Monday) and 7 (Sunday).',
        field: 'anchorWeekday',
      );
    }
    final anchorMonth = template.anchorMonth;
    if (anchorMonth != null && (anchorMonth < 1 || anchorMonth > 12)) {
      return const ValidationFailure(
        'The month must be between 1 and 12.',
        field: 'anchorMonth',
      );
    }

    // A monthly or yearly template with no day anchor would advance from whatever day it happened
    // to land on, so a February settlement would pull every later occurrence back to the 28th
    // permanently (anomaly A13). Requiring the anchor is what makes that impossible.
    final needsDayAnchor = template.intervalUnit == RecurringIntervalUnit.month ||
        template.intervalUnit == RecurringIntervalUnit.year;
    if (needsDayAnchor && anchorDay == null) {
      return const ValidationFailure(
        'A monthly or yearly template needs a day of the month to anchor to.',
        field: 'anchorDayOfMonth',
      );
    }
    return null;
  }

  Future<List<RecurringOccurrence>> _mapWithTemplateCurrency(
    List<RecurringOccurrenceRow> rows,
  ) async {
    final currencies = <String, String>{};
    for (final templateId in rows.map((r) => r.templateId).toSet()) {
      final template = await _templateDao.byIdIncludingDeleted(templateId);
      if (template != null) currencies[templateId] = template.currencyCode;
    }
    return rows
        .where((r) => currencies.containsKey(r.templateId))
        .map((r) => r.toEntity(currencies[r.templateId]!))
        .toList();
  }
}
```

### `test/domain/consumption_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';
import 'package:alaya/domain/services/low_stock_suggestion_engine.dart';
import 'package:alaya/domain/services/purchase_fan_out_service.dart';
import 'package:alaya/domain/services/stock_reconciler.dart';

/// FEFO consumption, reconciliation, low-stock idempotency and the purchase fan-out.
///
/// Every service under test is pure, so none of this touches a database or a mock.
void main() {
  const consumption = InventoryConsumptionService();
  const reconciler = StockReconciler();
  const suggestions = LowStockSuggestionEngine();
  const fanOut = PurchaseFanOutService();

  Qty grams(int g) => Qty(g * 1000, UnitCategory.weight);

  group('FEFO consumption', () {
    // The three batches exactly as specified, and deliberately in an order where neither the
    // nearest expiry nor the undated batch is first — so a service that trusted input order would
    // fail this.
    final batches = [
      ConsumableBatch(
        batchId: 'b_exp_10aug',
        remaining: grams(500),
        purchasedDateKey: DateKey.fromYmd(2026, 7, 15),
        expiryDateKey: DateKey.fromYmd(2026, 8, 10),
      ),
      ConsumableBatch(
        batchId: 'b_no_expiry',
        remaining: grams(1000),
        purchasedDateKey: DateKey.fromYmd(2026, 7, 1),
      ),
      ConsumableBatch(
        batchId: 'b_exp_05aug',
        remaining: grams(300),
        purchasedDateKey: DateKey.fromYmd(2026, 7, 20),
        expiryDateKey: DateKey.fromYmd(2026, 8, 5),
      ),
    ];

    test('consuming 600 g draws 300 from 05 Aug then 300 from 10 Aug', () {
      final result = consumption.plan(batches: batches, needed: grams(600));

      expect(result.isFailure, isFalse);
      final plan = result.valueOrNull!;

      expect(plan.draws.map((d) => d.batchId).toList(), ['b_exp_05aug', 'b_exp_10aug'],
          reason: 'nearest expiry first');
      expect(plan.draws[0].quantity, grams(300), reason: 'the 05 Aug batch is drained');
      expect(plan.draws[1].quantity, grams(300), reason: 'the balance comes from 10 Aug');
    });

    test('the no-expiry batch is left untouched', () {
      final plan = consumption.plan(batches: batches, needed: grams(600)).valueOrNull!;

      expect(plan.touchedBatchIds, isNot(contains('b_no_expiry')),
          reason: 'undated stock cannot spoil on a deadline, so dated stock goes first (A08)');
    });

    test('exactly two movement rows', () {
      final plan = consumption.plan(batches: batches, needed: grams(600)).valueOrNull!;

      // One movement per draw, which is the 1:1 mapping `StockRepository.consume` applies.
      expect(plan.movementCount, 2);
      expect(plan.draws, hasLength(2));
    });

    test('the draws sum to exactly what was asked for', () {
      final plan = consumption.plan(batches: batches, needed: grams(600)).valueOrNull!;
      final total = plan.draws.fold<int>(0, (sum, d) => sum + d.quantity.milliBase);

      expect(total, grams(600).milliBase);
    });

    test('ordering puts undated last regardless of input order', () {
      final ordered = consumption.orderFefo(batches);

      expect(ordered.map((b) => b.batchId).toList(),
          ['b_exp_05aug', 'b_exp_10aug', 'b_no_expiry']);
    });

    test('a batch holding nothing never produces a movement', () {
      final withEmpty = [
        ConsumableBatch(
          batchId: 'b_empty',
          remaining: grams(0),
          purchasedDateKey: DateKey.fromYmd(2026, 1, 1),
          expiryDateKey: DateKey.fromYmd(2026, 1, 2),
        ),
        ...batches,
      ];

      final plan = consumption.plan(batches: withEmpty, needed: grams(100)).valueOrNull!;

      expect(plan.touchedBatchIds, isNot(contains('b_empty')),
          reason: 'stock_movements has CHECK (quantity_milli > 0), and a zero movement is noise');
      expect(plan.draws.single.batchId, 'b_exp_05aug');
    });

    test('consuming exactly one batch\'s remaining does not spill into the next', () {
      final plan = consumption.plan(batches: batches, needed: grams(300)).valueOrNull!;

      expect(plan.draws, hasLength(1));
      expect(plan.draws.single.batchId, 'b_exp_05aug');
    });

    test('draining everything touches all three, undated last', () {
      final plan = consumption.plan(batches: batches, needed: grams(1800)).valueOrNull!;

      expect(plan.draws.map((d) => d.batchId).toList(),
          ['b_exp_05aug', 'b_exp_10aug', 'b_no_expiry']);
      expect(plan.movementCount, 3);
    });

    group('consuming more than total stock', () {
      test('fails rather than partially consuming', () {
        // One milli-gram beyond the 1800 g on hand.
        final result = consumption.plan(
          batches: batches,
          needed: Qty(grams(1800).milliBase + 1, UnitCategory.weight),
        );

        expect(result.isFailure, isTrue);
        expect(result.failureOrNull, isA<BusinessRuleFailure>());
        expect((result.failureOrNull! as BusinessRuleFailure).rule, 'insufficientStock');
      });

      test('and produces NO draws at all, so no partial write is possible', () {
        final result = consumption.plan(batches: batches, needed: grams(5000));

        expect(result.valueOrNull, isNull,
            reason: 'a half-applied consumption describes something that did not happen');
      });

      test('an empty inventory fails the same way', () {
        final result = consumption.plan(batches: const [], needed: grams(1));

        expect(result.isFailure, isTrue);
      });
    });

    test('a zero or negative request is rejected before anything else', () {
      expect(consumption.plan(batches: batches, needed: grams(0)).isFailure, isTrue);
      expect(
        consumption.plan(batches: batches, needed: Qty(-1000, UnitCategory.weight)).isFailure,
        isTrue,
      );
    });

    test('a cross-category request is refused, not converted (L8)', () {
      final result = consumption.plan(
        batches: batches,
        needed: Qty(600000, UnitCategory.volume),
      );

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<ValidationFailure>());
    });
  });

  group('stock reconciliation', () {
    StockMovement movement(StockMovementKind kind, int g) => StockMovement(
          id: 'm-${kind.name}-$g',
          batchId: 'b1',
          itemId: 'potato',
          kind: kind,
          quantity: grams(g),
          occurredAtUtc: DateTime.utc(2026, 7, 20),
          dateKey: DateKey.fromYmd(2026, 7, 20),
        );

    test('a consistent batch shows zero discrepancy', () {
      final result = reconciler.reconcile(
        batchId: 'b1',
        cached: grams(1700),
        movements: [
          movement(StockMovementKind.openingIn, 2000),
          movement(StockMovementKind.consume, 300),
        ],
      );

      expect(result.fromLedger, grams(1700));
      expect(result.discrepancy, grams(0));
      expect(result.isConsistent, isTrue);
    });

    test('a consume that never updated the cache is detected', () {
      final result = reconciler.reconcile(
        batchId: 'b1',
        cached: grams(2000),
        movements: [
          movement(StockMovementKind.openingIn, 2000),
          movement(StockMovementKind.consume, 300),
        ],
      );

      expect(result.fromLedger, grams(1700));
      expect(result.discrepancy, grams(300));
      expect(result.isConsistent, isFalse);
    });

    test('waste and expired both reduce stock', () {
      final ledger = reconciler.remainingFromLedgerMilli([
        movement(StockMovementKind.openingIn, 1000),
        movement(StockMovementKind.waste, 250),
        movement(StockMovementKind.expired, 250),
      ]);

      expect(ledger, grams(500).milliBase);
    });

    test('a reversal cancels the movement it points at', () {
      final ledger = reconciler.remainingFromLedgerMilli([
        movement(StockMovementKind.openingIn, 1000),
        movement(StockMovementKind.consume, 200),
        movement(StockMovementKind.adjustIn, 200),
      ]);

      expect(ledger, grams(1000).milliBase,
          reason: 'summing with the opposite sign is all a reversal needs to do');
    });

    test('a cache BELOW the ledger is a discrepancy too', () {
      final result = reconciler.reconcile(
        batchId: 'b1',
        cached: grams(500),
        movements: [movement(StockMovementKind.openingIn, 1000)],
      );

      expect(result.isConsistent, isFalse,
          reason: 'hiding stock the user has is the harder error to notice');
      expect(result.discrepancy.milliBase, lessThan(0));
    });

    test('every incoming kind is classified as incoming, every outgoing as outgoing', () {
      const incoming = [
        StockMovementKind.openingIn,
        StockMovementKind.purchaseIn,
        StockMovementKind.manualIn,
        StockMovementKind.adjustIn,
      ];
      const outgoing = [
        StockMovementKind.consume,
        StockMovementKind.waste,
        StockMovementKind.expired,
        StockMovementKind.adjustOut,
      ];

      // Exhaustive: if a kind is ever added, this fails until it is classified, which is the point.
      expect({...incoming, ...outgoing}, hasLength(StockMovementKind.values.length));
      for (final kind in incoming) {
        expect(reconciler.isIncoming(kind), isTrue, reason: kind.name);
      }
      for (final kind in outgoing) {
        expect(reconciler.isIncoming(kind), isFalse, reason: kind.name);
      }
    });

    test('a summary reports the worst offender', () {
      final summary = reconciler.summarise([
        reconciler.reconcile(
          batchId: 'ok',
          cached: grams(100),
          movements: [movement(StockMovementKind.openingIn, 100)],
        ),
        reconciler.reconcile(
          batchId: 'small',
          cached: grams(110),
          movements: [movement(StockMovementKind.openingIn, 100)],
        ),
        reconciler.reconcile(
          batchId: 'big',
          cached: grams(900),
          movements: [movement(StockMovementKind.openingIn, 100)],
        ),
      ]);

      expect(summary.batchesChecked, 3);
      expect(summary.batchesNeedingRepair, 2);
      expect(summary.largestDiscrepancy, grams(800));
      expect(summary.isHealthy, isFalse);
    });
  });

  group('low-stock suggestion idempotency', () {
    final today = DateKey.fromYmd(2026, 7, 28);

    ItemStock lowPotato({int remainingG = 2500, int thresholdG = 3000}) => ItemStock(
          itemId: 'potato',
          totalRemaining: grams(remainingG),
          batchCount: 1,
          isLowStock: true,
          lowStockThreshold: grams(thresholdG),
        );

    ShoppingEntry autoEntry({
      String id = 'e1',
      ShoppingEntryOrigin origin = ShoppingEntryOrigin.autoLowStock,
      ShoppingEntryAutoState autoState = ShoppingEntryAutoState.active,
      int? stockAtGenerationG,
      DateKey? snoozeUntil,
    }) =>
        ShoppingEntry(
          id: id,
          listId: 'L',
          origin: origin,
          autoState: autoState,
          isChecked: false,
          sortOrder: 0,
          itemId: 'potato',
          quantity: grams(500),
          stockAtGeneration: stockAtGenerationG == null ? null : grams(stockAtGenerationG),
          snoozeUntilDateKey: snoozeUntil,
        );

    test('running generation five times yields exactly one entry', () {
      // The engine is pure, so "running it five times" means: create once, then refresh — never a
      // second create. Simulated by feeding back the entry the previous run would have written.
      final existing = <ShoppingEntry>[];
      final actions = <SuggestionAction>[];

      for (var run = 0; run < 5; run++) {
        final decisions = suggestions.decide(
          lowStock: [lowPotato()],
          existingAutoEntries: existing,
          today: today,
        );
        final decision = decisions.single;
        actions.add(decision.action);

        if (decision.action == SuggestionAction.create) {
          existing.add(autoEntry(stockAtGenerationG: 2500));
        }
      }

      expect(actions.first, SuggestionAction.create);
      expect(actions.skip(1), everyElement(SuggestionAction.refresh),
          reason: 'runs 2-5 must refresh in place, never create again');
      expect(existing, hasLength(1), reason: 'exactly ONE auto entry after five runs');
    });

    test('the suggested quantity is the shortfall against the threshold', () {
      final decision = suggestions
          .decide(lowStock: [lowPotato()], existingAutoEntries: const [], today: today)
          .single;

      expect(decision.suggestedQuantity, grams(500), reason: '3000 threshold - 2500 on hand');
      expect(decision.stockAtDecision, grams(2500));
    });

    test('after the user edits it, regeneration does not touch it', () {
      // Editing promotes origin to manual — that is what ShoppingRepository.saveEntry does.
      final edited = autoEntry(origin: ShoppingEntryOrigin.manual, stockAtGenerationG: 2500);

      final decision = suggestions
          .decide(lowStock: [lowPotato()], existingAutoEntries: [edited], today: today)
          .single;

      expect(decision.action, SuggestionAction.leaveAlone);
      expect(decision.suggestedQuantity, isNull,
          reason: 'nothing is suggested, so nothing can overwrite the user\'s quantity');
      expect(decision.reason, contains('user'));
    });

    test('an item no longer low is left alone', () {
      final decision = suggestions
          .decide(
            lowStock: [
              ItemStock(
                itemId: 'potato',
                totalRemaining: grams(4000),
                batchCount: 1,
                isLowStock: false,
                lowStockThreshold: grams(3000),
              ),
            ],
            existingAutoEntries: const [],
            today: today,
          )
          .single;

      expect(decision.action, SuggestionAction.leaveAlone);
    });

    test('an item with no threshold is never suggested', () {
      final decision = suggestions
          .decide(
            lowStock: [
              ItemStock(
                itemId: 'salt',
                totalRemaining: grams(10),
                batchCount: 1,
                isLowStock: false,
              ),
            ],
            existingAutoEntries: const [],
            today: today,
          )
          .single;

      expect(decision.action, SuggestionAction.leaveAlone);
    });

    group('dismissal is not a timer', () {
      test('dismissed and stock unchanged stays suppressed', () {
        final decision = suggestions
            .decide(
              lowStock: [lowPotato()],
              existingAutoEntries: [
                autoEntry(
                  autoState: ShoppingEntryAutoState.dismissed,
                  stockAtGenerationG: 2500,
                ),
              ],
              today: today,
            )
            .single;

        expect(decision.action, SuggestionAction.leaveAlone);
      });

      test('dismissed and stock fell FURTHER still stays suppressed', () {
        final decision = suggestions
            .decide(
              lowStock: [lowPotato(remainingG: 1000)],
              existingAutoEntries: [
                autoEntry(
                  autoState: ShoppingEntryAutoState.dismissed,
                  stockAtGenerationG: 2500,
                ),
              ],
              today: today,
            )
            .single;

        expect(decision.action, SuggestionAction.leaveAlone,
            reason: 'they said no to this shortage; a worse one is the same shortage');
      });

      test('restocked above the dismissal reading, then low again, brings it back', () {
        final decision = suggestions
            .decide(
              lowStock: [lowPotato(remainingG: 2800)],
              existingAutoEntries: [
                autoEntry(
                  autoState: ShoppingEntryAutoState.dismissed,
                  stockAtGenerationG: 2500,
                ),
              ],
              today: today,
            )
            .single;

        expect(decision.action, SuggestionAction.refresh,
            reason: 'stock rose above 2500, so they bought some and ran low again');
      });

      test('a snooze still in force suppresses', () {
        final decision = suggestions
            .decide(
              lowStock: [lowPotato()],
              existingAutoEntries: [
                autoEntry(
                  autoState: ShoppingEntryAutoState.snoozed,
                  stockAtGenerationG: 2500,
                  snoozeUntil: DateKey.fromYmd(2026, 8, 5),
                ),
              ],
              today: today,
            )
            .single;

        expect(decision.action, SuggestionAction.leaveAlone);
      });

      test('an expired snooze returns, because a snooze IS a timer', () {
        final decision = suggestions
            .decide(
              lowStock: [lowPotato()],
              existingAutoEntries: [
                autoEntry(
                  autoState: ShoppingEntryAutoState.snoozed,
                  stockAtGenerationG: 2500,
                  snoozeUntil: DateKey.fromYmd(2026, 7, 20),
                ),
              ],
              today: today,
            )
            .single;

        expect(decision.action, SuggestionAction.refresh);
      });
    });
  });

  group('purchase fan-out', () {
    final transaction = Transaction(
      id: 't1',
      kind: TransactionKind.withdrawal,
      subtype: TransactionSubtype.electronics,
      occurredAtUtc: DateTime.utc(2026, 7, 28),
      dateKey: DateKey.fromYmd(2026, 7, 28),
      originalAmount: const Money(4500000, 'INR'),
      needsReview: false,
      fromAccountId: 'bank',
    );

    TransactionLine line({
      required TransactionLineDestination destination,
      String description = 'LG 55 inch TV',
      String? itemId,
      Qty? quantity,
      Money? lineAmount = const Money(4500000, 'INR'),
      // A line bound for inventory must name a unit: `unit_code_at_purchase` is a foreign key into
      // `units`, and `_planBatch` refuses a null rather than defaulting it to `''` and failing later
      // as `FOREIGN KEY constraint failed`.
      String? unitCode = 'pc',
    }) =>
        TransactionLine(
          id: 'l1',
          transactionId: 't1',
          lineNo: 1,
          description: description,
          destination: destination,
          itemId: itemId,
          quantity: quantity,
          unitCode: unitCode,
          lineAmount: lineAmount,
        );

    test('destination=asset creates an Asset and NO batch', () {
      final plan = fanOut
          .plan(
            line: line(destination: TransactionLineDestination.asset),
            transaction: transaction,
            newArtefactId: 'a1',
          )
          .valueOrNull!;

      expect(plan.target, FanOutTarget.asset);
      expect(plan.asset, isNotNull);
      expect(plan.batch, isNull,
          reason: 'a television is serviced and warrantied, not consumed in portions (A12)');
      expect(plan.isWellFormed, isTrue);
    });

    test('the created asset carries the line back, so createdAssetId can be written', () {
      final plan = fanOut
          .plan(
            line: line(destination: TransactionLineDestination.asset),
            transaction: transaction,
            newArtefactId: 'a1',
          )
          .valueOrNull!;

      expect(plan.lineId, 'l1', reason: 'the caller writes createdAssetId back to this line');
      expect(plan.asset!.id, 'a1');
      expect(plan.asset!.sourceTransactionLineId, 'l1');
      expect(plan.asset!.name, 'LG 55 inch TV');
      expect(plan.asset!.purchasePrice, const Money(4500000, 'INR'));
      expect(plan.asset!.purchaseDateKey, DateKey.fromYmd(2026, 7, 28));
    });

    test('a line bound for inventory with no unit is refused, not defaulted', () {
      // The empty-string default turned a missing value into `FOREIGN KEY constraint failed` several
      // layers away, after the transaction had already committed (ARCH_4 R30's family).
      final result = fanOut.plan(
        line: line(
          destination: TransactionLineDestination.inventory,
          itemId: 'i1',
          quantity: const Qty(2000, UnitCategory.count),
          unitCode: null,
        ),
        transaction: transaction,
        newArtefactId: 'b1',
      );
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull!.message, contains('no unit'));
    });


    test('destination=inventory creates a Batch and NO asset', () {
      final plan = fanOut
          .plan(
            line: line(
              destination: TransactionLineDestination.inventory,
              description: 'Potatoes',
              itemId: 'potato',
              quantity: grams(2000),
            ),
            transaction: transaction,
            newArtefactId: 'b1',
          )
          .valueOrNull!;

      expect(plan.target, FanOutTarget.batch);
      expect(plan.batch, isNotNull);
      expect(plan.asset, isNull);
      expect(plan.batch!.initialQuantity, grams(2000));
      expect(plan.batch!.remainingQuantity, grams(2000),
          reason: 'nothing consumed yet, and BatchRepository.create requires this');
      expect(plan.batch!.origin, BatchOrigin.purchase);
      expect(plan.batch!.sourceTransactionLineId, 'l1');
    });

    test('destination=none creates nothing', () {
      final plan = fanOut
          .plan(
            line: line(destination: TransactionLineDestination.none, description: 'Service fee'),
            transaction: transaction,
            newArtefactId: 'x1',
          )
          .valueOrNull!;

      expect(plan.createsArtefact, isFalse);
      expect(plan.batch, isNull);
      expect(plan.asset, isNull);
      expect(plan.isWellFormed, isTrue);
    });

    test('destination=recurring names a template but does not invent a schedule', () {
      final plan = fanOut
          .plan(
            line: line(destination: TransactionLineDestination.recurring, description: 'Netflix'),
            transaction: transaction,
            newArtefactId: 'r1',
          )
          .valueOrNull!;

      expect(plan.target, FanOutTarget.recurringTemplate);
      expect(plan.recurringTemplateName, 'Netflix');
      expect(plan.batch, isNull);
      expect(plan.asset, isNull);
    });

    test('an inventory line without an item is refused', () {
      final result = fanOut.plan(
        line: line(destination: TransactionLineDestination.inventory, quantity: grams(100)),
        transaction: transaction,
        newArtefactId: 'b1',
      );

      expect(result.isFailure, isTrue);
    });

    test('an inventory line without a quantity is refused rather than guessed', () {
      final result = fanOut.plan(
        line: line(destination: TransactionLineDestination.inventory, itemId: 'potato'),
        transaction: transaction,
        newArtefactId: 'b1',
      );

      expect(result.isFailure, isTrue,
          reason: 'a batch with a guessed quantity is stock the user never bought');
    });

    test('planAll skips lines that already produced an artefact, so a retry is safe', () {
      final lines = [
        TransactionLine(
          id: 'l1',
          transactionId: 't1',
          lineNo: 1,
          description: 'Already done',
          destination: TransactionLineDestination.asset,
          createdAssetId: 'a-existing',
        ),
        line(destination: TransactionLineDestination.asset, description: 'New TV'),
      ];

      final plans = fanOut
          .planAll(lines: lines, transaction: transaction, newArtefactIds: ['x', 'a2'])
          .valueOrNull!;

      expect(plans, hasLength(1));
      expect(plans.single.asset!.name, 'New TV');
    });
  });
}
```

### `test/domain/recurring_engine_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/services/recurring_engine.dart';

/// The recurring schedule: month-end clamping, lazy materialisation, settlement and skipping.
///
/// `RecurringEngine` is pure and takes every date it needs, so the calendar under test is fixed
/// rather than whatever day the suite happens to run on.
void main() {
  const engine = RecurringEngine();

  RecurringTemplate template({
    String id = 'rent',
    RecurringIntervalUnit unit = RecurringIntervalUnit.month,
    int count = 1,
    int? anchorDay = 1,
    required DateKey startDateKey,
    required DateKey nextDueDateKey,
    DateKey? endDateKey,
    RecurringDirection direction = RecurringDirection.outflow,
    int defaultMinor = 2500000,
    String currency = 'INR',
    bool isPaused = false,
  }) =>
      RecurringTemplate(
        id: id,
        name: 'Rent',
        normalizedName: 'rent',
        kind: RecurringKind.bill,
        direction: direction,
        defaultAmount: Money(defaultMinor, currency),
        intervalUnit: unit,
        intervalCount: count,
        startDateKey: startDateKey,
        nextDueDateKey: nextDueDateKey,
        isPaused: isPaused,
        autoRemind: false,
        remindDaysBefore: 1,
        anchorDayOfMonth: anchorDay,
        endDateKey: endDateKey,
        payeeId: 'landlord',
        tagId: 'tag-rent',
      );

  group('month-end clamp — anomaly A13', () {
    test('anchored on day 31 from 31 Jan gives 31, 28, 31, 30 — not 28, 28, 28', () {
      final anchored31 = template(
        anchorDay: 31,
        startDateKey: DateKey.fromYmd(2026, 1, 31),
        nextDueDateKey: DateKey.fromYmd(2026, 1, 31),
      );

      final dates = <DateKey>[DateKey.fromYmd(2026, 1, 31)];
      for (var i = 0; i < 3; i++) {
        dates.add(engine.nextDue(from: dates.last, template: anchored31));
      }

      expect(dates.map((d) => d.value).toList(), [20260131, 20260228, 20260331, 20260430]);
    });

    test('March returns to the 31st, proving the ANCHOR is clamped and not the current day', () {
      final anchored31 = template(
        anchorDay: 31,
        startDateKey: DateKey.fromYmd(2026, 1, 31),
        nextDueDateKey: DateKey.fromYmd(2026, 1, 31),
      );

      // February is the 28th...
      final february = engine.nextDue(
        from: DateKey.fromYmd(2026, 1, 31),
        template: anchored31,
      );
      expect(february, DateKey.fromYmd(2026, 2, 28));

      // ...and advancing from that clamped date must still land on the 31st, not the 28th.
      final march = engine.nextDue(from: february, template: anchored31);
      expect(march, DateKey.fromYmd(2026, 3, 31),
          reason: 'advancing from the clamped 28th would walk the bill back permanently');
    });

    test('a leap year clamps February to the 29th', () {
      final anchored31 = template(
        anchorDay: 31,
        startDateKey: DateKey.fromYmd(2024, 1, 31),
        nextDueDateKey: DateKey.fromYmd(2024, 1, 31),
      );

      final dates = <DateKey>[DateKey.fromYmd(2024, 1, 31)];
      for (var i = 0; i < 3; i++) {
        dates.add(engine.nextDue(from: dates.last, template: anchored31));
      }

      expect(dates.map((d) => d.value).toList(), [20240131, 20240229, 20240331, 20240430]);
    });

    test('a full year from 31 Jan never loses the anchor', () {
      final anchored31 = template(
        anchorDay: 31,
        startDateKey: DateKey.fromYmd(2026, 1, 31),
        nextDueDateKey: DateKey.fromYmd(2026, 1, 31),
      );

      var cursor = DateKey.fromYmd(2026, 1, 31);
      final days = <int>[cursor.day];
      for (var i = 0; i < 12; i++) {
        cursor = engine.nextDue(from: cursor, template: anchored31);
        days.add(cursor.day);
      }

      expect(days, [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31, 31],
          reason: 'every 31-day month gets its 31st back');
    });

    test('the clamp helper resolves February in both kinds of year', () {
      expect(engine.clampDayOfMonth(31, 2026, 2), 28);
      expect(engine.clampDayOfMonth(31, 2024, 2), 29);
      expect(engine.clampDayOfMonth(31, 2026, 4), 30);
      expect(engine.clampDayOfMonth(15, 2026, 2), 15, reason: 'a day that fits is untouched');
    });

    test('a yearly template anchored on 29 Feb clamps, then recovers four years on', () {
      final leapDay = template(
        unit: RecurringIntervalUnit.year,
        anchorDay: 29,
        startDateKey: DateKey.fromYmd(2024, 2, 29),
        nextDueDateKey: DateKey.fromYmd(2024, 2, 29),
      );

      var cursor = DateKey.fromYmd(2024, 2, 29);
      final seen = <int>[];
      for (var i = 0; i < 4; i++) {
        cursor = engine.nextDue(from: cursor, template: leapDay);
        seen.add(cursor.value);
      }

      expect(seen, [20250228, 20260228, 20270228, 20280229]);
    });

    test('day and week intervals cross month and year boundaries', () {
      final daily = template(
        unit: RecurringIntervalUnit.day,
        anchorDay: null,
        startDateKey: DateKey.fromYmd(2026, 12, 31),
        nextDueDateKey: DateKey.fromYmd(2026, 12, 31),
      );
      final weekly = template(
        unit: RecurringIntervalUnit.week,
        anchorDay: null,
        startDateKey: DateKey.fromYmd(2026, 2, 26),
        nextDueDateKey: DateKey.fromYmd(2026, 2, 26),
      );

      expect(engine.nextDue(from: DateKey.fromYmd(2026, 12, 31), template: daily),
          DateKey.fromYmd(2027, 1, 1));
      expect(engine.nextDue(from: DateKey.fromYmd(2026, 2, 26), template: weekly),
          DateKey.fromYmd(2026, 3, 5));
    });

    test('a quarterly template anchored on 31 clamps per target month', () {
      final quarterly = template(
        count: 3,
        anchorDay: 31,
        startDateKey: DateKey.fromYmd(2026, 1, 31),
        nextDueDateKey: DateKey.fromYmd(2026, 1, 31),
      );

      expect(engine.nextDue(from: DateKey.fromYmd(2026, 1, 31), template: quarterly),
          DateKey.fromYmd(2026, 4, 30));
    });
  });

  group('lazy materialisation — anomaly A14', () {
    final today = DateKey.fromYmd(2026, 7, 28);

    test('a template last due three months ago yields exactly three occurrences', () {
      final behind = template(
        startDateKey: DateKey.fromYmd(2026, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2026, 5, 1),
      );

      final plan = engine.planMaterialisation(template: behind, asOf: today);

      expect(plan.occurrences, hasLength(3));
      expect(plan.occurrences.map((o) => o.dueDateKey.value).toList(),
          [20260501, 20260601, 20260701]);
    });

    test('and creates ZERO transactions — money needs an explicit tap', () {
      final behind = template(
        startDateKey: DateKey.fromYmd(2026, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2026, 5, 1),
      );

      final plan = engine.planMaterialisation(template: behind, asOf: today);

      // The plan's only output is occurrences. There is no transaction field to populate, which is
      // the structural guarantee: a materialisation pass cannot create money even by mistake.
      expect(plan.occurrences.every((o) => o.templateId == 'rent'), isTrue);
      expect(plan.nextDueDateKey, DateKey.fromYmd(2026, 8, 1));
    });

    test('nextDueDateKey lands past today, ready for the following pass', () {
      final behind = template(
        startDateKey: DateKey.fromYmd(2026, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2026, 5, 1),
      );

      final plan = engine.planMaterialisation(template: behind, asOf: today);

      expect(plan.nextDueDateKey.isAfter(today), isTrue);
    });

    test('running again with those dates already present plans nothing', () {
      final behind = template(
        startDateKey: DateKey.fromYmd(2026, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2026, 5, 1),
      );

      final first = engine.planMaterialisation(template: behind, asOf: today);
      final second = engine.planMaterialisation(
        template: behind,
        asOf: today,
        alreadyMaterialised: first.occurrences.map((o) => o.dueDateKey),
      );

      expect(second.occurrences, isEmpty);
      expect(second.nextDueDateKey, first.nextDueDateKey,
          reason: 'the cursor must land identically either way, or the pass is not idempotent');
    });

    test('nothing due yet plans nothing and leaves the cursor alone', () {
      final future = template(
        startDateKey: DateKey.fromYmd(2026, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2026, 9, 1),
      );

      final plan = engine.planMaterialisation(template: future, asOf: today);

      expect(plan.isEmpty, isTrue);
      expect(plan.nextDueDateKey, DateKey.fromYmd(2026, 9, 1));
    });

    test('an end date stops materialisation', () {
      final ending = template(
        startDateKey: DateKey.fromYmd(2026, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2026, 5, 1),
        endDateKey: DateKey.fromYmd(2026, 6, 1),
      );

      final plan = engine.planMaterialisation(template: ending, asOf: today);

      expect(plan.occurrences.map((o) => o.dueDateKey.value).toList(), [20260501, 20260601]);
    });

    test('the anchor survives a materialisation run across February', () {
      final anchored31 = template(
        anchorDay: 31,
        startDateKey: DateKey.fromYmd(2026, 1, 31),
        nextDueDateKey: DateKey.fromYmd(2026, 1, 31),
      );

      final plan = engine.planMaterialisation(
        template: anchored31,
        asOf: DateKey.fromYmd(2026, 4, 30),
      );

      expect(plan.occurrences.map((o) => o.dueDateKey.value).toList(),
          [20260131, 20260228, 20260331, 20260430]);
      expect(plan.nextDueDateKey, DateKey.fromYmd(2026, 5, 31));
    });

    test('a daily template years behind stops at the safety bound instead of spinning', () {
      final daily = template(
        unit: RecurringIntervalUnit.day,
        anchorDay: null,
        startDateKey: DateKey.fromYmd(2024, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2024, 1, 1),
      );

      final plan = engine.planMaterialisation(template: daily, asOf: today);

      expect(plan.stoppedAtSafetyBound, isTrue);
      expect(plan.occurrences, hasLength(RecurringEngine.maxOccurrencesPerPass));
    });
  });

  group('settlement — direction decides the kind', () {
    final due = RecurringOccurrence(
      id: 'o1',
      templateId: 'rent',
      dueDateKey: DateKey.fromYmd(2026, 7, 1),
      status: RecurringOccurrenceStatus.due,
    );
    final paidOn = DateKey.fromYmd(2026, 7, 3);

    test('an outflow settles as a withdrawal from the account', () {
      final intent = engine
          .planSettlement(
            template: template(
              startDateKey: DateKey.fromYmd(2026, 1, 1),
              nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
            ),
            occurrence: due,
            amount: const Money(2500000, 'INR'),
            paidOn: paidOn,
            accountId: 'bank',
          )
          .valueOrNull!;

      expect(intent.kind, TransactionKind.withdrawal);
      expect(intent.fromAccountId, 'bank');
      expect(intent.toAccountId, isNull, reason: 'ARCH_2 §4.1 allows exactly one account');
    });

    test('an inflow settles as a deposit into the account', () {
      final intent = engine
          .planSettlement(
            template: template(
              direction: RecurringDirection.inflow,
              startDateKey: DateKey.fromYmd(2026, 1, 1),
              nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
            ),
            occurrence: due,
            amount: const Money(2500000, 'INR'),
            paidOn: paidOn,
            accountId: 'bank',
          )
          .valueOrNull!;

      expect(intent.kind, TransactionKind.deposit);
      expect(intent.toAccountId, 'bank');
      expect(intent.fromAccountId, isNull);
      expect(intent.subtype, TransactionSubtype.salaryIn,
          reason: 'one direction field is what lets salary share the system with bills (A27)');
    });

    test('the ACTUAL amount is carried, not the template default', () {
      final intent = engine
          .planSettlement(
            template: template(
              defaultMinor: 49900,
              startDateKey: DateKey.fromYmd(2026, 1, 1),
              nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
            ),
            occurrence: due,
            // Paid 520 against a 499 expectation.
            amount: const Money(52000, 'INR'),
            paidOn: paidOn,
            accountId: 'bank',
          )
          .valueOrNull!;

      expect(intent.amount, const Money(52000, 'INR'),
          reason: 'analytics uses actuals; the template keeps its expectation (A29)');
    });

    test('the payee and tag come from the template', () {
      final intent = engine
          .planSettlement(
            template: template(
              startDateKey: DateKey.fromYmd(2026, 1, 1),
              nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
            ),
            occurrence: due,
            amount: const Money(2500000, 'INR'),
            paidOn: paidOn,
            accountId: 'bank',
          )
          .valueOrNull!;

      expect(intent.payeeId, 'landlord');
      expect(intent.tagId, 'tag-rent');
      expect(intent.occurrenceId, 'o1');
      expect(intent.templateId, 'rent');
      expect(intent.dateKey, paidOn, reason: 'dated when paid, which may differ from when due');
    });

    test('an already-settled occurrence cannot be settled twice', () {
      final result = engine.planSettlement(
        template: template(
          startDateKey: DateKey.fromYmd(2026, 1, 1),
          nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
        ),
        occurrence: RecurringOccurrence(
          id: 'o1',
          templateId: 'rent',
          dueDateKey: DateKey.fromYmd(2026, 7, 1),
          status: RecurringOccurrenceStatus.paid,
        ),
        amount: const Money(2500000, 'INR'),
        paidOn: paidOn,
        accountId: 'bank',
      );

      expect(result.isFailure, isTrue);
      expect((result.failureOrNull! as BusinessRuleFailure).rule, 'occurrenceNotDue');
    });

    test('a payment in another currency is refused, not stored against the wrong code', () {
      final result = engine.planSettlement(
        template: template(
          startDateKey: DateKey.fromYmd(2026, 1, 1),
          nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
        ),
        occurrence: due,
        amount: const Money(600, 'USD'),
        paidOn: paidOn,
        accountId: 'bank',
      );

      expect(result.isFailure, isTrue,
          reason: 'recurring_occurrences has no currency column of its own (ARCH_2 §7)');
    });

    test('a zero amount is refused', () {
      final result = engine.planSettlement(
        template: template(
          startDateKey: DateKey.fromYmd(2026, 1, 1),
          nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
        ),
        occurrence: due,
        amount: const Money(0, 'INR'),
        paidOn: paidOn,
        accountId: 'bank',
      );

      expect(result.isFailure, isTrue);
    });

    test('an occurrence from a different template is refused', () {
      final result = engine.planSettlement(
        template: template(
          startDateKey: DateKey.fromYmd(2026, 1, 1),
          nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
        ),
        occurrence: RecurringOccurrence(
          id: 'o9',
          templateId: 'netflix',
          dueDateKey: DateKey.fromYmd(2026, 7, 1),
          status: RecurringOccurrenceStatus.due,
        ),
        amount: const Money(2500000, 'INR'),
        paidOn: paidOn,
        accountId: 'bank',
      );

      expect(result.isFailure, isTrue);
    });
  });

  group('skip and overdue', () {
    test('a due occurrence can be skipped', () {
      final result = engine.planSkip(
        RecurringOccurrence(
          id: 'o1',
          templateId: 'rent',
          dueDateKey: DateKey.fromYmd(2026, 7, 1),
          status: RecurringOccurrenceStatus.due,
        ),
      );

      expect(result.isFailure, isFalse);
    });

    test('a settled occurrence cannot be skipped', () {
      final result = engine.planSkip(
        RecurringOccurrence(
          id: 'o1',
          templateId: 'rent',
          dueDateKey: DateKey.fromYmd(2026, 7, 1),
          status: RecurringOccurrenceStatus.paid,
          paidTransactionId: 't1',
        ),
      );

      expect(result.isFailure, isTrue,
          reason: 'the money moved; skipping would leave a transaction with nothing explaining it');
    });

    test('overdue is derived from the date, never stored', () {
      final occurrence = RecurringOccurrence(
        id: 'o1',
        templateId: 'rent',
        dueDateKey: DateKey.fromYmd(2026, 7, 1),
        status: RecurringOccurrenceStatus.due,
      );

      expect(
        engine.isOverdue(occurrence: occurrence, today: DateKey.fromYmd(2026, 7, 28)),
        isTrue,
      );
      expect(
        engine.isOverdue(occurrence: occurrence, today: DateKey.fromYmd(2026, 6, 28)),
        isFalse,
      );
    });

    test('a paused template is not active', () {
      final paused = template(
        isPaused: true,
        startDateKey: DateKey.fromYmd(2026, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
      );

      expect(engine.isActive(template: paused, asOf: DateKey.fromYmd(2026, 7, 28)), isFalse);
    });
  });
}
```
