/// A rough classification of what kind of consumable an Item is, independent of its
/// [UnitCategory]. Drives a few UI defaults (e.g. medicine expiry surfacing on the
/// calendar) — see ARCH_2 §5.1.
enum ItemKind {
  /// No more specific classification applies.
  generic,

  /// Food and groceries.
  food,

  /// Medicines and health-related consumables.
  medicine,

  /// Beauty and personal-care products.
  beauty,

  /// Household and cleaning supplies.
  household,

  /// Anything not covered by the above.
  other,
}

/// Where an Inventory Batch came from.
enum BatchOrigin {
  /// Created by a withdrawal's line item.
  purchase,

  /// Added directly by the user, with no linked transaction.
  manual,

  /// Brought in from an external source (e.g. a data import or migration). Named `imported`
  /// rather than `import` — the latter is a reserved word in Dart and cannot be an enum
  /// member name, so this is a deliberate, one-value deviation from ARCH_2's literal text.
  imported,

  /// Created by a stock-correction/adjustment action.
  adjustment,

  /// Its source transaction was deleted; the batch survives on its own (see ARCH_3 §4.1 —
  /// deleting a receipt must never delete food already eaten).
  detached,
}

/// One kind of event in the append-only `stock_movements` ledger (Law L3/L6 exception: this
/// table has no soft delete — see ARCH_2 §5.3). [quantityMilli] is always positive; this
/// value carries the direction.
enum StockMovementKind {
  /// The opening stock recorded when an Item is first created with existing quantity.
  openingIn,

  /// Stock added by a withdrawal's line item.
  purchaseIn,

  /// Stock added manually by the user.
  manualIn,

  /// Stock used up through normal use.
  consume,

  /// Stock discarded as spoiled/expired before use.
  waste,

  /// Stock that reached its expiry date without being consumed or explicitly wasted.
  expired,

  /// A manual correction that increases the recorded stock.
  adjustIn,

  /// A manual correction that decreases the recorded stock.
  adjustOut,
}