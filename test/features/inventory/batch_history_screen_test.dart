import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_history_screen.dart';
import 'package:alaya/features/inventory/providers/batch_history_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_timeline.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/inventory_harness.dart';

/// Four states, plus the append-only rule: a reversal marks the original rather than removing it.
void main() {
  const batchId = 'batch-1';

  List<Override> overrides({
    List<StockMovement>? movements,
    bool pending = false,
    bool fail = false,
  }) => [
    if (pending)
      batchMovementsProvider(
        batchId,
      ).overrideWith((ref) => pendingStream<List<StockMovement>>())
    else if (fail)
      batchMovementsProvider(
        batchId,
      ).overrideWith((ref) => Stream.error(StateError('boom')))
    else
      batchMovementsProvider(
        batchId,
      ).overrideWith((ref) => Stream.value(movements ?? const [])),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpInventory(
      tester,
      const BatchHistoryScreen(itemId: 'item-1', batchId: batchId),
      overrides: overrides(pending: true),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('empty explains what will appear here', (tester) async {
    await pumpInventory(
      tester,
      const BatchHistoryScreen(itemId: 'item-1', batchId: batchId),
      overrides: overrides(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nothing recorded yet'), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpInventory(
      tester,
      const BatchHistoryScreen(itemId: 'item-1', batchId: batchId),
      overrides: overrides(fail: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('populated renders a timeline naming each movement kind', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const BatchHistoryScreen(itemId: 'item-1', batchId: batchId),
      overrides: overrides(
        movements: [
          sampleMovement(
            id: 'mv-2',
            kind: StockMovementKind.waste,
            reason: 'Mouldy',
          ),
          sampleMovement(kind: StockMovementKind.purchaseIn),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaTimeline), findsOneWidget);
    expect(find.text('Thrown away'), findsOneWidget);
    expect(find.text('Bought'), findsOneWidget);
    expect(find.text('Mouldy'), findsOneWidget);
  });

  testWidgets('a reversed movement is marked, and both rows stay', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const BatchHistoryScreen(itemId: 'item-1', batchId: batchId),
      overrides: overrides(
        movements: [
          sampleMovement(
            id: 'mv-2',
            kind: StockMovementKind.adjustIn,
            reverses: 'mv-1',
          ),
          sampleMovement(),
        ],
      ),
    );
    await tester.pumpAndSettle();
    // `stock_movements` is append-only (Law L6): the correction points back, the original is struck
    // through, and neither is erased.
    expect(find.text('Reversed'), findsOneWidget);
    expect(find.text('Reverses an earlier movement'), findsOneWidget);
    expect(find.text('Used'), findsOneWidget);
    expect(find.text('Adjusted up'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpInventory(
      tester,
      const BatchHistoryScreen(itemId: 'item-1', batchId: batchId),
      overrides: overrides(
        movements: [
          sampleMovement(
            id: 'mv-2',
            kind: StockMovementKind.waste,
            reason: 'Left out overnight',
          ),
          sampleMovement(),
        ],
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
