import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';

/// An immutable event changing a batch's remaining quantity — the second of the app's three
/// append-only truths (ARCH_1 §3.3).
///
/// There is no soft delete and no edit (Law L6's stated exception): a correction is a *reversing*
/// movement pointing at the original through [reversesMovementId]. A ledger you can edit is not a
/// ledger, and waste analytics depends on this one staying honest.
///
/// **Deliberately has no `copyWith`**, unlike every other entity here. Offering one would invite
/// exactly the edit this table exists to make impossible; construct a reversing movement instead.
class StockMovement {
  /// Creates a movement.
  const StockMovement({
    required this.id,
    required this.batchId,
    required this.itemId,
    required this.kind,
    required this.quantity,
    required this.occurredAtUtc,
    required this.dateKey,
    this.reason,
    this.note,
    this.linkedTransactionId,
    this.reversesMovementId,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// The batch this movement applies to.
  final String batchId;

  /// The owning item, denormalised so per-item analytics needs no join.
  final String itemId;

  /// What kind of event this was. [quantity] is always positive; this carries the direction.
  final StockMovementKind kind;

  /// Quantity moved, always positive.
  final Qty quantity;

  /// When it happened. Always UTC.
  final DateTime occurredAtUtc;

  /// The local civil date it happened on.
  final DateKey dateKey;

  /// Optional structured reason, e.g. why something was wasted.
  final String? reason;

  /// Optional free-text note.
  final String? note;

  /// The transaction that caused this movement, for purchase-driven increases.
  final String? linkedTransactionId;

  /// The movement this row reverses. Non-null exactly on correction rows.
  final String? reversesMovementId;

  /// Whether this kind of movement increases stock.
  ///
  /// The single Dart statement of the direction rule, matching `v_batch_stock_check`'s
  /// `CASE WHEN kind IN (...)` exactly — a repair path and its reconciliation probe must never
  /// disagree about which way a kind moves stock.
  bool get isIncoming => switch (kind) {
    StockMovementKind.openingIn ||
    StockMovementKind.purchaseIn ||
    StockMovementKind.manualIn ||
    StockMovementKind.adjustIn =>
    true,
    StockMovementKind.consume ||
    StockMovementKind.waste ||
    StockMovementKind.expired ||
    StockMovementKind.adjustOut =>
    false,
  };

  /// This movement's signed effect on the batch's remaining quantity.
  Qty get signedQuantity => isIncoming ? quantity : -quantity;

  /// True when this movement represents stock thrown away rather than used — the input to the
  /// food-waste analytics (ARCH_3 §5.1 query 14).
  bool get isWaste =>
      kind == StockMovementKind.waste || kind == StockMovementKind.expired;

  /// True when this movement corrects an earlier one.
  bool get isReversal => reversesMovementId != null;

  @override
  bool operator ==(Object other) =>
      other is StockMovement &&
          other.id == id &&
          other.batchId == batchId &&
          other.itemId == itemId &&
          other.kind == kind &&
          other.quantity == quantity &&
          other.occurredAtUtc == occurredAtUtc &&
          other.dateKey == dateKey &&
          other.reason == reason &&
          other.note == note &&
          other.linkedTransactionId == linkedTransactionId &&
          other.reversesMovementId == reversesMovementId;

  @override
  int get hashCode => Object.hashAll([
    id, batchId, itemId, kind, quantity, occurredAtUtc, dateKey, reason, note,
    linkedTransactionId, reversesMovementId,
  ]);

  @override
  String toString() => 'StockMovement($id, ${kind.name}, $quantity)';
}