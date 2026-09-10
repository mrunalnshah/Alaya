import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// A chart sized to the standard plot height, scaled from the text scaler.
///
/// **This replaced `ChartCard.chartHeight`, which was wrong in a way worth recording.** That parameter
/// wrapped the *whole* builder output in a fixed box, so a card whose builder returned chrome above its
/// chart — a title, a legend, a segmented control — had that chrome squeezed into the height meant for
/// the plot, and `Expanded` was then mandatory because only a bounded box makes it legal. Four of the
/// six chart cards were built that way and `InflationCard` overflowed by 44px at scale 1.
///
/// Sizing only the plot is the fix: the surrounding `Column` grows naturally inside the screen's
/// `SliverList`, and the card can be as tall as its own text needs.
///
/// **Measured from the text scaler and clamped** (Law U26). A plot is a graphic and does not grow with
/// type, but its axis labels do, so the box has to give them room; unclamped, a tripled scale produces a
/// card nobody can scroll past.
class AnalyticsPlotBox extends StatelessWidget {
  /// Sizes [child] to the scaled plot height.
  const AnalyticsPlotBox({
    required this.child,
    this.height = defaultHeight,
    super.key,
  });

  /// The plot.
  final Widget child;

  /// The unscaled height.
  final double height;

  /// One height for every chart on the screen, so eight cards cannot each pick their own and leave the
  /// scroll rhythm uneven.
  static const double defaultHeight = AlayaSpacing.xxxl * 2;

  /// The most a plot grows by under text scale.
  static const double maxScale = 2;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, maxScale);
    return SizedBox(height: height * scale, child: child);
  }
}

/// Which semantic role a series carries.
enum AnalyticsSeriesTone {
  /// Money arriving.
  income,

  /// Money leaving.
  expense,

  /// Neither — a balance, a unit price, a count.
  neutral,
}

/// One plotted observation.
class AnalyticsPoint {
  /// Creates a point at [x] worth [value] minor units.
  const AnalyticsPoint({required this.x, required this.value, this.axisLabel});

  /// The horizontal position — a month index, a day offset, a purchase ordinal.
  final double x;

  /// The figure, in **minor units** (Law L1). Never a decimal.
  final int value;

  /// The tick label at [x], already localised. Null on ticks that should stay unlabelled.
  final String? axisLabel;
}

/// One line on the chart.
class AnalyticsSeries {
  /// Creates a series.
  const AnalyticsSeries({
    required this.points,
    required this.tone,
    this.filled = false,
  });

  /// Its observations, ascending by [AnalyticsPoint.x].
  final List<AnalyticsPoint> points;

  /// Which semantic colour it takes.
  final AnalyticsSeriesTone tone;

  /// Whether to shade the area beneath it. One series may; two would obscure each other.
  final bool filled;
}

/// A trend over time, and one of the two surfaces `fl_chart` is used for.
///
/// **`fl_chart` is confined to this file and `analytics_bar_chart.dart`.** Its API could not be
/// verified against the installed package in the session that wrote this — the same position 7A was
/// in with `table_calendar` — so ARCH_4 R22 says to contain it rather than trust a changelog. Every
/// colour, gap and text style comes from Alaya's own tokens through the parameters below; the package
/// supplies path geometry and nothing a token would otherwise own. If its API differs, two files
/// change rather than the phase.
///
/// **There are no Y-axis number labels, and that is Law U7 rather than a style choice.** An axis is
/// exactly where a `Money` gets clipped, `AmountText` clips rather than ellipsises, and a clipped
/// figure is a wrong figure. The grid lines carry the shape; the card's headline carries the number;
/// the drill-down carries the rest.
///
/// **Touch is off.** A tooltip is a timed surface, and ARCH_5 §6 requires that nothing be available
/// *only* there.
class AnalyticsLineChart extends StatelessWidget {
  /// Creates a chart of [series].
  const AnalyticsLineChart({
    required this.series,
    this.gridLineCount = 4,
    super.key,
  });

  /// The lines to draw. Empty renders nothing — the caller's `ChartCard` owns the empty state.
  final List<AnalyticsSeries> series;

  /// How many horizontal grid lines to draw behind the lines.
  final int gridLineCount;

  /// The plotted line's thickness.
  static const double _barWidth = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    if (series.isEmpty) return const SizedBox.shrink();

    final all = [for (final s in series) ...s.points];
    if (all.isEmpty) return const SizedBox.shrink();

    var minValue = all.first.value;
    var maxValue = all.first.value;
    for (final point in all) {
      if (point.value < minValue) minValue = point.value;
      if (point.value > maxValue) maxValue = point.value;
    }
    // A flat line needs a band or the plot collapses to zero height and fl_chart divides by it.
    if (minValue == maxValue) {
      maxValue += 1;
      minValue -= 1;
    }
    // Zero is included whenever the data straddles or approaches it, so a bar of spending is not
    // drawn from an arbitrary floor that exaggerates every difference.
    if (minValue > 0) minValue = 0;

    final labels = <double, String>{
      for (final point in all)
        if (point.axisLabel != null) point.x: point.axisLabel!,
    };

    return LineChart(
      LineChartData(
        minY: minValue.toDouble(),
        maxY: maxValue.toDouble(),
        // Touch disabled: see the class doc. A tooltip would be the only place a figure lived.
        lineTouchData: const LineTouchData(enabled: false),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxValue - minValue) / gridLineCount,
          getDrawingHorizontalLine: (value) => FlLine(
            color: theme.colorScheme.outlineVariant,
            // A literal `1`, and the one dimension in this phase that has no token. ARCH_5 §2.2
            // defines a dividing line as 1px at divider weight and `AlayaSpacing` starts at 4, so
            // there is nothing to reach for — 6F's `range_row.dart` sets the same literal for its
            // rule. `outlineVariant` is Material 3's divider role, which keeps the weight consistent
            // across every palette preset.
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          // No numbers on the left, per Law U7 — see the class doc.
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              // Measured from the text scaler rather than fixed, so a doubled scale gets the room it
              // needs instead of clipping the tick (Law U26).
              reservedSize: MediaQuery.textScalerOf(
                context,
              ).scale(AlayaSpacing.lg),
              getTitlesWidget: (value, meta) {
                final label = labels[value];
                if (label == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: AlayaSpacing.xxs),
                  child: Text(
                    label,
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
        lineBarsData: [
          for (final s in series)
            LineChartBarData(
              // **`toDouble()` here is the one legitimate place a money figure becomes a double.**
              // Law L1 forbids a `double` storing money or crossing a repository boundary; a plot
              // coordinate is neither. The int is what was read, summed and cached.
              spots: [
                for (final p in s.points) FlSpot(p.x, p.value.toDouble()),
              ],
              isCurved: false,
              barWidth: _barWidth,
              color: _colorFor(s.tone, semantic),
              dotData: FlDotData(show: s.points.length <= _dotThreshold),
              belowBarData: BarAreaData(
                show: s.filled,
                color: _colorFor(s.tone, semantic).withValues(alpha: 0.12),
              ),
            ),
        ],
      ),
    );
  }

  /// Above this many points the dots merge into the line and are dropped.
  static const int _dotThreshold = 14;

  Color _colorFor(AnalyticsSeriesTone tone, AlayaSemanticColors semantic) =>
      switch (tone) {
        AnalyticsSeriesTone.income => semantic.income,
        AnalyticsSeriesTone.expense => semantic.expense,
        AnalyticsSeriesTone.neutral => semantic.transfer,
      };
}
