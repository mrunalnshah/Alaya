import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/converters/qty_converter.dart';
import 'package:alaya/domain/entities/recipe.dart';

/// Maps recipe rows to domain entities.
///
/// **A [UnitCategory] has to be supplied per ingredient**, because no recipe row stores one.
/// `QtyColumns` documents why: a `Qty` needs a category, and the category lives on
/// `items.unit_category` or `units.category` — never beside the quantity. The repository resolves
/// it once per save or load and threads it through here, which is what stops this file inventing
/// a category it cannot know.
extension RecipeIngredientMapper on RecipeIngredientRow {
  /// Maps this row to a domain entity, using [category] from the linked item or unit.
  RecipeIngredient toEntity({required UnitCategory? category}) =>
      RecipeIngredient(
        id: id,
        recipeId: recipeId,
        itemId: itemId,
        freeText: freeText,
        quantity: QtyColumns.readOrNull(quantityMilli, category),
        unitCode: unitCode,
        isOptional: isOptional,
        note: note,
        sortOrder: sortOrder,
      );
}

/// Maps step rows.
extension RecipeStepMapper on RecipeStepRow {
  /// Maps this row to a domain entity.
  RecipeStep toEntity() => RecipeStep(
    id: id,
    recipeId: recipeId,
    stepNumber: stepNumber,
    instruction: instruction,
    durationMinutes: durationMinutes,
  );
}

/// Maps recipe header rows.
extension RecipeMapper on RecipeRow {
  /// Maps this row plus its already-loaded [ingredients] and [steps] to a domain entity.
  ///
  /// The children are passed in rather than fetched here: a mapper that queried would make every
  /// list row a database round trip, and this extension has no database to query with.
  Recipe toEntity({
    required List<RecipeIngredient> ingredients,
    required List<RecipeStep> steps,
  }) => Recipe(
    id: id,
    name: name,
    normalizedName: normalizedName,
    servings: servings,
    ingredients: ingredients,
    steps: steps,
    prepMinutes: prepMinutes,
    cookMinutes: cookMinutes,
    isFavorite: isFavorite,
    notes: notes,
  );
}

/// Maps cook-log rows.
extension RecipeCookMapper on RecipeCookLogRow {
  /// Maps this row to a domain entity.
  RecipeCook toEntity() => RecipeCook(
    id: id,
    recipeId: recipeId,
    cookedOn: cookedDateKey,
    servingsCooked: servingsCooked,
    deductedStock: deductedStock,
    note: note,
  );
}
