import 'package:alaya/core/money/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/time/date_key_labels.dart';
import 'package:alaya/domain/entities/split_expense.dart';
import 'package:alaya/features/split/providers/split_expense_actions.dart';
import 'package:alaya/features/split/providers/split_history_provider.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// What a split actually was: who paid, who owed what, and how it was decided.
///
/// **History was a list of amounts you could not open.** It said a bill happened and what it came to, and
/// nothing about who covered it, how it divided, or what anybody's share was — so the one screen that
/// remembers a split settled the same evening could not answer the question somebody opens it with.
///
/// **Both the resolved amount and the input that produced it are shown**, because the schema stores both
/// for exactly this. A 40/30/30 split reopens as 40/30/30 rather than as three amounts the reader has to
/// reverse-engineer — and where a share carries an extra, the sentence separates it: *"₹1,050 share + ₹800
/// just for them"*, because a total nobody can decompose is one they argue with.
class SplitExpenseDetailSheet extends ConsumerWidget {
  /// Creates the sheet.
  const SplitExpenseDetailSheet({required this.expenseId, super.key});

  /// The split being shown.
  final String expenseId;

  /// Opens the sheet for [expenseId].
  static Future<void> show(BuildContext context, {required String expenseId}) =>
      AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) => SplitExpenseDetailSheet(expenseId: expenseId),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final expense = ref.watch(splitExpenseProvider(expenseId));

    return expense.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AlayaSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: error.toString(),
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(splitExpenseProvider(expenseId)),
      ),
      data: (found) => found == null
          ? ErrorState(
              title: strings.errorTitleNotFound,
              body: strings.errorBodyNotFound,
            )
          : _Body(expense: found),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.expense});

  final SplitExpense expense;

  static String _methodLabel(AlayaStrings strings, SplitMethod method) =>
      switch (method) {
        SplitMethod.equal => strings.splitMethodEqual,
        SplitMethod.shares => strings.splitMethodShares,
        SplitMethod.percent => strings.splitMethodPercent,
        SplitMethod.exactAmounts => strings.splitMethodExact,
        SplitMethod.perLine => strings.splitMethodPerLine,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final digits = ref.watch(splitDecimalDigitsProvider).valueOrNull ?? 2;
    final self = ref.watch(splitSelfProvider).valueOrNull;
    final payer =
        ref.watch(splitPayeeNameProvider(expense.paidByPayeeId)) ??
        strings.splitUnknownPerson;

    final title = expense.title?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title == null || title.isEmpty ? strings.splitBillAction : title,
          style: AlayaTypography.sectionHeader,
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        Text(
          expense.dateKey.fullLabel,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),

        const SizedBox(height: AlayaSpacing.md),
        _Line(
          label: strings.splitDetailTotal,
          trailing: AmountText(
            expense.total,
            showSign: false,
            decimalDigits: digits,
          ),
        ),
        _Line(
          label: strings.splitDetailPaidBy,
          // **The fact the history list could not show.** Whether you fronted the money or somebody else
          // did decides which direction every share below points, and it is the first thing anybody
          // reopening a split wants to check.
          value: expense.paidByPayeeId == self ? strings.splitPaidByYou : payer,
        ),
        _Line(
          label: strings.splitDetailMethod,
          value: _methodLabel(strings, expense.splitMethod),
        ),
        if (expense.place case final place? when place.trim().isNotEmpty)
          _Line(label: strings.splitDetailPlace, value: place),
        if (expense.occasion case final occasion?
            when occasion.trim().isNotEmpty)
          _Line(label: strings.splitDetailOccasion, value: occasion),

        SectionHeader(
          label: strings.splitBillTheSplit,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.lg,
            bottom: AlayaSpacing.xs,
          ),
        ),
        for (final share in expense.shares)
          _ShareRow(share: share, total: expense.total, digits: digits),

        if (!expense.isFullyAllocated) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            // Reported, never absorbed — the same rule the editor follows. Rounding a shortfall onto
            // somebody charges them for a discrepancy nobody told them about.
            child: StatusChip(
              label: expense.unallocated.isNegative
                  ? strings.splitOverAllocated
                  : strings.splitUnallocated,
              tone: StatusTone.warning,
              trailing: AmountText(
                expense.unallocated.abs(),
                size: AmountSize.small,
                showSign: false,
                decimalDigits: digits,
              ),
            ),
          ),
        ],

        const SizedBox(height: AlayaSpacing.lg),
        Wrap(
          spacing: AlayaSpacing.sm,
          runSpacing: AlayaSpacing.xs,
          children: [
            FilledButton.tonalIcon(
              // **Editing reopens the bill screen with this split loaded**, and saving replaces rather than
              // duplicates: `SplitExpenseService.record` has taken an `id` since it was written, and no
              // screen ever passed one. Nothing new was needed underneath.
              onPressed: () {
                Navigator.of(context).pop();
                context.push(Routes.splitNew, extra: expense.id);
              },
              icon: const Icon(Icons.edit_outlined, size: AlayaIconSize.md),
              label: Text(strings.actionEdit),
            ),
            OutlinedButton.icon(
              onPressed: () => _delete(context, ref, strings),
              icon: const Icon(Icons.delete_outline, size: AlayaIconSize.md),
              label: Text(strings.actionDelete),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.splitDeleteConfirmTitle,
      // **Says what survives.** Deleting a split is a statement about who owed what, not about whether the
      // payment happened — any linked transaction stays in the ledger, because the money did move.
      body: strings.splitDeleteConfirmBody,
      confirmLabel: strings.actionDelete,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final ok = await ref
        .read(splitExpenseActionsProvider.notifier)
        .remove(expense.id);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.splitDeleted)
        : showFailureSnack(context, message: strings.errorBodyGeneric);
  }
}

