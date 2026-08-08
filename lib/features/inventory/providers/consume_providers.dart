/// View-model state for the consume sheet (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/features/inventory/state/consume_state.dart';

/// The batches a consume may draw from, oldest expiry first.
final consumeFefoProvider = StreamProvider.autoDispose
    .family<List<Batch>, String>(
      (ref, itemId) => ref
          .watch(batchRepositoryProvider)
          .watchByItemFefo(itemId)
          .map(
            (batches) => [
              for (final batch in batches)
                if (batch.hasStock) batch,
            ],
          ),
    );

/// Which item a consume sheet is drawing down, and in what unit.
typedef ConsumeArgs = ({String itemId, String unitCode});

/// The consume sheet for one item.
final consumeProvider = NotifierProvider.autoDispose
    .family<ConsumeNotifier, ConsumeState, ConsumeArgs>(ConsumeNotifier.new);

/// Holds the pending consume and commits it.
///
/// **State is synchronous, not an `AsyncValue`.** A capture sheet must accept its first keystroke on
/// its first frame (§5.2), and everything this notifier needs — the item and its unit — arrives in
/// the family argument from the screen that already loaded them. The asynchronous surface belongs to
/// [consumeFefoProvider], which the sheet watches separately for its four states.
class ConsumeNotifier
    extends AutoDisposeFamilyNotifier<ConsumeState, ConsumeArgs> {
  @override
  ConsumeState build(ConsumeArgs arg) =>
      ConsumeState(itemId: arg.itemId, unitCode: arg.unitCode);

  /// Sets how much is leaving.
  void setQuantity(Qty? quantity) => state = quantity == null
      ? state.copyWith(clearQuantity: true)
      : state.copyWith(quantity: quantity, quantityMissing: false);

  /// Records the unit the field is entering quantities in.
  ///
  /// `QtyField`'s unit picker is controlled, so without this the user taps `g`, the number is
  /// re-parsed against the new factor, and the picker snaps back to `kg`.
  void setUnitCode(String code) =>
      state = state.copyWith(unitCode: code, dirty: true);

  /// Switches between used, thrown away and expired.
  void setKind(StockMovementKind kind) =>
      state = state.copyWith(kind: kind, dirty: true);

  /// Overrides the FEFO choice with a specific batch.
  void setBatch(String? batchId) => state = batchId == null
      ? state.copyWith(clearOverride: true, dirty: true)
      : state.copyWith(overrideBatchId: batchId, dirty: true);

  /// Sets why, for waste and expiry.
  void setReason(String reason) =>
      state = state.copyWith(reason: reason, dirty: true);

  /// Commits the consume, returning how many movements it wrote.
  ///
  /// **Two paths, deliberately.** Without an override this calls `consume`, which allocates across
  /// batches FEFO inside one transaction (Law L14) and returns the draws it made — so a consume that
  /// spans three batches writes three movements and the caller learns the real count rather than the
  /// predicted one. With an override it calls `consumeFromBatch`, a single movement against the
  /// batch the user named.
  ///
  /// Returns null when the form was rejected or the write failed.
  Future<int?> commit() async {
    final quantity = state.quantity;
    if (quantity == null || !quantity.isPositive) {
      state = state.copyWith(
        quantityMissing: true,
        shakeTrigger: state.shakeTrigger + 1,
      );
      return null;
    }

    state = state.copyWith(submitting: true);
    final repository = ref.read(stockRepositoryProvider);
    final override = state.overrideBatchId;

    if (override != null) {
      final result = await repository.consumeFromBatch(
        batchId: override,
        quantity: quantity,
        kind: state.kind,
        reason: state.reason,
      );
      state = state.copyWith(submitting: false);
      return result.isFailure ? null : 1;
    }

    final result = await repository.consume(
      itemId: state.itemId,
      quantity: quantity,
      kind: state.kind,
      reason: state.reason,
    );
    state = state.copyWith(submitting: false);
    return result.valueOrNull?.length;
  }
}
