import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/presentation/sheets/consume_sheet.dart';
import 'package:alaya/features/inventory/providers/consume_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/inventory/state/consume_state.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/qty_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

import '../../support/inventory_harness.dart';

/// The capture path's contract: one required field, FEFO named and overridable, and a multi-batch
/// draw declared before it is committed.
void main() {
  List<Override> overrides({List<Batch> fefo = const []}) => [
    consumeFefoProvider(kItem.id).overrideWith((ref) => Stream.value(fefo)),
    unitsInCategoryProvider(
      UnitCategory.weight,
    ).overrideWith((ref) => Stream.value(<Unit>[kKilogram, kGram])),
  ];

  Widget host() => Scaffold(
    body: AlayaBottomSheet(
      child: ConsumeSheet(
        itemId: kItem.id,
        unitCode: 'kg',
        category: UnitCategory.weight,
      ),
    ),
  );

  testWidgets('renders with exactly one required field', (tester) async {
    await pumpInventory(tester, host(), overrides: overrides());
    expect(find.byType(QtyField), findsOneWidget);
    expect(find.text('Use stock'), findsOneWidget);
  });

  testWidgets('offers used, thrown away and expired as three distinct kinds', (
    tester,
  ) async {
    await pumpInventory(tester, host(), overrides: overrides());
    // Three `StockMovementKind`s, not one kind plus a reason string: Phase 7B's waste insight
    // aggregates on the column and cannot read prose.
    expect(find.text('Used'), findsOneWidget);
    expect(find.text('Thrown away'), findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
  });

  testWidgets('an empty batch list simply omits the chip row', (tester) async {
    await pumpInventory(tester, host(), overrides: overrides());
    expect(find.text('Taking from'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FEFO names the batch it will draw from and offers the rest', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      host(),
      overrides: overrides(
        fefo: [
          sampleBatch(id: 'b1', expiry: const DateKey(20260805)),
          sampleBatch(id: 'b2', expiry: const DateKey(20260901)),
        ],
      ),
    );
    expect(find.text('Taking from'), findsOneWidget);
    expect(find.text('Oldest expiry first.'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(2));
  });

  testWidgets('committing with no quantity shakes and says why', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      host(),
      overrides: overrides(fefo: [sampleBatch()]),
    );
    final before = tester
        .widget<ShakeOnError>(find.byType(ShakeOnError))
        .trigger;

    await tester.tap(find.text('Record as used'));
    await tester.pump();

    final after = tester
        .widget<ShakeOnError>(find.byType(ShakeOnError))
        .trigger;
    expect(after, greaterThan(before));
    expect(find.text('Enter a quantity'), findsOneWidget);
  });

  testWidgets('a draw spanning batches is declared before it is committed', (
    tester,
  ) async {
    // Three 1 kg jars and a 2.5 kg draw: the plan crosses three batches, so three movements will be
    // appended and the sheet must say so up front rather than in the history afterwards.
    final container = ProviderContainer(
      overrides: [
        unitsInCategoryProvider(
          UnitCategory.weight,
        ).overrideWith((ref) => Stream.value(<Unit>[kKilogram, kGram])),
      ],
    );
    addTearDown(container.dispose);

    const state = ConsumeState(
      itemId: 'item-1',
      unitCode: 'kg',
      quantity: Qty(2500000, UnitCategory.weight),
    );
    final jars = [
      sampleBatch(id: 'b1', remainingMilli: 1000000),
      sampleBatch(id: 'b2', remainingMilli: 1000000),
      sampleBatch(id: 'b3', remainingMilli: 1000000),
    ];

    final plan = state.planAgainst(jars);
    expect(plan, hasLength(3));
    expect(plan.last.quantity, const Qty(500000, UnitCategory.weight));
    expect(state.shortfallAgainst(jars), isNull);
  });

  testWidgets('a draw larger than the shelf reports a shortfall', (
    tester,
  ) async {
    const state = ConsumeState(
      itemId: 'item-1',
      unitCode: 'kg',
      quantity: Qty(5000000, UnitCategory.weight),
    );
    final jars = [sampleBatch(id: 'b1', remainingMilli: 1000000)];
    expect(
      state.shortfallAgainst(jars),
      const Qty(4000000, UnitCategory.weight),
    );
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpInventory(
      tester,
      host(),
      overrides: overrides(fefo: [sampleBatch()]),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target floor', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpInventory(
      tester,
      host(),
      overrides: overrides(fefo: [sampleBatch()]),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });
}
