import 'package:drift/drift.dart';

import 'package:alaya/data/db/converters/enum_converters.dart';

/// One scheduled local notification (ARCH_3 §7).
///
/// Exists so every Android notification has a stable id that can be cancelled when the
/// underlying record changes. Without it you get orphaned reminders for food already eaten.
@DataClassName('NotificationScheduleRow')
class NotificationSchedule extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// What kind of event this reminder is for.
  TextColumn get kind => text().map(const NotificationKindConverter())();

  /// Which kind of record this points at, e.g. `inventoryBatch`, `asset`. Free text and
  /// deliberately not a foreign key: like [Attachments] this is genuinely polymorphic, and
  /// [refId] may outlive the row it names.
  TextColumn get refType => text()();

  /// The referenced record's id.
  TextColumn get refId => text()();

  /// When the OS should fire it, epoch millis UTC.
  IntColumn get scheduledAtUtcMillis => integer()();

  /// The stable id handed to Android, so this reminder can be cancelled later.
  IntColumn get androidNotificationId => integer()();

  /// Lifecycle state. `cancelled` rows are retained so a re-schedule can reuse the id.
  TextColumn get status => text().map(const NotificationStatusConverter())();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A log of exports the user has taken, for their own reference (ARCH_3 §3.1).
@DataClassName('BackupHistoryRow')
class BackupHistory extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Where the file was written. Recorded for display only — the path may since have moved or
  /// been deleted, and nothing reads from it.
  TextColumn get filePath => text()();

  /// Size of the produced file in bytes.
  IntColumn get sizeBytes => integer()();

  /// The schema version at export time, so a restore can refuse a newer file (anomaly A32).
  IntColumn get schemaVersion => integer()();

  /// The app version at export time.
  TextColumn get appVersion => text()();

  /// Whether the user triggered it or a background job did.
  TextColumn get kind => text().map(const BackupKindConverter())();

  /// Per-table row counts as JSON, so a restore can be sanity-checked against the export.
  TextColumn get recordCountsJson => text().nullable()();

  /// Optional free-text note.
  TextColumn get note => text().nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Memoised results for analytics queries slower than roughly 200 ms (ARCH_3 §5.2). Defined in
/// Phase 1B and unused until Phase 7B purely so that adding it later is not a migration.
/// Natural text key.
@DataClassName('AnalyticsCacheRow')
class AnalyticsCache extends Table {
  /// The query's name, e.g. `spendBySubtype`.
  TextColumn get cacheKey => text()();

  /// Hash of the query parameters, so the same query with different arguments does not collide.
  TextColumn get paramsHash => text()();

  /// The memoised result as JSON.
  TextColumn get payloadJson => text()();

  /// When it was computed, epoch millis UTC.
  IntColumn get computedAt => integer()();

  /// After this instant the entry is stale, epoch millis UTC. Invalidation on write to a
  /// contributing table is the primary mechanism; this is the backstop.
  IntColumn get staleAfter => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active. Present for uniformity with
  /// ARCH_2 §2 only — a cache entry is evicted rather than soft-deleted, so this is a candidate
  /// for removal if you would rather the schema not carry a column nothing will set.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {cacheKey};
}