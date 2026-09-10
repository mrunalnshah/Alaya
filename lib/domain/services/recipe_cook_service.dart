import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/recipe.dart';
import 'package:alaya/domain/repositories/recipe_repository.dart';
import 'package:alaya/domain/repositories/stock_repository.dart';
import 'package:alaya/domain/services/cookability_engine.dart';
import 'package:alaya/domain/services/draw_policy.dart';

/// What one cook did to inventory.
class CookOutcome {
  /// Creates an outcome.
  const CookOutcome({
    required this.cook,
    required this.deducted,
    required this.skipped,
  });

  /// The log entry written.
  final RecipeCook cook;

  /// The item ids whose stock was reduced.
  final List<String> deducted;

  /// The ingredients that could not be deducted, and why.
  ///
  /// Never empty on a recipe with untracked lines, which is most real recipes. A cook that deducted
  /// four of six ingredients and said nothing about the other two would leave the user believing
  /// their inventory is more accurate than it is.
  final List<IngredientCheck> skipped;
}

/// Cooking a recipe: deduct what it used, and record that it happened.
///
/// **Deducts through [StockRepository.consume], which is atomic.** This service adds no consumption
/// logic of its own — it maps a scaled ingredient list onto calls the inventory module already makes,
/// so a cook and a manual "use some" produce the same shape of movement and the same batch ordering
/// for the same policy.
///
/// **It chooses the policy, and that is the whole of the expiry fix.** `consume` defaults to FEFO,
/// which orders by nearest expiry — and an expired date is the nearest date, so the default reaches for
/// food that is already off before touching anything good. Correct for a write-off, wrong for cooking.
/// This service passes `DrawPolicy.freshFirst`, so good stock is spent first and expired stock is
/// touched only when the cook has said so.
class RecipeCookService {
  /// Creates the service.
  const RecipeCookService({
    required RecipeRepository recipes,
    required StockRepository stock,
    required Clock clock,
    CookabilityEngine engine = const CookabilityEngine(),
  }) : _recipes = recipes,
       _stock = stock,
       _clock = clock,
       _engine = engine;

  final RecipeRepository _recipes;
  final StockRepository _stock;
  final Clock _clock;
  final CookabilityEngine _engine;

  /// Cooks [recipe] at [servings], deducting stock unless [deductStock] is false.
  ///
  /// **Refuses the whole cook when a required ingredient is short**, unless [allowPartial]. That is
  /// `InventoryConsumptionService`'s own contract — it fails with `insufficientStock` rather than
  /// half-applying, because a ledger describing a consumption that only half happened is worse than
  /// one that did not happen. Overriding it from here would be arguing with a decision the
  /// inventory module already made carefully.
  ///
  /// Ingredients the engine could not check — untracked, or a unit mismatch — are **skipped, not
  /// failed**. Nobody tracks salt, and refusing to cook because of it would make the feature
  /// unusable. They come back in [CookOutcome.skipped] so the screen can say so.
  ///
  /// **[allowExpired] is the cook's answer, not a default worth guessing.** False means good stock only:
  /// a recipe that could be made solely from food past its date fails with `insufficientStock` rather
  /// than quietly eating it, which is what happened before this parameter existed. True means the user
  /// was asked and said yes — so the caller must have asked. `CookabilityStatus.readyWithExpired` is
  /// how a screen knows the question is worth putting.
  Future<Result<CookOutcome, Failure>> cook({
    required Recipe recipe,
    required Map<String, ItemStock> stock,
    required Map<String, Item> items,
    int? servings,
    bool deductStock = true,
    bool allowPartial = false,
    bool allowExpired = false,
    String? note,
  }) async {
    final target = servings ?? recipe.servings;
    final today = _clock.today();
    final verdict = _engine.judge(
      recipe,
      stock: stock,
      items: items,
      // **The clock this service already holds**, so `judge`'s requirement adds nothing to this
      // method's signature. `cook` is called from a controller with no notion of dates, and threading
      // one through would have put a date parameter on a screen's button handler.
      //
      // No batches are supplied, so this verdict is the coarse one and cannot see expiry. It does not
      // need to: the precise question is answered by `consume`, atomically, against the shelf as it is
      // at the moment of writing rather than as it was when the screen last rebuilt. A verdict here
      // that disagreed with that would be the more dangerous of the two.
      today: today,
      servings: target,
    );

    if (!allowPartial && verdict.missingCount > 0) {
      final blocked = verdict.checks
          .where((c) => !c.ingredient.isOptional && c.availability.isMissing)
          .map((c) => c.ingredient.freeText ?? c.ingredient.itemId ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
      return Result.failure(
        BusinessRuleFailure(
          blocked.isEmpty
              ? 'There is not enough stock for this recipe.'
              : 'Not enough stock for ${blocked.length} ingredient(s).',
          rule: 'recipeInsufficientStock',
        ),
      );
    }

    final deducted = <String>[];
    final skipped = <IngredientCheck>[];

    if (deductStock) {
      // Built once rather than per ingredient: every line of one cook must be judged against the same
      // date, or a cook running across midnight would treat two ingredients by different rules.
      final policy = DrawPolicy.freshFirst(
        today: today,
        allowExpired: allowExpired,
      );

      for (final check in verdict.checks) {
        final itemId = check.ingredient.itemId;
        final needed = check.required_;
        // Anything the engine could not judge, and anything with no quantity, is passed over. The
        // engine already decided which those are; re-deciding here would be a second opinion that
        // could disagree with the badge the user just looked at.
        if (itemId == null ||
            needed == null ||
            check.availability.isUncheckable) {
          skipped.add(check);
          continue;
        }
        if (!needed.isPositive) {
          skipped.add(check);
          continue;
        }

        final result = await _stock.consume(
          itemId: itemId,
          quantity: needed,
          // `consume` is "stock used up through normal use" — the same kind the inventory module's
          // own "use some" writes. Cooking is not waste and not an adjustment, and that holds even
          // when a batch used was past its date: the user ate it.
          kind: StockMovementKind.consume,
          policy: policy,
          reason: 'recipe',
          note: recipe.name,
        );
        if (result.isFailure) {
          // Partial application is the one outcome worth refusing outright: some movements are
          // already written, and the caller needs to know the ledger is now ahead of the UI.
          //
          // Under `allowExpired: false` this is also how "you have the food but it is off" arrives —
          // an `insufficientStock` naming the good stock alone. The screen should have asked before
          // getting here; if it did not, refusing is the safe half of the mistake.
          return Result.failure(
            result.failureOrNull ??
                const UnexpectedFailure(
                  'Stock could not be deducted for this recipe.',
                ),
          );
        }
        deducted.add(itemId);
      }
    } else {
      skipped.addAll(verdict.checks);
    }

    final logged = await _recipes.logCook(
      recipeId: recipe.id,
      cookedOn: today,
      servingsCooked: target,
      deductedStock: deductStock && deducted.isNotEmpty,
      note: note,
    );
    final cook = logged.valueOrNull;
    if (cook == null) {
      return Result.failure(
        logged.failureOrNull ??
            const UnexpectedFailure('That cook could not be recorded.'),
      );
    }

    return Result.ok(
      CookOutcome(cook: cook, deducted: deducted, skipped: skipped),
    );
  }
}
