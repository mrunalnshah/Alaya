import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/services/draw_policy.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';
import 'package:alaya/domain/services/recipe_cook_service.dart';

import '../support/cook_fakes.dart';
import '../support/recipe_harness.dart';

/// Cooking, and what it takes off the shelf.
///
/// **The first test `RecipeCookService` has ever had.** It appeared in no test file: the deduction path a
/// user reported as broken had never been exercised, so every round of this feature until now was verifying
/// the verdict and the sheet while the thing between them went unchecked.
void main() {
  const today = DateKey(20260814);
  final clock = FixedClock(DateTime.utc(2026, 8, 14, 9));

  Qty grams(int g) => Qty(g * 1000, UnitCategory.weight);

  ConsumableBatch batch(
    String id,
    int g, {
    int? expiry,
    int purchased = 20260701,
  }) => ConsumableBatch(
    batchId: id,
    remaining: grams(g),
    purchasedDateKey: DateKey(purchased),
    expiryDateKey: expiry == null ? null : DateKey(expiry),
  );

  /// 150 g good, 100 g past its date.
  List<ConsumableBatch> shelf() => [
    batch('good', 150, expiry: 20260901, purchased: 20260801),
    batch('gone', 100, expiry: 20260810),
  ];

  /// The rollup the engine reads. Includes expired stock, because `v_item_stock` does.
  Map<String, ItemStock> rollup(int totalGrams) => {
    'flour': stockOf('flour', totalGrams, expiry: const DateKey(20260810)),
  };

  Map<String, Item> catalogue() => {'flour': weightItem('flour', 'Flour')};

  ({RecipeCookService service, FakeStock stock, FakeRecipes recipes}) build({
    Map<String, List<ConsumableBatch>>? batches,
    bool logFails = false,
  }) {
    final stock = FakeStock(batches: batches ?? {'flour': shelf()});
    final recipes = FakeRecipes(logFails: logFails);
    return (
      service: RecipeCookService(
        recipes: recipes,
        stock: stock,
        clock: clock,
      ),
      stock: stock,
      recipes: recipes,
    );
  }

  group('the policy it sends', () {
    test('freshFirst, never the FEFO default', () async {
      // **The whole fix, in one assertion.** `consume` defaults to FEFO, which orders by nearest expiry —
      // and an expired date is the nearest date, so the default eats food that is already off first. A
      // service that forgot to pass a policy would still cook, still deduct, and still pass every test
      // that only looked at the draws.
      final t = build();
      await t.service.cook(
        recipe: recipeOf(ingredients: [linked('flour', 100)]),
        stock: rollup(250),
        items: catalogue(),
      );

      expect(t.stock.consumed, hasLength(1));
      final policy = t.stock.consumed.single.policy;
      expect(policy.isExpiryAware, isTrue);
      expect(policy.today, today);
      expect(policy.allowExpired, isFalse);
    });

    test('carries the consent it was given', () async {
      final t = build();
      await t.service.cook(
        recipe: recipeOf(ingredients: [linked('flour', 200)]),
        stock: rollup(250),
        items: catalogue(),
        allowExpired: true,
      );

      expect(t.stock.consumed.single.policy.allowExpired, isTrue);
    });

    test('records the movement as consume, not expired', () async {
      // The user ate it. `StockMovementKind.expired` is a write-off, and using it here would put food
      // somebody cooked with into the waste analytics.
      final t = build();
      await t.service.cook(
        recipe: recipeOf(ingredients: [linked('flour', 200)]),
        stock: rollup(250),
        items: catalogue(),
        allowExpired: true,
      );

      expect(t.stock.consumed.single.kind, StockMovementKind.consume);
    });
  });

  group('without consent', () {
    test(
      'good stock alone is spent, and the expired batch is untouched',
      () async {
        final t = build();
        final result = await t.service.cook(
          recipe: recipeOf(ingredients: [linked('flour', 100)]),
          stock: rollup(250),
          items: catalogue(),
        );

        expect(result.isOk, isTrue);
        expect(
          t.stock.consumed.single.draws.map((d) => d.batchId),
          orderedEquals(['good']),
        );
        // 250 on the shelf, 100 taken, and none of it from `gone`.
        expect(t.stock.remainingOf('flour', UnitCategory.weight), grams(150));
      },
    );

    test(
      'a cook that would need expired stock is refused, writing nothing',
      () async {
        // **The reported bug.** 200 g needed, 150 g good, 100 g past its date. This used to succeed by
        // eating the expired batch first and saying nothing.
        final t = build();
        final result = await t.service.cook(
          recipe: recipeOf(ingredients: [linked('flour', 200)]),
          stock: rollup(250),
          items: catalogue(),
        );

        expect(result.isFailure, isTrue);
        expect(
          (result.failureOrNull as BusinessRuleFailure?)?.rule,
          'insufficientStock',
        );
        expect(t.stock.consumed, isEmpty);
        // Nothing was logged either: a cook that did not happen is not a cook.
        expect(t.recipes.logged, isEmpty);
        expect(t.stock.remainingOf('flour', UnitCategory.weight), grams(250));
      },
    );

    test('a shelf holding only expired stock is refused too', () async {
      final t = build(
        batches: {
          'flour': [batch('gone', 300, expiry: 20260810)],
        },
      );
      final result = await t.service.cook(
        recipe: recipeOf(ingredients: [linked('flour', 200)]),
        stock: rollup(300),
        items: catalogue(),
      );

      expect(result.isFailure, isTrue);
      expect(t.stock.consumed, isEmpty);
    });
  });

  group('with consent', () {
    test('good stock is still spent first, expired only topping up', () async {
      // Consent is permission to reach the expired batch, not permission to start with it.
      final t = build();
      final result = await t.service.cook(
        recipe: recipeOf(ingredients: [linked('flour', 200)]),
        stock: rollup(250),
        items: catalogue(),
        allowExpired: true,
      );

      expect(result.isOk, isTrue);
      final draws = t.stock.consumed.single.draws;
      expect(draws.map((d) => d.batchId), orderedEquals(['good', 'gone']));
      expect(draws.first.quantity, grams(150));
      expect(draws.last.quantity, grams(50));
      expect(t.stock.remainingOf('flour', UnitCategory.weight), grams(50));
    });

    test('an expired-only shelf is drawn from, and logged', () async {
      final t = build(
        batches: {
          'flour': [batch('gone', 300, expiry: 20260810)],
        },
      );
      final result = await t.service.cook(
        recipe: recipeOf(ingredients: [linked('flour', 200)]),
        stock: rollup(300),
        items: catalogue(),
        allowExpired: true,
      );

      expect(result.isOk, isTrue);
      expect(t.stock.consumed.single.draws.single.batchId, 'gone');
      expect(t.recipes.logged.single.deductedStock, isTrue);
    });
  });

  group('what it declines to deduct', () {
    test('an untracked ingredient is skipped, not failed', () async {
      // Nobody tracks salt, and refusing to cook because of it would make the feature unusable.
      final t = build();
      final result = await t.service.cook(
        recipe: recipeOf(
          ingredients: [
            linked('flour', 100, sortOrder: 0),
            untracked('salt', sortOrder: 1),
          ],
        ),
        stock: rollup(250),
        items: catalogue(),
      );

      expect(result.isOk, isTrue);
      final outcome = result.valueOrNull;
      expect(outcome!.deducted, orderedEquals(['flour']));
      expect(outcome.skipped, hasLength(1));
      expect(outcome.skipped.single.ingredient.freeText, 'salt');
    });

    test('deductStock false writes nothing but still logs the cook', () async {
      // "I cooked this but I am not tracking it" is a real thing to want, and the log is what makes the
      // cook history honest about which entries touched stock.
      final t = build();
      final result = await t.service.cook(
        recipe: recipeOf(ingredients: [linked('flour', 100)]),
        stock: rollup(250),
        items: catalogue(),
        deductStock: false,
      );

      expect(result.isOk, isTrue);
      expect(t.stock.consumed, isEmpty);
      expect(t.recipes.logged.single.deductedStock, isFalse);
      expect(result.valueOrNull!.skipped, hasLength(1));
    });

    test('a short ingredient refuses before touching anything', () async {
      final t = build();
      final result = await t.service.cook(
        recipe: recipeOf(ingredients: [linked('flour', 900)]),
        stock: rollup(250),
        items: catalogue(),
        allowExpired: true,
      );

      expect(
        (result.failureOrNull as BusinessRuleFailure?)?.rule,
        'recipeInsufficientStock',
      );
      expect(t.stock.consumed, isEmpty);
    });
  });

  group('the log', () {
    test('is stamped with the service own clock', () async {
      // **50 g, not 100 g, and the difference is the whole point of the test.** At 100 g a recipe for two
      // cooked for four needs 200 g, which exceeds the 150 g of good stock — so the cook is refused and
      // nothing is logged. This test is about the date and the serving count, so its fixture must not also
      // be exercising the expiry refusal; 50 g doubles to 100 g and stays inside the good stock.
      //
      // I wrote it at 100 g after verifying the arithmetic for the expiry cases and not for this one.
      final t = build();
      await t.service.cook(
        recipe: recipeOf(servings: 2, ingredients: [linked('flour', 50)]),
        stock: rollup(250),
        items: catalogue(),
        servings: 4,
      );

      final cook = t.recipes.logged.single;
      expect(cook.cookedOn, today);
      expect(cook.servingsCooked, 4);
    });

    test('a failed log fails the cook, even though stock already moved', () async {
      // **Reported rather than swallowed.** The movements are written and the log is not, so the ledger
      // is ahead of the history — the caller has to know, because nothing else can tell them.
      final t = build(logFails: true);
      final result = await t.service.cook(
        recipe: recipeOf(ingredients: [linked('flour', 100)]),
        stock: rollup(250),
        items: catalogue(),
      );

      expect(result.isFailure, isTrue);
      expect(
        t.stock.consumed,
        hasLength(1),
        reason: 'the deduction did happen',
      );
    });
  });
}
