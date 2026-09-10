import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/features/settings/presentation/screens/payment_methods_settings_screen.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// Naming a payment method (ARCH_5 §3 archetype A).
///
/// One required field with the keyboard already up, the kind as chips rather than a picker, and a full-width
/// commit enabled the moment the name parses.
class PaymentMethodSheet extends ConsumerStatefulWidget {
  /// Creates the sheet. Prefer [show].
  const PaymentMethodSheet({
    required this.existing,
    required this.nextSortOrder,
    super.key,
  });

  /// The method being renamed, or null for a new one.
  final PaymentMethod? existing;

  /// The sort order a new method takes.
  final int nextSortOrder;

  /// Shows the sheet.
  static Future<void> show(
    BuildContext context, {
    required PaymentMethod? existing,
    required int nextSortOrder,
  }) => AlayaBottomSheet.show<void>(
    context: context,
    builder: (context) =>
        PaymentMethodSheet(existing: existing, nextSortOrder: nextSortOrder),
  );

  @override
  ConsumerState<PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends ConsumerState<PaymentMethodSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late PaymentMethodKind _kind =
      widget.existing?.kind ?? PaymentMethodKind.cash;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final editing = ref.watch(paymentMethodEditorProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.existing == null
              ? strings.paymentMethodsAdd
              : strings.paymentMethodsEditTitle,
          style: AlayaTypography.sectionHeader,
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _name,
          decoration: InputDecoration(
            labelText: strings.paymentMethodNameLabel,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AlayaSpacing.md),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final kind in PaymentMethodKind.values)
              ChoiceChip(
                label: Text(
                  paymentMethodKindLabel(strings, kind),
                  style: AlayaTypography.button,
                ),
                selected: kind == _kind,
                onSelected: (_) => setState(() => _kind = kind),
              ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          onPressed: _name.text.trim().isEmpty || editing.isLoading
              ? null
              : () => _save(strings),
          child: Text(
            strings.paymentMethodsSave,
            style: AlayaTypography.button,
          ),
        ),
      ],
    );
  }

  Future<void> _save(AlayaStrings strings) async {
    final ok = await ref
        .read(paymentMethodEditorProvider.notifier)
        .save(
          id: widget.existing?.id,
          name: _name.text,
          kind: _kind,
          sortOrder: widget.existing?.sortOrder ?? widget.nextSortOrder,
          // Preserved rather than defaulted: renaming a seeded method must not quietly turn it into a
          // user-created one that can then be deleted.
          isSystem: widget.existing?.isSystem ?? false,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.paymentMethodsSaved)
        : showFailureSnack(context, message: strings.paymentMethodsSaveFailed);
  }
}
