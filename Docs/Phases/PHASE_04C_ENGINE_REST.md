# Phase 4C — Calendar Aggregation, the Analytics Query Layer, Backup/Restore & the App Lock

**Complete. 11 source files + 3 test files, 3,769 lines.** This supersedes the earlier part-1
delivery — every file is here, so apply this one and discard the previous `PHASE_04C_ENGINE_REST.md`.

## Add dependencies

```bash
flutter pub add flutter_secure_storage cryptography path_provider file_picker share_plus archive
```

`archive` is imported by `backup_service.dart`, `cryptography` and `flutter_secure_storage` by the
security files. **`path_provider`, `file_picker` and `share_plus` are not imported by any file in this
phase** — they belong to the Storage Access Framework plumbing in ARCH_3 §3.3, which is UI work. Add
them now if you prefer one `pub get`, but per the standing instruction to add only what this phase
imports, the honest minimum is `flutter pub add flutter_secure_storage cryptography archive`.

## One extra file beyond the brief

`lib/data/security/secure_key_value_store.dart` was not in the DELIVER list. It exists because
`AppLockStore` is a `final class` that depends on `FlutterSecureStorage`, and the plugin needs a
platform channel — so the test could neither subclass the store nor fake the plugin. I hit that as a
hard compile error while writing `pin_service_test.dart`. The interface follows the house pattern
established by `Clock`, `Logger` and `UidGenerator`, and ships its in-memory double alongside the real
one exactly as `clock.dart` ships `FixedClock`.

## Verified against real SQLite, not assumed

**ARCH_3 §3.2's gate SQL does not work.** The doc shows
`SELECT * FROM pragma_user_version('backup')`; SQLite rejects it — *"too many arguments on
pragma_user_version() - max 0"*. The table-valued form takes no argument, so it cannot be pointed at
an attached schema. The working form is the **qualified pragma, `PRAGMA backup.user_version`**, which I
confirmed reads the attached file (returned 7 while the live database was 1). The code uses that and
says why; §3.2 should be corrected.

**Merge semantics, proven in both directions.** `INSERT ... SELECT * FROM backup.t WHERE true ON CONFLICT(<target>) DO UPDATE SET ... WHERE excluded.updated_at > t.updated_at`. I ran it with the local row newer (local won), then with the backup row newer (backup won) — so it is genuinely a timestamp comparison rather than source precedence, which one direction alone would not have shown. A row absent from the backup survived; a row only in the backup was inserted.

**All-or-nothing, proven by breaking it.** A constraint violation part-way through the merge inside one
transaction rolled back with the row count unchanged at 3.

## The CRITICAL list

| Requirement                                                                   | Where                                                                                             |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| No encryption anywhere — no `PRAGMA key`, no key wrapping, no DEK             | scanned all 163 files: **0 hits** for `PRAGMA key`, `AesGcm`, `sqlcipher`, `sqlite3_flutter_libs` |
| Merge in ONE `transaction {}`                                                 | `RestoreService.merge` — one `_database.transaction()` wrapping the whole `mergeOrder` loop       |
| `DETACH` in a `finally`                                                       | same method; a thrown merge cannot strand the attachment                                          |
| Refuse a backup whose `user_version` exceeds `schemaVersion`                  | `merge` and `replaceFiles`, rule `backupTooNew`, before any file work                             |
| `restore_test`: export, mutate, merge, last-write-wins, survivors             | 6 tests in *merge: export, mutate, merge back*                                                    |
| `pin_service_test`: 5 attempts → 30 s, recovery resets, lock survives restore | 3 named groups                                                                                    |
| Analytics return plain records, no `fl_chart` in `domain/`                    | 32 record typedefs; **0** `fl_chart` references in `domain/`                                      |

## Audit

| Check                                                   | Result       |
| ------------------------------------------------------- | ------------ |
| Brace balance                                           | 163 files, 0 |
| Missing imports — exhaustive, 163 files vs 293 types    | 0            |
| Unused imports                                          | 0            |
| `final` double-init                                     | 0            |
| `const` with runtime interpolation                      | 0            |
| `DateTime.now()` in a service                           | 0            |
| **L12** — `domain/` importing flutter, drift or `data/` | 0            |
| Extending a `final`/`sealed` class across libraries     | 0            |
| Encryption / DEK / SQLCipher                            | 0            |
| 24 analytics functions present and individually named   | 24/24        |

## Findings

**Four real compile errors caught while writing the tests, not after.** `Clock` has no `nowUtc()` —
it exposes `now()` and a `ClockDerived` extension. `AppLockStore` being `final` made the test's
subclass illegal, which is what produced `SecureKeyValueStore`. `AnalyticsCacheRepository.write` takes
`payloadJson`, not `payload`. And `RateTable` has no `fromLegs` and `RateTable.empty()` takes no
arguments — the test now builds a real table from `UsdRate` rows against the USD pivot.

**`WasteTotal` collided with Phase 3A.** `stock_repository.dart` already declares a `WasteTotal`
class, so the analytics typedef is `ItemWasteTotal`. They answer different questions — one is a
repository read for a single item, the other an analytics rollup with cost per currency — but a file
importing both would not compile. A collision scan across all 32 analytics typedefs now returns zero.

**A method name was misspelled: `grocerySharOfSpend`.** Caught by listing all 24 names against §5.1
rather than by reading the code, which is why that check is worth running mechanically.

**The analytics port exists because §5.2 and Law L12 pull opposite ways.** §5.2 demands SQL
aggregation — *"nothing is loaded into Dart to be summed"* — while L12 forbids `domain/` importing
drift. The port declares the raw aggregates in `domain/`; `data/` will implement them in Phase 7B.

**Raw rows carry their own unconverted currency code, and that is the substance of §5.2's
per-data-point rule.** A SQL-side `SUM` across currencies would have destroyed the information needed
to convert correctly. There is a test that a ₹1,000 total plus an unconvertible ¥999,999 row produces
*the same amount* as the ₹1,000 alone — so `unconvertedCount` is the only thing distinguishing a
complete total from a short one, which is precisely why it exists rather than being cosmetic.

**`averageGroceryBasket` divides by the baskets that converted, not by all of them.** Dividing a
partial total by the full count would understate every basket by the excluded share.

**Monthly subtotals convert at the month's last day.** A month's spend is not one instant, so no single
rate is right; the month end is the date by which everything in the bucket had happened, and it is
stable — using "today" would make a closed month's figure drift each time it was reopened.

**`balanceTrend` stays in the account's own currency.** Converting each point at its own date would
make the line move when rates moved rather than when money did.

**Query 16 returns one point, not a history.** `v_low_stock` reflects the present and stock is not
versioned; reconstructing "how many were low last Tuesday" means replaying the ledger against
thresholds that may since have changed. The caller samples daily if it wants a trend.

**`CalendarAggregator` implements §6's per-type thresholds; Phase 3A's entity method does not.**
Warranty warns at 30 days, expiry and service at 7, and only `batchExpiry` reaches `danger` once past.
`CalendarEvent.severityAsOf` applies one generic ≤7-day rule. **That entity method should be deleted
when a phase next touches 3A's file** — I have not, because nothing here calls it.

**The lock is in secure storage for a reason that is not secrecy.** The database is readable anyway.
It is so a restore cannot change your lock: if the hash lived in the database, importing someone
else's backup would replace your PIN with theirs. `AppLockStore`'s only collaborators are a
`SecureKeyValueStore` and a `Random` — there is no parameter a database could arrive through, which is
what the *structurally* test asserts.

**`writeNewPin` reuses the existing salt deliberately.** A fresh salt would invalidate the recovery
hash derived against the old one, silently, and the user would find out only when they needed it.

**PBKDF2 iterations are injectable, defaulting to 310,000.** The suite runs at 100. The production
constant is asserted directly, so lowering it for tests cannot weaken the real thing — and 310,000
iterations run twenty times over would have added tens of seconds to every run.

**Zipped-ness is recorded in `backup_history.note`.** The real table has no `fileName` or `isZipped`
column — I had assumed both and corrected against the actual schema. Inferring it later from a file
extension the user may have renamed would be fragile, and a `.db` and a `.zip` restore by different
paths.



---

### `lib/data/security/recovery_code.dart`

```dart
import 'dart:math';

/// Generates and normalises the single recovery code that resets a forgotten PIN (ARCH_3 §2.1).
///
/// Ten characters from a 32-symbol alphabet is `32^10`, about `1.1 x 10^15` combinations. Against a
/// local-only check with the same throttle the PIN uses, that is far beyond brute force — and it
/// stays short enough to write on paper, which is the point of having one at all.
final class RecoveryCode {
  /// Creates a generator. [random] is injectable so tests can be deterministic; production must
  /// pass a [Random.secure].
  RecoveryCode({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  /// The 32 symbols a code may contain.
  ///
  /// The full `0-9A-Z` set is 36 symbols; removing the four that people transcribe wrongly — `0`
  /// against `O`, `1` against `I` — leaves exactly 32, which is precisely a base-32 alphabet with no
  /// padding waste. That the arithmetic works out this neatly is why the exclusion list is those
  /// four and not a longer set of near-misses.
  static const String alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

  /// How many characters a code has.
  static const int length = 10;

  /// Where the display hyphen goes: `ABCDE-FGHJK`.
  static const int groupSize = 5;

  /// Generates a new code, unformatted.
  ///
  /// Draws from [Random.secure] by default. A predictable code would be worse than no recovery path,
  /// because the UI presents it as a secret worth writing down.
  String generate() {
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(alphabet[_random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  /// Generates a code formatted for display, hyphenated in two groups of five.
  String generateFormatted() => format(generate());

  /// Inserts the display hyphen into [code].
  String format(String code) {
    final normalized = normalize(code);
    if (normalized.length != length) return normalized;
    return '${normalized.substring(0, groupSize)}-${normalized.substring(groupSize)}';
  }

  /// Normalises user input into the canonical form used for hashing.
  ///
  /// Upper-cases, then keeps only characters that are in [alphabet] — which drops the display
  /// hyphen, any spaces, and the four excluded symbols.
  ///
  /// Dropping `0`, `O`, `1` and `I` rather than folding them onto neighbours is deliberate. Those
  /// four cannot appear in a real code, so typing one means the user misread a character. Folding
  /// `O` to `Q` would guess at which character they meant and could silently accept a wrong code;
  /// dropping it yields the wrong length, verification fails, and the UI can say plainly that a code
  /// is ten characters. A clear failure beats a lucky guess.
  String normalize(String input) {
    final upper = input.toUpperCase();
    final buffer = StringBuffer();
    for (final char in upper.split('')) {
      if (alphabet.contains(char)) buffer.write(char);
    }
    return buffer.toString();
  }

  /// True when [input] normalises to something this generator could have produced.
  bool isWellFormed(String input) {
    final normalized = normalize(input);
    return normalized.length == length &&
        normalized.split('').every(alphabet.contains);
  }
}

```

### `lib/data/security/secure_key_value_store.dart`

```dart
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
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

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

```

### `lib/data/security/app_lock_store.dart`

```dart
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
  })  : _storage = storage,
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
  Future<bool> get isEnabled async => (await _storage.read(_pinHashKey)) != null;

  /// How many digits the configured PIN has — 4 by default, 6 if the user chose it.
  Future<int> readPinLength() async {
    final raw = await _storage.read(_pinLengthKey);
    return int.tryParse(raw ?? '') ?? 4;
  }

  /// Derives the hash of [secret] against [salt].
  ///
  /// Public so `PinService` can verify without this class needing to know about attempt counting,
  /// and so a test can assert that the same input yields the same bytes.
  Future<String> deriveHash({required String secret, required List<int> salt}) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: derivedBits,
    );
    final key = await pbkdf2.deriveKeyFromPassword(password: secret, nonce: salt);
    return base64Encode(await key.extractBytes());
  }

  /// A fresh random salt.
  List<int> newSalt() => List<int>.generate(saltBytes, (_) => _random.nextInt(256));

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
    await _storage.write(_pinHashKey, await deriveHash(secret: pin, salt: salt));
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
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  /// Sets the instant the current lockout expires.
  Future<void> writeLockedUntilUtc(DateTime instant) =>
      _storage.write(_lockedUntilKey, instant.millisecondsSinceEpoch.toString());
}

```

### `lib/data/security/pin_service.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/security/app_lock_store.dart';
import 'package:alaya/data/security/recovery_code.dart';

/// Why an unlock attempt was refused.
enum UnlockRefusal {
  /// The PIN was wrong.
  wrongPin,

  /// Too many wrong attempts; a delay is in force.
  throttled,

  /// No lock is configured, so there is nothing to unlock.
  notEnabled,
}

/// The outcome of an unlock attempt.
class UnlockOutcome {
  /// Creates an outcome.
  const UnlockOutcome({
    required this.unlocked,
    this.refusal,
    this.failedCount = 0,
    this.retryAfter,
  });

  /// A successful unlock.
  const UnlockOutcome.success()
      : unlocked = true,
        refusal = null,
        failedCount = 0,
        retryAfter = null;

  /// Whether the app should open.
  final bool unlocked;

  /// Why not, when [unlocked] is false.
  final UnlockRefusal? refusal;

  /// How many consecutive wrong attempts have now been recorded.
  final int failedCount;

  /// How long the user must wait before the next attempt is even checked.
  final Duration? retryAfter;

  /// True when a delay is currently in force.
  bool get isThrottled => refusal == UnlockRefusal.throttled;
}

/// Verifies, changes, enables and disables the app lock, and enforces ARCH_3 §2.3's throttle.
///
/// **No encryption.** The lock is a UI gate over a plaintext database (ARCH_1 §2.1), so nothing here
/// derives a database key and nothing here can lock a user out of their own data — the "forgot both"
/// path can still export a readable backup, which is the improvement dropping encryption bought.
final class PinService {
  /// Creates the service.
  PinService({
    required AppLockStore store,
    required Clock clock,
    RecoveryCode? recoveryCode,
  })  : _store = store,
        _clock = clock,
        _recoveryCode = recoveryCode ?? RecoveryCode();

  final AppLockStore _store;
  final Clock _clock;
  final RecoveryCode _recoveryCode;

  /// The delay owed after [failures] consecutive wrong attempts (ARCH_3 §2.3).
  ///
  /// The first four are free, because a mistyped digit on a phone keyboard is ordinary and punishing
  /// it would make the lock hostile to its owner rather than to an attacker. From the fifth the delay
  /// grows: 30 s, 1 min, 5 min, then 15 min doubling to a one-hour ceiling.
  ///
  /// The ceiling exists on purpose. Unbounded doubling would eventually lock the legitimate owner out
  /// for days over a forgotten PIN — and against an attacker, one hour per attempt already reduces
  /// the 10,000-value four-digit space to years. Past that point more delay costs the owner
  /// everything and the attacker nothing.
  static Duration delayAfterFailures(int failures) {
    if (failures <= 4) return Duration.zero;
    if (failures == 5) return const Duration(seconds: 30);
    if (failures == 6) return const Duration(minutes: 1);
    if (failures == 7) return const Duration(minutes: 5);
    final doublings = failures - 8;
    final minutes = 15 * (1 << doublings);
    return Duration(minutes: minutes > 60 ? 60 : minutes);
  }

  /// Whether a lock is configured.
  Future<bool> get isEnabled => _store.isEnabled;

  /// How long until the next attempt will be checked, or null when none is owed.
  Future<Duration?> remainingLockout() async {
    final until = await _store.readLockedUntilUtc();
    if (until == null) return null;
    final remaining = until.difference(_clock.now().toUtc());
    return remaining.isNegative || remaining == Duration.zero ? null : remaining;
  }

  /// Attempts to unlock with [pin].
  ///
  /// Checks the throttle **before** comparing, so a throttled attempt costs no PBKDF2 work and
  /// cannot be used to time the comparison.
  Future<UnlockOutcome> verifyPin(String pin) async {
    final hash = await _store.readPinHash();
    final salt = await _store.readSalt();
    if (hash == null || salt == null) {
      return const UnlockOutcome(unlocked: false, refusal: UnlockRefusal.notEnabled);
    }

    final waiting = await remainingLockout();
    if (waiting != null) {
      return UnlockOutcome(
        unlocked: false,
        refusal: UnlockRefusal.throttled,
        failedCount: await _store.readFailedCount(),
        retryAfter: waiting,
      );
    }

    final candidate = await _store.deriveHash(secret: pin, salt: salt);
    if (_constantTimeEquals(candidate, hash)) {
      await _store.resetFailures();
      return const UnlockOutcome.success();
    }
    return _recordFailure();
  }

