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
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/features/service/presentation/screens/asset_detail_screen.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/service_editor_providers.dart';
import 'package:alaya/features/service/state/service_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// Records what was done to a thing, or what was paid to a person (archetype B, outside the shell).
///
/// **`type = salaryPaid` is what puts a maid's wages in the same table as a boiler service.** The maid
/// case needs no new screen: her asset row, this editor and the "also record as an expense" toggle are
/// the three pieces, and the salary history on her detail screen is this table filtered by type.
class ServiceEditorScreen extends ConsumerWidget {
  /// Edits [recordId] against [assetId], or creates a new record when it is null.
  const ServiceEditorScreen({required this.assetId, this.recordId, super.key});

  /// Which asset the record belongs to.
  final String assetId;

  /// The record being edited, or null for a new one.
  final String? recordId;

  ServiceEditorArgs get _args => (assetId: assetId, recordId: recordId);

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(serviceEditorProvider(_args).notifier).save();
    if (!context.mounted) return;
    if (saved == null) {
      final state = ref.read(serviceEditorProvider(_args)).valueOrNull;
      showFailureSnack(
        context,
        message:
            state?.rejection ??
            switch (state?.issue) {
              ServiceSaveIssue.costMissingForExpense =>
                strings.alsoRecordNeedsCost,
              ServiceSaveIssue.accountMissingForExpense =>
                strings.alsoRecordNeedsAccount,
              ServiceSaveIssue.rejected || null => strings.errorBodyGeneric,
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
    final async = ref.watch(serviceEditorProvider(_args));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(
          recordId == null ? strings.editorTitleNew : strings.editorTitleEdit,
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
          primaryLabel: strings.saveService,
          onPrimary: state.submitting ? null : () => _save(context, ref),
          isDirty: state.dirty,
          isSubmitting: state.submitting,
          discardTitle: strings.confirmDiscardTitle,
          discardBody: strings.confirmDiscardBody,
          discardConfirmLabel: strings.actionDiscard,
          discardCancelLabel: strings.actionKeepEditing,
          child: _Form(args: _args, state: state),
        ),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.args, required this.state});

  final ServiceEditorArgs args;
  final ServiceEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(serviceEditorProvider(args).notifier);
    final digits = ref.watch(serviceDecimalDigitsProvider).valueOrNull ?? 2;
    final accounts =
        ref.watch(serviceAccountsProvider).valueOrNull ?? const <Account>[];
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) =>
        DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());

    // The dropdown's value comes from the list being rendered, never from state: the accounts arrive
    // from a stream, and a value matching none of the items throws (ARCH_4 R33).
    Account? selectedAccount;
    for (final account in accounts) {
      if (account.id == state.accountId) selectedAccount = account;
    }
    final methods =
        ref.watch(servicePaymentMethodsProvider).valueOrNull ??
        const <PaymentMethod>[];
    PaymentMethod? selectedMethod;
    for (final method in methods) {
      if (method.id == state.paymentMethodId) selectedMethod = method;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<ServiceRecordType>(
          key: ValueKey(state.type),
          initialValue: state.type,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.labelServiceType),
          items: [
            for (final type in ServiceRecordType.values)
              DropdownMenuItem(
                value: type,
                child: Text(ServiceTypeLabels.of(strings, type)),
              ),
          ],
          onChanged: (value) => value == null ? null : notifier.setType(value),
        ),
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.serviceDateKey,
          formatted: format,
          label: strings.labelServiceDate,
          hint: strings.hintSelectDate,
          onChanged: notifier.setServiceDate,
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextFormField(
          initialValue: state.providerName,
          decoration: InputDecoration(labelText: strings.labelProviderName),
          onChanged: notifier.setProviderName,
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextFormField(
          initialValue: state.providerPhone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: strings.labelProviderPhone),
          onChanged: notifier.setProviderPhone,
        ),
        const SizedBox(height: AlayaSpacing.md),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: AmountField(
            currencyCode: state.currencyCode,
            decimalDigits: digits,
            label: strings.labelServiceCost,
            initialValue: state.cost,
            errorText: state.issue == ServiceSaveIssue.costMissingForExpense
                ? strings.alsoRecordNeedsCost
                : null,
            onChanged: notifier.setCost,
          ),
        ),
        // Not offered for a salary: the next payment is the recurring template's business, and a second
        // due date here would be a second schedule to keep in step.
        if (!state.isSalary) ...[
          const SizedBox(height: AlayaSpacing.md),
          DatePickerField(
            value: state.nextDueDateKey,
            formatted: format,
            label: strings.labelNextDue,
            hint: strings.hintSelectDate,
            onChanged: notifier.setNextDue,
          ),
        ],
        SectionHeader(
          label: strings.sectionMoney,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.xl,
            bottom: AlayaSpacing.xs,
          ),
        ),
        SwitchListTile(
          value: state.alsoRecordAsExpense,
          contentPadding: EdgeInsets.zero,
          title: Text(strings.alsoRecordAsExpense),
          subtitle: Text(
            strings.alsoRecordHelp,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          onChanged: (_) => notifier.toggleExpense(),
        ),
        if (state.alsoRecordAsExpense) ...[
          const SizedBox(height: AlayaSpacing.md),
          if (accounts.isNotEmpty)
            DropdownButtonFormField<String>(
              key: ValueKey(selectedAccount?.id),
              initialValue: selectedAccount?.id,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: strings.labelAccount,
                errorText:
                    state.issue == ServiceSaveIssue.accountMissingForExpense
                    ? strings.alsoRecordNeedsAccount
                    : null,
              ),
              items: [
                for (final account in accounts)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(account.name),
                  ),
              ],
              onChanged: notifier.setAccount,
            ),
          // Optional, and last: an account says where the money came from and the expense needs it; a
          // method says how, and plenty of people never record it. Offered only when methods exist, so
          // an empty picker never appears.
          if (methods.isNotEmpty) ...[
            const SizedBox(height: AlayaSpacing.md),
            DropdownButtonFormField<String>(
              key: ValueKey(selectedMethod?.id),
              initialValue: selectedMethod?.id,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: strings.labelPaymentMethodOptional,
              ),
              items: [
                for (final method in methods)
                  DropdownMenuItem(value: method.id, child: Text(method.name)),
              ],
              onChanged: notifier.setPaymentMethod,
            ),
          ],
        ],
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
        if (state.issue == ServiceSaveIssue.rejected &&
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
