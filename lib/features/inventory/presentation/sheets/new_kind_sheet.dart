import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/inventory/providers/inventory_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// Makes a new inventory kind without leaving the form that needed it.
///
/// **One field, because a kind is one word.** The tag it writes could carry a colour, an icon, a parent and
/// five other scopes — and asking for any of that here would turn "I want a Vegetables kind" into a form. Those
/// are all editable in Settings › Tags afterwards, on the same row this creates.
///
/// **Scoped to inventory only.** A kind made while entering a receipt must not appear in the deposit picker or
/// the recurring one; `allowedScopes` gets exactly `{inventory}`, which is what ARCH_2 §14's scoping is for.
/// Widening it later is a tick box in Settings.
///
/// **`isSystem: false`, so it is deletable.** The nine seeded kinds are protected — `softDeleteUserTag` returns
/// zero rows for them and the repository turns that into a refusal — and anything made here is not.
class NewKindSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const NewKindSheet({super.key});

  /// Opens the sheet, resolving to the new tag's id or null if nothing was made.
  static Future<String?> show(BuildContext context) =>
      AlayaBottomSheet.show<String>(
        context: context,
        builder: (context) => const NewKindSheet(),
      );

  @override
  ConsumerState<NewKindSheet> createState() => _NewKindSheetState();
}

class _NewKindSheetState extends ConsumerState<NewKindSheet> {
  final _name = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final strings = AlayaStrings.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = strings.inventoryKindNameRequired);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final id = ref.read(uidGeneratorProvider).generate();
    final result = await ref
        .read(tagRepositoryProvider)
        .save(
          Tag(
            id: id,
            name: name,
            normalizedName: ref.read(normalizerProvider).normalize(name),
            // Inventory alone. See the class doc — a kind is not a spending category.
            allowedScopes: const {TagScope.inventory},
            isSystem: false,
            // Last, so a new kind lands at the bottom of the list rather than jumping into the middle of the
            // seeded order. Reorderable in Settings like any other tag.
            sortOrder: 1000,
            // Required rather than defaulted, because `Tag` treats deletion as real writable state — the only
            // entity in this schema that does. `save` reads it to decide whether to set or clear `deleted_at`.
            isDeleted: false,
          ),
        );
    if (!mounted) return;

    final failure = result.failureOrNull;
    if (failure != null) {
      setState(() {
        _saving = false;
        // **The repository's own sentence.** `save` returns a `ConflictFailure` when an active tag already has
        // this normalized name — which is the likeliest failure here, because a user reaching for "Medicine"
        // has no way to know one of the nine seeded kinds is already called that. "Something went wrong" would
        // leave them retyping it.
        _error = failure is ConflictFailure
            ? strings.inventoryKindNameTaken
            : failure.message;
      });
      return;
    }

    // The picker that opened this reads `inventoryKindsProvider`; it is a stream over `tags`, so drift re-emits
    // on the write. Invalidating anyway would throw away the subscription and refetch for nothing.
    Navigator.of(context).pop(result.valueOrNull?.id ?? id);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          strings.inventoryKindNewTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          // Focused, because this sheet exists only to type one word and the tap that opened it said so. The
          // same rule the tip row's custom-percent field follows.
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: strings.inventoryKindNameLabel,
            errorText: _error,
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(strings.actionSave),
        ),
      ],
    );
  }
}
