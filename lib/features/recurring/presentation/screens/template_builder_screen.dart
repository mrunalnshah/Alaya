import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/features/recurring/state/template_builder_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/frequency_preview.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// Builds a recurring template (ARCH_5 §3 archetype B), outside the drawer shell (U18).
///
/// **The preview is the point of the screen.** `anchorDayOfMonth` is stored once and clamped at every
/// render, so a bill anchored on the 31st lands Jan 31 → Feb 28 → Mar 31 (anomaly A13). Nothing about
/// typing 31 tells the user that; seeing February shortened and March return does. It updates on every
/// change to the frequency, which is why it sits directly under the fields that drive it rather than at
/// the bottom of the form.
class TemplateBuilderScreen extends ConsumerWidget {
  /// Edits [templateId], or creates a new template when it is null.
  const TemplateBuilderScreen({this.templateId, super.key});

  /// The template being edited, or null for a new one.
  final String? templateId;

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref
        .read(templateBuilderProvider(templateId).notifier)
        .save();
    if (!context.mounted) return;
    if (saved == null) {
      // The reason, not a stand-in for it. The builder has three ways to be incomplete and one way to
      // be rejected, and a single generic message distinguishes none of them (Law U9).
      final state = ref.read(templateBuilderProvider(templateId)).valueOrNull;
      showFailureSnack(
        context,
        message: state?.rejection ?? _issueMessage(strings, state?.issue),
      );
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.actionSaved);
  }

  static String _issueMessage(AlayaStrings strings, TemplateSaveIssue? issue) =>
      switch (issue) {
        TemplateSaveIssue.nameMissing => strings.errorFieldRequired,
        TemplateSaveIssue.amountMissing => strings.errorAmountInvalid,
        TemplateSaveIssue.anchorMissing => strings.anchorDayHelp,
        TemplateSaveIssue.rejected || null => strings.errorBodyGeneric,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(templateBuilderProvider(templateId));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(
          templateId == null ? strings.editorTitleNew : strings.editorTitleEdit,
        ),
      ),
      body: async.when(
        loading: () => AlayaListSkeleton(
          label: strings.loadingRecurring,
          hasLeading: false,
        ),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleNotFound,
          body: strings.errorBodyNotFound,
        ),
        data: (state) => AlayaFormScaffold(
          primaryLabel: strings.saveTemplate,
          onPrimary: state.submitting ? null : () => _save(context, ref),
          isDirty: state.dirty,
          isSubmitting: state.submitting,
          discardTitle: strings.confirmDiscardTitle,
          discardBody: strings.confirmDiscardBody,
          discardConfirmLabel: strings.actionDiscard,
          discardCancelLabel: strings.actionKeepEditing,
          child: _Form(editorId: templateId, state: state),
        ),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.editorId, required this.state});

  final String? editorId;
  final TemplateBuilderState state;

  static String _kindLabel(AlayaStrings strings, RecurringKind kind) =>
      switch (kind) {
        RecurringKind.bill => strings.kindBill,
        RecurringKind.subscription => strings.kindSubscription,
        RecurringKind.rent => strings.kindRent,
        RecurringKind.salary => strings.kindSalary,
        RecurringKind.serviceFee => strings.kindServiceFee,
        RecurringKind.other => strings.kindOther,
      };

  static String _unitLabel(
    AlayaStrings strings,
    RecurringIntervalUnit unit,
    int count,
  ) => switch (unit) {
    RecurringIntervalUnit.day => strings.unitDay(count),
    RecurringIntervalUnit.week => strings.unitWeek(count),
    RecurringIntervalUnit.month => strings.unitMonth(count),
    RecurringIntervalUnit.year => strings.unitYear(count),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(templateBuilderProvider(editorId).notifier);
    final digits = ref.watch(builderDecimalDigitsProvider).valueOrNull ?? 2;
    final accounts =
        ref.watch(builderAccountsProvider).valueOrNull ?? const <Account>[];
    final dates = ref.watch(previewProvider(editorId));
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) =>
        DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());

    // The dropdown's value comes from the list being rendered, never from state: the accounts arrive
    // from a stream, and a value matching none of the items throws (ARCH_4 R33).
    Account? selectedAccount;
    for (final account in accounts) {
      if (account.id == state.accountId) selectedAccount = account;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: strings.builderSectionWhat,
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
        ),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: TextFormField(
            initialValue: state.name,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: strings.labelTemplateName,
              errorText: state.issue == TemplateSaveIssue.nameMissing
                  ? strings.errorFieldRequired
                  : null,
            ),
            onChanged: notifier.setName,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        DropdownButtonFormField<RecurringKind>(
          key: ValueKey(state.kind),
          initialValue: state.kind,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.labelRecurringKind),
          items: [
            for (final kind in RecurringKind.values)
              DropdownMenuItem(
                value: kind,
                child: Text(_kindLabel(strings, kind)),
              ),
          ],
          onChanged: (value) => value == null ? null : notifier.setKind(value),
        ),
        const SizedBox(height: AlayaSpacing.md),
        SegmentedButton<RecurringDirection>(
          segments: [
            ButtonSegment(
              value: RecurringDirection.outflow,
              label: Text(strings.directionOutflow),
            ),
            ButtonSegment(
              value: RecurringDirection.inflow,
              label: Text(strings.directionInflow),
            ),
          ],
          selected: {state.direction},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              notifier.setDirection(selection.first),
        ),
        SectionHeader(
          label: strings.builderSectionWhen,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.xl,
            bottom: AlayaSpacing.xs,
          ),
        ),
        // `Wrap`, not `Row`: the count field, the unit dropdown and their label all grow with text
        // scale, and at 320dp a Row starves whichever comes first (Law U21).
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              strings.labelEvery,
              style: AlayaTypography.label.copyWith(color: semantic.muted),
            ),
            // Not `isDense`: it takes the field to 46px, under the 48dp tap-target floor (Law U16).
            // A `ConstrainedBox` keeps the field narrow without shrinking what a finger has to hit.
            ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: AlayaSpacing.xxxl * 2,
                maxWidth: AlayaSpacing.xxxl * 2,
                minHeight: AlayaSpacing.minTapTarget,
              ),
              child: TextFormField(
                initialValue: '${state.intervalCount}',
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                onChanged: (raw) =>
                    notifier.setIntervalCount(int.tryParse(raw.trim()) ?? 1),
              ),
            ),
            DropdownButton<RecurringIntervalUnit>(
              value: state.intervalUnit,
              items: [
                for (final unit in RecurringIntervalUnit.values)
                  DropdownMenuItem(
                    value: unit,
                    child: Text(_unitLabel(strings, unit, state.intervalCount)),
                  ),
              ],
              onChanged: (value) =>
                  value == null ? null : notifier.setIntervalUnit(value),
            ),
          ],
        ),
        if (state.needsDayAnchor) ...[
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.anchorDayOfMonth?.toString(),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: strings.labelAnchorDay,
              helperText: strings.anchorDayHelp,
              helperMaxLines: 4,
              errorText: state.issue == TemplateSaveIssue.anchorMissing
                  ? strings.errorFieldRequired
                  : null,
            ),
            onChanged: (raw) => notifier.setAnchorDay(int.tryParse(raw.trim())),
          ),
        ],
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.startDateKey,
          formatted: format,
          label: strings.labelStartDate,
          hint: strings.hintSelectDate,
          onChanged: notifier.setStartDate,
        ),
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.endDateKey,
          formatted: format,
          label: strings.labelEndDate,
          hint: strings.hintSelectDate,
          onChanged: notifier.setEndDate,
        ),
        const SizedBox(height: AlayaSpacing.md),
        FrequencyPreview(dates: dates),
        SectionHeader(
          label: strings.builderSectionDefaults,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.xl,
            bottom: AlayaSpacing.xs,
          ),
        ),
        AmountField(
          currencyCode: state.currencyCode,
          decimalDigits: digits,
          label: strings.labelDefaultAmount,
          initialValue: state.amount,
          errorText: state.issue == TemplateSaveIssue.amountMissing
              ? strings.errorAmountInvalid
              : null,
          onChanged: notifier.setAmount,
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (accounts.isNotEmpty)
          DropdownButtonFormField<String>(
            key: ValueKey(selectedAccount?.id),
            initialValue: selectedAccount?.id,
            isExpanded: true,
            decoration: InputDecoration(labelText: strings.labelAccount),
            items: [
              for (final account in accounts)
                DropdownMenuItem(value: account.id, child: Text(account.name)),
            ],
            onChanged: notifier.setAccount,
          ),
        const SizedBox(height: AlayaSpacing.md),
        SwitchListTile(
          value: state.autoRemind,
          contentPadding: EdgeInsets.zero,
          title: Text(strings.labelRemindBefore),
          secondary: Icon(
            state.autoRemind
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            size: AlayaIconSize.md,
            color: semantic.muted,
          ),
          onChanged: (_) => notifier.toggleRemind(),
        ),
        if (state.autoRemind)
          TextFormField(
            initialValue: '${state.remindDaysBefore}',
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: strings.labelRemindBefore),
            onChanged: (raw) =>
                notifier.setRemindDaysBefore(int.tryParse(raw.trim()) ?? 0),
          ),
        SectionHeader(
          label: strings.labelNote,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.xl,
            bottom: AlayaSpacing.xs,
          ),
        ),
        TextFormField(
          initialValue: state.note,
          maxLines: 3,
          decoration: InputDecoration(hintText: strings.hintNote),
          onChanged: notifier.setNote,
        ),
        if (state.issue == TemplateSaveIssue.rejected &&
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