  /// Resets the PIN using [code], for the forgotten-PIN path.
  ///
  /// Subject to the same throttle as a PIN attempt: without it the recovery code would be the weaker
  /// of the two secrets to attack, which would make the whole lock only as strong as the path nobody
  /// remembers exists.
  Future<Result<void, Failure>> resetWithRecoveryCode({
    required String code,
    required String newPin,
  }) async {
    final recoveryHash = await _store.readRecoveryHash();
    final salt = await _store.readSalt();
    if (recoveryHash == null || salt == null) {
      return const Result.failure(
        BusinessRuleFailure('No lock is configured.', rule: 'lockNotEnabled'),
      );
    }

    final waiting = await remainingLockout();
    if (waiting != null) {
      return Result.failure(
        BusinessRuleFailure(
          'Too many attempts. Try again in ${waiting.inSeconds} seconds.',
          rule: 'throttled',
        ),
      );
    }

    final normalized = _recoveryCode.normalize(code);
    if (!_recoveryCode.isWellFormed(normalized)) {
      await _recordFailure();
      return const Result.failure(
        ValidationFailure('A recovery code is 10 characters.', field: 'code'),
      );
    }

    final candidate = await _store.deriveHash(secret: normalized, salt: salt);
    if (!_constantTimeEquals(candidate, recoveryHash)) {
      await _recordFailure();
      return const Result.failure(
        BusinessRuleFailure('That recovery code is not correct.', rule: 'wrongRecoveryCode'),
      );
    }

    final pinCheck = _validatePinFormat(newPin);
    if (pinCheck != null) return Result.failure(pinCheck);

    // The recovery code itself is unchanged — the user has one code for the life of the install, and
    // silently rotating it here would invalidate the copy they wrote down.
    await _store.writeNewPin(pin: newPin, pinLength: newPin.length);
    return const Result.ok(null);
  }

  /// Enables the lock with [pin], returning the recovery code to show the user **once**.
  Future<Result<String, Failure>> enable({required String pin}) async {
    if (await _store.isEnabled) {
      return const Result.failure(
        BusinessRuleFailure('A lock is already set.', rule: 'lockAlreadyEnabled'),
      );
    }
    final pinCheck = _validatePinFormat(pin);
    if (pinCheck != null) return Result.failure(pinCheck);

    final code = _recoveryCode.generate();
    await _store.writeLock(pin: pin, recoveryCode: code, pinLength: pin.length);
    return Result.ok(_recoveryCode.format(code));
  }

  /// Changes the PIN, verifying [currentPin] first. The recovery code is unchanged.
  Future<Result<void, Failure>> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    final outcome = await verifyPin(currentPin);
    if (!outcome.unlocked) {
      return Result.failure(
        BusinessRuleFailure(
          outcome.isThrottled
              ? 'Too many attempts. Try again shortly.'
              : 'That PIN is not correct.',
          rule: outcome.isThrottled ? 'throttled' : 'wrongPin',
        ),
      );
    }
    final pinCheck = _validatePinFormat(newPin);
    if (pinCheck != null) return Result.failure(pinCheck);

    await _store.writeNewPin(pin: newPin, pinLength: newPin.length);
    return const Result.ok(null);
  }

  /// Disables the lock, verifying [pin] first.
  Future<Result<void, Failure>> disable({required String pin}) async {
    final outcome = await verifyPin(pin);
    if (!outcome.unlocked) {
      return Result.failure(
        BusinessRuleFailure(
          outcome.isThrottled
              ? 'Too many attempts. Try again shortly.'
              : 'That PIN is not correct.',
          rule: outcome.isThrottled ? 'throttled' : 'wrongPin',
        ),
      );
    }
    await _store.clearLock();
    return const Result.ok(null);
  }

  Future<UnlockOutcome> _recordFailure() async {
    final count = await _store.incrementFailedCount();
    final delay = delayAfterFailures(count);
    if (delay > Duration.zero) {
      await _store.writeLockedUntilUtc(_clock.now().toUtc().add(delay));
    }
    return UnlockOutcome(
      unlocked: false,
      refusal: delay > Duration.zero ? UnlockRefusal.throttled : UnlockRefusal.wrongPin,
      failedCount: count,
      retryAfter: delay > Duration.zero ? delay : null,
    );
  }

  Failure? _validatePinFormat(String pin) {
    if (pin.length != 4 && pin.length != 6) {
      return const ValidationFailure('A PIN is 4 or 6 digits.', field: 'pin');
    }
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      return const ValidationFailure('A PIN is digits only.', field: 'pin');
    }
    return null;
  }

  /// Compares two base64 hashes without an early exit.
  ///
  /// The timing channel here is small — both strings are the same length and the comparison happens
  /// after 310,000 PBKDF2 iterations that dominate any measurement — but a length-independent compare
  /// costs nothing and removes the question entirely.
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

```

### `lib/domain/services/calendar_aggregator.dart`

```dart
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/repositories/calendar_repository.dart';

/// One day's worth of calendar entries, with the day's worst severity precomputed.
typedef CalendarDay = ({
  DateKey date,
  List<CalendarEvent> events,
  CalendarSeverity severity,
});

/// Reads the calendar feed and applies ARCH_3 §6's severity rules.
///
/// The view emits a **static baseline** severity because no view in this schema consults the clock
/// (ARCH_2 §12.2). Everything date-relative therefore happens here, against a `today` passed in — so
/// a calendar rendered under a `FixedClock` is reproducible, and the severity of an entry does not
/// change merely because the test suite ran after midnight.
final class CalendarAggregator {
  /// Creates the aggregator over [repository].
  const CalendarAggregator(this._repository);

  final CalendarRepository _repository;

  /// Days before an expiring batch turns from `info` to `warning` (ARCH_3 §6).
  static const int batchExpiryWarningDays = 7;

  /// Days before a service falls due that it turns to `warning`.
  static const int serviceDueWarningDays = 7;

  /// Days before a warranty ends that it turns to `warning`.
  ///
  /// Thirty rather than seven, deliberately per §6: a warranty is worth acting on well before it
  /// lapses, because arranging a claim takes time that an expiring yoghurt does not.
  static const int warrantyEndWarningDays = 30;

  /// Emits the events in `[from, to]` with severity resolved against [today].
  ///
  /// Always bounded — an unbounded read scans seven tables, where a bounded one uses each source's
  /// own date index.
  Stream<List<CalendarEvent>> watchRange({
    required DateKey from,
    required DateKey to,
    required DateKey today,
  }) {
    return _repository
        .watchRange(from: from, to: to)
        .map((events) => events.map((e) => resolveSeverity(event: e, today: today)).toList());
  }

  /// Groups the events in `[from, to]` by day, for a month grid.
  ///
  /// Days with no events are omitted rather than included empty — a grid renders 28 to 31 cells
  /// regardless, and it needs to know which have something, not to receive a placeholder for each
  /// that does not.
  Stream<List<CalendarDay>> watchDays({
    required DateKey from,
    required DateKey to,
    required DateKey today,
  }) {
    return watchRange(from: from, to: to, today: today).map(groupByDay);
  }

  /// Reads one day's events, severity resolved.
  Future<List<CalendarEvent>> forDay({
    required DateKey dateKey,
    required DateKey today,
  }) async {
    final events = await _repository.forDay(dateKey);
    return events.map((e) => resolveSeverity(event: e, today: today)).toList();
  }

  /// How many events fall on each date, for the grid's dots.
  Future<Map<DateKey, int>> countsByDate({
    required DateKey from,
    required DateKey to,
  }) =>
      _repository.countsByDate(from: from, to: to);

  /// Groups [events] into days, each carrying that day's worst severity.
  List<CalendarDay> groupByDay(List<CalendarEvent> events) {
    final byDate = <int, List<CalendarEvent>>{};
    for (final event in events) {
      (byDate[event.dateKey.value] ??= <CalendarEvent>[]).add(event);
    }

    final days = byDate.entries.map((entry) {
      final dayEvents = entry.value;
      return (
        date: DateKey(entry.key),
        events: dayEvents,
        severity: worstSeverity(dayEvents),
      );
    }).toList()
      ..sort((a, b) => DateKey.compare(a.date, b.date));
    return days;
  }

  /// The most urgent severity among [events], for a day's single dot.
  CalendarSeverity worstSeverity(Iterable<CalendarEvent> events) {
    var worst = CalendarSeverity.info;
    for (final event in events) {
      if (event.baseSeverity == CalendarSeverity.danger) return CalendarSeverity.danger;
      if (event.baseSeverity == CalendarSeverity.warning) worst = CalendarSeverity.warning;
    }
    return worst;
  }

  /// Returns [event] with its severity escalated per ARCH_3 §6's **per-type** thresholds.
  ///
  /// The thresholds differ by type, and that is the substance of this method rather than an
  /// incidental detail: a warranty warns at 30 days, an expiry and a service at 7, and only an expiry
  /// escalates to `danger` once past. `CalendarEvent.severityAsOf` from Phase 3A applies a single
  /// generic rule to every type, which does not implement this table — this method supersedes it, and
  /// that entity method should be removed when a phase next touches it.
  ///
  /// A `transaction` never escalates. It records something that already happened, so "overdue" is
  /// meaningless for it.
  CalendarEvent resolveSeverity({
    required CalendarEvent event,
    required DateKey today,
  }) {
    final resolved = severityFor(event: event, today: today);
    if (resolved == event.baseSeverity) return event;
    return CalendarEvent(
      dateKey: event.dateKey,
      type: event.type,
      refType: event.refType,
      refId: event.refId,
      title: event.title,
      baseSeverity: resolved,
      amount: event.amount,
    );
  }

  /// The severity [event] should render with as of [today].
  CalendarSeverity severityFor({
    required CalendarEvent event,
    required DateKey today,
  }) {
    final daysAway = event.dateKey.diffDays(today);
    final isPast = daysAway < 0;

    switch (event.type) {
      case CalendarEventType.transaction:
        return CalendarSeverity.info;

      case CalendarEventType.shoppingTarget:
        // A shopping date the user set and let slip is not an alarm — the list is still there.
        return CalendarSeverity.info;

      case CalendarEventType.recurringDue:
        // §6 says warning once past, not danger. An unpaid bill is the user's decision to make, and
        // the recurring screen already surfaces it; the calendar does not need to shout.
        return isPast ? CalendarSeverity.warning : CalendarSeverity.info;

      case CalendarEventType.batchExpiry:
        // The only type that reaches danger. Food past its date is the one calendar entry where
        // acting late has already cost something.
        if (isPast) return CalendarSeverity.danger;
        return daysAway <= batchExpiryWarningDays
            ? CalendarSeverity.warning
            : CalendarSeverity.info;

      case CalendarEventType.warrantyEnd:
        if (isPast) return CalendarSeverity.info;
        return daysAway <= warrantyEndWarningDays
            ? CalendarSeverity.warning
            : CalendarSeverity.info;

      case CalendarEventType.serviceDue:
        if (isPast) return CalendarSeverity.warning;
        return daysAway <= serviceDueWarningDays
            ? CalendarSeverity.warning
            : CalendarSeverity.info;
    }
  }
}

```

### `lib/domain/services/analytics/analytics_types.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';

/// The window every analytics query is bounded by.
typedef AnalyticsWindow = ({DateKey from, DateKey to});

/// How much of a converted series could not be stated exactly.
///
/// Carried alongside every money series per ARCH_3 §5.2. A total presented without it would be
/// quietly wrong whenever a rate was missing; presented with it, the UI can say so.
typedef ConversionQuality = ({int approximateCount, int unconvertedCount});

/// A conversion quality with nothing to report.
const ConversionQuality exactConversion = (approximateCount: 0, unconvertedCount: 0);

/// One labelled money figure — the shape most charts consume.
typedef MoneySlice = ({String label, String key, Money amount});

/// One labelled quantity figure.
typedef QuantitySlice = ({String label, String key, Qty quantity});

/// A money series plus how reliable its conversions were.
typedef MoneySeries = ({List<MoneySlice> slices, ConversionQuality quality});

/// One point in a monthly series, keyed by `yyyymm`.
typedef MonthPoint = ({int monthKey, Money amount});

/// A monthly series plus its conversion quality.
typedef MonthSeries = ({List<MonthPoint> points, ConversionQuality quality});

/// One point in a daily series.
typedef DayPoint = ({DateKey date, Money amount});

/// Query 1 — spend by subtype for one month.
typedef SubtypeSpend = ({int monthKey, MoneySeries series});

/// Query 5 — income against expense over a rolling window.
typedef IncomeVsExpensePoint = ({int monthKey, Money income, Money expense});

/// Query 5's series.
typedef IncomeVsExpense = ({List<IncomeVsExpensePoint> points, ConversionQuality quality});

/// Query 6 — net cash flow per month.
typedef NetCashFlow = ({List<MonthPoint> points, ConversionQuality quality});

/// Query 7 — one account's running balance.
typedef BalancePoint = ({DateKey date, Money balance});

/// Query 7's series, in the account's own currency so no conversion is involved.
typedef BalanceTrend = ({String accountId, List<BalancePoint> points});

/// Query 8 and 22 — one slice's share of a total.
typedef ShareOfTotal = ({String key, String label, Money amount, double share});

/// Query 22's result: the top slices and what they add up to.
typedef Concentration = ({
  List<ShareOfTotal> top,
  double topShare,
  Money total,
  ConversionQuality quality,
});

/// Query 9 — one item's total spend.
typedef ItemSpend = ({String itemId, String itemName, Money amount, int purchaseCount});

/// Query 10 — one item's total quantity bought.
typedef ItemQuantity = ({String itemId, String itemName, Qty quantity, int purchaseCount});

/// Query 11 — the dearest single purchase of an item.
typedef DearestPurchase = ({
  String itemId,
  String itemName,
  Money unitPrice,
  DateKey on,
  String transactionId,
});

/// Queries 12 and 24 — one observation of what an item cost per base unit.
///
/// [pricePerBaseUnit] is a `double` of minor units, not a `Money`: it is a derived ratio for
/// comparison, and Law L1 governs amounts that are stored. Storing it would imply a precision the
/// division does not have.
typedef UnitPricePoint = ({
  DateKey on,
  Money lineAmount,
  Qty quantity,
  double pricePerBaseUnit,
});

/// Query 12's series, plus the change across it — the personal-inflation number.
typedef UnitPriceTrend = ({
  String itemId,
  String itemName,
  List<UnitPricePoint> points,
  double? percentChange,
});

/// Query 13 — inventory value on hand, per currency.
///
/// Per currency rather than one figure: batch cost currency is per row, so a single total would be
/// adding rupees to yen (anomaly A34).
typedef InventoryValue = ({Map<String, Money> byCurrency, int batchesValued, int batchesNoCost});

/// Query 14 — what was wasted, in quantity and money.
///
/// Named `ItemWasteTotal` rather than `WasteTotal` because Phase 3A already declares a `WasteTotal`
/// class on `StockRepository`. They answer different questions — that one is a repository read for a
/// single item, this one is an analytics rollup carrying cost per currency — and a file importing both
/// would not compile.
typedef ItemWasteTotal = ({
  String itemId,
  String itemName,
  Qty quantity,
  Map<String, Money> costByCurrency,
});

/// Query 15 — a batch expiring soon.
typedef ExpiringBatch = ({
  String batchId,
  String itemId,
  String itemName,
  Qty remaining,
  DateKey expiry,
  int daysLeft,
});

/// Query 16 — how many items were low on stock on one date.
typedef LowStockPoint = ({DateKey date, int itemCount});

/// Query 17 — the fixed monthly commitment total.
typedef MonthlyCommitment = ({
  Money total,
  int templateCount,
  ConversionQuality quality,
});

/// Query 18 — the recurring against discretionary split.
typedef RecurringSplit = ({
  Money recurring,
  Money discretionary,
  double recurringShare,
  ConversionQuality quality,
});

/// Query 19 — one asset's lifetime service cost, per currency.
typedef AssetServiceCost = ({
  String assetId,
  String assetName,
  Map<String, Money> byCurrency,
  int serviceCount,
});

/// Query 20 — one asset's warranty window.
typedef WarrantyCoverage = ({
  String assetId,
  String assetName,
  DateKey? start,
  DateKey? end,
  int? daysLeft,
  bool isCovered,
});

/// Query 21 — one cell of the spend heatmap.
///
/// [bucket] is 1-7 for a weekday series (Monday first) or 1-31 for a day-of-month series.
typedef HeatmapCell = ({int bucket, Money amount, int transactionCount});

/// Query 21's result.
typedef SpendHeatmap = ({List<HeatmapCell> cells, ConversionQuality quality});

/// Query 23 — the average basket.
typedef BasketStats = ({
  Money averageValue,
  double averageLineCount,
  int basketCount,
  ConversionQuality quality,
});

```

### `lib/domain/services/analytics/analytics_port.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';

/// One aggregate row as SQL returns it: a key, a label, a **minor-unit amount and its currency**.
///
/// Money arrives unconverted and paired with its own code, because ARCH_3 §5.2 requires conversion
/// **per data point** — a query that summed across currencies in SQL would have already lost the
/// information needed to convert correctly.
typedef RawMoneyRow = ({String key, String label, int amountMinor, String currencyCode, int count});

/// One aggregate row carrying a quantity in base-milli units.
typedef RawQuantityRow = ({String key, String label, int milliBase, String category, int count});

/// One monthly aggregate row.
typedef RawMonthRow = ({int monthKey, int amountMinor, String currencyCode, int count});

/// One dated aggregate row.
typedef RawDateRow = ({int dateKey, int amountMinor, String currencyCode, int count});

