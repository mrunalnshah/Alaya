# B1_CORE

Money, Qty, DateKey, Result, ids, enums. No Flutter, no drift.

**42 files · 4,412 lines.**  Written 2026-08-27T08:54:37-04:00.

Every file below is complete and current. Paths are destinations.

---

### `lib/core/enums/date_range_preset.dart`

```dart
/// A named reporting window the user can pick, resolved to concrete dates by `DateRangeService`.
///
/// Lives in `core/` rather than beside the service because both `domain/` (the service, analytics)
/// and `features/` (the picker widget) name it, and Law L12 forbids `domain/` importing from
/// anywhere above it. Same reasoning as `TagScope`.
///
/// **Not stored anywhere.** Law L13's "renaming an enum value is a breaking migration" does not
/// apply — the resolved `DateKey` pair is what reaches the database, never the preset itself. The
/// selected preset is persisted only as an `app_settings` string, which the repository maps by
/// name and falls back to [thisMonth] on an unknown value.
enum DateRangePreset {
  /// Today only, from midnight to midnight.
  today,

  /// The seven days ending today, today included.
  last7Days,

  /// The thirty days ending today, today included.
  last30Days,

  /// The first of this month through today.
  thisMonth,

  /// The whole of the previous calendar month.
  lastMonth,

  /// The first of this calendar year through today.
  thisYear,

  /// Every date the user could have recorded anything on.
  allTime,

  /// A window the user picked by hand; `DateRangeService` cannot resolve this one alone.
  custom,
}
```

### `lib/core/enums/inventory_enums.dart`

```dart
/// A rough classification of what kind of consumable an Item is, independent of its
/// [UnitCategory]. Drives a few UI defaults (e.g. medicine expiry surfacing on the
/// calendar) — see ARCH_2 §5.1.
enum ItemKind {
  /// No more specific classification applies.
  generic,

  /// Food and groceries.
  food,

  /// Medicines and health-related consumables.
  medicine,

  /// Beauty and personal-care products.
  beauty,

  /// Household and cleaning supplies.
  household,

  /// Anything not covered by the above.
  other,
}

/// Where an Inventory Batch came from.
enum BatchOrigin {
  /// Created by a withdrawal's line item.
  purchase,

  /// Added directly by the user, with no linked transaction.
  manual,

  /// Brought in from an external source (e.g. a data import or migration). Named `imported`
  /// rather than `import` — the latter is a reserved word in Dart and cannot be an enum
  /// member name, so this is a deliberate, one-value deviation from ARCH_2's literal text.
  imported,

  /// Created by a stock-correction/adjustment action.
  adjustment,

  /// Its source transaction was deleted; the batch survives on its own (see ARCH_3 §4.1 —
  /// deleting a receipt must never delete food already eaten).
  detached,
}

/// One kind of event in the append-only `stock_movements` ledger (Law L3/L6 exception: this
/// table has no soft delete — see ARCH_2 §5.3). [quantityMilli] is always positive; this
/// value carries the direction.
enum StockMovementKind {
  /// The opening stock recorded when an Item is first created with existing quantity.
  openingIn,

  /// Stock added by a withdrawal's line item.
  purchaseIn,

  /// Stock added manually by the user.
  manualIn,

  /// Stock used up through normal use.
  consume,

  /// Stock discarded as spoiled/expired before use.
  waste,

  /// Stock that reached its expiry date without being consumed or explicitly wasted.
  expired,

  /// A manual correction that increases the recorded stock.
  adjustIn,

  /// A manual correction that decreases the recorded stock.
  adjustOut,
}
```

### `lib/core/enums/money_enums.dart`

```dart
/// How a transaction moves money — which side gains, which side loses. See ARCH_1 §3.1.
/// Stored as `TEXT` via [SafeEnumConverter]; member names are a schema contract (Law L13).
enum TransactionKind {
  /// Money enters an account from outside it (salary, gift, refund, ...).
  deposit,

  /// Money leaves an account to outside it (grocery, bills, ...).
  withdrawal,

  /// Money moves between two of the user's own accounts. Never counted as income or
  /// expense — see `v_account_ledger` in ARCH_2 §12.1.
  transfer,

  /// A manual correction that increases a balance (e.g. reconciling an opening balance).
  adjustmentIncrease,

  /// A manual correction that decreases a balance.
  adjustmentDecrease,
}

/// The structural flow subtype of a transaction: decides which editor form appears and
/// which analytics bucket the transaction lands in. Distinct from a [Tag], which is an
/// open, user-defined label — see ARCH_1 §3.1 for why both exist.
enum TransactionSubtype {
  /// A grocery withdrawal; its lines may fan out into Inventory.
  grocery,

  /// A household-item withdrawal; its lines may fan out into Inventory.
  household,

  /// An electronics withdrawal; its lines may fan out into the Service Manager as an Asset.
  electronics,

  /// A bill payment, optionally linked to a Recurring Template.
  bill,

  /// A transfer to one of the user's own other accounts. Kind is `transfer`.
  transferSelf,

  /// A payment to someone else framed as "transfer" in the UI. Kind is `withdrawal`.
  transferOut,

  /// Recurring income such as salary. Kind is `deposit`.
  salaryIn,

  /// Any other deposit not covered by a more specific subtype.
  otherIn,

  /// Any other withdrawal not covered by a more specific subtype.
  otherOut,
}

/// What a container of money is, for display grouping and iconography.
enum AccountKind {
  /// Physical cash on hand.
  cash,

  /// A bank account.
  bank,

  /// A digital wallet (e.g. Paytm, Google Pay balance).
  wallet,

  /// A credit or debit card treated as its own balance-holding container.
  card,

  /// Anything not covered by the above.
  other,
}

/// The rail money travelled on. Carries no balance of its own — see [AccountKind] for that.
enum PaymentMethodKind {
  /// Physical cash handed over.
  cash,

  /// UPI (or an equivalent real-time payment rail).
  upi,

  /// A bank transfer (NEFT/IMPS/wire/ACH or equivalent).
  bankTransfer,

  /// A credit or debit card swipe/tap.
  card,

  /// A paper cheque.
  cheque,

  /// A digital wallet payment.
  wallet,

  /// Anything not covered by the above; the user's own custom rail.
  other,
}

/// The counterparty on a transaction — used for both `From` (deposits) and `To`
/// (withdrawals).
enum PayeeKind {
  /// An individual (friend, family member, tenant, ...).
  person,

  /// A shop or business.
  merchant,

  /// The user's employer, for salary deposits.
  employer,

  /// A utility or service company (electricity, telecom, ...).
  utility,

  /// Anything not covered by the above.
  other,

  /// A participant on a split whom nobody has named yet.
  ///
  /// **Not a person, and that distinction is the whole point.** `split_shares.payee_id` is
  /// `NOT NULL REFERENCES payees(id)`, so saving a split with an unnamed participant needs a payee row
  /// to exist — without one the split cannot be saved at all, which is friction charged at the moment
  /// everybody is standing up to leave the restaurant.
  ///
  /// The first attempt made those rows ordinary [person] entries called "Person 4". They worked, and
  /// they accumulated in Settings › Payees beside real contacts, which is not a trade anybody agreed
  /// to. This kind keeps the row where balances need it and out of every list where it would be noise.
  ///
  /// **Adding a member needs no migration.** `SafeEnumConverter` stores an enum by its `name`, and
  /// nothing reads `PayeeKind` by ordinal — which is exactly why Law L13 forbids *renaming* a member
  /// while adding one is free.
  ///
  /// Naming a placeholder writes `kind: person` and the real name in one update. There is no flag to
  /// clear, so a flag and a name can never disagree.
  splitPlaceholder,
}

/// What a [TransactionLine] produced elsewhere in the app, if anything. A line produces at
/// most one artefact, recorded by whichever `created*Id` column matches this value.
enum TransactionLineDestination {
  /// This line created nothing beyond itself.
  none,

  /// This line created (or added a batch to) an Inventory Item.
  inventory,

  /// This line created a Service Manager Asset.
  asset,

  /// This line created a Recurring Template.
  recurring,
}
```

### `lib/core/enums/ops_enums.dart`

```dart
/// What kind of event a scheduled local notification is for. Paired with a stable Android
/// notification id in `notification_schedule` so it can be cancelled when the underlying
/// record changes (ARCH_3 §7).
enum NotificationKind {
  /// An inventory batch is approaching (or has passed) its expiry date.
  expiry,

  /// An Asset's next service is due.
  serviceDue,

  /// A Recurring Template's occurrence is due.
  recurringDue,

  /// An Item has fallen below its low-stock threshold.
  lowStock,

  /// An Asset's warranty is ending soon.
  warrantyEnd,

  /// A shared expense the user agreed to settle by a date is coming up.
  ///
  /// **A date, not a state**, which is what makes it eligible for a digest at all. [lowStock] is left
  /// out of `reminderKinds` because "you are low on rice" has no day and would repeat every morning
  /// until somebody shopped; a settle-by date has a day, so the sentence stops being true once acted on.
  settlementDue,
}

/// The lifecycle state of one scheduled local notification.
enum NotificationStatus {
  /// Scheduled with the OS but not yet fired.
  scheduled,

  /// Already delivered.
  fired,

  /// Cancelled before firing, e.g. because the underlying record was deleted or resolved.
  cancelled,
}

/// How a backup was produced, recorded in `backup_history` for the user's own reference.
enum BackupKind {
  /// Explicitly triggered by the user.
  manual,

  /// Produced by a scheduled background job.
  auto,
}
```

### `lib/core/enums/recurring_enums.dart`

```dart
/// A rough classification of what a Recurring Template represents, for grouping and
/// iconography.
enum RecurringKind {
  /// A recurring bill (electricity, water, ...).
  bill,

  /// A recurring subscription (streaming, software, ...).
  subscription,

  /// Rent, paid or received.
  rent,

  /// Salary, paid or received.
  salary,

  /// A recurring fee for a service (e.g. a house maid's monthly payment).
  serviceFee,

  /// Anything not covered by the above.
  other,
}

/// Which way money moves when a Recurring Template's occurrence is settled. This is what
/// lets salary live in the same system as bills, rather than needing a second, parallel
/// mechanism (ARCH_1 §3.2).
enum RecurringDirection {
  /// Settling an occurrence creates a withdrawal (a bill, a subscription, ...).
  outflow,

  /// Settling an occurrence creates a deposit (salary, recurring income, ...).
  inflow,
}

/// The unit a Recurring Template's repeat interval is counted in.
enum RecurringIntervalUnit {
  /// Every N days.
  day,

  /// Every N weeks.
  week,

  /// Every N months, anchored to a day-of-month that is clamped (never mutated) at render
  /// time for short months — see ARCH_2 §7.1.
  month,

  /// Every N years.
  year,
}

/// The settlement state of one dated instance of a Recurring Template. `due` past its date
/// renders as overdue — a derived state, never stored separately.
enum RecurringOccurrenceStatus {
  /// Materialised but not yet acted on.
  due,

  /// Settled — money moved and is linked back via `paidTransactionId`.
  paid,

  /// The user explicitly chose not to pay this occurrence.
  skipped,

  /// The user dismissed this occurrence without it ever being due in a meaningful sense
  /// (e.g. a template was paused retroactively).
  dismissed,
}
```

### `lib/core/enums/safe_enum_converter.dart`

```dart
/// Converts between a Dart enum and its stored `TEXT` representation, mapping any string
/// that doesn't match a current member to a declared [fallback] instead of throwing
/// (Law L13). This is what lets an older build of the app open a database written by a
/// newer one — an unrecognised value degrades to a safe default rather than crashing — and
/// why the stored form is always the enum's own name (`"grocery"`, not `3`): a plain-text
/// backup file stays human-readable, and Law L13 forbids ever renaming an enum value once
/// shipped, since that would silently change what every existing stored row means.
final class SafeEnumConverter<T extends Enum> {
  /// Creates a converter for an enum whose members are [values] (pass `T.values`), falling
  /// back to [fallback] for any unrecognised stored string.
  const SafeEnumConverter(this.values, this.fallback);

  /// All members of the enum, in declaration order.
  final List<T> values;

  /// The member returned when a stored string matches no current member's name.
  final T fallback;

  /// The stored `TEXT` representation of [value] — always its Dart enum name.
  String toSql(T value) => value.name;

  /// The enum member whose name matches [raw], or [fallback] if none does.
  T fromSql(String raw) {
    for (final candidate in values) {
      if (candidate.name == raw) return candidate;
    }
    return fallback;
  }
}
```

### `lib/core/enums/service_enums.dart`

```dart
/// What kind of durable, serviceable thing (or person) an Asset represents.
enum AssetType {
  /// A home appliance (fridge, washing machine, ...).
  appliance,

  /// A consumer electronics item (TV, laptop, phone, ...).
  electronics,

  /// A car, motorbike, or other vehicle.
  vehicle,

  /// Furniture.
  furniture,

  /// A property (house, flat, land, ...).
  property,

  /// A person providing an ongoing service (e.g. a house maid), tracked the same way as a
  /// physical asset so a single system covers both — see ARCH_2 §8.1.
  serviceProvider,

  /// A non-physical recurring subscription tracked here for its service history rather than
  /// only as a Recurring Template.
  subscription,

  /// Anything not covered by the above.
  other,
}

/// The current lifecycle state of an Asset. There is no "deleted" state — disposal is a
/// status change with a reason, never a delete (ARCH_3 §4.1).
enum AssetStatus {
  /// In normal use.
  active,

  /// Temporarily out of service, e.g. sent for repair.
  underRepair,

  /// No longer owned/in use. See [AssetDisposalReason] for why.
  disposed,
}

/// Why an Asset was disposed. Recorded so its purchase history and cost remain in analytics
/// even after disposal.
enum AssetDisposalReason {
  /// Sold to someone else.
  sold,

  /// Reached the end of its usable/warranty life.
  expired,

  /// Broken beyond economical repair.
  damaged,

  /// Given away.
  gifted,

  /// Lost or stolen.
  lost,

  /// Replaced by a newer Asset.
  replaced,

  /// Anything not covered by the above.
  other,
}

/// What kind of event a [ServiceRecord] represents.
enum ServiceRecordType {
  /// A routine service visit.
  service,

  /// A repair for a specific fault.
  repair,

  /// General maintenance not tied to a specific fault.
  maintenance,

  /// An inspection or checkup with no work performed.
  inspection,

  /// A salary payment to a [AssetType.serviceProvider] asset (e.g. a house maid).
  salaryPaid,

  /// Anything not covered by the above.
  other,
}
```

### `lib/core/enums/shopping_enums.dart`

```dart
/// How a [ShoppingEntry] came to exist, which decides whether it can be silently
/// regenerated/removed by the low-stock suggestion engine.
enum ShoppingEntryOrigin {
  /// Added directly by the user.
  manual,

  /// Generated automatically because an Item fell below its low-stock threshold. Editing
  /// such an entry promotes it to [manual] so it is never auto-removed afterwards.
  autoLowStock,

  /// Generated from a Recurring Template (e.g. a subscription that needs a physical item).
  fromRecurring,
}

/// The lifecycle state of an auto-generated [ShoppingEntry], letting a user dismiss a
/// suggestion without it reappearing on the very next regeneration.
enum ShoppingEntryAutoState {
  /// Currently shown to the user as a live suggestion.
  active,

  /// Hidden until the stock condition that generated it re-triggers after first clearing.
  snoozed,

  /// Permanently dismissed by the user for this occurrence of the low-stock condition.
  dismissed,
}
```

### `lib/core/enums/split_enums.dart`

```dart
/// Enums the split schema stores. Names are a schema contract (Law L13) — renaming a member
/// renames it in every existing row, so a member is added or deprecated, never renamed.
library;

/// How a split expense's shares were specified.
///
/// Recorded on `split_expenses` so the editor can reopen a split the way it was made rather than as
/// a list of amounts the user has to reverse-engineer. A 40/30/30 split must come back as 40/30/30.
enum SplitMethod {
  /// Everyone takes an equal share of the remainder.
  equal,

  /// Each participant's amount was typed directly.
  exactAmounts,

  /// Basis points of the total.
  percent,

  /// Weights against the other weighted participants.
  shares,

  /// Each `transaction_lines` row is split among its own participants.
  ///
  /// Needs the receipt, so it is only available on an expense the user paid for.
  perLine,
}

/// How one participant's share was specified.
///
/// Stored per row on `split_shares` rather than derived from [SplitMethod], because a mixed split is
/// the commonest real instruction: "the drinks were Ravi's, split the rest between us" is one
/// [extra] beside three [equal]s, and the header's method cannot express both.
enum ShareInputKind {
  /// An equal share of whatever is left after exact amounts, extras and percentages.
  equal,

  /// A fixed amount that is this person's **entire** share.
  ///
  /// "Priya owes exactly ₹500, full stop." She takes no part in dividing the remainder.
  exact,

  /// A fixed amount charged to this person **on top of** their equal share of the remainder.
  ///
  /// **The one input the module was missing, and it turns out to be two features.**
  ///
  /// *"Ravi bought his own drinks."* A ₹5,000 dinner where ₹400 of it was Ravi's round: the ₹400 is
  /// his, the remaining ₹4,600 splits four ways, and Ravi pays ₹1,550 while everybody else pays
  /// ₹1,150.
  ///
  /// *"I'll put in ₹2,000 and we'll split the rest."* Identical arithmetic from the other direction —
  /// ₹2,000 is charged to the payer, the remaining ₹3,000 splits four ways, and the payer's total is
  /// ₹2,750.
  ///
  /// The difference from [exact] is the whole point: an exact amount **replaces** a person's share,
  /// an extra **adds to** it. Getting that wrong is how an app tells four people they owe ₹400 each
  /// for one person's drinks.
  ///
  /// A participant with an extra takes a **weight of one** in the remainder. Combining an extra with
  /// a custom weight is deliberately not expressible: it is a fourth way to describe the same bill
  /// and this module's stated purpose is splitting simply.
  extra,

  /// Basis points of the **total** — 2500 is 25%. Basis points rather than a percentage so the
  /// stored value is an integer and Law L1 is never at risk.
  percent,

  /// A weight against the other weighted participants.
  shares,
}
```

### `lib/core/enums/tag_scope.dart`

```dart
/// Which module's tag picker a query is asking about, mapping one-to-one onto the six
/// `allowedIn*` columns on `tags` (ARCH_2 §3).
///
/// Lives in `core/` rather than beside the tag DAO deliberately. Phase 3B's abstract
/// `TagRepository` needs this vocabulary too, and Law L12 forbids `domain/` importing anything
/// from `data/` — so a scope type defined next to the DAO would either force an L12 violation or
/// a duplicated enum with a mapping function between the two. `core/` is the one layer both sides
/// may import.
enum TagScope {
  /// The deposit editor's tag picker.
  deposit,

  /// The withdrawal editor's tag picker.
  withdrawal,

  /// The inventory item editor's tag picker.
  inventory,

  /// The shopping list's group headers.
  shopping,

  /// The recurring template editor's tag picker.
  recurring,

  /// The service manager's tag picker.
  service,
}
```

### `lib/core/ids/uid.dart`

```dart
import 'package:uuid/uuid.dart' as pkg_uuid;

/// Generates the identifiers used for every table's `TEXT` primary key (Law L5). Injected
/// wherever an id is created so tests can substitute a deterministic generator.
abstract interface class UidGenerator {
  /// A new, globally unique identifier.
  String generate();
}

/// The production [UidGenerator]: RFC 9562 UUIDv7, time-ordered so rows created later sort
/// after rows created earlier even without an extra `createdAt` index.
final class Uuid7Generator implements UidGenerator {
  /// Creates a generator backed by `package:uuid`.
  const Uuid7Generator();

  static const pkg_uuid.Uuid _uuid = pkg_uuid.Uuid();

  @override
  String generate() => _uuid.v7();
}

/// A deterministic [UidGenerator] for tests: returns `prefix-0`, `prefix-1`, ... in call
/// order, so fixtures and assertions can reference ids without reading generated values.
final class SequentialUidGenerator implements UidGenerator {
  /// Creates a generator whose ids are `'$prefix-$n'` for an incrementing counter `n`.
  SequentialUidGenerator({this.prefix = 'test'});

  /// The fixed prefix used for every generated id.
  final String prefix;

  int _next = 0;

  @override
  String generate() => '$prefix-${_next++}';
}
```

