/// View-model state for the backup and restore screens (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart';

/// Every backup this app has taken, newest first.
final backupHistoryProvider = StreamProvider<List<BackupRecord>>(
  (ref) => ref.watch(dataTransferPortProvider).watchHistory(),
);

/// Whether a rollback snapshot is sitting beside the live database.
final hasRollbackProvider = FutureProvider<bool>(
  (ref) => ref.watch(dataTransferPortProvider).hasRollback(),
);

/// Exporting, and forgetting history entries.
final backupControllerProvider =
    NotifierProvider<BackupController, AsyncValue<void>>(BackupController.new);

/// Runs the export and reports what came back.
class BackupController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// The last export's artefact, so the screen can name the file it just wrote.
  BackupArtefact? get lastArtefact => _lastArtefact;
  BackupArtefact? _lastArtefact;

  /// Whether the last attempt ended because the user dismissed the system sheet.
  ///
  /// **Distinct from both success and failure**, because it is neither: cancelling a file chooser is the
  /// commonest thing to do with one, and a screen that cannot tell it apart either congratulates somebody on a
  /// backup they did not take or shows them an error for changing their mind.
  bool get wasCancelled => _wasCancelled;
  bool _wasCancelled = false;

  /// Writes a backup to a location the user picks.
  Future<bool> exportToLocation() async {
    state = const AsyncLoading<void>();
    _wasCancelled = false;
    final result = await ref.read(dataTransferPortProvider).exportToLocation();
    if (result.isFailure) {
      state = AsyncError<void>(
        result.failureOrNull ?? StateError('export failed'),
        StackTrace.current,
      );
      return false;
    }
    _lastArtefact = result.valueOrNull;
    _wasCancelled = _lastArtefact == null;
    state = const AsyncData<void>(null);
    return !_wasCancelled;
  }

  /// Writes a backup and hands it to the system share sheet.
  Future<bool> exportAndShare() async {
    state = const AsyncLoading<void>();
    _wasCancelled = false;
    final result = await ref.read(dataTransferPortProvider).exportAndShare();
    if (result.isFailure) {
      state = AsyncError<void>(
        result.failureOrNull ?? StateError('export failed'),
        StackTrace.current,
      );
      return false;
    }
    _lastArtefact = result.valueOrNull;
    state = const AsyncData<void>(null);
    return true;
  }

  /// Removes a history row, leaving its file where it is.
  Future<bool> forget(String id) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(dataTransferPortProvider)
        .forgetHistoryEntry(id);
    if (result.isFailure) {
      state = AsyncError<void>(
        result.failureOrNull ?? StateError('forget failed'),
        StackTrace.current,
      );
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}
