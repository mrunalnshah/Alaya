import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/expense/presentation/sheets/split_sheet.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

/// The "who owes for this" section of the transaction editor.
///
/// **Built on `LineItemsSection`'s shape, not beside it.** That widget already solved this exact
/// problem for line items — a summary in the editor, a sheet for the detail, and a chip for what does
/// not add up — and its own doc records the rule this section inherits:
///
/// > The unallocated chip is **never auto-balanced**. The transaction amount is the source of truth
/// > and the lines are optional detail; forcing them equal would invent a line the user did not buy
/// > (anomaly A11).
///
/// Shares are the same problem with different nouns. Percentages that reach 90%, or a tip nobody
/// assigned, leave a remainder — and quietly rounding it onto the last participant would charge
/// somebody for a discrepancy nobody told them about.
///
/// **Not a second `AlayaDisclosure`.** `TransactionEditorScreen` carries a pointed comment about Law
/// U16 — *"one door, not five collapsed sections… eleven controls at once is what made this screen
/// hard to read"* — so this sits inline with a summary and puts its controls behind a sheet, which is
/// where line items already put theirs.
class SplitSection extends ConsumerWidget {
  /// Creates the section for [state].
  const SplitSection({
    required this.editorId,
    required this.state,
    required this.decimalDigits,
    super.key,
  });

  /// The editor family argument, so the section writes to the right notifier.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final draft = await SplitSheet.show(
      context,
      total: state.amount,
      decimalDigits: decimalDigits,
      draft: state.split,
    );
    if (draft == null) return;
    ref
        .read(transactionEditorProvider(editorId).notifier)
        .setSplit(
          draft.isActive ? draft : null,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final split = state.split;
    final resolution = split?.resolve(state.amount);
    final people =
        ref.watch(splitParticipantsProvider).valueOrNull ?? const <Payee>[];

    String nameOf(String payeeId) {
      for (final payee in people) {
        if (payee.id == payeeId) return payee.name;
      }
      // A payee deleted while the editor was open. Better than a blank row, and rare enough that a
      // generic label is the right cost.
      return strings.splitUnknownPerson;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: strings.splitSectionHeader,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.xl,
            bottom: AlayaSpacing.xs,
          ),
        ),

        if (resolution == null)
          // **Says what it does before it is used.** A bare "Split" button gives no account of itself,
          // and this is the one section of the editor whose purpose is not obvious from its label.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: state.amount == null
                  ? null
                  : () => _edit(context, ref),
              icon: const Icon(
                Icons.group_add_outlined,
                size: AlayaIconSize.md,
              ),
              label: Text(strings.splitAdd),
            ),
          )
        else ...[
          for (final share in resolution.shares)
            AlayaCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AlayaSpacing.sm,
                vertical: AlayaSpacing.xs,
              ),
              onTap: () => _edit(context, ref),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      nameOf(share.payeeId),
                      style: AlayaTypography.body,
                    ),
                  ),
                  // Through `AmountText`, never `minor.toString()` — Law U7, and the mistake
                  // `LineItemsSection` records having made, which put `200000` on screen for two
                  // thousand rupees.
                  AmountText(
                    share.amount,
                    size: AmountSize.small,
                    showSign: false,
                    decimalDigits: decimalDigits,
                  ),
                ],
              ),
            ),

          if (!resolution.isExact) ...[
            const SizedBox(height: AlayaSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusChip(
                // Over-allocation and shortfall are different mistakes and read differently: "₹200
                // unassigned" is something to finish, "₹200 too much" is something to correct. One
                // label for both would describe neither.
                label: resolution.isOverAllocated
                    ? strings.splitOverAllocated
                    : strings.splitUnallocated,
                tone: StatusTone.warning,
                trailing: AmountText(
                  resolution.unallocated.abs(),
                  size: AmountSize.small,
                  showSign: false,
                  decimalDigits: decimalDigits,
                ),
              ),
            ),
          ],

          const SizedBox(height: AlayaSpacing.xs),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _edit(context, ref),
                icon: const Icon(Icons.edit_outlined, size: AlayaIconSize.md),
                label: Text(strings.splitEdit),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => ref
                    .read(transactionEditorProvider(editorId).notifier)
                    .setSplit(null),
                tooltip: strings.splitRemove,
                icon: Icon(
                  Icons.close,
                  size: AlayaIconSize.md,
                  color: semantic.muted,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
