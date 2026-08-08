import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Reads `v_calendar_events`, the `UNION ALL` view behind the calendar (ARCH_3 §6).
///
/// **Every read is bounded.** Unbounded, the view scans seven tables; bounded on `date_key`, each arm
/// uses its own date index. There is deliberately no "all events" method for a caller to reach for.
///
/// The view emits `severity` as a static baseline and never consults the clock (ARCH_2 §12.2), so this
/// DAO returns rows unescalated. `CalendarAggregator` applies the per-type thresholds.
class CalendarDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  CalendarDao(super.db);

  /// Emits the rows falling in `[fromDateKey, toDateKey]`, inclusive.
  Stream<List<CalendarEventRow>> watchRange({
    required int fromDateKey,
    required int toDateKey,
  }) =>
      (select(attachedDatabase.vCalendarEvents)
            ..where((t) => t.dateKey.isBetweenValues(fromDateKey, toDateKey))
            ..orderBy([
              (t) => OrderingTerm.asc(t.dateKey),
              (t) => OrderingTerm.asc(t.eventType),
              (t) => OrderingTerm.asc(t.refId),
            ]))
          .watch();

  /// Reads the rows falling in `[fromDateKey, toDateKey]`, inclusive.
  Future<List<CalendarEventRow>> range({
    required int fromDateKey,
    required int toDateKey,
  }) =>
      (select(attachedDatabase.vCalendarEvents)
            ..where((t) => t.dateKey.isBetweenValues(fromDateKey, toDateKey))
            ..orderBy([
              (t) => OrderingTerm.asc(t.dateKey),
              (t) => OrderingTerm.asc(t.eventType),
              (t) => OrderingTerm.asc(t.refId),
            ]))
          .get();

  /// Reads the rows falling on exactly [dateKey].
  Future<List<CalendarEventRow>> forDay(int dateKey) =>
      range(fromDateKey: dateKey, toDateKey: dateKey);

  /// Counts rows per `date_key` across `[fromDateKey, toDateKey]`.
  ///
  /// Grouped in SQL rather than by materialising every row and counting in Dart: a month grid needs a
  /// dot per day, and a busy month is several hundred rows to discard.
  Future<Map<int, int>> countsByDate({
    required int fromDateKey,
    required int toDateKey,
  }) async {
    final view = attachedDatabase.vCalendarEvents;
    final total = countAll();
    final query = selectOnly(view)
      ..addColumns([view.dateKey, total])
      ..where(view.dateKey.isBetweenValues(fromDateKey, toDateKey))
      ..groupBy([view.dateKey]);

    final rows = await query.get();
    return {
      for (final row in rows) row.read(view.dateKey)!: row.read(total)!,
    };
  }
}
