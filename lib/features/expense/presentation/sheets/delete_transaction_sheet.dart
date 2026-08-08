import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// Captures an optional reason before deleting (ARCH_5 §3 archetype A).
///
/// **This is not the primary delete.** Deleting a transaction is reversible, so the ordinary path
/// does it immediately and offers Undo — a confirmation dialog on an undoable action is friction
/// with no safety value, and it trains people to tap through the confirmations that do matter
/// (ARCH_5 §5.5).
///
/// This sheet exists only for the "delete with a reason" path, which is what surfaces
/// `transactions.deleteReason` (ARCH_5 §7.2). A household ledger genuinely needs "duplicate" or
/// "wrong account" recorded sometimes, and Phase 8B's trash screen shows it back. It still ends in
/// an Undo rather than a confirmation.
class DeleteTransactionSheet extends StatefulWidget {
  /// Creates the sheet. Prefer [show].
  const DeleteTransactionSheet({super.key});

  /// Opens the sheet, resolving to the typed reason, or null if the user backed out.
  ///
  /// An empty reason resolves to the empty string rather than null, so a caller can tell "deleted
  /// without saying why" from "changed their mind".
  static Future<String?> show(BuildContext context) =>
      AlayaBottomSheet.show<String>(
        context: context,
        builder: (context) => const DeleteTransactionSheet(),
      );

  @override
  State<DeleteTransactionSheet> createState() => _DeleteTransactionSheetState();
}

class _DeleteTransactionSheetState extends State<DeleteTransactionSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.actionDeleteTransaction,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Text(
          strings.confirmDeleteBody,
          style: AlayaTypography.body.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(hintText: strings.deleteReasonHint),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(strings.actionDelete),
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
