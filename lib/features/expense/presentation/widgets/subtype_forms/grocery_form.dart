import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/features/expense/presentation/widgets/line_items_section.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';

/// The grocery purchase sub-form.
///
/// Lines default to `destination = inventory`: a grocery receipt is the single most common way stock
/// enters the house, and defaulting to anything else means the inventory module stays empty however
/// diligently the user records their spending.
class GroceryForm extends ConsumerWidget {
  /// Creates the form.
  const GroceryForm({
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
        defaultDestination: TransactionLineDestination.inventory,
      ),
    ],
  );
}
