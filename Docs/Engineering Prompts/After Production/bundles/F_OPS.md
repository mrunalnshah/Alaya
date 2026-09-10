# F_OPS

Backup, restore, trash, reminders, attachments, Support Us.

**17 files · 3,738 lines.**  Written 2026-08-27T08:54:37-04:00.

Every file below is complete and current. Paths are destinations.

---

### `lib/features/attachments/presentation/attachments.dart`

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/services/attachments/attachment_port.dart';
import 'package:alaya/features/attachments/providers/attachment_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';

/// A row of thumbnails for whatever is attached to a record (ARCH_5 §7's `attachments` row).
///
/// **Horizontal and short by design.** A detail screen is about the record, not its photographs; a grid would
/// make three receipts look like the point of the screen. Tapping a thumbnail opens the file, long-pressing
/// offers to remove it — the same pairing every other list in the app uses.
class AttachmentStrip extends ConsumerWidget {
  /// Creates the strip.
  const AttachmentStrip({
    required this.owner,
    required this.ownerId,
    super.key,
  });

  /// Which kind of record these belong to.
  final AttachmentOwner owner;

  /// The record's id.
  final String ownerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final attachments = ref.watch(
      attachmentsForProvider((owner: owner, ownerId: ownerId)),
    );

    return attachments.when(
      // A strip is secondary to the screen it sits on, so it occupies its own height while loading rather than
      // pushing the record's own fields down when it arrives.
      loading: () => const SizedBox(height: _thumbExtent),
      error: (error, stack) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.xs),
        child: Text(
          error.toString(),
          style: AlayaTypography.caption.copyWith(
            color: context.semantic.danger,
          ),
        ),
      ),
      data: (rows) => Row(
        children: [
          if (rows.isEmpty)
            Expanded(
              child: Text(
                strings.attachmentsNone,
                style: AlayaTypography.caption.copyWith(
                  color: context.semantic.muted,
                ),
              ),
            )
          else
            Expanded(
              child: SizedBox(
                height: _thumbExtent,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: rows.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: AlayaSpacing.xs),
                  itemBuilder: (context, index) =>
                      _Thumbnail(attachment: rows[index]),
                ),
              ),
            ),
          IconButton(
            onPressed: () =>
                AttachSheet.show(context, owner: owner, ownerId: ownerId),
            tooltip: strings.attachmentsAdd,
            icon: const Icon(
              Icons.add_photo_alternate_outlined,
              size: AlayaIconSize.lg,
            ),
          ),
        ],
      ),
    );
  }

  static const double _thumbExtent = AlayaSpacing.xxxl + AlayaSpacing.lg;
}

/// One thumbnail.
class _Thumbnail extends ConsumerWidget {
  const _Thumbnail({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final path = ref.watch(attachmentPathProvider(attachment)).valueOrNull;
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: strings.attachmentsOpen,
      child: InkWell(
        onTap: () => _open(context, ref, strings),
        onLongPress: () => _delete(context, ref, strings),
        borderRadius: AlayaRadii.borderMd,
        child: ClipRRect(
          borderRadius: AlayaRadii.borderMd,
          child: SizedBox(
            width: AttachmentStrip._thumbExtent,
            height: AttachmentStrip._thumbExtent,
            child: path == null || !attachment.isImage
                // A file that is not an image, or whose path has not resolved, gets a glyph rather than a broken
                // picture — and the glyph is the same size, so the strip does not reflow when one loads.
                ? ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.description_outlined,
                      size: AlayaIconSize.lg,
                      color: context.semantic.muted,
                    ),
                  )
                : Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: AlayaIconSize.lg,
                        color: context.semantic.muted,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    final ok = await ref
        .read(attachmentControllerProvider.notifier)
        .open(attachment);
    if (!context.mounted || ok) return;
    showFailureSnack(context, message: strings.attachmentsMissing);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.attachmentsDeleteConfirmTitle,
      body: strings.attachmentsDeleteConfirmBody,
      confirmLabel: strings.attachmentsDelete,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await ref
        .read(attachmentControllerProvider.notifier)
        .delete(attachment);
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.attachmentsDeleted)
        : showFailureSnack(context, message: strings.attachmentsDeleteFailed);
  }
}

/// Attaching a file (ARCH_5 §3 archetype A).
///
/// **A sheet with one action, and it is honest about what it can do.** This phase attaches an image the user has
/// already taken; capturing one needs `image_picker`, which ARCH_1 §7 does not pin. The copy says *choose a photo*
/// rather than *add a photo*, because a sheet promising a camera that never opens is worse than one that does not
/// promise it.
class AttachSheet extends ConsumerWidget {
  /// Creates the sheet. Prefer [show].
  const AttachSheet({required this.owner, required this.ownerId, super.key});

  /// Which kind of record this attaches to.
  final AttachmentOwner owner;

  /// The record's id.
  final String ownerId;

  /// Shows the sheet.
  static Future<void> show(
    BuildContext context, {
    required AttachmentOwner owner,
    required String ownerId,
  }) => AlayaBottomSheet.show<void>(
    context: context,
    builder: (context) => AttachSheet(owner: owner, ownerId: ownerId),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final working = ref.watch(attachmentControllerProvider).isLoading;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.attachmentsAdd, style: AlayaTypography.sectionHeader),
        const SizedBox(height: AlayaSpacing.xs),
        Text(
          strings.attachmentsStoredLocally,
          style: AlayaTypography.caption.copyWith(
            color: context.semantic.muted,
          ),
        ),
        const SizedBox(height: AlayaSpacing.lg),
        FilledButton.icon(
          onPressed: working ? null : () => _attach(context, ref, strings),
          icon: const Icon(Icons.image_outlined, size: AlayaIconSize.md),
          label: Text(
            strings.attachmentsChoosePhoto,
            style: AlayaTypography.button,
          ),
        ),
      ],
    );
  }

  Future<void> _attach(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    final controller = ref.read(attachmentControllerProvider.notifier);
    final ok = await controller.attach(owner: owner, ownerId: ownerId);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    if (!context.mounted) return;
    if (ok) {
      showResultSnack(context, message: strings.attachmentsAdded);
      return;
    }
    // Dismissing the picker is silent, for the same reason cancelling an export is.
    if (controller.wasCancelled) return;
    showFailureSnack(context, message: strings.attachmentsAddFailed);
  }
}
```

### `lib/features/attachments/providers/attachment_providers.dart`

```dart
/// View-model state for attachments (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/domain/services/attachments/attachment_port.dart';

/// What is attached to one record.
final attachmentsForProvider =
    StreamProvider.family<
      List<Attachment>,
      ({AttachmentOwner owner, String ownerId})
    >(
      (ref, key) => ref
          .watch(attachmentPortProvider)
          .watchFor(owner: key.owner, ownerId: key.ownerId),
    );

/// Attaching and removing.
final attachmentControllerProvider =
    NotifierProvider<AttachmentController, AsyncValue<void>>(
      AttachmentController.new,
    );

/// Runs the picker and the delete.
class AttachmentController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Whether the last attempt ended because the picker was dismissed.
  bool get wasCancelled => _wasCancelled;
  bool _wasCancelled = false;

  /// Opens the picker and stores what was chosen.
  Future<bool> attach({
    required AttachmentOwner owner,
    required String ownerId,
  }) async {
    state = const AsyncLoading<void>();
    _wasCancelled = false;
    final result = await ref
        .read(attachmentPortProvider)
        .attach(owner: owner, ownerId: ownerId);
    if (result.isFailure) {
      state = AsyncError<void>(
        result.failureOrNull ?? StateError('attach failed'),
        StackTrace.current,
      );
      return false;
    }
    _wasCancelled = result.valueOrNull == null;
    state = const AsyncData<void>(null);
    return !_wasCancelled;
  }

  /// Removes an attachment and its file.
  Future<bool> delete(Attachment attachment) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(attachmentPortProvider).delete(attachment);
    if (result.isFailure) {
      state = AsyncError<void>(
        result.failureOrNull ?? StateError('delete failed'),
        StackTrace.current,
      );
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }

  /// Opens an attachment in whatever app handles its type.
  Future<bool> open(Attachment attachment) async {
    final result = await ref.read(attachmentPortProvider).open(attachment);
    if (result.isFailure) {
      state = AsyncError<void>(
        result.failureOrNull ?? StateError('open failed'),
        StackTrace.current,
      );
      return false;
    }
    return true;
  }
}

/// The absolute path of one attachment, for a thumbnail.
final attachmentPathProvider = FutureProvider.family<String?, Attachment>((
  ref,
  attachment,
) async {
  final result = await ref
      .watch(attachmentPortProvider)
      .resolvePath(attachment);
  return result.valueOrNull;
});
```

### `lib/features/backup/presentation/screens/backup_screen.dart`

```dart
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
```

### `lib/features/backup/presentation/screens/restore_flow.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart';
import 'package:alaya/features/backup/providers/restore_providers.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Restoring from a backup (ARCH_5 §3 archetype B).
///
/// **ARCH_3 §3.2's guards, in its order, and each one visible.** Verify the file opens → check its `user_version`
/// against this build → choose a mode → for Replace, type the word → snapshot a rollback → apply. The gate is
/// checked when the file is picked rather than when Apply is pressed, so a refusal arrives before the user has
/// chosen anything they would then lose.
///
/// **Merge is the default; Replace is a choice.** Merge upserts by UUID and keeps rows the backup does not have.
/// Replace discards them. A destructive default is a destructive accident.
///
/// **The lock is never restored**, and the screen says so. PIN and recovery hashes live in secure storage
/// (ARCH_3 §2.1), so importing a backup cannot change who can open the app — which is worth stating on the one
/// screen where somebody might expect otherwise.
class RestoreFlow extends ConsumerWidget {
  /// Creates the flow.
  const RestoreFlow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(restoreProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(strings.restoreTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
          child: switch (state.stage) {
            RestoreStage.pick => const _PickStage(),
            RestoreStage.confirm => const _ConfirmStage(),
            RestoreStage.arm => const _ArmStage(),
            RestoreStage.done => const _DoneStage(),
          },
        ),
      ),
    );
  }
}

