import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/features/calendar/presentation/widgets/event_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

import '../../support/calendar_harness.dart';

void main() {
  group('EventCard', () {
    testWidgets('names the event type, so the glyph is never the only clue', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        EventCard(
          event: event(type: CalendarEventType.batchExpiry),
          onTap: () {},
        ),
      );

      expect(find.text('Expiring'), findsOneWidget);
    });

    // The point of the card. A dot and a colour fail a colour-blind reader and fail in grayscale, so
    // anything above `info` says what it is in words (Law U9).
    testWidgets('a warning carries the severity in words, not only in colour', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        EventCard(
          event: event(
            type: CalendarEventType.warrantyEnd,
            baseSeverity: CalendarSeverity.warning,
          ),
          onTap: () {},
        ),
      );

      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.byType(StatusChip), findsOneWidget);
    });

    testWidgets('a danger says so too', (tester) async {
      await pumpCalendar(
        tester,
        EventCard(
          event: event(
            type: CalendarEventType.batchExpiry,
            baseSeverity: CalendarSeverity.danger,
          ),
          onTap: () {},
        ),
      );

      expect(find.text('Past its date'), findsOneWidget);
    });

    testWidgets('info carries no chip — there is nothing to warn about', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        EventCard(event: event(), onTap: () {}),
      );

      expect(find.byType(StatusChip), findsNothing);
      expect(find.text('Needs attention'), findsNothing);
      expect(find.text('Past its date'), findsNothing);
    });

    testWidgets('an amount renders through AmountText, never as a string', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        EventCard(event: event(amountMinor: 123456), onTap: () {}),
      );

      expect(find.byType(AmountText), findsOneWidget);
    });

    testWidgets('an entry with no amount shows none', (tester) async {
      await pumpCalendar(
        tester,
        EventCard(
          event: event(type: CalendarEventType.warrantyEnd),
          onTap: () {},
        ),
      );

      expect(find.byType(AmountText), findsNothing);
    });

    testWidgets(
      'a null onTap leaves the card inert rather than dead-tappable',
      (tester) async {
        await pumpCalendar(tester, EventCard(event: event(), onTap: null));

        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Groceries'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('survives 320dp at a doubled text scale', (tester) async {
      await pumpCalendar(
        tester,
        EventCard(
          event: event(
            title:
                'A warranty with a name long enough to wrap twice over at this scale',
            type: CalendarEventType.warrantyEnd,
            baseSeverity: CalendarSeverity.warning,
            amountMinor: 98765432,
          ),
          onTap: () {},
        ),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
