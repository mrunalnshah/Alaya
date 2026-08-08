import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/item.dart';

/// Why a save was refused, when it was refused for a reason worth naming.
enum ItemSaveIssue {
  /// A live item already has this name and this measure.
  duplicate,

  /// No units exist for the chosen measure, so the display unit would dangle.
  unitsMissing,

  /// The write failed for a reason the repository did not name.
  unknown,
}

/// Everything the item editor is holding (ARCH_5 §3 archetype B).
///
/// **`unitCategory` has no setter once [isEditing] is true.** Law L8 makes it immutable after
/// creation and there is no cross-category conversion, so changing it would reinterpret every batch
/// and movement already recorded against this item — 2 kg of flour silently becoming 2 litres. The
/// editor renders it read-only and says why rather than offering a control that must then be
/// refused.
class ItemEditorState {
  /// Creates the editor's state.
  const ItemEditorState({
    required this.unitCategory,
    required this.displayUnitCode,
    this.thresholdUnitCode,
    this.id,
    this.name = '',
    this.itemKind = ItemKind.generic,
    this.isFavorite = false,
    this.lowStockThreshold,
    this.expiryNotifyDays,
    this.notes,
    this.submitting = false,
    this.nameMissing = false,
    this.shakeTrigger = 0,
    this.dirty = false,
    this.issue,
    this.conflictItemId,
    this.similarInOtherMeasures = const <Item>[],
  });

  /// The item being edited, or null when this is a new one.
  final String? id;

  /// The name — the one required field (U11).
  final String name;

  /// How this item is measured. Immutable once saved (Law L8).
  final UnitCategory unitCategory;

  /// The unit this item's quantities are shown in.
  final String displayUnitCode;

  /// The unit the low-stock threshold is being *entered* in, which is not the display unit.
  ///
  /// Kept separately because typing a threshold in grams must not silently switch the item's whole
  /// display to grams — the stored `Qty` is milli-base either way, so the two choices are
  /// independent and conflating them surprises the user for no gain.
  final String? thresholdUnitCode;

  /// What sort of thing it is; also the catalogue's grouping axis.
  final ItemKind itemKind;

  /// Whether it is starred.
  final bool isFavorite;

  /// The level below which the `low` chip appears.
  final Qty? lowStockThreshold;

  /// Days of warning before a batch expires, consumed by Phase 8B.
  final int? expiryNotifyDays;

  /// Free notes.
  final String? notes;

  /// Whether a save is in flight.
  final bool submitting;

  /// Whether submit was pressed with an empty name.
  final bool nameMissing;

  /// Incremented to shake the name field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the unsaved-changes guard (U10).
  final bool dirty;

  /// Why the last save was refused, or null if it was not.
  final ItemSaveIssue? issue;

  /// The existing item this one collides with, so the editor can offer to open it.
  final String? conflictItemId;

  /// Items with this name under a different measure.
  ///
  /// Not a conflict — Law L8 makes `apple` by weight and `apple` by count two genuinely different
  /// things, and a household legitimately has both. Surfaced as a note so the catalogue does not
  /// fragment by accident, never as a block.
  final List<Item> similarInOtherMeasures;

  /// Whether this is editing an existing item rather than creating one.
  bool get isEditing => id != null;

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  ItemEditorState copyWith({
    String? id,
    String? name,
    String? displayUnitCode,
    String? thresholdUnitCode,
    ItemKind? itemKind,
    bool? isFavorite,
    Qty? lowStockThreshold,
    bool clearThreshold = false,
    int? expiryNotifyDays,
    bool clearNotifyDays = false,
    String? notes,
    bool? submitting,
    bool? nameMissing,
    int? shakeTrigger,
    bool? dirty,
    ItemSaveIssue? issue,
    bool clearIssue = false,
    String? conflictItemId,
    List<Item>? similarInOtherMeasures,
  }) => ItemEditorState(
    id: id ?? this.id,
    name: name ?? this.name,
    unitCategory: unitCategory,
    displayUnitCode: displayUnitCode ?? this.displayUnitCode,
    thresholdUnitCode: thresholdUnitCode ?? this.thresholdUnitCode,
    itemKind: itemKind ?? this.itemKind,
    isFavorite: isFavorite ?? this.isFavorite,
    lowStockThreshold: clearThreshold
        ? null
        : (lowStockThreshold ?? this.lowStockThreshold),
    expiryNotifyDays: clearNotifyDays
        ? null
        : (expiryNotifyDays ?? this.expiryNotifyDays),
    notes: notes ?? this.notes,
    submitting: submitting ?? this.submitting,
    nameMissing: nameMissing ?? this.nameMissing,
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? true,
    issue: clearIssue ? null : (issue ?? this.issue),
    conflictItemId: clearIssue ? null : (conflictItemId ?? this.conflictItemId),
    similarInOtherMeasures:
        similarInOtherMeasures ?? this.similarInOtherMeasures,
  );

  /// Builds the entity this state describes.
  Item toItem({required String newId, required String normalizedName}) => Item(
    id: id ?? newId,
    name: name.trim(),
    normalizedName: normalizedName,
    unitCategory: unitCategory,
    defaultDisplayUnitCode: displayUnitCode,
    itemKind: itemKind,
    isFavorite: isFavorite,
    lowStockThreshold: lowStockThreshold,
    expiryNotifyDays: expiryNotifyDays,
    notes: notes,
  );

  /// Loads an existing item into an editor state.
  static ItemEditorState fromItem(Item item) => ItemEditorState(
    id: item.id,
    name: item.name,
    unitCategory: item.unitCategory,
    displayUnitCode: item.defaultDisplayUnitCode,
    itemKind: item.itemKind,
    isFavorite: item.isFavorite,
    lowStockThreshold: item.lowStockThreshold,
    expiryNotifyDays: item.expiryNotifyDays,
    notes: item.notes,
  );
}
