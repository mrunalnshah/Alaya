import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// What a record an attachment can belong to.
///
/// **A closed set, where the column is free text.** ARCH_2 makes `attachments.ownerType` deliberately
/// polymorphic — it is the one such pointer in the schema — and integrity is enforced in the repository rather
/// than by a foreign key. This enum is that enforcement made checkable: a typo cannot reach the column, and
/// adding an eighth owner fails to compile at every switch instead of writing an orphan row.
enum AttachmentOwner {
  /// A transaction's receipt.
  transaction,

  /// An asset's warranty card or invoice.
  asset,

  /// A service record's bill.
  serviceRecord,

  /// An inventory item's photo.
  item,

  /// An inventory batch's label.
  batch;

  /// The value written to `attachments.ownerType`.
  ///
  /// Named rather than `name`, so renaming an enum member is a compile step and not a silent data migration.
  String get storedValue => switch (this) {
    AttachmentOwner.transaction => 'transaction',
    AttachmentOwner.asset => 'asset',
    AttachmentOwner.serviceRecord => 'serviceRecord',
    AttachmentOwner.item => 'item',
    AttachmentOwner.batch => 'batch',
  };
}

/// One attached file.
class Attachment {
  /// Creates an attachment.
  const Attachment({
    required this.id,
    required this.owner,
    required this.ownerId,
    required this.relativePath,
    required this.mimeType,
    required this.sizeBytes,
    required this.addedAtUtcMillis,
  });

  /// Row identifier.
  final String id;

  /// Which kind of record owns it.
  final AttachmentOwner owner;

  /// The owning record's id.
  final String ownerId;

  /// Path **relative** to the app's attachment directory.
  ///
  /// Relative and never absolute, because an absolute path breaks the moment a backup is restored onto a
  /// different device — the directory the app was installed into is not the same one twice (ARCH_2).
  final String relativePath;

  /// The file's type, e.g. `image/jpeg`.
  final String mimeType;

  /// Its size on disk.
  final int sizeBytes;

  /// When it was attached.
  final int addedAtUtcMillis;

  /// Whether this is something a thumbnail can be drawn from.
  bool get isImage => mimeType.startsWith('image/');
}

/// Attaching, listing, viewing and deleting files (ARCH_5 §7's `attachments` row).
///
/// **A port because the file work is all plugin-bound.** Picking needs `file_picker`, resolving a path needs
/// `path_provider`, and opening one for viewing needs a platform intent — none of which a widget test can run.
/// The screens see this; `data/` owns the platform.
///
/// **Deleting removes the row *and* the file, and that ordering matters.** A row without its file renders as a
/// broken thumbnail forever; a file without its row is invisible and never reclaimed. The implementation deletes
/// the row last, so a failure leaves an orphan file rather than a broken record — the recoverable direction.
abstract interface class AttachmentPort {
  /// What is attached to [ownerId], newest first.
  Stream<List<Attachment>> watchFor({
    required AttachmentOwner owner,
    required String ownerId,
  });

  /// How many files are attached to [ownerId].
  ///
  /// Separate from [watchFor] so a detail screen can show a count without reading every row's metadata.
  Stream<int> watchCountFor({
    required AttachmentOwner owner,
    required String ownerId,
  });

  /// Opens the picker, copies what the user chose into the app's attachment directory, and records it.
  ///
  /// Returns null when the user dismissed the picker — **not a failure**. Cancelling is the commonest outcome
  /// of a file chooser and reporting it as an error would put a red message under a deliberate action.
  Future<Result<Attachment?, Failure>> attach({
    required AttachmentOwner owner,
    required String ownerId,
  });

  /// The absolute path of [attachment], for a thumbnail or a viewer.
  ///
  /// Resolved on demand rather than stored, which is the whole reason [Attachment.relativePath] is relative.
  Future<Result<String, Failure>> resolvePath(Attachment attachment);

  /// Opens [attachment] in whatever app the device uses for its type.
  Future<Result<void, Failure>> open(Attachment attachment);

  /// Deletes the file and its row.
  Future<Result<void, Failure>> delete(Attachment attachment);

  /// Every attachment file, for the zipped export `BackupService` builds.
  Future<Result<List<String>, Failure>> allFilePaths();
}
