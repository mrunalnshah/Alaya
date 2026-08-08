/// The app lock's contract, and the vocabulary an unlock attempt answers in.
///
/// **Why this exists in `domain/` when `PinService` already exists in `data/`.** `PinService` reaches
/// `flutter_secure_storage` through `AppLockStore`, and Law L12 bars a plugin dependency from `domain/`
/// — which is why it was written in `data/` in the first place. But ARCH_1 §6 draws `features → domain →
/// core` and `data → domain → core` as two separate chains, and not one of the seven delivered UI phases
/// imports `data/` from a feature. A lock screen that must branch on [UnlockRefusal] and read
/// [UnlockOutcome.retryAfter] for its countdown would have been the first.
///
/// **The deciding argument is not purity, and it is stronger than a layering diagram.** `PinService` is
/// declared `final class`, which in Dart 3 means it can be neither extended nor implemented outside its
/// own library — so a test fake of it is not awkward, it is **impossible**. `flutter_secure_storage` needs
/// a platform channel, so the real one cannot run in a widget test either. Between the two, the lock
/// screen's four required states (§9.1) had no way to be tested at all. Behind this interface they test
/// against a fake, which is the same reason `Clock` and `SecureKeyValueStore` are interfaces rather than
/// direct plugin calls. `BackupService` is `final` too, and `DataTransferPort` exists for the same reason.
///
/// This is the `AnalyticsPort` pattern: the contract in `domain/`, the plugin-bound implementation in
/// `data/`, the provider typed as the contract so no feature can reach past it.
library;

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

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

/// Verifies, changes, enables and disables the app lock.
///
/// **No encryption, and the contract says so where an implementer will read it.** The lock is a UI gate
/// over a plaintext database (ARCH_1 §2.1): nothing here derives a database key, and nothing here can
/// lock a user out of their own data. That is what makes the "forgot both" path able to export a readable
/// backup before erasing, which is the improvement dropping encryption bought (ARCH_3 §2.2).
abstract interface class AppLock {
  /// How many characters a recovery code has (ARCH_3 §2.1).
  ///
  /// **On the contract because the field that accepts one needs it**, and `RecoveryCode.length` lives in
  /// `data/` where a feature may not reach. A counter that disagreed with the validator would tell the
  /// user their correct code was the wrong length.
  static const int recoveryCodeLength = 10;

  /// Whether a lock is configured.
  Future<bool> get isEnabled;

  /// How many digits the configured PIN has.
  Future<int> readPinLength();

  /// How long until the next attempt will be checked, or null when none is owed.
  Future<Duration?> remainingLockout();

  /// How many consecutive wrong attempts have been recorded.
  ///
  /// Read by the optional auto-erase, which fires at ARCH_3 §2.3's tenth failure — the count has to be
  /// legible to the caller for that, not only to the throttle.
  Future<int> readFailedCount();

  /// Attempts to unlock with [pin].
  Future<UnlockOutcome> verifyPin(String pin);

  /// Enables the lock with [pin], returning the recovery code to show **once**.
  Future<Result<String, Failure>> enable({required String pin});

  /// Changes the PIN, verifying [currentPin] first. The recovery code is unchanged.
  Future<Result<void, Failure>> changePin({
    required String currentPin,
    required String newPin,
  });

  /// Disables the lock, verifying [pin] first.
  Future<Result<void, Failure>> disable({required String pin});

  /// Resets the PIN using [code], for the forgotten-PIN path.
  Future<Result<void, Failure>> resetWithRecoveryCode({
    required String code,
    required String newPin,
  });
}
