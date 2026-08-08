import 'package:drift/drift.dart';

import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/date_key_filters.dart';

/// Typed access to `recurring_templates`, plus `v_recurring_due` for the due-list read.
///
/// **No method here ever writes `anchorDayOfMonth`, `anchorMonth` or `anchorWeekday` except
/// [upsert].** Those columns are stored once and clamped at *render* (anomaly A13): a bill
/// anchored on the 31st must stay anchored on the 31st, not walk backwards to the 28th
/// permanently after one February. [advanceNextDue] moves `nextDueDateKey` and nothing else,
/// which is exactly why the anchor survives.
class RecurringTemplateDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  RecurringTemplateDao(super.db);

  $RecurringTemplatesTable get _table => attachedDatabase.recurringTemplates;

  SimpleSelectStatement<$RecurringTemplatesTable, RecurringTemplateRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits every active template, paused included, in name order.
  Stream<List<RecurringTemplateRow>> watchAll() =>
      (_activeRows()..orderBy([(t) => OrderingTerm(expression: t.normalizedName)])).watch();

  /// Emits active templates in [direction] — the split that lets salary live in the same system
  /// as bills rather than needing a second one (anomaly A27).
  Stream<List<RecurringTemplateRow>> watchByDirection(RecurringDirection direction) {
    return (_activeRows()
      ..where((t) => t.direction.equalsValue(direction))
      ..orderBy([(t) => OrderingTerm(expression: t.nextDueDateKey)]))
        .watch();
  }

  /// Emits active, unpaused templates whose next due date falls in `[from, to]`.
  Stream<List<RecurringTemplateRow>> watchDueInRange({
    required DateKey from,
    required DateKey to,
  }) {
    return (_activeRows()
      ..where((t) => t.isPaused.equals(false) & t.nextDueDateKey.isInDateRange(from, to))
      ..orderBy([(t) => OrderingTerm(expression: t.nextDueDateKey)]))
        .watch();
  }

  /// Reads active, unpaused templates whose next due date is on or before [asOf] — what the
  /// recurring engine walks to materialise occurrences lazily up to today (anomaly A14).
  Future<List<RecurringTemplateRow>> needingMaterialisation(DateKey asOf) {
    return (_activeRows()
      ..where((t) => t.isPaused.equals(false) & t.nextDueDateKey.isDateOnOrBefore(asOf))
      ..orderBy([(t) => OrderingTerm(expression: t.nextDueDateKey)]))
        .get();
  }

  /// Reads one template by id, including a soft-deleted one — a settled occurrence and its
  /// transaction outlive the template, so the history still needs a name to render.
  Future<RecurringTemplateRow?> byIdIncludingDeleted(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads one active template by normalized name, for the merge-or-create decision.
  Future<RecurringTemplateRow?> byNormalizedName(String normalizedName) =>
      (_activeRows()..where((t) => t.normalizedName.equals(normalizedName))).getSingleOrNull();

  /// Emits active templates linked to [assetId] — the house-maid salary case, where a service
  /// provider's monthly payment hangs off an `assets` row (ARCH_2 §8.1).
  Stream<List<RecurringTemplateRow>> watchForAsset(String assetId) =>
      (_activeRows()..where((t) => t.linkedAssetId.equals(assetId))).watch();

  /// Inserts or updates a template.
  ///
  /// Upserts on the primary key, so the repository must resolve identity first via
  /// [byNormalizedName] and pass the existing row's `id` to update rather than create. Drift's
  /// default conflict target is the primary key, and `recurring_templates` has no other unique
  /// index, so there is nothing subtler happening here.
  Future<void> upsert(RecurringTemplatesCompanion template) =>
      into(_table).insertOnConflictUpdate(template);

  /// Moves `nextDueDateKey` forward after an occurrence is settled or skipped.
  ///
  /// Writes that one column and `updatedAt`. The anchor columns are untouched by construction —
  /// see this class's doc comment.
  Future<void> advanceNextDue({
    required String id,
    required DateKey nextDueDateKey,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      RecurringTemplatesCompanion(
        nextDueDateKey: Value(nextDueDateKey),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Pauses or resumes a template. A paused template materialises no new occurrences and leaves
  /// `v_recurring_due` entirely.
  Future<void> setPaused({
    required String id,
    required bool isPaused,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      RecurringTemplatesCompanion(isPaused: Value(isPaused), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Soft-deletes a template. Settled occurrences and the transactions they created survive
  /// untouched (ARCH_3 §4.1) — deleting a subscription does not un-pay last month's bill.
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      RecurringTemplatesCompanion(
        deletedAt: Value(nowUtcMillis),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  // ── the view ──────────────────────────────────────────────────────────────────────────

  /// Emits `v_recurring_due` — active, unpaused templates joined to their outstanding `due`
  /// occurrence.
  ///
  /// The view has no `isOverdue` column, deliberately: overdue is
  /// `occurrenceDueDateKey < clock.today()`, computed in Dart with the injected `Clock` so it
  /// stays deterministic and timezone-independent (ARCH_2 §12.2, Law L4).
  Stream<List<RecurringDueRow>> watchDue() => select(attachedDatabase.vRecurringDue).watch();

  /// Reads `v_recurring_due` once.
  Future<List<RecurringDueRow>> due() => select(attachedDatabase.vRecurringDue).get();
}