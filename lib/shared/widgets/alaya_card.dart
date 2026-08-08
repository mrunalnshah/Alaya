import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_elevation.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';

/// The app's one card surface.
///
/// Takes a surface **tier** rather than an elevation number, because depth here is a palette step and
/// not a shadow — which is what keeps a card legible in dark mode, where a soft black shadow on a
/// near-black ground conveys nothing (see `AlayaElevation`).
class AlayaCard extends StatelessWidget {
  /// Creates a card.
  const AlayaCard({
    required this.child,
    this.tier = 1,
    this.padding = const EdgeInsets.all(AlayaSpacing.md),
    this.onTap,
    this.onLongPress,
    this.border = false,
    this.semanticsLabel,
    super.key,
  });

  /// The card's content.
  final Widget child;

  /// The surface tier: -1 sunken, 0 base, 1 raised (the default), 2 overlay.
  final int tier;

  /// Inner padding. Always a token value.
  final EdgeInsetsGeometry padding;

  /// Tap handler. When null the card is not interactive and takes no ink.
  final VoidCallback? onTap;

  /// Long-press handler, usually a context menu.
  final VoidCallback? onLongPress;

  /// Draws a hairline border, for a card on a same-coloured surface.
  final bool border;

  /// An accessibility label describing the card as a whole.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final isDark = theme.brightness == Brightness.dark;
    final interactive = onTap != null || onLongPress != null;
    final shape = RoundedRectangleBorder(
      borderRadius: AlayaRadii.borderMd,
      side: border ? BorderSide(color: theme.dividerColor) : BorderSide.none,
    );
    final content = Padding(padding: padding, child: child);

    // The surface colour and the border belong to the Material, not to a DecoratedBox wrapped
    // around it. A Material paints its ink splashes *beneath* its child, so an opaque decoration
    // between the two hides every ripple — the card looked correct and simply never responded to a
    // press. The DecoratedBox here carries the shadow and nothing else.
    final surface = Material(
      color: semantic.surfaceForTier(tier),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: interactive
          ? InkWell(onTap: onTap, onLongPress: onLongPress, child: content)
          : content,
    );

    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AlayaRadii.borderMd,
        // No shadow on a sunken tier: a well does not cast one.
        boxShadow: tier <= 0
            ? AlayaElevation.none
            : AlayaElevation.raised(isDark: isDark),
      ),
      child: surface,
    );

    return semanticsLabel == null
        ? card
        : Semantics(label: semanticsLabel, container: true, child: card);
  }
}
