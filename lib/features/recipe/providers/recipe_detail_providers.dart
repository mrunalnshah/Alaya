/// View-model state for one recipe (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/recipe.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/domain/services/cookability_engine.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';
import 'package:alaya/domain/services/recipe_cook_service.dart';
import 'package:alaya/features/recipe/providers/recipe_list_providers.dart';

/// The recipe being viewed.
final recipeProvider = StreamProvider.family<Recipe?, String>(
  (ref, id) => ref.watch(recipeRepositoryProvider).watchById(id),
);

/// Every unit, keyed by code.
///
/// **The detail screen needs this because an ingredient stores a unit code and nothing resolved it.**
/// `RecipeIngredient.unitCode` records the vessel the cook chose; the row had no way to look it up, so it
/// rendered the canonical quantity instead and a line reading "half a tablespoon" displayed as `7 ml`.
///
/// Keyed rather than a list, unlike `editorUnitsProvider`, because the editor populates a picker and this
/// answers "what is `tbsp`". Two projections of one stream is not two sources for one fact — the same
/// pairing `itemsByIdProvider` and `editorItemsProvider` already have.
final unitsByCodeProvider = StreamProvider<Map<String, Unit>>(
  (ref) => ref
      .watch(unitRepositoryProvider)
      .watchAll()
      .map(
        (units) => {for (final unit in units) unit.code: unit},
      ),
);

/// One item's batches, nearest expiry first.
///
/// A family so Riverpod caches per item: two ingredients of the same thing share one subscription, and
/// the underlying query is index-backed on `inventory_batches(expiry_date_key)`.
///
/// Returns full `Batch` entities because that is what the repository returns; the narrowing to
/// [ConsumableBatch] happens once, in [recipeBatchesProvider], rather than at the repository boundary.
final itemBatchesProvider = StreamProvider.family<List<Batch>, String>(
  (ref, itemId) => ref.watch(batchRepositoryProvider).watchByItemFefo(itemId),
);

/// Every batch behind this recipe's linked ingredients, keyed by item id.
///
/// **This is what buys the precise verdict.** `ItemStock.totalRemaining` comes from `v_item_stock`, which
/// sums batches with **no expiry filter**, so a total alone cannot say how much of it is still good — and
/// that is exactly why cooking was deducting expired stock without saying so.
///
/// **[ConsumableBatch], not `Batch`.** The engine plans through `InventoryConsumptionService`, whose input
/// is the deliberately narrow four-field projection — `ConsumableBatch.fromBatch` is the mapping, and
/// doing it here means the engine never sees an entity it has no use for.
///
/// **Only the detail screen pays for this.** `recipeListProvider` deliberately judges without batches: a
/// query per item across forty recipes for a badge would be the most expensive read in the app.
/// `CookabilityEngine.judge` documents the trade.
///
/// Returns null until **every** ingredient's batches have arrived. A partial map would produce a verdict
/// computed from half the shelf — reporting a shortfall for stock that is simply still loading, which is
/// the kind of momentarily-wrong answer a user screenshots.
final recipeBatchesProvider =
    Provider.family<Map<String, List<ConsumableBatch>>?, String>((ref, id) {
      final recipe = ref.watch(recipeProvider(id)).valueOrNull;
      if (recipe == null) return null;
      final batches = <String, List<ConsumableBatch>>{};
      for (final ingredient in recipe.ingredients) {
        final itemId = ingredient.itemId;
        if (itemId == null || batches.containsKey(itemId)) continue;
        final forItem = ref.watch(itemBatchesProvider(itemId)).valueOrNull;
        if (forItem == null) return null;
        batches[itemId] = [
          for (final batch in forItem) ConsumableBatch.fromBatch(batch),
        ];
      }
      return batches;
    });

/// How many servings the user has dialled the detail screen to.
///
/// Defaults to the recipe's own count. Held per recipe id so opening a second recipe does not inherit
/// the first one's scaling.
final servingsProvider =
    NotifierProvider.family<ServingsNotifier, int?, String>(
      ServingsNotifier.new,
    );

/// Holds the chosen serving count.
class ServingsNotifier extends FamilyNotifier<int?, String> {
  @override
  int? build(String arg) => null;

  /// Sets the count, clamped to at least one — the engine divides by it.
  void set(int servings) => state = servings < 1 ? 1 : servings;

  /// Returns to the recipe's own count.
  void reset() => state = null;
}

/// This recipe's cookability at the currently chosen serving count.
///
/// Judged **with batches**, so expiry is accounted for and each check carries the `ConsumptionPlan` a
/// confirmation sheet and the deduction will share.
final recipeCookabilityProvider = Provider.family<Cookability?, String>((
  ref,
  id,
) {
  final recipe = ref.watch(recipeProvider(id)).valueOrNull;
  final stock = ref.watch(stockByItemProvider).valueOrNull;
  final items = ref.watch(itemsByIdProvider).valueOrNull;
  final batches = ref.watch(recipeBatchesProvider(id));
  if (recipe == null || stock == null || items == null || batches == null) {
    return null;
  }
  return const CookabilityEngine().judge(
    recipe,
    stock: stock,
    items: items,
    // Read from the clock provider rather than `DateTime.now()`, so a test overriding it with a
    // `FixedClock` gets a reproducible verdict — the reason `judge` takes a date at all.
    today: ref.watch(clockProvider).today(),
    batchesByItem: batches,
    servings: ref.watch(servingsProvider(id)) ?? recipe.servings,
  );
});

/// Cooking, and what it did.
final cookControllerProvider =
    NotifierProvider<CookController, AsyncValue<CookOutcome?>>(
      CookController.new,
    );

/// Runs a cook and holds its outcome for the screen to report.
class CookController extends Notifier<AsyncValue<CookOutcome?>> {
  @override
  AsyncValue<CookOutcome?> build() => const AsyncData<CookOutcome?>(null);

  /// Cooks [recipe], optionally without touching stock.
  ///
  /// **[allowExpired] is the answer to a question the screen must already have asked.** False is not a
  /// cautious default — it is the correct one: the service refuses rather than quietly drawing on food
  /// past its date, so a caller that forgets to ask gets a refusal instead of a silent deduction. The
  /// screen learns the question is worth putting from `Cookability.needsExpiredConsent`.
  Future<bool> cook(
    Recipe recipe, {
    required int servings,
    required bool deductStock,
    bool allowExpired = false,
  }) async {
    state = const AsyncLoading<CookOutcome?>();
    final stock = ref.read(stockByItemProvider).valueOrNull ?? const {};
    final items = ref.read(itemsByIdProvider).valueOrNull ?? const {};

    final result = await ref
        .read(recipeCookServiceProvider)
        .cook(
          recipe: recipe,
          stock: stock,
          items: items,
          servings: servings,
          deductStock: deductStock,
          allowExpired: allowExpired,
        );
    if (result.isFailure) {
      state = AsyncError<CookOutcome?>(
        result.failureOrNull ?? StateError('cook failed'),
        StackTrace.current,
      );
      return false;
    }
    state = AsyncData<CookOutcome?>(result.valueOrNull);
    return true;
  }
}
