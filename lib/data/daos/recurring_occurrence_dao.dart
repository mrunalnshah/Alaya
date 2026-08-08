import 'package:drift/drift.dart';

import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/date_key_filters.dart';

/// Typed access to `recurring_occurrences` — the third of the app's three append-only truths
/// (ARCH_1 §3.3).
class RecurringOccurrenceDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  RecurringOccurrenceDao(super.db);

  $RecurringOccurrencesTable get _table => attachedDatabase.recurringOccurrences;

  SimpleSelectStatement<$RecurringOccurrencesTable, RecurringOccurrenceRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Materialises the occurrence for `(templateId, dueDateKey)` if it does not already exist,
  /// and returns its id either way. Calling this twice is a no-op, never a crash.
  ///
  /// Implemented as read-then-insert inside one transaction rather than as an upsert, and that is
  /// a correctness requirement, not a style choice. `idx_recurring_occ` is a **partial** unique
  /// index (`... WHERE deleted_at IS NULL`), and SQLite rejects a partial index as an
  /// `ON CONFLICT` target unless the predicate is repeated in the target clause —
  /// `ON CONFLICT(template_id, due_date_key)` fails to compile with *"ON CONFLICT clause does not
  /// match any PRIMARY KEY or UNIQUE constraint"*. Drift's `DoUpdate.target` takes a column list
  /// with nowhere to put that predicate, so no drift upsert can dedupe against this index.
  /// Verified directly against SQLite.
  ///
  /// [InsertMode.insertOrIgnore] would also avoid the crash, and is rejected for a different
  /// reason: it swallows *every* constraint violation, so a bad `templateId` would silently
  /// insert nothing instead of surfacing the foreign-key error.
  ///
  /// Never creates money. A materialised occurrence is always `due`; only an explicit
  /// [markPaid] moves it, driven by a user tap (anomaly A14).
  Future<String> upsertForDue({
    required String id,
    required String templateId,
    required DateKey dueDateKey,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      final existing = await (_activeRows()
        ..where((t) => t.templateId.equals(templateId) & t.dueDateKey.isOnDate(dueDateKey)))
          .getSingleOrNull();
      if (existing != null) return existing.id;

      await into(_table).insert(
        RecurringOccurrencesCompanion.insert(
          id: id,
          templateId: templateId,
          dueDateKey: dueDateKey,
          status: RecurringOccurrenceStatus.due,
          createdAt: nowUtcMillis,
          updatedAt: nowUtcMillis,
        ),
      );
      return id;
    });
  }

  /// Emits the active occurrences of [templateId], newest due date first — the payment history.
  Stream<List<RecurringOccurrenceRow>> watchForTemplate(String templateId) {
    return (_activeRows()
      ..where((t) => t.templateId.equals(templateId))
      ..orderBy([(t) => OrderingTerm(expression: t.dueDateKey, mode: OrderingMode.desc)]))
        .watch();
  }

  /// Emits active occurrences due within `[from, to]`, whatever their status — the calendar's
  /// `recurringDue` source once filtered to `due` by the caller.
  Stream<List<RecurringOccurrenceRow>> watchDueInRange({
    required DateKey from,
    required DateKey to,
  }) {
    return (_activeRows()
      ..where((t) => t.dueDateKey.isInDateRange(from, to))
      ..orderBy([(t) => OrderingTerm(expression: t.dueDateKey)]))
        .watch();
  }

  /// Reads active occurrences still `due` on or before [asOf] — the overdue set, with the
  /// comparison supplied by the caller's `Clock` rather than by SQL (ARCH_2 §12.2).
  Future<List<RecurringOccurrenceRow>> outstandingAsOf(DateKey asOf) {
    return (_activeRows()
      ..where((t) =>
      t.status.equalsValue(RecurringOccurrenceStatus.due) &
      t.dueDateKey.isDateOnOrBefore(asOf))
      ..orderBy([(t) => OrderingTerm(expression: t.dueDateKey)]))
        .get();
  }

  /// Reads one occurrence by id.
  Future<RecurringOccurrenceRow?> byId(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Records that [id] was settled by [transactionId] for [paidAmountMinor] on [paidDateKey].
  ///
  /// The paid amount is stored on the occurrence, never written back to the template's default
  /// (anomaly A29): paying ₹520 against a ₹499 template records ₹520 here and leaves ₹499 as the
  /// template's expectation, so analytics uses actuals without corrupting the schedule.
  Future<void> markPaid({
    required String id,
    required String transactionId,
    required int paidAmountMinor,
    required DateKey paidDateKey,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      RecurringOccurrencesCompanion(
        status: const Value(RecurringOccurrenceStatus.paid),
        paidTransactionId: Value(transactionId),
        paidAmountMinor: Value(paidAmountMinor),
        paidDateKey: Value(paidDateKey),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Marks [id] as deliberately skipped — the user chose not to pay this one.
  Future<void> markSkipped({
    required String id,
    String? note,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      RecurringOccurrencesCompanion(
        status: const Value(RecurringOccurrenceStatus.skipped),
        note: note == null ? const Value.absent() : Value(note),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Marks [id] as dismissed — it was never meaningfully due, e.g. the template was paused
  /// retroactively.
  Future<void> markDismissed({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      RecurringOccurrencesCompanion(
        status: const Value(RecurringOccurrenceStatus.dismissed),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Clears the settlement link when the transaction that paid this occurrence is deleted,
  /// returning it to `due` so the obligation reappears rather than silently vanishing.
  Future<void> unlinkDeletedTransaction({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      RecurringOccurrencesCompanion(
        status: const Value(RecurringOccurrenceStatus.due),
        paidTransactionId: const Value(null),
        paidAmountMinor: const Value(null),
        paidDateKey: const Value(null),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Soft-deletes an occurrence.
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      RecurringOccurrencesCompanion(
        deletedAt: Value(nowUtcMillis),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }
}