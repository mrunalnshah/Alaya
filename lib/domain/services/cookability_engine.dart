import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/recipe.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';

/// What the engine could determine about one ingredient.
///
/// **Six states, and two of them mean "I do not know".** Collapsing those into "missing" is the
/// single easiest way to make this feature lie: an app that reports *you cannot cook this* because
/// nobody tracks the stock level of salt has told the user something false with total confidence.
enum IngredientAvailability {
  /// Linked to an item, comparable units, and enough unexpired stock on hand.
  sufficient,

  /// Enough on hand, but only by drawing on stock that is past its date.
  ///
  /// **Not a shortfall, and deliberately not `short`.** The food exists and the cook may well want to
  /// use it — a jar a day past its date is a judgement call, not an absence. Reporting it as missing
  /// would grey out the Cook button and remove the choice, which is the same mistake as gating a
  /// recipe on inventory configuration.
  ///
  /// Only ever reported when batches were supplied to [CookabilityEngine.judge]. Without them the
  /// engine has a total and no way to split it, and it does not guess.
  needsExpired,

  /// Linked and comparable, but less unexpired stock on hand than the recipe needs — and not enough
  /// expired stock to close the gap either.
  short,

  /// Linked and comparable, with nothing at all on hand.
  outOfStock,

  /// Linked, but the recipe's unit and the item's are different dimensions — 200 g of something
  /// tracked by the piece. **No conversion exists**, so this is unanswerable rather than false.
  unitMismatch,

  /// No linked item, or no quantity given. "Salt to taste" is a real ingredient, not a missing one.
  untracked;

  /// Whether this state contributes to a shortfall the user could act on.
  ///
  /// [needsExpired] is excluded on purpose: nothing needs buying, and a shopping list built from this
  /// would add an item the user already has.
  bool get isMissing =>
      this == IngredientAvailability.short ||
      this == IngredientAvailability.outOfStock;

  /// Whether the engine declined to answer rather than answering no.
  bool get isUncheckable =>
      this == IngredientAvailability.unitMismatch ||
      this == IngredientAvailability.untracked;
}

/// The engine's verdict on one ingredient line.
class IngredientCheck {
  /// Creates a verdict.
  const IngredientCheck({
    required this.ingredient,
    required this.availability,
    required this.required_,
    this.onHand,
    this.shortfall,
    this.nearestExpiry,
    this.plan,
  });

  /// The line this verdict is about.
  final RecipeIngredient ingredient;

  /// What the engine could determine.
  final IngredientAvailability availability;

  /// How much the recipe needs after serving-scaling. Null when the line carries no quantity.
  final Qty? required_;

  /// How much is on hand, when that is comparable.
  ///
  /// The item's whole remaining stock, expired batches included — it is what `v_item_stock` sums and
  /// it is what "you have 500 g" means to a user standing at a cupboard. [plan] is what says how much
  /// of it this recipe could actually use.
  final Qty? onHand;

  /// How much more is needed. Null unless [availability] is [IngredientAvailability.short] or
  /// [IngredientAvailability.outOfStock] — which is what a shopping list would consume.
  final Qty? shortfall;

  /// The earliest expiry among batches of this item still holding stock.
  final DateKey? nearestExpiry;

  /// Which batches this ingredient would actually draw from, when batches were supplied.
  ///
  /// **The one value a confirmation sheet and the deduction must share.** It names the batches, the
  /// amounts, and how much of the total comes from stock past its date — so a sheet describing what
  /// will happen and a repository carrying it out read the same answer rather than each deriving one.
  /// ARCH_M §6: no value displayed from a second source.
  ///
  /// Produced by `InventoryConsumptionService`, which is the one definition of the draw order. A plan
  /// only exists when it is complete: the service refuses rather than returning a partial one, so a
  /// non-null plan here is always a plan that could be applied.
  ///
  /// Null when [CookabilityEngine.judge] was called without batches for this item, which is the
  /// cheap path a list screen uses. A null plan means "not computed", never "nothing to draw".
  final ConsumptionPlan? plan;
}

/// The headline verdict, for sorting a list and choosing one word to show.
enum CookabilityStatus {
  /// Every required ingredient is present in sufficient unexpired quantity, and every one could be
  /// checked.
  ready,

