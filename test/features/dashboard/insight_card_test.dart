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
