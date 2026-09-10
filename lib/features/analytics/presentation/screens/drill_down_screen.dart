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
