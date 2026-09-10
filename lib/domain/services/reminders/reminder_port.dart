import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/core/time/date_key.dart';

/// Which kinds of upcoming event a reminder can cover.
///
/// **`NotificationKind` already existed** in `core/enums` and is the converter type on
/// `notification_schedule.kind` — I had written a parallel `NotificationKind` before reading the column, which would
/// have meant two vocabularies for one concept and a mapping between them that could only ever drift.
///
/// `lowStock` is deliberately absent from [reminderKinds]: it is a *state*, not a date. Everything a digest can
/// mention has a day it falls on, and "you are low on rice" has no day — it would fire every morning until
/// somebody shopped.
const List<NotificationKind> reminderKinds = [
  NotificationKind.expiry,
  NotificationKind.serviceDue,
  NotificationKind.recurringDue,
  NotificationKind.warrantyEnd,
  // **This one line is the whole feature switch.** `RemindersScreen` iterates this list, so adding a
  // member makes the toggle appear by itself — and the two exhaustive switches in
  // `LocalNotificationScheduler` stop compiling until they can say something about it, which is the
  // order that makes editing this list safe rather than reckless.
  NotificationKind.settlementDue,
];

/// Whether the operating system will let notifications through.
enum ReminderPermission {
  /// Never asked. The state a fresh install is in.
  ///
  /// **Distinct from `denied`, and the distinction is the whole of ARCH_3 §7's contextual rule.** A screen that
  /// cannot tell "not asked" from "refused" either nags somebody who said no, or never asks at all.
  notRequested,

  /// The user allowed them.
  granted,

  /// The user refused. Asking again is the OS's decision, not this app's.
  denied,
}

/// What the user has switched on, and when the digest goes out.
class ReminderSettings {
  /// Creates settings.
  const ReminderSettings({
    required this.enabled,
    required this.digestHour,
    required this.digestMinute,
  });

  /// A fresh install: everything off (ARCH_3 §7).
  ///
  /// **Off is not a cautious default, it is the specified one.** A finance app that starts pushing notifications
  /// before being asked is uninstalled, and `POST_NOTIFICATIONS` requested on first launch is the surest way to
  /// have it denied for good.
  const ReminderSettings.fresh()
    : enabled = const <NotificationKind>{},
      digestHour = 9,
      digestMinute = 0;

  /// Which kinds are switched on.
  final Set<NotificationKind> enabled;

  /// The hour the daily digest is delivered, 0–23, in the device's local zone.
  final int digestHour;

  /// The minute past [digestHour].
  final int digestMinute;

  /// Whether any reminder at all is on.
  bool get anyEnabled => enabled.isNotEmpty;

  /// A copy with the given fields replaced.
  ReminderSettings copyWith({
    Set<NotificationKind>? enabled,
    int? digestHour,
    int? digestMinute,
  }) => ReminderSettings(
    enabled: enabled ?? this.enabled,
    digestHour: digestHour ?? this.digestHour,
    digestMinute: digestMinute ?? this.digestMinute,
  );
}

/// The zone the schedule was computed in, and whether it can be trusted.
///
/// **Exists because the failure it reports was invisible for months.** `tz.local` silently defaults to UTC, so
/// every digest was booked against UTC wall time while the screen displayed the hour the user had chosen. There
/// was no wrong number anywhere — the schedule was internally consistent and externally five and a half hours
/// out. Surfacing the zone makes the one fact that mattered visible in the one place somebody would look.
class ReminderZone {
  /// Creates a zone report.
  const ReminderZone({required this.name, required this.matchesDevice});

  /// The IANA name, e.g. `Asia/Kolkata`.
  ///
  /// May be an alias of the canonical name for the same rules — `Asia/Calcutta` rather than `Asia/Kolkata`. The
  /// two are one rule set under two labels, so an alias changes what this string reads and nothing else.
  final String name;

  /// Whether this zone reproduces the device's own offsets.
  ///
  /// **False is the interesting value**, and the reason this is not simply a string. A zone that disagrees with
  /// the device delivers at the wrong hour, and the app cannot fix that for the user — but it can say so instead
  /// of scheduling confidently against a guess.
  final bool matchesDevice;
}

/// One notification the app has actually scheduled with the OS.
class ScheduledReminder {
  /// Creates a scheduled reminder.
  const ScheduledReminder({
    required this.id,
    required this.kind,
    required this.at,
    required this.androidNotificationId,
  });

  /// The `notification_schedule` row id.
  final String id;

  /// Which kind it is.
  final NotificationKind kind;

  /// **When it fires, as a local instant** — the moment the OS is actually holding.
  ///
  /// This field replaced a `DateKey` called `on`, and the replacement is the fix for a bug that made a real
  /// scheduling fault invisible for months. The old field was built with
  /// `DateKey.fromDateTime(DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true))`, and `DateKey.fromDateTime`
  /// takes calendar fields exactly as given without converting — so the "date it fires on" was the *UTC* civil
  /// date. East of Greenwich a digest before 05:30 showed yesterday; west of it, tomorrow.
  ///
  /// Worse, the date was all this carried, so the screen had nowhere to read the *time* from and read it from the
  /// user's settings instead. The row therefore displayed the time the user asked for rather than the time the OS
  /// was holding — which is precisely the pair of values that had silently diverged. A reminder system that cannot
  /// be inspected is one nobody trusts (ARCH_5 §7); one that can be inspected and reports the input as though it
  /// were the output is worse, because it answers the question wrongly and confidently.
  ///
  /// **Local rather than UTC on purpose.** Every consumer of this wants a wall clock — the day it lands on and
  /// the hour it arrives — and a local `DateTime` gives both without a call site remembering to convert. The
  /// instant is unchanged either way: `at.toUtc()` returns the stored value.
  final DateTime at;

