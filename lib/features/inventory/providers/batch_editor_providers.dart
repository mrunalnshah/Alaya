/// View-model state for the batch editor (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/features/inventory/state/batch_editor_state.dart';

/// Which batch an editor is pointed at. A record, so the family argument has structural equality.
typedef BatchEditorArgs = ({String itemId, String? batchId});

/// The home currency, so a unit cost is never denominated in a guess.
final batchCurrencyProvider = FutureProvider.autoDispose<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      'INR',
);

/// The home currency's decimal digits, so no cost hardcodes 2 (ARCH_1 §4.1).
final batchDecimalDigitsProvider = FutureProvider.autoDispose<int>((ref) async {
  final code = await ref.watch(batchCurrencyProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// The item a batch belongs to, so the editor knows its immutable category.
final batchOwnerProvider = FutureProvider.autoDispose.family<Item?, String>(
  (ref, itemId) => ref.watch(itemRepositoryProvider).byId(itemId),
);

/// The editor for one batch, or for a new one when `batchId` is null.
final batchEditorProvider = NotifierProvider.autoDispose
    .family<BatchEditorNotifier, AsyncValue<BatchEditorState>, BatchEditorArgs>(
      BatchEditorNotifier.new,
    );

/// Loads, edits and saves one batch.
class BatchEditorNotifier
    extends
        AutoDisposeFamilyNotifier<
          AsyncValue<BatchEditorState>,
          BatchEditorArgs
        > {
  @override
  AsyncValue<BatchEditorState> build(BatchEditorArgs arg) {
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(BatchEditorArgs arg) async {
    try {
      final batchId = arg.batchId;
      if (batchId != null) {
        final batch = await ref.read(batchRepositoryProvider).byId(batchId);
        if (batch == null) {
          state = AsyncValue.error(
            StateError('Batch $batchId not found.'),
            StackTrace.current,
          );
          return;
        }
        state = AsyncValue.data(BatchEditorState.fromBatch(batch));
        return;
      }
      final item = await ref.read(itemRepositoryProvider).byId(arg.itemId);
      if (item == null) {
        state = AsyncValue.error(
          StateError('Item ${arg.itemId} not found.'),
          StackTrace.current,
        );
        return;
      }
      state = AsyncValue.data(
        BatchEditorState(
          itemId: arg.itemId,
          unitCode: item.defaultDisplayUnitCode,
          purchasedDateKey: ref.read(clockProvider).today(),
        ),
      );
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  void _edit(BatchEditorState Function(BatchEditorState) change) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(change(current));
  }

  /// Sets how much arrived.
  void setQuantity(Qty? quantity) => _edit(
    (s) => quantity == null
        ? s.copyWith(clearQuantity: true)
        : s.copyWith(quantity: quantity, quantityMissing: false),
  );

  /// Sets the unit the quantity was entered in.
  void setUnitCode(String code) => _edit((s) => s.copyWith(unitCode: code));

  /// Sets when it was bought.
  void setPurchased(DateKey date) =>
      _edit((s) => s.copyWith(purchasedDateKey: date));

  /// Sets when it expires, or clears the expiry.
  void setExpiry(DateKey? date) => _edit(
    (s) => date == null
        ? s.copyWith(clearExpiry: true)
        : s.copyWith(expiryDateKey: date),
  );

  /// Sets what one unit cost.
  void setUnitCost(Money? cost) => _edit(
    (s) => cost == null
        ? s.copyWith(clearUnitCost: true)
        : s.copyWith(unitCost: cost),
  );

  /// Sets where it is kept.
  void setStorageLocation(String location) =>
      _edit((s) => s.copyWith(storageLocation: location));

  /// Sets the free note.
  void setNote(String note) => _edit((s) => s.copyWith(note: note));

  /// Saves the batch, returning its id on success and null on rejection or failure.
  ///
  /// A new batch goes through `create`; an existing one through `updateMetadata`, which is the only
  /// path that does not touch `remainingQuantity`. That split is Law L3: the remaining figure is a
  /// cache reconciled from `stock_movements`, and an editor that rewrote it would leave the cache
  /// and the ledger disagreeing with no movement to explain the difference.
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    final quantity = current.quantity;
    if (quantity == null || !quantity.isPositive) {
      _edit(
        (s) =>
            s.copyWith(quantityMissing: true, shakeTrigger: s.shakeTrigger + 1),
      );
      return null;
    }

    _edit((s) => s.copyWith(submitting: true));
    final repository = ref.read(batchRepositoryProvider);
    final id = current.id ?? ref.read(uidGeneratorProvider).generate();

    if (current.isEditing) {
      final existing = await repository.byId(id);
      if (existing == null) {
        _edit((s) => s.copyWith(submitting: false));
        return null;
      }
      final updated = await repository.updateMetadata(
        current.toBatch(
          newId: id,
          resolvedQuantity: existing.initialQuantity,
          remaining: existing.remainingQuantity,
        ),
      );
      if (updated.isFailure) {
        _edit((s) => s.copyWith(submitting: false));
        return null;
      }
    } else {
      final created = await repository.create(
        current.toBatch(newId: id, resolvedQuantity: quantity),
      );
      if (created.isFailure) {
        _edit((s) => s.copyWith(submitting: false));
        return null;
      }
    }
    _edit((s) => s.copyWith(submitting: false, dirty: false));
    return id;
  }
}
