import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/presentation/sheets/line_item_editor.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Everything on one receipt, in one place (ARCH_5 §3 archetype D).
///
/// **A page rather than a sheet per line.** Itemising a fifteen-line grocery receipt through
/// `LineItemEditor` alone meant fifteen open-close cycles with no view of what had been entered, no
/// running total, and no way to correct line three without starting over. This keeps the list, the
/// figures and the add action on screen together; the sheet is still what edits one line, reached from
/// here. `LineItemDraft.addAnother` lets the sheet stay open across a whole receipt.
///
/// **It edits the editor's state, and writes nothing.** The lines belong to
/// `transactionEditorProvider`, which stays alive because the editor screen remains mounted beneath
/// this route — so Done simply pops, and nothing is committed until the user saves the transaction.
class LineItemsScreen extends ConsumerWidget {
  /// Shows the lines of [transactionId], or of a new transaction when null.
  const LineItemsScreen({this.transactionId, super.key});

  /// Which transaction's lines to show.
  final String? transactionId;

  Future<void> _addMany(
    BuildContext context,
    WidgetRef ref,
    TransactionEditorState state,
    int digits,
  ) async {
    final notifier = ref.read(transactionEditorProvider(transactionId).notifier);
    var another = true;
    while (another && context.mounted) {
      final draft = await LineItemEditor.show(
        context,
        currencyCode: state.currencyCode,
        decimalDigits: digits,
        defaultDestination: TransactionLineDestination.none,
      );
      if (draft == null) return;
      notifier.upsertLine(draft.line);
      another = draft.addAnother;
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    TransactionEditorState state,
    TransactionLine line,
    int digits,
  ) async {
    final draft = await LineItemEditor.show(
      context,
      currencyCode: state.currencyCode,
      decimalDigits: digits,
      defaultDestination: line.destination,
      line: line,
    );
    if (draft == null) return;
    ref.read(transactionEditorProvider(transactionId).notifier).upsertLine(draft.line);
  }

  void _remove(BuildContext context, WidgetRef ref, TransactionLine line) {
    final strings = AlayaStrings.of(context);
    ref.read(transactionEditorProvider(transactionId).notifier).removeLine(line.id);
    // No undo offered: nothing has been written, so re-adding the line is the same two taps that
    // created it, and a snack promising undo for an uncommitted edit would be lying (§5.4).
    showResultSnack(context, message: strings.lineRemoved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(transactionEditorProvider(transactionId));
    final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2;

    return Scaffold(
      appBar: AppBar(title: Text(strings.lineItemsTitle)),
      body: async.when(
        loading: () => AlayaListSkeleton(label: strings.loadingLabel),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(transactionEditorProvider(transactionId)),
        ),
        data: (state) => Column(
          children: [
            _Summary(state: state, decimalDigits: digits),
            Expanded(
              child: state.lines.isEmpty
                  ? EmptyState(
                      title: strings.emptyTitleNoLineItems,
                      body: strings.emptyBodyNoLineItems,
                      icon: Icons.receipt_long_outlined,
                      actionLabel: strings.lineItemsAdd,
                      onAction: () => _addMany(context, ref, state, digits),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
                      itemCount: state.lines.length,
                      itemBuilder: (context, index) {
                        final line = state.lines[index];
                        return _LineTile(
                          line: line,
                          decimalDigits: digits,
                          onTap: () => _edit(context, ref, state, line, digits),
                          onRemove: () => _remove(context, ref, line),
                        );
                      },
                    ),
            ),
            SafeArea(
              minimum: const EdgeInsets.all(AlayaSpacing.screenEdge),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.lines.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => _addMany(context, ref, state, digits),
                      icon: const Icon(Icons.add, size: AlayaIconSize.md),
                      label: Text(strings.lineItemsAdd),
                    ),
                  const SizedBox(height: AlayaSpacing.xs),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(strings.actionDone),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.state, required this.decimalDigits});

  final TransactionEditorState state;
  final int decimalDigits;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final unallocated = state.unallocated;
    final allocated = state.lineTotal;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.sm,
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
      ),
      child: Wrap(
        spacing: AlayaSpacing.sm,
        runSpacing: AlayaSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            strings.lineItemsCount(state.lines.length),
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          if (allocated != null)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AlayaSpacing.xxs,
              children: [
                Text(
                  strings.lineItemsAllocated,
                  style: AlayaTypography.caption.copyWith(color: semantic.muted),
                ),
                AmountText(
                  allocated,
                  size: AmountSize.small,
                  showSign: false,
                  decimalDigits: decimalDigits,
                ),
              ],
            ),
          if (unallocated != null && !unallocated.isZero)
            StatusChip(
              label: strings.statusUnallocated,
              tone: StatusTone.warning,
              trailing: AmountText(
                unallocated.abs(),
                size: AmountSize.small,
                showSign: false,
                decimalDigits: decimalDigits,
              ),
            ),
        ],
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.decimalDigits,
    required this.onTap,
    required this.onRemove,
  });

  final TransactionLine line;
  final int decimalDigits;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final amount = line.lineAmount;
    final quantity = line.quantity;

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlayaSpacing.screenEdge,
            vertical: AlayaSpacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.description,
                      style: AlayaTypography.body
                          .copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    // Quantity, amount and destination all wrap together: at a doubled text scale a
                    // Row of them would starve the description beside it (Law U21).
                    const SizedBox(height: AlayaSpacing.xxs),
                    Wrap(
                      spacing: AlayaSpacing.xs,
                      runSpacing: AlayaSpacing.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (quantity != null) QtyText(quantity, muted: true),
                        if (amount != null)
                          AmountText(
                            amount,
                            size: AmountSize.small,
                            showSign: false,
                            decimalDigits: decimalDigits,
                          ),
                        if (line.destination == TransactionLineDestination.inventory)
                          StatusChip(
                            label: strings.destinationInventory,
                            icon: Icons.inventory_2_outlined,
                          ),
                        if (line.destination == TransactionLineDestination.asset)
                          StatusChip(
                            label: strings.destinationAsset,
                            icon: Icons.build_outlined,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRemove,
                tooltip: strings.actionRemove,
                icon: Icon(
                  Icons.close,
                  size: AlayaIconSize.md,
                  color: semantic.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
