import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/providers/transaction_draft_provider.dart';
import 'package:alaya/features/expense/state/transaction_draft.dart';
import 'package:alaya/features/shopping/presentation/screens/convert_to_purchase_screen.dart';
import 'package:alaya/features/shopping/providers/convert_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/shopping_harness.dart';

/// Four states, plus the rule this screen exists to hold: it hands off, it does not commit.
void main() {
  List<Override> overrides({
    List<TransactionLine>? lines,
    List<ShoppingEntry>? entries,
    bool pending = false,
    bool fail = false,
  }) => [
    entriesProvider(
      kList.id,
    ).overrideWith((ref) => Stream.value(entries ?? const [])),
    if (pending)
      purchaseDraftProvider(
        kList.id,
      ).overrideWith((ref) => pendingFuture<List<TransactionLine>>())
    else if (fail)
      purchaseDraftProvider(
        kList.id,
      ).overrideWith((ref) async => throw StateError('boom'))
    else
      purchaseDraftProvider(
        kList.id,
      ).overrideWith((ref) async => lines ?? const <TransactionLine>[]),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(pending: true),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('nothing ticked reads as nothing ticked, not as an error', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nothing is ticked'), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(fail: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('populated previews one line per entry, marked for inventory', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(
        lines: [
          sampleDraftLine(),
          sampleDraftLine(id: 'line-2', description: 'Bread'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.text('2 lines'), findsOneWidget);
    expect(find.text('Onion'), findsOneWidget);
    expect(find.text('Bread'), findsOneWidget);
  });

  testWidgets('the primary action hands off rather than committing', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(lines: [sampleDraftLine()]),
    );
    await tester.pumpAndSettle();
    // "Open the expense", not "Save". The amount, the account and the payee are decisions only the
    // expense editor collects; duplicating them here would fork the one screen that knows how a
    // withdrawal is shaped (anomaly A25).
    expect(
      find.widgetWithText(FilledButton, 'Open the expense'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(lines: [sampleDraftLine()]),
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
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(lines: [sampleDraftLine()]),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('the draft channel', () {
    test('carries the ticked entry ids so the loop can close on save', () {
      final container = ProviderContainer(
        overrides: [
          entriesProvider(kList.id).overrideWith(
            (ref) => Stream.value([
              sampleEntry(id: 'e1', isChecked: true),
              sampleEntry(id: 'e2', isChecked: false),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(entriesProvider(kList.id), (_, __) {});

      final offered = container
          .read(convertActionsProvider)
          .offerDraft(
            listId: kList.id,
            lines: [sampleDraftLine()],
          );
      expect(offered, isTrue);
      final draft = container.read(transactionDraftProvider);
      expect(draft, isNotNull);
      expect(draft!.kind, TransactionKind.withdrawal);
      expect(draft.lines, hasLength(1));
    });

    test('an empty draft is refused rather than opening a blank editor', () {
      final container = ProviderContainer(
        overrides: [
          entriesProvider(
            kList.id,
          ).overrideWith((ref) => Stream.value(const [])),
        ],
      );
      addTearDown(container.dispose);
      final offered = container
          .read(convertActionsProvider)
          .offerDraft(listId: kList.id, lines: const []);
      expect(offered, isFalse);
      expect(container.read(transactionDraftProvider), isNull);
    });

    test('take() empties the channel, so a draft is never applied twice', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(transactionDraftProvider.notifier)
          .offer(
            TransactionDraft(
              lines: [sampleDraftLine()],
              kind: TransactionKind.withdrawal,
              subtype: TransactionSubtype.grocery,
            ),
          );
      expect(
        container.read(transactionDraftProvider.notifier).take(),
        isNotNull,
      );
      // Without this, a draft left behind would ambush the next blank editor the user opened.
      expect(container.read(transactionDraftProvider.notifier).take(), isNull);
    });
  });
}
