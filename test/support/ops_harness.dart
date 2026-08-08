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
import 'package:alaya/features/lock/providers/lock_providers.dart';
import 'package:alaya/features/onboarding/providers/onboarding_providers.dart';
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
            (
              path: '/x/alaya.db',
              sizeBytes: 2048,
              isZipped: false,
              fileName: 'alaya.db',
            ),
          );
  }

  @override
  Future<Result<BackupArtefact, Failure>> exportAndShare() async {
    exports += 1;
    return const Result.ok(
      (
        path: '/x/alaya.db',
        sizeBytes: 2048,
        isZipped: false,
        fileName: 'alaya.db',
      ),
    );
  }

  @override
  Stream<List<BackupRecord>> watchHistory() => Stream.value(history);

  @override
  Future<Result<void, Failure>> forgetHistoryEntry(String id) async =>
      const Result.ok(null);

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
  Future<Result<void, Failure>> eraseEverything() async =>
      const Result.ok(null);
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
  Future<Result<List<TipProduct>, Failure>> tipProducts() async =>
      const Result.ok(
        [TipProduct(id: 'alaya_tip_once', title: 'Tip', price: '₹99.00')],
      );

  @override
  Future<Result<bool, Failure>> buyTip(String productId) async =>
      const Result.ok(true);
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
  }) => Stream.value(rows);

  @override
  Stream<int> watchCountFor({
    required AttachmentOwner owner,
    required String ownerId,
  }) => Stream.value(rows.length);

  @override
  Future<Result<Attachment?, Failure>> attach({
    required AttachmentOwner owner,
    required String ownerId,
  }) async => cancelled ? const Result.ok(null) : Result.ok(attachment());

  @override
  Future<Result<String, Failure>> resolvePath(Attachment attachment) async =>
      const Result.ok('/tmp/x.jpg');

  @override
  Future<Result<void, Failure>> open(Attachment attachment) async =>
      const Result.ok(null);

  @override
  Future<Result<void, Failure>> delete(Attachment attachment) async =>
      const Result.ok(null);

  @override
  Future<Result<List<String>, Failure>> allFilePaths() async =>
      const Result.ok([]);
}

/// One trash entry.
TrashEntry trashEntry({
  String id = 'tr-1',
  TrashKind kind = TrashKind.transaction,
  String label = 'Groceries',
  int deletedAt = 1754000000000,
}) => TrashEntry(
  id: id,
  kind: kind,
  label: label,
  deletedAtUtcMillis: deletedAt,
  purgeAfterUtcMillis: deletedAt + TrashPort.retention.inMilliseconds,
);

/// One backup record.
BackupRecord backupRecord({
  String id = 'bk-1',
  String path = '/x/alaya-2026-08-08.db',
}) => BackupRecord(
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
}) => ScheduledReminder(
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
}) => [
  dataTransferPortProvider.overrideWithValue(transfer ?? FakeTransfer()),
  // Throws when un-overridden, by design — `bootstrap()` is the only place that resolves it.
  lockConfiguredAtStartupProvider.overrideWithValue(false),
  // True, so no widget test is ever redirected into the first-run flow.
  onboardingDoneAtStartupProvider.overrideWithValue(true),
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
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pump();
}
