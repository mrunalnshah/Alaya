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
  final seeder = SeedData(
    uids: uids,
    clock: clock,
    homeCurrencyCode: homeCurrencyCode,
  );
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
