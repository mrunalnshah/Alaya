import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';

/// One line of a recipe's ingredient list.
///
/// Either [itemId] links it to the inventory catalogue, or [freeText] names it and nothing tracks
/// it. Both being null is meaningless and both being set is contradictory; the repository rejects
/// either shape rather than storing a row nothing can render.
class RecipeIngredient {
  /// Creates an ingredient line.
  const RecipeIngredient({
    required this.id,
    required this.recipeId,
    required this.sortOrder,
    this.itemId,
    this.freeText,
    this.quantity,
    this.unitCode,
    this.isOptional = false,
    this.note,
  });

  /// Row identifier.
  final String id;

  /// The recipe this belongs to.
  final String recipeId;

  /// The catalogued item, when this ingredient refers to one.
  final String? itemId;

  /// What the ingredient is, when there is no [itemId].
  final String? freeText;

  /// How much the recipe needs, at the recipe's own serving count. Null means "to taste".
  final Qty? quantity;

  /// The unit the cook reads, e.g. `g`, `ml`, `pc`.
  final String? unitCode;

  /// Excluded from the cookability verdict.
  final bool isOptional;

  /// Preparation note.
  final String? note;

  /// Display order within the recipe.
  final int sortOrder;

  /// Whether this line points at the inventory catalogue.
  bool get isLinked => itemId != null;
}

/// One instruction in a recipe's method.
class RecipeStep {
  /// Creates a step.
  const RecipeStep({
    required this.id,
    required this.recipeId,
    required this.stepNumber,
    required this.instruction,
    this.durationMinutes,
  });

  /// Row identifier.
  final String id;

  /// The recipe this belongs to.
  final String recipeId;

  /// Position in the method, from 1.
  final int stepNumber;

  /// What to do.
  final String instruction;

  /// How long it takes, when it is worth timing.
  final int? durationMinutes;
}

/// A recipe, with its ingredients and method.
///
/// [servings] anchors every quantity in [ingredients]: a line reading 200 g means 200 g *at this
/// serving count*, and `CookabilityEngine.scaleMilli` is the only thing that rescales it.
class Recipe {
  /// Creates a recipe.
  const Recipe({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.servings,
    this.ingredients = const [],
    this.steps = const [],
    this.prepMinutes,
    this.cookMinutes,
    this.isFavorite = false,
    this.notes,
  });

  /// Row identifier.
  final String id;

  /// Display name.
  final String name;

  /// Casefolded, accent-stripped name for search and duplicate detection.
  ///
  /// Carried on the entity rather than computed in the repository, matching `Item`, `Payee` and
  /// every other named row. The caller builds it with Phase 1A's `Normalizer`, so one
  /// implementation decides what "the same name" means everywhere in the app.
  final String normalizedName;

  /// How many servings the stored quantities describe. Always positive.
  final int servings;

  /// The ingredient list, in display order.
  final List<RecipeIngredient> ingredients;

  /// The method, in step order.
  final List<RecipeStep> steps;

  /// Hands-on time before cooking starts.
  final int? prepMinutes;

  /// Time on the heat.
  final int? cookMinutes;

  /// Pinned by the user.
  final bool isFavorite;

  /// Free-form notes.
  final String? notes;

  /// Prep plus cook, when either is known.
  int? get totalMinutes {
    if (prepMinutes == null && cookMinutes == null) return null;
    return (prepMinutes ?? 0) + (cookMinutes ?? 0);
  }

  /// The ingredients that count toward a cookability verdict.
  List<RecipeIngredient> get requiredIngredients => [
    for (final i in ingredients)
      if (!i.isOptional) i,
  ];

  /// The item ids this recipe draws on, for a stock lookup.
  Set<String> get linkedItemIds => {
    for (final i in ingredients)
      if (i.itemId != null) i.itemId!,
  };
}

/// A record that a recipe was cooked.
class RecipeCook {
  /// Creates a log entry.
  const RecipeCook({
    required this.id,
    required this.recipeId,
    required this.cookedOn,
    required this.servingsCooked,
    required this.deductedStock,
    this.note,
  });

  /// Row identifier.
  final String id;

  /// The recipe that was cooked.
  final String recipeId;

  /// The civil date it was cooked on.
  final DateKey cookedOn;

  /// How many servings were made.
  final int servingsCooked;

  /// Whether inventory was reduced for it.
  final bool deductedStock;

  /// Free-form note.
  final String? note;
}
