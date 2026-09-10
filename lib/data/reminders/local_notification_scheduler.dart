import 'package:drift/drift.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/notification_schedule_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/reminders/device_time_zone.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';
import 'package:alaya/domain/services/reminders/reminder_port.dart';

/// How many split debts are old enough to be worth mentioning, as of now.
///
/// **A function rather than a `SplitBalanceService`.** The scheduler assembles one message from
/// everything due; it has no business knowing what a split is, and taking the service would drag the
/// whole split repository chain into a class that runs in a `workmanager` isolate.
/// `buildReminderScheduler` owns that wiring, which is the same division `PurchaseFanOutService` keeps
/// by staying pure.
///
/// Returns a count rather than the debts themselves, because the digest is counts by kind — one line,
/// once a day (ARCH_3 §7). A richer sentence would need a second notification, which that section
/// forbids.
typedef AgeingDebtCounter = Future<int> Function();

/// The production [ReminderPort]: one daily digest, scheduled inexactly, in the device's own timezone.
///
/// **The only file in this phase that imports `flutter_local_notifications`.** `timezone` is imported here
/// and by `device_time_zone.dart`, which is pure Dart and does have tests. The plugin needs a platform
/// channel and so does not run in a widget test — which is the whole reason `ReminderPort` exists. This is
/// also the largest surface in the phase that could not be compiled against (ARCH_4 R22): `zonedSchedule`,
/// `AndroidScheduleMode`, and `requestNotificationsPermission` have each moved between major versions of the
/// plugin. 8A's `local_auth` took two wrong guesses before compiling; expect at least one here, and expect it
/// to cost this file and nothing else.
///
/// **One notification, not a stream of pings** (ARCH_3 §7). Every enabled kind is folded into a single sentence —
/// *"3 items expire this week, 1 bill due tomorrow"* — delivered once a day at a time the user picked. The
/// contract cannot express a per-item ping, and neither can this.
///
/// **Inexact, always.** `AndroidScheduleMode.inexactAllowWhileIdle` and never `exactAllowWhileIdle`: Android 14
/// restricts `SCHEDULE_EXACT_ALARM` and Play asks why an app needs it. A digest that arrives at 9:07 instead of
/// 9:00 has lost nothing.
///
/// **The zone is resolved, not assumed, and that was the bug.** `initializeTimeZones()` loads the database
/// without choosing a zone, so `tz.local` was UTC and every digest was booked against UTC wall time — 5½ hours
/// late in India, 8 hours early in California, a day out in New Zealand. `_ensureTimezones` now resolves the
/// device's real zone through [DeviceTimeZone] and re-resolves when the device's offset changes, which is what
/// makes this class's "somebody who asked for 9am wants 9am where they are" comment true rather than intended.
final class LocalNotificationScheduler implements ReminderPort {
  /// Creates the scheduler.
  LocalNotificationScheduler({
    required FlutterLocalNotificationsPlugin plugin,
    required AlayaDatabase database,
    required NotificationScheduleDao scheduleDao,
    required CalendarAggregator calendar,
    required SettingsRepository settings,
    required UidGenerator uids,
    required Clock clock,
    AgeingDebtCounter? ageingDebts,
  }) : _plugin = plugin,
       _db = database,
       _scheduleDao = scheduleDao,
       _calendar = calendar,
       _settings = settings,
       _uids = uids,
       _clock = clock,
       _ageingDebts = ageingDebts ?? _noAgeingDebts;

  final FlutterLocalNotificationsPlugin _plugin;
  final AlayaDatabase _db;
  final NotificationScheduleDao _scheduleDao;
  final CalendarAggregator _calendar;
  final SettingsRepository _settings;
  final UidGenerator _uids;
  final Clock _clock;

  /// Counts split debts past their ageing threshold, or reports none when unwired.
  ///
  /// **Defaulted rather than required**, so `bootstrap.dart`, the daily job and every test that builds
  /// a scheduler keep working untouched. A required parameter would have made this change reach files
  /// with no interest in splits.
  final AgeingDebtCounter _ageingDebts;

  /// The `app_settings` key holding which reminder kinds are on.
  ///
  /// Stored as a comma-separated list of names rather than one key per kind: adding a fifth kind then needs no
  /// migration, and an unknown name in the list is ignored rather than fatal.
  static const String enabledKindsKey = 'reminders.enabledKinds';

