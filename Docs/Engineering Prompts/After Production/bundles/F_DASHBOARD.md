# F_DASHBOARD

Funds header, module grid, insight cards.

**20 files · 3,050 lines.**  Written 2026-08-27T08:54:37-04:00.

Every file below is complete and current. Paths are destinations.

---

### `lib/features/dashboard/presentation/screens/dashboard_screen.dart`

```dart
import 'package:alaya/features/dashboard/presentation/widgets/split_balance_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/features/dashboard/presentation/widgets/dashboard_calendar.dart';
import 'package:alaya/features/dashboard/presentation/widgets/funds_header.dart';
import 'package:alaya/features/dashboard/presentation/widgets/insight_card.dart';
import 'package:alaya/features/dashboard/presentation/widgets/module_grid.dart';
import 'package:alaya/features/dashboard/presentation/widgets/range_row.dart';
import 'package:alaya/features/dashboard/providers/range_providers.dart';
import 'package:alaya/features/expense/presentation/sheets/quick_add_sheet.dart';
import 'package:alaya/features/expense/providers/quick_add_providers.dart';
import 'package:alaya/shared/widgets/alaya_expandable_fab.dart';

/// The dashboard (ARCH_5 §3 archetype F).
///
/// **One `displayAmount`, in the funds header.** Everything else on this screen is `small` or smaller, and
/// that hierarchy is the only reason a glance works — two headline numbers is no headline number.
///
/// **Four independent sections, four independent failures.** The header, each range row, the insight card
/// and the grid each render their own loading, empty and error state inline. A rate table that will not
/// load costs the header and the range rows their figures; it does not blank the dashboard, and it does
/// not stop the grid navigating.
///
/// **No scrim behind the FAB** — decided in this phase, recorded in the phase document's header. Its action
/// rows carry opaque surfaces of their own and `TapRegion` plus `PopScope` already dismiss it, so the
/// remaining argument for dimming was signalling modality that a three-item menu does not have.
class DashboardScreen extends ConsumerWidget {
  /// Creates the screen.
  const DashboardScreen({super.key});

  /// Opens the quick sheet, set to money in.
  ///
  /// **The sheet, not the full editor.** `QuickAddSheet` was built for exactly this — its own doc
  /// comment says "one-handed, in under eight seconds" — and until now nothing in the app opened it:
  /// every add action pushed the eleven-control editor instead. The elegant surface existed, was
  /// golden-tested, and was reachable only from tests (ARCH_5 §9.2, one level in).
  ///
  /// `setKind` rather than the draft channel. The draft exists to carry a *composed* transaction into
  /// the editor — a converted shopping list, a recurring occurrence — and a single enum is not that.
  /// One provider write either way, and this one does not leave a draft behind if the sheet is
  /// dismissed.
  void _addIncome(BuildContext context, WidgetRef ref) {
    ref.read(quickAddProvider.notifier).setKind(TransactionKind.deposit);
    QuickAddSheet.show(context);
  }

  /// Opens the quick sheet, set to money out.
  void _addExpense(BuildContext context, WidgetRef ref) {
    ref.read(quickAddProvider.notifier).setKind(TransactionKind.withdrawal);
    QuickAddSheet.show(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AlayaSpacing.screenEdge,
                AlayaSpacing.md,
                AlayaSpacing.screenEdge,
                AlayaSpacing.sm,
              ),
              child: const FundsHeader(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlayaSpacing.screenEdge,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Both windows are stated in words. A row reading "last month" would be ambiguous
                  // between thirty days and a calendar month, and the figures cannot disambiguate
                  // themselves (anomaly A33).
                  RangeRow(
                    label: strings.rangeLast30,
                    range: ref.watch(last30Provider),
                  ),
                  RangeRow(
                    label: strings.rangeAllTime,
                    range: ref.watch(allTimeProvider),
                  ),
                  const SizedBox(height: AlayaSpacing.sm),
                  // After the funds figures and before "Coming Up": the month's *shape* first, then the
                  // shortlist that says which of those days matters soonest.
                  const DashboardCalendar(),
                  const SizedBox(height: AlayaSpacing.sm),
                  const InsightCard(),
                  const SizedBox(height: AlayaSpacing.sm),
                  const SplitBalanceCard(),
                  Padding(
                    padding: const EdgeInsets.only(
                      top: AlayaSpacing.xl,
                      bottom: AlayaSpacing.xs,
                    ),
                    child: Text(
                      strings.moduleGridTitle,
                      style: AlayaTypography.sectionHeader.copyWith(
                        color: semantic.muted,
                      ),
                    ),
                  ),
                  const ModuleGrid(),
                  // Clears the FAB, which floats over the last row otherwise.
                  const SizedBox(height: AlayaSpacing.xxxl * 2),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: AlayaExpandableFab(
        openLabel: strings.fabOpenLabel,
        closeLabel: strings.fabCloseLabel,
        actions: [
          FabAction(
            label: strings.addExpense,
            icon: Icons.remove,
            onPressed: () => _addExpense(context, ref),
          ),
          FabAction(
            label: strings.fabAddIncome,
            icon: Icons.add,
            onPressed: () => _addIncome(context, ref),
          ),
          FabAction(
            label: strings.fabAddItem,
            icon: Icons.inventory_2_outlined,
            onPressed: () => context.push(Routes.itemNew),
          ),
        ],
      ),
    );
  }
}
```

### `lib/features/dashboard/presentation/widgets/dashboard_calendar.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';
import 'package:alaya/features/calendar/presentation/widgets/calendar_month_grid.dart';
import 'package:alaya/features/calendar/presentation/widgets/day_sheet.dart';
import 'package:alaya/features/calendar/providers/calendar_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';

/// This month at a glance. Each day opens its entries in a sheet — where the day is big enough to hit.
///
/// **The interaction is measured, not assumed.** Seven columns need 336dp to give every day the 48dp
/// tap-target floor, and this card's inner width is the screen minus 64dp of padding. So a 320dp phone
/// yields 36.6dp per day and a 412dp phone yields 49.7dp: the same widget is compliant on one and not on
/// the other. Rather than ship undersized targets everywhere or drop the feature everywhere, the grid
/// asks its own constraints:
///
/// * **48dp or more per cell** — every day is tappable and opens `DaySheet`.
/// * **less than that** — the days go inert (`IgnorePointer` removes the gestures, `ExcludeSemantics` the
///   undersized nodes) and the whole card becomes one large target that opens the calendar screen, which
///   has the room to do this properly.
///
/// That is why the dashboard's `androidTapTargetGuideline` test passes at 320dp with no exclusion: at
/// that width there are genuinely no small targets, rather than small targets the test agreed to ignore.
/// Suppressing the check would have hidden a real defect on exactly the phones least able to afford it.
///
/// `DaySheet` is the same sheet the calendar's deep link opens, so a day reads identically wherever it is
/// reached from. Ranges and month paging stay on the full screen.
///
/// Dots only in the grid itself: "Coming Up" sits directly below this card, and repeating the same events
/// as cards would say the same thing twice in one scroll. What the grid adds is shape — which days have
/// something on them — which no list conveys.
class DashboardCalendar extends ConsumerWidget {
  /// Creates the section.
  const DashboardCalendar({super.key});

