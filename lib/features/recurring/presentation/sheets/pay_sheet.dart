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
            autofocus: true,
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
