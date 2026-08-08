import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_editor_screen.dart';
import 'package:alaya/features/inventory/providers/batch_editor_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/inventory/state/batch_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/qty_field.dart';

import '../../support/inventory_harness.dart';

/// Four states, plus Law L3: an existing batch's quantity is a derived cache, not a form field.
void main() {
  BatchEditorState seed({String? id}) => BatchEditorState(
    id: id,
    itemId: kItem.id,
    unitCode: 'kg',
    purchasedDateKey: kToday,
    quantity: id == null ? null : const Qty(2000000, UnitCategory.weight),
  );

  List<Override> overrides(AsyncValue<BatchEditorState> state) => [
    batchEditorProvider.overrideWith(() => _StubBatchEditor(state)),
    batchOwnerProvider(kItem.id).overrideWith((ref) async => kItem),
    batchCurrencyProvider.overrideWith((ref) async => 'INR'),
    batchDecimalDigitsProvider.overrideWith((ref) async => 2),
    unitsInCategoryProvider(
      UnitCategory.weight,
    ).overrideWith((ref) => Stream.value(<Unit>[kKilogram, kGram])),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('error reads as not found', (tester) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('adding a batch opens on the form with every §7.2 field', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id),
      overrides: overrides(AsyncValue.data(seed())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.byType(QtyField), findsOneWidget);
    expect(find.text('Expiry'), findsOneWidget);
    expect(find.text('Purchased'), findsOneWidget);
    expect(find.text('Unit cost'), findsOneWidget);
    expect(find.text('Stored in'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save batch'), findsOneWidget);
  });

  testWidgets('editing locks the quantity and says the ledger owns it', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id, batchId: 'batch-1'),
      overrides: overrides(AsyncValue.data(seed(id: 'batch-1'))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(QtyField), findsNothing);
    expect(find.byType(KeyValueRow), findsOneWidget);
    expect(
      find.textContaining('worked out from the movement history'),
      findsOneWidget,
    );
  });

  testWidgets('editing offers a retire path; adding does not', (tester) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id, batchId: 'batch-1'),
      overrides: overrides(AsyncValue.data(seed(id: 'batch-1'))),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Delete batch'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Delete batch'), findsNothing);

    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id),
      overrides: overrides(AsyncValue.data(seed())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete batch'), findsNothing);
  });

  testWidgets('the commit lives in the footer', (tester) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id),
      overrides: overrides(AsyncValue.data(seed())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CloseButton), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(TextButton, 'Save batch'),
      ),
      findsNothing,
    );
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id),
      overrides: overrides(AsyncValue.data(seed())),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

/// A notifier reporting a fixed state.
class _StubBatchEditor extends BatchEditorNotifier {
  _StubBatchEditor(this._state);

  final AsyncValue<BatchEditorState> _state;

  @override
  AsyncValue<BatchEditorState> build(BatchEditorArgs arg) => _state;
}
