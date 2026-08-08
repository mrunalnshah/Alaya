import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// A centred loading indicator with a label.
///
/// The label is not decoration: a bare spinner tells a screen reader nothing, and
/// `CircularProgressIndicator` has no implicit semantics of its own.
class LoadingState extends StatelessWidget {
  /// Creates a loading state.
  const LoadingState({required this.label, this.compact = false, super.key});

  /// What is loading, already localised.
  final String label;

  /// Renders inline rather than filling the viewport — for a list footer.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indicator = SizedBox(
      width: AlayaSpacing.xl,
      height: AlayaSpacing.xl,
      child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: label),
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.all(AlayaSpacing.md),
        child: Center(child: indicator),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          indicator,
          const SizedBox(height: AlayaSpacing.md),
          Text(
            label,
            style: AlayaTypography.caption.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
