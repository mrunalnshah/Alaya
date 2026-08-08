import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// A navigation tile carrying a live number (ARCH_5 §8 — the one shared addition Phase 6F makes).
///
/// **The number is the point.** A grid of labelled icons is decoration: it tells the user what the app
/// contains, which they already know, and gives no reason to tap one tile rather than another. A count
/// that moves — three items running low, two bills due — is the difference between a menu and a
/// dashboard.
///
/// The count arrives as already-localised text rather than an `int`, because "nothing tracked" and
/// "3 running low" are different sentences and only the ARB knows which to use.
///
/// ## Requires a bounded height, and never overflows inside one
///
/// A grid cell is a fixed box, and both of this tile's labels grow with text scale while the box does
/// not. The first version put a `MainAxisSize.max` column of freely-wrapping `Text`s inside that box and
/// overflowed by 22px at scale 1 and 250px at scale 2 — the P1 shape, one layer in: not a starved
/// `Expanded` sibling but a starved `Column` (Law U2, U21).
///
/// Both `Text`s are therefore `Flexible` and ellipsise. **Ellipsis is legitimate here precisely because
/// neither string is a `Money` or a `Qty`.** U7 forbids truncating a figure because half a number reads
/// as a smaller number; a truncated sentence still reads as a sentence. `ModuleGrid` sizes its cells from
/// the current text scaler, so the ellipsis is a floor the layout rarely reaches rather than the normal
/// case — but it is the floor, and the tile holds it on its own.
///
/// Given an *unbounded* height the flex assertion fires and names the caller, which is the same contract
/// `ScrollSafeCenter` carries. That is deliberate: a tile with nothing bounding it has no shape to
/// defend.
class ModuleTile extends StatelessWidget {
  /// Creates a tile.
  const ModuleTile({
    required this.label,
    required this.icon,
    required this.detail,
    required this.onTap,
    this.tone,
    this.semanticsLabel,
    super.key,
  });

  /// What the module is called — the drawer's own wording, so the tile names somewhere real.
  final String label;

  /// Its glyph.
  final IconData icon;

  /// The live number, already localised and pluralised.
  final String detail;

  /// Opens the module.
  final VoidCallback onTap;

  /// Colours the glyph when the count is worth noticing; muted when it is not.
  final Color? tone;

  /// Overrides the composed semantics label, which otherwise reads label then detail.
  final String? semanticsLabel;

  /// How many lines each of the two labels may take before it truncates.
  ///
  /// Public because `ModuleGrid` reserves exactly this many when it measures a cell. A tile that budgets
  /// two lines inside a cell sized for one is the overflow all over again, so the two read one number.
  static const int maxLabelLines = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;

    return Semantics(
      button: true,
      label: semanticsLabel ?? '$label. $detail',
      excludeSemantics: true,
      child: Material(
        color: semantic.surfaceSunken,
        borderRadius: AlayaRadii.borderMd,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AlayaSpacing.minTapTarget * 2,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AlayaSpacing.sm),
              // A `Column`, not a `Row`: the label and the count both grow with text scale, and side by
              // side one of them starves at 320dp (Law U21).
              //
              // `min` rather than `max`, and `start` rather than `spaceBetween`: the flexible children
              // already absorb whatever room the cell has, so `spaceBetween` had nothing left to
              // distribute while `max` forced the column to fill a box its content could exceed.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: AlayaIconSize.lg,
                    color: tone ?? semantic.muted,
                  ),
                  const SizedBox(height: AlayaSpacing.xs),
                  Flexible(
                    child: Text(
                      label,
                      style: AlayaTypography.body.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: maxLabelLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: AlayaSpacing.xxs),
                  Flexible(
                    child: Text(
                      detail,
                      style: AlayaTypography.caption.copyWith(
                        color: tone ?? semantic.muted,
                      ),
                      maxLines: maxLabelLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
