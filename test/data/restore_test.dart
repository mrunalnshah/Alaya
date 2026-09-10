import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/backup/restore_service.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/seed/seed_data.dart';

/// Backup and restore: the `user_version` gate, merge last-write-wins, and all-or-nothing.
///
/// These run against real SQLite via `NativeDatabase`, because every guarantee under test is a
/// property of SQLite's `ATTACH` and upsert behaviour rather than of Dart. A fake would only assert
/// that I had understood them, which is the thing actually in question.
void main() {
  late AlayaDatabase db;
  late RestoreService restore;
  late Directory tempDir;

  setUpAll(() {
    // Several tests open a second AlayaDatabase to stamp or read an exported file. That is the point of
    // them, and the two never share a QueryExecutor, so drift's race-condition warning does not apply —
    // it was drowning the real failures in this suite.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    // Seeded, because `items.default_display_unit_code` is a hard foreign key to `units.code` and an
    // unseeded database has no units at all. A real restore always runs against a seeded database, so
    // testing against an empty one was testing a state the app never reaches.
    final seed = SeedData(
      uids: SequentialUidGenerator(prefix: 'restore'),
      clock: FixedClock(DateTime.utc(2026, 7, 28, 9)),
    );
    db = AlayaDatabase(NativeDatabase.memory(), seeder: seed.insertAll);
    restore = RestoreService(database: db);
    // Force onCreate, so the seed is in place before the first export.
    await db.customSelect('SELECT 1').get();
    tempDir = await Directory.systemTemp.createTemp('alaya_restore_test');
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Writes an item with an explicit `updatedAt`, which is what the merge rule compares.
  Future<void> putItem({
    required AlayaDatabase into,
    required String id,
    required String name,
    required int updatedAt,
  }) async {
    await into
        .into(into.items)
        .insertOnConflictUpdate(
          ItemsCompanion.insert(
            id: id,
            name: name,
            normalizedName: name.toLowerCase(),
            unitCategory: UnitCategory.weight,
            defaultDisplayUnitCode: 'g',
            // `food`, not `grocery` — ItemKind is generic/food/medicine/beauty/household/other.
            // `grocery` is a TransactionSubtype, which is a different axis: what the money was for
            // versus what the thing is.
            isFavorite: false,
            createdAt: 1000,
            updatedAt: updatedAt,
          ),
        );
  }

  Future<Map<String, ({String name, int updatedAt})>> readItems(
    AlayaDatabase from,
  ) async {
    final rows = await from.select(from.items).get();
    return {for (final r in rows) r.id: (name: r.name, updatedAt: r.updatedAt)};
  }

  /// Exports to a file with `VACUUM INTO`, which is what `BackupService` does.
  Future<String> exportTo(String fileName) async {
    final path = '${tempDir.path}/$fileName';
    await db.customStatement("VACUUM INTO '$path'");
    return path;
  }

  group('the user_version gate', () {
    test('a backup at the app\'s own version is accepted', () async {
      final path = await exportTo('same.db');

      final result = await restore.readBackupSchemaVersion(path);

      expect(result.isFailure, isFalse);
      expect(result.valueOrNull, db.schemaVersion);
    });

    test('a backup from a NEWER app version is refused', () async {
      final path = await exportTo('newer.db');
      // Stamp the exported file as if a future build wrote it.
      final future = AlayaDatabase(NativeDatabase(File(path)));
      await future.customStatement(
        'PRAGMA user_version = ${db.schemaVersion + 5}',
      );
      await future.close();

      final result = await restore.merge(path);

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull!.message, contains('newer version'));
    });

    test('the gate reads the ATTACHED file, not the live database', () async {
      final path = await exportTo('stamped.db');
      final other = AlayaDatabase(NativeDatabase(File(path)));
      await other.customStatement('PRAGMA user_version = 99');
      await other.close();

      final read = await restore.readBackupSchemaVersion(path);

      expect(
        read.valueOrNull,
        99,
        reason:
            'PRAGMA backup.user_version — the qualified form, since '
            'pragma_user_version() takes no argument',
      );
      expect(db.schemaVersion, isNot(99));
    });

    test('a file that is not SQLite is refused', () async {
      final path = '${tempDir.path}/garbage.db';
      await File(path).writeAsString('this is not a database');

      final result = await restore.readBackupSchemaVersion(path);

      expect(result.isFailure, isTrue);
    });

    test('a missing file is refused', () async {
      final result = await restore.readBackupSchemaVersion(
        '${tempDir.path}/absent.db',
      );

      expect(result.isFailure, isTrue);
    });
  });

  group('merge: export, mutate, merge back', () {
    test(
      'last-write-wins by updatedAt — the LOCAL newer row survives',
      () async {
        await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
        await putItem(into: db, id: 'b', name: 'Banana', updatedAt: 1000);

        final backup = await exportTo('lww.db');

        // Mutate locally AFTER the backup, so local is newer.
        await putItem(
          into: db,
          id: 'a',
          name: 'Apple (edited later)',
          updatedAt: 5000,
        );

        final result = await restore.merge(backup);
        expect(result.isFailure, isFalse);

        final items = await readItems(db);
        expect(
          items['a']!.name,
          'Apple (edited later)',
          reason:
              'the backup holds an OLDER version of a, so it must not overwrite',
        );
        expect(items['a']!.updatedAt, 5000);
      },
    );

    test('last-write-wins by updatedAt — the BACKUP newer row wins', () async {
      await putItem(
        into: db,
        id: 'a',
        name: 'Apple (newer, will be backed up)',
        updatedAt: 9000,
      );
      final backup = await exportTo('lww2.db');

      // Now make the local row older than what the backup holds.
      await putItem(
        into: db,
        id: 'a',
        name: 'Apple (rolled back locally)',
        updatedAt: 100,
      );

      await restore.merge(backup);

      final items = await readItems(db);
      expect(
        items['a']!.name,
        'Apple (newer, will be backed up)',
        reason:
            'the rule is genuinely a timestamp comparison, not local precedence',
      );
      expect(items['a']!.updatedAt, 9000);
    });

    test('rows absent from the backup SURVIVE', () async {
      await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
      final backup = await exportTo('survivors.db');

      // Added after the backup was taken, so the backup knows nothing about it.
      await putItem(
        into: db,
        id: 'z',
        name: 'Added after the backup',
        updatedAt: 6000,
      );

      await restore.merge(backup);

      final items = await readItems(db);
      expect(
        items.containsKey('z'),
        isTrue,
        reason:
            'merge is an upsert, never a replace — a merge that deleted local rows would '
            'lose data the user never asked to discard',
      );
      expect(items['z']!.name, 'Added after the backup');
    });

    test('rows only in the backup are INSERTED', () async {
      await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
      await putItem(
        into: db,
        id: 'gone',
        name: 'Only in the backup',
        updatedAt: 3000,
      );
      final backup = await exportTo('inserts.db');

      // Delete it locally (hard delete, so the merge must reinstate it).
      await db.customStatement("DELETE FROM items WHERE id = 'gone'");
      expect((await readItems(db)).containsKey('gone'), isFalse);

      await restore.merge(backup);

      expect((await readItems(db)).containsKey('gone'), isTrue);
    });

    test(
      'merging the same backup twice changes nothing the second time',
      () async {
        await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
        final backup = await exportTo('idempotent.db');

        await restore.merge(backup);
        final afterFirst = await readItems(db);
        await restore.merge(backup);
        final afterSecond = await readItems(db);

        expect(afterSecond.length, afterFirst.length);
        expect(
          afterSecond['a']!.updatedAt,
          afterFirst['a']!.updatedAt,
          reason:
              'UUID primary keys mean merge needs no ID remapping, so it is naturally idempotent',
        );
      },
    );

    test('the report names how many tables were merged', () async {
      await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
      final backup = await exportTo('report.db');

      final result = await restore.merge(backup);

      final report = result.valueOrNull!;
      expect(report.mode, RestoreMode.merge);
      expect(report.tablesMerged, greaterThan(0));
      expect(report.backupSchemaVersion, db.schemaVersion);
    });
  });

  group('the merge is all-or-nothing', () {
    test(
      'the backup file is DETACHED afterwards, so a second merge works',
      () async {
        final backup = await exportTo('detach.db');

        await restore.merge(backup);
        final second = await restore.merge(backup);

        expect(
          second.isFailure,
          isFalse,
          reason:
              'a stranded ATTACH would fail the next merge with a duplicate-alias error',
        );
      },
    );

    test('the backup is detached even when the merge throws', () async {
      final path = '${tempDir.path}/broken.db';
      await File(path).writeAsString('not sqlite');

      await restore.merge(path);

      // If the alias were still held, attaching it again would fail.
      await db.customStatement("ATTACH DATABASE ? AS backup", [
        path.replaceAll('broken', 'probe'),
      ]);
      await db.customStatement('DETACH DATABASE backup');
    });

    test('a failure part-way through leaves nothing applied', () async {
      await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
      final before = await readItems(db);

      // A statement that violates a constraint inside a transaction must roll the whole thing back.
      var threw = false;
      try {
        await db.transaction(() async {
          await putItem(
            into: db,
            id: 'new',
            name: 'Should vanish',
            updatedAt: 3000,
          );
          await db.customStatement(
            'INSERT INTO items (id, name, normalized_name, unit_category, '
            'default_display_unit_code, item_kind, is_favorite, created_at, updated_at) '
            "VALUES ('a', 'dup', 'dup', 'weight', 'g', 'food', 0, 1, 1)",
          );
        });
      } on Object {
        threw = true;
      }

      expect(threw, isTrue);
      final after = await readItems(db);
      expect(
        after.length,
        before.length,
        reason:
            'ONE transaction for the whole merge is what makes a partial merge impossible',
      );
      expect(after.containsKey('new'), isFalse);
    });
  });

  group('merge statement construction', () {
    test('a table with updated_at gets the last-write-wins guard', () async {
      final sql = await restore.buildMergeStatement('items');

      expect(sql, contains('ON CONFLICT(id) DO UPDATE SET'));
      expect(sql, contains('WHERE excluded.updated_at > items.updated_at'));
      expect(
        sql,
        isNot(contains('id = excluded.id')),
        reason: 'the conflict target must not be reassigned',
      );
    });

    test(
      'a link table upserts on its composite key, last-write-wins like any other',
      () async {
        final sql = await restore.buildMergeStatement('transaction_tags');

        // My first version of this test asserted `DO NOTHING`, on the assumption that link tables carry
        // no timestamps. They do — **every table in this schema has `updated_at`**, which I confirmed by
        // scanning all of them. So `buildMergeStatement`'s `DO NOTHING` branch is unreachable today; it
        // stays as insurance for a future table without audit columns, and this test asserts what the
        // schema actually produces.
        expect(sql, contains('ON CONFLICT(transaction_id, tag_id)'));
        expect(
          sql,
          contains('WHERE excluded.updated_at > transaction_tags.updated_at'),
        );
        expect(
          sql,
          isNot(contains('transaction_id = excluded.transaction_id')),
          reason: 'the conflict target must not be reassigned',
        );
      },
    );

    test('natural-key tables use their real primary key, not id', () async {
      expect(
        await restore.buildMergeStatement('currencies'),
        contains('ON CONFLICT(code)'),
      );
      expect(
        await restore.buildMergeStatement('app_settings'),
        contains('ON CONFLICT(key)'),
      );
      expect(
        await restore.buildMergeStatement('currency_rates'),
        contains('ON CONFLICT(base_code, quote_code, rate_date_key)'),
      );
    });

    test('the merge order is foreign-key safe', () {
      final order = RestoreService.mergeOrder;

      expect(
        order.indexOf('accounts'),
        lessThan(order.indexOf('transactions')),
      );
      expect(
        order.indexOf('transactions'),
        lessThan(order.indexOf('transaction_lines')),
      );
      expect(
        order.indexOf('items'),
        lessThan(order.indexOf('inventory_batches')),
      );
      expect(
        order.indexOf('inventory_batches'),
        lessThan(order.indexOf('stock_movements')),
      );
      expect(
        order.indexOf('tags'),
        lessThan(order.indexOf('transaction_tags')),
      );
      expect(
        order.indexOf('assets'),
        lessThan(order.indexOf('service_records')),
      );
      expect(order.indexOf('currencies'), lessThan(order.indexOf('accounts')));
      expect(
        order.indexOf('recurring_templates'),
        lessThan(order.indexOf('recurring_occurrences')),
      );
    });
  });

  group('replace mode', () {
    test('snapshots a rollback before swapping the file', () async {
      await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
      final backup = await exportTo('replace-source.db');
      final live = '${tempDir.path}/live.db';
      final rollback = '${tempDir.path}/rollback.db';
      await File(backup).copy(live);

      final result = await restore.replaceFiles(
        backupPath: backup,
        livePath: live,
        rollbackPath: rollback,
      );

      expect(result.isFailure, isFalse);
      expect(
        File(rollback).existsSync(),
        isTrue,
        reason:
            'a corrupt backup must not leave the user with no database at all',
      );
      expect(result.valueOrNull!.mode, RestoreMode.replace);
    });

    test(
      'refuses a backup from a newer app version before touching any file',
      () async {
        final backup = await exportTo('replace-newer.db');
        final future = AlayaDatabase(NativeDatabase(File(backup)));
        await future.customStatement(
          'PRAGMA user_version = ${db.schemaVersion + 1}',
        );
        await future.close();

        final live = '${tempDir.path}/live2.db';
        await File(backup).copy(live);

        final result = await restore.replaceFiles(
          backupPath: backup,
          livePath: live,
          rollbackPath: '${tempDir.path}/rollback2.db',
        );

        expect(result.isFailure, isTrue);
        expect(
          File('${tempDir.path}/rollback2.db').existsSync(),
          isFalse,
          reason: 'the gate runs first, so a refused restore does no file work',
        );
      },
    );

    test('the rollback can be put back', () async {
      final backup = await exportTo('rb-source.db');
      final live = '${tempDir.path}/live3.db';
      final rollback = '${tempDir.path}/rollback3.db';
      await File(backup).copy(live);
      await File(backup).copy(rollback);

      final result = await restore.restoreRollback(
        rollbackPath: rollback,
        livePath: live,
      );

      expect(result.isFailure, isFalse);
    });

    test('restoring a rollback that does not exist fails cleanly', () async {
      final result = await restore.restoreRollback(
        rollbackPath: '${tempDir.path}/nope.db',
        livePath: '${tempDir.path}/live4.db',
      );

      expect(result.isFailure, isTrue);
    });
  });

  group('no encryption', () {
    test(
      'an exported backup is readable plaintext SQLite with no key',
      () async {
        await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
        final path = await exportTo('plaintext.db');

        // Opened with no PRAGMA key, no passphrase, nothing.
        final reopened = AlayaDatabase(NativeDatabase(File(path)));
        final rows = await reopened.select(reopened.items).get();
        await reopened.close();

        expect(rows.map((r) => r.id), contains('a'));
      },
    );

    test('the file begins with SQLite\'s plaintext header', () async {
      final path = await exportTo('header.db');

      final header = await File(path).openRead(0, 16).first;

      expect(
        String.fromCharCodes(header.take(15)),
        'SQLite format 3',
        reason:
            'an encrypted file would have an opaque header; this is the honest threat model',
      );
    });
  });
}
