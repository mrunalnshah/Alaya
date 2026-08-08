import 'package:drift/drift.dart';

import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `tags` and the `transaction_tags` link table.
class TagDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  TagDao(super.db);

  $TagsTable get _tags => attachedDatabase.tags;
  $TransactionTagsTable get _links => attachedDatabase.transactionTags;
  $ItemTagsTable get _itemLinks => attachedDatabase.itemTags;
  $AssetTagsTable get _assetLinks => attachedDatabase.assetTags;

  SimpleSelectStatement<$TagsTable, TagRow> _activeRows() =>
      select(_tags)..where((t) => t.deletedAt.isNull());

  /// Maps a [TagScope] onto the matching `allowedIn*` column.
  ///
  /// The single place the scope vocabulary meets the schema. Six near-identical query methods
  /// would be the alternative, and each would be a chance to filter on the wrong column — which
  /// is exactly the bug that would put "Kitchen" in the deposit picker (ARCH_2 §14).
  Expression<bool> _scopeColumn($TagsTable t, TagScope scope) =>
      switch (scope) {
        TagScope.deposit => t.allowedInDeposit,
        TagScope.withdrawal => t.allowedInWithdrawal,
        TagScope.inventory => t.allowedInInventory,
        TagScope.shopping => t.allowedInShopping,
        TagScope.recurring => t.allowedInRecurring,
        TagScope.service => t.allowedInService,
      };

  /// Emits every active tag in display order.
  Stream<List<TagRow>> watchAll() =>
      (_activeRows()..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
          .watch();

  /// Emits the active tags offered in [scope]'s picker.
  Stream<List<TagRow>> watchByScope(TagScope scope) {
    return (_activeRows()
          ..where((t) => _scopeColumn(t, scope).equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Reads one tag by id, including a soft-deleted one.
  ///
  /// Deliberately unfiltered: a deleted tag's links survive so history stays readable, and the UI
  /// renders it greyed with `(deleted)` (anomaly A36). Every *listing* query filters; this
  /// single-row lookup must not, or old transactions would show a blank chip.
  Future<TagRow?> byIdIncludingDeleted(String id) =>
      (select(_tags)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads one active tag by its normalized name, for the merge-or-create decision.
  Future<TagRow?> byNormalizedName(String normalizedName) =>
      (_activeRows()..where((t) => t.normalizedName.equals(normalizedName)))
          .getSingleOrNull();

  /// Emits the active children of [parentTagId].
  Stream<List<TagRow>> watchChildrenOf(String parentTagId) {
    return (_activeRows()
          ..where((t) => t.parentTagId.equals(parentTagId))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Emits the active top-level tags — those with no parent.
  Stream<List<TagRow>> watchRoots() {
    return (_activeRows()
          ..where((t) => t.parentTagId.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Inserts or updates a tag.
  Future<void> upsert(TagsCompanion tag) =>
      into(_tags).insertOnConflictUpdate(tag);

  /// Soft-deletes a user-created tag.
  ///
  /// Returns 0 rows changed for a system tag; like [UnitDao.softDeleteUserUnit] the guard is a
  /// `WHERE` clause rather than a caller-side check, so it cannot be forgotten (ARCH_3 §4.1).
  Future<int> softDeleteUserTag({
    required String id,
    required int nowUtcMillis,
  }) {
    return (update(
      _tags,
    )..where((t) => t.id.equals(id) & t.isSystem.equals(false))).write(
      TagsCompanion(
        deletedAt: Value(nowUtcMillis),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  // ── transaction_tags links ─────────────────────────────────────────────────────────────

  /// Emits the tags attached to [transactionId], soft-deleted ones included.
  ///
  /// Includes deleted tags for the same reason as [byIdIncludingDeleted]: the link is history.
  Stream<List<TagRow>> watchForTransaction(String transactionId) {
    final query =
        select(_links).join([
            innerJoin(_tags, _tags.id.equalsExp(_links.tagId)),
          ])
          ..where(_links.transactionId.equals(transactionId))
          ..orderBy([OrderingTerm(expression: _tags.sortOrder)]);
    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(_tags)).toList(),
    );
  }

  /// Replaces the whole tag set for [transactionId], in one transaction (Law L14).
  ///
  /// Delete-then-insert rather than a diff: `transaction_tags` has no soft delete, so removing a
  /// link is a real delete and a set replacement is the honest operation. Both statements are in
  /// one transaction so a failure cannot leave a transaction with no tags at all.
  Future<void> setTransactionTags({
    required String transactionId,
    required List<String> tagIds,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      await (delete(
        _links,
      )..where((t) => t.transactionId.equals(transactionId))).go();
      for (final tagId in tagIds) {
        await into(_links).insert(
          TransactionTagsCompanion.insert(
            transactionId: transactionId,
            tagId: tagId,
            createdAt: nowUtcMillis,
            updatedAt: nowUtcMillis,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  /// Emits the tags attached to [itemId], in tag sort order.
  ///
  /// **`item_tags` was created in Phase 2C and had no reader until now.** Phase 6B needed it to group a
  /// catalogue and shipped grouping by `itemKind` instead; the row has been open in ARCH_5 §7.3 ever
  /// since. The shape is `watchForTransaction`'s exactly — one join, ordered by the tag rather than the
  /// link, so the ordering a user set in Settings is the ordering they see everywhere.
  Stream<List<TagRow>> watchForItem(String itemId) {
    final query =
        select(_itemLinks).join([
            innerJoin(_tags, _tags.id.equalsExp(_itemLinks.tagId)),
          ])
          ..where(_itemLinks.itemId.equals(itemId))
          ..orderBy([OrderingTerm(expression: _tags.sortOrder)]);
    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(_tags)).toList(),
    );
  }

  /// Replaces the tags attached to [itemId] with [tagIds].
  ///
  /// **Delete-then-insert inside one transaction, as `setTransactionTags` does.** A diff would be fewer
  /// writes and more code, and the link table carries nothing worth preserving — no id of its own, no
  /// audit trail anyone reads, and a composite primary key that makes re-insertion idempotent. Law L6's
  /// soft-delete rule governs entities, not the join rows that associate them.
  Future<void> setItemTags({
    required String itemId,
    required List<String> tagIds,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      await (delete(_itemLinks)..where((t) => t.itemId.equals(itemId))).go();
      for (final tagId in tagIds) {
        await into(_itemLinks).insert(
          ItemTagsCompanion.insert(
            itemId: itemId,
            tagId: tagId,
            createdAt: nowUtcMillis,
            updatedAt: nowUtcMillis,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  /// Emits the tags attached to [assetId], in tag sort order.
  ///
  /// `asset_tags` has been open since Phase 6E for the same reason `item_tags` was: the table existed and
  /// the contract did not, so the asset list groups by `type` instead.
  Stream<List<TagRow>> watchForAsset(String assetId) {
    final query =
        select(_assetLinks).join([
            innerJoin(_tags, _tags.id.equalsExp(_assetLinks.tagId)),
          ])
          ..where(_assetLinks.assetId.equals(assetId))
          ..orderBy([OrderingTerm(expression: _tags.sortOrder)]);
    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(_tags)).toList(),
    );
  }

  /// Replaces the tags attached to [assetId] with [tagIds].
  Future<void> setAssetTags({
    required String assetId,
    required List<String> tagIds,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      await (delete(_assetLinks)..where((t) => t.assetId.equals(assetId))).go();
      for (final tagId in tagIds) {
        await into(_assetLinks).insert(
          AssetTagsCompanion.insert(
            assetId: assetId,
            tagId: tagId,
            createdAt: nowUtcMillis,
            updatedAt: nowUtcMillis,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  /// Counts how many active transactions carry [tagId], for the "in use" check before deleting.
  Future<int> activeTransactionCount(String tagId) async {
    final count = countAll();
    final row =
        await (selectOnly(_links).join([
                innerJoin(
                  attachedDatabase.transactions,
                  attachedDatabase.transactions.id.equalsExp(
                    _links.transactionId,
                  ),
                ),
              ])
              ..addColumns([count])
              ..where(
                _links.tagId.equals(tagId) &
                    attachedDatabase.transactions.deletedAt.isNull(),
              ))
            .getSingle();
    return row.read(count) ?? 0;
  }
}
