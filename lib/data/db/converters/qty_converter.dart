import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';

/// Composes and decomposes [Qty] from the quantity columns the schema stores it in.
///
/// **This is deliberately not a drift `TypeConverter`**, and for a stronger reason than
/// [MoneyColumns]. A [Qty] needs a [UnitCategory], and no table stores one next to its
/// quantity — the category lives on `items.unit_category` (for anything item-linked) or
/// `units.category` (for a bare unit code). So building a [Qty] requires a **join or a cached
/// unit lookup**, not just two columns of the same row:
///
/// | Quantity column | Category comes from |
/// |---|---|
/// | `transaction_lines.quantity_milli` | `items.unit_category` via `item_id`, else `units.category` via `unit_code` |
/// | `inventory_batches.initial_quantity_milli` / `remaining_quantity_milli` | `items.unit_category` via `item_id` |
/// | `stock_movements.quantity_milli` | `items.unit_category` via `item_id` |
/// | `shopping_entries.quantity_milli` | `items.unit_category` via `item_id`, else `units.category` via `unit_code` |
/// | `items.low_stock_threshold_milli` | `items.unit_category` on the same row |
///
/// The two rows with an "else" are the ones to watch: a `transaction_lines` or
/// `shopping_entries` row may have a quantity and a unit but **no** `item_id` (buying something
/// never catalogued, ARCH_2 §4.2 and §6), in which case the category must come from the unit.
/// A row with a quantity but neither an item nor a unit has no recoverable category at all;
/// [readOrNull] returns `null` for that case rather than inventing one.
///
/// Every quantity column already stores **base-milli units**, never the purchased unit
/// (ARCH_2 §4.2: "Qty base x 1000"). `unit_code` and `unit_code_at_purchase` exist only to
/// render what the user originally typed — `2 kg` rather than `2000 g`. That is why ARCH_3
/// §5.1's queries 10 and 24 need no unit conversion: they aggregate `quantity_milli` directly.
/// Comparisons remain valid only *within* one item, since an item's category is immutable
/// (Law L8) but milli-grams and milli-pieces are not comparable across items.
abstract final class QtyColumns {
  /// Builds [Qty] from a non-null quantity column and a category resolved by the caller.
  static Qty read(int quantityMilli, UnitCategory category) => Qty(quantityMilli, category);

  /// Builds [Qty] when either the quantity or the resolved category may be absent.
  ///
  /// Returns `null` if [quantityMilli] is null (the row simply has no quantity — a `TV ☐`
  /// shopping entry) or if [category] could not be resolved from an item or a unit.
  static Qty? readOrNull(int? quantityMilli, UnitCategory? category) {
    if (quantityMilli == null || category == null) return null;
    return Qty(quantityMilli, category);
  }

  /// The value for the `INTEGER` base-milli quantity column.
  static int milliOf(Qty qty) => qty.milliBase;

  /// The base-milli column value for a nullable [Qty].
  static int? milliOfNullable(Qty? qty) => qty?.milliBase;
}