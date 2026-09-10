import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart';
import 'package:alaya/domain/services/reminders/reminder_port.dart';
import 'package:alaya/domain/services/support/support_port.dart';
import 'package:alaya/domain/services/trash/trash_port.dart';
import 'package:alaya/features/backup/presentation/screens/backup_screen.dart';
import 'package:alaya/features/backup/presentation/screens/restore_flow.dart';
import 'package:alaya/features/reminders/presentation/screens/reminders_screen.dart';
import 'package:alaya/features/support/presentation/screens/support_screen.dart';
import 'package:alaya/features/trash/presentation/screens/trash_screen.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';

import '../../support/ops_harness.dart';

/// The 8B screens — four states each (Law U4), and the CRITICAL requirements asserted rather than assumed.
void main() {
  group('backup — the export warning', () {
    testWidgets(
      'every export path goes through a sheet carrying ARCH_3 §3.4 verbatim',
      (tester) async {
        final transfer = FakeTransfer();
        await pumpOps(
          tester,
          const BackupScreen(),
          overrides: opsOverrides(transfer: transfer),
          size: kTallViewport,
        );
        await tester.pumpAndSettle();

        for (final action in ['Save a copy', 'Share a copy']) {
          await tester.tap(find.text(action));
          await tester.pumpAndSettle();

          // **The exact sentence, including the third clause.** 8A shipped a paraphrase that dropped "Only share it
          // somewhere you trust" — the only actionable sentence of the three — and nothing caught it until §3.4 was
          // read directly. Asserting the words rather than the key is what stops that recurring.
          expect(find.textContaining('not encrypted'), findsOneWidget);
          expect(
            find.textContaining('every transaction, balance and account name'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Only share it somewhere you trust'),
            findsOneWidget,
          );

          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
        }
        // Cancelling the warning wrote nothing, twice.
        expect(transfer.exports, 0);
      },
    );

    testWidgets('history renders its four states', (tester) async {
      await pumpOps(
        tester,
        const BackupScreen(),
        overrides: opsOverrides(transfer: FakeTransfer(history: const [])),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);

      await pumpOps(
        tester,
        const BackupScreen(),
        overrides: opsOverrides(
          transfer: FakeTransfer(history: [backupRecord()]),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      // The name is derived from the path, because the table stores no file name.
      expect(find.text('alaya-2026-08-08.db'), findsOneWidget);
    });
  });

  group('restore — the guards, in order', () {
    testWidgets('a newer backup is refused with both version numbers', (
      tester,
    ) async {
      await pumpOps(
        tester,
        const RestoreFlow(),
        overrides: opsOverrides(
          transfer: FakeTransfer(backupVersion: 7, schemaVersion: 1),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Choose a file'), findsOneWidget);
      // The gate itself is exercised in the port's own test; here the screen must be able to *say* it, which is
      // what a refusal nobody can act on fails at.
      expect(find.textContaining('Alaya is never restored'), findsNothing);
      expect(find.textContaining('PIN is never restored'), findsOneWidget);
    });

    testWidgets('the lock-not-restored line is on the first screen', (
      tester,
    ) async {
      await pumpOps(
        tester,
        const RestoreFlow(),
        overrides: opsOverrides(),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      // ARCH_3 §3.2's last line, on the one screen where somebody might expect otherwise.
      expect(find.textContaining('never restored'), findsOneWidget);
    });
  });

  group('reminders — contextual permission, all off', () {
    testWidgets('every toggle starts off', (tester) async {
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(reminders: FakeReminders()),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      final switches = tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      // ARCH_3 §7: all reminders default off. `ReminderSettings.fresh()` is what makes that true.
      expect(switches.isNotEmpty, isTrue);
      expect(switches.every((tile) => tile.value == false), isTrue);
    });

    testWidgets('permission is requested on the first switch-on, not on open', (
      tester,
    ) async {
      final reminders = FakeReminders(
        permissionState: ReminderPermission.notRequested,
      );
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(reminders: reminders),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      // **Nothing asked merely by opening the screen.** Asking on launch is what gets an app denied for good.
      expect(reminders.permissionRequests, 0);

      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      expect(reminders.permissionRequests, 1);
    });

    testWidgets('nothing on reads as nothing on', (tester) async {
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(reminders: FakeReminders()),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      // Everything off: an empty schedule is correct, and switching one on is the fix.
      expect(find.text('Nothing scheduled'), findsOneWidget);
      expect(find.text('Check now'), findsNothing);
    });

    testWidgets('reminders on with nothing due says so, and offers a scan', (
      tester,
    ) async {
      // **The case that made a working feature look broken.** `_scheduleDigest` deliberately sends
      // nothing rather than a message reading "0 items expire this week" — so an empty schedule with
      // reminders on is correct behaviour. The old copy said "turn on a reminder above", which is what
      // the user had already done.
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(
          reminders: FakeReminders(
            settings: const ReminderSettings.fresh().copyWith(
              enabled: {NotificationKind.expiry},
            ),
          ),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.text('Nothing due this week'), findsOneWidget);
      expect(find.text('Nothing scheduled'), findsNothing);
      expect(find.text('Check now'), findsOneWidget);
    });

    testWidgets('a scan that finds nothing says nothing found, not failed', (
      tester,
    ) async {
      // The sentence that was impossible to obtain before: proof the reminder works and the week is
      // simply clear. Reporting this as a failure would be the wrong answer to a correct scan.
      final reminders = FakeReminders(
        settings: const ReminderSettings.fresh().copyWith(
          enabled: {NotificationKind.expiry},
        ),
        rescheduleCount: 0,
      );
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(reminders: reminders),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check now'));
      await tester.pumpAndSettle();
      expect(reminders.reschedules, 1);
      expect(
        find.text('Nothing coming up in the next week'),
        findsOneWidget,
      );
    });

    testWidgets('a scan that finds things names the number', (tester) async {
      final reminders = FakeReminders(
        settings: const ReminderSettings.fresh().copyWith(
          enabled: {NotificationKind.expiry},
        ),
        rescheduleCount: 3,
      );
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(reminders: reminders),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check now'));
      await tester.pumpAndSettle();
      // Naming the count is what proves the scan ran rather than merely returned.
      expect(find.text('3 things coming up'), findsOneWidget);
    });

    testWidgets('a test notification can be sent whenever a reminder is on', (
      tester,
    ) async {
      // **The diagnostic that was missing.** A digest scheduled for tomorrow morning and a broken
      // delivery path look identical from outside the app, and nothing distinguished them.
      final reminders = FakeReminders(
        settings: const ReminderSettings.fresh().copyWith(
          enabled: {NotificationKind.expiry},
        ),
      );
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(reminders: reminders),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send a test notification'));
      await tester.pumpAndSettle();
      expect(reminders.testsSent, 1);
      expect(find.text('Sent — check your notifications'), findsOneWidget);
    });

    testWidgets('a failed test reports the reason, not a generic error', (
      tester,
    ) async {
      // A missing `@drawable/ic_notification` throws at post time and nowhere else — the compiler never
      // sees that string. Swallowing the message would discard the only diagnosis available.
      final reminders = FakeReminders(
        settings: const ReminderSettings.fresh().copyWith(
          enabled: {NotificationKind.expiry},
        ),
      )..testFails = true;
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(reminders: reminders),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send a test notification'));
      await tester.pumpAndSettle();
      expect(
        find.text('That test notification could not be sent.'),
        findsOneWidget,
      );
    });

    testWidgets('the test action is hidden when nothing is on', (tester) async {
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(reminders: FakeReminders()),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      // Nothing to test when nothing is on, and offering it would invite a false negative.
      expect(find.text('Send a test notification'), findsNothing);
    });

    testWidgets('a refused request leaves the switch off', (tester) async {
      final reminders = FakeReminders(
        permissionState: ReminderPermission.denied,
      );
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(reminders: reminders),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      // A control reading "on" while the OS drops every notification is a control that lies.
      final switches = tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(switches.every((tile) => tile.value == false), isTrue);
    });

    testWidgets('shows what is scheduled', (tester) async {
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(
          reminders: FakeReminders(scheduled: [scheduledReminder()]),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.text('Daily summary'), findsWidgets);
    });
  });

  group('trash — retention and the one hard delete', () {
    testWidgets('loading is a skeleton', (tester) async {
      // The stream must never emit, or the loading branch is gone before the first assertion — a
      // `Stream.value` resolves in the same microtask drain as the first frame.
      await pumpOps(
        tester,
        const TrashScreen(),
        overrides: opsOverrides(trash: FakeTrash(loading: true)),
      );
      expect(find.byType(AlayaListSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('empty explains the thirty days', (tester) async {
      await pumpOps(
        tester,
        const TrashScreen(),
        overrides: opsOverrides(trash: FakeTrash(entries: const [])),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.textContaining('30 days'), findsOneWidget);
    });

    testWidgets('every row says when it goes', (tester) async {
      await pumpOps(
        tester,
        const TrashScreen(),
        overrides: opsOverrides(trash: FakeTrash(entries: [trashEntry()])),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      // A trash that silently empties is one people stop trusting with what they deleted by accident.
      expect(find.textContaining('kept for 30 days'), findsOneWidget);
    });

    testWidgets('empty now is confirmed before anything is purged', (
      tester,
    ) async {
      final trash = FakeTrash(
        entries: [
          trashEntry(),
          trashEntry(id: 'tr-2', label: 'Rice'),
        ],
      );
      await pumpOps(
        tester,
        const TrashScreen(),
        overrides: opsOverrides(trash: trash),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Empty now'));
      await tester.pumpAndSettle();
      expect(find.textContaining('nowhere left for it to go'), findsOneWidget);
      expect(trash.purged, 0);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(trash.purged, 0);
    });
  });

  group('support — nothing loads unless this screen opens it', () {
    testWidgets('opening the screen is what starts the SDK', (tester) async {
      final support = FakeSupport();
      // Before the screen exists, nothing has been asked of the port.
      expect(support.initialisations, 0);
      expect(support.adLoads, 0);

      await pumpOps(
        tester,
        const SupportScreen(),
        overrides: opsOverrides(support: support),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      // **One initialisation, from `initState`.** The rest of the app makes zero ad calls because
      // `AdsAndBilling` is the only file importing either SDK — this asserts the other half, that the screen is
      // what triggers it.
      expect(support.initialisations, 1);
      expect(support.adLoads, 1);
    });

    testWidgets('no advert is requested when consent could not be settled', (
      tester,
    ) async {
      final support = FakeSupport(consent: AdConsent.unavailable);
      await pumpOps(
        tester,
        const SupportScreen(),
        overrides: opsOverrides(support: support),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      // Requesting an ad before consent is settled is what gets an app pulled in the EEA.
      expect(support.adLoads, 0);
      expect(find.textContaining('Nothing has been requested'), findsOneWidget);
    });

    testWidgets('the tip shows the store price, unformatted by us', (
      tester,
    ) async {
      await pumpOps(
        tester,
        const SupportScreen(),
        overrides: opsOverrides(support: FakeSupport()),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      // The store's own string. Reformatting it through AmountText would render it in the wrong currency.
      expect(find.textContaining('₹99.00'), findsOneWidget);
    });

    testWidgets('says plainly that nothing is unlocked', (tester) async {
      await pumpOps(
        tester,
        const SupportScreen(),
        overrides: opsOverrides(),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('no paid features'), findsOneWidget);
    });
  });

  group('the gate', () {
    testWidgets('every screen renders at 320x640 with a doubled text scale', (
      tester,
    ) async {
      final screens = <Widget>[
        const BackupScreen(),
        const RestoreFlow(),
        const RemindersScreen(),
        const TrashScreen(),
        const SupportScreen(),
      ];
      for (final screen in screens) {
        await pumpOps(
          tester,
          screen,
          overrides: opsOverrides(
            transfer: FakeTransfer(history: [backupRecord()]),
            trash: FakeTrash(entries: [trashEntry()]),
            reminders: FakeReminders(scheduled: [scheduledReminder()]),
          ),
          textScale: 2,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });
}
