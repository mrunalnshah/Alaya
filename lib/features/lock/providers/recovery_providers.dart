/// View-model state for the forgotten-PIN and forgotten-both paths (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/features/lock/providers/lock_providers.dart';

/// Which part of the recovery flow is showing.
enum RecoveryStage {
  /// Entering the recovery code.
  code,

  /// Choosing a new PIN.
  newPin,

  /// Entering the new PIN again.
  confirmPin,

  /// The last resort: erase and start over.
  forgotBoth,

  /// The PIN has been reset.
  done,
}

/// What the recovery flow is holding.
class RecoveryState {
  /// Creates a state.
  const RecoveryState({
    this.stage = RecoveryStage.code,
    this.code = '',
    this.length = 4,
    this.entered = '',
    this.confirmed = '',
    this.eraseTyped = '',
    this.isWorking = false,
    this.shakeTrigger = 0,
    this.mismatch = false,
    this.exported = false,
    this.failureMessage,
  });

  /// The stage being shown.
  final RecoveryStage stage;

  /// The recovery code as typed, hyphen and case included.
  ///
  /// Passed through unnormalised: `PinService.resetWithRecoveryCode` normalises and validates, and a second
  /// normaliser here could disagree with the one that actually checks.
  final String code;

  /// How many digits the new PIN will have.
  final int length;

  /// The first entry of the new PIN.
  final String entered;

  /// The second entry.
  final String confirmed;

  /// What the user has typed into the erase confirmation.
  final String eraseTyped;

  /// Whether a check, export or erase is in flight.
  final bool isWorking;

  /// Incremented on a rejection, so two in a row shake twice.
  final int shakeTrigger;

  /// Whether the two new-PIN entries differed.
  final bool mismatch;

  /// Whether a backup has been taken during this flow.
  final bool exported;

  /// The service's own message from the last failure (Law U9).
  final String? failureMessage;

  /// Which entry the keypad is filling.
  String get active => stage == RecoveryStage.confirmPin ? confirmed : entered;

  /// A copy with the given fields replaced.
  RecoveryState copyWith({
    RecoveryStage? stage,
    String? code,
    int? length,
    String? entered,
    String? confirmed,
    String? eraseTyped,
    bool? isWorking,
    int? shakeTrigger,
    bool? mismatch,
    bool? exported,
    String? failureMessage,
    bool clearFailure = false,
  }) => RecoveryState(
    stage: stage ?? this.stage,
    code: code ?? this.code,
    length: length ?? this.length,
    entered: entered ?? this.entered,
    confirmed: confirmed ?? this.confirmed,
    eraseTyped: eraseTyped ?? this.eraseTyped,
    isWorking: isWorking ?? this.isWorking,
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    mismatch: mismatch ?? this.mismatch,
    exported: exported ?? this.exported,
    failureMessage: clearFailure
        ? null
        : (failureMessage ?? this.failureMessage),
  );
}

/// The recovery flow's state.
final recoveryProvider = NotifierProvider<RecoveryNotifier, RecoveryState>(
  RecoveryNotifier.new,
);

/// Drives recovery by code, and the erase behind it.
class RecoveryNotifier extends Notifier<RecoveryState> {
  @override
  RecoveryState build() => const RecoveryState();

  /// Records the typed code.
  void setCode(String code) =>
      state = state.copyWith(code: code, clearFailure: true);

  /// Moves to choosing a new PIN.
  ///
  /// **The code is not checked here.** `PinService.resetWithRecoveryCode` verifies it and the throttle
  /// together, at the point it would set the new PIN — so a wrong code costs one throttled attempt rather
  /// than an unlimited number of free guesses against a check with nothing behind it.
  void toNewPin() {
    if (state.code.trim().isEmpty) return;
    state = state.copyWith(stage: RecoveryStage.newPin, clearFailure: true);
  }

  /// Switches between a 4- and 6-digit new PIN, discarding what was typed.
  void setLength(int length) => state = state.copyWith(
    length: length,
    entered: '',
    confirmed: '',
    mismatch: false,
  );

