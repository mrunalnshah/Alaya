import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_line_chart.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';
import 'package:alaya/shared/widgets/date_text.dart';

/// The personal-inflation card — queries 12 and 24.
///
/// **This is the differentiating surface** (ARCH_3 §5.1: *"your potatoes cost 34% more than in
/// January"*). It is the one figure on this screen that no mainstream expense app can produce, and it
/// falls out of `transaction_lines` for free: a line records what was bought, how much of it, and for
/// how much, so price per base unit is a division rather than a feature.
///
/// **Comparable across purchases because it is per *base* unit.** 2 kg and 500 g are the same
/// measurement once both are per gram, which is why the trend can put a sack and a handful on one
/// line.
///
/// The item is chosen rather than asked for: `personalInflationProvider` takes the largest absolute
/// change among the items the reader actually spends on.
class InflationCard extends ConsumerWidget {
  /// Creates the card.
  const InflationCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(personalInflationProvider);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;

    return ChartCard<UnitPriceTrend?>(
      title: strings.analyticsInflationTitle,
      subtitle: strings.analyticsInflationSubtitle,
      value: async,
      // Null *and* a trend with fewer than two points both read as empty: one observation is a price,
      // not a trend, and drawing a single dot and calling it inflation would be a claim the data does
      // not support.
      isEmpty: (trend) => trend == null || trend.points.length < 2,
      emptyMessage: strings.analyticsInflationEmpty,
      onRetry: () => ref.invalidate(personalInflationProvider),
      builder: (context, trend) => _Trend(trend: trend!, decimalDigits: digits),
    );
  }
}

class _Trend extends StatelessWidget {
  const _Trend({required this.trend, required this.decimalDigits});

  final UnitPriceTrend trend;
  final int decimalDigits;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final theme = Theme.of(context);
    final change = trend.percentChange;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          trend.itemName,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        if (change != null) ...[
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            _sentence(context, strings, change),
            style: AlayaTypography.bodyEmphasis.copyWith(
              // Paying more for the same thing is `warning`: worth noticing, not wrong. Colour is
              // never the only signal — the sentence says "more" or "less" (Law U17).
              color: change > 0 ? semantic.warning : semantic.success,
            ),
          ),
        ],
        const SizedBox(height: AlayaSpacing.xxs),
        // **The date goes through `DateText`, so the sentence above cannot contain it** (Law U7).
        // Interpolating a formatted date into an ARB string would bypass the one path from a `DateKey`
        // to pixels, and a `Wrap` lets the label and the date reflow rather than starving each other
        // at a raised text scale (Law U21).
        Wrap(
          spacing: AlayaSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              strings.analyticsInflationSince,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            DateText(
              trend.points.first.on,
              style: DateTextStyle.medium,
              muted: true,
            ),
            AmountText(
              trend.points.last.lineAmount,
              size: AmountSize.small,
              showSign: false,
              decimalDigits: decimalDigits,
            ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.sm),
        AnalyticsPlotBox(
          child: AnalyticsLineChart(
            series: [
              AnalyticsSeries(
                tone: AnalyticsSeriesTone.neutral,
                filled: true,
                points: _points(context, trend),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The observations, oldest first, as plot points.
  ///
  /// `x` is the purchase *ordinal* rather than the date, deliberately. Spacing the points by date
  /// would compress a cluster of weekly shops into an unreadable smear and stretch a six-month gap
  /// across the card; the question is "how has the price moved across my purchases", and each
  /// purchase is one step.
  ///
  /// `pricePerBaseUnit` is a `double` of minor units — a derived ratio, which is why
  /// `analytics_types.dart` refuses to make it a `Money`. It is rounded to whole minor units here
  /// because a pixel cannot express a fraction of a paisa, and only the first and last ticks are
  /// labelled so the axis stays legible at any purchase count.
  List<AnalyticsPoint> _points(BuildContext context, UnitPriceTrend trend) {
    final last = trend.points.length - 1;
    return [
      for (var i = 0; i <= last; i++)
        AnalyticsPoint(
          x: i.toDouble(),
          value: trend.points[i].pricePerBaseUnit.round(),
          axisLabel: i == 0 || i == last
              ? DateFormat.MMMd(
                  Localizations.localeOf(context).toLanguageTag(),
                ).format(trend.points[i].on.toUtcMidnight())
              : null,
        ),
    ];
  }

  String _sentence(BuildContext context, AlayaStrings strings, double change) {
    final formatted = AnalyticsLabels.percent(context, change.abs());
    return change > 0
        ? strings.analyticsInflationUp(formatted)
        : strings.analyticsInflationDown(formatted);
  }
}
