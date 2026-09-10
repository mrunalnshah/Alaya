# F_ANALYTICS

Analytics home, query surfaces, drill-down.

**27 files · 5,797 lines.**  Written 2026-08-27T08:54:37-04:00.

Every file below is complete and current. Paths are destinations.

---

### `lib/features/analytics/presentation/screens/analytics_home_screen.dart`

```dart
import 'package:alaya/features/analytics/presentation/widgets/split_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_header.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_range_row.dart';
import 'package:alaya/features/analytics/presentation/widgets/cache_row.dart';
import 'package:alaya/features/analytics/presentation/widgets/commitment_cards.dart';
import 'package:alaya/features/analytics/presentation/widgets/home_cards.dart';
import 'package:alaya/features/analytics/presentation/widgets/inflation_card.dart';
import 'package:alaya/features/analytics/presentation/widgets/items_cards.dart';
import 'package:alaya/features/analytics/presentation/widgets/spend_cards.dart';
import 'package:alaya/features/analytics/presentation/widgets/time_cards.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// The analytics overview (ARCH_5 §3 archetype F).
///
/// **No `Scaffold` and no app bar.** `Routes.insights` sits inside the drawer shell, which owns both —
/// the same shape `CalendarScreen` takes. That is also why the clear-cache action is a row at the foot of
/// this screen rather than an app-bar item: a bar action would belong to `_ShellScaffold` and appear on
/// all nine destinations.
///
/// **No FAB either**, unlike the dashboard. Archetype F lists one, and nothing on an analytics screen is
/// a capture action — the drawer and the dashboard own adding money. A FAB whose only job is to leave the
/// screen it floats over is decoration.
///
/// **One `displayAmount`**, in `AnalyticsHeader`. Every other figure here is `AmountSize.small` or
/// `large`, and that hierarchy is the only reason a glance works.
///
/// **Twenty-two cards, twenty-two independent failures.** Each owns its loading, empty and error state
/// inline through `ChartCard`, so an unreachable rate table costs the reader one figure rather than the
/// screen (archetype F).
///
/// **The sections are a lazy sliver list, and that is a performance decision rather than a style one.**
/// A `SliverToBoxAdapter` holding a `Column` builds every child on mount, which here would fire
/// twenty-two SQL aggregates the moment the drawer closed — precisely the risk ARCH_4 R7 names. A
/// `SliverList` builds only what is on screen, so the commitment queries do not run until somebody
/// scrolls to them.
class AnalyticsHomeScreen extends ConsumerWidget {
  /// Creates the screen.
  const AnalyticsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final headline = ref.watch(analyticsHeadlineProvider);
    // Empty only once the headline has actually resolved: treating a pending read as empty would flash
    // the empty state on every range change (Law U4 — loading and empty are different states).
    final nothingSpent = headline.valueOrNull?.top.isEmpty ?? false;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AlayaSpacing.screenEdge,
            AlayaSpacing.md,
            AlayaSpacing.screenEdge,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AnalyticsHeader(),
                const SizedBox(height: AlayaSpacing.sm),
                const AnalyticsRangeRow(),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlayaSpacing.screenEdge,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              nothingSpent
                  ? _emptySections(context, strings)
                  : _sections(strings),
            ),
          ),
        ),
      ],
    );
  }

  /// The full screen, in the order somebody reads it: the signature insight, then where the money went,
  /// then how it moved, then what it bought, then the house, then what is already committed.
  List<Widget> _sections(AlayaStrings strings) => [
    const SizedBox(height: AlayaSpacing.sm),
    const InflationCard(),
    _header(strings.analyticsSectionSpend),
    const SubtypeSpendCard(),
    _gap,
    const TagSpendCard(),
    _gap,
    const PaymentMethodSpendCard(),
    _gap,
    const ConcentrationCard(),
    _header(strings.analyticsSectionTime),
    const IncomeVsExpenseCard(),
    _gap,
    const NetCashFlowCard(),
    _gap,
    const BalanceTrendCard(),
    _gap,
    const SpendHeatmapCard(),
    _header(strings.analyticsSectionWhat),
    const TopPayeesCard(),
    _gap,
    const TopItemsBySpendCard(),
    _gap,
    const TopItemsByQuantityCard(),
    _gap,
    const DearestPurchaseCard(),
    _gap,
    const AverageBasketCard(),
    _header(strings.analyticsSectionSplit),
    const SplitLensesCard(),
    _gap,
    const SplitPartnersCard(),
    _gap,
    const SplitDimensionCard(),
    _gap,
    const SplitDimensionCard(byPlace: true),
    ..._homeSections(strings),
  ];

  /// What survives an empty window.
  ///
  /// **The house section is not range-dependent and stays.** Stock on hand, what is expiring and what is
  /// low are all "right now" figures, so hiding them because nothing was *spent* in the chosen range
  /// would withhold the answers that are still true. Only the spend-driven sections are replaced.
  List<Widget> _emptySections(BuildContext context, AlayaStrings strings) => [
    const SizedBox(height: AlayaSpacing.xl),
    EmptyState(
      title: strings.analyticsEmptyTitle,
      // Names both ways out — widen the window, or record something — because on a fresh install
      // the second is the answer and on a quiet month the first is (ARCH_5 §2.8).
      body: strings.analyticsEmptyBody,
      icon: Icons.insights_outlined,
      actionLabel: strings.addExpense,
      onAction: () => context.push(Routes.transactionNew),
    ),
    const SizedBox(height: AlayaSpacing.xl),
    ..._homeSections(strings),
  ];

  List<Widget> _homeSections(AlayaStrings strings) => [
    _header(strings.analyticsSectionHome),
    const InventoryValueCard(),
    _gap,
    const WasteCard(),
    _gap,
    const ExpiringCard(),
    _gap,
    const LowStockCard(),
    _header(strings.analyticsSectionCommitments),
    const MonthlyCommitmentCard(),
    _gap,
    const RecurringSplitCard(),
    _gap,
    const ServiceCostCard(),
    _gap,
    const WarrantyCard(),
    const SizedBox(height: AlayaSpacing.xl),
    const CacheRow(),
    // Clears the bottom of the viewport so the last row is not flush against the edge.
    const SizedBox(height: AlayaSpacing.xxxl),
  ];

  /// `xl` above a section header and `xs` below it, per ARCH_5 §2.2.
  static Widget _header(String label) => Padding(
    padding: const EdgeInsets.only(
      top: AlayaSpacing.xl,
      bottom: AlayaSpacing.xs,
    ),
    child: SectionHeader(label: label, padding: EdgeInsets.zero),
  );

  /// Between two cards. `sm` is the between-related-rows step (ARCH_5 §2.2).
  static const Widget _gap = SizedBox(height: AlayaSpacing.sm);
}
```

### `lib/features/analytics/presentation/screens/drill_down_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_amount.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/drill_down_providers.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';

/// The transactions behind one analytics slice (ARCH_5 §3 archetype C).
///
/// **Outside the drawer shell, so it owns its `Scaffold` and gets a back arrow.** `AppBar` resolves its
/// leading slot by checking `hasDrawer` before `canPop`, so a drill-down rendered inside the shell would
/// show a hamburger where back belongs (Law U18) — and a drill-down pushes rather than switching, which
/// is the half of Law U27 that applies here.
///
/// **Grouped by day with sticky headers**, exactly as the expense ledger is: a finance list without date
/// grouping is unreadable past twenty rows, and a drill-down that grouped differently from the ledger it
/// drills into would read as a different app.
///
/// **The window is inherited, never in the route** (ARCH_5 §5.7). Somebody who set the range to "this
/// year" and tapped a slice expects this year's transactions; a date in the path would let the two
/// disagree the moment either changed.
///
/// **No pull-to-refresh** (archetype C): the data is local and streamed, and a refresh gesture that
/// cannot do anything teaches the reader the app is slow.
class DrillDownScreen extends ConsumerWidget {
  /// Creates the screen for [spec], or an explanatory state when the route could not be parsed.
  const DrillDownScreen({required this.spec, super.key});

  /// What is filtered. Null when the path parameters named no axis this build knows.
  final DrillDownSpec? spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final resolved = spec;

    if (resolved == null) {
      // A drill-down route is deep-linkable, so a malformed one is reachable from outside the app. It
      // explains itself and offers the way on rather than throwing (Law U9, ARCH_5 §2.8).
      return Scaffold(
        appBar: AppBar(title: Text(strings.analyticsDrillTitle)),
        body: EmptyState(
          title: strings.analyticsDrillUnknownTitle,
          body: strings.analyticsDrillUnknownBody,
          icon: Icons.filter_alt_off_outlined,
          actionLabel: strings.navInsights,
          onAction: () => context.go(Routes.insights),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_title(strings, resolved, ref))),
      body: Column(
        children: [
          _ActiveFilter(spec: resolved),
          Expanded(child: _GroupedList(spec: resolved)),
        ],
      ),
    );
  }

  /// The screen's title: the resolved name where the label is data, an ARB string where it is not.
  String _title(AlayaStrings strings, DrillDownSpec spec, WidgetRef ref) {
    final resolved = ref.watch(drillDownLabelProvider(spec)).valueOrNull;
    if (resolved != null) return resolved;
    return switch (spec.kind) {
      DrillDownKind.subtype => AnalyticsLabels.subtype(strings, spec.value),
      DrillDownKind.recurring => AnalyticsLabels.recurringSide(
        strings,
        spec.value,
      ),
      // Still loading, or the record is gone. The generic title is honest for one frame and for a
      // payee that was deleted since the chart was drawn.
      _ => strings.analyticsDrillTitle,
    };
  }
}

/// The one filter narrowing this list, and the way out of it.
class _ActiveFilter extends ConsumerWidget {
  const _ActiveFilter({required this.spec});

  final DrillDownSpec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final preset = ref.watch(analyticsRangeProvider);

    // **Removing the only filter means leaving the drill-down**, so the chip pops rather than clearing
    // something in place. A chip that removed itself and left an unfiltered ledger would silently
    // duplicate the expense list on a route that is not it.
    return FilterChipBar(
      filters: [
        ActiveFilter(
          label: AnalyticsLabels.range(strings, preset),
          onRemove: () =>
              context.canPop() ? context.pop() : context.go(Routes.insights),
        ),
      ],
    );
  }
}

/// The rows, grouped by day.
class _GroupedList extends ConsumerWidget {
  const _GroupedList({required this.spec});

  final DrillDownSpec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final days = ref.watch(drillDownDaysProvider(spec));
    final totals =
        ref.watch(drillDownTotalsProvider(spec)).valueOrNull ??
        const <String, int>{};

    return days.when(
      // A skeleton, not a spinner: the shape of what is arriving beats a spinner in a space that is
      // about to be a list (ARCH_5 §5.2).
      loading: () => AlayaListSkeleton(label: strings.analyticsDrillLoading),
      // **The repository's own message, not `errorBodyGeneric`** (Law U9). A figure that fails
      // identically for every cause is a failure nobody can diagnose.
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: error.toString(),
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(drillDownTransactionsProvider(spec)),
      ),
      data: (groups) {
        if (groups.isEmpty) {
          return EmptyState(
            title: strings.analyticsDrillEmptyTitle,
            // Names the likely cause — the window, not the filter — because the filter is the thing
            // the reader just chose and the window is the thing they may have forgotten.
            body: strings.analyticsDrillEmptyBody,
            icon: Icons.filter_alt_outlined,
          );
        }
        final clock = ref.watch(clockProvider);
        final background = Theme.of(context).scaffoldBackgroundColor;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _TotalsRow(totals: totals)),
            for (final group in groups)
              SliverMainAxisGroup(
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _DayHeader(
                      date: group.date,
                      clock: clock,
                      background: background,
                    ),
                  ),
                  // Virtualised (Law U13). A drill-down over "all time" on one subtype is not a short
                  // list, and mapping it into a `Column` would build every row.
                  SliverList.builder(
                    itemCount: group.transactions.length,
                    itemBuilder: (context, index) => _Row(
                      transaction: group.transactions[index],
                    ),
                  ),
                ],
              ),
            const SliverToBoxAdapter(
              child: SizedBox(height: AlayaSpacing.xxxl),
            ),
          ],
        );
      },
    );
  }
}

/// What the filtered list comes to, one line per currency.
class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.totals});

  final Map<String, int> totals;

  @override
  Widget build(BuildContext context) {
    if (totals.isEmpty) return const SizedBox.shrink();
    final strings = AlayaStrings.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
        AlayaSpacing.screenEdge,
        AlayaSpacing.sm,
      ),
      child: Wrap(
        spacing: AlayaSpacing.xs,
        runSpacing: AlayaSpacing.xxs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            strings.analyticsDrillTotal,
            style: AlayaTypography.label.copyWith(
              color: context.semantic.muted,
            ),
          ),
          // Per currency, each with its own precision. This figure can legitimately differ from the
          // slice it came from: the slice excluded whatever could not be converted, and this one
          // excludes nothing (anomaly A15).
          for (final entry in totals.entries)
            AnalyticsCurrencyAmount(Money(entry.value, entry.key)),
        ],
      ),
    );
  }
}

/// One transaction, rendered by the ledger's own row so the two screens cannot drift apart.
class _Row extends ConsumerWidget {
  const _Row({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The expense feature's maps, watched rather than re-declared: a second `accountsByIdProvider`
    // would be a second stream over the same table (Law U19, ARCH_1 §6's 7A amendment).
    final accounts =
        ref.watch(accountsByIdProvider).valueOrNull ??
        const <String, Account>{};
    final payees =
        ref.watch(payeesByIdProvider).valueOrNull ?? const <String, Payee>{};
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final from = transaction.fromAccountId;
    final to = transaction.toAccountId;
    final payeeId = transaction.payeeId;

    return TransactionRow(
      transaction: transaction,
      decimalDigits: digits,
      payee: payeeId == null ? null : payees[payeeId],
      fromAccount: from == null ? null : accounts[from],
      toAccount: to == null ? null : accounts[to],
      onTap: () => context.push(Routes.transactionDetail(transaction.id)),
    );
  }
}

/// The sticky day header, identical to the expense ledger's.
class _DayHeader extends SliverPersistentHeaderDelegate {
  const _DayHeader({
    required this.date,
    required this.clock,
    required this.background,
  });

  final DateKey date;
  final Clock clock;
  final Color background;

  // The tap-target floor rather than a hand-picked figure: it is the one height token that stays
  // legible when the text scale doubles.
  @override
  double get minExtent => AlayaSpacing.minTapTarget;

  @override
  double get maxExtent => AlayaSpacing.minTapTarget;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(
    color: background,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.screenEdge,
        vertical: AlayaSpacing.xs,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DateText.relative(
          date,
          clock: clock,
          textStyle: AlayaTypography.sectionHeader,
        ),
      ),
    ),
  );

  @override
  bool shouldRebuild(_DayHeader oldDelegate) =>
      oldDelegate.date != date || oldDelegate.background != background;
}
```

### `lib/features/analytics/presentation/widgets/analytics_amount.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';

/// The largest amount in a breakdown, which every bar's length is measured against.
///
/// Share of the *largest* rather than of the total, because a breakdown whose bars are shares of a
/// total is nearly all whitespace the moment there are eight slices — and the figures beside them
/// already say what the totals are.
int analyticsPeak(Iterable<Money> amounts) {
  var peak = 0;
  for (final amount in amounts) {
    if (amount.minor > peak) peak = amount.minor;
  }
  return peak;
}

/// [amount] as a fraction of [peak], for a bar's length.
double analyticsShare(Money amount, int peak) =>
    peak == 0 ? 0 : amount.minor / peak;

/// A breakdown row's figure, rendered once for every card that has one.
///
/// `AmountSize.small` because this screen has exactly one headline (ARCH_5 §3 archetype F), and
/// `showSign: false` because a column that is already a breakdown of spending does not need a minus in
/// front of every row.
Widget analyticsAmount(Money amount, int decimalDigits) => AmountText(
  amount,
  size: AmountSize.small,
  showSign: false,
  decimalDigits: decimalDigits,
);

/// An amount that resolves its **own** currency's precision.
///
/// **For the figures on this screen that are not in the home currency**: an inventory valuation, a
/// waste cost and a service history are all per-currency, because a batch's cost currency is per row
/// and summing them would add rupees to yen (anomaly A34). Passing the home currency's precision to a
/// yen figure prints `¥1,200.00` for `¥1,200`.
///
/// A widget rather than a lookup at the call site, because the precision arrives asynchronously and a
/// card rendering four currencies would otherwise need four watches interleaved with its layout.
class AnalyticsCurrencyAmount extends ConsumerWidget {
  /// Renders [amount] with its own currency's precision.
  const AnalyticsCurrencyAmount(
    this.amount, {
    this.size = AmountSize.small,
    super.key,
  });

  /// The amount, in whatever currency it was recorded in.
  final Money amount;

