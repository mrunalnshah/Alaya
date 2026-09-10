import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/features/recurring/presentation/screens/template_list_screen.dart';
import 'package:alaya/features/recurring/presentation/widgets/template_row.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/features/recurring/providers/template_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/recurring_harness.dart';

/// Four states, 320dp at a doubled text scale, and both accessibility floors (ARCH_5 §9.1).
void main() {
  List<Override> overrides(AsyncValue<List<TemplateGroup>> groups) => [
    clockProvider.overrideWithValue(kRecurringClock),
    templateGroupsProvider.overrideWith((ref) => groups),
    overdueCountProvider.overrideWith((ref) => 0),
    builderDecimalDigitsProvider.overrideWith((ref) async => 2),
  ];

  final outflow = AsyncValue.data([
    TemplateGroup(
      direction: RecurringDirection.outflow,
      rows: [TemplateRow(template: billTemplate(), next: occurrence())],
    ),
  ]);

  testWidgets('loading shows a skeleton, not a spinner', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('empty invites the first template', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(const AsyncValue.data([])),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nothing recurring yet'), findsOneWidget);
  });

  testWidgets('error shows the real reason with a retry', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('populated groups outflow under its own header', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(outflow),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TemplateRowTile), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Expenses'), findsOneWidget);
  });

  testWidgets('an inflow reads as income, not a negative bill', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(
        AsyncValue.data([
          TemplateGroup(
            direction: RecurringDirection.inflow,
            rows: [
              TemplateRow(
                template: salaryTemplate(),
                next: occurrence(id: 'occ-2', templateId: 'tpl-2'),
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    // Its own group, and the amount unsigned. A salary shown as minus eighty-five thousand under a
    // list of bills is the §7.2 row this module exists to close.
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);
    expect(find.textContaining('-'), findsNothing);
  });

  testWidgets('overdue is derived from the clock, not a stored flag', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(
        AsyncValue.data([
          TemplateGroup(
            direction: RecurringDirection.outflow,
            rows: [
              TemplateRow(
                template: billTemplate(),
                // Due in July, clock fixed to 1 August. Nothing on the entity says "overdue".
                next: occurrence(dueDateKey: const DateKey(20260715)),
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Overdue'), findsWidgets);
  });

  testWidgets('a paused template says so and offers no pay button', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(
        AsyncValue.data([
          TemplateGroup(
            direction: RecurringDirection.outflow,
            rows: [
              TemplateRow(
                template: billTemplate(isPaused: true),
                next: occurrence(),
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    // Nothing is paid while paused: an occurrence may exist, but the obligation is suspended.
    expect(find.widgetWithText(FilledButton, 'Record it'), findsNothing);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(
        AsyncValue.data([
          TemplateGroup(
            direction: RecurringDirection.outflow,
            rows: [
              TemplateRow(
                template: billTemplate(),
                next: occurrence(dueDateKey: const DateKey(20260715)),
              ),
            ],
          ),
        ]),
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
      const TemplateListScreen(),
      overrides: overrides(outflow),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
