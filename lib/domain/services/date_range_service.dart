import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/time/date_key.dart';

/// An inclusive civil-date window: every `DateKey` from [from] to [to], both ends counted.
typedef DateRange = ({DateKey from, DateKey to});

/// Resolves a [DateRangePreset] into concrete dates.
///
/// Takes `today` as a parameter on every call rather than holding a `Clock`, for the same reason no
/// view in this schema consults the clock (ARCH_2 §12.2): a range that reads the time itself cannot
/// be asserted against a `FixedClock`, and every analytics figure downstream would inherit that
/// non-determinism.
///
/// Both ends are **inclusive**, matching `DateKeyColumnFilters.isInDateRange` and SQL's `BETWEEN`,
/// so a resolved range can be handed straight to a query without an off-by-one adjustment.
final class DateRangeService {
  /// Creates the service.
  const DateRangeService();

  /// The earliest date this app treats as real, used as the lower bound for [DateRangePreset.allTime].
  ///
  /// A sentinel rather than a query for the oldest row: "all time" must resolve without touching the
  /// database, and `1900-01-01` is comfortably before any household record while staying well inside
  /// `DateKey`'s range.
  static final DateKey earliest = DateKey.fromYmd(1900, 1, 1);

  /// Resolves [preset] against [today].
  ///
  /// Returns null for [DateRangePreset.custom], which by definition carries dates this service does
  /// not know — the caller supplies them. Returning null rather than a guessed window means a UI
  /// that forgets to handle `custom` shows nothing instead of silently showing the wrong month.
  DateRange? resolve(DateRangePreset preset, DateKey today) {
    switch (preset) {
      case DateRangePreset.today:
        return (from: today, to: today);

      case DateRangePreset.last7Days:
      // Six days back, not seven: "last 7 days" includes today, so today plus six earlier days is
      // seven dates. Subtracting seven would span eight.
        return (from: today.addDays(-6), to: today);

      case DateRangePreset.last30Days:
        return (from: today.addDays(-29), to: today);

      case DateRangePreset.thisMonth:
        return (from: DateKey.fromYmd(today.year, today.month, 1), to: today);

      case DateRangePreset.lastMonth:
        final year = today.month == 1 ? today.year - 1 : today.year;
        final month = today.month == 1 ? 12 : today.month - 1;
        return (
        from: DateKey.fromYmd(year, month, 1),
        to: DateKey.fromYmd(year, month, _lastDayOfMonth(year, month)),
        );

      case DateRangePreset.thisYear:
        return (from: DateKey.fromYmd(today.year, 1, 1), to: today);

      case DateRangePreset.allTime:
        return (from: earliest, to: today);

      case DateRangePreset.custom:
        return null;
    }
  }

  /// The calendar month containing [anyDayInMonth], whole.
  ///
  /// What a month-grid calendar asks for: the full month regardless of where today falls, unlike
  /// [DateRangePreset.thisMonth] which stops at today.
  DateRange wholeMonthOf(DateKey anyDayInMonth) {
    final year = anyDayInMonth.year;
    final month = anyDayInMonth.month;
    return (
    from: DateKey.fromYmd(year, month, 1),
    to: DateKey.fromYmd(year, month, _lastDayOfMonth(year, month)),
    );
  }

  /// The month before [range]'s start, whole — for a period-over-period comparison.
  DateRange previousWholeMonth(DateKey anyDayInMonth) {
    final year = anyDayInMonth.month == 1 ? anyDayInMonth.year - 1 : anyDayInMonth.year;
    final month = anyDayInMonth.month == 1 ? 12 : anyDayInMonth.month - 1;
    return (
    from: DateKey.fromYmd(year, month, 1),
    to: DateKey.fromYmd(year, month, _lastDayOfMonth(year, month)),
    );
  }

  /// A window of the same length as [range] ending the day before it starts.
  ///
  /// The honest comparison for a rolling preset: "last 30 days" against the 30 days before those,
  /// rather than against a calendar month of a different length.
  DateRange precedingWindowOf(DateRange range) {
    final lengthDays = range.to.diffDays(range.from);
    final end = range.from.addDays(-1);
    return (from: end.addDays(-lengthDays), to: end);
  }

  /// True when [date] falls inside [range], both ends counted.
  bool contains(DateRange range, DateKey date) =>
      date.isWithin(range.from, range.to);

  /// How many dates [range] spans, both ends counted.
  int lengthInDays(DateRange range) => range.to.diffDays(range.from) + 1;

  /// Day zero of the following month is the last day of this one, which handles February in both
  /// leap and non-leap years without a lookup table.
  static int _lastDayOfMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;
}