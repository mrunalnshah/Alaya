import 'package:alaya/data/db/migrations/schema_steps.dart';
import 'package:drift/drift.dart';

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// Populates a freshly created database. Injected rather than called directly so tests can seed
/// deterministically, or skip seeding entirely.
typedef DatabaseSeeder = Future<void> Function(AlayaDatabase db);

/// Builds the [MigrationStrategy] for [db].
///
/// Three responsibilities, in order of how easy they are to get wrong:
///
/// 1. **`beforeOpen` turns foreign keys on.** SQLite defaults `PRAGMA foreign_keys` to *off*,
///    per-connection, and drift does not change that. Until this runs, every foreign key in the
///    schema is declared and completely unenforced. This is the single most important line in
///    the file.
/// 2. **`onCreate` creates the schema and then seeds it.** `createAll()` covers the 35 tables,
///    15 views, 36 indexes and 2 FTS tables, because drift registers everything in the
///    `@DriftDatabase` annotation's `tables` and `include` sets.
/// 3. **`onUpgrade` steps forward one version at a time.** See the note on [_onUpgrade].
MigrationStrategy buildMigrationStrategy(
  AlayaDatabase db, {
  DatabaseSeeder? seeder,
}) {
  return MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      if (seeder != null) await seeder(db);
    },
    onUpgrade: _onUpgrade,
    beforeOpen: (details) async {
      await db.customStatement('PRAGMA foreign_keys = ON');
      if (_isDebugBuild) {
        await _assertFts5Available(db);
      }
    },
  );
}