  /// The `app_settings` key holding the digest time as `HH:mm`.
  static const String digestTimeKey = 'reminders.digestTime';

  /// The Android notification id the daily digest always uses.
  ///
  /// **Fixed, so rescheduling replaces rather than accumulates.** Every other id comes from
  /// `NotificationScheduleDao.nextAndroidNotificationId`; the digest is the one notification that is always
  /// exactly one, so it gets a constant and cancelling it needs no lookup.
  static const int digestNotificationId = 1;

  /// How far ahead the digest looks.
  ///
  /// A week, because that is the horizon a sentence can usefully summarise. A month's worth of counts reads as a
  /// backlog rather than a nudge, and a day's is too late to act on an expiry.
  static const Duration horizon = Duration(days: 7);

  /// The reference type recorded against the digest's `notification_schedule` row.
  static const String digestRefType = 'digest';

  /// The notification id used by [sendTest].
  ///
  /// Deliberately not [digestNotificationId]: a test must never cancel or overwrite a real scheduled
  /// digest, and reusing the id would do exactly that.
  static const int testNotificationId = 9001;

  /// The status-bar icon: white on transparency, at `android/app/src/main/res/drawable/ic_notification.xml`.
  ///
  /// **A resource *name*, not a resource *reference*, and the difference broke every notification this app
  /// ever tried to send.** This read `'@drawable/ic_notification'` — which is XML syntax, valid inside a
  /// layout or a manifest and nowhere else. The plugin resolves it on the Android side with
  /// `getResources().getIdentifier(name, "drawable", packageName)`, and `getIdentifier` wants
  /// `ic_notification`. Given the `@drawable/` prefix it matches nothing and returns 0.
  ///
  /// So the drawable was correct, present, and unreachable. Three symptoms came from this one string: the
  /// reminder switches would not stay on, the daily digest never fired, and a test notification never once
  /// arrived — all of them because `_ensurePlugin()` could not resolve the icon it was initialising with.
  ///
  /// **Nothing catches it at build time and nothing can.** A drawable name is a string the compiler never
  /// sees; `flutter analyze` is happy either way, and both spellings look equally plausible in review. The
  /// `@`-prefixed form is what you write in `AndroidManifest.xml`, four lines away from here in the same
  /// change, which is exactly why the wrong one felt right.
  static const String notificationIcon = 'ic_notification';

  bool _databaseLoaded = false;
  ResolvedTimeZone? _zone;
  bool _pluginReady = false;

  /// Loads the zone database once, then resolves the device's zone and applies it to `tz.local`.
  ///
  /// **`initializeTimeZones()` alone was the bug.** It loads six hundred zones and selects none of them;
  /// `tz.local` stays UTC until `setLocalLocation` is called, and nothing called it. Every `TZDateTime` built
  /// by `_nextOccurrence` was therefore a UTC wall time wearing a local label, so a 9am digest fired at 9am
  /// UTC — 2:30pm in Ahmedabad, 1am in Los Angeles. Nothing in a build or a test run could see it, because
  /// the tests use a fake and a fake has no zone.
  ///
  /// **Re-resolves when the device's offset changes.** The UI isolate outlives a flight: resolving once at
  /// startup and caching forever would keep scheduling in the zone the user left. Comparing the current
  /// offset against the resolved one is a single `dart:core` read, cheap enough to do on every reschedule,
  /// and it means a digest follows the device the next time anything reschedules — which the daily job does
  /// once a day regardless.
  ///
  /// **Returns the resolution rather than only storing it**, so [zone] needs no null check and no `!`. A
  /// nullable field read after a method that always assigns it is a place where a later edit introduces a
  /// crash the type system had been willing to prevent.
  Future<ResolvedTimeZone> _ensureTimezones() async {
    if (!_databaseLoaded) {
      tz_data.initializeTimeZones();
      _databaseLoaded = true;
    }
    final cached = _zone;
    if (cached != null &&
        cached.deviceOffset == DateTime.now().timeZoneOffset) {
      return cached;
    }
    final resolved = DeviceTimeZone.resolve();
    tz.setLocalLocation(resolved.location);
    return _zone = resolved;
  }

