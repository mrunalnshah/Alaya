import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/account_picker.dart';

/// The deposit sub-form.
///
/// A deposit needs a destination account and no source — the mirror of a withdrawal, and the shape
/// the `transactions` CHECK constraint enforces (ARCH_2 §4.1). The payee is the *source* of the
/// money here rather than its recipient, which is why one `payees` table serves both directions.
class DepositForm extends ConsumerWidget {
  /// Creates the form.
  const DepositForm({required this.editorId, required this.state, super.key});

  /// The editor family argument.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final notifier = ref.read(transactionEditorProvider(editorId).notifier);
    final accounts =
        ref.watch(selectableAccountsProvider).valueOrNull ?? const <Account>[];

    Account? selected;
    for (final account in accounts) {
      if (account.id == state.toAccountId) {
        selected = account;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PayeeField(editorId: editorId, selectedId: state.payeeId),
        const SizedBox(height: AlayaSpacing.md),
        AccountPicker(
          accounts: accounts,
          selected: selected,
          label: strings.labelTo,
          hint: strings.hintSelectAccount,
          onChanged: (account) => notifier.setToAccount(account.id),
        ),
      ],
    );
  }
}
