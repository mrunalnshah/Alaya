import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/features/recurring/presentation/screens/occurrence_history_screen.dart';
import 'package:alaya/features/recurring/providers/occurrence_history_providers.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/features/recurring/providers/template_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_timeline.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/recurring_harness.dart';

/// Four states, plus the §7.2 row: the actual against the usual, where they differ.
void main() {
  const templateId = 'tpl-1';

  List<Override> overrides({
    RecurringTemplate? template,
    List<RecurringOccurrence>? occurrences,
    bool pending = false,
    bool fail = false,
  }) => [
    clockProvider.overrideWithValue(kRecurringClock),
    builderDecimalDigitsProvider.overrideWith((ref) async => 2),
    historyTemplateProvider(
      templateId,
    ).overrideWith((ref) async => template ?? billTemplate()),
    if (pending)
      occurrencesProvider(
        templateId,
      ).overrideWith((ref) => pendingStream<List<RecurringOccurrence>>())
    else if (fail)
      occurrencesProvider(templateId).overrideWith(
        (ref) => Stream<List<RecurringOccurrence>>.error(StateError('boom')),
      )
    else
      occurrencesProvider(
        templateId,
      ).overrideWith((ref) => Stream.value(occurrences ?? const [])),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(pending: true),
    );
    await tester.pump();
    expect(find.byType(AlayaListSkeleton), findsWidgets);
  });

  testWidgets('empty states plainly that nothing is ever paid for you', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    // Anomaly A14 said out loud: materialisation creates due rows, never payments.
    expect(find.textContaining('Nothing is ever paid for you'), findsOneWidget);
  });

  testWidgets('error shows the real reason with a retry', (tester) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(fail: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('populated renders a timeline of occurrences', (tester) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(
        occurrences: [
          occurrence(
            id: 'o1',
            dueDateKey: const DateKey(20260630),
            status: RecurringOccurrenceStatus.paid,
            paidMinor: 120000,
            paidTransactionId: 't1',
          ),
          occurrence(id: 'o2', dueDateKey: const DateKey(20260731)),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaTimeline), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
  });

  testWidgets('a payment that differed from the usual amount is marked', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(
        occurrences: [
          occurrence(
            id: 'o1',
            dueDateKey: const DateKey(20260630),
            status: RecurringOccurrenceStatus.paid,
            // Template default is 1,200.00; this one came in at 1,247.00.
            paidMinor: 124700,
            paidTransactionId: 't1',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Differed from the usual amount'), findsWidgets);
  });

  testWidgets('a payment at the usual amount is not marked', (tester) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(
        occurrences: [
          occurrence(
            id: 'o1',
            dueDateKey: const DateKey(20260630),
            status: RecurringOccurrenceStatus.paid,
            paidMinor: 120000,
            paidTransactionId: 't1',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Differed from the usual amount'), findsNothing);
  });

  testWidgets('a skipped occurrence reads as skipped, not as paid', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(
        occurrences: [
          occurrence(
            id: 'o1',
            dueDateKey: const DateKey(20260630),
            status: RecurringOccurrenceStatus.skipped,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Skipped'), findsOneWidget);
    expect(find.text('Paid'), findsNothing);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(
        occurrences: [
          occurrence(
            id: 'o1',
            dueDateKey: const DateKey(20260630),
            status: RecurringOccurrenceStatus.paid,
            paidMinor: 124700,
            paidTransactionId: 't1',
          ),
          occurrence(id: 'o2', dueDateKey: const DateKey(20260715)),
        ],
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
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(
        occurrences: [
          occurrence(id: 'o2', dueDateKey: const DateKey(20260731)),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
