import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/expense/presentation/widgets/line_items_section.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// The electronics purchase sub-form.
///
/// **Lines default to `destination = asset`, not inventory, and the inventory opt-in is explicit.**
/// A television is a durable, serviceable thing with a warranty and a service history — it is not
/// consumable stock. Pushing it to both modules is anomaly A12: neither then owns the truth about
/// what you actually have. The opt-in exists because a few things genuinely are both, and it is off
/// by default because most are not.
///
/// The warranty window is collected here rather than on the line, because `transaction_lines` has no
/// column for it. The editor applies it to the asset the fan-out plans.
class ElectronicsForm extends ConsumerWidget {
  /// Creates the form.
  const ElectronicsForm({
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
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final notifier = ref.read(transactionEditorProvider(editorId).notifier);
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) =>
        DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PayeeField(editorId: editorId, selectedId: state.payeeId),
        SectionHeader(
          label: strings.sectionWarranty,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.xl,
            bottom: AlayaSpacing.xs,
          ),
        ),
        DatePickerField(
          value: state.warrantyStart,
          formatted: format,
          label: strings.labelFrom,
          hint: strings.hintSelectDate,
          onChanged: (date) =>
              notifier.setWarranty(start: date, end: state.warrantyEnd),
        ),
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.warrantyEnd,
          formatted: format,
          label: strings.labelTo,
          hint: strings.hintSelectDate,
          onChanged: (date) =>
              notifier.setWarranty(start: state.warrantyStart, end: date),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        CheckboxListTile(
          value: state.alsoAddToInventory,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(strings.alsoAddToInventory),
          onChanged: (value) =>
              notifier.setAlsoAddToInventory(value: value ?? false),
        ),
        LineItemsSection(
          editorId: editorId,
          state: state,
          decimalDigits: decimalDigits,
          defaultDestination: state.alsoAddToInventory
              ? TransactionLineDestination.inventory
              : TransactionLineDestination.asset,
        ),
      ],
    );
  }
}