### `lib/core/logging/logger.dart`

```dart
import 'dart:developer' as developer;

/// Severity levels for [Logger] output, ordered from least to most severe.
enum LogLevel {
  /// Verbose, developer-only detail.
  debug,

  /// Routine, expected events.
  info,

  /// Something unexpected happened but the app can continue normally.
  warning,

  /// An operation failed and could not recover on its own.
  error,
}

/// A minimal, injectable logging facade so call sites never depend on `dart:developer`
/// directly, and tests can capture or silence output.
abstract interface class Logger {
  /// Records [message] at [level], with an optional [error]/[stackTrace] pair and a [tag]
  /// identifying which subsystem logged it.
  void log(
      String message, {
        LogLevel level = LogLevel.info,
        String? tag,
        Object? error,
        StackTrace? stackTrace,
      });
}

/// The production [Logger]: writes to `dart:developer`'s `log()`, so output is visible in
/// DevTools and `flutter logs` without adding a third-party logging package.
final class DeveloperLogger implements Logger {
  /// Creates a logger that writes via `dart:developer`.
  const DeveloperLogger();

  @override
  void log(
      String message, {
        LogLevel level = LogLevel.info,
        String? tag,
        Object? error,
        StackTrace? stackTrace,
      }) {
    developer.log(
      message,
      name: tag ?? 'alaya',
      level: _severity(level),
      error: error,
      stackTrace: stackTrace,
    );
  }

  static int _severity(LogLevel level) => switch (level) {
    LogLevel.debug => 500,
    LogLevel.info => 800,
    LogLevel.warning => 900,
    LogLevel.error => 1000,
  };
}

/// A [Logger] that discards everything. Useful as a default in tests that don't care about
/// log output but still need to inject something.
final class NoopLogger implements Logger {
  /// Creates a logger that discards everything it's given.
  const NoopLogger();

  @override
  void log(
      String message, {
        LogLevel level = LogLevel.info,
        String? tag,
        Object? error,
        StackTrace? stackTrace,
      }) {}
}
```

### `lib/core/money/money.dart`

```dart
import 'dart:math' as math;

import 'rounding.dart';

/// An exact monetary amount: integer minor units (e.g. paise, cents) plus a currency code.
/// Never backed by a `double` (Law L1). This type deliberately does not know how many
/// decimal digits its own currency uses — that comes from the `currencies` table at the
/// call site (never hardcode `100`; see ARCH_1 §4.1) — so every operation that needs to
/// interpret [minor] as a decimal amount takes `decimalDigits` as an explicit parameter.
final class Money implements Comparable<Money> {
  /// Creates a [Money] directly from already-computed minor units. Prefer [MoneyParser] to
  /// build one from user-typed text.
  const Money(this.minor, this.currencyCode);

  /// A zero amount in [currencyCode].
  const Money.zero(String currencyCode) : this(0, currencyCode);

  /// The amount in minor units (e.g. paise, cents). Always a whole number.
  final int minor;

  /// The currency code, e.g. `'INR'`. Matches a row in the `currencies` table.
  final String currencyCode;

  /// True if [minor] is less than zero.
  bool get isNegative => minor < 0;

  /// True if [minor] is greater than zero.
  bool get isPositive => minor > 0;

  /// True if [minor] is exactly zero.
  bool get isZero => minor == 0;

  /// Adds [other]. Throws [CurrencyMismatchError] if the currencies differ.
  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(minor + other.minor, currencyCode);
  }

  /// Subtracts [other]. Throws [CurrencyMismatchError] if the currencies differ.
  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(minor - other.minor, currencyCode);
  }

  /// Scales this amount by the integer [factor].
  Money operator *(int factor) => Money(minor * factor, currencyCode);

  /// The negation of this amount, in the same currency.
  Money operator -() => Money(-minor, currencyCode);

  /// The absolute value of this amount, in the same currency.
  Money abs() => isNegative ? -this : this;

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return minor.compareTo(other.minor);
  }

  /// True if this amount is strictly less than [other]. Throws [CurrencyMismatchError] if
  /// the currencies differ.
  bool operator <(Money other) {
    _assertSameCurrency(other);
    return minor < other.minor;
  }

  /// True if this amount is less than or equal to [other]. Throws [CurrencyMismatchError]
  /// if the currencies differ.
  bool operator <=(Money other) {
    _assertSameCurrency(other);
    return minor <= other.minor;
  }

  /// True if this amount is strictly greater than [other]. Throws [CurrencyMismatchError]
  /// if the currencies differ.
  bool operator >(Money other) {
    _assertSameCurrency(other);
    return minor > other.minor;
  }

  /// True if this amount is greater than or equal to [other]. Throws [CurrencyMismatchError]
  /// if the currencies differ.
  bool operator >=(Money other) {
    _assertSameCurrency(other);
    return minor >= other.minor;
  }

  /// Converts this amount into [toCurrencyCode] using [rate] (units of [toCurrencyCode] per
  /// 1 unit of this currency), accounting for each currency's own decimal precision. This is
  /// the one sanctioned place in the app that rounds money; [rounding] defaults to
  /// [MoneyRounding.halfUp]. The result is a frozen, independent [Money] — this call never
  /// mutates `this` (Law L9: the original amount is immutable).
  Money convert({
    required double rate,
    required String toCurrencyCode,
    required int fromDecimalDigits,
    required int toDecimalDigits,
    MoneyRounding rounding = MoneyRounding.halfUp,
  }) {
    final scale = math.pow(10, toDecimalDigits - fromDecimalDigits).toDouble();
    final rawValue = minor * rate * scale;
    return Money(rounding.apply(rawValue), toCurrencyCode);
  }

  /// Splits this amount into parts proportional to [weights], losing nothing.
  ///
  /// **The parts always sum to exactly this amount.** That guarantee is the entire point:
  /// ₹1,000 shared three ways is not ₹333.33 three times, and an app that shows three equal
  /// thirds has quietly lost two paise that somebody is owed. Here it is
  /// `[₹333.34, ₹333.33, ₹333.33]`, and the sum is ₹1,000.
  ///
  /// **This is not a second rounding site.** [convert] documents itself as the one sanctioned
  /// place that rounds money, and that stays true: nothing here is rounded. Allocation
  /// *distributes* an exact integer across parts by the largest-remainder method — every minor
  /// unit of the input lands in exactly one part, and none is created or discarded. There is no
  /// [MoneyRounding] parameter because there is no rounding decision to make.
  ///
  /// The leftover units go to the parts with the largest fractional remainders, ties broken by
  /// position, so the same weights always produce the same answer. Determinism matters more than
  /// it looks: a split shown to a user and the same split recomputed on the next screen must
  /// assign the stray paise to the same person, or the two screens disagree about who owes what.
  ///
  /// A weight of `0` yields exactly `Money.zero` and **never** receives a leftover unit — the
  /// guest who did not eat pays nothing. That holds because the leftover count is always strictly
  /// less than the number of parts with a non-zero remainder, so the sort never reaches a zero.
  ///
  /// Negative amounts are allocated by magnitude and then negated, so splitting a refund behaves
  /// as splitting a charge does.
  ///
  /// Throws [ArgumentError] when [weights] is empty, contains a negative, or sums to zero — each
  /// is a programming error rather than a state a user can reach.
  List<Money> allocate(List<int> weights) {
    if (weights.isEmpty) {
      throw ArgumentError.value(weights, 'weights', 'must not be empty');
    }
    var totalWeight = 0;
    for (final weight in weights) {
      if (weight < 0) {
        throw ArgumentError.value(weight, 'weights', 'must not be negative');
      }
      totalWeight += weight;
    }
    if (totalWeight == 0) {
      throw ArgumentError.value(
        weights,
        'weights',
        'must not all be zero — there would be nothing to allocate against',
      );
    }

    // Allocated by magnitude, then re-signed. A refund split behaves as a charge split, and the
    // largest-remainder comparison stays a comparison of positive fractions.
    final negative = isNegative;
    final magnitude = negative ? -minor : minor;

    final parts = List<int>.filled(weights.length, 0);
    final remainders = List<int>.filled(weights.length, 0);
    var distributed = 0;
    for (var i = 0; i < weights.length; i++) {
      // Multiply before dividing so the integer division loses nothing recoverable (Law L1).
      // 64-bit headroom is ample: the largest realistic amount times the largest basis-point
      // weight is around 1e16, against a ceiling near 9.2e18.
      final numerator = magnitude * weights[i];
      parts[i] = numerator ~/ totalWeight;
      remainders[i] = numerator % totalWeight;
      distributed += parts[i];
    }

    // Each part lost strictly less than one unit to truncation, so the leftover is at least zero
    // and strictly less than the number of parts. It therefore always fits inside [order].
    final leftover = magnitude - distributed;
    assert(
      leftover >= 0 && leftover < weights.length,
      'largest-remainder leftover out of range: $leftover for ${weights.length} parts',
    );

    final order = List<int>.generate(weights.length, (i) => i)
      ..sort((a, b) {
        final byRemainder = remainders[b].compareTo(remainders[a]);
        return byRemainder != 0 ? byRemainder : a.compareTo(b);
      });
    for (var given = 0; given < leftover; given++) {
      parts[order[given]] += 1;
    }

    return [
      for (final part in parts) Money(negative ? -part : part, currencyCode),
    ];
  }

  /// Splits this amount into [parts] equal shares, losing nothing.
  ///
  /// Shorthand for [allocate] with equal weights, and it carries the same guarantee: the shares
  /// sum to exactly this amount, with the leftover units going to the earliest parts.
  ///
  /// Throws [ArgumentError] when [parts] is not positive.
  List<Money> allocateEvenly(int parts) {
    if (parts <= 0) {
      throw ArgumentError.value(parts, 'parts', 'must be greater than zero');
    }
    return allocate(List<int>.filled(parts, 1));
  }

  void _assertSameCurrency(Money other) {
    if (other.currencyCode != currencyCode) {
      throw CurrencyMismatchError(currencyCode, other.currencyCode);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minor == minor &&
      other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(minor, currencyCode);

  /// A debug-only representation, e.g. `INR 12345mu`. Never use this for UI display — use
  /// [MoneyFormatter] instead.
  @override
  String toString() => '$currencyCode ${minor}mu';
}

/// Thrown when an operation combines two [Money] values in different currencies. There is
/// no implicit conversion anywhere in this type — indicates a programming error, not a
/// recoverable user-facing condition.
final class CurrencyMismatchError extends Error {
  /// Records the two currency codes that could not be combined.
  CurrencyMismatchError(this.first, this.second);

  /// The currency code of the left-hand operand.
  final String first;

  /// The currency code of the right-hand operand.
  final String second;

  @override
  String toString() =>
      'CurrencyMismatchError: cannot combine $first with $second directly '
      '— convert explicitly first.';
}
```

### `lib/core/money/money_formatter.dart`

```dart
import 'package:intl/intl.dart';

import 'money.dart';

/// Renders [Money] as a locale-correct display string, including digit grouping. Deliberately
/// does not delegate grouping to `intl`'s `NumberFormat`: that class only supports a single,
/// uniform group size, so it cannot produce Indian lakh/crore grouping (2-2-3 digits) —
/// see dart-lang/i18n#349, an open feature request for exactly this. Instead, this formatter
/// uses `NumberFormat` only to look up which characters a locale uses as its decimal point
/// and group separator, and performs the actual digit grouping itself with exact integer and
/// string operations (never a `double`, consistent with Law L1). A purely display-layer
/// concern: it never mutates or rounds the underlying integer minor units.
final class MoneyFormatter {
  /// Creates a formatter. Stateless — safe to use as a `const` singleton.
  const MoneyFormatter();

  /// Separates the currency symbol from the digits: `INR 5,000.00`, not `INR5000.00`.
  ///
  /// An ISO code run hard against a number reads as one token — `INR5000` invites a glance to parse the `5`
  /// as part of the code. A symbol like `₹` does not have that problem, which is why the convention differs
  /// between them, but this app defaults [format]'s `symbol` to the ISO code and so needs the gap.
  ///
  /// **An ordinary space, not U+00A0.** A non-breaking space would be more correct typographically, and is
  /// the wrong trade here: it is invisible in a diff, invisible in a `grep`, and would make
  /// `find.text('INR 5,000.00')` fail in a way whose cause is not visible on screen. `AmountText` sets
  /// `maxLines: 1`, so there is no wrap for a non-breaking space to prevent — it would buy nothing and cost
  /// a class of silent test failure.
  static const String symbolGap = ' ';

  /// Formats [money] for display. [decimalDigits] and [symbol] must come from the
  /// `currencies` table (never hardcoded — see ARCH_1 §4.1); [localeTag] controls only
  /// digit grouping and the decimal separator character.
  String format(
    Money money, {
    required int decimalDigits,
    required String symbol,
    String localeTag = 'en_IN',
    bool showPlusSign = false,
  }) {
    final magnitude = money.minor.abs();
    final divisor = _pow10(decimalDigits);
    final whole = magnitude ~/ divisor;
    final frac = magnitude % divisor;

    final symbols = NumberFormat.decimalPattern(localeTag).symbols;
    final groupedWhole = _groupDigits(
      whole.toString(),
      groupSeparator: symbols.GROUP_SEP,
      useIndianGrouping: _isIndianLocale(localeTag),
    );

    final fracStr = decimalDigits == 0
        ? ''
        : '${symbols.DECIMAL_SEP}${frac.toString().padLeft(decimalDigits, '0')}';

    final sign = money.isNegative
        ? '-'
        : (showPlusSign && money.isPositive ? '+' : '');

    return '$sign$symbol$symbolGap$groupedWhole$fracStr';
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  /// True for locales whose region subtag is India, which use 2-2-3 grouping (lakh/crore)
  /// rather than the 3-3-3 grouping most other locales use.
  static bool _isIndianLocale(String localeTag) {
    final region = localeTag.split(RegExp('[_-]')).last.toUpperCase();
    return region == 'IN';
  }

  /// Groups [digits] (a plain non-negative integer string) into the target locale's scheme:
  /// a final group of 3 digits, then repeating groups of 2 (Indian) or 3 (Western) moving
  /// left, joined by [groupSeparator].
  static String _groupDigits(
    String digits, {
    required String groupSeparator,
    required bool useIndianGrouping,
  }) {
    if (groupSeparator.isEmpty || digits.length <= 3) return digits;

    final secondaryGroupSize = useIndianGrouping ? 2 : 3;
    final primaryGroup = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);

    final groups = <String>[];
    while (rest.length > secondaryGroupSize) {
      groups.insert(0, rest.substring(rest.length - secondaryGroupSize));
      rest = rest.substring(0, rest.length - secondaryGroupSize);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    groups.add(primaryGroup);

    return groups.join(groupSeparator);
  }
}
```

### `lib/core/money/money_parser.dart`

```dart
import 'package:intl/intl.dart';

import '../result/failure.dart';
import '../result/result.dart';
import 'money.dart';

/// Parses user-typed monetary text into [Money], honouring locale-specific decimal and
/// grouping separators. Never throws — every outcome, including a still-being-typed or
/// malformed string, comes back as a [Result] so the UI can decide how to react instead of
/// crashing. Converts the decimal text to minor units using exact string/integer
/// manipulation only; a `double` is never involved (Law L1), which also means this parser
/// never silently rounds a typed value — a currency's precision is enforced by rejecting
/// extra digits (see [ParseFailure.tooManyDecimalDigits]), not by discarding them.
final class MoneyParser {
  /// Creates a parser. Stateless — safe to use as a `const` singleton.
  const MoneyParser();

  static const int _maxInputLength = 24;

  /// Parses [input] as an amount in [currencyCode] with [decimalDigits] decimal places.
  /// [localeTag] (e.g. `'en_IN'`, `'de_DE'`) determines which characters are the decimal
  /// point and the grouping separator. Negative input is rejected unless [allowNegative].
  Result<Money, ParseFailure> parse(
      String input, {
        required String currencyCode,
        required int decimalDigits,
        String localeTag = 'en',
        bool allowNegative = false,
      }) {
    var text = input.trim();
    if (text.isEmpty) return const Result.failure(ParseFailure.empty);
    if (text.length > _maxInputLength) return const Result.failure(ParseFailure.tooLarge);

    var sign = 1;
    if (text.startsWith('-')) {
      if (!allowNegative) return const Result.failure(ParseFailure.negativeNotAllowed);
      sign = -1;
      text = text.substring(1);
    } else if (text.startsWith('+')) {
      text = text.substring(1);
    }
    if (text.isEmpty) return const Result.failure(ParseFailure.malformed);

    final symbols = NumberFormat.decimalPattern(localeTag).symbols;
    final groupSep = symbols.GROUP_SEP;
    final decimalSep = symbols.DECIMAL_SEP;

    if (groupSep.isNotEmpty) {
      text = text.replaceAll(groupSep, '');
    }
    if (text.isEmpty) return const Result.failure(ParseFailure.malformed);

    final decimalParts = decimalSep.isEmpty ? [text] : text.split(decimalSep);
    if (decimalParts.length > 2) return const Result.failure(ParseFailure.malformed);

    final wholePart = decimalParts[0];
    final fracPart = decimalParts.length == 2 ? decimalParts[1] : '';

    if (wholePart.isEmpty && fracPart.isEmpty) {
      return const Result.failure(ParseFailure.malformed);
    }
    if (!_isDigitsOnly(wholePart) || !_isDigitsOnly(fracPart)) {
      return const Result.failure(ParseFailure.invalidCharacter);
    }
    if (fracPart.length > decimalDigits) {
      return const Result.failure(ParseFailure.tooManyDecimalDigits);
    }

    final paddedFrac = fracPart.padRight(decimalDigits, '0');
    final digitString = '${wholePart.isEmpty ? '0' : wholePart}$paddedFrac';
    final magnitude = int.parse(digitString);

    return Result.ok(Money(sign * magnitude, currencyCode));
  }

  static bool _isDigitsOnly(String value) {
    for (final codeUnit in value.codeUnits) {
      if (codeUnit < 0x30 || codeUnit > 0x39) return false;
    }
    return true;
  }
}
```

### `lib/core/money/rounding.dart`

```dart
/// Strategies for rounding a fractional minor-unit amount to an integer. Used only at the
/// single sanctioned rounding boundary in the app, [Money.convert] — nowhere else rounds
/// money (Law L1's spirit: the stored and returned amounts are always exact integers; only
/// a currency conversion, which multiplies by an inherently inexact market rate, ever needs
/// to round the result back down to one).
enum MoneyRounding {
  /// Rounds half away from zero (`2.5 → 3`, `-2.5 → -3`). The "school rounding" most people
  /// expect, and this app's default.
  halfUp,

  /// Rounds half toward zero (`2.5 → 2`, `-2.5 → -2`).
  halfDown,

  /// Rounds half to the nearest even integer (banker's rounding; `2.5 → 2`, `3.5 → 4`).
  halfEven,

  /// Always rounds toward positive infinity.
  ceiling,

  /// Always rounds toward negative infinity.
  floor;

  /// Rounds [value] to the nearest integer per this strategy.
  int apply(double value) => switch (this) {
    MoneyRounding.ceiling => value.ceil(),
    MoneyRounding.floor => value.floor(),
    MoneyRounding.halfUp =>
    value.isNegative ? -_halfUpMagnitude(-value) : _halfUpMagnitude(value),
    MoneyRounding.halfDown =>
    value.isNegative ? -_halfDownMagnitude(-value) : _halfDownMagnitude(value),
    MoneyRounding.halfEven => _halfEven(value),
  };

  static int _halfUpMagnitude(double magnitude) => (magnitude + 0.5).floor();

  static int _halfDownMagnitude(double magnitude) {
    final flooredValue = magnitude.floor();
    final fraction = magnitude - flooredValue;
    return fraction > 0.5 ? flooredValue + 1 : flooredValue;
  }

  static int _halfEven(double value) {
    final flooredValue = value.floor();
    final fraction = value - flooredValue;
    if (fraction < 0.5) return flooredValue;
    if (fraction > 0.5) return flooredValue + 1;
    return flooredValue.isEven ? flooredValue : flooredValue + 1;
  }
}
```

