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
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_amount.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_donut_chart.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/presentation/widgets/slice_bar_list.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';

/// Query 1 — spend by subtype, tapping through to the ledger.
class SubtypeSpendCard extends ConsumerWidget {
  /// Creates the card.
  const SubtypeSpendCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;

    return ChartCard<MoneySeries>(
      title: strings.analyticsBySubtype,
      value: ref.watch(spendBySubtypeProvider),
      isEmpty: (series) => series.slices.isEmpty,
      emptyMessage: strings.analyticsNothingSpent,
      onRetry: () => ref.invalidate(spendBySubtypeProvider),
      approximateCount:
          ref
              .watch(spendBySubtypeProvider)
              .valueOrNull
              ?.quality
              .approximateCount ??
          0,
      unconvertedCount:
          ref
              .watch(spendBySubtypeProvider)
              .valueOrNull
              ?.quality
              .unconvertedCount ??
          0,
      builder: (context, series) {
        // **A partition, so a ring is honest here.** Subtypes are mutually exclusive — every withdrawal
        // has exactly one — so the wedges really do add up to the total in the header. The same
        // `analyticsSlices` call feeds the ring and the rows, so the fifth wedge and the fifth row
        // cannot end up different colours.
        final slices = analyticsSlices(
          context,
          [
            for (final slice in series.slices)
              (
                // `slice.key`, never `slice.label`: SQL grouped by the enum name, so the label is
                // `grocery` and rendering it would put an identifier on screen (Law U5).
                label: AnalyticsLabels.subtype(strings, slice.key),
                value: slice.amount.minor,
                key: slice.key,
              ),
          ],
          otherLabel: strings.analyticsOtherSlices,
        );
        final byKey = {
          for (final slice in series.slices) slice.key: slice.amount,
        };
        final leader = slices.isEmpty ? null : slices.first;
        final total = slices.fold<int>(0, (sum, slice) => sum + slice.value);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnalyticsDonutChart(
              slices: slices,
              centreTop: leader == null || total == 0
                  ? null
                  : AnalyticsLabels.percent(context, leader.value / total),
              centreBottom: leader?.label,
            ),
            const SizedBox(height: AlayaSpacing.sm),
            SliceBarList(
              // The ring carries the proportion, so the rows drop their bars and keep the swatch.
              showBars: false,
              slices: [
                for (final slice in slices)
                  SliceBar(
                    label: slice.label,
                    // The grouped remainder has no single amount of its own, so it is rebuilt from the
                    // magnitudes that went into it, in the home currency they were converted to.
                    value: analyticsAmount(
                      byKey[slice.key] ??
                          Money(
                            slice.value,
                            series.slices.first.amount.currencyCode,
                          ),
                      digits,
                    ),
                    share: total == 0 ? 0 : slice.value / total,
                    // **The share as a figure, not only as an arc.** Dropping the bar cost each row its
                    // sense of relative size, so the percentage replaces it — and a number is what a
                    // reader can act on, which a bar length never was.
                    detail: total == 0
                        ? null
                        : AnalyticsLabels.percent(context, slice.value / total),
                    swatch: slice.color,
                    onTap: slice.key == null
                        ? null
                        : () => context.push(
                            Routes.insightsDrillDown(
                              DrillDownKind.subtype.name,
                              slice.key!,
                            ),
                          ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Query 2 — spend by tag, with the one level of nesting the schema allows.
///
/// **This closes `tags.parentTagId`'s analytics half** (ARCH_5 §7.2). The drill is in place rather
/// than a route: a parent tag's children are a *view of the same figure*, so pushing a screen for
/// them would lose the total they roll up to.
class TagSpendCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const TagSpendCard({super.key});

  @override
  ConsumerState<TagSpendCard> createState() => _TagSpendCardState();
}

class _TagSpendCardState extends ConsumerState<TagSpendCard> {
  String? _openParentId;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final async = ref.watch(tagSpendTreeProvider);
    final quality = ref.watch(spendByTagProvider).valueOrNull?.quality;

    return ChartCard<List<TagSpendNode>>(
      title: strings.analyticsByTag,
      // The caveat belongs on the card rather than in a footnote: a transaction with two tags is in
      // both slices, so these do not add up to the headline and a reader comparing them deserves to
      // know why.
      subtitle: strings.analyticsByTagNote,
      value: async,
      isEmpty: (nodes) => nodes.isEmpty,
      emptyMessage: strings.analyticsNoTaggedSpend,
      onRetry: () => ref.invalidate(tagSpendTreeProvider),
      // `tagSpendTreeProvider` rolls slices into a tree and drops the series' quality on the way, so the
      // counts come from the series itself. No second query: `tagSpendTreeProvider` already watches it,
      // so Riverpod hands over the cached result.
      approximateCount: quality?.approximateCount ?? 0,
      unconvertedCount: quality?.unconvertedCount ?? 0,
      builder: (context, nodes) {
        // A plain loop rather than `firstOrNull`: that extension lives in `package:collection`,
        // which this project does not declare — importing a transitive dependency directly is what
        // `depend_on_referenced_packages` exists to catch (ARCH_1 §7.4's rule 2, from the other end).
        TagSpendNode? open;
        if (_openParentId != null) {
          for (final node in nodes) {
            if (node.tag.id == _openParentId) {
              open = node;
              break;
            }
          }
        }
        if (open == null) {
          final peak = analyticsPeak(nodes.map((n) => n.rolledUp));
          return SliceBarList(
            slices: [
              for (final node in nodes)
                SliceBar(
                  label: node.tag.name,
                  value: analyticsAmount(node.rolledUp, digits),
                  share: analyticsShare(node.rolledUp, peak),
                  detail: node.canDrill
                      ? strings.analyticsTagChildren(node.children.length)
                      : null,
                  // A leaf has nothing to open, so it gets no tap at all rather than a tap that does
                  // nothing — ARCH_5 §10's objection to a control that looks live and is not.
                  onTap: node.canDrill
                      ? () => setState(() => _openParentId = node.tag.id)
                      : null,
                ),
            ],
          );
        }

        final children = open.children;
        final peak = analyticsPeak([
          open.own,
          ...children.map((c) => c.rolledUp),
        ]);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DrillHeader(
              label: open.tag.name,
              total: open.rolledUp,
              decimalDigits: digits,
              onBack: () => setState(() => _openParentId = null),
            ),
            const SizedBox(height: AlayaSpacing.xs),
            SliceBarList(
              slices: [
                // The parent's own spend is a sibling of its children, not their sum: "Grocery
                // directly" and "Grocery > Vegetables" are different rows, and folding the first into
                // the second would misattribute it.
                if (open.own.minor > 0)
                  SliceBar(
                    label: strings.analyticsTagDirect(open.tag.name),
                    value: analyticsAmount(open.own, digits),
                    share: analyticsShare(open.own, peak),
                  ),
                for (final child in children)
                  SliceBar(
                    label: child.tag.name,
                    value: analyticsAmount(child.rolledUp, digits),
                    share: analyticsShare(child.rolledUp, peak),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The in-place drill's header: where you are, what it totals, and the way back.
class _DrillHeader extends StatelessWidget {
  const _DrillHeader({
    required this.label,
    required this.total,
    required this.decimalDigits,
    required this.onBack,
  });

  final String label;
  final Money total;
  final int decimalDigits;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    return Row(
      children: [
        // A labelled icon button, because "back" is one of the six glyphs ARCH_5 §2.7 lets stand
        // alone — but it still carries a tooltip so a screen reader names it.
        IconButton(
          onPressed: onBack,
          tooltip: strings.analyticsTagBack,
          icon: const Icon(Icons.arrow_back, size: AlayaIconSize.md),
        ),
        Expanded(
          child: Text(
            label,
            style: AlayaTypography.bodyEmphasis.copyWith(color: semantic.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        AmountText(
          total,
          size: AmountSize.small,
          showSign: false,
          decimalDigits: decimalDigits,
        ),
      ],
    );
  }
}

/// Query 3 — spend by payment method.
class PaymentMethodSpendCard extends ConsumerWidget {
  /// Creates the card.
  const PaymentMethodSpendCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final async = ref.watch(spendByPaymentMethodProvider);

    return ChartCard<MoneySeries>(
      title: strings.analyticsByMethod,
      value: async,
      isEmpty: (series) => series.slices.isEmpty,
      emptyMessage: strings.analyticsNoMethodSpend,
      onRetry: () => ref.invalidate(spendByPaymentMethodProvider),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, series) {
        final peak = analyticsPeak(series.slices.map((s) => s.amount));
        return SliceBarList(
          slices: [
            for (final slice in series.slices)
              SliceBar(
                // A payment method's name **is** data, so it renders directly.
                label: slice.label,
                value: analyticsAmount(slice.amount, digits),
                share: analyticsShare(slice.amount, peak),
                onTap: () => context.push(
                  Routes.insightsDrillDown(
                    DrillDownKind.paymentMethod.name,
                    slice.key,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Queries 8 and 22 — how concentrated spending is, and groceries' share of it.
///
/// One card for both, because they answer the same question at two grains: "is my spending spread or
/// clustered", then "and is the cluster food". Two cards would put the same total on screen twice.
class ConcentrationCard extends ConsumerWidget {
  /// Creates the card.
  const ConcentrationCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final async = ref.watch(analyticsHeadlineProvider);
    final grocery = ref.watch(groceryShareProvider).valueOrNull;

    return ChartCard<Concentration>(
      title: strings.analyticsConcentration,
      value: async,
      isEmpty: (c) => c.top.isEmpty,
      emptyMessage: strings.analyticsNothingSpent,
      onRetry: () => ref.invalidate(analyticsHeadlineProvider),
      // `Concentration` carries a quality and this card read neither count. A concentration figure that
      // silently excluded an unconvertible amount would report a household as more concentrated than it
      // is, because the excluded slice is missing from the denominator too (anomaly A15).
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, concentration) {
        // **The remainder is supplied rather than derived.** This card knows the whole — the header's
        // total — and shows only the top three, so what the ring needs is the difference. Deriving it
        // from the three slices would draw a ring of three wedges that filled the circle and asserted
        // that three kinds were all of the spending.
        final top = concentration.top.fold<int>(
          0,
          (sum, s) => sum + s.amount.minor,
        );
        final slices = analyticsSlices(
          context,
          [
            for (final slice in concentration.top)
              (
                label: AnalyticsLabels.subtype(strings, slice.key),
                value: slice.amount.minor,
                key: slice.key,
              ),
          ],
          otherLabel: strings.analyticsOtherSlices,
          remainder: concentration.total.minor - top,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnalyticsDonutChart(
              slices: slices,
              centreTop: _percent(context, concentration.topShare),
              centreBottom: strings.analyticsTopThree,
            ),
            const SizedBox(height: AlayaSpacing.sm),
            Text(
              strings.analyticsTopShare(
                _percent(context, concentration.topShare),
              ),
              style: AlayaTypography.bodyEmphasis,
            ),
            const SizedBox(height: AlayaSpacing.sm),
            SliceBarList(
              showBars: false,
              slices: [
                for (var i = 0; i < concentration.top.length; i++)
                  SliceBar(
                    label: AnalyticsLabels.subtype(
                      strings,
                      concentration.top[i].key,
                    ),
                    value: analyticsAmount(concentration.top[i].amount, digits),
                    share: concentration.top[i].share,
                    detail: _percent(context, concentration.top[i].share),
                    swatch: i < slices.length ? slices[i].color : null,
                  ),
              ],
            ),
            if (grocery != null) ...[
              const SizedBox(height: AlayaSpacing.sm),
              Text(
                strings.analyticsGroceryShare(_percent(context, grocery.share)),
                style: AlayaTypography.caption.copyWith(
                  color: context.semantic.muted,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _percent(BuildContext context, double share) =>
      AnalyticsLabels.percent(context, share);
}