  /// The Android tap-target floor, below which a day cell stops accepting taps.
  static const double _tapTargetFloor = 48;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    // `currentMonthProvider`, never `focusedMonthProvider`: this grid must not follow wherever the
    // calendar screen was last left, or returning from December would show December here.
    final month = ref.watch(currentMonthProvider);
    final today = ref.watch(calendarTodayProvider);
    final index = ref.watch(calendarDayIndexProvider(month));
    final label = DateFormat.yMMMM(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(month.toUtcMidnight());

    return LayoutBuilder(
      builder: (context, constraints) {
        // The width the grid will actually hand each of its seven columns.
        final cellWidth =
            (constraints.maxWidth - 2 * AlayaSpacing.md) / DateTime.daysPerWeek;
        final tappable = cellWidth >= _tapTargetFloor;

        final grid = CalendarMonthGrid(
          month: month,
          today: today,
          daysByKey: index.valueOrNull ?? const <int, CalendarDay>{},
          selected: today,
          onDaySelected: (day) => DaySheet.show(context: context, dateKey: day),
          // A long-press starts a range on the full screen; here there is nowhere to show one, so it
          // opens the same sheet. One gesture, one outcome, no hidden mode.
          onDayLongPressed: (day) =>
              DaySheet.show(context: context, dateKey: day),
          // Nothing to change to: the grid is bounded to this month and its gestures are off.
          onMonthChanged: (_) {},
          lockedToMonth: true,
        );

        final card = AlayaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                label,
                style: AlayaTypography.cardTitle.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AlayaSpacing.xs),
              if (tappable)
                grid
              else
                IgnorePointer(child: ExcludeSemantics(child: grid)),
              // Full width and free to wrap. Beside the month title this button wanted 435dp of the 256
              // available at a doubled text scale — the 179dp of overflow the dashboard's layout test
              // reported (Law U21).
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => context.push(Routes.calendar),
                  icon: const Icon(Icons.open_in_new, size: AlayaIconSize.sm),
                  label: Text(strings.dashboardOpenCalendar),
                ),
              ),
            ],
          ),
        );

        // Narrow: the card itself is the target, so the month is still one tap from being explored.
        if (tappable) return card;
        return Semantics(
          container: true,
          button: true,
          label: strings.dashboardCalendarSemantics(label),
          child: InkWell(
            onTap: () => context.push(Routes.calendar),
            child: card,
          ),
        );
      },
    );
  }
}
```

### `lib/features/dashboard/presentation/widgets/funds_breakdown_sheet.dart`

```dart
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
```

### `lib/features/dashboard/presentation/widgets/funds_header.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_durations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/dashboard/presentation/widgets/funds_breakdown_sheet.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Total available funds — the one `displayAmount` on the dashboard (ARCH_5 §3 archetype F).
///
/// **One headline, because two headline numbers is no headline number.** Every other figure on this
/// screen is `AmountSize.small` or smaller, and that hierarchy is the whole reason a glance works.
///
/// **The figure comes from `BalanceService.totalInHome` and nothing else.** A self-transfer cannot move
/// it: the balances behind it come from `v_account_ledger`, which counts a transfer once against each
/// side. If this number ever changes when money moves between the user's own accounts, the view is being
/// bypassed rather than the arithmetic being wrong.
///
/// **What cannot be converted is excluded and said out loud** (anomaly A34). Summing a dirham balance
/// into a rupee total at face value would be a wrong number presented as a right one; a smaller number
/// with a chip beside it is honest, and the chip explains itself rather than just counting.
class FundsHeader extends ConsumerWidget {
  /// Creates the header.
  const FundsHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final async = ref.watch(totalFundsProvider);
    final digits = ref.watch(dashboardDigitsProvider).valueOrNull ?? 2;

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.md),
      // **Tappable only once there is a figure to explain.** Offering the breakdown while the rate table
      // is still loading would open a sheet showing nothing, and offering it on an error would explain a
      // number that is not there.
      onTap: async.hasValue ? () => FundsBreakdownSheet.show(context) : null,
      child: async.when(
        // Its own skeleton rather than the screen's: a slow rate table must not blank the range rows or
        // the module grid beneath it (ARCH_5 §3 archetype F).
        loading: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.fundsAvailable,
              style: AlayaTypography.label.copyWith(color: semantic.muted),
            ),
            const SizedBox(height: AlayaSpacing.xs),
            Text(
              strings.loadingDashboard,
              style: AlayaTypography.body.copyWith(color: semantic.muted),
            ),
          ],
        ),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(totalFundsProvider),
        ),
        data: (worth) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.fundsAvailable,
              style: AlayaTypography.label.copyWith(color: semantic.muted),
            ),
            const SizedBox(height: AlayaSpacing.xs),
            // **ARCH_5 §2.6's fourth animation, and the only place it belongs.** A total that recalculates
            // should show *that* it changed — otherwise a figure quietly becoming a different figure is
            // indistinguishable from one that was always that. This is the app's headline number and the only
            // one that moves on its own, when a transaction lands or a rate is fetched.
            //
            // Keyed on the amount, so an identical recomputation does not blink. `AlayaDurations.base`, per the
            // token §2.6 names. Under reduced motion the duration collapses to zero, which is a **skip** rather
            // than a shortening: the new value simply replaces the old with no cross-fade at all.
            AnimatedSwitcher(
              duration: MediaQuery.maybeDisableAnimationsOf(context) ?? false
                  ? Duration.zero
                  : AlayaDurations.base,
              child: AmountText(
                worth.total,
                key: ValueKey<int>(worth.total.minor),
                // The one `displayAmount` on the screen (ARCH_5 §2.3). Omitting this fell back to
                // `AmountSize.medium` — the ledger-row size — which left the dashboard with no headline
                // at all while every doc comment claimed it had one.
                size: AmountSize.display,
                showSign: false,
                decimalDigits: digits,
              ),
            ),
            if (!worth.isComplete || worth.isApproximate) ...[
              const SizedBox(height: AlayaSpacing.sm),
              Wrap(
                spacing: AlayaSpacing.xs,
                runSpacing: AlayaSpacing.xxs,
                children: [
                  if (!worth.isComplete)
                    StatusChip(
                      label: strings.fundsUnconverted(worth.unconvertedCount),
                      tone: StatusTone.warning,
                    ),
                  if (worth.isApproximate)
                    StatusChip(
                      label: strings.fundsApproximate,
                      tone: StatusTone.info,
                    ),
                ],
              ),
              if (!worth.isComplete) ...[
                const SizedBox(height: AlayaSpacing.xs),
                Text(
                  strings.fundsWhyExcluded,
                  style: AlayaTypography.caption.copyWith(
                    color: semantic.muted,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
```

### `lib/features/dashboard/presentation/widgets/insight_card.dart`

```dart
import 'package:alaya/core/time/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/dashboard/state/insight_side.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// A switchable card: what is coming up, or where the money went.
///
/// **Each side owns its own loading, empty and error state, inline.** That is the whole reason this is one
/// card with a switch rather than two cards: a failing rate table or an unreachable engine must cost the
/// user this card and nothing else. One failing card never blanks the dashboard (ARCH_5 §3 archetype F).
///
/// **The spending side has no data, and says so rather than pretending.** `AnalyticsService` has no
/// `AnalyticsPort` adapter and `CalendarAggregator` has no `CalendarRepository`, both assigned to Phase 7B
/// and 7A (ARCH_4 §5.1 item 15). Aggregating spending here instead would leave 7B a competing
/// implementation to reconcile, so the side is built, switchable and honest — and 7B supplies data to a
/// card that already exists.
///
/// The choice is stored in `app_settings`, so it survives a restart.
class InsightCard extends ConsumerWidget {
  /// Creates the card.
  const InsightCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final side = ref.watch(insightSideProvider);
    final notifier = ref.read(insightSideProvider.notifier);

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: strings.insightSwitchLabel,
            child: SegmentedButton<InsightSide>(
              segments: [
                ButtonSegment(
                  value: InsightSide.upcoming,
                  label: Text(strings.insightUpcoming),
                ),
                ButtonSegment(
                  value: InsightSide.spending,
                  label: Text(strings.insightSpending),
                ),
              ],
              selected: {side},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => notifier.show(selection.first),
            ),
          ),
          const SizedBox(height: AlayaSpacing.md),
          switch (side) {
            InsightSide.upcoming => const _Upcoming(),
            InsightSide.spending => const _Spending(),
          },
        ],
      ),
    );
  }
}

class _Upcoming extends ConsumerWidget {
  const _Upcoming();

  static IconData _glyph(UpcomingKind kind) => switch (kind) {
    UpcomingKind.bill => Icons.event_repeat,
    UpcomingKind.service => Icons.build_outlined,
    UpcomingKind.warranty => Icons.verified_outlined,
    UpcomingKind.batch => Icons.inventory_2_outlined,
  };

