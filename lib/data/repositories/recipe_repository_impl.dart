import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/item_dao.dart';
import 'package:alaya/data/daos/recipe_dao.dart';
import 'package:alaya/data/daos/unit_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/mappers/recipe_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/recipe.dart';
import 'package:alaya/domain/repositories/recipe_repository.dart';
import 'package:drift/drift.dart';

/// `RecipeRepository` backed by [RecipeDao].
///
/// **Its main job beyond mapping is resolving a [UnitCategory] for every ingredient**, because no
/// recipe row stores one. The category comes from the linked item where there is one, and from the
/// unit's own row otherwise — see `QtyColumns` for why the schema is arranged that way.
final class RecipeRepositoryImpl implements RecipeRepository {
  /// Creates the repository.
  const RecipeRepositoryImpl(
    this._dao,
    this._itemDao,
    this._unitDao,
    this._uids,
    this._clock,
  );

  final RecipeDao _dao;
  final ItemDao _itemDao;
  final UnitDao _unitDao;
  final UidGenerator _uids;
  final Clock _clock;

  /// Builds the item-id and unit-code lookups an ingredient list needs to become entities.
  ///
  /// Two lookups rather than a join, because an ingredient may carry a unit with no item — "200 ml
  /// water" that nobody catalogues — and a join on items would drop that line's category entirely.
  Future<UnitCategory?> _categoryFor(
    RecipeIngredientRow row, {
    required Map<String, UnitCategory> itemCategories,
    required Map<String, UnitCategory> unitCategories,
  }) async {
    final itemId = row.itemId;
    if (itemId != null) return itemCategories[itemId];
    final code = row.unitCode;
    return code == null ? null : unitCategories[code];
  }

  Future<List<RecipeIngredient>> _hydrate(
    List<RecipeIngredientRow> rows,
  ) async {
    if (rows.isEmpty) return const [];

    final itemIds = {
      for (final r in rows)
        if (r.itemId != null) r.itemId!,
    };
    final unitCodes = {
      for (final r in rows)
        if (r.unitCode != null) r.unitCode!,
    };

    final itemCategories = <String, UnitCategory>{};
    for (final id in itemIds) {
      final item = await _itemDao.byIdIncludingDeleted(id);
      if (item != null) itemCategories[id] = item.unitCategory;
    }
    // One call rather than one per code — `UnitDao` already exposes the whole map, and the unit
    // list is small and effectively static.
    final unitCategories = await _unitDao.categoriesByCode();

    final out = <RecipeIngredient>[];
    for (final row in rows) {
      final category = await _categoryFor(
        row,
        itemCategories: itemCategories,
        unitCategories: unitCategories,
      );
      out.add(row.toEntity(category: category));
    }
    return out;
  }

  Future<Recipe> _assemble(RecipeRow row) async {
    final ingredientRows = await _dao.watchIngredients(row.id).first;
    final stepRows = await _dao.watchSteps(row.id).first;
    return row.toEntity(
      ingredients: await _hydrate(ingredientRows),
      steps: [for (final s in stepRows) s.toEntity()],
    );
  }

  Future<List<Recipe>> _assembleAll(List<RecipeRow> rows) async {
    if (rows.isEmpty) return const [];
    final ids = [for (final r in rows) r.id];
    final ingredientRows = await _dao.watchIngredientsForAll(ids).first;
    final ingredients = await _hydrate(ingredientRows);

    final byRecipe = <String, List<RecipeIngredient>>{};
    for (final i in ingredients) {
      byRecipe.putIfAbsent(i.recipeId, () => []).add(i);
    }
    return [
      for (final row in rows)
        row.toEntity(
          ingredients: byRecipe[row.id] ?? const [],
          steps: const [],
        ),
    ];
  }

  @override
  Stream<List<Recipe>> watchAll() => _dao.watchAll().asyncMap(_assembleAll);

  @override
  Stream<List<Recipe>> watchMatching(String query) =>
      // [query] arrives already normalized, for the same reason the entity carries
      // `normalizedName`: one implementation of "the same name" (Phase 1A `Normalizer`).
      _dao.watchMatching(query).asyncMap(_assembleAll);

  @override
  Stream<List<Recipe>> watchFavorites() =>
      _dao.watchFavorites().asyncMap(_assembleAll);

  @override
  Stream<Recipe?> watchById(String id) => _dao
      .watchById(id)
      .asyncMap(
        (row) async => row == null ? null : _assemble(row),
      );

  @override
  Stream<List<Recipe>> watchUsingItem(String itemId) =>
      _dao.watchUsingItem(itemId).asyncMap(_assembleAll);

  @override
  Future<Recipe?> byId(String id) async {
    final row = await _dao.byId(id);
    return row == null ? null : _assemble(row);
  }