### `lib/core/quantity/fraction.dart`

```dart
/// Exact fractions, and the vocabulary a kitchen drawer actually contains.
library;

/// An exact, reduced, non-negative fraction.
///
/// **A separate type from a `double` because Law L1 has no doubles anywhere.** A fraction here is two
/// integers and stays two integers; the only place it becomes an approximation is [milliOfUnit], where
/// it is quantised to thousandths on purpose and the quantisation is the thing this file exists to make
/// visible rather than to hide.
final class Fraction implements Comparable<Fraction> {
  /// A fraction that is already reduced. Library-private so no unreduced instance can exist.
  const Fraction._(this.numerator, this.denominator);

  /// Creates the reduced form of `numerator / denominator`.
  ///
  /// Reduces, so `Fraction(2, 4)` and `Fraction(1, 2)` are the same value and compare equal — which
  /// matters because the approximation search below finds `2/4` before it would find `1/2` for some
  /// inputs, and a reader shown "2/4 cup" would rightly wonder what the app was doing.
  factory Fraction(int numerator, int denominator) {
    if (denominator <= 0) {
      throw ArgumentError.value(denominator, 'denominator', 'must be positive');
    }
    if (numerator < 0) {
      throw ArgumentError.value(numerator, 'numerator', 'must not be negative');
    }
    if (numerator == 0) return zero;
    final divisor = _gcd(numerator, denominator);
    return Fraction._(numerator ~/ divisor, denominator ~/ divisor);
  }

  /// Zero, as `0/1`.
  static const Fraction zero = Fraction._(0, 1);

  /// One, as `1/1`.
  static const Fraction one = Fraction._(1, 1);

  /// The top of the fraction.
  final int numerator;

  /// The bottom of the fraction. Always positive, always coprime with [numerator].
  final int denominator;

  /// True when this is exactly zero.
  bool get isZero => numerator == 0;

  /// True when this is a whole number — `1/1`, `2/1`.
  bool get isWhole => denominator == 1;

  /// This fraction in thousandths, rounded half up.
  ///
  /// **The lossy step, and it is deliberate.** A thousandth of a teaspoon is five thousandths of a
  /// millilitre, which no kitchen can measure, so quantising here costs nothing real and buys integer
  /// arithmetic end to end. `1/3` becomes 333 and `1/16` becomes 63; both round-trip back to the same
  /// fraction through [fractionForMilli], which is the property that matters.
  int get milliOfUnit => roundDiv(numerator * 1000, denominator);

  @override
  int compareTo(Fraction other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);

  @override
  bool operator ==(Object other) =>
      other is Fraction &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  /// `1/2`, `3/4`. ASCII on purpose — see `MeasureFormatter` for why output is not `½`.
  @override
  String toString() => '$numerator/$denominator';

  static int _gcd(int a, int b) {
    var x = a;
    var y = b;
    while (y != 0) {
      final next = x % y;
      x = y;
      y = next;
    }
    return x == 0 ? 1 : x;
  }
}

/// Integer division rounded half up. Positive operands only.
///
/// **Half up, never truncating.** ARCH_M §7 records the failure this prevents: half a tablespoon is
/// 7393.5 milli-millilitres, and truncating on the way back gave 499 rather than 500 — so a field
/// showed `0.499` and a chip never lit. Every division in this file and in `Measure` goes through here
/// so there is one rounding rule rather than one per call site.
int roundDiv(int numerator, int denominator) =>
    (numerator + denominator ~/ 2) ~/ denominator;

/// The fractions a measuring set can actually produce.
///
/// **A human fact, not a derivable one.** It cannot be computed from the `units` table: a tablespoon's
/// factor of 14787 is divisible by 3 and not by 2, which would offer thirds and refuse halves — the
/// opposite of what is in the drawer. So this is a stated list, and stating it is more honest than
/// deriving something plausible from the wrong input.
///
/// Six, being the union of a spoon set (quarter, half) and a cup set (quarter, third, half, two
/// thirds, three quarters), plus the eighth that a half-of-a-quarter teaspoon gives you. Eighths like
/// `3/8` are reachable by typing and deliberately not offered here: "5/8 cup" is a worse sentence than
/// "2/3 cup" and a cook reading it has to think.
const List<Fraction> kMeasuringSet = [
  Fraction._(1, 8),
  Fraction._(1, 4),
  Fraction._(1, 3),
  Fraction._(1, 2),
  Fraction._(2, 3),
  Fraction._(3, 4),
];

/// The simplest fraction that would have been stored as exactly [milli] thousandths.
///
/// **The round trip is the acceptance test, and that is the whole idea.** Rather than a table of known
/// thousandths — the previous approach, which held nine entries and rendered anything else as a decimal
/// — a candidate `p/q` is accepted if and only if `Fraction(p, q).milliOfUnit == milli`. So the question
/// "is this a fraction?" becomes "could this have come from one?", which is exactly the property a user
/// cares about: they typed `2/3`, and `2/3` is what they should be shown.
///
/// Denominators are tried in ascending order, so the first match is the simplest: `500` returns `1/2`
/// rather than `2/4`, and `250` returns `1/4` rather than `3/12`.
///
/// [milli] must be a remainder — strictly between 0 and 1000. Whole parts are [Measure]'s business.
/// Returns null when nothing within [maxDenominator] round-trips, and a null is a real answer: `137`
/// thousandths is not any simple fraction, and rendering it as `2/15` would be a worse lie than
/// rendering it as `0.137`.
///
/// [maxDenominator] defaults to 16 because that is the finest gradation any kitchen tool has. Above it
/// the answers stop being useful before they stop being correct — nobody owns a nineteenth of a cup.
Fraction? fractionForMilli(int milli, {int maxDenominator = 16}) {
  if (milli <= 0 || milli >= 1000) return null;
  for (var denominator = 2; denominator <= maxDenominator; denominator++) {
    final numerator = roundDiv(milli * denominator, 1000);
    if (numerator <= 0 || numerator >= denominator) continue;
    if (roundDiv(numerator * 1000, denominator) != milli) continue;
    return Fraction(numerator, denominator);
  }
  return null;
}

/// The nearest thousandths value a measuring set can produce, and whether snapping changed anything.
///
/// **Ties round up**, matching `CookabilityEngine.scaleMilli`'s direction and for the same reason it
/// gives: overstating an amount is a shrug and understating one ruins the dish. A cook told to use a
/// little more flour adds a little more flour.
///
/// [milli] must be a remainder — strictly between 0 and 1000 — or zero. A snap to 1000 means the
/// remainder became a whole unit, and the caller carries it.
({int milli, bool changed}) snapRemainderToMeasuringSet(int milli) {
  if (milli <= 0) return (milli: 0, changed: false);
  var best = 0;
  var bestDistance = milli;
  for (final candidate in [
    0,
    for (final fraction in kMeasuringSet) fraction.milliOfUnit,
    1000,
  ]) {
    final distance = (candidate - milli).abs();
    // `<=` rather than `<`, so a tie is won by the later — and therefore larger — candidate.
    if (distance <= bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return (milli: best, changed: best != milli);
}
```

### `lib/core/quantity/measure.dart`

```dart
import 'fraction.dart';
import 'qty.dart';
import 'unit_category.dart';

/// An amount expressed in thousandths of some chosen unit — half a tablespoon, two thirds of a cup.
///
/// **The missing middle of the recipe module.** A [Qty] is canonical and unit-free: half a tablespoon is
/// `Qty(7393, volume)`, which is correct, comparable, and unable to say what the cook wrote. The unit
/// they chose is stored separately, and until this type existed there was nothing that held the two
/// together — so the editor kept the pairing in local widget state and the detail screen, having no
/// pairing to read, rendered `7 ml` for a line that said half a tablespoon.
///
/// **Thousandths rather than a [Fraction], and the choice is load-bearing.** A fraction is exact but
/// only closed under multiplication by other fractions; the moment servings scale an amount by 2/3 and
/// the engine takes a ceiling, the result is not a fraction of anything in a drawer. Thousandths absorb
/// that — every arithmetic result is representable, and `MeasureFormatter` decides afterwards whether
/// what came out can be *called* a fraction. Representation stays total; presentation does the judging.
///
/// **No unit lives here.** `Unit` is a domain entity and `B1_CORE` depends on nothing (Law L12), so
/// every conversion takes the raw `factorToBaseMilli` from the `units` row. That is not a workaround —
/// it is what keeps this arithmetic testable with three integer literals and no database.
final class Measure implements Comparable<Measure> {
  /// Creates a measure of [milliOfUnit] thousandths of a unit. `1500` is one and a half.
  const Measure(this.milliOfUnit);

  /// Nothing.
  const Measure.zero() : milliOfUnit = 0;

  /// [whole] units plus [fraction] of one.
  ///
  /// The shape a cook dictates: a number, then a fraction. "3 1/2 tablespoons" is three tablespoons and
  /// then the half, which is literally the sequence of actions at the counter.
  factory Measure.of(int whole, [Fraction? fraction]) =>
      Measure(whole * 1000 + (fraction?.milliOfUnit ?? 0));

  /// Re-expresses [quantity] in the unit whose factor is [factorToBaseMilli].
  ///
  /// **Rounded, not truncated** (ARCH_M §7). Half a tablespoon is 7393.5 milli-millilitres; truncating
  /// on the way back gives 499 rather than 500, so the field showed `0.499` and the fraction chip never
  /// lit. That bug was reported as a missing feature.
  factory Measure.fromQty(Qty quantity, {required int factorToBaseMilli}) {
    if (factorToBaseMilli <= 0) {
      throw ArgumentError.value(
        factorToBaseMilli,
        'factorToBaseMilli',
        'must be positive',
      );
    }
    return Measure(roundDiv(quantity.milliBase * 1000, factorToBaseMilli));
  }

  /// Thousandths of the chosen unit.
  final int milliOfUnit;

  /// The whole part — the `3` in `3 1/2`.
  int get whole => milliOfUnit ~/ 1000;

  /// The leftover thousandths — the `500` in `3 1/2`.
  int get remainderMilli => milliOfUnit % 1000;

  /// True when there is nothing to measure.
  bool get isZero => milliOfUnit <= 0;

  /// True when this is a whole number of units, with nothing left over.
  bool get isWhole => remainderMilli == 0;

  /// Converts to the canonical [Qty] the engine and the database use.
  ///
  /// Rounded in this direction too, so [Measure.fromQty] undoes it. That round trip is exact for every
  /// unit whose factor is at least 1000 — which is every unit in the seed, the smallest being `mg` at 1
  /// and every vessel being far larger: `tsp` 4929, `tbsp` 14787, `cup` 240000.
  Qty toQty({
    required int factorToBaseMilli,
    required UnitCategory category,
  }) => Qty(roundDiv(milliOfUnit * factorToBaseMilli, 1000), category);

  /// The nearest amount a measuring set can produce, carrying a full unit if the snap reaches one.
  ///
  /// **For a derived amount only.** At a recipe's own serving count an amount is what the cook typed and
  /// needs no snapping; it is scaling that produces 222 thousandths of a cup, which is a real number and
  /// not a thing anybody owns a scoop for. `MeasureFormatter` is what decides when to call this, and it
  /// marks the result so the screen never claims a snapped amount is the stored one.
  Measure snapToMeasuringSet() {
    final snapped = snapRemainderToMeasuringSet(remainderMilli);
    if (!snapped.changed) return this;
    return Measure(whole * 1000 + snapped.milli);
  }

  /// A copy with the whole part replaced, keeping the fraction.
  ///
  /// Clearing the number keeps the fraction, because "1/2 tsp" is a real amount and deleting the zero in
  /// front of it should not delete the half as well.
  Measure withWhole(int value) => Measure(value * 1000 + remainderMilli);

  /// A copy with the fraction replaced, keeping the whole part.
  ///
  /// Passing null clears the fraction, so `3 1/2` and `3` are one tap apart in both directions.
  Measure withFraction(Fraction? fraction) =>
      Measure(whole * 1000 + (fraction?.milliOfUnit ?? 0));

  /// This measure scaled from [fromServings] to [toServings].
  ///
  /// **Delegates the direction to the engine's rule rather than restating it.** `CookabilityEngine`
  /// takes a ceiling because a false "you have enough" ruins dinner. A display that rounded the other
  /// way would show less than the verdict demands, and the two disagreeing about the same recipe is the
  /// class of bug this whole type exists to close — so this rounds up too, and the arithmetic is here
  /// only because `B1_CORE` cannot import a domain service.
  Measure scaled({required int fromServings, required int toServings}) {
    if (fromServings <= 0) {
      throw ArgumentError.value(
        fromServings,
        'fromServings',
        'must be positive',
      );
    }
    if (toServings == fromServings) return this;
    final numerator = milliOfUnit * toServings;
    return Measure((numerator + fromServings - 1) ~/ fromServings);
  }

  @override
  int compareTo(Measure other) => milliOfUnit.compareTo(other.milliOfUnit);

  @override
  bool operator ==(Object other) =>
      other is Measure && other.milliOfUnit == milliOfUnit;

  @override
  int get hashCode => milliOfUnit.hashCode;

  /// Debug only. Never show this to anybody — use `MeasureFormatter`.
  @override
  String toString() => '${milliOfUnit}m/unit';
}
```

### `lib/core/quantity/measure_formatter.dart`

```dart
import 'package:intl/intl.dart';

import 'fraction.dart';
import 'measure.dart';

/// Which question a rendered measure is answering.
///
/// The two exist because the answers genuinely differ, and conflating them is how a screen ends up
/// asserting something false. See [MeasureStyle.kitchen].
enum MeasureStyle {
  /// What the amount *is*.
  ///
  /// Renders a fraction when one would have stored as exactly this value, and a decimal otherwise. Used
  /// wherever the amount is the one the cook typed — the editor, and any row shown at the recipe's own
  /// serving count. Never approximates, so `RenderedMeasure.isApproximate` is always false.
  exact,

  /// What the cook should *reach for*.
  ///
  /// Snaps to [kMeasuringSet], so 222 thousandths of a cup reads as a quarter cup rather than as `2/9` —
  /// which is the honest fraction, and useless, because no drawer contains a ninth.
  ///
  /// **Only for a derived amount, and always marked.** Snapping means the text no longer equals the
  /// stored value, and a screen that showed the snapped figure as though it were the real one would be
  /// telling the same kind of lie the reminders screen told for months: internally consistent, plausible,
  /// and wrong. `RenderedMeasure.isApproximate` is how the caller knows to say so.
  kitchen,
}

/// A measure ready to display, and enough for the caller to be honest about it.
final class RenderedMeasure {
  /// Creates a rendered measure.
  const RenderedMeasure({
    required this.text,
    required this.whole,
    required this.fraction,
    required this.isApproximate,
    required this.measure,
  });

  /// What to show: `2`, `3/4`, `1 1/2`, or `0.137` when nothing simpler fits.
  final String text;

  /// The whole part, for a caller that wants to lay the two out separately.
  final int whole;

  /// The fractional part, or null when the amount is whole or has no simple fraction.
  final Fraction? fraction;

  /// True when [text] is not the stored amount.
  ///
  /// **The caller must show this**, conventionally as a leading `≈`. One character is the whole cost of
  /// not lying, and it appears only when snapping actually changed something — so at a recipe's own
  /// serving count no glyph appears anywhere, and the moment the servings dial moves it earns its place.
  final bool isApproximate;

  /// The value [text] describes. Equals the input under [MeasureStyle.exact]; the snapped value under
  /// [MeasureStyle.kitchen]. Kept so a caller can show the exact figure alongside, or in a tooltip.
  final Measure measure;
}

/// Renders a [Measure] the way a cook writes it.
///
/// **Replaces a nine-entry lookup table, and the table was the ceiling.** The previous renderer knew
/// `1/8` through `7/8` and rendered everything else as a decimal — so a chip list of five fractions was
/// never the real limit, and adding `1/16` to it would have produced `0.062` on screen. Recognition is
/// now derived: a fraction is offered when it round-trips, which needs no table and no additions.
///
/// **ASCII output, deliberately.** `1/2` rather than `½`. The vulgar-fraction characters are prettier and
/// a font that lacks one renders nothing at all — an amount that silently disappears is worse than an
/// amount that is merely plain, and this app ships one font family it does not control the coverage of.
/// `MeasureParser` accepts the glyphs on input, where the risk runs the other way.
final class MeasureFormatter {
  /// Creates a formatter. Stateless — safe to use as a `const` singleton.
  const MeasureFormatter({this.maxDenominator = 16});

  /// The finest gradation to offer as a fraction. See [fractionForMilli].
  final int maxDenominator;

  /// Renders [measure].
  ///
  /// [localeTag] affects only the decimal fallback's separator, matching `QtyFormatter`, because a
  /// fraction has no locale-dependent characters and the unit vocabulary is not this class's business.
  RenderedMeasure format(
    Measure measure, {
    MeasureStyle style = MeasureStyle.exact,
    String localeTag = 'en',
  }) {
    final target = style == MeasureStyle.kitchen
        ? measure.snapToMeasuringSet()
        : measure;
    final approximate = target != measure;

    if (target.isZero) {
      return RenderedMeasure(
        text: '0',
        whole: 0,
        fraction: null,
        isApproximate: approximate,
        measure: target,
      );
    }

    final fraction = fractionForMilli(
      target.remainderMilli,
      maxDenominator: maxDenominator,
    );

    // No fraction and a leftover: a real number that is not any simple fraction. `0.137` is the honest
    // rendering, and reaching for `2/15` to avoid a decimal would be inventing precision.
    if (fraction == null && !target.isWhole) {
      return RenderedMeasure(
        text: _decimal(target.milliOfUnit, localeTag),
        whole: target.whole,
        fraction: null,
        isApproximate: approximate,
        measure: target,
      );
    }

    final text = switch ((target.whole, fraction)) {
      (final whole, null) => '$whole',
      (0, final Fraction f) => '$f',
      (final whole, final Fraction f) => '$whole $f',
    };

    return RenderedMeasure(
      text: text,
      whole: target.whole,
      fraction: fraction,
      isApproximate: approximate,
      measure: target,
    );
  }

  /// The chips to offer for [current].
  ///
  /// **[kMeasuringSet] plus whatever is already set, which is how a custom fraction becomes a chip.**
  /// Somebody who types `5/16` gets a lit `5/16` chip they can tap to clear, without a "custom" button, a
  /// picker, or anything remembered between sessions. The set is the drawer plus the present tense.
  ///
  /// Returns the drawer alone when [current] has no fraction, or when its fraction is already in it.
  List<Fraction> chipsFor(Measure current) {
    final fraction = fractionForMilli(
      current.remainderMilli,
      maxDenominator: maxDenominator,
    );
    if (fraction == null || kMeasuringSet.contains(fraction)) {
      return kMeasuringSet;
    }
    return [...kMeasuringSet, fraction]..sort();
  }

  String _decimal(int milliOfUnit, String localeTag) {
    final format = NumberFormat.decimalPattern(localeTag)
      ..minimumFractionDigits = 0
      ..maximumFractionDigits = 3;
    // Constructed from integers and formatted immediately: the double exists for the length of this
    // expression and never reaches a stored value, which is the only place Law L1 permits one.
    return format.format(milliOfUnit / 1000);
  }
}
```