  /// Appends a digit to whichever entry is active.
  Future<void> append(String digit) async {
    if (state.isWorking) return;
    if (state.stage == RecoveryStage.newPin) {
      final next = state.entered + digit;
      state = state.copyWith(
        entered: next,
        mismatch: false,
        clearFailure: true,
      );
      if (next.length >= state.length) {
        state = state.copyWith(stage: RecoveryStage.confirmPin);
      }
      return;
    }
    if (state.stage != RecoveryStage.confirmPin) return;
    final next = state.confirmed + digit;
    state = state.copyWith(confirmed: next, mismatch: false);
    if (next.length >= state.length) await _reset();
  }

  /// Removes the last digit, stepping back a stage when the entry empties.
  void backspace() {
    if (state.stage == RecoveryStage.confirmPin) {
      if (state.confirmed.isEmpty) {
        state = state.copyWith(stage: RecoveryStage.newPin, mismatch: false);
        return;
      }
      state = state.copyWith(
        confirmed: state.confirmed.substring(0, state.confirmed.length - 1),
        mismatch: false,
      );
      return;
    }
    if (state.entered.isEmpty) return;
    state = state.copyWith(
      entered: state.entered.substring(0, state.entered.length - 1),
    );
  }

  Future<void> _reset() async {
    if (state.confirmed != state.entered) {
      state = state.copyWith(
        stage: RecoveryStage.newPin,
        entered: '',
        confirmed: '',
        mismatch: true,
        shakeTrigger: state.shakeTrigger + 1,
      );
      return;
    }

    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await ref
        .read(pinServiceProvider)
        .resetWithRecoveryCode(
          code: state.code,
          newPin: state.entered,
        );
    if (result.isFailure) {
      // **Back to the code stage, not the PIN stage.** A rejection here is almost always a wrong recovery
      // code rather than a mistyped new PIN, and leaving somebody on the keypad to try the same code again
      // spends another throttled attempt on the same mistake.
      state = state.copyWith(
        isWorking: false,
        stage: RecoveryStage.code,
        entered: '',
        confirmed: '',
        shakeTrigger: state.shakeTrigger + 1,
        failureMessage: result.failureOrNull?.message,
      );
      return;
    }

    state = state.copyWith(isWorking: false, stage: RecoveryStage.done);
    // The new PIN satisfies this session: somebody who has just chosen one, twice, should not be asked for
    // it again on the way out.
    ref.read(lockPhaseProvider.notifier).markUnlocked();
  }

  /// Opens the last resort.
  void toForgotBoth() => state = state.copyWith(
    stage: RecoveryStage.forgotBoth,
    clearFailure: true,
  );

  /// Records what has been typed into the erase confirmation.
  void setEraseTyped(String value) => state = state.copyWith(eraseTyped: value);

  /// Exports a backup before erasing, per ARCH_3 §2.2.
  ///
  /// **Possible only because the database is plaintext and the lock is not a decryption key.** This is the
  /// path the redesign bought: nobody permanently loses their financial history to a forgotten PIN.
  Future<bool> exportFirst() async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await ref.read(dataTransferPortProvider).exportAndShare();
    state = state.copyWith(
      isWorking: false,
      exported: result.isOk,
      failureMessage: result.isOk ? null : result.failureOrNull?.message,
    );
    return result.isOk;
  }

  /// Erases everything, once the confirmation word has been typed exactly.
  Future<bool> eraseEverything() async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await ref.read(dataTransferPortProvider).eraseEverything();
    if (result.isFailure) {
      state = state.copyWith(
        isWorking: false,
        failureMessage: result.failureOrNull?.message,
      );
      return false;
    }
    state = state.copyWith(isWorking: false, stage: RecoveryStage.done);
    // The erase cleared the lock as well as the data, so re-reading leaves the app open.
    await ref.read(lockPhaseProvider.notifier).refresh();
    return true;
  }
}
