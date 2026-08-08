import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:alaya/features/inventory/presentation/widgets/item_row.dart';
import 'package:alaya/features/inventory/providers/inventory_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/inventory_harness.dart';

/// Four states, 320dp at a doubled text scale, and both accessibility floors (ARCH_5 §9.1).
void main() {
  List<Override> overrides(AsyncValue<List<InventoryGroup>> groups) => [
    clockProvider.overrideWithValue(kInventoryClock),
    inventoryGroupsProvider.overrideWith((ref) => groups),
    itemStocksProvider.overrideWith(
      (ref) => Stream.value(<String, ItemStock>{kItem.id: kStock}),
    ),
    lowStockCountProvider.overrideWith((ref) => 0),
  ];

  final populated = AsyncValue.data([
    InventoryGroup(items: const [kItem], kind: kItem.itemKind),
  ]);

  testWidgets('loading shows a skeleton, not a spinner', (tester) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('empty invites the user to add rather than reporting emptiness', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(const AsyncValue.data([])),
    );
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Add item'), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('populated renders a row showing the summed mixed-unit total', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(populated),
    );
    expect(find.byType(ItemRow), findsOneWidget);
    expect(find.text('Atta'), findsOneWidget);
    // ARCH_1 §5.4's worked example: 250 + 2000 + 1500 + 700 grams is 4 kg 450 g, not 2 kg 450 g.
    expect(find.text('4 kg 450 g'), findsOneWidget);
  });

  testWidgets('the group header names the kind, not the table', (tester) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(populated),
    );
    expect(find.text('Food'), findsOneWidget);
  });

  testWidgets('search is a pinned field, never an app-bar icon', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(populated),
    );
    expect(find.text('Search items'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.search),
      ),
      findsNothing,
    );
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(populated),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(populated),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
