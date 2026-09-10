import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/domain/services/reminders/reminder_port.dart';
import 'package:alaya/features/reminders/providers/reminder_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Settings › Reminders (ARCH_5 §3 archetype D, outside the shell).
///
/// **Shows what is actually scheduled, which is the point of ARCH_5 §7's `notification_schedule` row.** A reminder
/// system that cannot be inspected is one nobody trusts, and the commonest support question about notifications is
/// whether they are set at all.
///
/// **All four toggles start off** (ARCH_3 §7), and permission is requested when the first one goes on — never on
/// launch. A refused request leaves the switch where it was, because a control that says *on* while the OS drops
/// every notification is a control that lies.
///
/// **A refusal is not the only way a switch can fail to move, and for a long time it was the only one this screen
/// could describe.** `permission()` and `requestPermission()` report failure by throwing rather than returning, and
/// the throw travelled past the line that shows a message — so a plugin that could not initialise produced a switch
/// that animated on, snapped back, and said nothing. Every kind behaved identically, because the throw happens
/// before anything kind-specific runs. `_toggle` now reports the controller's own message when there is one.
///
/// **Every time on this screen has exactly one source, and that is a fix rather than tidying.** The scheduled
/// row used to render its date from a UTC conversion and its *time* from the settings above it — so it reported
/// the hour the user had asked for no matter what the OS was holding. When the two diverged, which they did on
/// every device on earth, this screen was the thing that hid it: it answered "is my reminder set for 9am?" with
/// "yes" by reading the question back. The row now renders `ScheduledReminder.at` and nothing else, and the zone
/// those times are computed in is named underneath — because a digest arriving at the wrong hour and one not
/// arriving at all are indistinguishable without it.
class RemindersScreen extends ConsumerWidget {
  /// Creates the screen.
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final settings = ref.watch(reminderSettingsProvider);
    final permission = ref.watch(reminderPermissionProvider).valueOrNull;
    final semantic = context.semantic;

    return Scaffold(
      appBar: AppBar(title: Text(strings.remindersTitle)),
      body: settings.when(
        loading: () => AlayaListSkeleton(label: strings.remindersLoading),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(reminderSettingsProvider),
        ),
        data: (current) => ListView(
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
          children: [
            Padding(
              padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
              child: Container(
                padding: const EdgeInsets.all(AlayaSpacing.md),
                decoration: BoxDecoration(
                  color: semantic.muted.withValues(alpha: 0.12),
                  borderRadius: AlayaRadii.borderMd,
                ),
                child: Text(
                  strings.remindersDigestExplainer,
                  style: AlayaTypography.body,
                ),
              ),
            ),

            if (permission == ReminderPermission.denied)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AlayaSpacing.screenEdge,
                ),
                child: Container(
                  padding: const EdgeInsets.all(AlayaSpacing.md),
                  decoration: BoxDecoration(
                    color: semantic.warning.withValues(alpha: 0.12),
                    borderRadius: AlayaRadii.borderMd,
                  ),
                  // Names the place to fix it. "Notifications are blocked" without saying where is a dead end.
                  child: Text(
                    strings.remindersBlocked,
                    style: AlayaTypography.bodyEmphasis,
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                AlayaSpacing.screenEdge,
                AlayaSpacing.lg,
                AlayaSpacing.screenEdge,
                AlayaSpacing.xs,
              ),
              child: SectionHeader(label: strings.remindersKindsHeader),
            ),

            for (final kind in reminderKinds)
              SwitchListTile(
                value: current.enabled.contains(kind),
                onChanged: (value) =>
                    _toggle(context, ref, strings, kind: kind, value: value),
                title: Text(
                  _kindLabel(strings, kind),
                  style: AlayaTypography.body,
                ),
                subtitle: Text(
                  _kindHelp(strings, kind),
                  style: AlayaTypography.caption.copyWith(
                    color: semantic.muted,
                  ),
                ),
              ),

            const SizedBox(height: AlayaSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlayaSpacing.screenEdge,
              ),
              child: SectionHeader(label: strings.remindersTimeHeader),
            ),
            ListTile(
              leading: Icon(
                Icons.schedule_outlined,
                size: AlayaIconSize.lg,
                color: semantic.muted,
              ),
              title: Text(
                strings.remindersTimeTitle,
                style: AlayaTypography.cardTitle,
              ),
              subtitle: Text(
                strings.remindersTimeBody(
                  _timeLabel(
                    context,
                    TimeOfDay(
                      hour: current.digestHour,
                      minute: current.digestMinute,
                    ),
                  ),
                ),
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
              // Disabled while nothing is on: a time picker for a digest that will never be sent is a control
              // with nothing behind it (ARCH_5 §10).
              enabled: current.anyEnabled,
              onTap: () => _pickTime(context, ref, strings, current),
            ),

            // **The zone every time on this screen is computed in.**
            //
            // Only while something is on, like the test button below — a zone qualifying a digest that will
            // never be sent is noise. This is the line whose absence let a five-and-a-half-hour error look
            // like a broken notification: the schedule was internally consistent, the screen agreed with
            // itself, and the one fact that would have named the fault was displayed nowhere.
            if (current.anyEnabled) const _ZoneNote(),

            // **Offered whenever a reminder is on, not only when nothing is due.** "It is scheduled
            // for tomorrow" and "the delivery path is broken" look identical from the outside, and this
            // is the only thing that separates them.
            if (current.anyEnabled)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AlayaSpacing.screenEdge,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _sendTest(context, ref, strings),
                    icon: const Icon(
                      Icons.notifications_active_outlined,
                      size: AlayaIconSize.md,
                    ),
                    label: Text(
                      strings.remindersSendTest,
                      style: AlayaTypography.button,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: AlayaSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlayaSpacing.screenEdge,
              ),
              child: SectionHeader(label: strings.remindersScheduledHeader),
            ),
            _ScheduledList(anyEnabled: current.anyEnabled),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings, {
    required NotificationKind kind,
    required bool value,
  }) async {
    final controller = ref.read(reminderControllerProvider.notifier);
    final ok = await controller.setEnabled(kind: kind, enabled: value);
    if (!context.mounted || ok) return;

    // **The reason, verbatim, when there is one.** A switch that moved back in silence was the whole complaint:
    // `permission()` and `requestPermission()` report failure by throwing, the throw travelled past this line,
    // and the user got a control that animated on and off saying nothing.
    //
    // The precedence is deliberate. A refusal by the OS is actionable in system settings and earns its own
    // sentence; anything else is a runtime string — a missing `@drawable/ic_notification`, a channel the OS
    // rejected — and reporting it raw is the same decision `_sendTest` below already makes, for the same reason.
    showFailureSnack(
      context,
      message: controller.wasDenied
          ? strings.remindersDenied
          : (controller.lastError ?? strings.remindersToggleFailed),
    );
  }

