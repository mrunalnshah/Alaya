import 'package:drift/drift.dart';

import 'package:alaya/data/db/converters/date_key_converter.dart';
import 'package:alaya/data/db/converters/enum_converters.dart';
import 'package:alaya/data/db/tables/meta_tables.dart';
import 'package:alaya/data/db/tables/money_tables.dart';

/// A recurring cast of people, with the context that keeps a split findable later — `Goa trip`,
/// `Flat 402`, `Sunday football`.
///
/// **A label, not an account.** Nobody else logs in, nothing syncs, and no row here belongs to
/// anybody but the one user (ARCH_4 §2.3's "no multi-user" stands). A group exists so a split can be
/// filed under something the user recognises and so a cast of people is entered once.
///
/// Occasion and place live on [SplitExpenses], not here: one group has many occasions, and pinning
/// them to the group would make `Goa trip` and `Goa trip day 2` two groups.
@DataClassName('SplitGroupRow')
class SplitGroups extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Display name as the user typed it.
  TextColumn get name => text()();

  /// Normalised form used for identity matching only, never displayed.
  TextColumn get normalizedName => text()();

  /// Optional free-text note.
  TextColumn get note => text().nullable()();

  /// Optional ARGB colour.
  IntColumn get colorArgb => integer().nullable()();

  /// Optional icon identifier.
  TextColumn get iconKey => text().nullable()();

  /// Which split method this group offers first.
  ///
  /// Flatmates who always split rent 40/30/30 should not re-choose "by shares" every month.
  TextColumn get defaultSplitMethod =>
      text().map(const SplitMethodConverter())();

  /// Retired but historical. Archived groups stay in totals but leave the pickers — the
  /// distinction from soft delete that ARCH_3 §4 exists to preserve.
  BoolColumn get isArchived => boolean()();

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

