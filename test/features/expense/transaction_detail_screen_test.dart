import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_detail_screen.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';

import '../../support/expense_harness.dart';

/// Four states, plus the two rules this screen exists to demonstrate: a null value renders no row,
/// and the destructive action sits last.
void main() {
  const id = 'tx-1';

  List<Override> overrides(AsyncValue<Transaction?> transaction) => [
    clockProvider.overrideWithValue(kTestClock),
    transactionByIdProvider(
      id,
    ).overrideWith((ref) async => transaction.valueOrNull),
    transactionLinesProvider(
      id,
    ).overrideWith((ref) => Stream.value(const <TransactionLine>[])),
    transactionAllocationProvider(id).overrideWith((ref) => Stream.value(null)),
    transactionTagsProvider(
      id,
    ).overrideWith((ref) => Stream.value(const <Tag>[])),
    paymentMethodsByIdProvider.overrideWith(
      (ref) => Stream.value(const <String, PaymentMethod>{}),
    ),
    accountsByIdProvider.overrideWith(
      (ref) => Stream.value(<String, Account>{kAccount.id: kAccount}),
    ),
    payeesByIdProvider.overrideWith(
      (ref) => Stream.value(<String, Payee>{kPayee.id: kPayee}),
    ),
    homeDecimalDigitsProvider.overrideWith((ref) => 2),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpExpense(
      tester,
      const TransactionDetailScreen(transactionId: id),
      overrides: [
        ...overrides(const AsyncValue.loading()),
        transactionByIdProvider(
          id,
        ).overrideWith((ref) => pendingFuture<Transaction?>()),
      ],
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('a missing transaction reads as not found, not as a crash', (
    tester,
  ) async {
    await pumpExpense(
      tester,
      const TransactionDetailScreen(transactionId: id),
      overrides: overrides(const AsyncValue.data(null)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Not found'), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpExpense(
      tester,
      const TransactionDetailScreen(transactionId: id),
      overrides: [
        ...overrides(const AsyncValue.loading()),
        transactionByIdProvider(
          id,
        ).overrideWith((ref) async => throw StateError('boom')),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('populated renders the hero and hides rows with no value', (
    tester,
  ) async {
    await pumpExpense(
      tester,
      const TransactionDetailScreen(transactionId: id),
      overrides: overrides(AsyncValue.data(sampleTransaction())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reliance Fresh'), findsOneWidget);
    // The sample has no note and no payment method, so neither row exists at all — a screen of
    // dashes reads as broken data rather than as a record with optional fields.
    expect(find.text('Note'), findsNothing);
    expect(find.text('Payment method'), findsNothing);
    expect(find.byType(KeyValueRow), findsWidgets);
  });

  testWidgets('the destructive action is present and is not a filled button', (
    tester,
  ) async {
    await pumpExpense(
      tester,
      const TransactionDetailScreen(transactionId: id),
      overrides: overrides(AsyncValue.data(sampleTransaction())),
    );
    await tester.pumpAndSettle();
    // The screen is a ListView and the destructive action is deliberately its last child, so on a
    // 320x640 viewport it is not built until scrolled to. That it sits below everything else is the
    // point (ARCH_5 §5.5) — the test travels to it rather than assuming it is on screen.
    await tester.scrollUntilVisible(
      find.text('Delete transaction'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextButton, 'Delete transaction'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Delete transaction'),
      findsNothing,
    );
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpExpense(
      tester,
      const TransactionDetailScreen(transactionId: id),
      overrides: overrides(
        AsyncValue.data(sampleTransaction(needsReview: true)),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
