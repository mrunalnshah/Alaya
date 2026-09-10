/// View-model state for the reminders screen (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/domain/services/reminders/reminder_port.dart';

/// What the user has switched on.
final reminderSettingsProvider = StreamProvider<ReminderSettings>(
  (ref) => ref.watch(reminderPortProvider).watchSettings(),
);

/// What is scheduled right now.
final scheduledRemindersProvider = StreamProvider<List<ScheduledReminder>>(
  (ref) => ref.watch(reminderPortProvider).watchScheduled(),
);

/// Whether the OS will deliver notifications.
final reminderPermissionProvider = FutureProvider<ReminderPermission>(
  (ref) => ref.watch(reminderPortProvider).permission(),
);

/// Which zone the schedule was computed in.
///
/// **Read once and not invalidated on a toggle**, unlike [reminderPermissionProvider]. Permission changes when
/// the user answers a prompt; the device's zone changes when they fly, which no action on this screen causes.
/// Re-resolving it after every switch would run a six-hundred-zone match to learn what it already knew.
final reminderZoneProvider = FutureProvider<ReminderZone>(
  (ref) => ref.watch(reminderPortProvider).zone(),
);

/// How many notifications the OS is holding, as opposed to how many Alaya recorded.
///
/// **The only provider on this screen that does not read Alaya's own opinion.** Everything else — the settings,
/// the schedule table, the zone — is the app describing itself, and a scheduling call the OS refused leaves all
/// three of them unchanged. This is the one that can disagree, which is the entire reason it exists.
final pendingNotificationCountProvider = FutureProvider<int?>(
  (ref) async {
    final result = await ref.watch(reminderPortProvider).pendingCount();
    // **Null for a failure, not zero.** They mean different things to the reader — "the phone says nothing is
    // scheduled" versus "the phone could not be asked" — but they mean the same thing for trust, so the screen
    // warns on both and the distinction stops here.
    return result.valueOrNull;
  },
);

/// Toggling kinds and moving the digest.
final reminderControllerProvider =
    NotifierProvider<ReminderController, AsyncValue<void>>(
      ReminderController.new,
    );

