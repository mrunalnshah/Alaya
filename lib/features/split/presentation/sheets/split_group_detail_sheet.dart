import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/features/split/presentation/sheets/settle_up_sheet.dart';
import 'package:alaya/features/split/presentation/sheets/split_settle_plan_sheet.dart';
import 'package:alaya/features/split/presentation/sheets/split_share_sheet.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// One group: who owes what within it, and what to do about it.
///
/// **Was `/split/groups/:groupId`, the second level of a stack behind a tab.** Nothing on it is an
/// editor — it reads balances and offers three actions — so a route bought a back arrow, an app bar with
/// three competing targets, and somewhere for a user to end up without knowing how.
///
/// **Balances and actions, not balances and a feed.** The screen this replaces also rendered the group's
/// activity, which the History tab now shows for every group at once. Duplicating it here made the sheet
/// long enough to need scrolling past the actions, which are the reason somebody opened it.
///
/// Group balances carry no ageing, deliberately. Ageing is a property of a debt with a *person*, and a
/// group-scoped day count would report the same debt twice for somebody you owe through two groups.
///
/// **Settling is the emphasised action.** Share and Edit are things you do *to* a group; settling is why
/// you looked.
class SplitGroupDetailSheet extends ConsumerWidget {
  /// Creates the sheet.
  const SplitGroupDetailSheet({required this.groupId, super.key});

  /// The group being shown.
  final String groupId;

  /// Opens the sheet for [groupId].
  static Future<void> show(BuildContext context, {required String groupId}) =>
      AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) => SplitGroupDetailSheet(groupId: groupId),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final group = ref.watch(splitGroupProvider(groupId));
    final balances =
        ref.watch(splitGroupBalancesProvider(groupId)).valueOrNull ??
        const <SplitBalance>[];

    final found = group.valueOrNull;
    if (group.hasError) {
      return ErrorState(
        title: strings.errorTitleGeneric,
        body: group.error.toString(),
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(splitGroupProvider(groupId)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          found?.name ?? strings.splitGroupsTitle,
          style: AlayaTypography.sectionHeader,
        ),
        if (found != null) ...[
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            strings.splitPerPersonCount(found.members.length),
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ],

        const SizedBox(height: AlayaSpacing.md),
        if (balances.isEmpty)
          Text(
            // Settled is a real state and worth saying plainly, rather than showing an empty area that
            // reads as a sheet which failed to load half of itself.
            strings.splitAllSettledTitle,
            style: AlayaTypography.body.copyWith(color: semantic.success),
          )
        else ...[
          SectionHeader(
            label: strings.splitBalancesHeader,
            padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
          ),
          for (final balance in balances)
            _GroupBalanceRow(balance: balance, groupId: groupId),
        ],

        const SizedBox(height: AlayaSpacing.lg),
        FilledButton.icon(
          // **Closed before the plan opens.** Two stacked bottom sheets leave somebody dragging one to
          // reveal another, and a plan is stale the moment a settlement is recorded — so reopening beats
          // holding a snapshot behind the thing that invalidates it.
          onPressed: () {
            Navigator.of(context).pop();
            SplitSettlePlanSheet.show(context, groupId: groupId);
          },
          icon: const Icon(Icons.call_merge_outlined, size: AlayaIconSize.md),
          label: Text(strings.splitSimplifyTitle),
        ),

        const SizedBox(height: AlayaSpacing.xs),
        Wrap(
          spacing: AlayaSpacing.sm,
          runSpacing: AlayaSpacing.xs,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                SplitShareSheet.show(context, groupId: groupId);
              },
              icon: const Icon(Icons.ios_share, size: AlayaIconSize.md),
              label: Text(strings.actionShare),
            ),
            OutlinedButton.icon(
              // The editor keeps its route: it is a form with a delete action and a discard guard, which
              // is what `AlayaFormScaffold` and archetype B exist for. A keyboard inside a bottom sheet
              // over a list of chips is the arrangement that made this module feel like work.
              onPressed: () {
                Navigator.of(context).pop();
                context.push(Routes.splitGroupEditFor(groupId));
              },
              icon: const Icon(Icons.edit_outlined, size: AlayaIconSize.md),
              label: Text(strings.actionEdit),
            ),
          ],
        ),
      ],
    );
  }
}

class _GroupBalanceRow extends ConsumerWidget {
  const _GroupBalanceRow({required this.balance, required this.groupId});

  final SplitBalance balance;
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final name =
        ref.watch(splitPayeeNameProvider(balance.payeeId)) ??
        strings.splitUnknownPerson;

    void settle() {
      Navigator.of(context).pop();
      SettleUpSheet.show(
        context,
        payeeId: balance.payeeId,
        payeeName: name,
        outstanding: balance.outstanding,
        theyOweMe: balance.theyOweMe,
        groupId: groupId,
      );
    }

    return AlayaCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.sm,
        vertical: AlayaSpacing.xs,
      ),
      // Settling one person directly, without going through the plan. Most groups have two people and no
      // simplification to find, and making the common case pass through an optimiser is how a feature
      // built for six people slows down the pair who use it daily.
      //
      // **Tappable and labelled**, the same fix as the balance rows on the split screen: a card with no
      // button reads as a list item, and recording a repayment was the least visible thing in the module.
      onTap: settle,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AlayaSpacing.sm,
        runSpacing: AlayaSpacing.xs,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: AlayaTypography.body),
              const SizedBox(height: AlayaSpacing.xxs),
              // The direction in words, not in colour. `AmountText` has no tone parameter — it colours
              // from `kind`, deliberately, so one movement of money never renders as two different
              // things — and a sentence survives a screenshot and a colour-blind reader.
              Text(
                balance.theyOweMe
                    ? strings.splitOwesYou(name)
                    : strings.splitYouOwePerson(name),
                style: AlayaTypography.caption,
              ),
              TextButton.icon(
                onPressed: settle,
                icon: const Icon(
                  Icons.handshake_outlined,
                  size: AlayaIconSize.sm,
                ),
                label: Text(
                  balance.theyOweMe
                      ? strings.splitRecordTheyPaid
                      : strings.splitRecordYouPaid,
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          AmountText(balance.outstanding, showSign: false),
        ],
      ),
    );
  }
}
