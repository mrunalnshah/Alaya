import 'package:drift/drift.dart';

import 'package:alaya/data/db/converters/date_key_converter.dart';
import 'package:alaya/data/db/converters/enum_converters.dart';
import 'package:alaya/data/db/tables/inventory_tables.dart';
import 'package:alaya/data/db/tables/meta_tables.dart';
import 'package:alaya/data/db/tables/money_tables.dart';
import 'package:alaya/data/db/tables/tag_tables.dart';

/// A shopping list. Multiple lists are supported, with one marked default so the app still
/// feels like it has just one (ARCH_4 open decision 5).
@DataClassName('ShoppingListRow')
class ShoppingLists extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Display name.
  TextColumn get name => text()();

  /// The list quick-add writes to when the user does not choose one.
  BoolColumn get isDefault => boolean()();

  /// Retired but kept for history.
  BoolColumn get isArchived => boolean()();

  /// Optional civil date the user intends to shop on; surfaces on the calendar.
  IntColumn get targetDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// An intent to buy something. May or may not link to a catalogued [Items] row.
///
/// [origin], [autoState] and [generatedAtStockMilli] together are what make low-stock
/// auto-generation idempotent *and* dismissible without the entry reappearing on the next run
/// (anomalies A22 and A23) — the hardest behaviour in the shopping module to get right, and it
/// is carried entirely by these three columns plus Phase 1C's partial unique index.
@DataClassName('ShoppingEntryRow')
class ShoppingEntries extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// The list this entry belongs to.
  TextColumn get listId => text().references(ShoppingLists, #id)();

  /// The catalogued item, when this entry refers to one. Nullable so `TV ☐` works without
  /// inventing an inventory item (anomaly A24).
  TextColumn get itemId => text().nullable().references(Items, #id)();

  /// What to buy, when there is no [itemId].
  TextColumn get freeText => text().nullable()();

  /// How much to buy, in base-milli units. Null renders as no quantity at all rather than `0`.
  IntColumn get quantityMilli => integer().nullable()();

  /// The unit the user typed, for display.
  TextColumn get unitCode => text().nullable().references(Units, #code)();

  /// The group header this entry appears under — `Grocery`, `Beauty`, `Electronics`. A direct
  /// column rather than a join table, because unlike the other modules an entry belongs to
  /// exactly one group (ARCH_2 §6).
  TextColumn get tagId => text().nullable().references(Tags, #id)();

  /// Optional expected price in minor units, for the running list estimate.
  IntColumn get estimatedPriceMinor => integer().nullable()();

  /// Ticked off in the list.
  BoolColumn get isChecked => boolean()();

  /// When it was ticked, epoch millis UTC.
  IntColumn get checkedAt => integer().nullable()();

  /// How this entry came to exist. Editing an `autoLowStock` entry promotes it to `manual`,
  /// after which the suggestion engine never removes it.
  TextColumn get origin => text().map(const ShoppingEntryOriginConverter())();

  /// Lifecycle of an auto-generated entry, so a dismissal survives the next regeneration.
  TextColumn get autoState => text().map(const ShoppingEntryAutoStateConverter())();

  /// Hide an auto entry until this civil date.
  IntColumn get snoozeUntilDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// The item's total remaining stock at the moment this entry was auto-generated, in
  /// base-milli units. The comparison point that stops a dismissed suggestion from returning
  /// until stock has genuinely risen above the threshold and fallen again.
  IntColumn get generatedAtStockMilli => integer().nullable()();

  /// The transaction line that fulfilled this entry, set by convert-to-purchase (anomaly A25).
  TextColumn get purchasedTransactionLineId =>
      text().nullable().references(TransactionLines, #id)();

  /// Manual ordering within its group.
  IntColumn get sortOrder => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}