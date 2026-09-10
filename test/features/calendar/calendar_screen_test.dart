import 'package:flutter_test/flutter_test.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/features/calendar/presentation/widgets/calendar_month_grid.dart';

import '../../support/calendar_harness.dart';

void main() {
  group('CalendarScreen', () {
    testWidgets('loading: the grid is there before the feed is', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(FakeCalendarRepository(pending: true)),
      );

      // A month of empty cells is still a usable month, so loading reports beneath the grid rather
      // than in place of it.
      expect(find.byType(CalendarMonthGrid), findsOneWidget);
      expect(find.text('Loading this month…'), findsOneWidget);
    });

    testWidgets('empty: the selected day says so, and the grid still stands', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(FakeCalendarRepository()),
      );
      await tester.pumpAndSettle();

      // There is no month-level empty state any longer. "Nothing this month" was a fact about the
      // month; the day section answers the question the reader actually asked, and an empty month is
      // simply an empty day plus a grid with no dots.
      expect(find.text('Nothing on this day'), findsOneWidget);
      expect(find.byType(CalendarMonthGrid), findsOneWidget);
    });

    testWidgets('error: the reason shows and the grid survives it', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(
          FakeCalendarRepository(error: 'view unavailable'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load the calendar'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(CalendarMonthGrid), findsOneWidget);
    });

    testWidgets('populated: the month summary counts days, not events', (
      tester,
    ) async {
      final repo = FakeCalendarRepository(
        events: [
          event(refId: 'tx-1', title: 'Groceries'),
          event(refId: 'tx-2', title: 'Fuel'),
          event(date: kToday.addDays(3), refId: 'tx-3', title: 'Rent'),
        ],
      );
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      // The entries themselves, not a count of days. Selection starts on today, so both of today's
      // entries show and the one three days out does not — a count could not tell the reader either.
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Fuel'), findsOneWidget);
      expect(find.text('Rent'), findsNothing);
    });

    testWidgets('the section names the day it is showing', (tester) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(FakeCalendarRepository(events: [event()])),
      );
      await tester.pumpAndSettle();

      expect(find.text('On this day'), findsOneWidget);
      expect(find.text('August 1, 2026'), findsOneWidget);
    });

    testWidgets('tapping a day moves the section to it', (tester) async {
      final repo = FakeCalendarRepository(
        events: [
          event(refId: 'tx-1', title: 'Groceries'),
          event(
            date: const DateKey(20260812),
            refId: 'tx-2',
            title: 'Broadband',
          ),
        ],
      );
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();
      expect(find.text('Groceries'), findsOneWidget);

      // A two-digit day, because single digits appear twice in a month grid — once for this month and
      // once as an adjacent month's outside cell.
      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();

      expect(find.text('Broadband'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
    });

    // What the semantics tree actually contains, verified by dumping it rather than guessed at.
    // `table_calendar` owns each cell's node and labels it with the full date, excluding anything its
    // builders add — so the grid speaks dates, and the section below speaks contents. Both halves are
    // asserted here because either one silently changing would leave a screen-reader user with a grid
    // they can navigate and nothing to navigate towards.
    testWidgets('the grid speaks dates and the section speaks contents', (
      tester,
    ) async {
      // Disposed inline, not via `addTearDown`. `_verifySemanticsHandlesWereDisposed` runs inside
      // `_runTestBody`, before tear-downs execute, so a handle released in one is still open when the
      // check looks — the test then fails having asserted everything it meant to.
      final handle = tester.ensureSemantics();

      final repo = FakeCalendarRepository(
        events: [
          event(refId: 'tx-1', title: 'Groceries'),
          event(refId: 'tx-2', title: 'Fuel'),
        ],
      );
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      // The package's own cell label. If a future version drops it, the grid goes mute and this fails.
      expect(find.bySemanticsLabel('Saturday, August 1, 2026'), findsOneWidget);

      // And the day's contents, which is the part that carries what the dots only hint at.
      expect(find.bySemanticsLabel('On this day'), findsOneWidget);
      expect(find.bySemanticsLabel('August 1, 2026'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Fuel'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('a range shows every entry across the span', (tester) async {
      final repo = FakeCalendarRepository(
        events: [
          event(
            date: const DateKey(20260810),
            refId: 'tx-1',
            title: 'Groceries',
          ),
          event(
            date: const DateKey(20260812),
            refId: 'tx-2',
            title: 'Broadband',
          ),
          event(
            date: const DateKey(20260820),
            refId: 'tx-3',
            title: 'Outside it',
          ),
        ],
      );
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      // Long-press starts the range on the day pressed — there is no mode button and no intermediate
      // "pick a start" step, because the gesture already named one.
      await tester.longPress(find.text('10'));
      await tester.pumpAndSettle();
      expect(
        find.text('From August 10, 2026 — tap another day to finish.'),
        findsOneWidget,
      );

      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();

      expect(find.text('3 days'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Broadband'), findsOneWidget);
      expect(find.text('Outside it'), findsNothing);
    });

    testWidgets(
      'a range picked backwards reads the same as one picked forwards',
      (tester) async {
        final repo = FakeCalendarRepository(
          events: [
            event(
              date: const DateKey(20260812),
              refId: 'tx-1',
              title: 'Broadband',
            ),
          ],
        );
        await pumpCalendar(
          tester,
          const CalendarScreen(),
          overrides: calendarOverrides(repo),
        );
        await tester.pumpAndSettle();

        await tester.longPress(find.text('15'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('10'));
        await tester.pumpAndSettle();

        expect(find.text('6 days'), findsOneWidget);
        expect(find.text('Broadband'), findsOneWidget);
      },
    );

    testWidgets('opens on the clock\'s month, never on the wall clock', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(FakeCalendarRepository()),
      );
      await tester.pumpAndSettle();

      expect(find.text('August 2026'), findsOneWidget);
    });

    testWidgets('the chevrons move a month at a time', (tester) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(FakeCalendarRepository()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous month'));
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('July 2026'), findsOneWidget);
    });

    // The whole reason `CalendarRepository.watchRange` is the only read: unbounded, the view scans seven
    // tables. A regression here is silent — the screen looks identical and the query stops using indexes.
    // December to January, in both directions. `DateKey.fromYmd` throws on month 13 and month 0, so
    // this boundary was a crash rather than a wrong answer — paging forward from December 2026 died and
    // the month could only be reached by swiping.
    testWidgets('paging crosses the year boundary in both directions', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(FakeCalendarRepository()),
      );
      await tester.pumpAndSettle();

      // August 2026 forward to January 2027.
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byTooltip('Next month'));
        await tester.pumpAndSettle();
      }
      expect(find.text('January 2027'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // And back over the same boundary.
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('December 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every read is bounded to the month plus its overscan', (
      tester,
    ) async {
      final repo = FakeCalendarRepository();
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      expect(repo.rangesRequested, isNotEmpty);
      for (final range in repo.rangesRequested) {
        expect(range.from, DateKey(20260801).addDays(-gridPadDaysForTest));
        expect(range.to, DateKey(20260901).addDays(gridPadDaysForTest - 1));
        expect(range.to.diffDays(range.from), lessThan(45));
      }
    });

    testWidgets('a deep link opens that day\'s month and its sheet', (
      tester,
    ) async {
      final repo = FakeCalendarRepository(
        events: [
          event(
            date: const DateKey(20261115),
            refId: 'tx-nov',
            title: 'Fireworks',
          ),
        ],
      );
      await pumpCalendar(
        tester,
        const CalendarScreen(initialDay: DateKey(20261115)),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      expect(find.text('November 2026'), findsOneWidget);
      expect(find.text('Fireworks'), findsOneWidget);
    });

    // U26. `TableCalendar` takes a fixed `rowHeight`, and a grid of text cells with a fixed row height
    // is the exact shape that overflowed twenty-six tests in Phase 6F.
    testWidgets('survives 320dp at a doubled text scale', (tester) async {
      final repo = FakeCalendarRepository(
        events: [
          event(refId: 'tx-1'),
          event(
            date: kToday.addDays(2),
            type: CalendarEventType.batchExpiry,
            refType: 'inventoryBatch',
            refId: 'ba-1',
            baseSeverity: CalendarSeverity.warning,
          ),
        ],
      );
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(repo),
        textScale: 2,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(CalendarMonthGrid), findsOneWidget);
    });
  });
}

/// Mirrors `gridPadDays`, so a change to the overscan has to be made deliberately in two places.
const int gridPadDaysForTest = 6;
