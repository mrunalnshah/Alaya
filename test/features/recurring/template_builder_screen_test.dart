import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/services/recurring_engine.dart';
import 'package:alaya/features/recurring/presentation/screens/template_builder_screen.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/features/recurring/state/template_builder_state.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/frequency_preview.dart';

import '../../support/recurring_harness.dart';

/// Four states, plus the reason this screen exists: the preview is the only way a user can see a clamp.
void main() {
  TemplateBuilderState state({
    String name = 'Rent',
    int? amountMinor = 120000,
    RecurringIntervalUnit unit = RecurringIntervalUnit.month,
    int? anchorDayOfMonth = 31,
    DateKey start = const DateKey(20260131),
    DateKey? end,
    TemplateSaveIssue? issue,
    String? rejection,
  }) => TemplateBuilderState(
    currencyCode: 'INR',
    startDateKey: start,
    name: name,
    amount: amountMinor == null ? null : Money(amountMinor, 'INR'),
    intervalUnit: unit,
    anchorDayOfMonth: anchorDayOfMonth,
    endDateKey: end,
    issue: issue,
    rejection: rejection,
  );

  // The override goes on the **family**: a NotifierProvider family instance has no `overrideWith`.
  List<Override> overrides(AsyncValue<TemplateBuilderState> value) => [
    templateBuilderProvider.overrideWith(() => _StubBuilder(value)),
    builderDecimalDigitsProvider.overrideWith((ref) async => 2),
    builderAccountsProvider.overrideWith(
      (ref) => Stream.value(const [kAccount]),
    ),
    recurringEngineProvider.overrideWithValue(const RecurringEngine()),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('error reads as not found', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('a new template opens on the form, which is its empty state', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(AsyncValue.data(state(name: '', amountMinor: null))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
  });

  testWidgets('the preview shows the anchor clamping and returning', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    // Anchored on the 31st from 31 January: Jan 31 → Feb 28 → Mar 31. February is shortened and March
    // returns to the 31st — the anchor never walks backwards (anomaly A13), and this is the only place
    // a user can see that happening.
    expect(find.byType(FrequencyPreview), findsOneWidget);
    expect(find.text('Shortened to fit the month'), findsOneWidget);
  });

  testWidgets('a weekly template never reports a clamp', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(unit: RecurringIntervalUnit.week, anchorDayOfMonth: null),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Only a monthly or yearly interval anchors to a day, so there is nothing to clamp.
    expect(find.text('Shortened to fit the month'), findsNothing);
    expect(find.text('On day of the month'), findsNothing);
  });

  testWidgets('an incomplete template previews nothing rather than a guess', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(AsyncValue.data(state(name: '', amountMinor: null))),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Set a start date to see when this lands.'),
      findsOneWidget,
    );
  });

  testWidgets('an end date truncates the preview instead of promising three', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(
        AsyncValue.data(state(end: const DateKey(20260215))),
      ),
    );
    await tester.pumpAndSettle();
    // Ends mid-February, so only 31 January survives. Showing three would describe a schedule that
    // will not happen.
    expect(find.byType(FrequencyPreview), findsOneWidget);
    expect(find.text('Shortened to fit the month'), findsNothing);
  });

  testWidgets('a rejection is shown in the repository own words', (
    tester,
  ) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(
            issue: TemplateSaveIssue.rejected,
            rejection:
                'A monthly template needs a day of the month to anchor to.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('needs a day of the month'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(AsyncValue.data(state())),
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
      const TemplateBuilderScreen(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('the clamp itself', () {
    const engine = RecurringEngine();

    test(
      'an anchor of 31 lands on the last day of a short month and then returns',
      () {
        final template = billTemplate(nextDue: const DateKey(20260131));
        final feb = engine.nextDue(
          from: const DateKey(20260131),
          template: template,
        );
        final mar = engine.nextDue(from: feb, template: template);
        expect(feb, const DateKey(20260228));
        // The point of storing the anchor rather than advancing it: March returns to the 31st instead of
        // inheriting February's 28 forever.
        expect(mar, const DateKey(20260331));
      },
    );

    test('a February anchor survives a leap year', () {
      expect(engine.clampDayOfMonth(31, 2028, 2), 29);
      expect(engine.clampDayOfMonth(31, 2026, 2), 28);
      expect(engine.clampDayOfMonth(15, 2026, 2), 15);
    });
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubBuilder extends TemplateBuilderNotifier {
  _StubBuilder(this._value);

  final AsyncValue<TemplateBuilderState> _value;

  @override
  AsyncValue<TemplateBuilderState> build(String? arg) => _value;
}