### `lib/core/quantity/measure_parser.dart`

```dart
import '../result/failure.dart';
import '../result/result.dart';
import 'fraction.dart';
import 'measure.dart';
import 'unit_converter.dart';

/// Parses the amounts cooks actually write.
///
/// **A sibling of [QtyParser], not a replacement, and the split is the point.** `QtyParser` refuses to
/// round: `0.5` of a teaspoon returns [ParseFailure.tooManyDecimalDigits], because 4929 is not divisible
/// by two and its contract is to never silently discard typed precision. That is correct for inventory,
/// where a recorded quantity is a fact about a shelf. It is wrong for a recipe, where "half a teaspoon"
/// is the most ordinary instruction in cooking and no cook is asserting 2.4645 millilitres.
///
/// So quantities stay exact and measures are allowed to approximate, and each has its own parser saying
/// so in its type. The alternative — relaxing `QtyParser` — would have made every inventory call site
/// quietly lossy to fix a recipe screen.
///
/// **The decimal path delegates to [UnitConverter].** That class already parses a locale-formatted
/// decimal into integer thousandths with half-up rounding and no rejection, and until this file it had no
/// callers anywhere — built, documented, and unreachable, which is `tool/reachability.py`'s whole subject.
/// Reusing it means one rounding implementation rather than a second one that drifts.
final class MeasureParser {
  /// Creates a parser. Stateless — safe to use as a `const` singleton.
  const MeasureParser();

  static const UnitConverter _decimals = UnitConverter();
  static const int _maxInputLength = 24;

  /// Thousandths per whole unit. [UnitConverter] converts into "milli of a thing"; passing 1000 as the
  /// factor makes that thing one unit, which is exactly [Measure]'s scale.
  static const int _milliPerUnit = 1000;

  /// Parses [input] into a [Measure].
  ///
  /// Accepted, all of which appear in real recipes:
  ///
  /// | Written | Means |
  /// |---|---|
  /// | `2`, `0.5`, `.5` | plain numbers, in the locale's own decimal separator |
  /// | `1/2`, `3/4`, `5/16` | any fraction |
  /// | `1 1/2`, `2 3/4` | a whole part and a fraction |
  /// | `½`, `⅔`, `⅜` | the vulgar-fraction characters a pasted recipe carries |
  /// | `1½`, `1 ½` | with or without the space |
  ///
  /// **Unicode fractions are accepted and never produced.** Reading them costs one lookup table and
  /// rescues every recipe pasted from a website. Writing them would risk a glyph the app's font does not
  /// carry, and `⅝` is invisible in a way that `5/8` cannot be — a rendering bug that looks like missing
  /// data. Input is generous, output is plain; see `MeasureFormatter`.
  Result<Measure, ParseFailure> parse(String input, {String localeTag = 'en'}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return const Result.failure(ParseFailure.empty);
    if (trimmed.length > _maxInputLength) {
      return const Result.failure(ParseFailure.tooLarge);
    }
    if (trimmed.startsWith('-')) {
      // A recipe cannot call for a negative amount, and the failure names the reason rather than
      // reporting a malformed number.
      return const Result.failure(ParseFailure.negativeNotAllowed);
    }

    final text = _expandVulgarFractions(trimmed);
    final parts = text.split(RegExp(r'\s+'));
    if (parts.length > 2) return const Result.failure(ParseFailure.malformed);

    if (parts.length == 2) {
      final whole = int.tryParse(parts.first);
      if (whole == null) return const Result.failure(ParseFailure.malformed);
      final fraction = _parseFraction(parts[1]);
      if (fraction == null) return const Result.failure(ParseFailure.malformed);
      return Result.ok(Measure.of(whole, fraction));
    }

    if (text.contains('/')) {
      final fraction = _parseFraction(text);
      return fraction == null
          ? const Result.failure(ParseFailure.malformed)
          : Result.ok(Measure(fraction.milliOfUnit));
    }

    final decimal = _decimals.parseToMilliBase(
      text,
      unitFactorMilliBase: _milliPerUnit,
      localeTag: localeTag,
    );
    return decimal.isOk
        ? Result.ok(Measure(decimal.valueOrNull ?? 0))
        : Result.failure(decimal.failureOrNull ?? ParseFailure.malformed);
  }

  /// `3/4` into a [Fraction], or null for anything that is not one.
  ///
  /// A denominator beyond 1000 is rejected rather than rounded to nothing: `1/5000` would quantise to
  /// zero thousandths, and silently reading a typed amount as "none" is worse than saying no.
  Fraction? _parseFraction(String text) {
    final parts = text.split('/');
    if (parts.length != 2) return null;
    final numerator = int.tryParse(parts.first.trim());
    final denominator = int.tryParse(parts[1].trim());
    if (numerator == null || denominator == null) return null;
    if (numerator < 0 || denominator <= 0 || denominator > 1000) return null;
    return Fraction(numerator, denominator);
  }

  /// Rewrites `1½` as `1 1/2` so one code path handles both spellings.
  ///
  /// A space is inserted when a digit precedes the glyph, because `1½` and `1 ½` are the same amount and
  /// splitting on whitespace afterwards should see the same two tokens either way.
  static String _expandVulgarFractions(String input) {
    final out = StringBuffer();
    for (final rune in input.runes) {
      final replacement = _vulgar[rune];
      if (replacement == null) {
        out.writeCharCode(rune);
        continue;
      }
      final written = out.toString();
      if (written.isNotEmpty &&
          _isDigit(written.codeUnitAt(written.length - 1))) {
        out.write(' ');
      }
      out.write(replacement);
    }
    return out.toString();
  }

  static bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

  /// Every vulgar fraction in Latin-1 and Number Forms. Halves through tenths, which is everything a
  /// recipe site emits.
  static const Map<int, String> _vulgar = {
    0x00BD: '1/2',
    0x2153: '1/3',
    0x2154: '2/3',
    0x00BC: '1/4',
    0x00BE: '3/4',
    0x2155: '1/5',
    0x2156: '2/5',
    0x2157: '3/5',
    0x2158: '4/5',
    0x2159: '1/6',
    0x215A: '5/6',
    0x2150: '1/7',
    0x215B: '1/8',
    0x215C: '3/8',
    0x215D: '5/8',
    0x215E: '7/8',
    0x2151: '1/9',
    0x2152: '1/10',
  };
}
```

### `lib/core/quantity/qty.dart`

```dart
import 'unit_category.dart';

/// An exact physical quantity: integer milli-base-units (the category's base unit × 1000)
/// plus a [UnitCategory]. Never backed by a `double` (Law L2). The ×1000 scale exists so a
/// half-piece or a fraction-of-a-gram spice measurement is still an exact integer — plain
/// base units would satisfy every whole-number example and then fail the first time someone
/// records `0.5 pc` or `0.25 g`. Arithmetic across categories throws
/// [UnitCategoryMismatchError] (Law L8) — there is no gram↔millilitre conversion.
final class Qty implements Comparable<Qty> {
  /// Creates a [Qty] directly from already-computed milli-base-units.
  const Qty(this.milliBase, this.category);

  /// A zero quantity in [category].
  const Qty.zero(UnitCategory category) : this(0, category);

  /// The quantity in milli-base-units, e.g. milli-grams-of-the-base-gram for weight.
  final int milliBase;

  /// Which of the three fixed categories this quantity belongs to.
  final UnitCategory category;

  /// True if [milliBase] is less than zero.
  bool get isNegative => milliBase < 0;

  /// True if [milliBase] is greater than zero.
  bool get isPositive => milliBase > 0;

  /// True if [milliBase] is exactly zero.
  bool get isZero => milliBase == 0;

  /// Adds [other]. Throws [UnitCategoryMismatchError] if the categories differ.
  Qty operator +(Qty other) {
    _assertSameCategory(other);
    return Qty(milliBase + other.milliBase, category);
  }

  /// Subtracts [other]. Throws [UnitCategoryMismatchError] if the categories differ.
  Qty operator -(Qty other) {
    _assertSameCategory(other);
    return Qty(milliBase - other.milliBase, category);
  }

  /// Scales this quantity by the integer [factor].
  Qty operator *(int factor) => Qty(milliBase * factor, category);

  /// The negation of this quantity, in the same category.
  Qty operator -() => Qty(-milliBase, category);

  @override
  int compareTo(Qty other) {
    _assertSameCategory(other);
    return milliBase.compareTo(other.milliBase);
  }

  /// True if this quantity is strictly less than [other]. Throws [UnitCategoryMismatchError]
  /// if the categories differ.
  bool operator <(Qty other) {
    _assertSameCategory(other);
    return milliBase < other.milliBase;
  }

  /// True if this quantity is less than or equal to [other]. Throws
  /// [UnitCategoryMismatchError] if the categories differ.
  bool operator <=(Qty other) {
    _assertSameCategory(other);
    return milliBase <= other.milliBase;
  }

  /// True if this quantity is strictly greater than [other]. Throws
  /// [UnitCategoryMismatchError] if the categories differ.
  bool operator >(Qty other) {
    _assertSameCategory(other);
    return milliBase > other.milliBase;
  }

  /// True if this quantity is greater than or equal to [other]. Throws
  /// [UnitCategoryMismatchError] if the categories differ.
  bool operator >=(Qty other) {
    _assertSameCategory(other);
    return milliBase >= other.milliBase;
  }

  void _assertSameCategory(Qty other) {
    if (other.category != category) {
      throw UnitCategoryMismatchError(category, other.category);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Qty && other.milliBase == milliBase && other.category == category;

  @override
  int get hashCode => Object.hash(milliBase, category);

  /// A debug-only representation, e.g. `2500000m(weight)`. Never use this for UI display —
  /// use [QtyFormatter] instead.
  @override
  String toString() => '${milliBase}m(${category.name})';
}

/// Thrown when an operation combines two [Qty] values from different [UnitCategory]s. There
/// is no gram↔millilitre conversion anywhere in this type — indicates a programming error,
/// not a recoverable user-facing condition.
final class UnitCategoryMismatchError extends Error {
  /// Records the two categories that could not be combined.
  UnitCategoryMismatchError(this.first, this.second);

  /// The category of the left-hand operand.
  final UnitCategory first;

  /// The category of the right-hand operand.
  final UnitCategory second;

  @override
  String toString() =>
      'UnitCategoryMismatchError: cannot combine ${first.name} with ${second.name}.';
}
```

### `lib/core/quantity/qty_formatter.dart`

```dart
import 'package:intl/intl.dart';

import 'qty.dart';
import 'unit_category.dart';

/// Controls how [QtyFormatter] renders a quantity. See ARCH_1 §5.2.
enum UnitStyle {
  /// Decomposes weight/volume into their carry pair (`"4 kg 450 g"`) and leaves `count` as a
  /// single number (`"3 pc"`). The default; used for item rows and batch chips.
  mixed,

  /// A single decimal number in the bigger unit for weight/volume, rounded to 2 decimal
  /// places (`"4.45 kg"`); identical to [mixed] for `count`. Used for dense chart axes and
  /// narrow chips only.
  compact,

  /// The raw base unit with no decomposition (`"4450 g"`); identical to [mixed] for `count`.
  /// Used for debug output and export.
  base,
}

/// Renders a [Qty] as a human-readable string per ARCH_1 §5.2. Pure and stateless: the same
/// [Qty] and [UnitStyle] always produce the same string. The unit vocabulary (`kg`, `g`,
/// `L`, `ml`, `pc`) is always these English abbreviations regardless of locale; [localeTag]
/// controls only the decimal separator character used in [UnitStyle.compact].
final class QtyFormatter {
  /// Creates a formatter. Stateless — safe to use as a `const` singleton.
  const QtyFormatter();

  static const int _milliPerBaseUnit = 1000;
  static const int _milliPerBigUnit = _milliPerBaseUnit * 1000; // 1 kg or 1 L, in milliBase

  /// Formats [qty] according to [style].
  String format(Qty qty, {UnitStyle style = UnitStyle.mixed, String localeTag = 'en'}) {
    final isNegative = qty.isNegative;
    final magnitude = isNegative ? -qty.milliBase : qty.milliBase;
    final sign = isNegative ? '-' : '';
    final body = switch (style) {
      UnitStyle.mixed => _formatMixed(magnitude, qty.category),
      UnitStyle.compact => _formatCompact(magnitude, qty.category, localeTag),
      UnitStyle.base => _formatBase(magnitude, qty.category),
    };
    return '$sign$body';
  }

  String _formatMixed(int magnitude, UnitCategory category) {
    return switch (category) {
      UnitCategory.count => '${_formatThousandths(magnitude)} pc',
      UnitCategory.weight => _formatCarryPair(magnitude, smallUnit: 'g', bigUnit: 'kg'),
      UnitCategory.volume => _formatCarryPair(magnitude, smallUnit: 'ml', bigUnit: 'L'),
    };
  }

  String _formatCarryPair(int magnitude, {required String smallUnit, required String bigUnit}) {
    final bigWhole = magnitude ~/ _milliPerBigUnit;
    final remainderMilli = magnitude % _milliPerBigUnit;

    if (bigWhole == 0) {
      return '${_formatThousandths(remainderMilli)} $smallUnit';
    }
    if (remainderMilli == 0) {
      return '$bigWhole $bigUnit';
    }
    return '$bigWhole $bigUnit ${_formatThousandths(remainderMilli)} $smallUnit';
  }

  String _formatCompact(int magnitude, UnitCategory category, String localeTag) {
    if (category == UnitCategory.count) return '${_formatThousandths(magnitude)} pc';

    final bigUnit = category == UnitCategory.weight ? 'kg' : 'L';
    // Half-up rounding to 2 decimal places of the big-unit value, via pure integer math:
    // hundredths = round(magnitude * 100 / 1_000_000).
    final hundredths = (magnitude * 100 + _milliPerBigUnit ~/ 2) ~/ _milliPerBigUnit;
    final whole = hundredths ~/ 100;
    final frac = hundredths % 100;
    final fracStr = frac.toString().padLeft(2, '0');
    return '$whole${_decimalSeparator(localeTag)}$fracStr $bigUnit';
  }

  String _formatBase(int magnitude, UnitCategory category) {
    final unit = category.baseUnitCode;
    return '${_formatThousandths(magnitude)} $unit';
  }

  /// Formats [valueMilli] (a count of thousandths of some unit) as that unit's exact
  /// decimal value, e.g. `450_000` → `"450"`, `500` → `"0.5"`, `5` → `"0.005"`, `0` → `"0"`.
  static String _formatThousandths(int valueMilli) {
    final whole = valueMilli ~/ _milliPerBaseUnit;
    final frac = valueMilli % _milliPerBaseUnit;
    if (frac == 0) return '$whole';

    var fracStr = frac.toString().padLeft(3, '0');
    while (fracStr.endsWith('0')) {
      fracStr = fracStr.substring(0, fracStr.length - 1);
    }
    return '$whole.$fracStr';
  }

  /// The locale's decimal-point character. Looked up from `intl`'s locale data rather than
  /// guessed from the language subtag — that would get exceptions like `de_CH` wrong, which
  /// uses a period unlike the rest of German-speaking locales.
  static String _decimalSeparator(String localeTag) =>
      NumberFormat.decimalPattern(localeTag).symbols.DECIMAL_SEP;
}
```

### `lib/core/quantity/qty_parser.dart`

```dart
import 'package:intl/intl.dart';

import '../result/failure.dart';
import '../result/result.dart';
import 'qty.dart';
import 'unit_category.dart';

/// Parses user-typed quantity text into [Qty] — Law L2's counterpart to `MoneyParser`.
///
/// **No `double` is involved at any point.** The typed decimal is converted to milli-base units by
/// exact integer arithmetic, which is what L2 requires and what makes the precision rule honest: a
/// value finer than the chosen unit can represent is **rejected**, never silently rounded. That is
/// the whole difference from a `double.parse` followed by `.round()`, which turned `0.501` of a
/// factor-1 unit into a whole one and reported success.
///
/// Never throws. Every outcome, including a string the user is still halfway through typing, comes
/// back as a [Result] so the field can decide what to surface.
final class QtyParser {
  /// Creates a parser. Stateless — safe to use as a `const` singleton.
  const QtyParser();

  static const int _maxInputLength = 18;

  /// The largest quantity this parser will produce, in milli-base units.
  ///
  /// 1e15 milli-base is a thousand tonnes of a weight item. The cap exists to keep
  /// `magnitude × factorToBaseMilli` inside a 64-bit int rather than to express a domain rule, and
  /// it is checked *before* the multiplication for exactly that reason.
  static const int maxMilliBase = 1000000000000000;

  /// Parses [input] as a quantity in the unit whose factor is [factorToBaseMilli].
  ///
  /// [factorToBaseMilli] comes from the `units` row, so `kg` is 1000000, `g` is 1000 and `pc` is
  /// 1000. [localeTag] decides which characters are the decimal point and the grouping separator.
  /// Negative input is rejected unless [allowNegative]: a movement is a positive quantity plus a
  /// `kind`, so a negative quantity is a bug at almost every call site.
  ///
  /// A fractional value is accepted whenever the unit can express it exactly — `0.5` of a `pc`
  /// is 500 milli-base, which ARCH_1 §4.2 requires — and returns
  /// [ParseFailure.tooManyDecimalDigits] when it cannot.
  Result<Qty, ParseFailure> parse(
    String input, {
    required UnitCategory category,
    required int factorToBaseMilli,
    String localeTag = 'en',
    bool allowNegative = false,
  }) {
    if (factorToBaseMilli <= 0)
      return const Result.failure(ParseFailure.malformed);

    var text = input.trim();
    if (text.isEmpty) return const Result.failure(ParseFailure.empty);
    if (text.length > _maxInputLength)
      return const Result.failure(ParseFailure.tooLarge);

    var sign = 1;
    if (text.startsWith('-')) {
      if (!allowNegative)
        return const Result.failure(ParseFailure.negativeNotAllowed);
      sign = -1;
      text = text.substring(1);
    } else if (text.startsWith('+')) {
      text = text.substring(1);
    }
    if (text.isEmpty) return const Result.failure(ParseFailure.malformed);

    final symbols = NumberFormat.decimalPattern(localeTag).symbols;
    final groupSeparator = symbols.GROUP_SEP;
    final decimalSeparator = symbols.DECIMAL_SEP;

    if (groupSeparator.isNotEmpty) {
      text = text.replaceAll(groupSeparator, '');
    }
    if (text.isEmpty) return const Result.failure(ParseFailure.malformed);

    final parts = decimalSeparator.isEmpty
        ? [text]
        : text.split(decimalSeparator);
    if (parts.length > 2) return const Result.failure(ParseFailure.malformed);

    final wholePart = parts[0];
    final fractionPart = parts.length == 2 ? parts[1] : '';

    if (wholePart.isEmpty && fractionPart.isEmpty) {
      return const Result.failure(ParseFailure.malformed);
    }
    if (!_isDigitsOnly(wholePart) || !_isDigitsOnly(fractionPart)) {
      return const Result.failure(ParseFailure.invalidCharacter);
    }

    final digits = '${wholePart.isEmpty ? '0' : wholePart}$fractionPart';
    if (digits.length > _maxInputLength)
      return const Result.failure(ParseFailure.tooLarge);

    final magnitude = int.parse(digits);
    if (magnitude > maxMilliBase ~/ factorToBaseMilli) {
      return const Result.failure(ParseFailure.tooLarge);
    }

    final scaled = magnitude * factorToBaseMilli;
    final divisor = _pow10(fractionPart.length);
    if (scaled % divisor != 0) {
      return const Result.failure(ParseFailure.tooManyDecimalDigits);
    }

    return Result.ok(Qty(sign * (scaled ~/ divisor), category));
  }

  /// Renders [qty] as plain editable digits in the unit whose factor is [factorToBaseMilli].
  ///
  /// The inverse of [parse] for a text field's initial value: plain digits with a decimal point and
  /// no grouping separators, because separators in an editable field fight the cursor.
  ///
  /// Integer arithmetic throughout, and it **truncates** at [maxFractionDigits] rather than
  /// rounding. Truncation matters because this text is what the user then edits: rounding up would
  /// let a save commit a larger quantity than the one stored, which nobody typed. A unit whose
  /// factor is not a power of ten (`dozen` is 12000) can hold values with no terminating decimal, so
  /// a bound is unavoidable.
  String format(
    Qty qty, {
    required int factorToBaseMilli,
    int maxFractionDigits = 6,
  }) {
    if (factorToBaseMilli <= 0) return '';
    final negative = qty.isNegative;
    final magnitude = negative ? -qty.milliBase : qty.milliBase;
    final sign = negative ? '-' : '';
    final whole = magnitude ~/ factorToBaseMilli;
    final remainder = magnitude % factorToBaseMilli;
    if (remainder == 0) return '$sign$whole';

    final scaled = remainder * _pow10(maxFractionDigits) ~/ factorToBaseMilli;
    var fraction = scaled.toString().padLeft(maxFractionDigits, '0');
    while (fraction.endsWith('0')) {
      fraction = fraction.substring(0, fraction.length - 1);
    }
    return fraction.isEmpty ? '$sign$whole' : '$sign$whole.$fraction';
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  static bool _isDigitsOnly(String value) {
    for (final codeUnit in value.codeUnits) {
      if (codeUnit < 0x30 || codeUnit > 0x39) return false;
    }
    return true;
  }
}
```

