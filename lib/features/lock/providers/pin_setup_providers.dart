/// View-model state for setting or changing the PIN (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/features/lock/providers/lock_providers.dart';

/// Which part of the setup flow is showing.
enum PinSetupStage {
  /// Choosing and entering a PIN.
  enter,

  /// Entering it a second time.
  confirm,

  /// The recovery code, shown once.
  recovery,

  /// The offer to make a backup, per ARCH_3 §2.2.
  backup,

  /// Finished.
  done,
}

/// What the setup flow is holding.
class PinSetupState {
  /// Creates a state.
  const PinSetupState({
    this.stage = PinSetupStage.enter,
    this.length = 4,
    this.entered = '',
    this.confirmed = '',
    this.recoveryCode,
    this.acknowledged = false,
    this.isSaving = false,
    this.shakeTrigger = 0,
    this.mismatch = false,
    this.failureMessage,
  });

  /// The part being shown.
  final PinSetupStage stage;

  /// Four digits, or six if the user chose it (ARCH_3 §2.1).
  final int length;

  /// The first entry.
  final String entered;

  /// The second entry.
  final String confirmed;

  /// The code to show exactly once, formatted `ABCDE-FGHJK`.
  ///
  /// Held in memory only, and never written anywhere this app can read back — `PinService` stores its
  /// hash and nothing else. A code the app could redisplay would be one an attacker could read off a
  /// screen instead of guessing.
  final String? recoveryCode;

  /// Whether the one confirmation box is ticked.
  final bool acknowledged;

  /// Whether a write is in flight.
  final bool isSaving;

  /// Incremented on a mismatch, so two in a row shake twice.
  final int shakeTrigger;

  /// Whether the second entry differed from the first.
  final bool mismatch;

  /// The service's own message from a failed enable (Law U9).
  final String? failureMessage;

  /// Which entry the keypad is filling.
  String get active => stage == PinSetupStage.confirm ? confirmed : entered;

  /// A copy with the given fields replaced.
  PinSetupState copyWith({
    PinSetupStage? stage,
    int? length,
    String? entered,
    String? confirmed,
    String? recoveryCode,
    bool? acknowledged,
    bool? isSaving,
    int? shakeTrigger,
    bool? mismatch,
    String? failureMessage,
    bool clearFailure = false,
  }) => PinSetupState(
    stage: stage ?? this.stage,
    length: length ?? this.length,
    entered: entered ?? this.entered,
    confirmed: confirmed ?? this.confirmed,
    recoveryCode: recoveryCode ?? this.recoveryCode,
    acknowledged: acknowledged ?? this.acknowledged,
    isSaving: isSaving ?? this.isSaving,
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    mismatch: mismatch ?? this.mismatch,
    failureMessage: clearFailure
        ? null
        : (failureMessage ?? this.failureMessage),
  );
}

/// The PIN setup flow's state.
final pinSetupProvider = NotifierProvider<PinSetupNotifier, PinSetupState>(
  PinSetupNotifier.new,
);

/// Drives the four stages ARCH_3 §2.2 specifies for enabling a lock.
class PinSetupNotifier extends Notifier<PinSetupState> {
  @override
  PinSetupState build() => const PinSetupState();

  /// Switches between a 4- and 6-digit PIN, discarding whatever was typed.
  ///
  /// Discarding is deliberate: keeping three digits of a four-digit attempt when the user asks for six
  /// leaves a half-filled field that looks like progress toward something it is not.
  void setLength(int length) => state = PinSetupState(length: length);

  /// Appends a digit to whichever entry is active, advancing when it is full.
  Future<void> append(String digit) async {
    if (state.isSaving) return;
    if (state.stage == PinSetupStage.enter) {
      final next = state.entered + digit;
      state = state.copyWith(
        entered: next,
        mismatch: false,
        clearFailure: true,
      );
      if (next.length >= state.length) {
        state = state.copyWith(stage: PinSetupStage.confirm);
      }
      return;
    }
    if (state.stage != PinSetupStage.confirm) return;
    final next = state.confirmed + digit;
    state = state.copyWith(confirmed: next, mismatch: false);
    if (next.length >= state.length) await _commit();
  }

  /// Removes the last digit of the active entry, stepping back a stage when it empties.
  void backspace() {
    if (state.stage == PinSetupStage.confirm) {
      if (state.confirmed.isEmpty) {
        // Back to the first entry rather than nowhere: a user who mistyped the confirmation and holds
        // backspace should end up somewhere they can act, not at a dead field.
        state = state.copyWith(stage: PinSetupStage.enter, mismatch: false);
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

  Future<void> _commit() async {
    if (state.confirmed != state.entered) {
      // **Both entries are cleared, not just the second.** Somebody who mistyped does not know which of
      // the two was wrong, and re-confirming against a first entry they may have fat-fingered would set a
      // PIN they do not know.
      state = state.copyWith(
        stage: PinSetupStage.enter,
        entered: '',
        confirmed: '',
        mismatch: true,
        shakeTrigger: state.shakeTrigger + 1,
      );
      return;
    }

    state = state.copyWith(isSaving: true, clearFailure: true);
    final result = await ref
        .read(pinServiceProvider)
        .enable(pin: state.entered);
    final code = result.valueOrNull;
    if (code == null) {
      state = state.copyWith(
        isSaving: false,
        stage: PinSetupStage.enter,
        entered: '',
        confirmed: '',
        shakeTrigger: state.shakeTrigger + 1,
        failureMessage: result.failureOrNull?.message,
      );
      return;
    }

    // **The session is marked satisfied, and deliberately *not* refreshed.** Enabling a lock means
    // `PinService.isEnabled` now answers true, so re-reading it here would set the phase to `locked` —
    // firing the router's `refreshListenable` and ejecting the user to the lock screen from the very
    // screen where they just entered the PIN twice, which is more proof than the lock screen asks for.
    // The re-read exists for the opposite direction: a lock disabled elsewhere.
    ref.read(lockPhaseProvider.notifier).markUnlocked();

    state = state.copyWith(
      isSaving: false,
      stage: PinSetupStage.recovery,
      recoveryCode: code,
    );
  }

  /// Ticks or unticks the single confirmation box.
  void acknowledge({required bool value}) =>
      state = state.copyWith(acknowledged: value);

  /// Moves from the recovery code to the backup offer.
  void toBackupOffer() {
    if (!state.acknowledged) return;
    state = state.copyWith(stage: PinSetupStage.backup);
  }

  /// Exports a backup and offers to share it, then finishes.
  Future<bool> backupNow() async {
    state = state.copyWith(isSaving: true, clearFailure: true);
    final result = await ref.read(dataTransferPortProvider).exportAndShare();
    state = state.copyWith(
      isSaving: false,
      stage: result.isOk ? PinSetupStage.done : PinSetupStage.backup,
      failureMessage: result.isOk ? null : result.failureOrNull?.message,
    );
    return result.isOk;
  }

  /// Declines the backup and finishes.
  void skipBackup() => state = state.copyWith(stage: PinSetupStage.done);
}
