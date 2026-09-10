import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// What is owed to you and by you, on the dashboard (ARCH_5 §3 archetype F).
///
/// ## Deliberately not part of the funds header
///
/// **The first decision this module recorded is that owed money is not spendable until it arrives.** A
/// receivable folded into "total available funds" would say the user can spend ₹4,000 that is sitting in
/// somebody else's bank account — and once a figure has been added to a total, nothing on screen can
/// unsay it. This card sits below the funds header with its own heading for exactly that reason, and the
/// caption states it rather than leaving it to be inferred.
///
/// ## Two figures, never one
///
/// *"You are owed ₹4,000 and you owe ₹3,900"* is a different story from *"you are up ₹100"*, and the net
/// version is the first step toward treating a receivable as an asset. Both directions are shown even
/// when one is zero, so the layout does not shift as debts appear and clear.
///
/// Hidden entirely when nothing is outstanding: a dashboard is a summary of what needs attention, and a
/// card reading "₹0 and ₹0" is a row of nothing occupying the space a real figure would use. That is the
/// same reasoning `InsightCard` applies to an empty span.
class SplitBalanceCard extends ConsumerWidget {
  /// Creates the card.
  const SplitBalanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final totals = ref.watch(splitTotalsProvider).valueOrNull;
    final ageing = ref.watch(splitAgeingProvider).valueOrNull ?? const [];

    // Still loading, or nothing outstanding. Both render nothing rather than a placeholder: a card that
    // appears empty and then fills is a layout jump on the screen a user looks at most often.
    if (totals == null || totals.isEmpty) return const SizedBox.shrink();

    // The oldest debt across every currency, which is the one worth naming. Ageing is per counterparty,
    // so this is a person rather than an amount — and the sentence is the point.
    final oldest = ageing.isEmpty ? null : ageing.first;

    return AlayaCard(
      onTap: () => context.push(Routes.split),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.call_split_outlined,
                size: AlayaIconSize.md,
                color: semantic.muted,
              ),
              const SizedBox(width: AlayaSpacing.xs),
              Expanded(
                child: Text(
                  strings.splitCardTitle,
                  style: AlayaTypography.bodyEmphasis,
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: AlayaIconSize.md,
                color: semantic.muted,
              ),
            ],
          ),

          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            // **The sentence that keeps the figure honest.** Without it a number on the dashboard reads as
            // money the user has, which is precisely the reading decision 1 exists to prevent.
            strings.splitCardNotSpendable,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),

          const SizedBox(height: AlayaSpacing.sm),
          for (final entry in totals.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: _Side(
                      label: strings.splitOwedToYou,
                      amount: entry.value.owedToMe,
                    ),
                  ),
                  Expanded(
                    child: _Side(
                      label: strings.splitYouOwe,
                      amount: entry.value.iOwe,
                    ),
                  ),
                ],
              ),
            ),

          if (oldest != null)
            Align(
              alignment: Alignment.centerLeft,
              child: StatusChip(
                // The nudge no competitor sends, on the screen people actually open. It needs no due
                // date — `v_split_balances` already carries the oldest contributing expense, and the day
                // count is computed against the injected clock because a view may not read the time.
                label: strings.splitCardOldest(oldest.ageInDays),
                tone: StatusTone.warning,
              ),
            ),
        ],
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.label, required this.amount});

  final String label;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        // Through `AmountText`, and without a colour: that widget has no `tone` parameter and colours
        // from `kind` deliberately. The label above already says which figure this is, and a sentence
        // survives a screenshot where a hue does not.
        AmountText(amount, showSign: false),
      ],
    );
  }
}
