/// View-model state for the recipe editor (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/text/normalizer.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/recipe.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/recipe/providers/recipe_list_providers.dart';
import 'package:alaya/features/recipe/state/recipe_editor_state.dart';

/// Every unit, for the ingredient rows' pickers.
final editorUnitsProvider = StreamProvider<List<Unit>>(
  (ref) => ref.watch(unitRepositoryProvider).watchAll(),
);

/// Every catalogued item, so an ingredient can be linked to stock.
///
/// **Linking is what makes cookability and deduction work at all.** An unlinked line is honest but
/// inert: the engine reports it as untracked and a cook skips it. This list is what turns "tomatoes"
/// the word into tomatoes the thing you have 500 g of.
final editorItemsProvider = StreamProvider<List<Item>>(
  (ref) => ref.watch(itemRepositoryProvider).watchAll(),
);

/// The editor's state for one recipe id, or the empty string for a new one.
final recipeEditorProvider =
    NotifierProvider.family<RecipeEditorNotifier, RecipeEditorState, String>(
      RecipeEditorNotifier.new,
    );

/// Drives every field in the editor.
class RecipeEditorNotifier extends FamilyNotifier<RecipeEditorState, String> {
  @override
  RecipeEditorState build(String arg) {
    if (arg.isEmpty) return const RecipeEditorState();
    // Seeded from whatever the list already holds rather than a fresh read: the catalogue is already
    // watching, so a second query would fetch what is in memory a frame later.
    final entries = ref.read(recipeListProvider).valueOrNull;
    if (entries != null) {
      for (final entry in entries) {
        if (entry.recipe.id == arg) return RecipeEditorState.from(entry.recipe);
      }
    }
    return const RecipeEditorState();
  }

  void _touch(RecipeEditorState next) =>
      state = next.copyWith(isDirty: true, clearFailure: true);

  /// Sets the name.
  void setName(String name) => _touch(state.copyWith(name: name));

  /// Sets the serving count, never below one — the engine divides by it.
  void setServings(int servings) =>
      _touch(state.copyWith(servings: servings < 1 ? 1 : servings));

  /// Sets the hands-on minutes.
  void setPrepMinutes(int? minutes) =>
      _touch(state.copyWith(prepMinutes: minutes));

  /// Sets the minutes on the heat.
  void setCookMinutes(int? minutes) =>
      _touch(state.copyWith(cookMinutes: minutes));

  /// Sets the notes.
  void setNotes(String? notes) => _touch(state.copyWith(notes: notes));

  /// Pins or unpins.
  void toggleFavourite() =>
      _touch(state.copyWith(isFavorite: !state.isFavorite));

  /// Appends an empty ingredient line.
  ///
  /// **The id is generated now, not at save time.** A draft with no id has no stable identity, and
  /// the editor's rows are keyed by it: with positional keys, removing the first row makes the
  /// second row inherit the first row's `TextFormField` element — and `initialValue` only applies on
  /// the first build, so the field keeps showing the deleted row's text.
  void addIngredient() => _touch(
    state.copyWith(
      ingredients: [
        ...state.ingredients,
        IngredientDraft(id: ref.read(uidGeneratorProvider).generate()),
      ],
    ),
  );

  /// Replaces the line at [index].
  void updateIngredient(int index, IngredientDraft draft) {
    final next = [...state.ingredients]..[index] = draft;
    _touch(state.copyWith(ingredients: next));
  }

  /// Removes the line at [index].
  void removeIngredient(int index) {
    final next = [...state.ingredients]..removeAt(index);
    _touch(state.copyWith(ingredients: next));
  }

  /// Appends an empty step. Same identity argument as [addIngredient].
  void addStep() => _touch(
    state.copyWith(
      steps: [
        ...state.steps,
        StepDraft(id: ref.read(uidGeneratorProvider).generate()),
      ],
    ),
  );

  /// Replaces the step at [index].
  void updateStep(int index, StepDraft draft) {
    final next = [...state.steps]..[index] = draft;
    _touch(state.copyWith(steps: next));
  }

  /// Removes the step at [index].
  void removeStep(int index) {
    final next = [...state.steps]..removeAt(index);
    _touch(state.copyWith(steps: next));
  }

  /// Saves, returning the id on success.
  ///
  /// **Quantities are parsed here, once, not on every keystroke.** A field that reformats while you
  /// type fights you; a field that rejects "1." before you have typed "5" is worse. Anything
  /// unparseable becomes a line with no quantity, which the engine already treats as untracked
  /// rather than zero.
  Future<String?> save() async {
    if (!state.canSave) return null;
    state = state.copyWith(isSaving: true, clearFailure: true);

    final uids = ref.read(uidGeneratorProvider);
    final id = state.id.isEmpty ? uids.generate() : state.id;
    final lines = <RecipeIngredient>[];
    for (var i = 0; i < state.ingredients.length; i++) {
      final draft = state.ingredients[i];
      if (!draft.isComplete) continue;
      lines.add(
        RecipeIngredient(
          id: draft.id,
          recipeId: id,
          itemId: draft.itemId,
          // Exactly one, as the repository requires. A linked line carries no free text even if the
          // user typed some before picking an item.
          freeText: draft.itemId == null ? draft.freeText.trim() : null,
          // Straight through. `QtyField` already validated this and handed back a finished `Qty`,
          // so there is no second parse here to disagree with the first — which is exactly what
          // produced a null quantity on every line: the parse needed a `unitCode` nothing set.
          quantity: draft.quantity,
          unitCode: draft.unitCode,
          isOptional: draft.isOptional,
          note: draft.note,
          sortOrder: i,
        ),
      );
    }

    final result = await ref
        .read(recipeRepositoryProvider)
        .save(
          Recipe(
            id: id,
            name: state.name.trim(),
            normalizedName: const Normalizer().normalize(state.name),
            servings: state.servings,
            ingredients: lines,
            steps: [
              for (var i = 0; i < state.steps.length; i++)
                if (state.steps[i].instruction.trim().isNotEmpty)
                  RecipeStep(
                    id: state.steps[i].id,
                    recipeId: id,
                    stepNumber: i + 1,
                    instruction: state.steps[i].instruction.trim(),
                    durationMinutes: state.steps[i].durationMinutes,
                  ),
            ],
            prepMinutes: state.prepMinutes,
            cookMinutes: state.cookMinutes,
            isFavorite: state.isFavorite,
            notes: (state.notes ?? '').trim().isEmpty
                ? null
                : state.notes!.trim(),
          ),
        );

    if (result.isFailure) {
      state = state.copyWith(
        isSaving: false,
        failureMessage: result.failureOrNull?.message,
      );
      return null;
    }
    state = state.copyWith(isSaving: false, isDirty: false);
    return id;
  }
}
