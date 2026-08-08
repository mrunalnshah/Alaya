import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/data/backup/backup_service.dart';
import 'package:alaya/data/backup/erase_service.dart';
import 'package:alaya/data/backup/restore_service.dart';
import 'package:alaya/data/daos/backup_history_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/connection/open_database.dart';
import 'package:alaya/data/platform/saf_channel.dart';
import 'package:alaya/domain/services/attachments/attachment_port.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart' as port;

/// The production [port.DataTransferPort]: `VACUUM INTO` into the cache, then the system share sheet.
///
/// **The only file in this phase that imports `path_provider` or `share_plus`,** for the same
/// containment reason as the biometric gate. `share_plus` is the sharper edge of the two: its v11
/// replaced `Share.shareXFiles` with `SharePlus.instance.share(ShareParams(...))`, and that call could
/// not be compiled against here (ARCH_4 R22). If it has moved again, this file is the only casualty.
///
/// **Share, not save-to.** ARCH_3 §3.3 gives export two shapes: a Storage Access Framework
/// *create-document* intent where the user picks a location, and a `share_plus` hand-off. This phase
/// needs only the second — its two prompts are "make a backup now?" after setting a PIN and "export
/// first" before erasing, and both want one tap to WhatsApp or Drive rather than a file browser. The SAF
/// path arrives with 8B's Backup screen, which is why `file_picker` is 8B's dependency and not this
/// phase's.
///
/// The file lands in the **cache** directory rather than documents, because it is a hand-off rather than
/// a stored artefact: the OS may reclaim it once shared, which is the correct lifetime for a copy of
/// every balance the user owns.
final class ShareBackupTransfer implements port.DataTransferPort {
  /// Creates the transfer over [backup] and [erase].
  const ShareBackupTransfer({
    required BackupService backup,
    required EraseService erase,
    required RestoreService restore,
    required BackupHistoryDao history,
    required AlayaDatabase database,
    required AttachmentPort attachments,
    SafChannel saf = const SafChannel(),
  }) : _saf = saf,
       _backup = backup,
       _erase = erase,
       _restore = restore,
       _history = history,
       _db = database,
       _attachments = attachments;

  final BackupService _backup;
  final EraseService _erase;
  final RestoreService _restore;
  final BackupHistoryDao _history;
  final AlayaDatabase _db;
  final AttachmentPort _attachments;
  final SafChannel _saf;

  /// What the rollback snapshot is called, beside the live database.
  static const String rollbackFileName = 'alaya-rollback.sqlite';

  /// Whether the installed `file_picker` can raise a Storage Access Framework **create-document** sheet.
  ///
  /// **False, because `FilePicker.saveFile` is not defined on the pinned version** — the analyzer rejected it
  /// outright. Sharing still works and still goes through a system sheet, so no storage permission is needed
  /// either way and ARCH_3 §3.3 holds; what is missing is only the *choose-a-folder* shape of the same export.
  ///
  /// The Backup screen hides that row while this is false, so there is no dead control (ARCH_5 §10). Flipping it
  /// back is this constant plus whichever call the installed version provides.
  static const bool savePickerAvailable = true;

