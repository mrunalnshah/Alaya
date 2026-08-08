import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/tag_dao.dart';
import 'package:alaya/data/repositories/mappers/tag_mapper.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/repositories/tag_repository.dart';

/// `TagRepository` backed by `TagDao`.
final class TagRepositoryImpl implements TagRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const TagRepositoryImpl(this._dao, this._clock);

  final TagDao _dao;
  final Clock _clock;

  @override
  Stream<List<Tag>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Tag>> watchByScope(TagScope scope) => _dao
      .watchByScope(scope)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Tag>> watchRoots() =>
      _dao.watchRoots().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Tag>> watchChildren(String parentTagId) => _dao
      .watchChildrenOf(parentTagId)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Tag?> byId(String id) async =>
      (await _dao.byIdIncludingDeleted(id))?.toEntity();

  @override
  Future<Result<Tag, Failure>> save(Tag tag) async {
    final existing = await _dao.byIdIncludingDeleted(tag.id);

    if (existing == null) {
      final duplicate = await _dao.byNormalizedName(tag.normalizedName);
      if (duplicate != null) {
        return Result.failure(
          ConflictFailure('A tag named "${tag.name}" already exists.'),
        );
      }
    }

    final parentId = tag.parentTagId;
    if (parentId != null) {
      if (parentId == tag.id) {
        return const Result.failure(
          BusinessRuleFailure(
            'A tag cannot be its own parent.',
            rule: 'tagSelfParent',
          ),
        );
      }
      final parent = await _dao.byIdIncludingDeleted(parentId);
      if (parent == null) {
        return const Result.failure(
          ValidationFailure(
            'The chosen parent tag does not exist.',
            field: 'parentTagId',
          ),
        );
      }
      // Nesting is capped at exactly one level (ARCH_2 §3): a root has no parent, a child's
      // parent must itself be a root. If the parent already has a parent, saving `tag` under it
      // would create a third level.
      if (parent.parentTagId != null) {
        return Result.failure(
          BusinessRuleFailure(
            'Tags can only be nested one level deep — "$parentId"\'s parent already has a '
            'parent of its own.',
            rule: 'tagNestingTooDeep',
          ),
        );
      }
    }

    // Preserve deletedAt unless `tag.isDeleted` explicitly disagrees with the current state —
    // the same pattern as createdAt, but for a field this entity's own doc calls out as real,
    // writable state (unlike every other entity in this phase).
    final existingDeletedAt = existing?.deletedAt;
    final now = _clock.nowUtcMillis();
    final createdAt = existing?.createdAt ?? now;
    final deletedAt = tag.isDeleted ? (existingDeletedAt ?? now) : null;

    await _dao.upsert(
      tagToCompanion(
        tag,
        createdAt: createdAt,
        updatedAt: now,
        deletedAt: deletedAt,
      ),
    );
    return Result.ok(tag);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    final rowsChanged = await _dao.softDeleteUserTag(
      id: id,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    if (rowsChanged == 0) {
      return const Result.failure(
        BusinessRuleFailure(
          'System tags cannot be deleted.',
          rule: 'systemProtected',
        ),
      );
    }
    return const Result.ok(null);
  }

  @override
  Stream<List<Tag>> watchForTransaction(String transactionId) => _dao
      .watchForTransaction(transactionId)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<void, Failure>> setForTransaction({
    required String transactionId,
    required List<String> tagIds,
  }) async {
    await _dao.setTransactionTags(
      transactionId: transactionId,
      tagIds: tagIds,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Stream<List<Tag>> watchForItem(String itemId) => _dao
      .watchForItem(itemId)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<void, Failure>> setForItem({
    required String itemId,
    required List<String> tagIds,
  }) async {
    await _dao.setItemTags(
      itemId: itemId,
      tagIds: tagIds,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Stream<List<Tag>> watchForAsset(String assetId) => _dao
      .watchForAsset(assetId)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<void, Failure>> setForAsset({
    required String assetId,
    required List<String> tagIds,
  }) async {
    await _dao.setAssetTags(
      assetId: assetId,
      tagIds: tagIds,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }
}
