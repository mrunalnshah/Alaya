/// Fakes for the two ports `RecipeCookService` writes through.
///
/// **These exist because that service had no test at all.** `RecipeCookService` appeared in no test file
/// in the repository — the deduction path a user reported as broken had never been exercised, which is the
/// third time this feature area has produced that finding (`RecipeDetailScreen` and `parseAmountMilli`
/// being the others). A confirmation sheet is only correct if the thing behind it is.
///
/// **`FakeStock` plans through the real service.** It fakes the *storage*, not the algorithm: the ordering
/// and the expiry policy are `InventoryConsumptionService`'s, exercised for real, and only the batch rows
/// and the movement writes are held in memory. A fake that reimplemented the draw order would pass while
/// production drew from different batches — the exact class of divergence this feature spent five rounds
/// removing.
library;

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recipe.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/domain/repositories/recipe_repository.dart';
import 'package:alaya/domain/repositories/stock_repository.dart';
import 'package:alaya/domain/services/draw_policy.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';

/// One consumption that reached the repository, kept so a test can assert what was drawn.
typedef RecordedConsume = ({
  String itemId,
  Qty quantity,
  StockMovementKind kind,
  DrawPolicy policy,
  List<ConsumptionDraw> draws,
});

/// A `StockRepository` over in-memory batches, planning through the real consumption service.
class FakeStock implements StockRepository {
  /// Creates the fake with [batches] keyed by item id.
  FakeStock({Map<String, List<ConsumableBatch>>? batches})
    : _batches = {...?batches};

  final Map<String, List<ConsumableBatch>> _batches;

  static const InventoryConsumptionService _consumption =
      InventoryConsumptionService();

  /// Every `consume` that succeeded, in order.
  ///
  /// **The policy is recorded too.** The whole point of this feature is that cooking passes
  /// `freshFirst` and a write-off passes `fefo`; a test that only checked the draws could not tell a
  /// service that forgot the policy from one that sent it.
  final List<RecordedConsume> consumed = [];

  /// Every `consume` that was refused, with the failure it gave.
  final List<Failure> refused = [];

  @override
  Future<Result<List<ConsumptionDraw>, Failure>> consume({
    required String itemId,
    required Qty quantity,
    required StockMovementKind kind,
    DrawPolicy policy = const DrawPolicy.fefo(),
    String? reason,
    String? note,
  }) async {
    final shelf = _batches[itemId] ?? const <ConsumableBatch>[];
    final planned = _consumption.plan(
      batches: shelf,
      needed: quantity,
      policy: policy,
    );
    final plan = planned.valueOrNull;
    if (plan == null) {
      final failure =
          planned.failureOrNull ??
          const UnexpectedFailure('Stock could not be planned.');
      refused.add(failure);
      return Result.failure(failure);
    }

    // Applied, so a second consume in the same cook sees a drawn-down shelf. Without this a recipe
    // needing the same item twice would draw the same batch twice and the test would not notice.
    final drawn = {for (final draw in plan.draws) draw.batchId: draw.quantity};
    _batches[itemId] = [
      for (final batch in shelf)
        if (drawn[batch.batchId] == null)
          batch
        else
          ConsumableBatch(
            batchId: batch.batchId,
            remaining: Qty(
              batch.remaining.milliBase - drawn[batch.batchId]!.milliBase,
              batch.remaining.category,
            ),
            purchasedDateKey: batch.purchasedDateKey,
            expiryDateKey: batch.expiryDateKey,
          ),
    ];

    consumed.add((
      itemId: itemId,
      quantity: quantity,
      kind: kind,
      policy: policy,
      draws: plan.draws,
    ));
    return Result.ok(plan.draws);
  }

  /// What is left of [itemId], for asserting the shelf after a cook.
  Qty remainingOf(String itemId, UnitCategory category) {
    var milli = 0;
    for (final batch in _batches[itemId] ?? const <ConsumableBatch>[]) {
      milli += batch.remaining.milliBase;
    }
    return Qty(milli, category);
  }