/// Steps a database forward one schema version at a time.
///
/// **This must stay wired to the generated helper.** Until Phase R5 it was a scaffold that threw,
/// while `schema_steps.dart` already contained a working v1 -> v2 step — so a device holding a v1
/// database could not open a v2 build at all. The generated file existed; nothing called it.
///
/// `stepByStep` is generated from the committed snapshots in
/// `lib/data/db/migrations/schema/`, and its parameter list grows with every version: adding v4
/// makes it demand a `from3To4` and the build fails until one is supplied. That is the property
/// worth having — a forgotten migration becomes a compile error rather than a crash in the field.
///
/// **None of these steps has ever run against a real database.** `migration_test.dart` says so of itself:
/// creating fresh at the current version exercises `onCreate`, not `onUpgrade`. Every step below is written,
/// generated, wired — and, on any device, unexecuted.
///
/// `from4To5` is the first one where that matters rather than merely being true. It **backfills**: it reads
/// `item_kind` on rows a user already has and writes `kind_tag_id` from them, then drops the column it read.
/// The three earlier steps only add — a table, a column, a few unit rows — and an add that half-runs leaves
/// the data it did not touch intact. A backfill that half-runs leaves items with no kind and no way to
/// recover the old value, because the source column is gone.
///
/// So a `verifyMigrations` test against `drift_schema_v4.json` is not optional for this one, and neither is
/// installing from Play and updating over a populated database before shipping it.
final OnUpgrade _onUpgrade = stepByStep(
  from1To2: (m, schema) async {
    // v2 added the four recipe tables and nothing else. No existing table changed, so there is no
    // backfill and no data to convert — `createTable` on each is the whole step.
    await m.createTable(schema.recipes);
    await m.createTable(schema.recipeIngredients);
    await m.createTable(schema.recipeSteps);
    await m.createTable(schema.recipeCookLog);
  },
  from2To3: (m, schema) async {
    // Two nullable columns on an existing table: no default, no backfill, nothing to convert.
    await m.addColumn(schema.items, schema.items.densityMilliGramsPerMl);
    await m.addColumn(schema.items, schema.items.milliGramsPerPiece);

    // The three cooking measures, as volume units.
    //
    // **Inserted here rather than in `seed_data.dart`**, which only runs on `onCreate`: a seed-only
    // change reaches new installs and never reaches a device that already has data.
    //
    // `factorToBaseMilli` is milli-millilitres per one of the unit — 1 tsp is 4.92892 ml, and the
    // US customary cup is 240 ml. `INSERT OR IGNORE` makes the step safe to re-run and harmless if
    // a user has already created a unit by one of these codes.
    //
    // The category is written as **text**, because `SafeEnumConverter.toSql` stores a Dart enum by
    // its `name`. Writing an ordinal here would produce rows that read back as the fallback member.
    const rows = [
      ('tsp', 4929, 'Teaspoon'),
      ('tbsp', 14787, 'Tablespoon'),
      ('cup', 240000, 'Cup'),
    ];
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (var i = 0; i < rows.length; i++) {
      final (code, factor, name) = rows[i];
      await m.database.customInsert(
        'INSERT OR IGNORE INTO units '
        '(code, category, factor_to_base_milli, display_name, is_system, sort_order, '
        'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable<String>(code),
          Variable<String>(UnitCategory.volume.name),
          Variable<int>(factor),
          Variable<String>(name),
          Variable<bool>(true),
          Variable<int>(100 + i),
          Variable<int>(now),
          Variable<int>(now),
        ],
      );
    }
  },
  from3To4: (m, schema) async {
    // v4 is the Split module: five tables, fourteen indexes, four new views, and one existing view
    // that changes shape.
    //
    // **Nothing to seed and nothing to backfill.** No currencies, units or system tags equivalent
    // exists for splits, which removes the failure ARCH_2 §14 and ARCH_M §7 both record — shipping a
    // seed without its migration step, or the reverse. The one setting this module needs,
    // `split.selfPayeeId`, is deliberately absent: on a fresh install there is no payee to point at
    // yet, and the balance views read a missing key as a null share, which is the correct reading of
    // "not configured".
    //
    // **The first migration in this project to create an index or touch a view.** `from1To2` only
    // created tables and `from2To3` only added columns, so every call below except `createTable` is
    // being used here for the first time.

    // ── tables, before anything that references them ──────────────────────────────────────
    await m.createTable(schema.splitGroups);
    await m.createTable(schema.splitMembers);
    await m.createTable(schema.splitExpenses);
    await m.createTable(schema.splitShares);
    await m.createTable(schema.splitSettlements);

    // ── indexes ──────────────────────────────────────────────────────────────────────────
    // Eleven of these fourteen are partial on `deleted_at IS NULL`. That is not decoration: without
    // it, soft-deleting a group named "Goa trip" and re-creating it collides on a row the user can no
    // longer see (anomaly A19). `createIndex` carries the `WHERE` clause because the index is
    // declared in `indexes.drift` as raw SQL, which is the reason ARCH_2 §11 keeps it there.
    await m.createIndex(schema.idxSplitGroupsName);
    await m.createIndex(schema.idxSplitMember);
    await m.createIndex(schema.idxSplitShare);
    await m.createIndex(schema.idxSplitExpDate);
    await m.createIndex(schema.idxSplitExpMonth);
    await m.createIndex(schema.idxSplitExpGroup);
    await m.createIndex(schema.idxSplitExpPayer);
    await m.createIndex(schema.idxSplitExpTx);
    await m.createIndex(schema.idxSplitExpSettle);
    await m.createIndex(schema.idxSplitShareExp);
    await m.createIndex(schema.idxSplitShareWho);
    await m.createIndex(schema.idxSplitSettleFrom);
    await m.createIndex(schema.idxSplitSettleTo);
    await m.createIndex(schema.idxSplitSettleGroup);

    // ── views ────────────────────────────────────────────────────────────────────────────
    // **`v_calendar_events` is dropped and recreated, and that is the whole reason this step needed
    // an API nothing here had used.** It gains a `splitSettleBy` arm, so the v3 definition is wrong
    // for v4 — and a view is pure derivation, holding no data, so dropping one costs nothing and
    // recreating it from the target schema is exact. `SQLite` has no `CREATE OR REPLACE VIEW`, which
    // is why this is two calls rather than one.
    //
    // `m.drop` issues `DROP VIEW` by the entity's own name, and `schema` here is the **v4** schema —
    // so the name matches the view that exists while the statement that follows is the new
    // definition. Ordered after the tables because the new arm reads `split_expenses`.
    await m.drop(schema.vCalendarEvents);
    await m.createView(schema.vCalendarEvents);

    await m.createView(schema.vSplitExpenses);
    await m.createView(schema.vSplitBalances);
    await m.createView(schema.vSplitGroupBalances);
    await m.createView(schema.vSplitActivity);
  },
  from4To5: (m, schema) async {
    // v5 retires `ItemKind`. An item's kind becomes a row in `tags`, scoped by `allowed_in_inventory`, so a
    // user can add `Vegetables` or `Cereals` without a code change.
    //
    // **Two new tags, not six.** `Medicine`, `Beauty` and `Household` were already in the seed matrix as
    // inventory-scoped system tags — `idx_tags_name` is unique on `normalized_name`, so a second row with any
    // of those names is not merely untidy, it is rejected. Only `Food` and `Other` had no tag to become.
    //
    // **Both here and in `seed_data.dart`**, which is the pairing ARCH_M §7 records as a recurring failure: a
    // seed-only change reaches new installs and never reaches a device that already has data. `from2To3` adds
    // the `tsp`/`tbsp`/`cup` units for the same reason and is the pattern this copies.

    // ── the two tags ────────────────────────────────────────────────────────────────────────
    //
    // **Literal ids, not generated ones.** A migration has no `UidGenerator` — `stepByStep` hands it a
    // `Migrator` and nothing else — and the backfill below has to name these rows in an `UPDATE`. A fresh
    // install gets uid-generated ids for the same two tags, which is harmless: an id is opaque and nothing
    // compares them across installs.
    const foodTagId = 'v5-tag-food';
    const otherTagId = 'v5-tag-other';
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    // `INSERT OR IGNORE`, so the step is safe to re-run and harmless if a user already made a tag with one of
    // these ids. `sort_order` continues past the seeded eighteen.
    for (final (id, name, order) in [
      (foodTagId, 'Food', 18),
      (otherTagId, 'Other', 19),
    ]) {
      await m.database.customInsert(
        'INSERT OR IGNORE INTO tags '
        '(id, name, normalized_name, allowed_in_deposit, allowed_in_withdrawal, '
        'allowed_in_inventory, allowed_in_shopping, allowed_in_recurring, '
        'allowed_in_service, is_system, sort_order, created_at, updated_at) '
        'VALUES (?, ?, ?, 0, 1, 1, 1, 0, 0, 1, ?, ?, ?)',
        variables: [
          Variable<String>(id),
          Variable<String>(name),
          // Matches Phase 1A's `Normalizer` for these two: single lowercase-able words, no diacritics.
          Variable<String>(name.toLowerCase()),
          Variable<int>(order),
          Variable<int>(now),
          Variable<int>(now),
        ],
      );
    }

    // ── the column ──────────────────────────────────────────────────────────────────────────
    //
    // Nullable, because there is nothing to default it to until the backfill below runs. It stays nullable
    // afterwards: making it `NOT NULL` would mean a second table rebuild for a constraint the data already
    // satisfies, and would leave no way to represent an item whose kind was deleted before Settings could move
    // it to `Other`.
    await m.addColumn(schema.items, schema.items.kindTagId);

    // ── the backfill ────────────────────────────────────────────────────────────────────────
    //
    // **`generic` and `other` both land on `Other`.** They were two enum members for one idea — "no more
    // specific classification applies" and "anything not covered by the above" — and `generic` was the
    // default, so most rows are it.
    //
    // The other three resolve by name rather than by a literal id, because those tags were created by
    // `seed_data.dart` with generated ids this migration cannot know.
    const byName = {
      'medicine': 'medicine',
      'beauty': 'beauty',
      'household': 'household',
    };
    for (final (kind, tagName) in byName.entries.map((e) => (e.key, e.value))) {
      await m.database.customUpdate(
        'UPDATE items SET kind_tag_id = '
        '(SELECT id FROM tags WHERE normalized_name = ? AND deleted_at IS NULL LIMIT 1), '
        'updated_at = ? '
        'WHERE item_kind = ?',
        variables: [
          Variable<String>(tagName),
          Variable<int>(now),
          Variable<String>(kind),
        ],
      );
    }
    for (final (kind, tagId) in [
      ('food', foodTagId),
      ('generic', otherTagId),
      ('other', otherTagId),
    ]) {
      await m.database.customUpdate(
        'UPDATE items SET kind_tag_id = ?, updated_at = ? WHERE item_kind = ?',
        variables: [
          Variable<String>(tagId),
          Variable<int>(now),
          Variable<String>(kind),
        ],
      );
    }

    // **Anything the six cases missed goes to `Other` rather than staying null.** `item_kind` was
    // `NOT NULL` through a `SafeEnumConverter`, so a row holding an unrecognised string reads back as the
    // fallback member in Dart while still holding its own text in SQLite — and a `WHERE item_kind = 'generic'`
    // would not have matched it. This is the sweep that catches those.
    await m.database.customUpdate(
      'UPDATE items SET kind_tag_id = ?, updated_at = ? WHERE kind_tag_id IS NULL',
      variables: [Variable<String>(otherTagId), Variable<int>(now)],
    );

    // ── the old column ──────────────────────────────────────────────────────────────────────
    //
    // **Dropped, not left beside the new one.** Two sources for one value is what §6 forbids outright, and a
    // shadow column that drifts is worse than a migration that has to be right once.
    //
    // `alterTable` rather than `DROP COLUMN`: SQLite gained that statement in 3.35, and the version bundled
    // with `sqlite3_flutter_libs` on an older Android is not guaranteed to have it. `TableMigration` recreates
    // the table from the v5 schema and copies every remaining column across, which works everywhere.
    await m.alterTable(TableMigration(schema.items));
  },
);

