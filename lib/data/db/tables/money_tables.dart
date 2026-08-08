import 'package:drift/drift.dart';

import 'package:alaya/data/db/converters/date_key_converter.dart';
import 'package:alaya/data/db/converters/enum_converters.dart';
import 'package:alaya/data/db/tables/inventory_tables.dart';
import 'package:alaya/data/db/tables/meta_tables.dart';
import 'package:alaya/data/db/tables/recurring_tables.dart';
import 'package:alaya/data/db/tables/service_tables.dart';

/// A container that holds money and has a balance — `Cash in hand`, `HDFC Savings`,
/// `Paytm Wallet`. Exactly one currency each (ARCH_1 §3.1).
///
/// Distinct from [PaymentMethods] (the rail money travelled on) and [Payees] (the
/// counterparty). Collapsing those three into one list is anomaly A01, and it is what makes
/// "Total Available Funds" unanswerable.
@DataClassName('AccountRow')
class Accounts extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Display name as the user typed it.
  TextColumn get name => text()();

  /// Normalised form used for identity matching only, never displayed.
  TextColumn get normalizedName => text()();

  /// What kind of container this is, for grouping and iconography.
  TextColumn get kind => text().map(const AccountKindConverter())();

  /// The single currency this account is denominated in.
  TextColumn get currencyCode => text().references(Currencies, #code)();

  /// Balance already present when tracking began, in minor units. Without this a user's real
  /// existing cash is invisible forever (anomaly A03).
  IntColumn get openingBalanceMinor => integer()();

  /// Civil date the opening balance was true on. Not nullable: a balance without a date cannot
  /// be placed on the balance-trend series (ARCH_3 §5.1 query 7).
  IntColumn get openingBalanceDateKey => integer().map(const DateKeyConverter())();

  /// Optional ARGB colour.
  IntColumn get colorArgb => integer().nullable()();

  /// Optional icon identifier.
  TextColumn get iconKey => text().nullable()();

  /// Retired but historical. Archived accounts stay in net worth and totals but leave the
  /// pickers — the distinction from soft delete that ARCH_3 §4 exists to preserve.
  BoolColumn get isArchived => boolean()();

  /// Whether this account contributes to the net-worth headline.
  BoolColumn get includeInNetWorth => boolean()();

  /// Manual ordering within pickers.
  IntColumn get sortOrder => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The rail money travelled on — `Cash`, `UPI`, `Card`, `Bank Transfer`, `Cheque`. Metadata
/// only: a payment method never holds a balance (ARCH_1 §3.1).
@DataClassName('PaymentMethodRow')
class PaymentMethods extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Display name as the user typed it.
  TextColumn get name => text()();

  /// Which rail this represents.
  TextColumn get kind => text().map(const PaymentMethodKindConverter())();

  /// Whether this method was seeded rather than user-created.
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
  Set<Column<Object>> get primaryKey => {id};
}

/// The counterparty on a transaction, used for both `From` (deposits) and `To` (withdrawals).
@DataClassName('PayeeRow')
class Payees extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Display name as the user typed it.
  TextColumn get name => text()();

  /// Normalised form used for identity matching only, never displayed.
  TextColumn get normalizedName => text()();

  /// What kind of counterparty this is.
  TextColumn get kind => text().map(const PayeeKindConverter())();

  /// Optional contact number.
  TextColumn get phone => text().nullable()();

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

