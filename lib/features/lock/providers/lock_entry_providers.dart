/// View-model state for the lock screen (ARCH_5 U19).
///
/// **Neither `AppLock` nor `UnlockOutcome` is named here, and that is deliberate.** Dart needs an import
/// only to *write* a type, not to call a member on an inferred one — so this file drives the lock through
/// `pinServiceProvider` and translates the outcome into [LockEntryError] before the screen sees anything.
/// The screen therefore owns every string (Law U5) while this owns every decision about which applies.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/domain/services/lock/app_lock.dart';
import 'package:alaya/features/lock/providers/lock_providers.dart';

/// What the lock screen is showing.
class LockEntryState {
  /// Creates a state.
  const LockEntryState({
    required this.pinLength,
    this.entered = '',
    this.shakeTrigger = 0,
    this.failedCount = 0,
    this.remaining,
    this.isChecking = false,
    this.biometricAvailable = false,
    this.isErasing = false,
    this.message,
  });

  /// How many digits the configured PIN has, so the field knows when it is full.
  final int pinLength;

  /// What has been typed.
  final String entered;

  /// Incremented on every rejection, so two failures shake twice (ARCH_5 §2.6).
  final int shakeTrigger;

  /// Consecutive wrong attempts recorded so far.
  final int failedCount;

  /// How long until the next attempt will even be checked, or null when none is owed.
  ///
  /// **Ticks down while the screen is open**, because a throttle the user cannot see reads as the app
  /// having frozen — and the countdown is the difference between "wait 30 seconds" and "this is broken".
  final Duration? remaining;

  /// Whether a check is in flight.
  final bool isChecking;

  /// Whether this device can offer the biometric shortcut.
  final bool biometricAvailable;

  /// Whether the ten-failure auto-erase is running.
  final bool isErasing;

  /// The reason the last attempt was refused, already localised by the screen.
  final String? message;

  /// Whether a delay is in force.
  bool get isThrottled => remaining != null;

  /// Whether the entered PIN is long enough to submit.
  bool get isComplete => entered.length >= pinLength;

  /// A copy with the given fields replaced.
  LockEntryState copyWith({
    int? pinLength,
    String? entered,
    int? shakeTrigger,
    int? failedCount,
    Duration? remaining,
    bool clearRemaining = false,
    bool? isChecking,
    bool? biometricAvailable,
    bool? isErasing,
    String? message,
    bool clearMessage = false,
  }) => LockEntryState(
    pinLength: pinLength ?? this.pinLength,
    entered: entered ?? this.entered,
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    failedCount: failedCount ?? this.failedCount,
    remaining: clearRemaining ? null : (remaining ?? this.remaining),
    isChecking: isChecking ?? this.isChecking,
    biometricAvailable: biometricAvailable ?? this.biometricAvailable,
    isErasing: isErasing ?? this.isErasing,
    message: clearMessage ? null : (message ?? this.message),
  );
}

/// Why the last attempt failed, in terms the screen can localise.
///
/// A separate signal from [LockEntryState.message] so the screen owns every string (Law U5) while the
/// view-model owns the decision about which one applies.
enum LockEntryError {
  /// The PIN was wrong and no delay is owed yet.
  wrongPin,

  /// A delay is in force.
  throttled,

  /// The biometric prompt did not succeed.
  biometricFailed,

  /// The erase failed.
  eraseFailed,
}

/// The lock screen's entry state.
final lockEntryProvider = NotifierProvider<LockEntryNotifier, LockEntryState>(
  LockEntryNotifier.new,
);

/// Drives PIN entry, the throttle countdown, the biometric shortcut and the auto-erase.
class LockEntryNotifier extends Notifier<LockEntryState> {
  Timer? _ticker;

  @override
  LockEntryState build() {
    ref.onDispose(() => _ticker?.cancel());
    unawaited(_prime());
    return const LockEntryState(pinLength: 4);
  }

  /// The last error, for the screen to turn into a sentence.
  LockEntryError? get lastError => _lastError;
  LockEntryError? _lastError;

  Future<void> _prime() async {
    final lock = ref.read(pinServiceProvider);
    final length = await lock.readPinLength();
    final failed = await lock.readFailedCount();
    final remaining = await lock.remainingLockout();
    final biometric = await ref.read(biometricGateProvider).isAvailable;
    state = state.copyWith(
      pinLength: length,
      failedCount: failed,
      remaining: remaining,
      biometricAvailable: biometric,
    );
    if (remaining != null) _startTicker();
  }

