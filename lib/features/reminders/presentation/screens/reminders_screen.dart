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
                  _clock(current.digestHour, current.digestMinute),
                ),
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
              // Disabled while nothing is on: a time picker for a digest that will never be sent is a control
              // with nothing behind it (ARCH_5 §10).
              enabled: current.anyEnabled,
              onTap: () => _pickTime(context, ref, strings, current),
            ),
            const SizedBox(height: AlayaSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlayaSpacing.screenEdge,
              ),
              child: SectionHeader(label: strings.remindersScheduledHeader),
            ),
            const _ScheduledList(),
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
    showFailureSnack(
      context,
      message: controller.wasDenied
          ? strings.remindersDenied
          : strings.remindersToggleFailed,
    );
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
    final ok = await ref
        .read(reminderControllerProvider.notifier)
        .setDigestTime(hour: picked.hour, minute: picked.minute);
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.remindersTimeSaved)
        : showFailureSnack(context, message: strings.remindersToggleFailed);
  }

  String _clock(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String _kindLabel(AlayaStrings strings, NotificationKind kind) =>
      switch (kind) {
        NotificationKind.expiry => strings.reminderKindExpiry,
        NotificationKind.serviceDue => strings.reminderKindService,
        NotificationKind.recurringDue => strings.reminderKindRecurring,
        NotificationKind.warrantyEnd => strings.reminderKindWarranty,
        NotificationKind.lowStock => strings.reminderKindLowStock,
      };

  String _kindHelp(AlayaStrings strings, NotificationKind kind) =>
      switch (kind) {
        NotificationKind.expiry => strings.reminderKindExpiryHelp,
        NotificationKind.serviceDue => strings.reminderKindServiceHelp,
        NotificationKind.recurringDue => strings.reminderKindRecurringHelp,
        NotificationKind.warrantyEnd => strings.reminderKindWarrantyHelp,
        NotificationKind.lowStock => strings.reminderKindLowStockHelp,
      };
}

/// What the OS is currently holding.
class _ScheduledList extends ConsumerWidget {
  const _ScheduledList();

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
          // Empty is the normal state with everything off, so it explains rather than apologises.
          ? EmptyState(
              title: strings.remindersNoneScheduledTitle,
              body: strings.remindersNoneScheduledBody,
              icon: Icons.notifications_none_outlined,
            )
          : Column(
              children: [
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
                    subtitle: DateText(row.on),
                  ),
              ],
            ),
    );
  }
}