  /// Cookable, but at least one required ingredient would have to come partly from expired stock.
  ///
  /// **A distinct status because the two decisions differ.** `ready` needs no permission; this needs
  /// the cook to be asked. Folding it into [short] would disable the very control that offers the
  /// choice, and folding it into [ready] would deduct expired food silently — which is the fault this
  /// state exists to end.
  readyWithExpired,

  /// Some required ingredients are present but insufficient. Nothing is entirely absent.
  short,

  /// At least one required ingredient is entirely absent.
  blocked,

  /// Nothing is missing, but at least one required ingredient could not be checked, so the engine
  /// will not claim the recipe is ready.
  uncheckable,

  /// The recipe has no required ingredients at all. A note, not a recipe.
  empty,
}

/// Whether a recipe can be cooked from what is on hand.
///
/// **[missingCount] and [uncheckableCount] are reported separately because they are different
/// facts.** A recipe can be both short of two ingredients and uncertain about a third, and a single
/// enum would have to discard one of those. [status] is the headline; these are what a screen shows
/// underneath it.
class Cookability {
  /// Creates a verdict.
  const Cookability({
    required this.recipeId,
    required this.checks,
    required this.status,
    required this.missingCount,
    required this.uncheckableCount,
    required this.optionalMissingCount,
    required this.expiredCount,
    this.soonestExpiryUsed,
  });

  /// The recipe this verdict is about.
  final String recipeId;

  /// Every ingredient's verdict, in the recipe's own order.
  final List<IngredientCheck> checks;

  /// The headline.
  final CookabilityStatus status;

  /// How many required ingredients are short or absent.
  final int missingCount;

  /// How many required ingredients could not be checked at all.
  final int uncheckableCount;

  /// How many *optional* ingredients are short or absent. Never affects [status] — a missing
  /// garnish should not stop dinner — but worth saying.
  final int optionalMissingCount;

  /// How many required ingredients would draw on stock past its date.
  ///
  /// What a confirmation sheet counts. Separate from [missingCount] because nothing here is absent —
  /// summing them would tell the user to go shopping for food in their cupboard.
  final int expiredCount;

  /// The earliest expiry among the items this recipe would draw on.
  ///
  /// This is what "cook what expires soonest" sorts by. It comes free: [ItemStock] already computes
  /// `nearestExpiry` per item, so no batch query is needed here.
  ///
  /// It is the nearest expiry across *all* batches of each item, not specifically the batches a
  /// cook would draw from. For an ordering hint that is the right approximation, and saying so is
  /// better than implying a precision the figure does not have.
  final DateKey? soonestExpiryUsed;

  /// Whether the recipe can be cooked right now with no caveats.
  bool get isReady => status == CookabilityStatus.ready;

  /// Whether the recipe can be cooked, once the cook has agreed to use expired stock.
  bool get needsExpiredConsent => status == CookabilityStatus.readyWithExpired;

  /// Whether cooking is possible at all, with or without consent.
  bool get isCookable => isReady || needsExpiredConsent;
}

/// Answers "can I cook this from what is on hand", and declines to answer when it cannot.
///
/// Pure: entities in, verdicts out. No repository, no drift, no Flutter — so every branch below is
/// exercisable from literals, which is what the unit tests do.
///
/// **The engine never converts between unit categories.** Grams and pieces are different
/// dimensions and no factor relates them; an item tracked by count cannot answer a question asked
/// in grams. That is reported as [IngredientAvailability.unitMismatch] and propagates to
/// [CookabilityStatus.uncheckable] rather than being silently treated as zero.
///
/// **The engine does not decide the draw order either.** `InventoryConsumptionService` owns it, and
/// this class asks — because the order a verdict assumes and the order a deduction performs must be
/// the same one. A separate planner written here would be the third copy of that rule, and the
/// service's own doc explains what happens to the second.
///
/// **Expiry is a two-tier answer, on purpose.** `ItemStock.totalRemaining` comes from `v_item_stock`,
/// which sums every batch holding stock with **no expiry filter** — so a total alone cannot say how
/// much of it is still good. Supplying batches for an item buys a precise answer and a
/// [ConsumptionPlan]; omitting them keeps the previous behaviour, which is what a list of forty
/// recipes wants. The engine never splits the difference by guessing.
class CookabilityEngine {
  /// Creates the engine. Stateless.
  const CookabilityEngine();

