import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty_formatter.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_amount.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Query 13 — what the stock on hand is worth, per currency.
///
/// **Per currency and never one figure** (anomaly A34): a batch's cost currency is its own column, so a
/// single total would be adding rupees to yen. Uncosted stock is counted and said out loud rather than
/// omitted, because a valuation that quietly skipped it would look complete while understating the
/// shelf.
class InventoryValueCard extends ConsumerWidget {
  /// Creates the card.
  const InventoryValueCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(inventoryValueProvider);

    return ChartCard<InventoryValue>(
      title: strings.analyticsInventoryValue,
      // Stated because this is the one figure on the screen the range chip does not change: stock on
      // hand is "right now", and a reader who narrowed the window would otherwise wonder why.
      subtitle: strings.analyticsInventoryValueNote,
      value: async,
      isEmpty: (value) => value.byCurrency.isEmpty && value.batchesNoCost == 0,
      emptyMessage: strings.analyticsNoStockValue,
      onRetry: () => ref.invalidate(inventoryValueProvider),
      builder: (context, value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in value.byCurrency.entries)
            KeyValueRow(
              label: entry.key,
              valueWidget: AnalyticsCurrencyAmount(entry.value),
            ),
          const SizedBox(height: AlayaSpacing.xs),
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xxs,
            children: [
              StatusChip(
                label: strings.analyticsBatchesValued(value.batchesValued),
              ),
              if (value.batchesNoCost > 0)
                StatusChip(
                  label: strings.analyticsBatchesNoCost(value.batchesNoCost),
                  tone: StatusTone.info,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Query 14 — food waste, in quantity and money.
///
/// **One of the app's three differentiating insights** (ARCH_3 §5.1). It exists because
/// `stock_movements` records *why* stock left — `waste` and `expired` are their own kinds — so throwing
/// food away is a fact the ledger holds rather than an absence to be inferred.
///
/// Reversed movements are already excluded by the adapter, so this counts what was wasted and not what
/// was wasted and then undone.
class WasteCard extends ConsumerWidget {
  /// Creates the card.
  const WasteCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(wasteTotalsProvider);

    return ChartCard<List<ItemWasteTotal>>(
      title: strings.analyticsWaste,
      value: async,
      isEmpty: (totals) => totals.isEmpty,
      // The empty state here is good news, and it should read that way rather than as an absence of
      // data (ARCH_5 §2.8: never apologise, name what is true).
      emptyMessage: strings.analyticsNoWaste,
      onRetry: () => ref.invalidate(wasteTotalsProvider),
      builder: (context, totals) {
        // Totalled **per currency**, not across them. Where a household records everything in one
        // currency — which is the ordinary case — this is the headline: "you threw away ₹340 of food".
        // Where it does not, each currency gets its own line rather than a sum that would be wrong.
        final byCurrency = <String, int>{};
        for (final total in totals) {
          for (final cost in total.costByCurrency.entries) {
            byCurrency.update(
              cost.key,
              (minor) => minor + cost.value.minor,
              ifAbsent: () => cost.value.minor,
            );
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in byCurrency.entries)
              AnalyticsCurrencyAmount(
                Money(entry.value, entry.key),
                size: AmountSize.large,
              ),
            const SizedBox(height: AlayaSpacing.sm),
            for (final total in totals.take(_maxItems))
              Padding(
                padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
                child: Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(total.itemName, style: AlayaTypography.body),
                    QtyText(
                      total.quantity,
                      style: UnitStyle.mixed,
                      muted: true,
                    ),
                    for (final cost in total.costByCurrency.values)
                      AnalyticsCurrencyAmount(cost),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  static const int _maxItems = 5;
}

/// Query 15 — what is about to expire.
class ExpiringCard extends ConsumerWidget {
  /// Creates the card.
  const ExpiringCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(expiringBatchesProvider(expiryHorizonDays));

    return ChartCard<List<ExpiringBatch>>(
      title: strings.analyticsExpiring(expiryHorizonDays),
      value: async,
      isEmpty: (batches) => batches.isEmpty,
      emptyMessage: strings.analyticsNothingExpiring,
      onRetry: () => ref.invalidate(expiringBatchesProvider(expiryHorizonDays)),
      builder: (context, batches) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final batch in batches.take(_maxRows))
            Padding(
              padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
              // A `Wrap`, so the name, the quantity, the date and the chip reflow among themselves
              // rather than starving each other at a raised text scale (Law U21).
              child: Wrap(
                spacing: AlayaSpacing.xs,
                runSpacing: AlayaSpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(batch.itemName, style: AlayaTypography.body),
                  QtyText(batch.remaining, style: UnitStyle.mixed, muted: true),
                  DateText(
                    batch.expiry,
                    style: DateTextStyle.dayMonth,
                    muted: true,
                  ),
                  // Colour is never the only signal (Law U17): the chip carries the day count in
                  // words as well as the tone.
                  StatusChip(
                    label: batch.daysLeft <= 0
                        ? strings.analyticsExpiredAlready
                        : strings.analyticsDaysLeft(batch.daysLeft),
                    tone: batch.daysLeft <= 0
                        ? StatusTone.danger
                        : batch.daysLeft <= _urgentDays
                        ? StatusTone.warning
                        : StatusTone.neutral,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static const int _maxRows = 6;

  /// Inside this many days an expiry is amber rather than neutral, matching ARCH_3 §6's own threshold
  /// for `batchExpiry` so the calendar and this card agree about what "soon" means.
  static const int _urgentDays = 7;
}

/// Query 16 — how many items are low on stock, right now.
class LowStockCard extends ConsumerWidget {
  /// Creates the card.
  const LowStockCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(lowStockTodayProvider);

    return ChartCard<LowStockPoint>(
      title: strings.analyticsLowStock,
      // **One point, not a history, and the card says so.** `v_low_stock` reflects the present and
      // stock is not versioned, so "how many were low last Tuesday" would mean replaying the movement
      // ledger against thresholds that may since have changed.
      subtitle: strings.analyticsLowStockNote,
      value: async,
      isEmpty: (point) => point.itemCount == 0,
      emptyMessage: strings.analyticsNothingLow,
      onRetry: () => ref.invalidate(lowStockTodayProvider),
      builder: (context, point) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.analyticsLowStockCount(point.itemCount),
            style: AlayaTypography.bodyEmphasis.copyWith(
              color: context.semantic.warning,
            ),
          ),
          const SizedBox(height: AlayaSpacing.xxs),
          Row(
            children: [
              Text(
                strings.analyticsAsOf,
                style: AlayaTypography.caption.copyWith(
                  color: context.semantic.muted,
                ),
              ),
              const SizedBox(width: AlayaSpacing.xxs),
              DateText(point.date, style: DateTextStyle.medium, muted: true),
            ],
          ),
        ],
      ),
    );
  }
}
