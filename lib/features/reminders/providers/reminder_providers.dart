/// View-model state for the reminders screen (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/ops_enums.dart';
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

  /// Switches [kind] on or off.
  ///
  /// **Permission is requested here, on the first switch-on, and nowhere else** (ARCH_3 §7). Asking on launch is
  /// the surest way to be denied for good; asking when somebody has just said they want a reminder is the moment
  /// the request makes sense to them. Switching *off* never asks — there is nothing to deliver.
  Future<bool> setEnabled({
    required NotificationKind kind,
    required bool enabled,
  }) async {
    state = const AsyncLoading<void>();
    _wasDenied = false;
    final port = ref.read(reminderPortProvider);

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
    if (result.isFailure) {
      state = AsyncError<void>(
        result.failureOrNull ?? StateError('toggle failed'),
        StackTrace.current,
      );
      return false;
    }
    state = const AsyncData<void>(null);
    ref.invalidate(reminderPermissionProvider);
    return true;
  }

  /// Moves the daily digest.
  Future<bool> setDigestTime({required int hour, required int minute}) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(reminderPortProvider)
        .setDigestTime(hour: hour, minute: minute);
    if (result.isFailure) {
      state = AsyncError<void>(
        result.failureOrNull ?? StateError('time failed'),
        StackTrace.current,
      );
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }

  /// Recomputes and reschedules everything.
  Future<bool> refreshSchedule() async {
    state = const AsyncLoading<void>();
    final result = await ref.read(reminderPortProvider).rescheduleAll();
    state = result.isFailure
        ? AsyncError<void>(
            result.failureOrNull ?? StateError('reschedule failed'),
            StackTrace.current,
          )
        : const AsyncData<void>(null);
    return result.isOk;
  }
}
