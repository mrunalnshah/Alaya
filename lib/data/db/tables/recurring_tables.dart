import 'package:drift/drift.dart';

import 'package:alaya/data/db/converters/date_key_converter.dart';
import 'package:alaya/data/db/converters/enum_converters.dart';
import 'package:alaya/data/db/tables/meta_tables.dart';
import 'package:alaya/data/db/tables/money_tables.dart';
import 'package:alaya/data/db/tables/service_tables.dart';
import 'package:alaya/data/db/tables/tag_tables.dart';

/// A repeating obligation or income (ARCH_1 §3.2).
///
/// [direction] is what lets salary live here rather than needing a second, parallel system
/// (anomaly A27).
@DataClassName('RecurringTemplateRow')
class RecurringTemplates extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Display name as the user typed it.
  TextColumn get name => text()();

  /// Normalised form used for identity matching only, never displayed.
  TextColumn get normalizedName => text()();

  /// Rough classification, for grouping and iconography.
  TextColumn get kind => text().map(const RecurringKindConverter())();

  /// Whether settling an occurrence creates a withdrawal or a deposit.
  TextColumn get direction => text().map(const RecurringDirectionConverter())();

  /// The usual amount in minor units. An occurrence may be settled for a different amount, which
  /// is recorded on the occurrence rather than overwriting this (anomaly A29).
  IntColumn get defaultAmountMinor => integer()();

  /// Currency of [defaultAmountMinor].
  TextColumn get currencyCode => text().references(Currencies, #code)();

  /// Who is billed or who pays.
  TextColumn get payeeId => text().nullable().references(Payees, #id)();

  /// The account settlement defaults to.
  TextColumn get defaultAccountId => text().nullable().references(Accounts, #id)();

  /// The rail settlement defaults to.
  TextColumn get defaultPaymentMethodId =>
      text().nullable().references(PaymentMethods, #id)();

  /// The tag applied to transactions this template creates.
  TextColumn get tagId => text().nullable().references(Tags, #id)();

  /// The unit the repeat interval is counted in.
  TextColumn get intervalUnit => text().map(const RecurringIntervalUnitConverter())();

  /// How many [intervalUnit]s between occurrences.
  IntColumn get intervalCount => integer()();

  /// Day of month, 1-31, for monthly and yearly intervals.
  ///
  /// **Stored once and clamped at render, never mutated** (anomaly A13). A bill anchored on the
  /// 31st renders as 28, 29 or 30 in short months but stays anchored on the 31st, instead of
  /// walking backwards to the 28th permanently after one February — which is what happens if the
  /// clamped value is written back.
  IntColumn get anchorDayOfMonth => integer().nullable()();

  /// Month of year, 1-12, for yearly intervals.
  IntColumn get anchorMonth => integer().nullable()();

  /// ISO weekday, 1-7, for weekly intervals.
  IntColumn get anchorWeekday => integer().nullable()();

  /// First civil date this template is active from.
  IntColumn get startDateKey => integer().map(const DateKeyConverter())();

  /// Last civil date this template is active until. Null means indefinite.
  IntColumn get endDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// The next civil date an occurrence is due on.
  IntColumn get nextDueDateKey => integer().map(const DateKeyConverter())();

  /// Suspended without being deleted; no new occurrences materialise.
  BoolColumn get isPaused => boolean()();

  /// Whether to schedule a local notification before each due date.
  BoolColumn get autoRemind => boolean()();

  /// How many days before the due date to remind.
  IntColumn get remindDaysBefore => integer()();

  /// The asset this template pays for — the link that lets a house maid's monthly salary hang
  /// off an [Assets] row (ARCH_2 §8.1).
  TextColumn get linkedAssetId => text().nullable().references(Assets, #id)();

  /// Optional free-text note.
  TextColumn get note => text().nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active. Deleting a template is soft, and
  /// settled occurrences with their transactions survive it (ARCH_3 §4.1).
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One dated instance of a [RecurringTemplates] row — the third of the app's three append-only
/// truths (ARCH_1 §3.3).
///
/// Rows are **materialised lazily** up to today, never in advance and never automatically
/// settled: money is only ever created by an explicit user tap (anomaly A14). A `due` row whose
/// [dueDateKey] has passed renders as *overdue*, which is derived at read time and deliberately
/// not a stored status.
@DataClassName('RecurringOccurrenceRow')
class RecurringOccurrences extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// The template this instance belongs to.
  TextColumn get templateId => text().references(RecurringTemplates, #id)();

  /// The civil date this instance is due on.
  IntColumn get dueDateKey => integer().map(const DateKeyConverter())();

  /// Settlement state. Never `paid` without [paidTransactionId].
  TextColumn get status => text().map(const RecurringOccurrenceStatusConverter())();

  /// The transaction that settled this occurrence.
  TextColumn get paidTransactionId => text().nullable().references(Transactions, #id)();

  /// The amount actually paid, in minor units, which may differ from the template default.
  /// Analytics uses this rather than the default (anomaly A29).
  IntColumn get paidAmountMinor => integer().nullable()();

  /// The civil date it was actually paid on, which may differ from [dueDateKey].
  IntColumn get paidDateKey => integer().map(const DateKeyConverter()).nullable()();

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
