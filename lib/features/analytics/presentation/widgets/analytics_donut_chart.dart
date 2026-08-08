import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_line_chart.dart';

/// One wedge of an [AnalyticsDonutChart], and one row of the list beneath it.
///
/// **The same object feeds the ring and the rows**, which is the point: build them from two sources and
/// they drift, so the fifth-largest wedge ends up a different colour from the fifth row.
class AnalyticsSlice {
  /// Creates a slice.
  const AnalyticsSlice({
    required this.label,
    required this.value,
    required this.color,
    this.key,
  });

  /// What it is, already localised.
  final String label;

  /// Its magnitude — minor units or base-milli. Only the ratio between slices is used.
  final int value;

  /// Its colour in both the ring and the row's swatch.
  final Color color;

  /// The drill-down key, or null for a slice that is not a filterable axis.
  final String? key;
}

/// The palette a donut's wedges take, largest first.
///
/// **A single-hue ramp, not a set of categorical colours.** Alaya's palette is data — five presets the
/// user chooses between (ARCH_5 §2.1) — so a hand-picked categorical set would clash under at least one
/// of them, and `warning`/`danger`/`success` are reserved for state and never for emphasis (§2.4).
/// Stepping the alpha on `primary` cannot clash with anything, and it reads in the right order: the
/// biggest share is the darkest.
///
/// Identity comes from the row beneath, whose swatch is this same colour. The ring carries proportion
/// only, which is the one thing a list genuinely cannot show.
List<Color> analyticsSliceColors(BuildContext context, int count) {
  final base = Theme.of(context).colorScheme.primary;
  const steps = [1.0, 0.78, 0.60, 0.45, 0.33, 0.24, 0.17];
  return [
    for (var i = 0; i < count; i++)
      base.withValues(alpha: steps[i < steps.length ? i : steps.length - 1]),
  ];
}

/// Builds the slices for a donut and its list, grouping the tail into one remainder wedge.
///
/// **Grouped because a ring of twelve slivers is not readable.** Past six wedges the arcs are thinner
/// than the gaps between them and the ordering stops being legible, so the tail becomes one wedge that
/// says what it is. [remainder] lets a caller supply a known total — the concentration card knows what
/// the top three leave behind — instead of it being derived from the slices given.
///
/// Zero and negative magnitudes are dropped: `PieChart` divides by the total and a zero wedge draws a
/// seam with no area, which reads as a rendering fault rather than as nothing.
List<AnalyticsSlice> analyticsSlices(
  BuildContext context,
  List<({String label, int value, String? key})> input, {
  required String otherLabel,
  int maxSlices = 6,
  int remainder = 0,
}) {
  final positive = [
    for (final row in input)
      if (row.value > 0) row,
  ];
  final head = positive.take(maxSlices).toList();
  final tail =
      positive.skip(maxSlices).fold<int>(0, (sum, row) => sum + row.value) +
      remainder;
  final colors = analyticsSliceColors(
    context,
    head.length + (tail > 0 ? 1 : 0),
  );

  return [
    for (var i = 0; i < head.length; i++)
      AnalyticsSlice(
        label: head[i].label,
        value: head[i].value,
        color: colors[i],
        key: head[i].key,
      ),
    // No key: "everything else" is not an axis anything can be filtered by, so the row it produces is
    // deliberately not tappable (ARCH_5 §10's objection to a control that looks live and is not).
    if (tail > 0)
      AnalyticsSlice(
        label: otherLabel,
        value: tail,
        color: colors[head.length],
      ),
  ];
}

/// A ring showing how a total divides, with a figure in the middle.
///
/// **Used only where the data is a genuine partition of one whole.** Spend by kind, the fixed-against-
/// chosen split and the concentration of spending all are. Tags are not — one purchase can carry two, so
/// the slices sum past the total and a ring would assert a whole that does not exist. Ranked lists
/// (payees, items) are not either: the top ten is not everything. Those stay as bars.
///
/// **The ring never carries a number.** Wedge titles are off: a `Money` in a 40dp arc is the clipping U7
/// forbids, and a percentage there duplicates what the rows already say. Touch is off for the same reason
/// as the other charts — a tooltip is a timed surface, and ARCH_5 §6 requires nothing live only there.
///
/// **Excluded from semantics.** The list beneath is the accessible rendering of the same slices, so
/// describing both makes a screen reader read the card twice.
class AnalyticsDonutChart extends StatelessWidget {
  /// Creates a ring of [slices].
  const AnalyticsDonutChart({
    required this.slices,
    this.centreTop,
    this.centreBottom,
    super.key,
  });

  /// The wedges, largest first, from [analyticsSlices].
  final List<AnalyticsSlice> slices;

  /// The emphasised line in the hole — usually a percentage.
  final String? centreTop;

  /// The quiet line under it — usually what that percentage is of.
  final String? centreBottom;

  /// The unscaled height of the ring's box, and so its diameter on any phone narrower than this.
  ///
  /// **Four times the spacing scale's largest step, where the line and bar charts use two.** They are
  /// wide and shallow by nature — a trend reads left to right — so `AnalyticsPlotBox.defaultHeight`
  /// suits them. A ring is square: its diameter is the box's *shorter* side, so at 96 the height was
  /// capping a circle whose width had 256 to spare on the narrowest supported phone, and it drew at
  /// barely more than a third of the room available. At 192 the width becomes the binding constraint
  /// instead, which is the right way round — the ring can never be wider than its card.
  static const double plotHeight = AlayaSpacing.xxxl * 4;

  /// How much of the box the hole takes. Two fifths leaves an arc thick enough to compare by eye — 58
  /// logical pixels at [plotHeight] — and a hole wide enough for a percentage at a doubled text scale.
  static const double _holeFraction = 0.4;

  /// The gap between wedges, on the spacing scale (Law U6).
  static const double _gap = AlayaSpacing.xxs / 2;

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) return const SizedBox.shrink();
    final semantic = context.semantic;

    return ExcludeSemantics(
      child: AnalyticsPlotBox(
        height: plotHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Sized from the box's own shorter side rather than from a constant, so the ring stays a
            // ring at any text scale: `AnalyticsPlotBox` grows the height and a fixed radius would
            // then be an ellipse cropped by the width.
            final extent = constraints.biggest.shortestSide;
            final hole = extent * _holeFraction / 2;
            final ring = extent / 2 - hole;

            return Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: _gap,
                    centerSpaceRadius: hole,
                    // From the top, clockwise: the largest wedge starts where a reader looks first.
                    startDegreeOffset: -90,
                    // Not `const`: `PieTouchData` has no const constructor, unlike `LineTouchData` and
                    // `BarTouchData`. Three sibling APIs, two of them const — exactly the inconsistency
                    // ARCH_4 R22 means by "verified by compiling, not by reading about it".
                    pieTouchData: PieTouchData(enabled: false),
                    sections: [
                      for (final slice in slices)
                        PieChartSectionData(
                          // `toDouble()` on a magnitude that is an int everywhere else — the same
                          // boundary the line chart's `FlSpot` crosses, and legal for the same reason:
                          // an arc sweep is geometry, not money (Law L1).
                          value: slice.value.toDouble(),
                          color: slice.color,
                          radius: ring,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
                if (centreTop != null || centreBottom != null)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (centreTop != null)
                        Text(centreTop!, style: AlayaTypography.amountSmall),
                      if (centreBottom != null)
                        Text(
                          centreBottom!,
                          style: AlayaTypography.overline.copyWith(
                            color: semantic.muted,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
