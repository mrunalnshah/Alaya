import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/dashboard/presentation/widgets/funds_header.dart';
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
}
