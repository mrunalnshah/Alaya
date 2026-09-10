/// Inventory enumerations.
///
/// **`ItemKind` used to live here and is now a row in `tags`.**
///
/// It was six members — generic, food, medicine, beauty, household, other — and a user who wanted
/// `Vegetables` separated from `Cereals` had no way to say so. An enum is a decision made at compile time, and
/// this one belonged to whoever is using the app.
///
/// The replacement is `items.kind_tag_id` referencing `tags`, scoped by `tags.allowed_in_inventory`. That
/// reuses a taxonomy the schema already had — a name, a colour, an icon, a sort order and `is_system` — rather
/// than adding a second one beside it. It is the call the split module made when it reused `payees` instead of
/// creating a `people` table.
///
/// **A column rather than an `item_tags` link, and the reason is `inventoryGroupsProvider`.** That provider
/// buckets every visible item synchronously, in memory, reading the kind off the row it already has. A link
/// would have needed a kind *per item* — two hundred `watchForItem` streams, or a bulk read that does not
/// exist. A link table is right for "many, looked up when I open one thing"; it is wrong for "one, needed for
/// all of them at once to draw a list."
///
/// Three things came free: renaming a kind updates every item at once, group order became `tags.sort_order`
/// rather than an enum's declaration order, and the six built-ins are protected by `tags.is_system` with no
/// new code.
///
/// **What did *not* come free** — the glyph. `ItemKind` mapped to an `IconData` in a `switch`;
/// `tags.icon_key` is a string with no reader anywhere in the app yet. Session 2 needs a registry for it.
library;

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
