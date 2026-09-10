/// View-model state for the inventory catalogue (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/tag.dart';
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

  /// Which kind this group collects, or null for the favourites group and for items whose kind is missing.
  ///
  /// **The `Tag` itself, not its id.** A group has to render a name, and with a colour and an `iconKey` on the
  /// same row it can render those too once something reads them. Passing an id would make every screen repeat
  /// the same lookup — which is how two screens come to disagree about what a kind is called.
  final Tag? kind;

  /// Whether this is the favourites group.
  final bool isFavourites;
}

/// The kinds an item can be filed under, in the order the user arranged them.
///
/// **`watchByScope`, so a `Rent` tag never appears as an inventory kind.** Scoping is what lets one `tags`
/// table serve six pickers — ARCH_2 §14 — and it is why kinds needed no table of their own.
///
/// Nine of these are seeded: Food, Grocery, Vegetables, Kitchen, Household, Beauty, Medicine, Electronics and
/// Other. The rest are the user's.
final inventoryKindsProvider = StreamProvider<List<Tag>>(
  (ref) => ref.watch(tagRepositoryProvider).watchByScope(TagScope.inventory),
);

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

  /// Adds or removes a kind from the filter, by tag id.
  void toggleKind(String kindTagId) {
    final next = {...state.kinds};
    if (next.contains(kindTagId)) {
      next.remove(kindTagId);
    } else {
      next.add(kindTagId);
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
  final kindsAsync = ref.watch(inventoryKindsProvider);

  if (items.hasError) return AsyncValue.error(items.error!, items.stackTrace!);
  if (kindsAsync.hasError) {
    return AsyncValue.error(kindsAsync.error!, kindsAsync.stackTrace!);
  }
  if (stocks.hasError)
    return AsyncValue.error(stocks.error!, stocks.stackTrace!);
  final all = items.valueOrNull;
  final stockById = stocks.valueOrNull;
  final kinds = kindsAsync.valueOrNull;
  if (all == null || stockById == null || kinds == null) {
    return const AsyncValue.loading();
  }

  final term = filter.query.toLowerCase();
  final visible = [
    for (final item in all)
      if (_admits(item, stockById[item.id], filter, term)) item,
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

  // **Group order comes from `tags.sort_order` now, not from an enum's declaration order.** It used to be
  // `for (final kind in ItemKind.values)` — the order sections appeared in was whatever order somebody had
  // typed the members. It is user-owned state, reorderable in Settings, and that arrived free with the move.
  final byId = {for (final kind in kinds) kind.id: kind};

  final buckets = <String?, List<Item>>{};
  for (final item in visible) {
    // **An id the scoped list does not contain buckets as null**, rather than creating a phantom group. That
    // happens when a kind was deleted without the Settings fallback running, or when its inventory scope was
    // turned off while items still pointed at it — and an item that renders nowhere is worse than one that
    // renders under a heading admitting it has no kind.
    final id = byId.containsKey(item.kindTagId) ? item.kindTagId : null;
    buckets.putIfAbsent(id, () => <Item>[]).add(item);
  }

  return AsyncValue.data([
    for (final kind in kinds)
      if (buckets[kind.id] != null)
        InventoryGroup(items: buckets[kind.id]!, kind: kind),
    // Unfiled last, and only when it has something in it. `kind: null` here means "no kind", which the
    // favourites group also uses — the screen tells them apart by `isFavourites`.
    if (buckets[null] != null) InventoryGroup(items: buckets[null]!),
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
  if (filter.kinds.isNotEmpty && !filter.kinds.contains(item.kindTagId))
    return false;
  if (term.isEmpty) return true;
  return item.normalizedName.contains(term) ||
      item.name.toLowerCase().contains(term);
}
