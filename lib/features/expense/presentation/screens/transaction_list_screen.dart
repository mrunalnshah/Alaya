import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/features/expense/presentation/sheets/quick_add_sheet.dart';
import 'package:alaya/features/expense/presentation/widgets/needs_review_banner.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_filter_sheet.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/providers/transaction_search_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_search_field.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';

/// The transaction ledger (ARCH_5 §3 archetype C).
///
/// **Search and filter live in the body, not the app bar.** The drawer shell owns the `Scaffold` and
/// its `AppBar` for every top-level destination, so a destination cannot contribute app-bar actions —
/// and a nested `Scaffold` carrying a second app bar would be worse than none. Putting them in the
/// body also makes this screen and the catalogue archetype consistent, where ARCH_5 §3 archetype D
/// already says the search field is pinned rather than hidden behind a magnifying glass.
///
/// **No pull-to-refresh.** The data is local and streamed, so a refresh gesture cannot do anything;
/// offering one teaches the user the app is slow.
class TransactionListScreen extends ConsumerWidget {
  /// Creates the ledger.
  const TransactionListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final searching = ref.watch(isSearchingProvider);

    return Scaffold(
      // A nested Scaffold with no app bar: the shell above supplies the bar and the drawer, this one
      // supplies the FAB slot and a snack-bar host for the delete-and-undo flow.
      body: Column(
        children: [
          const _Toolbar(),
          if (!searching) ...[
            const _NeedsReviewRow(),
            const _ActiveFilters(),
          ],
          Expanded(
            child: searching ? const _SearchResults() : const _GroupedList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        // The sheet, not the editor. Capturing a purchase is the frequent act and wants five
        // controls; the eleven-control editor is where you go when five are not enough, reached
        // from the sheet's own "Add details".
        onPressed: () => QuickAddSheet.show(context),
        tooltip: strings.addExpense,
        child: const Icon(Icons.add, size: AlayaIconSize.lg),
      ),
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final narrowed = ref.watch(transactionFilterProvider).isNarrowed;
    final semantic = context.semantic;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
        AlayaSpacing.xs,
        AlayaSpacing.xxs,
      ),
      child: Row(
        children: [
          Expanded(
            child: AlayaSearchField(
              hintText: strings.searchTransactionsHint,
              clearLabel: strings.actionClearSearch,
              onChanged: ref.read(transactionSearchQueryProvider.notifier).set,
            ),
          ),
          IconButton(
            onPressed: () => TransactionFilterSheet.show(context),
            tooltip: strings.filterTitle,
            icon: Icon(
              narrowed ? Icons.filter_alt : Icons.filter_alt_outlined,
              size: AlayaIconSize.lg,
              color: narrowed ? semantic.transfer : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _NeedsReviewRow extends ConsumerWidget {
  const _NeedsReviewRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(transactionFilterProvider);
    // Hidden once the user has acted on it: a nudge that stays put while you are looking at exactly
    // what it pointed at reads as an instruction you have failed to follow.
    if (filter.needsReviewOnly) return const SizedBox.shrink();
    final count = ref.watch(needsReviewCountProvider).valueOrNull ?? 0;
    return NeedsReviewBanner(
      count: count,
      onTap: ref.read(transactionFilterProvider.notifier).showNeedsReviewOnly,
    );
  }
}

class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final filter = ref.watch(transactionFilterProvider);
    final notifier = ref.read(transactionFilterProvider.notifier);
    if (!filter.isNarrowed) return const SizedBox.shrink();

    final accounts =
        ref.watch(accountsByIdProvider).valueOrNull ??
        const <String, Account>{};
    final payees =
        ref.watch(payeesByIdProvider).valueOrNull ?? const <String, Payee>{};

    return FilterChipBar(
      clearAllLabel: strings.actionClearAll,
      onClearAll: notifier.clear,
      filters: [
        if (filter.needsReviewOnly)
          ActiveFilter(
            label: strings.statusNeedsReview,
            onRemove: notifier.clearNeedsReviewOnly,
          ),
        if (filter.preset != DateRangePreset.last30Days)
          ActiveFilter(
            label: TransactionFilterSheet.rangeLabel(strings, filter.preset),
            onRemove: () => notifier.setPreset(DateRangePreset.last30Days),
          ),
        for (final kind in filter.kinds)
          ActiveFilter(
            label: TransactionRow.kindLabel(strings, kind),
            onRemove: () => notifier.toggleKind(kind),
          ),
        for (final subtype in filter.subtypes)
          ActiveFilter(
            label: TransactionRow.subtypeLabel(strings, subtype),
            onRemove: () => notifier.toggleSubtype(subtype),
          ),
        if (filter.accountId != null)
          ActiveFilter(
            label: strings.filterChipAccount(
              accounts[filter.accountId]?.name ?? filter.accountId!,
            ),
            onRemove: () => notifier.setAccount(null),
          ),
        if (filter.payeeId != null)
          ActiveFilter(
            label: strings.filterChipPayee(
              payees[filter.payeeId]?.name ?? filter.payeeId!,
            ),
            onRemove: () => notifier.setPayee(null),
          ),
      ],
    );
  }
}

class _GroupedList extends ConsumerWidget {
  const _GroupedList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final days = ref.watch(transactionDaysProvider);

    return days.when(
      loading: () => AlayaListSkeleton(label: strings.loadingTransactions),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: strings.errorBodyGeneric,
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(filteredTransactionsProvider),
      ),
      data: (groups) {
        if (groups.isEmpty) {
          return EmptyState(
            title: strings.emptyTitleNoTransactions,
            body: strings.emptyBodyNoTransactions,
            icon: Icons.receipt_long_outlined,
            actionLabel: strings.addExpense,
            // **Deliberately still the full editor.** An empty ledger means somebody is setting up
            // rather than capturing at a till, and the full form is the better first experience. It
            // also keeps `Routes.transactionNew` reachable: a route nothing navigates to is the
            // failure this whole change is fixing, and swapping it for another instance of the same
            // mistake would be no improvement (ARCH_5 §9.2).
            onAction: () => context.push(Routes.transactionNew),
          );
        }
        final clock = ref.watch(clockProvider);
        final background = Theme.of(context).scaffoldBackgroundColor;
        return CustomScrollView(
          slivers: [
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
                  SliverList.builder(
                    itemCount: group.transactions.length,
                    itemBuilder: (context, index) =>
                        _Row(transaction: group.transactions[index]),
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

class _SearchResults extends ConsumerWidget {
  const _SearchResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final results = ref.watch(transactionSearchResultsProvider);

    return results.when(
      loading: () => AlayaListSkeleton(label: strings.loadingTransactions),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: strings.errorBodyGeneric,
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(transactionSearchResultsProvider),
      ),
      // Search results are ranked by relevance, so they are deliberately not grouped by day — a date
      // header over a relevance-ordered list asserts an order the list does not have.
      data: (rows) => rows.isEmpty
          ? EmptyState(
              title: strings.emptyTitleNoResults,
              body: strings.emptyBodyNoResults,
              icon: Icons.search_off_outlined,
            )
          : ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) => _Row(transaction: rows[index]),
            ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts =
        ref.watch(accountsByIdProvider).valueOrNull ??
        const <String, Account>{};
    final payees =
        ref.watch(payeesByIdProvider).valueOrNull ?? const <String, Payee>{};
    final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2;
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
  // legible when the text scale doubles, which a guessed 36 would not.
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
