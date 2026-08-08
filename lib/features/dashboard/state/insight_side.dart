/// Which face of the dashboard's insight card is showing.
///
/// Stored in `app_settings` through `SettingsRepository.writeValue`, so the choice survives a restart —
/// a switch that resets every launch is a switch the user has to keep re-making.
enum InsightSide {
  /// Bills, services, warranties and batches falling due soon.
  upcoming,

  /// Spending breakdowns. Waiting on Phase 7B's analytics adapter.
  spending;

  /// The `app_settings` key this preference is stored under.
  static const String settingsKey = 'dashboard.insightSide';

  /// Parses a stored value, defaulting to [upcoming] for anything unrecognised.
  ///
  /// Defaults rather than throws: a settings row is user data and a future version may write a value this
  /// one has never heard of, which is not a reason to fail a dashboard.
  static InsightSide parse(String? stored) => switch (stored) {
    'spending' => InsightSide.spending,
    _ => InsightSide.upcoming,
  };

  /// The value written back to `app_settings`.
  String get stored => name;
}
