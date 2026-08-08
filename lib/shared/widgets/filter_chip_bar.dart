import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// One active filter, rendered as a removable chip.
class ActiveFilter {
  /// Creates a filter labelled [label] that [onRemove] clears.
  const ActiveFilter({required this.label, required this.onRemove});

  /// What is filtered, already localised and including the value — "Account: HDFC", not "Account".
  final String label;

  /// Clears just this filter.
  final VoidCallback onRemove;
}

/// The active-filter row above a ledger list (ARCH_5 §3 archetype C).
///
/// **A filter the user cannot see is a bug report waiting to happen.** A list quietly constrained by
/// a filter set on a previous visit is indistinguishable from a list that lost its data, and "my
/// transactions disappeared" is the support mail that follows. So every active filter is visible and
/// individually removable, and the bar disappears entirely when nothing is filtered.
///
/// A [Wrap] rather than a horizontal scroller: a scroller has to be given a height, and a fixed
/// height overflows the moment the text scale is raised (Law U15).
class FilterChipBar extends StatelessWidget {
  /// Creates a bar for [filters]. Renders nothing when the list is empty.
  const FilterChipBar({
    required this.filters,
    this.onClearAll,
    this.clearAllLabel,
    super.key,
  });

  /// The filters currently narrowing the list.
  final List<ActiveFilter> filters;

  /// Clears every filter at once. Offered only when more than one is active.
  final VoidCallback? onClearAll;

  /// The clear-all action's label, already localised.
  final String? clearAllLabel;

  @override
  Widget build(BuildContext context) {
    if (filters.isEmpty) return const SizedBox.shrink();
    final showClearAll =
        onClearAll != null && clearAllLabel != null && filters.length > 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
      ),
      child: Wrap(
        spacing: AlayaSpacing.xs,
        runSpacing: AlayaSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final filter in filters) _FilterChip(filter: filter),
          if (showClearAll)
            TextButton(
              onPressed: onClearAll,
              child: Text(clearAllLabel!, style: AlayaTypography.button),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.filter});

  final ActiveFilter filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: filter.label,
      child: Material(
        color: theme.colorScheme.secondary.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: AlayaRadii.borderXs,
          side: BorderSide(
            color: theme.colorScheme.secondary.withValues(alpha: 0.28),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: filter.onRemove,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AlayaSpacing.minTapTarget,
            ),
            child: Center(
              widthFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AlayaSpacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        filter.label,
                        style: AlayaTypography.overline.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AlayaSpacing.xxs),
                    Icon(
                      Icons.close,
                      size: AlayaIconSize.sm,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
