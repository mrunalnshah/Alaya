/// An in-memory [SettingsRepository] for widget tests.
///
/// **Needed because a notifier may read settings during `build`.** `InsightSideNotifier.build` restores
/// the insight card's side from `app_settings`, so any scope that mounts the card and leaves
/// `settingsRepositoryProvider` un-overridden resolves `databaseProvider`, which throws by design
/// (Law L10). The symptom is a `StateError` about the database in a test that never mentions one, which
/// reads as a product bug and is not (ARCH_6 P6).
///
/// Kept in `test/support/` rather than inside one harness because two suites need it — the dashboard
/// harness and `layout_overflow_test.dart` — and a fake written twice is a fake that will disagree with
/// itself (ARCH_4 R25, one layer down).
library;

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';

/// Key/value settings held in a map, with writes readable back.
class FakeSettingsRepository implements SettingsRepository {
  /// Creates a store seeded with [values].
  ///
  /// [homeCurrencyCode] and [defaultAccountId] are separate rather than map entries so the fake does not
  /// have to know `SettingsKeys`' spelling — a test asserting on a key it guessed wrong passes for the
  /// wrong reason.
  FakeSettingsRepository({
    Map<String, String>? values,
    this.homeCurrencyCode = 'INR',
    this.defaultAccountId,
  }) : _values = {...?values};

  final Map<String, String> _values;

  /// What `readHomeCurrencyCode` answers.
  final String? homeCurrencyCode;

  /// What `readDefaultAccountId` answers.
  final String? defaultAccountId;

  /// Everything written so far, so a test can assert a preference was actually persisted.
  Map<String, String> get values => Map.unmodifiable(_values);

  @override
  Future<String?> readValue(String key) async => _values[key];

  @override
  Stream<String?> watchValue(String key) => Stream.value(_values[key]);

  @override
  Stream<Map<String, String>> watchAll() => Stream.value(values);

  @override
  Future<Result<void, Failure>> writeValue({
    required String key,
    required String value,
    required String valueType,
  }) async {
    _values[key] = value;
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> remove(String key) async {
    _values.remove(key);
    return const Result.ok(null);
  }

  // Phase 8A added `writeHomeCurrencyCode` to the contract, so this fake stopped satisfying it. Routed
  // through `writeValue` like the real implementation, so a test asserting on the stored key sees the same
  // row either way.
  @override
  Future<Result<void, Failure>> writeHomeCurrencyCode(String code) =>
      writeValue(key: 'homeCurrencyCode', value: code, valueType: 'string');

  @override
  Future<String?> readHomeCurrencyCode() async => homeCurrencyCode;

  @override
  Future<String?> readDefaultAccountId() async => defaultAccountId;
}
