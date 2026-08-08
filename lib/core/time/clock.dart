import 'date_key.dart';

/// Supplies the current time so it can be faked in tests; no code outside this file should
/// call `DateTime.now()` directly. Deliberately a single-method interface: the derived values
/// live in [ClockDerived] as extension methods, so an implementation only ever has to supply
/// [now] and the derived values can never drift out of sync with it.
abstract interface class Clock {
  /// The current local wall-clock date and time.
  DateTime now();
}

/// Values derived from [Clock.now]. Extension methods rather than interface members with
/// default bodies: `implements` inherits an interface but not its method bodies, so a default
/// body on the interface would force every implementer to redeclare it anyway.
extension ClockDerived on Clock {
  /// The current instant as epoch milliseconds UTC (Law L4's instant representation).
  int nowUtcMillis() => now().toUtc().millisecondsSinceEpoch;

  /// Today's date in the device's local timezone, as a civil [DateKey].
  DateKey today() => DateKey.fromDateTime(now());
}

/// The production [Clock], backed by the real system time.
final class SystemClock implements Clock {
  /// Creates a clock that reads the device's real wall-clock time.
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// A [Clock] fixed to one instant, for deterministic tests. Call [advance] to move it
/// forward within a test instead of constructing a new instance each time.
final class FixedClock implements Clock {
  /// Creates a clock fixed at [initial].
  FixedClock(DateTime initial) : _current = initial;

  DateTime _current;

  @override
  DateTime now() => _current;

  /// Moves this clock forward by [duration] (or backward, if negative).
  void advance(Duration duration) => _current = _current.add(duration);

  /// Sets this clock to exactly [dateTime].
  void setTo(DateTime dateTime) => _current = dateTime;
}