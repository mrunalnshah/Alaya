import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';

/// Picks a counterparty, and creates one inline when it does not exist yet.
///
/// **Inline creation rather than a trip to Settings.** A payee is discovered at the moment of
/// recording a purchase — you find out the shop is called "Reliance Fresh" while you are typing the
/// receipt, not before. Sending the user to a settings screen to add one guarantees the field is
/// left blank, and a blank payee is the column that makes "top payees by spend" useless.
///
/// One widget rather than one per sub-form: six of the seven need it, and six copies is how one
/// component becomes six that drift (ARCH_4 R25).
class PayeeField extends ConsumerStatefulWidget {
  /// Creates the field for the editor identified by [editorId].
  const PayeeField({
    required this.editorId,
    required this.selectedId,
    super.key,
  });

  /// The editor family argument, so the field writes to the right notifier.
  final String? editorId;

  /// The payee currently chosen.
  final String? selectedId;

  @override
  ConsumerState<PayeeField> createState() => _PayeeFieldState();
}

class _PayeeFieldState extends ConsumerState<PayeeField> {
  final TextEditingController _newName = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _newName.text.trim();
    if (name.isEmpty) return;
    final strings = AlayaStrings.of(context);
    final created = await ref
        .read(transactionEditorProvider(widget.editorId).notifier)
        .createPayee(name);
    if (!mounted) return;
    // **The field stays open on failure, holding what was typed.** Closing it and clearing the name
    // would discard the user's input and leave them with an empty picker and no explanation — which
    // reads as the app having quietly ignored them.
    if (!created) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    _newName.clear();
    setState(() => _creating = false);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final payees =
        ref.watch(editorPayeesProvider).valueOrNull ?? const <Payee>[];
    final notifier = ref.read(
      transactionEditorProvider(widget.editorId).notifier,
    );

    Payee? current;
    for (final payee in payees) {
      if (payee.id == widget.selectedId) {
        current = payee;
        break;
      }
    }

    if (_creating) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _newName,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: strings.labelPayee),
              onSubmitted: (_) => _create(),
            ),
          ),
          const SizedBox(width: AlayaSpacing.xs),
          TextButton(onPressed: _create, child: Text(strings.actionAdd)),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey(current?.id),
            initialValue: current?.id,
            isExpanded: true,
            decoration: InputDecoration(labelText: strings.labelPayee),
            items: [
              for (final payee in payees)
                DropdownMenuItem(
                  value: payee.id,
                  child: Text(
                    payee.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: notifier.setPayee,
          ),
        ),
        const SizedBox(width: AlayaSpacing.xs),
        TextButton(
          onPressed: () => setState(() => _creating = true),
          child: Text(strings.actionAdd),
        ),
      ],
    );
  }
}
