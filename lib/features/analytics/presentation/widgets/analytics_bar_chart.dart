import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// One bucket on an [AnalyticsBarChart].
class AnalyticsBucket {
  /// Creates a bucket.
  const AnalyticsBucket({
    required this.bucket,
    required this.value,
    required this.label,
  });

  /// Its position — 1-7 for a weekday, 1-31 for a day of month (ARCH_3 §5.1 query 21).
  final int bucket;

  /// The figure, in **minor units** (Law L1).
  final int value;

  /// The tick label, already localised.
  final String label;
}

/// A bucketed comparison, and the second of the two surfaces `fl_chart` is used for.
///
/// **The same containment as `AnalyticsLineChart`**: unverified package API confined to one file,
/// every colour and gap from Alaya's tokens, no Y-axis numbers (Law U7), touch off (ARCH_5 §6).
///
/// A bar chart rather than a `SliceBarList` because the buckets are a **fixed ordered set** — seven
/// weekdays, thirty-one days — and their order carries the information. Ranking them largest-first
/// would destroy the only thing the reader is looking for, which is the shape of the week.
class AnalyticsBarChart extends StatelessWidget {
  /// Creates a chart of [buckets], in bucket order.
  const AnalyticsBarChart({
    required this.buckets,
    this.labelEvery = 1,
    super.key,
  });

  /// The buckets, ascending. Empty renders nothing — the caller's `ChartCard` owns the empty state.
  final List<AnalyticsBucket> buckets;

  /// Label every nth bucket. Thirty-one day labels do not fit on a phone; seven weekdays do.
  final int labelEvery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    if (buckets.isEmpty) return const SizedBox.shrink();

    var maxValue = 0;
    for (final bucket in buckets) {
      if (bucket.value > maxValue) maxValue = bucket.value;
    }
    // A window where nothing was spent still draws its axis rather than collapsing, so the reader can
    // see that the buckets exist and are all zero.
    final top = maxValue == 0 ? 1.0 : maxValue.toDouble();

    return BarChart(
      BarChartData(
        maxY: top,
        minY: 0,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: const BarTouchData(enabled: false),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: MediaQuery.textScalerOf(
                context,
              ).scale(AlayaSpacing.lg),
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                final match = buckets.where((b) => b.bucket == index);
                if (match.isEmpty) return const SizedBox.shrink();
                if (labelEvery > 1 && index % labelEvery != 0)
                  return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: AlayaSpacing.xxs),
                  child: Text(
                    match.first.label,
                    style: AlayaTypography.overline.copyWith(
                      color: semantic.muted,
                    ),
                    maxLines: 1,
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (final bucket in buckets)
            BarChartGroupData(
              x: bucket.bucket,
              barRods: [
                BarChartRodData(
                  // The same L1 boundary as the line chart: an int figure becomes a double only to
                  // become a coordinate.
                  toY: bucket.value.toDouble(),
                  color: theme.colorScheme.primary,
                  width: AlayaSpacing.sm,
                  borderRadius: AlayaRadii.borderXs,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
