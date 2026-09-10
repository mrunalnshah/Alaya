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
