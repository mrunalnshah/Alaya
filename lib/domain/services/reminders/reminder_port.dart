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

/// One notification the app has actually scheduled with the OS.
class ScheduledReminder {
  /// Creates a scheduled reminder.
  const ScheduledReminder({
    required this.id,
    required this.kind,
    required this.on,
    required this.androidNotificationId,
  });

  /// The `notification_schedule` row id.
  final String id;

  /// Which kind it is.
  final NotificationKind kind;

  /// The civil date it fires on.
  final DateKey on;

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

  /// Recomputes upcoming events and reschedules everything.
  ///
  /// Idempotent, because the `workmanager` job calls it daily and a user can call it from the screen. Every
  /// schedule is keyed by its source record, so running twice replaces rather than duplicates.
  Future<Result<int, Failure>> rescheduleAll();

  /// Cancels every scheduled notification, for when the last toggle goes off.
  Future<Result<void, Failure>> cancelAll();
}
