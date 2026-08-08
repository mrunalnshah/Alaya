/// View-model state for the inventory catalogue (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/state/inventory_filter.dart';

/// One section of the catalogue.
class InventoryGroup {
  /// Creates a group.
  const InventoryGroup({
    required this.items,
    this.kind,
    this.isFavourites = false,
  });

  /// The items in it, already sorted by name.
  final List<Item> items;

  /// Which kind this group collects, or null for the favourites group.
  final ItemKind? kind;

  /// Whether this is the favourites group.
  final bool isFavourites;
}

/// The catalogue's current filter.
final inventoryFilterProvider =
    NotifierProvider<InventoryFilterNotifier, InventoryFilter>(
      InventoryFilterNotifier.new,
    );

/// Drives the search field, group-by chips and filter toggles.
class InventoryFilterNotifier extends Notifier<InventoryFilter> {
  @override
  InventoryFilter build() => const InventoryFilter();

  /// Sets the search term.
  void setQuery(String query) => state = state.copyWith(query: query.trim());

  /// Switches the grouping axis.
  void setGroupBy(InventoryGroupBy groupBy) =>
      state = state.copyWith(groupBy: groupBy);

  /// Shows only starred items.
  void toggleFavouritesOnly() =>
      state = state.copyWith(favouritesOnly: !state.favouritesOnly);

  /// Shows only items below their low-stock level.
  void toggleLowStockOnly() =>
      state = state.copyWith(lowStockOnly: !state.lowStockOnly);

  /// Adds or removes a kind.
  void toggleKind(ItemKind kind) {
    final next = {...state.kinds};
    if (next.contains(kind)) {
      next.remove(kind);
    } else {
      next.add(kind);
    }
    state = state.copyWith(kinds: next);
  }

  /// Clears everything back to the full catalogue.
  void clear() => state = InventoryFilter(query: state.query);
}

/// Every item in the catalogue.
final itemsProvider = StreamProvider<List<Item>>(
  (ref) => ref.watch(itemRepositoryProvider).watchAll(),
);

/// Stock on hand for every item, keyed by item id.
///
/// `ItemStock.totalRemaining` is the summed mixed-unit figure the row shows — the sum lives in the
/// domain rather than being re-added in the widget, which is what keeps ARCH_1 §5.4's arithmetic in
/// one place instead of two.
final itemStocksProvider = StreamProvider<Map<String, ItemStock>>(
  (ref) => ref
      .watch(itemRepositoryProvider)
      .watchAllStock()
      .map(
        (stocks) => {for (final stock in stocks) stock.itemId: stock},
      ),
);

/// Every unit, keyed by code, so a row can name the unit a quantity is shown in.
final unitsByCodeProvider = StreamProvider<Map<String, Unit>>(
  (ref) => ref
      .watch(unitRepositoryProvider)
      .watchAll()
      .map(
        (units) => {for (final unit in units) unit.code: unit},
      ),
);

/// The catalogue, filtered, searched and grouped.
///
/// A `Provider` over the two streams rather than a third stream: grouping is pure, and doing it here
/// means the screen watches one thing and gets all four states from it.
final inventoryGroupsProvider = Provider<AsyncValue<List<InventoryGroup>>>((
  ref,
) {
  final items = ref.watch(itemsProvider);
  final stocks = ref.watch(itemStocksProvider);
  final filter = ref.watch(inventoryFilterProvider);

  if (items.hasError) return AsyncValue.error(items.error!, items.stackTrace!);
  if (stocks.hasError)
    return AsyncValue.error(stocks.error!, stocks.stackTrace!);
  final all = items.valueOrNull;
  final byId = stocks.valueOrNull;
  if (all == null || byId == null) return const AsyncValue.loading();

  final term = filter.query.toLowerCase();
  final visible = [
    for (final item in all)
      if (_admits(item, byId[item.id], filter, term)) item,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  if (filter.groupBy == InventoryGroupBy.favourite) {
    final starred = [
      for (final item in visible)
        if (item.isFavorite) item,
    ];
    final rest = [
      for (final item in visible)
        if (!item.isFavorite) item,
    ];
    return AsyncValue.data([
      if (starred.isNotEmpty)
        InventoryGroup(items: starred, isFavourites: true),
      if (rest.isNotEmpty) InventoryGroup(items: rest),
    ]);
  }

  final buckets = <ItemKind, List<Item>>{};
  for (final item in visible) {
    buckets.putIfAbsent(item.itemKind, () => <Item>[]).add(item);
  }
  return AsyncValue.data([
    for (final kind in ItemKind.values)
      if (buckets[kind] != null)
        InventoryGroup(items: buckets[kind]!, kind: kind),
  ]);
});

/// How many items are below their low-stock level, for the filter chip's count.
final lowStockCountProvider = Provider<int>((ref) {
  final stocks = ref.watch(itemStocksProvider).valueOrNull;
  if (stocks == null) return 0;
  return stocks.values.where((stock) => stock.isLowStock).length;
});

bool _admits(Item item, ItemStock? stock, InventoryFilter filter, String term) {
  if (filter.favouritesOnly && !item.isFavorite) return false;
  if (filter.lowStockOnly && !(stock?.isLowStock ?? false)) return false;
  if (filter.kinds.isNotEmpty && !filter.kinds.contains(item.itemKind))
    return false;
  if (term.isEmpty) return true;
  return item.normalizedName.contains(term) ||
      item.name.toLowerCase().contains(term);
}
