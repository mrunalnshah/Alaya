import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/inventory/presentation/sheets/new_kind_sheet.dart';
import 'package:alaya/features/inventory/presentation/widgets/kind_display.dart';
import 'package:alaya/features/inventory/providers/inventory_list_providers.dart';

/// Chooses which kind an item is filed under, and can make a new one.
///
/// **The last row is "New kind", and that is the point of the whole change.** Adding `Vegetables` used to mean
/// leaving whatever you were doing, finding Settings › Tags, creating a tag, remembering to tick the inventory
/// scope, and coming back. Now it is the bottom entry of the list you already opened.
///
/// The same pattern the item picker in `line_item_editor` uses, for the same reason: a separate "add" button
/// beside a dropdown is a control people do not find, and one that only appears when the list is empty is a
/// control that vanishes exactly when somebody has learnt to look for it.
///
/// **Creating is offered here; deleting is not.** Creating a kind is cheap and reversible. Deleting one moves
/// every item filed under it to *Other*, and that belongs where the count can be shown — Settings — not on a
/// form somebody is halfway through.
class KindPicker extends ConsumerWidget {
  /// Creates the picker.
  const KindPicker({
    required this.kindTagId,
    required this.onChanged,
    this.label,
    super.key,
  });

  /// The chosen kind's tag id, or null for none.
  final String? kindTagId;

  /// Called with the new tag id, or null when the kind is cleared.
  final ValueChanged<String?> onChanged;

  /// Overrides the field label.
  final String? label;

  /// The value the "new kind" row carries.
  ///
  /// A sentinel, because `null` in this dropdown already means "not set" and a row reusing it could not be told
  /// apart from clearing the field. Tag ids are UUIDv7, so nothing collides.
  static const String _newValue = '__alaya_new_kind__';

  /// The value the "not set" row carries, for the same reason in reverse.
  static const String _noneValue = '__alaya_no_kind__';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final kinds = ref.watch(inventoryKindsProvider).valueOrNull;

    // Law U4's loading state. A dropdown built from an empty list would show only "New kind" for a frame and
    // then reflow, which reads as the app losing the kinds it has.
    if (kinds == null) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: label ?? strings.inventoryKindLabel,
        ),
        child: const SizedBox(
          height: AlayaIconSize.md,
          width: AlayaIconSize.md,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    // **Only an id the list actually contains is shown as selected.** A kind deleted while this form was open
    // would otherwise make the dropdown assert — it requires exactly one item matching its value.
    final selected = kinds.any((k) => k.id == kindTagId)
        ? kindTagId
        : _noneValue;

    return DropdownButtonFormField<String>(
      key: ValueKey(selected),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label ?? strings.inventoryKindLabel,
      ),
      // The closed field shows the name alone; the open menu adds a glyph. `selectedItemBuilder` must emit one
      // entry per `DropdownMenuItem`, in the same order — including the two sentinels, which is why this list
      // ends the same way the one below it does.
      selectedItemBuilder: (context) => [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            strings.inventoryKindNone,
            style: TextStyle(color: semantic.muted),
          ),
        ),
        for (final kind in kinds)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              kind.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(strings.inventoryKindNew),
        ),
      ],
      items: [
        DropdownMenuItem(
          value: _noneValue,
          child: Text(
            strings.inventoryKindNone,
            style: TextStyle(color: semantic.muted),
          ),
        ),
        for (final kind in kinds)
          DropdownMenuItem(
            value: kind.id,
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AlayaSpacing.xs,
              children: [
                Icon(
                  KindDisplay.glyphFor(kind),
                  size: AlayaIconSize.sm,
                  color: semantic.muted,
                ),
                Text(kind.name),
              ],
            ),
          ),
        DropdownMenuItem(
          value: _newValue,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AlayaSpacing.xs,
            children: [
              Icon(
                Icons.add,
                size: AlayaIconSize.sm,
                color: semantic.muted,
              ),
              Text(strings.inventoryKindNew),
            ],
          ),
        ),
      ],
      onChanged: (value) async {
        if (value == _noneValue) {
          onChanged(null);
          return;
        }
        if (value != _newValue) {
          onChanged(value);
          return;
        }
        // **The new kind is selected the moment it exists.** Creating one and then having to find it in the
        // list would be the same trip to Settings with extra steps.
        final created = await NewKindSheet.show(context);
        if (created != null) onChanged(created);
      },
    );
  }
}
