import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/date_text.dart';

/// The clear-cache action — the whole of `analytics_cache`'s user-facing surface (ARCH_5 §7.1, §7.3).
///
/// **It is here rather than in Settings, and the reason is structural.** ARCH_5 §7.1 assigns the control
/// to Settings, which is a `PlaceholderScreen` until Phase 8A. It could not go in the app bar either:
/// `Routes.insights` is a shell destination, so the bar belongs to `_ShellScaffold` and an action added
/// there would appear on all nine destinations. So it sits last on the screen, quiet, in the manner of
/// archetype E's destructive actions. **Phase 8A's Settings entry must call
/// `analyticsCacheControllerProvider` rather than the service**, or one action gets two write paths
/// (Law U22).
///
/// **No `ConfirmSheet`.** Clearing a cache costs the reader a recomputation and nothing else, and
/// ARCH_5 §5.5 reserves confirmation for consequences — a confirm dialog on a harmless action trains
/// people to tap through the ones that matter.
class CacheRow extends ConsumerWidget {
  /// Creates the row.
  const CacheRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final state = ref.watch(analyticsCacheControllerProvider);
    final clearing = state.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The button is disabled while clearing rather than hidden, so the row does not move under the
        // reader's thumb (ARCH_5 §5.2: an in-place action disables, it does not throw up a barrier).
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: clearing ? null : () => _clear(context, ref),
            icon: const Icon(Icons.refresh, size: AlayaIconSize.md),
            label: Text(
              clearing
                  ? strings.analyticsCacheClearing
                  : strings.analyticsCacheClear,
              style: AlayaTypography.button,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.sm),
          child: Text(
            strings.analyticsCacheExplain,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ),
        // The repository's own message, in place and not only in a snack (Law U9): a snack is a timed
        // surface, and a failure the reader looked away from is a failure they never saw.
        state.when(
          data: (clearedOn) => clearedOn == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(
                    left: AlayaSpacing.sm,
                    top: AlayaSpacing.xxs,
                  ),
                  child: Row(
                    children: [
                      Text(
                        strings.analyticsCacheCleared,
                        style: AlayaTypography.caption.copyWith(
                          color: semantic.success,
                        ),
                      ),
                      const SizedBox(width: AlayaSpacing.xxs),
                      DateText(
                        clearedOn,
                        style: DateTextStyle.medium,
                        muted: true,
                      ),
                    ],
                  ),
                ),
          loading: () => const SizedBox.shrink(),
          error: (error, stack) => Padding(
            padding: const EdgeInsets.only(
              left: AlayaSpacing.sm,
              top: AlayaSpacing.xxs,
            ),
            child: Text(
              error.toString(),
              style: AlayaTypography.caption.copyWith(color: semantic.danger),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final ok = await ref
        .read(analyticsCacheControllerProvider.notifier)
        .clear();
    if (!context.mounted) return;
    // **Every write reports its outcome** (Law U9). No Undo: there is nothing to restore, and the
    // figures are already recomputing.
    if (ok) {
      showResultSnack(context, message: strings.analyticsCacheClearedSnack);
    } else {
      showFailureSnack(context, message: strings.analyticsCacheFailed);
    }
  }
}
