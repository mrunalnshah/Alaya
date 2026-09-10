import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_amount.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_donut_chart.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/presentation/widgets/slice_bar_list.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Query 17 — what is owed every month before anything discretionary happens.
///
/// Every interval is normalised to a month so a weekly bill and an annual one are comparable, and the
/// integer division truncates — so the figure is slightly conservative rather than optimistic, which is
/// the right direction for a number somebody budgets against.
class MonthlyCommitmentCard extends ConsumerWidget {
  /// Creates the card.
  const MonthlyCommitmentCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final async = ref.watch(monthlyCommitmentProvider);

    return ChartCard<MonthlyCommitment>(
      title: strings.analyticsCommitment,
      // Outflow only. Netting salary against rent would report a household with a surplus as having no
      // fixed costs at all, which is the opposite of what the figure is for.
      subtitle: strings.analyticsCommitmentNote,
      value: async,
      isEmpty: (data) => data.templateCount == 0,
      emptyMessage: strings.analyticsNoCommitments,
      onRetry: () => ref.invalidate(monthlyCommitmentProvider),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AmountText(
            data.total,
            size: AmountSize.large,
            showSign: false,
            decimalDigits: digits,
          ),
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            strings.analyticsCommitmentCount(data.templateCount),
            style: AlayaTypography.caption.copyWith(
              color: context.semantic.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Query 18 — the recurring against discretionary split.
///
/// Both sides tap through to the ledger, because "where did the discretionary half go" is the obvious
/// next question and the answer is a filtered list rather than another chart.
class RecurringSplitCard extends ConsumerWidget {
  /// Creates the card.
  const RecurringSplitCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final async = ref.watch(recurringSplitProvider);

    return ChartCard<RecurringSplit>(
      title: strings.analyticsRecurringSplit,
      value: async,
      isEmpty: (split) => split.recurring.isZero && split.discretionary.isZero,
      emptyMessage: strings.analyticsNothingSpent,
      onRetry: () => ref.invalidate(recurringSplitProvider),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, split) {
        // **Two wedges of one whole — the shape a ring is actually for.** Every withdrawal is on exactly
        // one side of this split, so the circle is the figure: how much of the month was decided before
        // it started.
        final slices = analyticsSlices(
          context,
          [
            (
              label: strings.analyticsRecurring,
              value: split.recurring.minor,
              key: 'recurring',
            ),
            (
              label: strings.analyticsDiscretionary,
              value: split.discretionary.minor,
              key: 'discretionary',
            ),
          ],
          otherLabel: strings.analyticsOtherSlices,
        );
        final amounts = {
          'recurring': split.recurring,
          'discretionary': split.discretionary,
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnalyticsDonutChart(
              slices: slices,
              centreTop: AnalyticsLabels.percent(context, split.recurringShare),
              centreBottom: strings.analyticsRecurring,
            ),
            const SizedBox(height: AlayaSpacing.sm),
            Text(
              strings.analyticsRecurringShare(
                AnalyticsLabels.percent(context, split.recurringShare),
              ),
              style: AlayaTypography.bodyEmphasis,
            ),
            const SizedBox(height: AlayaSpacing.sm),
            SliceBarList(
              showBars: false,
              slices: [
                for (final slice in slices)
                  SliceBar(
                    label: slice.label,
                    value: analyticsAmount(
                      amounts[slice.key] ?? split.recurring,
                      digits,
                    ),
                    // The real share, not a placeholder: the rows drop their bars while a ring is above
                    // them, but a `share` of zero would draw an empty bar the moment anyone turned them
                    // back on.
                    share: slice.key == 'recurring'
                        ? split.recurringShare
                        : 1 - split.recurringShare,
                    detail: AnalyticsLabels.percent(
                      context,
                      slice.key == 'recurring'
                          ? split.recurringShare
                          : 1 - split.recurringShare,
                    ),
                    swatch: slice.color,
                    onTap: slice.key == null
                        ? null
                        // The literals the adapter's SQL emits for the two sides, reached through the
                        // same constants the predicate compares against.
                        : () => context.push(
                            Routes.insightsDrillDown(
                              DrillDownKind.recurring.name,
                              slice.key!,
                            ),
                          ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Query 19 — what each asset has cost to keep, per currency.
///
/// **Disposed assets are included**, which is the point of `status = disposed` rather than a delete: the
/// ₹45,000 of servicing you put into a TV stays here after you sell it, and "lifetime" would be a
/// strange word for a figure that vanished on disposal.
class ServiceCostCard extends ConsumerWidget {
  /// Creates the card.
  const ServiceCostCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(serviceCostByAssetProvider);

    return ChartCard<List<AssetServiceCost>>(
      title: strings.analyticsServiceCost,
      value: async,
      isEmpty: (costs) => costs.isEmpty,
      emptyMessage: strings.analyticsNoServiceCost,
      onRetry: () => ref.invalidate(serviceCostByAssetProvider),
      builder: (context, costs) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final cost in costs.take(_maxRows))
            Padding(
              padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
              child: Wrap(
                spacing: AlayaSpacing.xs,
                runSpacing: AlayaSpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(cost.assetName, style: AlayaTypography.body),
                  Text(
                    strings.analyticsServiceCount(cost.serviceCount),
                    style: AlayaTypography.caption.copyWith(
                      color: context.semantic.muted,
                    ),
                  ),
                  // Per currency, unconverted: a service history spanning a move abroad holds two
                  // currencies and summing them would be wrong (anomaly A34).
                  for (final amount in cost.byCurrency.values)
                    AnalyticsCurrencyAmount(amount),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static const int _maxRows = 6;
}

/// Query 20 — the warranty coverage timeline.
class WarrantyCard extends ConsumerWidget {
  /// Creates the card.
  const WarrantyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(warrantyCoverageProvider);

    return ChartCard<List<WarrantyCoverage>>(
      title: strings.analyticsWarranty,
      value: async,
      isEmpty: (rows) => rows.isEmpty,
      emptyMessage: strings.analyticsNoWarranties,
      onRetry: () => ref.invalidate(warrantyCoverageProvider),
      builder: (context, rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows.take(_maxRows))
            KeyValueRow(
              label: row.assetName,
              // `KeyValueRow` renders nothing when the value is null, which is why the end date is
              // handed over as a widget rather than a formatted string: an asset with a start and no
              // end has no coverage window to state, and the row disappears rather than showing a dash.
              valueWidget: row.end == null
                  ? null
                  : Wrap(
                      spacing: AlayaSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DateText(
                          row.end!,
                          style: DateTextStyle.medium,
                          muted: true,
                        ),
                        StatusChip(
                          label: row.isCovered
                              ? strings.analyticsCovered
                              : strings.analyticsCoverageEnded,
                          // `warning` for a coverage window inside 30 days, matching ARCH_3 §6's own
                          // `warrantyEnd` threshold so this card and the calendar agree.
                          tone: !row.isCovered
                              ? StatusTone.neutral
                              : (row.daysLeft ?? _warrantyWarningDays + 1) <=
                                    _warrantyWarningDays
                              ? StatusTone.warning
                              : StatusTone.success,
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }

  static const int _maxRows = 6;

  /// ARCH_3 §6's `warrantyEnd` threshold: 30 days, where expiry and service warn at 7.
  static const int _warrantyWarningDays = 30;
}
