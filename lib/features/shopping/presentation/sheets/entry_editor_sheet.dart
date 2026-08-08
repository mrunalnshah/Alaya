import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/state/entry_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/qty_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// Adds or edits one shopping entry (ARCH_5 §3 archetype A).
///
/// **Free text is the primary field and the item link is optional.** A television belongs on a
/// shopping list and has no place in an inventory that measures flour by the gram, so `itemId` stays
/// nullable and an entry needs only one of the two to identify itself.
///
/// A quantity is offered only once an item is linked, for the same reason as the line editor in 6A:
/// a `Qty` is an integer plus a `UnitCategory`, and the category comes from the item (Law L8).
class EntryEditorSheet extends ConsumerWidget {
  /// Creates the sheet.
  const EntryEditorSheet({required this.listId, this.entryId, super.key});

  /// Which list the entry belongs to.
  final String listId;

  /// The entry being edited, or null for a new one.
  final String? entryId;

  /// Opens the sheet.
  static Future<void> show(
    BuildContext context, {
    required String listId,
    String? entryId,
  }) => AlayaBottomSheet.show<void>(
    context: context,
    builder: (context) => EntryEditorSheet(listId: listId, entryId: entryId),
  );

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    EntryEditorArgs args,
  ) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(entryEditorProvider(args).notifier).save();
    if (!context.mounted) return;
    if (saved == null) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    Navigator.of(context).pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.actionSaved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final args = (listId: listId, entryId: entryId);
    final async = ref.watch(entryEditorProvider(args));

    return async.when(
      loading: () => AlayaListSkeleton(label: strings.loadingShopping, rows: 3),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleNotFound,
        body: strings.errorBodyNotFound,
      ),
      data: (state) => _Form(
        args: args,
        state: state,
        onSave: () => _save(context, ref, args),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.args, required this.state, required this.onSave});

  final EntryEditorArgs args;
  final EntryEditorState state;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(entryEditorProvider(args).notifier);
    final items = ref.watch(entryItemsProvider).valueOrNull ?? const <Item>[];
    final tags = ref.watch(entryTagsProvider).valueOrNull ?? const <Tag>[];
    final currency = ref.watch(entryCurrencyProvider).valueOrNull;
    final digits = ref.watch(entryDecimalDigitsProvider).valueOrNull ?? 2;

    Item? linked;
    for (final item in items) {
      if (item.id == state.itemId) linked = item;
    }
    final units =
        ref.watch(entryUnitsProvider(linked?.unitCategory)).valueOrNull ??
        const <Unit>[];
    Unit? selectedUnit;
    for (final unit in units) {
      if (unit.code == state.unitCode) selectedUnit = unit;
    }
    selectedUnit ??= units.isEmpty ? null : units.first;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.entryEditorTitle,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: TextFormField(
            initialValue: state.freeText,
            autofocus: !state.isEditing,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: strings.entryFreeTextLabel,
              hintText: strings.entryFreeTextHint,
              errorText: state.identityMissing
                  ? strings.entryNeedsSomething
                  : null,
            ),
            onChanged: notifier.setFreeText,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        DropdownButtonFormField<String?>(
          // **`linked?.id`, not `state.itemId`.** The items arrive from a stream, so on the first
          // frame the list is empty while the state already names an item — and a dropdown whose
          // value matches none of its items throws "There should be exactly one item". Deriving the
          // value from the list that is actually rendered makes that unrepresentable.
          key: ValueKey(linked?.id),
          initialValue: linked?.id,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.entryLinkItem),
          items: [
            DropdownMenuItem<String?>(child: Text(strings.entryNoItem)),
            for (final item in items)
              DropdownMenuItem<String?>(
                value: item.id,
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value == null) {
              notifier.setItem(null);
              return;
            }
            for (final item in items) {
              if (item.id == value) notifier.setItem(item);
            }
          },
        ),
        if (linked != null && units.isNotEmpty && selectedUnit != null) ...[
          const SizedBox(height: AlayaSpacing.md),
          QtyField(
            key: ValueKey('${linked.id}:${selectedUnit.code}'),
            category: linked.unitCategory,
            units: units,
            selectedUnit: selectedUnit,
            label: strings.labelQuantity,
            unitLabel: strings.labelUnit,
            initialValue: state.quantity,
            onChanged: notifier.setQuantity,
            onUnitChanged: (unit) => notifier.setUnitCode(unit.code),
          ),
        ],
        if (currency != null) ...[
          const SizedBox(height: AlayaSpacing.md),
          AmountField(
            currencyCode: currency,
            decimalDigits: digits,
            label: strings.labelEstimatedPrice,
            initialValue: state.estimatedPrice,
            onChanged: notifier.setEstimatedPrice,
          ),
        ],
        if (tags.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.md),
          Text(
            strings.labelTags,
            style: AlayaTypography.label.copyWith(color: semantic.muted),
          ),
          const SizedBox(height: AlayaSpacing.xs),
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              for (final tag in tags)
                TagChip(
                  tag: tag,
                  selected: state.tagId == tag.id,
                  onTap: () =>
                      notifier.setTag(state.tagId == tag.id ? null : tag.id),
                ),
            ],
          ),
        ],
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: state.submitting ? null : onSave,
          child: Text(strings.actionSave),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.actionCancel),
        ),
      ],
    );
  }
}
