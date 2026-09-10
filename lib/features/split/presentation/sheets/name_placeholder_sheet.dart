import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/split/providers/split_merge_provider.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// Who an unnamed split participant turned out to be.
///
/// ## Two answers, and only one of them is a rename
///
/// **"Somebody you know" and "somebody new" are different operations**, which is the bug this sheet fixes.
/// The old affordance opened `PayeeSheet` — a name field — so the only thing you could say was *"call this
/// row Ravi"*. If Ravi already existed you now had two Ravis: two balances, and settling one left the other
/// outstanding with nothing on screen to explain it.
///
/// Picking an existing person **merges**: every share, settlement, membership and paid-by reference moves to
/// them and the placeholder is retired, in one transaction. Typing a name **renames and promotes** —
/// `kind: person`, which is what takes the row out of the placeholder set and into every list a contact
/// belongs in.
///
/// ## The list comes first
///
/// A name field first would invite typing "Ravi" while Ravi is three rows below, which is exactly the
/// duplicate this exists to prevent. The people you already have are the likelier answer at a table you
/// split a bill at, so they are what you see without scrolling.
class NamePlaceholderSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const NamePlaceholderSheet({required this.placeholder, super.key});

  /// The row this app created because nobody had been named.
  final Payee placeholder;

  /// Opens the sheet, resolving true when the placeholder was resolved.
  static Future<bool> show(
    BuildContext context, {
    required Payee placeholder,
  }) async =>
      await AlayaBottomSheet.show<bool>(
        context: context,
        builder: (context) => NamePlaceholderSheet(placeholder: placeholder),
      ) ??
      false;

  @override
  ConsumerState<NamePlaceholderSheet> createState() =>
      _NamePlaceholderSheetState();
}

class _NamePlaceholderSheetState extends ConsumerState<NamePlaceholderSheet> {
  final _name = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _merge(Payee into) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final notifier = ref.read(splitNamePlaceholderProvider.notifier);
    final ok = await notifier.mergeInto(
      placeholderPayeeId: widget.placeholder.id,
      payeeId: into.id,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        // The repository's own sentence — "that person has been deleted, restore them first" is actionable
        // where "something went wrong" is not (Law U9).
        _error =
            notifier.lastError ?? AlayaStrings.of(context).errorBodyGeneric;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _rename() async {
    final strings = AlayaStrings.of(context);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = strings.splitNameRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final notifier = ref.read(splitNamePlaceholderProvider.notifier);
    final ok = await notifier.rename(
      placeholder: widget.placeholder,
      name: _name.text,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = notifier.lastError ?? strings.errorBodyGeneric;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    // `splitPeopleProvider`, so no other placeholder is offered. Merging one placeholder into another would
    // resolve nothing and retire a row somebody still owes money to.
    final people =
        ref.watch(splitPeopleProvider).valueOrNull ?? const <Payee>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(strings.splitNameThisPerson, style: AlayaTypography.sectionHeader),
        const SizedBox(height: AlayaSpacing.xxs),
        Text(
          strings.splitNamePlaceholderBody(widget.placeholder.name),
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),

        if (people.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.lg),
          Text(
            strings.splitNameSomebodyKnown,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          const SizedBox(height: AlayaSpacing.xs),
          ConstrainedBox(
            // Bounded, because a sheet that grows with the payee list eventually covers the name field
            // below it — and that field is the other half of the question.
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: people.length,
              itemBuilder: (context, index) {
                final payee = people[index];
                final phone = payee.phone?.trim();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: !_busy,
                  leading: Icon(
                    Icons.person_outline,
                    size: AlayaIconSize.md,
                    color: semantic.muted,
                  ),
                  title: Text(payee.name),
                  subtitle: phone == null || phone.isEmpty ? null : Text(phone),
                  onTap: _busy ? null : () => _merge(payee),
                );
              },
            ),
          ),
          const SizedBox(height: AlayaSpacing.md),
          Row(
            children: [
              Expanded(child: Divider(color: semantic.muted)),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AlayaSpacing.sm,
                ),
                child: Text(
                  strings.splitNameOr,
                  style: AlayaTypography.caption.copyWith(
                    color: semantic.muted,
                  ),
                ),
              ),
              Expanded(child: Divider(color: semantic.muted)),
            ],
          ),
        ],

        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: strings.splitNameSomebodyNew,
            errorText: _error,
          ),
          onSubmitted: (_) => _rename(),
        ),
        const SizedBox(height: AlayaSpacing.md),
        FilledButton(
          onPressed: _busy ? null : _rename,
          child: Text(strings.actionSave),
        ),
      ],
    );
  }
}