  static String _label(AlayaStrings strings, UpcomingKind kind) =>
      switch (kind) {
        UpcomingKind.bill => strings.insightBillDue,
        UpcomingKind.service => strings.insightServiceDue,
        UpcomingKind.warranty => strings.insightWarrantyEnding,
        UpcomingKind.batch => strings.insightBatchExpiring,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final async = ref.watch(upcomingProvider);
    final today = ref.watch(clockProvider).today();

    return async.when(
      loading: () => Text(
        strings.loadingDashboard,
        style: AlayaTypography.caption.copyWith(color: semantic.muted),
      ),
      error: (error, stack) => Text(
        error.toString(),
        style: AlayaTypography.caption.copyWith(color: semantic.danger),
      ),
      data: (entries) => entries.isEmpty
          ? Text(
              strings.insightNothingUpcoming,
              style: AlayaTypography.body.copyWith(color: semantic.muted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Capped, not scrolled: a card inside a `CustomScrollView` that scrolls on its own is two
                // scroll gestures competing for the same drag. Five is a shortlist; the modules behind it
                // hold the rest.
                for (final entry in entries.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AlayaSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _glyph(entry.kind),
                          size: AlayaIconSize.md,
                          color: entry.isOverdue(today)
                              ? semantic.danger
                              : semantic.muted,
                        ),
                        const SizedBox(width: AlayaSpacing.sm),
                        Expanded(
                          // The title, its sort and its date all grow with text scale, so they wrap
                          // among themselves rather than starving the icon's neighbour (Law U21).
                          child: Wrap(
                            spacing: AlayaSpacing.xs,
                            runSpacing: AlayaSpacing.xxs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                entry.title,
                                style: AlayaTypography.body.copyWith(
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                _label(strings, entry.kind),
                                style: AlayaTypography.caption.copyWith(
                                  color: semantic.muted,
                                ),
                              ),
                              DateText(
                                entry.dueDateKey,
                                style: DateTextStyle.dayMonth,
                                muted: true,
                              ),
                              if (entry.isOverdue(today))
                                StatusChip(
                                  label: strings.recurringOverdue,
                                  tone: StatusTone.danger,
                                ),
                            ],
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

/// The spending side, reading the analytics engine Phase 7B wired.
///
/// **This replaced the "waiting on the analytics module" state 6F shipped.** That state was correct
/// while `AnalyticsService` had no adapter; aggregating spending here instead would have left 7B a
/// competing implementation to reconcile (ARCH_4 P7). The row it closed is ARCH_5 §7's, assigned to 7B.
///
/// A shortlist and not a chart: the card is one of four things on a dashboard, and the analytics screen
/// is one tap away for anyone who wants the breakdown.
class _Spending extends ConsumerWidget {
  const _Spending();

  /// How many kinds the card names before it stops. `Concentration.top` is already the top three.
  static const int _maxRows = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final async = ref.watch(spendingInsightProvider);
    final digits = ref.watch(dashboardDigitsProvider).valueOrNull ?? 2;

    return async.when(
      loading: () => Text(
        strings.chartLoading,
        style: AlayaTypography.body.copyWith(color: semantic.muted),
      ),
      // The repository's own message, never a generic body (Law U9).
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: error.toString(),
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(spendingInsightProvider),
      ),
      data: (concentration) {
        if (concentration.top.isEmpty) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.insights_outlined,
                size: AlayaIconSize.md,
                color: semantic.muted,
              ),
              const SizedBox(width: AlayaSpacing.sm),
              Expanded(
                child: Text(
                  strings.analyticsNothingSpent,
                  style: AlayaTypography.body.copyWith(color: semantic.muted),
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // **The window is labelled** (anomaly A33). "Spending" alone does not say over what, and no
            // figure on the card can disambiguate itself.
            Text(
              strings.rangeLast30Days,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            const SizedBox(height: AlayaSpacing.xxs),
            AmountText(
              concentration.total,
              size: AmountSize.medium,
              showSign: false,
              decimalDigits: digits,
            ),
            const SizedBox(height: AlayaSpacing.sm),
            for (final slice in concentration.top.take(_maxRows))
              KeyValueRow(
                // `slice.key` through the ARB, never `slice.label`: the adapter grouped by the enum
                // name, so the label is `grocery` (Law U5).
                label: AnalyticsLabels.subtype(strings, slice.key),
                valueWidget: AmountText(
                  slice.amount,
                  size: AmountSize.small,
                  showSign: false,
                  decimalDigits: digits,
                ),
              ),
          ],
        );
      },
    );
  }
}
```

### `lib/features/dashboard/presentation/widgets/module_grid.dart`

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/dashboard/providers/module_providers.dart';
import 'package:alaya/shared/widgets/module_tile.dart';

/// Navigation tiles, each carrying a live number (ARCH_5 §3 archetype F).
///
/// **Every tile's number is real, and a zero is worded rather than shown.** "0 running low" is a figure
/// the reader has to interpret; "nothing tracked" is an answer. The ARB holds both wordings and picks by
/// count, which is why `ModuleTile` takes text rather than an `int`.
///
/// A count still arriving shows the module's name and no number rather than a spinner: the tile's job is
/// navigation, and it can do that job before its count lands.
///
/// ## The cell height is measured, not a ratio
///
/// `childAspectRatio` ties a cell's height to its *width*, and width does not move when the user doubles
/// their text size. So the box stayed put while both labels inside it grew, and every dashboard test
/// overflowed — by 22px at scale 1 and 250px at scale 2 (Law U15, and the reason U15 asks for a test
/// rather than an opinion).
///
/// `mainAxisExtent` computed from `MediaQuery.textScalerOf` grows with the text instead. The grid gets
/// taller and the dashboard scrolls, which is the right outcome: archetype F requires the screen to
/// *survive* 320dp at scale 2, not to fit on it.
///
/// ## `push`, not `go` — a tile is a drill-down
///
/// Tapping a tile is a "go into this" gesture, so it should come back. `go` made the module a peer of the
/// dashboard and left the drawer as the only way home: two taps, and no back affordance at all. `push`
/// slides the module over the dashboard and `_ShellScaffold` now shows a back arrow when it can pop, so
/// the way out is the arrow, the OS gesture, or the drawer — three, rather than one.
///
/// The drawer still `go`es, which is correct: choosing Expenses from a list of nine destinations *is* a
/// peer switch, and it should not accumulate a stack.
///
/// `push` also keeps the dashboard live underneath. Six of its providers are `autoDispose`, so leaving the
/// location tears their subscriptions down and returning refetches — a visible loading flash on a screen
/// the user was just looking at. Pushed, the dashboard stays mounted, its drift streams keep emitting, and
/// a transaction added on the pushed screen has already landed in the figures before the pop finishes.
///
/// The budget below is what one tile actually needs — its glyph, its two spacers, both labels at
/// `ModuleTile.maxLabelLines`, and the tile's own padding — floored at two tap targets so a tile is never
/// smaller than something you can hit (U3).
class ModuleGrid extends ConsumerWidget {
  /// Creates the grid.
  const ModuleGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    final expenses = ref.watch(expenseCountProvider).valueOrNull;
    final inventory = ref.watch(inventoryCountProvider);
    final shopping = ref.watch(shoppingCountProvider).valueOrNull;
    final recipes = ref.watch(recipeCountProvider);
    final recurring = ref.watch(recurringCountProvider).valueOrNull;
    final services = ref.watch(serviceCountProvider);
    final split = ref.watch(splitCountProvider);

    // A count worth acting on is coloured; a settled one is not. Colour is the only thing distinguishing
    // "two bills due" from "two bills paid", and the wording carries the rest.
    Color? toneFor(int? count) =>
        count != null && count > 0 ? semantic.warning : null;

    final scaler = MediaQuery.textScalerOf(context);

    // The height one label occupies at its full line budget, at the scale in force right now.
    double labelBudget(TextStyle style) =>
        scaler.scale(style.fontSize!) *
        style.height! *
        ModuleTile.maxLabelLines;

    final tileExtent = math
        .max(
          AlayaSpacing.minTapTarget * 2,
          AlayaIconSize.lg +
              AlayaSpacing.xs +
              labelBudget(AlayaTypography.body) +
              AlayaSpacing.xxs +
              labelBudget(AlayaTypography.caption) +
              AlayaSpacing.sm * 2,
        )
        .toDouble();

    return GridView(
      shrinkWrap: true,
      // The dashboard owns the scroll (Law U13): a grid that scrolls inside a `CustomScrollView` is two
      // gestures fighting over one drag. `shrinkWrap` and `NeverScrollableScrollPhysics` travel together
      // — one without the other is the defect (ARCH_6 P2).
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AlayaSpacing.sm,
        crossAxisSpacing: AlayaSpacing.sm,
        mainAxisExtent: tileExtent,
      ),
      children: [
        ModuleTile(
          label: strings.navExpenses,
          icon: Icons.receipt_long_outlined,
          detail: expenses == null ? '' : strings.moduleExpenses(expenses),
          onTap: () => context.push(Routes.expenses),
        ),
        ModuleTile(
          label: strings.navInventory,
          icon: Icons.inventory_2_outlined,
          detail: strings.moduleInventory(inventory),
          tone: toneFor(inventory),
          onTap: () => context.push(Routes.inventory),
        ),
        ModuleTile(
          label: strings.navRecipes,
          icon: Icons.restaurant_menu_outlined,
          // A count still arriving shows the name and no number, like every other tile — the tile's job
          // is navigation and it can do that before its count lands.
          detail: recipes == null ? '' : strings.moduleRecipes(recipes),
          onTap: () => context.push(Routes.recipes),
        ),
        ModuleTile(
          label: strings.navSplit,
          icon: Icons.call_split_outlined,
          detail: split == null ? '' : strings.moduleSplit(split),
          // Coloured like the others when there is something outstanding. An open debt is a thing to act
          // on in the same way a bill due is — and unlike stock running low, it involves somebody else
          // waiting.
          tone: toneFor(split),
          onTap: () => context.push(Routes.split),
        ),
        ModuleTile(
          label: strings.navShopping,
          icon: Icons.shopping_basket_outlined,
          detail: shopping == null ? '' : strings.moduleShopping(shopping),
          tone: toneFor(shopping),
          onTap: () => context.push(Routes.shopping),
        ),
        ModuleTile(
          label: strings.navRecurring,
          icon: Icons.event_repeat,
          detail: recurring == null ? '' : strings.moduleRecurring(recurring),
          tone: toneFor(recurring),
          onTap: () => context.push(Routes.recurring),
        ),
        ModuleTile(
          label: strings.navServices,
          icon: Icons.handyman_outlined,
          detail: strings.moduleServices(services),
          tone: toneFor(services),
          onTap: () => context.push(Routes.services),
        ),
      ],
    );
  }
}
```

### `lib/features/dashboard/presentation/widgets/range_row.dart`

```dart
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
```

### `lib/features/dashboard/presentation/widgets/split_balance_card.dart`

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
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// What is owed to you and by you, on the dashboard (ARCH_5 §3 archetype F).
///
/// ## Deliberately not part of the funds header
///
/// **The first decision this module recorded is that owed money is not spendable until it arrives.** A
/// receivable folded into "total available funds" would say the user can spend ₹4,000 that is sitting in
/// somebody else's bank account — and once a figure has been added to a total, nothing on screen can
/// unsay it. This card sits below the funds header with its own heading for exactly that reason, and the
/// caption states it rather than leaving it to be inferred.
///
/// ## Two figures, never one
///
/// *"You are owed ₹4,000 and you owe ₹3,900"* is a different story from *"you are up ₹100"*, and the net
/// version is the first step toward treating a receivable as an asset. Both directions are shown even
/// when one is zero, so the layout does not shift as debts appear and clear.
///
/// Hidden entirely when nothing is outstanding: a dashboard is a summary of what needs attention, and a
/// card reading "₹0 and ₹0" is a row of nothing occupying the space a real figure would use. That is the
/// same reasoning `InsightCard` applies to an empty span.
class SplitBalanceCard extends ConsumerWidget {
  /// Creates the card.
  const SplitBalanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final totals = ref.watch(splitTotalsProvider).valueOrNull;
    final ageing = ref.watch(splitAgeingProvider).valueOrNull ?? const [];

    // Still loading, or nothing outstanding. Both render nothing rather than a placeholder: a card that
    // appears empty and then fills is a layout jump on the screen a user looks at most often.
    if (totals == null || totals.isEmpty) return const SizedBox.shrink();

    // The oldest debt across every currency, which is the one worth naming. Ageing is per counterparty,
    // so this is a person rather than an amount — and the sentence is the point.
    final oldest = ageing.isEmpty ? null : ageing.first;

    return AlayaCard(
      onTap: () => context.push(Routes.split),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.call_split_outlined,
                size: AlayaIconSize.md,
                color: semantic.muted,
              ),
              const SizedBox(width: AlayaSpacing.xs),
              Expanded(
                child: Text(
                  strings.splitCardTitle,
                  style: AlayaTypography.bodyEmphasis,
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: AlayaIconSize.md,
                color: semantic.muted,
              ),
            ],
          ),

          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            // **The sentence that keeps the figure honest.** Without it a number on the dashboard reads as
            // money the user has, which is precisely the reading decision 1 exists to prevent.
            strings.splitCardNotSpendable,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),

          const SizedBox(height: AlayaSpacing.sm),
          for (final entry in totals.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: _Side(
                      label: strings.splitOwedToYou,
                      amount: entry.value.owedToMe,
                    ),
                  ),
                  Expanded(
                    child: _Side(
                      label: strings.splitYouOwe,
                      amount: entry.value.iOwe,
                    ),
                  ),
                ],
              ),
            ),

          if (oldest != null)
            Align(
              alignment: Alignment.centerLeft,
              child: StatusChip(
                // The nudge no competitor sends, on the screen people actually open. It needs no due
                // date — `v_split_balances` already carries the oldest contributing expense, and the day
                // count is computed against the injected clock because a view may not read the time.
                label: strings.splitCardOldest(oldest.ageInDays),
                tone: StatusTone.warning,
              ),
            ),
        ],
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.label, required this.amount});

  final String label;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        // Through `AmountText`, and without a colour: that widget has no `tone` parameter and colours
        // from `kind` deliberately. The label above already says which figure this is, and a sentence
        // survives a screenshot where a hue does not.
        AmountText(amount, showSign: false),
      ],
    );
  }
}
```

### `lib/features/dashboard/providers/funds_providers.dart`

```dart
/// View-model state for the funds header (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/account_balance.dart';
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/domain/services/balance_service.dart';