  // The rest of the contract. `RecipeCookService` touches none of it, and a fake that quietly returned
  // plausible values would let a future change start depending on one of them without a test noticing.
  @override
  Future<Result<void, Failure>> consumeFromBatch({
    required String batchId,
    required Qty quantity,
    required StockMovementKind kind,
    String? reason,
    String? note,
  }) => throw UnimplementedError('FakeStock.consumeFromBatch');

  @override
  Future<Result<void, Failure>> addStock({
    required String batchId,
    required Qty quantity,
    required StockMovementKind kind,
    String? note,
  }) => throw UnimplementedError('FakeStock.addStock');

  @override
  Future<Result<void, Failure>> reverse({
    required String movementId,
    String? reason,
  }) => throw UnimplementedError('FakeStock.reverse');

  @override
  Stream<List<StockMovement>> watchForBatch(String batchId) =>
      throw UnimplementedError('FakeStock.watchForBatch');

  @override
  Stream<List<StockMovement>> watchForItemInRange({
    required String itemId,
    required DateKey from,
    required DateKey to,
  }) => throw UnimplementedError('FakeStock.watchForItemInRange');

  @override
  Future<List<WasteTotal>> wasteTotals({
    required DateKey from,
    required DateKey to,
  }) => throw UnimplementedError('FakeStock.wasteTotals');
}

/// A `RecipeRepository` that records cooks and answers nothing else.
class FakeRecipes implements RecipeRepository {
  /// Creates the fake.
  FakeRecipes({this.logFails = false});

  /// Whether [logCook] refuses, for the branch where the deduction succeeded and the log did not.
  bool logFails;

  /// Every cook logged, in order.
  final List<RecipeCook> logged = [];

  @override
  Future<Result<RecipeCook, Failure>> logCook({
    required String recipeId,
    required DateKey cookedOn,
    required int servingsCooked,
    required bool deductedStock,
    String? note,
  }) async {
    if (logFails) {
      return const Result.failure(
        UnexpectedFailure('That cook could not be recorded.'),
      );
    }
    final cook = RecipeCook(
      id: 'cook-${logged.length + 1}',
      recipeId: recipeId,
      cookedOn: cookedOn,
      servingsCooked: servingsCooked,
      deductedStock: deductedStock,
      note: note,
    );
    logged.add(cook);
    return Result.ok(cook);
  }

  @override
  Stream<List<Recipe>> watchAll() =>
      throw UnimplementedError('FakeRecipes.watchAll');

  @override
  Stream<List<Recipe>> watchMatching(String query) =>
      throw UnimplementedError('FakeRecipes.watchMatching');

  @override
  Stream<List<Recipe>> watchFavorites() =>
      throw UnimplementedError('FakeRecipes.watchFavorites');

  @override
  Stream<Recipe?> watchById(String id) =>
      throw UnimplementedError('FakeRecipes.watchById');

  @override
  Stream<List<Recipe>> watchUsingItem(String itemId) =>
      throw UnimplementedError('FakeRecipes.watchUsingItem');

  @override
  Future<Recipe?> byId(String id) =>
      throw UnimplementedError('FakeRecipes.byId');

  @override
  Future<Result<Recipe, Failure>> save(Recipe recipe) =>
      throw UnimplementedError('FakeRecipes.save');

  @override
  Future<Result<void, Failure>> setFavorite({
    required String id,
    required bool isFavorite,
  }) => throw UnimplementedError('FakeRecipes.setFavorite');

  @override
  Future<Result<void, Failure>> delete(String id) =>
      throw UnimplementedError('FakeRecipes.delete');

  @override
  Stream<List<RecipeCook>> watchCookLog(String recipeId) =>
      throw UnimplementedError('FakeRecipes.watchCookLog');
}
