import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/settings/presentation/sheets/payee_sheet.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_search_field.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

/// Settings › Payees (ARCH_5 §3 archetype D, outside the shell).
///
/// **The only settings branch with a search field, because it is the only one that grows without
/// bound.** Every other list here is fixed by the app's shape — five account kinds, six payment
/// methods, three unit categories — while payees accumulate one per shop the user ever names. A
/// hundred rows is normal, and scanning fails.
///
/// **This screen does not filter placeholders, and it used to.** `payeesSettingsProvider` excludes
/// [PayeeKind.splitPlaceholder] now, which is where the decision belongs: filtering here left every
/// other consumer of that provider counting rows this list refused to show, so a payee count and a
/// payee list disagreed by the number of unnamed split participants. One filter, one layer, and no
/// second reader to keep in step.
class PayeesSettingsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const PayeesSettingsScreen({super.key});

  @override
  ConsumerState<PayeesSettingsScreen> createState() =>
      _PayeesSettingsScreenState();
}

class _PayeesSettingsScreenState extends ConsumerState<PayeesSettingsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final payees = ref.watch(payeesSettingsProvider);
    final query = _query.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsPayees)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => PayeeSheet.show(context, existing: null),
        tooltip: strings.payeesAdd,
        child: const Icon(Icons.add, size: AlayaIconSize.lg),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AlayaSpacing.screenEdge,
              AlayaSpacing.sm,
              AlayaSpacing.screenEdge,
              AlayaSpacing.xs,
            ),
            child: AlayaSearchField(
              hintText: strings.payeesSearchHint,
              clearLabel: strings.actionClear,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: payees.when(
              loading: () => AlayaListSkeleton(label: strings.payeesLoading),
              error: (error, stack) => ErrorState(
                title: strings.errorTitleGeneric,
                body: error.toString(),
                retryLabel: strings.actionRetry,
                onRetry: () => ref.invalidate(payeesSettingsProvider),
              ),
              data: (rows) {
                final matching = query.isEmpty
                    ? rows
                    // Matched on `normalizedName`, so "cafe" finds "Café" — the same normaliser the
                    // repository used when it stored the row, rather than a second rule that would
                    // disagree with it.
                    : [
                        for (final row in rows)
                          if (row.normalizedName.contains(query)) row,
                      ];

                if (rows.isEmpty) {
                  return EmptyState(
                    title: strings.payeesEmptyTitle,
                    body: strings.payeesEmptyBody,
                    icon: Icons.storefront_outlined,
                    actionLabel: strings.payeesAdd,
                    onAction: () => PayeeSheet.show(context, existing: null),
                  );
                }
                // Two distinct empties: nothing at all, and nothing matching. The second names the
                // search, because "no payees" in front of a list the user can see is a lie.
                if (matching.isEmpty) {
                  return EmptyState(
                    title: strings.payeesNoMatchTitle,
                    body: strings.payeesNoMatchBody,
                    icon: Icons.search_off_outlined,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
                  itemCount: matching.length,
                  itemBuilder: (context, index) =>
                      _PayeeRow(payee: matching[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PayeeRow extends ConsumerWidget {
  const _PayeeRow({required this.payee});

  final Payee payee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final detail = [
      payeeKindLabel(strings, payee.kind),
      if (payee.phone != null && payee.phone!.isNotEmpty) payee.phone!,
    ].join(' · ');

    return ListTile(
      leading: Icon(
        // A person and a shop are different things and the list said so with one icon for both. The
        // kind is already in the subtitle; the glyph now agrees with it rather than contradicting it.
        payee.kind == PayeeKind.person
            ? Icons.person_outline
            : Icons.storefront_outlined,
        size: AlayaIconSize.lg,
        color: semantic.muted,
      ),
      title: Text(payee.name, style: AlayaTypography.cardTitle),
      subtitle: Text(
        detail,
        style: AlayaTypography.caption.copyWith(color: semantic.muted),
      ),
      trailing: IconButton(
        onPressed: () => _delete(context, ref, strings),
        tooltip: strings.payeesDelete,
        icon: Icon(
          Icons.delete_outline,
          size: AlayaIconSize.md,
          color: semantic.danger,
        ),
      ),
      onTap: () => PayeeSheet.show(context, existing: payee),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.payeesDeleteConfirmTitle,
      body: strings.payeesDeleteConfirmBody,
      confirmLabel: strings.payeesDelete,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await ref.read(payeeEditorProvider.notifier).delete(payee.id);
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.payeesDeleted)
        : showFailureSnack(context, message: strings.payeesDeleteFailed);
  }
}

/// The name of each payee kind.
///
/// **Exhaustive, and it refused to compile the moment `PayeeKind` gained a sixth member.** That is Law
/// L13 working: an added member cannot fall through to a wrong label, because every switch like this
/// one fails loudly until somebody decides what the new case means.
///
/// [PayeeKind.splitPlaceholder] never reaches this screen — `payeesSettingsProvider` filters those rows
/// out — but this function is public and the compiler is right to insist. A placeholder that reaches
/// some other caller should say what it is rather than borrow "Other".
String payeeKindLabel(AlayaStrings strings, PayeeKind kind) => switch (kind) {
  PayeeKind.person => strings.payeeKindPerson,
  PayeeKind.merchant => strings.payeeKindMerchant,
  PayeeKind.employer => strings.payeeKindEmployer,
  PayeeKind.utility => strings.payeeKindUtility,
  PayeeKind.other => strings.payeeKindOther,
  PayeeKind.splitPlaceholder => strings.payeeKindSplitPlaceholder,
};