/// One movement of money — the first of the app's three append-only truths (ARCH_1 §3.3).
///
/// A `transfer` is **one row**, not a pair: Phase 1C's `v_account_ledger` expands it into two
/// signed legs, which is why a self-transfer nets to zero by construction and cannot drift
/// (anomaly A02). The three table-level CHECK constraints below are what make that view sound —
/// without them a malformed row could produce a leg with a null account.
@DataClassName('TransactionRow')
class Transactions extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Which direction money moved and how it affects balances.
  TextColumn get kind => text().map(const TransactionKindConverter())();

  /// The structural flow subtype: decides which editor form appears and which analytics bucket
  /// this lands in. Closed enum by design, unlike the open [Tags] (ARCH_1 §3.1).
  TextColumn get subtype => text().map(const TransactionSubtypeConverter())();

  /// When it happened, epoch millis UTC.
  IntColumn get occurredAt => integer()();

  /// The local civil date it happened on.
  IntColumn get dateKey => integer().map(const DateKeyConverter())();

  /// `yyyymm`, denormalised from [dateKey] so monthly analytics never compute it per row. Kept
  /// consistent by the third CHECK constraint rather than by discipline.
  IntColumn get monthKey => integer()();

  /// The amount as stored, always positive — the sign comes from [kind] (Law L1).
  IntColumn get originalAmountMinor => integer()();

  /// Currency of [originalAmountMinor]. Immutable once saved, together with the amount (Law L9).
  TextColumn get originalCurrencyCode => text().references(Currencies, #code)();

  /// Source account for withdrawals, decreases and transfers.
  TextColumn get fromAccountId => text().nullable().references(Accounts, #id)();

  /// Destination account for deposits, increases and transfers.
  TextColumn get toAccountId => text().nullable().references(Accounts, #id)();

  /// The rail money travelled on.
  TextColumn get paymentMethodId => text().nullable().references(PaymentMethods, #id)();

  /// The counterparty.
  TextColumn get payeeId => text().nullable().references(Payees, #id)();

  /// Optional free-text note. Indexed for full-text search in Phase 1C.
  TextColumn get note => text().nullable()();

  /// Set by quick-add when only an amount was supplied; drives the "add details" nudge.
  BoolColumn get needsReview => boolean()();

  /// The recurring template this settled, if any. Also the discriminator for ARCH_3 §5.1
  /// query 18's recurring-versus-discretionary split.
  TextColumn get recurringTemplateId =>
      text().nullable().references(RecurringTemplates, #id)();

  /// The specific occurrence this settled, if any.
  TextColumn get recurringOccurrenceId =>
      text().nullable().references(RecurringOccurrences, #id)();

  /// Frozen converted amount, written only by the explicit per-transaction freeze action. Never
  /// recomputed and never a substitute for [originalAmountMinor] (Law L9).
  IntColumn get convertedAmountMinor => integer().nullable()();

  /// Currency of [convertedAmountMinor].
  TextColumn get convertedCurrencyCode => text().nullable()();

  /// The rate used at freeze time.
  RealColumn get conversionRate => real().nullable()();

  /// The exact rate string the API returned, so a questioned number can be reproduced.
  TextColumn get conversionRateRaw => text().nullable()();

  /// The civil date the frozen rate was quoted for.
  IntColumn get conversionDateKey => integer().map(const DateKeyConverter()).nullable()();

  /// Why the user deleted this, captured at soft-delete time.
  TextColumn get deleteReason => text().nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (original_amount_minor > 0)',
    'CHECK ('
        "(kind IN ('deposit','adjustmentIncrease')"
        ' AND to_account_id IS NOT NULL AND from_account_id IS NULL)'
        ' OR '
        "(kind IN ('withdrawal','adjustmentDecrease')"
        ' AND from_account_id IS NOT NULL AND to_account_id IS NULL)'
        ' OR '
        "(kind = 'transfer'"
        ' AND from_account_id IS NOT NULL AND to_account_id IS NOT NULL'
        ' AND from_account_id <> to_account_id)'
        ')',
    'CHECK (date_key / 100 = month_key)',
  ];
}

/// One purchased thing inside a [Transactions] row (ARCH_2 §4.2).
///
/// Optional detail: `transactions.original_amount_minor` remains the source of truth, and when
/// the lines do not sum to it the difference surfaces as an "unallocated" chip rather than being
/// auto-balanced (anomaly A11). These columns are also what make ARCH_3 §5.1's differentiating
/// queries 9-12 and 24 possible at all.
@DataClassName('TransactionLineRow')
class TransactionLines extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// The owning transaction.
  TextColumn get transactionId => text().references(Transactions, #id)();

  /// Position within the transaction, 1-based.
  IntColumn get lineNo => integer()();

  /// What was bought, as free text.
  TextColumn get description => text()();

  /// The catalogued item, when this line refers to one. Nullable so buying something never
  /// catalogued still records a line.
  TextColumn get itemId => text().nullable().references(Items, #id)();

  /// Quantity in **base-milli units**, not in [unitCode] (Law L2). Aggregating this column
  /// directly is valid and needs no unit conversion.
  IntColumn get quantityMilli => integer().nullable()();

  /// The unit the user actually typed, kept only so the line renders as `2 kg` rather than
  /// `2000 g`.
  TextColumn get unitCode => text().nullable().references(Units, #code)();

  /// Price per [unitCode], in minor units. Drives the personal-inflation series (query 12).
  IntColumn get unitPriceMinor => integer().nullable()();

  /// Total for this line, in minor units.
  IntColumn get lineAmountMinor => integer().nullable()();

  /// What this line produced elsewhere in the app — the single field that removes the
  /// electronics/inventory/service ambiguity (anomaly A12). One line produces at most one
  /// artefact, and the matching `created*Id` records which.
  TextColumn get destination => text().map(const TransactionLineDestinationConverter())();

  /// The inventory batch this line created, if [destination] was inventory.
  TextColumn get createdBatchId => text().nullable().references(InventoryBatches, #id)();

  /// The asset this line created, if [destination] was asset.
  TextColumn get createdAssetId => text().nullable().references(Assets, #id)();

  /// The recurring template this line created, if [destination] was recurring.
  TextColumn get createdRecurringTemplateId =>
      text().nullable().references(RecurringTemplates, #id)();

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
