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
    this.kindTagId,
    required this.isFavorite,
    this.lowStockThreshold,
    this.expiryNotifyDays,
    this.densityMilliGramsPerMl,
    this.milliGramsPerPiece,
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

  /// Which kind this item is filed under — a `tags` row id, or null while nothing has been chosen.
  ///
  /// **A tag id rather than an enum, so a user can add `Vegetables`.** The six built-ins are seeded rows with
  /// `is_system` set; anything else is one the user made, from Settings or inline while entering a receipt.
  ///
  /// **Nullable in the schema and, after the v5 backfill, never null in practice.** The migration had to add
  /// the column nullable — there was nothing to default it to before the tags existed — and then filled every
  /// row. It stays `String?` here because the column is, and the one place that resolves null is the grouping
  /// bucket, which sends it to *Other*. A non-null field would have forced the mapper to invent an id to
  /// maintain the lie.
  ///
  /// Deleting a kind moves its items to *Other* rather than leaving them pointing at a soft-deleted row —
  /// which is the one rule in this design that has to be remembered rather than enforced, and it lives in the
  /// Settings delete path.
  final String? kindTagId;

  /// Pinned to the top of the inventory list.
  final bool isFavorite;

  /// Below this total remaining quantity the item is low on stock, or null if unset.
  final Qty? lowStockThreshold;

  /// How many days before a batch's expiry to remind, or null to use the global setting.
  final int? expiryNotifyDays;

  /// How much one millilitre of this item weighs, in milli-grams. Null when unknown.
  ///
  /// The volume-to-weight bridge: a tablespoon is 14.787 ml for everything, but a tablespoon of
  /// butter and one of flour weigh different amounts. That difference is a property of the item, so
  /// one number here serves every volume unit at once.
  final int? densityMilliGramsPerMl;

  /// What one piece of this item weighs, in milli-grams. Null when unknown.
  final int? milliGramsPerPiece;

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
    String? kindTagId,
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
      defaultDisplayUnitCode:
          defaultDisplayUnitCode ?? this.defaultDisplayUnitCode,
      kindTagId: kindTagId ?? this.kindTagId,
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
      other.kindTagId == kindTagId &&
      other.isFavorite == isFavorite &&
      other.lowStockThreshold == lowStockThreshold &&
      other.expiryNotifyDays == expiryNotifyDays &&
      other.notes == notes;

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    normalizedName,
    unitCategory,
    defaultDisplayUnitCode,
    kindTagId,
    isFavorite,
    lowStockThreshold,
    expiryNotifyDays,
    notes,
  ]);

  @override
  String toString() => 'Item($id, $name, ${unitCategory.name})';
}