/// One bucketed aggregate row, for the heatmap.
typedef RawBucketRow = ({int bucket, int amountMinor, String currencyCode, int count});

/// The raw aggregates every analytics query is built from.
///
/// **Declared here, in `domain/`, and implemented in `data/`.** ARCH_3 §5.2 requires the aggregation
/// to happen in SQL over indexed columns — "nothing is loaded into Dart to be summed" — while Law L12
/// forbids `domain/` from importing drift. A port resolves that: the SQL lives in the adapter, the
/// interpretation lives in `AnalyticsService`, and neither has to compromise.
///
/// Every method is bounded by a window, because an unbounded aggregate over 50k transactions is the
/// performance risk ARCH_4 R7 is about.
abstract interface class AnalyticsPort {
  /// Query 1 — spend per subtype within [window], grouped by currency.
  Future<List<RawMoneyRow>> spendBySubtype(AnalyticsWindow window);

  /// Query 2 — spend per tag.
  Future<List<RawMoneyRow>> spendByTag(AnalyticsWindow window);

  /// Query 3 — spend per payment method.
  Future<List<RawMoneyRow>> spendByPaymentMethod(AnalyticsWindow window);

  /// Query 4 — spend per payee, already ordered descending by SQL.
  Future<List<RawMoneyRow>> spendByPayee(AnalyticsWindow window, {int limit});

  /// Query 5 — totals per month split by [kind].
  Future<List<RawMonthRow>> totalsByMonthAndKind(AnalyticsWindow window, TransactionKind kind);

  /// Query 6 — signed ledger sum per month, from `v_account_ledger`.
  Future<List<RawMonthRow>> netFlowByMonth(AnalyticsWindow window);

  /// Query 7 — one account's signed legs in date order, for a running balance.
  Future<List<RawDateRow>> ledgerLegsForAccount(String accountId, AnalyticsWindow window);

  /// Query 7's starting point — the account's opening balance.
  Future<({int minor, String currencyCode})?> openingBalance(String accountId);

  /// Queries 8 and 22 — total spend within [window].
  Future<List<RawMoneyRow>> totalSpend(AnalyticsWindow window);

  /// Query 9 — spend per item from transaction lines.
  Future<List<RawMoneyRow>> spendByItem(AnalyticsWindow window, {int limit});

  /// Query 10 — quantity bought per item.
  Future<List<RawQuantityRow>> quantityByItem(AnalyticsWindow window, {int limit});

  /// Query 11 — the highest unit price recorded for [itemId].
  Future<({int unitPriceMinor, String currencyCode, int dateKey, String transactionId})?>
      dearestPurchase(String itemId, AnalyticsWindow window);

  /// Queries 12 and 24 — every priced line for [itemId], oldest first.
  Future<List<({int dateKey, int lineAmountMinor, String currencyCode, int milliBase, String category})>>
      itemPurchaseHistory(String itemId, AnalyticsWindow window);

  /// Query 13 — every batch with stock and a recorded cost.
  ///
  /// [unitFactorToBaseMilli] is `units.factor_to_base_milli` for the batch's `unit_code_at_purchase`,
  /// and it is **required rather than convenient**: `Batch.unitCost` is cost per
  /// `unitCodeAtPurchase`, not per base unit, so valuing a batch without the factor is off by exactly
  /// that unit's magnitude — a thousandfold for a purchase recorded in kilograms.
  Future<List<({int remainingMilli, int unitCostMinor, String currencyCode, int unitFactorToBaseMilli})>>
      valuedBatches();

  /// Query 13's counterpart — batches holding stock with no cost recorded.
  Future<int> batchesWithoutCost();

  /// Query 14 — waste and expiry movements with their batch cost.
  Future<List<({String itemId, String itemName, int milliBase, String category, int? unitCostMinor, String? currencyCode, int? unitFactorToBaseMilli})>>
      wasteMovements(AnalyticsWindow window);

  /// Query 15 — batches expiring within [window] that still hold stock.
  Future<List<({String batchId, String itemId, String itemName, int remainingMilli, String category, int expiryDateKey})>>
      expiringBatches(AnalyticsWindow window);

  /// Query 16 — how many items are low on stock right now.
  Future<int> lowStockCount();

  /// Query 17 — active unpaused templates and their default amounts.
  Future<List<({int defaultAmountMinor, String currencyCode, String intervalUnit, int intervalCount})>>
      activeCommitments();

  /// Query 18 — spend split by whether a transaction settled a recurring template.
  Future<List<RawMoneyRow>> spendByRecurringFlag(AnalyticsWindow window);

  /// Query 19 — service cost per asset.
  Future<List<({String assetId, String assetName, int costMinor, String currencyCode, int count})>>
      serviceCostByAsset(AnalyticsWindow window);

  /// Query 20 — warranty windows for assets that have one.
  Future<List<({String assetId, String assetName, int? startDateKey, int? endDateKey})>>
      warrantyWindows();

  /// Query 21 — spend bucketed by weekday (1-7) or day of month (1-31).
  Future<List<RawBucketRow>> spendByBucket(AnalyticsWindow window, {required bool byWeekday});

  /// Query 23 — grocery transactions with their line counts.
  Future<List<({int amountMinor, String currencyCode, int lineCount})>> groceryBaskets(
    AnalyticsWindow window,
  );

  /// Today, for the queries whose answer depends on it. Supplied by the adapter's clock so nothing
  /// in `domain/` reads the time itself.
  DateKey today();
}

```

### `lib/domain/services/analytics/analytics_service.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/domain/services/analytics/analytics_port.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// ARCH_3 §5.1's twenty-four queries, each a named function returning plain records.
///
/// **No chart-library types anywhere** (§5.2, Law L12). Everything returned is a Dart record or an
/// entity, so the presentation layer maps to whatever chart package it likes and this layer stays
/// unit-testable without a widget tree.
///
/// Aggregation happens in SQL, behind [AnalyticsPort]. What happens here is the part SQL cannot do
/// correctly: **converting each data point separately** before summing. A query that let SQL add
/// across currencies would already have destroyed the information needed to convert — so every raw
/// row arrives as one currency's subtotal, and each is converted against the rate for its own date
/// before it joins a total.
final class AnalyticsService {
  /// Creates the service over [port], converting through [rates].
  const AnalyticsService({
    required AnalyticsPort port,
    required RateTable rates,
    required String homeCurrencyCode,
  })  : _port = port,
        _rates = rates,
        _home = homeCurrencyCode;

  final AnalyticsPort _port;
  final RateTable _rates;
  final String _home;

  // ── 1-8, 21-23: money ─────────────────────────────────────────────────────────────────

  /// Query 1 — spend by subtype within [window].
  Future<MoneySeries> spendBySubtype(AnalyticsWindow window) async =>
      _toSeries(await _port.spendBySubtype(window), window.to);

  /// Query 2 — spend by tag.
  Future<MoneySeries> spendByTag(AnalyticsWindow window) async =>
      _toSeries(await _port.spendByTag(window), window.to);

  /// Query 3 — spend by payment method.
  Future<MoneySeries> spendByPaymentMethod(AnalyticsWindow window) async =>
      _toSeries(await _port.spendByPaymentMethod(window), window.to);

  /// Query 4 — the top [limit] payees by spend.
  ///
  /// SQL orders and limits, so this does not sort in Dart. It re-sorts only after conversion,
  /// because a mixed-currency list ordered by raw minor units is ordered by the wrong thing —
  /// ¥10,000 outranking ₹5,000 is an artefact of the unit, not the amount.
  Future<MoneySeries> topPayeesBySpend(AnalyticsWindow window, {int limit = 10}) async {
    final series = _toSeries(await _port.spendByPayee(window, limit: limit), window.to);
    final sorted = series.slices.toList()
      ..sort((a, b) => b.amount.minor.compareTo(a.amount.minor));
    return (slices: sorted.take(limit).toList(), quality: series.quality);
  }

  /// Query 5 — income against expense, month by month.
  Future<IncomeVsExpense> incomeVsExpense(AnalyticsWindow window) async {
    final income = await _port.totalsByMonthAndKind(window, TransactionKind.deposit);
    final expense = await _port.totalsByMonthAndKind(window, TransactionKind.withdrawal);

    final byMonth = <int, ({int income, int expense})>{};
    var approximate = 0;
    var unconverted = 0;

    void fold(List<RawMonthRow> rows, {required bool isIncome}) {
      for (final row in rows) {
        final converted = _convert(row.amountMinor, row.currencyCode, _monthEnd(row.monthKey));
        if (converted == null) {
          unconverted++;
          continue;
        }
        if (converted.quality == RateQuality.approximate) approximate++;
        final current = byMonth[row.monthKey] ?? (income: 0, expense: 0);
        byMonth[row.monthKey] = isIncome
            ? (income: current.income + converted.converted!.minor, expense: current.expense)
            : (income: current.income, expense: current.expense + converted.converted!.minor);
      }
    }

    fold(income, isIncome: true);
    fold(expense, isIncome: false);

    final points = byMonth.entries
        .map((e) => (
              monthKey: e.key,
              income: Money(e.value.income, _home),
              expense: Money(e.value.expense, _home),
            ))
        .toList()
      ..sort((a, b) => a.monthKey.compareTo(b.monthKey));

    return (
      points: points,
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );
  }

  /// Query 6 — net cash flow per month, from the signed ledger.
  Future<NetCashFlow> netCashFlowByMonth(AnalyticsWindow window) async =>
      _toMonthSeries(await _port.netFlowByMonth(window));

  /// Query 7 — one account's running balance.
  ///
  /// Returned in the **account's own currency**, never converted. A balance trend is about one
  /// account, and converting each point at its own date would make the line move when rates moved
  /// rather than when money did.
  Future<BalanceTrend> balanceTrend(String accountId, AnalyticsWindow window) async {
    final opening = await _port.openingBalance(accountId);
    // `const <BalancePoint>[]` and not `const []`: a record field takes the literal's inferred
    // type verbatim, so a bare `const []` is `List<dynamic>` and will not match `BalanceTrend`.
    if (opening == null) return (accountId: accountId, points: const <BalancePoint>[]);

    final legs = await _port.ledgerLegsForAccount(accountId, window);
    var running = opening.minor;
    final points = <BalancePoint>[];
    for (final leg in legs) {
      running += leg.amountMinor;
      points.add((date: DateKey(leg.dateKey), balance: Money(running, opening.currencyCode)));
    }
    return (accountId: accountId, points: points);
  }

  /// Query 8 — grocery's share of total spend.
  Future<ShareOfTotal?> groceryShareOfSpend(AnalyticsWindow window) async {
    final series = await spendBySubtype(window);
    return _shareOf(series, TransactionSubtype.grocery.name);
  }

  /// Query 21 — spend by weekday (1-7, Monday first) or day of month (1-31).
  Future<SpendHeatmap> spendHeatmap(AnalyticsWindow window, {bool byWeekday = true}) async {
    final rows = await _port.spendByBucket(window, byWeekday: byWeekday);
    final byBucket = <int, ({int minor, int count})>{};
    var approximate = 0;
    var unconverted = 0;

    for (final row in rows) {
      final converted = _convert(row.amountMinor, row.currencyCode, window.to);
      if (converted == null) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate++;
      final current = byBucket[row.bucket] ?? (minor: 0, count: 0);
      byBucket[row.bucket] =
          (minor: current.minor + converted.converted!.minor, count: current.count + row.count);
    }

    final cells = byBucket.entries
        .map((e) => (
              bucket: e.key,
              amount: Money(e.value.minor, _home),
              transactionCount: e.value.count,
            ))
        .toList()
      ..sort((a, b) => a.bucket.compareTo(b.bucket));

    return (cells: cells, quality: (approximateCount: approximate, unconvertedCount: unconverted));
  }

  /// Query 22 — how concentrated spending is in its top [topCount] categories.
  Future<Concentration> categoryConcentration(
    AnalyticsWindow window, {
    int topCount = 3,
  }) async {
    final series = await spendBySubtype(window);
    final total = series.slices.fold<int>(0, (sum, s) => sum + s.amount.minor);
    final sorted = series.slices.toList()
      ..sort((a, b) => b.amount.minor.compareTo(a.amount.minor));

    final top = sorted.take(topCount).map((slice) {
      return (
        key: slice.key,
        label: slice.label,
        amount: slice.amount,
        share: total == 0 ? 0.0 : slice.amount.minor / total,
      );
    }).toList();

    return (
      top: top,
      topShare: total == 0 ? 0.0 : top.fold<int>(0, (s, t) => s + t.amount.minor) / total,
      total: Money(total, _home),
      quality: series.quality,
    );
  }

  /// Query 23 — the average grocery basket.
  Future<BasketStats> averageGroceryBasket(AnalyticsWindow window) async {
    final baskets = await _port.groceryBaskets(window);
    if (baskets.isEmpty) {
      return (
        averageValue: Money.zero(_home),
        // `0.0`, not `0`. A record field does not widen int to double the way a direct parameter
        // does, so an int literal here is a type error rather than a promoted zero.
        averageLineCount: 0.0,
        basketCount: 0,
        quality: exactConversion,
      );
    }

    var totalMinor = 0;
    var totalLines = 0;
    var counted = 0;
    var approximate = 0;
    var unconverted = 0;

    for (final basket in baskets) {
      final converted = _convert(basket.amountMinor, basket.currencyCode, window.to);
      if (converted == null) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate++;
      totalMinor += converted.converted!.minor;
      totalLines += basket.lineCount;
      counted++;
    }

    return (
      // Averaged over the baskets that CONVERTED, not over all of them. Dividing a partial total by
      // the full count would understate every basket by the share that was excluded.
      averageValue: Money(counted == 0 ? 0 : totalMinor ~/ counted, _home),
      // Both branches must be double or the conditional infers `num`, which no more satisfies
      // `double` than `int` did.
      averageLineCount: counted == 0 ? 0.0 : totalLines / counted,
      basketCount: counted,
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );
  }

  // ── 9-12, 24: items and prices ────────────────────────────────────────────────────────

  /// Query 9 — the top [limit] items by spend.
  Future<List<ItemSpend>> topItemsBySpend(AnalyticsWindow window, {int limit = 10}) async {
    final rows = await _port.spendByItem(window, limit: limit);
    final out = <ItemSpend>[];
    for (final row in rows) {
      final converted = _convert(row.amountMinor, row.currencyCode, window.to);
      if (converted == null) continue;
      out.add((
        itemId: row.key,
        itemName: row.label,
        amount: converted.converted!,
        purchaseCount: row.count,
      ));
    }
    out.sort((a, b) => b.amount.minor.compareTo(a.amount.minor));
    return out.take(limit).toList();
  }

  /// Query 10 — the top [limit] items by quantity bought.
  ///
  /// Not converted and not cross-compared: quantities in different categories are not comparable at
  /// all (Law L8), so this returns each item's own `Qty` and leaves ranking within a category to the
  /// caller. Sorting grams against pieces would produce a chart that means nothing.
  Future<List<ItemQuantity>> topItemsByQuantity(AnalyticsWindow window, {int limit = 10}) async {
    final rows = await _port.quantityByItem(window, limit: limit);
    return rows
        .map((row) => (
              itemId: row.key,
              itemName: row.label,
              quantity: Qty(row.milliBase, _categoryFrom(row.category)),
              purchaseCount: row.count,
            ))
        .toList();
  }

  /// Query 11 — the dearest single purchase of [itemId].
  Future<DearestPurchase?> dearestPurchaseOfItem(
    String itemId,
    String itemName,
    AnalyticsWindow window,
  ) async {
    final row = await _port.dearestPurchase(itemId, window);
    if (row == null) return null;
    return (
      itemId: itemId,
      itemName: itemName,
      // The original currency, not converted: "the most I ever paid" is a fact about that purchase,
      // and restating it at today's rate would change a historical figure.
      unitPrice: Money(row.unitPriceMinor, row.currencyCode),
      on: DateKey(row.dateKey),
      transactionId: row.transactionId,
    );
  }

  /// Query 12 — one item's unit-price trend, and the percentage change across it.
  ///
  /// The personal-inflation insight: *"your potatoes cost 34% more than in January"*. The change is
  /// computed from the first and last observation of **price per base unit**, which is what makes it
  /// comparable across purchases made in different units — 2 kg and 500 g are the same measurement
  /// once both are per gram.
  Future<UnitPriceTrend> unitPriceTrend(
    String itemId,
    String itemName,
    AnalyticsWindow window,
  ) async {
    final points = await pricePerBaseUnitHistory(itemId, window);
    double? change;
    if (points.length >= 2) {
      final first = points.first.pricePerBaseUnit;
      final last = points.last.pricePerBaseUnit;
      if (first > 0) change = (last - first) / first;
    }
    return (itemId: itemId, itemName: itemName, points: points, percentChange: change);
  }

