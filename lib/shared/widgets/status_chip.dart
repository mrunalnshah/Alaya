import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// What a [StatusChip] is reporting.
///
/// A tone rather than a colour: the chip is the single place any of these seven states is rendered,
/// so `needsReview`, `unallocated`, `detached`, `overdue`, `expiring`, `low` and `approximate` all
/// look the same wherever they appear, and changing what "warning" looks like is one edit.
enum StatusTone {
  /// Factual, no judgement — `detached`, `approximate`, a count.
  neutral,

  /// Worth knowing — `needsReview`, `unallocated`.
  info,

  /// Needs attention soon — `expiring`, `low`, due within the window.
  warning,

  /// Wrong or past due — `overdue`, `expired`.
  danger,

  /// Completed — `paid`, `restored`.
  success,
}

/// A small labelled status pill.
///
/// **The label is required, and that is Law U17 rather than a style choice.** Colour alone excludes
/// roughly eight percent of men, and survives neither a greyscale screenshot nor a screen reader.
/// The tone tints the chip; the word carries the meaning.
class StatusChip extends StatelessWidget {
  /// Creates a chip reading [label] in [tone].
  const StatusChip({
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
    this.trailing,
    this.onTap,
    super.key,
  });

  /// The status, already localised. Two or three words at most.
  final String label;

  /// Which semantic colour to tint with.
  final StatusTone tone;

  /// An optional leading glyph. Never a substitute for [label].
  final IconData? icon;

  /// A rendered value after the label — an `AmountText` or a `QtyText`.
  ///
  /// A chip that must show money cannot take it as a string: `Money` is minor units, and formatting
  /// it at the call site is how `2000.00` reaches the screen as `200000` (Law U7). The value is
  /// rendered by its own widget and handed in.
  final Widget? trailing;

  /// Makes the chip an action — "3 need details" opening a filtered list.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final foreground = switch (tone) {
      StatusTone.neutral => semantic.muted,
      StatusTone.info => semantic.transfer,
      StatusTone.warning => semantic.warning,
      StatusTone.danger => semantic.danger,
      StatusTone.success => semantic.success,
    };

    final body = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.xs,
        vertical: AlayaSpacing.xxs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AlayaIconSize.sm, color: foreground),
            const SizedBox(width: AlayaSpacing.xxs),
          ],
          Flexible(
            child: Text(
              label,
              style: AlayaTypography.overline.copyWith(color: foreground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AlayaSpacing.xxs),
            trailing!,
          ],
        ],
      ),
    );

    // The tint is the tone at low alpha rather than a second palette entry, so a chip cannot drift
    // out of step with the colour it is reporting.
    final shape = RoundedRectangleBorder(
      borderRadius: AlayaRadii.borderXs,
      side: BorderSide(color: foreground.withValues(alpha: 0.28)),
    );
    final background = foreground.withValues(alpha: 0.12);

    if (onTap == null) {
      return Semantics(
        label: label,
        child: Material(
          color: background,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: body,
        ),
      );
    }

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: background,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AlayaSpacing.minTapTarget,
            ),
            child: Center(widthFactor: 1, child: body),
          ),
        ),
      ),
    );
  }
}
