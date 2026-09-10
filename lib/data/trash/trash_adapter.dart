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
