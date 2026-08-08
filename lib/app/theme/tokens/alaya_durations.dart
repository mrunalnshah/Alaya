/// The animation duration scale (ARCH_3 §8).
///
/// Four values, and no widget writes its own. The figures are the ones ARCH_3 §8 specifies, and the
/// reason they are short is that this app is used in twenty-second bursts — logging a purchase at a
/// till. An animation the user waits through is a cost, not polish.
abstract final class AlayaDurations {
  /// 120 ms — a colour change, a check mark, a ripple settling.
  static const Duration fast = Duration(milliseconds: 120);

  /// 220 ms — the default. An expanding card, a chip toggling, a sheet's content settling.
  static const Duration base = Duration(milliseconds: 220);

  /// 380 ms — the expandable FAB unfolding, a large surface reflowing.
  static const Duration slow = Duration(milliseconds: 380);

  /// 90 ms — one leg of the error shake, which is four legs plus a settle.
  static const Duration shakeLeg = Duration(milliseconds: 90);

  /// 2.5 s — how long a snack bar stays.
  static const Duration snack = Duration(milliseconds: 2500);

  /// 300 ms — how long a search field waits after the last keystroke before querying.
  ///
  /// An interaction delay rather than an animation, and it sits here because Law U6 says every
  /// duration in a widget comes from a token — so the token file has to hold every duration a widget
  /// needs. It is deliberately longer than [base]: a debounce tuned to an animation scale fires
  /// mid-word and makes typing feel like it is fighting the field.
  ///
  /// A **network** timeout still does not belong here. That scale is seconds and lives with the
  /// client that owns the call (see `infrastructure_providers.dart`).
  static const Duration debounce = Duration(milliseconds: 300);
}
