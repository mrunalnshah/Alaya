import 'package:drift/drift.dart';

import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `notification_schedule` (ARCH_3 §7).
///
/// The table exists so every OS-level notification has a stable integer id that can be cancelled
/// when the record behind it changes — without it you get reminders for food already eaten.
class NotificationScheduleDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  NotificationScheduleDao(super.db);

  $NotificationScheduleTable get _table => attachedDatabase.notificationSchedule;

  SimpleSelectStatement<$NotificationScheduleTable, NotificationScheduleRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits every row still `scheduled`, soonest first.
  Stream<List<NotificationScheduleRow>> watchScheduled() {
    return (_activeRows()
      ..where((t) => t.status.equalsValue(NotificationStatus.scheduled))
      ..orderBy([(t) => OrderingTerm(expression: t.scheduledAtUtcMillis)]))
        .watch();
  }

  /// Reads rows still `scheduled` at or before [beforeUtcMillis] — what the daily `workmanager`
  /// job collects to hand to the OS.
  Future<List<NotificationScheduleRow>> scheduledDueBefore(int beforeUtcMillis) {
    return (_activeRows()
      ..where((t) =>
      t.status.equalsValue(NotificationStatus.scheduled) &
      t.scheduledAtUtcMillis.isSmallerOrEqualValue(beforeUtcMillis))
      ..orderBy([(t) => OrderingTerm(expression: t.scheduledAtUtcMillis)]))
        .get();
  }

  /// Reads the active rows pointing at `(refType, refId)`.
  Future<List<NotificationScheduleRow>> forRef({
    required String refType,
    required String refId,
  }) {
    return (_activeRows()..where((t) => t.refType.equals(refType) & t.refId.equals(refId))).get();
  }

  /// The next free `androidNotificationId`, one past the highest ever used.
  ///
  /// Deliberately reads across **every** row including cancelled and soft-deleted ones, rather
  /// than only live ones: reusing the id of a cancelled reminder risks colliding with a
  /// notification the OS has not actually dropped yet, and the user would see the wrong reminder
  /// dismissed. Starts at 1 — Android treats 0 as a valid id but some launchers handle it oddly,
  /// and starting at 1 costs nothing.
  Future<int> nextAndroidNotificationId() async {
    final highest = _table.androidNotificationId.max();
    final row = await (selectOnly(_table)..addColumns([highest])).getSingle();
    return (row.read(highest) ?? 0) + 1;
  }

  /// Replaces the schedule for `(refType, refId)` with [replacement], in one transaction
  /// (Law L14), and **returns the `androidNotificationId`s it superseded**.
  ///
  /// Those returned ids are the point of this method. Cancelling a reminder in the database does
  /// nothing to the notification already registered with Android, so the caller must cancel each
  /// returned id through `flutter_local_notifications` too. Returning them makes that step
  /// impossible to overlook; discovering it later means orphaned reminders that no longer
  /// correspond to anything.
  Future<List<int>> replaceForRef({
    required String refType,
    required String refId,
    required NotificationScheduleCompanion replacement,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      final superseded = await forRef(refType: refType, refId: refId);
      await (update(_table)
        ..where((t) =>
        t.refType.equals(refType) &
        t.refId.equals(refId) &
        t.status.equalsValue(NotificationStatus.scheduled)))
          .write(
        NotificationScheduleCompanion(
          status: const Value(NotificationStatus.cancelled),
          updatedAt: Value(nowUtcMillis),
        ),
      );
      await into(_table).insert(replacement);
      return superseded.map((row) => row.androidNotificationId).toList();
    });
  }

  /// Marks [id] as delivered.
  Future<void> markFired({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      NotificationScheduleCompanion(
        status: const Value(NotificationStatus.fired),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Cancels every scheduled row for `(refType, refId)` and returns the superseded Android ids,
  /// for the same reason [replaceForRef] does — used when the underlying record is deleted or
  /// resolved and no replacement reminder is wanted.
  Future<List<int>> cancelForRef({
    required String refType,
    required String refId,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      final cancelled = await (_activeRows()
        ..where((t) =>
        t.refType.equals(refType) &
        t.refId.equals(refId) &
        t.status.equalsValue(NotificationStatus.scheduled)))
          .get();
      await (update(_table)
        ..where((t) =>
        t.refType.equals(refType) &
        t.refId.equals(refId) &
        t.status.equalsValue(NotificationStatus.scheduled)))
          .write(
        NotificationScheduleCompanion(
          status: const Value(NotificationStatus.cancelled),
          updatedAt: Value(nowUtcMillis),
        ),
      );
      return cancelled.map((row) => row.androidNotificationId).toList();
    });
  }

  /// Cancels every scheduled row and returns their Android ids — what "turn all reminders off"
  /// in Settings calls.
  Future<List<int>> cancelAll({required int nowUtcMillis}) {
    return transaction(() async {
      final cancelled = await (_activeRows()
        ..where((t) => t.status.equalsValue(NotificationStatus.scheduled)))
          .get();
      await (update(_table)
        ..where((t) => t.status.equalsValue(NotificationStatus.scheduled)))
          .write(
        NotificationScheduleCompanion(
          status: const Value(NotificationStatus.cancelled),
          updatedAt: Value(nowUtcMillis),
        ),
      );
      return cancelled.map((row) => row.androidNotificationId).toList();
    });
  }

  /// Inserts one scheduled row.
  Future<void> insertSchedule(NotificationScheduleCompanion schedule) =>
      into(_table).insert(schedule);

  /// Soft-deletes rows that have already fired or been cancelled and are older than
  /// [olderThanUtcMillis] — housekeeping so the table does not grow without bound.
  Future<int> pruneSettled({
    required int olderThanUtcMillis,
    required int nowUtcMillis,
  }) {
    return (update(_table)
      ..where((t) =>
      t.deletedAt.isNull() &
      t.scheduledAtUtcMillis.isSmallerThanValue(olderThanUtcMillis) &
      t.status.equalsValue(NotificationStatus.scheduled).not()))
        .write(
      NotificationScheduleCompanion(
        deletedAt: Value(nowUtcMillis),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }
}