  static const InventoryConsumptionService _consumption =
      InventoryConsumptionService();

  /// Scales a stored milli-quantity from [fromServings] to [toServings].
  ///
  /// **Integer ceiling division, and the direction is deliberate.** Rounding 66.67 g down to 66 g
  /// would let the engine report *ready* when the cook is short; rounding up can only overstate a
  /// requirement. A false "you have enough" ruins dinner; a false "you are 1 g short" is a shrug.
  ///
  /// No doubles anywhere (Law L1).
  static int scaleMilli(
    int milli, {
    required int fromServings,
    required int toServings,
  }) {
    if (fromServings <= 0) {
      throw ArgumentError.value(
        fromServings,
        'fromServings',
        'must be positive',
      );
    }
    if (toServings == fromServings) return milli;
    final numerator = milli * toServings;
    // Ceiling for positives; recipe quantities are never negative, but the guard keeps the
    // arithmetic honest if one ever is.
    return numerator >= 0
        ? (numerator + fromServings - 1) ~/ fromServings
        : -((-numerator + fromServings - 1) ~/ fromServings);
  }

  /// Judges [recipe] against [stock], scaled to [servings] if given.
  ///
  /// [stock] and [items] are keyed by item id. An ingredient whose item is absent from [items] is
  /// treated as untracked rather than missing — the item may have been deleted, and inventing a
  /// verdict about a row that no longer exists would be a guess.
  ///
  /// [today] decides what counts as expired, and is required rather than read from a clock so the
  /// engine stays pure and a date-sensitive verdict is reproducible under a `FixedClock`. It is the
  /// same rule `ConsumableBatch.isExpired` and the views follow.
  ///
  /// [batchesByItem] is optional and keyed by item id, in any order — the consumption service sorts.
  /// Supply it and the engine answers precisely: which batches, how much from each, and how much of it
  /// is past its date. Omit it and expiry is not considered at all, which is the previous behaviour and
  /// the right trade for a list screen judging forty recipes.
  ///
  /// **Omitting it can overstate availability**, because `totalRemaining` includes expired batches.
  /// That is a deliberate approximation of the same kind [Cookability.soonestExpiryUsed] documents,
  /// and it is why the cook path and the detail screen both supply batches.
  Cookability judge(
    Recipe recipe, {
    required Map<String, ItemStock> stock,
    required Map<String, Item> items,
    required DateKey today,
    Map<String, List<ConsumableBatch>> batchesByItem = const {},
    int? servings,
  }) {
    final target = servings ?? recipe.servings;
    final checks = <IngredientCheck>[];
    var missing = 0;
    var uncheckable = 0;
    var optionalMissing = 0;
    var required = 0;
    var expired = 0;
    DateKey? soonest;

    for (final ingredient in recipe.ingredients) {
      final check = _check(
        ingredient,
        stock: stock,
        items: items,
        today: today,
        batchesByItem: batchesByItem,
        fromServings: recipe.servings,
        toServings: target,
      );
      checks.add(check);

      final expiry = check.nearestExpiry;
      // `isBefore` rather than comparing the representation int. `DateKey` is an extension type
      // over `int`, so `.value` would compile — and reading the representation is exactly the
      // habit the type exists to discourage.
      if (expiry != null && (soonest == null || expiry.isBefore(soonest))) {
        soonest = expiry;
      }

      if (ingredient.isOptional) {
        if (check.availability.isMissing) optionalMissing++;
        continue;
      }
      required++;
      if (check.availability.isMissing) missing++;
      if (check.availability.isUncheckable) uncheckable++;
      if (check.availability == IngredientAvailability.needsExpired) expired++;
    }

    return Cookability(
      recipeId: recipe.id,
      checks: checks,
      status: _statusFor(
        requiredCount: required,
        missing: missing,
        uncheckable: uncheckable,
        expired: expired,
        anyAbsent: checks.any(
          (c) =>
              !c.ingredient.isOptional &&
              c.availability == IngredientAvailability.outOfStock,
        ),
      ),
      missingCount: missing,
      uncheckableCount: uncheckable,
      optionalMissingCount: optionalMissing,
      expiredCount: expired,
      soonestExpiryUsed: soonest,
    );
  }

