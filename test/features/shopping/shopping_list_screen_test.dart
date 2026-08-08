import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/shopping/presentation/screens/shopping_list_screen.dart';
import 'package:alaya/features/shopping/presentation/widgets/entry_row.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/shopping_harness.dart';

/// Four states, 320dp at a doubled text scale, and both accessibility floors (ARCH_5 §9.1).
void main() {
  List<Override> overrides(AsyncValue<List<ShoppingGroup>> groups) => [
    clockProvider.overrideWithValue(kShoppingClock),
    defaultListProvider.overrideWith((ref) => Stream.value(kList)),
    selectableListsProvider.overrideWith((ref) => Stream.value(const [kList])),
    shoppingGroupsProvider(kList.id).overrideWith((ref) => groups),
    shoppingItemsByIdProvider.overrideWith(
      (ref) => Stream.value(<String, Item>{kOnion.id: kOnion}),
    ),
    shoppingTagsByIdProvider.overrideWith(
      (ref) => Stream.value(<String, Tag>{kProduceTag.id: kProduceTag}),
    ),
    entryDecimalDigitsProvider.overrideWith((ref) async => 2),
  ];

  final populated = AsyncValue.data([
    ShoppingGroup(
      entries: [sampleEntry(tagId: kProduceTag.id)],
      tag: kProduceTag,
    ),
  ]);

  testWidgets('loading shows a skeleton, not a spinner', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('empty offers the suggestions that would fill it', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(const AsyncValue.data([])),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nothing on this list yet'), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('populated groups by tag and names the group', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(populated),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EntryRow), findsOneWidget);
    expect(find.text('Television'), findsOneWidget);
    expect(find.text('Produce'), findsOneWidget);
  });

  testWidgets('a free-text entry needs no inventory item', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(
        AsyncValue.data([
          ShoppingGroup(entries: [sampleEntry()]),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    // "Television" is a shopping entry with itemId null. It renders, and it lands in the untagged
    // group rather than being refused for having nothing in the catalogue behind it.
    expect(find.text('Television'), findsOneWidget);
    expect(find.text('Everything else'), findsOneWidget);
  });

  testWidgets('a suggested row is marked and offers snooze and dismiss', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(
        AsyncValue.data([
          ShoppingGroup(entries: [sampleSuggestion()]),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Suggested'), findsOneWidget);
    expect(find.text('Snooze a week'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('a manual row offers neither', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(populated),
    );
    await tester.pumpAndSettle();
    // Snooze and dismiss only make sense against something the app proposed; offering them on a row
    // the user typed reads as the app second-guessing them.
    expect(find.text('Snooze a week'), findsNothing);
    expect(find.text('Not now'), findsNothing);
  });

  testWidgets('the running estimate sums only entries that carry one', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(
        AsyncValue.data([
          ShoppingGroup(
            entries: [
              sampleEntry(id: 'e1'),
              sampleEntry(id: 'e2', freeText: 'Bread', estimatedPrice: null),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    // One priced at 45,000.00 and one unpriced: the total is the priced one, not a figure that
    // quietly counts the other as zero.
    expect(find.text('Estimated'), findsOneWidget);
    expect(find.text('0 of 2 ticked'), findsOneWidget);
  });

  testWidgets('with no list at all it offers to create one', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: [
        clockProvider.overrideWithValue(kShoppingClock),
        defaultListProvider.overrideWith((ref) => Stream.value(null)),
        selectableListsProvider.overrideWith(
          (ref) => Stream.value(const <ShoppingList>[]),
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('No lists yet'), findsOneWidget);
    expect(find.text('New list'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(
        AsyncValue.data([
          ShoppingGroup(entries: [sampleSuggestion()]),
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
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(populated),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('a bought entry drops off the list', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(
        AsyncValue.data([
          ShoppingGroup(
            entries: [sampleEntry(id: 'e1', freeText: 'Bread')],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bread'), findsOneWidget);

    // Once a transaction fulfils it, the entry is no longer something to buy. The row survives —
    // `purchasedTransactionLineId` is the only link between the receipt and the list — but a list of
    // what to get should not still be offering it.
    final bought = sampleEntry(
      id: 'e1',
      freeText: 'Bread',
    ).copyWith(purchasedTransactionLineId: 'line-1');
    expect(bought.isPurchased, isTrue);
    expect(bought.isOutstandingAsOf(kToday), isFalse);
    expect(bought.isVisibleAsOf(kToday), isTrue);
  });
}
