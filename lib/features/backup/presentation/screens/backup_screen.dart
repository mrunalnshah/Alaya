import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart';
import 'package:alaya/features/backup/providers/backup_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Settings › Data › Backup (ARCH_5 §3 archetype D, outside the shell).
///
/// **The warning appears on the confirmation sheet, every single time** (ARCH_3 §3.4). Not in Settings, not a
/// tooltip, not once at first use: both export paths — save-to-a-location and share — go through
/// [_confirmExport], and neither can reach the file system without it. That is a structural guarantee rather
/// than a discipline, which is what a rule containing the words "every single time" needs.
///
/// **Two export shapes, because they answer different questions.** *Save a copy* raises the Storage Access
/// Framework's create-document sheet and puts a file where the user chose; *Share* hands it to whatever app they
/// pick. Neither needs a storage permission, which is why there is no `WRITE_EXTERNAL_STORAGE` anywhere in this
/// project (ARCH_3 §3.3).
class BackupScreen extends ConsumerWidget {
  /// Creates the screen.
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final history = ref.watch(backupHistoryProvider);
    final working = ref.watch(backupControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(strings.backupTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AlayaSpacing.screenEdge,
              AlayaSpacing.lg,
              AlayaSpacing.screenEdge,
              AlayaSpacing.xs,
            ),
            child: SectionHeader(label: strings.backupMakeHeader),
          ),
          // Hidden rather than disabled while `saveFile` is unavailable on the pinned `file_picker`: a row that
          // can never become enabled is the dead control ARCH_5 §10 objects to, and Share does the same job
          // through the same kind of system sheet.
          if (ref.watch(dataTransferPortProvider).canSaveToLocation)
            ListTile(
              leading: Icon(
                Icons.save_alt_outlined,
                size: AlayaIconSize.lg,
                color: context.semantic.muted,
              ),
              title: Text(
                strings.backupSaveTitle,
                style: AlayaTypography.cardTitle,
              ),
              subtitle: Text(
                strings.backupSaveBody,
                style: AlayaTypography.caption.copyWith(
                  color: context.semantic.muted,
                ),
              ),
              enabled: !working,
              onTap: () => _export(context, ref, strings, toLocation: true),
            ),
          ListTile(
            leading: Icon(
              Icons.ios_share_outlined,
              size: AlayaIconSize.lg,
              color: context.semantic.muted,
            ),
            title: Text(
              strings.backupShareTitle,
              style: AlayaTypography.cardTitle,
            ),
            subtitle: Text(
              strings.backupShareBody,
              style: AlayaTypography.caption.copyWith(
                color: context.semantic.muted,
              ),
            ),
            enabled: !working,
            onTap: () => _export(context, ref, strings, toLocation: false),
          ),
          const SizedBox(height: AlayaSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AlayaSpacing.screenEdge,
            ),
            child: SectionHeader(label: strings.backupRestoreHeader),
          ),
          ListTile(
            leading: Icon(
              Icons.settings_backup_restore_outlined,
              size: AlayaIconSize.lg,
              color: context.semantic.muted,
            ),
            title: Text(
              strings.backupRestoreTitle,
              style: AlayaTypography.cardTitle,
            ),
            subtitle: Text(
              strings.backupRestoreBody,
              style: AlayaTypography.caption.copyWith(
                color: context.semantic.muted,
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: AlayaIconSize.md,
              color: context.semantic.muted,
            ),
            onTap: () => context.push(Routes.settingsRestore),
          ),
          const SizedBox(height: AlayaSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AlayaSpacing.screenEdge,
            ),
            child: SectionHeader(label: strings.backupHistoryHeader),
          ),
          history.when(
            loading: () =>
                AlayaListSkeleton(label: strings.backupHistoryLoading),
            error: (error, stack) => ErrorState(
              title: strings.errorTitleGeneric,
              body: error.toString(),
              retryLabel: strings.actionRetry,
              onRetry: () => ref.invalidate(backupHistoryProvider),
            ),
            data: (rows) => rows.isEmpty
                ? EmptyState(
                    title: strings.backupHistoryEmptyTitle,
                    body: strings.backupHistoryEmptyBody,
                    icon: Icons.history_outlined,
                  )
                : Column(
                    children: [
                      for (final row in rows) _HistoryRow(record: row),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings, {
    required bool toLocation,
  }) async {
    if (!await _confirmExport(context, strings)) return;
    if (!context.mounted) return;
    final controller = ref.read(backupControllerProvider.notifier);
    final ok = toLocation
        ? await controller.exportToLocation()
        : await controller.exportAndShare();
    if (!context.mounted) return;
    if (!ok) {
      // Cancelling the system sheet is neither a success nor a failure, so it says nothing at all — a snack
      // either way would be the app commenting on the user changing their mind.
      if (controller.wasCancelled) return;
      showFailureSnack(context, message: strings.backupFailed);
      return;
    }
    final artefact = controller.lastArtefact;
    showResultSnack(
      context,
      message: artefact == null
          ? strings.backupDone
          : strings.backupDoneNamed(artefact.fileName),
    );
  }

  /// The gate every export passes through.
  ///
  /// **ARCH_3 §3.4, verbatim and unconditional.** There is no path to a written file that skips this, and the
  /// warning is the *body* of the sheet rather than a line beneath the button — a confirmation whose body is the
  /// warning cannot be dismissed without reading it.
  Future<bool> _confirmExport(BuildContext context, AlayaStrings strings) =>
      ConfirmSheet.show(
        context,
        title: strings.backupConfirmTitle,
        body: strings.backupNotEncryptedWarning,
        confirmLabel: strings.backupConfirmAction,
        cancelLabel: strings.actionCancel,
      );
}

/// One past backup.
class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({required this.record});

  final BackupRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return ListTile(
      leading: Icon(
        Icons.insert_drive_file_outlined,
        size: AlayaIconSize.lg,
        color: semantic.muted,
      ),
      title: Text(record.fileName, style: AlayaTypography.cardTitle),
      subtitle: Row(
        children: [
          // The plain constructor, not `DateText.relative`: that one fixes its own style and needs a `Clock`,
          // and a backup taken three weeks ago reads better as a date than as "3 weeks ago" anyway.
          DateText(
            DateKey.fromDateTime(
              DateTime.fromMillisecondsSinceEpoch(
                record.takenAtUtcMillis,
                isUtc: true,
              ),
            ),
          ),
          const SizedBox(width: AlayaSpacing.xs),
          Expanded(
            child: Text(
              strings.backupHistorySize(_readableSize(record.sizeBytes)),
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
          ),
        ],
      ),
      trailing: IconButton(
        onPressed: () => _forget(context, ref, strings),
        tooltip: strings.backupForget,
        icon: Icon(Icons.close, size: AlayaIconSize.md, color: semantic.muted),
      ),
    );
  }

  Future<void> _forget(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    // The body says what does *not* happen, because "remove" over a backup reads as deleting the file — and this
    // app has no reach into the Drive folder or chat thread the user put it in.
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.backupForgetConfirmTitle,
      body: strings.backupForgetConfirmBody,
      confirmLabel: strings.backupForget,
      cancelLabel: strings.actionCancel,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await ref
        .read(backupControllerProvider.notifier)
        .forget(record.id);
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.backupForgotten)
        : showFailureSnack(context, message: strings.backupForgetFailed);
  }

  /// Bytes as something a person reads.
  ///
  /// Formatted here rather than in the ARB because the unit changes with the magnitude, and a translator cannot
  /// choose between KB and MB inside one placeholder.
  String _readableSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
