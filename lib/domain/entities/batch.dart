import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';

/// One acquisition of an `Item`: a quantity, an expiry, a cost and a source.
///
/// Every stock operation acts on batches; the item row only sums them (ARCH_1 §5.4).
class Batch {
  /// Creates a batch.
  const Batch({
    required this.id,
    required this.itemId,
    required this.initialQuantity,
    required this.remainingQuantity,
    required this.unitCodeAtPurchase,
    required this.purchasedDateKey,
    required this.origin,
    this.expiryDateKey,
    this.unitCost,
    this.sourceTransactionLineId,
    this.storageLocation,
    this.note,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// The item this batch is an acquisition of.
  final String itemId;

  /// Quantity acquired.
  final Qty initialQuantity;

  /// Quantity still on hand.
  ///
  /// The one derived total the schema stores (Law L3's stated exception), reconstructible at any
  /// time from the movement ledger. Treat it as authoritative for display and repairable if it
  /// ever disagrees.
  final Qty remainingQuantity;

  /// The unit the user actually purchased in, kept for display fidelity only.
  final String unitCodeAtPurchase;

  /// The civil date acquired.
  final DateKey purchasedDateKey;

  /// Where this batch came from. `detached` once its source transaction is deleted — the food does
  /// not un-exist because the receipt did (anomaly A10).
  final BatchOrigin origin;

  /// The civil expiry date, or null if this batch does not expire.
  final DateKey? expiryDateKey;

  /// Cost per [unitCodeAtPurchase], or null if unrecorded.
  final Money? unitCost;

  /// The transaction line that created this batch, if it came from a purchase.
  final String? sourceTransactionLineId;

  /// Optional free-text location, e.g. `Top shelf`.
  final String? storageLocation;

  /// Optional free-text note.
  final String? note;

  /// True when nothing is left in this batch.
  bool get isExhausted => remainingQuantity.isZero;

  /// True when this batch has stock and therefore participates in FEFO consumption.
  bool get hasStock => remainingQuantity.isPositive;

  /// How much has been drawn down from this batch.
  Qty get consumedQuantity => initialQuantity - remainingQuantity;

  /// True when this batch has passed its expiry as of [today].
  ///
  /// A batch with no expiry date is never expired. Takes [today] rather than reading a clock so it
  /// stays deterministic under a `FixedClock`, the same rule the views follow (ARCH_2 §12.2).
  bool isExpired(DateKey today) {
    final expiry = expiryDateKey;
    return expiry != null && expiry < today;
  }

  /// True when this batch expires within [days] of [today] — including already past.
  bool isExpiringWithin(DateKey today, int days) {
    final expiry = expiryDateKey;
    return expiry != null && expiry.diffDays(today) <= days;
  }

  /// Days from [today] until expiry — negative once past, null if this batch does not expire.
  int? daysUntilExpiry(DateKey today) => expiryDateKey?.diffDays(today);

  /// The total cost of what remains, or null when no unit cost is recorded.
  ///
  /// Rounds toward zero: a fractional minor unit cannot be represented, and inventory valuation is
  /// an estimate rather than a ledger figure.
  Money? get remainingValue {
    final cost = unitCost;
    if (cost == null) return null;
    return Money(
      (cost.minor * remainingQuantity.milliBase / 1000).truncate(),
      cost.currencyCode,
    );
  }

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  Batch copyWith({
    String? id,
    String? itemId,
    Qty? initialQuantity,
    Qty? remainingQuantity,
    String? unitCodeAtPurchase,
    DateKey? purchasedDateKey,
    BatchOrigin? origin,
    DateKey? expiryDateKey,
    Money? unitCost,
    String? sourceTransactionLineId,
    String? storageLocation,
    String? note,
  }) {
    return Batch(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      initialQuantity: initialQuantity ?? this.initialQuantity,
      remainingQuantity: remainingQuantity ?? this.remainingQuantity,
      unitCodeAtPurchase: unitCodeAtPurchase ?? this.unitCodeAtPurchase,
      purchasedDateKey: purchasedDateKey ?? this.purchasedDateKey,
      origin: origin ?? this.origin,
      expiryDateKey: expiryDateKey ?? this.expiryDateKey,
      unitCost: unitCost ?? this.unitCost,
      sourceTransactionLineId: sourceTransactionLineId ?? this.sourceTransactionLineId,
      storageLocation: storageLocation ?? this.storageLocation,
      note: note ?? this.note,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Batch &&
          other.id == id &&
          other.itemId == itemId &&
          other.initialQuantity == initialQuantity &&
          other.remainingQuantity == remainingQuantity &&
          other.unitCodeAtPurchase == unitCodeAtPurchase &&
          other.purchasedDateKey == purchasedDateKey &&
          other.origin == origin &&
          other.expiryDateKey == expiryDateKey &&
          other.unitCost == unitCost &&
          other.sourceTransactionLineId == sourceTransactionLineId &&
          other.storageLocation == storageLocation &&
          other.note == note;

  @override
  int get hashCode => Object.hashAll([
    id, itemId, initialQuantity, remainingQuantity, unitCodeAtPurchase,
    purchasedDateKey, origin, expiryDateKey, unitCost, sourceTransactionLineId,
    storageLocation, note,
  ]);

  @override
  String toString() => 'Batch($id, $remainingQuantity of $itemId)';
}