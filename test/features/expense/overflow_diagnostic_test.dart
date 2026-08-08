import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_list_screen.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';

import '../../support/expense_harness.dart';

/// **Throwaway.** Delete this file once the 524px overflow is identified.
///
/// Reading every widget in the offending `Column` accounts for roughly 260px of non-flex height
/// against a 640px viewport, so the reported 1,164px cannot come from where the stack trace points.
/// That means an assumption about the *test* is wrong rather than an assumption about the widgets —
/// so this measures instead of reasoning.
void main() {
  testWidgets('measure the list screen body at a doubled text scale', (tester) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: [
        clockProvider.overrideWithValue(kTestClock),
        transactionDaysProvider.overrideWith(
          (ref) => AsyncValue.data([
            TransactionDayGroup(date: kToday, transactions: [sampleTransaction()]),
          ]),
        ),
        needsReviewCountProvider.overrideWith((ref) => Stream.value(2)),
        accountsByIdProvider.overrideWith(
          (ref) => Stream.value(<String, Account>{kAccount.id: kAccount}),
        ),
        payeesByIdProvider.overrideWith(
          (ref) => Stream.value(<String, Payee>{kPayee.id: kPayee}),
        ),
        homeDecimalDigitsProvider.overrideWith((ref) => 2),
      ],
      textScale: 2,
    );

    debugPrint('=== ALAYA OVERFLOW DIAGNOSTIC ===');

    // Every direct child of the body Column, in order, with its laid-out size. Whichever of these is
    // not ~60-160px tall is the culprit.
    for (final name in const [
      '_Toolbar',
      '_NeedsReviewRow',
      '_ActiveFilters',
      '_GroupedList',
      '_SearchResults',
    ]) {
      final found = find.byWidgetPredicate((w) => w.runtimeType.toString() == name);
      if (found.evaluate().isEmpty) {
        debugPrint('$name: ABSENT from the tree');
        continue;
      }
      try {
        debugPrint('$name: ${tester.getSize(found.first)}');
      } on Object catch (error) {
        debugPrint('$name: present but unmeasurable -> $error');
      }
    }

    // The Column itself: what it was offered, and what it took.
    final column = find
        .byWidgetPredicate((w) => w is Column && w.children.length >= 2)
        .evaluate()
        .map((e) => e.renderObject)
        .whereType<RenderFlex>()
        .toList();
    for (final flex in column) {
      debugPrint(
        'Column direction=${flex.direction} '
        'constraints=${flex.constraints} '
        'size=${flex.hasSize ? flex.size : "MISSING"}',
      );
    }

    // Which widget actually reported the overflow, and how far.
    final exception = tester.takeException();
    debugPrint('exception: ${exception ?? "none"}');
    debugPrint('=== END DIAGNOSTIC ===');
  });
}
