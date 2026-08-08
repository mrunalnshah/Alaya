import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';

/// The loading state for any list surface (ARCH_5 §5.2).
///
/// **A skeleton rather than a spinner, and deliberately without shimmer.** The shape of what is
/// arriving tells the user more than a spinner does, and a spinner centred in a screen that is about
/// to be a list reads as "slow". Shimmer is left out because it is an animation the user waits
/// through on a surface that exists only to be replaced — and because it would have to be suppressed
/// under `disableAnimations` anyway, leaving this exact widget as the fallback.
///
/// Non-scrollable: it fills whatever room it is given and clips the rest, so it can never overflow
/// the space a list was going to occupy.
class AlayaListSkeleton extends StatelessWidget {
  /// Creates a skeleton of [rows] placeholder rows, described to assistive technology as [label].
  const AlayaListSkeleton({
    required this.label,
    this.rows = 5,
    this.hasLeading = true,
    this.hasTrailing = true,
    super.key,
  });

  /// What is loading, already localised. `CircularProgressIndicator` has semantics; a box does not.
  final String label;

  /// How many placeholder rows to draw.
  final int rows;

  /// Whether rows show a leading identity block — an icon or a colour dot.
  final bool hasLeading;

  /// Whether rows show a trailing block, which in this app is almost always an amount.
  final bool hasTrailing;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    liveRegion: true,
    child: ExcludeSemantics(
      child: ListView.builder(
        // `shrinkWrap` and `NeverScrollableScrollPhysics` travel together. The physics say it
        // will not scroll; `shrinkWrap` is what lets it size to its children instead of
        // demanding a viewport. One without the other throws the moment this skeleton renders
        // inside another scrollable — which is every detail screen, on its first frame.
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.xs),
        itemCount: rows,
        itemBuilder: (context, index) => _SkeletonRow(
          hasLeading: hasLeading,
          hasTrailing: hasTrailing,
          // Varied widths so the block reads as content rather than as a loading bar.
          titleFactor: index.isEven ? 0.55 : 0.4,
        ),
      ),
    ),
  );
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({
    required this.hasLeading,
    required this.hasTrailing,
    required this.titleFactor,
  });

  final bool hasLeading;
  final bool hasTrailing;
  final double titleFactor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AlayaSpacing.screenEdge,
      vertical: AlayaSpacing.sm,
    ),
    child: Row(
      children: [
        if (hasLeading) ...[
          const _Block(
            width: AlayaSpacing.xxl,
            height: AlayaSpacing.xxl,
            rounded: true,
          ),
          const SizedBox(width: AlayaSpacing.sm),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: titleFactor,
                child: const _Block(height: AlayaSpacing.md),
              ),
              const SizedBox(height: AlayaSpacing.xxs),
              const FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: 0.3,
                child: _Block(height: AlayaSpacing.sm),
              ),
            ],
          ),
        ),
        if (hasTrailing) ...[
          const SizedBox(width: AlayaSpacing.md),
          const _Block(width: AlayaSpacing.xxxl, height: AlayaSpacing.md),
        ],
      ],
    ),
  );
}

class _Block extends StatelessWidget {
  const _Block({required this.height, this.width, this.rounded = false});

  final double height;
  final double? width;
  final bool rounded;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: context.semantic.surfaceSunken,
      borderRadius: rounded ? AlayaRadii.borderSm : AlayaRadii.borderXs,
    ),
  );
}
