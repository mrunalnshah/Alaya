import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/repositories/calendar_repository.dart';

/// One day's worth of calendar entries, with the day's worst severity precomputed.
typedef CalendarDay = ({
  DateKey date,
  List<CalendarEvent> events,
  CalendarSeverity severity,
});

/// Reads the calendar feed and applies ARCH_3 §6's severity rules.
///
/// The view emits a **static baseline** severity because no view in this schema consults the clock
/// (ARCH_2 §12.2). Everything date-relative therefore happens here, against a `today` passed in — so
/// a calendar rendered under a `FixedClock` is reproducible, and the severity of an entry does not
/// change merely because the test suite ran after midnight.
final class CalendarAggregator {
  /// Creates the aggregator over [repository].
  const CalendarAggregator(this._repository);

  final CalendarRepository _repository;

  /// Days before an expiring batch turns from `info` to `warning` (ARCH_3 §6).
  static const int batchExpiryWarningDays = 7;

  /// Days before a service falls due that it turns to `warning`.
  static const int serviceDueWarningDays = 7;

  /// Days before a warranty ends that it turns to `warning`.
  ///
  /// Thirty rather than seven, deliberately per §6: a warranty is worth acting on well before it
  /// lapses, because arranging a claim takes time that an expiring yoghurt does not.
  static const int warrantyEndWarningDays = 30;

  /// Emits the events in `[from, to]` with severity resolved against [today].
  ///
  /// Always bounded — an unbounded read scans seven tables, where a bounded one uses each source's
  /// own date index.
  Stream<List<CalendarEvent>> watchRange({
    required DateKey from,
    required DateKey to,
    required DateKey today,
  }) {
    return _repository
        .watchRange(from: from, to: to)
        .map(
          (events) => events
              .map((e) => resolveSeverity(event: e, today: today))
              .toList(),
        );
  }

  /// Groups the events in `[from, to]` by day, for a month grid.
  ///
  /// Days with no events are omitted rather than included empty — a grid renders 28 to 31 cells
  /// regardless, and it needs to know which have something, not to receive a placeholder for each
  /// that does not.
  Stream<List<CalendarDay>> watchDays({
    required DateKey from,
    required DateKey to,
    required DateKey today,
  }) {
    return watchRange(from: from, to: to, today: today).map(groupByDay);
  }

  /// Reads one day's events, severity resolved.
  Future<List<CalendarEvent>> forDay({
    required DateKey dateKey,
    required DateKey today,
  }) async {
    final events = await _repository.forDay(dateKey);
    return events.map((e) => resolveSeverity(event: e, today: today)).toList();
  }

  /// How many events fall on each date, for the grid's dots.
  Future<Map<DateKey, int>> countsByDate({
    required DateKey from,
    required DateKey to,
  }) => _repository.countsByDate(from: from, to: to);

  /// Groups [events] into days, each carrying that day's worst severity.
  List<CalendarDay> groupByDay(List<CalendarEvent> events) {
    final byDate = <int, List<CalendarEvent>>{};
    for (final event in events) {
      (byDate[event.dateKey.value] ??= <CalendarEvent>[]).add(event);
    }

    final days = byDate.entries.map((entry) {
      final dayEvents = entry.value;
      return (
        date: DateKey(entry.key),
        events: dayEvents,
        severity: worstSeverity(dayEvents),
      );
    }).toList()..sort((a, b) => DateKey.compare(a.date, b.date));
    return days;
  }

  /// The most urgent severity among [events], for a day's single dot.
  CalendarSeverity worstSeverity(Iterable<CalendarEvent> events) {
    var worst = CalendarSeverity.info;
    for (final event in events) {
      if (event.baseSeverity == CalendarSeverity.danger)
        return CalendarSeverity.danger;
      if (event.baseSeverity == CalendarSeverity.warning)
        worst = CalendarSeverity.warning;
    }
    return worst;
  }

  /// Returns [event] with its severity escalated per ARCH_3 §6's **per-type** thresholds.
  ///
  /// The thresholds differ by type, and that is the substance of this method rather than an
  /// incidental detail: a warranty warns at 30 days, an expiry and a service at 7, and only an expiry
  /// escalates to `danger` once past. `CalendarEvent.severityAsOf` from Phase 3A applies a single
  /// generic rule to every type, which does not implement this table — this method supersedes it, and
  /// that entity method should be removed when a phase next touches it.
  ///
  /// A `transaction` never escalates. It records something that already happened, so "overdue" is
  /// meaningless for it.
  CalendarEvent resolveSeverity({
    required CalendarEvent event,
    required DateKey today,
  }) {
    final resolved = severityFor(event: event, today: today);
    if (resolved == event.baseSeverity) return event;
    return CalendarEvent(
      dateKey: event.dateKey,
      type: event.type,
      refType: event.refType,
      refId: event.refId,
      title: event.title,
      baseSeverity: resolved,
      amount: event.amount,
    );
  }

  /// The severity [event] should render with as of [today].
  CalendarSeverity severityFor({
    required CalendarEvent event,
    required DateKey today,
  }) {
    final daysAway = event.dateKey.diffDays(today);
    final isPast = daysAway < 0;

    switch (event.type) {
      case CalendarEventType.transaction:
        return CalendarSeverity.info;

      case CalendarEventType.shoppingTarget:
        // A shopping date the user set and let slip is not an alarm — the list is still there.
        return CalendarSeverity.info;

      case CalendarEventType.recurringDue:
        // §6 says warning once past, not danger. An unpaid bill is the user's decision to make, and
        // the recurring screen already surfaces it; the calendar does not need to shout.
        return isPast ? CalendarSeverity.warning : CalendarSeverity.info;

      case CalendarEventType.batchExpiry:
        // The only type that reaches danger. Food past its date is the one calendar entry where
        // acting late has already cost something.
        if (isPast) return CalendarSeverity.danger;
        return daysAway <= batchExpiryWarningDays
            ? CalendarSeverity.warning
            : CalendarSeverity.info;

      case CalendarEventType.warrantyEnd:
        if (isPast) return CalendarSeverity.info;
        return daysAway <= warrantyEndWarningDays
            ? CalendarSeverity.warning
            : CalendarSeverity.info;

      case CalendarEventType.serviceDue:
        if (isPast) return CalendarSeverity.warning;
        return daysAway <= serviceDueWarningDays
            ? CalendarSeverity.warning
            : CalendarSeverity.info;

      case CalendarEventType.splitSettleBy:
        // Warning once past, matching `recurringDue` rather than `batchExpiry`. An unsettled debt is a
        // conversation the user has not had yet; food past its date has already cost something, which
        // is why that stays the only type reaching danger.
        return isPast ? CalendarSeverity.warning : CalendarSeverity.info;
    }
  }
}