### `lib/core/quantity/unit_category.dart`

```dart
/// The three fixed physical quantity categories [Qty] can hold. No fourth category is ever
/// added (ARCH_1 §5.3): if an amount can't be expressed in one of these, the correct action
/// is a new Item, never a new category — this keeps cross-category conversion permanently
/// impossible to express (Law L8), rather than merely discouraged.
enum UnitCategory {
  /// Measured by mass. Base unit: gram.
  weight,

  /// Measured by capacity. Base unit: millilitre.
  volume,

  /// Measured by count. Base unit: piece. Never decomposed into a bigger/smaller unit pair.
  count;

  /// The canonical base unit code for this category: `'g'`, `'ml'`, or `'pc'`.
  String get baseUnitCode => switch (this) {
    UnitCategory.weight => 'g',
    UnitCategory.volume => 'ml',
    UnitCategory.count => 'pc',
  };
}
```

### `lib/core/quantity/unit_converter.dart`

```dart
import 'package:intl/intl.dart';

import '../result/failure.dart';
import '../result/result.dart';

/// Converts between a user-typed decimal quantity in some unit and the canonical integer
/// milliBase representation, using only integer arithmetic (Law L2). Unlike a currency's
/// exchange rate, a unit's `factorToBaseMilli` is always exact (e.g. `1 kg = 1_000_000`
/// milliBase, exactly), so this converter never needs the rate-multiplication tolerance
/// [Money.convert] does — the rare factor/precision combination that doesn't divide evenly
/// is resolved with half-up integer rounding, never a `double`.
final class UnitConverter {
  /// Creates a converter. Stateless — safe to use as a `const` singleton.
  const UnitConverter();

  static const int _maxInputLength = 24;

  /// Parses [input] — a decimal quantity in some unit — into milliBase, where one unit of
  /// the input equals [unitFactorMilliBase] milliBase units (e.g. `1_000_000` for `kg`).
  /// [localeTag] determines the decimal and grouping separator characters. Rounds half up
  /// on the rare factor/input combination that doesn't divide evenly.
  Result<int, ParseFailure> parseToMilliBase(
      String input, {
        required int unitFactorMilliBase,
        String localeTag = 'en',
        bool allowNegative = false,
      }) {
    var text = input.trim();
    if (text.isEmpty) return const Result.failure(ParseFailure.empty);
    if (text.length > _maxInputLength) return const Result.failure(ParseFailure.tooLarge);

    var sign = 1;
    if (text.startsWith('-')) {
      if (!allowNegative) return const Result.failure(ParseFailure.negativeNotAllowed);
      sign = -1;
      text = text.substring(1);
    } else if (text.startsWith('+')) {
      text = text.substring(1);
    }
    if (text.isEmpty) return const Result.failure(ParseFailure.malformed);

    final symbols = NumberFormat.decimalPattern(localeTag).symbols;
    final groupSep = symbols.GROUP_SEP;
    final decimalSep = symbols.DECIMAL_SEP;

    if (groupSep.isNotEmpty) {
      text = text.replaceAll(groupSep, '');
    }
    if (text.isEmpty) return const Result.failure(ParseFailure.malformed);

    final parts = decimalSep.isEmpty ? [text] : text.split(decimalSep);
    if (parts.length > 2) return const Result.failure(ParseFailure.malformed);

    final wholePart = parts[0];
    final fracPart = parts.length == 2 ? parts[1] : '';

    if (wholePart.isEmpty && fracPart.isEmpty) {
      return const Result.failure(ParseFailure.malformed);
    }
    if (!_isDigitsOnly(wholePart) || !_isDigitsOnly(fracPart)) {
      return const Result.failure(ParseFailure.invalidCharacter);
    }

    final numerator = int.parse('${wholePart.isEmpty ? '0' : wholePart}$fracPart');
    final denominator = _pow10(fracPart.length);
    final product = numerator * unitFactorMilliBase;
    final milliBase = (product + denominator ~/ 2) ~/ denominator;

    return Result.ok(sign * milliBase);
  }

  /// Splits [milliBase] into a whole count of units (each equal to [unitFactorMilliBase]
  /// milliBase) and the milliBase remainder. Intended for non-negative, already-stored
  /// quantities; see [Qty] for arithmetic on values that might be negative.
  ({int wholeUnits, int remainderMilliBase}) decompose(int milliBase, int unitFactorMilliBase) {
    return (
    wholeUnits: milliBase ~/ unitFactorMilliBase,
    remainderMilliBase: milliBase % unitFactorMilliBase,
    );
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  static bool _isDigitsOnly(String value) {
    for (final codeUnit in value.codeUnits) {
      if (codeUnit < 0x30 || codeUnit > 0x39) return false;
    }
    return true;
  }
}
```

### `lib/core/result/failure.dart`

```dart
/// A recoverable, expected failure returned by a repository or service instead of a thrown
/// exception, so UI code can pattern-match on the concrete subtype to decide how to respond.
sealed class Failure {
  const Failure(this.message);

  /// A developer-facing description. Never shown to a user verbatim without localisation.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The requested record does not exist, or is soft-deleted and the caller required active.
final class NotFoundFailure extends Failure {
  /// Records that [id] could not be found.
  const NotFoundFailure(super.message, {required this.id});

  /// The identifier that was looked up.
  final String id;
}

/// The operation would violate a uniqueness or identity rule (e.g. a duplicate account name).
final class ConflictFailure extends Failure {
  /// Describes the conflicting rule in [message].
  const ConflictFailure(super.message);
}

/// The change is blocked by a business rule, e.g. deleting an account with live transactions.
final class BusinessRuleFailure extends Failure {
  /// [rule] is a short machine-readable rule id (e.g. `'accountInUse'`) for the UI to switch
  /// on; [message] is the human-readable explanation.
  const BusinessRuleFailure(super.message, {required this.rule});

  /// A short, stable identifier for the violated rule.
  final String rule;
}

/// Input failed validation before it reached storage.
final class ValidationFailure extends Failure {
  /// [field] names the offending input when the failure is field-specific.
  const ValidationFailure(super.message, {this.field});

  /// The offending field name, or `null` if the failure isn't tied to one field.
  final String? field;
}

/// An unexpected, non-recoverable error was caught and wrapped so it can't crash the app.
final class UnexpectedFailure extends Failure {
  /// Wraps the original [cause], if one is available.
  const UnexpectedFailure(super.message, {this.cause});

  /// The underlying exception or error that was caught, if any.
  final Object? cause;
}

/// Why a decimal-text-to-integer parse (an amount or a quantity) did not succeed. Shared by
/// [MoneyParser] and [UnitConverter] since both parse a locale-formatted decimal string into
/// an exact integer and can fail in exactly these ways.
enum ParseFailure {
  /// The input was empty (or became empty after trimming).
  empty,

  /// The input has no digits, or has structural problems a plain digit/separator scan
  /// can't resolve (e.g. two decimal points).
  malformed,

  /// The input contains a character that isn't a digit, sign, or a locale separator.
  invalidCharacter,

  /// The input starts with a minus sign but the caller disallowed negative values.
  negativeNotAllowed,

  /// The input has more fractional digits than the target precision supports (e.g. typing
  /// "100.5" for a currency with 0 decimal digits, or a unit finer than the stored factor
  /// allows) and this parser refuses to silently round away typed precision.
  tooManyDecimalDigits,

  /// The input is implausibly long and was rejected before attempting to parse it, as a
  /// guard against integer overflow on a pathological string.
  tooLarge,
}
```

### `lib/core/result/result.dart`

```dart
/// A value that is either a success [T] or a failure [F], forcing callers to handle both
/// paths explicitly instead of relying on a thrown exception for an expected, recoverable
/// outcome (e.g. a malformed amount the user is still typing).
sealed class Result<T, F> {
  const Result();

  /// A successful result wrapping [value].
  const factory Result.ok(T value) = Ok<T, F>;

  /// A failed result wrapping [failure].
  const factory Result.failure(F failure) = Err<T, F>;

  /// True if this is a success.
  bool get isOk => this is Ok<T, F>;

  /// True if this is a failure.
  bool get isFailure => this is Err<T, F>;

  /// The success value, or `null` if this is a failure.
  T? get valueOrNull => switch (this) {
    Ok<T, F>(:final value) => value,
    Err<T, F>() => null,
  };

  /// The failure, or `null` if this is a success.
  F? get failureOrNull => switch (this) {
    Err<T, F>(:final failure) => failure,
    Ok<T, F>() => null,
  };

  /// Transforms a success value with [transform]; a failure passes through unchanged.
  Result<R, F> map<R>(R Function(T value) transform) => switch (this) {
    Ok<T, F>(:final value) => Result.ok(transform(value)),
    Err<T, F>(:final failure) => Result.failure(failure),
  };

  /// Transforms a failure with [transform]; a success passes through unchanged.
  Result<T, R> mapFailure<R>(R Function(F failure) transform) => switch (this) {
    Ok<T, F>(:final value) => Result.ok(value),
    Err<T, F>(:final failure) => Result.failure(transform(failure)),
  };

  /// Reduces both branches to a single value of type [R].
  R fold<R>(R Function(T value) onOk, R Function(F failure) onFailure) => switch (this) {
    Ok<T, F>(:final value) => onOk(value),
    Err<T, F>(:final failure) => onFailure(failure),
  };
}

/// The success branch of a [Result].
final class Ok<T, F> extends Result<T, F> {
  /// Wraps a successful [value].
  const Ok(this.value);

  /// The success payload.
  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T, F> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

/// The failure branch of a [Result].
final class Err<T, F> extends Result<T, F> {
  /// Wraps a [failure].
  const Err(this.failure);

  /// The failure payload.
  final F failure;

  @override
  bool operator ==(Object other) => other is Err<T, F> && other.failure == failure;

  @override
  int get hashCode => Object.hash(Err, failure);

  @override
  String toString() => 'Err($failure)';
}
```

### `lib/core/text/normalizer.dart`

```dart
/// Reduces a display name to a canonical form used only for identity matching (e.g. two
/// Items are the same Item only if their normalized names are identical) — the normalized
/// form is never shown to a user. Deliberately does no stemming or singularisation: "tomato"
/// and "tomatoes" normalize to two different strings, and stay two different Items, because
/// silent fuzzy merging can corrupt data in ways a user can't easily notice or undo.
final class Normalizer {
  /// Creates a normalizer. Stateless — safe to use as a `const` singleton.
  const Normalizer();

  // \p{M} (combining marks) must stay allowed alongside \p{L}\p{N} — Devanagari vowel
  // signs, Arabic tashkeel, and similar combining diacritics are category M, not L, and
  // stripping them as "punctuation" would corrupt those scripts' words, not just declutter
  // them the way it does for Latin punctuation.
  static final RegExp _nonLetterDigitOrMark = RegExp(r'[^\p{L}\p{N}\p{M}\s]', unicode: true);
  static final RegExp _whitespaceRun = RegExp(r'\s+');

  /// Produces the canonical identity form of [input]: case-folded, common precomposed Latin
  /// diacritics stripped to their base letter, all other punctuation removed (any script,
  /// via a Unicode-aware letter/number/mark test — not a hardcoded ASCII punctuation list),
  /// internal whitespace collapsed to single spaces, and the result trimmed. Limitation:
  /// this folds precomposed Latin accents (`'é'` as one code point, how Android text input
  /// normally produces them) but not an `'e'` followed by a separate combining-accent code
  /// point, which is rare in practice and is left attached rather than risking corruption
  /// of combining marks in other scripts.
  String normalize(String input) {
    final caseFolded = input.toLowerCase();
    final withoutDiacritics = _stripDiacritics(caseFolded);
    final withoutPunctuation = withoutDiacritics.replaceAll(_nonLetterDigitOrMark, ' ');
    return withoutPunctuation.replaceAll(_whitespaceRun, ' ').trim();
  }

  String _stripDiacritics(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final replacement = _diacriticMap[rune];
      if (replacement != null) {
        buffer.write(replacement);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  /// Maps lowercase Latin letters with diacritics/ligatures to their plain base form(s).
  /// Covers Latin-1 Supplement and the common Latin Extended-A range; scripts without this
  /// notion of "diacritics to strip" (Devanagari, Arabic, CJK, ...) pass through unchanged.
  /// Every rune of each key maps to the value, including the plain base letter that leads the
  /// multi-character groups — that self-mapping is a harmless no-op, and iterating all runes
  /// is what makes the single-character ligature entries (`æ`, `œ`, `ß`, `ð`, `þ`) work at all.
  static final Map<int, String> _diacriticMap = {
    for (final entry in const {
      'aàáâãäåāăą': 'a',
      'cçćĉċč': 'c',
      'dđď': 'd',
      'eèéêëēĕėęě': 'e',
      'gĝğġģ': 'g',
      'hĥħ': 'h',
      'iìíîïĩīĭįı': 'i',
      'jĵ': 'j',
      'kķ': 'k',
      'lĺļľł': 'l',
      'nñńņň': 'n',
      'oòóôõöøōŏő': 'o',
      'rŕŗř': 'r',
      'sśŝşš': 's',
      'tţťŧ': 't',
      'uùúûüũūŭůűų': 'u',
      'wŵ': 'w',
      'yýÿŷ': 'y',
      'zźżž': 'z',
      'æ': 'ae',
      'œ': 'oe',
      'ß': 'ss',
      'ð': 'd',
      'þ': 'th',
    }.entries)
      for (final variant in entry.key.runes) variant: entry.value,
  };
}
```

### `lib/core/text/split_placeholder_names.dart`

```dart
/// Naming a split participant nobody has identified yet.
///
/// **A split saves without names, and this is how without junking your contacts.** A share must name
/// somebody — `split_shares.payee_id` is `NOT NULL REFERENCES payees(id)` — so an unnamed participant
/// needs a payee row to exist at all.
///
/// The first attempt made those rows ordinary people called "Person 4", which was rejected for the
/// right reason: they pile up in Settings › Payees beside real contacts. The second idea was a schema
/// change making `payee_id` nullable, which needs the table rebuilt, a new drift snapshot and a
/// regenerated `schema_steps.dart`.
///
/// [PayeeKind.splitPlaceholder] costs neither. `SafeEnumConverter` stores an enum **by name**, so a new
/// member needs no migration; the row exists where balances need it and is filtered out of every list
/// where you would not want it.
library;

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/payee.dart';

/// Placeholder participants: how they are named, and how they are recognised.
abstract final class SplitPlaceholderNames {
  /// The word every placeholder starts with.
  ///
  /// Not localised, deliberately: the name is written to the database, so translating it would leave a
  /// user who changes language with half their placeholders called "Person" and half "Personne".
  static const String prefix = 'Person';

  /// Whether [payee] is a row this app created because nobody had been named.
  ///
  /// **Read from `kind`, not from the name.** An earlier version matched `Person \d+` with a regular
  /// expression, which meant somebody who genuinely typed "Person 5" got offered a rename, and a
  /// placeholder renamed to "Ravi" stopped being detectable only because the *name* changed rather
  /// than because anything said so. The kind is the fact; the name is a label on it.
  static bool isPlaceholder(Payee payee) =>
      payee.kind == PayeeKind.splitPlaceholder;

  /// [count] fresh placeholder names, numbered past everything in [existing].
  ///
  /// **Continues the sequence rather than restarting it**, so a second split does not create a second
  /// "Person 1" beside the first. Two strangers sharing a row is a wrong balance nobody would think to
  /// check, and renaming one does not free its number.
  ///
  /// [existing] should be every participant of any kind: a placeholder that has since become "Ravi" no
  /// longer matches the pattern, but the number it used is still spoken for by the rows referencing it.
  static List<String> nextNames({
    required int count,
    required Iterable<String> existing,
  }) {
    var top = 0;
    final pattern = RegExp('^$prefix\\s+(\\d+)\$');
    for (final name in existing) {
      final match = pattern.firstMatch(name.trim());
      if (match == null) continue;
      final value = int.tryParse(match.group(1)!);
      if (value != null && value > top) top = value;
    }
    return [for (var i = 1; i <= count; i++) '$prefix ${top + i}'];
  }
}
```

### `lib/core/time/clock.dart`

```dart
import 'date_key.dart';

/// Supplies the current time so it can be faked in tests; no code outside this file should
/// call `DateTime.now()` directly. Deliberately a single-method interface: the derived values
/// live in [ClockDerived] as extension methods, so an implementation only ever has to supply
/// [now] and the derived values can never drift out of sync with it.
abstract interface class Clock {
  /// The current local wall-clock date and time.
  DateTime now();
}

/// Values derived from [Clock.now]. Extension methods rather than interface members with
/// default bodies: `implements` inherits an interface but not its method bodies, so a default
/// body on the interface would force every implementer to redeclare it anyway.
extension ClockDerived on Clock {
  /// The current instant as epoch milliseconds UTC (Law L4's instant representation).
  int nowUtcMillis() => now().toUtc().millisecondsSinceEpoch;

  /// Today's date in the device's local timezone, as a civil [DateKey].
  DateKey today() => DateKey.fromDateTime(now());
}

/// The production [Clock], backed by the real system time.
final class SystemClock implements Clock {
  /// Creates a clock that reads the device's real wall-clock time.
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// A [Clock] fixed to one instant, for deterministic tests. Call [advance] to move it
/// forward within a test instead of constructing a new instance each time.
final class FixedClock implements Clock {
  /// Creates a clock fixed at [initial].
  FixedClock(DateTime initial) : _current = initial;

  DateTime _current;

  @override
  DateTime now() => _current;

  /// Moves this clock forward by [duration] (or backward, if negative).
  void advance(Duration duration) => _current = _current.add(duration);

  /// Sets this clock to exactly [dateTime].
  void setTo(DateTime dateTime) => _current = dateTime;
}
```

### `lib/core/time/date_key.dart`