/// The home currency every figure on the dashboard is expressed in.
final dashboardCurrencyProvider = FutureProvider<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      'INR',
);

/// The home currency's decimal precision (ARCH_1 §4.1).
final dashboardDigitsProvider = FutureProvider<int>((ref) async {
  final code = await ref.watch(dashboardCurrencyProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// Every account, so a balance can be paired with its net-worth flag.
final dashboardAccountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchAllIncludingArchived(),
);

/// Per-account balances, straight from `v_account_ledger`.
final dashboardBalancesProvider = StreamProvider<List<AccountBalance>>(
  (ref) => ref.watch(accountRepositoryProvider).watchBalances(),
);

/// Total available funds — the one headline figure on the dashboard.
///
/// **`BalanceService.totalInHome` and nothing else.** `AccountRepository.watchTotalInHomeCurrency` was a
/// second answer to the same question and is dropped by this phase (ARCH_4 §5.1 item 13); two sources is
/// how a dashboard starts disagreeing with itself.
///
/// **A self-transfer nets to zero here by construction.** The balances come from `v_account_ledger`,
/// which counts a transfer once against each side — so moving money between your own accounts leaves the
/// sum untouched. If this figure ever moves on a transfer, the view is being bypassed, not the maths.
///
/// **Unconvertible balances are excluded, never guessed at** (anomaly A34). `NetWorth` carries the count
/// so the header can say so rather than quietly under-reporting.
final totalFundsProvider = FutureProvider<NetWorth>((ref) async {
  final accounts = await ref.watch(dashboardAccountsProvider.future);
  final balances = await ref.watch(dashboardBalancesProvider.future);
  final code = await ref.watch(dashboardCurrencyProvider.future);

  final flags = <String, bool>{
    for (final account in accounts) account.id: account.includeInNetWorth,
  };
  return ref
      .watch(balanceServiceProvider)
      .totalInHome(
        balances: [
          for (final balance in balances)
            AccountBalanceInput(
              accountId: balance.accountId,
              balance: balance.balance,
              // An account excluded from net worth is excluded here too. A loan you are servicing is
              // real money owed and belongs in the ledger, but it is not money you can spend today.
              includeInNetWorth: flags[balance.accountId] ?? true,
            ),
        ],
        rates: ref.watch(currencyRateServiceProvider),
        homeCurrencyCode: code,
        asOf: ref.watch(clockProvider).today(),
      );
});

/// One account, as the breakdown shows it.
///
/// Carries the converted figure **and** the original, because a total that was converted cannot be
/// explained by a list of raw balances — they would not add up to the number the user tapped. Showing
/// both is what `BalanceService.convertOne` was built for; its doc comment says so, and until now
/// nothing called it.
class FundsRow {
  /// Creates a row.
  const FundsRow({
    required this.account,
    required this.original,
    required this.converted,
    required this.quality,
    required this.countsToward,
  });

  /// The account.
  final Account account;

  /// Its balance in its own currency.
  final Money original;

  /// The same balance in the home currency, or null when no rate could be found.
  ///
  /// **Null is displayed as null, never as zero** (anomaly A34). An account whose currency has no rate is
  /// excluded from the headline figure, and the row says so rather than contributing a silent nothing.
  final Money? converted;

  /// How trustworthy the conversion is.
  final RateQuality quality;

  /// Whether this account is part of the headline total.
  ///
  /// False for anything flagged out of net worth — a loan is real money owed but not money you can spend
  /// today. The row still appears, greyed, because a breakdown that omits accounts is a breakdown nobody
  /// can reconcile against their own bank.
  final bool countsToward;
}

/// Every account with its balance, for the sheet behind the headline figure.
///
/// **Composed from the providers the header already uses**, so the sheet and the total cannot disagree.
/// A second query for the same numbers is how a dashboard starts contradicting itself — the same reason
/// `watchTotalInHomeCurrency` was dropped in Phase 4 (ARCH_4 §5.1 item 13).
///
/// Sorted by converted magnitude, largest first: somebody opening this wants to know where the money is,
/// and alphabetical ordering answers a question nobody asked.
final fundsBreakdownProvider = FutureProvider<List<FundsRow>>((ref) async {
  final accounts = await ref.watch(dashboardAccountsProvider.future);
  final balances = await ref.watch(dashboardBalancesProvider.future);
  final code = await ref.watch(dashboardCurrencyProvider.future);
  final table = await ref.watch(currencyRateServiceProvider).table();
  final service = ref.watch(balanceServiceProvider);
  final asOf = ref.watch(clockProvider).today();

  final byId = {for (final account in accounts) account.id: account};
  final rows = <FundsRow>[];
  for (final balance in balances) {
    final account = byId[balance.accountId];
    if (account == null) continue;
    final result = service.convertOne(
      balance: balance.balance,
      table: table,
      homeCurrencyCode: code,
      asOf: asOf,
    );
    rows.add(
      FundsRow(
        account: account,
        original: balance.balance,
        converted: result.converted,
        quality: result.quality,
        countsToward: account.includeInNetWorth,
      ),
    );
  }
  rows.sort((a, b) {
    // The field is `minor`. I used a longer name from memory that has never existed — `Money`'s own doc
    // comment states it, and reading the declaration would have cost ten seconds against two rounds.
    final left = a.converted?.minor ?? 0;
    final right = b.converted?.minor ?? 0;
    return right.compareTo(left);
  });
  return rows;
});
```

### `lib/features/dashboard/providers/insight_providers.dart`

```dart
import 'dart:async';
import 'package:alaya/core/time/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/calendar/providers/calendar_providers.dart';
import 'package:alaya/features/dashboard/providers/range_providers.dart';
import 'package:alaya/features/dashboard/state/insight_side.dart';

/// One thing that needs attention, and when.
class UpcomingEntry {
  /// Creates an entry.
  const UpcomingEntry({
    required this.kind,
    required this.title,
    required this.dueDateKey,
    this.route,
  });

  /// Which sort of obligation this is, which decides its wording and glyph.
  final UpcomingKind kind;

  /// What it is called.
  final String title;

  /// When it falls due.
  final DateKey dueDateKey;

  /// Where tapping it goes, when there is somewhere useful.
  final String? route;

  /// Whether it is already past its date, derived from the clock and never stored (ARCH_2 §12.2).
  bool isOverdue(DateKey today) => dueDateKey < today;
}

/// The four sorts of thing the upcoming side collects.
enum UpcomingKind {
  /// A recurring occurrence that is due.
  bill,

  /// An asset whose service interval has come round.
  service,

  /// A warranty about to lapse.
  warranty,

  /// A batch at or near its expiry date.
  batch,
}

/// How far ahead the upcoming side looks.
///
/// A fortnight: long enough that a monthly bill appears before it is late, short enough that the card
/// stays a shortlist rather than a second ledger.
const int upcomingHorizonDays = 14;

/// Spend by kind over the dashboard's own thirty-day window — the insight card's spending side.
///
/// **Added in Phase 7B, which closed the gap this side was built around.** 6F shipped it as an inline
/// empty state naming what it waited for, because `AnalyticsService` had no `AnalyticsPort` adapter and
/// aggregating spending in the dashboard would have left 7B a competing implementation to reconcile
/// (ARCH_4 P7, ARCH_5 §7). The adapter now exists, so the side reads the engine.
///
/// **Its own window, not the analytics screen's.** `last30Provider` is fixed; `analyticsWindowProvider`
/// follows a chip the user last touched on another screen. Sharing it would make the dashboard change
/// when nothing on the dashboard was touched.
final spendingInsightProvider = FutureProvider<Concentration>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.categoryConcentration(ref.watch(last30Provider));
});

/// Which face of the insight card is showing, restored from `app_settings`.
final insightSideProvider = NotifierProvider<InsightSideNotifier, InsightSide>(
  InsightSideNotifier.new,
);

/// Holds and persists the insight card's side.
class InsightSideNotifier extends Notifier<InsightSide> {
  @override
  InsightSide build() {
    unawaited(_restore());
    return InsightSide.upcoming;
  }

  Future<void> _restore() async {
    final stored = await ref
        .read(settingsRepositoryProvider)
        .readValue(InsightSide.settingsKey);
    final restored = InsightSide.parse(stored);
    if (restored != state) state = restored;
  }

  /// Shows [side] and remembers it.
  ///
  /// The write is not awaited: the card should flip on the frame the user taps, and a settings row that
  /// lands a millisecond later changes nothing they can see.
  void show(InsightSide side) {
    state = side;
    unawaited(
      ref
          .read(settingsRepositoryProvider)
          .writeValue(
            key: InsightSide.settingsKey,
            value: side.stored,
            // `app_settings` stores its own type alongside the value, and every row this app writes is a
            // string. An enum's name is a string; declaring it anything else would be a claim the reader
            // has to unpick.
            valueType: 'string',
          ),
    );
  }
}