  /// How large to render it.
  final AmountSize size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Two while the precision loads is the right guess for four of the app's five seeded currencies,
    // and it is corrected on the next frame rather than showing a placeholder where a figure goes.
    final digits =
        ref
            .watch(analyticsDigitsForCurrencyProvider(amount.currencyCode))
            .valueOrNull ??
        2;
    return AmountText(
      amount,
      size: size,
      showSign: false,
      decimalDigits: digits,
    );
  }
}
```

### `lib/features/analytics/presentation/widgets/analytics_bar_chart.dart`

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// One bucket on an [AnalyticsBarChart].
class AnalyticsBucket {
  /// Creates a bucket.
  const AnalyticsBucket({
    required this.bucket,
    required this.value,
    required this.label,
  });

  /// Its position — 1-7 for a weekday, 1-31 for a day of month (ARCH_3 §5.1 query 21).
  final int bucket;

  /// The figure, in **minor units** (Law L1).
  final int value;

  /// The tick label, already localised.
  final String label;
}

/// A bucketed comparison, and the second of the two surfaces `fl_chart` is used for.
///
/// **The same containment as `AnalyticsLineChart`**: unverified package API confined to one file,
/// every colour and gap from Alaya's tokens, no Y-axis numbers (Law U7), touch off (ARCH_5 §6).
///
/// A bar chart rather than a `SliceBarList` because the buckets are a **fixed ordered set** — seven
/// weekdays, thirty-one days — and their order carries the information. Ranking them largest-first
/// would destroy the only thing the reader is looking for, which is the shape of the week.
class AnalyticsBarChart extends StatelessWidget {
  /// Creates a chart of [buckets], in bucket order.
  const AnalyticsBarChart({
    required this.buckets,
    this.labelEvery = 1,
    super.key,
  });

  /// The buckets, ascending. Empty renders nothing — the caller's `ChartCard` owns the empty state.
  final List<AnalyticsBucket> buckets;

  /// Label every nth bucket. Thirty-one day labels do not fit on a phone; seven weekdays do.
  final int labelEvery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    if (buckets.isEmpty) return const SizedBox.shrink();

    var maxValue = 0;
    for (final bucket in buckets) {
      if (bucket.value > maxValue) maxValue = bucket.value;
    }
    // A window where nothing was spent still draws its axis rather than collapsing, so the reader can
    // see that the buckets exist and are all zero.
    final top = maxValue == 0 ? 1.0 : maxValue.toDouble();

    return BarChart(
      BarChartData(
        maxY: top,
        minY: 0,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: const BarTouchData(enabled: false),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: MediaQuery.textScalerOf(
                context,
              ).scale(AlayaSpacing.lg),
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                final match = buckets.where((b) => b.bucket == index);
                if (match.isEmpty) return const SizedBox.shrink();
                if (labelEvery > 1 && index % labelEvery != 0)
                  return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: AlayaSpacing.xxs),
                  child: Text(
                    match.first.label,
                    style: AlayaTypography.overline.copyWith(
                      color: semantic.muted,
                    ),
                    maxLines: 1,
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (final bucket in buckets)
            BarChartGroupData(
              x: bucket.bucket,
              barRods: [
                BarChartRodData(
                  // The same L1 boundary as the line chart: an int figure becomes a double only to
                  // become a coordinate.
                  toY: bucket.value.toDouble(),
                  color: theme.colorScheme.primary,
                  width: AlayaSpacing.sm,
                  borderRadius: AlayaRadii.borderXs,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
```

### `lib/features/analytics/presentation/widgets/analytics_donut_chart.dart`

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_line_chart.dart';

/// One wedge of an [AnalyticsDonutChart], and one row of the list beneath it.
///
/// **The same object feeds the ring and the rows**, which is the point: build them from two sources and
/// they drift, so the fifth-largest wedge ends up a different colour from the fifth row.
class AnalyticsSlice {
  /// Creates a slice.
  const AnalyticsSlice({
    required this.label,
    required this.value,
    required this.color,
    this.key,
  });

  /// What it is, already localised.
  final String label;

  /// Its magnitude — minor units or base-milli. Only the ratio between slices is used.
  final int value;

  /// Its colour in both the ring and the row's swatch.
  final Color color;

  /// The drill-down key, or null for a slice that is not a filterable axis.
  final String? key;
}

/// The palette a donut's wedges take, largest first.
///
/// **A single-hue ramp, not a set of categorical colours.** Alaya's palette is data — five presets the
/// user chooses between (ARCH_5 §2.1) — so a hand-picked categorical set would clash under at least one
/// of them, and `warning`/`danger`/`success` are reserved for state and never for emphasis (§2.4).
/// Stepping the alpha on `primary` cannot clash with anything, and it reads in the right order: the
/// biggest share is the darkest.
///
/// Identity comes from the row beneath, whose swatch is this same colour. The ring carries proportion
/// only, which is the one thing a list genuinely cannot show.
List<Color> analyticsSliceColors(BuildContext context, int count) {
  final base = Theme.of(context).colorScheme.primary;
  const steps = [1.0, 0.78, 0.60, 0.45, 0.33, 0.24, 0.17];
  return [
    for (var i = 0; i < count; i++)
      base.withValues(alpha: steps[i < steps.length ? i : steps.length - 1]),
  ];
}

/// Builds the slices for a donut and its list, grouping the tail into one remainder wedge.
///
/// **Grouped because a ring of twelve slivers is not readable.** Past six wedges the arcs are thinner
/// than the gaps between them and the ordering stops being legible, so the tail becomes one wedge that
/// says what it is. [remainder] lets a caller supply a known total — the concentration card knows what
/// the top three leave behind — instead of it being derived from the slices given.
///
/// Zero and negative magnitudes are dropped: `PieChart` divides by the total and a zero wedge draws a
/// seam with no area, which reads as a rendering fault rather than as nothing.
List<AnalyticsSlice> analyticsSlices(
  BuildContext context,
  List<({String label, int value, String? key})> input, {
  required String otherLabel,
  int maxSlices = 6,
  int remainder = 0,
}) {
  final positive = [
    for (final row in input)
      if (row.value > 0) row,
  ];
  final head = positive.take(maxSlices).toList();
  final tail =
      positive.skip(maxSlices).fold<int>(0, (sum, row) => sum + row.value) +
      remainder;
  final colors = analyticsSliceColors(
    context,
    head.length + (tail > 0 ? 1 : 0),
  );

  return [
    for (var i = 0; i < head.length; i++)
      AnalyticsSlice(
        label: head[i].label,
        value: head[i].value,
        color: colors[i],
        key: head[i].key,
      ),
    // No key: "everything else" is not an axis anything can be filtered by, so the row it produces is
    // deliberately not tappable (ARCH_5 §10's objection to a control that looks live and is not).
    if (tail > 0)
      AnalyticsSlice(
        label: otherLabel,
        value: tail,
        color: colors[head.length],
      ),
  ];
}

/// A ring showing how a total divides, with a figure in the middle.
///
/// **Used only where the data is a genuine partition of one whole.** Spend by kind, the fixed-against-
/// chosen split and the concentration of spending all are. Tags are not — one purchase can carry two, so
/// the slices sum past the total and a ring would assert a whole that does not exist. Ranked lists
/// (payees, items) are not either: the top ten is not everything. Those stay as bars.
///
/// **The ring never carries a number.** Wedge titles are off: a `Money` in a 40dp arc is the clipping U7
/// forbids, and a percentage there duplicates what the rows already say. Touch is off for the same reason
/// as the other charts — a tooltip is a timed surface, and ARCH_5 §6 requires nothing live only there.
///
/// **Excluded from semantics.** The list beneath is the accessible rendering of the same slices, so
/// describing both makes a screen reader read the card twice.
class AnalyticsDonutChart extends StatelessWidget {
  /// Creates a ring of [slices].
  const AnalyticsDonutChart({
    required this.slices,
    this.centreTop,
    this.centreBottom,
    super.key,
  });

  /// The wedges, largest first, from [analyticsSlices].
  final List<AnalyticsSlice> slices;

  /// The emphasised line in the hole — usually a percentage.
  final String? centreTop;

  /// The quiet line under it — usually what that percentage is of.
  final String? centreBottom;

  /// The unscaled height of the ring's box, and so its diameter on any phone narrower than this.
  ///
  /// **Four times the spacing scale's largest step, where the line and bar charts use two.** They are
  /// wide and shallow by nature — a trend reads left to right — so `AnalyticsPlotBox.defaultHeight`
  /// suits them. A ring is square: its diameter is the box's *shorter* side, so at 96 the height was
  /// capping a circle whose width had 256 to spare on the narrowest supported phone, and it drew at
  /// barely more than a third of the room available. At 192 the width becomes the binding constraint
  /// instead, which is the right way round — the ring can never be wider than its card.
  static const double plotHeight = AlayaSpacing.xxxl * 4;

  /// How much of the box the hole takes. Two fifths leaves an arc thick enough to compare by eye — 58
  /// logical pixels at [plotHeight] — and a hole wide enough for a percentage at a doubled text scale.
  static const double _holeFraction = 0.4;

