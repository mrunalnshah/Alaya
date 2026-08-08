import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/widgets/scroll_safe_center.dart';

/// What a screen shows when a read failed.
///
/// **Errors do not apologise and are never vague about what happened.** [title] names the failure and
/// [body] says what to do; neither says "sorry". A retry appears only when retrying could plausibly
/// work — offering it for a deleted record trains the user to ignore the button.
///
/// Scrolls rather than overflowing when the viewport is short, through [ScrollSafeCenter]. This one
/// is the tallest of the three states — icon, two text blocks and a 48px button — so it is the one
/// most likely to meet a viewport that cannot hold it.
class ErrorState extends StatelessWidget {
  /// Creates an error state.
  const ErrorState({
    required this.title,
    required this.body,
    this.retryLabel,
    this.onRetry,
    super.key,
  });

  /// What went wrong.
  final String title;

  /// What to do about it.
  final String body;

  /// The retry action's label. Ignored when [onRetry] is null.
  final String? retryLabel;

  /// The retry action.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    return ScrollSafeCenter(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.xxl,
        vertical: AlayaSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: AlayaIconSize.xl,
            color: semantic.danger,
          ),
          const SizedBox(height: AlayaSpacing.md),
          Text(
            title,
            style: AlayaTypography.cardTitle.copyWith(
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            body,
            style: AlayaTypography.body.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null && retryLabel != null) ...[
            const SizedBox(height: AlayaSpacing.xl),
            OutlinedButton(onPressed: onRetry, child: Text(retryLabel!)),
          ],
        ],
      ),
    );
  }
}
