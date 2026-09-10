import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/recipe.dart';
import 'package:alaya/domain/services/cookability_engine.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';

import '../../support/recipe_harness.dart';

/// The engine, from literals. No database, no widget — the whole point of it being pure.
void main() {
  Map<String, Item> items(List<String> ids) => {
    for (final id in ids) id: weightItem(id, id),
  };

  /// The date every verdict below is judged against.
  ///
  /// **Explicit rather than a clock read.** `judge` requires it so a date-sensitive verdict is
  /// reproducible — the same rule `ConsumableBatch.isExpired` and the views follow. Most tests here
  /// supply no batches, so expiry is not consulted and the value is arbitrary; the ones that do supply
  /// batches pick their expiry dates relative to this.
  const today = DateKey(20260814);

  /// A weight batch of [grams], expiring on [expiry] or never.
  ///
  /// Built directly rather than from a `Batch` entity: `ConsumableBatch` is the four-field projection
  /// `InventoryConsumptionService` takes, and a test that constructed twelve fields to use four would
  /// break on every unrelated change to a batch.
  ConsumableBatch batch(
    String id,
    int grams, {
    int? expiry,
    int purchased = 20260701,
  }) => ConsumableBatch(
    batchId: id,
    remaining: Qty(grams * 1000, UnitCategory.weight),
    purchasedDateKey: DateKey(purchased),
    expiryDateKey: expiry == null ? null : DateKey(expiry),
  );

  group('serving scale', () {
    test('rounds up, because rounding down would claim you have enough', () {
      // 200g for 4 servings, scaled to 3, is 150g exactly.
      expect(
        CookabilityEngine.scaleMilli(200000, fromServings: 4, toServings: 3),
        150000,
      );
      // 100g for 3 servings, scaled to 2, is 66.666…g. Down would be 66666, and an engine that said
      // "ready" with 66666 on hand would be wrong.
      expect(
        CookabilityEngine.scaleMilli(100000, fromServings: 3, toServings: 2),
        66667,
      );
    });

    test('is exact when the servings match', () {
      expect(
        CookabilityEngine.scaleMilli(12345, fromServings: 4, toServings: 4),
        12345,
      );
    });

    test('refuses a zero base, which would divide by nothing', () {
      expect(
        () =>
            CookabilityEngine.scaleMilli(1000, fromServings: 0, toServings: 1),
        throwsArgumentError,
      );
    });
  });

  group('the availabilities', () {
    test('enough on hand is sufficient', () {
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('flour', 200)]),
        stock: {'flour': stockOf('flour', 500)},
        items: items(['flour']),
        today: today,
      );
      expect(
        verdict.checks.single.availability,
        IngredientAvailability.sufficient,
      );
      expect(verdict.status, CookabilityStatus.ready);
    });

    test(
      'some but not enough is short, with a shortfall a shopping list could use',
      () {
        final verdict = kEngine.judge(
          recipeOf(ingredients: [linked('flour', 200)]),
          stock: {'flour': stockOf('flour', 150)},
          items: items(['flour']),
          today: today,
        );
        final check = verdict.checks.single;
        expect(check.availability, IngredientAvailability.short);
        expect(check.shortfall, Qty(50 * 1000, UnitCategory.weight));
        expect(verdict.status, CookabilityStatus.short);
      },
    );

    test('none at all is blocked, not merely short', () {
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('flour', 200)]),
        stock: {'flour': stockOf('flour', 0)},
        items: items(['flour']),
        today: today,
      );
      expect(
        verdict.checks.single.availability,
        IngredientAvailability.outOfStock,
      );
      expect(verdict.status, CookabilityStatus.blocked);
    });

    test('a unit that cannot be compared is unanswerable, NOT zero', () {
      // The recipe asks for 200g; the item is counted in pieces. No factor relates them, so the
      // engine must decline rather than report a shortfall it cannot compute.
      final counted = Item(
        id: 'eggs',
        name: 'Eggs',
        normalizedName: 'eggs',
        unitCategory: UnitCategory.count,
        defaultDisplayUnitCode: 'pc',
        isFavorite: false,
      );
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('eggs', 200)]),
        stock: {
          'eggs': ItemStock(
            itemId: 'eggs',
            totalRemaining: const Qty(6000, UnitCategory.count),
            batchCount: 1,
            isLowStock: false,
          ),
        },
        items: {'eggs': counted},
        today: today,
      );
      expect(
        verdict.checks.single.availability,
        IngredientAvailability.unitMismatch,
      );
      expect(verdict.status, CookabilityStatus.uncheckable);
      expect(verdict.missingCount, 0, reason: 'unanswerable is not missing');
    });

    test('an ingredient nothing tracks is untracked', () {
      final verdict = kEngine.judge(
        recipeOf(ingredients: [untracked('salt')]),
        stock: const {},
        items: const {},
        today: today,
      );
      expect(
        verdict.checks.single.availability,
        IngredientAvailability.untracked,
      );
      expect(verdict.status, CookabilityStatus.uncheckable);
    });

    test('a linked item that no longer exists is untracked, not missing', () {
      // The item was deleted. Inventing a verdict about a row that is gone would be a guess.
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('ghost', 200)]),
        stock: const {},
        items: const {},
        today: today,
      );
      expect(
        verdict.checks.single.availability,
        IngredientAvailability.untracked,
      );
    });
  });

  group('the verdict combines its parts', () {
    test('missing and uncheckable are counted apart', () {
      final verdict = kEngine.judge(
        recipeOf(
          ingredients: [
            linked('flour', 200, sortOrder: 0),
            untracked('salt', sortOrder: 1),
          ],
        ),
        stock: {'flour': stockOf('flour', 150)},
        items: items(['flour']),
        today: today,
      );
      expect(verdict.missingCount, 1);
      expect(verdict.uncheckableCount, 1);
      // Short wins the headline: something is definitely missing, which is more actionable than
      // something being unknown.
      expect(verdict.status, CookabilityStatus.short);
    });

    test('an optional ingredient never blocks the verdict', () {
      final verdict = kEngine.judge(
        recipeOf(
          ingredients: [
            linked('flour', 200, sortOrder: 0),
            linked('coriander', 10, sortOrder: 1, optional: true),
          ],
        ),
        stock: {
          'flour': stockOf('flour', 500),
          'coriander': stockOf('coriander', 0),
        },
        items: items(['flour', 'coriander']),
        today: today,
      );
      expect(verdict.status, CookabilityStatus.ready);
      expect(verdict.missingCount, 0);
      expect(verdict.optionalMissingCount, 1, reason: 'still worth saying');
    });

    test('a recipe with no required ingredients is empty, not ready', () {
      final verdict = kEngine.judge(
        recipeOf(),
        stock: const {},
        items: const {},
        today: today,
      );
      expect(verdict.status, CookabilityStatus.empty);
    });

    test('scaling servings can turn ready into short', () {
      final recipe = recipeOf(servings: 2, ingredients: [linked('flour', 200)]);
      final stock = {'flour': stockOf('flour', 250)};
      expect(
        kEngine
            .judge(
              recipe,
              stock: stock,
              items: items(['flour']),
              today: today,
            )
            .status,
        CookabilityStatus.ready,
      );
      // Doubled, the recipe needs 400g and only 250g is on hand.
      expect(
        kEngine
            .judge(
              recipe,
              stock: stock,
              items: items(['flour']),
              today: today,
              servings: 4,
            )
            .status,
        CookabilityStatus.short,
      );
    });
  });

  group('bridging one measure to another', () {
    test('millilitres convert to grams when the item states a density', () {
      // Oil is 0.92 g/ml, so 920 milli-grams per ml. 50 ml is 46 g, and 100 g on hand covers it.
      final verdict = kEngine.judge(
        recipeOf(ingredients: [inVolume('oil', 50)]),
        stock: {'oil': stockOf('oil', 100)},
        items: {'oil': weightItem('oil', 'Oil', densityMilliGramsPerMl: 920)},
        today: today,
      );
      final check = verdict.checks.single;
      expect(check.availability, IngredientAvailability.sufficient);
      expect(
        check.required_,
        Qty(46 * 1000, UnitCategory.weight),
        reason: '50 ml x 0.92 g/ml = 46 g',
      );
      expect(verdict.status, CookabilityStatus.ready);
    });

    test('a converted amount can still fall short, and reports it in grams', () {
      // 200 ml of oil is 184 g; only 100 g is on hand, so the shortfall is 84 g.
      final verdict = kEngine.judge(
        recipeOf(ingredients: [inVolume('oil', 200)]),
        stock: {'oil': stockOf('oil', 100)},
        items: {'oil': weightItem('oil', 'Oil', densityMilliGramsPerMl: 920)},
        today: today,
      );
      final check = verdict.checks.single;
      expect(check.availability, IngredientAvailability.short);
      expect(check.shortfall, Qty(84 * 1000, UnitCategory.weight));
    });

    test('without a density it stays unanswerable, NOT missing', () {
      // The whole design in one assertion: no density means the engine declines rather than
      // reporting a shortfall it cannot compute. A `short` here would be a confident falsehood.
      final verdict = kEngine.judge(
        recipeOf(ingredients: [inVolume('oil', 50)]),
        stock: {'oil': stockOf('oil', 100)},
        items: {'oil': weightItem('oil', 'Oil')},
        today: today,
      );
      expect(
        verdict.checks.single.availability,
        IngredientAvailability.unitMismatch,
      );
      expect(verdict.status, CookabilityStatus.uncheckable);
      expect(verdict.missingCount, 0);
    });

    test('pieces convert to grams when the item states a piece weight', () {
      // An onion is 110 g. Two of them is 220 g, and 500 g on hand covers it.
      final verdict = kEngine.judge(
        recipeOf(ingredients: [inPieces('onion', 2)]),
        stock: {'onion': stockOf('onion', 500)},
        items: {
          'onion': weightItem('onion', 'Onion', milliGramsPerPiece: 110 * 1000),
        },
        today: today,
      );
      expect(
        verdict.checks.single.required_,
        Qty(220 * 1000, UnitCategory.weight),
      );
      expect(verdict.status, CookabilityStatus.ready);
    });

    test('a density does not answer a question asked in pieces', () {
      // The two bridges are independent: knowing what a millilitre weighs says nothing about what
      // one onion weighs, and the engine must not borrow one for the other.
      final verdict = kEngine.judge(
        recipeOf(ingredients: [inPieces('onion', 2)]),
        stock: {'onion': stockOf('onion', 500)},
        items: {
          'onion': weightItem('onion', 'Onion', densityMilliGramsPerMl: 920),
        },
        today: today,
      );
      expect(
        verdict.checks.single.availability,
        IngredientAvailability.unitMismatch,
      );
    });

    test('serving scale applies after the conversion, not before', () {
      // 50 ml at 2 servings, doubled, is 100 ml -> 92 g. Converting first then scaling and scaling
      // first then converting agree here only because both are linear; asserting it pins the order
      // so a future non-linear bridge cannot silently change the answer.
      final verdict = kEngine.judge(
        recipeOf(servings: 2, ingredients: [inVolume('oil', 50)]),
        stock: {'oil': stockOf('oil', 100)},
        items: {'oil': weightItem('oil', 'Oil', densityMilliGramsPerMl: 920)},
        today: today,
        servings: 4,
      );
      expect(
        verdict.checks.single.required_,
        Qty(92 * 1000, UnitCategory.weight),
      );
    });
  });

  group('expiry', () {
    test('reports the soonest expiry among the items it would use', () {
      final verdict = kEngine.judge(
        recipeOf(
          ingredients: [
            linked('flour', 100, sortOrder: 0),
            linked('milk', 100, sortOrder: 1),
          ],
        ),
        stock: {
          'flour': stockOf('flour', 500, expiry: const DateKey(20261201)),
          'milk': stockOf('milk', 500, expiry: const DateKey(20260815)),
        },
        items: items(['flour', 'milk']),
        today: today,
      );
      expect(verdict.soonestExpiryUsed, const DateKey(20260815));
    });

    test('is null when nothing it uses expires', () {
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('flour', 100)]),
        stock: {'flour': stockOf('flour', 500)},
        items: items(['flour']),
        today: today,
      );
      expect(verdict.soonestExpiryUsed, isNull);
    });
  });

  group('expiry, with batches — the precise path', () {
    /// 100 g still good, 200 g past its date. `stockOf` carries the total, because `v_item_stock`
    /// sums every batch holding stock with no expiry filter — which is the whole reason a total
    /// alone could not answer this.
    Map<String, List<ConsumableBatch>> mixed() => {
      'flour': [
        batch('good', 100, expiry: 20260901, purchased: 20260801),
        batch('gone', 200, expiry: 20260810),
      ],
    };

    test('needing expired stock is not missing, and does not block cooking', () {
      // **The reported bug, as a verdict.** 200 g needed, 100 g good, 200 g past its date. The recipe
      // is cookable — but only with permission, which is a different answer from both "ready" and
      // "you are short".
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('flour', 200)]),
        stock: {'flour': stockOf('flour', 300)},
        items: items(['flour']),
        today: today,
        batchesByItem: mixed(),
      );

      expect(
        verdict.checks.single.availability,
        IngredientAvailability.needsExpired,
      );
      expect(verdict.status, CookabilityStatus.readyWithExpired);
      expect(verdict.expiredCount, 1);
      expect(
        verdict.missingCount,
        0,
        reason: 'nothing needs buying — the food is in the cupboard',
      );
      expect(verdict.isCookable, isTrue);
      expect(verdict.isReady, isFalse);
    });

    test('the plan it carries is the one that would actually run', () {
      // Replanned with permission, so a confirmation sheet and the deduction read the same object.
      // The fresh-only attempt *failed*, so there is no plan on it to hand over — which is why the
      // service refusing rather than returning a partial plan is the better contract.
      final plan = kEngine
          .judge(
            recipeOf(ingredients: [linked('flour', 200)]),
            stock: {'flour': stockOf('flour', 300)},
            items: items(['flour']),
            today: today,
            batchesByItem: mixed(),
          )
          .checks
          .single
          .plan;

      expect(plan, isNotNull);
      expect(plan!.usesExpired, isTrue);
      // Good stock exhausted first, expired only topping it up.
      expect(
        plan.draws.map((draw) => draw.batchId),
        orderedEquals(['good', 'gone']),
      );
      expect(plan.fromExpired, Qty(100 * 1000, UnitCategory.weight));
      // Counts what the permitted policy could reach, which is everything on the shelf.
      expect(plan.totalAvailable, Qty(300 * 1000, UnitCategory.weight));
    });

    test('good stock alone is enough, so nothing is flagged', () {
      // There is expired stock and the plan never reaches it. Prompting here would be a warning
      // about nothing.
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('flour', 100)]),
        stock: {'flour': stockOf('flour', 300)},
        items: items(['flour']),
        today: today,
        batchesByItem: mixed(),
      );

      final check = verdict.checks.single;
      expect(check.availability, IngredientAvailability.sufficient);
      expect(verdict.status, CookabilityStatus.ready);
      expect(verdict.expiredCount, 0);
      expect(check.plan?.usesExpired, isFalse);
      // The fresh-only policy counts only good stock, so the total it quotes is 100 g not 300 g.
      expect(check.plan?.totalAvailable, Qty(100 * 1000, UnitCategory.weight));
    });

    test('not enough even counting expired stock is short, not needsExpired', () {
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('flour', 500)]),
        stock: {'flour': stockOf('flour', 300)},
        items: items(['flour']),
        today: today,
        batchesByItem: mixed(),
      );

      final check = verdict.checks.single;
      expect(check.availability, IngredientAvailability.short);
      expect(verdict.status, CookabilityStatus.short);
      // The gap after everything usable, expired included — what a shopping list needs.
      expect(check.shortfall, Qty(200 * 1000, UnitCategory.weight));
      expect(
        check.plan,
        isNull,
        reason: 'no plan exists when none can be applied',
      );
    });

    test('a cupboard holding only expired stock is not empty', () {
      // `outOfStock` means nothing usable at all. Something past its date is still something.
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('flour', 500)]),
        stock: {'flour': stockOf('flour', 200)},
        items: items(['flour']),
        today: today,
        batchesByItem: {
          'flour': [batch('gone', 200, expiry: 20260810)],
        },
      );

      final check = verdict.checks.single;
      expect(check.availability, IngredientAvailability.short);
      expect(verdict.status, CookabilityStatus.short);
      expect(check.shortfall, Qty(300 * 1000, UnitCategory.weight));
    });

    test('an empty shelf is out of stock', () {
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('flour', 100)]),
        stock: {'flour': stockOf('flour', 0)},
        items: items(['flour']),
        today: today,
        batchesByItem: const {'flour': []},
      );

      expect(
        verdict.checks.single.availability,
        IngredientAvailability.outOfStock,
      );
      expect(verdict.status, CookabilityStatus.blocked);
    });

    test('a batch expiring today is still good today', () {
      // Confirms `ConsumableBatch.isExpired`, which is strict: `expiry < today`. Use-by 14 Aug is
      // usable on 14 Aug, matching what the calendar module already assumes.
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('flour', 100)]),
        stock: {'flour': stockOf('flour', 100)},
        items: items(['flour']),
        today: today,
        batchesByItem: {
          'flour': [batch('edge', 100, expiry: 20260814)],
        },
      );

      expect(
        verdict.checks.single.availability,
        IngredientAvailability.sufficient,
      );
    });

    test(
      'batches in a category the requirement was never bridged into are declined',
      () {
        // The consumption service refuses this as a validation error rather than a shortfall, and the
        // engine passes that through as its own "I cannot compare" state. Reporting `short` would be a
        // confident falsehood about stock it never looked at.
        final verdict = kEngine.judge(
          recipeOf(ingredients: [linked('flour', 100)]),
          stock: {'flour': stockOf('flour', 500)},
          items: items(['flour']),
          today: today,
          batchesByItem: {
            'flour': [
              ConsumableBatch(
                batchId: 'wrong',
                remaining: const Qty(500000, UnitCategory.volume),
                purchasedDateKey: const DateKey(20260701),
              ),
            ],
          },
        );

        expect(
          verdict.checks.single.availability,
          IngredientAvailability.unitMismatch,
        );
      },
    );

    test(
      'the same stock without batches reports sufficient — the documented trade',
      () {
        // **Pins the approximation `judge` documents.** Omitting batches keeps the previous behaviour,
        // which is what a list of forty recipes wants and which cannot see expiry. The detail screen
        // supplies batches; the list does not. This assertion is here so nobody "fixes" the coarse path
        // without noticing it was deliberate.
        final verdict = kEngine.judge(
          recipeOf(ingredients: [linked('flour', 200)]),
          stock: {'flour': stockOf('flour', 300)},
          items: items(['flour']),
          today: today,
        );

        expect(
          verdict.checks.single.availability,
          IngredientAvailability.sufficient,
        );
        expect(verdict.checks.single.plan, isNull, reason: 'not computed');
      },
    );
  });
}
