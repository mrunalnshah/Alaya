import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/router/routes.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/features/calendar/presentation/widgets/calendar_event_list.dart';
import 'package:alaya/features/calendar/presentation/widgets/day_sheet.dart';
import 'package:alaya/features/calendar/presentation/widgets/event_card.dart';
import 'package:alaya/shared/widgets/section_header.dart';

import '../../support/calendar_harness.dart';

void main() {
  // `calendarEventRoute` and the grouped list moved to `calendar_event_list.dart` when the screen
  // started rendering the same list inline. They are exercised here because the sheet is still their
  // only widget host; if a list-specific suite ever earns its own file, these move with it.
  group('calendarEventRoute', () {
    test('deep-links the three types whose ref_id addresses a record', () {
      expect(
        calendarEventRoute(event(refType: 'transaction', refId: 'tx-9')),
        Routes.transactionDetail('tx-9'),
      );
      expect(
        calendarEventRoute(event(refType: 'asset', refId: 'as-2')),
        Routes.assetDetail('as-2'),
      );
      expect(
        calendarEventRoute(event(refType: 'shoppingList', refId: 'sl-3')),
        Routes.shoppingList('sl-3'),
      );
    });

    // Not an oversight and not a fallback chosen for convenience: `v_calendar_events` carries no parent
    // id, and `batchEdit` needs an item, `serviceEdit` needs an asset, and a recurring occurrence has no
    // route at all. Asserted so the day it gains one, this test is what says so.
    test(
      'falls back to the owning module where the feed carries no parent id',
      () {
        expect(
          calendarEventRoute(event(refType: 'inventoryBatch')),
          Routes.inventory,
        );
        expect(
          calendarEventRoute(event(refType: 'serviceRecord')),
          Routes.services,
        );
        expect(
          calendarEventRoute(event(refType: 'recurringOccurrence')),
          Routes.recurring,
        );
      },
    );

    test(
      'an unknown ref_type resolves to nothing rather than to somewhere wrong',
      () {
        expect(
          calendarEventRoute(event(refType: 'somethingNewInPhase9')),
          isNull,
        );
      },
    );
  });

  group('DaySheet', () {
    testWidgets('loading says so', (tester) async {
      final repo = FakeCalendarRepository(pending: true);
      await pumpCalendar(
        tester,
        const DaySheet(dateKey: kToday),
        overrides: calendarOverrides(repo),
      );

      expect(find.text('Loading this day…'), findsOneWidget);
    });

    testWidgets('empty is an answer, not a blank', (tester) async {
      await pumpCalendar(
        tester,
        const DaySheet(dateKey: kToday),
        overrides: calendarOverrides(FakeCalendarRepository()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nothing on this day'), findsOneWidget);
    });

    testWidgets('a failed read shows its reason and offers a retry', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        const DaySheet(dateKey: kToday),
        overrides: calendarOverrides(
          FakeCalendarRepository(error: 'view unavailable'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load this day'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('populated groups by type, one heading each', (tester) async {
      final repo = FakeCalendarRepository(
        events: [
          event(refId: 'tx-1', title: 'Groceries'),
          event(refId: 'tx-2', title: 'Fuel'),
          event(
            type: CalendarEventType.batchExpiry,
            refType: 'inventoryBatch',
            refId: 'ba-1',
            title: 'Milk',
          ),
        ],
      );
      await pumpCalendar(
        tester,
        const DaySheet(dateKey: kToday),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EventCard), findsNWidgets(3));

      // Read the headings off the widgets rather than searching for their text. `SectionHeader`
      // upper-cases for display and keeps the original in `semanticsLabel`, so `find.text('Transaction')`
      // tests SectionHeader's presentation choice instead of this sheet's grouping. Order matters too:
      // enum declaration order, so a reader scanning twice finds the same thing in the same place.
      final headings = tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((h) => h.label)
          .toList();
      expect(headings, ['Transaction', 'Expiring']);
    });

    // The aggregator escalates, not the view and not the card: a batch three days out is a warning by
    // ARCH_3 §6, and the view handed it the static `warning` baseline with no notion of today.
    testWidgets(
      'severity is resolved through the aggregator, against the fixed clock',
      (tester) async {
        final repo = FakeCalendarRepository(
          events: [
            event(
              date: kToday.addDays(-1),
              type: CalendarEventType.batchExpiry,
              refType: 'inventoryBatch',
              refId: 'ba-past',
              title: 'Yoghurt',
              baseSeverity: CalendarSeverity.warning,
            ),
          ],
        );
        await pumpCalendar(
          tester,
          DaySheet(dateKey: kToday.addDays(-1)),
          overrides: calendarOverrides(repo),
        );
        await tester.pumpAndSettle();

        // Past its date, and `batchExpiry` is the only type §6 lets reach danger.
        expect(find.text('Past its date'), findsOneWidget);
      },
    );

    testWidgets('survives 320dp at a doubled text scale', (tester) async {
      final repo = FakeCalendarRepository(
        events: [
          event(
            title: 'A payee with a name long enough to wrap at a doubled scale',
          ),
          event(
            type: CalendarEventType.serviceDue,
            refType: 'asset',
            refId: 'as-1',
            title: 'The boiler in the upstairs cupboard',
            baseSeverity: CalendarSeverity.warning,
          ),
        ],
      );
      await pumpCalendar(
        tester,
        const DaySheet(dateKey: kToday),
        overrides: calendarOverrides(repo),
        textScale: 2,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
