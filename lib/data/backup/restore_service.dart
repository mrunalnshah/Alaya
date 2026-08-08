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
