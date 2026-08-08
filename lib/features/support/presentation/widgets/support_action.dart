import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/features/support/providers/support_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';

/// The app bar's support action — one tap, one advert, nothing before the tap.
///
/// **This is an amendment to ARCH_4 §5.1, which said rewarded ads live "only in Support Us".** The entry point
/// moves to the dashboard; the constraint that matters does not.
///
/// **Nothing is loaded until the button is pressed.** The obvious way to make an app bar button feel instant is
/// to have an advert waiting — which means `MobileAds.initialize()` and `RewardedAd.load()` on every dashboard
/// build, and an advertising identifier collected from every user who never taps it. That is what 8B's "the rest
/// of the app makes zero ad calls" forbids, and the privacy cost is real rather than notional.
///
/// So the sequence runs *on* the tap: initialise → settle consent → load → show. It costs a second or two, which
/// is why the button shows a spinner rather than pretending to be immediate. **The user chooses when an advert
/// plays, and also when one is fetched** — the second half is the part a pre-loaded button would give away.
///
/// Tinted `colorScheme.secondary`, which is the palette's own accent (ARCH_3 §8) rather than a raw colour, so it
/// reads as distinct from the app bar's other actions under every preset and in both brightnesses.
class SupportAction extends ConsumerWidget {
  /// Creates the action.
  const SupportAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(supportProvider);
    final theme = Theme.of(context);

    if (state.isWorking) {
      // A spinner in the button's own footprint, so the app bar does not reflow while an advert is fetched.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.md),
        child: Center(
          child: SizedBox(
            width: AlayaIconSize.md,
            height: AlayaIconSize.md,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.secondary,
            ),
          ),
        ),
      );
    }

    return IconButton(
      onPressed: () => _watch(context, ref, strings),
      tooltip: strings.supportWatchTooltip,
      icon: Icon(
        // Joined hands. Not a padlock-style overload: it reads as "together" rather than as an advert, which is
        // honest — the action is supporting the app, and the advert is the mechanism.
        Icons.handshake_outlined,
        size: AlayaIconSize.md,
        color: theme.colorScheme.secondary,
      ),
    );
  }

  Future<void> _watch(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    final controller = ref.read(supportProvider.notifier);
    final outcome = await controller.watchNow();
    if (!context.mounted) return;
    switch (outcome) {
      case SupportWatchOutcome.rewarded:
        showResultSnack(context, message: strings.supportThanks);
      case SupportWatchOutcome.dismissed:
        // Silent. Somebody who changes their mind half way through an advert has done nothing wrong, and a
        // message either way would be the app commenting on it.
        break;
      case SupportWatchOutcome.unavailable:
        showFailureSnack(context, message: strings.supportNoAd);
      case SupportWatchOutcome.blocked:
        showFailureSnack(context, message: strings.supportConsentUnavailable);
    }
  }
}
