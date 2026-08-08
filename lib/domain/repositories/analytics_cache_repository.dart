/// Reads and writes memoised analytics results.
///
/// Exists as a domain contract because `domain/services/analytics/` consumes it, and Law L12 forbids
/// anything under `domain/` importing from `data/`.
///
/// **One entry per query name, not per parameter set.** The schema's primary key is the cache key
/// alone, so caching "spend by subtype for July" evicts the June entry. [read] treats a parameter
/// mismatch as a miss — safe, but it means alternating between two date ranges recomputes each time.
/// If that proves costly, a caller can fold the parameter hash into [cacheKey] and get a row per
/// parameter set with no schema change.
abstract interface class AnalyticsCacheRepository {
  /// Reads the cached payload, or null when absent, stale, or computed for different parameters.
  Future<String?> read({
    required String cacheKey,
    required String paramsHash,
  });

  /// Stores a payload against [cacheKey], valid for [ttl].
  Future<void> write({
    required String cacheKey,
    required String paramsHash,
    required String payloadJson,
    required Duration ttl,
  });

  /// Invalidates one cached query.
  Future<void> invalidate(String cacheKey);

  /// Invalidates every cached query — what a write to any contributing table triggers.
  Future<void> invalidateAll();
}