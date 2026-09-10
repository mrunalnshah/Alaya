import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:alaya/features/inventory/presentation/widgets/kind_picker.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/inventory/state/item_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_disclosure.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/qty_field.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';
import 'package:alaya/shared/widgets/unit_picker.dart';

/// The item editor (ARCH_5 §3 archetype B), routed outside the drawer shell (U18).
///
/// **`unitCategory` is a control while creating and a read-only row while editing.** Law L8 makes it
/// immutable after creation, and the row says why rather than leaving the user to discover that a
/// disabled dropdown exists: every batch and movement already recorded is stored in that measure, and
/// there is no conversion between weight, volume and count. Offering the control and then refusing
/// the change would be worse than not offering it.
class ItemEditorScreen extends ConsumerWidget {
  /// Edits [itemId], or creates a new item when it is null.
  const ItemEditorScreen({this.itemId, super.key});

  /// The item being edited, or null for a new one.
  final String? itemId;

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(itemEditorProvider(itemId).notifier).save();
    if (!context.mounted) return;
    if (saved == null) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.actionSaved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(itemEditorProvider(itemId));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(
          itemId == null ? strings.editorTitleNew : strings.editorTitleEdit,
        ),
      ),
      body: async.when(
        loading: () =>
            AlayaListSkeleton(label: strings.loadingLabel, hasLeading: false),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleNotFound,
          body: strings.errorBodyNotFound,
        ),
        data: (state) => AlayaFormScaffold(
          primaryLabel: strings.saveItem,
          onPrimary: state.submitting ? null : () => _save(context, ref),
          isDirty: state.dirty,
          isSubmitting: state.submitting,
          discardTitle: strings.confirmDiscardTitle,
          discardBody: strings.confirmDiscardBody,
          discardConfirmLabel: strings.actionDiscard,
          discardCancelLabel: strings.actionKeepEditing,
          child: _Form(editorId: itemId, state: state),
        ),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.editorId, required this.state});

  final String? editorId;
  final ItemEditorState state;

  static String _categoryLabel(AlayaStrings strings, UnitCategory category) =>
      switch (category) {
        UnitCategory.weight => strings.unitCategoryWeight,
        UnitCategory.volume => strings.unitCategoryVolume,
        UnitCategory.count => strings.unitCategoryCount,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(itemEditorProvider(editorId).notifier);
    final units =
        ref.watch(unitsInCategoryProvider(state.unitCategory)).valueOrNull ??
        const <Unit>[];
    Unit? selected;
    Unit? thresholdUnit;
    for (final unit in units) {
      if (unit.code == state.displayUnitCode) selected = unit;
      if (unit.code == state.thresholdUnitCode) thresholdUnit = unit;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.issue != null) ...[
          _IssueBanner(state: state),
          const SizedBox(height: AlayaSpacing.md),
        ],
        SectionHeader(
          label: strings.sectionWhatItIs,
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
        ),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: TextFormField(
            initialValue: state.name,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: strings.labelItem,
              errorText: state.nameMissing ? strings.errorFieldRequired : null,
            ),
            onChanged: notifier.setName,
            onEditingComplete: notifier.refreshSimilar,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        // **The picker with "New kind" in it**, rather than a dropdown over a closed enum. Six fixed options
        // became however many the user has, and adding one no longer means finding Settings.
        KindPicker(
          kindTagId: state.kindTagId,
          label: strings.labelItemKind,
          onChanged: notifier.setKind,
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (state.isEditing) ...[
          KeyValueRow(
            label: strings.labelCategory,
            value: strings.unitCategoryLocked(
              _categoryLabel(strings, state.unitCategory),
            ),
            icon: Icons.lock_outline,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AlayaSpacing.screenEdge,
            ),
            child: Text(
              strings.unitCategoryLockedHelp,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
          ),
        ] else
          DropdownButtonFormField<UnitCategory>(
            key: ValueKey(state.unitCategory),
            initialValue: state.unitCategory,
            isExpanded: true,
            decoration: InputDecoration(labelText: strings.labelCategory),
            items: [
              for (final category in UnitCategory.values)
                DropdownMenuItem(
                  value: category,
                  child: Text(_categoryLabel(strings, category)),
                ),
            ],
            onChanged: (value) => value == null
                ? null
                : notifier.setCategory(value, value.baseUnitCode),
          ),
        if (state.similarInOtherMeasures.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            strings.itemSimilarNote,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ],
        const SizedBox(height: AlayaSpacing.md),
        UnitPicker(
          category: state.unitCategory,
          units: units,
          selected: selected,
          label: strings.labelDisplayUnit,
          onChanged: notifier.setDisplayUnit,
        ),
        AlayaDisclosure(
          label: strings.sectionMoreDetails,
          summary: _itemSummary(strings, state),
          startExpanded: _hasItemDetails(state),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                label: strings.sectionStockRules,
                padding: const EdgeInsets.only(
                  top: AlayaSpacing.xl,
                  bottom: AlayaSpacing.xs,
                ),
              ),
              if (units.isNotEmpty)
                QtyField(
                  category: state.unitCategory,
                  units: units,
                  selectedUnit: thresholdUnit ?? selected ?? units.first,
                  label: strings.labelLowStockThreshold,
                  unitLabel: strings.labelUnit,
                  initialValue: state.lowStockThreshold,
                  onChanged: notifier.setThreshold,
                  onUnitChanged: notifier.setThresholdUnit,
                ),
              const SizedBox(height: AlayaSpacing.md),
              TextFormField(
                initialValue: state.expiryNotifyDays?.toString(),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: strings.labelExpiryNotifyDays,
                  helperText: strings.expiryNotifyDaysHelp,
                ),
                onChanged: (raw) =>
                    notifier.setExpiryNotifyDays(int.tryParse(raw.trim())),
              ),

              // Only for items measured by weight. The field converts a *volume* into grams, so on an item
              // already kept in millilitres there is nothing to convert and it would be noise.
              if (state.unitCategory == UnitCategory.weight) ...[
                SectionHeader(
                  label: strings.sectionRecipeMeasures,
                  padding: const EdgeInsets.only(
                    top: AlayaSpacing.xl,
                    bottom: AlayaSpacing.xs,
                  ),
                ),
                TextFormField(
                  // **Asked as "one tablespoon weighs", not "one millilitre weighs".** The column stores a
                  // density either way, but nobody can estimate the density of flour and everybody can look
                  // up that a tablespoon of it is about 8 g — which is how every cooking table is written.
                  //
                  // One number still covers every volume unit: 8 g/tbsp derives 2.7 g/tsp and 130 g/cup. A
                  // per-unit table would need three rows per ingredient and would let tsp and tbsp disagree
                  // about the same substance.
                  initialValue: _gramsPerTbspText(state.densityMilliGramsPerMl),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: strings.labelGramsPerTbsp,
                    helperText: strings.gramsPerTbspHelp,
                    suffixText: strings.suffixGrams,
                  ),
                  onChanged: (raw) =>
                      notifier.setDensity(_densityFromTbsp(raw)),
                ),
                const SizedBox(height: AlayaSpacing.md),
                TextFormField(
                  initialValue: _gramsText(state.milliGramsPerPiece),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: strings.labelPieceWeight,
                    helperText: strings.pieceWeightHelp,
                    suffixText: strings.suffixGrams,
                  ),
                  onChanged: (raw) => notifier.setPieceWeight(_milliGrams(raw)),
                ),
              ],
              const SizedBox(height: AlayaSpacing.xs),
              SwitchListTile(
                value: state.isFavorite,
                contentPadding: EdgeInsets.zero,
                title: Text(strings.labelFavourite),
                secondary: Icon(
                  state.isFavorite ? Icons.star : Icons.star_outline,
                  size: AlayaIconSize.md,
                  color: state.isFavorite ? semantic.warning : semantic.muted,
                ),
                onChanged: (_) => notifier.toggleFavourite(),
              ),
              SectionHeader(
                label: strings.labelNote,
                padding: const EdgeInsets.only(
                  top: AlayaSpacing.xl,
                  bottom: AlayaSpacing.xs,
                ),
              ),
              TextFormField(
                initialValue: state.notes,
                maxLines: 3,
                decoration: InputDecoration(hintText: strings.hintNote),
                onChanged: notifier.setNotes,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Whether anything behind the door is set, so it should open on arrival.
  ///
  /// **A recipe measure counts.** It is usually the reason somebody opened this screen at all — a recipe
  /// told them their spoon amount could not be converted — and collapsing the number they came here to
  /// set would be the worst possible moment to hide it.
  static bool _hasItemDetails(ItemEditorState state) =>
      state.lowStockThreshold != null ||
      state.expiryNotifyDays != null ||
      state.densityMilliGramsPerMl != null ||
      state.milliGramsPerPiece != null ||
      state.isFavorite ||
      (state.notes ?? '').trim().isNotEmpty;

  /// What is set behind the door, for the collapsed row.
  static String? _itemSummary(AlayaStrings strings, ItemEditorState state) {
    final parts = <String>[];
    if (state.lowStockThreshold != null) parts.add(strings.sectionStockRules);
    if (state.densityMilliGramsPerMl != null ||
        state.milliGramsPerPiece != null) {
      parts.add(strings.sectionRecipeMeasures);
    }
    if (state.isFavorite) parts.add(strings.labelFavourite);
    if ((state.notes ?? '').trim().isNotEmpty) parts.add(strings.labelNote);
    return parts.isEmpty ? null : parts.join(' \u00B7 ');
  }
}

