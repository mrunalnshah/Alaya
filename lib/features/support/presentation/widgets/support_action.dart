import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/features/support/providers/support_availability_provider.dart';
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
/// ## Two changes, and one of them was nearly a mistake
///
/// **It carries a label now.** An unlabelled hands icon beside a title is a guess: it could be sharing, a
/// partnership, a handshake gesture. "Support Us" says what a tap does, and a button in an app bar that nobody
/// can identify is a button nobody presses.
///
/// **It hides itself when the last attempt found no advert.** The obvious implementation — ask the SDK on
/// launch whether one is available — is the one thing this widget's own doc forbids: `google_mobile_ads` cannot
/// answer that without loading, and loading collects an identifier from everyone who never asked. So the answer
/// comes from what happened last time somebody tapped, which costs the SDK nothing.
///
/// **Settings › Support Us stays visible unconditionally**, and that is the safety net rather than an
/// oversight. This widget's answer is a guess from stale evidence; a wrong guess must never be the only answer.
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

    // **Absent, not disabled, when there is nothing to show.** A greyed-out button in an app bar is a
    // permanent question — "why can't I press that?" — with no answer available on the screen it sits on.
    //
    // `valueOrNull ?? true` so the action is present while the settings row is being read. Hiding during the
    // first frames and appearing a moment later would make the app bar jump on every launch, and the common
    // answer is "show it" anyway.
    final visible = ref.watch(supportActionVisibleProvider).valueOrNull ?? true;
    if (!visible) return const SizedBox.shrink();

    return TextButton.icon(
      onPressed: () => _watch(context, ref, strings),
      icon: Icon(
        // Joined hands. Not a padlock-style overload: it reads as "together" rather than as an advert, which is
        // honest — the action is supporting the app, and the advert is the mechanism.
        Icons.handshake_outlined,
        size: AlayaIconSize.md,
      ),
      label: Text(strings.supportActionLabel),
      style: TextButton.styleFrom(
        foregroundColor: theme.colorScheme.secondary,
        // An app bar does not wrap its actions, so a long label at a doubled text scale eats the title rather
        // than reflowing. Tightening the padding buys back most of what the label costs; if it still crowds at
        // 320dp, the label is the thing to shorten, not the icon to drop.
        padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.sm),
        visualDensity: VisualDensity.compact,
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

    // **Recorded before the message.** This is the only moment the app learns anything about availability, and
    // an early `return` in the switch below would skip it — `dismissed` says nothing to the user and would have
    // been exactly the case that fell through.
    await ref.read(supportOutcomeRecorderProvider.notifier).record(outcome);
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