/// Everything falling due inside [upcomingHorizonDays], soonest first.
///
/// **Now `CalendarAggregator`, which is what the previous version said it could not be.** It read four
/// repositories directly because `CalendarRepository` had no implementation until Phase 7A
/// (ARCH_4 §5.1 item 15); it does now, so the stand-in retires rather than drifting alongside the real
/// engine. Three things were wrong with it, and none were visible from here:
///
/// 1. Its own doc comment claimed five reads including `ServiceRecordRepository.watchWithNextDueInRange`.
///    The body performed four and never called it, so a service due recorded against a **service record**
///    rather than against the asset never reached this card (ARCH_6 P18 — a comment asserting what the
///    code does not do).
/// 2. Batches were titled `batch.id`, so an expiring item showed a **UUID** where the calendar, whose
///    view `COALESCE`s the item name, showed "Yoghurt".
/// 3. Severity was nobody's job here. `CalendarAggregator` applies ARCH_3 §6's per-type thresholds
///    against the injected clock, so "needs attention" now means the same thing on both screens.
///
/// **Transactions and shopping targets are filtered out, deliberately.** Every kind this card carries is
/// consequential if ignored: a bill goes late, a service lapses, a warranty dies, food spoils. A past
/// transaction is not an obligation, and a shopping target is self-imposed — missing it costs nothing,
/// and a weekly shop would land in almost every fortnight, so it would be the one row always present and
/// therefore the one carrying no signal. The calendar is where plans belong; this card is for obligations.
final upcomingProvider = FutureProvider.autoDispose<List<UpcomingEntry>>((
  ref,
) async {
  // The same materialisation the calendar waits on. Without it this card cannot show a bill that is
  // not already overdue, which was true of the version it replaced too.
  await ref.watch(recurringHorizonProvider.future);

  final today = ref.watch(clockProvider).today();
  final horizon = today.addDays(upcomingHorizonDays);

  // A year back, not `DateRangeFloor.past`. Overdue still matters more than upcoming, but a floor in
  // 1900 makes the range nominally bounded and practically a full scan of seven tables — and nothing
  // outstanding for over a year is going to be actioned from a fortnight's shortlist.
  final days = await ref
      .watch(calendarAggregatorProvider)
      .watchDays(
        from: today.addDays(-overdueLookbackDays),
        to: horizon,
        today: today,
      )
      .first;

  final entries = <UpcomingEntry>[];
  for (final day in days) {
    for (final event in day.events) {
      final kind = _kindOf(event.type);
      if (kind == null) continue;
      entries.add(
        UpcomingEntry(
          kind: kind,
          title: event.title,
          dueDateKey: event.dateKey,
        ),
      );
    }
  }

  entries.sort((a, b) => a.dueDateKey.compareTo(b.dueDateKey));
  return entries;
});

/// The [UpcomingKind] for [type], or null where the type is not an obligation.
UpcomingKind? _kindOf(CalendarEventType type) => switch (type) {
  CalendarEventType.recurringDue => UpcomingKind.bill,
  CalendarEventType.serviceDue => UpcomingKind.service,
  CalendarEventType.warrantyEnd => UpcomingKind.warranty,
  CalendarEventType.batchExpiry => UpcomingKind.batch,
  CalendarEventType.transaction => null,
  CalendarEventType.shoppingTarget => null,
  // **Null, like the two above, and it is a decision rather than an oversight.** A settle-by date is a
  // real obligation, so the tempting move is a fifth `UpcomingKind` — but that enum is rendered by its
  // own label and icon switches, so one member here cascades into three more files for a card the split
  // module is getting anyway. Its own dashboard card, showing net owed and the oldest unsettled debt,
  // says more than one row on a list of bills would.
  CalendarEventType.splitSettleBy => null,
};

/// How far back the card reaches for things still outstanding.
const int overdueLookbackDays = 365;

/// The lower bound for a read that should include things already overdue.
///
/// Overdue matters more than upcoming, so the floor reaches back rather than starting at today — a
/// service three weeks late must not fall off the card for being too late.
abstract final class DateRangeFloor {
  /// Far enough back to catch anything still outstanding.
  static final DateKey past = DateKey.fromYmd(1900, 1, 1);
}
```

### `lib/features/dashboard/providers/module_providers.dart`

```dart
/// The live numbers on the dashboard's navigation tiles (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/inventory/providers/inventory_list_providers.dart';
import 'package:alaya/features/recipe/providers/recipe_list_providers.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

/// How many transactions were recorded this calendar month.
///
/// The month rather than a rolling window, because the tile's wording says "this month" and a tile whose
/// number does not match its label is worse than no number (anomaly A33).
final expenseCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final today = ref.watch(clockProvider).today();
  final month = ref.watch(dateRangeServiceProvider).wholeMonthOf(today);
  final rows = await ref
      .watch(transactionRepositoryProvider)
      .watchByDateRange(from: month.from, to: month.to)
      .first;
  return rows.length;
});

/// How many items sit below their low-stock level.
///
/// **Phase 6B's provider, not a second one.** `lowStockCountProvider` already answers exactly this and is
/// derived from the same stream the inventory list watches — a dashboard-local reimplementation would be a
/// second definition of "low" to keep in step (ARCH_4 P7).
final inventoryCountProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(lowStockCountProvider),
);

/// How many recipes can be cooked right now.
///
/// **Phase R3a's provider, not a second one.** `cookableCountProvider` is derived from the same single
/// pass the recipe catalogue makes, so the tile and the list can never disagree about what "cookable"
/// means — the same argument `inventoryCountProvider` makes about "low" (ARCH_4 P7).
///
/// Counts only `ready`. A recipe the engine could not judge is not one the tile can promise.
final recipeCountProvider = Provider.autoDispose<int?>(
  (ref) => ref.watch(cookableCountProvider),
);

/// How many people have something outstanding with you, either way.
///
/// **Counterparties, not amounts**, because a tile holds one small number and "3 people" is a thing a
/// person can act on where "₹4,150" invites the question of which direction it runs. The card below the
/// grid carries the two figures; this only says how many conversations are open.
///
/// **Not `SplitBalanceService.totals`, and not a second definition of "outstanding".**
/// `splitBalancesProvider` already drops anyone who nets to zero, so this counts exactly what the split
/// screen lists — the same argument `inventoryCountProvider` and `recipeCountProvider` both make about
/// reusing their module's own provider rather than re-deriving (ARCH_4 P7).
final splitCountProvider = Provider.autoDispose<int?>(
  (ref) => ref.watch(splitBalancesProvider).valueOrNull?.length,
);

/// How many things are still to buy on the default list.
final shoppingCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final repository = ref.watch(shoppingRepositoryProvider);
  final list = await repository.watchDefaultList().first;
  if (list == null) return 0;
  final entries = await repository.watchUncheckedEntries(list.id).first;
  final today = ref.watch(clockProvider).today();
  // The entity decides what counts: a snoozed suggestion and a bought entry are both unchecked and
  // neither is something to buy (see `ShoppingEntry.isOutstandingAsOf`).
  return entries.where((entry) => entry.isOutstandingAsOf(today)).length;
});

/// How many recurring obligations are outstanding.
final recurringCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final due = await ref.watch(recurringRepositoryProvider).watchDue().first;
  return due.where((row) => row.occurrence != null).length;
});

/// How many assets need a service or are losing their warranty.
///
/// Reuses the dashboard's own upcoming list rather than re-querying, so the tile and the insight card can
/// never disagree about what needs attention.
final serviceCountProvider = Provider.autoDispose<int>((ref) {
  final upcoming =
      ref.watch(upcomingProvider).valueOrNull ?? const <UpcomingEntry>[];
  return upcoming
      .where(
        (entry) =>
            entry.kind == UpcomingKind.service ||
            entry.kind == UpcomingKind.warranty,
      )
      .length;
});
```

### `lib/features/dashboard/providers/range_providers.dart`

```dart
/// View-model state for the dashboard's range rows (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/date_range_service.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';

/// Money in and money out over one labelled window, with what could not be converted.
class RangeTotals {
  /// Creates a set of totals.
  const RangeTotals({
    required this.moneyIn,
    required this.moneyOut,
    required this.excludedCount,
  });

  /// Deposits, converted into the home currency.
  final Money moneyIn;

  /// Withdrawals, converted into the home currency.
  final Money moneyOut;

  /// How many transactions held a currency no rate could convert.
  ///
  /// Excluded from both figures rather than summed at face value (anomaly A34), and surfaced so the row
  /// can say the total is partial instead of quietly under-reporting.
  final int excludedCount;

  /// Whether the window held nothing at all, which reads differently from holding zero.
  bool get isEmpty => moneyIn.isZero && moneyOut.isZero && excludedCount == 0;
}

/// The last thirty days, ending today.
///
/// **Always labelled with what it means** (anomaly A33). A row reading "last month" is ambiguous between
/// the previous calendar month and the preceding thirty days, and a user cannot tell which they are
/// looking at from the number alone — so the label states the window and the code computes exactly that.
final last30Provider = Provider<DateRange>((ref) {
  final today = ref.watch(clockProvider).today();
  return (from: today.addDays(-29), to: today);
});

/// Everything on record, from the earliest date this app treats as real.
final allTimeProvider = Provider<DateRange>((ref) {
  return (
    from: DateRangeService.earliest,
    to: ref.watch(clockProvider).today(),
  );
});

