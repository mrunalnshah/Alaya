/// Which module's tag picker a query is asking about, mapping one-to-one onto the six
/// `allowedIn*` columns on `tags` (ARCH_2 §3).
///
/// Lives in `core/` rather than beside the tag DAO deliberately. Phase 3B's abstract
/// `TagRepository` needs this vocabulary too, and Law L12 forbids `domain/` importing anything
/// from `data/` — so a scope type defined next to the DAO would either force an L12 violation or
/// a duplicated enum with a mapping function between the two. `core/` is the one layer both sides
/// may import.
enum TagScope {
  /// The deposit editor's tag picker.
  deposit,

  /// The withdrawal editor's tag picker.
  withdrawal,

  /// The inventory item editor's tag picker.
  inventory,

  /// The shopping list's group headers.
  shopping,

  /// The recurring template editor's tag picker.
  recurring,

  /// The service manager's tag picker.
  service,
}