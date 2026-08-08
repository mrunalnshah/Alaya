/// A local civil date stored as an integer `yyyymmdd` (e.g. `20260728`), with zero runtime
/// overhead over the `int` it wraps. Deliberately has no timezone or time-of-day component
/// (Law L4): a bill "due on the 5th" is the 5th regardless of where the user is standing,
/// which is why this is never a `DateTime`/instant. `DateKey(rawValue)` does not validate —
/// it exists for cheap, trusted round-tripping of a value already known to be valid (e.g.
/// hydrating a database row). Build a validated instance from components with
/// [DateKey.fromYmd] or [DateKey.fromDateTime].
///
/// Note this cannot declare `implements Comparable<DateKey>`: an extension type may only
/// implement supertypes of its representation type, and `int` implements `Comparable<num>`,
/// not `Comparable<DateKey>`. [compareTo] is therefore a plain method, and sorting a
/// `List<DateKey>` uses the static [DateKey.compare] as an explicit comparator.
extension type const DateKey(int value) {
  /// Builds a validated [DateKey] from calendar components. Throws [ArgumentError] if the
  /// combination isn't a real calendar date (e.g. 30 February).
  factory DateKey.fromYmd(int year, int month, int day) {
    if (month < 1 || month > 12) {
      throw ArgumentError.value(month, 'month', 'must be between 1 and 12');
    }
    if (day < 1 || day > 31) {
      throw ArgumentError.value(day, 'day', 'must be between 1 and 31');
    }
    final rolled = DateTime.utc(year, month, day);
    if (rolled.year != year || rolled.month != month || rolled.day != day) {
      throw ArgumentError('$year-$month-$day is not a real calendar date');
    }
    return DateKey(year * 10000 + month * 100 + day);
  }

  /// Builds a [DateKey] from [dateTime]'s own year/month/day fields, taken exactly as they
  /// are on [dateTime] — this never calls `.toUtc()`, so passing a local `DateTime` yields
  /// the local civil date, which is almost always what "today" should mean.
  factory DateKey.fromDateTime(DateTime dateTime) =>
      DateKey.fromYmd(dateTime.year, dateTime.month, dateTime.day);

  /// The 4-digit year component.
  int get year => value ~/ 10000;

  /// The 1-based month component, `1`-`12`.
  int get month => (value ~/ 100) % 100;

  /// The 1-based day-of-month component.
  int get day => value % 100;

  /// The `yyyymm` month this date falls in, e.g. `20260728` → `202607`.
  int get monthKey => value ~/ 100;

  /// ISO weekday: `1` (Monday) through `7` (Sunday).
  int get weekday => toUtcMidnight().weekday;

  /// This date as a UTC-anchored midnight [DateTime]. This exists purely as a calculation
  /// vehicle for calendar arithmetic (UTC has no DST jumps, so day-arithmetic is exact) — it
  /// is never a real instant and must never be persisted as one.
  DateTime toUtcMidnight() => DateTime.utc(year, month, day);

  /// A new [DateKey] this many calendar days after this one. [days] may be negative.
  DateKey addDays(int days) => DateKey.fromDateTime(toUtcMidnight().add(Duration(days: days)));

  /// The number of calendar days from [other] to this date; positive when this date is
  /// later, negative when earlier.
  int diffDays(DateKey other) => toUtcMidnight().difference(other.toUtcMidnight()).inDays;

  /// True if this date is strictly before [other].
  bool isBefore(DateKey other) => value < other.value;

  /// True if this date is strictly after [other].
  bool isAfter(DateKey other) => value > other.value;

  /// True if this date is on or after [start] and on or before [end] (inclusive).
  bool isWithin(DateKey start, DateKey end) => value >= start.value && value <= end.value;

  /// Compares this date with [other]: negative if earlier, zero if equal, positive if later.
  int compareTo(DateKey other) => value.compareTo(other.value);

  /// A comparator for sorting, e.g. `dates.sort(DateKey.compare)`. Needed because an
  /// extension type cannot implement `Comparable<DateKey>` (see the class doc), so the
  /// zero-argument `List.sort()` is unavailable.
  static int compare(DateKey a, DateKey b) => a.value.compareTo(b.value);

  /// True if this date is strictly before [other].
  bool operator <(DateKey other) => value < other.value;

  /// True if this date is before or the same as [other].
  bool operator <=(DateKey other) => value <= other.value;

  /// True if this date is strictly after [other].
  bool operator >(DateKey other) => value > other.value;

  /// True if this date is after or the same as [other].
  bool operator >=(DateKey other) => value >= other.value;

  /// Renders as `yyyy-mm-dd` for logs and debugging only — never for UI display.
  String toIso() => '$year-${_twoDigits(month)}-${_twoDigits(day)}';

  static String _twoDigits(int n) => n < 10 ? '0$n' : '$n';
}