  /// The civil date [at] falls on, in the device's own zone.
  ///
  /// Derived rather than stored. Two fields for one fact is one too many, and the previous version of this class
  /// had exactly that problem in a subtler form: a stored date computed in one zone beside a time read from
  /// somewhere else entirely.
  DateKey get on => DateKey.fromDateTime(at);

  /// The stable Android id, so it can be cancelled when the underlying record changes (ARCH_3 §7).
  final int androidNotificationId;
}

/// Scheduling, cancelling, and showing what is scheduled (ARCH_3 §7).
///
/// **A port because every line beneath it is a plugin**: `flutter_local_notifications` for delivery, `timezone`
/// for a local-zone digest, `workmanager` for the daily recompute. None runs in a widget test, and §9.1 needs
/// four states per screen.
///
/// **One digest, inexactly scheduled.** ARCH_3 §7 is explicit on both: a stream of individual pings is worse than
/// one sentence a day, and `SCHEDULE_EXACT_ALARM` is restricted on Android 14 with Play asking why it is needed.
/// Nothing in this contract can express an exact time or a per-item ping, which is deliberate — a contract that
/// cannot say the wrong thing is better than a comment asking callers not to.
abstract interface class ReminderPort {
  /// What the user has switched on.
  Stream<ReminderSettings> watchSettings();

  /// Whether the OS will deliver notifications.
  Future<ReminderPermission> permission();

  /// Asks the OS for permission, **contextually**.
  ///
  /// Called the first time a reminder is switched on and never on launch (ARCH_3 §7). Returns the resulting
  /// state, so a caller that was refused can say so instead of silently enabling a switch that does nothing.
  Future<ReminderPermission> requestPermission();

  /// Switches [kind] on or off, scheduling or cancelling as needed.
  Future<Result<ReminderSettings, Failure>> setEnabled({
    required NotificationKind kind,
    required bool enabled,
  });

  /// Moves the daily digest to [hour]:[minute] local time.
  Future<Result<ReminderSettings, Failure>> setDigestTime({
    required int hour,
    required int minute,
  });

  /// What is scheduled right now, soonest first.
  ///
  /// **Shown to the user, which is the point of ARCH_5 §7's row for this table.** A reminder system that cannot
  /// be inspected is one nobody trusts — and the commonest support question about notifications is whether they
  /// are set at all.
  Stream<List<ScheduledReminder>> watchScheduled();

  /// Which zone [watchScheduled]'s times were computed in.
  ///
  /// **Shown to the user for the same reason the schedule itself is** (ARCH_5 §7): a digest arriving at the wrong
  /// hour and one not arriving at all are indistinguishable from the outside, and the zone is the fact that
  /// separates them. A caller that never displays this leaves the user with no way to tell a working reminder
  /// from one booked against the wrong clock — which is the state this app shipped in.
  Future<ReminderZone> zone();

  /// Recomputes upcoming events and reschedules everything.
  ///
  /// Idempotent, because the `workmanager` job calls it daily and a user can call it from the screen. Every
  /// schedule is keyed by its source record, so running twice replaces rather than duplicates.
  Future<Result<int, Failure>> rescheduleAll();

  /// How many notifications the OS says it is currently holding for this app.
  ///
  /// **The one fact this app could never see, and the reason a scheduling fault took weeks.** Everything else
  /// here reports what Alaya *intends*: `watchScheduled` reads the `notification_schedule` table, which is
  /// written before `zonedSchedule` is called and is never reconciled against it. So a digest the OS silently
  /// refused looks identical to one it accepted — same row, same date, same time — and `sendTest` cannot tell
  /// them apart either, because an immediate `show` never touches the alarm path at all.
  ///
  /// Zero while [watchScheduled] emits rows is the diagnosis: Alaya scheduled it, the phone is not holding it.
  Future<Result<int, Failure>> pendingCount();

  /// Posts one notification immediately, to prove the delivery path works.
  ///
  /// **This exists because "no notification arrived" has too many causes to distinguish by waiting.** The
  /// digest is scheduled, inexact, for a wall-clock time that may be tomorrow — so a silent evening tells
  /// you nothing about whether the icon resolves, the permission really landed, or the channel exists. One
  /// notification you can ask for settles all of that in two seconds.
  ///
  /// It is not a feature for daily use and it is not part of the digest: it schedules nothing, writes no
  /// `notification_schedule` row, and uses its own id so it can never collide with the digest.
  Future<Result<void, Failure>> sendTest();

  /// Cancels every scheduled notification, for when the last toggle goes off.
  Future<Result<void, Failure>> cancelAll();
}
