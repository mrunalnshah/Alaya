import 'package:drift/drift.dart';

import 'package:alaya/data/db/converters/date_key_converter.dart';
import 'package:alaya/data/db/converters/enum_converters.dart';

/// Key/value store for everything user-configurable (ARCH_2 §3). Natural text key, no UUID.
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  /// Setting identifier, e.g. `homeCurrencyCode`.
  TextColumn get key => text()();

  /// The setting value, always serialised to text; [valueType] says how to read it.
  TextColumn get value => text()();

  /// How to interpret [value] — e.g. `string`, `int`, `bool`, `json`. Free text rather than an
  /// enum: Phase 1A declares no enum for it, and inventing one here would be a schema contract
  /// (Law L13) created by guesswork.
  TextColumn get valueType => text()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Supported currencies, extensible with no migration (ARCH_2 §3). Natural text key.
@DataClassName('CurrencyRow')
class Currencies extends Table {
  /// ISO 4217 code, e.g. `INR`.
  TextColumn get code => text()();

  /// Display name, e.g. `Indian Rupee`.
  TextColumn get name => text()();

  /// Display symbol, e.g. `₹`.
  TextColumn get symbol => text()();

  /// Minor units per major unit as a power of ten — 2 for INR/USD/EUR/CNY, 0 for JPY. The
  /// reason nothing in the app hardcodes `100` (ARCH_1 §4.1).
  IntColumn get decimalDigits => integer()();

  /// Whether this currency is offered in pickers.
  BoolColumn get isEnabled => boolean()();

  /// Manual ordering within pickers.
  IntColumn get sortOrder => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {code};
}

/// Daily exchange-rate cache. Only ever holds rows with `baseCode = 'USD'` — every other pair
/// is cross-rated locally from the USD pivot (ARCH_3 §1.2), which is what keeps the app to one
/// HTTP request per day.
@DataClassName('CurrencyRateRow')
class CurrencyRates extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Base currency of the quote. Always `USD` in practice.
  TextColumn get baseCode => text().references(Currencies, #code)();

  /// Quoted currency.
  TextColumn get quoteCode => text().references(Currencies, #code)();

  /// Civil date the rate applies to.
  IntColumn get rateDateKey => integer().map(const DateKeyConverter())();

  /// The rate as a double, for display and arithmetic.
  RealColumn get rate => real()();

  /// The exact string the API returned, so any number a user questions can be reproduced
  /// (ARCH_3 §1.3).
  TextColumn get rateRaw => text()();

  /// Which endpoint supplied it, for debugging the fallback ladder.
  TextColumn get source => text()();

  /// Fetch instant, epoch millis UTC.
  IntColumn get fetchedAt => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// System and user-defined units, each an exact integer factor to its category base
/// (ARCH_1 §5.3). Natural text key.
@DataClassName('UnitRow')
class Units extends Table {
  /// Unit code, e.g. `kg`, `ml`, `dozen`.
  TextColumn get code => text()();

  /// Which of the three fixed categories this unit measures.
  TextColumn get category => text().map(const UnitCategoryConverter())();

  /// Exact integer milli-base units per one of this unit — `kg` is `1000000`, `dozen` is
  /// `12000`. Integer by design: unit conversion never touches a double (Law L2).
  IntColumn get factorToBaseMilli => integer()();

  /// Human-readable name for pickers.
  TextColumn get displayName => text()();

  /// Whether this unit was seeded rather than user-created; system units cannot be deleted.
  BoolColumn get isSystem => boolean()();

  /// Manual ordering within pickers.
  IntColumn get sortOrder => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {code};
}

/// Receipt and warranty images. Defined in Phase 1B with no UI until Phase 8B, purely so that
/// adding attachments later is not a migration (ARCH_2 §3).
@DataClassName('AttachmentRow')
class Attachments extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Which kind of record owns this attachment, e.g. `transaction`, `asset`. Free text rather
  /// than a real foreign key: this is the one intentionally polymorphic pointer in the schema,
  /// and anomaly A35's fix was to avoid polymorphic FKs elsewhere by using join tables — an
  /// attachment genuinely can belong to any owner type, so integrity is enforced in the
  /// repository instead.
  TextColumn get ownerType => text()();

  /// The owning record's id.
  TextColumn get ownerId => text()();

  /// Path relative to the app's attachment directory, never absolute — absolute paths break
  /// on restore to a different device.
  TextColumn get relativePath => text()();

  /// MIME type, e.g. `image/jpeg`.
  TextColumn get mimeType => text()();

  /// File size in bytes, for the backup size estimate.
  IntColumn get sizeBytes => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}