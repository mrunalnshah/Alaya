import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// A header separating sections inside a scrolling screen.
///
/// Upper-cases its label. The transformation lives here rather than in the ARB, because the ARB holds
/// the sentence a translator writes and casing is presentation — a locale where upper case is wrong,
/// or a screen reader that spells out capitals, both need the original string intact.
class SectionHeader extends StatelessWidget {
  /// Creates a header.
  const SectionHeader({
    required this.label,
    this.trailing,
    this.padding = const EdgeInsets.only(
      left: AlayaSpacing.screenEdge,
      right: AlayaSpacing.screenEdge,
      top: AlayaSpacing.xl,
      bottom: AlayaSpacing.xs,
    ),
    super.key,
  });

  /// The label, already localised.
  final String label;

  /// An optional action on the right — "See all", a count, a filter.
  final Widget? trailing;

  /// Surrounding padding.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: AlayaTypography.sectionHeader.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              // The original casing is what assistive technology reads.
              semanticsLabel: label,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
