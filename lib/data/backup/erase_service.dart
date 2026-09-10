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
