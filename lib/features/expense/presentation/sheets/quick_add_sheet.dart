import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/expense/providers/quick_add_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// Captures a transaction in one field (ARCH_5 §3 archetype A).
///
/// **The amount is the only required field, and everything else is a chip.** This sheet is used at a
/// till, one-handed, in under eight seconds — a column of dropdowns would make it a form nobody
/// fills in at a checkout, and the row would simply not get recorded. Every other field has a
/// defensible default and the row is saved `needsReview`, which is what makes the shortcut honest
/// rather than lossy (Law U11, ARCH_5 §7.2).
///
/// Chips rather than pickers for the same reason: a chip row shows the current choice *and* the
/// likely alternatives without a tap, where a dropdown hides both behind one.
class QuickAddSheet extends ConsumerWidget {
  /// Creates the sheet. Prefer [show].
  const QuickAddSheet({super.key});

  /// Opens the sheet.
  static Future<void> show(BuildContext context) => AlayaBottomSheet.show<void>(
    context: context,
    builder: (context) => const QuickAddSheet(),
  );

  Future<void> _save(
    BuildContext context,
    WidgetRef ref, {
    required bool thenEdit,
  }) async {
    final strings = AlayaStrings.of(context);
    final navigator = Navigator.of(context);
    final messengerContext = context;
    final created = await ref.read(quickAddProvider.notifier).submit();
    if (created == null) return;
    if (navigator.canPop()) navigator.pop();
    if (!messengerContext.mounted) return;

    if (thenEdit) {
      messengerContext.push(Routes.transactionEdit(created.id));
      return;
    }
    showUndoSnack(
      messengerContext,
      message: strings.actionSaved,
      undoLabel: strings.actionUndo,
      onUndo: () => ref.read(quickAddProvider.notifier).undo(created.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(quickAddProvider);
    final notifier = ref.read(quickAddProvider.notifier);
    final currency = ref.watch(homeCurrencyCodeProvider).valueOrNull ?? 'INR';
    final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2;
    final accounts =
        ref.watch(selectableAccountsProvider).valueOrNull ?? const <Account>[];
    final tags = ref.watch(quickAddTagsProvider).valueOrNull ?? const <Tag>[];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.quickAddTitle,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        SegmentedButton<TransactionKind>(
          segments: [
            ButtonSegment(
              value: TransactionKind.withdrawal,
              label: Text(strings.quickAddMoneyOut),
            ),
            ButtonSegment(
              value: TransactionKind.deposit,
              label: Text(strings.quickAddMoneyIn),
            ),
          ],
          selected: {state.kind},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => notifier.setKind(selection.first),
        ),
        const SizedBox(height: AlayaSpacing.md),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: AmountField(
            currencyCode: currency,
            decimalDigits: digits,
            autofocus: true,
            label: strings.labelAmount,
            errorText: state.amountMissing ? strings.errorAmountInvalid : null,
            onChanged: notifier.setAmount,
          ),
        ),
        if (accounts.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.md),
          _ChipRow(
            label: strings.labelAccount,
            children: [
              for (final account in accounts)
                _Choice(
                  label: account.name,
                  selected: state.accountId == account.id,
                  onTap: () => notifier.setAccount(account.id),
                ),
            ],
          ),
        ],
        if (tags.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.md),
          _ChipRow(
            label: strings.labelTags,
            children: [
              for (final tag in tags)
                TagChip(
                  tag: tag,
                  selected: state.tagId == tag.id,
                  onTap: () => notifier.toggleTag(tag.id),
                ),
            ],
          ),
        ],
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: state.submitting
              ? null
              : () => _save(context, ref, thenEdit: false),
          child: Text(strings.quickAddSave),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: state.submitting
              ? null
              : () => _save(context, ref, thenEdit: true),
          child: Text(strings.actionAddDetails),
        ),
      ],
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AlayaTypography.label.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: children,
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
  );
}
