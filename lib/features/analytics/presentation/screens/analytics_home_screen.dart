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
