import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/services/split/debt_simplifier.dart';
import 'package:alaya/domain/services/split/split_balance_service.dart';
import 'package:alaya/features/split/presentation/sheets/settle_up_sheet.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// The shortest way to settle a group up — as a suggestion, never as an edit.
///
/// ## Why this is a preview and not a mode
///
/// Splitwise rewrites the group's debt graph in place when simplification is on. Three things follow,
/// all documented by Splitwise itself: its help centre ends up advising users to look at their total
/// rather than the balances between specific members, because those may have been reshuffled; turning it
/// off does not cleanly reverse, so payments already made may no longer line up; and its forum has
/// carried the same complaint for over a decade — *"why do I owe ₹100 to someone who never lent me
/// money?"*
///
/// The most-requested fix, acknowledged by their staff in 2014 and never shipped, was a way to *see* the
/// simplified view without committing to it. That is this sheet.
///
/// **Nothing here writes.** The true pairwise debts stay exactly as recorded; a transfer is acted on by
/// opening the ordinary settle-up sheet, which records the ordinary settlement any manual payment would.
/// There is no simplified state to get stuck in and no toggle to lock.
///
/// **One payment at a time, deliberately.** An "accept all" button would have to write N settlements, and
/// N repository calls cannot be atomic — session 4 established that, and claiming otherwise is the
/// mistake this module already made once.
///
/// ## Why a sheet rather than the screen it was
///
/// It was `/split/groups/:groupId/settle` — the third level of a stack, reached from a group reached from
/// a tab. Nothing on it is an editor: it reads a plan and hands each line to another sheet. A route buys
/// a back arrow and a place to get lost, and this content needs neither.
class SplitSettlePlanSheet extends ConsumerWidget {
  /// Creates the sheet.
  const SplitSettlePlanSheet({required this.groupId, super.key});

  /// The group being settled.
  final String groupId;

  /// Opens the sheet for [groupId].
  static Future<void> show(BuildContext context, {required String groupId}) =>
      AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) => SplitSettlePlanSheet(groupId: groupId),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final plans = ref.watch(splitSettlePlansProvider(groupId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(strings.splitSimplifyTitle, style: AlayaTypography.sectionHeader),
        const SizedBox(height: AlayaSpacing.sm),

        plans.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AlayaSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stack) => ErrorState(
            title: strings.errorTitleGeneric,
            body: error.toString(),
            retryLabel: strings.actionRetry,
            onRetry: () => ref.invalidate(splitSettlePlansProvider(groupId)),
          ),
          data: (rows) => rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AlayaSpacing.lg,
                  ),
                  child: Text(
                    strings.splitAllSettledBody,
                    style: AlayaTypography.body.copyWith(
                      color: semantic.muted,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in rows)
                      _CurrencySection(groupId: groupId, entry: entry),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CurrencySection extends ConsumerWidget {
  const _CurrencySection({required this.groupId, required this.entry});

  final String groupId;
  final CurrencyPlan entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final plan = entry.plan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          // **One section per currency, never merged.** Netting INR against USD without a rate produces
          // a figure nobody can reproduce, and the simplifier refuses a mixed list outright — which is
          // the correct refusal and the reason the grouping is visible here rather than hidden in a
          // total.
          label: entry.currencyCode,
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
        ),

        Text(
          plan.isImprovement
              ? strings.splitSimplifySaves(
                  plan.originalDebtCount,
                  plan.transfers.length,
                )
              : strings.splitSimplifyNoBetter,
          style: AlayaTypography.body.copyWith(
            color: plan.isImprovement ? semantic.success : semantic.muted,
          ),
        ),

        if (!plan.wasPartitionedExactly) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            // **Says "a way", not "the fewest".** The exact partition runs up to sixteen people; beyond
            // that the greedy fallback still settles everybody but cannot prove it is minimal, and a
            // screen claiming otherwise would assert something the code deliberately does not know.
            child: StatusChip(
              label: strings.splitSimplifyApproximate,
              tone: StatusTone.info,
            ),
          ),
        ],

        const SizedBox(height: AlayaSpacing.sm),
        for (final transfer in plan.transfers)
          _TransferCard(groupId: groupId, transfer: transfer),
      ],
    );
  }
}

class _TransferCard extends ConsumerWidget {
  const _TransferCard({required this.groupId, required this.transfer});

  final String groupId;
  final SuggestedTransfer transfer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final self = ref.watch(splitSelfProvider).valueOrNull;

    String nameOf(String payeeId) =>
        ref.watch(splitPayeeNameProvider(payeeId)) ??
        strings.splitUnknownPerson;

    final youPay = transfer.fromPayeeId == self;
    final youArePaid = transfer.toPayeeId == self;
    final counterparty = youPay ? transfer.toPayeeId : transfer.fromPayeeId;
    final yours = youPay || youArePaid;

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.sm),
      // A transfer between two other people is a suggestion the user can pass on, not something they can
      // record — no money of theirs moves, so there is no account to put it through.
      //
      // **The plan sheet closes before the settle sheet opens.** Two stacked bottom sheets leave a user
      // dragging one to reveal another, and the plan is stale the moment a settlement is recorded anyway
      // — reopening it is both cheaper and more correct than keeping a snapshot behind the thing that
      // invalidates it.
      onTap: !yours
          ? null
          : () {
              Navigator.of(context).pop();
              SettleUpSheet.show(
                context,
                payeeId: counterparty,
                payeeName: nameOf(counterparty),
                outstanding: transfer.amount,
                theyOweMe: youArePaid,
                groupId: groupId,
              );
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A `Wrap`, not a `Row`: "Ravi pays Priya" beside an amount is the shape that overflows at
          // 320dp with the text scaler doubled (Law U15).
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AlayaSpacing.sm,
            runSpacing: AlayaSpacing.xxs,
            children: [
              SizedBox(
                width: 170,
                child: Text(
                  strings.splitTransferLine(
                    nameOf(transfer.fromPayeeId),
                    nameOf(transfer.toPayeeId),
                  ),
                  style: AlayaTypography.bodyEmphasis,
                ),
              ),
              AmountText(transfer.amount, showSign: false),
            ],
          ),

          // **The sentence Splitwise leaves its users to work out.** A simplified transfer arrives with
          // no provenance there, which is why the same question keeps being asked on their forum. Every
          // transfer here can account for itself.
          if (!transfer.isDirect) ...[
            const SizedBox(height: AlayaSpacing.xs),
            for (final cleared in transfer.clears)
              Padding(
                padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AlayaSpacing.xxs,
                  children: [
                    Icon(
                      Icons.subdirectory_arrow_right,
                      size: AlayaIconSize.sm,
                      color: semantic.muted,
                    ),
                    SizedBox(
                      width: 150,
                      child: Text(
                        strings.splitClearsDebt(nameOf(cleared.edge.toPayeeId)),
                        style: AlayaTypography.caption.copyWith(
                          color: semantic.muted,
                        ),
                      ),
                    ),
                    AmountText(
                      cleared.amount,
                      size: AmountSize.small,
                      showSign: false,
                      muted: true,
                    ),
                  ],
                ),
              ),
          ],

          if (!yours) ...[
            const SizedBox(height: AlayaSpacing.xxs),
            Text(
              // Says why the row does not respond, rather than leaving a dead card. A transfer between
              // two other people is real advice and not something the user can act on here.
              strings.splitTransferNotYours,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
          ],
        ],
      ),
    );
  }
}
