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
///
/// **[PayeeKind.splitPlaceholder] is not offered, and a placeholder being edited is promoted.** That
/// kind exists so a split can be saved before anybody is named — `split_shares.payee_id` is
/// `NOT NULL REFERENCES payees(id)`, so the row has to exist — and it is filtered out of every list a
/// human reads. Two things followed from adding it that this sheet got wrong:
///
/// * the chip row iterated `PayeeKind.values`, so *"Unnamed on a split"* became something a user could
///   assign to a real contact; and
/// * `_kind` was seeded from the existing row, so renaming a placeholder left the kind alone and the
///   row stayed hidden — the user did exactly the right thing and the app ignored it.
///
/// Both are fixed by [_selectableKinds] and by seeding a placeholder's selection as
/// [PayeeKind.person]: opening this sheet on a placeholder *is* the act of naming somebody, and saving
/// is what completes it.
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

  /// The kinds a person may choose between.
  ///
  /// Everything except [PayeeKind.splitPlaceholder], which the app assigns and never asks about.
  /// Derived from `PayeeKind.values` rather than listed, so a seventh member appears here
  /// automatically — the opposite mistake to hardcoding, which is what left this loop showing a kind
  /// nobody should pick.
  static final List<PayeeKind> selectableKinds = [
    for (final kind in PayeeKind.values)
      if (kind != PayeeKind.splitPlaceholder) kind,
  ];

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

  /// The kind that will be written.
  ///
  /// **A placeholder arrives as [PayeeKind.person].** Opening this sheet on one is somebody deciding
  /// who it was, and leaving the selection on a kind that is filtered out of every list would make
  /// saving look like it did nothing.
  late PayeeKind _kind = switch (widget.existing?.kind) {
    null => PayeeKind.merchant,
    PayeeKind.splitPlaceholder => PayeeKind.person,
    final existing => existing,
  };

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
          decoration: InputDecoration(labelText: strings.payeeNameLabel),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AlayaSpacing.md),
        // Optional, and marked as such. A payee is usually a shop name and nothing else; an unmarked
        // second field reads as required and is the commonest reason a two-field sheet feels like a form.
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
            for (final kind in PayeeSheet.selectableKinds)
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
          // Empty becomes null rather than an empty string, so a "has a phone number" test anywhere
          // else does not have to know about both.
          phone: phone.isEmpty ? null : phone,
          note: widget.existing?.note,
        );
    if (!mounted) return;

    // **The message goes up before the sheet comes down, and the order is the whole fix.** This used
    // to pop first and then check `context.mounted` — which is false the instant a sheet pops, so the
    // check returned and *both* snacks were dropped. A duplicate-name refusal, the one message that
    // explains why nothing happened, had never once been visible.
    //
    // `ScaffoldMessenger` lives above this route, so a snack shown now outlives the pop that follows.
    // The guard that caused the silence looks exactly like the guard that prevents a crash, which is
    // why it survived review: `if (!context.mounted) return;` is correct almost everywhere else.
    ok
        ? showResultSnack(context, message: strings.payeesSaved)
        : showFailureSnack(context, message: strings.payeesSaveFailed);
    Navigator.of(context).pop();
  }
}
