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
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';
import 'package:alaya/domain/services/reminders/reminder_port.dart';

/// The production [ReminderPort]: one daily digest, scheduled inexactly, in the device's own timezone.
///
/// **The only file in this phase that imports `flutter_local_notifications` or `timezone`.** Both need a platform
/// channel, so neither runs in a widget test — which is the whole reason `ReminderPort` exists. This is also the
/// largest surface in the phase that could not be compiled against (ARCH_4 R22): `zonedSchedule`,
/// `AndroidScheduleMode`, and `requestNotificationsPermission` have each moved between major versions of the
/// plugin. 8A's `local_auth` took two wrong guesses before compiling; expect at least one here, and expect it to
/// cost this file and nothing else.
///
/// **One notification, not a stream of pings** (ARCH_3 §7). Every enabled kind is folded into a single sentence —
/// *"3 items expire this week, 1 bill due tomorrow"* — delivered once a day at a time the user picked. The
/// contract cannot express a per-item ping, and neither can this.
///
/// **Inexact, always.** `AndroidScheduleMode.inexactAllowWhileIdle` and never `exactAllowWhileIdle`: Android 14
/// restricts `SCHEDULE_EXACT_ALARM` and Play asks why an app needs it. A digest that arrives at 9:07 instead of
/// 9:00 has lost nothing.
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
  }) : _plugin = plugin,
       _db = database,
       _scheduleDao = scheduleDao,
       _calendar = calendar,
       _settings = settings,
       _uids = uids,
       _clock = clock;

  final FlutterLocalNotificationsPlugin _plugin;
  final AlayaDatabase _db;
  final NotificationScheduleDao _scheduleDao;
  final CalendarAggregator _calendar;
  final SettingsRepository _settings;
  final UidGenerator _uids;
  final Clock _clock;

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

  bool _timezonesReady = false;

  Future<void> _ensureTimezones() async {
    if (_timezonesReady) return;
    tz_data.initializeTimeZones();
    _timezonesReady = true;
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
          on: DateKey.fromDateTime(
            DateTime.fromMillisecondsSinceEpoch(
              row.scheduledAtUtcMillis,
              isUtc: true,
            ),
          ),
          androidNotificationId: row.androidNotificationId,
        ),
    ],
  );

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
  Future<Result<void, Failure>> cancelAll() async {
    try {
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
  /// where they are, and wants it to still be 9am after they fly somewhere.
  tz.TZDateTime _nextOccurrence(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    return next;
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
        // Not in `reminderKinds`, so it never reaches here — but the switch is exhaustive so that adding a sixth
        // kind fails to compile rather than falling through to silence.
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
