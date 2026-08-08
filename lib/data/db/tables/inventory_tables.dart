import 'package:drift/drift.dart';

import 'package:alaya/data/db/converters/date_key_converter.dart';
import 'package:alaya/data/db/converters/enum_converters.dart';
import 'package:alaya/data/db/tables/meta_tables.dart';
import 'package:alaya/data/db/tables/money_tables.dart';

/// The *kind* of consumable thing, as opposed to one acquisition of it (ARCH_1 §3.2).
///
/// Identity is `(normalizedName, unitCategory)`, enforced by the partial unique index in
/// Phase 1C: same category means the same item and a new batch, a different category means a
/// genuinely different item shown as `Milk (Volume)` / `Milk (Weight)` (anomaly A06).
@DataClassName('ItemRow')
class Items extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Display name as the user typed it.
  TextColumn get name => text()();

  /// Normalised form used for identity matching only, never displayed. Exact matches merge;
  /// near matches are only ever *suggested* (anomaly A07).
  TextColumn get normalizedName => text()();

  /// Which of the three fixed categories this item is measured in. **Immutable after creation**
  /// (Law L8) — rejected on update in the repository, since changing it would silently
  /// reinterpret every quantity ever recorded against the item.
  TextColumn get unitCategory => text().map(const UnitCategoryConverter())();

  /// The unit this item's quantities are rendered in by default.
  TextColumn get defaultDisplayUnitCode => text().references(Units, #code)();

  /// Rough classification. `medicine` is what makes medicine expiry appear on the calendar with
  /// no extra table (ARCH_3 §6).
  TextColumn get itemKind => text().map(const ItemKindConverter())();

  /// Below this total remaining quantity the item is low on stock and the suggestion engine may
  /// generate a shopping entry. In base-milli units. Null means no threshold set.
  IntColumn get lowStockThresholdMilli => integer().nullable()();

  /// How many days before a batch's expiry to remind. Null falls back to the global setting.
  IntColumn get expiryNotifyDays => integer().nullable()();

  /// Optional free-text notes. Indexed for full-text search in Phase 1C.
  TextColumn get notes => text().nullable()();

  /// Pinned to the top of the inventory list.
  BoolColumn get isFavorite => boolean()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One acquisition of an [Items] row: a quantity, an expiry, a cost and a source
/// (ARCH_1 §3.2). Every stock operation acts on batches; the item row only sums them.
@DataClassName('InventoryBatchRow')
class InventoryBatches extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// The item this batch is an acquisition of.
  TextColumn get itemId => text().references(Items, #id)();

  /// Quantity acquired, in base-milli units.
  IntColumn get initialQuantityMilli => integer()();

  /// Quantity still on hand, in base-milli units.
  ///
  /// **The schema's only stored total, and the sole exception to Law L3.** It is a cache,
  /// reconstructible at any time by summing this batch's [StockMovements] — Phase 1C's
  /// `v_batch_stock_check` is the reconciliation probe and Phase 2B's `recomputeRemaining` is
  /// the repair path. Every write that changes it must insert the matching movement row in the
  /// same transaction (Law L14).
  IntColumn get remainingQuantityMilli => integer()();

  /// The unit the user actually purchased in, kept for display fidelity only.
  TextColumn get unitCodeAtPurchase => text().references(Units, #code)();

  /// Civil expiry date. Null means this batch does not expire, which also excludes it from FEFO
  /// ordering until the dated batches are exhausted (anomaly A08).
  IntColumn get expiryDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// Civil date acquired.
  IntColumn get purchasedDateKey => integer().map(const DateKeyConverter())();

  /// Cost per [unitCodeAtPurchase], in minor units. Paired with [costCurrencyCode]; the two are
  /// composed into a `Money` by `MoneyColumns`, never separately.
  IntColumn get unitCostMinor => integer().nullable()();

  /// Currency of [unitCostMinor].
  TextColumn get costCurrencyCode => text().nullable().references(Currencies, #code)();

  /// The transaction line that created this batch, if it came from a purchase. Nulled rather
  /// than cascaded when that transaction is deleted (anomaly A10).
  TextColumn get sourceTransactionLineId =>
      text().nullable().references(TransactionLines, #id)();

  /// Where this batch came from. Becomes `detached` when its source transaction is deleted —
  /// the food does not un-exist because the receipt did.
  TextColumn get origin => text().map(const BatchOriginConverter())();

  /// Optional free-text location, e.g. `Top shelf`.
  TextColumn get storageLocation => text().nullable()();

  /// Optional free-text note.
  TextColumn get note => text().nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// An immutable event changing a batch's remaining quantity — the second of the app's three
/// append-only truths (ARCH_1 §3.3).
///
/// **Explicit exception to Law L6: this table has no `deletedAt`.** Corrections insert a
/// *reversing* row pointing at the original through [reversesMovementId]. A ledger you can edit
/// is not a ledger: undo in the UI writes a reversal, so the user sees "removed", the audit
/// trail survives, and the food-waste analytics in ARCH_3 §5.1 query 14 stay honest.
@DataClassName('StockMovementRow')
class StockMovements extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// The batch this movement applies to.
  TextColumn get batchId => text().references(InventoryBatches, #id)();

  /// The owning item, denormalised from the batch purely so per-item analytics never need the
  /// join (ARCH_2 §5.3).
  TextColumn get itemId => text().references(Items, #id)();

  /// What kind of event this was. [quantityMilli] is always positive; this column carries the
  /// direction.
  TextColumn get kind => text().map(const StockMovementKindConverter())();

  /// Quantity moved, in base-milli units, always positive.
  IntColumn get quantityMilli => integer()();

  /// When it happened, epoch millis UTC.
  IntColumn get occurredAt => integer()();

  /// The local civil date it happened on.
  IntColumn get dateKey => integer().map(const DateKeyConverter())();

  /// Optional structured reason, e.g. why something was wasted.
  TextColumn get reason => text().nullable()();

  /// Optional free-text note.
  TextColumn get note => text().nullable()();

  /// The transaction that caused this movement, for purchase-driven stock increases.
  TextColumn get linkedTransactionId => text().nullable().references(Transactions, #id)();

  /// The movement this row reverses. Non-null exactly on correction rows.
  TextColumn get reversesMovementId => text().nullable().references(StockMovements, #id)();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC. Present for uniformity with ARCH_2 §2; an
  /// append-only row is never updated in practice.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    // Beyond ARCH_2's literal spec, which states this invariant in prose only
    // ("always > 0"). Declared here because Law L3 makes every derived stock figure depend
    // on it: a zero or negative row would corrupt both `recomputeRemaining` and the waste
    // analytics, and neither would report an error. See the deviation note in the phase
    // report.
    'CHECK (quantity_milli > 0)',
  ];
}