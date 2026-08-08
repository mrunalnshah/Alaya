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