  Future<void> _sendTest(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    final error = await ref
        .read(reminderControllerProvider.notifier)
        .sendTest();
    if (!context.mounted) return;
    // **The failure message is reported verbatim.** A missing `@drawable/ic_notification` throws at post
    // time and nowhere else — the compiler never sees that string — so swallowing it into a generic
    // "something went wrong" would discard the only diagnosis available.
    error == null
        ? showResultSnack(context, message: strings.remindersTestSent)
        : showFailureSnack(context, message: error);
  }

  Future<void> _pickTime(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
    ReminderSettings current,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: current.digestHour,
        minute: current.digestMinute,
      ),
    );
    if (picked == null || !context.mounted) return;

    final controller = ref.read(reminderControllerProvider.notifier);
    final ok = await controller.setDigestTime(
      hour: picked.hour,
      minute: picked.minute,
    );
    if (!context.mounted) return;
    // Same reasoning as `_toggle`: `setDigestTime` schedules as well as writes, so it reaches the same plugin
    // surface and can fail the same way.
    ok
        ? showResultSnack(context, message: strings.remindersTimeSaved)
        : showFailureSnack(
            context,
            message: controller.lastError ?? strings.remindersToggleFailed,
          );
  }

  String _kindLabel(AlayaStrings strings, NotificationKind kind) =>
      switch (kind) {
        NotificationKind.expiry => strings.reminderKindExpiry,
        NotificationKind.serviceDue => strings.reminderKindService,
        NotificationKind.recurringDue => strings.reminderKindRecurring,
        NotificationKind.warrantyEnd => strings.reminderKindWarranty,
        NotificationKind.settlementDue => strings.reminderKindSettlement,
        NotificationKind.lowStock => strings.reminderKindLowStock,
      };

  String _kindHelp(AlayaStrings strings, NotificationKind kind) =>
      switch (kind) {
        NotificationKind.expiry => strings.reminderKindExpiryHelp,
        NotificationKind.serviceDue => strings.reminderKindServiceHelp,
        NotificationKind.recurringDue => strings.reminderKindRecurringHelp,
        NotificationKind.warrantyEnd => strings.reminderKindWarrantyHelp,
        NotificationKind.settlementDue => strings.reminderKindSettlementHelp,
        NotificationKind.lowStock => strings.reminderKindLowStockHelp,
      };
}

