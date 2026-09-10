import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/analytics_cache_dao.dart';
import 'package:alaya/domain/repositories/analytics_cache_repository.dart';

/// `AnalyticsCacheRepository` backed by `AnalyticsCacheDao`.
///
/// **This is where the contract's `Duration` meets the DAO's absolute millis.** The DAO takes
/// `nowUtcMillis` and `staleAfterUtcMillis` so it stays assertable under a `FixedClock` — the rule
/// every read in this schema follows (ARCH_2 §12.2) — while the domain contract speaks a TTL and
/// knows nothing about a clock. Holding the `Clock` here is the whole of this class's job, and it is
/// why it is worth existing rather than having `AnalyticsCacheService` talk to the DAO directly:
/// that would put a `data/` import in `domain/` and break Law L12.
///
/// **The eviction problem the DAO's own doc comment warns about is already solved upstream.** Both
/// the DAO and the contract note that `cacheKey` is the sole primary key, so caching July would
/// evict June, and both defer the fix to a caller folding the params hash into the key.
/// `AnalyticsCacheService.keyFor` returns `'$queryName:$paramsHash'`, which is exactly that — so each
/// parameter set already owns a row and no schema change is needed (ARCH_4 §5.1 item 12).
final class AnalyticsCacheRepositoryImpl implements AnalyticsCacheRepository {
  /// Creates the repository over [dao], stamping and expiring entries with [clock].
  const AnalyticsCacheRepositoryImpl(this._dao, this._clock);

  final AnalyticsCacheDao _dao;
  final Clock _clock;

  @override
  Future<String?> read({
    required String cacheKey,
    required String paramsHash,
  }) {
    return _dao.read(
      cacheKey: cacheKey,
      paramsHash: paramsHash,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
  }

  @override
  Future<void> write({
    required String cacheKey,
    required String paramsHash,
    required String payloadJson,
    required Duration ttl,
  }) {
    final now = _clock.nowUtcMillis();
    return _dao.write(
      cacheKey: cacheKey,
      paramsHash: paramsHash,
      payloadJson: payloadJson,
      computedAtUtcMillis: now,
      // One clock reading for both, not two calls: a `computedAt` and a `staleAfter` derived from
      // different instants would drift by however long the write took, which is invisible and
      // pointless.
      staleAfterUtcMillis: now + ttl.inMilliseconds,
    );
  }

  @override
  Future<void> invalidate(String cacheKey) {
    return _dao.invalidate(
      cacheKey: cacheKey,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
  }

  @override
  Future<void> invalidateAll() async {
    // `await`ed rather than returned: the DAO reports how many rows it tombstoned and the contract
    // returns nothing, so `Future<int>` does not satisfy `Future<void>` without this.
    await _dao.invalidateAll(nowUtcMillis: _clock.nowUtcMillis());
  }
}
