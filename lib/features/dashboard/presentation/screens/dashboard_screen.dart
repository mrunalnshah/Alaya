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
