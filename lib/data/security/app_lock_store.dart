import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'package:alaya/data/security/secure_key_value_store.dart';

/// Persists the app-lock secrets, and **never** in the database (ARCH_3 §2.1).
///
/// The reason is not secrecy — the database is plaintext by design and a determined reader of the
/// file learns nothing from a PIN hash. The reason is that **restoring a backup must not change your
/// lock.** If the hash lived in the database, importing a friend's export would silently replace
/// your PIN with theirs, and a restore would be able to lock you out of your own install. Secure
/// storage ties the lock to the *install* and the database to the *data*, which is the correct
/// boundary and the one `restore_test.dart` asserts.
///
/// There is **no encryption anywhere in this class**. No `PRAGMA key`, no derived database key, no
/// key wrapping. PBKDF2 is used purely as a slow one-way hash so a stolen `pinHash` cannot be
/// reversed to a four-digit PIN by inspection — the derived bytes are compared and then discarded,
/// never used to decrypt anything.
final class AppLockStore {
  /// Creates the store over [storage].
  ///
  /// [random] is injectable so salts are deterministic in tests. [pbkdf2Iterations] defaults to the
  /// production [iterations] and is lowered only by tests — 310,000 iterations run twenty times over
  /// would make a unit suite take tens of seconds, and what those tests need from the hash is that it
  /// is stable and salt-dependent, not that it is slow. The production value is asserted separately
  /// as a constant so lowering it here cannot silently weaken the real thing.
  AppLockStore({
    required SecureKeyValueStore storage,
    Random? random,
    int? pbkdf2Iterations,
  }) : _storage = storage,
       _random = random ?? Random.secure(),
       _iterations = pbkdf2Iterations ?? iterations;

  final SecureKeyValueStore _storage;
  final Random _random;
  final int _iterations;

  /// PBKDF2 iterations, per ARCH_3 §2.1.
  ///
  /// 310,000 is OWASP's 2023 floor for PBKDF2-HMAC-SHA256. It is deliberately slow: the PIN space is
  /// only 10,000 values at four digits, so the iteration count is doing most of the work that a
  /// longer secret would otherwise do. Lowering it to make unlock feel snappier would be trading the
  /// only real defence this design has.
  static const int iterations = 310000;

  /// Derived key length in bits.
  static const int derivedBits = 256;

  /// Salt length in bytes.
  static const int saltBytes = 16;

  static const String _pinHashKey = 'alaya.lock.pinHash';
  static const String _saltKey = 'alaya.lock.salt';
  static const String _recoveryHashKey = 'alaya.lock.recoveryHash';
  static const String _failedCountKey = 'alaya.lock.failedCount';
  static const String _lockedUntilKey = 'alaya.lock.lockedUntilUtcMillis';
  static const String _pinLengthKey = 'alaya.lock.pinLength';

  /// True when a lock is configured.
  Future<bool> get isEnabled async =>
      (await _storage.read(_pinHashKey)) != null;

  /// How many digits the configured PIN has — 4 by default, 6 if the user chose it.
  Future<int> readPinLength() async {
    final raw = await _storage.read(_pinLengthKey);
    return int.tryParse(raw ?? '') ?? 4;
  }

  /// Derives the hash of [secret] against [salt].
  ///
  /// Public so `PinService` can verify without this class needing to know about attempt counting,
  /// and so a test can assert that the same input yields the same bytes.
  Future<String> deriveHash({
    required String secret,
    required List<int> salt,
  }) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: derivedBits,
    );
    final key = await pbkdf2.deriveKeyFromPassword(
      password: secret,
      nonce: salt,
    );
    return base64Encode(await key.extractBytes());
  }

  /// A fresh random salt.
  List<int> newSalt() =>
      List<int>.generate(saltBytes, (_) => _random.nextInt(256));

  /// Stores a new lock: [pin] and [recoveryCode], both hashed against one freshly generated salt.
  ///
  /// One salt for both is intentional. They are separate secrets with separate hashes, and a shared
  /// salt only matters if an attacker could benefit from a rainbow table spanning both — which it
  /// cannot, because the salt is random per install and never reused elsewhere.
  Future<void> writeLock({
    required String pin,
    required String recoveryCode,
    int pinLength = 4,
  }) async {
    final salt = newSalt();
    final pinHash = await deriveHash(secret: pin, salt: salt);
    final recoveryHash = await deriveHash(secret: recoveryCode, salt: salt);

    await _storage.write(_saltKey, base64Encode(salt));
    await _storage.write(_pinHashKey, pinHash);
    await _storage.write(_recoveryHashKey, recoveryHash);
    await _storage.write(_pinLengthKey, pinLength.toString());
    await resetFailures();
  }

  /// Replaces the PIN hash, reusing the existing salt and leaving the recovery hash untouched.
  ///
  /// Reusing the salt is what keeps the recovery code valid across a PIN change — a new salt would
  /// invalidate the recovery hash derived against the old one, silently, and the user would discover
  /// it only when they needed it.
  Future<void> writeNewPin({required String pin, int? pinLength}) async {
    final salt = await readSalt();
    if (salt == null) return;
    await _storage.write(
      _pinHashKey,
      await deriveHash(secret: pin, salt: salt),
    );
    if (pinLength != null) {
      await _storage.write(_pinLengthKey, pinLength.toString());
    }
    await resetFailures();
  }

  /// The stored salt, or null when no lock is configured.
  Future<List<int>?> readSalt() async {
    final raw = await _storage.read(_saltKey);
    return raw == null ? null : base64Decode(raw);
  }

  /// The stored PIN hash, or null when no lock is configured.
  Future<String?> readPinHash() => _storage.read(_pinHashKey);

  /// The stored recovery-code hash, or null when no lock is configured.
  Future<String?> readRecoveryHash() => _storage.read(_recoveryHashKey);

  /// Removes every lock secret and resets the attempt counter.
  Future<void> clearLock() async {
    await _storage.delete(_pinHashKey);
    await _storage.delete(_saltKey);
    await _storage.delete(_recoveryHashKey);
    await _storage.delete(_pinLengthKey);
    await resetFailures();
  }

  /// How many consecutive wrong attempts have been recorded.
  Future<int> readFailedCount() async {
    final raw = await _storage.read(_failedCountKey);
    return int.tryParse(raw ?? '') ?? 0;
  }

  /// Records one more wrong attempt and returns the new count.
  Future<int> incrementFailedCount() async {
    final next = (await readFailedCount()) + 1;
    await _storage.write(_failedCountKey, next.toString());
    return next;
  }

  /// Clears the attempt counter and any active lockout.
  Future<void> resetFailures() async {
    await _storage.delete(_failedCountKey);
    await _storage.delete(_lockedUntilKey);
  }

  /// When the current lockout expires, or null when there is none.
  ///
  /// Stored as an absolute instant rather than a remaining duration, so backgrounding the app or
  /// killing it does not reset the wait — a countdown held in memory would make the throttle
  /// trivially bypassable.
  Future<DateTime?> readLockedUntilUtc() async {
    final raw = await _storage.read(_lockedUntilKey);
    final millis = int.tryParse(raw ?? '');
    return millis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  /// Sets the instant the current lockout expires.
  Future<void> writeLockedUntilUtc(DateTime instant) => _storage.write(
    _lockedUntilKey,
    instant.millisecondsSinceEpoch.toString(),
  );
}
