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
