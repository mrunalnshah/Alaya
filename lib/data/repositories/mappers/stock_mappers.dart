import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/converters/money_converter.dart';
import 'package:alaya/data/db/converters/qty_converter.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/domain/repositories/batch_repository.dart';

/// Converts between `ItemRow` and the domain `Item` entity.
///
/// An item is the one inventory row that carries its own `unitCategory`, so unlike every other
/// mapper here it needs no category resolution — it *is* the source every other one resolves
/// against.
extension ItemMapper on ItemRow {
  /// Maps this row to a domain entity.
  Item toEntity() => Item(
    id: id,
    name: name,
    normalizedName: normalizedName,
    unitCategory: unitCategory,
    defaultDisplayUnitCode: defaultDisplayUnitCode,
    itemKind: itemKind,
    isFavorite: isFavorite,
    lowStockThreshold: QtyColumns.readOrNull(lowStockThresholdMilli, unitCategory),
    expiryNotifyDays: expiryNotifyDays,
    notes: notes,
  );
}

/// Builds the companion for [item].
ItemsCompanion itemToCompanion(
    Item item, {
      required int createdAt,
      required int updatedAt,
    }) {
  return ItemsCompanion.insert(
    id: item.id,
    name: item.name,
    normalizedName: item.normalizedName,
    unitCategory: item.unitCategory,
    defaultDisplayUnitCode: item.defaultDisplayUnitCode,
    itemKind: item.itemKind,
    lowStockThresholdMilli: Value(QtyColumns.milliOfNullable(item.lowStockThreshold)),
    expiryNotifyDays: Value(item.expiryNotifyDays),
    notes: Value(item.notes),
    isFavorite: item.isFavorite,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `InventoryBatchRow` and the domain `Batch` entity.
///
/// Requires [category] explicitly: a batch stores `initialQuantityMilli` and
/// `remainingQuantityMilli` as bare integers, and a `Qty` is meaningless without the
/// [UnitCategory] that says whether those milli-units are grams, millilitres or pieces. The
/// category lives on the owning item, never on the batch (`qty_converter.dart` documents why no
/// drift `TypeConverter` can bridge this).
extension BatchMapper on InventoryBatchRow {
  /// Maps this row to a domain entity, using [category] from the owning item.
  Batch toEntity(UnitCategory category) => Batch(
    id: id,
    itemId: itemId,
    initialQuantity: QtyColumns.read(initialQuantityMilli, category),
    remainingQuantity: QtyColumns.read(remainingQuantityMilli, category),
    unitCodeAtPurchase: unitCodeAtPurchase,
    purchasedDateKey: purchasedDateKey,
    origin: origin,
    expiryDateKey: expiryDateKey,
    unitCost: MoneyColumns.readNullable(unitCostMinor, costCurrencyCode),
    sourceTransactionLineId: sourceTransactionLineId,
    storageLocation: storageLocation,
    note: note,
  );
}

/// Builds the companion for [batch].
InventoryBatchesCompanion batchToCompanion(
    Batch batch, {
      required int createdAt,
      required int updatedAt,
    }) {
  return InventoryBatchesCompanion.insert(
    id: batch.id,
    itemId: batch.itemId,
    initialQuantityMilli: QtyColumns.milliOf(batch.initialQuantity),
    remainingQuantityMilli: QtyColumns.milliOf(batch.remainingQuantity),
    unitCodeAtPurchase: batch.unitCodeAtPurchase,
    expiryDateKey: Value(batch.expiryDateKey),
    purchasedDateKey: batch.purchasedDateKey,
    unitCostMinor: Value(MoneyColumns.minorOfNullable(batch.unitCost)),
    costCurrencyCode: Value(MoneyColumns.codeOfNullable(batch.unitCost)),
    sourceTransactionLineId: Value(batch.sourceTransactionLineId),
    origin: batch.origin,
    storageLocation: Value(batch.storageLocation),
    note: Value(batch.note),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `StockMovementRow` and the domain `StockMovement` entity.
///
/// Requires [category] for the same reason [BatchMapper] does. There is deliberately no
/// entity-to-companion direction: `stock_movements` is append-only and the repository builds its
/// companions directly from a consumption plan, so a general reverse mapper would only invite the
/// edit Law L6's exception exists to prevent.
extension StockMovementMapper on StockMovementRow {
  /// Maps this row to a domain entity, using [category] from the owning item.
  StockMovement toEntity(UnitCategory category) => StockMovement(
    id: id,
    batchId: batchId,
    itemId: itemId,
    kind: kind,
    quantity: QtyColumns.read(quantityMilli, category),
    occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(occurredAt, isUtc: true),
    dateKey: dateKey,
    reason: reason,
    note: note,
    linkedTransactionId: linkedTransactionId,
    reversesMovementId: reversesMovementId,
  );
}

/// Converts `ItemStockRow` (from `v_item_stock`) into the domain `ItemStock` entity.
///
/// Needs no external category: the view selects `items.unit_category` directly, so a stock
/// rollup is self-describing.
extension ItemStockMapper on ItemStockRow {
  /// Maps this row to a domain entity.
  ItemStock toEntity() => ItemStock(
    itemId: itemId,
    totalRemaining: QtyColumns.read(totalRemainingMilli, unitCategory),
    batchCount: batchCount,
    isLowStock: isLowStock == 1,
    nearestExpiry: nearestExpiryDateKey,
    lowStockThreshold: QtyColumns.readOrNull(lowStockThresholdMilli, unitCategory),
  );
}

/// Converts `LowStockRow` (from `v_low_stock`) into the domain `ItemStock` entity.
///
/// `v_low_stock` is `v_item_stock` filtered to `is_low_stock = 1` plus a pre-computed shortfall,
/// so every row it yields is low on stock by construction — hence `isLowStock: true` rather than
/// a column read. The shortfall itself is recomputed by [ItemStock.shortfall] from the threshold
/// and remaining quantity rather than carried across, so there is exactly one definition of it.
extension LowStockMapper on LowStockRow {
  /// Maps this row to a domain entity.
  ItemStock toEntity() => ItemStock(
    itemId: itemId,
    totalRemaining: QtyColumns.read(totalRemainingMilli, unitCategory),
    // `v_low_stock` does not select batch_count — a low-stock suggestion needs the shortfall,
    // not how many batches it is spread across. Callers wanting the count read v_item_stock.
    batchCount: 0,
    isLowStock: true,
    nearestExpiry: nearestExpiryDateKey,
    lowStockThreshold: QtyColumns.readOrNull(lowStockThresholdMilli, unitCategory),
  );
}

/// Converts `BatchStockCheckRow` (from `v_batch_stock_check`) into the domain
/// `BatchReconciliation` entity.
///
/// Requires [category] for the same reason [BatchMapper] and [StockMovementMapper] do — all three
/// figures are `Qty`, and `v_batch_stock_check` is batch-centric with no `items` in its `FROM`
/// clause. Adding a join purely to surface `unit_category` would cost a join on a view that scans
/// every batch, when the caller already resolves categories through `ItemCategoryResolver` for the
/// batch and movement rows alongside it.
extension BatchReconciliationMapper on BatchStockCheckRow {
  /// Maps this row to a domain entity, using [category] from the owning item.
  BatchReconciliation toEntity(UnitCategory category) => BatchReconciliation(
    batchId: batchId,
    cached: QtyColumns.read(cachedRemainingMilli, category),
    fromLedger: QtyColumns.read(ledgerRemainingMilli, category),
    discrepancy: QtyColumns.read(discrepancyMilli, category),
  );
}

/// A `Money` total keyed by currency code, accumulated without ever adding across currencies.
///
/// Exists because waste and inventory valuation both sum costs whose currency is per-row
/// (`inventory_batches.cost_currency_code`), and `Money + Money` throws on a mismatch by design
/// (Law L1). Adding rupees to yen is anomaly A34; this makes that impossible rather than merely
/// discouraged.
final class MoneyByCurrency {
  /// Creates an empty accumulator.
  MoneyByCurrency();

  final Map<String, int> _minorByCode = {};

  /// Adds [minor] units of [currencyCode] to the running total.
  void add({required String currencyCode, required int minor}) {
    _minorByCode.update(currencyCode, (existing) => existing + minor, ifAbsent: () => minor);
  }

  /// The accumulated totals, one `Money` per currency encountered.
  Map<String, Money> get totals =>
      {for (final e in _minorByCode.entries) e.key: Money(e.value, e.key)};

  /// True when nothing has been added.
  bool get isEmpty => _minorByCode.isEmpty;
}