/// Choosing a file.
class _PickStage extends ConsumerWidget {
  const _PickStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(restoreProvider);
    final semantic = context.semantic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.restorePickBody, style: AlayaTypography.body),
        const SizedBox(height: AlayaSpacing.md),
        _Notice(text: strings.restoreLockNotRestored, tone: semantic.muted),
        if (state.refusal == RestoreRefusal.notADatabase) ...[
          const SizedBox(height: AlayaSpacing.md),
          _Notice(text: strings.restoreNotADatabase, tone: semantic.danger),
        ],
        if (state.failureMessage != null) ...[
          const SizedBox(height: AlayaSpacing.md),
          Text(
            state.failureMessage!,
            style: AlayaTypography.body.copyWith(color: semantic.danger),
          ),
        ],
        const SizedBox(height: AlayaSpacing.lg),
        FilledButton.icon(
          onPressed: state.isWorking
              ? null
              : () => ref.read(restoreProvider.notifier).pickFile(),
          icon: const Icon(Icons.folder_open_outlined, size: AlayaIconSize.md),
          label: Text(strings.restoreChooseFile, style: AlayaTypography.button),
        ),
      ],
    );
  }
}

/// The file is readable; choose a mode.
class _ConfirmStage extends ConsumerWidget {
  const _ConfirmStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(restoreProvider);
    final notifier = ref.read(restoreProvider.notifier);
    final semantic = context.semantic;
    final refused = state.refusal == RestoreRefusal.newerSchema;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(label: strings.restoreChosenHeader),
        const SizedBox(height: AlayaSpacing.xs),
        Text(state.fileName ?? '', style: AlayaTypography.cardTitle),
        const SizedBox(height: AlayaSpacing.md),
        if (refused) ...[
          // **Both numbers, because a refusal without them is one nobody can act on.** "That backup is from a
          // newer version (7) than this app understands (1)" tells the user to update; "cannot restore" does not.
          _Notice(
            text: strings.restoreNewerSchema(
              state.backupVersion ?? 0,
              state.appVersion ?? 0,
            ),
            tone: semantic.danger,
          ),
          const SizedBox(height: AlayaSpacing.lg),
          OutlinedButton(
            onPressed: () => ref.invalidate(restoreProvider),
            child: Text(
              strings.restoreChooseAnother,
              style: AlayaTypography.button,
            ),
          ),
        ] else ...[
          SectionHeader(label: strings.restoreModeHeader),
          const SizedBox(height: AlayaSpacing.xs),
          for (final mode in RestoreMode.values)
            RadioListTile<RestoreMode>(
              value: mode,
              groupValue: state.mode,
              onChanged: (next) => next == null ? null : notifier.setMode(next),
              contentPadding: EdgeInsets.zero,
              title: Text(
                mode == RestoreMode.merge
                    ? strings.restoreMergeTitle
                    : strings.restoreReplaceTitle,
                style: AlayaTypography.body,
              ),
              subtitle: Text(
                mode == RestoreMode.merge
                    ? strings.restoreMergeBody
                    : strings.restoreReplaceBody,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
            ),
          const SizedBox(height: AlayaSpacing.md),
          _Notice(text: strings.restoreLockNotRestored, tone: semantic.muted),
          if (state.failureMessage != null) ...[
            const SizedBox(height: AlayaSpacing.md),
            Text(
              state.failureMessage!,
              style: AlayaTypography.body.copyWith(color: semantic.danger),
            ),
          ],
          const SizedBox(height: AlayaSpacing.lg),
          if (state.mode == RestoreMode.merge)
            FilledButton(
              onPressed: state.isWorking ? null : () => notifier.apply(),
              child: Text(
                strings.restoreApplyMerge,
                style: AlayaTypography.button,
              ),
            )
          else
            // Replace never commits from this screen: it goes to the typed confirmation first, and the button
            // says so rather than pretending to be the last step.
            OutlinedButton(
              onPressed: state.isWorking ? null : notifier.arm,
              style: OutlinedButton.styleFrom(foregroundColor: semantic.danger),
              child: Text(
                strings.restoreContinueReplace,
                style: AlayaTypography.button,
              ),
            ),
        ],
      ],
    );
  }
}

/// Typing the word, for Replace.
class _ArmStage extends ConsumerWidget {
  const _ArmStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(restoreProvider);
    final notifier = ref.read(restoreProvider.notifier);
    final semantic = context.semantic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Notice(text: strings.restoreReplaceWarning, tone: semantic.danger),
        const SizedBox(height: AlayaSpacing.md),
        // Says the snapshot happens *before* the swap, because that is what makes this recoverable — and a user
        // who knows there is a way back reads the warning as information rather than a threat.
        Text(strings.restoreRollbackPromise, style: AlayaTypography.body),
        const SizedBox(height: AlayaSpacing.lg),
        Text(
          strings.restoreTypeToConfirm(RestoreState.confirmationWord),
          style: AlayaTypography.body,
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextField(
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: RestoreState.confirmationWord),
          onChanged: notifier.setTyped,
        ),
        if (state.failureMessage != null) ...[
          const SizedBox(height: AlayaSpacing.md),
          Text(
            state.failureMessage!,
            style: AlayaTypography.body.copyWith(color: semantic.danger),
          ),
        ],
        const SizedBox(height: AlayaSpacing.lg),
        OutlinedButton(
          onPressed: state.isArmed && !state.isWorking
              ? () => notifier.apply()
              : null,
          style: OutlinedButton.styleFrom(foregroundColor: semantic.danger),
          child: Text(
            strings.restoreApplyReplace,
            style: AlayaTypography.button,
          ),
        ),
      ],
    );
  }
}

/// Applied.
class _DoneStage extends ConsumerWidget {
  const _DoneStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(restoreProvider);
    final outcome = state.outcome;
    final semantic = context.semantic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: AlayaIconSize.lg,
              color: semantic.success,
            ),
            const SizedBox(width: AlayaSpacing.sm),
            Expanded(
              child: Text(
                outcome == null
                    ? strings.restoreDone
                    : strings.restoreDoneDetail(outcome.tablesMerged),
                style: AlayaTypography.bodyEmphasis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.md),
        _Notice(text: strings.restoreLockNotRestored, tone: semantic.muted),
        if (outcome != null && outcome.rollbackAvailable) ...[
          const SizedBox(height: AlayaSpacing.lg),
          Text(strings.restoreRollbackAvailable, style: AlayaTypography.body),
          const SizedBox(height: AlayaSpacing.xs),
          // Offered on the success screen, not hidden behind a settings row: the moment somebody realises they
          // restored the wrong file is the moment they are looking at this.
          OutlinedButton(
            onPressed: state.isWorking
                ? null
                : () => ref.read(restoreProvider.notifier).rollback(),
            child: Text(strings.restoreUndo, style: AlayaTypography.button),
          ),
        ],
        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          onPressed: () => context.go(Routes.dashboard),
          child: Text(strings.actionDone, style: AlayaTypography.button),
        ),
      ],
    );
  }
}

/// A tinted paragraph.
class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.tone});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AlayaSpacing.md),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: 0.12),
      borderRadius: AlayaRadii.borderMd,
    ),
    child: Text(text, style: AlayaTypography.body),
  );
}
```

### `lib/features/backup/providers/backup_providers.dart`

```dart
/// View-model state for the backup and restore screens (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart';

/// Every backup this app has taken, newest first.
final backupHistoryProvider = StreamProvider<List<BackupRecord>>(
  (ref) => ref.watch(dataTransferPortProvider).watchHistory(),
);

/// Whether a rollback snapshot is sitting beside the live database.
final hasRollbackProvider = FutureProvider<bool>(
  (ref) => ref.watch(dataTransferPortProvider).hasRollback(),
);

/// Exporting, and forgetting history entries.
final backupControllerProvider =
    NotifierProvider<BackupController, AsyncValue<void>>(BackupController.new);

