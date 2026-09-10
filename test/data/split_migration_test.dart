import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/data/db/alaya_database.dart';

import 'generated_migrations/schema.dart';

/// **The first test in this project that runs a migration.**
///
/// `migration_test.dart` states the gap in its own doc comment: creating fresh at the current version
/// exercises `onCreate`, not `onUpgrade`. So `from1To2`, `from2To3` and `from3To4` are all written,
/// generated, wired — and until this file, none had ever executed against a database. ARCH_2 §13 calls
/// skipping the v1 snapshot "unrecoverable"; never running the step is the same risk one layer up, and
/// v4 is the first version whose step does anything other than create a table.
///
/// Data is inserted through [InitializedSchema.rawDatabase] with plain SQL rather than through
/// generated per-version data classes. That avoids passing `--data-classes --companions` to
/// `drift_dev schema generate`, which would emit a `DatabaseAtV1`-style class per version — four more
/// generated files to keep in step for no assertion this file could not already make.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  /// Inserts one payee, which is the cleanest possible survival probe: `payees` has **no foreign
  /// keys**, so the row cannot fail to insert for a reason unrelated to what is being tested. Every
  /// other table worth using here hangs off `currencies` or `accounts`.
  ///
  /// `kind` is written as text because `SafeEnumConverter.toSql` stores an enum by its `name` — the
  /// same trap `from2To3` documents for `units.category`. An ordinal here would read back as the
  /// fallback member and the assertion would pass while proving nothing.
  Future<void> insertPayee(InitializedSchema schema, String id) async {
    schema.rawDatabase.execute(
      'INSERT INTO payees (id, name, normalized_name, kind, created_at, updated_at) '
      "VALUES (?, ?, ?, 'person', 0, 0)",
      [id, 'Ravi', 'ravi'],
    );
  }

  Future<Set<String>> objectsOf(AlayaDatabase db, String type) async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = '$type'")
        .get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  group('v3 to v4 — the split module', () {
    test('the migration runs and yields the v4 schema', () async {
      final schema = await verifier.schemaAt(3);
      final db = AlayaDatabase(schema.newConnection());
      // Throws SchemaMismatch if the migrated schema differs from what v4 declares. This is the
      // assertion that catches a hand-edited `schema_steps.dart`, which is the failure
      // `alaya_database.dart` warns about and which drift otherwise detects only on a real device.
      await verifier.migrateAndValidate(db, 4);
      await db.close();
      schema.close();
    });

    test('data written at v3 survives', () async {
      final schema = await verifier.schemaAt(3);
      await insertPayee(schema, 'payee-1');

      final db = AlayaDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 4);

      final row = await db
          .customSelect("SELECT name FROM payees WHERE id = 'payee-1'")
          .getSingle();
      expect(row.read<String>('name'), 'Ravi');

      await db.close();
      schema.close();
    });

    test('the five split tables arrive', () async {
      final schema = await verifier.schemaAt(3);
      final db = AlayaDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 4);

      expect(
        await objectsOf(db, 'table'),
        containsAll([
          'split_groups',
          'split_members',
          'split_expenses',
          'split_shares',
          'split_settlements',
        ]),
      );

      await db.close();
      schema.close();
    });

    test('the four split views arrive, and the calendar view is rebuilt', () async {
      // **The reason this step needed an API nothing here had used.** `v_calendar_events` gains a
      // `splitSettleBy` arm, so `from3To4` drops and recreates it — the first time any migration in
      // this project has touched a view. If the drop were missing, SQLite would raise
      // "view v_calendar_events already exists" and this test is what surfaces that.
      final schema = await verifier.schemaAt(3);
      final db = AlayaDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 4);

      final views = await objectsOf(db, 'view');
      expect(
        views,
        containsAll([
          'v_split_expenses',
          'v_split_balances',
          'v_split_group_balances',
          'v_split_activity',
          'v_calendar_events',
        ]),
      );

      // And the rebuilt one really is the new definition: the v3 view had no split arm.
      final sql = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type = 'view' "
            "AND name = 'v_calendar_events'",
          )
          .getSingle();
      expect(sql.read<String>('sql'), contains('splitSettleBy'));

      await db.close();
      schema.close();
    });

    test('the split indexes arrive, and the partial ones keep their WHERE', () async {
      // Eleven of the fourteen are partial on `deleted_at IS NULL`. A uniqueness index that lost its
      // WHERE clause is anomaly A19 — soft-deleting a group and re-creating it would collide on a row
      // the user can no longer see — and `createIndex` carrying the clause through a migration is
      // exactly what has never been exercised before.
      final schema = await verifier.schemaAt(3);
      final db = AlayaDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 4);

      final rows = await db
          .customSelect(
            "SELECT name, sql FROM sqlite_master WHERE type = 'index' "
            "AND name LIKE 'idx_split_%'",
          )
          .get();
      final byName = {
        for (final r in rows) r.read<String>('name'): r.read<String?>('sql'),
      };
      expect(byName, hasLength(14));

      const partial = {
        'idx_split_groups_name',
        'idx_split_member',
        'idx_split_share',
        'idx_split_exp_date',
        'idx_split_exp_month',
        'idx_split_exp_group',
        'idx_split_exp_payer',
        'idx_split_exp_settle',
        'idx_split_share_exp',
        'idx_split_share_who',
        'idx_split_settle_group',
      };
      expect(partial, hasLength(11));
      for (final name in partial) {
        expect(
          byName[name],
          contains('deleted_at IS NULL'),
          reason: '$name lost its partial clause (A19)',
        );
      }

      await db.close();
      schema.close();
    });
  });

  group('the two steps that had also never run', () {
    test('v1 to v4 walks all three, and each one leaves its mark', () async {
      // The single most valuable test in this file. It is also the case ARCH_2 §13 was written for:
      // a device that has held a v1 database since launch and has just taken this build.
      final schema = await verifier.schemaAt(1);
      await insertPayee(schema, 'ancient');

      final db = AlayaDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 4);

      final tables = await objectsOf(db, 'table');
      // from1To2 — the four recipe tables.
      expect(tables, containsAll(['recipes', 'recipe_ingredients']));
      // from3To4 — the split tables.
      expect(tables, contains('split_expenses'));

      // from2To3 — the three cooking measures, inserted by the *migration* rather than the seed,
      // because a seed-only change reaches new installs and never a device that already has data.
      // This is the assertion that proves that fix works, which nothing has ever checked.
      final tsp = await db
          .customSelect(
            "SELECT factor_to_base_milli FROM units WHERE code = 'tsp'",
          )
          .getSingle();
      expect(tsp.read<int>('factor_to_base_milli'), 4929);

      // from2To3 — and the two nullable columns on an existing table.
      final items = await db
          .customSelect("SELECT * FROM pragma_table_info('items')")
          .get();
      expect(
        items.map((r) => r.read<String>('name')),
        containsAll(['density_milli_grams_per_ml', 'milli_grams_per_piece']),
      );

      // The row inserted before any of it still reads back.
      final row = await db
          .customSelect("SELECT name FROM payees WHERE id = 'ancient'")
          .getSingle();
      expect(row.read<String>('name'), 'Ravi');

      await db.close();
      schema.close();
    });

    test('v2 to v4 leaves the recipe tables it already had alone', () async {
      final schema = await verifier.schemaAt(2);
      // A recipe row created at v2, to prove `from2To3` and `from3To4` do not disturb it.
      schema.rawDatabase.execute(
        'INSERT INTO recipes (id, name, normalized_name, servings, is_favorite, '
        'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        ['r1', 'Dal', 'dal', 2, 0, 0, 0],
      );

      final db = AlayaDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 4);

      final row = await db
          .customSelect("SELECT name FROM recipes WHERE id = 'r1'")
          .getSingle();
      expect(row.read<String>('name'), 'Dal');

      await db.close();
      schema.close();
    });
  });

  group('a fresh v4 and a migrated v4 agree', () {
    test('validateDatabaseSchema passes on a database built by createAll', () async {
      // The other direction, and it needs no verifier helper: `validateDatabaseSchema` compares the
      // live schema against what the generated code expects. A schema object declared in
      // `@DriftDatabase` but never created — or created with different constraints than declared —
      // fails here, which is the mistake `onCreate` alone cannot surface.
      final db = AlayaDatabase(NativeDatabase.memory());
      await db.customSelect('SELECT 1').get();
      await db.validateDatabaseSchema();
      await db.close();
    });
  });
}
