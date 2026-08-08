import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/service/presentation/screens/asset_list_screen.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/state/asset_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// Records an asset — or a person (ARCH_5 §3 archetype B), outside the shell per U18.
///
/// **Only the name is required, and that is what makes `type = serviceProvider` work.** A house maid has
/// no serial number, no warranty and no purchase price; a television has no phone number worth calling.
/// Both live in one table because every field except the name is optional, so neither has to be
/// described in the other's vocabulary.
class AssetEditorScreen extends ConsumerWidget {
  /// Edits [assetId], or creates a new asset when it is null.
  const AssetEditorScreen({this.assetId, super.key});

  /// The asset being edited, or null for a new one.
  final String? assetId;

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(assetEditorProvider(assetId).notifier).save();
    if (!context.mounted) return;
    if (saved == null) {
      final state = ref.read(assetEditorProvider(assetId)).valueOrNull;
      showFailureSnack(
        context,
        message:
            state?.rejection ??
            switch (state?.issue) {
              AssetSaveIssue.nameMissing => strings.errorFieldRequired,
              AssetSaveIssue.warrantyBackwards =>
                strings.errorWarrantyBackwards,
              AssetSaveIssue.rejected || null => strings.errorBodyGeneric,
            },
      );
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.actionSaved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(assetEditorProvider(assetId));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(
          assetId == null ? strings.editorTitleNew : strings.editorTitleEdit,
        ),
      ),
      body: async.when(
        loading: () =>
            AlayaListSkeleton(label: strings.loadingAssets, hasLeading: false),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleNotFound,
          body: strings.errorBodyNotFound,
        ),
        data: (state) => AlayaFormScaffold(
          primaryLabel: strings.saveAsset,
          onPrimary: state.submitting ? null : () => _save(context, ref),
          isDirty: state.dirty,
          isSubmitting: state.submitting,
          discardTitle: strings.confirmDiscardTitle,
          discardBody: strings.confirmDiscardBody,
          discardConfirmLabel: strings.actionDiscard,
          discardCancelLabel: strings.actionKeepEditing,
          child: _Form(editorId: assetId, state: state),
        ),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.editorId, required this.state});

  final String? editorId;
  final AssetEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(assetEditorProvider(editorId).notifier);
    final digits = ref.watch(serviceDecimalDigitsProvider).valueOrNull ?? 2;
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) =>
        DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: strings.assetSectionIdentity,
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
        ),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: TextFormField(
            initialValue: state.name,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: strings.labelAssetName,
              errorText: state.issue == AssetSaveIssue.nameMissing
                  ? strings.errorFieldRequired
                  : null,
            ),
            onChanged: notifier.setName,
          ),
        ),
        // Informational, never a block. A repeated name is normal — but saying nothing would leave a
        // genuine slip, the same phone entered twice, invisible.
        if (ref.watch(
          assetNameClashProvider((id: state.id, name: state.name)),
        )) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            strings.assetSameNameNote,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ],
        const SizedBox(height: AlayaSpacing.md),
        DropdownButtonFormField<AssetType>(
          key: ValueKey(state.type),
          initialValue: state.type,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.labelAssetType),
          items: [
            for (final type in AssetType.values)
              DropdownMenuItem(
                value: type,
                child: Text(AssetListScreen.typeLabel(strings, type)),
              ),
          ],
          onChanged: (value) => value == null ? null : notifier.setType(value),
        ),
        if (state.isPerson) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            strings.assetTypeHelpPerson,
            style: AlayaTypography.caption.copyWith(color: semantic.transfer),
          ),
        ],
        // A person has no brand, model or serial, so those fields are not offered at all rather than
        // offered and left blank — an empty "Model" on a human being is worse than its absence.
        if (!state.isPerson) ...[
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.brand,
            decoration: InputDecoration(labelText: strings.labelBrand),
            onChanged: notifier.setBrand,
          ),
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.modelNo,
            decoration: InputDecoration(labelText: strings.labelModelNo),
            onChanged: notifier.setModelNo,
          ),
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.serialNo,
            decoration: InputDecoration(labelText: strings.labelSerialNo),
            onChanged: notifier.setSerialNo,
          ),
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.location,
            decoration: InputDecoration(labelText: strings.labelLocation),
            onChanged: notifier.setLocation,
          ),
          const SizedBox(height: AlayaSpacing.md),
          DatePickerField(
            value: state.purchaseDateKey,
            formatted: format,
            label: strings.labelPurchased,
            hint: strings.hintSelectDate,
            onChanged: notifier.setPurchaseDate,
          ),
          const SizedBox(height: AlayaSpacing.md),
          AmountField(
            currencyCode: state.currencyCode,
            decimalDigits: digits,
            label: strings.labelPurchasePrice,
            initialValue: state.purchasePrice,
            onChanged: notifier.setPurchasePrice,
          ),
          SectionHeader(
            label: strings.assetSectionWarranty,
            padding: const EdgeInsets.only(
              top: AlayaSpacing.xl,
              bottom: AlayaSpacing.xs,
            ),
          ),
          DatePickerField(
            value: state.warrantyStartDateKey,
            formatted: format,
            label: strings.labelWarrantyStart,
            hint: strings.hintSelectDate,
            onChanged: notifier.setWarrantyStart,
          ),
          const SizedBox(height: AlayaSpacing.md),
          DatePickerField(
            value: state.warrantyEndDateKey,
            formatted: format,
            label: strings.labelWarrantyEnd,
            hint: strings.hintSelectDate,
            errorText: state.issue == AssetSaveIssue.warrantyBackwards
                ? strings.errorWarrantyBackwards
                : null,
            onChanged: notifier.setWarrantyEnd,
          ),
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.warrantyProvider,
            decoration: InputDecoration(
              labelText: strings.labelWarrantyProvider,
            ),
            onChanged: notifier.setWarrantyProvider,
          ),
        ],
        SectionHeader(
          label: strings.assetSectionService,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.xl,
            bottom: AlayaSpacing.xs,
          ),
        ),
        TextFormField(
          initialValue: state.serviceIntervalDays?.toString(),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: strings.labelServiceInterval,
            helperText: strings.serviceIntervalHelp,
            helperMaxLines: 3,
          ),
          onChanged: (raw) =>
              notifier.setServiceIntervalDays(int.tryParse(raw.trim())),
        ),
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.nextServiceDueDateKey,
          formatted: format,
          label: strings.labelNextService,
          hint: strings.hintSelectDate,
          onChanged: notifier.setNextServiceDue,
        ),
        SectionHeader(
          label: strings.assetSectionContact,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.xl,
            bottom: AlayaSpacing.xs,
          ),
        ),
        TextFormField(
          initialValue: state.contactName,
          decoration: InputDecoration(labelText: strings.labelContactName),
          onChanged: notifier.setContactName,
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextFormField(
          initialValue: state.contactPhone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: strings.labelContactPhone),
          onChanged: notifier.setContactPhone,
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
        if (state.issue == AssetSaveIssue.rejected &&
            state.rejection != null) ...[
          const SizedBox(height: AlayaSpacing.md),
          AlayaCard(
            padding: const EdgeInsets.all(AlayaSpacing.sm),
            child: Text(
              state.rejection!,
              style: AlayaTypography.body.copyWith(color: semantic.danger),
            ),
          ),
        ],
      ],
    );
  }
}
