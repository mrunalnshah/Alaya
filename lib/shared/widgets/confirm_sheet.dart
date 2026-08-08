import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// A bottom sheet asking the user to confirm something.
///
/// A sheet rather than a dialog: it appears near the thumb, and on a one-handed phone a centred
/// dialog puts the destructive button where a stretch is needed.
///
/// Returns `true` only on explicit confirmation. Dismissing by tapping outside or swiping down
/// returns `false` rather than null, so a caller cannot treat "they walked away" as consent by
/// forgetting a null check.
class ConfirmSheet extends StatelessWidget {
  /// Creates a confirmation sheet. Prefer [show].
  const ConfirmSheet({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    this.destructive = false,
    super.key,
  });

  /// The question, phrased so that confirming is the obvious reading.
  final String title;

  /// What confirming will do, including anything reversible about it.
  final String body;

  /// The confirm button's label. Names the action — "Delete", not "OK".
  final String confirmLabel;

  /// The cancel button's label.
  final String cancelLabel;

  /// Renders the confirm button in the danger colour.
  final bool destructive;

  /// Shows the sheet and resolves to whether the user confirmed.
  ///
  /// Through [AlayaBottomSheet.show], so the content scrolls. There is no keyboard here, but a user
  /// at a large accessibility text scale can still make a title, a body and two buttons taller than
  /// the sheet — the same overflow with a different cause.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    required String cancelLabel,
    bool destructive = false,
  }) async {
    final result = await AlayaBottomSheet.show<bool>(
      context: context,
      builder: (context) => ConfirmSheet(
        title: title,
        body: body,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    // AlayaBottomSheet owns the safe area, the padding and the scroll view.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Text(
          body,
          style: AlayaTypography.body.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: semantic.danger,
                  foregroundColor: semantic.onStatus,
                )
              : null,
          child: Text(confirmLabel),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
      ],
    );
  }
}
