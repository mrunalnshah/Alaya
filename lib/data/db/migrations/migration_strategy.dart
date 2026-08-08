import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Populates a freshly created database. Injected rather than called directly so tests can seed
/// deterministically, or skip seeding entirely.
typedef DatabaseSeeder = Future<void> Function(AlayaDatabase db);

/// Builds the [MigrationStrategy] for [db].
///
/// Three responsibilities, in order of how easy they are to get wrong:
///
/// 1. **`beforeOpen` turns foreign keys on.** SQLite defaults `PRAGMA foreign_keys` to *off*,
///    per-connection, and drift does not change that. Until this runs, all 51 foreign keys in the
///    schema are declared and completely unenforced. This is the single most important line in
///    the file.
/// 2. **`onCreate` creates the schema and then seeds it.** `createAll()` covers the 26 tables,
///    11 views, 22 indexes and 2 FTS tables, because drift registers everything in the
///    `@DriftDatabase` annotation's `tables` and `include` sets.
/// 3. **`onUpgrade` is a deliberate scaffold.** See the note on [_onUpgrade].
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

/// Handles a schema upgrade.
///
/// At `schemaVersion = 1` there is nothing to upgrade *from*, so any invocation here means the
/// database was written by a build whose schema version this build does not know about — which
/// [DatabaseSchemaError] reports rather than silently continuing against a schema it cannot
/// interpret.
///
/// When v2 lands, replace this with drift's generated `stepByStep` helper:
///
/// ```dart
/// onUpgrade: stepByStep(from1To2: (m, schema) async { ... }),
/// ```
///
/// That helper is *generated* from the committed schema snapshots — see
/// `lib/data/db/migrations/schema/README.md`. It cannot exist until there are at least two
/// versions to step between, which is exactly why the v1 snapshot has to be committed now.
Future<void> _onUpgrade(Migrator m, int from, int to) async {
  throw DatabaseSchemaError(
    'Unsupported schema upgrade $from -> $to. Schema version 1 has no predecessors, so this '
        'database was created by a different build. Restore a backup taken by a compatible version, '
        'or reinstall.',
  );
}

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