/// One label-and-value line.
class _Line extends StatelessWidget {
  const _Line({required this.label, this.value, this.trailing});

  final String label;
  final String? value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Padding(
      padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
      // A `Wrap`, not a `Row`: a label beside a long value or an amount is the shape that overflows at
      // 320dp with the scaler doubled (Law U15).
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AlayaSpacing.sm,
        runSpacing: AlayaSpacing.xxs,
        children: [
          Text(
            label,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          trailing ?? Text(value ?? '', style: AlayaTypography.body),
        ],
      ),
    );
  }
}

/// One participant's share, with the input that produced it.
class _ShareRow extends ConsumerWidget {
  const _ShareRow({
    required this.share,
    required this.total,
    required this.digits,
  });

  final SplitShare share;
  final Money total;
  final int digits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final self = ref.watch(splitSelfProvider).valueOrNull;
    final name = share.payeeId == self
        ? strings.splitPaidByYou
        : ref.watch(splitPayeeNameProvider(share.payeeId)) ??
              strings.splitUnknownPerson;

    // **How it was decided, not just what it came to.** The schema stores the input beside the resolved
    // amount for this: a 40% share reopens as 40%, and an extra says it is an extra rather than hiding
    // inside a larger figure.
    final how = switch (share.inputKind) {
      ShareInputKind.equal => null,
      ShareInputKind.percent => strings.splitSharePercentOf(
        (share.inputValue ?? 0) / 100,
      ),
      ShareInputKind.shares => strings.splitShareWeightOf(
        share.inputValue ?? 1,
      ),
      ShareInputKind.exact => null,
      ShareInputKind.extra => strings.splitShareIsExtra,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AlayaSpacing.sm,
        runSpacing: AlayaSpacing.xxs,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: AlayaTypography.body),
              if (how != null)
                Text(
                  how,
                  style: AlayaTypography.caption.copyWith(
                    color: semantic.muted,
                  ),
                ),
            ],
          ),
          AmountText(share.amount, showSign: false, decimalDigits: digits),
        ],
      ),
    );
  }
}
