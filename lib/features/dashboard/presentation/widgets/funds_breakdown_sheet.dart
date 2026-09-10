/// Where the headline figure comes from (ARCH_5 §3 archetype A).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Which accounts the available-funds figure is made of.
///
/// **A sheet, not a route.** It is a read-only explanation you dismiss, which is archetype A — and a pushed
/// screen for something you glance at costs a back navigation for no gain.
///
/// It answers one question: *where is that number coming from?* So every account appears, including the ones
/// excluded from the total — a breakdown that silently omits accounts is one nobody can reconcile against
/// their own bank, which defeats the purpose of opening it.
class FundsBreakdownSheet extends ConsumerWidget {
  /// Creates the sheet.
  const FundsBreakdownSheet({super.key});

  /// Shows it. Prefer this over constructing the sheet directly.
  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const AlayaBottomSheet(child: FundsBreakdownSheet()),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final async = ref.watch(fundsBreakdownProvider);
    final digits = ref.watch(dashboardDigitsProvider).valueOrNull ?? 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionHeader(
          label: strings.fundsBreakdownTitle,
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
        ),
        async.when(
          loading: () => AlayaListSkeleton(label: strings.loadingDashboard),
          error: (error, stack) => ErrorState(
            title: strings.errorTitleGeneric,
            body: error.toString(),
            retryLabel: strings.actionRetry,
            onRetry: () => ref.invalidate(fundsBreakdownProvider),
          ),
          data: (rows) => rows.isEmpty
              ? EmptyState(
                  title: strings.fundsNoAccountsTitle,
                  body: strings.fundsNoAccountsBody,
                  icon: Icons.account_balance_wallet_outlined,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final row in rows)
                      _AccountRow(row: row, decimalDigits: digits),
                    if (rows.any((row) => !row.countsToward)) ...[
                      const SizedBox(height: AlayaSpacing.sm),
                      Text(
                        strings.fundsExcludedNote,
                        style: AlayaTypography.caption.copyWith(
                          color: semantic.muted,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// One account.
class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.row, required this.decimalDigits});

  final FundsRow row;
  final int decimalDigits;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final converted = row.converted;
    // A converted figure that differs from the original means this account is in another currency, and the
    // original belongs on screen too — otherwise the row claims a rupee balance the bank has never shown.
    final showOriginal =
        converted == null ||
        converted.currencyCode != row.original.currencyCode;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.account.name,
                  style: AlayaTypography.body.copyWith(
                    // Greyed, not hidden. An excluded account still has to appear or the list cannot be
                    // reconciled — it simply must not look like it is contributing.
                    color: row.countsToward ? null : semantic.muted,
                  ),
                ),
                if (showOriginal) ...[
                  const SizedBox(height: AlayaSpacing.xxs),
                  Row(
                    children: [
                      AmountText(
                        row.original,
                        size: AmountSize.small,
                        decimalDigits: decimalDigits,
                        muted: true,
                      ),
                      // `approximate`, not a `stale` member I invented — the enum is
                      // exact / approximate / unconverted. Law U9 requires an approximate figure to be
                      // marked as one, and this is the mark.
                      if (row.quality == RateQuality.approximate) ...[
                        const SizedBox(width: AlayaSpacing.xs),
                        // **`StatusChip`, not an icon I guessed at.** B6_SHARED names it "the single home
                        // for `needsReview`, `unallocated`, `detached`, `overdue`, `expiring`, `low`" and
                        // approximate — so a bare icon here would be a second vocabulary for a state that
                        // already has one. I reached for `Icons.approximate_outlined` and then
                        // `Icons.tilde`, neither of which exists; the answer was a widget, not a glyph.
                        StatusChip(
                          label: strings.statusApproximate,
                          tone: StatusTone.warning,
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AlayaSpacing.sm),
          // **Null converts to a word, never to zero** (anomaly A34). An account whose currency has no rate
          // is left out of the total, and saying "not counted" is the only honest thing to show — a nought
          // would read as an empty account.
          if (converted == null)
            Text(
              strings.fundsNotCounted,
              style: AlayaTypography.caption.copyWith(color: semantic.warning),
            )
          else
            AmountText(
              converted,
              decimalDigits: decimalDigits,
              muted: !row.countsToward,
            ),
        ],
      ),
    );
  }
}