/// Totals over one window.
///
/// Converted through `RateTable` once for the whole window rather than per transaction, because
/// `CurrencyRateService.toHome` reloads the table on every call and a year of transactions would reload it
/// a thousand times.
final rangeTotalsProvider = FutureProvider.autoDispose.family<RangeTotals, DateRange>((
  ref,
  range,
) async {
  final code = await ref.watch(dashboardCurrencyProvider.future);
  final rows = await ref
      .watch(transactionRepositoryProvider)
      .watchByDateRange(from: range.from, to: range.to)
      .first;
  final table = await ref.watch(currencyRateServiceProvider).table();

  var moneyIn = Money.zero(code);
  var moneyOut = Money.zero(code);
  var excluded = 0;
  for (final transaction in rows) {
    // **Transfers and adjustments are neither in nor out.** A transfer moves money between the user's own
    // accounts, so counting it as both would double every figure and net to a lie. An adjustment is a
    // bookkeeping correction — presenting one as income would tell the user they earned their own
    // reconciliation. The rows are labelled "In" and "Out" and must contain only what those words mean
    // (anomaly A33).
    if (transaction.kind == TransactionKind.transfer ||
        transaction.kind == TransactionKind.adjustmentIncrease ||
        transaction.kind == TransactionKind.adjustmentDecrease) {
      continue;
    }

    final converted = table.convert(
      amount: transaction.originalAmount,
      toCurrencyCode: code,
      on: transaction.dateKey,
    );
    final value = converted.converted;
    if (value == null) {
      excluded++;
      continue;
    }
    switch (transaction.kind) {
      case TransactionKind.deposit:
        moneyIn = moneyIn + value;
      case TransactionKind.withdrawal:
        moneyOut = moneyOut + value;
      case TransactionKind.transfer:
      case TransactionKind.adjustmentIncrease:
      case TransactionKind.adjustmentDecrease:
        break;
    }
  }
  return RangeTotals(
    moneyIn: moneyIn,
    moneyOut: moneyOut,
    excludedCount: excluded,
  );
});
```

### `lib/features/dashboard/state/insight_side.dart`

```dart
/// Which face of the dashboard's insight card is showing.
///
/// Stored in `app_settings` through `SettingsRepository.writeValue`, so the choice survives a restart —
/// a switch that resets every launch is a switch the user has to keep re-making.
enum InsightSide {
  /// Bills, services, warranties and batches falling due soon.
  upcoming,

  /// Spending breakdowns. Waiting on Phase 7B's analytics adapter.
  spending;

  /// The `app_settings` key this preference is stored under.
  static const String settingsKey = 'dashboard.insightSide';

  /// Parses a stored value, defaulting to [upcoming] for anything unrecognised.
  ///
  /// Defaults rather than throws: a settings row is user data and a future version may write a value this
  /// one has never heard of, which is not a reason to fail a dashboard.
  static InsightSide parse(String? stored) => switch (stored) {
    'spending' => InsightSide.spending,
    _ => InsightSide.upcoming,
  };

  /// The value written back to `app_settings`.
  String get stored => name;
}
```

### `test/features/dashboard/dashboard_calendar_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/calendar/presentation/widgets/calendar_month_grid.dart';
import 'package:alaya/features/calendar/presentation/widgets/day_sheet.dart';
import 'package:alaya/features/dashboard/presentation/widgets/dashboard_calendar.dart';

import '../../support/calendar_harness.dart';

/// The dashboard's month card, whose three behaviours are all invisible until they are wrong.
///
/// It changed shape three times in three rounds with nothing pinning it, which is what these are for: a
/// width gate that silently disables an interaction, a lock that silently permits paging, and a sheet
/// that silently never opens are each the kind of fault a screenshot cannot show.
void main() {
  /// Pumps the card at [width] logical pixels, which is the only input the width gate reads.
  ///
  /// Through `pumpCalendar`'s own `size`, not by setting `physicalSize` first — the harness sets it after
  /// this function would have, so anything set beforehand is silently discarded.
  Future<void> pumpAt(WidgetTester tester, double width) async {
    await pumpCalendar(
      tester,
      const DashboardCalendar(),
      overrides: calendarOverrides(FakeCalendarRepository(events: [event()])),
      size: Size(width, 800),
    );
    await tester.pumpAndSettle();
  }

  /// Whether the grid is currently wrapped in something that swallows its gestures.
  ///
  /// Presence of an `IgnorePointer` says nothing: the framework wraps this subtree in two of its own on
  /// every screen (`ignoring: false`), so `findsOneWidget` counted three at 320dp and two at 412dp. The
  /// property is the contract, not the type — so this asks whether any ancestor is actually ignoring.
  bool gridIsInert(WidgetTester tester) => tester
      .widgetList<IgnorePointer>(
        find.ancestor(
          of: find.byType(CalendarMonthGrid),
          matching: find.byType(IgnorePointer),
        ),
      )
      .any((widget) => widget.ignoring);

  group('DashboardCalendar', () {
    testWidgets('the grid is there whatever the width', (tester) async {
      await pumpAt(tester, 412);
      expect(find.byType(CalendarMonthGrid), findsOneWidget);
    });

    // 412dp leaves (412 - 64) / 7 = 49.7dp per cell, over the 48dp floor, so days accept taps.
    testWidgets('a wide screen opens the day in a sheet', (tester) async {
      await pumpAt(tester, 412);

      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();

      expect(find.byType(DaySheet), findsOneWidget);
    });

    // 320dp leaves 36.6dp per cell. Rather than ship targets nobody can hit, the days go inert and the
    // card itself becomes the way in.
    //
    // Asserted structurally rather than by tapping. A tap here does not land on nothing — it falls
    // through the inert grid to the card's own `InkWell`, which calls `context.push`, and this harness has
    // no `GoRouter`. That the tap reaches the card is the fallback working, so the useful assertion is
    // whether the grid's gestures are being swallowed, not what a tap happens to trigger.
    testWidgets('a narrow screen makes the days inert', (tester) async {
      await pumpAt(tester, 320);

      expect(gridIsInert(tester), isTrue);
      expect(find.byType(DaySheet), findsNothing);
    });

    testWidgets('a wide screen leaves the days live', (tester) async {
      await pumpAt(tester, 412);

      expect(gridIsInert(tester), isFalse);
    });

    // `availableGestures: none` alone would not do it: `firstDay`/`lastDay` spanning years leave the
    // underlying `PageView` with neighbouring pages that a fling can still reach. The bounds are the lock.
    testWidgets('the month cannot be paged away from', (tester) async {
      await pumpAt(tester, 412);
      expect(find.text('August 2026'), findsOneWidget);

      await tester.fling(
        find.byType(CalendarMonthGrid),
        const Offset(-300, 0),
        1000,
      );
      await tester.pumpAndSettle();

      expect(find.text('August 2026'), findsOneWidget);
      expect(find.text('September 2026'), findsNothing);
    });
  });
}
```

### `test/features/dashboard/dashboard_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:alaya/features/dashboard/presentation/widgets/funds_header.dart';
import 'package:alaya/features/dashboard/presentation/widgets/insight_card.dart';
import 'package:alaya/features/dashboard/presentation/widgets/module_grid.dart';
import 'package:alaya/features/dashboard/presentation/widgets/range_row.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/expense/presentation/sheets/quick_add_sheet.dart';
import 'package:alaya/shared/widgets/alaya_expandable_fab.dart';
import 'package:alaya/shared/widgets/amount_text.dart';

import '../../support/dashboard_harness.dart';

