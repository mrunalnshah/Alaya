import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/shopping/presentation/sheets/entry_editor_sheet.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/state/entry_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/qty_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

import '../../support/shopping_harness.dart';

/// Four states, plus the rule this sheet exists to hold: `itemId` is optional, and an entry needs
/// only one of a name or a link to identify itself.
void main() {
  // The override goes on the **family**: a NotifierProvider family instance has no `overrideWith`,
  // unlike a FutureProvider or StreamProvider instance.
  List<Override> overrides(
    AsyncValue<EntryEditorState> state, {
    List<Item> items = const [kOnion],
  }) => [
    entryEditorProvider.overrideWith(() => _StubEntryEditor(state)),
    entryItemsProvider.overrideWith((ref) => Stream.value(items)),
    entryTagsProvider.overrideWith(
      (ref) => Stream.value(const <Tag>[kProduceTag]),
    ),
    entryUnitsProvider(
      UnitCategory.weight,
    ).overrideWith((ref) => Stream.value(const <Unit>[kKilogram])),
    entryUnitsProvider(
      null,
    ).overrideWith((ref) => Stream.value(const <Unit>[])),
    entryCurrencyProvider.overrideWith((ref) async => 'INR'),
    entryDecimalDigitsProvider.overrideWith((ref) async => 2),
  ];

  Widget host() => const Scaffold(
    body: AlayaBottomSheet(child: EntryEditorSheet(listId: 'list-1')),
  );

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('error reads as not found', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('a new entry opens on the form, which is its empty state', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        const AsyncValue.data(EntryEditorState(listId: 'list-1')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('What do you need?'), findsOneWidget);
    expect(find.text('Name it'), findsOneWidget);
  });

  testWidgets('free text alone is enough — no inventory item required', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        const AsyncValue.data(
          EntryEditorState(listId: 'list-1', freeText: 'Television'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // A television belongs on a list and has no place in an inventory measuring flour by the gram,
    // so the item link stays optional and the quantity field stays hidden without one.
    expect(find.text('Not in my inventory'), findsOneWidget);
    expect(find.byType(QtyField), findsNothing);
  });

  testWidgets('linking an item reveals a category-filtered quantity', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        const AsyncValue.data(
          EntryEditorState(listId: 'list-1', itemId: 'item-1', unitCode: 'kg'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Law L8: a Qty is an integer plus a UnitCategory, and the category comes from the item.
    expect(find.byType(QtyField), findsOneWidget);
  });

  testWidgets('saving with neither a name nor an item shakes and says why', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        const AsyncValue.data(
          EntryEditorState(
            listId: 'list-1',
            identityMissing: true,
            shakeTrigger: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ShakeOnError), findsOneWidget);
    expect(find.text('Give it a name, or link it to an item'), findsOneWidget);
  });

  testWidgets('an empty catalogue still lets an entry be created', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        const AsyncValue.data(EntryEditorState(listId: 'list-1')),
        items: const [],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Name it'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        const AsyncValue.data(
          EntryEditorState(listId: 'list-1', itemId: 'item-1', unitCode: 'kg'),
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
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        const AsyncValue.data(EntryEditorState(listId: 'list-1')),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('promotion', () {
    test(
      'editing an auto entry promotes it to manual and never auto-removes it',
      () {
        final promoted = EntryEditorState.fromEntry(
          sampleSuggestion(),
        ).copyWith(freeText: 'Onions, the big ones').toEntry(newId: 'unused');
        // Anomaly A23: a suggestion the user has shaped is theirs. `origin` is what the regeneration
        // engine keys that decision on, so the promotion happens in `toEntry` rather than being left
        // to whichever call site remembers.
        expect(promoted.origin, ShoppingEntryOrigin.manual);
        expect(promoted.autoState, ShoppingEntryAutoState.active);
        expect(promoted.isAutoGenerated, isFalse);
      },
    );

    test('a new manual entry is not promoted from anything', () {
      final made = const EntryEditorState(
        listId: 'list-1',
        freeText: 'Television',
      ).toEntry(newId: 'entry-9');
      expect(made.origin, ShoppingEntryOrigin.manual);
      expect(made.itemId, isNull);
      expect(made.freeText, 'Television');
    });
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubEntryEditor extends EntryEditorNotifier {
  _StubEntryEditor(this._state);

  final AsyncValue<EntryEditorState> _state;

  @override
  AsyncValue<EntryEditorState> build(EntryEditorArgs arg) => _state;
}