  /// The gap between wedges, on the spacing scale (Law U6).
  static const double _gap = AlayaSpacing.xxs / 2;

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) return const SizedBox.shrink();
    final semantic = context.semantic;

    return ExcludeSemantics(
      child: AnalyticsPlotBox(
        height: plotHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Sized from the box's own shorter side rather than from a constant, so the ring stays a
            // ring at any text scale: `AnalyticsPlotBox` grows the height and a fixed radius would
            // then be an ellipse cropped by the width.
            final extent = constraints.biggest.shortestSide;
            final hole = extent * _holeFraction / 2;
            final ring = extent / 2 - hole;

            return Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: _gap,
                    centerSpaceRadius: hole,
                    // From the top, clockwise: the largest wedge starts where a reader looks first.
                    startDegreeOffset: -90,
                    // Not `const`: `PieTouchData` has no const constructor, unlike `LineTouchData` and
                    // `BarTouchData`. Three sibling APIs, two of them const — exactly the inconsistency
                    // ARCH_4 R22 means by "verified by compiling, not by reading about it".
                    pieTouchData: PieTouchData(enabled: false),
                    sections: [
                      for (final slice in slices)
                        PieChartSectionData(
                          // `toDouble()` on a magnitude that is an int everywhere else — the same
                          // boundary the line chart's `FlSpot` crosses, and legal for the same reason:
                          // an arc sweep is geometry, not money (Law L1).
                          value: slice.value.toDouble(),
                          color: slice.color,
                          radius: ring,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
                if (centreTop != null || centreBottom != null)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (centreTop != null)
                        Text(centreTop!, style: AlayaTypography.amountSmall),
                      if (centreBottom != null)
                        Text(
                          centreBottom!,
                          style: AlayaTypography.overline.copyWith(
                            color: semantic.muted,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
```

### `lib/features/analytics/presentation/widgets/analytics_header.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Total spend in the window — the one `displayAmount` on this screen (ARCH_5 §3 archetype F).
///
/// **One headline figure, because two headline numbers is no headline number.** Every other figure on
/// the analytics screen is `AmountSize.small` or smaller, exactly as the dashboard's hierarchy works.
///
/// **The comparison is against a window of equal length, not against a calendar month.** "Last 30
/// days" compared with the previous calendar month would be comparing 30 days against 28, 30 or 31,
/// and the resulting percentage would be an artefact of the calendar rather than a fact about
/// spending (`DateRangeService.precedingWindowOf` exists for this).
class AnalyticsHeader extends ConsumerWidget {
  /// Creates the header.
  const AnalyticsHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final async = ref.watch(analyticsHeadlineProvider);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final preset = ref.watch(analyticsRangeProvider);
    final unconverted =
        ref.watch(analyticsUnconvertedProvider).valueOrNull ?? 0;

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.analyticsTotalSpent,
            style: AlayaTypography.label.copyWith(color: semantic.muted),
          ),
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            AnalyticsLabels.range(strings, preset),
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          const SizedBox(height: AlayaSpacing.xs),
          async.when(
            loading: () => Text(
              strings.chartLoading,
              style: AlayaTypography.body.copyWith(color: semantic.muted),
            ),
            error: (error, stack) => ErrorState(
              title: strings.errorTitleGeneric,
              body: error.toString(),
              retryLabel: strings.actionRetry,
              onRetry: () => ref.invalidate(analyticsHeadlineProvider),
            ),
            data: (concentration) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AmountText(
                  concentration.total,
                  size: AmountSize.display,
                  // The card is headed "Spent", so a minus in front of the figure restates the
                  // heading rather than adding to it.
                  showSign: false,
                  decimalDigits: digits,
                ),
                const _Comparison(),
                if (unconverted > 0 ||
                    concentration.quality.unconvertedCount > 0) ...[
                  const SizedBox(height: AlayaSpacing.sm),
                  Wrap(
                    spacing: AlayaSpacing.xs,
                    runSpacing: AlayaSpacing.xxs,
                    children: [
                      if (concentration.quality.unconvertedCount > 0)
                        StatusChip(
                          label: strings.chartUnconverted(
                            concentration.quality.unconvertedCount,
                          ),
                          tone: StatusTone.warning,
                        ),
                      // The app-wide count, distinct from this figure's own exclusions: a
                      // transaction outside the window can still be unconvertible, and Settings is
                      // where a reader fixes that. Said once here rather than on every card.
                      if (unconverted > 0)
                        StatusChip(
                          label: strings.analyticsUnconvertedTotal(unconverted),
                          tone: StatusTone.neutral,
                        ),
                    ],
                  ),
                  const SizedBox(height: AlayaSpacing.xs),
                  Text(
                    strings.fundsWhyExcluded,
                    style: AlayaTypography.caption.copyWith(
                      color: semantic.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How this window compares with the one before it, of the same length.
class _Comparison extends ConsumerWidget {
  const _Comparison();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final now = ref.watch(analyticsHeadlineProvider).valueOrNull;
    final before = ref.watch(analyticsPreviousHeadlineProvider).valueOrNull;

    // Renders nothing until both windows have resolved, and nothing when the earlier one held zero.
    // A percentage against zero is infinite, and "up ∞%" is not a fact about spending.
    if (now == null || before == null || before.total.minor == 0)
      return const SizedBox.shrink();

    final delta = (now.total.minor - before.total.minor) / before.total.minor;
    final formatted = AnalyticsLabels.percent(context, delta.abs());

    // **Colour is not the only signal** (Law U17): the word carries the direction and the hue only
    // reinforces it. Spending more is `warning` rather than `danger` — it is worth noticing, not
    // wrong.
    final rose = delta > 0;
    return Padding(
      padding: const EdgeInsets.only(top: AlayaSpacing.xs),
      child: Text(
        rose
            ? strings.analyticsComparisonUp(formatted)
            : strings.analyticsComparisonDown(formatted),
        style: AlayaTypography.caption.copyWith(
          color: rose ? semantic.warning : semantic.success,
        ),
      ),
    );
  }
}
```

### `lib/features/analytics/presentation/widgets/analytics_labels.dart`

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';

/// Turns the keys `AnalyticsPort` grouped by into labels a reader can understand.
///
/// **The adapter groups by enum name, so `slice.label` for a subtype is `grocery`.** Rendering it
/// would put an untranslated identifier on screen (Law U5). Every key whose label is *not* data goes
/// through here; keys whose labels are data — a payee, a tag, an item — render their label directly.
abstract final class AnalyticsLabels {
  /// The localised name for a `TransactionSubtype` key.
  ///
  /// **Delegates to `TransactionRow.subtypeLabel`, which is public for exactly this reason.** A tenth
  /// switch over nine subtypes is a tenth thing to update when one is renamed, and ARCH_5 §10's
  /// objection to re-deriving a rule at a call site does not stop at colours.
  ///
  /// Falls back to the raw key rather than throwing: an unrecognised name means the database holds a
  /// value this build does not know, which is what Law L13's fallback-safe storage exists to survive.
  /// A cosmetic label is not worth a crash on the analytics screen.
  static String subtype(AlayaStrings strings, String key) {
    for (final value in TransactionSubtype.values) {
      if (value.name == key) return TransactionRow.subtypeLabel(strings, value);
    }
    return key;
  }

  /// The localised name for query 18's two sides.
  static String recurringSide(AlayaStrings strings, String key) =>
      key == 'recurring'
      ? strings.analyticsRecurring
      : strings.analyticsDiscretionary;

  /// The localised name of a reporting window.
  ///
  /// Exhaustive over `DateRangePreset` on purpose: adding a preset to `AnalyticsRange.presets`
  /// without labelling it should be a compile error here, not a chip rendering its own enum name.
  /// Every key already exists in the ARB from earlier phases — this phase adds none.
  static String range(AlayaStrings strings, DateRangePreset preset) =>
      switch (preset) {
        DateRangePreset.today => strings.rangeToday,
        DateRangePreset.last7Days => strings.rangeLast7Days,
        DateRangePreset.last30Days => strings.rangeLast30Days,
        DateRangePreset.thisMonth => strings.rangeThisMonth,
        DateRangePreset.lastMonth => strings.rangeLastMonth,
        DateRangePreset.thisYear => strings.rangeThisYear,
        DateRangePreset.allTime => strings.rangeAllTime,
        DateRangePreset.custom => strings.rangeCustom,
      };

  /// The short axis label for a heatmap bucket.
  ///
  /// **Weekdays come from `MaterialLocalizations.narrowWeekdays`, not from the ARB**, which is how
  /// 7A's month grid labels its own weekday row — locale-correct in every locale Flutter ships
  /// without seven strings a translator has to be asked for.
  ///
  /// That list is Sunday-first while ARCH_3 §5.1's buckets are 1-7 Monday-first, so `bucket % 7` maps
  /// between them: Monday's 1 lands on index 1 and Sunday's 7 wraps to index 0. It is the same
  /// expression 7A uses for a `DateTime.weekday`, for the same reason.
  ///
  /// A day-of-month bucket is its own number and needs no translation.
  static String bucket(
    BuildContext context,
    int bucket, {
    required bool byWeekday,
  }) {
    if (!byWeekday) return '$bucket';
    return MaterialLocalizations.of(context).narrowWeekdays[bucket %
        DateTime.daysPerWeek];
  }

  /// The localised name of a `UnitCategory`.
  ///
  /// **A third copy of this switch, and that is worth recording rather than hiding.** 6B already holds
  /// two private ones — `_categoryLabel` in its line-item editor and again in its item editor — so the
  /// mapping had drifted into duplication before this phase arrived. Reaching either would mean making
  /// a private helper public in a file this phase has no other reason to carry.
  ///
  /// It cannot live on `UnitCategory` itself: that is in `core/`, and `AlayaStrings` is in `app/`
  /// (Law L12). The right home is one helper in `shared/`, which ARCH_5 §8 does not permit this phase
  /// to add without a record — so it is filed as a finding for Phase 9's sweep instead of taken here.
  static String unitCategory(AlayaStrings strings, UnitCategory category) =>
      switch (category) {
        UnitCategory.weight => strings.unitCategoryWeight,
        UnitCategory.volume => strings.unitCategoryVolume,
        UnitCategory.count => strings.unitCategoryCount,
      };

  /// [share] as a whole-number percentage in the active locale.
  ///
  /// One definition, because five surfaces state a share and five `NumberFormat` calls is five places
  /// for the decimal count to drift — the same objection ARCH_5 §10 raises to re-deriving red/green at
  /// a call site.
  ///
  /// Whole numbers: "34%" is the insight, and "33.7%" implies a precision a ratio of two rounded
  /// totals does not have.
  static String percent(BuildContext context, double share) =>
      NumberFormat.decimalPercentPattern(
        locale: Localizations.localeOf(context).toLanguageTag(),
        decimalDigits: 0,
      ).format(share);
}
```

### `lib/features/analytics/presentation/widgets/analytics_line_chart.dart`

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// A chart sized to the standard plot height, scaled from the text scaler.
///
/// **This replaced `ChartCard.chartHeight`, which was wrong in a way worth recording.** That parameter
/// wrapped the *whole* builder output in a fixed box, so a card whose builder returned chrome above its
/// chart — a title, a legend, a segmented control — had that chrome squeezed into the height meant for
/// the plot, and `Expanded` was then mandatory because only a bounded box makes it legal. Four of the
/// six chart cards were built that way and `InflationCard` overflowed by 44px at scale 1.
///
/// Sizing only the plot is the fix: the surrounding `Column` grows naturally inside the screen's
/// `SliverList`, and the card can be as tall as its own text needs.
///
/// **Measured from the text scaler and clamped** (Law U26). A plot is a graphic and does not grow with
/// type, but its axis labels do, so the box has to give them room; unclamped, a tripled scale produces a
/// card nobody can scroll past.
class AnalyticsPlotBox extends StatelessWidget {
  /// Sizes [child] to the scaled plot height.
  const AnalyticsPlotBox({
    required this.child,
    this.height = defaultHeight,
    super.key,
  });

  /// The plot.
  final Widget child;

  /// The unscaled height.
  final double height;

  /// One height for every chart on the screen, so eight cards cannot each pick their own and leave the
  /// scroll rhythm uneven.
  static const double defaultHeight = AlayaSpacing.xxxl * 2;

  /// The most a plot grows by under text scale.
  static const double maxScale = 2;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, maxScale);
    return SizedBox(height: height * scale, child: child);
  }
}

/// Which semantic role a series carries.
enum AnalyticsSeriesTone {
  /// Money arriving.
  income,

  /// Money leaving.
  expense,

  /// Neither — a balance, a unit price, a count.
  neutral,
}

/// One plotted observation.
class AnalyticsPoint {
  /// Creates a point at [x] worth [value] minor units.
  const AnalyticsPoint({required this.x, required this.value, this.axisLabel});

  /// The horizontal position — a month index, a day offset, a purchase ordinal.
  final double x;

  /// The figure, in **minor units** (Law L1). Never a decimal.
  final int value;

  /// The tick label at [x], already localised. Null on ticks that should stay unlabelled.
  final String? axisLabel;
}

/// One line on the chart.
class AnalyticsSeries {
  /// Creates a series.
  const AnalyticsSeries({
    required this.points,
    required this.tone,
    this.filled = false,
  });

  /// Its observations, ascending by [AnalyticsPoint.x].
  final List<AnalyticsPoint> points;

  /// Which semantic colour it takes.
  final AnalyticsSeriesTone tone;

  /// Whether to shade the area beneath it. One series may; two would obscure each other.
  final bool filled;
}

/// A trend over time, and one of the two surfaces `fl_chart` is used for.
///
/// **`fl_chart` is confined to this file and `analytics_bar_chart.dart`.** Its API could not be
/// verified against the installed package in the session that wrote this — the same position 7A was
/// in with `table_calendar` — so ARCH_4 R22 says to contain it rather than trust a changelog. Every
/// colour, gap and text style comes from Alaya's own tokens through the parameters below; the package
/// supplies path geometry and nothing a token would otherwise own. If its API differs, two files
/// change rather than the phase.
///
/// **There are no Y-axis number labels, and that is Law U7 rather than a style choice.** An axis is
/// exactly where a `Money` gets clipped, `AmountText` clips rather than ellipsises, and a clipped
/// figure is a wrong figure. The grid lines carry the shape; the card's headline carries the number;
/// the drill-down carries the rest.
///
/// **Touch is off.** A tooltip is a timed surface, and ARCH_5 §6 requires that nothing be available
/// *only* there.
class AnalyticsLineChart extends StatelessWidget {
  /// Creates a chart of [series].
  const AnalyticsLineChart({
    required this.series,
    this.gridLineCount = 4,
    super.key,
  });

  /// The lines to draw. Empty renders nothing — the caller's `ChartCard` owns the empty state.
  final List<AnalyticsSeries> series;

  /// How many horizontal grid lines to draw behind the lines.
  final int gridLineCount;

  /// The plotted line's thickness.
  static const double _barWidth = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    if (series.isEmpty) return const SizedBox.shrink();

    final all = [for (final s in series) ...s.points];
    if (all.isEmpty) return const SizedBox.shrink();

    var minValue = all.first.value;
    var maxValue = all.first.value;
    for (final point in all) {
      if (point.value < minValue) minValue = point.value;
      if (point.value > maxValue) maxValue = point.value;
    }
    // A flat line needs a band or the plot collapses to zero height and fl_chart divides by it.
    if (minValue == maxValue) {
      maxValue += 1;
      minValue -= 1;
    }
    // Zero is included whenever the data straddles or approaches it, so a bar of spending is not
    // drawn from an arbitrary floor that exaggerates every difference.
    if (minValue > 0) minValue = 0;

    final labels = <double, String>{
      for (final point in all)
        if (point.axisLabel != null) point.x: point.axisLabel!,
    };

    return LineChart(
      LineChartData(
        minY: minValue.toDouble(),
        maxY: maxValue.toDouble(),
        // Touch disabled: see the class doc. A tooltip would be the only place a figure lived.
        lineTouchData: const LineTouchData(enabled: false),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxValue - minValue) / gridLineCount,
          getDrawingHorizontalLine: (value) => FlLine(
            color: theme.colorScheme.outlineVariant,
            // A literal `1`, and the one dimension in this phase that has no token. ARCH_5 §2.2
            // defines a dividing line as 1px at divider weight and `AlayaSpacing` starts at 4, so
            // there is nothing to reach for — 6F's `range_row.dart` sets the same literal for its
            // rule. `outlineVariant` is Material 3's divider role, which keeps the weight consistent
            // across every palette preset.
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          // No numbers on the left, per Law U7 — see the class doc.
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              // Measured from the text scaler rather than fixed, so a doubled scale gets the room it
              // needs instead of clipping the tick (Law U26).
              reservedSize: MediaQuery.textScalerOf(
                context,
              ).scale(AlayaSpacing.lg),
              getTitlesWidget: (value, meta) {
                final label = labels[value];
                if (label == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: AlayaSpacing.xxs),
                  child: Text(
                    label,
                    style: AlayaTypography.overline.copyWith(
                      color: semantic.muted,
                    ),
                    maxLines: 1,
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          for (final s in series)
            LineChartBarData(
              // **`toDouble()` here is the one legitimate place a money figure becomes a double.**
              // Law L1 forbids a `double` storing money or crossing a repository boundary; a plot
              // coordinate is neither. The int is what was read, summed and cached.
              spots: [
                for (final p in s.points) FlSpot(p.x, p.value.toDouble()),
              ],
              isCurved: false,
              barWidth: _barWidth,
              color: _colorFor(s.tone, semantic),
              dotData: FlDotData(show: s.points.length <= _dotThreshold),
              belowBarData: BarAreaData(
                show: s.filled,
                color: _colorFor(s.tone, semantic).withValues(alpha: 0.12),
              ),
            ),
        ],
      ),
    );
  }

  /// Above this many points the dots merge into the line and are dropped.
  static const int _dotThreshold = 14;

  Color _colorFor(AnalyticsSeriesTone tone, AlayaSemanticColors semantic) =>
      switch (tone) {
        AnalyticsSeriesTone.income => semantic.income,
        AnalyticsSeriesTone.expense => semantic.expense,
        AnalyticsSeriesTone.neutral => semantic.transfer,
      };
}
```

### `lib/features/analytics/presentation/widgets/analytics_range_row.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/state/analytics_range.dart';

/// The reporting window, as chips.
///
/// **Every range is labelled with what it means** (anomaly A33). "Last month" is ambiguous between
/// the previous calendar month and the preceding thirty days, and no figure on the screen can
/// disambiguate itself — so the chip states the window and `DateRangeService` resolves exactly that.
///
/// Chips rather than a dropdown: six options, one tap each, and the current choice is visible without
/// opening anything (ARCH_5 §3 archetype A's reasoning, which holds wherever a choice is small and
/// frequent).
class AnalyticsRangeRow extends ConsumerWidget {
  /// Creates the row.
  const AnalyticsRangeRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final selected = ref.watch(analyticsRangeProvider);

    // A `Wrap`, not a horizontal scroller: a scroller needs a fixed height and a fixed height
    // overflows the moment the text scale is raised (Law U15). Six chips wrap to two rows at 2x and
    // stay reachable.
    return Semantics(
      label: strings.analyticsRangeLabel,
      child: Wrap(
        spacing: AlayaSpacing.xs,
        runSpacing: AlayaSpacing.xs,
        children: [
          for (final preset in AnalyticsRange.presets)
            ChoiceChip(
              label: Text(
                AnalyticsLabels.range(strings, preset),
                style: AlayaTypography.button,
              ),
              selected: preset == selected,
              onSelected: (_) =>
                  ref.read(analyticsRangeProvider.notifier).show(preset),
            ),
        ],
      ),
    );
  }
}
```

### `lib/features/analytics/presentation/widgets/cache_row.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/date_text.dart';

/// The clear-cache action — the whole of `analytics_cache`'s user-facing surface (ARCH_5 §7.1, §7.3).
///
/// **It is here rather than in Settings, and the reason is structural.** ARCH_5 §7.1 assigns the control
/// to Settings, which is a `PlaceholderScreen` until Phase 8A. It could not go in the app bar either:
/// `Routes.insights` is a shell destination, so the bar belongs to `_ShellScaffold` and an action added
/// there would appear on all nine destinations. So it sits last on the screen, quiet, in the manner of
/// archetype E's destructive actions. **Phase 8A's Settings entry must call
/// `analyticsCacheControllerProvider` rather than the service**, or one action gets two write paths
/// (Law U22).
///
/// **No `ConfirmSheet`.** Clearing a cache costs the reader a recomputation and nothing else, and
/// ARCH_5 §5.5 reserves confirmation for consequences — a confirm dialog on a harmless action trains
/// people to tap through the ones that matter.
class CacheRow extends ConsumerWidget {
  /// Creates the row.
  const CacheRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final state = ref.watch(analyticsCacheControllerProvider);
    final clearing = state.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The button is disabled while clearing rather than hidden, so the row does not move under the
        // reader's thumb (ARCH_5 §5.2: an in-place action disables, it does not throw up a barrier).
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: clearing ? null : () => _clear(context, ref),
            icon: const Icon(Icons.refresh, size: AlayaIconSize.md),
            label: Text(
              clearing
                  ? strings.analyticsCacheClearing
                  : strings.analyticsCacheClear,
              style: AlayaTypography.button,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.sm),
          child: Text(
            strings.analyticsCacheExplain,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ),
        // The repository's own message, in place and not only in a snack (Law U9): a snack is a timed
        // surface, and a failure the reader looked away from is a failure they never saw.
        state.when(
          data: (clearedOn) => clearedOn == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(
                    left: AlayaSpacing.sm,
                    top: AlayaSpacing.xxs,
                  ),
                  child: Row(
                    children: [
                      Text(
                        strings.analyticsCacheCleared,
                        style: AlayaTypography.caption.copyWith(
                          color: semantic.success,
                        ),
                      ),
                      const SizedBox(width: AlayaSpacing.xxs),
                      DateText(
                        clearedOn,
                        style: DateTextStyle.medium,
                        muted: true,
                      ),
                    ],
                  ),
                ),
          loading: () => const SizedBox.shrink(),
          error: (error, stack) => Padding(
            padding: const EdgeInsets.only(
              left: AlayaSpacing.sm,
              top: AlayaSpacing.xxs,
            ),
            child: Text(
              error.toString(),
              style: AlayaTypography.caption.copyWith(color: semantic.danger),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final ok = await ref
        .read(analyticsCacheControllerProvider.notifier)
        .clear();
    if (!context.mounted) return;
    // **Every write reports its outcome** (Law U9). No Undo: there is nothing to restore, and the
    // figures are already recomputing.
    if (ok) {
      showResultSnack(context, message: strings.analyticsCacheClearedSnack);
    } else {
      showFailureSnack(context, message: strings.analyticsCacheFailed);
    }
  }
}
```

### `lib/features/analytics/presentation/widgets/commitment_cards.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
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
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Query 17 — what is owed every month before anything discretionary happens.
///
/// Every interval is normalised to a month so a weekly bill and an annual one are comparable, and the
/// integer division truncates — so the figure is slightly conservative rather than optimistic, which is
/// the right direction for a number somebody budgets against.
class MonthlyCommitmentCard extends ConsumerWidget {
  /// Creates the card.
  const MonthlyCommitmentCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final async = ref.watch(monthlyCommitmentProvider);

    return ChartCard<MonthlyCommitment>(
      title: strings.analyticsCommitment,
      // Outflow only. Netting salary against rent would report a household with a surplus as having no
      // fixed costs at all, which is the opposite of what the figure is for.
      subtitle: strings.analyticsCommitmentNote,
      value: async,
      isEmpty: (data) => data.templateCount == 0,
      emptyMessage: strings.analyticsNoCommitments,
      onRetry: () => ref.invalidate(monthlyCommitmentProvider),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AmountText(
            data.total,
            size: AmountSize.large,
            showSign: false,
            decimalDigits: digits,
          ),
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            strings.analyticsCommitmentCount(data.templateCount),
            style: AlayaTypography.caption.copyWith(
              color: context.semantic.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Query 18 — the recurring against discretionary split.
///
/// Both sides tap through to the ledger, because "where did the discretionary half go" is the obvious
/// next question and the answer is a filtered list rather than another chart.
class RecurringSplitCard extends ConsumerWidget {
  /// Creates the card.
  const RecurringSplitCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;
    final async = ref.watch(recurringSplitProvider);

    return ChartCard<RecurringSplit>(
      title: strings.analyticsRecurringSplit,
      value: async,
      isEmpty: (split) => split.recurring.isZero && split.discretionary.isZero,
      emptyMessage: strings.analyticsNothingSpent,
      onRetry: () => ref.invalidate(recurringSplitProvider),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, split) {
        // **Two wedges of one whole — the shape a ring is actually for.** Every withdrawal is on exactly
        // one side of this split, so the circle is the figure: how much of the month was decided before
        // it started.
        final slices = analyticsSlices(
          context,
          [
            (
              label: strings.analyticsRecurring,
              value: split.recurring.minor,
              key: 'recurring',
            ),
            (
              label: strings.analyticsDiscretionary,
              value: split.discretionary.minor,
              key: 'discretionary',
            ),
          ],
          otherLabel: strings.analyticsOtherSlices,
        );
        final amounts = {
          'recurring': split.recurring,
          'discretionary': split.discretionary,
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnalyticsDonutChart(
              slices: slices,
              centreTop: AnalyticsLabels.percent(context, split.recurringShare),
              centreBottom: strings.analyticsRecurring,
            ),
            const SizedBox(height: AlayaSpacing.sm),
            Text(
              strings.analyticsRecurringShare(
                AnalyticsLabels.percent(context, split.recurringShare),
              ),
              style: AlayaTypography.bodyEmphasis,
            ),
            const SizedBox(height: AlayaSpacing.sm),
            SliceBarList(
              showBars: false,
              slices: [
                for (final slice in slices)
                  SliceBar(
                    label: slice.label,
                    value: analyticsAmount(
                      amounts[slice.key] ?? split.recurring,
                      digits,
                    ),
                    // The real share, not a placeholder: the rows drop their bars while a ring is above
                    // them, but a `share` of zero would draw an empty bar the moment anyone turned them
                    // back on.
                    share: slice.key == 'recurring'
                        ? split.recurringShare
                        : 1 - split.recurringShare,
                    detail: AnalyticsLabels.percent(
                      context,
                      slice.key == 'recurring'
                          ? split.recurringShare
                          : 1 - split.recurringShare,
                    ),
                    swatch: slice.color,
                    onTap: slice.key == null
                        ? null
                        // The literals the adapter's SQL emits for the two sides, reached through the
                        // same constants the predicate compares against.
                        : () => context.push(
                            Routes.insightsDrillDown(
                              DrillDownKind.recurring.name,
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

/// Query 19 — what each asset has cost to keep, per currency.
///
/// **Disposed assets are included**, which is the point of `status = disposed` rather than a delete: the
/// ₹45,000 of servicing you put into a TV stays here after you sell it, and "lifetime" would be a
/// strange word for a figure that vanished on disposal.
class ServiceCostCard extends ConsumerWidget {
  /// Creates the card.
  const ServiceCostCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(serviceCostByAssetProvider);

    return ChartCard<List<AssetServiceCost>>(
      title: strings.analyticsServiceCost,
      value: async,
      isEmpty: (costs) => costs.isEmpty,
      emptyMessage: strings.analyticsNoServiceCost,
      onRetry: () => ref.invalidate(serviceCostByAssetProvider),
      builder: (context, costs) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final cost in costs.take(_maxRows))
            Padding(
              padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
              child: Wrap(
                spacing: AlayaSpacing.xs,
                runSpacing: AlayaSpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(cost.assetName, style: AlayaTypography.body),
                  Text(
                    strings.analyticsServiceCount(cost.serviceCount),
                    style: AlayaTypography.caption.copyWith(
                      color: context.semantic.muted,
                    ),
                  ),
                  // Per currency, unconverted: a service history spanning a move abroad holds two
                  // currencies and summing them would be wrong (anomaly A34).
                  for (final amount in cost.byCurrency.values)
                    AnalyticsCurrencyAmount(amount),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static const int _maxRows = 6;
}

/// Query 20 — the warranty coverage timeline.
class WarrantyCard extends ConsumerWidget {
  /// Creates the card.
  const WarrantyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(warrantyCoverageProvider);

    return ChartCard<List<WarrantyCoverage>>(
      title: strings.analyticsWarranty,
      value: async,
      isEmpty: (rows) => rows.isEmpty,
      emptyMessage: strings.analyticsNoWarranties,
      onRetry: () => ref.invalidate(warrantyCoverageProvider),
      builder: (context, rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows.take(_maxRows))
            KeyValueRow(
              label: row.assetName,
              // `KeyValueRow` renders nothing when the value is null, which is why the end date is
              // handed over as a widget rather than a formatted string: an asset with a start and no
              // end has no coverage window to state, and the row disappears rather than showing a dash.
              valueWidget: row.end == null
                  ? null
                  : Wrap(
                      spacing: AlayaSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DateText(
                          row.end!,
                          style: DateTextStyle.medium,
                          muted: true,
                        ),
                        StatusChip(
                          label: row.isCovered
                              ? strings.analyticsCovered
                              : strings.analyticsCoverageEnded,
                          // `warning` for a coverage window inside 30 days, matching ARCH_3 §6's own
                          // `warrantyEnd` threshold so this card and the calendar agree.
                          tone: !row.isCovered
                              ? StatusTone.neutral
                              : (row.daysLeft ?? _warrantyWarningDays + 1) <=
                                    _warrantyWarningDays
                              ? StatusTone.warning
                              : StatusTone.success,
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }

  static const int _maxRows = 6;

  /// ARCH_3 §6's `warrantyEnd` threshold: 30 days, where expiry and service warn at 7.
  static const int _warrantyWarningDays = 30;
}
```

### `lib/features/analytics/presentation/widgets/home_cards.dart`

```dart
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
```

### `lib/features/analytics/presentation/widgets/inflation_card.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_line_chart.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';
import 'package:alaya/shared/widgets/date_text.dart';

/// The personal-inflation card — queries 12 and 24.
///
/// **This is the differentiating surface** (ARCH_3 §5.1: *"your potatoes cost 34% more than in
/// January"*). It is the one figure on this screen that no mainstream expense app can produce, and it
/// falls out of `transaction_lines` for free: a line records what was bought, how much of it, and for
/// how much, so price per base unit is a division rather than a feature.
///
/// **Comparable across purchases because it is per *base* unit.** 2 kg and 500 g are the same
/// measurement once both are per gram, which is why the trend can put a sack and a handful on one
/// line.
///
/// The item is chosen rather than asked for: `personalInflationProvider` takes the largest absolute
/// change among the items the reader actually spends on.
class InflationCard extends ConsumerWidget {
  /// Creates the card.
  const InflationCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(personalInflationProvider);
    final digits = ref.watch(analyticsDigitsProvider).valueOrNull ?? 2;

    return ChartCard<UnitPriceTrend?>(
      title: strings.analyticsInflationTitle,
      subtitle: strings.analyticsInflationSubtitle,
      value: async,
      // Null *and* a trend with fewer than two points both read as empty: one observation is a price,
      // not a trend, and drawing a single dot and calling it inflation would be a claim the data does
      // not support.
      isEmpty: (trend) => trend == null || trend.points.length < 2,
      emptyMessage: strings.analyticsInflationEmpty,
      onRetry: () => ref.invalidate(personalInflationProvider),
      builder: (context, trend) => _Trend(trend: trend!, decimalDigits: digits),
    );
  }
}

class _Trend extends StatelessWidget {
  const _Trend({required this.trend, required this.decimalDigits});

  final UnitPriceTrend trend;
  final int decimalDigits;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final theme = Theme.of(context);
    final change = trend.percentChange;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          trend.itemName,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        if (change != null) ...[
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            _sentence(context, strings, change),
            style: AlayaTypography.bodyEmphasis.copyWith(
              // Paying more for the same thing is `warning`: worth noticing, not wrong. Colour is
              // never the only signal — the sentence says "more" or "less" (Law U17).
              color: change > 0 ? semantic.warning : semantic.success,
            ),
          ),
        ],
        const SizedBox(height: AlayaSpacing.xxs),
        // **The date goes through `DateText`, so the sentence above cannot contain it** (Law U7).
        // Interpolating a formatted date into an ARB string would bypass the one path from a `DateKey`
        // to pixels, and a `Wrap` lets the label and the date reflow rather than starving each other
        // at a raised text scale (Law U21).
        Wrap(
          spacing: AlayaSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              strings.analyticsInflationSince,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            DateText(
              trend.points.first.on,
              style: DateTextStyle.medium,
              muted: true,
            ),
            AmountText(
              trend.points.last.lineAmount,
              size: AmountSize.small,
              showSign: false,
              decimalDigits: decimalDigits,
            ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.sm),
        AnalyticsPlotBox(
          child: AnalyticsLineChart(
            series: [
              AnalyticsSeries(
                tone: AnalyticsSeriesTone.neutral,
                filled: true,
                points: _points(context, trend),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The observations, oldest first, as plot points.
  ///
  /// `x` is the purchase *ordinal* rather than the date, deliberately. Spacing the points by date
  /// would compress a cluster of weekly shops into an unreadable smear and stretch a six-month gap
  /// across the card; the question is "how has the price moved across my purchases", and each
  /// purchase is one step.
  ///
  /// `pricePerBaseUnit` is a `double` of minor units — a derived ratio, which is why
  /// `analytics_types.dart` refuses to make it a `Money`. It is rounded to whole minor units here
  /// because a pixel cannot express a fraction of a paisa, and only the first and last ticks are
  /// labelled so the axis stays legible at any purchase count.
  List<AnalyticsPoint> _points(BuildContext context, UnitPriceTrend trend) {
    final last = trend.points.length - 1;
    return [
      for (var i = 0; i <= last; i++)
        AnalyticsPoint(
          x: i.toDouble(),
          value: trend.points[i].pricePerBaseUnit.round(),
          axisLabel: i == 0 || i == last
              ? DateFormat.MMMd(
                  Localizations.localeOf(context).toLanguageTag(),
                ).format(trend.points[i].on.toUtcMidnight())
              : null,
        ),
    ];
  }

  String _sentence(BuildContext context, AlayaStrings strings, double change) {
    final formatted = AnalyticsLabels.percent(context, change.abs());
    return change > 0
        ? strings.analyticsInflationUp(formatted)
        : strings.analyticsInflationDown(formatted);
  }
}
```

### `lib/features/analytics/presentation/widgets/items_cards.dart`

```dart
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
```

### `lib/features/analytics/presentation/widgets/slice_bar_list.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// One row of a [SliceBarList].
class SliceBar {
  /// Creates a row.
  const SliceBar({
    required this.label,
    required this.value,
    required this.share,
    this.detail,
    this.onTap,
    this.swatch,
  });

  /// What this slice is, already localised.
  final String label;

  /// The figure, **already rendered by its own widget** — an `AmountText` or a `QtyText`.
  ///
  /// A `Money` field would have hardcoded `AmountText` here and made this list unable to show a
  /// quantity, which query 10 needs; formatting either into a `String` at the call site would bypass
  /// the only path from a `Money` or a `Qty` to pixels (Law U7). The same reasoning gives
  /// `KeyValueRow` its `valueWidget`.
  final Widget value;

  /// Its share of the largest slice, `0.0`-`1.0`, which sets the bar's length.
  final double share;

  /// An optional second line — a count, a unit, a date.
  final String? detail;

  /// Opens this slice's drill-down.
  final VoidCallback? onTap;

  /// The colour of this slice's wedge, when a donut sits above the list.
  ///
  /// Present only where a ring is showing. It is what ties a row to its arc, and it is why the ring can
  /// use a single-hue ramp instead of categorical colours — identity lives here, in text, beside a
  /// figure (Law U17: colour is never the only signal).
  final Color? swatch;
}

/// A ranked breakdown as labelled bars, largest first.
///
/// **This is the workhorse surface and it deliberately uses no chart library.** A pie is unreadable
/// at a doubled text scale, cannot label eight slices, and gives the reader nothing to tap; a ranked
/// list of figures is what somebody deciding where their money went actually needs, and every row is
/// a 48dp target into the ledger behind it (Laws U3, U13, U15).
///
/// `fl_chart` earns its place for the two shapes a list genuinely cannot express — a trend over time
/// and a bucketed heatmap — and nowhere else.
class SliceBarList extends StatelessWidget {
  /// Creates a breakdown of [slices].
  const SliceBarList({
    required this.slices,
    this.maxRows = 6,
    this.showBars = true,
    super.key,
  });

  /// The slices, already ordered.
  final List<SliceBar> slices;

  /// Whether each row draws its proportional bar.
  ///
  /// False where a donut sits above the list: the ring already carries the proportion, and a bar
  /// repeating it is the second accessory to remove. The swatch and the figure stay.
  final bool showBars;

  /// How many rows to show before stopping.
  ///
  /// A card is a shortlist, not a second screen: the drill-down holds the rest. Six is what fits
  /// above the fold on the narrowest supported phone.
  final int maxRows;

  /// Above this text scale a row stacks its figure under its label (Law U21).
  static const double _stackAboveScale = 1.5;

  @override
  Widget build(BuildContext context) {
    final stacked =
        MediaQuery.textScalerOf(context).scale(1) >= _stackAboveScale;
    // A plain Column, not a ListView: this is a bounded shortlist of at most [maxRows] inside a card
    // that is already inside the screen's scroll view. Law U13 is about lists fed by a repository
    // stream, and a nested scrollable here would put two gestures in one arena (ARCH_6 P2).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final slice in slices.take(maxRows))
          _SliceRow(slice: slice, stacked: stacked, showBar: showBars),
      ],
    );
  }
}

class _SliceRow extends StatelessWidget {
  const _SliceRow({
    required this.slice,
    required this.stacked,
    required this.showBar,
  });

  final SliceBar slice;
  final bool stacked;
  final bool showBar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;

    final text = Text(
      slice.label,
      style: AlayaTypography.body.copyWith(color: theme.colorScheme.onSurface),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    final label = slice.swatch == null
        ? text
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Decorative: the arc it matches is already excluded from semantics, and the label beside
              // it carries the identity.
              ExcludeSemantics(child: _Swatch(color: slice.swatch!)),
              const SizedBox(width: AlayaSpacing.xs),
              Flexible(child: text),
            ],
          );
    final amount = slice.value;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stacked) ...[
          label,
          const SizedBox(height: AlayaSpacing.xxs),
          Align(alignment: Alignment.centerLeft, child: amount),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: label),
              const SizedBox(width: AlayaSpacing.sm),
              amount,
            ],
          ),
        if (slice.detail != null) ...[
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            slice.detail!,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ],
        if (showBar) ...[
          const SizedBox(height: AlayaSpacing.xs),
          ExcludeSemantics(child: _Bar(share: slice.share)),
        ],
      ],
    );

    // One semantics node per row, so a screen reader reads "Groceries, 4,200 rupees" as one thing
    // rather than three fragments and an unlabelled bar (ARCH_5 §6).
    //
    // **`container: true` with no `label`, deliberately.** A hand-written label would replace the
    // children's own semantics — including `AmountText`'s, which is the only thing that knows how to
    // say a `Money` out loud. Building that string here would mean formatting minor units at the call
    // site, which is the Law U7 violation the widget exists to prevent. Only the bar is excluded: it
    // carries nothing the figure beside it does not.
    final semantics = Semantics(
      container: true,
      button: slice.onTap != null,
      child: body,
    );

    final padded = Padding(
      padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.xs),
      child: semantics,
    );

    if (slice.onTap == null) return padded;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: slice.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AlayaSpacing.minTapTarget,
          ),
          child: padded,
        ),
      ),
    );
  }
}

/// The dot tying a row to its wedge.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  /// On the spacing scale, like every other dimension (Law U6).
  static const double _size = AlayaSpacing.sm;

  @override
  Widget build(BuildContext context) => Container(
    width: _size,
    height: _size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// The proportional bar under a row.
class _Bar extends StatelessWidget {
  const _Bar({required this.share});

  final double share;

  /// The bar's thickness. On the spacing scale because Law U6 admits no other source of a dimension.
  static const double _thickness = AlayaSpacing.xs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Clamped, because `share` is a ratio computed from sums and a rounding artefact above 1 would
    // hand `FractionallySizedBox` a factor it asserts on.
    final factor = share.isFinite ? share.clamp(0.0, 1.0) : 0.0;
    return ClipRRect(
      borderRadius: AlayaRadii.borderXs,
      child: SizedBox(
        height: _thickness,
        child: ColoredBox(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: factor,
            child: ColoredBox(color: theme.colorScheme.primary),
          ),
        ),
      ),
    );
  }
}
```

### `lib/features/analytics/presentation/widgets/spend_cards.dart`

```dart
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
```

### `lib/features/analytics/presentation/widgets/split_cards.dart`

```dart
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
```

### `lib/features/analytics/presentation/widgets/time_cards.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_bar_chart.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_line_chart.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';

/// A `yyyymm` month key as a short localised month name.
///
/// `DateKey.fromYmd(y, m, 1)` rather than arithmetic on the key: `fromYmd` **validates**, so a
/// malformed month key throws here rather than rendering a nonsense label (ARCH_2's 7A amendment).
String _monthLabel(BuildContext context, int monthKey) {
  final date = DateKey.fromYmd(monthKey ~/ 100, monthKey % 100, 1);
  return DateFormat.MMM(
    Localizations.localeOf(context).toLanguageTag(),
  ).format(date.toUtcMidnight());
}

/// Only the first and last tick are labelled, and every tick when there are few enough.
///
/// Twelve month labels do not fit across a phone; two do, and the shape between them is what the card
/// is for.
bool _labelTick(int index, int last) =>
    index == 0 || index == last || last <= _denseTickLimit;

const int _denseTickLimit = 4;

/// Query 5 — income against expense, month by month.
class IncomeVsExpenseCard extends ConsumerWidget {
  /// Creates the card.
  const IncomeVsExpenseCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(incomeVsExpenseProvider);

    return ChartCard<IncomeVsExpense>(
      title: strings.analyticsIncomeVsExpense,
      value: async,
      isEmpty: (data) => data.points.length < 2,
      // Fewer than two months is not a trend, and a single pair of dots presented as one would invite
      // a comparison the data cannot support.
      emptyMessage: strings.analyticsNeedTwoMonths,
      onRetry: () => ref.invalidate(incomeVsExpenseProvider),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, data) {
        final last = data.points.length - 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Legend(
              entries: [
                (label: strings.rangeMoneyIn, tone: AnalyticsSeriesTone.income),
                (
                  label: strings.rangeMoneyOut,
                  tone: AnalyticsSeriesTone.expense,
                ),
              ],
            ),
            const SizedBox(height: AlayaSpacing.xs),
            AnalyticsPlotBox(
              child: AnalyticsLineChart(
                series: [
                  AnalyticsSeries(
                    tone: AnalyticsSeriesTone.income,
                    points: [
                      for (var i = 0; i <= last; i++)
                        AnalyticsPoint(
                          x: i.toDouble(),
                          value: data.points[i].income.minor,
                          axisLabel: _labelTick(i, last)
                              ? _monthLabel(context, data.points[i].monthKey)
                              : null,
                        ),
                    ],
                  ),
                  AnalyticsSeries(
                    tone: AnalyticsSeriesTone.expense,
                    points: [
                      for (var i = 0; i <= last; i++)
                        AnalyticsPoint(
                          x: i.toDouble(),
                          value: data.points[i].expense.minor,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Query 6 — net cash flow per month, from the signed ledger.
class NetCashFlowCard extends ConsumerWidget {
  /// Creates the card.
  const NetCashFlowCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(netCashFlowProvider);

    return ChartCard<NetCashFlow>(
      title: strings.analyticsNetFlow,
      // Worth stating: a reader who moves money between their own accounts every month would
      // otherwise wonder why it is absent. `v_account_ledger` nets a transfer to zero across its two
      // legs, so it never reaches this line.
      subtitle: strings.analyticsNetFlowNote,
      value: async,
      isEmpty: (data) => data.points.isEmpty,
      emptyMessage: strings.analyticsNoFlow,
      onRetry: () => ref.invalidate(netCashFlowProvider),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, data) {
        final last = data.points.length - 1;
        return AnalyticsPlotBox(
          child: AnalyticsLineChart(
            series: [
              AnalyticsSeries(
                // Neutral, not income or expense: a net figure crosses zero, and colouring the whole
                // line by one direction would assert something half of it contradicts. The chart
                // includes zero in its band so the crossing is visible.
                tone: AnalyticsSeriesTone.neutral,
                filled: true,
                points: [
                  for (var i = 0; i <= last; i++)
                    AnalyticsPoint(
                      x: i.toDouble(),
                      value: data.points[i].amount.minor,
                      axisLabel: _labelTick(i, last)
                          ? _monthLabel(context, data.points[i].monthKey)
                          : null,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Query 7 — one account's running balance, in that account's own currency.
class BalanceTrendCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const BalanceTrendCard({super.key});

  @override
  ConsumerState<BalanceTrendCard> createState() => _BalanceTrendCardState();
}

class _BalanceTrendCardState extends ConsumerState<BalanceTrendCard> {
  String? _accountId;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final accounts =
        ref.watch(analyticsAccountsProvider).valueOrNull ?? const <Account>[];
    if (accounts.isEmpty) return const SizedBox.shrink();

    // **The account is resolved, not asked for** (Law U23). A household with one account is never
    // shown a picker; the first selectable account is the answer, and the picker appears only when
    // there is a genuine choice.
    final selected = _resolve(accounts);
    final async = ref.watch(balanceTrendProvider(selected.id));
    final digits =
        ref
            .watch(analyticsDigitsForCurrencyProvider(selected.currencyCode))
            .valueOrNull ??
        2;

    return ChartCard<BalanceTrend>(
      title: strings.analyticsBalanceTrend,
      // The currency is named because this is the one card not in the home currency, and an
      // unlabelled figure in a second currency is a wrong figure.
      subtitle: strings.analyticsBalanceIn(
        selected.name,
        selected.currencyCode,
      ),
      value: async,
      isEmpty: (trend) => trend.points.length < 2,
      emptyMessage: strings.analyticsNoBalanceMovement,
      onRetry: () => ref.invalidate(balanceTrendProvider(selected.id)),
      trailing:
          async.valueOrNull != null && async.valueOrNull!.points.isNotEmpty
          ? AmountText(
              async.valueOrNull!.points.last.balance,
              size: AmountSize.small,
              showSign: false,
              decimalDigits: digits,
            )
          : null,
      builder: (context, trend) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (accounts.length > 1)
            _AccountPicker(
              accounts: accounts,
              selectedId: selected.id,
              onChanged: (id) => setState(() => _accountId = id),
            ),
          AnalyticsPlotBox(
            child: AnalyticsLineChart(
              series: [
                AnalyticsSeries(
                  tone: AnalyticsSeriesTone.neutral,
                  points: [
                    for (var i = 0; i < trend.points.length; i++)
                      AnalyticsPoint(
                        x: i.toDouble(),
                        value: trend.points[i].balance.minor,
                        axisLabel: _labelTick(i, trend.points.length - 1)
                            ? DateFormat.MMMd(
                                Localizations.localeOf(context).toLanguageTag(),
                              ).format(trend.points[i].date.toUtcMidnight())
                            : null,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Account _resolve(List<Account> accounts) {
    final id = _accountId;
    if (id != null) {
      for (final account in accounts) {
        if (account.id == id) return account;
      }
    }
    return accounts.first;
  }
}

/// Which account the balance trend is showing.
class _AccountPicker extends StatelessWidget {
  const _AccountPicker({
    required this.accounts,
    required this.selectedId,
    required this.onChanged,
  });

  final List<Account> accounts;
  final String selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
      child: DropdownButtonFormField<String>(
        // **`isExpanded` is not optional** (ARCH_5 §10): without it the field lays out at the widest
        // item's natural width and overflows a narrow card.
        isExpanded: true,
        initialValue: selectedId,
        decoration: InputDecoration(labelText: strings.analyticsAccount),
        items: [
          for (final account in accounts)
            DropdownMenuItem(value: account.id, child: Text(account.name)),
        ],
        onChanged: (id) {
          if (id != null) onChanged(id);
        },
      ),
    );
  }
}

/// Query 21 — the spend heatmap, by weekday or by day of month.
class SpendHeatmapCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const SpendHeatmapCard({super.key});

  @override
  ConsumerState<SpendHeatmapCard> createState() => _SpendHeatmapCardState();
}

class _SpendHeatmapCardState extends ConsumerState<SpendHeatmapCard> {
  bool _byWeekday = true;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(spendHeatmapProvider(_byWeekday));

    return ChartCard<SpendHeatmap>(
      title: strings.analyticsHeatmap,
      value: async,
      isEmpty: (data) => data.cells.isEmpty,
      emptyMessage: strings.analyticsNothingSpent,
      onRetry: () => ref.invalidate(spendHeatmapProvider(_byWeekday)),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, data) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: true,
                label: Text(strings.analyticsByWeekday),
              ),
              ButtonSegment(
                value: false,
                label: Text(strings.analyticsByDayOfMonth),
              ),
            ],
            selected: {_byWeekday},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => _byWeekday = selection.first),
          ),
          const SizedBox(height: AlayaSpacing.sm),
          AnalyticsPlotBox(
            child: AnalyticsBarChart(
              // Thirty-one labels do not fit across a phone; seven do. Every fifth day is enough to
              // orient the reader without the axis becoming a smear.
              labelEvery: _byWeekday ? 1 : _dayOfMonthLabelEvery,
              buckets: [
                for (final cell in data.cells)
                  AnalyticsBucket(
                    bucket: cell.bucket,
                    value: cell.amount.minor,
                    label: AnalyticsLabels.bucket(
                      context,
                      cell.bucket,
                      byWeekday: _byWeekday,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const int _dayOfMonthLabelEvery = 5;
}

/// A key for a multi-series chart, since colour alone cannot say which line is which (Law U17).
class _Legend extends StatelessWidget {
  const _Legend({required this.entries});

  final List<({String label, AnalyticsSeriesTone tone})> entries;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Wrap(
      spacing: AlayaSpacing.sm,
      runSpacing: AlayaSpacing.xxs,
      children: [
        for (final entry in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Swatch(tone: entry.tone),
              const SizedBox(width: AlayaSpacing.xxs),
              Text(
                entry.label,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
            ],
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.tone});

  final AnalyticsSeriesTone tone;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final color = switch (tone) {
      AnalyticsSeriesTone.income => semantic.income,
      AnalyticsSeriesTone.expense => semantic.expense,
      AnalyticsSeriesTone.neutral => semantic.transfer,
    };
    return SizedBox(
      width: AlayaSpacing.sm,
      height: AlayaSpacing.xxs,
      child: ColoredBox(color: color),
    );
  }
}
```

### `lib/features/analytics/providers/analytics_providers.dart`

```dart
/// View-model state for the analytics screens (ARCH_5 U19).
///
/// **Nothing here declares a repository or an engine.** The range, the resolved window, the display
/// precision and the cache action are screen state; `analyticsServiceProvider`,
/// `analyticsCacheServiceProvider` and every repository live in `lib/app/providers/` and are watched
/// from here (ARCH_1 §7.3, Law U19).
library;

import 'dart:async';

import 'package:alaya/core/time/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/state/analytics_range.dart';

/// The window every figure on the analytics screen is bounded by, restored from `app_settings`.
final analyticsRangeProvider =
    NotifierProvider<AnalyticsRangeNotifier, DateRangePreset>(
      AnalyticsRangeNotifier.new,
    );

/// Holds and persists the chosen reporting window.
///
/// The same shape as 6F's `InsightSideNotifier`: a synchronous default so the first frame has a
/// window, then an unawaited restore. A `FutureProvider` here would make every chart on the screen
/// wait on a settings read to learn which month it is showing.
class AnalyticsRangeNotifier extends Notifier<DateRangePreset> {
  @override
  DateRangePreset build() {
    unawaited(_restore());
    return AnalyticsRange.fallback;
  }

  Future<void> _restore() async {
    final stored = await ref
        .read(settingsRepositoryProvider)
        .readValue(AnalyticsRange.settingsKey);
    final restored = AnalyticsRange.parse(stored);
    if (restored != state) state = restored;
  }

  /// Shows [preset] and remembers it.
  ///
  /// The write is not awaited: the charts should recompute on the frame the chip is tapped, and a
  /// settings row landing a millisecond later changes nothing the reader can see.
  void show(DateRangePreset preset) {
    state = preset;
    unawaited(
      ref
          .read(settingsRepositoryProvider)
          .writeValue(
            key: AnalyticsRange.settingsKey,
            value: AnalyticsRange.stored(preset),
            valueType: 'string',
          ),
    );
  }
}

/// The chosen preset resolved against today.
///
/// **`DateRange` and `AnalyticsWindow` are the same record type** — both are
/// `({DateKey from, DateKey to})` — so this needs no conversion and none is written. They are
/// declared separately because `DateRangeService` and the analytics layer were built in different
/// phases, and Dart's structural records make that free rather than a mapping to maintain.
///
/// `resolve` returns null only for [DateRangePreset.custom], which `AnalyticsRange.presets` does not
/// offer; the fallback covers a preset restored from a future version's settings row.
final analyticsWindowProvider = Provider<AnalyticsWindow>((ref) {
  final today = ref.watch(clockProvider).today();
  final preset = ref.watch(analyticsRangeProvider);
  final service = ref.watch(dateRangeServiceProvider);
  return service.resolve(preset, today) ??
      service.resolve(AnalyticsRange.fallback, today)!;
});

/// The window immediately before [analyticsWindowProvider], for a period-over-period comparison.
///
/// `precedingWindowOf` rather than `previousWholeMonth`: the honest comparison for "last 30 days" is
/// the 30 days before those, not a calendar month of a different length.
final analyticsPreviousWindowProvider = Provider<AnalyticsWindow>((ref) {
  return ref
      .watch(dateRangeServiceProvider)
      .precedingWindowOf(ref.watch(analyticsWindowProvider));
});

/// The home currency every converted figure is expressed in.
final analyticsCurrencyProvider = FutureProvider<String>((ref) async {
  return await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      analyticsFallbackHomeCurrencyCode;
});

/// The home currency's minor-unit precision (ARCH_1 §4.1).
///
/// Read rather than assumed, because `AmountText` defaults to 2 and JPY has none — rendering
/// `¥1,200.00` is wrong, and hardcoding `100` anywhere is what the `currencies` table exists to
/// prevent.
final analyticsDigitsProvider = FutureProvider<int>((ref) async {
  final code = await ref.watch(analyticsCurrencyProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// One named currency's minor-unit precision.
///
/// **Needed because not every figure on this screen is in the home currency.** A balance trend stays in
/// its account's own currency — converting each point at its own date would make the line move when
/// rates moved rather than when money did — and rendering a yen balance with the home currency's two
/// digits would print `¥1,200.00` for `¥1,200`. `AmountText` defaults to 2 and says a screen holding
/// the currency should pass the real value; this is how it gets it.
final analyticsDigitsForCurrencyProvider = FutureProvider.autoDispose
    .family<int, String>((ref, currencyCode) async {
      final currency = await ref
          .watch(currencyRepositoryProvider)
          .byCode(currencyCode);
      return currency?.decimalDigits ?? 2;
    });

/// How many amounts currently cannot be converted into the home currency.
///
/// The stream Phase 7B implemented over `UnconvertedCounter`; it was `Stream.value(0)` until this
/// phase (ARCH_3 §1.5, ARCH_5 §7.3). Watched here so the screen's header can report a partial total
/// once, rather than every card repeating the same caveat.
final analyticsUnconvertedProvider = StreamProvider<int>(
  (ref) => ref.watch(currencyRepositoryProvider).watchUnconvertedCount(),
);

/// Clears the memoised analytics results and reports the outcome.
///
/// **This is the whole of `analytics_cache`'s user-facing surface** (ARCH_5 §7.1, §7.3: "invisible by
/// design; only 'clear cache' ever surfaces").
///
/// ARCH_5 §7.1 assigns the control to Settings, and Settings is a `PlaceholderScreen` until Phase 8A
/// — so it ships on the analytics screen itself, as a quiet row after the figures in the manner of
/// archetype E's destructive actions. It could not go in the app bar: `Routes.insights` is a shell
/// destination and the app bar belongs to `_ShellScaffold`, so an action added there would appear on
/// all nine destinations. Phase 8A's Settings entry must call this same notifier rather than the
/// service directly (Law U22).
final analyticsCacheControllerProvider =
    NotifierProvider<AnalyticsCacheController, AsyncValue<DateKey?>>(
      AnalyticsCacheController.new,
    );

/// Owns the clear-cache action and the date it last succeeded on.
///
/// The state is an `AsyncValue` so the row can disable itself while clearing and render the
/// repository's own message on failure (Laws U4, U9) — not because the value itself is fetched.
class AnalyticsCacheController extends Notifier<AsyncValue<DateKey?>> {
  @override
  AsyncValue<DateKey?> build() => const AsyncData<DateKey?>(null);

  /// Invalidates every cached result, then recomputes what is on screen.
  ///
  /// Returns whether it succeeded, so the caller can choose between a result snack and a failure
  /// snack; the message stays in [state] for the row to render in place.
  ///
  /// **Coarse by design.** `AnalyticsCacheService.invalidateOnWrite` drops everything rather than
  /// tracking which of the twenty-four queries a row touches — that dependency graph is a thing to
  /// maintain and get wrong, and recomputing on the next open is cheap by comparison.
  Future<bool> clear() async {
    state = const AsyncLoading<DateKey?>();
    try {
      await ref.read(analyticsCacheServiceProvider).invalidateOnWrite();
      state = AsyncData<DateKey?>(ref.read(clockProvider).today());
      // Dropping the rows is not enough on its own: a provider that already resolved is holding the
      // figure it computed, and without this the screen would show the same numbers over an empty
      // cache and the action would look like it did nothing (Law U9).
      ref.invalidate(analyticsServiceProvider);
      return true;
    } catch (error, stackTrace) {
      // The service swallows its own read and write failures, so reaching here means the delete
      // itself failed. Surfaced rather than ignored: the alternative is a button that silently does
      // nothing, which U9 calls the worst outcome available.
      state = AsyncError<DateKey?>(error, stackTrace);
      return false;
    }
  }
}
```

### `lib/features/analytics/providers/chart_providers.dart`

```dart
/// One view-model provider per ARCH_3 §5.1 query (ARCH_5 U19).
///
/// **Every figure is its own provider, and that is what makes archetype F's "one failing card never
/// blanks the screen" true rather than aspirational.** A single provider returning all twenty-four
/// results would fail as a unit.
///
/// All of them watch `analyticsWindowProvider`, so changing the range chip recomputes the screen with
/// no per-card plumbing. All are `autoDispose`: leaving the screen should release a month of
/// aggregates rather than hold them for a session.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/services/analytics/analytics_cache_service.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';

/// An item named for a family key, so a provider caches per item rather than per rebuild.
///
/// A record, so Riverpod compares by value. The name travels with the id because
/// `AnalyticsService.unitPriceTrend` takes both — the port returns ids and the service will not guess
/// a label it was not given.
typedef AnalyticsItemRef = ({String id, String name});

// ── the headline ──────────────────────────────────────────────────────────────────────────

/// Total spend in the window and how concentrated it is — queries 8 and 22.
///
/// **One query serves the headline figure and the concentration card**, because
/// `Concentration.total` *is* total spend in the home currency. `AnalyticsPort.totalSpend` exists and
/// `AnalyticsService` never calls it: the service derives the total from `spendBySubtype` instead, so
/// asking the port again would be a second read for a number already in hand.
final analyticsHeadlineProvider = FutureProvider.autoDispose<Concentration>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.categoryConcentration(ref.watch(analyticsWindowProvider));
});

/// The same figure over the preceding window of equal length, for a period-over-period line.
final analyticsPreviousHeadlineProvider =
    FutureProvider.autoDispose<Concentration>((ref) async {
      final service = await ref.watch(analyticsServiceProvider.future);
      return service.categoryConcentration(
        ref.watch(analyticsPreviousWindowProvider),
      );
    });

// ── 1-4: where it went ────────────────────────────────────────────────────────────────────

/// Query 1 — spend by subtype.
///
/// The slices carry the **enum name** as both key and label, because that is what SQL grouped by. A
/// surface renders `slice.key` through an ARB lookup and never `slice.label`, or an untranslated
/// `grocery` reaches the screen (Law U5).
final spendBySubtypeProvider = FutureProvider.autoDispose<MoneySeries>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.spendBySubtype(ref.watch(analyticsWindowProvider));
});

/// Query 2 — spend by tag. Labels here **are** data, so they render directly.
///
/// A transaction carrying two tags contributes to both slices, so these do not sum to total spend.
/// The surface says so rather than presenting them as a partition.
final spendByTagProvider = FutureProvider.autoDispose<MoneySeries>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.spendByTag(ref.watch(analyticsWindowProvider));
});

/// Query 3 — spend by payment method.
final spendByPaymentMethodProvider = FutureProvider.autoDispose<MoneySeries>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.spendByPaymentMethod(ref.watch(analyticsWindowProvider));
});

/// Query 4 — the top payees by spend, ranked after conversion.
final topPayeesProvider = FutureProvider.autoDispose<MoneySeries>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.topPayeesBySpend(ref.watch(analyticsWindowProvider));
});

/// Query 8 — grocery's share of total spend, or null when nothing was spent on groceries.
final groceryShareProvider = FutureProvider.autoDispose<ShareOfTotal?>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.groceryShareOfSpend(ref.watch(analyticsWindowProvider));
});

// ── the tag hierarchy, for the one-level drill ARCH_5 §7.2 assigns ────────────────────────

/// Every tag by id, so a slice can be rolled up to its parent.
///
/// `watchAll` rather than `watchRoots` plus `watchChildren`: the rollup needs the whole
/// `id -> parentTagId` map in one place, and the tag table is small enough that two streams would be
/// more work than one map.
final analyticsTagsByIdProvider = StreamProvider.autoDispose<Map<String, Tag>>(
  (ref) => ref
      .watch(tagRepositoryProvider)
      .watchAll()
      .map((tags) => {for (final tag in tags) tag.id: tag}),
);

/// One tag's spend and the spend of its children, for the tag card's two levels.
class TagSpendNode {
  /// Creates a node.
  const TagSpendNode({
    required this.tag,
    required this.own,
    required this.rolledUp,
    required this.children,
  });

  /// The tag itself. May be soft-deleted, which still labels old transactions (anomaly A36).
  final Tag tag;

  /// What was spent against this tag alone.
  final Money own;

  /// [own] plus every child's spend — what the top level shows.
  final Money rolledUp;

  /// This tag's children that have spend in the window, largest first.
  final List<TagSpendNode> children;

  /// Whether drilling into this node would show anything new.
  bool get canDrill => children.isNotEmpty;
}

/// Root tags with their children rolled up, largest first — the tag card's feed.
///
/// **This is the whole of `tags.parentTagId`'s analytics surface** (ARCH_5 §7.2). One level, because
/// the schema permits exactly one and the repository enforces it (ARCH_2 §3).
///
/// A slice whose tag is missing from the map is dropped rather than shown parentless: it means the
/// tag stream and the spend query disagreed for a frame, and inventing a row for it would flicker.
final tagSpendTreeProvider = FutureProvider.autoDispose<List<TagSpendNode>>((
  ref,
) async {
  final series = await ref.watch(spendByTagProvider.future);
  final tags = await ref.watch(analyticsTagsByIdProvider.future);
  final code = await ref.watch(analyticsCurrencyProvider.future);

  final own = <String, Money>{};
  for (final slice in series.slices) {
    own[slice.key] = slice.amount;
  }

  final childrenOf = <String, List<TagSpendNode>>{};
  final roots = <String, Money>{};
  for (final entry in own.entries) {
    final tag = tags[entry.key];
    if (tag == null) continue;
    final parentId = tag.parentTagId;
    if (parentId == null) continue;
    (childrenOf[parentId] ??= <TagSpendNode>[]).add(
      TagSpendNode(
        tag: tag,
        own: entry.value,
        rolledUp: entry.value,
        children: const <TagSpendNode>[],
      ),
    );
  }

  for (final entry in own.entries) {
    final tag = tags[entry.key];
    if (tag == null || tag.isChild) continue;
    roots[entry.key] = entry.value;
  }
  // A parent with no spend of its own but children that do spend still belongs at the top level:
  // "Grocery ₹0" would be wrong and hiding it would lose the children entirely.
  for (final parentId in childrenOf.keys) {
    if (tags.containsKey(parentId))
      roots.putIfAbsent(parentId, () => Money.zero(code));
  }

  final nodes = <TagSpendNode>[];
  for (final entry in roots.entries) {
    final children = (childrenOf[entry.key] ?? const <TagSpendNode>[]).toList()
      ..sort((a, b) => b.rolledUp.minor.compareTo(a.rolledUp.minor));
    final rolled = children.fold<int>(
      entry.value.minor,
      (sum, c) => sum + c.rolledUp.minor,
    );
    nodes.add(
      TagSpendNode(
        tag: tags[entry.key]!,
        own: entry.value,
        rolledUp: Money(rolled, code),
        children: children,
      ),
    );
  }
  nodes.sort((a, b) => b.rolledUp.minor.compareTo(a.rolledUp.minor));
  return nodes;
});

// ── 5-7, 21: over time ────────────────────────────────────────────────────────────────────

/// Query 5 — income against expense, month by month.
final incomeVsExpenseProvider = FutureProvider.autoDispose<IncomeVsExpense>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.incomeVsExpense(ref.watch(analyticsWindowProvider));
});

/// Query 6 — net cash flow per month, from the signed ledger.
final netCashFlowProvider = FutureProvider.autoDispose<NetCashFlow>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.netCashFlowByMonth(ref.watch(analyticsWindowProvider));
});

/// Query 7 — one account's running balance, in that account's own currency.
///
/// Never converted: converting each point at its own date would make the line move when rates moved
/// rather than when money did.
final balanceTrendProvider = FutureProvider.autoDispose
    .family<BalanceTrend, String>((ref, accountId) async {
      final service = await ref.watch(analyticsServiceProvider.future);
      return service.balanceTrend(
        accountId,
        ref.watch(analyticsWindowProvider),
      );
    });

/// The accounts the balance-trend card can offer.
final analyticsAccountsProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// Query 21 — spend bucketed by weekday or day of month, **through the cache**.
///
/// **One of exactly two cached queries in this phase, and the gate is
/// `AnalyticsCacheService.shouldCache` rather than a preference.** This one earns it: the bucket is
/// `strftime` over a rebuilt date string, so no index in ARCH_2 §11 can serve the grouping and the
/// cost grows with the whole window rather than with the number of buckets.
///
/// The other twenty-two are computed live. §5.2 asks for a cache "for anything over ~200 ms", and the
/// service's own doc comment says why the rest are not: a cache on a query that already runs in 5 ms
/// costs a read, a write, an invalidation path and a staleness bug and buys nothing.
final spendHeatmapProvider = FutureProvider.autoDispose.family<SpendHeatmap, bool>((
  ref,
  byWeekday,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  final cache = ref.watch(analyticsCacheServiceProvider);
  final window = ref.watch(analyticsWindowProvider);

  if (!cache.shouldCache(heatmapEstimatedCost)) {
    return service.spendHeatmap(window, byWeekday: byWeekday);
  }
  // Encoded then decoded even on a miss, deliberately: the cache stores strings, so one path through
  // the codec is simpler than two and guarantees a hit and a miss return the same shape.
  final payload = await cache.readOrCompute(
    queryName: 'spendHeatmap',
    params: {...cache.windowParams(window), 'byWeekday': byWeekday},
    compute: () async => _encodeHeatmap(
      await service.spendHeatmap(window, byWeekday: byWeekday),
    ),
  );
  return _decodeHeatmap(payload);
});

/// What query 21 is estimated to cost, measured against `AnalyticsCacheService.cacheThreshold`.
const Duration heatmapEstimatedCost = Duration(milliseconds: 250);

/// What query 13 is estimated to cost.
const Duration inventoryValueEstimatedCost = Duration(milliseconds: 220);

// ── 9-12, 23, 24: items and prices ────────────────────────────────────────────────────────

/// Query 9 — the top items by spend, ranked after conversion.
final topItemsBySpendProvider = FutureProvider.autoDispose<List<ItemSpend>>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.topItemsBySpend(ref.watch(analyticsWindowProvider));
});

/// Query 10 — the top items by quantity bought, per unit category.
///
/// Not ranked across categories and not converted: grams and pieces are not comparable at all
/// (Law L8), so the surface groups by category rather than producing a single ordering that would
/// mean nothing.
final topItemsByQuantityProvider =
    FutureProvider.autoDispose<List<ItemQuantity>>((ref) async {
      final service = await ref.watch(analyticsServiceProvider.future);
      return service.topItemsByQuantity(ref.watch(analyticsWindowProvider));
    });

/// Query 11 — the dearest single purchase of one item, in the currency it was bought in.
final dearestPurchaseProvider = FutureProvider.autoDispose
    .family<DearestPurchase?, AnalyticsItemRef>((ref, item) async {
      final service = await ref.watch(analyticsServiceProvider.future);
      return service.dearestPurchaseOfItem(
        item.id,
        item.name,
        ref.watch(analyticsWindowProvider),
      );
    });

/// Queries 12 and 24 — one item's unit-price trend and the change across it.
///
/// **One provider for both queries, because query 24 is query 12's data.**
/// `AnalyticsService.unitPriceTrend` calls `pricePerBaseUnitHistory` and returns its points
/// alongside the percentage change, so a second provider would run the same read twice. The surface
/// draws the points (24) and states the change (12).
final unitPriceTrendProvider = FutureProvider.autoDispose
    .family<UnitPriceTrend, AnalyticsItemRef>((ref, item) async {
      final service = await ref.watch(analyticsServiceProvider.future);
      return service.unitPriceTrend(
        item.id,
        item.name,
        ref.watch(analyticsWindowProvider),
      );
    });

/// The item whose unit price moved most across the window — the personal-inflation headline.
///
/// **This is the screenshot** (ARCH_3 §5.1: *"your potatoes cost 34% more than in January"*). It is
/// derived rather than asked for: no query returns "the most interesting item", so the candidates are
/// the top items by spend — the ones the reader actually buys — and the winner is the largest
/// absolute change among them.
///
/// Capped at [inflationCandidateCount] queries. Uncapped this would be one read per item in the
/// house, on a card that shows one line.
///
/// Null when nothing has two priced purchases in the window, which is the ordinary case for a new
/// install and reads as an absence rather than as a failure.
final personalInflationProvider = FutureProvider.autoDispose<UnitPriceTrend?>((
  ref,
) async {
  final items = await ref.watch(topItemsBySpendProvider.future);
  UnitPriceTrend? best;
  for (final item in items.take(inflationCandidateCount)) {
    final trend = await ref.watch(
      unitPriceTrendProvider((id: item.itemId, name: item.itemName)).future,
    );
    final change = trend.percentChange;
    if (change == null) continue;
    final bestChange = best?.percentChange;
    if (bestChange == null || change.abs() > bestChange.abs()) best = trend;
  }
  return best;
});

/// How many of the top-spend items are probed for a price trend.
const int inflationCandidateCount = 5;

/// Query 23 — the average grocery basket.
final averageBasketProvider = FutureProvider.autoDispose<BasketStats>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.averageGroceryBasket(ref.watch(analyticsWindowProvider));
});

// ── 13-16: the home ───────────────────────────────────────────────────────────────────────

/// Query 13 — inventory value on hand, per currency, **through the cache**.
///
/// The second of the two cached queries. It is unbounded by design — stock on hand has no window —
/// so its cost grows with the shelf rather than with the range, and it is the one figure on the
/// screen that a narrower range cannot make cheaper.
///
/// Per currency rather than one total: batch cost currency is per row, and a single figure would be
/// adding rupees to yen (anomaly A34).
final inventoryValueProvider = FutureProvider.autoDispose<InventoryValue>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  final cache = ref.watch(analyticsCacheServiceProvider);
  if (!cache.shouldCache(inventoryValueEstimatedCost)) {
    return service.inventoryValueOnHand();
  }
  final payload = await cache.readOrCompute(
    queryName: 'inventoryValueOnHand',
    // No window: the figure is "right now", so the parameter set is empty and the entry is a
    // singleton. `hashParams({})` is stable, so this still gets its own row.
    params: const <String, Object?>{},
    compute: () async =>
        _encodeInventoryValue(await service.inventoryValueOnHand()),
  );
  return _decodeInventoryValue(payload);
});

/// Query 14 — food waste, in quantity and money.
///
/// Reversed movements are already excluded by the adapter, so this reports what was wasted and not
/// what was wasted and then corrected.
final wasteTotalsProvider = FutureProvider.autoDispose<List<ItemWasteTotal>>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.wasteTotals(ref.watch(analyticsWindowProvider));
});

/// Query 15 — batches expiring within [days] of today, soonest first.
///
/// Keyed on days rather than on the window: expiry is about the future and the reporting range is
/// about the past, so tying the two would make "last month" show nothing expiring.
final expiringBatchesProvider = FutureProvider.autoDispose
    .family<List<ExpiringBatch>, int>((ref, days) async {
      final service = await ref.watch(analyticsServiceProvider.future);
      return service.itemsExpiringWithin(days);
    });

/// The expiry horizon the home section shows.
const int expiryHorizonDays = 14;

/// Query 16 — how many items are low on stock, as one point.
///
/// One point and not a history: `v_low_stock` reflects the present and stock is not versioned, so
/// "how many were low last Tuesday" would mean replaying the movement ledger against thresholds that
/// may since have changed.
final lowStockTodayProvider = FutureProvider.autoDispose<LowStockPoint>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.lowStockCountToday();
});

// ── 17-20: commitments and assets ─────────────────────────────────────────────────────────

/// Query 17 — the fixed monthly commitment total, every interval normalised to a month.
final monthlyCommitmentProvider = FutureProvider.autoDispose<MonthlyCommitment>(
  (ref) async {
    final service = await ref.watch(analyticsServiceProvider.future);
    return service.monthlyCommitmentTotal();
  },
);

/// Query 18 — the recurring against discretionary split.
final recurringSplitProvider = FutureProvider.autoDispose<RecurringSplit>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.recurringVsDiscretionary(ref.watch(analyticsWindowProvider));
});

/// Query 19 — lifetime service cost per asset, per currency.
///
/// Disposed assets are included: the money you put into a TV stays in the analytics after you sell
/// it, which is the point of `status = disposed` rather than a delete.
final serviceCostByAssetProvider =
    FutureProvider.autoDispose<List<AssetServiceCost>>((ref) async {
      final service = await ref.watch(analyticsServiceProvider.future);
      return service.lifetimeServiceCostByAsset(
        ref.watch(analyticsWindowProvider),
      );
    });

/// Query 20 — the warranty coverage timeline.
final warrantyCoverageProvider =
    FutureProvider.autoDispose<List<WarrantyCoverage>>((ref) async {
      final service = await ref.watch(analyticsServiceProvider.future);
      return service.warrantyCoverage();
    });

// ── cache codecs ──────────────────────────────────────────────────────────────────────────
//
// Two, not twenty-four. `AnalyticsCacheService` stores strings, so caching a result type means a
// codec for it — and writing twenty-four to satisfy the letter of ARCH_3 §5.2 would contradict its
// reasoning, which is that a cache is only worth its invalidation path above roughly 200 ms.
//
// `Money` encodes as minor units plus its code and never as a decimal (Law L1): a JSON number for
// `12.34` would be a double crossing a persistence boundary, which is exactly what L1 forbids.

String _encodeHeatmap(SpendHeatmap heatmap) => jsonEncode({
  'cells': [
    for (final cell in heatmap.cells)
      {
        'b': cell.bucket,
        'm': cell.amount.minor,
        'c': cell.amount.currencyCode,
        'n': cell.transactionCount,
      },
  ],
  'approx': heatmap.quality.approximateCount,
  'unconv': heatmap.quality.unconvertedCount,
});

SpendHeatmap _decodeHeatmap(String payload) {
  final root = jsonDecode(payload) as Map<String, Object?>;
  final raw = root['cells'] as List<Object?>? ?? const <Object?>[];
  // `const <HeatmapCell>[]` and never a bare `const []`: a record field takes the literal's inferred
  // type verbatim, so `List<dynamic>` would not satisfy `List<HeatmapCell>` (ARCH_4 R17).
  final cells = <HeatmapCell>[];
  for (final entry in raw) {
    final cell = entry as Map<String, Object?>;
    cells.add((
      bucket: cell['b']! as int,
      amount: Money(cell['m']! as int, cell['c']! as String),
      transactionCount: cell['n']! as int,
    ));
  }
  return (
    cells: cells.isEmpty ? const <HeatmapCell>[] : cells,
    quality: (
      approximateCount: root['approx'] as int? ?? 0,
      unconvertedCount: root['unconv'] as int? ?? 0,
    ),
  );
}

String _encodeInventoryValue(InventoryValue value) => jsonEncode({
  'by': {
    for (final entry in value.byCurrency.entries) entry.key: entry.value.minor,
  },
  'valued': value.batchesValued,
  'noCost': value.batchesNoCost,
});

InventoryValue _decodeInventoryValue(String payload) {
  final root = jsonDecode(payload) as Map<String, Object?>;
  final by = root['by'] as Map<String, Object?>? ?? const <String, Object?>{};
  return (
    byCurrency: {
      for (final entry in by.entries)
        entry.key: Money(entry.value! as int, entry.key),
    },
    batchesValued: root['valued'] as int? ?? 0,
    batchesNoCost: root['noCost'] as int? ?? 0,
  );
}
```

### `lib/features/analytics/providers/drill_down_providers.dart`

```dart
/// View-model state for the analytics drill-down (ARCH_5 U19).
///
/// **Every axis here is answerable from what `TransactionRepository` already exposes.** Four come
/// from fields the `Transaction` entity carries, so the window's indexed query does the narrowing and
/// the predicate runs over a page of rows rather than the table. `item` needs one extra stream and
/// gets it. `tag` has no arm at all — see `drill_down_spec.dart` for the missing read and its owner.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';

/// The transaction ids whose lines reference one item.
///
/// Only the `item` arm needs this. A line-level read cannot be folded into the predicate below,
/// because a `Transaction` does not know what its lines bought — so the ids are gathered once and the
/// windowed list is filtered against the set.
final drillDownItemTransactionIdsProvider = StreamProvider.autoDispose
    .family<Set<String>, String>((ref, itemId) {
      return ref
          .watch(transactionRepositoryProvider)
          .watchLinesForItem(itemId)
          .map((lines) => {for (final line in lines) line.transactionId});
    });

/// The transactions behind one analytics slice, newest first.
///
/// **The window comes from the analytics screen, not from the route** (ARCH_5 §5.7). A reader who set
/// the range to "this year" and tapped a slice expects this year's transactions; putting the dates in
/// the path would have made the two disagree the moment either changed.
///
/// Withdrawals only, matching every spend query in the adapter: a drill-down that showed the deposits
/// too would not add up to the slice it came from.
final drillDownTransactionsProvider = StreamProvider.autoDispose
    .family<List<Transaction>, DrillDownSpec>((ref, spec) {
      final window = ref.watch(analyticsWindowProvider);
      final rows = ref
          .watch(transactionRepositoryProvider)
          .watchByDateRange(from: window.from, to: window.to);

      if (spec.kind == DrillDownKind.item) {
        final ids = ref.watch(drillDownItemTransactionIdsProvider(spec.value));
        // Until the id set resolves the list stays loading rather than briefly showing every
        // transaction in the window — a flash of the unfiltered ledger reads as a broken filter.
        return ids.when(
          loading: Stream<List<Transaction>>.empty,
          error: (error, stack) =>
              Stream<List<Transaction>>.error(error, stack),
          data: (set) => rows.map(
            (all) => [
              for (final row in all)
                if (row.kind == TransactionKind.withdrawal &&
                    set.contains(row.id))
                  row,
            ],
          ),
        );
      }

      return rows.map(
        (all) => [
          for (final row in all)
            if (row.kind == TransactionKind.withdrawal && _admits(spec, row))
              row,
        ],
      );
    });

bool _admits(DrillDownSpec spec, Transaction row) => switch (spec.kind) {
  DrillDownKind.subtype => row.subtype.name == spec.value,
  DrillDownKind.paymentMethod => row.paymentMethodId == spec.value,
  DrillDownKind.payee => row.payeeId == spec.value,
  DrillDownKind.recurring =>
    spec.value == _recurringValue
        ? row.recurringTemplateId != null
        : row.recurringTemplateId == null,
  // Handled above, before the predicate: an item cannot be judged from the transaction alone.
  DrillDownKind.item => false,
};

/// The `recurring` side of query 18's split, spelled as the adapter's SQL spells it.
const String _recurringValue = 'recurring';

/// One day's transactions in a drill-down, for archetype C's sticky date header.
class DrillDownDayGroup {
  /// Creates a day group.
  const DrillDownDayGroup({required this.date, required this.transactions});

  /// The civil date these share.
  final DateKey date;

  /// The transactions on [date], newest first.
  final List<Transaction> transactions;
}

/// The drill-down's transactions grouped into days, newest day first.
///
/// **Grouped by day because archetype C requires it**: a finance ledger without date grouping is
/// unreadable past twenty rows (ARCH_5 §3 C). The same shape 6A's `transactionDaysProvider` produces,
/// deliberately — a drill-down that grouped differently from the ledger it drills into would read as
/// a different screen.
final drillDownDaysProvider = Provider.autoDispose
    .family<AsyncValue<List<DrillDownDayGroup>>, DrillDownSpec>((ref, spec) {
      return ref
          .watch(drillDownTransactionsProvider(spec))
          .whenData(_groupByDay);
    });

List<DrillDownDayGroup> _groupByDay(List<Transaction> rows) {
  final groups = <int, List<Transaction>>{};
  for (final row in rows) {
    groups.putIfAbsent(row.dateKey.value, () => <Transaction>[]).add(row);
  }
  final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final date in dates)
      DrillDownDayGroup(date: DateKey(date), transactions: groups[date]!),
  ];
}

/// What the drill-down totals to, **per currency**, so its header can be checked against the slice it
/// came from.
///
/// **Per currency and not one figure** (anomaly A34). These are `originalAmount`s, each in whatever
/// currency it was recorded in, and folding them into a single int would add rupees to yen — which is
/// the defect this project has a whole anomaly number for. Converting instead would need the rate table
/// and would still disagree with the slice above by whatever the slice excluded, so the honest answer is
/// one subtotal per currency, which for almost every household is one line.
final drillDownTotalsProvider = Provider.autoDispose
    .family<AsyncValue<Map<String, int>>, DrillDownSpec>((ref, spec) {
      return ref.watch(drillDownTransactionsProvider(spec)).whenData((rows) {
        final byCurrency = <String, int>{};
        for (final row in rows) {
          byCurrency.update(
            row.originalAmount.currencyCode,
            (minor) => minor + row.originalAmount.minor,
            ifAbsent: () => row.originalAmount.minor,
          );
        }
        return byCurrency;
      });
    });

/// The label for one drill-down, resolved from the id the route carried.
///
/// **Resolved rather than passed.** `go_router`'s `extra` does not survive a deep link or a process
/// death, so a label carried that way would render blank on the one path where the route is reached
/// from outside the app. Returns null for the kinds whose label is an ARB string rather than data —
/// `subtype` and `recurring` — which the screen localises itself (Law U5).
final drillDownLabelProvider = FutureProvider.autoDispose
    .family<String?, DrillDownSpec>((ref, spec) async {
      switch (spec.kind) {
        case DrillDownKind.subtype:
        case DrillDownKind.recurring:
          return null;
        case DrillDownKind.payee:
          final payee = await ref
              .watch(payeeRepositoryProvider)
              .byId(spec.value);
          return payee?.name;
        case DrillDownKind.item:
          final item = await ref.watch(itemRepositoryProvider).byId(spec.value);
          return item?.name;
        case DrillDownKind.paymentMethod:
          final method = await ref
              .watch(paymentMethodRepositoryProvider)
              .byId(spec.value);
          return method?.name;
      }
    });
```

### `lib/features/analytics/providers/split_analytics_providers.dart`

```dart
/// The split module's analytics surfaces (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

/// One counterparty's share of the shared spending in the window.
typedef SplitPartner = ({String payeeId, Money total, int expenseCount});

/// What a window of shared expenses cost, from both sides.
///
/// **Two lenses on the same rows, and the reason this module can offer them at all.** [outflow] is what
/// left the user's account — the full bill on every expense they paid. [myShare] is what they actually
/// consumed. Splitwise knows the second and nothing about a bank account; a bank app knows the first and
/// nothing about the split. Both come from one set of rows here, which no competitor can do.
///
/// [recovered] is what came back through settlements, so `outflow - myShare - recovered` is money still
/// out with somebody. That is the figure a person actually feels, and it is derived rather than stored
/// (Law L3).
typedef SplitLenses = ({
  Money outflow,
  Money myShare,
  Money recovered,
  int expenseCount,
  int skippedForeignCount,
});

/// The two lenses over the analytics window.
///
/// Watches `analyticsWindowProvider` like every other surface on that screen, so changing the range chip
/// recomputes this with the rest — a card resolving its own window is how two figures on one screen come
/// to describe different months.
final splitLensesProvider = FutureProvider<SplitLenses?>((ref) async {
  final window = ref.watch(analyticsWindowProvider);
  final self = await ref.watch(splitSelfProvider.future);
  // Null, not an empty result. With nobody claimed as the user there is no "my share" to compute, and a
  // card showing ₹0 would read as "you consumed nothing" rather than "the module is not set up".
  if (self == null) return null;

  final code = await ref.watch(analyticsCurrencyProvider.future);
  final ledger = ref.watch(splitLedgerRepositoryProvider);
  final expenses = await ledger
      .watchExpenses(from: window.from, to: window.to)
      .first;
  final settlements = await ledger
      .watchSettlements(from: window.from, to: window.to)
      .first;

  var outflow = Money.zero(code);
  var mine = Money.zero(code);
  var recovered = Money.zero(code);
  var counted = 0;
  var skipped = 0;

  for (final expense in expenses) {
    // **Foreign-currency rows are counted, not converted.** A travel split carries a frozen conversion
    // on the entity (Law L9), but `SplitExpenseSummary` reports the original — and adding a THB total to
    // a rupee one produces a figure nobody can reproduce, which anomaly A34 settled. The card shows the
    // skipped count rather than quietly answering a different question.
    if (expense.total.currencyCode != code) {
      skipped++;
      continue;
    }
    counted++;
    if (expense.wasPaidByYou) outflow += expense.total;
    final share = expense.myShare;
    if (share != null) mine += share;
  }

  for (final settlement in settlements) {
    if (settlement.amount.currencyCode != code) continue;
    // Money arriving, not money sent onward — the two directions answer different questions and summing
    // them would net a repayment against a debt paid.
    if (settlement.toPayeeId == self) recovered += settlement.amount;
  }

  return (
    outflow: outflow,
    myShare: mine,
    recovered: recovered,
    expenseCount: counted,
    skippedForeignCount: skipped,
  );
});

/// Who the user shares expenses with most, by that person's share of the bills in the window.
///
/// **Counts the other person's share, not the bill.** "You split with Ravi most" should mean Ravi is on
/// the most of your money — his share of what you paid — rather than the totals of dinners he happened
/// to attend.
///
/// Loads each expense's shares, which is a read per row and the reason this provider is not on the
/// dashboard. On an analytics screen the window is bounded and the section is lazy: `SliverList` does not
/// build a card until somebody scrolls to it, which is the same protection ARCH_4 R7 gives the other
/// twenty-two.
final splitPartnersProvider = FutureProvider<List<SplitPartner>>((ref) async {
  final window = ref.watch(analyticsWindowProvider);
  final self = await ref.watch(splitSelfProvider.future);
  if (self == null) return const [];

  final code = await ref.watch(analyticsCurrencyProvider.future);
  final ledger = ref.watch(splitLedgerRepositoryProvider);
  final summaries = await ledger
      .watchExpenses(from: window.from, to: window.to)
      .first;

  final totals = <String, ({int minor, int count})>{};
  for (final summary in summaries) {
    if (summary.total.currencyCode != code) continue;
    final expense = await ledger.expenseById(summary.splitExpenseId);
    if (expense == null) continue;
    for (final share in expense.shares) {
      if (share.payeeId == self) continue;
      final running = totals[share.payeeId] ?? (minor: 0, count: 0);
      totals[share.payeeId] = (
        minor: running.minor + share.amount.minor,
        count: running.count + 1,
      );
    }
  }

  return [
    for (final entry in totals.entries)
      (
        payeeId: entry.key,
        total: Money(entry.value.minor, code),
        expenseCount: entry.value.count,
      ),
  ]..sort((a, b) => b.total.minor.compareTo(a.total.minor));
});

/// Shared spending by occasion.
///
/// **The dimension no competitor has**, and it exists only because `split_expenses` carries `occasion`
/// and `place` as columns rather than folding them into a note. *"What did Diwali cost us"* and *"what do
/// we spend in Goa"* are questions a split app is uniquely placed to answer, and none of them do.
final splitOccasionProvider =
    FutureProvider<List<({String label, Money total})>>(
      (ref) => _byDimension(ref, (e) => e.occasion),
    );

/// The same, by place.
final splitPlaceProvider = FutureProvider<List<({String label, Money total})>>(
  (ref) => _byDimension(ref, (e) => e.place),
);

Future<List<({String label, Money total})>> _byDimension(
  Ref ref,
  String? Function(SplitExpenseSummary) pick,
) async {
  final window = ref.watch(analyticsWindowProvider);
  final code = await ref.watch(analyticsCurrencyProvider.future);
  final rows = await ref
      .watch(splitLedgerRepositoryProvider)
      .watchExpenses(from: window.from, to: window.to)
      .first;

  final totals = <String, int>{};
  for (final row in rows) {
    if (row.total.currencyCode != code) continue;
    final label = pick(row)?.trim();
    // A blank dimension is dropped rather than bucketed as "Other". Most expenses carry neither field,
    // so an "Other" slice would dominate every chart and say nothing at all.
    if (label == null || label.isEmpty) continue;
    totals[label] = (totals[label] ?? 0) + row.total.minor;
  }

  return [
    for (final entry in totals.entries)
      (label: entry.key, total: Money(entry.value, code)),
  ]..sort((a, b) => b.total.minor.compareTo(a.total.minor));
}
```

### `lib/features/analytics/state/analytics_range.dart`

```dart
import 'package:alaya/core/enums/date_range_preset.dart';

/// Which reporting window the analytics screen is showing, and how it is remembered.
///
/// Wraps `DateRangePreset` rather than declaring a second enum: `DateRangeService` already resolves
/// every preset, and a parallel enum would need a mapping that drifts. The preset itself is never
/// stored in the database — only as an `app_settings` string — so Law L13 does not reach it
/// (`date_range_preset.dart` says as much).
abstract final class AnalyticsRange {
  /// The `app_settings` key the chosen preset is stored under.
  static const String settingsKey = 'analytics.range';

  /// The default window: the current calendar month to date.
  ///
  /// A month is the unit a household budgets in, and it is the only preset that is both bounded and
  /// non-empty on the day the app is installed.
  static const DateRangePreset fallback = DateRangePreset.thisMonth;

  /// The presets the range row offers, in the order they appear.
  ///
  /// [DateRangePreset.today] is omitted: a one-day window makes every trend a single point, and the
  /// calendar already answers "what happened today" better than a chart can.
  /// [DateRangePreset.custom] is omitted because `DateRangeService.resolve` returns null for it by
  /// design — the caller supplies the dates — and 7B ships no date-range picker. Recorded as a
  /// deferral rather than silently absent.
  static const List<DateRangePreset> presets = [
    DateRangePreset.last7Days,
    DateRangePreset.last30Days,
    DateRangePreset.thisMonth,
    DateRangePreset.lastMonth,
    DateRangePreset.thisYear,
    DateRangePreset.allTime,
  ];

  /// Parses a stored value, falling back to [fallback] for anything this build cannot offer.
  ///
  /// Defaults rather than throws, for the same reason `SafeEnumConverter` does (Law L13): a settings
  /// row is user data, a later version may write a preset this one has never heard of, and that is
  /// not a reason to fail the analytics screen. A stored `custom` or `today` also lands here, which
  /// is why the check is against [presets] and not against `DateRangePreset.values`.
  static DateRangePreset parse(String? stored) {
    for (final preset in presets) {
      if (preset.name == stored) return preset;
    }
    return fallback;
  }

  /// The value written back to `app_settings`.
  static String stored(DateRangePreset preset) => preset.name;
}
```

### `lib/features/analytics/state/drill_down_spec.dart`

```dart
/// What an analytics drill-down filters the ledger by.
///
/// The **kind** is a closed set because each arm is a different query against
/// `TransactionRepository`, and the **value** is an id or an enum name that the view-model resolves
/// to a display label. Neither carries the window: ARCH_5 §5.7 keeps a selected range in the
/// view-model rather than in the route, so a drill-down inherits whatever the analytics screen is
/// showing and the URL stays the record's identity.
///
/// **There is deliberately no `tag` arm, and the cause is one missing read rather than a design
/// choice.** Every kind here is answerable from what `TransactionRepository` already exposes — four
/// from fields the `Transaction` entity carries, and `item` from `watchLinesForItem`. A tag is not:
/// the link lives in `transaction_tags`, `Transaction` carries no tag ids, and
/// `TagRepository.watchForTransaction` is per-transaction, so filtering a window by tag would be one
/// query per row. The same gap is why 6A's `TransactionFilter` has no tag axis either — this phase
/// inherits it rather than introducing it.
///
/// So the tag surface drills **within analytics**, parent tag to child tags, which is exactly what
/// ARCH_5 §7.2 assigns to this phase. Closing the ledger path needs
/// `TagRepository.watchTransactionIdsFor(tagId)` over `transaction_tags` — one DAO query, one
/// contract method, one impl — and is recorded in this phase's coverage table with its owner.
enum DrillDownKind {
  /// One `TransactionSubtype` — the closed structural flow type.
  subtype,

  /// One payment method, by id.
  paymentMethod,

  /// One payee, by id.
  payee,

  /// One item, by id — the transactions whose lines reference it.
  item,

  /// Whether spending settled a recurring template. The value is `recurring` or `discretionary`.
  recurring;

  /// Parses a path parameter, or null when it names no kind this build knows.
  ///
  /// Null rather than a fallback, because a drill-down route is deep-linkable and guessing at the
  /// kind would filter by the wrong axis while looking like it worked.
  static DrillDownKind? parse(String? raw) {
    for (final kind in DrillDownKind.values) {
      if (kind.name == raw) return kind;
    }
    return null;
  }
}

/// One drill-down: an axis and the value on it.
class DrillDownSpec {
  /// Creates a spec.
  const DrillDownSpec({required this.kind, required this.value});

  /// Parses a spec from its two path parameters, or null when either is unusable.
  static DrillDownSpec? parse({String? kind, String? value}) {
    final parsed = DrillDownKind.parse(kind);
    if (parsed == null || value == null || value.isEmpty) return null;
    return DrillDownSpec(kind: parsed, value: value);
  }

  /// Which axis is filtered.
  final DrillDownKind kind;

  /// The id or enum name filtered on.
  final String value;

  /// Value equality, so a Riverpod family keyed on this caches one provider per drill-down rather
  /// than rebuilding on every navigation.
  @override
  bool operator ==(Object other) =>
      other is DrillDownSpec && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => 'DrillDownSpec(${kind.name}, $value)';
}
```

### `test/features/analytics/analytics_home_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/presentation/screens/analytics_home_screen.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_header.dart';
import 'package:alaya/features/analytics/presentation/widgets/inflation_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';

import '../../support/analytics_harness.dart';

/// `AnalyticsHomeScreen` — archetype F, all four states (Law U4, ARCH_5 §9.1).
void main() {
  group('the four states', () {
    testWidgets('loading shows no figure and no error', (tester) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(
          headline: const AsyncValue<Concentration>.loading(),
          inflation: const AsyncValue<UnitPriceTrend?>.loading(),
        ),
      );

      // No `AmountText` at all: a pending read must not resolve to a zero, which would read as a real
      // figure of nothing spent.
      expect(find.byType(AmountText), findsNothing);
      expect(find.byType(EmptyState), findsNothing);
    });

    testWidgets('populated shows exactly one displayAmount', (tester) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(),
      );
      await tester.pumpAndSettle();

      // **One headline, and the test asserts the count rather than its presence.** Two `display`
      // amounts is no headline at all (ARCH_5 §3 archetype F), and it is the kind of regression a
      // "finds one widget" assertion would let through.
      final display = tester
          .widgetList<AmountText>(find.byType(AmountText))
          .where((widget) => widget.size == AmountSize.display);
      expect(display, hasLength(1));
    });

    testWidgets('empty replaces the spend sections and keeps the house', (
      tester,
    ) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(
          headline: AsyncValue.data(concentration(total: 0, top: 0)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsOneWidget);
      // The signature card is a spend surface and goes; the house section is a "right now" figure and
      // stays, which is the whole point of splitting them.
      expect(find.byType(InflationCard), findsNothing);
    });

    testWidgets('a failed headline costs the header and nothing else', (
      tester,
    ) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(
          headline: AsyncValue<Concentration>.error(
            Exception('rate table unreachable'),
            StackTrace.empty,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // **The repository's own message, not a generic body** (Law U9), and the screen survives: the
      // range row and the header are both still mounted. One failing card never blanks an overview.
      expect(find.textContaining('rate table unreachable'), findsOneWidget);
      expect(find.byType(AnalyticsHeader), findsOneWidget);
    });
  });

  group('the gate', () {
    testWidgets('renders at 320x640 with a doubled text scale', (tester) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(),
        textScale: 2,
      );
      await tester.pumpAndSettle();
      // No exception is the assertion (Law U15). An overflow throws in a test binding, so reaching
      // here at all is the pass.
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders at a tripled scale, past what U15 asks for', (
      tester,
    ) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(),
        textScale: 3,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('every target is large enough and named', (tester) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(),
      );
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    testWidgets('adds no chrome of its own; the shell owns it', (tester) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(),
      );
      await tester.pumpAndSettle();

      // Exactly one `Scaffold` — the harness's stand-in for `_ShellScaffold` — so the screen added
      // none, and **no `AppBar`**, because `Routes.insights` is a shell destination and a bar declared
      // here would be a second one inside the shell (Law U18).
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });
}
```

### `test/features/analytics/drill_down_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/features/analytics/presentation/screens/drill_down_screen.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';

