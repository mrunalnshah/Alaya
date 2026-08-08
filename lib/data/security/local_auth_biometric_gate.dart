import 'package:local_auth/local_auth.dart';

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/services/lock/biometric_gate.dart';

/// The production [BiometricGate], over `local_auth`.
///
/// **The only file in this phase that imports `local_auth`.** Confining it is the same containment 7A
/// applied to `table_calendar` and 7B to `fl_chart` — the plugin's surface could not be compiled against
/// in the session that wrote this (ARCH_4 R22), so if it differs, one file changes rather than the lock
/// screen.
///
/// **Every failure is a `Result`, never an exception.** `local_auth` throws a `PlatformException` for a
/// missing enrolment, a hardware lockout and a user cancellation alike, and a lock screen that crashes
/// because somebody tapped the wrong thing is worse than one with no shortcut at all.
final class LocalAuthBiometricGate implements BiometricGate {
  /// Creates the gate over [auth].
  const LocalAuthBiometricGate(this._auth);

  final LocalAuthentication _auth;

  /// Whether the shortcut is offered at all.
  ///
  /// **False, and that is a security decision rather than a stub.** Two attempts at the installed
  /// `local_auth`'s signature were rejected by the analyzer — first `options: AuthenticationOptions(...)`,
  /// then `stickyAuth:`/`biometricOnly:` as direct parameters — so `authenticate` here accepts
  /// `localizedReason` and nothing this file can identify.
  ///
  /// Without `biometricOnly`, the platform prompt may offer **device-credential fallback**: the phone's own
  /// PIN or pattern would satisfy Alaya's lock. That is precisely the threat ARCH_3 §2.5 says this lock
  /// exists for — someone holding an already-unlocked phone — so shipping the shortcut unconstrained would
  /// quietly undo the guarantee the lock screen makes in writing.
  ///
  /// A convenience is the right thing to lose to uncertainty. The shortcut is optional in ARCH_3 §2.2,
  /// `LockScreen` already omits the key entirely when this is false (asserted in `lock_screen_test.dart`),
  /// and re-enabling it is this one constant plus the options `authenticate` turns out to accept.
  static const bool shortcutEnabled = false;

  @override
  Future<bool> get isAvailable async {
    if (!shortcutEnabled) return false;
    try {
      // Both checks, because they answer different questions: the device may have the hardware while
      // the user has enrolled nothing, and offering a shortcut that cannot work is the dead control
      // ARCH_5 §10 objects to.
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      return _auth.canCheckBiometrics;
    } on Object {
      return false;
    }
  }

  @override
  Future<Result<void, Failure>> authenticate({required String reason}) async {
    try {
      // `localizedReason` only: it is the one parameter every published `local_auth` signature has agreed
      // on. **Unreachable while [shortcutEnabled] is false**, and the options that constrain the prompt to
      // biometrics must be restored here before that flag is flipped back.
      final ok = await _auth.authenticate(localizedReason: reason);
      return ok
          ? const Result.ok(null)
          : const Result.failure(
              BusinessRuleFailure('Not recognised.', rule: 'biometricRejected'),
            );
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The fingerprint check could not run.', cause: error),
      );
    }
  }
}
