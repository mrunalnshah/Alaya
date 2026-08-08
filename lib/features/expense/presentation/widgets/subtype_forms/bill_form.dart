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
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/features/recurring/providers/bill_account_providers.dart';
import 'package:alaya/features/recurring/providers/due_bills_providers.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// The bill payment sub-form.
///
/// A bill paid off-template is an ordinary withdrawal with `subtype = bill` and a null
/// `recurringTemplateId` — which is why this form never requires a template. Paying a bill you never
/// set up must not be harder than paying one you did.
///
/// **Selecting a due bill links this payment to it; it does not pay it here.** An earlier version
/// opened the pay sheet from this list, which left two write paths reachable at once: the sheet
/// recorded one transaction and then saving the editor recorded a second for the same payment. There
/// is now one amount field and one save — picking a bill routes that save through `payOccurrence`,
/// which settles the occurrence and writes the transaction together.
class BillForm extends ConsumerWidget {
  /// Creates the form.
  const BillForm({required this.editorId, required this.state, super.key});

  /// The editor family argument.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(transactionEditorProvider(editorId).notifier);
    final due = ref.watch(dueBillsProvider);
    final today = ref.watch(clockProvider).today();
    final digits = ref.watch(builderDecimalDigitsProvider).valueOrNull ?? 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PayeeField(editorId: editorId, selectedId: state.payeeId),
        SectionHeader(
          label: strings.billDueSection,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.xl,
            bottom: AlayaSpacing.xs,
          ),
        ),
        due.when(
          // A failed or pending schedule read costs the shortcut, never the ability to record a bill
          // by hand — which is what this form does without any of this.
          loading: () => Text(
            strings.loadingRecurring,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          error: (error, stack) => Text(
            error.toString(),
            style: AlayaTypography.caption.copyWith(color: semantic.danger),
          ),
          data: (rows) => rows.isEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.billNothingDue,
                      style: AlayaTypography.caption.copyWith(
                        color: semantic.muted,
                      ),
                    ),
                    const SizedBox(height: AlayaSpacing.xs),
                    TextButton.icon(
                      onPressed: () => context.push(Routes.recurringNew),
                      icon: const Icon(
                        Icons.event_repeat,
                        size: AlayaIconSize.sm,
                      ),
                      label: Text(strings.billSetUpAction),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      strings.billSettleHelp,
                      style: AlayaTypography.caption.copyWith(
                        color: semantic.muted,
                      ),
                    ),
                    const SizedBox(height: AlayaSpacing.xs),
                    RadioGroup<String?>(
                      groupValue: state.recurringOccurrenceId,
                      onChanged: (value) {
                        if (value == null) {
                          notifier.setRecurringOccurrence();
                          return;
                        }
                        for (final row in rows) {
                          if (row.occurrence!.id != value) continue;
                          notifier.setRecurringOccurrence(
                            occurrenceId: value,
                            defaultAmount: row.template.defaultAmount,
                            accountId: ref.read(
                              resolvedBillAccountProvider(
                                row.template.defaultAccountId,
                              ),
                            ),
                          );
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          RadioListTile<String?>(
                            value: null,
                            contentPadding: EdgeInsets.zero,
                            title: Text(strings.billSettleNone),
                          ),
                          for (final row in rows)
                            RadioListTile<String?>(
                              value: row.occurrence!.id,
                              contentPadding: EdgeInsets.zero,
                              title: Text(row.template.name),
                              subtitle: Wrap(
                                spacing: AlayaSpacing.xs,
                                runSpacing: AlayaSpacing.xxs,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  AmountText(
                                    row.template.defaultAmount,
                                    size: AmountSize.small,
                                    showSign: false,
                                    decimalDigits: digits,
                                  ),
                                  DateText(
                                    row.occurrence!.dueDateKey,
                                    style: DateTextStyle.medium,
                                    muted: true,
                                  ),
                                  if (row.occurrence!.isOverdue(today))
                                    StatusChip(
                                      label: strings.recurringOverdue,
                                      tone: StatusTone.danger,
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (state.recurringOccurrenceId != null) ...[
                      const SizedBox(height: AlayaSpacing.xs),
                      Text(
                        strings.billAmountBecomesPaid,
                        style: AlayaTypography.caption.copyWith(
                          color: semantic.transfer,
                        ),
                      ),
                      // Only reached when the template, the app default and a sole account all failed
                      // to answer — so it is asked once and remembered on the bill, never per payment.
                      if (state.accountMissing) ...[
                        const SizedBox(height: AlayaSpacing.xs),
                        Text(
                          strings.billAccountAskOnce,
                          style: AlayaTypography.caption.copyWith(
                            color: semantic.danger,
                          ),
                        ),
                      ] else if (state.fromAccountId != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AlayaSpacing.xxs),
                          child: Text(
                            strings.billAccountAuto,
                            style: AlayaTypography.caption.copyWith(
                              color: semantic.muted,
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
}
