import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// Adds somebody you split bills with, and hands their id straight back.
///
/// ## Why the split module has its own instead of reusing `PayeeSheet`
///
/// **`PayeeSheet` defaults to `PayeeKind.merchant`**, which is right for the expense editor — most
/// payees are shops — and wrong here in a way that was invisible and total. Every person added from a
/// split screen was filed as a merchant, `splitPeopleProvider` filters to `person`, so they never
/// appeared. That emptied the name picker, emptied the "which person is you" list in Settings, left
/// `split.selfPayeeId` unsettable, and therefore made **saving a split impossible** — one wrong default
/// four steps upstream of the symptom.
///
/// **It also returns the payee it created.** `PayeeSheet.show` returns `Future<void>`, so the caller
/// had to find the new person by re-reading `splitPeopleProvider` after the sheet closed and diffing
/// against what was there before. That read happens before drift's stream has ticked, so the diff was
/// usually empty and the new person was silently not selected — the "it creates but does not change
/// Person 1" symptom. Returning the id removes the race rather than timing around it.
class AddPersonSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const AddPersonSheet({super.key});

  /// Opens the sheet, resolving to the new payee's id or null when dismissed.
  static Future<String?> show(BuildContext context) =>
      AlayaBottomSheet.show<String>(
        context: context,
        builder: (context) => const AddPersonSheet(),
      );

  @override
  ConsumerState<AddPersonSheet> createState() => _AddPersonSheetState();
}

class _AddPersonSheetState extends ConsumerState<AddPersonSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final strings = AlayaStrings.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = strings.splitAddPersonNameRequired);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final phone = _phone.text.trim();
    final saved = await ref
        .read(payeeRepositoryProvider)
        .save(
          Payee(
            id: ref.read(uidGeneratorProvider).generate(),
            name: name,
            normalizedName: ref.read(normalizerProvider).normalize(name),
            // **`person`, and that is the entire point of this sheet.** A merchant here is invisible to
            // every split screen, which is what made the module unusable.
            kind: PayeeKind.person,
            phone: phone.isEmpty ? null : phone,
          ),
        );
    if (!mounted) return;

    final payee = saved.valueOrNull;
    if (payee == null) {
      setState(() {
        _saving = false;
        // The repository's own sentence — a duplicate name says so, which "something went wrong" does
        // not (Law U9).
        _error = saved.failureOrNull?.message ?? strings.errorBodyGeneric;
      });
      return;
    }
    Navigator.of(context).pop(payee.id);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(strings.splitAddPersonTitle, style: AlayaTypography.sectionHeader),

        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: strings.payeeNameLabel,
            errorText: _error,
          ),
          onSubmitted: (_) => _save(),
        ),

        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          // `payeePhoneOptionalLabel`, the key `PayeeSheet` already uses — it reads "Phone (optional)",
          // which `PayeeSheet`'s own comment records as the fix for a two-field sheet feeling like a
          // form. Inventing a second key for the same field would give the same control two names.
          decoration: InputDecoration(
            labelText: strings.payeePhoneOptionalLabel,
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        Text(
          // Says what the field buys, which the label's "(optional)" does not. Two people really are
          // called the same thing, and the phone is the only field that tells them apart in a picker.
          strings.splitAddPersonPhoneHelp,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),

        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(strings.actionSave),
        ),
      ],
    );
  }
}
