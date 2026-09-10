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
