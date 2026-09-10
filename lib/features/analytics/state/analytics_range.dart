import 'package:alaya/core/enums/date_range_preset.dart';

/// Which reporting window the analytics screen is showing, and how it is remembered.
///
/// Wraps `DateRangePreset` rather than declaring a second enum: `DateRangeService` already resolves
/// every preset, and a parallel enum would need a mapping that drifts. The preset itself is never
/// stored in the database — only as an `app_settings` string — so Law L13 does not reach it
/// (`date_range_preset.dart` says as much).
abstract final class AnalyticsRange {
  /// The `app_settings` key the chosen preset is stored under.
  static const String settingsKey = 'analytics.range';

  /// The default window: the current calendar month to date.
  ///
  /// A month is the unit a household budgets in, and it is the only preset that is both bounded and
  /// non-empty on the day the app is installed.
  static const DateRangePreset fallback = DateRangePreset.thisMonth;

  /// The presets the range row offers, in the order they appear.
  ///
  /// [DateRangePreset.today] is omitted: a one-day window makes every trend a single point, and the
  /// calendar already answers "what happened today" better than a chart can.
  /// [DateRangePreset.custom] is omitted because `DateRangeService.resolve` returns null for it by
  /// design — the caller supplies the dates — and 7B ships no date-range picker. Recorded as a
  /// deferral rather than silently absent.
  static const List<DateRangePreset> presets = [
    DateRangePreset.last7Days,
    DateRangePreset.last30Days,
    DateRangePreset.thisMonth,
    DateRangePreset.lastMonth,
    DateRangePreset.thisYear,
    DateRangePreset.allTime,
  ];

  /// Parses a stored value, falling back to [fallback] for anything this build cannot offer.
  ///
  /// Defaults rather than throws, for the same reason `SafeEnumConverter` does (Law L13): a settings
  /// row is user data, a later version may write a preset this one has never heard of, and that is
  /// not a reason to fail the analytics screen. A stored `custom` or `today` also lands here, which
  /// is why the check is against [presets] and not against `DateRangePreset.values`.
  static DateRangePreset parse(String? stored) {
    for (final preset in presets) {
      if (preset.name == stored) return preset;
    }
    return fallback;
  }

  /// The value written back to `app_settings`.
  static String stored(DateRangePreset preset) => preset.name;
}
