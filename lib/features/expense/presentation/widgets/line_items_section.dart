import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/features/expense/presentation/sheets/line_item_editor.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// The "what you bought" section, shared by every sub-form that itemises (ARCH_5 §4).
///
/// One widget rather than one per sub-form: grocery, household, electronics and other all itemise
/// identically, and four copies is how one component becomes four that drift (ARCH_4 R25). Only the
/// default destination differs, so that is the parameter.
///
/// **The unallocated chip is never auto-balanced.** The transaction amount is the source of truth
/// and the lines are optional detail; forcing them equal would invent a line the user did not buy
/// (anomaly A11). Note the chip appears only when lines exist — with none at all, "unallocated"
/// equals the whole amount, which is not a mismatch.
class LineItemsSection extends ConsumerWidget {
  /// Creates the section for [state], defaulting new lines to [defaultDestination].
  const LineItemsSection({
    required this.editorId,
    required this.state,
    required this.decimalDigits,
    this.defaultDestination = TransactionLineDestination.inventory,
    super.key,
  });

  /// The editor family argument, so the section writes to the right notifier.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  /// What a new line starts as.
  final TransactionLineDestination defaultDestination;

  /// Opens the dedicated items page.
  ///
  /// **A page, not the sheet.** Adding one line at a time through a sheet meant a fifteen-item receipt
  /// was fifteen open-close cycles with no view of what had been entered. The page keeps the list, the
  /// running total and the add action on screen together; the sheet is still what edits a single line,
  /// reached from there.
  void _openItems(BuildContext context) =>
      context.push(Routes.transactionLines(state.id));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(transactionEditorProvider(editorId).notifier);
    final unallocated = state.unallocated;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: strings.sectionWhatYouBought,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.xl,
            bottom: AlayaSpacing.xs,
          ),
        ),
        for (final line in state.lines)
          AlayaCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AlayaSpacing.sm,
              vertical: AlayaSpacing.xs,
            ),
            onTap: () async {
              final edited = await LineItemEditor.show(
                context,
                currencyCode: state.currencyCode,
                decimalDigits: decimalDigits,
                defaultDestination: defaultDestination,
                line: line,
              );
              if (edited != null) notifier.upsertLine(edited.line);
            },
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.description, style: AlayaTypography.body),
                      if (line.quantity != null) ...[
                        const SizedBox(height: AlayaSpacing.xxs),
                        QtyText(line.quantity!, muted: true),
                      ],
                    ],
                  ),
                ),
                if (line.lineAmount != null)
                  AmountText(
                    line.lineAmount!,
                    size: AmountSize.small,
                    showSign: false,
                    decimalDigits: decimalDigits,
                  ),
                IconButton(
                  onPressed: () => notifier.removeLine(line.id),
                  tooltip: strings.actionDelete,
                  icon: Icon(
                    Icons.close,
                    size: AlayaIconSize.md,
                    color: semantic.muted,
                  ),
                ),
              ],
            ),
          ),
        if (unallocated != null) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusChip(
              label: strings.statusUnallocated,
              tone: StatusTone.warning,
              // Through `AmountText`, not `minor.toString()`. `Money` is minor units, so the old call
              // put `200000` on screen for two thousand rupees (Law U7).
              trailing: AmountText(
                unallocated.abs(),
                size: AmountSize.small,
                showSign: false,
                decimalDigits: decimalDigits,
              ),
            ),
          ),
        ],
        const SizedBox(height: AlayaSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _openItems(context),
            icon: const Icon(Icons.add, size: AlayaIconSize.md),
            label: Text(strings.lineAdd),
          ),
        ),
      ],
    );
  }
}
