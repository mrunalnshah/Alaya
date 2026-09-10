/// Whether the support action is worth showing (ARCH_5 U19).
library;

import 'package:alaya/core/time/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/features/support/providers/support_providers.dart';

/// The `app_settings` key holding when an advert was last unavailable.
///
/// Epoch millis, or absent. **Absent means "show it"** — including on a fresh install, which is the whole
/// reason this stores a *failure* rather than a success.
const String adUnavailableSinceKey = 'support.adUnavailableSince';

/// How long a failure suppresses the action.
///
/// **Three days, not one and not forever.** A fill failure is usually transient — no inventory in the region
/// for a few hours, a network blip — so hiding permanently would remove the feature over a temporary
/// condition. Retrying daily is the other extreme: the button would appear each morning, vanish on the first
/// tap, and read as broken. Three days is long enough that nobody notices the retry and short enough that a
/// genuine recovery is picked up within the week.
const Duration adRetryAfter = Duration(days: 3);

/// Whether the app-bar support action should be shown at all.
///
/// ## Why this cannot ask the SDK
///
/// `google_mobile_ads` has **no way to report availability without loading an advert**, and loading requires
/// `MobileAds.initialize()` plus a settled consent flow — which collects an advertising identifier. ARCH_4's
/// Support Us row is explicit that nothing may run before the tap:
///
/// > *nothing loads until the button is tapped … a user who never taps it never has an advertising
/// > identifier collected.*
///
/// Checking availability on launch would break that for every user in the app, to decide whether to draw one
/// icon. So the question is answered from **what happened last time somebody asked**, which costs the SDK
/// nothing and is right far more often than not: an account with no fill yesterday usually has no fill today.
///
/// **Optimistic when it knows nothing.** A first launch shows the action, because the alternative is a
/// feature that never appears until it has been used, which it cannot be.
///
/// **Settings › Support Us is unaffected and always visible.** That is deliberate: this provider can be wrong,
/// and a wrong answer must never be the only answer. There is always a way in.
final supportActionVisibleProvider = FutureProvider<bool>((ref) async {
  final stored = await ref
      .watch(settingsRepositoryProvider)
      .readValue(adUnavailableSinceKey);
  if (stored == null) return true;

  final since = int.tryParse(stored);
  // Unparseable is treated as absent rather than as a failure. A malformed row should not hide a feature, and
  // the next outcome overwrites it.
  if (since == null) return true;

  final elapsed = ref.watch(clockProvider).nowUtcMillis() - since;
  return elapsed >= adRetryAfter.inMilliseconds;
});

/// Records what happened, so the next launch can decide.
final supportOutcomeRecorderProvider =
    NotifierProvider<SupportOutcomeRecorder, void>(
      SupportOutcomeRecorder.new,
    );

/// Writes the outcome of a support attempt.
class SupportOutcomeRecorder extends Notifier<void> {
  @override
  void build() {}

  /// Records [outcome] and refreshes the visibility answer.
  ///
  /// **An advert that played and one the user dismissed both count as available**, and the distinction matters:
  /// dismissing is a decision about *this* advert, not evidence that adverts cannot be fetched. Treating it as
  /// unavailability would hide the button for three days because somebody changed their mind after four
  /// seconds.
  ///
  /// **`unavailable` and `blocked` are recorded together, though they are not the same thing.** No fill is
  /// transient; a consent flow that cannot complete is usually not. They are merged because the *action* is
  /// identical either way — there is no advert to show now — and because a consent problem that resolves
  /// itself deserves the same three-day retry as anything else. If they ever need different handling, the
  /// place to split them is here, not at the call site.
  Future<void> record(SupportWatchOutcome outcome) async {
    final settings = ref.read(settingsRepositoryProvider);
    switch (outcome) {
      case SupportWatchOutcome.rewarded:
      case SupportWatchOutcome.dismissed:
        // Clearing rather than writing a success marker: absence already means "show it", so a second
        // representation of the same state would be one more thing to keep in step.
        await settings.writeValue(
          key: adUnavailableSinceKey,
          value: '',
          valueType: 'string',
        );
      case SupportWatchOutcome.unavailable:
      case SupportWatchOutcome.blocked:
        await settings.writeValue(
          key: adUnavailableSinceKey,
          value: '${ref.read(clockProvider).nowUtcMillis()}',
          valueType: 'string',
        );
    }
    ref.invalidate(supportActionVisibleProvider);
  }
}
