import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_list_screen.dart';
import 'package:alaya/features/expense/presentation/widgets/needs_review_banner.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/expense_harness.dart';

/// Four states, a narrow viewport at a doubled text scale, and the tap-target floor (ARCH_5 §9.1).
void main() {
  List<Override> overrides(
    AsyncValue<List<TransactionDayGroup>> days, {
    int needsReview = 0,
  }) => [
    clockProvider.overrideWithValue(kTestClock),
    transactionDaysProvider.overrideWith((ref) => days),
    needsReviewCountProvider.overrideWith((ref) => Stream.value(needsReview)),
    accountsByIdProvider.overrideWith(
      (ref) => Stream.value(<String, Account>{kAccount.id: kAccount}),
    ),
    payeesByIdProvider.overrideWith(
      (ref) => Stream.value(<String, Payee>{kPayee.id: kPayee}),
    ),
    homeDecimalDigitsProvider.overrideWith((ref) => 2),
  ];

  final populated = AsyncValue.data([
    TransactionDayGroup(date: kToday, transactions: [sampleTransaction()]),
  ]);

  testWidgets('loading shows a skeleton, not a spinner', (tester) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('empty invites the user to act rather than reporting emptiness', (
    tester,
  ) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(const AsyncValue.data([])),
    );
    expect(find.byType(EmptyState), findsOneWidget);
    expect(
      find.text('Add your first expense and it will appear here.'),
      findsOneWidget,
    );
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('populated renders a row per transaction', (tester) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(populated),
    );
    expect(find.byType(TransactionRow), findsOneWidget);
    expect(find.text('Reliance Fresh'), findsOneWidget);
  });

  testWidgets('the needs-review nudge is absent at zero', (tester) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(populated),
    );
    expect(find.byType(NeedsReviewBanner), findsOneWidget);
    // The banner widget is present but renders nothing: a nudge that says "0 need details" is
    // noise, and hiding it is the widget's own job rather than the screen's.
    expect(find.text('Review'), findsNothing);
  });

  testWidgets(
    'the needs-review nudge counts and offers the action above zero',
    (tester) async {
      await pumpExpense(
        tester,
        const TransactionListScreen(),
        overrides: overrides(populated, needsReview: 3),
      );
      expect(find.text('3 transactions need details'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
    },
  );

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(populated, needsReview: 2),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(populated),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
