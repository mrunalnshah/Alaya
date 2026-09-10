import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/entities/tag.dart';

/// Reads and writes tags, and their links to transactions.
abstract interface class TagRepository {
  /// Emits every active tag in display order.
  Stream<List<Tag>> watchAll();

  /// Emits the tags offered in [scope]'s picker.
  ///
  /// Scoping is the whole point: a `Kitchen` tag created for inventory and shopping must not appear
  /// in the deposit picker (ARCH_2 §14).
  Stream<List<Tag>> watchByScope(TagScope scope);

  /// Emits the active top-level tags — those with no parent.
  Stream<List<Tag>> watchRoots();

  /// Emits the active children of [parentTagId].
  Stream<List<Tag>> watchChildren(String parentTagId);

  /// Reads one tag by id, soft-deleted ones included — a deleted tag still renders on old
  /// transactions, greyed with `(deleted)` (anomaly A36).
  Future<Tag?> byId(String id);

  /// Reads the active tag whose normalized name is [normalizedName], or null.
  ///
  /// **`TagDao` has had this since Phase 1A and no contract exposed it.** It is the merge-or-create lookup:
  /// `idx_tags_name` is unique on `normalized_name`, so this is how a caller learns whether a name is taken
  /// before writing it — which is also why `NewKindSheet` can report "a tag with that name already exists"
  /// rather than a raw conflict.
  ///
  /// Settings needs it for a second reason. Deleting a kind moves its items to `Other`, and `Other` is a
  /// seeded row whose id differs between a fresh install and one upgraded through `from4To5` — so the
  /// fallback has to be found by name. It cannot be missing: `is_system` makes it undeletable, which is the
  /// only reason a fallback can be relied on at all.
  ///
  /// Active only, unlike [byId]. A soft-deleted tag is neither a name collision nor a usable fallback.
  Future<Tag?> byNormalizedName(String normalizedName);

  /// Creates or updates a tag.
  ///
  /// Fails with a [BusinessRuleFailure] when nesting would exceed one level, or a
  /// [ConflictFailure] when another active tag already has the same normalized name.
  Future<Result<Tag, Failure>> save(Tag tag);

  /// Soft-deletes a user-created tag. Fails for a system tag.
  ///
  /// Links survive, so history stays readable.
  Future<Result<void, Failure>> delete(String id);

  /// Emits the tags attached to [transactionId], soft-deleted ones included.
  Stream<List<Tag>> watchForTransaction(String transactionId);

  /// Replaces the whole tag set on [transactionId].
  Future<Result<void, Failure>> setForTransaction({
    required String transactionId,
    required List<String> tagIds,
  });

  /// Emits the tags attached to [itemId], in the order the user arranged them.
  Stream<List<Tag>> watchForItem(String itemId);

  /// Replaces the tags on [itemId] with [tagIds].
  ///
  /// **A set, not a diff.** The caller sends the whole list it wants and the link rows are rewritten to
  /// match — a partial API would need add and remove and an answer for the race between them.
  Future<Result<void, Failure>> setForItem({
    required String itemId,
    required List<String> tagIds,
  });

  /// Emits the tags attached to [assetId], in the order the user arranged them.
  Stream<List<Tag>> watchForAsset(String assetId);

  /// Replaces the tags on [assetId] with [tagIds].
  Future<Result<void, Failure>> setForAsset({
    required String assetId,
    required List<String> tagIds,
  });
}