/// Asks for permission at the right moment, then schedules.
class ReminderController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Whether the last attempt was refused by the OS rather than by the app.
  bool get wasDenied => _wasDenied;
  bool _wasDenied = false;

  /// What went wrong last, verbatim, or null.
  ///
  /// **Reported rather than summarised, for the reason `sendTest` already is.** A missing
  /// `@drawable/ic_notification`, a plugin that failed to initialise, a channel the OS rejected — every one of
  /// these is a runtime string nothing checks at build time, and a screen that folds them into "that could not be
  /// changed" throws away the only diagnosis available.
  String? get lastError => _lastError;
  String? _lastError;

  /// Switches [kind] on or off.
  ///
  /// **Permission is requested here, on the first switch-on, and nowhere else** (ARCH_3 §7). Asking on launch is
  /// the surest way to be denied for good; asking when somebody has just said they want a reminder is the moment
  /// the request makes sense to them. Switching *off* never asks — there is nothing to deliver.
  ///
  /// ## Why the whole body is inside a `try`
  ///
  /// **Only `port.setEnabled` reported failure as a value; `permission()` and `requestPermission()` reported it
  /// by throwing, and nothing caught them.** Both begin with `_ensurePlugin()`, which initialises the plugin
  /// against `@drawable/ic_notification` — a resource whose absence is a runtime error and nothing else.
  ///
  /// An exception there produced exactly the symptom that was reported: the switch animates on, rebuilds from
  /// `reminderSettingsProvider`, and goes off — with **no message at all**, because the line that shows one is
  /// two awaits further down and never runs. Every kind behaved the same way, because the throw happens before
  /// anything kind-specific.
  ///
  /// A control that moves and moves back while saying nothing is the worst version of this screen's own rule:
  /// a screen must be able to report the app's own failure.
  Future<bool> setEnabled({
    required NotificationKind kind,
    required bool enabled,
  }) async {
    state = const AsyncLoading<void>();
    _wasDenied = false;
    _lastError = null;
    final port = ref.read(reminderPortProvider);

    try {
      if (enabled) {
        var permission = await port.permission();
        if (permission == ReminderPermission.notRequested) {
          permission = await port.requestPermission();
        }
        if (permission != ReminderPermission.granted) {
          // **The switch does not move.** Turning it on while the OS drops every notification would be a control
          // that lies, and the screen shows the refusal instead so the user can fix it in system settings.
          _wasDenied = true;
          state = const AsyncData<void>(null);
          ref.invalidate(reminderPermissionProvider);
          return false;
        }
      }

      final result = await port.setEnabled(kind: kind, enabled: enabled);
      final failure = result.failureOrNull;
      if (failure != null) {
        _lastError = failure.message;
        state = AsyncError<void>(failure, StackTrace.current);
        return false;
      }
      state = const AsyncData<void>(null);
      ref.invalidate(reminderPermissionProvider);
      // A toggle schedules or cancels, so what the OS holds has changed.
      ref.invalidate(pendingNotificationCountProvider);
      return true;
    } on Object catch (error, stack) {
      // Anything the plugin threw rather than returned. `toString()` on purpose: a `PlatformException` names the
      // resource or the channel that failed, and that name is the entire value of this branch.
      _lastError = error.toString();
      state = AsyncError<void>(error, stack);
      return false;
    }
  }

  /// Moves the daily digest.
  Future<bool> setDigestTime({required int hour, required int minute}) async {
    state = const AsyncLoading<void>();
    _lastError = null;
    try {
      final result = await ref
          .read(reminderPortProvider)
          .setDigestTime(hour: hour, minute: minute);
      final failure = result.failureOrNull;
      if (failure != null) {
        _lastError = failure.message;
        state = AsyncError<void>(failure, StackTrace.current);
        return false;
      }
      state = const AsyncData<void>(null);
      ref.invalidate(pendingNotificationCountProvider);
      return true;
    } on Object catch (error, stack) {
      // `setDigestTime` schedules as well as writes, so it reaches the same plugin surface `setEnabled` does.
      _lastError = error.toString();
      state = AsyncError<void>(error, stack);
      return false;
    }
  }

  /// Recomputes and reschedules everything, returning how many things are coming up.
  ///
  /// **Returns the count, not a bool.** `rescheduleAll` already reports how many items fell inside the
  /// horizon and the old signature threw it away — so the screen could tell the user *that* a scan ran
  /// but not *what it found*. "Nothing found" is the single most useful sentence here: it distinguishes a
  /// working reminder from a broken one, which was exactly what nobody could tell.
  ///
  /// Null means the reschedule failed. Zero means it succeeded and there is nothing due.
  Future<int?> refreshSchedule() async {
    state = const AsyncLoading<void>();
    _lastError = null;
    try {
      final result = await ref.read(reminderPortProvider).rescheduleAll();
      final failure = result.failureOrNull;
      if (failure != null) {
        _lastError = failure.message;
        state = AsyncError<void>(failure, StackTrace.current);
        return null;
      }
      state = const AsyncData<void>(null);
      // **The zone is re-read after a reschedule, and only here.** A reschedule is the one moment the adapter
      // re-resolves — it compares the device's current offset and starts again if it moved — so it is also the
      // one moment the displayed zone can have gone stale. Invalidating anywhere else would recompute nothing.
      ref.invalidate(reminderZoneProvider);
      // The alarm the OS holds was just replaced, so the count taken before it is stale.
      ref.invalidate(pendingNotificationCountProvider);
      return result.valueOrNull ?? 0;
    } on Object catch (error, stack) {
      _lastError = error.toString();
      state = AsyncError<void>(error, stack);
      return null;
    }
  }

  /// Sends one notification now, and reports whether it arrived at the OS.
  ///
  /// Returns the failure message rather than a bool: when this fails the *reason* is the whole value —
  /// a missing `@drawable/ic_notification` is a runtime string nothing checks at build time, and this is
  /// the only place it can surface.
  ///
  /// **Now also catches**, for the same reason the toggles do: `sendTest` reaches `_ensurePlugin` too, and a
  /// throw here was reaching the widget as an unhandled future rather than as the message it was designed to be.
  Future<String?> sendTest() async {
    try {
      final result = await ref.read(reminderPortProvider).sendTest();
      return result.isOk ? null : (result.failureOrNull?.message ?? 'failed');
    } on Object catch (error) {
      return error.toString();
    }
  }
}
