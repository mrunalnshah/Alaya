/// A named reporting window the user can pick, resolved to concrete dates by `DateRangeService`.
///
/// Lives in `core/` rather than beside the service because both `domain/` (the service, analytics)
/// and `features/` (the picker widget) name it, and Law L12 forbids `domain/` importing from
/// anywhere above it. Same reasoning as `TagScope`.
///
/// **Not stored anywhere.** Law L13's "renaming an enum value is a breaking migration" does not
/// apply — the resolved `DateKey` pair is what reaches the database, never the preset itself. The
/// selected preset is persisted only as an `app_settings` string, which the repository maps by
/// name and falls back to [thisMonth] on an unknown value.
enum DateRangePreset {
  /// Today only, from midnight to midnight.
  today,

  /// The seven days ending today, today included.
  last7Days,

  /// The thirty days ending today, today included.
  last30Days,

  /// The first of this month through today.
  thisMonth,

  /// The whole of the previous calendar month.
  lastMonth,

  /// The first of this calendar year through today.
  thisYear,

  /// Every date the user could have recorded anything on.
  allTime,

  /// A window the user picked by hand; `DateRangeService` cannot resolve this one alone.
  custom,
}