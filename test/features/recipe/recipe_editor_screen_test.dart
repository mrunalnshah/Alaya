import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/recipe/amount_format.dart';
import 'package:alaya/features/recipe/presentation/screens/recipe_editor_screen.dart';
import 'package:alaya/features/recipe/providers/recipe_editor_providers.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';

import '../../support/recipe_harness.dart';

/// The editor, which is where a recipe becomes something the engine can reason about.
///
/// **Two things make an ingredient count: a link to stock and a measured amount.** For most of this
/// module's life the row offered neither, so every recipe saved as untracked text and every cook
/// deducted nothing. These tests exist to keep that from returning quietly.
void main() {
  group('an ingredient can be linked and measured', () {
    testWidgets('a new recipe starts with no ingredient rows', (tester) async {
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      // No unit dropdown until an ingredient exists: the recipe's own fields — name, servings, prep,
      // cook, notes — are all plain text.
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    });

    testWidgets('adding a row offers an amount AND a unit', (tester) async {
      // A row without a unit picker cannot produce a Qty, which is precisely how every ingredient
      // came out null. Asserted through what the user sees rather than the widget class: the control
      // behind it has already been swapped once, because a recipe must be able to offer spoons for
      // something stored by weight, and a test naming the class failed on a change that did not alter
      // the behaviour it was written to protect.
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ingredient'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('choosing a spoon offers the sizes a drawer actually has', (
      tester,
    ) async {
      // A cook reaches for the half-teaspoon rather than typing 0.5. The chips are only for spoons and
      // cups, so a grams row must not show them — that distinction is the whole reason the hint used to
      // be confusing.
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(units: kSpoonTestUnits),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ingredient'));
      await tester.pumpAndSettle();
      // Defaults to grams, so no chips.
      expect(find.byType(ChoiceChip), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tablespoon').last);
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNWidgets(6));
      expect(find.widgetWithText(ChoiceChip, '1/2'), findsOneWidget);
    });

    testWidgets('every unit is offered, whether or not it can be converted', (
      tester,
    ) async {
      // Writing a recipe is never gated on inventory setup. An earlier version hid spoons until the
      // item declared a tablespoon weight, which made "2 tbsp oil" impossible to write before
      // configuring oil — backwards, and the reason this test exists.
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(
          items: [weightItem('f1', 'Flour')],
          units: kSpoonTestUnits,
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ingredient'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('Tablespoon').last, findsOneWidget);
    });

    testWidgets('typing an ingredient name offers matching catalogue items', (
      tester,
    ) async {
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(items: [weightItem('t1', 'Tomatoes')]),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ingredient'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(4), 'tom');
      await tester.pumpAndSettle();
      // The option is what links the line to stock. Without it the row is free text, which saves
      // fine and can never be checked against inventory.
      expect(find.text('Tomatoes'), findsWidgets);
    });
  });

  group('the form guards itself', () {
    testWidgets('save is disabled until there is a name and an ingredient', (
      tester,
    ) async {
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      // A recipe with no usable ingredient is a note. The engine would report it as `empty`, so the
      // form refuses it rather than storing something the catalogue cannot describe.
      final scaffold = tester.widget<AlayaFormScaffold>(
        find.byType(AlayaFormScaffold),
      );
      expect(scaffold.onPrimary, isNull);
    });

    testWidgets('steps and ingredients do not collide on their keys', (
      tester,
    ) async {
      // Both lists once keyed by position, in the same Column — so ingredient 0 and step 0 were two
      // widgets keyed 0 under one parent, which Flutter refuses outright.
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ingredient'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add step'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('removing a row takes its text with it', (tester) async {
      // The quiet half of the key bug: with positional keys, deleting row 0 left row 1 inheriting
      // row 0's field element, so the deleted row's text stayed on screen.
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ingredient'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ingredient'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(4), 'First');
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(6), 'Second');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();

      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);
    });
  });

  group('every measuring size survives the round trip', () {
    // The bug this group exists for: a written amount is converted to base-milli units for storage and
    // back again for display. Truncating either way turned 1/2 tbsp into 0.499 — so the field showed a
    // number nobody typed and the 1/2 chip never highlighted, which read as "fractions do not work".
    //
    // Whole numbers passed throughout, because a factor divides 1000 exactly at 1x. That is what made
    // it look like a missing feature instead of an arithmetic error.
    for (final code in ['tsp', 'tbsp', 'cup']) {
      testWidgets('$code keeps each standard size exactly', (tester) async {
        await pumpRecipe(
          tester,
          const RecipeEditorScreen(recipeId: ''),
          overrides: editorOverrides(units: kAllMeasureTestUnits),
          size: kTallViewport,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add ingredient'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(_displayName(code)).last);
        await tester.pumpAndSettle();

        for (final label in ['1/4', '1/3', '1/2', '2/3', '3/4']) {
          await tester.tap(find.widgetWithText(ChoiceChip, label));
          await tester.pumpAndSettle();
          // Selected means the value read back equals the value written. Anything lost in the
          // conversion shows up here and nowhere else.
          final chip = tester.widget<ChoiceChip>(
            find.widgetWithText(ChoiceChip, label),
          );
          expect(
            chip.selected,
            isTrue,
            reason: '$label of $code did not round-trip',
          );
        }
      });
    }
  });

  group('a number and a fraction', () {
    testWidgets('3 and a half tablespoons is a number then a tap', (
      tester,
    ) async {
      // What a cook does at the counter: three tablespoons, then the half. Typing `3 1/2` into one
      // field asked them to assemble a string instead.
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(units: kAllMeasureTestUnits),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ingredient'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tablespoon').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(5), '3');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '1/2'));
      await tester.pumpAndSettle();

      // The readout is the proof: 3.5 tbsp is 51.75 ml, and it says so.
      expect(find.textContaining('3 1/2'), findsWidgets);
      final half = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '1/2'),
      );
      expect(half.selected, isTrue);
    });

    testWidgets('tapping the lit fraction clears it, keeping the number', (
      tester,
    ) async {
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(units: kAllMeasureTestUnits),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ingredient'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tablespoon').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(5), '2');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '1/4'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '1/4'));
      await tester.pumpAndSettle();

      // "2 1/4" and "2" are one tap apart in both directions, which is the whole point of a toggle.
      final quarter = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '1/4'),
      );
      expect(quarter.selected, isFalse);
    });
  });

  group('the gate', () {
    testWidgets('renders at 320x640 with a doubled text scale', (tester) async {
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(),
        textScale: 2,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

/// The display name the seeded unit carries, for tapping a dropdown entry.
String _displayName(String code) => switch (code) {
  'tsp' => 'Teaspoon',
  'tbsp' => 'Tablespoon',
  'cup' => 'Cup',
  _ => code,
};