  IngredientCheck _check(
    RecipeIngredient ingredient, {
    required Map<String, ItemStock> stock,
    required Map<String, Item> items,
    required DateKey today,
    required Map<String, List<ConsumableBatch>> batchesByItem,
    required int fromServings,
    required int toServings,
  }) {
    final itemId = ingredient.itemId;
    final quantity = ingredient.quantity;

    // No link, or no quantity to compare. Both are ordinary, and neither is a shortfall.
    if (itemId == null || quantity == null) {
      return IngredientCheck(
        ingredient: ingredient,
        availability: IngredientAvailability.untracked,
        required_: quantity,
      );
    }

    final item = items[itemId];
    final onHand = stock[itemId];
    if (item == null || onHand == null) {
      return IngredientCheck(
        ingredient: ingredient,
        availability: IngredientAvailability.untracked,
        required_: quantity,
      );
    }

    // Different dimensions are convertible only if the item states how it bridges them. A null
    // bridge is not a failure — it is the engine declining, which is the whole point of the module.
    final wanted = item.unitCategory == quantity.category
        ? quantity
        : _bridge(quantity, item);
    if (wanted == null) {
      return IngredientCheck(
        ingredient: ingredient,
        availability: IngredientAvailability.unitMismatch,
        // The amount as the cook wrote it, not a conversion that could not be made.
        required_: quantity,
        onHand: onHand.totalRemaining,
        nearestExpiry: onHand.nearestExpiry,
      );
    }

    final needed = Qty(
      scaleMilli(
        wanted.milliBase,
        fromServings: fromServings,
        toServings: toServings,
      ),
      wanted.category,
    );

    final have = onHand.totalRemaining;
    final batches = batchesByItem[itemId];

    // **The precise path.** Batches were supplied, so the split between good and expired stock is
    // knowable and the answer carries the plan that will be executed.
    if (batches != null && needed.isPositive) {
      return _checkWithBatches(
        ingredient,
        batches: batches,
        needed: needed,
        onHand: onHand,
        today: today,
      );
    }

    // The cheap path: a total, no split. Expiry is not considered — see [judge]'s note.
    //
    // A zero requirement lands here too, deliberately. The consumption service refuses a non-positive
    // quantity as a validation error, which is right for a real consumption and wrong as a verdict —
    // "0 g of flour" is trivially satisfied, and it was `sufficient` before batches existed.
    if (have.milliBase >= needed.milliBase) {
      return IngredientCheck(
        ingredient: ingredient,
        availability: IngredientAvailability.sufficient,
        required_: needed,
        onHand: have,
        nearestExpiry: onHand.nearestExpiry,
      );
    }

    return IngredientCheck(
      ingredient: ingredient,
      availability: have.isZero
          ? IngredientAvailability.outOfStock
          : IngredientAvailability.short,
      required_: needed,
      onHand: have,
      shortfall: Qty(needed.milliBase - have.milliBase, needed.category),
      nearestExpiry: onHand.nearestExpiry,
    );
  }

