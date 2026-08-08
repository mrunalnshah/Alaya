import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/services/date_range_service.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/features/dashboard/providers/range_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Money in and money out over one window, always labelled with what the window means.
///
/// **The label is not decoration** (anomaly A33). "Last month" is ambiguous between the previous calendar
/// month and the preceding thirty days, and no user can tell which they are looking at from the figures
/// alone — so the row states its window in words and the provider computes exactly that window. A range
/// row without its label is a number with no meaning.
///
/// **Transfers are not counted.** Money moving between the user's own accounts is neither income nor
/// expenditure, and including it would double both figures and net to a lie.
///
/// ## Two cells, split by a rule, rather than a sentence of four words
///
/// The first version laid the two legs out as a `Wrap` of `label figure  label figure`, which reads as
/// prose and makes the eye parse before it can compare. In and out are a **pair** — the whole reason to
/// show them together is that one is measured against the other — so they get equal halves and a hairline
/// between them, and the caption sits above its figure rather than beside it. That halves the row's width
/// and lets the two windows stack tightly enough to read as one block.
///
/// **The figures scale down rather than truncate.** U7 forbids clipping a `Money`, because half a number
/// reads as a smaller number — but a fixed half-width cell at a doubled text scale cannot always hold one.
/// `BoxFit.scaleDown` keeps every digit and gives up type-scale fidelity instead, which is the correct
/// trade: a figure one step smaller than its token is still true, and an overflowed one is a crash.
class RangeRow extends ConsumerWidget {
  /// Creates a row over [range], described by [label].
  const RangeRow({required this.label, required this.range, super.key});

  /// What this window means, in words.
  final String label;

  /// The window itself.
  final DateRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final async = ref.watch(rangeTotalsProvider(range));
    final digits = ref.watch(dashboardDigitsProvider).valueOrNull ?? 2;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AlayaTypography.label.copyWith(color: semantic.muted),
          ),
          const SizedBox(height: AlayaSpacing.xxs),
          async.when(
            loading: () => Text(
              strings.loadingDashboard,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            // Inline, and it keeps the label: a failed conversion must not take the window's meaning down
            // with it, and the reader still needs to know which row broke.
            error: (error, stack) => Text(
              error.toString(),
              style: AlayaTypography.caption.copyWith(color: semantic.danger),
            ),
            data: (totals) => totals.isEmpty
                ? Text(
                    strings.rangeNothingYet,
                    style: AlayaTypography.body.copyWith(color: semantic.muted),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Split(
                        left: _Leg(
                          label: strings.rangeMoneyIn,
                          amount: totals.moneyIn,
                          kind: TransactionKind.deposit,
                          digits: digits,
                        ),
                        right: _Leg(
                          label: strings.rangeMoneyOut,
                          amount: totals.moneyOut,
                          kind: TransactionKind.withdrawal,
                          digits: digits,
                        ),
                      ),
                      // Below the pair, not inside it. The chip is a caveat about the figures, and a
                      // caveat sitting in one of the two cells looks like it belongs to that cell alone.
                      if (totals.excludedCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: AlayaSpacing.xs),
                          child: StatusChip(
                            label: strings.rangeExcluded(totals.excludedCount),
                            tone: StatusTone.warning,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Two equal cells with a hairline between them.
class _Split extends StatelessWidget {
  const _Split({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // `IntrinsicHeight` so the rule can stretch to the taller cell. Without it, `stretch` asks for the
    // incoming maxHeight — unbounded inside the dashboard's sliver — and the layout throws.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Equal halves, so the two figures start at predictable places and the eye can compare them
          // without measuring. Neither cell can starve the other (Law U21) because neither is intrinsic.
          Expanded(child: left),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.sm),
            child: SizedBox(
              width: 1,
              // `outlineVariant` is Material 3's divider role. Using it rather than a muted text colour
              // at low opacity keeps the rule at divider weight across every palette preset.
              child: ColoredBox(color: theme.colorScheme.outlineVariant),
            ),
          ),
          Expanded(child: right),
        ],
      ),
    );
  }
}

/// One side of the split: what it is, then how much.
class _Leg extends StatelessWidget {
  const _Leg({
    required this.label,
    required this.amount,
    required this.kind,
    required this.digits,
  });

  final String label;
  final Money amount;
  final TransactionKind kind;
  final int digits;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        // Left-aligned as it shrinks, so both figures keep a common left edge whatever their length.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AmountText(
            amount,
            size: AmountSize.small,
            showSign: false,
            decimalDigits: digits,
            kind: kind,
          ),
        ),
      ],
    );
  }
}
