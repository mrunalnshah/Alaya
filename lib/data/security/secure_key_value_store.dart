import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The small slice of key-value storage the app lock needs.
///
/// An interface rather than a direct `FlutterSecureStorage` dependency, for the same reason [Clock]
/// exists: the plugin needs a platform channel, so code depending on it directly is untestable
/// without one. Three methods is the whole surface the lock uses, so widening it would only invite
/// coupling to a plugin this project should be able to swap.
abstract interface class SecureKeyValueStore {
  /// Reads [key], or null when absent.
  Future<String?> read(String key);

  /// Writes [value] against [key].
  Future<void> write(String key, String value);

  /// Removes [key].
  Future<void> delete(String key);
}

/// The production [SecureKeyValueStore], backed by the platform keystore.
final class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  /// Creates a store over [storage].
  const FlutterSecureKeyValueStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// An in-memory [SecureKeyValueStore] for tests.
///
/// Lives beside the production implementation rather than in the test tree, mirroring how
/// `FixedClock` ships alongside `SystemClock`: a fake that drifts from the interface it doubles is
/// worse than no fake, and keeping them in one file makes that drift visible.
final class InMemorySecureKeyValueStore implements SecureKeyValueStore {
  /// Creates an empty store.
  InMemorySecureKeyValueStore();

  final Map<String, String> _values = {};

  /// Every key currently held — what a test asserting "no lock secret reaches the database" inspects.
  Iterable<String> get keys => _values.keys;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
