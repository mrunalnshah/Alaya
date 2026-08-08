import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';

/// Everything the batch editor is holding (ARCH_5 §3 archetype B).
///
/// A batch's quantity is editable only while creating. Once movements exist against it,
/// `remainingQuantity` is a derived cache (Law L3) reconciled from the movement ledger, so an editor
/// rewriting it would put the cache and the ledger into disagreement that only `recompute()` could
/// resolve. Editing therefore covers the metadata — expiry, purchase date, unit cost, location — and
/// quantity changes go through the consume and adjust paths, which append movements.
class BatchEditorState {
  /// Creates the editor's state.
  const BatchEditorState({
    required this.itemId,
    required this.unitCode,
    required this.purchasedDateKey,
    this.id,
    this.quantity,
    this.expiryDateKey,
    this.unitCost,
    this.storageLocation,
    this.note,
    this.origin = BatchOrigin.manual,
    this.submitting = false,
    this.quantityMissing = false,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// The batch being edited, or null when this is a new one.
  final String? id;

  /// Which item this batch belongs to.
  final String itemId;

  /// How much arrived — the one required field when creating (U11).
  final Qty? quantity;

  /// The unit the quantity was entered in.
  final String unitCode;

  /// When it was bought.
  final DateKey purchasedDateKey;

  /// When it expires, if it does.
  final DateKey? expiryDateKey;

  /// What one unit cost.
  final Money? unitCost;

  /// Where it is kept.
  final String? storageLocation;

  /// Free note.
  final String? note;

  /// Where this batch came from; preserved on edit so a fan-out batch stays attributed.
  final BatchOrigin origin;

  /// Whether a save is in flight.
  final bool submitting;

  /// Whether submit was pressed with no parseable quantity.
  final bool quantityMissing;

  /// Incremented to shake the quantity field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the unsaved-changes guard (U10).
  final bool dirty;

  /// Whether this is editing an existing batch rather than creating one.
  bool get isEditing => id != null;

  /// Whether the quantity field may be edited.
  bool get quantityEditable => !isEditing;

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  BatchEditorState copyWith({
    String? id,
    Qty? quantity,
    bool clearQuantity = false,
    String? unitCode,
    DateKey? purchasedDateKey,
    DateKey? expiryDateKey,
    bool clearExpiry = false,
    Money? unitCost,
    bool clearUnitCost = false,
    String? storageLocation,
    String? note,
    BatchOrigin? origin,
    bool? submitting,
    bool? quantityMissing,
    int? shakeTrigger,
    bool? dirty,
  }) => BatchEditorState(
    id: id ?? this.id,
    itemId: itemId,
    quantity: clearQuantity ? null : (quantity ?? this.quantity),
    unitCode: unitCode ?? this.unitCode,
    purchasedDateKey: purchasedDateKey ?? this.purchasedDateKey,
    expiryDateKey: clearExpiry ? null : (expiryDateKey ?? this.expiryDateKey),
    unitCost: clearUnitCost ? null : (unitCost ?? this.unitCost),
    storageLocation: storageLocation ?? this.storageLocation,
    note: note ?? this.note,
    origin: origin ?? this.origin,
    submitting: submitting ?? this.submitting,
    quantityMissing: quantityMissing ?? this.quantityMissing,
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? true,
  );

  /// Builds the entity this state describes.
  ///
  /// [remaining] is the existing remaining quantity when editing; a new batch starts full.
  Batch toBatch({
    required String newId,
    required Qty resolvedQuantity,
    Qty? remaining,
  }) => Batch(
    id: id ?? newId,
    itemId: itemId,
    initialQuantity: resolvedQuantity,
    remainingQuantity: remaining ?? resolvedQuantity,
    unitCodeAtPurchase: unitCode,
    purchasedDateKey: purchasedDateKey,
    origin: origin,
    expiryDateKey: expiryDateKey,
    unitCost: unitCost,
    storageLocation: storageLocation,
    note: note,
  );

  /// Loads an existing batch into an editor state.
  static BatchEditorState fromBatch(Batch batch) => BatchEditorState(
    id: batch.id,
    itemId: batch.itemId,
    quantity: batch.initialQuantity,
    unitCode: batch.unitCodeAtPurchase,
    purchasedDateKey: batch.purchasedDateKey,
    expiryDateKey: batch.expiryDateKey,
    unitCost: batch.unitCost,
    storageLocation: batch.storageLocation,
    note: batch.note,
    origin: batch.origin,
  );
}