class _IssueBanner extends ConsumerWidget {
  const _IssueBanner({required this.state});

  final ItemEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final conflictId = state.conflictItemId;

    final message = switch (state.issue) {
      ItemSaveIssue.duplicate => strings.itemDuplicateBody,
      ItemSaveIssue.unitsMissing => strings.itemUnitsMissingBody,
      ItemSaveIssue.unknown || null => strings.errorBodyGeneric,
    };

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: AlayaIconSize.md,
            color: semantic.danger,
          ),
          const SizedBox(width: AlayaSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: AlayaTypography.body.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                // The duplicate case is the only one with somewhere useful to go: the item they
                // already have. Offering to open it beats making them back out and search for it.
                if (state.issue == ItemSaveIssue.duplicate &&
                    conflictId != null) ...[
                  const SizedBox(height: AlayaSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => context.pushReplacement(
                        Routes.itemDetail(conflictId),
                      ),
                      child: Text(strings.actionOpenExisting),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One tablespoon in milli-millilitres, matching the seeded `tbsp` unit's `factorToBaseMilli`.
///
/// Duplicated from the seed deliberately: this file cannot read the units table synchronously while
/// building a text field, and a field that silently disagreed with the unit picker would be worse than
/// a constant with a comment saying where it came from.
const int _tbspMilliMl = 14787;

/// Renders a stored density as the grams-per-tablespoon a person typed.
///
/// `541` shows as `8`, because 541 milli-grams per millilitre times 14.787 ml is 8.00 g. A field that
/// reads back what you entered is the minimum for trusting it.
String? _gramsPerTbspText(int? milliGramsPerMl) {
  if (milliGramsPerMl == null) return null;
  return _gramsText(milliGramsPerMl * _tbspMilliMl ~/ 1000);
}

/// Parses typed grams-per-tablespoon into a stored density, or null for anything unusable.
int? _densityFromTbsp(String raw) {
  final milliGrams = _milliGrams(raw);
  if (milliGrams == null) return null;
  // Multiply before dividing so the integer arithmetic keeps its precision (Law L1).
  return milliGrams * 1000 ~/ _tbspMilliMl;
}

/// Renders milli-grams as the grams a person typed, or null for an empty field.
String? _gramsText(int? milliGrams) {
  if (milliGrams == null) return null;
  if (milliGrams % 1000 == 0) return '${milliGrams ~/ 1000}';
  return (milliGrams / 1000).toString();
}

/// Parses typed grams into milli-grams, or null for anything unusable.
///
/// Integer arithmetic on the decimal string rather than `double.parse`: `0.1` has no exact binary
/// representation, and Law L1 keeps quantities exact end to end. An empty or malformed field returns
/// null, which is a real state — it clears the value rather than storing a zero that would claim a
/// tablespoon of this weighs nothing.
int? _milliGrams(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final parts = text.split('.');
  if (parts.length > 2) return null;
  final whole = int.tryParse(parts.first.isEmpty ? '0' : parts.first);
  if (whole == null) return null;
  if (parts.length == 1) return whole * 1000;
  if (parts[1].length > 3) return null;
  final fraction = int.tryParse(parts[1].padRight(3, '0'));
  if (fraction == null) return null;
  return whole * 1000 + fraction;
}
