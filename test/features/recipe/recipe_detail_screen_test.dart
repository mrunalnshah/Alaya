import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/fraction.dart';
import 'package:alaya/core/quantity/measure.dart';
import 'package:alaya/features/recipe/presentation/screens/recipe_detail_screen.dart';

import '../../support/recipe_harness.dart';

/// The recipe detail screen — **the first widget test it has ever had.**
///
/// That absence is why this bug lasted. `RecipeDetailScreen` appeared in no test file, and it could not
/// have: `recipeProvider` resolves `recipeRepositoryProvider`, which needs a database, and
/// `recipeOverrides` did not cover it. So the screen a cook actually reads while cooking was never
/// pumped, and it rendered `7 ml` for a line that said half a tablespoon — the unit stored, and thrown
/// away at render time — through every green run of the suite.
///
/// The assertions below are the ones whose absence allowed that.
void main() {
  /// Flour, weighed, with a stated tablespoon weight so the engine can judge a spoon against stock.
  ///
  /// 8 g per tablespoon is what a cooking table says, and `densityMilliGramsPerMl` is that figure
  /// divided across a tablespoon's 14.787 ml — the item editor asks the question the human way round and
  /// stores it this way.
  final flour = weightItem('flour', 'Flour', densityMilliGramsPerMl: 541);

  group('a vessel line is shown in its vessel', () {
    testWidgets('half a tablespoon reads as a half tablespoon, not 7 ml', (
      tester,
    ) async {
      // **The regression this whole change exists for.** 1/2 tbsp stores as `Qty(7394, volume)`; the row
      // used to render that canonical figure and the cook read `7 ml`.
      await pumpRecipe(
        tester,
        const RecipeDetailScreen(recipeId: 'r1'),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(
              ingredients: [inVessel('flour', Measure.of(0, Fraction(1, 2)))],
            ),
          ],
          stock: {'flour': stockOf('flour', 500)},
          items: {'flour': flour},
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.text('1/2 tbsp'), findsOneWidget);
      // The old rendering, asserted absent by name. Without this the test would pass if the row showed
      // both figures, which is not the fix — it is clutter with the bug still in it.
      expect(find.textContaining('ml'), findsNothing);
    });

    testWidgets('a whole number of cups carries no fraction', (tester) async {
      await pumpRecipe(
        tester,
        const RecipeDetailScreen(recipeId: 'r1'),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(
              ingredients: [
                inVessel('flour', const Measure(2000), code: 'cup'),
              ],
            ),
          ],
          stock: {'flour': stockOf('flour', 5000)},
          items: {'flour': flour},
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.text('2 cup'), findsOneWidget);
    });

    testWidgets('a line the engine cannot judge still says what to measure', (
      tester,
    ) async {
      // **An item with no stated tablespoon weight.** The engine reports `unitMismatch` and `required_`
      // is null, so the old row rendered nothing at all — the cook was told a spoonful of something with
      // no indication of how much. The amount comes from what they wrote, which is always available.
      await pumpRecipe(
        tester,
        const RecipeDetailScreen(recipeId: 'r1'),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(
              ingredients: [inVessel('salt', Measure.of(1, Fraction(1, 4)))],
            ),
          ],
          stock: {'salt': stockOf('salt', 200)},
          items: {'salt': weightItem('salt', 'Salt')},
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.text('1 1/4 tbsp'), findsOneWidget);
    });
  });

  group('everything else keeps QtyText', () {
    testWidgets('a weight line is unchanged', (tester) async {
      // The narrowing, asserted. Only tsp, tbsp and cup take the new path; grams keep the decomposition
      // every other screen in the app uses, and `200 g` is not `200 g` by accident.
      await pumpRecipe(
        tester,
        const RecipeDetailScreen(recipeId: 'r1'),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(ingredients: [linked('flour', 200)]),
          ],
          stock: {'flour': stockOf('flour', 500)},
          items: {'flour': flour},
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('200'), findsWidgets);
      expect(find.textContaining('tbsp'), findsNothing);
    });
  });

  group('scaling, and the glyph that admits it', () {
    testWidgets('an amount no drawer can hold snaps, and says so', (
      tester,
    ) async {
      // Half a cup written for 3 servings, read at 2: 500 x 2 / 3, rounded up, is 334 thousandths.
      // That is not any simple fraction — exact style would render `0.334` — so kitchen style snaps it
      // to the third of a cup that is 1 thousandth away and marks it. This one assertion is the whole
      // design: a derived number, rendered as something measurable, and not passed off as exact.
      await pumpRecipe(
        tester,
        const RecipeDetailScreen(recipeId: 'r1'),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(
              servings: 3,
              ingredients: [
                inVessel('flour', const Measure(500), code: 'cup'),
              ],
            ),
          ],
          stock: {'flour': stockOf('flour', 5000)},
          items: {'flour': flour},
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      // Down from 3 servings to 2.
      await tester.tap(find.byTooltip('Fewer servings'));
      await tester.pumpAndSettle();

      expect(find.text('\u2248 1/3 cup'), findsOneWidget);
      // And the legend appears with it, because a mark nobody can interpret is worse than no mark.
      expect(find.textContaining('rounded to the nearest'), findsOneWidget);
    });

    testWidgets('an amount that divides cleanly is not marked', (tester) async {
      // A third of a cup written for 4 servings, read at 3, is exactly a quarter cup. Nothing was
      // approximated, so nothing claims to have been — no glyph, and the legend is the only thing on
      // screen admitting the numbers moved at all.
      await pumpRecipe(
        tester,
        const RecipeDetailScreen(recipeId: 'r1'),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(
              servings: 4,
              ingredients: [
                inVessel('flour', Measure.of(0, Fraction(1, 3)), code: 'cup'),
              ],
            ),
          ],
          stock: {'flour': stockOf('flour', 5000)},
          items: {'flour': flour},
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Fewer servings'));
      await tester.pumpAndSettle();

      expect(find.text('1/4 cup'), findsOneWidget);
      // **Scoped to the amount, not the screen.** The legend under the servings dial contains `≈` by
      // design — it is the sentence explaining the mark — so a screen-wide search for the glyph can
      // never come back empty once the dial has moved. What must be absent is the *marked* rendering of
      // this row, which is a different claim and the one worth making.
      //
      // I asserted the screen-wide version first and it failed on its own legend. Worth the comment:
      // the broad finder reads as the stronger assertion and is the one that cannot hold.
      expect(find.text('\u2248 1/4 cup'), findsNothing);
    });

    testWidgets('at the recipe own serving count nothing is marked at all', (
      tester,
    ) async {
      // The condition that must never produce a glyph: an untouched dial. The amount is what the cook
      // typed, and snapping a value they chose deliberately would be the screen overruling them.
      await pumpRecipe(
        tester,
        const RecipeDetailScreen(recipeId: 'r1'),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(
              servings: 3,
              ingredients: [
                inVessel('flour', const Measure(334), code: 'cup'),
              ],
            ),
          ],
          stock: {'flour': stockOf('flour', 5000)},
          items: {'flour': flour},
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      // 334 thousandths of a cup has no simple fraction, so exact style renders the decimal rather than
      // pretending. Honest, and unmarked, because nothing was rounded.
      expect(find.text('0.334 cup'), findsOneWidget);
      expect(find.textContaining('\u2248'), findsNothing);
      expect(find.textContaining('rounded to the nearest'), findsNothing);
    });
  });
}
