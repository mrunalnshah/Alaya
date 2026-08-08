import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/account_picker.dart';

/// The transfer sub-form — and the one place in this app where the copy has to be exact.
///
/// **"To my own account" and "To someone else" are different transaction kinds, not two phrasings
/// of one.** Moving ₹5,000 from Cash to Bank must not reduce net worth: it is `kind = transfer`,
/// it appears in both accounts' ledgers with opposite signs, and it nets to zero by construction.
/// Sending ₹5,000 to your brother is a real withdrawal with `subtype = transferOut` and a payee.
///
/// Getting this wrong is anomaly A02, and the symptom is a net worth that falls every time the user
/// moves their own money between their own accounts — a number they cannot explain and will not
/// trust again.
class TransferForm extends ConsumerWidget {
  /// Creates the form.
  const TransferForm({required this.editorId, required this.state, super.key});

  /// The editor family argument.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(transactionEditorProvider(editorId).notifier);
    final accounts =
        ref.watch(selectableAccountsProvider).valueOrNull ?? const <Account>[];

    Account? accountFor(String? id) {
      for (final account in accounts) {
        if (account.id == id) return account;
      }
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text(strings.transferOwnAccount)),
            ButtonSegment(
              value: false,
              label: Text(strings.transferSomeoneElse),
            ),
          ],
          selected: {state.toOwnAccount},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              notifier.setTransferTarget(toOwnAccount: selection.first),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Text(
          state.toOwnAccount
              ? strings.transferOwnAccountHelp
              : strings.transferSomeoneElseHelp,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.md),
        AccountPicker(
          accounts: accounts,
          selected: accountFor(state.fromAccountId),
          label: strings.labelFrom,
          hint: strings.hintSelectAccount,
          onChanged: (account) => notifier.setFromAccount(account.id),
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (state.toOwnAccount)
          AccountPicker(
            accounts: accounts,
            selected: accountFor(state.toAccountId),
            label: strings.labelTo,
            hint: strings.hintSelectAccount,
            // Excluded so a transfer cannot have the same account on both sides, which the
            // transactions CHECK constraint rejects anyway (ARCH_2 §4.1).
            excludeId: state.fromAccountId,
            onChanged: (account) => notifier.setToAccount(account.id),
          )
        else
          PayeeField(editorId: editorId, selectedId: state.payeeId),
      ],
    );
  }
}
