/// View-model state for the restore flow (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart';

/// Which part of the restore flow is showing.
enum RestoreStage {
  /// Choosing a file.
  pick,

  /// The file has been read and its schema version checked.
  confirm,

  /// Typing REPLACE, for the destructive mode only.
  arm,

  /// Applied.
  done,
}

/// Why a chosen backup cannot be applied.
enum RestoreRefusal {
  /// The file is newer than this build understands.
  ///
  /// **The one gate ARCH_3 §3.2 puts first**, and the only refusal that is about the file rather than the device:
  /// a backup written by a later schema may contain columns this build would silently drop.
  newerSchema,

  /// The file could not be opened as a database at all.
  notADatabase,
}

/// What the restore flow is holding.
class RestoreState {
  /// Creates a state.
  const RestoreState({
    this.stage = RestoreStage.pick,
    this.path,
    this.fileName,
    this.backupVersion,
    this.appVersion,
    this.mode = RestoreMode.merge,
    this.typed = '',
    this.isWorking = false,
    this.refusal,
    this.outcome,
    this.failureMessage,
  });

  /// The part being shown.
  final RestoreStage stage;

  /// The chosen file's path.
  final String? path;

  /// Its name, for the copy.
  final String? fileName;

  /// The schema version inside it.
  final int? backupVersion;

  /// The schema version this build writes.
  final int? appVersion;

  /// Merge or Replace.
  ///
  /// **Merge is the default and Replace is the choice**, because merge keeps rows the backup does not have while
  /// replace discards them. A destructive default is a destructive accident.
  final RestoreMode mode;

  /// What has been typed into the confirmation.
  final String typed;

  /// Whether a read or a write is in flight.
  final bool isWorking;

  /// Why the file was refused, if it was.
  final RestoreRefusal? refusal;

  /// What the restore did, once it has.
  final RestoreOutcome? outcome;

  /// The service's own message from a failure (Law U9).
  final String? failureMessage;

  /// Whether the typed confirmation matches, for Replace.
  bool get isArmed => typed.trim() == RestoreState.confirmationWord;

  /// The word Replace requires.
  ///
  /// Not localised, for the reason 8A's `ERASE` is not: a translated confirmation word means a support article
  /// cannot tell anyone what to type, and the point of the gate is that it cannot be satisfied by tapping.
  static const String confirmationWord = 'REPLACE';

  /// A copy with the given fields replaced.
  RestoreState copyWith({
    RestoreStage? stage,
    String? path,
    String? fileName,
    int? backupVersion,
    int? appVersion,
    RestoreMode? mode,
    String? typed,
    bool? isWorking,
    RestoreRefusal? refusal,
    bool clearRefusal = false,
    RestoreOutcome? outcome,
    String? failureMessage,
    bool clearFailure = false,
  }) => RestoreState(
    stage: stage ?? this.stage,
    path: path ?? this.path,
    fileName: fileName ?? this.fileName,
    backupVersion: backupVersion ?? this.backupVersion,
    appVersion: appVersion ?? this.appVersion,
    mode: mode ?? this.mode,
    typed: typed ?? this.typed,
    isWorking: isWorking ?? this.isWorking,
    refusal: clearRefusal ? null : (refusal ?? this.refusal),
    outcome: outcome ?? this.outcome,
    failureMessage: clearFailure
        ? null
        : (failureMessage ?? this.failureMessage),
  );
}

/// The restore flow's state.
final restoreProvider = NotifierProvider<RestoreNotifier, RestoreState>(
  RestoreNotifier.new,
);

/// Picks a file, gates it, and applies it.
class RestoreNotifier extends Notifier<RestoreState> {
  @override
  RestoreState build() => const RestoreState();

  /// Opens the system picker and reads the chosen file's schema version.
  Future<void> pickFile() async {
    state = state.copyWith(
      isWorking: true,
      clearFailure: true,
      clearRefusal: true,
    );
    try {
      // **Through the port, not a plugin.** A feature may not import `data/`, and the SAF channel lives there —
      // so picking a file is one more thing `DataTransferPort` answers, alongside reading its version.
      final picked = await ref.read(dataTransferPortProvider).pickBackupFile();
      if (picked.isFailure) {
        state = state.copyWith(
          isWorking: false,
          failureMessage: picked.failureOrNull?.message,
        );
        return;
      }
      final path = picked.valueOrNull;
      if (path == null) {
        state = state.copyWith(isWorking: false);
        return;
      }
      final port = ref.read(dataTransferPortProvider);
      final version = await port.readBackupVersion(path);
      final backupVersion = version.valueOrNull;
      if (backupVersion == null) {
        state = state.copyWith(
          isWorking: false,
          refusal: RestoreRefusal.notADatabase,
          failureMessage: version.failureOrNull?.message,
        );
        return;
      }
      final appVersion = port.appSchemaVersion;
      state = state.copyWith(
        isWorking: false,
        stage: RestoreStage.confirm,
        path: path,
        fileName: path.split(RegExp(r'[/\\]')).last,
        backupVersion: backupVersion,
        appVersion: appVersion,
        // **Gated before anything is applied** (ARCH_3 §3.2). A backup from a later schema may carry columns this
        // build would silently drop, so it is refused with both numbers rather than merged lossily.
        refusal: backupVersion > appVersion ? RestoreRefusal.newerSchema : null,
      );
    } on Object catch (error) {
      state = state.copyWith(
        isWorking: false,
        failureMessage: error.toString(),
      );
    }
  }

  /// Chooses Merge or Replace.
  void setMode(RestoreMode mode) =>
      state = state.copyWith(mode: mode, typed: '', clearFailure: true);

  /// Records what has been typed into the Replace confirmation.
  void setTyped(String value) => state = state.copyWith(typed: value);

  /// Moves to the typed confirmation, for Replace only.
  void arm() {
    if (state.mode != RestoreMode.replace) return;
    state = state.copyWith(stage: RestoreStage.arm, typed: '');
  }

  /// Applies the backup.
  Future<bool> apply() async {
    final path = state.path;
    if (path == null || state.refusal != null) return false;
    if (state.mode == RestoreMode.replace && !state.isArmed) return false;

    state = state.copyWith(isWorking: true, clearFailure: true);
    final port = ref.read(dataTransferPortProvider);
    final result = state.mode == RestoreMode.merge
        ? await port.merge(path)
        : await port.replace(path);
    final outcome = result.valueOrNull;
    if (outcome == null) {
      state = state.copyWith(
        isWorking: false,
        failureMessage: result.failureOrNull?.message,
      );
      return false;
    }
    state = state.copyWith(
      isWorking: false,
      stage: RestoreStage.done,
      outcome: outcome,
    );
    return true;
  }

  /// Puts the pre-replace snapshot back.
  Future<bool> rollback() async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await ref.read(dataTransferPortProvider).rollback();
    state = state.copyWith(
      isWorking: false,
      failureMessage: result.isFailure ? result.failureOrNull?.message : null,
    );
    return result.isOk;
  }
}
