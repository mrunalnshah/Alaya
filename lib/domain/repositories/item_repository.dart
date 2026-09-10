import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';

/// Reads and writes inventory items, and reads their derived stock.
abstract interface class ItemRepository {
  /// Emits every active item, alphabetically.
  Stream<List<Item>> watchAll();

  /// Emits active items measuring [category].
  Stream<List<Item>> watchByCategory(UnitCategory category);

  /// Emits favourited items.
  Stream<List<Item>> watchFavorites();

  /// Emits active items whose name matches [term], for the picker's search field.
  Stream<List<Item>> watchMatching(String term);

  /// Reads one item by id, soft-deleted ones included.
  Future<Item?> byId(String id);

  /// Reads the item whose identity is `(normalizedName, category)`, or null if none exists.
  ///
  /// Identity is the pair together: `Milk (Weight)` and `Milk (Volume)` are different items, so a
  /// name that matches under a *different* category is correctly not a match (anomaly A06).
  Future<Item?> findByIdentity({
    required String normalizedName,
    required UnitCategory unitCategory,
  });

  /// Finds active items whose names are close to [name] within [category], for the
  /// "Add to existing Tomato?" suggestion.
  ///
  /// **Suggestions only, never an automatic merge.** Silent fuzzy merging corrupts data in ways a
  /// user cannot easily notice or undo, so only an exact normalized match merges (anomaly A07).
  Future<List<Item>> findSimilar({
    required String name,
    required UnitCategory unitCategory,
  });

  /// Emits every item's stock rollup.
  Stream<List<ItemStock>> watchAllStock();

  /// Emits one item's stock rollup.
  Stream<ItemStock?> watchStockOf(String itemId);

  /// Emits every item currently below its low-stock threshold.
  Stream<List<ItemStock>> watchLowStock();

  /// Creates or updates an item.
  ///
  /// **Rejects a change to `unitCategory` on an existing item** with a [BusinessRuleFailure]
  /// (Law L8): changing it would silently reinterpret every quantity ever recorded against the
  /// item. Rejects a duplicate identity with a [ConflictFailure].
  /// How many live items are filed under [kindTagId] as their kind.
  ///
  /// **Asked before a kind is deleted, so the confirmation can state what it costs.** A kind is
  /// `items.kind_tag_id`; soft-deleting the tag would leave those items pointing at a row no scoped query
  /// returns, and they would drop out of every group into "No kind". The count is what turns that from a
  /// surprise into a sentence.
  ///
  /// Zero for a tag no item uses, which is every non-inventory tag — so deleting `Rent` says nothing about
  /// items and reads exactly as it always did.
  Future<int> countByKind(String kindTagId);

  /// Moves every live item from [fromTagId] to [toTagId], returning how many moved.
  ///
  /// **One statement, and it must run before the old kind is deleted.** Deleting first would leave any item
  /// the move missed pointing at a soft-deleted row with no way to recover which kind it had — the tag is
  /// gone by then. This way a failure leaves both the kind and its items intact.
  ///
  /// **This is where a kind's delete path diverges from a tag's, deliberately.** A soft-deleted transaction
  /// tag is correct as it stands: the transaction happened and was tagged that way, and rendering it greyed
  /// keeps history readable (ARCH_3 §4). An item is *current* — a reference to a deleted tag is not a fact
  /// about the past, it is an item with no working kind.
  Future<Result<int, Failure>> reassignKind({
    required String fromTagId,
    required String toTagId,
  });

  Future<Result<Item, Failure>> save(Item item);

  /// Toggles the favourite flag.
  Future<Result<void, Failure>> setFavorite({
    required String id,
    required bool isFavorite,
  });

  /// Soft-deletes an item and its batches.
  ///
  /// Cascades to batches — deliberately, and unlike deleting a transaction. Deleting an *item*
  /// removes the thing the batches describe; deleting a *transaction* removes only a receipt. The
  /// movement ledger is untouched either way (Law L6's exception).
  Future<Result<void, Failure>> delete(String id);
}
