import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Total spend in the window — the one `displayAmount` on this screen (ARCH_5 §3 archetype F).
///
/// **One headline figure, because two headline numbers is no headline number.** Every other figure on
/// the analytics screen is `AmountSize.small` or smaller, exactly as the dashboard's hierarchy works.
///
/// **The comparison is against a window of equal length, not against a calendar month.** "Last 30
/// days" compared with the previous calendar month would be comparing 30 days against 28, 30 or 31,
/// and the resulting percentage would be an artefact of the calendar rather than a fact about
/// spending (`DateRangeService.precedingWindowOf` exists for this).
class AnalyticsHeader extends ConsumerWidget {
  /// Creates the header.
  const AnalyticsHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final async = ref.watch(analyticsHeadlineProvider);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final preset = ref.watch(analyticsRangeProvider);
    final unconverted =
        ref.watch(analyticsUnconvertedProvider).valueOrNull ?? 0;

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.analyticsTotalSpent,
            style: AlayaTypography.label.copyWith(color: semantic.muted),
          ),
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            AnalyticsLabels.range(strings, preset),
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          const SizedBox(height: AlayaSpacing.xs),
          async.when(
            loading: () => Text(
              strings.chartLoading,
              style: AlayaTypography.body.copyWith(color: semantic.muted),
            ),
            error: (error, stack) => ErrorState(
              title: strings.errorTitleGeneric,
              body: error.toString(),
              retryLabel: strings.actionRetry,
              onRetry: () => ref.invalidate(analyticsHeadlineProvider),
            ),
            data: (concentration) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AmountText(
                  concentration.total,
                  size: AmountSize.display,
                  // The card is headed "Spent", so a minus in front of the figure restates the
                  // heading rather than adding to it.
                  showSign: false,
                  decimalDigits: digits,
                ),
                const _Comparison(),
                if (unconverted > 0 ||
                    concentration.quality.unconvertedCount > 0) ...[
                  const SizedBox(height: AlayaSpacing.sm),
                  Wrap(
                    spacing: AlayaSpacing.xs,
                    runSpacing: AlayaSpacing.xxs,
                    children: [
                      if (concentration.quality.unconvertedCount > 0)
                        StatusChip(
                          label: strings.chartUnconverted(
                            concentration.quality.unconvertedCount,
                          ),
                          tone: StatusTone.warning,
                        ),
                      // The app-wide count, distinct from this figure's own exclusions: a
                      // transaction outside the window can still be unconvertible, and Settings is
                      // where a reader fixes that. Said once here rather than on every card.
                      if (unconverted > 0)
                        StatusChip(
                          label: strings.analyticsUnconvertedTotal(unconverted),
                          tone: StatusTone.neutral,
                        ),
                    ],
                  ),
                  const SizedBox(height: AlayaSpacing.xs),
                  Text(
                    strings.fundsWhyExcluded,
                    style: AlayaTypography.caption.copyWith(
                      color: semantic.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How this window compares with the one before it, of the same length.
class _Comparison extends ConsumerWidget {
  const _Comparison();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final now = ref.watch(analyticsHeadlineProvider).valueOrNull;
    final before = ref.watch(analyticsPreviousHeadlineProvider).valueOrNull;

    // Renders nothing until both windows have resolved, and nothing when the earlier one held zero.
    // A percentage against zero is infinite, and "up ∞%" is not a fact about spending.
    if (now == null || before == null || before.total.minor == 0)
      return const SizedBox.shrink();

    final delta = (now.total.minor - before.total.minor) / before.total.minor;
    final formatted = AnalyticsLabels.percent(context, delta.abs());

    // **Colour is not the only signal** (Law U17): the word carries the direction and the hue only
    // reinforces it. Spending more is `warning` rather than `danger` — it is worth noticing, not
    // wrong.
    final rose = delta > 0;
    return Padding(
      padding: const EdgeInsets.only(top: AlayaSpacing.xs),
      child: Text(
        rose
            ? strings.analyticsComparisonUp(formatted)
            : strings.analyticsComparisonDown(formatted),
        style: AlayaTypography.caption.copyWith(
          color: rose ? semantic.warning : semantic.success,
        ),
      ),
    );
  }
}
