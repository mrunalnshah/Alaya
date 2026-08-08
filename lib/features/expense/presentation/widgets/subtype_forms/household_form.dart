import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/features/expense/presentation/widgets/line_items_section.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';

/// The household purchase sub-form.
///
/// Identical in shape to the grocery form, and deliberately a separate file rather than an alias:
/// the two subtypes exist because they land in different analytics buckets, and a single shared
/// widget invites the first divergence to be made by editing the other module's form.
class HouseholdForm extends ConsumerWidget {
  /// Creates the form.
  const HouseholdForm({
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
