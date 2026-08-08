import 'dart:convert';

import 'package:alaya/domain/repositories/analytics_cache_repository.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';

/// Caches expensive analytics results, keyed by query name and its parameters (ARCH_3 §5.2).
///
/// **Only worth it above roughly 200 ms.** A cache on a query that already runs in 5 ms costs a read,
/// a write, an invalidation path and a staleness bug, and buys nothing — so `shouldCache` is a
/// deliberate gate rather than a policy applied to everything.
final class AnalyticsCacheService {
  /// Creates the service over [repository].
  const AnalyticsCacheService(this._repository);

  final AnalyticsCacheRepository _repository;

  /// How long a cached result stays valid.
  ///
  /// Six hours, not minutes: every contributing write invalidates the cache explicitly
  /// ([invalidateOnWrite]), so the TTL is only a backstop for the case where an invalidation was
  /// missed. Making it short would mean recomputing constantly to defend against a bug that should
  /// be fixed rather than papered over.
  static const Duration defaultTtl = Duration(hours: 6);

  /// The estimated cost above which caching earns its keep.
  static const Duration cacheThreshold = Duration(milliseconds: 200);

  /// Whether a query taking [estimatedCost] should be cached at all.
  bool shouldCache(Duration estimatedCost) => estimatedCost >= cacheThreshold;

  /// The cache key for [queryName] with [params].
  ///
  /// The params hash is folded **into the key**, not stored beside it. ARCH_2 §9 makes `cacheKey` the
  /// primary key on its own, so two parameter sets sharing a key would evict each other — caching
  /// July would drop June, and alternating between two date ranges would recompute every time. Making
  /// the key `queryName:paramsHash` gives each parameter set its own row with no schema change, which
  /// is the resolution ARCH_4 §5.1 item 12 recommends.
  String keyFor(String queryName, Map<String, Object?> params) =>
      '$queryName:${hashParams(params)}';

  /// A stable hash of [params].
  ///
  /// Keys are sorted before encoding, because Dart map iteration order follows insertion order — two
  /// callers passing the same parameters in a different order would otherwise produce different
  /// hashes and each miss the other's cache entry.
  String hashParams(Map<String, Object?> params) {
    final sorted = params.keys.toList()..sort();
    final canonical = {for (final key in sorted) key: _stringify(params[key])};
    final encoded = jsonEncode(canonical);
    // A stable non-cryptographic digest. This identifies a parameter set; it defends nothing, so a
    // real hash function would be cost without benefit.
    var hash = 0;
    for (final unit in encoded.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return hash.toRadixString(16);
  }

  /// The window's contribution to a params map, in a form [hashParams] can encode.
  Map<String, Object?> windowParams(AnalyticsWindow window) => {
    'from': window.from.value,
    'to': window.to.value,
  };

  /// Reads a cached payload, or null on a miss.
  Future<String?> read({
    required String queryName,
    required Map<String, Object?> params,
  }) {
    final key = keyFor(queryName, params);
    return _repository.read(cacheKey: key, paramsHash: hashParams(params));
  }

  /// Stores [payload] for [queryName] with [params].
  Future<void> write({
    required String queryName,
    required Map<String, Object?> params,
    required String payload,
    Duration ttl = defaultTtl,
  }) {
    final key = keyFor(queryName, params);
    return _repository.write(
      cacheKey: key,
      paramsHash: hashParams(params),
      payloadJson: payload,
      ttl: ttl,
    );
  }

  /// Computes through the cache: returns the cached payload when present, otherwise runs [compute],
  /// stores it, and returns it.
  ///
  /// A failure to read or write the cache never fails the query — a cache is an optimisation, and a
  /// broken one should slow the app down rather than break the analytics screen.
  Future<String> readOrCompute({
    required String queryName,
    required Map<String, Object?> params,
    required Future<String> Function() compute,
    Duration ttl = defaultTtl,
  }) async {
    try {
      final cached = await read(queryName: queryName, params: params);
      if (cached != null) return cached;
    } catch (_) {
      // Fall through and compute.
    }
    final fresh = await compute();
    try {
      await write(
        queryName: queryName,
        params: params,
        payload: fresh,
        ttl: ttl,
      );
    } catch (_) {
      // The caller still gets its answer.
    }
    return fresh;
  }

  /// Invalidates everything, which is what any write to a contributing table triggers.
  ///
  /// Coarse on purpose. Tracking which of the twenty-four queries a given row touches would be a
  /// dependency graph to maintain and get wrong; recomputing on the next open is cheap by comparison,
  /// and a stale figure on a money screen is the one outcome worth spending correctness on.
  Future<void> invalidateOnWrite() => _repository.invalidateAll();

  /// Invalidates one query's entries.
  Future<void> invalidate({
    required String queryName,
    required Map<String, Object?> params,
  }) => _repository.invalidate(keyFor(queryName, params));

  String _stringify(Object? value) => switch (value) {
    null => 'null',
    final bool v => v.toString(),
    final num v => v.toString(),
    final String v => v,
    final Iterable<Object?> v => v.map(_stringify).join(','),
    _ => value.toString(),
  };
}
