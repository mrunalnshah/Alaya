import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/platform/saf_channel.dart';
import 'package:alaya/domain/services/attachments/attachment_port.dart';

/// The production [AttachmentPort]: `file_picker` in, a private app directory on disk, a row in `attachments`.
///
/// **The only file in this phase that imports `file_picker` or `path_provider`.** Both are plugins, so a widget
/// test cannot run them; confining them here is the containment 7A applied to `table_calendar` and 8A to
/// `local_auth`. `file_picker`'s surface could not be compiled against (ARCH_4 R22), and 8A's experience with
/// `local_auth` says to expect the first build to disagree — if it does, this file changes and nothing else.
///
/// **Files live inside the app's own directory, never in shared storage** (ARCH_3 §3.3). That is what makes SAF
/// the only outward path and `WRITE_EXTERNAL_STORAGE` unnecessary: Alaya writes where it already has the right to
/// write, and the user reaches it through the system's own sheets.
final class AttachmentStore implements AttachmentPort {
  /// Creates the store.
  AttachmentStore({
    required AlayaDatabase database,
    required UidGenerator uids,
    required Clock clock,
    SafChannel saf = const SafChannel(),
  }) : _db = database,
       _uids = uids,
       _clock = clock,
       _saf = saf;

  final AlayaDatabase _db;
  final UidGenerator _uids;
  final Clock _clock;
  final SafChannel _saf;

  /// The directory attachments live in, relative to the app's documents directory.
  static const String directoryName = 'attachments';

  Directory? _cachedRoot;

  Future<Directory> _root() async {
    final cached = _cachedRoot;
    if (cached != null) return cached;
    final documents = await getApplicationDocumentsDirectory();
    final root = Directory(
      '${documents.path}${Platform.pathSeparator}$directoryName',
    );
    if (!root.existsSync()) await root.create(recursive: true);
    _cachedRoot = root;
    return root;
  }

  Attachment _toEntity(AttachmentRow row) => Attachment(
    id: row.id,
    owner: AttachmentOwner.values.firstWhere(
      (owner) => owner.storedValue == row.ownerType,
      // **Falls back rather than throwing**, for the reason Law L13 gives about enums in the database: a
      // later version may write an owner type this build has never heard of, and one unknown row must not
      // take out the list it appears in.
      orElse: () => AttachmentOwner.transaction,
    ),
    ownerId: row.ownerId,
    relativePath: row.relativePath,
    mimeType: row.mimeType,
    sizeBytes: row.sizeBytes,
    addedAtUtcMillis: row.createdAt,
  );

  @override
  Stream<List<Attachment>> watchFor({
    required AttachmentOwner owner,
    required String ownerId,
  }) {
    final query = _db.select(_db.attachments)
      ..where((row) => row.ownerType.equals(owner.storedValue))
      ..where((row) => row.ownerId.equals(ownerId))
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]);
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  @override
  Stream<int> watchCountFor({
    required AttachmentOwner owner,
    required String ownerId,
  }) => watchFor(owner: owner, ownerId: ownerId).map((rows) => rows.length);

  @override
  Future<Result<Attachment?, Failure>> attach({
    required AttachmentOwner owner,
    required String ownerId,
  }) async {
    try {
      // Through the SAF channel rather than `file_picker`, which cannot be used in this project (ARCH_1 §7.4).
      // The channel copies the chosen document into the cache before returning, so this is a real path.
      final picked = await _saf.openDocument(mimeTypes: const ['image/*']);
      if (picked.isFailure) return Result.failure(picked.failureOrNull!);
      final source = picked.valueOrNull;
      // Dismissing the picker is the commonest outcome of a file chooser, so it is an absent value rather than a
      // failure — reporting it as an error would put a red message under a deliberate action.
      if (source == null) return const Result.ok(null);

      final file = File(source);
      if (!file.existsSync()) {
        return const Result.failure(
          BusinessRuleFailure(
            'That file is no longer there.',
            rule: 'attachmentMissing',
          ),
        );
      }

      final id = _uids.generate();
      final extension = source.contains('.')
          ? source.split('.').last.toLowerCase()
          : 'bin';
      final relative = '$id.$extension';
      final root = await _root();
      // **Copied, not referenced.** The picked file may live in a cache the OS reclaims, or behind a content URI
      // that expires with the permission grant — a row pointing at either is a broken thumbnail tomorrow.
      final stored = await file.copy(
        '${root.path}${Platform.pathSeparator}$relative',
      );
      final size = await stored.length();
      final now = _clock.nowUtcMillis();

      await _db
          .into(_db.attachments)
          .insert(
            AttachmentsCompanion.insert(
              id: id,
              ownerType: owner.storedValue,
              ownerId: ownerId,
              relativePath: relative,
              mimeType: _mimeFor(extension),
              sizeBytes: size,
              createdAt: now,
              updatedAt: now,
            ),
          );

      return Result.ok(
        Attachment(
          id: id,
          owner: owner,
          ownerId: ownerId,
          relativePath: relative,
          mimeType: _mimeFor(extension),
          sizeBytes: size,
          addedAtUtcMillis: now,
        ),
      );
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That file could not be attached.', cause: error),
      );
    }
  }

  @override
  Future<Result<String, Failure>> resolvePath(Attachment attachment) async {
    try {
      final root = await _root();
      return Result.ok(
        '${root.path}${Platform.pathSeparator}${attachment.relativePath}',
      );
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That file could not be found.', cause: error),
      );
    }
  }

  @override
  Future<Result<void, Failure>> open(Attachment attachment) async {
    final path = await resolvePath(attachment);
    final resolved = path.valueOrNull;
    if (resolved == null) return Result.failure(path.failureOrNull!);
    if (!File(resolved).existsSync()) {
      // Says which of the two went missing. A row whose file is gone is a different problem from a row that was
      // never written, and only one of them is fixed by re-attaching.
      return const Result.failure(
        BusinessRuleFailure(
          'The file is missing from this device.',
          rule: 'attachmentFileGone',
        ),
      );
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> delete(Attachment attachment) async {
    try {
      final path = await resolvePath(attachment);
      final resolved = path.valueOrNull;
      if (resolved != null) {
        final file = File(resolved);
        if (file.existsSync()) await file.delete();
      }
      // **The row goes last.** A failure between the two leaves an orphan file rather than a row pointing at
      // nothing — the recoverable direction, because a stray file wastes space while a broken row renders as a
      // permanently broken thumbnail.
      await (_db.update(_db.attachments)
            ..where((row) => row.id.equals(attachment.id)))
          .write(AttachmentsCompanion(deletedAt: Value(_clock.nowUtcMillis())));
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure(
          'That attachment could not be removed.',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<List<String>, Failure>> allFilePaths() async {
    try {
      final rows = await (_db.select(
        _db.attachments,
      )..where((row) => row.deletedAt.isNull())).get();
      final root = await _root();
      return Result.ok([
        for (final row in rows)
          '${root.path}${Platform.pathSeparator}${row.relativePath}',
      ]);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The attachments could not be listed.', cause: error),
      );
    }
  }

  /// A MIME type from a file extension.
  ///
  /// A short table rather than a package: the picker is restricted to images, so five cases cover everything it
  /// can return and a dependency to look up the sixth would not earn its place.
  String _mimeFor(String extension) => switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'gif' => 'image/gif',
    _ => 'application/octet-stream',
  };
}
