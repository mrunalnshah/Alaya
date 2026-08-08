/// View-model state for one batch's movement history (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/stock_movement.dart';

/// The batch the history belongs to.
final historyBatchProvider = FutureProvider.autoDispose.family<Batch?, String>(
  (ref, batchId) => ref.watch(batchRepositoryProvider).byId(batchId),
);

/// Every movement against one batch, newest first.
final batchMovementsProvider = StreamProvider.autoDispose
    .family<List<StockMovement>, String>(
      (ref, batchId) =>
          ref.watch(stockRepositoryProvider).watchForBatch(batchId),
    );

/// Which movement ids have already been reversed by a later movement.
///
/// **Derived from the ledger rather than stored on the row.** `stock_movements` is append-only
/// (Law L6): a reversal is a new row pointing back with `reversesMovementId`, and the row it
/// corrects is never rewritten. Reading the set of reversed ids out of the same stream is what lets
/// the timeline strike through the original without either row lying about the other.
final reversedMovementIdsProvider = Provider.autoDispose
    .family<Set<String>, String>((ref, batchId) {
      final movements = ref.watch(batchMovementsProvider(batchId)).valueOrNull;
      if (movements == null) return const <String>{};
      return {
        for (final movement in movements)
          if (movement.reversesMovementId != null) movement.reversesMovementId!,
      };
    });

/// Writes the history screen can perform.
final movementActionsProvider = Provider<MovementActions>(MovementActions.new);

/// Reverses movements.
class MovementActions {
  /// Creates the actions.
  MovementActions(this._ref);

  final Ref _ref;

  /// Appends an opposite movement, correcting [movementId] without erasing it.
  Future<bool> reverse(String movementId, {String? reason}) async {
    final result = await _ref
        .read(stockRepositoryProvider)
        .reverse(movementId: movementId, reason: reason);
    return !result.isFailure;
  }
}