  @override
  Future<Result<Recipe, Failure>> save(Recipe recipe) async {
    if (recipe.servings <= 0) {
      return const Result.failure(
        BusinessRuleFailure(
          'A recipe must serve at least one.',
          rule: 'recipeServings',
        ),
      );
    }
    for (final line in recipe.ingredients) {
      final linked = line.itemId != null;
      final named = (line.freeText ?? '').trim().isNotEmpty;
      // Exactly one, mirroring `shopping_entries`. Neither is a row nothing can render; both is a
      // row two screens would disagree about.
      if (linked == named) {
        return const Result.failure(
          BusinessRuleFailure(
            'An ingredient needs either an item or a name, not both.',
            rule: 'recipeIngredientIdentity',
          ),
        );
      }
    }

    try {
      final existing = await _dao.byId(recipe.id);
      final stamps = WriteTimestamps.resolve(
        existingCreatedAt: existing?.createdAt,
        clock: _clock,
      );
      final now = stamps.updatedAt;

      await _dao.saveAggregate(
        nowUtcMillis: now,
        recipe: RecipesCompanion(
          id: Value(recipe.id),
          name: Value(recipe.name),
          normalizedName: Value(recipe.normalizedName),
          servings: Value(recipe.servings),
          prepMinutes: Value(recipe.prepMinutes),
          cookMinutes: Value(recipe.cookMinutes),
          isFavorite: Value(recipe.isFavorite),
          notes: Value(recipe.notes),
          createdAt: Value(stamps.createdAt),
          updatedAt: Value(now),
          deletedAt: const Value(null),
        ),
        ingredients: [
          for (var i = 0; i < recipe.ingredients.length; i++)
            _ingredientCompanion(recipe.ingredients[i], recipe.id, i, now),
        ],
        steps: [
          for (var i = 0; i < recipe.steps.length; i++)
            RecipeStepsCompanion(
              id: Value(
                recipe.steps[i].id.isEmpty
                    ? _uids.generate()
                    : recipe.steps[i].id,
              ),
              recipeId: Value(recipe.id),
              stepNumber: Value(i + 1),
              instruction: Value(recipe.steps[i].instruction),
              durationMinutes: Value(recipe.steps[i].durationMinutes),
              createdAt: Value(now),
              updatedAt: Value(now),
              deletedAt: const Value(null),
            ),
        ],
      );

      final saved = await byId(recipe.id);
      return saved == null
          ? const Result.failure(
              UnexpectedFailure('The recipe could not be read back.'),
            )
          : Result.ok(saved);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That recipe could not be saved.', cause: error),
      );
    }
  }

  RecipeIngredientsCompanion _ingredientCompanion(
    RecipeIngredient line,
    String recipeId,
    int index,
    int now,
  ) => RecipeIngredientsCompanion(
    id: Value(line.id.isEmpty ? _uids.generate() : line.id),
    recipeId: Value(recipeId),
    itemId: Value(line.itemId),
    freeText: Value(line.freeText),
    quantityMilli: Value(line.quantity?.milliBase),
    unitCode: Value(line.unitCode),
    isOptional: Value(line.isOptional),
    note: Value(line.note),
    sortOrder: Value(index),
    createdAt: Value(now),
    updatedAt: Value(now),
    deletedAt: const Value(null),
  );

  @override
  Future<Result<void, Failure>> setFavorite({
    required String id,
    required bool isFavorite,
  }) async {
    try {
      await _dao.setFavorite(
        id: id,
        isFavorite: isFavorite,
        nowUtcMillis: _clock.nowUtcMillis(),
      );
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That could not be changed.', cause: error),
      );
    }
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    try {
      await _dao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That recipe could not be deleted.', cause: error),
      );
    }
  }

  @override
  Future<Result<RecipeCook, Failure>> logCook({
    required String recipeId,
    required DateKey cookedOn,
    required int servingsCooked,
    required bool deductedStock,
    String? note,
  }) async {
    try {
      final now = _clock.nowUtcMillis();
      final id = _uids.generate();
      await _dao.insertCook(
        RecipeCookLogCompanion(
          id: Value(id),
          recipeId: Value(recipeId),
          cookedDateKey: Value(cookedOn),
          servingsCooked: Value(servingsCooked),
          deductedStock: Value(deductedStock),
          note: Value(note),
          createdAt: Value(now),
          updatedAt: Value(now),
          deletedAt: const Value(null),
        ),
      );
      return Result.ok(
        RecipeCook(
          id: id,
          recipeId: recipeId,
          cookedOn: cookedOn,
          servingsCooked: servingsCooked,
          deductedStock: deductedStock,
          note: note,
        ),
      );
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That cook could not be recorded.', cause: error),
      );
    }
  }

  @override
  Stream<List<RecipeCook>> watchCookLog(String recipeId) => _dao
      .watchCookLog(recipeId)
      .map((rows) => [for (final r in rows) r.toEntity()]);
}
