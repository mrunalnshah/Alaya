import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/expense/presentation/sheets/quick_add_sheet.dart';
import 'package:alaya/features/expense/providers/quick_add_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

import '../../support/expense_harness.dart';

/// The capture path's contract: one required field, everything else optional, and a rejection that
/// says so out loud rather than doing nothing (Laws U9 and U11).
void main() {
  List<Override> overrides({List<Account> accounts = const [kAccount]}) => [
    homeCurrencyCodeProvider.overrideWith((ref) => 'INR'),
    homeDecimalDigitsProvider.overrideWith((ref) => 2),
    selectableAccountsProvider.overrideWith((ref) => Stream.value(accounts)),
    quickAddTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
  ];

  Widget host() => Scaffold(
    body: AlayaBottomSheet(child: const QuickAddSheet()),
  );

  testWidgets('renders with exactly one required field', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides());
    expect(find.byType(AmountField), findsOneWidget);
    expect(find.text('Quick add'), findsOneWidget);
  });

  testWidgets('offers accounts as chips, never a dropdown', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides());
    expect(find.byType(ChoiceChip), findsWidgets);
    expect(find.byType(DropdownButtonFormField<Account>), findsNothing);
  });

  testWidgets('an empty account list simply omits the chip row', (
    tester,
  ) async {
    await pumpExpense(tester, host(), overrides: overrides(accounts: const []));
    expect(find.text('Account'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saving with no amount shakes and says why, rather than doing nothing',
    (tester) async {
      await pumpExpense(tester, host(), overrides: overrides());
      final before = tester
          .widget<ShakeOnError>(find.byType(ShakeOnError))
          .trigger;

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();

      final after = tester
          .widget<ShakeOnError>(find.byType(ShakeOnError))
          .trigger;
      expect(after, greaterThan(before));
      expect(find.text('Enter an amount'), findsOneWidget);
    },
  );

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides(), textScale: 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target floor', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpExpense(tester, host(), overrides: overrides());
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });
}