/// Names the zone the schedule was computed in, or says it could not be worked out.
class _ZoneNote extends ConsumerWidget {
  const _ZoneNote();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final zone = ref.watch(reminderZoneProvider);
    final semantic = context.semantic;

    return zone.when(
      // Nothing while resolving. This is a caption qualifying data the screen has already shown rather than
      // the screen's own content, so Law U4's four states are the outer `settings.when` — a skeleton here
      // would flicker a line of text on every visit and inform nobody.
      loading: () => const SizedBox.shrink(),
      // **A failed resolution reads exactly like an unmatched one, deliberately.** Both mean the digest may
      // arrive at the wrong hour and the user's next step is identical. Falling silent on the error branch is
      // the behaviour this whole line exists to end.
      error: (error, stack) =>
          _line(strings.remindersZoneUnknown, semantic.warning),
      data: (value) => value.matchesDevice
          ? _line(strings.remindersZone(value.name), semantic.muted)
          : _line(strings.remindersZoneUnknown, semantic.warning),
    );
  }

  Widget _line(String text, Color color) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AlayaSpacing.screenEdge,
      AlayaSpacing.xs,
      AlayaSpacing.screenEdge,
      0,
    ),
    child: Text(text, style: AlayaTypography.caption.copyWith(color: color)),
  );
}

/// What the OS is currently holding.
class _ScheduledList extends ConsumerWidget {
  const _ScheduledList({required this.anyEnabled});

  /// Whether any reminder kind is switched on.
  ///
  /// Passed in rather than read here, because the settings are already watched by the screen above and
  /// a second watch would be a second source for one fact.
  ///
  /// **The settings object itself is no longer passed, and that removal is the fix.** It was here so a row
  /// could print the digest time beside its date — which meant the row reported an input as though it were an
  /// output, and hid the divergence between the two. Everything a row needs is now on the row.
  final bool anyEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final scheduled = ref.watch(scheduledRemindersProvider);

