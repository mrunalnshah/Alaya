import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';

/// What the entry editor is holding (ARCH_5 §3 archetype A).
///
/// **`itemId` is nullable and stays that way.** A television belongs on a shopping list and has no
/// business in an inventory that tracks flour by the gram, so an entry needs either a name or a
/// linked item — never both, never necessarily one in particular.
class EntryEditorState {
  /// Creates the editor's state.
  const EntryEditorState({
    required this.listId,
    this.id,
    this.freeText = '',
    this.itemId,
    this.quantity,
    this.unitCode,
    this.tagId,
    this.estimatedPrice,
    this.origin = ShoppingEntryOrigin.manual,
    this.autoState = ShoppingEntryAutoState.active,
    this.sortOrder = 0,
    this.isChecked = false,
    this.submitting = false,
    this.identityMissing = false,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// The entry being edited, or null for a new one.
  final String? id;

  /// Which list it belongs to.
  final String listId;

  /// What to buy, in the user's words.
  final String freeText;

  /// The catalogued item this restocks, if any.
  final String? itemId;

  /// How much to buy.
  final Qty? quantity;

  /// The unit the quantity was entered in.
  final String? unitCode;

  /// The aisle-ish grouping this row sits under.
  final String? tagId;

  /// What the user expects it to cost.
  final Money? estimatedPrice;

  /// Where the entry came from.
  final ShoppingEntryOrigin origin;

  /// Whether an auto entry is active, snoozed or dismissed.
  final ShoppingEntryAutoState autoState;

  /// Its position in the list.
  final int sortOrder;

  /// Whether it is already ticked.
  final bool isChecked;

  /// Whether a save is in flight.
  final bool submitting;

  /// Whether submit was pressed with neither a name nor an item.
  final bool identityMissing;

  /// Incremented to shake the name field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the dismiss guard (Law U10).
  final bool dirty;

  /// Whether this is editing an existing entry.
  bool get isEditing => id != null;

  /// Whether the entry has something to identify it by.
  bool get hasIdentity => freeText.trim().isNotEmpty || itemId != null;

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  EntryEditorState copyWith({
    String? id,
    String? freeText,
    String? itemId,
    bool clearItem = false,
    Qty? quantity,
    bool clearQuantity = false,
    String? unitCode,
    String? tagId,
    bool clearTag = false,
    Money? estimatedPrice,
    bool clearPrice = false,
    ShoppingEntryOrigin? origin,
    ShoppingEntryAutoState? autoState,
    int? sortOrder,
    bool? isChecked,
    bool? submitting,
    bool? identityMissing,
    int? shakeTrigger,
    bool? dirty,
  }) => EntryEditorState(
    id: id ?? this.id,
    listId: listId,
    freeText: freeText ?? this.freeText,
    itemId: clearItem ? null : (itemId ?? this.itemId),
    quantity: clearQuantity ? null : (quantity ?? this.quantity),
    unitCode: unitCode ?? this.unitCode,
    tagId: clearTag ? null : (tagId ?? this.tagId),
    estimatedPrice: clearPrice ? null : (estimatedPrice ?? this.estimatedPrice),
    origin: origin ?? this.origin,
    autoState: autoState ?? this.autoState,
    sortOrder: sortOrder ?? this.sortOrder,
    isChecked: isChecked ?? this.isChecked,
    submitting: submitting ?? this.submitting,
    identityMissing: identityMissing ?? this.identityMissing,
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? true,
  );

  /// Builds the entity this state describes.
  ///
  /// **Editing an auto entry promotes it to manual.** A suggestion the user has shaped is theirs,
  /// and regeneration must never remove or rewrite it (anomaly A23) — `origin` is what the engine
  /// keys that decision on, so the promotion happens here rather than being left to the caller.
  ShoppingEntry toEntry({required String newId}) {
    final promoted = isEditing && origin == ShoppingEntryOrigin.autoLowStock
        ? ShoppingEntryOrigin.manual
        : origin;
    return ShoppingEntry(
      id: id ?? newId,
      listId: listId,
      origin: promoted,
      autoState: promoted == ShoppingEntryOrigin.manual
          ? ShoppingEntryAutoState.active
          : autoState,
      isChecked: isChecked,
      sortOrder: sortOrder,
      itemId: itemId,
      freeText: freeText.trim().isEmpty ? null : freeText.trim(),
      quantity: quantity,
      unitCode: unitCode,
      tagId: tagId,
      estimatedPrice: estimatedPrice,
    );
  }

  /// Loads an existing entry into an editor state.
  static EntryEditorState fromEntry(ShoppingEntry entry) => EntryEditorState(
    id: entry.id,
    listId: entry.listId,
    freeText: entry.freeText ?? '',
    itemId: entry.itemId,
    quantity: entry.quantity,
    unitCode: entry.unitCode,
    tagId: entry.tagId,
    estimatedPrice: entry.estimatedPrice,
    origin: entry.origin,
    autoState: entry.autoState,
    sortOrder: entry.sortOrder,
    isChecked: entry.isChecked,
  );
}