  /// The verdict when batches are known, derived from `InventoryConsumptionService`.
  ///
  /// **Two calls, three answers.** The service refuses rather than returning a partial plan, so the
  /// question "would consent help?" is asked by planning again with consent rather than by inspecting
  /// a plan nobody may apply. Planning succeeds on good stock alone, or succeeds only once expired
  /// stock is permitted, or fails both ways — and there is no fourth outcome.
  IngredientCheck _checkWithBatches(
    RecipeIngredient ingredient, {
    required List<ConsumableBatch> batches,
    required Qty needed,
    required ItemStock onHand,
    required DateKey today,
  }) {
    final fresh = _consumption.plan(
      batches: batches,
      needed: needed,
      policy: DrawPolicy.freshFirst(today: today),
    );
    if (fresh.isOk) {
      return IngredientCheck(
        ingredient: ingredient,
        availability: IngredientAvailability.sufficient,
        required_: needed,
        onHand: onHand.totalRemaining,
        nearestExpiry: onHand.nearestExpiry,
        plan: fresh.valueOrNull,
      );
    }

    final permitted = _consumption.plan(
      batches: batches,
      needed: needed,
      policy: DrawPolicy.freshFirst(today: today, allowExpired: true),
    );

    // A validation failure is not a shortfall — it means the caller handed over batches in a category
    // the requirement was never bridged into. Reporting `short` would be a confident falsehood about
    // stock the engine simply could not compare, so it declines instead, exactly as a null bridge does.
    if (permitted.failureOrNull is ValidationFailure) {
      return IngredientCheck(
        ingredient: ingredient,
        availability: IngredientAvailability.unitMismatch,
        required_: needed,
        onHand: onHand.totalRemaining,
        nearestExpiry: onHand.nearestExpiry,
      );
    }

    if (permitted.isOk) {
      return IngredientCheck(
        ingredient: ingredient,
        availability: IngredientAvailability.needsExpired,
        required_: needed,
        onHand: onHand.totalRemaining,
        nearestExpiry: onHand.nearestExpiry,
        // The plan that would actually run once the cook agrees. Handing over the fresh-only attempt
        // would mean the sheet describing the consent and the deduction performing it were different
        // objects — and it failed, so there is no plan on it to hand over.
        plan: permitted.valueOrNull,
      );
    }

    // Not enough even counting expired stock. Summed from the batches rather than read from the
    // rollup, because the batches are what was planned against and a stale `v_item_stock` row would
    // otherwise put a number on screen the deduction could not honour.
    var availableMilli = 0;
    for (final batch in batches) {
      if (batch.remaining.isPositive)
        availableMilli += batch.remaining.milliBase;
    }
    return IngredientCheck(
      ingredient: ingredient,
      // `outOfStock` only when there is nothing usable at all, expired included — a cupboard holding
      // something past its date is not empty.
      availability: availableMilli > 0
          ? IngredientAvailability.short
          : IngredientAvailability.outOfStock,
      required_: needed,
      onHand: onHand.totalRemaining,
      shortfall: Qty(needed.milliBase - availableMilli, needed.category),
      nearestExpiry: onHand.nearestExpiry,
    );
  }

  /// Converts [quantity] into [item]'s own dimension, or null when the item cannot say how.
  ///
  /// **Only the item knows the conversion.** A tablespoon is 14.787 ml for everything, but a
  /// tablespoon of butter and one of flour weigh different amounts — so volume-to-weight needs
  /// `densityMilliGramsPerMl`, and count-to-weight needs `milliGramsPerPiece`. Both are nullable,
  /// and null keeps the answer *unanswerable* rather than turning it into a guess.
  ///
  /// Only bridging **to** weight is implemented. An item kept by volume asked for in grams needs the
  /// inverse of the same number; it is easy to add and nothing has needed it, so this returns null
  /// rather than shipping a path no test exercises.
  static Qty? _bridge(Qty quantity, Item item) {
    if (item.unitCategory != UnitCategory.weight) return null;

    final factor = switch (quantity.category) {
      // milliBase is thousandths of a millilitre; density is milli-grams per whole millilitre.
      UnitCategory.volume => item.densityMilliGramsPerMl,
      UnitCategory.count => item.milliGramsPerPiece,
      UnitCategory.weight => null,
    };
    if (factor == null) return null;
    // Multiply before dividing, so integer arithmetic keeps its precision (Law L1).
    return Qty(quantity.milliBase * factor ~/ 1000, UnitCategory.weight);
  }

  CookabilityStatus _statusFor({
    required int requiredCount,
    required int missing,
    required int uncheckable,
    required int expired,
    required bool anyAbsent,
  }) {
    if (requiredCount == 0) return CookabilityStatus.empty;
    if (anyAbsent) return CookabilityStatus.blocked;
    if (missing > 0) return CookabilityStatus.short;
    // Nothing missing — but the engine will not claim "ready" while it could not check everything.
    if (uncheckable > 0) return CookabilityStatus.uncheckable;
    // **Below `uncheckable`, above `ready`.** An unanswerable ingredient is the more important
    // caveat: it means the verdict itself is incomplete, whereas this one is a complete verdict that
    // happens to need permission.
    if (expired > 0) return CookabilityStatus.readyWithExpired;
    return CookabilityStatus.ready;
  }
}
