import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// What an export produced.
///
/// Moved here from `data/` in 8A so a feature can name it. A record of four plain values with no drift
/// or Flutter dependency, so `domain/` is a legal home for it on Law L12's own terms.
typedef BackupArtefact = ({
  String path,
  int sizeBytes,
  bool isZipped,
  String fileName,
});

/// Which way a backup was applied.
///
/// Mirrored into `domain/` in 8B so a screen can name it. The `data/` enum it corresponds to is the same two
/// cases; a screen that could not say which mode ran could not offer the rollback that only one of them creates.
enum RestoreMode {
  /// Upserted by UUID, keeping rows the backup does not have.
  merge,

  /// The file was swapped wholesale, with a rollback snapshot taken first.
  replace,
}

/// What a restore did.
typedef RestoreOutcome = ({
  RestoreMode mode,
  int tablesMerged,
  int backupSchemaVersion,
  bool rollbackAvailable,
});

/// One entry in `backup_history`.
///
/// **Mirrors the columns that exist, which is not what I first wrote.** The table stores `filePath`, `sizeBytes`,
/// `schemaVersion` and a `kind` of manual-or-auto; it has no `fileName` and no `isZipped`, both of which my first
/// version invented. The name is derived from the path, which is the one place it can honestly come from.
class BackupRecord {
  /// Creates a record.
  const BackupRecord({
    required this.id,
    required this.filePath,
    required this.sizeBytes,
    required this.schemaVersion,
    required this.takenAtUtcMillis,
    this.note,
  });

  /// Row identifier.
  final String id;

  /// Where the file was written.
  final String filePath;

  /// How large it was.
  final int sizeBytes;

  /// The schema version inside it, so an old backup can be labelled as old.
  final int schemaVersion;

  /// When it was taken.
  final int takenAtUtcMillis;

  /// Whatever the service recorded about it.
  final String? note;

  /// The file's name, derived rather than stored.
  ///
  /// **A backup you cannot identify is one you will not trust when you need it** — ARCH_3 §3.4's quieter
  /// counterpart. A list of dated rows with no names is not a history.
  String get fileName {
    final parts = filePath.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? filePath : parts.last;
  }
}

/// Exporting the database, and erasing it.
///
/// **One port for both, because they are the two halves of the same conversation.** ARCH_3 §2.2's
/// forgot-both path offers an export *and then* erases, and a user who is about to lose everything
/// should not have that offer come from a different subsystem than the erase does.
///
/// **Why a port at all.** The export needs a destination path (`path_provider`) and a way to hand the
/// file off (`share_plus`), and both are plugins — so a feature orchestrating them directly would be
/// untestable, and Law L12 keeps plugin dependencies out of `domain/`. The screens see this; `data/`
/// owns the platform.
abstract interface class DataTransferPort {
  /// The word the user must type before an erase runs (ARCH_3 §2.2).
  ///
  /// **On the contract, because the screen that compares against it may not import `data/`** — and
  /// because a second copy in the UI would be a second thing to change. Not localised, and the only
  /// user-facing string in this project exempt from Law U5: a translated confirmation word would mean a
  /// support article could not tell anyone what to type, and the point of the gate is that it cannot be
  /// satisfied by tapping.
  static const String eraseConfirmationWord = 'ERASE';

  /// Writes a backup somewhere the user can reach and offers to share it.
  ///
  /// Returns the artefact so a screen can state the file name and size — a backup the user cannot
  /// identify later is one they will not trust when they need it (ARCH_3 §3.4).
  Future<Result<BackupArtefact, Failure>> exportAndShare();

  /// Whether a Storage Access Framework **create-document** sheet can be raised at all.
  ///
  /// **On the contract, because the screen has to decide whether to show the row** — and a feature may not import
  /// `data/` to ask the implementation. False on the pinned `file_picker`, whose `saveFile` the analyzer rejected
  /// outright; sharing still goes through a system sheet, so ARCH_3 §3.3 holds either way and what is missing is
  /// only the choose-a-folder shape of the same export.
  bool get canSaveToLocation;

  /// Writes a backup to a location the user chose, through the Storage Access Framework.
  ///
  /// **SAF, and only SAF** (ARCH_3 §3.3). No `WRITE_EXTERNAL_STORAGE`, no `MANAGE_EXTERNAL_STORAGE`: the user
  /// picks the destination in the system's own create-document sheet, which is both the modern Android answer and
  /// the one that needs no storage permission at all.
  ///
  /// Returns null when the sheet was dismissed — cancelling is not a failure.
  Future<Result<BackupArtefact?, Failure>> exportToLocation();

  /// Every backup this app has taken, newest first.
  Stream<List<BackupRecord>> watchHistory();

  /// Forgets a history entry, without touching the file it describes.
  ///
  /// **The file is not deleted, and the copy says so.** It lives wherever the user put it — a Drive folder, a
  /// WhatsApp thread — and this app has no business reaching in there. Forgetting the row is all this can honestly
  /// offer (ARCH_5 §7's "delete entry").
  Future<Result<void, Failure>> forgetHistoryEntry(String id);

  /// Opens the system file chooser and returns a readable path to what the user picked.
  ///
  /// **On the contract because the chooser lives in `data/`.** Returns null when the sheet was dismissed, which
  /// is not a failure. The path is a cache copy rather than the chosen document itself, because `ATTACH DATABASE`
  /// needs a filesystem path and the read grant expires with the picker.
  Future<Result<String?, Failure>> pickBackupFile();

  /// The schema version inside the backup at [path], for the gate ARCH_3 §3.2 puts first.
  Future<Result<int, Failure>> readBackupVersion(String path);

  /// The schema version this build of the app writes.
  ///
  /// Exposed so a screen can say *"that backup is from a newer version (7) than this app understands (1)"* rather
  /// than only refusing. A refusal without both numbers is one nobody can act on.
  int get appSchemaVersion;

  /// Applies the backup at [path] by upserting on UUID, last-write-wins on `updatedAt`.
  ///
  /// Rows absent from the backup are kept, which is what makes merge the safe mode and the default.
  Future<Result<RestoreOutcome, Failure>> merge(String path);

  /// Replaces the live database with the backup at [path], snapshotting a rollback first.
  ///
  /// **The destructive mode.** ARCH_3 §3.2's order is verify, gate, snapshot, swap, and auto-restore the rollback
  /// if reopening throws. It is behind a typed confirmation in the UI, and it never restores the lock — PIN and
  /// recovery hashes are in secure storage, so importing a backup cannot change who can open the app.
  Future<Result<RestoreOutcome, Failure>> replace(String path);

  /// Puts the pre-replace snapshot back.
  ///
  /// Offered after a Replace so the user is never one tap from a decision they cannot walk back.
  Future<Result<void, Failure>> rollback();

  /// Whether a rollback snapshot exists to go back to.
  Future<bool> hasRollback();

  /// Deletes every row, clears the lock, and re-seeds.
  ///
  /// **Clears the lock too, and that is the point.** A user who has forgotten their PIN *and* their
  /// recovery code is locked out; wiping their history while leaving the lock in place would leave them
  /// exactly as locked out, with nothing left to unlock.
  Future<Result<void, Failure>> eraseEverything();
}