    return scheduled.when(
      loading: () => AlayaListSkeleton(label: strings.remindersLoading),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: error.toString(),
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(scheduledRemindersProvider),
      ),
      data: (rows) => rows.isEmpty
          // **Two different silences, and they used to read the same.**
          //
          // With every reminder off, nothing scheduled is correct and the fix is to switch one on.
          // With reminders on and nothing due in the next seven days, nothing scheduled is *also*
          // correct — `_scheduleDigest` deliberately sends nothing rather than a message reading
          // "0 items expire this week". But the old copy said "turn on a reminder above", which is
          // what somebody had already done. The app told them to do the thing they had done and
          // looked broken as a result.
          //
          // The second case also gets a way to act: **Check now** reruns the scan, so the feature is
          // testable without waiting for real data to fall due. That was the deeper problem — there
          // was no way to tell a working reminder from a broken one.
          ? _NothingScheduled(anyEnabled: anyEnabled)
          : Column(
              children: [
                // **Whether the phone agrees.** The rows below are Alaya's record; this line is the OS's.
                const _OsAgreement(),
                for (final row in rows)
                  ListTile(
                    leading: Icon(
                      Icons.notifications_active_outlined,
                      size: AlayaIconSize.lg,
                      color: context.semantic.muted,
                    ),
                    title: Text(
                      strings.remindersDigestRow,
                      style: AlayaTypography.cardTitle,
                    ),
                    // **Date and time, both read from `row.at` and nowhere else.** The date goes through
                    // `DateText` per Law U7; the time goes through `MaterialLocalizations`, so a phone set
                    // to a 12-hour clock reads `9:00 am` and one set to 24 reads `09:00` without this file
                    // deciding which.
                    //
                    // `Wrap` rather than `Row`: two fixed-size children in a `Row` have no strategy for
                    // growth, and the 320dp × textScaler 2.0 gate roughly halves the usable width. This also
                    // removed the ` · ` separator, which was a raw string literal (Law U5) doing a job that
                    // spacing does better.
                    subtitle: Wrap(
                      spacing: AlayaSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DateText(row.on, muted: true),
                        Text(
                          _timeLabel(context, TimeOfDay.fromDateTime(row.at)),
                          style: AlayaTypography.caption.copyWith(
                            color: context.semantic.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Whether the OS is holding an alarm for the rows beneath it.
///
/// **The line that would have ended this in a minute.** Every other thing on this screen is Alaya reporting on
/// itself: the toggles, the digest time, the scheduled rows, the zone. All four agreed with each other while no
/// notification arrived, because all four describe the app's intent and none of them asks the phone. A `show`
/// test does not close the gap either — it posts directly and never touches the alarm path.
///
/// So a scheduled row with nothing behind it looked exactly like a scheduled row that worked. This is the only
/// widget in the feature that can contradict the others.
class _OsAgreement extends ConsumerWidget {
  const _OsAgreement();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final pending = ref.watch(pendingNotificationCountProvider);
    final semantic = context.semantic;

    return pending.when(
      loading: () => const SizedBox.shrink(),
      // **An error and a zero are one message.** "The phone says nothing is scheduled" and "the phone could not
      // be asked" differ to a developer and not at all to somebody whose reminder did not arrive, and both mean
      // the row below cannot be trusted. Distinguishing them on screen would be precision about the wrong thing.
      error: (error, stack) =>
          _line(strings.remindersOsMissing, semantic.warning),
      data: (count) => count == null || count == 0
          ? _line(strings.remindersOsMissing, semantic.warning)
          : _line(strings.remindersOsHolding, semantic.muted),
    );
  }

  Widget _line(String text, Color color) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AlayaSpacing.screenEdge,
      AlayaSpacing.xs,
      AlayaSpacing.screenEdge,
      AlayaSpacing.xs,
    ),
    child: Text(text, style: AlayaTypography.caption.copyWith(color: color)),
  );
}

/// Why nothing is scheduled, and what to do about it.
///
/// **The distinction this widget exists for:** reminders off is a different situation from reminders on
/// with nothing due, and they used to produce identical copy. The second one is the case that makes a
/// working feature look broken.
class _NothingScheduled extends ConsumerStatefulWidget {
  const _NothingScheduled({required this.anyEnabled});

  final bool anyEnabled;

  @override
  ConsumerState<_NothingScheduled> createState() => _NothingScheduledState();
}

class _NothingScheduledState extends ConsumerState<_NothingScheduled> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);

    // Nothing on: the fix really is to switch something on, so keep the original copy.
    if (!widget.anyEnabled) {
      return EmptyState(
        title: strings.remindersNoneScheduledTitle,
        body: strings.remindersNoneScheduledBody,
        icon: Icons.notifications_none_outlined,
      );
    }

    // Reminders on, nothing due. Say so, and offer the scan.
    return EmptyState(
      title: strings.remindersNothingDueTitle,
      body: strings.remindersNothingDueBody,
      icon: Icons.event_available_outlined,
      actionLabel: _checking
          ? strings.remindersChecking
          : strings.remindersCheckNow,
      onAction: _checking ? null : _check,
    );
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final controller = ref.read(reminderControllerProvider.notifier);
    final count = await controller.refreshSchedule();
    if (!mounted) return;
    setState(() => _checking = false);

    final strings = AlayaStrings.of(context);
    if (count == null) {
      // The controller's own message when it has one, for the same reason `_toggle` reports it: a reschedule
      // reaches the plugin, and a plugin that cannot initialise says so in a string nothing else will show.
      showFailureSnack(
        context,
        message: controller.lastError ?? strings.remindersToggleFailed,
      );
      return;
    }
    // **Reports the count either way.** "Nothing found" is a result, not a failure — and it is the
    // sentence that tells somebody their reminders are working and their week is simply clear.
    showResultSnack(
      context,
      message: count > 0
          ? strings.remindersFoundCount(count)
          : strings.remindersFoundNothing,
    );
  }
}

/// A time of day in the reader's own convention.
///
/// **File scope, because two call sites need it** — the digest-time row and each scheduled row — and they
/// must agree. They did not before: one printed a zero-padded 24-hour string and the other printed the same
/// string for a different value, which is how a divergence between them stayed invisible.
///
/// Goes through `MaterialLocalizations` rather than `padLeft`, so `en_IN` gets `9:00 am` and `de_DE` gets
/// `09:00`, and a phone with the 24-hour setting on is honoured either way. Law U5 is satisfied without an
/// ARB key, because a formatted time is not copy.
String _timeLabel(BuildContext context, TimeOfDay time) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      time,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
