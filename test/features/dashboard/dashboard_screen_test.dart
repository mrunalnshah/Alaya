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
    expect(find.text('Money in'), findsOneWidget);
    expect(find.text('New item'), findsOneWidget);
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