```dart
/// A local civil date stored as an integer `yyyymmdd` (e.g. `20260728`), with zero runtime
/// overhead over the `int` it wraps. Deliberately has no timezone or time-of-day component
/// (Law L4): a bill "due on the 5th" is the 5th regardless of where the user is standing,
/// which is why this is never a `DateTime`/instant. `DateKey(rawValue)` does not validate —
/// it exists for cheap, trusted round-tripping of a value already known to be valid (e.g.
/// hydrating a database row). Build a validated instance from components with
/// [DateKey.fromYmd] or [DateKey.fromDateTime].
///
/// Note this cannot declare `implements Comparable<DateKey>`: an extension type may only
/// implement supertypes of its representation type, and `int` implements `Comparable<num>`,
/// not `Comparable<DateKey>`. [compareTo] is therefore a plain method, and sorting a
/// `List<DateKey>` uses the static [DateKey.compare] as an explicit comparator.
extension type const DateKey(int value) {
  /// Builds a validated [DateKey] from calendar components. Throws [ArgumentError] if the
  /// combination isn't a real calendar date (e.g. 30 February).
  factory DateKey.fromYmd(int year, int month, int day) {
    if (month < 1 || month > 12) {
      throw ArgumentError.value(month, 'month', 'must be between 1 and 12');
    }
    if (day < 1 || day > 31) {
      throw ArgumentError.value(day, 'day', 'must be between 1 and 31');
    }
    final rolled = DateTime.utc(year, month, day);
    if (rolled.year != year || rolled.month != month || rolled.day != day) {
      throw ArgumentError('$year-$month-$day is not a real calendar date');
    }
    return DateKey(year * 10000 + month * 100 + day);
  }

  /// Builds a [DateKey] from [dateTime]'s own year/month/day fields, taken exactly as they
  /// are on [dateTime] — this never calls `.toUtc()`, so passing a local `DateTime` yields
  /// the local civil date, which is almost always what "today" should mean.
  factory DateKey.fromDateTime(DateTime dateTime) =>
      DateKey.fromYmd(dateTime.year, dateTime.month, dateTime.day);

  /// The 4-digit year component.
  int get year => value ~/ 10000;

  /// The 1-based month component, `1`-`12`.
  int get month => (value ~/ 100) % 100;

  /// The 1-based day-of-month component.
  int get day => value % 100;

  /// The `yyyymm` month this date falls in, e.g. `20260728` → `202607`.
  int get monthKey => value ~/ 100;

  /// ISO weekday: `1` (Monday) through `7` (Sunday).
  int get weekday => toUtcMidnight().weekday;

  /// This date as a UTC-anchored midnight [DateTime]. This exists purely as a calculation
  /// vehicle for calendar arithmetic (UTC has no DST jumps, so day-arithmetic is exact) — it
  /// is never a real instant and must never be persisted as one.
  DateTime toUtcMidnight() => DateTime.utc(year, month, day);

  /// A new [DateKey] this many calendar days after this one. [days] may be negative.
  DateKey addDays(int days) => DateKey.fromDateTime(toUtcMidnight().add(Duration(days: days)));

  /// The number of calendar days from [other] to this date; positive when this date is
  /// later, negative when earlier.
  int diffDays(DateKey other) => toUtcMidnight().difference(other.toUtcMidnight()).inDays;

  /// True if this date is strictly before [other].
  bool isBefore(DateKey other) => value < other.value;

  /// True if this date is strictly after [other].
  bool isAfter(DateKey other) => value > other.value;

  /// True if this date is on or after [start] and on or before [end] (inclusive).
  bool isWithin(DateKey start, DateKey end) => value >= start.value && value <= end.value;

  /// Compares this date with [other]: negative if earlier, zero if equal, positive if later.
  int compareTo(DateKey other) => value.compareTo(other.value);

  /// A comparator for sorting, e.g. `dates.sort(DateKey.compare)`. Needed because an
  /// extension type cannot implement `Comparable<DateKey>` (see the class doc), so the
  /// zero-argument `List.sort()` is unavailable.
  static int compare(DateKey a, DateKey b) => a.value.compareTo(b.value);

  /// True if this date is strictly before [other].
  bool operator <(DateKey other) => value < other.value;

  /// True if this date is before or the same as [other].
  bool operator <=(DateKey other) => value <= other.value;

  /// True if this date is strictly after [other].
  bool operator >(DateKey other) => value > other.value;

  /// True if this date is after or the same as [other].
  bool operator >=(DateKey other) => value >= other.value;

  /// Renders as `yyyy-mm-dd` for logs and debugging only — never for UI display.
  String toIso() => '$year-${_twoDigits(month)}-${_twoDigits(day)}';

  static String _twoDigits(int n) => n < 10 ? '0$n' : '$n';
}
```

### `lib/core/time/date_key_labels.dart`

```dart
import 'date_key.dart';

/// Human day labels for a ledger's date headers.
///
/// A ledger is scanned, not read: the eye is looking for *when*, and `2026-08-01` forces the reader to
/// work out that it means today. "Today" and "Yesterday" are recognised without parsing, and beyond
/// that a weekday plus a short date is enough — a ledger row's year is almost never in doubt, and
/// printing it on every header is noise that crowds out the amount.
///
/// Lives in `core/time` rather than a widget so the ledger, the calendar and any future export agree on
/// what a given date is called.
extension DateKeyLabels on DateKey {
  /// Short month names, indexed 1-12.
  static const List<String> monthNames = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Short weekday names, indexed 1-7 with Monday first, matching `DateTime.weekday`.
  static const List<String> weekdayNames = [
    '',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// `1 Aug` — no year.
  String get shortLabel => '$day ${monthNames[month]}';

  /// `Fri 1 Aug` — no year.
  String get weekdayLabel =>
      '${weekdayNames[weekday]} $day ${monthNames[month]}';

  /// `1 Aug 2026` — with year, for a date far from now.
  String get fullLabel => '$day ${monthNames[month]} $year';

  /// The label a ledger day header should show, relative to [today].
  ///
  /// Today and yesterday are named. Anything else in the same year gets a weekday and date; a different
  /// year gets the year too, because that is the one case where omitting it could mislead.
  String headerLabel(DateKey today) {
    final delta = today.diffDays(this);
    if (delta == 0) return 'Today';
    if (delta == 1) return 'Yesterday';
    if (year != today.year) return fullLabel;
    return weekdayLabel;
  }

  /// `August 2026`, for a period header.
  String get monthLabel => '${monthNames[month]} $year';
}
```

### `test/core/date_key_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/time/date_key.dart';

void main() {
  group('DateKey.fromYmd — valid dates', () {
    test('packs year/month/day into yyyymmdd', () {
      expect(DateKey.fromYmd(2026, 7, 28).value, 20260728);
    });

    test('accepts the last day of a 31-day month', () {
      expect(DateKey.fromYmd(2026, 7, 31).value, 20260731);
    });

    test('accepts 29 February on a leap year', () {
      expect(DateKey.fromYmd(2024, 2, 29).value, 20240229);
    });
  });

  group('DateKey.fromYmd — invalid dates rejected', () {
    test('rejects 30 February', () {
      expect(() => DateKey.fromYmd(2026, 2, 30), throwsArgumentError);
    });

    test('rejects 29 February on a non-leap year', () {
      expect(() => DateKey.fromYmd(2026, 2, 29), throwsArgumentError);
    });

    test('rejects month 0 and month 13', () {
      expect(() => DateKey.fromYmd(2026, 0, 1), throwsArgumentError);
      expect(() => DateKey.fromYmd(2026, 13, 1), throwsArgumentError);
    });

    test('rejects day 0 and day 32', () {
      expect(() => DateKey.fromYmd(2026, 1, 0), throwsArgumentError);
      expect(() => DateKey.fromYmd(2026, 1, 32), throwsArgumentError);
    });

    test('rejects 31 April (a 30-day month)', () {
      expect(() => DateKey.fromYmd(2026, 4, 31), throwsArgumentError);
    });
  });

  group('DateKey component getters', () {
    test('year, month, day, monthKey all read back correctly', () {
      final date = DateKey.fromYmd(2026, 7, 28);
      expect(date.year, 2026);
      expect(date.month, 7);
      expect(date.day, 28);
      expect(date.monthKey, 202607);
    });

    test('weekday matches the known calendar weekday', () {
      // 28 July 2026 is a Tuesday (ISO weekday 2).
      expect(DateKey.fromYmd(2026, 7, 28).weekday, DateTime.tuesday);
    });
  });

  group('DateKey.addDays', () {
    test('stays within a month', () {
      expect(DateKey.fromYmd(2026, 7, 28).addDays(2), DateKey.fromYmd(2026, 7, 30));
    });

    test('crosses a month boundary', () {
      expect(DateKey.fromYmd(2026, 7, 31).addDays(1), DateKey.fromYmd(2026, 8, 1));
    });

    test('crosses a year boundary', () {
      expect(DateKey.fromYmd(2026, 12, 31).addDays(1), DateKey.fromYmd(2027, 1, 1));
    });

    test('crosses a leap-year 29 February correctly', () {
      expect(DateKey.fromYmd(2024, 2, 28).addDays(1), DateKey.fromYmd(2024, 2, 29));
      expect(DateKey.fromYmd(2024, 2, 29).addDays(1), DateKey.fromYmd(2024, 3, 1));
    });

    test('negative days moves backward', () {
      expect(DateKey.fromYmd(2026, 8, 1).addDays(-1), DateKey.fromYmd(2026, 7, 31));
    });
  });

  group('DateKey.diffDays', () {
    test('is positive when this date is later', () {
      final later = DateKey.fromYmd(2026, 8, 1);
      final earlier = DateKey.fromYmd(2026, 7, 28);
      expect(later.diffDays(earlier), 4);
    });

    test('is negative when this date is earlier', () {
      final later = DateKey.fromYmd(2026, 8, 1);
      final earlier = DateKey.fromYmd(2026, 7, 28);
      expect(earlier.diffDays(later), -4);
    });

    test('is zero for the same date', () {
      final date = DateKey.fromYmd(2026, 7, 28);
      expect(date.diffDays(date), 0);
    });
  });

  group('DateKey comparisons', () {
    test('compareTo, isBefore, isAfter, and operators agree', () {
      final earlier = DateKey.fromYmd(2026, 7, 28);
      final later = DateKey.fromYmd(2026, 8, 1);

      expect(earlier.compareTo(later), lessThan(0));
      expect(earlier.isBefore(later), isTrue);
      expect(later.isAfter(earlier), isTrue);
      expect(earlier < later, isTrue);
      expect(later > earlier, isTrue);
      expect(earlier <= earlier, isTrue);
      expect(earlier >= earlier, isTrue);
    });

    test('isWithin is inclusive of both bounds', () {
      final start = DateKey.fromYmd(2026, 7, 1);
      final end = DateKey.fromYmd(2026, 7, 31);
      expect(DateKey.fromYmd(2026, 7, 15).isWithin(start, end), isTrue);
      expect(start.isWithin(start, end), isTrue);
      expect(end.isWithin(start, end), isTrue);
      expect(DateKey.fromYmd(2026, 8, 1).isWithin(start, end), isFalse);
    });
  });

  group('DateKey.fromDateTime', () {
    test('uses the DateTime\'s own year/month/day fields', () {
      final localDateTime = DateTime(2026, 7, 28, 23, 45);
      expect(DateKey.fromDateTime(localDateTime), DateKey.fromYmd(2026, 7, 28));

      final utcDateTime = DateTime.utc(2027, 1, 1, 0, 15);
      expect(DateKey.fromDateTime(utcDateTime), DateKey.fromYmd(2027, 1, 1));
    });

    test('reads the local calendar date, never one shifted through .toUtc()', () {
      // Pick a local time-of-day placed right at whichever edge of the day would cross
      // into an adjacent UTC calendar day for this machine's actual UTC offset, so the
      // test is a real, portable proof rather than one that only works by coincidence.
      final offset = DateTime.now().timeZoneOffset;
      final local = offset.isNegative
          ? DateTime(2026, 7, 28, 23, 59)
          : DateTime(2026, 7, 28, 0, 1);

      expect(DateKey.fromDateTime(local), DateKey.fromYmd(2026, 7, 28));
    });
  });

  group('DateKey.toIso', () {
    test('renders as zero-padded yyyy-mm-dd', () {
      expect(DateKey.fromYmd(2026, 1, 5).toIso(), '2026-01-05');
    });
  });
}
```

### `test/core/measure_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/fraction.dart';
import 'package:alaya/core/quantity/measure.dart';
import 'package:alaya/core/quantity/measure_formatter.dart';
import 'package:alaya/core/quantity/measure_parser.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';

/// The three vessel factors from the `units` seed, plus the two that divide cleanly.
///
/// **The awkward ones are the point.** ARCH_M §7: "test with the awkward factors: 240000 divides cleanly
/// and would have passed." A cup is 240000 and hides every rounding fault; a teaspoon is 4929, which is
/// odd, not divisible by two, and is where the previous implementation broke.
const int kTsp = 4929;
const int kTbsp = 14787;
const int kCup = 240000;
const int kMl = 1000;
const int kLitre = 1000000;

void main() {
  const parser = MeasureParser();
  const formatter = MeasureFormatter();

  group('Fraction', () {
    test('reduces, so 2/4 and 1/2 are one value', () {
      expect(Fraction(2, 4), Fraction(1, 2));
      expect(Fraction(6, 8).denominator, 4);
      expect(Fraction(0, 7), Fraction.zero);
    });

    test('quantises to thousandths, half up', () {
      expect(Fraction(1, 2).milliOfUnit, 500);
      expect(Fraction(1, 3).milliOfUnit, 333);
      expect(Fraction(2, 3).milliOfUnit, 667);
      expect(Fraction(1, 8).milliOfUnit, 125);
      // 62.5 rounds up rather than truncating to 62 — the truncation ARCH_M §7 records.
      expect(Fraction(1, 16).milliOfUnit, 63);
    });

    test('refuses a zero or negative denominator', () {
      expect(() => Fraction(1, 0), throwsArgumentError);
      expect(() => Fraction(1, -2), throwsArgumentError);
    });
  });

  group('fractionForMilli — recognition by round trip, not by table', () {
    test('finds every fraction a drawer contains', () {
      for (final fraction in kMeasuringSet) {
        expect(
          fractionForMilli(fraction.milliOfUnit),
          fraction,
          reason: 'failed for $fraction',
        );
      }
    });

    test('finds the fractions the old nine-entry table did', () {
      // Every key of the table this replaced. None of them may regress.
      const table = {
        125: '1/8',
        250: '1/4',
        333: '1/3',
        375: '3/8',
        500: '1/2',
        625: '5/8',
        667: '2/3',
        750: '3/4',
        875: '7/8',
      };
      for (final entry in table.entries) {
        expect(fractionForMilli(entry.key).toString(), entry.value);
      }
      // A count beside the set, per ARCH_M §7: without it, a shrinking expectation passes quietly.
      expect(table, hasLength(9));
    });

    test('finds fractions the old table could not', () {
      // The whole complaint: these rendered as decimals before.
      expect(fractionForMilli(63).toString(), '1/16');
      expect(fractionForMilli(167).toString(), '1/6');
      expect(fractionForMilli(833).toString(), '5/6');
      expect(fractionForMilli(200).toString(), '1/5');
      expect(fractionForMilli(143).toString(), '1/7');
    });

    test('returns the simplest denominator, not the first that fits', () {
      expect(fractionForMilli(500).toString(), '1/2');
      expect(fractionForMilli(250).toString(), '1/4');
      expect(fractionForMilli(750).toString(), '3/4');
    });

    test('returns null rather than inventing precision', () {
      // 137 is closest to 2/15, which is 0.1333 — not close enough to have been stored as 137.
      expect(fractionForMilli(137), isNull);
      expect(fractionForMilli(0), isNull);
      expect(fractionForMilli(1000), isNull);
    });

    test('every fraction it returns round-trips to the input', () {
      // The property the whole design rests on, asserted across the entire domain rather than at
      // sampled points: if a fraction comes back, storing it again must reproduce the same thousandths.
      for (var milli = 1; milli < 1000; milli++) {
        final fraction = fractionForMilli(milli);
        if (fraction == null) continue;
        expect(
          fraction.milliOfUnit,
          milli,
          reason: '$fraction did not round-trip from $milli',
        );
      }
    });
  });

  group('Measure — the Qty round trip', () {
    test('survives every vessel factor, across the whole useful range', () {
      // ARCH_M §7's recorded failure, asserted as a property. 4929 is the factor that broke it.
      for (final factor in [kTsp, kTbsp, kCup, kMl, kLitre]) {
        for (var milli = 0; milli <= 10000; milli++) {
          final measure = Measure(milli);
          final restored = Measure.fromQty(
            measure.toQty(
              factorToBaseMilli: factor,
              category: UnitCategory.volume,
            ),
            factorToBaseMilli: factor,
          );
          expect(
            restored.milliOfUnit,
            milli,
            reason: 'factor $factor lost $milli',
          );
        }
      }
    });

    test('half a tablespoon is 7393 or 7394, and comes back as a half', () {
      final half = Measure.of(0, Fraction(1, 2));
      final quantity = half.toQty(
        factorToBaseMilli: kTbsp,
        category: UnitCategory.volume,
      );
      // 14787 / 2 is 7393.5. Either neighbour is acceptable; silently becoming 499 thousandths is not.
      expect(quantity.milliBase, anyOf(7393, 7394));
      expect(
        Measure.fromQty(quantity, factorToBaseMilli: kTbsp).remainderMilli,
        500,
      );
    });

    test('composes and decomposes a whole part and a fraction', () {
      final measure = Measure.of(3, Fraction(1, 2));
      expect(measure.milliOfUnit, 3500);
      expect(measure.whole, 3);
      expect(measure.remainderMilli, 500);
      expect(measure.withWhole(0).milliOfUnit, 500);
      expect(measure.withFraction(null).milliOfUnit, 3000);
    });

    test('scales upward, matching the engine rather than contradicting it', () {
      // `CookabilityEngine.scaleMilli` takes a ceiling because a false "you have enough" ruins dinner.
      // A display that rounded down would show less than the verdict demands.
      expect(
        Measure(1000).scaled(fromServings: 3, toServings: 2).milliOfUnit,
        667,
      );
      expect(
        Measure(12345).scaled(fromServings: 4, toServings: 4).milliOfUnit,
        12345,
      );
      expect(
        () => Measure(1000).scaled(fromServings: 0, toServings: 1),
        throwsArgumentError,
      );
    });
  });

  group('MeasureParser — what cooks write', () {
    test('plain numbers and decimals', () {
      expect(parser.parse('2').valueOrNull, const Measure(2000));
      expect(parser.parse('0.5').valueOrNull, const Measure(500));
      expect(parser.parse('.5').valueOrNull, const Measure(500));
    });

    test('fractions, including ones no chip offers', () {
      expect(parser.parse('1/2').valueOrNull, const Measure(500));
      expect(parser.parse('3/4').valueOrNull, const Measure(750));
      expect(parser.parse('2/3').valueOrNull, const Measure(667));
      expect(parser.parse('5/16').valueOrNull, const Measure(313));
    });

    test('a whole part and a fraction', () {
      expect(parser.parse('1 1/2').valueOrNull, const Measure(1500));
      expect(parser.parse('2 3/4').valueOrNull, const Measure(2750));
    });

    test('the vulgar fractions a pasted recipe carries', () {
      expect(parser.parse('½').valueOrNull, const Measure(500));
      expect(parser.parse('⅔').valueOrNull, const Measure(667));
      expect(parser.parse('⅜').valueOrNull, const Measure(375));
      // With and without the space, because a website emits either.
      expect(parser.parse('1½').valueOrNull, const Measure(1500));
      expect(parser.parse('1 ½').valueOrNull, const Measure(1500));
    });

    test('names its refusals', () {
      expect(parser.parse('').failureOrNull, ParseFailure.empty);
      expect(parser.parse('-1').failureOrNull, ParseFailure.negativeNotAllowed);
      expect(parser.parse('1 2 3').failureOrNull, ParseFailure.malformed);
      expect(parser.parse('1/0').failureOrNull, ParseFailure.malformed);
      // A denominator that would quantise to nothing is refused rather than read as zero.
      expect(parser.parse('1/5000').failureOrNull, ParseFailure.malformed);
    });

    test('what is typed is what is rendered', () {
      // The round trip a user actually notices: type 2/3, see 2/3. Not 0.667.
      for (final written in [
        '1/2',
        '3/4',
        '2/3',
        '1/3',
        '1/8',
        '1 1/2',
        '5/16',
      ]) {
        final measure = parser.parse(written).valueOrNull;
        expect(measure, isNotNull, reason: 'could not parse $written');
        expect(formatter.format(measure!).text, written);
      }
    });
  });

  group('MeasureFormatter — exact style', () {
    test('renders whole numbers without a fraction', () {
      expect(formatter.format(const Measure(2000)).text, '2');
      expect(formatter.format(const Measure(0)).text, '0');
    });

    test('never marks anything approximate', () {
      for (final milli in [137, 222, 500, 3500, 63]) {
        expect(formatter.format(Measure(milli)).isApproximate, isFalse);
      }
    });

    test('falls back to a decimal when no fraction fits', () {
      final rendered = formatter.format(const Measure(137));
      expect(rendered.text, '0.137');
      expect(rendered.fraction, isNull);
    });
  });

  group('MeasureFormatter — kitchen style', () {
    test('222 thousandths of a cup is a quarter cup', () {
      // The case that motivated the style. 2/9 is the honest fraction and no drawer contains a ninth.
      final rendered = formatter.format(
        const Measure(222),
        style: MeasureStyle.kitchen,
      );
      expect(rendered.text, '1/4');
      expect(rendered.isApproximate, isTrue);
      expect(rendered.measure.milliOfUnit, 250);
    });

    test('leaves an amount alone when it is already in the drawer', () {
      // And therefore claims nothing: no snap, no glyph, no caveat on a figure that needs none.
      for (final fraction in kMeasuringSet) {
        final rendered = formatter.format(
          Measure(fraction.milliOfUnit),
          style: MeasureStyle.kitchen,
        );
        expect(rendered.isApproximate, isFalse, reason: 'snapped $fraction');
        expect(rendered.text, fraction.toString());
      }
    });

    test('carries into the whole part when the snap reaches a full unit', () {
      final rendered = formatter.format(
        const Measure(1960),
        style: MeasureStyle.kitchen,
      );
      expect(rendered.text, '2');
      expect(rendered.isApproximate, isTrue);
    });

    test('a tie snaps upward, because understating ruins the dish', () {
      // **875 is the only genuine tie in the drawer**, sitting exactly 125 from both 3/4 and a whole
      // unit — the other six gaps have non-integer midpoints, so no thousandths value lands on them.
      // Upward means it becomes one whole unit rather than three quarters, matching
      // `CookabilityEngine.scaleMilli`'s direction.
      //
      // I asserted 625 -> 3/4 first, reasoning from the halves and quarters and forgetting that the
      // drawer contains 2/3 between them. It snaps to 2/3, which is 42 thousandths away rather than 125.
      final tie = formatter.format(
        const Measure(875),
        style: MeasureStyle.kitchen,
      );
      expect(tie.text, '1');
      expect(tie.isApproximate, isTrue);

      expect(
        formatter.format(const Measure(625), style: MeasureStyle.kitchen).text,
        '2/3',
      );
    });

    test('every snapped value is itself renderable', () {
      // A snap that produced something the formatter then rendered as a decimal would defeat the
      // purpose. Asserted across the whole remainder range rather than at sampled points.
      for (var milli = 1; milli < 4000; milli++) {
        final rendered = formatter.format(
          Measure(milli),
          style: MeasureStyle.kitchen,
        );
        expect(
          rendered.text,
          isNot(contains('.')),
          reason: '$milli snapped to an unrenderable ${rendered.text}',
        );
      }
    });
  });

  group('chipsFor — the drawer plus the present tense', () {
    test('offers the drawer when nothing unusual is set', () {
      expect(formatter.chipsFor(const Measure(0)), kMeasuringSet);
      expect(formatter.chipsFor(const Measure(500)), kMeasuringSet);
      expect(formatter.chipsFor(const Measure(3250)), kMeasuringSet);
    });

    test('a typed fraction becomes a chip, in order', () {
      final chips = formatter.chipsFor(const Measure(313));
      expect(chips, hasLength(kMeasuringSet.length + 1));
      expect(chips.contains(Fraction(5, 16)), isTrue);
      // Sorted, so the new chip appears where a cook would look for it rather than tacked on the end.
      expect(chips, orderedEquals(<Fraction>[...chips]..sort()));
    });

    test('adds nothing when the amount has no simple fraction', () {
      expect(formatter.chipsFor(const Measure(137)), kMeasuringSet);
    });
  });

  group('Qty is untouched', () {
    test('a measure converts to the canonical quantity the engine compares', () {
      // The engine, the database and the cook flow all still speak Qty. This type is a lens on it, not
      // a replacement for it — nothing above needs to learn a new storage format.
      final measure = Measure.of(2, Fraction(1, 2));
      expect(
        measure.toQty(factorToBaseMilli: kCup, category: UnitCategory.volume),
        const Qty(600000, UnitCategory.volume),
      );
    });
  });
}
```

### `test/core/money_allocate_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';

