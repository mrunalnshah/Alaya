import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/domain/services/reminders/reminder_port.dart';
import 'package:alaya/features/reminders/presentation/screens/reminders_screen.dart';

import '../../support/ops_harness.dart';

/// The assertions whose absence let a five-and-a-half-hour scheduling error ship.
///
/// **A new file rather than more cases in `ops_screens_test.dart`**, because these are not about the four states
/// per screen that file exists to cover. They are about one specific failure mode: the screen displaying a value
/// it was given as *input* while presenting it as the schedule's *output*. That fault has nothing to do with
/// loading, empty or error branches and everything to do with which field a row reads.
///
/// **Why the old suite could not catch it.** `shows what is scheduled` asserted `find.text('Daily summary')` —
/// the row's title, which was correct throughout. The row was rendering the digest time from the settings object
/// passed down from the parent, so a schedule at 14:30 with a setting of 09:00 displayed 09:00 and every
/// assertion passed. The fixture could not express the divergence either: it took a `DateKey`, so no test could
/// construct a schedule whose time differed from the setting at all.
void main() {
  /// Reminders on, so the sections under test are rendered at all.
  ReminderSettings enabled() => const ReminderSettings.fresh().copyWith(
    enabled: {NotificationKind.expiry},
  );

  AlayaStrings stringsOf(WidgetTester tester) =>
      AlayaStrings.of(tester.element(find.byType(RemindersScreen)));

  group('the scheduled row reports the schedule, not the setting', () {
    testWidgets('a digest set for 09:00 but scheduled for 14:30 shows 14:30', (
      tester,
    ) async {
      // The whole bug in one fixture: the setting says nine, the OS is holding half past two. Before
      // `ScheduledReminder.at` existed the row could only read the former, so this test could not be written
      // and the failure could not be seen from inside the app.
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(
          reminders: FakeReminders(
            settings: enabled(),
            scheduled: [scheduledReminder(at: DateTime(2026, 8, 12, 14, 30))],
          ),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      // **Asserted on the minutes rather than the whole formatted string.** `MaterialLocalizations` renders
      // `2:30 PM` on a 12-hour locale and `14:30` on a 24-hour one, and both are correct — so matching the
      // half-past holds whichever the test environment picks, while a literal `'2:30 PM'` would make this
      // test a statement about the locale instead of about the screen.
      expect(find.textContaining(':30'), findsOneWidget);

      // The setting is still on screen and still says nine. That is the point: two values, both shown, no
      // longer pretending to be one. A count assertion, because `findsWidgets` would pass if the digest-time
      // row had vanished entirely and something else supplied the text.
      expect(find.textContaining('Sent at'), findsOneWidget);
    });

    testWidgets('the row survives a schedule whose minutes match the setting', (
      tester,
    ) async {
      // The control case, and the reason the assertion above is not enough on its own: a screen that printed
      // nothing at all would also fail to show `:30`. Here the schedule and the setting agree, so exactly two
      // widgets carry the same time — the setting row and the scheduled row.
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(
          reminders: FakeReminders(
            settings: enabled(),
            scheduled: [scheduledReminder(at: DateTime(2026, 8, 12, 9))],
          ),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining(':00'), findsNWidgets(2));
    });
  });

  group('the zone is named, because its silence was the bug', () {
    testWidgets('a matched zone is shown by name', (tester) async {
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(
          reminders: FakeReminders(settings: enabled()),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Asia/Kolkata'), findsOneWidget);
    });

    testWidgets('an unmatched zone warns instead of naming it', (tester) async {
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(
          reminders: FakeReminders(
            settings: enabled(),
            // What the app did on every device before this work: resolved to UTC and scheduled against it
            // without saying so.
            deviceZone: const ReminderZone(name: 'UTC', matchesDevice: false),
          ),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      // **Read from the ARB rather than typed in.** Asserting the copy verbatim would make this a test of the
      // string table, and it would break on a wording change that altered no behaviour.
      expect(
        find.text(stringsOf(tester).remindersZoneUnknown),
        findsOneWidget,
      );
      // The name is withheld, because naming a zone the device disagrees with is the confident wrong answer
      // this line replaced.
      expect(find.textContaining('UTC'), findsNothing);
    });

    testWidgets('nothing is claimed while every reminder is off', (
      tester,
    ) async {
      await pumpOps(
        tester,
        const RemindersScreen(),
        // `ReminderSettings.fresh()` by default: all four off (ARCH_3 §7).
        overrides: opsOverrides(reminders: FakeReminders()),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Asia/Kolkata'), findsNothing);
      expect(
        find.text(stringsOf(tester).remindersZoneUnknown),
        findsNothing,
      );
    });
  });

  group('the phone is asked, not just the database', () {
    testWidgets('a row the OS is not holding is called out', (tester) async {
      // **The state the app shipped in and could not describe.** A row in `notification_schedule`, a date, a
      // time, a zone — everything agreeing, and no alarm behind any of it. Before `pendingCount` this screen
      // rendered identical output for a schedule that worked and one the OS had refused.
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(
          reminders: FakeReminders(
            settings: enabled(),
            scheduled: [scheduledReminder()],
            osPendingCount: 0,
          ),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.text(stringsOf(tester).remindersOsMissing), findsOneWidget);
      expect(find.text(stringsOf(tester).remindersOsHolding), findsNothing);
    });

    testWidgets('a row the OS is holding is confirmed', (tester) async {
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(
          reminders: FakeReminders(
            settings: enabled(),
            scheduled: [scheduledReminder()],
          ),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.text(stringsOf(tester).remindersOsHolding), findsOneWidget);
    });

    testWidgets('a plugin that throws warns rather than falling silent', (
      tester,
    ) async {
      // A negative count stands for the plugin throwing. It must read as the warning rather than as an absent
      // line — silence on the error branch is the behaviour this widget exists to replace.
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(
          reminders: FakeReminders(
            settings: enabled(),
            scheduled: [scheduledReminder()],
            osPendingCount: -1,
          ),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.text(stringsOf(tester).remindersOsMissing), findsOneWidget);
    });
  });
}
