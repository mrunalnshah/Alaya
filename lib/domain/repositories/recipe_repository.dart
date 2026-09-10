import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recipe.dart';

/// Reading and writing recipes.
///
/// Ingredients and steps are never saved independently of their recipe: [save] replaces the whole
/// aggregate in one transaction. A partially-saved recipe — three of five ingredients, steps out of
/// order — is a state no screen can render and no user asked for.
abstract interface class RecipeRepository {
  /// Every recipe, newest first. Ingredients and steps are included.
  Stream<List<Recipe>> watchAll();

  /// Recipes whose normalized name contains [query].
  Stream<List<Recipe>> watchMatching(String query);

  /// Pinned recipes.
  Stream<List<Recipe>> watchFavorites();

  /// One recipe with its ingredients and steps, or null if it does not exist.
  Stream<Recipe?> watchById(String id);

  /// Recipes that use [itemId] as an ingredient.
  ///
  /// The reverse lookup an item's detail screen shows: *"you can make 3 things with this"*. Backed
  /// by an index on `recipe_ingredients.itemId`.
  Stream<List<Recipe>> watchUsingItem(String itemId);

  /// Fetches one recipe.
  Future<Recipe?> byId(String id);

  /// Inserts or replaces [recipe] and its whole ingredient and step list, atomically.
  ///
  /// Rejects an ingredient with neither an item link nor free text, and one with both.
  Future<Result<Recipe, Failure>> save(Recipe recipe);

  /// Pins or unpins.
  Future<Result<void, Failure>> setFavorite({
    required String id,
    required bool isFavorite,
  });

  /// Soft-deletes the recipe and its lines.
  Future<Result<void, Failure>> delete(String id);

  /// Records that [recipeId] was cooked, without touching stock.
  ///
  /// Deducting inventory is `RecipeCookService`'s job, not this one — a repository that consumed
  /// stock as a side effect of a write would put FEFO ordering behind a `save`.
  Future<Result<RecipeCook, Failure>> logCook({
    required String recipeId,
    required DateKey cookedOn,
    required int servingsCooked,
    required bool deductedStock,
    String? note,
  });

  /// Past cooks of [recipeId], most recent first.
  Stream<List<RecipeCook>> watchCookLog(String recipeId);
}
