import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/settings/presentation/screens/payees_settings_screen.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// Naming a payee (ARCH_5 §3 archetype A).
class PayeeSheet extends ConsumerStatefulWidget {
  /// Creates the sheet. Prefer [show].
  const PayeeSheet({required this.existing, super.key});

  /// The payee being edited, or null for a new one.
  final Payee? existing;

  /// Shows the sheet.
  static Future<void> show(BuildContext context, {required Payee? existing}) =>
      AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) => PayeeSheet(existing: existing),
      );

  @override
  ConsumerState<PayeeSheet> createState() => _PayeeSheetState();
}

class _PayeeSheetState extends ConsumerState<PayeeSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.existing?.phone ?? '',
  );
  late PayeeKind _kind = widget.existing?.kind ?? PayeeKind.merchant;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final editing = ref.watch(payeeEditorProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.existing == null ? strings.payeesAdd : strings.payeesEditTitle,
          style: AlayaTypography.sectionHeader,
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _name,
          autofocus: true,
          decoration: InputDecoration(labelText: strings.payeeNameLabel),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AlayaSpacing.md),
        // Optional, and marked as such. A payee is usually a shop name and nothing else; an unmarked second
        // field reads as required and is the commonest reason a two-field sheet feels like a form.
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: strings.payeePhoneOptionalLabel,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final kind in PayeeKind.values)
              ChoiceChip(
                label: Text(
                  payeeKindLabel(strings, kind),
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
          child: Text(strings.payeesSave, style: AlayaTypography.button),
        ),
      ],
    );
  }

  Future<void> _save(AlayaStrings strings) async {
    final phone = _phone.text.trim();
    final ok = await ref
        .read(payeeEditorProvider.notifier)
        .save(
          id: widget.existing?.id,
          name: _name.text,
          kind: _kind,
          // Empty becomes null rather than an empty string, so a "has a phone number" test anywhere else does
          // not have to know about both.
          phone: phone.isEmpty ? null : phone,
          note: widget.existing?.note,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.payeesSaved)
        : showFailureSnack(context, message: strings.payeesSaveFailed);
  }
}
