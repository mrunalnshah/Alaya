import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';

import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/backup_history_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// What an export produced.
typedef BackupArtefact = ({
  String path,
  int sizeBytes,
  bool isZipped,
  String fileName,
});

/// Exports the database with `VACUUM INTO` (ARCH_3 §3.1).
///
/// **One statement does the whole job.** `VACUUM INTO` produces a consistent, compacted, standalone
/// SQLite file while the app is running — no manual file copy, no WAL race, no serialisation layer.
/// With a plaintext database there is nothing further to do: no key to wrap, no header to write.
///
/// The export is **not encrypted**, and the UI must say so on every export sheet (ARCH_3 §3.4). That
/// is a consistent threat model rather than a contradiction, because the database itself is plaintext
/// too.
final class BackupService {
  /// Creates the service.
  const BackupService({
    required AlayaDatabase database,
    required BackupHistoryDao historyDao,
    required Clock clock,
    required UidGenerator uids,
    this.appVersion = 'unknown',
  }) : _database = database,
       _historyDao = historyDao,
       _clock = clock,
       _uids = uids;

  final AlayaDatabase _database;
  final BackupHistoryDao _historyDao;
  final Clock _clock;
  final UidGenerator _uids;

  /// The app version recorded against each backup, so a support question about an old file can be
  /// answered without guessing which build wrote it.
  final String appVersion;

  /// The name inside a zipped backup.
  static const String zipEntryName = 'data.db';

  /// The directory inside a zipped backup holding attachments.
  static const String zipAttachmentDir = 'attachments';

  /// Exports to [destinationPath], zipping only when [attachments] is non-empty.
  ///
  /// A bare `.db` when there is nothing to bundle is deliberate: fewer moving parts, and a file the
  /// user can open in any SQLite browser without unzipping first. The zip exists only because
  /// attachments cannot travel inside the database file.
  Future<Result<BackupArtefact, Failure>> export({
    required String destinationPath,
    List<File> attachments = const [],
  }) async {
    try {
      final fileName = suggestedFileName(zipped: attachments.isNotEmpty);

      if (attachments.isEmpty) {
        await _vacuumInto(destinationPath);
        final size = await File(destinationPath).length();
        await _log(
          fileName: fileName,
          path: destinationPath,
          sizeBytes: size,
          zipped: false,
        );
        return Result.ok(
          (
            path: destinationPath,
            sizeBytes: size,
            isZipped: false,
            fileName: fileName,
          ),
        );
      }

      // VACUUM INTO cannot write into an archive, so the .db is produced beside the destination and
      // removed once bundled. A temporary path derived from the destination keeps both on the same
      // filesystem, so no cross-device copy is involved.
      final stagedPath = '$destinationPath.staging.db';
      await _vacuumInto(stagedPath);

      final archive = Archive()
        ..addFile(
          ArchiveFile(
            zipEntryName,
            await File(stagedPath).length(),
            await File(stagedPath).readAsBytes(),
          ),
        );
      for (final attachment in attachments) {
        if (!attachment.existsSync()) continue;
        final bytes = await attachment.readAsBytes();
        final name = attachment.uri.pathSegments.last;
        archive.addFile(
          ArchiveFile('$zipAttachmentDir/$name', bytes.length, bytes),
        );
      }

      final encoded = ZipEncoder().encode(archive);
      await File(destinationPath).writeAsBytes(encoded);
      await File(stagedPath).delete();

      final size = await File(destinationPath).length();
      await _log(
        fileName: fileName,
        path: destinationPath,
        sizeBytes: size,
        zipped: true,
      );
      return Result.ok(
        (
          path: destinationPath,
          sizeBytes: size,
          isZipped: true,
          fileName: fileName,
        ),
      );
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The backup could not be written.', cause: error),
      );
    }
  }

  /// The filename ARCH_3 §3.1 specifies: `alaya-backup-<yyyyMMdd-HHmm>.db` or `.zip`.
  String suggestedFileName({required bool zipped}) {
    final now = _clock.now();
    final stamp =
        '${now.year}${_two(now.month)}${_two(now.day)}'
        '-${_two(now.hour)}${_two(now.minute)}';
    return 'alaya-backup-$stamp.${zipped ? "zip" : "db"}';
  }

  /// The schema version that travels **inside** the file, via drift's `user_version`.
  ///
  /// There is no manifest to keep in sync, because SQLite already carries this in its header — which
  /// is what lets `RestoreService` gate an incoming file without trusting anything alongside it.
  int get schemaVersion => _database.schemaVersion;

  Future<void> _vacuumInto(String path) async {
    // Interpolated rather than bound: SQLite does not accept a parameter in VACUUM INTO's target.
    // The path is not user-typed — it comes from the Storage Access Framework — and the quote
    // doubling below closes the injection question rather than leaving it to that assumption.
    final escaped = path.replaceAll("'", "''");
    await _database.customStatement("VACUUM INTO '$escaped'");
  }

  Future<void> _log({
    required String fileName,
    required String path,
    required int sizeBytes,
    required bool zipped,
  }) async {
    final now = _clock.nowUtcMillis();
    await _historyDao.insertEntry(
      BackupHistoryCompanion.insert(
        id: _uids.generate(),
        filePath: path,
        sizeBytes: sizeBytes,
        schemaVersion: _database.schemaVersion,
        appVersion: appVersion,
        kind: BackupKind.manual,
        // `backup_history` has no `isZipped` column, so the fact is recorded in the note rather than
        // inferred from the extension later — a `.db` and a `.zip` are restored by different paths,
        // and guessing from a filename the user may have renamed would be fragile.
        note: Value(
          zipped ? 'zip (attachments bundled): $fileName' : 'db: $fileName',
        ),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  String _two(int n) => n < 10 ? '0$n' : '$n';
}
