import 'package:drift/drift.dart';

import 'package:alaya/data/db/converters/date_key_converter.dart';
import 'package:alaya/data/db/converters/enum_converters.dart';
import 'package:alaya/data/db/tables/meta_tables.dart';
import 'package:alaya/data/db/tables/money_tables.dart';
import 'package:alaya/data/db/tables/recurring_tables.dart';

/// A durable, serviceable, non-consumable thing **or person** (ARCH_1 §3.2).
///
/// [type] `serviceProvider` is how a house maid lives in the same table as a TV: an asset, plus a
/// linked [RecurringTemplates] row for monthly salary, plus a [ServiceRecords] row per payment.
/// No second system (anomaly A30).
///
/// There is no delete path. [status] `disposed` plus [disposalReason] implements "delete my TV by
/// selecting a reason" as a status change, so the money spent on it stays in analytics
/// (ARCH_3 §4.1).
@DataClassName('AssetRow')
class Assets extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Display name as the user typed it.
  TextColumn get name => text()();

  /// Normalised form used for identity matching only, never displayed.
  TextColumn get normalizedName => text()();

  /// What kind of asset — or person — this is.
  TextColumn get type => text().map(const AssetTypeConverter())();

  /// Manufacturer or brand.
  TextColumn get brand => text().nullable()();

  /// Model number.
  TextColumn get modelNo => text().nullable()();

  /// Serial number.
  TextColumn get serialNo => text().nullable()();

  /// Civil date acquired.
  IntColumn get purchaseDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// Purchase price in minor units, paired with [purchaseCurrencyCode].
  IntColumn get purchasePriceMinor => integer().nullable()();

  /// Currency of [purchasePriceMinor].
  TextColumn get purchaseCurrencyCode => text().nullable().references(Currencies, #code)();

  /// The transaction line that created this asset, if it came from a purchase.
  TextColumn get sourceTransactionLineId =>
      text().nullable().references(TransactionLines, #id)();

  /// Civil date warranty cover begins.
  IntColumn get warrantyStartDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// Civil date warranty cover ends. Drives the warranty timeline (ARCH_3 §5.1 query 20) and the
  /// calendar's `warrantyEnd` events.
  IntColumn get warrantyEndDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// Who provides the warranty.
  TextColumn get warrantyProvider => text().nullable()();

  /// Free-text warranty detail.
  TextColumn get warrantyNote => text().nullable()();

  /// Nominal days between services, used to propose [nextServiceDueDateKey].
  IntColumn get serviceIntervalDays => integer().nullable()();

  /// Civil date the next service is due.
  IntColumn get nextServiceDueDateKey =>
      integer().map(const DateKeyConverter()).nullable()();

  /// Primary contact name, e.g. the technician or the person themselves.
  TextColumn get primaryContactName => text().nullable()();

  /// Primary contact phone number, made tappable in the UI.
  TextColumn get primaryContactPhone => text().nullable()();

  /// Where the asset physically is.
  TextColumn get location => text().nullable()();

  /// The recurring template that pays for this asset, e.g. a monthly salary or subscription fee.
  TextColumn get linkedRecurringTemplateId =>
      text().nullable().references(RecurringTemplates, #id)();

  /// Current lifecycle state. Never silently `disposed`.
  TextColumn get status => text().map(const AssetStatusConverter())();

  /// Civil date of disposal.
  IntColumn get disposedAtDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// Why it was disposed of. Non-null exactly when [status] is `disposed`.
  TextColumn get disposalReason =>
      text().map(const AssetDisposalReasonConverter()).nullable()();

  /// Free-text disposal detail.
  TextColumn get disposalNote => text().nullable()();

  /// Sale proceeds in minor units, if sold. Uses the asset's [purchaseCurrencyCode].
  IntColumn get disposalAmountMinor => integer().nullable()();

  /// Optional free-text notes.
  TextColumn get notes => text().nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active. Reserved for the trash screen;
  /// ordinary removal is disposal, not deletion.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One service, repair or payment event against an [Assets] row. Also the payment log for a
/// `serviceProvider` asset, via [type] `salaryPaid`.
@DataClassName('ServiceRecordRow')
class ServiceRecords extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// The asset this record belongs to.
  TextColumn get assetId => text().references(Assets, #id)();

  /// The civil date of the event.
  IntColumn get serviceDateKey => integer().map(const DateKeyConverter())();

  /// What kind of event this was.
  TextColumn get type => text().map(const ServiceRecordTypeConverter())();

  /// Who performed it.
  TextColumn get providerName => text().nullable()();

  /// Their contact number.
  TextColumn get providerPhone => text().nullable()();

  /// Cost in minor units, paired with [currencyCode]. Drives lifetime-service-cost per asset
  /// (ARCH_3 §5.1 query 19).
  IntColumn get costMinor => integer().nullable()();

  /// Currency of [costMinor].
  TextColumn get currencyCode => text().nullable().references(Currencies, #code)();

  /// The withdrawal this cost was booked as, when the user chose to record it as an expense.
  TextColumn get linkedTransactionId => text().nullable().references(Transactions, #id)();

  /// The civil date the next service was scheduled for at the time of this one.
  IntColumn get nextDueDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// Optional free-text notes.
  TextColumn get notes => text().nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}