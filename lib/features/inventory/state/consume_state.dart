import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/domain/entities/batch.dart';

/// One batch the pending consume will draw from, and how much.
class ConsumePlanLeg {
  /// Creates a leg.
  const ConsumePlanLeg({required this.batch, required this.quantity});

  /// The batch drawn from.
  final Batch batch;

  /// How much comes out of it.
  final Qty quantity;
}

/// What the consume sheet is holding (ARCH_5 §3 archetype A).
class ConsumeState {
  /// Creates the sheet's state.
  const ConsumeState({
    required this.itemId,
    required this.unitCode,
    this.quantity,
    this.kind = StockMovementKind.consume,
    this.overrideBatchId,
    this.reason,
    this.submitting = false,
    this.quantityMissing = false,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// Which item is being drawn down.
  final String itemId;

  /// The unit the quantity was entered in.
  final String unitCode;

  /// How much — the one required field (U11).
  final Qty? quantity;

  /// Used, thrown away, or expired. Three kinds, not one with a reason string, because 7B's waste
  /// insight aggregates on `stock_movements.kind` and cannot read prose.
  final StockMovementKind kind;

  /// The batch the user picked instead of letting FEFO choose.
  final String? overrideBatchId;

  /// Why, for waste and expiry.
  final String? reason;

  /// Whether a commit is in flight.
  final bool submitting;

  /// Whether commit was pressed with no parseable quantity.
  final bool quantityMissing;

  /// Incremented to shake the quantity field.
  final int shakeTrigger;

  /// Whether any optional field was touched, for the dismiss guard (U10).
  final bool dirty;

  /// Whether the user has overridden the FEFO choice.
  bool get isOverridden => overrideBatchId != null;

  /// Returns a copy with the supplied changes.
  ConsumeState copyWith({
    Qty? quantity,
    bool clearQuantity = false,
    String? unitCode,
    StockMovementKind? kind,
    String? overrideBatchId,
    bool clearOverride = false,
    String? reason,
    bool? submitting,
    bool? quantityMissing,
    int? shakeTrigger,
    bool? dirty,
  }) => ConsumeState(
    itemId: itemId,
    unitCode: unitCode ?? this.unitCode,
    quantity: clearQuantity ? null : (quantity ?? this.quantity),
    kind: kind ?? this.kind,
    overrideBatchId: clearOverride
        ? null
        : (overrideBatchId ?? this.overrideBatchId),
    reason: reason ?? this.reason,
    submitting: submitting ?? this.submitting,
    quantityMissing: quantityMissing ?? this.quantityMissing,
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? this.dirty,
  );

  /// Which batches this consume will touch, oldest expiry first.
  ///
  /// **Computed here so the sheet can say "spans 3 batches" before committing**, not after. The
  /// repository's `consume()` does the authoritative allocation and returns the draws it actually
  /// made; this is the preview that lets the user see a multi-batch write coming. The two agree
  /// because both walk the same FEFO ordering from `watchByItemFefo`.
  ///
  /// An override collapses the plan to a single leg, clamped to what that batch holds.
  List<ConsumePlanLeg> planAgainst(List<Batch> fefo) {
    final wanted = quantity;
    if (wanted == null || !wanted.isPositive) return const [];

    final override = overrideBatchId;
    if (override != null) {
      for (final batch in fefo) {
        if (batch.id != override) continue;
        final take = wanted <= batch.remainingQuantity
            ? wanted
            : batch.remainingQuantity;
        return take.isPositive
            ? [ConsumePlanLeg(batch: batch, quantity: take)]
            : const [];
      }
      return const [];
    }

    final legs = <ConsumePlanLeg>[];
    var outstanding = wanted;
    for (final batch in fefo) {
      if (!outstanding.isPositive) break;
      if (!batch.hasStock) continue;
      final take = outstanding <= batch.remainingQuantity
          ? outstanding
          : batch.remainingQuantity;
      legs.add(ConsumePlanLeg(batch: batch, quantity: take));
      outstanding -= take;
    }
    return legs;
  }

  /// How much of [quantity] the batches cannot cover.
  Qty? shortfallAgainst(List<Batch> fefo) {
    final wanted = quantity;
    if (wanted == null) return null;
    var covered = Qty(0, wanted.category);
    for (final leg in planAgainst(fefo)) {
      covered += leg.quantity;
    }
    final missing = wanted - covered;
    return missing.isPositive ? missing : null;
  }
}
