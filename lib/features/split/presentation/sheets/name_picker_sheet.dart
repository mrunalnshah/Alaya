import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/split/presentation/sheets/add_person_sheet.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// Puts a name to one participant.
///
/// **Two people really are called the same thing**, and a list showing "Priya" twice is a coin toss.
/// `payees.phone` is the only field that reliably tells them apart, so it is shown **exactly where a
/// name repeats and nowhere else** — a phone beside every row is noise on the ninety-nine that are
/// unambiguous, and noise is what stops people reading a list at all.
///
/// **Names already used on this split are shown and disabled rather than hidden.** Somebody looking
/// for Ravi and not finding him would add a second Ravi; seeing him greyed with "already on this
/// split" answers the question instead of raising a new one.
///
/// **Adding somebody goes through [AddPersonSheet], not `PayeeSheet`.** The shared sheet defaults to
/// `PayeeKind.merchant` and returns `Future<void>`, which produced two failures at once: the new
/// person was filed as a shop and so never appeared in this list, and the caller had to find them by
/// re-reading a stream that had not ticked yet. `AddPersonSheet` creates a `person` and hands the id
/// straight back, so both the kind and the race are gone rather than worked around.
class NamePickerSheet extends ConsumerWidget {
  /// Creates the sheet.
  const NamePickerSheet({
    required this.people,
    required this.selected,
    required this.taken,
    super.key,
  });

  /// Everybody who could be named.
  final List<Payee> people;

  /// Who this slot currently holds, if anybody.
  final String? selected;

  /// Payee ids already used by the other slots.
  final Set<String> taken;

  /// Opens the sheet, resolving to the chosen payee id or null when dismissed.
  static Future<String?> show(
    BuildContext context, {
    required List<Payee> people,
    required String? selected,
    required Set<String> taken,
  }) => AlayaBottomSheet.show<String>(
    context: context,
    builder: (context) =>
        NamePickerSheet(people: people, selected: selected, taken: taken),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    // Counted once rather than per row: a name clashes when more than one payee carries it, and asking
    // that question inside the loop would be quadratic on a list somebody might have hundreds of.
    final byName = <String, int>{};
    for (final payee in people) {
      byName[payee.name] = (byName[payee.name] ?? 0) + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(strings.splitPickName, style: AlayaTypography.sectionHeader),
        const SizedBox(height: AlayaSpacing.sm),

        if (people.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.md),
            child: Text(
              strings.splitPickPeopleEmpty,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
          )
        else
          ConstrainedBox(
            // Bounded, because a sheet that grows with the payee list eventually covers the screen and
            // loses its own confirm affordance.
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: people.length,
              itemBuilder: (context, index) {
                final payee = people[index];
                final used = taken.contains(payee.id);
                final phone = payee.phone?.trim();
                final ambiguous = (byName[payee.name] ?? 0) > 1;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: !used,
                  selected: payee.id == selected,
                  leading: Icon(
                    payee.id == selected
                        ? Icons.check_circle
                        : Icons.person_outline,
                    size: AlayaIconSize.md,
                    color: used ? semantic.muted : null,
                  ),
                  title: Text(payee.name),
                  subtitle: used
                      ? Text(strings.splitAlreadyOnSplit)
                      : (ambiguous && phone != null && phone.isNotEmpty
                            ? Text(phone)
                            : null),
                  onTap: used
                      ? null
                      : () => Navigator.of(context).pop(payee.id),
                );
              },
            ),
          ),

        const SizedBox(height: AlayaSpacing.sm),
        OutlinedButton.icon(
          onPressed: () => _create(context),
          icon: const Icon(Icons.person_add_outlined, size: AlayaIconSize.md),
          label: Text(strings.splitNewPerson),
        ),
      ],
    );
  }

  /// Adds somebody and chooses them in one gesture.
  ///
  /// The id comes back from the sheet, so there is nothing to look up and nothing to wait for. The
  /// previous version diffed `splitPeopleProvider` before and after, which read the stream before it
  /// had emitted and so usually found nobody new.
  Future<void> _create(BuildContext context) async {
    final created = await AddPersonSheet.show(context);
    if (!context.mounted) return;
    Navigator.of(context).pop(created);
  }
}
