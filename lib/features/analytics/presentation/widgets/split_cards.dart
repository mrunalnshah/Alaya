import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/split_analytics_providers.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';
import 'package:alaya/features/analytics/presentation/widgets/slice_bar_list.dart';

/// What shared bills cost, from both sides (ARCH_5 §3 archetype F).
///
/// **The card this whole module was built to make possible.** You paid ₹1,000; you consumed ₹250.
/// Splitwise knows the second and nothing about your bank; your bank app knows the first and nothing
/// about the split. Both figures come from one set of rows here, and the gap between them is money still
/// out with somebody.
///
/// Three figures rather than a net one, for the reason decision 1 records: a receivable is not spendable,
/// and a single number invites reading it as though it were.
class SplitLensesCard extends ConsumerWidget {
  /// Creates the card.
  const SplitLensesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final value = ref.watch(splitLensesProvider);

    return ChartCard<SplitLenses?>(
      title: strings.analyticsSplitLensesTitle,
      subtitle: strings.analyticsSplitLensesSubtitle,
      value: value,
      // Null means the self payee is unset, which is a setup step rather than an absence of data — so
      // the empty message names the fix instead of suggesting there is nothing to show.
      isEmpty: (data) => data == null || data.expenseCount == 0,
      emptyMessage: value.valueOrNull == null
          ? strings.analyticsSplitNoSelf
          : strings.analyticsSplitEmpty,
      onRetry: () => ref.invalidate(splitLensesProvider),
      unconvertedCount: value.valueOrNull?.skippedForeignCount ?? 0,
      builder: (context, data) {
        final lenses = data!;
        final outstanding = Money(
          lenses.outflow.minor - lenses.myShare.minor - lenses.recovered.minor,
          lenses.outflow.currencyCode,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Lens(
              label: strings.analyticsSplitOutflow,
              help: strings.analyticsSplitOutflowHelp,
              amount: lenses.outflow,
              digits: digits,
            ),
            const SizedBox(height: AlayaSpacing.sm),
            _Lens(
              label: strings.analyticsSplitMyShare,
              help: strings.analyticsSplitMyShareHelp,
              amount: lenses.myShare,
              digits: digits,
            ),
            const SizedBox(height: AlayaSpacing.sm),
            _Lens(
              label: strings.analyticsSplitOutstanding,
              // The number a person actually feels: what left the account, minus what they consumed,
              // minus what has come back.
              help: strings.analyticsSplitOutstandingHelp,
              amount: outstanding,
              digits: digits,
            ),
          ],
        );
      },
    );
  }
}

class _Lens extends StatelessWidget {
  const _Lens({
    required this.label,
    required this.help,
    required this.amount,
    required this.digits,
  });

  final String label;
  final String help;
  final Money amount;
  final int digits;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    // A `Wrap`, not a `Row`: a label beside an amount at 320dp with the text scaler doubled is the
    // shape that overflows (Law U15).
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AlayaSpacing.sm,
      runSpacing: AlayaSpacing.xxs,
      children: [
        SizedBox(
          width: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AlayaTypography.body),
              Text(
                help,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
            ],
          ),
        ),
        AmountText(
          amount,
          size: AmountSize.small,
          showSign: false,
          decimalDigits: digits,
        ),
      ],
    );
  }
}

/// Who the user shares expenses with most.
class SplitPartnersCard extends ConsumerWidget {
  /// Creates the card.
  const SplitPartnersCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final value = ref.watch(splitPartnersProvider);

    return ChartCard<List<SplitPartner>>(
      title: strings.analyticsSplitPartnersTitle,
      subtitle: strings.analyticsSplitPartnersSubtitle,
      value: value,
      isEmpty: (data) => data.isEmpty,
      emptyMessage: strings.analyticsSplitEmpty,
      onRetry: () => ref.invalidate(splitPartnersProvider),
      builder: (context, data) {
        // `share` is against the largest slice, which is what sets each bar's length. Computed here
        // rather than inside the list, because only the caller knows whether the figures are money, a
        // quantity or a count.
        final largest = data.first.total.minor;
        return SliceBarList(
          slices: [
            for (final partner in data)
              SliceBar(
                label:
                    ref.watch(splitPayeeNameProvider(partner.payeeId)) ??
                    strings.splitUnknownPerson,
                // A rendered widget, not a `Money`. `SliceBar` takes one so the same list can show a
                // quantity — and formatting to a `String` here would bypass the only path from a
                // `Money` to pixels (Law U7).
                value: AmountText(
                  partner.total,
                  size: AmountSize.small,
                  showSign: false,
                  decimalDigits: digits,
                ),
                share: largest == 0 ? 0 : partner.total.minor / largest,
                detail: strings.analyticsSplitPartnerCount(
                  partner.expenseCount,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Shared spending by occasion, and by place.
///
/// **Two dimensions no competitor offers**, because no competitor stores them. They are columns on
/// `split_expenses` rather than words in a note, which is the whole difference between a searchable
/// dimension and a string somebody has to remember they typed.
class SplitDimensionCard extends ConsumerWidget {
  /// Creates the card for [byPlace] or, by default, by occasion.
  const SplitDimensionCard({this.byPlace = false, super.key});

  /// Whether this card groups by place rather than occasion.
  final bool byPlace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final provider = byPlace ? splitPlaceProvider : splitOccasionProvider;
    final value = ref.watch(provider);

    return ChartCard<List<({String label, Money total})>>(
      title: byPlace
          ? strings.analyticsSplitPlaceTitle
          : strings.analyticsSplitOccasionTitle,
      subtitle: byPlace
          ? strings.analyticsSplitPlaceSubtitle
          : strings.analyticsSplitOccasionSubtitle,
      value: value,
      isEmpty: (data) => data.isEmpty,
      // Names the field to fill in, because an empty result here almost always means nobody has typed an
      // occasion yet rather than that nothing was spent.
      emptyMessage: byPlace
          ? strings.analyticsSplitPlaceEmpty
          : strings.analyticsSplitOccasionEmpty,
      onRetry: () => ref.invalidate(provider),
      builder: (context, data) {
        final largest = data.first.total.minor;
        return SliceBarList(
          slices: [
            for (final row in data)
              SliceBar(
                label: row.label,
                value: AmountText(
                  row.total,
                  size: AmountSize.small,
                  showSign: false,
                  decimalDigits: digits,
                ),
                share: largest == 0 ? 0 : row.total.minor / largest,
              ),
          ],
        );
      },
    );
  }
}
