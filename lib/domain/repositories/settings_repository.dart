import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// Reads and writes the app's key/value settings.
abstract interface class SettingsRepository {
  /// Emits the value for [key], or null when unset.
  Stream<String?> watchValue(String key);

  /// Reads the value for [key], or null when unset.
  Future<String?> readValue(String key);

  /// Emits every setting as a key/value map.
  Stream<Map<String, String>> watchAll();

  /// Writes [value] against [key].
  Future<Result<void, Failure>> writeValue({
    required String key,
    required String value,
    required String valueType,
  });

  /// Removes [key].
  Future<Result<void, Failure>> remove(String key);

  /// Records the user's chosen home currency code.
  ///
  /// **Added in 8A, as the counterpart to [readHomeCurrencyCode].** Onboarding has to write this key,
  /// and the key itself lives in `data/repositories/settings_keys.dart` — which a feature may not import
  /// (Law L12, and no delivered feature does). The alternative was a duplicated literal in the
  /// onboarding feature that would silently write to a dead key if `data/` ever renamed it. A named
  /// method keeps one definition on the side that owns it.
  Future<Result<void, Failure>> writeHomeCurrencyCode(String code);

  /// The user's chosen home currency code, used for display aggregation only (Law L9).
  Future<String?> readHomeCurrencyCode();

  /// The account quick-add falls back to when no last-used account is known.
  ///
  /// Lives in settings rather than as a column on `Account`, because the schema has no
  /// `isDefault` there — quick-add resolves last-used first, then this (ARCH_2 §4.1).
  Future<String?> readDefaultAccountId();
}
