import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/calendar_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/repositories/calendar_repository.dart';

/// Reads the unified calendar feed from `v_calendar_events`.
///
/// Phase 3A declared [CalendarRepository] and no phase implemented it, which left
/// `CalendarAggregator` with no provider and three of its methods unreachable (ARCH_4 §5.1 item 15).
/// This closes that.
///
/// **Returns rows with their baseline severity, unescalated.** The escalation thresholds differ per
/// event type (ARCH_3 §6) and depend on the current date, so they belong in `CalendarAggregator` with
/// the injected `Clock` — not here, and not in the view (ARCH_2 §12.2).
class CalendarRepositoryImpl implements CalendarRepository {
  /// Creates the repository over [dao].
  const CalendarRepositoryImpl(this._dao);

  final CalendarDao _dao;

  @override
  Stream<List<CalendarEvent>> watchRange({
    required DateKey from,
    required DateKey to,
  }) => _dao
      .watchRange(fromDateKey: from.value, toDateKey: to.value)
      .map((rows) => rows.map(_toEntity).toList());

  @override
  Future<List<CalendarEvent>> forDay(DateKey dateKey) async {
    final rows = await _dao.forDay(dateKey.value);
    return rows.map(_toEntity).toList();
  }

  @override
  Future<Map<DateKey, int>> countsByDate({
    required DateKey from,
    required DateKey to,
  }) async {
    final counts = await _dao.countsByDate(
      fromDateKey: from.value,
      toDateKey: to.value,
    );
    return {
      for (final entry in counts.entries) DateKey(entry.key): entry.value,
    };
  }

  /// Maps one view row onto the domain entity.
  ///
  /// `event_type` and `severity` decode by enum *name*, which Law L11 makes the schema contract: the
  /// view's arms emit the literals `'transaction'`, `'recurringDue'` and so on, and renaming a value
  /// in either enum is a breaking change to this view.
  CalendarEvent _toEntity(CalendarEventRow row) {
    final minor = row.amountMinor;
    final currency = row.currencyCode;

    return CalendarEvent(
      // `DateKey?`, not `int`: the view column carries `DateKeyConverter`, and drift types it nullable
      // because six of the seven arms select a nullable column. Every one of those arms filters
      // `IS NOT NULL`, and the transaction arm's `date_key` is NOT NULL, so a null here means the view
      // changed and throwing is the correct response.
      dateKey: row.dateKey!,
      type: CalendarEventType.values.byName(row.eventType),
      refType: row.refType,
      refId: row.refId,
      title: row.title,
      baseSeverity: CalendarSeverity.values.byName(row.severity),
      amount: minor != null && currency != null ? Money(minor, currency) : null,
    );
  }
}
