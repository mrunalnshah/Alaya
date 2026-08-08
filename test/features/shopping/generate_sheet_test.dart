import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/features/shopping/presentation/sheets/generate_sheet.dart';
import 'package:alaya/features/shopping/providers/generate_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';

import '../../support/shopping_harness.dart';

/// Four states, plus the shortfall figure and the per-row snooze and dismiss.
void main() {
  List<Override> overrides({
    List<ShoppingEntry>? entries,
    bool pending = false,
    bool fail = false,
  }) => [
    clockProvider.overrideWithValue(kShoppingClock),
    shoppingItemsByIdProvider.overrideWith(
      (ref) => Stream.value(<String, Item>{kOnion.id: kOnion}),
    ),
    if (pending)
      entriesProvider(
        kList.id,
      ).overrideWith((ref) => pendingStream<List<ShoppingEntry>>())
    else if (fail)
      entriesProvider(kList.id).overrideWith(
        (ref) => Stream<List<ShoppingEntry>>.error(StateError('boom')),
      )
    else
      entriesProvider(
        kList.id,
      ).overrideWith((ref) => Stream.value(entries ?? const [])),
  ];

  Widget host() => const Scaffold(
    body: AlayaBottomSheet(child: GenerateSheet(listId: 'list-1')),
  );

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpShopping(tester, host(), overrides: overrides(pending: true));
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('empty explains what would make a suggestion appear', (
    tester,
  ) async {
    await pumpShopping(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nothing is running low'), findsOneWidget);
  });

  testWidgets('error is reported without hiding the refresh', (tester) async {
    await pumpShopping(tester, host(), overrides: overrides(fail: true));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
  });

  testWidgets('a suggestion shows the shortfall that produced it', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(entries: [sampleSuggestion()]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Onion'), findsOneWidget);
    expect(find.text('Short by'), findsOneWidget);
    // threshold 2 kg minus 500 g on hand at generation. Read from the entry's own history, not from
    // live stock, so the figure cannot drift between the sheet opening and the user acting.
    expect(find.byType(QtyText), findsWidgets);
    expect(find.text('1 kg 500 g'), findsOneWidget);
  });

  testWidgets('each suggestion is snoozed or dismissed on its own', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        entries: [
          sampleSuggestion(),
          sampleSuggestion(id: 'auto-2'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Snooze a week'), findsNWidgets(2));
    expect(find.text('Not now'), findsNWidgets(2));
  });

  testWidgets('a manual entry never appears as a suggestion', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(entries: [sampleEntry()]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing is running low'), findsOneWidget);
    expect(find.text('Television'), findsNothing);
  });

  testWidgets('a dismissed suggestion still lists here so it can be reconsidered', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        entries: [
          sampleSuggestion(autoState: ShoppingEntryAutoState.dismissed),
        ],
      ),
    );
    await tester.pumpAndSettle();
    // The list screen hides it via `isVisibleAsOf`; this sheet is where the user manages
    // suggestions, so hiding it here would leave no way to see what was turned down.
    expect(find.text('Onion'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(entries: [sampleSuggestion()]),
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
      overrides: overrides(entries: [sampleSuggestion()]),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