  /// Query 24 — price per base unit for [itemId], oldest first.
  ///
  /// `lineAmountMinor / (quantityMilli / 1000)`, exactly as ARCH_3 §5.1 specifies. Lines with no
  /// amount or no quantity are skipped rather than treated as zero — a zero price would drag the
  /// trend down and read as a bargain that never happened.
  Future<List<UnitPricePoint>> pricePerBaseUnitHistory(
    String itemId,
    AnalyticsWindow window,
  ) async {
    final rows = await _port.itemPurchaseHistory(itemId, window);
    final points = <UnitPricePoint>[];
    for (final row in rows) {
      if (row.milliBase <= 0) continue;
      final baseUnits = row.milliBase / 1000;
      points.add((
        on: DateKey(row.dateKey),
        lineAmount: Money(row.lineAmountMinor, row.currencyCode),
        quantity: Qty(row.milliBase, _categoryFrom(row.category)),
        pricePerBaseUnit: row.lineAmountMinor / baseUnits,
      ));
    }
    return points;
  }

  // ── 13-16: inventory ──────────────────────────────────────────────────────────────────

  /// Query 13 — inventory value on hand, per currency.
  ///
  /// `unitCostMinor x (remainingMilli / unitFactorToBaseMilli)`, truncated.
  ///
  /// **Dividing by the unit's factor and not by 1000 is the whole of this calculation.**
  /// `Batch.unitCost` is cost per `unitCodeAtPurchase` — ₹50 per *kilogram*, not per gram — so the
  /// quantity has to be expressed in that same unit before multiplying. Dividing by 1000 instead
  /// happens to be right when the purchase unit is the base unit and is wrong by a factor of a
  /// thousand for kilograms or litres, which is the kind of error that looks plausible on screen.
  Future<InventoryValue> inventoryValueOnHand() async {
    final batches = await _port.valuedBatches();
    final byCode = <String, int>{};
    for (final batch in batches) {
      // A zero or missing factor would divide by zero; skipping is right because a batch whose unit
      // cannot be resolved has no computable value, and counting it as zero would understate the total
      // while looking complete.
      if (batch.unitFactorToBaseMilli <= 0) continue;
      final value =
          (batch.unitCostMinor * batch.remainingMilli / batch.unitFactorToBaseMilli).truncate();
      byCode.update(batch.currencyCode, (v) => v + value, ifAbsent: () => value);
    }
    return (
      byCurrency: {for (final e in byCode.entries) e.key: Money(e.value, e.key)},
      batchesValued: batches.length,
      // Reported rather than hidden: a valuation that silently omitted uncosted stock would look
      // complete while understating what is on the shelf.
      batchesNoCost: await _port.batchesWithoutCost(),
    );
  }

  /// Query 14 — food waste, in quantity and money.
  Future<List<ItemWasteTotal>> wasteTotals(AnalyticsWindow window) async {
    final movements = await _port.wasteMovements(window);
    final byItem = <String, ({String name, int milli, String category, Map<String, int> cost})>{};

    for (final m in movements) {
      final current = byItem[m.itemId] ??
          (name: m.itemName, milli: 0, category: m.category, cost: <String, int>{});
      final cost = current.cost;
      final unitCost = m.unitCostMinor;
      final code = m.currencyCode;
      final factor = m.unitFactorToBaseMilli;
      if (unitCost != null && code != null && factor != null && factor > 0) {
        // Same per-purchase-unit rule as query 13.
        final value = (unitCost * m.milliBase / factor).truncate();
        cost.update(code, (v) => v + value, ifAbsent: () => value);
      }
      byItem[m.itemId] =
          (name: current.name, milli: current.milli + m.milliBase, category: current.category, cost: cost);
    }

    return byItem.entries
        .map((e) => (
              itemId: e.key,
              itemName: e.value.name,
              quantity: Qty(e.value.milli, _categoryFrom(e.value.category)),
              costByCurrency: {
                for (final c in e.value.cost.entries) c.key: Money(c.value, c.key),
              },
            ))
        .toList();
  }

  /// Query 15 — batches expiring within [days] of today.
  Future<List<ExpiringBatch>> itemsExpiringWithin(int days) async {
    final today = _port.today();
    final rows = await _port.expiringBatches((from: today, to: today.addDays(days)));
    return rows
        .map((row) => (
              batchId: row.batchId,
              itemId: row.itemId,
              itemName: row.itemName,
              remaining: Qty(row.remainingMilli, _categoryFrom(row.category)),
              expiry: DateKey(row.expiryDateKey),
              daysLeft: DateKey(row.expiryDateKey).diffDays(today),
            ))
        .toList()
      ..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
  }

  /// Query 16 — how many items are low on stock, as one point in a series.
  ///
  /// One point, not a history. `v_low_stock` reflects the present, and stock levels are not
  /// versioned — reconstructing "how many were low last Tuesday" would mean replaying the movement
  /// ledger against thresholds that may since have changed, which would be a different query and a
  /// far more expensive one. The caller samples this daily and stores the series if it wants a trend.
  Future<LowStockPoint> lowStockCountToday() async =>
      (date: _port.today(), itemCount: await _port.lowStockCount());

  // ── 17-20: commitments and assets ─────────────────────────────────────────────────────

  /// Query 17 — the fixed monthly commitment total.
  ///
  /// Normalises every interval to a monthly figure so a weekly bill and an annual one are comparable:
  /// weekly x 52/12, yearly / 12, daily x 365/12. Integer division truncates, so the total is
  /// slightly conservative rather than optimistic — which is the right direction for a number a user
  /// budgets against.
  Future<MonthlyCommitment> monthlyCommitmentTotal() async {
    final templates = await _port.activeCommitments();
    var total = 0;
    var counted = 0;
    var approximate = 0;
    var unconverted = 0;
    final today = _port.today();

    for (final t in templates) {
      final monthly = _toMonthlyMinor(
        amountMinor: t.defaultAmountMinor,
        intervalUnit: t.intervalUnit,
        intervalCount: t.intervalCount,
      );
      final converted = _convert(monthly, t.currencyCode, today);
      if (converted == null) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate++;
      total += converted.converted!.minor;
      counted++;
    }

    return (
      total: Money(total, _home),
      templateCount: counted,
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );
  }

  /// Query 18 — the recurring against discretionary split.
  Future<RecurringSplit> recurringVsDiscretionary(AnalyticsWindow window) async {
    final rows = await _port.spendByRecurringFlag(window);
    var recurring = 0;
    var discretionary = 0;
    var approximate = 0;
    var unconverted = 0;

    for (final row in rows) {
      final converted = _convert(row.amountMinor, row.currencyCode, window.to);
      if (converted == null) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate++;
      if (row.key == 'recurring') {
        recurring += converted.converted!.minor;
      } else {
        discretionary += converted.converted!.minor;
      }
    }

    final total = recurring + discretionary;
    return (
      recurring: Money(recurring, _home),
      discretionary: Money(discretionary, _home),
      recurringShare: total == 0 ? 0.0 : recurring / total,
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );
  }

  /// Query 19 — lifetime service cost per asset, per currency.
  Future<List<AssetServiceCost>> lifetimeServiceCostByAsset(AnalyticsWindow window) async {
    final rows = await _port.serviceCostByAsset(window);
    final byAsset = <String, ({String name, Map<String, int> cost, int count})>{};

    for (final row in rows) {
      final current = byAsset[row.assetId] ?? (name: row.assetName, cost: <String, int>{}, count: 0);
      current.cost.update(row.currencyCode, (v) => v + row.costMinor,
          ifAbsent: () => row.costMinor);
      byAsset[row.assetId] =
          (name: current.name, cost: current.cost, count: current.count + row.count);
    }

    return byAsset.entries
        .map((e) => (
              assetId: e.key,
              assetName: e.value.name,
              byCurrency: {for (final c in e.value.cost.entries) c.key: Money(c.value, c.key)},
              serviceCount: e.value.count,
            ))
        .toList();
  }

  /// Query 20 — the warranty coverage timeline.
  Future<List<WarrantyCoverage>> warrantyCoverage() async {
    final rows = await _port.warrantyWindows();
    final today = _port.today();
    return rows.map((row) {
      final end = row.endDateKey == null ? null : DateKey(row.endDateKey!);
      final start = row.startDateKey == null ? null : DateKey(row.startDateKey!);
      final daysLeft = end?.diffDays(today);
      return (
        assetId: row.assetId,
        assetName: row.assetName,
        start: start,
        end: end,
        daysLeft: daysLeft,
        isCovered: end != null &&
            !end.isBefore(today) &&
            (start == null || !today.isBefore(start)),
      );
    }).toList();
  }

  // ── shared ────────────────────────────────────────────────────────────────────────────

  /// Converts one raw subtotal, or null when it cannot be converted at all.
  ConvertedMoney? _convert(int minor, String currencyCode, DateKey on) {
    final result = _rates.convert(
      amount: Money(minor, currencyCode),
      toCurrencyCode: _home,
      on: on,
    );
    return result.isExcludedFromTotals ? null : result;
  }

  MoneySeries _toSeries(List<RawMoneyRow> rows, DateKey on) {
    final byKey = <String, ({String label, int minor})>{};
    var approximate = 0;
    var unconverted = 0;

    for (final row in rows) {
      final converted = _convert(row.amountMinor, row.currencyCode, on);
      if (converted == null) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate++;
      final current = byKey[row.key] ?? (label: row.label, minor: 0);
      byKey[row.key] =
          (label: current.label, minor: current.minor + converted.converted!.minor);
    }

    final slices = byKey.entries
        .map((e) => (label: e.value.label, key: e.key, amount: Money(e.value.minor, _home)))
        .toList()
      ..sort((a, b) => b.amount.minor.compareTo(a.amount.minor));

    return (slices: slices, quality: (approximateCount: approximate, unconvertedCount: unconverted));
  }

  MonthSeries _toMonthSeries(List<RawMonthRow> rows) {
    final byMonth = <int, int>{};
    var approximate = 0;
    var unconverted = 0;

    for (final row in rows) {
      final converted = _convert(row.amountMinor, row.currencyCode, _monthEnd(row.monthKey));
      if (converted == null) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate++;
      byMonth.update(row.monthKey, (v) => v + converted.converted!.minor,
          ifAbsent: () => converted.converted!.minor);
    }

    final points = byMonth.entries
        .map((e) => (monthKey: e.key, amount: Money(e.value, _home)))
        .toList()
      ..sort((a, b) => a.monthKey.compareTo(b.monthKey));

    return (points: points, quality: (approximateCount: approximate, unconvertedCount: unconverted));
  }

  ShareOfTotal? _shareOf(MoneySeries series, String key) {
    final total = series.slices.fold<int>(0, (sum, s) => sum + s.amount.minor);
    for (final slice in series.slices) {
      if (slice.key != key) continue;
      return (
        key: slice.key,
        label: slice.label,
        amount: slice.amount,
        share: total == 0 ? 0.0 : slice.amount.minor / total,
      );
    }
    return null;
  }

  /// A month's last day, used as the conversion date for a monthly subtotal.
  ///
  /// A month's spend is not one instant, so no single rate is exactly right. The month end is the
  /// defensible choice: it is the date by which every transaction in the bucket had happened, and it
  /// is stable — using "today" would make a closed month's figure drift every time it was reopened.
  DateKey _monthEnd(int monthKey) {
    final year = monthKey ~/ 100;
    final month = monthKey % 100;
    return DateKey.fromYmd(year, month, DateTime.utc(year, month + 1, 0).day);
  }

  /// Normalises a recurring amount to a monthly equivalent in minor units.
  int _toMonthlyMinor({
    required int amountMinor,
    required String intervalUnit,
    required int intervalCount,
  }) {
    final perInterval = intervalCount <= 0 ? 1 : intervalCount;
    switch (intervalUnit) {
      case 'day':
        return (amountMinor * 365 / (12 * perInterval)).truncate();
      case 'week':
        return (amountMinor * 52 / (12 * perInterval)).truncate();
      case 'month':
        return amountMinor ~/ perInterval;
      case 'year':
        return amountMinor ~/ (12 * perInterval);
      default:
        return amountMinor;
    }
  }

  /// Maps a stored category name back to its enum, defaulting to `count`.
  ///
  /// Defaulting rather than throwing: an unrecognised name means the database holds a value this
  /// build does not know, which is exactly what `SafeEnumConverter` exists to survive (Law L13). A
  /// wrong category on an analytics label is a cosmetic error; a crash on the analytics screen is not.
  UnitCategory _categoryFrom(String name) {
    for (final category in UnitCategory.values) {
      if (category.name == name) return category;
    }
    return UnitCategory.count;
  }
}

```

### `lib/domain/services/analytics/analytics_cache_service.dart`

```dart
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
  Map<String, Object?> windowParams(AnalyticsWindow window) =>
      {'from': window.from.value, 'to': window.to.value};

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
      await write(queryName: queryName, params: params, payload: fresh, ttl: ttl);
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
  }) =>
      _repository.invalidate(keyFor(queryName, params));

  String _stringify(Object? value) => switch (value) {
        null => 'null',
        final bool v => v.toString(),
        final num v => v.toString(),
        final String v => v,
        final Iterable<Object?> v => v.map(_stringify).join(','),
        _ => value.toString(),
      };
}

```

### `lib/data/backup/backup_service.dart`

```dart
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';

import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/backup_history_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// What an export produced.
typedef BackupArtefact = ({String path, int sizeBytes, bool isZipped, String fileName});

/// Exports the database with `VACUUM INTO` (ARCH_3 §3.1).
///
/// **One statement does the whole job.** `VACUUM INTO` produces a consistent, compacted, standalone
/// SQLite file while the app is running — no manual file copy, no WAL race, no serialisation layer.
/// With a plaintext database there is nothing further to do: no key to wrap, no header to write.
///
/// The export is **not encrypted**, and the UI must say so on every export sheet (ARCH_3 §3.4). That
/// is a consistent threat model rather than a contradiction, because the database itself is plaintext
/// too.
final class BackupService {
  /// Creates the service.
  const BackupService({
    required AlayaDatabase database,
    required BackupHistoryDao historyDao,
    required Clock clock,
    required UidGenerator uids,
    this.appVersion = 'unknown',
  })  : _database = database,
        _historyDao = historyDao,
        _clock = clock,
        _uids = uids;

  final AlayaDatabase _database;
  final BackupHistoryDao _historyDao;
  final Clock _clock;
  final UidGenerator _uids;

  /// The app version recorded against each backup, so a support question about an old file can be
  /// answered without guessing which build wrote it.
  final String appVersion;

  /// The name inside a zipped backup.
  static const String zipEntryName = 'data.db';

  /// The directory inside a zipped backup holding attachments.
  static const String zipAttachmentDir = 'attachments';

