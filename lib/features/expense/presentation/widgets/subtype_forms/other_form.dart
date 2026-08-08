import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/features/expense/presentation/widgets/line_items_section.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';

/// The catch-all withdrawal sub-form.
///
/// Lines default to `destination = none` and the chooser in the line editor is where the user says
/// otherwise. This is the form that can produce any of the three artefacts, which is why the
/// destination is a decision here rather than an assumption.
class OtherForm extends ConsumerWidget {
  /// Creates the form.
  const OtherForm({
    required this.editorId,
    required this.state,
    required this.decimalDigits,
    super.key,
  });

  /// The editor family argument.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PayeeField(editorId: editorId, selectedId: state.payeeId),
      LineItemsSection(
        editorId: editorId,
        state: state,
        decimalDigits: decimalDigits,
        defaultDestination: TransactionLineDestination.none,
      ),
    ],
  );
}
