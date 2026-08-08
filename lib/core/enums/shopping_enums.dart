/// How a [ShoppingEntry] came to exist, which decides whether it can be silently
/// regenerated/removed by the low-stock suggestion engine.
enum ShoppingEntryOrigin {
  /// Added directly by the user.
  manual,

  /// Generated automatically because an Item fell below its low-stock threshold. Editing
  /// such an entry promotes it to [manual] so it is never auto-removed afterwards.
  autoLowStock,

  /// Generated from a Recurring Template (e.g. a subscription that needs a physical item).
  fromRecurring,
}

/// The lifecycle state of an auto-generated [ShoppingEntry], letting a user dismiss a
/// suggestion without it reappearing on the very next regeneration.
enum ShoppingEntryAutoState {
  /// Currently shown to the user as a live suggestion.
  active,

  /// Hidden until the stock condition that generated it re-triggers after first clearing.
  snoozed,

  /// Permanently dismissed by the user for this occurrence of the low-stock condition.
  dismissed,
}