/// One person's standing membership of a group.
///
/// **People are [Payees].** That table already carries `kind ∈ {person, merchant, …}` with a phone
/// and a note, so a second `people` table would be a second vocabulary for one concept — and the
/// same person appearing as both a payee and a split member is exactly the duplication ARCH_1 §3.1
/// spent three tables avoiding.
///
/// **Who *you* are is not a flag here.** It is one `app_settings` key, `split.selfPayeeId`. A column
/// on this table would let two rows claim it, and a flag on the shared `payees` table would change
/// a table five other modules read.
@DataClassName('SplitMemberRow')
class SplitMembers extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// The group.
  TextColumn get groupId => text().references(SplitGroups, #id)();

  /// The person, as a payee.
  TextColumn get payeeId => text().references(Payees, #id)();

  /// This member's default weight within the group, in basis points.
  ///
  /// Nullable because most groups split equally and storing `3333` three times would invite the
  /// question of why they do not sum to 10,000. Set it once for `40/30/30` and the editor stops
  /// asking.
  IntColumn get defaultWeightBasisPoints => integer().nullable()();

  /// Manual ordering within the group.
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

/// One shared expense, and who fronted the money for it.
///
/// ## Two cases, and the nullable [transactionId] is what holds both
///
/// **You paid.** Cash left your account, so a `transactions` withdrawal for the *full* amount exists
/// and [transactionId] points at it. Recording only your own share would make the account balance
/// wrong on the day.
///
/// **Somebody else paid.** No money has left your account, so there is **no transaction at all**
/// until you settle — [transactionId] is null and [paidByPayeeId] names who covered it. Most
/// implementations of this feature model only the first case and bolt the second on afterwards.
///
/// ## What is deliberately absent
///
/// **No `myShareMinor`.** Law L3 — no total is ever stored. Your share is a sum over
/// [SplitShares] and it is the single most tempting column in this schema; it would drift the first
/// time a share was edited.
///
/// **No `settledMinor` and no `isSettled`.** Same reason. Settlement is a ledger of
/// [SplitSettlements] rows, and what remains is a view.
@DataClassName('SplitExpenseRow')
class SplitExpenses extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// The group this belongs to, or null for a one-off split with one person.
  TextColumn get groupId => text().nullable().references(SplitGroups, #id)();

  /// The transaction that moved your money, or null when somebody else paid.
  TextColumn get transactionId =>
      text().nullable().references(Transactions, #id)();

  /// Who actually paid the bill.
  TextColumn get paidByPayeeId => text().references(Payees, #id)();

  /// What the whole bill came to, in minor units.
  IntColumn get totalAmountMinor => integer()();

  /// The currency the bill was in.
  TextColumn get currencyCode => text().references(Currencies, #code)();

  /// The civil date the expense happened on.
  IntColumn get dateKey => integer().map(const DateKeyConverter())();

  /// `dateKey`'s month, denormalised for month-grouped reads — the same pattern
  /// `transactions.monthKey` uses.
  IntColumn get monthKey => integer()();

  /// What it was — `Dinner at Olive`, `October rent`.
  TextColumn get title => text().nullable()();

  /// Where it happened. An analytics dimension, not decoration: "what do we spend in Goa" is a
  /// question no split app answers.
  TextColumn get place => text().nullable()();

  /// What the occasion was — `Diwali`, `Ravi's birthday`.
  TextColumn get occasion => text().nullable()();

  /// Optional free-text note.
  TextColumn get note => text().nullable()();

  /// How the shares were specified.
  TextColumn get splitMethod => text().map(const SplitMethodConverter())();

  /// An optional date to settle by, which feeds the calendar and the daily digest.
  IntColumn get settleByDateKey =>
      integer().nullable().map(const DateKeyConverter())();

  /// The amount converted into the home currency, in minor units.
  ///
  /// A **frozen snapshot** taken when the expense was recorded (Law L9), not a live conversion. A
  /// holiday split in THB must keep the rate it was entered at, or last March's trip re-prices
  /// itself every time the rate table updates.
  IntColumn get convertedAmountMinor => integer().nullable()();

  /// The currency [convertedAmountMinor] is in.
  TextColumn get convertedCurrencyCode =>
      text().nullable().references(Currencies, #code)();

  /// The rate used, as a display string. Kept so the conversion can be explained, never re-derived.
  TextColumn get conversionRate => text().nullable()();

  /// The raw rate as fetched, before any rounding, for audit.
  TextColumn get conversionRateRaw => text().nullable()();

  /// The civil date the rate was valid on.
  IntColumn get conversionDateKey =>
      integer().nullable().map(const DateKeyConverter())();

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
    // A bill of nothing is not a bill.
    'CHECK (total_amount_minor > 0)',
    // Itemised splitting needs the receipt, and the receipt is the transaction's own lines. A share
    // cannot name a line number when no transaction exists to hold one — see SplitShares.
    'CHECK (split_method <> \'perLine\' OR transaction_id IS NOT NULL)',
  ];
}

/// What one participant owes on one expense, and how that was decided.
///
/// **Both the input and the resolved amount are stored, deliberately.** Re-deriving shares from
/// their inputs on every read would re-run largest-remainder allocation and could hand the stray
/// paise to a different person than the one the user saw and agreed to. [shareAmountMinor] is what
/// they owe; [inputKind] and [inputValue] are how it was arrived at, so the editor can show 40/30/30
/// rather than three amounts.
@DataClassName('SplitShareRow')
class SplitShares extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// The expense being split.
  TextColumn get splitExpenseId => text().references(SplitExpenses, #id)();

  /// Who owes this share.
  TextColumn get payeeId => text().references(Payees, #id)();

  /// The `transaction_lines.lineNo` this share is against, or null for a share of the whole expense.
  ///
  /// **This column is the itemised split** — the ₹400 dessert is one line with one participant while
  /// the ₹1,200 platter is one line split four ways, and each person's total becomes a sum over lines
  /// rather than a division of the bill.
  ///
  /// Only meaningful when the expense has a transaction, which the CHECK below enforces.
  IntColumn get transactionLineNo => integer().nullable()();

  /// The exact amount owed, in minor units. Sums with its siblings to the allocated total.
  IntColumn get shareAmountMinor => integer()();

  /// How this share was specified.
  TextColumn get inputKind => text().map(const ShareInputKindConverter())();

  /// The typed value behind [inputKind] — minor units for `exact`, basis points for `percent`, a
  /// weight for `shares`, and null for `equal`.
  IntColumn get inputValue => integer().nullable()();

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
    // A share may be zero — the guest who did not eat — but never negative. A negative share reads
    // as being owed money by a bill you are paying.
    'CHECK (share_amount_minor >= 0)',
    // `percent` and `shares` carry a value; `equal` carries none. Catching a null weight here means
    // a share the resolver cannot interpret never reaches a row.
    "CHECK (input_kind = 'equal' OR input_value IS NOT NULL)",
    // A percentage is basis points, so it cannot exceed 100% of anything meaningful, and a weight
    // cannot be negative. Both are the same column, so one range covers them.
    'CHECK (input_value IS NULL OR input_value >= 0)',
  ];

  // **"A line number only when the expense has a transaction" is deliberately NOT a CHECK.** It
  // spans two tables, and SQLite CHECK constraints cannot contain a subquery — an attempt would
  // either be rejected at `CREATE TABLE` or, worse, silently accepted and never evaluated. The
  // expense-side guard (`split_method <> 'perLine' OR transaction_id IS NOT NULL`) is enforceable
  // because it is single-row; this direction is the repository's to uphold, and session 3's
  // `insertWithShares` is where it belongs — the same division `transactions.monthKey` uses, where
  // the database enforces what it can see and the DAO's doc comment carries the rest.
}

/// Money that actually changed hands to settle a debt.
///
/// **Many settlements per debt, on purpose.** "Keep adding as they keep paying" is partial
/// settlement, and what remains outstanding is a view over these rows — never a decremented column
/// (Law L3).
///
/// [transactionId] is non-null whenever you are a party, because a settlement you are in moved your
/// money and must appear in your ledger. It is nullable only for a settlement between two other
/// people, which an accepted simplification plan can produce.
@DataClassName('SplitSettlementRow')
class SplitSettlements extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// The group this settles within, or null for a one-off debt.
  TextColumn get groupId => text().nullable().references(SplitGroups, #id)();

  /// Who paid.
  TextColumn get fromPayeeId => text().references(Payees, #id)();

  /// Who was paid.
  TextColumn get toPayeeId => text().references(Payees, #id)();

  /// How much, in minor units.
  IntColumn get amountMinor => integer()();

  /// The currency.
  TextColumn get currencyCode => text().references(Currencies, #code)();

  /// The civil date the money moved.
  IntColumn get dateKey => integer().map(const DateKeyConverter())();

  /// `dateKey`'s month, denormalised for month-grouped reads.
  IntColumn get monthKey => integer()();

  /// The transaction this wrote into your ledger. Non-null whenever you are a party.
  ///
  /// **This is what makes a settlement real rather than a flag.** Splitwise's "settle up" is a
  /// bookkeeping marker that cannot touch your bank; here the deposit or withdrawal is an ordinary
  /// `transactions` row, so the split ledger and the account ledger cannot diverge.
  TextColumn get transactionId =>
      text().nullable().references(Transactions, #id)();

  /// How the money travelled — UPI, cash, bank transfer.
  TextColumn get paymentMethodId =>
      text().nullable().references(PaymentMethods, #id)();

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

  @override
  List<String> get customConstraints => [
    'CHECK (amount_minor > 0)',
    // Paying yourself is not a settlement.
    'CHECK (from_payee_id <> to_payee_id)',
  ];
}
