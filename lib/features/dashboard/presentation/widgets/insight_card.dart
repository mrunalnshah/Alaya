import 'package:alaya/core/time/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/dashboard/state/insight_side.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// A switchable card: what is coming up, or where the money went.
///
/// **Each side owns its own loading, empty and error state, inline.** That is the whole reason this is one
/// card with a switch rather than two cards: a failing rate table or an unreachable engine must cost the
/// user this card and nothing else. One failing card never blanks the dashboard (ARCH_5 §3 archetype F).
///
/// **The spending side has no data, and says so rather than pretending.** `AnalyticsService` has no
/// `AnalyticsPort` adapter and `CalendarAggregator` has no `CalendarRepository`, both assigned to Phase 7B
/// and 7A (ARCH_4 §5.1 item 15). Aggregating spending here instead would leave 7B a competing
/// implementation to reconcile, so the side is built, switchable and honest — and 7B supplies data to a
/// card that already exists.
///
/// The choice is stored in `app_settings`, so it survives a restart.
class InsightCard extends ConsumerWidget {
  /// Creates the card.
  const InsightCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final side = ref.watch(insightSideProvider);
    final notifier = ref.read(insightSideProvider.notifier);

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: strings.insightSwitchLabel,
            child: SegmentedButton<InsightSide>(
              segments: [
                ButtonSegment(
                  value: InsightSide.upcoming,
                  label: Text(strings.insightUpcoming),
                ),
                ButtonSegment(
                  value: InsightSide.spending,
                  label: Text(strings.insightSpending),
                ),
              ],
              selected: {side},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => notifier.show(selection.first),
            ),
          ),
          const SizedBox(height: AlayaSpacing.md),
          switch (side) {
            InsightSide.upcoming => const _Upcoming(),
            InsightSide.spending => const _Spending(),
          },
        ],
      ),
    );
  }
}

class _Upcoming extends ConsumerWidget {
  const _Upcoming();

  static IconData _glyph(UpcomingKind kind) => switch (kind) {
    UpcomingKind.bill => Icons.event_repeat,
    UpcomingKind.service => Icons.build_outlined,
    UpcomingKind.warranty => Icons.verified_outlined,
    UpcomingKind.batch => Icons.inventory_2_outlined,
  };

  static String _label(AlayaStrings strings, UpcomingKind kind) =>
      switch (kind) {
        UpcomingKind.bill => strings.insightBillDue,
        UpcomingKind.service => strings.insightServiceDue,
        UpcomingKind.warranty => strings.insightWarrantyEnding,
        UpcomingKind.batch => strings.insightBatchExpiring,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final async = ref.watch(upcomingProvider);
    final today = ref.watch(clockProvider).today();

    return async.when(
      loading: () => Text(
        strings.loadingDashboard,
        style: AlayaTypography.caption.copyWith(color: semantic.muted),
      ),
      error: (error, stack) => Text(
        error.toString(),
        style: AlayaTypography.caption.copyWith(color: semantic.danger),
      ),
      data: (entries) => entries.isEmpty
          ? Text(
              strings.insightNothingUpcoming,
              style: AlayaTypography.body.copyWith(color: semantic.muted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Capped, not scrolled: a card inside a `CustomScrollView` that scrolls on its own is two
                // scroll gestures competing for the same drag. Five is a shortlist; the modules behind it
                // hold the rest.
                for (final entry in entries.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AlayaSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _glyph(entry.kind),
                          size: AlayaIconSize.md,
                          color: entry.isOverdue(today)
                              ? semantic.danger
                              : semantic.muted,
                        ),
                        const SizedBox(width: AlayaSpacing.sm),
                        Expanded(
                          // The title, its sort and its date all grow with text scale, so they wrap
                          // among themselves rather than starving the icon's neighbour (Law U21).
                          child: Wrap(
                            spacing: AlayaSpacing.xs,
                            runSpacing: AlayaSpacing.xxs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                entry.title,
                                style: AlayaTypography.body.copyWith(
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                _label(strings, entry.kind),
                                style: AlayaTypography.caption.copyWith(
                                  color: semantic.muted,
                                ),
                              ),
                              DateText(
                                entry.dueDateKey,
                                style: DateTextStyle.dayMonth,
                                muted: true,
                              ),
                              if (entry.isOverdue(today))
                                StatusChip(
                                  label: strings.recurringOverdue,
                                  tone: StatusTone.danger,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// The spending side, reading the analytics engine Phase 7B wired.
///
/// **This replaced the "waiting on the analytics module" state 6F shipped.** That state was correct
/// while `AnalyticsService` had no adapter; aggregating spending here instead would have left 7B a
/// competing implementation to reconcile (ARCH_4 P7). The row it closed is ARCH_5 §7's, assigned to 7B.
///
/// A shortlist and not a chart: the card is one of four things on a dashboard, and the analytics screen
/// is one tap away for anyone who wants the breakdown.
class _Spending extends ConsumerWidget {
  const _Spending();

  /// How many kinds the card names before it stops. `Concentration.top` is already the top three.
  static const int _maxRows = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final async = ref.watch(spendingInsightProvider);
    final digits = ref.watch(dashboardDigitsProvider).valueOrNull ?? 2;

    return async.when(
      loading: () => Text(
        strings.chartLoading,
        style: AlayaTypography.body.copyWith(color: semantic.muted),
      ),
      // The repository's own message, never a generic body (Law U9).
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: error.toString(),
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(spendingInsightProvider),
      ),
      data: (concentration) {
        if (concentration.top.isEmpty) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.insights_outlined,
                size: AlayaIconSize.md,
                color: semantic.muted,
              ),
              const SizedBox(width: AlayaSpacing.sm),
              Expanded(
                child: Text(
                  strings.analyticsNothingSpent,
                  style: AlayaTypography.body.copyWith(color: semantic.muted),
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // **The window is labelled** (anomaly A33). "Spending" alone does not say over what, and no
            // figure on the card can disambiguate itself.
            Text(
              strings.rangeLast30Days,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            const SizedBox(height: AlayaSpacing.xxs),
            AmountText(
              concentration.total,
              size: AmountSize.medium,
              showSign: false,
              decimalDigits: digits,
            ),
            const SizedBox(height: AlayaSpacing.sm),
            for (final slice in concentration.top.take(_maxRows))
              KeyValueRow(
                // `slice.key` through the ARB, never `slice.label`: the adapter grouped by the enum
                // name, so the label is `grocery` (Law U5).
                label: AnalyticsLabels.subtype(strings, slice.key),
                valueWidget: AmountText(
                  slice.amount,
                  size: AmountSize.small,
                  showSign: false,
                  decimalDigits: digits,
                ),
              ),
          ],
        );
      },
    );
  }
}
