import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/core/time/date_key.dart';

/// Reads the unified calendar feed.
///
/// Exists as a domain contract because `domain/services/calendar_aggregator.dart` consumes it, and
/// Law L12 forbids anything under `domain/` importing from `data/`.
abstract interface class CalendarRepository {
  /// Emits the events falling within `[from, to]`.
  ///
  /// **Always bounded.** Unbounded, the underlying view scans seven tables; bounded, each arm uses
  /// its own date index. Callers should request the visible month plus a month of prefetch, not
  /// everything.
  Stream<List<CalendarEvent>> watchRange({
    required DateKey from,
    required DateKey to,
  });

  /// Reads the events falling on exactly [dateKey], for the day-detail sheet.
  Future<List<CalendarEvent>> forDay(DateKey dateKey);

  /// Reads how many events fall on each date in `[from, to]`, for the month grid's severity dots.
  ///
  /// Returns counts keyed by date rather than the events themselves, because a month grid needs a
  /// dot per day and not several hundred full event objects.
  Future<Map<DateKey, int>> countsByDate({
    required DateKey from,
    required DateKey to,
  });
}