import '../../support/analytics_harness.dart';

/// `DrillDownScreen` — archetype C, all four states (Law U4, ARCH_5 §9.1).
void main() {
  group('the four states', () {
    testWidgets('loading is a skeleton, not a spinner', (tester) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(
          drillRows: const AsyncValue<List<Transaction>>.loading(),
        ),
        wrapInShell: false,
      );

      // The shape of what is arriving, in a space that is about to be a list (ARCH_5 §5.2).
      expect(find.byType(AlayaListSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('populated groups rows under a sticky day header', (
      tester,
    ) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(),
        wrapInShell: false,
      );
      await tester.pumpAndSettle();

      expect(find.byType(TransactionRow), findsOneWidget);
      expect(find.byType(SliverPersistentHeader), findsOneWidget);
    });

    testWidgets('empty names the window rather than the filter', (
      tester,
    ) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(
          drillRows: const AsyncValue.data(<Transaction>[]),
        ),
        wrapInShell: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('error carries the repository message', (tester) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(
          drillRows: AsyncValue<List<Transaction>>.error(
            Exception('payee lookup failed'),
            StackTrace.empty,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      // **Not `errorBodyGeneric`** (Law U9): a list that fails identically for every cause is a
      // failure nobody can diagnose.
      expect(find.textContaining('payee lookup failed'), findsOneWidget);
    });
  });

  group('archetype C obligations', () {
    testWidgets('the active filter is visible and removable', (tester) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(),
        wrapInShell: false,
      );
      await tester.pumpAndSettle();

      // A filter the reader cannot see is a bug report waiting to happen (ARCH_5 §3 archetype C).
      expect(find.byType(FilterChipBar), findsOneWidget);
    });

    testWidgets('it owns its Scaffold and app bar, outside the shell', (
      tester,
    ) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(),
        wrapInShell: false,
      );
      await tester.pumpAndSettle();

      // The opposite assertion to the home screen's, and why every pump here passes
      // `wrapInShell: false`: this screen brings its own `Scaffold`. `AppBar` resolves `hasDrawer`
      // before `canPop`, so a drill-down inside the shell would show a hamburger where back belongs
      // (Law U18).
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(Drawer), findsNothing);
    });

    testWidgets('an unparseable route explains itself instead of throwing', (
      tester,
    ) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: null),
        overrides: analyticsOverrides(),
        wrapInShell: false,
      );
      await tester.pumpAndSettle();

      // This route is deep-linkable, so a malformed one is reachable from outside the app.
      expect(find.byType(EmptyState), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the gate', () {
    testWidgets('renders at 320x640 with a doubled text scale', (tester) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(),
        wrapInShell: false,
        textScale: 2,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('every target is large enough and named', (tester) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(),
        wrapInShell: false,
      );
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });
}
```

### `test/features/analytics/seed_test.dart`

```dart
// `show` clause per ARCH_1 §7.6, and for one symbol only: `driftRuntimeOptions`. A bare drift import
// beside `flutter_test` collides on `isNull`.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/seed/seed_data.dart';

