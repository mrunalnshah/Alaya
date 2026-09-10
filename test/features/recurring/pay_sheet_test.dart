import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/recurring/presentation/sheets/pay_sheet.dart';
import 'package:alaya/features/recurring/providers/pay_providers.dart';
import 'package:alaya/features/recurring/state/pay_state.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

import '../../support/recurring_harness.dart';

/// The capture path: the default is pre-filled, the actual is editable, and both are kept.
void main() {
  /// A fixed-length override list.
  ///
  /// The length must not vary between scopes — a conditional entry is what produced *"Tried to change
  /// the number of overrides"*. `seed` defaults to the state the notifier would build anyway.
  List<Override> overrides({PayState? seed}) => [
    clockProvider.overrideWithValue(kRecurringClock),
    payAccountsProvider.overrideWith((ref) => Stream.value(const [kAccount])),
    payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
    payProvider.overrideWith(
      () => _StubPay(
        seed ??
            PayState(
              occurrenceId: 'occ-1',
              defaultAmount: const Money(120000, 'INR'),
              amount: const Money(120000, 'INR'),
              paidOn: kToday,
              accountId: kAccount.id,
            ),
      ),
    ),
  ];

  Widget host() => Scaffold(
    body: AlayaBottomSheet(
      child: PaySheet(occurrenceId: 'occ-1', template: billTemplate()),
    ),
  );

  testWidgets('opens with the usual amount already filled in', (tester) async {
    await pumpRecurring(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    // The common case is that it cost what it usually costs, so that path is one tap.
    expect(find.byType(AmountField), findsOneWidget);
    expect(find.text('Amount actually paid'), findsOneWidget);
  });

  testWidgets('an inflow asks what was received, not what was paid', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      Scaffold(
        body: AlayaBottomSheet(
          child: PaySheet(occurrenceId: 'occ-2', template: salaryTemplate()),
        ),
      ),
      overrides: [
        clockProvider.overrideWithValue(kRecurringClock),
        payAccountsProvider.overrideWith(
          (ref) => Stream.value(const [kAccount]),
        ),
        payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Record this receipt'), findsOneWidget);
    expect(find.text('Amount actually received'), findsOneWidget);
  });

  // **Two tests, not two pumps.** A second `pumpWidget` in one `testWidgets` reuses the same
  // `ProviderScope`, so a differing override count throws *"Tried to change the number of
  // overrides"* — and even with a matching count the scope updates rather than replaces, so the new
  // override silently never installs and the test passes for the wrong reason (ARCH_4 P5).
  testWidgets('the usual figure is hidden while the actual matches it', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: overrides(
        seed: PayState(
          occurrenceId: 'occ-1',
          defaultAmount: const Money(120000, 'INR'),
          amount: const Money(120000, 'INR'),
          paidOn: kToday,
          accountId: kAccount.id,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Repeating the default under an unchanged figure is noise.
    expect(find.text('Usually'), findsNothing);
  });

  testWidgets('the usual figure appears once the actual differs', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: overrides(
        seed: PayState(
          occurrenceId: 'occ-1',
          defaultAmount: const Money(120000, 'INR'),
          amount: const Money(124700, 'INR'),
          paidOn: kToday,
          accountId: kAccount.id,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Beside a changed one it confirms the change was deliberate.
    expect(find.text('Usually'), findsOneWidget);
  });

  testWidgets('a missing amount shakes rather than writing zero', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: overrides(
        seed: PayState(
          occurrenceId: 'occ-1',
          defaultAmount: const Money(120000, 'INR'),
          paidOn: kToday,
          accountId: kAccount.id,
          issue: PayIssue.amountMissing,
          shakeTrigger: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ShakeOnError), findsOneWidget);
    expect(find.text('Enter an amount'), findsOneWidget);
  });

  testWidgets('a missing account is named, not reported generically', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: overrides(
        seed: PayState(
          occurrenceId: 'occ-1',
          defaultAmount: const Money(120000, 'INR'),
          amount: const Money(120000, 'INR'),
          paidOn: kToday,
          issue: PayIssue.accountMissing,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose which account it came from'), findsOneWidget);
  });

  testWidgets('loading accounts still lets the amount be typed', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: [
        clockProvider.overrideWithValue(kRecurringClock),
        payAccountsProvider.overrideWith(
          (ref) => pendingStream<List<Account>>(),
        ),
        payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
      ],
    );
    await tester.pump();
    // A capture sheet takes its first keystroke on its first frame (§5.2): the account list is still
    // arriving and the amount field is already there, pre-filled.
    expect(find.byType(AmountField), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });

  testWidgets('no accounts at all omits the picker rather than blocking', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: [
        clockProvider.overrideWithValue(kRecurringClock),
        payAccountsProvider.overrideWith(
          (ref) => Stream.value(const <Account>[]),
        ),
        payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed account stream does not take the sheet down', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: [
        clockProvider.overrideWithValue(kRecurringClock),
        payAccountsProvider.overrideWith(
          (ref) => Stream<List<Account>>.error(StateError('boom')),
        ),
        payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
      ],
    );
    await tester.pumpAndSettle();
    // The template carries a default account, so a failed lookup costs the picker, not the payment.
    expect(find.byType(AmountField), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Record it'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpRecurring(tester, host(), overrides: overrides(), textScale: 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpRecurring(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('state', () {
    test('differsFromDefault is false until the figure changes', () {
      const base = PayState(
        occurrenceId: 'occ-1',
        defaultAmount: Money(120000, 'INR'),
        amount: Money(120000, 'INR'),
        paidOn: kToday,
      );
      expect(base.differsFromDefault, isFalse);
      expect(
        base.copyWith(amount: const Money(124700, 'INR')).differsFromDefault,
        isTrue,
      );
    });

    test('an issue survives an unrelated copyWith', () {
      const base = PayState(
        occurrenceId: 'occ-1',
        defaultAmount: Money(120000, 'INR'),
        paidOn: kToday,
        issue: PayIssue.accountMissing,
      );
      // ARCH_4 R31: a bare assignment let `submitting: false` in a `finally` erase the reason
      // microseconds before the sheet read it. It must survive, and clear only when asked.
      expect(base.copyWith(submitting: false).issue, PayIssue.accountMissing);
      expect(base.copyWith(clearIssue: true).issue, isNull);
    });
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubPay extends PayNotifier {
  _StubPay(this._value);

  final PayState _value;

  @override
  PayState build(PayArgs arg) => _value;
}