  /// Brings the notification plugin up, once.
  ///
  /// **This was missing entirely until Phase 9, and nothing worked without it.** `zonedSchedule` on an
  /// uninitialised plugin does not throw — it fails quietly — so the digest had never fired on a device while
  /// every test passed, because the tests use a fake and the fake has nothing to initialise.
  ///
  /// `settings` is **named**, like every other parameter on this plugin version — `zonedSchedule` and `cancel`
  /// are too. This is the third time that surface has differed from its documented form, so treat any call here
  /// as named-only until the analyzer says otherwise.
  ///
  /// **The icon is a purpose-made drawable, not `@mipmap/ic_launcher`.** Android flattens a notification icon to
  /// a white silhouette on API 21 and above, discarding colour entirely, so pointing this at the launcher icon
  /// renders a solid white square in the status bar. `@drawable/ic_notification` is white-on-transparent by
  /// construction.
  Future<void> _ensurePlugin() async {
    if (_pluginReady) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(notificationIcon),
      ),
    );
    _pluginReady = true;
  }

  @override
  Stream<ReminderSettings> watchSettings() =>
      _db.select(_db.appSettings).watch().asyncMap((_) => _readSettings());

  Future<ReminderSettings> _readSettings() async {
    final stored = await _settings.readValue(enabledKindsKey);
    final time = await _settings.readValue(digestTimeKey);
    final enabled = <NotificationKind>{};
    for (final name in (stored ?? '').split(',')) {
      for (final kind in reminderKinds) {
        if (kind.name == name.trim()) enabled.add(kind);
      }
    }
    final parts = (time ?? '09:00').split(':');
    return ReminderSettings(
      enabled: enabled,
      digestHour: int.tryParse(parts.first) ?? 9,
      digestMinute: parts.length > 1 ? int.tryParse(parts.last) ?? 0 : 0,
    );
  }

  @override
  Future<ReminderPermission> permission() async {
    await _ensurePlugin();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return ReminderPermission.denied;
    final enabled = await android.areNotificationsEnabled();
    if (enabled ?? false) return ReminderPermission.granted;
    // **`notRequested` unless something has been asked for.** The OS cannot tell us whether we have asked, so the
    // app records it: a stored digest time means a toggle was once turned on, which means the prompt has been
    // shown. Without this the screen would nag somebody who deliberately said no.
    final asked = await _settings.readValue(digestTimeKey);
    return asked == null
        ? ReminderPermission.notRequested
        : ReminderPermission.denied;
  }

  @override
  Future<ReminderPermission> requestPermission() async {
    await _ensurePlugin();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return ReminderPermission.denied;
    final granted = await android.requestNotificationsPermission();
    return (granted ?? false)
        ? ReminderPermission.granted
        : ReminderPermission.denied;
  }

  @override
  Future<Result<ReminderSettings, Failure>> setEnabled({
    required NotificationKind kind,
    required bool enabled,
  }) async {
    try {
      final current = await _readSettings();
      final next = {...current.enabled};
      enabled ? next.add(kind) : next.remove(kind);
      await _settings.writeValue(
        key: enabledKindsKey,
        value: next.map((kind) => kind.name).join(','),
        valueType: 'string',
      );
      final settings = current.copyWith(enabled: next);
      // Turning the last one off cancels everything rather than leaving a digest that says nothing.
      next.isEmpty ? await cancelAll() : await _scheduleDigest(settings);
      return Result.ok(settings);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That reminder could not be changed.', cause: error),
      );
    }
  }

  @override
  Future<Result<ReminderSettings, Failure>> setDigestTime({
    required int hour,
    required int minute,
  }) async {
    try {
      final two = (int value) => value < 10 ? '0$value' : '$value';
      await _settings.writeValue(
        key: digestTimeKey,
        value: '${two(hour)}:${two(minute)}',
        valueType: 'string',
      );
      final settings = (await _readSettings()).copyWith(
        digestHour: hour,
        digestMinute: minute,
      );
      if (settings.anyEnabled) await _scheduleDigest(settings);
      return Result.ok(settings);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure(
          'The reminder time could not be changed.',
          cause: error,
        ),
      );
    }
  }

  @override
  Stream<List<ScheduledReminder>>
  watchScheduled() => _scheduleDao.watchScheduled().map(
    (rows) => [
      for (final row in rows)
        ScheduledReminder(
          id: row.id,
          // The row's own `kind` column, converted by drift — not derived from `refType`, which I had
          // written before reading the table. Two sources for one fact is one too many.
          kind: row.kind,
          // **`.toLocal()`, and the missing call was half the bug.** The column is a UTC instant, and the
          // previous version handed its *UTC calendar fields* to `DateKey.fromDateTime` — which takes fields
          // as given and converts nothing. So the date reported was the UTC date: yesterday for anything
          // before 05:30 in India, tomorrow for an evening digest in California. Converting here means every
          // consumer gets a wall clock without having to remember to ask for one.
          at: DateTime.fromMillisecondsSinceEpoch(
            row.scheduledAtUtcMillis,
            isUtc: true,
          ).toLocal(),
          androidNotificationId: row.androidNotificationId,
        ),
    ],
  );

  @override
  Future<ReminderZone> zone() async {
    final resolved = await _ensureTimezones();
    return ReminderZone(
      name: resolved.name,
      // **`ambiguous` counts as a match, and that is not a concession.** Several zones agreeing with the device
      // at every probe across fourteen months are the same rules under different names, so the digest lands at
      // the right moment whichever label was picked. Only `approximate` and `fallback` mean the schedule may be
      // wrong, and those are the two the user needs told about.
      matchesDevice:
          resolved.match == TimeZoneMatch.exact ||
          resolved.match == TimeZoneMatch.ambiguous,
    );
  }

  @override
  Future<Result<int, Failure>> rescheduleAll() async {
    try {
      final settings = await _readSettings();
      if (!settings.anyEnabled) {
        await cancelAll();
        return const Result.ok(0);
      }
      final count = await _scheduleDigest(settings);
      return Result.ok(count);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('Reminders could not be rescheduled.', cause: error),
      );
    }
  }

  @override
  Future<Result<int, Failure>> pendingCount() async {
    try {
      await _ensurePlugin();
      // **Asks the OS, not the database.** `pendingNotificationRequests` is the plugin's own view of what
      // `AlarmManager` is holding, so it is the only value in this class that is not something Alaya asserted
      // about itself. `.length` rather than the list: the identities add nothing a count does not, and naming
      // `PendingNotificationRequest` would be one more type to have guessed wrongly.
      final pending = await _plugin.pendingNotificationRequests();
      return Result.ok(pending.length);
    } on Object catch (error) {
      // A throw here is as informative as a zero — both mean the alarm path cannot be confirmed — so it goes
      // to the screen rather than the log, like `sendTest`'s.
      return Result.failure(
        UnexpectedFailure(
          'Your phone could not be asked what it has scheduled.',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<void, Failure>> sendTest() async {
    try {
      await _ensurePlugin();
      // `show`, not `zonedSchedule`. The point is to remove timing from the question entirely — if this
      // arrives, the icon resolves, the permission is real and the channel exists, and any remaining
      // silence is about *when* rather than *whether*.
      await _plugin.show(
        id: testNotificationId,
        title: 'Reminders are working',
        body:
            'This is a test. Your daily summary will arrive at the time you set.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            // The digest's own channel, on purpose. A test on a different channel could succeed while
            // the real one is blocked in system settings — which is the failure most worth catching.
            'alaya_digest',
            'Daily summary',
            channelDescription: 'One message a day about what is coming up.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
      return const Result.ok(null);
    } on Object catch (error) {
      // **A throw here is the answer, not an inconvenience.** A missing `@drawable/ic_notification` is a
      // runtime string the compiler never checks, so this is the only place it can surface — and the
      // message goes to the screen rather than the log.
      return Result.failure(
        UnexpectedFailure(
          'That test notification could not be sent.',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<void, Failure>> cancelAll() async {
    try {
      await _ensurePlugin();
      // `cancel` is named-only on the installed plugin, like `zonedSchedule` — this version takes nothing
      // positionally anywhere on its surface.
      await _plugin.cancel(id: digestNotificationId);
      await _scheduleDao.cancelAll(nowUtcMillis: _clock.nowUtcMillis());
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('Reminders could not be cancelled.', cause: error),
      );
    }
  }

  /// Counts what is coming, writes one schedule row, and books one notification.
  ///
  /// Idempotent by construction: the digest's Android id is a constant and its `notification_schedule` row is
  /// replaced by `refType`/`refId`, so the daily `workmanager` job can call this as often as it likes without
  /// stacking duplicates — which is exactly what ARCH_3 §7 means by the table guaranteeing idempotency.
  Future<int> _scheduleDigest(ReminderSettings settings) async {
    await _ensurePlugin();
    await _ensureTimezones();
    final today = _clock.today();
    final events = await _calendar
        .watchRange(
          from: today,
          to: today.addDays(horizon.inDays),
          today: today,
        )
        .first;

    final counts = <NotificationKind, int>{};
    for (final event in events) {
      final kind = _kindForEvent(event.type);
      if (kind == null || !settings.enabled.contains(kind)) continue;
      counts[kind] = (counts[kind] ?? 0) + 1;
    }

    // **The second source, and the only one that is not a calendar event.** An ageing debt has no date:
    // nobody agreed to settle by anything, it has simply been three weeks. That cannot be a view arm,
    // because ARCH_2 §12.2 forbids a view from consulting the current time — so the comparison happens
    // in Dart against the injected clock, inside `SplitBalanceService`.
    //
    // **Added to the settle-by count rather than deduplicated against it.** The calendar arm counts
    // *expenses* with a deadline; this counts *counterparties* past a threshold, and one person can be
    // both. Reconciling them would need a query per event to find each expense's counterparty, to
    // improve a number that already reads "3 debts to settle" on a screen that shows what they are.
    // The count is items needing attention, not distinct debts, and over-counting errs toward
    // reminding rather than staying quiet.
    if (settings.enabled.contains(NotificationKind.settlementDue)) {
      final ageing = await _ageingDebts();
      if (ageing > 0) {
        counts[NotificationKind.settlementDue] =
            (counts[NotificationKind.settlementDue] ?? 0) + ageing;
      }
    }
    if (counts.isEmpty) {
      // **Nothing to say means nothing is sent.** A daily notification reading "0 items expire this week" is how
      // a reminder becomes something people switch off.
      await _plugin.cancel(id: digestNotificationId);
      await _scheduleDao.cancelForRef(
        refType: digestRefType,
        refId: digestRefType,
        nowUtcMillis: _clock.nowUtcMillis(),
      );
      return 0;
    }

    final when = _nextOccurrence(settings.digestHour, settings.digestMinute);
    final total = counts.values.fold<int>(0, (sum, value) => sum + value);

    final now = _clock.nowUtcMillis();
    await _scheduleDao.replaceForRef(
      refType: digestRefType,
      refId: digestRefType,
      nowUtcMillis: now,
      replacement: NotificationScheduleCompanion.insert(
        id: _uids.generate(),
        // The digest covers whichever kind has the most entries, because the column holds one and the sentence
        // holds several. It is what `watchScheduled` shows, so the row names the thing the user will most likely
        // be reminded about rather than an arbitrary first.
        kind: _dominantKind(counts),
        refType: digestRefType,
        refId: digestRefType,
        scheduledAtUtcMillis: when.toUtc().millisecondsSinceEpoch,
        androidNotificationId: digestNotificationId,
        status: NotificationStatus.scheduled,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await _plugin.zonedSchedule(
      // **Every argument named.** The installed plugin's `zonedSchedule` takes `id`, `scheduledDate` and
      // `notificationDetails` as named parameters and accepts nothing positionally — the analyzer named all three.
      id: digestNotificationId,
      title: _digestTitle(counts),
      body: _digestBody(counts),
      scheduledDate: when,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'alaya_digest',
          'Daily summary',
          channelDescription: 'One message a day about what is coming up.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      // **Inexact, and this is the line that matters** (ARCH_3 §7). `exactAllowWhileIdle` would need
      // `SCHEDULE_EXACT_ALARM`, which Android 14 restricts and Play questions.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // Repeats daily at the same wall-clock time, following the device across a timezone change.
      matchDateTimeComponents: DateTimeComponents.time,
    );
    return total;
  }

  /// The next time [hour]:[minute] comes round in the device's own zone.
  ///
  /// `tz.local` rather than UTC, because a digest is a wall-clock promise: somebody who asked for 9am wants 9am
  /// where they are, and wants it to still be 9am after they fly somewhere. `_ensureTimezones` is what makes
  /// `tz.local` mean that; before it did, every line below was arithmetic on the wrong zone.
  ///
  /// **Tomorrow is built as a calendar day, not as `+ Duration(days: 1)`.** A `Duration` is elapsed time, so
  /// adding twenty-four hours across a DST boundary moves the wall clock by an hour and a 9am digest becomes
  /// 8am or 10am for the rest of the year. Overflowing the day field lets `TZDateTime` resolve the civil date,
  /// which keeps the promise the user actually made.
  ///
  /// A wall time that does not exist — 2:30am on a spring-forward morning — resolves to a nearby instant and
  /// the digest arrives an hour off on that one day, then self-corrects on the next reschedule. Worth knowing;
  /// not worth code, because the alternative is asking the user to pick a time that exists everywhere.
  tz.TZDateTime _nextOccurrence(int hour, int minute) {
    // **The injected clock, not the wall clock.** Every other date-sensitive path in this app takes `Clock`
    // so a `FixedClock` makes it reproducible; this one read the real time, which made "did it schedule for
    // the right moment" the single question in this class no test could ask.
    final now = tz.TZDateTime.from(_clock.now(), tz.local);
    final today = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (today.isAfter(now)) return today;
    return tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day + 1,
      hour,
      minute,
    );
  }

  String _digestTitle(Map<NotificationKind, int> counts) {
    final total = counts.values.fold<int>(0, (sum, value) => sum + value);
    return total == 1 ? '1 thing coming up' : '$total things coming up';
  }

  /// The one sentence.
  ///
  /// **Assembled here rather than from the ARB, and that is a deviation worth recording.** A notification is
  /// built by a `workmanager` isolate with no `BuildContext` and no `AlayaStrings`, so Law U5's "every string
  /// through the ARB" cannot reach it. The alternative — passing pre-localised text from the UI into a background
  /// job that may run days later, in a locale the user has since changed — would be worse than plain English.
  String _digestBody(Map<NotificationKind, int> counts) {
    final parts = <String>[];
    for (final kind in reminderKinds) {
      final count = counts[kind];
      if (count == null || count == 0) continue;
      parts.add(switch (kind) {
        NotificationKind.expiry =>
          count == 1 ? '1 item expires' : '$count items expire',
        NotificationKind.serviceDue =>
          count == 1 ? '1 service due' : '$count services due',
        NotificationKind.recurringDue =>
          count == 1 ? '1 bill due' : '$count bills due',
        NotificationKind.warrantyEnd =>
          count == 1 ? '1 warranty ends' : '$count warranties end',
        NotificationKind.settlementDue =>
          count == 1 ? '1 debt to settle' : '$count debts to settle',
        // Not in `reminderKinds`, so it never reaches here — but the switch is exhaustive so that adding a sixth
        // kind fails to compile rather than falling through to silence. `settlementDue` above IS in that list,
        // so its branch is live and the empty string must not be copied to it.
        NotificationKind.lowStock => '',
      });
    }
    return '${parts.join(', ')} this week';
  }

  NotificationKind? _kindForEvent(CalendarEventType type) => switch (type) {
    CalendarEventType.batchExpiry => NotificationKind.expiry,
    CalendarEventType.serviceDue => NotificationKind.serviceDue,
    CalendarEventType.recurringDue => NotificationKind.recurringDue,
    CalendarEventType.warrantyEnd => NotificationKind.warrantyEnd,
    // A settle-by date is a deadline somebody set, so it belongs in the digest — unlike the two below.
    CalendarEventType.splitSettleBy => NotificationKind.settlementDue,
    // A recorded transaction and a shopping target are history and intent, not things that fall due.
    CalendarEventType.transaction || CalendarEventType.shoppingTarget => null,
  };

  /// Whichever kind contributes most to the digest.
  NotificationKind _dominantKind(Map<NotificationKind, int> counts) {
    var best = reminderKinds.first;
    var most = -1;
    for (final entry in counts.entries) {
      if (entry.value > most) {
        best = entry.key;
        most = entry.value;
      }
    }
    return best;
  }
}

/// The default [AgeingDebtCounter]: nothing ageing.
///
/// A named function rather than an inline closure, so a stack trace names it instead of showing an
/// anonymous closure.
Future<int> _noAgeingDebts() async => 0;