void main() {
  // **Silences drift's multiple-database warning, which this file earns honestly.** Several tests here
  // open a second `AlayaDatabase` on purpose — the non-default-home-currency case and the determinism
  // case both need a fresh, independently seeded database to compare against. Drift cannot tell that
  // apart from the mistake it is warning about, which is two databases over *one* `QueryExecutor`; each
  // of these has its own `NativeDatabase.memory()`, so there is nothing to race.
  //
  // Set here rather than suppressed globally, so a genuine double-open elsewhere still reports.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AlayaDatabase db;

  setUp(() async {
    final seed = SeedData(
      uids: SequentialUidGenerator(prefix: 'seed'),
      clock: FixedClock(DateTime(2026, 7, 28, 9)),
    );
    db = AlayaDatabase(NativeDatabase.memory(), seeder: seed.insertAll);
    // Force onCreate to run.
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() => db.close());

  group('currencies', () {
    test('five currencies with the correct decimal digits', () async {
      final rows = await db.select(db.currencies).get();
      expect(rows.map((r) => r.code).toSet(), {
        'INR',
        'USD',
        'EUR',
        'JPY',
        'CNY',
      });

      final digits = {for (final r in rows) r.code: r.decimalDigits};
      expect(digits['INR'], 2);
      expect(digits['USD'], 2);
      expect(digits['EUR'], 2);
      expect(digits['CNY'], 2);
      expect(
        digits['JPY'],
        0,
        reason: 'yen has no minor unit — this is why nothing hardcodes 100',
      );
    });

    test('all seeded currencies are enabled', () async {
      final rows = await db.select(db.currencies).get();
      expect(rows.every((r) => r.isEnabled), isTrue);
    });
  });

  group('units', () {
    test('eleven units across the three fixed categories', () async {
      final rows = await db.select(db.units).get();
      expect(rows, hasLength(11));
      final byCategory = <UnitCategory, List<String>>{};
      for (final r in rows) {
        byCategory.putIfAbsent(r.category, () => []).add(r.code);
      }
      expect(byCategory[UnitCategory.weight]!.toSet(), {'mg', 'g', 'kg'});
      expect(byCategory[UnitCategory.volume]!.toSet(), {'ml', 'l', 'tsp', 'tbsp', 'cup'});
      expect(byCategory[UnitCategory.count]!.toSet(), {'pc', 'dozen', 'pack'});
    });

    test(
      'factors are exact integers relative to the milli-base unit',
      () async {
        final rows = await db.select(db.units).get();
        final factor = {for (final r in rows) r.code: r.factorToBaseMilli};
        expect(factor['mg'], 1);
        expect(factor['g'], 1000);
        expect(factor['kg'], 1000000);
        expect(factor['ml'], 1000);
        expect(factor['l'], 1000000);
        expect(factor['pc'], 1000);
        expect(factor['dozen'], 12000, reason: 'a dozen is exactly 12 pieces');
        expect(factor['pack'], 1000);
      expect(factor['tsp'], 4929);
      expect(factor['tbsp'], 14787);
      expect(factor['cup'], 240000);
      },
    );

    test('every unit is a system unit', () async {
      final rows = await db.select(db.units).get();
      expect(rows.every((r) => r.isSystem), isTrue);
    });
  });

  group('payment methods', () {
    test('the five rails from ARCH_2 §14', () async {
      final rows = await db.select(db.paymentMethods).get();
      expect(rows.map((r) => r.name).toSet(), {
        'Cash',
        'UPI',
        'Bank Transfer',
        'Card',
        'Cheque',
      });
      expect(rows.every((r) => r.isSystem), isTrue);
    });
  });

  group('tags — the exact ARCH_2 §14 scoping matrix', () {
    test('eighteen system tags', () async {
      final rows = await db.select(db.tags).get();
      expect(rows, hasLength(18));
      expect(rows.every((r) => r.isSystem), isTrue);
    });

    test('THE SPEC TEST CASE: Kitchen is inventory + shopping only', () async {
      final kitchen = await (db.select(
        db.tags,
      )..where((t) => t.name.equals('Kitchen'))).getSingle();

      expect(kitchen.allowedInInventory, isTrue);
      expect(kitchen.allowedInShopping, isTrue);

      expect(
        kitchen.allowedInDeposit,
        isFalse,
        reason:
            'Kitchen must NOT appear in the deposit tag picker — visible on first launch',
      );
      expect(kitchen.allowedInWithdrawal, isFalse);
      expect(kitchen.allowedInRecurring, isFalse);
      expect(kitchen.allowedInService, isFalse);
    });

    test('every row of the matrix, exactly', () async {
      // (name, deposit, withdrawal, inventory, shopping, recurring, service)
      const expected = <(String, bool, bool, bool, bool, bool, bool)>[
        ('Salary', true, false, false, false, true, false),
        ('Gift', true, true, false, false, false, false),
        ('Refund', true, false, false, false, false, false),
        ('Business', true, true, false, false, false, false),
        ('Grocery', false, true, true, true, false, false),
        ('Vegetables', false, true, true, true, false, false),
        ('Household', false, true, true, true, false, false),
        ('Kitchen', false, false, true, true, false, false),
        ('Beauty', false, true, true, true, false, false),
        ('Medicine', false, true, true, true, false, false),
        ('Electronics', false, true, true, true, false, true),
        ('Utilities', false, true, false, false, true, true),
        ('Rent', false, true, false, false, true, false),
        ('Subscription', false, true, false, false, true, true),
        ('Transport', false, true, false, false, true, false),
        ('Health', false, true, false, false, true, true),
        ('Education', false, true, false, false, true, false),
        ('Maintenance', false, true, false, false, true, true),
      ];

      final rows = await db.select(db.tags).get();
      final byName = {for (final r in rows) r.name: r};
      expect(byName.keys.toSet(), expected.map((e) => e.$1).toSet());

      for (final (name, dep, wdr, inv, shop, rec, svc) in expected) {
        final tag = byName[name]!;
        expect(
          [
            tag.allowedInDeposit,
            tag.allowedInWithdrawal,
            tag.allowedInInventory,
            tag.allowedInShopping,
            tag.allowedInRecurring,
            tag.allowedInService,
          ],
          [dep, wdr, inv, shop, rec, svc],
          reason: 'scoping mismatch for "$name"',
        );
      }
    });

    test('the deposit picker shows exactly four tags', () async {
      final rows = await (db.select(
        db.tags,
      )..where((t) => t.allowedInDeposit.equals(true))).get();
      expect(rows.map((r) => r.name).toSet(), {
        'Salary',
        'Gift',
        'Refund',
        'Business',
      });
    });

    test('Vegetables is nested exactly one level under Grocery', () async {
      final grocery = await (db.select(
        db.tags,
      )..where((t) => t.name.equals('Grocery'))).getSingle();
      final vegetables = await (db.select(
        db.tags,
      )..where((t) => t.name.equals('Vegetables'))).getSingle();

      expect(vegetables.parentTagId, grocery.id);
      expect(
        grocery.parentTagId,
        isNull,
        reason: 'nesting is capped at one level',
      );

      final nested = await (db.select(
        db.tags,
      )..where((t) => t.parentTagId.isNotNull())).get();
      expect(nested.map((r) => r.name), ['Vegetables']);
    });

    test('normalized names match what the Normalizer would produce', () async {
      final rows = await db.select(db.tags).get();
      for (final r in rows) {
        expect(r.normalizedName, r.name.toLowerCase());
      }
    });
  });

  group('accounts', () {
    test('Cash and Bank, zero opening balance, home currency', () async {
      final rows = await db.select(db.accounts).get();
      expect(rows.map((r) => r.name).toSet(), {'Cash', 'Bank'});
      for (final r in rows) {
        expect(r.openingBalanceMinor, 0);
        expect(r.currencyCode, 'INR');
        expect(r.isArchived, isFalse);
        expect(r.includeInNetWorth, isTrue);
      }
    });

    test(
      'the opening balance date is the seed date, not an absent value',
      () async {
        final rows = await db.select(db.accounts).get();
        for (final r in rows) {
          expect(r.openingBalanceDateKey.value, 20260728);
        }
      },
    );

    test('honours a non-default home currency', () async {
      final other = AlayaDatabase(
        NativeDatabase.memory(),
        seeder: SeedData(
          uids: SequentialUidGenerator(),
          clock: FixedClock(DateTime(2026, 7, 28)),
          homeCurrencyCode: 'JPY',
        ).insertAll,
      );
      addTearDown(other.close);
      final rows = await other.select(other.accounts).get();
      expect(rows.every((r) => r.currencyCode == 'JPY'), isTrue);
    });
  });

  group('shopping list', () {
    test('exactly one, marked default', () async {
      final rows = await db.select(db.shoppingLists).get();
      expect(rows, hasLength(1));
      expect(rows.single.isDefault, isTrue);
      expect(rows.single.isArchived, isFalse);
    });
  });

  group('app settings', () {
    test('homeCurrencyCode is stored', () async {
      final row = await (db.select(
        db.appSettings,
      )..where((t) => t.key.equals('homeCurrencyCode'))).getSingle();
      expect(row.value, 'INR');
      expect(row.valueType, 'string');
    });

    test('defaultAccountId points at a real account', () async {
      final setting = await (db.select(
        db.appSettings,
      )..where((t) => t.key.equals('defaultAccountId'))).getSingle();
      final account = await (db.select(
        db.accounts,
      )..where((t) => t.id.equals(setting.value))).getSingle();
      expect(
        account.name,
        'Cash',
        reason:
            'accounts has no isDefault column, so the default lives in app_settings',
      );
    });
  });

  group('determinism', () {
    test(
      'seeding twice with the same generator and clock produces identical ids',
      () async {
        Future<List<String>> seedIds() async {
          final fresh = AlayaDatabase(
            NativeDatabase.memory(),
            seeder: SeedData(
              uids: SequentialUidGenerator(prefix: 'seed'),
              clock: FixedClock(DateTime(2026, 7, 28, 9)),
            ).insertAll,
          );
          addTearDown(fresh.close);
          final tags = await fresh.select(fresh.tags).get();
          return tags.map((t) => t.id).toList();
        }

        expect(await seedIds(), await seedIds());
      },
    );
  });

  group('referential integrity', () {
    test('foreign keys are enforced after beforeOpen ran', () async {
      final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(
        row.data.values.first,
        1,
        reason:
            'SQLite defaults this OFF per connection — beforeOpen must turn it on',
      );
    });

    test('an account referencing an unknown currency is rejected', () async {
      expect(
        () => db.customStatement(
          'INSERT INTO accounts (id, name, normalized_name, kind, currency_code, '
          'opening_balance_minor, opening_balance_date_key, is_archived, include_in_net_worth, '
          "sort_order, created_at, updated_at) VALUES ('x','X','x','cash','ZZZ',0,20260728,0,1,0,0,0)",
        ),
        throwsA(anything),
      );
    });
  });
}
```