/// Thrown when a database presents a schema version this build cannot migrate.
class DatabaseSchemaError extends Error {
  /// Creates the error with a human-readable [message].
  DatabaseSchemaError(this.message);

  /// What went wrong, and what the user's options are.
  final String message;

  @override
  String toString() => 'DatabaseSchemaError: $message';
}

/// True in debug and profile builds, false in release.
///
/// Uses the assert-side-effect idiom rather than `kDebugMode` so that this file — and everything
/// under `lib/data/db/` — stays free of any `package:flutter` import, which also means the whole
/// migration path is exercisable from a plain `dart test`.
bool get _isDebugBuild {
  var isDebug = false;
  assert(() {
    isDebug = true;
    return true;
  }());
  return isDebug;
}

/// Fails loudly in debug builds if the bundled SQLite lacks FTS5 (ARCH_2 §10, risk R3).
///
/// Checked at open time rather than trusted, because the symptom otherwise appears much later as
/// "search returns nothing" — with no indication that the index was never created.
Future<void> _assertFts5Available(AlayaDatabase db) async {
  final rows = await db.customSelect('PRAGMA compile_options').get();
  final options = rows
      .map((row) => row.data.values.first)
      .whereType<String>()
      .map((value) => value.toUpperCase())
      .toList();
  final hasFts5 = options.any((option) => option.contains('ENABLE_FTS5'));
  assert(
    hasFts5,
    'The bundled SQLite was built without FTS5. items_fts and transactions_fts cannot work, so '
    'search would silently return nothing. Check the sqlite3 package version (ARCH_1 §7) before '
    'going further.',
  );
}