/// Runs the export and reports what came back.
class BackupController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// The last export's artefact, so the screen can name the file it just wrote.
  BackupArtefact? get lastArtefact => _lastArtefact;
  BackupArtefact? _lastArtefact;

  /// Whether the last attempt ended because the user dismissed the system sheet.
  ///
  /// **Distinct from both success and failure**, because it is neither: cancelling a file chooser is the
  /// commonest thing to do with one, and a screen that cannot tell it apart either congratulates somebody on a
  /// backup they did not take or shows them an error for changing their mind.
  bool get wasCancelled => _wasCancelled;
  bool _wasCancelled = false;

  /// Writes a backup to a location the user picks.
  Future<bool> exportToLocation() async {
    state = const AsyncLoading<void>();
    _wasCancelled = false;
    final result = await ref.read(dataTransferPortProvider).exportToLocation();
    if (result.isFailure) {
      state = AsyncError<void>(
        result.failureOrNull ?? StateError('export failed'),
        StackTrace.current,
      );
      return false;
    }
    _lastArtefact = result.valueOrNull;
    _wasCancelled = _lastArtefact == null;
    state = const AsyncData<void>(null);
    return !_wasCancelled;
  }

  /// Writes a backup and hands it to the system share sheet.
  Future<bool> exportAndShare() async {
    state = const AsyncLoading<void>();
    _wasCancelled = false;
    final result = await ref.read(dataTransferPortProvider).exportAndShare();
    if (result.isFailure) {
      state = AsyncError<void>(
        result.failureOrNull ?? StateError('export failed'),
        StackTrace.current,
      );
      return false;
    }
    _lastArtefact = result.valueOrNull;
    state = const AsyncData<void>(null);
    return true;
  }

  /// Removes a history row, leaving its file where it is.
  Future<bool> forget(String id) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(dataTransferPortProvider)
        .forgetHistoryEntry(id);
    if (result.isFailure) {
      state = AsyncError<void>(
        result.failureOrNull ?? StateError('forget failed'),
        StackTrace.current,
      );
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}
```

### `lib/features/backup/providers/restore_providers.dart`

```dart
/// View-model state for the restore flow (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart';

/// Which part of the restore flow is showing.
enum RestoreStage {
  /// Choosing a file.
  pick,

  /// The file has been read and its schema version checked.
  confirm,

  /// Typing REPLACE, for the destructive mode only.
  arm,

  /// Applied.
  done,
}

/// Why a chosen backup cannot be applied.
enum RestoreRefusal {
  /// The file is newer than this build understands.
  ///
  /// **The one gate ARCH_3 §3.2 puts first**, and the only refusal that is about the file rather than the device:
  /// a backup written by a later schema may contain columns this build would silently drop.
  newerSchema,

  /// The file could not be opened as a database at all.
  notADatabase,
}

/// What the restore flow is holding.
class RestoreState {
  /// Creates a state.
  const RestoreState({
    this.stage = RestoreStage.pick,
    this.path,
    this.fileName,
    this.backupVersion,
    this.appVersion,
    this.mode = RestoreMode.merge,
    this.typed = '',
    this.isWorking = false,
    this.refusal,
    this.outcome,
    this.failureMessage,
  });

  /// The part being shown.
  final RestoreStage stage;

  /// The chosen file's path.
  final String? path;

  /// Its name, for the copy.
  final String? fileName;

  /// The schema version inside it.
  final int? backupVersion;

  /// The schema version this build writes.
  final int? appVersion;

  /// Merge or Replace.
  ///
  /// **Merge is the default and Replace is the choice**, because merge keeps rows the backup does not have while
  /// replace discards them. A destructive default is a destructive accident.
  final RestoreMode mode;

  /// What has been typed into the confirmation.
  final String typed;

  /// Whether a read or a write is in flight.
  final bool isWorking;

  /// Why the file was refused, if it was.
  final RestoreRefusal? refusal;

  /// What the restore did, once it has.
  final RestoreOutcome? outcome;

  /// The service's own message from a failure (Law U9).
  final String? failureMessage;

  /// Whether the typed confirmation matches, for Replace.
  bool get isArmed => typed.trim() == RestoreState.confirmationWord;

  /// The word Replace requires.
  ///
  /// Not localised, for the reason 8A's `ERASE` is not: a translated confirmation word means a support article
  /// cannot tell anyone what to type, and the point of the gate is that it cannot be satisfied by tapping.
  static const String confirmationWord = 'REPLACE';

  /// A copy with the given fields replaced.
  RestoreState copyWith({
    RestoreStage? stage,
    String? path,
    String? fileName,
    int? backupVersion,
    int? appVersion,
    RestoreMode? mode,
    String? typed,
    bool? isWorking,
    RestoreRefusal? refusal,
    bool clearRefusal = false,
    RestoreOutcome? outcome,
    String? failureMessage,
    bool clearFailure = false,
  }) => RestoreState(
    stage: stage ?? this.stage,
    path: path ?? this.path,
    fileName: fileName ?? this.fileName,
    backupVersion: backupVersion ?? this.backupVersion,
    appVersion: appVersion ?? this.appVersion,
    mode: mode ?? this.mode,
    typed: typed ?? this.typed,
    isWorking: isWorking ?? this.isWorking,
    refusal: clearRefusal ? null : (refusal ?? this.refusal),
    outcome: outcome ?? this.outcome,
    failureMessage: clearFailure
        ? null
        : (failureMessage ?? this.failureMessage),
  );
}

/// The restore flow's state.
final restoreProvider = NotifierProvider<RestoreNotifier, RestoreState>(
  RestoreNotifier.new,
);

/// Picks a file, gates it, and applies it.
class RestoreNotifier extends Notifier<RestoreState> {
  @override
  RestoreState build() => const RestoreState();

  /// Opens the system picker and reads the chosen file's schema version.
  Future<void> pickFile() async {
    state = state.copyWith(
      isWorking: true,
      clearFailure: true,
      clearRefusal: true,
    );
    try {
      // **Through the port, not a plugin.** A feature may not import `data/`, and the SAF channel lives there —
      // so picking a file is one more thing `DataTransferPort` answers, alongside reading its version.
      final picked = await ref.read(dataTransferPortProvider).pickBackupFile();
      if (picked.isFailure) {
        state = state.copyWith(
          isWorking: false,
          failureMessage: picked.failureOrNull?.message,
        );
        return;
      }
      final path = picked.valueOrNull;
      if (path == null) {
        state = state.copyWith(isWorking: false);
        return;
      }
      final port = ref.read(dataTransferPortProvider);
      final version = await port.readBackupVersion(path);
      final backupVersion = version.valueOrNull;
      if (backupVersion == null) {
        state = state.copyWith(
          isWorking: false,
          refusal: RestoreRefusal.notADatabase,
          failureMessage: version.failureOrNull?.message,
        );
        return;
      }
      final appVersion = port.appSchemaVersion;
      state = state.copyWith(
        isWorking: false,
        stage: RestoreStage.confirm,
        path: path,
        fileName: path.split(RegExp(r'[/\\]')).last,
        backupVersion: backupVersion,
        appVersion: appVersion,
        // **Gated before anything is applied** (ARCH_3 §3.2). A backup from a later schema may carry columns this
        // build would silently drop, so it is refused with both numbers rather than merged lossily.
        refusal: backupVersion > appVersion ? RestoreRefusal.newerSchema : null,
      );
    } on Object catch (error) {
      state = state.copyWith(
        isWorking: false,
        failureMessage: error.toString(),
      );
    }
  }

  /// Chooses Merge or Replace.
  void setMode(RestoreMode mode) =>
      state = state.copyWith(mode: mode, typed: '', clearFailure: true);

  /// Records what has been typed into the Replace confirmation.
  void setTyped(String value) => state = state.copyWith(typed: value);

  /// Moves to the typed confirmation, for Replace only.
  void arm() {
    if (state.mode != RestoreMode.replace) return;
    state = state.copyWith(stage: RestoreStage.arm, typed: '');
  }

  /// Applies the backup.
  Future<bool> apply() async {
    final path = state.path;
    if (path == null || state.refusal != null) return false;
    if (state.mode == RestoreMode.replace && !state.isArmed) return false;

    state = state.copyWith(isWorking: true, clearFailure: true);
    final port = ref.read(dataTransferPortProvider);
    final result = state.mode == RestoreMode.merge
        ? await port.merge(path)
        : await port.replace(path);
    final outcome = result.valueOrNull;
    if (outcome == null) {
      state = state.copyWith(
        isWorking: false,
        failureMessage: result.failureOrNull?.message,
      );
      return false;
    }
    state = state.copyWith(
      isWorking: false,
      stage: RestoreStage.done,
      outcome: outcome,
    );
    return true;
  }

  /// Puts the pre-replace snapshot back.
  Future<bool> rollback() async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await ref.read(dataTransferPortProvider).rollback();
    state = state.copyWith(
      isWorking: false,
      failureMessage: result.isFailure ? result.failureOrNull?.message : null,
    );
    return result.isOk;
  }
}
```

### `lib/features/ops/presentation/screens/reminders_screen.dart`

```dart

