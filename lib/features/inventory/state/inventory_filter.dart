import 'package:alaya/core/enums/inventory_enums.dart';

/// The axis the catalogue groups by.
enum InventoryGroupBy {
  /// By `items.itemKind` — food, medicine, household.
  kind,

  /// Favourites first, everything else after.
  favourite,
}

/// What the inventory list is currently showing.
///
/// **Grouping is by `itemKind`, not by tag.** Archetype D asks for "the user's own axis — tag for
/// items", and `item_tags` is assigned to this phase in ARCH_5 §7.1 — but no contract in Phase 3A
/// reads or writes an item's tags. `TagRepository` exposes `watchForTransaction` and nothing
/// equivalent for items, and U19 forbids a feature declaring its own repository. `itemKind` is the
/// nearest axis that exists, is set by the user in the editor, and needs no new contract. The tag
/// axis is recorded as a deferral in the coverage table with the contract it waits on.
class InventoryFilter {
  /// Creates a filter.
  const InventoryFilter({
    this.groupBy = InventoryGroupBy.kind,
    this.favouritesOnly = false,
    this.lowStockOnly = false,
    this.kinds = const <ItemKind>{},
    this.query = '',
  });

  /// The grouping axis.
  final InventoryGroupBy groupBy;

  /// Whether only starred items are shown.
  final bool favouritesOnly;

  /// Whether only items below their low-stock level are shown.
  final bool lowStockOnly;

  /// Which kinds are shown; empty means all.
  final Set<ItemKind> kinds;

  /// The search term, already trimmed.
  final String query;

  /// Whether anything narrows the full catalogue.
  bool get isNarrowed =>
      favouritesOnly ||
      lowStockOnly ||
      kinds.isNotEmpty ||
      groupBy != InventoryGroupBy.kind;

  /// Whether a search is running.
  bool get isSearching => query.isNotEmpty;

  /// Returns a copy with the supplied changes.
  InventoryFilter copyWith({
    InventoryGroupBy? groupBy,
    bool? favouritesOnly,
    bool? lowStockOnly,
    Set<ItemKind>? kinds,
    String? query,
  }) => InventoryFilter(
    groupBy: groupBy ?? this.groupBy,
    favouritesOnly: favouritesOnly ?? this.favouritesOnly,
    lowStockOnly: lowStockOnly ?? this.lowStockOnly,
    kinds: kinds ?? this.kinds,
    query: query ?? this.query,
  );
}
