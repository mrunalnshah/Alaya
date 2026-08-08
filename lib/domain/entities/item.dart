import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';

/// The *kind* of consumable thing, as opposed to one acquisition of it.
///
/// Identity is `(normalizedName, unitCategory)` together — so `Milk (Weight)` and `Milk (Volume)`
/// are genuinely different items, not a naming collision (anomaly A06).
class Item {
  /// Creates an item.
  const Item({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.unitCategory,
    required this.defaultDisplayUnitCode,
    required this.itemKind,
    required this.isFavorite,
    this.lowStockThreshold,
    this.expiryNotifyDays,
    this.notes,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// Display name as the user typed it.
  final String name;

  /// Normalised form used for identity matching only, never displayed. Exact matches merge; near
  /// matches are only ever *suggested* (anomaly A07).
  final String normalizedName;

  /// Which of the three fixed categories this item is measured in.
  ///
  /// **Immutable after creation** (Law L8). Changing it would silently reinterpret every quantity
  /// ever recorded against the item, so the repository rejects an update that alters it.
  final UnitCategory unitCategory;

  /// The unit this item's quantities are rendered in by default.
  final String defaultDisplayUnitCode;

  /// Rough classification. `medicine` is what puts medicine expiry on the calendar with no extra
  /// table (ARCH_3 §6).
  final ItemKind itemKind;

  /// Pinned to the top of the inventory list.
  final bool isFavorite;

  /// Below this total remaining quantity the item is low on stock, or null if unset.
  final Qty? lowStockThreshold;

  /// How many days before a batch's expiry to remind, or null to use the global setting.
  final int? expiryNotifyDays;

  /// Optional free-text notes. Indexed for full-text search.
  final String? notes;

  /// True when a low-stock threshold is set, so the suggestion engine may act on this item.
  bool get hasThreshold => lowStockThreshold != null;

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  ///
  /// [unitCategory] is accepted here so a mapper can round-trip an entity unchanged, but the
  /// repository rejects a *saved* change to it (Law L8).
  Item copyWith({
    String? id,
    String? name,
    String? normalizedName,
    UnitCategory? unitCategory,
    String? defaultDisplayUnitCode,
    ItemKind? itemKind,
    bool? isFavorite,
    Qty? lowStockThreshold,
    int? expiryNotifyDays,
    String? notes,
  }) {
    return Item(
      id: id ?? this.id,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      unitCategory: unitCategory ?? this.unitCategory,
      defaultDisplayUnitCode: defaultDisplayUnitCode ?? this.defaultDisplayUnitCode,
      itemKind: itemKind ?? this.itemKind,
      isFavorite: isFavorite ?? this.isFavorite,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      expiryNotifyDays: expiryNotifyDays ?? this.expiryNotifyDays,
      notes: notes ?? this.notes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Item &&
          other.id == id &&
          other.name == name &&
          other.normalizedName == normalizedName &&
          other.unitCategory == unitCategory &&
          other.defaultDisplayUnitCode == defaultDisplayUnitCode &&
          other.itemKind == itemKind &&
          other.isFavorite == isFavorite &&
          other.lowStockThreshold == lowStockThreshold &&
          other.expiryNotifyDays == expiryNotifyDays &&
          other.notes == notes;

  @override
  int get hashCode => Object.hashAll([
    id, name, normalizedName, unitCategory, defaultDisplayUnitCode, itemKind,
    isFavorite, lowStockThreshold, expiryNotifyDays, notes,
  ]);

  @override
  String toString() => 'Item($id, $name, ${unitCategory.name})';
}