import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/features/shopping/presentation/sheets/list_manager_sheet.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/shopping_harness.dart';

/// Four states, plus the retirement rule: a list is archived, never deleted.
void main() {
  List<Override> overrides({
    List<ShoppingList>? lists,
    bool pending = false,
    bool fail = false,
  }) => [
    if (pending)
      allListsProvider.overrideWith(
        (ref) => pendingStream<List<ShoppingList>>(),
      )
    else if (fail)
      allListsProvider.overrideWith(
        (ref) => Stream<List<ShoppingList>>.error(StateError('boom')),
      )
    else
      allListsProvider.overrideWith((ref) => Stream.value(lists ?? const [])),
  ];

  Widget host() => const Scaffold(
    body: AlayaBottomSheet(child: ListManagerSheet()),
  );

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpShopping(tester, host(), overrides: overrides(pending: true));
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('empty invites the first list, which becomes the default', (
    tester,
  ) async {
    await pumpShopping(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'New list'), findsOneWidget);
  });

  testWidgets('error is reported', (tester) async {
    await pumpShopping(tester, host(), overrides: overrides(fail: true));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('populated marks the default and separates the archived', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(lists: const [kList, kArchivedList]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Weekly shop'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Diwali'), findsOneWidget);
    expect(find.text('Archived'), findsNWidgets(2));
  });

  testWidgets('retiring a list archives it rather than deleting it', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(lists: const [kList]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    // A converted list is the provenance of those transaction lines, so it is hidden, not removed
    // (Law L6). There is no delete in this menu at all.
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('the default list is not offered "make default" again', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(lists: const [kList]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    expect(find.text('Make default'), findsNothing);
    expect(find.text('Rename'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(lists: const [kList, kArchivedList]),
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
      overrides: overrides(lists: const [kList]),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
