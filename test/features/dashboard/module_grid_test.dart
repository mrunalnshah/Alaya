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
