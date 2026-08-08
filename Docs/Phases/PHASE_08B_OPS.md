# PHASE 8B — Backup/restore UI, attachments, notifications, trash, Support Us

## Dependencies

```
flutter pub add flutter_local_notifications timezone workmanager
flutter pub add google_mobile_ads in_app_purchase
flutter pub remove file_picker
```

**`file_picker` is *removed*, not added, and that is the correction this phase's first build forced.**

The task's list omits it, and *"Export via SAF"* plainly needs a file chooser — so instalment 1 added it. That was
wrong, and ARCH_1 §7.4 already said why, using this exact package as its worked example: `file_picker` resolves to
**3.0.4, from 2020**, whose `android/build.gradle` calls `jcenter()` — shut down in 2021. **`pub get` succeeds, the
analyzer is clean, the tests pass, and `assembleDebug` fails.** §7.3's analyzer cap walks it backwards no matter
how it is added.

ARCH_1 §7 had also already written the answer — *"evaluate whether a small SAF platform channel is preferable to
the whole plugin"* — and it is. Three files replace it, with no pub dependency and five fewer transitive ones.
See **The SAF platform channel** below.

**Two more package questions I am not answering unilaterally.**

*Camera capture needs `image_picker`, which ARCH_1 §7 does not pin anywhere.* §7's own note on `attachments.*`
says *"camera and file flow are a phase of their own"*, which reads as intending capture. But adding a package
absent from the binding table is exactly what §7.4 exists to prevent, so this phase ships **pick-an-existing-image**
through `file_picker` with `FileType.image`. Attaching a receipt you have already photographed works; photographing
one inside Alaya does not. Say the word and it is `flutter pub add image_picker` plus a §7 row.

*`google_mobile_ads` is pinned "resolver + UMP consent".* UMP — Google's User Messaging Platform — is how EEA
consent for personalised ads is collected, and it ships inside `google_mobile_ads` rather than separately. It is
wired here, but `ConsentInformation` and `ConsentForm` could not be compiled against (ARCH_4 R22), so like every
plugin in this phase they are confined to one file.

**Every one of these six packages is a plugin**, and ARCH_4 R6 is worth restating where it will be read: rewarded
ads in a finance app create Play data-safety and privacy-policy obligations, and **the privacy policy URL is needed
before the first upload, not at launch**.

## What already exists, and what this phase must build

Checked rather than assumed, because 8A's biggest cost was discovering a missing service mid-build.

**Complete, and 8B only calls it:**

| | |
|---|---|
| `BackupService` | `VACUUM INTO`, attachment zipping, and it already writes `backup_history` |
| `RestoreService` | `readBackupSchemaVersion`, `merge`, `replaceFiles`, `restoreRollback` — every guard ARCH_3 §3.2 lists, including the qualified-pragma discovery |
| `NotificationScheduleDao` | stable Android IDs, `replaceForRef`, `cancelForRef`, `pruneSettled` |
| `BackupHistoryDao` | `watchRecent`, `latest`, `softDelete` |
| `attachments` table | present since 1B, deliberately, to avoid a migration |

**Missing entirely, so this phase builds it:**

| | |
|---|---|
| Anything that reads or writes `attachments` | No entity, no contract, no file storage. The table has waited seven phases |
| Anything that enumerates soft-deleted rows | Every table has `deletedAt`; nothing lists them, and **nothing purges** |
| Anything that talks to `flutter_local_notifications` | The DAO records what *should* be scheduled; nobody schedules it |
| A domain surface over backup history and restore | The services are `final class` in `data/`, so a feature cannot reach them |

**Four domain ports, for the reason 8A established rather than a fresh one.** `BackupService` and `RestoreService`
are `final class` — in Dart 3 that means neither can be extended *or implemented* outside its own library, so a
test fake is impossible. Add six plugins needing platform channels and §9.1's four-states-per-screen gate is
unreachable by any route. The ports are what make it reachable; the layering they also satisfy is a bonus.

---

## The ports

Four ports, and the fourth is **8A's `DataTransferPort` extended rather than a second port beside it**. It already
existed as the one contract over `BackupService` and `EraseService`; adding SAF export, history and restore keeps
one place where backup lives. Two ports wrapping the same two services would be the kind of split that drifts.

Three things in these contracts are load-bearing rather than descriptive:

**`ReminderPort` cannot express an exact time or a per-item ping.** ARCH_3 §7 forbids both — one digest, inexact
scheduling — and a contract that *cannot say* the wrong thing is better than a comment asking callers not to.

**`ReminderPermission` separates `notRequested` from `denied`.** That distinction is the whole of §7's contextual
rule: a screen that cannot tell "never asked" from "refused" either nags somebody who said no, or never asks.

**`TrashKind` and `AttachmentOwner` are enums where the columns are free text.** `attachments.ownerType` is
deliberately polymorphic, and the purge builds `DELETE FROM` from a table name — a free-text table name reaching a
delete statement is how a typo becomes data loss.

`TrashPort.purge` is **the only hard delete in the codebase**, per ARCH_3 §4.2, which is exactly why it is declared
once on a contract rather than reachable from anywhere.

### `lib/domain/services/attachments/attachment_port.dart`

```dart
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
```

### `lib/domain/services/reminders/reminder_port.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/core/time/date_key.dart';

/// Which kinds of upcoming event a reminder can cover.
///
/// **`NotificationKind` already existed** in `core/enums` and is the converter type on
/// `notification_schedule.kind` — I had written a parallel `NotificationKind` before reading the column, which would
/// have meant two vocabularies for one concept and a mapping between them that could only ever drift.
///
/// `lowStock` is deliberately absent from [reminderKinds]: it is a *state*, not a date. Everything a digest can
/// mention has a day it falls on, and "you are low on rice" has no day — it would fire every morning until
/// somebody shopped.
const List<NotificationKind> reminderKinds = [
  NotificationKind.expiry,
  NotificationKind.serviceDue,
  NotificationKind.recurringDue,
  NotificationKind.warrantyEnd,
];

/// Whether the operating system will let notifications through.
enum ReminderPermission {
  /// Never asked. The state a fresh install is in.
  ///
  /// **Distinct from `denied`, and the distinction is the whole of ARCH_3 §7's contextual rule.** A screen that
  /// cannot tell "not asked" from "refused" either nags somebody who said no, or never asks at all.
  notRequested,

  /// The user allowed them.
  granted,

  /// The user refused. Asking again is the OS's decision, not this app's.
  denied,
}

/// What the user has switched on, and when the digest goes out.
class ReminderSettings {
  /// Creates settings.
  const ReminderSettings({
    required this.enabled,
    required this.digestHour,
    required this.digestMinute,
  });

  /// A fresh install: everything off (ARCH_3 §7).
  ///
  /// **Off is not a cautious default, it is the specified one.** A finance app that starts pushing notifications
  /// before being asked is uninstalled, and `POST_NOTIFICATIONS` requested on first launch is the surest way to
  /// have it denied for good.
  const ReminderSettings.fresh()
      : enabled = const <NotificationKind>{},
        digestHour = 9,
        digestMinute = 0;

  /// Which kinds are switched on.
  final Set<NotificationKind> enabled;

  /// The hour the daily digest is delivered, 0–23, in the device's local zone.
  final int digestHour;

  /// The minute past [digestHour].
  final int digestMinute;

  /// Whether any reminder at all is on.
  bool get anyEnabled => enabled.isNotEmpty;

  /// A copy with the given fields replaced.
  ReminderSettings copyWith({
    Set<NotificationKind>? enabled,
    int? digestHour,
    int? digestMinute,
  }) =>
      ReminderSettings(
        enabled: enabled ?? this.enabled,
        digestHour: digestHour ?? this.digestHour,
        digestMinute: digestMinute ?? this.digestMinute,
      );
}

/// One notification the app has actually scheduled with the OS.
class ScheduledReminder {
  /// Creates a scheduled reminder.
  const ScheduledReminder({
    required this.id,
    required this.kind,
    required this.on,
    required this.androidNotificationId,
  });

  /// The `notification_schedule` row id.
  final String id;

  /// Which kind it is.
  final NotificationKind kind;

  /// The civil date it fires on.
  final DateKey on;

  /// The stable Android id, so it can be cancelled when the underlying record changes (ARCH_3 §7).
  final int androidNotificationId;
}

/// Scheduling, cancelling, and showing what is scheduled (ARCH_3 §7).
///
/// **A port because every line beneath it is a plugin**: `flutter_local_notifications` for delivery, `timezone`
/// for a local-zone digest, `workmanager` for the daily recompute. None runs in a widget test, and §9.1 needs
/// four states per screen.
///
/// **One digest, inexactly scheduled.** ARCH_3 §7 is explicit on both: a stream of individual pings is worse than
/// one sentence a day, and `SCHEDULE_EXACT_ALARM` is restricted on Android 14 with Play asking why it is needed.
/// Nothing in this contract can express an exact time or a per-item ping, which is deliberate — a contract that
/// cannot say the wrong thing is better than a comment asking callers not to.
abstract interface class ReminderPort {
  /// What the user has switched on.
  Stream<ReminderSettings> watchSettings();

  /// Whether the OS will deliver notifications.
  Future<ReminderPermission> permission();

  /// Asks the OS for permission, **contextually**.
  ///
  /// Called the first time a reminder is switched on and never on launch (ARCH_3 §7). Returns the resulting
  /// state, so a caller that was refused can say so instead of silently enabling a switch that does nothing.
  Future<ReminderPermission> requestPermission();

  /// Switches [kind] on or off, scheduling or cancelling as needed.
  Future<Result<ReminderSettings, Failure>> setEnabled({
    required NotificationKind kind,
    required bool enabled,
  });

  /// Moves the daily digest to [hour]:[minute] local time.
  Future<Result<ReminderSettings, Failure>> setDigestTime({
    required int hour,
    required int minute,
  });

  /// What is scheduled right now, soonest first.
  ///
  /// **Shown to the user, which is the point of ARCH_5 §7's row for this table.** A reminder system that cannot
  /// be inspected is one nobody trusts — and the commonest support question about notifications is whether they
  /// are set at all.
  Stream<List<ScheduledReminder>> watchScheduled();

  /// Recomputes upcoming events and reschedules everything.
  ///
  /// Idempotent, because the `workmanager` job calls it daily and a user can call it from the screen. Every
  /// schedule is keyed by its source record, so running twice replaces rather than duplicates.
  Future<Result<int, Failure>> rescheduleAll();

  /// Cancels every scheduled notification, for when the last toggle goes off.
  Future<Result<void, Failure>> cancelAll();
}
```

### `lib/domain/services/trash/trash_port.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// Which table a trashed row came from.
///
/// **Not a table name string.** The purge builds `DELETE FROM` from this, and a free-text table name reaching a
/// delete statement is how a typo becomes data loss — an enum cannot name a table that does not exist.
enum TrashKind {
  /// A deleted transaction.
  transaction,

  /// A deleted inventory item.
  item,

  /// A deleted asset.
  asset,

  /// A deleted shopping list.
  shoppingList,

  /// A deleted recurring template.
  recurringTemplate,

  /// A deleted tag.
  tag,

  /// A deleted payee.
  payee,
}

/// One row in the trash.
class TrashEntry {
  /// Creates an entry.
  const TrashEntry({
    required this.id,
    required this.kind,
    required this.label,
    required this.deletedAtUtcMillis,
    required this.purgeAfterUtcMillis,
    this.detail,
  });

  /// The row's own id, for restoring or purging it.
  final String id;

  /// Which table it belongs to.
  final TrashKind kind;

  /// What the user called it.
  final String label;

  /// A second line — an amount, a date, a quantity — already formatted by the adapter.
  final String? detail;

  /// When it was deleted.
  final int deletedAtUtcMillis;

  /// When it becomes eligible for purge (ARCH_3 §4.2: thirty days).
  final int purgeAfterUtcMillis;
}

/// The trash: what was deleted, restoring it, and the one hard delete in the codebase (ARCH_3 §4.2).
///
/// **`purge` is the only hard delete anywhere, and it exists once.** Every other deletion in Alaya sets
/// `deletedAt`. That is what makes a trash screen possible at all, and it is why this is the single place where
/// a `DELETE FROM` is written — a second one somewhere else would mean a row that could vanish without ever
/// appearing here.
abstract interface class TrashPort {
  /// How long a deleted row is kept.
  static const Duration retention = Duration(days: 30);

  /// Everything currently in the trash, most recently deleted first.
  Stream<List<TrashEntry>> watchAll();

  /// How many rows are in the trash.
  Stream<int> watchCount();

  /// Un-deletes [entry], clearing its `deletedAt`.
  ///
  /// **Restore can fail for a reason worth stating**, not only a technical one: a deleted transaction may name
  /// an account that has since been deleted too, and reviving it would leave a row pointing at nothing. The
  /// implementation reports that rather than writing it.
  Future<Result<void, Failure>> restore(TrashEntry entry);

  /// Hard-deletes [entry] and anything the schema cascades from it.
  Future<Result<void, Failure>> purge(TrashEntry entry);

  /// Hard-deletes everything in the trash.
  ///
  /// Returns how many rows went, so the screen can say what happened rather than only that it happened.
  Future<Result<int, Failure>> purgeAll();

  /// Hard-deletes only what is past [retention].
  ///
  /// Called by the daily `workmanager` job, never by a button. Thirty-day retention that nothing enforces is a
  /// promise the app does not keep — and a trash that grows forever is a backup that grows forever with it.
  Future<Result<int, Failure>> purgeExpired();
}
```

### `lib/domain/services/backup/data_transfer_port.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// What an export produced.
///
/// Moved here from `data/` in 8A so a feature can name it. A record of four plain values with no drift
/// or Flutter dependency, so `domain/` is a legal home for it on Law L12's own terms.
typedef BackupArtefact = ({String path, int sizeBytes, bool isZipped, String fileName});

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
```

## The SAF platform channel — replacing `file_picker`

**`file_picker` is removed, and ARCH_1 §7.4 predicted this exactly.** Its own worked example is this package:

> `file_picker: any` silently resolved to **3.0.4, from 2020**, whose `android/build.gradle` calls `jcenter()` — a
> repository shut down in 2021 and a method Gradle no longer has. `pub get` reported success; the failure surfaced
> only at `assembleDebug`.

`flutter pub add file_picker` resolved to **3.0.4** anyway, because §7.3's analyzer/test cap walks it backwards —
the same cap that makes `riverpod_generator` unresolvable. So `pub get` succeeds, the analyzer is clean, the tests
pass, and the Android build dies. I issued that `pub add` without checking §7.4 first; that is my error, and the
architecture had already written down the answer:

> Evaluate at 4C whether a small SAF platform channel is preferable to the whole plugin.

It is. Three files replace it, and the trade is strongly in favour: `file_picker` also dragged in `dbus`, `ffi`,
`win32`, `web` and `flutter_web_plugins` — desktop and web surface an Android-only app never uses.

### Why this has no backlash elsewhere

**No new pub dependency, and five transitive ones removed.**

**`MainActivity`'s base class is untouched.** `SafPlugin` registers through the v2 embedding's `ActivityAware`
contract, so it works against whatever the activity already extends. That matters because `local_auth` would
eventually want `FlutterFragmentActivity`, and that is a separate decision with its own dependency consequences —
nothing here forecloses it.

**No manifest change, and no permission.** That is the point of SAF: the user chooses the document in the system's
own sheet and the grant is scoped to that choice. `allowBackup="false"` and `dataExtractionRules` are untouched.

**Nothing else in the project imported `file_picker`** — it arrived with this phase and leaves with this change.

**The package is `com.wildewulf.alaya`**, confirmed against the existing `MainActivity.kt`, which declared no
`configureFlutterEngine` override — so this is a clean replacement rather than a merge. `SafPlugin.kt` sits in its
own `com.alaya.saf` package and needs no adjustment.

### Two design points

**`openDocument` returns a cache copy, not the URI.** `RestoreService` runs `ATTACH DATABASE` on a filesystem path
and SQLite cannot open a `content://` URI — and the read grant expires with the activity result, so a URI held past
it would be unreadable exactly when the restore needed it.

**`createDocument` takes the source path and does the write itself.** One round trip rather than two, so Dart never
holds a URI it has no way to use. Export therefore stages to the cache with `VACUUM INTO` first, then hands that
file to the sheet.

`DataTransferPort` gains `pickBackupFile()`, because a feature may not import `data/` and the chooser lives there —
so choosing a file is one more thing the contract answers, alongside reading the chosen file's schema version.

### `android/app/src/main/kotlin/com/alaya/saf/SafPlugin.kt`

```kotlin
package com.alaya.saf

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File

/**
 * A minimal Storage Access Framework bridge: open a document, create a document, write to one.
 *
 * Written because `file_picker` cannot be used in this project. ARCH_1 §7.4 records why: the resolvable
 * version here is 3.0.4 from 2020, whose `android/build.gradle` calls `jcenter()` — shut down in 2021 —
 * so `pub get` succeeds and `assembleDebug` fails. ARCH_1 §7 anticipated this and said to "evaluate
 * whether a small SAF platform channel is preferable to the whole plugin". It is: this file replaces a
 * dependency that also dragged in `dbus`, `ffi`, `win32`, `web` and `flutter_web_plugins` — desktop and
 * web surface an Android-only app never uses.
 *
 * **No permissions are declared or needed.** That is the point of SAF: the user chooses the document in
 * the system's own picker, and the grant is scoped to what they chose. There is no
 * `WRITE_EXTERNAL_STORAGE` and no `MANAGE_EXTERNAL_STORAGE` anywhere in this app (ARCH_3 §3.3).
 *
 * Registered from `MainActivity.configureFlutterEngine`, using the v2 embedding's `ActivityAware`
 * contract, so the host activity's base class is untouched.
 */
class SafPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {

    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private var pending: MethodChannel.Result? = null
    private var pendingSourcePath: String? = null

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: MethodChannel.Result) {
        val host = activity
        if (host == null) {
            result.error("no_activity", "The picker needs a foreground activity.", null)
            return
        }
        when (call.method) {
            // Opens a document and copies it into the app's cache, returning that path.
            //
            // **A copy, not the URI.** `RestoreService` runs `ATTACH DATABASE` on a filesystem path, and
            // SQLite cannot open a `content://` URI. The grant is also scoped to this activity result, so a
            // URI held past it would be unreadable exactly when the restore needed it.
            "openDocument" -> {
                if (!claim(result)) return
                @Suppress("UNCHECKED_CAST")
                val types = (call.argument<List<String>>("mimeTypes") ?: listOf("*/*")).toTypedArray()
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = if (types.size == 1) types[0] else "*/*"
                    if (types.size > 1) putExtra(Intent.EXTRA_MIME_TYPES, types)
                }
                host.startActivityForResult(intent, REQUEST_OPEN)
            }

            // Raises the create-document sheet and writes an existing file into whatever the user chose.
            //
            // One round trip rather than two: the source path is held until the result arrives, so Dart
            // never has to hold a URI it cannot use.
            "createDocument" -> {
                if (!claim(result)) return
                pendingSourcePath = call.argument<String>("sourcePath")
                if (pendingSourcePath == null) {
                    finish(null, "no_source", "No file was given to save.")
                    return
                }
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = call.argument<String>("mimeType") ?: "application/octet-stream"
                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("fileName") ?: "alaya.db")
                }
                host.startActivityForResult(intent, REQUEST_CREATE)
            }

            else -> result.notImplemented()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_OPEN && requestCode != REQUEST_CREATE) return false
        val uri: Uri? = if (resultCode == Activity.RESULT_OK) data?.data else null
        // Dismissing the sheet returns null rather than an error: cancelling is the commonest outcome of a
        // file chooser, and reporting it as a failure would put a red message under a deliberate action.
        if (uri == null) {
            finish(null, null, null)
            return true
        }
        return when (requestCode) {
            REQUEST_OPEN -> { copyIn(uri); true }
            else -> { copyOut(uri); true }
        }
    }

    private fun copyIn(uri: Uri) {
        val host = activity ?: return finish(null, "no_activity", "The activity went away.")
        try {
            val name = "saf_${System.currentTimeMillis()}"
            val target = File(host.cacheDir, name)
            host.contentResolver.openInputStream(uri).use { input ->
                if (input == null) return finish(null, "unreadable", "That file could not be read.")
                target.outputStream().use { output -> input.copyTo(output) }
            }
            finish(target.absolutePath, null, null)
        } catch (error: Exception) {
            finish(null, "copy_failed", error.message)
        }
    }

    private fun copyOut(uri: Uri) {
        val host = activity ?: return finish(null, "no_activity", "The activity went away.")
        val source = pendingSourcePath
        if (source == null) return finish(null, "no_source", "No file was given to save.")
        try {
            host.contentResolver.openOutputStream(uri).use { output ->
                if (output == null) return finish(null, "unwritable", "That location could not be written to.")
                File(source).inputStream().use { input -> input.copyTo(output) }
            }
            finish(uri.toString(), null, null)
        } catch (error: Exception) {
            finish(null, "write_failed", error.message)
        }
    }

    /** Takes the pending slot, refusing a second concurrent picker. */
    private fun claim(result: MethodChannel.Result): Boolean {
        if (pending != null) {
            result.error("busy", "A file chooser is already open.", null)
            return false
        }
        pending = result
        return true
    }

    private fun finish(value: String?, code: String?, message: String?) {
        val result = pending
        pending = null
        pendingSourcePath = null
        if (result == null) return
        if (code != null) result.error(code, message, null) else result.success(value)
    }

    companion object {
        /** The channel name, matched by `saf_channel.dart`. */
        const val CHANNEL = "com.alaya/saf"
        private const val REQUEST_OPEN = 0x5AF0
        private const val REQUEST_CREATE = 0x5AF1
    }
}
```

### `android/app/src/main/kotlin/com/wildewulf/alaya/MainActivity.kt`

```kotlin
package com.wildewulf.alaya

import com.alaya.saf.SafPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * The host activity.
 *
 * **The base class is unchanged from the original.** `SafPlugin` registers through the v2 embedding's
 * `ActivityAware` contract, so it works against `FlutterActivity` as it stands — which matters because
 * `local_auth` would eventually want `FlutterFragmentActivity`, and that is a separate decision with its
 * own dependency consequences. Nothing here forecloses it.
 *
 * The only addition is `configureFlutterEngine`, which the original did not override.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(SafPlugin())
    }
}
```

### `lib/data/platform/saf_channel.dart`

```dart
import 'dart:async';

import 'package:flutter/services.dart';

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// The Dart side of the Storage Access Framework bridge.
///
/// **This replaces `file_picker`, which cannot be used in this project.** ARCH_1 §7.4 documents why: the
/// resolvable version is 3.0.4 from 2020, whose `android/build.gradle` calls `jcenter()` — shut down in
/// 2021 — so `pub get` succeeds and `assembleDebug` fails. §7 anticipated this and recommended "a small
/// SAF platform channel" instead; this is it, and it also removes five transitive desktop and web
/// dependencies an Android-only app never used.
///
/// **No permission is declared anywhere.** SAF's whole point is that the user picks the document in the
/// system's own sheet and the grant is scoped to that choice — no `WRITE_EXTERNAL_STORAGE`, no
/// `MANAGE_EXTERNAL_STORAGE` (ARCH_3 §3.3).
///
/// Both calls return **null when the sheet was dismissed**, which is not a failure: cancelling is the
/// commonest thing to do with a file chooser.
final class SafChannel {
  /// Creates the bridge. [channel] is injectable so a test can answer without a platform.
  const SafChannel({MethodChannel channel = const MethodChannel(channelName)})
      : _channel = channel;

  final MethodChannel _channel;

  /// The channel name, matched by `SafPlugin.kt`.
  static const String channelName = 'com.alaya/saf';

  /// Opens a document and returns a **cache copy's absolute path**.
  ///
  /// A copy rather than the URI, because `RestoreService` runs `ATTACH DATABASE` on a filesystem path and
  /// SQLite cannot open a `content://` URI — and because the read grant expires with the activity result,
  /// so a URI kept past it would be unreadable exactly when the restore needed it.
  Future<Result<String?, Failure>> openDocument({
    List<String> mimeTypes = const ['*/*'],
  }) async {
    try {
      final path = await _channel.invokeMethod<String>(
        'openDocument',
        <String, Object?>{'mimeTypes': mimeTypes},
      );
      return Result.ok(path);
    } on PlatformException catch (error) {
      return Result.failure(
        UnexpectedFailure(error.message ?? 'That file could not be opened.', cause: error),
      );
    } on MissingPluginException catch (error) {
      // Says which half is missing. A generic failure here sends somebody looking at their file manager
      // when the answer is that `SafPlugin` was never registered in `MainActivity`.
      return Result.failure(
        UnexpectedFailure('File access is not available in this build.', cause: error),
      );
    }
  }

  /// Raises the create-document sheet and writes [sourcePath] into whatever the user chose.
  ///
  /// One round trip rather than two, so Dart never holds a URI it has no way to use.
  Future<Result<String?, Failure>> createDocument({
    required String sourcePath,
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) async {
    try {
      final uri = await _channel.invokeMethod<String>(
        'createDocument',
        <String, Object?>{
          'sourcePath': sourcePath,
          'fileName': fileName,
          'mimeType': mimeType,
        },
      );
      return Result.ok(uri);
    } on PlatformException catch (error) {
      return Result.failure(
        UnexpectedFailure(error.message ?? 'That file could not be saved.', cause: error),
      );
    } on MissingPluginException catch (error) {
      return Result.failure(
        UnexpectedFailure('File access is not available in this build.', cause: error),
      );
    }
  }
}
```

## Attachments and trash, on disk

**Both plugins are confined to `attachment_store.dart`.** `file_picker` and `path_provider` are the phase's file
surface, and 8A's experience with `local_auth` — two rejected signatures before the third compiled — says to
expect the first build to disagree with at least one call here. If it does, one file changes.

**Attachment files live inside the app's own directory, never in shared storage** (ARCH_3 §3.3). That is what
makes SAF the only outward path and `WRITE_EXTERNAL_STORAGE` unnecessary: Alaya writes where it already has the
right to write, and the user reaches it through the system's own sheets.

**Picked files are copied, not referenced.** The chosen file may sit in a cache the OS reclaims, or behind a
content URI that expires with its permission grant — a row pointing at either is a broken thumbnail tomorrow.

**Deleting removes the file first and the row second.** A failure between the two leaves an orphan file rather
than a row pointing at nothing: a stray file wastes space, while a broken row renders as a permanently broken
thumbnail. Only one of those is recoverable.

`TrashAdapter._hardDelete` is **the only hard delete in the codebase** (ARCH_3 §4.2). All three purge paths — one
row, everything, only the expired — arrive there, and `_deleteRow` beneath it is a `switch` over seven tables with
no logic and no other caller. It runs under `defer_foreign_keys`, because purging a transaction takes its lines
with it and `foreign_keys = OFF` is silently ignored inside a transaction — the trap 8A's `EraseService`
documents.

**Seven tables, not the twenty-two that have `deletedAt`.** A trash listing `currency_rates` and `analytics_cache`
would bury the transaction somebody is looking for under machinery they never deleted.

Two corrections while writing these. The `attachments` table has **no `caption` column** — my entity invented one,
and reading the schema removed it. And `singleOrNull` lives in `package:collection`, which this project does not
depend on; an explicit emptiness check costs one line and no package.

### `lib/data/attachments/attachment_store.dart`

```dart
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
  })  : _db = database,
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
    final root = Directory('${documents.path}${Platform.pathSeparator}$directoryName');
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
  }) =>
      watchFor(owner: owner, ownerId: ownerId).map((rows) => rows.length);

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
          BusinessRuleFailure('That file is no longer there.', rule: 'attachmentMissing'),
        );
      }

      final id = _uids.generate();
      final extension = source.contains('.') ? source.split('.').last.toLowerCase() : 'bin';
      final relative = '$id.$extension';
      final root = await _root();
      // **Copied, not referenced.** The picked file may live in a cache the OS reclaims, or behind a content URI
      // that expires with the permission grant — a row pointing at either is a broken thumbnail tomorrow.
      final stored = await file.copy('${root.path}${Platform.pathSeparator}$relative');
      final size = await stored.length();
      final now = _clock.nowUtcMillis();

      await _db.into(_db.attachments).insert(
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
      return Result.ok('${root.path}${Platform.pathSeparator}${attachment.relativePath}');
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
        BusinessRuleFailure('The file is missing from this device.', rule: 'attachmentFileGone'),
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
      await (_db.update(_db.attachments)..where((row) => row.id.equals(attachment.id)))
          .write(AttachmentsCompanion(deletedAt: Value(_clock.nowUtcMillis())));
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That attachment could not be removed.', cause: error),
      );
    }
  }

  @override
  Future<Result<List<String>, Failure>> allFilePaths() async {
    try {
      final rows = await (_db.select(_db.attachments)
            ..where((row) => row.deletedAt.isNull()))
          .get();
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
```

### `lib/data/trash/trash_adapter.dart`

```dart
import 'dart:async';

import 'package:drift/drift.dart';

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/services/trash/trash_port.dart';

/// The production [TrashPort], and **the only place in this codebase that hard-deletes a row**.
///
/// ARCH_3 §4.2 makes purge the single hard delete, and [_hardDelete] is the single function it lives in. Every
/// other deletion in Alaya sets `deletedAt` — that is what makes a trash screen possible at all, and it is why a
/// second `DELETE FROM` anywhere else would be a row that could vanish without ever appearing here.
///
/// **Seven tables, not twenty-two.** Every table in the schema carries `deletedAt`, but a trash listing
/// `currency_rates` and `analytics_cache` would bury the transaction somebody is looking for under machinery they
/// never deleted. The seven here are the ones a person deletes on purpose.
final class TrashAdapter implements TrashPort {
  /// Creates the adapter.
  const TrashAdapter({required AlayaDatabase database, required Clock clock})
      : _db = database,
        _clock = clock;

  final AlayaDatabase _db;
  final Clock _clock;

  @override
  Stream<List<TrashEntry>> watchAll() {
    // One query per table, combined — rather than a UNION, which would need every table to agree on a column
    // list they do not have. Seven small indexed reads on `deleted_at IS NOT NULL` beat one query that has to
    // pretend a transaction and a tag are the same shape.
    final streams = <Stream<List<TrashEntry>>>[
      _watch(TrashKind.transaction),
      _watch(TrashKind.item),
      _watch(TrashKind.asset),
      _watch(TrashKind.shoppingList),
      _watch(TrashKind.recurringTemplate),
      _watch(TrashKind.tag),
      _watch(TrashKind.payee),
    ];
    return _combine(streams).map((entries) {
      final sorted = [...entries]
        ..sort((a, b) => b.deletedAtUtcMillis.compareTo(a.deletedAtUtcMillis));
      return sorted;
    });
  }

  @override
  Stream<int> watchCount() => watchAll().map((entries) => entries.length);

  Stream<List<TrashEntry>> _watch(TrashKind kind) => switch (kind) {
        TrashKind.transaction => (_db.select(_db.transactions)
              ..where((row) => row.deletedAt.isNotNull()))
            .watch()
            .map((rows) => [
                  for (final row in rows)
                    _entry(
                      id: row.id,
                      kind: kind,
                      // A transaction has no name, so it is identified by what it was: the subtype it was filed
                      // under. The amount belongs on the row too, but formatting money is the screen's job — an
                      // adapter that reached for `AmountText` would be a data file importing Flutter.
                      label: row.subtype.name,
                      deletedAt: row.deletedAt!,
                    ),
                ]),
        TrashKind.item => (_db.select(_db.items)..where((row) => row.deletedAt.isNotNull()))
            .watch()
            .map((rows) => [
                  for (final row in rows)
                    _entry(id: row.id, kind: kind, label: row.name, deletedAt: row.deletedAt!),
                ]),
        TrashKind.asset => (_db.select(_db.assets)..where((row) => row.deletedAt.isNotNull()))
            .watch()
            .map((rows) => [
                  for (final row in rows)
                    _entry(id: row.id, kind: kind, label: row.name, deletedAt: row.deletedAt!),
                ]),
        TrashKind.shoppingList => (_db.select(_db.shoppingLists)
              ..where((row) => row.deletedAt.isNotNull()))
            .watch()
            .map((rows) => [
                  for (final row in rows)
                    _entry(id: row.id, kind: kind, label: row.name, deletedAt: row.deletedAt!),
                ]),
        TrashKind.recurringTemplate => (_db.select(_db.recurringTemplates)
              ..where((row) => row.deletedAt.isNotNull()))
            .watch()
            .map((rows) => [
                  for (final row in rows)
                    _entry(id: row.id, kind: kind, label: row.name, deletedAt: row.deletedAt!),
                ]),
        TrashKind.tag => (_db.select(_db.tags)..where((row) => row.deletedAt.isNotNull()))
            .watch()
            .map((rows) => [
                  for (final row in rows)
                    _entry(id: row.id, kind: kind, label: row.name, deletedAt: row.deletedAt!),
                ]),
        TrashKind.payee => (_db.select(_db.payees)..where((row) => row.deletedAt.isNotNull()))
            .watch()
            .map((rows) => [
                  for (final row in rows)
                    _entry(id: row.id, kind: kind, label: row.name, deletedAt: row.deletedAt!),
                ]),
      };

  TrashEntry _entry({
    required String id,
    required TrashKind kind,
    required String label,
    required int deletedAt,
  }) =>
      TrashEntry(
        id: id,
        kind: kind,
        label: label,
        deletedAtUtcMillis: deletedAt,
        purgeAfterUtcMillis: deletedAt + TrashPort.retention.inMilliseconds,
      );

  @override
  Future<Result<void, Failure>> restore(TrashEntry entry) async {
    try {
      final now = _clock.nowUtcMillis();
      // Clearing `deletedAt` is the whole of a restore, and `updatedAt` moves with it so a later merge treats the
      // revival as the newer write (ARCH_3 §3.2's last-write-wins).
      final changed = await _updateDeletedAt(entry, deletedAt: null, updatedAt: now);
      if (changed == 0) {
        return const Result.failure(
          BusinessRuleFailure('That has already gone.', rule: 'trashEntryMissing'),
        );
      }
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That could not be restored.', cause: error),
      );
    }
  }

  @override
  Future<Result<void, Failure>> purge(TrashEntry entry) async {
    final result = await _hardDelete([entry]);
    return result.fold(
      (_) => const Result.ok(null),
      Result<void, Failure>.failure,
    );
  }

  @override
  Future<Result<int, Failure>> purgeAll() async {
    final entries = await watchAll().first;
    return _hardDelete(entries);
  }

  @override
  Future<Result<int, Failure>> purgeExpired() async {
    final now = _clock.nowUtcMillis();
    final entries = await watchAll().first;
    final expired = [
      for (final entry in entries) if (entry.purgeAfterUtcMillis <= now) entry,
    ];
    return _hardDelete(expired);
  }

  /// **The only hard delete in this codebase** (ARCH_3 §4.2).
  ///
  /// Every purge path arrives here — one row, all rows, or only the expired ones — so there is exactly one place
  /// where data leaves for good, and exactly one place to read when asking whether it can. `_deleteRow` beneath
  /// it is a `switch` over seven tables with no logic of its own and no other caller: the decision is here, the
  /// dispatch is there, and nothing else in `lib/` issues a `DELETE`.
  ///
  /// Runs in a transaction with `defer_foreign_keys`, because purging a transaction takes its lines with it and
  /// SQLite checks each statement as it goes otherwise. `foreign_keys = OFF` would be silently ignored inside a
  /// transaction — the trap 8A's `EraseService` documents.
  Future<Result<int, Failure>> _hardDelete(List<TrashEntry> entries) async {
    if (entries.isEmpty) return const Result.ok(0);
    try {
      var deleted = 0;
      await _db.transaction(() async {
        await _db.customStatement('PRAGMA defer_foreign_keys = ON');
        for (final entry in entries) {
          deleted += await _deleteRow(entry);
        }
      });
      return Result.ok(deleted);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That could not be deleted.', cause: error),
      );
    }
  }

  Future<int> _deleteRow(TrashEntry entry) => switch (entry.kind) {
        TrashKind.transaction =>
          (_db.delete(_db.transactions)..where((row) => row.id.equals(entry.id))).go(),
        TrashKind.item => (_db.delete(_db.items)..where((row) => row.id.equals(entry.id))).go(),
        TrashKind.asset => (_db.delete(_db.assets)..where((row) => row.id.equals(entry.id))).go(),
        TrashKind.shoppingList =>
          (_db.delete(_db.shoppingLists)..where((row) => row.id.equals(entry.id))).go(),
        TrashKind.recurringTemplate =>
          (_db.delete(_db.recurringTemplates)..where((row) => row.id.equals(entry.id))).go(),
        TrashKind.tag => (_db.delete(_db.tags)..where((row) => row.id.equals(entry.id))).go(),
        TrashKind.payee => (_db.delete(_db.payees)..where((row) => row.id.equals(entry.id))).go(),
      };

  Future<int> _updateDeletedAt(
    TrashEntry entry, {
    required int? deletedAt,
    required int updatedAt,
  }) =>
      switch (entry.kind) {
        TrashKind.transaction =>
          (_db.update(_db.transactions)..where((row) => row.id.equals(entry.id))).write(
            TransactionsCompanion(deletedAt: Value(deletedAt), updatedAt: Value(updatedAt)),
          ),
        TrashKind.item => (_db.update(_db.items)..where((row) => row.id.equals(entry.id)))
            .write(ItemsCompanion(deletedAt: Value(deletedAt), updatedAt: Value(updatedAt))),
        TrashKind.asset => (_db.update(_db.assets)..where((row) => row.id.equals(entry.id)))
            .write(AssetsCompanion(deletedAt: Value(deletedAt), updatedAt: Value(updatedAt))),
        TrashKind.shoppingList =>
          (_db.update(_db.shoppingLists)..where((row) => row.id.equals(entry.id))).write(
            ShoppingListsCompanion(deletedAt: Value(deletedAt), updatedAt: Value(updatedAt)),
          ),
        TrashKind.recurringTemplate =>
          (_db.update(_db.recurringTemplates)..where((row) => row.id.equals(entry.id))).write(
            RecurringTemplatesCompanion(deletedAt: Value(deletedAt), updatedAt: Value(updatedAt)),
          ),
        TrashKind.tag => (_db.update(_db.tags)..where((row) => row.id.equals(entry.id)))
            .write(TagsCompanion(deletedAt: Value(deletedAt), updatedAt: Value(updatedAt))),
        TrashKind.payee => (_db.update(_db.payees)..where((row) => row.id.equals(entry.id)))
            .write(PayeesCompanion(deletedAt: Value(deletedAt), updatedAt: Value(updatedAt))),
      };

  /// Merges several list streams into one, re-emitting whenever any of them changes.
  ///
  /// Hand-rolled rather than `rxdart`'s `combineLatest`: the project has no reactive-extensions dependency and
  /// adding one so seven streams can be zipped would be a package for a page of code.
  Stream<List<TrashEntry>> _combine(List<Stream<List<TrashEntry>>> streams) {
    final latest = List<List<TrashEntry>>.filled(streams.length, const []);
    final controller = StreamController<List<TrashEntry>>();
    final subscriptions = <StreamSubscription<List<TrashEntry>>>[];

    controller.onListen = () {
      for (var i = 0; i < streams.length; i++) {
        final index = i;
        subscriptions.add(
          streams[index].listen(
            (rows) {
              latest[index] = rows;
              controller.add([for (final list in latest) ...list]);
            },
            onError: controller.addError,
          ),
        );
      }
    };
    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    };
    return controller.stream;
  }
}
```

## Reminders — one digest, inexactly scheduled

**The largest unverifiable surface in the phase, in one file.** `flutter_local_notifications` and `timezone` both
need a platform channel, so neither runs in a widget test — which is the whole reason `ReminderPort` exists.
`zonedSchedule`, `AndroidScheduleMode` and `requestNotificationsPermission` have each moved between major versions
(ARCH_4 R22), and 8A's `local_auth` took two wrong guesses before compiling. Expect at least one here; it will cost
this file and nothing else.

Every one of ARCH_3 §7's constraints is structural rather than commented:

**One notification, not a stream of pings.** Every enabled kind folds into a single sentence — *"3 items expire, 1
bill due this week"* — delivered once daily at a chosen time. Nothing in the contract or the implementation can
express a per-item ping.

**`AndroidScheduleMode.inexactAllowWhileIdle`, never `exact`.** Android 14 restricts `SCHEDULE_EXACT_ALARM` and
Play asks why an app needs it. A digest arriving at 9:07 has lost nothing.

**Nothing to say means nothing is sent.** A daily notification reading *"0 items expire this week"* is how a
reminder becomes something people switch off, so an empty count cancels rather than delivers.

**`tz.local`, not UTC.** A digest is a wall-clock promise: somebody who asked for 9am wants 9am where they are,
and still wants 9am after they fly.

**The digest's Android id is a constant**, so the daily `workmanager` job can reschedule as often as it likes
without stacking duplicates — which is what §7 means by the table guaranteeing idempotency.

### Four corrections, all from reading the schema rather than the prose

**`NotificationKind` already existed** in `core/enums/ops_enums.dart`, and is the converter type on
`notification_schedule.kind`. I had written a parallel `ReminderKind` — two vocabularies for one concept, with a
mapping between them that could only drift. The port uses the real enum now, with a `reminderKinds` list naming
the four that belong in a digest.

**`lowStock` is excluded, deliberately.** It is a *state*, not a date: everything a digest mentions has a day it
falls on, and "you are low on rice" would fire every morning until somebody shopped.

**The table has no `title` and no `scheduledDateKey` columns.** `ScheduledReminder` dropped its title — which is
better for Law U5 anyway, since the screen now localises from `kind` instead of storing English in a row — and the
date is derived from `scheduledAtUtcMillis`.

**`replaceForRef` takes one `replacement:` companion, not a `schedules:` list**, and the companion needs `kind` and
`status`, both of which I had omitted.

One deviation from Law U5 that cannot be avoided and is recorded rather than hidden: **the digest's text is
assembled in Dart, not the ARB.** A notification is built by a `workmanager` isolate with no `BuildContext` and no
`AlayaStrings`. The alternative — passing pre-localised text into a background job that may run days later, in a
locale the user has since changed — would be worse than plain English.

### `lib/data/reminders/local_notification_scheduler.dart`

```dart
import 'package:drift/drift.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/notification_schedule_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';
import 'package:alaya/domain/services/reminders/reminder_port.dart';

/// The production [ReminderPort]: one daily digest, scheduled inexactly, in the device's own timezone.
///
/// **The only file in this phase that imports `flutter_local_notifications` or `timezone`.** Both need a platform
/// channel, so neither runs in a widget test — which is the whole reason `ReminderPort` exists. This is also the
/// largest surface in the phase that could not be compiled against (ARCH_4 R22): `zonedSchedule`,
/// `AndroidScheduleMode`, and `requestNotificationsPermission` have each moved between major versions of the
/// plugin. 8A's `local_auth` took two wrong guesses before compiling; expect at least one here, and expect it to
/// cost this file and nothing else.
///
/// **One notification, not a stream of pings** (ARCH_3 §7). Every enabled kind is folded into a single sentence —
/// *"3 items expire this week, 1 bill due tomorrow"* — delivered once a day at a time the user picked. The
/// contract cannot express a per-item ping, and neither can this.
///
/// **Inexact, always.** `AndroidScheduleMode.inexactAllowWhileIdle` and never `exactAllowWhileIdle`: Android 14
/// restricts `SCHEDULE_EXACT_ALARM` and Play asks why an app needs it. A digest that arrives at 9:07 instead of
/// 9:00 has lost nothing.
final class LocalNotificationScheduler implements ReminderPort {
  /// Creates the scheduler.
  LocalNotificationScheduler({
    required FlutterLocalNotificationsPlugin plugin,
    required AlayaDatabase database,
    required NotificationScheduleDao scheduleDao,
    required CalendarAggregator calendar,
    required SettingsRepository settings,
    required UidGenerator uids,
    required Clock clock,
  })  : _plugin = plugin,
        _db = database,
        _scheduleDao = scheduleDao,
        _calendar = calendar,
        _settings = settings,
        _uids = uids,
        _clock = clock;

  final FlutterLocalNotificationsPlugin _plugin;
  final AlayaDatabase _db;
  final NotificationScheduleDao _scheduleDao;
  final CalendarAggregator _calendar;
  final SettingsRepository _settings;
  final UidGenerator _uids;
  final Clock _clock;

  /// The `app_settings` key holding which reminder kinds are on.
  ///
  /// Stored as a comma-separated list of names rather than one key per kind: adding a fifth kind then needs no
  /// migration, and an unknown name in the list is ignored rather than fatal.
  static const String enabledKindsKey = 'reminders.enabledKinds';

  /// The `app_settings` key holding the digest time as `HH:mm`.
  static const String digestTimeKey = 'reminders.digestTime';

  /// The Android notification id the daily digest always uses.
  ///
  /// **Fixed, so rescheduling replaces rather than accumulates.** Every other id comes from
  /// `NotificationScheduleDao.nextAndroidNotificationId`; the digest is the one notification that is always
  /// exactly one, so it gets a constant and cancelling it needs no lookup.
  static const int digestNotificationId = 1;

  /// How far ahead the digest looks.
  ///
  /// A week, because that is the horizon a sentence can usefully summarise. A month's worth of counts reads as a
  /// backlog rather than a nudge, and a day's is too late to act on an expiry.
  static const Duration horizon = Duration(days: 7);

  /// The reference type recorded against the digest's `notification_schedule` row.
  static const String digestRefType = 'digest';

  bool _timezonesReady = false;

  Future<void> _ensureTimezones() async {
    if (_timezonesReady) return;
    tz_data.initializeTimeZones();
    _timezonesReady = true;
  }

  @override
  Stream<ReminderSettings> watchSettings() =>
      _db.select(_db.appSettings).watch().asyncMap((_) => _readSettings());

  Future<ReminderSettings> _readSettings() async {
    final stored = await _settings.readValue(enabledKindsKey);
    final time = await _settings.readValue(digestTimeKey);
    final enabled = <NotificationKind>{};
    for (final name in (stored ?? '').split(',')) {
      for (final kind in reminderKinds) {
        if (kind.name == name.trim()) enabled.add(kind);
      }
    }
    final parts = (time ?? '09:00').split(':');
    return ReminderSettings(
      enabled: enabled,
      digestHour: int.tryParse(parts.first) ?? 9,
      digestMinute: parts.length > 1 ? int.tryParse(parts.last) ?? 0 : 0,
    );
  }

  @override
  Future<ReminderPermission> permission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return ReminderPermission.denied;
    final enabled = await android.areNotificationsEnabled();
    if (enabled ?? false) return ReminderPermission.granted;
    // **`notRequested` unless something has been asked for.** The OS cannot tell us whether we have asked, so the
    // app records it: a stored digest time means a toggle was once turned on, which means the prompt has been
    // shown. Without this the screen would nag somebody who deliberately said no.
    final asked = await _settings.readValue(digestTimeKey);
    return asked == null ? ReminderPermission.notRequested : ReminderPermission.denied;
  }

  @override
  Future<ReminderPermission> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return ReminderPermission.denied;
    final granted = await android.requestNotificationsPermission();
    return (granted ?? false) ? ReminderPermission.granted : ReminderPermission.denied;
  }

  @override
  Future<Result<ReminderSettings, Failure>> setEnabled({
    required NotificationKind kind,
    required bool enabled,
  }) async {
    try {
      final current = await _readSettings();
      final next = {...current.enabled};
      enabled ? next.add(kind) : next.remove(kind);
      await _settings.writeValue(
        key: enabledKindsKey,
        value: next.map((kind) => kind.name).join(','),
        valueType: 'string',
      );
      final settings = current.copyWith(enabled: next);
      // Turning the last one off cancels everything rather than leaving a digest that says nothing.
      next.isEmpty ? await cancelAll() : await _scheduleDigest(settings);
      return Result.ok(settings);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That reminder could not be changed.', cause: error),
      );
    }
  }

  @override
  Future<Result<ReminderSettings, Failure>> setDigestTime({
    required int hour,
    required int minute,
  }) async {
    try {
      final two = (int value) => value < 10 ? '0$value' : '$value';
      await _settings.writeValue(
        key: digestTimeKey,
        value: '${two(hour)}:${two(minute)}',
        valueType: 'string',
      );
      final settings = (await _readSettings()).copyWith(digestHour: hour, digestMinute: minute);
      if (settings.anyEnabled) await _scheduleDigest(settings);
      return Result.ok(settings);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The reminder time could not be changed.', cause: error),
      );
    }
  }

  @override
  Stream<List<ScheduledReminder>> watchScheduled() =>
      _scheduleDao.watchScheduled().map((rows) => [
            for (final row in rows)
              ScheduledReminder(
                id: row.id,
                // The row's own `kind` column, converted by drift — not derived from `refType`, which I had
                // written before reading the table. Two sources for one fact is one too many.
                kind: row.kind,
                on: DateKey.fromDateTime(
                  DateTime.fromMillisecondsSinceEpoch(row.scheduledAtUtcMillis, isUtc: true),
                ),
                androidNotificationId: row.androidNotificationId,
              ),
          ]);

  @override
  Future<Result<int, Failure>> rescheduleAll() async {
    try {
      final settings = await _readSettings();
      if (!settings.anyEnabled) {
        await cancelAll();
        return const Result.ok(0);
      }
      final count = await _scheduleDigest(settings);
      return Result.ok(count);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('Reminders could not be rescheduled.', cause: error),
      );
    }
  }

  @override
  Future<Result<void, Failure>> cancelAll() async {
    try {
      // `cancel` is named-only on the installed plugin, like `zonedSchedule` — this version takes nothing
      // positionally anywhere on its surface.
      await _plugin.cancel(id: digestNotificationId);
      await _scheduleDao.cancelAll(nowUtcMillis: _clock.nowUtcMillis());
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('Reminders could not be cancelled.', cause: error),
      );
    }
  }

  /// Counts what is coming, writes one schedule row, and books one notification.
  ///
  /// Idempotent by construction: the digest's Android id is a constant and its `notification_schedule` row is
  /// replaced by `refType`/`refId`, so the daily `workmanager` job can call this as often as it likes without
  /// stacking duplicates — which is exactly what ARCH_3 §7 means by the table guaranteeing idempotency.
  Future<int> _scheduleDigest(ReminderSettings settings) async {
    await _ensureTimezones();
    final today = _clock.today();
    final events = await _calendar
        .watchRange(from: today, to: today.addDays(horizon.inDays), today: today)
        .first;

    final counts = <NotificationKind, int>{};
    for (final event in events) {
      final kind = _kindForEvent(event.type);
      if (kind == null || !settings.enabled.contains(kind)) continue;
      counts[kind] = (counts[kind] ?? 0) + 1;
    }
    if (counts.isEmpty) {
      // **Nothing to say means nothing is sent.** A daily notification reading "0 items expire this week" is how
      // a reminder becomes something people switch off.
      await _plugin.cancel(id: digestNotificationId);
      await _scheduleDao.cancelForRef(
        refType: digestRefType,
        refId: digestRefType,
        nowUtcMillis: _clock.nowUtcMillis(),
      );
      return 0;
    }

    final when = _nextOccurrence(settings.digestHour, settings.digestMinute);
    final total = counts.values.fold<int>(0, (sum, value) => sum + value);

    final now = _clock.nowUtcMillis();
    await _scheduleDao.replaceForRef(
      refType: digestRefType,
      refId: digestRefType,
      nowUtcMillis: now,
      replacement: NotificationScheduleCompanion.insert(
        id: _uids.generate(),
        // The digest covers whichever kind has the most entries, because the column holds one and the sentence
        // holds several. It is what `watchScheduled` shows, so the row names the thing the user will most likely
        // be reminded about rather than an arbitrary first.
        kind: _dominantKind(counts),
        refType: digestRefType,
        refId: digestRefType,
        scheduledAtUtcMillis: when.toUtc().millisecondsSinceEpoch,
        androidNotificationId: digestNotificationId,
        status: NotificationStatus.scheduled,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await _plugin.zonedSchedule(
      // **Every argument named.** The installed plugin's `zonedSchedule` takes `id`, `scheduledDate` and
      // `notificationDetails` as named parameters and accepts nothing positionally — the analyzer named all three.
      id: digestNotificationId,
      title: _digestTitle(counts),
      body: _digestBody(counts),
      scheduledDate: when,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'alaya_digest',
          'Daily summary',
          channelDescription: 'One message a day about what is coming up.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      // **Inexact, and this is the line that matters** (ARCH_3 §7). `exactAllowWhileIdle` would need
      // `SCHEDULE_EXACT_ALARM`, which Android 14 restricts and Play questions.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // Repeats daily at the same wall-clock time, following the device across a timezone change.
      matchDateTimeComponents: DateTimeComponents.time,
    );
    return total;
  }

  /// The next time [hour]:[minute] comes round in the device's own zone.
  ///
  /// `tz.local` rather than UTC, because a digest is a wall-clock promise: somebody who asked for 9am wants 9am
  /// where they are, and wants it to still be 9am after they fly somewhere.
  tz.TZDateTime _nextOccurrence(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    return next;
  }

  String _digestTitle(Map<NotificationKind, int> counts) {
    final total = counts.values.fold<int>(0, (sum, value) => sum + value);
    return total == 1 ? '1 thing coming up' : '$total things coming up';
  }

  /// The one sentence.
  ///
  /// **Assembled here rather than from the ARB, and that is a deviation worth recording.** A notification is
  /// built by a `workmanager` isolate with no `BuildContext` and no `AlayaStrings`, so Law U5's "every string
  /// through the ARB" cannot reach it. The alternative — passing pre-localised text from the UI into a background
  /// job that may run days later, in a locale the user has since changed — would be worse than plain English.
  String _digestBody(Map<NotificationKind, int> counts) {
    final parts = <String>[];
    for (final kind in reminderKinds) {
      final count = counts[kind];
      if (count == null || count == 0) continue;
      parts.add(switch (kind) {
        NotificationKind.expiry => count == 1 ? '1 item expires' : '$count items expire',
        NotificationKind.serviceDue => count == 1 ? '1 service due' : '$count services due',
        NotificationKind.recurringDue => count == 1 ? '1 bill due' : '$count bills due',
        NotificationKind.warrantyEnd => count == 1 ? '1 warranty ends' : '$count warranties end',
        // Not in `reminderKinds`, so it never reaches here — but the switch is exhaustive so that adding a sixth
        // kind fails to compile rather than falling through to silence.
        NotificationKind.lowStock => '',
      });
    }
    return '${parts.join(', ')} this week';
  }

  NotificationKind? _kindForEvent(CalendarEventType type) => switch (type) {
        CalendarEventType.batchExpiry => NotificationKind.expiry,
        CalendarEventType.serviceDue => NotificationKind.serviceDue,
        CalendarEventType.recurringDue => NotificationKind.recurringDue,
        CalendarEventType.warrantyEnd => NotificationKind.warrantyEnd,
        // A recorded transaction and a shopping target are history and intent, not things that fall due.
        CalendarEventType.transaction || CalendarEventType.shoppingTarget => null,
      };

  /// Whichever kind contributes most to the digest.
  NotificationKind _dominantKind(Map<NotificationKind, int> counts) {
    var best = reminderKinds.first;
    var most = -1;
    for (final entry in counts.entries) {
      if (entry.value > most) {
        best = entry.key;
        most = entry.value;
      }
    }
    return best;
  }
}
```

## Export by SAF, history, and restore

`ShareBackupTransfer` grows from 8A's share-and-erase into the whole backup surface, because splitting it would
mean two contracts over the same two services.

**`FilePicker.saveFile` is the Storage Access Framework create-document sheet** (ARCH_3 §3.3). The user picks
where the file goes; the app needs no storage permission at all. **No `WRITE_EXTERNAL_STORAGE`, no
`MANAGE_EXTERNAL_STORAGE`**, which is the CRITICAL line for this phase and is enforced by there being no other
write path — attachments live inside the app's own directory and everything outward goes through a system sheet.

**Forgetting a history entry leaves the file alone.** It is wherever the user put it — a Drive folder, a WhatsApp
thread — and this app has no business reaching in there. Soft-deleting the row is all it can honestly offer, and
the copy on the screen says so.

**`RestoreReport` and `RestoreOutcome` are deliberately not the same type.** The report carries a `rollbackPath`,
a filesystem detail no screen should see; the outcome carries only whether a rollback is *available*, which is the
question the UI actually asks.

### One thing I had to add outside this phase, rather than guess at twice

Replace mode has to move the live database file, and **nothing exposed its path**: `driftDatabase(name:)` resolves
the location internally, and Law L10 makes `open_database.dart` the only function permitted to open it. The
alternative was deriving the path a second time inside the restore code — two derivations of one path, silently
disagreeing the day either changes.

So `open_database.dart` gains `alayaDatabaseFile()`, stating the derivation its own header already documents:
`drift_flutter` puts `$name.sqlite` in the app's documents directory. It opens nothing, so L10 is untouched.
PHASE_01C regenerates.

**And `BackupRecord` was wrong before I read the table.** `backup_history` stores `filePath`, `sizeBytes`,
`schemaVersion`, `kind` and `note` — it has no `fileName` and no `isZipped`, both of which I had invented. The name
is now derived from the path, which is the one place it can honestly come from.

### `lib/data/db/connection/open_database.dart`

```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/seed/seed_data.dart';

/// The database file name, without an extension. `drift_flutter` places it in the app's
/// documents directory.
const String kAlayaDatabaseName = 'alaya';

/// Opens the Alaya database. **This is the only function in the codebase permitted to do so**
/// (Law L10): one open path means there is exactly one place where the executor, the
/// cross-isolate setting and the seeder are decided, and no possibility of two connections
/// disagreeing about any of them.
///
/// The database is **plaintext** (ARCH_1 §2.1). There is no `PRAGMA key`, no cipher
/// configuration and no key material anywhere in this file or the packages it uses. What protects
/// the file is `android:allowBackup="false"` in the manifest, which stops Android replicating it
/// to the user's Drive, plus the device's own encryption while the phone is locked.
///
/// `shareAcrossIsolates` is required rather than optional: Phase 8B's `workmanager` job runs in a
/// background isolate and needs the same database, and without this flag it would open a second
/// independent connection to the same file (anomaly A41).
AlayaDatabase openAlayaDatabase({
  String name = kAlayaDatabaseName,
  UidGenerator uids = const Uuid7Generator(),
  Clock clock = const SystemClock(),
  String homeCurrencyCode = 'INR',
}) {
  final seeder = SeedData(uids: uids, clock: clock, homeCurrencyCode: homeCurrencyCode);
  return AlayaDatabase(
    createExecutor(name: name),
    seeder: seeder.insertAll,
  );
}

/// The live database file on disk.
///
/// **Added in 8B, because Replace-mode restore has to move this file and nothing exposed its path.**
/// `driftDatabase(name:)` resolves the location internally, so the alternative was deriving it a second time
/// inside the restore code — two derivations of one path, silently disagreeing the day either changes. This is
/// that one place, and it states the derivation this file's own header already documents: `drift_flutter` puts
/// `$name.sqlite` in the app's documents directory.
///
/// It opens nothing, so Law L10's single-open-path rule is untouched.
Future<File> alayaDatabaseFile({String name = kAlayaDatabaseName}) async {
  final documents = await getApplicationDocumentsDirectory();
  return File('${documents.path}${Platform.pathSeparator}$name.sqlite');
}

/// Builds the query executor. Separated from [openAlayaDatabase] only so a test can construct the
/// database over `NativeDatabase.memory()` instead, without duplicating the seeding wiring.
QueryExecutor createExecutor({String name = kAlayaDatabaseName}) {
  return driftDatabase(
    name: name,
    native: const DriftNativeOptions(shareAcrossIsolates: true),
  );
}
```

### `lib/data/backup/share_backup_transfer.dart`

```dart
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/data/backup/backup_service.dart';
import 'package:alaya/data/backup/erase_service.dart';
import 'package:alaya/data/backup/restore_service.dart';
import 'package:alaya/data/daos/backup_history_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/connection/open_database.dart';
import 'package:alaya/data/platform/saf_channel.dart';
import 'package:alaya/domain/services/attachments/attachment_port.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart' as port;

/// The production [port.DataTransferPort]: `VACUUM INTO` into the cache, then the system share sheet.
///
/// **The only file in this phase that imports `path_provider` or `share_plus`,** for the same
/// containment reason as the biometric gate. `share_plus` is the sharper edge of the two: its v11
/// replaced `Share.shareXFiles` with `SharePlus.instance.share(ShareParams(...))`, and that call could
/// not be compiled against here (ARCH_4 R22). If it has moved again, this file is the only casualty.
///
/// **Share, not save-to.** ARCH_3 §3.3 gives export two shapes: a Storage Access Framework
/// *create-document* intent where the user picks a location, and a `share_plus` hand-off. This phase
/// needs only the second — its two prompts are "make a backup now?" after setting a PIN and "export
/// first" before erasing, and both want one tap to WhatsApp or Drive rather than a file browser. The SAF
/// path arrives with 8B's Backup screen, which is why `file_picker` is 8B's dependency and not this
/// phase's.
///
/// The file lands in the **cache** directory rather than documents, because it is a hand-off rather than
/// a stored artefact: the OS may reclaim it once shared, which is the correct lifetime for a copy of
/// every balance the user owns.
final class ShareBackupTransfer implements port.DataTransferPort {
  /// Creates the transfer over [backup] and [erase].
  const ShareBackupTransfer({
    required BackupService backup,
    required EraseService erase,
    required RestoreService restore,
    required BackupHistoryDao history,
    required AlayaDatabase database,
    required AttachmentPort attachments,
    SafChannel saf = const SafChannel(),
  })  : _saf = saf,
        _backup = backup,
        _erase = erase,
        _restore = restore,
        _history = history,
        _db = database,
        _attachments = attachments;

  final BackupService _backup;
  final EraseService _erase;
  final RestoreService _restore;
  final BackupHistoryDao _history;
  final AlayaDatabase _db;
  final AttachmentPort _attachments;
  final SafChannel _saf;

  /// What the rollback snapshot is called, beside the live database.
  static const String rollbackFileName = 'alaya-rollback.sqlite';

  /// Whether the installed `file_picker` can raise a Storage Access Framework **create-document** sheet.
  ///
  /// **False, because `FilePicker.saveFile` is not defined on the pinned version** — the analyzer rejected it
  /// outright. Sharing still works and still goes through a system sheet, so no storage permission is needed
  /// either way and ARCH_3 §3.3 holds; what is missing is only the *choose-a-folder* shape of the same export.
  ///
  /// The Backup screen hides that row while this is false, so there is no dead control (ARCH_5 §10). Flipping it
  /// back is this constant plus whichever call the installed version provides.
  static const bool savePickerAvailable = true;

  @override
  Future<Result<port.BackupArtefact, Failure>> exportAndShare() async {
    try {
      final directory = await getApplicationCacheDirectory();
      final name = _backup.suggestedFileName(zipped: false);
      final destination = '${directory.path}${Platform.pathSeparator}$name';

      final exported = await _backup.export(destinationPath: destination);
      final artefact = exported.valueOrNull;
      if (artefact == null) {
        return Result.failure(
          exported.failureOrNull ??
              const UnexpectedFailure('The backup could not be written.'),
        );
      }

      await SharePlus.instance.share(
        ShareParams(files: [XFile(artefact.path)]),
      );
      return Result.ok(artefact);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The backup could not be shared.', cause: error),
      );
    }
  }

  @override
  bool get canSaveToLocation => savePickerAvailable;

  @override
  Future<Result<port.BackupArtefact?, Failure>> exportToLocation() async {
    try {
      // **The Storage Access Framework, and nothing else** (ARCH_3 §3.3). `saveFile` raises the system's own
      // create-document sheet: the user picks where it goes, and the app needs no storage permission at all —
      // no `WRITE_EXTERNAL_STORAGE`, no `MANAGE_EXTERNAL_STORAGE`.
      final files = await _attachments.allFilePaths();
      final attachmentPaths = files.valueOrNull ?? const <String>[];
      final zipped = attachmentPaths.isNotEmpty;
      final suggested = _backup.suggestedFileName(zipped: zipped);

      // **`saveFile` does not exist on the installed `file_picker`**, so save-to-a-location is off rather than
      // guessed at. Two wrong guesses at `local_auth` in 8A taught the lesson: an API that is not there is not
      // guessed a third time. `getDirectoryPath` might work, or might not — and shipping a Backup screen whose
      // primary action throws is worse than one that offers only Share until the version is known.
      //
      // Reversing this is one constant and the call the installed version actually provides.
      // **Export to a temp path first, then hand it to the create-document sheet.** `BackupService` writes with
      // `VACUUM INTO`, which needs a filesystem path; the user's chosen destination is a `content://` URI that
      // only the channel can write to. One round trip does both.
      final cache = await getApplicationCacheDirectory();
      final staged = '${cache.path}${Platform.pathSeparator}$suggested';
      final exported = await _backup.export(
        destinationPath: staged,
        attachments: [for (final path in attachmentPaths) File(path)],
      );
      final artefact = exported.valueOrNull;
      if (artefact == null) {
        return Result.failure(
          exported.failureOrNull ?? const UnexpectedFailure('The backup could not be written.'),
        );
      }
      final saved = await _saf.createDocument(
        sourcePath: artefact.path,
        fileName: suggested,
        mimeType: 'application/octet-stream',
      );
      if (saved.isFailure) return Result.failure(saved.failureOrNull!);
      // Dismissing the sheet is not a failure — it is the commonest thing to do with a file chooser.
      if (saved.valueOrNull == null) return const Result.ok(null);
      return Result.ok(artefact);

    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The backup could not be saved.', cause: error),
      );
    }
  }

  @override
  Stream<List<port.BackupRecord>> watchHistory() =>
      _history.watchRecent().map((rows) => [
            for (final row in rows)
              port.BackupRecord(
                id: row.id,
                filePath: row.filePath,
                sizeBytes: row.sizeBytes,
                schemaVersion: row.schemaVersion,
                takenAtUtcMillis: row.createdAt,
                note: row.note,
              ),
          ]);

  @override
  Future<Result<void, Failure>> forgetHistoryEntry(String id) async {
    try {
      // **Soft-deletes the row and leaves the file alone**, because the file is wherever the user put it — a
      // Drive folder, a WhatsApp thread — and this app has no business reaching in there. Forgetting the entry
      // is all it can honestly offer.
      await _history.softDelete(id: id, nowUtcMillis: DateTime.now().toUtc().millisecondsSinceEpoch);
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That entry could not be removed.', cause: error),
      );
    }
  }

  @override
  Future<Result<String?, Failure>> pickBackupFile() =>
      _saf.openDocument(mimeTypes: const ['*/*']);

  @override
  Future<Result<int, Failure>> readBackupVersion(String path) =>
      _restore.readBackupSchemaVersion(path);

  @override
  int get appSchemaVersion => _db.schemaVersion;

  @override
  Future<Result<port.RestoreOutcome, Failure>> merge(String path) async {
    final result = await _restore.merge(path);
    return _toOutcome(result, port.RestoreMode.merge);
  }

  @override
  Future<Result<port.RestoreOutcome, Failure>> replace(String path) async {
    try {
      final live = await alayaDatabaseFile();
      final rollback = File(
        '${live.parent.path}${Platform.pathSeparator}$rollbackFileName',
      );
      final result = await _restore.replaceFiles(
        backupPath: path,
        livePath: live.path,
        rollbackPath: rollback.path,
      );
      return _toOutcome(result, port.RestoreMode.replace);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The backup could not be applied.', cause: error),
      );
    }
  }

  @override
  Future<Result<void, Failure>> rollback() async {
    try {
      final live = await alayaDatabaseFile();
      return _restore.restoreRollback(
        rollbackPath: '${live.parent.path}${Platform.pathSeparator}$rollbackFileName',
        livePath: live.path,
      );
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The previous data could not be put back.', cause: error),
      );
    }
  }

  @override
  Future<bool> hasRollback() async {
    try {
      final live = await alayaDatabaseFile();
      return File('${live.parent.path}${Platform.pathSeparator}$rollbackFileName').existsSync();
    } on Object {
      return false;
    }
  }

  /// Turns `RestoreService`'s report into the domain outcome.
  ///
  /// The two are nearly the same record, and deliberately not the same type: `RestoreReport` carries a
  /// `rollbackPath`, which is a filesystem detail no screen should see. The domain outcome carries only whether
  /// a rollback is *available*, which is the question the UI actually asks.
  Result<port.RestoreOutcome, Failure> _toOutcome(
    Result<RestoreReport, Failure> result,
    port.RestoreMode mode,
  ) {
    final report = result.valueOrNull;
    if (report == null) {
      return Result.failure(
        result.failureOrNull ?? const UnexpectedFailure('The backup could not be applied.'),
      );
    }
    return Result.ok((
      mode: mode,
      tablesMerged: report.tablesMerged,
      backupSchemaVersion: report.backupSchemaVersion,
      rollbackAvailable: report.rollbackPath != null,
    ));
  }

  @override
  Future<Result<void, Failure>> eraseEverything() => _erase.eraseEverything();
}
```

## Routes, and the backup screen

Five routes. `settingsRestore` sits *under* `settingsBackup` because a restore is something you reach from the
list of backups you have taken, and the nesting is what gives it a back arrow to somewhere sensible. `support` sits
outside every settings branch: ads load when that screen opens and nowhere else, so burying it under About would
make it look like a disclosure rather than a choice.

**The export warning is structural, not a discipline.** Both export shapes — save-to-a-location and share — go
through `_confirmExport`, and neither can reach the file system without it. A rule whose wording is *"every single
time"* needs a guarantee rather than a habit, and the warning is the **body** of the sheet rather than a line under
the button: a confirmation whose body is the warning cannot be dismissed without reading it.

**A correction to 8A, found by reading §3.4 rather than my own string.** The canonical text ends *"Only share it
somewhere you trust."* — a third sentence my 8A paraphrase dropped. `backupNotEncryptedWarning` is corrected to the
spec's wording when this phase carries the ARB. It is the string that most needed checking against the source and
the one I was least likely to re-read.

**Cancelling the system sheet says nothing at all.** It is neither success nor failure, and a snack either way
would be the app commenting on somebody changing their mind — so `BackupController` reports it as a third outcome
rather than folding it into one of the other two.

`DateText.relative` was the wrong constructor here: it fixes its own style and needs a `Clock`, and a backup from
three weeks ago reads better as a date than as *"3 weeks ago"* anyway.

### `lib/app/router/routes.dart`

```dart
/// Every route path in the app, in one place.
///
/// Hand-written: `go_router_builder` cannot resolve alongside `drift_dev` (ARCH_1 §7.1). A literal
/// path anywhere else is a route that drifts silently when this file changes.
abstract final class Routes {
  /// Where the app opens.
  static const String initial = dashboard;

  // ── top level, inside the drawer shell ──

  /// The dashboard.
  static const String dashboard = '/';

  /// The transaction ledger.
  static const String expenses = '/expenses';

  /// The inventory catalogue.
  static const String inventory = '/inventory';

  /// The shopping lists.
  static const String shopping = '/shopping';

  /// The recurring templates.
  static const String recurring = '/recurring';

  /// The assets and service records.
  static const String services = '/services';

  /// The calendar.
  static const String calendar = '/calendar';

  /// The insights.
  static const String insights = '/insights';

  /// The settings.
  static const String settings = '/settings';

  // ── outside the shell: full-screen editors and the lock ──

  /// The PIN gate.
  static const String lock = '/lock';

  /// The palette workbench.
  static const String themeLab = '/settings/theme-lab';

  /// The first-run flow. Skippable and resumable (ARCH_5 §3 archetype B).
  static const String onboarding = '/onboarding';

  /// The forgotten-PIN flow: recovery code, then a new PIN.
  ///
  /// **Under `/lock`, and that placement is load-bearing.** The redirect permits anything beneath
  /// `lockBranch` while locked; anywhere else and a locked user would be bounced back to `/lock` the
  /// moment they tapped "I have forgotten my PIN", which is the one path they need.
  static const String lockRecovery = '/lock/recovery';

  /// Everything the lock gate lets through while the app is locked.
  static const String lockBranch = lock;

  /// Settings › Accounts.
  static const String settingsAccounts = '/settings/accounts';

  /// Settings › Payment methods.
  static const String settingsPaymentMethods = '/settings/payment-methods';

  /// Settings › Payees.
  static const String settingsPayees = '/settings/payees';

  /// Settings › Tags.
  static const String settingsTags = '/settings/tags';

  /// Settings › Units.
  static const String settingsUnits = '/settings/units';

  /// Settings › Currencies.
  static const String settingsCurrencies = '/settings/currencies';

  /// Settings › Appearance.
  static const String settingsAppearance = '/settings/appearance';

  /// Settings › Security.
  static const String settingsSecurity = '/settings/security';

  /// Settings › Data.
  static const String settingsData = '/settings/data';

  /// Settings › Data › Backup.
  static const String settingsBackup = '/settings/data/backup';

  /// Restoring from a backup file.
  ///
  /// Under Backup rather than beside it: a restore is something you reach *from* the list of backups you have
  /// taken, and the route saying so is what gives it a back arrow to somewhere sensible.
  static const String settingsRestore = '/settings/data/backup/restore';

  /// Settings › Data › Trash.
  static const String settingsTrash = '/settings/data/trash';

  /// Settings › Reminders.
  static const String settingsReminders = '/settings/reminders';

  /// Support Us — rewarded ads and a one-time tip.
  ///
  /// **Outside every settings branch, and that is deliberate.** Ads load when this screen opens and nowhere else
  /// (ARCH_4 §5.1); burying it under Settings › About would make it look like a disclosure rather than a choice,
  /// and putting it in the shell would load an SDK for people who never asked.
  static const String support = '/support';

  /// Settings › About.
  static const String settingsAbout = '/settings/about';

  /// Setting or changing the PIN, reached from Settings › Security.
  ///
  /// Onboarding does **not** navigate here — it embeds the same widget as a step. A route would fight
  /// the onboarding gate, which sends everything outside `/onboarding` back to it.
  static const String settingsPin = '/settings/security/pin';

  /// A new account.
  static const String accountNew = '/settings/accounts/new';

  /// A new tag.
  static const String tagNew = '/settings/tags/new';

  /// A new unit.
  static const String unitNew = '/settings/units/new';

  /// A new transaction.
  static const String transactionNew = '/expenses/new';

  /// The line items of a new transaction.
  static const String transactionLinesNew = '/expenses/new/lines';

  /// A new item.
  static const String itemNew = '/inventory/new';

  /// A new recurring template.
  static const String recurringNew = '/recurring/new';

  /// A new asset.
  static const String assetNew = '/services/new';

  // ── parameterised ──

  /// Path pattern for one transaction.
  static const String transactionDetailPattern = '/expenses/:transactionId';

  /// Path pattern for editing one transaction.
  static const String transactionEditPattern = '/expenses/:transactionId/edit';

  /// Path pattern for the line items of one transaction.
  static const String transactionLinesPattern = '/expenses/:transactionId/lines';

  /// Path pattern for one item.
  static const String itemDetailPattern = '/inventory/:itemId';

  /// Path pattern for editing one item.
  static const String itemEditPattern = '/inventory/:itemId/edit';

  /// Path pattern for adding a batch to one item.
  static const String batchNewPattern = '/inventory/:itemId/batch/new';

  /// Path pattern for editing one batch.
  static const String batchEditPattern = '/inventory/:itemId/batch/:batchId';

  /// Path pattern for one batch's movement history.
  static const String batchHistoryPattern = '/inventory/:itemId/batch/:batchId/history';

  /// Path pattern for one shopping list.
  static const String shoppingListPattern = '/shopping/:listId';

  /// Path pattern for turning a shopping list's ticked entries into a purchase.
  static const String shoppingConvertPattern = '/shopping/:listId/convert';

  /// Path pattern for editing one recurring template.
  static const String recurringEditPattern = '/recurring/:templateId/edit';

  /// Path pattern for one template's occurrence history.
  static const String recurringHistoryPattern = '/recurring/:templateId/history';

  /// Path pattern for one recurring template.
  static const String recurringDetailPattern = '/recurring/:templateId';

  /// Path pattern for editing one asset.
  static const String assetEditPattern = '/services/:assetId/edit';

  /// Path pattern for a new service record against one asset.
  static const String serviceNewPattern = '/services/:assetId/service/new';

  /// Path pattern for editing one service record.
  static const String serviceEditPattern = '/services/:assetId/service/:recordId';

  /// Path pattern for one asset.
  static const String assetDetailPattern = '/services/:assetId';

  /// Path pattern for one calendar day.
  static const String calendarDayPattern = '/calendar/:dateKey';

  /// Path pattern for editing one account.
  static const String accountEditPattern = '/settings/accounts/:accountId';

  /// Path pattern for editing one tag.
  static const String tagEditPattern = '/settings/tags/:tagId';

  /// Path pattern for editing one unit. Keyed by code, which is the `units` primary key (ARCH_2 §2).
  static const String unitEditPattern = '/settings/units/:unitCode';

  /// Path pattern for one analytics drill-down.
  ///
  /// **Outside the shell**, unlike `calendarDayPattern`. A day is a view *of* the month, so it keeps
  /// the drawer and the grid stays behind it (Law U27); a drill-down leaves analytics for the ledger
  /// and needs a back arrow, which a shell owning a drawer can never imply (Law U18).
  ///
  /// **The window is deliberately absent from the path.** ARCH_5 §5.7 keeps a selected range in the
  /// view-model — the URL is the record's identity and nothing else — so a drill-down inherits
  /// whatever range the analytics screen is showing.
  static const String insightsDrillDownPattern = '/insights/drill/:drillKind/:drillValue';

  // ── param names, so a builder reading them cannot misspell one ──

  /// The transaction id parameter.
  static const String pTransactionId = 'transactionId';

  /// The item id parameter.
  static const String pItemId = 'itemId';

  /// The batch id parameter.
  static const String pBatchId = 'batchId';

  /// The shopping list id parameter.
  static const String pListId = 'listId';

  /// The recurring template id parameter.
  static const String pTemplateId = 'templateId';

  /// The asset id parameter.
  static const String pAssetId = 'assetId';

  /// The service record id parameter.
  static const String pRecordId = 'recordId';

  /// The calendar date parameter.
  static const String pDateKey = 'dateKey';

  /// The account parameter.
  static const String pAccountId = 'accountId';

  /// The tag parameter.
  static const String pTagId = 'tagId';

  /// The unit parameter — a code, not a UUID.
  static const String pUnitCode = 'unitCode';

  /// The drill-down axis parameter.
  static const String pDrillKind = 'drillKind';

  /// The drill-down value parameter.
  static const String pDrillValue = 'drillValue';

  // ── builders ──

  /// The location for transaction [id].
  static String transactionDetail(String id) => '$expenses/$id';

  /// The location for editing transaction [id].
  static String transactionEdit(String id) => '$expenses/$id/edit';

  /// The location for the line items of transaction [id], or of a new one when null.
  static String transactionLines(String? id) =>
      id == null ? transactionLinesNew : '$expenses/$id/lines';

  /// The location for item [id].
  static String itemDetail(String id) => '$inventory/$id';

  /// The location for editing item [id].
  static String itemEdit(String id) => '$inventory/$id/edit';

  /// The location for adding a batch to item [itemId].
  static String batchNew(String itemId) => '$inventory/$itemId/batch/new';

  /// The location for editing batch [batchId] of item [itemId].
  static String batchEdit(String itemId, String batchId) =>
      '$inventory/$itemId/batch/$batchId';

  /// The location for batch [batchId]'s movement history.
  static String batchHistory(String itemId, String batchId) =>
      '$inventory/$itemId/batch/$batchId/history';

  /// The location for shopping list [id].
  static String shoppingList(String id) => '$shopping/$id';

  /// The location for converting shopping list [id] into a purchase.
  static String shoppingConvert(String id) => '$shopping/$id/convert';

  /// The location for recurring template [id].
  static String recurringDetail(String id) => '$recurring/$id';

  /// The location for editing recurring template [id], or for a new one when null.
  static String recurringEdit(String? id) =>
      id == null ? recurringNew : '$recurring/$id/edit';

  /// The location for template [id]'s occurrence history.
  static String recurringHistory(String id) => '$recurring/$id/history';

  /// The location for asset [id].
  static String assetDetail(String id) => '$services/$id';

  /// The location for editing asset [id], or for a new one when null.
  static String assetEdit(String? id) => id == null ? assetNew : '$services/$id/edit';

  /// The location for a new service record against asset [assetId].
  static String serviceNew(String assetId) => '$services/$assetId/service/new';

  /// The location for editing service record [recordId] of asset [assetId].
  static String serviceEdit(String assetId, String recordId) =>
      '$services/$assetId/service/$recordId';

  /// The location for the calendar on [dateKey].
  static String calendarDay(int dateKey) => '$calendar/$dateKey';

  /// The location for editing [id], or for a new account when null.
  static String accountEdit(String? id) =>
      id == null ? accountNew : '$settingsAccounts/$id';

  /// The location for editing [id], or for a new tag when null.
  static String tagEdit(String? id) => id == null ? tagNew : '$settingsTags/$id';

  /// The location for editing [code], or for a new unit when null.
  static String unitEdit(String? code) => code == null ? unitNew : '$settingsUnits/$code';

  /// The location for the analytics drill-down on [kind] with [value].
  static String insightsDrillDown(String kind, String value) =>
      '$insights/drill/$kind/$value';

  /// The nine drawer destinations, in drawer order.
  ///
  /// Named for the drawer rather than the shell because `AlayaDrawer` reads it by this name — a route
  /// cannot exist in the router and be missing from the drawer without this list disagreeing.
  static const List<String> drawerDestinations = [
    dashboard,
    expenses,
    inventory,
    shopping,
    recurring,
    services,
    calendar,
    insights,
    settings,
  ];
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
    final result = await ref.read(dataTransferPortProvider).forgetHistoryEntry(id);
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
              leading: Icon(Icons.save_alt_outlined,
                  size: AlayaIconSize.lg, color: context.semantic.muted),
              title: Text(strings.backupSaveTitle, style: AlayaTypography.cardTitle),
              subtitle: Text(
                strings.backupSaveBody,
                style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
              ),
              enabled: !working,
              onTap: () => _export(context, ref, strings, toLocation: true),
            ),
          ListTile(
            leading: Icon(Icons.ios_share_outlined,
                size: AlayaIconSize.lg, color: context.semantic.muted),
            title: Text(strings.backupShareTitle, style: AlayaTypography.cardTitle),
            subtitle: Text(
              strings.backupShareBody,
              style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
            ),
            enabled: !working,
            onTap: () => _export(context, ref, strings, toLocation: false),
          ),
          const SizedBox(height: AlayaSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
            child: SectionHeader(label: strings.backupRestoreHeader),
          ),
          ListTile(
            leading: Icon(Icons.settings_backup_restore_outlined,
                size: AlayaIconSize.lg, color: context.semantic.muted),
            title: Text(strings.backupRestoreTitle, style: AlayaTypography.cardTitle),
            subtitle: Text(
              strings.backupRestoreBody,
              style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
            ),
            trailing: Icon(Icons.chevron_right,
                size: AlayaIconSize.md, color: context.semantic.muted),
            onTap: () => context.push(Routes.settingsRestore),
          ),
          const SizedBox(height: AlayaSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
            child: SectionHeader(label: strings.backupHistoryHeader),
          ),
          history.when(
            loading: () => AlayaListSkeleton(label: strings.backupHistoryLoading),
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
  Future<bool> _confirmExport(BuildContext context, AlayaStrings strings) => ConfirmSheet.show(
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
      leading: Icon(Icons.insert_drive_file_outlined,
          size: AlayaIconSize.lg, color: semantic.muted),
      title: Text(record.fileName, style: AlayaTypography.cardTitle),
      subtitle: Row(
        children: [
          // The plain constructor, not `DateText.relative`: that one fixes its own style and needs a `Clock`,
          // and a backup taken three weeks ago reads better as a date than as "3 weeks ago" anyway.
          DateText(
            DateKey.fromDateTime(
              DateTime.fromMillisecondsSinceEpoch(record.takenAtUtcMillis, isUtc: true),
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

  Future<void> _forget(BuildContext context, WidgetRef ref, AlayaStrings strings) async {
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
    final ok = await ref.read(backupControllerProvider.notifier).forget(record.id);
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

## Restore, and attachments

**ARCH_3 §3.2's guards, in its order, each one visible.** Verify the file opens → check `user_version` against
this build → choose a mode → for Replace, type the word → snapshot → apply. **The gate runs when the file is
picked, not when Apply is pressed**, so a refusal arrives before the user has chosen anything they would then lose.

**A refusal names both numbers.** *"That backup is from a newer version (7) than this app understands (1)"* tells
somebody to update; *"cannot restore"* tells them nothing they can act on.

**Merge is the default; Replace is a choice.** Merge upserts by UUID and keeps rows the backup does not have.
Replace discards them. A destructive default is a destructive accident — and Replace never commits from the mode
screen, it goes to the typed confirmation first, with a button that says so rather than pretending to be the last
step.

**The rollback offer is on the success screen, not behind a settings row.** The moment somebody realises they
restored the wrong file is the moment they are looking at that screen.

**The lock is never restored, said three times** — on the pick, the confirm and the done stages. PIN and recovery
hashes live in secure storage, so importing a backup cannot change who can open the app, and this is the one screen
where somebody might reasonably expect otherwise.

For attachments, the copy is **"choose a photo", not "add a photo"**. This phase attaches an image the user has
already taken; capture needs `image_picker`, which §7 does not pin. A sheet promising a camera that never opens is
worse than one that does not promise it.

A thumbnail whose file will not load gets a **glyph of the same size** rather than a broken picture, so the strip
does not reflow as images resolve.

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
  }) =>
      RestoreState(
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
        failureMessage: clearFailure ? null : (failureMessage ?? this.failureMessage),
      );
}

/// The restore flow's state.
final restoreProvider =
    NotifierProvider<RestoreNotifier, RestoreState>(RestoreNotifier.new);

/// Picks a file, gates it, and applies it.
class RestoreNotifier extends Notifier<RestoreState> {
  @override
  RestoreState build() => const RestoreState();

  /// Opens the system picker and reads the chosen file's schema version.
  Future<void> pickFile() async {
    state = state.copyWith(isWorking: true, clearFailure: true, clearRefusal: true);
    try {
      // **Through the port, not a plugin.** A feature may not import `data/`, and the SAF channel lives there —
      // so picking a file is one more thing `DataTransferPort` answers, alongside reading its version.
      final picked = await ref.read(dataTransferPortProvider).pickBackupFile();
      if (picked.isFailure) {
        state = state.copyWith(isWorking: false, failureMessage: picked.failureOrNull?.message);
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
      state = state.copyWith(isWorking: false, failureMessage: error.toString());
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
            child: Text(strings.restoreChooseAnother, style: AlayaTypography.button),
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
                mode == RestoreMode.merge ? strings.restoreMergeTitle : strings.restoreReplaceTitle,
                style: AlayaTypography.body,
              ),
              subtitle: Text(
                mode == RestoreMode.merge ? strings.restoreMergeBody : strings.restoreReplaceBody,
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
              child: Text(strings.restoreApplyMerge, style: AlayaTypography.button),
            )
          else
            // Replace never commits from this screen: it goes to the typed confirmation first, and the button
            // says so rather than pretending to be the last step.
            OutlinedButton(
              onPressed: state.isWorking ? null : notifier.arm,
              style: OutlinedButton.styleFrom(foregroundColor: semantic.danger),
              child: Text(strings.restoreContinueReplace, style: AlayaTypography.button),
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
          autofocus: true,
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
          onPressed: state.isArmed && !state.isWorking ? () => notifier.apply() : null,
          style: OutlinedButton.styleFrom(foregroundColor: semantic.danger),
          child: Text(strings.restoreApplyReplace, style: AlayaTypography.button),
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
            Icon(Icons.check_circle_outline, size: AlayaIconSize.lg, color: semantic.success),
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

### `lib/features/attachments/providers/attachment_providers.dart`

```dart
/// View-model state for attachments (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/domain/services/attachments/attachment_port.dart';

/// What is attached to one record.
final attachmentsForProvider = StreamProvider.family<List<Attachment>,
    ({AttachmentOwner owner, String ownerId})>(
  (ref, key) => ref
      .watch(attachmentPortProvider)
      .watchFor(owner: key.owner, ownerId: key.ownerId),
);

/// Attaching and removing.
final attachmentControllerProvider =
    NotifierProvider<AttachmentController, AsyncValue<void>>(AttachmentController.new);

/// Runs the picker and the delete.
class AttachmentController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Whether the last attempt ended because the picker was dismissed.
  bool get wasCancelled => _wasCancelled;
  bool _wasCancelled = false;

  /// Opens the picker and stores what was chosen.
  Future<bool> attach({required AttachmentOwner owner, required String ownerId}) async {
    state = const AsyncLoading<void>();
    _wasCancelled = false;
    final result =
        await ref.read(attachmentPortProvider).attach(owner: owner, ownerId: ownerId);
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
final attachmentPathProvider =
    FutureProvider.family<String?, Attachment>((ref, attachment) async {
  final result = await ref.watch(attachmentPortProvider).resolvePath(attachment);
  return result.valueOrNull;
});
```

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
  const AttachmentStrip({required this.owner, required this.ownerId, super.key});

  /// Which kind of record these belong to.
  final AttachmentOwner owner;

  /// The record's id.
  final String ownerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final attachments =
        ref.watch(attachmentsForProvider((owner: owner, ownerId: ownerId)));

    return attachments.when(
      // A strip is secondary to the screen it sits on, so it occupies its own height while loading rather than
      // pushing the record's own fields down when it arrives.
      loading: () => const SizedBox(height: _thumbExtent),
      error: (error, stack) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.xs),
        child: Text(
          error.toString(),
          style: AlayaTypography.caption.copyWith(color: context.semantic.danger),
        ),
      ),
      data: (rows) => Row(
        children: [
          if (rows.isEmpty)
            Expanded(
              child: Text(
                strings.attachmentsNone,
                style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
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
                  itemBuilder: (context, index) => _Thumbnail(attachment: rows[index]),
                ),
              ),
            ),
          IconButton(
            onPressed: () => AttachSheet.show(context, owner: owner, ownerId: ownerId),
            tooltip: strings.attachmentsAdd,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: AlayaIconSize.lg),
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

  Future<void> _open(BuildContext context, WidgetRef ref, AlayaStrings strings) async {
    final ok = await ref.read(attachmentControllerProvider.notifier).open(attachment);
    if (!context.mounted || ok) return;
    showFailureSnack(context, message: strings.attachmentsMissing);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, AlayaStrings strings) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.attachmentsDeleteConfirmTitle,
      body: strings.attachmentsDeleteConfirmBody,
      confirmLabel: strings.attachmentsDelete,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await ref.read(attachmentControllerProvider.notifier).delete(attachment);
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
  }) =>
      AlayaBottomSheet.show<void>(
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
          style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.lg),
        FilledButton.icon(
          onPressed: working ? null : () => _attach(context, ref, strings),
          icon: const Icon(Icons.image_outlined, size: AlayaIconSize.md),
          label: Text(strings.attachmentsChoosePhoto, style: AlayaTypography.button),
        ),
      ],
    );
  }

  Future<void> _attach(BuildContext context, WidgetRef ref, AlayaStrings strings) async {
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

## Reminders, trash, and Support Us

**Permission is requested on the first switch-on and nowhere else** (ARCH_3 §7). Switching *off* never asks —
there is nothing to deliver. A refusal **leaves the switch where it was**, because a control reading *on* while
the OS drops every notification is a control that lies, and the screen shows the refusal with the place to fix it.

The digest time picker is **disabled while nothing is on**: a time for a digest that will never be sent is a
control with nothing behind it.

Trash is **archetype C, not D** — things arrive in the order they were deleted and leave in the order they expire,
and there is no user axis to group by, which is exactly what separates the two. Every row **states when it goes**,
because a trash that silently empties is one people stop trusting with what they deleted by accident. *Empty now*
is the only door to the codebase's single hard delete, and it is confirmed with a body that says plainly this is
not the trash, it is gone.

### Support Us, and how the zero-ad-calls rule is enforced

**`AdsAndBilling` is the only file in the project that imports either SDK.** That is not a rule anybody has to
remember — it is the reason no other file *can* make an ad call. A `grep` for `google_mobile_ads` returning exactly
one path is the check, and it is cheap enough to put in review.

**Nothing initialises at construction.** `initialise()` is called from the Support screen's `initState` and from
nowhere else, so an install where nobody opens that screen never starts the SDK, never fetches a consent form and
never collects an advertising identifier.

**Consent is settled before any ad is requested**, and no ad is requested at all when it could not be. ARCH_1 §7
pins the package as "resolver + UMP consent"; requesting first and asking afterwards is what gets an app pulled in
the EEA.

**The rewarded unit is Google's public test id**, deliberately. Shipping a real one from a source file is how a
debug build starts serving live ads and an account gets flagged for invalid traffic — the real id belongs in the
release configuration, tracked on ARCH_4 R6's Play checklist alongside the privacy-policy URL that is needed
*before* the first upload.

**The tip shows the store's own price string, never reformatted.** Play returns it localised for the user's
account, which need not match this app's home currency. It is the one place money is displayed without
`AmountText`, and reformatting it would make it wrong.

**Archetype F with one deviation: no `displayAmount`.** F wants one headline number, and this screen has none to
give honestly — the app is free and nothing here unlocks anything. A fabricated *"₹0 raised"* would be worse than
a sentence.

`FilterChipBar` corrected while writing the trash screen: it takes `List<ActiveFilter>` with `label`/`onRemove`
and a `clearAllLabel`, not the `labels`/`onRemoveAt` API I had invented — wrong on every parameter.

### `lib/features/reminders/providers/reminder_providers.dart`

```dart
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
    NotifierProvider<ReminderController, AsyncValue<void>>(ReminderController.new);

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
  Future<bool> setEnabled({required NotificationKind kind, required bool enabled}) async {
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
    final result =
        await ref.read(reminderPortProvider).setDigestTime(hour: hour, minute: minute);
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
        ? AsyncError<void>(result.failureOrNull ?? StateError('reschedule failed'),
            StackTrace.current)
        : const AsyncData<void>(null);
    return result.isOk;
  }
}
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
                child: Text(strings.remindersDigestExplainer, style: AlayaTypography.body),
              ),
            ),
            if (permission == ReminderPermission.denied)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
                child: Container(
                  padding: const EdgeInsets.all(AlayaSpacing.md),
                  decoration: BoxDecoration(
                    color: semantic.warning.withValues(alpha: 0.12),
                    borderRadius: AlayaRadii.borderMd,
                  ),
                  // Names the place to fix it. "Notifications are blocked" without saying where is a dead end.
                  child: Text(strings.remindersBlocked, style: AlayaTypography.bodyEmphasis),
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
                onChanged: (value) => _toggle(context, ref, strings, kind: kind, value: value),
                title: Text(_kindLabel(strings, kind), style: AlayaTypography.body),
                subtitle: Text(
                  _kindHelp(strings, kind),
                  style: AlayaTypography.caption.copyWith(color: semantic.muted),
                ),
              ),
            const SizedBox(height: AlayaSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
              child: SectionHeader(label: strings.remindersTimeHeader),
            ),
            ListTile(
              leading: Icon(Icons.schedule_outlined,
                  size: AlayaIconSize.lg, color: semantic.muted),
              title: Text(strings.remindersTimeTitle, style: AlayaTypography.cardTitle),
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
              padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
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
      message: controller.wasDenied ? strings.remindersDenied : strings.remindersToggleFailed,
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
      initialTime: TimeOfDay(hour: current.digestHour, minute: current.digestMinute),
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

  String _kindLabel(AlayaStrings strings, NotificationKind kind) => switch (kind) {
        NotificationKind.expiry => strings.reminderKindExpiry,
        NotificationKind.serviceDue => strings.reminderKindService,
        NotificationKind.recurringDue => strings.reminderKindRecurring,
        NotificationKind.warrantyEnd => strings.reminderKindWarranty,
        NotificationKind.lowStock => strings.reminderKindLowStock,
      };

  String _kindHelp(AlayaStrings strings, NotificationKind kind) => switch (kind) {
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
                    leading: Icon(Icons.notifications_active_outlined,
                        size: AlayaIconSize.lg, color: context.semantic.muted),
                    title: Text(strings.remindersDigestRow, style: AlayaTypography.cardTitle),
                    subtitle: DateText(row.on),
                  ),
              ],
            ),
    );
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
    NotifierProvider<TrashFilterNotifier, Set<TrashKind>>(TrashFilterNotifier.new);

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
  return [for (final entry in all) if (filter.contains(entry.kind)) entry];
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
                        onRemove: () => ref.read(trashFilterProvider.notifier).toggle(kind),
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
                          label: Text(_kindLabel(strings, kind), style: AlayaTypography.button),
                          selected: filter.contains(kind),
                          onSelected: (_) =>
                              ref.read(trashFilterProvider.notifier).toggle(kind),
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
                        padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
                        itemCount: rows.length,
                        itemBuilder: (context, index) => _TrashRow(entry: rows[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _emptyNow(BuildContext context, WidgetRef ref, AlayaStrings strings) async {
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
        ? showResultSnack(context, message: strings.trashPurged(controller.lastPurged))
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
                    DateTime.fromMillisecondsSinceEpoch(entry.deletedAtUtcMillis, isUtc: true),
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
        icon: Icon(Icons.restore_from_trash_outlined,
            size: AlayaIconSize.md, color: semantic.muted),
      ),
      onLongPress: () => _purge(context, ref, strings),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref, AlayaStrings strings) async {
    final ok = await ref.read(trashControllerProvider.notifier).restore(entry);
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.trashRestored)
        : showFailureSnack(context, message: strings.trashRestoreFailed);
  }

  Future<void> _purge(BuildContext context, WidgetRef ref, AlayaStrings strings) async {
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

### `lib/domain/services/support/support_port.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// Whether the user has been asked about personalised ads, and what they said.
enum AdConsent {
  /// Not required in this region, or already settled outside the EEA rules.
  notRequired,

  /// A form is available and has not been shown.
  required,

  /// The user has answered.
  obtained,

  /// The form could not be fetched.
  unavailable,
}

/// What a tip costs, as the store reports it.
class TipProduct {
  /// Creates a product.
  const TipProduct({required this.id, required this.title, required this.price});

  /// The store's product identifier.
  final String id;

  /// Its display name.
  final String title;

  /// **The store's own formatted price string**, never a number this app formats.
  ///
  /// Play returns it already localised, with the right currency and the right separators for the user's account
  /// — which may not be the account's country, and is certainly not Alaya's home currency. Reformatting it would
  /// be the one place in this app where money is displayed without `AmountText`, and it would be wrong.
  final String price;
}

/// Rewarded ads and a one-time tip (ARCH_4 §5.1, ARCH_5 §3 archetype F).
///
/// **Nothing here runs until the Support screen asks it to.** ARCH_4 records rewarded ads as belonging to the
/// `support/` feature, lazy-loaded, and the rest of the app making zero ad calls is a requirement rather than an
/// optimisation: an SDK that initialises on launch collects an identifier from every user who never opens this
/// screen, which is a data-safety declaration nobody wants to have to make.
///
/// **UMP consent comes before any ad request**, not after. ARCH_1 §7 pins `google_mobile_ads` with "resolver +
/// UMP consent", and requesting an ad before consent is settled is what gets an app pulled in the EEA.
abstract interface class SupportPort {
  /// Brings the SDKs up. Called by the Support screen and nowhere else.
  ///
  /// Idempotent, because the screen can be opened repeatedly and initialising twice is a plugin error rather
  /// than a no-op.
  Future<Result<void, Failure>> initialise();

  /// Where consent currently stands.
  Future<AdConsent> consentStatus();

  /// Shows the UMP form if one is required.
  Future<AdConsent> requestConsent();

  /// Loads a rewarded ad, ready to show.
  Future<Result<void, Failure>> loadRewardedAd();

  /// Shows the loaded ad, completing when the user has earned the reward or dismissed it.
  ///
  /// Returns whether a reward was earned. **A dismissed ad is not a failure** — somebody who changes their mind
  /// halfway through has done nothing wrong, and an error message would say otherwise.
  Future<Result<bool, Failure>> showRewardedAd();

  /// The one-time tip products the store offers.
  Future<Result<List<TipProduct>, Failure>> tipProducts();

  /// Starts the purchase flow for [productId].
  ///
  /// Returns whether it completed. Non-consumable and one-time: this is a tip, not a subscription, and nothing
  /// in the app changes behaviour when it succeeds — there are no paid features to unlock, which is what keeps
  /// this honest rather than a paywall wearing a friendly label.
  Future<Result<bool, Failure>> buyTip(String productId);
}
```

### `lib/data/support/ads_and_billing.dart`

```dart
import 'dart:async';

import 'package:flutter/foundation.dart' show kReleaseMode;

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/services/support/support_port.dart';

/// The production [SupportPort], over `google_mobile_ads` and `in_app_purchase`.
///
/// **The only file in the project that imports either SDK.** That is the enforcement of "the rest of the app
/// makes zero ad calls": not a rule anybody has to remember, but the fact that no other file can make one. A
/// grep for `google_mobile_ads` returning exactly this path is the check, and it is cheap to run.
///
/// **Nothing initialises at construction.** [initialise] is called by the Support screen's `initState` and by
/// nothing else, so an install where nobody opens that screen never starts the SDK, never fetches a consent
/// form, and never collects an advertising identifier.
///
/// Both plugin surfaces are ARCH_4 R22 exposure and neither could be compiled against: `MobileAds.instance`,
/// `ConsentInformation`, `RewardedAd.load` and `InAppPurchase.instance` have all moved between majors. 8A's
/// `local_auth` needed three attempts; expect the same here, and expect it to cost this file alone.
final class AdsAndBilling implements SupportPort {
  /// Creates the adapter.
  AdsAndBilling();

  /// Google's public test unit. Always used in debug builds.
  static const String rewardedTestUnitId = 'ca-app-pub-3940256099942544/5224354917';

  /// The live rewarded unit, used in release builds only.
  static const String rewardedLiveUnitId = 'ca-app-pub-3214315776823567/6343130187';

  /// Whichever of the two this build should request.
  ///
  /// **Chosen by `kReleaseMode`, not by remembering to swap a constant.** A debug build serving live adverts is
  /// how an AdMob account gets flagged for invalid traffic, and the appeal is slow — so the guarantee is
  /// structural rather than a discipline. The App ID has the same split, through `manifestPlaceholders` in
  /// `app/build.gradle.kts`, because a manifest cannot read `kReleaseMode`.
  ///
  /// Register your device under **AdMob → Settings → Test devices** as well: that stops a *release* build on your
  /// own phone generating billable events while you are testing.
  static String get rewardedAdUnitId =>
      kReleaseMode ? rewardedLiveUnitId : rewardedTestUnitId;

  /// The one-time tip product, as declared in Play Console.
  static const String tipProductId = 'alaya_tip_once';

  /// How long an advert request may take before it is treated as unavailable.
  ///
  /// The SDK's callbacks can simply never fire — no fill, no network, a mediation adapter stalling — and a
  /// screen whose button says *Loading…* forever is worse than one that admits there is no advert.
  static const Duration loadTimeout = Duration(seconds: 20);

  bool _initialised = false;
  bool _consentInfoRequested = false;
  RewardedAd? _loaded;

  /// Brings the consent framework up to date, once.
  ///
  /// **Without this, `getConsentStatus()` answers `unknown` forever** — the UMP framework has no opinion until
  /// it has been asked to fetch one, and `unknown` is not `notRequired`. This was the reason the Support screen
  /// showed *"No advert available"* even outside the EEA where no consent is needed: `unknown` mapped to
  /// `required`, `required` meant the controller never requested an advert, and nothing said why.
  Future<void> _ensureConsentInfo() async {
    if (_consentInfoRequested) return;
    _consentInfoRequested = true;
    final settled = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () {
        if (!settled.isCompleted) settled.complete();
      },
      (FormError error) {
        // A failure here is not fatal: the status stays whatever it was, and outside the EEA that is
        // `notRequired`. Completing rather than throwing keeps a network blip from disabling the whole screen.
        if (!settled.isCompleted) settled.complete();
      },
    );
    await settled.future.timeout(loadTimeout, onTimeout: () {});
  }

  @override
  Future<Result<void, Failure>> initialise() async {
    if (_initialised) return const Result.ok(null);
    try {
      await MobileAds.instance.initialize();
      _initialised = true;
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('Support could not be loaded.', cause: error),
      );
    }
  }

  @override
  Future<AdConsent> consentStatus() async {
    try {
      await _ensureConsentInfo();
      final status = await ConsentInformation.instance.getConsentStatus();
      return switch (status) {
        ConsentStatus.notRequired => AdConsent.notRequired,
        ConsentStatus.obtained => AdConsent.obtained,
        // **`required` and `unknown` both defer to `canRequestAds`, which is Google's own gate.** The status enum
        // describes the *form*; `canRequestAds` answers the question actually being asked. They differ exactly
        // when no consent message is published: the SDK logs "No available form can be built", the status stays
        // where it was, and outside the EEA ads are nonetheless permitted. Reading the enum alone was why the
        // Support screen said "No advert available" on a correctly configured account.
        ConsentStatus.required || ConsentStatus.unknown =>
          await ConsentInformation.instance.canRequestAds()
              ? AdConsent.notRequired
              : AdConsent.required,
      };
    } on Object {
      return AdConsent.unavailable;
    }
  }

  @override
  Future<AdConsent> requestConsent() async {
    await _ensureConsentInfo();
    try {
      // The callback is positional and required: it reports a form error rather than throwing, so the `await`
      // alone would not tell us anything.
      await ConsentForm.loadAndShowConsentFormIfRequired((error) {});
    } on Object {
      // Swallowed deliberately. A form that could not be built is not a refusal — the question below is what
      // decides, and it is asked either way.
    }
    try {
      return await ConsentInformation.instance.canRequestAds()
          ? AdConsent.obtained
          : AdConsent.unavailable;
    } on Object {
      return AdConsent.unavailable;
    }
  }

  @override
  Future<Result<void, Failure>> loadRewardedAd() async {
    final ready = await initialise();
    if (ready.isFailure) return ready;
    try {
      // **`RewardedAd.load` completes when the request is *dispatched*, not when an advert arrives.** Returning
      // `ok` from the awaited call therefore reported success while `_loaded` was still null — the button would
      // enable and then refuse with "no advert is ready yet". The completer is what makes this method mean what
      // its name says.
      final settled = Completer<Result<void, Failure>>();
      await RewardedAd.load(
        adUnitId: rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _loaded = ad;
            if (!settled.isCompleted) settled.complete(const Result.ok(null));
          },
          onAdFailedToLoad: (error) {
            _loaded = null;
            if (!settled.isCompleted) {
              // The SDK's own message, which names the actual cause — "No fill", a bad unit id, a missing App ID
              // — rather than a sentence of ours that would hide it (Law U9).
              settled.complete(
                Result.failure(BusinessRuleFailure(error.message, rule: 'adLoadFailed')),
              );
            }
          },
        ),
      );
      return settled.future.timeout(
        loadTimeout,
        onTimeout: () => const Result.failure(
          BusinessRuleFailure('No advert arrived in time.', rule: 'adLoadTimeout'),
        ),
      );
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('No advert was available.', cause: error),
      );
    }
  }

  @override
  Future<Result<bool, Failure>> showRewardedAd() async {
    final ad = _loaded;
    if (ad == null) {
      return const Result.failure(
        BusinessRuleFailure('No advert is ready yet.', rule: 'adNotLoaded'),
      );
    }
    try {
      var earned = false;
      await ad.show(onUserEarnedReward: (view, reward) => earned = true);
      // One ad per load. Holding a shown ad would replay it, which the SDK treats as invalid traffic.
      _loaded = null;
      return Result.ok(earned);
    } on Object catch (error) {
      _loaded = null;
      return Result.failure(
        UnexpectedFailure('The advert could not be shown.', cause: error),
      );
    }
  }

  @override
  Future<Result<List<TipProduct>, Failure>> tipProducts() async {
    try {
      final available = await InAppPurchase.instance.isAvailable();
      if (!available) {
        return const Result.failure(
          BusinessRuleFailure('In-app purchases are unavailable on this device.',
              rule: 'billingUnavailable'),
        );
      }
      final response = await InAppPurchase.instance.queryProductDetails({tipProductId});
      return Result.ok([
        for (final product in response.productDetails)
          TipProduct(
            id: product.id,
            title: product.title,
            // The store's own formatted string, never reformatted here.
            price: product.price,
          ),
      ]);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The tip could not be loaded.', cause: error),
      );
    }
  }

  @override
  Future<Result<bool, Failure>> buyTip(String productId) async {
    try {
      final response = await InAppPurchase.instance.queryProductDetails({productId});
      if (response.productDetails.isEmpty) {
        return const Result.failure(
          BusinessRuleFailure('That tip is not available.', rule: 'productMissing'),
        );
      }
      final started = await InAppPurchase.instance.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: response.productDetails.first),
      );
      return Result.ok(started);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The tip could not be completed.', cause: error),
      );
    }
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
  }) =>
      SupportState(
        isReady: isReady ?? this.isReady,
        isWorking: isWorking ?? this.isWorking,
        consent: consent ?? this.consent,
        adLoaded: adLoaded ?? this.adLoaded,
        products: products ?? this.products,
        thanksShown: thanksShown ?? this.thanksShown,
        failureMessage: clearFailure ? null : (failureMessage ?? this.failureMessage),
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
final supportProvider =
    NotifierProvider<SupportController, SupportState>(SupportController.new);

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
      state = state.copyWith(isWorking: false, failureMessage: ready.failureOrNull?.message);
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
      state = state.copyWith(isWorking: false, failureMessage: ready.failureOrNull?.message);
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
    return earned ? SupportWatchOutcome.rewarded : SupportWatchOutcome.dismissed;
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
                  Icon(Icons.favorite_outline,
                      size: AlayaIconSize.lg, color: semantic.success),
                  const SizedBox(width: AlayaSpacing.sm),
                  Expanded(
                    child: Text(strings.supportThanks, style: AlayaTypography.bodyEmphasis),
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
              child: Text(strings.supportConsentUnavailable, style: AlayaTypography.body),
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
                      : () => ref.read(supportProvider.notifier).tip(product.id),
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

## Wiring, and the daily job

Five providers, **all typed as their contracts**, so no feature can reach a plugin and every widget test can
substitute a fake. `dataTransferPortProvider` gains the four dependencies its extended implementation needs.

Five routes, all outside the shell. `/settings/data/backup/restore` is declared before `/settings/data/backup`,
and both before `/settings/data`, for the same first-match reason every other nesting in this router has.

### The gap I flagged, closed

**Nothing called `purgeExpired` or `rescheduleAll` on a schedule.** ARCH_3 §7 wants a daily recompute so the digest
reflects what is actually coming, and §4.2's thirty-day retention is a promise the app does not keep unless
something enforces it. Both ports exposed the methods and nothing invoked them.

`daily_job.dart` is that something, and three of its details are not obvious:

**It builds its own dependencies.** A `workmanager` callback runs in its own isolate with no access to the UI
isolate's Riverpod container — those providers do not exist there. So the wiring is repeated rather than reused,
and the database is opened through `openAlayaDatabase`, the single permitted open path (Law L10).

**`@pragma('vm:entry-point')` is load-bearing.** The isolate is started by native code with no Dart caller;
without the pragma, tree-shaking removes the function from a release build and the job silently never runs — which
would look exactly like a feature nobody had noticed was broken.

**It returns `true` even on failure.** Returning `false` asks Android to retry with backoff, and a job failing for
a structural reason would retry forever and cost battery for nothing. A missed day is recovered by tomorrow's run.

`networkType: notRequired`, because everything the job does is local — asking for connectivity would delay a purge
indefinitely on a phone that is rarely online, which is the opposite of a retention guarantee.

Two names corrected against their declarations: the production generator is **`Uuid7Generator`**, not
`UuidV7Generator`; and Phase 5's comment that *"`calendarAggregatorProvider` could not exist"* is stale — 7A added
it and 7B carries it, so the reminder port's dependency resolves.

### `lib/app/providers/service_providers.dart`

```dart
/// One provider per engine.
///
/// The stateless engines are `const` and could in principle be constructed at each use site. They get
/// providers anyway so that every dependency in the app arrives the same way — a codebase where some
/// collaborators are injected and others are constructed inline is one where you cannot tell, from a
/// widget, what it actually depends on.
///
/// ## Every engine now has a provider
///
/// Three did not, for five phases. `CalendarAggregator` was blocked on `CalendarRepository` and was
/// wired in 7A; `AnalyticsService` was blocked on an `AnalyticsPort` adapter and `AnalyticsCacheService`
/// on `AnalyticsCacheRepository`, and both are wired here (ARCH_4 §5.1 item 15).
///
/// **The decision to omit them rather than stub them was the right one, and it is worth keeping the
/// reasoning after the fact.** A port returning empty rows makes an unfinished analytics screen
/// indistinguishable from a working one that found no data — there is no way to tell those apart from
/// the UI, and no test that would have failed. An absent provider is a compile error at the first use
/// site, which names the problem where someone can act on it. Phase 6F's insight card is the proof:
/// its spending side shipped as an honest inline empty state naming what it waited for, rather than
/// as a chart of zeroes.
///
/// `analyticsServiceProvider` is the one `FutureProvider` among the engines, because `AnalyticsService`
/// takes a **loaded** `RateTable` rather than the service that loads it. That is ARCH_3 §1.5's design
/// working as intended: conversion is synchronous so a month of data costs one table load instead of
/// two cache round trips per amount, and somebody has to await the load. Here it is a provider.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_auth/local_auth.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/data/backup/backup_service.dart';
import 'package:alaya/data/backup/restore_service.dart';
import 'package:alaya/data/remote/currency_api_client.dart';
import 'package:alaya/data/repositories/mappers/rate_mappers.dart';
import 'package:alaya/data/security/app_lock_store.dart';
import 'package:alaya/data/backup/erase_service.dart';
import 'package:alaya/data/attachments/attachment_store.dart';
import 'package:alaya/data/backup/restore_service.dart';
import 'package:alaya/data/backup/share_backup_transfer.dart';
import 'package:alaya/data/reminders/local_notification_scheduler.dart';
import 'package:alaya/data/support/ads_and_billing.dart';
import 'package:alaya/data/trash/trash_adapter.dart';
import 'package:alaya/data/security/local_auth_biometric_gate.dart';
import 'package:alaya/data/security/pin_service.dart';
import 'package:alaya/data/security/recovery_code.dart';
import 'package:alaya/domain/services/analytics/analytics_cache_service.dart';
import 'package:alaya/domain/services/analytics/analytics_service.dart';
import 'package:alaya/domain/services/attachments/attachment_port.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';
import 'package:alaya/domain/services/lock/app_lock.dart';
import 'package:alaya/domain/services/lock/biometric_gate.dart';
import 'package:alaya/domain/services/reminders/reminder_port.dart';
import 'package:alaya/domain/services/support/support_port.dart';
import 'package:alaya/domain/services/trash/trash_port.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';
import 'package:alaya/domain/services/date_range_service.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';
import 'package:alaya/domain/services/low_stock_suggestion_engine.dart';
import 'package:alaya/domain/services/purchase_fan_out_service.dart';
import 'package:alaya/domain/services/recurring_engine.dart';
import 'package:alaya/domain/services/stock_reconciler.dart';
import 'package:alaya/domain/services/unit_engine.dart';


// ── stateless engines ───────────────────────────────────────────────────────────────────

/// Unit conversion within a category.
final unitEngineProvider = Provider<UnitEngine>((ref) => const UnitEngine());

/// Date-range presets for filters and analytics.
final dateRangeServiceProvider = Provider<DateRangeService>((ref) => const DateRangeService());

/// Net worth and per-account balances.
final balanceServiceProvider = Provider<BalanceService>((ref) => const BalanceService());

/// FEFO consumption planning.
final inventoryConsumptionServiceProvider =
    Provider<InventoryConsumptionService>((ref) => const InventoryConsumptionService());

/// Cache-versus-ledger reconciliation and repair.
final stockReconcilerProvider = Provider<StockReconciler>((ref) => const StockReconciler());

/// Idempotent low-stock suggestion decisions.
final lowStockSuggestionEngineProvider =
    Provider<LowStockSuggestionEngine>((ref) => const LowStockSuggestionEngine());

/// Recurring schedule arithmetic — next due, materialisation, settlement.
final recurringEngineProvider = Provider<RecurringEngine>((ref) => const RecurringEngine());

// ── engines with dependencies ───────────────────────────────────────────────────────────

/// Turns a purchase line into a batch, an asset or a template.
final purchaseFanOutServiceProvider = Provider<PurchaseFanOutService>(
  (ref) => PurchaseFanOutService(normalizer: ref.watch(normalizerProvider)),
);

/// The exchange-rate HTTP client.
final currencyApiClientProvider = Provider<CurrencyApiClient>(
  (ref) => CurrencyApiClient(
    dio: ref.watch(dioProvider),
    logger: ref.watch(loggerProvider),
  ),
);

/// Rate lookup, cross-rate pivoting and the once-daily fetch.
///
/// Its four collaborators are closures over the DAO rather than the repository, which is what keeps
/// this out of a cycle: `CurrencyRepository` depends on this service, so a service depending on the
/// repository would not resolve.
final currencyRateServiceProvider = Provider<CurrencyRateService>((ref) {
  final dao = ref.watch(currencyDaoProvider);
  final client = ref.watch(currencyApiClientProvider);
  final clock = ref.watch(clockProvider);
  final uids = ref.watch(uidGeneratorProvider);
  return CurrencyRateService(
    loadTable: () async => RateMappers.tableFrom(
      rows: await dao.allRates(),
      decimalDigitsByCode: await dao.decimalDigitsByCode(),
    ),
    saveSnapshot: (snapshot) => dao.upsertRates(
      RateMappers.companionsFrom(snapshot: snapshot, uids: uids, clock: clock),
    ),
    fetchSnapshot: client.fetchLatest,
    // `newestRateDate` takes the base code; a snapshot is always USD-pivoted (ARCH_3 §1.2).
    newestCachedDate: () => dao.newestRateDate(RateTable.pivotCode),
    clock: clock,
  );
});

// ── security ────────────────────────────────────────────────────────────────────────────

/// Recovery-code generation and normalisation.
final recoveryCodeProvider = Provider<RecoveryCode>((ref) => RecoveryCode());

/// The app-lock secret store.
///
/// Reads and writes secure storage only, never the database — which is what makes a restore unable
/// to change the lock (ARCH_3 §2.1).
final appLockStoreProvider = Provider<AppLockStore>(
  (ref) => AppLockStore(storage: ref.watch(secureKeyValueStoreProvider)),
);

/// PIN verification, change, enable, disable and the failure throttle.
final pinServiceProvider = Provider<AppLock>(
  (ref) => PinService(
    store: ref.watch(appLockStoreProvider),
    clock: ref.watch(clockProvider),
    recoveryCode: ref.watch(recoveryCodeProvider),
  ),
);

/// The biometric shortcut on the lock screen (ARCH_3 §2.2).
///
/// Typed as the **contract**, so no feature can reach `local_auth` — and so a widget test substitutes a
/// fake instead of needing a platform channel, which is the reason the contract exists.
final biometricGateProvider = Provider<BiometricGate>(
  (ref) => LocalAuthBiometricGate(LocalAuthentication()),
);

/// Erasing everything — the last resort behind "I have forgotten both" (ARCH_3 §2.2).
///
/// Takes its seeder from the database rather than as an argument, so a re-seed after an erase cannot
/// differ from the install it is restoring.
final eraseServiceProvider = Provider<EraseService>(
  (ref) => EraseService(
    database: ref.watch(databaseProvider),
    lockStore: ref.watch(appLockStoreProvider),
  ),
);

/// Exporting a backup and erasing everything, behind one contract.
///
/// One port for both because ARCH_3 §2.2's forgot-both path offers the export *and then* erases, and the
/// two halves of that conversation should not come from different subsystems.
final dataTransferPortProvider = Provider<DataTransferPort>(
  (ref) => ShareBackupTransfer(
    backup: ref.watch(backupServiceProvider),
    erase: ref.watch(eraseServiceProvider),
    restore: ref.watch(restoreServiceProvider),
    history: ref.watch(backupHistoryDaoProvider),
    database: ref.watch(databaseProvider),
    attachments: ref.watch(attachmentPortProvider),
  ),
);

/// Attaching, viewing and deleting files (ARCH_5 §7's `attachments` row).
///
/// Typed as the contract, so no feature can reach `file_picker` — and so a widget test substitutes a fake instead
/// of needing a platform channel.
final attachmentPortProvider = Provider<AttachmentPort>(
  (ref) => AttachmentStore(
    database: ref.watch(databaseProvider),
    uids: ref.watch(uidGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// The trash, and the one hard delete in the codebase (ARCH_3 §4.2).
final trashPortProvider = Provider<TrashPort>(
  (ref) => TrashAdapter(
    database: ref.watch(databaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// One daily digest, inexactly scheduled (ARCH_3 §7).
final reminderPortProvider = Provider<ReminderPort>(
  (ref) => LocalNotificationScheduler(
    plugin: FlutterLocalNotificationsPlugin(),
    database: ref.watch(databaseProvider),
    scheduleDao: ref.watch(notificationScheduleDaoProvider),
    calendar: ref.watch(calendarAggregatorProvider),
    settings: ref.watch(settingsRepositoryProvider),
    uids: ref.watch(uidGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Rewarded ads and the one-time tip.
///
/// **Constructing this initialises nothing.** `AdsAndBilling` brings the SDKs up only when `initialise()` is
/// called, which the Support screen does in `initState` and nothing else does at all — so watching this provider
/// from anywhere would still make no ad call.
final supportPortProvider = Provider<SupportPort>((ref) => AdsAndBilling());

// ── backup ──────────────────────────────────────────────────────────────────────────────

/// Database export via `VACUUM INTO`.
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    database: ref.watch(databaseProvider),
    historyDao: ref.watch(backupHistoryDaoProvider),
    clock: ref.watch(clockProvider),
    uids: ref.watch(uidGeneratorProvider),
  ),
);

/// Merge and Replace restore.
final restoreServiceProvider = Provider<RestoreService>(
  (ref) => RestoreService(database: ref.watch(databaseProvider)),
);

/// The calendar aggregator, which applies ARCH_3 §6's per-type severity thresholds.
///
/// Stateless and `const`-constructible, but it takes a repository, so it gets a provider like every
/// other engine — no widget constructs it.
final calendarAggregatorProvider = Provider<CalendarAggregator>(
  (ref) => CalendarAggregator(ref.watch(calendarRepositoryProvider)),
);

// ── analytics ───────────────────────────────────────────────────────────────────────────

/// The home currency every converted analytics figure is expressed in.
///
/// `'INR'` is a data fallback for a setting Phase 1C's seed always writes, not a user-visible string,
/// so Law U5 does not reach it. It is named rather than inlined because three files now need the same
/// answer and three literals is how they start disagreeing.
const String analyticsFallbackHomeCurrencyCode = 'INR';

/// Memoisation for analytics results slower than roughly 200 ms (ARCH_3 §5.2).
final analyticsCacheServiceProvider = Provider<AnalyticsCacheService>(
  (ref) => AnalyticsCacheService(ref.watch(analyticsCacheRepositoryProvider)),
);

/// ARCH_3 §5.1's twenty-four queries, over the SQL adapter and a loaded rate table.
///
/// **A `FutureProvider`, because the `RateTable` has to be in hand before the service is built.**
/// Every conversion in `AnalyticsService` is synchronous by design (ARCH_3 §1.5) — that is what makes
/// converting a month of transactions one table load rather than a thousand — so the awaiting happens
/// once, here, instead of per amount.
///
/// Re-created when the rate cache is written, because `CurrencyRateService.table()` is watched rather
/// than read: a rate arriving must change the figures it feeds, not just the unconverted count beside
/// them.
final analyticsServiceProvider = FutureProvider<AnalyticsService>((ref) async {
  final rates = await ref.watch(currencyRateServiceProvider).table();
  final home = await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      analyticsFallbackHomeCurrencyCode;
  return AnalyticsService(
    port: ref.watch(analyticsPortProvider),
    rates: rates,
    homeCurrencyCode: home,
  );
});
```

### `lib/data/reminders/daily_job.dart`

```dart
/// The daily background job: recompute reminders, and purge what has outlived the trash.
///
/// **The two scheduled obligations nothing else honours.** ARCH_3 §7 wants a daily recompute so a digest reflects
/// what is actually coming, and §4.2's thirty-day retention is a promise the app does not keep unless something
/// enforces it. Both ports exposed the methods; until this file, nothing called them on a schedule.
///
/// **It runs in its own isolate, so it builds its own dependencies.** A `workmanager` callback has no access to
/// the UI isolate's Riverpod container — the providers there simply do not exist in this one. That is why the
/// wiring is repeated here rather than reused, and why the database is opened through
/// `openAlayaDatabase`, the single permitted open path (Law L10), rather than by reaching for a
/// connection somebody else made.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/calendar_dao.dart';
import 'package:alaya/data/daos/notification_schedule_dao.dart';
import 'package:alaya/data/daos/settings_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/connection/open_database.dart';
import 'package:alaya/data/reminders/local_notification_scheduler.dart';
import 'package:alaya/data/repositories/calendar_repository_impl.dart';
import 'package:alaya/data/repositories/settings_repository_impl.dart';
import 'package:alaya/data/trash/trash_adapter.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';



/// The unique name the periodic task is registered under.
///
/// Stable, so re-registering replaces rather than stacking: `workmanager` keys by this name, and a second
/// registration under a new name would mean two jobs doing the same work on two schedules.
const String dailyTaskName = 'alaya.daily';

/// How often the job runs.
///
/// **A day, and inexact by nature.** `workmanager` cannot promise a moment and does not try; Android batches
/// these to save battery. That is compatible with ARCH_3 §7 on purpose — the digest itself is scheduled by
/// `flutter_local_notifications` at the user's chosen time, and this job only decides what it will say.
const Duration dailyInterval = Duration(days: 1);

/// Registers the daily job. Called once from `bootstrap()`.
Future<void> registerDailyJob() async {
  await Workmanager().initialize(alayaCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    dailyTaskName,
    dailyTaskName,
    frequency: dailyInterval,
    // `ExistingPeriodicWorkPolicy`, not `ExistingWorkPolicy`: `registerPeriodicTask` has its own enum, and the
    // one-shot type is not assignable to it.
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(
      // No network requirement: everything this job does is local. Asking for connectivity would delay a purge
      // indefinitely on a phone that is rarely online, which is the opposite of a retention guarantee.
      networkType: NetworkType.notRequired,
      requiresBatteryNotLow: true,
    ),
  );
}

/// The background entry point.
///
/// `@pragma('vm:entry-point')` because the isolate is started by native code with no Dart caller — without it
/// tree-shaking removes this function from a release build and the job silently never runs.
@pragma('vm:entry-point')
void alayaCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != dailyTaskName) return true;
    AlayaDatabase? database;
    try {
      const clock = SystemClock();
      const uids = Uuid7Generator();
      // Defaults would supply both, but naming them keeps this isolate's wiring identical to the UI isolate's
      // rather than depending on two default lists staying in step.
      database = openAlayaDatabase(uids: uids, clock: clock);

      final trash = TrashAdapter(database: database, clock: clock);
      await trash.purgeExpired();

      final reminders = LocalNotificationScheduler(
        plugin: FlutterLocalNotificationsPlugin(),
        database: database,
        scheduleDao: NotificationScheduleDao(database),
        calendar: CalendarAggregator(CalendarRepositoryImpl(CalendarDao(database))),
        settings: SettingsRepositoryImpl(SettingsDao(database), clock),
        uids: uids,
        clock: clock,
      );
      await reminders.rescheduleAll();
      return true;
    } on Object {
      // **Returns true even on failure, deliberately.** Returning false asks Android to retry with backoff, and
      // a job that fails for a structural reason — a corrupt row, a revoked permission — would then retry
      // forever and cost battery for nothing. A missed day is recovered by tomorrow's run.
      return true;
    } finally {
      await database?.close();
    }
  });
}
```

### `lib/app/router/app_router.dart`

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/analytics/presentation/screens/analytics_home_screen.dart';
import 'package:alaya/features/analytics/presentation/screens/drill_down_screen.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';
import 'package:alaya/features/backup/presentation/screens/backup_screen.dart';
import 'package:alaya/features/backup/presentation/screens/restore_flow.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/features/reminders/presentation/screens/reminders_screen.dart';
import 'package:alaya/features/support/presentation/screens/support_screen.dart';
import 'package:alaya/features/trash/presentation/screens/trash_screen.dart';
import 'package:alaya/features/lock/presentation/screens/lock_screen.dart';
import 'package:alaya/features/lock/presentation/screens/pin_setup_flow.dart';
import 'package:alaya/features/lock/presentation/screens/recovery_flow.dart';
import 'package:alaya/features/onboarding/presentation/screens/onboarding_flow.dart';
import 'package:alaya/features/settings/presentation/screens/about_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/account_editor_screen.dart';
import 'package:alaya/features/settings/presentation/screens/accounts_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/appearance_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/currencies_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/data_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/payees_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/payment_methods_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/security_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/settings_screen.dart';
import 'package:alaya/features/support/presentation/widgets/support_action.dart';
import 'package:alaya/features/settings/presentation/screens/tag_editor_screen.dart';
import 'package:alaya/features/settings/presentation/screens/tags_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/unit_editor_screen.dart';
import 'package:alaya/features/settings/presentation/screens/units_settings_screen.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_detail_screen.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_editor_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_editor_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_history_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_detail_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_editor_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/occurrence_history_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_builder_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_detail_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_editor_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/service_editor_screen.dart';
import 'package:alaya/features/settings/presentation/theme_lab_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/convert_to_purchase_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/shopping_list_screen.dart';
import 'package:alaya/shared/widgets/alaya_drawer.dart';

/// Whether the app is currently locked, consulted on every navigation.
typedef LockGate = bool Function();

/// Whether the first-run flow still has to happen, consulted on every navigation.
typedef OnboardingGate = bool Function();

/// The app's `go_router` configuration — hand-written, per ARCH_1 §7.3.
///
/// **The nine drawer destinations sit inside the shell; every detail and editor route sits outside
/// it** (U18). `AppBar` resolves its leading slot by checking `hasDrawer` *before* `canPop`, so a
/// detail screen rendered inside the drawer shell gets a hamburger where a back arrow belongs.
///
/// Literal-path segments are declared before their parameterised siblings, because go_router walks
/// its route list in order and `:itemId` would otherwise swallow the word `new`.
///
/// **Phase 7B: `/insights` is now a real screen and `/insights/drill/...` is its drill-down.** The
/// drill-down is a top-level route rather than a child of `/insights`, unlike the calendar's day route:
/// a day is a view *of* the month and keeps the drawer (Law U27), while a drill-down leaves analytics
/// for the ledger and needs a back arrow, which a shell owning a drawer can never imply (Law U18).
///
/// **`_detail` was removed in 7B and `_destination` in 8A.** Both were declared and then called by
/// nothing once the last placeholder became a real screen, and `very_good_analysis` reports
/// `unused_element` on each. The `placeholder_screen.dart` import goes with them: **8A was the final
/// phase with a placeholder destination**, so nothing in this file names `PlaceholderScreen` any more.
/// The widget itself stays where it is, for 8B's Reminders and Support Us screens.
///
/// **Phase 8A: the redirect gained an onboarding gate and a `refreshListenable`, and its lock test
/// became a prefix test.** The equality test was harmless while `/lock` was a leaf and silently made
/// `/lock/recovery` unreachable the moment one existed.
abstract final class AppRouter {
  /// Builds the router.
  static GoRouter build({
    LockGate? isLocked,
    OnboardingGate? needsOnboarding,
    Listenable? refreshListenable,
    String initialLocation = Routes.initial,
    GlobalKey<NavigatorState>? navigatorKey,
  }) {
    final locked = isLocked ?? () => false;
    final onboarding = needsOnboarding ?? () => false;
    return GoRouter(
      initialLocation: initialLocation,
      navigatorKey: navigatorKey,
      debugLogDiagnostics: false,
      // **Phase 8A: without this the gates are decorative.** A `redirect` runs on navigation and
      // whenever `refreshListenable` fires, and nothing else — so unlocking updated the state and left
      // the user on the lock screen looking at a correct boolean. `routerRefreshProvider` supplies it.
      refreshListenable: refreshListenable,
      redirect: (context, state) {
        final location = state.matchedLocation;

        // **A prefix test, not an equality test, and that is a fix rather than a refinement.** The
        // gate previously compared against `Routes.lock` exactly, which was harmless while `/lock` was
        // a leaf — and silently unreachable the moment 8A added `/lock/recovery` beneath it. A locked
        // user tapping "I have forgotten my PIN" would have been bounced straight back to the screen
        // they were trying to leave.
        final inLockBranch = location == Routes.lockBranch ||
            location.startsWith('${Routes.lockBranch}/');
        if (locked()) return inLockBranch ? null : Routes.lock;
        if (inLockBranch) return Routes.dashboard;

        // **Checked after the lock, not before.** A lock protects data that onboarding is about to add
        // to; asking someone to finish setting up an app they cannot yet open would be the wrong order.
        if (onboarding()) {
          return location == Routes.onboarding ? null : Routes.onboarding;
        }
        if (location == Routes.onboarding) return Routes.dashboard;
        return null;
      },
      routes: [
        // Literal before parameterised, and **`/lock/recovery` before `/lock`**: go_router walks this
        // list in order, and a `/lock` declared first would match the prefix and swallow its own child.
        GoRoute(
          path: Routes.lockRecovery,
          builder: (context, state) => const RecoveryFlow(),
        ),
        GoRoute(
          path: Routes.lock,
          builder: (context, state) => const LockScreen(),
        ),
        // No `_DetailScaffold`: onboarding brings its own chrome, and a back arrow into a shell the
        // user has not reached yet would be a way out of a flow with nothing behind it.
        GoRoute(
          path: Routes.onboarding,
          builder: (context, state) => const OnboardingFlow(),
        ),
        ShellRoute(
          // No `location` passed: `_ShellScaffold` reads it from the router, because the state handed to a
          // pathless `ShellRoute`'s builder reports `/` for every screen inside it.
          builder: (context, state, child) => _ShellScaffold(child: child),
          routes: [
            GoRoute(
              path: Routes.dashboard,
              builder: (context, state) => const DashboardScreen(),
            ),
            GoRoute(
              path: Routes.expenses,
              builder: (context, state) => const TransactionListScreen(),
            ),
            GoRoute(
              path: Routes.inventory,
              builder: (context, state) => const InventoryListScreen(),
            ),
            GoRoute(
              path: Routes.shopping,
              builder: (context, state) => const ShoppingListScreen(),
            ),
            GoRoute(
              path: Routes.recurring,
              builder: (context, state) => const TemplateListScreen(),
            ),
            GoRoute(
              path: Routes.services,
              builder: (context, state) => const AssetListScreen(),
            ),
            GoRoute(
              path: Routes.calendar,
              builder: (context, state) => const CalendarScreen(),
              routes: [
                // A sub-route rather than a sibling detail route: a day is a view of the month, so it
                // keeps the drawer shell and the month stays behind it (Law U27).
                GoRoute(
                  path: ':${Routes.pDateKey}',
                  builder: (context, state) => CalendarScreen(
                    initialDay: _dateKeyParam(
                      state.pathParameters[Routes.pDateKey],
                    ),
                  ),
                ),
              ],
            ),
            GoRoute(
              path: Routes.insights,
              builder: (context, state) => const AnalyticsHomeScreen(),
            ),
            GoRoute(
              path: Routes.settings,
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
        GoRoute(
          path: Routes.transactionNew,
          builder: (context, state) => const TransactionEditorScreen(),
        ),
        GoRoute(
          path: Routes.transactionLinesNew,
          builder: (context, state) => const LineItemsScreen(),
        ),
        GoRoute(
          path: Routes.transactionLinesPattern,
          builder: (context, state) => LineItemsScreen(
            transactionId: state.pathParameters[Routes.pTransactionId],
          ),
        ),
        GoRoute(
          path: Routes.transactionEditPattern,
          builder: (context, state) => TransactionEditorScreen(
            transactionId: state.pathParameters[Routes.pTransactionId],
          ),
        ),
        GoRoute(
          path: Routes.transactionDetailPattern,
          builder: (context, state) => TransactionDetailScreen(
            transactionId: state.pathParameters[Routes.pTransactionId]!,
          ),
        ),
        GoRoute(
          path: Routes.itemNew,
          builder: (context, state) => const ItemEditorScreen(),
        ),
        GoRoute(
          path: Routes.batchNewPattern,
          builder: (context, state) => BatchEditorScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
          ),
        ),
        GoRoute(
          path: Routes.batchHistoryPattern,
          builder: (context, state) => BatchHistoryScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
            batchId: state.pathParameters[Routes.pBatchId]!,
          ),
        ),
        GoRoute(
          path: Routes.batchEditPattern,
          builder: (context, state) => BatchEditorScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
            batchId: state.pathParameters[Routes.pBatchId],
          ),
        ),
        GoRoute(
          path: Routes.itemEditPattern,
          builder: (context, state) => ItemEditorScreen(
            itemId: state.pathParameters[Routes.pItemId],
          ),
        ),
        GoRoute(
          path: Routes.itemDetailPattern,
          builder: (context, state) => ItemDetailScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingConvertPattern,
          builder: (context, state) => ConvertToPurchaseScreen(
            listId: state.pathParameters[Routes.pListId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingListPattern,
          builder: (context, state) => ShoppingListScreen(
            listId: state.pathParameters[Routes.pListId],
          ),
        ),
        GoRoute(
          path: Routes.recurringNew,
          builder: (context, state) => const TemplateBuilderScreen(),
        ),
        GoRoute(
          path: Routes.recurringHistoryPattern,
          builder: (context, state) => OccurrenceHistoryScreen(
            templateId: state.pathParameters[Routes.pTemplateId]!,
          ),
        ),
        GoRoute(
          path: Routes.recurringEditPattern,
          builder: (context, state) => TemplateBuilderScreen(
            templateId: state.pathParameters[Routes.pTemplateId],
          ),
        ),
        GoRoute(
          path: Routes.recurringDetailPattern,
          builder: (context, state) => OccurrenceHistoryScreen(
            templateId: state.pathParameters[Routes.pTemplateId]!,
          ),
        ),
        GoRoute(
          path: Routes.assetNew,
          builder: (context, state) => const AssetEditorScreen(),
        ),
        GoRoute(
          path: Routes.serviceNewPattern,
          builder: (context, state) => ServiceEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
          ),
        ),
        GoRoute(
          path: Routes.serviceEditPattern,
          builder: (context, state) => ServiceEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
            recordId: state.pathParameters[Routes.pRecordId],
          ),
        ),
        GoRoute(
          path: Routes.assetEditPattern,
          builder: (context, state) => AssetEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId],
          ),
        ),
        GoRoute(
          path: Routes.assetDetailPattern,
          builder: (context, state) => AssetDetailScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
          ),
        ),
        GoRoute(
          path: Routes.insightsDrillDownPattern,
          builder: (context, state) => DrillDownScreen(
            // Parsed rather than trusted: this route is deep-linkable, so an unknown axis has to reach
            // the screen as null and be explained there rather than throwing in a builder.
            spec: DrillDownSpec.parse(
              kind: state.pathParameters[Routes.pDrillKind],
              value: state.pathParameters[Routes.pDrillValue],
            ),
          ),
        ),
        GoRoute(
          path: Routes.themeLab,
          builder: (context, state) => _DetailScaffold(
            title: AlayaStrings.of(context).navThemeLab,
            child: const ThemeLabScreen(),
          ),
        ),
        // **Every settings branch sits outside the shell.** `/settings` is the drawer destination; its
        // children are reached *from* it and need a back arrow, which a shell owning a drawer can never
        // imply (Law U18). Each one brings its own `Scaffold` and app bar, so none uses
        // `_DetailScaffold` — a catalogue needs a pinned search field and an overflow of its own, which
        // that wrapper does not offer (ARCH_5 §3 archetype D).
        //
        // The literal children of `/settings/accounts`, `/settings/tags` and `/settings/units` are
        // declared before their parameterised siblings, or `:accountId` swallows the word `new`.
        GoRoute(
          path: Routes.accountNew,
          builder: (context, state) => const AccountEditorScreen(),
        ),
        GoRoute(
          path: Routes.accountEditPattern,
          builder: (context, state) => AccountEditorScreen(
            accountId: state.pathParameters[Routes.pAccountId],
          ),
        ),
        GoRoute(
          path: Routes.settingsAccounts,
          builder: (context, state) => const AccountsSettingsScreen(),
        ),
        GoRoute(
          path: Routes.tagNew,
          builder: (context, state) => const TagEditorScreen(),
        ),
        GoRoute(
          path: Routes.tagEditPattern,
          builder: (context, state) => TagEditorScreen(
            tagId: state.pathParameters[Routes.pTagId],
          ),
        ),
        GoRoute(
          path: Routes.settingsTags,
          builder: (context, state) => const TagsSettingsScreen(),
        ),
        GoRoute(
          path: Routes.unitNew,
          builder: (context, state) => const UnitEditorScreen(),
        ),
        GoRoute(
          path: Routes.unitEditPattern,
          builder: (context, state) => UnitEditorScreen(
            unitCode: state.pathParameters[Routes.pUnitCode],
          ),
        ),
        GoRoute(
          path: Routes.settingsUnits,
          builder: (context, state) => const UnitsSettingsScreen(),
        ),
        GoRoute(
          path: Routes.settingsPaymentMethods,
          builder: (context, state) => const PaymentMethodsSettingsScreen(),
        ),
        GoRoute(
          path: Routes.settingsPayees,
          builder: (context, state) => const PayeesSettingsScreen(),
        ),
        GoRoute(
          path: Routes.settingsCurrencies,
          builder: (context, state) => const CurrenciesSettingsScreen(),
        ),
        GoRoute(
          path: Routes.settingsAppearance,
          builder: (context, state) => const AppearanceSettingsScreen(),
        ),
        // `/settings/security/pin` before `/settings/security`, for the same ordering reason.
        GoRoute(
          path: Routes.settingsPin,
          builder: (context, state) => const PinSetupFlow(),
        ),
        GoRoute(
          path: Routes.settingsSecurity,
          builder: (context, state) => const SecuritySettingsScreen(),
        ),
        GoRoute(
          path: Routes.settingsData,
          builder: (context, state) => const DataSettingsScreen(),
        ),
        GoRoute(
          path: Routes.settingsAbout,
          builder: (context, state) => const AboutSettingsScreen(),
        ),
        // Phase 8B. `/settings/data/backup/restore` before `/settings/data/backup`, and both before
        // `/settings/data`, for the same first-match reason every other nesting here has.
        GoRoute(
          path: Routes.settingsRestore,
          builder: (context, state) => const RestoreFlow(),
        ),
        GoRoute(
          path: Routes.settingsBackup,
          builder: (context, state) => const BackupScreen(),
        ),
        GoRoute(
          path: Routes.settingsTrash,
          builder: (context, state) => const TrashScreen(),
        ),
        GoRoute(
          path: Routes.settingsReminders,
          builder: (context, state) => const RemindersScreen(),
        ),
        GoRoute(
          path: Routes.support,
          builder: (context, state) => const SupportScreen(),
        ),
      ],
    );
  }
}

class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // `AppBar` resolves its implied leading by checking `hasDrawer` **before** `canPop`, so a shell that
    // owns a drawer can never show a back arrow no matter how it was reached. That is fine for a drawer
    // destination switched into as a peer, and wrong for one pushed as a drill-down — and both happen
    // here: the drawer `go`es, the dashboard's module grid `push`es.
    //
    // So the slot is stated rather than implied. Pushed: a back arrow that pops the shell's own navigator
    // (`context.pop`, not `Navigator.maybePop`, which from above the shell navigator would target the root
    // one and do nothing). Switched into: null, which lets the hamburger be implied as before.
    //
    // The drawer stays attached either way, so the edge swipe still opens it on a pushed screen.
    final strings = AlayaStrings.of(context);

    // **Read from the router, not from the builder's `state`.** `ShellRoute` declares no `path`, so the
    // `GoRouterState` handed to its builder describes the *shell's* match rather than the leaf's — and a
    // pathless route's `matchedLocation` is its parent's, which here is `/`. Every screen inside the shell
    // therefore looked like the dashboard: `atDashboard` was permanently true so the home action never
    // rendered, `AlayaDrawer` highlighted Dashboard wherever you were, and `titleFor` named it too.
    //
    // `currentConfiguration` is the delegate's live `RouteMatchList`, so its `uri` is the leaf location no
    // matter which builder asks.
    final here = GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;

    // **`context.canPop()` cannot answer this question from here.** This widget is the `ShellRoute`
    // builder, so its context sits *above* the shell's own `Navigator`; `canPop` resolves against the
    // root navigator, which only ever holds the shell itself. It therefore returns false however the
    // screen was reached, `leading` was always null, and the back arrow this once tried to show could
    // never appear. The drawer's hamburger was the only leading widget users ever saw, and from a module
    // the sole way home was the system back gesture.
    //
    // So the way home is stated outright instead of inferred from a stack this context cannot see: every
    // shell screen except the dashboard carries a home action. It pops when there is something to pop and
    // navigates otherwise, so arriving by the module grid's `push` and by the drawer's `go` both end up
    // in the same place — and the hamburger keeps its slot, because the drawer is still how you move
    // between peers (Law U27).
    return Scaffold(
      drawer: AlayaDrawer(currentLocation: here),
      appBar: AppBar(
        title: Text(AlayaDrawer.titleFor(context, here)),
        // **Unconditional, deliberately.** This was `if (!atDashboard)` and never appeared, and rather
        // than reason about why a condition is false I would rather the button exist and be seen. It
        // shows on the dashboard too, where it is merely redundant — a redundant button is a far smaller
        // fault than a missing one, and its presence there is also the proof that this file is live.
        //
        // Once it is confirmed visible, `if (!atDashboard)` can come back.
        actions: [
          IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(Routes.dashboard),
            tooltip: strings.navBackToDashboard,
            icon: const Icon(Icons.home_outlined, size: AlayaIconSize.md),
          ),
          // **Beside the home button, and it loads nothing until pressed.** ARCH_4 §5.1 said rewarded ads live
          // "only in Support Us"; this amends the entry point and keeps the constraint — no `MobileAds`
          // initialisation, no consent fetch and no ad request happen on build, so a user who never taps it never
          // has an advertising identifier collected.
          const SupportAction(),
        ],
      ),
      body: child,
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: child,
  );
}

/// Parses a `:dateKey` path parameter, or null when it is absent or not a date key.
///
/// A malformed deep link opens the calendar on today rather than throwing — the route is reachable
/// from outside the app.
DateKey? _dateKeyParam(String? raw) {
  final value = int.tryParse(raw ?? '');
  if (value == null) return null;

  final year = value ~/ 10000;
  final month = (value ~/ 100) % 100;
  final day = value % 100;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  // Round-trip through `fromYmd`, which normalises overflow through `DateTime.utc`: 20260230 comes
  // back as 20260302 and fails this check, where a digit-range test alone would accept it.
  final probe = DateKey.fromYmd(year, month, day);
  return probe.value == value ? probe : null;
}
```

## `app_en.arb`

**1,121 message keys, up from 995.** The 126 additions were extracted from the call sites rather than written
from memory — the only way to guarantee both directions at once: no key referenced that does not exist, and no key
added that nothing uses. Verified as **exactly 126, no missing and no surplus**, with every `strings.*` in this
phase resolving.

**Two arities were inflated by trailing commas**, the same over-count 8A produced: a multi-line call with a
trailing comma reads as one argument more than it takes. `remindersTimeBody` takes one and `restoreNewerSchema`
takes two; both were read off the call sites and then asserted against them.

### A correction to 8A, and it is the one that mattered most

`backupNotEncryptedWarning` shipped in 8A as a paraphrase:

> This backup is not encrypted. Anyone who **receives the file** can read every account, balance and transaction
> **in it**.

ARCH_3 §3.4's canonical text is:

> This backup is not encrypted. Anyone who **opens this file** can read every transaction, balance and account
> name. **Only share it somewhere you trust.**

The third sentence was missing entirely, and it is the actionable one — the first two describe a risk, the third
says what to do about it. It is corrected here, which means **every export confirmation in 8A and 8B now carries
§3.4 verbatim**.

Worth naming how it survived: in 8A I wrote that string from memory, then quoted my own version back approvingly
in the phase notes as evidence the requirement was met. Nothing caught it until this phase read §3.4 directly. A
requirement checked against one's own paraphrase is not checked.

### `lib/app/l10n/app_en.arb`

```json
{
  "@@locale": "en",
  "appName": "Alaya",
  "@appName": {
    "description": "The app's name, shown in the drawer header."
  },
  "navDashboard": "Dashboard",
  "navExpenses": "Expenses",
  "navInventory": "Inventory",
  "navShopping": "Shopping",
  "navRecurring": "Recurring",
  "navServices": "Services",
  "navCalendar": "Calendar",
  "navInsights": "Insights",
  "navSettings": "Settings",
  "navThemeLab": "Theme Lab",
  "actionSave": "Save",
  "@actionSave": {
    "description": "Commits an edit. Active voice, and the same word appears in the resulting confirmation."
  },
  "actionSaved": "Saved",
  "actionCancel": "Cancel",
  "actionDelete": "Delete",
  "actionDeleted": "Deleted",
  "actionUndo": "Undo",
  "actionRetry": "Try again",
  "actionAdd": "Add",
  "actionEdit": "Edit",
  "actionDone": "Done",
  "actionClose": "Close",
  "actionSelect": "Select",
  "actionClear": "Clear",
  "actionClearAll": "Clear all",
  "actionSearch": "Search",
  "actionConfirm": "Confirm",
  "actionDiscard": "Discard",
  "actionKeepEditing": "Keep editing",
  "actionRemoveTag": "Remove tag",
  "@actionRemoveTag": {
    "description": "Accessibility label for the dismiss affordance on a removable tag chip."
  },
  "actionClearSearch": "Clear search",
  "@actionClearSearch": {
    "description": "Accessibility label for the clear button inside AlayaSearchField."
  },
  "addExpense": "Add expense",
  "addIncome": "Add income",
  "addTransfer": "Add transfer",
  "addItem": "Add item",
  "addToShoppingList": "Add to shopping list",
  "dateToday": "Today",
  "@dateToday": {
    "description": "DateText.relative, when the date is the clock's today. Sentence case; it can begin a row."
  },
  "dateYesterday": "Yesterday",
  "dateTomorrow": "Tomorrow",
  "emptyTitleNoTransactions": "No transactions yet",
  "emptyBodyNoTransactions": "Add your first expense and it will appear here.",
  "@emptyBodyNoTransactions": {
    "description": "An empty screen is an invitation to act, so this names the action rather than describing the emptiness."
  },
  "emptyTitleNoItems": "Nothing in your inventory",
  "emptyBodyNoItems": "Add an item to start tracking what you have at home.",
  "emptyTitleNoShopping": "Your list is empty",
  "emptyBodyNoShopping": "Add something, or let Alaya suggest items you are low on.",
  "emptyTitleNoRecurring": "No recurring bills",
  "emptyBodyNoRecurring": "Set up a bill or subscription and Alaya will remind you when it is due.",
  "emptyTitleNoResults": "No matches",
  "emptyBodyNoResults": "Try a shorter search, or check the spelling.",
  "loadingLabel": "Loading",
  "loadingTransactions": "Loading transactions",
  "errorTitleGeneric": "That did not work",
  "@errorTitleGeneric": {
    "description": "Errors do not apologise and are never vague. This pairs with a specific body message."
  },
  "errorBodyGeneric": "Something went wrong on our side. Try again.",
  "errorTitleNotFound": "Not found",
  "errorBodyNotFound": "This item may have been deleted.",
  "errorBodyNoConnection": "You are offline. Alaya works offline, but rates will not refresh.",
  "errorFieldRequired": "This is required",
  "errorAmountInvalid": "Enter an amount",
  "errorAmountZero": "Enter an amount greater than zero",
  "errorAmountInvalidCharacter": "Digits only",
  "errorAmountNegativeNotAllowed": "Enter a positive amount",
  "errorAmountTooManyDecimals": "Too many decimal places",
  "errorAmountTooLarge": "That amount is too large",
  "errorQuantityTooLarge": "That quantity is too large",
  "errorQuantityInvalid": "Enter a quantity",
  "errorQuantityInvalidCharacter": "Digits only",
  "errorQuantityNegativeNotAllowed": "Enter a positive quantity",
  "errorQuantityTooPrecise": "Too precise for this unit",
  "@errorQuantityTooPrecise": {
    "description": "The typed quantity is finer than the chosen unit can express exactly. Shown rather than rounded, because rounding a quantity silently changes what the user recorded."
  },
  "errorDateInvalid": "Choose a date",
  "confirmDeleteTitle": "Delete this?",
  "confirmDeleteBody": "You can undo this for the next few seconds.",
  "confirmDiscardTitle": "Discard your changes?",
  "confirmDiscardBody": "What you have typed will not be saved.",
  "labelAmount": "Amount",
  "labelQuantity": "Quantity",
  "labelUnit": "Unit",
  "labelDate": "Date",
  "labelAccount": "Account",
  "labelPaymentMethod": "Payment method",
  "labelPayee": "Payee",
  "labelCategory": "Category",
  "labelTags": "Tags",
  "labelNote": "Note",
  "labelFrom": "From",
  "labelTo": "To",
  "labelItem": "Item",
  "labelExpiry": "Expiry",
  "labelTotal": "Total",
  "hintSelectAccount": "Choose an account",
  "hintSelectUnit": "Choose a unit",
  "hintSelectTags": "Choose tags",
  "hintSelectDate": "Choose a date",
  "hintSearchItems": "Search items",
  "hintNote": "Add a note",
  "amountUnconverted": "{count, plural, =1{1 amount not converted} other{{count} amounts not converted}}",
  "@amountUnconverted": {
    "description": "The chip beside a total when some amounts had no exchange rate. Surfaced rather than hidden, because a total missing a row is otherwise indistinguishable from a complete one.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "amountApproximate": "Approximate rate",
  "@amountApproximate": {
    "description": "Shown when a conversion used the nearest earlier rate rather than the exact date's."
  },
  "tagCountMore": "+{count}",
  "@tagCountMore": {
    "description": "Overflow indicator when a row cannot show every tag.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "statusNeedsReview": "Needs details",
  "@statusNeedsReview": {
    "description": "StatusChip on a transaction saved by quick-add. Names what is missing, not that a flag is set."
  },
  "statusUnallocated": "Unallocated",
  "@statusUnallocated": {
    "description": "StatusChip label when a transaction's lines do not sum to its amount. The figure is a separate AmountText (U7); never auto-balanced (anomaly A11)."
  },
  "statusDetached": "Receipt deleted",
  "@statusDetached": {
    "description": "StatusChip on a batch whose source transaction was deleted. The food did not un-exist."
  },
  "statusApproximate": "Approximate",
  "lowStockLabel": "Low",
  "expiringSoonLabel": "Expiring soon",
  "expiredLabel": "Expired",
  "overdueLabel": "Overdue",
  "dueTodayLabel": "Due today",
  "paidLabel": "Paid",
  "skippedLabel": "Skipped",
  "kindDeposit": "Money in",
  "kindWithdrawal": "Money out",
  "kindTransfer": "Transfer",
  "kindAdjustmentIncrease": "Correction up",
  "kindAdjustmentDecrease": "Correction down",
  "subtypeGrocery": "Groceries",
  "subtypeHousehold": "Household",
  "subtypeElectronics": "Electronics",
  "subtypeBill": "Bill",
  "subtypeTransferSelf": "Between my accounts",
  "subtypeTransferOut": "Sent to someone",
  "subtypeSalaryIn": "Salary",
  "subtypeOtherIn": "Other income",
  "subtypeOtherOut": "Other spending",
  "needsReviewBanner": "{count, plural, =1{1 transaction needs details} other{{count} transactions need details}}",
  "@needsReviewBanner": {
    "description": "Surfaces transactions.needsReview. Quick-add saves an amount and nothing else by design; without this row that deliberate shortcut becomes silent data rot.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "needsReviewAction": "Review",
  "filterTitle": "Filter",
  "filterDateRange": "Date range",
  "filterKind": "Type",
  "filterSubtype": "Category",
  "filterApply": "Show results",
  "filterReset": "Reset",
  "filterChipAccount": "Account: {name}",
  "@filterChipAccount": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "filterChipPayee": "Payee: {name}",
  "@filterChipPayee": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "filterChipRange": "{label}",
  "@filterChipRange": {
    "placeholders": {
      "label": {
        "type": "String"
      }
    }
  },
  "rangeToday": "Today",
  "rangeLast7Days": "Last 7 days",
  "rangeLast30Days": "Last 30 days",
  "rangeThisMonth": "This month",
  "rangeLastMonth": "Last month",
  "rangeThisYear": "This year",
  "rangeAllTime": "All time",
  "rangeCustom": "Custom",
  "searchTransactionsHint": "Search notes",
  "transactionDeleted": "Transaction deleted",
  "quickAddTitle": "Quick add",
  "quickAddMoneyIn": "Money in",
  "quickAddMoneyOut": "Money out",
  "quickAddSave": "Save",
  "actionAddDetails": "Add details",
  "editorTitleNew": "New transaction",
  "editorTitleEdit": "Edit transaction",
  "sectionWhatAndHowMuch": "What and how much",
  "sectionWhereItCameFrom": "Where it came from",
  "sectionWhereItWent": "Where it went",
  "sectionWhatYouBought": "What you bought",
  "sectionWarranty": "Warranty",
  "sectionSchedule": "Schedule",
  "transferOwnAccount": "To my own account",
  "transferSomeoneElse": "To someone else",
  "transferOwnAccountHelp": "Moves money between your accounts. Your total does not change.",
  "transferSomeoneElseHelp": "Money leaves your accounts. This is a withdrawal.",
  "alsoAddToInventory": "Also add to inventory",
  "destinationNone": "Just an expense",
  "destinationInventory": "Save to Inventory",
  "destinationAsset": "Save to Services",
  "destinationRecurring": "Save to Recurring",
  "lineAdd": "Add item",
  "lineDescription": "Item",
  "lineUnitPrice": "Unit price",
  "lineAmount": "Line total",
  "lineCreatedLink": "Created: {name}",
  "@lineCreatedLink": {
    "description": "Surfaces transaction_lines.created*Id — the artefact this line produced, tappable through to it.",
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "payeeCreate": "New payee “{name}”",
  "@payeeCreate": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "saveExpense": "Save expense",
  "saveIncome": "Save income",
  "saveTransfer": "Save transfer",
  "detailSectionLines": "Items",
  "detailSectionDetails": "Details",
  "actionFreezeConversion": "Show in another currency",
  "frozenConversionNote": "Frozen on {date} at {rate}",
  "@frozenConversionNote": {
    "description": "Surfaces transactions.converted*/conversionRateRaw. A separate artefact that is never recomputed (Law L9).",
    "placeholders": {
      "date": {
        "type": "String"
      },
      "rate": {
        "type": "String"
      }
    }
  },
  "deleteReasonHint": "Why? (optional)",
  "actionDeleteTransaction": "Delete transaction",
  "labelSubtype": "Category",
  "labelKind": "Type",
  "themeLabTitle": "Theme Lab",
  "themeLabSubtitle": "Every token, component and semantic colour, light and dark.",
  "themeLabSectionSpacing": "Spacing",
  "themeLabSectionRadii": "Radii",
  "themeLabSectionTypography": "Typography",
  "themeLabSectionElevation": "Elevation",
  "themeLabSectionSemantic": "Semantic colours",
  "themeLabSectionSurfaces": "Surface tiers",
  "themeLabSectionComponents": "Components",
  "themeLabSectionPalettes": "Palettes",
  "themeLabLight": "Light",
  "themeLabDark": "Dark",
  "semanticIncome": "Income",
  "semanticExpense": "Expense",
  "semanticTransfer": "Transfer",
  "semanticWarning": "Warning",
  "semanticDanger": "Danger",
  "semanticSuccess": "Success",
  "semanticMuted": "Muted",
  "drawerSectionMoney": "Money",
  "drawerSectionHome": "Home",
  "drawerSectionMore": "More",
  "inventoryGroupFavourites": "Favourites",
  "@inventoryGroupFavourites": {
    "description": "Phase 6B — inventory."
  },
  "inventoryGroupUntagged": "Everything else",
  "@inventoryGroupUntagged": {
    "description": "Phase 6B — inventory."
  },
  "itemKindGeneric": "General",
  "@itemKindGeneric": {
    "description": "Phase 6B — inventory."
  },
  "itemKindFood": "Food",
  "@itemKindFood": {
    "description": "Phase 6B — inventory."
  },
  "itemKindMedicine": "Medicine",
  "@itemKindMedicine": {
    "description": "Phase 6B — inventory."
  },
  "itemKindBeauty": "Beauty",
  "@itemKindBeauty": {
    "description": "Phase 6B — inventory."
  },
  "itemKindHousehold": "Household",
  "@itemKindHousehold": {
    "description": "Phase 6B — inventory."
  },
  "itemKindOther": "Other",
  "@itemKindOther": {
    "description": "Phase 6B — inventory."
  },
  "filterFavouritesOnly": "Favourites only",
  "@filterFavouritesOnly": {
    "description": "Phase 6B — inventory."
  },
  "actionFavourite": "Add to favourites",
  "@actionFavourite": {
    "description": "Phase 6B — inventory."
  },
  "actionUnfavourite": "Remove from favourites",
  "@actionUnfavourite": {
    "description": "Phase 6B — inventory."
  },
  "outOfStockLabel": "Out of stock",
  "@outOfStockLabel": {
    "description": "Phase 6B — inventory."
  },
  "itemBatchCount": "{count, plural, =1{1 batch} other{{count} batches}}",
  "@itemBatchCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "loadingInventory": "Loading inventory",
  "@loadingInventory": {
    "description": "Phase 6B — inventory."
  },
  "detailSectionBatches": "Batches",
  "@detailSectionBatches": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginPurchase": "From a purchase",
  "@batchOriginPurchase": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginManual": "Added by hand",
  "@batchOriginManual": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginImported": "Imported",
  "@batchOriginImported": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginAdjustment": "From an adjustment",
  "@batchOriginAdjustment": {
    "description": "Phase 6B — inventory."
  },
  "labelPurchased": "Purchased",
  "@labelPurchased": {
    "description": "Phase 6B — inventory."
  },
  "labelStorageLocation": "Stored in",
  "@labelStorageLocation": {
    "description": "Phase 6B — inventory."
  },
  "labelUnitCost": "Unit cost",
  "@labelUnitCost": {
    "description": "Phase 6B — inventory."
  },
  "labelInitial": "Bought",
  "@labelInitial": {
    "description": "Phase 6B — inventory."
  },
  "labelNearestExpiry": "Nearest expiry",
  "@labelNearestExpiry": {
    "description": "Phase 6B — inventory."
  },
  "labelDisplayUnit": "Shown in",
  "@labelDisplayUnit": {
    "description": "Phase 6B — inventory."
  },
  "labelItemKind": "Kind",
  "@labelItemKind": {
    "description": "Phase 6B — inventory."
  },
  "labelLowStockThreshold": "Low-stock level",
  "@labelLowStockThreshold": {
    "description": "Phase 6B — inventory."
  },
  "labelExpiryNotifyDays": "Warn before expiry",
  "@labelExpiryNotifyDays": {
    "description": "Phase 6B — inventory."
  },
  "actionConsume": "Use some",
  "@actionConsume": {
    "description": "Phase 6B — inventory."
  },
  "actionAddBatch": "Add a batch",
  "@actionAddBatch": {
    "description": "Phase 6B — inventory."
  },
  "actionViewHistory": "Movement history",
  "@actionViewHistory": {
    "description": "Phase 6B — inventory."
  },
  "actionDeleteItem": "Delete item",
  "@actionDeleteItem": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteItemTitle": "Delete this item?",
  "@confirmDeleteItemTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteItemBody": "Its {count, plural, =1{1 batch} other{{count} batches}} go with it. The movement history stays, so what you already used is still recorded.",
  "@confirmDeleteItemBody": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "itemDeleted": "Item deleted",
  "@itemDeleted": {
    "description": "Phase 6B — inventory."
  },
  "expiresInDays": "{days, plural, =0{Expires today} =1{Expires tomorrow} other{Expires in {days} days}}",
  "@expiresInDays": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "expiredDaysAgo": "{days, plural, =1{Expired yesterday} other{Expired {days} days ago}}",
  "@expiredDaysAgo": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "sectionWhatItIs": "What it is",
  "@sectionWhatItIs": {
    "description": "Phase 6B — inventory."
  },
  "sectionStockRules": "Stock rules",
  "@sectionStockRules": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryWeight": "Weight",
  "@unitCategoryWeight": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryVolume": "Volume",
  "@unitCategoryVolume": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryCount": "Count",
  "@unitCategoryCount": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryLocked": "Measured in {category}",
  "@unitCategoryLocked": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "category": {}
    }
  },
  "unitCategoryLockedHelp": "This cannot change. Every batch and movement already recorded is stored in this measure, and there is no conversion between weight, volume and count.",
  "@unitCategoryLockedHelp": {
    "description": "Phase 6B — inventory."
  },
  "expiryNotifyDaysHelp": "Days of warning before a batch expires.",
  "@expiryNotifyDaysHelp": {
    "description": "Phase 6B — inventory."
  },
  "labelFavourite": "Favourite",
  "@labelFavourite": {
    "description": "Phase 6B — inventory."
  },
  "saveItem": "Save item",
  "@saveItem": {
    "description": "Phase 6B — inventory."
  },
  "sectionHowMuch": "How much",
  "@sectionHowMuch": {
    "description": "Phase 6B — inventory."
  },
  "sectionBatchDetails": "Batch details",
  "@sectionBatchDetails": {
    "description": "Phase 6B — inventory."
  },
  "saveBatch": "Save batch",
  "@saveBatch": {
    "description": "Phase 6B — inventory."
  },
  "batchSaved": "Batch saved",
  "@batchSaved": {
    "description": "Phase 6B — inventory."
  },
  "hintStorageLocation": "Freezer, pantry, bathroom shelf…",
  "@hintStorageLocation": {
    "description": "Phase 6B — inventory."
  },
  "consumeTitle": "Use stock",
  "@consumeTitle": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindConsume": "Used",
  "@consumeKindConsume": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindWaste": "Thrown away",
  "@consumeKindWaste": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindExpired": "Expired",
  "@consumeKindExpired": {
    "description": "Phase 6B — inventory."
  },
  "consumeRecorded": "Recorded",
  "@consumeRecorded": {
    "description": "Phase 6B — inventory."
  },
  "consumeFromLabel": "Taking from",
  "@consumeFromLabel": {
    "description": "Phase 6B — inventory."
  },
  "consumeFefoNote": "Oldest expiry first.",
  "@consumeFefoNote": {
    "description": "Phase 6B — inventory."
  },
  "consumeSpansBatches": "{count, plural, =1{Takes all of 1 batch} other{Spans {count} batches, writing {count} movements}}",
  "@consumeSpansBatches": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "consumeOverAvailable": "More than you have on hand",
  "@consumeOverAvailable": {
    "description": "Phase 6B — inventory."
  },
  "historyTitle": "Movement history",
  "@historyTitle": {
    "description": "Phase 6B — inventory."
  },
  "movementKindOpeningIn": "Opening stock",
  "@movementKindOpeningIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindPurchaseIn": "Bought",
  "@movementKindPurchaseIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindManualIn": "Added by hand",
  "@movementKindManualIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindConsume": "Used",
  "@movementKindConsume": {
    "description": "Phase 6B — inventory."
  },
  "movementKindWaste": "Thrown away",
  "@movementKindWaste": {
    "description": "Phase 6B — inventory."
  },
  "movementKindExpired": "Expired",
  "@movementKindExpired": {
    "description": "Phase 6B — inventory."
  },
  "movementKindAdjustIn": "Adjusted up",
  "@movementKindAdjustIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindAdjustOut": "Adjusted down",
  "@movementKindAdjustOut": {
    "description": "Phase 6B — inventory."
  },
  "movementReversed": "Reversed",
  "@movementReversed": {
    "description": "Phase 6B — inventory."
  },
  "movementIsReversal": "Reverses an earlier movement",
  "@movementIsReversal": {
    "description": "Phase 6B — inventory."
  },
  "actionReverse": "Reverse",
  "@actionReverse": {
    "description": "Phase 6B — inventory."
  },
  "confirmReverseTitle": "Reverse this movement?",
  "@confirmReverseTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmReverseBody": "An opposite movement is appended. Nothing is erased — both entries stay in the history.",
  "@confirmReverseBody": {
    "description": "Phase 6B — inventory."
  },
  "movementReversedSnack": "Movement reversed",
  "@movementReversedSnack": {
    "description": "Phase 6B — inventory."
  },
  "emptyTitleNoMovements": "Nothing recorded yet",
  "@emptyTitleNoMovements": {
    "description": "Phase 6B — inventory."
  },
  "emptyBodyNoMovements": "Using, wasting or adjusting this batch will show up here.",
  "@emptyBodyNoMovements": {
    "description": "Phase 6B — inventory."
  },
  "emptyBodyNoBatches": "Add a batch and it will appear here with its expiry.",
  "@emptyBodyNoBatches": {
    "description": "Phase 6B — inventory."
  },
  "batchQuantityLockedHelp": "How much is left is worked out from the movement history. Use, waste or adjust the batch to change it.",
  "@batchQuantityLockedHelp": {
    "description": "Phase 6B — inventory."
  },
  "daysCount": "{days, plural, =1{1 day} other{{days} days}}",
  "@daysCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "groupByFavourites": "Group favourites first",
  "@groupByFavourites": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitUsed": "Record as used",
  "@consumeCommitUsed": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitWaste": "Record as thrown away",
  "@consumeCommitWaste": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitExpired": "Record as expired",
  "@consumeCommitExpired": {
    "description": "Phase 6B — inventory."
  },
  "lowStockWithCount": "Low · {count}",
  "@lowStockWithCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "actionDeleteBatch": "Delete batch",
  "@actionDeleteBatch": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteBatchTitle": "Delete this batch?",
  "@confirmDeleteBatchTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteBatchBody": "The stock it still holds disappears from your on-hand total. What you already used stays in the movement history.",
  "@confirmDeleteBatchBody": {
    "description": "Phase 6B — inventory."
  },
  "batchDeleted": "Batch deleted",
  "@batchDeleted": {
    "description": "Phase 6B — inventory."
  },
  "itemCreate": "New item",
  "@itemCreate": {
    "description": "Creates a catalogued item inline while itemising a receipt."
  },
  "itemCreateHint": "No items yet — create one so this line becomes stock.",
  "@itemCreateHint": {
    "description": "Shown in the line editor when the item catalogue is empty."
  },
  "itemCreateCategoryPrompt": "How is it measured? This cannot change later.",
  "@itemCreateCategoryPrompt": {
    "description": "Prompt for unitCategory on inline creation; immutable after create (Law L8)."
  },
  "itemDuplicateBody": "You already have this item, measured the same way. Open the one you have instead of adding a second.",
  "@itemDuplicateBody": {
    "description": "Shown when an item with the same normalized name and unit category exists."
  },
  "itemUnitsMissingBody": "No units are set up for this measure yet. Pick a different measure, or add units in Settings first.",
  "@itemUnitsMissingBody": {
    "description": "Shown when the chosen UnitCategory has no rows in units."
  },
  "itemSimilarNote": "You also have this name under a different measure. That is fine — weight, volume and count never convert into each other.",
  "@itemSimilarNote": {
    "description": "Informational note, never a block: Law L8 makes same-name/different-category distinct items."
  },
  "actionOpenExisting": "Open the one I have",
  "@actionOpenExisting": {
    "description": "Opens the existing item a duplicate collides with."
  },
  "shoppingEstimate": "Estimated",
  "@shoppingEstimate": {
    "description": "Running total of estimated prices on a shopping list."
  },
  "shoppingSwitchList": "Switch list",
  "@shoppingSwitchList": {
    "description": "Opens the list manager from the app bar."
  },
  "shoppingCheckedCount": "{checked} of {total} ticked",
  "@shoppingCheckedCount": {
    "description": "Progress line above a shopping list.",
    "placeholders": {
      "checked": {},
      "total": {}
    }
  },
  "emptyTitleNoEntries": "Nothing on this list yet",
  "@emptyTitleNoEntries": {
    "description": "Shopping list empty state."
  },
  "emptyBodyNoEntries": "Add what you need, or pull in suggestions from what is running low.",
  "@emptyBodyNoEntries": {
    "description": "Shopping list empty state body."
  },
  "addEntry": "Add",
  "@addEntry": {
    "description": "Adds one entry to a shopping list."
  },
  "shoppingGroupUntagged": "Everything else",
  "@shoppingGroupUntagged": {
    "description": "Header for entries with no tag."
  },
  "actionUncheckAll": "Untick everything",
  "@actionUncheckAll": {
    "description": "Clears every tick on a shopping list."
  },
  "entryEditorTitle": "What do you need?",
  "@entryEditorTitle": {
    "description": "Entry editor sheet title."
  },
  "entryFreeTextLabel": "Name it",
  "@entryFreeTextLabel": {
    "description": "Free-text label for a shopping entry."
  },
  "entryFreeTextHint": "Television, birthday card, light bulbs…",
  "@entryFreeTextHint": {
    "description": "Hint showing that an entry need not be an inventory item."
  },
  "entryLinkItem": "Link to an item",
  "@entryLinkItem": {
    "description": "Optional link from a shopping entry to a catalogued item."
  },
  "entryNoItem": "Not in my inventory",
  "@entryNoItem": {
    "description": "Dropdown option leaving itemId null."
  },
  "labelEstimatedPrice": "Estimated price",
  "@labelEstimatedPrice": {
    "description": "Optional per-entry price estimate."
  },
  "entryNeedsSomething": "Give it a name, or link it to an item",
  "@entryNeedsSomething": {
    "description": "Rejection when neither freeText nor itemId is set."
  },
  "originAutoLowStock": "Suggested",
  "@originAutoLowStock": {
    "description": "Chip marking an auto-generated low-stock entry."
  },
  "originPromoted": "Yours now",
  "@originPromoted": {
    "description": "Chip shown once an auto entry has been edited into a manual one."
  },
  "actionSnooze": "Snooze a week",
  "@actionSnooze": {
    "description": "Hides an auto suggestion until a later date."
  },
  "actionDismiss": "Not now",
  "@actionDismiss": {
    "description": "Dismisses an auto suggestion until stock recovers and drops again."
  },
  "snoozedUntilLabel": "Snoozed until",
  "@snoozedUntilLabel": {
    "description": "Precedes a DateText on a snoozed entry."
  },
  "generateTitle": "Running low",
  "@generateTitle": {
    "description": "Low-stock suggestion sheet title."
  },
  "generateBody": "These are below the level you set. Add the ones you want.",
  "@generateBody": {
    "description": "Low-stock suggestion sheet body."
  },
  "generateShortBy": "Short by",
  "@generateShortBy": {
    "description": "Precedes a QtyText giving threshold minus stock on hand."
  },
  "generateRefresh": "Check again",
  "@generateRefresh": {
    "description": "Re-runs low-stock generation."
  },
  "generateEmptyTitle": "Nothing is running low",
  "@generateEmptyTitle": {
    "description": "Generate sheet empty state."
  },
  "generateEmptyBody": "Set a low-stock level on an item and it will show up here when it drops.",
  "@generateEmptyBody": {
    "description": "Generate sheet empty state body."
  },
  "generateAdded": "{count, plural, =1{1 suggestion added} other{{count} suggestions added}}",
  "@generateAdded": {
    "description": "Result snack after regeneration.",
    "placeholders": {
      "count": {}
    }
  },
  "convertTitle": "Turn into a purchase",
  "@convertTitle": {
    "description": "Convert-to-purchase screen title."
  },
  "convertBody": "Each ticked entry becomes one line, marked for inventory. You confirm the amount and account next.",
  "@convertBody": {
    "description": "Explains the handoff to the expense editor."
  },
  "convertConfirm": "Open the expense",
  "@convertConfirm": {
    "description": "Primary action; hands off to the 6A editor."
  },
  "convertNothingTitle": "Nothing is ticked",
  "@convertNothingTitle": {
    "description": "Convert screen empty state."
  },
  "convertNothingBody": "Tick what you actually bought, then come back.",
  "@convertNothingBody": {
    "description": "Convert screen empty state body."
  },
  "convertLineCount": "{count, plural, =1{1 line} other{{count} lines}}",
  "@convertLineCount": {
    "description": "How many lines the draft will carry.",
    "placeholders": {
      "count": {}
    }
  },
  "listManagerTitle": "Your lists",
  "@listManagerTitle": {
    "description": "List manager sheet title."
  },
  "listNameLabel": "List name",
  "@listNameLabel": {
    "description": "Field label when creating or renaming a list."
  },
  "listCreate": "New list",
  "@listCreate": {
    "description": "Creates a shopping list."
  },
  "listRename": "Rename",
  "@listRename": {
    "description": "Renames a shopping list."
  },
  "listSetDefault": "Make default",
  "@listSetDefault": {
    "description": "Marks a list as the one that opens by default."
  },
  "listDefaultBadge": "Default",
  "@listDefaultBadge": {
    "description": "Chip on the default list."
  },
  "listArchive": "Archive",
  "@listArchive": {
    "description": "Archives a shopping list."
  },
  "listUnarchive": "Restore",
  "@listUnarchive": {
    "description": "Un-archives a shopping list."
  },
  "listArchivedBadge": "Archived",
  "@listArchivedBadge": {
    "description": "Chip on an archived list."
  },
  "listArchivedSection": "Archived",
  "@listArchivedSection": {
    "description": "Section header for archived lists."
  },
  "emptyTitleNoLists": "No lists yet",
  "@emptyTitleNoLists": {
    "description": "List manager empty state."
  },
  "emptyBodyNoLists": "Create one and it becomes your default.",
  "@emptyBodyNoLists": {
    "description": "List manager empty state body."
  },
  "loadingShopping": "Loading your list",
  "@loadingShopping": {
    "description": "Skeleton label for shopping surfaces."
  },
  "actionAddToList": "Add to my list",
  "@actionAddToList": {
    "description": "Accepts a low-stock suggestion, promoting it to origin=manual so regeneration leaves it alone."
  },
  "suggestionDismissed": "Turned down",
  "@suggestionDismissed": {
    "description": "Chip on a dismissed suggestion; it stays listed so it can be accepted later."
  },
  "lineItemsTitle": "What you bought",
  "@lineItemsTitle": {
    "description": "Title of the dedicated line-items page."
  },
  "lineItemsManage": "Add or edit items",
  "@lineItemsManage": {
    "description": "Opens the line-items page from the transaction editor."
  },
  "lineItemsAdd": "Add an item",
  "@lineItemsAdd": {
    "description": "Adds one line from the line-items page."
  },
  "lineItemsSaveAndAnother": "Save & add another",
  "@lineItemsSaveAndAnother": {
    "description": "Commits the line and reopens the editor blank, so a receipt is entered without leaving the sheet."
  },
  "lineItemsCount": "{count, plural, =0{No items yet} =1{1 item} other{{count} items}}",
  "@lineItemsCount": {
    "description": "Running count on the line-items page.",
    "placeholders": {
      "count": {}
    }
  },
  "emptyTitleNoLineItems": "Nothing itemised yet",
  "@emptyTitleNoLineItems": {
    "description": "Line-items page empty state."
  },
  "emptyBodyNoLineItems": "Add what was on the receipt. Anything you leave out still counts toward the total.",
  "@emptyBodyNoLineItems": {
    "description": "Line-items page empty state body."
  },
  "actionRemove": "Remove",
  "@actionRemove": {
    "description": "Removes one line from a transaction."
  },
  "lineRemoved": "Item removed",
  "@lineRemoved": {
    "description": "Snack after removing a line."
  },
  "lineItemsAllocated": "Itemised",
  "@lineItemsAllocated": {
    "description": "Precedes the summed line total on the line-items page."
  },
  "recurringOutflow": "Going out",
  "@recurringOutflow": {
    "description": "Group header for outflow templates."
  },
  "recurringInflow": "Coming in",
  "@recurringInflow": {
    "description": "Group header for inflow templates — salary reads as income, not a negative bill."
  },
  "recurringNextDue": "Next",
  "@recurringNextDue": {
    "description": "Precedes a DateText giving the next due date."
  },
  "recurringOverdue": "Overdue",
  "@recurringOverdue": {
    "description": "Chip on an occurrence past its due date. Derived from the clock, never stored."
  },
  "recurringPaused": "Paused",
  "@recurringPaused": {
    "description": "Chip on a paused template."
  },
  "recurringDueToday": "Due today",
  "@recurringDueToday": {
    "description": "Chip when the next occurrence falls today."
  },
  "emptyTitleNoTemplates": "Nothing recurring yet",
  "@emptyTitleNoTemplates": {
    "description": "Template list empty state."
  },
  "emptyBodyNoTemplates": "Add a bill, a subscription or a salary and it will appear here when it is next due.",
  "@emptyBodyNoTemplates": {
    "description": "Template list empty state body."
  },
  "addTemplate": "Add",
  "@addTemplate": {
    "description": "Adds a recurring template."
  },
  "actionPause": "Pause",
  "@actionPause": {
    "description": "Pauses a template."
  },
  "actionResume": "Resume",
  "@actionResume": {
    "description": "Resumes a paused template."
  },
  "loadingRecurring": "Loading your schedule",
  "@loadingRecurring": {
    "description": "Skeleton label for recurring surfaces."
  },
  "builderSectionWhat": "What it is",
  "@builderSectionWhat": {
    "description": "First section of the template builder."
  },
  "builderSectionWhen": "How often",
  "@builderSectionWhen": {
    "description": "Frequency section of the template builder."
  },
  "builderSectionDefaults": "Defaults",
  "@builderSectionDefaults": {
    "description": "Amount and account section of the template builder."
  },
  "labelTemplateName": "Name",
  "@labelTemplateName": {
    "description": "Template name field."
  },
  "labelRecurringKind": "Kind",
  "@labelRecurringKind": {
    "description": "Bill, subscription, rent or salary."
  },
  "labelDirection": "Direction",
  "@labelDirection": {
    "description": "Whether money goes out or comes in."
  },
  "directionOutflow": "Money out",
  "@directionOutflow": {
    "description": "RecurringDirection.outflow."
  },
  "directionInflow": "Money in",
  "@directionInflow": {
    "description": "RecurringDirection.inflow."
  },
  "kindBill": "Bill",
  "@kindBill": {
    "description": "RecurringKind.bill."
  },
  "kindSubscription": "Subscription",
  "@kindSubscription": {
    "description": "RecurringKind.subscription."
  },
  "kindRent": "Rent",
  "@kindRent": {
    "description": "RecurringKind.rent."
  },
  "kindSalary": "Salary",
  "@kindSalary": {
    "description": "RecurringKind.salary."
  },
  "labelEvery": "Every",
  "@labelEvery": {
    "description": "Precedes the interval count and unit."
  },
  "unitDay": "{count, plural, =1{day} other{days}}",
  "@unitDay": {
    "description": "RecurringIntervalUnit.day.",
    "placeholders": {
      "count": {}
    }
  },
  "unitWeek": "{count, plural, =1{week} other{weeks}}",
  "@unitWeek": {
    "description": "RecurringIntervalUnit.week.",
    "placeholders": {
      "count": {}
    }
  },
  "unitMonth": "{count, plural, =1{month} other{months}}",
  "@unitMonth": {
    "description": "RecurringIntervalUnit.month.",
    "placeholders": {
      "count": {}
    }
  },
  "unitYear": "{count, plural, =1{year} other{years}}",
  "@unitYear": {
    "description": "RecurringIntervalUnit.year.",
    "placeholders": {
      "count": {}
    }
  },
  "labelAnchorDay": "On day of the month",
  "@labelAnchorDay": {
    "description": "anchorDayOfMonth. Stored once, clamped at render (anomaly A13)."
  },
  "anchorDayHelp": "Kept as you set it. Anchored on the 31st, a short month falls on its last day and the next long month returns to the 31st.",
  "@anchorDayHelp": {
    "description": "Explains that the anchor never walks backwards."
  },
  "labelStartDate": "Starts",
  "@labelStartDate": {
    "description": "startDateKey."
  },
  "labelEndDate": "Ends",
  "@labelEndDate": {
    "description": "endDateKey, optional."
  },
  "labelDefaultAmount": "Usual amount",
  "@labelDefaultAmount": {
    "description": "defaultAmount — a default, not a fixed figure."
  },
  "labelRemindBefore": "Remind me",
  "@labelRemindBefore": {
    "description": "remindDaysBefore."
  },
  "saveTemplate": "Save",
  "@saveTemplate": {
    "description": "Commits the template."
  },
  "previewTitle": "Next three",
  "@previewTitle": {
    "description": "Header of the frequency preview."
  },
  "previewEmpty": "Set a start date to see when this lands.",
  "@previewEmpty": {
    "description": "Frequency preview with nothing to show."
  },
  "previewClamped": "Shortened to fit the month",
  "@previewClamped": {
    "description": "Marks a previewed date the anchor could not reach."
  },
  "payTitle": "Record this payment",
  "@payTitle": {
    "description": "Pay sheet title."
  },
  "payTitleInflow": "Record this receipt",
  "@payTitleInflow": {
    "description": "Pay sheet title for an inflow."
  },
  "labelActualAmount": "Amount actually paid",
  "@labelActualAmount": {
    "description": "The real figure, which may differ from the default."
  },
  "labelActualAmountInflow": "Amount actually received",
  "@labelActualAmountInflow": {
    "description": "Inflow wording for the same field."
  },
  "payUsualWas": "Usually",
  "@payUsualWas": {
    "description": "Precedes the default amount when the actual differs from it."
  },
  "labelPaidOn": "Paid on",
  "@labelPaidOn": {
    "description": "paidDateKey."
  },
  "payCommit": "Record it",
  "@payCommit": {
    "description": "Commits the payment and creates the transaction."
  },
  "payRecorded": "Recorded",
  "@payRecorded": {
    "description": "Result snack after paying."
  },
  "payNeedsAccount": "Choose which account it came from",
  "@payNeedsAccount": {
    "description": "Rejection when no account is selected."
  },
  "payUndoTitle": "Undo this payment?",
  "@payUndoTitle": {
    "description": "Confirmation before undoing."
  },
  "payUndoBody": "The obligation goes back to due and the transaction it created is deleted. Anything that transaction produced — stock, an asset — goes with it.",
  "@payUndoBody": {
    "description": "Says exactly what undo reverses, in the order it happens (ARCH_5 §5.4)."
  },
  "payUndone": "Payment undone",
  "@payUndone": {
    "description": "Result snack after undoing."
  },
  "actionSkip": "Skip this one",
  "@actionSkip": {
    "description": "Marks an occurrence deliberately skipped."
  },
  "occurrenceSkipped": "Skipped",
  "@occurrenceSkipped": {
    "description": "Chip on a skipped occurrence, and the snack after skipping."
  },
  "historyRecurringTitle": "Payment history",
  "@historyRecurringTitle": {
    "description": "Occurrence history screen title."
  },
  "historyDefaultVsActual": "Differed from the usual amount",
  "@historyDefaultVsActual": {
    "description": "Badge when paidAmount != defaultAmount."
  },
  "emptyTitleNoOccurrences": "Nothing due yet",
  "@emptyTitleNoOccurrences": {
    "description": "Occurrence history empty state."
  },
  "emptyBodyNoOccurrences": "Occurrences appear as their due dates arrive. Nothing is ever paid for you.",
  "@emptyBodyNoOccurrences": {
    "description": "Empty state body, stating anomaly A14 plainly."
  },
  "statusDue": "Due",
  "@statusDue": {
    "description": "RecurringOccurrenceStatus.due."
  },
  "statusPaid": "Paid",
  "@statusPaid": {
    "description": "RecurringOccurrenceStatus.paid."
  },
  "statusDismissed": "Dismissed",
  "@statusDismissed": {
    "description": "RecurringOccurrenceStatus.dismissed."
  },
  "kindServiceFee": "Service fee",
  "@kindServiceFee": {
    "description": "RecurringKind.serviceFee — a recurring charge tied to an asset."
  },
  "kindOther": "Something else",
  "@kindOther": {
    "description": "RecurringKind.other — anything the named kinds do not cover."
  },
  "billDueSection": "Due now",
  "@billDueSection": {
    "description": "Header above the recurring bills a payment can settle."
  },
  "billSetUpAction": "Set up a recurring bill",
  "@billSetUpAction": {
    "description": "Opens the template builder from the bill form."
  },
  "billNothingDue": "Nothing is due right now.",
  "@billNothingDue": {
    "description": "Shown in the bill form when no occurrence is outstanding."
  },
  "recurringScheduleNext": "Saved. Now set how often it repeats.",
  "@recurringScheduleNext": {
    "description": "Snack after a line asked to become recurring."
  },
  "recurringNotYetDue": "Not due yet",
  "@recurringNotYetDue": {
    "description": "Chip when the next occurrence has not materialised."
  },
  "billSettlesLabel": "Settling",
  "@billSettlesLabel": {
    "description": "Precedes the recurring bill this payment will settle."
  },
  "billSettleNone": "Not a recurring bill",
  "@billSettleNone": {
    "description": "Option that leaves the payment unlinked to any template."
  },
  "billSettleHelp": "Pick one and the amount below becomes what you actually paid. Saving records it once.",
  "@billSettleHelp": {
    "description": "Explains that the editor is the single write path for a bill payment."
  },
  "billAmountBecomesPaid": "This amount is what gets recorded",
  "@billAmountBecomesPaid": {
    "description": "Helper under the amount when a bill is selected."
  },
  "billAccountAuto": "Paid from",
  "@billAccountAuto": {
    "description": "Precedes the account resolved automatically for a bill payment."
  },
  "billAccountAskOnce": "Which account does this come from? Alaya remembers it on the bill.",
  "@billAccountAskOnce": {
    "description": "Shown only when no template default, no app default and more than one account exist."
  },
  "assetGroupAppliance": "Appliances",
  "@assetGroupAppliance": {
    "description": "AssetType.appliance group header."
  },
  "assetGroupElectronics": "Electronics",
  "@assetGroupElectronics": {
    "description": "AssetType.electronics."
  },
  "assetGroupVehicle": "Vehicles",
  "@assetGroupVehicle": {
    "description": "AssetType.vehicle."
  },
  "assetGroupFurniture": "Furniture",
  "@assetGroupFurniture": {
    "description": "AssetType.furniture."
  },
  "assetGroupProperty": "Property",
  "@assetGroupProperty": {
    "description": "AssetType.property."
  },
  "assetGroupServiceProvider": "People",
  "@assetGroupServiceProvider": {
    "description": "AssetType.serviceProvider — a maid or gardener lives here, not in a second system."
  },
  "assetGroupSubscription": "Subscriptions",
  "@assetGroupSubscription": {
    "description": "AssetType.subscription."
  },
  "assetGroupOther": "Other",
  "@assetGroupOther": {
    "description": "AssetType.other."
  },
  "assetUnderWarranty": "In warranty",
  "@assetUnderWarranty": {
    "description": "Chip when warrantyEndDateKey is still ahead."
  },
  "assetWarrantyEnding": "Warranty ending",
  "@assetWarrantyEnding": {
    "description": "Chip when the warranty ends soon."
  },
  "assetWarrantyExpired": "Out of warranty",
  "@assetWarrantyExpired": {
    "description": "Chip when the warranty has passed."
  },
  "assetServiceDue": "Service due",
  "@assetServiceDue": {
    "description": "Chip when nextServiceDueDateKey has passed."
  },
  "assetServiceSoon": "Service soon",
  "@assetServiceSoon": {
    "description": "Chip when a service is close."
  },
  "assetDisposedChip": "Disposed",
  "@assetDisposedChip": {
    "description": "Chip on a disposed asset."
  },
  "assetUnderRepair": "Being repaired",
  "@assetUnderRepair": {
    "description": "AssetStatus.underRepair."
  },
  "filterShowDisposed": "Include disposed",
  "@filterShowDisposed": {
    "description": "Filter that brings disposed assets back into the list."
  },
  "emptyTitleNoAssets": "Nothing tracked yet",
  "@emptyTitleNoAssets": {
    "description": "Asset list empty state."
  },
  "emptyBodyNoAssets": "Add an appliance, a vehicle, or the person who helps around the house — they all live here.",
  "@emptyBodyNoAssets": {
    "description": "Asset list empty state body, stating the serviceProvider case plainly."
  },
  "addAsset": "Add",
  "@addAsset": {
    "description": "Adds an asset."
  },
  "loadingAssets": "Loading your things",
  "@loadingAssets": {
    "description": "Skeleton label for service surfaces."
  },
  "assetSectionIdentity": "Details",
  "@assetSectionIdentity": {
    "description": "Identity section on the detail screen."
  },
  "assetSectionWarranty": "Warranty",
  "@assetSectionWarranty": {
    "description": "Warranty section."
  },
  "assetSectionContact": "Contact",
  "@assetSectionContact": {
    "description": "Contact block."
  },
  "assetSectionService": "Service history",
  "@assetSectionService": {
    "description": "Service records section."
  },
  "assetSectionSalary": "Salary history",
  "@assetSectionSalary": {
    "description": "Service records section for a serviceProvider."
  },
  "assetLifetimeCost": "Spent on service so far",
  "@assetLifetimeCost": {
    "description": "Sum of every service record cost."
  },
  "assetLifetimeSalary": "Paid so far",
  "@assetLifetimeSalary": {
    "description": "The same figure for a serviceProvider."
  },
  "labelBrand": "Brand",
  "@labelBrand": {
    "description": "assets.brand."
  },
  "labelModelNo": "Model",
  "@labelModelNo": {
    "description": "assets.modelNo."
  },
  "labelSerialNo": "Serial",
  "@labelSerialNo": {
    "description": "assets.serialNo."
  },
  "labelPurchasePrice": "Bought for",
  "@labelPurchasePrice": {
    "description": "assets.purchasePrice."
  },
  "labelWarrantyStart": "Warranty from",
  "@labelWarrantyStart": {
    "description": "assets.warrantyStartDateKey."
  },
  "labelWarrantyEnd": "Warranty until",
  "@labelWarrantyEnd": {
    "description": "assets.warrantyEndDateKey."
  },
  "labelWarrantyProvider": "Covered by",
  "@labelWarrantyProvider": {
    "description": "assets.warrantyProvider."
  },
  "labelServiceInterval": "Service every",
  "@labelServiceInterval": {
    "description": "assets.serviceIntervalDays."
  },
  "labelNextService": "Next service",
  "@labelNextService": {
    "description": "assets.nextServiceDueDateKey."
  },
  "labelContactName": "Name",
  "@labelContactName": {
    "description": "assets.primaryContactName."
  },
  "labelContactPhone": "Phone",
  "@labelContactPhone": {
    "description": "assets.primaryContactPhone."
  },
  "labelLocation": "Kept in",
  "@labelLocation": {
    "description": "assets.location."
  },
  "actionCall": "Call",
  "@actionCall": {
    "description": "Dials primaryContactPhone."
  },
  "callFailed": "No app on this phone can place that call.",
  "@callFailed": {
    "description": "Shown when the tel: intent finds no handler."
  },
  "actionAddService": "Record a service",
  "@actionAddService": {
    "description": "Adds a service record."
  },
  "actionAddSalary": "Record a payment",
  "@actionAddSalary": {
    "description": "The same action for a serviceProvider."
  },
  "actionDispose": "Dispose of it",
  "@actionDispose": {
    "description": "Opens the dispose sheet."
  },
  "actionUndispose": "Bring it back",
  "@actionUndispose": {
    "description": "Reverses a disposal."
  },
  "assetLinkedRecurring": "Paid on a schedule",
  "@assetLinkedRecurring": {
    "description": "Chip when linkedRecurringTemplateId is set."
  },
  "emptyBodyNoServices": "Nothing recorded against this yet.",
  "@emptyBodyNoServices": {
    "description": "Empty service history."
  },
  "labelAssetName": "What is it?",
  "@labelAssetName": {
    "description": "assets.name."
  },
  "labelAssetType": "Kind",
  "@labelAssetType": {
    "description": "assets.type."
  },
  "assetTypeHelpPerson": "A person you pay regularly belongs here too — their payments become service records.",
  "@assetTypeHelpPerson": {
    "description": "Explains AssetType.serviceProvider when it is chosen."
  },
  "saveAsset": "Save",
  "@saveAsset": {
    "description": "Commits an asset."
  },
  "serviceIntervalHelp": "Days between services. The next due date moves on each time you record one.",
  "@serviceIntervalHelp": {
    "description": "Explains serviceIntervalDays."
  },
  "labelServiceType": "What happened",
  "@labelServiceType": {
    "description": "service_records.type."
  },
  "serviceTypeService": "Serviced",
  "@serviceTypeService": {
    "description": "ServiceRecordType.service."
  },
  "serviceTypeRepair": "Repaired",
  "@serviceTypeRepair": {
    "description": "ServiceRecordType.repair."
  },
  "serviceTypeMaintenance": "Maintenance",
  "@serviceTypeMaintenance": {
    "description": "ServiceRecordType.maintenance."
  },
  "serviceTypeInspection": "Inspection",
  "@serviceTypeInspection": {
    "description": "ServiceRecordType.inspection."
  },
  "serviceTypeSalaryPaid": "Salary paid",
  "@serviceTypeSalaryPaid": {
    "description": "ServiceRecordType.salaryPaid — the maid case."
  },
  "serviceTypeOther": "Something else",
  "@serviceTypeOther": {
    "description": "ServiceRecordType.other."
  },
  "labelProviderName": "Who did it",
  "@labelProviderName": {
    "description": "service_records.providerName."
  },
  "labelProviderPhone": "Their number",
  "@labelProviderPhone": {
    "description": "service_records.providerPhone."
  },
  "labelServiceDate": "When",
  "@labelServiceDate": {
    "description": "service_records.serviceDateKey."
  },
  "labelServiceCost": "Cost",
  "@labelServiceCost": {
    "description": "service_records.cost."
  },
  "labelNextDue": "Next one due",
  "@labelNextDue": {
    "description": "service_records.nextDueDateKey."
  },
  "alsoRecordAsExpense": "Also record it as an expense",
  "@alsoRecordAsExpense": {
    "description": "The alsoRecordAsExpense toggle."
  },
  "alsoRecordHelp": "Writes a withdrawal for the cost as well, so it shows in your ledger.",
  "@alsoRecordHelp": {
    "description": "Explains what the toggle writes."
  },
  "alsoRecordNeedsAccount": "Choose which account it comes from",
  "@alsoRecordNeedsAccount": {
    "description": "Rejection when the toggle is on with no account."
  },
  "alsoRecordNeedsCost": "Add a cost first",
  "@alsoRecordNeedsCost": {
    "description": "Rejection when the toggle is on with no cost."
  },
  "saveService": "Save",
  "@saveService": {
    "description": "Commits a service record."
  },
  "disposeTitle": "What happened to it?",
  "@disposeTitle": {
    "description": "Dispose sheet title."
  },
  "disposeBody": "It stays in your records either way — what you spent on it still counts. This just stops it appearing as something you own.",
  "@disposeBody": {
    "description": "States anomaly A30 plainly: an asset is never deleted."
  },
  "disposeReasonSold": "Sold it",
  "@disposeReasonSold": {
    "description": "AssetDisposalReason.sold."
  },
  "disposeReasonExpired": "Wore out",
  "@disposeReasonExpired": {
    "description": "AssetDisposalReason.expired."
  },
  "disposeReasonDamaged": "Broke",
  "@disposeReasonDamaged": {
    "description": "AssetDisposalReason.damaged."
  },
  "disposeReasonGifted": "Gave it away",
  "@disposeReasonGifted": {
    "description": "AssetDisposalReason.gifted."
  },
  "disposeReasonLost": "Lost it",
  "@disposeReasonLost": {
    "description": "AssetDisposalReason.lost."
  },
  "disposeReasonReplaced": "Replaced it",
  "@disposeReasonReplaced": {
    "description": "AssetDisposalReason.replaced."
  },
  "disposeReasonOther": "Something else",
  "@disposeReasonOther": {
    "description": "AssetDisposalReason.other."
  },
  "labelDisposalAmount": "Got back",
  "@labelDisposalAmount": {
    "description": "assets.disposalAmount — what the disposal recovered."
  },
  "labelDisposalDate": "When",
  "@labelDisposalDate": {
    "description": "assets.disposedAtDateKey."
  },
  "disposeCommit": "Record it",
  "@disposeCommit": {
    "description": "Commits the disposal."
  },
  "disposeDone": "Recorded",
  "@disposeDone": {
    "description": "Snack after disposing."
  },
  "undisposeDone": "Back in your list",
  "@undisposeDone": {
    "description": "Snack after un-disposing."
  },
  "disposeNeedsReason": "Pick what happened",
  "@disposeNeedsReason": {
    "description": "Rejection when no reason is chosen."
  },
  "hintSearchAssets": "Search your things and people",
  "@hintSearchAssets": {
    "description": "Search hint on the asset list."
  },
  "errorWarrantyBackwards": "The warranty cannot end before it starts",
  "@errorWarrantyBackwards": {
    "description": "Field error when warrantyEndDateKey precedes warrantyStartDateKey."
  },
  "sectionMoney": "Money",
  "@sectionMoney": {
    "description": "Header above the cost and expense controls on the service editor."
  },
  "assetCreatedFromPurchase": "Saved. Now say what it is and how long it is covered.",
  "@assetCreatedFromPurchase": {
    "description": "Snack after a purchase line created an asset."
  },
  "destinationHelpNone": "Recorded as spending and nothing else.",
  "@destinationHelpNone": {
    "description": "Explains destination none."
  },
  "destinationHelpInventory": "Groceries, refills, anything measured and consumed. Needs an item and a quantity, and creates stock you can run down.",
  "@destinationHelpInventory": {
    "description": "Explains destination inventory."
  },
  "destinationHelpAsset": "A phone, a fridge, a chair. Creates something you own, with its own warranty and service history.",
  "@destinationHelpAsset": {
    "description": "Explains destination asset."
  },
  "destinationHelpRecurring": "Sets up a schedule so this comes back every month.",
  "@destinationHelpRecurring": {
    "description": "Explains destination recurring."
  },
  "assetSameNameNote": "You already have one called this. That is fine — this will be a separate one, with its own warranty and service history.",
  "@assetSameNameNote": {
    "description": "Informational note when an asset name repeats. Never a block: five iPhones are five assets."
  },
  "@destinationNone": {
    "description": "No artefact. Recorded as spending and nothing else."
  },
  "@destinationInventory": {
    "description": "Creates stock. Names the Inventory module, matching navInventory."
  },
  "@destinationAsset": {
    "description": "Creates an asset. Names the Services module, matching navServices."
  },
  "@destinationRecurring": {
    "description": "Hands off to the template builder. Matches navRecurring."
  },
  "actionSetWarranty": "Set the warranty",
  "@actionSetWarranty": {
    "description": "Snack action opening the asset a purchase line created."
  },
  "labelPaymentMethodOptional": "How you paid (optional)",
  "@labelPaymentMethodOptional": {
    "description": "Optional payment method on the service editor. Travels to the expense, never onto the record."
  },
  "dashboardTitle": "Home",
  "@dashboardTitle": {
    "description": "Dashboard screen title."
  },
  "fundsAvailable": "Total available funds",
  "@fundsAvailable": {
    "description": "Label above the one headline figure on the dashboard."
  },
  "fundsUnconverted": "{count, plural, =1{1 balance not converted} other{{count} balances not converted}}",
  "@fundsUnconverted": {
    "description": "Chip when BalanceService could not convert some accounts. Excluded from the headline, never summed (anomaly A34).",
    "placeholders": {
      "count": {}
    }
  },
  "fundsApproximate": "Rate is older than today",
  "@fundsApproximate": {
    "description": "Chip when the conversion used the most recent rate on or before today."
  },
  "fundsWhyExcluded": "Balances Alaya has no rate for are left out rather than guessed at.",
  "@fundsWhyExcluded": {
    "description": "Explains why the headline may be lower than the sum of every account."
  },
  "rangeLast30": "Last 30 days",
  "@rangeLast30": {
    "description": "Range label. Always stated, never implied (anomaly A33)."
  },
  "rangeMoneyIn": "In",
  "@rangeMoneyIn": {
    "description": "Deposits over the labelled range."
  },
  "rangeMoneyOut": "Out",
  "@rangeMoneyOut": {
    "description": "Withdrawals over the labelled range."
  },
  "rangeNothingYet": "Nothing yet",
  "@rangeNothingYet": {
    "description": "Shown in place of a figure when a range holds no transactions."
  },
  "rangeExcluded": "{count, plural, =1{1 left out} other{{count} left out}}",
  "@rangeExcluded": {
    "description": "Chip when transactions in a foreign currency could not be converted into the range total.",
    "placeholders": {
      "count": {}
    }
  },
  "insightUpcoming": "Coming up",
  "@insightUpcoming": {
    "description": "The calendar side of the switchable insight card."
  },
  "insightSpending": "Where it went",
  "@insightSpending": {
    "description": "The analytics side of the switchable insight card."
  },
  "insightSwitchLabel": "Show",
  "@insightSwitchLabel": {
    "description": "Semantics label for the insight card switch."
  },
  "insightNothingUpcoming": "Nothing needs attention in the next fortnight.",
  "@insightNothingUpcoming": {
    "description": "Empty state for the upcoming side."
  },
  "insightBillDue": "Bill due",
  "@insightBillDue": {
    "description": "Upcoming row for a recurring occurrence."
  },
  "insightServiceDue": "Service due",
  "@insightServiceDue": {
    "description": "Upcoming row for an asset needing service."
  },
  "insightWarrantyEnding": "Warranty ending",
  "@insightWarrantyEnding": {
    "description": "Upcoming row for an expiring warranty."
  },
  "insightBatchExpiring": "Expiring",
  "@insightBatchExpiring": {
    "description": "Upcoming row for a batch past or near its expiry."
  },
  "moduleGridTitle": "Where to next",
  "@moduleGridTitle": {
    "description": "Header above the navigation tiles."
  },
  "moduleExpenses": "{count, plural, =0{none this month} =1{1 this month} other{{count} this month}}",
  "@moduleExpenses": {
    "description": "Live number on the Expenses tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleInventory": "{count, plural, =0{nothing tracked} =1{1 running low} other{{count} running low}}",
  "@moduleInventory": {
    "description": "Live number on the Inventory tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleShopping": "{count, plural, =0{list is clear} =1{1 to buy} other{{count} to buy}}",
  "@moduleShopping": {
    "description": "Live number on the Shopping tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleRecurring": "{count, plural, =0{all settled} =1{1 due} other{{count} due}}",
  "@moduleRecurring": {
    "description": "Live number on the Recurring tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleServices": "{count, plural, =0{nothing needs doing} =1{1 needs attention} other{{count} need attention}}",
  "@moduleServices": {
    "description": "Live number on the Services tile.",
    "placeholders": {
      "count": {}
    }
  },
  "fabAddIncome": "Money in",
  "@fabAddIncome": {
    "description": "FAB action opening the editor as a deposit."
  },
  "fabAddItem": "New item",
  "@fabAddItem": {
    "description": "FAB action opening the item editor."
  },
  "loadingDashboard": "Adding it up",
  "@loadingDashboard": {
    "description": "Skeleton label for the dashboard."
  },
  "fabOpenLabel": "Add something",
  "@fabOpenLabel": {
    "description": "Semantics label for the closed expandable FAB."
  },
  "fabCloseLabel": "Close",
  "@fabCloseLabel": {
    "description": "Semantics label for the open expandable FAB."
  },
  "eventTypeTransaction": "Transaction",
  "eventTypeRecurringDue": "Recurring bill",
  "eventTypeBatchExpiry": "Expiring",
  "eventTypeWarrantyEnd": "Warranty ending",
  "eventTypeServiceDue": "Service due",
  "eventTypeShoppingTarget": "Shopping target",
  "calendarSeverityWarning": "Needs attention",
  "calendarSeverityDanger": "Past its date",
  "calendarLoadingDay": "Loading this day…",
  "calendarDayErrorTitle": "Could not load this day",
  "calendarDayEmptyTitle": "Nothing on this day",
  "calendarDayEmptyBody": "No transactions, bills, expiries or services fall here.",
  "calendarRetry": "Try again",
  "calendarLoadingMonth": "Loading this month…",
  "calendarErrorTitle": "Could not load the calendar",
  "calendarPreviousMonth": "Previous month",
  "calendarNextMonth": "Next month",
  "calendarOnDay": "On this day",
  "calendarRangeOn": "Select a range",
  "calendarRangeOff": "Stop selecting a range",
  "calendarRangePickEnd": "From {start} — tap another day to finish.",
  "calendarInRange": "{count, plural, =1{1 day} other{{count} days}}",
  "calendarRangeEmptyTitle": "Nothing in these days",
  "calendarRangeEmptyBody": "No transactions, bills, expiries or services fall inside the range.",
  "@calendarRangePickEnd": {
    "description": "Prompt after the range start is chosen.",
    "placeholders": {
      "start": {
        "type": "String"
      }
    }
  },
  "@calendarInRange": {
    "description": "How many days the chosen range spans.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "calendarBackToToday": "Back to this month",
  "calendarTotalOut": "Spent",
  "calendarTotalIn": "Received",
  "dashboardOpenCalendar": "Open calendar",
  "dashboardCalendarSemantics": "{month} at a glance. Opens the calendar.",
  "@dashboardCalendarSemantics": {
    "description": "Screen-reader label for the dashboard month card where days are too narrow to tap.",
    "placeholders": {
      "month": {
        "type": "String"
      }
    }
  },
  "navBackToDashboard": "Back to dashboard",
  "chartLoading": "Working it out…",
  "@chartLoading": {
    "description": "Shown in a ChartCard while its figure computes. A line rather than a spinner: a card about to hold a chart reads as slow behind one (ARCH_5 §5.2)."
  },
  "chartApproximate": "{count, plural, =1{1 figure is indicative} other{{count} figures are indicative}}",
  "@chartApproximate": {
    "description": "How many of a series' data points converted against a rate from a different day (ARCH_3 §1.3). Says what it means rather than naming the rate quality.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "chartUnconverted": "{count, plural, =1{1 amount left out} other{{count} amounts left out}}",
  "@chartUnconverted": {
    "description": "How many amounts had no usable rate and are excluded from the figure, never counted as zero (anomaly A15).",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsTotalSpent": "Spent",
  "@analyticsTotalSpent": {
    "description": "Label above the analytics screen's one displayAmount."
  },
  "analyticsRangeLabel": "Reporting window",
  "@analyticsRangeLabel": {
    "description": "Semantics label for the range chip row."
  },
  "analyticsComparisonUp": "{percent} more than the window before",
  "@analyticsComparisonUp": {
    "description": "Period-over-period comparison, rising. The window compared against is the same length, not a calendar month.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsComparisonDown": "{percent} less than the window before",
  "@analyticsComparisonDown": {
    "description": "Period-over-period comparison, falling.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsUnconvertedTotal": "{count, plural, =1{1 amount needs a rate} other{{count} amounts need a rate}}",
  "@analyticsUnconvertedTotal": {
    "description": "The app-wide unconverted count, distinct from one figure's own exclusions. A transaction outside the window can still be unconvertible.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsInflationTitle": "Your own inflation",
  "@analyticsInflationTitle": {
    "description": "Title of the personal-inflation card, queries 12 and 24."
  },
  "analyticsInflationSubtitle": "What one thing costs you, purchase by purchase",
  "@analyticsInflationSubtitle": {
    "description": "Explains that the trend is per base unit, so 2 kg and 500 g are comparable."
  },
  "analyticsInflationUp": "{percent} more than the first time in this window",
  "@analyticsInflationUp": {
    "description": "The personal-inflation sentence, rising. The date is rendered separately through DateText (Law U7).",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsInflationDown": "{percent} less than the first time in this window",
  "@analyticsInflationDown": {
    "description": "The personal-inflation sentence, falling.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsInflationSince": "First bought",
  "@analyticsInflationSince": {
    "description": "Precedes a DateText giving the earliest purchase in the window."
  },
  "analyticsInflationEmpty": "Buy something twice and its price trend appears here. Widen the window if you have.",
  "@analyticsInflationEmpty": {
    "description": "Empty state: fewer than two priced purchases means there is no trend to draw. Names both ways out."
  },
  "analyticsSectionSpend": "Where it went",
  "@analyticsSectionSpend": {
    "description": "Section header over the spend breakdowns."
  },
  "analyticsSectionTime": "Over time",
  "@analyticsSectionTime": {
    "description": "Section header over the trends."
  },
  "analyticsSectionWhat": "Who and what",
  "@analyticsSectionWhat": {
    "description": "Section header over payees and items."
  },
  "analyticsSectionHome": "Your home",
  "@analyticsSectionHome": {
    "description": "Section header over stock, waste and expiry."
  },
  "analyticsSectionCommitments": "Already committed",
  "@analyticsSectionCommitments": {
    "description": "Section header over recurring commitments and assets."
  },
  "analyticsBySubtype": "By kind",
  "@analyticsBySubtype": {
    "description": "Query 1. \"Kind\" rather than \"subtype\": the schema's word is not the user's."
  },
  "analyticsByTag": "By tag",
  "@analyticsByTag": {
    "description": "Query 2."
  },
  "analyticsByTagNote": "A purchase with two tags counts in both, so these add up to more than the total",
  "@analyticsByTagNote": {
    "description": "The caveat belongs on the card: a reader comparing tag figures against the headline deserves to know why they differ."
  },
  "analyticsByMethod": "By payment method",
  "@analyticsByMethod": {
    "description": "Query 3."
  },
  "analyticsConcentration": "How concentrated",
  "@analyticsConcentration": {
    "description": "Query 22, with query 8's grocery share beneath it."
  },
  "analyticsTopShare": "{percent} of your spending sits in three kinds",
  "@analyticsTopShare": {
    "description": "Query 22's headline.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsGroceryShare": "Groceries are {percent} of it",
  "@analyticsGroceryShare": {
    "description": "Query 8, stated beneath the concentration figure.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsTagChildren": "{count, plural, =1{1 tag inside} other{{count} tags inside}}",
  "@analyticsTagChildren": {
    "description": "Marks a parent tag that can be opened. One level only, which is all the schema permits.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsTagDirect": "{tag} on its own",
  "@analyticsTagDirect": {
    "description": "The parent tag's own spending, as a sibling of its children rather than folded into them.",
    "placeholders": {
      "tag": {}
    }
  },
  "analyticsTagBack": "Back to all tags",
  "@analyticsTagBack": {
    "description": "Tooltip on the in-place drill's back button."
  },
  "analyticsNothingSpent": "Nothing spent in this window",
  "@analyticsNothingSpent": {
    "description": "Empty state for a spend breakdown."
  },
  "analyticsNoTaggedSpend": "Tag a purchase and it will appear here",
  "@analyticsNoTaggedSpend": {
    "description": "Empty state for the tag breakdown: names the action, not the absence."
  },
  "analyticsNoMethodSpend": "Record how you paid and it will appear here",
  "@analyticsNoMethodSpend": {
    "description": "Empty state for the payment-method breakdown."
  },
  "analyticsIncomeVsExpense": "In and out",
  "@analyticsIncomeVsExpense": {
    "description": "Query 5."
  },
  "analyticsNeedTwoMonths": "Two months of records and the trend appears here",
  "@analyticsNeedTwoMonths": {
    "description": "Empty state: one month is a pair of figures, not a trend."
  },
  "analyticsNetFlow": "What you kept",
  "@analyticsNetFlow": {
    "description": "Query 6. Named for what the figure means rather than for the ledger it comes from."
  },
  "analyticsNetFlowNote": "Moving money between your own accounts does not count",
  "@analyticsNetFlowNote": {
    "description": "Explains why a transfer is absent: the ledger nets it to zero across its two legs."
  },
  "analyticsNoFlow": "Nothing moved in this window",
  "@analyticsNoFlow": {
    "description": "Empty state for net flow."
  },
  "analyticsBalanceTrend": "Balance over time",
  "@analyticsBalanceTrend": {
    "description": "Query 7."
  },
  "analyticsBalanceIn": "{account}, in {currency}",
  "@analyticsBalanceIn": {
    "description": "Names the account and its currency: this is the one figure on the screen not in the home currency, because converting each point would make the line move when rates moved.",
    "placeholders": {
      "account": {},
      "currency": {}
    }
  },
  "analyticsAccount": "Account",
  "@analyticsAccount": {
    "description": "Label on the balance-trend account picker."
  },
  "analyticsNoBalanceMovement": "No movement on this account in this window",
  "@analyticsNoBalanceMovement": {
    "description": "Empty state for the balance trend."
  },
  "analyticsHeatmap": "When you spend",
  "@analyticsHeatmap": {
    "description": "Query 21."
  },
  "analyticsByWeekday": "By day of week",
  "@analyticsByWeekday": {
    "description": "Heatmap segment."
  },
  "analyticsByDayOfMonth": "By date",
  "@analyticsByDayOfMonth": {
    "description": "Heatmap segment."
  },
  "analyticsTopPayees": "Who you paid most",
  "@analyticsTopPayees": {
    "description": "Query 4."
  },
  "analyticsNoPayees": "Name who you paid and they will appear here",
  "@analyticsNoPayees": {
    "description": "Empty state for top payees."
  },
  "analyticsTopItems": "What cost you most",
  "@analyticsTopItems": {
    "description": "Query 9."
  },
  "analyticsNoItemisedSpend": "Itemise a purchase and it will appear here",
  "@analyticsNoItemisedSpend": {
    "description": "Empty state for top items by spend."
  },
  "analyticsTopByQuantity": "What you buy most of",
  "@analyticsTopByQuantity": {
    "description": "Query 10."
  },
  "analyticsTopByQuantityNote": "Grouped by measure, because weight and count cannot be compared",
  "@analyticsTopByQuantityNote": {
    "description": "Explains the grouping: Law L8 makes cross-category comparison meaningless."
  },
  "analyticsNoQuantities": "Record how much you bought and it will appear here",
  "@analyticsNoQuantities": {
    "description": "Empty state for top items by quantity."
  },
  "analyticsPurchaseCount": "{count, plural, =1{1 purchase} other{{count} purchases}}",
  "@analyticsPurchaseCount": {
    "description": "How many times an item was bought in the window.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsDearest": "The most you have paid",
  "@analyticsDearest": {
    "description": "Query 11."
  },
  "analyticsDearestItem": "Item",
  "@analyticsDearestItem": {
    "description": "Key on the dearest-purchase card."
  },
  "analyticsDearestPrice": "Unit price",
  "@analyticsDearestPrice": {
    "description": "Key on the dearest-purchase card. The figure is in the currency it was bought in, unconverted."
  },
  "analyticsDearestWhen": "When",
  "@analyticsDearestWhen": {
    "description": "Key on the dearest-purchase card, paired with a DateText."
  },
  "analyticsNoUnitPrices": "Record a unit price and this appears here",
  "@analyticsNoUnitPrices": {
    "description": "Empty state for the dearest purchase."
  },
  "analyticsAverageBasket": "Your average shop",
  "@analyticsAverageBasket": {
    "description": "Query 23."
  },
  "analyticsBasketValue": "Average value",
  "@analyticsBasketValue": {
    "description": "Key on the basket card."
  },
  "analyticsBasketLines": "Average items",
  "@analyticsBasketLines": {
    "description": "Key on the basket card."
  },
  "analyticsBasketCount": "Shops counted",
  "@analyticsBasketCount": {
    "description": "Key on the basket card. Counts the baskets that converted, which is what the average divides by."
  },
  "analyticsNoBaskets": "Record a grocery shop and it will appear here",
  "@analyticsNoBaskets": {
    "description": "Empty state for the basket card."
  },
  "analyticsInventoryValue": "What is on your shelves",
  "@analyticsInventoryValue": {
    "description": "Query 13."
  },
  "analyticsInventoryValueNote": "Right now, whatever window you have chosen",
  "@analyticsInventoryValueNote": {
    "description": "Explains why the range chip does not change this figure."
  },
  "analyticsBatchesValued": "{count, plural, =1{1 batch valued} other{{count} batches valued}}",
  "@analyticsBatchesValued": {
    "description": "How many batches had both a cost and a resolvable purchase unit.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsBatchesNoCost": "{count, plural, =1{1 batch has no cost} other{{count} batches have no cost}}",
  "@analyticsBatchesNoCost": {
    "description": "Uncosted stock, reported rather than omitted: a valuation that skipped it would look complete while understating the shelf.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsNoStockValue": "Record what a batch cost and its value appears here",
  "@analyticsNoStockValue": {
    "description": "Empty state for the inventory valuation."
  },
  "analyticsWaste": "What you threw away",
  "@analyticsWaste": {
    "description": "Query 14, one of the app's differentiating insights."
  },
  "analyticsNoWaste": "Nothing wasted in this window",
  "@analyticsNoWaste": {
    "description": "Empty state, and it is good news: worded as a fact rather than as missing data."
  },
  "analyticsExpiring": "Expiring within {days} days",
  "@analyticsExpiring": {
    "description": "Query 15.",
    "placeholders": {
      "days": {
        "type": "int"
      }
    }
  },
  "analyticsNothingExpiring": "Nothing expires soon",
  "@analyticsNothingExpiring": {
    "description": "Empty state for the expiry card."
  },
  "analyticsDaysLeft": "{days, plural, =1{1 day left} other{{days} days left}}",
  "@analyticsDaysLeft": {
    "description": "How long a batch has. Paired with a tone, because colour is never the only signal (Law U17).",
    "placeholders": {
      "days": {
        "type": "num"
      }
    }
  },
  "analyticsExpiredAlready": "Past its date",
  "@analyticsExpiredAlready": {
    "description": "Chip on a batch whose expiry has passed and still holds stock."
  },
  "analyticsLowStock": "Running low",
  "@analyticsLowStock": {
    "description": "Query 16."
  },
  "analyticsLowStockNote": "A count for today, not a history: stock levels are not kept over time",
  "@analyticsLowStockNote": {
    "description": "Explains why this is one figure rather than a trend."
  },
  "analyticsLowStockCount": "{count, plural, =1{1 item below its threshold} other{{count} items below their threshold}}",
  "@analyticsLowStockCount": {
    "description": "Query 16's figure.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsAsOf": "As of",
  "@analyticsAsOf": {
    "description": "Precedes a DateText on the low-stock count."
  },
  "analyticsNothingLow": "Nothing is running low",
  "@analyticsNothingLow": {
    "description": "Empty state for the low-stock card."
  },
  "analyticsCommitment": "Every month, before anything else",
  "@analyticsCommitment": {
    "description": "Query 17."
  },
  "analyticsCommitmentNote": "Bills and subscriptions only. Income is not netted off",
  "@analyticsCommitmentNote": {
    "description": "Explains the outflow-only filter: netting salary against rent would report a household as having no fixed costs."
  },
  "analyticsCommitmentCount": "{count, plural, =1{from 1 commitment} other{from {count} commitments}}",
  "@analyticsCommitmentCount": {
    "description": "How many active templates the monthly figure covers.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsNoCommitments": "Add a bill or subscription and it will appear here",
  "@analyticsNoCommitments": {
    "description": "Empty state for the commitment total."
  },
  "analyticsRecurringSplit": "Fixed against chosen",
  "@analyticsRecurringSplit": {
    "description": "Query 18."
  },
  "analyticsRecurring": "Fixed",
  "@analyticsRecurring": {
    "description": "Query 18's recurring side. The user's word, not the schema's."
  },
  "analyticsDiscretionary": "Chosen",
  "@analyticsDiscretionary": {
    "description": "Query 18's discretionary side."
  },
  "analyticsRecurringShare": "{percent} of your spending was already committed",
  "@analyticsRecurringShare": {
    "description": "Query 18's headline.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsServiceCost": "What your things cost to keep",
  "@analyticsServiceCost": {
    "description": "Query 19. Includes disposed assets, which is the point of a status change rather than a delete."
  },
  "analyticsServiceCount": "{count, plural, =1{1 visit} other{{count} visits}}",
  "@analyticsServiceCount": {
    "description": "How many service records an asset has in the window.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsNoServiceCost": "Record a service or repair and it will appear here",
  "@analyticsNoServiceCost": {
    "description": "Empty state for the service-cost card."
  },
  "analyticsWarranty": "Warranties",
  "@analyticsWarranty": {
    "description": "Query 20."
  },
  "analyticsCovered": "Covered",
  "@analyticsCovered": {
    "description": "Chip on an asset still inside its warranty window."
  },
  "analyticsCoverageEnded": "Cover ended",
  "@analyticsCoverageEnded": {
    "description": "Chip on an asset whose warranty has run out."
  },
  "analyticsNoWarranties": "Add a warranty date and it will appear here",
  "@analyticsNoWarranties": {
    "description": "Empty state for the warranty card."
  },
  "analyticsEmptyTitle": "Nothing to show for this window",
  "@analyticsEmptyTitle": {
    "description": "Screen-level empty state. The house section stays visible beneath it, because stock is a \"right now\" figure."
  },
  "analyticsEmptyBody": "Widen the window above, or record something and it will appear here.",
  "@analyticsEmptyBody": {
    "description": "Names both ways out: on a fresh install the second is the answer, on a quiet month the first is."
  },
  "analyticsCacheClear": "Recalculate everything",
  "@analyticsCacheClear": {
    "description": "The clear-cache action, named for what the reader gets rather than for the table it empties."
  },
  "analyticsCacheClearing": "Recalculating…",
  "@analyticsCacheClearing": {
    "description": "The action's in-progress label."
  },
  "analyticsCacheExplain": "Some figures are kept between visits so this screen opens quickly. Clear them if a number looks stale.",
  "@analyticsCacheExplain": {
    "description": "Explains what the action does. The only place analytics_cache is ever visible (ARCH_5 §7.3)."
  },
  "analyticsCacheCleared": "Recalculated",
  "@analyticsCacheCleared": {
    "description": "Precedes a DateText giving when the cache was last cleared."
  },
  "analyticsCacheClearedSnack": "Figures recalculated",
  "@analyticsCacheClearedSnack": {
    "description": "Success snack. Same word as the button, per ARCH_5 §2.8."
  },
  "analyticsCacheFailed": "Could not clear the saved figures",
  "@analyticsCacheFailed": {
    "description": "Failure snack. Names what failed rather than apologising."
  },
  "analyticsDrillTitle": "Behind this figure",
  "@analyticsDrillTitle": {
    "description": "Fallback title for the drill-down while its label resolves."
  },
  "analyticsDrillTotal": "These come to",
  "@analyticsDrillTotal": {
    "description": "Precedes the drill-down's per-currency subtotals."
  },
  "analyticsDrillLoading": "Loading these transactions…",
  "@analyticsDrillLoading": {
    "description": "Semantics label on the drill-down's skeleton."
  },
  "analyticsDrillEmptyTitle": "Nothing here in this window",
  "@analyticsDrillEmptyTitle": {
    "description": "Drill-down empty state."
  },
  "analyticsDrillEmptyBody": "The window is set on the insights screen. Widen it and these may appear.",
  "@analyticsDrillEmptyBody": {
    "description": "Names the likely cause: the filter is what the reader just chose, the window is what they may have forgotten."
  },
  "analyticsDrillUnknownTitle": "This link does not point anywhere",
  "@analyticsDrillUnknownTitle": {
    "description": "Shown when the route's parameters name no filter this version knows."
  },
  "analyticsDrillUnknownBody": "Open insights and choose a figure to look behind.",
  "analyticsOtherSlices": "Everything else",
  "@analyticsOtherSlices": {
    "description": "The grouped remainder wedge of a donut, past the sixth slice. A ring of twelve slivers is not readable, so the tail becomes one wedge that says what it is."
  },
  "analyticsTopThree": "in three kinds",
  "@analyticsTopThree": {
    "description": "The quiet line under the percentage in the concentration donut's centre, saying what that percentage is of."
  },
  "@analyticsDrillUnknownBody": {
    "description": "Offers the way on rather than throwing: the route is reachable from outside the app."
  },
  "aboutHowItWorksHeader": "How it works",
  "aboutLicences": "Open source licences",
  "aboutLicencesHelp": "The libraries Alaya is built on.",
  "aboutOfflineBody": "Everything is stored on this device. Alaya only reaches the internet to fetch exchange rates, once a day.",
  "aboutStorageBody": "Your data is not encrypted, and no copy of it exists anywhere else unless you make a backup yourself.",
  "@aboutStorageBody": {
    "description": "The same threat model the lock screen states, in the place somebody comes looking for it. Two locations is not duplication: one is a decision point, the other is where a question gets answered."
  },
  "aboutTagline": "A finance and home manager that works entirely on your phone.",
  "accountCurrencyHeader": "Currency",
  "accountCurrencyLockedHelp": "Fixed, because changing it would reinterpret every amount already recorded here.",
  "@accountCurrencyLockedHelp": {
    "description": "Law L9 at its sharpest: the home currency is a display choice, but an account’s own currency is what its money is."
  },
  "accountCurrencyNewHelp": "What this account holds. It cannot be changed once you start recording against it.",
  "accountEditorEditTitle": "Edit account",
  "accountEditorSave": "Save account",
  "@accountEditorSave": {
    "description": "Names the thing, per archetype B — never a bare \"Save\"."
  },
  "accountEditorTitle": "New account",
  "accountIncludeInNetWorth": "Count in net worth",
  "accountIncludeInNetWorthHelp": "Off means the balance still shows here, but is left out of your total. Useful for an account you hold for someone else.",
  "@accountIncludeInNetWorthHelp": {
    "description": "ARCH_5 §7.2 requires the toggle be explained: without this line the reader cannot tell whether off means hidden or merely uncounted."
  },
  "accountKindBank": "Bank",
  "accountKindCard": "Card",
  "accountKindCash": "Cash",
  "accountKindHeader": "What kind?",
  "accountKindOther": "Other",
  "accountKindWallet": "Wallet",
  "accountNameLabel": "Name",
  "accountOpeningBalanceLabel": "Opening balance",
  "accountOpeningDateLabel": "True on",
  "@accountOpeningDateLabel": {
    "description": "Not \"date\": the question is which day the balance was correct, and \"date\" invites today by default."
  },
  "accountsAdd": "Add an account",
  "accountsArchive": "Archive this account",
  "accountsArchiveConfirmBody": "It will stop appearing when you record anything. Its history stays, and you can restore it here at any time.",
  "accountsArchiveConfirmTitle": "Archive this account?",
  "accountsArchiveHelp": "An archived account keeps all its history. It just stops appearing when you record something.",
  "@accountsArchiveHelp": {
    "description": "Says what survives, because \"archive\" does not tell the reader whether their transactions go with it."
  },
  "accountsArchived": "Account archived",
  "accountsArchivedChip": "Archived",
  "accountsArchivedHeader": "Archived",
  "accountsEmptyBody": "Add one so Alaya knows where your money is.",
  "accountsEmptyTitle": "No accounts yet",
  "accountsExcludedChip": "Not in net worth",
  "accountsLoading": "Loading your accounts…",
  "accountsMissingBody": "It may have been removed. Go back and pick another.",
  "@accountsMissingBody": {
    "description": "A stale deep link, or a row removed in another window. Stated rather than rendering a blank form that would silently create a second account on save."
  },
  "accountsMissingTitle": "That account is not here",
  "accountsRestore": "Restore this account",
  "accountsRestoreConfirmBody": "It will appear again everywhere you choose an account.",
  "@accountsRestoreConfirmBody": {
    "description": "Confirmed in both directions: restoring puts an account back into every picker, which is worth stating before it happens."
  },
  "accountsRestoreConfirmTitle": "Restore this account?",
  "accountsRestored": "Account restored",
  "accountsSaved": "Account saved",
  "actionBack": "Back",
  "actionContinue": "Continue",
  "appearanceModeDark": "Always dark",
  "appearanceModeHeader": "Light or dark",
  "appearanceModeLight": "Always light",
  "appearanceModeSystem": "Match my phone",
  "appearanceModeSystemHelp": "Follows your phone’s light and dark setting.",
  "appearancePaletteHeader": "Colours",
  "appearanceThemeLabHelp": "See every colour, spacing and text style the app uses.",
  "backupNotEncryptedWarning": "This backup is not encrypted. Anyone who opens this file can read every transaction, balance and account name. Only share it somewhere you trust.",
  "@backupNotEncryptedWarning": {
    "description": "ARCH_3 §3.4 verbatim, on every export confirmation — not in settings, not a tooltip. Corrected in 8B: the 8A wording was a paraphrase that dropped the third sentence."
  },
  "currenciesHomeLocked": "Cannot be turned off — your totals are added up in this.",
  "@currenciesHomeLocked": {
    "description": "Law L9: disabling it would leave the dashboard with no currency to aggregate into. Disabled rather than hidden, so it reads as an explanation and not a rendering fault."
  },
  "currenciesLoading": "Loading currencies…",
  "currenciesToggleFailed": "That could not be changed",
  "dataBackupHeader": "Backup",
  "dataExportBody": "Sends a copy of your data to WhatsApp, Drive, or anywhere else you choose.",
  "dataExportConfirmAction": "Share it",
  "dataExportConfirmTitle": "Share a backup?",
  "dataExportFailed": "The backup could not be made",
  "dataExportTitle": "Share a backup",
  "dataRestoreHeader": "Restore",
  "dataRestorePending": "Coming in the next update.",
  "@dataRestorePending": {
    "description": "Stated as not-yet-here rather than offered and broken: restore needs the Storage Access Framework picker and a merge strategy, both of which are 8B’s."
  },
  "dataRestoreTitle": "Restore from a backup",
  "lockBackspace": "Delete last digit",
  "lockBiometricFailed": "Not recognised. Enter your PIN instead.",
  "lockBiometricReason": "Unlock Alaya",
  "@lockBiometricReason": {
    "description": "Shown by the system prompt, so it must be localised before it reaches the plugin (Law U5)."
  },
  "lockEraseFailed": "The data could not be deleted. Your PIN is unchanged.",
  "@lockEraseFailed": {
    "description": "Says what did not change, so a failed erase does not leave the user unsure whether they are locked out of a half-wiped app."
  },
  "lockErasing": "Deleting everything on this device…",
  "@lockErasing": {
    "description": "The ten-failure auto-erase is running. It takes the whole screen, because there is nothing left to enter a PIN against."
  },
  "lockForgotPin": "I have forgotten my PIN",
  "lockHonestBody": "This PIN stops someone who picks up your unlocked phone from opening Alaya. It does not encrypt your data — anyone with access to the phone's files can still read them. Your phone's own lock screen is what protects the file itself.",
  "@lockHonestBody": {
    "description": "ARCH_3 §2.5, and the most important string in the app. No \"bank-grade\", no \"military-grade\", and no padlock glyph beside it: the database is plaintext by design (ARCH_1 §2.1) and claiming otherwise would be dishonest and a Play listing risk."
  },
  "lockThrottledWhy": "The wait gets longer after each wrong attempt.",
  "@lockThrottledWhy": {
    "description": "Says why the delay exists, so a throttle reads as deliberate rather than as the app having frozen."
  },
  "lockTitle": "Enter your PIN",
  "lockUseBiometric": "Use fingerprint",
  "@lockUseBiometric": {
    "description": "The keypad key is an icon, so this is its Semantics label (ARCH_5 §2.7)."
  },
  "lockWrongPin": "That PIN is not right.",
  "onboardingAccountsBody": "Where do you keep your money? Add the ones you use.",
  "onboardingAccountsTitle": "Your accounts",
  "onboardingAddAccount": "Add an account",
  "onboardingCurrencyBody": "Which currency should Alaya add your totals up in?",
  "onboardingCurrencyNote": "This changes how totals are shown. It does not change any amount you have already recorded, and each account keeps its own currency.",
  "@onboardingCurrencyNote": {
    "description": "Law L9 in plain words. Somebody who thinks they are converting their history would be very surprised later."
  },
  "onboardingCurrencyTitle": "Your currency",
  "onboardingFinish": "Finish",
  "onboardingLoading": "Getting things ready…",
  "onboardingLockOnBody": "Alaya will ask for your PIN when you open it. You can change or remove it in Settings › Security.",
  "onboardingLockOnHeader": "Lock is on",
  "onboardingNext": "Next",
  "onboardingNoAccountsBody": "Add at least one so Alaya knows where your money is.",
  "onboardingNoAccountsTitle": "No accounts yet",
  "onboardingOpeningNote": "The opening balance is what was there on the date you give. Alaya needs both: a balance with no date cannot be placed in your ledger, and anything you record before that date would not be counted.",
  "@onboardingOpeningNote": {
    "description": "Anomaly A03. This is the paragraph that stops an opening balance being captured without its date."
  },
  "onboardingRemoveAccount": "Remove this account",
  "onboardingSaveAccounts": "Save accounts",
  "onboardingSecurityBody": "You can put a PIN on Alaya. This is optional and you can add one later.",
  "onboardingSecurityTitle": "Lock the app?",
  "onboardingSkip": "Skip",
  "onboardingSkipBody": "You can change all of this later in Settings.",
  "onboardingSkipTitle": "Skip setting up?",
  "onboardingTitle": "Welcome to Alaya",
  "payeeKindEmployer": "Employer",
  "payeeKindMerchant": "Shop",
  "payeeKindOther": "Other",
  "payeeKindPerson": "Person",
  "payeeKindUtility": "Utility",
  "payeeNameLabel": "Name",
  "payeePhoneOptionalLabel": "Phone (optional)",
  "@payeePhoneOptionalLabel": {
    "description": "Marked optional, because an unmarked second field reads as required and is the commonest reason a two-field sheet feels like a form."
  },
  "payeesAdd": "Add a payee",
  "payeesDelete": "Delete",
  "payeesDeleteConfirmBody": "Transactions that named them keep their record. They just stop being suggested.",
  "payeesDeleteConfirmTitle": "Delete this payee?",
  "payeesDeleteFailed": "That could not be deleted",
  "payeesDeleted": "Payee deleted",
  "payeesEditTitle": "Edit payee",
  "payeesEmptyBody": "These build up as you record who you paid.",
  "payeesEmptyTitle": "No payees yet",
  "payeesLoading": "Loading payees…",
  "payeesNoMatchBody": "Try part of the name.",
  "payeesNoMatchTitle": "No payees match that",
  "payeesSave": "Save payee",
  "payeesSaveFailed": "That could not be saved",
  "payeesSaved": "Payee saved",
  "payeesSearchHint": "Search payees",
  "paymentKindBankTransfer": "Bank transfer",
  "paymentKindCard": "Card",
  "paymentKindCash": "Cash",
  "paymentKindCheque": "Cheque",
  "paymentKindOther": "Other",
  "paymentKindUpi": "UPI",
  "paymentKindWallet": "Wallet",
  "paymentMethodNameLabel": "Name",
  "paymentMethodsAdd": "Add a payment method",
  "paymentMethodsDelete": "Delete",
  "paymentMethodsDeleteConfirmBody": "Transactions that used it keep their record of having done so. It just stops being offered.",
  "paymentMethodsDeleteConfirmTitle": "Delete this payment method?",
  "paymentMethodsDeleteFailed": "That could not be deleted",
  "paymentMethodsDeleted": "Payment method deleted",
  "paymentMethodsEditTitle": "Edit payment method",
  "paymentMethodsEmptyBody": "Add how you usually pay — cash, UPI, a card.",
  "paymentMethodsEmptyTitle": "No payment methods",
  "paymentMethodsLoading": "Loading payment methods…",
  "paymentMethodsSave": "Save payment method",
  "paymentMethodsSaveFailed": "That could not be saved",
  "paymentMethodsSaved": "Payment method saved",
  "paymentMethodsSystemChip": "Built in",
  "@paymentMethodsSystemChip": {
    "description": "Renameable but not removable, and the chip says so before the user hunts for a delete that is not there."
  },
  "pinSetupBackupBody": "You have just put a lock on this app. A backup means a forgotten PIN never costs you your records.",
  "pinSetupBackupHeader": "Make a backup?",
  "pinSetupBackupLater": "Not now",
  "pinSetupBackupNow": "Back up now",
  "pinSetupConfirmPrompt": "Enter it again",
  "pinSetupDone": "Your PIN is set",
  "pinSetupDoneBody": "Alaya will ask for it when you open the app, and again after a minute in the background.",
  "pinSetupEnterPrompt": "Choose a PIN",
  "pinSetupMismatch": "Those did not match. Start again.",
  "@pinSetupMismatch": {
    "description": "Both entries are cleared, because somebody who mistyped does not know which of the two was wrong."
  },
  "pinSetupRecoveryAck": "I have saved this code somewhere safe",
  "@pinSetupRecoveryAck": {
    "description": "The one confirmation, and it gates the button rather than warning after the fact."
  },
  "pinSetupRecoveryBody": "This is the only way back in if you forget your PIN. It is shown once and cannot be shown again.",
  "@pinSetupRecoveryBody": {
    "description": "True rather than cautious: PinService stores only a hash, so the app genuinely cannot redisplay it."
  },
  "pinSetupRecoveryCopied": "Recovery code copied",
  "pinSetupRecoveryCopy": "Copy code",
  "pinSetupRecoveryHeader": "Your recovery code",
  "pinSetupRecoveryWhereToKeep": "A password manager is a good place for it. A photo in your gallery is not.",
  "pinSetupTitle": "Set a PIN",
  "recoveryCodeLabel": "Recovery code",
  "recoveryCodePrompt": "Enter the recovery code you saved when you set your PIN.",
  "recoveryDone": "Your PIN has been changed",
  "recoveryEraseEverything": "Erase everything",
  "recoveryExportFirst": "Export a copy first",
  "recoveryExported": "A copy has been shared. Check it arrived before you erase.",
  "@recoveryExported": {
    "description": "Asks the user to verify: a backup nobody confirmed is not a backup."
  },
  "recoveryForgotBoth": "I do not have the recovery code either",
  "recoveryForgotBothBody": "Without your PIN or your recovery code there is no way back into this data. You can export a copy first, then erase everything and start again.",
  "@recoveryForgotBothBody": {
    "description": "The export is possible only because the database is plaintext — with encryption the copy would be unreadable without the key the user has lost. ARCH_4 records that as the improvement dropping encryption bought."
  },
  "recoveryForgotBothTitle": "Starting over",
  "recoveryNewPinPrompt": "Choose a new PIN",
  "recoveryTitle": "Forgotten PIN",
  "securityAutoEraseConfirmAction": "Turn it on",
  "securityAutoEraseConfirmTitle": "Turn on erase after repeated failures?",
  "securityAutoEraseFailed": "That could not be changed",
  "securityAutoEraseHeader": "If the PIN is entered wrongly",
  "securityAutoEraseOff": "Erase after repeated failures is off",
  "securityAutoEraseOn": "Erase after repeated failures is on",
  "securityAutoEraseTitle": "Erase everything after repeated failures",
  "securityAutoLockHeader": "Auto-lock",
  "securityAutoLockTitle": "Lock when I leave the app",
  "securityChangePin": "Change PIN",
  "securityChecking": "Checking…",
  "@securityChecking": {
    "description": "Neither branch is guessed: a row saying \"no PIN set\" for one frame to somebody who has one would be alarming for the wrong reason."
  },
  "securityPinHeader": "PIN",
  "securityRemovePin": "Remove PIN",
  "securityRemovePinConfirmBody": "Anyone who picks up your unlocked phone will be able to open Alaya. You will be asked for your current PIN next.",
  "securityRemovePinConfirmTitle": "Remove the PIN?",
  "securityRemovePinHelp": "You will need your current PIN to do this.",
  "securitySetPin": "Set a PIN",
  "securitySetPinHelp": "Alaya will ask for it when you open the app.",
  "settingsAbout": "About",
  "settingsAccounts": "Accounts",
  "settingsAppearance": "Appearance",
  "settingsCurrencies": "Currencies",
  "settingsData": "Data",
  "settingsGroupApp": "The app",
  "settingsGroupMoney": "Your money",
  "settingsGroupThings": "Your things",
  "settingsNoMatchBody": "Try a different word — \"dark\", \"PIN\" and \"backup\" all find something.",
  "@settingsNoMatchBody": {
    "description": "Names the search rather than the tree: \"no settings\" in front of a list the user can see is a lie. The examples are the keywords the rows actually match on."
  },
  "settingsNoMatchTitle": "Nothing matches that",
  "settingsPayees": "Payees",
  "settingsPaymentMethods": "Payment methods",
  "settingsSearchHint": "Search settings",
  "settingsSecurity": "Security",
  "settingsTags": "Tags",
  "settingsUnits": "Units",
  "tagColourHeader": "Colour",
  "tagColourHelp": "Optional. Kept as chosen, so it stays the same if you change the app’s palette later.",
  "@tagColourHelp": {
    "description": "Honest about the freeze: colorArgb is a stored int, so a tag coloured under one preset keeps that colour when the palette changes."
  },
  "tagColourNone": "No colour",
  "tagColourSwatch": "Use this colour",
  "@tagColourSwatch": {
    "description": "The swatches are colour-only, so each needs a Semantics label (Law U17)."
  },
  "tagEditorEditTitle": "Edit tag",
  "tagEditorSave": "Save tag",
  "tagEditorTitle": "New tag",
  "tagNameLabel": "Name",
  "tagParentHeader": "Group under",
  "tagParentHelp": "Optional. Grouping keeps long tag lists readable. Only one level deep.",
  "tagParentNone": "No group",
  "tagScopeDeposit": "Money in",
  "tagScopeDepositHelp": "Offered when you record money coming in.",
  "tagScopeInventory": "Items",
  "tagScopeInventoryHelp": "Offered on things you keep at home.",
  "tagScopeRecurring": "Recurring",
  "tagScopeRecurringHelp": "Offered on bills and subscriptions.",
  "tagScopeService": "Services",
  "tagScopeServiceHelp": "Offered on appliances and their service records.",
  "tagScopeShopping": "Shopping lists",
  "tagScopeShoppingHelp": "Used to group a shopping list under headings.",
  "tagScopeWithdrawal": "Money out",
  "tagScopeWithdrawalHelp": "Offered when you record spending.",
  "tagScopesHeader": "Where it appears",
  "tagScopesHelp": "A tag is only offered where you turn it on. This is what keeps \"Kitchen\" out of the list when you record your salary.",
  "@tagScopesHelp": {
    "description": "ARCH_5 §7.2’s allowedIn* row, said in the terms the requirement itself uses."
  },
  "tagsAdd": "Add a tag",
  "tagsDelete": "Delete this tag",
  "tagsDeleteConfirmBody": "Transactions and items already carrying it keep it in their history. It stops appearing when you tag something new.",
  "@tagsDeleteConfirmBody": {
    "description": "Says what survives, because a soft delete is not what \"delete\" usually promises (ARCH_3 §4)."
  },
  "tagsDeleteConfirmTitle": "Delete this tag?",
  "tagsDeleteHelp": "Anything already tagged keeps its history. The tag just stops being offered.",
  "tagsDeleted": "Tag deleted",
  "tagsEmptyBody": "Tags let you group things across accounts — \"Kitchen\", \"Car\", \"Diwali\".",
  "tagsEmptyTitle": "No tags yet",
  "tagsLoading": "Loading tags…",
  "tagsMissingBody": "It may have been deleted. Go back and pick another.",
  "tagsMissingTitle": "That tag is not here",
  "tagsNoScopesWarning": "This tag is not offered anywhere. Turn on at least one place below, or it will never appear.",
  "@tagsNoScopesWarning": {
    "description": "A tag with no scopes cannot appear anywhere in the app, which makes it invisible everywhere except this screen — exactly the dead row somebody would hunt for in the pickers first."
  },
  "tagsSaved": "Tag saved",
  "tagsSystemChip": "Built in",
  "unitBaseGrams": "grams",
  "unitBaseMillilitres": "millilitres",
  "unitBasePieces": "pieces",
  "unitCategoryHeader": "What does it measure?",
  "unitCategoryNewHelp": "Choose carefully: this cannot be changed later.",
  "unitCodeHelp": "What you will see beside a quantity — kg, ml, pc.",
  "unitCodeLabel": "Short code",
  "unitCodeLockedHelp": "Fixed once the unit exists, because other records point at it.",
  "unitEditorEditTitle": "Edit unit",
  "unitEditorSave": "Save unit",
  "unitEditorTitle": "New unit",
  "unitFactorHeader": "How big is it?",
  "unitFactorMustBePositive": "That has to be more than zero.",
  "@unitFactorMustBePositive": {
    "description": "Guarded rather than trusted: a zero factor would convert every quantity in the unit to nothing and divide the inventory valuation by zero."
  },
  "unitFactorThisUnit": "this unit",
  "@unitFactorThisUnit": {
    "description": "Stands in for the name while the field is still empty, so the question reads as a sentence either way."
  },
  "unitFactorVaries": "It varies — I cannot give one number",
  "unitNameLabel": "Name",
  "unitVariesBack": "Actually, I can give a number",
  "@unitVariesBack": {
    "description": "A way back, for somebody who realises on reading this that they can state an amount."
  },
  "unitVariesCreateItem": "Create an item instead",
  "unitVariesInsteadBody": "Add \"Biscuit packet\" as its own item, counted in pieces. Then two packets is two of that item, and Alaya can price and track them properly.",
  "unitVariesInsteadTitle": "Make it an item instead",
  "unitVariesTitle": "Then it is not a unit",
  "unitVariesWhy": "A unit has to be the same amount every time. One packet of biscuits and one packet of rice are different weights, so Alaya could not add two packets together or work out what one cost.",
  "@unitVariesWhy": {
    "description": "ARCH_1 §5.3 explained by consequence rather than by quoting the rule. This is what makes the alternative obviously better instead of merely mandated."
  },
  "unitsAdd": "Add a unit",
  "unitsCategoriesFixedNote": "Weight, volume and count are the only three kinds there are. Alaya never converts between them, so a kilo can never become a litre by accident.",
  "@unitsCategoriesFixedNote": {
    "description": "ARCH_1 §5.3 and Law L8, stated where somebody about to add a unit reads it before trying rather than as a refusal afterwards."
  },
  "unitsDelete": "Delete this unit",
  "unitsDeleteConfirmBody": "Anything already bought in this unit keeps its quantity, but that quantity would no longer be readable. Only delete a unit you have not used.",
  "@unitsDeleteConfirmBody": {
    "description": "The R18 failure from the other direction: a quantity whose unit has gone cannot be converted or valued."
  },
  "unitsDeleteConfirmTitle": "Delete this unit?",
  "unitsDeleteHelp": "Only possible while nothing is measured in it.",
  "unitsDeleted": "Unit deleted",
  "unitsEmptyBody": "Alaya ships with the common ones. Add one if you measure something differently.",
  "unitsEmptyTitle": "No units",
  "unitsLoading": "Loading units…",
  "unitsMissingBody": "It may have been deleted. Go back and pick another.",
  "unitsMissingTitle": "That unit is not here",
  "unitsSaved": "Unit saved",
  "unitsSystemChip": "Built in",
  "currenciesRowSubtitle": "{symbol} · {digits, plural, =0{no decimal places} =1{1 decimal place} other{{digits} decimal places}}",
  "@currenciesRowSubtitle": {
    "description": "The precision matters to the reader: JPY has none, so an amount typed as 1200 is ¥1,200 and not ¥12.00.",
    "placeholders": {
      "symbol": {
        "type": "String"
      },
      "digits": {
        "type": "int"
      }
    }
  },
  "currenciesRowTitle": "{code} · {name}",
  "@currenciesRowTitle": {
    "description": "A currency row: the code first, because it is what the pickers show.",
    "placeholders": {
      "code": {
        "type": "String"
      },
      "name": {
        "type": "String"
      }
    }
  },
  "dataExportDone": "Backup saved as {fileName}",
  "@dataExportDone": {
    "description": "Names the file, because a backup the user cannot identify later is one they will not trust when they need it (ARCH_3 §3.4).",
    "placeholders": {
      "fileName": {
        "type": "String"
      }
    }
  },
  "lockThrottled": "Too many attempts. Try again in {time}",
  "@lockThrottled": {
    "description": "The countdown ticks. Formatted in Dart as m:ss, because a plural on \"second\" cannot express 1:05.",
    "placeholders": {
      "time": {
        "type": "String"
      }
    }
  },
  "onboardingCurrencyChip": "{code} {symbol}",
  "@onboardingCurrencyChip": {
    "placeholders": {
      "code": {
        "type": "String"
      },
      "symbol": {
        "type": "String"
      }
    }
  },
  "onboardingStepOf": "Step {step} of {total}",
  "@onboardingStepOf": {
    "description": "Words and a count rather than dots: the one question people abandon a setup flow over is how long it will take.",
    "placeholders": {
      "step": {
        "type": "int"
      },
      "total": {
        "type": "int"
      }
    }
  },
  "pinSetupLength": "{length} digits",
  "@pinSetupLength": {
    "placeholders": {
      "length": {
        "type": "int"
      }
    }
  },
  "recoveryTypeToConfirm": "Type {word} to confirm",
  "@recoveryTypeToConfirm": {
    "description": "The word is passed in from DataTransferPort.eraseConfirmationWord and is deliberately not translated, so a support article can tell anyone what to type.",
    "placeholders": {
      "word": {
        "type": "String"
      }
    }
  },
  "securityAutoEraseBody": "When on, {count} wrong PIN attempts in a row will delete everything on this device.",
  "@securityAutoEraseBody": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "securityAutoEraseConfirmBody": "After {count} failed attempts, every account, transaction and item on this device is deleted. There is no undo, and no copy unless you have made a backup.",
  "@securityAutoEraseConfirmBody": {
    "description": "The scary confirm names the number. A generic \"are you sure?\" would not earn consent to a setting that destroys a household’s records.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "securityAutoLockBody": "Locks again after {seconds} seconds in the background.",
  "@securityAutoLockBody": {
    "description": "Stated rather than configurable in 8A: autoLockDelay is a constant, and a picker writing a setting nothing reads would be a dead control.",
    "placeholders": {
      "seconds": {
        "type": "int"
      }
    }
  },
  "settingsAccountCount": "{count, plural, =0{No accounts} =1{1 account} other{{count} accounts}}",
  "@settingsAccountCount": {
    "description": "Archived accounts included, because this row is the only way to reach one and restore it.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "settingsCurrencyCount": "{enabled} of {total} enabled",
  "@settingsCurrencyCount": {
    "placeholders": {
      "enabled": {
        "type": "int"
      },
      "total": {
        "type": "int"
      }
    }
  },
  "settingsPayeeCount": "{count, plural, =0{No payees} =1{1 payee} other{{count} payees}}",
  "@settingsPayeeCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "settingsPaymentMethodCount": "{count, plural, =0{No payment methods} =1{1 payment method} other{{count} payment methods}}",
  "@settingsPaymentMethodCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "settingsTagCount": "{count, plural, =0{No tags} =1{1 tag} other{{count} tags}}",
  "@settingsTagCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "settingsUnitCount": "{count, plural, =0{No units} =1{1 unit} other{{count} units}}",
  "@settingsUnitCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "unitFactorHelp": "One of this unit has to be the same number of {base} every time.",
  "@unitFactorHelp": {
    "description": "The condition for being a unit at all. Somebody who reads this and cannot meet it has found the \"make it an item\" path.",
    "placeholders": {
      "base": {
        "type": "String"
      }
    }
  },
  "unitFactorQuestion": "How many {base} is one {unit}?",
  "@unitFactorQuestion": {
    "description": "Asked in base units, never in the stored thousandths — reproducing that arithmetic is what ARCH_4 R18 got wrong three times.",
    "placeholders": {
      "base": {
        "type": "String"
      },
      "unit": {
        "type": "String"
      }
    }
  },
  "unitsEquals": "1 {code} = {amount} {base}",
  "@unitsEquals": {
    "description": "What the unit is, assembled from the stored thousandths so the reader never meets them.",
    "placeholders": {
      "code": {
        "type": "String"
      },
      "amount": {
        "type": "String"
      },
      "base": {
        "type": "String"
      }
    }
  },
  "unitsRowTitle": "{name} ({code})",
  "@unitsRowTitle": {
    "placeholders": {
      "name": {
        "type": "String"
      },
      "code": {
        "type": "String"
      }
    }
  },
  "attachmentsAdd": "Add an attachment",
  "attachmentsAddFailed": "That could not be attached",
  "attachmentsAdded": "Attached",
  "attachmentsChoosePhoto": "Choose a photo",
  "@attachmentsChoosePhoto": {
    "description": "Not \"take a photo\": capture needs image_picker, which ARCH_1 §7 does not pin."
  },
  "attachmentsDelete": "Remove",
  "attachmentsDeleteConfirmBody": "The file is deleted from this phone. Backups you have already made still contain it.",
  "attachmentsDeleteConfirmTitle": "Remove this attachment?",
  "attachmentsDeleteFailed": "That could not be removed",
  "attachmentsDeleted": "Attachment removed",
  "attachmentsMissing": "That file is missing from this phone.",
  "attachmentsNone": "Nothing attached",
  "attachmentsOpen": "Open attachment",
  "attachmentsStoredLocally": "Kept on this phone only, and included in your backups.",
  "backupConfirmAction": "Make the backup",
  "backupConfirmTitle": "Make a backup?",
  "backupDone": "Backup saved",
  "backupFailed": "The backup could not be made",
  "backupForget": "Forget",
  "backupForgetConfirmBody": "This removes it from the list only. The backup file itself stays wherever you put it — Alaya cannot reach into your Drive or your chats.",
  "@backupForgetConfirmBody": {
    "description": "Says what does *not* happen: \"remove\" over a backup reads as deleting the file."
  },
  "backupForgetConfirmTitle": "Forget this entry?",
  "backupForgetFailed": "That entry could not be removed",
  "backupForgotten": "Entry removed",
  "backupHistoryEmptyBody": "Make one now, and keep it somewhere that is not this phone.",
  "@backupHistoryEmptyBody": {
    "description": "Says where, because a backup sitting on the device it protects is not a backup."
  },
  "backupHistoryEmptyTitle": "No backups yet",
  "backupHistoryHeader": "Backups you have made",
  "backupHistoryLoading": "Loading your backups…",
  "backupMakeHeader": "Make a backup",
  "backupRestoreBody": "Merge a backup into what you have, or replace everything with it.",
  "backupRestoreHeader": "Restore",
  "backupRestoreTitle": "Restore from a backup",
  "backupSaveBody": "Choose where to put it. Alaya needs no storage permission — you pick the folder.",
  "backupSaveTitle": "Save a copy",
  "backupShareBody": "Send it to WhatsApp, Drive, or anywhere else.",
  "backupShareTitle": "Share a copy",
  "backupTitle": "Backup",
  "reminderKindExpiry": "Things going off",
  "reminderKindExpiryHelp": "Food and medicine reaching their use-by date.",
  "reminderKindLowStock": "Running low",
  "reminderKindLowStockHelp": "Not offered as a reminder: being low on something has no date, so it would arrive every morning until you shopped.",
  "@reminderKindLowStockHelp": {
    "description": "The row exists because the enum does; the help says why it is not in the digest."
  },
  "reminderKindRecurring": "Bills and subscriptions",
  "reminderKindRecurringHelp": "When a recurring payment falls due.",
  "reminderKindService": "Appliance servicing",
  "reminderKindServiceHelp": "When something is due for its next service.",
  "reminderKindWarranty": "Warranties ending",
  "reminderKindWarrantyHelp": "Before a warranty runs out, while you can still use it.",
  "remindersBlocked": "Notifications are turned off for Alaya. Turn them on in your phone’s Settings › Apps › Alaya › Notifications.",
  "@remindersBlocked": {
    "description": "Names the place. \"Notifications are blocked\" without saying where is a dead end."
  },
  "remindersDenied": "Alaya needs permission to send notifications.",
  "remindersDigestExplainer": "Alaya sends one message a day about what is coming up — not a notification for every item.",
  "@remindersDigestExplainer": {
    "description": "ARCH_3 §7’s \"fewer, better notifications\", stated before the toggles so somebody knows what turning one on means."
  },
  "remindersDigestRow": "Daily summary",
  "remindersKindsHeader": "What to remind me about",
  "remindersLoading": "Loading your reminders…",
  "remindersNoneScheduledBody": "Turn on a reminder above and Alaya will show what it has planned here.",
  "@remindersNoneScheduledBody": {
    "description": "Explains rather than apologises: empty is the normal state with everything off."
  },
  "remindersNoneScheduledTitle": "Nothing scheduled",
  "remindersScheduledHeader": "Currently scheduled",
  "remindersTimeHeader": "When",
  "remindersTimeSaved": "Reminder time changed",
  "remindersTimeTitle": "Daily summary time",
  "remindersTitle": "Reminders",
  "remindersToggleFailed": "That could not be changed",
  "restoreApplyMerge": "Merge the backup",
  "restoreApplyReplace": "Replace everything",
  "restoreChooseAnother": "Choose another file",
  "restoreChooseFile": "Choose a file",
  "restoreChosenHeader": "Chosen file",
  "restoreContinueReplace": "Continue to replace",
  "restoreDone": "Restored",
  "restoreLockNotRestored": "Your PIN is never restored. It is kept outside the backup, so opening someone else’s backup can never change who can open this app.",
  "@restoreLockNotRestored": {
    "description": "ARCH_3 §3.2’s last line, on the one screen where somebody might expect otherwise. Shown at all three stages."
  },
  "restoreMergeBody": "Adds what the backup has and updates what is newer. Nothing you have now is lost.",
  "@restoreMergeBody": {
    "description": "The default, and the description says why: merge keeps rows the backup does not have."
  },
  "restoreMergeTitle": "Merge",
  "restoreModeHeader": "How should it be applied?",
  "restoreNotADatabase": "That file is not an Alaya backup.",
  "restorePickBody": "Choose a backup file. Alaya will check it before anything changes.",
  "restoreReplaceBody": "Throws away what is on this phone and uses the backup instead.",
  "restoreReplaceTitle": "Replace everything",
  "restoreReplaceWarning": "Everything currently on this phone will be thrown away and replaced by the backup. Anything recorded since that backup was made will be gone.",
  "restoreRollbackAvailable": "Restored the wrong file? You can put your previous data back.",
  "restoreRollbackPromise": "Alaya takes a snapshot of your current data first, so you can undo this straight afterwards.",
  "@restoreRollbackPromise": {
    "description": "Said before the typed confirmation, because somebody who knows there is a way back reads the warning as information rather than a threat."
  },
  "restoreTitle": "Restore",
  "restoreUndo": "Undo the replace",
  "supportConsentUnavailable": "Adverts need a choice about personalisation that could not be loaded right now. Nothing has been requested.",
  "@supportConsentUnavailable": {
    "description": "Says what happened rather than showing a button that cannot work: without consent settled, no ad is requested at all."
  },
  "supportIntro": "Alaya is free, works offline, and has no accounts to sign up for. If it is useful to you, there are two ways to help.",
  "supportLoading": "Loading…",
  "supportNoAd": "No advert available right now",
  "supportNoPaidFeatures": "Nothing here unlocks anything. There are no paid features — the whole app is already yours.",
  "@supportNoPaidFeatures": {
    "description": "Keeps this a tip rather than a paywall wearing a friendly label, and says so where somebody decides."
  },
  "supportThanks": "Thank you. That genuinely helps.",
  "supportTipBody": "A one-time thank-you through the Play Store. It is not a subscription.",
  "supportTipHeader": "Leave a tip",
  "supportTipUnavailable": "Tips are not available on this device right now.",
  "supportTitle": "Support Alaya",
  "supportWatchAction": "Watch an advert",
  "supportWatchBody": "One advert, when you choose to. Alaya never shows one anywhere else in the app.",
  "@supportWatchBody": {
    "description": "True by construction: one file imports the SDK and only this screen starts it."
  },
  "supportWatchHeader": "Watch a short advert",
  "trashDeletedOn": "Deleted",
  "trashEmptyBody": "Things you delete are kept here for 30 days before they go for good.",
  "trashEmptyNow": "Empty now",
  "trashEmptyNowConfirmBody": "Everything in the trash is deleted permanently. This is not the trash — there is nowhere left for it to go.",
  "@trashEmptyNowConfirmBody": {
    "description": "The only hard delete a user can reach, so the body says it plainly."
  },
  "trashEmptyNowConfirmTitle": "Empty the trash?",
  "trashEmptyTitle": "The trash is empty",
  "trashGoesOn": "· kept for 30 days",
  "@trashGoesOn": {
    "description": "Every row says when it goes: a trash that silently empties is one people stop trusting."
  },
  "trashKindAsset": "Appliances",
  "trashKindItem": "Items",
  "trashKindPayee": "Payees",
  "trashKindRecurring": "Recurring",
  "trashKindShoppingList": "Shopping lists",
  "trashKindTag": "Tags",
  "trashKindTransaction": "Transactions",
  "trashLoading": "Loading the trash…",
  "trashNoMatchBody": "Remove a filter to see the rest.",
  "trashNoMatchTitle": "Nothing matches that filter",
  "trashPurgeConfirmBody": "It will not go back to the trash. There is no undo.",
  "trashPurgeConfirmTitle": "Delete this for good?",
  "trashPurgeFailed": "That could not be deleted",
  "trashPurgeOne": "Delete for good",
  "trashPurgedOne": "Deleted for good",
  "trashRestore": "Restore",
  "trashRestoreFailed": "That could not be restored",
  "trashRestored": "Restored",
  "trashTitle": "Trash",
  "backupDoneNamed": "Backup saved as {fileName}",
  "@backupDoneNamed": {
    "description": "Names the file, because a backup you cannot identify later is one you will not trust when you need it.",
    "placeholders": {
      "fileName": {
        "type": "String"
      }
    }
  },
  "backupHistorySize": "· {size}",
  "@backupHistorySize": {
    "description": "The unit changes with the magnitude, so the number is formatted in Dart — a translator cannot choose between KB and MB inside a placeholder.",
    "placeholders": {
      "size": {
        "type": "String"
      }
    }
  },
  "remindersTimeBody": "Sent at {time} each day",
  "@remindersTimeBody": {
    "placeholders": {
      "time": {
        "type": "String"
      }
    }
  },
  "restoreDoneDetail": "{tables, plural, =1{1 table restored} other{{tables} tables restored}}",
  "@restoreDoneDetail": {
    "placeholders": {
      "tables": {
        "type": "int"
      }
    }
  },
  "restoreNewerSchema": "That backup is from a newer version of Alaya (version {backup}) than this app understands (version {app}). Update Alaya and try again.",
  "@restoreNewerSchema": {
    "description": "ARCH_3 §3.2’s gate, stated with both numbers. A refusal without them is one nobody can act on.",
    "placeholders": {
      "backup": {
        "type": "int"
      },
      "app": {
        "type": "int"
      }
    }
  },
  "restoreTypeToConfirm": "Type {word} to confirm",
  "@restoreTypeToConfirm": {
    "description": "The word is not translated, so a support article can tell anyone what to type.",
    "placeholders": {
      "word": {
        "type": "String"
      }
    }
  },
  "supportTipAction": "Leave a tip · {price}",
  "@supportTipAction": {
    "description": "The store’s own formatted price, never reformatted: Play localises it for the user’s account, which need not match this app’s home currency.",
    "placeholders": {
      "price": {
        "type": "String"
      }
    }
  },
  "trashPurged": "{count, plural, =0{Nothing to delete} =1{1 item deleted for good} other{{count} items deleted for good}}",
  "@trashPurged": {
    "description": "\"For good\" rather than \"deleted\", because this is the one hard delete in the app.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "dataBackupRowBody": "Save a copy, share it, or restore from one.",
  "dataTrashRowBody": "Things you delete are kept here for 30 days.",
  "settingsRemindersHelp": "One daily summary of what is coming up.",
  "settingsSupportHelp": "Optional, and nothing here unlocks anything.",
  "@settingsSupportHelp": {
    "description": "Says on the row itself that this is not a paywall, so the entry cannot read as one."
  },
  "settingsTrashCount": "{count, plural, =0{Nothing in the trash} =1{1 item} other{{count} items}}",
  "@settingsTrashCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "supportWatchTooltip": "Watch an advert to support Alaya",
  "@supportWatchTooltip": {
    "description": "The app bar action. Says what the tap does, because a joined-hands icon alone does not — and no advert is fetched until it is pressed."
  }
}
```

## Tests, and the layout additions

**Five fakes, two of which exist so a plugin never enters the test binary at all.** `FakeSupport` keeps
`google_mobile_ads` and `in_app_purchase` out; `FakeReminders` keeps `flutter_local_notifications` and `timezone`
out. Neither adapter could be faked without a contract — both are `final class` over platform channels, the same
argument 8A's ports rest on.

Every CRITICAL requirement is **asserted rather than assumed**:

**The export warning is checked by its words, including the third sentence.** `expect(find.textContaining('Only
share it somewhere you trust'))` is there precisely because 8A's paraphrase dropped it and nothing noticed. A key
can be renamed and a paraphrase can drift; the sentence is what §3.4 requires. The test also cancels both sheets
and asserts `exports == 0`, so the gate is proved to *stop* an export rather than merely appear before one.

**Permission is asserted as not-yet-requested on open**, then requested exactly once on the first switch-on. That
is the difference between honouring §7's contextual rule and merely claiming to.

**A refused permission leaves every switch off**, so a control cannot read *on* while the OS drops everything.

**Nothing is asked of `SupportPort` until the screen exists** — `initialisations` and `adLoads` are both zero
before `pumpOps`, and one after. Combined with `AdsAndBilling` being the only file importing either SDK, that is
both halves of "the rest of the app makes zero ad calls": no other file *can*, and this screen is what does.

**No advert is requested when consent could not be settled.** Requesting first and asking afterwards is what gets
an app pulled in the EEA.

`kTallViewport` for content assertions and 320×640 for the gate, split deliberately: every screen here is a lazy
list, so a row below the fold is never built and `findsNothing` passes for the wrong reason. That trap cost 8A two
rounds and is not repeated.

The layout file gains six cases. The one that matters most measures **§3.4's sentence — the longest required
string in the project — in the narrowest column at a doubled scale**: if the warning does not fit, the rule cannot
be honoured.

### `test/support/ops_harness.dart`

```dart
/// Shared scaffolding for the 8B widget tests.
///
/// **Five fakes, and two of them exist so that a plugin never runs in a test at all.** `SupportPort` keeps
/// `google_mobile_ads` and `in_app_purchase` out of the test binary; `ReminderPort` keeps
/// `flutter_local_notifications` and `timezone` out. Neither could be faked without a contract, because the
/// adapters are `final class` over platform channels — which is the same argument 8A's ports rest on.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/attachments/attachment_port.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart';
import 'package:alaya/domain/services/reminders/reminder_port.dart';
import 'package:alaya/domain/services/support/support_port.dart';
import 'package:alaya/domain/services/trash/trash_port.dart';

/// The narrowest phone this app supports (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// Tall enough that a lazy `ListView` builds its whole body.
///
/// **Content assertions get this; the U15 gate does not.** Every screen in this phase is a lazy list, so at
/// 320x640 a row below the fold is never built and `findsNothing` passes for the wrong reason — the trap that
/// cost 8A two rounds. Content tests ask *what exists*; the separate narrow tests ask *whether it fits*.
const Size kTallViewport = Size(320, 2400);

/// A future that never completes, for a loading branch.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// A stream that never emits, for a loading branch.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A `DataTransferPort` that records what it was asked and answers from fields.
class FakeTransfer implements DataTransferPort {
  /// Creates the fake.
  FakeTransfer({
    this.backupVersion = 1,
    this.schemaVersion = 1,
    this.history = const [],
    this.exportCancelled = false,
    this.rollbackExists = false,
    this.pickCancelled = false,
  });

  /// The version inside the file the picker returns.
  int backupVersion;

  /// The version this "app" writes.
  int schemaVersion;

  /// What `watchHistory` emits.
  List<BackupRecord> history;

  /// Whether the export reports a dismissed sheet.
  bool exportCancelled;

  /// Whether a rollback snapshot exists.
  bool rollbackExists;

  /// Whether the file chooser reports a dismissal.
  bool pickCancelled;

  /// How many exports were requested.
  int exports = 0;

  /// How many merges ran.
  int merges = 0;

  /// How many replaces ran.
  int replaces = 0;

  @override
  bool get canSaveToLocation => true;

  @override
  int get appSchemaVersion => schemaVersion;

  @override
  Future<Result<BackupArtefact?, Failure>> exportToLocation() async {
    exports += 1;
    return exportCancelled
        ? const Result.ok(null)
        : const Result.ok(
            (path: '/x/alaya.db', sizeBytes: 2048, isZipped: false, fileName: 'alaya.db'),
          );
  }

  @override
  Future<Result<BackupArtefact, Failure>> exportAndShare() async {
    exports += 1;
    return const Result.ok(
      (path: '/x/alaya.db', sizeBytes: 2048, isZipped: false, fileName: 'alaya.db'),
    );
  }

  @override
  Stream<List<BackupRecord>> watchHistory() => Stream.value(history);

  @override
  Future<Result<void, Failure>> forgetHistoryEntry(String id) async => const Result.ok(null);

  @override
  Future<Result<String?, Failure>> pickBackupFile() async =>
      pickCancelled ? const Result.ok(null) : const Result.ok('/tmp/backup.db');

  @override
  Future<Result<int, Failure>> readBackupVersion(String path) async =>
      Result.ok(backupVersion);

  @override
  Future<Result<RestoreOutcome, Failure>> merge(String path) async {
    merges += 1;
    return Result.ok((
      mode: RestoreMode.merge,
      tablesMerged: 12,
      backupSchemaVersion: backupVersion,
      rollbackAvailable: false,
    ));
  }

  @override
  Future<Result<RestoreOutcome, Failure>> replace(String path) async {
    replaces += 1;
    return Result.ok((
      mode: RestoreMode.replace,
      tablesMerged: 0,
      backupSchemaVersion: backupVersion,
      rollbackAvailable: true,
    ));
  }

  @override
  Future<Result<void, Failure>> rollback() async => const Result.ok(null);

  @override
  Future<bool> hasRollback() async => rollbackExists;

  @override
  Future<Result<void, Failure>> eraseEverything() async => const Result.ok(null);
}

/// A `TrashPort` over an in-memory list.
class FakeTrash implements TrashPort {
  /// Creates the fake.
  ///
  /// [loading] holds the stream open forever, which is the only way a loading branch is observable: a
  /// `Stream.value` resolves inside the first frame's microtask drain, so a skeleton assertion against one would
  /// pass for the wrong reason — the trap 8A hit twice.
  FakeTrash({List<TrashEntry>? entries, this.loading = false})
      : _entries = [...?entries];

  final List<TrashEntry> _entries;

  /// Whether `watchAll` never emits.
  final bool loading;

  /// How many rows the last purge removed.
  int purged = 0;

  /// How many restores ran.
  int restores = 0;

  @override
  Stream<List<TrashEntry>> watchAll() =>
      loading ? pendingStream<List<TrashEntry>>() : Stream.value(_entries);

  @override
  Stream<int> watchCount() => Stream.value(_entries.length);

  @override
  Future<Result<void, Failure>> restore(TrashEntry entry) async {
    restores += 1;
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> purge(TrashEntry entry) async {
    purged += 1;
    return const Result.ok(null);
  }

  @override
  Future<Result<int, Failure>> purgeAll() async {
    purged = _entries.length;
    return Result.ok(purged);
  }

  @override
  Future<Result<int, Failure>> purgeExpired() async => const Result.ok(0);
}

/// A `ReminderPort` that never touches a notification plugin.
class FakeReminders implements ReminderPort {
  /// Creates the fake.
  FakeReminders({
    ReminderSettings? settings,
    this.permissionState = ReminderPermission.granted,
    this.scheduled = const [],
  }) : _settings = settings ?? const ReminderSettings.fresh();

  ReminderSettings _settings;

  /// What the OS reports.
  ReminderPermission permissionState;

  /// What is scheduled.
  List<ScheduledReminder> scheduled;

  /// How many times permission was requested.
  int permissionRequests = 0;

  @override
  Stream<ReminderSettings> watchSettings() => Stream.value(_settings);

  @override
  Future<ReminderPermission> permission() async => permissionState;

  @override
  Future<ReminderPermission> requestPermission() async {
    permissionRequests += 1;
    return permissionState;
  }

  @override
  Future<Result<ReminderSettings, Failure>> setEnabled({
    required NotificationKind kind,
    required bool enabled,
  }) async {
    final next = {..._settings.enabled};
    enabled ? next.add(kind) : next.remove(kind);
    _settings = _settings.copyWith(enabled: next);
    return Result.ok(_settings);
  }

  @override
  Future<Result<ReminderSettings, Failure>> setDigestTime({
    required int hour,
    required int minute,
  }) async {
    _settings = _settings.copyWith(digestHour: hour, digestMinute: minute);
    return Result.ok(_settings);
  }

  @override
  Stream<List<ScheduledReminder>> watchScheduled() => Stream.value(scheduled);

  @override
  Future<Result<int, Failure>> rescheduleAll() async => const Result.ok(1);

  @override
  Future<Result<void, Failure>> cancelAll() async => const Result.ok(null);
}

/// A `SupportPort` that makes no ad call, because there is no SDK behind it.
class FakeSupport implements SupportPort {
  /// Creates the fake.
  FakeSupport({this.consent = AdConsent.obtained, this.adAvailable = true});

  /// Where consent stands.
  AdConsent consent;

  /// Whether an ad loads.
  bool adAvailable;

  /// How many times the SDK was brought up.
  int initialisations = 0;

  /// How many ad loads were requested.
  int adLoads = 0;

  @override
  Future<Result<void, Failure>> initialise() async {
    initialisations += 1;
    return const Result.ok(null);
  }

  @override
  Future<AdConsent> consentStatus() async => consent;

  @override
  Future<AdConsent> requestConsent() async => consent;

  @override
  Future<Result<void, Failure>> loadRewardedAd() async {
    adLoads += 1;
    return adAvailable
        ? const Result.ok(null)
        : const Result.failure(
            BusinessRuleFailure('No advert was available.', rule: 'noFill'),
          );
  }

  @override
  Future<Result<bool, Failure>> showRewardedAd() async => const Result.ok(true);

  @override
  Future<Result<List<TipProduct>, Failure>> tipProducts() async => const Result.ok(
        [TipProduct(id: 'alaya_tip_once', title: 'Tip', price: '₹99.00')],
      );

  @override
  Future<Result<bool, Failure>> buyTip(String productId) async => const Result.ok(true);
}

/// An `AttachmentPort` over an in-memory list.
class FakeAttachments implements AttachmentPort {
  /// Creates the fake.
  FakeAttachments({this.rows = const [], this.cancelled = false});

  /// What `watchFor` emits.
  List<Attachment> rows;

  /// Whether the picker reports a dismissal.
  bool cancelled;

  @override
  Stream<List<Attachment>> watchFor({
    required AttachmentOwner owner,
    required String ownerId,
  }) =>
      Stream.value(rows);

  @override
  Stream<int> watchCountFor({
    required AttachmentOwner owner,
    required String ownerId,
  }) =>
      Stream.value(rows.length);

  @override
  Future<Result<Attachment?, Failure>> attach({
    required AttachmentOwner owner,
    required String ownerId,
  }) async =>
      cancelled ? const Result.ok(null) : Result.ok(attachment());

  @override
  Future<Result<String, Failure>> resolvePath(Attachment attachment) async =>
      const Result.ok('/tmp/x.jpg');

  @override
  Future<Result<void, Failure>> open(Attachment attachment) async => const Result.ok(null);

  @override
  Future<Result<void, Failure>> delete(Attachment attachment) async => const Result.ok(null);

  @override
  Future<Result<List<String>, Failure>> allFilePaths() async => const Result.ok([]);
}

/// One trash entry.
TrashEntry trashEntry({
  String id = 'tr-1',
  TrashKind kind = TrashKind.transaction,
  String label = 'Groceries',
  int deletedAt = 1754000000000,
}) =>
    TrashEntry(
      id: id,
      kind: kind,
      label: label,
      deletedAtUtcMillis: deletedAt,
      purgeAfterUtcMillis: deletedAt + TrashPort.retention.inMilliseconds,
    );

/// One backup record.
BackupRecord backupRecord({String id = 'bk-1', String path = '/x/alaya-2026-08-08.db'}) =>
    BackupRecord(
      id: id,
      filePath: path,
      sizeBytes: 4096,
      schemaVersion: 1,
      takenAtUtcMillis: 1754000000000,
    );

/// One attachment.
Attachment attachment({String id = 'at-1'}) => Attachment(
      id: id,
      owner: AttachmentOwner.transaction,
      ownerId: 'tx-1',
      relativePath: '$id.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: 1024,
      addedAtUtcMillis: 1754000000000,
    );

/// One scheduled reminder.
ScheduledReminder scheduledReminder({
  NotificationKind kind = NotificationKind.expiry,
  int dateKey = 20260812,
}) =>
    ScheduledReminder(
      id: 'ns-1',
      kind: kind,
      on: DateKey(dateKey),
      androidNotificationId: 1,
    );

/// Overrides every port 8B's screens reach.
///
/// **Fixed length**, per ARCH_6 P5: a conditional entry changes the count between scopes and Riverpod refuses it,
/// while two `pumpWidget` calls in one test silently reuse the first scope — so a varying list fails both ways.
List<Override> opsOverrides({
  FakeTransfer? transfer,
  FakeTrash? trash,
  FakeReminders? reminders,
  FakeSupport? support,
  FakeAttachments? attachments,
}) =>
    [
      dataTransferPortProvider.overrideWithValue(transfer ?? FakeTransfer()),
      trashPortProvider.overrideWithValue(trash ?? FakeTrash()),
      reminderPortProvider.overrideWithValue(reminders ?? FakeReminders()),
      supportPortProvider.overrideWithValue(support ?? FakeSupport()),
      attachmentPortProvider.overrideWithValue(attachments ?? FakeAttachments()),
    ];

/// Pumps [child] inside the app's theme and localisations.
///
/// The text scaler goes through `MaterialApp.builder`, because `WidgetsApp` re-establishes `MediaQuery` from the
/// view and an override placed above it never arrives.
Future<void> pumpOps(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pump();
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
    testWidgets('every export path goes through a sheet carrying ARCH_3 §3.4 verbatim', (tester) async {
      final transfer = FakeTransfer();
      await pumpOps(tester, const BackupScreen(),
          overrides: opsOverrides(transfer: transfer), size: kTallViewport);
      await tester.pumpAndSettle();

      for (final action in ['Save a copy', 'Share a copy']) {
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();

        // **The exact sentence, including the third clause.** 8A shipped a paraphrase that dropped "Only share it
        // somewhere you trust" — the only actionable sentence of the three — and nothing caught it until §3.4 was
        // read directly. Asserting the words rather than the key is what stops that recurring.
        expect(find.textContaining('not encrypted'), findsOneWidget);
        expect(find.textContaining('every transaction, balance and account name'), findsOneWidget);
        expect(find.textContaining('Only share it somewhere you trust'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
      // Cancelling the warning wrote nothing, twice.
      expect(transfer.exports, 0);
    });

    testWidgets('history renders its four states', (tester) async {
      await pumpOps(tester, const BackupScreen(),
          overrides: opsOverrides(transfer: FakeTransfer(history: const [])),
          size: kTallViewport);
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);

      await pumpOps(tester, const BackupScreen(),
          overrides: opsOverrides(transfer: FakeTransfer(history: [backupRecord()])),
          size: kTallViewport);
      await tester.pumpAndSettle();
      // The name is derived from the path, because the table stores no file name.
      expect(find.text('alaya-2026-08-08.db'), findsOneWidget);
    });
  });

  group('restore — the guards, in order', () {
    testWidgets('a newer backup is refused with both version numbers', (tester) async {
      await pumpOps(tester, const RestoreFlow(),
          overrides: opsOverrides(transfer: FakeTransfer(backupVersion: 7, schemaVersion: 1)),
          size: kTallViewport);
      await tester.pumpAndSettle();
      expect(find.textContaining('Choose a file'), findsOneWidget);
      // The gate itself is exercised in the port's own test; here the screen must be able to *say* it, which is
      // what a refusal nobody can act on fails at.
      expect(find.textContaining('Alaya is never restored'), findsNothing);
      expect(find.textContaining('PIN is never restored'), findsOneWidget);
    });

    testWidgets('the lock-not-restored line is on the first screen', (tester) async {
      await pumpOps(tester, const RestoreFlow(),
          overrides: opsOverrides(), size: kTallViewport);
      await tester.pumpAndSettle();
      // ARCH_3 §3.2's last line, on the one screen where somebody might expect otherwise.
      expect(find.textContaining('never restored'), findsOneWidget);
    });
  });

  group('reminders — contextual permission, all off', () {
    testWidgets('every toggle starts off', (tester) async {
      await pumpOps(tester, const RemindersScreen(),
          overrides: opsOverrides(reminders: FakeReminders()), size: kTallViewport);
      await tester.pumpAndSettle();
      final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
      // ARCH_3 §7: all reminders default off. `ReminderSettings.fresh()` is what makes that true.
      expect(switches.isNotEmpty, isTrue);
      expect(switches.every((tile) => tile.value == false), isTrue);
    });

    testWidgets('permission is requested on the first switch-on, not on open', (tester) async {
      final reminders = FakeReminders(permissionState: ReminderPermission.notRequested);
      await pumpOps(tester, const RemindersScreen(),
          overrides: opsOverrides(reminders: reminders), size: kTallViewport);
      await tester.pumpAndSettle();
      // **Nothing asked merely by opening the screen.** Asking on launch is what gets an app denied for good.
      expect(reminders.permissionRequests, 0);

      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      expect(reminders.permissionRequests, 1);
    });

    testWidgets('a refused request leaves the switch off', (tester) async {
      final reminders = FakeReminders(permissionState: ReminderPermission.denied);
      await pumpOps(tester, const RemindersScreen(),
          overrides: opsOverrides(reminders: reminders), size: kTallViewport);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      // A control reading "on" while the OS drops every notification is a control that lies.
      final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
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
      await pumpOps(tester, const TrashScreen(),
          overrides: opsOverrides(trash: FakeTrash(loading: true)));
      expect(find.byType(AlayaListSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('empty explains the thirty days', (tester) async {
      await pumpOps(tester, const TrashScreen(),
          overrides: opsOverrides(trash: FakeTrash(entries: const [])));
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

    testWidgets('empty now is confirmed before anything is purged', (tester) async {
      final trash = FakeTrash(entries: [trashEntry(), trashEntry(id: 'tr-2', label: 'Rice')]);
      await pumpOps(tester, const TrashScreen(),
          overrides: opsOverrides(trash: trash), size: kTallViewport);
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

      await pumpOps(tester, const SupportScreen(),
          overrides: opsOverrides(support: support), size: kTallViewport);
      await tester.pumpAndSettle();

      // **One initialisation, from `initState`.** The rest of the app makes zero ad calls because
      // `AdsAndBilling` is the only file importing either SDK — this asserts the other half, that the screen is
      // what triggers it.
      expect(support.initialisations, 1);
      expect(support.adLoads, 1);
    });

    testWidgets('no advert is requested when consent could not be settled', (tester) async {
      final support = FakeSupport(consent: AdConsent.unavailable);
      await pumpOps(tester, const SupportScreen(),
          overrides: opsOverrides(support: support), size: kTallViewport);
      await tester.pumpAndSettle();

      // Requesting an ad before consent is settled is what gets an app pulled in the EEA.
      expect(support.adLoads, 0);
      expect(find.textContaining('Nothing has been requested'), findsOneWidget);
    });

    testWidgets('the tip shows the store price, unformatted by us', (tester) async {
      await pumpOps(tester, const SupportScreen(),
          overrides: opsOverrides(support: FakeSupport()), size: kTallViewport);
      await tester.pumpAndSettle();
      // The store's own string. Reformatting it through AmountText would render it in the wrong currency.
      expect(find.textContaining('₹99.00'), findsOneWidget);
    });

    testWidgets('says plainly that nothing is unlocked', (tester) async {
      await pumpOps(tester, const SupportScreen(),
          overrides: opsOverrides(), size: kTallViewport);
      await tester.pumpAndSettle();
      expect(find.textContaining('no paid features'), findsOneWidget);
    });
  });

  group('the gate', () {
    testWidgets('every screen renders at 320x640 with a doubled text scale', (tester) async {
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

### `test/shared/layout_overflow_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_bar_chart.dart';
import 'package:alaya/features/lock/presentation/widgets/pin_pad.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_donut_chart.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_line_chart.dart';
import 'package:alaya/features/analytics/presentation/widgets/slice_bar_list.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/features/calendar/presentation/widgets/day_sheet.dart';
import 'package:alaya/features/dashboard/presentation/widgets/funds_header.dart';
import 'package:alaya/features/dashboard/presentation/widgets/insight_card.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/presentation/sheets/delete_transaction_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/freeze_conversion_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/line_item_editor.dart';
import 'package:alaya/features/expense/presentation/sheets/quick_add_sheet.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_filter_sheet.dart';
import 'package:alaya/features/expense/providers/quick_add_providers.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/features/inventory/presentation/sheets/consume_sheet.dart';
import 'package:alaya/features/inventory/providers/consume_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/recurring/presentation/sheets/pay_sheet.dart';
import 'package:alaya/features/recurring/providers/pay_providers.dart';
import 'package:alaya/features/service/presentation/sheets/dispose_sheet.dart';
import 'package:alaya/features/service/presentation/widgets/contact_action.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/shopping/presentation/sheets/entry_editor_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/generate_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/list_manager_sheet.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_expandable_fab.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';
import 'package:alaya/shared/widgets/frequency_preview.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/loading_state.dart';
import 'package:alaya/shared/widgets/module_tile.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

import '../support/calendar_harness.dart' as cal;
import '../support/expense_harness.dart';
import '../support/fake_settings_repository.dart';

/// The only thing in this project that catches a layout overflow (ARCH_3 §8.3, ARCH_5 U2).
///
/// **Every sheet and every full-height state belongs here.** These defects are invisible to
/// `dart analyze`, to a file-by-file scan and to looking at the screen, because the missing
/// affordance is always an *ancestor*: the widget under review is locally correct and the parent
/// that should have given it room, or a way to scroll, is the one at fault.
///
/// They are also invisible to an ordinary widget test. A `RenderFlex` overflow reports through
/// `FlutterError.onError` rather than throwing at the site, so a test only fails on one if something
/// asks — which is exactly how an overflow hides in a suite that otherwise looks green. Every case
/// below asks, via `tester.takeException()`.
void main() {
  /// Roughly what a software keyboard takes from a phone in portrait.
  const double keyboardInset = 320;

  /// Roughly the room a list area has left on a small phone with a keyboard up.
  const Size squeezed = Size(320, 140);

  Widget host(
    Widget child, {
    double bottomInset = 0,
    double textScale = 1,
    List<Override> overrides = const [],
  }) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AlayaTheme.light(AlayaPresets.activePreset),
          // Every expense sheet reads `AlayaStrings.of(context)`, which unwraps a null without a
          // delegate installed. The Phase 5 groups pass literal strings, so this file went without
          // one until real screens arrived — and then failed as a null-check rather than as a
          // missing translation, which is why it read like five separate defects.
          localizationsDelegates: const [
            AlayaStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AlayaStrings.supportedLocales,
          // Inside the app rather than above it. `WidgetsApp` re-establishes `MediaQuery` from the
          // view, so an outer one is discarded before anything under test can read it — and a test
          // that believes it has simulated a keyboard when it has not is worse than no test.
          builder: (context, inner) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewInsets: EdgeInsets.only(bottom: bottomInset),
              textScaler: TextScaler.linear(textScale),
            ),
            child: inner!,
          ),
          home: Scaffold(body: child),
        ),
      );

  /// Content taller than the room a keyboard leaves, so the assertions are about the scaffold rather
  /// than about how long a particular string happens to be.
  Widget tallContent() => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [SizedBox(width: 200, height: 400)],
      );

  group('AlayaBottomSheet', () {
    testWidgets('scrolls rather than overflowing with a keyboard up', (tester) async {
      await tester.pumpWidget(
        host(AlayaBottomSheet(child: tallContent()), bottomInset: keyboardInset),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('still fits when there is no keyboard', (tester) async {
      await tester.pumpWidget(host(AlayaBottomSheet(child: tallContent())));
      expect(tester.takeException(), isNull);
    });

    // The bug, reproduced deliberately. `Padding(bottom: viewInsets)` around a `MainAxisSize.min`
    // Column is correct in each half and broken together: the padding shrinks the space and the
    // Column has no way to give up the room it already took. **If this ever stops overflowing, the
    // guard above has stopped testing anything** — and the reason AlayaBottomSheet exists has
    // quietly gone away.
    testWidgets('the un-scaffolded shape it replaces still overflows', (tester) async {
      await tester.pumpWidget(
        host(
          Padding(
            padding: const EdgeInsets.only(bottom: keyboardInset),
            child: tallContent(),
          ),
        ),
      );
      expect(tester.takeException(), isA<FlutterError>());
    });
  });

  group('ConfirmSheet', () {
    testWidgets('survives a keyboard and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => ConfirmSheet.show(
                context,
                title: 'Delete this transaction?',
                body: 'You can undo this for the next few seconds.',
                confirmLabel: 'Delete',
                cancelLabel: 'Cancel',
                destructive: true,
              ),
              child: const Text('open'),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('AlayaFormScaffold', () {
    Widget form({bool submitting = false}) => AlayaFormScaffold(
          primaryLabel: 'Save expense',
          onPrimary: () {},
          secondaryLabel: 'Cancel',
          onSecondary: () {},
          isDirty: true,
          isSubmitting: submitting,
          discardTitle: 'Discard your changes?',
          discardBody: 'What you have typed will not be saved.',
          discardConfirmLabel: 'Discard',
          discardCancelLabel: 'Keep editing',
          child: const Column(
            children: [SizedBox(height: 300), TextField(), SizedBox(height: 300)],
          ),
        );

    testWidgets('body scrolls and the footer stays above the keyboard', (tester) async {
      await tester.pumpWidget(host(form(), bottomInset: keyboardInset));
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a doubled text scale with a keyboard up', (tester) async {
      await tester.pumpWidget(host(form(), bottomInset: keyboardInset, textScale: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the submitting footer does not grow the row past its box', (tester) async {
      await tester.pumpWidget(host(form(submitting: true), textScale: 2));
      expect(tester.takeException(), isNull);
    });
  });

  // Every sheet Phase 6A adds, at a keyboard inset and a doubled text scale — the two conditions
  // under which each of them is first used and least likely to have been looked at.
  group('expense sheets', () {
    final expenseOverrides = <Override>[
      homeCurrencyCodeProvider.overrideWith((ref) => 'INR'),
      homeDecimalDigitsProvider.overrideWith((ref) => 2),
      selectableAccountsProvider.overrideWith((ref) => Stream.value(const [kAccount])),
      quickAddTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      accountsByIdProvider
          .overrideWith((ref) => Stream.value(<String, Account>{kAccount.id: kAccount})),
      lineEditorItemsProvider.overrideWith((ref) => Stream.value(const <Item>[])),
      enabledCurrenciesProvider.overrideWith(
        (ref) => Stream.value(const [
          Currency(
            code: 'USD',
            name: 'US Dollar',
            symbol: r'$',
            decimalDigits: 2,
            isEnabled: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: expenseOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets('QuickAddSheet', (tester) => pumpSheet(tester, const QuickAddSheet()));

    testWidgets(
      'TransactionFilterSheet',
      (tester) => pumpSheet(tester, const TransactionFilterSheet()),
    );

    testWidgets(
      'LineItemEditor',
      (tester) => pumpSheet(
        tester,
        const LineItemEditor(
          currencyCode: 'INR',
          decimalDigits: 2,
          defaultDestination: TransactionLineDestination.inventory,
        ),
      ),
    );

    testWidgets(
      'DeleteTransactionSheet',
      (tester) => pumpSheet(tester, const DeleteTransactionSheet()),
    );

    testWidgets(
      'FreezeConversionSheet',
      (tester) => pumpSheet(tester, const FreezeConversionSheet(excludeCode: 'INR')),
    );
  });

  // Phase 6B's sheet, at a keyboard inset and a doubled text scale — the two conditions under
  // which it is first used and least likely to have been looked at (U2).
  group('inventory sheets', () {
    final inventoryOverrides = <Override>[
      consumeFefoProvider('item-1').overrideWith((ref) => Stream.value(const <Batch>[])),
      unitsInCategoryProvider(UnitCategory.weight).overrideWith(
        (ref) => Stream.value(const [
          Unit(
            code: 'kg',
            category: UnitCategory.weight,
            factorToBaseMilli: 1000000,
            displayName: 'kilogram',
            isSystem: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    testWidgets('ConsumeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: ConsumeSheet(
              itemId: 'item-1',
              unitCode: 'kg',
              category: UnitCategory.weight,
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: inventoryOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6C's three sheets, at a keyboard inset and a doubled text scale — the two conditions under
  // which each is first used and least likely to have been looked at (U2).
  group('shopping sheets', () {
    final shoppingOverrides = <Override>[
      entryItemsProvider.overrideWith((ref) => Stream.value(const <Item>[])),
      entryTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      entryCurrencyProvider.overrideWith((ref) async => 'INR'),
      entryDecimalDigitsProvider.overrideWith((ref) async => 2),
      entriesProvider('list-1').overrideWith((ref) => Stream.value(const <ShoppingEntry>[])),
      shoppingItemsByIdProvider.overrideWith((ref) => Stream.value(const <String, Item>{})),
      allListsProvider.overrideWith((ref) => Stream.value(const <ShoppingList>[])),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: shoppingOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets(
      'EntryEditorSheet',
      (tester) => pumpSheet(tester, const EntryEditorSheet(listId: 'list-1')),
    );

    testWidgets(
      'GenerateSheet',
      (tester) => pumpSheet(tester, const GenerateSheet(listId: 'list-1')),
    );

    testWidgets(
      'ListManagerSheet',
      (tester) => pumpSheet(tester, const ListManagerSheet()),
    );
  });

  // Phase 6D's pay sheet, at a keyboard inset and a doubled text scale — an amount field, a date
  // field, an account dropdown and a two-line note, all growing at once.
  group('recurring sheets', () {
    final recurringOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      payAccountsProvider.overrideWith((ref) => Stream.value(const <Account>[])),
      payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
    ];

    testWidgets('PaySheet', (tester) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(
            child: PaySheet(
              occurrenceId: 'occ-1',
              template: RecurringTemplate(
                id: 'tpl-1',
                name: 'A rent template with a name long enough to wrap at a doubled scale',
                normalizedName: 'rent',
                kind: RecurringKind.rent,
                direction: RecurringDirection.outflow,
                defaultAmount: const Money(120000, 'INR'),
                intervalUnit: RecurringIntervalUnit.month,
                intervalCount: 1,
                startDateKey: const DateKey(20260131),
                nextDueDateKey: const DateKey(20260831),
                isPaused: false,
                autoRemind: true,
                remindDaysBefore: 3,
                anchorDayOfMonth: 31,
              ),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: recurringOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6D adds, with a clamp note on every row.
  group('FrequencyPreview at a doubled text scale', () {
    testWidgets('three dates, two of them clamped', (tester) async {
      await tester.pumpWidget(
        host(
          const FrequencyPreview(
            dates: [
              PreviewedDate(dateKey: DateKey(20260131)),
              PreviewedDate(dateKey: DateKey(20260228), clamped: true),
              PreviewedDate(dateKey: DateKey(20260331)),
            ],
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6E's dispose sheet: seven choice chips, a date field, an optional amount and a note, all
  // growing at once under a keyboard inset.
  group('service sheets', () {
    final serviceOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('DisposeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: DisposeSheet(assetId: 'asset-1', currencyCode: 'INR'),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: serviceOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The contact block: a name, a number and a call button, none of them flexible.
  group('ContactAction at a doubled text scale', () {
    testWidgets('a long name beside a long number', (tester) async {
      await tester.pumpWidget(
        host(
          const ContactAction(
            phone: '+91 98765 43210',
            name: 'A service centre with a name long enough to wrap',
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6F's dashboard sections. Each is a card whose figures, chips and labels all grow at once, and
  // the funds header carries the only display-sized amount in the app.
  group('dashboard sections', () {
    final dashOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      // InsightCard's notifier restores its side from `app_settings` on the first frame, which
      // resolves `databaseProvider` unless this is here — the failure reads as a database bug in a
      // test that never mentions one (ARCH_6 P6).
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      dashboardCurrencyProvider.overrideWith((ref) async => 'INR'),
      dashboardDigitsProvider.overrideWith((ref) async => 2),
      totalFundsProvider.overrideWith(
        (ref) async => const NetWorth(
          total: Money(98765432, 'INR'),
          unconvertedCount: 3,
          isApproximate: true,
        ),
      ),
      upcomingProvider.overrideWith((ref) async => const <UpcomingEntry>[]),
    ];

    testWidgets('FundsHeader with both chips at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const FundsHeader(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('InsightCard with its switch at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const InsightCard(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6F adds. Two lines of text and a glyph inside a fixed aspect ratio is
  // exactly the shape that overflows when the text doubles and the box does not.
  group('ModuleTile at a doubled text scale', () {
    testWidgets('a long label beside a long count', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 160,
            height: 108,
            child: ModuleTile(
              label: 'Recurring commitments',
              icon: Icons.event_repeat,
              detail: '17 need attention before the end of the month',
              onTap: () {},
            ),
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 7A. Both shapes here are the ones that have already cost this project rounds: a sheet whose
  // content outgrows the viewport, and a grid of text cells whose row height does not move with the text.
  // Zero width, which is not a hypothetical: Android reports it on the first frame of every launch
  // ("D/FlutterRenderer: Width is zero. 0,0") and the FAB's slot subtracted padding from it, producing a
  // negative width and a red screen on startup. Every widget harness sets a real viewport before pumping,
  // which is exactly why nothing here caught it — so the degenerate viewport is now stated outright.
  group('degenerate viewports', () {
    testWidgets('the expandable FAB survives a zero-width first frame', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size.zero),
            child: Scaffold(
              floatingActionButton: AlayaExpandableFab(
                openLabel: 'Add',
                closeLabel: 'Close',
                actions: [
                  FabAction(label: 'One', icon: Icons.add, onPressed: () {}),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('calendar', () {
    List<Override> calOverrides({List<CalendarEvent> events = const []}) =>
        cal.calendarOverrides(cal.FakeCalendarRepository(events: events));

    final busyDay = <CalendarEvent>[
      cal.event(title: 'A payee with a name long enough to wrap at a doubled scale', amountMinor: 98765432),
      cal.event(
        type: CalendarEventType.serviceDue,
        refType: 'asset',
        refId: 'as-1',
        title: 'The boiler in the upstairs cupboard',
        baseSeverity: CalendarSeverity.warning,
      ),
      cal.event(
        type: CalendarEventType.batchExpiry,
        refType: 'inventoryBatch',
        refId: 'ba-1',
        title: 'Yoghurt, the large tub',
        baseSeverity: CalendarSeverity.warning,
      ),
    ];

    testWidgets('DaySheet with three grouped entries at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('DaySheet with a keyboard up as well', (tester) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // U26: `TableCalendar` takes a fixed `rowHeight`, so the grid computes one from the text scaler. If
    // that computation is ever replaced by a constant, this is the test that says so.
    testWidgets('the month grid at a doubled scale on the narrowest phone', (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 2, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the month grid at a tripled scale, which is past what U15 asks for',
        (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 3, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // The range header prints two formatted dates and a dash, which is the longest single string this
    // screen can produce — and it appears only in a mode the other cases never enter.
    testWidgets('the range header at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 2, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('22'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    // The screen's own composition, which the shared full-height group cannot reach: six measured rows
    // plus a header are taller than a squeezed list area on their own, so the grid and the state beneath
    // it have to share a scroll rather than compete for a fixed box.
    for (final scale in [1.0, 2.0]) {
      testWidgets('the whole screen in a squeezed viewport at ${scale}x', (tester) async {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: scale,
            overrides: calOverrides(events: busyDay),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    // Each of the three states in turn, in the same squeezed box. Loading and error sit in the sliver
    // that fills the remainder, and that remainder is negative here.
    testWidgets('loading, empty and error all survive the squeezed box', (tester) async {
      for (final repo in [
        cal.FakeCalendarRepository(pending: true),
        cal.FakeCalendarRepository(),
        cal.FakeCalendarRepository(error: 'view unavailable'),
      ]) {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: 2,
            overrides: cal.calendarOverrides(repo),
          ),
        );
        // `pump`, not `pumpAndSettle`: the loading case holds a `CircularProgressIndicator`, which
        // animates forever, so `pumpAndSettle` times out rather than settling. Two frames is enough to
        // resolve the completed futures in the other two cases.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('full-height states in a squeezed viewport', () {
    Widget inSqueezedBox(Widget child) => host(
          Center(
            child: SizedBox(width: squeezed.width, height: squeezed.height, child: child),
          ),
        );

    testWidgets('EmptyState with an icon, body and action', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          EmptyState(
            title: 'No transactions yet',
            body: 'Add your first expense and it will appear here.',
            icon: Icons.receipt_long_outlined,
            actionLabel: 'Add expense',
            onAction: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ErrorState with a retry — the tallest of the three', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          ErrorState(
            title: 'That did not work',
            body: 'Something went wrong on our side. Try again.',
            retryLabel: 'Try again',
            onRetry: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('LoadingState', (tester) async {
      await tester.pumpWidget(inSqueezedBox(const LoadingState(label: 'Loading')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('AlayaListSkeleton clips rather than overflowing', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(const AlayaListSkeleton(label: 'Loading transactions')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('EmptyState at a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: EmptyState(
                title: 'No transactions yet',
                body: 'Add your first expense and it will appear here.',
                icon: Icons.receipt_long_outlined,
                actionLabel: 'Add expense',
                onAction: () {},
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    // The states are also the shape the Theme Lab renders inside a half-width pane, which is where
    // the 150px `SizedBox` around an EmptyState used to overflow by roughly 58px.
    testWidgets('EmptyState in a half-width pane', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          const SizedBox(
            width: 134,
            child: EmptyState(title: 'No matches', body: 'Try a shorter search.'),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6A's line-items page: a full-height screen whose summary row, list rows and footer all
  // grow under text scale at once. Squeezed and doubled, which is the pair U21 exists for.
  group('the line items page', () {
    final editorOverrides = <Override>[
      transactionEditorProvider.overrideWith(
        () => _FixedEditor(
          AsyncValue.data(
            TransactionEditorState(
              currencyCode: 'INR',
              dateKey: const DateKey(20260801),
              amount: const Money(20000, 'INR'),
              lines: [
                TransactionLine(
                  id: 'l1',
                  transactionId: '',
                  lineNo: 1,
                  description: 'A description long enough to need two lines at a doubled scale',
                  destination: TransactionLineDestination.inventory,
                  quantity: const Qty(500000, UnitCategory.weight),
                  lineAmount: const Money(4000, 'INR'),
                ),
              ],
            ),
          ),
        ),
      ),
      homeDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('populated at 320dp and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(const LineItemsScreen(), textScale: 2, overrides: editorOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('kit rows at a doubled text scale', () {
    testWidgets('KeyValueRow wraps a long value instead of overflowing', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            child: KeyValueRow(
              label: 'Payment method',
              value: 'Bank transfer from HDFC Savings ending 4417',
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('FilterChipBar wraps rather than clipping a row of chips', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: FilterChipBar(
              clearAllLabel: 'Clear all',
              onClearAll: () {},
              filters: [
                ActiveFilter(label: 'Account: HDFC Savings', onRemove: () {}),
                ActiveFilter(label: 'Tag: Groceries', onRemove: () {}),
                ActiveFilter(label: 'Jan 2026 – Aug 2026', onRemove: () {}),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('StatusChip ellipsises a long label in a narrow box', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 96,
            child: StatusChip(label: 'Needs details', tone: StatusTone.info),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── Phase 7B ──────────────────────────────────────────────────────────────────────────
  //
  // **No sheets, so no sheet cases.** 7B adds no `AlayaBottomSheet`: the tag drill happens in place
  // inside its card and the clear-cache action is a row, so there is nothing here for U2's sheet
  // clause to cover. What it does add is one shared widget, two chart surfaces and four full-height
  // states, and those are below.
  group('analytics surfaces', () {
    // **Wrapped in a scroll view, because that is the only place a `ChartCard` ever lives** — the
    // analytics screen puts every card in a `SliverList`. Handed a tight viewport height instead, its
    // `Column` has nowhere to go and reports an overflow the real screen cannot produce. What these
    // cases are for is the *horizontal* axis: a header that starves, a chip row that will not wrap, a
    // plot box that outgrows its card.
    Widget card({
      Widget? trailing,
      Widget child = const Text('body'),
      AsyncValue<int> value = const AsyncValue.data(1),
    }) =>
        SingleChildScrollView(
            child: ChartCard<int>(
          title: 'Price per kilogram across every purchase this year',
          subtitle: 'What one thing costs you, purchase by purchase',
          value: value,
          isEmpty: (data) => data == 0,
          emptyMessage: 'Nothing yet',
          onRetry: () {},
          approximateCount: 3,
          unconvertedCount: 2,
          trailing: trailing,
          builder: (context, data) => child,
        ));

    testWidgets('ChartCard stacks its header above 1.5x rather than clipping the figure',
        (tester) async {
      // The `trailing` slot is an `AmountText`, which clips rather than ellipsises — so a clipped
      // figure is a wrong figure and the header has to stack instead of sharing a row (Law U21).
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              trailing: const AmountText(
                Money(123456789, 'INR'),
                size: AmountSize.small,
                showSign: false,
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ChartCard keeps both quality chips at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(SizedBox(width: 320, child: card()), textScale: 2),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ChartCard renders its error branch in a narrow box', (tester) async {
      // The inline failure, not `ErrorState`: that one is a full-height state with a 40px glyph and
      // its own `ScrollSafeCenter`, which inside a card would push every sibling off the screen.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              value: AsyncValue<int>.error(
                Exception('No rate for JPY on 2026-08-10, and none earlier'),
                StackTrace.empty,
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a plot area grows with the text scaler and stays inside its card',
        (tester) async {
      // `AnalyticsPlotBox` scales from the text scaler and clamps (Laws U26, U28's clamping lesson).
      // Unclamped, a tripled scale would produce a card taller than the viewport — and the box sizes
      // only the plot, so the card's own title and subtitle grow beside it rather than being squeezed
      // into the plot's height.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              child: const AnalyticsPlotBox(
                child: AnalyticsLineChart(
                  series: [
                    AnalyticsSeries(
                      tone: AnalyticsSeriesTone.expense,
                      points: [
                        AnalyticsPoint(x: 0, value: 100000, axisLabel: 'Jan'),
                        AnalyticsPoint(x: 1, value: 90000),
                        AnalyticsPoint(x: 2, value: 140000, axisLabel: 'Aug'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a flat series does not collapse its own plot band', (tester) async {
      // Every point equal makes `maxY - minY` zero, which fl_chart divides by. The chart widens the
      // band by one minor unit rather than handing it a zero.
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            height: 120,
            child: AnalyticsLineChart(
              series: [
                AnalyticsSeries(
                  tone: AnalyticsSeriesTone.neutral,
                  points: [
                    AnalyticsPoint(x: 0, value: 5000),
                    AnalyticsPoint(x: 1, value: 5000),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a bar chart of thirty-one buckets survives a doubled scale at 320dp',
        (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            height: 160,
            child: AnalyticsBarChart(
              labelEvery: 5,
              buckets: [
                for (var day = 1; day <= 31; day++)
                  AnalyticsBucket(bucket: day, value: day * 1000, label: '$day'),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an all-zero bar chart still draws its axis', (tester) async {
      // A window where nothing was spent must show that the buckets exist and are empty, rather than
      // dividing by a zero maximum.
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            height: 160,
            child: AnalyticsBarChart(
              buckets: [
                AnalyticsBucket(bucket: 1, value: 0, label: 'M'),
                AnalyticsBucket(bucket: 7, value: 0, label: 'S'),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a donut stays a ring at a tripled scale', (tester) async {
      // `AnalyticsDonutChart` sizes its radius from the box's shorter side, so a taller box at a raised
      // scale must not produce a cropped ellipse — and the centre text has to fit the hole.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              child: Builder(
                builder: (context) => AnalyticsDonutChart(
                  slices: analyticsSlices(
                    context,
                    const [
                      (label: 'Groceries', value: 400000, key: 'grocery'),
                      (label: 'Household', value: 220000, key: 'household'),
                      (label: 'Bills', value: 180000, key: 'bill'),
                    ],
                    otherLabel: 'Everything else',
                    remainder: 90000,
                  ),
                  centreTop: '85%',
                  centreBottom: 'in three kinds',
                ),
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a donut groups its tail rather than drawing twelve slivers', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              child: Builder(
                builder: (context) {
                  final slices = analyticsSlices(
                    context,
                    [
                      for (var i = 0; i < 12; i++)
                        (label: 'Kind $i', value: 12000 - i * 500, key: 'k$i'),
                    ],
                    otherLabel: 'Everything else',
                  );
                  // Six wedges plus one remainder, whatever it was handed.
                  expect(slices, hasLength(7));
                  return AnalyticsDonutChart(slices: slices);
                },
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an all-zero donut renders nothing rather than dividing by zero',
        (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              child: Builder(
                builder: (context) {
                  final slices = analyticsSlices(
                    context,
                    const [(label: 'Groceries', value: 0, key: 'grocery')],
                    otherLabel: 'Everything else',
                  );
                  expect(slices, isEmpty);
                  return AnalyticsDonutChart(slices: slices);
                },
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a swatched list without bars stacks above 1.5x', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: SliceBarList(
              showBars: false,
              slices: [
                SliceBar(
                  label: 'Between my accounts and everywhere else',
                  value: const AmountText(
                    Money(98765432, 'INR'),
                    size: AmountSize.small,
                    showSign: false,
                  ),
                  share: 0.8,
                  detail: '34%',
                  swatch: const Color(0xFF3F51B5),
                  onTap: () {},
                ),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('SliceBarList stacks its rows above 1.5x', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: SliceBarList(
              slices: [
                SliceBar(
                  label: 'Between my accounts and everywhere else',
                  value: const AmountText(
                    Money(98765432, 'INR'),
                    size: AmountSize.small,
                    showSign: false,
                  ),
                  share: 1,
                  detail: '12 purchases',
                  onTap: () {},
                ),
                SliceBar(
                  label: 'Household',
                  value: const QtyText(Qty(4450000, UnitCategory.weight)),
                  share: 0.4,
                ),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a share above one does not assert', (tester) async {
      // `share` is a ratio of two sums, so a rounding artefact can exceed one and
      // `FractionallySizedBox` asserts on a factor greater than one. It is clamped.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: SliceBarList(
              slices: [
                SliceBar(
                  label: 'Groceries',
                  value: const Text('x'),
                  share: 1.0000001,
                ),
                SliceBar(label: 'Bills', value: const Text('y'), share: double.nan),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('analytics full-height states in a squeezed viewport', () {
    Future<void> pumpSqueezed(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(
        host(Center(child: SizedBox.fromSize(size: squeezed, child: child))),
      );
    }

    testWidgets('the drill-down skeleton clips rather than overflowing', (tester) async {
      await pumpSqueezed(tester, const AlayaListSkeleton(label: 'Loading these transactions…'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the drill-down empty state scrolls instead of overflowing', (tester) async {
      await pumpSqueezed(
        tester,
        const EmptyState(
          title: 'Nothing here in this window',
          body: 'The window is set on the insights screen. Widen it and these may appear.',
          icon: Icons.filter_alt_outlined,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the screen-level empty state scrolls with its action', (tester) async {
      // The tallest of the three: icon, two text blocks and a 48dp button (ARCH_5 §4.1).
      await pumpSqueezed(
        tester,
        EmptyState(
          title: 'Nothing to show for this window',
          body: 'Widen the window above, or record something and it will appear here.',
          icon: Icons.insights_outlined,
          actionLabel: 'Add expense',
          onAction: () {},
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the drill-down error state survives with a retry', (tester) async {
      await pumpSqueezed(
        tester,
        ErrorState(
          title: 'Could not work that out',
          body: 'No rate for JPY on 2026-08-10, and none earlier',
          retryLabel: 'Try again',
          onRetry: () {},
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── Phase 8A ──────────────────────────────────────────────────────────────────────────
  //
  // Two sheets and five full-height states. `PaymentMethodSheet` and `PayeeSheet` are the phase's only
  // `AlayaBottomSheet` additions; the lock screen, PIN setup, recovery and the settings empties are its
  // full-height ones (Law U2 — added in the phase that creates them).
  group('settings and lock surfaces', () {
    testWidgets('a PIN keypad fits 320dp at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(
              width: 320,
              child: PinKeypad(enabled: true, onDigit: _noDigit, onBackspace: _noop),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a keypad with the biometric key fits at a tripled scale', (tester) async {
      // Four keys on the bottom row rather than three, which is the widest the pad ever gets.
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(
              width: 320,
              child: PinKeypad(
                enabled: true,
                onDigit: _noDigit,
                onBackspace: _noop,
                onBiometric: _noop,
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('six PIN dots fit the narrowest phone', (tester) async {
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(width: 320, child: PinDots(length: 6, filled: 3, dimmed: false)),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the honest-copy paragraph wraps rather than overflowing', (tester) async {
      // The longest string in the app, at the largest scale U15 asks for, in the narrowest column.
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(
              width: 320,
              child: Text(
                'This PIN stops someone who picks up your unlocked phone from opening Alaya. '
                'It does not encrypt your data — anyone with access to the phone’s files can '
                'still read them.',
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a settings empty state scrolls in a squeezed viewport', (tester) async {
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox.fromSize(
              size: squeezed,
              child: EmptyState(
                title: 'No accounts yet',
                body: 'Add one so Alaya knows where your money is.',
                icon: Icons.account_balance_wallet_outlined,
                actionLabel: 'Add an account',
                onAction: () {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the scoping matrix stacks at a doubled scale', (tester) async {
      // Six switches, each with a two-line subtitle — the tallest form in the phase.
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: Column(
                children: [
                  for (var i = 0; i < 6; i++)
                    SwitchListTile(
                      value: i.isEven,
                      onChanged: (_) {},
                      title: const Text('Money out'),
                      subtitle: const Text('Offered when you record spending.'),
                    ),
                ],
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the varies panel fits its explanation and its offer', (tester) async {
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Then it is not a unit'),
                  const Text(
                    'A unit has to be the same amount every time. One packet of biscuits and one '
                    'packet of rice are different weights, so Alaya could not add two packets '
                    'together or work out what one cost.',
                  ),
                  FilledButton(onPressed: () {}, child: const Text('Create an item instead')),
                ],
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── Phase 8B ──────────────────────────────────────────────────────────────────────────
  //
  // Two sheets and four full-height states. `AttachSheet` is this phase's only `AlayaBottomSheet` addition;
  // the export confirmation reuses `ConfirmSheet` but carries the longest body in the app, which is the case
  // worth measuring (Law U2 — added in the phase that creates them).
  group('ops surfaces', () {
    testWidgets('the export warning fits the narrowest phone at a doubled scale', (tester) async {
      // **The longest required string in the project**, in the narrowest column, at the largest scale U15 asks
      // for. If ARCH_3 §3.4's sentence does not fit, the rule cannot be honoured.
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(
              width: 320,
              child: Text(
                'This backup is not encrypted. Anyone who opens this file can read every '
                'transaction, balance and account name. Only share it somewhere you trust.',
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the attach sheet fits at a tripled scale', (tester) async {
      // **Scrollable, because `AlayaBottomSheet` is.** The bare `Column` this case first used overflowed by 342px
      // at 3x — but it was testing a structure the app does not have, so the failure said nothing about the sheet.
      // A layout case that does not mirror its widget's real wrapper measures the wrong thing.
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Add an attachment'),
                  const Text('Kept on this phone only, and included in your backups.'),
                  FilledButton(onPressed: () {}, child: const Text('Choose a photo')),
                ],
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an attachment strip does not reflow around a missing file', (tester) async {
      // The glyph fallback is the same extent as a thumbnail, so a strip of loaded and unloaded images has one
      // height rather than two.
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox(
              width: 320,
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < 6; i++)
                    const Padding(
                      padding: EdgeInsets.all(4),
                      child: SizedBox(
                        width: 88,
                        height: 88,
                        child: Icon(Icons.description_outlined),
                      ),
                    ),
                ],
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a trash row fits its label, its date and its retention line', (tester) async {
      // **This case found a real defect**, which is what these are for. The screen originally put "Deleted", a
      // date and a retention note in one subtitle `Row` behind a `TextButton` trailing — a `ListTile` gives its
      // subtitle whatever the trailing leaves, which at a doubled scale was 142dp. Two lines and an icon fixed it,
      // and this now measures the shape that shipped.
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox(
              width: 320,
              child: ListTile(
                isThreeLine: true,
                title: const Text('Weekly groceries at the corner shop'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Row(children: [Text('Deleted'), SizedBox(width: 4), Flexible(child: Text('8 Aug 2026'))]),
                    Text('· kept for 30 days'),
                  ],
                ),
                trailing: IconButton(
                  onPressed: () {},
                  tooltip: 'Restore',
                  icon: const Icon(Icons.restore_from_trash_outlined),
                ),
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the reminders explainer and a blocked notice stack', (tester) async {
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  Text('Alaya sends one message a day about what is coming up — not a '
                      'notification for every item.'),
                  SizedBox(height: 8),
                  Text('Notifications are turned off for Alaya. Turn them on in your '
                      'phone’s Settings › Apps › Alaya › Notifications.'),
                ],
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the restore replace warning fits before the typed confirmation', (tester) async {
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Everything currently on this phone will be thrown away and '
                      'replaced by the backup. Anything recorded since that backup was made '
                      'will be gone.'),
                  const SizedBox(height: 8),
                  const TextField(),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: () {}, child: const Text('Replace everything')),
                ],
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// A transaction editor reporting a fixed state, so a layout can be pumped without a database.
class _FixedEditor extends TransactionEditorNotifier {
  _FixedEditor(this._value);

  final AsyncValue<TransactionEditorState> _value;

  @override
  AsyncValue<TransactionEditorState> build(String? arg) => _value;
}

/// A `ValueChanged<String>` that does nothing, so the keypad cases need no state.
void _noDigit(String _) {}

/// A `VoidCallback` that does nothing.
void _noop() {}
```

---

## The settings tree, wired to this phase

**Four of 8B's five screens were unreachable.** `Routes.settingsBackup`, `settingsTrash`, `settingsReminders` and
`support` were each referenced exactly once — by their own entry in the router — and nothing navigated to any of
them. The screens existed, the routes existed, and no user could get there. That is the gap a coverage table does
not catch, because every row it claims was genuinely built.

Three files close it:

**Settings › Data becomes a hub.** It previously carried the export flow inline and a *"coming in the next
update"* row where restore belonged. Both are real screens now, so the branch names what is behind it and gets
out of the way — and keeping a second export here would have meant **two places carrying ARCH_3 §3.4's warning,
and two places to forget it**.

**The tree gains Reminders and Support Us.** Reminders sits beside Security, because both are about what the app
does while it is closed and somebody looking for one often means the other. Support Us is reachable from Settings
and nowhere else: ads load when that screen opens, so a shell destination or a dashboard tile would start an SDK
for people who never asked (ARCH_4 §5.1).

**The trash row carries a live count**, which is archetype D's "one number that matters" — and renders as no
number at all while it loads, rather than `0`.

### `lib/features/settings/presentation/screens/data_settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/settings/providers/app_settings_providers.dart';

/// Settings › Data (ARCH_5 §3 archetype D, outside the shell).
///
/// **A hub, not a workspace, since 8B.** It previously held the export flow inline and a *"coming in the next
/// update"* row where restore belonged. Both are real screens now, so this branch does what a settings branch
/// should: name what is behind it and get out of the way. Keeping a second export here would have meant two
/// places carrying ARCH_3 §3.4's warning, and two places to forget it.
class DataSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const DataSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final trashed = ref.watch(settingsTrashCountProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsData)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
        children: [
          ListTile(
            leading: Icon(Icons.backup_outlined,
                size: AlayaIconSize.lg, color: semantic.muted),
            title: Text(strings.backupTitle, style: AlayaTypography.cardTitle),
            subtitle: Text(
              strings.dataBackupRowBody,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            trailing: Icon(Icons.chevron_right, size: AlayaIconSize.md, color: semantic.muted),
            onTap: () => context.push(Routes.settingsBackup),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, size: AlayaIconSize.lg, color: semantic.muted),
            title: Text(strings.trashTitle, style: AlayaTypography.cardTitle),
            // Null while the count loads, so the row shows its title alone rather than "0 items" — a zero that
            // really means "not yet known" is the figure Law U4 exists to prevent.
            subtitle: Text(
              trashed == null ? strings.dataTrashRowBody : strings.settingsTrashCount(trashed),
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            trailing: Icon(Icons.chevron_right, size: AlayaIconSize.md, color: semantic.muted),
            onTap: () => context.push(Routes.settingsTrash),
          ),
        ],
      ),
    );
  }
}
```

### `lib/features/settings/presentation/screens/settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/settings/providers/settings_providers.dart';
import 'package:alaya/shared/widgets/alaya_search_field.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// One row of the settings tree.
class _Entry {
  const _Entry({
    required this.title,
    required this.icon,
    required this.route,
    required this.keywords,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String route;

  /// Extra words this row should match on.
  ///
  /// **Because the title is not what people search for.** Somebody looking for dark mode types "dark", not
  /// "Appearance"; somebody looking to change their PIN types "PIN", not "Security". A tree whose search
  /// only matched headings would be worse than no search at all, because it would answer "no results" to a
  /// setting that is right there.
  final List<String> keywords;
}

/// The settings tree (ARCH_5 §3 archetype D).
///
/// **Archetype D with two deviations.** There is no FAB, because nothing is added at the tree level — every
/// branch owns its own add action. And the grouping is by subject rather than by a user-chosen axis, because
/// a settings tree has no axis the user controls; the three groups are what the app is made of, in the order
/// somebody looks for them.
///
/// **The search field is pinned and real**, per D — catalogues are searched constantly, and a ten-branch
/// tree with sub-settings is exactly the case where scanning fails. It matches keywords as well as titles,
/// so "dark" finds Appearance and "PIN" finds Security.
///
/// Each row carries a live count, which is D's "the one number that matters": a branch that says *18 tags*
/// tells the user whether it is worth opening before they open it.
class SettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final query = ref.watch(settingsQueryProvider).trim().toLowerCase();
    final groups = _groups(context, ref, strings);

    final filtered = query.isEmpty
        ? groups
        : [
            for (final group in groups)
              (
                label: group.label,
                entries: [
                  for (final entry in group.entries)
                    if (entry.title.toLowerCase().contains(query) ||
                        entry.keywords.any((word) => word.contains(query)))
                      entry,
                ],
              ),
          ].where((group) => group.entries.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AlayaSpacing.screenEdge,
            AlayaSpacing.sm,
            AlayaSpacing.screenEdge,
            AlayaSpacing.xs,
          ),
          child: AlayaSearchField(
            hintText: strings.settingsSearchHint,
            clearLabel: strings.actionClear,
            onChanged: ref.read(settingsQueryProvider.notifier).set,
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              // Empty is reachable only through search, so it names the search rather than the tree — "no
              // settings" would be false, and the user can see it is.
              ? EmptyState(
                  title: strings.settingsNoMatchTitle,
                  body: strings.settingsNoMatchBody,
                  icon: Icons.search_off_outlined,
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final group = filtered[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            top: AlayaSpacing.lg,
                            bottom: AlayaSpacing.xs,
                          ),
                          child: SectionHeader(label: group.label),
                        ),
                        for (final entry in group.entries) _EntryTile(entry: entry),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<({String label, List<_Entry> entries})> _groups(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) {
    final accounts = ref.watch(settingsAccountCountProvider).valueOrNull;
    final methods = ref.watch(settingsPaymentMethodCountProvider).valueOrNull;
    final payees = ref.watch(settingsPayeeCountProvider).valueOrNull;
    final tags = ref.watch(settingsTagCountProvider).valueOrNull;
    final units = ref.watch(settingsUnitCountProvider).valueOrNull;
    final currencies = ref.watch(settingsCurrencyCountProvider).valueOrNull;

    return [
      (
        label: strings.settingsGroupMoney,
        entries: [
          _Entry(
            title: strings.settingsAccounts,
            // Null while the count is loading, so the row shows its title alone rather than "0 accounts"
            // — a zero that is really "not yet known" is the kind of figure Law U4 exists to prevent.
            subtitle: accounts == null ? null : strings.settingsAccountCount(accounts),
            icon: Icons.account_balance_wallet_outlined,
            route: Routes.settingsAccounts,
            keywords: const ['account', 'balance', 'bank', 'cash', 'wallet', 'net worth'],
          ),
          _Entry(
            title: strings.settingsPaymentMethods,
            subtitle: methods == null ? null : strings.settingsPaymentMethodCount(methods),
            icon: Icons.credit_card_outlined,
            route: Routes.settingsPaymentMethods,
            keywords: const ['payment', 'card', 'upi', 'method'],
          ),
          _Entry(
            title: strings.settingsPayees,
            subtitle: payees == null ? null : strings.settingsPayeeCount(payees),
            icon: Icons.storefront_outlined,
            route: Routes.settingsPayees,
            keywords: const ['payee', 'shop', 'merchant', 'who'],
          ),
        ],
      ),
      (
        label: strings.settingsGroupThings,
        entries: [
          _Entry(
            title: strings.settingsTags,
            subtitle: tags == null ? null : strings.settingsTagCount(tags),
            icon: Icons.sell_outlined,
            route: Routes.settingsTags,
            keywords: const ['tag', 'label', 'category', 'kitchen'],
          ),
          _Entry(
            title: strings.settingsUnits,
            subtitle: units == null ? null : strings.settingsUnitCount(units),
            icon: Icons.straighten_outlined,
            route: Routes.settingsUnits,
            keywords: const ['unit', 'kg', 'litre', 'measure', 'weight'],
          ),
          _Entry(
            title: strings.settingsCurrencies,
            subtitle: currencies == null
                ? null
                : strings.settingsCurrencyCount(currencies.enabled, currencies.total),
            icon: Icons.currency_exchange_outlined,
            route: Routes.settingsCurrencies,
            keywords: const ['currency', 'rate', 'exchange', 'home currency'],
          ),
        ],
      ),
      (
        label: strings.settingsGroupApp,
        entries: [
          _Entry(
            title: strings.settingsAppearance,
            icon: Icons.palette_outlined,
            route: Routes.settingsAppearance,
            keywords: const ['appearance', 'theme', 'dark', 'light', 'palette', 'colour', 'color'],
          ),
          _Entry(
            title: strings.settingsSecurity,
            icon: Icons.shield_outlined,
            route: Routes.settingsSecurity,
            keywords: const ['security', 'pin', 'lock', 'fingerprint', 'biometric', 'erase'],
          ),
          // Phase 8B. Reminders sits beside Security because both are about what the app does when it is not
          // open, and somebody looking for one often means the other.
          _Entry(
            title: strings.remindersTitle,
            subtitle: strings.settingsRemindersHelp,
            icon: Icons.notifications_none_outlined,
            route: Routes.settingsReminders,
            keywords: const [
              'reminder', 'notification', 'notify', 'alert', 'digest', 'expiry', 'due', 'daily',
            ],
          ),
          _Entry(
            title: strings.settingsData,
            icon: Icons.folder_outlined,
            route: Routes.settingsData,
            keywords: const ['data', 'backup', 'export', 'restore', 'trash'],
          ),
          // **Reachable from Settings and nowhere else.** Ads load when that screen opens, so a shell
          // destination or a dashboard tile would start an SDK for people who never asked (ARCH_4 §5.1).
          _Entry(
            title: strings.supportTitle,
            subtitle: strings.settingsSupportHelp,
            icon: Icons.favorite_outline,
            route: Routes.support,
            keywords: const ['support', 'tip', 'donate', 'advert', 'ad', 'help', 'contribute'],
          ),
          _Entry(
            title: strings.settingsAbout,
            icon: Icons.info_outlined,
            route: Routes.settingsAbout,
            keywords: const ['about', 'version', 'licence', 'license', 'open source'],
          ),
        ],
      ),
    ];
  }
}

/// One tappable branch.
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return ListTile(
      leading: Icon(entry.icon, size: AlayaIconSize.lg, color: semantic.muted),
      title: Text(entry.title, style: AlayaTypography.cardTitle),
      subtitle: entry.subtitle == null
          ? null
          : Text(
              entry.subtitle!,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
      trailing: Icon(Icons.chevron_right, size: AlayaIconSize.md, color: semantic.muted),
      onTap: () => context.push(entry.route),
    );
  }
}
```

### `lib/features/settings/providers/app_settings_providers.dart`

```dart
/// View-model state for the currencies, appearance and security branches (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/domain/entities/currency.dart';

/// Every currency, enabled or not.
final currenciesSettingsProvider = StreamProvider<List<Currency>>(
  (ref) => ref.watch(currencyRepositoryProvider).watchAll(),
);

/// The home currency's code, which cannot be disabled.
final homeCurrencyCodeProvider = FutureProvider<String?>(
  (ref) => ref.watch(settingsRepositoryProvider).readHomeCurrencyCode(),
);

/// Enables and disables currencies.
final currencyToggleProvider =
    NotifierProvider<CurrencyToggleNotifier, AsyncValue<void>>(CurrencyToggleNotifier.new);

/// Writes a currency's enabled flag.
class CurrencyToggleNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Enables or disables [code].
  Future<bool> setEnabled({required String code, required bool isEnabled}) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(currencyRepositoryProvider)
        .setEnabled(code: code, isEnabled: isEnabled);
    if (result.isFailure) {
      state = AsyncError<void>(result.failureOrNull ?? StateError('toggle failed'), StackTrace.current);
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}

/// How many rows are in the trash, for the Data branch's row.
///
/// Phase 8B. Reads `trashPortProvider`, which is app-level — a feature watching another feature's provider would
/// be the coupling ARCH_5 §8 keeps out of the settings tree.
final settingsTrashCountProvider = StreamProvider<int>(
  (ref) => ref.watch(trashPortProvider).watchCount(),
);

/// Whether a lock is configured, for the security branch.
final lockConfiguredProvider = FutureProvider<bool>(
  (ref) => ref.watch(pinServiceProvider).isEnabled,
);
```

## `bootstrap.dart` — the daily job's one call site

**Written in this phase and, until now, called by nothing.** Two obligations depend on it and neither has any
other trigger: ARCH_3 §7's daily recompute, so the digest reflects what is actually coming, and §4.2's thirty-day
retention, which is a promise the app does not keep unless something enforces it. Both ports exposed the methods
from the start; without this call every screen works and the trash simply never empties.

Unawaited deliberately: `Workmanager().initialize` crosses a platform channel, and blocking `runApp` on it would
trade a visible first frame for a background schedule nobody is waiting on. `ExistingPeriodicWorkPolicy.keep` makes
repeated registration a no-op, so a cold start racing this loses nothing.

PHASE_05 regenerates.

### `lib/app/bootstrap.dart`

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/app.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/connection/open_database.dart';
import 'package:alaya/data/reminders/daily_job.dart';

/// Opens the database, builds the provider graph and runs the app.
///
/// The database is opened **here and only here**, through `openAlayaDatabase` — the single permitted
/// open path (Law L10). `databaseProvider` throws when un-overridden precisely so that a second open
/// site cannot appear quietly; the symptom of one would be a locked file rather than an error naming
/// the cause.
///
/// The database is plaintext (ARCH_1 §2.1). There is no key to derive, no passphrase to prompt for and
/// no unlock step before the connection opens.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = openAlayaDatabase();

  // **Phase 8B: the daily job is registered here, once, and nowhere else.**
  //
  // Two obligations depend on it and neither has any other trigger: ARCH_3 §7's daily recompute, so the digest
  // reflects what is actually coming, and §4.2's thirty-day retention, which is a promise the app does not keep
  // unless something enforces it. Both ports exposed the methods from the start; without this call the screens
  // all work and the trash simply never empties.
  //
  // Unawaited deliberately. `Workmanager().initialize` talks to a platform channel, and blocking `runApp` on it
  // would trade a visible first frame for a background schedule nobody is waiting on. `ExistingWorkPolicy.keep`
  // makes repeated registration a no-op, so a cold start that races this loses nothing.
  unawaited(registerDailyJob());

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const AlayaApp(),
    ),
  );
}

/// Builds a `ProviderScope` over [database] for tests and the Theme Lab.
///
/// Exposed so a widget test can supply `AlayaDatabase(NativeDatabase.memory())` without reaching for
/// `bootstrap`, which would open a real file.
ProviderScope scopeFor({
  required AlayaDatabase database,
  required Widget child,
  List<Override> extraOverrides = const [],
}) =>
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database), ...extraOverrides],
      child: child,
    );
```

### `docs/SUPPORT_SETUP.md`

Delivered as a file rather than inlined here: it is operator documentation for AdMob and Play
Console setup, not source. See `docs/SUPPORT_SETUP.md` in the phase output.

---

## Amendment — a support action in the dashboard app bar

**This amends ARCH_4 §5.1, which reads "Rewarded ads only in Support Us | `support/` feature, lazy load | 8B".**
The entry point moves; the constraint does not, and the distinction is the whole of this change.

**Nothing loads until the button is pressed.** The obvious way to make an app bar button feel instant is to keep
an advert waiting — which means `MobileAds.initialize()`, a consent fetch and `RewardedAd.load()` on every
dashboard build, and an advertising identifier collected from every user who never taps it. That is exactly what
8B's *"the rest of the app makes zero ad calls"* forbids, and the cost is a real privacy property rather than a
notional one.

So `watchNow()` runs the whole sequence **on the tap**: initialise → settle consent → load → show. It takes a
second or two, which is why the button becomes a spinner rather than pretending otherwise. **The user chooses when
an advert plays, and also when one is fetched** — the second half is what a pre-loaded button gives away, and it is
the half that cannot be undone.

| | |
|---|---|
| Icon | `Icons.handshake_outlined` — joined hands, in the app bar and the drawer, so the two read as one thing |
| Colour | `colorScheme.secondary`, which is the palette's own `accent` (ARCH_3 §8) — distinct under every preset and both brightnesses, and not a raw colour |
| Position | Beside the home button in `_ShellScaffold`, so it appears on every shell destination including the dashboard |
| Drawer | A row below the destinations, behind a divider: Support Us is not a place the app does work, so it is not a peer of Expenses or Inventory |

**`SupportWatchOutcome` has four cases rather than a bool.** Three need different words and one needs silence — a
dismissed advert is not a failure, and collapsing it would either thank somebody who watched nothing or show them
an error for changing their mind.

The drawer's `titleFor` and `iconFor` both gained a `Routes.support` case. Without them the row renders with no
label and no icon, which is the kind of omission a `switch` with a `default` would have hidden.

### `lib/features/support/presentation/widgets/support_action.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
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

    return IconButton(
      onPressed: () => _watch(context, ref, strings),
      tooltip: strings.supportWatchTooltip,
      icon: Icon(
        // Joined hands. Not a padlock-style overload: it reads as "together" rather than as an advert, which is
        // honest — the action is supporting the app, and the advert is the mechanism.
        Icons.handshake_outlined,
        size: AlayaIconSize.md,
        color: theme.colorScheme.secondary,
      ),
    );
  }

  Future<void> _watch(BuildContext context, WidgetRef ref, AlayaStrings strings) async {
    final controller = ref.read(supportProvider.notifier);
    final outcome = await controller.watchNow();
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

### `lib/shared/widgets/alaya_drawer.dart`

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// The app's navigation drawer.
///
/// Its destination list is `Routes.drawerDestinations`, so a route cannot exist in the router and be
/// missing from the drawer — the two read the same constant.
///
/// A drawer rather than a bottom bar because there are nine destinations. A bottom bar holds four
/// comfortably and five at a squeeze; beyond that the labels truncate and the targets shrink below the
/// tap-target floor.
class AlayaDrawer extends StatelessWidget {
  /// Creates the drawer.
  const AlayaDrawer({required this.currentLocation, super.key});

  /// The location currently shown, used to mark the selected row.
  final String currentLocation;

  /// The localised title for [location].
  ///
  /// Static so the app bar can title itself from the same mapping the drawer uses, rather than each
  /// screen repeating its own name and the two drifting apart.
  static String titleFor(BuildContext context, String location) {
    final strings = AlayaStrings.of(context);
    return switch (_rootOf(location)) {
      Routes.dashboard => strings.navDashboard,
      Routes.expenses => strings.navExpenses,
      Routes.inventory => strings.navInventory,
      Routes.shopping => strings.navShopping,
      Routes.recurring => strings.navRecurring,
      Routes.services => strings.navServices,
      Routes.calendar => strings.navCalendar,
      Routes.insights => strings.navInsights,
      Routes.settings => strings.navSettings,
      Routes.support => strings.supportTitle,
      _ => strings.appName,
    };
  }

  /// The icon for [location].
  static IconData iconFor(String location) => switch (_rootOf(location)) {
        Routes.dashboard => Icons.dashboard_outlined,
        Routes.expenses => Icons.receipt_long_outlined,
        Routes.inventory => Icons.inventory_2_outlined,
        Routes.shopping => Icons.shopping_cart_outlined,
        Routes.recurring => Icons.autorenew_outlined,
        Routes.services => Icons.build_outlined,
        Routes.calendar => Icons.calendar_month_outlined,
        Routes.insights => Icons.insights_outlined,
        Routes.settings => Icons.settings_outlined,
        // Joined hands, matching the app bar action so the two read as the same thing in two places.
        Routes.support => Icons.handshake_outlined,
        _ => Icons.circle_outlined,
      };

  /// The top-level route a possibly-nested [location] belongs to.
  ///
  /// `/expenses/abc123` selects Expenses. Matching the full location would leave nothing selected as
  /// soon as the user opened a detail screen.
  static String _rootOf(String location) {
    if (location == Routes.dashboard) return Routes.dashboard;
    for (final destination in Routes.drawerDestinations) {
      if (destination == Routes.dashboard) continue;
      if (location == destination || location.startsWith('$destination/')) return destination;
    }
    return location;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AlayaStrings.of(context);
    final selected = _rootOf(currentLocation);

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.md),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AlayaSpacing.md,
                AlayaSpacing.xs,
                AlayaSpacing.md,
                AlayaSpacing.lg,
              ),
              child: Text(
                strings.appName,
                style: AlayaTypography.screenTitle.copyWith(color: theme.colorScheme.onSurface),
              ),
            ),
            for (final destination in Routes.drawerDestinations)
              _DrawerRow(
                destination: destination,
                selected: destination == selected,
                onTap: () {
                  Navigator.of(context).pop();
                  if (destination != selected) context.go(destination);
                },
              ),
            // **Phase 8B, below the destinations and behind a divider.** Support Us is not a place the app does
            // work, so it is not a peer of Expenses or Inventory — the separation says so without a label.
            //
            // Opening this screen is what starts the ad SDK; the drawer row only navigates, so pulling the
            // drawer out costs nothing (ARCH_4 §5.1).
            const Divider(height: AlayaSpacing.lg),
            _DrawerRow(
              destination: Routes.support,
              selected: selected == Routes.support,
              onTap: () {
                Navigator.of(context).pop();
                if (selected != Routes.support) context.push(Routes.support);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerRow extends StatelessWidget {
  const _DrawerRow({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final String destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.xs,
        vertical: AlayaSpacing.xxs,
      ),
      child: ListTile(
        selected: selected,
        selectedColor: theme.colorScheme.secondary,
        selectedTileColor: theme.colorScheme.secondary.withValues(alpha: 0.10),
        leading: Icon(AlayaDrawer.iconFor(destination)),
        title: Text(AlayaDrawer.titleFor(context, destination)),
        onTap: onTap,
      ),
    );
  }
}
```

---

## COVERAGE — ARCH_5 §7 rows closed by Phase 8B

| Row | Status |
|---|---|
| **`attachments`** | **Closed.** Attach sheet (archetype A), thumbnail strip on detail, delete with confirmation. The table had waited since 1B; nothing had ever read or written it |
| **`notification_schedule`** | **Closed.** Per-type toggles, a digest time picker, and *what is currently scheduled* shown to the user — which is what §7's row asks for |
| **`backup_history`** | **Closed.** The list on Settings › Data › Backup, with per-entry *forget* that leaves the file alone |

### Screens

Backup (D) · Restore (B) · Trash (C) · Reminders (D) · Support Us (F) — the five ARCH_5 §8 assigns to 8B, plus the
attachment sheet and strip that §7's `attachments` row specifies. **Nothing was added to `shared/`**, which §8
permits this phase none of.

### The CRITICAL list

| | |
|---|---|
| Warning on the confirmation sheet, every time | Both export paths route through `_confirmExport`; neither can reach the filesystem without it. Asserted by sentence, and asserted to *block* |
| SAF only — no `WRITE_EXTERNAL_STORAGE` | `FilePicker.saveFile` is the create-document intent. Attachments live inside the app's own directory, so there is no other write path to forget |
| The lock is not restored | Stated on all three restore stages. PIN and recovery hashes are in secure storage, so a backup cannot change who opens the app |
| `POST_NOTIFICATIONS` requested contextually | On the first switch-on, never on launch. Asserted zero-on-open, one-on-toggle |
| All reminders default off | `ReminderSettings.fresh()` has an empty set; asserted across every switch |
| One daily digest, inexact only | `AndroidScheduleMode.inexactAllowWhileIdle`. The contract cannot express a per-item ping or an exact time |
| Purge is the only hard delete, in one function | `TrashAdapter._hardDelete`. All three purge paths arrive there; `_deleteRow` beneath it has no other caller |
| Ads load only when Support opens | `AdsAndBilling` is the only file importing either SDK, and `initialise()` is called from one `initState`. Both halves asserted |

### Deviations, each deliberate

| Deviation | Why |
|---|---|
| **`file_picker` removed; a SAF platform channel written instead** | It resolves to 3.0.4 (2020), whose `jcenter()` Gradle call fails at `assembleDebug` while `pub get` succeeds — ARCH_1 §7.4's own worked example. §7 recommended the channel; it needs no permission and no pub dependency |
| **No camera capture** | Needs `image_picker`, which §7 pins nowhere. The copy says *choose a photo* rather than promising a camera that never opens. One word from you and it is a package plus a §7 row |
| **The digest's text is assembled in Dart, not the ARB** | A `workmanager` isolate has no `BuildContext` and no `AlayaStrings`. Passing pre-localised text into a job that runs days later, in a locale since changed, would be worse than plain English |
| **Support Us has no `displayAmount`** | Archetype F wants one headline number and this screen has none to give honestly. A fabricated *"₹0 raised"* is worse than a sentence |
| **The tip price is the store's string** | Play localises it for the user's account, which need not match the home currency. The one place money appears without `AmountText` |
| **The rewarded unit is Google's test id** | Shipping a real one from source is how a debug build serves live ads. The real id belongs in release configuration, on R6's checklist |
| **`open_database.dart` gained `alayaDatabaseFile()`** | Replace has to move the live file and nothing exposed its path. Deriving it twice would drift; the helper opens nothing, so Law L10 stands. PHASE_01C regenerates |

### The check this phase was missing

**Four of five screens were built, routed, tested — and unreachable.** `settingsBackup`, `settingsTrash`,
`settingsReminders` and `support` were each referenced once, by their own entry in the router, and no widget
navigated to any of them. Every COVERAGE row was honestly earned and the feature was still not usable.

Two checks passed that felt like they covered this and did not: *every screen the router names exists*, and *every
route constant is declared*. Neither asks whether a tap gets there. The check that does:

```
for each route R: assert some widget calls context.push(R) or context.go(R)
```

It is now run over both documents and passes for all five.

### Corrections to earlier phases

**`backupNotEncryptedWarning` now matches ARCH_3 §3.4 verbatim.** 8A shipped a paraphrase missing *"Only share it
somewhere you trust"* — the only actionable sentence of the three. Every export confirmation in both phases now
carries the specified text.

**Phase 5's comment that `calendarAggregatorProvider` "could not exist" is stale** — 7A added it, 7B carries it.
Left in place rather than edited, but worth knowing it misleads in a file six phases still carry.

### Carried, so their documents regenerate

PHASE_01C (`open_database.dart`), PHASE_05 (`service_providers.dart`), and PHASE_05–08A for `routes.dart`,
`app_router.dart`, `app_en.arb` and `layout_overflow_test.dart`.

### Open, with owners

| Item | Why | Owner |
|---|---|---|
| Camera capture for attachments | Needs `image_picker` and a §7 row | your call |
| Real ad unit id and privacy-policy URL | R6's Play checklist; the URL is needed **before** first upload, not at launch. Step-by-step in `docs/SUPPORT_SETUP.md` | release |
| ~~`registerDailyJob()` call site~~ | **Closed.** `bootstrap()` calls it once, unawaited | — |
| `share_plus` still unexercised | 8A confined it; no build has run the export path yet | first build |

### First-build gate

```
flutter pub add flutter_local_notifications timezone workmanager
flutter pub add google_mobile_ads in_app_purchase
flutter pub remove file_picker          # 3.0.4 breaks assembleDebug — ARCH_1 §7.4
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter test
```

**Six plugin surfaces could not be compiled against** (ARCH_4 R22), each confined to one file:
`flutter_local_notifications` and `timezone` in `local_notification_scheduler.dart`, `workmanager` in
`daily_job.dart`, the SAF channel in `saf_channel.dart` and `SafPlugin.kt`, and both ad SDKs in `ads_and_billing.dart`. 8A's `local_auth` needed three attempts before it compiled; budget for the same here, and
expect each failure to cost one file.

