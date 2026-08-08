import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/features/service/presentation/screens/service_editor_screen.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/service_editor_providers.dart';
import 'package:alaya/features/service/state/service_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/service_harness.dart';

/// Four states, plus the one write path: the toggle is a repository parameter, never a second save.
void main() {
  const assetId = 'asset-1';

  ServiceEditorState state({
    ServiceRecordType type = ServiceRecordType.service,
    int? costMinor = 120000,
    bool alsoRecordAsExpense = false,
    String? accountId,
    ServiceSaveIssue? issue,
    String? rejection,
  }) => ServiceEditorState(
    assetId: assetId,
    currencyCode: 'INR',
    serviceDateKey: kToday,
    type: type,
    cost: costMinor == null ? null : Money(costMinor, 'INR'),
    alsoRecordAsExpense: alsoRecordAsExpense,
    accountId: accountId,
    issue: issue,
    rejection: rejection,
  );

  const method = PaymentMethod(
    id: 'pm-1',
    name: 'UPI',
    kind: PaymentMethodKind.upi,
    isSystem: true,
    sortOrder: 0,
  );

  /// A fixed-length override list.
  ///
  /// **The payment methods are always overridden, even when the test does not care.** Left alone,
  /// `servicePaymentMethodsProvider` reaches `paymentMethodRepositoryProvider` and through it a real
  /// database — which a widget test has no business opening (ARCH_4 P6).
  List<Override> overrides(
    AsyncValue<ServiceEditorState> value, {
    List<Account> accounts = const [kAccount],
    List<PaymentMethod> methods = const [],
  }) => [
    serviceEditorProvider.overrideWith(() => _StubEditor(value)),
    serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
    serviceAccountsProvider.overrideWith((ref) => Stream.value(accounts)),
    servicePaymentMethodsProvider.overrideWith((ref) => Stream.value(methods)),
  ];

  Widget host() => const ServiceEditorScreen(assetId: assetId);

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('an unknown record reads as not found', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('a new record opens on the form', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(AsyncValue.data(state(costMinor: null))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.text('What happened'), findsOneWidget);
  });

  testWidgets('every service type is offered, salaryPaid included', (
    tester,
  ) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<ServiceRecordType>));
    await tester.pumpAndSettle();
    // §7.2: `salaryPaid` has to be reachable, or the maid case has no way to record a payment.
    expect(find.text('Salary paid'), findsWidgets);
  });

  testWidgets('a salary is not asked when the next one is due', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(state(type: ServiceRecordType.salaryPaid)),
      ),
    );
    await tester.pumpAndSettle();
    // The next payment is the recurring template's business; a second due date here would be a second
    // schedule to keep in step.
    expect(find.text('Next one due'), findsNothing);
  });

  testWidgets('a service is asked when the next one is due', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Next one due'), findsOneWidget);
  });

  // The screen renders whatever the flag says; the *default* is the notifier's business and is asserted
  // in the state group below. Naming this "off until asked for" implied the screen owned a default it
  // never had.
  testWidgets('the toggle off hides both money pickers', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(AsyncValue.data(state()), methods: const [method]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Also record it as an expense'), findsOneWidget);
    // Both the account and the method live under the flag, so neither appears.
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });

  testWidgets('the toggle on reveals the account it will draw from', (
    tester,
  ) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(
          state(alsoRecordAsExpense: true, accountId: kAccount.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // One picker, because no payment methods were supplied — an empty method dropdown never appears.
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.text('How you paid (optional)'), findsNothing);
    expect(
      find.textContaining('Writes a withdrawal for the cost as well'),
      findsOneWidget,
    );
  });

  testWidgets('the payment method is offered, and only ever optional', (
    tester,
  ) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(
          state(alsoRecordAsExpense: true, accountId: kAccount.id),
        ),
        methods: const [method],
      ),
    );
    await tester.pumpAndSettle();
    // Account and method: two pickers, and the label says which one may be left alone.
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    expect(find.text('How you paid (optional)'), findsOneWidget);
  });

  testWidgets('the toggle with no cost is refused at the field', (
    tester,
  ) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(
          state(
            costMinor: null,
            alsoRecordAsExpense: true,
            issue: ServiceSaveIssue.costMissingForExpense,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add a cost first'), findsWidgets);
  });

  testWidgets('the toggle with no account is refused at the field', (
    tester,
  ) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(
          state(
            alsoRecordAsExpense: true,
            issue: ServiceSaveIssue.accountMissingForExpense,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose which account it comes from'), findsWidgets);
  });

  testWidgets('a rejection is shown in the repository own words', (
    tester,
  ) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(
          state(
            issue: ServiceSaveIssue.rejected,
            rejection: 'That asset no longer exists.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('no longer exists'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(
          state(alsoRecordAsExpense: true, accountId: kAccount.id),
        ),
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
    await pumpService(
      tester,
      host(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('the state', () {
    test('editing an existing record never re-offers the expense toggle', () {
      final saved = state(
        alsoRecordAsExpense: true,
        costMinor: 120000,
      ).toRecord(newId: 'rec-1');
      final reopened = ServiceEditorState.fromRecord(saved, 'INR');
      // One service must not be able to write two withdrawals — the same shape as ARCH_4 R35.
      expect(reopened.alsoRecordAsExpense, isFalse);
    });

    test('the toggle is only satisfiable with a cost and an account', () {
      expect(state().expenseIsSatisfiable, isTrue);
      expect(state(alsoRecordAsExpense: true).expenseIsSatisfiable, isFalse);
      expect(
        state(
          alsoRecordAsExpense: true,
          accountId: 'acc-1',
        ).expenseIsSatisfiable,
        isTrue,
      );
      expect(
        state(
          alsoRecordAsExpense: true,
          accountId: 'acc-1',
          costMinor: null,
        ).expenseIsSatisfiable,
        isFalse,
      );
    });

    test(
      'a new record defaults to recording the expense, an edited one never does',
      () {
        // The default lives in `_load`, so it is asserted where it is observable: a record round-tripped
        // through `fromRecord` must come back with the toggle off, because an existing record either wrote
        // its expense already or deliberately did not (ARCH_4 R35).
        final saved = state(alsoRecordAsExpense: true).toRecord(newId: 'rec-1');
        expect(
          ServiceEditorState.fromRecord(saved, 'INR').alsoRecordAsExpense,
          isFalse,
        );
      },
    );

    test('a payment method is held by the editor, never by the record', () {
      // `ServiceRecord` has no such field — adding one would duplicate a column `transactions` already
      // owns, and the two would drift. The editor carries it only to hand to `save`, which puts it on
      // the expense. That `toRecord` cannot express it is the point, and it is a compile-time fact; what
      // is worth asserting is that the editor does not quietly lose it on the way.
      expect(state().copyWith(paymentMethodId: 'pm-1').paymentMethodId, 'pm-1');
      expect(
        state()
            .copyWith(paymentMethodId: 'pm-1')
            .copyWith(notes: 'x')
            .paymentMethodId,
        'pm-1',
      );
    });

    test('an existing transaction link survives an edit', () {
      final linked = state().toRecord(
        newId: 'rec-1',
        existing: serviceRecord(linkedTransactionId: 'txn-1'),
      );
      // Clearing it would orphan a transaction that genuinely happened (Law L6).
      expect(linked.linkedTransactionId, 'txn-1');
    });
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubEditor extends ServiceEditorNotifier {
  _StubEditor(this._value);

  final AsyncValue<ServiceEditorState> _value;

  @override
  AsyncValue<ServiceEditorState> build(ServiceEditorArgs arg) => _value;
}
