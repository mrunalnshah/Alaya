import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';

/// One item's derived stock rollup — the summed figure an item row displays.
///
/// Read-only: comes from `v_item_stock`, and no total is stored (Law L3). Batches with nothing
/// left are excluded from every field here, so [batchCount] means "batches still holding stock"
/// and an exhausted batch cannot drag [nearestExpiry] earlier.
class ItemStock {
  /// Creates a stock rollup.
  const ItemStock({
    required this.itemId,
    required this.totalRemaining,
    required this.batchCount,
    required this.isLowStock,
    this.nearestExpiry,
    this.lowStockThreshold,
  });

  /// The item this rollup belongs to.
  final String itemId;

  /// Total quantity still on hand across every batch with stock.
  final Qty totalRemaining;

  /// How many batches still hold stock.
  final int batchCount;

  /// Whether [totalRemaining] has fallen below [lowStockThreshold].
  final bool isLowStock;

  /// The earliest expiry among batches still holding stock, or null if none expire.
  final DateKey? nearestExpiry;

  /// The threshold below which this item counts as low, or null if none is set.
  final Qty? lowStockThreshold;

  /// True when nothing at all is on hand.
  bool get isOutOfStock => totalRemaining.isZero;

  /// How much to buy to reach the threshold, or null when no threshold is set or stock is above
  /// it. The quantity the low-stock suggestion engine puts on a generated shopping entry.
  Qty? get shortfall {
    final threshold = lowStockThreshold;
    if (threshold == null || !isLowStock) return null;
    return threshold - totalRemaining;
  }

  /// True when a batch has already passed its expiry as of [today].
  bool hasExpiredStock(DateKey today) {
    final expiry = nearestExpiry;
    return expiry != null && expiry < today;
  }

  /// Days until the nearest expiry as of [today] — negative once past, null if nothing expires.
  int? daysUntilNearestExpiry(DateKey today) => nearestExpiry?.diffDays(today);

  @override
  bool operator ==(Object other) =>
      other is ItemStock &&
          other.itemId == itemId &&
          other.totalRemaining == totalRemaining &&
          other.batchCount == batchCount &&
          other.isLowStock == isLowStock &&
          other.nearestExpiry == nearestExpiry &&
          other.lowStockThreshold == lowStockThreshold;

  @override
  int get hashCode => Object.hashAll(
      [itemId, totalRemaining, batchCount, isLowStock, nearestExpiry, lowStockThreshold]);

  @override
  String toString() => 'ItemStock($itemId: $totalRemaining across $batchCount batches)';
}