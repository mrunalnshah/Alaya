import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// One row of a [SliceBarList].
class SliceBar {
  /// Creates a row.
  const SliceBar({
    required this.label,
    required this.value,
    required this.share,
    this.detail,
    this.onTap,
    this.swatch,
  });

  /// What this slice is, already localised.
  final String label;

  /// The figure, **already rendered by its own widget** — an `AmountText` or a `QtyText`.
  ///
  /// A `Money` field would have hardcoded `AmountText` here and made this list unable to show a
  /// quantity, which query 10 needs; formatting either into a `String` at the call site would bypass
  /// the only path from a `Money` or a `Qty` to pixels (Law U7). The same reasoning gives
  /// `KeyValueRow` its `valueWidget`.
  final Widget value;

  /// Its share of the largest slice, `0.0`-`1.0`, which sets the bar's length.
  final double share;

  /// An optional second line — a count, a unit, a date.
  final String? detail;

  /// Opens this slice's drill-down.
  final VoidCallback? onTap;

  /// The colour of this slice's wedge, when a donut sits above the list.
  ///
  /// Present only where a ring is showing. It is what ties a row to its arc, and it is why the ring can
  /// use a single-hue ramp instead of categorical colours — identity lives here, in text, beside a
  /// figure (Law U17: colour is never the only signal).
  final Color? swatch;
}

/// A ranked breakdown as labelled bars, largest first.
///
/// **This is the workhorse surface and it deliberately uses no chart library.** A pie is unreadable
/// at a doubled text scale, cannot label eight slices, and gives the reader nothing to tap; a ranked
/// list of figures is what somebody deciding where their money went actually needs, and every row is
/// a 48dp target into the ledger behind it (Laws U3, U13, U15).
///
/// `fl_chart` earns its place for the two shapes a list genuinely cannot express — a trend over time
/// and a bucketed heatmap — and nowhere else.
class SliceBarList extends StatelessWidget {
  /// Creates a breakdown of [slices].
  const SliceBarList({
    required this.slices,
    this.maxRows = 6,
    this.showBars = true,
    super.key,
  });

  /// The slices, already ordered.
  final List<SliceBar> slices;

  /// Whether each row draws its proportional bar.
  ///
  /// False where a donut sits above the list: the ring already carries the proportion, and a bar
  /// repeating it is the second accessory to remove. The swatch and the figure stay.
  final bool showBars;

  /// How many rows to show before stopping.
  ///
  /// A card is a shortlist, not a second screen: the drill-down holds the rest. Six is what fits
  /// above the fold on the narrowest supported phone.
  final int maxRows;

  /// Above this text scale a row stacks its figure under its label (Law U21).
  static const double _stackAboveScale = 1.5;

  @override
  Widget build(BuildContext context) {
    final stacked =
        MediaQuery.textScalerOf(context).scale(1) >= _stackAboveScale;
    // A plain Column, not a ListView: this is a bounded shortlist of at most [maxRows] inside a card
    // that is already inside the screen's scroll view. Law U13 is about lists fed by a repository
    // stream, and a nested scrollable here would put two gestures in one arena (ARCH_6 P2).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final slice in slices.take(maxRows))
          _SliceRow(slice: slice, stacked: stacked, showBar: showBars),
      ],
    );
  }
}

class _SliceRow extends StatelessWidget {
  const _SliceRow({
    required this.slice,
    required this.stacked,
    required this.showBar,
  });

  final SliceBar slice;
  final bool stacked;
  final bool showBar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;

    final text = Text(
      slice.label,
      style: AlayaTypography.body.copyWith(color: theme.colorScheme.onSurface),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    final label = slice.swatch == null
        ? text
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Decorative: the arc it matches is already excluded from semantics, and the label beside
              // it carries the identity.
              ExcludeSemantics(child: _Swatch(color: slice.swatch!)),
              const SizedBox(width: AlayaSpacing.xs),
              Flexible(child: text),
            ],
          );
    final amount = slice.value;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stacked) ...[
          label,
          const SizedBox(height: AlayaSpacing.xxs),
          Align(alignment: Alignment.centerLeft, child: amount),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: label),
              const SizedBox(width: AlayaSpacing.sm),
              amount,
            ],
          ),
        if (slice.detail != null) ...[
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            slice.detail!,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ],
        if (showBar) ...[
          const SizedBox(height: AlayaSpacing.xs),
          ExcludeSemantics(child: _Bar(share: slice.share)),
        ],
      ],
    );

    // One semantics node per row, so a screen reader reads "Groceries, 4,200 rupees" as one thing
    // rather than three fragments and an unlabelled bar (ARCH_5 §6).
    //
    // **`container: true` with no `label`, deliberately.** A hand-written label would replace the
    // children's own semantics — including `AmountText`'s, which is the only thing that knows how to
    // say a `Money` out loud. Building that string here would mean formatting minor units at the call
    // site, which is the Law U7 violation the widget exists to prevent. Only the bar is excluded: it
    // carries nothing the figure beside it does not.
    final semantics = Semantics(
      container: true,
      button: slice.onTap != null,
      child: body,
    );

    final padded = Padding(
      padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.xs),
      child: semantics,
    );

    if (slice.onTap == null) return padded;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: slice.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AlayaSpacing.minTapTarget,
          ),
          child: padded,
        ),
      ),
    );
  }
}

/// The dot tying a row to its wedge.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  /// On the spacing scale, like every other dimension (Law U6).
  static const double _size = AlayaSpacing.sm;

  @override
  Widget build(BuildContext context) => Container(
    width: _size,
    height: _size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// The proportional bar under a row.
class _Bar extends StatelessWidget {
  const _Bar({required this.share});

  final double share;

  /// The bar's thickness. On the spacing scale because Law U6 admits no other source of a dimension.
  static const double _thickness = AlayaSpacing.xs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Clamped, because `share` is a ratio computed from sums and a rounding artefact above 1 would
    // hand `FractionallySizedBox` a factor it asserts on.
    final factor = share.isFinite ? share.clamp(0.0, 1.0) : 0.0;
    return ClipRRect(
      borderRadius: AlayaRadii.borderXs,
      child: SizedBox(
        height: _thickness,
        child: ColoredBox(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: factor,
            child: ColoredBox(color: theme.colorScheme.primary),
          ),
        ),
      ),
    );
  }
}
