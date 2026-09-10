import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/expense_harness.dart';

/// Four states, 320dp at a doubled text scale, and both accessibility floors (ARCH_5 §9.1).
void main() {
  TransactionLine line({
    String id = 'line-1',
    String description = 'Onion',
    int? amountMinor = 4000,
    Qty? quantity,
    TransactionLineDestination destination = TransactionLineDestination.none,
  }) =>
      TransactionLine(
        id: id,
        transactionId: '',
        lineNo: 1,
        description: description,
        destination: destination,
        quantity: quantity,
        lineAmount: amountMinor == null ? null : Money(amountMinor, 'INR'),
      );

  TransactionEditorState state({List<TransactionLine> lines = const [], int? amountMinor = 20000}) =>
      TransactionEditorState(
        currencyCode: 'INR',
        dateKey: kToday,
        amount: amountMinor == null ? null : Money(amountMinor, 'INR'),
        lines: lines,
      );

  // The override goes on the **family**: a NotifierProvider family instance has no `overrideWith`.
  List<Override> overrides(AsyncValue<TransactionEditorState> value) => [
        transactionEditorProvider.overrideWith(() => _StubEditor(value)),
        homeDecimalDigitsProvider.overrideWith((ref) async => 2),
      ];

  testWidgets('loading shows a skeleton, not a spinner', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('empty invites the first item and says what happens if you skip it',
      (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nothing itemised yet'), findsOneWidget);
    // Itemising is optional (anomaly A11), and the empty state has to say so or it reads as a
    // required step blocking the save.
    expect(find.textContaining('Anything you leave out still counts'), findsOneWidget);
  });

  testWidgets('error shows the real reason with a retry', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(AsyncValue.error(StateError('boom'), StackTrace.empty)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('populated lists every line with its figure', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(lines: [line(), line(id: 'line-2', description: 'Tomato', amountMinor: 6000)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Onion'), findsOneWidget);
    expect(find.text('Tomato'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
  });

  testWidgets('the running figures show what is itemised and what is not', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(
        AsyncValue.data(state(lines: [line()], amountMinor: 20000)),
      ),
    );
    await tester.pumpAndSettle();
    // 200.00 entered, 40.00 itemised. The gap is shown, never auto-balanced (anomaly A11).
    expect(find.text('Itemised'), findsOneWidget);
    expect(find.text('Unallocated'), findsOneWidget);
  });

  testWidgets('a fully itemised transaction shows no unallocated chip', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(
        AsyncValue.data(state(lines: [line(amountMinor: 20000)], amountMinor: 20000)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unallocated'), findsNothing);
  });

  testWidgets('an inventory line is marked as one', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(
            lines: [
              line(
                destination: TransactionLineDestination.inventory,
                quantity: const Qty(500000, UnitCategory.weight),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('500 g'), findsOneWidget);
  });

  testWidgets('removing a line reports it', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(AsyncValue.data(state(lines: [line()]))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    // No Undo: nothing has been written, so a snack promising undo for an uncommitted edit would be
    // lying (§5.4). It confirms, and stops there.
    expect(find.text('Item removed'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('Done leaves without committing anything', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(AsyncValue.data(state(lines: [line()]))),
    );
    await tester.pumpAndSettle();
    // The page edits editor state; the transaction is written by the editor's own save.
    expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save expense'), findsNothing);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(
            lines: [
              line(
                destination: TransactionLineDestination.inventory,
                quantity: const Qty(500000, UnitCategory.weight),
              ),
              line(id: 'line-2', description: 'Tomato', amountMinor: 6000),
            ],
          ),
        ),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(AsyncValue.data(state(lines: [line()]))),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubEditor extends TransactionEditorNotifier {
  _StubEditor(this._value);

  final AsyncValue<TransactionEditorState> _value;

  @override
  AsyncValue<TransactionEditorState> build(String? arg) => _value;
}
