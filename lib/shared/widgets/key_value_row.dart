import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// One label/value line on a detail screen (ARCH_5 §3 archetype E).
///
/// **Renders nothing at all when there is no value.** A detail screen that shows `—` for every
/// unset field reads as broken data rather than as a record with optional fields, and on a schema
/// where most columns are nullable that is most of the screen. Hiding the row is the difference
/// between "this asset has no warranty" and "this app failed to load the warranty".
///
/// Both sides are [Flexible], so a long value wraps instead of overflowing — which is what keeps
/// the row safe at a doubled text scale (Law U15).
class KeyValueRow extends StatelessWidget {
  /// Creates a row for [label]. Renders nothing unless [value] or [valueWidget] is supplied.
  const KeyValueRow({
    required this.label,
    this.value,
    this.valueWidget,
    this.onTap,
    this.icon,
    super.key,
  });

  /// The field's name, already localised.
  final String label;

  /// The value as text. Ignored when [valueWidget] is supplied.
  final String? value;

  /// The value as a widget — an `AmountText`, a `QtyText`, a `DateText`, a chip row.
  ///
  /// Preferred over [value] for anything typed: Law U7 routes every `Money`, `Qty` and `DateKey`
  /// through its own widget, and formatting one into a string here would bypass that.
  final Widget? valueWidget;

  /// Makes the row tappable — a payee that opens its detail, a phone number that dials.
  final VoidCallback? onTap;

  /// A leading icon, for a row that is also an action.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final rendered = valueWidget;
    if (rendered == null && value == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final semantic = context.semantic;

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.screenEdge,
        vertical: AlayaSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AlayaIconSize.md, color: semantic.muted),
            const SizedBox(width: AlayaSpacing.sm),
          ],
          Flexible(
            flex: 2,
            child: Text(
              label,
              style: AlayaTypography.label.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AlayaSpacing.md),
          Flexible(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child:
                  rendered ??
                  Text(
                    value!,
                    style: AlayaTypography.body.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.end,
                  ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: AlayaSpacing.xs),
            Icon(
              Icons.chevron_right,
              size: AlayaIconSize.md,
              color: semantic.muted,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AlayaSpacing.minTapTarget,
          ),
          child: content,
        ),
      ),
    );
  }
}
