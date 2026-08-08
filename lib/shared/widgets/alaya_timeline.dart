import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// How a timeline entry is toned.
enum TimelineTone {
  /// The default — a neutral event.
  neutral,

  /// Stock arriving.
  incoming,

  /// Stock leaving.
  outgoing,

  /// A correction, drawn muted and struck through.
  superseded,
}

/// One event on an [AlayaTimeline].
class AlayaTimelineEntry {
  /// Creates an entry.
  const AlayaTimelineEntry({
    required this.title,
    required this.trailing,
    this.subtitle,
    this.meta,
    this.icon,
    this.tone = TimelineTone.neutral,
    this.badge,
    this.onTap,
  });

  /// What happened.
  final String title;

  /// The figure, rendered by the caller so `Qty` still goes through `QtyText` (U7).
  final Widget trailing;

  /// When it happened, rendered by the caller so `DateKey` still goes through `DateText` (U7).
  final Widget? subtitle;

  /// A secondary line — a reason, a note.
  final String? meta;

  /// A glyph on the rail.
  final IconData? icon;

  /// How to tone the entry.
  final TimelineTone tone;

  /// A chip-like marker, e.g. "Reversed".
  final String? badge;

  /// Opens the entry.
  final VoidCallback? onTap;
}

/// A vertical event timeline (ARCH_5 §8), returned as a sliver.
///
/// **Takes a builder, not a list.** An earlier version took `List<AlayaTimelineEntry>`, and because
/// every entry holds constructed widgets — a `QtyText`, a `DateText` — a batch with a year of
/// consumption allocated the whole year's widgets on every rebuild. Rendering was virtualised;
/// construction was not, which is the half of U13 that a `SliverList` alone does not give you.
///
/// Place it inside a `CustomScrollView`.
class AlayaTimeline extends StatelessWidget {
  /// Creates the timeline.
  const AlayaTimeline({
    required this.itemCount,
    required this.itemBuilder,
    super.key,
  });

  /// How many events there are.
  final int itemCount;

  /// Builds the event at [index], newest first.
  final AlayaTimelineEntry Function(BuildContext context, int index)
  itemBuilder;

  @override
  Widget build(BuildContext context) => SliverList.builder(
    itemCount: itemCount,
    itemBuilder: (context, index) => _Entry(
      entry: itemBuilder(context, index),
      isFirst: index == 0,
      isLast: index == itemCount - 1,
    ),
  );
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.entry,
    required this.isFirst,
    required this.isLast,
  });

  final AlayaTimelineEntry entry;
  final bool isFirst;
  final bool isLast;

  Color _toneColour(AlayaSemanticColors semantic) => switch (entry.tone) {
    TimelineTone.neutral => semantic.muted,
    TimelineTone.incoming => semantic.success,
    TimelineTone.outgoing => semantic.danger,
    TimelineTone.superseded => semantic.muted,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final colour = _toneColour(semantic);
    final superseded = entry.tone == TimelineTone.superseded;

    // `IntrinsicHeight` is what lets the connector reach the next entry. The rail is a Column with an
    // `Expanded` segment, and a sliver child's Row has no height of its own — so without this the
    // Column is unbounded and `Expanded` throws rather than stretching.
    final body = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.screenEdge,
        vertical: AlayaSpacing.xs,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Rail(
              colour: colour,
              icon: entry.icon,
              isFirst: isFirst,
              isLast: isLast,
            ),
            const SizedBox(width: AlayaSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // **Stacks above 1.5x (Law U21).** `trailing` is whatever the caller passes — an
                  // `AmountText`, a `QtyText` — and it is not flexible, so at a doubled text scale it
                  // takes its natural width and pushes the title off the rail. `Flexible` is the wrong
                  // fix: against a tight `Expanded` the two split evenly and the title truncates at
                  // scale 1, and a clipped figure is a wrong figure.
                  if (MediaQuery.textScalerOf(context).scale(1) >= 1.5) ...[
                    Text(
                      entry.title,
                      style: AlayaTypography.body.copyWith(
                        color: superseded
                            ? semantic.muted
                            : theme.colorScheme.onSurface,
                        decoration: superseded
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: AlayaSpacing.xxs),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: entry.trailing,
                    ),
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            entry.title,
                            style: AlayaTypography.body.copyWith(
                              color: superseded
                                  ? semantic.muted
                                  : theme.colorScheme.onSurface,
                              decoration: superseded
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: AlayaSpacing.sm),
                        entry.trailing,
                      ],
                    ),
                  if (entry.subtitle != null) ...[
                    const SizedBox(height: AlayaSpacing.xxs),
                    entry.subtitle!,
                  ],
                  if (entry.meta != null) ...[
                    const SizedBox(height: AlayaSpacing.xxs),
                    Text(
                      entry.meta!,
                      style: AlayaTypography.caption.copyWith(
                        color: semantic.muted,
                      ),
                    ),
                  ],
                  if (entry.badge != null) ...[
                    const SizedBox(height: AlayaSpacing.xs),
                    _Badge(label: entry.badge!, colour: colour),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final onTap = entry.onTap;
    if (onTap == null) return body;
    return InkWell(onTap: onTap, child: body);
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.colour,
    required this.icon,
    required this.isFirst,
    required this.isLast,
  });

  final Color colour;
  final IconData? icon;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: AlayaIconSize.lg,
    child: Column(
      children: [
        _Line(colour: colour, visible: !isFirst, height: AlayaSpacing.xs),
        Icon(icon ?? Icons.circle, size: AlayaIconSize.sm, color: colour),
        if (!isLast) Expanded(child: _Line(colour: colour, visible: true)),
      ],
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line({required this.colour, required this.visible, this.height});

  final Color colour;
  final bool visible;
  final double? height;

  @override
  Widget build(BuildContext context) => Container(
    width: AlayaSpacing.xxs / 2,
    height: height,
    color: visible ? colour.withValues(alpha: 0.28) : Colors.transparent,
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.colour});

  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AlayaSpacing.xs,
      vertical: AlayaSpacing.xxs,
    ),
    decoration: BoxDecoration(
      color: colour.withValues(alpha: 0.12),
      borderRadius: AlayaRadii.borderXs,
    ),
    child: Text(
      label,
      style: AlayaTypography.overline.copyWith(color: colour),
    ),
  );
}
