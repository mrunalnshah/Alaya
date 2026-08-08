import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/settings_dao.dart';
import 'package:alaya/data/repositories/settings_keys.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';

/// `SettingsRepository` backed by `SettingsDao`.
///
/// The two named lookups — [readHomeCurrencyCode], [readDefaultAccountId] — read the fixed keys
/// in [SettingsKeys] that Phase 1C's seed data writes on first launch, so both are populated from
/// the very first run rather than needing an explicit "unset" path.
final class SettingsRepositoryImpl implements SettingsRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const SettingsRepositoryImpl(this._dao, this._clock);

  final SettingsDao _dao;
  final Clock _clock;

  @override
  Stream<String?> watchValue(String key) => _dao.watchValue(key);

  @override
  Future<String?> readValue(String key) => _dao.readValue(key);

  @override
  Stream<Map<String, String>> watchAll() => _dao.watchAll();

  @override
  Future<Result<void, Failure>> writeValue({
    required String key,
    required String value,
    required String valueType,
  }) async {
    await _dao.writeValue(
      key: key,
      value: value,
      valueType: valueType,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> remove(String key) async {
    await _dao.softDelete(key: key, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Future<String?> readHomeCurrencyCode() =>
      _dao.readValue(SettingsKeys.homeCurrencyCode);

  @override
  Future<Result<void, Failure>> writeHomeCurrencyCode(String code) =>
      writeValue(
        key: SettingsKeys.homeCurrencyCode,
        value: code,
        valueType: 'string',
      );

  @override
  Future<String?> readDefaultAccountId() =>
      _dao.readValue(SettingsKeys.defaultAccountId);
}
