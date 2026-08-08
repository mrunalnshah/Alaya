import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/providers/batch_editor_providers.dart';
import 'package:alaya/features/inventory/providers/item_detail_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/inventory/state/batch_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/qty_field.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// The batch editor (ARCH_5 §3 archetype B), routed outside the drawer shell (U18).
///
/// **Quantity is a field while creating and a read-only row while editing.** `remainingQuantity` is
/// the one cache the Laws permit (L3), reconciled from `stock_movements`; rewriting it from a form
/// would leave the cache and the ledger disagreeing with no movement to account for the difference.
/// Changing how much is left goes through the consume and adjust paths, which append movements.
class BatchEditorScreen extends ConsumerWidget {
  /// Edits [batchId] of [itemId], or adds a batch when [batchId] is null.
  const BatchEditorScreen({required this.itemId, this.batchId, super.key});

  /// Which item the batch belongs to.
  final String itemId;

  /// The batch being edited, or null for a new one.
  final String? batchId;

  BatchEditorArgs get _args => (itemId: itemId, batchId: batchId);

  Future<void> _delete(BuildContext context, WidgetRef ref, String id) async {
    final strings = AlayaStrings.of(context);
    // Consequential, not reversible (§5.5): `BatchRepository.delete` soft-deletes and the 3A
    // contract offers no restore, so the sheet names what leaves the on-hand total — and what does
    // not, because the movements stay (Law L6).
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.confirmDeleteBatchTitle,
      body: strings.confirmDeleteBatchBody,
      confirmLabel: strings.actionDeleteBatch,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await ref.read(itemActionsProvider).deleteBatch(id);
    if (!context.mounted) return;
    if (!ok) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.batchDeleted);
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(batchEditorProvider(_args).notifier).save();
    if (!context.mounted) return;
    if (saved == null) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.batchSaved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(batchEditorProvider(_args));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(
          batchId == null ? strings.actionAddBatch : strings.editorTitleEdit,
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
          primaryLabel: strings.saveBatch,
          onPrimary: state.submitting ? null : () => _save(context, ref),
          isDirty: state.dirty,
          isSubmitting: state.submitting,
          discardTitle: strings.confirmDiscardTitle,
          discardBody: strings.confirmDiscardBody,
          discardConfirmLabel: strings.actionDiscard,
          discardCancelLabel: strings.actionKeepEditing,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Form(args: _args, state: state),
              if (state.isEditing) ...[
                const SizedBox(height: AlayaSpacing.xxl),
                TextButton(
                  onPressed: () => _delete(context, ref, state.id!),
                  style: TextButton.styleFrom(
                    foregroundColor: context.semantic.danger,
                  ),
                  child: Text(strings.actionDeleteBatch),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.args, required this.state});

  final BatchEditorArgs args;
  final BatchEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(batchEditorProvider(args).notifier);
    final item = ref.watch(batchOwnerProvider(state.itemId)).valueOrNull;
    final currency = ref.watch(batchCurrencyProvider).valueOrNull;
    final digits = ref.watch(batchDecimalDigitsProvider).valueOrNull ?? 2;
    final units = item == null
        ? const <Unit>[]
        : ref.watch(unitsInCategoryProvider(item.unitCategory)).valueOrNull ??
              const <Unit>[];
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) =>
        DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());

    Unit? selected;
    for (final unit in units) {
      if (unit.code == state.unitCode) selected = unit;
    }
    final quantity = state.quantity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: strings.sectionHowMuch,
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
        ),
        if (!state.quantityEditable)
          KeyValueRow(
            label: strings.labelInitial,
            valueWidget: quantity == null ? null : QtyText(quantity),
            icon: Icons.lock_outline,
          )
        else if (item != null && units.isNotEmpty)
          ShakeOnError(
            trigger: state.shakeTrigger,
            child: QtyField(
              category: item.unitCategory,
              units: units,
              selectedUnit: selected ?? units.first,
              label: strings.labelQuantity,
              unitLabel: strings.labelUnit,
              initialValue: quantity,
              errorText: state.quantityMissing
                  ? strings.errorQuantityInvalid
                  : null,
              onChanged: notifier.setQuantity,
              onUnitChanged: (unit) => notifier.setUnitCode(unit.code),
            ),
          ),
        if (!state.quantityEditable)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AlayaSpacing.screenEdge,
            ),
            child: Text(
              strings.batchQuantityLockedHelp,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
          ),
        SectionHeader(
          label: strings.sectionBatchDetails,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.xl,
            bottom: AlayaSpacing.xs,
          ),
        ),
        DatePickerField(
          value: state.purchasedDateKey,
          formatted: format,
          label: strings.labelPurchased,
          hint: strings.hintSelectDate,
          onChanged: notifier.setPurchased,
        ),
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.expiryDateKey,
          formatted: format,
          label: strings.labelExpiry,
          hint: strings.hintSelectDate,
          onChanged: notifier.setExpiry,
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (currency != null)
          AmountField(
            currencyCode: currency,
            decimalDigits: digits,
            label: strings.labelUnitCost,
            initialValue: state.unitCost,
            onChanged: notifier.setUnitCost,
          ),
        const SizedBox(height: AlayaSpacing.md),
        TextFormField(
          initialValue: state.storageLocation,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: strings.labelStorageLocation,
            hintText: strings.hintStorageLocation,
          ),
          onChanged: notifier.setStorageLocation,
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextFormField(
          initialValue: state.note,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: strings.labelNote,
            hintText: strings.hintNote,
          ),
          onChanged: notifier.setNote,
        ),
      ],
    );
  }
}
