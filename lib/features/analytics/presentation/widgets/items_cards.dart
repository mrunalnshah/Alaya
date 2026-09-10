import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_formatter.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_amount.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/presentation/widgets/slice_bar_list.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/qty_text.dart';

/// Query 4 — the top payees by spend.
class TopPayeesCard extends ConsumerWidget {
  /// Creates the card.
  const TopPayeesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final async = ref.watch(topPayeesProvider);

    return ChartCard<MoneySeries>(
      title: strings.analyticsTopPayees,
      value: async,
      isEmpty: (series) => series.slices.isEmpty,
      emptyMessage: strings.analyticsNoPayees,
      onRetry: () => ref.invalidate(topPayeesProvider),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, series) {
        final peak = analyticsPeak(series.slices.map((s) => s.amount));
        return SliceBarList(
          slices: [
            for (final slice in series.slices)
              SliceBar(
                label: slice.label,
                value: analyticsAmount(slice.amount, digits),
                share: analyticsShare(slice.amount, peak),
                onTap: () => context.push(
                  Routes.insightsDrillDown(DrillDownKind.payee.name, slice.key),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Query 9 — the top items by spend.
class TopItemsBySpendCard extends ConsumerWidget {
  /// Creates the card.
  const TopItemsBySpendCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final async = ref.watch(topItemsBySpendProvider);

    return ChartCard<List<ItemSpend>>(
      title: strings.analyticsTopItems,
      value: async,
      isEmpty: (items) => items.isEmpty,
      emptyMessage: strings.analyticsNoItemisedSpend,
      onRetry: () => ref.invalidate(topItemsBySpendProvider),
      builder: (context, items) {
        final peak = analyticsPeak(items.map((i) => i.amount));
        return SliceBarList(
          slices: [
            for (final item in items)
              SliceBar(
                label: item.itemName,
                value: analyticsAmount(item.amount, digits),
                share: analyticsShare(item.amount, peak),
                detail: strings.analyticsPurchaseCount(item.purchaseCount),
                onTap: () => context.push(
                  Routes.insightsDrillDown(
                    DrillDownKind.item.name,
                    item.itemId,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Query 10 — the top items by quantity bought, grouped by measure.
///
/// **Grouped rather than ranked, because Law L8 makes the categories incomparable.** There is no
/// gram-to-piece conversion anywhere in this app, so a single ordering would put 4 kg of potatoes above
/// 30 eggs and mean nothing at all. Each measure gets its own bars, each measured against its own peak.
class TopItemsByQuantityCard extends ConsumerWidget {
  /// Creates the card.
  const TopItemsByQuantityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(topItemsByQuantityProvider);

    return ChartCard<List<ItemQuantity>>(
      title: strings.analyticsTopByQuantity,
      subtitle: strings.analyticsTopByQuantityNote,
      value: async,
      isEmpty: (items) => items.isEmpty,
      emptyMessage: strings.analyticsNoQuantities,
      onRetry: () => ref.invalidate(topItemsByQuantityProvider),
      builder: (context, items) {
        final byCategory = <UnitCategory, List<ItemQuantity>>{};
        for (final item in items) {
          byCategory
              .putIfAbsent(item.quantity.category, () => <ItemQuantity>[])
              .add(item);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in byCategory.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: AlayaSpacing.xs),
                child: Text(
                  AnalyticsLabels.unitCategory(strings, entry.key),
                  style: AlayaTypography.sectionHeader.copyWith(
                    color: context.semantic.muted,
                  ),
                ),
              ),
              SliceBarList(
                maxRows: _rowsPerCategory,
                slices: [
                  for (final item in entry.value)
                    SliceBar(
                      label: item.itemName,
                      // A `Qty` through `QtyText` and never `toString()` (Law U7). `mixed` is the
                      // default style — "4 kg 450 g" — which is what an item row wants; `compact` is
                      // for a chart axis.
                      value: QtyText(item.quantity, style: UnitStyle.mixed),
                      share: _quantityShare(item.quantity, entry.value),
                      detail: strings.analyticsPurchaseCount(
                        item.purchaseCount,
                      ),
                      onTap: () => context.push(
                        Routes.insightsDrillDown(
                          DrillDownKind.item.name,
                          item.itemId,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  /// Four per measure: three measures at six rows each would make this the longest card on the screen.
  static const int _rowsPerCategory = 4;

  double _quantityShare(Qty quantity, List<ItemQuantity> withinCategory) {
    var peak = 0;
    for (final item in withinCategory) {
      if (item.quantity.milliBase > peak) peak = item.quantity.milliBase;
    }
    return peak == 0 ? 0 : quantity.milliBase / peak;
  }
}

/// Query 11 — the dearest single purchase of the item spent most on.
///
/// **The figure is in the currency it was bought in, unconverted.** "The most I ever paid" is a fact
/// about that purchase, and restating it at today's rate would silently change a historical number.
class DearestPurchaseCard extends ConsumerWidget {
  /// Creates the card.
  const DearestPurchaseCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final top = ref.watch(topItemsBySpendProvider).valueOrNull;
    if (top == null || top.isEmpty) return const SizedBox.shrink();

    final item = top.first;
    final ref0 = (id: item.itemId, name: item.itemName);
    final async = ref.watch(dearestPurchaseProvider(ref0));
    final digits =
        ref
            .watch(analyticsDigitsForCurrencyProvider(item.amount.currencyCode))
            .valueOrNull ??
        2;

    return ChartCard<DearestPurchase?>(
      title: strings.analyticsDearest,
      value: async,
      isEmpty: (purchase) => purchase == null,
      emptyMessage: strings.analyticsNoUnitPrices,
      onRetry: () => ref.invalidate(dearestPurchaseProvider(ref0)),
      builder: (context, purchase) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyValueRow(
            label: strings.analyticsDearestItem,
            value: purchase!.itemName,
          ),
          KeyValueRow(
            label: strings.analyticsDearestPrice,
            valueWidget: AmountText(
              purchase.unitPrice,
              size: AmountSize.small,
              showSign: false,
              decimalDigits: digits,
            ),
          ),
          KeyValueRow(
            label: strings.analyticsDearestWhen,
            valueWidget: DateText(purchase.on, style: DateTextStyle.medium),
          ),
        ],
      ),
    );
  }
}

/// Query 23 — the average grocery basket.
class AverageBasketCard extends ConsumerWidget {
  /// Creates the card.
  const AverageBasketCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final async = ref.watch(averageBasketProvider);

    return ChartCard<BasketStats>(
      title: strings.analyticsAverageBasket,
      value: async,
      isEmpty: (stats) => stats.basketCount == 0,
      emptyMessage: strings.analyticsNoBaskets,
      onRetry: () => ref.invalidate(averageBasketProvider),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, stats) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyValueRow(
            label: strings.analyticsBasketValue,
            valueWidget: AmountText(
              stats.averageValue,
              size: AmountSize.small,
              showSign: false,
              decimalDigits: digits,
            ),
          ),
          KeyValueRow(
            label: strings.analyticsBasketLines,
            // One decimal: "4.3 items" is the answer, and rounding it to 4 would lose the only thing
            // an average adds over a count.
            value: stats.averageLineCount.toStringAsFixed(1),
          ),
          KeyValueRow(
            label: strings.analyticsBasketCount,
            // **Baskets that CONVERTED, not all of them.** `AnalyticsService` divides by the ones it
            // could convert, so reporting the full count beside that average would describe a
            // different calculation.
            value: '${stats.basketCount}',
          ),
        ],
      ),
    );
  }
}
