import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/security/app_lock_store.dart';
import 'package:alaya/data/security/recovery_code.dart';
import 'package:alaya/domain/services/lock/app_lock.dart';

/// Verifies, changes, enables and disables the app lock, and enforces ARCH_3 §2.3's throttle.
///
/// **No encryption.** The lock is a UI gate over a plaintext database (ARCH_1 §2.1), so nothing here
/// derives a database key and nothing here can lock a user out of their own data — the "forgot both"
/// path can still export a readable backup, which is the improvement dropping encryption bought.
final class PinService implements AppLock {
  /// Creates the service.
  PinService({
    required AppLockStore store,
    required Clock clock,
    RecoveryCode? recoveryCode,
  }) : _store = store,
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

  @override
  Future<bool> get isEnabled => _store.isEnabled;

  /// How many digits the configured PIN has.
  ///
  /// Delegated rather than reimplemented: the store owns the value because it is written alongside the
  /// hash, and a second source of truth for "is this a 4- or 6-box keypad" would eventually disagree
  /// with the PIN it is asking for.
  @override
  Future<int> readPinLength() => _store.readPinLength();

  /// How many consecutive wrong attempts have been recorded.
  ///
  /// Exposed for the optional auto-erase, which fires at ARCH_3 §2.3's tenth failure. The throttle
  /// already reads this internally; the caller needs it too, and reaching around this class to the store
  /// would put a second consumer on a field only this class is supposed to interpret.
  @override
  Future<int> readFailedCount() => _store.readFailedCount();

  @override
  Future<Duration?> remainingLockout() async {
    final until = await _store.readLockedUntilUtc();
    if (until == null) return null;
    final remaining = until.difference(_clock.now().toUtc());
    return remaining.isNegative || remaining == Duration.zero
        ? null
        : remaining;
  }

  /// Attempts to unlock with [pin].
  ///
  /// Checks the throttle **before** comparing, so a throttled attempt costs no PBKDF2 work and
  /// cannot be used to time the comparison.
  @override
  Future<UnlockOutcome> verifyPin(String pin) async {
    final hash = await _store.readPinHash();
    final salt = await _store.readSalt();
    if (hash == null || salt == null) {
      return const UnlockOutcome(
        unlocked: false,
        refusal: UnlockRefusal.notEnabled,
      );
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
  @override
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
        BusinessRuleFailure(
          'That recovery code is not correct.',
          rule: 'wrongRecoveryCode',
        ),
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
  @override
  Future<Result<String, Failure>> enable({required String pin}) async {
    if (await _store.isEnabled) {
      return const Result.failure(
        BusinessRuleFailure(
          'A lock is already set.',
          rule: 'lockAlreadyEnabled',
        ),
      );
    }
    final pinCheck = _validatePinFormat(pin);
    if (pinCheck != null) return Result.failure(pinCheck);

    final code = _recoveryCode.generate();
    await _store.writeLock(pin: pin, recoveryCode: code, pinLength: pin.length);
    return Result.ok(_recoveryCode.format(code));
  }

  /// Changes the PIN, verifying [currentPin] first. The recovery code is unchanged.
  @override
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
  @override
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
      refusal: delay > Duration.zero
          ? UnlockRefusal.throttled
          : UnlockRefusal.wrongPin,
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
