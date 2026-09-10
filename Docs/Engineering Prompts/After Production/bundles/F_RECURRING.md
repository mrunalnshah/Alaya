# F_RECURRING

Recurring templates and occurrences.

**19 files · 3,518 lines.**  Written 2026-08-27T08:54:37-04:00.

Every file below is complete and current. Paths are destinations.

---

### `lib/features/recurring/presentation/screens/occurrence_history_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/features/recurring/presentation/sheets/pay_sheet.dart';
import 'package:alaya/features/recurring/providers/occurrence_history_providers.dart';
import 'package:alaya/features/recurring/providers/pay_providers.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/features/recurring/providers/template_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_timeline.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

/// One template's occurrences (ARCH_5 §3 archetype C), outside the drawer shell (U18).
///
/// **Shows the actual against the usual, but only where they differ.** `paidAmount` is what really
/// left the account and `defaultAmount` is what the template expects; a bill that came in high is the
/// §7.2 row this screen closes, and repeating the default under every unchanged row would bury it.
class OccurrenceHistoryScreen extends ConsumerWidget {
  /// Shows the occurrences of [templateId].
  const OccurrenceHistoryScreen({required this.templateId, super.key});

  /// Which template's history to show.
  final String templateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final template = ref.watch(historyTemplateProvider(templateId));

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.historyRecurringTitle),
        actions: [
          IconButton(
            onPressed: () => context.push(Routes.recurringEdit(templateId)),
            tooltip: strings.actionEdit,
            icon: const Icon(Icons.edit_outlined, size: AlayaIconSize.lg),
          ),
        ],
      ),
      body: template.when(
        loading: () => AlayaListSkeleton(
          label: strings.loadingRecurring,
          hasLeading: false,
        ),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(historyTemplateProvider(templateId)),
        ),
        data: (value) => value == null
            ? EmptyState(
                title: strings.errorTitleNotFound,
                body: strings.errorBodyNotFound,
                icon: Icons.search_off_outlined,
              )
            : _Body(template: value),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.template});

  final RecurringTemplate template;

  Future<void> _undo(
    BuildContext context,
    WidgetRef ref,
    RecurringOccurrence occurrence,
  ) async {
    final strings = AlayaStrings.of(context);
    final transactionId = occurrence.paidTransactionId;
    if (transactionId == null) return;
    // Consequential, and the body names both halves and their order (ARCH_5 §5.4): the obligation
    // returns to due, then the transaction it created is deleted along with anything that transaction
    // produced.
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.payUndoTitle,
      body: strings.payUndoBody,
      confirmLabel: strings.actionUndo,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final error = await ref
        .read(occurrenceActionsProvider)
        .undoPayment(
          occurrenceId: occurrence.id,
          transactionId: transactionId,
        );
    if (!context.mounted) return;
    error == null
        ? showResultSnack(context, message: strings.payUndone)
        : showFailureSnack(context, message: error);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final async = ref.watch(occurrencesProvider(template.id));
    final today = ref.watch(clockProvider).today();
    final digits = ref.watch(builderDecimalDigitsProvider).valueOrNull ?? 2;

    return async.when(
      loading: () => AlayaListSkeleton(label: strings.loadingRecurring),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: error.toString(),
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(occurrencesProvider(template.id)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return EmptyState(
            title: strings.emptyTitleNoOccurrences,
            body: strings.emptyBodyNoOccurrences,
            icon: Icons.event_repeat_outlined,
          );
        }
        final ordered = [...rows]
          ..sort((a, b) => b.dueDateKey.compareTo(a.dueDateKey));
        return CustomScrollView(
          slivers: [
            AlayaTimeline(
              itemCount: ordered.length,
              itemBuilder: (context, index) {
                final occurrence = ordered[index];
                final paid = occurrence.paidAmount;
                final overdue = occurrence.isOverdue(today);
                final differs = paid != null && paid != template.defaultAmount;

                return AlayaTimelineEntry(
                  title: switch (occurrence.status) {
                    RecurringOccurrenceStatus.paid => strings.statusPaid,
                    RecurringOccurrenceStatus.skipped =>
                      strings.occurrenceSkipped,
                    RecurringOccurrenceStatus.dismissed =>
                      strings.statusDismissed,
                    RecurringOccurrenceStatus.due =>
                      overdue ? strings.recurringOverdue : strings.statusDue,
                  },
                  trailing: AmountText(
                    paid ?? template.defaultAmount,
                    size: AmountSize.small,
                    showSign: false,
                    decimalDigits: digits,
                    muted: !occurrence.isPaid,
                  ),
                  subtitle: DateText(
                    occurrence.dueDateKey,
                    style: DateTextStyle.medium,
                    muted: true,
                  ),
                  meta: differs
                      ? strings.historyDefaultVsActual
                      : occurrence.note,
                  icon: switch (occurrence.status) {
                    RecurringOccurrenceStatus.paid =>
                      Icons.check_circle_outline,
                    RecurringOccurrenceStatus.skipped => Icons.redo,
                    RecurringOccurrenceStatus.dismissed => Icons.block,
                    RecurringOccurrenceStatus.due => Icons.schedule,
                  },
                  tone: switch (occurrence.status) {
                    RecurringOccurrenceStatus.paid =>
                      template.direction == RecurringDirection.inflow
                          ? TimelineTone.incoming
                          : TimelineTone.outgoing,
                    RecurringOccurrenceStatus.skipped ||
                    RecurringOccurrenceStatus.dismissed =>
                      TimelineTone.superseded,
                    RecurringOccurrenceStatus.due =>
                      overdue ? TimelineTone.outgoing : TimelineTone.neutral,
                  },
                  badge: differs ? strings.historyDefaultVsActual : null,
                  onTap: occurrence.isPaid
                      ? () => _undo(context, ref, occurrence)
                      : occurrence.isOutstanding
                      ? () => PaySheet.show(
                          context,
                          occurrenceId: occurrence.id,
                          template: template,
                        )
                      : null,
                );
              },
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
                child: Text(
                  strings.emptyBodyNoOccurrences,
                  style: AlayaTypography.caption.copyWith(
                    color: semantic.muted,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
```

### `lib/features/recurring/presentation/screens/template_builder_screen.dart`

```dart
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
import 'package:alaya/shared/widgets/alaya_disclosure.dart';
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
        AlayaDisclosure(
          label: strings.sectionMoreDetails,
          summary: _templateSummary(strings, state),
          startExpanded: _hasTemplateDefaults(state),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                      DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
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
                  decoration: InputDecoration(
                    labelText: strings.labelRemindBefore,
                  ),
                  onChanged: (raw) => notifier.setRemindDaysBefore(
                    int.tryParse(raw.trim()) ?? 0,
                  ),
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
                    style: AlayaTypography.body.copyWith(
                      color: semantic.danger,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Whether anything behind the door is set, so it should open on arrival.
  ///
  /// **`autoRemind` is excluded on purpose.** ARCH_3 §7 has every reminder default to off, so it carries
  /// a default rather than a choice — counting it would open the door on every template and the tiering
  /// would do nothing. A reminder somebody actually set is caught by `remindDaysBefore`.
  static bool _hasTemplateDefaults(TemplateBuilderState state) =>
      state.payeeId != null ||
      state.accountId != null ||
      state.tagId != null ||
      state.remindDaysBefore > 0 ||
      state.endDateKey != null ||
      (state.note ?? '').trim().isNotEmpty;

  /// What is set behind the door, for the collapsed row.
  static String? _templateSummary(
    AlayaStrings strings,
    TemplateBuilderState state,
  ) {
    final parts = <String>[];
    if (state.accountId != null ||
        state.payeeId != null ||
        state.tagId != null) {
      parts.add(strings.builderSectionDefaults);
    }
    if (state.remindDaysBefore > 0) parts.add(strings.labelRemindBefore);
    if ((state.note ?? '').trim().isNotEmpty) parts.add(strings.labelNote);
    return parts.isEmpty ? null : parts.join(' \u00B7 ');
  }
}
```

### `lib/features/recurring/presentation/screens/template_list_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/features/recurring/presentation/sheets/pay_sheet.dart';
import 'package:alaya/features/recurring/presentation/widgets/template_row.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/features/recurring/providers/template_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Everything that repeats (ARCH_5 §3 archetype D).
///
/// **Nothing on this screen pays anything by itself.** Mounting it materialises occurrences up to
/// today so the list can show what is due; every one of them is created `due`, and money appears only
/// when the user taps Record (anomaly A14).
class TemplateListScreen extends ConsumerWidget {
  /// Creates the screen.
  const TemplateListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final groups = ref.watch(templateGroupsProvider);
    final overdue = ref.watch(overdueCountProvider);

    return Scaffold(
      body: groups.when(
        loading: () => AlayaListSkeleton(label: strings.loadingRecurring),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () {
            ref.invalidate(materialiseProvider);
            ref.invalidate(templatesProvider);
          },
        ),
        data: (sections) => sections.isEmpty
            ? EmptyState(
                title: strings.emptyTitleNoTemplates,
                body: strings.emptyBodyNoTemplates,
                icon: Icons.event_repeat_outlined,
                actionLabel: strings.addTemplate,
                onAction: () => context.push(Routes.recurringNew),
              )
            : Column(
                children: [
                  if (overdue > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AlayaSpacing.screenEdge,
                        AlayaSpacing.sm,
                        AlayaSpacing.screenEdge,
                        0,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: StatusChip(
                          label: strings.recurringOverdue,
                          tone: StatusTone.danger,
                          trailing: Text(
                            '$overdue',
                            style: AlayaTypography.overline.copyWith(
                              color: context.semantic.onStatus,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(child: _Sections(sections: sections)),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.recurringNew),
        tooltip: strings.addTemplate,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _Sections extends ConsumerWidget {
  const _Sections({required this.sections});

  final List<TemplateGroup> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final today = ref.watch(clockProvider).today();
    final digits = ref.watch(builderDecimalDigitsProvider).valueOrNull ?? 2;
    final actions = ref.read(templateActionsProvider);

    Future<void> guard(Future<String?> Function() run) async {
      final error = await run();
      if (!context.mounted || error == null) return;
      showFailureSnack(context, message: error);
    }

    return CustomScrollView(
      slivers: [
        for (final section in sections)
          SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AlayaSpacing.screenEdge,
                    AlayaSpacing.md,
                    AlayaSpacing.screenEdge,
                    AlayaSpacing.xs,
                  ),
                  child: Text(
                    section.direction == RecurringDirection.inflow
                        ? strings.recurringInflow
                        : strings.recurringOutflow,
                    style: AlayaTypography.sectionHeader.copyWith(
                      color: semantic.muted,
                    ),
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: section.rows.length,
                itemBuilder: (context, index) {
                  final row = section.rows[index];
                  final next = row.next;
                  return TemplateRowTile(
                    template: row.template,
                    next: next,
                    today: today,
                    decimalDigits: digits,
                    onTap: () =>
                        context.push(Routes.recurringHistory(row.template.id)),
                    onPay: next == null || row.template.isPaused
                        ? null
                        : () => PaySheet.show(
                            context,
                            occurrenceId: next.id,
                            template: row.template,
                          ),
                    onTogglePause: () => guard(
                      () => actions.setPaused(
                        id: row.template.id,
                        isPaused: !row.template.isPaused,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AlayaSpacing.xxxl)),
      ],
    );
  }
}
```

### `lib/features/recurring/presentation/sheets/pay_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/features/recurring/providers/pay_providers.dart';
import 'package:alaya/features/recurring/state/pay_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// Records what was actually paid (ARCH_5 §3 archetype A).
///
/// **The default is pre-filled and the actual is editable, and both are kept.** A bill quoted at ₹1,200
/// arriving at ₹1,247 is the ordinary case: pre-filling means the common path is one tap, and storing
/// what was really paid is what lets the history show the gap rather than pretending it did not happen.
///
/// **This is the only place money is created for a recurring template.** Materialisation produces `due`
/// rows and nothing else (anomaly A14); the transaction exists because someone tapped here.
class PaySheet extends ConsumerWidget {
  /// Creates the sheet.
  const PaySheet({
    required this.occurrenceId,
    required this.template,
    super.key,
  });

  /// Which occurrence is being settled.
  final String occurrenceId;

  /// The template it belongs to, for the default amount, account and wording.
  final RecurringTemplate template;

  /// Opens the sheet.
  static Future<void> show(
    BuildContext context, {
    required String occurrenceId,
    required RecurringTemplate template,
  }) => AlayaBottomSheet.show<void>(
    context: context,
    builder: (context) =>
        PaySheet(occurrenceId: occurrenceId, template: template),
  );

  PayArgs get _args => (
    occurrenceId: occurrenceId,
    defaultMinor: template.defaultAmount.minor,
    currencyCode: template.defaultAmount.currencyCode,
    accountId: template.defaultAccountId,
  );

  Future<void> _commit(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final created = await ref.read(payProvider(_args).notifier).commit();
    if (!context.mounted) return;
    if (created == null) {
      final state = ref.read(payProvider(_args));
      showFailureSnack(
        context,
        message:
            state.rejection ??
            switch (state.issue) {
              PayIssue.amountMissing => strings.errorAmountInvalid,
              PayIssue.accountMissing => strings.payNeedsAccount,
              PayIssue.rejected || null => strings.errorBodyGeneric,
            },
      );
      return;
    }
    Navigator.of(context).pop();
    if (!context.mounted) return;
    // Undo is offered, and the confirmation behind it says exactly what gets reversed and in which
    // order (ARCH_5 §5.4) — paying creates a transaction, so undoing it must remove one.
    showUndoSnack(
      context,
      message: strings.payRecorded,
      undoLabel: strings.actionUndo,
      onUndo: () async {
        final error = await ref
            .read(occurrenceActionsProvider)
            .undoPayment(
              occurrenceId: occurrenceId,
              transactionId: created,
            );
        if (!context.mounted) return;
        error == null
            ? showResultSnack(context, message: strings.payUndone)
            : showFailureSnack(context, message: error);
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final state = ref.watch(payProvider(_args));
    final notifier = ref.read(payProvider(_args).notifier);
    final currency = template.defaultAmount.currencyCode;
    final digits =
        ref.watch(payDecimalDigitsProvider(currency)).valueOrNull ?? 2;
    final accounts =
        ref.watch(payAccountsProvider).valueOrNull ?? const <Account>[];
    final inflow = template.direction == RecurringDirection.inflow;
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) =>
        DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());

    Account? selectedAccount;
    for (final account in accounts) {
      if (account.id == state.accountId) selectedAccount = account;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          inflow ? strings.payTitleInflow : strings.payTitle,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        Text(
          template.name,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.md),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: AmountField(
            currencyCode: currency,
            decimalDigits: digits,
            label: inflow
                ? strings.labelActualAmountInflow
                : strings.labelActualAmount,
            initialValue: state.amount,
            errorText: state.issue == PayIssue.amountMissing
                ? strings.errorAmountInvalid
                : null,
            onChanged: notifier.setAmount,
          ),
        ),
        if (state.differsFromDefault) ...[
          const SizedBox(height: AlayaSpacing.xxs),
          // Shown only when they differ. Repeating the default under an unchanged figure is noise;
          // showing it beside a changed one is the confirmation that the change was deliberate.
          Wrap(
            spacing: AlayaSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                strings.payUsualWas,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
              AmountText(
                state.defaultAmount,
                size: AmountSize.small,
                showSign: false,
                decimalDigits: digits,
                muted: true,
              ),
            ],
          ),
        ],
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.paidOn,
          formatted: format,
          label: strings.labelPaidOn,
          hint: strings.hintSelectDate,
          onChanged: notifier.setPaidOn,
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (accounts.isNotEmpty)
          DropdownButtonFormField<String>(
            key: ValueKey(selectedAccount?.id),
            initialValue: selectedAccount?.id,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: strings.labelAccount,
              errorText: state.issue == PayIssue.accountMissing
                  ? strings.payNeedsAccount
                  : null,
            ),
            items: [
              for (final account in accounts)
                DropdownMenuItem(value: account.id, child: Text(account.name)),
            ],
            onChanged: notifier.setAccount,
          ),
        const SizedBox(height: AlayaSpacing.md),
        TextFormField(
          initialValue: state.note,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: strings.labelNote,
            hintText: strings.hintNote,
          ),
          onChanged: notifier.setNote,
        ),
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: state.submitting ? null : () => _commit(context, ref),
          child: Text(strings.payCommit),
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
```

### `lib/features/recurring/presentation/widgets/template_row.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One recurring template: what it is, what it costs, and when it next lands.
///
/// **Overdue is derived, never stored.** `RecurringOccurrence.isOverdue(today)` is asked on every
/// build, because a stored flag is wrong the moment midnight passes with the app closed
/// (ARCH_2 §12.2).
///
/// **An inflow is not a negative outflow.** The amount is rendered unsigned with the direction carried
/// by wording and colour, so a salary reads as income rather than as a bill for minus twelve thousand
/// — the §7.2 row this row exists to close.
class TemplateRowTile extends StatelessWidget {
  /// Creates the row.
  const TemplateRowTile({
    required this.template,
    required this.next,
    required this.today,
    required this.decimalDigits,
    required this.onTap,
    this.onPay,
    this.onTogglePause,
    super.key,
  });

  /// The template.
  final RecurringTemplate template;

  /// Its soonest outstanding occurrence, or null when nothing is materialised.
  final RecurringOccurrence? next;

  /// Today, for the overdue derivation.
  final DateKey today;

  /// The currency's precision.
  final int decimalDigits;

  /// Opens the occurrence history.
  final VoidCallback onTap;

  /// Opens the pay sheet for [next].
  final VoidCallback? onPay;

  /// Pauses or resumes the template.
  final VoidCallback? onTogglePause;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final occurrence = next;
    final overdue = occurrence != null && occurrence.isOverdue(today);
    final dueToday = occurrence != null && occurrence.dueDateKey == today;

    // Collected before the tree so the tier can be omitted entirely when there is nothing unusual to
    // say, rather than rendering an empty row of padding.
    final chips = <Widget>[
      if (overdue)
        StatusChip(label: strings.recurringOverdue, tone: StatusTone.danger)
      else if (dueToday)
        StatusChip(label: strings.recurringDueToday, tone: StatusTone.warning),
      if (occurrence == null && !template.isPaused)
        StatusChip(label: strings.recurringNotYetDue),
      if (template.isPaused) StatusChip(label: strings.recurringPaused),
    ];

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlayaSpacing.screenEdge,
            vertical: AlayaSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    template.direction == RecurringDirection.inflow
                        ? Icons.south_west
                        : Icons.north_east,
                    size: AlayaIconSize.lg,
                    color: template.isPaused
                        ? semantic.muted
                        : template.direction == RecurringDirection.inflow
                        ? semantic.success
                        : semantic.muted,
                  ),
                  const SizedBox(width: AlayaSpacing.sm),
                  Expanded(
                    child: Text(
                      template.name,
                      style: AlayaTypography.body.copyWith(
                        color: template.isPaused
                            ? semantic.muted
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AlayaSpacing.xxs),
              // **Three tiers, not one line.** Everything below the name used to sit in a single
              // `Wrap`, so the amount, the due date, three possible chips and two buttons reflowed
              // into each other and nothing read as more important than anything else. Split by
              // role: the figure, then when it lands, then what is unusual about it, then what you
              // can do. Each tier wraps internally, so 320dp at a doubled scale still reflows
              // rather than overflowing (Law U21).
              Padding(
                padding: const EdgeInsets.only(
                  left: AlayaIconSize.lg + AlayaSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The figure, at full size. It is the thing a glance is looking for.
                    AmountText(
                      template.defaultAmount,
                      showSign: false,
                      decimalDigits: decimalDigits,
                      muted: template.isPaused,
                    ),
                    const SizedBox(height: AlayaSpacing.xxs),
                    // When it lands. Shown whether or not an occurrence exists yet: materialisation
                    // only reaches today, so a bill paid this month has nothing outstanding until
                    // next month, and an empty space where the Record button was reads as a broken
                    // screen rather than as "nothing to do".
                    Wrap(
                      spacing: AlayaSpacing.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          strings.recurringNextDue,
                          style: AlayaTypography.caption.copyWith(
                            color: semantic.muted,
                          ),
                        ),
                        DateText(
                          occurrence?.dueDateKey ?? template.nextDueDateKey,
                          style: DateTextStyle.medium,
                          muted: true,
                        ),
                      ],
                    ),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: AlayaSpacing.xs),
                      Wrap(
                        spacing: AlayaSpacing.xs,
                        runSpacing: AlayaSpacing.xxs,
                        children: chips,
                      ),
                    ],
                    if (onPay != null || onTogglePause != null) ...[
                      const SizedBox(height: AlayaSpacing.xs),
                      // Actions last and on their own line, so a destructive-feeling Pause is never
                      // adjacent to the figure it would suspend.
                      Wrap(
                        spacing: AlayaSpacing.xs,
                        runSpacing: AlayaSpacing.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (onPay != null)
                            FilledButton.tonal(
                              onPressed: onPay,
                              child: Text(strings.payCommit),
                            ),
                          if (onTogglePause != null)
                            TextButton(
                              onPressed: onTogglePause,
                              child: Text(
                                template.isPaused
                                    ? strings.actionResume
                                    : strings.actionPause,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### `lib/features/recurring/providers/bill_account_providers.dart`

```dart
/// Resolving which account a bill payment comes from, without asking (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/account.dart';

/// Accounts a payment may come from.
final billAccountsProvider = StreamProvider.autoDispose<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// The app-wide default account, if the user has set one.
final defaultAccountIdProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(settingsRepositoryProvider).readDefaultAccountId(),
);

/// The account a bill payment should use when the user has not chosen one.
///
/// **Three fallbacks, in order, none of which asks:** the template's own `defaultAccountId`, then the
/// app-wide default from settings, then the only selectable account if there is exactly one. Recording
/// a bill should be one tap, and every one of these is information the user has already given.
///
/// It stops at null rather than guessing between two accounts. A withdrawal attributed to the wrong
/// account is worse than one that asked, because nothing on screen would ever reveal it — whereas the
/// question is answered once and remembered on the template.
final resolvedBillAccountProvider = Provider.autoDispose
    .family<String?, String?>((ref, templateDefault) {
      if (templateDefault != null) return templateDefault;
      final appDefault = ref.watch(defaultAccountIdProvider).valueOrNull;
      if (appDefault != null) return appDefault;
      final accounts =
          ref.watch(billAccountsProvider).valueOrNull ?? const <Account>[];
      return accounts.length == 1 ? accounts.single.id : null;
    });
```

### `lib/features/recurring/providers/due_bills_providers.dart`

```dart
/// The recurring bills a payment can settle (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/domain/repositories/recurring_repository.dart';

/// Outflow templates with an occurrence outstanding today, soonest first.
///
/// **`watchDue()` was built in Phase 3A and used nowhere until now.** It already excludes paused and
/// ended templates and picks each one's soonest outstanding occurrence, which is exactly the read the
/// bill form needs — reimplementing that filter over `watchAllTemplates` would have been a second
/// definition of "due" to keep in step.
final dueBillsProvider = StreamProvider.autoDispose<List<RecurringDue>>(
  (ref) => ref
      .watch(recurringRepositoryProvider)
      .watchDue()
      .map(
        (all) =>
            [
              for (final due in all)
                if (due.template.direction == RecurringDirection.outflow &&
                    due.occurrence != null)
                  due,
            ]..sort(
              (a, b) =>
                  a.occurrence!.dueDateKey.compareTo(b.occurrence!.dueDateKey),
            ),
      ),
);
```

### `lib/features/recurring/providers/occurrence_history_providers.dart`

```dart
/// View-model state for one template's occurrence history (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/recurring_template.dart';

/// The template the history belongs to.
final historyTemplateProvider = FutureProvider.autoDispose
    .family<RecurringTemplate?, String>(
      (ref, templateId) =>
          ref.watch(recurringRepositoryProvider).templateById(templateId),
    );
```

### `lib/features/recurring/providers/pay_providers.dart`

```dart
/// View-model state for the pay sheet and occurrence history (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/recurring/state/pay_state.dart';

/// Which occurrence a pay sheet is settling, and what the template says it usually costs.
typedef PayArgs = ({
  String occurrenceId,
  int defaultMinor,
  String currencyCode,
  String? accountId,
});

/// Accounts the payment may come from.
final payAccountsProvider = StreamProvider.autoDispose<List<Account>>(
  // `watchSelectable`, not a list of everything: an archived account is not somewhere a payment can
  // come from, and offering it is how a closed account acquires new transactions.
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// The home currency's decimal digits (ARCH_1 §4.1).
final payDecimalDigitsProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, code) async =>
      (await ref.watch(currencyRepositoryProvider).byCode(code))
          ?.decimalDigits ??
      2,
);

/// The pay sheet for one occurrence.
final payProvider = NotifierProvider.autoDispose
    .family<PayNotifier, PayState, PayArgs>(PayNotifier.new);

/// Holds the pending payment and commits it.
///
/// **State is synchronous.** Everything the sheet needs — the occurrence, the default, the template's
/// account — arrives in the family argument from the row that opened it, so the amount field accepts a
/// keystroke on the first frame rather than after a spinner (ARCH_5 §5.2).
class PayNotifier extends AutoDisposeFamilyNotifier<PayState, PayArgs> {
  @override
  PayState build(PayArgs arg) {
    final defaultAmount = Money(arg.defaultMinor, arg.currencyCode);
    return PayState(
      occurrenceId: arg.occurrenceId,
      defaultAmount: defaultAmount,
      // Pre-filled, so the common case — it cost what it usually costs — is one tap.
      amount: defaultAmount,
      paidOn: ref.read(clockProvider).today(),
      accountId: arg.accountId,
    );
  }

  /// Sets what is actually being paid.
  void setAmount(Money? amount) =>
      state = state.copyWith(amount: amount, clearIssue: true, dirty: true);

  /// Sets which account it came from.
  void setAccount(String? accountId) => state = state.copyWith(
    accountId: accountId,
    clearIssue: true,
    dirty: true,
  );

  /// Sets when it was paid.
  void setPaidOn(DateKey date) =>
      state = state.copyWith(paidOn: date, dirty: true);

  /// Sets the free note.
  void setNote(String note) => state = state.copyWith(note: note, dirty: true);

  /// Commits the payment, returning the id of the transaction it created.
  ///
  /// `payOccurrence` writes the transaction and settles the occurrence together; nothing here does it
  /// by hand. Returns null on rejection, with the reason on the state.
  Future<String?> commit() async {
    final amount = state.amount;
    if (amount == null || !amount.isPositive) {
      state = state.copyWith(
        issue: PayIssue.amountMissing,
        shakeTrigger: state.shakeTrigger + 1,
      );
      return null;
    }
    final accountId = state.accountId;
    if (accountId == null) {
      state = state.copyWith(issue: PayIssue.accountMissing);
      return null;
    }

    state = state.copyWith(submitting: true, clearIssue: true);
    try {
      final result = await ref
          .read(recurringRepositoryProvider)
          .payOccurrence(
            occurrenceId: state.occurrenceId,
            amount: amount,
            paidOn: state.paidOn,
            accountId: accountId,
            paymentMethodId: state.paymentMethodId,
          );
      final failure = result.failureOrNull;
      if (failure != null) {
        state = state.copyWith(
          issue: PayIssue.rejected,
          rejection: failure.message,
        );
        return null;
      }
      return result.valueOrNull?.id;
    } on Object catch (error, stack) {
      ref
          .read(loggerProvider)
          .log(
            'Recurring payment failed',
            level: LogLevel.error,
            tag: 'recurring.pay',
            error: error,
            stackTrace: stack,
          );
      state = state.copyWith(
        issue: PayIssue.rejected,
        rejection: error.toString(),
      );
      return null;
    } finally {
      state = state.copyWith(submitting: false);
    }
  }
}

/// Writes an occurrence row performs.
final occurrenceActionsProvider = Provider<OccurrenceActions>(
  OccurrenceActions.new,
);

/// Skips and un-pays occurrences.
class OccurrenceActions {
  /// Creates the actions.
  OccurrenceActions(this._ref);

  final Ref _ref;

  /// Marks an occurrence deliberately skipped, so it stops being outstanding without inventing money.
  Future<String?> skip({required String occurrenceId, String? note}) async {
    final result = await _ref
        .read(recurringRepositoryProvider)
        .skipOccurrence(occurrenceId: occurrenceId, note: note);
    return result.failureOrNull?.message;
  }

  /// Undoes a payment: the occurrence returns to due, then the transaction it created is deleted.
  ///
  /// **That order is deliberate.** Neither half can be inside the other's transaction, so one of two
  /// partial states survives a failure between them: an occurrence due while its transaction still
  /// exists shows a visible duplicate the user can fix, whereas a transaction deleted while the
  /// occurrence still reads paid hides an obligation with nothing on screen to reveal it. Order for the
  /// visible failure (ARCH_4 R21).
  Future<String?> undoPayment({
    required String occurrenceId,
    required String transactionId,
  }) async {
    final unsettled = await _ref
        .read(recurringRepositoryProvider)
        .unsettleOccurrence(occurrenceId);
    final unsettleFailure = unsettled.failureOrNull;
    if (unsettleFailure != null) return unsettleFailure.message;

    final deleted = await _ref
        .read(transactionRepositoryProvider)
        .delete(id: transactionId);
    return deleted.failureOrNull?.message;
  }
}
```

### `lib/features/recurring/providers/template_builder_providers.dart`

```dart
/// View-model state for the recurring template builder (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/recurring/providers/template_draft_provider.dart';
import 'package:alaya/features/recurring/providers/template_list_providers.dart';
import 'package:alaya/features/recurring/state/template_builder_state.dart';
import 'package:alaya/shared/widgets/frequency_preview.dart';

/// Accounts the pay sheet may default to.
final builderAccountsProvider = StreamProvider.autoDispose<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// The home currency, so an amount is never denominated in a guess.
final builderCurrencyProvider = FutureProvider.autoDispose<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      'INR',
);

/// The home currency's decimal digits (ARCH_1 §4.1).
final builderDecimalDigitsProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final code = await ref.watch(builderCurrencyProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// The builder for one template, or for a new one when the argument is null.
final templateBuilderProvider = NotifierProvider.autoDispose
    .family<TemplateBuilderNotifier, AsyncValue<TemplateBuilderState>, String?>(
      TemplateBuilderNotifier.new,
    );

/// The next three dates the current frequency would land on.
///
/// **Walked through `RecurringEngine.nextDue`, the same method materialisation uses.** A second copy
/// of the clamp here would let the preview and the written occurrences disagree, which is the one
/// thing this preview exists to prevent (anomaly A13).
final previewProvider = Provider.autoDispose.family<List<PreviewedDate>, String?>((
  ref,
  editorId,
) {
  final state = ref.watch(templateBuilderProvider(editorId)).valueOrNull;
  if (state == null || !state.isComplete) return const [];
  final engine = ref.watch(recurringEngineProvider);
  final template = state.toTemplate(
    newId: 'preview',
    normalizedName: 'preview',
    nextDue: state.startDateKey,
  );

  final dates = <PreviewedDate>[];
  var cursor = state.startDateKey;
  final end = state.endDateKey;
  final anchor = state.anchorDayOfMonth;
  while (dates.length < 3) {
    if (end != null && cursor.isAfter(end)) break;
    dates.add(
      PreviewedDate(
        dateKey: cursor,
        // A clamp is visible exactly when the anchor could not be reached this month. Only a monthly
        // or yearly interval anchors to a day, so a weekly template never reports one.
        clamped: anchor != null && state.needsDayAnchor && cursor.day != anchor,
      ),
    );
    cursor = engine.nextDue(from: cursor, template: template);
  }
  return dates;
});

/// Loads, edits and saves one recurring template.
class TemplateBuilderNotifier
    extends
        AutoDisposeFamilyNotifier<AsyncValue<TemplateBuilderState>, String?> {
  @override
  AsyncValue<TemplateBuilderState> build(String? arg) {
    // A new template needs nothing fetched beyond the currency, so it does not flash a skeleton for a
    // form it could have shown. Assigning state from a synchronous path inside `build` is what
    // Riverpod refuses, so the load is always awaited.
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(String? id) async {
    try {
      final code =
          await ref.read(settingsRepositoryProvider).readHomeCurrencyCode() ??
          'INR';
      if (id == null) {
        final today = ref.read(clockProvider).today();
        // A draft another module prepared, if one is waiting. `take()` clears it, so it is applied
        // exactly once and a stale one cannot ambush the next blank builder.
        final draft = ref.read(templateDraftProvider.notifier).take();
        state = AsyncValue.data(
          TemplateBuilderState(
            currencyCode: code,
            startDateKey: today,
            anchorDayOfMonth: today.day,
            name: draft?.name ?? '',
            amount: draft?.amount,
          ),
        );
        return;
      }
      final template = await ref
          .read(recurringRepositoryProvider)
          .templateById(id);
      if (template == null) {
        state = AsyncValue.error(
          StateError('Recurring template $id not found.'),
          StackTrace.current,
        );
        return;
      }
      state = AsyncValue.data(TemplateBuilderState.fromTemplate(template));
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  void _edit(TemplateBuilderState Function(TemplateBuilderState) change) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(change(current));
  }

  /// Sets the name.
  void setName(String name) =>
      _edit((s) => s.copyWith(name: name, clearIssue: true));

  /// Sets bill, subscription, rent or salary.
  ///
  /// Salary implies an inflow, and setting it also flips the direction — a salary rendered as a
  /// negative bill is the §7.2 row this module exists to close, and making the user set both is how
  /// that mistake gets made.
  void setKind(RecurringKind kind) => _edit(
    (s) => s.copyWith(
      kind: kind,
      direction: kind == RecurringKind.salary
          ? RecurringDirection.inflow
          : s.direction,
    ),
  );

  /// Sets whether money leaves or arrives.
  void setDirection(RecurringDirection direction) =>
      _edit((s) => s.copyWith(direction: direction));

  /// Sets the usual amount.
  void setAmount(Money? amount) =>
      _edit((s) => s.copyWith(amount: amount, clearIssue: true));

  /// Sets the interval unit, and drops an anchor the new unit cannot use.
  void setIntervalUnit(RecurringIntervalUnit unit) => _edit((s) {
    final anchored =
        unit == RecurringIntervalUnit.month ||
        unit == RecurringIntervalUnit.year;
    return s.copyWith(
      intervalUnit: unit,
      anchorDayOfMonth: anchored
          ? (s.anchorDayOfMonth ?? s.startDateKey.day)
          : null,
      clearAnchor: !anchored,
      clearIssue: true,
    );
  });

  /// Sets how many units make up one interval.
  void setIntervalCount(int count) =>
      _edit((s) => s.copyWith(intervalCount: count < 1 ? 1 : count));

  /// Sets the day of the month the schedule anchors to.
  void setAnchorDay(int? day) => _edit(
    (s) => day == null
        ? s.copyWith(clearAnchor: true)
        : s.copyWith(anchorDayOfMonth: day, clearIssue: true),
  );

  /// Sets when it starts, carrying the day anchor with it unless the user has chosen one.
  ///
  /// **The anchor followed nothing before, and that was a due-date bug.** The builder seeds the anchor
  /// from today; moving the start date to the 15th left it on today's day, so the first occurrence
  /// landed on the 15th and every one after it on some unrelated day. The anchor only stops following
  /// once `setAnchorDay` is called, which is the user saying they meant a different day.
  void setStartDate(DateKey date) => _edit((s) {
    final follows =
        s.anchorDayOfMonth == null || s.anchorDayOfMonth == s.startDateKey.day;
    return s.copyWith(
      startDateKey: date,
      anchorDayOfMonth: follows && s.needsDayAnchor
          ? date.day
          : s.anchorDayOfMonth,
    );
  });

  /// Sets when it stops, or clears the end date.
  void setEndDate(DateKey? date) => _edit(
    (s) => date == null
        ? s.copyWith(clearEndDate: true)
        : s.copyWith(endDateKey: date),
  );

  /// Sets which account the pay sheet defaults to.
  void setAccount(String? accountId) =>
      _edit((s) => s.copyWith(accountId: accountId));

  /// Sets how many days of warning to give.
  void setRemindDaysBefore(int days) =>
      _edit((s) => s.copyWith(remindDaysBefore: days < 0 ? 0 : days));

  /// Turns reminders on or off.
  void toggleRemind() => _edit((s) => s.copyWith(autoRemind: !s.autoRemind));

  /// Sets the free note.
  void setNote(String note) => _edit((s) => s.copyWith(note: note));

  /// Saves the template, returning its id on success and null on rejection or failure.
  ///
  /// Every refusal is named before the repository sees it, and a rejection carries the repository's own
  /// message — the builder has three ways to be incomplete and "something went wrong" distinguishes
  /// none of them (Law U9).
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (current.name.trim().isEmpty) {
      _edit(
        (s) => s.copyWith(
          issue: TemplateSaveIssue.nameMissing,
          shakeTrigger: s.shakeTrigger + 1,
        ),
      );
      return null;
    }
    if (!(current.amount?.isPositive ?? false)) {
      _edit(
        (s) => s.copyWith(
          issue: TemplateSaveIssue.amountMissing,
          shakeTrigger: s.shakeTrigger + 1,
        ),
      );
      return null;
    }
    if (current.needsDayAnchor && current.anchorDayOfMonth == null) {
      _edit((s) => s.copyWith(issue: TemplateSaveIssue.anchorMissing));
      return null;
    }

    _edit((s) => s.copyWith(submitting: true, clearIssue: true));
    try {
      final id = current.id ?? ref.read(uidGeneratorProvider).generate();
      final saved = await ref
          .read(recurringRepositoryProvider)
          .saveTemplate(
            current.toTemplate(
              newId: id,
              normalizedName: ref
                  .read(normalizerProvider)
                  .normalize(current.name.trim()),
              // A new template's first occurrence is its start date, not one interval after it.
              // Editing leaves the cursor alone: materialisation owns it, and resetting it would
              // resurrect occurrences already paid.
              nextDue: current.isEditing
                  ? (await ref
                                .read(recurringRepositoryProvider)
                                .templateById(id))
                            ?.nextDueDateKey ??
                        current.startDateKey
                  : current.startDateKey,
            ),
          );
      final failure = saved.failureOrNull;
      if (failure != null) {
        _edit(
          (s) => s.copyWith(
            issue: TemplateSaveIssue.rejected,
            rejection: failure.message,
          ),
        );
        return null;
      }
      // Materialisation runs once per list mount, so a template created afterwards would show no
      // occurrence until the next launch. Invalidating it here is what makes the first due row appear
      // immediately rather than looking like nothing happened.
      ref.invalidate(materialiseProvider);
      _edit((s) => s.copyWith(dirty: false));
      return id;
    } on Object catch (error, stack) {
      ref
          .read(loggerProvider)
          .log(
            'Recurring template save failed',
            level: LogLevel.error,
            tag: 'recurring.builder',
            error: error,
            stackTrace: stack,
          );
      _edit(
        (s) => s.copyWith(
          issue: TemplateSaveIssue.rejected,
          rejection: error.toString(),
        ),
      );
      return null;
    } finally {
      _edit((s) => s.copyWith(submitting: false));
    }
  }
}
```

### `lib/features/recurring/providers/template_draft_provider.dart`

```dart
/// The one-shot channel a module uses to hand the template builder a starting point.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/money/money.dart';

/// A template another module has prepared for the user to finish.
class TemplateDraft {
  /// Creates a draft.
  const TemplateDraft({required this.name, this.amount});

  /// What to call it — a transaction line's description, usually.
  final String name;

  /// What it cost this time, offered as the usual amount.
  final Money? amount;
}

/// A draft waiting to be picked up by the next new-template builder.
///
/// **Set immediately before pushing the builder, consumed by its first load, then cleared.** A line
/// marked "Make it recurring" carries a name and an amount but no interval and no anchor — a receipt
/// cannot know how often something repeats, and inventing monthly-on-the-1st would create an
/// obligation nobody agreed to. So the line hands over what it knows and the user supplies the rest.
///
/// `take()` makes the one-shot explicit rather than leaving a stale draft to ambush the next blank
/// builder — the same reason `transactionDraftProvider` works this way.
final templateDraftProvider =
    NotifierProvider<TemplateDraftNotifier, TemplateDraft?>(
      TemplateDraftNotifier.new,
    );

/// Holds at most one pending draft.
class TemplateDraftNotifier extends Notifier<TemplateDraft?> {
  @override
  TemplateDraft? build() => null;

  /// Offers a draft to the next builder that opens.
  void offer(TemplateDraft draft) => state = draft;

  /// Returns the pending draft and clears it, so it is never applied twice.
  TemplateDraft? take() {
    final draft = state;
    state = null;
    return draft;
  }
}
```

### `lib/features/recurring/providers/template_list_providers.dart`

```dart
/// View-model state for the recurring template list (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';

/// A template with the soonest outstanding occurrence against it, if any.
class TemplateRow {
  /// Creates a row.
  const TemplateRow({required this.template, this.next});

  /// The template.
  final RecurringTemplate template;

  /// Its soonest outstanding occurrence, or null when nothing is materialised yet.
  final RecurringOccurrence? next;
}

/// One direction's worth of templates.
class TemplateGroup {
  /// Creates a group.
  const TemplateGroup({required this.direction, required this.rows});

  /// Whether these are outflows or inflows.
  final RecurringDirection direction;

  /// The rows under it.
  final List<TemplateRow> rows;
}

/// Materialises occurrences up to today, once per list mount.
///
/// **Lazy, and never automatic beyond this.** Occurrences are created up to today so the list can show
/// what is due; not one of them is paid, and no transaction exists until a user taps (anomaly A14). An
/// app unopened for three months produces three due rows and zero transactions.
final materialiseProvider = FutureProvider<int>((ref) async {
  final result = await ref
      .watch(recurringRepositoryProvider)
      .materialiseUpTo(ref.watch(clockProvider).today());
  return result.valueOrNull ?? 0;
});

/// Every template.
final templatesProvider = StreamProvider<List<RecurringTemplate>>(
  (ref) => ref.watch(recurringRepositoryProvider).watchAllTemplates(),
);

/// Outstanding occurrences for one template, soonest first.
final occurrencesProvider = StreamProvider.autoDispose
    .family<List<RecurringOccurrence>, String>(
      (ref, templateId) =>
          ref.watch(recurringRepositoryProvider).watchOccurrences(templateId),
    );

/// Templates grouped by direction, each with its soonest outstanding occurrence.
///
/// Grouped by direction rather than sorted by date because a salary and a rent bill are not two
/// entries on one list — the §7.2 row this closes is precisely that an inflow must read as income
/// rather than as a negative bill.
final templateGroupsProvider = Provider<AsyncValue<List<TemplateGroup>>>((ref) {
  // Depended on so the list cannot render before today's rows exist; its own value is not needed.
  ref.watch(materialiseProvider);
  final templates = ref.watch(templatesProvider);
  if (templates.hasError) {
    return AsyncValue.error(templates.error!, templates.stackTrace!);
  }
  final all = templates.valueOrNull;
  if (all == null) return const AsyncValue.loading();

  List<TemplateRow> rowsFor(RecurringDirection direction) =>
      [
        for (final template in all)
          if (template.direction == direction)
            TemplateRow(
              template: template,
              next: _soonestOutstanding(
                ref.watch(occurrencesProvider(template.id)).valueOrNull,
              ),
            ),
      ]..sort(
        (a, b) =>
            a.template.nextDueDateKey.compareTo(b.template.nextDueDateKey),
      );

  final outflow = rowsFor(RecurringDirection.outflow);
  final inflow = rowsFor(RecurringDirection.inflow);
  return AsyncValue.data([
    if (outflow.isNotEmpty)
      TemplateGroup(direction: RecurringDirection.outflow, rows: outflow),
    if (inflow.isNotEmpty)
      TemplateGroup(direction: RecurringDirection.inflow, rows: inflow),
  ]);
});

RecurringOccurrence? _soonestOutstanding(
  List<RecurringOccurrence>? occurrences,
) {
  if (occurrences == null) return null;
  RecurringOccurrence? soonest;
  for (final occurrence in occurrences) {
    if (!occurrence.isOutstanding) continue;
    if (soonest == null || occurrence.dueDateKey.isBefore(soonest.dueDateKey)) {
      soonest = occurrence;
    }
  }
  return soonest;
}

/// How many templates have an occurrence past its due date, for the header count.
///
/// Derived from the clock through `RecurringEngine.isOverdue`, never a stored flag (ARCH_2 §12.2): a
/// flag would be wrong the moment midnight passed with the app closed.
final overdueCountProvider = Provider<int>((ref) {
  final groups = ref.watch(templateGroupsProvider).valueOrNull ?? const [];
  final engine = ref.watch(recurringEngineProvider);
  final today = ref.watch(clockProvider).today();
  var count = 0;
  for (final group in groups) {
    for (final row in group.rows) {
      final next = row.next;
      if (next == null) continue;
      if (engine.isOverdue(occurrence: next, today: today)) count++;
    }
  }
  return count;
});

/// Writes the template list performs.
final templateActionsProvider = Provider<TemplateActions>(TemplateActions.new);

/// Pauses, resumes and deletes templates.
class TemplateActions {
  /// Creates the actions.
  TemplateActions(this._ref);

  final Ref _ref;

  /// Pauses or resumes a template, returning the failure's own message or null on success.
  Future<String?> setPaused({
    required String id,
    required bool isPaused,
  }) async {
    final result = await _ref
        .read(recurringRepositoryProvider)
        .setTemplatePaused(id: id, isPaused: isPaused);
    return result.failureOrNull?.message;
  }

  /// Deletes a template.
  ///
  /// Its occurrences go with it; the transactions any of them created stay, because a payment that
  /// happened happened (Law L6).
  Future<String?> delete(String id) async {
    final result = await _ref
        .read(recurringRepositoryProvider)
        .deleteTemplate(id);
    return result.failureOrNull?.message;
  }
}
```

### `lib/features/recurring/state/pay_state.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// Why a payment was refused, when it was refused for a reason worth naming.
enum PayIssue {
  /// No amount, or a non-positive one.
  amountMissing,

  /// No account chosen, and the template had no default.
  accountMissing,

  /// The write failed for a reason the repository named.
  rejected,
}

/// What the pay sheet is holding (ARCH_5 §3 archetype A).
///
/// **The default and the actual are two different figures and both are kept.** A bill quoted at
/// ₹1,200 that arrives at ₹1,247 is the normal case, not an error — the sheet pre-fills the default so
/// the common path is one tap, and stores what was actually paid so the history can show the gap.
class PayState {
  /// Creates the sheet's state.
  const PayState({
    required this.occurrenceId,
    required this.defaultAmount,
    required this.paidOn,
    this.amount,
    this.accountId,
    this.paymentMethodId,
    this.note,
    this.submitting = false,
    this.issue,
    this.rejection,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// Which occurrence is being settled.
  final String occurrenceId;

  /// What the template says it usually is.
  final Money defaultAmount;

  /// What is actually being paid, pre-filled from [defaultAmount].
  final Money? amount;

  /// When.
  final DateKey paidOn;

  /// Which account it came from, or goes into.
  final String? accountId;

  /// How it was paid.
  final String? paymentMethodId;

  /// Free note.
  final String? note;

  /// Whether a commit is in flight.
  final bool submitting;

  /// Why the last commit was refused, or null if it was not.
  final PayIssue? issue;

  /// The repository's own message when it rejected the write.
  final String? rejection;

  /// Incremented to shake the offending field.
  final int shakeTrigger;

  /// Whether anything was touched, for the dismiss guard (Law U10).
  final bool dirty;

  /// Whether the actual figure differs from the usual one, which is what the history highlights.
  bool get differsFromDefault {
    final actual = amount;
    return actual != null && actual != defaultAmount;
  }

  /// Returns a copy with the supplied changes.
  ///
  /// `issue` and `rejection` survive an unrelated `copyWith` — a bare assignment lets the
  /// `submitting: false` in a `finally` erase the reason before the sheet reads it (ARCH_4 R31).
  PayState copyWith({
    Money? amount,
    DateKey? paidOn,
    String? accountId,
    String? paymentMethodId,
    String? note,
    bool? submitting,
    PayIssue? issue,
    String? rejection,
    bool clearIssue = false,
    int? shakeTrigger,
    bool? dirty,
  }) => PayState(
    occurrenceId: occurrenceId,
    defaultAmount: defaultAmount,
    amount: amount ?? this.amount,
    paidOn: paidOn ?? this.paidOn,
    accountId: accountId ?? this.accountId,
    paymentMethodId: paymentMethodId ?? this.paymentMethodId,
    note: note ?? this.note,
    submitting: submitting ?? this.submitting,
    issue: clearIssue ? null : (issue ?? this.issue),
    rejection: clearIssue ? null : (rejection ?? this.rejection),
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? this.dirty,
  );
}
```

### `lib/features/recurring/state/template_builder_state.dart`

```dart
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_template.dart';

/// Why a template save was refused, when it was refused for a reason worth naming.
enum TemplateSaveIssue {
  /// The name was blank.
  nameMissing,

  /// The default amount was missing or not positive.
  amountMissing,

  /// A monthly or yearly template with no day to anchor to.
  anchorMissing,

  /// The write failed for a reason the repository named.
  rejected,
}

/// Everything the template builder is holding (ARCH_5 §3 archetype B).
class TemplateBuilderState {
  /// Creates the builder's state.
  const TemplateBuilderState({
    required this.currencyCode,
    required this.startDateKey,
    this.id,
    this.name = '',
    this.kind = RecurringKind.bill,
    this.direction = RecurringDirection.outflow,
    this.amount,
    this.intervalUnit = RecurringIntervalUnit.month,
    this.intervalCount = 1,
    this.anchorDayOfMonth,
    this.endDateKey,
    this.payeeId,
    this.accountId,
    this.tagId,
    this.remindDaysBefore = 3,
    this.autoRemind = true,
    this.isPaused = false,
    this.note,
    this.submitting = false,
    this.issue,
    this.rejection,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// The template being edited, or null for a new one.
  final String? id;

  /// What to call it.
  final String name;

  /// Bill, subscription, rent or salary.
  final RecurringKind kind;

  /// Whether money leaves or arrives.
  ///
  /// Drives the whole module's wording: an inflow salary is income, never a negative bill.
  final RecurringDirection direction;

  /// The currency amounts are entered in.
  final String currencyCode;

  /// What it usually costs. A default the pay sheet pre-fills, never a fixed figure.
  final Money? amount;

  /// Days, weeks, months or years.
  final RecurringIntervalUnit intervalUnit;

  /// How many of them.
  final int intervalCount;

  /// The day of the month it anchors to.
  ///
  /// Stored once and clamped at every render, never advanced (anomaly A13). Required for a monthly or
  /// yearly template, which is what stops a February settlement dragging every later occurrence back
  /// to the 28th permanently.
  final int? anchorDayOfMonth;

  /// When it starts.
  final DateKey startDateKey;

  /// When it stops, if it does.
  final DateKey? endDateKey;

  /// Who it is paid to, or received from.
  final String? payeeId;

  /// Which account the pay sheet should default to.
  final String? accountId;

  /// The tag every generated transaction carries.
  final String? tagId;

  /// How many days of warning Phase 8B should give.
  final int remindDaysBefore;

  /// Whether to remind at all.
  final bool autoRemind;

  /// Whether it is currently paused.
  final bool isPaused;

  /// Free note.
  final String? note;

  /// Whether a save is in flight.
  final bool submitting;

  /// Why the last save was refused, or null if it was not.
  final TemplateSaveIssue? issue;

  /// The repository's own message when it rejected the write.
  final String? rejection;

  /// Incremented to shake the offending field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the unsaved-changes guard (Law U10).
  final bool dirty;

  /// Whether this is editing an existing template.
  bool get isEditing => id != null;

  /// Whether the interval is anchored to a day of the month.
  bool get needsDayAnchor =>
      intervalUnit == RecurringIntervalUnit.month ||
      intervalUnit == RecurringIntervalUnit.year;

  /// Whether the state is complete enough to preview and to save.
  bool get isComplete =>
      name.trim().isNotEmpty &&
      (amount?.isPositive ?? false) &&
      intervalCount >= 1 &&
      (!needsDayAnchor || anchorDayOfMonth != null);

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  ///
  /// `issue` and `rejection` are preserved unless [clearIssue] is passed, because a bare assignment
  /// lets any later `copyWith` erase the reason before the screen reads it (ARCH_4 R31).
  TemplateBuilderState copyWith({
    String? id,
    String? name,
    RecurringKind? kind,
    RecurringDirection? direction,
    Money? amount,
    RecurringIntervalUnit? intervalUnit,
    int? intervalCount,
    int? anchorDayOfMonth,
    bool clearAnchor = false,
    DateKey? startDateKey,
    DateKey? endDateKey,
    bool clearEndDate = false,
    String? payeeId,
    String? accountId,
    String? tagId,
    int? remindDaysBefore,
    bool? autoRemind,
    bool? isPaused,
    String? note,
    bool? submitting,
    TemplateSaveIssue? issue,
    String? rejection,
    bool clearIssue = false,
    int? shakeTrigger,
    bool? dirty,
  }) => TemplateBuilderState(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    direction: direction ?? this.direction,
    currencyCode: currencyCode,
    amount: amount ?? this.amount,
    intervalUnit: intervalUnit ?? this.intervalUnit,
    intervalCount: intervalCount ?? this.intervalCount,
    anchorDayOfMonth: clearAnchor
        ? null
        : (anchorDayOfMonth ?? this.anchorDayOfMonth),
    startDateKey: startDateKey ?? this.startDateKey,
    endDateKey: clearEndDate ? null : (endDateKey ?? this.endDateKey),
    payeeId: payeeId ?? this.payeeId,
    accountId: accountId ?? this.accountId,
    tagId: tagId ?? this.tagId,
    remindDaysBefore: remindDaysBefore ?? this.remindDaysBefore,
    autoRemind: autoRemind ?? this.autoRemind,
    isPaused: isPaused ?? this.isPaused,
    note: note ?? this.note,
    submitting: submitting ?? this.submitting,
    issue: clearIssue ? null : (issue ?? this.issue),
    rejection: clearIssue ? null : (rejection ?? this.rejection),
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? true,
  );

  /// Builds the entity this state describes.
  ///
  /// `nextDueDateKey` starts at `startDateKey` for a new template: materialisation walks forward from
  /// there, so the first occurrence is the start date itself rather than one interval after it.
  RecurringTemplate toTemplate({
    required String newId,
    required String normalizedName,
    required DateKey nextDue,
  }) => RecurringTemplate(
    id: id ?? newId,
    name: name.trim(),
    normalizedName: normalizedName,
    kind: kind,
    direction: direction,
    defaultAmount: amount ?? Money.zero(currencyCode),
    intervalUnit: intervalUnit,
    intervalCount: intervalCount,
    startDateKey: startDateKey,
    nextDueDateKey: nextDue,
    isPaused: isPaused,
    autoRemind: autoRemind,
    remindDaysBefore: remindDaysBefore,
    payeeId: payeeId,
    defaultAccountId: accountId,
    tagId: tagId,
    anchorDayOfMonth: anchorDayOfMonth,
    endDateKey: endDateKey,
    note: note,
  );

  /// Loads an existing template into a builder state.
  static TemplateBuilderState fromTemplate(RecurringTemplate template) =>
      TemplateBuilderState(
        id: template.id,
        name: template.name,
        kind: template.kind,
        direction: template.direction,
        currencyCode: template.defaultAmount.currencyCode,
        amount: template.defaultAmount,
        intervalUnit: template.intervalUnit,
        intervalCount: template.intervalCount,
        anchorDayOfMonth: template.anchorDayOfMonth,
        startDateKey: template.startDateKey,
        endDateKey: template.endDateKey,
        payeeId: template.payeeId,
        accountId: template.defaultAccountId,
        tagId: template.tagId,
        remindDaysBefore: template.remindDaysBefore,
        autoRemind: template.autoRemind,
        isPaused: template.isPaused,
        note: template.note,
      );
}
```

### `test/features/recurring/due_dates_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/services/recurring_engine.dart';
import 'package:alaya/features/recurring/state/template_builder_state.dart';

/// The due-date arithmetic, and the builder rules that feed it.
///
/// These are the cases a user notices and cannot debug: a bill that walks backwards through February,
/// an anchor that stops matching the start date, a first occurrence that never appears.
void main() {
  const engine = RecurringEngine();

  RecurringTemplate template({
    RecurringIntervalUnit unit = RecurringIntervalUnit.month,
    int intervalCount = 1,
    int? anchorDayOfMonth = 31,
    DateKey start = const DateKey(20260131),
    DateKey? nextDue,
    DateKey? end,
  }) => RecurringTemplate(
    id: 'tpl-1',
    name: 'Rent',
    normalizedName: 'rent',
    kind: RecurringKind.rent,
    direction: RecurringDirection.outflow,
    defaultAmount: const Money(120000, 'INR'),
    intervalUnit: unit,
    intervalCount: intervalCount,
    startDateKey: start,
    nextDueDateKey: nextDue ?? start,
    isPaused: false,
    autoRemind: true,
    remindDaysBefore: 3,
    anchorDayOfMonth: anchorDayOfMonth,
    endDateKey: end,
  );

  group('the anchor clamp', () {
    test('a 31st anchor shortens for February and returns in March', () {
      final t = template();
      final feb = engine.nextDue(from: const DateKey(20260131), template: t);
      final mar = engine.nextDue(from: feb, template: t);
      final apr = engine.nextDue(from: mar, template: t);
      expect(feb, const DateKey(20260228));
      // The whole point of storing the anchor rather than advancing it (anomaly A13): March returns to
      // the 31st instead of inheriting February's 28 for the rest of the template's life.
      expect(mar, const DateKey(20260331));
      expect(apr, const DateKey(20260430));
    });

    test('it never walks backwards across a whole year', () {
      final t = template();
      var cursor = const DateKey(20260131);
      final days = <int>[];
      for (var i = 0; i < 12; i++) {
        cursor = engine.nextDue(from: cursor, template: t);
        days.add(cursor.day);
      }
      // Every long month is back on the 31st. A carried-forward clamp would show 28 from February on.
      expect(days.where((d) => d == 31).length, greaterThanOrEqualTo(5));
      expect(days.contains(28), isTrue);
    });

    test('February is 29 in a leap year and 28 otherwise', () {
      expect(engine.clampDayOfMonth(31, 2028, 2), 29);
      expect(engine.clampDayOfMonth(31, 2026, 2), 28);
      expect(engine.clampDayOfMonth(30, 2026, 4), 30);
      expect(engine.clampDayOfMonth(15, 2026, 2), 15);
    });

    test('a day and week interval never clamps', () {
      final weekly = template(
        unit: RecurringIntervalUnit.week,
        anchorDayOfMonth: null,
      );
      expect(
        engine.nextDue(from: const DateKey(20260129), template: weekly),
        const DateKey(20260205),
      );
      final daily = template(
        unit: RecurringIntervalUnit.day,
        intervalCount: 3,
        anchorDayOfMonth: null,
      );
      expect(
        engine.nextDue(from: const DateKey(20260227), template: daily),
        const DateKey(20260302),
      );
    });

    test('a yearly interval keeps its month and clamps its day', () {
      final yearly = template(
        unit: RecurringIntervalUnit.year,
        anchorDayOfMonth: 29,
        start: const DateKey(20280229),
      );
      // 29 February 2028 exists; 2029 does not have one.
      expect(
        engine.nextDue(from: const DateKey(20280229), template: yearly),
        const DateKey(20290228),
      );
    });
  });

  group('the builder', () {
    TemplateBuilderState state({
      DateKey start = const DateKey(20260301),
      int? anchor,
      RecurringIntervalUnit unit = RecurringIntervalUnit.month,
    }) => TemplateBuilderState(
      currencyCode: 'INR',
      startDateKey: start,
      name: 'Rent',
      amount: const Money(120000, 'INR'),
      intervalUnit: unit,
      anchorDayOfMonth: anchor ?? start.day,
    );

    test('the anchor follows the start date while it still matches it', () {
      // The bug this pins: the builder seeds the anchor from today, so moving the start date left the
      // anchor on an unrelated day and the second occurrence landed nowhere near the first.
      final before = state(start: const DateKey(20260301));
      expect(before.anchorDayOfMonth, 1);
      final follows = before.anchorDayOfMonth == before.startDateKey.day;
      expect(follows, isTrue);
    });

    test(
      'an anchor the user chose is not overwritten by a start-date change',
      () {
        final chosen = state(start: const DateKey(20260301), anchor: 15);
        final follows = chosen.anchorDayOfMonth == chosen.startDateKey.day;
        // 15 is not 1, so the anchor was deliberate and must survive.
        expect(follows, isFalse);
      },
    );

    test('a monthly template is incomplete without a day anchor', () {
      const bare = TemplateBuilderState(
        currencyCode: 'INR',
        startDateKey: DateKey(20260301),
        name: 'Rent',
        amount: Money(120000, 'INR'),
      );
      expect(bare.needsDayAnchor, isTrue);
      expect(bare.isComplete, isFalse);
      expect(bare.copyWith(anchorDayOfMonth: 1).isComplete, isTrue);
    });

    test('a weekly template needs no anchor to be complete', () {
      const weekly = TemplateBuilderState(
        currencyCode: 'INR',
        startDateKey: DateKey(20260301),
        name: 'Gym',
        amount: Money(50000, 'INR'),
        intervalUnit: RecurringIntervalUnit.week,
      );
      expect(weekly.needsDayAnchor, isFalse);
      expect(weekly.isComplete, isTrue);
    });

    test(
      'a new template is first due on its start date, not one interval later',
      () {
        final t = state(start: const DateKey(20260315), anchor: 15).toTemplate(
          newId: 'tpl-9',
          normalizedName: 'rent',
          nextDue: const DateKey(20260315),
        );
        // Materialisation walks from `nextDueDateKey` inclusive, so seeding it with the start date is
        // what makes the first occurrence appear on the day the user chose.
        expect(t.nextDueDateKey, t.startDateKey);
      },
    );
  });

  group('an end date', () {
    test('stops the schedule rather than being ignored', () {
      final t = template(end: const DateKey(20260315));
      final feb = engine.nextDue(from: const DateKey(20260131), template: t);
      final mar = engine.nextDue(from: feb, template: t);
      expect(feb.isAfter(t.endDateKey!), isFalse);
      // March 31 is past the 15 March end, so a materialiser walking this must stop before it.
      expect(mar.isAfter(t.endDateKey!), isTrue);
    });
  });
}
```

### `test/features/recurring/occurrence_history_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/features/recurring/presentation/screens/occurrence_history_screen.dart';
import 'package:alaya/features/recurring/providers/occurrence_history_providers.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/features/recurring/providers/template_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_timeline.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/recurring_harness.dart';

/// Four states, plus the §7.2 row: the actual against the usual, where they differ.
void main() {
  const templateId = 'tpl-1';

  List<Override> overrides({
    RecurringTemplate? template,
    List<RecurringOccurrence>? occurrences,
    bool pending = false,
    bool fail = false,
  }) => [
    clockProvider.overrideWithValue(kRecurringClock),
    builderDecimalDigitsProvider.overrideWith((ref) async => 2),
    historyTemplateProvider(
      templateId,
    ).overrideWith((ref) async => template ?? billTemplate()),
    if (pending)
      occurrencesProvider(
        templateId,
      ).overrideWith((ref) => pendingStream<List<RecurringOccurrence>>())
    else if (fail)
      occurrencesProvider(templateId).overrideWith(
        (ref) => Stream<List<RecurringOccurrence>>.error(StateError('boom')),
      )
    else
      occurrencesProvider(
        templateId,
      ).overrideWith((ref) => Stream.value(occurrences ?? const [])),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(pending: true),
    );
    await tester.pump();
    expect(find.byType(AlayaListSkeleton), findsWidgets);
  });

  testWidgets('empty states plainly that nothing is ever paid for you', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    // Anomaly A14 said out loud: materialisation creates due rows, never payments.
    expect(find.textContaining('Nothing is ever paid for you'), findsOneWidget);
  });

  testWidgets('error shows the real reason with a retry', (tester) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(fail: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('populated renders a timeline of occurrences', (tester) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(
        occurrences: [
          occurrence(
            id: 'o1',
            dueDateKey: const DateKey(20260630),
            status: RecurringOccurrenceStatus.paid,
            paidMinor: 120000,
            paidTransactionId: 't1',
          ),
          occurrence(id: 'o2', dueDateKey: const DateKey(20260731)),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaTimeline), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
  });

  testWidgets('a payment that differed from the usual amount is marked', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(
        occurrences: [
          occurrence(
            id: 'o1',
            dueDateKey: const DateKey(20260630),
            status: RecurringOccurrenceStatus.paid,
            // Template default is 1,200.00; this one came in at 1,247.00.
            paidMinor: 124700,
            paidTransactionId: 't1',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Differed from the usual amount'), findsWidgets);
  });

  testWidgets('a payment at the usual amount is not marked', (tester) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(
        occurrences: [
          occurrence(
            id: 'o1',
            dueDateKey: const DateKey(20260630),
            status: RecurringOccurrenceStatus.paid,
            paidMinor: 120000,
            paidTransactionId: 't1',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Differed from the usual amount'), findsNothing);
  });

  testWidgets('a skipped occurrence reads as skipped, not as paid', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(
        occurrences: [
          occurrence(
            id: 'o1',
            dueDateKey: const DateKey(20260630),
            status: RecurringOccurrenceStatus.skipped,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Skipped'), findsOneWidget);
    expect(find.text('Paid'), findsNothing);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(
        occurrences: [
          occurrence(
            id: 'o1',
            dueDateKey: const DateKey(20260630),
            status: RecurringOccurrenceStatus.paid,
            paidMinor: 124700,
            paidTransactionId: 't1',
          ),
          occurrence(id: 'o2', dueDateKey: const DateKey(20260715)),
        ],
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(
        occurrences: [
          occurrence(id: 'o2', dueDateKey: const DateKey(20260731)),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/recurring/pay_sheet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/recurring/presentation/sheets/pay_sheet.dart';
import 'package:alaya/features/recurring/providers/pay_providers.dart';
import 'package:alaya/features/recurring/state/pay_state.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

import '../../support/recurring_harness.dart';

/// The capture path: the default is pre-filled, the actual is editable, and both are kept.
void main() {
  /// A fixed-length override list.
  ///
  /// The length must not vary between scopes — a conditional entry is what produced *"Tried to change
  /// the number of overrides"*. `seed` defaults to the state the notifier would build anyway.
  List<Override> overrides({PayState? seed}) => [
    clockProvider.overrideWithValue(kRecurringClock),
    payAccountsProvider.overrideWith((ref) => Stream.value(const [kAccount])),
    payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
    payProvider.overrideWith(
      () => _StubPay(
        seed ??
            PayState(
              occurrenceId: 'occ-1',
              defaultAmount: const Money(120000, 'INR'),
              amount: const Money(120000, 'INR'),
              paidOn: kToday,
              accountId: kAccount.id,
            ),
      ),
    ),
  ];

  Widget host() => Scaffold(
    body: AlayaBottomSheet(
      child: PaySheet(occurrenceId: 'occ-1', template: billTemplate()),
    ),
  );

  testWidgets('opens with the usual amount already filled in', (tester) async {
    await pumpRecurring(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    // The common case is that it cost what it usually costs, so that path is one tap.
    expect(find.byType(AmountField), findsOneWidget);
    expect(find.text('Amount actually paid'), findsOneWidget);
  });

  testWidgets('an inflow asks what was received, not what was paid', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      Scaffold(
        body: AlayaBottomSheet(
          child: PaySheet(occurrenceId: 'occ-2', template: salaryTemplate()),
        ),
      ),
      overrides: [
        clockProvider.overrideWithValue(kRecurringClock),
        payAccountsProvider.overrideWith(
          (ref) => Stream.value(const [kAccount]),
        ),
        payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Record this receipt'), findsOneWidget);
    expect(find.text('Amount actually received'), findsOneWidget);
  });

  // **Two tests, not two pumps.** A second `pumpWidget` in one `testWidgets` reuses the same
  // `ProviderScope`, so a differing override count throws *"Tried to change the number of
  // overrides"* — and even with a matching count the scope updates rather than replaces, so the new
  // override silently never installs and the test passes for the wrong reason (ARCH_4 P5).
  testWidgets('the usual figure is hidden while the actual matches it', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: overrides(
        seed: PayState(
          occurrenceId: 'occ-1',
          defaultAmount: const Money(120000, 'INR'),
          amount: const Money(120000, 'INR'),
          paidOn: kToday,
          accountId: kAccount.id,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Repeating the default under an unchanged figure is noise.
    expect(find.text('Usually'), findsNothing);
  });

  testWidgets('the usual figure appears once the actual differs', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: overrides(
        seed: PayState(
          occurrenceId: 'occ-1',
          defaultAmount: const Money(120000, 'INR'),
          amount: const Money(124700, 'INR'),
          paidOn: kToday,
          accountId: kAccount.id,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Beside a changed one it confirms the change was deliberate.
    expect(find.text('Usually'), findsOneWidget);
  });

  testWidgets('a missing amount shakes rather than writing zero', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: overrides(
        seed: PayState(
          occurrenceId: 'occ-1',
          defaultAmount: const Money(120000, 'INR'),
          paidOn: kToday,
          accountId: kAccount.id,
          issue: PayIssue.amountMissing,
          shakeTrigger: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ShakeOnError), findsOneWidget);
    expect(find.text('Enter an amount'), findsOneWidget);
  });

  testWidgets('a missing account is named, not reported generically', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: overrides(
        seed: PayState(
          occurrenceId: 'occ-1',
          defaultAmount: const Money(120000, 'INR'),
          amount: const Money(120000, 'INR'),
          paidOn: kToday,
          issue: PayIssue.accountMissing,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose which account it came from'), findsOneWidget);
  });

  testWidgets('loading accounts still lets the amount be typed', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: [
        clockProvider.overrideWithValue(kRecurringClock),
        payAccountsProvider.overrideWith(
          (ref) => pendingStream<List<Account>>(),
        ),
        payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
      ],
    );
    await tester.pump();
    // A capture sheet takes its first keystroke on its first frame (§5.2): the account list is still
    // arriving and the amount field is already there, pre-filled.
    expect(find.byType(AmountField), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });

  testWidgets('no accounts at all omits the picker rather than blocking', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: [
        clockProvider.overrideWithValue(kRecurringClock),
        payAccountsProvider.overrideWith(
          (ref) => Stream.value(const <Account>[]),
        ),
        payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed account stream does not take the sheet down', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: [
        clockProvider.overrideWithValue(kRecurringClock),
        payAccountsProvider.overrideWith(
          (ref) => Stream<List<Account>>.error(StateError('boom')),
        ),
        payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
      ],
    );
    await tester.pumpAndSettle();
    // The template carries a default account, so a failed lookup costs the picker, not the payment.
    expect(find.byType(AmountField), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Record it'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpRecurring(tester, host(), overrides: overrides(), textScale: 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpRecurring(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('state', () {
    test('differsFromDefault is false until the figure changes', () {
      const base = PayState(
        occurrenceId: 'occ-1',
        defaultAmount: Money(120000, 'INR'),
        amount: Money(120000, 'INR'),
        paidOn: kToday,
      );
      expect(base.differsFromDefault, isFalse);
      expect(
        base.copyWith(amount: const Money(124700, 'INR')).differsFromDefault,
        isTrue,
      );
    });

    test('an issue survives an unrelated copyWith', () {
      const base = PayState(
        occurrenceId: 'occ-1',
        defaultAmount: Money(120000, 'INR'),
        paidOn: kToday,
        issue: PayIssue.accountMissing,
      );
      // ARCH_4 R31: a bare assignment let `submitting: false` in a `finally` erase the reason
      // microseconds before the sheet read it. It must survive, and clear only when asked.
      expect(base.copyWith(submitting: false).issue, PayIssue.accountMissing);
      expect(base.copyWith(clearIssue: true).issue, isNull);
    });
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubPay extends PayNotifier {
  _StubPay(this._value);

  final PayState _value;

  @override
  PayState build(PayArgs arg) => _value;
}
```

### `test/features/recurring/template_builder_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/services/recurring_engine.dart';
import 'package:alaya/features/recurring/presentation/screens/template_builder_screen.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/features/recurring/state/template_builder_state.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/frequency_preview.dart';

import '../../support/recurring_harness.dart';

/// Four states, plus the reason this screen exists: the preview is the only way a user can see a clamp.
void main() {
  TemplateBuilderState state({
    String name = 'Rent',
    int? amountMinor = 120000,
    RecurringIntervalUnit unit = RecurringIntervalUnit.month,
    int? anchorDayOfMonth = 31,
    DateKey start = const DateKey(20260131),
    DateKey? end,
    TemplateSaveIssue? issue,
    String? rejection,
  }) => TemplateBuilderState(
    currencyCode: 'INR',
    startDateKey: start,
    name: name,
    amount: amountMinor == null ? null : Money(amountMinor, 'INR'),
    intervalUnit: unit,
    anchorDayOfMonth: anchorDayOfMonth,
    endDateKey: end,
    issue: issue,
    rejection: rejection,
  );

  // The override goes on the **family**: a NotifierProvider family instance has no `overrideWith`.
  List<Override> overrides(AsyncValue<TemplateBuilderState> value) => [
    templateBuilderProvider.overrideWith(() => _StubBuilder(value)),
    builderDecimalDigitsProvider.overrideWith((ref) async => 2),
    builderAccountsProvider.overrideWith(
      (ref) => Stream.value(const [kAccount]),
    ),
    recurringEngineProvider.overrideWithValue(const RecurringEngine()),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('error reads as not found', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('a new template opens on the form, which is its empty state', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(AsyncValue.data(state(name: '', amountMinor: null))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
  });

  testWidgets('the preview shows the anchor clamping and returning', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    // Anchored on the 31st from 31 January: Jan 31 → Feb 28 → Mar 31. February is shortened and March
    // returns to the 31st — the anchor never walks backwards (anomaly A13), and this is the only place
    // a user can see that happening.
    expect(find.byType(FrequencyPreview), findsOneWidget);
    expect(find.text('Shortened to fit the month'), findsOneWidget);
  });

  testWidgets('a weekly template never reports a clamp', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(unit: RecurringIntervalUnit.week, anchorDayOfMonth: null),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Only a monthly or yearly interval anchors to a day, so there is nothing to clamp.
    expect(find.text('Shortened to fit the month'), findsNothing);
    expect(find.text('On day of the month'), findsNothing);
  });

  testWidgets('an incomplete template previews nothing rather than a guess', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(AsyncValue.data(state(name: '', amountMinor: null))),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Set a start date to see when this lands.'),
      findsOneWidget,
    );
  });

  testWidgets('an end date truncates the preview instead of promising three', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(
        AsyncValue.data(state(end: const DateKey(20260215))),
      ),
    );
    await tester.pumpAndSettle();
    // Ends mid-February, so only 31 January survives. Showing three would describe a schedule that
    // will not happen.
    expect(find.byType(FrequencyPreview), findsOneWidget);
    expect(find.text('Shortened to fit the month'), findsNothing);
  });

  testWidgets('a rejection is shown in the repository own words', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(
            issue: TemplateSaveIssue.rejected,
            rejection:
                'A monthly template needs a day of the month to anchor to.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('needs a day of the month'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(AsyncValue.data(state())),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('the clamp itself', () {
    const engine = RecurringEngine();

    test(
      'an anchor of 31 lands on the last day of a short month and then returns',
      () {
        final template = billTemplate(nextDue: const DateKey(20260131));
        final feb = engine.nextDue(
          from: const DateKey(20260131),
          template: template,
        );
        final mar = engine.nextDue(from: feb, template: template);
        expect(feb, const DateKey(20260228));
        // The point of storing the anchor rather than advancing it: March returns to the 31st instead of
        // inheriting February's 28 forever.
        expect(mar, const DateKey(20260331));
      },
    );

    test('a February anchor survives a leap year', () {
      expect(engine.clampDayOfMonth(31, 2028, 2), 29);
      expect(engine.clampDayOfMonth(31, 2026, 2), 28);
      expect(engine.clampDayOfMonth(15, 2026, 2), 15);
    });
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubBuilder extends TemplateBuilderNotifier {
  _StubBuilder(this._value);

  final AsyncValue<TemplateBuilderState> _value;

  @override
  AsyncValue<TemplateBuilderState> build(String? arg) => _value;
}
```

### `test/features/recurring/template_list_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/features/recurring/presentation/screens/template_list_screen.dart';
import 'package:alaya/features/recurring/presentation/widgets/template_row.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/features/recurring/providers/template_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/recurring_harness.dart';

/// Four states, 320dp at a doubled text scale, and both accessibility floors (ARCH_5 §9.1).
void main() {
  List<Override> overrides(AsyncValue<List<TemplateGroup>> groups) => [
    clockProvider.overrideWithValue(kRecurringClock),
    templateGroupsProvider.overrideWith((ref) => groups),
    overdueCountProvider.overrideWith((ref) => 0),
    builderDecimalDigitsProvider.overrideWith((ref) async => 2),
  ];

  final outflow = AsyncValue.data([
    TemplateGroup(
      direction: RecurringDirection.outflow,
      rows: [TemplateRow(template: billTemplate(), next: occurrence())],
    ),
  ]);

  testWidgets('loading shows a skeleton, not a spinner', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('empty invites the first template', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(const AsyncValue.data([])),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nothing recurring yet'), findsOneWidget);
  });

  testWidgets('error shows the real reason with a retry', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('populated groups outflow under its own header', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(outflow),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TemplateRowTile), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Expenses'), findsOneWidget);
  });

  testWidgets('an inflow reads as income, not a negative bill', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(
        AsyncValue.data([
          TemplateGroup(
            direction: RecurringDirection.inflow,
            rows: [
              TemplateRow(
                template: salaryTemplate(),
                next: occurrence(id: 'occ-2', templateId: 'tpl-2'),
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    // Its own group, and the amount unsigned. A salary shown as minus eighty-five thousand under a
    // list of bills is the §7.2 row this module exists to close.
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);
    expect(find.textContaining('-'), findsNothing);
  });

  testWidgets('overdue is derived from the clock, not a stored flag', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(
        AsyncValue.data([
          TemplateGroup(
            direction: RecurringDirection.outflow,
            rows: [
              TemplateRow(
                template: billTemplate(),
                // Due in July, clock fixed to 1 August. Nothing on the entity says "overdue".
                next: occurrence(dueDateKey: const DateKey(20260715)),
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Overdue'), findsWidgets);
  });

  testWidgets('a paused template says so and offers no pay button', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(
        AsyncValue.data([
          TemplateGroup(
            direction: RecurringDirection.outflow,
            rows: [
              TemplateRow(
                template: billTemplate(isPaused: true),
                next: occurrence(),
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    // Nothing is paid while paused: an occurrence may exist, but the obligation is suspended.
    expect(find.widgetWithText(FilledButton, 'Record it'), findsNothing);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(
        AsyncValue.data([
          TemplateGroup(
            direction: RecurringDirection.outflow,
            rows: [
              TemplateRow(
                template: billTemplate(),
                next: occurrence(dueDateKey: const DateKey(20260715)),
              ),
            ],
          ),
        ]),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(outflow),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```
