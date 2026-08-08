import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/widgets/scroll_safe_center.dart';

/// What a screen shows when it has nothing to show.
///
/// **An empty screen is an invitation to act, not a report that there is no data.** So [body] names
/// the next step and [actionLabel] performs it — "Add your first expense and it will appear here",
/// not "No data available". The copy lives in the ARB; this widget only lays it out.
///
/// Scrolls rather than overflowing when the viewport is short, through [ScrollSafeCenter]. The
/// vertical margin is `xl` rather than `xxxl` because it is a *minimum*: the content is centred in
/// whatever space there is, so a larger figure buys nothing on a tall screen and costs 48px of
/// headroom on a short one.
class EmptyState extends StatelessWidget {
  /// Creates an empty state.
  const EmptyState({
    required this.title,
    required this.body,
    this.icon,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// A short line naming what is absent.
  final String title;

  /// One or two lines naming what to do about it.
  final String body;

  /// An optional icon above the title.
  final IconData? icon;

  /// The action's label. Ignored when [onAction] is null.
  final String? actionLabel;

  /// The action.
  final VoidCallback? onAction;

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
          if (icon != null) ...[
            Icon(icon, size: AlayaIconSize.xl, color: semantic.muted),
            const SizedBox(height: AlayaSpacing.md),
          ],
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
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: AlayaSpacing.xl),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
