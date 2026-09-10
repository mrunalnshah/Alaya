import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/recipe.dart';

/// One ingredient line while it is being edited.
///
/// A draft rather than a [RecipeIngredient] because a half-typed line is not a valid one: the
/// quantity is still text, and the entity's "either an item or free text" invariant is exactly what
/// the user is in the middle of deciding.
class IngredientDraft {
  /// Creates a draft.
  const IngredientDraft({
    this.id = '',
    this.itemId,
    this.itemName,
    this.freeText = '',
    this.quantity,
    this.category = UnitCategory.weight,
    this.unitCode,
    this.isOptional = false,
    this.note,
  });

  /// The row id, empty for a line that has never been saved.
  final String id;

  /// The linked catalogue item, if any.
  final String? itemId;

  /// That item's name, held so the row can render without a lookup.
  final String? itemName;

  /// What the ingredient is, when it is not linked.
  final String freeText;

  /// The measured amount, or null for "to taste".
  ///
  /// **A `Qty`, not text.** `QtyField` parses and validates as the user types and hands back a
  /// finished value, so the editor no longer re-parses on save — which is what made every ingredient
  /// quantity null: the parse depended on a `unitCode` no widget ever set.
  final Qty? quantity;

  /// Which dimension this line is measured in.
  ///
  /// Follows the linked item when there is one — tomatoes are weighed, so their line offers grams
  /// and kilograms and nothing else (Law L8). An unlinked line defaults to weight.
  final UnitCategory category;

  /// The unit the cook reads.
  final String? unitCode;

  /// Excluded from the cookability verdict.
  final bool isOptional;

  /// Preparation note.
  final String? note;

  /// A copy with the given fields replaced.
  IngredientDraft copyWith({
    String? id,
    String? itemId,
    String? itemName,
    String? freeText,
    Qty? quantity,
    UnitCategory? category,
    String? unitCode,
    bool clearQuantity = false,
    bool? isOptional,
    String? note,
    bool clearItem = false,
  }) => IngredientDraft(
    id: id ?? this.id,
    itemId: clearItem ? null : (itemId ?? this.itemId),
    itemName: clearItem ? null : (itemName ?? this.itemName),
    freeText: freeText ?? this.freeText,
    quantity: clearQuantity ? null : (quantity ?? this.quantity),
    category: category ?? this.category,
    unitCode: unitCode ?? this.unitCode,
    isOptional: isOptional ?? this.isOptional,
    note: note ?? this.note,
  );

  /// What the row displays: the linked item's name, or the typed text.
  String get label => itemName ?? freeText;

  /// Whether this line has enough to save.
  bool get isComplete => itemId != null || freeText.trim().isNotEmpty;
}

/// One step while it is being edited.
class StepDraft {
  /// Creates a draft.
  const StepDraft({this.id = '', this.instruction = '', this.durationMinutes});

  /// The row id, empty for a new step.
  final String id;

  /// What to do.
  final String instruction;

  /// How long it takes.
  final int? durationMinutes;

  /// A copy with the given fields replaced.
  StepDraft copyWith({String? id, String? instruction, int? durationMinutes}) =>
      StepDraft(
        id: id ?? this.id,
        instruction: instruction ?? this.instruction,
        durationMinutes: durationMinutes ?? this.durationMinutes,
      );
}

/// The recipe editor's whole state.
class RecipeEditorState {
  /// Creates a state.
  const RecipeEditorState({
    this.id = '',
    this.name = '',
    this.servings = 2,
    this.prepMinutes,
    this.cookMinutes,
    this.notes,
    this.isFavorite = false,
    this.ingredients = const [],
    this.steps = const [],
    this.isDirty = false,
    this.isSaving = false,
    this.failureMessage,
  });

  /// Builds the editor's state from an existing recipe.
  factory RecipeEditorState.from(Recipe recipe) => RecipeEditorState(
    id: recipe.id,
    name: recipe.name,
    servings: recipe.servings,
    prepMinutes: recipe.prepMinutes,
    cookMinutes: recipe.cookMinutes,
    notes: recipe.notes,
    isFavorite: recipe.isFavorite,
    ingredients: [
      for (final line in recipe.ingredients)
        IngredientDraft(
          id: line.id,
          itemId: line.itemId,
          freeText: line.freeText ?? '',
          quantity: line.quantity,
          category: line.quantity?.category ?? UnitCategory.weight,
          unitCode: line.unitCode,
          isOptional: line.isOptional,
          note: line.note,
        ),
    ],
    steps: [
      for (final step in recipe.steps)
        StepDraft(
          id: step.id,
          instruction: step.instruction,
          durationMinutes: step.durationMinutes,
        ),
    ],
  );

  /// The row id, empty for a new recipe.
  final String id;

  /// Display name.
  final String name;

  /// How many servings the quantities describe.
  final int servings;

  /// Hands-on minutes.
  final int? prepMinutes;

  /// Minutes on the heat.
  final int? cookMinutes;

  /// Free-form notes.
  final String? notes;

  /// Pinned.
  final bool isFavorite;

  /// The ingredient lines.
  final List<IngredientDraft> ingredients;

  /// The method.
  final List<StepDraft> steps;

  /// Whether anything has been edited, for the discard guard.
  final bool isDirty;

  /// Whether a save is in flight.
  final bool isSaving;

  /// The repository's own message from the last failure (Law U9).
  final String? failureMessage;

  /// A copy with the given fields replaced.
  RecipeEditorState copyWith({
    String? id,
    String? name,
    int? servings,
    int? prepMinutes,
    int? cookMinutes,
    String? notes,
    bool? isFavorite,
    List<IngredientDraft>? ingredients,
    List<StepDraft>? steps,
    bool? isDirty,
    bool? isSaving,
    String? failureMessage,
    bool clearFailure = false,
  }) => RecipeEditorState(
    id: id ?? this.id,
    name: name ?? this.name,
    servings: servings ?? this.servings,
    prepMinutes: prepMinutes ?? this.prepMinutes,
    cookMinutes: cookMinutes ?? this.cookMinutes,
    notes: notes ?? this.notes,
    isFavorite: isFavorite ?? this.isFavorite,
    ingredients: ingredients ?? this.ingredients,
    steps: steps ?? this.steps,
    isDirty: isDirty ?? this.isDirty,
    isSaving: isSaving ?? this.isSaving,
    failureMessage: clearFailure
        ? null
        : (failureMessage ?? this.failureMessage),
  );

  /// Whether the form can be submitted.
  ///
  /// A name and at least one usable ingredient. A recipe with no ingredients is a note, and the
  /// engine reports it as [CookabilityStatus.empty] — better to refuse it here than to store one.
  bool get canSave =>
      name.trim().isNotEmpty &&
      servings > 0 &&
      ingredients.any((line) => line.isComplete);
}
