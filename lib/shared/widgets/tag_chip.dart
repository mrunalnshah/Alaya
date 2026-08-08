import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/tag.dart';

/// Renders one [Tag].
///
/// A tag may carry its own `colorArgb`, which is user data rather than a palette value — so it is
/// used for a small leading dot and never for the label or the fill. A user-chosen colour behind text
/// would break contrast unpredictably, and there is no way to guarantee a readable foreground for an
/// arbitrary background.
///
/// **A tappable chip reaches the 48px tap-target floor; a display-only one stays compact.** The chip
/// is the densest interactive element in the app and it is how tags get selected, so the hit area
/// cannot be the 21px the label alone implies. The coloured pill is also the ink surface rather than
/// sitting on top of one, because a Material paints its splashes beneath its child and an opaque fill
/// in between makes a press produce no feedback at all.
class TagChip extends StatelessWidget {
  /// Creates a chip for [tag].
  const TagChip({
    required this.tag,
    this.selected = false,
    this.onTap,
    this.onRemove,
    this.removeLabel,
    super.key,
  });

  /// The tag.
  final Tag tag;

  /// Whether the tag is currently applied.
  final bool selected;

  /// Tap handler, usually a toggle.
  final VoidCallback? onTap;

  /// Remove handler. When set, a trailing dismiss affordance appears.
  final VoidCallback? onRemove;

  /// Accessibility label for the dismiss affordance, already localised.
  ///
  /// Passed in rather than read from the ARB here, so this widget needs no `Localizations` ancestor
  /// and its goldens stay independent of `flutter gen-l10n` having run.
  final String? removeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final dotColor = tag.colorArgb == null ? null : Color(tag.colorArgb!);
    final background = selected
        ? theme.colorScheme.primary
        : semantic.surfaceSunken;
    final foreground = selected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurfaceVariant;
    final shape = RoundedRectangleBorder(
      borderRadius: AlayaRadii.borderXs,
      side: selected ? BorderSide.none : BorderSide(color: theme.dividerColor),
    );

    final body = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.xs,
        vertical: AlayaSpacing.xxs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            _Dot(color: dotColor),
            const SizedBox(width: AlayaSpacing.xxs),
          ],
          Flexible(
            child: Text(
              tag.name,
              style: AlayaTypography.overline.copyWith(color: foreground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: AlayaSpacing.xxs),
            Semantics(
              button: true,
              label: removeLabel,
              child: InkResponse(
                onTap: onRemove,
                radius: AlayaSpacing.md,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(AlayaSpacing.xxs),
                  child: Icon(
                    Icons.close,
                    size: AlayaIconSize.sm,
                    color: foreground,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return Material(
        color: background,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: body,
      );
    }

    return Semantics(
      button: true,
      selected: selected,
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

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: AlayaSpacing.xs,
    height: AlayaSpacing.xs,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