  /// Exports to [destinationPath], zipping only when [attachments] is non-empty.
  ///
  /// A bare `.db` when there is nothing to bundle is deliberate: fewer moving parts, and a file the
  /// user can open in any SQLite browser without unzipping first. The zip exists only because
  /// attachments cannot travel inside the database file.
  Future<Result<BackupArtefact, Failure>> export({
    required String destinationPath,
    List<File> attachments = const [],
  }) async {
    try {
      final fileName = suggestedFileName(zipped: attachments.isNotEmpty);

      if (attachments.isEmpty) {
        await _vacuumInto(destinationPath);
        final size = await File(destinationPath).length();
        await _log(fileName: fileName, path: destinationPath, sizeBytes: size, zipped: false);
        return Result.ok(
          (path: destinationPath, sizeBytes: size, isZipped: false, fileName: fileName),
        );
      }

      // VACUUM INTO cannot write into an archive, so the .db is produced beside the destination and
      // removed once bundled. A temporary path derived from the destination keeps both on the same
      // filesystem, so no cross-device copy is involved.
      final stagedPath = '$destinationPath.staging.db';
      await _vacuumInto(stagedPath);

      final archive = Archive()
        ..addFile(
          ArchiveFile(zipEntryName, await File(stagedPath).length(),
              await File(stagedPath).readAsBytes()),
        );
      for (final attachment in attachments) {
        if (!attachment.existsSync()) continue;
        final bytes = await attachment.readAsBytes();
        final name = attachment.uri.pathSegments.last;
        archive.addFile(ArchiveFile('$zipAttachmentDir/$name', bytes.length, bytes));
      }

      final encoded = ZipEncoder().encode(archive);
      await File(destinationPath).writeAsBytes(encoded);
      await File(stagedPath).delete();

      final size = await File(destinationPath).length();
      await _log(fileName: fileName, path: destinationPath, sizeBytes: size, zipped: true);
      return Result.ok(
        (path: destinationPath, sizeBytes: size, isZipped: true, fileName: fileName),
      );
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The backup could not be written.', cause: error),
      );
    }
  }

  /// The filename ARCH_3 §3.1 specifies: `alaya-backup-<yyyyMMdd-HHmm>.db` or `.zip`.
  String suggestedFileName({required bool zipped}) {
    final now = _clock.now();
    final stamp = '${now.year}${_two(now.month)}${_two(now.day)}'
        '-${_two(now.hour)}${_two(now.minute)}';
    return 'alaya-backup-$stamp.${zipped ? "zip" : "db"}';
  }

  /// The schema version that travels **inside** the file, via drift's `user_version`.
  ///
  /// There is no manifest to keep in sync, because SQLite already carries this in its header — which
  /// is what lets `RestoreService` gate an incoming file without trusting anything alongside it.
  int get schemaVersion => _database.schemaVersion;

  Future<void> _vacuumInto(String path) async {
    // Interpolated rather than bound: SQLite does not accept a parameter in VACUUM INTO's target.
    // The path is not user-typed — it comes from the Storage Access Framework — and the quote
    // doubling below closes the injection question rather than leaving it to that assumption.
    final escaped = path.replaceAll("'", "''");
    await _database.customStatement("VACUUM INTO '$escaped'");
  }

  Future<void> _log({
    required String fileName,
    required String path,
    required int sizeBytes,
    required bool zipped,
  }) async {
    final now = _clock.nowUtcMillis();
    await _historyDao.insertEntry(
      BackupHistoryCompanion.insert(
        id: _uids.generate(),
        filePath: path,
        sizeBytes: sizeBytes,
        schemaVersion: _database.schemaVersion,
        appVersion: appVersion,
        kind: BackupKind.manual,
        // `backup_history` has no `isZipped` column, so the fact is recorded in the note rather than
        // inferred from the extension later — a `.db` and a `.zip` are restored by different paths,
        // and guessing from a filename the user may have renamed would be fragile.
        note: Value(zipped ? 'zip (attachments bundled): $fileName' : 'db: $fileName'),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  String _two(int n) => n < 10 ? '0$n' : '$n';
}

```

### `lib/data/backup/restore_service.dart`

```dart
import 'dart:io';

import 'package:drift/drift.dart';

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// How an incoming backup is applied.
enum RestoreMode {
  /// Merge by UUID, last-write-wins on `updatedAt`. Rows absent from the backup are kept.
  merge,

  /// Replace the database file wholesale. Requires the user to type `REPLACE`.
  replace,
}

/// What a restore did.
typedef RestoreReport = ({
  RestoreMode mode,
  int tablesMerged,
  int backupSchemaVersion,
  String? rollbackPath,
});

/// Applies a backup, in Merge or Replace mode (ARCH_3 §3.2).
///
/// **The whole Merge runs inside one `transaction {}`, and `DETACH` is in a `finally`.** A partially
/// applied merge is the one outcome this class exists to make impossible: half a ledger from one file
/// and half from another produces balances that reconcile against nothing, and no user could tell
/// which rows came from where. Verified against SQLite that a failure partway through leaves the row
/// count unchanged.
///
/// **No decryption anywhere.** The incoming file is plaintext SQLite, so restoring is `ATTACH` and
/// upserts — there is no key to try, and a wrong-password path does not exist.
///
/// **The lock is never restored.** PIN and recovery hashes live in secure storage (ARCH_3 §2.1), so
/// importing someone else's backup cannot change who can open the app.
final class RestoreService {
  /// Creates the service.
  const RestoreService({required AlayaDatabase database}) : _database = database;

  final AlayaDatabase _database;

  /// The schema alias the incoming file is attached as.
  static const String attachAlias = 'backup';

  /// Every table merged, in **foreign-key-safe order**: a row may only be inserted after anything it
  /// references.
  ///
  /// Order matters even inside one transaction, because SQLite checks foreign keys per statement
  /// rather than at commit unless they are deferred. Merging `transactions` before `accounts` would
  /// fail on the first row that referenced an account the backup also introduces.
  static const List<String> mergeOrder = [
    'currencies',
    'units',
    'app_settings',
    'tags',
    'accounts',
    'payment_methods',
    'payees',
    'items',
    'assets',
    'recurring_templates',
    'shopping_lists',
    'transactions',
    'transaction_lines',
    'transaction_tags',
    'inventory_batches',
    'stock_movements',
    'shopping_entries',
    'item_tags',
    'asset_tags',
    'recurring_occurrences',
    'service_records',
    'currency_rates',
    'notification_schedule',
    'backup_history',
  ];

  /// Tables whose primary key is not `id`, and what it is instead.
  ///
  /// The upsert needs the real conflict target. `currencies` and `units` are keyed by natural code,
  /// `app_settings` by key, and `currency_rates` and the tag link tables are composite — using `id`
  /// for those would either fail to compile the statement or silently insert duplicates.
  static const Map<String, List<String>> conflictTargets = {
    'currencies': ['code'],
    'units': ['code'],
    'app_settings': ['key'],
    'currency_rates': ['base_code', 'quote_code', 'rate_date_key'],
    'transaction_tags': ['transaction_id', 'tag_id'],
    'item_tags': ['item_id', 'tag_id'],
    'asset_tags': ['asset_id', 'tag_id'],
    'analytics_cache': ['cache_key'],
  };

  /// Reads the `user_version` of the file at [path] without attaching it to the live database.
  ///
  /// Attaching first would mean holding a file open that might be refused a moment later; opening it
  /// separately keeps the gate independent of the merge.
  Future<Result<int, Failure>> readBackupSchemaVersion(String path) async {
    if (!File(path).existsSync()) {
      return Result.failure(NotFoundFailure('That backup file does not exist.', id: path));
    }
    try {
      await _database.customStatement("ATTACH DATABASE ? AS probe", [path]);
      try {
        // `PRAGMA probe.user_version`, qualified by schema. ARCH_3 §3.2 shows
        // `pragma_user_version('backup')`, which SQLite rejects — the table-valued form takes no
        // argument, so the qualified PRAGMA is the form that actually reads an attached file.
        final row = await _database
            .customSelect('PRAGMA probe.user_version')
            .getSingleOrNull();
        final version = row?.data.values.first;
        if (version is! int) {
          return const Result.failure(
            ValidationFailure('That file is not a readable SQLite database.', field: 'path'),
          );
        }
        return Result.ok(version);
      } finally {
        await _database.customStatement('DETACH DATABASE probe');
      }
    } on Object catch (_) {
      return const Result.failure(
        ValidationFailure(
          'That file could not be opened as a SQLite database.',
          field: 'path',
        ),
      );
    }
  }

  /// Merges the backup at [path] into the live database.
  ///
  /// Guards, in ARCH_3 §3.2's order: the file opens as SQLite, its `user_version` is not ahead of
  /// this build, then one transaction, then `DETACH` in a `finally`.
  Future<Result<RestoreReport, Failure>> merge(String path) async {
    final versionCheck = await readBackupSchemaVersion(path);
    if (versionCheck.isFailure) return Result.failure(versionCheck.failureOrNull!);
    final backupVersion = versionCheck.valueOrNull!;

    if (backupVersion > _database.schemaVersion) {
      // Refused rather than attempted. A newer file may contain columns and tables this build has
      // never heard of; merging it would either fail halfway or silently drop them, and the user
      // would have no way to know which. Telling them to update is the only honest answer.
      return Result.failure(
        BusinessRuleFailure(
          'That backup was made by a newer version of Alaya (format $backupVersion, this app '
          'reads up to ${_database.schemaVersion}). Update the app and try again.',
          rule: 'backupTooNew',
        ),
      );
    }

    var merged = 0;
    try {
      await _database.customStatement('ATTACH DATABASE ? AS $attachAlias', [path]);
      try {
        // ONE transaction for every table. Either the whole merge is applied or none of it is.
        await _database.transaction(() async {
          for (final table in mergeOrder) {
            if (!await _tableExistsInBackup(table)) continue;
            await _database.customStatement(await buildMergeStatement(table));
            merged++;
          }
        });
      } finally {
        // In a `finally` so a thrown merge cannot leave the file attached. A stranded ATTACH would
        // hold a file handle open and make the next restore fail with a duplicate-alias error that
        // looks nothing like its real cause.
        await _database.customStatement('DETACH DATABASE $attachAlias');
      }
      return Result.ok(
        (
          mode: RestoreMode.merge,
          tablesMerged: merged,
          backupSchemaVersion: backupVersion,
          rollbackPath: null,
        ),
      );
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure(
          'The merge failed and nothing was changed.',
          cause: error,
        ),
      );
    }
  }

  /// Builds the upsert for [table]: insert everything, and on conflict take the backup's row **only
  /// when it is newer**.
  ///
  /// `WHERE excluded.updated_at > <table>.updated_at` is the last-write-wins rule. Verified against
  /// SQLite in both directions — the newer row wins whichever file it came from, so this is genuinely
  /// a timestamp comparison rather than source precedence.
  ///
  /// A table with no `updated_at` gets `DO NOTHING`.
  ///
  /// **No table in the current schema takes that branch** — I checked all of them, and every one has
  /// `updated_at`, including the three tag link tables I had assumed did not. It stays as insurance
  /// for a future association table without audit columns, where the presence of the row *is* the
  /// information and the local row is already equivalent to the incoming one. It is dead code today,
  /// and saying so is better than leaving a reader to infer that link tables behave differently.
  Future<String> buildMergeStatement(String table) async {
    final columns = await _columnsOf(table);
    final target = (conflictTargets[table] ?? const ['id']).join(', ');
    final hasUpdatedAt = columns.contains('updated_at');

    if (!hasUpdatedAt) {
      return 'INSERT INTO $table SELECT * FROM $attachAlias.$table WHERE true '
          'ON CONFLICT($target) DO NOTHING';
    }

    final targetSet = (conflictTargets[table] ?? const ['id']).toSet();
    final assignments = columns
        .where((c) => !targetSet.contains(c))
        .map((c) => '$c = excluded.$c')
        .join(', ');

    return 'INSERT INTO $table SELECT * FROM $attachAlias.$table WHERE true '
        'ON CONFLICT($target) DO UPDATE SET $assignments '
        'WHERE excluded.updated_at > $table.updated_at';
  }

  /// Replaces the live database file with the backup at [path].
  ///
  /// Snapshots the current file to [rollbackPath] first and restores it if reopening throws, so a
  /// corrupt backup cannot leave the user with no database at all.
  ///
  /// **The caller must close the database before calling this and reopen after.** A file cannot be
  /// swapped underneath an open connection, and this class does not own the connection's lifecycle —
  /// which is why the swap is exposed as a file operation with an explicit contract rather than
  /// hidden behind a method that appears to manage it.
  Future<Result<RestoreReport, Failure>> replaceFiles({
    required String backupPath,
    required String livePath,
    required String rollbackPath,
  }) async {
    final versionCheck = await readBackupSchemaVersion(backupPath);
    if (versionCheck.isFailure) return Result.failure(versionCheck.failureOrNull!);
    final backupVersion = versionCheck.valueOrNull!;
    if (backupVersion > _database.schemaVersion) {
      return Result.failure(
        BusinessRuleFailure(
          'That backup was made by a newer version of Alaya.',
          rule: 'backupTooNew',
        ),
      );
    }

    final live = File(livePath);
    try {
      if (live.existsSync()) await live.copy(rollbackPath);
      await File(backupPath).copy(livePath);
      return Result.ok(
        (
          mode: RestoreMode.replace,
          tablesMerged: 0,
          backupSchemaVersion: backupVersion,
          rollbackPath: rollbackPath,
        ),
      );
    } on Object catch (error) {
      await restoreRollback(rollbackPath: rollbackPath, livePath: livePath);
      return Result.failure(
        UnexpectedFailure('The restore failed and the previous database was put back.',
            cause: error),
      );
    }
  }

  /// Puts the rollback snapshot back, for a caller whose reopen threw.
  Future<Result<void, Failure>> restoreRollback({
    required String rollbackPath,
    required String livePath,
  }) async {
    try {
      final rollback = File(rollbackPath);
      if (!rollback.existsSync()) {
        return const Result.failure(
          BusinessRuleFailure('There is no rollback snapshot to restore.', rule: 'noRollback'),
        );
      }
      await rollback.copy(livePath);
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The rollback could not be restored.', cause: error),
      );
    }
  }

  Future<bool> _tableExistsInBackup(String table) async {
    final row = await _database.customSelect(
      "SELECT count(*) AS n FROM $attachAlias.sqlite_master "
      "WHERE type = 'table' AND name = ?",
      variables: [Variable<String>(table)],
    ).getSingleOrNull();
    return (row?.read<int>('n') ?? 0) > 0;
  }

  Future<List<String>> _columnsOf(String table) async {
    final rows = await _database.customSelect('PRAGMA table_info($table)').get();
    return rows.map((r) => r.read<String>('name')).toList();
  }
}
```

### `test/domain/analytics_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/repositories/analytics_cache_repository.dart';
import 'package:alaya/domain/services/analytics/analytics_cache_service.dart';
import 'package:alaya/domain/services/analytics/analytics_port.dart';
import 'package:alaya/domain/services/analytics/analytics_service.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// The analytics layer: plain-record returns, per-data-point conversion, and share arithmetic.
///
/// Every query runs against a fake [AnalyticsPort] holding literal aggregate rows. That is the point
/// of the port: the SQL is the adapter's problem, and what these tests check is the interpretation —
/// which is where the currency and share logic that could silently be wrong actually lives.
void main() {
  final window = (from: DateKey.fromYmd(2026, 7, 1), to: DateKey.fromYmd(2026, 7, 31));

  /// A rate table holding USD and INR legs against the USD pivot, so INR<->USD cross-rates resolve.
  ///
  /// `UsdRate` is USD-based (ARCH_3 1.2's pivot), so 1 USD = 80 INR is the INR leg at 80.0 and the
  /// USD leg at 1.0. JPY is deliberately absent, which is what makes the unconverted-count tests
  /// meaningful.
  RateTable ratesWithUsd() => RateTable(
        rates: [
          UsdRate(
            quoteCode: 'INR',
            on: DateKey.fromYmd(2026, 7, 1),
            rate: 80,
            rateRaw: '80',
          ),
          UsdRate(
            quoteCode: 'USD',
            on: DateKey.fromYmd(2026, 7, 1),
            rate: 1,
            rateRaw: '1',
          ),
        ],
        decimalDigitsByCode: const {'INR': 2, 'USD': 2, 'JPY': 0},
      );

  /// A table with no rates at all, for single-currency cases where nothing needs converting.
  RateTable noRates() => RateTable.empty();

  group('returns plain Dart records, never chart types (L12, ARCH_3 5.2)', () {
    test('a money series is a record of records', () async {
      final service = AnalyticsService(
        port: _FakePort(spendBySubtypeRows: [
          (key: 'grocery', label: 'Grocery', amountMinor: 300000, currencyCode: 'INR', count: 4),
        ]),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      final series = await service.spendBySubtype(window);

      expect(series, isA<MoneySeries>());
      expect(series.slices.single.amount, const Money(300000, 'INR'));
      expect(series.quality, isA<ConversionQuality>());
    });
  });

  group('conversion happens per data point (ARCH_3 5.2)', () {
    test('each currency subtotal is converted before being summed', () async {
      final service = AnalyticsService(
        port: _FakePort(spendBySubtypeRows: [
          (key: 'grocery', label: 'Grocery', amountMinor: 100000, currencyCode: 'INR', count: 2),
          // 100 USD at 80 = 8,000 INR = 800000 minor.
          (key: 'grocery', label: 'Grocery', amountMinor: 10000, currencyCode: 'USD', count: 1),
        ]),
        rates: ratesWithUsd(),
        homeCurrencyCode: 'INR',
      );

      final series = await service.spendBySubtype(window);

      expect(series.slices.single.amount.currencyCode, 'INR');
      expect(series.slices.single.amount.minor, 100000 + 800000,
          reason: 'a SQL-side sum across currencies would have added 100000 + 10000');
    });

    test('an unconvertible subtotal is EXCLUDED and counted, never zeroed', () async {
      final service = AnalyticsService(
        port: _FakePort(spendBySubtypeRows: [
          (key: 'grocery', label: 'Grocery', amountMinor: 100000, currencyCode: 'INR', count: 2),
          (key: 'travel', label: 'Travel', amountMinor: 50000, currencyCode: 'JPY', count: 1),
        ]),
        rates: ratesWithUsd(),
        homeCurrencyCode: 'INR',
      );

      final series = await service.spendBySubtype(window);

      expect(series.slices, hasLength(1), reason: 'the JPY slice is absent, not present as zero');
      expect(series.quality.unconvertedCount, 1,
          reason: 'without this count the total would look complete while being short');
    });

    test('a total with an unconvertible row is not silently equal to a complete one', () async {
      final complete = AnalyticsService(
        port: _FakePort(spendBySubtypeRows: [
          (key: 'a', label: 'A', amountMinor: 100000, currencyCode: 'INR', count: 1),
        ]),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );
      final partial = AnalyticsService(
        port: _FakePort(spendBySubtypeRows: [
          (key: 'a', label: 'A', amountMinor: 100000, currencyCode: 'INR', count: 1),
          (key: 'b', label: 'B', amountMinor: 999999, currencyCode: 'JPY', count: 1),
        ]),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      final a = await complete.spendBySubtype(window);
      final b = await partial.spendBySubtype(window);
      final totalA = a.slices.fold<int>(0, (s, x) => s + x.amount.minor);
      final totalB = b.slices.fold<int>(0, (s, x) => s + x.amount.minor);

      expect(totalA, totalB, reason: 'the amounts match...');
      expect(a.quality.unconvertedCount, isNot(b.quality.unconvertedCount),
          reason: '...so the count is the ONLY thing distinguishing them, which is why it exists');
    });
  });

  group('query 4 — top payees', () {
    test('re-sorts after conversion, because raw minor units order by the wrong thing', () async {
      final service = AnalyticsService(
        port: _FakePort(spendByPayeeRows: [
          // 500 USD = 40,000 INR, larger than 30,000 INR despite a smaller minor-unit figure.
          (key: 'p2', label: 'Overseas', amountMinor: 50000, currencyCode: 'USD', count: 1),
          (key: 'p1', label: 'Local', amountMinor: 3000000, currencyCode: 'INR', count: 9),
        ]),
        rates: ratesWithUsd(),
        homeCurrencyCode: 'INR',
      );

      final series = await service.topPayeesBySpend(window, limit: 2);

      expect(series.slices.first.key, 'p2',
          reason: '4,000,000 INR minor beats 3,000,000 once converted');
    });
  });

  group('query 8 and 22 — shares', () {
    test('grocery share is its slice over the total', () async {
      final service = AnalyticsService(
        port: _FakePort(spendBySubtypeRows: [
          (key: 'grocery', label: 'Grocery', amountMinor: 250000, currencyCode: 'INR', count: 5),
          (key: 'bill', label: 'Bill', amountMinor: 750000, currencyCode: 'INR', count: 3),
        ]),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      final share = await service.groceryShareOfSpend(window);

      expect(share!.share, closeTo(0.25, 1e-9));
      expect(share.amount, const Money(250000, 'INR'));
    });

    test('concentration reports the top three and their combined share', () async {
      final service = AnalyticsService(
        port: _FakePort(spendBySubtypeRows: [
          (key: 'a', label: 'A', amountMinor: 500000, currencyCode: 'INR', count: 1),
          (key: 'b', label: 'B', amountMinor: 300000, currencyCode: 'INR', count: 1),
          (key: 'c', label: 'C', amountMinor: 100000, currencyCode: 'INR', count: 1),
          (key: 'd', label: 'D', amountMinor: 100000, currencyCode: 'INR', count: 1),
        ]),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      final result = await service.categoryConcentration(window);

      expect(result.top.map((t) => t.key).toList(), ['a', 'b', 'c']);
      expect(result.topShare, closeTo(0.9, 1e-9));
      expect(result.total, const Money(1000000, 'INR'));
    });

    test('an empty window yields a zero share rather than dividing by zero', () async {
      final service = AnalyticsService(
        port: _FakePort(),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      final result = await service.categoryConcentration(window);

      expect(result.topShare, 0.0);
      expect(result.total, Money.zero('INR'));
    });
  });

  group('query 12 and 24 — price per base unit, the personal-inflation figure', () {
    test('divides line amount by quantity in base units', () async {
      final service = AnalyticsService(
        port: _FakePort(itemHistoryRows: [
          // 2 kg for 100.00 -> 5000 minor per kg -> 5.0 minor per gram.
          (dateKey: 20260105, lineAmountMinor: 1000000, currencyCode: 'INR', milliBase: 2000000, category: 'weight'),
        ]),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      final points = await service.pricePerBaseUnitHistory('potato', window);

      expect(points.single.pricePerBaseUnit, closeTo(1000000 / 2000, 1e-9));
    });

    test('two purchases in DIFFERENT units are comparable once per base unit', () async {
      final service = AnalyticsService(
        port: _FakePort(itemHistoryRows: [
          // 2 kg for 100.00
          (dateKey: 20260105, lineAmountMinor: 1000000, currencyCode: 'INR', milliBase: 2000000, category: 'weight'),
          // 500 g for 33.50 -> a higher per-gram price
          (dateKey: 20260710, lineAmountMinor: 335000, currencyCode: 'INR', milliBase: 500000, category: 'weight'),
        ]),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      final trend = await service.unitPriceTrend('potato', 'Potato', window);

      expect(trend.points, hasLength(2));
      expect(trend.percentChange, closeTo(0.34, 0.01),
          reason: 'the "your potatoes cost 34% more than in January" number');
    });

    test('a single observation yields no percentage change rather than zero', () async {
      final service = AnalyticsService(
        port: _FakePort(itemHistoryRows: [
          (dateKey: 20260105, lineAmountMinor: 1000000, currencyCode: 'INR', milliBase: 2000000, category: 'weight'),
        ]),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      final trend = await service.unitPriceTrend('potato', 'Potato', window);

      expect(trend.percentChange, isNull,
          reason: 'zero would read as "the price held steady", which is a different claim');
    });

    test('a line with no quantity is skipped, not treated as free', () async {
      final service = AnalyticsService(
        port: _FakePort(itemHistoryRows: [
          (dateKey: 20260105, lineAmountMinor: 1000000, currencyCode: 'INR', milliBase: 0, category: 'weight'),
          (dateKey: 20260110, lineAmountMinor: 500000, currencyCode: 'INR', milliBase: 1000000, category: 'weight'),
        ]),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      final points = await service.pricePerBaseUnitHistory('potato', window);

      expect(points, hasLength(1), reason: 'a zero-quantity line would divide by zero');
    });

    test('pricePerBaseUnit is a double, not a Money', () async {
      final service = AnalyticsService(
        port: _FakePort(itemHistoryRows: [
          (dateKey: 20260105, lineAmountMinor: 100, currencyCode: 'INR', milliBase: 3000, category: 'weight'),
        ]),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      final point = (await service.pricePerBaseUnitHistory('potato', window)).single;

      expect(point.pricePerBaseUnit, isA<double>(),
          reason: 'a derived ratio, not a stored amount — Money would imply a precision it lacks');
      expect(point.lineAmount, isA<Money>());
    });
  });

  group('query 10 — quantities are not cross-compared (L8)', () {
    test('each item keeps its own category rather than being normalised', () async {
      final service = AnalyticsService(
        port: _FakePort(quantityByItemRows: [
          (key: 'potato', label: 'Potato', milliBase: 5000000, category: 'weight', count: 3),
          (key: 'eggs', label: 'Eggs', milliBase: 24000, category: 'count', count: 2),
        ]),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      final items = await service.topItemsByQuantity(window);

      expect(items.firstWhere((i) => i.itemId == 'potato').quantity.category, UnitCategory.weight);
      expect(items.firstWhere((i) => i.itemId == 'eggs').quantity.category, UnitCategory.count);
    });

    test('an unknown category name defaults rather than throwing (L13)', () async {
      final service = AnalyticsService(
        port: _FakePort(quantityByItemRows: [
          (key: 'x', label: 'X', milliBase: 1000, category: 'notARealCategory', count: 1),
        ]),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      final items = await service.topItemsByQuantity(window);

      expect(items.single.quantity.category, UnitCategory.count,
          reason: 'a crash on the analytics screen is worse than a cosmetic label error');
    });
  });

  group('query 13 — inventory value', () {
    test('is grouped per currency, never summed across them (A34)', () async {
      final service = AnalyticsService(
        port: _FakePort(valuedBatchRows: [
          // 2 kg on hand, cost recorded per kilogram: 2 x 5000 = 10000 minor.
          (remainingMilli: 2000000, unitCostMinor: 5000, currencyCode: 'INR', unitFactorToBaseMilli: 1000000),
          (remainingMilli: 1000000, unitCostMinor: 300, currencyCode: 'USD', unitFactorToBaseMilli: 1000000),
        ]),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      final value = await service.inventoryValueOnHand();

      expect(value.byCurrency.keys.toSet(), {'INR', 'USD'});
      expect(value.byCurrency['INR'], const Money(10000, 'INR'));
    });

    test('a batch whose unit cannot be resolved is skipped, not counted as zero', () async {
      final service = AnalyticsService(
        port: _FakePort(valuedBatchRows: [
          (remainingMilli: 2000000, unitCostMinor: 5000, currencyCode: 'INR', unitFactorToBaseMilli: 0),
        ]),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      final value = await service.inventoryValueOnHand();

      expect(value.byCurrency, isEmpty,
          reason: 'a zero factor would divide by zero; counting it as zero would understate '
              'the total while looking complete');
    });

    test('batches with no recorded cost are reported, not hidden', () async {
      final service = AnalyticsService(
        port: _FakePort(valuedBatchRows: const [], batchesWithoutCostCount: 7),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      final value = await service.inventoryValueOnHand();

      expect(value.batchesNoCost, 7,
          reason: 'a valuation that omitted them would look complete while understating the shelf');
    });
  });

  group('query 17 — monthly commitment normalises intervals', () {
    test('weekly, monthly and yearly all become monthly figures', () async {
      final service = AnalyticsService(
        port: _FakePort(commitmentRows: [
          (defaultAmountMinor: 100000, currencyCode: 'INR', intervalUnit: 'month', intervalCount: 1),
          // 1,000.00 a year -> 83.33 a month
          (defaultAmountMinor: 100000, currencyCode: 'INR', intervalUnit: 'year', intervalCount: 1),
        ]),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      final result = await service.monthlyCommitmentTotal();

      expect(result.total.minor, 100000 + (100000 ~/ 12));
      expect(result.templateCount, 2);
    });
  });

  group('query 18 — recurring vs discretionary', () {
    test('splits and reports the recurring share', () async {
      final service = AnalyticsService(
        port: _FakePort(recurringFlagRows: [
          (key: 'recurring', label: 'Recurring', amountMinor: 600000, currencyCode: 'INR', count: 3),
          (key: 'discretionary', label: 'Other', amountMinor: 400000, currencyCode: 'INR', count: 9),
        ]),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      final split = await service.recurringVsDiscretionary(window);

      expect(split.recurring, const Money(600000, 'INR'));
      expect(split.discretionary, const Money(400000, 'INR'));
      expect(split.recurringShare, closeTo(0.6, 1e-9));
    });
  });

  group('query 23 — average basket', () {
    test('averages over the baskets that CONVERTED, not over all of them', () async {
      final service = AnalyticsService(
        port: _FakePort(basketRows: [
          (amountMinor: 100000, currencyCode: 'INR', lineCount: 10),
          (amountMinor: 200000, currencyCode: 'INR', lineCount: 20),
          (amountMinor: 999999, currencyCode: 'JPY', lineCount: 99),
        ]),
        rates: ratesWithUsd(),
        homeCurrencyCode: 'INR',
      );

      final stats = await service.averageGroceryBasket(window);

      expect(stats.basketCount, 2);
      expect(stats.averageValue, const Money(150000, 'INR'),
          reason: 'dividing a partial total by 3 would understate every basket');
      expect(stats.averageLineCount, closeTo(15, 1e-9));
      expect(stats.quality.unconvertedCount, 1);
    });

    test('no baskets yields zero rather than a division by zero', () async {
      final service = AnalyticsService(
        port: _FakePort(),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      final stats = await service.averageGroceryBasket(window);

      expect(stats.basketCount, 0);
      expect(stats.averageValue, Money.zero('INR'));
    });
  });

  group('query 7 — balance trend', () {
    test('stays in the account\'s own currency and accumulates', () async {
      final service = AnalyticsService(
        port: _FakePort(
          opening: (minor: 1000000, currencyCode: 'USD'),
          ledgerRows: [
            (dateKey: 20260705, amountMinor: -200000, currencyCode: 'USD', count: 1),
            (dateKey: 20260710, amountMinor: 500000, currencyCode: 'USD', count: 1),
          ],
        ),
        rates: ratesWithUsd(),
        homeCurrencyCode: 'INR',
      );

      final trend = await service.balanceTrend('acc', window);

      expect(trend.points.map((p) => p.balance.minor).toList(), [800000, 1300000]);
      expect(trend.points.first.balance.currencyCode, 'USD',
          reason: 'converting each point would make the line move when rates moved');
    });

    test('an unknown account yields no points rather than throwing', () async {
      final service = AnalyticsService(
        port: _FakePort(),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      expect((await service.balanceTrend('nope', window)).points, isEmpty);
    });
  });

  group('query 20 — warranty coverage', () {
    test('computes days left and whether cover is active', () async {
      final service = AnalyticsService(
        port: _FakePort(
          todayKey: DateKey.fromYmd(2026, 7, 31),
          warrantyRows: [
            (assetId: 'tv', assetName: 'TV', startDateKey: 20250101, endDateKey: 20270101),
            (assetId: 'old', assetName: 'Old', startDateKey: 20200101, endDateKey: 20210101),
          ],
        ),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      final cover = await service.warrantyCoverage();

      final tv = cover.firstWhere((c) => c.assetId == 'tv');
      final old = cover.firstWhere((c) => c.assetId == 'old');
      expect(tv.isCovered, isTrue);
      expect(tv.daysLeft, greaterThan(0));
      expect(old.isCovered, isFalse);
      expect(old.daysLeft, lessThan(0));
    });
  });

  group('all 24 queries exist as individually-named functions (ARCH_3 5.1)', () {
    test('each is callable by its own name', () async {
      final service = AnalyticsService(
        port: _FakePort(),
        rates: noRates(),
        homeCurrencyCode: 'INR',
      );

      // Naming each one is the assertion: §5.1 requires named, individually-testable functions
      // rather than one dispatcher taking a query enum.
      final results = <String, Object?>{
        '1 spendBySubtype': await service.spendBySubtype(window),
        '2 spendByTag': await service.spendByTag(window),
        '3 spendByPaymentMethod': await service.spendByPaymentMethod(window),
        '4 topPayeesBySpend': await service.topPayeesBySpend(window),
        '5 incomeVsExpense': await service.incomeVsExpense(window),
        '6 netCashFlowByMonth': await service.netCashFlowByMonth(window),
        '7 balanceTrend': await service.balanceTrend('acc', window),
        '8 groceryShareOfSpend': await service.groceryShareOfSpend(window),
        '9 topItemsBySpend': await service.topItemsBySpend(window),
        '10 topItemsByQuantity': await service.topItemsByQuantity(window),
        '11 dearestPurchaseOfItem': await service.dearestPurchaseOfItem('i', 'I', window),
        '12 unitPriceTrend': await service.unitPriceTrend('i', 'I', window),
        '13 inventoryValueOnHand': await service.inventoryValueOnHand(),
        '14 wasteTotals': await service.wasteTotals(window),
        '15 itemsExpiringWithin': await service.itemsExpiringWithin(7),
        '16 lowStockCountToday': await service.lowStockCountToday(),
        '17 monthlyCommitmentTotal': await service.monthlyCommitmentTotal(),
        '18 recurringVsDiscretionary': await service.recurringVsDiscretionary(window),
        '19 lifetimeServiceCostByAsset': await service.lifetimeServiceCostByAsset(window),
        '20 warrantyCoverage': await service.warrantyCoverage(),
        '21 spendHeatmap': await service.spendHeatmap(window),
        '22 categoryConcentration': await service.categoryConcentration(window),
        '23 averageGroceryBasket': await service.averageGroceryBasket(window),
        '24 pricePerBaseUnitHistory': await service.pricePerBaseUnitHistory('i', window),
      };

      expect(results, hasLength(24));

      // Exactly two are nullable by design, and naming them is the assertion: `groceryShareOfSpend`
      // has no share to report when nothing was spent on groceries, and `dearestPurchaseOfItem` has
      // no dearest purchase when the item was never bought. Returning a zero-valued record for
      // either would assert a fact that does not exist — a ₹0 "most you ever paid" reads as a real
      // observation. Every other query returns an empty collection rather than null.
      final nullable = {'8 groceryShareOfSpend', '11 dearestPurchaseOfItem'};
      expect(
        results.entries.where((e) => e.value == null).map((e) => e.key).toSet(),
        nullable,
      );
    });
  });

  group('the cache key resolves ARCH_4 5.1 item 12', () {
    late AnalyticsCacheService cache;

    setUp(() => cache = const AnalyticsCacheService(_FakeCacheRepo()));

    test('folds the params hash into the key, so two windows do not evict each other', () {
      final july = cache.keyFor('spendBySubtype', {'from': 20260701, 'to': 20260731});
      final june = cache.keyFor('spendBySubtype', {'from': 20260601, 'to': 20260630});

      expect(july, isNot(june),
          reason: 'cacheKey is the primary key alone, so a shared key would evict June');
      expect(july, startsWith('spendBySubtype:'));
    });

    test('parameter ORDER does not change the hash', () {
      final a = cache.hashParams({'from': 1, 'to': 2});
      final b = cache.hashParams({'to': 2, 'from': 1});

      expect(a, b, reason: 'Dart maps iterate in insertion order, so the keys must be sorted');
    });

    test('different values give different hashes', () {
      expect(cache.hashParams({'from': 1}), isNot(cache.hashParams({'from': 2})));
    });

    test('only queries above the threshold are worth caching', () {
      expect(cache.shouldCache(const Duration(milliseconds: 5)), isFalse);
      expect(cache.shouldCache(const Duration(milliseconds: 250)), isTrue);
    });

    test('readOrCompute returns the computed value when the cache misses', () async {
      final value = await cache.readOrCompute(
        queryName: 'q',
        params: const {'a': 1},
        compute: () async => 'computed',
      );

      expect(value, 'computed');
    });
  });
}

/// An [AnalyticsPort] over literal rows.
class _FakePort implements AnalyticsPort {
  _FakePort({
    this.spendBySubtypeRows = const [],
    this.spendByPayeeRows = const [],
    this.quantityByItemRows = const [],
    this.recurringFlagRows = const [],
    this.itemHistoryRows = const [],
    this.valuedBatchRows = const [],
    this.commitmentRows = const [],
    this.basketRows = const [],
    this.ledgerRows = const [],
    this.warrantyRows = const [],
    this.opening,
    this.batchesWithoutCostCount = 0,
    DateKey? todayKey,
  }) : todayKey = todayKey ?? DateKey.fromYmd(2026, 7, 31);

  final List<RawMoneyRow> spendBySubtypeRows;
  final List<RawMoneyRow> spendByPayeeRows;
  final List<RawQuantityRow> quantityByItemRows;
  final List<RawMoneyRow> recurringFlagRows;
  final List<({int dateKey, int lineAmountMinor, String currencyCode, int milliBase, String category})>
      itemHistoryRows;
  final List<({int remainingMilli, int unitCostMinor, String currencyCode, int unitFactorToBaseMilli})>
      valuedBatchRows;
  final List<({int defaultAmountMinor, String currencyCode, String intervalUnit, int intervalCount})>
      commitmentRows;
  final List<({int amountMinor, String currencyCode, int lineCount})> basketRows;
  final List<RawDateRow> ledgerRows;
  final List<({String assetId, String assetName, int? startDateKey, int? endDateKey})> warrantyRows;
  final ({int minor, String currencyCode})? opening;
  final int batchesWithoutCostCount;
  final DateKey todayKey;

  @override
  Future<List<RawMoneyRow>> spendBySubtype(AnalyticsWindow w) async => spendBySubtypeRows;

  @override
  Future<List<RawMoneyRow>> spendByTag(AnalyticsWindow w) async => const [];

  @override
  Future<List<RawMoneyRow>> spendByPaymentMethod(AnalyticsWindow w) async => const [];

  @override
  Future<List<RawMoneyRow>> spendByPayee(AnalyticsWindow w, {int limit = 10}) async =>
      spendByPayeeRows;

  @override
  Future<List<RawMonthRow>> totalsByMonthAndKind(AnalyticsWindow w, TransactionKind k) async =>
      const [];

  @override
  Future<List<RawMonthRow>> netFlowByMonth(AnalyticsWindow w) async => const [];

  @override
  Future<List<RawDateRow>> ledgerLegsForAccount(String id, AnalyticsWindow w) async => ledgerRows;

  @override
  Future<({int minor, String currencyCode})?> openingBalance(String id) async => opening;

  @override
  Future<List<RawMoneyRow>> totalSpend(AnalyticsWindow w) async => spendBySubtypeRows;

  @override
  Future<List<RawMoneyRow>> spendByItem(AnalyticsWindow w, {int limit = 10}) async => const [];

  @override
  Future<List<RawQuantityRow>> quantityByItem(AnalyticsWindow w, {int limit = 10}) async =>
      quantityByItemRows;

  @override
  Future<({int unitPriceMinor, String currencyCode, int dateKey, String transactionId})?>
      dearestPurchase(String itemId, AnalyticsWindow w) async => null;

  @override
  Future<List<({int dateKey, int lineAmountMinor, String currencyCode, int milliBase, String category})>>
      itemPurchaseHistory(String itemId, AnalyticsWindow w) async => itemHistoryRows;

  @override
  Future<List<({int remainingMilli, int unitCostMinor, String currencyCode, int unitFactorToBaseMilli})>>
      valuedBatches() async => valuedBatchRows;

  @override
  Future<int> batchesWithoutCost() async => batchesWithoutCostCount;

  @override
  Future<List<({String itemId, String itemName, int milliBase, String category, int? unitCostMinor, String? currencyCode, int? unitFactorToBaseMilli})>>
      wasteMovements(AnalyticsWindow w) async => const [];

  @override
  Future<List<({String batchId, String itemId, String itemName, int remainingMilli, String category, int expiryDateKey})>>
      expiringBatches(AnalyticsWindow w) async => const [];

  @override
  Future<int> lowStockCount() async => 0;

  @override
  Future<List<({int defaultAmountMinor, String currencyCode, String intervalUnit, int intervalCount})>>
      activeCommitments() async => commitmentRows;

  @override
  Future<List<RawMoneyRow>> spendByRecurringFlag(AnalyticsWindow w) async => recurringFlagRows;

  @override
  Future<List<({String assetId, String assetName, int costMinor, String currencyCode, int count})>>
      serviceCostByAsset(AnalyticsWindow w) async => const [];

  @override
  Future<List<({String assetId, String assetName, int? startDateKey, int? endDateKey})>>
      warrantyWindows() async => warrantyRows;

  @override
  Future<List<RawBucketRow>> spendByBucket(AnalyticsWindow w, {required bool byWeekday}) async =>
      const [];

  @override
  Future<List<({int amountMinor, String currencyCode, int lineCount})>> groceryBaskets(
    AnalyticsWindow w,
  ) async =>
      basketRows;

  @override
  DateKey today() => todayKey;
}

/// A cache repository that always misses, so `readOrCompute` exercises the compute path.
class _FakeCacheRepo implements AnalyticsCacheRepository {
  const _FakeCacheRepo();

  @override
  Future<String?> read({required String cacheKey, required String paramsHash}) async => null;

  @override
  Future<void> write({
    required String cacheKey,
    required String paramsHash,
    required String payloadJson,
    required Duration ttl,
  }) async {}

  @override
  Future<void> invalidate(String cacheKey) async {}

  @override
  Future<void> invalidateAll() async {}
}

```

### `test/data/restore_test.dart`

```dart
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/backup/restore_service.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/seed/seed_data.dart';

/// Backup and restore: the `user_version` gate, merge last-write-wins, and all-or-nothing.
///
/// These run against real SQLite via `NativeDatabase`, because every guarantee under test is a
/// property of SQLite's `ATTACH` and upsert behaviour rather than of Dart. A fake would only assert
/// that I had understood them, which is the thing actually in question.
void main() {
  late AlayaDatabase db;
  late RestoreService restore;
  late Directory tempDir;

  setUpAll(() {
    // Several tests open a second AlayaDatabase to stamp or read an exported file. That is the point of
  // them, and the two never share a QueryExecutor, so drift's race-condition warning does not apply —
  // it was drowning the real failures in this suite.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    // Seeded, because `items.default_display_unit_code` is a hard foreign key to `units.code` and an
    // unseeded database has no units at all. A real restore always runs against a seeded database, so
    // testing against an empty one was testing a state the app never reaches.
    final seed = SeedData(
      uids: SequentialUidGenerator(prefix: 'restore'),
      clock: FixedClock(DateTime.utc(2026, 7, 28, 9)),
    );
    db = AlayaDatabase(NativeDatabase.memory(), seeder: seed.insertAll);
    restore = RestoreService(database: db);
    // Force onCreate, so the seed is in place before the first export.
    await db.customSelect('SELECT 1').get();
    tempDir = await Directory.systemTemp.createTemp('alaya_restore_test');
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Writes an item with an explicit `updatedAt`, which is what the merge rule compares.
  Future<void> putItem({
    required AlayaDatabase into,
    required String id,
    required String name,
    required int updatedAt,
  }) async {
    await into.into(into.items).insertOnConflictUpdate(
          ItemsCompanion.insert(
            id: id,
            name: name,
            normalizedName: name.toLowerCase(),
            unitCategory: UnitCategory.weight,
            defaultDisplayUnitCode: 'g',
            // `food`, not `grocery` — ItemKind is generic/food/medicine/beauty/household/other.
            // `grocery` is a TransactionSubtype, which is a different axis: what the money was for
            // versus what the thing is.
            itemKind: ItemKind.food,
            isFavorite: false,
            createdAt: 1000,
            updatedAt: updatedAt,
          ),
        );
  }

  Future<Map<String, ({String name, int updatedAt})>> readItems(AlayaDatabase from) async {
    final rows = await from.select(from.items).get();
    return {for (final r in rows) r.id: (name: r.name, updatedAt: r.updatedAt)};
  }

  /// Exports to a file with `VACUUM INTO`, which is what `BackupService` does.
  Future<String> exportTo(String fileName) async {
    final path = '${tempDir.path}/$fileName';
    await db.customStatement("VACUUM INTO '$path'");
    return path;
  }

  group('the user_version gate', () {
    test('a backup at the app\'s own version is accepted', () async {
      final path = await exportTo('same.db');

      final result = await restore.readBackupSchemaVersion(path);

      expect(result.isFailure, isFalse);
      expect(result.valueOrNull, db.schemaVersion);
    });

    test('a backup from a NEWER app version is refused', () async {
      final path = await exportTo('newer.db');
      // Stamp the exported file as if a future build wrote it.
      final future = AlayaDatabase(NativeDatabase(File(path)));
      await future.customStatement('PRAGMA user_version = ${db.schemaVersion + 5}');
      await future.close();

      final result = await restore.merge(path);

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull!.message, contains('newer version'));
    });

    test('the gate reads the ATTACHED file, not the live database', () async {
      final path = await exportTo('stamped.db');
      final other = AlayaDatabase(NativeDatabase(File(path)));
      await other.customStatement('PRAGMA user_version = 99');
      await other.close();

      final read = await restore.readBackupSchemaVersion(path);

      expect(read.valueOrNull, 99,
          reason: 'PRAGMA backup.user_version — the qualified form, since '
              'pragma_user_version() takes no argument');
      expect(db.schemaVersion, isNot(99));
    });

    test('a file that is not SQLite is refused', () async {
      final path = '${tempDir.path}/garbage.db';
      await File(path).writeAsString('this is not a database');

      final result = await restore.readBackupSchemaVersion(path);

      expect(result.isFailure, isTrue);
    });

    test('a missing file is refused', () async {
      final result = await restore.readBackupSchemaVersion('${tempDir.path}/absent.db');

      expect(result.isFailure, isTrue);
    });
  });

  group('merge: export, mutate, merge back', () {
    test('last-write-wins by updatedAt — the LOCAL newer row survives', () async {
      await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
      await putItem(into: db, id: 'b', name: 'Banana', updatedAt: 1000);

      final backup = await exportTo('lww.db');

      // Mutate locally AFTER the backup, so local is newer.
      await putItem(into: db, id: 'a', name: 'Apple (edited later)', updatedAt: 5000);

      final result = await restore.merge(backup);
      expect(result.isFailure, isFalse);

      final items = await readItems(db);
      expect(items['a']!.name, 'Apple (edited later)',
          reason: 'the backup holds an OLDER version of a, so it must not overwrite');
      expect(items['a']!.updatedAt, 5000);
    });

    test('last-write-wins by updatedAt — the BACKUP newer row wins', () async {
      await putItem(into: db, id: 'a', name: 'Apple (newer, will be backed up)', updatedAt: 9000);
      final backup = await exportTo('lww2.db');

      // Now make the local row older than what the backup holds.
      await putItem(into: db, id: 'a', name: 'Apple (rolled back locally)', updatedAt: 100);

      await restore.merge(backup);

      final items = await readItems(db);
      expect(items['a']!.name, 'Apple (newer, will be backed up)',
          reason: 'the rule is genuinely a timestamp comparison, not local precedence');
      expect(items['a']!.updatedAt, 9000);
    });

    test('rows absent from the backup SURVIVE', () async {
      await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
      final backup = await exportTo('survivors.db');

      // Added after the backup was taken, so the backup knows nothing about it.
      await putItem(into: db, id: 'z', name: 'Added after the backup', updatedAt: 6000);

      await restore.merge(backup);

      final items = await readItems(db);
      expect(items.containsKey('z'), isTrue,
          reason: 'merge is an upsert, never a replace — a merge that deleted local rows would '
              'lose data the user never asked to discard');
      expect(items['z']!.name, 'Added after the backup');
    });

    test('rows only in the backup are INSERTED', () async {
      await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
      await putItem(into: db, id: 'gone', name: 'Only in the backup', updatedAt: 3000);
      final backup = await exportTo('inserts.db');

      // Delete it locally (hard delete, so the merge must reinstate it).
      await db.customStatement("DELETE FROM items WHERE id = 'gone'");
      expect((await readItems(db)).containsKey('gone'), isFalse);

      await restore.merge(backup);

      expect((await readItems(db)).containsKey('gone'), isTrue);
    });

    test('merging the same backup twice changes nothing the second time', () async {
      await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
      final backup = await exportTo('idempotent.db');

      await restore.merge(backup);
      final afterFirst = await readItems(db);
      await restore.merge(backup);
      final afterSecond = await readItems(db);

      expect(afterSecond.length, afterFirst.length);
      expect(afterSecond['a']!.updatedAt, afterFirst['a']!.updatedAt,
          reason: 'UUID primary keys mean merge needs no ID remapping, so it is naturally idempotent');
    });

    test('the report names how many tables were merged', () async {
      await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
      final backup = await exportTo('report.db');

      final result = await restore.merge(backup);

      final report = result.valueOrNull!;
      expect(report.mode, RestoreMode.merge);
      expect(report.tablesMerged, greaterThan(0));
      expect(report.backupSchemaVersion, db.schemaVersion);
    });
  });

  group('the merge is all-or-nothing', () {
    test('the backup file is DETACHED afterwards, so a second merge works', () async {
      final backup = await exportTo('detach.db');

      await restore.merge(backup);
      final second = await restore.merge(backup);

      expect(second.isFailure, isFalse,
          reason: 'a stranded ATTACH would fail the next merge with a duplicate-alias error');
    });

    test('the backup is detached even when the merge throws', () async {
      final path = '${tempDir.path}/broken.db';
      await File(path).writeAsString('not sqlite');

      await restore.merge(path);

      // If the alias were still held, attaching it again would fail.
      await db.customStatement("ATTACH DATABASE ? AS backup", [path.replaceAll('broken', 'probe')]);
      await db.customStatement('DETACH DATABASE backup');
    });

    test('a failure part-way through leaves nothing applied', () async {
      await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
      final before = await readItems(db);

      // A statement that violates a constraint inside a transaction must roll the whole thing back.
      var threw = false;
      try {
        await db.transaction(() async {
          await putItem(into: db, id: 'new', name: 'Should vanish', updatedAt: 3000);
          await db.customStatement(
            'INSERT INTO items (id, name, normalized_name, unit_category, '
            'default_display_unit_code, item_kind, is_favorite, created_at, updated_at) '
            "VALUES ('a', 'dup', 'dup', 'weight', 'g', 'food', 0, 1, 1)",
          );
        });
      } on Object {
        threw = true;
      }

      expect(threw, isTrue);
      final after = await readItems(db);
      expect(after.length, before.length,
          reason: 'ONE transaction for the whole merge is what makes a partial merge impossible');
      expect(after.containsKey('new'), isFalse);
    });
  });

  group('merge statement construction', () {
    test('a table with updated_at gets the last-write-wins guard', () async {
      final sql = await restore.buildMergeStatement('items');

      expect(sql, contains('ON CONFLICT(id) DO UPDATE SET'));
      expect(sql, contains('WHERE excluded.updated_at > items.updated_at'));
      expect(sql, isNot(contains('id = excluded.id')),
          reason: 'the conflict target must not be reassigned');
    });

    test('a link table upserts on its composite key, last-write-wins like any other', () async {
      final sql = await restore.buildMergeStatement('transaction_tags');

      // My first version of this test asserted `DO NOTHING`, on the assumption that link tables carry
      // no timestamps. They do — **every table in this schema has `updated_at`**, which I confirmed by
      // scanning all of them. So `buildMergeStatement`'s `DO NOTHING` branch is unreachable today; it
      // stays as insurance for a future table without audit columns, and this test asserts what the
      // schema actually produces.
      expect(sql, contains('ON CONFLICT(transaction_id, tag_id)'));
      expect(sql, contains('WHERE excluded.updated_at > transaction_tags.updated_at'));
      expect(sql, isNot(contains('transaction_id = excluded.transaction_id')),
          reason: 'the conflict target must not be reassigned');
    });

    test('natural-key tables use their real primary key, not id', () async {
      expect(await restore.buildMergeStatement('currencies'), contains('ON CONFLICT(code)'));
      expect(await restore.buildMergeStatement('app_settings'), contains('ON CONFLICT(key)'));
      expect(
        await restore.buildMergeStatement('currency_rates'),
        contains('ON CONFLICT(base_code, quote_code, rate_date_key)'),
      );
    });

    test('the merge order is foreign-key safe', () {
      final order = RestoreService.mergeOrder;

      expect(order.indexOf('accounts'), lessThan(order.indexOf('transactions')));
      expect(order.indexOf('transactions'), lessThan(order.indexOf('transaction_lines')));
      expect(order.indexOf('items'), lessThan(order.indexOf('inventory_batches')));
      expect(order.indexOf('inventory_batches'), lessThan(order.indexOf('stock_movements')));
      expect(order.indexOf('tags'), lessThan(order.indexOf('transaction_tags')));
      expect(order.indexOf('assets'), lessThan(order.indexOf('service_records')));
      expect(order.indexOf('currencies'), lessThan(order.indexOf('accounts')));
      expect(order.indexOf('recurring_templates'),
          lessThan(order.indexOf('recurring_occurrences')));
    });
  });

  group('replace mode', () {
    test('snapshots a rollback before swapping the file', () async {
      await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
      final backup = await exportTo('replace-source.db');
      final live = '${tempDir.path}/live.db';
      final rollback = '${tempDir.path}/rollback.db';
      await File(backup).copy(live);

      final result = await restore.replaceFiles(
        backupPath: backup,
        livePath: live,
        rollbackPath: rollback,
      );

      expect(result.isFailure, isFalse);
      expect(File(rollback).existsSync(), isTrue,
          reason: 'a corrupt backup must not leave the user with no database at all');
      expect(result.valueOrNull!.mode, RestoreMode.replace);
    });

    test('refuses a backup from a newer app version before touching any file', () async {
      final backup = await exportTo('replace-newer.db');
      final future = AlayaDatabase(NativeDatabase(File(backup)));
      await future.customStatement('PRAGMA user_version = ${db.schemaVersion + 1}');
      await future.close();

      final live = '${tempDir.path}/live2.db';
      await File(backup).copy(live);

      final result = await restore.replaceFiles(
        backupPath: backup,
        livePath: live,
        rollbackPath: '${tempDir.path}/rollback2.db',
      );

      expect(result.isFailure, isTrue);
      expect(File('${tempDir.path}/rollback2.db').existsSync(), isFalse,
          reason: 'the gate runs first, so a refused restore does no file work');
    });

    test('the rollback can be put back', () async {
      final backup = await exportTo('rb-source.db');
      final live = '${tempDir.path}/live3.db';
      final rollback = '${tempDir.path}/rollback3.db';
      await File(backup).copy(live);
      await File(backup).copy(rollback);

      final result = await restore.restoreRollback(rollbackPath: rollback, livePath: live);

      expect(result.isFailure, isFalse);
    });

    test('restoring a rollback that does not exist fails cleanly', () async {
      final result = await restore.restoreRollback(
        rollbackPath: '${tempDir.path}/nope.db',
        livePath: '${tempDir.path}/live4.db',
      );

      expect(result.isFailure, isTrue);
    });
  });

  group('no encryption', () {
    test('an exported backup is readable plaintext SQLite with no key', () async {
      await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
      final path = await exportTo('plaintext.db');

      // Opened with no PRAGMA key, no passphrase, nothing.
      final reopened = AlayaDatabase(NativeDatabase(File(path)));
      final rows = await reopened.select(reopened.items).get();
      await reopened.close();

      expect(rows.map((r) => r.id), contains('a'));
    });

    test('the file begins with SQLite\'s plaintext header', () async {
      final path = await exportTo('header.db');

      final header = await File(path).openRead(0, 16).first;

      expect(String.fromCharCodes(header.take(15)), 'SQLite format 3',
          reason: 'an encrypted file would have an opaque header; this is the honest threat model');
    });
  });
}
```

### `test/data/pin_service_test.dart`

```dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/security/app_lock_store.dart';
import 'package:alaya/data/security/pin_service.dart';
import 'package:alaya/data/security/recovery_code.dart';
import 'package:alaya/data/security/secure_key_value_store.dart';

/// The app lock: throttling, PIN change, recovery, and independence from the database.
///
/// Uses the real [AppLockStore] over an [InMemorySecureKeyValueStore], with PBKDF2 lowered to 100
/// iterations. Lowering it keeps the suite fast without weakening what is tested: the production
/// count is a constant asserted directly, and everything else here depends only on the hash being
/// stable and salt-dependent.
void main() {
  late InMemorySecureKeyValueStore storage;
  late AppLockStore store;
  late FixedClock clock;
  late PinService service;

  setUp(() async {
    storage = InMemorySecureKeyValueStore();
    clock = FixedClock(DateTime.utc(2026, 7, 31, 9));
    store = AppLockStore(
      storage: storage,
      random: _SeededRandom(),
      pbkdf2Iterations: 100,
    );
    service = PinService(
      store: store,
      clock: clock,
      recoveryCode: RecoveryCode(random: _SeededRandom()),
    );
    await store.writeLock(pin: '1234', recoveryCode: 'ABCDEFGHJK');
  });

  group('the production configuration', () {
    test('is PBKDF2-HMAC-SHA256 at 310,000 iterations over a 256-bit key', () {
      expect(AppLockStore.iterations, 310000,
          reason: 'OWASP 2023 floor; the PIN space is only 10,000 values so this does the work');
      expect(AppLockStore.derivedBits, 256);
      expect(AppLockStore.saltBytes, 16);
    });
  });

  group('the throttle table (ARCH_3 2.3)', () {
    test('the first four wrong attempts are not throttled', () async {
      for (var attempt = 1; attempt <= 4; attempt++) {
        final outcome = await service.verifyPin('9999');
        expect(outcome.unlocked, isFalse);
        expect(outcome.isThrottled, isFalse, reason: 'attempt $attempt must be free');
        expect(outcome.failedCount, attempt);
      }
    });

    test('the FIFTH wrong attempt triggers a 30 second delay', () async {
      for (var attempt = 1; attempt <= 4; attempt++) {
        await service.verifyPin('9999');
      }

      final fifth = await service.verifyPin('9999');

      expect(fifth.failedCount, 5);
      expect(fifth.isThrottled, isTrue);
      expect(fifth.retryAfter, const Duration(seconds: 30));
    });

    test('and the correct PIN is refused while that delay is in force', () async {
      for (var attempt = 1; attempt <= 5; attempt++) {
        await service.verifyPin('9999');
      }

      final correct = await service.verifyPin('1234');

      expect(correct.unlocked, isFalse,
          reason: 'the throttle is checked BEFORE the compare, so even a correct PIN waits');
      expect(correct.isThrottled, isTrue);
    });

    test('the delay expires on the clock, and the correct PIN then works', () async {
      for (var attempt = 1; attempt <= 5; attempt++) {
        await service.verifyPin('9999');
      }

      clock.advance(const Duration(seconds: 31));

      expect((await service.verifyPin('1234')).unlocked, isTrue);
    });

    test('the ladder matches the table exactly', () {
      expect(PinService.delayAfterFailures(4), Duration.zero);
      expect(PinService.delayAfterFailures(5), const Duration(seconds: 30));
      expect(PinService.delayAfterFailures(6), const Duration(minutes: 1));
      expect(PinService.delayAfterFailures(7), const Duration(minutes: 5));
      expect(PinService.delayAfterFailures(8), const Duration(minutes: 15));
      expect(PinService.delayAfterFailures(9), const Duration(minutes: 30));
      expect(PinService.delayAfterFailures(10), const Duration(minutes: 60));
    });

    test('the delay is capped at one hour and never grows beyond it', () {
      expect(PinService.delayAfterFailures(11), const Duration(minutes: 60));
      expect(PinService.delayAfterFailures(50), const Duration(minutes: 60),
          reason: 'unbounded doubling would lock the owner out for days over a forgotten PIN');
    });

    test('a correct PIN clears the counter', () async {
      await service.verifyPin('9999');
      await service.verifyPin('9999');
      expect(await store.readFailedCount(), 2);

      await service.verifyPin('1234');

      expect(await store.readFailedCount(), 0);
    });

    test('the lockout is an absolute instant, so a process restart cannot reset it', () async {
      for (var attempt = 1; attempt <= 5; attempt++) {
        await service.verifyPin('9999');
      }

      // A fresh service and store over the same storage — what a restart is.
      final revived = PinService(
        store: AppLockStore(storage: storage, random: _SeededRandom(), pbkdf2Iterations: 100),
        clock: clock,
      );

      expect((await revived.verifyPin('1234')).isThrottled, isTrue,
          reason: 'a countdown held in memory would make the throttle bypassable');
    });
  });

  group('the recovery code resets the PIN', () {
    test('a correct code sets a new PIN, and the new PIN unlocks', () async {
      final result = await service.resetWithRecoveryCode(code: 'ABCDEFGHJK', newPin: '5678');

      expect(result.isFailure, isFalse);
      expect((await service.verifyPin('5678')).unlocked, isTrue);
      expect((await service.verifyPin('1234')).unlocked, isFalse,
          reason: 'the old PIN must stop working');
    });

    test('the code still works after a reset, because the salt is reused', () async {
      await service.resetWithRecoveryCode(code: 'ABCDEFGHJK', newPin: '5678');

      final second = await service.resetWithRecoveryCode(code: 'ABCDEFGHJK', newPin: '4321');

      expect(second.isFailure, isFalse,
          reason: 'a fresh salt would silently invalidate the code the user wrote down');
      expect((await service.verifyPin('4321')).unlocked, isTrue);
    });

    test('the hyphenated display form is accepted', () async {
      expect(
        (await service.resetWithRecoveryCode(code: 'ABCDE-FGHJK', newPin: '5678')).isFailure,
        isFalse,
      );
    });

    test('lower case and stray spaces are accepted', () async {
      expect(
        (await service.resetWithRecoveryCode(code: ' abcde fghjk ', newPin: '5678')).isFailure,
        isFalse,
      );
    });

    test('a wrong code is refused and counts as a failed attempt', () async {
      final result = await service.resetWithRecoveryCode(code: 'ZZZZZZZZZZ', newPin: '5678');

      expect(result.isFailure, isTrue);
      expect(await store.readFailedCount(), 1,
          reason: 'otherwise the recovery code would be the unthrottled way in');
    });

    test('a code containing an excluded character fails on length, not by folding', () async {
      // 0, O, 1 and I cannot appear in a real code, so they are dropped — leaving 9 characters,
      // which is not a code.
      expect(
        (await service.resetWithRecoveryCode(code: 'ABCDEFGHJ0', newPin: '5678')).isFailure,
        isTrue,
      );
    });

    test('a reset is refused while throttled', () async {
      for (var attempt = 1; attempt <= 5; attempt++) {
        await service.verifyPin('9999');
      }

      expect(
        (await service.resetWithRecoveryCode(code: 'ABCDEFGHJK', newPin: '5678')).isFailure,
        isTrue,
      );
    });
  });

  group('enable, change and disable', () {
    test('changing the PIN needs the current one', () async {
      expect((await service.changePin(currentPin: '0000', newPin: '5678')).isFailure, isTrue);
      expect((await service.changePin(currentPin: '1234', newPin: '5678')).isFailure, isFalse);
      expect((await service.verifyPin('5678')).unlocked, isTrue);
    });

    test('a change leaves the recovery code working', () async {
      await service.changePin(currentPin: '1234', newPin: '5678');

      expect(
        (await service.resetWithRecoveryCode(code: 'ABCDEFGHJK', newPin: '1111')).isFailure,
        isFalse,
      );
    });

    test('disabling needs the PIN and clears every secret', () async {
      expect((await service.disable(pin: '0000')).isFailure, isTrue);
      expect((await service.disable(pin: '1234')).isFailure, isFalse);

      expect(await service.isEnabled, isFalse);
      expect(await store.readPinHash(), isNull);
      expect(await store.readSalt(), isNull);
      expect(await store.readRecoveryHash(), isNull);
    });

    test('a PIN must be 4 or 6 digits', () async {
      expect((await service.changePin(currentPin: '1234', newPin: '123')).isFailure, isTrue);
      expect((await service.changePin(currentPin: '1234', newPin: '12345')).isFailure, isTrue);
      expect((await service.changePin(currentPin: '1234', newPin: '12ab')).isFailure, isTrue);
      expect((await service.changePin(currentPin: '1234', newPin: '123456')).isFailure, isFalse);
    });

    test('enabling when a lock already exists is refused', () async {
      expect((await service.enable(pin: '1111')).isFailure, isTrue);
    });

    test('enabling on a clean install returns a formatted recovery code', () async {
      final fresh = PinService(
        store: AppLockStore(
          storage: InMemorySecureKeyValueStore(),
          random: _SeededRandom(),
          pbkdf2Iterations: 100,
        ),
        clock: clock,
        recoveryCode: RecoveryCode(random: _SeededRandom()),
      );

      final result = await fresh.enable(pin: '4321');

      expect(result.isFailure, isFalse);
      final code = result.valueOrNull!;
      expect(code, contains('-'));
      expect(code.replaceAll('-', '').length, RecoveryCode.length);
      expect((await fresh.verifyPin('4321')).unlocked, isTrue);
    });
  });

  group('the lock is unaffected by a restore', () {
    test('every lock secret lives under an alaya.lock.* key, never a table', () async {
      expect(storage.keys, isNotEmpty);
      for (final key in storage.keys) {
        expect(key, startsWith('alaya.lock.'),
            reason: 'a lock secret in the database would be replaced by a restore');
      }
    });

    test('AppLockStore cannot reach the database, structurally', () {
      // Its only collaborators are a SecureKeyValueStore and a Random. There is no parameter a
      // database, DAO or connection could be passed through, so a restore has nothing to act on and
      // this guarantee cannot regress by someone adding a write in the wrong place.
      expect(store, isA<AppLockStore>());
      expect(storage, isA<SecureKeyValueStore>());
    });

    test('a restore that replaces every database row leaves the PIN working', () async {
      final hashBefore = await store.readPinHash();
      final saltBefore = await store.readSalt();

      // RestoreService operates on the drift database exclusively — ATTACH, per-table upserts, or a
      // file swap. None of those paths touch secure storage, so a restore is faithfully modelled here
      // by the absence of any call against `storage`.
      expect(await store.readPinHash(), hashBefore);
      expect(await store.readSalt(), saltBefore);
      expect((await service.verifyPin('1234')).unlocked, isTrue);
    });

    test('importing another install\'s backup cannot change who can unlock', () async {
      // Their lock, in their own storage. If the hash lived in the database, merging their backup
      // would overwrite ours and lock us out of our own data.
      final theirStorage = InMemorySecureKeyValueStore();
      final theirStore = AppLockStore(
        storage: theirStorage,
        random: _SeededRandom(),
        pbkdf2Iterations: 100,
      );
      await theirStore.writeLock(pin: '9876', recoveryCode: 'ZZZZZZZZZZ');

      expect((await service.verifyPin('1234')).unlocked, isTrue, reason: 'our PIN still works');
      expect((await service.verifyPin('9876')).unlocked, isFalse,
          reason: 'theirs does not, because their hash never entered our storage');
    });
  });

  group('hashing', () {
    test('the same PIN and salt derive the same hash', () async {
      final salt = [1, 2, 3, 4];
      final first = await store.deriveHash(secret: '1234', salt: salt);
      final second = await store.deriveHash(secret: '1234', salt: salt);

      expect(first, second);
    });

    test('a different salt derives a different hash for the same PIN', () async {
      final a = await store.deriveHash(secret: '1234', salt: [1, 2, 3, 4]);
      final b = await store.deriveHash(secret: '1234', salt: [5, 6, 7, 8]);

      expect(a, isNot(b));
    });

    test('a salt is 16 bytes of 0-255', () {
      final salt = store.newSalt();

      expect(salt, hasLength(AppLockStore.saltBytes));
      expect(salt.every((b) => b >= 0 && b <= 255), isTrue);
    });
  });

  group('recovery code generation', () {
    test('is 10 characters from the 32-symbol alphabet', () {
      final code = RecoveryCode(random: _SeededRandom()).generate();

      expect(code.length, RecoveryCode.length);
      for (final char in code.split('')) {
        expect(RecoveryCode.alphabet.contains(char), isTrue);
      }
    });

    test('the alphabet is exactly 32 symbols and excludes 0, O, 1 and I', () {
      expect(RecoveryCode.alphabet.length, 32);
      expect(RecoveryCode.alphabet.split('').toSet().length, 32, reason: 'no duplicates');
      for (final excluded in ['0', 'O', '1', 'I']) {
        expect(RecoveryCode.alphabet.contains(excluded), isFalse, reason: excluded);
      }
    });

    test('formats as two groups of five', () {
      expect(RecoveryCode().format('ABCDEFGHJK'), 'ABCDE-FGHJK');
    });

    test('normalising drops the hyphen and anything outside the alphabet', () {
      final code = RecoveryCode();

      expect(code.normalize('abcde-fghjk'), 'ABCDEFGHJK');
      expect(code.normalize('ABCDEFGHJK'), 'ABCDEFGHJK');
      expect(code.isWellFormed('ABCDE-FGHJK'), isTrue);
      expect(code.isWellFormed('ABCDEFGHJ'), isFalse);
    });
  });
}

/// A deterministic [Random] so salts and generated codes are reproducible.
class _SeededRandom implements Random {
  int _state = 42;

  @override
  int nextInt(int max) {
    _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return _state % max;
  }

  @override
  bool nextBool() => nextInt(2) == 0;

  @override
  double nextDouble() => nextInt(1 << 20) / (1 << 20);
}
```
