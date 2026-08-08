import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/presentation/screens/item_editor_screen.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/inventory/state/item_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';

import '../../support/inventory_harness.dart';

/// Four states, plus the Law this screen exists to enforce: `unitCategory` is read-only on edit.
void main() {
  ItemEditorState seed({String? id}) => ItemEditorState(
    id: id,
    name: id == null ? '' : 'Atta',
    unitCategory: UnitCategory.weight,
    displayUnitCode: 'kg',
  );

  // The override goes on the **family**, not on an instance of it: a NotifierProvider family
  // instance has no `overrideWith`, unlike a FutureProvider or StreamProvider instance.
  List<Override> overrides(AsyncValue<ItemEditorState> state) => [
    itemEditorProvider.overrideWith(() => _StubEditor(state)),
    unitsInCategoryProvider(
      UnitCategory.weight,
    ).overrideWith((ref) => Stream.value(<Unit>[kKilogram, kGram])),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('error reads as not found rather than as a blank form', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('a new item opens on the form, which is its empty state', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
    );
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save item'), findsOneWidget);
  });

  testWidgets('creating offers the measure as a control', (tester) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
    );
    expect(find.byType(DropdownButtonFormField<UnitCategory>), findsOneWidget);
    expect(find.byType(KeyValueRow), findsNothing);
  });

  testWidgets('editing locks the measure and says why', (tester) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(itemId: 'item-1'),
      overrides: [
        itemEditorProvider.overrideWith(
          () => _StubEditor(AsyncValue.data(seed(id: 'item-1'))),
        ),
        unitsInCategoryProvider(
          UnitCategory.weight,
        ).overrideWith((ref) => Stream.value(<Unit>[kKilogram, kGram])),
      ],
    );
    // Law L8: no control at all, not a disabled one — and the reason is on screen, because a lock
    // without an explanation reads as a bug.
    expect(find.byType(DropdownButtonFormField<UnitCategory>), findsNothing);
    expect(find.text('Measured in Weight'), findsOneWidget);
    expect(
      find.textContaining('no conversion between weight, volume and count'),
      findsOneWidget,
    );
  });

  testWidgets('the commit lives in the footer, never in the app bar', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
    );
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(TextButton, 'Save item'),
      ),
      findsNothing,
    );
    expect(find.byType(CloseButton), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubEditor extends ItemEditorNotifier {
  _StubEditor(this._state);

  final AsyncValue<ItemEditorState> _state;

  @override
  AsyncValue<ItemEditorState> build(String? arg) => _state;
}
