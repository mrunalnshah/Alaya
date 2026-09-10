import 'package:drift/drift.dart';

import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/date_key_filters.dart';

/// Typed access to the four recipe tables.
///
/// One DAO rather than four, because a recipe is an aggregate: its ingredients and steps have no
/// meaning apart from it, and nothing ever loads a step without the recipe it belongs to. Splitting
/// them would mean a repository orchestrating four DAOs to answer one question.
class RecipeDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  RecipeDao(super.db);

  $RecipesTable get _recipes => attachedDatabase.recipes;
  $RecipeIngredientsTable get _ingredients =>
      attachedDatabase.recipeIngredients;
  $RecipeStepsTable get _steps => attachedDatabase.recipeSteps;
  $RecipeCookLogTable get _cookLog => attachedDatabase.recipeCookLog;

  SimpleSelectStatement<$RecipesTable, RecipeRow> _activeRecipes() =>
      select(_recipes)..where((t) => t.deletedAt.isNull());

  /// Emits every active recipe, newest first. Header rows only — no ingredients or steps.
  Stream<List<RecipeRow>> watchAll() {
    return (_activeRecipes()..orderBy([
          (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
        ]))
        .watch();
  }

  /// Emits active recipes whose normalized name contains [normalizedQuery].
  Stream<List<RecipeRow>> watchMatching(String normalizedQuery) {
    return (_activeRecipes()
          ..where((t) => t.normalizedName.contains(normalizedQuery))
          ..orderBy([(t) => OrderingTerm(expression: t.normalizedName)]))
        .watch();
  }

  /// Emits pinned recipes.
  Stream<List<RecipeRow>> watchFavorites() {
    return (_activeRecipes()
          ..where((t) => t.isFavorite.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.normalizedName)]))
        .watch();
  }

  /// Emits one recipe header, or null when it does not exist or is soft-deleted.
  Stream<RecipeRow?> watchById(String id) =>
      (_activeRecipes()..where((t) => t.id.equals(id))).watchSingleOrNull();

  /// Reads one recipe header.
  Future<RecipeRow?> byId(String id) =>
      (_activeRecipes()..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Emits the active ingredient lines of [recipeId], in display order.
  Stream<List<RecipeIngredientRow>> watchIngredients(String recipeId) {
    return (select(_ingredients)
          ..where((t) => t.recipeId.equals(recipeId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Reads the active ingredient lines of several recipes at once.
  ///
  /// A list screen showing a cookability badge per row needs every recipe's ingredients. One query
  /// with `isIn` rather than N queries, because the alternative is a query per visible row on every
  /// rebuild of a virtualised list.
  Stream<List<RecipeIngredientRow>> watchIngredientsForAll(
    List<String> recipeIds,
  ) {
    return (select(_ingredients)
          ..where((t) => t.recipeId.isIn(recipeIds) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Emits the active steps of [recipeId], in order.
  Stream<List<RecipeStepRow>> watchSteps(String recipeId) {
    return (select(_steps)
          ..where((t) => t.recipeId.equals(recipeId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.stepNumber)]))
        .watch();
  }

  /// Emits the recipes that use [itemId] as an ingredient.
  ///
  /// The reverse lookup an item's detail screen shows. A join rather than two round trips, and
  /// `useColumns: false` because only the recipe rows are wanted — without it drift materialises
  /// the ingredient columns as well for every match.
  Stream<List<RecipeRow>> watchUsingItem(String itemId) {
    final query =
        select(_recipes).join([
            innerJoin(
              _ingredients,
              _ingredients.recipeId.equalsExp(_recipes.id),
              useColumns: false,
            ),
          ])
          ..where(
            _recipes.deletedAt.isNull() &
                _ingredients.deletedAt.isNull() &
                _ingredients.itemId.equals(itemId),
          )
          ..orderBy([OrderingTerm(expression: _recipes.normalizedName)]);
    // An item can appear on two lines of the same recipe — "2 eggs, then 1 egg to glaze" — so the
    // join can return a recipe twice. `groupBy` on the id is cheaper than de-duplicating in Dart
    // and keeps the stream emitting a clean list.
    query.groupBy([_recipes.id]);
    return query.watch().map(
      (rows) => rows.map((r) => r.readTable(_recipes)).toList(),
    );
  }

  /// Replaces a recipe and its whole ingredient and step list, atomically.
  ///
  /// **Delete-then-insert inside one transaction, rather than diffing.** An editor can reorder,
  /// remove and add lines in one sitting; computing a minimal diff would need stable line
  /// identities the UI does not carry, and would leave a half-applied list if any step failed.
  /// The rows are soft-deleted rather than dropped so the trash keeps its promise (ARCH_3 §4.2).
  Future<void> saveAggregate({
    required RecipesCompanion recipe,
    required List<RecipeIngredientsCompanion> ingredients,
    required List<RecipeStepsCompanion> steps,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      await into(_recipes).insertOnConflictUpdate(recipe);
      final id = recipe.id.value;

      await (update(
        _ingredients,
      )..where((t) => t.recipeId.equals(id) & t.deletedAt.isNull())).write(
        RecipeIngredientsCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );
      await (update(
        _steps,
      )..where((t) => t.recipeId.equals(id) & t.deletedAt.isNull())).write(
        RecipeStepsCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );

      for (final line in ingredients) {
        await into(_ingredients).insertOnConflictUpdate(line);
      }
      for (final step in steps) {
        await into(_steps).insertOnConflictUpdate(step);
      }
    });
  }

  /// Pins or unpins a recipe.
  Future<void> setFavorite({
    required String id,
    required bool isFavorite,
    required int nowUtcMillis,
  }) {
    return (update(_recipes)..where((t) => t.id.equals(id))).write(
      RecipesCompanion(
        isFavorite: Value(isFavorite),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Soft-deletes a recipe and every line beneath it, in one transaction.
  ///
  /// The children go too. A recipe in the trash whose ingredients were still active would surface
  /// in `watchUsingItem` — an item claiming to be used by a recipe the user deleted.
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return transaction(() async {
      await (update(_recipes)..where((t) => t.id.equals(id))).write(
        RecipesCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );
      await (update(_ingredients)..where((t) => t.recipeId.equals(id))).write(
        RecipeIngredientsCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );
      await (update(_steps)..where((t) => t.recipeId.equals(id))).write(
        RecipeStepsCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );
    });
  }

  /// Records that a recipe was cooked.
  Future<void> insertCook(RecipeCookLogCompanion entry) =>
      into(_cookLog).insertOnConflictUpdate(entry);

  /// Emits past cooks of [recipeId], most recent first.
  Stream<List<RecipeCookLogRow>> watchCookLog(String recipeId) {
    return (select(_cookLog)
          ..where((t) => t.recipeId.equals(recipeId) & t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.cookedDateKey,
              mode: OrderingMode.desc,
            ),
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  /// How many times [recipeId] has been cooked on or after [since].
  ///
  /// `isDateOnOrAfter` from `date_key_filters.dart`, not `isBiggerOrEqualValue`. `DateKey` does not
  /// implement `int` — deliberately, so `dateKey + 1` cannot compile — and drift's comparisons
  /// operate on the column's SQL type even with a converter attached. That extension crosses the
  /// boundary once, where it is visible; doing it inline here would be the spread it exists to
  /// prevent.
  Future<int> cookCountSince({
    required String recipeId,
    required DateKey since,
  }) async {
    final rows =
        await (select(_cookLog)..where(
              (t) =>
                  t.recipeId.equals(recipeId) &
                  t.deletedAt.isNull() &
                  t.cookedDateKey.isDateOnOrAfter(since),
            ))
            .get();
    return rows.length;
  }
}
