import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/shared/widgets/amount_text.dart';

/// One person's slice of a bill.
final class ProportionSlice {
  /// Creates a slice.
  const ProportionSlice({
    required this.label,
    required this.amount,
    this.extra,
  });

  /// Who — a name, or "Person 2" before anybody is named.
  final String label;

  /// Their whole share, extra included.
  final Money amount;

  /// The part of [amount] charged to them alone, when they had an extra.
  final Money? extra;
}

/// A bill drawn to scale, so the split can be seen rather than read.
///
/// ## Why a bar and not just the numbers
///
/// Four figures in a column are four things to compare by reading. One bar is a single glance: Ravi's
/// slice is visibly a third of the bill while everybody else has a fifth, and **the reason for it is
/// drawn as a distinct block inside his slice**. The sentence "₹1,050 share + ₹800 just for them" says
/// the same thing and takes a moment longer, which is a moment somebody spends at a table with three
/// people waiting.
///
/// Nothing else in this category shows the shape of a bill. It costs one widget and no schema.
///
/// ## Colour, and its limits
///
/// Hues are derived from the theme's primary by rotating 47° per slice — a prime-ish step that keeps
/// adjacent slices apart without a hardcoded palette that would fight a user's chosen scheme.
///
/// **Colour is never the only carrier.** Every slice is also named and priced in the legend below, and
/// the bar is decorative in the accessibility sense: a reader who cannot distinguish two hues loses
/// nothing, because the same information is in the rows underneath. That is the same rule the balance
/// rows follow by putting direction in a section heading rather than in a tint.
///
/// ## The remainder
///
/// What the slices do not cover is drawn as a hatched gap rather than being absorbed. Percentages
/// reaching 90% leave a visible tenth of the bar empty, which is a better explanation of "unallocated"
/// than a chip — and it is the same refusal to auto-balance that `LineItemsSection` records.
class SplitProportionBar extends StatelessWidget {
  /// Creates the bar.
  const SplitProportionBar({
    required this.slices,
    required this.total,
    required this.decimalDigits,
    super.key,
  });

  /// Each participant's slice, in display order.
  final List<ProportionSlice> slices;

  /// What is being split, which sets the scale.
  final Money total;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  /// How tall the bar is drawn.
  static const double barHeight = 28;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    // Against the *total*, not against the sum of the slices. Scaling to the slices would stretch an
    // over-allocated split to a perfect bar and hide the very thing worth seeing.
    final scale = total.minor.abs();
    if (scale == 0 || slices.isEmpty) return const SizedBox.shrink();

    final allocated = slices.fold<int>(0, (sum, s) => sum + s.amount.minor);
    final leftover = scale - allocated;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AlayaSpacing.xs),
          child: SizedBox(
            height: barHeight,
            child: Row(
              children: [
                for (var i = 0; i < slices.length; i++)
                  ..._segmentsFor(slices[i], _hueFor(scheme, i)),
                if (leftover > 0)
                  Expanded(
                    flex: leftover,
                    child: CustomPaint(
                      painter: _HatchPainter(color: semantic.muted),
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: AlayaSpacing.sm),
        for (var i = 0; i < slices.length; i++)
          _LegendRow(
            slice: slices[i],
            colour: _hueFor(scheme, i),
            percent: scale == 0 ? 0 : slices[i].amount.minor * 100 / scale,
            decimalDigits: decimalDigits,
          ),
      ],
    );
  }

  /// One or two segments for a slice — two when part of it is an extra.
  ///
  /// `Expanded` with an integer flex, so the widths are laid out by the framework in exact proportion
  /// to minor units. Computing pixel widths here would need the bar's measured width and would
  /// re-introduce the rounding that `Money.allocate` exists to avoid.
  List<Widget> _segmentsFor(ProportionSlice slice, Color colour) {
    final extra = slice.extra?.minor ?? 0;
    final share = slice.amount.minor - extra;
    return [
      if (share > 0)
        Expanded(
          flex: share,
          child: ColoredBox(color: colour),
        ),
      if (extra > 0)
        Expanded(
          flex: extra,
          child: ColoredBox(
            // The same hue, darkened — related to the person's share, and visibly not the same thing.
            // A separate hue would read as a fifth participant.
            color: Color.alphaBlend(
              Colors.black.withValues(alpha: 0.32),
              colour,
            ),
          ),
        ),
    ];
  }

  /// A hue for slice [index], rotated from the theme's primary.
  static Color _hueFor(ColorScheme scheme, int index) {
    final base = HSLColor.fromColor(scheme.primary);
    return base
        .withHue((base.hue + index * 47) % 360)
        // Floors kept off the extremes so a pale or near-black primary still yields legible slices.
        .withSaturation(base.saturation.clamp(0.45, 0.85))
        .withLightness(base.lightness.clamp(0.42, 0.62))
        .toColor();
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.slice,
    required this.colour,
    required this.percent,
    required this.decimalDigits,
  });

  final ProportionSlice slice;
  final Color colour;
  final double percent;
  final int decimalDigits;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Padding(
      padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
      // A `Wrap`, not a `Row`: a name beside an amount beside a percentage is three fixed children,
      // which is the shape that overflows at 320dp with the scaler doubled (Law U15).
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AlayaSpacing.xs,
        runSpacing: AlayaSpacing.xxs,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Text(slice.label, style: AlayaTypography.caption),
          Text(
            strings.splitPercentOfBill(percent.round()),
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          AmountText(
            slice.amount,
            size: AmountSize.small,
            showSign: false,
            decimalDigits: decimalDigits,
          ),
        ],
      ),
    );
  }
}

/// Diagonal stripes for the part of a bill nothing covers.
///
/// Drawn rather than tinted, because a solid grey block reads as another participant. Stripes read as
/// absence, which is what an unallocated remainder is.
class _HatchPainter extends CustomPainter {
  const _HatchPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = color.withValues(alpha: 0.10);
    canvas.drawRect(Offset.zero & size, background);

    final stroke = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = 1.5;
    // Starting at -height so the first stripes still cross the top-left corner; without the offset the
    // leading edge of a narrow remainder is blank and the hatching looks like a rendering fault.
    for (var x = -size.height; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_HatchPainter oldDelegate) => oldDelegate.color != color;
}
