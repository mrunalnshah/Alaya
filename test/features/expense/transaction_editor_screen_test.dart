import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_editor_screen.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/deposit_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/grocery_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/transfer_form.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/expense_harness.dart';

/// The editor's four states, and the two behaviours the phase brief singles out: the sub-form
/// switches on subtype, and the commit lives in the footer rather than the app bar.
void main() {
  TransactionEditorState seed({
    TransactionKind kind = TransactionKind.withdrawal,
    TransactionSubtype subtype = TransactionSubtype.grocery,
  }) => TransactionEditorState(
    currencyCode: 'INR',
    dateKey: kToday,
    kind: kind,
    subtype: subtype,
  );

  // The override goes on the **family**, not on an instance of it. A NotifierProvider family
  // instance has no `overrideWith` — unlike a FutureProvider or StreamProvider instance, which do.
  // Overriding the family replaces every instance, which is what this test wants anyway.
  List<Override> overrides(AsyncValue<TransactionEditorState> state) => [
    transactionEditorProvider.overrideWith(() => _StubEditor(state)),
    homeDecimalDigitsProvider.overrideWith((ref) => 2),
    selectableAccountsProvider.overrideWith(
      (ref) => Stream.value(const [kAccount]),
    ),
    editorPaymentMethodsProvider.overrideWith(
      (ref) => Stream.value(const <PaymentMethod>[]),
    ),
    editorPayeesProvider.overrideWith((ref) => Stream.value(const [kPayee])),
    for (final kind in TransactionKind.values)
      editorTagsProvider(
        kind,
      ).overrideWith((ref) => Stream.value(const <Tag>[])),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('error reads as not found rather than as a blank form', (
    tester,
  ) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('a new transaction opens on the form, which is its empty state', (
    tester,
  ) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
    );
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.text('New transaction'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save expense'), findsOneWidget);
  });

  testWidgets('a grocery withdrawal shows the grocery form', (tester) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
    );
    expect(find.byType(GroceryForm), findsOneWidget);
    expect(find.byType(DepositForm), findsNothing);
  });

  testWidgets('a salary deposit shows the deposit form', (tester) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(
        AsyncValue.data(
          seed(
            kind: TransactionKind.deposit,
            subtype: TransactionSubtype.salaryIn,
          ),
        ),
      ),
    );
    expect(find.byType(DepositForm), findsOneWidget);
    expect(find.byType(GroceryForm), findsNothing);
  });

  testWidgets('a transfer shows the two-option toggle, not a payee-only form', (
    tester,
  ) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(
        AsyncValue.data(
          seed(
            kind: TransactionKind.transfer,
            subtype: TransactionSubtype.transferSelf,
          ),
        ),
      ),
    );
    expect(find.byType(TransferForm), findsOneWidget);
    expect(find.text('To my own account'), findsOneWidget);
    expect(find.text('To someone else'), findsOneWidget);
    // The copy states the consequence rather than the mechanism — anomaly A02's whole point.
    expect(
      find.text(
        'Moves money between your accounts. Your total does not change.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the commit lives in the footer, never in the app bar', (
    tester,
  ) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
    );
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(TextButton, 'Save expense'),
      ),
      findsNothing,
    );
    expect(find.byType(CloseButton), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });
}

/// A notifier reporting a fixed state, so each of the four branches can be pumped directly.
class _StubEditor extends TransactionEditorNotifier {
  _StubEditor(this._state);

  final AsyncValue<TransactionEditorState> _state;

  @override
  AsyncValue<TransactionEditorState> build(String? arg) => _state;
}
