/// The daily background job: recompute reminders, and purge what has outlived the trash.
///
/// **The two scheduled obligations nothing else honours.** ARCH_3 §7 wants a daily recompute so a digest reflects
/// what is actually coming, and §4.2's thirty-day retention is a promise the app does not keep unless something
/// enforces it. Both ports exposed the methods; until this file, nothing called them on a schedule.
///
/// **It runs in its own isolate, so it builds its own dependencies.** A `workmanager` callback has no access to
/// the UI isolate's Riverpod container — the providers there simply do not exist in this one. That is why the
/// wiring is repeated here rather than reused, and why the database is opened through
/// `openAlayaDatabase`, the single permitted open path (Law L10), rather than by reaching for a
/// connection somebody else made.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/calendar_dao.dart';
import 'package:alaya/data/daos/account_dao.dart';
import 'package:alaya/data/daos/notification_schedule_dao.dart';
import 'package:alaya/data/daos/split_dao.dart';
import 'package:alaya/data/daos/split_view_dao.dart';
import 'package:alaya/data/repositories/split_group_repository_impl.dart';
import 'package:alaya/data/repositories/split_ledger_repository_impl.dart';
import 'package:alaya/domain/services/split/split_balance_service.dart';
import 'package:alaya/data/daos/settings_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/connection/open_database.dart';
import 'package:alaya/data/reminders/local_notification_scheduler.dart';
import 'package:alaya/data/repositories/calendar_repository_impl.dart';
import 'package:alaya/data/repositories/settings_repository_impl.dart';
import 'package:alaya/data/trash/trash_adapter.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';

/// The unique name the periodic task is registered under.
///
/// Stable, so re-registering replaces rather than stacking: `workmanager` keys by this name, and a second
/// registration under a new name would mean two jobs doing the same work on two schedules.
const String dailyTaskName = 'alaya.daily';

/// How often the job runs.
///
/// **A day, and inexact by nature.** `workmanager` cannot promise a moment and does not try; Android batches
/// these to save battery. That is compatible with ARCH_3 §7 on purpose — the digest itself is scheduled by
/// `flutter_local_notifications` at the user's chosen time, and this job only decides what it will say.
const Duration dailyInterval = Duration(days: 1);

/// Registers the daily job. Called once from `bootstrap()`.
Future<void> registerDailyJob() async {
  await Workmanager().initialize(alayaCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    dailyTaskName,
    dailyTaskName,
    frequency: dailyInterval,
    // `ExistingPeriodicWorkPolicy`, not `ExistingWorkPolicy`: `registerPeriodicTask` has its own enum, and the
    // one-shot type is not assignable to it.
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(
      // No network requirement: everything this job does is local. Asking for connectivity would delay a purge
      // indefinitely on a phone that is rarely online, which is the opposite of a retention guarantee.
      networkType: NetworkType.notRequired,
      requiresBatteryNotLow: true,
    ),
  );
}

/// Builds a [LocalNotificationScheduler] over [database].
///
/// **Extracted so `bootstrap()` can re-arm at launch without a fourth copy of this wiring.** Three already
/// existed — this isolate's, the UI's `reminderPortProvider`, and none at startup — and a seven-argument
/// constructor duplicated per caller is a place where two copies drift and only one is tested.
///
/// **A fresh `FlutterLocalNotificationsPlugin` every call, deliberately.** It is not a singleton across
/// isolates: the instance the UI created does not exist in the `workmanager` isolate, and an uninitialised one
/// fails quietly rather than throwing. `LocalNotificationScheduler` initialises whatever it is handed, lazily,
/// which is why callers construct the scheduler rather than reaching for the plugin.
LocalNotificationScheduler buildReminderScheduler({
  required AlayaDatabase database,
  required Clock clock,
  required UidGenerator uids,
}) {
  final settingsDao = SettingsDao(database);
  final splitDao = SplitDao(database);

  // **The split chain, assembled here rather than injected into the scheduler.** The scheduler counts
  // ageing debts through a one-method function; it has no business knowing what a split is, and taking
  // `SplitBalanceService` would drag two repositories and three DAOs into a class that runs in a
  // `workmanager` isolate. This factory already exists to assemble everything from a database, which
  // makes it the right place and the only place — the seven-argument constructor this function replaced
  // is exactly the duplication its own doc warns about.
  final groups = SplitGroupRepositoryImpl(splitDao, settingsDao, clock);
  final balances = SplitBalanceService(
    ledger: SplitLedgerRepositoryImpl(
      splitDao,
      SplitViewDao(database),
      groups,
      AccountDao(database),
      clock,
    ),
    clock: clock,
  );

  return LocalNotificationScheduler(
    plugin: FlutterLocalNotificationsPlugin(),
    database: database,
    scheduleDao: NotificationScheduleDao(database),
    calendar: CalendarAggregator(CalendarRepositoryImpl(CalendarDao(database))),
    settings: SettingsRepositoryImpl(settingsDao, clock),
    uids: uids,
    clock: clock,
    // The threshold is `SplitBalanceService.defaultAgeingThresholdDays` — fourteen days, a judgement
    // rather than a finding, and documented as one where it is declared.
    ageingDebts: () async => (await balances.ageingDebts()).length,
  );
}

/// The background entry point.
///
/// `@pragma('vm:entry-point')` because the isolate is started by native code with no Dart caller — without it
/// tree-shaking removes this function from a release build and the job silently never runs.
@pragma('vm:entry-point')
void alayaCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != dailyTaskName) return true;
    AlayaDatabase? database;
    try {
      const clock = SystemClock();
      const uids = Uuid7Generator();
      // Defaults would supply both, but naming them keeps this isolate's wiring identical to the UI isolate's
      // rather than depending on two default lists staying in step.
      database = openAlayaDatabase(uids: uids, clock: clock);

      final trash = TrashAdapter(database: database, clock: clock);
      await trash.purgeExpired();

      final reminders = buildReminderScheduler(
        database: database,
        clock: clock,
        uids: uids,
      );
      await reminders.rescheduleAll();
      return true;
    } on Object {
      // **Returns true even on failure, deliberately.** Returning false asks Android to retry with backoff, and
      // a job that fails for a structural reason — a corrupt row, a revoked permission — would then retry
      // forever and cost battery for nothing. A missed day is recovered by tomorrow's run.
      return true;
    } finally {
      await database?.close();
    }
  });
}
