/// View-model state for one item (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/providers/inventory_list_providers.dart';

/// The item, or null when it has been deleted.
/// **Derived from the catalogue stream, not a one-shot `byId`.** A `FutureProvider` reads once and
/// then serves its cache, and `autoDispose` does not help — the detail screen stays mounted beneath
/// the editor, so it kept showing the pre-edit item until the app was restarted. `watchAll()` re-emits
/// on every write, so selecting one item out of it makes the screen live and needs no `watchById` on
/// the contract.
final itemByIdProvider = Provider.autoDispose.family<AsyncValue<Item?>, String>(
  (ref, id) {
    return ref.watch(itemsProvider).whenData((all) {
      for (final item in all) {
        if (item.id == id) return item;
      }
      return null;
    });
  },
);

/// Stock on hand for one item — the hero figure.
final itemStockProvider = StreamProvider.autoDispose.family<ItemStock?, String>(
  (ref, id) => ref.watch(itemRepositoryProvider).watchStockOf(id),
);

/// This item's batches, oldest expiry first, which is also the order a consume draws them.
final itemBatchesProvider = StreamProvider.autoDispose
    .family<List<Batch>, String>(
      (ref, id) => ref.watch(batchRepositoryProvider).watchByItemFefo(id),
    );

/// Every unit, keyed by code.
final detailUnitsByCodeProvider = StreamProvider.autoDispose<Map<String, Unit>>(
  (ref) => ref
      .watch(unitRepositoryProvider)
      .watchAll()
      .map(
        (units) => {for (final unit in units) unit.code: unit},
      ),
);

/// Writes an item detail screen can perform.
final itemActionsProvider = Provider<ItemActions>(ItemActions.new);

/// Deletes and stars items.
class ItemActions {
  /// Creates the actions.
  ItemActions(this._ref);

  final Ref _ref;

  /// Deletes the item, cascade-soft-deleting its batches.
  ///
  /// **The movement history is left untouched.** Batches carry `deletedAt` and go with the item, but
  /// `stock_movements` is append-only (Law L6) — what was already used genuinely happened, and
  /// erasing it would change last month's waste figures because a container was tidied away today.
  Future<bool> delete(String id) async {
    final result = await _ref.read(itemRepositoryProvider).delete(id);
    return !result.isFailure;
  }

  /// Stars or unstars the item.
  Future<bool> toggleFavourite(Item item) async {
    final result = await _ref
        .read(itemRepositoryProvider)
        .setFavorite(
          id: item.id,
          isFavorite: !item.isFavorite,
        );
    return !result.isFailure;
  }

  /// Deletes one batch, leaving its movements in place for the same reason.
  Future<bool> deleteBatch(String batchId) async {
    final result = await _ref.read(batchRepositoryProvider).delete(batchId);
    return !result.isFailure;
  }
}
