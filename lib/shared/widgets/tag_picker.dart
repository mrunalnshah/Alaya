import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// Selects zero or more tags, filtered to those valid for a [scope].
///
/// A wrap of chips rather than a dropdown or a dialog. Tags are chosen several at a time and the
/// current selection needs to stay visible while choosing — a dropdown hides it at exactly the moment
/// the user is deciding whether they have enough.
///
/// Filters by [scope] because `Tag.allowedScopes` exists: a tag scoped to items should not be offerable
/// on a transaction, and letting it through would put a link row in a table whose scope forbids it.
class TagPicker extends StatelessWidget {
  /// Creates a tag picker.
  const TagPicker({
    required this.available,
    required this.selectedIds,
    required this.scope,
    required this.onToggle,
    this.label,
    this.emptyLabel,
    super.key,
  });

  /// Every tag the user has.
  final List<Tag> available;

  /// The ids currently applied.
  final Set<String> selectedIds;

  /// The scope being tagged.
  final TagScope scope;

  /// Called with a tag's id when the user toggles it.
  final ValueChanged<String> onToggle;

  /// The control's label.
  final String? label;

  /// Shown when no tag is valid for [scope].
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eligible =
        available
            .where((tag) => !tag.isDeleted && tag.allowedScopes.contains(scope))
            .toList()
          ..sort((a, b) {
            // Selected first, then the user's own order. Keeping selection at the top means a long tag
            // list never hides what is already applied.
            final aSelected = selectedIds.contains(a.id);
            final bSelected = selectedIds.contains(b.id);
            if (aSelected != bSelected) return aSelected ? -1 : 1;
            return a.sortOrder.compareTo(b.sortOrder);
          });

    if (eligible.isEmpty && emptyLabel != null) {
      return Text(
        emptyLabel!,
        style: AlayaTypography.caption.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: AlayaTypography.label.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AlayaSpacing.xs),
        ],
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final tag in eligible)
              TagChip(
                tag: tag,
                selected: selectedIds.contains(tag.id),
                onTap: () => onToggle(tag.id),
              ),
          ],
        ),
      ],
    );
  }
}
