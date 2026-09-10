import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_durations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/dashboard/presentation/widgets/funds_breakdown_sheet.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Total available funds — the one `displayAmount` on the dashboard (ARCH_5 §3 archetype F).
///
/// **One headline, because two headline numbers is no headline number.** Every other figure on this
/// screen is `AmountSize.small` or smaller, and that hierarchy is the whole reason a glance works.
///
/// **The figure comes from `BalanceService.totalInHome` and nothing else.** A self-transfer cannot move
/// it: the balances behind it come from `v_account_ledger`, which counts a transfer once against each
/// side. If this number ever changes when money moves between the user's own accounts, the view is being
/// bypassed rather than the arithmetic being wrong.
///
/// **What cannot be converted is excluded and said out loud** (anomaly A34). Summing a dirham balance
/// into a rupee total at face value would be a wrong number presented as a right one; a smaller number
/// with a chip beside it is honest, and the chip explains itself rather than just counting.
class FundsHeader extends ConsumerWidget {
  /// Creates the header.
  const FundsHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final async = ref.watch(totalFundsProvider);
    final digits = ref.watch(dashboardDigitsProvider).valueOrNull ?? 2;

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.md),
      // **Tappable only once there is a figure to explain.** Offering the breakdown while the rate table
      // is still loading would open a sheet showing nothing, and offering it on an error would explain a
      // number that is not there.
      onTap: async.hasValue ? () => FundsBreakdownSheet.show(context) : null,
      child: async.when(
        // Its own skeleton rather than the screen's: a slow rate table must not blank the range rows or
        // the module grid beneath it (ARCH_5 §3 archetype F).
        loading: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.fundsAvailable,
              style: AlayaTypography.label.copyWith(color: semantic.muted),
            ),
            const SizedBox(height: AlayaSpacing.xs),
            Text(
              strings.loadingDashboard,
              style: AlayaTypography.body.copyWith(color: semantic.muted),
            ),
          ],
        ),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(totalFundsProvider),
        ),
        data: (worth) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.fundsAvailable,
              style: AlayaTypography.label.copyWith(color: semantic.muted),
            ),
            const SizedBox(height: AlayaSpacing.xs),
            // **ARCH_5 §2.6's fourth animation, and the only place it belongs.** A total that recalculates
            // should show *that* it changed — otherwise a figure quietly becoming a different figure is
            // indistinguishable from one that was always that. This is the app's headline number and the only
            // one that moves on its own, when a transaction lands or a rate is fetched.
            //
            // Keyed on the amount, so an identical recomputation does not blink. `AlayaDurations.base`, per the
            // token §2.6 names. Under reduced motion the duration collapses to zero, which is a **skip** rather
            // than a shortening: the new value simply replaces the old with no cross-fade at all.
            AnimatedSwitcher(
              duration: MediaQuery.maybeDisableAnimationsOf(context) ?? false
                  ? Duration.zero
                  : AlayaDurations.base,
              child: AmountText(
                worth.total,
                key: ValueKey<int>(worth.total.minor),
                // The one `displayAmount` on the screen (ARCH_5 §2.3). Omitting this fell back to
                // `AmountSize.medium` — the ledger-row size — which left the dashboard with no headline
                // at all while every doc comment claimed it had one.
                size: AmountSize.display,
                showSign: false,
                decimalDigits: digits,
              ),
            ),
            if (!worth.isComplete || worth.isApproximate) ...[
              const SizedBox(height: AlayaSpacing.sm),
              Wrap(
                spacing: AlayaSpacing.xs,
                runSpacing: AlayaSpacing.xxs,
                children: [
                  if (!worth.isComplete)
                    StatusChip(
                      label: strings.fundsUnconverted(worth.unconvertedCount),
                      tone: StatusTone.warning,
                    ),
                  if (worth.isApproximate)
                    StatusChip(
                      label: strings.fundsApproximate,
                      tone: StatusTone.info,
                    ),
                ],
              ),
              if (!worth.isComplete) ...[
                const SizedBox(height: AlayaSpacing.xs),
                Text(
                  strings.fundsWhyExcluded,
                  style: AlayaTypography.caption.copyWith(
                    color: semantic.muted,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
