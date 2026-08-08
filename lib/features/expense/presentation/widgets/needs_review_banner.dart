import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// The nudge that surfaces `transactions.needsReview` (ARCH_5 §7.2).
///
/// Quick-add captures an amount and nothing else, which is the whole point of an optional-first
/// capture path (Law U11) — but a column that records "this is incomplete" and is never shown turns
/// a deliberate shortcut into silent data rot. This is the row that closes that loop.
///
/// Renders nothing at zero. A banner reading "0 transactions need details" is noise on every screen
/// where the user is already up to date.
class NeedsReviewBanner extends StatelessWidget {
  /// Creates the nudge for [count] transactions, opening the filtered list through [onTap].
  const NeedsReviewBanner({
    required this.count,
    required this.onTap,
    super.key,
  });

  /// How many transactions still need details.
  final int count;

  /// Shows them.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final strings = AlayaStrings.of(context);
    // Above roughly 1.5x, the message and the action cannot share a line at 320dp. The action is
    // non-flexible, so it takes its full natural width and leaves the message a column barely wider
    // than a character — which wrapped "2 transactions need details" to twenty-nine lines and made
    // this banner 1,084px tall, starving the ledger beneath it of every pixel (Law U15).
    //
    // Stacking is the fix rather than truncating: ellipsising the count is the one thing this nudge
    // cannot do, because the count *is* the message.
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5;

    final message = Text(
      strings.needsReviewBanner(count),
      style: AlayaTypography.body.copyWith(color: theme.colorScheme.onSurface),
    );
    final action = Text(
      strings.needsReviewAction,
      style: AlayaTypography.button.copyWith(color: semantic.transfer),
    );
    final leading = Icon(
      Icons.edit_note,
      size: AlayaIconSize.md,
      color: semantic.transfer,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
        AlayaSpacing.screenEdge,
        AlayaSpacing.xxs,
      ),
      child: Material(
        color: semantic.transfer.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: AlayaRadii.borderSm,
          side: BorderSide(color: semantic.transfer.withValues(alpha: 0.28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AlayaSpacing.minTapTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlayaSpacing.sm,
                vertical: AlayaSpacing.xs,
              ),
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            leading,
                            const SizedBox(width: AlayaSpacing.xs),
                            Expanded(child: message),
                          ],
                        ),
                        const SizedBox(height: AlayaSpacing.xs),
                        action,
                      ],
                    )
                  : Row(
                      children: [
                        leading,
                        const SizedBox(width: AlayaSpacing.xs),
                        Expanded(child: message),
                        const SizedBox(width: AlayaSpacing.xs),
                        action,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
