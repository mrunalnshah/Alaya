import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `analytics_cache` — memoised results for analytics queries slower than roughly
/// 200 ms (ARCH_3 §5.2). Defined in Phase 1B, first used in Phase 7B.
///
/// **One entry per query name, not per parameter set.** ARCH_2 §9 gives this table a natural
/// primary key of `cacheKey` alone, while ARCH_3 §5.2 describes keying by
/// `(queryName, paramsHash)`. Those cannot both hold: with `cacheKey` as the sole key, storing
/// "spend by subtype for July" evicts "spend by subtype for June". [read] therefore treats a
/// `paramsHash` mismatch as a **miss**, which is correct and safe — a stale entry for different
/// parameters is never returned — but means switching date ranges back and forth recomputes each
/// time rather than hitting the cache.
///
/// If Phase 7B finds that costly, the fix is for the caller to compose `cacheKey` as
/// `'queryName:paramsHash'`, which makes each parameter set its own row with no schema change.
/// That is a Phase 7B decision, so this DAO does not impose it.
class AnalyticsCacheDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  AnalyticsCacheDao(super.db);

  $AnalyticsCacheTable get _table => attachedDatabase.analyticsCache;

  /// Reads the cached payload for [cacheKey], or null on any kind of miss.
  ///
  /// Returns null when the entry is absent, soft-deleted, was computed for a different
  /// [paramsHash], or is stale as of [nowUtcMillis]. Staleness is passed in rather than read from
  /// a clock here, so a caller with an injected `Clock` stays deterministic in tests — the same
  /// rule the views follow (ARCH_2 §12.2).
  Future<String?> read({
    required String cacheKey,
    required String paramsHash,
    required int nowUtcMillis,
  }) async {
    final row = await (select(_table)
      ..where((t) => t.cacheKey.equals(cacheKey) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) return null;
    if (row.paramsHash != paramsHash) return null;
    if (row.staleAfter <= nowUtcMillis) return null;
    return row.payloadJson;
  }

  /// Stores or replaces the cached payload for [cacheKey].
  ///
  /// Upserts on `cacheKey`, which is this table's primary key — so unlike most tables in this
  /// project, drift's default conflict target is exactly the logical key and no explicit target is
  /// needed. Clears `deletedAt` so writing over an invalidated entry revives the row rather than
  /// leaving one [read] will keep filtering out.
  Future<void> write({
    required String cacheKey,
    required String paramsHash,
    required String payloadJson,
    required int computedAtUtcMillis,
    required int staleAfterUtcMillis,
  }) {
    return into(_table).insertOnConflictUpdate(
      AnalyticsCacheCompanion.insert(
        cacheKey: cacheKey,
        paramsHash: paramsHash,
        payloadJson: payloadJson,
        computedAt: computedAtUtcMillis,
        staleAfter: staleAfterUtcMillis,
        createdAt: computedAtUtcMillis,
        updatedAt: computedAtUtcMillis,
        deletedAt: const Value(null),
      ),
    );
  }

  /// Invalidates one cached query by soft-deleting its row.
  ///
  /// Soft rather than hard so the purge job remains the only hard delete in the codebase
  /// (ARCH_3 §4.2), and so [write] can revive the same row instead of accumulating tombstones.
  Future<void> invalidate({required String cacheKey, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.cacheKey.equals(cacheKey))).write(
      AnalyticsCacheCompanion(deletedAt: Value(nowUtcMillis), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Invalidates every cached query — what a write to any contributing table triggers, since
  /// tracking which queries depend on which tables is not worth the bookkeeping at this scale.
  Future<int> invalidateAll({required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.deletedAt.isNull())).write(
      AnalyticsCacheCompanion(deletedAt: Value(nowUtcMillis), updatedAt: Value(nowUtcMillis)),
    );
  }
}