/// The §9.1 gate for the dashboard, plus the two invariants archetype F exists to protect.
void main() {
  testWidgets('loading: every section says so on its own', (tester) async {
    await pumpDashboard(
      tester,
      const DashboardScreen(),
      overrides: dashboardOverrides(
        funds: const AsyncValue.loading(),
        last30: const AsyncValue.loading(),
        allTime: const AsyncValue.loading(),
        upcomingEntries: const AsyncValue.loading(),
      ),
    );
    await tester.pump();
    // Four sections still present while none of them has a figure — the screen is a frame, not a spinner.
    expect(find.byType(FundsHeader), findsOneWidget);
    expect(find.byType(RangeRow, skipOffstage: false), findsNWidgets(2));
    expect(find.byType(InsightCard, skipOffstage: false), findsOneWidget);
    expect(find.byType(ModuleGrid, skipOffstage: false), findsOneWidget);
  });

  testWidgets('empty: a household with no data still gets a usable screen', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      const DashboardScreen(),
      overrides: dashboardOverrides(
        funds: AsyncValue.data(netWorth(minor: 0)),
        last30: AsyncValue.data(totals(inMinor: 0, outMinor: 0)),
        allTime: AsyncValue.data(totals(inMinor: 0, outMinor: 0)),
      ),
    );
    await tester.pumpAndSettle();
    // There is no whole-screen empty state, deliberately: every section has its own, and a first-run
    // dashboard should still show a user where everything is.
    expect(find.text('Nothing yet'), findsWidgets);
    expect(find.byType(ModuleGrid, skipOffstage: false), findsOneWidget);
  });

  testWidgets('error: one failing section never blanks the others', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      const DashboardScreen(),
      overrides: dashboardOverrides(
        funds: AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    await tester.pumpAndSettle();
    // The whole point of archetype F's inline states: a broken rate table costs the headline and nothing
    // else. The grid must still navigate.
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.byType(ModuleGrid, skipOffstage: false), findsOneWidget);
    expect(find.byType(RangeRow, skipOffstage: false), findsNWidgets(2));
  });

  testWidgets('populated: exactly one headline figure on the whole screen', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      const DashboardScreen(),
      overrides: dashboardOverrides(
        upcomingEntries: AsyncValue.data([upcoming()]),
        inventory: 3,
      ),
    );
    await tester.pumpAndSettle();
    final display = tester
        .widgetList<AmountText>(find.byType(AmountText, skipOffstage: false))
        .where((a) => a.size == AmountSize.display)
        .length;
    // Two headline numbers is no headline number (ARCH_5 §3 archetype F). Every other figure is small.
    expect(display, 1);
  });

  testWidgets('both range windows are named, and named differently', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      const DashboardScreen(),
      overrides: dashboardOverrides(),
    );
    await tester.pumpAndSettle();
    // Anomaly A33: never an unlabelled window, and never two rows a user cannot tell apart.
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text('All time'), findsOneWidget);
  });

  testWidgets('the FAB offers three ways in and nothing else', (tester) async {
    await pumpDashboard(
      tester,
      const DashboardScreen(),
      overrides: dashboardOverrides(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaExpandableFab), findsOneWidget);
    await tester.tap(find.byTooltip('Add something'));
    await tester.pumpAndSettle();
    expect(find.text('Add expense'), findsOneWidget);
    expect(find.text('Add income'), findsOneWidget);
    expect(find.text('New item'), findsOneWidget);
  });

  testWidgets('adding an expense opens the quick sheet, not the full editor', (
    tester,
  ) async {
    // Law U16. `QuickAddSheet` was built for this — five controls, one-handed — and for three phases
    // nothing in the app opened it: every add action pushed the eleven-control editor instead, so the
    // quick surface existed, passed its golden test, and was reachable only from tests.
    //
    // Asserted on what appears rather than on a route, because the failure was never a broken route.
    // It was a working route to the wrong screen.
    await pumpDashboard(
      tester,
      const DashboardScreen(),
      overrides: dashboardOverrides(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add something'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();

    expect(find.byType(QuickAddSheet), findsOneWidget);
    // The full editor's own heading must not be here. If it is, the FAB is pushing the editor again.
    expect(find.text('What and how much'), findsNothing);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpDashboard(
      tester,
      const DashboardScreen(),
      overrides: dashboardOverrides(
        funds: AsyncValue.data(netWorth(unconverted: 2, approximate: true)),
        last30: AsyncValue.data(totals(excluded: 4)),
        upcomingEntries: AsyncValue.data([
          upcoming(title: 'A bill with a name long enough to wrap twice over'),
          upcoming(kind: UpcomingKind.batch, on: const DateKey(20260710)),
        ]),
        inventory: 12,
        services: 9,
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpDashboard(
      tester,
      const DashboardScreen(),
      overrides: dashboardOverrides(
        upcomingEntries: AsyncValue.data([upcoming()]),
        inventory: 2,
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/dashboard/funds_header_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/features/dashboard/presentation/widgets/funds_header.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/dashboard_harness.dart';

/// The one headline figure, and the two things it must never do quietly.
void main() {
  Widget host() => const Scaffold(body: FundsHeader());

  testWidgets('loading says so without a spinner', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(funds: const AsyncValue.loading()),
    );
    expect(find.text('Adding it up'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('error shows the real reason with a retry', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        funds: AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('a complete total is the only figure, and carries no chips', (
    tester,
  ) async {
    await pumpDashboard(tester, host(), overrides: dashboardOverrides());
    await tester.pumpAndSettle();
    expect(find.text('Total available funds'), findsOneWidget);
    // Exactly one AmountText, and it is the display size — archetype F allows one headline.
    expect(find.byType(AmountText), findsOneWidget);
    expect(
      tester.widget<AmountText>(find.byType(AmountText)).size,
      AmountSize.display,
    );
    // Nothing to warn about, so nothing is said.
    expect(find.textContaining('not converted'), findsNothing);
    expect(find.text('Rate is older than today'), findsNothing);
  });

  testWidgets('a zero total is still a total, not an empty state', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(funds: AsyncValue.data(netWorth(minor: 0))),
    );
    await tester.pumpAndSettle();
    // Nought available funds is a fact about the accounts, not an absence of data — showing an empty
    // state here would imply Alaya had failed to look.
    expect(find.byType(AmountText), findsOneWidget);
    expect(find.text('Total available funds'), findsOneWidget);
  });

  testWidgets('unconvertible balances are counted out loud, never summed', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        funds: AsyncValue.data(netWorth(unconverted: 2)),
      ),
    );
    await tester.pumpAndSettle();
    // Anomaly A34: a dirham balance folded into a rupee total at face value would be a wrong number
    // presented as a right one. A smaller number plus a chip is honest — and the chip explains itself
    // rather than only counting.
    expect(find.text('2 balances not converted'), findsOneWidget);
    expect(
      find.textContaining('left out rather than guessed at'),
      findsOneWidget,
    );
  });

  testWidgets('a stale rate is disclosed separately from an exclusion', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        funds: AsyncValue.data(netWorth(approximate: true)),
      ),
    );
    await tester.pumpAndSettle();
    // Converted with yesterday's rate is a different claim from not converted at all, so it gets its own
    // chip and no exclusion note.
    expect(find.text('Rate is older than today'), findsOneWidget);
    expect(find.textContaining('not converted'), findsNothing);
    expect(
      find.textContaining('left out rather than guessed at'),
      findsNothing,
    );
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        funds: AsyncValue.data(netWorth(unconverted: 3, approximate: true)),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpDashboard(tester, host(), overrides: dashboardOverrides());
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('the total is tappable and explains itself', (tester) async {
    // The headline figure answered "how much" and nothing answered "from where". `BalanceService.convertOne`
    // was built for exactly this — its doc comment says "for a per-account row that shows both its own
    // currency and the home one" — and had no callers at all.
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        funds: AsyncValue.data(netWorth(minor: 400000)),
        breakdown: AsyncValue.data([
          FundsRow(
            account: kDashAccount,
            original: Money(400000, 'INR'),
            converted: Money(400000, 'INR'),
            quality: RateQuality.exact,
            countsToward: true,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AmountText).first);
    await tester.pumpAndSettle();
    // Upper-case: `SectionHeader` renders `label.toUpperCase()`. I asserted the sentence case two
    // sessions running — the ARB holds the sentence, the widget shouts it, and a test that reads the ARB
    // value is testing the string table rather than the screen.
    expect(find.text('WHERE THIS COMES FROM'), findsOneWidget);
    expect(find.text(kDashAccount.name), findsOneWidget);
  });

  testWidgets('an unconvertible account says so instead of showing zero', (
    tester,
  ) async {
    // Anomaly A34. A nought would read as an empty account, and the balance is neither zero nor countable —
    // it is excluded, and the row has to say which.
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        funds: AsyncValue.data(netWorth(minor: 0, unconverted: 1)),
        breakdown: AsyncValue.data([
          FundsRow(
            account: kDashAccount,
            original: Money(5000, 'JPY'),
            converted: null,
            quality: RateQuality.unconverted,
            countsToward: true,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AmountText).first);
    await tester.pumpAndSettle();
    expect(find.text('Not counted'), findsOneWidget);
  });

  testWidgets('the total is not tappable while it is still loading', (
    tester,
  ) async {
    // A sheet opened over a figure that does not exist yet would explain nothing.
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(funds: const AsyncValue.loading()),
    );
    await tester.pumpAndSettle();
    expect(find.text('WHERE THIS COMES FROM'), findsNothing);
  });
}
```

### `test/features/dashboard/insight_card_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/dashboard/presentation/widgets/insight_card.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/dashboard/state/insight_side.dart';

import '../../support/dashboard_harness.dart';

/// Both sides, both empty states, and the switch. One failing card never blanks the dashboard.
void main() {
  // Inside a scroll view, because that is the only place the app ever puts this card: `DashboardScreen`
  // mounts it in a `CustomScrollView`, and the card's own contract is that it must not scroll on its own
  // — two scroll gestures competing for one drag. A bare `Scaffold` body bounds the main axis at the
  // viewport, so at a doubled scale this failed the card for being tall, which is what a card full of
  // wrapped text at 2x is supposed to be.
  //
  // This does not weaken the assertions. The cross axis stays tight at 320dp, and that is where the
  // overflow class this suite exists for actually lives (Law U21) — a starved `Expanded`, or a `Row`
  // that will not stack, still throws here.
  Widget host() => const Scaffold(
    body: SingleChildScrollView(child: InsightCard()),
  );

  testWidgets('it opens on what is coming up', (tester) async {
    await pumpDashboard(tester, host(), overrides: dashboardOverrides());
    await tester.pumpAndSettle();
    expect(find.text('Coming up'), findsOneWidget);
    expect(find.text('Where it went'), findsOneWidget);
  });

  testWidgets('loading the upcoming side says so, inline', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        upcomingEntries: const AsyncValue.loading(),
      ),
    );
    // Inline, inside the card: the header and the module grid above and below must stay usable.
    expect(find.text('Adding it up'), findsOneWidget);
  });

  testWidgets('a failed upcoming read shows its reason inline', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        upcomingEntries: AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('nothing upcoming is good news, and reads like it', (
    tester,
  ) async {
    await pumpDashboard(tester, host(), overrides: dashboardOverrides());
    await tester.pumpAndSettle();
    expect(
      find.text('Nothing needs attention in the next fortnight.'),
      findsOneWidget,
    );
  });

  testWidgets('populated lists what is due, soonest first', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        upcomingEntries: AsyncValue.data([
          upcoming(title: 'Rent'),
          upcoming(
            kind: UpcomingKind.service,
            title: 'Living room TV',
            on: const DateKey(20260810),
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Bill due'), findsOneWidget);
    expect(find.text('Living room TV'), findsOneWidget);
    expect(find.text('Service due'), findsOneWidget);
  });

  testWidgets('something already late says so', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        // Due in July against a clock fixed to 1 August. Derived from the clock, never stored.
        upcomingEntries: AsyncValue.data([
          upcoming(on: const DateKey(20260715)),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Overdue'), findsOneWidget);
  });

  testWidgets('the spending side shows a labelled total and its top kinds', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: [
        ...dashboardOverrides(),
        insightSideProvider.overrideWith(
          () => _FixedSide(InsightSide.spending),
        ),
      ],
    );
    await tester.pumpAndSettle();
    // **Phase 7B replaced the "waiting on the analytics module" assertion this test used to make.**
    // The side reads `AnalyticsService` now; what is asserted is that the window is labelled
    // (anomaly A33) and that the subtype key was localised rather than rendered raw (Law U5).
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text('Groceries'), findsWidgets);
    expect(find.text('grocery'), findsNothing);
    expect(
      find.text('Nothing needs attention in the next fortnight.'),
      findsNothing,
    );
  });

  testWidgets('the spending side reports its own failure and keeps the switch', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: [
        ...dashboardOverrides(
          spending: AsyncValue<Concentration>.error(
            Exception('rate table unreachable'),
            StackTrace.empty,
          ),
        ),
        insightSideProvider.overrideWith(
          () => _FixedSide(InsightSide.spending),
        ),
      ],
    );
    await tester.pumpAndSettle();
    // The repository's own message, not a generic body (Law U9), and the segmented control survives so
    // the reader can switch back to the side that works.
    expect(find.textContaining('rate table unreachable'), findsOneWidget);
    expect(find.byType(SegmentedButton<InsightSide>), findsOneWidget);
  });

  testWidgets('an empty window reads as a fact rather than a failure', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: [
        ...dashboardOverrides(
          spending: AsyncValue.data(spendByKind(total: 0, kinds: 0)),
        ),
        insightSideProvider.overrideWith(
          () => _FixedSide(InsightSide.spending),
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing spent in this window'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        upcomingEntries: AsyncValue.data([
          upcoming(
            title: 'A bill with a name long enough to wrap at a doubled scale',
          ),
          upcoming(kind: UpcomingKind.batch, on: const DateKey(20260710)),
        ]),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        upcomingEntries: AsyncValue.data([upcoming()]),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('the stored side', () {
    test('an unknown value falls back to upcoming rather than throwing', () {
      // A settings row is user data, and a future version may write a value this one has never heard of.
      expect(InsightSide.parse('spending'), InsightSide.spending);
      expect(InsightSide.parse('upcoming'), InsightSide.upcoming);
      expect(InsightSide.parse('something-else'), InsightSide.upcoming);
      expect(InsightSide.parse(null), InsightSide.upcoming);
    });

    test('what is stored round-trips', () {
      for (final side in InsightSide.values) {
        expect(InsightSide.parse(side.stored), side);
      }
    });
  });
}

/// A notifier reporting a fixed side, so each face can be pumped directly.
class _FixedSide extends InsightSideNotifier {
  _FixedSide(this._value);

  final InsightSide _value;

  @override
  InsightSide build() => _value;
}
```

### `test/features/dashboard/module_grid_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/dashboard/presentation/widgets/module_grid.dart';
import 'package:alaya/shared/widgets/module_tile.dart';

import '../../support/dashboard_harness.dart';

/// The grid is navigation, not decoration — so every tile's number is the test.
void main() {
  Widget host() =>
      const Scaffold(body: SingleChildScrollView(child: ModuleGrid()));

  testWidgets('seven tiles, each naming a module the drawer also names', (
    tester,
  ) async {
    await pumpDashboard(tester, host(), overrides: dashboardOverrides());
    await tester.pumpAndSettle();
    expect(find.byType(ModuleTile), findsNWidgets(7));
    for (final label in [
      'Expenses',
      'Inventory',
      'Recipes',
      'Split',
      'Shopping',
      'Recurring',
      'Services',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('a zero is worded, never shown as a figure', (tester) async {
    await pumpDashboard(tester, host(), overrides: dashboardOverrides());
    await tester.pumpAndSettle();
    // "0 running low" is a number the reader has to interpret; "nothing tracked" is an answer. Only the
    // ARB knows which sentence a count needs, which is why ModuleTile takes text rather than an int.
    expect(find.text('nothing tracked'), findsOneWidget);
    expect(find.text('list is clear'), findsOneWidget);
    expect(find.text('all settled'), findsOneWidget);
    expect(find.text('nothing needs doing'), findsOneWidget);
  });

  testWidgets('a live number appears, singular and plural both worded', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        inventory: 1,
        services: 4,
        shopping: const AsyncValue.data(7),
        recurring: const AsyncValue.data(2),
        expenses: const AsyncValue.data(31),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 running low'), findsOneWidget);
    expect(find.text('4 need attention'), findsOneWidget);
    expect(find.text('7 to buy'), findsOneWidget);
    expect(find.text('2 due'), findsOneWidget);
    expect(find.text('31 this month'), findsOneWidget);
  });

  testWidgets('a count still arriving leaves the tile navigable', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(shopping: const AsyncValue.loading()),
    );
    await tester.pump();
    // The tile's job is navigation and it can do that before its count lands — a spinner on a nav tile
    // would suggest the destination itself was unavailable.
    expect(find.byType(ModuleTile), findsNWidgets(7));
    expect(find.text('Shopping'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failed count leaves the tile navigable too', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        recurring: AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    await tester.pumpAndSettle();
    // One broken count must not cost the user five destinations.
    expect(find.byType(ModuleTile), findsNWidgets(7));
    expect(find.text('Recurring'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        inventory: 12,
        services: 9,
        shopping: const AsyncValue.data(23),
        recurring: const AsyncValue.data(5),
        expenses: const AsyncValue.data(147),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every tile is a labelled button of a reachable size', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(inventory: 2),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/dashboard/range_row_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/dashboard/presentation/widgets/range_row.dart';
import 'package:alaya/shared/widgets/amount_text.dart';

import '../../support/dashboard_harness.dart';

/// The label is the test. A range row without one is a number with no meaning (anomaly A33).
void main() {
  const window = (from: DateKey(20260703), to: kToday);

  Widget host(String label) => Scaffold(
    body: RangeRow(label: label, range: window),
  );

  testWidgets('the window is stated in words, never implied', (tester) async {
    await pumpDashboard(
      tester,
      host('Last 30 days'),
      overrides: dashboardOverrides(),
    );
    await tester.pumpAndSettle();
    // "Last month" would be ambiguous between thirty days and a calendar month, and the figures cannot
    // disambiguate themselves. The label states the window the provider actually computed.
    expect(find.text('Last 30 days'), findsOneWidget);
  });

  testWidgets('loading keeps the label', (tester) async {
    await pumpDashboard(
      tester,
      host('Last 30 days'),
      overrides: dashboardOverrides(last30: const AsyncValue.loading()),
    );
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text('Adding it up'), findsOneWidget);
  });

  testWidgets('an error keeps the label and names itself', (tester) async {
    await pumpDashboard(
      tester,
      host('Last 30 days'),
      overrides: dashboardOverrides(
        last30: AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    await tester.pumpAndSettle();
    // A failed conversion must not take the window's meaning down with it — the reader still needs to
    // know which row broke.
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('an empty window reads as nothing yet, not as zero', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      host('Last 30 days'),
      overrides: dashboardOverrides(
        last30: AsyncValue.data(totals(inMinor: 0, outMinor: 0)),
      ),
    );
    await tester.pumpAndSettle();
    // Two zeroes side by side look like a computation; "nothing yet" is what actually happened.
    expect(find.text('Nothing yet'), findsOneWidget);
    expect(find.byType(AmountText), findsNothing);
  });

  testWidgets('populated shows both legs, each labelled and each small', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      host('Last 30 days'),
      overrides: dashboardOverrides(),
    );
    await tester.pumpAndSettle();
    expect(find.text('In'), findsOneWidget);
    expect(find.text('Out'), findsOneWidget);
    final amounts = tester
        .widgetList<AmountText>(find.byType(AmountText))
        .toList();
    expect(amounts.length, 2);
    // Neither is a headline: the funds header owns the only display-sized figure on the dashboard.
    expect(amounts.every((a) => a.size == AmountSize.small), isTrue);
    expect(amounts.first.kind, TransactionKind.deposit);
    expect(amounts.last.kind, TransactionKind.withdrawal);
  });

  testWidgets('excluded transactions are disclosed, not folded in', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      host('Last 30 days'),
      overrides: dashboardOverrides(
        last30: AsyncValue.data(totals(excluded: 3)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3 left out'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpDashboard(
      tester,
      host('All time'),
      overrides: dashboardOverrides(
        last30: AsyncValue.data(totals(excluded: 2)),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpDashboard(
      tester,
      host('Last 30 days'),
      overrides: dashboardOverrides(),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/dashboard/span_totals_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/features/calendar/providers/calendar_providers.dart';

/// `SpanTotals.from` is a pure mapping, so it is tested as one — no provider, no repository, no pump.
/// The three decisions it encodes are all invisible from the screen and all wrong in a way a reader
/// would believe: a transfer counted twice, a second currency added to the first, an empty span
/// reporting two confident zeroes.
void main() {
  Transaction tx({
    required String id,
    required TransactionKind kind,
    required int minor,
    String currency = 'INR',
  }) => Transaction(
    id: id,
    kind: kind,
    // Irrelevant to the mapping, which reads only `kind` and `originalAmount`.
    subtype: TransactionSubtype.otherOut,
    occurredAtUtc: DateTime.utc(2026, 8, 10),
    dateKey: const DateKey(20260810),
    originalAmount: Money(minor, currency),
    needsReview: false,
  );

  test(
    'deposits and increases count in, withdrawals and decreases count out',
    () {
      final totals = SpanTotals.from([
        tx(id: 't1', kind: TransactionKind.deposit, minor: 50000),
        tx(id: 't2', kind: TransactionKind.adjustmentIncrease, minor: 500),
        tx(id: 't3', kind: TransactionKind.withdrawal, minor: 12000),
        tx(id: 't4', kind: TransactionKind.adjustmentDecrease, minor: 300),
      ]);

      expect(totals.inMinor, 50500);
      expect(totals.outMinor, 12300);
      expect(totals.currencyCode, 'INR');
      expect(totals.isEmpty, isFalse);
    },
  );

  test('a transfer counts as neither', () {
    // Money moving between your own accounts is not spending and not income. Counting it as both
    // would double the totals of anyone who moves money in order to save it.
    final totals = SpanTotals.from([
      tx(id: 't1', kind: TransactionKind.transfer, minor: 99999),
    ]);

    expect(totals.inMinor, 0);
    expect(totals.outMinor, 0);
  });

  test('a second currency is skipped rather than added to the first', () {
    // Adding minor units across currencies produces a number that looks right and is not. Converting
    // properly needs the frozen-rate path, which belongs to analytics — so the figure stays honest by
    // covering less.
    final totals = SpanTotals.from([
      tx(id: 't1', kind: TransactionKind.withdrawal, minor: 10000),
      tx(
        id: 't2',
        kind: TransactionKind.withdrawal,
        minor: 7000,
        currency: 'USD',
      ),
    ]);

    expect(totals.outMinor, 10000);
    expect(totals.currencyCode, 'INR');
  });

  test('an empty span reports empty, not zero', () {
    // The screen hides the figures when this is true. Two zeroes read like a finding — "you spent
    // nothing" — where nothing was measured at all.
    expect(SpanTotals.from(const []).isEmpty, isTrue);
  });
}
```