/// [Money.allocate] and [Money.allocateEvenly].
///
/// **A separate file from `money_test.dart` on purpose.** That file covers arithmetic, comparison and
/// conversion and needed no change; putting allocation there would bury a new guarantee inside a
/// regression suite for existing behaviour.
///
/// Every expected vector below was recomputed in an independent implementation before it was written
/// here — ARCH_M §7 records why that is not optional.
void main() {
  Money inr(int minor) => Money(minor, 'INR');

  /// The guarantee the whole type rests on.
  void expectExact(Money total, List<int> weights) {
    final parts = total.allocate(weights);
    final sum = parts.fold(Money.zero(total.currencyCode), (a, b) => a + b);
    expect(
      sum,
      total,
      reason: 'allocate($weights) of $total summed to $sum',
    );
  }

  group('the sum is always exactly the input', () {
    test('across a wide sweep of amounts and part counts', () {
      // The property, not a sample. Anything that loses or invents a paisa fails here.
      for (var minor = 0; minor <= 2000; minor++) {
        for (var parts = 1; parts <= 9; parts++) {
          final shares = inr(minor).allocateEvenly(parts);
          final sum = shares.fold(0, (a, b) => a + b.minor);
          expect(sum, minor, reason: '$minor into $parts');
        }
      }
    });

    test('with lopsided and zero weights', () {
      expectExact(inr(100000), [9999, 1]);
      expectExact(inr(100000), [1, 1, 0]);
      expectExact(inr(7), [3, 3, 3, 3, 3]);
      expectExact(inr(1), [1, 1, 1, 1]);
    });

    test('for negative amounts, so a refund splits like a charge', () {
      expectExact(inr(-100000), [1, 1, 1]);
      expectExact(inr(-7), [2, 3]);
    });
  });

  group('the vectors', () {
    test('a thousand rupees three ways', () {
      // Not 333.33 three times. The stray two paise go to the largest remainders.
      expect(
        inr(100000).allocateEvenly(3).map((m) => m.minor),
        orderedEquals([33334, 33333, 33333]),
      );
    });

    test('a thousand rupees seven ways', () {
      expect(
        inr(100000).allocateEvenly(7).map((m) => m.minor),
        orderedEquals([14286, 14286, 14286, 14286, 14286, 14285, 14285]),
      );
    });

    test('one paisa between two people', () {
      // Somebody gets it. Nobody gets half.
      expect(
        inr(1).allocateEvenly(2).map((m) => m.minor),
        orderedEquals([1, 0]),
      );
    });

    test('fifty thirty twenty, in basis points', () {
      expect(
        inr(100000).allocate([5000, 3000, 2000]).map((m) => m.minor),
        orderedEquals([50000, 30000, 20000]),
      );
    });

    test('a refund of a thousand three ways', () {
      expect(
        inr(-100000).allocateEvenly(3).map((m) => m.minor),
        orderedEquals([-33334, -33333, -33333]),
      );
    });
  });

  group('a zero weight pays nothing, ever', () {
    test('and never collects a leftover unit', () {
      // The guest who did not eat. This holds because the leftover count is always strictly less
      // than the number of parts with a non-zero remainder, so the sort never reaches a zero.
      for (var minor = 1; minor <= 500; minor++) {
        final parts = inr(minor).allocate([1, 1, 1, 0]);
        expect(parts.last, inr(0), reason: 'minor $minor gave ${parts.last}');
      }
    });
  });

  group('determinism', () {
    test('the same weights always place the stray units identically', () {
      // A split shown on one screen and recomputed on the next must agree about who owes the extra
      // paisa, or the two screens disagree about the amount.
      for (var i = 0; i < 50; i++) {
        expect(
          inr(100000).allocate([1, 1, 1]).map((m) => m.minor),
          orderedEquals([33334, 33333, 33333]),
        );
      }
    });

    test('equal remainders break toward the earlier position', () {
      expect(
        inr(10).allocate([1, 1, 1]).map((m) => m.minor),
        orderedEquals([4, 3, 3]),
      );
    });
  });

  group('zero and one', () {
    test('nothing splits into nothing', () {
      expect(
        inr(0).allocateEvenly(4).map((m) => m.minor),
        orderedEquals([0, 0, 0, 0]),
      );
    });

    test('one participant takes the lot', () {
      expect(inr(12345).allocateEvenly(1).single, inr(12345));
    });
  });

  group('the currency travels', () {
    test('every part keeps the input currency', () {
      for (final part in Money(999, 'USD').allocateEvenly(4)) {
        expect(part.currencyCode, 'USD');
      }
    });
  });

  group('programming errors, not user states', () {
    test('empty weights', () {
      expect(() => inr(100).allocate([]), throwsArgumentError);
    });

    test('a negative weight', () {
      expect(() => inr(100).allocate([1, -1]), throwsArgumentError);
    });

    test('all weights zero', () {
      expect(() => inr(100).allocate([0, 0]), throwsArgumentError);
    });

    test('a non-positive part count', () {
      expect(() => inr(100).allocateEvenly(0), throwsArgumentError);
      expect(() => inr(100).allocateEvenly(-3), throwsArgumentError);
    });
  });
}
```

### `test/core/money_formatter_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/money/money_formatter.dart';

void main() {
  const formatter = MoneyFormatter();

  String rupees(int minor, {bool showPlusSign = false}) => formatter.format(
    Money(minor, 'INR'),
    decimalDigits: 2,
    symbol: 'INR',
    showPlusSign: showPlusSign,
  );

  group('symbol gap', () {
    test('separates the symbol from the digits', () {
      expect(rupees(500000), 'INR 5,000.00');
    });

    test('the sign leads, before the symbol', () {
      expect(rupees(-50000), '-INR 500.00');
      expect(rupees(50000, showPlusSign: true), '+INR 500.00');
    });

    test('is an ordinary space, so a test can assert it by eye', () {
      expect(MoneyFormatter.symbolGap, ' ');
      expect(rupees(100).contains('\u00A0'), isFalse);
    });
  });

  group('Indian grouping', () {
    // The reason this formatter does not use NumberFormat: `intl` supports one uniform group
    // size, so it cannot produce 2-2-3. These are the boundaries where that difference appears.
    test('groups by thousand, then by hundred', () {
      expect(rupees(100000), 'INR 1,000.00');
      expect(rupees(1000000), 'INR 10,000.00');
      expect(rupees(10000000), 'INR 1,00,000.00');
      expect(rupees(100000000), 'INR 10,00,000.00');
      expect(rupees(1000000000), 'INR 1,00,00,000.00');
    });

    test('leaves three digits and fewer ungrouped', () {
      expect(rupees(99900), 'INR 999.00');
      expect(rupees(100), 'INR 1.00');
      expect(rupees(0), 'INR 0.00');
    });

    test('a Western locale groups by three throughout', () {
      expect(
        formatter.format(
          const Money(1000000000, 'USD'),
          decimalDigits: 2,
          symbol: 'USD',
          localeTag: 'en_US',
        ),
        'USD 10,000,000.00',
      );
    });
  });

  group('decimal digits come from the currency', () {
    test('zero-decimal currencies render no fractional part', () {
      expect(
        formatter.format(
          const Money(1200, 'JPY'),
          decimalDigits: 0,
          symbol: 'JPY',
        ),
        'JPY 1,200',
      );
    });

    test('a fraction is padded to the currency width', () {
      expect(rupees(50005), 'INR 500.05');
      expect(rupees(50050), 'INR 500.50');
    });
  });

  group('the integer is never touched', () {
    test('formatting is display-only and does not round', () {
      // Law L1: money is integer minor units end to end. A formatter that rounded would make the
      // displayed figure disagree with the stored one, which is the bug this rule exists to prevent.
      const money = Money(123456789, 'INR');
      formatter.format(money, decimalDigits: 2, symbol: 'INR');
      expect(money.minor, 123456789);
    });

    test('a negative amount keeps its magnitude', () {
      expect(rupees(-123456789), '-INR 12,34,567.89');
    });
  });
}
```

### `test/core/money_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/money/rounding.dart';

