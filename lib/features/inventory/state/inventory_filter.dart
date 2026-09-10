/// The axis the catalogue groups by.
enum InventoryGroupBy {
  /// By `items.kindTagId` — whatever kinds the user has.
  kind,

  /// Favourites first, everything else after.
  favourite,
}

/// What the inventory list is currently showing.
///
/// **Grouping is by the user's own kinds, which is the deferral this pays off.** The note that used to sit
/// here said `itemKind` was "the nearest axis that exists" because `TagRepository` had no equivalent of
/// `watchForTransaction` for items, so Archetype D's "the user's own axis — tag for items" had to wait on a
/// contract nobody had written.
///
/// That contract arrived — `watchForItem` and `setForItem` are on `TagRepository` and implemented — and the
/// note went stale without anybody noticing, which is why a six-member enum outlived its reason. v5 finished
/// the job differently than the old note predicted: a kind is `items.kind_tag_id`, one column referencing
/// `tags`, rather than a row in `item_tags`.
///
/// **The column, because this filter's own provider decides it.** `inventoryGroupsProvider` buckets every
/// visible item synchronously off the row it already holds. A link would have needed a kind per item.
///
/// [kinds] holds tag ids. It was already a `Set` before any of this — filtering has always been
/// multi-select, and only grouping and the editor were ever single-valued.
class InventoryFilter {
  /// Creates a filter.
  const InventoryFilter({
    this.groupBy = InventoryGroupBy.kind,
    this.favouritesOnly = false,
    this.lowStockOnly = false,
    this.kinds = const <String>{},
    this.query = '',
  });

  /// The grouping axis.
  final InventoryGroupBy groupBy;

  /// Whether only starred items are shown.
  final bool favouritesOnly;

  /// Whether only items below their low-stock level are shown.
  final bool lowStockOnly;

  /// Which kinds are shown; empty means all. Tag ids.
  final Set<String> kinds;

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
    Set<String>? kinds,
    String? query,
  }) => InventoryFilter(
    groupBy: groupBy ?? this.groupBy,
    favouritesOnly: favouritesOnly ?? this.favouritesOnly,
    lowStockOnly: lowStockOnly ?? this.lowStockOnly,
    kinds: kinds ?? this.kinds,
    query: query ?? this.query,
  );
}