  @override
  Future<Result<port.BackupArtefact, Failure>> exportAndShare() async {
    try {
      final directory = await getApplicationCacheDirectory();
      final name = _backup.suggestedFileName(zipped: false);
      final destination = '${directory.path}${Platform.pathSeparator}$name';

      final exported = await _backup.export(destinationPath: destination);
      final artefact = exported.valueOrNull;
      if (artefact == null) {
        return Result.failure(
          exported.failureOrNull ??
              const UnexpectedFailure('The backup could not be written.'),
        );
      }

      await SharePlus.instance.share(
        ShareParams(files: [XFile(artefact.path)]),
      );
      return Result.ok(artefact);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The backup could not be shared.', cause: error),
      );
    }
  }

  @override
  bool get canSaveToLocation => savePickerAvailable;

  @override
  Future<Result<port.BackupArtefact?, Failure>> exportToLocation() async {
    try {
      // **The Storage Access Framework, and nothing else** (ARCH_3 §3.3). `saveFile` raises the system's own
      // create-document sheet: the user picks where it goes, and the app needs no storage permission at all —
      // no `WRITE_EXTERNAL_STORAGE`, no `MANAGE_EXTERNAL_STORAGE`.
      final files = await _attachments.allFilePaths();
      final attachmentPaths = files.valueOrNull ?? const <String>[];
      final zipped = attachmentPaths.isNotEmpty;
      final suggested = _backup.suggestedFileName(zipped: zipped);

      // **`saveFile` does not exist on the installed `file_picker`**, so save-to-a-location is off rather than
      // guessed at. Two wrong guesses at `local_auth` in 8A taught the lesson: an API that is not there is not
      // guessed a third time. `getDirectoryPath` might work, or might not — and shipping a Backup screen whose
      // primary action throws is worse than one that offers only Share until the version is known.
      //
      // Reversing this is one constant and the call the installed version actually provides.
      // **Export to a temp path first, then hand it to the create-document sheet.** `BackupService` writes with
      // `VACUUM INTO`, which needs a filesystem path; the user's chosen destination is a `content://` URI that
      // only the channel can write to. One round trip does both.
      final cache = await getApplicationCacheDirectory();
      final staged = '${cache.path}${Platform.pathSeparator}$suggested';
      final exported = await _backup.export(
        destinationPath: staged,
        attachments: [for (final path in attachmentPaths) File(path)],
      );
      final artefact = exported.valueOrNull;
      if (artefact == null) {
        return Result.failure(
          exported.failureOrNull ??
              const UnexpectedFailure('The backup could not be written.'),
        );
      }
      final saved = await _saf.createDocument(
        sourcePath: artefact.path,
        fileName: suggested,
        mimeType: 'application/octet-stream',
      );
      if (saved.isFailure) return Result.failure(saved.failureOrNull!);
      // Dismissing the sheet is not a failure — it is the commonest thing to do with a file chooser.
      if (saved.valueOrNull == null) return const Result.ok(null);
      return Result.ok(artefact);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The backup could not be saved.', cause: error),
      );
    }
  }

  @override
  Stream<List<port.BackupRecord>> watchHistory() => _history.watchRecent().map(
    (rows) => [
      for (final row in rows)
        port.BackupRecord(
          id: row.id,
          filePath: row.filePath,
          sizeBytes: row.sizeBytes,
          schemaVersion: row.schemaVersion,
          takenAtUtcMillis: row.createdAt,
          note: row.note,
        ),
    ],
  );

  @override
  Future<Result<void, Failure>> forgetHistoryEntry(String id) async {
    try {
      // **Soft-deletes the row and leaves the file alone**, because the file is wherever the user put it — a
      // Drive folder, a WhatsApp thread — and this app has no business reaching in there. Forgetting the entry
      // is all it can honestly offer.
      await _history.softDelete(
        id: id,
        nowUtcMillis: DateTime.now().toUtc().millisecondsSinceEpoch,
      );
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That entry could not be removed.', cause: error),
      );
    }
  }

  @override
  Future<Result<String?, Failure>> pickBackupFile() =>
      _saf.openDocument(mimeTypes: const ['*/*']);

  @override
  Future<Result<int, Failure>> readBackupVersion(String path) =>
      _restore.readBackupSchemaVersion(path);

  @override
  int get appSchemaVersion => _db.schemaVersion;

  @override
  Future<Result<port.RestoreOutcome, Failure>> merge(String path) async {
    final result = await _restore.merge(path);
    return _toOutcome(result, port.RestoreMode.merge);
  }

  @override
  Future<Result<port.RestoreOutcome, Failure>> replace(String path) async {
    try {
      final live = await alayaDatabaseFile();
      final rollback = File(
        '${live.parent.path}${Platform.pathSeparator}$rollbackFileName',
      );
      final result = await _restore.replaceFiles(
        backupPath: path,
        livePath: live.path,
        rollbackPath: rollback.path,
      );
      return _toOutcome(result, port.RestoreMode.replace);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The backup could not be applied.', cause: error),
      );
    }
  }

  @override
  Future<Result<void, Failure>> rollback() async {
    try {
      final live = await alayaDatabaseFile();
      return _restore.restoreRollback(
        rollbackPath:
            '${live.parent.path}${Platform.pathSeparator}$rollbackFileName',
        livePath: live.path,
      );
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure(
          'The previous data could not be put back.',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<bool> hasRollback() async {
    try {
      final live = await alayaDatabaseFile();
      return File(
        '${live.parent.path}${Platform.pathSeparator}$rollbackFileName',
      ).existsSync();
    } on Object {
      return false;
    }
  }

  /// Turns `RestoreService`'s report into the domain outcome.
  ///
  /// The two are nearly the same record, and deliberately not the same type: `RestoreReport` carries a
  /// `rollbackPath`, which is a filesystem detail no screen should see. The domain outcome carries only whether
  /// a rollback is *available*, which is the question the UI actually asks.
  Result<port.RestoreOutcome, Failure> _toOutcome(
    Result<RestoreReport, Failure> result,
    port.RestoreMode mode,
  ) {
    final report = result.valueOrNull;
    if (report == null) {
      return Result.failure(
        result.failureOrNull ??
            const UnexpectedFailure('The backup could not be applied.'),
      );
    }
    return Result.ok((
      mode: mode,
      tablesMerged: report.tablesMerged,
      backupSchemaVersion: report.backupSchemaVersion,
      rollbackAvailable: report.rollbackPath != null,
    ));
  }

  @override
  Future<Result<void, Failure>> eraseEverything() => _erase.eraseEverything();
}
