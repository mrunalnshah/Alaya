import 'package:drift/drift.dart';

import 'package:alaya/data/db/tables/inventory_tables.dart';
import 'package:alaya/data/db/tables/money_tables.dart';
import 'package:alaya/data/db/tables/service_tables.dart';

/// The single tag table, scoped per module by the six `allowedIn*` flags (ARCH_2 §3).
///
/// One table as the spec requires, but linked through separate join tables per entity rather
/// than a polymorphic owner column — that is anomaly A35's resolution: real foreign keys with
/// real integrity, which codegen makes free.
@DataClassName('TagRow')
class Tags extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Display name as the user typed it.
  TextColumn get name => text()();

  /// Normalised form used for identity matching only, never displayed
  /// (Phase 1A `Normalizer`).
  TextColumn get normalizedName => text()();

  /// Optional ARGB colour for the chip.
  IntColumn get colorArgb => integer().nullable()();

  /// Optional icon identifier.
  TextColumn get iconKey => text().nullable()();

  /// Parent tag, permitting exactly **one** level of nesting (`Grocery > Vegetables`). Depth is
  /// capped in the repository, not here. This single column is what makes drill-down analytics
  /// possible (ARCH_2 §3).
  TextColumn get parentTagId => text().nullable().references(Tags, #id)();

  /// Offered in the deposit tag picker.
  BoolColumn get allowedInDeposit => boolean()();

  /// Offered in the withdrawal tag picker.
  BoolColumn get allowedInWithdrawal => boolean()();

  /// Offered in the inventory tag picker.
  BoolColumn get allowedInInventory => boolean()();

  /// Offered in the shopping tag picker, where it also acts as the group header.
  BoolColumn get allowedInShopping => boolean()();

  /// Offered in the recurring tag picker.
  BoolColumn get allowedInRecurring => boolean()();

  /// Offered in the service tag picker.
  BoolColumn get allowedInService => boolean()();

  /// Whether this tag was seeded; system tags cannot be deleted (ARCH_3 §4.1).
  BoolColumn get isSystem => boolean()();

  /// Manual ordering within pickers.
  IntColumn get sortOrder => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active — a deleted tag keeps its links
  /// so history stays readable (anomaly A36).
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Links a transaction to a tag. Composite primary key, no UUID, no soft delete (ARCH_2 §4).
@DataClassName('TransactionTagRow')
class TransactionTags extends Table {
  /// The tagged transaction.
  TextColumn get transactionId => text().references(Transactions, #id)();

  /// The applied tag.
  TextColumn get tagId => text().references(Tags, #id)();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC. Retained for uniformity with ARCH_2 §2's
  /// common columns; a link row is only ever inserted or removed, so merge-restore reconciles
  /// these tables with `INSERT OR IGNORE` rather than the `updatedAt` comparison used elsewhere
  /// (ARCH_3 §3.2).
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {transactionId, tagId};
}

/// Links an inventory item to a tag. Composite primary key, no UUID, no soft delete.
@DataClassName('ItemTagRow')
class ItemTags extends Table {
  /// The tagged item.
  TextColumn get itemId => text().references(Items, #id)();

  /// The applied tag.
  TextColumn get tagId => text().references(Tags, #id)();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {itemId, tagId};
}

/// Links a service-manager asset to a tag. Composite primary key, no UUID, no soft delete.
@DataClassName('AssetTagRow')
class AssetTags extends Table {
  /// The tagged asset.
  TextColumn get assetId => text().references(Assets, #id)();

  /// The applied tag.
  TextColumn get tagId => text().references(Tags, #id)();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {assetId, tagId};
}