void main() {
  group('Money construction', () {
    test('stores minor units and currency code as given', () {
      const money = Money(12345, 'INR');
      expect(money.minor, 12345);
      expect(money.currencyCode, 'INR');
    });

    test('Money.zero is zero in the given currency', () {
      const zero = Money.zero('INR');
      expect(zero.minor, 0);
      expect(zero.isZero, isTrue);
      expect(zero.currencyCode, 'INR');
    });
  });

  group('Money arithmetic (same currency)', () {
    test('addition sums minor units', () {
      expect(const Money(100, 'INR') + const Money(50, 'INR'), const Money(150, 'INR'));
    });

    test('subtraction can go negative', () {
      expect(const Money(50, 'INR') - const Money(100, 'INR'), const Money(-50, 'INR'));
    });

    test('multiplication by an int scales minor units', () {
      expect(const Money(100, 'INR') * 3, const Money(300, 'INR'));
    });

    test('unary minus negates minor units, keeping currency', () {
      expect(-const Money(100, 'INR'), const Money(-100, 'INR'));
    });

    test('abs returns a positive amount regardless of sign', () {
      expect(const Money(-100, 'INR').abs(), const Money(100, 'INR'));
      expect(const Money(100, 'INR').abs(), const Money(100, 'INR'));
    });

    test('isNegative, isPositive, isZero classify correctly', () {
      expect(const Money(-1, 'INR').isNegative, isTrue);
      expect(const Money(1, 'INR').isPositive, isTrue);
      expect(const Money(0, 'INR').isZero, isTrue);
    });
  });

  group('Money cross-currency arithmetic throws', () {
    test('addition across currencies throws CurrencyMismatchError', () {
      expect(
            () => const Money(100, 'INR') + const Money(100, 'USD'),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });

    test('subtraction across currencies throws CurrencyMismatchError', () {
      expect(
            () => const Money(100, 'INR') - const Money(100, 'USD'),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });
  });

  group('Money comparisons (same currency)', () {
    test('compareTo orders by minor units', () {
      expect(const Money(100, 'INR').compareTo(const Money(200, 'INR')), lessThan(0));
      expect(const Money(200, 'INR').compareTo(const Money(100, 'INR')), greaterThan(0));
      expect(const Money(100, 'INR').compareTo(const Money(100, 'INR')), 0);
    });

    test('< <= > >= behave as expected', () {
      expect(const Money(100, 'INR') < const Money(200, 'INR'), isTrue);
      expect(const Money(100, 'INR') <= const Money(100, 'INR'), isTrue);
      expect(const Money(200, 'INR') > const Money(100, 'INR'), isTrue);
      expect(const Money(100, 'INR') >= const Money(100, 'INR'), isTrue);
    });
  });

  group('Money cross-currency comparison throws', () {
    test('compareTo across currencies throws CurrencyMismatchError', () {
      expect(
            () => const Money(100, 'INR').compareTo(const Money(100, 'USD')),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });

    test('< across currencies throws CurrencyMismatchError', () {
      expect(
            () => const Money(100, 'INR') < const Money(100, 'USD'),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });
  });

  group('Money equality and hashCode', () {
    test('equal minor units and currency are equal', () {
      expect(const Money(100, 'INR'), const Money(100, 'INR'));
      expect(const Money(100, 'INR').hashCode, const Money(100, 'INR').hashCode);
    });

    test('different currency is never equal even with the same minor units', () {
      expect(const Money(100, 'INR') == const Money(100, 'USD'), isFalse);
    });

    test('different minor units are never equal', () {
      expect(const Money(100, 'INR') == const Money(200, 'INR'), isFalse);
    });
  });

  group('Money.convert', () {
    test('same decimal digits, simple rate', () {
      final converted = const Money(10000, 'INR').convert(
        rate: 0.5,
        toCurrencyCode: 'XXX',
        fromDecimalDigits: 2,
        toDecimalDigits: 2,
      );
      expect(converted, const Money(5000, 'XXX'));
    });

    test('converting to a zero-decimal currency (JPY) scales correctly', () {
      final converted = const Money(10000, 'INR').convert(
        rate: 1.9,
        toCurrencyCode: 'JPY',
        fromDecimalDigits: 2,
        toDecimalDigits: 0,
      );
      expect(converted, const Money(190, 'JPY'));
    });

    test('does not mutate the original amount (Law L9)', () {
      const original = Money(10000, 'INR');
      original.convert(
        rate: 2,
        toCurrencyCode: 'USD',
        fromDecimalDigits: 2,
        toDecimalDigits: 2,
      );
      expect(original.minor, 10000);
      expect(original.currencyCode, 'INR');
    });

    test('halfUp rounds an exact .5 away from zero', () {
      final positive = const Money(1, 'INR').convert(
        rate: 2.5,
        toCurrencyCode: 'XXX',
        fromDecimalDigits: 0,
        toDecimalDigits: 0,
      );
      expect(positive.minor, 3);

      final negative = const Money(-1, 'INR').convert(
        rate: 2.5,
        toCurrencyCode: 'XXX',
        fromDecimalDigits: 0,
        toDecimalDigits: 0,
      );
      expect(negative.minor, -3);
    });

    test('halfEven rounds an exact .5 to the nearest even integer', () {
      final roundsDown = const Money(1, 'INR').convert(
        rate: 2.5,
        toCurrencyCode: 'XXX',
        fromDecimalDigits: 0,
        toDecimalDigits: 0,
        rounding: MoneyRounding.halfEven,
      );
      expect(roundsDown.minor, 2); // 2 is already even

      final roundsUp = const Money(1, 'INR').convert(
        rate: 3.5,
        toCurrencyCode: 'XXX',
        fromDecimalDigits: 0,
        toDecimalDigits: 0,
        rounding: MoneyRounding.halfEven,
      );
      expect(roundsUp.minor, 4); // 3 is odd, rounds up to even 4
    });

    test('halfDown rounds an exact .5 toward zero', () {
      final result = const Money(1, 'INR').convert(
        rate: 2.5,
        toCurrencyCode: 'XXX',
        fromDecimalDigits: 0,
        toDecimalDigits: 0,
        rounding: MoneyRounding.halfDown,
      );
      expect(result.minor, 2);
    });
  });
}
```

### `test/core/normalizer_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/text/normalizer.dart';

void main() {
  const normalizer = Normalizer();

  group('casefolding', () {
    test('uppercase folds to lowercase', () {
      expect(normalizer.normalize('POTATO'), 'potato');
    });

    test('mixed case folds to lowercase', () {
      expect(normalizer.normalize('PoTaTo'), 'potato');
    });
  });

  group('diacritic stripping', () {
    test('strips a single acute accent', () {
      expect(normalizer.normalize('café'), 'cafe');
    });

    test('strips a tilde', () {
      expect(normalizer.normalize('jalapeño'), 'jalapeno');
    });

    test('strips diacritics on uppercase letters too, after casefolding', () {
      expect(normalizer.normalize('MÜNCHEN'), 'munchen');
    });

    test('folds ligatures to their letter pairs', () {
      expect(normalizer.normalize('œuf'), 'oeuf');
    });

    test('folds eszett to ss', () {
      expect(normalizer.normalize('straße'), 'strasse');
    });
  });

  group('punctuation stripping', () {
    test('a comma becomes whitespace and is collapsed', () {
      expect(normalizer.normalize('Rice, White'), 'rice white');
    });

    test('an apostrophe becomes whitespace, consistent with all other punctuation', () {
      expect(normalizer.normalize("Tomato's"), 'tomato s');
    });

    test('digits are preserved, only punctuation is stripped', () {
      expect(normalizer.normalize('Vitamin B-12!'), 'vitamin b 12');
    });
  });

  group('whitespace collapse and trim', () {
    test('multiple internal spaces collapse to one', () {
      expect(normalizer.normalize('Rice    Flour'), 'rice flour');
    });

    test('leading and trailing whitespace is trimmed', () {
      expect(normalizer.normalize('   Rice Flour   '), 'rice flour');
    });

    test('tabs and newlines count as whitespace', () {
      expect(normalizer.normalize('Rice\tFlour\n'), 'rice flour');
    });
  });

  group('combined pipeline', () {
    test('casefold, diacritics, punctuation, and whitespace all apply together', () {
      expect(normalizer.normalize('  CAFÉ-Au-Lait!!  '), 'cafe au lait');
    });
  });

  group('exact-match-only (no stemming, no singularisation) — A07', () {
    test('a plural and its singular remain two different normalized strings', () {
      expect(normalizer.normalize('tomato'), isNot(normalizer.normalize('tomatoes')));
      expect(normalizer.normalize('tomatoes'), 'tomatoes');
    });

    test('near-identical words are not silently merged', () {
      expect(normalizer.normalize('onion'), isNot(normalizer.normalize('onions')));
    });
  });

  group('non-Latin scripts pass through unchanged (beyond casefold/whitespace)', () {
    test('Devanagari text is preserved, not stripped as punctuation', () {
      expect(normalizer.normalize('टमाटर'), 'टमाटर');
    });

    test('Devanagari text still has its surrounding whitespace trimmed', () {
      expect(normalizer.normalize('  टमाटर  '), 'टमाटर');
    });
  });

  group('empty and whitespace-only input', () {
    test('an empty string normalizes to an empty string', () {
      expect(normalizer.normalize(''), '');
    });

    test('a whitespace-only string normalizes to an empty string', () {
      expect(normalizer.normalize('   '), '');
    });
  });
}
```

### `test/core/qty_formatter_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_formatter.dart';
import 'package:alaya/core/quantity/unit_category.dart';

void main() {
  const formatter = QtyFormatter();

  group('CRITICAL required test cases (ARCH_1 §5.4, mixed style)', () {
    test('250_000 + 2_000_000 + 1_500_000 + 700_000 weight = 4_450_000 -> "4 kg 450 g"', () {
      // `final`, not `const`: a constant expression may only use the built-in `num`/`String`
      // operators, never a user-defined `operator +` like Qty's.
      final sum = const Qty(250000, UnitCategory.weight) +
          const Qty(2000000, UnitCategory.weight) +
          const Qty(1500000, UnitCategory.weight) +
          const Qty(700000, UnitCategory.weight);
      expect(sum.milliBase, 4450000);
      expect(formatter.format(sum), '4 kg 450 g');
    });

    test('2_000_000 weight -> "2 kg", never "2 kg 0 g"', () {
      const qty = Qty(2000000, UnitCategory.weight);
      expect(formatter.format(qty), '2 kg');
    });

    test('1_200_000 volume -> "1 L 200 ml"', () {
      const qty = Qty(1200000, UnitCategory.volume);
      expect(formatter.format(qty), '1 L 200 ml');
    });

    test('500 count -> "0.5 pc"', () {
      const qty = Qty(500, UnitCategory.count);
      expect(formatter.format(qty), '0.5 pc');
    });

    test('3_000 count -> "3 pc"', () {
      const qty = Qty(3000, UnitCategory.count);
      expect(formatter.format(qty), '3 pc');
    });
  });

  group('mixed style — additional edge cases', () {
    test('zero renders without a big-unit part', () {
      expect(formatter.format(const Qty(0, UnitCategory.weight)), '0 g');
      expect(formatter.format(const Qty(0, UnitCategory.volume)), '0 ml');
      expect(formatter.format(const Qty(0, UnitCategory.count)), '0 pc');
    });

    test('sub-base fractional weight with no whole big unit', () {
      // 250 milliBase = 0.25 g — less than one base unit, no kg part at all.
      expect(formatter.format(const Qty(250, UnitCategory.weight)), '0.25 g');
    });

    test('fractional remainder in the small unit alongside a whole big unit', () {
      // 1_000_250 milliBase weight = 1 kg + 0.25 g.
      expect(formatter.format(const Qty(1000250, UnitCategory.weight)), '1 kg 0.25 g');
    });

    test('a tiny sub-thousandth-of-a-gram amount keeps 3 decimal places', () {
      // 5 milliBase = 0.005 g exactly.
      expect(formatter.format(const Qty(5, UnitCategory.weight)), '0.005 g');
    });

    test('negative quantity is prefixed with a minus sign', () {
      expect(formatter.format(const Qty(-2000000, UnitCategory.weight)), '-2 kg');
    });
  });

  group('compact style', () {
    test('4_450_000 weight -> "4.45 kg"', () {
      const qty = Qty(4450000, UnitCategory.weight);
      expect(formatter.format(qty, style: UnitStyle.compact), '4.45 kg');
    });

    test('a value under 1 big unit still renders in the big unit', () {
      // 450_000 milliBase = 0.45 kg, expressed in kg even though it's under 1.
      const qty = Qty(450000, UnitCategory.weight);
      expect(formatter.format(qty, style: UnitStyle.compact), '0.45 kg');
    });

    test('count is unaffected by compact style', () {
      const qty = Qty(3000, UnitCategory.count);
      expect(formatter.format(qty, style: UnitStyle.compact), '3 pc');
    });

    test('uses the locale decimal separator', () {
      const qty = Qty(4450000, UnitCategory.weight);
      expect(formatter.format(qty, style: UnitStyle.compact, localeTag: 'de_DE'), '4,45 kg');
    });
  });

  group('base style', () {
    test('4_450_000 weight -> "4450 g", no decomposition', () {
      const qty = Qty(4450000, UnitCategory.weight);
      expect(formatter.format(qty, style: UnitStyle.base), '4450 g');
    });

    test('1_200_000 volume -> "1200 ml"', () {
      const qty = Qty(1200000, UnitCategory.volume);
      expect(formatter.format(qty, style: UnitStyle.base), '1200 ml');
    });

    test('count is unaffected by base style', () {
      const qty = Qty(3000, UnitCategory.count);
      expect(formatter.format(qty, style: UnitStyle.base), '3 pc');
    });
  });
}
```

### `test/core/qty_parser_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_parser.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';

void main() {
  const parser = QtyParser();

  // The seeded factors from ARCH_2 §14, so the cases are the ones the app actually meets.
  const kg = 1000000;
  const g = 1000;
  const mg = 1;
  const pc = 1000;
  const dozen = 12000;

  Qty? parsed(
    String input, {
    required int factor,
    UnitCategory category = UnitCategory.weight,
    bool allowNegative = false,
  }) => parser
      .parse(
        input,
        category: category,
        factorToBaseMilli: factor,
        allowNegative: allowNegative,
      )
      .valueOrNull;

  ParseFailure? failed(
    String input, {
    required int factor,
    UnitCategory category = UnitCategory.weight,
    bool allowNegative = false,
  }) => parser
      .parse(
        input,
        category: category,
        factorToBaseMilli: factor,
        allowNegative: allowNegative,
      )
      .failureOrNull;

  group('exact conversion', () {
    test('whole units scale by the factor', () {
      expect(parsed('2', factor: kg), const Qty(2000000, UnitCategory.weight));
      expect(parsed('250', factor: g), const Qty(250000, UnitCategory.weight));
      expect(parsed('5', factor: mg), const Qty(5, UnitCategory.weight));
    });

    test('fractions the unit can express are exact', () {
      expect(
        parsed('0.25', factor: kg),
        const Qty(250000, UnitCategory.weight),
      );
      expect(
        parsed('1.5', factor: kg),
        const Qty(1500000, UnitCategory.weight),
      );
      expect(parsed('0.5', factor: g), const Qty(500, UnitCategory.weight));
    });

    test('half a piece is legal — ARCH_1 §4.2 requires it', () {
      expect(
        parsed('0.5', factor: pc, category: UnitCategory.count),
        const Qty(500, UnitCategory.count),
      );
    });

    test('a factor that is not a power of ten still converts exactly', () {
      expect(
        parsed('0.5', factor: dozen, category: UnitCategory.count),
        const Qty(6000, UnitCategory.count),
      );
      expect(
        parsed('1', factor: dozen, category: UnitCategory.count),
        const Qty(12000, UnitCategory.count),
      );
    });

    test('the category is carried through, not inferred', () {
      expect(
        parsed('1', factor: g, category: UnitCategory.volume),
        const Qty(1000, UnitCategory.volume),
      );
    });
  });

  group('precision is refused, never rounded', () {
    // ARCH_4 R20: the double-backed field turned this into one whole unit and reported success.
    test('a value finer than the unit fails rather than rounding', () {
      expect(failed('0.501', factor: mg), ParseFailure.tooManyDecimalDigits);
      expect(failed('0.0001', factor: g), ParseFailure.tooManyDecimalDigits);
    });

    test('the boundary case is accepted', () {
      expect(parsed('0.001', factor: g), const Qty(1, UnitCategory.weight));
    });
  });

  group('rejections', () {
    test('empty and still-being-typed input', () {
      expect(failed('', factor: g), ParseFailure.empty);
      expect(failed('   ', factor: g), ParseFailure.empty);
      expect(failed('.', factor: g), ParseFailure.malformed);
      expect(failed('1.2.3', factor: g), ParseFailure.malformed);
    });

    test('non-digits', () {
      expect(failed('abc', factor: g), ParseFailure.invalidCharacter);
      expect(failed('1kg', factor: g), ParseFailure.invalidCharacter);
    });

    test('negatives need opting in', () {
      expect(failed('-1', factor: g), ParseFailure.negativeNotAllowed);
      expect(
        parsed('-1', factor: g, allowNegative: true),
        const Qty(-1000, UnitCategory.weight),
      );
    });

    test(
      'a quantity too large to hold is caught before the multiplication',
      () {
        expect(failed('99999999999999', factor: kg), ParseFailure.tooLarge);
      },
    );

    test('a nonsensical factor fails rather than dividing by zero', () {
      expect(failed('1', factor: 0), ParseFailure.malformed);
    });
  });

  test('grouping separators are stripped', () {
    expect(parsed('1,250', factor: g), const Qty(1250000, UnitCategory.weight));
  });

  group('format', () {
    test('renders in the unit with no trailing zeros', () {
      expect(
        parser.format(
          const Qty(4450000, UnitCategory.weight),
          factorToBaseMilli: kg,
        ),
        '4.45',
      );
      expect(
        parser.format(
          const Qty(4450000, UnitCategory.weight),
          factorToBaseMilli: g,
        ),
        '4450',
      );
      expect(
        parser.format(
          const Qty(500, UnitCategory.count),
          factorToBaseMilli: pc,
        ),
        '0.5',
      );
      expect(
        parser.format(
          const Qty(2000000, UnitCategory.weight),
          factorToBaseMilli: kg,
        ),
        '2',
      );
    });

    test('round trips through parse', () {
      const original = Qty(1234500, UnitCategory.weight);
      final text = parser.format(original, factorToBaseMilli: kg);
      expect(parsed(text, factor: kg), original);
    });

    test('negatives keep their sign', () {
      expect(
        parser.format(
          const Qty(-500, UnitCategory.weight),
          factorToBaseMilli: g,
        ),
        '-0.5',
      );
    });
  });
}
```

### `test/core/qty_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';

void main() {
  group('Qty construction', () {
    test('stores milliBase and category as given', () {
      const qty = Qty(2000000, UnitCategory.weight);
      expect(qty.milliBase, 2000000);
      expect(qty.category, UnitCategory.weight);
    });

    test('Qty.zero is zero in the given category', () {
      const zero = Qty.zero(UnitCategory.weight);
      expect(zero.milliBase, 0);
      expect(zero.isZero, isTrue);
      expect(zero.category, UnitCategory.weight);
    });
  });

  group('Qty arithmetic (same category)', () {
    test('addition sums milliBase', () {
      expect(
        const Qty(1000, UnitCategory.weight) + const Qty(500, UnitCategory.weight),
        const Qty(1500, UnitCategory.weight),
      );
    });

    test('subtraction can go negative', () {
      expect(
        const Qty(500, UnitCategory.weight) - const Qty(1000, UnitCategory.weight),
        const Qty(-500, UnitCategory.weight),
      );
    });

    test('multiplication by an int scales milliBase', () {
      expect(
        const Qty(1000, UnitCategory.weight) * 3,
        const Qty(3000, UnitCategory.weight),
      );
    });

    test('unary minus negates milliBase, keeping category', () {
      expect(-const Qty(1000, UnitCategory.weight), const Qty(-1000, UnitCategory.weight));
    });

    test('isNegative, isPositive, isZero classify correctly', () {
      expect(const Qty(-1, UnitCategory.count).isNegative, isTrue);
      expect(const Qty(1, UnitCategory.count).isPositive, isTrue);
      expect(const Qty(0, UnitCategory.count).isZero, isTrue);
    });
  });

  group('Qty cross-category arithmetic throws', () {
    test('addition across categories throws UnitCategoryMismatchError', () {
      expect(
            () => const Qty(1000, UnitCategory.weight) + const Qty(1000, UnitCategory.volume),
        throwsA(isA<UnitCategoryMismatchError>()),
      );
    });

    test('subtraction across categories throws UnitCategoryMismatchError', () {
      expect(
            () => const Qty(1000, UnitCategory.weight) - const Qty(1000, UnitCategory.count),
        throwsA(isA<UnitCategoryMismatchError>()),
      );
    });
  });

  group('Qty comparisons (same category)', () {
    test('compareTo orders by milliBase', () {
      expect(
        const Qty(100, UnitCategory.weight).compareTo(const Qty(200, UnitCategory.weight)),
        lessThan(0),
      );
    });

    test('< <= > >= behave as expected', () {
      expect(const Qty(100, UnitCategory.weight) < const Qty(200, UnitCategory.weight), isTrue);
      expect(
        const Qty(100, UnitCategory.weight) <= const Qty(100, UnitCategory.weight),
        isTrue,
      );
      expect(
        const Qty(200, UnitCategory.weight) > const Qty(100, UnitCategory.weight),
        isTrue,
      );
      expect(
        const Qty(100, UnitCategory.weight) >= const Qty(100, UnitCategory.weight),
        isTrue,
      );
    });
  });

  group('Qty cross-category comparison throws', () {
    test('compareTo across categories throws UnitCategoryMismatchError', () {
      expect(
            () => const Qty(100, UnitCategory.weight).compareTo(const Qty(100, UnitCategory.volume)),
        throwsA(isA<UnitCategoryMismatchError>()),
      );
    });
  });

  group('Qty equality and hashCode', () {
    test('equal milliBase and category are equal', () {
      expect(const Qty(1000, UnitCategory.weight), const Qty(1000, UnitCategory.weight));
      expect(
        const Qty(1000, UnitCategory.weight).hashCode,
        const Qty(1000, UnitCategory.weight).hashCode,
      );
    });

    test('different category is never equal even with the same milliBase', () {
      expect(const Qty(1000, UnitCategory.weight) == const Qty(1000, UnitCategory.volume), isFalse);
    });

    test('different milliBase is never equal', () {
      expect(const Qty(1000, UnitCategory.weight) == const Qty(2000, UnitCategory.weight), isFalse);
    });
  });

  group('UnitCategory.baseUnitCode', () {
    test('maps each category to its base unit code', () {
      expect(UnitCategory.weight.baseUnitCode, 'g');
      expect(UnitCategory.volume.baseUnitCode, 'ml');
      expect(UnitCategory.count.baseUnitCode, 'pc');
    });
  });
}
```

### `test/core/split_placeholder_names_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/text/split_placeholder_names.dart';
import 'package:alaya/domain/entities/payee.dart';

/// [SplitPlaceholderNames].
///
/// **The detection tests are rewritten, not repaired.** They used to assert a regular expression over
/// the *name* — which meant somebody who genuinely typed "Person 5" was treated as a placeholder, and
/// a placeholder renamed to "Ravi" stopped being one only because the name changed rather than because
/// anything said so. Detection now reads `kind`, so the tests assert the fact rather than a label on it.
void main() {
  Payee payee(String name, {PayeeKind kind = PayeeKind.person}) => Payee(
    id: 'p-$name',
    name: name,
    normalizedName: name.toLowerCase(),
    kind: kind,
  );

  group('numbering', () {
    test('starts at one when nobody exists', () {
      expect(
        SplitPlaceholderNames.nextNames(count: 3, existing: const []),
        ['Person 1', 'Person 2', 'Person 3'],
      );
    });

    test('continues past whatever is already there', () {
      // **A second split must not create a second "Person 1".** Two people who have never met sharing
      // a row is the failure this avoids, and it is invisible until somebody settles the wrong debt.
      expect(
        SplitPlaceholderNames.nextNames(
          count: 2,
          existing: const ['Person 1', 'Person 2', 'Person 3', 'Ravi'],
        ),
        ['Person 4', 'Person 5'],
      );
    });

    test('a renamed placeholder does not free its number', () {
      // "Person 1" became "Ravi", and the next name is still 4 — reusing 1 would put a fresh stranger
      // where a known person used to be in every historical split.
      expect(
        SplitPlaceholderNames.nextNames(
          count: 1,
          existing: const ['Ravi', 'Person 2', 'Person 3'],
        ),
        ['Person 4'],
      );
    });

    test('names that merely look similar are ignored', () {
      expect(
        SplitPlaceholderNames.nextNames(
          count: 1,
          existing: const ['Person', 'Personal', 'Person X', 'Persons 9'],
        ),
        ['Person 1'],
      );
    });

    test('asking for none gives none', () {
      expect(
        SplitPlaceholderNames.nextNames(count: 0, existing: const ['Person 1']),
        isEmpty,
      );
    });
  });

  group('detection reads the kind, not the name', () {
    test('a placeholder is one whatever it is called', () {
      // The kind survives a rename that has not happened yet, and it is what the balance row keys its
      // "Who is this?" affordance on.
      for (final name in ['Person 4', 'Ravi', '']) {
        expect(
          SplitPlaceholderNames.isPlaceholder(
            payee(name, kind: PayeeKind.splitPlaceholder),
          ),
          isTrue,
          reason: name,
        );
      }
    });

    test('somebody who typed "Person 5" themselves is not a placeholder', () {
      // **The bug the regular expression had.** A real contact called "Person 5" was offered a rename
      // prompt they never needed, and nothing in the data disagreed — because the data was never asked.
      expect(SplitPlaceholderNames.isPlaceholder(payee('Person 5')), isFalse);
    });

    test('naming one is what stops it being a placeholder', () {
      // Renaming writes `kind: person` and the real name in a single update. There is no flag to clear,
      // so a flag and a name can never disagree.
      final before = payee('Person 4', kind: PayeeKind.splitPlaceholder);
      final after = payee('Ravi');
      expect(SplitPlaceholderNames.isPlaceholder(before), isTrue);
      expect(SplitPlaceholderNames.isPlaceholder(after), isFalse);
    });

    test('no other kind is ever mistaken for one', () {
      for (final kind in PayeeKind.values) {
        expect(
          SplitPlaceholderNames.isPlaceholder(payee('Anybody', kind: kind)),
          kind == PayeeKind.splitPlaceholder,
          reason: kind.name,
        );
      }
    });
  });
}
```