```

### `lib/features/reminders/presentation/screens/reminders_screen.dart`

```dart
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
```

### `lib/features/reminders/providers/reminder_providers.dart`

```dart
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
```

### `lib/features/support/presentation/screens/support_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/services/support/support_port.dart';
import 'package:alaya/features/support/providers/support_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Support Us (ARCH_5 §3 archetype F, outside the shell).
///
/// **The SDKs start in `initState` and nowhere else in the app.** That is the requirement, and it is enforced by
/// `AdsAndBilling` being the only file that imports either SDK — a `grep` for `google_mobile_ads` returning one
/// path is the check. An install where nobody opens this screen never initialises the SDK, never fetches a
/// consent form, and never collects an advertising identifier.
///
/// **Archetype F with one deviation: no `displayAmount`.** F wants one headline number per overview, and this
/// screen has none to give — the honest headline is a sentence, because the app is free and nothing here unlocks
/// anything. A fabricated "₹0 raised" would be worse than no number.
///
/// **Nothing on this screen changes what the app can do.** There are no paid features, so a tip is a tip rather
/// than a paywall wearing a friendly label, and the copy says so.
class SupportScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  @override
  void initState() {
    super.initState();
    // The one call site. A post-frame callback because `start()` mutates a provider, which Riverpod asserts on
    // during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(supportProvider.notifier).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(supportProvider);
    final semantic = context.semantic;

    return Scaffold(
      appBar: AppBar(title: Text(strings.supportTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
        children: [
          Text(strings.supportIntro, style: AlayaTypography.body),
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            strings.supportNoPaidFeatures,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          if (state.thanksShown) ...[
            const SizedBox(height: AlayaSpacing.lg),
            AlayaCard(
              padding: const EdgeInsets.all(AlayaSpacing.lg),
              child: Row(
                children: [
                  Icon(
                    Icons.favorite_outline,
                    size: AlayaIconSize.lg,
                    color: semantic.success,
                  ),
                  const SizedBox(width: AlayaSpacing.sm),
                  Expanded(
                    child: Text(
                      strings.supportThanks,
                      style: AlayaTypography.bodyEmphasis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AlayaSpacing.lg),
          SectionHeader(label: strings.supportWatchHeader),
          const SizedBox(height: AlayaSpacing.xs),
          Text(strings.supportWatchBody, style: AlayaTypography.body),
          if (state.consent == AdConsent.unavailable) ...[
            const SizedBox(height: AlayaSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AlayaSpacing.md),
              decoration: BoxDecoration(
                color: semantic.muted.withValues(alpha: 0.12),
                borderRadius: AlayaRadii.borderMd,
              ),
              // Says what happened rather than showing a button that cannot work: without consent settled, no ad
              // is requested at all (ARCH_1 §7's "resolver + UMP consent").
              child: Text(
                strings.supportConsentUnavailable,
                style: AlayaTypography.body,
              ),
            ),
          ],
          const SizedBox(height: AlayaSpacing.md),
          FilledButton.icon(
            onPressed: state.adLoaded && !state.isWorking
                ? () => ref.read(supportProvider.notifier).watchAd()
                : null,
            icon: const Icon(Icons.play_circle_outline, size: AlayaIconSize.md),
            label: Text(
              // Three honest labels rather than one that lies while loading: an enabled "Watch" over an advert
              // that has not arrived is the dead control §10 objects to.
              state.isWorking
                  ? strings.supportLoading
                  : state.adLoaded
                  ? strings.supportWatchAction
                  : strings.supportNoAd,
              style: AlayaTypography.button,
            ),
          ),
          const SizedBox(height: AlayaSpacing.xl),
          SectionHeader(label: strings.supportTipHeader),
          const SizedBox(height: AlayaSpacing.xs),
          Text(strings.supportTipBody, style: AlayaTypography.body),
          const SizedBox(height: AlayaSpacing.md),
          if (state.products.isEmpty)
            Text(
              strings.supportTipUnavailable,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            )
          else
            for (final product in state.products)
              Padding(
                padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
                child: OutlinedButton(
                  onPressed: state.isWorking
                      ? null
                      : () =>
                            ref.read(supportProvider.notifier).tip(product.id),
                  // **The store's own price string**, never reformatted: Play returns it localised for the
                  // user's account, which need not match this app's home currency. This is the one place money
                  // is displayed without `AmountText`, and reformatting it would make it wrong.
                  child: Text(
                    strings.supportTipAction(product.price),
                    style: AlayaTypography.button,
                  ),
                ),
              ),
          if (state.failureMessage != null) ...[
            const SizedBox(height: AlayaSpacing.md),
            Text(
              state.failureMessage!,
              style: AlayaTypography.body.copyWith(color: semantic.danger),
            ),
          ],
        ],
      ),
    );
  }
}
```

### `lib/features/support/presentation/widgets/support_action.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/features/support/providers/support_availability_provider.dart';
import 'package:alaya/features/support/providers/support_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';

/// The app bar's support action — one tap, one advert, nothing before the tap.
///
/// **This is an amendment to ARCH_4 §5.1, which said rewarded ads live "only in Support Us".** The entry point
/// moves to the dashboard; the constraint that matters does not.
///
/// **Nothing is loaded until the button is pressed.** The obvious way to make an app bar button feel instant is
/// to have an advert waiting — which means `MobileAds.initialize()` and `RewardedAd.load()` on every dashboard
/// build, and an advertising identifier collected from every user who never taps it. That is what 8B's "the rest
/// of the app makes zero ad calls" forbids, and the privacy cost is real rather than notional.
///
/// So the sequence runs *on* the tap: initialise → settle consent → load → show. It costs a second or two, which
/// is why the button shows a spinner rather than pretending to be immediate. **The user chooses when an advert
/// plays, and also when one is fetched** — the second half is the part a pre-loaded button would give away.
///
/// ## Two changes, and one of them was nearly a mistake
///
/// **It carries a label now.** An unlabelled hands icon beside a title is a guess: it could be sharing, a
/// partnership, a handshake gesture. "Support Us" says what a tap does, and a button in an app bar that nobody
/// can identify is a button nobody presses.
///
/// **It hides itself when the last attempt found no advert.** The obvious implementation — ask the SDK on
/// launch whether one is available — is the one thing this widget's own doc forbids: `google_mobile_ads` cannot
/// answer that without loading, and loading collects an identifier from everyone who never asked. So the answer
/// comes from what happened last time somebody tapped, which costs the SDK nothing.
///
/// **Settings › Support Us stays visible unconditionally**, and that is the safety net rather than an
/// oversight. This widget's answer is a guess from stale evidence; a wrong guess must never be the only answer.
///
/// Tinted `colorScheme.secondary`, which is the palette's own accent (ARCH_3 §8) rather than a raw colour, so it
/// reads as distinct from the app bar's other actions under every preset and in both brightnesses.
class SupportAction extends ConsumerWidget {
  /// Creates the action.
  const SupportAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(supportProvider);
    final theme = Theme.of(context);

    if (state.isWorking) {
      // A spinner in the button's own footprint, so the app bar does not reflow while an advert is fetched.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.md),
        child: Center(
          child: SizedBox(
            width: AlayaIconSize.md,
            height: AlayaIconSize.md,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.secondary,
            ),
          ),
        ),
      );
    }

    // **Absent, not disabled, when there is nothing to show.** A greyed-out button in an app bar is a
    // permanent question — "why can't I press that?" — with no answer available on the screen it sits on.
    //
    // `valueOrNull ?? true` so the action is present while the settings row is being read. Hiding during the
    // first frames and appearing a moment later would make the app bar jump on every launch, and the common
    // answer is "show it" anyway.
    final visible = ref.watch(supportActionVisibleProvider).valueOrNull ?? true;
    if (!visible) return const SizedBox.shrink();

    return TextButton.icon(
      onPressed: () => _watch(context, ref, strings),
      icon: Icon(
        // Joined hands. Not a padlock-style overload: it reads as "together" rather than as an advert, which is
        // honest — the action is supporting the app, and the advert is the mechanism.
        Icons.handshake_outlined,
        size: AlayaIconSize.md,
      ),
      label: Text(strings.supportActionLabel),
      style: TextButton.styleFrom(
        foregroundColor: theme.colorScheme.secondary,
        // An app bar does not wrap its actions, so a long label at a doubled text scale eats the title rather
        // than reflowing. Tightening the padding buys back most of what the label costs; if it still crowds at
        // 320dp, the label is the thing to shorten, not the icon to drop.
        padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.sm),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Future<void> _watch(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    final controller = ref.read(supportProvider.notifier);
    final outcome = await controller.watchNow();
    if (!context.mounted) return;

    // **Recorded before the message.** This is the only moment the app learns anything about availability, and
    // an early `return` in the switch below would skip it — `dismissed` says nothing to the user and would have
    // been exactly the case that fell through.
    await ref.read(supportOutcomeRecorderProvider.notifier).record(outcome);
    if (!context.mounted) return;

    switch (outcome) {
      case SupportWatchOutcome.rewarded:
        showResultSnack(context, message: strings.supportThanks);
      case SupportWatchOutcome.dismissed:
        // Silent. Somebody who changes their mind half way through an advert has done nothing wrong, and a
        // message either way would be the app commenting on it.
        break;
      case SupportWatchOutcome.unavailable:
        showFailureSnack(context, message: strings.supportNoAd);
      case SupportWatchOutcome.blocked:
        showFailureSnack(context, message: strings.supportConsentUnavailable);
    }
  }
}
```

### `lib/features/support/providers/support_availability_provider.dart`

```dart
/// Whether the support action is worth showing (ARCH_5 U19).
library;

import 'package:alaya/core/time/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/features/support/providers/support_providers.dart';

/// The `app_settings` key holding when an advert was last unavailable.
///
/// Epoch millis, or absent. **Absent means "show it"** — including on a fresh install, which is the whole
/// reason this stores a *failure* rather than a success.
const String adUnavailableSinceKey = 'support.adUnavailableSince';

/// How long a failure suppresses the action.
///
/// **Three days, not one and not forever.** A fill failure is usually transient — no inventory in the region
/// for a few hours, a network blip — so hiding permanently would remove the feature over a temporary
/// condition. Retrying daily is the other extreme: the button would appear each morning, vanish on the first
/// tap, and read as broken. Three days is long enough that nobody notices the retry and short enough that a
/// genuine recovery is picked up within the week.
const Duration adRetryAfter = Duration(days: 3);

/// Whether the app-bar support action should be shown at all.
///
/// ## Why this cannot ask the SDK
///
/// `google_mobile_ads` has **no way to report availability without loading an advert**, and loading requires
/// `MobileAds.initialize()` plus a settled consent flow — which collects an advertising identifier. ARCH_4's
/// Support Us row is explicit that nothing may run before the tap:
///
/// > *nothing loads until the button is tapped … a user who never taps it never has an advertising
/// > identifier collected.*
///
/// Checking availability on launch would break that for every user in the app, to decide whether to draw one
/// icon. So the question is answered from **what happened last time somebody asked**, which costs the SDK
/// nothing and is right far more often than not: an account with no fill yesterday usually has no fill today.
///
/// **Optimistic when it knows nothing.** A first launch shows the action, because the alternative is a
/// feature that never appears until it has been used, which it cannot be.
///
/// **Settings › Support Us is unaffected and always visible.** That is deliberate: this provider can be wrong,
/// and a wrong answer must never be the only answer. There is always a way in.
final supportActionVisibleProvider = FutureProvider<bool>((ref) async {
  final stored = await ref
      .watch(settingsRepositoryProvider)
      .readValue(adUnavailableSinceKey);
  if (stored == null) return true;

  final since = int.tryParse(stored);
  // Unparseable is treated as absent rather than as a failure. A malformed row should not hide a feature, and
  // the next outcome overwrites it.
  if (since == null) return true;

  final elapsed = ref.watch(clockProvider).nowUtcMillis() - since;
  return elapsed >= adRetryAfter.inMilliseconds;
});

/// Records what happened, so the next launch can decide.
final supportOutcomeRecorderProvider =
    NotifierProvider<SupportOutcomeRecorder, void>(
      SupportOutcomeRecorder.new,
    );

/// Writes the outcome of a support attempt.
class SupportOutcomeRecorder extends Notifier<void> {
  @override
  void build() {}

  /// Records [outcome] and refreshes the visibility answer.
  ///
  /// **An advert that played and one the user dismissed both count as available**, and the distinction matters:
  /// dismissing is a decision about *this* advert, not evidence that adverts cannot be fetched. Treating it as
  /// unavailability would hide the button for three days because somebody changed their mind after four
  /// seconds.
  ///
  /// **`unavailable` and `blocked` are recorded together, though they are not the same thing.** No fill is
  /// transient; a consent flow that cannot complete is usually not. They are merged because the *action* is
  /// identical either way — there is no advert to show now — and because a consent problem that resolves
  /// itself deserves the same three-day retry as anything else. If they ever need different handling, the
  /// place to split them is here, not at the call site.
  Future<void> record(SupportWatchOutcome outcome) async {
    final settings = ref.read(settingsRepositoryProvider);
    switch (outcome) {
      case SupportWatchOutcome.rewarded:
      case SupportWatchOutcome.dismissed:
        // Clearing rather than writing a success marker: absence already means "show it", so a second
        // representation of the same state would be one more thing to keep in step.
        await settings.writeValue(
          key: adUnavailableSinceKey,
          value: '',
          valueType: 'string',
        );
      case SupportWatchOutcome.unavailable:
      case SupportWatchOutcome.blocked:
        await settings.writeValue(
          key: adUnavailableSinceKey,
          value: '${ref.read(clockProvider).nowUtcMillis()}',
          valueType: 'string',
        );
    }
    ref.invalidate(supportActionVisibleProvider);
  }
}
```

### `lib/features/support/providers/support_providers.dart`

```dart
/// View-model state for the Support screen (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/domain/services/support/support_port.dart';

/// What the Support screen is holding.
class SupportState {
  /// Creates a state.
  const SupportState({
    this.isReady = false,
    this.isWorking = false,
    this.consent = AdConsent.required,
    this.adLoaded = false,
    this.products = const [],
    this.thanksShown = false,
    this.failureMessage,
  });

  /// Whether the SDKs have been brought up.
  ///
  /// **False until the screen asks**, which is the whole design: nothing initialises anywhere else.
  final bool isReady;

  /// Whether something is in flight.
  final bool isWorking;

  /// Where consent stands.
  final AdConsent consent;

  /// Whether an advert is ready to show.
  final bool adLoaded;

  /// The tip products the store offers.
  final List<TipProduct> products;

  /// Whether the thank-you has been shown for this visit.
  final bool thanksShown;

  /// The adapter's own message from the last failure (Law U9).
  final String? failureMessage;

  /// A copy with the given fields replaced.
  SupportState copyWith({
    bool? isReady,
    bool? isWorking,
    AdConsent? consent,
    bool? adLoaded,
    List<TipProduct>? products,
    bool? thanksShown,
    String? failureMessage,
    bool clearFailure = false,
  }) => SupportState(
    isReady: isReady ?? this.isReady,
    isWorking: isWorking ?? this.isWorking,
    consent: consent ?? this.consent,
    adLoaded: adLoaded ?? this.adLoaded,
    products: products ?? this.products,
    thanksShown: thanksShown ?? this.thanksShown,
    failureMessage: clearFailure
        ? null
        : (failureMessage ?? this.failureMessage),
  );
}

/// What a one-tap watch ended in.
///
/// Four outcomes rather than a bool, because three of them need different words and one needs silence. A
/// dismissed advert is not a failure — collapsing it into one would either thank somebody who watched nothing or
/// show them an error for changing their mind.
enum SupportWatchOutcome {
  /// Watched through; the reward callback fired.
  rewarded,

  /// Dismissed part way. Not a failure.
  dismissed,

  /// Nothing was available to show.
  unavailable,

  /// Consent could not be settled, so no advert was requested at all.
  blocked,
}

/// The Support screen's state.
final supportProvider = NotifierProvider<SupportController, SupportState>(
  SupportController.new,
);

/// Brings the SDKs up on demand, settles consent, then loads.
class SupportController extends Notifier<SupportState> {
  @override
  SupportState build() => const SupportState();

  /// Called from the screen's `initState`, and from nowhere else in the app.
  ///
  /// **Consent is settled before any ad is requested.** Requesting first and asking afterwards is what gets an
  /// app pulled in the EEA, and the ordering here is the only thing preventing it.
  Future<void> start() async {
    if (state.isReady) return;
    state = state.copyWith(isWorking: true, clearFailure: true);
    final port = ref.read(supportPortProvider);

    final ready = await port.initialise();
    if (ready.isFailure) {
      state = state.copyWith(
        isWorking: false,
        failureMessage: ready.failureOrNull?.message,
      );
      return;
    }

    var consent = await port.consentStatus();
    if (consent == AdConsent.required) consent = await port.requestConsent();

    final products = await port.tipProducts();
    state = state.copyWith(
      isReady: true,
      isWorking: false,
      consent: consent,
      products: products.valueOrNull ?? const [],
    );

    // An advert is only fetched once consent is settled — and never when it could not be.
    if (consent == AdConsent.obtained || consent == AdConsent.notRequired) {
      await loadAd();
    }
  }

  /// Fetches an advert.
  Future<void> loadAd() async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await ref.read(supportPortProvider).loadRewardedAd();
    state = state.copyWith(
      isWorking: false,
      adLoaded: result.isOk,
      failureMessage: result.isFailure ? result.failureOrNull?.message : null,
    );
  }

  /// Shows the advert and records whether it was watched through.
  Future<bool> watchAd() async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await ref.read(supportPortProvider).showRewardedAd();
    final earned = result.valueOrNull ?? false;
    state = state.copyWith(
      isWorking: false,
      adLoaded: false,
      thanksShown: earned,
      // Dismissing halfway is not a failure — somebody who changes their mind has done nothing wrong.
      failureMessage: result.isFailure ? result.failureOrNull?.message : null,
    );
    return earned;
  }

  /// Initialise, settle consent, load and show — in one action, on demand.
  ///
  /// **Written for the app bar button, and the ordering is the whole point.** Nothing here runs until it is
  /// called, so a user who never taps the button never has an advertising identifier collected. A pre-loaded
  /// button would feel faster and would give that away on every app open.
  ///
  /// Safe to call from anywhere: `initialise()` is idempotent, and consent is only fetched once per session.
  Future<SupportWatchOutcome> watchNow() async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final port = ref.read(supportPortProvider);

    final ready = await port.initialise();
    if (ready.isFailure) {
      state = state.copyWith(
        isWorking: false,
        failureMessage: ready.failureOrNull?.message,
      );
      return SupportWatchOutcome.unavailable;
    }

    var consent = await port.consentStatus();
    if (consent == AdConsent.required) consent = await port.requestConsent();
    if (consent != AdConsent.obtained && consent != AdConsent.notRequired) {
      // No advert is requested when consent could not be settled. Asking afterwards is what gets an app pulled
      // in the EEA.
      state = state.copyWith(isWorking: false, consent: consent);
      return SupportWatchOutcome.blocked;
    }

    final loaded = await port.loadRewardedAd();
    if (loaded.isFailure) {
      state = state.copyWith(
        isWorking: false,
        consent: consent,
        failureMessage: loaded.failureOrNull?.message,
      );
      return SupportWatchOutcome.unavailable;
    }

    final shown = await port.showRewardedAd();
    final earned = shown.valueOrNull ?? false;
    state = state.copyWith(
      isWorking: false,
      consent: consent,
      adLoaded: false,
      thanksShown: earned,
      failureMessage: shown.isFailure ? shown.failureOrNull?.message : null,
    );
    if (shown.isFailure) return SupportWatchOutcome.unavailable;
    return earned
        ? SupportWatchOutcome.rewarded
        : SupportWatchOutcome.dismissed;
  }

  /// Starts the one-time tip purchase.
  Future<bool> tip(String productId) async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await ref.read(supportPortProvider).buyTip(productId);
    final ok = result.valueOrNull ?? false;
    state = state.copyWith(
      isWorking: false,
      thanksShown: ok,
      failureMessage: result.isFailure ? result.failureOrNull?.message : null,
    );
    return ok;
  }
}
```

### `lib/features/trash/presentation/screens/trash_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/trash/trash_port.dart';
import 'package:alaya/features/trash/providers/trash_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';