  /// Appends a digit, submitting automatically once the PIN is long enough.
  ///
  /// **Auto-submits rather than waiting for a button.** A four-digit PIN with a separate Enter is five
  /// taps for a screen the user passes through several times a day, and there is nothing to review — the
  /// field is either right or it is not.
  Future<void> append(String digit) async {
    if (state.isThrottled || state.isChecking) return;
    final next = state.entered + digit;
    state = state.copyWith(entered: next, clearMessage: true);
    if (next.length >= state.pinLength) await submit();
  }

  /// Removes the last digit.
  void backspace() {
    if (state.entered.isEmpty) return;
    state = state.copyWith(
      entered: state.entered.substring(0, state.entered.length - 1),
      clearMessage: true,
    );
  }

  /// Checks the entered PIN.
  Future<void> submit() async {
    if (state.isThrottled || state.isChecking) return;
    state = state.copyWith(isChecking: true);
    final outcome = await ref.read(pinServiceProvider).verifyPin(state.entered);

    if (outcome.unlocked) {
      _ticker?.cancel();
      _lastError = null;
      state = state.copyWith(
        isChecking: false,
        entered: '',
        clearMessage: true,
      );
      ref.read(lockPhaseProvider.notifier).markUnlocked();
      return;
    }

    // **`notEnabled` means there is nothing to unlock, so let the user through.** Mapping it to `wrongPin` — as
    // this did — traps somebody behind a PIN that does not exist, and every digit they try says "not right". It
    // should be unreachable now that the phase is resolved before the first frame, but a lock screen with no way
    // past it is bad enough to guard twice.
    if (outcome.refusal == UnlockRefusal.notEnabled) {
      _lastError = null;
      state = state.copyWith(
        isChecking: false,
        entered: '',
        clearMessage: true,
      );
      ref.read(lockPhaseProvider.notifier).markUnlocked();
      return;
    }
    _lastError = outcome.isThrottled
        ? LockEntryError.throttled
        : LockEntryError.wrongPin;
    state = state.copyWith(
      isChecking: false,
      // Cleared, so the next attempt starts from an empty field rather than the user having to delete
      // four digits they already know are wrong.
      entered: '',
      shakeTrigger: state.shakeTrigger + 1,
      failedCount: outcome.failedCount,
      remaining: outcome.retryAfter,
    );
    if (outcome.retryAfter != null) _startTicker();

    // **Checked here and not inside `PinService`.** The service enforces ARCH_3 §2.3's throttle for
    // everyone; the erase is an opt-in the user turned on in Settings, so the decision belongs where the
    // setting is readable. Default off (§2.3), which is why an unset key reads as false.
    if (outcome.failedCount >= autoEraseFailureThreshold) {
      final enabled = await ref.read(autoEraseEnabledProvider.future);
      if (enabled) await _eraseEverything();
    }
  }

  /// Tries the biometric shortcut.
  ///
  /// **Subject to the same throttle as a PIN.** Otherwise the shortcut would be the cheaper of the two
  /// paths to attack, and a lock is only as strong as the weakest way in.
  Future<void> useBiometric({required String reason}) async {
    if (state.isThrottled || state.isChecking) return;
    state = state.copyWith(isChecking: true, clearMessage: true);
    final result = await ref
        .read(biometricGateProvider)
        .authenticate(reason: reason);
    if (result.isOk) {
      _lastError = null;
      state = state.copyWith(isChecking: false);
      ref.read(lockPhaseProvider.notifier).markUnlocked();
      return;
    }
    _lastError = LockEntryError.biometricFailed;
    state = state.copyWith(
      isChecking: false,
      // **No `shakeTrigger` and no `failedCount`.** A dismissed fingerprint prompt is not a wrong PIN,
      // and counting it toward the throttle would let a pocket-tap lock somebody out.
      message: '',
    );
  }

  Future<void> _eraseEverything() async {
    state = state.copyWith(isErasing: true);
    final result = await ref.read(dataTransferPortProvider).eraseEverything();
    state = state.copyWith(isErasing: false);
    if (result.isFailure) {
      _lastError = LockEntryError.eraseFailed;
      return;
    }
    // The erase clears the lock too, so there is nothing left to unlock.
    await ref.read(lockPhaseProvider.notifier).refresh();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final remaining = await ref.read(pinServiceProvider).remainingLockout();
      if (remaining == null) {
        timer.cancel();
        state = state.copyWith(clearRemaining: true, clearMessage: true);
        return;
      }
      state = state.copyWith(remaining: remaining);
    });
  }
}
