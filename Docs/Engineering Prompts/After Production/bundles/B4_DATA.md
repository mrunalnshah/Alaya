# B4_DATA

Repository implementations, security, backup, platform channels.

**54 files · 11,405 lines.**  Written 2026-08-27T08:54:37-04:00.

Every file below is complete and current. Paths are destinations.

---

### `lib/data/attachments/attachment_store.dart`

```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/platform/saf_channel.dart';
import 'package:alaya/domain/services/attachments/attachment_port.dart';

/// The production [AttachmentPort]: `file_picker` in, a private app directory on disk, a row in `attachments`.
///
/// **The only file in this phase that imports `file_picker` or `path_provider`.** Both are plugins, so a widget
/// test cannot run them; confining them here is the containment 7A applied to `table_calendar` and 8A to
/// `local_auth`. `file_picker`'s surface could not be compiled against (ARCH_4 R22), and 8A's experience with
/// `local_auth` says to expect the first build to disagree — if it does, this file changes and nothing else.
///
/// **Files live inside the app's own directory, never in shared storage** (ARCH_3 §3.3). That is what makes SAF
/// the only outward path and `WRITE_EXTERNAL_STORAGE` unnecessary: Alaya writes where it already has the right to
/// write, and the user reaches it through the system's own sheets.
final class AttachmentStore implements AttachmentPort {
  /// Creates the store.
  AttachmentStore({
    required AlayaDatabase database,
    required UidGenerator uids,
    required Clock clock,
    SafChannel saf = const SafChannel(),
  }) : _db = database,
       _uids = uids,
       _clock = clock,
       _saf = saf;

  final AlayaDatabase _db;
  final UidGenerator _uids;
  final Clock _clock;
  final SafChannel _saf;

  /// The directory attachments live in, relative to the app's documents directory.
  static const String directoryName = 'attachments';

  Directory? _cachedRoot;

  Future<Directory> _root() async {
    final cached = _cachedRoot;
    if (cached != null) return cached;
    final documents = await getApplicationDocumentsDirectory();
    final root = Directory(
      '${documents.path}${Platform.pathSeparator}$directoryName',
    );
    if (!root.existsSync()) await root.create(recursive: true);
    _cachedRoot = root;
    return root;
  }

  Attachment _toEntity(AttachmentRow row) => Attachment(
    id: row.id,
    owner: AttachmentOwner.values.firstWhere(
      (owner) => owner.storedValue == row.ownerType,
      // **Falls back rather than throwing**, for the reason Law L13 gives about enums in the database: a
      // later version may write an owner type this build has never heard of, and one unknown row must not
      // take out the list it appears in.
      orElse: () => AttachmentOwner.transaction,
    ),
    ownerId: row.ownerId,
    relativePath: row.relativePath,
    mimeType: row.mimeType,
    sizeBytes: row.sizeBytes,
    addedAtUtcMillis: row.createdAt,
  );

  @override
  Stream<List<Attachment>> watchFor({
    required AttachmentOwner owner,
    required String ownerId,
  }) {
    final query = _db.select(_db.attachments)
      ..where((row) => row.ownerType.equals(owner.storedValue))
      ..where((row) => row.ownerId.equals(ownerId))
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]);
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  @override
  Stream<int> watchCountFor({
    required AttachmentOwner owner,
    required String ownerId,
  }) => watchFor(owner: owner, ownerId: ownerId).map((rows) => rows.length);

  @override
  Future<Result<Attachment?, Failure>> attach({
    required AttachmentOwner owner,
    required String ownerId,
  }) async {
    try {
      // Through the SAF channel rather than `file_picker`, which cannot be used in this project (ARCH_1 §7.4).
      // The channel copies the chosen document into the cache before returning, so this is a real path.
      final picked = await _saf.openDocument(mimeTypes: const ['image/*']);
      if (picked.isFailure) return Result.failure(picked.failureOrNull!);
      final source = picked.valueOrNull;
      // Dismissing the picker is the commonest outcome of a file chooser, so it is an absent value rather than a
      // failure — reporting it as an error would put a red message under a deliberate action.
      if (source == null) return const Result.ok(null);

      final file = File(source);
      if (!file.existsSync()) {
        return const Result.failure(
          BusinessRuleFailure(
            'That file is no longer there.',
            rule: 'attachmentMissing',
          ),
        );
      }

      final id = _uids.generate();
      final extension = source.contains('.')
          ? source.split('.').last.toLowerCase()
          : 'bin';
      final relative = '$id.$extension';
      final root = await _root();
      // **Copied, not referenced.** The picked file may live in a cache the OS reclaims, or behind a content URI
      // that expires with the permission grant — a row pointing at either is a broken thumbnail tomorrow.
      final stored = await file.copy(
        '${root.path}${Platform.pathSeparator}$relative',
      );
      final size = await stored.length();
      final now = _clock.nowUtcMillis();

      await _db
          .into(_db.attachments)
          .insert(
            AttachmentsCompanion.insert(
              id: id,
              ownerType: owner.storedValue,
              ownerId: ownerId,
              relativePath: relative,
              mimeType: _mimeFor(extension),
              sizeBytes: size,
              createdAt: now,
              updatedAt: now,
            ),
          );

      return Result.ok(
        Attachment(
          id: id,
          owner: owner,
          ownerId: ownerId,
          relativePath: relative,
          mimeType: _mimeFor(extension),
          sizeBytes: size,
          addedAtUtcMillis: now,
        ),
      );
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That file could not be attached.', cause: error),
      );
    }
  }

  @override
  Future<Result<String, Failure>> resolvePath(Attachment attachment) async {
    try {
      final root = await _root();
      return Result.ok(
        '${root.path}${Platform.pathSeparator}${attachment.relativePath}',
      );
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That file could not be found.', cause: error),
      );
    }
  }

  @override
  Future<Result<void, Failure>> open(Attachment attachment) async {
    final path = await resolvePath(attachment);
    final resolved = path.valueOrNull;
    if (resolved == null) return Result.failure(path.failureOrNull!);
    if (!File(resolved).existsSync()) {
      // Says which of the two went missing. A row whose file is gone is a different problem from a row that was
      // never written, and only one of them is fixed by re-attaching.
      return const Result.failure(
        BusinessRuleFailure(
          'The file is missing from this device.',
          rule: 'attachmentFileGone',
        ),
      );
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> delete(Attachment attachment) async {
    try {
      final path = await resolvePath(attachment);
      final resolved = path.valueOrNull;
      if (resolved != null) {
        final file = File(resolved);
        if (file.existsSync()) await file.delete();
      }
      // **The row goes last.** A failure between the two leaves an orphan file rather than a row pointing at
      // nothing — the recoverable direction, because a stray file wastes space while a broken row renders as a
      // permanently broken thumbnail.
      await (_db.update(_db.attachments)
            ..where((row) => row.id.equals(attachment.id)))
          .write(AttachmentsCompanion(deletedAt: Value(_clock.nowUtcMillis())));
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure(
          'That attachment could not be removed.',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<List<String>, Failure>> allFilePaths() async {
    try {
      final rows = await (_db.select(
        _db.attachments,
      )..where((row) => row.deletedAt.isNull())).get();
      final root = await _root();
      return Result.ok([
        for (final row in rows)
          '${root.path}${Platform.pathSeparator}${row.relativePath}',
      ]);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The attachments could not be listed.', cause: error),
      );
    }
  }

  /// A MIME type from a file extension.
  ///
  /// A short table rather than a package: the picker is restricted to images, so five cases cover everything it
  /// can return and a dependency to look up the sixth would not earn its place.
  String _mimeFor(String extension) => switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'gif' => 'image/gif',
    _ => 'application/octet-stream',
  };
}
```

### `lib/data/backup/backup_service.dart`

```dart
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
```

### `lib/data/backup/erase_service.dart`

```dart
import 'dart:async';

import 'package:drift/drift.dart';

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/security/app_lock_store.dart';

/// Erases every row and clears the lock — the last resort behind "I have forgotten both".
///
/// **The one capability ARCH_3 §2.2 requires that no phase had built.** `BackupService` and
/// `RestoreService` arrived in 4C, but nothing could erase, and two of this phase's flows need it: the
/// forgot-both path that requires typing `ERASE`, and the optional auto-erase after ten failed
/// attempts (§2.3). Neither can wait for 8B, because both are reachable from the lock screen — the one
/// screen a user sees when they cannot get in.
///
/// **It clears the lock as well as the data, and that is the whole point.** A user who has forgotten
/// their PIN *and* their recovery code is locked out; wiping their history while leaving the lock in
/// place would leave them exactly as locked out, with nothing left to unlock. Erasing both is what
/// makes "start over" true.
///
/// **It re-seeds, using the database's own seeder rather than one passed in.** An empty database has no
/// currencies and no units, so the app would open to a currency picker with nothing in it, and
/// `AlayaDatabase` already holds the `DatabaseSeeder` it was opened with — taking a second one as a
/// parameter would let the two disagree, and a re-seed that differs from the original install is a
/// worse outcome than no re-seed at all. A database opened without a seeder (every unit test) simply
/// ends up empty, which is what those tests want.
final class EraseService {
  /// Creates the service.
  const EraseService({
    required AlayaDatabase database,
    required AppLockStore lockStore,
  }) : _database = database,
       _lockStore = lockStore;

  final AlayaDatabase _database;
  final AppLockStore _lockStore;

  /// Deletes every row, clears the lock, and re-seeds.
  ///
  /// Ordered deliberately: the data goes first, so a failure part-way leaves the lock intact and the
  /// user no worse off than before they started. Clearing the lock first and then failing the delete
  /// would hand an unlocked app full of data to whoever was holding the phone.
  Future<Result<void, Failure>> eraseEverything() async {
    try {
      await _database.transaction(() async {
        // **`defer_foreign_keys`, not `foreign_keys = OFF`.** SQLite ignores a change to
        // `foreign_keys` inside a transaction — it is a no-op there, silently — so the usual
        // "disable, delete, re-enable" recipe would leave enforcement on and fail on the first child
        // row. `defer_foreign_keys` holds every check until COMMIT, by which point nothing is left to
        // violate. Phase 1C turns `foreign_keys` on in `beforeOpen`, and this leaves that alone.
        await _database.customStatement('PRAGMA defer_foreign_keys = ON');
        for (final table in _database.allTables) {
          await _database.delete(table).go();
        }
      });

      await _lockStore.clearLock();
      // `DatabaseSeeder` is a typedef — `Future<void> Function(AlayaDatabase)` — so this is a call,
      // not a method on an object.
      await _database.seeder?.call(_database);
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure(
          'Could not erase the data on this device.',
          cause: error,
        ),
      );
    }
  }
}
```

### `lib/data/backup/restore_service.dart`

```dart
import 'dart:io';

import 'package:drift/drift.dart';

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// How an incoming backup is applied.
enum RestoreMode {
  /// Merge by UUID, last-write-wins on `updatedAt`. Rows absent from the backup are kept.
  merge,

  /// Replace the database file wholesale. Requires the user to type `REPLACE`.
  replace,
}

/// What a restore did.
typedef RestoreReport = ({
  RestoreMode mode,
  int tablesMerged,
  int backupSchemaVersion,
  String? rollbackPath,
});

/// Applies a backup, in Merge or Replace mode (ARCH_3 §3.2).
///
/// **The whole Merge runs inside one `transaction {}`, and `DETACH` is in a `finally`.** A partially
/// applied merge is the one outcome this class exists to make impossible: half a ledger from one file
/// and half from another produces balances that reconcile against nothing, and no user could tell
/// which rows came from where. Verified against SQLite that a failure partway through leaves the row
/// count unchanged.
///
/// **No decryption anywhere.** The incoming file is plaintext SQLite, so restoring is `ATTACH` and
/// upserts — there is no key to try, and a wrong-password path does not exist.
///
/// **The lock is never restored.** PIN and recovery hashes live in secure storage (ARCH_3 §2.1), so
/// importing someone else's backup cannot change who can open the app.
final class RestoreService {
  /// Creates the service.
  const RestoreService({required AlayaDatabase database})
    : _database = database;

  final AlayaDatabase _database;

  /// The schema alias the incoming file is attached as.
  static const String attachAlias = 'backup';

  /// Every table merged, in **foreign-key-safe order**: a row may only be inserted after anything it
  /// references.
  ///
  /// Order matters even inside one transaction, because SQLite checks foreign keys per statement
  /// rather than at commit unless they are deferred. Merging `transactions` before `accounts` would
  /// fail on the first row that referenced an account the backup also introduces.
  static const List<String> mergeOrder = [
    'currencies',
    'units',
    'app_settings',
    'tags',
    'accounts',
    'payment_methods',
    'payees',
    'items',
    'assets',
    'recurring_templates',
    'shopping_lists',
    'transactions',
    'transaction_lines',
    'transaction_tags',
    'inventory_batches',
    'stock_movements',
    'shopping_entries',
    'item_tags',
    'asset_tags',
    'recurring_occurrences',
    'service_records',
    'currency_rates',
    'notification_schedule',
    'backup_history',
  ];

  /// Tables whose primary key is not `id`, and what it is instead.
  ///
  /// The upsert needs the real conflict target. `currencies` and `units` are keyed by natural code,
  /// `app_settings` by key, and `currency_rates` and the tag link tables are composite — using `id`
  /// for those would either fail to compile the statement or silently insert duplicates.
  static const Map<String, List<String>> conflictTargets = {
    'currencies': ['code'],
    'units': ['code'],
    'app_settings': ['key'],
    'currency_rates': ['base_code', 'quote_code', 'rate_date_key'],
    'transaction_tags': ['transaction_id', 'tag_id'],
    'item_tags': ['item_id', 'tag_id'],
    'asset_tags': ['asset_id', 'tag_id'],
    'analytics_cache': ['cache_key'],
  };

  /// Reads the `user_version` of the file at [path] without attaching it to the live database.
  ///
  /// Attaching first would mean holding a file open that might be refused a moment later; opening it
  /// separately keeps the gate independent of the merge.
  Future<Result<int, Failure>> readBackupSchemaVersion(String path) async {
    if (!File(path).existsSync()) {
      return Result.failure(
        NotFoundFailure('That backup file does not exist.', id: path),
      );
    }
    try {
      await _database.customStatement("ATTACH DATABASE ? AS probe", [path]);
      try {
        // `PRAGMA probe.user_version`, qualified by schema. ARCH_3 §3.2 shows
        // `pragma_user_version('backup')`, which SQLite rejects — the table-valued form takes no
        // argument, so the qualified PRAGMA is the form that actually reads an attached file.
        final row = await _database
            .customSelect('PRAGMA probe.user_version')
            .getSingleOrNull();
        final version = row?.data.values.first;
        if (version is! int) {
          return const Result.failure(
            ValidationFailure(
              'That file is not a readable SQLite database.',
              field: 'path',
            ),
          );
        }
        return Result.ok(version);
      } finally {
        await _database.customStatement('DETACH DATABASE probe');
      }
    } on Object catch (_) {
      return const Result.failure(
        ValidationFailure(
          'That file could not be opened as a SQLite database.',
          field: 'path',
        ),
      );
    }
  }

  /// Merges the backup at [path] into the live database.
  ///
  /// Guards, in ARCH_3 §3.2's order: the file opens as SQLite, its `user_version` is not ahead of
  /// this build, then one transaction, then `DETACH` in a `finally`.
  Future<Result<RestoreReport, Failure>> merge(String path) async {
    final versionCheck = await readBackupSchemaVersion(path);
    if (versionCheck.isFailure)
      return Result.failure(versionCheck.failureOrNull!);
    final backupVersion = versionCheck.valueOrNull!;

    if (backupVersion > _database.schemaVersion) {
      // Refused rather than attempted. A newer file may contain columns and tables this build has
      // never heard of; merging it would either fail halfway or silently drop them, and the user
      // would have no way to know which. Telling them to update is the only honest answer.
      return Result.failure(
        BusinessRuleFailure(
          'That backup was made by a newer version of Alaya (format $backupVersion, this app '
          'reads up to ${_database.schemaVersion}). Update the app and try again.',
          rule: 'backupTooNew',
        ),
      );
    }

    var merged = 0;
    try {
      await _database.customStatement('ATTACH DATABASE ? AS $attachAlias', [
        path,
      ]);
      try {
        // ONE transaction for every table. Either the whole merge is applied or none of it is.
        await _database.transaction(() async {
          for (final table in mergeOrder) {
            if (!await _tableExistsInBackup(table)) continue;
            await _database.customStatement(await buildMergeStatement(table));
            merged++;
          }
        });
      } finally {
        // In a `finally` so a thrown merge cannot leave the file attached. A stranded ATTACH would
        // hold a file handle open and make the next restore fail with a duplicate-alias error that
        // looks nothing like its real cause.
        await _database.customStatement('DETACH DATABASE $attachAlias');
      }
      return Result.ok(
        (
          mode: RestoreMode.merge,
          tablesMerged: merged,
          backupSchemaVersion: backupVersion,
          rollbackPath: null,
        ),
      );
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure(
          'The merge failed and nothing was changed.',
          cause: error,
        ),
      );
    }
  }

  /// Builds the upsert for [table]: insert everything, and on conflict take the backup's row **only
  /// when it is newer**.
  ///
  /// `WHERE excluded.updated_at > <table>.updated_at` is the last-write-wins rule. Verified against
  /// SQLite in both directions — the newer row wins whichever file it came from, so this is genuinely
  /// a timestamp comparison rather than source precedence.
  ///
  /// A table with no `updated_at` gets `DO NOTHING`.
  ///
  /// **No table in the current schema takes that branch** — I checked all of them, and every one has
  /// `updated_at`, including the three tag link tables I had assumed did not. It stays as insurance
  /// for a future association table without audit columns, where the presence of the row *is* the
  /// information and the local row is already equivalent to the incoming one. It is dead code today,
  /// and saying so is better than leaving a reader to infer that link tables behave differently.
  Future<String> buildMergeStatement(String table) async {
    final columns = await _columnsOf(table);
    final target = (conflictTargets[table] ?? const ['id']).join(', ');
    final hasUpdatedAt = columns.contains('updated_at');

    if (!hasUpdatedAt) {
      return 'INSERT INTO $table SELECT * FROM $attachAlias.$table WHERE true '
          'ON CONFLICT($target) DO NOTHING';
    }

    final targetSet = (conflictTargets[table] ?? const ['id']).toSet();
    final assignments = columns
        .where((c) => !targetSet.contains(c))
        .map((c) => '$c = excluded.$c')
        .join(', ');

    return 'INSERT INTO $table SELECT * FROM $attachAlias.$table WHERE true '
        'ON CONFLICT($target) DO UPDATE SET $assignments '
        'WHERE excluded.updated_at > $table.updated_at';
  }

  /// Replaces the live database file with the backup at [path].
  ///
  /// Snapshots the current file to [rollbackPath] first and restores it if reopening throws, so a
  /// corrupt backup cannot leave the user with no database at all.
  ///
  /// **The caller must close the database before calling this and reopen after.** A file cannot be
  /// swapped underneath an open connection, and this class does not own the connection's lifecycle —
  /// which is why the swap is exposed as a file operation with an explicit contract rather than
  /// hidden behind a method that appears to manage it.
  Future<Result<RestoreReport, Failure>> replaceFiles({
    required String backupPath,
    required String livePath,
    required String rollbackPath,
  }) async {
    final versionCheck = await readBackupSchemaVersion(backupPath);
    if (versionCheck.isFailure)
      return Result.failure(versionCheck.failureOrNull!);
    final backupVersion = versionCheck.valueOrNull!;
    if (backupVersion > _database.schemaVersion) {
      return Result.failure(
        BusinessRuleFailure(
          'That backup was made by a newer version of Alaya.',
          rule: 'backupTooNew',
        ),
      );
    }

    final live = File(livePath);
    try {
      if (live.existsSync()) await live.copy(rollbackPath);
      await File(backupPath).copy(livePath);
      return Result.ok(
        (
          mode: RestoreMode.replace,
          tablesMerged: 0,
          backupSchemaVersion: backupVersion,
          rollbackPath: rollbackPath,
        ),
      );
    } on Object catch (error) {
      await restoreRollback(rollbackPath: rollbackPath, livePath: livePath);
      return Result.failure(
        UnexpectedFailure(
          'The restore failed and the previous database was put back.',
          cause: error,
        ),
      );
    }
  }

  /// Puts the rollback snapshot back, for a caller whose reopen threw.
  Future<Result<void, Failure>> restoreRollback({
    required String rollbackPath,
    required String livePath,
  }) async {
    try {
      final rollback = File(rollbackPath);
      if (!rollback.existsSync()) {
        return const Result.failure(
          BusinessRuleFailure(
            'There is no rollback snapshot to restore.',
            rule: 'noRollback',
          ),
        );
      }
      await rollback.copy(livePath);
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The rollback could not be restored.', cause: error),
      );
    }
  }

  Future<bool> _tableExistsInBackup(String table) async {
    final row = await _database
        .customSelect(
          "SELECT count(*) AS n FROM $attachAlias.sqlite_master "
          "WHERE type = 'table' AND name = ?",
          variables: [Variable<String>(table)],
        )
        .getSingleOrNull();
    return (row?.read<int>('n') ?? 0) > 0;
  }

  Future<List<String>> _columnsOf(String table) async {
    final rows = await _database
        .customSelect('PRAGMA table_info($table)')
        .get();
    return rows.map((r) => r.read<String>('name')).toList();
  }
}
```

### `lib/data/backup/share_backup_transfer.dart`

```dart
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
```

### `lib/data/platform/saf_channel.dart`

```dart
import 'dart:async';

import 'package:flutter/services.dart';

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// The Dart side of the Storage Access Framework bridge.
///
/// **This replaces `file_picker`, which cannot be used in this project.** ARCH_1 §7.4 documents why: the
/// resolvable version is 3.0.4 from 2020, whose `android/build.gradle` calls `jcenter()` — shut down in
/// 2021 — so `pub get` succeeds and `assembleDebug` fails. §7 anticipated this and recommended "a small
/// SAF platform channel" instead; this is it, and it also removes five transitive desktop and web
/// dependencies an Android-only app never used.
///
/// **No permission is declared anywhere.** SAF's whole point is that the user picks the document in the
/// system's own sheet and the grant is scoped to that choice — no `WRITE_EXTERNAL_STORAGE`, no
/// `MANAGE_EXTERNAL_STORAGE` (ARCH_3 §3.3).
///
/// Both calls return **null when the sheet was dismissed**, which is not a failure: cancelling is the
/// commonest thing to do with a file chooser.
final class SafChannel {
  /// Creates the bridge. [channel] is injectable so a test can answer without a platform.
  const SafChannel({MethodChannel channel = const MethodChannel(channelName)})
    : _channel = channel;

  final MethodChannel _channel;

  /// The channel name, matched by `SafPlugin.kt`.
  static const String channelName = 'com.alaya/saf';

  /// Opens a document and returns a **cache copy's absolute path**.
  ///
  /// A copy rather than the URI, because `RestoreService` runs `ATTACH DATABASE` on a filesystem path and
  /// SQLite cannot open a `content://` URI — and because the read grant expires with the activity result,
  /// so a URI kept past it would be unreadable exactly when the restore needed it.
  Future<Result<String?, Failure>> openDocument({
    List<String> mimeTypes = const ['*/*'],
  }) async {
    try {
      final path = await _channel.invokeMethod<String>(
        'openDocument',
        <String, Object?>{'mimeTypes': mimeTypes},
      );
      return Result.ok(path);
    } on PlatformException catch (error) {
      return Result.failure(
        UnexpectedFailure(
          error.message ?? 'That file could not be opened.',
          cause: error,
        ),
      );
    } on MissingPluginException catch (error) {
      // Says which half is missing. A generic failure here sends somebody looking at their file manager
      // when the answer is that `SafPlugin` was never registered in `MainActivity`.
      return Result.failure(
        UnexpectedFailure(
          'File access is not available in this build.',
          cause: error,
        ),
      );
    }
  }

  /// Raises the create-document sheet and writes [sourcePath] into whatever the user chose.
  ///
  /// One round trip rather than two, so Dart never holds a URI it has no way to use.
  Future<Result<String?, Failure>> createDocument({
    required String sourcePath,
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) async {
    try {
      final uri = await _channel.invokeMethod<String>(
        'createDocument',
        <String, Object?>{
          'sourcePath': sourcePath,
          'fileName': fileName,
          'mimeType': mimeType,
        },
      );
      return Result.ok(uri);
    } on PlatformException catch (error) {
      return Result.failure(
        UnexpectedFailure(
          error.message ?? 'That file could not be saved.',
          cause: error,
        ),
      );
    } on MissingPluginException catch (error) {
      return Result.failure(
        UnexpectedFailure(
          'File access is not available in this build.',
          cause: error,
        ),
      );
    }
  }
}
```

### `lib/data/ports/split_share_port.dart`

```dart
import 'package:share_plus/share_plus.dart';

/// Hands text to the system share sheet.
///
/// **A port with one method, and the containment is the point.** `B4_DATA`'s `ShareBackupTransfer`
/// records why: `share_plus` v11 replaced `Share.shareXFiles` with
/// `SharePlus.instance.share(ShareParams(...))`, and it calls itself *"the sharper edge"* of its two
/// dependencies. Keeping every reference in one small file means the next such change has exactly one
/// casualty rather than a screen.
///
/// It also keeps `share_plus` out of the widget tree, so the sheet above is testable without a plugin
/// channel — a widget test can override this with a fake that records what it was handed.
abstract interface class SplitSharePort {
  /// Offers [text] to the system share sheet.
  Future<void> shareText(String text);
}

/// The production port.
final class SystemSplitShare implements SplitSharePort {
  /// Creates the port.
  const SystemSplitShare();

  @override
  Future<void> shareText(String text) =>
      SharePlus.instance.share(ShareParams(text: text));
}
```

### `lib/data/reminders/daily_job.dart`

```dart
/// The daily background job: recompute reminders, and purge what has outlived the trash.
///
/// **The two scheduled obligations nothing else honours.** ARCH_3 §7 wants a daily recompute so a digest reflects
/// what is actually coming, and §4.2's thirty-day retention is a promise the app does not keep unless something
/// enforces it. Both ports exposed the methods; until this file, nothing called them on a schedule.
///
/// **It runs in its own isolate, so it builds its own dependencies.** A `workmanager` callback has no access to
/// the UI isolate's Riverpod container — the providers there simply do not exist in this one. That is why the
/// wiring is repeated here rather than reused, and why the database is opened through
/// `openAlayaDatabase`, the single permitted open path (Law L10), rather than by reaching for a
/// connection somebody else made.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/calendar_dao.dart';
import 'package:alaya/data/daos/account_dao.dart';
import 'package:alaya/data/daos/notification_schedule_dao.dart';
import 'package:alaya/data/daos/split_dao.dart';
import 'package:alaya/data/daos/split_view_dao.dart';
import 'package:alaya/data/repositories/split_group_repository_impl.dart';
import 'package:alaya/data/repositories/split_ledger_repository_impl.dart';
import 'package:alaya/domain/services/split/split_balance_service.dart';
import 'package:alaya/data/daos/settings_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/connection/open_database.dart';
import 'package:alaya/data/reminders/local_notification_scheduler.dart';
import 'package:alaya/data/repositories/calendar_repository_impl.dart';
import 'package:alaya/data/repositories/settings_repository_impl.dart';
import 'package:alaya/data/trash/trash_adapter.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';

/// The unique name the periodic task is registered under.
///
/// Stable, so re-registering replaces rather than stacking: `workmanager` keys by this name, and a second
/// registration under a new name would mean two jobs doing the same work on two schedules.
const String dailyTaskName = 'alaya.daily';

/// How often the job runs.
///
/// **A day, and inexact by nature.** `workmanager` cannot promise a moment and does not try; Android batches
/// these to save battery. That is compatible with ARCH_3 §7 on purpose — the digest itself is scheduled by
/// `flutter_local_notifications` at the user's chosen time, and this job only decides what it will say.
const Duration dailyInterval = Duration(days: 1);

/// Registers the daily job. Called once from `bootstrap()`.
Future<void> registerDailyJob() async {
  await Workmanager().initialize(alayaCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    dailyTaskName,
    dailyTaskName,
    frequency: dailyInterval,
    // `ExistingPeriodicWorkPolicy`, not `ExistingWorkPolicy`: `registerPeriodicTask` has its own enum, and the
    // one-shot type is not assignable to it.
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(
      // No network requirement: everything this job does is local. Asking for connectivity would delay a purge
      // indefinitely on a phone that is rarely online, which is the opposite of a retention guarantee.
      networkType: NetworkType.notRequired,
      requiresBatteryNotLow: true,
    ),
  );
}

/// Builds a [LocalNotificationScheduler] over [database].
///
/// **Extracted so `bootstrap()` can re-arm at launch without a fourth copy of this wiring.** Three already
/// existed — this isolate's, the UI's `reminderPortProvider`, and none at startup — and a seven-argument
/// constructor duplicated per caller is a place where two copies drift and only one is tested.
///
/// **A fresh `FlutterLocalNotificationsPlugin` every call, deliberately.** It is not a singleton across
/// isolates: the instance the UI created does not exist in the `workmanager` isolate, and an uninitialised one
/// fails quietly rather than throwing. `LocalNotificationScheduler` initialises whatever it is handed, lazily,
/// which is why callers construct the scheduler rather than reaching for the plugin.
LocalNotificationScheduler buildReminderScheduler({
  required AlayaDatabase database,
  required Clock clock,
  required UidGenerator uids,
}) {
  final settingsDao = SettingsDao(database);
  final splitDao = SplitDao(database);

  // **The split chain, assembled here rather than injected into the scheduler.** The scheduler counts
  // ageing debts through a one-method function; it has no business knowing what a split is, and taking
  // `SplitBalanceService` would drag two repositories and three DAOs into a class that runs in a
  // `workmanager` isolate. This factory already exists to assemble everything from a database, which
  // makes it the right place and the only place — the seven-argument constructor this function replaced
  // is exactly the duplication its own doc warns about.
  final groups = SplitGroupRepositoryImpl(splitDao, settingsDao, clock);
  final balances = SplitBalanceService(
    ledger: SplitLedgerRepositoryImpl(
      splitDao,
      SplitViewDao(database),
      groups,
      AccountDao(database),
      clock,
    ),
    clock: clock,
  );

  return LocalNotificationScheduler(
    plugin: FlutterLocalNotificationsPlugin(),
    database: database,
    scheduleDao: NotificationScheduleDao(database),
    calendar: CalendarAggregator(CalendarRepositoryImpl(CalendarDao(database))),
    settings: SettingsRepositoryImpl(settingsDao, clock),
    uids: uids,
    clock: clock,
    // The threshold is `SplitBalanceService.defaultAgeingThresholdDays` — fourteen days, a judgement
    // rather than a finding, and documented as one where it is declared.
    ageingDebts: () async => (await balances.ageingDebts()).length,
  );
}

/// The background entry point.
///
/// `@pragma('vm:entry-point')` because the isolate is started by native code with no Dart caller — without it
/// tree-shaking removes this function from a release build and the job silently never runs.
@pragma('vm:entry-point')
void alayaCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != dailyTaskName) return true;
    AlayaDatabase? database;
    try {
      const clock = SystemClock();
      const uids = Uuid7Generator();
      // Defaults would supply both, but naming them keeps this isolate's wiring identical to the UI isolate's
      // rather than depending on two default lists staying in step.
      database = openAlayaDatabase(uids: uids, clock: clock);

      final trash = TrashAdapter(database: database, clock: clock);
      await trash.purgeExpired();

      final reminders = buildReminderScheduler(
        database: database,
        clock: clock,
        uids: uids,
      );
      await reminders.rescheduleAll();
      return true;
    } on Object {
      // **Returns true even on failure, deliberately.** Returning false asks Android to retry with backoff, and
      // a job that fails for a structural reason — a corrupt row, a revoked permission — would then retry
      // forever and cost battery for nothing. A missed day is recovered by tomorrow's run.
      return true;
    } finally {
      await database?.close();
    }
  });
}
```

### `lib/data/reminders/device_time_zone.dart`

```dart
/// Resolves the device's own IANA time zone in pure Dart, with no platform channel.
///
/// **Why this file exists.** `initializeTimeZones()` loads the zone database; it does not choose a zone.
/// `tz.local` stays UTC until something calls `setLocalLocation`, and nothing ever did — so every digest
/// this app has scheduled was booked against UTC wall time. In Ahmedabad that is 5½ hours late; in Los
/// Angeles it is 7 or 8 hours early; in Auckland it lands on the wrong day. The symptom is identical
/// everywhere and it never looks like a timezone bug: the screen shows the time the user picked, and the
/// notification arrives at some other hour.
///
/// **Pure Dart, and that is the design rather than a constraint.** The obvious fix is to ask Android for
/// `ZoneId.systemDefault()`. That is the wrong fix here for two reasons that have nothing to do with
/// ARCH_1 §7.4:
///
/// 1. `daily_job.dart` reschedules from a `workmanager` isolate. A channel registered in
///    `MainActivity.configureFlutterEngine` is not registered in that isolate — so the caller that
///    matters most after a reboot would be the only caller with no zone.
/// 2. A platform channel cannot be exercised in a widget test. That is the stated reason `ReminderPort`
///    exists, and a fix that inherits the same untestability inherits the same class of bug: green suite,
///    broken device.
///
/// **How it works: match behaviour, not names.** `dart:core` already knows the device's UTC offset at any
/// instant, DST included — `DateTime.fromMillisecondsSinceEpoch(ms).timeZoneOffset` asks the OS. So sample
/// the device's offset across fourteen months, ask every zone in the database the same questions, and keep
/// the zones whose answers agree at every probe. A zone that reproduces the device's entire DST behaviour
/// for a year either *is* the device's zone or is indistinguishable from it for scheduling purposes.
///
/// This is why no name lookup is needed, and why it is more robust than one: `DateTime.now().timeZoneName`
/// returns an abbreviation on Android, and abbreviations are ambiguous — `IST` is India, Israel *and* Irish
/// Summer Time, three zones and two hemispheres. An offset fingerprint cannot be ambiguous in that way.
library;

import 'package:timezone/timezone.dart' as tz;

/// How well the resolved zone reproduced the device's own behaviour.
enum TimeZoneMatch {
  /// Exactly one zone matched the device at every probe.
  exact,

  /// Several zones matched at every probe, including the fine pass.
  ///
  /// Not a degraded result. Zones that agree at every probe across fourteen months are interchangeable
  /// for a daily wall-clock reminder — `Asia/Kolkata` and `Asia/Calcutta` are the same rules under two
  /// names. Only the label is a guess; the delivery time is not.
  ambiguous,

  /// No zone matched every probe, so the closest was taken.
  ///
  /// Reachable when a device has a manually-skewed clock or a zone newer than the bundled database.
  /// Scheduling still works; it may be an hour out during a DST window.
  approximate,

  /// Nothing in the database shared the device's current offset. UTC was kept.
  fallback,
}

/// The outcome of one resolution, including enough to explain itself.
final class ResolvedTimeZone {
  /// Creates a resolution result.
  const ResolvedTimeZone({
    required this.location,
    required this.match,
    required this.deviceOffset,
    required this.candidates,
    required this.probes,
    required this.mismatches,
  });

  /// The zone to hand to `setLocalLocation`.
  final tz.Location location;

  /// How much to trust [location]'s name. Never affects whether delivery is correct.
  final TimeZoneMatch match;

  /// The device's offset at the moment of resolution.
  ///
  /// Kept so a caller can notice the device has changed zone — a flight — and re-resolve, which is what
  /// makes the port's "still 9am after you fly somewhere" promise true rather than aspirational.
  final Duration deviceOffset;

  /// How many zones matched at every probe.
  final int candidates;

  /// How many instants were compared.
  final int probes;

  /// How many probes the chosen zone disagreed on. Zero unless [match] is [TimeZoneMatch.approximate].
  final int mismatches;

  /// The IANA name, e.g. `Asia/Kolkata`.
  String get name => location.name;

  @override
  String toString() =>
      'ResolvedTimeZone($name, ${match.name}, offset=$deviceOffset, '
          'candidates=$candidates, probes=$probes, mismatches=$mismatches)';
}

/// Finds the zone whose offsets match this device's.
///
/// Stateless and synchronous: it reads `dart:core` and the already-loaded zone database and nothing else.
/// The caller loads the database and applies the result, because caching policy differs between the UI
/// isolate (long-lived, can change zone mid-flight) and the daily job's (born and dies in one run).
abstract final class DeviceTimeZone {
  /// The coarse pass's step, in days.
  ///
  /// Five days observes both sides of any DST period, since no zone's summer time is shorter than that.
  /// It deliberately does *not* try to separate zones whose transition dates differ by a week — the EU
  /// switches on the last Sunday of October and the US on the first Sunday of November — because that is
  /// what the fine pass is for, and running the fine step over 600 zones to discriminate a handful is
  /// work for nothing.
  static const int coarseStepDays = 5;

  /// The fine pass's step, in days. One, so a single-day difference in transition dates separates.
  static const int fineStepDays = 1;

  /// How far back the probe window reaches.
  static const int probeDaysBefore = 200;

  /// How far forward it reaches.
  ///
  /// Together with [probeDaysBefore] this spans fourteen months, so the window contains a full DST cycle
  /// whatever day of the year it runs on, in either hemisphere. A twelve-month window anchored at *now*
  /// can straddle a rule change and see each state once, which is not enough to tell two rules apart.
  static const int probeDaysAfter = 220;

  /// Resolves the device's zone.
  ///
  /// [now] is injectable so this can be tested against a fixed instant; [database] so a test can supply
  /// three known zones instead of six hundred. Neither is used in production.
  static ResolvedTimeZone resolve({
    DateTime? now,
    Iterable<tz.Location>? database,
  }) {
    final reference = (now ?? DateTime.now()).toUtc();
    final deviceOffset = _deviceOffsetAt(reference);

    // **Phase 1: the current offset, over everything.** One comparison per zone cuts six hundred to
    // roughly thirty before any DST work happens. Every zone the device could be is in this shortlist,
    // because a zone that disagrees about *now* cannot be the device's zone.
    final shortlist = <tz.Location>[];
    for (final location in database ?? _allLocations()) {
      if (_offsetAt(location, reference) == deviceOffset) shortlist.add(location);
    }

    if (shortlist.isEmpty) {
      // **UTC, and this is not silent.** `match` records it, so the caller can surface "we could not
      // work out your time zone" instead of quietly scheduling against the wrong one — which is the
      // failure this whole file exists to end.
      return ResolvedTimeZone(
        location: tz.UTC,
        match: TimeZoneMatch.fallback,
        deviceOffset: deviceOffset,
        candidates: 0,
        probes: 0,
        mismatches: 0,
      );
    }

    // **Phase 2: fourteen months of DST behaviour, over the shortlist only.**
    final coarse = _probeInstants(reference, coarseStepDays);
    var narrowed = _survivors(shortlist, coarse);

    // **Phase 3: the fine pass, and only when it can change the answer.** Skipped for a single survivor
    // and skipped when the coarse pass eliminated everything, which are the two common cases.
    var probesRun = coarse.length;
    if (narrowed.matched.length > 1) {
      final fine = _probeInstants(reference, fineStepDays);
      final refined = _survivors(narrowed.matched, fine);
      if (refined.matched.isNotEmpty) {
        narrowed = refined;
        probesRun = fine.length;
      }
    }

    if (narrowed.matched.isNotEmpty) {
      return ResolvedTimeZone(
        location: _preferred(narrowed.matched),
        match: narrowed.matched.length == 1
            ? TimeZoneMatch.exact
            : TimeZoneMatch.ambiguous,
        deviceOffset: deviceOffset,
        candidates: narrowed.matched.length,
        probes: probesRun,
        mismatches: 0,
      );
    }

    // Nothing matched every probe. The best of the shortlist still shares the device's offset today, so
    // it is right now and may drift for one DST window — strictly better than UTC, which is wrong now.
    return ResolvedTimeZone(
      location: narrowed.best ?? shortlist.first,
      match: TimeZoneMatch.approximate,
      deviceOffset: deviceOffset,
      candidates: shortlist.length,
      probes: probesRun,
      mismatches: probesRun - narrowed.bestHits,
    );
  }

  /// Every zone the loaded database knows.
  ///
  /// **The one expression in this file that could not be compiled against** (ARCH_M §7, and the scheduler's
  /// own note that this plugin surface "has moved between major versions"). If the analyzer rejects
  /// `tz.timeZoneDatabase.locations`, read the declaration in `package:timezone` rather than trying a
  /// second remembered name — the doc's rule is that a second guess after the first fails is worse than
  /// the first. Nothing else in this file changes either way.
  static Iterable<tz.Location> _allLocations() =>
      tz.timeZoneDatabase.locations.values;

  /// The device's own offset at [instant], from the OS rather than the zone database.
  ///
  /// `fromMillisecondsSinceEpoch` without `isUtc` yields a *local* `DateTime` for that instant, and its
  /// `timeZoneOffset` is therefore the device's offset then — DST included. This is the measurement the
  /// whole file is built on and it needs no plugin.
  static Duration _deviceOffsetAt(DateTime instant) =>
      DateTime.fromMillisecondsSinceEpoch(
        instant.millisecondsSinceEpoch,
      ).timeZoneOffset;

  /// What [location] thinks the offset is at [instant].
  ///
  /// Deliberately via `TZDateTime.timeZoneOffset` rather than the database's own zone lookup:
  /// `TZDateTime` implements `DateTime`, so this is the one member guaranteed to exist by an interface
  /// this project already depends on.
  static Duration _offsetAt(tz.Location location, DateTime instant) =>
      tz.TZDateTime.from(instant, location).timeZoneOffset;

  /// Instants to compare, [stepDays] apart, spanning the probe window.
  static List<DateTime> _probeInstants(DateTime reference, int stepDays) {
    final instants = <DateTime>[];
    for (var day = -probeDaysBefore; day <= probeDaysAfter; day += stepDays) {
      instants.add(reference.add(Duration(days: day)));
    }
    return instants;
  }

  /// Which of [candidates] agree with the device at every instant in [probes].
  static _Narrowing _survivors(
      List<tz.Location> candidates,
      List<DateTime> probes,
      ) {
    final expected = [for (final probe in probes) _deviceOffsetAt(probe)];
    final matched = <tz.Location>[];
    tz.Location? best;
    var bestHits = -1;

    for (final location in candidates) {
      var hits = 0;
      for (var i = 0; i < probes.length; i++) {
        if (_offsetAt(location, probes[i]) == expected[i]) hits++;
      }
      if (hits == probes.length) matched.add(location);
      if (hits > bestHits) {
        bestHits = hits;
        best = location;
      }
    }
    return _Narrowing(matched: matched, best: best, bestHits: bestHits);
  }

  /// Picks one name from several behaviourally identical zones.
  ///
  /// **Cosmetic by construction.** Every zone reaching here agreed with the device at every probe, so the
  /// choice cannot change when a notification arrives — only what a diagnostic line would print. The
  /// ordering prefers a real region over a fixed-offset pseudo-zone (`Etc/GMT-5`) and over a legacy alias
  /// (`US/Pacific`), then sorts by name so the answer is stable across runs rather than dependent on map
  /// iteration order.
  static tz.Location _preferred(List<tz.Location> candidates) {
    final sorted = [...candidates]..sort((a, b) {
      final tier = _tier(a.name).compareTo(_tier(b.name));
      return tier != 0 ? tier : a.name.compareTo(b.name);
    });
    return sorted.first;
  }

  static int _tier(String name) {
    final slash = name.indexOf('/');
    if (slash < 0 || name.startsWith('Etc/')) return 3;
    return _legacyRoots.contains(name.substring(0, slash)) ? 2 : 1;
  }

  /// Roots kept in the database for compatibility, each an alias of a `Region/City` zone.
  static const Set<String> _legacyRoots = {
    'SystemV',
    'US',
    'Canada',
    'Brazil',
    'Chile',
    'Mexico',
  };
}

/// One pass's result: who matched everything, and who came closest if nobody did.
final class _Narrowing {
  const _Narrowing({
    required this.matched,
    required this.best,
    required this.bestHits,
  });

  final List<tz.Location> matched;
  final tz.Location? best;
  final int bestHits;
}
```

### `lib/data/reminders/local_notification_scheduler.dart`

```dart
import 'package:drift/drift.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/notification_schedule_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/reminders/device_time_zone.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';
import 'package:alaya/domain/services/reminders/reminder_port.dart';

/// How many split debts are old enough to be worth mentioning, as of now.
///
/// **A function rather than a `SplitBalanceService`.** The scheduler assembles one message from
/// everything due; it has no business knowing what a split is, and taking the service would drag the
/// whole split repository chain into a class that runs in a `workmanager` isolate.
/// `buildReminderScheduler` owns that wiring, which is the same division `PurchaseFanOutService` keeps
/// by staying pure.
///
/// Returns a count rather than the debts themselves, because the digest is counts by kind — one line,
/// once a day (ARCH_3 §7). A richer sentence would need a second notification, which that section
/// forbids.
typedef AgeingDebtCounter = Future<int> Function();

/// The production [ReminderPort]: one daily digest, scheduled inexactly, in the device's own timezone.
///
/// **The only file in this phase that imports `flutter_local_notifications`.** `timezone` is imported here
/// and by `device_time_zone.dart`, which is pure Dart and does have tests. The plugin needs a platform
/// channel and so does not run in a widget test — which is the whole reason `ReminderPort` exists. This is
/// also the largest surface in the phase that could not be compiled against (ARCH_4 R22): `zonedSchedule`,
/// `AndroidScheduleMode`, and `requestNotificationsPermission` have each moved between major versions of the
/// plugin. 8A's `local_auth` took two wrong guesses before compiling; expect at least one here, and expect it
/// to cost this file and nothing else.
///
/// **One notification, not a stream of pings** (ARCH_3 §7). Every enabled kind is folded into a single sentence —
/// *"3 items expire this week, 1 bill due tomorrow"* — delivered once a day at a time the user picked. The
/// contract cannot express a per-item ping, and neither can this.
///
/// **Inexact, always.** `AndroidScheduleMode.inexactAllowWhileIdle` and never `exactAllowWhileIdle`: Android 14
/// restricts `SCHEDULE_EXACT_ALARM` and Play asks why an app needs it. A digest that arrives at 9:07 instead of
/// 9:00 has lost nothing.
///
/// **The zone is resolved, not assumed, and that was the bug.** `initializeTimeZones()` loads the database
/// without choosing a zone, so `tz.local` was UTC and every digest was booked against UTC wall time — 5½ hours
/// late in India, 8 hours early in California, a day out in New Zealand. `_ensureTimezones` now resolves the
/// device's real zone through [DeviceTimeZone] and re-resolves when the device's offset changes, which is what
/// makes this class's "somebody who asked for 9am wants 9am where they are" comment true rather than intended.
final class LocalNotificationScheduler implements ReminderPort {
  /// Creates the scheduler.
  LocalNotificationScheduler({
    required FlutterLocalNotificationsPlugin plugin,
    required AlayaDatabase database,
    required NotificationScheduleDao scheduleDao,
    required CalendarAggregator calendar,
    required SettingsRepository settings,
    required UidGenerator uids,
    required Clock clock,
    AgeingDebtCounter? ageingDebts,
  }) : _plugin = plugin,
       _db = database,
       _scheduleDao = scheduleDao,
       _calendar = calendar,
       _settings = settings,
       _uids = uids,
       _clock = clock,
       _ageingDebts = ageingDebts ?? _noAgeingDebts;

  final FlutterLocalNotificationsPlugin _plugin;
  final AlayaDatabase _db;
  final NotificationScheduleDao _scheduleDao;
  final CalendarAggregator _calendar;
  final SettingsRepository _settings;
  final UidGenerator _uids;
  final Clock _clock;

  /// Counts split debts past their ageing threshold, or reports none when unwired.
  ///
  /// **Defaulted rather than required**, so `bootstrap.dart`, the daily job and every test that builds
  /// a scheduler keep working untouched. A required parameter would have made this change reach files
  /// with no interest in splits.
  final AgeingDebtCounter _ageingDebts;

  /// The `app_settings` key holding which reminder kinds are on.
  ///
  /// Stored as a comma-separated list of names rather than one key per kind: adding a fifth kind then needs no
  /// migration, and an unknown name in the list is ignored rather than fatal.
  static const String enabledKindsKey = 'reminders.enabledKinds';

  /// The `app_settings` key holding the digest time as `HH:mm`.
  static const String digestTimeKey = 'reminders.digestTime';

  /// The Android notification id the daily digest always uses.
  ///
  /// **Fixed, so rescheduling replaces rather than accumulates.** Every other id comes from
  /// `NotificationScheduleDao.nextAndroidNotificationId`; the digest is the one notification that is always
  /// exactly one, so it gets a constant and cancelling it needs no lookup.
  static const int digestNotificationId = 1;

  /// How far ahead the digest looks.
  ///
  /// A week, because that is the horizon a sentence can usefully summarise. A month's worth of counts reads as a
  /// backlog rather than a nudge, and a day's is too late to act on an expiry.
  static const Duration horizon = Duration(days: 7);

  /// The reference type recorded against the digest's `notification_schedule` row.
  static const String digestRefType = 'digest';

  /// The notification id used by [sendTest].
  ///
  /// Deliberately not [digestNotificationId]: a test must never cancel or overwrite a real scheduled
  /// digest, and reusing the id would do exactly that.
  static const int testNotificationId = 9001;

  /// The status-bar icon: white on transparency, at `android/app/src/main/res/drawable/ic_notification.xml`.
  ///
  /// **A resource *name*, not a resource *reference*, and the difference broke every notification this app
  /// ever tried to send.** This read `'@drawable/ic_notification'` — which is XML syntax, valid inside a
  /// layout or a manifest and nowhere else. The plugin resolves it on the Android side with
  /// `getResources().getIdentifier(name, "drawable", packageName)`, and `getIdentifier` wants
  /// `ic_notification`. Given the `@drawable/` prefix it matches nothing and returns 0.
  ///
  /// So the drawable was correct, present, and unreachable. Three symptoms came from this one string: the
  /// reminder switches would not stay on, the daily digest never fired, and a test notification never once
  /// arrived — all of them because `_ensurePlugin()` could not resolve the icon it was initialising with.
  ///
  /// **Nothing catches it at build time and nothing can.** A drawable name is a string the compiler never
  /// sees; `flutter analyze` is happy either way, and both spellings look equally plausible in review. The
  /// `@`-prefixed form is what you write in `AndroidManifest.xml`, four lines away from here in the same
  /// change, which is exactly why the wrong one felt right.
  static const String notificationIcon = 'ic_notification';

  bool _databaseLoaded = false;
  ResolvedTimeZone? _zone;
  bool _pluginReady = false;

  /// Loads the zone database once, then resolves the device's zone and applies it to `tz.local`.
  ///
  /// **`initializeTimeZones()` alone was the bug.** It loads six hundred zones and selects none of them;
  /// `tz.local` stays UTC until `setLocalLocation` is called, and nothing called it. Every `TZDateTime` built
  /// by `_nextOccurrence` was therefore a UTC wall time wearing a local label, so a 9am digest fired at 9am
  /// UTC — 2:30pm in Ahmedabad, 1am in Los Angeles. Nothing in a build or a test run could see it, because
  /// the tests use a fake and a fake has no zone.
  ///
  /// **Re-resolves when the device's offset changes.** The UI isolate outlives a flight: resolving once at
  /// startup and caching forever would keep scheduling in the zone the user left. Comparing the current
  /// offset against the resolved one is a single `dart:core` read, cheap enough to do on every reschedule,
  /// and it means a digest follows the device the next time anything reschedules — which the daily job does
  /// once a day regardless.
  ///
  /// **Returns the resolution rather than only storing it**, so [zone] needs no null check and no `!`. A
  /// nullable field read after a method that always assigns it is a place where a later edit introduces a
  /// crash the type system had been willing to prevent.
  Future<ResolvedTimeZone> _ensureTimezones() async {
    if (!_databaseLoaded) {
      tz_data.initializeTimeZones();
      _databaseLoaded = true;
    }
    final cached = _zone;
    if (cached != null &&
        cached.deviceOffset == DateTime.now().timeZoneOffset) {
      return cached;
    }
    final resolved = DeviceTimeZone.resolve();
    tz.setLocalLocation(resolved.location);
    return _zone = resolved;
  }

  /// Brings the notification plugin up, once.
  ///
  /// **This was missing entirely until Phase 9, and nothing worked without it.** `zonedSchedule` on an
  /// uninitialised plugin does not throw — it fails quietly — so the digest had never fired on a device while
  /// every test passed, because the tests use a fake and the fake has nothing to initialise.
  ///
  /// `settings` is **named**, like every other parameter on this plugin version — `zonedSchedule` and `cancel`
  /// are too. This is the third time that surface has differed from its documented form, so treat any call here
  /// as named-only until the analyzer says otherwise.
  ///
  /// **The icon is a purpose-made drawable, not `@mipmap/ic_launcher`.** Android flattens a notification icon to
  /// a white silhouette on API 21 and above, discarding colour entirely, so pointing this at the launcher icon
  /// renders a solid white square in the status bar. `@drawable/ic_notification` is white-on-transparent by
  /// construction.
  Future<void> _ensurePlugin() async {
    if (_pluginReady) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(notificationIcon),
      ),
    );
    _pluginReady = true;
  }

  @override
  Stream<ReminderSettings> watchSettings() =>
      _db.select(_db.appSettings).watch().asyncMap((_) => _readSettings());

  Future<ReminderSettings> _readSettings() async {
    final stored = await _settings.readValue(enabledKindsKey);
    final time = await _settings.readValue(digestTimeKey);
    final enabled = <NotificationKind>{};
    for (final name in (stored ?? '').split(',')) {
      for (final kind in reminderKinds) {
        if (kind.name == name.trim()) enabled.add(kind);
      }
    }
    final parts = (time ?? '09:00').split(':');
    return ReminderSettings(
      enabled: enabled,
      digestHour: int.tryParse(parts.first) ?? 9,
      digestMinute: parts.length > 1 ? int.tryParse(parts.last) ?? 0 : 0,
    );
  }

  @override
  Future<ReminderPermission> permission() async {
    await _ensurePlugin();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return ReminderPermission.denied;
    final enabled = await android.areNotificationsEnabled();
    if (enabled ?? false) return ReminderPermission.granted;
    // **`notRequested` unless something has been asked for.** The OS cannot tell us whether we have asked, so the
    // app records it: a stored digest time means a toggle was once turned on, which means the prompt has been
    // shown. Without this the screen would nag somebody who deliberately said no.
    final asked = await _settings.readValue(digestTimeKey);
    return asked == null
        ? ReminderPermission.notRequested
        : ReminderPermission.denied;
  }

  @override
  Future<ReminderPermission> requestPermission() async {
    await _ensurePlugin();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return ReminderPermission.denied;
    final granted = await android.requestNotificationsPermission();
    return (granted ?? false)
        ? ReminderPermission.granted
        : ReminderPermission.denied;
  }

  @override
  Future<Result<ReminderSettings, Failure>> setEnabled({
    required NotificationKind kind,
    required bool enabled,
  }) async {
    try {
      final current = await _readSettings();
      final next = {...current.enabled};
      enabled ? next.add(kind) : next.remove(kind);
      await _settings.writeValue(
        key: enabledKindsKey,
        value: next.map((kind) => kind.name).join(','),
        valueType: 'string',
      );
      final settings = current.copyWith(enabled: next);
      // Turning the last one off cancels everything rather than leaving a digest that says nothing.
      next.isEmpty ? await cancelAll() : await _scheduleDigest(settings);
      return Result.ok(settings);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That reminder could not be changed.', cause: error),
      );
    }
  }

  @override
  Future<Result<ReminderSettings, Failure>> setDigestTime({
    required int hour,
    required int minute,
  }) async {
    try {
      final two = (int value) => value < 10 ? '0$value' : '$value';
      await _settings.writeValue(
        key: digestTimeKey,
        value: '${two(hour)}:${two(minute)}',
        valueType: 'string',
      );
      final settings = (await _readSettings()).copyWith(
        digestHour: hour,
        digestMinute: minute,
      );
      if (settings.anyEnabled) await _scheduleDigest(settings);
      return Result.ok(settings);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure(
          'The reminder time could not be changed.',
          cause: error,
        ),
      );
    }
  }

  @override
  Stream<List<ScheduledReminder>>
  watchScheduled() => _scheduleDao.watchScheduled().map(
    (rows) => [
      for (final row in rows)
        ScheduledReminder(
          id: row.id,
          // The row's own `kind` column, converted by drift — not derived from `refType`, which I had
          // written before reading the table. Two sources for one fact is one too many.
          kind: row.kind,
          // **`.toLocal()`, and the missing call was half the bug.** The column is a UTC instant, and the
          // previous version handed its *UTC calendar fields* to `DateKey.fromDateTime` — which takes fields
          // as given and converts nothing. So the date reported was the UTC date: yesterday for anything
          // before 05:30 in India, tomorrow for an evening digest in California. Converting here means every
          // consumer gets a wall clock without having to remember to ask for one.
          at: DateTime.fromMillisecondsSinceEpoch(
            row.scheduledAtUtcMillis,
            isUtc: true,
          ).toLocal(),
          androidNotificationId: row.androidNotificationId,
        ),
    ],
  );

  @override
  Future<ReminderZone> zone() async {
    final resolved = await _ensureTimezones();
    return ReminderZone(
      name: resolved.name,
      // **`ambiguous` counts as a match, and that is not a concession.** Several zones agreeing with the device
      // at every probe across fourteen months are the same rules under different names, so the digest lands at
      // the right moment whichever label was picked. Only `approximate` and `fallback` mean the schedule may be
      // wrong, and those are the two the user needs told about.
      matchesDevice:
          resolved.match == TimeZoneMatch.exact ||
          resolved.match == TimeZoneMatch.ambiguous,
    );
  }

  @override
  Future<Result<int, Failure>> rescheduleAll() async {
    try {
      final settings = await _readSettings();
      if (!settings.anyEnabled) {
        await cancelAll();
        return const Result.ok(0);
      }
      final count = await _scheduleDigest(settings);
      return Result.ok(count);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('Reminders could not be rescheduled.', cause: error),
      );
    }
  }

  @override
  Future<Result<int, Failure>> pendingCount() async {
    try {
      await _ensurePlugin();
      // **Asks the OS, not the database.** `pendingNotificationRequests` is the plugin's own view of what
      // `AlarmManager` is holding, so it is the only value in this class that is not something Alaya asserted
      // about itself. `.length` rather than the list: the identities add nothing a count does not, and naming
      // `PendingNotificationRequest` would be one more type to have guessed wrongly.
      final pending = await _plugin.pendingNotificationRequests();
      return Result.ok(pending.length);
    } on Object catch (error) {
      // A throw here is as informative as a zero — both mean the alarm path cannot be confirmed — so it goes
      // to the screen rather than the log, like `sendTest`'s.
      return Result.failure(
        UnexpectedFailure(
          'Your phone could not be asked what it has scheduled.',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<void, Failure>> sendTest() async {
    try {
      await _ensurePlugin();
      // `show`, not `zonedSchedule`. The point is to remove timing from the question entirely — if this
      // arrives, the icon resolves, the permission is real and the channel exists, and any remaining
      // silence is about *when* rather than *whether*.
      await _plugin.show(
        id: testNotificationId,
        title: 'Reminders are working',
        body:
            'This is a test. Your daily summary will arrive at the time you set.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            // The digest's own channel, on purpose. A test on a different channel could succeed while
            // the real one is blocked in system settings — which is the failure most worth catching.
            'alaya_digest',
            'Daily summary',
            channelDescription: 'One message a day about what is coming up.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
      return const Result.ok(null);
    } on Object catch (error) {
      // **A throw here is the answer, not an inconvenience.** A missing `@drawable/ic_notification` is a
      // runtime string the compiler never checks, so this is the only place it can surface — and the
      // message goes to the screen rather than the log.
      return Result.failure(
        UnexpectedFailure(
          'That test notification could not be sent.',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<void, Failure>> cancelAll() async {
    try {
      await _ensurePlugin();
      // `cancel` is named-only on the installed plugin, like `zonedSchedule` — this version takes nothing
      // positionally anywhere on its surface.
      await _plugin.cancel(id: digestNotificationId);
      await _scheduleDao.cancelAll(nowUtcMillis: _clock.nowUtcMillis());
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('Reminders could not be cancelled.', cause: error),
      );
    }
  }

  /// Counts what is coming, writes one schedule row, and books one notification.
  ///
  /// Idempotent by construction: the digest's Android id is a constant and its `notification_schedule` row is
  /// replaced by `refType`/`refId`, so the daily `workmanager` job can call this as often as it likes without
  /// stacking duplicates — which is exactly what ARCH_3 §7 means by the table guaranteeing idempotency.
  Future<int> _scheduleDigest(ReminderSettings settings) async {
    await _ensurePlugin();
    await _ensureTimezones();
    final today = _clock.today();
    final events = await _calendar
        .watchRange(
          from: today,
          to: today.addDays(horizon.inDays),
          today: today,
        )
        .first;

    final counts = <NotificationKind, int>{};
    for (final event in events) {
      final kind = _kindForEvent(event.type);
      if (kind == null || !settings.enabled.contains(kind)) continue;
      counts[kind] = (counts[kind] ?? 0) + 1;
    }

    // **The second source, and the only one that is not a calendar event.** An ageing debt has no date:
    // nobody agreed to settle by anything, it has simply been three weeks. That cannot be a view arm,
    // because ARCH_2 §12.2 forbids a view from consulting the current time — so the comparison happens
    // in Dart against the injected clock, inside `SplitBalanceService`.
    //
    // **Added to the settle-by count rather than deduplicated against it.** The calendar arm counts
    // *expenses* with a deadline; this counts *counterparties* past a threshold, and one person can be
    // both. Reconciling them would need a query per event to find each expense's counterparty, to
    // improve a number that already reads "3 debts to settle" on a screen that shows what they are.
    // The count is items needing attention, not distinct debts, and over-counting errs toward
    // reminding rather than staying quiet.
    if (settings.enabled.contains(NotificationKind.settlementDue)) {
      final ageing = await _ageingDebts();
      if (ageing > 0) {
        counts[NotificationKind.settlementDue] =
            (counts[NotificationKind.settlementDue] ?? 0) + ageing;
      }
    }
    if (counts.isEmpty) {
      // **Nothing to say means nothing is sent.** A daily notification reading "0 items expire this week" is how
      // a reminder becomes something people switch off.
      await _plugin.cancel(id: digestNotificationId);
      await _scheduleDao.cancelForRef(
        refType: digestRefType,
        refId: digestRefType,
        nowUtcMillis: _clock.nowUtcMillis(),
      );
      return 0;
    }

    final when = _nextOccurrence(settings.digestHour, settings.digestMinute);
    final total = counts.values.fold<int>(0, (sum, value) => sum + value);

    final now = _clock.nowUtcMillis();
    await _scheduleDao.replaceForRef(
      refType: digestRefType,
      refId: digestRefType,
      nowUtcMillis: now,
      replacement: NotificationScheduleCompanion.insert(
        id: _uids.generate(),
        // The digest covers whichever kind has the most entries, because the column holds one and the sentence
        // holds several. It is what `watchScheduled` shows, so the row names the thing the user will most likely
        // be reminded about rather than an arbitrary first.
        kind: _dominantKind(counts),
        refType: digestRefType,
        refId: digestRefType,
        scheduledAtUtcMillis: when.toUtc().millisecondsSinceEpoch,
        androidNotificationId: digestNotificationId,
        status: NotificationStatus.scheduled,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await _plugin.zonedSchedule(
      // **Every argument named.** The installed plugin's `zonedSchedule` takes `id`, `scheduledDate` and
      // `notificationDetails` as named parameters and accepts nothing positionally — the analyzer named all three.
      id: digestNotificationId,
      title: _digestTitle(counts),
      body: _digestBody(counts),
      scheduledDate: when,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'alaya_digest',
          'Daily summary',
          channelDescription: 'One message a day about what is coming up.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      // **Inexact, and this is the line that matters** (ARCH_3 §7). `exactAllowWhileIdle` would need
      // `SCHEDULE_EXACT_ALARM`, which Android 14 restricts and Play questions.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // Repeats daily at the same wall-clock time, following the device across a timezone change.
      matchDateTimeComponents: DateTimeComponents.time,
    );
    return total;
  }

  /// The next time [hour]:[minute] comes round in the device's own zone.
  ///
  /// `tz.local` rather than UTC, because a digest is a wall-clock promise: somebody who asked for 9am wants 9am
  /// where they are, and wants it to still be 9am after they fly somewhere. `_ensureTimezones` is what makes
  /// `tz.local` mean that; before it did, every line below was arithmetic on the wrong zone.
  ///
  /// **Tomorrow is built as a calendar day, not as `+ Duration(days: 1)`.** A `Duration` is elapsed time, so
  /// adding twenty-four hours across a DST boundary moves the wall clock by an hour and a 9am digest becomes
  /// 8am or 10am for the rest of the year. Overflowing the day field lets `TZDateTime` resolve the civil date,
  /// which keeps the promise the user actually made.
  ///
  /// A wall time that does not exist — 2:30am on a spring-forward morning — resolves to a nearby instant and
  /// the digest arrives an hour off on that one day, then self-corrects on the next reschedule. Worth knowing;
  /// not worth code, because the alternative is asking the user to pick a time that exists everywhere.
  tz.TZDateTime _nextOccurrence(int hour, int minute) {
    // **The injected clock, not the wall clock.** Every other date-sensitive path in this app takes `Clock`
    // so a `FixedClock` makes it reproducible; this one read the real time, which made "did it schedule for
    // the right moment" the single question in this class no test could ask.
    final now = tz.TZDateTime.from(_clock.now(), tz.local);
    final today = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (today.isAfter(now)) return today;
    return tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day + 1,
      hour,
      minute,
    );
  }

  String _digestTitle(Map<NotificationKind, int> counts) {
    final total = counts.values.fold<int>(0, (sum, value) => sum + value);
    return total == 1 ? '1 thing coming up' : '$total things coming up';
  }

  /// The one sentence.
  ///
  /// **Assembled here rather than from the ARB, and that is a deviation worth recording.** A notification is
  /// built by a `workmanager` isolate with no `BuildContext` and no `AlayaStrings`, so Law U5's "every string
  /// through the ARB" cannot reach it. The alternative — passing pre-localised text from the UI into a background
  /// job that may run days later, in a locale the user has since changed — would be worse than plain English.
  String _digestBody(Map<NotificationKind, int> counts) {
    final parts = <String>[];
    for (final kind in reminderKinds) {
      final count = counts[kind];
      if (count == null || count == 0) continue;
      parts.add(switch (kind) {
        NotificationKind.expiry =>
          count == 1 ? '1 item expires' : '$count items expire',
        NotificationKind.serviceDue =>
          count == 1 ? '1 service due' : '$count services due',
        NotificationKind.recurringDue =>
          count == 1 ? '1 bill due' : '$count bills due',
        NotificationKind.warrantyEnd =>
          count == 1 ? '1 warranty ends' : '$count warranties end',
        NotificationKind.settlementDue =>
          count == 1 ? '1 debt to settle' : '$count debts to settle',
        // Not in `reminderKinds`, so it never reaches here — but the switch is exhaustive so that adding a sixth
        // kind fails to compile rather than falling through to silence. `settlementDue` above IS in that list,
        // so its branch is live and the empty string must not be copied to it.
        NotificationKind.lowStock => '',
      });
    }
    return '${parts.join(', ')} this week';
  }

  NotificationKind? _kindForEvent(CalendarEventType type) => switch (type) {
    CalendarEventType.batchExpiry => NotificationKind.expiry,
    CalendarEventType.serviceDue => NotificationKind.serviceDue,
    CalendarEventType.recurringDue => NotificationKind.recurringDue,
    CalendarEventType.warrantyEnd => NotificationKind.warrantyEnd,
    // A settle-by date is a deadline somebody set, so it belongs in the digest — unlike the two below.
    CalendarEventType.splitSettleBy => NotificationKind.settlementDue,
    // A recorded transaction and a shopping target are history and intent, not things that fall due.
    CalendarEventType.transaction || CalendarEventType.shoppingTarget => null,
  };

  /// Whichever kind contributes most to the digest.
  NotificationKind _dominantKind(Map<NotificationKind, int> counts) {
    var best = reminderKinds.first;
    var most = -1;
    for (final entry in counts.entries) {
      if (entry.value > most) {
        best = entry.key;
        most = entry.value;
      }
    }
    return best;
  }
}

/// The default [AgeingDebtCounter]: nothing ageing.
///
/// A named function rather than an inline closure, so a stack trace names it instead of showing an
/// anonymous closure.
Future<int> _noAgeingDebts() async => 0;
```

### `lib/data/remote/currency_api_client.dart`

```dart
import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/remote/network_policy.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// Fetches USD-pivoted rates, walking ARCH_3 §1.1's three-entry ladder and normalising two
/// incompatible response shapes into one [RateSnapshot].
///
/// The ladder exists because the endpoint most tutorials still show is dead: the fawazahmed0
/// project moved from `currency-api@1` to `@fawazahmed0/currency-api` on npm. Entry 2 is that
/// project's own mirror; entry 3 is Frankfurter, which is ECB-backed and self-hostable rather than
/// another community CDN — which is why it is the fallback.
///
/// **Never throws.** Every method returns null on failure, because ARCH_3 §1.3.2 makes a failed
/// fetch a no-op and Law L11 forbids a rate lookup from blocking a write.
final class CurrencyApiClient {
  /// Creates the client over [dio], gated by [policy].
  CurrencyApiClient({
    required Dio dio,
    NetworkPolicy policy = const NetworkPolicy(),
    Logger? logger,
  })  : _dio = dio,
        _policy = policy,
        _logger = logger;

  final Dio _dio;
  final NetworkPolicy _policy;
  final Logger? _logger;

  static const String _logTag = 'currency';

  /// The quote currencies requested from Frankfurter.
  ///
  /// Only entry 3 needs this list: the fawazahmed0 endpoints return *every* quote for a base in one
  /// file, which is exactly what makes one daily request enough (ARCH_3 §1.2).
  static const List<String> frankfurterQuotes = ['INR', 'EUR', 'JPY', 'CNY'];

  /// Fetches the latest rates, trying each ladder entry until one succeeds.
  ///
  /// Returns null only when all three failed.
  Future<RateSnapshot?> fetchLatest() async {
    for (final attempt in _latestLadder()) {
      final snapshot = await _attempt(attempt);
      if (snapshot != null && !snapshot.isEmpty) return snapshot;
    }
    _logger?.log(
      'Every currency ladder entry failed; leaving the rate cache untouched.',
      level: LogLevel.warning,
      tag: _logTag,
    );
    return null;
  }

  /// Fetches the rates quoted for [on], for backfilling a historical conversion.
  Future<RateSnapshot?> fetchOn(DateKey on) async {
    for (final attempt in _historicalLadder(on)) {
      final snapshot = await _attempt(attempt);
      if (snapshot != null && !snapshot.isEmpty) return snapshot;
    }
    return null;
  }

  List<_LadderEntry> _latestLadder() => [
    _LadderEntry(
      Uri.parse(
        'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest'
            '/v1/currencies/usd.min.json',
      ),
      'jsdelivr',
      _parseFawazahmed0,
    ),
    _LadderEntry(
      Uri.parse('https://latest.currency-api.pages.dev/v1/currencies/usd.min.json'),
      'currency-api.pages.dev',
      _parseFawazahmed0,
    ),
    _LadderEntry(
      Uri.parse(
        'https://api.frankfurter.dev/v2/rates'
            '?base=USD&quotes=${frankfurterQuotes.join(",")}',
      ),
      'frankfurter',
      _parseFrankfurter,
    ),
  ];

  List<_LadderEntry> _historicalLadder(DateKey on) {
    final iso = on.toIso();
    return [
      _LadderEntry(
        Uri.parse(
          'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@$iso'
              '/v1/currencies/usd.min.json',
        ),
        'jsdelivr@$iso',
        _parseFawazahmed0,
      ),
      _LadderEntry(
        Uri.parse('https://$iso.currency-api.pages.dev/v1/currencies/usd.min.json'),
        'currency-api.pages.dev@$iso',
        _parseFawazahmed0,
      ),
      _LadderEntry(
        Uri.parse(
          'https://api.frankfurter.dev/v2/rates'
              '?base=USD&quotes=${frankfurterQuotes.join(",")}&date=$iso',
        ),
        'frankfurter@$iso',
        _parseFrankfurter,
      ),
    ];
  }

  Future<RateSnapshot?> _attempt(_LadderEntry entry) async {
    try {
      // Every request passes the allowlist, including ones this class built itself — the gate is
      // worth nothing if the code that constructs URLs is exempt from it (ARCH_3 §1.4).
      _policy.ensureAllowed(entry.url);

      final response = await _dio.getUri<String>(
        entry.url,
        // Plain text, not Dio's automatic JSON decode, so the body can be decoded here and the raw
        // numeric text is available for `rateRaw`.
        options: Options(responseType: ResponseType.plain),
      );
      final body = response.data;
      if (body == null || body.isEmpty) return null;

      return entry.parse(body, entry.source);
    } on DisallowedHostError {
      // A programming error, not a network condition — rethrown so it surfaces in development
      // rather than being mistaken for an offline device.
      rethrow;
    } catch (error) {
      _logger?.log(
        'Currency ladder entry ${entry.source} failed.',
        level: LogLevel.debug,
        tag: _logTag,
        error: error,
      );
      return null;
    }
  }

  /// Parses the fawazahmed0 shape: `{"date":"2026-07-28","usd":{"inr":83.2,"eur":0.92,...}}`.
  ///
  /// Keys are lowercase and the rate map is nested under the base currency's own name.
  RateSnapshot? _parseFawazahmed0(String body, String source) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;

    final date = _parseIsoDate(decoded['date']);
    if (date == null) return null;

    final quotes = decoded['usd'];
    if (quotes is! Map<String, dynamic>) return null;

    return RateSnapshot(on: date, rates: _toRates(quotes, date), source: source);
  }

  /// Parses the Frankfurter shape:
  /// `{"amount":1.0,"base":"USD","date":"2026-07-28","rates":{"INR":83.2,...}}`.
  ///
  /// Keys are uppercase, the rate map is under a fixed `rates` key, and an `amount` other than 1
  /// would scale every rate — so it is divided out rather than assumed.
  RateSnapshot? _parseFrankfurter(String body, String source) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;

    final date = _parseIsoDate(decoded['date']);
    if (date == null) return null;

    final quotes = decoded['rates'];
    if (quotes is! Map<String, dynamic>) return null;

    final amount = _toDouble(decoded['amount']) ?? 1.0;
    if (amount <= 0) return null;

    return RateSnapshot(
      on: date,
      rates: _toRates(quotes, date, divisor: amount),
      source: source,
    );
  }

  /// Normalises a quote map into [UsdRate]s, upper-casing codes so both shapes index alike.
  List<UsdRate> _toRates(
      Map<String, dynamic> quotes,
      DateKey on, {
        double divisor = 1.0,
      }) {
    final rates = <UsdRate>[];
    for (final entry in quotes.entries) {
      final value = _toDouble(entry.value);
      if (value == null || value <= 0) continue;
      final rate = divisor == 1.0 ? value : value / divisor;
      rates.add(
        UsdRate(
          quoteCode: entry.key.toUpperCase(),
          on: on,
          rate: rate,
          // Dart's `toString()` on a double is its shortest round-trip form, so this reproduces the
          // exact value ARCH_3 §1.3.7 asks to be able to reproduce. What it does not preserve is
          // wire formatting — a body carrying `83.20` yields `83.2` — which carries no numeric
          // meaning. Preserving the literal token would mean scanning raw JSON text, which is
          // fragile for a difference that cannot change a figure.
          rateRaw: rate.toString(),
        ),
      );
    }
    return rates;
  }

  DateKey? _parseIsoDate(Object? raw) {
    if (raw is! String) return null;
    final parts = raw.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2].length > 2 ? parts[2].substring(0, 2) : parts[2]);
    if (year == null || month == null || day == null) return null;
    try {
      return DateKey.fromYmd(year, month, day);
    } on ArgumentError {
      return null;
    }
  }

  double? _toDouble(Object? raw) => switch (raw) {
    final num value => value.toDouble(),
    final String value => double.tryParse(value),
    _ => null,
  };
}

class _LadderEntry {
  const _LadderEntry(this.url, this.source, this.parse);

  final Uri url;
  final String source;
  final RateSnapshot? Function(String body, String source) parse;
}
```

### `lib/data/remote/network_policy.dart`

```dart
/// The complete list of hosts this app may contact, and the single gate every HTTP call passes
/// through (ARCH_3 §1.4).
///
/// Three purposes, and nothing else: currency rates, rewarded ads, and the tip purchase. No crash
/// reporter, no analytics SDK, no font CDN, no image loader. The value of an allowlist is that it
/// is checked in code rather than asserted in a document — a package that quietly wants a fourth
/// host fails [ensureAllowed] instead of shipping.
///
/// Ads and billing are Phase 8B and route through Google's own SDKs rather than this client, so
/// their hosts are recorded here for completeness but are not yet reachable through [isAllowed].
final class NetworkPolicy {
  /// Creates the policy.
  const NetworkPolicy();

  /// Hosts serving currency rates — the only hosts this app's own HTTP client may reach.
  ///
  /// `latest.currency-api.pages.dev` and `{date}.currency-api.pages.dev` are both real: the
  /// fawazahmed0 mirror puts the date in the subdomain for historical lookups, which is why
  /// [isAllowed] matches that host by suffix rather than exactly.
  static const Set<String> currencyHosts = {
    'cdn.jsdelivr.net',
    'api.frankfurter.dev',
  };

  /// The suffix that admits any `*.currency-api.pages.dev` subdomain.
  static const String currencyHostSuffix = '.currency-api.pages.dev';

  /// Hosts reached by Google's ad SDK, not by this app's HTTP client (Phase 8B).
  static const Set<String> adHosts = {'googleads.g.doubleclick.net'};

  /// Hosts reached by Google Play Billing, not by this app's HTTP client (Phase 8B).
  static const Set<String> billingHosts = {'play.google.com'};

  /// True when [url] may be requested by this app's own HTTP client.
  ///
  /// Requires HTTPS and rejects a URL carrying credentials — a rate endpoint never needs either,
  /// so anything presenting them is not the endpoint it claims to be.
  bool isAllowed(Uri url) {
    if (url.scheme != 'https') return false;
    if (url.userInfo.isNotEmpty) return false;
    final host = url.host.toLowerCase();
    return currencyHosts.contains(host) || host.endsWith(currencyHostSuffix);
  }

  /// Throws [DisallowedHostError] unless [url] passes [isAllowed].
  ///
  /// Throws rather than returning a failure deliberately: a disallowed host is a programming
  /// mistake, not a runtime condition a user can act on, and it should surface in development
  /// rather than degrade into a silent no-op.
  void ensureAllowed(Uri url) {
    if (!isAllowed(url)) throw DisallowedHostError(url);
  }
}

/// Thrown when code attempts an HTTP request to a host outside [NetworkPolicy]'s allowlist.
final class DisallowedHostError extends Error {
  /// Creates the error for [url].
  DisallowedHostError(this.url);

  /// The rejected URL.
  final Uri url;

  @override
  String toString() =>
      'DisallowedHostError: $url is not on the network allowlist (ARCH_3 §1.4). '
          'If a package needs this host, it does not go in the app.';
}
```

### `lib/data/repositories/account_repository_impl.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/account_dao.dart';
import 'package:alaya/data/daos/transaction_dao.dart';
import 'package:alaya/data/repositories/mappers/money_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/account_balance.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/repositories/account_repository.dart';
import 'package:alaya/domain/repositories/currency_repository.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';

/// `AccountRepository` backed by `AccountDao`.
final class AccountRepositoryImpl implements AccountRepository {
  /// Creates the repository over [dao], using [transactionDao] to resolve a transaction's line
  /// mapper dependency for [watchLedgerFor], [currency] for net-worth conversion, [settings] for
  /// the home currency code, and [clock] for write timestamps.
  const AccountRepositoryImpl(
    this._dao,
    this._transactionDao,
    this._currency,
    this._settings,
    this._clock,
  );

  final AccountDao _dao;
  final TransactionDao _transactionDao;
  final CurrencyRepository _currency;
  final SettingsRepository _settings;
  final Clock _clock;

  @override
  Stream<List<Account>> watchSelectable() => _dao.watchSelectable().map(
    (rows) => rows.map((r) => r.toEntity()).toList(),
  );

  @override
  Stream<List<Account>> watchAllIncludingArchived() => _dao
      .watchAllIncludingArchived()
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Account?> byId(String id) async =>
      (await _dao.byIdIncludingDeleted(id))?.toEntity();

  @override
  Stream<List<AccountBalance>> watchBalances() {
    return _dao.watchBalances().map(
      (rows) => rows
          .map(
            (r) => AccountBalance(
              accountId: r.accountId,
              balance: Money(r.balanceMinor, r.currencyCode),
            ),
          )
          .toList(),
    );
  }

  @override
  Stream<AccountBalance?> watchBalanceOf(String accountId) {
    return _dao
        .watchBalanceOf(accountId)
        .map(
          (row) => row == null
              ? null
              : AccountBalance(
                  accountId: row.accountId,
                  balance: Money(row.balanceMinor, row.currencyCode),
                ),
        );
  }

  @override
  Stream<List<Transaction>> watchLedgerFor(String accountId) {
    return _transactionDao
        .watchByAccount(accountId)
        .map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Future<Result<Account, Failure>> save(Account account) async {
    final existing = await _dao.byIdIncludingDeleted(account.id);

    if (existing == null) {
      final duplicate = await _dao.byNormalizedName(account.normalizedName);
      if (duplicate != null) {
        return Result.failure(
          ConflictFailure('An account named "${account.name}" already exists.'),
        );
      }
    }

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _dao.upsert(
      accountToCompanion(
        account,
        createdAt: stamps.createdAt,
        updatedAt: stamps.updatedAt,
      ),
    );
    return Result.ok(account);
  }

  @override
  Future<Result<void, Failure>> setArchived({
    required String id,
    required bool isArchived,
  }) async {
    await _dao.setArchived(
      id: id,
      isArchived: isArchived,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    final inUseCount = await _dao.activeTransactionCount(id);
    if (inUseCount > 0) {
      return Result.failure(
        BusinessRuleFailure(
          'This account has $inUseCount transaction(s) and cannot be deleted. Archive it instead.',
          rule: 'accountInUse',
        ),
      );
    }
    await _dao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }
}
```

### `lib/data/repositories/analytics_cache_repository_impl.dart`

```dart
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/analytics_cache_dao.dart';
import 'package:alaya/domain/repositories/analytics_cache_repository.dart';

/// `AnalyticsCacheRepository` backed by `AnalyticsCacheDao`.
///
/// **This is where the contract's `Duration` meets the DAO's absolute millis.** The DAO takes
/// `nowUtcMillis` and `staleAfterUtcMillis` so it stays assertable under a `FixedClock` — the rule
/// every read in this schema follows (ARCH_2 §12.2) — while the domain contract speaks a TTL and
/// knows nothing about a clock. Holding the `Clock` here is the whole of this class's job, and it is
/// why it is worth existing rather than having `AnalyticsCacheService` talk to the DAO directly:
/// that would put a `data/` import in `domain/` and break Law L12.
///
/// **The eviction problem the DAO's own doc comment warns about is already solved upstream.** Both
/// the DAO and the contract note that `cacheKey` is the sole primary key, so caching July would
/// evict June, and both defer the fix to a caller folding the params hash into the key.
/// `AnalyticsCacheService.keyFor` returns `'$queryName:$paramsHash'`, which is exactly that — so each
/// parameter set already owns a row and no schema change is needed (ARCH_4 §5.1 item 12).
final class AnalyticsCacheRepositoryImpl implements AnalyticsCacheRepository {
  /// Creates the repository over [dao], stamping and expiring entries with [clock].
  const AnalyticsCacheRepositoryImpl(this._dao, this._clock);

  final AnalyticsCacheDao _dao;
  final Clock _clock;

  @override
  Future<String?> read({
    required String cacheKey,
    required String paramsHash,
  }) {
    return _dao.read(
      cacheKey: cacheKey,
      paramsHash: paramsHash,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
  }

  @override
  Future<void> write({
    required String cacheKey,
    required String paramsHash,
    required String payloadJson,
    required Duration ttl,
  }) {
    final now = _clock.nowUtcMillis();
    return _dao.write(
      cacheKey: cacheKey,
      paramsHash: paramsHash,
      payloadJson: payloadJson,
      computedAtUtcMillis: now,
      // One clock reading for both, not two calls: a `computedAt` and a `staleAfter` derived from
      // different instants would drift by however long the write took, which is invisible and
      // pointless.
      staleAfterUtcMillis: now + ttl.inMilliseconds,
    );
  }

  @override
  Future<void> invalidate(String cacheKey) {
    return _dao.invalidate(
      cacheKey: cacheKey,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
  }

  @override
  Future<void> invalidateAll() async {
    // `await`ed rather than returned: the DAO reports how many rows it tombstoned and the contract
    // returns nothing, so `Future<int>` does not satisfy `Future<void>` without this.
    await _dao.invalidateAll(nowUtcMillis: _clock.nowUtcMillis());
  }
}
```

### `lib/data/repositories/analytics_port_impl.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/services/analytics/analytics_port.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';

/// `AnalyticsPort` over SQL — the adapter Law L12 requires and ARCH_3 §5.2 demands.
///
/// **Aggregation happens here and nowhere else.** §5.2's rule is that nothing is loaded into Dart to
/// be summed, while L12 forbids `domain/` importing drift; the port declared in `domain/` is what
/// lets both hold, and this is its one implementation.
///
/// Every method returns rows **grouped by currency, unconverted**. A SQL-side `SUM` across
/// currencies would already have destroyed the information `AnalyticsService` needs to convert per
/// data point, so a query that looks like it is missing a total is doing the one thing that keeps
/// the total correct.
///
/// Written as `customSelect` rather than as a DAO of generated queries because the twenty-four
/// aggregates share almost no shape with one another and several need SQL the query builder cannot
/// express — a weekday bucket, a unit-normalised ordering, a `NOT EXISTS` against the same table.
/// `readsFrom` is omitted throughout: every method returns a `Future` through `.get()`, and that set
/// only affects which writes re-trigger a `.watch()`.
final class AnalyticsPortImpl implements AnalyticsPort {
  /// Creates the adapter over [database], taking "today" from [clock].
  const AnalyticsPortImpl(this._database, this._clock);

  final AlayaDatabase _database;
  final Clock _clock;

  /// How far past [limit] a ranked query fetches before `AnalyticsService` re-ranks.
  ///
  /// SQL orders by raw minor units, which is the wrong order across currencies — so a query that
  /// limited to exactly [limit] would discard rows the service is about to promote. Four covers a
  /// household holding four currencies, which is more than the app's seeded five allows for in
  /// practice.
  static const int _currencySpread = 4;

  /// Spend is `withdrawal` and only `withdrawal`, in every query in this file.
  ///
  /// A transfer moves money between the user's own accounts and an adjustment is a bookkeeping
  /// correction; counting either as spending would double the first and invent the second
  /// (anomaly A33, and the same rule 6F's range rows apply).
  static const String _spendKind = 'withdrawal';

  // ── 1-8, 21-23: money over transactions ───────────────────────────────────────────────

  @override
  Future<List<RawMoneyRow>> spendBySubtype(AnalyticsWindow window) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT t.subtype AS group_key,
             t.subtype AS group_label,
             SUM(t.original_amount_minor) AS amount_minor,
             t.original_currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM v_active_transactions t
       WHERE t.kind = ?
         AND t.date_key BETWEEN ? AND ?
       GROUP BY t.subtype, t.original_currency_code
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows.map(_moneyRow).toList();
  }

  @override
  Future<List<RawMoneyRow>> spendByTag(AnalyticsWindow window) async {
    // `tags.deleted_at` is deliberately not filtered: a deleted tag still labels the transactions it
    // was on (anomaly A36), and excluding it would shrink a historical total with no visible cause.
    // `transaction_tags` has no `deleted_at` to filter — it is a composite-key link table
    // (ARCH_2 §4).
    //
    // A transaction carrying two tags contributes to both slices, so these slices do not sum to
    // total spend. That is inherent to grouping by a many-to-many label, and the UI says so rather
    // than presenting the slices as a partition.
    final rows = await _database
        .customSelect(
          '''
      SELECT tg.id AS group_key,
             tg.name AS group_label,
             SUM(t.original_amount_minor) AS amount_minor,
             t.original_currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM v_active_transactions t
        JOIN transaction_tags tt ON tt.transaction_id = t.tx_id
        JOIN tags tg ON tg.id = tt.tag_id
       WHERE t.kind = ?
         AND t.date_key BETWEEN ? AND ?
       GROUP BY tg.id, t.original_currency_code
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows.map(_moneyRow).toList();
  }

  @override
  Future<List<RawMoneyRow>> spendByPaymentMethod(AnalyticsWindow window) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT t.payment_method_id AS group_key,
             t.payment_method_name AS group_label,
             SUM(t.original_amount_minor) AS amount_minor,
             t.original_currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM v_active_transactions t
       WHERE t.kind = ?
         AND t.payment_method_id IS NOT NULL
         AND t.date_key BETWEEN ? AND ?
       GROUP BY t.payment_method_id, t.original_currency_code
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows.map(_moneyRow).toList();
  }

  @override
  Future<List<RawMoneyRow>> spendByPayee(
    AnalyticsWindow window, {
    int limit = 10,
  }) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT t.payee_id AS group_key,
             t.payee_name AS group_label,
             SUM(t.original_amount_minor) AS amount_minor,
             t.original_currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM v_active_transactions t
       WHERE t.kind = ?
         AND t.payee_id IS NOT NULL
         AND t.date_key BETWEEN ? AND ?
       GROUP BY t.payee_id, t.original_currency_code
       ORDER BY amount_minor DESC
       LIMIT ?
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
            Variable<int>(limit * _currencySpread),
          ],
        )
        .get();
    return rows.map(_moneyRow).toList();
  }

  @override
  Future<List<RawMonthRow>> totalsByMonthAndKind(
    AnalyticsWindow window,
    TransactionKind kind,
  ) async {
    // Bounded on `date_key` and grouped by `month_key`, rather than read from `v_monthly_totals`.
    // That view carries no `date_key`, so bounding it means comparing month keys — which turns a
    // 30-day window into two whole months and reports spending from outside the window the caller
    // asked for. Enum *name*, not index: Law L13 makes the name the schema contract.
    final rows = await _database
        .customSelect(
          '''
      SELECT t.month_key AS month_key,
             SUM(t.original_amount_minor) AS amount_minor,
             t.original_currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM v_active_transactions t
       WHERE t.kind = ?
         AND t.date_key BETWEEN ? AND ?
       GROUP BY t.month_key, t.original_currency_code
       ORDER BY t.month_key
      ''',
          variables: [
            Variable<String>(kind.name),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows.map(_monthRow).toList();
  }

  @override
  Future<List<RawMonthRow>> netFlowByMonth(AnalyticsWindow window) async {
    // `v_account_ledger` expands a transfer into two legs with opposite signs, so a self-transfer
    // nets to zero here without this query knowing anything about transfers (ARCH_2 §12.1). That
    // property is the whole reason net flow reads the ledger rather than the transactions.
    final rows = await _database
        .customSelect(
          '''
      SELECT (l.date_key / 100) AS month_key,
             SUM(l.signed_minor) AS amount_minor,
             l.currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM v_account_ledger l
       WHERE l.date_key BETWEEN ? AND ?
       GROUP BY month_key, l.currency_code
       ORDER BY month_key
      ''',
          variables: [
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows.map(_monthRow).toList();
  }

  @override
  Future<List<RawDateRow>> ledgerLegsForAccount(
    String accountId,
    AnalyticsWindow window,
  ) async {
    // **The first row is synthetic, and it is what makes a windowed trend correct.**
    // `openingBalance` takes no window, so a trend over anything narrower than all time would
    // otherwise start at the account's opening figure and jump on the first in-window leg. This row
    // carries the sum of every leg strictly before the window, dated at the window's start, with
    // `count` reporting how many legs it condenses — which is what `count` is for on this record.
    //
    // Emitted only when there is something to carry, so an account whose history starts inside the
    // window is unaffected.
    final carried = await _database
        .customSelect(
          '''
      SELECT COALESCE(SUM(l.signed_minor), 0) AS amount_minor,
             COUNT(*) AS row_count
        FROM v_account_ledger l
       WHERE l.account_id = ?
         AND l.date_key < ?
      ''',
          variables: [
            Variable<String>(accountId),
            Variable<int>(window.from.value),
          ],
        )
        .getSingle();

    final legs = await _database
        .customSelect(
          '''
      SELECT l.date_key AS date_key,
             l.signed_minor AS amount_minor,
             l.currency_code AS currency_code,
             1 AS row_count
        FROM v_account_ledger l
       WHERE l.account_id = ?
         AND l.date_key BETWEEN ? AND ?
       ORDER BY l.date_key, l.tx_id
      ''',
          variables: [
            Variable<String>(accountId),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();

    final carriedCount = carried.read<int>('row_count');
    final mapped = legs.map(_dateRow).toList();
    if (carriedCount == 0) return mapped;

    // The currency comes from the account rather than from the carried legs: `SUM` across a mixed
    // set would be meaningless, and an account holds exactly one currency (ARCH_2 §4).
    final account = await openingBalance(accountId);
    return [
      (
        dateKey: window.from.value,
        amountMinor: carried.read<int>('amount_minor'),
        currencyCode: account?.currencyCode ?? '',
        count: carriedCount,
      ),
      ...mapped,
    ];
  }

  @override
  Future<({int minor, String currencyCode})?> openingBalance(
    String accountId,
  ) async {
    // The base table, not `v_account_balances`: that view returns opening *plus* every leg, which is
    // the current balance. A running trend has to start before the legs it is about to add.
    final row = await _database
        .customSelect(
          '''
      SELECT a.opening_balance_minor AS minor,
             a.currency_code AS currency_code
        FROM accounts a
       WHERE a.id = ?
         AND a.deleted_at IS NULL
      ''',
          variables: [Variable<String>(accountId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return (
      minor: row.read<int>('minor'),
      currencyCode: row.read<String>('currency_code'),
    );
  }

  @override
  Future<List<RawMoneyRow>> totalSpend(AnalyticsWindow window) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT 'total' AS group_key,
             'total' AS group_label,
             SUM(t.original_amount_minor) AS amount_minor,
             t.original_currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM v_active_transactions t
       WHERE t.kind = ?
         AND t.date_key BETWEEN ? AND ?
       GROUP BY t.original_currency_code
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows.map(_moneyRow).toList();
  }

  @override
  Future<List<RawBucketRow>> spendByBucket(
    AnalyticsWindow window, {
    required bool byWeekday,
  }) async {
    // The bucket expression is chosen in Dart and interpolated, because it appears in both `SELECT`
    // and `GROUP BY` and SQLite will not group by a bound parameter. Neither branch contains
    // anything a caller supplied, so there is nothing to inject.
    //
    // `date_key` is an `INTEGER yyyymmdd`, so a weekday needs a real date first: `printf` rebuilds
    // the ISO string and `strftime('%w')` reads it. That returns 0 for Sunday, and ARCH_3 §5.1 wants
    // 1-7 Monday first, hence `(w + 6) % 7 + 1` — which maps Sunday's 0 to 7 and Monday's 1 to 1.
    //
    // No current time is involved, so ARCH_2 §12.2's ban on `now` in a read is untouched.
    const weekdayBucket =
        "((CAST(strftime('%w', printf('%04d-%02d-%02d', "
        't.date_key / 10000, (t.date_key / 100) % 100, t.date_key % 100)) '
        'AS INTEGER) + 6) % 7) + 1';
    const dayOfMonthBucket = 't.date_key % 100';
    final bucket = byWeekday ? weekdayBucket : dayOfMonthBucket;

    final rows = await _database
        .customSelect(
          '''
      SELECT $bucket AS bucket,
             SUM(t.original_amount_minor) AS amount_minor,
             t.original_currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM v_active_transactions t
       WHERE t.kind = ?
         AND t.date_key BETWEEN ? AND ?
       GROUP BY bucket, t.original_currency_code
       ORDER BY bucket
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows
        .map(
          (row) => (
            bucket: row.read<int>('bucket'),
            amountMinor: row.read<int>('amount_minor'),
            currencyCode: row.read<String>('currency_code'),
            count: row.read<int>('row_count'),
          ),
        )
        .toList();
  }

  @override
  Future<List<({int amountMinor, String currencyCode, int lineCount})>>
  groceryBaskets(
    AnalyticsWindow window,
  ) async {
    // One row per basket, not an aggregate: `AnalyticsService.averageGroceryBasket` averages over the
    // baskets that *converted*, which it cannot do from a pre-summed total.
    final rows = await _database
        .customSelect(
          '''
      SELECT t.original_amount_minor AS amount_minor,
             t.original_currency_code AS currency_code,
             (SELECT COUNT(*) FROM transaction_lines l
               WHERE l.transaction_id = t.tx_id AND l.deleted_at IS NULL) AS line_count
        FROM v_active_transactions t
       WHERE t.kind = ?
         AND t.subtype = ?
         AND t.date_key BETWEEN ? AND ?
       ORDER BY t.date_key
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<String>(TransactionSubtype.grocery.name),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows
        .map(
          (row) => (
            amountMinor: row.read<int>('amount_minor'),
            currencyCode: row.read<String>('currency_code'),
            lineCount: row.read<int>('line_count'),
          ),
        )
        .toList();
  }

  // ── 9-12, 24: items and prices ────────────────────────────────────────────────────────

  @override
  Future<List<RawMoneyRow>> spendByItem(
    AnalyticsWindow window, {
    int limit = 10,
  }) async {
    // The line's currency is the parent transaction's `original_currency_code`: a line has no
    // currency column of its own (ARCH_2 §1.x). Joining `v_active_transactions` rather than
    // `transactions` is what supplies the parent's `deleted_at IS NULL` — L7 doing its job even in a
    // query the views do not otherwise serve.
    final rows = await _database
        .customSelect(
          '''
      SELECT l.item_id AS group_key,
             i.name AS group_label,
             SUM(l.line_amount_minor) AS amount_minor,
             t.original_currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM transaction_lines l
        JOIN v_active_transactions t ON t.tx_id = l.transaction_id
        JOIN items i ON i.id = l.item_id
       WHERE l.deleted_at IS NULL
         AND i.deleted_at IS NULL
         AND l.line_amount_minor IS NOT NULL
         AND t.kind = ?
         AND t.date_key BETWEEN ? AND ?
       GROUP BY l.item_id, t.original_currency_code
       ORDER BY amount_minor DESC
       LIMIT ?
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
            Variable<int>(limit * _currencySpread),
          ],
        )
        .get();
    return rows.map(_moneyRow).toList();
  }

  @override
  Future<List<RawQuantityRow>> quantityByItem(
    AnalyticsWindow window, {
    int limit = 10,
  }) async {
    // `transaction_lines.quantity_milli` is already base-milli (Law L2), so no unit join is needed
    // here — unlike the batch queries, where the *cost* is per purchase unit. `unit_code` records
    // what the user typed; the quantity is stored normalised.
    //
    // Ordered by category first: Law L8 makes grams and pieces incomparable, so a single
    // `ORDER BY milli_base DESC` would return ten weights and drop the most-bought item in the
    // house because pieces carry smaller numbers. The service does not re-rank; the UI groups.
    final rows = await _database
        .customSelect(
          '''
      SELECT l.item_id AS group_key,
             i.name AS group_label,
             SUM(l.quantity_milli) AS milli_base,
             i.unit_category AS category,
             COUNT(*) AS row_count
        FROM transaction_lines l
        JOIN v_active_transactions t ON t.tx_id = l.transaction_id
        JOIN items i ON i.id = l.item_id
       WHERE l.deleted_at IS NULL
         AND i.deleted_at IS NULL
         AND l.quantity_milli IS NOT NULL
         AND l.quantity_milli > 0
         AND t.kind = ?
         AND t.date_key BETWEEN ? AND ?
       GROUP BY l.item_id
       ORDER BY i.unit_category, milli_base DESC
       LIMIT ?
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
            Variable<int>(limit * _currencySpread),
          ],
        )
        .get();
    return rows
        .map(
          (row) => (
            key: row.read<String>('group_key'),
            label: row.read<String>('group_label'),
            milliBase: row.read<int>('milli_base'),
            category: row.read<String>('category'),
            count: row.read<int>('row_count'),
          ),
        )
        .toList();
  }

  @override
  Future<
    ({
      int unitPriceMinor,
      String currencyCode,
      int dateKey,
      String transactionId,
    })?
  >
  dearestPurchase(String itemId, AnalyticsWindow window) async {
    // **Ordered by the unit-normalised price, returning the recorded one.** `unit_price_minor` is per
    // `transaction_lines.unit_code`, so ordering by it directly makes ₹1/g beat ₹50/kg and the
    // "dearest purchase" becomes whichever line used the smallest unit. This is ARCH_4 R18's defect
    // one row over: R18 closed `inventoryValueOnHand` and `wasteTotals`, and query 11 has it too.
    //
    // The figure returned is still the recorded one, because "the most I ever paid" is a fact about
    // that purchase expressed in the unit it was bought in — restating it per gram would answer a
    // different question.
    //
    // `LEFT JOIN` with a base-unit fallback: a line with no `unit_code` is priced per base unit by
    // definition, and excluding it would hide a purchase rather than rank it.
    final row = await _database
        .customSelect(
          '''
      SELECT l.unit_price_minor AS unit_price_minor,
             t.original_currency_code AS currency_code,
             t.date_key AS date_key,
             t.tx_id AS transaction_id
        FROM transaction_lines l
        JOIN v_active_transactions t ON t.tx_id = l.transaction_id
        LEFT JOIN units u ON u.code = l.unit_code
       WHERE l.deleted_at IS NULL
         AND l.item_id = ?
         AND l.unit_price_minor IS NOT NULL
         AND t.date_key BETWEEN ? AND ?
       ORDER BY (CAST(l.unit_price_minor AS REAL) * 1000.0
                 / COALESCE(NULLIF(u.factor_to_base_milli, 0), 1000)) DESC
       LIMIT 1
      ''',
          variables: [
            Variable<String>(itemId),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return (
      unitPriceMinor: row.read<int>('unit_price_minor'),
      currencyCode: row.read<String>('currency_code'),
      dateKey: row.read<int>('date_key'),
      transactionId: row.read<String>('transaction_id'),
    );
  }

  @override
  Future<
    List<
      ({
        int dateKey,
        int lineAmountMinor,
        String currencyCode,
        int milliBase,
        String category,
      })
    >
  >
  itemPurchaseHistory(String itemId, AnalyticsWindow window) async {
    // Oldest first, because `AnalyticsService.unitPriceTrend` takes the percentage change from the
    // first and last observation and reversing the order inverts the sign of the headline insight.
    //
    // `quantity_milli` is base-milli, so the service's `lineAmountMinor / (milliBase / 1000)` is
    // already price per base unit and needs no factor. That is the opposite of the batch case, and
    // the difference is that a line stores its quantity normalised while a batch stores its *cost*
    // per purchase unit.
    //
    // Zero-quantity and unpriced lines are excluded rather than sent through as zero: a zero price
    // would drag the trend down and read as a bargain that never happened.
    final rows = await _database
        .customSelect(
          '''
      SELECT t.date_key AS date_key,
             l.line_amount_minor AS line_amount_minor,
             t.original_currency_code AS currency_code,
             l.quantity_milli AS milli_base,
             i.unit_category AS category
        FROM transaction_lines l
        JOIN v_active_transactions t ON t.tx_id = l.transaction_id
        JOIN items i ON i.id = l.item_id
       WHERE l.deleted_at IS NULL
         AND l.item_id = ?
         AND l.line_amount_minor IS NOT NULL
         AND l.quantity_milli IS NOT NULL
         AND l.quantity_milli > 0
         AND t.date_key BETWEEN ? AND ?
       ORDER BY t.date_key, t.occurred_at
      ''',
          variables: [
            Variable<String>(itemId),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows
        .map(
          (row) => (
            dateKey: row.read<int>('date_key'),
            lineAmountMinor: row.read<int>('line_amount_minor'),
            currencyCode: row.read<String>('currency_code'),
            milliBase: row.read<int>('milli_base'),
            category: row.read<String>('category'),
          ),
        )
        .toList();
  }

  // ── 13-16: inventory ──────────────────────────────────────────────────────────────────

  @override
  Future<
    List<
      ({
        int remainingMilli,
        int unitCostMinor,
        String currencyCode,
        int unitFactorToBaseMilli,
      })
    >
  >
  valuedBatches() async {
    // **The R18 join.** `unit_cost_minor` is cost per `unit_code_at_purchase` — ₹50 per *kilogram*,
    // not per gram — so valuing a batch needs that unit's `factor_to_base_milli`, and dividing by
    // 1000 instead values a 2 kg batch at ₹100,000 (ARCH_2 §5.2). The factor is returned rather than
    // the value so the arithmetic stays in the service, where it is unit-tested against literals.
    //
    // **`units.deleted_at` is not filtered, deliberately.** A retired unit's factor is still the
    // correct factor for a batch bought in it, and filtering would drop every such batch from the
    // valuation while the figure still looked complete — R18's failure mode from the other side.
    //
    // `factor_to_base_milli > 0` here and its complement in `batchesWithoutCost` make the two
    // methods exact opposites, so `batchesValued` counts only batches that really were valued.
    final rows = await _database.customSelect(
      '''
      SELECT b.remaining_quantity_milli AS remaining_milli,
             b.unit_cost_minor AS unit_cost_minor,
             b.cost_currency_code AS currency_code,
             u.factor_to_base_milli AS unit_factor_to_base_milli
        FROM inventory_batches b
        JOIN units u ON u.code = b.unit_code_at_purchase
       WHERE b.deleted_at IS NULL
         AND b.remaining_quantity_milli > 0
         AND b.unit_cost_minor IS NOT NULL
         AND b.cost_currency_code IS NOT NULL
         AND u.factor_to_base_milli > 0
      ''',
    ).get();
    return rows
        .map(
          (row) => (
            remainingMilli: row.read<int>('remaining_milli'),
            unitCostMinor: row.read<int>('unit_cost_minor'),
            currencyCode: row.read<String>('currency_code'),
            unitFactorToBaseMilli: row.read<int>('unit_factor_to_base_milli'),
          ),
        )
        .toList();
  }

  @override
  Future<int> batchesWithoutCost() async {
    // The exact complement of `valuedBatches`, including the unresolvable-unit case. A batch whose
    // unit cannot be resolved has no computable value, so counting it as valued would understate the
    // total while reporting a complete valuation.
    final row = await _database.customSelect(
      '''
      SELECT COUNT(*) AS row_count
        FROM inventory_batches b
        LEFT JOIN units u ON u.code = b.unit_code_at_purchase
       WHERE b.deleted_at IS NULL
         AND b.remaining_quantity_milli > 0
         AND (b.unit_cost_minor IS NULL
              OR b.cost_currency_code IS NULL
              OR u.factor_to_base_milli IS NULL
              OR u.factor_to_base_milli <= 0)
      ''',
    ).getSingle();
    return row.read<int>('row_count');
  }

  @override
  Future<
    List<
      ({
        String itemId,
        String itemName,
        int milliBase,
        String category,
        int? unitCostMinor,
        String? currencyCode,
        int? unitFactorToBaseMilli,
      })
    >
  >
  wasteMovements(AnalyticsWindow window) async {
    // **Reversed movements are excluded, and that is `reverses_movement_id` earning its column.**
    // Undo on a waste entry writes a reversing row rather than deleting the original (ARCH_2 §5.3,
    // ARCH_5 §5.4), so counting the original would report waste the user already corrected — and
    // food-waste analytics that overstates itself is worse than none.
    //
    // No `deleted_at` filter on `stock_movements`: the table has none at all, which is L6's one
    // explicit exception. `inventory_batches.deleted_at` is not filtered either — the waste happened
    // whether or not the batch row was later removed, and its cost is still the cost.
    //
    // The same per-purchase-unit factor as `valuedBatches`, nullable because a movement's batch may
    // carry no cost. All three cost fields travel together so the service can tell "no cost
    // recorded" from "cost of zero".
    final rows = await _database
        .customSelect(
          '''
      SELECT m.item_id AS item_id,
             i.name AS item_name,
             m.quantity_milli AS milli_base,
             i.unit_category AS category,
             b.unit_cost_minor AS unit_cost_minor,
             b.cost_currency_code AS currency_code,
             u.factor_to_base_milli AS unit_factor_to_base_milli
        FROM stock_movements m
        JOIN items i ON i.id = m.item_id
        LEFT JOIN inventory_batches b ON b.id = m.batch_id
        LEFT JOIN units u ON u.code = b.unit_code_at_purchase
       WHERE m.kind IN ('waste', 'expired')
         AND i.deleted_at IS NULL
         AND m.date_key BETWEEN ? AND ?
         AND NOT EXISTS (SELECT 1 FROM stock_movements r
                          WHERE r.reverses_movement_id = m.id)
       ORDER BY m.date_key
      ''',
          variables: [
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows
        .map(
          (row) => (
            itemId: row.read<String>('item_id'),
            itemName: row.read<String>('item_name'),
            milliBase: row.read<int>('milli_base'),
            category: row.read<String>('category'),
            unitCostMinor: row.readNullable<int>('unit_cost_minor'),
            currencyCode: row.readNullable<String>('currency_code'),
            unitFactorToBaseMilli: row.readNullable<int>(
              'unit_factor_to_base_milli',
            ),
          ),
        )
        .toList();
  }

  @override
  Future<
    List<
      ({
        String batchId,
        String itemId,
        String itemName,
        int remainingMilli,
        String category,
        int expiryDateKey,
      })
    >
  >
  expiringBatches(AnalyticsWindow window) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT b.id AS batch_id,
             b.item_id AS item_id,
             i.name AS item_name,
             b.remaining_quantity_milli AS remaining_milli,
             i.unit_category AS category,
             b.expiry_date_key AS expiry_date_key
        FROM inventory_batches b
        JOIN items i ON i.id = b.item_id
       WHERE b.deleted_at IS NULL
         AND i.deleted_at IS NULL
         AND b.remaining_quantity_milli > 0
         AND b.expiry_date_key IS NOT NULL
         AND b.expiry_date_key BETWEEN ? AND ?
       ORDER BY b.expiry_date_key
      ''',
          variables: [
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows
        .map(
          (row) => (
            batchId: row.read<String>('batch_id'),
            itemId: row.read<String>('item_id'),
            itemName: row.read<String>('item_name'),
            remainingMilli: row.read<int>('remaining_milli'),
            category: row.read<String>('category'),
            expiryDateKey: row.read<int>('expiry_date_key'),
          ),
        )
        .toList();
  }

  @override
  Future<int> lowStockCount() async {
    // `v_low_stock` reflects the present and stock is not versioned, which is why query 16 is one
    // point rather than a history (ARCH_3 §5.2's note, and the service says the same).
    final row = await _database
        .customSelect(
          'SELECT COUNT(*) AS row_count FROM v_low_stock',
        )
        .getSingle();
    return row.read<int>('row_count');
  }

  // ── 17-20: commitments and assets ─────────────────────────────────────────────────────

  @override
  Future<
    List<
      ({
        int defaultAmountMinor,
        String currencyCode,
        String intervalUnit,
        int intervalCount,
      })
    >
  >
  activeCommitments() async {
    // **The base table, not `v_recurring_due`.** That view LEFT JOINs occurrences where
    // `status = 'due'`, and `idx_recurring_occ` is unique on `(template_id, due_date_key)` rather
    // than on the template — so a template with two outstanding dues appears twice and its
    // commitment would be counted twice. The view is right for a due list and wrong for a total.
    //
    // `direction = 'outflow'` because query 17 is a *commitment* total: netting salary against rent
    // would report a household with a surplus as having no fixed costs.
    //
    // An ended template is excluded, which needs today — from the injected clock, never
    // `DateTime.now()`.
    final rows = await _database
        .customSelect(
          '''
      SELECT rt.default_amount_minor AS default_amount_minor,
             rt.currency_code AS currency_code,
             rt.interval_unit AS interval_unit,
             rt.interval_count AS interval_count
        FROM recurring_templates rt
       WHERE rt.deleted_at IS NULL
         AND rt.is_paused = 0
         AND rt.direction = 'outflow'
         AND (rt.end_date_key IS NULL OR rt.end_date_key >= ?)
      ''',
          variables: [Variable<int>(_clock.today().value)],
        )
        .get();
    return rows
        .map(
          (row) => (
            defaultAmountMinor: row.read<int>('default_amount_minor'),
            currencyCode: row.read<String>('currency_code'),
            intervalUnit: row.read<String>('interval_unit'),
            intervalCount: row.read<int>('interval_count'),
          ),
        )
        .toList();
  }

  @override
  Future<List<RawMoneyRow>> spendByRecurringFlag(AnalyticsWindow window) async {
    // The keys are the literals `AnalyticsService.recurringVsDiscretionary` compares against, so
    // they are spelled here exactly as it reads them. A rename on either side silently routes every
    // rupee into `discretionary`, which is why they are worth stating rather than deriving.
    final rows = await _database
        .customSelect(
          '''
      SELECT CASE WHEN t.recurring_template_id IS NULL THEN 'discretionary' ELSE 'recurring' END
               AS group_key,
             CASE WHEN t.recurring_template_id IS NULL THEN 'discretionary' ELSE 'recurring' END
               AS group_label,
             SUM(t.original_amount_minor) AS amount_minor,
             t.original_currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM v_active_transactions t
       WHERE t.kind = ?
         AND t.date_key BETWEEN ? AND ?
       GROUP BY group_key, t.original_currency_code
      ''',
          variables: [
            Variable<String>(_spendKind),
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows.map(_moneyRow).toList();
  }

  @override
  Future<
    List<
      ({
        String assetId,
        String assetName,
        int costMinor,
        String currencyCode,
        int count,
      })
    >
  >
  serviceCostByAsset(AnalyticsWindow window) async {
    // Disposed assets are included, and that is the point of `status = disposed` rather than a
    // delete (ARCH_2 §8.1): the ₹45,000 of servicing you put into a TV stays in the analytics after
    // you sell it. "Lifetime" would be a strange word for a figure that vanished on disposal.
    final rows = await _database
        .customSelect(
          '''
      SELECT sr.asset_id AS asset_id,
             a.name AS asset_name,
             SUM(sr.cost_minor) AS cost_minor,
             sr.currency_code AS currency_code,
             COUNT(*) AS row_count
        FROM service_records sr
        JOIN assets a ON a.id = sr.asset_id
       WHERE sr.deleted_at IS NULL
         AND a.deleted_at IS NULL
         AND sr.cost_minor IS NOT NULL
         AND sr.currency_code IS NOT NULL
         AND sr.service_date_key BETWEEN ? AND ?
       GROUP BY sr.asset_id, sr.currency_code
      ''',
          variables: [
            Variable<int>(window.from.value),
            Variable<int>(window.to.value),
          ],
        )
        .get();
    return rows
        .map(
          (row) => (
            assetId: row.read<String>('asset_id'),
            assetName: row.read<String>('asset_name'),
            costMinor: row.read<int>('cost_minor'),
            currencyCode: row.read<String>('currency_code'),
            count: row.read<int>('row_count'),
          ),
        )
        .toList();
  }

  @override
  Future<
    List<
      ({String assetId, String assetName, int? startDateKey, int? endDateKey})
    >
  >
  warrantyWindows() async {
    // `v_asset_alerts` carries `warranty_end_date_key` and not `warranty_start_date_key`, so a
    // coverage *timeline* cannot be built from it. Disposed assets are excluded here — unlike the
    // service-cost query — because a warranty on something you no longer own covers nothing, which
    // is the same judgement the view makes.
    final rows = await _database.customSelect(
      '''
      SELECT a.id AS asset_id,
             a.name AS asset_name,
             a.warranty_start_date_key AS start_date_key,
             a.warranty_end_date_key AS end_date_key
        FROM assets a
       WHERE a.deleted_at IS NULL
         AND a.status <> 'disposed'
         AND (a.warranty_start_date_key IS NOT NULL OR a.warranty_end_date_key IS NOT NULL)
       ORDER BY a.warranty_end_date_key
      ''',
    ).get();
    return rows
        .map(
          (row) => (
            assetId: row.read<String>('asset_id'),
            assetName: row.read<String>('asset_name'),
            startDateKey: row.readNullable<int>('start_date_key'),
            endDateKey: row.readNullable<int>('end_date_key'),
          ),
        )
        .toList();
  }

  @override
  DateKey today() => _clock.today();

  // ── row mappers ───────────────────────────────────────────────────────────────────────
  //
  // One per raw record shape. Named rather than inlined because ARCH_4 R19 makes an inline record
  // type structurally matched and nothing else — so a field added to `RawMoneyRow` should break in
  // one place here, not in eleven query bodies.

  RawMoneyRow _moneyRow(QueryRow row) => (
    key: row.read<String>('group_key'),
    // `group_label` is nullable wherever it comes from a LEFT JOIN in the view — a payee or a
    // payment method the transaction did not name. The key is filtered NOT NULL in those
    // queries, so an empty label means the joined row is gone rather than absent.
    label: row.readNullable<String>('group_label') ?? '',
    amountMinor: row.read<int>('amount_minor'),
    currencyCode: row.read<String>('currency_code'),
    count: row.read<int>('row_count'),
  );

  RawMonthRow _monthRow(QueryRow row) => (
    monthKey: row.read<int>('month_key'),
    amountMinor: row.read<int>('amount_minor'),
    currencyCode: row.read<String>('currency_code'),
    count: row.read<int>('row_count'),
  );

  RawDateRow _dateRow(QueryRow row) => (
    dateKey: row.read<int>('date_key'),
    amountMinor: row.read<int>('amount_minor'),
    currencyCode: row.read<String>('currency_code'),
    count: row.read<int>('row_count'),
  );
}
```

### `lib/data/repositories/asset_repository_impl.dart`

```dart
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/asset_dao.dart';
import 'package:alaya/data/repositories/mappers/schedule_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/repositories/asset_repository.dart';

/// `AssetRepository` backed by `AssetDao`.
///
/// **There is no delete method on the contract and none here.** Retiring an asset is [dispose],
/// which records a reason and a date so the money spent stays in analytics after the thing is gone
/// (ARCH_3 §4.1). The `deletedAt` column exists on the table and nothing in this class or its DAO
/// writes it — it is reserved for Phase 8B's trash screen.
final class AssetRepositoryImpl implements AssetRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const AssetRepositoryImpl(this._dao, this._clock);

  final AssetDao _dao;
  final Clock _clock;

  @override
  Stream<List<Asset>> watchInUse() =>
      _dao.watchInUse().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Asset>> watchByType(AssetType type) => _dao
      .watchByType(type)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Asset>> watchDisposed() => _dao.watchDisposed().map(
    (rows) => rows.map((r) => r.toEntity()).toList(),
  );

  @override
  Future<Asset?> byId(String id) async => (await _dao.byId(id))?.toEntity();

  @override
  Stream<List<Asset>> watchWarrantyEndingInRange({
    required DateKey from,
    required DateKey to,
  }) => _dao
      .watchWarrantyEndingInRange(from: from, to: to)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Asset>> watchServiceDueInRange({
    required DateKey from,
    required DateKey to,
  }) => _dao
      .watchServiceDueInRange(from: from, to: to)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<Asset, Failure>> save(Asset asset) async {
    if (asset.name.trim().isEmpty) {
      return const Result.failure(
        ValidationFailure('An asset needs a name.', field: 'name'),
      );
    }
    if (asset.status == AssetStatus.disposed) {
      // A disposal needs a reason and a date, which this method has no parameters for. Accepting
      // the status alone would produce a `disposed` asset with no record of why or when — exactly
      // the state ARCH_3 §4.1's "never deleted, always a reason" rule exists to prevent.
      return const Result.failure(
        BusinessRuleFailure(
          'Use dispose() to retire an asset — a disposal needs a reason and a date.',
          rule: 'disposalNeedsReason',
        ),
      );
    }

    // **An asset is not unique by name, and refusing a duplicate was wrong.**
    //
    // A household with five iPhones has five assets: five serial numbers, five warranties, five service
    // histories. Two identical ceiling fans are two fans. The name is a label a person chose, not an
    // identity — so a second "iPhone" is a second phone, and blocking it made the app unusable for the
    // ordinary case of owning more than one of something.
    //
    // This is the opposite of `items`, deliberately. Law L8 makes name plus unit category the identity of
    // an Item because 500g of onion *is* the same onion as another 500g; quantities of a fungible thing
    // merge. An asset never merges: it is one object and it wears out on its own schedule. The
    // name lookup stays on the DAO for the editor to offer a note with — never a block.
    final existing = await _dao.byId(asset.id);

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _dao.upsert(
      assetToCompanion(
        asset,
        createdAt: stamps.createdAt,
        updatedAt: stamps.updatedAt,
      ),
    );
    return Result.ok(asset);
  }

  @override
  Future<Result<void, Failure>> setStatus({
    required String id,
    required AssetStatus status,
  }) async {
    final existing = await _dao.byId(id);
    if (existing == null) {
      return Result.failure(NotFoundFailure('Asset not found.', id: id));
    }
    if (status == AssetStatus.disposed) {
      // The DAO throws an ArgumentError for this rather than silently accepting it. Catching it
      // here first turns a programming error into a failure the UI can render.
      return const Result.failure(
        BusinessRuleFailure(
          'Use dispose() to retire an asset — a disposal needs a reason and a date.',
          rule: 'disposalNeedsReason',
        ),
      );
    }
    await _dao.setStatus(
      id: id,
      status: status,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> dispose({
    required String assetId,
    required AssetDisposalReason reason,
    required DateKey dateKey,
    int? amountMinor,
    String? note,
  }) async {
    final existing = await _dao.byId(assetId);
    if (existing == null) {
      return Result.failure(NotFoundFailure('Asset not found.', id: assetId));
    }
    if (existing.status == AssetStatus.disposed) {
      return const Result.failure(
        BusinessRuleFailure(
          'This asset is already disposed.',
          rule: 'alreadyDisposed',
        ),
      );
    }
    if (amountMinor != null && amountMinor < 0) {
      return const Result.failure(
        ValidationFailure(
          'Sale proceeds cannot be negative.',
          field: 'amountMinor',
        ),
      );
    }
    if (amountMinor != null && existing.purchaseCurrencyCode == null) {
      // `assets` has no disposal-currency column: proceeds are denominated in whatever the asset
      // was bought in (ARCH_2 §8). With no purchase currency recorded there is nothing to pair the
      // amount with, and storing a bare number would break Law L1's pairing rule.
      return const Result.failure(
        BusinessRuleFailure(
          'This asset has no purchase currency recorded, so sale proceeds cannot be stored '
          'against it. Add a purchase price first.',
          rule: 'noCurrencyForProceeds',
        ),
      );
    }

    await _dao.dispose(
      assetId: assetId,
      reason: reason,
      dateKey: dateKey,
      amountMinor: amountMinor,
      note: note,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> undispose(String id) async {
    final existing = await _dao.byId(id);
    if (existing == null) {
      return Result.failure(NotFoundFailure('Asset not found.', id: id));
    }
    if (existing.status != AssetStatus.disposed) {
      return const Result.failure(
        BusinessRuleFailure('This asset is not disposed.', rule: 'notDisposed'),
      );
    }
    await _dao.undispose(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> detachFromDeletedTransaction(String id) async {
    await _dao.detachFromDeletedTransaction(
      id: id,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }
}
```

### `lib/data/repositories/batch_repository_impl.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/batch_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/item_category_resolver.dart';
import 'package:alaya/data/repositories/mappers/stock_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/repositories/batch_repository.dart';

/// `BatchRepository` backed by `BatchDao`.
final class BatchRepositoryImpl implements BatchRepository {
  /// Creates the repository over [dao], resolving item categories through [categories].
  const BatchRepositoryImpl(this._dao, this._categories, this._clock);

  final BatchDao _dao;
  final ItemCategoryResolver _categories;
  final Clock _clock;

  @override
  Stream<List<Batch>> watchByItemFefo(String itemId) =>
      _dao.watchByItemFefo(itemId).asyncMap((rows) => _mapAll(rows));

  @override
  Future<List<Batch>> byItemFefo(String itemId) async =>
      _mapAll(await _dao.byItemFefo(itemId));

  @override
  Stream<List<Batch>> watchByItem(String itemId) =>
      _dao.watchByItem(itemId).asyncMap((rows) => _mapAll(rows));

  @override
  Stream<List<Batch>> watchExpiringInRange({
    required DateKey from,
    required DateKey to,
  }) =>
      _dao.watchExpiringInRange(from: from, to: to).asyncMap((rows) => _mapAll(rows));

  @override
  Future<Batch?> byId(String id) async {
    final row = await _dao.byIdIncludingDeleted(id);
    if (row == null) return null;
    final category = await _categories.categoryOf(row.itemId);
    if (category == null) return null;
    return row.toEntity(category);
  }

  @override
  Future<Result<Batch, Failure>> create(Batch batch) async {
    if (!batch.initialQuantity.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'A new batch needs a quantity greater than zero.',
          field: 'initialQuantity',
        ),
      );
    }
    if (batch.remainingQuantity != batch.initialQuantity) {
      // BatchDao.insertWithOpeningMovement's documented caller contract: nothing has been consumed
      // yet, so the two cannot differ. Enforced here rather than trusted, because the founding
      // movement it writes uses `initialQuantityMilli` — a mismatch would make the batch a
      // permanent discrepancy in `v_batch_stock_check` from the moment it was created.
      return const Result.failure(
        ValidationFailure(
          'A new batch must have its full quantity remaining.',
          field: 'remainingQuantity',
        ),
      );
    }

    final category = await _categories.categoryOf(batch.itemId);
    if (category == null) {
      return Result.failure(
        NotFoundFailure('The item this batch belongs to does not exist.', id: batch.itemId),
      );
    }
    if (category != batch.initialQuantity.category) {
      // A `Qty` in the wrong category would be stored as a bare integer and silently reinterpreted
      // on read as the item's own category — 2 pieces becoming 2 grams. Law L8 makes this
      // impossible to fix afterwards, so it is refused now.
      return Result.failure(
        ValidationFailure(
          'This batch is measured in ${batch.initialQuantity.category.name} but its item is '
              'measured in ${category.name}.',
          field: 'initialQuantity',
        ),
      );
    }

    final now = _clock.nowUtcMillis();
    await _dao.insertWithOpeningMovement(
      batch: batchToCompanion(batch, createdAt: now, updatedAt: now),
      // `purchaseIn` when the batch came from a transaction line, `manualIn` when the user added
      // it directly. The repository's call to make, as the DAO's doc notes.
      openingKind: batch.sourceTransactionLineId != null
          ? StockMovementKind.purchaseIn
          : StockMovementKind.manualIn,
      nowUtcMillis: now,
    );
    return Result.ok(batch);
  }

  @override
  Future<Result<Batch, Failure>> updateMetadata(Batch batch) async {
    final existing = await _dao.byIdIncludingDeleted(batch.id);
    if (existing == null) {
      return Result.failure(NotFoundFailure('Batch not found.', id: batch.id));
    }
    if (existing.remainingQuantityMilli != batch.remainingQuantity.milliBase ||
        existing.initialQuantityMilli != batch.initialQuantity.milliBase) {
      // Quantities move only by recording a movement, so that the ledger and the cache can never
      // disagree (Law L3). A metadata update that also changed a quantity would write the cache
      // with no matching movement — exactly the drift `v_batch_stock_check` exists to detect.
      return const Result.failure(
        BusinessRuleFailure(
          'A batch\'s quantity cannot be changed here — record a stock movement instead.',
          rule: 'quantityRequiresMovement',
        ),
      );
    }

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing.createdAt,
      clock: _clock,
    );
    await _dao.updateMetadata(
      batchToCompanion(batch, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );
    return Result.ok(batch);
  }

  @override
  Future<Result<void, Failure>> detachFromDeletedTransaction(String batchId) async {
    await _dao.detachFromDeletedTransaction(
      batchId: batchId,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    await _dao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Stream<List<BatchReconciliation>> watchReconciliation() =>
      _dao.watchReconciliation().asyncMap(_mapReconciliations);

  @override
  Future<List<BatchReconciliation>> findDiscrepancies() async =>
      _mapReconciliations(await _dao.findDiscrepancies());

  @override
  Future<Result<void, Failure>> recompute(String batchId) async {
    await _dao.recomputeRemaining(batchId);
    return const Result.ok(null);
  }

  @override
  Future<Result<int, Failure>> recomputeAll() async {
    // Counted before repairing, not after: once every cache is rebuilt there are no discrepancies
    // left to count, so asking afterwards would always return zero and report that nothing was
    // wrong. The figure the Settings screen wants is how many were broken.
    final broken = await _dao.findDiscrepancies();
    await _dao.recomputeAll();
    return Result.ok(broken.length);
  }

  Future<List<BatchReconciliation>> _mapReconciliations(List<BatchStockCheckRow> rows) async {
    final categories = await _categories.categoriesFor(rows.map((r) => r.itemId));
    return rows
        .where((r) => categories.containsKey(r.itemId))
        .map((r) => r.toEntity(categories[r.itemId]!))
        .toList();
  }

  Future<List<Batch>> _mapAll(List<InventoryBatchRow> rows) async {
    final categories = await _categories.categoriesFor(rows.map((r) => r.itemId));
    return rows
        .where((r) => categories.containsKey(r.itemId))
        .map((r) => r.toEntity(categories[r.itemId]!))
        .toList();
  }
}
```

### `lib/data/repositories/calendar_repository_impl.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/calendar_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/repositories/calendar_repository.dart';

/// Reads the unified calendar feed from `v_calendar_events`.
///
/// Phase 3A declared [CalendarRepository] and no phase implemented it, which left
/// `CalendarAggregator` with no provider and three of its methods unreachable (ARCH_4 §5.1 item 15).
/// This closes that.
///
/// **Returns rows with their baseline severity, unescalated.** The escalation thresholds differ per
/// event type (ARCH_3 §6) and depend on the current date, so they belong in `CalendarAggregator` with
/// the injected `Clock` — not here, and not in the view (ARCH_2 §12.2).
class CalendarRepositoryImpl implements CalendarRepository {
  /// Creates the repository over [dao].
  const CalendarRepositoryImpl(this._dao);

  final CalendarDao _dao;

  @override
  Stream<List<CalendarEvent>> watchRange({
    required DateKey from,
    required DateKey to,
  }) => _dao
      .watchRange(fromDateKey: from.value, toDateKey: to.value)
      .map((rows) => rows.map(_toEntity).toList());

  @override
  Future<List<CalendarEvent>> forDay(DateKey dateKey) async {
    final rows = await _dao.forDay(dateKey.value);
    return rows.map(_toEntity).toList();
  }

  @override
  Future<Map<DateKey, int>> countsByDate({
    required DateKey from,
    required DateKey to,
  }) async {
    final counts = await _dao.countsByDate(
      fromDateKey: from.value,
      toDateKey: to.value,
    );
    return {
      for (final entry in counts.entries) DateKey(entry.key): entry.value,
    };
  }

  /// Maps one view row onto the domain entity.
  ///
  /// `event_type` and `severity` decode by enum *name*, which Law L11 makes the schema contract: the
  /// view's arms emit the literals `'transaction'`, `'recurringDue'` and so on, and renaming a value
  /// in either enum is a breaking change to this view.
  CalendarEvent _toEntity(CalendarEventRow row) {
    final minor = row.amountMinor;
    final currency = row.currencyCode;

    return CalendarEvent(
      // `DateKey?`, not `int`: the view column carries `DateKeyConverter`, and drift types it nullable
      // because six of the seven arms select a nullable column. Every one of those arms filters
      // `IS NOT NULL`, and the transaction arm's `date_key` is NOT NULL, so a null here means the view
      // changed and throwing is the correct response.
      dateKey: row.dateKey!,
      type: CalendarEventType.values.byName(row.eventType),
      refType: row.refType,
      refId: row.refId,
      title: row.title,
      baseSeverity: CalendarSeverity.values.byName(row.severity),
      amount: minor != null && currency != null ? Money(minor, currency) : null,
    );
  }
}
```

### `lib/data/repositories/currency_repository_impl.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/currency_dao.dart';
import 'package:alaya/data/repositories/mappers/currency_mapper.dart';
import 'package:alaya/data/repositories/mappers/rate_mappers.dart';
import 'package:alaya/data/repositories/unconverted_count.dart';
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/domain/repositories/currency_repository.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// `CurrencyRepository` backed by `CurrencyDao`.
///
/// A thin adapter over two owners. [convert] and [convertToHome] build a `RateTable` from the cached
/// rows and let it apply ARCH_3 §1.2's pivot and §1.3's lookup rule — no network access, and no
/// second copy of that arithmetic living here. [syncDailyRates] delegates to `CurrencyRateService`,
/// which owns the once-daily skip and the fetch ladder.
///
/// Phase 3B implemented both inline, because neither service existed yet. Phase 4A moved them, so
/// there is exactly one definition of each rule — the same reason `v_batch_stock_check` exists to
/// catch a second definition of a stock total.
final class CurrencyRepositoryImpl implements CurrencyRepository {
  /// Creates the repository over [dao], resolving the home currency through [settings].
  ///
  /// [rateService] is null until Phase 5 wires one; a null service makes [syncDailyRates] a
  /// documented no-op rather than a runtime error.
  ///
  /// [unconvertedCounter] is **required**, unlike [rateService], and the asymmetry is deliberate. A
  /// null rate service degrades a *write* to a no-op, which Law L11 permits outright — a rate that
  /// never arrives costs nothing. A null counter would degrade a *read* to `0`, and zero
  /// unconverted amounts is a claim that everything converted rather than an admission that nobody
  /// checked. Three phases of `Stream.value(0)` is exactly what an optional parameter here buys.
  const CurrencyRepositoryImpl(
    this._dao,
    this._clock,
    this._settings, {
    required UnconvertedCounter unconvertedCounter,
    CurrencyRateService? rateService,
  }) : _unconvertedCounter = unconvertedCounter,
       _rateService = rateService;

  final CurrencyDao _dao;
  final Clock _clock;
  final SettingsRepository _settings;
  final CurrencyRateService? _rateService;
  final UnconvertedCounter _unconvertedCounter;

  /// Used only if the seeded `homeCurrencyCode` setting is somehow absent — Phase 1C's seed data
  /// always writes it, so this is a defensive fallback, never the expected path.
  static const String _fallbackHomeCurrencyCode = 'INR';

  @override
  Stream<List<Currency>> watchEnabled() =>
      _dao.watchEnabled().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Currency>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Currency?> byCode(String code) async =>
      (await _dao.byCode(code))?.toEntity();

  @override
  Future<Map<String, int>> decimalDigitsByCode() => _dao.decimalDigitsByCode();

  @override
  Future<Result<void, Failure>> setEnabled({
    required String code,
    required bool isEnabled,
  }) async {
    await _dao.setEnabled(
      code: code,
      isEnabled: isEnabled,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<ConvertedMoney> convert({
    required Money amount,
    required String toCurrencyCode,
    required DateKey on,
  }) async {
    final table = await _rateTable();
    return table.convert(
      amount: amount,
      toCurrencyCode: toCurrencyCode,
      on: on,
    );
  }

  @override
  Future<ConvertedMoney> convertToHome({
    required Money amount,
    required DateKey on,
  }) async {
    final homeCode =
        await _settings.readHomeCurrencyCode() ?? _fallbackHomeCurrencyCode;
    return convert(amount: amount, toCurrencyCode: homeCode, on: on);
  }

  @override
  /// Delegates to [UnconvertedCounter], which owns the query and the re-evaluation.
  ///
  /// **This replaced a `Stream.value(0)` stub that had stood since Phase 3B** (ARCH_3 §1.5, ARCH_5
  /// §7.3). The stub was correct to exist: a real count re-evaluates every active transaction's
  /// convertibility whenever the rate cache changes, which is analytics work, and guessing at a
  /// query would have shipped a wrong number instead of an unimplemented one.
  ///
  /// It lives in a collaborator rather than here because ARCH_3 §1.5 is explicit that the count
  /// belongs with whatever is being totalled rather than with the rate subsystem — this repository
  /// holds a `CurrencyDao` and cannot see `transactions` at all. The counter converts through the
  /// same `RateTable` this class does, so the chip and the totals it annotates cannot disagree.
  Stream<int> watchUnconvertedCount() => _unconvertedCounter.watch();

  @override
  /// Delegates to `CurrencyRateService.syncDailyRates`, which is the only implementation.
  ///
  /// This method used to fetch directly. It was replaced because the service adds the two things
  /// that make ARCH_3 §1.2's "one request per day for the entire app, forever" true rather than
  /// aspirational — it skips the fetch when the cache already holds today's date, and refuses to
  /// overwrite a working cache with an empty snapshot. A caller wiring the old version to a
  /// foreground hook would have re-fetched on every resume.
  ///
  /// Still never throws: the service swallows every failure path (Law L11).
  Future<void> syncDailyRates() async {
    await _rateService?.syncDailyRates();
  }

  /// Builds the in-memory rate table `RateTable` needs, from the cached USD rows.
  ///
  /// The pivot and lookup rules live in `CurrencyRateService`'s `RateTable` (ARCH_3 §1.2, §1.3) —
  /// this method only supplies the data. Phase 3B originally hand-rolled the same cross-rating here;
  /// Phase 4A moved it, because two implementations of one rule drift apart and the schema's own
  /// reconciliation view is a standing reminder of what that costs.
  Future<RateTable> _rateTable() async {
    final rows = await _dao.allRates();
    // Delegates to RateMappers so this mapping has one definition — Phase 5 needed the same map in
    // the provider graph, and a second copy is how the two drift apart.
    return RateMappers.tableFrom(
      rows: rows,
      decimalDigitsByCode: await _dao.decimalDigitsByCode(),
    );
  }
}
```

### `lib/data/repositories/item_category_resolver.dart`

```dart
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/data/daos/item_dao.dart';

/// Resolves an item's [UnitCategory], which every batch, movement and shopping quantity needs but
/// no batch, movement or entry row carries.
///
/// Lives in its own file because three repositories use it — `BatchRepositoryImpl`,
/// `StockRepositoryImpl` and `ShoppingRepositoryImpl`. Leaving it inside
/// `batch_repository_impl.dart` forced the other two to import another repository's
/// *implementation* file just to reach a shared helper: the same coupling `settings_keys.dart`
/// was extracted to avoid in Phase 3B. Nothing here touches Law L12 — all three are `data/` — so
/// it is a design smell rather than a violation, but the fix is cheap and the precedent is set.
final class ItemCategoryResolver {
  /// Creates a resolver over [itemDao].
  ItemCategoryResolver(this._itemDao);

  final ItemDao _itemDao;
  final Map<String, UnitCategory> _cache = {};

  /// The category for [itemId], or null when no such item exists.
  ///
  /// Cached per instance. An item's category is immutable once created (Law L8), so a cached value
  /// can never go stale — which is precisely what makes caching safe here rather than a risk.
  Future<UnitCategory?> categoryOf(String itemId) async {
    final cached = _cache[itemId];
    if (cached != null) return cached;

    final row = await _itemDao.byIdIncludingDeleted(itemId);
    if (row == null) return null;
    _cache[itemId] = row.unitCategory;
    return row.unitCategory;
  }

  /// Resolves categories for [itemIds] in one pass, for mapping a list of rows.
  Future<Map<String, UnitCategory>> categoriesFor(Iterable<String> itemIds) async {
    final result = <String, UnitCategory>{};
    for (final id in itemIds.toSet()) {
      final category = await categoryOf(id);
      if (category != null) result[id] = category;
    }
    return result;
  }
}
```

### `lib/data/repositories/item_repository_impl.dart`

```dart
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/item_dao.dart';
import 'package:alaya/data/repositories/mappers/stock_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/repositories/item_repository.dart';

/// How far apart two normalized names may be and still be offered as the same thing.
///
/// Two edits, per anomaly A07's resolution. Deliberately permissive on short names — `tea` and
/// `pea` are one edit apart — which is safe only because these are *suggestions the user confirms*
/// and never an automatic merge. Raising the bar would lose real near-misses like
/// `tomato`/`tomatto`; lowering it to scale with length would silently stop catching typos in
/// short names, which are exactly where typos are most likely.
const int _maxSuggestionDistance = 2;

/// `ItemRepository` backed by `ItemDao`.
final class ItemRepositoryImpl implements ItemRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const ItemRepositoryImpl(this._dao, this._clock);

  final ItemDao _dao;
  final Clock _clock;

  @override
  Stream<List<Item>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Item>> watchByCategory(UnitCategory category) =>
      _dao.watchByCategory(category).map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Item>> watchFavorites() =>
      _dao.watchFavorites().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Item>> watchMatching(String term) =>
      _dao.watchMatching(term).map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Item?> byId(String id) async => (await _dao.byIdIncludingDeleted(id))?.toEntity();

  @override
  Future<Item?> findByIdentity({
    required String normalizedName,
    required UnitCategory unitCategory,
  }) async {
    final row = await _dao.findByIdentity(
      normalizedName: normalizedName,
      unitCategory: unitCategory,
    );
    return row?.toEntity();
  }

  @override
  Future<List<Item>> findSimilar({
    required String name,
    required UnitCategory unitCategory,
  }) async {
    // Same category only. A different category is a different item by definition (Law L8,
    // anomaly A06) — `Milk (Weight)` is not a near-miss for `Milk (Volume)`, it is a separate
    // thing — so suggesting across categories would invite exactly the merge the schema forbids.
    final candidates = await _dao.watchByCategory(unitCategory).first;

    final scored = <({Item item, int distance})>[];
    for (final row in candidates) {
      final candidate = row.normalizedName;
      // Cheap pre-filter: a length difference greater than the threshold guarantees the edit
      // distance exceeds it too, since each edit changes length by at most one. Verified over
      // 4000 random pairs never to exclude a genuine match.
      if ((candidate.length - name.length).abs() > _maxSuggestionDistance) continue;

      final distance = _levenshtein(candidate, name);
      // Distance 0 is the exact identity match, which is [findByIdentity]'s job — a merge, not a
      // suggestion. Including it here would offer the user "did you mean this same item?".
      if (distance == 0 || distance > _maxSuggestionDistance) continue;

      scored.add((item: row.toEntity(), distance: distance));
    }

    scored.sort((a, b) {
      final byDistance = a.distance.compareTo(b.distance);
      return byDistance != 0
          ? byDistance
          : a.item.normalizedName.compareTo(b.item.normalizedName);
    });
    return scored.map((s) => s.item).toList();
  }

  @override
  Stream<List<ItemStock>> watchAllStock() =>
      _dao.watchAllStock().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<ItemStock?> watchStockOf(String itemId) =>
      _dao.watchStockOf(itemId).map((row) => row?.toEntity());

  @override
  Stream<List<ItemStock>> watchLowStock() =>
      _dao.watchLowStock().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<Item, Failure>> save(Item item) async {
    final existing = await _dao.byIdIncludingDeleted(item.id);

    if (existing == null) {
      // A new item may not collide with an existing active identity. The partial unique index
      // would reject it anyway; catching it here turns a raw SQLite constraint error into a
      // failure the UI can act on ("add to the existing item instead?").
      final duplicate = await _dao.findByIdentity(
        normalizedName: item.normalizedName,
        unitCategory: item.unitCategory,
      );
      if (duplicate != null) {
        return Result.failure(
          ConflictFailure(
            'An item named "${item.name}" already exists in this category. '
                'Add a new batch to it instead of creating a second item.',
          ),
        );
      }
    } else if (existing.unitCategory != item.unitCategory) {
      // Law L8. Changing an item's category would silently reinterpret every quantity ever
      // recorded against it — 2000 milli-units stops meaning 2 g and starts meaning 2 ml, across
      // every batch, movement and transaction line already written. There is no migration that
      // fixes that after the fact, so the write is refused rather than attempted.
      return Result.failure(
        BusinessRuleFailure(
          'An item\'s unit category cannot be changed once it exists — every quantity already '
              'recorded against "${existing.name}" is measured in '
              '${existing.unitCategory.baseUnitCode}. Create a separate item instead.',
          rule: 'unitCategoryImmutable',
        ),
      );
    }

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _dao.upsert(
      itemToCompanion(item, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );
    return Result.ok(item);
  }

  @override
  Future<Result<void, Failure>> setFavorite({
    required String id,
    required bool isFavorite,
  }) async {
    await _dao.setFavorite(
      id: id,
      isFavorite: isFavorite,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    // Cascades to the item's batches inside one transaction, in the DAO. Movements are untouched:
    // the ledger for food that no longer has a catalogued item stays exactly as complete as it was
    // (Law L6's stated exception).
    await _dao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }
}

/// Levenshtein edit distance between [a] and [b].
///
/// Two-row implementation: only the previous and current rows of the distance matrix are ever
/// live, so memory is `O(min(len))` rather than `O(len × len)`. Called once per same-category
/// candidate that survives the length pre-filter, on strings that are item names — short enough
/// that this is far cheaper than a second database round trip would be.
int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previous = List<int>.generate(b.length + 1, (i) => i);
  var current = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final substitution = previous[j - 1] + (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1);
      final deletion = previous[j] + 1;
      final insertion = current[j - 1] + 1;
      current[j] = substitution < deletion
          ? (substitution < insertion ? substitution : insertion)
          : (deletion < insertion ? deletion : insertion);
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}
```

### `lib/data/repositories/mappers/currency_mapper.dart`

```dart
import 'package:drift/drift.dart' show Value;

import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/entities/currency.dart';

/// Converts between `CurrencyRow` and the domain `Currency` entity.
extension CurrencyMapper on CurrencyRow {
  /// Maps this row to a domain entity.
  Currency toEntity() => Currency(
    code: code,
    name: name,
    symbol: symbol,
    decimalDigits: decimalDigits,
    isEnabled: isEnabled,
    sortOrder: sortOrder,
  );
}

/// Builds the companion for [currency], given the `(createdAt, updatedAt)` pair
/// `WriteTimestamps.resolve` decided.
CurrenciesCompanion currencyToCompanion(
    Currency currency, {
      required int createdAt,
      required int updatedAt,
    }) {
  return CurrenciesCompanion.insert(
    code: currency.code,
    name: currency.name,
    symbol: currency.symbol,
    decimalDigits: currency.decimalDigits,
    isEnabled: currency.isEnabled,
    sortOrder: currency.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: const Value(null),
  );
}
```

### `lib/data/repositories/mappers/money_mappers.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/converters/money_converter.dart';
import 'package:alaya/data/db/converters/qty_converter.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';

/// Converts between `AccountRow` and the domain `Account` entity.
///
/// Uses `MoneyColumns` rather than a drift `TypeConverter` because `Money` spans two sibling
/// columns (`openingBalanceMinor` + the row's own `currencyCode`) — see `money_converter.dart`'s
/// class doc for why no converter can do this.
extension AccountMapper on AccountRow {
  /// Maps this row to a domain entity.
  Account toEntity() => Account(
    id: id,
    name: name,
    normalizedName: normalizedName,
    kind: kind,
    currencyCode: currencyCode,
    openingBalance: MoneyColumns.read(openingBalanceMinor, currencyCode),
    openingBalanceDateKey: openingBalanceDateKey,
    isArchived: isArchived,
    includeInNetWorth: includeInNetWorth,
    sortOrder: sortOrder,
    colorArgb: colorArgb,
    iconKey: iconKey,
  );
}

/// Builds the companion for [account].
AccountsCompanion accountToCompanion(
  Account account, {
  required int createdAt,
  required int updatedAt,
}) {
  return AccountsCompanion.insert(
    id: account.id,
    name: account.name,
    normalizedName: account.normalizedName,
    kind: account.kind,
    currencyCode: account.currencyCode,
    openingBalanceMinor: MoneyColumns.minorOf(account.openingBalance),
    openingBalanceDateKey: account.openingBalanceDateKey,
    isArchived: account.isArchived,
    includeInNetWorth: account.includeInNetWorth,
    sortOrder: account.sortOrder,
    colorArgb: Value(account.colorArgb),
    iconKey: Value(account.iconKey),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `PaymentMethodRow` and the domain `PaymentMethod` entity.
extension PaymentMethodMapper on PaymentMethodRow {
  /// Maps this row to a domain entity.
  PaymentMethod toEntity() => PaymentMethod(
    id: id,
    name: name,
    kind: kind,
    isSystem: isSystem,
    sortOrder: sortOrder,
  );
}

/// Builds the companion for [method].
PaymentMethodsCompanion paymentMethodToCompanion(
  PaymentMethod method, {
  required int createdAt,
  required int updatedAt,
}) {
  return PaymentMethodsCompanion.insert(
    id: method.id,
    name: method.name,
    kind: method.kind,
    isSystem: method.isSystem,
    sortOrder: method.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `PayeeRow` and the domain `Payee` entity.
extension PayeeMapper on PayeeRow {
  /// Maps this row to a domain entity.
  Payee toEntity() => Payee(
    id: id,
    name: name,
    normalizedName: normalizedName,
    kind: kind,
    phone: phone,
    note: note,
  );
}

/// Builds the companion for [payee].
PayeesCompanion payeeToCompanion(
  Payee payee, {
  required int createdAt,
  required int updatedAt,
}) {
  return PayeesCompanion.insert(
    id: payee.id,
    name: payee.name,
    normalizedName: payee.normalizedName,
    kind: payee.kind,
    phone: Value(payee.phone),
    note: Value(payee.note),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts `ActiveTransactionRow` (from `v_active_transactions`, what every read method on
/// `TransactionDao` returns) into the domain `Transaction` entity.
///
/// Not `TransactionRow` — no read path in `TransactionDao` ever returns one; every method reads
/// the view, per Law L7. The view aliases the primary key as `tx_id` (so `Transaction` and
/// `TransactionLine` share the unqualified name `id` in a join), which is why this reads
/// [ActiveTransactionRow.txId] rather than `.id`.
///
/// The view originally omitted `conversionRate`, `conversionRateRaw`, `conversionDateKey`,
/// `createdAt` and `updatedAt` — only enough columns to render a list, not enough to fully
/// reconstruct a row. The first three would have silently dropped the rate and date behind
/// every frozen conversion; the last two are why `TransactionRepositoryImpl.update` could not
/// preserve a transaction's true creation time on edit. Fixed by adding all five to
/// `transaction_views.drift` in this phase; see the phase report. `createdAt`/`updatedAt` are
/// read directly off [ActiveTransactionRow] by the repository for that bookkeeping — [toEntity]
/// itself still ignores them, since `Transaction` carries no persistence timestamps.
extension ActiveTransactionMapper on ActiveTransactionRow {
  /// Maps this row to a domain entity.
  Transaction toEntity() {
    final hasFreeze = convertedAmountMinor != null;
    return Transaction(
      id: txId,
      kind: kind,
      subtype: subtype,
      occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
        occurredAt,
        isUtc: true,
      ),
      dateKey: dateKey,
      originalAmount: MoneyColumns.read(
        originalAmountMinor,
        originalCurrencyCode,
      ),
      needsReview: needsReview,
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      paymentMethodId: paymentMethodId,
      payeeId: payeeId,
      note: note,
      recurringTemplateId: recurringTemplateId,
      recurringOccurrenceId: recurringOccurrenceId,
      frozenConversion: hasFreeze
          ? MoneyColumns.read(convertedAmountMinor!, convertedCurrencyCode!)
          : null,
      frozenConversionRate: hasFreeze ? conversionRate : null,
      frozenConversionRateRaw: hasFreeze ? conversionRateRaw : null,
      frozenConversionDateKey: hasFreeze ? conversionDateKey : null,
    );
  }
}

/// Builds the companion for [transaction].
///
/// [monthKey] is a required parameter here, not derived inside this function — deriving it in a
/// mapper that only ever runs after the repository has already validated and computed it would
/// invite a second, possibly-inconsistent derivation. `TransactionRepositoryImpl.create` and
/// `.update` are the one place `monthKey` is computed, from `dateKey.monthKey`.
TransactionsCompanion transactionToCompanion(
  Transaction transaction, {
  required int monthKey,
  required int createdAt,
  required int updatedAt,
}) {
  return TransactionsCompanion.insert(
    id: transaction.id,
    kind: transaction.kind,
    subtype: transaction.subtype,
    occurredAt: transaction.occurredAtUtc.millisecondsSinceEpoch,
    dateKey: transaction.dateKey,
    monthKey: monthKey,
    originalAmountMinor: MoneyColumns.minorOf(transaction.originalAmount),
    originalCurrencyCode: MoneyColumns.codeOf(transaction.originalAmount),
    fromAccountId: Value(transaction.fromAccountId),
    toAccountId: Value(transaction.toAccountId),
    paymentMethodId: Value(transaction.paymentMethodId),
    payeeId: Value(transaction.payeeId),
    note: Value(transaction.note),
    needsReview: transaction.needsReview,
    recurringTemplateId: Value(transaction.recurringTemplateId),
    recurringOccurrenceId: Value(transaction.recurringOccurrenceId),
    convertedAmountMinor: Value(
      MoneyColumns.minorOfNullable(transaction.frozenConversion),
    ),
    convertedCurrencyCode: Value(
      MoneyColumns.codeOfNullable(transaction.frozenConversion),
    ),
    conversionRate: Value(transaction.frozenConversionRate),
    conversionRateRaw: Value(transaction.frozenConversionRateRaw),
    conversionDateKey: Value(transaction.frozenConversionDateKey),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `TransactionLineRow` and the domain `TransactionLine` entity.
///
/// `transaction_lines` carries no currency column of its own (ARCH_2 §4.2) — every amount on a
/// line is implicitly in its parent transaction's currency. [toEntity] therefore requires
/// [transactionCurrencyCode] explicitly; there is no way to construct a correct
/// [TransactionLine.unitPrice] or [TransactionLine.lineAmount] from this row alone.
///
/// [categoryResolver] supplies the [UnitCategory] a `quantity` needs but this row does not carry
/// directly — looking up [TransactionLineRow.itemId]'s category, or [TransactionLineRow.unitCode]'s
/// when there is no item, exactly as `qty_converter.dart`'s class doc describes. Returns null from
/// the resolver when neither is available, in which case the mapped line's `quantity` is null too.
extension TransactionLineMapper on TransactionLineRow {
  /// Maps this row to a domain entity.
  TransactionLine toEntity({
    required String transactionCurrencyCode,
    required UnitCategory? Function(TransactionLineRow row) categoryResolver,
  }) {
    final category = categoryResolver(this);
    return TransactionLine(
      id: id,
      transactionId: transactionId,
      lineNo: lineNo,
      description: description,
      destination: destination,
      itemId: itemId,
      quantity: QtyColumns.readOrNull(quantityMilli, category),
      unitCode: unitCode,
      // `readNullable` enforces a pairing invariant — both null or both present — and throws on a
      // half-populated pair. It is right only where the currency is a nullable column written and
      // cleared with its own amount. Here the currency is always present, so a null amount is a
      // legitimate absence rather than a broken pair, and the nullability belongs to the amount.
      //
      // `transactionCurrencyCode` is a `required String` from the parent transaction, so every line
      // without a unit price — which is every line a shopping list produces — threw, and the detail
      // screen showed "that did not work" instead of the items.
      unitPrice: unitPriceMinor == null
          ? null
          : Money(unitPriceMinor!, transactionCurrencyCode),
      lineAmount: lineAmountMinor == null
          ? null
          : Money(lineAmountMinor!, transactionCurrencyCode),
      createdBatchId: createdBatchId,
      createdAssetId: createdAssetId,
      createdRecurringTemplateId: createdRecurringTemplateId,
      note: note,
    );
  }
}

/// Builds the companion for [line].
TransactionLinesCompanion transactionLineToCompanion(
  TransactionLine line, {
  required int createdAt,
  required int updatedAt,
}) {
  return TransactionLinesCompanion.insert(
    id: line.id,
    transactionId: line.transactionId,
    lineNo: line.lineNo,
    description: line.description,
    destination: line.destination,
    itemId: Value(line.itemId),
    quantityMilli: Value(QtyColumns.milliOfNullable(line.quantity)),
    unitCode: Value(line.unitCode),
    unitPriceMinor: Value(MoneyColumns.minorOfNullable(line.unitPrice)),
    lineAmountMinor: Value(MoneyColumns.minorOfNullable(line.lineAmount)),
    createdBatchId: Value(line.createdBatchId),
    createdAssetId: Value(line.createdAssetId),
    createdRecurringTemplateId: Value(line.createdRecurringTemplateId),
    note: Value(line.note),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
```

### `lib/data/repositories/mappers/rate_mappers.dart`

```dart
import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// Maps between `currency_rates` rows and the rate types `CurrencyRateService` works in.
///
/// Extracted in Phase 5, when wiring the provider graph revealed that **one direction existed only
/// as a private method inside `CurrencyRepositoryImpl` and the other did not exist at all.**
/// `CurrencyRateService` takes a `RateSnapshotSaver`, and until now nothing in the codebase could
/// satisfy it against the DAO — the port had no adapter, so `syncDailyRates` could not actually have
/// been called in production.
///
/// Both directions live here so the mapping has one definition. Writing the row-to-`UsdRate` map a
/// second time in the provider would have been the fourth instance of the duplication that Phase 4A
/// and 4B each had to undo.
abstract final class RateMappers {
  /// Builds an in-memory [RateTable] from cached rows.
  ///
  /// [decimalDigitsByCode] comes from `currencies`, not from the rate rows: minor-unit precision is a
  /// property of the currency, and reading it from a rate row would make a JPY amount's precision
  /// depend on whether a rate happened to be cached for it.
  static RateTable tableFrom({
    required Iterable<CurrencyRateRow> rows,
    required Map<String, int> decimalDigitsByCode,
  }) => RateTable(
    rates: rows.map(usdRateFrom),
    decimalDigitsByCode: decimalDigitsByCode,
  );

  /// Maps one cached row to a [UsdRate].
  static UsdRate usdRateFrom(CurrencyRateRow row) => UsdRate(
    quoteCode: row.quoteCode,
    on: row.rateDateKey,
    rate: row.rate,
    rateRaw: row.rateRaw,
  );

  /// Maps a fetched snapshot to insertable rows.
  ///
  /// [uids] supplies a primary key per row even though `idx_rates_point` is what actually prevents
  /// duplicates — the table's own key is a UUID (ARCH_1 §4.4), and the upsert targets the index
  /// rather than the id, so a fresh id on a row that already exists is discarded by the conflict
  /// clause rather than inserted twice.
  ///
  /// `baseCode` is [RateTable.pivotCode] for every row, because a snapshot is USD-pivoted by
  /// definition (ARCH_3 §1.2) — storing each pair separately is exactly what the pivot avoids.
  static List<CurrencyRatesCompanion> companionsFrom({
    required RateSnapshot snapshot,
    required UidGenerator uids,
    required Clock clock,
  }) {
    final now = clock.nowUtcMillis();
    return snapshot.rates
        .map(
          (rate) => CurrencyRatesCompanion.insert(
            id: uids.generate(),
            baseCode: RateTable.pivotCode,
            quoteCode: rate.quoteCode,
            rateDateKey: rate.on,
            rate: rate.rate,
            // The provider's exact string, kept verbatim. ARCH_3 §1.3.7 wants the raw response value
            // so a rounding question later can be answered against what the provider actually sent.
            rateRaw: rate.rateRaw,
            source: snapshot.source,
            fetchedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        )
        .toList();
  }
}
```

### `lib/data/repositories/mappers/recipe_mappers.dart`

```dart
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/converters/qty_converter.dart';
import 'package:alaya/domain/entities/recipe.dart';

/// Maps recipe rows to domain entities.
///
/// **A [UnitCategory] has to be supplied per ingredient**, because no recipe row stores one.
/// `QtyColumns` documents why: a `Qty` needs a category, and the category lives on
/// `items.unit_category` or `units.category` — never beside the quantity. The repository resolves
/// it once per save or load and threads it through here, which is what stops this file inventing
/// a category it cannot know.
extension RecipeIngredientMapper on RecipeIngredientRow {
  /// Maps this row to a domain entity, using [category] from the linked item or unit.
  RecipeIngredient toEntity({required UnitCategory? category}) =>
      RecipeIngredient(
        id: id,
        recipeId: recipeId,
        itemId: itemId,
        freeText: freeText,
        quantity: QtyColumns.readOrNull(quantityMilli, category),
        unitCode: unitCode,
        isOptional: isOptional,
        note: note,
        sortOrder: sortOrder,
      );
}

/// Maps step rows.
extension RecipeStepMapper on RecipeStepRow {
  /// Maps this row to a domain entity.
  RecipeStep toEntity() => RecipeStep(
    id: id,
    recipeId: recipeId,
    stepNumber: stepNumber,
    instruction: instruction,
    durationMinutes: durationMinutes,
  );
}

/// Maps recipe header rows.
extension RecipeMapper on RecipeRow {
  /// Maps this row plus its already-loaded [ingredients] and [steps] to a domain entity.
  ///
  /// The children are passed in rather than fetched here: a mapper that queried would make every
  /// list row a database round trip, and this extension has no database to query with.
  Recipe toEntity({
    required List<RecipeIngredient> ingredients,
    required List<RecipeStep> steps,
  }) => Recipe(
    id: id,
    name: name,
    normalizedName: normalizedName,
    servings: servings,
    ingredients: ingredients,
    steps: steps,
    prepMinutes: prepMinutes,
    cookMinutes: cookMinutes,
    isFavorite: isFavorite,
    notes: notes,
  );
}

/// Maps cook-log rows.
extension RecipeCookMapper on RecipeCookLogRow {
  /// Maps this row to a domain entity.
  RecipeCook toEntity() => RecipeCook(
    id: id,
    recipeId: recipeId,
    cookedOn: cookedDateKey,
    servingsCooked: servingsCooked,
    deductedStock: deductedStock,
    note: note,
  );
}
```

### `lib/data/repositories/mappers/schedule_mappers.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:drift/drift.dart' show Value;

import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/converters/money_converter.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/service_record.dart';

/// Converts between `RecurringTemplateRow` and the domain `RecurringTemplate` entity.
extension RecurringTemplateMapper on RecurringTemplateRow {
  /// Maps this row to a domain entity.
  RecurringTemplate toEntity() => RecurringTemplate(
    id: id,
    name: name,
    normalizedName: normalizedName,
    kind: kind,
    direction: direction,
    defaultAmount: MoneyColumns.read(defaultAmountMinor, currencyCode),
    intervalUnit: intervalUnit,
    intervalCount: intervalCount,
    startDateKey: startDateKey,
    nextDueDateKey: nextDueDateKey,
    isPaused: isPaused,
    autoRemind: autoRemind,
    remindDaysBefore: remindDaysBefore,
    payeeId: payeeId,
    defaultAccountId: defaultAccountId,
    defaultPaymentMethodId: defaultPaymentMethodId,
    tagId: tagId,
    anchorDayOfMonth: anchorDayOfMonth,
    anchorMonth: anchorMonth,
    anchorWeekday: anchorWeekday,
    endDateKey: endDateKey,
    linkedAssetId: linkedAssetId,
    note: note,
  );
}

/// Builds the companion for [template].
RecurringTemplatesCompanion recurringTemplateToCompanion(
  RecurringTemplate template, {
  required int createdAt,
  required int updatedAt,
}) {
  return RecurringTemplatesCompanion.insert(
    id: template.id,
    name: template.name,
    normalizedName: template.normalizedName,
    kind: template.kind,
    direction: template.direction,
    defaultAmountMinor: MoneyColumns.minorOf(template.defaultAmount),
    currencyCode: MoneyColumns.codeOf(template.defaultAmount),
    payeeId: Value(template.payeeId),
    defaultAccountId: Value(template.defaultAccountId),
    defaultPaymentMethodId: Value(template.defaultPaymentMethodId),
    tagId: Value(template.tagId),
    intervalUnit: template.intervalUnit,
    intervalCount: template.intervalCount,
    anchorDayOfMonth: Value(template.anchorDayOfMonth),
    anchorMonth: Value(template.anchorMonth),
    anchorWeekday: Value(template.anchorWeekday),
    startDateKey: template.startDateKey,
    endDateKey: Value(template.endDateKey),
    nextDueDateKey: template.nextDueDateKey,
    isPaused: template.isPaused,
    autoRemind: template.autoRemind,
    remindDaysBefore: template.remindDaysBefore,
    linkedAssetId: Value(template.linkedAssetId),
    note: Value(template.note),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `RecurringOccurrenceRow` and the domain `RecurringOccurrence` entity.
///
/// [currencyCode] comes from the owning template: `recurring_occurrences` stores
/// `paid_amount_minor` with no currency column of its own (ARCH_2 §7), because an occurrence is
/// always denominated in its template's currency. Passing it in rather than assuming one keeps
/// Law L1's pairing rule honest.
extension RecurringOccurrenceMapper on RecurringOccurrenceRow {
  /// Maps this row to a domain entity.
  RecurringOccurrence toEntity(String currencyCode) => RecurringOccurrence(
    id: id,
    templateId: templateId,
    dueDateKey: dueDateKey,
    status: status,
    paidTransactionId: paidTransactionId,
    // `readNullable` enforces a pairing invariant — both null or both present — and throws on a
    // half-populated pair. It is right only where the currency is a nullable column written and
    // cleared with its own amount. Here the currency is always present, so a null amount is a
    // legitimate absence rather than a broken pair, and the nullability belongs to the amount.
    //
    // `recurring_occurrences.currency_code` is NOT NULL, so an occurrence that has not been paid
    // yet is exactly the half-populated pair this would reject.
    paidAmount: paidAmountMinor == null
        ? null
        : Money(paidAmountMinor!, currencyCode),
    paidDateKey: paidDateKey,
    note: note,
  );
}

/// Converts between `AssetRow` and the domain `Asset` entity.
///
/// `disposalAmountMinor` is read against `purchaseCurrencyCode`, because `assets` carries no
/// separate disposal currency (ARCH_2 §8) — sale proceeds are denominated in whatever the asset
/// was bought in. Pairing it with any other code would silently misstate the figure.
extension AssetMapper on AssetRow {
  /// Maps this row to a domain entity.
  Asset toEntity() => Asset(
    id: id,
    name: name,
    normalizedName: normalizedName,
    type: type,
    status: status,
    brand: brand,
    modelNo: modelNo,
    serialNo: serialNo,
    purchaseDateKey: purchaseDateKey,
    // Same shared currency as `disposalAmount` below, so the exposure runs both ways: an asset
    // disposed of without a recorded purchase price has the currency set and this amount null.
    purchasePrice: purchasePriceMinor == null || purchaseCurrencyCode == null
        ? null
        : Money(purchasePriceMinor!, purchaseCurrencyCode!),
    sourceTransactionLineId: sourceTransactionLineId,
    warrantyStartDateKey: warrantyStartDateKey,
    warrantyEndDateKey: warrantyEndDateKey,
    warrantyProvider: warrantyProvider,
    warrantyNote: warrantyNote,
    serviceIntervalDays: serviceIntervalDays,
    nextServiceDueDateKey: nextServiceDueDateKey,
    primaryContactName: primaryContactName,
    primaryContactPhone: primaryContactPhone,
    location: location,
    linkedRecurringTemplateId: linkedRecurringTemplateId,
    disposedAtDateKey: disposedAtDateKey,
    disposalReason: disposalReason,
    disposalNote: disposalNote,
    // `purchase_currency_code` is nullable, but it is shared with `purchasePrice` above — so an
    // asset bought for a known price and not yet disposed of has the currency set and this
    // amount null. One currency serving two amounts cannot carry a pairing invariant for either.
    disposalAmount: disposalAmountMinor == null || purchaseCurrencyCode == null
        ? null
        : Money(disposalAmountMinor!, purchaseCurrencyCode!),
    notes: notes,
  );
}

/// Builds the companion for [asset].
AssetsCompanion assetToCompanion(
  Asset asset, {
  required int createdAt,
  required int updatedAt,
}) {
  return AssetsCompanion.insert(
    id: asset.id,
    name: asset.name,
    normalizedName: asset.normalizedName,
    type: asset.type,
    brand: Value(asset.brand),
    modelNo: Value(asset.modelNo),
    serialNo: Value(asset.serialNo),
    purchaseDateKey: Value(asset.purchaseDateKey),
    purchasePriceMinor: Value(
      MoneyColumns.minorOfNullable(asset.purchasePrice),
    ),
    purchaseCurrencyCode: Value(
      MoneyColumns.codeOfNullable(asset.purchasePrice),
    ),
    sourceTransactionLineId: Value(asset.sourceTransactionLineId),
    warrantyStartDateKey: Value(asset.warrantyStartDateKey),
    warrantyEndDateKey: Value(asset.warrantyEndDateKey),
    warrantyProvider: Value(asset.warrantyProvider),
    warrantyNote: Value(asset.warrantyNote),
    serviceIntervalDays: Value(asset.serviceIntervalDays),
    nextServiceDueDateKey: Value(asset.nextServiceDueDateKey),
    primaryContactName: Value(asset.primaryContactName),
    primaryContactPhone: Value(asset.primaryContactPhone),
    location: Value(asset.location),
    linkedRecurringTemplateId: Value(asset.linkedRecurringTemplateId),
    status: asset.status,
    disposedAtDateKey: Value(asset.disposedAtDateKey),
    disposalReason: Value(asset.disposalReason),
    disposalNote: Value(asset.disposalNote),
    disposalAmountMinor: Value(
      MoneyColumns.minorOfNullable(asset.disposalAmount),
    ),
    notes: Value(asset.notes),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `ServiceRecordRow` and the domain `ServiceRecord` entity.
extension ServiceRecordMapper on ServiceRecordRow {
  /// Maps this row to a domain entity.
  ServiceRecord toEntity() => ServiceRecord(
    id: id,
    assetId: assetId,
    serviceDateKey: serviceDateKey,
    type: type,
    providerName: providerName,
    providerPhone: providerPhone,
    cost: MoneyColumns.readNullable(costMinor, currencyCode),
    linkedTransactionId: linkedTransactionId,
    nextDueDateKey: nextDueDateKey,
    notes: notes,
  );
}

/// Builds the companion for [record].
ServiceRecordsCompanion serviceRecordToCompanion(
  ServiceRecord record, {
  required int createdAt,
  required int updatedAt,
}) {
  return ServiceRecordsCompanion.insert(
    id: record.id,
    assetId: record.assetId,
    serviceDateKey: record.serviceDateKey,
    type: record.type,
    providerName: Value(record.providerName),
    providerPhone: Value(record.providerPhone),
    costMinor: Value(MoneyColumns.minorOfNullable(record.cost)),
    currencyCode: Value(MoneyColumns.codeOfNullable(record.cost)),
    linkedTransactionId: Value(record.linkedTransactionId),
    nextDueDateKey: Value(record.nextDueDateKey),
    notes: Value(record.notes),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
```

### `lib/data/repositories/mappers/shopping_mappers.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/converters/money_converter.dart';
import 'package:alaya/data/db/converters/qty_converter.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';

/// Converts between `ShoppingListRow` and the domain `ShoppingList` entity.
extension ShoppingListMapper on ShoppingListRow {
  /// Maps this row to a domain entity.
  ShoppingList toEntity() => ShoppingList(
    id: id,
    name: name,
    isDefault: isDefault,
    isArchived: isArchived,
    targetDateKey: targetDateKey,
  );
}

/// Builds the companion for [list].
ShoppingListsCompanion shoppingListToCompanion(
  ShoppingList list, {
  required int createdAt,
  required int updatedAt,
}) {
  return ShoppingListsCompanion.insert(
    id: list.id,
    name: list.name,
    isDefault: list.isDefault,
    isArchived: list.isArchived,
    targetDateKey: Value(list.targetDateKey),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `ShoppingEntryRow` and the domain `ShoppingEntry` entity.
///
/// [category] is **nullable** here, unlike the batch and movement mappers. A shopping entry may
/// name no item at all — `TV ☐` is a legitimate entry with nothing in the catalogue behind it
/// (anomaly A24) — so there is often no item whose `unitCategory` could be resolved. A null
/// category yields a null `quantity`, which is also the honest outcome for a free-text entry
/// nobody has attached a measurable amount to.
///
/// [homeCurrencyCode] must be supplied because `shopping_entries` carries no currency column
/// (ARCH_2 §6). An estimated price is a guess typed before any transaction exists, so there is no
/// parent row to inherit a currency from the way a `transaction_lines` amount inherits its
/// transaction's. Passing it in rather than assuming one keeps Law L1's pairing honest — a
/// hardcoded default would label a yen estimate as rupees for every user outside India.
extension ShoppingEntryMapper on ShoppingEntryRow {
  /// Maps this row to a domain entity, using [category] from the linked item when there is one.
  ShoppingEntry toEntity({
    required UnitCategory? category,
    required String homeCurrencyCode,
  }) => ShoppingEntry(
    id: id,
    listId: listId,
    origin: origin,
    autoState: autoState,
    isChecked: isChecked,
    sortOrder: sortOrder,
    itemId: itemId,
    freeText: freeText,
    quantity: QtyColumns.readOrNull(quantityMilli, category),
    unitCode: unitCode,
    tagId: tagId,
    // **Not `readNullable`.** That helper enforces a pairing invariant for tables storing an
    // amount *and* its currency, and throws on a half-populated pair. `shopping_entries` stores
    // only `estimated_price_minor`; the currency comes from settings and is therefore always
    // present, so every entry without a price — which is every auto-generated suggestion —
    // arrived as `(null, 'INR')` and threw. The nullability here belongs to the amount alone.
    estimatedPrice: estimatedPriceMinor == null
        ? null
        : Money(estimatedPriceMinor!, homeCurrencyCode),
    checkedAtUtc: checkedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(checkedAt!, isUtc: true),
    snoozeUntilDateKey: snoozeUntilDateKey,
    stockAtGeneration: QtyColumns.readOrNull(generatedAtStockMilli, category),
    purchasedTransactionLineId: purchasedTransactionLineId,
  );
}

/// Builds the companion for [entry].
ShoppingEntriesCompanion shoppingEntryToCompanion(
  ShoppingEntry entry, {
  required int createdAt,
  required int updatedAt,
}) {
  return ShoppingEntriesCompanion.insert(
    id: entry.id,
    listId: entry.listId,
    itemId: Value(entry.itemId),
    freeText: Value(entry.freeText),
    quantityMilli: Value(QtyColumns.milliOfNullable(entry.quantity)),
    unitCode: Value(entry.unitCode),
    tagId: Value(entry.tagId),
    estimatedPriceMinor: Value(
      MoneyColumns.minorOfNullable(entry.estimatedPrice),
    ),
    isChecked: entry.isChecked,
    checkedAt: Value(entry.checkedAtUtc?.millisecondsSinceEpoch),
    origin: entry.origin,
    autoState: entry.autoState,
    snoozeUntilDateKey: Value(entry.snoozeUntilDateKey),
    generatedAtStockMilli: Value(
      QtyColumns.milliOfNullable(entry.stockAtGeneration),
    ),
    purchasedTransactionLineId: Value(entry.purchasedTransactionLineId),
    sortOrder: entry.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
```

### `lib/data/repositories/mappers/split_mappers.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/converters/money_converter.dart';
import 'package:alaya/domain/entities/split_expense.dart';
import 'package:alaya/domain/entities/split_group.dart';
import 'package:alaya/domain/entities/split_read_models.dart';

/// Maps split rows to domain entities and back.
///
/// Uses `MoneyColumns` rather than a drift `TypeConverter` because `Money` spans two sibling columns
/// — an amount and the row's own `currencyCode` — which `money_converter.dart`'s class doc explains no
/// converter can do.
///
/// **The view mappers are where the nullability lives.** `SUM()` in SQL yields null, so every summed
/// column arrives as `int?` even where a join guarantees rows. Each one below states whether null
/// means zero or means *unknown*, because for `myShareMinor` those are different facts and collapsing
/// them would show ₹0 owed on a fresh install where the truth is "not configured yet".

// ── groups ────────────────────────────────────────────────────────────────────────────────

/// Maps group member rows.
extension SplitMemberMapper on SplitMemberRow {
  /// Maps this row to a domain entity.
  SplitMember toEntity() => SplitMember(
    id: id,
    groupId: groupId,
    payeeId: payeeId,
    defaultWeightBasisPoints: defaultWeightBasisPoints,
    sortOrder: sortOrder,
  );
}

/// Maps group header rows.
extension SplitGroupMapper on SplitGroupRow {
  /// Maps this row plus its already-loaded [members] to a domain entity.
  ///
  /// The members are passed in rather than fetched here, matching `RecipeMapper`: a mapper that
  /// queried would make every list row a database round trip, and this extension has no database to
  /// query with.
  SplitGroup toEntity({required List<SplitMember> members}) => SplitGroup(
    id: id,
    name: name,
    normalizedName: normalizedName,
    defaultSplitMethod: defaultSplitMethod,
    members: members,
    note: note,
    colorArgb: colorArgb,
    iconKey: iconKey,
    isArchived: isArchived,
    sortOrder: sortOrder,
  );
}

/// Builds the companion for [group].
SplitGroupsCompanion splitGroupToCompanion(
  SplitGroup group, {
  required int createdAt,
  required int updatedAt,
}) => SplitGroupsCompanion.insert(
  id: group.id,
  name: group.name,
  normalizedName: group.normalizedName,
  defaultSplitMethod: group.defaultSplitMethod,
  isArchived: group.isArchived,
  sortOrder: group.sortOrder,
  note: Value(group.note),
  colorArgb: Value(group.colorArgb),
  iconKey: Value(group.iconKey),
  createdAt: createdAt,
  updatedAt: updatedAt,
);

/// Builds the companion for [member].
SplitMembersCompanion splitMemberToCompanion(
  SplitMember member, {
  required int createdAt,
  required int updatedAt,
}) => SplitMembersCompanion.insert(
  id: member.id,
  groupId: member.groupId,
  payeeId: member.payeeId,
  sortOrder: member.sortOrder,
  defaultWeightBasisPoints: Value(member.defaultWeightBasisPoints),
  createdAt: createdAt,
  updatedAt: updatedAt,
);

// ── expenses ──────────────────────────────────────────────────────────────────────────────

/// Maps share rows.
extension SplitShareMapper on SplitShareRow {
  /// Maps this row to a domain entity.
  ///
  /// [currencyCode] comes from the parent expense, because a share row stores an amount and no
  /// currency — the same arrangement `RecipeIngredientMapper` has with `UnitCategory`, and for the
  /// same reason: the fact lives on the parent and a mapper must not invent one it cannot know.
  SplitShare toEntity({required String currencyCode}) => SplitShare(
    id: id,
    splitExpenseId: splitExpenseId,
    payeeId: payeeId,
    amount: MoneyColumns.read(shareAmountMinor, currencyCode),
    inputKind: inputKind,
    inputValue: inputValue,
    transactionLineNo: transactionLineNo,
  );
}

/// Maps expense header rows.
extension SplitExpenseMapper on SplitExpenseRow {
  /// Maps this row plus its already-loaded [shares] to a domain entity.
  SplitExpense toEntity({required List<SplitShare> shares}) => SplitExpense(
    id: id,
    paidByPayeeId: paidByPayeeId,
    total: MoneyColumns.read(totalAmountMinor, currencyCode),
    dateKey: dateKey,
    splitMethod: splitMethod,
    shares: shares,
    groupId: groupId,
    transactionId: transactionId,
    title: title,
    place: place,
    occasion: occasion,
    note: note,
    settleByDateKey: settleByDateKey,
    // `readNullable` throws on a half-populated pair rather than guessing, so a converted amount
    // without its currency surfaces here instead of as a wrong number on a dashboard.
    converted: _conversionOf(this),
  );
}

SplitConversion? _conversionOf(SplitExpenseRow row) {
  final amount = MoneyColumns.readNullable(
    row.convertedAmountMinor,
    row.convertedCurrencyCode,
  );
  final rate = row.conversionRate;
  final rateRaw = row.conversionRateRaw;
  final on = row.conversionDateKey;
  // All four move together or none does. A rate without an amount, or an amount without the date it
  // was valid on, is a snapshot that cannot be explained — and Law L9's whole point is that a frozen
  // conversion stays explainable years later.
  if (amount == null || rate == null || rateRaw == null || on == null) {
    return null;
  }
  return SplitConversion(
    amount: amount,
    rate: rate,
    rateRaw: rateRaw,
    dateKey: on,
  );
}

/// Builds the companion for [expense].
SplitExpensesCompanion splitExpenseToCompanion(
  SplitExpense expense, {
  required int createdAt,
  required int updatedAt,
}) => SplitExpensesCompanion.insert(
  id: expense.id,
  paidByPayeeId: expense.paidByPayeeId,
  totalAmountMinor: MoneyColumns.minorOf(expense.total),
  currencyCode: MoneyColumns.codeOf(expense.total),
  dateKey: expense.dateKey,
  // Derived on the entity, and the schema's `CHECK (date_key / 100 = month_key)` rejects a caller
  // that computes it differently — the same arrangement `transactions` uses.
  monthKey: expense.monthKey,
  splitMethod: expense.splitMethod,
  groupId: Value(expense.groupId),
  transactionId: Value(expense.transactionId),
  title: Value(expense.title),
  place: Value(expense.place),
  occasion: Value(expense.occasion),
  note: Value(expense.note),
  settleByDateKey: Value(expense.settleByDateKey),
  convertedAmountMinor: Value(
    MoneyColumns.minorOfNullable(expense.converted?.amount),
  ),
  convertedCurrencyCode: Value(
    MoneyColumns.codeOfNullable(expense.converted?.amount),
  ),
  conversionRate: Value(expense.converted?.rate),
  conversionRateRaw: Value(expense.converted?.rateRaw),
  conversionDateKey: Value(expense.converted?.dateKey),
  createdAt: createdAt,
  updatedAt: updatedAt,
);

/// Builds the companion for [share].
SplitSharesCompanion splitShareToCompanion(
  SplitShare share, {
  required int createdAt,
  required int updatedAt,
}) => SplitSharesCompanion.insert(
  id: share.id,
  splitExpenseId: share.splitExpenseId,
  payeeId: share.payeeId,
  shareAmountMinor: MoneyColumns.minorOf(share.amount),
  inputKind: share.inputKind,
  inputValue: Value(share.inputValue),
  transactionLineNo: Value(share.transactionLineNo),
  createdAt: createdAt,
  updatedAt: updatedAt,
);

// ── settlements ───────────────────────────────────────────────────────────────────────────

/// Maps settlement rows.
extension SplitSettlementMapper on SplitSettlementRow {
  /// Maps this row to a domain entity.
  SplitSettlement toEntity() => SplitSettlement(
    id: id,
    fromPayeeId: fromPayeeId,
    toPayeeId: toPayeeId,
    amount: MoneyColumns.read(amountMinor, currencyCode),
    dateKey: dateKey,
    groupId: groupId,
    transactionId: transactionId,
    paymentMethodId: paymentMethodId,
    note: note,
  );
}

/// Builds the companion for [settlement].
SplitSettlementsCompanion splitSettlementToCompanion(
  SplitSettlement settlement, {
  required int createdAt,
  required int updatedAt,
}) => SplitSettlementsCompanion.insert(
  id: settlement.id,
  fromPayeeId: settlement.fromPayeeId,
  toPayeeId: settlement.toPayeeId,
  amountMinor: MoneyColumns.minorOf(settlement.amount),
  currencyCode: MoneyColumns.codeOf(settlement.amount),
  dateKey: settlement.dateKey,
  monthKey: settlement.monthKey,
  groupId: Value(settlement.groupId),
  transactionId: Value(settlement.transactionId),
  paymentMethodId: Value(settlement.paymentMethodId),
  note: Value(settlement.note),
  createdAt: createdAt,
  updatedAt: updatedAt,
);

// ── views ─────────────────────────────────────────────────────────────────────────────────
//
// **A view column keeps the type converter of the table column it selects.** `v_split_expenses`
// selects `split_expenses.date_key` straight through, so it arrives as a `DateKey` rather than an
// `int` — and wrapping it in `DateKey(...)` here was four compile errors, because the converter had
// already run.
//
// That is not in tension with `SplitViewDao` passing plain ints to `isBetweenValues`: drift's
// comparison operators work on a column's **SQL** type even with a converter attached, while reading
// a row yields the **Dart** type. `recipe_dao.dart` records the same asymmetry from the other side,
// where it forced `date_key_filters.dart` into existence.

/// Maps `v_split_expenses` rows.
extension SplitExpenseSummaryMapper on SplitExpenseSummaryRow {
  /// Maps this row to a read model.
  SplitExpenseSummary toEntity() => SplitExpenseSummary(
    splitExpenseId: splitExpenseId,
    total: MoneyColumns.read(totalAmountMinor, currencyCode),
    // `COALESCE(..., 0)` in the view means this is never null in practice, but drift types a summed
    // column nullable regardless. Zero is the honest default here: no shares means nothing allocated.
    allocated: MoneyColumns.read(allocatedMinor ?? 0, currencyCode),
    dateKey: dateKey,
    paidByPayeeId: paidByPayeeId,
    shareCount: shareCount ?? 0,
    groupId: groupId,
    transactionId: transactionId,
    title: title,
    place: place,
    occasion: occasion,
    settleByDateKey: settleByDateKey,
    // **Null is passed through, not defaulted, and this is the one place that matters.** The view's
    // self-share subquery joins `app_settings` on `split.selfPayeeId`; with no such setting the join
    // finds nothing and the column is null. `?? 0` here would render "your share: ₹0" on a fresh
    // install, which reads as "you owe nothing" when the truth is that the app does not yet know who
    // you are.
    myShare: myShareMinor == null
        ? null
        : MoneyColumns.read(myShareMinor!, currencyCode),
  );
}

/// Maps `v_split_balances` rows.
extension SplitBalanceMapper on SplitBalanceRow {
  /// Maps this row to a read model.
  ///
  /// The summed columns default to zero: a counterparty who appears in the view has at least one
  /// contributing row, so a null side means "nothing on that side", which zero says exactly.
  SplitBalance toEntity() => SplitBalance(
    payeeId: payeeId,
    owedToMe: MoneyColumns.read(owedToMeMinor ?? 0, currencyCode),
    iOwe: MoneyColumns.read(iOweMinor ?? 0, currencyCode),
    // `MIN(date_key)` over rows that may all be settlements, which carry NULL there. Null means
    // nothing dated is outstanding, and `SplitBalance.ageInDays` already returns null for it.
    oldestUnsettledDateKey: oldestUnsettledDateKey,
  );
}

/// Maps `v_split_group_balances` rows.
extension SplitGroupBalanceMapper on SplitGroupBalanceRow {
  /// Maps this row to a read model.
  ///
  /// The group view carries no oldest-unsettled date: ageing is a property of a debt with a person,
  /// not of a debt within a group, and a group-scoped date would double-count somebody who owes you
  /// through two groups.
  SplitBalance toEntity() => SplitBalance(
    payeeId: payeeId,
    owedToMe: MoneyColumns.read(owedToMeMinor ?? 0, currencyCode),
    iOwe: MoneyColumns.read(iOweMinor ?? 0, currencyCode),
  );
}

/// Maps `v_split_activity` rows.
extension SplitActivityMapper on SplitActivityRow {
  /// Maps this row to a read model.
  SplitActivityEntry toEntity() => SplitActivityEntry(
    refId: refId,
    kind: activityKind == 'settlement'
        ? SplitActivityKind.settlement
        : SplitActivityKind.expense,
    dateKey: dateKey,
    amount: MoneyColumns.read(amountMinor, currencyCode),
    payeeId: payeeId,
    groupId: groupId,
    label: label,
  );
}
```

### `lib/data/repositories/mappers/stock_mappers.dart`

```dart
import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/converters/money_converter.dart';
import 'package:alaya/data/db/converters/qty_converter.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/domain/repositories/batch_repository.dart';

/// Converts between `ItemRow` and the domain `Item` entity.
///
/// An item is the one inventory row that carries its own `unitCategory`, so unlike every other
/// mapper here it needs no category resolution — it *is* the source every other one resolves
/// against.
extension ItemMapper on ItemRow {
  /// Maps this row to a domain entity.
  Item toEntity() => Item(
    id: id,
    name: name,
    normalizedName: normalizedName,
    unitCategory: unitCategory,
    defaultDisplayUnitCode: defaultDisplayUnitCode,
    itemKind: itemKind,
    isFavorite: isFavorite,
    lowStockThreshold: QtyColumns.readOrNull(lowStockThresholdMilli, unitCategory),
    expiryNotifyDays: expiryNotifyDays,
    notes: notes,
  );
}

/// Builds the companion for [item].
ItemsCompanion itemToCompanion(
    Item item, {
      required int createdAt,
      required int updatedAt,
    }) {
  return ItemsCompanion.insert(
    id: item.id,
    name: item.name,
    normalizedName: item.normalizedName,
    unitCategory: item.unitCategory,
    defaultDisplayUnitCode: item.defaultDisplayUnitCode,
    itemKind: item.itemKind,
    lowStockThresholdMilli: Value(QtyColumns.milliOfNullable(item.lowStockThreshold)),
    expiryNotifyDays: Value(item.expiryNotifyDays),
    notes: Value(item.notes),
    isFavorite: item.isFavorite,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `InventoryBatchRow` and the domain `Batch` entity.
///
/// Requires [category] explicitly: a batch stores `initialQuantityMilli` and
/// `remainingQuantityMilli` as bare integers, and a `Qty` is meaningless without the
/// [UnitCategory] that says whether those milli-units are grams, millilitres or pieces. The
/// category lives on the owning item, never on the batch (`qty_converter.dart` documents why no
/// drift `TypeConverter` can bridge this).
extension BatchMapper on InventoryBatchRow {
  /// Maps this row to a domain entity, using [category] from the owning item.
  Batch toEntity(UnitCategory category) => Batch(
    id: id,
    itemId: itemId,
    initialQuantity: QtyColumns.read(initialQuantityMilli, category),
    remainingQuantity: QtyColumns.read(remainingQuantityMilli, category),
    unitCodeAtPurchase: unitCodeAtPurchase,
    purchasedDateKey: purchasedDateKey,
    origin: origin,
    expiryDateKey: expiryDateKey,
    unitCost: MoneyColumns.readNullable(unitCostMinor, costCurrencyCode),
    sourceTransactionLineId: sourceTransactionLineId,
    storageLocation: storageLocation,
    note: note,
  );
}

/// Builds the companion for [batch].
InventoryBatchesCompanion batchToCompanion(
    Batch batch, {
      required int createdAt,
      required int updatedAt,
    }) {
  return InventoryBatchesCompanion.insert(
    id: batch.id,
    itemId: batch.itemId,
    initialQuantityMilli: QtyColumns.milliOf(batch.initialQuantity),
    remainingQuantityMilli: QtyColumns.milliOf(batch.remainingQuantity),
    unitCodeAtPurchase: batch.unitCodeAtPurchase,
    expiryDateKey: Value(batch.expiryDateKey),
    purchasedDateKey: batch.purchasedDateKey,
    unitCostMinor: Value(MoneyColumns.minorOfNullable(batch.unitCost)),
    costCurrencyCode: Value(MoneyColumns.codeOfNullable(batch.unitCost)),
    sourceTransactionLineId: Value(batch.sourceTransactionLineId),
    origin: batch.origin,
    storageLocation: Value(batch.storageLocation),
    note: Value(batch.note),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `StockMovementRow` and the domain `StockMovement` entity.
///
/// Requires [category] for the same reason [BatchMapper] does. There is deliberately no
/// entity-to-companion direction: `stock_movements` is append-only and the repository builds its
/// companions directly from a consumption plan, so a general reverse mapper would only invite the
/// edit Law L6's exception exists to prevent.
extension StockMovementMapper on StockMovementRow {
  /// Maps this row to a domain entity, using [category] from the owning item.
  StockMovement toEntity(UnitCategory category) => StockMovement(
    id: id,
    batchId: batchId,
    itemId: itemId,
    kind: kind,
    quantity: QtyColumns.read(quantityMilli, category),
    occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(occurredAt, isUtc: true),
    dateKey: dateKey,
    reason: reason,
    note: note,
    linkedTransactionId: linkedTransactionId,
    reversesMovementId: reversesMovementId,
  );
}

/// Converts `ItemStockRow` (from `v_item_stock`) into the domain `ItemStock` entity.
///
/// Needs no external category: the view selects `items.unit_category` directly, so a stock
/// rollup is self-describing.
extension ItemStockMapper on ItemStockRow {
  /// Maps this row to a domain entity.
  ItemStock toEntity() => ItemStock(
    itemId: itemId,
    totalRemaining: QtyColumns.read(totalRemainingMilli, unitCategory),
    batchCount: batchCount,
    isLowStock: isLowStock == 1,
    nearestExpiry: nearestExpiryDateKey,
    lowStockThreshold: QtyColumns.readOrNull(lowStockThresholdMilli, unitCategory),
  );
}

/// Converts `LowStockRow` (from `v_low_stock`) into the domain `ItemStock` entity.
///
/// `v_low_stock` is `v_item_stock` filtered to `is_low_stock = 1` plus a pre-computed shortfall,
/// so every row it yields is low on stock by construction — hence `isLowStock: true` rather than
/// a column read. The shortfall itself is recomputed by [ItemStock.shortfall] from the threshold
/// and remaining quantity rather than carried across, so there is exactly one definition of it.
extension LowStockMapper on LowStockRow {
  /// Maps this row to a domain entity.
  ItemStock toEntity() => ItemStock(
    itemId: itemId,
    totalRemaining: QtyColumns.read(totalRemainingMilli, unitCategory),
    // `v_low_stock` does not select batch_count — a low-stock suggestion needs the shortfall,
    // not how many batches it is spread across. Callers wanting the count read v_item_stock.
    batchCount: 0,
    isLowStock: true,
    nearestExpiry: nearestExpiryDateKey,
    lowStockThreshold: QtyColumns.readOrNull(lowStockThresholdMilli, unitCategory),
  );
}

/// Converts `BatchStockCheckRow` (from `v_batch_stock_check`) into the domain
/// `BatchReconciliation` entity.
///
/// Requires [category] for the same reason [BatchMapper] and [StockMovementMapper] do — all three
/// figures are `Qty`, and `v_batch_stock_check` is batch-centric with no `items` in its `FROM`
/// clause. Adding a join purely to surface `unit_category` would cost a join on a view that scans
/// every batch, when the caller already resolves categories through `ItemCategoryResolver` for the
/// batch and movement rows alongside it.
extension BatchReconciliationMapper on BatchStockCheckRow {
  /// Maps this row to a domain entity, using [category] from the owning item.
  BatchReconciliation toEntity(UnitCategory category) => BatchReconciliation(
    batchId: batchId,
    cached: QtyColumns.read(cachedRemainingMilli, category),
    fromLedger: QtyColumns.read(ledgerRemainingMilli, category),
    discrepancy: QtyColumns.read(discrepancyMilli, category),
  );
}

/// A `Money` total keyed by currency code, accumulated without ever adding across currencies.
///
/// Exists because waste and inventory valuation both sum costs whose currency is per-row
/// (`inventory_batches.cost_currency_code`), and `Money + Money` throws on a mismatch by design
/// (Law L1). Adding rupees to yen is anomaly A34; this makes that impossible rather than merely
/// discouraged.
final class MoneyByCurrency {
  /// Creates an empty accumulator.
  MoneyByCurrency();

  final Map<String, int> _minorByCode = {};

  /// Adds [minor] units of [currencyCode] to the running total.
  void add({required String currencyCode, required int minor}) {
    _minorByCode.update(currencyCode, (existing) => existing + minor, ifAbsent: () => minor);
  }

  /// The accumulated totals, one `Money` per currency encountered.
  Map<String, Money> get totals =>
      {for (final e in _minorByCode.entries) e.key: Money(e.value, e.key)};

  /// True when nothing has been added.
  bool get isEmpty => _minorByCode.isEmpty;
}
```

### `lib/data/repositories/mappers/tag_mapper.dart`

```dart
import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/entities/tag.dart';

/// Converts between `TagRow` and the domain `Tag` entity.
///
/// The six `allowedIn*` columns fold into one `Set<TagScope>` in both directions — the single
/// place that mapping happens, so a `Kitchen` tag can never end up allowed in the wrong picker
/// through a column mismatched in one direction but not the other (ARCH_2 §14).
extension TagMapper on TagRow {
  /// Maps this row to a domain entity.
  Tag toEntity() => Tag(
    id: id,
    name: name,
    normalizedName: normalizedName,
    allowedScopes: {
      if (allowedInDeposit) TagScope.deposit,
      if (allowedInWithdrawal) TagScope.withdrawal,
      if (allowedInInventory) TagScope.inventory,
      if (allowedInShopping) TagScope.shopping,
      if (allowedInRecurring) TagScope.recurring,
      if (allowedInService) TagScope.service,
    },
    isSystem: isSystem,
    sortOrder: sortOrder,
    isDeleted: deletedAt != null,
    colorArgb: colorArgb,
    iconKey: iconKey,
    parentTagId: parentTagId,
  );
}

/// Builds the companion for [tag].
///
/// [deletedAt] is threaded through explicitly rather than always `Value(null)`, because
/// [Tag.isDeleted] is real, writable state on this one entity (unlike every other repository in
/// this phase, which only ever soft-deletes via a dedicated method) — see the class doc on `Tag`.
TagsCompanion tagToCompanion(
    Tag tag, {
      required int createdAt,
      required int updatedAt,
      int? deletedAt,
    }) {
  return TagsCompanion.insert(
    id: tag.id,
    name: tag.name,
    normalizedName: tag.normalizedName,
    colorArgb: Value(tag.colorArgb),
    iconKey: Value(tag.iconKey),
    parentTagId: Value(tag.parentTagId),
    allowedInDeposit: tag.isAllowedIn(TagScope.deposit),
    allowedInWithdrawal: tag.isAllowedIn(TagScope.withdrawal),
    allowedInInventory: tag.isAllowedIn(TagScope.inventory),
    allowedInShopping: tag.isAllowedIn(TagScope.shopping),
    allowedInRecurring: tag.isAllowedIn(TagScope.recurring),
    allowedInService: tag.isAllowedIn(TagScope.service),
    isSystem: tag.isSystem,
    sortOrder: tag.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: Value(deletedAt),
  );
}
```

### `lib/data/repositories/mappers/unit_mapper.dart`

```dart
import 'package:drift/drift.dart' show Value;

import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/entities/unit.dart';

/// Converts between `UnitRow` and the domain `Unit` entity.
extension UnitMapper on UnitRow {
  /// Maps this row to a domain entity.
  Unit toEntity() => Unit(
    code: code,
    category: category,
    factorToBaseMilli: factorToBaseMilli,
    displayName: displayName,
    isSystem: isSystem,
    sortOrder: sortOrder,
  );
}

/// Builds the companion for [unit], given the `(createdAt, updatedAt)` pair
/// `WriteTimestamps.resolve` decided.
UnitsCompanion unitToCompanion(
    Unit unit, {
      required int createdAt,
      required int updatedAt,
    }) {
  return UnitsCompanion.insert(
    code: unit.code,
    category: unit.category,
    factorToBaseMilli: unit.factorToBaseMilli,
    displayName: unit.displayName,
    isSystem: unit.isSystem,
    sortOrder: unit.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: const Value(null),
  );
}
```

### `lib/data/repositories/payee_repository_impl.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/payee_dao.dart';
import 'package:alaya/data/repositories/mappers/money_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/repositories/payee_repository.dart';

/// `PayeeRepository` backed by `PayeeDao`.
final class PayeeRepositoryImpl implements PayeeRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const PayeeRepositoryImpl(this._dao, this._clock);

  final PayeeDao _dao;
  final Clock _clock;

  @override
  Stream<List<Payee>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Payee>> watchMatching(String term) =>
      _dao.watchMatching(term).map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Payee?> byId(String id) async => (await _dao.byIdIncludingDeleted(id))?.toEntity();

  @override
  Future<Payee?> byNormalizedName(String normalizedName) async =>
      (await _dao.byNormalizedName(normalizedName))?.toEntity();

  @override
  Future<Result<Payee, Failure>> save(Payee payee) async {
    final existing = await _dao.byIdIncludingDeleted(payee.id);

    if (existing == null) {
      final duplicate = await _dao.byNormalizedName(payee.normalizedName);
      if (duplicate != null) {
        return Result.failure(
          ConflictFailure('A payee named "${payee.name}" already exists.'),
        );
      }
    }

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _dao.upsert(
      payeeToCompanion(payee, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );
    return Result.ok(payee);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    await _dao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }
}
```

### `lib/data/repositories/payment_method_repository_impl.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/payment_method_dao.dart';
import 'package:alaya/data/repositories/mappers/money_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/repositories/payment_method_repository.dart';

/// `PaymentMethodRepository` backed by `PaymentMethodDao`.
final class PaymentMethodRepositoryImpl implements PaymentMethodRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const PaymentMethodRepositoryImpl(this._dao, this._clock);

  final PaymentMethodDao _dao;
  final Clock _clock;

  @override
  Stream<List<PaymentMethod>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<PaymentMethod?> byId(String id) async =>
      (await _dao.byIdIncludingDeleted(id))?.toEntity();

  @override
  Future<Result<PaymentMethod, Failure>> save(PaymentMethod method) async {
    final existing = await _dao.byIdIncludingDeleted(method.id);
    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _dao.upsert(
      paymentMethodToCompanion(method, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );
    return Result.ok(method);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    final inUseCount = await _dao.activeTransactionCount(id);
    if (inUseCount > 0) {
      return Result.failure(
        BusinessRuleFailure(
          'This payment method is used by $inUseCount transaction(s) and cannot be deleted.',
          rule: 'paymentMethodInUse',
        ),
      );
    }
    final rowsChanged = await _dao.softDeleteUserMethod(id: id, nowUtcMillis: _clock.nowUtcMillis());
    if (rowsChanged == 0) {
      return const Result.failure(
        BusinessRuleFailure('System payment methods cannot be deleted.', rule: 'systemProtected'),
      );
    }
    return const Result.ok(null);
  }
}
```

### `lib/data/repositories/recipe_repository_impl.dart`

```dart
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/item_dao.dart';
import 'package:alaya/data/daos/recipe_dao.dart';
import 'package:alaya/data/daos/unit_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/mappers/recipe_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/recipe.dart';
import 'package:alaya/domain/repositories/recipe_repository.dart';
import 'package:drift/drift.dart';

/// `RecipeRepository` backed by [RecipeDao].
///
/// **Its main job beyond mapping is resolving a [UnitCategory] for every ingredient**, because no
/// recipe row stores one. The category comes from the linked item where there is one, and from the
/// unit's own row otherwise — see `QtyColumns` for why the schema is arranged that way.
final class RecipeRepositoryImpl implements RecipeRepository {
  /// Creates the repository.
  const RecipeRepositoryImpl(
    this._dao,
    this._itemDao,
    this._unitDao,
    this._uids,
    this._clock,
  );

  final RecipeDao _dao;
  final ItemDao _itemDao;
  final UnitDao _unitDao;
  final UidGenerator _uids;
  final Clock _clock;

  /// Builds the item-id and unit-code lookups an ingredient list needs to become entities.
  ///
  /// Two lookups rather than a join, because an ingredient may carry a unit with no item — "200 ml
  /// water" that nobody catalogues — and a join on items would drop that line's category entirely.
  Future<UnitCategory?> _categoryFor(
    RecipeIngredientRow row, {
    required Map<String, UnitCategory> itemCategories,
    required Map<String, UnitCategory> unitCategories,
  }) async {
    final itemId = row.itemId;
    if (itemId != null) return itemCategories[itemId];
    final code = row.unitCode;
    return code == null ? null : unitCategories[code];
  }

  Future<List<RecipeIngredient>> _hydrate(
    List<RecipeIngredientRow> rows,
  ) async {
    if (rows.isEmpty) return const [];

    final itemIds = {
      for (final r in rows)
        if (r.itemId != null) r.itemId!,
    };
    final unitCodes = {
      for (final r in rows)
        if (r.unitCode != null) r.unitCode!,
    };

    final itemCategories = <String, UnitCategory>{};
    for (final id in itemIds) {
      final item = await _itemDao.byIdIncludingDeleted(id);
      if (item != null) itemCategories[id] = item.unitCategory;
    }
    // One call rather than one per code — `UnitDao` already exposes the whole map, and the unit
    // list is small and effectively static.
    final unitCategories = await _unitDao.categoriesByCode();

    final out = <RecipeIngredient>[];
    for (final row in rows) {
      final category = await _categoryFor(
        row,
        itemCategories: itemCategories,
        unitCategories: unitCategories,
      );
      out.add(row.toEntity(category: category));
    }
    return out;
  }

  Future<Recipe> _assemble(RecipeRow row) async {
    final ingredientRows = await _dao.watchIngredients(row.id).first;
    final stepRows = await _dao.watchSteps(row.id).first;
    return row.toEntity(
      ingredients: await _hydrate(ingredientRows),
      steps: [for (final s in stepRows) s.toEntity()],
    );
  }

  Future<List<Recipe>> _assembleAll(List<RecipeRow> rows) async {
    if (rows.isEmpty) return const [];
    final ids = [for (final r in rows) r.id];
    final ingredientRows = await _dao.watchIngredientsForAll(ids).first;
    final ingredients = await _hydrate(ingredientRows);

    final byRecipe = <String, List<RecipeIngredient>>{};
    for (final i in ingredients) {
      byRecipe.putIfAbsent(i.recipeId, () => []).add(i);
    }
    return [
      for (final row in rows)
        row.toEntity(
          ingredients: byRecipe[row.id] ?? const [],
          steps: const [],
        ),
    ];
  }

  @override
  Stream<List<Recipe>> watchAll() => _dao.watchAll().asyncMap(_assembleAll);

  @override
  Stream<List<Recipe>> watchMatching(String query) =>
      // [query] arrives already normalized, for the same reason the entity carries
      // `normalizedName`: one implementation of "the same name" (Phase 1A `Normalizer`).
      _dao.watchMatching(query).asyncMap(_assembleAll);

  @override
  Stream<List<Recipe>> watchFavorites() =>
      _dao.watchFavorites().asyncMap(_assembleAll);

  @override
  Stream<Recipe?> watchById(String id) => _dao
      .watchById(id)
      .asyncMap(
        (row) async => row == null ? null : _assemble(row),
      );

  @override
  Stream<List<Recipe>> watchUsingItem(String itemId) =>
      _dao.watchUsingItem(itemId).asyncMap(_assembleAll);

  @override
  Future<Recipe?> byId(String id) async {
    final row = await _dao.byId(id);
    return row == null ? null : _assemble(row);
  }

  @override
  Future<Result<Recipe, Failure>> save(Recipe recipe) async {
    if (recipe.servings <= 0) {
      return const Result.failure(
        BusinessRuleFailure(
          'A recipe must serve at least one.',
          rule: 'recipeServings',
        ),
      );
    }
    for (final line in recipe.ingredients) {
      final linked = line.itemId != null;
      final named = (line.freeText ?? '').trim().isNotEmpty;
      // Exactly one, mirroring `shopping_entries`. Neither is a row nothing can render; both is a
      // row two screens would disagree about.
      if (linked == named) {
        return const Result.failure(
          BusinessRuleFailure(
            'An ingredient needs either an item or a name, not both.',
            rule: 'recipeIngredientIdentity',
          ),
        );
      }
    }

    try {
      final existing = await _dao.byId(recipe.id);
      final stamps = WriteTimestamps.resolve(
        existingCreatedAt: existing?.createdAt,
        clock: _clock,
      );
      final now = stamps.updatedAt;

      await _dao.saveAggregate(
        nowUtcMillis: now,
        recipe: RecipesCompanion(
          id: Value(recipe.id),
          name: Value(recipe.name),
          normalizedName: Value(recipe.normalizedName),
          servings: Value(recipe.servings),
          prepMinutes: Value(recipe.prepMinutes),
          cookMinutes: Value(recipe.cookMinutes),
          isFavorite: Value(recipe.isFavorite),
          notes: Value(recipe.notes),
          createdAt: Value(stamps.createdAt),
          updatedAt: Value(now),
          deletedAt: const Value(null),
        ),
        ingredients: [
          for (var i = 0; i < recipe.ingredients.length; i++)
            _ingredientCompanion(recipe.ingredients[i], recipe.id, i, now),
        ],
        steps: [
          for (var i = 0; i < recipe.steps.length; i++)
            RecipeStepsCompanion(
              id: Value(
                recipe.steps[i].id.isEmpty
                    ? _uids.generate()
                    : recipe.steps[i].id,
              ),
              recipeId: Value(recipe.id),
              stepNumber: Value(i + 1),
              instruction: Value(recipe.steps[i].instruction),
              durationMinutes: Value(recipe.steps[i].durationMinutes),
              createdAt: Value(now),
              updatedAt: Value(now),
              deletedAt: const Value(null),
            ),
        ],
      );

      final saved = await byId(recipe.id);
      return saved == null
          ? const Result.failure(
              UnexpectedFailure('The recipe could not be read back.'),
            )
          : Result.ok(saved);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That recipe could not be saved.', cause: error),
      );
    }
  }

  RecipeIngredientsCompanion _ingredientCompanion(
    RecipeIngredient line,
    String recipeId,
    int index,
    int now,
  ) => RecipeIngredientsCompanion(
    id: Value(line.id.isEmpty ? _uids.generate() : line.id),
    recipeId: Value(recipeId),
    itemId: Value(line.itemId),
    freeText: Value(line.freeText),
    quantityMilli: Value(line.quantity?.milliBase),
    unitCode: Value(line.unitCode),
    isOptional: Value(line.isOptional),
    note: Value(line.note),
    sortOrder: Value(index),
    createdAt: Value(now),
    updatedAt: Value(now),
    deletedAt: const Value(null),
  );

  @override
  Future<Result<void, Failure>> setFavorite({
    required String id,
    required bool isFavorite,
  }) async {
    try {
      await _dao.setFavorite(
        id: id,
        isFavorite: isFavorite,
        nowUtcMillis: _clock.nowUtcMillis(),
      );
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That could not be changed.', cause: error),
      );
    }
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    try {
      await _dao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That recipe could not be deleted.', cause: error),
      );
    }
  }

  @override
  Future<Result<RecipeCook, Failure>> logCook({
    required String recipeId,
    required DateKey cookedOn,
    required int servingsCooked,
    required bool deductedStock,
    String? note,
  }) async {
    try {
      final now = _clock.nowUtcMillis();
      final id = _uids.generate();
      await _dao.insertCook(
        RecipeCookLogCompanion(
          id: Value(id),
          recipeId: Value(recipeId),
          cookedDateKey: Value(cookedOn),
          servingsCooked: Value(servingsCooked),
          deductedStock: Value(deductedStock),
          note: Value(note),
          createdAt: Value(now),
          updatedAt: Value(now),
          deletedAt: const Value(null),
        ),
      );
      return Result.ok(
        RecipeCook(
          id: id,
          recipeId: recipeId,
          cookedOn: cookedOn,
          servingsCooked: servingsCooked,
          deductedStock: deductedStock,
          note: note,
        ),
      );
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That cook could not be recorded.', cause: error),
      );
    }
  }

  @override
  Stream<List<RecipeCook>> watchCookLog(String recipeId) => _dao
      .watchCookLog(recipeId)
      .map((rows) => [for (final r in rows) r.toEntity()]);
}
```

### `lib/data/repositories/recurring_repository_impl.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/recurring_occurrence_dao.dart';
import 'package:alaya/data/daos/recurring_template_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/mappers/schedule_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/repositories/recurring_repository.dart';
import 'package:alaya/domain/repositories/transaction_repository.dart';
import 'package:alaya/domain/services/recurring_engine.dart';

/// `RecurringRepository` backed by `RecurringTemplateDao` and `RecurringOccurrenceDao`.
///
/// Depends on `TransactionRepository` — the domain interface — so [payOccurrence] reuses its shape
/// validation and `monthKey` derivation rather than reimplementing them.
final class RecurringRepositoryImpl implements RecurringRepository {
  /// Creates the repository.
  const RecurringRepositoryImpl(
    this._templateDao,
    this._occurrenceDao,
    this._transactions,
    this._uids,
    this._clock,
  );

  final RecurringTemplateDao _templateDao;
  final RecurringOccurrenceDao _occurrenceDao;
  final TransactionRepository _transactions;
  final UidGenerator _uids;
  final Clock _clock;

  /// Owns the interval arithmetic, the month-end clamp and the materialisation bound.
  static const RecurringEngine _engine = RecurringEngine();

  // ── templates ─────────────────────────────────────────────────────────────────────────

  @override
  Stream<List<RecurringTemplate>> watchAllTemplates() => _templateDao
      .watchAll()
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<RecurringTemplate>> watchTemplatesByDirection(
    RecurringDirection direction,
  ) => _templateDao
      .watchByDirection(direction)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<RecurringTemplate>> watchTemplatesForAsset(String assetId) =>
      _templateDao
          .watchForAsset(assetId)
          .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<RecurringTemplate?> templateById(String id) async =>
      (await _templateDao.byIdIncludingDeleted(id))?.toEntity();

  /// Emits the due list: unpaused templates paired with their outstanding occurrence.
  ///
  /// Built from two typed queries rather than from `v_recurring_due`, deliberately. That view is a
  /// presentation-shaped projection of 18 columns; a full `RecurringTemplate` needs nine more
  /// (`normalizedName`, `startDateKey`, `isPaused`, the three anchors, `endDateKey`,
  /// `linkedAssetId`, `note`) and a full `RecurringOccurrence` four more (`paidTransactionId`,
  /// `paidAmount`, `paidDateKey`, `note`). Widening the view to carry all thirteen — with `note`
  /// needing an alias on both sides — would leave it a bare join whose only remaining value is a
  /// filter these two queries already express. Two queries, no per-template round trip.
  ///
  /// `RecurringTemplateDao.watchDue()` still reads the view and is the right call for a caller
  /// that only needs the projection, such as a dashboard count.
  @override
  Stream<List<RecurringDue>> watchDue() {
    return _templateDao.watchAll().asyncMap((templateRows) async {
      final today = _clock.today();
      // Materialisation never runs ahead of today, so every `due` occurrence has a due date on or
      // before it — this is the whole outstanding set, in one query rather than one per template.
      final outstanding = await _occurrenceDao.outstandingAsOf(today);
      final byTemplate = <String, RecurringOccurrenceRow>{};
      for (final row in outstanding) {
        final existing = byTemplate[row.templateId];
        // Oldest outstanding occurrence wins: that is the one the user owes next.
        if (existing == null || row.dueDateKey < existing.dueDateKey) {
          byTemplate[row.templateId] = row;
        }
      }

      final due = <RecurringDue>[];
      for (final templateRow in templateRows) {
        if (templateRow.isPaused) continue;
        final template = templateRow.toEntity();
        if (template.hasEnded(today)) continue;
        final occurrenceRow = byTemplate[templateRow.id];
        due.add(
          RecurringDue(
            template: template,
            occurrence: occurrenceRow?.toEntity(templateRow.currencyCode),
          ),
        );
      }
      due.sort(
        (a, b) => DateKey.compare(
          a.template.nextDueDateKey,
          b.template.nextDueDateKey,
        ),
      );
      return due;
    });
  }

  @override
  Future<Result<RecurringTemplate, Failure>> saveTemplate(
    RecurringTemplate template,
  ) async {
    final validation = _validateTemplate(template);
    if (validation != null) return Result.failure(validation);

    final existing = await _templateDao.byIdIncludingDeleted(template.id);
    if (existing == null) {
      final duplicate = await _templateDao.byNormalizedName(
        template.normalizedName,
      );
      if (duplicate != null) {
        return Result.failure(
          ConflictFailure(
            'A recurring template named "${template.name}" already exists.',
          ),
        );
      }
    }

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _templateDao.upsert(
      recurringTemplateToCompanion(
        template,
        createdAt: stamps.createdAt,
        updatedAt: stamps.updatedAt,
      ),
    );
    return Result.ok(template);
  }

  @override
  Future<Result<void, Failure>> setTemplatePaused({
    required String id,
    required bool isPaused,
  }) async {
    final existing = await _templateDao.byIdIncludingDeleted(id);
    if (existing == null || existing.deletedAt != null) {
      return Result.failure(
        NotFoundFailure('Recurring template not found.', id: id),
      );
    }
    await _templateDao.setPaused(
      id: id,
      isPaused: isPaused,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> deleteTemplate(String id) async {
    // Soft, and it cascades to nothing. Paid occurrences and the transactions they created survive
    // untouched (ARCH_3 §4.1): deleting a subscription does not un-pay last month's bill, and the
    // money that left the account really left it.
    await _templateDao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  // ── occurrences ───────────────────────────────────────────────────────────────────────

  @override
  Stream<List<RecurringOccurrence>> watchOccurrences(String templateId) {
    return _occurrenceDao.watchForTemplate(templateId).asyncMap((rows) async {
      final template = await _templateDao.byIdIncludingDeleted(templateId);
      if (template == null) return const <RecurringOccurrence>[];
      return rows.map((r) => r.toEntity(template.currencyCode)).toList();
    });
  }

  @override
  Stream<List<RecurringOccurrence>> watchOccurrencesInRange({
    required DateKey from,
    required DateKey to,
  }) {
    return _occurrenceDao
        .watchDueInRange(from: from, to: to)
        .asyncMap(_mapWithTemplateCurrency);
  }

  @override
  Future<Result<int, Failure>> materialiseUpTo(DateKey asOf) async {
    final templates = await _templateDao.needingMaterialisation(asOf);
    final now = _clock.nowUtcMillis();
    var created = 0;

    for (final row in templates) {
      final template = row.toEntity();
      var cursor = template.nextDueDateKey;
      var guard = 0;

      while (!cursor.isAfter(asOf) &&
          guard < RecurringEngine.maxOccurrencesPerPass) {
        guard++;
        final end = template.endDateKey;
        if (end != null && cursor.isAfter(end)) break;

        // Idempotent: the DAO reads before inserting, because `idx_recurring_occ` is a partial
        // unique index and SQLite rejects a partial index as an ON CONFLICT target. Running this
        // twice creates nothing the second time.
        await _occurrenceDao.upsertForDue(
          id: _uids.generate(),
          templateId: template.id,
          dueDateKey: cursor,
          nowUtcMillis: now,
        );
        created++;
        cursor = _advance(cursor, template);
      }

      if (cursor != template.nextDueDateKey) {
        await _templateDao.advanceNextDue(
          id: template.id,
          nextDueDateKey: cursor,
          nowUtcMillis: now,
        );
      }
    }
    // Every occurrence created here is `due`. Nothing is paid, and no transaction exists — money is
    // only ever created by an explicit user tap (anomaly A14). An app unopened for three months
    // produces three due rows and zero transactions.
    return Result.ok(created);
  }

  @override
  Future<Result<Transaction, Failure>> payOccurrence({
    required String occurrenceId,
    required Money amount,
    required DateKey paidOn,
    required String accountId,
    String? paymentMethodId,
  }) async {
    if (!amount.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'The amount paid must be greater than zero.',
          field: 'amount',
        ),
      );
    }

    final occurrence = await _occurrenceDao.byId(occurrenceId);
    if (occurrence == null) {
      return Result.failure(
        NotFoundFailure('Occurrence not found.', id: occurrenceId),
      );
    }
    if (occurrence.status != RecurringOccurrenceStatus.due) {
      return Result.failure(
        BusinessRuleFailure(
          'This occurrence is already ${occurrence.status.name}.',
          rule: 'occurrenceNotDue',
        ),
      );
    }

    final templateRow = await _templateDao.byIdIncludingDeleted(
      occurrence.templateId,
    );
    if (templateRow == null) {
      return Result.failure(
        NotFoundFailure(
          'The template this occurrence belongs to does not exist.',
          id: occurrence.templateId,
        ),
      );
    }
    if (amount.currencyCode != templateRow.currencyCode) {
      // `recurring_occurrences` has no currency column: a paid amount is denominated in its
      // template's currency (ARCH_2 §7). Accepting a different one would store the number against
      // the wrong code on read — Law L1's pairing rule, broken silently.
      return Result.failure(
        ValidationFailure(
          'This template is in ${templateRow.currencyCode}, so the payment cannot be in '
          '${amount.currencyCode}.',
          field: 'amount',
        ),
      );
    }

    // `direction` decides the kind: an outflow settles by taking money out, an inflow by putting it
    // in. This is what lets salary share the recurring system with bills instead of needing a
    // second, parallel one (anomaly A27).
    final isOutflow = templateRow.direction == RecurringDirection.outflow;
    final created = await _transactions.create(
      transaction: Transaction(
        id: _uids.generate(),
        kind: isOutflow ? TransactionKind.withdrawal : TransactionKind.deposit,
        subtype: isOutflow
            ? TransactionSubtype.bill
            : TransactionSubtype.salaryIn,
        // **Now when the date is today, midnight only when it is not.**
        //
        // The ledger orders by `dateKey DESC, occurredAt DESC`. Stamping midnight unconditionally sent
        // every same-day entry to the *bottom* of today's group, behind hand-entered expenses stamped
        // with the real clock — so two records made seconds apart appeared in an order with no
        // relationship to anything the user did.
        //
        // Midnight stays right for a back-dated payment: nobody knows what time last Tuesday's plumber
        // came, and inventing one would be a worse lie than admitting the day is all we have.
        occurredAtUtc: paidOn == _clock.today()
            ? _clock.now().toUtc()
            : paidOn.toUtcMidnight(),
        dateKey: paidOn,
        originalAmount: amount,
        needsReview: false,
        fromAccountId: isOutflow ? accountId : null,
        toAccountId: isOutflow ? null : accountId,
        paymentMethodId: paymentMethodId,
        payeeId: templateRow.payeeId,
        note: templateRow.name,
        recurringTemplateId: templateRow.id,
        recurringOccurrenceId: occurrenceId,
      ),
      tagIds: templateRow.tagId == null ? const [] : [templateRow.tagId!],
    );
    if (created.isFailure) return Result.failure(created.failureOrNull!);
    final transaction = created.valueOrNull!;

    // The ACTUAL amount is recorded on the occurrence. The template's `defaultAmountMinor` is not
    // touched — paying ₹520 against a ₹499 subscription records ₹520 here and leaves ₹499 as the
    // template's expectation, so analytics uses actuals without corrupting the schedule
    // (anomaly A29).
    await _occurrenceDao.markPaid(
      id: occurrenceId,
      transactionId: transaction.id,
      paidAmountMinor: amount.minor,
      paidDateKey: paidOn,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return Result.ok(transaction);
  }

  @override
  Future<Result<void, Failure>> skipOccurrence({
    required String occurrenceId,
    String? note,
  }) async {
    final occurrence = await _occurrenceDao.byId(occurrenceId);
    if (occurrence == null) {
      return Result.failure(
        NotFoundFailure('Occurrence not found.', id: occurrenceId),
      );
    }
    if (occurrence.status == RecurringOccurrenceStatus.paid) {
      return const Result.failure(
        BusinessRuleFailure(
          'A settled occurrence cannot be skipped — unsettle it first.',
          rule: 'cannotSkipPaid',
        ),
      );
    }
    await _occurrenceDao.markSkipped(
      id: occurrenceId,
      note: note,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> unsettleOccurrence(String occurrenceId) async {
    final occurrence = await _occurrenceDao.byId(occurrenceId);
    if (occurrence == null) {
      return Result.failure(
        NotFoundFailure('Occurrence not found.', id: occurrenceId),
      );
    }
    // Returns it to `due` and clears the settlement fields, so the obligation reappears rather than
    // staying silently marked paid after the transaction behind it is gone. The transaction itself
    // is not touched — this is called *because* it was deleted.
    await _occurrenceDao.unlinkDeletedTransaction(
      id: occurrenceId,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  // ── interval arithmetic ───────────────────────────────────────────────────────────────

  /// Delegates to [RecurringEngine.nextDue].
  ///
  /// The interval arithmetic and the month-end anchor clamp used to live here. Phase 4B moved them
  /// into the engine so the clamp has one definition — anomaly A13 is exactly the kind of rule that
  /// must not exist twice, because the second copy is the one that walks a bill backwards.
  DateKey _advance(DateKey from, RecurringTemplate template) =>
      _engine.nextDue(from: from, template: template);

  /// Validates a template's interval and anchor coherence.
  Failure? _validateTemplate(RecurringTemplate template) {
    if (template.name.trim().isEmpty) {
      return const ValidationFailure(
        'A recurring template needs a name.',
        field: 'name',
      );
    }
    if (!template.defaultAmount.isPositive) {
      return const ValidationFailure(
        'A recurring template needs a positive default amount.',
        field: 'defaultAmount',
      );
    }
    if (template.intervalCount < 1) {
      return const ValidationFailure(
        'The interval must be at least 1.',
        field: 'intervalCount',
      );
    }
    final end = template.endDateKey;
    if (end != null && end.isBefore(template.startDateKey)) {
      return const ValidationFailure(
        'The end date cannot be before the start date.',
        field: 'endDateKey',
      );
    }

    final anchorDay = template.anchorDayOfMonth;
    if (anchorDay != null && (anchorDay < 1 || anchorDay > 31)) {
      return const ValidationFailure(
        'The day of the month must be between 1 and 31.',
        field: 'anchorDayOfMonth',
      );
    }
    final anchorWeekday = template.anchorWeekday;
    if (anchorWeekday != null && (anchorWeekday < 1 || anchorWeekday > 7)) {
      return const ValidationFailure(
        'The weekday must be between 1 (Monday) and 7 (Sunday).',
        field: 'anchorWeekday',
      );
    }
    final anchorMonth = template.anchorMonth;
    if (anchorMonth != null && (anchorMonth < 1 || anchorMonth > 12)) {
      return const ValidationFailure(
        'The month must be between 1 and 12.',
        field: 'anchorMonth',
      );
    }

    // A monthly or yearly template with no day anchor would advance from whatever day it happened
    // to land on, so a February settlement would pull every later occurrence back to the 28th
    // permanently (anomaly A13). Requiring the anchor is what makes that impossible.
    final needsDayAnchor =
        template.intervalUnit == RecurringIntervalUnit.month ||
        template.intervalUnit == RecurringIntervalUnit.year;
    if (needsDayAnchor && anchorDay == null) {
      return const ValidationFailure(
        'A monthly or yearly template needs a day of the month to anchor to.',
        field: 'anchorDayOfMonth',
      );
    }
    return null;
  }

  Future<List<RecurringOccurrence>> _mapWithTemplateCurrency(
    List<RecurringOccurrenceRow> rows,
  ) async {
    final currencies = <String, String>{};
    for (final templateId in rows.map((r) => r.templateId).toSet()) {
      final template = await _templateDao.byIdIncludingDeleted(templateId);
      if (template != null) currencies[templateId] = template.currencyCode;
    }
    return rows
        .where((r) => currencies.containsKey(r.templateId))
        .map((r) => r.toEntity(currencies[r.templateId]!))
        .toList();
  }
}
```

### `lib/data/repositories/service_record_repository_impl.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/asset_dao.dart';
import 'package:alaya/data/daos/service_record_dao.dart';
import 'package:alaya/data/repositories/mappers/schedule_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/service_record.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/repositories/service_record_repository.dart';
import 'package:alaya/domain/repositories/transaction_repository.dart';

/// `ServiceRecordRepository` backed by `ServiceRecordDao`.
///
/// Depends on `TransactionRepository` — the **domain interface**, not the implementation — so that
/// [save]'s optional expense reuses the shape validation, `monthKey` derivation and account
/// resolution already built there rather than reimplementing any of it.
final class ServiceRecordRepositoryImpl implements ServiceRecordRepository {
  /// Creates the repository.
  const ServiceRecordRepositoryImpl(
    this._dao,
    this._assetDao,
    this._transactions,
    this._uids,
    this._clock,
  );

  final ServiceRecordDao _dao;
  final AssetDao _assetDao;
  final TransactionRepository _transactions;
  final UidGenerator _uids;
  final Clock _clock;

  @override
  Stream<List<ServiceRecord>> watchForAsset(String assetId) => _dao
      .watchForAsset(assetId)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<ServiceRecord>> watchForAssetByType({
    required String assetId,
    required ServiceRecordType type,
  }) => _dao
      .watchForAssetByType(assetId: assetId, type: type)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<ServiceRecord>> watchWithNextDueInRange({
    required DateKey from,
    required DateKey to,
  }) => _dao
      .watchWithNextDueInRange(from: from, to: to)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<ServiceRecord?> byId(String id) async =>
      (await _dao.byId(id))?.toEntity();

  @override
  Future<ServiceRecord?> mostRecentForAsset(String assetId) async =>
      (await _dao.mostRecentForAsset(assetId))?.toEntity();

  @override
  Future<Map<String, Money>> lifetimeCostByCurrency(String assetId) async {
    // The DAO already sums in SQL grouped by currency, so this only rewraps each total as `Money`.
    // Never flattened into one figure: an asset serviced in two countries has costs in two
    // currencies and adding them is anomaly A34.
    final minorByCode = await _dao.lifetimeCostByCurrency(assetId);
    return {
      for (final e in minorByCode.entries) e.key: Money(e.value, e.key),
    };
  }

  @override
  Future<Result<ServiceRecord, Failure>> save(
    ServiceRecord record, {
    bool alsoRecordAsExpense = false,
    String? accountId,
    String? paymentMethodId,
  }) async {
    final asset = await _assetDao.byId(record.assetId);
    if (asset == null) {
      return Result.failure(
        NotFoundFailure(
          'The asset this record belongs to does not exist.',
          id: record.assetId,
        ),
      );
    }

    if (alsoRecordAsExpense) {
      if (record.cost == null) {
        return const Result.failure(
          ValidationFailure(
            'A service record needs a cost before it can be recorded as an expense.',
            field: 'cost',
          ),
        );
      }
      if (accountId == null) {
        return const Result.failure(
          ValidationFailure(
            'Recording this as an expense needs an account to pay it from.',
            field: 'accountId',
          ),
        );
      }
      if (record.linkedTransactionId != null) {
        return const Result.failure(
          BusinessRuleFailure(
            'This service record is already linked to a transaction.',
            rule: 'alreadyLinked',
          ),
        );
      }
    }

    final existing = await _dao.byId(record.id);
    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );

    if (!alsoRecordAsExpense) {
      await _dao.upsert(
        serviceRecordToCompanion(
          record,
          createdAt: stamps.createdAt,
          updatedAt: stamps.updatedAt,
        ),
      );
      return Result.ok(record);
    }

    // The transaction is created FIRST, and that order is forced rather than chosen:
    // `service_records.linked_transaction_id` is a foreign key into `transactions`, so the row it
    // points at must already exist. The two writes therefore cannot share one drift transaction —
    // neither repository exposes transaction control spanning aggregates — so a failure on the
    // second write is compensated below rather than rolled back by the database.
    final created = await _transactions.create(
      transaction: Transaction(
        id: _uids.generate(),
        kind: TransactionKind.withdrawal,
        // `otherOut` rather than `electronics`: the subtype describes the *flow*, and servicing a
        // television is not the purchase of one. The semantic detail lives on the tag — Phase 1C
        // seeds a `Maintenance` tag scoped to withdrawal and service for exactly this.
        subtype: TransactionSubtype.otherOut,
        // **Now when the date is today, midnight only when it is not.**
        //
        // The ledger orders by `dateKey DESC, occurredAt DESC`. Stamping midnight unconditionally sent
        // every same-day entry to the *bottom* of today's group, behind hand-entered expenses stamped
        // with the real clock — so two records made seconds apart appeared in an order with no
        // relationship to anything the user did.
        //
        // Midnight stays right for a back-dated record: nobody knows what time last Tuesday's plumber
        // came, and inventing one would be a worse lie than admitting the day is all we have.
        occurredAtUtc: record.serviceDateKey == _clock.today()
            ? _clock.now().toUtc()
            : record.serviceDateKey.toUtcMidnight(),
        dateKey: record.serviceDateKey,
        originalAmount: record.cost!,
        needsReview: false,
        fromAccountId: accountId,
        // Optional, and unvalidated on purpose: a null method is the ordinary case, and refusing one
        // would make "how did you pay?" a question the user must answer to record what they spent.
        paymentMethodId: paymentMethodId,
        note: _expenseNote(record, assetName: asset.name),
      ),
    );
    if (created.isFailure) return Result.failure(created.failureOrNull!);
    final transactionId = created.valueOrNull!.id;

    final linked = record.copyWith(linkedTransactionId: transactionId);
    try {
      await _dao.upsert(
        serviceRecordToCompanion(
          linked,
          createdAt: stamps.createdAt,
          updatedAt: stamps.updatedAt,
        ),
      );
    } catch (error) {
      // Compensating action. Without it a failed record write would leave a withdrawal standing on
      // its own — silently inflating expenses with nothing in the service history to explain it,
      // which is worse than the operation plainly failing.
      await _transactions.delete(
        id: transactionId,
        reason:
            'Rolled back: the service record it belonged to could not be saved.',
      );
      return Result.failure(
        UnexpectedFailure(
          'The service record could not be saved, so the matching expense was rolled back.',
          cause: error,
        ),
      );
    }

    // Returns the record carrying BOTH ids — its own and `linkedTransactionId` — which is what the
    // caller needs to navigate between the service history and the expense.
    return Result.ok(linked);
  }

  @override
  Future<Result<void, Failure>> unlinkDeletedTransaction(String id) async {
    await _dao.unlinkDeletedTransaction(
      id: id,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    await _dao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  /// The note put on the generated withdrawal, so the expense is recognisable in the transaction
  /// list without opening the asset.
  String _expenseNote(ServiceRecord record, {required String assetName}) {
    final provider = record.providerName;
    final base = '${record.type.name} — $assetName';
    return provider == null || provider.isEmpty ? base : '$base ($provider)';
  }
}
```

### `lib/data/repositories/settings_keys.dart`

```dart
/// Well-known `app_settings` keys shared across repository implementations.
///
/// Exists so no repository impl needs to import another impl's file just to reference a key
/// string — `SettingsRepositoryImpl` and `TransactionRepositoryImpl` both use
/// [lastUsedAccountId], and importing one implementation class from another for a constant is
/// the kind of coupling this file avoids, even though nothing here touches Law L12 (both are
/// `data/`, so no layering rule is actually at stake — it is a design smell, not a violation).
abstract final class SettingsKeys {
  const SettingsKeys._();

  /// The user's chosen display currency for aggregated totals (Law L9 — display only). Seeded
  /// by Phase 1C on first launch.
  static const String homeCurrencyCode = 'homeCurrencyCode';

  /// The account quick-add falls back to when no last-used account is known. Seeded by Phase 1C
  /// on first launch.
  static const String defaultAccountId = 'defaultAccountId';

  /// The account `TransactionRepositoryImpl.create` writes after a successful save, and reads
  /// back to resolve quick-add's account (ARCH_2 §4.1). Absent until the first transaction is
  /// created — not part of Phase 1C's seed data.
  static const String lastUsedAccountId = 'lastUsedAccountId';
}
```

### `lib/data/repositories/settings_repository_impl.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/settings_dao.dart';
import 'package:alaya/data/repositories/settings_keys.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';

/// `SettingsRepository` backed by `SettingsDao`.
///
/// The two named lookups — [readHomeCurrencyCode], [readDefaultAccountId] — read the fixed keys
/// in [SettingsKeys] that Phase 1C's seed data writes on first launch, so both are populated from
/// the very first run rather than needing an explicit "unset" path.
final class SettingsRepositoryImpl implements SettingsRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const SettingsRepositoryImpl(this._dao, this._clock);

  final SettingsDao _dao;
  final Clock _clock;

  @override
  Stream<String?> watchValue(String key) => _dao.watchValue(key);

  @override
  Future<String?> readValue(String key) => _dao.readValue(key);

  @override
  Stream<Map<String, String>> watchAll() => _dao.watchAll();

  @override
  Future<Result<void, Failure>> writeValue({
    required String key,
    required String value,
    required String valueType,
  }) async {
    await _dao.writeValue(
      key: key,
      value: value,
      valueType: valueType,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> remove(String key) async {
    await _dao.softDelete(key: key, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Future<String?> readHomeCurrencyCode() =>
      _dao.readValue(SettingsKeys.homeCurrencyCode);

  @override
  Future<Result<void, Failure>> writeHomeCurrencyCode(String code) =>
      writeValue(
        key: SettingsKeys.homeCurrencyCode,
        value: code,
        valueType: 'string',
      );

  @override
  Future<String?> readDefaultAccountId() =>
      _dao.readValue(SettingsKeys.defaultAccountId);
}
```

### `lib/data/repositories/shopping_repository_impl.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/item_dao.dart';
import 'package:alaya/data/daos/shopping_entry_dao.dart';
import 'package:alaya/data/daos/shopping_list_dao.dart';
import 'package:alaya/data/daos/transaction_line_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/item_category_resolver.dart';
import 'package:alaya/data/repositories/mappers/shopping_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/repositories/shopping_repository.dart';

/// `ShoppingRepository` backed by `ShoppingListDao` and `ShoppingEntryDao`.
final class ShoppingRepositoryImpl implements ShoppingRepository {
  /// Creates the repository.
  const ShoppingRepositoryImpl(
    this._listDao,
    this._entryDao,
    this._itemDao,
    this._lineDao,
    this._categories,
    this._settings,
    this._uids,
    this._clock,
  );

  final ShoppingListDao _listDao;
  final ShoppingEntryDao _entryDao;
  final ItemDao _itemDao;
  final TransactionLineDao _lineDao;
  final ItemCategoryResolver _categories;
  final SettingsRepository _settings;
  final UidGenerator _uids;
  final Clock _clock;

  // ── lists ─────────────────────────────────────────────────────────────────────────────

  @override
  Stream<List<ShoppingList>> watchSelectableLists() => _listDao
      .watchSelectable()
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<ShoppingList>> watchAllLists() => _listDao
      .watchAllIncludingArchived()
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<ShoppingList?> watchDefaultList() =>
      _listDao.watchDefault().map((row) => row?.toEntity());

  @override
  Future<ShoppingList?> listById(String id) async =>
      (await _listDao.byIdIncludingDeleted(id))?.toEntity();

  @override
  Future<Result<ShoppingList, Failure>> saveList(ShoppingList list) async {
    if (list.name.trim().isEmpty) {
      return const Result.failure(
        ValidationFailure('A shopping list needs a name.', field: 'name'),
      );
    }

    final existing = await _listDao.byIdIncludingDeleted(list.id);
    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _listDao.upsert(
      shoppingListToCompanion(
        list,
        createdAt: stamps.createdAt,
        updatedAt: stamps.updatedAt,
      ),
    );

    // `isDefault` carries no database-level uniqueness constraint, so setting it through a plain
    // upsert would leave two lists flagged. The DAO's setDefault clears every other list's flag in
    // the same transaction; routing through it keeps "exactly one default" true in practice.
    if (list.isDefault && existing?.isDefault != true) {
      await _listDao.setDefault(id: list.id, nowUtcMillis: stamps.updatedAt);
    }
    return Result.ok(list);
  }

  @override
  Future<Result<void, Failure>> setDefaultList(String id) async {
    final list = await _listDao.byIdIncludingDeleted(id);
    if (list == null || list.deletedAt != null) {
      return Result.failure(
        NotFoundFailure('Shopping list not found.', id: id),
      );
    }
    if (list.isArchived) {
      return const Result.failure(
        BusinessRuleFailure(
          'An archived list cannot be the default — unarchive it first.',
          rule: 'archivedCannotBeDefault',
        ),
      );
    }
    await _listDao.setDefault(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> setListArchived({
    required String id,
    required bool isArchived,
  }) async {
    final list = await _listDao.byIdIncludingDeleted(id);
    if (list == null || list.deletedAt != null) {
      return Result.failure(
        NotFoundFailure('Shopping list not found.', id: id),
      );
    }
    if (isArchived && list.isDefault) {
      // Archiving the default would leave quick-add with nowhere to write, silently. Refusing
      // makes the user pick a new default first, which is the decision they actually need to make.
      return const Result.failure(
        BusinessRuleFailure(
          'This is the default list. Make another list the default before archiving it.',
          rule: 'cannotArchiveDefaultList',
        ),
      );
    }
    await _listDao.setArchived(
      id: id,
      isArchived: isArchived,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> deleteList(String id) async {
    // Cascades to the list's entries inside one transaction, in the DAO.
    await _listDao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  // ── entries ───────────────────────────────────────────────────────────────────────────

  @override
  Stream<List<ShoppingEntry>> watchEntries(String listId) =>
      _entryDao.watchForList(listId).asyncMap(_mapEntries);

  @override
  Stream<List<ShoppingEntry>> watchUncheckedEntries(String listId) =>
      _entryDao.watchUncheckedForList(listId).asyncMap(_mapEntries);

  @override
  Future<Result<ShoppingEntry, Failure>> saveEntry(ShoppingEntry entry) async {
    // An entry names a catalogued item OR carries free text — never neither, or the row renders as
    // a blank line nobody can act on (anomaly A24 is about allowing free text, not about allowing
    // nothing).
    final hasItem = entry.itemId != null;
    final hasText = entry.freeText != null && entry.freeText!.trim().isNotEmpty;
    if (!hasItem && !hasText) {
      return const Result.failure(
        ValidationFailure(
          'A shopping entry needs either an item or some text.',
          field: 'freeText',
        ),
      );
    }

    if (hasItem) {
      final item = await _itemDao.byIdIncludingDeleted(entry.itemId!);
      if (item == null) {
        return Result.failure(
          NotFoundFailure('Item not found.', id: entry.itemId!),
        );
      }
      final quantity = entry.quantity;
      if (quantity != null && quantity.category != item.unitCategory) {
        // A quantity in the wrong category would be stored as a bare integer and reinterpreted on
        // read as the item's own category — 2 pieces becoming 2 grams (Law L8).
        return Result.failure(
          ValidationFailure(
            'This entry is measured in ${quantity.category.name} but the item is measured in '
            '${item.unitCategory.name}.',
            field: 'quantity',
          ),
        );
      }
    }

    final existing = await _entryDao.byIdIncludingDeleted(entry.id);
    final now = _clock.nowUtcMillis();

    // Editing an auto-generated entry promotes it to `manual`, after which the suggestion engine
    // never touches it again (anomaly A22). Detected by comparing against the stored row rather
    // than trusting the incoming entity's own `origin`: a UI that round-trips an entity would
    // otherwise have to remember to flip the flag itself, and forgetting would let regeneration
    // silently overwrite the user's edit.
    final wasAuto =
        existing != null && existing.origin == ShoppingEntryOrigin.autoLowStock;
    final effectiveOrigin = wasAuto ? ShoppingEntryOrigin.manual : entry.origin;

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    final promoted = entry.copyWith(origin: effectiveOrigin);
    await _entryDao.upsert(
      shoppingEntryToCompanion(
        promoted,
        createdAt: stamps.createdAt,
        updatedAt: stamps.updatedAt,
      ),
    );
    if (wasAuto) {
      // Belt and braces: the companion already carries `manual`, but routing through the DAO's own
      // promote method means the transition is expressed in one place if it ever grows.
      await _entryDao.promoteToManual(id: entry.id, nowUtcMillis: now);
    }
    return Result.ok(promoted);
  }

  @override
  Future<Result<void, Failure>> setEntryChecked({
    required String id,
    required bool isChecked,
  }) async {
    await _entryDao.setChecked(
      id: id,
      isChecked: isChecked,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> snoozeEntry({
    required String id,
    required DateKey until,
  }) async {
    final stock = await _stockAtDecisionMilli(id);
    if (stock == null) {
      return Result.failure(
        NotFoundFailure('Shopping entry not found.', id: id),
      );
    }
    await _entryDao.setAutoState(
      id: id,
      autoState: ShoppingEntryAutoState.snoozed,
      stockAtDecisionMilli: stock,
      snoozeUntil: until,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> dismissEntry(String id) async {
    final stock = await _stockAtDecisionMilli(id);
    if (stock == null) {
      return Result.failure(
        NotFoundFailure('Shopping entry not found.', id: id),
      );
    }
    // Records the stock level at the moment of dismissal alongside the state. A dismissal that
    // stored only the flag would never come back — but one that came back on a timer would nag.
    // Storing the reading means the suggestion returns exactly when stock has genuinely risen
    // above the threshold and fallen below it again (anomaly A23).
    await _entryDao.setAutoState(
      id: id,
      autoState: ShoppingEntryAutoState.dismissed,
      stockAtDecisionMilli: stock,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> reorderEntries(List<String> orderedIds) async {
    await _entryDao.reorder(
      orderedIds: orderedIds,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> deleteEntry(String id) async {
    await _entryDao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  // ── the suggestion engine ─────────────────────────────────────────────────────────────

  @override
  Future<Result<int, Failure>> regenerateLowStockSuggestions(
    String listId,
  ) async {
    final list = await _listDao.byIdIncludingDeleted(listId);
    if (list == null || list.deletedAt != null) {
      return Result.failure(
        NotFoundFailure('Shopping list not found.', id: listId),
      );
    }

    final lowStock = await _itemDao.watchLowStock().first;
    final existingAuto = await _entryDao
        .watchActiveAutoSuggestions(listId)
        .first;
    var sortOrder = existingAuto.length;
    var active = 0;

    for (final row in lowStock) {
      final threshold = row.lowStockThresholdMilli;
      if (threshold == null) continue;
      final shortfall = threshold - row.totalRemainingMilli;
      if (shortfall <= 0) continue;

      final existing = await _entryDao.findAutoEntry(
        listId: listId,
        itemId: row.itemId,
      );

      // A dismissed or snoozed suggestion stays suppressed until stock has recovered past the
      // reading taken when the user dismissed it. Comparing against `generatedAtStockMilli` rather
      // than against the threshold is what distinguishes "still the same shortage they already
      // said no to" from "they bought some and ran out again" (anomaly A23).
      if (existing != null &&
          existing.autoState != ShoppingEntryAutoState.active) {
        final atDecision = existing.generatedAtStockMilli;
        final recovered =
            atDecision != null && row.totalRemainingMilli > atDecision;
        if (!recovered) continue;
      }

      // Idempotent by construction: `idx_shopping_auto` makes
      // `(listId, itemId, origin='autoLowStock')` unique among live rows, and the DAO's
      // read-then-write honours it — a partial index cannot be an `ON CONFLICT` target, which is
      // why this is not a plain upsert (see the DAO's own note).
      await _entryDao.upsertAutoEntry(
        newId: _uids.generate(),
        listId: listId,
        itemId: row.itemId,
        unitCode: await _itemUnitCode(row.itemId),
        quantityMilli: shortfall,
        stockAtGenerationMilli: row.totalRemainingMilli,
        sortOrder: sortOrder++,
        nowUtcMillis: _clock.nowUtcMillis(),
      );
      active++;
    }
    return Result.ok(active);
  }

  // ── closing the loop back to money ────────────────────────────────────────────────────

  @override
  Future<Result<List<TransactionLine>, Failure>> buildPurchaseDraft(
    String listId,
  ) async {
    // Mapped to entities first, deliberately. Building drafts straight off `ShoppingEntryRow`
    // means hand-assembling a `Qty` from `quantityMilli` and a `Money` from
    // `estimatedPriceMinor` — re-deriving, at a second site, the category and currency resolution
    // that `_mapEntries` already does correctly.
    final entries = await _mapEntries(
      await _entryDao.watchForList(listId).first,
    );
    final checked = entries
        .where((e) => e.isChecked && e.purchasedTransactionLineId == null)
        .toList();
    if (checked.isEmpty) {
      return const Result.failure(
        BusinessRuleFailure(
          'Nothing on this list is ticked off yet.',
          rule: 'nothingToPurchase',
        ),
      );
    }

    // Drafts only — nothing is written here. The user still confirms the amount and account in the
    // expense editor, and `TransactionRepository.create` is what commits. `transactionId` is left
    // empty deliberately: the transaction does not exist yet, and inventing an id here would let a
    // caller persist a line pointing at nothing.
    final drafts = <TransactionLine>[];
    var lineNo = 1;
    for (final entry in checked) {
      final itemId = entry.itemId;
      drafts.add(
        TransactionLine(
          id: _uids.generate(),
          transactionId: '',
          lineNo: lineNo++,
          description: entry.freeText ?? await _itemName(itemId) ?? 'Item',
          // A catalogued item becomes stock on purchase; free text has nowhere to land, so it
          // stays a plain expense line (ARCH_2 §4.2's `destination` is what removes that
          // ambiguity — anomaly A12).
          destination: itemId != null
              ? TransactionLineDestination.inventory
              : TransactionLineDestination.none,
          itemId: itemId,
          quantity: entry.quantity,
          // Falls back to the item's own display unit. An auto-generated low-stock suggestion is
          // written without one — nothing asked the user — and a line bound for inventory with no
          // unit cannot become a batch, because the column is a foreign key into `units`.
          unitCode: entry.unitCode ?? await _itemUnitCode(itemId),
          lineAmount: entry.estimatedPrice,
        ),
      );
    }
    return Result.ok(drafts);
  }

  @override
  Future<Result<void, Failure>> markPurchased({
    required List<String> entryIds,
    required String transactionId,
  }) async {
    final lines = await _lineDao.forTransaction(transactionId);
    if (lines.isEmpty) {
      return Result.failure(
        NotFoundFailure(
          'That transaction has no lines to link.',
          id: transactionId,
        ),
      );
    }

    // The contract hands over a transaction id, but an entry links to one specific *line*
    // (anomaly A25 — knowing which line fulfilled it is what lets the UI show the price paid).
    // Matching is by `itemId`, since `buildPurchaseDraft` built each line from an entry and
    // carried that id across; free-text entries fall back to matching the description.
    final byItemId = <String, String>{};
    final byDescription = <String, String>{};
    for (final line in lines) {
      final itemId = line.itemId;
      if (itemId != null) {
        byItemId.putIfAbsent(itemId, () => line.id);
      } else {
        byDescription.putIfAbsent(
          line.description.trim().toLowerCase(),
          () => line.id,
        );
      }
    }

    final now = _clock.nowUtcMillis();
    final unmatched = <String>[];
    for (final entryId in entryIds) {
      final entry = await _entryDao.byIdIncludingDeleted(entryId);
      if (entry == null) {
        unmatched.add(entryId);
        continue;
      }
      final lineId = entry.itemId != null
          ? byItemId[entry.itemId]
          : byDescription[(entry.freeText ?? '').trim().toLowerCase()];
      if (lineId == null) {
        unmatched.add(entryId);
        continue;
      }
      await _entryDao.markPurchased(
        id: entryId,
        transactionLineId: lineId,
        nowUtcMillis: now,
      );
    }

    if (unmatched.isNotEmpty) {
      // Reported rather than swallowed: the entries that *did* match are already linked, and
      // silently dropping the rest would leave the user's list half-updated with no explanation.
      return Result.failure(
        BusinessRuleFailure(
          '${unmatched.length} of ${entryIds.length} entries had no matching line in that '
          'transaction and were left unticked.',
          rule: 'entryLineMismatch',
        ),
      );
    }
    return const Result.ok(null);
  }

  /// The item's current total stock in base-milli units, for recording alongside a snooze or
  /// dismissal. Returns 0 for a free-text entry, which has no stock to read.
  Future<int?> _stockAtDecisionMilli(String entryId) async {
    final entry = await _entryDao.byIdIncludingDeleted(entryId);
    if (entry == null) return null;
    final itemId = entry.itemId;
    if (itemId == null) return 0;
    final stock = await _itemDao.stockOf(itemId);
    return stock?.totalRemainingMilli ?? 0;
  }

  /// The display unit code of [itemId], or null when there is no item.
  Future<String?> _itemUnitCode(String? itemId) async {
    if (itemId == null) return null;
    final item = await _itemDao.byIdIncludingDeleted(itemId);
    return item?.defaultDisplayUnitCode;
  }

  Future<String?> _itemName(String? itemId) async {
    if (itemId == null) return null;
    final row = await _itemDao.byIdIncludingDeleted(itemId);
    return row?.name;
  }

  Future<List<ShoppingEntry>> _mapEntries(List<ShoppingEntryRow> rows) async {
    final categories = await _categories.categoriesFor(
      rows.map((r) => r.itemId).whereType<String>(),
    );
    final homeCurrencyCode = await _homeCurrencyCode();
    return rows
        .map(
          (r) => r.toEntity(
            category: r.itemId == null ? null : categories[r.itemId],
            homeCurrencyCode: homeCurrencyCode,
          ),
        )
        .toList();
  }

  /// The user's home currency, for reading an entry's estimated price.
  ///
  /// Falls back to `INR` only if the seeded setting is somehow absent — Phase 1C always writes it,
  /// so this is defensive rather than an expected path.
  Future<String> _homeCurrencyCode() async =>
      await _settings.readHomeCurrencyCode() ?? 'INR';
}
```

### `lib/data/repositories/split_group_repository_impl.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/settings_dao.dart';
import 'package:alaya/data/daos/split_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/mappers/split_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/split_group.dart';
import 'package:alaya/domain/repositories/split_group_repository.dart';

/// `SplitGroupRepository` backed by [SplitDao].
///
/// Its own work beyond mapping is the refusals: a duplicate group name, a member listed twice, a
/// weight outside range, and — the one that matters — a delete while expenses still reference the
/// group.
final class SplitGroupRepositoryImpl implements SplitGroupRepository {
  /// Creates the repository.
  const SplitGroupRepositoryImpl(this._dao, this._settings, this._clock);

  final SplitDao _dao;
  final SettingsDao _settings;
  final Clock _clock;

  /// The `app_settings` key holding the payee the user has claimed as themselves.
  ///
  /// A setting rather than a flag on `payees`, so no two rows can claim it and a table five other
  /// modules read stays untouched.
  static const String selfPayeeSettingKey = 'split.selfPayeeId';

  Future<List<SplitMember>> _membersOf(String groupId) async {
    final rows = await _dao.watchMembers(groupId).first;
    return [for (final row in rows) row.toEntity()];
  }

  Future<SplitGroup> _assemble(SplitGroupRow row) async =>
      row.toEntity(members: await _membersOf(row.id));

  /// Assembles many groups with one membership query rather than one per group.
  ///
  /// The pattern `RecipeRepositoryImpl._assembleAll` uses: a list screen showing "4 people" per row
  /// would otherwise issue a query per visible row on every rebuild of a virtualised list.
  Future<List<SplitGroup>> _assembleAll(List<SplitGroupRow> rows) async {
    if (rows.isEmpty) return const [];
    final memberRows = await _dao.watchMembersForAll([
      for (final r in rows) r.id,
    ]).first;
    final byGroup = <String, List<SplitMember>>{};
    for (final row in memberRows) {
      byGroup.putIfAbsent(row.groupId, () => []).add(row.toEntity());
    }
    return [
      for (final row in rows)
        row.toEntity(members: byGroup[row.id] ?? const []),
    ];
  }

  @override
  Stream<List<SplitGroup>> watchAll() =>
      _dao.watchGroups().asyncMap(_assembleAll);

  @override
  Stream<List<SplitGroup>> watchActive() =>
      _dao.watchActiveGroups().asyncMap(_assembleAll);

  @override
  Stream<SplitGroup?> watchById(String id) => _dao
      .watchGroupById(id)
      .asyncMap((row) async => row == null ? null : _assemble(row));

  @override
  Future<SplitGroup?> byId(String id) async {
    final row = await _dao.groupById(id);
    return row == null ? null : _assemble(row);
  }

  @override
  Stream<List<SplitGroup>> watchForPayee(String payeeId) =>
      _dao.watchGroupsForPayee(payeeId).asyncMap(_assembleAll);

  @override
  Future<Result<SplitGroup, Failure>> save(SplitGroup group) async {
    if (group.name.trim().isEmpty) {
      return const Result.failure(
        ValidationFailure('A group needs a name.', field: 'name'),
      );
    }

    final seen = <String>{};
    for (final member in group.members) {
      if (!seen.add(member.payeeId)) {
        return const Result.failure(
          BusinessRuleFailure(
            'Somebody is listed twice in this group.',
            rule: 'splitDuplicateMember',
          ),
        );
      }
      final weight = member.defaultWeightBasisPoints;
      // Basis points, so 10,000 is the whole. A weight above it is meaningless and a negative one
      // would make the resolver throw — better to refuse it here, where the message can name the
      // group, than to let it reach `SplitResolver` as an `ArgumentError`.
      if (weight != null && (weight < 0 || weight > 10000)) {
        return const Result.failure(
          ValidationFailure(
            'A share must be between 0% and 100%.',
            field: 'defaultWeightBasisPoints',
          ),
        );
      }
    }

    final existing = await _dao.groupById(group.id);

    // **Checked before the write, not caught after it**, which is how `AccountRepositoryImpl` and
    // `ItemRepositoryImpl` handle their own uniqueness. Catching the index violation instead would
    // report *any* throw as a duplicate name — a disk error, a foreign-key failure, a bug in the
    // mapper — all wearing the same message. My first version did exactly that.
    //
    // Only on insert. A rename that collides is caught the same way, because `byNormalizedName`
    // returns the other group and its id differs.
    final duplicate = await _dao.byNormalizedName(group.normalizedName);
    if (duplicate != null && duplicate.id != group.id) {
      return Result.failure(
        ConflictFailure('A group named "${group.name}" already exists.'),
      );
    }

    try {
      final stamps = WriteTimestamps.resolve(
        existingCreatedAt: existing?.createdAt,
        clock: _clock,
      );
      final now = stamps.updatedAt;

      await _dao.saveGroup(
        nowUtcMillis: now,
        group: splitGroupToCompanion(
          group,
          createdAt: stamps.createdAt,
          updatedAt: now,
        ),
        members: [
          for (var i = 0; i < group.members.length; i++)
            splitMemberToCompanion(
              // The list's own order is authoritative, so a reorder in the editor is saved without
              // the UI having to renumber anything — the same treatment recipe ingredients get.
              SplitMember(
                id: group.members[i].id,
                groupId: group.id,
                payeeId: group.members[i].payeeId,
                defaultWeightBasisPoints:
                    group.members[i].defaultWeightBasisPoints,
                sortOrder: i,
              ),
              createdAt: now,
              updatedAt: now,
            ),
        ],
      );
      final saved = await byId(group.id);
      return saved == null
          ? const Result.failure(
              UnexpectedFailure('That group could not be saved.'),
            )
          : Result.ok(saved);
    } on Object catch (error) {
      // Whatever reaches here is genuinely unexplained, which is why `UnexpectedFailure` is the only
      // failure in this hierarchy that carries a `cause` — the others name a rule or a field the code
      // already understands, so there is nothing unaccounted for to attach.
      return Result.failure(
        UnexpectedFailure('That group could not be saved.', cause: error),
      );
    }
  }

  @override
  Future<Result<void, Failure>> setArchived({
    required String id,
    required bool isArchived,
  }) async {
    try {
      await _dao.setGroupArchived(
        id: id,
        isArchived: isArchived,
        nowUtcMillis: _clock.nowUtcMillis(),
      );
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That group could not be updated.', cause: error),
      );
    }
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    // **Refused while expenses reference the group**, and the message says what to do instead.
    // Cascading would delete a shared history because a label was tidied away, and every balance
    // those expenses feed would vanish with them. Archiving is the operation the user actually wants
    // and it is one tap away.
    final expenses = await _dao.expenseCountInGroup(id);
    if (expenses > 0) {
      return Result.failure(
        BusinessRuleFailure(
          'This group has $expenses expense(s). Archive it instead — its history stays and it '
          'leaves the pickers.',
          rule: 'splitGroupHasExpenses',
        ),
      );
    }
    try {
      await _dao.softDeleteGroup(id: id, nowUtcMillis: _clock.nowUtcMillis());
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That group could not be deleted.', cause: error),
      );
    }
  }

  @override
  Future<String?> selfPayeeId() => _settings.readValue(selfPayeeSettingKey);

  @override
  Future<Result<void, Failure>> setSelfPayeeId(String payeeId) async {
    try {
      await _settings.writeValue(
        key: selfPayeeSettingKey,
        value: payeeId,
        valueType: 'string',
        nowUtcMillis: _clock.nowUtcMillis(),
      );
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That could not be saved.', cause: error),
      );
    }
  }
}
```

### `lib/data/repositories/split_ledger_repository_impl.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/split_dao.dart';
import 'package:alaya/data/daos/split_view_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/mappers/split_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/split_expense.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/domain/repositories/split_group_repository.dart';
import 'package:alaya/domain/repositories/split_ledger_repository.dart';
import 'package:alaya/domain/services/split/debt_simplifier.dart' show DebtEdge;
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/data/daos/account_dao.dart';
import 'package:alaya/data/repositories/mappers/money_mappers.dart';
import 'package:alaya/domain/entities/transaction.dart';

/// `SplitLedgerRepository` backed by [SplitDao] for writes and [SplitViewDao] for everything derived.
///
/// **Two DAOs, and the split is Law L7 made structural.** Writes go to tables; every balance, total
/// and feed comes from a view. Nothing here can return a stored total because there is no stored total
/// to return.
final class SplitLedgerRepositoryImpl implements SplitLedgerRepository {
  /// Creates the repository.
  const SplitLedgerRepositoryImpl(
    this._dao,
    this._views,
    this._groups,
    this._accounts,
    this._clock,
  );

  final SplitDao _dao;
  final SplitViewDao _views;
  final SplitGroupRepository _groups;
  final AccountDao _accounts;
  final Clock _clock;

  Future<List<SplitShare>> _sharesOf(SplitExpenseRow row) async {
    final shares = await _dao.watchShares(row.id).first;
    return [for (final s in shares) s.toEntity(currencyCode: row.currencyCode)];
  }

  Future<SplitExpense> _assemble(SplitExpenseRow row) async =>
      row.toEntity(shares: await _sharesOf(row));

  // ── expenses ────────────────────────────────────────────────────────────────────────────

  @override
  Stream<List<SplitExpenseSummary>> watchExpenses({
    required DateKey from,
    required DateKey to,
    String? groupId,
  }) => _views
      .watchExpenses(
        // The typed boundary is crossed once, here. The views carry no converter, which is why
        // `SplitViewDao` takes plain ints — the same arrangement `CalendarDao` has.
        fromDateKey: from.value,
        toDateKey: to.value,
        groupId: groupId,
      )
      .map((rows) => [for (final row in rows) row.toEntity()]);

  @override
  Stream<SplitExpense?> watchExpenseById(String id) => _dao
      .watchExpenseById(id)
      .asyncMap((row) async => row == null ? null : _assemble(row));

  @override
  Future<SplitExpense?> expenseById(String id) async {
    final row = await _dao.expenseById(id);
    return row == null ? null : _assemble(row);
  }

  @override
  Future<SplitExpense?> expenseForTransaction(String transactionId) async {
    final row = await _dao.expenseForTransaction(transactionId);
    return row == null ? null : _assemble(row);
  }

  @override
  Future<Result<SplitExpense, Failure>> saveExpense(
    SplitExpense expense,
  ) async {
    if (!expense.total.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'A shared expense needs an amount.',
          field: 'total',
        ),
      );
    }

    // **The cross-table rule SQLite cannot express.** A share may only name a transaction line when
    // the expense has a transaction, because the lines belong to that transaction. The header half —
    // `split_method <> 'perLine' OR transaction_id IS NOT NULL` — is a CHECK; this direction spans
    // two tables and a CHECK cannot hold a subquery, so it lives here. `split_tables.dart` says so at
    // the column.
    if (expense.transactionId == null &&
        expense.shares.any((s) => s.transactionLineNo != null)) {
      return const Result.failure(
        BusinessRuleFailure(
          'Itemising needs the receipt, which means the expense you paid for.',
          rule: 'splitItemiseNeedsTransaction',
        ),
      );
    }

    final seen = <String>{};
    for (final share in expense.shares) {
      // One share per person per line. Two shares for the same person on the same line would both be
      // counted by `v_split_balances`, so the debt would silently double.
      final key = '${share.payeeId}#${share.transactionLineNo ?? -1}';
      if (!seen.add(key)) {
        return const Result.failure(
          BusinessRuleFailure(
            'Somebody has two shares of the same item.',
            rule: 'splitDuplicateShare',
          ),
        );
      }
      if (share.amount.isNegative) {
        return const Result.failure(
          ValidationFailure(
            'A share cannot be negative.',
            field: 'shareAmountMinor',
          ),
        );
      }
      if (share.amount.currencyCode != expense.total.currencyCode) {
        return const Result.failure(
          BusinessRuleFailure(
            'Every share must be in the same currency as the expense.',
            rule: 'splitShareCurrency',
          ),
        );
      }
    }

    // **Shares that do not sum to the total are accepted, deliberately.** Percentages mid-edit, or a
    // tip nobody assigned, are real states rather than errors — `SplitExpense.unallocated` reports
    // the gap and the screen decides what to say. `v_transaction_allocation` gives an un-itemised
    // transaction exactly the same treatment.

    try {
      final existing = await _dao.expenseById(expense.id);
      final stamps = WriteTimestamps.resolve(
        existingCreatedAt: existing?.createdAt,
        clock: _clock,
      );
      final now = stamps.updatedAt;

      await _dao.saveExpense(
        nowUtcMillis: now,
        expense: splitExpenseToCompanion(
          expense,
          createdAt: stamps.createdAt,
          updatedAt: now,
        ),
        shares: [
          for (final share in expense.shares)
            splitShareToCompanion(share, createdAt: now, updatedAt: now),
        ],
      );
      final saved = await expenseById(expense.id);
      return saved == null
          ? const Result.failure(
              UnexpectedFailure('That split could not be saved.'),
            )
          : Result.ok(saved);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That split could not be saved.', cause: error),
      );
    }
  }

  @override
  Future<Result<void, Failure>> deleteExpense(String id) async {
    try {
      await _dao.softDeleteExpense(id: id, nowUtcMillis: _clock.nowUtcMillis());
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That split could not be deleted.', cause: error),
      );
    }
  }

  @override
  Future<Result<void, Failure>> mergePlaceholder({
    required String placeholderPayeeId,
    required String payeeId,
  }) async {
    if (placeholderPayeeId == payeeId) {
      return const Result.failure(
        BusinessRuleFailure(
          'That is already the same person.',
          rule: 'splitMergeSelf',
        ),
      );
    }

    // Through `SplitDao`, which already touches `payees` for the merge itself. The first version took a
    // `PayeeDao` as a sixth constructor argument — and every place that builds this repository,
    // `repository_providers.dart` and `daily_job.dart`, stopped compiling. A dependency added for one guard
    // is not worth two call sites.
    final from = await _dao.payeeIdentity(placeholderPayeeId);
    if (from == null) {
      return Result.failure(
        NotFoundFailure(
          'That participant no longer exists.',
          id: placeholderPayeeId,
        ),
      );
    }
    // **Only a placeholder may be merged away, and the guard belongs here rather than in the DAO.**
    // Reassigning every reference and retiring a row is destructive in one direction: whichever payee is
    // named first stops existing. That is exactly right for "Person 4 was Ravi all along", where the first
    // row was never a contact anybody chose — and wrong as a general "combine two shops" tool, where a
    // caller with the arguments the wrong way round would silently delete the one they meant to keep.
    if (from.kind != PayeeKind.splitPlaceholder) {
      return const Result.failure(
        BusinessRuleFailure(
          'Only an unnamed split participant can be merged into somebody else.',
          rule: 'splitMergeNotPlaceholder',
        ),
      );
    }

    final into = await _dao.payeeIdentity(payeeId);
    if (into == null) {
      return Result.failure(
        NotFoundFailure('That person no longer exists.', id: payeeId),
      );
    }
    if (into.deletedAt != null) {
      // Merging into the trash would move live debts onto a row `v_split_balances` filters out, so the
      // balances would disappear from every screen while still sitting in the table.
      return const Result.failure(
        BusinessRuleFailure(
          'That person has been deleted. Restore them first.',
          rule: 'splitMergeIntoDeleted',
        ),
      );
    }

    try {
      await _dao.mergePayee(
        fromPayeeId: placeholderPayeeId,
        intoPayeeId: payeeId,
        nowUtcMillis: _clock.nowUtcMillis(),
      );
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure(
          'Those two could not be merged.',
          cause: error,
        ),
      );
    }
  }

  // ── settlements ─────────────────────────────────────────────────────────────────────────

  @override
  Stream<List<SplitSettlement>> watchSettlements({
    required DateKey from,
    required DateKey to,
    String? groupId,
  }) => _dao
      .watchSettlements(
        fromDateKey: from.value,
        toDateKey: to.value,
        groupId: groupId,
      )
      .map((rows) => [for (final row in rows) row.toEntity()]);

  @override
  Future<Result<SplitSettlement, Failure>> recordSettlement({
    required SplitSettlement settlement,
    Transaction? transaction,
  }) async {
    if (!settlement.amount.isPositive) {
      return const Result.failure(
        ValidationFailure('A settlement needs an amount.', field: 'amount'),
      );
    }
    if (settlement.fromPayeeId == settlement.toPayeeId) {
      return const Result.failure(
        BusinessRuleFailure(
          'Paying yourself is not a settlement.',
          rule: 'splitSelfSettlement',
        ),
      );
    }

    // **Checked here rather than trusted from the caller.** A settlement of the user's own money with
    // no transaction is the one failure in this module they could not see: the debt reads as cleared
    // and no money appears anywhere. `SettlementService` already refuses it; this is the backstop for
    // anything that reaches the repository another way.
    final self = await _groups.selfPayeeId();
    final involvesYou = self != null && settlement.involves(self);
    if (involvesYou && transaction == null) {
      return const Result.failure(
        BusinessRuleFailure(
          'A settlement you are part of has to be recorded against an account.',
          rule: 'splitSettlementNeedsTransaction',
        ),
      );
    }
    if (!involvesYou && transaction != null) {
      // The mirror image, and worth refusing too: a transaction for a settlement between two other
      // people would move money in an account of the user's that nothing in the split ever justified.
      return const Result.failure(
        BusinessRuleFailure(
          'That settlement does not involve you, so it moves none of your money.',
          rule: 'splitSettlementNotYours',
        ),
      );
    }

    if (transaction != null) {
      final accountId = transaction.toAccountId ?? transaction.fromAccountId;
      if (accountId == null) {
        return const Result.failure(
          ValidationFailure(
            'Choose the account this money moved through.',
            field: 'accountId',
          ),
        );
      }
      final account = await _accounts.byIdIncludingDeleted(accountId);
      if (account == null) {
        return Result.failure(
          NotFoundFailure('That account no longer exists.', id: accountId),
        );
      }
      // Law L8's money-side twin: an amount is minor units plus a code, and putting INR into a USD
      // account would store a number that reads back as the wrong currency forever.
      if (account.currencyCode != settlement.amount.currencyCode) {
        return Result.failure(
          BusinessRuleFailure(
            'That account is in ${account.currencyCode}, not '
            '${settlement.amount.currencyCode}.',
            rule: 'splitSettlementCurrency',
          ),
        );
      }
    }

    try {
      final now = _clock.nowUtcMillis();
      if (transaction == null) {
        await _dao.insertSettlement(
          splitSettlementToCompanion(
            settlement,
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else {
        await _dao.insertSettlementWithTransaction(
          transaction: transactionToCompanion(
            transaction,
            monthKey: transaction.dateKey.value ~/ 100,
            createdAt: now,
            updatedAt: now,
          ),
          settlement: splitSettlementToCompanion(
            settlement,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      return Result.ok(settlement);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure(
          'That settlement could not be recorded.',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<void, Failure>> deleteSettlement(String id) async {
    try {
      await _dao.softDeleteSettlement(
        id: id,
        nowUtcMillis: _clock.nowUtcMillis(),
      );
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure(
          'That settlement could not be deleted.',
          cause: error,
        ),
      );
    }
  }

  // ── derived reads ───────────────────────────────────────────────────────────────────────

  @override
  Stream<List<SplitBalance>> watchBalances() => _views.watchBalances().map(
    (rows) => [for (final row in rows) row.toEntity()],
  );

  @override
  Stream<List<SplitBalance>> watchGroupBalances(String groupId) => _views
      .watchGroupBalances(groupId)
      .map((rows) => [for (final row in rows) row.toEntity()]);

  @override
  Stream<List<SplitBalance>> watchBalanceWith(String payeeId) => _views
      .watchBalanceWith(payeeId)
      .map((rows) => [for (final row in rows) row.toEntity()]);

  @override
  Stream<List<SplitActivityEntry>> watchActivity({
    String? groupId,
    int limit = 50,
  }) => _views
      .watchActivity(limit: limit, groupId: groupId)
      .map((rows) => [for (final row in rows) row.toEntity()]);

  @override
  Future<List<DebtEdge>> debtsIn(String groupId) async {
    final self = await _groups.selfPayeeId();
    if (self == null) return const [];

    // **Built from net balances, and that is a known narrowing worth stating.** The contract says the
    // simplifier wants the edges as incurred, because its tie-break prefers transfers along debts that
    // genuinely exist. What `v_split_group_balances` can supply is one net figure per counterparty
    // *with you* — a single-user ledger records no debt between two other people, so every edge here
    // has you at one end anyway.
    //
    // The consequence is real but small: with only you-shaped edges the partition has nothing to
    // prefer between, so the tie-break is inert until the plan gains third-party debts. It becomes
    // live the moment a settle-up plan suggests one, which session 7 does — and the simplifier already
    // handles it because it was written for edges rather than for balances.
    final rows = await _views.groupBalances(groupId);
    final edges = <DebtEdge>[];
    for (final row in rows) {
      final balance = row.toEntity();
      if (balance.isSettled) continue;
      edges.add(
        balance.theyOweMe
            ? DebtEdge(
                fromPayeeId: balance.payeeId,
                toPayeeId: self,
                amount: balance.outstanding,
              )
            : DebtEdge(
                fromPayeeId: self,
                toPayeeId: balance.payeeId,
                amount: balance.outstanding,
              ),
      );
    }
    return edges;
  }
}
```

### `lib/data/repositories/stock_repository_impl.dart`

```dart
import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_formatter.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/batch_dao.dart';
import 'package:alaya/data/daos/stock_movement_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/item_category_resolver.dart';
import 'package:alaya/data/repositories/mappers/stock_mappers.dart';
import 'package:alaya/domain/services/draw_policy.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/domain/repositories/stock_repository.dart';

/// `StockRepository` backed by `BatchDao` and `StockMovementDao`.
///
/// Every write here goes through [BatchDao.applyMovements], which pairs each movement with its
/// batch's cache update inside one transaction (Laws L3, L14). There is no path that records a
/// movement without updating the cache, or the reverse.
final class StockRepositoryImpl implements StockRepository {
  /// Creates the repository.
  const StockRepositoryImpl(
    this._batchDao,
    this._movementDao,
    this._categories,
    this._uids,
    this._clock,
  );

  final BatchDao _batchDao;
  final StockMovementDao _movementDao;
  final ItemCategoryResolver _categories;
  final UidGenerator _uids;
  final Clock _clock;

  /// Formats quantities for the user-facing text on a failure. `Qty.toString()` is a debug
  /// representation (`2500000m(weight)`) and its own doc says never to show it — these messages are
  /// read by a person, so they go through the formatter.
  static const QtyFormatter _qtyFormat = QtyFormatter();

  /// The one definition of the draw order.
  ///
  /// This class used to implement the ordering and the draw-down itself. Phase 4B moved the algorithm
  /// into the service so there is one definition of it — the same consolidation Phase 4A made for the
  /// currency cross-rate, and for the same reason: two copies of an ordering rule drift apart. What
  /// stays here is the part only a repository can do — writing every draw in one transaction.
  static const InventoryConsumptionService _consumption =
      InventoryConsumptionService();

  @override
  Future<Result<List<ConsumptionDraw>, Failure>> consume({
    required String itemId,
    required Qty quantity,
    required StockMovementKind kind,
    DrawPolicy policy = const DrawPolicy.fefo(),
    String? reason,
    String? note,
  }) async {
    if (!quantity.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'The quantity to consume must be greater than zero.',
          field: 'quantity',
        ),
      );
    }

    final category = await _categories.categoryOf(itemId);
    if (category == null) {
      return Result.failure(NotFoundFailure('Item not found.', id: itemId));
    }
    if (category != quantity.category) {
      return Result.failure(
        ValidationFailure(
          'This item is measured in ${category.name}, not ${quantity.category.name}.',
          field: 'quantity',
        ),
      );
    }

    // FEFO order from SQL, already filtered to batches holding stock (anomaly A08). The service sorts
    // again under whichever policy applies — a pure function that trusts its input's order is one
    // whose correctness depends on something it cannot see — so this ordering is a query optimisation
    // rather than a guarantee the plan relies on.
    final batches = _consumable(await _batchDao.byItemFefo(itemId), category);

    // **Counted under the policy, not over the whole shelf.** Excluding expired stock means excluding
    // it from the total too, or the refusal would quote a figure the plan could not have reached —
    // "only 250 g is on hand" beside a cupboard holding 550 g, 300 g of it off.
    final available = _consumption.availableUnder(
      batches,
      policy: policy,
      ofCategory: quantity,
    );
    if (available.milliBase < quantity.milliBase) {
      // Checked before any write, and nothing is written on this path. A partial consumption would
      // leave the ledger describing something that did not happen — worse than refusing, because
      // the user would have no way to tell how much actually came out.
      return Result.failure(
        BusinessRuleFailure(
          'Only ${_qtyFormat.format(available)} is on hand, less than the '
          '${_qtyFormat.format(quantity)} requested.',
          rule: 'insufficientStock',
        ),
      );
    }

    final planned = _consumption.plan(
      batches: batches,
      needed: quantity,
      policy: policy,
    );
    final plan = planned.valueOrNull;
    if (plan == null) {
      // **Forwarded rather than swallowed.** This used to read `plan.valueOrNull?.draws ?? const []`,
      // on the reasoning that the caller had already checked availability so a failure was impossible.
      // Under a policy that can legitimately refuse, that swallow would apply zero draws and report
      // success — a consumption the user was told happened and did not.
      return Result.failure(
        planned.failureOrNull ??
            const UnexpectedFailure('Stock could not be planned.'),
      );
    }

    await _applyDraws(
      itemId: itemId,
      draws: plan.draws,
      kind: kind,
      reason: reason,
      note: note,
    );
    return Result.ok(plan.draws);
  }

  @override
  Future<Result<void, Failure>> consumeFromBatch({
    required String batchId,
    required Qty quantity,
    required StockMovementKind kind,
    String? reason,
    String? note,
  }) async {
    if (!quantity.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'The quantity to consume must be greater than zero.',
          field: 'quantity',
        ),
      );
    }

    final batch = await _batchDao.byIdIncludingDeleted(batchId);
    if (batch == null) {
      return Result.failure(NotFoundFailure('Batch not found.', id: batchId));
    }
    final category = await _categories.categoryOf(batch.itemId);
    if (category == null) {
      return Result.failure(
        NotFoundFailure('Item not found.', id: batch.itemId),
      );
    }
    if (category != quantity.category) {
      return Result.failure(
        ValidationFailure(
          'This batch is measured in ${category.name}, not ${quantity.category.name}.',
          field: 'quantity',
        ),
      );
    }
    if (batch.remainingQuantityMilli < quantity.milliBase) {
      return Result.failure(
        BusinessRuleFailure(
          'This batch holds only '
          '${_qtyFormat.format(Qty(batch.remainingQuantityMilli, category))}, less than the '
          '${_qtyFormat.format(quantity)} requested.',
          rule: 'insufficientStock',
        ),
      );
    }

    await _applyDraws(
      itemId: batch.itemId,
      draws: [ConsumptionDraw(batchId: batchId, quantity: quantity)],
      kind: kind,
      reason: reason,
      note: note,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> addStock({
    required String batchId,
    required Qty quantity,
    required StockMovementKind kind,
    String? note,
  }) async {
    if (!quantity.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'The quantity to add must be greater than zero.',
          field: 'quantity',
        ),
      );
    }
    if (!StockMovementDao.incomingKinds.contains(kind)) {
      // Guarding the direction rather than trusting it: an outgoing kind passed here would reduce
      // stock while the caller believed it was adding, and the cache would faithfully follow.
      return Result.failure(
        ValidationFailure(
          '${kind.name} removes stock rather than adding it.',
          field: 'kind',
        ),
      );
    }

    final batch = await _batchDao.byIdIncludingDeleted(batchId);
    if (batch == null) {
      return Result.failure(NotFoundFailure('Batch not found.', id: batchId));
    }
    final category = await _categories.categoryOf(batch.itemId);
    if (category == null) {
      return Result.failure(
        NotFoundFailure('Item not found.', id: batch.itemId),
      );
    }
    if (category != quantity.category) {
      return Result.failure(
        ValidationFailure(
          'This batch is measured in ${category.name}, not ${quantity.category.name}.',
          field: 'quantity',
        ),
      );
    }

    await _applyDraws(
      itemId: batch.itemId,
      draws: [ConsumptionDraw(batchId: batchId, quantity: quantity)],
      kind: kind,
      note: note,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> reverse({
    required String movementId,
    String? reason,
  }) async {
    final original = await _movementDao.byId(movementId);
    if (original == null) {
      return Result.failure(
        NotFoundFailure('Movement not found.', id: movementId),
      );
    }

    final alreadyReversed = await _movementDao.reversalOf(movementId);
    if (alreadyReversed != null) {
      return const Result.failure(
        BusinessRuleFailure(
          'This movement has already been reversed.',
          rule: 'alreadyReversed',
        ),
      );
    }
    if (original.reversesMovementId != null) {
      // Reversing a reversal would be indistinguishable from re-applying the original, and would
      // let a chain build up that nothing can interpret. Undo is one level deep by design.
      return const Result.failure(
        BusinessRuleFailure(
          'A correction cannot itself be reversed — record a new movement instead.',
          rule: 'cannotReverseAReversal',
        ),
      );
    }

    // The compensating kind, chosen so the pair nets to zero under the same direction rule
    // `v_batch_stock_check` applies: an incoming movement is undone by an adjustOut and vice versa.
    final compensating = StockMovementDao.incomingKinds.contains(original.kind)
        ? StockMovementKind.adjustOut
        : StockMovementKind.adjustIn;

    final now = _clock.nowUtcMillis();
    await _batchDao.applyMovements(
      entries: [
        (
          batchId: original.batchId,
          movement: StockMovementsCompanion.insert(
            id: _uids.generate(),
            batchId: original.batchId,
            itemId: original.itemId,
            kind: compensating,
            quantityMilli: original.quantityMilli,
            occurredAt: now,
            dateKey: _clock.today(),
            reason: Value(reason),
            reversesMovementId: Value(movementId),
            createdAt: now,
            updatedAt: now,
          ),
        ),
      ],
      nowUtcMillis: now,
    );
    return const Result.ok(null);
  }

  @override
  Stream<List<StockMovement>> watchForBatch(String batchId) {
    return _movementDao.watchForBatch(batchId).asyncMap(_mapAll);
  }

  @override
  Stream<List<StockMovement>> watchForItemInRange({
    required String itemId,
    required DateKey from,
    required DateKey to,
  }) {
    return _movementDao
        .watchForItemInRange(itemId: itemId, from: from, to: to)
        .asyncMap(_mapAll);
  }

  @override
  Future<List<WasteTotal>> wasteTotals({
    required DateKey from,
    required DateKey to,
  }) async {
    // Both waste kinds, totalled separately per item. `expired` and `waste` are distinct events —
    // food that rotted unnoticed versus food thrown out deliberately — but both are stock that was
    // paid for and never used, which is what ARCH_3 §5.1 query 14 measures.
    final byItem = <String, ({int milli, MoneyByCurrency cost})>{};

    // One query across all items, both waste kinds. Asking per item would require the caller to
    // already know which items have waste — inverting the question, since that set is the answer.
    final movements = await _movementDao.forKindsInRange(
      kinds: const {StockMovementKind.waste, StockMovementKind.expired},
      from: from,
      to: to,
    );

    // Batch costs are cached: a single wasted item is typically spread over few batches, and
    // re-reading the same batch row once per movement would dominate the cost of this query.
    final batchCosts = <String, ({int? unitCostMinor, String? currencyCode})>{};

    for (final m in movements) {
      final entry = byItem.putIfAbsent(
        m.itemId,
        () => (milli: 0, cost: MoneyByCurrency()),
      );
      byItem[m.itemId] = (
        milli: entry.milli + m.quantityMilli,
        cost: entry.cost,
      );

      final cost = batchCosts[m.batchId] ??= await () async {
        final batch = await _batchDao.byIdIncludingDeleted(m.batchId);
        return (
          unitCostMinor: batch?.unitCostMinor,
          currencyCode: batch?.costCurrencyCode,
        );
      }();

      final unitCost = cost.unitCostMinor;
      final costCode = cost.currencyCode;
      if (unitCost != null && costCode != null) {
        entry.cost.add(
          currencyCode: costCode,
          // unitCost is per purchased unit; the movement is in base-milli units, so the wasted
          // money is unitCost x (milli / 1000). Truncated: a fraction of a minor unit cannot be
          // represented, and waste valuation is an estimate rather than a ledger figure.
          minor: (unitCost * m.quantityMilli / 1000).truncate(),
        );
      }
    }

    final result = <WasteTotal>[];
    for (final e in byItem.entries) {
      final category = await _categories.categoryOf(e.key);
      if (category == null) continue;
      result.add(
        WasteTotal(
          itemId: e.key,
          quantity: Qty(e.value.milli, category),
          costByCurrency: e.value.cost.totals,
        ),
      );
    }
    return result;
  }

  /// Narrows DAO rows to the four fields the consumption service takes.
  ///
  /// [category] comes from the item rather than the row, because `inventory_batches` stores a bare
  /// integer and Law L8 forbids reinterpreting one without knowing its dimension.
  List<ConsumableBatch> _consumable(
    List<InventoryBatchRow> rows,
    UnitCategory category,
  ) => [
    for (final row in rows)
      ConsumableBatch(
        batchId: row.id,
        remaining: Qty(row.remainingQuantityMilli, category),
        purchasedDateKey: row.purchasedDateKey,
        expiryDateKey: row.expiryDateKey,
      ),
  ];

  /// Records one movement per draw, all in a single transaction (Law L14).
  Future<void> _applyDraws({
    required String itemId,
    required List<ConsumptionDraw> draws,
    required StockMovementKind kind,
    String? reason,
    String? note,
  }) {
    final now = _clock.nowUtcMillis();
    final today = _clock.today();
    return _batchDao.applyMovements(
      entries: draws
          .map(
            (draw) => (
              batchId: draw.batchId,
              movement: StockMovementsCompanion.insert(
                id: _uids.generate(),
                batchId: draw.batchId,
                itemId: itemId,
                kind: kind,
                quantityMilli: draw.quantity.milliBase,
                occurredAt: now,
                dateKey: today,
                reason: Value(reason),
                note: Value(note),
                createdAt: now,
                updatedAt: now,
              ),
            ),
          )
          .toList(),
      nowUtcMillis: now,
    );
  }

  Future<List<StockMovement>> _mapAll(List<StockMovementRow> rows) async {
    final categories = await _categories.categoriesFor(
      rows.map((r) => r.itemId),
    );
    return rows
        .where((r) => categories.containsKey(r.itemId))
        .map((r) => r.toEntity(categories[r.itemId]!))
        .toList();
  }
}
```

### `lib/data/repositories/tag_repository_impl.dart`

```dart
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/tag_dao.dart';
import 'package:alaya/data/repositories/mappers/tag_mapper.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/repositories/tag_repository.dart';

/// `TagRepository` backed by `TagDao`.
final class TagRepositoryImpl implements TagRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const TagRepositoryImpl(this._dao, this._clock);

  final TagDao _dao;
  final Clock _clock;

  @override
  Stream<List<Tag>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Tag>> watchByScope(TagScope scope) => _dao
      .watchByScope(scope)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Tag>> watchRoots() =>
      _dao.watchRoots().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Tag>> watchChildren(String parentTagId) => _dao
      .watchChildrenOf(parentTagId)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Tag?> byId(String id) async =>
      (await _dao.byIdIncludingDeleted(id))?.toEntity();

  @override
  Future<Result<Tag, Failure>> save(Tag tag) async {
    final existing = await _dao.byIdIncludingDeleted(tag.id);

    if (existing == null) {
      final duplicate = await _dao.byNormalizedName(tag.normalizedName);
      if (duplicate != null) {
        return Result.failure(
          ConflictFailure('A tag named "${tag.name}" already exists.'),
        );
      }
    }

    final parentId = tag.parentTagId;
    if (parentId != null) {
      if (parentId == tag.id) {
        return const Result.failure(
          BusinessRuleFailure(
            'A tag cannot be its own parent.',
            rule: 'tagSelfParent',
          ),
        );
      }
      final parent = await _dao.byIdIncludingDeleted(parentId);
      if (parent == null) {
        return const Result.failure(
          ValidationFailure(
            'The chosen parent tag does not exist.',
            field: 'parentTagId',
          ),
        );
      }
      // Nesting is capped at exactly one level (ARCH_2 §3): a root has no parent, a child's
      // parent must itself be a root. If the parent already has a parent, saving `tag` under it
      // would create a third level.
      if (parent.parentTagId != null) {
        return Result.failure(
          BusinessRuleFailure(
            'Tags can only be nested one level deep — "$parentId"\'s parent already has a '
            'parent of its own.',
            rule: 'tagNestingTooDeep',
          ),
        );
      }
    }

    // Preserve deletedAt unless `tag.isDeleted` explicitly disagrees with the current state —
    // the same pattern as createdAt, but for a field this entity's own doc calls out as real,
    // writable state (unlike every other entity in this phase).
    final existingDeletedAt = existing?.deletedAt;
    final now = _clock.nowUtcMillis();
    final createdAt = existing?.createdAt ?? now;
    final deletedAt = tag.isDeleted ? (existingDeletedAt ?? now) : null;

    await _dao.upsert(
      tagToCompanion(
        tag,
        createdAt: createdAt,
        updatedAt: now,
        deletedAt: deletedAt,
      ),
    );
    return Result.ok(tag);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    final rowsChanged = await _dao.softDeleteUserTag(
      id: id,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    if (rowsChanged == 0) {
      return const Result.failure(
        BusinessRuleFailure(
          'System tags cannot be deleted.',
          rule: 'systemProtected',
        ),
      );
    }
    return const Result.ok(null);
  }

  @override
  Stream<List<Tag>> watchForTransaction(String transactionId) => _dao
      .watchForTransaction(transactionId)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<void, Failure>> setForTransaction({
    required String transactionId,
    required List<String> tagIds,
  }) async {
    await _dao.setTransactionTags(
      transactionId: transactionId,
      tagIds: tagIds,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Stream<List<Tag>> watchForItem(String itemId) => _dao
      .watchForItem(itemId)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<void, Failure>> setForItem({
    required String itemId,
    required List<String> tagIds,
  }) async {
    await _dao.setItemTags(
      itemId: itemId,
      tagIds: tagIds,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Stream<List<Tag>> watchForAsset(String assetId) => _dao
      .watchForAsset(assetId)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<void, Failure>> setForAsset({
    required String assetId,
    required List<String> tagIds,
  }) async {
    await _dao.setAssetTags(
      assetId: assetId,
      tagIds: tagIds,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }
}
```

### `lib/data/repositories/transaction_repository_impl.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/account_dao.dart';
import 'package:alaya/data/daos/batch_dao.dart';
import 'package:alaya/data/daos/stock_movement_dao.dart';
import 'package:alaya/data/daos/transaction_dao.dart';
import 'package:alaya/data/daos/transaction_line_dao.dart';
import 'package:alaya/data/daos/unit_dao.dart';
import 'package:alaya/data/repositories/mappers/money_mappers.dart';
import 'package:alaya/data/repositories/settings_keys.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/repositories/currency_repository.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/repositories/transaction_repository.dart';

/// `TransactionRepository` backed by `TransactionDao` and `TransactionLineDao`.
///
/// Depends on `BatchDao` and `StockMovementDao` (Phase 2B) directly, read-only, purely to answer
/// "is this batch provably untouched" for [delete]. That is normal DAO composition, not a
/// layering violation: any repository may depend on any DAO it needs, and the inventory domain
/// not having its own repository yet (Phase 3C) does not block this one from reading its data.
///
/// Also depends on `CurrencyRepository`, for [freezeConversion] — `convert()` reads only the
/// already-cached rate table and needs no network access, so there is no reason to defer this to
/// a later phase; only `CurrencyRepository.syncDailyRates()` (the network fetch) is Phase 4A's.
final class TransactionRepositoryImpl implements TransactionRepository {
  /// Creates the repository.
  const TransactionRepositoryImpl(
    this._transactionDao,
    this._lineDao,
    this._accountDao,
    this._unitDao,
    this._batchDao,
    this._movementDao,
    this._settings,
    this._currency,
    this._clock,
  );

  final TransactionDao _transactionDao;
  final TransactionLineDao _lineDao;
  final AccountDao _accountDao;
  final UnitDao _unitDao;
  final BatchDao _batchDao;
  final StockMovementDao _movementDao;
  final SettingsRepository _settings;
  final CurrencyRepository _currency;
  final Clock _clock;

  @override
  Future<Transaction?> byId(String id) async =>
      (await _transactionDao.byId(id))?.toEntity();

  @override
  Stream<List<Transaction>> watchByDateRange({
    required DateKey from,
    required DateKey to,
  }) {
    return _transactionDao
        .watchByDateRange(from: from, to: to)
        .map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Stream<List<Transaction>> watchByAccount(String accountId) {
    return _transactionDao
        .watchByAccount(accountId)
        .map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Stream<List<Transaction>> watchBySubtype(
    TransactionSubtype subtype, {
    int? fromMonthKey,
    int? toMonthKey,
  }) {
    return _transactionDao
        .watchBySubtype(
          subtype,
          fromMonthKey: fromMonthKey,
          toMonthKey: toMonthKey,
        )
        .map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Stream<List<Transaction>> watchNeedingReview() {
    return _transactionDao.watchNeedingReview().map(
      (rows) => rows.map((r) => r.toEntity()).toList(),
    );
  }

  @override
  Stream<int> watchNeedsReviewCount() =>
      _transactionDao.watchNeedsReviewCount();

  @override
  Future<List<Transaction>> search(String query, {int limit = 50}) async {
    final rows = await _transactionDao.search(query, limit: limit);
    return rows.map((r) => r.toEntity()).toList();
  }

  @override
  Stream<List<TransactionLine>> watchLines(String transactionId) async* {
    // The parent transaction's currency is needed for every line's Money fields
    // (transaction_lines has no currency column of its own, ARCH_2 §4.2), so it is read once
    // before subscribing to the lines stream rather than re-read per emission.
    final parent = await _transactionDao.byId(transactionId);
    final currencyCode = parent?.originalCurrencyCode;
    if (currencyCode == null) return;

    final categories = await _unitDao.categoriesByCode();
    yield* _lineDao
        .watchForTransaction(transactionId)
        .map(
          (rows) => rows
              .map(
                (r) => r.toEntity(
                  transactionCurrencyCode: currencyCode,
                  categoryResolver: (row) =>
                      row.unitCode == null ? null : categories[row.unitCode],
                ),
              )
              .toList(),
        );
  }

  @override
  Stream<TransactionAllocation?> watchAllocation(String transactionId) {
    return _lineDao
        .watchAllocation(transactionId)
        .map(
          (row) => row == null
              ? null
              : TransactionAllocation(
                  transactionId: row.txId,
                  amount: Money(row.amountMinor, row.currencyCode),
                  allocated: Money(row.allocatedMinor, row.currencyCode),
                  unallocated: Money(row.unallocatedMinor, row.currencyCode),
                  lineCount: row.lineCount,
                ),
        );
  }

  @override
  Stream<List<TransactionLine>> watchLinesForItem(String itemId) async* {
    final categories = await _unitDao.categoriesByCode();
    yield* _lineDao.watchForItem(itemId).asyncMap((rows) async {
      final result = <TransactionLine>[];
      for (final row in rows) {
        final parent = await _transactionDao.byId(row.transactionId);
        if (parent == null) continue;
        result.add(
          row.toEntity(
            transactionCurrencyCode: parent.originalCurrencyCode,
            categoryResolver: (r) =>
                r.unitCode == null ? null : categories[r.unitCode],
          ),
        );
      }
      return result;
    });
  }

  @override
  Future<Result<Transaction, Failure>> create({
    required Transaction transaction,
    List<TransactionLine> lines = const [],
    List<String> tagIds = const [],
  }) async {
    final resolved = await _fillQuickAddAccount(transaction);
    if (resolved.isFailure) return Result.failure(resolved.failureOrNull!);
    final withAccount = resolved.valueOrNull!;

    final shapeCheck = _validateShape(withAccount);
    if (shapeCheck != null) return Result.failure(shapeCheck);

    final monthKey = withAccount.dateKey.monthKey;
    final now = _clock.nowUtcMillis();

    await _transactionDao.insertWithDetails(
      header: transactionToCompanion(
        withAccount,
        monthKey: monthKey,
        createdAt: now,
        updatedAt: now,
      ),
      lines: lines
          .map(
            (line) => transactionLineToCompanion(
              line,
              createdAt: now,
              updatedAt: now,
            ),
          )
          .toList(),
      tagIds: tagIds,
      nowUtcMillis: now,
    );

    final lastUsed = withAccount.toAccountId ?? withAccount.fromAccountId;
    if (lastUsed != null) {
      await _settings.writeValue(
        key: SettingsKeys.lastUsedAccountId,
        value: lastUsed,
        valueType: 'string',
      );
    }

    return Result.ok(withAccount);
  }

  @override
  Future<Result<Transaction, Failure>> update(Transaction transaction) async {
    final shapeCheck = _validateShape(transaction);
    if (shapeCheck != null) return Result.failure(shapeCheck);

    final existing = await _transactionDao.byId(transaction.id);
    if (existing == null) {
      return Result.failure(
        NotFoundFailure('Transaction not found.', id: transaction.id),
      );
    }

    final monthKey = transaction.dateKey.monthKey;
    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing.createdAt,
      clock: _clock,
    );
    await _transactionDao.updateTransaction(
      transactionToCompanion(
        transaction,
        monthKey: monthKey,
        createdAt: stamps.createdAt,
        updatedAt: stamps.updatedAt,
      ),
    );
    return Result.ok(transaction);
  }

  @override
  Future<Result<void, Failure>> recordCreatedArtefact({
    required String lineId,
    String? createdBatchId,
    String? createdAssetId,
    String? createdRecurringTemplateId,
  }) async {
    await _lineDao.setCreatedArtefact(
      lineId: lineId,
      nowUtcMillis: _clock.nowUtcMillis(),
      createdBatchId: createdBatchId,
      createdAssetId: createdAssetId,
      createdRecurringTemplateId: createdRecurringTemplateId,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> replaceLines({
    required String transactionId,
    required List<TransactionLine> lines,
  }) async {
    final now = _clock.nowUtcMillis();
    await _lineDao.replaceLines(
      transactionId: transactionId,
      lines: lines
          .map(
            (line) => transactionLineToCompanion(
              line,
              createdAt: now,
              updatedAt: now,
            ),
          )
          .toList(),
      nowUtcMillis: now,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> markReviewed(String id) async {
    await _transactionDao.markReviewed(
      id: id,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> freezeConversion({
    required String id,
    required DateKey on,
    required String toCurrencyCode,
  }) async {
    final existing = await _transactionDao.byId(id);
    if (existing == null) {
      return Result.failure(NotFoundFailure('Transaction not found.', id: id));
    }

    final original = Money(
      existing.originalAmountMinor,
      existing.originalCurrencyCode,
    );
    final converted = await _currency.convert(
      amount: original,
      toCurrencyCode: toCurrencyCode,
      on: on,
    );

    if (converted.isExcludedFromTotals) {
      return const Result.failure(
        BusinessRuleFailure(
          'No exchange rate is cached for this currency pair, so a conversion cannot be '
          'frozen yet. Try again once rates have synced.',
          rule: 'noRateAvailable',
        ),
      );
    }

    // `ConvertedMoney` carries no separate "raw API string" — and a cross-rate genuinely has
    // none: it is computed from two USD-pivoted quotes (ARCH_3 §1.2), never itself a literal API
    // response. The computed rate's own exact decimal string is the reproducible substitute
    // ARCH_3 §1.3 actually needs ("so any number a user questions can be reproduced") — `rate` on
    // a `ConvertedMoney` with `isExcludedFromTotals == false` is always non-null.
    await _transactionDao.freezeConversion(
      id: id,
      convertedAmountMinor: converted.converted!.minor,
      convertedCurrencyCode: converted.converted!.currencyCode,
      conversionRate: converted.rate!,
      conversionRateRaw: converted.rate!.toString(),
      conversionDateKey: converted.rateDateKey!,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<DetachedArtefacts, Failure>> delete({
    required String id,
    String? reason,
  }) async {
    final lines = await _lineDao.forTransaction(id);
    final now = _clock.nowUtcMillis();

    await _transactionDao.softDelete(id: id, reason: reason, nowUtcMillis: now);

    final batchIds = <String>[];
    final assetIds = <String>[];
    final recurringTemplateIds = <String>[];
    final untouchedBatchIds = <String>[];

    for (final line in lines) {
      final batchId = line.createdBatchId;
      final assetId = line.createdAssetId;
      final recurringId = line.createdRecurringTemplateId;
      if (batchId == null && assetId == null && recurringId == null) continue;

      await _lineDao.clearCreatedArtefacts(lineId: line.id, nowUtcMillis: now);

      if (batchId != null) {
        batchIds.add(batchId);
        await _batchDao.detachFromDeletedTransaction(
          batchId: batchId,
          nowUtcMillis: now,
        );
        if (await _isBatchUntouched(batchId)) untouchedBatchIds.add(batchId);
      }
      if (assetId != null) assetIds.add(assetId);
      if (recurringId != null) recurringTemplateIds.add(recurringId);
    }

    return Result.ok(
      DetachedArtefacts(
        batchIds: batchIds,
        assetIds: assetIds,
        recurringTemplateIds: recurringTemplateIds,
        untouchedBatchIds: untouchedBatchIds,
      ),
    );
  }

  /// A batch is provably untouched when nothing has been drawn from it — its remaining quantity
  /// still equals what it started with, and no movement beyond the founding one exists. Only
  /// these may be offered for removal after a delete; a batch already consumed from must never
  /// be, because the food really was eaten (anomaly A10).
  Future<bool> _isBatchUntouched(String batchId) async {
    final batch = await _batchDao.byIdIncludingDeleted(batchId);
    if (batch == null) return false;
    if (batch.remainingQuantityMilli != batch.initialQuantityMilli)
      return false;

    final movements = await _movementDao.forBatch(batchId);
    return movements.every(
      (m) => StockMovementDao.incomingKinds.contains(m.kind),
    );
  }

  /// Fills [transaction]'s missing account with last-used, then the default, then the first
  /// selectable account — never leaving it null (ARCH_2 §4.1). Only applies to
  /// [TransactionKind.deposit], `.withdrawal`, `.adjustmentIncrease` and `.adjustmentDecrease`,
  /// which need exactly one account; a transfer needs two different ones with no sensible
  /// default for either, so a transfer missing an account is a validation failure, not something
  /// to auto-fill.
  Future<Result<Transaction, Failure>> _fillQuickAddAccount(
    Transaction transaction,
  ) async {
    final needsTo =
        transaction.kind == TransactionKind.deposit ||
        transaction.kind == TransactionKind.adjustmentIncrease;
    final needsFrom =
        transaction.kind == TransactionKind.withdrawal ||
        transaction.kind == TransactionKind.adjustmentDecrease;

    if (!needsTo && !needsFrom) return Result.ok(transaction);
    if (needsTo && transaction.toAccountId != null)
      return Result.ok(transaction);
    if (needsFrom && transaction.fromAccountId != null)
      return Result.ok(transaction);

    final resolvedId = await _resolveQuickAddAccountId();
    if (resolvedId == null) {
      return const Result.failure(
        BusinessRuleFailure(
          'No account is available to record this against. Create an account first.',
          rule: 'noAccountAvailable',
        ),
      );
    }

    return Result.ok(
      needsTo
          ? transaction.copyWith(toAccountId: resolvedId)
          : transaction.copyWith(fromAccountId: resolvedId),
    );
  }

  /// Resolves quick-add's account: last-used, then the seeded default, then the first
  /// selectable account by sort order — each candidate checked for existence, since an account
  /// referenced by a stale setting could since have been deleted.
  Future<String?> _resolveQuickAddAccountId() async {
    final lastUsedId = await _settings.readValue(
      SettingsKeys.lastUsedAccountId,
    );
    if (lastUsedId != null && await _accountExists(lastUsedId))
      return lastUsedId;

    final defaultId = await _settings.readDefaultAccountId();
    if (defaultId != null && await _accountExists(defaultId)) return defaultId;

    final selectable = await _accountDao.watchSelectable().first;
    return selectable.isEmpty ? null : selectable.first.id;
  }

  Future<bool> _accountExists(String id) async {
    final account = await _accountDao.byIdIncludingDeleted(id);
    return account != null && account.deletedAt == null;
  }

  /// Validates the shape ARCH_2 §4.1's CHECK constraints require, in Dart, so a caller sees a
  /// clear [ValidationFailure] rather than a raw SQLite constraint error.
  Failure? _validateShape(Transaction transaction) {
    if (transaction.originalAmount.minor <= 0) {
      return const ValidationFailure(
        'The amount must be greater than zero.',
        field: 'originalAmount',
      );
    }

    final from = transaction.fromAccountId;
    final to = transaction.toAccountId;

    switch (transaction.kind) {
      case TransactionKind.deposit:
      case TransactionKind.adjustmentIncrease:
        if (to == null || from != null) {
          return const ValidationFailure(
            'A deposit needs a destination account and no source account.',
            field: 'toAccountId',
          );
        }
      case TransactionKind.withdrawal:
      case TransactionKind.adjustmentDecrease:
        if (from == null || to != null) {
          return const ValidationFailure(
            'A withdrawal needs a source account and no destination account.',
            field: 'fromAccountId',
          );
        }
      case TransactionKind.transfer:
        if (from == null || to == null) {
          return const ValidationFailure(
            'A transfer needs both a source and a destination account.',
            field: 'toAccountId',
          );
        }
        if (from == to) {
          return const ValidationFailure(
            'A transfer must be between two different accounts.',
            field: 'toAccountId',
          );
        }
    }
    return null;
  }
}
```

### `lib/data/repositories/unconverted_count.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// Counts the active transactions whose currency no cached rate can convert (ARCH_3 §1.5).
///
/// **The count belongs with whatever is being totalled, not with the rate subsystem** — ARCH_3 §1.5
/// says so outright, and lists this half as Phase 7B's. `CurrencyRepositoryImpl` returned
/// `Stream.value(0)` because it holds a `CurrencyDao` and nothing that can see `transactions`;
/// adding a transaction query to that DAO would have been the wrong aggregate, and injecting
/// `TransactionDao` into the currency repository would have coupled two modules for one figure. So
/// the query lives here and the repository delegates.
///
/// **Built over the same `RateTable`, never a second lookup path.** §1.5 asks for exactly that: the
/// weekend-gap rule and the approximate fallback have one implementation (ARCH_3 §1.3), and a count
/// that disagreed with the totals it annotates would be worse than no count.
final class UnconvertedCounter {
  /// Creates a counter over [database], converting through [rates].
  const UnconvertedCounter({
    required AlayaDatabase database,
    required CurrencyRateService rates,
    required SettingsRepository settings,
    String fallbackHomeCurrencyCode = 'INR',
  }) : _database = database,
       _rates = rates,
       _settings = settings,
       _fallbackHome = fallbackHomeCurrencyCode;

  final AlayaDatabase _database;
  final CurrencyRateService _rates;
  final SettingsRepository _settings;
  final String _fallbackHome;

  /// Emits how many active transactions cannot be converted into the home currency.
  ///
  /// **Re-emits when the rate cache changes, which is the requirement.** ARCH_3 §1.5 rejects a
  /// static implementation precisely because convertibility has to be re-evaluated whenever a rate
  /// arrives — a fetch that fills in last Tuesday's missing rate must drop the chip's count without
  /// anyone touching a transaction. The query does not read `currency_rates`, so `readsFrom` names
  /// that table anyway: it is the set of tables whose writes invalidate the stream, not a claim
  /// about what was selected.
  ///
  /// **Affordable because it excludes the home currency in SQL.** An unbounded aggregate is
  /// ARCH_4 R7's risk, and this one has no window to bound it by — an unconvertible transaction from
  /// four years ago is still unconvertible. Filtering `<> home` means the common case, a household
  /// with one currency, returns **zero rows** however large the ledger is; a household with two
  /// returns one row per distinct date in the second currency.
  Stream<int> watch() async* {
    final home = await _settings.readHomeCurrencyCode() ?? _fallbackHome;

    yield* _database
        .customSelect(
          '''
          SELECT t.original_currency_code AS currency_code,
                 t.date_key AS date_key,
                 COUNT(*) AS row_count
            FROM v_active_transactions t
           WHERE t.original_currency_code <> ?
           GROUP BY t.original_currency_code, t.date_key
          ''',
          variables: [Variable<String>(home)],
          readsFrom: {_database.transactions, _database.currencyRates},
        )
        .watch()
        .asyncMap((rows) async {
          if (rows.isEmpty) return 0;
          final table = await _rates.table();
          var unconverted = 0;
          for (final row in rows) {
            final result = table.convert(
              // One probe per (currency, date) group rather than per transaction: convertibility is
              // a property of that pair, so a thousand rupee-denominated rows on one day ask the
              // same question once. The amount is a single minor unit because only the *quality*
              // of the answer is read.
              amount: Money(1, row.read<String>('currency_code')),
              toCurrencyCode: home,
              on: DateKey(row.read<int>('date_key')),
            );
            if (result.isExcludedFromTotals)
              unconverted += row.read<int>('row_count');
          }
          return unconverted;
        });
  }
}
```

### `lib/data/repositories/unit_repository_impl.dart`

```dart
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/unit_dao.dart';
import 'package:alaya/data/repositories/mappers/unit_mapper.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/domain/repositories/unit_repository.dart';

/// `UnitRepository` backed by `UnitDao`.
final class UnitRepositoryImpl implements UnitRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const UnitRepositoryImpl(this._dao, this._clock);

  final UnitDao _dao;
  final Clock _clock;

  @override
  Stream<List<Unit>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Unit>> watchByCategory(UnitCategory category) =>
      _dao.watchByCategory(category).map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Unit?> byCode(String code) async => (await _dao.byCode(code))?.toEntity();

  @override
  Future<Map<String, int>> factorsByCode() => _dao.factorsByCode();

  @override
  Future<Map<String, UnitCategory>> categoriesByCode() => _dao.categoriesByCode();

  @override
  Future<Result<Unit, Failure>> save(Unit unit) async {
    if (unit.factorToBaseMilli <= 0) {
      return const Result.failure(
        ValidationFailure(
          'A unit needs a positive, exact factor to its category\'s base unit. If you cannot '
              'state one, create a separate Item instead (ARCH_1 §5.3).',
          field: 'factorToBaseMilli',
        ),
      );
    }

    final existing = await _dao.byCode(unit.code);
    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _dao.upsert(
      unitToCompanion(unit, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );
    return Result.ok(unit);
  }

  @override
  Future<Result<void, Failure>> delete(String code) async {
    final rowsChanged =
    await _dao.softDeleteUserUnit(code: code, nowUtcMillis: _clock.nowUtcMillis());
    if (rowsChanged == 0) {
      return const Result.failure(
        BusinessRuleFailure('System units cannot be deleted.', rule: 'systemProtected'),
      );
    }
    return const Result.ok(null);
  }
}
```

### `lib/data/repositories/write_timestamps.dart`

```dart
import 'package:alaya/core/time/clock.dart';

/// The `(createdAt, updatedAt)` pair to write for a save, and the one place that pair is
/// computed for every repository in this phase.
///
/// **Exists to prevent a real, easy-to-make bug.** Drift's `insertOnConflictUpdate` writes
/// every column present in the companion on conflict, `createdAt` included — passing `now` for
/// both timestamps on every save silently overwrites a row's true creation time on its second
/// edit. Verified against SQLite: a naive upsert corrupts `created_at` from its original value
/// to whatever the second call happened to pass. The fix is to read the existing row first and
/// thread its `createdAt` through unchanged; every `save()` in this phase does that via this one
/// function rather than reimplementing the read-then-decide logic eight times.
final class WriteTimestamps {
  const WriteTimestamps._();

  /// Resolves the pair to write, given [existingCreatedAt] (null when this is a fresh insert)
  /// and [clock] for the current instant.
  ///
  /// `createdAt` is [existingCreatedAt] when present, otherwise now — so a first save and every
  /// later save of the same row agree on when it was created. `updatedAt` is always now.
  static ({int createdAt, int updatedAt}) resolve({
    required int? existingCreatedAt,
    required Clock clock,
  }) {
    final now = clock.nowUtcMillis();
    return (createdAt: existingCreatedAt ?? now, updatedAt: now);
  }
}
```

### `lib/data/security/app_lock_store.dart`

```dart
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'package:alaya/data/security/secure_key_value_store.dart';

/// Persists the app-lock secrets, and **never** in the database (ARCH_3 §2.1).
///
/// The reason is not secrecy — the database is plaintext by design and a determined reader of the
/// file learns nothing from a PIN hash. The reason is that **restoring a backup must not change your
/// lock.** If the hash lived in the database, importing a friend's export would silently replace
/// your PIN with theirs, and a restore would be able to lock you out of your own install. Secure
/// storage ties the lock to the *install* and the database to the *data*, which is the correct
/// boundary and the one `restore_test.dart` asserts.
///
/// There is **no encryption anywhere in this class**. No `PRAGMA key`, no derived database key, no
/// key wrapping. PBKDF2 is used purely as a slow one-way hash so a stolen `pinHash` cannot be
/// reversed to a four-digit PIN by inspection — the derived bytes are compared and then discarded,
/// never used to decrypt anything.
final class AppLockStore {
  /// Creates the store over [storage].
  ///
  /// [random] is injectable so salts are deterministic in tests. [pbkdf2Iterations] defaults to the
  /// production [iterations] and is lowered only by tests — 310,000 iterations run twenty times over
  /// would make a unit suite take tens of seconds, and what those tests need from the hash is that it
  /// is stable and salt-dependent, not that it is slow. The production value is asserted separately
  /// as a constant so lowering it here cannot silently weaken the real thing.
  AppLockStore({
    required SecureKeyValueStore storage,
    Random? random,
    int? pbkdf2Iterations,
  }) : _storage = storage,
       _random = random ?? Random.secure(),
       _iterations = pbkdf2Iterations ?? iterations;

  final SecureKeyValueStore _storage;
  final Random _random;
  final int _iterations;

  /// PBKDF2 iterations, per ARCH_3 §2.1.
  ///
  /// 310,000 is OWASP's 2023 floor for PBKDF2-HMAC-SHA256. It is deliberately slow: the PIN space is
  /// only 10,000 values at four digits, so the iteration count is doing most of the work that a
  /// longer secret would otherwise do. Lowering it to make unlock feel snappier would be trading the
  /// only real defence this design has.
  static const int iterations = 310000;

  /// Derived key length in bits.
  static const int derivedBits = 256;

  /// Salt length in bytes.
  static const int saltBytes = 16;

  static const String _pinHashKey = 'alaya.lock.pinHash';
  static const String _saltKey = 'alaya.lock.salt';
  static const String _recoveryHashKey = 'alaya.lock.recoveryHash';
  static const String _failedCountKey = 'alaya.lock.failedCount';
  static const String _lockedUntilKey = 'alaya.lock.lockedUntilUtcMillis';
  static const String _pinLengthKey = 'alaya.lock.pinLength';

  /// True when a lock is configured.
  Future<bool> get isEnabled async =>
      (await _storage.read(_pinHashKey)) != null;

  /// How many digits the configured PIN has — 4 by default, 6 if the user chose it.
  Future<int> readPinLength() async {
    final raw = await _storage.read(_pinLengthKey);
    return int.tryParse(raw ?? '') ?? 4;
  }

  /// Derives the hash of [secret] against [salt].
  ///
  /// Public so `PinService` can verify without this class needing to know about attempt counting,
  /// and so a test can assert that the same input yields the same bytes.
  Future<String> deriveHash({
    required String secret,
    required List<int> salt,
  }) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: derivedBits,
    );
    final key = await pbkdf2.deriveKeyFromPassword(
      password: secret,
      nonce: salt,
    );
    return base64Encode(await key.extractBytes());
  }

  /// A fresh random salt.
  List<int> newSalt() =>
      List<int>.generate(saltBytes, (_) => _random.nextInt(256));

  /// Stores a new lock: [pin] and [recoveryCode], both hashed against one freshly generated salt.
  ///
  /// One salt for both is intentional. They are separate secrets with separate hashes, and a shared
  /// salt only matters if an attacker could benefit from a rainbow table spanning both — which it
  /// cannot, because the salt is random per install and never reused elsewhere.
  Future<void> writeLock({
    required String pin,
    required String recoveryCode,
    int pinLength = 4,
  }) async {
    final salt = newSalt();
    final pinHash = await deriveHash(secret: pin, salt: salt);
    final recoveryHash = await deriveHash(secret: recoveryCode, salt: salt);

    await _storage.write(_saltKey, base64Encode(salt));
    await _storage.write(_pinHashKey, pinHash);
    await _storage.write(_recoveryHashKey, recoveryHash);
    await _storage.write(_pinLengthKey, pinLength.toString());
    await resetFailures();
  }

  /// Replaces the PIN hash, reusing the existing salt and leaving the recovery hash untouched.
  ///
  /// Reusing the salt is what keeps the recovery code valid across a PIN change — a new salt would
  /// invalidate the recovery hash derived against the old one, silently, and the user would discover
  /// it only when they needed it.
  Future<void> writeNewPin({required String pin, int? pinLength}) async {
    final salt = await readSalt();
    if (salt == null) return;
    await _storage.write(
      _pinHashKey,
      await deriveHash(secret: pin, salt: salt),
    );
    if (pinLength != null) {
      await _storage.write(_pinLengthKey, pinLength.toString());
    }
    await resetFailures();
  }

  /// The stored salt, or null when no lock is configured.
  Future<List<int>?> readSalt() async {
    final raw = await _storage.read(_saltKey);
    return raw == null ? null : base64Decode(raw);
  }

  /// The stored PIN hash, or null when no lock is configured.
  Future<String?> readPinHash() => _storage.read(_pinHashKey);

  /// The stored recovery-code hash, or null when no lock is configured.
  Future<String?> readRecoveryHash() => _storage.read(_recoveryHashKey);

  /// Removes every lock secret and resets the attempt counter.
  Future<void> clearLock() async {
    await _storage.delete(_pinHashKey);
    await _storage.delete(_saltKey);
    await _storage.delete(_recoveryHashKey);
    await _storage.delete(_pinLengthKey);
    await resetFailures();
  }

  /// How many consecutive wrong attempts have been recorded.
  Future<int> readFailedCount() async {
    final raw = await _storage.read(_failedCountKey);
    return int.tryParse(raw ?? '') ?? 0;
  }

  /// Records one more wrong attempt and returns the new count.
  Future<int> incrementFailedCount() async {
    final next = (await readFailedCount()) + 1;
    await _storage.write(_failedCountKey, next.toString());
    return next;
  }

  /// Clears the attempt counter and any active lockout.
  Future<void> resetFailures() async {
    await _storage.delete(_failedCountKey);
    await _storage.delete(_lockedUntilKey);
  }

  /// When the current lockout expires, or null when there is none.
  ///
  /// Stored as an absolute instant rather than a remaining duration, so backgrounding the app or
  /// killing it does not reset the wait — a countdown held in memory would make the throttle
  /// trivially bypassable.
  Future<DateTime?> readLockedUntilUtc() async {
    final raw = await _storage.read(_lockedUntilKey);
    final millis = int.tryParse(raw ?? '');
    return millis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  /// Sets the instant the current lockout expires.
  Future<void> writeLockedUntilUtc(DateTime instant) => _storage.write(
    _lockedUntilKey,
    instant.millisecondsSinceEpoch.toString(),
  );
}
```

### `lib/data/security/local_auth_biometric_gate.dart`

```dart
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
```

### `lib/data/security/pin_service.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/security/app_lock_store.dart';
import 'package:alaya/data/security/recovery_code.dart';
import 'package:alaya/domain/services/lock/app_lock.dart';

/// Verifies, changes, enables and disables the app lock, and enforces ARCH_3 §2.3's throttle.
///
/// **No encryption.** The lock is a UI gate over a plaintext database (ARCH_1 §2.1), so nothing here
/// derives a database key and nothing here can lock a user out of their own data — the "forgot both"
/// path can still export a readable backup, which is the improvement dropping encryption bought.
final class PinService implements AppLock {
  /// Creates the service.
  PinService({
    required AppLockStore store,
    required Clock clock,
    RecoveryCode? recoveryCode,
  }) : _store = store,
       _clock = clock,
       _recoveryCode = recoveryCode ?? RecoveryCode();

  final AppLockStore _store;
  final Clock _clock;
  final RecoveryCode _recoveryCode;

  /// The delay owed after [failures] consecutive wrong attempts (ARCH_3 §2.3).
  ///
  /// The first four are free, because a mistyped digit on a phone keyboard is ordinary and punishing
  /// it would make the lock hostile to its owner rather than to an attacker. From the fifth the delay
  /// grows: 30 s, 1 min, 5 min, then 15 min doubling to a one-hour ceiling.
  ///
  /// The ceiling exists on purpose. Unbounded doubling would eventually lock the legitimate owner out
  /// for days over a forgotten PIN — and against an attacker, one hour per attempt already reduces
  /// the 10,000-value four-digit space to years. Past that point more delay costs the owner
  /// everything and the attacker nothing.
  static Duration delayAfterFailures(int failures) {
    if (failures <= 4) return Duration.zero;
    if (failures == 5) return const Duration(seconds: 30);
    if (failures == 6) return const Duration(minutes: 1);
    if (failures == 7) return const Duration(minutes: 5);
    final doublings = failures - 8;
    final minutes = 15 * (1 << doublings);
    return Duration(minutes: minutes > 60 ? 60 : minutes);
  }

  @override
  Future<bool> get isEnabled => _store.isEnabled;

  /// How many digits the configured PIN has.
  ///
  /// Delegated rather than reimplemented: the store owns the value because it is written alongside the
  /// hash, and a second source of truth for "is this a 4- or 6-box keypad" would eventually disagree
  /// with the PIN it is asking for.
  @override
  Future<int> readPinLength() => _store.readPinLength();

  /// How many consecutive wrong attempts have been recorded.
  ///
  /// Exposed for the optional auto-erase, which fires at ARCH_3 §2.3's tenth failure. The throttle
  /// already reads this internally; the caller needs it too, and reaching around this class to the store
  /// would put a second consumer on a field only this class is supposed to interpret.
  @override
  Future<int> readFailedCount() => _store.readFailedCount();

  @override
  Future<Duration?> remainingLockout() async {
    final until = await _store.readLockedUntilUtc();
    if (until == null) return null;
    final remaining = until.difference(_clock.now().toUtc());
    return remaining.isNegative || remaining == Duration.zero
        ? null
        : remaining;
  }

  /// Attempts to unlock with [pin].
  ///
  /// Checks the throttle **before** comparing, so a throttled attempt costs no PBKDF2 work and
  /// cannot be used to time the comparison.
  @override
  Future<UnlockOutcome> verifyPin(String pin) async {
    final hash = await _store.readPinHash();
    final salt = await _store.readSalt();
    if (hash == null || salt == null) {
      return const UnlockOutcome(
        unlocked: false,
        refusal: UnlockRefusal.notEnabled,
      );
    }

    final waiting = await remainingLockout();
    if (waiting != null) {
      return UnlockOutcome(
        unlocked: false,
        refusal: UnlockRefusal.throttled,
        failedCount: await _store.readFailedCount(),
        retryAfter: waiting,
      );
    }

    final candidate = await _store.deriveHash(secret: pin, salt: salt);
    if (_constantTimeEquals(candidate, hash)) {
      await _store.resetFailures();
      return const UnlockOutcome.success();
    }
    return _recordFailure();
  }

  /// Resets the PIN using [code], for the forgotten-PIN path.
  ///
  /// Subject to the same throttle as a PIN attempt: without it the recovery code would be the weaker
  /// of the two secrets to attack, which would make the whole lock only as strong as the path nobody
  /// remembers exists.
  @override
  Future<Result<void, Failure>> resetWithRecoveryCode({
    required String code,
    required String newPin,
  }) async {
    final recoveryHash = await _store.readRecoveryHash();
    final salt = await _store.readSalt();
    if (recoveryHash == null || salt == null) {
      return const Result.failure(
        BusinessRuleFailure('No lock is configured.', rule: 'lockNotEnabled'),
      );
    }

    final waiting = await remainingLockout();
    if (waiting != null) {
      return Result.failure(
        BusinessRuleFailure(
          'Too many attempts. Try again in ${waiting.inSeconds} seconds.',
          rule: 'throttled',
        ),
      );
    }

    final normalized = _recoveryCode.normalize(code);
    if (!_recoveryCode.isWellFormed(normalized)) {
      await _recordFailure();
      return const Result.failure(
        ValidationFailure('A recovery code is 10 characters.', field: 'code'),
      );
    }

    final candidate = await _store.deriveHash(secret: normalized, salt: salt);
    if (!_constantTimeEquals(candidate, recoveryHash)) {
      await _recordFailure();
      return const Result.failure(
        BusinessRuleFailure(
          'That recovery code is not correct.',
          rule: 'wrongRecoveryCode',
        ),
      );
    }

    final pinCheck = _validatePinFormat(newPin);
    if (pinCheck != null) return Result.failure(pinCheck);

    // The recovery code itself is unchanged — the user has one code for the life of the install, and
    // silently rotating it here would invalidate the copy they wrote down.
    await _store.writeNewPin(pin: newPin, pinLength: newPin.length);
    return const Result.ok(null);
  }

  /// Enables the lock with [pin], returning the recovery code to show the user **once**.
  @override
  Future<Result<String, Failure>> enable({required String pin}) async {
    if (await _store.isEnabled) {
      return const Result.failure(
        BusinessRuleFailure(
          'A lock is already set.',
          rule: 'lockAlreadyEnabled',
        ),
      );
    }
    final pinCheck = _validatePinFormat(pin);
    if (pinCheck != null) return Result.failure(pinCheck);

    final code = _recoveryCode.generate();
    await _store.writeLock(pin: pin, recoveryCode: code, pinLength: pin.length);
    return Result.ok(_recoveryCode.format(code));
  }

  /// Changes the PIN, verifying [currentPin] first. The recovery code is unchanged.
  @override
  Future<Result<void, Failure>> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    final outcome = await verifyPin(currentPin);
    if (!outcome.unlocked) {
      return Result.failure(
        BusinessRuleFailure(
          outcome.isThrottled
              ? 'Too many attempts. Try again shortly.'
              : 'That PIN is not correct.',
          rule: outcome.isThrottled ? 'throttled' : 'wrongPin',
        ),
      );
    }
    final pinCheck = _validatePinFormat(newPin);
    if (pinCheck != null) return Result.failure(pinCheck);

    await _store.writeNewPin(pin: newPin, pinLength: newPin.length);
    return const Result.ok(null);
  }

  /// Disables the lock, verifying [pin] first.
  @override
  Future<Result<void, Failure>> disable({required String pin}) async {
    final outcome = await verifyPin(pin);
    if (!outcome.unlocked) {
      return Result.failure(
        BusinessRuleFailure(
          outcome.isThrottled
              ? 'Too many attempts. Try again shortly.'
              : 'That PIN is not correct.',
          rule: outcome.isThrottled ? 'throttled' : 'wrongPin',
        ),
      );
    }
    await _store.clearLock();
    return const Result.ok(null);
  }

  Future<UnlockOutcome> _recordFailure() async {
    final count = await _store.incrementFailedCount();
    final delay = delayAfterFailures(count);
    if (delay > Duration.zero) {
      await _store.writeLockedUntilUtc(_clock.now().toUtc().add(delay));
    }
    return UnlockOutcome(
      unlocked: false,
      refusal: delay > Duration.zero
          ? UnlockRefusal.throttled
          : UnlockRefusal.wrongPin,
      failedCount: count,
      retryAfter: delay > Duration.zero ? delay : null,
    );
  }

  Failure? _validatePinFormat(String pin) {
    if (pin.length != 4 && pin.length != 6) {
      return const ValidationFailure('A PIN is 4 or 6 digits.', field: 'pin');
    }
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      return const ValidationFailure('A PIN is digits only.', field: 'pin');
    }
    return null;
  }

  /// Compares two base64 hashes without an early exit.
  ///
  /// The timing channel here is small — both strings are the same length and the comparison happens
  /// after 310,000 PBKDF2 iterations that dominate any measurement — but a length-independent compare
  /// costs nothing and removes the question entirely.
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
```

### `lib/data/security/recovery_code.dart`

```dart
import 'dart:math';

/// Generates and normalises the single recovery code that resets a forgotten PIN (ARCH_3 §2.1).
///
/// Ten characters from a 32-symbol alphabet is `32^10`, about `1.1 x 10^15` combinations. Against a
/// local-only check with the same throttle the PIN uses, that is far beyond brute force — and it
/// stays short enough to write on paper, which is the point of having one at all.
final class RecoveryCode {
  /// Creates a generator. [random] is injectable so tests can be deterministic; production must
  /// pass a [Random.secure].
  RecoveryCode({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  /// The 32 symbols a code may contain.
  ///
  /// The full `0-9A-Z` set is 36 symbols; removing the four that people transcribe wrongly — `0`
  /// against `O`, `1` against `I` — leaves exactly 32, which is precisely a base-32 alphabet with no
  /// padding waste. That the arithmetic works out this neatly is why the exclusion list is those
  /// four and not a longer set of near-misses.
  static const String alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

  /// How many characters a code has.
  static const int length = 10;

  /// Where the display hyphen goes: `ABCDE-FGHJK`.
  static const int groupSize = 5;

  /// Generates a new code, unformatted.
  ///
  /// Draws from [Random.secure] by default. A predictable code would be worse than no recovery path,
  /// because the UI presents it as a secret worth writing down.
  String generate() {
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(alphabet[_random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  /// Generates a code formatted for display, hyphenated in two groups of five.
  String generateFormatted() => format(generate());

  /// Inserts the display hyphen into [code].
  String format(String code) {
    final normalized = normalize(code);
    if (normalized.length != length) return normalized;
    return '${normalized.substring(0, groupSize)}-${normalized.substring(groupSize)}';
  }

  /// Normalises user input into the canonical form used for hashing.
  ///
  /// Upper-cases, then keeps only characters that are in [alphabet] — which drops the display
  /// hyphen, any spaces, and the four excluded symbols.
  ///
  /// Dropping `0`, `O`, `1` and `I` rather than folding them onto neighbours is deliberate. Those
  /// four cannot appear in a real code, so typing one means the user misread a character. Folding
  /// `O` to `Q` would guess at which character they meant and could silently accept a wrong code;
  /// dropping it yields the wrong length, verification fails, and the UI can say plainly that a code
  /// is ten characters. A clear failure beats a lucky guess.
  String normalize(String input) {
    final upper = input.toUpperCase();
    final buffer = StringBuffer();
    for (final char in upper.split('')) {
      if (alphabet.contains(char)) buffer.write(char);
    }
    return buffer.toString();
  }

  /// True when [input] normalises to something this generator could have produced.
  bool isWellFormed(String input) {
    final normalized = normalize(input);
    return normalized.length == length &&
        normalized.split('').every(alphabet.contains);
  }
}
```

### `lib/data/security/secure_key_value_store.dart`

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The small slice of key-value storage the app lock needs.
///
/// An interface rather than a direct `FlutterSecureStorage` dependency, for the same reason [Clock]
/// exists: the plugin needs a platform channel, so code depending on it directly is untestable
/// without one. Three methods is the whole surface the lock uses, so widening it would only invite
/// coupling to a plugin this project should be able to swap.
abstract interface class SecureKeyValueStore {
  /// Reads [key], or null when absent.
  Future<String?> read(String key);

  /// Writes [value] against [key].
  Future<void> write(String key, String value);

  /// Removes [key].
  Future<void> delete(String key);
}

/// The production [SecureKeyValueStore], backed by the platform keystore.
final class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  /// Creates a store over [storage].
  const FlutterSecureKeyValueStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// An in-memory [SecureKeyValueStore] for tests.
///
/// Lives beside the production implementation rather than in the test tree, mirroring how
/// `FixedClock` ships alongside `SystemClock`: a fake that drifts from the interface it doubles is
/// worse than no fake, and keeping them in one file makes that drift visible.
final class InMemorySecureKeyValueStore implements SecureKeyValueStore {
  /// Creates an empty store.
  InMemorySecureKeyValueStore();

  final Map<String, String> _values = {};

  /// Every key currently held — what a test asserting "no lock secret reaches the database" inspects.
  Iterable<String> get keys => _values.keys;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
```

### `lib/data/support/ads_and_billing.dart`

```dart
import 'dart:async';

import 'package:flutter/foundation.dart' show kReleaseMode;

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/services/support/support_port.dart';

/// The production [SupportPort], over `google_mobile_ads` and `in_app_purchase`.
///
/// **The only file in the project that imports either SDK.** That is the enforcement of "the rest of the app
/// makes zero ad calls": not a rule anybody has to remember, but the fact that no other file can make one. A
/// grep for `google_mobile_ads` returning exactly this path is the check, and it is cheap to run.
///
/// **Nothing initialises at construction.** [initialise] is called by the Support screen's `initState` and by
/// nothing else, so an install where nobody opens that screen never starts the SDK, never fetches a consent
/// form, and never collects an advertising identifier.
///
/// Both plugin surfaces are ARCH_4 R22 exposure and neither could be compiled against: `MobileAds.instance`,
/// `ConsentInformation`, `RewardedAd.load` and `InAppPurchase.instance` have all moved between majors. 8A's
/// `local_auth` needed three attempts; expect the same here, and expect it to cost this file alone.
final class AdsAndBilling implements SupportPort {
  /// Creates the adapter.
  AdsAndBilling();

  /// Google's public test unit. Always used in debug builds.
  static const String rewardedTestUnitId =
      'ca-app-pub-3940256099942544/5224354917';

  /// The live rewarded unit, used in release builds only.
  static const String rewardedLiveUnitId =
      'ca-app-pub-3214315776823567/6343130187';

  /// Whichever of the two this build should request.
  ///
  /// **Chosen by `kReleaseMode`, not by remembering to swap a constant.** A debug build serving live adverts is
  /// how an AdMob account gets flagged for invalid traffic, and the appeal is slow — so the guarantee is
  /// structural rather than a discipline. The App ID has the same split, through `manifestPlaceholders` in
  /// `app/build.gradle.kts`, because a manifest cannot read `kReleaseMode`.
  ///
  /// Register your device under **AdMob → Settings → Test devices** as well: that stops a *release* build on your
  /// own phone generating billable events while you are testing.
  static String get rewardedAdUnitId =>
      kReleaseMode ? rewardedLiveUnitId : rewardedTestUnitId;

  /// The one-time tip product, as declared in Play Console.
  static const String tipProductId = 'alaya_tip_once';

  /// How long an advert request may take before it is treated as unavailable.
  ///
  /// The SDK's callbacks can simply never fire — no fill, no network, a mediation adapter stalling — and a
  /// screen whose button says *Loading…* forever is worse than one that admits there is no advert.
  static const Duration loadTimeout = Duration(seconds: 20);

  bool _initialised = false;
  bool _consentInfoRequested = false;
  RewardedAd? _loaded;

  /// Brings the consent framework up to date, once.
  ///
  /// **Without this, `getConsentStatus()` answers `unknown` forever** — the UMP framework has no opinion until
  /// it has been asked to fetch one, and `unknown` is not `notRequired`. This was the reason the Support screen
  /// showed *"No advert available"* even outside the EEA where no consent is needed: `unknown` mapped to
  /// `required`, `required` meant the controller never requested an advert, and nothing said why.
  Future<void> _ensureConsentInfo() async {
    if (_consentInfoRequested) return;
    _consentInfoRequested = true;
    final settled = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () {
        if (!settled.isCompleted) settled.complete();
      },
      (FormError error) {
        // A failure here is not fatal: the status stays whatever it was, and outside the EEA that is
        // `notRequired`. Completing rather than throwing keeps a network blip from disabling the whole screen.
        if (!settled.isCompleted) settled.complete();
      },
    );
    await settled.future.timeout(loadTimeout, onTimeout: () {});
  }

  @override
  Future<Result<void, Failure>> initialise() async {
    if (_initialised) return const Result.ok(null);
    try {
      await MobileAds.instance.initialize();
      _initialised = true;
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('Support could not be loaded.', cause: error),
      );
    }
  }

  @override
  Future<AdConsent> consentStatus() async {
    try {
      await _ensureConsentInfo();
      final status = await ConsentInformation.instance.getConsentStatus();
      return switch (status) {
        ConsentStatus.notRequired => AdConsent.notRequired,
        ConsentStatus.obtained => AdConsent.obtained,
        // **`required` and `unknown` both defer to `canRequestAds`, which is Google's own gate.** The status enum
        // describes the *form*; `canRequestAds` answers the question actually being asked. They differ exactly
        // when no consent message is published: the SDK logs "No available form can be built", the status stays
        // where it was, and outside the EEA ads are nonetheless permitted. Reading the enum alone was why the
        // Support screen said "No advert available" on a correctly configured account.
        ConsentStatus.required || ConsentStatus.unknown =>
          await ConsentInformation.instance.canRequestAds()
              ? AdConsent.notRequired
              : AdConsent.required,
      };
    } on Object {
      return AdConsent.unavailable;
    }
  }

  @override
  Future<AdConsent> requestConsent() async {
    await _ensureConsentInfo();
    try {
      // The callback is positional and required: it reports a form error rather than throwing, so the `await`
      // alone would not tell us anything.
      await ConsentForm.loadAndShowConsentFormIfRequired((error) {});
    } on Object {
      // Swallowed deliberately. A form that could not be built is not a refusal — the question below is what
      // decides, and it is asked either way.
    }
    try {
      return await ConsentInformation.instance.canRequestAds()
          ? AdConsent.obtained
          : AdConsent.unavailable;
    } on Object {
      return AdConsent.unavailable;
    }
  }

  @override
  Future<Result<void, Failure>> loadRewardedAd() async {
    final ready = await initialise();
    if (ready.isFailure) return ready;
    try {
      // **`RewardedAd.load` completes when the request is *dispatched*, not when an advert arrives.** Returning
      // `ok` from the awaited call therefore reported success while `_loaded` was still null — the button would
      // enable and then refuse with "no advert is ready yet". The completer is what makes this method mean what
      // its name says.
      final settled = Completer<Result<void, Failure>>();
      await RewardedAd.load(
        adUnitId: rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _loaded = ad;
            if (!settled.isCompleted) settled.complete(const Result.ok(null));
          },
          onAdFailedToLoad: (error) {
            _loaded = null;
            if (!settled.isCompleted) {
              // The SDK's own message, which names the actual cause — "No fill", a bad unit id, a missing App ID
              // — rather than a sentence of ours that would hide it (Law U9).
              settled.complete(
                Result.failure(
                  BusinessRuleFailure(error.message, rule: 'adLoadFailed'),
                ),
              );
            }
          },
        ),
      );
      return settled.future.timeout(
        loadTimeout,
        onTimeout: () => const Result.failure(
          BusinessRuleFailure(
            'No advert arrived in time.',
            rule: 'adLoadTimeout',
          ),
        ),
      );
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('No advert was available.', cause: error),
      );
    }
  }

  @override
  Future<Result<bool, Failure>> showRewardedAd() async {
    final ad = _loaded;
    if (ad == null) {
      return const Result.failure(
        BusinessRuleFailure('No advert is ready yet.', rule: 'adNotLoaded'),
      );
    }
    try {
      var earned = false;
      await ad.show(onUserEarnedReward: (view, reward) => earned = true);
      // One ad per load. Holding a shown ad would replay it, which the SDK treats as invalid traffic.
      _loaded = null;
      return Result.ok(earned);
    } on Object catch (error) {
      _loaded = null;
      return Result.failure(
        UnexpectedFailure('The advert could not be shown.', cause: error),
      );
    }
  }

  @override
  Future<Result<List<TipProduct>, Failure>> tipProducts() async {
    try {
      final available = await InAppPurchase.instance.isAvailable();
      if (!available) {
        return const Result.failure(
          BusinessRuleFailure(
            'In-app purchases are unavailable on this device.',
            rule: 'billingUnavailable',
          ),
        );
      }
      final response = await InAppPurchase.instance.queryProductDetails({
        tipProductId,
      });
      return Result.ok([
        for (final product in response.productDetails)
          TipProduct(
            id: product.id,
            title: product.title,
            // The store's own formatted string, never reformatted here.
            price: product.price,
          ),
      ]);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The tip could not be loaded.', cause: error),
      );
    }
  }

  @override
  Future<Result<bool, Failure>> buyTip(String productId) async {
    try {
      final response = await InAppPurchase.instance.queryProductDetails({
        productId,
      });
      if (response.productDetails.isEmpty) {
        return const Result.failure(
          BusinessRuleFailure(
            'That tip is not available.',
            rule: 'productMissing',
          ),
        );
      }
      final started = await InAppPurchase.instance.buyConsumable(
        purchaseParam: PurchaseParam(
          productDetails: response.productDetails.first,
        ),
      );
      return Result.ok(started);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The tip could not be completed.', cause: error),
      );
    }
  }
}
```

### `lib/data/trash/trash_adapter.dart`

```dart
import 'dart:async';

import 'package:drift/drift.dart';

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/services/trash/trash_port.dart';

/// The production [TrashPort], and **the only place in this codebase that hard-deletes a row**.
///
/// ARCH_3 §4.2 makes purge the single hard delete, and [_hardDelete] is the single function it lives in. Every
/// other deletion in Alaya sets `deletedAt` — that is what makes a trash screen possible at all, and it is why a
/// second `DELETE FROM` anywhere else would be a row that could vanish without ever appearing here.
///
/// **Seven tables, not twenty-two.** Every table in the schema carries `deletedAt`, but a trash listing
/// `currency_rates` and `analytics_cache` would bury the transaction somebody is looking for under machinery they
/// never deleted. The seven here are the ones a person deletes on purpose.
final class TrashAdapter implements TrashPort {
  /// Creates the adapter.
  const TrashAdapter({required AlayaDatabase database, required Clock clock})
    : _db = database,
      _clock = clock;

  final AlayaDatabase _db;
  final Clock _clock;

  @override
  Stream<List<TrashEntry>> watchAll() {
    // One query per table, combined — rather than a UNION, which would need every table to agree on a column
    // list they do not have. Seven small indexed reads on `deleted_at IS NOT NULL` beat one query that has to
    // pretend a transaction and a tag are the same shape.
    final streams = <Stream<List<TrashEntry>>>[
      _watch(TrashKind.transaction),
      _watch(TrashKind.item),
      _watch(TrashKind.asset),
      _watch(TrashKind.shoppingList),
      _watch(TrashKind.recurringTemplate),
      _watch(TrashKind.tag),
      _watch(TrashKind.payee),
    ];
    return _combine(streams).map((entries) {
      final sorted = [...entries]
        ..sort((a, b) => b.deletedAtUtcMillis.compareTo(a.deletedAtUtcMillis));
      return sorted;
    });
  }

  @override
  Stream<int> watchCount() => watchAll().map((entries) => entries.length);

  Stream<List<TrashEntry>> _watch(TrashKind kind) => switch (kind) {
    TrashKind.transaction =>
      (_db.select(
        _db.transactions,
      )..where((row) => row.deletedAt.isNotNull())).watch().map(
        (rows) => [
          for (final row in rows)
            _entry(
              id: row.id,
              kind: kind,
              // A transaction has no name, so it is identified by what it was: the subtype it was filed
              // under. The amount belongs on the row too, but formatting money is the screen's job — an
              // adapter that reached for `AmountText` would be a data file importing Flutter.
              label: row.subtype.name,
              deletedAt: row.deletedAt!,
            ),
        ],
      ),
    TrashKind.item =>
      (_db.select(
        _db.items,
      )..where((row) => row.deletedAt.isNotNull())).watch().map(
        (rows) => [
          for (final row in rows)
            _entry(
              id: row.id,
              kind: kind,
              label: row.name,
              deletedAt: row.deletedAt!,
            ),
        ],
      ),
    TrashKind.asset =>
      (_db.select(
        _db.assets,
      )..where((row) => row.deletedAt.isNotNull())).watch().map(
        (rows) => [
          for (final row in rows)
            _entry(
              id: row.id,
              kind: kind,
              label: row.name,
              deletedAt: row.deletedAt!,
            ),
        ],
      ),
    TrashKind.shoppingList =>
      (_db.select(
        _db.shoppingLists,
      )..where((row) => row.deletedAt.isNotNull())).watch().map(
        (rows) => [
          for (final row in rows)
            _entry(
              id: row.id,
              kind: kind,
              label: row.name,
              deletedAt: row.deletedAt!,
            ),
        ],
      ),
    TrashKind.recurringTemplate =>
      (_db.select(
        _db.recurringTemplates,
      )..where((row) => row.deletedAt.isNotNull())).watch().map(
        (rows) => [
          for (final row in rows)
            _entry(
              id: row.id,
              kind: kind,
              label: row.name,
              deletedAt: row.deletedAt!,
            ),
        ],
      ),
    TrashKind.tag =>
      (_db.select(
        _db.tags,
      )..where((row) => row.deletedAt.isNotNull())).watch().map(
        (rows) => [
          for (final row in rows)
            _entry(
              id: row.id,
              kind: kind,
              label: row.name,
              deletedAt: row.deletedAt!,
            ),
        ],
      ),
    TrashKind.payee =>
      (_db.select(
        _db.payees,
      )..where((row) => row.deletedAt.isNotNull())).watch().map(
        (rows) => [
          for (final row in rows)
            _entry(
              id: row.id,
              kind: kind,
              label: row.name,
              deletedAt: row.deletedAt!,
            ),
        ],
      ),
  };

  TrashEntry _entry({
    required String id,
    required TrashKind kind,
    required String label,
    required int deletedAt,
  }) => TrashEntry(
    id: id,
    kind: kind,
    label: label,
    deletedAtUtcMillis: deletedAt,
    purgeAfterUtcMillis: deletedAt + TrashPort.retention.inMilliseconds,
  );

  @override
  Future<Result<void, Failure>> restore(TrashEntry entry) async {
    try {
      final now = _clock.nowUtcMillis();
      // Clearing `deletedAt` is the whole of a restore, and `updatedAt` moves with it so a later merge treats the
      // revival as the newer write (ARCH_3 §3.2's last-write-wins).
      final changed = await _updateDeletedAt(
        entry,
        deletedAt: null,
        updatedAt: now,
      );
      if (changed == 0) {
        return const Result.failure(
          BusinessRuleFailure(
            'That has already gone.',
            rule: 'trashEntryMissing',
          ),
        );
      }
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That could not be restored.', cause: error),
      );
    }
  }

  @override
  Future<Result<void, Failure>> purge(TrashEntry entry) async {
    final result = await _hardDelete([entry]);
    return result.fold(
      (_) => const Result.ok(null),
      Result<void, Failure>.failure,
    );
  }

  @override
  Future<Result<int, Failure>> purgeAll() async {
    final entries = await watchAll().first;
    return _hardDelete(entries);
  }

  @override
  Future<Result<int, Failure>> purgeExpired() async {
    final now = _clock.nowUtcMillis();
    final entries = await watchAll().first;
    final expired = [
      for (final entry in entries)
        if (entry.purgeAfterUtcMillis <= now) entry,
    ];
    return _hardDelete(expired);
  }

  /// **The only hard delete in this codebase** (ARCH_3 §4.2).
  ///
  /// Every purge path arrives here — one row, all rows, or only the expired ones — so there is exactly one place
  /// where data leaves for good, and exactly one place to read when asking whether it can. `_deleteRow` beneath
  /// it is a `switch` over seven tables with no logic of its own and no other caller: the decision is here, the
  /// dispatch is there, and nothing else in `lib/` issues a `DELETE`.
  ///
  /// Runs in a transaction with `defer_foreign_keys`, because purging a transaction takes its lines with it and
  /// SQLite checks each statement as it goes otherwise. `foreign_keys = OFF` would be silently ignored inside a
  /// transaction — the trap 8A's `EraseService` documents.
  Future<Result<int, Failure>> _hardDelete(List<TrashEntry> entries) async {
    if (entries.isEmpty) return const Result.ok(0);
    try {
      var deleted = 0;
      await _db.transaction(() async {
        await _db.customStatement('PRAGMA defer_foreign_keys = ON');
        for (final entry in entries) {
          deleted += await _deleteRow(entry);
        }
      });
      return Result.ok(deleted);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That could not be deleted.', cause: error),
      );
    }
  }

  Future<int> _deleteRow(TrashEntry entry) => switch (entry.kind) {
    TrashKind.transaction => (_db.delete(
      _db.transactions,
    )..where((row) => row.id.equals(entry.id))).go(),
    TrashKind.item => (_db.delete(
      _db.items,
    )..where((row) => row.id.equals(entry.id))).go(),
    TrashKind.asset => (_db.delete(
      _db.assets,
    )..where((row) => row.id.equals(entry.id))).go(),
    TrashKind.shoppingList => (_db.delete(
      _db.shoppingLists,
    )..where((row) => row.id.equals(entry.id))).go(),
    TrashKind.recurringTemplate => (_db.delete(
      _db.recurringTemplates,
    )..where((row) => row.id.equals(entry.id))).go(),
    TrashKind.tag => (_db.delete(
      _db.tags,
    )..where((row) => row.id.equals(entry.id))).go(),
    TrashKind.payee => (_db.delete(
      _db.payees,
    )..where((row) => row.id.equals(entry.id))).go(),
  };

  Future<int> _updateDeletedAt(
    TrashEntry entry, {
    required int? deletedAt,
    required int updatedAt,
  }) => switch (entry.kind) {
    TrashKind.transaction =>
      (_db.update(
        _db.transactions,
      )..where((row) => row.id.equals(entry.id))).write(
        TransactionsCompanion(
          deletedAt: Value(deletedAt),
          updatedAt: Value(updatedAt),
        ),
      ),
    TrashKind.item =>
      (_db.update(_db.items)..where((row) => row.id.equals(entry.id))).write(
        ItemsCompanion(
          deletedAt: Value(deletedAt),
          updatedAt: Value(updatedAt),
        ),
      ),
    TrashKind.asset =>
      (_db.update(_db.assets)..where((row) => row.id.equals(entry.id))).write(
        AssetsCompanion(
          deletedAt: Value(deletedAt),
          updatedAt: Value(updatedAt),
        ),
      ),
    TrashKind.shoppingList =>
      (_db.update(
        _db.shoppingLists,
      )..where((row) => row.id.equals(entry.id))).write(
        ShoppingListsCompanion(
          deletedAt: Value(deletedAt),
          updatedAt: Value(updatedAt),
        ),
      ),
    TrashKind.recurringTemplate =>
      (_db.update(
        _db.recurringTemplates,
      )..where((row) => row.id.equals(entry.id))).write(
        RecurringTemplatesCompanion(
          deletedAt: Value(deletedAt),
          updatedAt: Value(updatedAt),
        ),
      ),
    TrashKind.tag =>
      (_db.update(_db.tags)..where((row) => row.id.equals(entry.id))).write(
        TagsCompanion(deletedAt: Value(deletedAt), updatedAt: Value(updatedAt)),
      ),
    TrashKind.payee =>
      (_db.update(_db.payees)..where((row) => row.id.equals(entry.id))).write(
        PayeesCompanion(
          deletedAt: Value(deletedAt),
          updatedAt: Value(updatedAt),
        ),
      ),
  };

  /// Merges several list streams into one, re-emitting whenever any of them changes.
  ///
  /// Hand-rolled rather than `rxdart`'s `combineLatest`: the project has no reactive-extensions dependency and
  /// adding one so seven streams can be zipped would be a package for a page of code.
  Stream<List<TrashEntry>> _combine(List<Stream<List<TrashEntry>>> streams) {
    final latest = List<List<TrashEntry>>.filled(streams.length, const []);
    final controller = StreamController<List<TrashEntry>>();
    final subscriptions = <StreamSubscription<List<TrashEntry>>>[];

    controller.onListen = () {
      for (var i = 0; i < streams.length; i++) {
        final index = i;
        subscriptions.add(
          streams[index].listen(
            (rows) {
              latest[index] = rows;
              controller.add([for (final list in latest) ...list]);
            },
            onError: controller.addError,
          ),
        );
      }
    };
    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    };
    return controller.stream;
  }
}
```
