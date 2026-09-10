import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// Why a biometric prompt did not unlock.
enum BiometricRefusal {
  /// The device has no enrolled biometric, or none the app may use.
  unavailable,

  /// The user dismissed the prompt or failed the check.
  rejected,

  /// The platform refused — too many attempts, or a hardware lockout of its own.
  lockedOut,
}

/// The biometric shortcut on the lock screen (ARCH_3 §2.2).
///
/// **A shortcut and nothing more, which is why the contract is this small.** No key material is involved
/// — the database is plaintext and the PIN is a UI gate — so a successful biometric check is exactly as
/// authoritative as a correct PIN and no more. Anything richer here would imply otherwise.
///
/// A port because `local_auth` needs a platform channel: without one, a widget test of the lock screen
/// could not run, and §9.1 requires four of them per screen.
abstract interface class BiometricGate {
  /// Whether this device can offer the shortcut at all.
  ///
  /// Checked before the button is shown rather than after it is pressed. Offering a shortcut that then
  /// says "not available" is the control ARCH_5 §10 objects to — one that looks live and is not.
  Future<bool> get isAvailable;

  /// Prompts, returning the refusal rather than throwing when it does not succeed.
  ///
  /// [reason] is the already-localised sentence the platform shows, so no string literal reaches the
  /// plugin (Law U5).
  Future<Result<void, Failure>> authenticate({required String reason});
}
