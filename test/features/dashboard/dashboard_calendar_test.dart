import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/calendar/presentation/widgets/calendar_month_grid.dart';
import 'package:alaya/features/calendar/presentation/widgets/day_sheet.dart';
import 'package:alaya/features/dashboard/presentation/widgets/dashboard_calendar.dart';

import '../../support/calendar_harness.dart';

/// The dashboard's month card, whose three behaviours are all invisible until they are wrong.
///
/// It changed shape three times in three rounds with nothing pinning it, which is what these are for: a
/// width gate that silently disables an interaction, a lock that silently permits paging, and a sheet
/// that silently never opens are each the kind of fault a screenshot cannot show.
void main() {
  /// Pumps the card at [width] logical pixels, which is the only input the width gate reads.
  ///
  /// Through `pumpCalendar`'s own `size`, not by setting `physicalSize` first — the harness sets it after
  /// this function would have, so anything set beforehand is silently discarded.
  Future<void> pumpAt(WidgetTester tester, double width) async {
    await pumpCalendar(
      tester,
      const DashboardCalendar(),
      overrides: calendarOverrides(FakeCalendarRepository(events: [event()])),
      size: Size(width, 800),
    );
    await tester.pumpAndSettle();
  }

  /// Whether the grid is currently wrapped in something that swallows its gestures.
  ///
  /// Presence of an `IgnorePointer` says nothing: the framework wraps this subtree in two of its own on
  /// every screen (`ignoring: false`), so `findsOneWidget` counted three at 320dp and two at 412dp. The
  /// property is the contract, not the type — so this asks whether any ancestor is actually ignoring.
  bool gridIsInert(WidgetTester tester) => tester
      .widgetList<IgnorePointer>(
        find.ancestor(
          of: find.byType(CalendarMonthGrid),
          matching: find.byType(IgnorePointer),
        ),
      )
      .any((widget) => widget.ignoring);

  group('DashboardCalendar', () {
    testWidgets('the grid is there whatever the width', (tester) async {
      await pumpAt(tester, 412);
      expect(find.byType(CalendarMonthGrid), findsOneWidget);
    });

    // 412dp leaves (412 - 64) / 7 = 49.7dp per cell, over the 48dp floor, so days accept taps.
    testWidgets('a wide screen opens the day in a sheet', (tester) async {
      await pumpAt(tester, 412);

      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();

      expect(find.byType(DaySheet), findsOneWidget);
    });

    // 320dp leaves 36.6dp per cell. Rather than ship targets nobody can hit, the days go inert and the
    // card itself becomes the way in.
    //
    // Asserted structurally rather than by tapping. A tap here does not land on nothing — it falls
    // through the inert grid to the card's own `InkWell`, which calls `context.push`, and this harness has
    // no `GoRouter`. That the tap reaches the card is the fallback working, so the useful assertion is
    // whether the grid's gestures are being swallowed, not what a tap happens to trigger.
    testWidgets('a narrow screen makes the days inert', (tester) async {
      await pumpAt(tester, 320);

      expect(gridIsInert(tester), isTrue);
      expect(find.byType(DaySheet), findsNothing);
    });

    testWidgets('a wide screen leaves the days live', (tester) async {
      await pumpAt(tester, 412);

      expect(gridIsInert(tester), isFalse);
    });

    // `availableGestures: none` alone would not do it: `firstDay`/`lastDay` spanning years leave the
    // underlying `PageView` with neighbouring pages that a fling can still reach. The bounds are the lock.
    testWidgets('the month cannot be paged away from', (tester) async {
      await pumpAt(tester, 412);
      expect(find.text('August 2026'), findsOneWidget);

      await tester.fling(
        find.byType(CalendarMonthGrid),
        const Offset(-300, 0),
        1000,
      );
      await tester.pumpAndSettle();

      expect(find.text('August 2026'), findsOneWidget);
      expect(find.text('September 2026'), findsNothing);
    });
  });
}
