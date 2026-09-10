/// View-model state for the recipe catalogue (ARCH_5 U19).
library;

import 'package:alaya/core/time/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/recipe.dart';
import 'package:alaya/domain/services/cookability_engine.dart';

/// How the catalogue is filtered.
class RecipeFilter {
  /// Creates a filter.
  const RecipeFilter({
    this.query = '',
    this.favouritesOnly = false,
    this.cookableOnly = false,
  });

  /// Free-text search, already normalized by the notifier.
  final String query;

  /// Only pinned recipes.
  final bool favouritesOnly;

  /// Only recipes the engine reports as cookable.
  ///
  /// Deliberately excludes `uncheckable`. A recipe the engine could not judge is not one it can
  /// promise you can cook, and putting it in this list would make the filter mean "probably".
  ///
  /// **Includes `readyWithExpired`**, because the engine *can* judge those and they *can* be cooked —
  /// they need the cook's permission, not a shopping trip. On this screen the distinction cannot
  /// currently arise, since the list judges without batches and expiry needs them, but the filter
  /// should mean what it says rather than happening to be right.
  final bool cookableOnly;

  /// A copy with the given fields replaced.
  RecipeFilter copyWith({
    String? query,
    bool? favouritesOnly,
    bool? cookableOnly,
  }) => RecipeFilter(
    query: query ?? this.query,
    favouritesOnly: favouritesOnly ?? this.favouritesOnly,
    cookableOnly: cookableOnly ?? this.cookableOnly,
  );

  /// Whether anything is narrowing the list.
  bool get isActive => query.isNotEmpty || favouritesOnly || cookableOnly;
}

/// The catalogue's current filter.
final recipeFilterProvider =
    NotifierProvider<RecipeFilterNotifier, RecipeFilter>(
      RecipeFilterNotifier.new,
    );

/// Drives the search field and the filter chips.
class RecipeFilterNotifier extends Notifier<RecipeFilter> {
  @override
  RecipeFilter build() => const RecipeFilter();

  /// Sets the search term.
  void setQuery(String query) => state = state.copyWith(query: query.trim());

  /// Shows only pinned recipes.
  void toggleFavourites() =>
      state = state.copyWith(favouritesOnly: !state.favouritesOnly);

  /// Shows only recipes that can be cooked right now.
  void toggleCookable() =>
      state = state.copyWith(cookableOnly: !state.cookableOnly);

  /// Clears every filter.
  void clear() => state = const RecipeFilter();
}

/// Every recipe, unfiltered.
final allRecipesProvider = StreamProvider<List<Recipe>>(
  (ref) => ref.watch(recipeRepositoryProvider).watchAll(),
);

/// Stock for every item, keyed by id — the engine's input.
///
/// Public because the detail screen and the cook controller read it too. Two private copies would be
/// two subscriptions computing the same map, and could momentarily disagree about the same stock.
final stockByItemProvider = StreamProvider<Map<String, ItemStock>>(
  (ref) => ref
      .watch(itemRepositoryProvider)
      .watchAllStock()
      .map((rows) => {for (final r in rows) r.itemId: r}),
);

/// Every item, keyed by id — the engine needs `unitCategory` to compare units.
final itemsByIdProvider = StreamProvider<Map<String, Item>>(
  (ref) => ref
      .watch(itemRepositoryProvider)
      .watchAll()
      .map((rows) => {for (final r in rows) r.id: r}),
);

/// One row of the catalogue: a recipe and what the engine could say about it.
class RecipeListEntry {
  /// Creates a row.
  const RecipeListEntry({required this.recipe, this.cookability});

  /// The recipe.
  final Recipe recipe;

  /// Its verdict, or null while stock is still loading.
  final Cookability? cookability;
}

/// The catalogue after the active filter, with a verdict per row.
///
/// One pass over the whole list rather than a `family` per row: a virtualised list rebuilds rows
/// constantly, and a per-row provider would judge the same recipe on every scroll frame.
///
/// **Judged without batches, deliberately.** `judge` answers precisely when given an item's batches,
/// and that costs a query per item — across forty recipes it would be the most expensive read in the
/// app for a badge. The list therefore takes the coarse answer, which cannot report expiry, and the
/// detail screen takes the precise one. `judge`'s own documentation states the trade.
final recipeListProvider = Provider<AsyncValue<List<RecipeListEntry>>>((ref) {
  final recipes = ref.watch(allRecipesProvider);
  final stock = ref.watch(stockByItemProvider);
  final items = ref.watch(itemsByIdProvider);
  final filter = ref.watch(recipeFilterProvider);
  // Read once per rebuild rather than per recipe, so every row in one pass is judged against the same
  // date. Forty rows straddling midnight would otherwise disagree with each other.
  final today = ref.watch(clockProvider).today();

  return recipes.whenData((all) {
    final stockMap = stock.valueOrNull;
    final itemMap = items.valueOrNull;
    const engine = CookabilityEngine();

    final entries = <RecipeListEntry>[];
    for (final recipe in all) {
      if (filter.favouritesOnly && !recipe.isFavorite) continue;
      if (filter.query.isNotEmpty &&
          !recipe.normalizedName.contains(filter.query.toLowerCase())) {
        continue;
      }
      final verdict = (stockMap == null || itemMap == null)
          ? null
          : engine.judge(
              recipe,
              stock: stockMap,
              items: itemMap,
              today: today,
            );
      if (filter.cookableOnly && verdict?.isCookable != true) {
        continue;
      }
      entries.add(RecipeListEntry(recipe: recipe, cookability: verdict));
    }
    return entries;
  });
});

/// How many recipes can be cooked right now, for the dashboard tile and the empty state.
final cookableCountProvider = Provider<int?>((ref) {
  final entries = ref.watch(recipeListProvider).valueOrNull;
  if (entries == null) return null;
  return entries.where((e) => e.cookability?.isCookable ?? false).length;
});

/// One recipe's cookability, for a detail screen.
///
/// **Derived rather than stored.** A cached verdict would be wrong the moment a batch is consumed
/// anywhere else in the app, and Law L3 already refuses to store a figure that can be computed.
final cookabilityProvider = Provider.family<Cookability?, String>((
  ref,
  recipeId,
) {
  // Reuses the list's single pass rather than judging again — the list is already watching the
  // same three streams, so a second computation here would be the same arithmetic twice.
  final entries = ref.watch(recipeListProvider).valueOrNull;
  if (entries == null) return null;
  for (final entry in entries) {
    if (entry.recipe.id == recipeId) return entry.cookability;
  }
  return null;
});
