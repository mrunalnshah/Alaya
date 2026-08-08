import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/presentation/screens/item_detail_screen.dart';
import 'package:alaya/features/inventory/presentation/widgets/batch_card.dart';
import 'package:alaya/features/inventory/providers/item_detail_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';

import '../../support/inventory_harness.dart';

/// Four states, plus the two rules this screen exists to demonstrate: the hero is the summed total,
/// and a detached batch explains itself.
void main() {
  const id = 'item-1';

  List<Override> overrides({
    Item? item = kItem,
    List<Batch> batches = const [],
    bool pendingItem = false,
    bool failItem = false,
  }) => [
    clockProvider.overrideWithValue(kInventoryClock),
    // `itemByIdProvider` is a synchronous `Provider<AsyncValue<Item?>>` derived from the
    // catalogue stream, so each state is handed over directly rather than as a Future.
    if (pendingItem)
      itemByIdProvider(id).overrideWith((ref) => const AsyncValue.loading())
    else if (failItem)
      itemByIdProvider(id).overrideWith(
        (ref) => AsyncValue.error(StateError('boom'), StackTrace.empty),
      )
    else
      itemByIdProvider(id).overrideWith((ref) => AsyncValue.data(item)),
    itemStockProvider(id).overrideWith((ref) => Stream.value(kStock)),
    itemBatchesProvider(id).overrideWith((ref) => Stream.value(batches)),
    detailUnitsByCodeProvider.overrideWith(
      (ref) => Stream.value(<String, Unit>{'kg': kKilogram, 'g': kGram}),
    ),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(pendingItem: true),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('a missing item reads as not found, not as a crash', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(item: null),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Not found'), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(failItem: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('the hero is the summed mixed-unit total across every batch', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(batches: [sampleBatch()]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Atta'), findsOneWidget);
    expect(find.text('4 kg 450 g'), findsOneWidget);
    expect(find.byType(BatchCard), findsOneWidget);
  });

  testWidgets('a null value hides its row rather than rendering a dash', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(batches: [sampleBatch()]),
    );
    await tester.pumpAndSettle();
    // kItem has no notes and no low-stock threshold, so neither row exists at all.
    expect(find.text('Note'), findsNothing);
    expect(find.text('Low-stock level'), findsNothing);
    expect(find.byType(KeyValueRow), findsWidgets);
  });

  testWidgets('a detached batch says the receipt is gone', (tester) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(
        batches: [sampleBatch(origin: BatchOrigin.detached)],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Receipt deleted'), findsOneWidget);
  });

  testWidgets('the destructive action is present and is not a filled button', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(batches: [sampleBatch()]),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Delete item'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Delete item'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Delete item'), findsNothing);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(batches: [sampleBatch()]),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(batches: [sampleBatch()]),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
