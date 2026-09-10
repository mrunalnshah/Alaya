import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/recipe/presentation/screens/recipe_list_screen.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';

import '../../support/recipe_harness.dart';

/// The catalogue's four states, and the badge that has to tell the truth (ARCH_5 §9.1).
void main() {
  group('four states', () {
    testWidgets('loading is a skeleton', (tester) async {
      // A `Stream.value` resolves in the first frame's microtask drain, so the loading branch would
      // be gone before the assertion. The harness holds the stream open instead.
      await pumpRecipe(
        tester,
        const RecipeListScreen(),
        overrides: recipeOverrides(loading: true),
      );
      expect(find.byType(AlayaListSkeleton), findsOneWidget);
    });

    testWidgets('empty invites the first recipe', (tester) async {
      await pumpRecipe(
        tester,
        const RecipeListScreen(),
        overrides: recipeOverrides(),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('populated lists every recipe', (tester) async {
      await pumpRecipe(
        tester,
        const RecipeListScreen(),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(name: 'Dal'),
            recipeOf(id: 'r2', name: 'Pulao'),
          ],
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.text('Dal'), findsOneWidget);
      expect(find.text('Pulao'), findsOneWidget);
    });

    testWidgets('a way in exists — the catalogue can be added to', (
      tester,
    ) async {
      // Four screens in Phase 8B were built, routed, tested and unreachable. A catalogue with no
      // add affordance is the same failure one level in.
      await pumpRecipe(
        tester,
        const RecipeListScreen(),
        overrides: recipeOverrides(),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });

  group('the badge tells the truth', () {
    testWidgets('everything on hand reads as ready', (tester) async {
      await pumpRecipe(
        tester,
        const RecipeListScreen(),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(ingredients: [linked('flour', 200)]),
          ],
          stock: {'flour': stockOf('flour', 500)},
          items: {'flour': weightItem('flour', 'Flour')},
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.text('Ready'), findsOneWidget);
    });

    testWidgets("an untracked ingredient reads as can't tell, NOT as missing", (
      tester,
    ) async {
      // The distinction the whole module exists for. "Can't cook" would be a confident falsehood.
      await pumpRecipe(
        tester,
        const RecipeListScreen(),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(ingredients: [untracked('salt')]),
          ],
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.text("Can't tell"), findsOneWidget);
      expect(find.textContaining('missing'), findsNothing);
    });

    testWidgets('a shortfall says how many, not just that there is one', (
      tester,
    ) async {
      await pumpRecipe(
        tester,
        const RecipeListScreen(),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(ingredients: [linked('flour', 200)]),
          ],
          stock: {'flour': stockOf('flour', 150)},
          items: {'flour': weightItem('flour', 'Flour')},
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.text('1 short'), findsOneWidget);
    });

    testWidgets('no badge at all while stock is still arriving', (
      tester,
    ) async {
      // A placeholder would read as a verdict. Better to show nothing than to imply an answer.
      await pumpRecipe(
        tester,
        const RecipeListScreen(),
        overrides: [
          ...recipeOverrides(recipes: [recipeOf()]),
        ],
        size: kTallViewport,
      );
      await tester.pump();
      expect(find.text('Ready'), findsNothing);
    });
  });

  group('the gate', () {
    testWidgets('renders at 320x640 with a doubled text scale', (tester) async {
      await pumpRecipe(
        tester,
        const RecipeListScreen(),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(
              name: 'A very long recipe name that will wrap at this width',
            ),
            recipeOf(
              id: 'r2',
              name: 'Pulao',
              ingredients: [linked('rice', 300)],
            ),
          ],
          stock: {'rice': stockOf('rice', 100)},
          items: {'rice': weightItem('rice', 'Rice')},
        ),
        textScale: 2,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
