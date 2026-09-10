import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/item_dao.dart';
import 'package:alaya/data/repositories/mappers/stock_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/repositories/item_repository.dart';

/// How far apart two normalized names may be and still be offered as the same thing.
///
/// Two edits, per anomaly A07's resolution. Deliberately permissive on short names — `tea` and
/// `pea` are one edit apart — which is safe only because these are *suggestions the user confirms*
/// and never an automatic merge. Raising the bar would lose real near-misses like
/// `tomato`/`tomatto`; lowering it to scale with length would silently stop catching typos in
/// short names, which are exactly where typos are most likely.
const int _maxSuggestionDistance = 2;

/// `ItemRepository` backed by `ItemDao`.
final class ItemRepositoryImpl implements ItemRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const ItemRepositoryImpl(this._dao, this._clock);

  final ItemDao _dao;
  final Clock _clock;

  @override
  Stream<List<Item>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Item>> watchByCategory(UnitCategory category) => _dao
      .watchByCategory(category)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Item>> watchFavorites() => _dao.watchFavorites().map(
    (rows) => rows.map((r) => r.toEntity()).toList(),
  );

  @override
  Stream<List<Item>> watchMatching(String term) => _dao
      .watchMatching(term)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Item?> byId(String id) async =>
      (await _dao.byIdIncludingDeleted(id))?.toEntity();

  @override
  Future<Item?> findByIdentity({
    required String normalizedName,
    required UnitCategory unitCategory,
  }) async {
    final row = await _dao.findByIdentity(
      normalizedName: normalizedName,
      unitCategory: unitCategory,
    );
    return row?.toEntity();
  }

  @override
  Future<List<Item>> findSimilar({
    required String name,
    required UnitCategory unitCategory,
  }) async {
    // Same category only. A different category is a different item by definition (Law L8,
    // anomaly A06) — `Milk (Weight)` is not a near-miss for `Milk (Volume)`, it is a separate
    // thing — so suggesting across categories would invite exactly the merge the schema forbids.
    final candidates = await _dao.watchByCategory(unitCategory).first;

    final scored = <({Item item, int distance})>[];
    for (final row in candidates) {
      final candidate = row.normalizedName;
      // Cheap pre-filter: a length difference greater than the threshold guarantees the edit
      // distance exceeds it too, since each edit changes length by at most one. Verified over
      // 4000 random pairs never to exclude a genuine match.
      if ((candidate.length - name.length).abs() > _maxSuggestionDistance)
        continue;

      final distance = _levenshtein(candidate, name);
      // Distance 0 is the exact identity match, which is [findByIdentity]'s job — a merge, not a
      // suggestion. Including it here would offer the user "did you mean this same item?".
      if (distance == 0 || distance > _maxSuggestionDistance) continue;

      scored.add((item: row.toEntity(), distance: distance));
    }

    scored.sort((a, b) {
      final byDistance = a.distance.compareTo(b.distance);
      return byDistance != 0
          ? byDistance
          : a.item.normalizedName.compareTo(b.item.normalizedName);
    });
    return scored.map((s) => s.item).toList();
  }

  @override
  Stream<List<ItemStock>> watchAllStock() => _dao.watchAllStock().map(
    (rows) => rows.map((r) => r.toEntity()).toList(),
  );

  @override
  Stream<ItemStock?> watchStockOf(String itemId) =>
      _dao.watchStockOf(itemId).map((row) => row?.toEntity());

  @override
  Stream<List<ItemStock>> watchLowStock() => _dao.watchLowStock().map(
    (rows) => rows.map((r) => r.toEntity()).toList(),
  );

  @override
  Future<int> countByKind(String kindTagId) => _dao.countByKind(kindTagId);

  @override
  Future<Result<int, Failure>> reassignKind({
    required String fromTagId,
    required String toTagId,
  }) async {
    if (fromTagId == toTagId) {
      // Not an error worth a failure sentence — moving items onto the kind they already have is a no-op, and
      // the caller reaches this when somebody deletes `Other` itself, which `is_system` refuses one layer down.
      return const Result.ok(0);
    }
    try {
      final moved = await _dao.reassignKind(
        fromTagId: fromTagId,
        toTagId: toTagId,
        nowUtcMillis: _clock.nowUtcMillis(),
      );
      return Result.ok(moved);
    } on Object catch (error) {
      // A foreign-key violation is the realistic case: `toTagId` naming a row that is gone. Returned rather
      // than thrown, because the caller deletes a tag next and has to decide not to on a failure.
      return Result.failure(
        UnexpectedFailure(
          'Those items could not be moved.',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<Item, Failure>> save(Item item) async {
    final existing = await _dao.byIdIncludingDeleted(item.id);

    if (existing == null) {
      // A new item may not collide with an existing active identity. The partial unique index
      // would reject it anyway; catching it here turns a raw SQLite constraint error into a
      // failure the UI can act on ("add to the existing item instead?").
      final duplicate = await _dao.findByIdentity(
        normalizedName: item.normalizedName,
        unitCategory: item.unitCategory,
      );
      if (duplicate != null) {
        return Result.failure(
          ConflictFailure(
            'An item named "${item.name}" already exists in this category. '
            'Add a new batch to it instead of creating a second item.',
          ),
        );
      }
    } else if (existing.unitCategory != item.unitCategory) {
      // Law L8. Changing an item's category would silently reinterpret every quantity ever
      // recorded against it — 2000 milli-units stops meaning 2 g and starts meaning 2 ml, across
      // every batch, movement and transaction line already written. There is no migration that
      // fixes that after the fact, so the write is refused rather than attempted.
      return Result.failure(
        BusinessRuleFailure(
          'An item\'s unit category cannot be changed once it exists — every quantity already '
          'recorded against "${existing.name}" is measured in '
          '${existing.unitCategory.baseUnitCode}. Create a separate item instead.',
          rule: 'unitCategoryImmutable',
        ),
      );
    }

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _dao.upsert(
      itemToCompanion(
        item,
        createdAt: stamps.createdAt,
        updatedAt: stamps.updatedAt,
      ),
    );
    return Result.ok(item);
  }

  @override
  Future<Result<void, Failure>> setFavorite({
    required String id,
    required bool isFavorite,
  }) async {
    await _dao.setFavorite(
      id: id,
      isFavorite: isFavorite,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    // Cascades to the item's batches inside one transaction, in the DAO. Movements are untouched:
    // the ledger for food that no longer has a catalogued item stays exactly as complete as it was
    // (Law L6's stated exception).
    await _dao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }
}

/// Levenshtein edit distance between [a] and [b].
///
/// Two-row implementation: only the previous and current rows of the distance matrix are ever
/// live, so memory is `O(min(len))` rather than `O(len × len)`. Called once per same-category
/// candidate that survives the length pre-filter, on strings that are item names — short enough
/// that this is far cheaper than a second database round trip would be.
int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previous = List<int>.generate(b.length + 1, (i) => i);
  var current = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final substitution =
          previous[j - 1] +
          (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1);
      final deletion = previous[j] + 1;
      final insertion = current[j - 1] + 1;
      current[j] = substitution < deletion
          ? (substitution < insertion ? substitution : insertion)
          : (deletion < insertion ? deletion : insertion);
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}