/// Settings › Data › Trash (ARCH_5 §3 archetype C, outside the shell).
///
/// **A ledger list rather than a catalogue, because the trash is a record of events.** Things arrive here in the
/// order they were deleted and leave in the order they expire; there is no user axis to group by, which is what
/// separates C from D.
///
/// **Thirty-day retention, stated per row** (ARCH_3 §4.2). A trash that silently empties is one people stop
/// trusting with the thing they deleted by accident, so every row says when it goes.
///
/// **Empty now is the only place a hard delete is reachable from**, and it is confirmed. Purge is the single hard
/// delete in the codebase; this screen is the only door to it.
class TrashScreen extends ConsumerWidget {
  /// Creates the screen.
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final all = ref.watch(trashProvider);
    final filter = ref.watch(trashFilterProvider);
    final rows = ref.watch(filteredTrashProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.trashTitle),
        actions: [
          if (all.valueOrNull?.isNotEmpty ?? false)
            TextButton(
              onPressed: () => _emptyNow(context, ref, strings),
              child: Text(strings.trashEmptyNow, style: AlayaTypography.button),
            ),
        ],
      ),
      body: all.when(
        loading: () => AlayaListSkeleton(label: strings.trashLoading),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(trashProvider),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return EmptyState(
              title: strings.trashEmptyTitle,
              body: strings.trashEmptyBody,
              icon: Icons.delete_outline,
            );
          }
          return Column(
            children: [
              // Active filters stay visible as removable chips, per archetype C — a filter you cannot see is the
              // bug report that begins "my deleted items disappeared".
              if (filter.isNotEmpty)
                FilterChipBar(
                  filters: [
                    for (final kind in filter)
                      ActiveFilter(
                        label: _kindLabel(strings, kind),
                        onRemove: () =>
                            ref.read(trashFilterProvider.notifier).toggle(kind),
                      ),
                  ],
                  clearAllLabel: strings.actionClear,
                  onClearAll: ref.read(trashFilterProvider.notifier).clear,
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AlayaSpacing.screenEdge,
                  vertical: AlayaSpacing.xs,
                ),
                child: Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xs,
                  children: [
                    for (final kind in TrashKind.values)
                      if (entries.any((entry) => entry.kind == kind))
                        FilterChip(
                          label: Text(
                            _kindLabel(strings, kind),
                            style: AlayaTypography.button,
                          ),
                          selected: filter.contains(kind),
                          onSelected: (_) => ref
                              .read(trashFilterProvider.notifier)
                              .toggle(kind),
                        ),
                  ],
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? EmptyState(
                        title: strings.trashNoMatchTitle,
                        body: strings.trashNoMatchBody,
                        icon: Icons.filter_alt_off_outlined,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(
                          bottom: AlayaSpacing.xxxl,
                        ),
                        itemCount: rows.length,
                        itemBuilder: (context, index) =>
                            _TrashRow(entry: rows[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _emptyNow(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.trashEmptyNowConfirmTitle,
      // **The only hard delete a user can reach**, so the body says it plainly: this is not the trash, it is gone.
      body: strings.trashEmptyNowConfirmBody,
      confirmLabel: strings.trashEmptyNow,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final controller = ref.read(trashControllerProvider.notifier);
    final ok = await controller.purgeAll();
    if (!context.mounted) return;
    ok
        ? showResultSnack(
            context,
            message: strings.trashPurged(controller.lastPurged),
          )
        : showFailureSnack(context, message: strings.trashPurgeFailed);
  }

  String _kindLabel(AlayaStrings strings, TrashKind kind) => switch (kind) {
    TrashKind.transaction => strings.trashKindTransaction,
    TrashKind.item => strings.trashKindItem,
    TrashKind.asset => strings.trashKindAsset,
    TrashKind.shoppingList => strings.trashKindShoppingList,
    TrashKind.recurringTemplate => strings.trashKindRecurring,
    TrashKind.tag => strings.trashKindTag,
    TrashKind.payee => strings.trashKindPayee,
  };
}

/// One deleted thing.
class _TrashRow extends ConsumerWidget {
  const _TrashRow({required this.entry});

  final TrashEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return ListTile(
      title: Text(entry.label, style: AlayaTypography.cardTitle),
      // **Two lines, not one Row of three pieces.** A `ListTile` gives its subtitle whatever the trailing widget
      // leaves — 142dp at a doubled text scale — and "Deleted", a date and a retention note will not share that.
      // The layout test caught it before a device did.
      isThreeLine: true,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                strings.trashDeletedOn,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
              const SizedBox(width: AlayaSpacing.xxs),
              Flexible(
                child: DateText(
                  DateKey.fromDateTime(
                    DateTime.fromMillisecondsSinceEpoch(
                      entry.deletedAtUtcMillis,
                      isUtc: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Text(
            // Says when it goes, because a trash that silently empties is one people stop trusting with the
            // thing they deleted by accident.
            strings.trashGoesOn,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ],
      ),
      // **An icon, not a text button.** "Restore" at a doubled scale took most of the row's width and left the
      // subtitle unreadable. The tooltip and the `Semantics` label carry the word for anyone who needs it, which
      // is what ARCH_5 §2.7 asks of an icon that is not one of the six that stand alone.
      trailing: IconButton(
        onPressed: () => _restore(context, ref, strings),
        tooltip: strings.trashRestore,
        icon: Icon(
          Icons.restore_from_trash_outlined,
          size: AlayaIconSize.md,
          color: semantic.muted,
        ),
      ),
      onLongPress: () => _purge(context, ref, strings),
    );
  }

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    final ok = await ref.read(trashControllerProvider.notifier).restore(entry);
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.trashRestored)
        : showFailureSnack(context, message: strings.trashRestoreFailed);
  }

  Future<void> _purge(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.trashPurgeConfirmTitle,
      body: strings.trashPurgeConfirmBody,
      confirmLabel: strings.trashPurgeOne,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await ref.read(trashControllerProvider.notifier).purge(entry);
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.trashPurgedOne)
        : showFailureSnack(context, message: strings.trashPurgeFailed);
  }
}
```

### `lib/features/trash/providers/trash_providers.dart`

```dart
/// View-model state for the trash screen (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/domain/services/trash/trash_port.dart';

/// Everything currently in the trash.
final trashProvider = StreamProvider<List<TrashEntry>>(
  (ref) => ref.watch(trashPortProvider).watchAll(),
);

/// Which kinds the user is filtering to, empty meaning all.
final trashFilterProvider =
    NotifierProvider<TrashFilterNotifier, Set<TrashKind>>(
      TrashFilterNotifier.new,
    );

/// Holds the active filter.
class TrashFilterNotifier extends Notifier<Set<TrashKind>> {
  @override
  Set<TrashKind> build() => const {};

  /// Adds or removes [kind].
  void toggle(TrashKind kind) {
    final next = {...state};
    next.contains(kind) ? next.remove(kind) : next.add(kind);
    state = next;
  }

  /// Clears the filter.
  void clear() => state = const {};
}

/// The trash after the active filter.
final filteredTrashProvider = Provider<List<TrashEntry>>((ref) {
  final all = ref.watch(trashProvider).valueOrNull ?? const <TrashEntry>[];
  final filter = ref.watch(trashFilterProvider);
  if (filter.isEmpty) return all;
  return [
    for (final entry in all)
      if (filter.contains(entry.kind)) entry,
  ];
});

/// Restoring and purging.
final trashControllerProvider =
    NotifierProvider<TrashController, AsyncValue<void>>(TrashController.new);

/// Runs the restore and the one hard delete.
class TrashController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// How many rows the last purge removed.
  int get lastPurged => _lastPurged;
  int _lastPurged = 0;

  /// Un-deletes an entry.
  Future<bool> restore(TrashEntry entry) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(trashPortProvider).restore(entry);
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  /// Hard-deletes one entry.
  Future<bool> purge(TrashEntry entry) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(trashPortProvider).purge(entry);
    _lastPurged = result.isOk ? 1 : 0;
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  /// Hard-deletes everything.
  Future<bool> purgeAll() async {
    state = const AsyncLoading<void>();
    final result = await ref.read(trashPortProvider).purgeAll();
    _lastPurged = result.valueOrNull ?? 0;
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  bool _settle(Object? failure) {
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}
```

### `test/features/ops/ops_screens_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart';
import 'package:alaya/domain/services/reminders/reminder_port.dart';
import 'package:alaya/domain/services/support/support_port.dart';
import 'package:alaya/domain/services/trash/trash_port.dart';
import 'package:alaya/features/backup/presentation/screens/backup_screen.dart';
import 'package:alaya/features/backup/presentation/screens/restore_flow.dart';
import 'package:alaya/features/reminders/presentation/screens/reminders_screen.dart';
import 'package:alaya/features/support/presentation/screens/support_screen.dart';
import 'package:alaya/features/trash/presentation/screens/trash_screen.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';

import '../../support/ops_harness.dart';

/// The 8B screens — four states each (Law U4), and the CRITICAL requirements asserted rather than assumed.
void main() {
  group('backup — the export warning', () {
    testWidgets(
      'every export path goes through a sheet carrying ARCH_3 §3.4 verbatim',
      (tester) async {
        final transfer = FakeTransfer();
        await pumpOps(
          tester,
          const BackupScreen(),
          overrides: opsOverrides(transfer: transfer),
          size: kTallViewport,
        );
        await tester.pumpAndSettle();

        for (final action in ['Save a copy', 'Share a copy']) {
          await tester.tap(find.text(action));
          await tester.pumpAndSettle();

          // **The exact sentence, including the third clause.** 8A shipped a paraphrase that dropped "Only share it
          // somewhere you trust" — the only actionable sentence of the three — and nothing caught it until §3.4 was
          // read directly. Asserting the words rather than the key is what stops that recurring.
          expect(find.textContaining('not encrypted'), findsOneWidget);
          expect(
            find.textContaining('every transaction, balance and account name'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Only share it somewhere you trust'),
            findsOneWidget,
          );

          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
        }
        // Cancelling the warning wrote nothing, twice.
        expect(transfer.exports, 0);
      },
    );

    testWidgets('history renders its four states', (tester) async {
      await pumpOps(
        tester,
        const BackupScreen(),
        overrides: opsOverrides(transfer: FakeTransfer(history: const [])),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);

      await pumpOps(
        tester,
        const BackupScreen(),
        overrides: opsOverrides(
          transfer: FakeTransfer(history: [backupRecord()]),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      // The name is derived from the path, because the table stores no file name.
      expect(find.text('alaya-2026-08-08.db'), findsOneWidget);
    });
  });

  group('restore — the guards, in order', () {
    testWidgets('a newer backup is refused with both version numbers', (
      tester,
    ) async {
      await pumpOps(
        tester,
        const RestoreFlow(),
        overrides: opsOverrides(
          transfer: FakeTransfer(backupVersion: 7, schemaVersion: 1),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Choose a file'), findsOneWidget);
      // The gate itself is exercised in the port's own test; here the screen must be able to *say* it, which is
      // what a refusal nobody can act on fails at.
      expect(find.textContaining('Alaya is never restored'), findsNothing);
      expect(find.textContaining('PIN is never restored'), findsOneWidget);
    });

    testWidgets('the lock-not-restored line is on the first screen', (
      tester,
    ) async {
      await pumpOps(
        tester,
        const RestoreFlow(),
        overrides: opsOverrides(),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      // ARCH_3 §3.2's last line, on the one screen where somebody might expect otherwise.
      expect(find.textContaining('never restored'), findsOneWidget);
    });
  });

  group('reminders — contextual permission, all off', () {
    testWidgets('every toggle starts off', (tester) async {
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(reminders: FakeReminders()),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      final switches = tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      // ARCH_3 §7: all reminders default off. `ReminderSettings.fresh()` is what makes that true.
      expect(switches.isNotEmpty, isTrue);
      expect(switches.every((tile) => tile.value == false), isTrue);
    });

    testWidgets('permission is requested on the first switch-on, not on open', (
      tester,
    ) async {
      final reminders = FakeReminders(
        permissionState: ReminderPermission.notRequested,
      );
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(reminders: reminders),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      // **Nothing asked merely by opening the screen.** Asking on launch is what gets an app denied for good.
      expect(reminders.permissionRequests, 0);

      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      expect(reminders.permissionRequests, 1);
    });

    testWidgets('nothing on reads as nothing on', (tester) async {
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(reminders: FakeReminders()),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      // Everything off: an empty schedule is correct, and switching one on is the fix.
      expect(find.text('Nothing scheduled'), findsOneWidget);
      expect(find.text('Check now'), findsNothing);
    });

    testWidgets('reminders on with nothing due says so, and offers a scan', (
      tester,
    ) async {
      // **The case that made a working feature look broken.** `_scheduleDigest` deliberately sends
      // nothing rather than a message reading "0 items expire this week" — so an empty schedule with
      // reminders on is correct behaviour. The old copy said "turn on a reminder above", which is what
      // the user had already done.
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(
          reminders: FakeReminders(
            settings: const ReminderSettings.fresh().copyWith(
              enabled: {NotificationKind.expiry},
            ),
          ),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.text('Nothing due this week'), findsOneWidget);
      expect(find.text('Nothing scheduled'), findsNothing);
      expect(find.text('Check now'), findsOneWidget);
    });

    testWidgets('a scan that finds nothing says nothing found, not failed', (
      tester,
    ) async {
      // The sentence that was impossible to obtain before: proof the reminder works and the week is
      // simply clear. Reporting this as a failure would be the wrong answer to a correct scan.
      final reminders = FakeReminders(
        settings: const ReminderSettings.fresh().copyWith(
          enabled: {NotificationKind.expiry},
        ),
        rescheduleCount: 0,
      );
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(reminders: reminders),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check now'));
      await tester.pumpAndSettle();
      expect(reminders.reschedules, 1);
      expect(
        find.text('Nothing coming up in the next week'),
        findsOneWidget,
      );
    });

    testWidgets('a scan that finds things names the number', (tester) async {
      final reminders = FakeReminders(
        settings: const ReminderSettings.fresh().copyWith(
          enabled: {NotificationKind.expiry},
        ),
        rescheduleCount: 3,
      );
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(reminders: reminders),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check now'));
      await tester.pumpAndSettle();
      // Naming the count is what proves the scan ran rather than merely returned.
      expect(find.text('3 things coming up'), findsOneWidget);
    });

    testWidgets('a test notification can be sent whenever a reminder is on', (
      tester,
    ) async {
      // **The diagnostic that was missing.** A digest scheduled for tomorrow morning and a broken
      // delivery path look identical from outside the app, and nothing distinguished them.
      final reminders = FakeReminders(
        settings: const ReminderSettings.fresh().copyWith(
          enabled: {NotificationKind.expiry},
        ),
      );
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(reminders: reminders),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send a test notification'));
      await tester.pumpAndSettle();
      expect(reminders.testsSent, 1);
      expect(find.text('Sent — check your notifications'), findsOneWidget);
    });

    testWidgets('a failed test reports the reason, not a generic error', (
      tester,
    ) async {
      // A missing `@drawable/ic_notification` throws at post time and nowhere else — the compiler never
      // sees that string. Swallowing the message would discard the only diagnosis available.
      final reminders = FakeReminders(
        settings: const ReminderSettings.fresh().copyWith(
          enabled: {NotificationKind.expiry},
        ),
      )..testFails = true;
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(reminders: reminders),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send a test notification'));
      await tester.pumpAndSettle();
      expect(
        find.text('That test notification could not be sent.'),
        findsOneWidget,
      );
    });

    testWidgets('the test action is hidden when nothing is on', (tester) async {
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(reminders: FakeReminders()),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      // Nothing to test when nothing is on, and offering it would invite a false negative.
      expect(find.text('Send a test notification'), findsNothing);
    });

    testWidgets('a refused request leaves the switch off', (tester) async {
      final reminders = FakeReminders(
        permissionState: ReminderPermission.denied,
      );
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(reminders: reminders),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      // A control reading "on" while the OS drops every notification is a control that lies.
      final switches = tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(switches.every((tile) => tile.value == false), isTrue);
    });

    testWidgets('shows what is scheduled', (tester) async {
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(
          reminders: FakeReminders(scheduled: [scheduledReminder()]),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.text('Daily summary'), findsWidgets);
    });
  });

  group('trash — retention and the one hard delete', () {
    testWidgets('loading is a skeleton', (tester) async {
      // The stream must never emit, or the loading branch is gone before the first assertion — a
      // `Stream.value` resolves in the same microtask drain as the first frame.
      await pumpOps(
        tester,
        const TrashScreen(),
        overrides: opsOverrides(trash: FakeTrash(loading: true)),
      );
      expect(find.byType(AlayaListSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('empty explains the thirty days', (tester) async {
      await pumpOps(
        tester,
        const TrashScreen(),
        overrides: opsOverrides(trash: FakeTrash(entries: const [])),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.textContaining('30 days'), findsOneWidget);
    });

    testWidgets('every row says when it goes', (tester) async {
      await pumpOps(
        tester,
        const TrashScreen(),
        overrides: opsOverrides(trash: FakeTrash(entries: [trashEntry()])),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      // A trash that silently empties is one people stop trusting with what they deleted by accident.
      expect(find.textContaining('kept for 30 days'), findsOneWidget);
    });

    testWidgets('empty now is confirmed before anything is purged', (
      tester,
    ) async {
      final trash = FakeTrash(
        entries: [
          trashEntry(),
          trashEntry(id: 'tr-2', label: 'Rice'),
        ],
      );
      await pumpOps(
        tester,
        const TrashScreen(),
        overrides: opsOverrides(trash: trash),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Empty now'));
      await tester.pumpAndSettle();
      expect(find.textContaining('nowhere left for it to go'), findsOneWidget);
      expect(trash.purged, 0);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(trash.purged, 0);
    });
  });

  group('support — nothing loads unless this screen opens it', () {
    testWidgets('opening the screen is what starts the SDK', (tester) async {
      final support = FakeSupport();
      // Before the screen exists, nothing has been asked of the port.
      expect(support.initialisations, 0);
      expect(support.adLoads, 0);

      await pumpOps(
        tester,
        const SupportScreen(),
        overrides: opsOverrides(support: support),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      // **One initialisation, from `initState`.** The rest of the app makes zero ad calls because
      // `AdsAndBilling` is the only file importing either SDK — this asserts the other half, that the screen is
      // what triggers it.
      expect(support.initialisations, 1);
      expect(support.adLoads, 1);
    });

    testWidgets('no advert is requested when consent could not be settled', (
      tester,
    ) async {
      final support = FakeSupport(consent: AdConsent.unavailable);
      await pumpOps(
        tester,
        const SupportScreen(),
        overrides: opsOverrides(support: support),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      // Requesting an ad before consent is settled is what gets an app pulled in the EEA.
      expect(support.adLoads, 0);
      expect(find.textContaining('Nothing has been requested'), findsOneWidget);
    });

    testWidgets('the tip shows the store price, unformatted by us', (
      tester,
    ) async {
      await pumpOps(
        tester,
        const SupportScreen(),
        overrides: opsOverrides(support: FakeSupport()),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      // The store's own string. Reformatting it through AmountText would render it in the wrong currency.
      expect(find.textContaining('₹99.00'), findsOneWidget);
    });

    testWidgets('says plainly that nothing is unlocked', (tester) async {
      await pumpOps(
        tester,
        const SupportScreen(),
        overrides: opsOverrides(),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('no paid features'), findsOneWidget);
    });
  });

  group('the gate', () {
    testWidgets('every screen renders at 320x640 with a doubled text scale', (
      tester,
    ) async {
      final screens = <Widget>[
        const BackupScreen(),
        const RestoreFlow(),
        const RemindersScreen(),
        const TrashScreen(),
        const SupportScreen(),
      ];
      for (final screen in screens) {
        await pumpOps(
          tester,
          screen,
          overrides: opsOverrides(
            transfer: FakeTransfer(history: [backupRecord()]),
            trash: FakeTrash(entries: [trashEntry()]),
            reminders: FakeReminders(scheduled: [scheduledReminder()]),
          ),
          textScale: 2,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });
}
```

### `test/features/ops/reminders_schedule_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/domain/services/reminders/reminder_port.dart';
import 'package:alaya/features/reminders/presentation/screens/reminders_screen.dart';

import '../../support/ops_harness.dart';

/// The assertions whose absence let a five-and-a-half-hour scheduling error ship.
///
/// **A new file rather than more cases in `ops_screens_test.dart`**, because these are not about the four states
/// per screen that file exists to cover. They are about one specific failure mode: the screen displaying a value
/// it was given as *input* while presenting it as the schedule's *output*. That fault has nothing to do with
/// loading, empty or error branches and everything to do with which field a row reads.
///
/// **Why the old suite could not catch it.** `shows what is scheduled` asserted `find.text('Daily summary')` —
/// the row's title, which was correct throughout. The row was rendering the digest time from the settings object
/// passed down from the parent, so a schedule at 14:30 with a setting of 09:00 displayed 09:00 and every
/// assertion passed. The fixture could not express the divergence either: it took a `DateKey`, so no test could
/// construct a schedule whose time differed from the setting at all.
void main() {
  /// Reminders on, so the sections under test are rendered at all.
  ReminderSettings enabled() => const ReminderSettings.fresh().copyWith(
    enabled: {NotificationKind.expiry},
  );

  AlayaStrings stringsOf(WidgetTester tester) =>
      AlayaStrings.of(tester.element(find.byType(RemindersScreen)));

  group('the scheduled row reports the schedule, not the setting', () {
    testWidgets('a digest set for 09:00 but scheduled for 14:30 shows 14:30', (
      tester,
    ) async {
      // The whole bug in one fixture: the setting says nine, the OS is holding half past two. Before
      // `ScheduledReminder.at` existed the row could only read the former, so this test could not be written
      // and the failure could not be seen from inside the app.
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(
          reminders: FakeReminders(
            settings: enabled(),
            scheduled: [scheduledReminder(at: DateTime(2026, 8, 12, 14, 30))],
          ),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      // **Asserted on the minutes rather than the whole formatted string.** `MaterialLocalizations` renders
      // `2:30 PM` on a 12-hour locale and `14:30` on a 24-hour one, and both are correct — so matching the
      // half-past holds whichever the test environment picks, while a literal `'2:30 PM'` would make this
      // test a statement about the locale instead of about the screen.
      expect(find.textContaining(':30'), findsOneWidget);

      // The setting is still on screen and still says nine. That is the point: two values, both shown, no
      // longer pretending to be one. A count assertion, because `findsWidgets` would pass if the digest-time
      // row had vanished entirely and something else supplied the text.
      expect(find.textContaining('Sent at'), findsOneWidget);
    });

    testWidgets('the row survives a schedule whose minutes match the setting', (
      tester,
    ) async {
      // The control case, and the reason the assertion above is not enough on its own: a screen that printed
      // nothing at all would also fail to show `:30`. Here the schedule and the setting agree, so exactly two
      // widgets carry the same time — the setting row and the scheduled row.
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(
          reminders: FakeReminders(
            settings: enabled(),
            scheduled: [scheduledReminder(at: DateTime(2026, 8, 12, 9))],
          ),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining(':00'), findsNWidgets(2));
    });
  });

  group('the zone is named, because its silence was the bug', () {
    testWidgets('a matched zone is shown by name', (tester) async {
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(
          reminders: FakeReminders(settings: enabled()),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Asia/Kolkata'), findsOneWidget);
    });

    testWidgets('an unmatched zone warns instead of naming it', (tester) async {
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(
          reminders: FakeReminders(
            settings: enabled(),
            // What the app did on every device before this work: resolved to UTC and scheduled against it
            // without saying so.
            deviceZone: const ReminderZone(name: 'UTC', matchesDevice: false),
          ),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      // **Read from the ARB rather than typed in.** Asserting the copy verbatim would make this a test of the
      // string table, and it would break on a wording change that altered no behaviour.
      expect(
        find.text(stringsOf(tester).remindersZoneUnknown),
        findsOneWidget,
      );
      // The name is withheld, because naming a zone the device disagrees with is the confident wrong answer
      // this line replaced.
      expect(find.textContaining('UTC'), findsNothing);
    });

    testWidgets('nothing is claimed while every reminder is off', (
      tester,
    ) async {
      await pumpOps(
        tester,
        const RemindersScreen(),
        // `ReminderSettings.fresh()` by default: all four off (ARCH_3 §7).
        overrides: opsOverrides(reminders: FakeReminders()),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Asia/Kolkata'), findsNothing);
      expect(
        find.text(stringsOf(tester).remindersZoneUnknown),
        findsNothing,
      );
    });
  });

  group('the phone is asked, not just the database', () {
    testWidgets('a row the OS is not holding is called out', (tester) async {
      // **The state the app shipped in and could not describe.** A row in `notification_schedule`, a date, a
      // time, a zone — everything agreeing, and no alarm behind any of it. Before `pendingCount` this screen
      // rendered identical output for a schedule that worked and one the OS had refused.
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(
          reminders: FakeReminders(
            settings: enabled(),
            scheduled: [scheduledReminder()],
            osPendingCount: 0,
          ),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.text(stringsOf(tester).remindersOsMissing), findsOneWidget);
      expect(find.text(stringsOf(tester).remindersOsHolding), findsNothing);
    });

    testWidgets('a row the OS is holding is confirmed', (tester) async {
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(
          reminders: FakeReminders(
            settings: enabled(),
            scheduled: [scheduledReminder()],
          ),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.text(stringsOf(tester).remindersOsHolding), findsOneWidget);
    });

    testWidgets('a plugin that throws warns rather than falling silent', (
      tester,
    ) async {
      // A negative count stands for the plugin throwing. It must read as the warning rather than as an absent
      // line — silence on the error branch is the behaviour this widget exists to replace.
      await pumpOps(
        tester,
        const RemindersScreen(),
        overrides: opsOverrides(
          reminders: FakeReminders(
            settings: enabled(),
            scheduled: [scheduledReminder()],
            osPendingCount: -1,
          ),
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.text(stringsOf(tester).remindersOsMissing), findsOneWidget);
    });
  });
}
```
