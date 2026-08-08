import 'package:alaya/core/money/money.dart';
import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/converters/money_converter.dart';
import 'package:alaya/data/db/converters/qty_converter.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';

/// Converts between `ShoppingListRow` and the domain `ShoppingList` entity.
extension ShoppingListMapper on ShoppingListRow {
  /// Maps this row to a domain entity.
  ShoppingList toEntity() => ShoppingList(
    id: id,
    name: name,
    isDefault: isDefault,
    isArchived: isArchived,
    targetDateKey: targetDateKey,
  );
}

/// Builds the companion for [list].
ShoppingListsCompanion shoppingListToCompanion(
  ShoppingList list, {
  required int createdAt,
  required int updatedAt,
}) {
  return ShoppingListsCompanion.insert(
    id: list.id,
    name: list.name,
    isDefault: list.isDefault,
    isArchived: list.isArchived,
    targetDateKey: Value(list.targetDateKey),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `ShoppingEntryRow` and the domain `ShoppingEntry` entity.
///
/// [category] is **nullable** here, unlike the batch and movement mappers. A shopping entry may
/// name no item at all — `TV ☐` is a legitimate entry with nothing in the catalogue behind it
/// (anomaly A24) — so there is often no item whose `unitCategory` could be resolved. A null
/// category yields a null `quantity`, which is also the honest outcome for a free-text entry
/// nobody has attached a measurable amount to.
///
/// [homeCurrencyCode] must be supplied because `shopping_entries` carries no currency column
/// (ARCH_2 §6). An estimated price is a guess typed before any transaction exists, so there is no
/// parent row to inherit a currency from the way a `transaction_lines` amount inherits its
/// transaction's. Passing it in rather than assuming one keeps Law L1's pairing honest — a
/// hardcoded default would label a yen estimate as rupees for every user outside India.
extension ShoppingEntryMapper on ShoppingEntryRow {
  /// Maps this row to a domain entity, using [category] from the linked item when there is one.
  ShoppingEntry toEntity({
    required UnitCategory? category,
    required String homeCurrencyCode,
  }) => ShoppingEntry(
    id: id,
    listId: listId,
    origin: origin,
    autoState: autoState,
    isChecked: isChecked,
    sortOrder: sortOrder,
    itemId: itemId,
    freeText: freeText,
    quantity: QtyColumns.readOrNull(quantityMilli, category),
    unitCode: unitCode,
    tagId: tagId,
    // **Not `readNullable`.** That helper enforces a pairing invariant for tables storing an
    // amount *and* its currency, and throws on a half-populated pair. `shopping_entries` stores
    // only `estimated_price_minor`; the currency comes from settings and is therefore always
    // present, so every entry without a price — which is every auto-generated suggestion —
    // arrived as `(null, 'INR')` and threw. The nullability here belongs to the amount alone.
    estimatedPrice: estimatedPriceMinor == null
        ? null
        : Money(estimatedPriceMinor!, homeCurrencyCode),
    checkedAtUtc: checkedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(checkedAt!, isUtc: true),
    snoozeUntilDateKey: snoozeUntilDateKey,
    stockAtGeneration: QtyColumns.readOrNull(generatedAtStockMilli, category),
    purchasedTransactionLineId: purchasedTransactionLineId,
  );
}

/// Builds the companion for [entry].
ShoppingEntriesCompanion shoppingEntryToCompanion(
  ShoppingEntry entry, {
  required int createdAt,
  required int updatedAt,
}) {
  return ShoppingEntriesCompanion.insert(
    id: entry.id,
    listId: entry.listId,
    itemId: Value(entry.itemId),
    freeText: Value(entry.freeText),
    quantityMilli: Value(QtyColumns.milliOfNullable(entry.quantity)),
    unitCode: Value(entry.unitCode),
    tagId: Value(entry.tagId),
    estimatedPriceMinor: Value(
      MoneyColumns.minorOfNullable(entry.estimatedPrice),
    ),
    isChecked: entry.isChecked,
    checkedAt: Value(entry.checkedAtUtc?.millisecondsSinceEpoch),
    origin: entry.origin,
    autoState: entry.autoState,
    snoozeUntilDateKey: Value(entry.snoozeUntilDateKey),
    generatedAtStockMilli: Value(
      QtyColumns.milliOfNullable(entry.stockAtGeneration),
    ),
    purchasedTransactionLineId: Value(entry.purchasedTransactionLineId),
    sortOrder: entry.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
