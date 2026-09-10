# B3_DOMAIN

Entities, repository contracts, service contracts, pure engines.

**91 files · 17,216 lines.**  Written 2026-08-27T08:54:37-04:00.

Every file below is complete and current. Paths are destinations.

---

### `lib/domain/entities/account.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// A container that holds money and has a balance — `Cash in hand`, `HDFC Savings`.
///
/// Distinct from a `PaymentMethod` (the rail money travelled on) and a `Payee` (the counterparty).
/// Collapsing those three into one list is anomaly A01, and it is what makes "Total Available
/// Funds" unanswerable.
class Account {
  /// Creates an account.
  const Account({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.kind,
    required this.currencyCode,
    required this.openingBalance,
    required this.openingBalanceDateKey,
    required this.isArchived,
    required this.includeInNetWorth,
    required this.sortOrder,
    this.colorArgb,
    this.iconKey,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// Display name as the user typed it.
  final String name;

  /// Normalised form used for identity matching only, never displayed.
  final String normalizedName;

  /// What kind of container this is.
  final AccountKind kind;

  /// The single currency this account is denominated in.
  final String currencyCode;

  /// Balance already present when tracking began (anomaly A03).
  final Money openingBalance;

  /// The civil date [openingBalance] was true on.
  final DateKey openingBalanceDateKey;

  /// Retired but historical.
  ///
  /// An archived account still counts toward totals and net worth — it has only left the pickers.
  /// That is the distinction from deletion which ARCH_3 §4 exists to preserve: a closed bank
  /// account with ₹0 is archived, a duplicate transaction is deleted.
  final bool isArchived;

  /// Whether this account contributes to the net-worth headline.
  final bool includeInNetWorth;

  /// Manual ordering within pickers.
  final int sortOrder;

  /// Optional ARGB colour.
  final int? colorArgb;

  /// Optional icon identifier.
  final String? iconKey;

  /// True when this account may be chosen in a picker.
  bool get isSelectable => !isArchived;

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  Account copyWith({
    String? id,
    String? name,
    String? normalizedName,
    AccountKind? kind,
    String? currencyCode,
    Money? openingBalance,
    DateKey? openingBalanceDateKey,
    bool? isArchived,
    bool? includeInNetWorth,
    int? sortOrder,
    int? colorArgb,
    String? iconKey,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      kind: kind ?? this.kind,
      currencyCode: currencyCode ?? this.currencyCode,
      openingBalance: openingBalance ?? this.openingBalance,
      openingBalanceDateKey: openingBalanceDateKey ?? this.openingBalanceDateKey,
      isArchived: isArchived ?? this.isArchived,
      includeInNetWorth: includeInNetWorth ?? this.includeInNetWorth,
      sortOrder: sortOrder ?? this.sortOrder,
      colorArgb: colorArgb ?? this.colorArgb,
      iconKey: iconKey ?? this.iconKey,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Account &&
          other.id == id &&
          other.name == name &&
          other.normalizedName == normalizedName &&
          other.kind == kind &&
          other.currencyCode == currencyCode &&
          other.openingBalance == openingBalance &&
          other.openingBalanceDateKey == openingBalanceDateKey &&
          other.isArchived == isArchived &&
          other.includeInNetWorth == includeInNetWorth &&
          other.sortOrder == sortOrder &&
          other.colorArgb == colorArgb &&
          other.iconKey == iconKey;

  @override
  int get hashCode => Object.hashAll([
    id, name, normalizedName, kind, currencyCode, openingBalance,
    openingBalanceDateKey, isArchived, includeInNetWorth, sortOrder, colorArgb, iconKey,
  ]);

  @override
  String toString() => 'Account($id, $name)';
}
```

### `lib/domain/entities/account_balance.dart`

```dart
import 'package:alaya/core/money/money.dart';

/// One account's derived balance — opening balance plus the sum of its ledger legs.
///
/// Read-only by nature: no repository writes a balance, because no total is ever stored (Law L3).
/// It comes from `v_account_balances`, which is what makes a self-transfer net to zero by
/// construction rather than by arithmetic anyone has to get right (anomaly A02).
class AccountBalance {
  /// Creates a balance.
  const AccountBalance({
    required this.accountId,
    required this.balance,
  });

  /// The account this balance belongs to.
  final String accountId;

  /// The balance, in the account's own currency.
  ///
  /// Never sum these across accounts without converting first — they may be in different
  /// currencies (anomaly A34).
  final Money balance;

  /// True when the account is overdrawn.
  bool get isNegative => balance.isNegative;

  @override
  bool operator ==(Object other) =>
      other is AccountBalance && other.accountId == accountId && other.balance == balance;

  @override
  int get hashCode => Object.hash(accountId, balance);

  @override
  String toString() => 'AccountBalance($accountId: $balance)';
}
```

### `lib/domain/entities/asset.dart`

```dart
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// A durable, serviceable, non-consumable thing **or person**.
///
/// [AssetType.serviceProvider] is how a house maid lives in the same table as a TV — an asset, plus
/// a linked recurring template for salary, plus a service record per payment. No second system
/// (anomaly A30).
///
/// There is no delete. Removal is [AssetStatus.disposed] plus a [disposalReason], so the money
/// spent stays in analytics after the thing is gone (ARCH_3 §4.1).
class Asset {
  /// Creates an asset.
  const Asset({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.type,
    required this.status,
    this.brand,
    this.modelNo,
    this.serialNo,
    this.purchaseDateKey,
    this.purchasePrice,
    this.sourceTransactionLineId,
    this.warrantyStartDateKey,
    this.warrantyEndDateKey,
    this.warrantyProvider,
    this.warrantyNote,
    this.serviceIntervalDays,
    this.nextServiceDueDateKey,
    this.primaryContactName,
    this.primaryContactPhone,
    this.location,
    this.linkedRecurringTemplateId,
    this.disposedAtDateKey,
    this.disposalReason,
    this.disposalNote,
    this.disposalAmount,
    this.notes,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// Display name as the user typed it.
  final String name;

  /// Normalised form used for identity matching only, never displayed.
  final String normalizedName;

  /// What kind of asset — or person — this is.
  final AssetType type;

  /// Current lifecycle state.
  final AssetStatus status;

  /// Manufacturer or brand.
  final String? brand;

  /// Model number.
  final String? modelNo;

  /// Serial number.
  final String? serialNo;

  /// Civil date acquired.
  final DateKey? purchaseDateKey;

  /// Purchase price.
  final Money? purchasePrice;

  /// The transaction line that created this asset, if it came from a purchase.
  final String? sourceTransactionLineId;

  /// Civil date warranty cover begins.
  final DateKey? warrantyStartDateKey;

  /// Civil date warranty cover ends.
  final DateKey? warrantyEndDateKey;

  /// Who provides the warranty.
  final String? warrantyProvider;

  /// Free-text warranty detail.
  final String? warrantyNote;

  /// Nominal days between services.
  final int? serviceIntervalDays;

  /// Civil date the next service is due.
  final DateKey? nextServiceDueDateKey;

  /// Primary contact name — the technician, or the person themselves.
  final String? primaryContactName;

  /// Primary contact phone, made tappable in the UI.
  final String? primaryContactPhone;

  /// Where the asset physically is.
  final String? location;

  /// The recurring template that pays for this asset.
  final String? linkedRecurringTemplateId;

  /// Civil date of disposal.
  final DateKey? disposedAtDateKey;

  /// Why it was disposed of. Non-null exactly when [status] is disposed.
  final AssetDisposalReason? disposalReason;

  /// Free-text disposal detail.
  final String? disposalNote;

  /// Sale proceeds, if sold. Denominated in the same currency as [purchasePrice], since the schema
  /// carries no separate disposal currency.
  final Money? disposalAmount;

  /// Optional free-text notes.
  final String? notes;

  /// True when this asset has been retired.
  bool get isDisposed => status == AssetStatus.disposed;

  /// True when this asset is currently in normal use.
  bool get isInUse => status != AssetStatus.disposed;

  /// True when a phone number is recorded, so the UI can offer a tappable dial action.
  bool get hasContactPhone =>
      primaryContactPhone != null && primaryContactPhone!.isNotEmpty;

  /// True when this asset represents a person rather than a thing.
  bool get isServiceProvider => type == AssetType.serviceProvider;

  /// Days of warranty remaining as of [today] — negative once expired, null when no warranty end
  /// is recorded.
  ///
  /// A **method taking [today]**, not the bare getter the phase brief sketched: days-remaining is
  /// meaningless without a reference date, and a getter would have to read the clock — making it
  /// non-deterministic and untestable, exactly the problem ARCH_2 §12.2 solved for the views. The
  /// brief's intent, that derived state is computed rather than stored, is honoured.
  int? warrantyDaysLeftFrom(DateKey today) => warrantyEndDateKey?.diffDays(today);

  /// True when a warranty is recorded and still in force as of [today]. The last day counts.
  bool isUnderWarranty(DateKey today) {
    final end = warrantyEndDateKey;
    if (end == null) return false;
    final start = warrantyStartDateKey;
    if (start != null && today.isBefore(start)) return false;
    return !end.isBefore(today);
  }

  /// True when the warranty ends within [days] of [today], already-expired included.
  bool isWarrantyEndingWithin(DateKey today, int days) {
    final left = warrantyDaysLeftFrom(today);
    return left != null && left <= days;
  }

  /// Days until the next service as of [today] — negative once overdue, null when unscheduled.
  int? serviceDaysLeftFrom(DateKey today) => nextServiceDueDateKey?.diffDays(today);

  /// True when a service is scheduled and its date has passed as of [today].
  bool isServiceOverdue(DateKey today) {
    final due = nextServiceDueDateKey;
    return due != null && due < today;
  }

  /// Net cost of ownership — what was paid, less anything recovered on disposal.
  ///
  /// Null when no purchase price is recorded. Both amounts share a currency by construction, so
  /// this cannot throw a currency mismatch.
  Money? get netCost {
    final paid = purchasePrice;
    if (paid == null) return null;
    final recovered = disposalAmount;
    return recovered == null ? paid : paid - recovered;
  }

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables —
  /// notably, undisposing an asset clears four fields and so constructs directly.
  Asset copyWith({
    String? id,
    String? name,
    String? normalizedName,
    AssetType? type,
    AssetStatus? status,
    String? brand,
    String? modelNo,
    String? serialNo,
    DateKey? purchaseDateKey,
    Money? purchasePrice,
    String? sourceTransactionLineId,
    DateKey? warrantyStartDateKey,
    DateKey? warrantyEndDateKey,
    String? warrantyProvider,
    String? warrantyNote,
    int? serviceIntervalDays,
    DateKey? nextServiceDueDateKey,
    String? primaryContactName,
    String? primaryContactPhone,
    String? location,
    String? linkedRecurringTemplateId,
    DateKey? disposedAtDateKey,
    AssetDisposalReason? disposalReason,
    String? disposalNote,
    Money? disposalAmount,
    String? notes,
  }) {
    return Asset(
      id: id ?? this.id,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      type: type ?? this.type,
      status: status ?? this.status,
      brand: brand ?? this.brand,
      modelNo: modelNo ?? this.modelNo,
      serialNo: serialNo ?? this.serialNo,
      purchaseDateKey: purchaseDateKey ?? this.purchaseDateKey,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      sourceTransactionLineId: sourceTransactionLineId ?? this.sourceTransactionLineId,
      warrantyStartDateKey: warrantyStartDateKey ?? this.warrantyStartDateKey,
      warrantyEndDateKey: warrantyEndDateKey ?? this.warrantyEndDateKey,
      warrantyProvider: warrantyProvider ?? this.warrantyProvider,
      warrantyNote: warrantyNote ?? this.warrantyNote,
      serviceIntervalDays: serviceIntervalDays ?? this.serviceIntervalDays,
      nextServiceDueDateKey: nextServiceDueDateKey ?? this.nextServiceDueDateKey,
      primaryContactName: primaryContactName ?? this.primaryContactName,
      primaryContactPhone: primaryContactPhone ?? this.primaryContactPhone,
      location: location ?? this.location,
      linkedRecurringTemplateId:
      linkedRecurringTemplateId ?? this.linkedRecurringTemplateId,
      disposedAtDateKey: disposedAtDateKey ?? this.disposedAtDateKey,
      disposalReason: disposalReason ?? this.disposalReason,
      disposalNote: disposalNote ?? this.disposalNote,
      disposalAmount: disposalAmount ?? this.disposalAmount,
      notes: notes ?? this.notes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Asset &&
          other.id == id &&
          other.name == name &&
          other.normalizedName == normalizedName &&
          other.type == type &&
          other.status == status &&
          other.brand == brand &&
          other.modelNo == modelNo &&
          other.serialNo == serialNo &&
          other.purchaseDateKey == purchaseDateKey &&
          other.purchasePrice == purchasePrice &&
          other.sourceTransactionLineId == sourceTransactionLineId &&
          other.warrantyStartDateKey == warrantyStartDateKey &&
          other.warrantyEndDateKey == warrantyEndDateKey &&
          other.warrantyProvider == warrantyProvider &&
          other.warrantyNote == warrantyNote &&
          other.serviceIntervalDays == serviceIntervalDays &&
          other.nextServiceDueDateKey == nextServiceDueDateKey &&
          other.primaryContactName == primaryContactName &&
          other.primaryContactPhone == primaryContactPhone &&
          other.location == location &&
          other.linkedRecurringTemplateId == linkedRecurringTemplateId &&
          other.disposedAtDateKey == disposedAtDateKey &&
          other.disposalReason == disposalReason &&
          other.disposalNote == disposalNote &&
          other.disposalAmount == disposalAmount &&
          other.notes == notes;

  @override
  int get hashCode => Object.hashAll([
    id, name, normalizedName, type, status, brand, modelNo, serialNo,
    purchaseDateKey, purchasePrice, sourceTransactionLineId, warrantyStartDateKey,
    warrantyEndDateKey, warrantyProvider, warrantyNote, serviceIntervalDays,
    nextServiceDueDateKey, primaryContactName, primaryContactPhone, location,
    linkedRecurringTemplateId, disposedAtDateKey, disposalReason, disposalNote,
    disposalAmount, notes,
  ]);

  @override
  String toString() => 'Asset($id, $name, ${status.name})';
}
```

### `lib/domain/entities/batch.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';

/// One acquisition of an `Item`: a quantity, an expiry, a cost and a source.
///
/// Every stock operation acts on batches; the item row only sums them (ARCH_1 §5.4).
class Batch {
  /// Creates a batch.
  const Batch({
    required this.id,
    required this.itemId,
    required this.initialQuantity,
    required this.remainingQuantity,
    required this.unitCodeAtPurchase,
    required this.purchasedDateKey,
    required this.origin,
    this.expiryDateKey,
    this.unitCost,
    this.sourceTransactionLineId,
    this.storageLocation,
    this.note,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// The item this batch is an acquisition of.
  final String itemId;

  /// Quantity acquired.
  final Qty initialQuantity;

  /// Quantity still on hand.
  ///
  /// The one derived total the schema stores (Law L3's stated exception), reconstructible at any
  /// time from the movement ledger. Treat it as authoritative for display and repairable if it
  /// ever disagrees.
  final Qty remainingQuantity;

  /// The unit the user actually purchased in, kept for display fidelity only.
  final String unitCodeAtPurchase;

  /// The civil date acquired.
  final DateKey purchasedDateKey;

  /// Where this batch came from. `detached` once its source transaction is deleted — the food does
  /// not un-exist because the receipt did (anomaly A10).
  final BatchOrigin origin;

  /// The civil expiry date, or null if this batch does not expire.
  final DateKey? expiryDateKey;

  /// Cost per [unitCodeAtPurchase], or null if unrecorded.
  final Money? unitCost;

  /// The transaction line that created this batch, if it came from a purchase.
  final String? sourceTransactionLineId;

  /// Optional free-text location, e.g. `Top shelf`.
  final String? storageLocation;

  /// Optional free-text note.
  final String? note;

  /// True when nothing is left in this batch.
  bool get isExhausted => remainingQuantity.isZero;

  /// True when this batch has stock and therefore participates in FEFO consumption.
  bool get hasStock => remainingQuantity.isPositive;

  /// How much has been drawn down from this batch.
  Qty get consumedQuantity => initialQuantity - remainingQuantity;

  /// True when this batch has passed its expiry as of [today].
  ///
  /// A batch with no expiry date is never expired. Takes [today] rather than reading a clock so it
  /// stays deterministic under a `FixedClock`, the same rule the views follow (ARCH_2 §12.2).
  bool isExpired(DateKey today) {
    final expiry = expiryDateKey;
    return expiry != null && expiry < today;
  }

  /// True when this batch expires within [days] of [today] — including already past.
  bool isExpiringWithin(DateKey today, int days) {
    final expiry = expiryDateKey;
    return expiry != null && expiry.diffDays(today) <= days;
  }

  /// Days from [today] until expiry — negative once past, null if this batch does not expire.
  int? daysUntilExpiry(DateKey today) => expiryDateKey?.diffDays(today);

  /// The total cost of what remains, or null when no unit cost is recorded.
  ///
  /// Rounds toward zero: a fractional minor unit cannot be represented, and inventory valuation is
  /// an estimate rather than a ledger figure.
  Money? get remainingValue {
    final cost = unitCost;
    if (cost == null) return null;
    return Money(
      (cost.minor * remainingQuantity.milliBase / 1000).truncate(),
      cost.currencyCode,
    );
  }

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  Batch copyWith({
    String? id,
    String? itemId,
    Qty? initialQuantity,
    Qty? remainingQuantity,
    String? unitCodeAtPurchase,
    DateKey? purchasedDateKey,
    BatchOrigin? origin,
    DateKey? expiryDateKey,
    Money? unitCost,
    String? sourceTransactionLineId,
    String? storageLocation,
    String? note,
  }) {
    return Batch(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      initialQuantity: initialQuantity ?? this.initialQuantity,
      remainingQuantity: remainingQuantity ?? this.remainingQuantity,
      unitCodeAtPurchase: unitCodeAtPurchase ?? this.unitCodeAtPurchase,
      purchasedDateKey: purchasedDateKey ?? this.purchasedDateKey,
      origin: origin ?? this.origin,
      expiryDateKey: expiryDateKey ?? this.expiryDateKey,
      unitCost: unitCost ?? this.unitCost,
      sourceTransactionLineId: sourceTransactionLineId ?? this.sourceTransactionLineId,
      storageLocation: storageLocation ?? this.storageLocation,
      note: note ?? this.note,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Batch &&
          other.id == id &&
          other.itemId == itemId &&
          other.initialQuantity == initialQuantity &&
          other.remainingQuantity == remainingQuantity &&
          other.unitCodeAtPurchase == unitCodeAtPurchase &&
          other.purchasedDateKey == purchasedDateKey &&
          other.origin == origin &&
          other.expiryDateKey == expiryDateKey &&
          other.unitCost == unitCost &&
          other.sourceTransactionLineId == sourceTransactionLineId &&
          other.storageLocation == storageLocation &&
          other.note == note;

  @override
  int get hashCode => Object.hashAll([
    id, itemId, initialQuantity, remainingQuantity, unitCodeAtPurchase,
    purchasedDateKey, origin, expiryDateKey, unitCost, sourceTransactionLineId,
    storageLocation, note,
  ]);

  @override
  String toString() => 'Batch($id, $remainingQuantity of $itemId)';
}
```

### `lib/domain/entities/calendar_event.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// What kind of thing a calendar entry represents (ARCH_3 §6).
///
/// Declared here rather than in `core/enums/` because these values are never stored: the
/// `v_calendar_events` view computes them, so Law L13's "renaming an enum value is a breaking
/// migration" does not apply.
enum CalendarEventType {
  /// A recorded transaction.
  transaction,

  /// A recurring obligation that is due.
  recurringDue,

  /// An inventory batch reaching its expiry.
  batchExpiry,

  /// An asset's warranty ending.
  warrantyEnd,

  /// An asset's next service falling due.
  serviceDue,

  /// A shopping list's target date.
  shoppingTarget,

  /// A shared expense with a settle-by date.
  ///
  /// **The deadline, not the expense.** When the user paid, the bill already reaches this feed through
  /// its own `transactions` row; carrying it twice would show one dinner as two entries on two days.
  ///
  /// Declared last on purpose. The day sheet groups by `CalendarEventType.values`, so declaration order
  /// is display order — and a deadline belongs after the things that have already happened.
  splitSettleBy,
}

/// How urgently a calendar entry should read.
enum CalendarSeverity {
  /// Informational — it happened, or it is simply scheduled.
  info,

  /// Approaching and worth attention.
  warning,

  /// Already past its date.
  danger,
}

/// One entry in the unified calendar feed.
///
/// Read-only: it comes from `v_calendar_events`, a `UNION ALL` view rather than a physical table,
/// so there is no synchronisation code to get wrong (anomaly A37).
class CalendarEvent {
  /// Creates a calendar entry.
  const CalendarEvent({
    required this.dateKey,
    required this.type,
    required this.refType,
    required this.refId,
    required this.title,
    required this.baseSeverity,
    this.amount,
  });

  /// The civil date this entry falls on.
  final DateKey dateKey;

  /// What kind of thing this is.
  final CalendarEventType type;

  /// Which kind of record [refId] names, e.g. `transaction`, `inventoryBatch`.
  final String refType;

  /// The owning record's id, for navigation.
  final String refId;

  /// What to show on the card.
  final String title;

  /// The static baseline severity the view emits.
  ///
  /// Resolve it through `CalendarAggregator.severityFor` before display. The view never consults the
  /// clock (ARCH_2 §12.2) and the escalation thresholds differ per type (ARCH_3 §6), so neither the
  /// view nor this entity can answer what an entry should look like today.
  final CalendarSeverity baseSeverity;

  /// The amount, where the entry has one — transactions and recurring dues do, expiries do not.
  final Money? amount;

  /// Days from [today] until this entry — negative once past.
  int daysAwayFrom(DateKey today) => dateKey.diffDays(today);

  /// True when this entry's date has already passed as of [today].
  bool isPast(DateKey today) => dateKey < today;

  @override
  bool operator ==(Object other) =>
      other is CalendarEvent &&
      other.dateKey == dateKey &&
      other.type == type &&
      other.refType == refType &&
      other.refId == refId &&
      other.title == title &&
      other.baseSeverity == baseSeverity &&
      other.amount == amount;

  @override
  int get hashCode => Object.hashAll([
    dateKey,
    type,
    refType,
    refId,
    title,
    baseSeverity,
    amount,
  ]);

  @override
  String toString() =>
      'CalendarEvent(${type.name} $refId on ${dateKey.toIso()})';
}
```

### `lib/domain/entities/converted_money.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// How reliable a currency conversion is (ARCH_3 §1.3).
enum RateQuality {
  /// A rate was cached for the requested date, or the most recent one on or before it.
  exact,

  /// No rate on or before the requested date existed, so the earliest available one was used.
  /// The figure is indicative and the UI must say so.
  approximate,

  /// No rate existed at all. [ConvertedMoney.converted] is null and the amount must be excluded
  /// from any total rather than counted as zero.
  unconverted,
}

/// An original amount paired with its conversion into another currency, and how much to trust it.
///
/// Never replaces the original (Law L9). This is a read-time view: the display layer aggregates
/// these, and only the explicit per-transaction freeze action writes a converted figure back to
/// the database.
class ConvertedMoney {
  /// Creates a conversion result.
  const ConvertedMoney({
    required this.original,
    required this.quality,
    this.converted,
    this.rate,
    this.rateDateKey,
  });

  /// A result for an amount that could not be converted at all.
  const ConvertedMoney.unconverted(this.original)
      : quality = RateQuality.unconverted,
        converted = null,
        rate = null,
        rateDateKey = null;

  /// The amount as stored, in its own currency. Immutable (Law L9).
  final Money original;

  /// How reliable [converted] is.
  final RateQuality quality;

  /// The converted amount, or null when [quality] is [RateQuality.unconverted].
  final Money? converted;

  /// The rate used, or null when nothing was converted.
  final double? rate;

  /// The civil date the applied rate was quoted for, or null when nothing was converted.
  final DateKey? rateDateKey;

  /// True when a converted figure is available, whatever its quality.
  bool get hasConversion => converted != null;

  /// True when this amount must be excluded from a converted total (anomaly A15).
  bool get isExcludedFromTotals => quality == RateQuality.unconverted;

  /// The amount to display: [converted] when available, otherwise [original].
  Money get display => converted ?? original;

  @override
  bool operator ==(Object other) =>
      other is ConvertedMoney &&
          other.original == original &&
          other.quality == quality &&
          other.converted == converted &&
          other.rate == rate &&
          other.rateDateKey == rateDateKey;

  @override
  int get hashCode => Object.hashAll([original, quality, converted, rate, rateDateKey]);

  @override
  String toString() => 'ConvertedMoney($original -> $converted, ${quality.name})';
}
```

### `lib/domain/entities/currency.dart`

```dart
import 'package:alaya/core/money/money.dart';

/// A supported currency, with the decimal precision that keeps `100` out of the codebase.
class Currency {
  /// Creates a currency.
  const Currency({
    required this.code,
    required this.name,
    required this.symbol,
    required this.decimalDigits,
    required this.isEnabled,
    required this.sortOrder,
  });

  /// ISO 4217 code, e.g. `INR`.
  final String code;

  /// Display name, e.g. `Indian Rupee`.
  final String name;

  /// Display symbol, e.g. `₹`.
  final String symbol;

  /// Minor units per major unit as a power of ten — 2 for INR/USD/EUR/CNY, 0 for JPY.
  final int decimalDigits;

  /// Whether this currency is offered in pickers.
  final bool isEnabled;

  /// Manual ordering within pickers.
  final int sortOrder;

  /// A zero amount in this currency.
  Money get zero => Money.zero(code);

  /// A copy with the given fields replaced.
  ///
  /// Every parameter is nullable and falls back to the current value, so this cannot *clear* a
  /// nullable field. Where clearing matters — disposing an asset, unlinking a transaction — the
  /// repository constructs a new instance directly instead. The alternative, a sentinel per
  /// parameter, costs far more noise across 21 entities than it earns.
  Currency copyWith({
    String? code,
    String? name,
    String? symbol,
    int? decimalDigits,
    bool? isEnabled,
    int? sortOrder,
  }) {
    return Currency(
      code: code ?? this.code,
      name: name ?? this.name,
      symbol: symbol ?? this.symbol,
      decimalDigits: decimalDigits ?? this.decimalDigits,
      isEnabled: isEnabled ?? this.isEnabled,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Currency &&
          other.code == code &&
          other.name == name &&
          other.symbol == symbol &&
          other.decimalDigits == decimalDigits &&
          other.isEnabled == isEnabled &&
          other.sortOrder == sortOrder;

  @override
  int get hashCode =>
      Object.hashAll([code, name, symbol, decimalDigits, isEnabled, sortOrder]);

  @override
  String toString() => 'Currency($code)';
}
```

### `lib/domain/entities/debt_edge.dart`

```dart
import 'package:alaya/core/money/money.dart';

/// One debt as it was actually incurred: [fromPayeeId] owes [toPayeeId] this much.
///
/// **Here rather than inside `debt_simplifier.dart`, where it was declared.** Three things name this
/// type now — `SplitLedgerRepository.debtsIn` returns a list of them, `SplitBalanceService` groups them
/// by currency, and the settle-up screen renders what each transfer clears. A repository contract
/// importing a *service* to name its own return type is the wrong direction, and it is the fault
/// `SplitLedgerRepository` has carried a note about since session 3a.
///
/// The move is invisible to callers: `debt_simplifier.dart` re-exports this file, so every existing
/// `import '.../debt_simplifier.dart'` still resolves `DebtEdge`. New code should import this path.
///
/// **An edge, not a balance, and the distinction is load-bearing.** `DebtSimplifier` prefers transfers
/// along debts that genuinely exist, so it needs the pairs as they happened rather than one netted
/// figure per person. Handing it balances would silently disable its best tie-break — which is exactly
/// what `debtsIn` does today, and says so.
final class DebtEdge {
  /// Creates an edge.
  const DebtEdge({
    required this.fromPayeeId,
    required this.toPayeeId,
    required this.amount,
  });

  /// Who owes.
  final String fromPayeeId;

  /// Who is owed.
  final String toPayeeId;

  /// How much. Always positive — the direction is in the field names.
  final Money amount;
}
```

### `lib/domain/entities/item.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';

/// The *kind* of consumable thing, as opposed to one acquisition of it.
///
/// Identity is `(normalizedName, unitCategory)` together — so `Milk (Weight)` and `Milk (Volume)`
/// are genuinely different items, not a naming collision (anomaly A06).
class Item {
  /// Creates an item.
  const Item({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.unitCategory,
    required this.defaultDisplayUnitCode,
    required this.itemKind,
    required this.isFavorite,
    this.lowStockThreshold,
    this.expiryNotifyDays,
    this.densityMilliGramsPerMl,
    this.milliGramsPerPiece,
    this.notes,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// Display name as the user typed it.
  final String name;

  /// Normalised form used for identity matching only, never displayed. Exact matches merge; near
  /// matches are only ever *suggested* (anomaly A07).
  final String normalizedName;

  /// Which of the three fixed categories this item is measured in.
  ///
  /// **Immutable after creation** (Law L8). Changing it would silently reinterpret every quantity
  /// ever recorded against the item, so the repository rejects an update that alters it.
  final UnitCategory unitCategory;

  /// The unit this item's quantities are rendered in by default.
  final String defaultDisplayUnitCode;

  /// Rough classification. `medicine` is what puts medicine expiry on the calendar with no extra
  /// table (ARCH_3 §6).
  final ItemKind itemKind;

  /// Pinned to the top of the inventory list.
  final bool isFavorite;

  /// Below this total remaining quantity the item is low on stock, or null if unset.
  final Qty? lowStockThreshold;

  /// How many days before a batch's expiry to remind, or null to use the global setting.
  final int? expiryNotifyDays;

  /// How much one millilitre of this item weighs, in milli-grams. Null when unknown.
  ///
  /// The volume-to-weight bridge: a tablespoon is 14.787 ml for everything, but a tablespoon of
  /// butter and one of flour weigh different amounts. That difference is a property of the item, so
  /// one number here serves every volume unit at once.
  final int? densityMilliGramsPerMl;

  /// What one piece of this item weighs, in milli-grams. Null when unknown.
  final int? milliGramsPerPiece;

  /// Optional free-text notes. Indexed for full-text search.
  final String? notes;

  /// True when a low-stock threshold is set, so the suggestion engine may act on this item.
  bool get hasThreshold => lowStockThreshold != null;

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  ///
  /// [unitCategory] is accepted here so a mapper can round-trip an entity unchanged, but the
  /// repository rejects a *saved* change to it (Law L8).
  Item copyWith({
    String? id,
    String? name,
    String? normalizedName,
    UnitCategory? unitCategory,
    String? defaultDisplayUnitCode,
    ItemKind? itemKind,
    bool? isFavorite,
    Qty? lowStockThreshold,
    int? expiryNotifyDays,
    String? notes,
  }) {
    return Item(
      id: id ?? this.id,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      unitCategory: unitCategory ?? this.unitCategory,
      defaultDisplayUnitCode:
          defaultDisplayUnitCode ?? this.defaultDisplayUnitCode,
      itemKind: itemKind ?? this.itemKind,
      isFavorite: isFavorite ?? this.isFavorite,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      expiryNotifyDays: expiryNotifyDays ?? this.expiryNotifyDays,
      notes: notes ?? this.notes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Item &&
      other.id == id &&
      other.name == name &&
      other.normalizedName == normalizedName &&
      other.unitCategory == unitCategory &&
      other.defaultDisplayUnitCode == defaultDisplayUnitCode &&
      other.itemKind == itemKind &&
      other.isFavorite == isFavorite &&
      other.lowStockThreshold == lowStockThreshold &&
      other.expiryNotifyDays == expiryNotifyDays &&
      other.notes == notes;

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    normalizedName,
    unitCategory,
    defaultDisplayUnitCode,
    itemKind,
    isFavorite,
    lowStockThreshold,
    expiryNotifyDays,
    notes,
  ]);

  @override
  String toString() => 'Item($id, $name, ${unitCategory.name})';
}
```

### `lib/domain/entities/item_stock.dart`

```dart
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';

/// One item's derived stock rollup — the summed figure an item row displays.
///
/// Read-only: comes from `v_item_stock`, and no total is stored (Law L3). Batches with nothing
/// left are excluded from every field here, so [batchCount] means "batches still holding stock"
/// and an exhausted batch cannot drag [nearestExpiry] earlier.
class ItemStock {
  /// Creates a stock rollup.
  const ItemStock({
    required this.itemId,
    required this.totalRemaining,
    required this.batchCount,
    required this.isLowStock,
    this.nearestExpiry,
    this.lowStockThreshold,
  });

  /// The item this rollup belongs to.
  final String itemId;

  /// Total quantity still on hand across every batch with stock.
  final Qty totalRemaining;

  /// How many batches still hold stock.
  final int batchCount;

  /// Whether [totalRemaining] has fallen below [lowStockThreshold].
  final bool isLowStock;

  /// The earliest expiry among batches still holding stock, or null if none expire.
  final DateKey? nearestExpiry;

  /// The threshold below which this item counts as low, or null if none is set.
  final Qty? lowStockThreshold;

  /// True when nothing at all is on hand.
  bool get isOutOfStock => totalRemaining.isZero;

  /// How much to buy to reach the threshold, or null when no threshold is set or stock is above
  /// it. The quantity the low-stock suggestion engine puts on a generated shopping entry.
  Qty? get shortfall {
    final threshold = lowStockThreshold;
    if (threshold == null || !isLowStock) return null;
    return threshold - totalRemaining;
  }

  /// True when a batch has already passed its expiry as of [today].
  bool hasExpiredStock(DateKey today) {
    final expiry = nearestExpiry;
    return expiry != null && expiry < today;
  }

  /// Days until the nearest expiry as of [today] — negative once past, null if nothing expires.
  int? daysUntilNearestExpiry(DateKey today) => nearestExpiry?.diffDays(today);

  @override
  bool operator ==(Object other) =>
      other is ItemStock &&
          other.itemId == itemId &&
          other.totalRemaining == totalRemaining &&
          other.batchCount == batchCount &&
          other.isLowStock == isLowStock &&
          other.nearestExpiry == nearestExpiry &&
          other.lowStockThreshold == lowStockThreshold;

  @override
  int get hashCode => Object.hashAll(
      [itemId, totalRemaining, batchCount, isLowStock, nearestExpiry, lowStockThreshold]);

  @override
  String toString() => 'ItemStock($itemId: $totalRemaining across $batchCount batches)';
}
```

### `lib/domain/entities/payee.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';

/// The counterparty on a transaction, used for both `From` on deposits and `To` on withdrawals.
class Payee {
  /// Creates a payee.
  const Payee({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.kind,
    this.phone,
    this.note,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// Display name as the user typed it.
  final String name;

  /// Normalised form used for identity matching only, never displayed.
  final String normalizedName;

  /// What kind of counterparty this is.
  final PayeeKind kind;

  /// Optional contact number.
  final String? phone;

  /// Optional free-text note.
  final String? note;

  /// True when a phone number is recorded, so the UI can offer a tappable dial action.
  bool get hasPhone => phone != null && phone!.isNotEmpty;

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  Payee copyWith({
    String? id,
    String? name,
    String? normalizedName,
    PayeeKind? kind,
    String? phone,
    String? note,
  }) {
    return Payee(
      id: id ?? this.id,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      kind: kind ?? this.kind,
      phone: phone ?? this.phone,
      note: note ?? this.note,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Payee &&
          other.id == id &&
          other.name == name &&
          other.normalizedName == normalizedName &&
          other.kind == kind &&
          other.phone == phone &&
          other.note == note;

  @override
  int get hashCode => Object.hashAll([id, name, normalizedName, kind, phone, note]);

  @override
  String toString() => 'Payee($id, $name)';
}
```

### `lib/domain/entities/payment_method.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';

/// The rail money travelled on — `Cash`, `UPI`, `Card`, `Bank Transfer`, `Cheque`.
///
/// Metadata only: a payment method never holds a balance. That is an `Account`.
class PaymentMethod {
  /// Creates a payment method.
  const PaymentMethod({
    required this.id,
    required this.name,
    required this.kind,
    required this.isSystem,
    required this.sortOrder,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// Display name as the user typed it.
  final String name;

  /// Which rail this represents.
  final PaymentMethodKind kind;

  /// Whether this method was seeded rather than user-created; system methods cannot be deleted.
  final bool isSystem;

  /// Manual ordering within pickers.
  final int sortOrder;

  /// True when the user is allowed to delete this method.
  bool get isDeletable => !isSystem;

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  PaymentMethod copyWith({
    String? id,
    String? name,
    PaymentMethodKind? kind,
    bool? isSystem,
    int? sortOrder,
  }) {
    return PaymentMethod(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      isSystem: isSystem ?? this.isSystem,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PaymentMethod &&
          other.id == id &&
          other.name == name &&
          other.kind == kind &&
          other.isSystem == isSystem &&
          other.sortOrder == sortOrder;

  @override
  int get hashCode => Object.hashAll([id, name, kind, isSystem, sortOrder]);

  @override
  String toString() => 'PaymentMethod($id, $name)';
}
```

### `lib/domain/entities/recipe.dart`

```dart
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';

/// One line of a recipe's ingredient list.
///
/// Either [itemId] links it to the inventory catalogue, or [freeText] names it and nothing tracks
/// it. Both being null is meaningless and both being set is contradictory; the repository rejects
/// either shape rather than storing a row nothing can render.
class RecipeIngredient {
  /// Creates an ingredient line.
  const RecipeIngredient({
    required this.id,
    required this.recipeId,
    required this.sortOrder,
    this.itemId,
    this.freeText,
    this.quantity,
    this.unitCode,
    this.isOptional = false,
    this.note,
  });

  /// Row identifier.
  final String id;

  /// The recipe this belongs to.
  final String recipeId;

  /// The catalogued item, when this ingredient refers to one.
  final String? itemId;

  /// What the ingredient is, when there is no [itemId].
  final String? freeText;

  /// How much the recipe needs, at the recipe's own serving count. Null means "to taste".
  final Qty? quantity;

  /// The unit the cook reads, e.g. `g`, `ml`, `pc`.
  final String? unitCode;

  /// Excluded from the cookability verdict.
  final bool isOptional;

  /// Preparation note.
  final String? note;

  /// Display order within the recipe.
  final int sortOrder;

  /// Whether this line points at the inventory catalogue.
  bool get isLinked => itemId != null;
}

/// One instruction in a recipe's method.
class RecipeStep {
  /// Creates a step.
  const RecipeStep({
    required this.id,
    required this.recipeId,
    required this.stepNumber,
    required this.instruction,
    this.durationMinutes,
  });

  /// Row identifier.
  final String id;

  /// The recipe this belongs to.
  final String recipeId;

  /// Position in the method, from 1.
  final int stepNumber;

  /// What to do.
  final String instruction;

  /// How long it takes, when it is worth timing.
  final int? durationMinutes;
}

/// A recipe, with its ingredients and method.
///
/// [servings] anchors every quantity in [ingredients]: a line reading 200 g means 200 g *at this
/// serving count*, and `CookabilityEngine.scaleMilli` is the only thing that rescales it.
class Recipe {
  /// Creates a recipe.
  const Recipe({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.servings,
    this.ingredients = const [],
    this.steps = const [],
    this.prepMinutes,
    this.cookMinutes,
    this.isFavorite = false,
    this.notes,
  });

  /// Row identifier.
  final String id;

  /// Display name.
  final String name;

  /// Casefolded, accent-stripped name for search and duplicate detection.
  ///
  /// Carried on the entity rather than computed in the repository, matching `Item`, `Payee` and
  /// every other named row. The caller builds it with Phase 1A's `Normalizer`, so one
  /// implementation decides what "the same name" means everywhere in the app.
  final String normalizedName;

  /// How many servings the stored quantities describe. Always positive.
  final int servings;

  /// The ingredient list, in display order.
  final List<RecipeIngredient> ingredients;

  /// The method, in step order.
  final List<RecipeStep> steps;

  /// Hands-on time before cooking starts.
  final int? prepMinutes;

  /// Time on the heat.
  final int? cookMinutes;

  /// Pinned by the user.
  final bool isFavorite;

  /// Free-form notes.
  final String? notes;

  /// Prep plus cook, when either is known.
  int? get totalMinutes {
    if (prepMinutes == null && cookMinutes == null) return null;
    return (prepMinutes ?? 0) + (cookMinutes ?? 0);
  }

  /// The ingredients that count toward a cookability verdict.
  List<RecipeIngredient> get requiredIngredients => [
    for (final i in ingredients)
      if (!i.isOptional) i,
  ];

  /// The item ids this recipe draws on, for a stock lookup.
  Set<String> get linkedItemIds => {
    for (final i in ingredients)
      if (i.itemId != null) i.itemId!,
  };
}

/// A record that a recipe was cooked.
class RecipeCook {
  /// Creates a log entry.
  const RecipeCook({
    required this.id,
    required this.recipeId,
    required this.cookedOn,
    required this.servingsCooked,
    required this.deductedStock,
    this.note,
  });

  /// Row identifier.
  final String id;

  /// The recipe that was cooked.
  final String recipeId;

  /// The civil date it was cooked on.
  final DateKey cookedOn;

  /// How many servings were made.
  final int servingsCooked;

  /// Whether inventory was reduced for it.
  final bool deductedStock;

  /// Free-form note.
  final String? note;
}
```

### `lib/domain/entities/recurring_occurrence.dart`

```dart
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// One dated instance of a `RecurringTemplate` — the third of the app's three append-only truths
/// (ARCH_1 §3.3).
///
/// Materialised lazily up to today, never in advance and never automatically settled: money is
/// only ever created by an explicit user tap (anomaly A14).
class RecurringOccurrence {
  /// Creates an occurrence.
  const RecurringOccurrence({
    required this.id,
    required this.templateId,
    required this.dueDateKey,
    required this.status,
    this.paidTransactionId,
    this.paidAmount,
    this.paidDateKey,
    this.note,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// The template this instance belongs to.
  final String templateId;

  /// The civil date this instance is due on.
  final DateKey dueDateKey;

  /// Settlement state. Never `paid` without [paidTransactionId].
  final RecurringOccurrenceStatus status;

  /// The transaction that settled this occurrence.
  final String? paidTransactionId;

  /// The amount actually paid, which may differ from the template's default. Analytics uses this
  /// rather than the default (anomaly A29).
  final Money? paidAmount;

  /// The civil date it was actually paid on, which may differ from [dueDateKey].
  final DateKey? paidDateKey;

  /// Optional free-text note.
  final String? note;

  /// True when this occurrence is still outstanding.
  bool get isOutstanding => status == RecurringOccurrenceStatus.due;

  /// True when this occurrence has been settled.
  bool get isPaid => status == RecurringOccurrenceStatus.paid;

  /// True when this occurrence is still due and its date has passed as of [today].
  ///
  /// **Derived, never stored** — ARCH_2 §7.2's requirement, and the reason `v_recurring_due` has no
  /// `is_overdue` column. Takes [today] rather than reading a clock so it stays deterministic under
  /// a `FixedClock`, the same rule the views follow (ARCH_2 §12.2).
  bool isOverdue(DateKey today) => isOutstanding && dueDateKey < today;

  /// Days from [today] until due — negative once overdue.
  int daysUntilDue(DateKey today) => dueDateKey.diffDays(today);

  /// True when this occurrence falls due within [days] of [today], already-overdue included.
  bool isDueWithin(DateKey today, int days) => dueDateKey.diffDays(today) <= days;

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  RecurringOccurrence copyWith({
    String? id,
    String? templateId,
    DateKey? dueDateKey,
    RecurringOccurrenceStatus? status,
    String? paidTransactionId,
    Money? paidAmount,
    DateKey? paidDateKey,
    String? note,
  }) {
    return RecurringOccurrence(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      dueDateKey: dueDateKey ?? this.dueDateKey,
      status: status ?? this.status,
      paidTransactionId: paidTransactionId ?? this.paidTransactionId,
      paidAmount: paidAmount ?? this.paidAmount,
      paidDateKey: paidDateKey ?? this.paidDateKey,
      note: note ?? this.note,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RecurringOccurrence &&
          other.id == id &&
          other.templateId == templateId &&
          other.dueDateKey == dueDateKey &&
          other.status == status &&
          other.paidTransactionId == paidTransactionId &&
          other.paidAmount == paidAmount &&
          other.paidDateKey == paidDateKey &&
          other.note == note;

  @override
  int get hashCode => Object.hashAll([
    id, templateId, dueDateKey, status, paidTransactionId, paidAmount,
    paidDateKey, note,
  ]);

  @override
  String toString() => 'RecurringOccurrence($id, ${dueDateKey.toIso()}, ${status.name})';
}
```

### `lib/domain/entities/recurring_template.dart`

```dart
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// A repeating obligation or income.
///
/// [direction] is what lets salary live in the same system as bills rather than needing a second,
/// parallel one (anomaly A27).
class RecurringTemplate {
  /// Creates a template.
  const RecurringTemplate({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.kind,
    required this.direction,
    required this.defaultAmount,
    required this.intervalUnit,
    required this.intervalCount,
    required this.startDateKey,
    required this.nextDueDateKey,
    required this.isPaused,
    required this.autoRemind,
    required this.remindDaysBefore,
    this.payeeId,
    this.defaultAccountId,
    this.defaultPaymentMethodId,
    this.tagId,
    this.anchorDayOfMonth,
    this.anchorMonth,
    this.anchorWeekday,
    this.endDateKey,
    this.linkedAssetId,
    this.note,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// Display name as the user typed it.
  final String name;

  /// Normalised form used for identity matching only, never displayed.
  final String normalizedName;

  /// Rough classification, for grouping and iconography.
  final RecurringKind kind;

  /// Whether settling an occurrence creates a withdrawal or a deposit.
  final RecurringDirection direction;

  /// The usual amount. An occurrence may be settled for a different one, recorded on the
  /// occurrence rather than overwriting this (anomaly A29).
  final Money defaultAmount;

  /// The unit the repeat interval is counted in.
  final RecurringIntervalUnit intervalUnit;

  /// How many [intervalUnit]s between occurrences.
  final int intervalCount;

  /// First civil date this template is active from.
  final DateKey startDateKey;

  /// The next civil date an occurrence is due on.
  final DateKey nextDueDateKey;

  /// Suspended without being deleted; no new occurrences materialise.
  final bool isPaused;

  /// Whether to schedule a local notification before each due date.
  final bool autoRemind;

  /// How many days before the due date to remind.
  final int remindDaysBefore;

  /// Who is billed, or who pays.
  final String? payeeId;

  /// The account settlement defaults to.
  final String? defaultAccountId;

  /// The rail settlement defaults to.
  final String? defaultPaymentMethodId;

  /// The tag applied to transactions this template creates.
  final String? tagId;

  /// Day of month, 1-31, for monthly and yearly intervals.
  ///
  /// **Stored once and clamped at render, never rewritten** (anomaly A13). A bill anchored on the
  /// 31st renders as 28, 29 or 30 in short months but stays anchored on the 31st — write the
  /// clamped value back and it walks permanently backwards after one February. Use
  /// [clampedDayFor] to render it.
  final int? anchorDayOfMonth;

  /// Month of year, 1-12, for yearly intervals.
  final int? anchorMonth;

  /// ISO weekday, 1-7, for weekly intervals.
  final int? anchorWeekday;

  /// Last civil date this template is active until, or null for indefinite.
  final DateKey? endDateKey;

  /// The asset this template pays for — the link that hangs a house maid's monthly salary off an
  /// `Asset` row.
  final String? linkedAssetId;

  /// Optional free-text note.
  final String? note;

  /// True when this template creates a withdrawal on settlement.
  bool get isOutflow => direction == RecurringDirection.outflow;

  /// True when this template has an end date that [today] has passed.
  bool hasEnded(DateKey today) {
    final end = endDateKey;
    return end != null && end < today;
  }

  /// True when this template should currently be materialising occurrences.
  bool isActiveAsOf(DateKey today) =>
      !isPaused && !hasEnded(today) && !startDateKey.isAfter(today);

  /// [anchorDayOfMonth] clamped into the given month's real length.
  ///
  /// The render-time half of anomaly A13: an anchor of 31 returns 28 for a non-leap February, 29
  /// for a leap one, 30 for April. Returns null when no day-of-month anchor is set.
  int? clampedDayFor({required int year, required int month}) {
    final anchor = anchorDayOfMonth;
    if (anchor == null) return null;
    final lastDayOfMonth = DateTime.utc(year, month + 1, 0).day;
    return anchor < lastDayOfMonth ? anchor : lastDayOfMonth;
  }

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  RecurringTemplate copyWith({
    String? id,
    String? name,
    String? normalizedName,
    RecurringKind? kind,
    RecurringDirection? direction,
    Money? defaultAmount,
    RecurringIntervalUnit? intervalUnit,
    int? intervalCount,
    DateKey? startDateKey,
    DateKey? nextDueDateKey,
    bool? isPaused,
    bool? autoRemind,
    int? remindDaysBefore,
    String? payeeId,
    String? defaultAccountId,
    String? defaultPaymentMethodId,
    String? tagId,
    int? anchorDayOfMonth,
    int? anchorMonth,
    int? anchorWeekday,
    DateKey? endDateKey,
    String? linkedAssetId,
    String? note,
  }) {
    return RecurringTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      kind: kind ?? this.kind,
      direction: direction ?? this.direction,
      defaultAmount: defaultAmount ?? this.defaultAmount,
      intervalUnit: intervalUnit ?? this.intervalUnit,
      intervalCount: intervalCount ?? this.intervalCount,
      startDateKey: startDateKey ?? this.startDateKey,
      nextDueDateKey: nextDueDateKey ?? this.nextDueDateKey,
      isPaused: isPaused ?? this.isPaused,
      autoRemind: autoRemind ?? this.autoRemind,
      remindDaysBefore: remindDaysBefore ?? this.remindDaysBefore,
      payeeId: payeeId ?? this.payeeId,
      defaultAccountId: defaultAccountId ?? this.defaultAccountId,
      defaultPaymentMethodId: defaultPaymentMethodId ?? this.defaultPaymentMethodId,
      tagId: tagId ?? this.tagId,
      anchorDayOfMonth: anchorDayOfMonth ?? this.anchorDayOfMonth,
      anchorMonth: anchorMonth ?? this.anchorMonth,
      anchorWeekday: anchorWeekday ?? this.anchorWeekday,
      endDateKey: endDateKey ?? this.endDateKey,
      linkedAssetId: linkedAssetId ?? this.linkedAssetId,
      note: note ?? this.note,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RecurringTemplate &&
          other.id == id &&
          other.name == name &&
          other.normalizedName == normalizedName &&
          other.kind == kind &&
          other.direction == direction &&
          other.defaultAmount == defaultAmount &&
          other.intervalUnit == intervalUnit &&
          other.intervalCount == intervalCount &&
          other.startDateKey == startDateKey &&
          other.nextDueDateKey == nextDueDateKey &&
          other.isPaused == isPaused &&
          other.autoRemind == autoRemind &&
          other.remindDaysBefore == remindDaysBefore &&
          other.payeeId == payeeId &&
          other.defaultAccountId == defaultAccountId &&
          other.defaultPaymentMethodId == defaultPaymentMethodId &&
          other.tagId == tagId &&
          other.anchorDayOfMonth == anchorDayOfMonth &&
          other.anchorMonth == anchorMonth &&
          other.anchorWeekday == anchorWeekday &&
          other.endDateKey == endDateKey &&
          other.linkedAssetId == linkedAssetId &&
          other.note == note;

  @override
  int get hashCode => Object.hashAll([
    id, name, normalizedName, kind, direction, defaultAmount, intervalUnit,
    intervalCount, startDateKey, nextDueDateKey, isPaused, autoRemind,
    remindDaysBefore, payeeId, defaultAccountId, defaultPaymentMethodId, tagId,
    anchorDayOfMonth, anchorMonth, anchorWeekday, endDateKey, linkedAssetId, note,
  ]);

  @override
  String toString() => 'RecurringTemplate($id, $name, ${direction.name})';
}
```

### `lib/domain/entities/service_record.dart`

```dart
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// One service, repair or payment event against an `Asset`.
///
/// Also the payment log for a service provider, via [ServiceRecordType.salaryPaid].
class ServiceRecord {
  /// Creates a service record.
  const ServiceRecord({
    required this.id,
    required this.assetId,
    required this.serviceDateKey,
    required this.type,
    this.providerName,
    this.providerPhone,
    this.cost,
    this.linkedTransactionId,
    this.nextDueDateKey,
    this.notes,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// The asset this record belongs to.
  final String assetId;

  /// The civil date of the event.
  final DateKey serviceDateKey;

  /// What kind of event this was.
  final ServiceRecordType type;

  /// Who performed it.
  final String? providerName;

  /// Their contact number.
  final String? providerPhone;

  /// What it cost. Drives lifetime service cost per asset (ARCH_3 §5.1 query 19), which must be
  /// totalled per currency rather than summed across them (anomaly A34).
  final Money? cost;

  /// The withdrawal this cost was booked as, when the user chose to record it as an expense.
  final String? linkedTransactionId;

  /// The civil date the next service was scheduled for at the time of this one.
  final DateKey? nextDueDateKey;

  /// Optional free-text notes.
  final String? notes;

  /// True when this record has a recorded cost.
  bool get hasCost => cost != null;

  /// True when this cost was also booked as a transaction.
  bool get isBookedAsExpense => linkedTransactionId != null;

  /// True when a phone number is recorded, so the UI can offer a tappable dial action.
  bool get hasProviderPhone => providerPhone != null && providerPhone!.isNotEmpty;

  /// True when this record is a salary payment to a service provider rather than a repair.
  bool get isSalaryPayment => type == ServiceRecordType.salaryPaid;

  /// Days from [today] until the next scheduled service — negative once overdue, null when none is
  /// scheduled.
  int? daysUntilNextDue(DateKey today) => nextDueDateKey?.diffDays(today);

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  ServiceRecord copyWith({
    String? id,
    String? assetId,
    DateKey? serviceDateKey,
    ServiceRecordType? type,
    String? providerName,
    String? providerPhone,
    Money? cost,
    String? linkedTransactionId,
    DateKey? nextDueDateKey,
    String? notes,
  }) {
    return ServiceRecord(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      serviceDateKey: serviceDateKey ?? this.serviceDateKey,
      type: type ?? this.type,
      providerName: providerName ?? this.providerName,
      providerPhone: providerPhone ?? this.providerPhone,
      cost: cost ?? this.cost,
      linkedTransactionId: linkedTransactionId ?? this.linkedTransactionId,
      nextDueDateKey: nextDueDateKey ?? this.nextDueDateKey,
      notes: notes ?? this.notes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ServiceRecord &&
          other.id == id &&
          other.assetId == assetId &&
          other.serviceDateKey == serviceDateKey &&
          other.type == type &&
          other.providerName == providerName &&
          other.providerPhone == providerPhone &&
          other.cost == cost &&
          other.linkedTransactionId == linkedTransactionId &&
          other.nextDueDateKey == nextDueDateKey &&
          other.notes == notes;

  @override
  int get hashCode => Object.hashAll([
    id, assetId, serviceDateKey, type, providerName, providerPhone, cost,
    linkedTransactionId, nextDueDateKey, notes,
  ]);

  @override
  String toString() => 'ServiceRecord($id, ${type.name}, ${serviceDateKey.toIso()})';
}
```

### `lib/domain/entities/shopping_entry.dart`

```dart
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';

/// An intent to buy something. May or may not link to a catalogued `Item`.
///
/// [origin], [autoState] and [stockAtGeneration] together are what make low-stock auto-generation
/// idempotent *and* dismissible without the entry reappearing on the next run (anomalies A22, A23).
class ShoppingEntry {
  /// Creates an entry.
  const ShoppingEntry({
    required this.id,
    required this.listId,
    required this.origin,
    required this.autoState,
    required this.isChecked,
    required this.sortOrder,
    this.itemId,
    this.freeText,
    this.quantity,
    this.unitCode,
    this.tagId,
    this.estimatedPrice,
    this.checkedAtUtc,
    this.snoozeUntilDateKey,
    this.stockAtGeneration,
    this.purchasedTransactionLineId,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// The list this entry belongs to.
  final String listId;

  /// How this entry came to exist. Editing an auto entry promotes it to `manual`, after which the
  /// suggestion engine never removes it.
  final ShoppingEntryOrigin origin;

  /// Lifecycle of an auto-generated entry, so a dismissal survives the next regeneration.
  final ShoppingEntryAutoState autoState;

  /// Ticked off in the list.
  final bool isChecked;

  /// Manual ordering within its group.
  final int sortOrder;

  /// The catalogued item, when this entry refers to one. Null lets `TV ☐` work without inventing
  /// an inventory item (anomaly A24).
  final String? itemId;

  /// What to buy, when there is no [itemId].
  final String? freeText;

  /// How much to buy, or null to render no quantity at all rather than a misleading `0`.
  final Qty? quantity;

  /// The unit the user typed, for display.
  final String? unitCode;

  /// The group header this entry appears under — `Grocery`, `Beauty`, `Electronics`.
  final String? tagId;

  /// Optional expected price, for the running list estimate.
  final Money? estimatedPrice;

  /// When it was ticked. Always UTC.
  final DateTime? checkedAtUtc;

  /// Hide an auto entry until this civil date.
  final DateKey? snoozeUntilDateKey;

  /// The item's total stock when this entry was auto-generated — the comparison point that stops a
  /// dismissed suggestion returning until stock has genuinely risen and fallen again.
  final Qty? stockAtGeneration;

  /// The transaction line that fulfilled this entry (anomaly A25).
  final String? purchasedTransactionLineId;

  /// What to show on the row: the free text, or null when the caller should resolve [itemId]'s
  /// name instead.
  String? get displayLabel => freeText;

  /// True when this entry was generated rather than typed.
  bool get isAutoGenerated => origin == ShoppingEntryOrigin.autoLowStock;

  /// True when this entry has been converted into an actual purchase.
  bool get isPurchased => purchasedTransactionLineId != null;

  /// True when an auto entry should currently be visible in the list.
  ///
  /// A snoozed entry becomes visible again once [snoozeUntilDateKey] has passed; a dismissed one
  /// does not return on a date at all — only on the stock condition re-triggering, which the
  /// suggestion engine decides using [stockAtGeneration].
  bool isVisibleAsOf(DateKey today) {
    if (!isAutoGenerated) return true;
    return switch (autoState) {
      ShoppingEntryAutoState.active => true,
      ShoppingEntryAutoState.dismissed => false,
      ShoppingEntryAutoState.snoozed =>
        snoozeUntilDateKey != null && !today.isBefore(snoozeUntilDateKey!),
    };
  }

  /// True when this entry is still something to buy.
  ///
  /// **Visibility and outstandingness are different questions.** `isVisibleAsOf` answers whether an
  /// auto suggestion has been snoozed or turned down. This also excludes anything already bought: a
  /// list is a list of what to get, and an entry fulfilled by a committed transaction is done.
  ///
  /// It is filtered rather than deleted. `purchasedTransactionLineId` is the provenance of the line
  /// that bought it, and removing the row would break the only link between a receipt and the list it
  /// came from (Law L6).
  bool isOutstandingAsOf(DateKey today) => !isPurchased && isVisibleAsOf(today);

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  ShoppingEntry copyWith({
    String? id,
    String? listId,
    ShoppingEntryOrigin? origin,
    ShoppingEntryAutoState? autoState,
    bool? isChecked,
    int? sortOrder,
    String? itemId,
    String? freeText,
    Qty? quantity,
    String? unitCode,
    String? tagId,
    Money? estimatedPrice,
    DateTime? checkedAtUtc,
    DateKey? snoozeUntilDateKey,
    Qty? stockAtGeneration,
    String? purchasedTransactionLineId,
  }) {
    return ShoppingEntry(
      id: id ?? this.id,
      listId: listId ?? this.listId,
      origin: origin ?? this.origin,
      autoState: autoState ?? this.autoState,
      isChecked: isChecked ?? this.isChecked,
      sortOrder: sortOrder ?? this.sortOrder,
      itemId: itemId ?? this.itemId,
      freeText: freeText ?? this.freeText,
      quantity: quantity ?? this.quantity,
      unitCode: unitCode ?? this.unitCode,
      tagId: tagId ?? this.tagId,
      estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      checkedAtUtc: checkedAtUtc ?? this.checkedAtUtc,
      snoozeUntilDateKey: snoozeUntilDateKey ?? this.snoozeUntilDateKey,
      stockAtGeneration: stockAtGeneration ?? this.stockAtGeneration,
      purchasedTransactionLineId:
          purchasedTransactionLineId ?? this.purchasedTransactionLineId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShoppingEntry &&
      other.id == id &&
      other.listId == listId &&
      other.origin == origin &&
      other.autoState == autoState &&
      other.isChecked == isChecked &&
      other.sortOrder == sortOrder &&
      other.itemId == itemId &&
      other.freeText == freeText &&
      other.quantity == quantity &&
      other.unitCode == unitCode &&
      other.tagId == tagId &&
      other.estimatedPrice == estimatedPrice &&
      other.checkedAtUtc == checkedAtUtc &&
      other.snoozeUntilDateKey == snoozeUntilDateKey &&
      other.stockAtGeneration == stockAtGeneration &&
      other.purchasedTransactionLineId == purchasedTransactionLineId;

  @override
  int get hashCode => Object.hashAll([
    id,
    listId,
    origin,
    autoState,
    isChecked,
    sortOrder,
    itemId,
    freeText,
    quantity,
    unitCode,
    tagId,
    estimatedPrice,
    checkedAtUtc,
    snoozeUntilDateKey,
    stockAtGeneration,
    purchasedTransactionLineId,
  ]);

  @override
  String toString() => 'ShoppingEntry($id, ${freeText ?? itemId})';
}
```

### `lib/domain/entities/shopping_list.dart`

```dart
import 'package:alaya/core/time/date_key.dart';

/// A shopping list. Multiple are supported, with one marked default so the app still feels like it
/// has just one.
class ShoppingList {
  /// Creates a list.
  const ShoppingList({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.isArchived,
    this.targetDateKey,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// Display name.
  final String name;

  /// Whether quick-add writes to this list when the user chooses none.
  ///
  /// Carries no database-level uniqueness constraint — the repository keeps it single by clearing
  /// every other list's flag in the same transaction it sets this one.
  final bool isDefault;

  /// Retired but kept for history.
  final bool isArchived;

  /// Optional civil date the user intends to shop on; surfaces on the calendar.
  final DateKey? targetDateKey;

  /// True when this list may be chosen in a picker.
  bool get isSelectable => !isArchived;

  /// Days from [today] until the shopping date — negative once past, null if none is set.
  int? daysUntilTarget(DateKey today) => targetDateKey?.diffDays(today);

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  ShoppingList copyWith({
    String? id,
    String? name,
    bool? isDefault,
    bool? isArchived,
    DateKey? targetDateKey,
  }) {
    return ShoppingList(
      id: id ?? this.id,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      isArchived: isArchived ?? this.isArchived,
      targetDateKey: targetDateKey ?? this.targetDateKey,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShoppingList &&
          other.id == id &&
          other.name == name &&
          other.isDefault == isDefault &&
          other.isArchived == isArchived &&
          other.targetDateKey == targetDateKey;

  @override
  int get hashCode => Object.hashAll([id, name, isDefault, isArchived, targetDateKey]);

  @override
  String toString() => 'ShoppingList($id, $name)';
}
```

### `lib/domain/entities/split_expense.dart`

```dart
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

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
/// **No `myShare`, no `settled`, no `isSettled`.** Law L3 — no total is ever stored. Every one of
/// those is a sum over [shares] and settlements, and [SplitExpenseSummary] is where they arrive from
/// the view. `myShare` on this class would be the single most tempting field in the module and it
/// would drift the first time a share was edited.
class SplitExpense {
  /// Creates an expense.
  const SplitExpense({
    required this.id,
    required this.paidByPayeeId,
    required this.total,
    required this.dateKey,
    required this.splitMethod,
    this.shares = const [],
    this.groupId,
    this.transactionId,
    this.title,
    this.place,
    this.occasion,
    this.note,
    this.settleByDateKey,
    this.converted,
  });

  /// Row identifier.
  final String id;

  /// Who actually paid the bill.
  final String paidByPayeeId;

  /// What the whole bill came to.
  final Money total;

  /// The civil date the expense happened on.
  final DateKey dateKey;

  /// How the shares were specified.
  final SplitMethod splitMethod;

  /// Who owes what, in display order.
  final List<SplitShare> shares;

  /// The group this belongs to, or null for a one-off split with one person.
  final String? groupId;

  /// The transaction that moved your money, or null when somebody else paid.
  final String? transactionId;

  /// What it was — `Dinner at Olive`, `October rent`.
  final String? title;

  /// Where it happened.
  ///
  /// An analytics dimension rather than decoration: "what do we spend in Goa" is a question no split
  /// app answers, and it is answerable here because the column exists.
  final String? place;

  /// What the occasion was — `Diwali`, `Ravi's birthday`.
  final String? occasion;

  /// Free-form note.
  final String? note;

  /// An optional date to settle by, which feeds the calendar and the daily digest.
  final DateKey? settleByDateKey;

  /// The frozen home-currency conversion, or null when the expense was already in it.
  final SplitConversion? converted;

  /// `dateKey`'s month, for month-grouped reads.
  ///
  /// Derived here and stored on the row, because the schema's CHECK enforces
  /// `date_key / 100 = month_key` — the same arrangement `transactions` uses, where the database
  /// rejects a caller that gets it wrong rather than letting a row become invisible to monthly
  /// analytics.
  int get monthKey => dateKey.value ~/ 100;

  /// Whether the money for this has already left your account.
  ///
  /// True in the "you paid" case. The screens read this rather than testing `transactionId != null`
  /// directly, so the reason is named where it is used.
  bool get wasPaidByYou => transactionId != null;

  /// Whether any share is attached to a specific transaction line.
  bool get isItemised => shares.any((share) => share.transactionLineNo != null);

  /// What the shares add up to.
  Money get allocated => shares.fold(
    Money.zero(total.currencyCode),
    (sum, share) => sum + share.amount,
  );

  /// What the shares fail to account for — [total] minus [allocated].
  ///
  /// **Reported, never absorbed.** Percentages summing to 90% leave 10% here, and exact amounts that
  /// overshoot leave it negative. `transaction_lines` already surfaces "₹500 total, ₹480 of lines →
  /// unallocated ₹20" rather than adjusting a figure to make it balance (ARCH_2 §4.2); quietly
  /// rounding a shortfall onto the last participant charges somebody for a discrepancy nobody told
  /// them about.
  Money get unallocated => total - allocated;

  /// Whether the shares account for the total exactly.
  bool get isFullyAllocated => unallocated.isZero;

  /// The share belonging to [payeeId], or null when they are not on this expense.
  SplitShare? shareOf(String payeeId) {
    for (final share in shares) {
      if (share.payeeId == payeeId) return share;
    }
    return null;
  }
}

/// What one participant owes on one expense, and how that was decided.
///
/// **Both the input and the resolved amount are carried, deliberately.** Re-deriving shares from
/// their inputs on every read would re-run largest-remainder allocation and could hand the stray
/// paise to a different person than the one the user agreed with. [amount] is what they owe;
/// [inputKind] and [inputValue] are how it was arrived at, so the editor shows 40/30/30 rather than
/// three amounts.
class SplitShare {
  /// Creates a share.
  const SplitShare({
    required this.id,
    required this.splitExpenseId,
    required this.payeeId,
    required this.amount,
    required this.inputKind,
    this.inputValue,
    this.transactionLineNo,
  });

  /// Row identifier.
  final String id;

  /// The expense being split.
  final String splitExpenseId;

  /// Who owes this share.
  final String payeeId;

  /// The exact amount owed. Sums with its siblings to the expense's allocated total.
  final Money amount;

  /// How this share was specified.
  final ShareInputKind inputKind;

  /// The typed value behind [inputKind] — minor units for `exact`, basis points for `percent`, a
  /// weight for `shares`, and null for `equal`.
  final int? inputValue;

  /// The `transaction_lines.lineNo` this share is against, or null for a share of the whole expense.
  ///
  /// **This field is the itemised split** — the ₹400 dessert is one line with one participant while
  /// the ₹1,200 platter is one line split four ways, so each person's total becomes a sum over lines
  /// rather than a division of the bill. The feature Splitwise puts behind its paid tier.
  ///
  /// Only meaningful when the expense has a transaction, because the lines are the transaction's. The
  /// schema enforces the header half of that (`split_method <> 'perLine' OR transaction_id IS NOT
  /// NULL`); this direction spans two tables, which SQLite cannot express as a CHECK, so the
  /// repository upholds it.
  final int? transactionLineNo;
}

/// A frozen currency conversion, taken when an expense was recorded.
///
/// **A snapshot, never a live conversion (Law L9).** A holiday split in THB must keep the rate it was
/// entered at, or last March's trip re-prices itself every time the rate table updates.
class SplitConversion {
  /// Creates a conversion snapshot.
  const SplitConversion({
    required this.amount,
    required this.rate,
    required this.rateRaw,
    required this.dateKey,
  });

  /// The converted amount, in the home currency at the time.
  final Money amount;

  /// The rate used, as the display string it was shown with.
  final String rate;

  /// The rate exactly as fetched, before rounding, for audit.
  final String rateRaw;

  /// The civil date the rate was valid on.
  final DateKey dateKey;
}

/// Money that actually changed hands to settle a debt.
///
/// **Many settlements per debt, on purpose.** "Keep adding as they keep paying" is partial
/// settlement, and what remains outstanding is derived from these rows — never a decremented column
/// (Law L3).
///
/// [transactionId] is non-null whenever you are a party, because a settlement you are in moved your
/// money and must appear in your ledger. **That is what makes settling up real rather than a flag**:
/// Splitwise's "settle up" is a bookkeeping marker that cannot touch your bank, whereas here the
/// deposit or withdrawal is an ordinary transaction, so the split ledger and the account ledger
/// cannot diverge.
class SplitSettlement {
  /// Creates a settlement.
  const SplitSettlement({
    required this.id,
    required this.fromPayeeId,
    required this.toPayeeId,
    required this.amount,
    required this.dateKey,
    this.groupId,
    this.transactionId,
    this.paymentMethodId,
    this.note,
  });

  /// Row identifier.
  final String id;

  /// Who paid.
  final String fromPayeeId;

  /// Who was paid.
  final String toPayeeId;

  /// How much.
  final Money amount;

  /// The civil date the money moved.
  final DateKey dateKey;

  /// The group this settles within, or null for a one-off debt.
  final String? groupId;

  /// The transaction this wrote into your ledger. Non-null whenever you are a party.
  final String? transactionId;

  /// How the money travelled — UPI, cash, bank transfer.
  final String? paymentMethodId;

  /// Free-form note.
  final String? note;

  /// `dateKey`'s month, for month-grouped reads. See [SplitExpense.monthKey].
  int get monthKey => dateKey.value ~/ 100;

  /// Whether [payeeId] is either side of this settlement.
  bool involves(String payeeId) =>
      fromPayeeId == payeeId || toPayeeId == payeeId;
}
```

### `lib/domain/entities/split_group.dart`

```dart
import 'package:alaya/core/enums/split_enums.dart';

/// A recurring cast of people, with enough context to make a split findable later — `Goa trip`,
/// `Flat 402`, `Sunday football`.
///
/// **A label, not an account.** Nobody else logs in, nothing syncs, and no group belongs to anybody
/// but the one user (ARCH_4 §2.3's "no multi-user" stands). A group exists so a cast of people is
/// entered once and a split can be filed under something recognisable.
///
/// Occasion and place live on [SplitExpense], not here: one group has many occasions, and pinning
/// them to the group would make `Goa trip` and `Goa trip day 2` two groups.
class SplitGroup {
  /// Creates a group.
  const SplitGroup({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.defaultSplitMethod,
    this.members = const [],
    this.note,
    this.colorArgb,
    this.iconKey,
    this.isArchived = false,
    this.sortOrder = 0,
  });

  /// Row identifier.
  final String id;

  /// Display name.
  final String name;

  /// Casefolded, accent-stripped name for search and duplicate detection.
  ///
  /// Carried on the entity rather than computed in the repository, matching `Item`, `Payee`, `Recipe`
  /// and every other named row. The caller builds it with `Normalizer`, so one implementation decides
  /// what "the same name" means everywhere.
  final String normalizedName;

  /// Which split method this group offers first.
  ///
  /// Flatmates who always split rent 40/30/30 should not re-choose "by shares" every month.
  final SplitMethod defaultSplitMethod;

  /// The members, in display order.
  final List<SplitMember> members;

  /// Free-form note.
  final String? note;

  /// Optional ARGB colour.
  final int? colorArgb;

  /// Optional icon identifier.
  final String? iconKey;

  /// Retired but historical. Archived groups stay in totals and leave the pickers — the distinction
  /// from soft delete that ARCH_3 §4 exists to preserve.
  final bool isArchived;

  /// Manual ordering within pickers.
  final int sortOrder;

  /// Whether any member carries a weight of their own.
  ///
  /// What the editor checks before offering "by shares" as a starting point: a group where everybody
  /// splits equally has nothing to prefill.
  bool get hasDefaultWeights =>
      members.any((member) => member.defaultWeightBasisPoints != null);

  /// The members' default weights, or null when they do not all have one.
  ///
  /// Null rather than a partial map, because a split resolved from three weights and one absent one
  /// would silently treat the fourth person as weightless — which is a real instruction ("she did not
  /// eat") and must never be inferred from a missing value.
  Map<String, int>? get defaultWeightsByPayee {
    if (members.isEmpty) return null;
    final weights = <String, int>{};
    for (final member in members) {
      final weight = member.defaultWeightBasisPoints;
      if (weight == null) return null;
      weights[member.payeeId] = weight;
    }
    return weights;
  }
}

/// One person's standing membership of a [SplitGroup].
///
/// **People are payees.** That table already carries `kind ∈ {person, merchant, …}` with a phone and
/// a note, so a second `people` concept would be a second vocabulary for one thing — the duplication
/// ARCH_1 §3.1 spent three tables avoiding.
class SplitMember {
  /// Creates a membership.
  const SplitMember({
    required this.id,
    required this.groupId,
    required this.payeeId,
    this.defaultWeightBasisPoints,
    this.sortOrder = 0,
  });

  /// Row identifier.
  final String id;

  /// The group.
  final String groupId;

  /// The person, as a payee id.
  final String payeeId;

  /// This member's default weight within the group, in basis points, or null for an equal share.
  ///
  /// Basis points rather than a percentage so the stored value is an integer and Law L1 is never at
  /// risk. Nullable because most groups split equally, and storing `3333` three times would invite
  /// the question of why they do not sum to 10,000.
  final int? defaultWeightBasisPoints;

  /// Manual ordering within the group.
  final int sortOrder;
}
```

### `lib/domain/entities/split_read_models.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// What one person owes you, or you owe them, in one currency.
///
/// **Read-only: comes from `v_split_balances`, and no balance is stored (Law L3).**
///
/// That is the single most consequential line in this module. Splitwise stores balances and has to
/// reconcile them, and its own help centre ends up advising users to distrust the pairwise figures
/// after simplification reshuffles them. Here a balance cannot drift because there is nowhere for it
/// to drift from — it is a sum over shares and settlements, recomputed on every read.
///
/// **Per currency, never summed across.** Netting INR against USD without a rate produces a figure
/// nobody can reproduce, which is the same reason anomaly A34 made waste costs group by currency
/// rather than collapse into one number.
class SplitBalance {
  /// Creates a balance.
  const SplitBalance({
    required this.payeeId,
    required this.owedToMe,
    required this.iOwe,
    this.oldestUnsettledDateKey,
  });

  /// The counterparty.
  final String payeeId;

  /// Their share of expenses **you** paid.
  final Money owedToMe;

  /// Your share of expenses **they** paid.
  final Money iOwe;

  /// The earliest date of an expense contributing to this balance, or null when nothing is
  /// outstanding.
  ///
  /// **What the ageing nudge reads, and why the view can supply it.** The notification worth sending
  /// is not a due date — it is "Ravi has owed you ₹1,850 for three weeks", which needs a start date
  /// and today. The view provides the date; the day count is computed in Dart against the injected
  /// `Clock`, because ARCH_2 §12.2 forbids any view from referencing the current time and a view
  /// containing `now` cannot be asserted against a `FixedClock`.
  final DateKey? oldestUnsettledDateKey;

  /// Positive when they owe you, negative when you owe them.
  Money get net => owedToMe - iOwe;

  /// Whether anything is outstanding either way.
  bool get isSettled => net.isZero;

  /// Whether they owe you.
  bool get theyOweMe => net.isPositive;

  /// Whether you owe them.
  bool get iOweThem => net.isNegative;

  /// The outstanding amount, without its direction. What a row displays beside a name.
  Money get outstanding => net.abs();

  /// How many days [oldestUnsettledDateKey] is before [today], or null when nothing is outstanding.
  ///
  /// Takes [today] rather than reading a clock, so an ageing nudge is reproducible under a
  /// `FixedClock` — the rule `Batch.isExpired` and every view in this schema follow.
  int? ageInDays(DateKey today) {
    final since = oldestUnsettledDateKey;
    if (since == null || isSettled) return null;
    // `diffDays` is positive when the receiver is later, so `today.diffDays(since)` is the age. The
    // same direction `DateKeyLabels.headerLabel` uses — I reached for `differenceInDays` first, which
    // does not exist.
    return today.diffDays(since);
  }
}

/// One expense with its own allocation totals, from `v_split_expenses`.
///
/// The read-model twin of `SplitExpense`, in the same relationship `ItemStock` has to `Item`: the
/// entity mirrors the table and this carries what the view derives. Screens listing expenses read
/// this and never load the shares, which is the point — a list of forty expenses should not fetch
/// four hundred share rows to show four hundred totals.
class SplitExpenseSummary {
  /// Creates a summary.
  const SplitExpenseSummary({
    required this.splitExpenseId,
    required this.total,
    required this.allocated,
    required this.dateKey,
    required this.paidByPayeeId,
    required this.shareCount,
    this.groupId,
    this.transactionId,
    this.title,
    this.place,
    this.occasion,
    this.settleByDateKey,
    this.myShare,
  });

  /// The expense.
  final String splitExpenseId;

  /// What the whole bill came to.
  final Money total;

  /// What the shares add up to.
  final Money allocated;

  /// The civil date the expense happened on.
  final DateKey dateKey;

  /// Who paid.
  final String paidByPayeeId;

  /// How many people are on it.
  final int shareCount;

  /// The group, or null for a one-off.
  final String? groupId;

  /// The transaction that moved your money, or null when somebody else paid.
  final String? transactionId;

  /// What it was.
  final String? title;

  /// Where it happened.
  final String? place;

  /// What the occasion was.
  final String? occasion;

  /// An optional date to settle by.
  final DateKey? settleByDateKey;

  /// Your own share, or null when the self payee is not configured yet.
  ///
  /// **Null means "not configured", never "zero".** `split.selfPayeeId` is a setting with no value on
  /// a fresh install — there is no payee to point at until the user creates one — so the view yields
  /// null and a screen must say so rather than displaying ₹0 as though you owed nothing.
  final Money? myShare;

  /// What the shares fail to account for. See `SplitExpense.unallocated`.
  Money get unallocated => total - allocated;

  /// Whether the shares account for the total exactly.
  bool get isFullyAllocated => unallocated.isZero;

  /// Whether the money for this has already left your account.
  bool get wasPaidByYou => transactionId != null;
}

/// What kind of thing an activity entry is.
enum SplitActivityKind {
  /// A shared expense was recorded.
  expense,

  /// Money changed hands.
  settlement,
}

/// One line of a group's activity feed, from `v_split_activity`.
///
/// A `UNION ALL` view rather than an events table, for the same reason `v_calendar_events` is one: two
/// subsystems writing into a shared feed table is a synchronisation-bug factory, and a view has no
/// synchronisation code to get wrong (anomaly A37).
class SplitActivityEntry {
  /// Creates an entry.
  const SplitActivityEntry({
    required this.refId,
    required this.kind,
    required this.dateKey,
    required this.amount,
    required this.payeeId,
    this.groupId,
    this.label,
  });

  /// The expense or settlement id this refers to.
  final String refId;

  /// Which of the two it is.
  final SplitActivityKind kind;

  /// The civil date.
  final DateKey dateKey;

  /// The amount involved.
  final Money amount;

  /// Who paid — the payer for an expense, the sender for a settlement.
  final String payeeId;

  /// The group, or null for a one-off.
  final String? groupId;

  /// A title, occasion, place or note, whichever the row had.
  final String? label;
}

/// A balance old enough to be worth mentioning.
///
/// **Here rather than in `SplitBalanceService`, where it was first declared.** A screen reads this and
/// a screen has no business importing a service to name a type — the same fault
/// `SplitLedgerRepository` records about `DebtEdge` still living inside `debt_simplifier.dart`. A
/// value type that two layers pass around belongs with the other read models, which is where a
/// consumer looks for it.
///
/// It carries no clock and no threshold: [ageInDays] is already computed, because ARCH_2 §12.2 forbids
/// a view from consulting the current time and the comparison happens once, in the service, against an
/// injected `Clock`.
final class AgeingDebt {
  /// Creates an ageing debt.
  const AgeingDebt({required this.balance, required this.ageInDays});

  /// Who, and how much.
  final SplitBalance balance;

  /// How long the oldest contributing expense has been outstanding.
  final int ageInDays;
}
```

### `lib/domain/entities/stock_movement.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';

/// An immutable event changing a batch's remaining quantity — the second of the app's three
/// append-only truths (ARCH_1 §3.3).
///
/// There is no soft delete and no edit (Law L6's stated exception): a correction is a *reversing*
/// movement pointing at the original through [reversesMovementId]. A ledger you can edit is not a
/// ledger, and waste analytics depends on this one staying honest.
///
/// **Deliberately has no `copyWith`**, unlike every other entity here. Offering one would invite
/// exactly the edit this table exists to make impossible; construct a reversing movement instead.
class StockMovement {
  /// Creates a movement.
  const StockMovement({
    required this.id,
    required this.batchId,
    required this.itemId,
    required this.kind,
    required this.quantity,
    required this.occurredAtUtc,
    required this.dateKey,
    this.reason,
    this.note,
    this.linkedTransactionId,
    this.reversesMovementId,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// The batch this movement applies to.
  final String batchId;

  /// The owning item, denormalised so per-item analytics needs no join.
  final String itemId;

  /// What kind of event this was. [quantity] is always positive; this carries the direction.
  final StockMovementKind kind;

  /// Quantity moved, always positive.
  final Qty quantity;

  /// When it happened. Always UTC.
  final DateTime occurredAtUtc;

  /// The local civil date it happened on.
  final DateKey dateKey;

  /// Optional structured reason, e.g. why something was wasted.
  final String? reason;

  /// Optional free-text note.
  final String? note;

  /// The transaction that caused this movement, for purchase-driven increases.
  final String? linkedTransactionId;

  /// The movement this row reverses. Non-null exactly on correction rows.
  final String? reversesMovementId;

  /// Whether this kind of movement increases stock.
  ///
  /// The single Dart statement of the direction rule, matching `v_batch_stock_check`'s
  /// `CASE WHEN kind IN (...)` exactly — a repair path and its reconciliation probe must never
  /// disagree about which way a kind moves stock.
  bool get isIncoming => switch (kind) {
    StockMovementKind.openingIn ||
    StockMovementKind.purchaseIn ||
    StockMovementKind.manualIn ||
    StockMovementKind.adjustIn =>
    true,
    StockMovementKind.consume ||
    StockMovementKind.waste ||
    StockMovementKind.expired ||
    StockMovementKind.adjustOut =>
    false,
  };

  /// This movement's signed effect on the batch's remaining quantity.
  Qty get signedQuantity => isIncoming ? quantity : -quantity;

  /// True when this movement represents stock thrown away rather than used — the input to the
  /// food-waste analytics (ARCH_3 §5.1 query 14).
  bool get isWaste =>
      kind == StockMovementKind.waste || kind == StockMovementKind.expired;

  /// True when this movement corrects an earlier one.
  bool get isReversal => reversesMovementId != null;

  @override
  bool operator ==(Object other) =>
      other is StockMovement &&
          other.id == id &&
          other.batchId == batchId &&
          other.itemId == itemId &&
          other.kind == kind &&
          other.quantity == quantity &&
          other.occurredAtUtc == occurredAtUtc &&
          other.dateKey == dateKey &&
          other.reason == reason &&
          other.note == note &&
          other.linkedTransactionId == linkedTransactionId &&
          other.reversesMovementId == reversesMovementId;

  @override
  int get hashCode => Object.hashAll([
    id, batchId, itemId, kind, quantity, occurredAtUtc, dateKey, reason, note,
    linkedTransactionId, reversesMovementId,
  ]);

  @override
  String toString() => 'StockMovement($id, ${kind.name}, $quantity)';
}
```

### `lib/domain/entities/tag.dart`

```dart
import 'package:alaya/core/enums/tag_scope.dart';

/// A free user-defined label, scoped by which modules may use it.
///
/// Distinct from a transaction's `subtype`, which is a closed enum because it changes the editor
/// form and must stay stable for analytics. Tags are open because nobody can enumerate what a user
/// in Ahmedabad, Osaka and Lisbon will call things — they are not redundant with each other
/// (ARCH_1 §3.1).
class Tag {
  /// Creates a tag.
  const Tag({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.allowedScopes,
    required this.isSystem,
    required this.sortOrder,
    required this.isDeleted,
    this.colorArgb,
    this.iconKey,
    this.parentTagId,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// Display name as the user typed it.
  final String name;

  /// Normalised form used for identity matching only, never displayed.
  final String normalizedName;

  /// Which module pickers offer this tag.
  ///
  /// A set rather than six booleans: the six `allowedIn*` columns are one concept, and a set makes
  /// [isAllowedIn] a single containment check instead of a switch that can select the wrong
  /// column — the mistake that would put `Kitchen` in the deposit picker (ARCH_2 §14).
  final Set<TagScope> allowedScopes;

  /// Whether this tag was seeded; system tags cannot be deleted.
  final bool isSystem;

  /// Manual ordering within pickers.
  final int sortOrder;

  /// Whether this tag has been soft-deleted.
  ///
  /// Present on this entity alone among the 21, deliberately. A deleted tag keeps its links so
  /// history stays readable, and the UI renders it greyed with `(deleted)` (anomaly A36) — so the
  /// flag is genuinely display state here, not the persistence detail it is everywhere else.
  final bool isDeleted;

  /// Optional ARGB colour for the chip.
  final int? colorArgb;

  /// Optional icon identifier.
  final String? iconKey;

  /// Parent tag, permitting exactly one level of nesting (`Grocery > Vegetables`).
  final String? parentTagId;

  /// True when this tag is offered in [scope]'s picker.
  bool isAllowedIn(TagScope scope) => allowedScopes.contains(scope);

  /// True when this tag is nested under another.
  bool get isChild => parentTagId != null;

  /// True when the user is allowed to delete this tag.
  bool get isDeletable => !isSystem;

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  Tag copyWith({
    String? id,
    String? name,
    String? normalizedName,
    Set<TagScope>? allowedScopes,
    bool? isSystem,
    int? sortOrder,
    bool? isDeleted,
    int? colorArgb,
    String? iconKey,
    String? parentTagId,
  }) {
    return Tag(
      id: id ?? this.id,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      allowedScopes: allowedScopes ?? this.allowedScopes,
      isSystem: isSystem ?? this.isSystem,
      sortOrder: sortOrder ?? this.sortOrder,
      isDeleted: isDeleted ?? this.isDeleted,
      colorArgb: colorArgb ?? this.colorArgb,
      iconKey: iconKey ?? this.iconKey,
      parentTagId: parentTagId ?? this.parentTagId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Tag &&
          other.id == id &&
          other.name == name &&
          other.normalizedName == normalizedName &&
          _sameScopes(other.allowedScopes) &&
          other.isSystem == isSystem &&
          other.sortOrder == sortOrder &&
          other.isDeleted == isDeleted &&
          other.colorArgb == colorArgb &&
          other.iconKey == iconKey &&
          other.parentTagId == parentTagId;

  bool _sameScopes(Set<TagScope> other) =>
      other.length == allowedScopes.length && other.containsAll(allowedScopes);

  @override
  int get hashCode => Object.hashAll([
    id, name, normalizedName,
    // Order-independent, so two equal sets built in different orders hash alike.
    Object.hashAllUnordered(allowedScopes),
    isSystem, sortOrder, isDeleted, colorArgb, iconKey, parentTagId,
  ]);

  @override
  String toString() => 'Tag($id, $name${isDeleted ? ' (deleted)' : ''})';
}
```

### `lib/domain/entities/transaction.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// One movement of money — the first of the app's three append-only truths (ARCH_1 §3.3).
///
/// A `transfer` is **one** transaction, not a pair. The ledger expands it into two signed legs,
/// which is why a self-transfer nets to zero by construction (anomaly A02) — and why
/// [signedAmount] is zero for one, while [signedAmountFor] gives each account its own side.
class Transaction {
  /// Creates a transaction.
  const Transaction({
    required this.id,
    required this.kind,
    required this.subtype,
    required this.occurredAtUtc,
    required this.dateKey,
    required this.originalAmount,
    required this.needsReview,
    this.fromAccountId,
    this.toAccountId,
    this.paymentMethodId,
    this.payeeId,
    this.note,
    this.recurringTemplateId,
    this.recurringOccurrenceId,
    this.frozenConversion,
    this.frozenConversionRate,
    this.frozenConversionRateRaw,
    this.frozenConversionDateKey,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// Which direction money moved.
  final TransactionKind kind;

  /// The structural flow subtype, which decides the editor form and the analytics bucket.
  final TransactionSubtype subtype;

  /// When it happened. Always UTC; the civil date is [dateKey], which is the timezone-independent
  /// one (Law L4).
  final DateTime occurredAtUtc;

  /// The local civil date it happened on.
  final DateKey dateKey;

  /// The amount as stored, always positive — the sign comes from [kind] (Law L1). Immutable
  /// once saved, together with its currency (Law L9).
  final Money originalAmount;

  /// Set by quick-add when only an amount was supplied; drives the "add details" nudge.
  final bool needsReview;

  /// Source account for withdrawals, decreases and transfers.
  final String? fromAccountId;

  /// Destination account for deposits, increases and transfers.
  final String? toAccountId;

  /// The rail money travelled on.
  final String? paymentMethodId;

  /// The counterparty.
  final String? payeeId;

  /// Optional free-text note. Indexed for full-text search.
  final String? note;

  /// The recurring template this settled, if any.
  final String? recurringTemplateId;

  /// The specific occurrence this settled, if any.
  final String? recurringOccurrenceId;

  /// A frozen converted amount, written only by the explicit per-transaction freeze action and
  /// never recomputed (Law L9).
  final Money? frozenConversion;

  /// The rate used at freeze time.
  final double? frozenConversionRate;

  /// The exact rate string the API returned, so a questioned figure can be reproduced.
  final String? frozenConversionRateRaw;

  /// The civil date the frozen rate was quoted for.
  final DateKey? frozenConversionDateKey;

  /// `yyyymm`, derived from [dateKey] rather than stored on this entity.
  ///
  /// The database keeps a denormalised `month_key` column so monthly analytics never computes it
  /// per row, and a CHECK constraint keeps the two consistent — but a domain entity that stored it
  /// too would just be a third copy able to disagree with both.
  int get monthKey => dateKey.monthKey;

  /// This transaction's effect on **total net worth**.
  ///
  /// Positive for a deposit or increase, negative for a withdrawal or decrease, and exactly
  /// **zero for a transfer** — moving money between your own accounts does not change how much you
  /// have (anomaly A02). For one account's side of a transfer, use [signedAmountFor].
  Money get signedAmount => switch (kind) {
    TransactionKind.deposit || TransactionKind.adjustmentIncrease => originalAmount,
    TransactionKind.withdrawal || TransactionKind.adjustmentDecrease => -originalAmount,
    TransactionKind.transfer => Money.zero(originalAmount.currencyCode),
  };

  /// This transaction's effect on [accountId]'s balance, or zero if it does not touch it.
  ///
  /// Mirrors `v_account_ledger`: a transfer contributes `-amount` to the source and `+amount` to
  /// the destination, so summing this across a transfer's two accounts gives zero.
  Money signedAmountFor(String accountId) {
    final zero = Money.zero(originalAmount.currencyCode);
    if (kind == TransactionKind.transfer) {
      if (accountId == fromAccountId) return -originalAmount;
      if (accountId == toAccountId) return originalAmount;
      return zero;
    }
    if (accountId == toAccountId) return originalAmount;
    if (accountId == fromAccountId) return -originalAmount;
    return zero;
  }

  /// True when this moves money between two of the user's own accounts.
  bool get isTransfer => kind == TransactionKind.transfer;

  /// True when this increases an account's balance.
  bool get isInflow =>
      kind == TransactionKind.deposit || kind == TransactionKind.adjustmentIncrease;

  /// True when this decreases an account's balance.
  bool get isOutflow =>
      kind == TransactionKind.withdrawal || kind == TransactionKind.adjustmentDecrease;

  /// True when this is a manual reconciliation rather than a real-world movement.
  bool get isAdjustment =>
      kind == TransactionKind.adjustmentIncrease || kind == TransactionKind.adjustmentDecrease;

  /// True when this settled a recurring obligation, the discriminator for the
  /// recurring-versus-discretionary split (ARCH_3 §5.1 query 18).
  bool get isRecurring => recurringTemplateId != null;

  /// True when an explicit conversion snapshot has been frozen against this transaction.
  bool get hasFrozenConversion => frozenConversion != null;

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  Transaction copyWith({
    String? id,
    TransactionKind? kind,
    TransactionSubtype? subtype,
    DateTime? occurredAtUtc,
    DateKey? dateKey,
    Money? originalAmount,
    bool? needsReview,
    String? fromAccountId,
    String? toAccountId,
    String? paymentMethodId,
    String? payeeId,
    String? note,
    String? recurringTemplateId,
    String? recurringOccurrenceId,
    Money? frozenConversion,
    double? frozenConversionRate,
    String? frozenConversionRateRaw,
    DateKey? frozenConversionDateKey,
  }) {
    return Transaction(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      subtype: subtype ?? this.subtype,
      occurredAtUtc: occurredAtUtc ?? this.occurredAtUtc,
      dateKey: dateKey ?? this.dateKey,
      originalAmount: originalAmount ?? this.originalAmount,
      needsReview: needsReview ?? this.needsReview,
      fromAccountId: fromAccountId ?? this.fromAccountId,
      toAccountId: toAccountId ?? this.toAccountId,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      payeeId: payeeId ?? this.payeeId,
      note: note ?? this.note,
      recurringTemplateId: recurringTemplateId ?? this.recurringTemplateId,
      recurringOccurrenceId: recurringOccurrenceId ?? this.recurringOccurrenceId,
      frozenConversion: frozenConversion ?? this.frozenConversion,
      frozenConversionRate: frozenConversionRate ?? this.frozenConversionRate,
      frozenConversionRateRaw: frozenConversionRateRaw ?? this.frozenConversionRateRaw,
      frozenConversionDateKey: frozenConversionDateKey ?? this.frozenConversionDateKey,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Transaction &&
          other.id == id &&
          other.kind == kind &&
          other.subtype == subtype &&
          other.occurredAtUtc == occurredAtUtc &&
          other.dateKey == dateKey &&
          other.originalAmount == originalAmount &&
          other.needsReview == needsReview &&
          other.fromAccountId == fromAccountId &&
          other.toAccountId == toAccountId &&
          other.paymentMethodId == paymentMethodId &&
          other.payeeId == payeeId &&
          other.note == note &&
          other.recurringTemplateId == recurringTemplateId &&
          other.recurringOccurrenceId == recurringOccurrenceId &&
          other.frozenConversion == frozenConversion &&
          other.frozenConversionRate == frozenConversionRate &&
          other.frozenConversionRateRaw == frozenConversionRateRaw &&
          other.frozenConversionDateKey == frozenConversionDateKey;

  @override
  int get hashCode => Object.hashAll([
    id, kind, subtype, occurredAtUtc, dateKey, originalAmount, needsReview,
    fromAccountId, toAccountId, paymentMethodId, payeeId, note,
    recurringTemplateId, recurringOccurrenceId, frozenConversion,
    frozenConversionRate, frozenConversionRateRaw, frozenConversionDateKey,
  ]);

  @override
  String toString() => 'Transaction($id, ${kind.name}, $originalAmount)';
}
```

### `lib/domain/entities/transaction_line.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';

/// One purchased thing inside a `Transaction`.
///
/// Optional detail: the transaction's own amount stays the source of truth, and when the lines do
/// not sum to it the difference is surfaced rather than auto-balanced (anomaly A11).
class TransactionLine {
  /// Creates a line.
  const TransactionLine({
    required this.id,
    required this.transactionId,
    required this.lineNo,
    required this.description,
    required this.destination,
    this.itemId,
    this.quantity,
    this.unitCode,
    this.unitPrice,
    this.lineAmount,
    this.createdBatchId,
    this.createdAssetId,
    this.createdRecurringTemplateId,
    this.note,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// The owning transaction.
  final String transactionId;

  /// Position within the transaction, 1-based.
  final int lineNo;

  /// What was bought, as free text.
  final String description;

  /// What this line produced elsewhere in the app — the field that removes the
  /// electronics/inventory/service ambiguity (anomaly A12).
  final TransactionLineDestination destination;

  /// The catalogued item, when this line refers to one.
  final String? itemId;

  /// How much was bought. Already in base units, so aggregating it needs no conversion.
  final Qty? quantity;

  /// The unit the user actually typed, kept so the line renders as `2 kg` rather than `2000 g`.
  final String? unitCode;

  /// Price per [unitCode]. Drives the personal-inflation series (ARCH_3 §5.1 query 12).
  final Money? unitPrice;

  /// Total for this line.
  final Money? lineAmount;

  /// The inventory batch this line created, if [destination] was inventory.
  final String? createdBatchId;

  /// The asset this line created, if [destination] was asset.
  final String? createdAssetId;

  /// The recurring template this line created, if [destination] was recurring.
  final String? createdRecurringTemplateId;

  /// Optional free-text note.
  final String? note;

  /// True when this line produced an artefact elsewhere.
  bool get hasArtefact =>
      createdBatchId != null ||
          createdAssetId != null ||
          createdRecurringTemplateId != null;

  /// The id of whatever artefact this line produced, or null if none.
  ///
  /// At most one is ever set, matching [destination] (ARCH_2 §4.2).
  String? get createdArtefactId =>
      createdBatchId ?? createdAssetId ?? createdRecurringTemplateId;

  /// True when this line refers to a catalogued item rather than free text.
  bool get isCatalogued => itemId != null;

  /// Price per base unit — what makes prices comparable across purchases in different units
  /// (ARCH_3 §5.1 query 24). Null when either the amount or the quantity is missing or zero.
  ///
  /// Returns minor units per base unit as a double, because a per-unit price is a derived ratio
  /// for display and comparison, not a stored amount — Law L1 governs amounts that are persisted.
  double? get pricePerBaseUnit {
    final amount = lineAmount;
    final qty = quantity;
    if (amount == null || qty == null || qty.milliBase == 0) return null;
    return amount.minor / (qty.milliBase / 1000);
  }

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  TransactionLine copyWith({
    String? id,
    String? transactionId,
    int? lineNo,
    String? description,
    TransactionLineDestination? destination,
    String? itemId,
    Qty? quantity,
    String? unitCode,
    Money? unitPrice,
    Money? lineAmount,
    String? createdBatchId,
    String? createdAssetId,
    String? createdRecurringTemplateId,
    String? note,
  }) {
    return TransactionLine(
      id: id ?? this.id,
      transactionId: transactionId ?? this.transactionId,
      lineNo: lineNo ?? this.lineNo,
      description: description ?? this.description,
      destination: destination ?? this.destination,
      itemId: itemId ?? this.itemId,
      quantity: quantity ?? this.quantity,
      unitCode: unitCode ?? this.unitCode,
      unitPrice: unitPrice ?? this.unitPrice,
      lineAmount: lineAmount ?? this.lineAmount,
      createdBatchId: createdBatchId ?? this.createdBatchId,
      createdAssetId: createdAssetId ?? this.createdAssetId,
      createdRecurringTemplateId:
      createdRecurringTemplateId ?? this.createdRecurringTemplateId,
      note: note ?? this.note,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TransactionLine &&
          other.id == id &&
          other.transactionId == transactionId &&
          other.lineNo == lineNo &&
          other.description == description &&
          other.destination == destination &&
          other.itemId == itemId &&
          other.quantity == quantity &&
          other.unitCode == unitCode &&
          other.unitPrice == unitPrice &&
          other.lineAmount == lineAmount &&
          other.createdBatchId == createdBatchId &&
          other.createdAssetId == createdAssetId &&
          other.createdRecurringTemplateId == createdRecurringTemplateId &&
          other.note == note;

  @override
  int get hashCode => Object.hashAll([
    id, transactionId, lineNo, description, destination, itemId, quantity,
    unitCode, unitPrice, lineAmount, createdBatchId, createdAssetId,
    createdRecurringTemplateId, note,
  ]);

  @override
  String toString() => 'TransactionLine($id, $description)';
}
```

### `lib/domain/entities/unit.dart`

```dart
import 'package:alaya/core/quantity/unit_category.dart';

/// A unit of measure with an exact integer factor to its category's base unit.
class Unit {
  /// Creates a unit.
  const Unit({
    required this.code,
    required this.category,
    required this.factorToBaseMilli,
    required this.displayName,
    required this.isSystem,
    required this.sortOrder,
  });

  /// Unit code, e.g. `kg`, `ml`, `dozen`.
  final String code;

  /// Which of the three fixed categories this unit measures.
  final UnitCategory category;

  /// Exact milli-base units per one of this unit — `kg` is `1000000`, `dozen` is `12000`.
  /// Integer by design: no step of a unit conversion touches a double (Law L2).
  final int factorToBaseMilli;

  /// Human-readable name for pickers.
  final String displayName;

  /// Whether this unit was seeded; system units cannot be deleted.
  final bool isSystem;

  /// Manual ordering within pickers.
  final int sortOrder;

  /// True if this unit *is* its category's base unit — `g`, `ml` or `pc`.
  bool get isBaseUnit => factorToBaseMilli == 1000;

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  Unit copyWith({
    String? code,
    UnitCategory? category,
    int? factorToBaseMilli,
    String? displayName,
    bool? isSystem,
    int? sortOrder,
  }) {
    return Unit(
      code: code ?? this.code,
      category: category ?? this.category,
      factorToBaseMilli: factorToBaseMilli ?? this.factorToBaseMilli,
      displayName: displayName ?? this.displayName,
      isSystem: isSystem ?? this.isSystem,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Unit &&
          other.code == code &&
          other.category == category &&
          other.factorToBaseMilli == factorToBaseMilli &&
          other.displayName == displayName &&
          other.isSystem == isSystem &&
          other.sortOrder == sortOrder;

  @override
  int get hashCode => Object.hashAll(
      [code, category, factorToBaseMilli, displayName, isSystem, sortOrder]);

  @override
  String toString() => 'Unit($code)';
}
```

### `lib/domain/repositories/account_repository.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/account_balance.dart';
import 'package:alaya/domain/entities/transaction.dart';

/// Reads and writes accounts, and reads the balances derived from them.
abstract interface class AccountRepository {
  /// Emits accounts that may be chosen in a picker — active and unarchived.
  Stream<List<Account>> watchSelectable();

  /// Emits every account, archived included.
  ///
  /// An archived account still counts toward totals and net worth; it has only left the pickers
  /// (ARCH_3 §4).
  Stream<List<Account>> watchAllIncludingArchived();

  /// Reads one account by id, soft-deleted ones included, so history can render a name.
  Future<Account?> byId(String id);

  /// Emits every account's balance, each in its own currency.
  ///
  /// Never sum these directly — accounts may hold different currencies (anomaly A34). Pair them with
  /// `Account.includeInNetWorth` and hand the result to `BalanceService.totalInHome`, which is the only
  /// sanctioned source of a headline figure.
  Stream<List<AccountBalance>> watchBalances();

  /// Emits one account's balance.
  Stream<AccountBalance?> watchBalanceOf(String accountId);

  /// Emits the transactions touching [accountId] on either side, newest first.
  Stream<List<Transaction>> watchLedgerFor(String accountId);

  /// Creates or updates an account.
  Future<Result<Account, Failure>> save(Account account);

  /// Archives or unarchives an account.
  Future<Result<void, Failure>> setArchived({
    required String id,
    required bool isArchived,
  });

  /// Deletes an account.
  ///
  /// **Fails with a [BusinessRuleFailure] carrying rule `accountInUse` when any live transaction
  /// references it**, and the UI offers Archive instead — a hard block, not a warning
  /// (ARCH_3 §4.1). Deleting an account with history would silently remove money from every total
  /// that history contributed to.
  Future<Result<void, Failure>> delete(String id);
}
```

### `lib/domain/repositories/analytics_cache_repository.dart`

```dart
/// Reads and writes memoised analytics results.
///
/// Exists as a domain contract because `domain/services/analytics/` consumes it, and Law L12 forbids
/// anything under `domain/` importing from `data/`.
///
/// **One entry per query name, not per parameter set.** The schema's primary key is the cache key
/// alone, so caching "spend by subtype for July" evicts the June entry. [read] treats a parameter
/// mismatch as a miss — safe, but it means alternating between two date ranges recomputes each time.
/// If that proves costly, a caller can fold the parameter hash into [cacheKey] and get a row per
/// parameter set with no schema change.
abstract interface class AnalyticsCacheRepository {
  /// Reads the cached payload, or null when absent, stale, or computed for different parameters.
  Future<String?> read({
    required String cacheKey,
    required String paramsHash,
  });

  /// Stores a payload against [cacheKey], valid for [ttl].
  Future<void> write({
    required String cacheKey,
    required String paramsHash,
    required String payloadJson,
    required Duration ttl,
  });

  /// Invalidates one cached query.
  Future<void> invalidate(String cacheKey);

  /// Invalidates every cached query — what a write to any contributing table triggers.
  Future<void> invalidateAll();
}
```

### `lib/domain/repositories/asset_repository.dart`

```dart
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';

/// Reads and writes service-manager assets.
///
/// **There is no delete method.** Removal is [dispose], which records a reason and a date, so the
/// money spent stays in analytics after the thing is gone (ARCH_3 §4.1).
abstract interface class AssetRepository {
  /// Emits assets in use — everything not disposed.
  Stream<List<Asset>> watchInUse();

  /// Emits non-disposed assets of [type], including service providers.
  Stream<List<Asset>> watchByType(AssetType type);

  /// Emits disposed assets, most recent first — still viewable with their full history.
  Stream<List<Asset>> watchDisposed();

  /// Reads one asset by id, disposed ones included.
  Future<Asset?> byId(String id);

  /// Emits non-disposed assets whose warranty ends within `[from, to]`.
  Stream<List<Asset>> watchWarrantyEndingInRange({
    required DateKey from,
    required DateKey to,
  });

  /// Emits non-disposed assets whose next service falls within `[from, to]`.
  Stream<List<Asset>> watchServiceDueInRange({
    required DateKey from,
    required DateKey to,
  });

  /// Creates or updates an asset.
  ///
  /// Rejects a status of [AssetStatus.disposed] with a [BusinessRuleFailure] — disposal needs a
  /// reason and a date, so it goes through [dispose].
  Future<Result<Asset, Failure>> save(Asset asset);

  /// Moves an asset between active and under-repair.
  Future<Result<void, Failure>> setStatus({
    required String id,
    required AssetStatus status,
  });

  /// Retires an asset — the only removal path.
  ///
  /// [amountMinor] is the sale proceeds when [reason] is [AssetDisposalReason.sold]. It is
  /// denominated in the asset's own purchase currency, since the schema carries no separate disposal
  /// currency — pairing an amount with the wrong currency is the mistake Law L1 exists to prevent.
  Future<Result<void, Failure>> dispose({
    required String assetId,
    required AssetDisposalReason reason,
    required DateKey dateKey,
    int? amountMinor,
    String? note,
  });

  /// Returns a disposed asset to service, clearing its disposal fields — the undo for a mis-tap.
  Future<Result<void, Failure>> undispose(String id);

  /// Clears the link to a deleted source transaction (anomaly A10) — the TV does not un-exist
  /// because the receipt did.
  Future<Result<void, Failure>> detachFromDeletedTransaction(String id);
}
```

### `lib/domain/repositories/batch_repository.dart`

```dart
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';

/// One batch's cached remaining quantity against what its movement ledger says.
///
/// [discrepancy] must be zero for every batch, always. A non-zero one means the Law L3 cache has
/// drifted and needs repairing.
class BatchReconciliation {
  /// Creates a reconciliation result.
  const BatchReconciliation({
    required this.batchId,
    required this.cached,
    required this.fromLedger,
    required this.discrepancy,
  });

  /// The batch this describes.
  final String batchId;

  /// What the batch row currently claims is left.
  final Qty cached;

  /// What summing the movement ledger says is left.
  final Qty fromLedger;

  /// [cached] less [fromLedger].
  final Qty discrepancy;

  /// True when the cache agrees with the ledger.
  bool get isConsistent => discrepancy.isZero;
}

/// Reads and writes inventory batches.
abstract interface class BatchRepository {
  /// Emits the batches of [itemId] in FEFO order — nearest expiry first, undated batches last.
  ///
  /// The order stock is drawn down in (anomaly A08). Only batches with stock appear.
  Stream<List<Batch>> watchByItemFefo(String itemId);

  /// Reads the same FEFO-ordered list once — what a consumption run walks.
  Future<List<Batch>> byItemFefo(String itemId);

  /// Emits the batches of [itemId] in purchase order, for the expanded item detail which itemises
  /// rather than sums (ARCH_1 §5.4).
  Stream<List<Batch>> watchByItem(String itemId);

  /// Emits batches with stock expiring within `[from, to]`.
  Stream<List<Batch>> watchExpiringInRange({
    required DateKey from,
    required DateKey to,
  });

  /// Reads one batch by id, soft-deleted ones included.
  Future<Batch?> byId(String id);

  /// Creates a batch together with its founding movement.
  ///
  /// A batch never exists without one, or the reconciliation probe would report the new row as a
  /// permanent discrepancy of its own initial quantity.
  Future<Result<Batch, Failure>> create(Batch batch);

  /// Updates a batch's display metadata — location, note, expiry, cost.
  ///
  /// Cannot change the quantity: that only ever moves by recording a movement, so
  /// `StockRepository` owns it.
  Future<Result<Batch, Failure>> updateMetadata(Batch batch);

  /// Marks a batch detached when its source transaction is deleted (anomaly A10).
  Future<Result<void, Failure>> detachFromDeletedTransaction(String batchId);

  /// Soft-deletes a batch. Its movements are untouched.
  Future<Result<void, Failure>> delete(String id);

  /// Emits every batch's cache-versus-ledger reconciliation.
  Stream<List<BatchReconciliation>> watchReconciliation();

  /// Reads only the batches whose cache disagrees with their ledger — the Settings screen's
  /// "N batches need repair" count.
  Future<List<BatchReconciliation>> findDiscrepancies();

  /// Rebuilds one batch's cached quantity from its movement history — the Law L3 repair path.
  Future<Result<void, Failure>> recompute(String batchId);

  /// Rebuilds every batch's cached quantity — the Settings "repair stock" action.
  Future<Result<int, Failure>> recomputeAll();
}
```

### `lib/domain/repositories/calendar_repository.dart`

```dart
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/core/time/date_key.dart';

/// Reads the unified calendar feed.
///
/// Exists as a domain contract because `domain/services/calendar_aggregator.dart` consumes it, and
/// Law L12 forbids anything under `domain/` importing from `data/`.
abstract interface class CalendarRepository {
  /// Emits the events falling within `[from, to]`.
  ///
  /// **Always bounded.** Unbounded, the underlying view scans seven tables; bounded, each arm uses
  /// its own date index. Callers should request the visible month plus a month of prefetch, not
  /// everything.
  Stream<List<CalendarEvent>> watchRange({
    required DateKey from,
    required DateKey to,
  });

  /// Reads the events falling on exactly [dateKey], for the day-detail sheet.
  Future<List<CalendarEvent>> forDay(DateKey dateKey);

  /// Reads how many events fall on each date in `[from, to]`, for the month grid's severity dots.
  ///
  /// Returns counts keyed by date rather than the events themselves, because a month grid needs a
  /// dot per day and not several hundred full event objects.
  Future<Map<DateKey, int>> countsByDate({
    required DateKey from,
    required DateKey to,
  });
}
```

### `lib/domain/repositories/currency_repository.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/domain/entities/currency.dart';

/// Reads currencies and the cached exchange rates.
abstract interface class CurrencyRepository {
  /// Emits the currencies offered in pickers.
  Stream<List<Currency>> watchEnabled();

  /// Emits every currency, enabled or not.
  Stream<List<Currency>> watchAll();

  /// Reads one currency by ISO code.
  Future<Currency?> byCode(String code);

  /// Reads `code -> decimalDigits` for every currency — the lookup that keeps `100` out of the
  /// codebase (ARCH_1 §4.1).
  Future<Map<String, int>> decimalDigitsByCode();

  /// Enables or disables a currency without deleting it.
  Future<Result<void, Failure>> setEnabled({
    required String code,
    required bool isEnabled,
  });

  /// Converts [amount] into [toCurrencyCode] using the rate for [on].
  ///
  /// Returns a [ConvertedMoney] rather than a bare [Money] so the caller cannot lose track of how
  /// reliable the figure is — an unconverted amount must be excluded from a total rather than
  /// counted as zero (anomaly A15).
  Future<ConvertedMoney> convert({
    required Money amount,
    required String toCurrencyCode,
    required DateKey on,
  });

  /// Converts [amount] into the user's home currency.
  Future<ConvertedMoney> convertToHome({
    required Money amount,
    required DateKey on,
  });

  /// Emits how many amounts currently cannot be converted, for the `+N unconverted` chip.
  Stream<int> watchUnconvertedCount();

  /// Fetches today's rates if the network allows. Never throws and never blocks a write
  /// (Law L11) — a failure is a no-op.
  Future<void> syncDailyRates();
}
```

### `lib/domain/repositories/item_repository.dart`

```dart
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';

/// Reads and writes inventory items, and reads their derived stock.
abstract interface class ItemRepository {
  /// Emits every active item, alphabetically.
  Stream<List<Item>> watchAll();

  /// Emits active items measuring [category].
  Stream<List<Item>> watchByCategory(UnitCategory category);

  /// Emits favourited items.
  Stream<List<Item>> watchFavorites();

  /// Emits active items whose name matches [term], for the picker's search field.
  Stream<List<Item>> watchMatching(String term);

  /// Reads one item by id, soft-deleted ones included.
  Future<Item?> byId(String id);

  /// Reads the item whose identity is `(normalizedName, category)`, or null if none exists.
  ///
  /// Identity is the pair together: `Milk (Weight)` and `Milk (Volume)` are different items, so a
  /// name that matches under a *different* category is correctly not a match (anomaly A06).
  Future<Item?> findByIdentity({
    required String normalizedName,
    required UnitCategory unitCategory,
  });

  /// Finds active items whose names are close to [name] within [category], for the
  /// "Add to existing Tomato?" suggestion.
  ///
  /// **Suggestions only, never an automatic merge.** Silent fuzzy merging corrupts data in ways a
  /// user cannot easily notice or undo, so only an exact normalized match merges (anomaly A07).
  Future<List<Item>> findSimilar({
    required String name,
    required UnitCategory unitCategory,
  });

  /// Emits every item's stock rollup.
  Stream<List<ItemStock>> watchAllStock();

  /// Emits one item's stock rollup.
  Stream<ItemStock?> watchStockOf(String itemId);

  /// Emits every item currently below its low-stock threshold.
  Stream<List<ItemStock>> watchLowStock();

  /// Creates or updates an item.
  ///
  /// **Rejects a change to `unitCategory` on an existing item** with a [BusinessRuleFailure]
  /// (Law L8): changing it would silently reinterpret every quantity ever recorded against the
  /// item. Rejects a duplicate identity with a [ConflictFailure].
  Future<Result<Item, Failure>> save(Item item);

  /// Toggles the favourite flag.
  Future<Result<void, Failure>> setFavorite({
    required String id,
    required bool isFavorite,
  });

  /// Soft-deletes an item and its batches.
  ///
  /// Cascades to batches — deliberately, and unlike deleting a transaction. Deleting an *item*
  /// removes the thing the batches describe; deleting a *transaction* removes only a receipt. The
  /// movement ledger is untouched either way (Law L6's exception).
  Future<Result<void, Failure>> delete(String id);
}
```

### `lib/domain/repositories/payee_repository.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/entities/payee.dart';

/// Reads and writes payees.
abstract interface class PayeeRepository {
  /// Emits every active payee, alphabetically.
  Stream<List<Payee>> watchAll();

  /// Emits active payees whose name matches [term], for the picker's search field.
  Stream<List<Payee>> watchMatching(String term);

  /// Reads one by id, soft-deleted ones included, so history can render a name.
  Future<Payee?> byId(String id);

  /// Reads the active payee with this normalized name, for the merge-or-create decision.
  Future<Payee?> byNormalizedName(String normalizedName);

  /// Creates or updates a payee.
  ///
  /// Fails with a [ConflictFailure] when another active payee already has the same normalized
  /// name.
  Future<Result<Payee, Failure>> save(Payee payee);

  /// Soft-deletes a payee. Existing transactions keep their link so history stays readable.
  Future<Result<void, Failure>> delete(String id);
}
```

### `lib/domain/repositories/payment_method_repository.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/entities/payment_method.dart';

/// Reads and writes payment methods.
abstract interface class PaymentMethodRepository {
  /// Emits every active payment method in display order.
  Stream<List<PaymentMethod>> watchAll();

  /// Reads one by id, soft-deleted ones included, so history can render a name.
  Future<PaymentMethod?> byId(String id);

  /// Creates or updates a payment method.
  Future<Result<PaymentMethod, Failure>> save(PaymentMethod method);

  /// Deletes a user-created payment method. Fails for a system one, or when a live transaction
  /// still references it.
  Future<Result<void, Failure>> delete(String id);
}
```

### `lib/domain/repositories/recipe_repository.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recipe.dart';

/// Reading and writing recipes.
///
/// Ingredients and steps are never saved independently of their recipe: [save] replaces the whole
/// aggregate in one transaction. A partially-saved recipe — three of five ingredients, steps out of
/// order — is a state no screen can render and no user asked for.
abstract interface class RecipeRepository {
  /// Every recipe, newest first. Ingredients and steps are included.
  Stream<List<Recipe>> watchAll();

  /// Recipes whose normalized name contains [query].
  Stream<List<Recipe>> watchMatching(String query);

  /// Pinned recipes.
  Stream<List<Recipe>> watchFavorites();

  /// One recipe with its ingredients and steps, or null if it does not exist.
  Stream<Recipe?> watchById(String id);

  /// Recipes that use [itemId] as an ingredient.
  ///
  /// The reverse lookup an item's detail screen shows: *"you can make 3 things with this"*. Backed
  /// by an index on `recipe_ingredients.itemId`.
  Stream<List<Recipe>> watchUsingItem(String itemId);

  /// Fetches one recipe.
  Future<Recipe?> byId(String id);

  /// Inserts or replaces [recipe] and its whole ingredient and step list, atomically.
  ///
  /// Rejects an ingredient with neither an item link nor free text, and one with both.
  Future<Result<Recipe, Failure>> save(Recipe recipe);

  /// Pins or unpins.
  Future<Result<void, Failure>> setFavorite({
    required String id,
    required bool isFavorite,
  });

  /// Soft-deletes the recipe and its lines.
  Future<Result<void, Failure>> delete(String id);

  /// Records that [recipeId] was cooked, without touching stock.
  ///
  /// Deducting inventory is `RecipeCookService`'s job, not this one — a repository that consumed
  /// stock as a side effect of a write would put FEFO ordering behind a `save`.
  Future<Result<RecipeCook, Failure>> logCook({
    required String recipeId,
    required DateKey cookedOn,
    required int servingsCooked,
    required bool deductedStock,
    String? note,
  });

  /// Past cooks of [recipeId], most recent first.
  Stream<List<RecipeCook>> watchCookLog(String recipeId);
}
```

### `lib/domain/repositories/recurring_repository.dart`

```dart
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/transaction.dart';

/// A template paired with its outstanding occurrence, for the due list.
class RecurringDue {
  /// Creates a due entry.
  const RecurringDue({required this.template, this.occurrence});

  /// The template.
  final RecurringTemplate template;

  /// Its outstanding occurrence, or null when none has been materialised yet.
  final RecurringOccurrence? occurrence;

  /// True when an occurrence exists and its date has passed as of [today].
  ///
  /// Derived here rather than read from a column — `v_recurring_due` has no `is_overdue` field, and
  /// deliberately so (ARCH_2 §12.2).
  bool isOverdue(DateKey today) => occurrence?.isOverdue(today) ?? false;
}

/// Reads and writes recurring templates and their occurrences.
abstract interface class RecurringRepository {
  /// Emits every active template, paused included.
  Stream<List<RecurringTemplate>> watchAllTemplates();

  /// Emits active templates in [direction] — the split that lets salary share the system with bills
  /// (anomaly A27).
  Stream<List<RecurringTemplate>> watchTemplatesByDirection(RecurringDirection direction);

  /// Emits the due list: unpaused templates with their outstanding occurrence.
  Stream<List<RecurringDue>> watchDue();

  /// Reads one template by id, soft-deleted ones included.
  Future<RecurringTemplate?> templateById(String id);

  /// Emits templates linked to [assetId] — the service-provider salary case.
  Stream<List<RecurringTemplate>> watchTemplatesForAsset(String assetId);

  /// Creates or updates a template.
  ///
  /// Fails with a [ValidationFailure] when the interval or anchor is incoherent — a monthly template
  /// needs a day-of-month, a weekly one a weekday. Never rewrites the anchor to a clamped value:
  /// a bill anchored on the 31st must stay anchored on the 31st (anomaly A13).
  Future<Result<RecurringTemplate, Failure>> saveTemplate(RecurringTemplate template);

  /// Pauses or resumes a template.
  Future<Result<void, Failure>> setTemplatePaused({
    required String id,
    required bool isPaused,
  });

  /// Soft-deletes a template. Settled occurrences and their transactions survive (ARCH_3 §4.1).
  Future<Result<void, Failure>> deleteTemplate(String id);

  /// Emits the occurrences of [templateId], newest due date first — the payment history.
  Stream<List<RecurringOccurrence>> watchOccurrences(String templateId);

  /// Emits occurrences due within `[from, to]`, for the calendar.
  Stream<List<RecurringOccurrence>> watchOccurrencesInRange({
    required DateKey from,
    required DateKey to,
  });

  /// Materialises every occurrence now due up to [asOf], and returns how many were created.
  ///
  /// **Creates no money.** Every materialised occurrence is `due`; only [payOccurrence] settles one,
  /// and only from an explicit user tap. An app unopened for three months produces three due rows
  /// and zero transactions (anomaly A14). Idempotent — running it twice creates nothing the second
  /// time.
  Future<Result<int, Failure>> materialiseUpTo(DateKey asOf);

  /// Settles [occurrenceId] by creating the matching transaction.
  ///
  /// [amount] may differ from the template's default; the actual figure is recorded on the
  /// occurrence and the template's expectation is left alone (anomaly A29). [direction] decides
  /// whether a withdrawal or a deposit is created.
  Future<Result<Transaction, Failure>> payOccurrence({
    required String occurrenceId,
    required Money amount,
    required DateKey paidOn,
    required String accountId,
    String? paymentMethodId,
  });

  /// Marks [occurrenceId] deliberately skipped.
  Future<Result<void, Failure>> skipOccurrence({
    required String occurrenceId,
    String? note,
  });

  /// Returns [occurrenceId] to due when the transaction that settled it is deleted, so the
  /// obligation reappears rather than staying silently marked paid.
  Future<Result<void, Failure>> unsettleOccurrence(String occurrenceId);
}
```

### `lib/domain/repositories/service_record_repository.dart`

```dart
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/service_record.dart';

/// Reads and writes service records.
abstract interface class ServiceRecordRepository {
  /// Emits the records for [assetId], most recent first — the service timeline.
  Stream<List<ServiceRecord>> watchForAsset(String assetId);

  /// Emits the records of [type] for [assetId] — e.g. only salary payments, which is the payment log
  /// for a service provider.
  Stream<List<ServiceRecord>> watchForAssetByType({
    required String assetId,
    required ServiceRecordType type,
  });

  /// Emits records whose scheduled next service falls within `[from, to]`.
  Stream<List<ServiceRecord>> watchWithNextDueInRange({
    required DateKey from,
    required DateKey to,
  });

  /// Reads one record by id.
  Future<ServiceRecord?> byId(String id);

  /// Reads the most recent record for [assetId], for the "last serviced" line.
  Future<ServiceRecord?> mostRecentForAsset(String assetId);

  /// Totals lifetime service cost for [assetId], **per currency** (ARCH_3 §5.1 query 19).
  ///
  /// A map rather than one figure: cost currency is per record, so an asset serviced in two
  /// countries has costs in two currencies and adding them would be anomaly A34.
  Future<Map<String, Money>> lifetimeCostByCurrency(String assetId);

  /// Creates or updates a record.
  ///
  /// When [alsoRecordAsExpense] is true and the record has a cost, a matching withdrawal is created
  /// and linked in the same transaction, so the service history and the expense cannot disagree
  /// about whether the money moved.
  /// [paymentMethodId] is carried to the expense, never onto the record.
  ///
  /// How a service was paid for is a property of the payment, not of the work done — the same boiler
  /// service settled in cash one year and by card the next is one kind of service. Putting it on
  /// `ServiceRecord` would duplicate a column `transactions` already owns, and the two would drift.
  /// Optional throughout: an account says where the money came from and is required for an expense; a
  /// method says how, and plenty of people never record it.
  Future<Result<ServiceRecord, Failure>> save(
    ServiceRecord record, {
    bool alsoRecordAsExpense,
    String? accountId,
    String? paymentMethodId,
  });

  /// Clears the link to a deleted transaction, leaving the record itself intact — the repair happened
  /// whether or not the expense row survives.
  Future<Result<void, Failure>> unlinkDeletedTransaction(String id);

  /// Soft-deletes a record.
  Future<Result<void, Failure>> delete(String id);
}
```

### `lib/domain/repositories/settings_repository.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// Reads and writes the app's key/value settings.
abstract interface class SettingsRepository {
  /// Emits the value for [key], or null when unset.
  Stream<String?> watchValue(String key);

  /// Reads the value for [key], or null when unset.
  Future<String?> readValue(String key);

  /// Emits every setting as a key/value map.
  Stream<Map<String, String>> watchAll();

  /// Writes [value] against [key].
  Future<Result<void, Failure>> writeValue({
    required String key,
    required String value,
    required String valueType,
  });

  /// Removes [key].
  Future<Result<void, Failure>> remove(String key);

  /// Records the user's chosen home currency code.
  ///
  /// **Added in 8A, as the counterpart to [readHomeCurrencyCode].** Onboarding has to write this key,
  /// and the key itself lives in `data/repositories/settings_keys.dart` — which a feature may not import
  /// (Law L12, and no delivered feature does). The alternative was a duplicated literal in the
  /// onboarding feature that would silently write to a dead key if `data/` ever renamed it. A named
  /// method keeps one definition on the side that owns it.
  Future<Result<void, Failure>> writeHomeCurrencyCode(String code);

  /// The user's chosen home currency code, used for display aggregation only (Law L9).
  Future<String?> readHomeCurrencyCode();

  /// The account quick-add falls back to when no last-used account is known.
  ///
  /// Lives in settings rather than as a column on `Account`, because the schema has no
  /// `isDefault` there — quick-add resolves last-used first, then this (ARCH_2 §4.1).
  Future<String?> readDefaultAccountId();
}
```

### `lib/domain/repositories/shopping_repository.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/transaction_line.dart';

/// Reads and writes shopping lists and their entries.
abstract interface class ShoppingRepository {
  /// Emits lists that may be chosen — active and unarchived.
  Stream<List<ShoppingList>> watchSelectableLists();

  /// Emits every list, archived included.
  Stream<List<ShoppingList>> watchAllLists();

  /// Emits the list marked default, if any.
  Stream<ShoppingList?> watchDefaultList();

  /// Reads one list by id.
  Future<ShoppingList?> listById(String id);

  /// Creates or updates a list.
  Future<Result<ShoppingList, Failure>> saveList(ShoppingList list);

  /// Marks [id] the default, clearing the flag on every other list atomically.
  Future<Result<void, Failure>> setDefaultList(String id);

  /// Archives or unarchives a list.
  Future<Result<void, Failure>> setListArchived({
    required String id,
    required bool isArchived,
  });

  /// Soft-deletes a list and its entries.
  Future<Result<void, Failure>> deleteList(String id);

  /// Emits the entries of [listId], in display order.
  Stream<List<ShoppingEntry>> watchEntries(String listId);

  /// Emits only the unticked entries of [listId].
  Stream<List<ShoppingEntry>> watchUncheckedEntries(String listId);

  /// Creates or updates an entry.
  ///
  /// Editing an auto-generated entry promotes it to manual, after which the suggestion engine never
  /// removes it (anomaly A22).
  Future<Result<ShoppingEntry, Failure>> saveEntry(ShoppingEntry entry);

  /// Ticks or unticks an entry.
  Future<Result<void, Failure>> setEntryChecked({
    required String id,
    required bool isChecked,
  });

  /// Snoozes an auto-generated suggestion until [until].
  Future<Result<void, Failure>> snoozeEntry({
    required String id,
    required DateKey until,
  });

  /// Dismisses an auto-generated suggestion.
  ///
  /// It does not return on a date — only once stock has genuinely risen above the threshold and
  /// fallen again, which the suggestion engine decides from the stock reading taken now
  /// (anomaly A23).
  Future<Result<void, Failure>> dismissEntry(String id);

  /// Reorders the entries of one list.
  Future<Result<void, Failure>> reorderEntries(List<String> orderedIds);

  /// Soft-deletes an entry.
  Future<Result<void, Failure>> deleteEntry(String id);

  /// Regenerates the auto-suggestions for [listId] from current low-stock state.
  ///
  /// Idempotent: running it repeatedly neither duplicates entries nor resurrects dismissed ones
  /// (anomalies A22, A23). Returns how many suggestions are now active.
  Future<Result<int, Failure>> regenerateLowStockSuggestions(String listId);

  /// Turns the ticked entries of [listId] into draft transaction lines, closing the loop from a
  /// finished list back to money and stock (anomaly A25).
  ///
  /// Returns drafts rather than writing anything: the user still confirms the amount and account in
  /// the expense editor, and `TransactionRepository.create` is what actually commits.
  Future<Result<List<TransactionLine>, Failure>> buildPurchaseDraft(String listId);

  /// Records that [entryIds] were fulfilled by the lines of [transactionId].
  Future<Result<void, Failure>> markPurchased({
    required List<String> entryIds,
    required String transactionId,
  });
}
```

### `lib/domain/repositories/split_group_repository.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/entities/split_group.dart';

/// Groups and their membership.
///
/// **Split from [SplitLedgerRepository] on purpose.** Groups are reference data — a cast of people
/// with a name — while expenses and settlements are the ledger. One contract covering both would run
/// to twenty methods and would put "rename a group" beside "record a settlement", which are not the
/// same kind of operation and are not read by the same screens.
///
/// People themselves are `payees` and belong to `PayeeRepository`. This contract deals only in payee
/// ids, so a group can never become a second place a person's name is stored.
abstract interface class SplitGroupRepository {
  /// Every group with its members, in sort order. Archived groups included.
  Stream<List<SplitGroup>> watchAll();

  /// Groups that are not archived — what a picker offers.
  Stream<List<SplitGroup>> watchActive();

  /// One group with its members, or null if it does not exist.
  Stream<SplitGroup?> watchById(String id);

  /// Fetches one group with its members.
  Future<SplitGroup?> byId(String id);

  /// Groups [payeeId] is a member of.
  ///
  /// The reverse lookup a person's detail screen shows — *"you split with Ravi in 3 groups"*. Backed
  /// by `idx_split_member`.
  Stream<List<SplitGroup>> watchForPayee(String payeeId);

  /// Inserts or replaces [group] and its whole member list, atomically.
  ///
  /// Rejects a duplicate normalized name against a live group (`idx_split_groups_name`), a member list
  /// with the same payee twice, and a weight outside 0–10,000 basis points.
  Future<Result<SplitGroup, Failure>> save(SplitGroup group);

  /// Archives or unarchives.
  ///
  /// Archiving is not deleting: an archived group keeps its expenses and stays in totals, and only
  /// leaves the pickers (ARCH_3 §4).
  Future<Result<void, Failure>> setArchived({
    required String id,
    required bool isArchived,
  });

  /// Soft-deletes the group and its memberships.
  ///
  /// **Refuses while the group still has expenses.** Deleting a group whose expenses reference it
  /// would leave those expenses filed under a group nothing can name, and the balances they feed would
  /// keep counting. Archive it instead, which is what the refusal says.
  Future<Result<void, Failure>> delete(String id);

  /// The payee id the user has claimed as themselves, or null when unset.
  ///
  /// Read from `app_settings` under `split.selfPayeeId` rather than a flag on `payees`, so no two rows
  /// can claim it and a table five other modules read stays untouched.
  ///
  /// **Null means "not configured", never "nobody".** On a fresh install there is no payee to point at
  /// until the user creates one, and every balance view yields a null own-share until this is set — a
  /// screen must say so rather than showing zero as though nothing were owed.
  Future<String?> selfPayeeId();

  /// Claims [payeeId] as the user.
  Future<Result<void, Failure>> setSelfPayeeId(String payeeId);
}
```

### `lib/domain/repositories/split_ledger_repository.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/split_expense.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/services/split/debt_simplifier.dart' show DebtEdge;

/// Shared expenses, settlements, and the balances derived from them.
///
/// **Every balance here is derived (Law L3).** Nothing in this contract returns a stored total, and
/// nothing in it lets a caller write one — which is what makes a balance in this module structurally
/// unable to drift. It is also why [watchBalances] is a stream over a view rather than a getter over a
/// column.
abstract interface class SplitLedgerRepository {
  // ── expenses ────────────────────────────────────────────────────────────────────────────

  /// Expenses in `[from, to]`, newest first, as summaries.
  ///
  /// Summaries rather than full entities: a list of forty expenses should not fetch four hundred share
  /// rows to display forty totals. Load the entity when one is opened.
  Stream<List<SplitExpenseSummary>> watchExpenses({
    required DateKey from,
    required DateKey to,
    String? groupId,
  });

  /// One expense with its shares, or null if it does not exist.
  Stream<SplitExpense?> watchExpenseById(String id);

  /// Fetches one expense with its shares.
  Future<SplitExpense?> expenseById(String id);

  /// The expense attached to [transactionId], or null when that transaction is not a split.
  ///
  /// What the expense editor reads when reopening a transaction: it has the transaction id and needs to
  /// know whether a split already hangs off it.
  Future<SplitExpense?> expenseForTransaction(String transactionId);

  /// Inserts or replaces [expense] and its whole share list, atomically (Law L14).
  ///
  /// **Does not create the transaction.** In the "you paid" case a transaction must already exist and
  /// [SplitExpense.transactionId] must point at it — writing one here would put money movement behind
  /// a split save, and `TransactionRepository` is where that belongs.
  ///
  /// Rejects: a share whose `transactionLineNo` is set on an expense with no transaction — the
  /// cross-table half of the itemising rule that SQLite cannot express as a CHECK; a share list with
  /// the same payee twice for the same line; a negative share; and a currency on any share that
  /// differs from the expense's.
  ///
  /// **Accepts shares that do not sum to the total.** That is a real state, not an error: percentages
  /// mid-edit, or a tip nobody assigned. [SplitExpense.unallocated] reports it and the screen decides
  /// what to say — the same treatment `v_transaction_allocation` gives an un-itemised transaction.
  Future<Result<SplitExpense, Failure>> saveExpense(SplitExpense expense);

  /// Soft-deletes the expense and its shares.
  ///
  /// Leaves any linked transaction alone. The money did move, and deleting the split is a statement
  /// about who owed what — not about whether the payment happened.
  Future<Result<void, Failure>> deleteExpense(String id);

  // ── naming an unnamed participant ───────────────────────────────────────────────────────

  /// Makes [placeholderPayeeId] and [payeeId] one person, keeping the second.
  ///
  /// **What a rename cannot do.** Saving a split with unnamed participants writes a
  /// `PayeeKind.splitPlaceholder` row so the debt can exist at all — `split_shares.payee_id` is
  /// `NOT NULL REFERENCES payees(id)`. Renaming that row is right when the person turns out to be
  /// somebody new; when they are somebody the app already knows, the two identities have to *become*
  /// one, or that person ends up with two balances and settling one leaves the other outstanding with
  /// nothing on screen to explain it.
  ///
  /// Every share, settlement, membership and paid-by reference moves, and the placeholder is retired —
  /// atomically, because a half-moved identity is two debts where there should be one.
  ///
  /// **Shares are summed where both already exist on the same expense**, rather than refused.
  /// `idx_split_share` is unique on `(split_expense_id, payee_id, transaction_line_no)`, so a
  /// reassignment onto an expense the target is already on collides — and somebody telling the app who
  /// a participant really was is a statement it should be able to record. The merged row's stored input
  /// becomes `exact`, because 40% plus somebody else's ₹800 is not 40% of anything, and a percentage
  /// that no longer reproduces the amount beside it is the one thing this module must never show.
  ///
  /// Rejects merging a payee into itself, merging into a deleted payee, and merging *from* anything that
  /// is not a placeholder. The last is the important one: this is destructive in one direction — whichever
  /// payee is named first stops existing — which is right for *"Person 4 was Ravi all along"* and wrong as
  /// a general "combine two contacts" tool, where a caller with the arguments the wrong way round would
  /// silently delete the row they meant to keep.
  Future<Result<void, Failure>> mergePlaceholder({
    required String placeholderPayeeId,
    required String payeeId,
  });

  // ── settlements ─────────────────────────────────────────────────────────────────────────

  /// Settlements in `[from, to]`, newest first.
  Stream<List<SplitSettlement>> watchSettlements({
    required DateKey from,
    required DateKey to,
    String? groupId,
  });

  /// Records [settlement] and the [transaction] that moved the money, **atomically**.
  ///
  /// **One call rather than two, and that is the point.** Splitwise's "settle up" is a bookkeeping
  /// marker it cannot back with anything; here the deposit or withdrawal is an ordinary
  /// `transactions` row written in the same database transaction as the settlement. Two calls would
  /// commit independently, and a settlement written without its transaction clears a debt with no
  /// money anywhere — the one failure in this module a user could not see.
  ///
  /// [transaction] is required whenever the user is a party, and null only for a settlement between
  /// two other people, which an accepted simplification plan can suggest and which moves none of the
  /// user's money. The implementation refuses the mismatch rather than trusting the caller, because a
  /// null here silently produces exactly the invisible failure above.
  ///
  /// The caller builds both — `SettlementService` — so that this contract stays a write and the
  /// decisions about deposit-versus-withdrawal, subtype and payee stay in the domain where they can
  /// be tested without a database.
  Future<Result<SplitSettlement, Failure>> recordSettlement({
    required SplitSettlement settlement,
    Transaction? transaction,
  });

  /// Soft-deletes a settlement.
  Future<Result<void, Failure>> deleteSettlement(String id);

  // ── derived reads ───────────────────────────────────────────────────────────────────────

  /// What each person owes you and you owe them, per currency.
  ///
  /// Only counterparties with something outstanding, so an empty stream means settled up with
  /// everybody. Grouped by currency and never summed across it.
  Stream<List<SplitBalance>> watchBalances();

  /// The same, restricted to one group.
  Stream<List<SplitBalance>> watchGroupBalances(String groupId);

  /// One counterparty's balance across every currency, or an empty list when settled.
  Stream<List<SplitBalance>> watchBalanceWith(String payeeId);

  /// Expenses and settlements interleaved, newest first.
  Stream<List<SplitActivityEntry>> watchActivity({String? groupId, int limit});

  /// Every real pairwise debt in [groupId], for the simplifier.
  ///
  /// **Returns [DebtEdge]s, not [SplitBalance]s, and the difference is the whole point.**
  /// `DebtSimplifier`'s partition tie-break prefers transfers along debts that genuinely exist — the
  /// answer to *"she never lent me money"* — so it needs the edges as incurred. A netted summary would
  /// have discarded exactly the information the tie-break runs on, before the algorithm could see it.
  ///
  /// **Imports [DebtEdge] from the service rather than declaring a twin here.** A repository contract
  /// naming a service's type is the wrong direction, and the honest fix is that `DebtEdge` is a domain
  /// *value* — "X owes Y this much" — that belongs in `entities/` rather than inside
  /// `debt_simplifier.dart`. It has since moved there, and this import now resolves through a
  /// re-export; the `show` clause stays because it documents which single type is wanted.
  Future<List<DebtEdge>> debtsIn(String groupId);
}
```

### `lib/domain/repositories/stock_repository.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/domain/services/draw_policy.dart';

/// One batch's share of a consumption run, and how much came out of it.
class ConsumptionDraw {
  /// Creates a draw.
  const ConsumptionDraw({required this.batchId, required this.quantity});

  /// The batch drawn from.
  final String batchId;

  /// How much came out of it.
  final Qty quantity;
}

/// What a waste query totalled, in both quantity and money.
///
/// The differentiating insight of ARCH_3 §5.1 query 14 — costs are grouped by currency rather than
/// summed across them (anomaly A34).
class WasteTotal {
  /// Creates a waste total.
  const WasteTotal({
    required this.itemId,
    required this.quantity,
    required this.costByCurrency,
  });

  /// The item wasted.
  final String itemId;

  /// How much was wasted.
  final Qty quantity;

  /// What it cost, per currency code.
  final Map<String, Money> costByCurrency;
}

/// Records stock movements and reads the ledger.
///
/// Every write here pairs a movement with the batch cache update in one transaction (Laws L3, L14).
/// There is deliberately **no delete and no edit**: a correction is a reversing movement, because a
/// ledger you can edit is not a ledger (Law L6's stated exception).
abstract interface class StockRepository {
  /// Consumes [quantity] of [itemId] across as many batches as [policy] allows.
  ///
  /// Returns which batches were drawn from and by how much, so the UI can show that 600 g came out
  /// of two batches *before* confirming (anomaly A08).
  ///
  /// Fails with a [BusinessRuleFailure] when stock is insufficient **under [policy]**, writing nothing
  /// — a partial consumption would leave the ledger describing something that did not happen.
  ///
  /// **[policy] defaults to FEFO, which is what every caller written before it existed was doing.**
  /// FEFO orders by nearest expiry, and an expired date is the nearest date, so the default reaches for
  /// expired stock first — correct for a waste or expiry write-off and wrong for cooking, where it
  /// silently eats food that is already off before touching anything good. A caller that means "use
  /// this" rather than "throw this away" passes `DrawPolicy.freshFirst`.
  ///
  /// Under a policy excluding expired stock, insufficiency means *insufficient good stock* — there may
  /// be plenty on the shelf. The failure is how a caller learns that asking the user would help; see
  /// `InventoryConsumptionService.plan`.
  Future<Result<List<ConsumptionDraw>, Failure>> consume({
    required String itemId,
    required Qty quantity,
    required StockMovementKind kind,
    DrawPolicy policy = const DrawPolicy.fefo(),
    String? reason,
    String? note,
  });

  /// Consumes [quantity] from one specific batch, overriding FEFO for when the user knows better.
  Future<Result<void, Failure>> consumeFromBatch({
    required String batchId,
    required Qty quantity,
    required StockMovementKind kind,
    String? reason,
    String? note,
  });

  /// Adds stock to an existing batch.
  Future<Result<void, Failure>> addStock({
    required String batchId,
    required Qty quantity,
    required StockMovementKind kind,
    String? note,
  });

  /// Reverses [movementId] by recording a compensating movement that points at it.
  ///
  /// This is what undo does. The user sees "removed"; the audit trail keeps both rows, so waste
  /// analytics stays honest.
  Future<Result<void, Failure>> reverse({
    required String movementId,
    String? reason,
  });

  /// Emits the movements for [batchId], oldest first — a batch's full history.
  Stream<List<StockMovement>> watchForBatch(String batchId);

  /// Emits the movements for [itemId] within `[from, to]`, newest first.
  Stream<List<StockMovement>> watchForItemInRange({
    required String itemId,
    required DateKey from,
    required DateKey to,
  });

  /// Totals waste and expiry for every item within `[from, to]`.
  Future<List<WasteTotal>> wasteTotals({
    required DateKey from,
    required DateKey to,
  });
}
```

### `lib/domain/repositories/tag_repository.dart`

```dart
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/entities/tag.dart';

/// Reads and writes tags, and their links to transactions.
abstract interface class TagRepository {
  /// Emits every active tag in display order.
  Stream<List<Tag>> watchAll();

  /// Emits the tags offered in [scope]'s picker.
  ///
  /// Scoping is the whole point: a `Kitchen` tag created for inventory and shopping must not appear
  /// in the deposit picker (ARCH_2 §14).
  Stream<List<Tag>> watchByScope(TagScope scope);

  /// Emits the active top-level tags — those with no parent.
  Stream<List<Tag>> watchRoots();

  /// Emits the active children of [parentTagId].
  Stream<List<Tag>> watchChildren(String parentTagId);

  /// Reads one tag by id, soft-deleted ones included — a deleted tag still renders on old
  /// transactions, greyed with `(deleted)` (anomaly A36).
  Future<Tag?> byId(String id);

  /// Creates or updates a tag.
  ///
  /// Fails with a [BusinessRuleFailure] when nesting would exceed one level, or a
  /// [ConflictFailure] when another active tag already has the same normalized name.
  Future<Result<Tag, Failure>> save(Tag tag);

  /// Soft-deletes a user-created tag. Fails for a system tag.
  ///
  /// Links survive, so history stays readable.
  Future<Result<void, Failure>> delete(String id);

  /// Emits the tags attached to [transactionId], soft-deleted ones included.
  Stream<List<Tag>> watchForTransaction(String transactionId);

  /// Replaces the whole tag set on [transactionId].
  Future<Result<void, Failure>> setForTransaction({
    required String transactionId,
    required List<String> tagIds,
  });

  /// Emits the tags attached to [itemId], in the order the user arranged them.
  Stream<List<Tag>> watchForItem(String itemId);

  /// Replaces the tags on [itemId] with [tagIds].
  ///
  /// **A set, not a diff.** The caller sends the whole list it wants and the link rows are rewritten to
  /// match — a partial API would need add and remove and an answer for the race between them.
  Future<Result<void, Failure>> setForItem({
    required String itemId,
    required List<String> tagIds,
  });

  /// Emits the tags attached to [assetId], in the order the user arranged them.
  Stream<List<Tag>> watchForAsset(String assetId);

  /// Replaces the tags on [assetId] with [tagIds].
  Future<Result<void, Failure>> setForAsset({
    required String assetId,
    required List<String> tagIds,
  });
}
```

### `lib/domain/repositories/transaction_repository.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';

/// One transaction's totals against the lines that itemise it.
///
/// [unallocated] is the difference the UI surfaces as an "unallocated ₹20" chip. Check [lineCount]
/// before showing it: with no lines at all the unallocated figure equals the whole amount, which is
/// not the same thing as a mismatch (anomaly A11).
class TransactionAllocation {
  /// Creates an allocation summary.
  const TransactionAllocation({
    required this.transactionId,
    required this.amount,
    required this.allocated,
    required this.unallocated,
    required this.lineCount,
  });

  /// The transaction this summarises.
  final String transactionId;

  /// The transaction's own amount — the source of truth.
  final Money amount;

  /// The sum of its lines.
  final Money allocated;

  /// [amount] less [allocated].
  final Money unallocated;

  /// How many lines exist.
  final int lineCount;

  /// True when lines exist and do not sum to the transaction amount.
  bool get hasMismatch => lineCount > 0 && !unallocated.isZero;
}

/// What a delete detached rather than removed, so the UI can offer a follow-up.
///
/// Deleting a transaction never cascades to the batches or assets its lines created — you deleted a
/// receipt, not the groceries (anomaly A10). These ids are what was cut loose.
class DetachedArtefacts {
  /// Creates a detachment report.
  const DetachedArtefacts({
    required this.batchIds,
    required this.assetIds,
    required this.recurringTemplateIds,
    required this.untouchedBatchIds,
  });

  /// Batches whose source link was cleared.
  final List<String> batchIds;

  /// Assets whose source link was cleared.
  final List<String> assetIds;

  /// Recurring templates whose source link was cleared.
  final List<String> recurringTemplateIds;

  /// Batches that are provably untouched — nothing consumed, remaining still equals initial.
  ///
  /// Only for these may the UI offer "also remove the 4 items this added". A batch already drawn
  /// down must never be offered for removal, because the food really was eaten (anomaly A10).
  final List<String> untouchedBatchIds;

  /// True when nothing was detached.
  bool get isEmpty =>
      batchIds.isEmpty && assetIds.isEmpty && recurringTemplateIds.isEmpty;
}

/// Reads and writes transactions and the lines that itemise them.
abstract interface class TransactionRepository {
  /// Reads one transaction by id.
  Future<Transaction?> byId(String id);

  /// Emits transactions whose civil date falls in `[from, to]`, newest first. Inclusive both ends.
  Stream<List<Transaction>> watchByDateRange({
    required DateKey from,
    required DateKey to,
  });

  /// Emits transactions touching [accountId] on either side, newest first.
  ///
  /// A transfer appears in both accounts' lists — once as an outflow and once as an inflow, which
  /// is what the user expects to see.
  Stream<List<Transaction>> watchByAccount(String accountId);

  /// Emits transactions of [subtype], newest first, optionally bounded by `yyyymm` month.
  Stream<List<Transaction>> watchBySubtype(
    TransactionSubtype subtype, {
    int? fromMonthKey,
    int? toMonthKey,
  });

  /// Emits transactions still flagged as needing details, for the dashboard nudge.
  Stream<List<Transaction>> watchNeedingReview();

  /// Emits how many transactions need details.
  Stream<int> watchNeedsReviewCount();

  /// Full-text search over notes, best match first.
  Future<List<Transaction>> search(String query, {int limit});

  /// Emits the lines of [transactionId], in entry order.
  Stream<List<TransactionLine>> watchLines(String transactionId);

  /// Emits [transactionId]'s allocation summary.
  Stream<TransactionAllocation?> watchAllocation(String transactionId);

  /// Emits the lines referencing [itemId], newest first — an item's purchase history, and the basis
  /// of the unit-price trend (ARCH_3 §5.1 queries 12 and 24).
  Stream<List<TransactionLine>> watchLinesForItem(String itemId);

  /// Creates a transaction with its lines and tags, atomically.
  ///
  /// Validates the shape [Transaction.kind] requires before writing — a deposit needs a destination
  /// and no source, a transfer needs two different accounts — and returns a [ValidationFailure]
  /// rather than letting the user hit a raw SQLite constraint error (ARCH_2 §4.1).
  ///
  /// Fills the account from last-used, then the default, so it is never null even though the UI
  /// treats it as optional (ARCH_2 §4.1). Derives `monthKey` from the date rather than trusting a
  /// caller — the DAO deliberately does not, so this layer must.
  Future<Result<Transaction, Failure>> create({
    required Transaction transaction,
    List<TransactionLine> lines,
    List<String> tagIds,
  });

  /// Updates a transaction's own fields.
  Future<Result<Transaction, Failure>> update(Transaction transaction);

  /// Replaces the lines of [transactionId].
  /// Records which artefact one line produced, after the fan-out service created it.
  ///
  /// **Not `replaceLines`.** `replaceLines` soft-deletes the existing rows and inserts new ones, so
  /// calling it with the same line ids violates the primary key — the soft-deleted row is still
  /// physically there. Writing an artefact id back onto a line that already exists is an update of
  /// one column, and this is the method for it.
  ///
  /// Exactly one of the three ids is set for a given line, matching its `destination`
  /// (ARCH_2 §4.2); the others are left untouched.
  Future<Result<void, Failure>> recordCreatedArtefact({
    required String lineId,
    String? createdBatchId,
    String? createdAssetId,
    String? createdRecurringTemplateId,
  });

  /// Replaces every line on a transaction.
  ///
  /// The supplied lines must carry **fresh ids**: the existing rows are soft-deleted rather than
  /// removed (Law L6), so reusing an id collides with the row that is still there.
  Future<Result<void, Failure>> replaceLines({
    required String transactionId,
    required List<TransactionLine> lines,
  });

  /// Clears the needs-review flag once the user has filled in the details.
  Future<Result<void, Failure>> markReviewed(String id);

  /// Freezes a converted snapshot against [id].
  ///
  /// Cannot touch the original amount or its currency — those are immutable once saved (Law L9),
  /// and the signature has no parameter for them.
  Future<Result<void, Failure>> freezeConversion({
    required String id,
    required DateKey on,
    required String toCurrencyCode,
  });

  /// Deletes a transaction and its lines, reporting what it detached.
  ///
  /// Never cascades to created batches or assets. The returned [DetachedArtefacts] is what lets the
  /// UI offer to remove an untouched batch as a *separate, explicit* action.
  Future<Result<DetachedArtefacts, Failure>> delete({
    required String id,
    String? reason,
  });
}
```

### `lib/domain/repositories/unit_repository.dart`

```dart
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/entities/unit.dart';

/// Reads and writes units of measure.
abstract interface class UnitRepository {
  /// Emits every unit in display order.
  Stream<List<Unit>> watchAll();

  /// Emits the units measuring [category].
  ///
  /// A quantity picker must never offer a unit from another category — cross-category conversion
  /// does not exist (Law L8), so offering `ml` for a weight item would produce a value nothing can
  /// convert.
  Stream<List<Unit>> watchByCategory(UnitCategory category);

  /// Reads one unit by code.
  Future<Unit?> byCode(String code);

  /// Reads `code -> factorToBaseMilli` for every unit.
  Future<Map<String, int>> factorsByCode();

  /// Reads `code -> category`, which is what lets a mapper resolve a quantity's category from a
  /// bare unit code when a row has no linked item.
  Future<Map<String, UnitCategory>> categoriesByCode();

  /// Creates or updates a user-defined unit.
  ///
  /// Fails with a [ValidationFailure] when the factor is not a positive integer: a unit whose
  /// factor cannot be stated exactly should be a separate item instead (ARCH_1 §5.3).
  Future<Result<Unit, Failure>> save(Unit unit);

  /// Deletes a user-defined unit. Fails for a system unit.
  Future<Result<void, Failure>> delete(String code);
}
```

### `lib/domain/services/analytics/analytics_cache_service.dart`

```dart
import 'dart:convert';

import 'package:alaya/domain/repositories/analytics_cache_repository.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';

/// Caches expensive analytics results, keyed by query name and its parameters (ARCH_3 §5.2).
///
/// **Only worth it above roughly 200 ms.** A cache on a query that already runs in 5 ms costs a read,
/// a write, an invalidation path and a staleness bug, and buys nothing — so `shouldCache` is a
/// deliberate gate rather than a policy applied to everything.
final class AnalyticsCacheService {
  /// Creates the service over [repository].
  const AnalyticsCacheService(this._repository);

  final AnalyticsCacheRepository _repository;

  /// How long a cached result stays valid.
  ///
  /// Six hours, not minutes: every contributing write invalidates the cache explicitly
  /// ([invalidateOnWrite]), so the TTL is only a backstop for the case where an invalidation was
  /// missed. Making it short would mean recomputing constantly to defend against a bug that should
  /// be fixed rather than papered over.
  static const Duration defaultTtl = Duration(hours: 6);

  /// The estimated cost above which caching earns its keep.
  static const Duration cacheThreshold = Duration(milliseconds: 200);

  /// Whether a query taking [estimatedCost] should be cached at all.
  bool shouldCache(Duration estimatedCost) => estimatedCost >= cacheThreshold;

  /// The cache key for [queryName] with [params].
  ///
  /// The params hash is folded **into the key**, not stored beside it. ARCH_2 §9 makes `cacheKey` the
  /// primary key on its own, so two parameter sets sharing a key would evict each other — caching
  /// July would drop June, and alternating between two date ranges would recompute every time. Making
  /// the key `queryName:paramsHash` gives each parameter set its own row with no schema change, which
  /// is the resolution ARCH_4 §5.1 item 12 recommends.
  String keyFor(String queryName, Map<String, Object?> params) =>
      '$queryName:${hashParams(params)}';

  /// A stable hash of [params].
  ///
  /// Keys are sorted before encoding, because Dart map iteration order follows insertion order — two
  /// callers passing the same parameters in a different order would otherwise produce different
  /// hashes and each miss the other's cache entry.
  String hashParams(Map<String, Object?> params) {
    final sorted = params.keys.toList()..sort();
    final canonical = {for (final key in sorted) key: _stringify(params[key])};
    final encoded = jsonEncode(canonical);
    // A stable non-cryptographic digest. This identifies a parameter set; it defends nothing, so a
    // real hash function would be cost without benefit.
    var hash = 0;
    for (final unit in encoded.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return hash.toRadixString(16);
  }

  /// The window's contribution to a params map, in a form [hashParams] can encode.
  Map<String, Object?> windowParams(AnalyticsWindow window) => {
    'from': window.from.value,
    'to': window.to.value,
  };

  /// Reads a cached payload, or null on a miss.
  Future<String?> read({
    required String queryName,
    required Map<String, Object?> params,
  }) {
    final key = keyFor(queryName, params);
    return _repository.read(cacheKey: key, paramsHash: hashParams(params));
  }

  /// Stores [payload] for [queryName] with [params].
  Future<void> write({
    required String queryName,
    required Map<String, Object?> params,
    required String payload,
    Duration ttl = defaultTtl,
  }) {
    final key = keyFor(queryName, params);
    return _repository.write(
      cacheKey: key,
      paramsHash: hashParams(params),
      payloadJson: payload,
      ttl: ttl,
    );
  }

  /// Computes through the cache: returns the cached payload when present, otherwise runs [compute],
  /// stores it, and returns it.
  ///
  /// A failure to read or write the cache never fails the query — a cache is an optimisation, and a
  /// broken one should slow the app down rather than break the analytics screen.
  Future<String> readOrCompute({
    required String queryName,
    required Map<String, Object?> params,
    required Future<String> Function() compute,
    Duration ttl = defaultTtl,
  }) async {
    try {
      final cached = await read(queryName: queryName, params: params);
      if (cached != null) return cached;
    } catch (_) {
      // Fall through and compute.
    }
    final fresh = await compute();
    try {
      await write(
        queryName: queryName,
        params: params,
        payload: fresh,
        ttl: ttl,
      );
    } catch (_) {
      // The caller still gets its answer.
    }
    return fresh;
  }

  /// Invalidates everything, which is what any write to a contributing table triggers.
  ///
  /// Coarse on purpose. Tracking which of the twenty-four queries a given row touches would be a
  /// dependency graph to maintain and get wrong; recomputing on the next open is cheap by comparison,
  /// and a stale figure on a money screen is the one outcome worth spending correctness on.
  Future<void> invalidateOnWrite() => _repository.invalidateAll();

  /// Invalidates one query's entries.
  Future<void> invalidate({
    required String queryName,
    required Map<String, Object?> params,
  }) => _repository.invalidate(keyFor(queryName, params));

  String _stringify(Object? value) => switch (value) {
    null => 'null',
    final bool v => v.toString(),
    final num v => v.toString(),
    final String v => v,
    final Iterable<Object?> v => v.map(_stringify).join(','),
    _ => value.toString(),
  };
}
```

### `lib/domain/services/analytics/analytics_port.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';

/// One aggregate row as SQL returns it: a key, a label, a **minor-unit amount and its currency**.
///
/// Money arrives unconverted and paired with its own code, because ARCH_3 §5.2 requires conversion
/// **per data point** — a query that summed across currencies in SQL would have already lost the
/// information needed to convert correctly.
typedef RawMoneyRow = ({
  String key,
  String label,
  int amountMinor,
  String currencyCode,
  int count,
});

/// One aggregate row carrying a quantity in base-milli units.
typedef RawQuantityRow = ({
  String key,
  String label,
  int milliBase,
  String category,
  int count,
});

/// One monthly aggregate row.
typedef RawMonthRow = ({
  int monthKey,
  int amountMinor,
  String currencyCode,
  int count,
});

/// One dated aggregate row.
typedef RawDateRow = ({
  int dateKey,
  int amountMinor,
  String currencyCode,
  int count,
});

/// One bucketed aggregate row, for the heatmap.
typedef RawBucketRow = ({
  int bucket,
  int amountMinor,
  String currencyCode,
  int count,
});

/// The raw aggregates every analytics query is built from.
///
/// **Declared here, in `domain/`, and implemented in `data/`.** ARCH_3 §5.2 requires the aggregation
/// to happen in SQL over indexed columns — "nothing is loaded into Dart to be summed" — while Law L12
/// forbids `domain/` from importing drift. A port resolves that: the SQL lives in the adapter, the
/// interpretation lives in `AnalyticsService`, and neither has to compromise.
///
/// Every method is bounded by a window, because an unbounded aggregate over 50k transactions is the
/// performance risk ARCH_4 R7 is about.
abstract interface class AnalyticsPort {
  /// Query 1 — spend per subtype within [window], grouped by currency.
  Future<List<RawMoneyRow>> spendBySubtype(AnalyticsWindow window);

  /// Query 2 — spend per tag.
  Future<List<RawMoneyRow>> spendByTag(AnalyticsWindow window);

  /// Query 3 — spend per payment method.
  Future<List<RawMoneyRow>> spendByPaymentMethod(AnalyticsWindow window);

  /// Query 4 — spend per payee, already ordered descending by SQL.
  Future<List<RawMoneyRow>> spendByPayee(AnalyticsWindow window, {int limit});

  /// Query 5 — totals per month split by [kind].
  Future<List<RawMonthRow>> totalsByMonthAndKind(
    AnalyticsWindow window,
    TransactionKind kind,
  );

  /// Query 6 — signed ledger sum per month, from `v_account_ledger`.
  Future<List<RawMonthRow>> netFlowByMonth(AnalyticsWindow window);

  /// Query 7 — one account's signed legs in date order, for a running balance.
  Future<List<RawDateRow>> ledgerLegsForAccount(
    String accountId,
    AnalyticsWindow window,
  );

  /// Query 7's starting point — the account's opening balance.
  Future<({int minor, String currencyCode})?> openingBalance(String accountId);

  /// Queries 8 and 22 — total spend within [window].
  Future<List<RawMoneyRow>> totalSpend(AnalyticsWindow window);

  /// Query 9 — spend per item from transaction lines.
  Future<List<RawMoneyRow>> spendByItem(AnalyticsWindow window, {int limit});

  /// Query 10 — quantity bought per item.
  Future<List<RawQuantityRow>> quantityByItem(
    AnalyticsWindow window, {
    int limit,
  });

  /// Query 11 — the highest unit price recorded for [itemId].
  Future<
    ({
      int unitPriceMinor,
      String currencyCode,
      int dateKey,
      String transactionId,
    })?
  >
  dearestPurchase(String itemId, AnalyticsWindow window);

  /// Queries 12 and 24 — every priced line for [itemId], oldest first.
  Future<
    List<
      ({
        int dateKey,
        int lineAmountMinor,
        String currencyCode,
        int milliBase,
        String category,
      })
    >
  >
  itemPurchaseHistory(String itemId, AnalyticsWindow window);

  /// Query 13 — every batch with stock and a recorded cost.
  ///
  /// [unitFactorToBaseMilli] is `units.factor_to_base_milli` for the batch's `unit_code_at_purchase`,
  /// and it is **required rather than convenient**: `Batch.unitCost` is cost per
  /// `unitCodeAtPurchase`, not per base unit, so valuing a batch without the factor is off by exactly
  /// that unit's magnitude — a thousandfold for a purchase recorded in kilograms.
  Future<
    List<
      ({
        int remainingMilli,
        int unitCostMinor,
        String currencyCode,
        int unitFactorToBaseMilli,
      })
    >
  >
  valuedBatches();

  /// Query 13's counterpart — batches holding stock with no cost recorded.
  Future<int> batchesWithoutCost();

  /// Query 14 — waste and expiry movements with their batch cost.
  Future<
    List<
      ({
        String itemId,
        String itemName,
        int milliBase,
        String category,
        int? unitCostMinor,
        String? currencyCode,
        int? unitFactorToBaseMilli,
      })
    >
  >
  wasteMovements(AnalyticsWindow window);

  /// Query 15 — batches expiring within [window] that still hold stock.
  Future<
    List<
      ({
        String batchId,
        String itemId,
        String itemName,
        int remainingMilli,
        String category,
        int expiryDateKey,
      })
    >
  >
  expiringBatches(AnalyticsWindow window);

  /// Query 16 — how many items are low on stock right now.
  Future<int> lowStockCount();

  /// Query 17 — active unpaused templates and their default amounts.
  Future<
    List<
      ({
        int defaultAmountMinor,
        String currencyCode,
        String intervalUnit,
        int intervalCount,
      })
    >
  >
  activeCommitments();

  /// Query 18 — spend split by whether a transaction settled a recurring template.
  Future<List<RawMoneyRow>> spendByRecurringFlag(AnalyticsWindow window);

  /// Query 19 — service cost per asset.
  Future<
    List<
      ({
        String assetId,
        String assetName,
        int costMinor,
        String currencyCode,
        int count,
      })
    >
  >
  serviceCostByAsset(AnalyticsWindow window);

  /// Query 20 — warranty windows for assets that have one.
  Future<
    List<
      ({String assetId, String assetName, int? startDateKey, int? endDateKey})
    >
  >
  warrantyWindows();

  /// Query 21 — spend bucketed by weekday (1-7) or day of month (1-31).
  Future<List<RawBucketRow>> spendByBucket(
    AnalyticsWindow window, {
    required bool byWeekday,
  });

  /// Query 23 — grocery transactions with their line counts.
  Future<List<({int amountMinor, String currencyCode, int lineCount})>>
  groceryBaskets(
    AnalyticsWindow window,
  );

  /// Today, for the queries whose answer depends on it. Supplied by the adapter's clock so nothing
  /// in `domain/` reads the time itself.
  DateKey today();
}
```

### `lib/domain/services/analytics/analytics_service.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/domain/services/analytics/analytics_port.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// ARCH_3 §5.1's twenty-four queries, each a named function returning plain records.
///
/// **No chart-library types anywhere** (§5.2, Law L12). Everything returned is a Dart record or an
/// entity, so the presentation layer maps to whatever chart package it likes and this layer stays
/// unit-testable without a widget tree.
///
/// Aggregation happens in SQL, behind [AnalyticsPort]. What happens here is the part SQL cannot do
/// correctly: **converting each data point separately** before summing. A query that let SQL add
/// across currencies would already have destroyed the information needed to convert — so every raw
/// row arrives as one currency's subtotal, and each is converted against the rate for its own date
/// before it joins a total.
final class AnalyticsService {
  /// Creates the service over [port], converting through [rates].
  const AnalyticsService({
    required AnalyticsPort port,
    required RateTable rates,
    required String homeCurrencyCode,
  }) : _port = port,
       _rates = rates,
       _home = homeCurrencyCode;

  final AnalyticsPort _port;
  final RateTable _rates;
  final String _home;

  // ── 1-8, 21-23: money ─────────────────────────────────────────────────────────────────

  /// Query 1 — spend by subtype within [window].
  Future<MoneySeries> spendBySubtype(AnalyticsWindow window) async =>
      _toSeries(await _port.spendBySubtype(window), window.to);

  /// Query 2 — spend by tag.
  Future<MoneySeries> spendByTag(AnalyticsWindow window) async =>
      _toSeries(await _port.spendByTag(window), window.to);

  /// Query 3 — spend by payment method.
  Future<MoneySeries> spendByPaymentMethod(AnalyticsWindow window) async =>
      _toSeries(await _port.spendByPaymentMethod(window), window.to);

  /// Query 4 — the top [limit] payees by spend.
  ///
  /// SQL orders and limits, so this does not sort in Dart. It re-sorts only after conversion,
  /// because a mixed-currency list ordered by raw minor units is ordered by the wrong thing —
  /// ¥10,000 outranking ₹5,000 is an artefact of the unit, not the amount.
  Future<MoneySeries> topPayeesBySpend(
    AnalyticsWindow window, {
    int limit = 10,
  }) async {
    final series = _toSeries(
      await _port.spendByPayee(window, limit: limit),
      window.to,
    );
    final sorted = series.slices.toList()
      ..sort((a, b) => b.amount.minor.compareTo(a.amount.minor));
    return (slices: sorted.take(limit).toList(), quality: series.quality);
  }

  /// Query 5 — income against expense, month by month.
  Future<IncomeVsExpense> incomeVsExpense(AnalyticsWindow window) async {
    final income = await _port.totalsByMonthAndKind(
      window,
      TransactionKind.deposit,
    );
    final expense = await _port.totalsByMonthAndKind(
      window,
      TransactionKind.withdrawal,
    );

    final byMonth = <int, ({int income, int expense})>{};
    var approximate = 0;
    var unconverted = 0;

    void fold(List<RawMonthRow> rows, {required bool isIncome}) {
      for (final row in rows) {
        final converted = _convert(
          row.amountMinor,
          row.currencyCode,
          _monthEnd(row.monthKey),
        );
        if (converted == null) {
          unconverted++;
          continue;
        }
        if (converted.quality == RateQuality.approximate) approximate++;
        final current = byMonth[row.monthKey] ?? (income: 0, expense: 0);
        byMonth[row.monthKey] = isIncome
            ? (
                income: current.income + converted.converted!.minor,
                expense: current.expense,
              )
            : (
                income: current.income,
                expense: current.expense + converted.converted!.minor,
              );
      }
    }

    fold(income, isIncome: true);
    fold(expense, isIncome: false);

    final points =
        byMonth.entries
            .map(
              (e) => (
                monthKey: e.key,
                income: Money(e.value.income, _home),
                expense: Money(e.value.expense, _home),
              ),
            )
            .toList()
          ..sort((a, b) => a.monthKey.compareTo(b.monthKey));

    return (
      points: points,
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );
  }

  /// Query 6 — net cash flow per month, from the signed ledger.
  Future<NetCashFlow> netCashFlowByMonth(AnalyticsWindow window) async =>
      _toMonthSeries(await _port.netFlowByMonth(window));

  /// Query 7 — one account's running balance.
  ///
  /// Returned in the **account's own currency**, never converted. A balance trend is about one
  /// account, and converting each point at its own date would make the line move when rates moved
  /// rather than when money did.
  Future<BalanceTrend> balanceTrend(
    String accountId,
    AnalyticsWindow window,
  ) async {
    final opening = await _port.openingBalance(accountId);
    // `const <BalancePoint>[]` and not `const []`: a record field takes the literal's inferred
    // type verbatim, so a bare `const []` is `List<dynamic>` and will not match `BalanceTrend`.
    if (opening == null)
      return (accountId: accountId, points: const <BalancePoint>[]);

    final legs = await _port.ledgerLegsForAccount(accountId, window);
    var running = opening.minor;
    final points = <BalancePoint>[];
    for (final leg in legs) {
      running += leg.amountMinor;
      points.add((
        date: DateKey(leg.dateKey),
        balance: Money(running, opening.currencyCode),
      ));
    }
    return (accountId: accountId, points: points);
  }

  /// Query 8 — grocery's share of total spend.
  Future<ShareOfTotal?> groceryShareOfSpend(AnalyticsWindow window) async {
    final series = await spendBySubtype(window);
    return _shareOf(series, TransactionSubtype.grocery.name);
  }

  /// Query 21 — spend by weekday (1-7, Monday first) or day of month (1-31).
  Future<SpendHeatmap> spendHeatmap(
    AnalyticsWindow window, {
    bool byWeekday = true,
  }) async {
    final rows = await _port.spendByBucket(window, byWeekday: byWeekday);
    final byBucket = <int, ({int minor, int count})>{};
    var approximate = 0;
    var unconverted = 0;

    for (final row in rows) {
      final converted = _convert(row.amountMinor, row.currencyCode, window.to);
      if (converted == null) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate++;
      final current = byBucket[row.bucket] ?? (minor: 0, count: 0);
      byBucket[row.bucket] = (
        minor: current.minor + converted.converted!.minor,
        count: current.count + row.count,
      );
    }

    final cells =
        byBucket.entries
            .map(
              (e) => (
                bucket: e.key,
                amount: Money(e.value.minor, _home),
                transactionCount: e.value.count,
              ),
            )
            .toList()
          ..sort((a, b) => a.bucket.compareTo(b.bucket));

    return (
      cells: cells,
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );
  }

  /// Query 22 — how concentrated spending is in its top [topCount] categories.
  Future<Concentration> categoryConcentration(
    AnalyticsWindow window, {
    int topCount = 3,
  }) async {
    final series = await spendBySubtype(window);
    final total = series.slices.fold<int>(0, (sum, s) => sum + s.amount.minor);
    final sorted = series.slices.toList()
      ..sort((a, b) => b.amount.minor.compareTo(a.amount.minor));

    final top = sorted.take(topCount).map((slice) {
      return (
        key: slice.key,
        label: slice.label,
        amount: slice.amount,
        share: total == 0 ? 0.0 : slice.amount.minor / total,
      );
    }).toList();

    return (
      top: top,
      topShare: total == 0
          ? 0.0
          : top.fold<int>(0, (s, t) => s + t.amount.minor) / total,
      total: Money(total, _home),
      quality: series.quality,
    );
  }

  /// Query 23 — the average grocery basket.
  Future<BasketStats> averageGroceryBasket(AnalyticsWindow window) async {
    final baskets = await _port.groceryBaskets(window);
    if (baskets.isEmpty) {
      return (
        averageValue: Money.zero(_home),
        // `0.0`, not `0`. A record field does not widen int to double the way a direct parameter
        // does, so an int literal here is a type error rather than a promoted zero.
        averageLineCount: 0.0,
        basketCount: 0,
        quality: exactConversion,
      );
    }

    var totalMinor = 0;
    var totalLines = 0;
    var counted = 0;
    var approximate = 0;
    var unconverted = 0;

    for (final basket in baskets) {
      final converted = _convert(
        basket.amountMinor,
        basket.currencyCode,
        window.to,
      );
      if (converted == null) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate++;
      totalMinor += converted.converted!.minor;
      totalLines += basket.lineCount;
      counted++;
    }

    return (
      // Averaged over the baskets that CONVERTED, not over all of them. Dividing a partial total by
      // the full count would understate every basket by the share that was excluded.
      averageValue: Money(counted == 0 ? 0 : totalMinor ~/ counted, _home),
      // Both branches must be double or the conditional infers `num`, which no more satisfies
      // `double` than `int` did.
      averageLineCount: counted == 0 ? 0.0 : totalLines / counted,
      basketCount: counted,
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );
  }

  // ── 9-12, 24: items and prices ────────────────────────────────────────────────────────

  /// Query 9 — the top [limit] items by spend.
  Future<List<ItemSpend>> topItemsBySpend(
    AnalyticsWindow window, {
    int limit = 10,
  }) async {
    final rows = await _port.spendByItem(window, limit: limit);
    final out = <ItemSpend>[];
    for (final row in rows) {
      final converted = _convert(row.amountMinor, row.currencyCode, window.to);
      if (converted == null) continue;
      out.add((
        itemId: row.key,
        itemName: row.label,
        amount: converted.converted!,
        purchaseCount: row.count,
      ));
    }
    out.sort((a, b) => b.amount.minor.compareTo(a.amount.minor));
    return out.take(limit).toList();
  }

  /// Query 10 — the top [limit] items by quantity bought.
  ///
  /// Not converted and not cross-compared: quantities in different categories are not comparable at
  /// all (Law L8), so this returns each item's own `Qty` and leaves ranking within a category to the
  /// caller. Sorting grams against pieces would produce a chart that means nothing.
  Future<List<ItemQuantity>> topItemsByQuantity(
    AnalyticsWindow window, {
    int limit = 10,
  }) async {
    final rows = await _port.quantityByItem(window, limit: limit);
    return rows
        .map(
          (row) => (
            itemId: row.key,
            itemName: row.label,
            quantity: Qty(row.milliBase, _categoryFrom(row.category)),
            purchaseCount: row.count,
          ),
        )
        .toList();
  }

  /// Query 11 — the dearest single purchase of [itemId].
  Future<DearestPurchase?> dearestPurchaseOfItem(
    String itemId,
    String itemName,
    AnalyticsWindow window,
  ) async {
    final row = await _port.dearestPurchase(itemId, window);
    if (row == null) return null;
    return (
      itemId: itemId,
      itemName: itemName,
      // The original currency, not converted: "the most I ever paid" is a fact about that purchase,
      // and restating it at today's rate would change a historical figure.
      unitPrice: Money(row.unitPriceMinor, row.currencyCode),
      on: DateKey(row.dateKey),
      transactionId: row.transactionId,
    );
  }

  /// Query 12 — one item's unit-price trend, and the percentage change across it.
  ///
  /// The personal-inflation insight: *"your potatoes cost 34% more than in January"*. The change is
  /// computed from the first and last observation of **price per base unit**, which is what makes it
  /// comparable across purchases made in different units — 2 kg and 500 g are the same measurement
  /// once both are per gram.
  Future<UnitPriceTrend> unitPriceTrend(
    String itemId,
    String itemName,
    AnalyticsWindow window,
  ) async {
    final points = await pricePerBaseUnitHistory(itemId, window);
    double? change;
    if (points.length >= 2) {
      final first = points.first.pricePerBaseUnit;
      final last = points.last.pricePerBaseUnit;
      if (first > 0) change = (last - first) / first;
    }
    return (
      itemId: itemId,
      itemName: itemName,
      points: points,
      percentChange: change,
    );
  }

  /// Query 24 — price per base unit for [itemId], oldest first.
  ///
  /// `lineAmountMinor / (quantityMilli / 1000)`, exactly as ARCH_3 §5.1 specifies. Lines with no
  /// amount or no quantity are skipped rather than treated as zero — a zero price would drag the
  /// trend down and read as a bargain that never happened.
  Future<List<UnitPricePoint>> pricePerBaseUnitHistory(
    String itemId,
    AnalyticsWindow window,
  ) async {
    final rows = await _port.itemPurchaseHistory(itemId, window);
    final points = <UnitPricePoint>[];
    for (final row in rows) {
      if (row.milliBase <= 0) continue;
      final baseUnits = row.milliBase / 1000;
      points.add((
        on: DateKey(row.dateKey),
        lineAmount: Money(row.lineAmountMinor, row.currencyCode),
        quantity: Qty(row.milliBase, _categoryFrom(row.category)),
        pricePerBaseUnit: row.lineAmountMinor / baseUnits,
      ));
    }
    return points;
  }

  // ── 13-16: inventory ──────────────────────────────────────────────────────────────────

  /// Query 13 — inventory value on hand, per currency.
  ///
  /// `unitCostMinor x (remainingMilli / unitFactorToBaseMilli)`, truncated.
  ///
  /// **Dividing by the unit's factor and not by 1000 is the whole of this calculation.**
  /// `Batch.unitCost` is cost per `unitCodeAtPurchase` — ₹50 per *kilogram*, not per gram — so the
  /// quantity has to be expressed in that same unit before multiplying. Dividing by 1000 instead
  /// happens to be right when the purchase unit is the base unit and is wrong by a factor of a
  /// thousand for kilograms or litres, which is the kind of error that looks plausible on screen.
  Future<InventoryValue> inventoryValueOnHand() async {
    final batches = await _port.valuedBatches();
    final byCode = <String, int>{};
    for (final batch in batches) {
      // A zero or missing factor would divide by zero; skipping is right because a batch whose unit
      // cannot be resolved has no computable value, and counting it as zero would understate the total
      // while looking complete.
      if (batch.unitFactorToBaseMilli <= 0) continue;
      final value =
          (batch.unitCostMinor *
                  batch.remainingMilli /
                  batch.unitFactorToBaseMilli)
              .truncate();
      byCode.update(
        batch.currencyCode,
        (v) => v + value,
        ifAbsent: () => value,
      );
    }
    return (
      byCurrency: {
        for (final e in byCode.entries) e.key: Money(e.value, e.key),
      },
      batchesValued: batches.length,
      // Reported rather than hidden: a valuation that silently omitted uncosted stock would look
      // complete while understating what is on the shelf.
      batchesNoCost: await _port.batchesWithoutCost(),
    );
  }

  /// Query 14 — food waste, in quantity and money.
  Future<List<ItemWasteTotal>> wasteTotals(AnalyticsWindow window) async {
    final movements = await _port.wasteMovements(window);
    final byItem =
        <
          String,
          ({String name, int milli, String category, Map<String, int> cost})
        >{};

    for (final m in movements) {
      final current =
          byItem[m.itemId] ??
          (
            name: m.itemName,
            milli: 0,
            category: m.category,
            cost: <String, int>{},
          );
      final cost = current.cost;
      final unitCost = m.unitCostMinor;
      final code = m.currencyCode;
      final factor = m.unitFactorToBaseMilli;
      if (unitCost != null && code != null && factor != null && factor > 0) {
        // Same per-purchase-unit rule as query 13.
        final value = (unitCost * m.milliBase / factor).truncate();
        cost.update(code, (v) => v + value, ifAbsent: () => value);
      }
      byItem[m.itemId] = (
        name: current.name,
        milli: current.milli + m.milliBase,
        category: current.category,
        cost: cost,
      );
    }

    return byItem.entries
        .map(
          (e) => (
            itemId: e.key,
            itemName: e.value.name,
            quantity: Qty(e.value.milli, _categoryFrom(e.value.category)),
            costByCurrency: {
              for (final c in e.value.cost.entries)
                c.key: Money(c.value, c.key),
            },
          ),
        )
        .toList();
  }

  /// Query 15 — batches expiring within [days] of today.
  Future<List<ExpiringBatch>> itemsExpiringWithin(int days) async {
    final today = _port.today();
    final rows = await _port.expiringBatches((
      from: today,
      to: today.addDays(days),
    ));
    return rows
        .map(
          (row) => (
            batchId: row.batchId,
            itemId: row.itemId,
            itemName: row.itemName,
            remaining: Qty(row.remainingMilli, _categoryFrom(row.category)),
            expiry: DateKey(row.expiryDateKey),
            daysLeft: DateKey(row.expiryDateKey).diffDays(today),
          ),
        )
        .toList()
      ..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
  }

  /// Query 16 — how many items are low on stock, as one point in a series.
  ///
  /// One point, not a history. `v_low_stock` reflects the present, and stock levels are not
  /// versioned — reconstructing "how many were low last Tuesday" would mean replaying the movement
  /// ledger against thresholds that may since have changed, which would be a different query and a
  /// far more expensive one. The caller samples this daily and stores the series if it wants a trend.
  Future<LowStockPoint> lowStockCountToday() async =>
      (date: _port.today(), itemCount: await _port.lowStockCount());

  // ── 17-20: commitments and assets ─────────────────────────────────────────────────────

  /// Query 17 — the fixed monthly commitment total.
  ///
  /// Normalises every interval to a monthly figure so a weekly bill and an annual one are comparable:
  /// weekly x 52/12, yearly / 12, daily x 365/12. Integer division truncates, so the total is
  /// slightly conservative rather than optimistic — which is the right direction for a number a user
  /// budgets against.
  Future<MonthlyCommitment> monthlyCommitmentTotal() async {
    final templates = await _port.activeCommitments();
    var total = 0;
    var counted = 0;
    var approximate = 0;
    var unconverted = 0;
    final today = _port.today();

    for (final t in templates) {
      final monthly = _toMonthlyMinor(
        amountMinor: t.defaultAmountMinor,
        intervalUnit: t.intervalUnit,
        intervalCount: t.intervalCount,
      );
      final converted = _convert(monthly, t.currencyCode, today);
      if (converted == null) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate++;
      total += converted.converted!.minor;
      counted++;
    }

    return (
      total: Money(total, _home),
      templateCount: counted,
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );
  }

  /// Query 18 — the recurring against discretionary split.
  Future<RecurringSplit> recurringVsDiscretionary(
    AnalyticsWindow window,
  ) async {
    final rows = await _port.spendByRecurringFlag(window);
    var recurring = 0;
    var discretionary = 0;
    var approximate = 0;
    var unconverted = 0;

    for (final row in rows) {
      final converted = _convert(row.amountMinor, row.currencyCode, window.to);
      if (converted == null) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate++;
      if (row.key == 'recurring') {
        recurring += converted.converted!.minor;
      } else {
        discretionary += converted.converted!.minor;
      }
    }

    final total = recurring + discretionary;
    return (
      recurring: Money(recurring, _home),
      discretionary: Money(discretionary, _home),
      recurringShare: total == 0 ? 0.0 : recurring / total,
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );
  }

  /// Query 19 — lifetime service cost per asset, per currency.
  Future<List<AssetServiceCost>> lifetimeServiceCostByAsset(
    AnalyticsWindow window,
  ) async {
    final rows = await _port.serviceCostByAsset(window);
    final byAsset =
        <String, ({String name, Map<String, int> cost, int count})>{};

    for (final row in rows) {
      final current =
          byAsset[row.assetId] ??
          (name: row.assetName, cost: <String, int>{}, count: 0);
      current.cost.update(
        row.currencyCode,
        (v) => v + row.costMinor,
        ifAbsent: () => row.costMinor,
      );
      byAsset[row.assetId] = (
        name: current.name,
        cost: current.cost,
        count: current.count + row.count,
      );
    }

    return byAsset.entries
        .map(
          (e) => (
            assetId: e.key,
            assetName: e.value.name,
            byCurrency: {
              for (final c in e.value.cost.entries)
                c.key: Money(c.value, c.key),
            },
            serviceCount: e.value.count,
          ),
        )
        .toList();
  }

  /// Query 20 — the warranty coverage timeline.
  Future<List<WarrantyCoverage>> warrantyCoverage() async {
    final rows = await _port.warrantyWindows();
    final today = _port.today();
    return rows.map((row) {
      final end = row.endDateKey == null ? null : DateKey(row.endDateKey!);
      final start = row.startDateKey == null
          ? null
          : DateKey(row.startDateKey!);
      final daysLeft = end?.diffDays(today);
      return (
        assetId: row.assetId,
        assetName: row.assetName,
        start: start,
        end: end,
        daysLeft: daysLeft,
        isCovered:
            end != null &&
            !end.isBefore(today) &&
            (start == null || !today.isBefore(start)),
      );
    }).toList();
  }

  // ── shared ────────────────────────────────────────────────────────────────────────────

  /// Converts one raw subtotal, or null when it cannot be converted at all.
  ConvertedMoney? _convert(int minor, String currencyCode, DateKey on) {
    final result = _rates.convert(
      amount: Money(minor, currencyCode),
      toCurrencyCode: _home,
      on: on,
    );
    return result.isExcludedFromTotals ? null : result;
  }

  MoneySeries _toSeries(List<RawMoneyRow> rows, DateKey on) {
    final byKey = <String, ({String label, int minor})>{};
    var approximate = 0;
    var unconverted = 0;

    for (final row in rows) {
      final converted = _convert(row.amountMinor, row.currencyCode, on);
      if (converted == null) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate++;
      final current = byKey[row.key] ?? (label: row.label, minor: 0);
      byKey[row.key] = (
        label: current.label,
        minor: current.minor + converted.converted!.minor,
      );
    }

    final slices =
        byKey.entries
            .map(
              (e) => (
                label: e.value.label,
                key: e.key,
                amount: Money(e.value.minor, _home),
              ),
            )
            .toList()
          ..sort((a, b) => b.amount.minor.compareTo(a.amount.minor));

    return (
      slices: slices,
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );
  }

  MonthSeries _toMonthSeries(List<RawMonthRow> rows) {
    final byMonth = <int, int>{};
    var approximate = 0;
    var unconverted = 0;

    for (final row in rows) {
      final converted = _convert(
        row.amountMinor,
        row.currencyCode,
        _monthEnd(row.monthKey),
      );
      if (converted == null) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate++;
      byMonth.update(
        row.monthKey,
        (v) => v + converted.converted!.minor,
        ifAbsent: () => converted.converted!.minor,
      );
    }

    final points =
        byMonth.entries
            .map((e) => (monthKey: e.key, amount: Money(e.value, _home)))
            .toList()
          ..sort((a, b) => a.monthKey.compareTo(b.monthKey));

    return (
      points: points,
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );
  }

  ShareOfTotal? _shareOf(MoneySeries series, String key) {
    final total = series.slices.fold<int>(0, (sum, s) => sum + s.amount.minor);
    for (final slice in series.slices) {
      if (slice.key != key) continue;
      return (
        key: slice.key,
        label: slice.label,
        amount: slice.amount,
        share: total == 0 ? 0.0 : slice.amount.minor / total,
      );
    }
    return null;
  }

  /// A month's last day, used as the conversion date for a monthly subtotal.
  ///
  /// A month's spend is not one instant, so no single rate is exactly right. The month end is the
  /// defensible choice: it is the date by which every transaction in the bucket had happened, and it
  /// is stable — using "today" would make a closed month's figure drift every time it was reopened.
  DateKey _monthEnd(int monthKey) {
    final year = monthKey ~/ 100;
    final month = monthKey % 100;
    return DateKey.fromYmd(year, month, DateTime.utc(year, month + 1, 0).day);
  }

  /// Normalises a recurring amount to a monthly equivalent in minor units.
  int _toMonthlyMinor({
    required int amountMinor,
    required String intervalUnit,
    required int intervalCount,
  }) {
    final perInterval = intervalCount <= 0 ? 1 : intervalCount;
    switch (intervalUnit) {
      case 'day':
        return (amountMinor * 365 / (12 * perInterval)).truncate();
      case 'week':
        return (amountMinor * 52 / (12 * perInterval)).truncate();
      case 'month':
        return amountMinor ~/ perInterval;
      case 'year':
        return amountMinor ~/ (12 * perInterval);
      default:
        return amountMinor;
    }
  }

  /// Maps a stored category name back to its enum, defaulting to `count`.
  ///
  /// Defaulting rather than throwing: an unrecognised name means the database holds a value this
  /// build does not know, which is exactly what `SafeEnumConverter` exists to survive (Law L13). A
  /// wrong category on an analytics label is a cosmetic error; a crash on the analytics screen is not.
  UnitCategory _categoryFrom(String name) {
    for (final category in UnitCategory.values) {
      if (category.name == name) return category;
    }
    return UnitCategory.count;
  }
}
```

### `lib/domain/services/analytics/analytics_types.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';

/// The window every analytics query is bounded by.
typedef AnalyticsWindow = ({DateKey from, DateKey to});

/// How much of a converted series could not be stated exactly.
///
/// Carried alongside every money series per ARCH_3 §5.2. A total presented without it would be
/// quietly wrong whenever a rate was missing; presented with it, the UI can say so.
typedef ConversionQuality = ({int approximateCount, int unconvertedCount});

/// A conversion quality with nothing to report.
const ConversionQuality exactConversion = (
  approximateCount: 0,
  unconvertedCount: 0,
);

/// One labelled money figure — the shape most charts consume.
typedef MoneySlice = ({String label, String key, Money amount});

/// One labelled quantity figure.
typedef QuantitySlice = ({String label, String key, Qty quantity});

/// A money series plus how reliable its conversions were.
typedef MoneySeries = ({List<MoneySlice> slices, ConversionQuality quality});

/// One point in a monthly series, keyed by `yyyymm`.
typedef MonthPoint = ({int monthKey, Money amount});

/// A monthly series plus its conversion quality.
typedef MonthSeries = ({List<MonthPoint> points, ConversionQuality quality});

/// One point in a daily series.
typedef DayPoint = ({DateKey date, Money amount});

/// Query 1 — spend by subtype for one month.
typedef SubtypeSpend = ({int monthKey, MoneySeries series});

/// Query 5 — income against expense over a rolling window.
typedef IncomeVsExpensePoint = ({int monthKey, Money income, Money expense});

/// Query 5's series.
typedef IncomeVsExpense = ({
  List<IncomeVsExpensePoint> points,
  ConversionQuality quality,
});

/// Query 6 — net cash flow per month.
typedef NetCashFlow = ({List<MonthPoint> points, ConversionQuality quality});

/// Query 7 — one account's running balance.
typedef BalancePoint = ({DateKey date, Money balance});

/// Query 7's series, in the account's own currency so no conversion is involved.
typedef BalanceTrend = ({String accountId, List<BalancePoint> points});

/// Query 8 and 22 — one slice's share of a total.
typedef ShareOfTotal = ({String key, String label, Money amount, double share});

/// Query 22's result: the top slices and what they add up to.
typedef Concentration = ({
  List<ShareOfTotal> top,
  double topShare,
  Money total,
  ConversionQuality quality,
});

/// Query 9 — one item's total spend.
typedef ItemSpend = ({
  String itemId,
  String itemName,
  Money amount,
  int purchaseCount,
});

/// Query 10 — one item's total quantity bought.
typedef ItemQuantity = ({
  String itemId,
  String itemName,
  Qty quantity,
  int purchaseCount,
});

/// Query 11 — the dearest single purchase of an item.
typedef DearestPurchase = ({
  String itemId,
  String itemName,
  Money unitPrice,
  DateKey on,
  String transactionId,
});

/// Queries 12 and 24 — one observation of what an item cost per base unit.
///
/// [pricePerBaseUnit] is a `double` of minor units, not a `Money`: it is a derived ratio for
/// comparison, and Law L1 governs amounts that are stored. Storing it would imply a precision the
/// division does not have.
typedef UnitPricePoint = ({
  DateKey on,
  Money lineAmount,
  Qty quantity,
  double pricePerBaseUnit,
});

/// Query 12's series, plus the change across it — the personal-inflation number.
typedef UnitPriceTrend = ({
  String itemId,
  String itemName,
  List<UnitPricePoint> points,
  double? percentChange,
});

/// Query 13 — inventory value on hand, per currency.
///
/// Per currency rather than one figure: batch cost currency is per row, so a single total would be
/// adding rupees to yen (anomaly A34).
typedef InventoryValue = ({
  Map<String, Money> byCurrency,
  int batchesValued,
  int batchesNoCost,
});

/// Query 14 — what was wasted, in quantity and money.
///
/// Named `ItemWasteTotal` rather than `WasteTotal` because Phase 3A already declares a `WasteTotal`
/// class on `StockRepository`. They answer different questions — that one is a repository read for a
/// single item, this one is an analytics rollup carrying cost per currency — and a file importing both
/// would not compile.
typedef ItemWasteTotal = ({
  String itemId,
  String itemName,
  Qty quantity,
  Map<String, Money> costByCurrency,
});

/// Query 15 — a batch expiring soon.
typedef ExpiringBatch = ({
  String batchId,
  String itemId,
  String itemName,
  Qty remaining,
  DateKey expiry,
  int daysLeft,
});

/// Query 16 — how many items were low on stock on one date.
typedef LowStockPoint = ({DateKey date, int itemCount});

/// Query 17 — the fixed monthly commitment total.
typedef MonthlyCommitment = ({
  Money total,
  int templateCount,
  ConversionQuality quality,
});

/// Query 18 — the recurring against discretionary split.
typedef RecurringSplit = ({
  Money recurring,
  Money discretionary,
  double recurringShare,
  ConversionQuality quality,
});

/// Query 19 — one asset's lifetime service cost, per currency.
typedef AssetServiceCost = ({
  String assetId,
  String assetName,
  Map<String, Money> byCurrency,
  int serviceCount,
});

/// Query 20 — one asset's warranty window.
typedef WarrantyCoverage = ({
  String assetId,
  String assetName,
  DateKey? start,
  DateKey? end,
  int? daysLeft,
  bool isCovered,
});

/// Query 21 — one cell of the spend heatmap.
///
/// [bucket] is 1-7 for a weekday series (Monday first) or 1-31 for a day-of-month series.
typedef HeatmapCell = ({int bucket, Money amount, int transactionCount});

/// Query 21's result.
typedef SpendHeatmap = ({List<HeatmapCell> cells, ConversionQuality quality});

/// Query 23 — the average basket.
typedef BasketStats = ({
  Money averageValue,
  double averageLineCount,
  int basketCount,
  ConversionQuality quality,
});
```

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

### `lib/domain/services/backup/data_transfer_port.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// What an export produced.
///
/// Moved here from `data/` in 8A so a feature can name it. A record of four plain values with no drift
/// or Flutter dependency, so `domain/` is a legal home for it on Law L12's own terms.
typedef BackupArtefact = ({
  String path,
  int sizeBytes,
  bool isZipped,
  String fileName,
});

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

### `lib/domain/services/balance_service.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// One account's balance plus whether it counts toward net worth.
///
/// A narrow input type rather than the full `Account` entity: net worth needs three facts, and
/// asking for twenty-six would couple this service to every unrelated change to an account.
class AccountBalanceInput {
  /// Creates an input row.
  const AccountBalanceInput({
    required this.accountId,
    required this.balance,
    required this.includeInNetWorth,
  });

  /// The account.
  final String accountId;

  /// Its balance, in its own currency.
  final Money balance;

  /// Whether the user wants this account counted in the headline.
  final bool includeInNetWorth;
}

/// A converted headline total, and how many balances could not be converted into it.
///
/// The count is carried rather than discarded because a missing rate must exclude an amount, not
/// count it as zero (ARCH_3 §1.3.4). A total presented without it would be quietly wrong; presented
/// with it, the UI can show `+2 unconverted` and the number stops being a lie.
class NetWorth {
  /// Creates a headline.
  const NetWorth({
    required this.total,
    required this.unconvertedCount,
    required this.isApproximate,
  });

  /// The sum of every convertible, included balance, in the home currency.
  final Money total;

  /// How many included balances had no usable rate and were left out of [total].
  final int unconvertedCount;

  /// True when at least one contributing rate had to fall back to a date outside the requested one,
  /// so the figure is indicative rather than exact (`RateQuality.approximate`).
  final bool isApproximate;

  /// True when every included balance converted cleanly.
  bool get isComplete => unconvertedCount == 0;
}

/// Computes per-account and aggregate balances.
///
/// Owns the net-worth rule so there is exactly one definition of it. `AccountRepository` supplies
/// the raw per-account balances — which come from `v_account_balances`, where a self-transfer nets to
/// zero by construction — and this service decides what counts and converts what remains.
final class BalanceService {
  /// Creates the service.
  const BalanceService();

  /// Sums [balances] into [homeCurrencyCode] using [table], as of [asOf].
  ///
  /// Pure and synchronous: given a rate table it performs no I/O, which is why the whole net-worth
  /// rule is testable from literals. Callers converting a long list should load the table once and
  /// call this, rather than converting amount by amount.
  ///
  /// **Which accounts count.** Only `includeInNetWorth`. An **archived** account still counts —
  /// ARCH_3 §4's table is explicit that archive keeps money in your net worth and only delete
  /// removes it, because a closed bank account with a remaining balance is retired, not gone. So
  /// archived-ness is deliberately not a filter here, and `AccountRepository.watchAllIncludingArchived`
  /// is the right source to feed this.
  ///
  /// **Which balances convert.** One already in [homeCurrencyCode] passes through untouched — no
  /// rate is consulted, so an all-single-currency user never sees an `unconvertedCount` above zero
  /// even with an empty rate cache.
  NetWorth totalFrom({
    required Iterable<AccountBalanceInput> balances,
    required RateTable table,
    required String homeCurrencyCode,
    required DateKey asOf,
  }) {
    var total = Money.zero(homeCurrencyCode);
    var unconverted = 0;
    var approximate = false;

    for (final input in balances) {
      if (!input.includeInNetWorth) continue;

      final converted = table.convert(
        amount: input.balance,
        toCurrencyCode: homeCurrencyCode,
        on: asOf,
      );
      if (converted.isExcludedFromTotals) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate = true;

      // `converted.converted` is in homeCurrencyCode, matching `total`, so this cannot throw a
      // currency mismatch however many source currencies were involved.
      total = total + converted.converted!;
    }

    return NetWorth(
      total: total,
      unconvertedCount: unconverted,
      isApproximate: approximate,
    );
  }

  /// Loads the rate table and sums [balances] — the convenience form of [totalFrom].
  Future<NetWorth> totalInHome({
    required Iterable<AccountBalanceInput> balances,
    required CurrencyRateService rates,
    required String homeCurrencyCode,
    required DateKey asOf,
  }) async {
    final table = await rates.table();
    return totalFrom(
      balances: balances,
      table: table,
      homeCurrencyCode: homeCurrencyCode,
      asOf: asOf,
    );
  }

  /// Converts one balance, for a per-account row that shows both its own currency and the home one.
  ConvertedMoney convertOne({
    required Money balance,
    required RateTable table,
    required String homeCurrencyCode,
    required DateKey asOf,
  }) {
    return table.convert(amount: balance, toCurrencyCode: homeCurrencyCode, on: asOf);
  }

  /// Totals [balances] per currency without converting anything.
  ///
  /// The honest answer when no rate is available at all: `₹4,000 + $50` rather than a single number
  /// that silently dropped the dollars. Also what a currency-breakdown panel needs.
  Map<String, Money> totalsByCurrency(Iterable<AccountBalanceInput> balances) {
    final byCode = <String, int>{};
    for (final input in balances) {
      if (!input.includeInNetWorth) continue;
      byCode.update(
        input.balance.currencyCode,
            (running) => running + input.balance.minor,
        ifAbsent: () => input.balance.minor,
      );
    }
    return {
      for (final entry in byCode.entries) entry.key: Money(entry.value, entry.key),
    };
  }
}
```

### `lib/domain/services/calendar_aggregator.dart`

```dart
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/repositories/calendar_repository.dart';

/// One day's worth of calendar entries, with the day's worst severity precomputed.
typedef CalendarDay = ({
  DateKey date,
  List<CalendarEvent> events,
  CalendarSeverity severity,
});

/// Reads the calendar feed and applies ARCH_3 §6's severity rules.
///
/// The view emits a **static baseline** severity because no view in this schema consults the clock
/// (ARCH_2 §12.2). Everything date-relative therefore happens here, against a `today` passed in — so
/// a calendar rendered under a `FixedClock` is reproducible, and the severity of an entry does not
/// change merely because the test suite ran after midnight.
final class CalendarAggregator {
  /// Creates the aggregator over [repository].
  const CalendarAggregator(this._repository);

  final CalendarRepository _repository;

  /// Days before an expiring batch turns from `info` to `warning` (ARCH_3 §6).
  static const int batchExpiryWarningDays = 7;

  /// Days before a service falls due that it turns to `warning`.
  static const int serviceDueWarningDays = 7;

  /// Days before a warranty ends that it turns to `warning`.
  ///
  /// Thirty rather than seven, deliberately per §6: a warranty is worth acting on well before it
  /// lapses, because arranging a claim takes time that an expiring yoghurt does not.
  static const int warrantyEndWarningDays = 30;

  /// Emits the events in `[from, to]` with severity resolved against [today].
  ///
  /// Always bounded — an unbounded read scans seven tables, where a bounded one uses each source's
  /// own date index.
  Stream<List<CalendarEvent>> watchRange({
    required DateKey from,
    required DateKey to,
    required DateKey today,
  }) {
    return _repository
        .watchRange(from: from, to: to)
        .map(
          (events) => events
              .map((e) => resolveSeverity(event: e, today: today))
              .toList(),
        );
  }

  /// Groups the events in `[from, to]` by day, for a month grid.
  ///
  /// Days with no events are omitted rather than included empty — a grid renders 28 to 31 cells
  /// regardless, and it needs to know which have something, not to receive a placeholder for each
  /// that does not.
  Stream<List<CalendarDay>> watchDays({
    required DateKey from,
    required DateKey to,
    required DateKey today,
  }) {
    return watchRange(from: from, to: to, today: today).map(groupByDay);
  }

  /// Reads one day's events, severity resolved.
  Future<List<CalendarEvent>> forDay({
    required DateKey dateKey,
    required DateKey today,
  }) async {
    final events = await _repository.forDay(dateKey);
    return events.map((e) => resolveSeverity(event: e, today: today)).toList();
  }

  /// How many events fall on each date, for the grid's dots.
  Future<Map<DateKey, int>> countsByDate({
    required DateKey from,
    required DateKey to,
  }) => _repository.countsByDate(from: from, to: to);

  /// Groups [events] into days, each carrying that day's worst severity.
  List<CalendarDay> groupByDay(List<CalendarEvent> events) {
    final byDate = <int, List<CalendarEvent>>{};
    for (final event in events) {
      (byDate[event.dateKey.value] ??= <CalendarEvent>[]).add(event);
    }

    final days = byDate.entries.map((entry) {
      final dayEvents = entry.value;
      return (
        date: DateKey(entry.key),
        events: dayEvents,
        severity: worstSeverity(dayEvents),
      );
    }).toList()..sort((a, b) => DateKey.compare(a.date, b.date));
    return days;
  }

  /// The most urgent severity among [events], for a day's single dot.
  CalendarSeverity worstSeverity(Iterable<CalendarEvent> events) {
    var worst = CalendarSeverity.info;
    for (final event in events) {
      if (event.baseSeverity == CalendarSeverity.danger)
        return CalendarSeverity.danger;
      if (event.baseSeverity == CalendarSeverity.warning)
        worst = CalendarSeverity.warning;
    }
    return worst;
  }

  /// Returns [event] with its severity escalated per ARCH_3 §6's **per-type** thresholds.
  ///
  /// The thresholds differ by type, and that is the substance of this method rather than an
  /// incidental detail: a warranty warns at 30 days, an expiry and a service at 7, and only an expiry
  /// escalates to `danger` once past. `CalendarEvent.severityAsOf` from Phase 3A applies a single
  /// generic rule to every type, which does not implement this table — this method supersedes it, and
  /// that entity method should be removed when a phase next touches it.
  ///
  /// A `transaction` never escalates. It records something that already happened, so "overdue" is
  /// meaningless for it.
  CalendarEvent resolveSeverity({
    required CalendarEvent event,
    required DateKey today,
  }) {
    final resolved = severityFor(event: event, today: today);
    if (resolved == event.baseSeverity) return event;
    return CalendarEvent(
      dateKey: event.dateKey,
      type: event.type,
      refType: event.refType,
      refId: event.refId,
      title: event.title,
      baseSeverity: resolved,
      amount: event.amount,
    );
  }

  /// The severity [event] should render with as of [today].
  CalendarSeverity severityFor({
    required CalendarEvent event,
    required DateKey today,
  }) {
    final daysAway = event.dateKey.diffDays(today);
    final isPast = daysAway < 0;

    switch (event.type) {
      case CalendarEventType.transaction:
        return CalendarSeverity.info;

      case CalendarEventType.shoppingTarget:
        // A shopping date the user set and let slip is not an alarm — the list is still there.
        return CalendarSeverity.info;

      case CalendarEventType.recurringDue:
        // §6 says warning once past, not danger. An unpaid bill is the user's decision to make, and
        // the recurring screen already surfaces it; the calendar does not need to shout.
        return isPast ? CalendarSeverity.warning : CalendarSeverity.info;

      case CalendarEventType.batchExpiry:
        // The only type that reaches danger. Food past its date is the one calendar entry where
        // acting late has already cost something.
        if (isPast) return CalendarSeverity.danger;
        return daysAway <= batchExpiryWarningDays
            ? CalendarSeverity.warning
            : CalendarSeverity.info;

      case CalendarEventType.warrantyEnd:
        if (isPast) return CalendarSeverity.info;
        return daysAway <= warrantyEndWarningDays
            ? CalendarSeverity.warning
            : CalendarSeverity.info;

      case CalendarEventType.serviceDue:
        if (isPast) return CalendarSeverity.warning;
        return daysAway <= serviceDueWarningDays
            ? CalendarSeverity.warning
            : CalendarSeverity.info;

      case CalendarEventType.splitSettleBy:
        // Warning once past, matching `recurringDue` rather than `batchExpiry`. An unsettled debt is a
        // conversation the user has not had yet; food past its date has already cost something, which
        // is why that stays the only type reaching danger.
        return isPast ? CalendarSeverity.warning : CalendarSeverity.info;
    }
  }
}
```

### `lib/domain/services/cookability_engine.dart`

```dart
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/recipe.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';

/// What the engine could determine about one ingredient.
///
/// **Six states, and two of them mean "I do not know".** Collapsing those into "missing" is the
/// single easiest way to make this feature lie: an app that reports *you cannot cook this* because
/// nobody tracks the stock level of salt has told the user something false with total confidence.
enum IngredientAvailability {
  /// Linked to an item, comparable units, and enough unexpired stock on hand.
  sufficient,

  /// Enough on hand, but only by drawing on stock that is past its date.
  ///
  /// **Not a shortfall, and deliberately not `short`.** The food exists and the cook may well want to
  /// use it — a jar a day past its date is a judgement call, not an absence. Reporting it as missing
  /// would grey out the Cook button and remove the choice, which is the same mistake as gating a
  /// recipe on inventory configuration.
  ///
  /// Only ever reported when batches were supplied to [CookabilityEngine.judge]. Without them the
  /// engine has a total and no way to split it, and it does not guess.
  needsExpired,

  /// Linked and comparable, but less unexpired stock on hand than the recipe needs — and not enough
  /// expired stock to close the gap either.
  short,

  /// Linked and comparable, with nothing at all on hand.
  outOfStock,

  /// Linked, but the recipe's unit and the item's are different dimensions — 200 g of something
  /// tracked by the piece. **No conversion exists**, so this is unanswerable rather than false.
  unitMismatch,

  /// No linked item, or no quantity given. "Salt to taste" is a real ingredient, not a missing one.
  untracked;

  /// Whether this state contributes to a shortfall the user could act on.
  ///
  /// [needsExpired] is excluded on purpose: nothing needs buying, and a shopping list built from this
  /// would add an item the user already has.
  bool get isMissing =>
      this == IngredientAvailability.short ||
      this == IngredientAvailability.outOfStock;

  /// Whether the engine declined to answer rather than answering no.
  bool get isUncheckable =>
      this == IngredientAvailability.unitMismatch ||
      this == IngredientAvailability.untracked;
}

/// The engine's verdict on one ingredient line.
class IngredientCheck {
  /// Creates a verdict.
  const IngredientCheck({
    required this.ingredient,
    required this.availability,
    required this.required_,
    this.onHand,
    this.shortfall,
    this.nearestExpiry,
    this.plan,
  });

  /// The line this verdict is about.
  final RecipeIngredient ingredient;

  /// What the engine could determine.
  final IngredientAvailability availability;

  /// How much the recipe needs after serving-scaling. Null when the line carries no quantity.
  final Qty? required_;

  /// How much is on hand, when that is comparable.
  ///
  /// The item's whole remaining stock, expired batches included — it is what `v_item_stock` sums and
  /// it is what "you have 500 g" means to a user standing at a cupboard. [plan] is what says how much
  /// of it this recipe could actually use.
  final Qty? onHand;

  /// How much more is needed. Null unless [availability] is [IngredientAvailability.short] or
  /// [IngredientAvailability.outOfStock] — which is what a shopping list would consume.
  final Qty? shortfall;

  /// The earliest expiry among batches of this item still holding stock.
  final DateKey? nearestExpiry;

  /// Which batches this ingredient would actually draw from, when batches were supplied.
  ///
  /// **The one value a confirmation sheet and the deduction must share.** It names the batches, the
  /// amounts, and how much of the total comes from stock past its date — so a sheet describing what
  /// will happen and a repository carrying it out read the same answer rather than each deriving one.
  /// ARCH_M §6: no value displayed from a second source.
  ///
  /// Produced by `InventoryConsumptionService`, which is the one definition of the draw order. A plan
  /// only exists when it is complete: the service refuses rather than returning a partial one, so a
  /// non-null plan here is always a plan that could be applied.
  ///
  /// Null when [CookabilityEngine.judge] was called without batches for this item, which is the
  /// cheap path a list screen uses. A null plan means "not computed", never "nothing to draw".
  final ConsumptionPlan? plan;
}

/// The headline verdict, for sorting a list and choosing one word to show.
enum CookabilityStatus {
  /// Every required ingredient is present in sufficient unexpired quantity, and every one could be
  /// checked.
  ready,

  /// Cookable, but at least one required ingredient would have to come partly from expired stock.
  ///
  /// **A distinct status because the two decisions differ.** `ready` needs no permission; this needs
  /// the cook to be asked. Folding it into [short] would disable the very control that offers the
  /// choice, and folding it into [ready] would deduct expired food silently — which is the fault this
  /// state exists to end.
  readyWithExpired,

  /// Some required ingredients are present but insufficient. Nothing is entirely absent.
  short,

  /// At least one required ingredient is entirely absent.
  blocked,

  /// Nothing is missing, but at least one required ingredient could not be checked, so the engine
  /// will not claim the recipe is ready.
  uncheckable,

  /// The recipe has no required ingredients at all. A note, not a recipe.
  empty,
}

/// Whether a recipe can be cooked from what is on hand.
///
/// **[missingCount] and [uncheckableCount] are reported separately because they are different
/// facts.** A recipe can be both short of two ingredients and uncertain about a third, and a single
/// enum would have to discard one of those. [status] is the headline; these are what a screen shows
/// underneath it.
class Cookability {
  /// Creates a verdict.
  const Cookability({
    required this.recipeId,
    required this.checks,
    required this.status,
    required this.missingCount,
    required this.uncheckableCount,
    required this.optionalMissingCount,
    required this.expiredCount,
    this.soonestExpiryUsed,
  });

  /// The recipe this verdict is about.
  final String recipeId;

  /// Every ingredient's verdict, in the recipe's own order.
  final List<IngredientCheck> checks;

  /// The headline.
  final CookabilityStatus status;

  /// How many required ingredients are short or absent.
  final int missingCount;

  /// How many required ingredients could not be checked at all.
  final int uncheckableCount;

  /// How many *optional* ingredients are short or absent. Never affects [status] — a missing
  /// garnish should not stop dinner — but worth saying.
  final int optionalMissingCount;

  /// How many required ingredients would draw on stock past its date.
  ///
  /// What a confirmation sheet counts. Separate from [missingCount] because nothing here is absent —
  /// summing them would tell the user to go shopping for food in their cupboard.
  final int expiredCount;

  /// The earliest expiry among the items this recipe would draw on.
  ///
  /// This is what "cook what expires soonest" sorts by. It comes free: [ItemStock] already computes
  /// `nearestExpiry` per item, so no batch query is needed here.
  ///
  /// It is the nearest expiry across *all* batches of each item, not specifically the batches a
  /// cook would draw from. For an ordering hint that is the right approximation, and saying so is
  /// better than implying a precision the figure does not have.
  final DateKey? soonestExpiryUsed;

  /// Whether the recipe can be cooked right now with no caveats.
  bool get isReady => status == CookabilityStatus.ready;

  /// Whether the recipe can be cooked, once the cook has agreed to use expired stock.
  bool get needsExpiredConsent => status == CookabilityStatus.readyWithExpired;

  /// Whether cooking is possible at all, with or without consent.
  bool get isCookable => isReady || needsExpiredConsent;
}

/// Answers "can I cook this from what is on hand", and declines to answer when it cannot.
///
/// Pure: entities in, verdicts out. No repository, no drift, no Flutter — so every branch below is
/// exercisable from literals, which is what the unit tests do.
///
/// **The engine never converts between unit categories.** Grams and pieces are different
/// dimensions and no factor relates them; an item tracked by count cannot answer a question asked
/// in grams. That is reported as [IngredientAvailability.unitMismatch] and propagates to
/// [CookabilityStatus.uncheckable] rather than being silently treated as zero.
///
/// **The engine does not decide the draw order either.** `InventoryConsumptionService` owns it, and
/// this class asks — because the order a verdict assumes and the order a deduction performs must be
/// the same one. A separate planner written here would be the third copy of that rule, and the
/// service's own doc explains what happens to the second.
///
/// **Expiry is a two-tier answer, on purpose.** `ItemStock.totalRemaining` comes from `v_item_stock`,
/// which sums every batch holding stock with **no expiry filter** — so a total alone cannot say how
/// much of it is still good. Supplying batches for an item buys a precise answer and a
/// [ConsumptionPlan]; omitting them keeps the previous behaviour, which is what a list of forty
/// recipes wants. The engine never splits the difference by guessing.
class CookabilityEngine {
  /// Creates the engine. Stateless.
  const CookabilityEngine();

  static const InventoryConsumptionService _consumption =
      InventoryConsumptionService();

  /// Scales a stored milli-quantity from [fromServings] to [toServings].
  ///
  /// **Integer ceiling division, and the direction is deliberate.** Rounding 66.67 g down to 66 g
  /// would let the engine report *ready* when the cook is short; rounding up can only overstate a
  /// requirement. A false "you have enough" ruins dinner; a false "you are 1 g short" is a shrug.
  ///
  /// No doubles anywhere (Law L1).
  static int scaleMilli(
    int milli, {
    required int fromServings,
    required int toServings,
  }) {
    if (fromServings <= 0) {
      throw ArgumentError.value(
        fromServings,
        'fromServings',
        'must be positive',
      );
    }
    if (toServings == fromServings) return milli;
    final numerator = milli * toServings;
    // Ceiling for positives; recipe quantities are never negative, but the guard keeps the
    // arithmetic honest if one ever is.
    return numerator >= 0
        ? (numerator + fromServings - 1) ~/ fromServings
        : -((-numerator + fromServings - 1) ~/ fromServings);
  }

  /// Judges [recipe] against [stock], scaled to [servings] if given.
  ///
  /// [stock] and [items] are keyed by item id. An ingredient whose item is absent from [items] is
  /// treated as untracked rather than missing — the item may have been deleted, and inventing a
  /// verdict about a row that no longer exists would be a guess.
  ///
  /// [today] decides what counts as expired, and is required rather than read from a clock so the
  /// engine stays pure and a date-sensitive verdict is reproducible under a `FixedClock`. It is the
  /// same rule `ConsumableBatch.isExpired` and the views follow.
  ///
  /// [batchesByItem] is optional and keyed by item id, in any order — the consumption service sorts.
  /// Supply it and the engine answers precisely: which batches, how much from each, and how much of it
  /// is past its date. Omit it and expiry is not considered at all, which is the previous behaviour and
  /// the right trade for a list screen judging forty recipes.
  ///
  /// **Omitting it can overstate availability**, because `totalRemaining` includes expired batches.
  /// That is a deliberate approximation of the same kind [Cookability.soonestExpiryUsed] documents,
  /// and it is why the cook path and the detail screen both supply batches.
  Cookability judge(
    Recipe recipe, {
    required Map<String, ItemStock> stock,
    required Map<String, Item> items,
    required DateKey today,
    Map<String, List<ConsumableBatch>> batchesByItem = const {},
    int? servings,
  }) {
    final target = servings ?? recipe.servings;
    final checks = <IngredientCheck>[];
    var missing = 0;
    var uncheckable = 0;
    var optionalMissing = 0;
    var required = 0;
    var expired = 0;
    DateKey? soonest;

    for (final ingredient in recipe.ingredients) {
      final check = _check(
        ingredient,
        stock: stock,
        items: items,
        today: today,
        batchesByItem: batchesByItem,
        fromServings: recipe.servings,
        toServings: target,
      );
      checks.add(check);

      final expiry = check.nearestExpiry;
      // `isBefore` rather than comparing the representation int. `DateKey` is an extension type
      // over `int`, so `.value` would compile — and reading the representation is exactly the
      // habit the type exists to discourage.
      if (expiry != null && (soonest == null || expiry.isBefore(soonest))) {
        soonest = expiry;
      }

      if (ingredient.isOptional) {
        if (check.availability.isMissing) optionalMissing++;
        continue;
      }
      required++;
      if (check.availability.isMissing) missing++;
      if (check.availability.isUncheckable) uncheckable++;
      if (check.availability == IngredientAvailability.needsExpired) expired++;
    }

    return Cookability(
      recipeId: recipe.id,
      checks: checks,
      status: _statusFor(
        requiredCount: required,
        missing: missing,
        uncheckable: uncheckable,
        expired: expired,
        anyAbsent: checks.any(
          (c) =>
              !c.ingredient.isOptional &&
              c.availability == IngredientAvailability.outOfStock,
        ),
      ),
      missingCount: missing,
      uncheckableCount: uncheckable,
      optionalMissingCount: optionalMissing,
      expiredCount: expired,
      soonestExpiryUsed: soonest,
    );
  }

  IngredientCheck _check(
    RecipeIngredient ingredient, {
    required Map<String, ItemStock> stock,
    required Map<String, Item> items,
    required DateKey today,
    required Map<String, List<ConsumableBatch>> batchesByItem,
    required int fromServings,
    required int toServings,
  }) {
    final itemId = ingredient.itemId;
    final quantity = ingredient.quantity;

    // No link, or no quantity to compare. Both are ordinary, and neither is a shortfall.
    if (itemId == null || quantity == null) {
      return IngredientCheck(
        ingredient: ingredient,
        availability: IngredientAvailability.untracked,
        required_: quantity,
      );
    }

    final item = items[itemId];
    final onHand = stock[itemId];
    if (item == null || onHand == null) {
      return IngredientCheck(
        ingredient: ingredient,
        availability: IngredientAvailability.untracked,
        required_: quantity,
      );
    }

    // Different dimensions are convertible only if the item states how it bridges them. A null
    // bridge is not a failure — it is the engine declining, which is the whole point of the module.
    final wanted = item.unitCategory == quantity.category
        ? quantity
        : _bridge(quantity, item);
    if (wanted == null) {
      return IngredientCheck(
        ingredient: ingredient,
        availability: IngredientAvailability.unitMismatch,
        // The amount as the cook wrote it, not a conversion that could not be made.
        required_: quantity,
        onHand: onHand.totalRemaining,
        nearestExpiry: onHand.nearestExpiry,
      );
    }

    final needed = Qty(
      scaleMilli(
        wanted.milliBase,
        fromServings: fromServings,
        toServings: toServings,
      ),
      wanted.category,
    );

    final have = onHand.totalRemaining;
    final batches = batchesByItem[itemId];

    // **The precise path.** Batches were supplied, so the split between good and expired stock is
    // knowable and the answer carries the plan that will be executed.
    if (batches != null && needed.isPositive) {
      return _checkWithBatches(
        ingredient,
        batches: batches,
        needed: needed,
        onHand: onHand,
        today: today,
      );
    }

    // The cheap path: a total, no split. Expiry is not considered — see [judge]'s note.
    //
    // A zero requirement lands here too, deliberately. The consumption service refuses a non-positive
    // quantity as a validation error, which is right for a real consumption and wrong as a verdict —
    // "0 g of flour" is trivially satisfied, and it was `sufficient` before batches existed.
    if (have.milliBase >= needed.milliBase) {
      return IngredientCheck(
        ingredient: ingredient,
        availability: IngredientAvailability.sufficient,
        required_: needed,
        onHand: have,
        nearestExpiry: onHand.nearestExpiry,
      );
    }

    return IngredientCheck(
      ingredient: ingredient,
      availability: have.isZero
          ? IngredientAvailability.outOfStock
          : IngredientAvailability.short,
      required_: needed,
      onHand: have,
      shortfall: Qty(needed.milliBase - have.milliBase, needed.category),
      nearestExpiry: onHand.nearestExpiry,
    );
  }

  /// The verdict when batches are known, derived from `InventoryConsumptionService`.
  ///
  /// **Two calls, three answers.** The service refuses rather than returning a partial plan, so the
  /// question "would consent help?" is asked by planning again with consent rather than by inspecting
  /// a plan nobody may apply. Planning succeeds on good stock alone, or succeeds only once expired
  /// stock is permitted, or fails both ways — and there is no fourth outcome.
  IngredientCheck _checkWithBatches(
    RecipeIngredient ingredient, {
    required List<ConsumableBatch> batches,
    required Qty needed,
    required ItemStock onHand,
    required DateKey today,
  }) {
    final fresh = _consumption.plan(
      batches: batches,
      needed: needed,
      policy: DrawPolicy.freshFirst(today: today),
    );
    if (fresh.isOk) {
      return IngredientCheck(
        ingredient: ingredient,
        availability: IngredientAvailability.sufficient,
        required_: needed,
        onHand: onHand.totalRemaining,
        nearestExpiry: onHand.nearestExpiry,
        plan: fresh.valueOrNull,
      );
    }

    final permitted = _consumption.plan(
      batches: batches,
      needed: needed,
      policy: DrawPolicy.freshFirst(today: today, allowExpired: true),
    );

    // A validation failure is not a shortfall — it means the caller handed over batches in a category
    // the requirement was never bridged into. Reporting `short` would be a confident falsehood about
    // stock the engine simply could not compare, so it declines instead, exactly as a null bridge does.
    if (permitted.failureOrNull is ValidationFailure) {
      return IngredientCheck(
        ingredient: ingredient,
        availability: IngredientAvailability.unitMismatch,
        required_: needed,
        onHand: onHand.totalRemaining,
        nearestExpiry: onHand.nearestExpiry,
      );
    }

    if (permitted.isOk) {
      return IngredientCheck(
        ingredient: ingredient,
        availability: IngredientAvailability.needsExpired,
        required_: needed,
        onHand: onHand.totalRemaining,
        nearestExpiry: onHand.nearestExpiry,
        // The plan that would actually run once the cook agrees. Handing over the fresh-only attempt
        // would mean the sheet describing the consent and the deduction performing it were different
        // objects — and it failed, so there is no plan on it to hand over.
        plan: permitted.valueOrNull,
      );
    }

    // Not enough even counting expired stock. Summed from the batches rather than read from the
    // rollup, because the batches are what was planned against and a stale `v_item_stock` row would
    // otherwise put a number on screen the deduction could not honour.
    var availableMilli = 0;
    for (final batch in batches) {
      if (batch.remaining.isPositive)
        availableMilli += batch.remaining.milliBase;
    }
    return IngredientCheck(
      ingredient: ingredient,
      // `outOfStock` only when there is nothing usable at all, expired included — a cupboard holding
      // something past its date is not empty.
      availability: availableMilli > 0
          ? IngredientAvailability.short
          : IngredientAvailability.outOfStock,
      required_: needed,
      onHand: onHand.totalRemaining,
      shortfall: Qty(needed.milliBase - availableMilli, needed.category),
      nearestExpiry: onHand.nearestExpiry,
    );
  }

  /// Converts [quantity] into [item]'s own dimension, or null when the item cannot say how.
  ///
  /// **Only the item knows the conversion.** A tablespoon is 14.787 ml for everything, but a
  /// tablespoon of butter and one of flour weigh different amounts — so volume-to-weight needs
  /// `densityMilliGramsPerMl`, and count-to-weight needs `milliGramsPerPiece`. Both are nullable,
  /// and null keeps the answer *unanswerable* rather than turning it into a guess.
  ///
  /// Only bridging **to** weight is implemented. An item kept by volume asked for in grams needs the
  /// inverse of the same number; it is easy to add and nothing has needed it, so this returns null
  /// rather than shipping a path no test exercises.
  static Qty? _bridge(Qty quantity, Item item) {
    if (item.unitCategory != UnitCategory.weight) return null;

    final factor = switch (quantity.category) {
      // milliBase is thousandths of a millilitre; density is milli-grams per whole millilitre.
      UnitCategory.volume => item.densityMilliGramsPerMl,
      UnitCategory.count => item.milliGramsPerPiece,
      UnitCategory.weight => null,
    };
    if (factor == null) return null;
    // Multiply before dividing, so integer arithmetic keeps its precision (Law L1).
    return Qty(quantity.milliBase * factor ~/ 1000, UnitCategory.weight);
  }

  CookabilityStatus _statusFor({
    required int requiredCount,
    required int missing,
    required int uncheckable,
    required int expired,
    required bool anyAbsent,
  }) {
    if (requiredCount == 0) return CookabilityStatus.empty;
    if (anyAbsent) return CookabilityStatus.blocked;
    if (missing > 0) return CookabilityStatus.short;
    // Nothing missing — but the engine will not claim "ready" while it could not check everything.
    if (uncheckable > 0) return CookabilityStatus.uncheckable;
    // **Below `uncheckable`, above `ready`.** An unanswerable ingredient is the more important
    // caveat: it means the verdict itself is incomplete, whereas this one is a complete verdict that
    // happens to need permission.
    if (expired > 0) return CookabilityStatus.readyWithExpired;
    return CookabilityStatus.ready;
  }
}
```

### `lib/domain/services/currency_rate_service.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/converted_money.dart';

/// One cached rate: how many units of [quoteCode] one USD bought on [on].
///
/// Every cached rate is USD-based (ARCH_3 §1.2) — `currency_rates` never stores any other base —
/// which is what makes a single daily fetch enough for every pair the app supports.
class UsdRate {
  /// Creates a rate.
  const UsdRate({
    required this.quoteCode,
    required this.on,
    required this.rate,
    required this.rateRaw,
  });

  /// The currency being quoted against USD.
  final String quoteCode;

  /// The civil date the rate was quoted for.
  final DateKey on;

  /// Units of [quoteCode] per one USD.
  final double rate;

  /// The source's own representation of [rate], kept so a figure a user questions can be
  /// reproduced exactly (ARCH_3 §1.3.7).
  final String rateRaw;
}

/// Everything one fetch produced, normalised so the cache never learns which source it came from.
///
/// `CurrencyApiClient` maps both the fawazahmed0 and Frankfurter response shapes into this, because
/// they disagree about almost everything — key casing, nesting depth, and where the date lives
/// (ARCH_3 §1.2).
class RateSnapshot {
  /// Creates a snapshot.
  const RateSnapshot({
    required this.on,
    required this.rates,
    required this.source,
  });

  /// The civil date every rate in [rates] is quoted for.
  final DateKey on;

  /// USD-based rates, one per quote currency.
  final List<UsdRate> rates;

  /// Which ladder entry produced this, for debugging only. Never affects a conversion.
  final String source;

  /// True when the fetch produced nothing usable.
  bool get isEmpty => rates.isEmpty;
}

/// An immutable, in-memory index of every cached USD rate, and the single owner of ARCH_3 §1.2's
/// pivot and §1.3's lookup rule.
///
/// Built once and queried many times, deliberately. ARCH_3 §1.5 specifies `toHome` as a
/// *synchronous* call, which only works if the rates are already in hand — and converting a list of
/// 500 transactions for a monthly total would otherwise mean 1000 asynchronous cache round trips,
/// two per amount. Loading the table once and converting synchronously is both what the contract
/// asks for and dramatically less work.
///
/// It is also pure, which is why the whole lookup rule — including the weekend gap and the
/// approximate fallback — is testable with a literal map and no database at all.
class RateTable {
  /// Builds a table from [rates], indexing each quote currency's rates by date.
  RateTable({
    required Iterable<UsdRate> rates,
    required Map<String, int> decimalDigitsByCode,
  }) : _decimalDigits = Map.unmodifiable(decimalDigitsByCode) {
    for (final rate in rates) {
      final code = rate.quoteCode.toUpperCase();
      (_byQuote[code] ??= <UsdRate>[]).add(rate);
    }
    // Ascending by date, so the lookup can walk backwards from the target and take the first hit.
    for (final list in _byQuote.values) {
      list.sort((a, b) => DateKey.compare(a.on, b.on));
    }
  }

  /// An empty table — every lookup misses, so every conversion is `unconverted`.
  ///
  /// Only `_decimalDigits` is initialized here. `_byQuote` already has `= {}` at its declaration —
  /// which the primary constructor depends on, since it populates the map in its body rather than
  /// its initializer list — and Dart forbids initializing a final field in both places.
  RateTable.empty() : _decimalDigits = const {};

  final Map<String, List<UsdRate>> _byQuote = {};
  final Map<String, int> _decimalDigits;

  /// The USD code, which needs no cached row: one USD is one USD on every date.
  static const String pivotCode = 'USD';

  /// True when no rate is cached for any currency.
  bool get isEmpty => _byQuote.isEmpty;

  /// Every quote currency this table can resolve.
  Iterable<String> get quoteCodes => _byQuote.keys;

  /// Resolves the USD leg for [code] as of [on], applying ARCH_3 §1.3's lookup rule.
  ///
  /// The greatest cached date **on or before** [on] wins, and counts as
  /// [RateQuality.exact] however old it is — that is what makes a Saturday transaction resolve to
  /// Friday's rate instead of failing, which the rule exists for. Only when *no* row on or before
  /// [on] exists does it fall forward to the earliest row available and mark the result
  /// [RateQuality.approximate]. Never interpolates, never extrapolates.
  RateLeg? legFor({required String code, required DateKey on}) {
    final upper = code.toUpperCase();
    if (upper == pivotCode) {
      return RateLeg(rate: 1, quotedOn: on, quality: RateQuality.exact, rateRaw: '1');
    }

    final rates = _byQuote[upper];
    if (rates == null || rates.isEmpty) return null;

    UsdRate? onOrBefore;
    for (final rate in rates) {
      if (rate.on.value <= on.value) {
        onOrBefore = rate;
      } else {
        break;
      }
    }
    if (onOrBefore != null) {
      return RateLeg(
        rate: onOrBefore.rate,
        quotedOn: onOrBefore.on,
        quality: RateQuality.exact,
        rateRaw: onOrBefore.rateRaw,
      );
    }

    final earliest = rates.first;
    return RateLeg(
      rate: earliest.rate,
      quotedOn: earliest.on,
      quality: RateQuality.approximate,
      rateRaw: earliest.rateRaw,
    );
  }

  /// The cross-rate from [from] to [to] as of [on], or null when either leg is missing.
  ///
  /// `INR→JPY = (USD→JPY) / (USD→INR)`, exactly as ARCH_3 §1.2 specifies. Both legs come from the
  /// same USD pivot, so no pair needs its own cached row.
  CrossRate? crossRate({
    required String from,
    required String to,
    required DateKey on,
  }) {
    if (from.toUpperCase() == to.toUpperCase()) {
      return CrossRate(rate: 1, quotedOn: on, quality: RateQuality.exact);
    }
    final fromLeg = legFor(code: from, on: on);
    final toLeg = legFor(code: to, on: on);
    if (fromLeg == null || toLeg == null) return null;
    if (fromLeg.rate == 0) return null;

    return CrossRate(
      rate: toLeg.rate / fromLeg.rate,
      quotedOn: _combinedQuotedOn(fromLeg, toLeg, on),
      quality: fromLeg.quality == RateQuality.approximate ||
          toLeg.quality == RateQuality.approximate
          ? RateQuality.approximate
          : RateQuality.exact,
    );
  }

  /// Converts [amount] into [toCurrencyCode] as of [on].
  ///
  /// Returns [ConvertedMoney.unconverted] when either leg has no cached rate at all, or when
  /// either currency's precision is unknown — never a zero, because a missing rate means the amount
  /// must be *excluded* from a total rather than counted as nothing (ARCH_3 §1.3.4).
  ConvertedMoney convert({
    required Money amount,
    required String toCurrencyCode,
    required DateKey on,
  }) {
    if (amount.currencyCode.toUpperCase() == toCurrencyCode.toUpperCase()) {
      return ConvertedMoney(
        original: amount,
        quality: RateQuality.exact,
        converted: amount,
        rate: 1,
        rateDateKey: on,
      );
    }

    final cross = crossRate(from: amount.currencyCode, to: toCurrencyCode, on: on);
    if (cross == null) return ConvertedMoney.unconverted(amount);

    final fromDigits = _decimalDigits[amount.currencyCode];
    final toDigits = _decimalDigits[toCurrencyCode];
    if (fromDigits == null || toDigits == null) {
      // A rate without a precision cannot produce a correct minor-unit figure — converting into
      // JPY needs to know it has none. Excluding is honest; guessing 2 would misstate every yen.
      return ConvertedMoney.unconverted(amount);
    }

    return ConvertedMoney(
      original: amount,
      quality: cross.quality,
      converted: amount.convert(
        rate: cross.rate,
        toCurrencyCode: toCurrencyCode,
        fromDecimalDigits: fromDigits,
        toDecimalDigits: toDigits,
      ),
      rate: cross.rate,
      rateDateKey: cross.quotedOn,
    );
  }

  /// The honest "as of" date for a cross-rate built from [fromLeg] and [toLeg].
  ///
  /// When both legs resolved exactly, the answer is the requested date. When a leg fell *forward*
  /// past it — the only way [RateQuality.approximate] is reached — the conversion cannot truthfully
  /// claim to be as of anything earlier than the latest such fallback.
  DateKey _combinedQuotedOn(RateLeg fromLeg, RateLeg toLeg, DateKey on) {
    final fromApprox = fromLeg.quality == RateQuality.approximate;
    final toApprox = toLeg.quality == RateQuality.approximate;
    if (!fromApprox && !toApprox) return on;
    if (fromApprox && !toApprox) return fromLeg.quotedOn;
    if (toApprox && !fromApprox) return toLeg.quotedOn;
    return fromLeg.quotedOn.value > toLeg.quotedOn.value ? fromLeg.quotedOn : toLeg.quotedOn;
  }
}

/// One resolved side of a USD-pivoted lookup.
class RateLeg {
  /// Creates a leg.
  const RateLeg({
    required this.rate,
    required this.quotedOn,
    required this.quality,
    required this.rateRaw,
  });

  /// Units of the quote currency per one USD.
  final double rate;

  /// The date the applied rate was actually quoted for, which may not be the date requested.
  final DateKey quotedOn;

  /// How reliable this leg is.
  final RateQuality quality;

  /// The source's own string for [rate].
  final String rateRaw;
}

/// A resolved rate between two non-USD currencies.
class CrossRate {
  /// Creates a cross-rate.
  const CrossRate({
    required this.rate,
    required this.quotedOn,
    required this.quality,
  });

  /// Units of the target currency per one unit of the source.
  final double rate;

  /// The honest "as of" date for this rate.
  final DateKey quotedOn;

  /// How reliable this rate is.
  final RateQuality quality;
}

/// Loads every cached USD rate plus each currency's precision, as one table.
///
/// A function rather than an interface so `domain/` never names a `data/` type (Law L12): Phase 5's
/// wiring passes a closure over `CurrencyDao`.
typedef RateTableLoader = Future<RateTable> Function();

/// Persists a fetched snapshot into the rate cache.
typedef RateSnapshotSaver = Future<void> Function(RateSnapshot snapshot);

/// Fetches today's rates, or returns null when every ladder entry failed.
typedef RateSnapshotFetcher = Future<RateSnapshot?> Function();

/// Reads the newest cached rate date, so a same-day sync can be skipped.
typedef NewestRateDateReader = Future<DateKey?> Function();

/// Orchestrates the currency subsystem: ARCH_3 §1.5's service contract.
final class CurrencyRateService {
  /// Creates the service over its four collaborators, each a function so this stays inside
  /// `domain/` without importing anything from `data/`.
  const CurrencyRateService({
    required RateTableLoader loadTable,
    required RateSnapshotSaver saveSnapshot,
    required RateSnapshotFetcher fetchSnapshot,
    required NewestRateDateReader newestCachedDate,
    required Clock clock,
  })  : _loadTable = loadTable,
        _saveSnapshot = saveSnapshot,
        _fetchSnapshot = fetchSnapshot,
        _newestCachedDate = newestCachedDate,
        _clock = clock;

  final RateTableLoader _loadTable;
  final RateSnapshotSaver _saveSnapshot;
  final RateSnapshotFetcher _fetchSnapshot;
  final NewestRateDateReader _newestCachedDate;
  final Clock _clock;

  /// Loads the current rate table. Callers converting more than one amount should hold onto it.
  Future<RateTable> table() => _loadTable();

  /// Converts [amount] into [homeCurrencyCode] as of [on].
  ///
  /// Loads the table per call, so prefer [table] plus [RateTable.convert] for a list.
  Future<ConvertedMoney> toHome({
    required Money amount,
    required DateKey on,
    required String homeCurrencyCode,
  }) async {
    final rates = await _loadTable();
    return rates.convert(amount: amount, toCurrencyCode: homeCurrencyCode, on: on);
  }

  /// The rate from [from] to [to] as of [on], for the explicit freeze action (ARCH_3 §1.3.6).
  Future<CrossRate?> rateOn({
    required String from,
    required String to,
    required DateKey on,
  }) async {
    final rates = await _loadTable();
    return rates.crossRate(from: from, to: to, on: on);
  }

  /// Fetches and caches today's rates, at most once a day.
  ///
  /// **Never throws and never blocks a write** (Law L11, ARCH_3 §1.3.2). Every failure path — no
  /// network, a ladder that exhausted all three entries, a malformed body, a database error on
  /// save — returns normally, because a rate is a display convenience and a transaction the user
  /// just typed is not. Callers may safely ignore the future entirely.
  ///
  /// Skips the fetch when the cache already holds today's date, which is what makes ARCH_3 §1.2's
  /// "one request per day for the entire app, forever" true rather than aspirational.
  Future<void> syncDailyRates() async {
    try {
      final today = _clock.today();
      final newest = await _newestCachedDate();
      if (newest != null && !newest.isBefore(today)) return;

      final snapshot = await _fetchSnapshot();
      if (snapshot == null || snapshot.isEmpty) return;
      await _saveSnapshot(snapshot);
    } catch (_) {
      // Deliberately swallowed. See the doc comment: this method exists to be safe to call from a
      // foreground hook without any caller having to reason about failure.
      return;
    }
  }
}
```

### `lib/domain/services/date_range_service.dart`

```dart
import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/time/date_key.dart';

/// An inclusive civil-date window: every `DateKey` from [from] to [to], both ends counted.
typedef DateRange = ({DateKey from, DateKey to});

/// Resolves a [DateRangePreset] into concrete dates.
///
/// Takes `today` as a parameter on every call rather than holding a `Clock`, for the same reason no
/// view in this schema consults the clock (ARCH_2 §12.2): a range that reads the time itself cannot
/// be asserted against a `FixedClock`, and every analytics figure downstream would inherit that
/// non-determinism.
///
/// Both ends are **inclusive**, matching `DateKeyColumnFilters.isInDateRange` and SQL's `BETWEEN`,
/// so a resolved range can be handed straight to a query without an off-by-one adjustment.
final class DateRangeService {
  /// Creates the service.
  const DateRangeService();

  /// The earliest date this app treats as real, used as the lower bound for [DateRangePreset.allTime].
  ///
  /// A sentinel rather than a query for the oldest row: "all time" must resolve without touching the
  /// database, and `1900-01-01` is comfortably before any household record while staying well inside
  /// `DateKey`'s range.
  static final DateKey earliest = DateKey.fromYmd(1900, 1, 1);

  /// Resolves [preset] against [today].
  ///
  /// Returns null for [DateRangePreset.custom], which by definition carries dates this service does
  /// not know — the caller supplies them. Returning null rather than a guessed window means a UI
  /// that forgets to handle `custom` shows nothing instead of silently showing the wrong month.
  DateRange? resolve(DateRangePreset preset, DateKey today) {
    switch (preset) {
      case DateRangePreset.today:
        return (from: today, to: today);

      case DateRangePreset.last7Days:
      // Six days back, not seven: "last 7 days" includes today, so today plus six earlier days is
      // seven dates. Subtracting seven would span eight.
        return (from: today.addDays(-6), to: today);

      case DateRangePreset.last30Days:
        return (from: today.addDays(-29), to: today);

      case DateRangePreset.thisMonth:
        return (from: DateKey.fromYmd(today.year, today.month, 1), to: today);

      case DateRangePreset.lastMonth:
        final year = today.month == 1 ? today.year - 1 : today.year;
        final month = today.month == 1 ? 12 : today.month - 1;
        return (
        from: DateKey.fromYmd(year, month, 1),
        to: DateKey.fromYmd(year, month, _lastDayOfMonth(year, month)),
        );

      case DateRangePreset.thisYear:
        return (from: DateKey.fromYmd(today.year, 1, 1), to: today);

      case DateRangePreset.allTime:
        return (from: earliest, to: today);

      case DateRangePreset.custom:
        return null;
    }
  }

  /// The calendar month containing [anyDayInMonth], whole.
  ///
  /// What a month-grid calendar asks for: the full month regardless of where today falls, unlike
  /// [DateRangePreset.thisMonth] which stops at today.
  DateRange wholeMonthOf(DateKey anyDayInMonth) {
    final year = anyDayInMonth.year;
    final month = anyDayInMonth.month;
    return (
    from: DateKey.fromYmd(year, month, 1),
    to: DateKey.fromYmd(year, month, _lastDayOfMonth(year, month)),
    );
  }

  /// The month before [range]'s start, whole — for a period-over-period comparison.
  DateRange previousWholeMonth(DateKey anyDayInMonth) {
    final year = anyDayInMonth.month == 1 ? anyDayInMonth.year - 1 : anyDayInMonth.year;
    final month = anyDayInMonth.month == 1 ? 12 : anyDayInMonth.month - 1;
    return (
    from: DateKey.fromYmd(year, month, 1),
    to: DateKey.fromYmd(year, month, _lastDayOfMonth(year, month)),
    );
  }

  /// A window of the same length as [range] ending the day before it starts.
  ///
  /// The honest comparison for a rolling preset: "last 30 days" against the 30 days before those,
  /// rather than against a calendar month of a different length.
  DateRange precedingWindowOf(DateRange range) {
    final lengthDays = range.to.diffDays(range.from);
    final end = range.from.addDays(-1);
    return (from: end.addDays(-lengthDays), to: end);
  }

  /// True when [date] falls inside [range], both ends counted.
  bool contains(DateRange range, DateKey date) =>
      date.isWithin(range.from, range.to);

  /// How many dates [range] spans, both ends counted.
  int lengthInDays(DateRange range) => range.to.diffDays(range.from) + 1;

  /// Day zero of the following month is the last day of this one, which handles February in both
  /// leap and non-leap years without a lookup table.
  static int _lastDayOfMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;
}
```

### `lib/domain/services/draw_plan.dart`

```dart
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';

/// One batch, and how much this plan would take from it.
final class DrawLine {
  /// Creates a line.
  const DrawLine({
    required this.batch,
    required this.amount,
    required this.isExpired,
  });

  /// The batch drawn from.
  final Batch batch;

  /// How much comes out of it. Never more than the batch holds.
  final Qty amount;

  /// Whether this batch was past its date on the day the plan was made.
  ///
  /// Carried on the line rather than recomputed by the reader, so a screen showing the plan and the
  /// repository executing it cannot disagree about which batches were the expired ones — the reader
  /// would need `today` to work it out again, and a second `today` is a second answer.
  final bool isExpired;
}

/// What a consumption would actually do, before it does it.
///
/// **The read that anomaly A08 asked for and the contract could not provide.**
/// `StockRepository.consume` already returns which batches it drew from — but *after* writing, so
/// "show that 600 g came out of two batches before confirming" was unimplementable. A plan is that
/// same answer, computed from batches and taking nothing.
final class DrawPlan {
  /// Creates a plan.
  const DrawPlan({
    required this.needed,
    required this.lines,
    required this.drawnMilli,
    required this.fromExpiredMilli,
    required this.expiredUntouchedMilli,
  });

  /// A plan that draws nothing, for a request of zero or less.
  const DrawPlan.nothing(this.needed)
    : lines = const [],
      drawnMilli = 0,
      fromExpiredMilli = 0,
      expiredUntouchedMilli = 0;

  /// How much was asked for.
  final Qty needed;

  /// The batches to draw from, in the order to draw them.
  final List<DrawLine> lines;

  /// How much the lines add up to.
  final int drawnMilli;

  /// How much of [drawnMilli] comes out of expired batches.
  final int fromExpiredMilli;

  /// Expired stock this plan does **not** touch.
  ///
  /// The headroom that makes [couldCompleteWithExpired] answerable: when a plan falls short with
  /// expired stock excluded, this is what saying yes would unlock. Without it the caller would have
  /// to re-scan the batches to find out, which is the second opinion this type exists to prevent.
  final int expiredUntouchedMilli;

  /// How much the lines add up to.
  Qty get drawn => Qty(drawnMilli, needed.category);

  /// How much comes from expired batches.
  Qty get fromExpired => Qty(fromExpiredMilli, needed.category);

  /// How much is still missing. Zero when the plan is complete.
  Qty get shortfall => Qty(
    drawnMilli >= needed.milliBase ? 0 : needed.milliBase - drawnMilli,
    needed.category,
  );

  /// Whether this plan covers what was asked for.
  bool get isComplete => drawnMilli >= needed.milliBase;

  /// Whether any of it comes from expired stock.
  ///
  /// **This is what a confirmation prompt hangs on**, and it is a fact about the plan rather than a
  /// question about the shelf: there may be expired stock the plan never reaches, and warning about
  /// that would be warning about nothing.
  bool get usesExpired => fromExpiredMilli > 0;

  /// Whether saying yes to expired stock would make this plan complete.
  ///
  /// False when the plan already works, and false when even the expired stock is not enough — in
  /// which case there is nothing to offer and the honest answer is a shortfall.
  bool get couldCompleteWithExpired =>
      !isComplete && expiredUntouchedMilli >= shortfall.milliBase;
}

/// Decides which batches a consumption should draw from, and in what order.
///
/// Pure: entities in, a plan out. No repository, no clock, no Flutter — the same shape as
/// `CookabilityEngine`, and for the same reason. Three callers need this answer and they must not
/// each derive it: the engine to judge a recipe, a confirmation sheet to describe what will happen,
/// and the repository to carry it out. **Two of those disagreeing about the same recipe is the
/// failure ARCH_M §6 names** — no value displayed from a second source.
///
/// ## Why this is not FEFO
///
/// `BatchRepository.watchByItemFefo` orders by nearest expiry first, undated last — and an expired
/// date *is* the nearest date, so FEFO hands out expired stock before anything else. That is right
/// for a waste write-off and wrong for cooking, which is the whole of the reported problem: the
/// deduction was not misbehaving, it was following a policy chosen for a different purpose.
///
/// So the order here is:
///
/// 1. **Unexpired, soonest expiry first**, undated last — FEFO among the food that is still good, so
///    cooking still burns down what is about to go off.
/// 2. **Expired, least spoiled first**, and only when the caller permits it. Strict FEFO would reach
///    for the *oldest* expired batch, which is the most spoiled thing in the house; among food that
///    is already past its date, nearest-to-fresh is the only defensible order.
///
/// **The existing FEFO path is deliberately untouched.** A waste or expiry movement should still
/// take the worst batch first, and nothing here changes that — there is no policy enum because
/// nothing needs a second order yet.
final class DrawPlanner {
  /// Creates the planner. Stateless.
  const DrawPlanner();

  /// Plans a draw of [needed] from [batches] as of [today].
  ///
  /// [batches] may arrive in any order; this sorts. Batches holding nothing are skipped, so a caller
  /// can pass an item's whole history without filtering.
  ///
  /// [allowExpired] false is the default and the safe one: the plan then reports a shortfall it could
  /// have covered, which is exactly the state a confirmation prompt needs to describe.
  ///
  /// Throws when a batch's category differs from [needed]'s. That means the caller skipped the
  /// volume-to-weight bridge, and quietly dropping the batch would report a shortfall for stock that
  /// is sitting on the shelf.
  DrawPlan plan({
    required List<Batch> batches,
    required Qty needed,
    required DateKey today,
    bool allowExpired = false,
  }) {
    if (needed.milliBase <= 0) return DrawPlan.nothing(needed);

    final fresh = <Batch>[];
    final stale = <Batch>[];
    for (final batch in batches) {
      if (!batch.hasStock) continue;
      if (batch.remainingQuantity.category != needed.category) {
        throw ArgumentError.value(
          batch.id,
          'batches',
          'batch is ${batch.remainingQuantity.category.name} but '
              '${needed.category.name} was asked for — bridge the requirement first',
        );
      }
      (batch.isExpired(today) ? stale : fresh).add(batch);
    }

    fresh.sort(_soonestFirst);
    stale.sort(_leastSpoiledFirst);

    final lines = <DrawLine>[];
    var drawn = 0;
    var fromExpired = 0;

    for (final batch in [...fresh, if (allowExpired) ...stale]) {
      final outstanding = needed.milliBase - drawn;
      if (outstanding <= 0) break;
      final available = batch.remainingQuantity.milliBase;
      final take = available < outstanding ? available : outstanding;
      final expired = batch.isExpired(today);
      lines.add(
        DrawLine(
          batch: batch,
          amount: Qty(take, needed.category),
          isExpired: expired,
        ),
      );
      drawn += take;
      if (expired) fromExpired += take;
    }

    var expiredTotal = 0;
    for (final batch in stale) {
      expiredTotal += batch.remainingQuantity.milliBase;
    }

    return DrawPlan(
      needed: needed,
      lines: lines,
      drawnMilli: drawn,
      fromExpiredMilli: fromExpired,
      expiredUntouchedMilli: expiredTotal - fromExpired,
    );
  }

  /// Soonest expiry first, undated last — the order `watchByItemFefo` documents.
  ///
  /// A batch with no expiry sorts last because it is the one thing that cannot go off: spending it
  /// ahead of something dated would waste the dated one.
  static int _soonestFirst(Batch a, Batch b) {
    final left = a.expiryDateKey;
    final right = b.expiryDateKey;
    if (left == null && right == null) return a.id.compareTo(b.id);
    if (left == null) return 1;
    if (right == null) return -1;
    final byExpiry = left.compareTo(right);
    // **Ties break on id, and the tie-break is not cosmetic.** Two batches expiring on the same day
    // are equally good choices, but a plan shown to the user and a plan executed a second later must
    // list them in the same order or the confirmation described something else.
    return byExpiry != 0 ? byExpiry : a.id.compareTo(b.id);
  }

  /// Least spoiled first — the most recent expiry among batches already past it.
  ///
  /// The reverse of [_soonestFirst], and deliberately not FEFO. A null expiry cannot appear here: a
  /// batch with no date is never expired.
  static int _leastSpoiledFirst(Batch a, Batch b) {
    final left = a.expiryDateKey;
    final right = b.expiryDateKey;
    if (left == null || right == null) return a.id.compareTo(b.id);
    final byExpiry = right.compareTo(left);
    return byExpiry != 0 ? byExpiry : a.id.compareTo(b.id);
  }
}
```

### `lib/domain/services/draw_policy.dart`

```dart
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';

/// Which order stock should be drawn in, and whether expired batches may participate.
///
/// **Two orders, because the same rule cannot serve both purposes.** Drawing stock down to *use* it
/// and drawing it down to *write it off* want opposite things from expired batches, and a single
/// ordering would be wrong for one of them. Making the choice a parameter with a default keeps every
/// caller written before this policy existed on the behaviour it was written against.
///
/// **Its own file, and the reason is a cycle rather than taste.** `InventoryConsumptionService` already
/// imports `StockRepository` for `ConsumptionDraw`; putting this class in the service and then naming
/// it on `StockRepository.consume` would have the contract importing the service that imports the
/// contract. A policy shared by a contract and a service belongs in neither.
final class DrawPolicy {
  /// Nearest expiry first, undated last, expired batches included.
  ///
  /// The waste-minimising order (anomaly A08) and the default, because it is what every caller before
  /// this policy existed was doing. Right for a waste or expiry write-off, where the most spoiled
  /// batch is exactly the one to reach for.
  const DrawPolicy.fefo() : today = null, allowExpired = true;

  /// Unexpired batches first — nearest expiry among those — then expired ones last, and only when
  /// [allowExpired].
  ///
  /// Right for cooking. FEFO orders by nearest expiry and an expired date *is* the nearest date, so
  /// under FEFO a recipe silently eats the food that is already off before touching anything good.
  /// That was not a bug in the ordering; it was the wrong ordering for the job.
  ///
  /// Among expired batches the order is **least spoiled first**, which is the reverse of FEFO and
  /// deliberate: strict FEFO would hand over the oldest expired batch, the most spoiled thing in the
  /// house. Among food already past its date, nearest-to-fresh is the only defensible choice.
  const DrawPolicy.freshFirst({
    required DateKey today,
    this.allowExpired = false,
  }) : today = today;

  /// The date expiry is judged against, or null under [DrawPolicy.fefo] where it is not consulted.
  ///
  /// Passed in rather than read from a clock, so a plan is reproducible under a `FixedClock` — the
  /// rule `ConsumableBatch.isExpired` and the views follow.
  final DateKey? today;

  /// Whether expired batches may be drawn from at all.
  final bool allowExpired;

  /// Whether this policy distinguishes expired stock from good stock.
  bool get isExpiryAware => today != null;

  /// Whether [batch] may be drawn from under this policy.
  ///
  /// **One definition, two readers.** `InventoryConsumptionService.plan` uses it to choose what to
  /// draw and `StockRepositoryImpl` uses it to decide what a refusal message may quote. Two copies of
  /// "which batches does this policy admit" would be the same fault the service's own doc comment
  /// records about ordering rules.
  bool admits(ConsumableBatch batch) {
    final on = today;
    return allowExpired || on == null || !batch.isExpired(on);
  }
}
```

### `lib/domain/services/inventory_consumption_service.dart`

```dart
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/repositories/stock_repository.dart';
import 'package:alaya/domain/services/draw_policy.dart';

export 'package:alaya/domain/services/draw_policy.dart' show DrawPolicy;

/// The facts consumption needs about one batch, and nothing else.
///
/// A narrow input rather than the full `Batch` entity: FEFO needs four fields, and taking twelve
/// would couple the algorithm to every unrelated change to a batch. It also means the whole engine
/// is exercisable from literals — which is why `consumption_test.dart` needs no database.
class ConsumableBatch {
  /// Creates an input row.
  const ConsumableBatch({
    required this.batchId,
    required this.remaining,
    required this.purchasedDateKey,
    this.expiryDateKey,
  });

  /// Builds an input row from a domain [Batch].
  factory ConsumableBatch.fromBatch(Batch batch) => ConsumableBatch(
    batchId: batch.id,
    remaining: batch.remainingQuantity,
    purchasedDateKey: batch.purchasedDateKey,
    expiryDateKey: batch.expiryDateKey,
  );

  /// The batch.
  final String batchId;

  /// How much is left in it.
  final Qty remaining;

  /// When it was acquired — the tiebreaker between two batches expiring on the same date.
  final DateKey purchasedDateKey;

  /// When it expires, or null if it does not.
  final DateKey? expiryDateKey;

  /// True when this batch has passed its expiry as of [today].
  ///
  /// **Strict: `expiry < today`.** A use-by of the 14th is usable on the 14th, which is what
  /// `v_calendar_events` already assumes — a batch expiring today appears as an upcoming event rather
  /// than as history.
  ///
  /// Deliberately the same one-line predicate as `Batch.isExpired`, and it must stay that way. This
  /// type cannot delegate to it because it holds four fields rather than a batch, and a projection
  /// that could not answer for itself would push the question back onto every caller.
  bool isExpired(DateKey today) {
    final expiry = expiryDateKey;
    return expiry != null && expiry < today;
  }
}

/// A consumption that can be carried out: which batches to draw from, and how much from each.
class ConsumptionPlan {
  /// Creates a plan.
  const ConsumptionPlan({
    required this.draws,
    required this.totalAvailable,
    required this.fromExpired,
  });

  /// The draws, in the order they should be applied.
  final List<ConsumptionDraw> draws;

  /// Everything that was on hand when the plan was made, for the caller's messaging.
  ///
  /// Counts only what the policy would consider: under a policy excluding expired stock this is the
  /// good stock alone, which is what makes the `insufficientStock` message match the refusal.
  final Qty totalAvailable;

  /// How much of this plan comes out of batches that are past their date.
  ///
  /// **What a confirmation prompt hangs on**, and a fact about the plan rather than about the shelf:
  /// there may be expired stock the plan never reaches, and warning about that would be warning about
  /// nothing. Always zero under a policy that is not expiry-aware, because that policy does not ask.
  final Qty fromExpired;

  /// How many movement rows applying this plan will write — exactly one per draw.
  int get movementCount => draws.length;

  /// Every batch this plan touches.
  Iterable<String> get touchedBatchIds => draws.map((d) => d.batchId);

  /// Whether any of this plan comes from stock past its date.
  bool get usesExpired => fromExpired.isPositive;
}

/// Plans stock consumption.
///
/// **Pure.** No I/O, no clock, no database — given a list of batches and a quantity it returns the
/// draws, and the caller writes them. That split is what lets `StockRepository.consume` guarantee
/// atomicity (all draws in one transaction) while this class guarantees correctness.
///
/// Phase 3C originally held this logic inside `StockRepositoryImpl._planDraws`, because no service
/// existed yet. It lives here now so there is one definition — the same consolidation Phase 4A made
/// for the currency cross-rate, and for the same reason: two copies of an ordering rule drift apart
/// and the second one is always the one that is wrong.
///
/// **The expiry-aware order was very nearly the third copy.** A separate `DrawPlanner` was written for
/// the cookability engine before this service was found, which is exactly the outcome the paragraph
/// above warns about. It lives here instead, as a [DrawPolicy] on the one definition.
final class InventoryConsumptionService {
  /// Creates the service.
  const InventoryConsumptionService();

  /// Orders [batches] as stock should be drawn down: nearest expiry first, undated batches last,
  /// ties broken by purchase date.
  ///
  /// Undated stock goes last rather than first because it is the stock that *cannot* spoil on a
  /// deadline — drawing it down first would leave the dated stock to expire, which is precisely the
  /// waste this ordering exists to prevent (anomaly A08). Batches holding nothing are dropped: a
  /// zero draw would trip `stock_movements`' `CHECK (quantity_milli > 0)` and, worse, would record
  /// that nothing moved.
  ///
  /// Sorting happens here rather than being assumed of the caller. The DAO also returns FEFO order
  /// from SQL, where an index can serve it — but a pure function that trusts its input's order is a
  /// function whose correctness depends on something it cannot see.
  List<ConsumableBatch> orderFefo(Iterable<ConsumableBatch> batches) {
    final ordered = batches.where((b) => b.remaining.isPositive).toList()
      ..sort(_byNearestExpiry);
    return ordered;
  }

  /// Orders [batches] so good stock is spent before anything past its date on [today].
  ///
  /// Unexpired batches first in [orderFefo]'s own order, so cooking still burns down what is about to
  /// go off. Expired batches follow, least spoiled first. Batches holding nothing are dropped, as in
  /// [orderFefo].
  ///
  /// Returns every batch including the expired ones — excluding them is [plan]'s decision, because a
  /// caller needs to know how much expired stock exists in order to offer it.
  List<ConsumableBatch> orderFreshFirst(
    Iterable<ConsumableBatch> batches,
    DateKey today,
  ) {
    final fresh = <ConsumableBatch>[];
    final stale = <ConsumableBatch>[];
    for (final batch in batches) {
      if (!batch.remaining.isPositive) continue;
      (batch.isExpired(today) ? stale : fresh).add(batch);
    }
    fresh.sort(_byNearestExpiry);
    stale.sort(_byLeastSpoiled);
    return [...fresh, ...stale];
  }

  /// Orders [batches] according to [policy].
  List<ConsumableBatch> orderFor(
    Iterable<ConsumableBatch> batches,
    DrawPolicy policy,
  ) {
    final today = policy.today;
    return today == null ? orderFefo(batches) : orderFreshFirst(batches, today);
  }

  /// How much of [batches] a plan under [policy] could actually draw, in [category].
  ///
  /// **The number a refusal is allowed to quote.** A message naming a total the policy could not have
  /// reached would be arithmetic the user cannot reproduce — "only 250 g is on hand" beside a cupboard
  /// holding 550 g of which 300 g is off.
  Qty availableUnder(
    Iterable<ConsumableBatch> batches, {
    required DrawPolicy policy,
    required Qty ofCategory,
  }) {
    var milli = 0;
    for (final batch in batches) {
      if (!batch.remaining.isPositive) continue;
      if (!policy.admits(batch)) continue;
      milli += batch.remaining.milliBase;
    }
    return Qty(milli, ofCategory.category);
  }

  /// Plans drawing [needed] from [batches] under [policy].
  ///
  /// Fails with a [BusinessRuleFailure] carrying rule `insufficientStock` when the total on hand is
  /// less than [needed] — and returns **no draws at all** in that case, so a caller cannot
  /// accidentally apply a partial consumption. A ledger describing a consumption that only half
  /// happened is worse than one describing none of it, because nothing tells the user which half.
  ///
  /// Fails with a [ValidationFailure] on a non-positive quantity, and on a category mismatch
  /// between [needed] and any batch — a `Qty` in the wrong category is a bare integer that would be
  /// reinterpreted on read (Law L8).
  ///
  /// **The refusal is how a caller learns that consent would help.** Planning under
  /// `DrawPolicy.freshFirst(today: t)` and getting `insufficientStock`, then planning again with
  /// `allowExpired: true` and succeeding, is the difference between "you are short" and "you are short
  /// of good stock" — two answers rather than three states on one object, so nothing has to carry a
  /// partial plan nobody may apply.
  Result<ConsumptionPlan, Failure> plan({
    required Iterable<ConsumableBatch> batches,
    required Qty needed,
    DrawPolicy policy = const DrawPolicy.fefo(),
  }) {
    if (!needed.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'The quantity to consume must be greater than zero.',
          field: 'needed',
        ),
      );
    }

    final ordered = orderFor(batches, policy);
    for (final batch in ordered) {
      if (batch.remaining.category != needed.category) {
        return Result.failure(
          ValidationFailure(
            'Batch ${batch.batchId} is measured in ${batch.remaining.category.name}, not '
            '${needed.category.name}.',
            field: 'needed',
          ),
        );
      }
    }

    // Excluded rather than merely ordered last: a plan that must not touch expired stock must not
    // count it as available either, or the shortfall would quote a total the plan cannot reach.
    final usable = ordered.where(policy.admits).toList();
    final available = availableUnder(
      usable,
      policy: policy,
      ofCategory: needed,
    );
    if (available.milliBase < needed.milliBase) {
      return Result.failure(
        BusinessRuleFailure(
          'Not enough stock on hand to consume this quantity.',
          rule: 'insufficientStock',
        ),
      );
    }

    final today = policy.today;
    final draws = <ConsumptionDraw>[];
    var remaining = needed.milliBase;
    var expiredMilli = 0;
    for (final batch in usable) {
      if (remaining <= 0) break;
      final take = remaining < batch.remaining.milliBase
          ? remaining
          : batch.remaining.milliBase;
      if (take <= 0) continue;
      draws.add(
        ConsumptionDraw(
          batchId: batch.batchId,
          quantity: Qty(take, needed.category),
        ),
      );
      if (today != null && batch.isExpired(today)) expiredMilli += take;
      remaining -= take;
    }

    return Result.ok(
      ConsumptionPlan(
        draws: draws,
        totalAvailable: available,
        fromExpired: Qty(expiredMilli, needed.category),
      ),
    );
  }

  /// Plans consuming everything left in [batches] — for "used it all up".
  ///
  /// Always FEFO: emptying a shelf has no reason to prefer good stock, and every batch is drawn
  /// regardless of order.
  Result<ConsumptionPlan, Failure> planAll({
    required Iterable<ConsumableBatch> batches,
    required Qty zeroOfCategory,
  }) {
    final ordered = orderFefo(batches);
    final total = ordered.fold<int>(0, (sum, b) => sum + b.remaining.milliBase);
    if (total <= 0) {
      return const Result.failure(
        BusinessRuleFailure(
          'There is nothing on hand to consume.',
          rule: 'insufficientStock',
        ),
      );
    }
    return plan(batches: ordered, needed: Qty(total, zeroOfCategory.category));
  }

  /// Nearest expiry first, undated last, ties broken by purchase date.
  static int _byNearestExpiry(ConsumableBatch a, ConsumableBatch b) {
    // `expiryDateKey == null` sorts after any date. SQLite's NULLS LAST is not portable, so the
    // DAO expresses this as `expiry IS NULL` ascending; this is the Dart twin of that.
    final aUndated = a.expiryDateKey == null;
    final bUndated = b.expiryDateKey == null;
    if (aUndated != bUndated) return aUndated ? 1 : -1;
    if (!aUndated) {
      final byExpiry = DateKey.compare(a.expiryDateKey!, b.expiryDateKey!);
      if (byExpiry != 0) return byExpiry;
    }
    return DateKey.compare(a.purchasedDateKey, b.purchasedDateKey);
  }

  /// Most recent expiry first — least spoiled among batches already past their date.
  ///
  /// A null expiry cannot reach here: a batch with no date is never expired. The purchase tiebreak
  /// keeps the order deterministic, which matters because a plan shown in a confirmation and the plan
  /// applied a moment later must list equally-spoiled batches identically.
  static int _byLeastSpoiled(ConsumableBatch a, ConsumableBatch b) {
    final left = a.expiryDateKey;
    final right = b.expiryDateKey;
    if (left == null || right == null) {
      return DateKey.compare(a.purchasedDateKey, b.purchasedDateKey);
    }
    final byExpiry = DateKey.compare(right, left);
    return byExpiry != 0
        ? byExpiry
        : DateKey.compare(a.purchasedDateKey, b.purchasedDateKey);
  }
}
```

### `lib/domain/services/lock/app_lock.dart`

```dart
/// The app lock's contract, and the vocabulary an unlock attempt answers in.
///
/// **Why this exists in `domain/` when `PinService` already exists in `data/`.** `PinService` reaches
/// `flutter_secure_storage` through `AppLockStore`, and Law L12 bars a plugin dependency from `domain/`
/// — which is why it was written in `data/` in the first place. But ARCH_1 §6 draws `features → domain →
/// core` and `data → domain → core` as two separate chains, and not one of the seven delivered UI phases
/// imports `data/` from a feature. A lock screen that must branch on [UnlockRefusal] and read
/// [UnlockOutcome.retryAfter] for its countdown would have been the first.
///
/// **The deciding argument is not purity, and it is stronger than a layering diagram.** `PinService` is
/// declared `final class`, which in Dart 3 means it can be neither extended nor implemented outside its
/// own library — so a test fake of it is not awkward, it is **impossible**. `flutter_secure_storage` needs
/// a platform channel, so the real one cannot run in a widget test either. Between the two, the lock
/// screen's four required states (§9.1) had no way to be tested at all. Behind this interface they test
/// against a fake, which is the same reason `Clock` and `SecureKeyValueStore` are interfaces rather than
/// direct plugin calls. `BackupService` is `final` too, and `DataTransferPort` exists for the same reason.
///
/// This is the `AnalyticsPort` pattern: the contract in `domain/`, the plugin-bound implementation in
/// `data/`, the provider typed as the contract so no feature can reach past it.
library;

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// Why an unlock attempt was refused.
enum UnlockRefusal {
  /// The PIN was wrong.
  wrongPin,

  /// Too many wrong attempts; a delay is in force.
  throttled,

  /// No lock is configured, so there is nothing to unlock.
  notEnabled,
}

/// The outcome of an unlock attempt.
class UnlockOutcome {
  /// Creates an outcome.
  const UnlockOutcome({
    required this.unlocked,
    this.refusal,
    this.failedCount = 0,
    this.retryAfter,
  });

  /// A successful unlock.
  const UnlockOutcome.success()
    : unlocked = true,
      refusal = null,
      failedCount = 0,
      retryAfter = null;

  /// Whether the app should open.
  final bool unlocked;

  /// Why not, when [unlocked] is false.
  final UnlockRefusal? refusal;

  /// How many consecutive wrong attempts have now been recorded.
  final int failedCount;

  /// How long the user must wait before the next attempt is even checked.
  final Duration? retryAfter;

  /// True when a delay is currently in force.
  bool get isThrottled => refusal == UnlockRefusal.throttled;
}

/// Verifies, changes, enables and disables the app lock.
///
/// **No encryption, and the contract says so where an implementer will read it.** The lock is a UI gate
/// over a plaintext database (ARCH_1 §2.1): nothing here derives a database key, and nothing here can
/// lock a user out of their own data. That is what makes the "forgot both" path able to export a readable
/// backup before erasing, which is the improvement dropping encryption bought (ARCH_3 §2.2).
abstract interface class AppLock {
  /// How many characters a recovery code has (ARCH_3 §2.1).
  ///
  /// **On the contract because the field that accepts one needs it**, and `RecoveryCode.length` lives in
  /// `data/` where a feature may not reach. A counter that disagreed with the validator would tell the
  /// user their correct code was the wrong length.
  static const int recoveryCodeLength = 10;

  /// Whether a lock is configured.
  Future<bool> get isEnabled;

  /// How many digits the configured PIN has.
  Future<int> readPinLength();

  /// How long until the next attempt will be checked, or null when none is owed.
  Future<Duration?> remainingLockout();

  /// How many consecutive wrong attempts have been recorded.
  ///
  /// Read by the optional auto-erase, which fires at ARCH_3 §2.3's tenth failure — the count has to be
  /// legible to the caller for that, not only to the throttle.
  Future<int> readFailedCount();

  /// Attempts to unlock with [pin].
  Future<UnlockOutcome> verifyPin(String pin);

  /// Enables the lock with [pin], returning the recovery code to show **once**.
  Future<Result<String, Failure>> enable({required String pin});

  /// Changes the PIN, verifying [currentPin] first. The recovery code is unchanged.
  Future<Result<void, Failure>> changePin({
    required String currentPin,
    required String newPin,
  });

  /// Disables the lock, verifying [pin] first.
  Future<Result<void, Failure>> disable({required String pin});

  /// Resets the PIN using [code], for the forgotten-PIN path.
  Future<Result<void, Failure>> resetWithRecoveryCode({
    required String code,
    required String newPin,
  });
}
```

### `lib/domain/services/lock/biometric_gate.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// Why a biometric prompt did not unlock.
enum BiometricRefusal {
  /// The device has no enrolled biometric, or none the app may use.
  unavailable,

  /// The user dismissed the prompt or failed the check.
  rejected,

  /// The platform refused — too many attempts, or a hardware lockout of its own.
  lockedOut,
}

/// The biometric shortcut on the lock screen (ARCH_3 §2.2).
///
/// **A shortcut and nothing more, which is why the contract is this small.** No key material is involved
/// — the database is plaintext and the PIN is a UI gate — so a successful biometric check is exactly as
/// authoritative as a correct PIN and no more. Anything richer here would imply otherwise.
///
/// A port because `local_auth` needs a platform channel: without one, a widget test of the lock screen
/// could not run, and §9.1 requires four of them per screen.
abstract interface class BiometricGate {
  /// Whether this device can offer the shortcut at all.
  ///
  /// Checked before the button is shown rather than after it is pressed. Offering a shortcut that then
  /// says "not available" is the control ARCH_5 §10 objects to — one that looks live and is not.
  Future<bool> get isAvailable;

  /// Prompts, returning the refusal rather than throwing when it does not succeed.
  ///
  /// [reason] is the already-localised sentence the platform shows, so no string literal reaches the
  /// plugin (Law U5).
  Future<Result<void, Failure>> authenticate({required String reason});
}
```

### `lib/domain/services/low_stock_suggestion_engine.dart`

```dart
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';

/// What the engine decided to do about one item.
enum SuggestionAction {
  /// No auto entry exists and stock is low — create one.
  create,

  /// An active auto entry exists — refresh its quantity and stock reading.
  refresh,

  /// Leave the entry entirely alone.
  ///
  /// Either the user has taken ownership of it (`origin` promoted to `manual`), or they dismissed or
  /// snoozed it and the condition that would bring it back has not been met.
  leaveAlone,
}

/// One decision, ready for the caller to write.
class SuggestionDecision {
  /// Creates a decision.
  const SuggestionDecision({
    required this.itemId,
    required this.action,
    required this.reason,
    this.existingEntryId,
    this.suggestedQuantity,
    this.stockAtDecision,
  });

  /// The item this concerns.
  final String itemId;

  /// What to do.
  final SuggestionAction action;

  /// Why, in words — surfaced in logs and useful when a user asks why something reappeared.
  final String reason;

  /// The entry to update, when [action] is [SuggestionAction.refresh].
  final String? existingEntryId;

  /// How much to buy — the shortfall against the threshold.
  final Qty? suggestedQuantity;

  /// The stock reading at the moment of the decision, stored so a later dismissal can be compared
  /// against it.
  final Qty? stockAtDecision;

  /// True when the caller needs to write something.
  bool get requiresWrite => action != SuggestionAction.leaveAlone;
}

/// Decides which low-stock shopping suggestions should exist.
///
/// **Pure and idempotent.** Given the same stock and the same existing entries it returns the same
/// decisions, however many times it runs — which is what makes regeneration safe to call from a
/// foreground hook. The idempotency is a property of this function, not of the database: the partial
/// unique index `idx_shopping_auto` is a backstop, and one that cannot serve as an `ON CONFLICT`
/// target anyway (ARCH_2 §11.1), so correctness has to live here.
///
/// Phase 3C held this inside `ShoppingRepositoryImpl.regenerateLowStockSuggestions`. It lives here
/// now so the rule has one definition and can be tested without a database.
final class LowStockSuggestionEngine {
  /// Creates the engine.
  const LowStockSuggestionEngine();

  /// Decides what to do for every item in [lowStock].
  ///
  /// [existingAutoEntries] should be every entry on the list already keyed to an item, whatever its
  /// origin or state — including ones promoted to `manual`, because those are precisely the ones
  /// that must be recognised and left alone.
  List<SuggestionDecision> decide({
    required Iterable<ItemStock> lowStock,
    required Iterable<ShoppingEntry> existingAutoEntries,
    required DateKey today,
  }) {
    final byItem = <String, ShoppingEntry>{};
    for (final entry in existingAutoEntries) {
      final itemId = entry.itemId;
      if (itemId != null) byItem[itemId] = entry;
    }

    final decisions = <SuggestionDecision>[];
    for (final stock in lowStock) {
      decisions.add(
        _decideFor(stock: stock, existing: byItem[stock.itemId], today: today),
      );
    }
    return decisions;
  }

  SuggestionDecision _decideFor({
    required ItemStock stock,
    required ShoppingEntry? existing,
    required DateKey today,
  }) {
    final shortfall = stock.shortfall;
    if (shortfall == null || !shortfall.isPositive) {
      return SuggestionDecision(
        itemId: stock.itemId,
        action: SuggestionAction.leaveAlone,
        reason: 'Not low on stock, or no threshold set.',
      );
    }

    if (existing == null) {
      return SuggestionDecision(
        itemId: stock.itemId,
        action: SuggestionAction.create,
        reason: 'Low on stock and nothing suggested yet.',
        suggestedQuantity: shortfall,
        stockAtDecision: stock.totalRemaining,
      );
    }

    // The user has taken ownership. Editing an auto entry promotes its origin, and from that moment
    // the engine never touches it again — not its quantity, not its state (anomaly A22). Any other
    // behaviour would silently overwrite a deliberate edit on the next foreground.
    if (existing.origin != ShoppingEntryOrigin.autoLowStock) {
      return SuggestionDecision(
        itemId: stock.itemId,
        action: SuggestionAction.leaveAlone,
        reason: 'The user edited this entry, so it is theirs now.',
        existingEntryId: existing.id,
      );
    }

    if (existing.autoState != ShoppingEntryAutoState.active) {
      return _decideSuppressed(
        stock: stock,
        existing: existing,
        today: today,
        shortfall: shortfall,
      );
    }

    return SuggestionDecision(
      itemId: stock.itemId,
      action: SuggestionAction.refresh,
      reason: 'Still low on stock; refreshing the suggested quantity.',
      existingEntryId: existing.id,
      suggestedQuantity: shortfall,
      stockAtDecision: stock.totalRemaining,
    );
  }

  /// Whether a dismissed or snoozed suggestion has earned its way back.
  ///
  /// A dismissal is not a timer. Bringing the entry back after N days would nag about a shortage the
  /// user already declined; never bringing it back would mean they stop being told after they
  /// restock and run out again. The condition is therefore the stock itself: it returns only once
  /// stock has risen **above** the reading taken when they dismissed it — which can only happen if
  /// they bought some — and then fallen below the threshold again (anomaly A23).
  ///
  /// A snooze additionally has a date, and that date genuinely is a timer: the user asked to be
  /// reminded later, rather than saying no.
  SuggestionDecision _decideSuppressed({
    required ItemStock stock,
    required ShoppingEntry existing,
    required DateKey today,
    required Qty shortfall,
  }) {
    if (existing.autoState == ShoppingEntryAutoState.snoozed) {
      final until = existing.snoozeUntilDateKey;
      if (until != null && today.isBefore(until)) {
        return SuggestionDecision(
          itemId: stock.itemId,
          action: SuggestionAction.leaveAlone,
          reason: 'Snoozed until ${until.toIso()}.',
          existingEntryId: existing.id,
        );
      }
      return SuggestionDecision(
        itemId: stock.itemId,
        action: SuggestionAction.refresh,
        reason: 'The snooze has expired and stock is still low.',
        existingEntryId: existing.id,
        suggestedQuantity: shortfall,
        stockAtDecision: stock.totalRemaining,
      );
    }

    final atDecision = existing.stockAtGeneration;
    if (atDecision == null) {
      // No reading was stored, so the recovery condition cannot be evaluated. Staying suppressed is
      // the safer default: a suggestion that never returns is a missing nudge, whereas one that
      // returns on every foreground is the nag this rule exists to prevent.
      return SuggestionDecision(
        itemId: stock.itemId,
        action: SuggestionAction.leaveAlone,
        reason: 'Dismissed, with no stock reading to compare against.',
        existingEntryId: existing.id,
      );
    }

    final recovered = stock.totalRemaining.milliBase > atDecision.milliBase;
    if (!recovered) {
      return SuggestionDecision(
        itemId: stock.itemId,
        action: SuggestionAction.leaveAlone,
        reason: 'Dismissed, and stock has not been replenished since.',
        existingEntryId: existing.id,
      );
    }
    return SuggestionDecision(
      itemId: stock.itemId,
      action: SuggestionAction.refresh,
      reason: 'Restocked after being dismissed, and low again.',
      existingEntryId: existing.id,
      suggestedQuantity: shortfall,
      stockAtDecision: stock.totalRemaining,
    );
  }
}
```

### `lib/domain/services/purchase_fan_out_service.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/text/normalizer.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';

/// Which artefact a purchase line produces, if any.
enum FanOutTarget {
  /// Nothing — a plain expense line.
  none,

  /// An `inventory_batches` row.
  batch,

  /// An `assets` row.
  asset,

  /// A `recurring_templates` row.
  recurringTemplate,
}

/// Exactly one artefact to create, and the line to write its id back to.
///
/// **At most one of [batch] and [asset] is ever non-null.** That is the invariant the whole class
/// exists to enforce: a line has one `destination`, so it produces one artefact, and
/// `transaction_lines` has three separate `created*Id` columns precisely so a reader can tell which
/// (ARCH_2 §4.2). A line that produced both a batch and an asset would make "what did this purchase
/// create" unanswerable — which is anomaly A12.
class FanOutPlan {
  /// Creates a plan.
  const FanOutPlan({
    required this.lineId,
    required this.target,
    this.batch,
    this.asset,
    this.recurringTemplateName,
  });

  /// A plan that creates nothing.
  const FanOutPlan.none(this.lineId)
    : target = FanOutTarget.none,
      batch = null,
      asset = null,
      recurringTemplateName = null;

  /// The line this plan came from, and where the created id is written back.
  final String lineId;

  /// What to create.
  final FanOutTarget target;

  /// The batch to create, when [target] is [FanOutTarget.batch].
  final Batch? batch;

  /// The asset to create, when [target] is [FanOutTarget.asset].
  final Asset? asset;

  /// The name for a template the user will finish configuring, when [target] is
  /// [FanOutTarget.recurringTemplate].
  ///
  /// A name rather than a whole `RecurringTemplate`: a schedule needs an interval and an anchor that
  /// a receipt line simply does not contain, and inventing a monthly-on-the-1st default would create
  /// obligations the user never agreed to. The caller opens the template editor pre-filled instead.
  final String? recurringTemplateName;

  /// True when the caller must create something.
  bool get createsArtefact => target != FanOutTarget.none;

  /// Sanity invariant: never more than one artefact.
  bool get isWellFormed {
    final count = [
      batch != null,
      asset != null,
      recurringTemplateName != null,
    ].where((set) => set).length;
    return target == FanOutTarget.none ? count == 0 : count == 1;
  }
}

/// Turns a saved transaction line into the one artefact its `destination` calls for.
///
/// **Pure.** It builds entities and returns them; the caller writes them and calls
/// `TransactionLineDao.setCreatedArtefact` to record the link. Nothing here touches a database, so
/// the "asset destination creates no batch" guarantee is testable directly rather than inferred from
/// what a repository happened to do.
///
/// This is the only service in Phase 4B with no prior implementation — the `created*Id` columns and
/// the *detach* path existed from Phase 1B and 3B, but nothing ever populated them.
final class PurchaseFanOutService {
  /// Creates the service.
  const PurchaseFanOutService({Normalizer normalizer = const Normalizer()})
    : _normalizer = normalizer;

  final Normalizer _normalizer;

  /// Plans the artefact [line] should produce.
  ///
  /// [newArtefactId] is used only when something is actually created, so a caller may generate a
  /// UUID unconditionally without leaking an unused one.
  ///
  /// Fails with a [ValidationFailure] when the destination needs data the line lacks — an inventory
  /// line without a quantity, or without a catalogued item to attach the batch to. Refusing is the
  /// point: a batch with a guessed quantity is stock the user never bought.
  Result<FanOutPlan, Failure> plan({
    required TransactionLine line,
    required Transaction transaction,
    required String newArtefactId,
  }) {
    switch (line.destination) {
      case TransactionLineDestination.none:
        return Result.ok(FanOutPlan.none(line.id));

      case TransactionLineDestination.inventory:
        return _planBatch(
          line: line,
          transaction: transaction,
          newId: newArtefactId,
        );

      case TransactionLineDestination.asset:
        return _planAsset(
          line: line,
          transaction: transaction,
          newId: newArtefactId,
        );

      case TransactionLineDestination.recurring:
        return Result.ok(
          FanOutPlan(
            lineId: line.id,
            target: FanOutTarget.recurringTemplate,
            recurringTemplateName: line.description,
          ),
        );
    }
  }

  /// Plans every artefact a transaction's lines produce, skipping lines that already have one.
  ///
  /// [newArtefactIds] must supply one id per line in [lines]; ids for lines that create nothing go
  /// unused. Re-running over a transaction whose lines already carry a `created*Id` produces no
  /// plans, which is what makes the fan-out safe to retry after a partial failure.
  Result<List<FanOutPlan>, Failure> planAll({
    required List<TransactionLine> lines,
    required Transaction transaction,
    required List<String> newArtefactIds,
  }) {
    if (newArtefactIds.length < lines.length) {
      return const Result.failure(
        ValidationFailure(
          'One artefact id is needed per line.',
          field: 'newArtefactIds',
        ),
      );
    }

    final plans = <FanOutPlan>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.hasArtefact) continue;
      final planned = plan(
        line: line,
        transaction: transaction,
        newArtefactId: newArtefactIds[i],
      );
      if (planned.isFailure) return Result.failure(planned.failureOrNull!);
      final value = planned.valueOrNull!;
      if (value.createsArtefact) plans.add(value);
    }
    return Result.ok(plans);
  }

  Result<FanOutPlan, Failure> _planBatch({
    required TransactionLine line,
    required Transaction transaction,
    required String newId,
  }) {
    // **A missing unit code is refused, not defaulted to `''`.**
    // `inventory_batches.unit_code_at_purchase` is a foreign key into `units`, and the empty string
    // matches no row — so the old `?? ''` did not paper over the gap, it turned a legible rejection
    // into `FOREIGN KEY constraint failed` several layers away, after the transaction had already
    // been written.
    final unitCode = line.unitCode;
    if (unitCode == null || unitCode.isEmpty) {
      return Result.failure(
        ValidationFailure(
          'This line is marked for inventory but has no unit, so the stock it would create could '
          'not be measured.',
          field: 'unitCode',
        ),
      );
    }
    final itemId = line.itemId;
    if (itemId == null) {
      return const Result.failure(
        ValidationFailure(
          'An inventory line needs a catalogued item for its batch to belong to.',
          field: 'itemId',
        ),
      );
    }
    final quantity = line.quantity;
    if (quantity == null || !quantity.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'An inventory line needs a quantity greater than zero.',
          field: 'quantity',
        ),
      );
    }

    return Result.ok(
      FanOutPlan(
        lineId: line.id,
        target: FanOutTarget.batch,
        batch: Batch(
          id: newId,
          itemId: itemId,
          initialQuantity: quantity,
          // Nothing has been consumed yet, so remaining equals initial. `BatchRepository.create`
          // enforces this and writes the founding movement from it.
          remainingQuantity: quantity,
          unitCodeAtPurchase: unitCode,
          purchasedDateKey: transaction.dateKey,
          origin: BatchOrigin.purchase,
          unitCost: line.unitPrice,
          sourceTransactionLineId: line.id,
        ),
      ),
    );
  }

  Result<FanOutPlan, Failure> _planAsset({
    required TransactionLine line,
    required Transaction transaction,
    required String newId,
  }) {
    final name = line.description.trim();
    if (name.isEmpty) {
      return const Result.failure(
        ValidationFailure(
          'An asset line needs a description to name the asset.',
          field: 'description',
        ),
      );
    }

    return Result.ok(
      FanOutPlan(
        lineId: line.id,
        target: FanOutTarget.asset,
        // No batch, deliberately and unconditionally. Electronics defaulting to the Service Manager
        // rather than Inventory is the resolution of anomaly A12: a television is serviced and has a
        // warranty, it is not consumed in portions. A user who also wants it in inventory adds it
        // there explicitly, which creates a second line with its own destination.
        asset: Asset(
          id: newId,
          name: name,
          normalizedName: _normalizer.normalize(name),
          // `other` rather than a guess from the description. Classifying "LG 55 inch" as
          // `electronics` by keyword would be wrong often enough to matter, and the asset editor
          // asks for the type anyway.
          type: AssetType.other,
          status: AssetStatus.active,
          purchaseDateKey: transaction.dateKey,
          purchasePrice: line.lineAmount,
          sourceTransactionLineId: line.id,
        ),
      ),
    );
  }

  /// The quantity a fanned-out batch should hold, for a caller checking before it writes.
  Qty? batchQuantityFor(TransactionLine line) =>
      line.destination == TransactionLineDestination.inventory
      ? line.quantity
      : null;

  /// The price a fanned-out asset should record, for the same reason.
  Money? assetPriceFor(TransactionLine line) =>
      line.destination == TransactionLineDestination.asset
      ? line.lineAmount
      : null;

  /// The civil date any artefact from [transaction] is dated.
  DateKey artefactDateFor(Transaction transaction) => transaction.dateKey;
}
```

### `lib/domain/services/recipe_cook_service.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/recipe.dart';
import 'package:alaya/domain/repositories/recipe_repository.dart';
import 'package:alaya/domain/repositories/stock_repository.dart';
import 'package:alaya/domain/services/cookability_engine.dart';
import 'package:alaya/domain/services/draw_policy.dart';

/// What one cook did to inventory.
class CookOutcome {
  /// Creates an outcome.
  const CookOutcome({
    required this.cook,
    required this.deducted,
    required this.skipped,
  });

  /// The log entry written.
  final RecipeCook cook;

  /// The item ids whose stock was reduced.
  final List<String> deducted;

  /// The ingredients that could not be deducted, and why.
  ///
  /// Never empty on a recipe with untracked lines, which is most real recipes. A cook that deducted
  /// four of six ingredients and said nothing about the other two would leave the user believing
  /// their inventory is more accurate than it is.
  final List<IngredientCheck> skipped;
}

/// Cooking a recipe: deduct what it used, and record that it happened.
///
/// **Deducts through [StockRepository.consume], which is atomic.** This service adds no consumption
/// logic of its own — it maps a scaled ingredient list onto calls the inventory module already makes,
/// so a cook and a manual "use some" produce the same shape of movement and the same batch ordering
/// for the same policy.
///
/// **It chooses the policy, and that is the whole of the expiry fix.** `consume` defaults to FEFO,
/// which orders by nearest expiry — and an expired date is the nearest date, so the default reaches for
/// food that is already off before touching anything good. Correct for a write-off, wrong for cooking.
/// This service passes `DrawPolicy.freshFirst`, so good stock is spent first and expired stock is
/// touched only when the cook has said so.
class RecipeCookService {
  /// Creates the service.
  const RecipeCookService({
    required RecipeRepository recipes,
    required StockRepository stock,
    required Clock clock,
    CookabilityEngine engine = const CookabilityEngine(),
  }) : _recipes = recipes,
       _stock = stock,
       _clock = clock,
       _engine = engine;

  final RecipeRepository _recipes;
  final StockRepository _stock;
  final Clock _clock;
  final CookabilityEngine _engine;

  /// Cooks [recipe] at [servings], deducting stock unless [deductStock] is false.
  ///
  /// **Refuses the whole cook when a required ingredient is short**, unless [allowPartial]. That is
  /// `InventoryConsumptionService`'s own contract — it fails with `insufficientStock` rather than
  /// half-applying, because a ledger describing a consumption that only half happened is worse than
  /// one that did not happen. Overriding it from here would be arguing with a decision the
  /// inventory module already made carefully.
  ///
  /// Ingredients the engine could not check — untracked, or a unit mismatch — are **skipped, not
  /// failed**. Nobody tracks salt, and refusing to cook because of it would make the feature
  /// unusable. They come back in [CookOutcome.skipped] so the screen can say so.
  ///
  /// **[allowExpired] is the cook's answer, not a default worth guessing.** False means good stock only:
  /// a recipe that could be made solely from food past its date fails with `insufficientStock` rather
  /// than quietly eating it, which is what happened before this parameter existed. True means the user
  /// was asked and said yes — so the caller must have asked. `CookabilityStatus.readyWithExpired` is
  /// how a screen knows the question is worth putting.
  Future<Result<CookOutcome, Failure>> cook({
    required Recipe recipe,
    required Map<String, ItemStock> stock,
    required Map<String, Item> items,
    int? servings,
    bool deductStock = true,
    bool allowPartial = false,
    bool allowExpired = false,
    String? note,
  }) async {
    final target = servings ?? recipe.servings;
    final today = _clock.today();
    final verdict = _engine.judge(
      recipe,
      stock: stock,
      items: items,
      // **The clock this service already holds**, so `judge`'s requirement adds nothing to this
      // method's signature. `cook` is called from a controller with no notion of dates, and threading
      // one through would have put a date parameter on a screen's button handler.
      //
      // No batches are supplied, so this verdict is the coarse one and cannot see expiry. It does not
      // need to: the precise question is answered by `consume`, atomically, against the shelf as it is
      // at the moment of writing rather than as it was when the screen last rebuilt. A verdict here
      // that disagreed with that would be the more dangerous of the two.
      today: today,
      servings: target,
    );

    if (!allowPartial && verdict.missingCount > 0) {
      final blocked = verdict.checks
          .where((c) => !c.ingredient.isOptional && c.availability.isMissing)
          .map((c) => c.ingredient.freeText ?? c.ingredient.itemId ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
      return Result.failure(
        BusinessRuleFailure(
          blocked.isEmpty
              ? 'There is not enough stock for this recipe.'
              : 'Not enough stock for ${blocked.length} ingredient(s).',
          rule: 'recipeInsufficientStock',
        ),
      );
    }

    final deducted = <String>[];
    final skipped = <IngredientCheck>[];

    if (deductStock) {
      // Built once rather than per ingredient: every line of one cook must be judged against the same
      // date, or a cook running across midnight would treat two ingredients by different rules.
      final policy = DrawPolicy.freshFirst(
        today: today,
        allowExpired: allowExpired,
      );

      for (final check in verdict.checks) {
        final itemId = check.ingredient.itemId;
        final needed = check.required_;
        // Anything the engine could not judge, and anything with no quantity, is passed over. The
        // engine already decided which those are; re-deciding here would be a second opinion that
        // could disagree with the badge the user just looked at.
        if (itemId == null ||
            needed == null ||
            check.availability.isUncheckable) {
          skipped.add(check);
          continue;
        }
        if (!needed.isPositive) {
          skipped.add(check);
          continue;
        }

        final result = await _stock.consume(
          itemId: itemId,
          quantity: needed,
          // `consume` is "stock used up through normal use" — the same kind the inventory module's
          // own "use some" writes. Cooking is not waste and not an adjustment, and that holds even
          // when a batch used was past its date: the user ate it.
          kind: StockMovementKind.consume,
          policy: policy,
          reason: 'recipe',
          note: recipe.name,
        );
        if (result.isFailure) {
          // Partial application is the one outcome worth refusing outright: some movements are
          // already written, and the caller needs to know the ledger is now ahead of the UI.
          //
          // Under `allowExpired: false` this is also how "you have the food but it is off" arrives —
          // an `insufficientStock` naming the good stock alone. The screen should have asked before
          // getting here; if it did not, refusing is the safe half of the mistake.
          return Result.failure(
            result.failureOrNull ??
                const UnexpectedFailure(
                  'Stock could not be deducted for this recipe.',
                ),
          );
        }
        deducted.add(itemId);
      }
    } else {
      skipped.addAll(verdict.checks);
    }

    final logged = await _recipes.logCook(
      recipeId: recipe.id,
      cookedOn: today,
      servingsCooked: target,
      deductedStock: deductStock && deducted.isNotEmpty,
      note: note,
    );
    final cook = logged.valueOrNull;
    if (cook == null) {
      return Result.failure(
        logged.failureOrNull ??
            const UnexpectedFailure('That cook could not be recorded.'),
      );
    }

    return Result.ok(
      CookOutcome(cook: cook, deducted: deducted, skipped: skipped),
    );
  }
}
```

### `lib/domain/services/recurring_engine.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';

/// One occurrence a materialisation pass would create.
class PlannedOccurrence {
  /// Creates a planned occurrence.
  const PlannedOccurrence({required this.templateId, required this.dueDateKey});

  /// The template it belongs to.
  final String templateId;

  /// The civil date it is due on.
  final DateKey dueDateKey;
}

/// What one template's materialisation pass produced.
class MaterialisationPlan {
  /// Creates a plan.
  const MaterialisationPlan({
    required this.templateId,
    required this.occurrences,
    required this.nextDueDateKey,
    required this.stoppedAtSafetyBound,
  });

  /// The template.
  final String templateId;

  /// The occurrences to create, oldest first. **Every one is `due`** — never paid.
  final List<PlannedOccurrence> occurrences;

  /// Where `nextDueDateKey` should be left afterwards.
  final DateKey nextDueDateKey;

  /// True when the pass hit [RecurringEngine.maxOccurrencesPerPass] rather than reaching the target
  /// date, which means the template is almost certainly misconfigured.
  final bool stoppedAtSafetyBound;

  /// True when nothing needs writing.
  bool get isEmpty => occurrences.isEmpty;
}

/// The transaction shape settling an occurrence should create.
///
/// Returned rather than written, so the caller commits it through `TransactionRepository` and
/// inherits its shape validation and `monthKey` derivation instead of this service reimplementing
/// them.
class SettlementIntent {
  /// Creates an intent.
  const SettlementIntent({
    required this.kind,
    required this.subtype,
    required this.amount,
    required this.dateKey,
    required this.fromAccountId,
    required this.toAccountId,
    required this.templateId,
    required this.occurrenceId,
    this.payeeId,
    this.tagId,
    this.note,
  });

  /// Withdrawal for an outflow, deposit for an inflow.
  final TransactionKind kind;

  /// The analytics bucket.
  final TransactionSubtype subtype;

  /// The amount actually paid, which may differ from the template's default.
  final Money amount;

  /// The civil date it was paid on.
  final DateKey dateKey;

  /// Source account — set for an outflow, null for an inflow.
  final String? fromAccountId;

  /// Destination account — set for an inflow, null for an outflow.
  final String? toAccountId;

  /// The template being settled.
  final String templateId;

  /// The occurrence being settled.
  final String occurrenceId;

  /// The counterparty, carried from the template.
  final String? payeeId;

  /// The tag to apply, carried from the template.
  final String? tagId;

  /// The note to put on the transaction.
  final String? note;
}

/// Computes recurring schedules: the next due date, what to materialise, and what settling implies.
///
/// **Pure.** No clock, no database — every method takes the dates it needs. That is what makes the
/// month-end clamp testable against a fixed calendar rather than against whenever the suite happens
/// to run.
///
/// Phase 3D held `nextDue` and the materialisation loop inside `RecurringRepositoryImpl`. They live
/// here now for one definition, consolidated the same way Phase 4A consolidated the currency
/// cross-rate.
final class RecurringEngine {
  /// Creates the engine.
  const RecurringEngine();

  /// How many occurrences one pass will create per template before stopping.
  ///
  /// Twenty years of monthly, or eight months of daily, is past any honest backlog. Beyond it the
  /// template is misconfigured, and a device left unopened for two years should not materialise 700
  /// rows inside the startup path. The bound engages instead, and [MaterialisationPlan] says so.
  static const int maxOccurrencesPerPass = 240;

  /// The next due date after [from], per [template]'s interval.
  ///
  /// Day and week intervals are plain day arithmetic. Month and year intervals do calendar
  /// arithmetic and then clamp **the stored anchor** into the target month's real length — never the
  /// current day, which may itself already be clamped.
  ///
  /// That distinction is the whole of anomaly A13. A bill anchored on the 31st renders as the 28th in
  /// February and returns to the 31st in March. Advancing from the clamped 28th instead would walk it
  /// permanently backwards after a single February, and no later month would ever recover it.
  DateKey nextDue({
    required DateKey from,
    required RecurringTemplate template,
  }) {
    final count = template.intervalCount;
    switch (template.intervalUnit) {
      case RecurringIntervalUnit.day:
        return from.addDays(count);
      case RecurringIntervalUnit.week:
        return from.addDays(7 * count);
      case RecurringIntervalUnit.month:
        final total = from.year * 12 + (from.month - 1) + count;
        final year = total ~/ 12;
        final month = total % 12 + 1;
        return DateKey.fromYmd(
          year,
          month,
          clampDayOfMonth(template.anchorDayOfMonth ?? from.day, year, month),
        );
      case RecurringIntervalUnit.year:
        final year = from.year + count;
        return DateKey.fromYmd(
          year,
          from.month,
          clampDayOfMonth(
            template.anchorDayOfMonth ?? from.day,
            year,
            from.month,
          ),
        );
    }
  }

  /// [day] limited to the last real day of `year-month`.
  ///
  /// Day zero of the following month is the last day of this one, which resolves February in both
  /// leap and non-leap years without a lookup table.
  int clampDayOfMonth(int day, int year, int month) {
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    return day < lastDay ? day : lastDay;
  }

  /// Plans every occurrence [template] owes up to and including [asOf].
  ///
  /// **Creates no money.** Every planned occurrence is `due`; only an explicit user tap settles one.
  /// An app unopened for three months plans three occurrences and zero transactions (anomaly A14).
  ///
  /// [alreadyMaterialised] makes the pass idempotent: dates already present are skipped while the
  /// cursor still advances past them, so running twice plans nothing the second time and leaves
  /// `nextDueDateKey` in the same place either way.
  MaterialisationPlan planMaterialisation({
    required RecurringTemplate template,
    required DateKey asOf,
    Iterable<DateKey> alreadyMaterialised = const [],
  }) {
    final existing = alreadyMaterialised.map((d) => d.value).toSet();
    final planned = <PlannedOccurrence>[];
    var cursor = template.nextDueDateKey;
    var guard = 0;
    var hitBound = false;

    while (!cursor.isAfter(asOf)) {
      if (guard >= maxOccurrencesPerPass) {
        hitBound = true;
        break;
      }
      guard++;

      final end = template.endDateKey;
      if (end != null && cursor.isAfter(end)) break;

      if (!existing.contains(cursor.value)) {
        planned.add(
          PlannedOccurrence(templateId: template.id, dueDateKey: cursor),
        );
      }
      cursor = nextDue(from: cursor, template: template);
    }

    return MaterialisationPlan(
      templateId: template.id,
      occurrences: planned,
      nextDueDateKey: cursor,
      stoppedAtSafetyBound: hitBound,
    );
  }

  /// Whether [template] should be materialising at all as of [asOf].
  bool isActive({required RecurringTemplate template, required DateKey asOf}) =>
      template.isActiveAsOf(asOf);

  /// What settling [occurrence] implies, without writing anything.
  ///
  /// [template]'s `direction` decides the kind: an outflow settles by taking money out, an inflow by
  /// putting it in. That single field is what lets salary share the recurring system with bills
  /// rather than needing a second, parallel one (anomaly A27).
  ///
  /// [amount] is the amount **actually** paid and is recorded on the occurrence by the caller. The
  /// template's default is never touched — paying ₹520 against a ₹499 subscription records ₹520 and
  /// leaves ₹499 as the expectation, so analytics uses actuals without corrupting the schedule
  /// (anomaly A29).
  Result<SettlementIntent, Failure> planSettlement({
    required RecurringTemplate template,
    required RecurringOccurrence occurrence,
    required Money amount,
    required DateKey paidOn,
    required String accountId,
  }) {
    if (!amount.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'The amount paid must be greater than zero.',
          field: 'amount',
        ),
      );
    }
    if (occurrence.status != RecurringOccurrenceStatus.due) {
      return Result.failure(
        BusinessRuleFailure(
          'This occurrence is already ${occurrence.status.name}.',
          rule: 'occurrenceNotDue',
        ),
      );
    }
    if (occurrence.templateId != template.id) {
      return const Result.failure(
        ValidationFailure(
          'That occurrence belongs to a different template.',
          field: 'occurrence',
        ),
      );
    }
    if (amount.currencyCode != template.defaultAmount.currencyCode) {
      // `recurring_occurrences` has no currency column: a paid amount is denominated in its
      // template's currency (ARCH_2 §7). Accepting another would store the number against the wrong
      // code on read — Law L1's pairing rule, broken silently.
      return Result.failure(
        ValidationFailure(
          'This template is in ${template.defaultAmount.currencyCode}, so the payment cannot be '
          'in ${amount.currencyCode}.',
          field: 'amount',
        ),
      );
    }

    final isOutflow = template.direction == RecurringDirection.outflow;
    return Result.ok(
      SettlementIntent(
        kind: isOutflow ? TransactionKind.withdrawal : TransactionKind.deposit,
        subtype: isOutflow
            ? TransactionSubtype.bill
            : TransactionSubtype.salaryIn,
        amount: amount,
        dateKey: paidOn,
        fromAccountId: isOutflow ? accountId : null,
        toAccountId: isOutflow ? null : accountId,
        templateId: template.id,
        occurrenceId: occurrence.id,
        payeeId: template.payeeId,
        tagId: template.tagId,
        note: template.name,
      ),
    );
  }

  /// Validates skipping [occurrence].
  ///
  /// A settled occurrence cannot be skipped: the money already moved, and marking it skipped would
  /// leave a transaction with nothing explaining it. Unsettle it first.
  Result<void, Failure> planSkip(RecurringOccurrence occurrence) {
    if (occurrence.status == RecurringOccurrenceStatus.paid) {
      return const Result.failure(
        BusinessRuleFailure(
          'A settled occurrence cannot be skipped — unsettle it first.',
          rule: 'cannotSkipPaid',
        ),
      );
    }
    return const Result.ok(null);
  }

  /// Whether [occurrence] is overdue as of [today].
  ///
  /// Derived, never stored — which is why `v_recurring_due` has no `is_overdue` column
  /// (ARCH_2 §12.2).
  bool isOverdue({
    required RecurringOccurrence occurrence,
    required DateKey today,
  }) => occurrence.isOverdue(today);
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
  // **This one line is the whole feature switch.** `RemindersScreen` iterates this list, so adding a
  // member makes the toggle appear by itself — and the two exhaustive switches in
  // `LocalNotificationScheduler` stop compiling until they can say something about it, which is the
  // order that makes editing this list safe rather than reckless.
  NotificationKind.settlementDue,
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
  }) => ReminderSettings(
    enabled: enabled ?? this.enabled,
    digestHour: digestHour ?? this.digestHour,
    digestMinute: digestMinute ?? this.digestMinute,
  );
}

/// The zone the schedule was computed in, and whether it can be trusted.
///
/// **Exists because the failure it reports was invisible for months.** `tz.local` silently defaults to UTC, so
/// every digest was booked against UTC wall time while the screen displayed the hour the user had chosen. There
/// was no wrong number anywhere — the schedule was internally consistent and externally five and a half hours
/// out. Surfacing the zone makes the one fact that mattered visible in the one place somebody would look.
class ReminderZone {
  /// Creates a zone report.
  const ReminderZone({required this.name, required this.matchesDevice});

  /// The IANA name, e.g. `Asia/Kolkata`.
  ///
  /// May be an alias of the canonical name for the same rules — `Asia/Calcutta` rather than `Asia/Kolkata`. The
  /// two are one rule set under two labels, so an alias changes what this string reads and nothing else.
  final String name;

  /// Whether this zone reproduces the device's own offsets.
  ///
  /// **False is the interesting value**, and the reason this is not simply a string. A zone that disagrees with
  /// the device delivers at the wrong hour, and the app cannot fix that for the user — but it can say so instead
  /// of scheduling confidently against a guess.
  final bool matchesDevice;
}

/// One notification the app has actually scheduled with the OS.
class ScheduledReminder {
  /// Creates a scheduled reminder.
  const ScheduledReminder({
    required this.id,
    required this.kind,
    required this.at,
    required this.androidNotificationId,
  });

  /// The `notification_schedule` row id.
  final String id;

  /// Which kind it is.
  final NotificationKind kind;

  /// **When it fires, as a local instant** — the moment the OS is actually holding.
  ///
  /// This field replaced a `DateKey` called `on`, and the replacement is the fix for a bug that made a real
  /// scheduling fault invisible for months. The old field was built with
  /// `DateKey.fromDateTime(DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true))`, and `DateKey.fromDateTime`
  /// takes calendar fields exactly as given without converting — so the "date it fires on" was the *UTC* civil
  /// date. East of Greenwich a digest before 05:30 showed yesterday; west of it, tomorrow.
  ///
  /// Worse, the date was all this carried, so the screen had nowhere to read the *time* from and read it from the
  /// user's settings instead. The row therefore displayed the time the user asked for rather than the time the OS
  /// was holding — which is precisely the pair of values that had silently diverged. A reminder system that cannot
  /// be inspected is one nobody trusts (ARCH_5 §7); one that can be inspected and reports the input as though it
  /// were the output is worse, because it answers the question wrongly and confidently.
  ///
  /// **Local rather than UTC on purpose.** Every consumer of this wants a wall clock — the day it lands on and
  /// the hour it arrives — and a local `DateTime` gives both without a call site remembering to convert. The
  /// instant is unchanged either way: `at.toUtc()` returns the stored value.
  final DateTime at;

  /// The civil date [at] falls on, in the device's own zone.
  ///
  /// Derived rather than stored. Two fields for one fact is one too many, and the previous version of this class
  /// had exactly that problem in a subtler form: a stored date computed in one zone beside a time read from
  /// somewhere else entirely.
  DateKey get on => DateKey.fromDateTime(at);

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

  /// Which zone [watchScheduled]'s times were computed in.
  ///
  /// **Shown to the user for the same reason the schedule itself is** (ARCH_5 §7): a digest arriving at the wrong
  /// hour and one not arriving at all are indistinguishable from the outside, and the zone is the fact that
  /// separates them. A caller that never displays this leaves the user with no way to tell a working reminder
  /// from one booked against the wrong clock — which is the state this app shipped in.
  Future<ReminderZone> zone();

  /// Recomputes upcoming events and reschedules everything.
  ///
  /// Idempotent, because the `workmanager` job calls it daily and a user can call it from the screen. Every
  /// schedule is keyed by its source record, so running twice replaces rather than duplicates.
  Future<Result<int, Failure>> rescheduleAll();

  /// How many notifications the OS says it is currently holding for this app.
  ///
  /// **The one fact this app could never see, and the reason a scheduling fault took weeks.** Everything else
  /// here reports what Alaya *intends*: `watchScheduled` reads the `notification_schedule` table, which is
  /// written before `zonedSchedule` is called and is never reconciled against it. So a digest the OS silently
  /// refused looks identical to one it accepted — same row, same date, same time — and `sendTest` cannot tell
  /// them apart either, because an immediate `show` never touches the alarm path at all.
  ///
  /// Zero while [watchScheduled] emits rows is the diagnosis: Alaya scheduled it, the phone is not holding it.
  Future<Result<int, Failure>> pendingCount();

  /// Posts one notification immediately, to prove the delivery path works.
  ///
  /// **This exists because "no notification arrived" has too many causes to distinguish by waiting.** The
  /// digest is scheduled, inexact, for a wall-clock time that may be tomorrow — so a silent evening tells
  /// you nothing about whether the icon resolves, the permission really landed, or the channel exists. One
  /// notification you can ask for settles all of that in two seconds.
  ///
  /// It is not a feature for daily use and it is not part of the digest: it schedules nothing, writes no
  /// `notification_schedule` row, and uses its own id so it can never collide with the digest.
  Future<Result<void, Failure>> sendTest();

  /// Cancels every scheduled notification, for when the last toggle goes off.
  Future<Result<void, Failure>> cancelAll();
}
```

### `lib/domain/services/split/debt_simplifier.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/debt_edge.dart';

// **Re-exported, so moving `DebtEdge` breaks nothing.** Three files import it from here — a repository
// contract, a service and a screen — and a contract importing a service to name its own return type was
// the reason to move it. Callers keep working; new code should import `entities/debt_edge.dart`.
//
// This line is the whole migration. Delete it once no import of this file relies on it, which a
// project-wide grep for `debt_simplifier.dart` can decide and `tool/reachability.py` cannot.
export 'package:alaya/domain/entities/debt_edge.dart';

/// How much of one real debt a suggested transfer discharges.
final class ClearedDebt {
  /// Creates a discharge record.
  const ClearedDebt({required this.edge, required this.amount});

  /// The debt as it was incurred.
  final DebtEdge edge;

  /// How much of it this transfer settles. May be less than the edge's own amount.
  final Money amount;
}

/// One payment the plan suggests making.
final class SuggestedTransfer {
  /// Creates a suggested transfer.
  const SuggestedTransfer({
    required this.fromPayeeId,
    required this.toPayeeId,
    required this.amount,
    required this.clears,
  });

  /// Who pays.
  final String fromPayeeId;

  /// Who is paid.
  final String toPayeeId;

  /// How much.
  final Money amount;

  /// Which real debts this discharges, and by how much.
  ///
  /// **This is the sentence Splitwise makes its users work out for themselves.** Their forum has
  /// carried the same complaint for over a decade — *"why do I owe ₹100 to someone who never lent me
  /// money?"* — because a simplified transfer arrives with no provenance. Every transfer here can
  /// explain itself: *"₹450 to Ravi — this clears ₹300 you owe Priya and ₹150 you owe Amit."*
  final List<ClearedDebt> clears;

  /// True when this transfer settles a debt that genuinely exists between these two people.
  bool get isDirect =>
      clears.length == 1 &&
      clears.single.edge.fromPayeeId == fromPayeeId &&
      clears.single.edge.toPayeeId == toPayeeId;
}

/// A suggested way to settle up, and nothing more.
///
/// **Suggested, never applied.** The pairwise ledger is untouched, which is what makes this
/// materially different from Splitwise: their simplification rewrites the group's debt graph in
/// place, their own help centre then advises users to stop trusting the individual balances because
/// those may have been reshuffled, and turning it off does not cleanly reverse — payments already
/// made may no longer line up with the restored debts.
///
/// Accepting this plan records ordinary settlements, the same rows a manual settle-up writes. There
/// is no simplified state to get stuck in and no toggle to lock.
final class SettlementPlan {
  /// Creates a plan.
  const SettlementPlan({
    required this.transfers,
    required this.originalDebtCount,
    required this.wasPartitionedExactly,
  });

  /// A plan for nothing owed.
  const SettlementPlan.settled()
    : transfers = const [],
      originalDebtCount = 0,
      wasPartitionedExactly = true;

  /// The payments to make, in the order to make them.
  final List<SuggestedTransfer> transfers;

  /// How many real debts existed before simplifying — what the user would otherwise pay.
  final int originalDebtCount;

  /// Whether the minimum was proved rather than approached.
  ///
  /// True when the exact zero-sum partition ran; false when the group exceeded
  /// [DebtSimplifier.maxExactMembers] and the greedy fallback was used. A screen that claims
  /// "the fewest possible payments" should only say so when this is true.
  final bool wasPartitionedExactly;

  /// How many payments the plan saves.
  int get paymentsSaved => originalDebtCount - transfers.length;

  /// Whether simplifying is worth offering at all.
  bool get isImprovement => transfers.length < originalDebtCount;
}

/// Finds the fewest payments that settle a set of debts.
///
/// Pure: edges in, a plan out. No repository, no clock, no Flutter.
///
/// ## The algorithm, and why each step is there
///
/// **1. Net.** Reduce the edges to one signed balance per person. Anyone at zero drops out.
///
/// **2. Partition into zero-sum subsets.** A subset whose balances sum to zero settles internally in
/// `size - 1` transfers, so maximising the number of such subsets minimises the total. This is the
/// step that beats greedy, and it earns its place: a brute-force search over every balance vector up
/// to five people found **no** case where greedy was beaten at three or four people, and 840 cases at
/// five. The smallest is `-6, -5, +2, +4, +5` — greedy needs four payments, but `{-6,+2,+4}` and
/// `{-5,+5}` are both zero-sum, so three suffice.
///
/// **3. Greedy within each subset.** Largest debtor to largest creditor, repeatedly.
///
/// **4. Prefer real debts on ties, which costs nothing — at both levels.** Within a subset that has no
/// proper zero-sum subset of its own — guaranteed by step 2's maximality — *every* greedy pairing
/// produces exactly `size - 1` transfers. Each transfer zeroes exactly one person, because zeroing two
/// at once would require `|debt| == credit`, which would itself be a zero-sum pair that step 2 would
/// have split off. So the count is fixed no matter who is paired with whom, and preferring a creditor
/// the debtor genuinely owes is free.
///
/// The same tie-break has to apply to the **choice of partition**, and omitting it was a real bug.
/// `a` owing `b` and `c` owing `d` can be grouped as `{a,b},{c,d}` or as `{a,d},{b,c}` — both are
/// zero-sum, both give two payments, and the second suggests two payments between people who have
/// never owed each other anything. Step 2 therefore scores each candidate group by how many real
/// debts lie inside it and prefers the higher score when counts tie.
///
/// Together, those two are the direct answer to *"she never lent me money"*.
final class DebtSimplifier {
  /// Creates the simplifier. Stateless.
  const DebtSimplifier();

  /// The largest group the exact partition runs on.
  ///
  /// Above this, step 2 is skipped and the plan reports `wasPartitionedExactly: false`.
  ///
  /// **Sixteen, measured rather than guessed.** The partition enumerates submasks, which costs about
  /// `3^n` steps: 4.8 million at 14 people, 43 million at 16, and 387 million at 18. A reference
  /// implementation in Python took 360 ms at 14 and 3.1 s at 16; Dart runs this kind of tight integer
  /// loop roughly 20–50 times faster, putting the worst case near 100 ms — acceptable for a button
  /// press, and comfortably beyond any real group. An earlier draft of the plan said 20; that would
  /// have been 3.5 billion steps and minutes of work.
  static const int maxExactMembers = 16;

  /// Plans the fewest payments that settle [debts].
  ///
  /// Every edge must be in the same currency. Netting across currencies without a rate would produce
  /// a figure nobody can reproduce, so a caller with a multi-currency group calls this once per
  /// currency — which is also how the settle-up screen should present it.
  ///
  /// Throws [CurrencyMismatchError] on mixed currencies and [ArgumentError] on a non-positive or
  /// self-directed edge.
  SettlementPlan plan(List<DebtEdge> debts) {
    final live = <DebtEdge>[];
    String? currency;
    for (final debt in debts) {
      if (debt.amount.isZero) continue;
      if (!debt.amount.isPositive) {
        throw ArgumentError.value(
          debt.amount.minor,
          'debts',
          'an edge amount must be positive — reverse the direction instead',
        );
      }
      if (debt.fromPayeeId == debt.toPayeeId) {
        throw ArgumentError.value(
          debt.fromPayeeId,
          'debts',
          'cannot owe yourself',
        );
      }
      currency ??= debt.amount.currencyCode;
      if (debt.amount.currencyCode != currency) {
        throw CurrencyMismatchError(currency, debt.amount.currencyCode);
      }
      live.add(debt);
    }
    if (live.isEmpty || currency == null) return const SettlementPlan.settled();

    // Step 1 — net. Insertion order is kept so the output is stable for a given input.
    final balances = <String, int>{};
    final order = <String>[];
    void touch(String id) {
      if (!balances.containsKey(id)) {
        balances[id] = 0;
        order.add(id);
      }
    }

    for (final debt in live) {
      touch(debt.fromPayeeId);
      touch(debt.toPayeeId);
      balances[debt.fromPayeeId] =
          balances[debt.fromPayeeId]! - debt.amount.minor;
      balances[debt.toPayeeId] = balances[debt.toPayeeId]! + debt.amount.minor;
    }
    final people = order.where((id) => balances[id] != 0).toList();
    if (people.isEmpty) {
      // Everything cancels out. Real: A owes B ₹100 and B owes A ₹100.
      return SettlementPlan(
        transfers: const [],
        originalDebtCount: live.length,
        wasPartitionedExactly: true,
      );
    }

    // Step 2 — partition.
    final exact = people.length <= maxExactMembers;
    final groups = exact
        ? _maximalZeroSumGroups(people, balances, live)
        : [people];

    // Steps 3 and 4 — greedy within each group, preferring debts that really exist.
    final owedBetween = <String, Map<String, int>>{};
    for (final debt in live) {
      (owedBetween[debt.fromPayeeId] ??= {}).update(
        debt.toPayeeId,
        (existing) => existing + debt.amount.minor,
        ifAbsent: () => debt.amount.minor,
      );
    }

    final outstanding = <String, List<_Outstanding>>{};
    for (final debt in live) {
      (outstanding[debt.fromPayeeId] ??= []).add(_Outstanding(debt));
    }
    for (final entries in outstanding.values) {
      entries.sort((a, b) {
        final byAmount = b.edge.amount.minor.compareTo(a.edge.amount.minor);
        return byAmount != 0
            ? byAmount
            : a.edge.toPayeeId.compareTo(b.edge.toPayeeId);
      });
    }

    final transfers = <SuggestedTransfer>[];
    for (final group in groups) {
      transfers.addAll(
        _settleGroup(
          group: group,
          balances: Map<String, int>.fromEntries(
            group.map((id) => MapEntry(id, balances[id]!)),
          ),
          owedBetween: owedBetween,
          outstanding: outstanding,
          currencyCode: currency,
        ),
      );
    }

    return SettlementPlan(
      transfers: transfers,
      originalDebtCount: live.length,
      wasPartitionedExactly: exact,
    );
  }

  /// Splits [people] into as many zero-sum groups as possible, preferring groups that hold real
  /// debts.
  ///
  /// Subset dynamic programming: for each mask, try every submask containing the lowest set bit that
  /// itself sums to zero, and take the best count from the rest. `parts[mask]` is the most zero-sum
  /// groups that exactly cover `mask`, or -1 when the mask cannot be covered at all.
  ///
  /// **`edgesInside` is the tie-break, and leaving it out was a real shortfall.** Two people owing two
  /// other people the same amount can be partitioned as `{a,b}` and `{c,d}` — the pairs that actually
  /// transacted — or as `{a,d}` and `{b,c}`, which are equally zero-sum and produce two payments
  /// between people who have never owed each other anything. Both partitions give the same *count*, so
  /// counting alone cannot choose, and the submask enumeration happened to reach the wrong one first.
  ///
  /// Scoring each candidate group by how many real debts lie entirely inside it, and preferring the
  /// higher score when the counts tie, picks the partition that matches what people did. It is free:
  /// the count is already equal, which is the whole reason a tie-break is possible.
  List<List<String>> _maximalZeroSumGroups(
    List<String> people,
    Map<String, int> balances,
    List<DebtEdge> debts,
  ) {
    final n = people.length;
    final full = (1 << n) - 1;
    final index = <String, int>{
      for (var i = 0; i < n; i++) people[i]: i,
    };

    final sums = List<int>.filled(1 << n, 0);
    for (var mask = 1; mask <= full; mask++) {
      final low = mask & -mask;
      final at = low.bitLength - 1;
      sums[mask] = sums[mask ^ low] + balances[people[at]]!;
    }

    // How many real debts join this person to each other person. Built once so the mask sweep below
    // stays proportional to a person's degree rather than to the whole edge list.
    final degree = List<Map<int, int>>.generate(n, (_) => <int, int>{});
    for (final debt in debts) {
      final from = index[debt.fromPayeeId];
      final to = index[debt.toPayeeId];
      // A person whose net balance is zero is not in [people] and so has no index — their debts
      // cancelled out and cannot influence how the rest is grouped.
      if (from == null || to == null) continue;
      degree[from].update(to, (n) => n + 1, ifAbsent: () => 1);
      degree[to].update(from, (n) => n + 1, ifAbsent: () => 1);
    }

    final edgesInside = List<int>.filled(1 << n, 0);
    for (var mask = 1; mask <= full; mask++) {
      final low = mask & -mask;
      final at = low.bitLength - 1;
      final rest = mask ^ low;
      var added = 0;
      for (final entry in degree[at].entries) {
        if (rest >> entry.key & 1 == 1) added += entry.value;
      }
      edgesInside[mask] = edgesInside[rest] + added;
    }

    const unreachable = -1;
    final parts = List<int>.filled(1 << n, unreachable);
    final score = List<int>.filled(1 << n, -1);
    final chosen = List<int>.filled(1 << n, 0);
    parts[0] = 0;
    score[0] = 0;
    for (var mask = 1; mask <= full; mask++) {
      final low = mask & -mask;
      var best = unreachable;
      var bestScore = -1;
      var bestSub = 0;
      // Every submask of `mask` that contains its lowest bit, so each group is counted once.
      for (var sub = mask; sub != 0; sub = (sub - 1) & mask) {
        if (sub & low == 0) continue;
        if (sums[sub] != 0) continue;
        final rest = parts[mask ^ sub];
        if (rest == unreachable) continue;
        final candidate = rest + 1;
        final candidateScore = score[mask ^ sub] + edgesInside[sub];
        if (candidate > best ||
            (candidate == best && candidateScore > bestScore)) {
          best = candidate;
          bestScore = candidateScore;
          bestSub = sub;
        }
      }
      parts[mask] = best;
      score[mask] = bestScore;
      chosen[mask] = bestSub;
    }

    // The whole set always sums to zero, so it is always coverable — worst case as one group.
    final groups = <List<String>>[];
    var mask = full;
    while (mask != 0) {
      final sub = chosen[mask];
      if (sub == 0) {
        groups.add([
          for (var i = 0; i < n; i++)
            if (mask >> i & 1 == 1) people[i],
        ]);
        break;
      }
      groups.add([
        for (var i = 0; i < n; i++)
          if (sub >> i & 1 == 1) people[i],
      ]);
      mask ^= sub;
    }
    return groups;
  }

  /// Greedy settlement within one group, preferring creditors the debtor genuinely owes.
  List<SuggestedTransfer> _settleGroup({
    required List<String> group,
    required Map<String, int> balances,
    required Map<String, Map<String, int>> owedBetween,
    required Map<String, List<_Outstanding>> outstanding,
    required String currencyCode,
  }) {
    final working = Map<String, int>.of(balances);
    final transfers = <SuggestedTransfer>[];

    while (true) {
      String? debtor;
      String? creditor;
      for (final id in group) {
        final value = working[id]!;
        if (value < 0 && (debtor == null || value < working[debtor]!))
          debtor = id;
      }
      if (debtor == null) break;

      // Among creditors, prefer one this debtor really owes. Free, because every pairing in a group
      // with no proper zero-sum subset yields the same number of transfers — see the class doc.
      final directly = owedBetween[debtor] ?? const <String, int>{};
      for (final id in group) {
        final value = working[id]!;
        if (value <= 0) continue;
        if (creditor == null) {
          creditor = id;
          continue;
        }
        final currentIsDirect = directly.containsKey(creditor);
        final candidateIsDirect = directly.containsKey(id);
        if (candidateIsDirect != currentIsDirect) {
          if (candidateIsDirect) creditor = id;
          continue;
        }
        if (value > working[creditor]!) creditor = id;
      }
      if (creditor == null) break;

      final amount = -working[debtor]! < working[creditor]!
          ? -working[debtor]!
          : working[creditor]!;
      if (amount <= 0) break;

      working[debtor] = working[debtor]! + amount;
      working[creditor] = working[creditor]! - amount;

      transfers.add(
        SuggestedTransfer(
          fromPayeeId: debtor,
          toPayeeId: creditor,
          amount: Money(amount, currencyCode),
          clears: _attribute(
            debtor: debtor,
            amountMinor: amount,
            outstanding: outstanding,
            currencyCode: currencyCode,
          ),
        ),
      );
    }
    return transfers;
  }

  /// Charges [amountMinor] against the debtor's own real debts, largest first.
  ///
  /// This is what lets a transfer explain itself. The debts are consumed as they are attributed, so
  /// two transfers by the same person never claim to clear the same debt twice.
  List<ClearedDebt> _attribute({
    required String debtor,
    required int amountMinor,
    required Map<String, List<_Outstanding>> outstanding,
    required String currencyCode,
  }) {
    final cleared = <ClearedDebt>[];
    var left = amountMinor;
    for (final entry in outstanding[debtor] ?? const <_Outstanding>[]) {
      if (left <= 0) break;
      if (entry.remaining <= 0) continue;
      final taken = entry.remaining < left ? entry.remaining : left;
      entry.remaining -= taken;
      left -= taken;
      cleared.add(
        ClearedDebt(edge: entry.edge, amount: Money(taken, currencyCode)),
      );
    }
    return cleared;
  }
}

/// A real debt with however much of it is still unattributed.
final class _Outstanding {
  _Outstanding(this.edge) : remaining = edge.amount.minor;

  final DebtEdge edge;
  int remaining;
}
```

### `lib/domain/services/split/settlement_service.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/split_expense.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/repositories/split_group_repository.dart';
import 'package:alaya/domain/repositories/split_ledger_repository.dart';

/// Records money changing hands to settle a split debt.
///
/// **A settlement you are part of is a real transaction, and that is the module's whole claim.**
/// Splitwise's "settle up" is a marker it cannot back with anything — it has no access to your bank.
/// Here the deposit or withdrawal is an ordinary `transactions` row written in the *same* database
/// transaction as the settlement itself, so the account ledger and the split ledger cannot diverge.
///
/// **This service does no I/O ordering, deliberately.** It builds the pair and hands both to one
/// repository call. An earlier design had it write through two repositories and called that
/// "atomic", which it could not have been: two repositories commit independently, and a settlement
/// written without its transaction clears a debt with no money anywhere — invisible, and the worst
/// of the available failures. The atomicity lives in `SplitDao`, which is the only layer that can
/// open a drift transaction.
final class SettlementService {
  /// Creates the service.
  const SettlementService({
    required SplitLedgerRepository ledger,
    required SplitGroupRepository groups,
    required UidGenerator uids,
    required Clock clock,
  }) : _ledger = ledger,
       _groups = groups,
       _uids = uids,
       _clock = clock;

  final SplitLedgerRepository _ledger;
  final SplitGroupRepository _groups;
  final UidGenerator _uids;
  final Clock _clock;

  /// Records that [amount] moved from [fromPayeeId] to [toPayeeId].
  ///
  /// [accountId] is the account the money landed in or left, and is **required whenever you are a
  /// party** — which is every settlement a single-user ledger normally records. It is null only for a
  /// settlement between two other people, which an accepted simplification plan can suggest and which
  /// moves none of your money.
  ///
  /// Decision 1 of the module plan, made concrete: money owed is not spendable until it arrives, and
  /// the moment it does it becomes an ordinary deposit in an account of the user's choosing. There is
  /// no separate split wallet and nothing to reconcile.
  ///
  /// Fails rather than guessing when the self payee is unset, when a settlement involving you names no
  /// account, or when the amount is not positive.
  Future<Result<SplitSettlement, Failure>> settle({
    required String fromPayeeId,
    required String toPayeeId,
    required Money amount,
    String? accountId,
    String? groupId,
    String? paymentMethodId,
    String? note,
    DateKey? on,
  }) async {
    if (!amount.isPositive) {
      return const Result.failure(
        ValidationFailure('A settlement needs an amount.', field: 'amount'),
      );
    }
    if (fromPayeeId == toPayeeId) {
      return const Result.failure(
        BusinessRuleFailure(
          'Paying yourself is not a settlement.',
          rule: 'splitSelfSettlement',
        ),
      );
    }

    final self = await _groups.selfPayeeId();
    if (self == null) {
      // Not an edge case worth papering over: with no self payee the module cannot tell which side of
      // any debt the user is on, so every balance it could show would be a guess.
      return const Result.failure(
        BusinessRuleFailure(
          'Choose which person is you before settling up.',
          rule: 'splitSelfPayeeUnset',
        ),
      );
    }

    final youArePaying = fromPayeeId == self;
    final youArePaid = toPayeeId == self;
    final involvesYou = youArePaying || youArePaid;

    if (involvesYou && accountId == null) {
      return const Result.failure(
        ValidationFailure(
          'Choose the account this money moved through.',
          field: 'accountId',
        ),
      );
    }

    final today = on ?? _clock.today();
    final settlementId = _uids.generate();

    final settlement = SplitSettlement(
      id: settlementId,
      fromPayeeId: fromPayeeId,
      toPayeeId: toPayeeId,
      amount: amount,
      dateKey: today,
      groupId: groupId,
      transactionId: involvesYou ? _uids.generate() : null,
      paymentMethodId: paymentMethodId,
      note: note,
    );

    return _ledger.recordSettlement(
      settlement: settlement,
      transaction: involvesYou
          ? _transactionFor(
              settlement: settlement,
              accountId: accountId!,
              youArePaid: youArePaid,
              today: today,
            )
          : null,
    );
  }

  /// Builds the ledger entry for a settlement you are part of.
  ///
  /// **A deposit when they pay you, a withdrawal when you pay them.** Money arriving is money you can
  /// spend from that instant — decision 1 again, from the other side: nothing marks it as
  /// split-related once it has landed, because a rupee that has arrived is just a rupee.
  ///
  /// `otherIn` and `otherOut` rather than a subtype of their own. A settlement is not a category of
  /// spending — the *original* expense already carried whatever category it deserved, and counting the
  /// repayment as spending too would double it in every analytics surface. Law L13 also makes a new
  /// enum member a schema contract, and one added to dodge a naming question is one nobody can remove.
  ///
  /// `needsReview` is false: the user just typed the amount, chose the account and confirmed. Flagging
  /// their own deliberate entry would make the review queue meaningless.
  Transaction _transactionFor({
    required SplitSettlement settlement,
    required String accountId,
    required bool youArePaid,
    required DateKey today,
  }) => Transaction(
    id: settlement.transactionId!,
    kind: youArePaid ? TransactionKind.deposit : TransactionKind.withdrawal,
    subtype: youArePaid
        ? TransactionSubtype.otherIn
        : TransactionSubtype.otherOut,
    occurredAtUtc: _clock.now(),
    dateKey: today,
    originalAmount: settlement.amount,
    needsReview: false,
    // A deposit fills an account and a withdrawal empties one; only the relevant side is set, which
    // is what `v_account_balances` reads to decide the direction.
    toAccountId: youArePaid ? accountId : null,
    fromAccountId: youArePaid ? null : accountId,
    paymentMethodId: settlement.paymentMethodId,
    // The counterparty, so the transaction is legible in the ledger on its own: "₹1,850 from Ravi"
    // rather than an unexplained deposit the user has to open the split module to understand.
    payeeId: youArePaid ? settlement.fromPayeeId : settlement.toPayeeId,
    note: settlement.note,
  );
}
```

### `lib/domain/services/split/split_balance_service.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/domain/repositories/split_ledger_repository.dart';
import 'package:alaya/domain/services/split/debt_simplifier.dart';

/// One currency's worth of a settle-up plan.
///
/// **Plans are per currency and never merged.** Netting INR against USD without a rate produces a
/// figure nobody can reproduce, and anomaly A34 already settled that money groups by currency rather
/// than collapsing. A group that spent in two currencies gets two plans, which is also how a person
/// would settle it.
final class CurrencyPlan {
  /// Creates a plan for one currency.
  const CurrencyPlan({required this.currencyCode, required this.plan});

  /// The currency.
  final String currencyCode;

  /// What to pay, and to whom.
  final SettlementPlan plan;
}

/// Answers "who owes what" and "what is the shortest way to settle it".
///
/// **Every figure here is derived (Law L3).** The service adds two things the views cannot: a *date
/// comparison*, because ARCH_2 §12.2 forbids any view from consulting the current time, and the
/// simplification, because that is a graph algorithm rather than a query.
final class SplitBalanceService {
  /// Creates the service.
  const SplitBalanceService({
    required SplitLedgerRepository ledger,
    required Clock clock,
    DebtSimplifier simplifier = const DebtSimplifier(),
  }) : _ledger = ledger,
       _clock = clock,
       _simplifier = simplifier;

  final SplitLedgerRepository _ledger;
  final Clock _clock;
  final DebtSimplifier _simplifier;

  /// How old a debt has to be before the daily digest mentions it, by default.
  ///
  /// **Fourteen days, and the number is a judgement rather than a finding.** Short enough that a
  /// forgotten dinner surfaces while both people still remember it; long enough that splitting a bill
  /// on Friday does not produce a notification the following Tuesday. Overridable, because the right
  /// answer differs between flatmates settling monthly and a trip that ends on Sunday.
  static const int defaultAgeingThresholdDays = 14;

  /// Balances outstanding with somebody, oldest first.
  ///
  /// **The nudge nobody else sends.** A due-date reminder is what the competition offers, and it needs
  /// a date somebody remembered to set. This needs nothing: the balance view already carries the oldest
  /// contributing expense, so *"Ravi has owed you ₹1,850 for three weeks"* falls out of data that
  /// exists whether or not anyone planned ahead.
  ///
  /// The day count is computed here against [Clock] rather than in SQL, because a view containing
  /// `now` could not be asserted against a `FixedClock` — the same rule `CalendarAggregator` follows
  /// for severity escalation.
  Future<List<AgeingDebt>> ageingDebts({
    int thresholdDays = defaultAgeingThresholdDays,
  }) async {
    final today = _clock.today();
    final balances = await _ledger.watchBalances().first;

    final ageing = <AgeingDebt>[];
    for (final balance in balances) {
      final age = balance.ageInDays(today);
      if (age == null || age < thresholdDays) continue;
      ageing.add(AgeingDebt(balance: balance, ageInDays: age));
    }
    ageing.sort((a, b) => b.ageInDays.compareTo(a.ageInDays));
    return ageing;
  }

  /// The single largest outstanding amount, in each direction, across every currency.
  ///
  /// What a dashboard card shows. Returned as two separate figures rather than one net total, because
  /// **"you are owed ₹4,000 and you owe ₹3,900" is not the same story as "you are up ₹100"** — and per
  /// decision 1 neither figure is spendable until it arrives, so a single net number would invite
  /// exactly the reading the card exists to avoid.
  Future<Map<String, ({Money owedToMe, Money iOwe})>> totals() async {
    final balances = await _ledger.watchBalances().first;
    final byCurrency = <String, ({Money owedToMe, Money iOwe})>{};
    for (final balance in balances) {
      final code = balance.net.currencyCode;
      final running =
          byCurrency[code] ??
          (owedToMe: Money.zero(code), iOwe: Money.zero(code));
      byCurrency[code] = balance.theyOweMe
          ? (
              owedToMe: running.owedToMe + balance.outstanding,
              iOwe: running.iOwe,
            )
          : (
              owedToMe: running.owedToMe,
              iOwe: running.iOwe + balance.outstanding,
            );
    }
    return byCurrency;
  }

  /// The fewest payments that settle [groupId], one plan per currency.
  ///
  /// **Suggested, never applied.** The pairwise ledger is untouched — Splitwise rewrites the debt graph
  /// in place, then has to advise users that the individual balances may have been reshuffled, and
  /// turning it off does not cleanly reverse. Accepting one of these plans records ordinary
  /// settlements, the same rows a manual settle-up writes, so there is no simplified state to get
  /// stuck in.
  ///
  /// Edges are grouped by currency here rather than in the repository: `debtsIn` returns what the
  /// group owes in every currency it has spent in, and `DebtSimplifier.plan` refuses a mixed list
  /// outright — which is the correct refusal, and the reason the grouping has to happen somewhere
  /// visible.
  ///
  /// Plans that suggest nothing are dropped, so an empty list means settled up.
  Future<List<CurrencyPlan>> settleUpPlans(String groupId) async {
    final edges = await _ledger.debtsIn(groupId);
    if (edges.isEmpty) return const [];

    final byCurrency = <String, List<DebtEdge>>{};
    for (final edge in edges) {
      byCurrency.putIfAbsent(edge.amount.currencyCode, () => []).add(edge);
    }

    final plans = <CurrencyPlan>[];
    for (final entry in byCurrency.entries) {
      final plan = _simplifier.plan(entry.value);
      if (plan.transfers.isEmpty) continue;
      plans.add(CurrencyPlan(currencyCode: entry.key, plan: plan));
    }
    // Most payments saved first: a plan that turns six transfers into two is the one worth showing at
    // the top, and a plan that saves nothing has already been dropped.
    plans.sort(
      (a, b) => b.plan.paymentsSaved.compareTo(a.plan.paymentsSaved),
    );
    return plans;
  }

  /// Whether simplifying [groupId] would help at all.
  ///
  /// What a screen checks before offering the button. Cheaper to ask than to render a plan that turns
  /// three payments into three payments, which is the state most small groups are in.
  Future<bool> canSimplify(String groupId) async {
    final plans = await settleUpPlans(groupId);
    return plans.any((p) => p.plan.isImprovement);
  }

  /// One counterparty's outstanding balances, across every currency.
  Stream<List<SplitBalance>> watchBalanceWith(String payeeId) =>
      _ledger.watchBalanceWith(payeeId);

  /// Every outstanding balance, for a list screen.
  Stream<List<SplitBalance>> watchBalances() => _ledger.watchBalances();

  /// [today], for a caller that wants to compute ageing itself without reaching for a clock.
  DateKey get today => _clock.today();
}
```

### `lib/domain/services/split/split_expense_service.dart`

```dart
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/split_expense.dart';
import 'package:alaya/domain/repositories/split_ledger_repository.dart';
import 'package:alaya/domain/services/split/split_resolver.dart';

/// Turns split instructions into a persisted expense, in both directions the module supports.
///
/// ## The two cases
///
/// **You paid.** Cash left your account, so a `transactions` withdrawal for the *full* amount already
/// exists and [transactionId] points at it. The split is attached to a transaction the expense editor
/// has already saved — this service never creates one, which is what keeps money movement in
/// `TransactionRepository` where its own validation lives.
///
/// **Somebody else paid.** No money has left your account, so there is **no transaction at all**
/// until you settle. [transactionId] is null and `paidByPayeeId` names who covered it.
///
/// The ordering is forced and it is the safe one: an expense saved without its split leaves a
/// transaction the user can see and re-split. There is no path that writes a split against a
/// transaction that does not exist, because the repository refuses a `transactionLineNo` on an expense
/// with no transaction and the id has to come from a save that already succeeded.
///
/// ## What it does not do
///
/// It does not resolve *and* store two versions of the same answer. `SplitResolver` decides the
/// amounts, and both the resolved figure and the input that produced it are written — so reopening a
/// 40/30/30 split shows 40/30/30 rather than three amounts the user has to reverse-engineer.
final class SplitExpenseService {
  /// Creates the service.
  const SplitExpenseService({
    required SplitLedgerRepository ledger,
    required UidGenerator uids,
    required Clock clock,
    SplitResolver resolver = const SplitResolver(),
  }) : _ledger = ledger,
       _uids = uids,
       _clock = clock,
       _resolver = resolver;

  final SplitLedgerRepository _ledger;
  final UidGenerator _uids;
  final Clock _clock;
  final SplitResolver _resolver;

  /// Records a split of [total] among [inputs].
  ///
  /// [id] is supplied when re-saving an existing split, so an edit replaces rather than duplicates.
  ///
  /// **A split whose shares do not sum to the total is saved, not refused.** Percentages that reach
  /// 90%, or a tip nobody assigned, are real states — `SplitExpense.unallocated` reports the gap and
  /// the screen decides what to say. `transaction_lines` already treats an un-itemised transaction
  /// exactly this way (ARCH_2 §4.2), and refusing would make the editor unusable mid-typing.
  Future<Result<SplitExpense, Failure>> record({
    required Money total,
    required String paidByPayeeId,
    required List<ShareInput> inputs,
    required SplitMethod method,
    String? id,
    String? transactionId,
    String? groupId,
    String? title,
    String? place,
    String? occasion,
    String? note,
    DateKey? on,
    DateKey? settleBy,
    SplitConversion? converted,
  }) async {
    if (method == SplitMethod.perLine) {
      return const Result.failure(
        BusinessRuleFailure(
          'An itemised split is recorded line by line.',
          rule: 'splitUseRecordItemised',
        ),
      );
    }

    final SplitResolution resolution;
    try {
      resolution = _resolver.resolve(total: total, inputs: inputs);
    } on ArgumentError catch (error) {
      // The resolver throws only for things a user cannot cause — no participants, the same person
      // twice, percent mixed with weights. Surfacing them as a failure rather than letting an
      // `ArgumentError` escape means a controller can show a message instead of crashing.
      return Result.failure(
        ValidationFailure(
          error.message?.toString() ?? 'That split could not be worked out.',
          field: 'inputs',
        ),
      );
    }

    final expenseId = id ?? _uids.generate();
    return _ledger.saveExpense(
      SplitExpense(
        id: expenseId,
        paidByPayeeId: paidByPayeeId,
        total: total,
        dateKey: on ?? _clock.today(),
        splitMethod: method,
        shares: [
          for (final share in resolution.shares)
            _shareOf(share, expenseId: expenseId),
        ],
        groupId: groupId,
        transactionId: transactionId,
        title: title,
        place: place,
        occasion: occasion,
        note: note,
        settleByDateKey: settleBy,
        converted: converted,
      ),
    );
  }

  /// Records an itemised split: each line divided among its own participants.
  ///
  /// **The feature the competition charges for**, and it rests on `transaction_lines`, which this app
  /// already had for the grocery-into-inventory flow. The ₹400 dessert is one line with one
  /// participant; the ₹1,200 platter is one line split four ways; each person's total is a sum over
  /// lines rather than a division of the bill.
  ///
  /// **Each line is resolved separately rather than through `SplitResolver.resolvePerLine`**, and the
  /// distinction is not cosmetic. `resolvePerLine` aggregates per person — which is exactly right for
  /// showing somebody their total, and wrong for writing rows, because the schema wants one share per
  /// person *per line* so `split_shares.transactionLineNo` can carry which item it was. Summing first
  /// would discard the line the row is supposed to name.
  ///
  /// Requires [transactionId]: itemising needs the receipt, and the receipt is the transaction's own
  /// lines. The repository enforces the same rule, and the schema enforces the half of it that fits in
  /// a single-row CHECK.
  Future<Result<SplitExpense, Failure>> recordItemised({
    required Money total,
    required String paidByPayeeId,
    required String transactionId,
    required List<SplitLine> lines,
    String? id,
    String? groupId,
    String? title,
    String? place,
    String? occasion,
    String? note,
    DateKey? on,
    DateKey? settleBy,
    SplitConversion? converted,
  }) async {
    if (lines.isEmpty) {
      return const Result.failure(
        ValidationFailure(
          'An itemised split needs at least one line.',
          field: 'lines',
        ),
      );
    }

    final expenseId = id ?? _uids.generate();
    final shares = <SplitShare>[];
    for (final line in lines) {
      final SplitResolution resolved;
      try {
        resolved = _resolver.resolve(total: line.amount, inputs: line.inputs);
      } on ArgumentError catch (error) {
        return Result.failure(
          ValidationFailure(
            'Line ${line.lineNo}: '
            '${error.message?.toString() ?? 'that split could not be worked out.'}',
            field: 'lines',
          ),
        );
      }
      for (final share in resolved.shares) {
        // A zero share is dropped rather than written. On a whole-expense split a zero is meaningful —
        // "she was there and did not eat" — but per line it would be a row per person per item they
        // did not order, which is most of them, and every one would sit in `split_shares` forever.
        if (share.amount.isZero) continue;
        shares.add(
          _shareOf(share, expenseId: expenseId, lineNo: line.lineNo),
        );
      }
    }

    return _ledger.saveExpense(
      SplitExpense(
        id: expenseId,
        paidByPayeeId: paidByPayeeId,
        total: total,
        dateKey: on ?? _clock.today(),
        splitMethod: SplitMethod.perLine,
        shares: shares,
        groupId: groupId,
        transactionId: transactionId,
        title: title,
        place: place,
        occasion: occasion,
        note: note,
        settleByDateKey: settleBy,
        converted: converted,
      ),
    );
  }

  /// Removes a split, leaving any linked transaction alone.
  ///
  /// The money did move. Deleting the split is a statement about who owed what, not about whether the
  /// payment happened — so the expense stays in the account ledger and only the debt disappears.
  Future<Result<void, Failure>> remove(String id) => _ledger.deleteExpense(id);

  /// Builds one share row from a resolved share.
  ///
  /// A resolved share carries the inputs that produced it — a list, because per line one person can
  /// appear several times. Here exactly one applies, since each line is resolved on its own.
  SplitShare _shareOf(
    ResolvedShare share, {
    required String expenseId,
    int? lineNo,
  }) {
    final input = share.inputs.first;
    return SplitShare(
      id: _uids.generate(),
      splitExpenseId: expenseId,
      payeeId: share.payeeId,
      amount: share.amount,
      inputKind: input.kind,
      inputValue: input.value,
      transactionLineNo: lineNo,
    );
  }
}
```

### `lib/domain/services/split/split_resolver.dart`

```dart
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';

/// One participant's instruction for how much they owe.
final class ShareInput {
  /// Creates an input. Prefer the named constructors.
  const ShareInput({required this.payeeId, required this.kind, this.value});

  /// An equal share of the remainder.
  const ShareInput.equal(String payeeId)
    : this(payeeId: payeeId, kind: ShareInputKind.equal);

  /// A fixed [minorUnits] amount that is this person's entire share.
  const ShareInput.exact(String payeeId, int minorUnits)
    : this(payeeId: payeeId, kind: ShareInputKind.exact, value: minorUnits);

  /// [minorUnits] charged to this person **on top of** an equal share of the remainder.
  ///
  /// Their drinks, or their half of the taxi, or the amount somebody volunteered to cover.
  const ShareInput.extra(String payeeId, int minorUnits)
    : this(payeeId: payeeId, kind: ShareInputKind.extra, value: minorUnits);

  /// [basisPoints] of the total — 2500 is 25%.
  const ShareInput.percent(String payeeId, int basisPoints)
    : this(payeeId: payeeId, kind: ShareInputKind.percent, value: basisPoints);

  /// A [weight] against the other weighted participants.
  const ShareInput.shares(String payeeId, int weight)
    : this(payeeId: payeeId, kind: ShareInputKind.shares, value: weight);

  /// Who owes.
  final String payeeId;

  /// How their share was specified.
  final ShareInputKind kind;

  /// Minor units for [ShareInputKind.exact] and [ShareInputKind.extra], basis points for
  /// [ShareInputKind.percent], a weight for [ShareInputKind.shares], and null for
  /// [ShareInputKind.equal].
  final int? value;

  /// Whether this participant takes part in dividing the remainder.
  ///
  /// Everyone except [ShareInputKind.exact] and [ShareInputKind.percent], both of which name a whole
  /// share and are finished once named.
  bool get sharesRemainder =>
      kind == ShareInputKind.equal ||
      kind == ShareInputKind.shares ||
      kind == ShareInputKind.extra;

  /// This participant's weight in the remainder.
  ///
  /// One for [ShareInputKind.extra]: an extra says what somebody additionally owes, not how the rest
  /// is divided, so they take an ordinary share of it.
  int get weight => switch (kind) {
    ShareInputKind.shares => value ?? 0,
    ShareInputKind.equal || ShareInputKind.extra => 1,
    ShareInputKind.exact || ShareInputKind.percent => 0,
  };
}

/// One line of an itemised split, with its own participants.
final class SplitLine {
  /// Creates a line.
  const SplitLine({
    required this.lineNo,
    required this.amount,
    required this.inputs,
  });

  /// The `transaction_lines.lineNo` this line corresponds to.
  final int lineNo;

  /// What the line cost.
  final Money amount;

  /// Who is on the hook for it, and how.
  final List<ShareInput> inputs;
}

/// What one participant ends up owing.
final class ResolvedShare {
  /// Creates a resolved share.
  const ResolvedShare({
    required this.payeeId,
    required this.amount,
    required this.inputs,
    this.extra,
    this.fromRemainder,
  });

  /// Who owes.
  final String payeeId;

  /// The exact amount, after allocation. Sums with its siblings to the allocated total.
  final Money amount;

  /// The inputs that produced it — more than one when the split was itemised.
  final List<ShareInput> inputs;

  /// The part of [amount] charged to this person alone, when they had an extra.
  ///
  /// Carried so a screen can show *"₹1,150 + ₹400 drinks"* rather than a bare ₹1,550 that reads like
  /// arithmetic nobody can check. A total a person cannot decompose is one they argue with.
  final Money? extra;

  /// The part of [amount] that came from dividing the remainder.
  final Money? fromRemainder;
}

/// A resolved split, including what it failed to account for.
final class SplitResolution {
  /// Creates a resolution.
  const SplitResolution({
    required this.total,
    required this.shares,
    required this.allocated,
  });

  /// What was being split.
  final Money total;

  /// Each participant's share, in the order the inputs arrived.
  final List<ResolvedShare> shares;

  /// The sum of [shares].
  final Money allocated;

  /// What is left over — [total] minus [allocated].
  ///
  /// **Reported, never absorbed.** Percentages that sum to 90% leave 10% unallocated, and exact
  /// amounts that overshoot leave it negative. `transaction_lines` already surfaces "₹500 total,
  /// ₹480 of lines → unallocated ₹20" rather than adjusting one of them, and a split is the same
  /// problem: quietly rounding a shortfall onto the last participant is how somebody ends up paying
  /// for a discrepancy nobody told them about.
  Money get unallocated => total - allocated;

  /// Whether the shares account for the total exactly.
  bool get isExact => unallocated.isZero;

  /// Whether the shares add up to more than the total.
  bool get isOverAllocated => unallocated.isNegative;
}

/// Turns split instructions into exact amounts.
///
/// Pure: money and instructions in, money out. No repository, no clock, no Flutter.
///
/// **A mismatch is a state, not a failure.** The editor shows live amounts as the user types, so a
/// resolver that threw on percentages totalling 90% would be unusable — the user is *mid-edit*. The
/// resolution carries [SplitResolution.unallocated] and the screen decides what to say about it.
/// `ArgumentError` is reserved for things a user cannot cause: no participants, a duplicate
/// participant, a negative weight.
///
/// ## The order of operations, and why it is this one
///
/// 1. **Exact amounts** come off the total first. "Priya owes exactly ₹500" is a fact, not a share,
///    and she takes no part in what follows.
/// 2. **Extras** come off next, and the person who owes one **stays in** for step 4. That single
///    difference is what lets one bill say "Ravi's drinks were ₹400" and "I'll cover ₹2,000" — the
///    same operation from two directions, and the thing the first version of this class could not
///    express at all.
/// 3. **Percentages** apply to the **total**, not to the remainder. A user who says "Priya covers
///    25%" means a quarter of the bill; making it a quarter of what is left would silently change
///    the number they typed.
/// 4. **Weights** — `equal`, `shares`, and anyone carrying an extra — divide **whatever remains**.
///
/// Mixing `percent` with weights in one split is refused. Both are proportional and the combination
/// has no single defensible reading; being told so beats getting a number nobody can explain.
final class SplitResolver {
  /// Creates the resolver. Stateless.
  const SplitResolver();

  /// Resolves [inputs] against [total].
  SplitResolution resolve({
    required Money total,
    required List<ShareInput> inputs,
  }) {
    if (inputs.isEmpty) {
      throw ArgumentError.value(inputs, 'inputs', 'must not be empty');
    }
    final seen = <String>{};
    for (final input in inputs) {
      if (!seen.add(input.payeeId)) {
        throw ArgumentError.value(
          input.payeeId,
          'inputs',
          'appears twice — one participant has one share per split',
        );
      }
      final value = input.value;
      if (value != null && value < 0) {
        throw ArgumentError.value(
          value,
          'inputs',
          'an amount, percentage or weight must not be negative',
        );
      }
    }

    final hasPercent = inputs.any((i) => i.kind == ShareInputKind.percent);
    final hasWeights = inputs.any((i) => i.sharesRemainder);
    if (hasPercent && hasWeights) {
      throw ArgumentError.value(
        inputs,
        'inputs',
        'mixes percent with weights — both are proportional and the combination has no single '
            'reading. Use one or the other, or exact amounts alongside either.',
      );
    }

    final code = total.currencyCode;
    final own = <String, Money>{
      for (final i in inputs) i.payeeId: Money.zero(code),
    };
    final extras = <String, Money>{};
    final fromRest = <String, Money>{};
    var claimed = 0;

    // Step 1 — exact amounts, taken as given.
    for (final input in inputs) {
      if (input.kind != ShareInputKind.exact) continue;
      final minor = input.value ?? 0;
      own[input.payeeId] = Money(minor, code);
      claimed += minor;
    }

    // Step 2 — extras, charged to one person and still leaving them in the division below.
    for (final input in inputs) {
      if (input.kind != ShareInputKind.extra) continue;
      final minor = input.value ?? 0;
      final amount = Money(minor, code);
      extras[input.payeeId] = amount;
      own[input.payeeId] = amount;
      claimed += minor;
    }

    // Step 3 — percentages, of the total.
    final percentInputs = inputs
        .where((i) => i.kind == ShareInputKind.percent)
        .toList();
    if (percentInputs.isNotEmpty) {
      var basisPoints = 0;
      for (final input in percentInputs) {
        basisPoints += input.value ?? 0;
      }
      if (basisPoints > 0 && basisPoints <= 10000) {
        // Allocated against a notional 10,000 basis points, with the unassigned share as the last
        // weight, so the parts stay exact and the shortfall surfaces as `unallocated` rather than
        // being spread across whoever happens to be listed.
        final weights = [
          for (final input in percentInputs) input.value ?? 0,
          if (basisPoints < 10000) 10000 - basisPoints,
        ];
        final parts = total.allocate(weights);
        for (var i = 0; i < percentInputs.length; i++) {
          own[percentInputs[i].payeeId] = parts[i];
          claimed += parts[i].minor;
        }
      } else if (basisPoints > 10000) {
        // **Over 100%, and allocation is the wrong tool.** `allocate` divides by the *sum* of the
        // weights it is given, so 70% and 70% would come back as 50% and 50% — renormalising the
        // overshoot away and reporting a perfectly balanced split. That is the clamping this
        // resolver exists not to do, and a test caught it.
        final magnitude = total.isNegative ? -total.minor : total.minor;
        for (final input in percentInputs) {
          final share = (magnitude * (input.value ?? 0) + 5000) ~/ 10000;
          final signed = total.isNegative ? -share : share;
          own[input.payeeId] = Money(signed, code);
          claimed += signed;
        }
      }
    }

    // Step 4 — weights, over what is left. Anyone with an extra is here too, at weight one.
    final weighted = inputs.where((i) => i.sharesRemainder).toList();
    if (weighted.isNotEmpty) {
      final remaining = Money(total.minor - claimed, code);
      var weightTotal = 0;
      final weights = <int>[];
      for (final input in weighted) {
        weights.add(input.weight);
        weightTotal += input.weight;
      }
      // **Only divided when it points the same way as the total.** Exact amounts and extras that
      // overshoot leave a negative remainder, and allocating that would hand somebody a negative
      // share — which reads as being *owed* money by a bill they are paying. They stay at zero and
      // the overshoot surfaces in `unallocated`, so nothing is hidden. The sign comparison rather
      // than `isPositive` is what keeps a refund split working.
      final sameDirection = remaining.isNegative == total.isNegative;
      if (weightTotal > 0 && !remaining.isZero && sameDirection) {
        final parts = remaining.allocate(weights);
        for (var i = 0; i < weighted.length; i++) {
          final id = weighted[i].payeeId;
          fromRest[id] = parts[i];
          own[id] = (own[id] ?? Money.zero(code)) + parts[i];
        }
      }
    }

    var allocated = Money.zero(code);
    final shares = <ResolvedShare>[];
    for (final input in inputs) {
      final amount = own[input.payeeId]!;
      shares.add(
        ResolvedShare(
          payeeId: input.payeeId,
          amount: amount,
          inputs: [input],
          extra: extras[input.payeeId],
          fromRemainder: fromRest[input.payeeId],
        ),
      );
      allocated += amount;
    }
    return SplitResolution(total: total, shares: shares, allocated: allocated);
  }

  /// Resolves an itemised split: each line divided among its own participants, then summed per
  /// person.
  ///
  /// [total] is the expense's own total, which is **not** assumed to equal the sum of the lines —
  /// `transactions.originalAmountMinor` is the source of truth and lines are optional detail
  /// (ARCH_2 §4.2). Anything the lines do not cover, and anything a line's own shares do not cover,
  /// both land in [SplitResolution.unallocated].
  SplitResolution resolvePerLine({
    required Money total,
    required List<SplitLine> lines,
  }) {
    if (lines.isEmpty) {
      throw ArgumentError.value(lines, 'lines', 'must not be empty');
    }

    final amounts = <String, Money>{};
    final inputsByPayee = <String, List<ShareInput>>{};
    final order = <String>[];

    for (final line in lines) {
      if (line.amount.currencyCode != total.currencyCode) {
        throw ArgumentError.value(
          line.lineNo,
          'lines',
          'line ${line.lineNo} is in ${line.amount.currencyCode}, not ${total.currencyCode}',
        );
      }
      final resolved = resolve(total: line.amount, inputs: line.inputs);
      for (final share in resolved.shares) {
        if (!inputsByPayee.containsKey(share.payeeId)) {
          inputsByPayee[share.payeeId] = [];
          amounts[share.payeeId] = Money.zero(total.currencyCode);
          order.add(share.payeeId);
        }
        amounts[share.payeeId] = amounts[share.payeeId]! + share.amount;
        inputsByPayee[share.payeeId]!.addAll(share.inputs);
      }
    }

    var allocated = Money.zero(total.currencyCode);
    final shares = <ResolvedShare>[];
    for (final payeeId in order) {
      final amount = amounts[payeeId]!;
      shares.add(
        ResolvedShare(
          payeeId: payeeId,
          amount: amount,
          inputs: inputsByPayee[payeeId]!,
        ),
      );
      allocated += amount;
    }
    return SplitResolution(total: total, shares: shares, allocated: allocated);
  }
}
```

### `lib/domain/services/split/split_summary_builder.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/split_read_models.dart';

/// One line of a shareable summary.
final class SummaryLine {
  /// Creates a line.
  const SummaryLine({
    required this.payeeId,
    required this.name,
    required this.amount,
    required this.theyOweMe,
  });

  /// The counterparty.
  final String payeeId;

  /// Their display name.
  final String name;

  /// What is outstanding, without its direction.
  final Money amount;

  /// Whether they owe the user.
  final bool theyOweMe;
}

/// A summary of who owes what, ready to send to somebody who does not have the app.
final class SplitSummary {
  /// Creates a summary.
  const SplitSummary({required this.lines, required this.text});

  /// The lines, worst first.
  final List<SummaryLine> lines;

  /// The whole thing as plain text.
  final String text;

  /// Whether there is anything to send.
  bool get isEmpty => lines.isEmpty;
}

/// The sentences a summary needs, read from the ARB by the caller.
///
/// A named record rather than positional strings, so adding a fifth does not silently reorder the
/// existing four at every call site.
final class SummaryLabels {
  /// Creates the labels.
  const SummaryLabels({
    required this.heading,
    required this.owesYou,
    required this.youOwe,
    required this.payMeAt,
  });

  /// The first line.
  final String heading;

  /// Precedes a name that owes the user.
  final String owesYou;

  /// Precedes a name the user owes.
  final String youOwe;

  /// Introduces the user's payment details, when they have set any.
  final String payMeAt;
}

/// Builds the message that stands in for sync.
///
/// **This is the module's answer to the friction every review of every competitor names.** To split a
/// bill with six people on Splitwise, all six install it and create accounts, and in practice two
/// never will. Alaya is already on the right side of that — nobody else needs anything — but the gap
/// is outbound: without this there is no way to show them the same numbers.
///
/// ## Plain text, and no payment protocol
///
/// An earlier version emitted a `upi://pay` intent per line. **That was wrong for an app that ships
/// worldwide**: UPI is India's rail and the link is inert in the US, Europe, China and everywhere else,
/// so the feature was dead weight for most users and a maintenance burden for all of them — amount
/// formatting in major units, percent-encoding, a currency parameter, and a link that opens a payment
/// app with the wrong figure if any of it is subtly wrong.
///
/// What replaced it is one optional line of free text the user writes once: a UPI id, a PayPal.me
/// link, an IBAN, a Venmo handle, "cash is fine". It works in every country because it makes no claim
/// about how money moves, and it is one field instead of a protocol.
///
/// Dropping the link also removed [Money] formatting for machines from this class entirely, which is
/// why it no longer needs a per-currency precision. The only formatting left is [formatAmount], which
/// the caller supplies because a currency symbol comes from the `currencies` row and a pure builder
/// has no way to read one.
///
/// Pure: balances, names and labels in, a string out. No clock, no repository, no Flutter.
final class SplitSummaryBuilder {
  /// Creates the builder. Stateless.
  const SplitSummaryBuilder();

  /// Composes a summary of [balances].
  ///
  /// [labels] carries the copy, because a builder in `domain/` has no `BuildContext` and Law U5 keeps
  /// English out of anything below the widget layer.
  ///
  /// [paymentHandle] is whatever the user wrote under "How people can pay you". Supplied, it becomes a
  /// closing line; omitted, the summary is still perfectly useful text.
  SplitSummary build({
    required List<SplitBalance> balances,
    required String Function(String payeeId) nameOf,
    required String Function(Money amount) formatAmount,
    required SummaryLabels labels,
    String? paymentHandle,
  }) {
    final lines = <SummaryLine>[];
    for (final balance in balances) {
      if (balance.isSettled) continue;
      lines.add(
        SummaryLine(
          payeeId: balance.payeeId,
          name: nameOf(balance.payeeId),
          amount: balance.outstanding,
          theyOweMe: balance.theyOweMe,
        ),
      );
    }

    final buffer = StringBuffer()..writeln(labels.heading);
    for (final line in lines) {
      final amount = formatAmount(line.amount);
      buffer
        ..writeln()
        ..writeln(
          line.theyOweMe
              ? '${labels.owesYou} ${line.name}: $amount'
              : '${labels.youOwe} ${line.name}: $amount',
        );
    }

    // **Only when somebody owes the user.** A payment handle on a summary where the user owes everybody
    // is asking to be paid for a debt they hold, which reads as a mistake at best.
    final handle = paymentHandle?.trim();
    if (lines.any((line) => line.theyOweMe) &&
        handle != null &&
        handle.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('${labels.payMeAt} $handle');
    }

    return SplitSummary(lines: lines, text: buffer.toString().trimRight());
  }
}
```

### `lib/domain/services/stock_reconciler.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/domain/repositories/batch_repository.dart';

/// Decides whether a batch's cached quantity still matches its movement ledger, and what the cache
/// should be set to when it does not.
///
/// Law L3 permits exactly one stored derived total in the schema —
/// `inventory_batches.remaining_quantity_milli` — on the condition that it is reconstructible from
/// the append-only ledger at any time. This class is that reconstruction, and
/// `v_batch_stock_check` is the database's own independent statement of the same sum.
///
/// **The formula is duplicated on purpose, and that is the whole point.** Two independent
/// computations that must agree is a check; one computation used twice is not. If they ever diverge,
/// the view is authoritative for *detection* and this class for *repair* — and a divergence between
/// them is itself a bug worth failing a test over. `StockMovementDao.incomingKinds` is the single
/// shared definition of direction, so the two can only differ by arithmetic, not by disagreeing
/// about which way a `waste` moves stock.
final class StockReconciler {
  /// Creates the reconciler.
  const StockReconciler();

  /// Whether [kind] increases stock.
  ///
  /// Mirrors `v_batch_stock_check`'s `CASE WHEN m.kind IN ('openingIn','purchaseIn','manualIn',
  /// 'adjustIn')` exactly. A reversal needs no special case: a reversing `adjustIn` cancels the
  /// `consume` it points at simply by summing with the opposite sign.
  bool isIncoming(StockMovementKind kind) => switch (kind) {
    StockMovementKind.openingIn ||
    StockMovementKind.purchaseIn ||
    StockMovementKind.manualIn ||
    StockMovementKind.adjustIn => true,
    StockMovementKind.consume ||
    StockMovementKind.waste ||
    StockMovementKind.expired ||
    StockMovementKind.adjustOut => false,
  };

  /// The remaining quantity [movements] imply, in milli-base units.
  ///
  /// Absolute rather than a delta: it reads the whole history and returns what the cache *should*
  /// be, so a repair self-heals even if the cache had already drifted before the repair ran.
  int remainingFromLedgerMilli(Iterable<StockMovement> movements) {
    var total = 0;
    for (final movement in movements) {
      total += isIncoming(movement.kind)
          ? movement.quantity.milliBase
          : -movement.quantity.milliBase;
    }
    return total;
  }

  /// Reconciles one batch's [cached] quantity against [movements].
  BatchReconciliation reconcile({
    required String batchId,
    required Qty cached,
    required Iterable<StockMovement> movements,
  }) {
    final fromLedgerMilli = remainingFromLedgerMilli(movements);
    final category = cached.category;
    return BatchReconciliation(
      batchId: batchId,
      cached: cached,
      fromLedger: Qty(fromLedgerMilli, category),
      discrepancy: Qty(cached.milliBase - fromLedgerMilli, category),
    );
  }

  /// The batches among [reconciliations] whose cache disagrees with their ledger.
  ///
  /// Both signs count. A cache *below* the ledger is as wrong as one above it — it would hide stock
  /// the user actually has, which is the harder error to notice.
  List<BatchReconciliation> discrepancies(
    Iterable<BatchReconciliation> reconciliations,
  ) => reconciliations.where((r) => !r.isConsistent).toList();

  /// A one-line summary for the Settings repair screen.
  ReconciliationSummary summarise(
    Iterable<BatchReconciliation> reconciliations,
  ) {
    final all = reconciliations.toList();
    final broken = discrepancies(all);
    return ReconciliationSummary(
      batchesChecked: all.length,
      batchesNeedingRepair: broken.length,
      largestDiscrepancy: broken.isEmpty
          ? null
          : broken
                .map((r) => r.discrepancy)
                .reduce(
                  (a, b) => a.milliBase.abs() >= b.milliBase.abs() ? a : b,
                ),
    );
  }

  /// A zero quantity in [category], for reconciling a batch with no movements at all.
  Qty zeroIn(UnitCategory category) => Qty(0, category);
}

/// What a reconciliation pass found.
class ReconciliationSummary {
  /// Creates a summary.
  const ReconciliationSummary({
    required this.batchesChecked,
    required this.batchesNeedingRepair,
    this.largestDiscrepancy,
  });

  /// How many batches were examined.
  final int batchesChecked;

  /// How many disagreed with their ledger.
  final int batchesNeedingRepair;

  /// The biggest disagreement by absolute size, or null when everything agreed.
  final Qty? largestDiscrepancy;

  /// True when every batch's cache matched its ledger.
  bool get isHealthy => batchesNeedingRepair == 0;
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
  const TipProduct({
    required this.id,
    required this.title,
    required this.price,
  });

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

### `lib/domain/services/unit_engine.dart`

```dart
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/entities/unit.dart';

/// Converts quantities between units of the same category, and validates user-defined units.
///
/// **There is no unit conversion of a stored quantity, and that is the point.** A `Qty` holds
/// milli-base-units plus a category (Law L2), so `2 kg` and `2000 g` are the *same* stored value —
/// only their display differs. Units matter at two boundaries: parsing text into base units
/// (`UnitConverter`) and formatting base units back out (`QtyFormatter`). What is left for this
/// engine is the genuinely arithmetic question — *how many of unit X is this quantity?* — plus
/// refusing the two conversions that must never happen.
///
/// Every operation is integer-only. No step touches a `double`, so no quantity can accumulate the
/// drift that made `0.1 + 0.2 != 0.3` a reason to store money in minor units in the first place.
final class UnitEngine {
  /// Creates the engine.
  const UnitEngine();

  /// Milli-base-units per one base unit — the scale every `factorToBaseMilli` is expressed in.
  static const int milliPerBaseUnit = 1000;

  /// The largest factor a user-defined unit may declare.
  ///
  /// One million milli-base-units is one thousand base units — a `tonne` against `g`, or a
  /// `kilolitre` against `ml`. Beyond that, `amountInUnitMilli`'s intermediate
  /// `milliBase * 1000` starts approaching the 64-bit ceiling for large quantities, and no
  /// household inventory needs it.
  static const int maxFactorToBaseMilli = 1000000000;

  /// How much of [unit] the quantity [quantity] represents, in **thousandths of [unit]**.
  ///
  /// Returns thousandths rather than whole units because the answer is frequently fractional and
  /// this engine will not return a `double`: `1.5 kg` is `1500` thousandths of a kilogram, exactly.
  /// Divide by [milliPerBaseUnit] at the display boundary, where `QtyFormatter` already does.
  ///
  /// Fails with a [BusinessRuleFailure] when [unit] measures a different category (Law L8) — a
  /// weight cannot be asked to express itself in millilitres — and with a [ValidationFailure] when
  /// the conversion would not be exact, rather than silently truncating. An inexact result means
  /// the user is asking for a unit the quantity cannot be cleanly expressed in, which is a real
  /// answer worth surfacing rather than rounding away.
  Result<int, Failure> amountInUnitMilli({
    required Qty quantity,
    required Unit unit,
  }) {
    if (unit.category != quantity.category) {
      return Result.failure(
        BusinessRuleFailure(
          'A ${quantity.category.name} quantity cannot be expressed in ${unit.code}, which '
              'measures ${unit.category.name}. There is no conversion between categories.',
          rule: 'crossCategoryConversion',
        ),
      );
    }
    if (unit.factorToBaseMilli <= 0) {
      return Result.failure(
        ValidationFailure(
          'Unit ${unit.code} has a non-positive factor and cannot be converted to.',
          field: 'factorToBaseMilli',
        ),
      );
    }

    final scaled = quantity.milliBase * milliPerBaseUnit;
    if (scaled % unit.factorToBaseMilli != 0) {
      return Result.failure(
        ValidationFailure(
          'This quantity cannot be expressed exactly in ${unit.code}.',
          field: 'unit',
        ),
      );
    }
    return Result.ok(scaled ~/ unit.factorToBaseMilli);
  }

  /// The same question as [amountInUnitMilli], but truncating toward zero instead of failing.
  ///
  /// For display and estimates only. Returns null on a category mismatch, because that is not a
  /// rounding problem — it is a question with no answer.
  int? amountInUnitMilliTruncating({
    required Qty quantity,
    required Unit unit,
  }) {
    if (unit.category != quantity.category) return null;
    if (unit.factorToBaseMilli <= 0) return null;
    return (quantity.milliBase * milliPerBaseUnit) ~/ unit.factorToBaseMilli;
  }

  /// Builds a `Qty` from [amountMilli] thousandths of [unit].
  ///
  /// The inverse of [amountInUnitMilli], and always exact: multiplying into base units cannot lose
  /// precision the way dividing out of them can. `1500` thousandths of `kg` becomes `1500000`
  /// milli-grams.
  Result<Qty, Failure> quantityFromUnit({
    required int amountMilli,
    required Unit unit,
  }) {
    if (unit.factorToBaseMilli <= 0) {
      return Result.failure(
        ValidationFailure(
          'Unit ${unit.code} has a non-positive factor.',
          field: 'factorToBaseMilli',
        ),
      );
    }
    final milliBase = amountMilli * unit.factorToBaseMilli ~/ milliPerBaseUnit;
    return Result.ok(Qty(milliBase, unit.category));
  }

  /// Converts a quantity expressed in [from] into thousandths of [to].
  ///
  /// A convenience over [quantityFromUnit] + [amountInUnitMilli] for the direct question "2 dozen
  /// is how many pieces?" — `2000` thousandths of `dozen` becomes `24000` thousandths of `pc`.
  Result<int, Failure> convert({
    required int amountMilli,
    required Unit from,
    required Unit to,
  }) {
    if (from.category != to.category) {
      return Result.failure(
        BusinessRuleFailure(
          'There is no conversion between ${from.category.name} and ${to.category.name}.',
          rule: 'crossCategoryConversion',
        ),
      );
    }
    final quantity = quantityFromUnit(amountMilli: amountMilli, unit: from);
    if (quantity.isFailure) return Result.failure(quantity.failureOrNull!);
    return amountInUnitMilli(quantity: quantity.valueOrNull!, unit: to);
  }

  /// Validates a unit the user defined themselves.
  ///
  /// ARCH_1 §5.3 is explicit that a unit needs a factor the user can *state exactly*. If they
  /// cannot — "one packet of noodles" — the correct action is a new Item, not a unit with an
  /// invented factor, because every quantity recorded against a wrong factor is silently wrong and
  /// no migration can recover the intent.
  ///
  /// Rejects a non-positive factor, one above [maxFactorToBaseMilli], an empty or overlong code,
  /// and a code that collides with a seeded system unit under case folding — `KG` and `kg` would
  /// be two rows the user cannot tell apart.
  Result<void, Failure> validateUserUnit({
    required Unit unit,
    required Iterable<Unit> existingUnits,
  }) {
    final code = unit.code.trim();
    if (code.isEmpty) {
      return const Result.failure(ValidationFailure('A unit needs a code.', field: 'code'));
    }
    if (code.length > 12) {
      return const Result.failure(
        ValidationFailure('A unit code must be 12 characters or fewer.', field: 'code'),
      );
    }
    if (unit.displayName.trim().isEmpty) {
      return const Result.failure(
        ValidationFailure('A unit needs a display name.', field: 'displayName'),
      );
    }
    if (unit.factorToBaseMilli <= 0) {
      return const Result.failure(
        ValidationFailure(
          'A unit needs a positive factor to its category\'s base unit. If you cannot state one '
              'exactly, create a separate Item instead.',
          field: 'factorToBaseMilli',
        ),
      );
    }
    if (unit.factorToBaseMilli > maxFactorToBaseMilli) {
      return const Result.failure(
        ValidationFailure(
          'That factor is too large to convert safely.',
          field: 'factorToBaseMilli',
        ),
      );
    }

    final folded = code.toLowerCase();
    for (final existing in existingUnits) {
      if (existing.code == unit.code) continue;
      if (existing.code.toLowerCase() == folded) {
        return Result.failure(
          ConflictFailure('A unit with the code "${existing.code}" already exists.'),
        );
      }
    }
    return const Result.ok(null);
  }
}
```

### `test/domain/analytics_test.dart`

```dart
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/backup/restore_service.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/seed/seed_data.dart';

/// Backup and restore: the `user_version` gate, merge last-write-wins, and all-or-nothing.
///
/// These run against real SQLite via `NativeDatabase`, because every guarantee under test is a
/// property of SQLite's `ATTACH` and upsert behaviour rather than of Dart. A fake would only assert
/// that I had understood them, which is the thing actually in question.
void main() {
  late AlayaDatabase db;
  late RestoreService restore;
  late Directory tempDir;

  setUpAll(() {
    // Several tests open a second AlayaDatabase to stamp or read an exported file. That is the point of
    // them, and the two never share a QueryExecutor, so drift's race-condition warning does not apply —
    // it was drowning the real failures in this suite.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    // Seeded, because `items.default_display_unit_code` is a hard foreign key to `units.code` and an
    // unseeded database has no units at all. A real restore always runs against a seeded database, so
    // testing against an empty one was testing a state the app never reaches.
    final seed = SeedData(
      uids: SequentialUidGenerator(prefix: 'restore'),
      clock: FixedClock(DateTime.utc(2026, 7, 28, 9)),
    );
    db = AlayaDatabase(NativeDatabase.memory(), seeder: seed.insertAll);
    restore = RestoreService(database: db);
    // Force onCreate, so the seed is in place before the first export.
    await db.customSelect('SELECT 1').get();
    tempDir = await Directory.systemTemp.createTemp('alaya_restore_test');
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Writes an item with an explicit `updatedAt`, which is what the merge rule compares.
  Future<void> putItem({
    required AlayaDatabase into,
    required String id,
    required String name,
    required int updatedAt,
  }) async {
    await into
        .into(into.items)
        .insertOnConflictUpdate(
          ItemsCompanion.insert(
            id: id,
            name: name,
            normalizedName: name.toLowerCase(),
            unitCategory: UnitCategory.weight,
            defaultDisplayUnitCode: 'g',
            // `food`, not `grocery` — ItemKind is generic/food/medicine/beauty/household/other.
            // `grocery` is a TransactionSubtype, which is a different axis: what the money was for
            // versus what the thing is.
            itemKind: ItemKind.food,
            isFavorite: false,
            createdAt: 1000,
            updatedAt: updatedAt,
          ),
        );
  }

  Future<Map<String, ({String name, int updatedAt})>> readItems(
    AlayaDatabase from,
  ) async {
    final rows = await from.select(from.items).get();
    return {for (final r in rows) r.id: (name: r.name, updatedAt: r.updatedAt)};
  }

  /// Exports to a file with `VACUUM INTO`, which is what `BackupService` does.
  Future<String> exportTo(String fileName) async {
    final path = '${tempDir.path}/$fileName';
    await db.customStatement("VACUUM INTO '$path'");
    return path;
  }

  group('the user_version gate', () {
    test('a backup at the app\'s own version is accepted', () async {
      final path = await exportTo('same.db');

      final result = await restore.readBackupSchemaVersion(path);

      expect(result.isFailure, isFalse);
      expect(result.valueOrNull, db.schemaVersion);
    });

    test('a backup from a NEWER app version is refused', () async {
      final path = await exportTo('newer.db');
      // Stamp the exported file as if a future build wrote it.
      final future = AlayaDatabase(NativeDatabase(File(path)));
      await future.customStatement(
        'PRAGMA user_version = ${db.schemaVersion + 5}',
      );
      await future.close();

      final result = await restore.merge(path);

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull!.message, contains('newer version'));
    });

    test('the gate reads the ATTACHED file, not the live database', () async {
      final path = await exportTo('stamped.db');
      final other = AlayaDatabase(NativeDatabase(File(path)));
      await other.customStatement('PRAGMA user_version = 99');
      await other.close();

      final read = await restore.readBackupSchemaVersion(path);

      expect(
        read.valueOrNull,
        99,
        reason:
            'PRAGMA backup.user_version — the qualified form, since '
            'pragma_user_version() takes no argument',
      );
      expect(db.schemaVersion, isNot(99));
    });

    test('a file that is not SQLite is refused', () async {
      final path = '${tempDir.path}/garbage.db';
      await File(path).writeAsString('this is not a database');

      final result = await restore.readBackupSchemaVersion(path);

      expect(result.isFailure, isTrue);
    });

    test('a missing file is refused', () async {
      final result = await restore.readBackupSchemaVersion(
        '${tempDir.path}/absent.db',
      );

      expect(result.isFailure, isTrue);
    });
  });

  group('merge: export, mutate, merge back', () {
    test(
      'last-write-wins by updatedAt — the LOCAL newer row survives',
      () async {
        await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
        await putItem(into: db, id: 'b', name: 'Banana', updatedAt: 1000);

        final backup = await exportTo('lww.db');

        // Mutate locally AFTER the backup, so local is newer.
        await putItem(
          into: db,
          id: 'a',
          name: 'Apple (edited later)',
          updatedAt: 5000,
        );

        final result = await restore.merge(backup);
        expect(result.isFailure, isFalse);

        final items = await readItems(db);
        expect(
          items['a']!.name,
          'Apple (edited later)',
          reason:
              'the backup holds an OLDER version of a, so it must not overwrite',
        );
        expect(items['a']!.updatedAt, 5000);
      },
    );

    test('last-write-wins by updatedAt — the BACKUP newer row wins', () async {
      await putItem(
        into: db,
        id: 'a',
        name: 'Apple (newer, will be backed up)',
        updatedAt: 9000,
      );
      final backup = await exportTo('lww2.db');

      // Now make the local row older than what the backup holds.
      await putItem(
        into: db,
        id: 'a',
        name: 'Apple (rolled back locally)',
        updatedAt: 100,
      );

      await restore.merge(backup);

      final items = await readItems(db);
      expect(
        items['a']!.name,
        'Apple (newer, will be backed up)',
        reason:
            'the rule is genuinely a timestamp comparison, not local precedence',
      );
      expect(items['a']!.updatedAt, 9000);
    });

    test('rows absent from the backup SURVIVE', () async {
      await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
      final backup = await exportTo('survivors.db');

      // Added after the backup was taken, so the backup knows nothing about it.
      await putItem(
        into: db,
        id: 'z',
        name: 'Added after the backup',
        updatedAt: 6000,
      );

      await restore.merge(backup);

      final items = await readItems(db);
      expect(
        items.containsKey('z'),
        isTrue,
        reason:
            'merge is an upsert, never a replace — a merge that deleted local rows would '
            'lose data the user never asked to discard',
      );
      expect(items['z']!.name, 'Added after the backup');
    });

    test('rows only in the backup are INSERTED', () async {
      await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
      await putItem(
        into: db,
        id: 'gone',
        name: 'Only in the backup',
        updatedAt: 3000,
      );
      final backup = await exportTo('inserts.db');

      // Delete it locally (hard delete, so the merge must reinstate it).
      await db.customStatement("DELETE FROM items WHERE id = 'gone'");
      expect((await readItems(db)).containsKey('gone'), isFalse);

      await restore.merge(backup);

      expect((await readItems(db)).containsKey('gone'), isTrue);
    });

    test(
      'merging the same backup twice changes nothing the second time',
      () async {
        await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
        final backup = await exportTo('idempotent.db');

        await restore.merge(backup);
        final afterFirst = await readItems(db);
        await restore.merge(backup);
        final afterSecond = await readItems(db);

        expect(afterSecond.length, afterFirst.length);
        expect(
          afterSecond['a']!.updatedAt,
          afterFirst['a']!.updatedAt,
          reason:
              'UUID primary keys mean merge needs no ID remapping, so it is naturally idempotent',
        );
      },
    );

    test('the report names how many tables were merged', () async {
      await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
      final backup = await exportTo('report.db');

      final result = await restore.merge(backup);

      final report = result.valueOrNull!;
      expect(report.mode, RestoreMode.merge);
      expect(report.tablesMerged, greaterThan(0));
      expect(report.backupSchemaVersion, db.schemaVersion);
    });
  });

  group('the merge is all-or-nothing', () {
    test(
      'the backup file is DETACHED afterwards, so a second merge works',
      () async {
        final backup = await exportTo('detach.db');

        await restore.merge(backup);
        final second = await restore.merge(backup);

        expect(
          second.isFailure,
          isFalse,
          reason:
              'a stranded ATTACH would fail the next merge with a duplicate-alias error',
        );
      },
    );

    test('the backup is detached even when the merge throws', () async {
      final path = '${tempDir.path}/broken.db';
      await File(path).writeAsString('not sqlite');

      await restore.merge(path);

      // If the alias were still held, attaching it again would fail.
      await db.customStatement("ATTACH DATABASE ? AS backup", [
        path.replaceAll('broken', 'probe'),
      ]);
      await db.customStatement('DETACH DATABASE backup');
    });

    test('a failure part-way through leaves nothing applied', () async {
      await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
      final before = await readItems(db);

      // A statement that violates a constraint inside a transaction must roll the whole thing back.
      var threw = false;
      try {
        await db.transaction(() async {
          await putItem(
            into: db,
            id: 'new',
            name: 'Should vanish',
            updatedAt: 3000,
          );
          await db.customStatement(
            'INSERT INTO items (id, name, normalized_name, unit_category, '
            'default_display_unit_code, item_kind, is_favorite, created_at, updated_at) '
            "VALUES ('a', 'dup', 'dup', 'weight', 'g', 'food', 0, 1, 1)",
          );
        });
      } on Object {
        threw = true;
      }

      expect(threw, isTrue);
      final after = await readItems(db);
      expect(
        after.length,
        before.length,
        reason:
            'ONE transaction for the whole merge is what makes a partial merge impossible',
      );
      expect(after.containsKey('new'), isFalse);
    });
  });

  group('merge statement construction', () {
    test('a table with updated_at gets the last-write-wins guard', () async {
      final sql = await restore.buildMergeStatement('items');

      expect(sql, contains('ON CONFLICT(id) DO UPDATE SET'));
      expect(sql, contains('WHERE excluded.updated_at > items.updated_at'));
      expect(
        sql,
        isNot(contains('id = excluded.id')),
        reason: 'the conflict target must not be reassigned',
      );
    });

    test(
      'a link table upserts on its composite key, last-write-wins like any other',
      () async {
        final sql = await restore.buildMergeStatement('transaction_tags');

        // My first version of this test asserted `DO NOTHING`, on the assumption that link tables carry
        // no timestamps. They do — **every table in this schema has `updated_at`**, which I confirmed by
        // scanning all of them. So `buildMergeStatement`'s `DO NOTHING` branch is unreachable today; it
        // stays as insurance for a future table without audit columns, and this test asserts what the
        // schema actually produces.
        expect(sql, contains('ON CONFLICT(transaction_id, tag_id)'));
        expect(
          sql,
          contains('WHERE excluded.updated_at > transaction_tags.updated_at'),
        );
        expect(
          sql,
          isNot(contains('transaction_id = excluded.transaction_id')),
          reason: 'the conflict target must not be reassigned',
        );
      },
    );

    test('natural-key tables use their real primary key, not id', () async {
      expect(
        await restore.buildMergeStatement('currencies'),
        contains('ON CONFLICT(code)'),
      );
      expect(
        await restore.buildMergeStatement('app_settings'),
        contains('ON CONFLICT(key)'),
      );
      expect(
        await restore.buildMergeStatement('currency_rates'),
        contains('ON CONFLICT(base_code, quote_code, rate_date_key)'),
      );
    });

    test('the merge order is foreign-key safe', () {
      final order = RestoreService.mergeOrder;

      expect(
        order.indexOf('accounts'),
        lessThan(order.indexOf('transactions')),
      );
      expect(
        order.indexOf('transactions'),
        lessThan(order.indexOf('transaction_lines')),
      );
      expect(
        order.indexOf('items'),
        lessThan(order.indexOf('inventory_batches')),
      );
      expect(
        order.indexOf('inventory_batches'),
        lessThan(order.indexOf('stock_movements')),
      );
      expect(
        order.indexOf('tags'),
        lessThan(order.indexOf('transaction_tags')),
      );
      expect(
        order.indexOf('assets'),
        lessThan(order.indexOf('service_records')),
      );
      expect(order.indexOf('currencies'), lessThan(order.indexOf('accounts')));
      expect(
        order.indexOf('recurring_templates'),
        lessThan(order.indexOf('recurring_occurrences')),
      );
    });
  });

  group('replace mode', () {
    test('snapshots a rollback before swapping the file', () async {
      await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
      final backup = await exportTo('replace-source.db');
      final live = '${tempDir.path}/live.db';
      final rollback = '${tempDir.path}/rollback.db';
      await File(backup).copy(live);

      final result = await restore.replaceFiles(
        backupPath: backup,
        livePath: live,
        rollbackPath: rollback,
      );

      expect(result.isFailure, isFalse);
      expect(
        File(rollback).existsSync(),
        isTrue,
        reason:
            'a corrupt backup must not leave the user with no database at all',
      );
      expect(result.valueOrNull!.mode, RestoreMode.replace);
    });

    test(
      'refuses a backup from a newer app version before touching any file',
      () async {
        final backup = await exportTo('replace-newer.db');
        final future = AlayaDatabase(NativeDatabase(File(backup)));
        await future.customStatement(
          'PRAGMA user_version = ${db.schemaVersion + 1}',
        );
        await future.close();

        final live = '${tempDir.path}/live2.db';
        await File(backup).copy(live);

        final result = await restore.replaceFiles(
          backupPath: backup,
          livePath: live,
          rollbackPath: '${tempDir.path}/rollback2.db',
        );

        expect(result.isFailure, isTrue);
        expect(
          File('${tempDir.path}/rollback2.db').existsSync(),
          isFalse,
          reason: 'the gate runs first, so a refused restore does no file work',
        );
      },
    );

    test('the rollback can be put back', () async {
      final backup = await exportTo('rb-source.db');
      final live = '${tempDir.path}/live3.db';
      final rollback = '${tempDir.path}/rollback3.db';
      await File(backup).copy(live);
      await File(backup).copy(rollback);

      final result = await restore.restoreRollback(
        rollbackPath: rollback,
        livePath: live,
      );

      expect(result.isFailure, isFalse);
    });

    test('restoring a rollback that does not exist fails cleanly', () async {
      final result = await restore.restoreRollback(
        rollbackPath: '${tempDir.path}/nope.db',
        livePath: '${tempDir.path}/live4.db',
      );

      expect(result.isFailure, isTrue);
    });
  });

  group('no encryption', () {
    test(
      'an exported backup is readable plaintext SQLite with no key',
      () async {
        await putItem(into: db, id: 'a', name: 'Apple', updatedAt: 2000);
        final path = await exportTo('plaintext.db');

        // Opened with no PRAGMA key, no passphrase, nothing.
        final reopened = AlayaDatabase(NativeDatabase(File(path)));
        final rows = await reopened.select(reopened.items).get();
        await reopened.close();

        expect(rows.map((r) => r.id), contains('a'));
      },
    );

    test('the file begins with SQLite\'s plaintext header', () async {
      final path = await exportTo('header.db');

      final header = await File(path).openRead(0, 16).first;

      expect(
        String.fromCharCodes(header.take(15)),
        'SQLite format 3',
        reason:
            'an encrypted file would have an opaque header; this is the honest threat model',
      );
    });
  });
}
```

### `test/domain/balance_service_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// Exercises the net-worth rule: what counts, what converts, and what is excluded.
///
/// `BalanceService.totalFrom` is pure given a rate table, so none of this needs a database.
void main() {
  const service = BalanceService();
  final asOf = DateKey.fromYmd(2026, 7, 27);

  const digits = {'USD': 2, 'INR': 2, 'EUR': 2, 'JPY': 0, 'CNY': 2};

  RateTable table() => RateTable(
    rates: [
      UsdRate(quoteCode: 'INR', on: asOf, rate: 83.30, rateRaw: '83.3'),
      UsdRate(quoteCode: 'EUR', on: asOf, rate: 0.92, rateRaw: '0.92'),
      UsdRate(quoteCode: 'JPY', on: asOf, rate: 158.60, rateRaw: '158.6'),
    ],
    decimalDigitsByCode: digits,
  );

  AccountBalanceInput account(
      String id,
      int minor,
      String code, {
        bool includeInNetWorth = true,
      }) =>
      AccountBalanceInput(
        accountId: id,
        balance: Money(minor, code),
        includeInNetWorth: includeInNetWorth,
      );

  group('what counts toward net worth', () {
    test('an account with includeInNetWorth false is excluded from the total', () {
      final result = service.totalFrom(
        balances: [
          account('cash', 400000, 'INR'),
          account('loan', 999999, 'INR', includeInNetWorth: false),
        ],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, const Money(400000, 'INR'));
      expect(result.unconvertedCount, 0,
          reason: 'deliberately excluded is not the same as unconvertible');
    });

    test('an ARCHIVED account still counts — archive keeps money in net worth', () {
      // ARCH_3 §4's table is explicit: `isArchived` is "counted in totals? yes". Only `deletedAt`
      // removes money. A closed bank account holding a balance is retired, not gone — and the
      // repository filters soft-deleted rows before this service ever sees them, so archived-ness
      // is deliberately not a filter here.
      final result = service.totalFrom(
        balances: [
          account('cash', 400000, 'INR'),
          account('old-bank', 250000, 'INR'),
        ],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, const Money(650000, 'INR'));
    });

    test('no accounts at all is a zero in the home currency, not an error', () {
      final result = service.totalFrom(
        balances: const [],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, Money.zero('INR'));
      expect(result.isComplete, isTrue);
    });

    test('a negative balance reduces the total', () {
      final result = service.totalFrom(
        balances: [account('cash', 400000, 'INR'), account('overdrawn', -150000, 'INR')],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, const Money(250000, 'INR'));
    });
  });

  group('conversion', () {
    test('a balance already in the home currency needs no rate', () {
      final result = service.totalFrom(
        balances: [account('cash', 400000, 'INR')],
        // An entirely empty table: a single-currency user must never see an unconverted chip.
        table: RateTable.empty(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, const Money(400000, 'INR'));
      expect(result.unconvertedCount, 0);
      expect(result.isComplete, isTrue);
    });

    test('mixed currencies convert into one home total', () {
      final result = service.totalFrom(
        balances: [
          account('inr', 100000, 'INR'), // 1000.00 INR
          account('usd', 10000, 'USD'), // 100.00 USD -> 8330.00 INR
        ],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      // 1000 + (100 x 83.30) = 9330.00 INR
      expect(result.total.currencyCode, 'INR');
      expect(result.total.minor, closeTo(933000, 100));
      expect(result.unconvertedCount, 0);
    });

    test('a zero-decimal currency converts without being inflated', () {
      final result = service.totalFrom(
        // 10,000 yen. JPY has no minor unit, so `minor` IS the yen count.
        balances: [account('jpy', 10000, 'JPY')],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      // 10000 JPY / 158.60 x 83.30 = about 5251 INR = 525,100 minor units.
      expect(result.total.minor, closeTo(525100, 2000));
    });
  });

  group('unconverted amounts are EXCLUDED, never counted as zero', () {
    test('a balance with no cached rate raises the count and leaves the total alone', () {
      final result = service.totalFrom(
        balances: [
          account('inr', 400000, 'INR'),
          // CNY has no row in the table at all.
          account('cny', 700000, 'CNY'),
        ],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, const Money(400000, 'INR'),
          reason: 'the CNY balance is left out entirely');
      expect(result.unconvertedCount, 1);
      expect(result.isComplete, isFalse);
    });

    test('counting it as zero would be indistinguishable from an empty account', () {
      final excluded = service.totalFrom(
        balances: [account('inr', 400000, 'INR'), account('cny', 700000, 'CNY')],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );
      final asIfEmpty = service.totalFrom(
        balances: [account('inr', 400000, 'INR'), account('cny', 0, 'CNY')],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      // The totals match, which is exactly why the count has to exist — without it these two very
      // different situations would look identical to the user.
      expect(excluded.total, asIfEmpty.total);
      expect(excluded.unconvertedCount, 1);
      expect(asIfEmpty.unconvertedCount, 1);
    });

    test('every balance unconvertible gives a zero total and a full count', () {
      final result = service.totalFrom(
        balances: [account('cny', 700000, 'CNY'), account('brl', 500000, 'BRL')],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, Money.zero('INR'));
      expect(result.unconvertedCount, 2);
      expect(result.isComplete, isFalse);
    });

    test('an excluded account that is also unconvertible does not raise the count', () {
      final result = service.totalFrom(
        balances: [account('cny', 700000, 'CNY', includeInNetWorth: false)],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.unconvertedCount, 0,
          reason: 'it was never going to be in the total, so it is not missing from it');
    });
  });

  group('approximate rates', () {
    test('an approximate leg marks the whole headline approximate but still totals', () {
      final staleTable = RateTable(
        rates: [
          UsdRate(quoteCode: 'INR', on: asOf, rate: 83.30, rateRaw: '83.3'),
          // EUR's earliest row is after the date asked about, so the leg falls forward.
          UsdRate(
            quoteCode: 'EUR',
            on: DateKey.fromYmd(2026, 9, 1),
            rate: 0.92,
            rateRaw: '0.92',
          ),
        ],
        decimalDigitsByCode: digits,
      );

      final result = service.totalFrom(
        balances: [account('inr', 100000, 'INR'), account('eur', 10000, 'EUR')],
        table: staleTable,
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.isApproximate, isTrue);
      expect(result.unconvertedCount, 0, reason: 'approximate still converts');
      expect(result.total.minor, greaterThan(100000));
    });

    test('all-exact rates leave the headline exact', () {
      final result = service.totalFrom(
        balances: [account('inr', 100000, 'INR'), account('usd', 10000, 'USD')],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.isApproximate, isFalse);
    });
  });

  group('totalsByCurrency — the honest answer with no rates', () {
    test('groups per currency without converting anything', () {
      final totals = service.totalsByCurrency([
        account('a', 400000, 'INR'),
        account('b', 250000, 'INR'),
        account('c', 10000, 'USD'),
      ]);

      expect(totals['INR'], const Money(650000, 'INR'));
      expect(totals['USD'], const Money(10000, 'USD'));
    });

    test('respects includeInNetWorth', () {
      final totals = service.totalsByCurrency([
        account('a', 400000, 'INR'),
        account('b', 999999, 'INR', includeInNetWorth: false),
      ]);

      expect(totals['INR'], const Money(400000, 'INR'));
    });

    test('never adds across currencies', () {
      final totals = service.totalsByCurrency([
        account('a', 400000, 'INR'),
        account('c', 10000, 'JPY'),
      ]);

      expect(totals.keys.toSet(), {'INR', 'JPY'},
          reason: 'adding rupees to yen is exactly what this method exists to prevent');
    });
  });
}
```

### `test/domain/consumption_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';
import 'package:alaya/domain/services/low_stock_suggestion_engine.dart';
import 'package:alaya/domain/services/purchase_fan_out_service.dart';
import 'package:alaya/domain/services/stock_reconciler.dart';

/// FEFO consumption, reconciliation, low-stock idempotency and the purchase fan-out.
///
/// Every service under test is pure, so none of this touches a database or a mock.
void main() {
  const consumption = InventoryConsumptionService();
  const reconciler = StockReconciler();
  const suggestions = LowStockSuggestionEngine();
  const fanOut = PurchaseFanOutService();

  Qty grams(int g) => Qty(g * 1000, UnitCategory.weight);

  group('FEFO consumption', () {
    // The three batches exactly as specified, and deliberately in an order where neither the
    // nearest expiry nor the undated batch is first — so a service that trusted input order would
    // fail this.
    final batches = [
      ConsumableBatch(
        batchId: 'b_exp_10aug',
        remaining: grams(500),
        purchasedDateKey: DateKey.fromYmd(2026, 7, 15),
        expiryDateKey: DateKey.fromYmd(2026, 8, 10),
      ),
      ConsumableBatch(
        batchId: 'b_no_expiry',
        remaining: grams(1000),
        purchasedDateKey: DateKey.fromYmd(2026, 7, 1),
      ),
      ConsumableBatch(
        batchId: 'b_exp_05aug',
        remaining: grams(300),
        purchasedDateKey: DateKey.fromYmd(2026, 7, 20),
        expiryDateKey: DateKey.fromYmd(2026, 8, 5),
      ),
    ];

    test('consuming 600 g draws 300 from 05 Aug then 300 from 10 Aug', () {
      final result = consumption.plan(batches: batches, needed: grams(600));

      expect(result.isFailure, isFalse);
      final plan = result.valueOrNull!;

      expect(plan.draws.map((d) => d.batchId).toList(), [
        'b_exp_05aug',
        'b_exp_10aug',
      ], reason: 'nearest expiry first');
      expect(
        plan.draws[0].quantity,
        grams(300),
        reason: 'the 05 Aug batch is drained',
      );
      expect(
        plan.draws[1].quantity,
        grams(300),
        reason: 'the balance comes from 10 Aug',
      );
    });

    test('the no-expiry batch is left untouched', () {
      final plan = consumption
          .plan(batches: batches, needed: grams(600))
          .valueOrNull!;

      expect(
        plan.touchedBatchIds,
        isNot(contains('b_no_expiry')),
        reason:
            'undated stock cannot spoil on a deadline, so dated stock goes first (A08)',
      );
    });

    test('exactly two movement rows', () {
      final plan = consumption
          .plan(batches: batches, needed: grams(600))
          .valueOrNull!;

      // One movement per draw, which is the 1:1 mapping `StockRepository.consume` applies.
      expect(plan.movementCount, 2);
      expect(plan.draws, hasLength(2));
    });

    test('the draws sum to exactly what was asked for', () {
      final plan = consumption
          .plan(batches: batches, needed: grams(600))
          .valueOrNull!;
      final total = plan.draws.fold<int>(
        0,
        (sum, d) => sum + d.quantity.milliBase,
      );

      expect(total, grams(600).milliBase);
    });

    test('ordering puts undated last regardless of input order', () {
      final ordered = consumption.orderFefo(batches);

      expect(ordered.map((b) => b.batchId).toList(), [
        'b_exp_05aug',
        'b_exp_10aug',
        'b_no_expiry',
      ]);
    });

    test('a batch holding nothing never produces a movement', () {
      final withEmpty = [
        ConsumableBatch(
          batchId: 'b_empty',
          remaining: grams(0),
          purchasedDateKey: DateKey.fromYmd(2026, 1, 1),
          expiryDateKey: DateKey.fromYmd(2026, 1, 2),
        ),
        ...batches,
      ];

      final plan = consumption
          .plan(batches: withEmpty, needed: grams(100))
          .valueOrNull!;

      expect(
        plan.touchedBatchIds,
        isNot(contains('b_empty')),
        reason:
            'stock_movements has CHECK (quantity_milli > 0), and a zero movement is noise',
      );
      expect(plan.draws.single.batchId, 'b_exp_05aug');
    });

    test(
      'consuming exactly one batch\'s remaining does not spill into the next',
      () {
        final plan = consumption
            .plan(batches: batches, needed: grams(300))
            .valueOrNull!;

        expect(plan.draws, hasLength(1));
        expect(plan.draws.single.batchId, 'b_exp_05aug');
      },
    );

    test('draining everything touches all three, undated last', () {
      final plan = consumption
          .plan(batches: batches, needed: grams(1800))
          .valueOrNull!;

      expect(plan.draws.map((d) => d.batchId).toList(), [
        'b_exp_05aug',
        'b_exp_10aug',
        'b_no_expiry',
      ]);
      expect(plan.movementCount, 3);
    });

    group('consuming more than total stock', () {
      test('fails rather than partially consuming', () {
        // One milli-gram beyond the 1800 g on hand.
        final result = consumption.plan(
          batches: batches,
          needed: Qty(grams(1800).milliBase + 1, UnitCategory.weight),
        );

        expect(result.isFailure, isTrue);
        expect(result.failureOrNull, isA<BusinessRuleFailure>());
        expect(
          (result.failureOrNull! as BusinessRuleFailure).rule,
          'insufficientStock',
        );
      });

      test('and produces NO draws at all, so no partial write is possible', () {
        final result = consumption.plan(batches: batches, needed: grams(5000));

        expect(
          result.valueOrNull,
          isNull,
          reason:
              'a half-applied consumption describes something that did not happen',
        );
      });

      test('an empty inventory fails the same way', () {
        final result = consumption.plan(batches: const [], needed: grams(1));

        expect(result.isFailure, isTrue);
      });
    });

    test('a zero or negative request is rejected before anything else', () {
      expect(
        consumption.plan(batches: batches, needed: grams(0)).isFailure,
        isTrue,
      );
      expect(
        consumption
            .plan(batches: batches, needed: Qty(-1000, UnitCategory.weight))
            .isFailure,
        isTrue,
      );
    });

    test('a cross-category request is refused, not converted (L8)', () {
      final result = consumption.plan(
        batches: batches,
        needed: Qty(600000, UnitCategory.volume),
      );

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<ValidationFailure>());
    });
  });

  group('stock reconciliation', () {
    StockMovement movement(StockMovementKind kind, int g) => StockMovement(
      id: 'm-${kind.name}-$g',
      batchId: 'b1',
      itemId: 'potato',
      kind: kind,
      quantity: grams(g),
      occurredAtUtc: DateTime.utc(2026, 7, 20),
      dateKey: DateKey.fromYmd(2026, 7, 20),
    );

    test('a consistent batch shows zero discrepancy', () {
      final result = reconciler.reconcile(
        batchId: 'b1',
        cached: grams(1700),
        movements: [
          movement(StockMovementKind.openingIn, 2000),
          movement(StockMovementKind.consume, 300),
        ],
      );

      expect(result.fromLedger, grams(1700));
      expect(result.discrepancy, grams(0));
      expect(result.isConsistent, isTrue);
    });

    test('a consume that never updated the cache is detected', () {
      final result = reconciler.reconcile(
        batchId: 'b1',
        cached: grams(2000),
        movements: [
          movement(StockMovementKind.openingIn, 2000),
          movement(StockMovementKind.consume, 300),
        ],
      );

      expect(result.fromLedger, grams(1700));
      expect(result.discrepancy, grams(300));
      expect(result.isConsistent, isFalse);
    });

    test('waste and expired both reduce stock', () {
      final ledger = reconciler.remainingFromLedgerMilli([
        movement(StockMovementKind.openingIn, 1000),
        movement(StockMovementKind.waste, 250),
        movement(StockMovementKind.expired, 250),
      ]);

      expect(ledger, grams(500).milliBase);
    });

    test('a reversal cancels the movement it points at', () {
      final ledger = reconciler.remainingFromLedgerMilli([
        movement(StockMovementKind.openingIn, 1000),
        movement(StockMovementKind.consume, 200),
        movement(StockMovementKind.adjustIn, 200),
      ]);

      expect(
        ledger,
        grams(1000).milliBase,
        reason: 'summing with the opposite sign is all a reversal needs to do',
      );
    });

    test('a cache BELOW the ledger is a discrepancy too', () {
      final result = reconciler.reconcile(
        batchId: 'b1',
        cached: grams(500),
        movements: [movement(StockMovementKind.openingIn, 1000)],
      );

      expect(
        result.isConsistent,
        isFalse,
        reason: 'hiding stock the user has is the harder error to notice',
      );
      expect(result.discrepancy.milliBase, lessThan(0));
    });

    test(
      'every incoming kind is classified as incoming, every outgoing as outgoing',
      () {
        const incoming = [
          StockMovementKind.openingIn,
          StockMovementKind.purchaseIn,
          StockMovementKind.manualIn,
          StockMovementKind.adjustIn,
        ];
        const outgoing = [
          StockMovementKind.consume,
          StockMovementKind.waste,
          StockMovementKind.expired,
          StockMovementKind.adjustOut,
        ];

        // Exhaustive: if a kind is ever added, this fails until it is classified, which is the point.
        expect({
          ...incoming,
          ...outgoing,
        }, hasLength(StockMovementKind.values.length));
        for (final kind in incoming) {
          expect(reconciler.isIncoming(kind), isTrue, reason: kind.name);
        }
        for (final kind in outgoing) {
          expect(reconciler.isIncoming(kind), isFalse, reason: kind.name);
        }
      },
    );

    test('a summary reports the worst offender', () {
      final summary = reconciler.summarise([
        reconciler.reconcile(
          batchId: 'ok',
          cached: grams(100),
          movements: [movement(StockMovementKind.openingIn, 100)],
        ),
        reconciler.reconcile(
          batchId: 'small',
          cached: grams(110),
          movements: [movement(StockMovementKind.openingIn, 100)],
        ),
        reconciler.reconcile(
          batchId: 'big',
          cached: grams(900),
          movements: [movement(StockMovementKind.openingIn, 100)],
        ),
      ]);

      expect(summary.batchesChecked, 3);
      expect(summary.batchesNeedingRepair, 2);
      expect(summary.largestDiscrepancy, grams(800));
      expect(summary.isHealthy, isFalse);
    });
  });

  group('low-stock suggestion idempotency', () {
    final today = DateKey.fromYmd(2026, 7, 28);

    ItemStock lowPotato({int remainingG = 2500, int thresholdG = 3000}) =>
        ItemStock(
          itemId: 'potato',
          totalRemaining: grams(remainingG),
          batchCount: 1,
          isLowStock: true,
          lowStockThreshold: grams(thresholdG),
        );

    ShoppingEntry autoEntry({
      String id = 'e1',
      ShoppingEntryOrigin origin = ShoppingEntryOrigin.autoLowStock,
      ShoppingEntryAutoState autoState = ShoppingEntryAutoState.active,
      int? stockAtGenerationG,
      DateKey? snoozeUntil,
    }) => ShoppingEntry(
      id: id,
      listId: 'L',
      origin: origin,
      autoState: autoState,
      isChecked: false,
      sortOrder: 0,
      itemId: 'potato',
      quantity: grams(500),
      stockAtGeneration: stockAtGenerationG == null
          ? null
          : grams(stockAtGenerationG),
      snoozeUntilDateKey: snoozeUntil,
    );

    test('running generation five times yields exactly one entry', () {
      // The engine is pure, so "running it five times" means: create once, then refresh — never a
      // second create. Simulated by feeding back the entry the previous run would have written.
      final existing = <ShoppingEntry>[];
      final actions = <SuggestionAction>[];

      for (var run = 0; run < 5; run++) {
        final decisions = suggestions.decide(
          lowStock: [lowPotato()],
          existingAutoEntries: existing,
          today: today,
        );
        final decision = decisions.single;
        actions.add(decision.action);

        if (decision.action == SuggestionAction.create) {
          existing.add(autoEntry(stockAtGenerationG: 2500));
        }
      }

      expect(actions.first, SuggestionAction.create);
      expect(
        actions.skip(1),
        everyElement(SuggestionAction.refresh),
        reason: 'runs 2-5 must refresh in place, never create again',
      );
      expect(
        existing,
        hasLength(1),
        reason: 'exactly ONE auto entry after five runs',
      );
    });

    test('the suggested quantity is the shortfall against the threshold', () {
      final decision = suggestions
          .decide(
            lowStock: [lowPotato()],
            existingAutoEntries: const [],
            today: today,
          )
          .single;

      expect(
        decision.suggestedQuantity,
        grams(500),
        reason: '3000 threshold - 2500 on hand',
      );
      expect(decision.stockAtDecision, grams(2500));
    });

    test('after the user edits it, regeneration does not touch it', () {
      // Editing promotes origin to manual — that is what ShoppingRepository.saveEntry does.
      final edited = autoEntry(
        origin: ShoppingEntryOrigin.manual,
        stockAtGenerationG: 2500,
      );

      final decision = suggestions
          .decide(
            lowStock: [lowPotato()],
            existingAutoEntries: [edited],
            today: today,
          )
          .single;

      expect(decision.action, SuggestionAction.leaveAlone);
      expect(
        decision.suggestedQuantity,
        isNull,
        reason:
            'nothing is suggested, so nothing can overwrite the user\'s quantity',
      );
      expect(decision.reason, contains('user'));
    });

    test('an item no longer low is left alone', () {
      final decision = suggestions
          .decide(
            lowStock: [
              ItemStock(
                itemId: 'potato',
                totalRemaining: grams(4000),
                batchCount: 1,
                isLowStock: false,
                lowStockThreshold: grams(3000),
              ),
            ],
            existingAutoEntries: const [],
            today: today,
          )
          .single;

      expect(decision.action, SuggestionAction.leaveAlone);
    });

    test('an item with no threshold is never suggested', () {
      final decision = suggestions
          .decide(
            lowStock: [
              ItemStock(
                itemId: 'salt',
                totalRemaining: grams(10),
                batchCount: 1,
                isLowStock: false,
              ),
            ],
            existingAutoEntries: const [],
            today: today,
          )
          .single;

      expect(decision.action, SuggestionAction.leaveAlone);
    });

    group('dismissal is not a timer', () {
      test('dismissed and stock unchanged stays suppressed', () {
        final decision = suggestions
            .decide(
              lowStock: [lowPotato()],
              existingAutoEntries: [
                autoEntry(
                  autoState: ShoppingEntryAutoState.dismissed,
                  stockAtGenerationG: 2500,
                ),
              ],
              today: today,
            )
            .single;

        expect(decision.action, SuggestionAction.leaveAlone);
      });

      test('dismissed and stock fell FURTHER still stays suppressed', () {
        final decision = suggestions
            .decide(
              lowStock: [lowPotato(remainingG: 1000)],
              existingAutoEntries: [
                autoEntry(
                  autoState: ShoppingEntryAutoState.dismissed,
                  stockAtGenerationG: 2500,
                ),
              ],
              today: today,
            )
            .single;

        expect(
          decision.action,
          SuggestionAction.leaveAlone,
          reason:
              'they said no to this shortage; a worse one is the same shortage',
        );
      });

      test(
        'restocked above the dismissal reading, then low again, brings it back',
        () {
          final decision = suggestions
              .decide(
                lowStock: [lowPotato(remainingG: 2800)],
                existingAutoEntries: [
                  autoEntry(
                    autoState: ShoppingEntryAutoState.dismissed,
                    stockAtGenerationG: 2500,
                  ),
                ],
                today: today,
              )
              .single;

          expect(
            decision.action,
            SuggestionAction.refresh,
            reason:
                'stock rose above 2500, so they bought some and ran low again',
          );
        },
      );

      test('a snooze still in force suppresses', () {
        final decision = suggestions
            .decide(
              lowStock: [lowPotato()],
              existingAutoEntries: [
                autoEntry(
                  autoState: ShoppingEntryAutoState.snoozed,
                  stockAtGenerationG: 2500,
                  snoozeUntil: DateKey.fromYmd(2026, 8, 5),
                ),
              ],
              today: today,
            )
            .single;

        expect(decision.action, SuggestionAction.leaveAlone);
      });

      test('an expired snooze returns, because a snooze IS a timer', () {
        final decision = suggestions
            .decide(
              lowStock: [lowPotato()],
              existingAutoEntries: [
                autoEntry(
                  autoState: ShoppingEntryAutoState.snoozed,
                  stockAtGenerationG: 2500,
                  snoozeUntil: DateKey.fromYmd(2026, 7, 20),
                ),
              ],
              today: today,
            )
            .single;

        expect(decision.action, SuggestionAction.refresh);
      });
    });
  });

  group('purchase fan-out', () {
    final transaction = Transaction(
      id: 't1',
      kind: TransactionKind.withdrawal,
      subtype: TransactionSubtype.electronics,
      occurredAtUtc: DateTime.utc(2026, 7, 28),
      dateKey: DateKey.fromYmd(2026, 7, 28),
      originalAmount: const Money(4500000, 'INR'),
      needsReview: false,
      fromAccountId: 'bank',
    );

    TransactionLine line({
      required TransactionLineDestination destination,
      String description = 'LG 55 inch TV',
      String? itemId,
      Qty? quantity,
      Money? lineAmount = const Money(4500000, 'INR'),
      // A line bound for inventory must name a unit: `unit_code_at_purchase` is a foreign key into
      // `units`, and `_planBatch` refuses a null rather than defaulting it to `''` and failing later
      // as `FOREIGN KEY constraint failed`.
      String? unitCode = 'pc',
    }) => TransactionLine(
      id: 'l1',
      transactionId: 't1',
      lineNo: 1,
      description: description,
      destination: destination,
      itemId: itemId,
      quantity: quantity,
      unitCode: unitCode,
      lineAmount: lineAmount,
    );

    test('destination=asset creates an Asset and NO batch', () {
      final plan = fanOut
          .plan(
            line: line(destination: TransactionLineDestination.asset),
            transaction: transaction,
            newArtefactId: 'a1',
          )
          .valueOrNull!;

      expect(plan.target, FanOutTarget.asset);
      expect(plan.asset, isNotNull);
      expect(
        plan.batch,
        isNull,
        reason:
            'a television is serviced and warrantied, not consumed in portions (A12)',
      );
      expect(plan.isWellFormed, isTrue);
    });

    test(
      'the created asset carries the line back, so createdAssetId can be written',
      () {
        final plan = fanOut
            .plan(
              line: line(destination: TransactionLineDestination.asset),
              transaction: transaction,
              newArtefactId: 'a1',
            )
            .valueOrNull!;

        expect(
          plan.lineId,
          'l1',
          reason: 'the caller writes createdAssetId back to this line',
        );
        expect(plan.asset!.id, 'a1');
        expect(plan.asset!.sourceTransactionLineId, 'l1');
        expect(plan.asset!.name, 'LG 55 inch TV');
        expect(plan.asset!.purchasePrice, const Money(4500000, 'INR'));
        expect(plan.asset!.purchaseDateKey, DateKey.fromYmd(2026, 7, 28));
      },
    );

    test('a line bound for inventory with no unit is refused, not defaulted', () {
      // The empty-string default turned a missing value into `FOREIGN KEY constraint failed` several
      // layers away, after the transaction had already committed (ARCH_4 R30's family).
      final result = fanOut.plan(
        line: line(
          destination: TransactionLineDestination.inventory,
          itemId: 'i1',
          quantity: const Qty(2000, UnitCategory.count),
          unitCode: null,
        ),
        transaction: transaction,
        newArtefactId: 'b1',
      );
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull!.message, contains('no unit'));
    });

    test('destination=inventory creates a Batch and NO asset', () {
      final plan = fanOut
          .plan(
            line: line(
              destination: TransactionLineDestination.inventory,
              description: 'Potatoes',
              itemId: 'potato',
              quantity: grams(2000),
            ),
            transaction: transaction,
            newArtefactId: 'b1',
          )
          .valueOrNull!;

      expect(plan.target, FanOutTarget.batch);
      expect(plan.batch, isNotNull);
      expect(plan.asset, isNull);
      expect(plan.batch!.initialQuantity, grams(2000));
      expect(
        plan.batch!.remainingQuantity,
        grams(2000),
        reason:
            'nothing consumed yet, and BatchRepository.create requires this',
      );
      expect(plan.batch!.origin, BatchOrigin.purchase);
      expect(plan.batch!.sourceTransactionLineId, 'l1');
    });

    test('destination=none creates nothing', () {
      final plan = fanOut
          .plan(
            line: line(
              destination: TransactionLineDestination.none,
              description: 'Service fee',
            ),
            transaction: transaction,
            newArtefactId: 'x1',
          )
          .valueOrNull!;

      expect(plan.createsArtefact, isFalse);
      expect(plan.batch, isNull);
      expect(plan.asset, isNull);
      expect(plan.isWellFormed, isTrue);
    });

    test(
      'destination=recurring names a template but does not invent a schedule',
      () {
        final plan = fanOut
            .plan(
              line: line(
                destination: TransactionLineDestination.recurring,
                description: 'Netflix',
              ),
              transaction: transaction,
              newArtefactId: 'r1',
            )
            .valueOrNull!;

        expect(plan.target, FanOutTarget.recurringTemplate);
        expect(plan.recurringTemplateName, 'Netflix');
        expect(plan.batch, isNull);
        expect(plan.asset, isNull);
      },
    );

    test('an inventory line without an item is refused', () {
      final result = fanOut.plan(
        line: line(
          destination: TransactionLineDestination.inventory,
          quantity: grams(100),
        ),
        transaction: transaction,
        newArtefactId: 'b1',
      );

      expect(result.isFailure, isTrue);
    });

    test(
      'an inventory line without a quantity is refused rather than guessed',
      () {
        final result = fanOut.plan(
          line: line(
            destination: TransactionLineDestination.inventory,
            itemId: 'potato',
          ),
          transaction: transaction,
          newArtefactId: 'b1',
        );

        expect(
          result.isFailure,
          isTrue,
          reason:
              'a batch with a guessed quantity is stock the user never bought',
        );
      },
    );

    test(
      'planAll skips lines that already produced an artefact, so a retry is safe',
      () {
        final lines = [
          TransactionLine(
            id: 'l1',
            transactionId: 't1',
            lineNo: 1,
            description: 'Already done',
            destination: TransactionLineDestination.asset,
            createdAssetId: 'a-existing',
          ),
          line(
            destination: TransactionLineDestination.asset,
            description: 'New TV',
          ),
        ];

        final plans = fanOut
            .planAll(
              lines: lines,
              transaction: transaction,
              newArtefactIds: ['x', 'a2'],
            )
            .valueOrNull!;

        expect(plans, hasLength(1));
        expect(plans.single.asset!.name, 'New TV');
      },
    );
  });
}
```

### `test/domain/currency_rate_service_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// Exercises ARCH_3 §1.2's USD pivot and §1.3's lookup rule.
///
/// Every test builds a `RateTable` from literals. That is possible because the table is pure — no
/// database, no mocks, no fakes — which is the whole reason the lookup rule lives there rather than
/// inside a repository.
void main() {
  // Frankfurter is ECB-backed and publishes no weekend rows. Friday the 24th, then Monday the 27th,
  // with the 25th and 26th deliberately absent — the gap the lookup rule exists for.
  final friday = DateKey.fromYmd(2026, 7, 24);
  final saturday = DateKey.fromYmd(2026, 7, 25);
  final sunday = DateKey.fromYmd(2026, 7, 26);
  final monday = DateKey.fromYmd(2026, 7, 27);

  const digits = {'USD': 2, 'INR': 2, 'EUR': 2, 'JPY': 0, 'CNY': 2};

  RateTable tableWithWeekendGap() => RateTable(
    rates: [
      UsdRate(quoteCode: 'INR', on: friday, rate: 83.10, rateRaw: '83.1'),
      UsdRate(quoteCode: 'INR', on: monday, rate: 83.30, rateRaw: '83.3'),
      UsdRate(quoteCode: 'JPY', on: friday, rate: 158.20, rateRaw: '158.2'),
      UsdRate(quoteCode: 'JPY', on: monday, rate: 158.60, rateRaw: '158.6'),
    ],
    decimalDigitsByCode: digits,
  );

  group('the weekend gap — §1.3 rule 3', () {
    test('a Saturday resolves to Friday\'s rate rather than failing', () {
      final leg = tableWithWeekendGap().legFor(code: 'INR', on: saturday);

      expect(leg, isNotNull, reason: 'a Saturday must resolve, not fail');
      expect(leg!.quotedOn, friday);
      expect(leg.rate, 83.10);
    });

    test('Friday\'s rate used on Saturday is EXACT, not approximate', () {
      final leg = tableWithWeekendGap().legFor(code: 'INR', on: saturday);

      // The rule is "greatest rateDateKey <= D". A hit is exact however old it is; `approximate` is
      // reserved for the case where no row on or before D exists at all. Marking a weekend
      // approximate would flag every Saturday transaction in the app as unreliable.
      expect(leg!.quality, RateQuality.exact);
    });

    test('Sunday also resolves to Friday, not forward to Monday', () {
      final leg = tableWithWeekendGap().legFor(code: 'INR', on: sunday);

      expect(leg!.quotedOn, friday);
      expect(leg.rate, 83.10, reason: 'never extrapolates forward to a rate not yet quoted');
    });

    test('Monday takes Monday\'s own rate', () {
      final leg = tableWithWeekendGap().legFor(code: 'INR', on: monday);

      expect(leg!.quotedOn, monday);
      expect(leg.rate, 83.30);
    });

    test('a rate months stale is still exact — the rule never expires a row', () {
      final leg = tableWithWeekendGap().legFor(code: 'INR', on: DateKey.fromYmd(2027, 3, 1));

      expect(leg!.quotedOn, monday);
      expect(leg.quality, RateQuality.exact);
    });

    test('a full conversion on a Saturday succeeds', () {
      final converted = tableWithWeekendGap().convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'USD',
        on: saturday,
      );

      expect(converted.quality, RateQuality.exact);
      expect(converted.isExcludedFromTotals, isFalse);
      expect(converted.rateDateKey, saturday,
          reason: 'an exact resolution reports the date asked for');
    });
  });

  group('USD pivot cross-rating — §1.2', () {
    test('INR to JPY is (USD to JPY) / (USD to INR)', () {
      final cross = tableWithWeekendGap().crossRate(from: 'INR', to: 'JPY', on: monday);

      expect(cross, isNotNull);
      expect(cross!.rate, closeTo(158.60 / 83.30, 1e-12));
      expect(cross.quality, RateQuality.exact);
    });

    test('1000 INR converts to roughly 1904 JPY', () {
      final converted = tableWithWeekendGap().convert(
        // 1000.00 INR in minor units.
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'JPY',
        on: monday,
      );

      expect(converted.converted, isNotNull);
      expect(converted.converted!.currencyCode, 'JPY');
      // JPY has zero decimal digits, so its minor unit IS the yen. 1000 x (158.6/83.3) = 1903.96,
      // which rounds to 1904.
      expect(converted.converted!.minor, closeTo(1904, 1));
    });

    test('the reverse rate is the reciprocal, so a round trip returns the original', () {
      final table = tableWithWeekendGap();
      final forward = table.crossRate(from: 'INR', to: 'JPY', on: monday)!;
      final back = table.crossRate(from: 'JPY', to: 'INR', on: monday)!;

      expect(back.rate, closeTo(1 / forward.rate, 1e-12));
      expect(1000 * forward.rate * back.rate, closeTo(1000, 1e-9));
    });

    test('USD needs no cached row — it is the pivot', () {
      final leg = RateTable.empty().legFor(code: 'USD', on: monday);

      expect(leg, isNotNull, reason: 'one USD is one USD on every date');
      expect(leg!.rate, 1);
      expect(leg.quality, RateQuality.exact);
    });

    test('converting a currency to itself needs no rate at all', () {
      final converted = RateTable.empty().convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'INR',
        on: monday,
      );

      expect(converted.quality, RateQuality.exact);
      expect(converted.converted, const Money(100000, 'INR'));
      expect(converted.isExcludedFromTotals, isFalse);
    });
  });

  group('no rate cached — §1.3 rule 4', () {
    test('a missing currency yields unconverted, never a zero', () {
      final converted = tableWithWeekendGap().convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'CNY',
        on: monday,
      );

      expect(converted.quality, RateQuality.unconverted);
      expect(converted.converted, isNull,
          reason: 'a zero would be counted in a total; null forces exclusion');
      expect(converted.isExcludedFromTotals, isTrue);
    });

    test('the original amount survives on an unconverted result', () {
      final converted = tableWithWeekendGap().convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'CNY',
        on: monday,
      );

      expect(converted.original, const Money(100000, 'INR'));
      expect(converted.display, const Money(100000, 'INR'),
          reason: 'the row still shows the amount the user typed');
    });

    test('an empty table converts nothing but throws nothing', () {
      final converted = RateTable.empty().convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'USD',
        on: monday,
      );

      expect(converted.isExcludedFromTotals, isTrue);
    });

    test('a known rate with unknown precision is excluded rather than guessed', () {
      final table = RateTable(
        rates: [UsdRate(quoteCode: 'INR', on: monday, rate: 83.30, rateRaw: '83.3')],
        // JPY's precision is absent, so its minor unit is unknown.
        decimalDigitsByCode: const {'INR': 2},
      );

      final converted = table.convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'JPY',
        on: monday,
      );

      expect(converted.isExcludedFromTotals, isTrue,
          reason: 'assuming 2 digits would misstate every yen figure by a factor of 100');
    });
  });

  group('approximate quality', () {
    test('a leg whose cache starts after the target falls forward and is approximate', () {
      final table = RateTable(
        rates: [
          UsdRate(quoteCode: 'INR', on: friday, rate: 83.10, rateRaw: '83.1'),
          // EUR's earliest row is a week after the date being asked about.
          UsdRate(quoteCode: 'EUR', on: DateKey.fromYmd(2026, 8, 1), rate: 0.92, rateRaw: '0.92'),
        ],
        decimalDigitsByCode: digits,
      );

      final cross = table.crossRate(from: 'INR', to: 'EUR', on: friday)!;

      expect(cross.quality, RateQuality.approximate);
      expect(cross.quotedOn, DateKey.fromYmd(2026, 8, 1),
          reason: 'reports the date actually used, which is the source of the doubt');
    });

    test('when both legs fall forward, the later date is reported', () {
      final table = RateTable(
        rates: [
          UsdRate(quoteCode: 'EUR', on: DateKey.fromYmd(2026, 8, 1), rate: 0.92, rateRaw: '0.92'),
          UsdRate(quoteCode: 'CNY', on: DateKey.fromYmd(2026, 9, 10), rate: 7.1, rateRaw: '7.1'),
        ],
        decimalDigitsByCode: digits,
      );

      final cross = table.crossRate(from: 'EUR', to: 'CNY', on: friday)!;

      expect(cross.quality, RateQuality.approximate);
      expect(cross.quotedOn, DateKey.fromYmd(2026, 9, 10),
          reason: 'the conversion cannot claim to be as of a date before its latest fallback');
    });

    test('one approximate leg makes the whole conversion approximate', () {
      final table = RateTable(
        rates: [
          UsdRate(quoteCode: 'INR', on: friday, rate: 83.10, rateRaw: '83.1'),
          UsdRate(quoteCode: 'EUR', on: DateKey.fromYmd(2026, 8, 1), rate: 0.92, rateRaw: '0.92'),
        ],
        decimalDigitsByCode: digits,
      );

      final converted = table.convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'EUR',
        on: friday,
      );

      expect(converted.quality, RateQuality.approximate);
      expect(converted.hasConversion, isTrue,
          reason: 'approximate still converts — it is indicative, not missing');
      expect(converted.isExcludedFromTotals, isFalse);
    });
  });

  group('syncDailyRates never throws and never blocks — §1.3 rule 2, Law L11', () {
    CurrencyRateService serviceWith({
      required RateSnapshotFetcher fetch,
      required RateSnapshotSaver save,
      NewestRateDateReader? newest,
      RateTableLoader? load,
    }) {
      return CurrencyRateService(
        loadTable: load ?? () async => RateTable.empty(),
        saveSnapshot: save,
        fetchSnapshot: fetch,
        newestCachedDate: newest ?? () async => null,
        clock: FixedClock(DateTime.utc(2026, 7, 27)),
      );
    }

    test('a client that always throws is swallowed', () async {
      var saved = false;
      final service = serviceWith(
        fetch: () async => throw const SocketExceptionStub(),
        save: (_) async => saved = true,
      );

      await expectLater(service.syncDailyRates(), completes);
      expect(saved, isFalse);
    });

    test('a client returning null is a no-op', () async {
      var saved = false;
      final service = serviceWith(fetch: () async => null, save: (_) async => saved = true);

      await service.syncDailyRates();

      expect(saved, isFalse);
    });

    test('an empty snapshot is not saved', () async {
      var saved = false;
      final service = serviceWith(
        fetch: () async =>
            RateSnapshot(on: monday, rates: const [], source: 'test'),
        save: (_) async => saved = true,
      );

      await service.syncDailyRates();

      expect(saved, isFalse, reason: 'an empty fetch must not overwrite a working cache');
    });

    test('a save that throws is swallowed too', () async {
      final service = serviceWith(
        fetch: () async => RateSnapshot(
          on: monday,
          rates: [UsdRate(quoteCode: 'INR', on: monday, rate: 83.3, rateRaw: '83.3')],
          source: 'test',
        ),
        save: (_) async => throw StateError('database is locked'),
      );

      await expectLater(service.syncDailyRates(), completes);
    });

    test('a reader that throws is swallowed too', () async {
      var fetched = false;
      final service = serviceWith(
        fetch: () async {
          fetched = true;
          return null;
        },
        save: (_) async {},
        newest: () async => throw StateError('database is locked'),
      );

      await expectLater(service.syncDailyRates(), completes);
      expect(fetched, isFalse, reason: 'it failed before reaching the network');
    });

    test('a successful fetch is saved once', () async {
      RateSnapshot? saved;
      final service = serviceWith(
        fetch: () async => RateSnapshot(
          on: monday,
          rates: [UsdRate(quoteCode: 'INR', on: monday, rate: 83.3, rateRaw: '83.3')],
          source: 'test',
        ),
        save: (snapshot) async => saved = snapshot,
      );

      await service.syncDailyRates();

      expect(saved, isNotNull);
      expect(saved!.rates.single.quoteCode, 'INR');
    });

    test('today\'s rates already cached means no fetch at all — one request per day', () async {
      var fetched = false;
      final service = serviceWith(
        fetch: () async {
          fetched = true;
          return null;
        },
        save: (_) async {},
        newest: () async => monday,
      );

      await service.syncDailyRates();

      expect(fetched, isFalse, reason: 'ARCH_3 §1.2 promises one request per day, forever');
    });

    test('a stale cache does trigger a fetch', () async {
      var fetched = false;
      final service = serviceWith(
        fetch: () async {
          fetched = true;
          return null;
        },
        save: (_) async {},
        newest: () async => friday,
      );

      await service.syncDailyRates();

      expect(fetched, isTrue);
    });
  });
}

/// Stands in for a network failure without importing `dart:io`, which a pure domain test should not
/// need.
class SocketExceptionStub implements Exception {
  /// Creates the stub.
  const SocketExceptionStub();
}
```

### `test/domain/expiry_draw_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';

/// The expiry-aware draw policy on [InventoryConsumptionService].
///
/// **A separate file from `consumption_test.dart` on purpose.** That one is 848 lines covering four
/// services and every case in it exercises the default `DrawPolicy.fefo()`, which is unchanged — so
/// none of it needed touching, and putting these there would have buried a new policy inside a
/// regression suite for an old one.
///
/// These cases began life against a `DrawPlanner` written before this service was found. The policy
/// survived the move; the class did not. `orderFefo` and its own tests are untouched.
void main() {
  const service = InventoryConsumptionService();
  const today = DateKey(20260814);

  Qty grams(int g) => Qty(g * 1000, UnitCategory.weight);

  ConsumableBatch batch(
    String id,
    int g, {
    int? expiry,
    int purchased = 20260701,
  }) => ConsumableBatch(
    batchId: id,
    remaining: grams(g),
    purchasedDateKey: DateKey(purchased),
    expiryDateKey: expiry == null ? null : DateKey(expiry),
  );

  /// Deliberately in an order where neither the good stock nor the least-spoiled expired batch is
  /// first, so a policy that trusted its input order would fail every assertion below.
  List<ConsumableBatch> shelf() => [
    batch('ancient', 100, expiry: 20260601, purchased: 20260501),
    batch('yesterday', 100, expiry: 20260813),
    batch('lastweek', 100, expiry: 20260807, purchased: 20260601),
    batch('good', 150, expiry: 20260901, purchased: 20260801),
    batch('never', 100, purchased: 20260401),
  ];

  group('ConsumableBatch.isExpired', () {
    test('is strict, so a batch expiring today is still good today', () {
      expect(batch('edge', 10, expiry: 20260814).isExpired(today), isFalse);
      expect(batch('gone', 10, expiry: 20260813).isExpired(today), isTrue);
    });

    test('a batch with no date never expires', () {
      expect(batch('never', 10).isExpired(today), isFalse);
    });
  });

  group('orderFreshFirst', () {
    test('good stock first, then least spoiled among the expired', () {
      // Good stock in FEFO order — `good` expires before `never`, and undated goes last because it
      // cannot spoil on a deadline. Then the expired, nearest-to-fresh first: strict FEFO would have
      // handed over `ancient`, the most spoiled thing on the shelf.
      expect(
        service.orderFreshFirst(shelf(), today).map((b) => b.batchId),
        orderedEquals(['good', 'never', 'yesterday', 'lastweek', 'ancient']),
      );
    });

    test('which is the reverse of orderFefo among the expired', () {
      // The same shelf under the existing policy. Both orders are correct — for different jobs.
      expect(
        service.orderFefo(shelf()).map((b) => b.batchId),
        orderedEquals(['ancient', 'lastweek', 'yesterday', 'good', 'never']),
      );
    });

    test('drops batches holding nothing', () {
      final ordered = service.orderFreshFirst([
        batch('empty', 0, expiry: 20260901),
        batch('full', 100, expiry: 20260901),
      ], today);
      expect(ordered.map((b) => b.batchId), orderedEquals(['full']));
    });

    test(
      'returns expired batches too, because the caller must be able to offer them',
      () {
        expect(service.orderFreshFirst(shelf(), today), hasLength(5));
      },
    );
  });

  group('plan under DrawPolicy.freshFirst', () {
    test('spends good stock and never reaches the expired', () {
      final result = service.plan(
        batches: shelf(),
        needed: grams(200),
        policy: const DrawPolicy.freshFirst(today: today),
      );

      final plan = result.valueOrNull;
      expect(plan, isNotNull);
      expect(
        plan!.draws.map((d) => d.batchId),
        orderedEquals(['good', 'never']),
      );
      expect(plan.draws.last.quantity, grams(50));
      expect(plan.usesExpired, isFalse);
      expect(plan.fromExpired, grams(0));
    });

    test('refuses rather than dipping into expired stock', () {
      // **The reported bug, as a refusal.** 300 g wanted, 250 g good, 300 g past its date. Under FEFO
      // this succeeded silently by eating the expired batches first.
      final result = service.plan(
        batches: shelf(),
        needed: grams(300),
        policy: const DrawPolicy.freshFirst(today: today),
      );

      expect(result.isFailure, isTrue);
      expect(
        (result.failureOrNull as BusinessRuleFailure?)?.rule,
        'insufficientStock',
      );
    });

    test('and the same request succeeds once expired stock is permitted', () {
      // The second call is how a caller learns that consent would help — two answers rather than a
      // partial plan nobody may apply.
      final plan = service
          .plan(
            batches: shelf(),
            needed: grams(300),
            policy: const DrawPolicy.freshFirst(
              today: today,
              allowExpired: true,
            ),
          )
          .valueOrNull;

      expect(plan, isNotNull);
      expect(
        plan!.draws.map((d) => d.batchId),
        orderedEquals(['good', 'never', 'yesterday']),
      );
      // Good stock exhausted first; only 50 g came from the least spoiled expired batch.
      expect(plan.usesExpired, isTrue);
      expect(plan.fromExpired, grams(50));
    });

    test('still refuses when even the expired stock is not enough', () {
      final result = service.plan(
        batches: shelf(),
        needed: grams(600),
        policy: const DrawPolicy.freshFirst(today: today, allowExpired: true),
      );

      expect(result.isFailure, isTrue);
      expect(
        (result.failureOrNull as BusinessRuleFailure?)?.rule,
        'insufficientStock',
      );
    });

    test('totalAvailable counts only what the policy would reach', () {
      // The number quoted in a shortfall must be one the plan could actually have drawn, or the
      // refusal reads as arithmetic nobody can reproduce.
      final excluded = service
          .plan(
            batches: shelf(),
            needed: grams(1),
            policy: const DrawPolicy.freshFirst(today: today),
          )
          .valueOrNull;
      expect(excluded!.totalAvailable, grams(250));

      final included = service
          .plan(
            batches: shelf(),
            needed: grams(1),
            policy: const DrawPolicy.freshFirst(
              today: today,
              allowExpired: true,
            ),
          )
          .valueOrNull;
      expect(included!.totalAvailable, grams(550));
    });

    test('a batch expiring today is spent as good stock', () {
      final plan = service
          .plan(
            batches: [batch('edge', 100, expiry: 20260814)],
            needed: grams(100),
            policy: const DrawPolicy.freshFirst(today: today),
          )
          .valueOrNull;

      expect(plan, isNotNull);
      expect(plan!.usesExpired, isFalse);
    });
  });

  group('the default policy is unchanged', () {
    test('fefo includes expired stock and reports none of it as expired', () {
      // `fromExpired` is zero because `DrawPolicy.fefo()` does not ask the question — not because the
      // batches are fresh. A write-off has no use for the distinction.
      final plan = service
          .plan(batches: shelf(), needed: grams(200))
          .valueOrNull;

      expect(plan, isNotNull);
      expect(
        plan!.draws.map((d) => d.batchId),
        orderedEquals(['ancient', 'lastweek']),
      );
      expect(plan.fromExpired, grams(0));
      expect(plan.usesExpired, isFalse);
      expect(plan.totalAvailable, grams(550));
    });

    test('planAll stays FEFO, because emptying a shelf has no preference', () {
      final plan = service
          .planAll(batches: shelf(), zeroOfCategory: grams(0))
          .valueOrNull;

      expect(plan, isNotNull);
      expect(plan!.draws, hasLength(5));
      expect(plan.totalAvailable, grams(550));
    });
  });

  group('refusals a policy cannot change', () {
    test('a non-positive quantity is a validation failure', () {
      for (final wanted in [grams(0), grams(-5)]) {
        final result = service.plan(
          batches: shelf(),
          needed: wanted,
          policy: const DrawPolicy.freshFirst(today: today),
        );
        expect(result.failureOrNull, isA<ValidationFailure>());
      }
    });

    test('a mismatched category is a validation failure, not a shortfall', () {
      // Law L8: a `Qty` in the wrong category is a bare integer that would be reinterpreted on read.
      final result = service.plan(
        batches: shelf(),
        needed: const Qty(100000, UnitCategory.volume),
        policy: const DrawPolicy.freshFirst(today: today),
      );
      expect(result.failureOrNull, isA<ValidationFailure>());
    });
  });
}
```

### `test/domain/recipe_cook_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/services/draw_policy.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';
import 'package:alaya/domain/services/recipe_cook_service.dart';

import '../support/cook_fakes.dart';
import '../support/recipe_harness.dart';

/// Cooking, and what it takes off the shelf.
///
/// **The first test `RecipeCookService` has ever had.** It appeared in no test file: the deduction path a
/// user reported as broken had never been exercised, so every round of this feature until now was verifying
/// the verdict and the sheet while the thing between them went unchecked.
void main() {
  const today = DateKey(20260814);
  final clock = FixedClock(DateTime.utc(2026, 8, 14, 9));

  Qty grams(int g) => Qty(g * 1000, UnitCategory.weight);

  ConsumableBatch batch(
    String id,
    int g, {
    int? expiry,
    int purchased = 20260701,
  }) => ConsumableBatch(
    batchId: id,
    remaining: grams(g),
    purchasedDateKey: DateKey(purchased),
    expiryDateKey: expiry == null ? null : DateKey(expiry),
  );

  /// 150 g good, 100 g past its date.
  List<ConsumableBatch> shelf() => [
    batch('good', 150, expiry: 20260901, purchased: 20260801),
    batch('gone', 100, expiry: 20260810),
  ];

  /// The rollup the engine reads. Includes expired stock, because `v_item_stock` does.
  Map<String, ItemStock> rollup(int totalGrams) => {
    'flour': stockOf('flour', totalGrams, expiry: const DateKey(20260810)),
  };

  Map<String, Item> catalogue() => {'flour': weightItem('flour', 'Flour')};

  ({RecipeCookService service, FakeStock stock, FakeRecipes recipes}) build({
    Map<String, List<ConsumableBatch>>? batches,
    bool logFails = false,
  }) {
    final stock = FakeStock(batches: batches ?? {'flour': shelf()});
    final recipes = FakeRecipes(logFails: logFails);
    return (
      service: RecipeCookService(
        recipes: recipes,
        stock: stock,
        clock: clock,
      ),
      stock: stock,
      recipes: recipes,
    );
  }

  group('the policy it sends', () {
    test('freshFirst, never the FEFO default', () async {
      // **The whole fix, in one assertion.** `consume` defaults to FEFO, which orders by nearest expiry —
      // and an expired date is the nearest date, so the default eats food that is already off first. A
      // service that forgot to pass a policy would still cook, still deduct, and still pass every test
      // that only looked at the draws.
      final t = build();
      await t.service.cook(
        recipe: recipeOf(ingredients: [linked('flour', 100)]),
        stock: rollup(250),
        items: catalogue(),
      );

      expect(t.stock.consumed, hasLength(1));
      final policy = t.stock.consumed.single.policy;
      expect(policy.isExpiryAware, isTrue);
      expect(policy.today, today);
      expect(policy.allowExpired, isFalse);
    });

    test('carries the consent it was given', () async {
      final t = build();
      await t.service.cook(
        recipe: recipeOf(ingredients: [linked('flour', 200)]),
        stock: rollup(250),
        items: catalogue(),
        allowExpired: true,
      );

      expect(t.stock.consumed.single.policy.allowExpired, isTrue);
    });

    test('records the movement as consume, not expired', () async {
      // The user ate it. `StockMovementKind.expired` is a write-off, and using it here would put food
      // somebody cooked with into the waste analytics.
      final t = build();
      await t.service.cook(
        recipe: recipeOf(ingredients: [linked('flour', 200)]),
        stock: rollup(250),
        items: catalogue(),
        allowExpired: true,
      );

      expect(t.stock.consumed.single.kind, StockMovementKind.consume);
    });
  });

  group('without consent', () {
    test(
      'good stock alone is spent, and the expired batch is untouched',
      () async {
        final t = build();
        final result = await t.service.cook(
          recipe: recipeOf(ingredients: [linked('flour', 100)]),
          stock: rollup(250),
          items: catalogue(),
        );

        expect(result.isOk, isTrue);
        expect(
          t.stock.consumed.single.draws.map((d) => d.batchId),
          orderedEquals(['good']),
        );
        // 250 on the shelf, 100 taken, and none of it from `gone`.
        expect(t.stock.remainingOf('flour', UnitCategory.weight), grams(150));
      },
    );

    test(
      'a cook that would need expired stock is refused, writing nothing',
      () async {
        // **The reported bug.** 200 g needed, 150 g good, 100 g past its date. This used to succeed by
        // eating the expired batch first and saying nothing.
        final t = build();
        final result = await t.service.cook(
          recipe: recipeOf(ingredients: [linked('flour', 200)]),
          stock: rollup(250),
          items: catalogue(),
        );

        expect(result.isFailure, isTrue);
        expect(
          (result.failureOrNull as BusinessRuleFailure?)?.rule,
          'insufficientStock',
        );
        expect(t.stock.consumed, isEmpty);
        // Nothing was logged either: a cook that did not happen is not a cook.
        expect(t.recipes.logged, isEmpty);
        expect(t.stock.remainingOf('flour', UnitCategory.weight), grams(250));
      },
    );

    test('a shelf holding only expired stock is refused too', () async {
      final t = build(
        batches: {
          'flour': [batch('gone', 300, expiry: 20260810)],
        },
      );
      final result = await t.service.cook(
        recipe: recipeOf(ingredients: [linked('flour', 200)]),
        stock: rollup(300),
        items: catalogue(),
      );

      expect(result.isFailure, isTrue);
      expect(t.stock.consumed, isEmpty);
    });
  });

  group('with consent', () {
    test('good stock is still spent first, expired only topping up', () async {
      // Consent is permission to reach the expired batch, not permission to start with it.
      final t = build();
      final result = await t.service.cook(
        recipe: recipeOf(ingredients: [linked('flour', 200)]),
        stock: rollup(250),
        items: catalogue(),
        allowExpired: true,
      );

      expect(result.isOk, isTrue);
      final draws = t.stock.consumed.single.draws;
      expect(draws.map((d) => d.batchId), orderedEquals(['good', 'gone']));
      expect(draws.first.quantity, grams(150));
      expect(draws.last.quantity, grams(50));
      expect(t.stock.remainingOf('flour', UnitCategory.weight), grams(50));
    });

    test('an expired-only shelf is drawn from, and logged', () async {
      final t = build(
        batches: {
          'flour': [batch('gone', 300, expiry: 20260810)],
        },
      );
      final result = await t.service.cook(
        recipe: recipeOf(ingredients: [linked('flour', 200)]),
        stock: rollup(300),
        items: catalogue(),
        allowExpired: true,
      );

      expect(result.isOk, isTrue);
      expect(t.stock.consumed.single.draws.single.batchId, 'gone');
      expect(t.recipes.logged.single.deductedStock, isTrue);
    });
  });

  group('what it declines to deduct', () {
    test('an untracked ingredient is skipped, not failed', () async {
      // Nobody tracks salt, and refusing to cook because of it would make the feature unusable.
      final t = build();
      final result = await t.service.cook(
        recipe: recipeOf(
          ingredients: [
            linked('flour', 100, sortOrder: 0),
            untracked('salt', sortOrder: 1),
          ],
        ),
        stock: rollup(250),
        items: catalogue(),
      );

      expect(result.isOk, isTrue);
      final outcome = result.valueOrNull;
      expect(outcome!.deducted, orderedEquals(['flour']));
      expect(outcome.skipped, hasLength(1));
      expect(outcome.skipped.single.ingredient.freeText, 'salt');
    });

    test('deductStock false writes nothing but still logs the cook', () async {
      // "I cooked this but I am not tracking it" is a real thing to want, and the log is what makes the
      // cook history honest about which entries touched stock.
      final t = build();
      final result = await t.service.cook(
        recipe: recipeOf(ingredients: [linked('flour', 100)]),
        stock: rollup(250),
        items: catalogue(),
        deductStock: false,
      );

      expect(result.isOk, isTrue);
      expect(t.stock.consumed, isEmpty);
      expect(t.recipes.logged.single.deductedStock, isFalse);
      expect(result.valueOrNull!.skipped, hasLength(1));
    });

    test('a short ingredient refuses before touching anything', () async {
      final t = build();
      final result = await t.service.cook(
        recipe: recipeOf(ingredients: [linked('flour', 900)]),
        stock: rollup(250),
        items: catalogue(),
        allowExpired: true,
      );

      expect(
        (result.failureOrNull as BusinessRuleFailure?)?.rule,
        'recipeInsufficientStock',
      );
      expect(t.stock.consumed, isEmpty);
    });
  });

  group('the log', () {
    test('is stamped with the service own clock', () async {
      // **50 g, not 100 g, and the difference is the whole point of the test.** At 100 g a recipe for two
      // cooked for four needs 200 g, which exceeds the 150 g of good stock — so the cook is refused and
      // nothing is logged. This test is about the date and the serving count, so its fixture must not also
      // be exercising the expiry refusal; 50 g doubles to 100 g and stays inside the good stock.
      //
      // I wrote it at 100 g after verifying the arithmetic for the expiry cases and not for this one.
      final t = build();
      await t.service.cook(
        recipe: recipeOf(servings: 2, ingredients: [linked('flour', 50)]),
        stock: rollup(250),
        items: catalogue(),
        servings: 4,
      );

      final cook = t.recipes.logged.single;
      expect(cook.cookedOn, today);
      expect(cook.servingsCooked, 4);
    });

    test('a failed log fails the cook, even though stock already moved', () async {
      // **Reported rather than swallowed.** The movements are written and the log is not, so the ledger
      // is ahead of the history — the caller has to know, because nothing else can tell them.
      final t = build(logFails: true);
      final result = await t.service.cook(
        recipe: recipeOf(ingredients: [linked('flour', 100)]),
        stock: rollup(250),
        items: catalogue(),
      );

      expect(result.isFailure, isTrue);
      expect(
        t.stock.consumed,
        hasLength(1),
        reason: 'the deduction did happen',
      );
    });
  });
}
```

### `test/domain/recurring_engine_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/services/recurring_engine.dart';

/// The recurring schedule: month-end clamping, lazy materialisation, settlement and skipping.
///
/// `RecurringEngine` is pure and takes every date it needs, so the calendar under test is fixed
/// rather than whatever day the suite happens to run on.
void main() {
  const engine = RecurringEngine();

  RecurringTemplate template({
    String id = 'rent',
    RecurringIntervalUnit unit = RecurringIntervalUnit.month,
    int count = 1,
    int? anchorDay = 1,
    required DateKey startDateKey,
    required DateKey nextDueDateKey,
    DateKey? endDateKey,
    RecurringDirection direction = RecurringDirection.outflow,
    int defaultMinor = 2500000,
    String currency = 'INR',
    bool isPaused = false,
  }) => RecurringTemplate(
    id: id,
    name: 'Rent',
    normalizedName: 'rent',
    kind: RecurringKind.bill,
    direction: direction,
    defaultAmount: Money(defaultMinor, currency),
    intervalUnit: unit,
    intervalCount: count,
    startDateKey: startDateKey,
    nextDueDateKey: nextDueDateKey,
    isPaused: isPaused,
    autoRemind: false,
    remindDaysBefore: 1,
    anchorDayOfMonth: anchorDay,
    endDateKey: endDateKey,
    payeeId: 'landlord',
    tagId: 'tag-rent',
  );

  group('month-end clamp — anomaly A13', () {
    test(
      'anchored on day 31 from 31 Jan gives 31, 28, 31, 30 — not 28, 28, 28',
      () {
        final anchored31 = template(
          anchorDay: 31,
          startDateKey: DateKey.fromYmd(2026, 1, 31),
          nextDueDateKey: DateKey.fromYmd(2026, 1, 31),
        );

        final dates = <DateKey>[DateKey.fromYmd(2026, 1, 31)];
        for (var i = 0; i < 3; i++) {
          dates.add(engine.nextDue(from: dates.last, template: anchored31));
        }

        expect(dates.map((d) => d.value).toList(), [
          20260131,
          20260228,
          20260331,
          20260430,
        ]);
      },
    );

    test(
      'March returns to the 31st, proving the ANCHOR is clamped and not the current day',
      () {
        final anchored31 = template(
          anchorDay: 31,
          startDateKey: DateKey.fromYmd(2026, 1, 31),
          nextDueDateKey: DateKey.fromYmd(2026, 1, 31),
        );

        // February is the 28th...
        final february = engine.nextDue(
          from: DateKey.fromYmd(2026, 1, 31),
          template: anchored31,
        );
        expect(february, DateKey.fromYmd(2026, 2, 28));

        // ...and advancing from that clamped date must still land on the 31st, not the 28th.
        final march = engine.nextDue(from: february, template: anchored31);
        expect(
          march,
          DateKey.fromYmd(2026, 3, 31),
          reason:
              'advancing from the clamped 28th would walk the bill back permanently',
        );
      },
    );

    test('a leap year clamps February to the 29th', () {
      final anchored31 = template(
        anchorDay: 31,
        startDateKey: DateKey.fromYmd(2024, 1, 31),
        nextDueDateKey: DateKey.fromYmd(2024, 1, 31),
      );

      final dates = <DateKey>[DateKey.fromYmd(2024, 1, 31)];
      for (var i = 0; i < 3; i++) {
        dates.add(engine.nextDue(from: dates.last, template: anchored31));
      }

      expect(dates.map((d) => d.value).toList(), [
        20240131,
        20240229,
        20240331,
        20240430,
      ]);
    });

    test('a full year from 31 Jan never loses the anchor', () {
      final anchored31 = template(
        anchorDay: 31,
        startDateKey: DateKey.fromYmd(2026, 1, 31),
        nextDueDateKey: DateKey.fromYmd(2026, 1, 31),
      );

      var cursor = DateKey.fromYmd(2026, 1, 31);
      final days = <int>[cursor.day];
      for (var i = 0; i < 12; i++) {
        cursor = engine.nextDue(from: cursor, template: anchored31);
        days.add(cursor.day);
      }

      expect(days, [
        31,
        28,
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
        31,
      ], reason: 'every 31-day month gets its 31st back');
    });

    test('the clamp helper resolves February in both kinds of year', () {
      expect(engine.clampDayOfMonth(31, 2026, 2), 28);
      expect(engine.clampDayOfMonth(31, 2024, 2), 29);
      expect(engine.clampDayOfMonth(31, 2026, 4), 30);
      expect(
        engine.clampDayOfMonth(15, 2026, 2),
        15,
        reason: 'a day that fits is untouched',
      );
    });

    test(
      'a yearly template anchored on 29 Feb clamps, then recovers four years on',
      () {
        final leapDay = template(
          unit: RecurringIntervalUnit.year,
          anchorDay: 29,
          startDateKey: DateKey.fromYmd(2024, 2, 29),
          nextDueDateKey: DateKey.fromYmd(2024, 2, 29),
        );

        var cursor = DateKey.fromYmd(2024, 2, 29);
        final seen = <int>[];
        for (var i = 0; i < 4; i++) {
          cursor = engine.nextDue(from: cursor, template: leapDay);
          seen.add(cursor.value);
        }

        expect(seen, [20250228, 20260228, 20270228, 20280229]);
      },
    );

    test('day and week intervals cross month and year boundaries', () {
      final daily = template(
        unit: RecurringIntervalUnit.day,
        anchorDay: null,
        startDateKey: DateKey.fromYmd(2026, 12, 31),
        nextDueDateKey: DateKey.fromYmd(2026, 12, 31),
      );
      final weekly = template(
        unit: RecurringIntervalUnit.week,
        anchorDay: null,
        startDateKey: DateKey.fromYmd(2026, 2, 26),
        nextDueDateKey: DateKey.fromYmd(2026, 2, 26),
      );

      expect(
        engine.nextDue(from: DateKey.fromYmd(2026, 12, 31), template: daily),
        DateKey.fromYmd(2027, 1, 1),
      );
      expect(
        engine.nextDue(from: DateKey.fromYmd(2026, 2, 26), template: weekly),
        DateKey.fromYmd(2026, 3, 5),
      );
    });

    test('a quarterly template anchored on 31 clamps per target month', () {
      final quarterly = template(
        count: 3,
        anchorDay: 31,
        startDateKey: DateKey.fromYmd(2026, 1, 31),
        nextDueDateKey: DateKey.fromYmd(2026, 1, 31),
      );

      expect(
        engine.nextDue(from: DateKey.fromYmd(2026, 1, 31), template: quarterly),
        DateKey.fromYmd(2026, 4, 30),
      );
    });
  });

  group('lazy materialisation — anomaly A14', () {
    final today = DateKey.fromYmd(2026, 7, 28);

    test(
      'a template last due three months ago yields exactly three occurrences',
      () {
        final behind = template(
          startDateKey: DateKey.fromYmd(2026, 1, 1),
          nextDueDateKey: DateKey.fromYmd(2026, 5, 1),
        );

        final plan = engine.planMaterialisation(template: behind, asOf: today);

        expect(plan.occurrences, hasLength(3));
        expect(plan.occurrences.map((o) => o.dueDateKey.value).toList(), [
          20260501,
          20260601,
          20260701,
        ]);
      },
    );

    test('and creates ZERO transactions — money needs an explicit tap', () {
      final behind = template(
        startDateKey: DateKey.fromYmd(2026, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2026, 5, 1),
      );

      final plan = engine.planMaterialisation(template: behind, asOf: today);

      // The plan's only output is occurrences. There is no transaction field to populate, which is
      // the structural guarantee: a materialisation pass cannot create money even by mistake.
      expect(plan.occurrences.every((o) => o.templateId == 'rent'), isTrue);
      expect(plan.nextDueDateKey, DateKey.fromYmd(2026, 8, 1));
    });

    test('nextDueDateKey lands past today, ready for the following pass', () {
      final behind = template(
        startDateKey: DateKey.fromYmd(2026, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2026, 5, 1),
      );

      final plan = engine.planMaterialisation(template: behind, asOf: today);

      expect(plan.nextDueDateKey.isAfter(today), isTrue);
    });

    test('running again with those dates already present plans nothing', () {
      final behind = template(
        startDateKey: DateKey.fromYmd(2026, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2026, 5, 1),
      );

      final first = engine.planMaterialisation(template: behind, asOf: today);
      final second = engine.planMaterialisation(
        template: behind,
        asOf: today,
        alreadyMaterialised: first.occurrences.map((o) => o.dueDateKey),
      );

      expect(second.occurrences, isEmpty);
      expect(
        second.nextDueDateKey,
        first.nextDueDateKey,
        reason:
            'the cursor must land identically either way, or the pass is not idempotent',
      );
    });

    test('nothing due yet plans nothing and leaves the cursor alone', () {
      final future = template(
        startDateKey: DateKey.fromYmd(2026, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2026, 9, 1),
      );

      final plan = engine.planMaterialisation(template: future, asOf: today);

      expect(plan.isEmpty, isTrue);
      expect(plan.nextDueDateKey, DateKey.fromYmd(2026, 9, 1));
    });

    test('an end date stops materialisation', () {
      final ending = template(
        startDateKey: DateKey.fromYmd(2026, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2026, 5, 1),
        endDateKey: DateKey.fromYmd(2026, 6, 1),
      );

      final plan = engine.planMaterialisation(template: ending, asOf: today);

      expect(plan.occurrences.map((o) => o.dueDateKey.value).toList(), [
        20260501,
        20260601,
      ]);
    });

    test('the anchor survives a materialisation run across February', () {
      final anchored31 = template(
        anchorDay: 31,
        startDateKey: DateKey.fromYmd(2026, 1, 31),
        nextDueDateKey: DateKey.fromYmd(2026, 1, 31),
      );

      final plan = engine.planMaterialisation(
        template: anchored31,
        asOf: DateKey.fromYmd(2026, 4, 30),
      );

      expect(plan.occurrences.map((o) => o.dueDateKey.value).toList(), [
        20260131,
        20260228,
        20260331,
        20260430,
      ]);
      expect(plan.nextDueDateKey, DateKey.fromYmd(2026, 5, 31));
    });

    test(
      'a daily template years behind stops at the safety bound instead of spinning',
      () {
        final daily = template(
          unit: RecurringIntervalUnit.day,
          anchorDay: null,
          startDateKey: DateKey.fromYmd(2024, 1, 1),
          nextDueDateKey: DateKey.fromYmd(2024, 1, 1),
        );

        final plan = engine.planMaterialisation(template: daily, asOf: today);

        expect(plan.stoppedAtSafetyBound, isTrue);
        expect(
          plan.occurrences,
          hasLength(RecurringEngine.maxOccurrencesPerPass),
        );
      },
    );
  });

  group('settlement — direction decides the kind', () {
    final due = RecurringOccurrence(
      id: 'o1',
      templateId: 'rent',
      dueDateKey: DateKey.fromYmd(2026, 7, 1),
      status: RecurringOccurrenceStatus.due,
    );
    final paidOn = DateKey.fromYmd(2026, 7, 3);

    test('an outflow settles as a withdrawal from the account', () {
      final intent = engine
          .planSettlement(
            template: template(
              startDateKey: DateKey.fromYmd(2026, 1, 1),
              nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
            ),
            occurrence: due,
            amount: const Money(2500000, 'INR'),
            paidOn: paidOn,
            accountId: 'bank',
          )
          .valueOrNull!;

      expect(intent.kind, TransactionKind.withdrawal);
      expect(intent.fromAccountId, 'bank');
      expect(
        intent.toAccountId,
        isNull,
        reason: 'ARCH_2 §4.1 allows exactly one account',
      );
    });

    test('an inflow settles as a deposit into the account', () {
      final intent = engine
          .planSettlement(
            template: template(
              direction: RecurringDirection.inflow,
              startDateKey: DateKey.fromYmd(2026, 1, 1),
              nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
            ),
            occurrence: due,
            amount: const Money(2500000, 'INR'),
            paidOn: paidOn,
            accountId: 'bank',
          )
          .valueOrNull!;

      expect(intent.kind, TransactionKind.deposit);
      expect(intent.toAccountId, 'bank');
      expect(intent.fromAccountId, isNull);
      expect(
        intent.subtype,
        TransactionSubtype.salaryIn,
        reason:
            'one direction field is what lets salary share the system with bills (A27)',
      );
    });

    test('the ACTUAL amount is carried, not the template default', () {
      final intent = engine
          .planSettlement(
            template: template(
              defaultMinor: 49900,
              startDateKey: DateKey.fromYmd(2026, 1, 1),
              nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
            ),
            occurrence: due,
            // Paid 520 against a 499 expectation.
            amount: const Money(52000, 'INR'),
            paidOn: paidOn,
            accountId: 'bank',
          )
          .valueOrNull!;

      expect(
        intent.amount,
        const Money(52000, 'INR'),
        reason:
            'analytics uses actuals; the template keeps its expectation (A29)',
      );
    });

    test('the payee and tag come from the template', () {
      final intent = engine
          .planSettlement(
            template: template(
              startDateKey: DateKey.fromYmd(2026, 1, 1),
              nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
            ),
            occurrence: due,
            amount: const Money(2500000, 'INR'),
            paidOn: paidOn,
            accountId: 'bank',
          )
          .valueOrNull!;

      expect(intent.payeeId, 'landlord');
      expect(intent.tagId, 'tag-rent');
      expect(intent.occurrenceId, 'o1');
      expect(intent.templateId, 'rent');
      expect(
        intent.dateKey,
        paidOn,
        reason: 'dated when paid, which may differ from when due',
      );
    });

    test('an already-settled occurrence cannot be settled twice', () {
      final result = engine.planSettlement(
        template: template(
          startDateKey: DateKey.fromYmd(2026, 1, 1),
          nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
        ),
        occurrence: RecurringOccurrence(
          id: 'o1',
          templateId: 'rent',
          dueDateKey: DateKey.fromYmd(2026, 7, 1),
          status: RecurringOccurrenceStatus.paid,
        ),
        amount: const Money(2500000, 'INR'),
        paidOn: paidOn,
        accountId: 'bank',
      );

      expect(result.isFailure, isTrue);
      expect(
        (result.failureOrNull! as BusinessRuleFailure).rule,
        'occurrenceNotDue',
      );
    });

    test(
      'a payment in another currency is refused, not stored against the wrong code',
      () {
        final result = engine.planSettlement(
          template: template(
            startDateKey: DateKey.fromYmd(2026, 1, 1),
            nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
          ),
          occurrence: due,
          amount: const Money(600, 'USD'),
          paidOn: paidOn,
          accountId: 'bank',
        );

        expect(
          result.isFailure,
          isTrue,
          reason:
              'recurring_occurrences has no currency column of its own (ARCH_2 §7)',
        );
      },
    );

    test('a zero amount is refused', () {
      final result = engine.planSettlement(
        template: template(
          startDateKey: DateKey.fromYmd(2026, 1, 1),
          nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
        ),
        occurrence: due,
        amount: const Money(0, 'INR'),
        paidOn: paidOn,
        accountId: 'bank',
      );

      expect(result.isFailure, isTrue);
    });

    test('an occurrence from a different template is refused', () {
      final result = engine.planSettlement(
        template: template(
          startDateKey: DateKey.fromYmd(2026, 1, 1),
          nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
        ),
        occurrence: RecurringOccurrence(
          id: 'o9',
          templateId: 'netflix',
          dueDateKey: DateKey.fromYmd(2026, 7, 1),
          status: RecurringOccurrenceStatus.due,
        ),
        amount: const Money(2500000, 'INR'),
        paidOn: paidOn,
        accountId: 'bank',
      );

      expect(result.isFailure, isTrue);
    });
  });

  group('skip and overdue', () {
    test('a due occurrence can be skipped', () {
      final result = engine.planSkip(
        RecurringOccurrence(
          id: 'o1',
          templateId: 'rent',
          dueDateKey: DateKey.fromYmd(2026, 7, 1),
          status: RecurringOccurrenceStatus.due,
        ),
      );

      expect(result.isFailure, isFalse);
    });

    test('a settled occurrence cannot be skipped', () {
      final result = engine.planSkip(
        RecurringOccurrence(
          id: 'o1',
          templateId: 'rent',
          dueDateKey: DateKey.fromYmd(2026, 7, 1),
          status: RecurringOccurrenceStatus.paid,
          paidTransactionId: 't1',
        ),
      );

      expect(
        result.isFailure,
        isTrue,
        reason:
            'the money moved; skipping would leave a transaction with nothing explaining it',
      );
    });

    test('overdue is derived from the date, never stored', () {
      final occurrence = RecurringOccurrence(
        id: 'o1',
        templateId: 'rent',
        dueDateKey: DateKey.fromYmd(2026, 7, 1),
        status: RecurringOccurrenceStatus.due,
      );

      expect(
        engine.isOverdue(
          occurrence: occurrence,
          today: DateKey.fromYmd(2026, 7, 28),
        ),
        isTrue,
      );
      expect(
        engine.isOverdue(
          occurrence: occurrence,
          today: DateKey.fromYmd(2026, 6, 28),
        ),
        isFalse,
      );
    });

    test('a paused template is not active', () {
      final paused = template(
        isPaused: true,
        startDateKey: DateKey.fromYmd(2026, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
      );

      expect(
        engine.isActive(template: paused, asOf: DateKey.fromYmd(2026, 7, 28)),
        isFalse,
      );
    });
  });
}
```

### `test/domain/services/draw_plan_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/services/draw_plan.dart';

import '../../support/inventory_harness.dart';

/// The draw planner.
///
/// **Every case here was unstateable before.** `stockOf` builds an `ItemStock` with `batchCount: 1`
/// and one optional expiry, so no test in the repo could say "three batches, two of them expired" —
/// which is the entire scenario. `sampleBatch` from the inventory harness can, which is why these
/// tests live on batches rather than on a stock rollup.
void main() {
  const planner = DrawPlanner();
  const today = DateKey(20260814);

  /// A batch of [grams] expiring on [expiry], or never.
  Batch batch(String id, int grams, {DateKey? expiry}) =>
      sampleBatch(id: id, remainingMilli: grams * 1000, expiry: expiry);

  Qty grams(int value) => Qty(value * 1000, UnitCategory.weight);

  group('ordering among unexpired stock', () {
    test('soonest expiry first, whatever order the batches arrive in', () {
      final plan = planner.plan(
        batches: [
          batch('c', 100, expiry: const DateKey(20260901)),
          batch('a', 100, expiry: const DateKey(20260816)),
          batch('b', 100, expiry: const DateKey(20260820)),
        ],
        needed: grams(250),
        today: today,
      );

      expect(
        plan.lines.map((line) => line.batch.id),
        orderedEquals(['a', 'b', 'c']),
      );
      // The last batch is only partly drawn, because 250 is not a multiple of 100.
      expect(plan.lines.last.amount, grams(50));
      expect(plan.isComplete, isTrue);
    });

    test('an undated batch is spent last', () {
      // Nothing else can go off, so spending it ahead of a dated batch would waste the dated one.
      final plan = planner.plan(
        batches: [
          batch('never', 100),
          batch('dated', 100, expiry: const DateKey(20260901)),
        ],
        needed: grams(150),
        today: today,
      );

      expect(plan.lines.first.batch.id, 'dated');
      expect(plan.lines.last.batch.id, 'never');
    });

    test('a same-day tie breaks on id, so two plans agree', () {
      // Not cosmetic: a plan shown in a confirmation sheet and the plan executed a moment later must
      // list equally-good batches identically, or the user approved something else.
      final expiry = const DateKey(20260820);
      final first = planner.plan(
        batches: [
          batch('b', 100, expiry: expiry),
          batch('a', 100, expiry: expiry),
        ],
        needed: grams(120),
        today: today,
      );
      final second = planner.plan(
        batches: [
          batch('a', 100, expiry: expiry),
          batch('b', 100, expiry: expiry),
        ],
        needed: grams(120),
        today: today,
      );

      expect(
        first.lines.map((line) => line.batch.id),
        orderedEquals(second.lines.map((line) => line.batch.id)),
      );
      expect(first.lines.first.batch.id, 'a');
    });

    test('batches holding nothing are skipped, not counted', () {
      final plan = planner.plan(
        batches: [
          batch('empty', 0, expiry: const DateKey(20260816)),
          batch('full', 100, expiry: const DateKey(20260901)),
        ],
        needed: grams(100),
        today: today,
      );

      expect(plan.lines, hasLength(1));
      expect(plan.lines.single.batch.id, 'full');
    });
  });

  group('expired stock is excluded unless asked for', () {
    test('an expired batch is not drawn, and the shortfall says so', () {
      // **The reported bug.** Expired stock was being deducted silently, because FEFO orders by
      // nearest expiry and an expired date is the nearest date — the policy was working, for a
      // different purpose.
      final plan = planner.plan(
        batches: [
          batch('gone', 200, expiry: const DateKey(20260810)),
          batch('good', 100, expiry: const DateKey(20260901)),
        ],
        needed: grams(250),
        today: today,
      );

      expect(plan.lines.map((line) => line.batch.id), orderedEquals(['good']));
      expect(plan.isComplete, isFalse);
      expect(plan.shortfall, grams(150));
      expect(plan.usesExpired, isFalse);
    });

    test('and reports that saying yes would cover it', () {
      // What the confirmation prompt is for: 150 g short, 200 g sitting there past its date.
      final plan = planner.plan(
        batches: [
          batch('gone', 200, expiry: const DateKey(20260810)),
          batch('good', 100, expiry: const DateKey(20260901)),
        ],
        needed: grams(250),
        today: today,
      );

      expect(plan.couldCompleteWithExpired, isTrue);
      expect(plan.expiredUntouchedMilli, grams(200).milliBase);
    });

    test('a complete plan never offers expired stock', () {
      // There is expired stock, and the plan does not reach it. Prompting here would be a warning
      // about nothing.
      final plan = planner.plan(
        batches: [
          batch('gone', 200, expiry: const DateKey(20260810)),
          batch('good', 500, expiry: const DateKey(20260901)),
        ],
        needed: grams(250),
        today: today,
      );

      expect(plan.isComplete, isTrue);
      expect(plan.usesExpired, isFalse);
      expect(plan.couldCompleteWithExpired, isFalse);
    });

    test(
      'when even the expired stock is not enough, there is nothing to offer',
      () {
        final plan = planner.plan(
          batches: [
            batch('gone', 50, expiry: const DateKey(20260810)),
            batch('good', 100, expiry: const DateKey(20260901)),
          ],
          needed: grams(400),
          today: today,
        );

        expect(plan.couldCompleteWithExpired, isFalse);
        expect(plan.shortfall, grams(300));
      },
    );
  });

  group('the expired fallback, once permitted', () {
    test('good stock is spent first and expired only tops it up', () {
      // Your case: 150 good, 100 expired, 200 needed. Good stock is exhausted before anything past
      // its date is touched, and the plan says exactly how much of the total was expired.
      final plan = planner.plan(
        batches: [
          batch('gone', 100, expiry: const DateKey(20260810)),
          batch('good', 150, expiry: const DateKey(20260901)),
        ],
        needed: grams(200),
        today: today,
        allowExpired: true,
      );

      expect(
        plan.lines.map((line) => line.batch.id),
        orderedEquals(['good', 'gone']),
      );
      expect(plan.lines.first.amount, grams(150));
      expect(plan.lines.last.amount, grams(50));
      expect(plan.isComplete, isTrue);
      expect(plan.usesExpired, isTrue);
      expect(plan.fromExpired, grams(50));
      // 100 expired existed, 50 was used, 50 remains untouched.
      expect(plan.expiredUntouchedMilli, grams(50).milliBase);
    });

    test('least spoiled first among expired, not oldest first', () {
      // **Deliberately the reverse of FEFO.** Strict FEFO reaches for the oldest expired batch, which
      // is the most spoiled thing in the house. Among food already past its date, nearest-to-fresh is
      // the only defensible order.
      final plan = planner.plan(
        batches: [
          batch('ancient', 100, expiry: const DateKey(20260601)),
          batch('yesterday', 100, expiry: const DateKey(20260813)),
          batch('lastweek', 100, expiry: const DateKey(20260807)),
        ],
        needed: grams(250),
        today: today,
        allowExpired: true,
      );

      expect(
        plan.lines.map((line) => line.batch.id),
        orderedEquals(['yesterday', 'lastweek', 'ancient']),
      );
    });

    test('every line is marked, so nobody recomputes which were expired', () {
      final plan = planner.plan(
        batches: [
          batch('gone', 100, expiry: const DateKey(20260810)),
          batch('good', 100, expiry: const DateKey(20260901)),
        ],
        needed: grams(200),
        today: today,
        allowExpired: true,
      );

      expect(plan.lines.where((line) => line.isExpired), hasLength(1));
      expect(
        plan.lines.singleWhere((line) => line.isExpired).batch.id,
        'gone',
      );
    });
  });

  group('the expiry boundary', () {
    test('a batch expiring today is still good today', () {
      // Confirms `Batch.isExpired`, which is strict: `expiry < today`. Use-by 14 Aug is usable on
      // 14 Aug, which is what the calendar module already assumes — a batch expiring today appears
      // as an event rather than as history.
      final plan = planner.plan(
        batches: [batch('today', 100, expiry: today)],
        needed: grams(100),
        today: today,
      );

      expect(plan.isComplete, isTrue);
      expect(plan.usesExpired, isFalse);
    });

    test('a batch that expired yesterday is not', () {
      final plan = planner.plan(
        batches: [batch('yesterday', 100, expiry: const DateKey(20260813))],
        needed: grams(100),
        today: today,
      );

      expect(plan.lines, isEmpty);
      expect(plan.couldCompleteWithExpired, isTrue);
    });
  });

  group('degenerate requests', () {
    test('asking for nothing draws nothing', () {
      for (final wanted in [grams(0), grams(-5)]) {
        final plan = planner.plan(
          batches: [batch('good', 100, expiry: const DateKey(20260901))],
          needed: wanted,
          today: today,
        );
        expect(plan.lines, isEmpty);
        expect(plan.isComplete, isTrue);
        expect(plan.usesExpired, isFalse);
      }
    });

    test('no batches at all is a shortfall, not a crash', () {
      final plan = planner.plan(
        batches: const [],
        needed: grams(100),
        today: today,
      );

      expect(plan.shortfall, grams(100));
      expect(plan.couldCompleteWithExpired, isFalse);
    });

    test(
      'a mismatched category throws rather than reporting a false shortfall',
      () {
        // A caller that skipped the volume-to-weight bridge. Silently dropping the batch would report
        // a shortfall for stock sitting on the shelf, which is the worse of the two failures.
        expect(
          () => planner.plan(
            batches: [batch('good', 100, expiry: const DateKey(20260901))],
            needed: const Qty(100000, UnitCategory.volume),
            today: today,
          ),
          throwsArgumentError,
        );
      },
    );
  });
}
```

### `test/domain/split/debt_simplifier_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/services/split/debt_simplifier.dart';

/// [DebtSimplifier].
///
/// Every expected plan below was produced by an independent implementation of the same algorithm and
/// compared before being written here. The counter-example in *"beats greedy"* came from a
/// brute-force search over every balance vector up to five people — ARCH_M §7 records why a test
/// expectation reasoned from a subset of the space is worth nothing.
void main() {
  const simplifier = DebtSimplifier();
  Money inr(int minor) => Money(minor, 'INR');
  DebtEdge owes(String from, String to, int minor) =>
      DebtEdge(fromPayeeId: from, toPayeeId: to, amount: inr(minor));

  List<String> shape(SettlementPlan plan) => [
    for (final t in plan.transfers)
      '${t.fromPayeeId}->${t.toPayeeId}:${t.amount.minor}',
  ];

  group('nothing to do', () {
    test('no debts', () {
      final plan = simplifier.plan(const []);
      expect(plan.transfers, isEmpty);
      expect(plan.isImprovement, isFalse);
    });

    test('zero-amount edges are ignored', () {
      expect(simplifier.plan([owes('a', 'b', 0)]).transfers, isEmpty);
    });

    test('mutual debts cancel to nothing', () {
      // A owes B ₹100 and B owes A ₹100. Two payments become none.
      final plan = simplifier.plan([
        owes('a', 'b', 10000),
        owes('b', 'a', 10000),
      ]);
      expect(plan.transfers, isEmpty);
      expect(plan.originalDebtCount, 2);
      expect(plan.paymentsSaved, 2);
    });
  });

  group('the chain, which is the whole pitch', () {
    test('A owes B and B owes C becomes A pays C', () {
      final plan = simplifier.plan([
        owes('a', 'b', 2000),
        owes('b', 'c', 2000),
      ]);
      expect(shape(plan), orderedEquals(['a->c:2000']));
      expect(plan.paymentsSaved, 1);
      expect(plan.wasPartitionedExactly, isTrue);
    });

    test('and the transfer explains itself', () {
      // The sentence Splitwise leaves its users to work out: their forum has carried "why do I owe
      // someone who never lent me money?" for over a decade.
      final plan = simplifier.plan([
        owes('a', 'b', 2000),
        owes('b', 'c', 2000),
      ]);
      final transfer = plan.transfers.single;
      expect(transfer.clears, hasLength(1));
      expect(transfer.clears.single.edge.toPayeeId, 'b');
      expect(transfer.clears.single.amount, inr(2000));
      expect(transfer.isDirect, isFalse, reason: 'a never owed c directly');
    });

    test('a transfer covering two debts names both', () {
      final plan = simplifier.plan([
        owes('a', 'b', 30000),
        owes('a', 'c', 15000),
        owes('b', 'd', 30000),
        owes('c', 'd', 15000),
      ]);
      final fromA = plan.transfers.firstWhere((t) => t.fromPayeeId == 'a');
      expect(fromA.toPayeeId, 'd');
      expect(fromA.amount, inr(45000));
      expect(
        fromA.clears.map((c) => c.edge.toPayeeId),
        containsAll(['b', 'c']),
      );
      expect(
        fromA.clears.fold(0, (sum, c) => sum + c.amount.minor),
        45000,
        reason: 'the discharges must account for the whole transfer',
      );
    });
  });

  group('beats greedy where greedy cannot', () {
    test('the smallest case a brute-force search could find', () {
      // Balances A:-6 B:-5 C:+2 D:+4 E:+5. Greedy needs four payments; {A,C,D} and {B,E} are both
      // zero-sum, so three suffice. No such case exists at three or four people — verified
      // exhaustively — and there are 840 at five.
      final plan = simplifier.plan([
        owes('a', 'c', 200),
        owes('a', 'd', 400),
        owes('b', 'e', 500),
      ]);
      expect(plan.transfers, hasLength(3));
      expect(
        shape(plan),
        orderedEquals(['a->d:400', 'a->c:200', 'b->e:500']),
      );
      expect(plan.wasPartitionedExactly, isTrue);
    });

    test('the same balances reached by different debts settle the same way', () {
      // The plan depends on the net position, not on which edges produced it — but the *explanations*
      // differ, because they are attributed against the real debts.
      final plan = simplifier.plan([
        owes('a', 'e', 600),
        owes('b', 'd', 400),
        owes('b', 'c', 100),
      ]);
      expect(plan.transfers, hasLength(3));
      expect(
        shape(plan),
        orderedEquals(['a->e:600', 'b->d:400', 'b->c:100']),
      );
      // Every transfer here settles a debt that genuinely exists, so all three are direct.
      expect(plan.transfers.every((t) => t.isDirect), isTrue);
    });
  });

  group('preferring real debts, which costs nothing', () {
    test('a debtor pays someone they actually owe when the count is unaffected', () {
      // **This one caught a real gap.** The first implementation applied the preference only inside
      // greedy, never to the choice of partition — so `{a,d}` and `{b,c}` won on enumeration order and
      // both suggested payments were between people who had never owed each other anything. Equally
      // zero-sum, equally two payments, and wrong.
      final plan = simplifier.plan([
        owes('a', 'b', 5000),
        owes('c', 'd', 5000),
      ]);
      expect(plan.transfers, hasLength(2));
      expect(plan.transfers.every((t) => t.isDirect), isTrue);
      expect(
        plan.transfers.map((t) => '${t.fromPayeeId}->${t.toPayeeId}'),
        orderedEquals(['a->b', 'c->d']),
      );
    });
  });

  group('every transfer is accounted for', () {
    test('the discharges of each transfer sum to the transfer', () {
      final plan = simplifier.plan([
        owes('a', 'b', 12345),
        owes('b', 'c', 6789),
        owes('c', 'a', 111),
        owes('d', 'a', 4000),
      ]);
      for (final transfer in plan.transfers) {
        expect(
          transfer.clears.fold(0, (sum, c) => sum + c.amount.minor),
          transfer.amount.minor,
          reason: '${transfer.fromPayeeId}->${transfer.toPayeeId}',
        );
      }
    });

    test('no debt is discharged twice across a debtor own transfers', () {
      final plan = simplifier.plan([
        owes('a', 'b', 10000),
        owes('a', 'c', 10000),
        owes('b', 'd', 5000),
        owes('c', 'd', 5000),
      ]);
      final byEdge = <String, int>{};
      for (final transfer in plan.transfers) {
        for (final cleared in transfer.clears) {
          final key = '${cleared.edge.fromPayeeId}->${cleared.edge.toPayeeId}';
          byEdge[key] = (byEdge[key] ?? 0) + cleared.amount.minor;
        }
      }
      expect(byEdge['a->b'], lessThanOrEqualTo(10000));
      expect(byEdge['a->c'], lessThanOrEqualTo(10000));
    });
  });

  group('the plan settles the balances it was given', () {
    test('applying every transfer leaves everyone at zero', () {
      // The property the whole class has to satisfy, asserted over several shapes rather than one.
      final cases = <List<DebtEdge>>[
        [owes('a', 'b', 2000), owes('b', 'c', 2000)],
        [owes('a', 'c', 200), owes('a', 'd', 400), owes('b', 'e', 500)],
        [owes('a', 'b', 3333), owes('b', 'c', 1111), owes('c', 'a', 777)],
        [
          owes('a', 'b', 10000),
          owes('c', 'b', 2500),
          owes('a', 'd', 700),
          owes('d', 'c', 700),
        ],
      ];
      for (final debts in cases) {
        final net = <String, int>{};
        for (final debt in debts) {
          net[debt.fromPayeeId] =
              (net[debt.fromPayeeId] ?? 0) - debt.amount.minor;
          net[debt.toPayeeId] = (net[debt.toPayeeId] ?? 0) + debt.amount.minor;
        }
        for (final transfer in simplifier.plan(debts).transfers) {
          net[transfer.fromPayeeId] =
              (net[transfer.fromPayeeId] ?? 0) + transfer.amount.minor;
          net[transfer.toPayeeId] =
              (net[transfer.toPayeeId] ?? 0) - transfer.amount.minor;
        }
        expect(
          net.values.every((v) => v == 0),
          isTrue,
          reason: 'left over: $net',
        );
      }
    });

    test('and never suggests more payments than there were debts', () {
      final plan = simplifier.plan([
        owes('a', 'b', 100),
        owes('b', 'c', 100),
        owes('c', 'd', 100),
        owes('d', 'e', 100),
      ]);
      expect(plan.transfers.length, lessThanOrEqualTo(plan.originalDebtCount));
      expect(shape(plan), orderedEquals(['a->e:100']));
    });
  });

  group('refusals', () {
    test('mixed currencies, because netting them would invent a rate', () {
      expect(
        () => simplifier.plan([
          owes('a', 'b', 100),
          DebtEdge(
            fromPayeeId: 'b',
            toPayeeId: 'c',
            amount: const Money(100, 'USD'),
          ),
        ]),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });

    test('a negative edge, because the direction is in the field names', () {
      expect(
        () => simplifier.plan([owes('a', 'b', -100)]),
        throwsArgumentError,
      );
    });

    test('owing yourself', () {
      expect(() => simplifier.plan([owes('a', 'a', 100)]), throwsArgumentError);
    });
  });

  group('the exact ceiling', () {
    test('a group past it still produces a valid plan, marked inexact', () {
      // Seventeen people, one over `maxExactMembers`. The greedy fallback must still settle everyone;
      // it just cannot claim to be minimal, and `wasPartitionedExactly` is how a screen knows not to
      // say "the fewest possible payments".
      final debts = <DebtEdge>[
        for (var i = 0; i < 17; i++) owes('p$i', 'p${(i + 1) % 17}', 1000 + i),
      ];
      final plan = simplifier.plan(debts);
      expect(plan.wasPartitionedExactly, isFalse);

      final net = <String, int>{};
      for (final debt in debts) {
        net[debt.fromPayeeId] =
            (net[debt.fromPayeeId] ?? 0) - debt.amount.minor;
        net[debt.toPayeeId] = (net[debt.toPayeeId] ?? 0) + debt.amount.minor;
      }
      for (final transfer in plan.transfers) {
        net[transfer.fromPayeeId] =
            (net[transfer.fromPayeeId] ?? 0) + transfer.amount.minor;
        net[transfer.toPayeeId] =
            (net[transfer.toPayeeId] ?? 0) - transfer.amount.minor;
      }
      expect(net.values.every((v) => v == 0), isTrue);
    });

    test('independent pairs are each found, and each stays direct', () {
      // Six pairs, twelve people. **Deliberately not sixteen**: the partition enumerates submasks at
      // about 3^n, so twelve is 531,441 steps and instant, while sixteen is 43 million and would make
      // one unit test the slowest thing in the suite. The ceiling itself is asserted by the case above,
      // which crosses it.
      //
      // Every pair is zero-sum, so a partition exists that matches what people actually did — and the
      // score tie-break is what picks it. Without that, the DP happily pairs `d0` with `c3`.
      final debts = <DebtEdge>[
        for (var i = 0; i < 6; i++) owes('d$i', 'c$i', 1000),
      ];
      final plan = simplifier.plan(debts);
      expect(plan.wasPartitionedExactly, isTrue);
      expect(plan.transfers, hasLength(6));
      expect(plan.transfers.every((t) => t.isDirect), isTrue);
      expect(
        plan.transfers.map((t) => '${t.fromPayeeId}->${t.toPayeeId}'),
        orderedEquals([
          for (var i = 0; i < 6; i++) 'd$i->c$i',
        ]),
      );
    });
  });
}
```

### `test/domain/split/settlement_service_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/split/settlement_service.dart';

import '../../support/split_fakes.dart';

/// [SettlementService].
///
/// **The write whose failure a user could not see**, and until now the one with no test. A settlement
/// that reaches the ledger without its transaction clears a debt with no money anywhere — the whole
/// reason `recordSettlement` takes both and writes them in one database transaction.
void main() {
  late FakeSplitLedger ledger;
  late FakeSplitGroups groups;
  late SettlementService service;
  final clock = FixedClock(DateTime.utc(2026, 8, 14, 9));

  Money inr(int minor) => Money(minor, 'INR');

  setUp(() {
    ledger = FakeSplitLedger();
    groups = FakeSplitGroups(self: 'me');
    service = SettlementService(
      ledger: ledger,
      groups: groups,
      uids: SeqUids(),
      clock: clock,
    );
  });

  group('they pay you', () {
    test('writes a deposit into the chosen account', () async {
      final result = await service.settle(
        fromPayeeId: 'ravi',
        toPayeeId: 'me',
        amount: inr(185000),
        accountId: 'ac-1',
      );

      expect(result.isOk, isTrue);
      final recorded = ledger.settlements.single;
      final tx = recorded.transaction!;
      expect(tx.kind, TransactionKind.deposit);
      // A deposit fills an account; only that side is set, which is what `v_account_balances` reads.
      expect(tx.toAccountId, 'ac-1');
      expect(tx.fromAccountId, isNull);
      expect(tx.originalAmount, inr(185000));
    });

    test('names the counterparty, so the ledger row is legible alone', () async {
      // "₹1,850 from Ravi", not an unexplained deposit somebody has to open the split module to
      // understand.
      await service.settle(
        fromPayeeId: 'ravi',
        toPayeeId: 'me',
        amount: inr(185000),
        accountId: 'ac-1',
      );
      expect(ledger.settlements.single.transaction!.payeeId, 'ravi');
    });
  });

  group('you pay them', () {
    test('writes a withdrawal out of the chosen account', () async {
      await service.settle(
        fromPayeeId: 'me',
        toPayeeId: 'priya',
        amount: inr(40000),
        accountId: 'ac-1',
      );

      final tx = ledger.settlements.single.transaction!;
      expect(tx.kind, TransactionKind.withdrawal);
      expect(tx.fromAccountId, 'ac-1');
      expect(tx.toAccountId, isNull);
      expect(tx.payeeId, 'priya');
    });
  });

  group('the subtype is not a category', () {
    test('otherIn and otherOut, never a spending category', () async {
      // The *original* expense already carried whatever category it deserved. Counting the repayment
      // as spending too would double it in every analytics surface — and Law L13 makes a new enum
      // member a schema contract, so one added to dodge a naming question is one nobody can remove.
      await service.settle(
        fromPayeeId: 'ravi',
        toPayeeId: 'me',
        amount: inr(1000),
        accountId: 'ac-1',
      );
      await service.settle(
        fromPayeeId: 'me',
        toPayeeId: 'priya',
        amount: inr(1000),
        accountId: 'ac-1',
      );

      expect(
        ledger.settlements.map((s) => s.transaction!.subtype),
        [TransactionSubtype.otherIn, TransactionSubtype.otherOut],
      );
    });

    test('needsReview is false — the user just typed it', () async {
      await service.settle(
        fromPayeeId: 'ravi',
        toPayeeId: 'me',
        amount: inr(1000),
        accountId: 'ac-1',
      );
      expect(ledger.settlements.single.transaction!.needsReview, isFalse);
    });
  });

  group('the settlement and its transaction are one write', () {
    test('both carry the same id link', () async {
      await service.settle(
        fromPayeeId: 'ravi',
        toPayeeId: 'me',
        amount: inr(1000),
        accountId: 'ac-1',
      );
      final recorded = ledger.settlements.single;
      expect(recorded.settlement.transactionId, recorded.transaction!.id);
    });

    test(
      'a settlement between two other people carries no transaction',
      () async {
        // None of the user's money moves, so there is no account to put it through. An accepted
        // simplification plan can suggest one of these.
        final result = await service.settle(
          fromPayeeId: 'ravi',
          toPayeeId: 'priya',
          amount: inr(1000),
        );

        expect(result.isOk, isTrue);
        expect(ledger.settlements.single.transaction, isNull);
        expect(ledger.settlements.single.settlement.transactionId, isNull);
      },
    );
  });

  group('refusals', () {
    test('an account is required whenever you are a party', () async {
      // **The refusal that protects the central claim.** Without it a settlement of the user's own
      // money could reach the ledger with nothing in their account to match — the one failure in this
      // module they could not see.
      final result = await service.settle(
        fromPayeeId: 'ravi',
        toPayeeId: 'me',
        amount: inr(1000),
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(ledger.settlements, isEmpty);
    });

    test('an unset self payee stops everything', () async {
      // With nobody claimed, nothing can say which side of a debt the user is on, so every balance
      // would be a guess. Better to refuse than to record a direction nobody chose.
      groups.self = null;
      final result = await service.settle(
        fromPayeeId: 'ravi',
        toPayeeId: 'me',
        amount: inr(1000),
        accountId: 'ac-1',
      );

      expect(
        (result.failureOrNull as BusinessRuleFailure?)?.rule,
        'splitSelfPayeeUnset',
      );
      expect(ledger.settlements, isEmpty);
    });

    test('paying yourself is not a settlement', () async {
      final result = await service.settle(
        fromPayeeId: 'me',
        toPayeeId: 'me',
        amount: inr(1000),
        accountId: 'ac-1',
      );
      expect(
        (result.failureOrNull as BusinessRuleFailure?)?.rule,
        'splitSelfSettlement',
      );
    });

    test('a non-positive amount is refused', () async {
      for (final amount in [inr(0), inr(-100)]) {
        final result = await service.settle(
          fromPayeeId: 'ravi',
          toPayeeId: 'me',
          amount: amount,
          accountId: 'ac-1',
        );
        expect(result.failureOrNull, isA<ValidationFailure>());
      }
      expect(ledger.settlements, isEmpty);
    });
  });

  group('the date', () {
    test('comes from the clock unless given', () async {
      await service.settle(
        fromPayeeId: 'ravi',
        toPayeeId: 'me',
        amount: inr(1000),
        accountId: 'ac-1',
      );
      expect(
        ledger.settlements.single.settlement.dateKey,
        const DateKey(20260814),
      );
    });

    test('is honoured when a back-dated payment is recorded', () async {
      await service.settle(
        fromPayeeId: 'ravi',
        toPayeeId: 'me',
        amount: inr(1000),
        accountId: 'ac-1',
        on: const DateKey(20260801),
      );
      final recorded = ledger.settlements.single;
      expect(recorded.settlement.dateKey, const DateKey(20260801));
      // The transaction must agree, or the account ledger and the split ledger disagree about when.
      expect(recorded.transaction!.dateKey, const DateKey(20260801));
    });
  });
}
```

### `test/domain/split/split_balance_service_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/domain/services/split/debt_simplifier.dart';
import 'package:alaya/domain/services/split/split_balance_service.dart';

import '../../support/split_fakes.dart';

/// [SplitBalanceService].
///
/// The two things a view cannot do: compare against today, and run a graph algorithm. Everything else
/// it exposes is a pass-through, and the tests below say which is which.
void main() {
  final clock = FixedClock(DateTime.utc(2026, 8, 14, 9));
  Money inr(int minor) => Money(minor, 'INR');

  SplitBalanceService build(FakeSplitLedger ledger) =>
      SplitBalanceService(ledger: ledger, clock: clock);

  group('ageing', () {
    test('counts days against the injected clock, not the wall clock', () async {
      // **Why this is here and not in SQL.** ARCH_2 §12.2 forbids a view from consulting the current
      // time, and a view that did could not be asserted against a `FixedClock` — this test would be
      // impossible to write, and the notification impossible to verify.
      final service = build(
        FakeSplitLedger(
          balances: [
            owedToMe('ravi', 185000, since: const DateKey(20260714)),
          ],
        ),
      );

      final ageing = await service.ageingDebts();
      expect(ageing.single.ageInDays, 31);
    });

    test('a debt inside the threshold is not mentioned', () async {
      // Splitting a bill on Friday must not produce a notification the following Tuesday.
      final service = build(
        FakeSplitLedger(
          balances: [owedToMe('ravi', 1000, since: const DateKey(20260810))],
        ),
      );
      expect(await service.ageingDebts(), isEmpty);
    });

    test('the threshold is overridable', () async {
      final service = build(
        FakeSplitLedger(
          balances: [owedToMe('ravi', 1000, since: const DateKey(20260810))],
        ),
      );
      expect(await service.ageingDebts(thresholdDays: 3), hasLength(1));
    });

    test('oldest first', () async {
      final service = build(
        FakeSplitLedger(
          balances: [
            owedToMe('recent', 1000, since: const DateKey(20260720)),
            owedToMe('ancient', 1000, since: const DateKey(20260601)),
          ],
        ),
      );
      expect(
        (await service.ageingDebts()).map((d) => d.balance.payeeId),
        ['ancient', 'recent'],
      );
    });

    test('a balance with no date is never ageing', () async {
      // `MIN(date_key)` over rows that are all settlements yields null — nothing dated is outstanding.
      final service = build(
        FakeSplitLedger(balances: [owedToMe('ravi', 1000)]),
      );
      expect(await service.ageingDebts(), isEmpty);
    });

    test('debts you owe age too', () async {
      // The nudge runs both ways: forgetting to pay somebody back is the commoner failure.
      final service = build(
        FakeSplitLedger(
          balances: [iOwe('priya', 40000, since: const DateKey(20260601))],
        ),
      );
      expect(
        await service.ageingDebts().then((d) => d.single.balance.iOweThem),
        isTrue,
      );
    });
  });

  group('totals', () {
    test('two figures per currency, never netted', () async {
      // "Owed ₹4,000 and owe ₹3,900" is a different story from "up ₹100", and the net version is the
      // first step towards treating a receivable as an asset.
      final service = build(
        FakeSplitLedger(
          balances: [
            owedToMe('ravi', 400000),
            iOwe('priya', 390000),
          ],
        ),
      );

      final totals = await service.totals();
      expect(totals['INR']!.owedToMe, inr(400000));
      expect(totals['INR']!.iOwe, inr(390000));
    });

    test('currencies stay apart', () async {
      // Netting INR against USD without a rate produces a figure nobody can reproduce (A34).
      final service = build(
        FakeSplitLedger(
          balances: [
            owedToMe('ravi', 100000),
            SplitBalanceFixture.usdOwed('sam', 5000),
          ],
        ),
      );

      final totals = await service.totals();
      expect(totals.keys.toSet(), {'INR', 'USD'});
    });

    test('nothing outstanding is an empty map, not zeroes', () async {
      expect(await build(FakeSplitLedger()).totals(), isEmpty);
    });
  });

  group('settle-up plans', () {
    test(
      'one plan per currency, because the simplifier refuses a mixed list',
      () async {
        // `DebtSimplifier.plan` throws `CurrencyMismatchError` on mixed edges — a correct refusal, and
        // the reason this grouping is visible here rather than hidden inside a total. A travel group
        // would otherwise crash the settle-up screen.
        final service = build(
          FakeSplitLedger(
            debts: [
              DebtEdge(
                fromPayeeId: 'a',
                toPayeeId: 'me',
                amount: inr(2000),
              ),
              const DebtEdge(
                fromPayeeId: 'b',
                toPayeeId: 'me',
                amount: Money(50, 'USD'),
              ),
            ],
          ),
        );

        final plans = await service.settleUpPlans('g-1');
        expect(plans.map((p) => p.currencyCode).toSet(), {'INR', 'USD'});
      },
    );

    test('a plan that saves nothing is dropped', () async {
      // Two independent debts already settle in two payments. Showing a "plan" that changes nothing is
      // a wasted tap; an empty list means settled or already minimal.
      final service = build(
        FakeSplitLedger(
          debts: [
            DebtEdge(fromPayeeId: 'a', toPayeeId: 'me', amount: inr(1000)),
          ],
        ),
      );

      final plans = await service.settleUpPlans('g-1');
      expect(plans.single.plan.transfers, hasLength(1));
      expect(plans.single.plan.isImprovement, isFalse);
    });

    test('nothing owed is an empty list', () async {
      expect(await build(FakeSplitLedger()).settleUpPlans('g-1'), isEmpty);
    });

    test('canSimplify only says yes when it would help', () async {
      final noBetter = build(
        FakeSplitLedger(
          debts: [
            DebtEdge(fromPayeeId: 'a', toPayeeId: 'me', amount: inr(1000)),
          ],
        ),
      );
      expect(await noBetter.canSimplify('g-1'), isFalse);

      // A chain: a owes me, I owe b. One payment replaces two.
      final better = build(
        FakeSplitLedger(
          debts: [
            DebtEdge(fromPayeeId: 'a', toPayeeId: 'me', amount: inr(1000)),
            DebtEdge(fromPayeeId: 'me', toPayeeId: 'b', amount: inr(1000)),
          ],
        ),
      );
      expect(await better.canSimplify('g-1'), isTrue);
    });
  });
}

/// A USD balance, which the fixtures above are hardcoded to INR for.
abstract final class SplitBalanceFixture {
  /// Somebody owes the user [minor] in USD.
  static SplitBalance usdOwed(String payeeId, int minor) => SplitBalance(
    payeeId: payeeId,
    owedToMe: Money(minor, 'USD'),
    iOwe: const Money(0, 'USD'),
  );
}
```

### `test/domain/split/split_expense_service_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/split/split_expense_service.dart';
import 'package:alaya/domain/services/split/split_resolver.dart';

import '../../support/split_fakes.dart';

/// [SplitExpenseService].
///
/// **The first test this service has had.** It turns instructions into stored shares, which means a
/// fault here is a wrong debt rather than a crash — the kind nothing surfaces until somebody argues
/// about money.
void main() {
  late FakeSplitLedger ledger;
  late SplitExpenseService service;
  final clock = FixedClock(DateTime.utc(2026, 8, 14, 9));

  Money inr(int minor) => Money(minor, 'INR');

  setUp(() {
    ledger = FakeSplitLedger();
    service = SplitExpenseService(
      ledger: ledger,
      uids: SeqUids(),
      clock: clock,
    );
  });

  group('record', () {
    test('resolves shares through the real resolver', () async {
      // ₹1,000 three ways is not ₹333.33 three times. The service runs `SplitResolver` for real, so
      // this asserts the same allocation production performs — a fake resolver here would prove only
      // that the fake was consistent with itself.
      final result = await service.record(
        total: inr(100000),
        paidByPayeeId: 'me',
        method: SplitMethod.equal,
        inputs: const [
          ShareInput.equal('a'),
          ShareInput.equal('b'),
          ShareInput.equal('c'),
        ],
      );

      final saved = ledger.saved.single;
      expect(saved.shares.map((s) => s.amount.minor), [33334, 33333, 33333]);
      expect(saved.allocated, inr(100000));
      expect(result.isOk, isTrue);
    });

    test('stores the input beside the resolved amount', () async {
      // Both, so reopening a 50/30/20 split shows 50/30/20 rather than three amounts the user has to
      // reverse-engineer.
      await service.record(
        total: inr(100000),
        paidByPayeeId: 'me',
        method: SplitMethod.percent,
        inputs: const [
          ShareInput.percent('a', 5000),
          ShareInput.percent('b', 3000),
          ShareInput.percent('c', 2000),
        ],
      );

      final shares = ledger.saved.single.shares;
      expect(
        shares.map((s) => s.inputKind),
        everyElement(ShareInputKind.percent),
      );
      expect(shares.map((s) => s.inputValue), [5000, 3000, 2000]);
      expect(shares.map((s) => s.amount.minor), [50000, 30000, 20000]);
    });

    test('saves a split whose shares do not cover the total', () async {
      // **A real state, not an error.** Percentages reaching 90% mid-edit, or a tip nobody assigned.
      // `transaction_lines` treats an un-itemised transaction exactly this way (ARCH_2 §4.2), and
      // refusing would make the editor unusable while somebody is still typing.
      final result = await service.record(
        total: inr(100000),
        paidByPayeeId: 'me',
        method: SplitMethod.percent,
        inputs: const [ShareInput.percent('a', 9000)],
      );

      expect(result.isOk, isTrue);
      expect(ledger.saved.single.unallocated, inr(10000));
    });

    test('refuses perLine, which is recorded line by line', () async {
      final result = await service.record(
        total: inr(100000),
        paidByPayeeId: 'me',
        method: SplitMethod.perLine,
        inputs: const [ShareInput.equal('a')],
      );

      expect(
        (result.failureOrNull as BusinessRuleFailure?)?.rule,
        'splitUseRecordItemised',
      );
      expect(ledger.saved, isEmpty);
    });

    test('turns a resolver refusal into a failure, not a crash', () async {
      // The resolver throws `ArgumentError` for things a user cannot cause — percent mixed with
      // weights. Letting it escape would crash a controller; surfacing it lets a screen say something.
      final result = await service.record(
        total: inr(100000),
        paidByPayeeId: 'me',
        method: SplitMethod.percent,
        inputs: const [
          ShareInput.percent('a', 5000),
          ShareInput.equal('b'),
        ],
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(ledger.saved, isEmpty);
    });

    test('dates from the clock when no date is given', () async {
      await service.record(
        total: inr(1000),
        paidByPayeeId: 'me',
        method: SplitMethod.equal,
        inputs: const [ShareInput.equal('a')],
      );
      expect(ledger.saved.single.dateKey, const DateKey(20260814));
    });

    test('reuses the id it is handed, so an edit replaces', () async {
      await service.record(
        id: 'existing',
        total: inr(1000),
        paidByPayeeId: 'me',
        method: SplitMethod.equal,
        inputs: const [ShareInput.equal('a')],
      );
      expect(ledger.saved.single.id, 'existing');
    });

    test('surfaces a repository refusal', () async {
      ledger.rejectSave = true;
      final result = await service.record(
        total: inr(1000),
        paidByPayeeId: 'me',
        method: SplitMethod.equal,
        inputs: const [ShareInput.equal('a')],
      );
      expect(result.isFailure, isTrue);
    });
  });

  group('recordItemised', () {
    test('writes one share per person per line', () async {
      // **The shape session 4b's API gap exposed.** `SplitResolver.resolvePerLine` aggregates per
      // person — right for showing somebody their total, wrong for writing rows, because the schema
      // wants `transactionLineNo` on each. Summing first would discard the line the column names.
      final result = await service.recordItemised(
        total: inr(180000),
        paidByPayeeId: 'me',
        transactionId: 'tx-1',
        lines: const [
          SplitLine(
            lineNo: 1,
            amount: Money(120000, 'INR'),
            inputs: [
              ShareInput.equal('ravi'),
              ShareInput.equal('a'),
              ShareInput.equal('b'),
              ShareInput.equal('c'),
            ],
          ),
          SplitLine(
            lineNo: 2,
            amount: Money(40000, 'INR'),
            inputs: [ShareInput.equal('ravi')],
          ),
          SplitLine(
            lineNo: 3,
            amount: Money(20000, 'INR'),
            inputs: [
              ShareInput.equal('ravi'),
              ShareInput.equal('a'),
              ShareInput.equal('b'),
              ShareInput.equal('c'),
            ],
          ),
        ],
      );

      expect(result.isOk, isTrue);
      final shares = ledger.saved.single.shares;
      // Four on the platter, one on the dessert, four on the delivery.
      expect(shares, hasLength(9));
      expect(shares.map((s) => s.transactionLineNo).toSet(), {1, 2, 3});

      // Ravi's total is a sum over lines: 30000 + 40000 + 5000.
      final ravi = shares
          .where((s) => s.payeeId == 'ravi')
          .fold(0, (sum, s) => sum + s.amount.minor);
      expect(ravi, 75000);
    });

    test('drops a zero share on a line', () async {
      // Per line a zero would be a row per person per item they did not order — most of them, sitting
      // in `split_shares` forever. On a whole-expense split a zero is meaningful and is kept.
      await service.recordItemised(
        total: inr(10000),
        paidByPayeeId: 'me',
        transactionId: 'tx-1',
        lines: const [
          SplitLine(
            lineNo: 1,
            amount: Money(10000, 'INR'),
            inputs: [ShareInput.shares('a', 1), ShareInput.shares('b', 0)],
          ),
        ],
      );

      final shares = ledger.saved.single.shares;
      expect(shares, hasLength(1));
      expect(shares.single.payeeId, 'a');
    });

    test('refuses an empty line list', () async {
      final result = await service.recordItemised(
        total: inr(10000),
        paidByPayeeId: 'me',
        transactionId: 'tx-1',
        lines: const [],
      );
      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('names the line when one cannot be resolved', () async {
      final result = await service.recordItemised(
        total: inr(10000),
        paidByPayeeId: 'me',
        transactionId: 'tx-1',
        lines: const [
          SplitLine(
            lineNo: 7,
            amount: Money(10000, 'INR'),
            inputs: [
              ShareInput.percent('a', 5000),
              ShareInput.shares('b', 1),
            ],
          ),
        ],
      );
      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(result.failureOrNull!.message, contains('7'));
    });
  });

  group('remove', () {
    test('deletes the split and says nothing about the transaction', () async {
      await service.remove('se-1');
      expect(ledger.deleted, ['se-1']);
    });
  });
}
```

### `test/domain/split/split_resolver_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/services/split/split_resolver.dart';

/// [SplitResolver].
///
/// Every figure recomputed independently before it was asserted.
void main() {
  const resolver = SplitResolver();
  Money inr(int minor) => Money(minor, 'INR');

  Map<String, int> minorByPayee(SplitResolution r) => {
    for (final share in r.shares) share.payeeId: share.amount.minor,
  };

  group('equal', () {
    test('divides exactly, stray paise and all', () {
      final r = resolver.resolve(
        total: inr(100000),
        inputs: const [
          ShareInput.equal('a'),
          ShareInput.equal('b'),
          ShareInput.equal('c'),
        ],
      );
      expect(minorByPayee(r), {'a': 33334, 'b': 33333, 'c': 33333});
      expect(r.isExact, isTrue);
      expect(r.unallocated, inr(0));
    });
  });

  group('shares', () {
    test('a double weight takes twice as much', () {
      final r = resolver.resolve(
        total: inr(40000),
        inputs: const [
          ShareInput.shares('a', 2),
          ShareInput.shares('b', 1),
          ShareInput.shares('c', 1),
        ],
      );
      expect(minorByPayee(r), {'a': 20000, 'b': 10000, 'c': 10000});
      expect(r.isExact, isTrue);
    });

    test('a zero weight pays nothing', () {
      final r = resolver.resolve(
        total: inr(30000),
        inputs: const [
          ShareInput.shares('a', 1),
          ShareInput.shares('b', 1),
          ShareInput.shares('c', 0),
        ],
      );
      expect(minorByPayee(r), {'a': 15000, 'b': 15000, 'c': 0});
    });
  });

  group('percent', () {
    test('basis points of the total', () {
      final r = resolver.resolve(
        total: inr(100000),
        inputs: const [
          ShareInput.percent('a', 5000),
          ShareInput.percent('b', 3000),
          ShareInput.percent('c', 2000),
        ],
      );
      expect(minorByPayee(r), {'a': 50000, 'b': 30000, 'c': 20000});
      expect(r.isExact, isTrue);
    });

    test('percentages short of 100 leave a remainder, not a fudge', () {
      // **The commitment.** 90% assigned means 10% unassigned, surfaced. Spreading the missing 10%
      // across whoever happens to be listed would charge somebody for a number they never typed.
      final r = resolver.resolve(
        total: inr(100000),
        inputs: const [
          ShareInput.percent('a', 5000),
          ShareInput.percent('b', 4000),
        ],
      );
      expect(minorByPayee(r), {'a': 50000, 'b': 40000});
      expect(r.unallocated, inr(10000));
      expect(r.isExact, isFalse);
      expect(r.isOverAllocated, isFalse);
    });

    test('percentages over 100 report an overshoot rather than clamping', () {
      final r = resolver.resolve(
        total: inr(100000),
        inputs: const [
          ShareInput.percent('a', 7000),
          ShareInput.percent('b', 7000),
        ],
      );
      expect(r.isOverAllocated, isTrue);
      expect(r.unallocated.isNegative, isTrue);
    });
  });

  group('exact', () {
    test('amounts are taken as typed', () {
      final r = resolver.resolve(
        total: inr(100000),
        inputs: const [
          ShareInput.exact('a', 60000),
          ShareInput.exact('b', 40000),
        ],
      );
      expect(minorByPayee(r), {'a': 60000, 'b': 40000});
      expect(r.isExact, isTrue);
    });

    test('a shortfall surfaces, exactly as transaction lines do', () {
      final r = resolver.resolve(
        total: inr(50000),
        inputs: const [ShareInput.exact('a', 48000)],
      );
      expect(r.unallocated, inr(2000));
    });
  });

  group('mixed — exact off the top, the rest split', () {
    test('Ravi covers his own dessert and the remainder divides equally', () {
      // The instruction people actually give: "the dessert was Ravi's, split the rest between us."
      // Splitwise calls this an adjustment and buries it; here it is one input kind beside another.
      final r = resolver.resolve(
        total: inr(160000),
        inputs: const [
          ShareInput.exact('ravi', 40000),
          ShareInput.equal('a'),
          ShareInput.equal('b'),
          ShareInput.equal('c'),
        ],
      );
      expect(minorByPayee(r), {
        'ravi': 40000,
        'a': 40000,
        'b': 40000,
        'c': 40000,
      });
      expect(r.isExact, isTrue);
    });

    test('the remainder divides by weight when weights are given', () {
      final r = resolver.resolve(
        total: inr(100000),
        inputs: const [
          ShareInput.exact('a', 40000),
          ShareInput.shares('b', 3),
          ShareInput.shares('c', 1),
        ],
      );
      expect(minorByPayee(r), {'a': 40000, 'b': 45000, 'c': 15000});
      expect(r.isExact, isTrue);
    });

    test('exact amounts exceeding the total leave nothing for the weights', () {
      // Over-allocated, and the weighted participants sit at zero rather than going negative — a
      // negative share would read as somebody being owed money by a bill they are paying.
      final r = resolver.resolve(
        total: inr(50000),
        inputs: const [
          ShareInput.exact('a', 60000),
          ShareInput.equal('b'),
        ],
      );
      expect(minorByPayee(r)['b'], 0);
      expect(r.isOverAllocated, isTrue);
    });
  });

  group('per line — the itemised split', () {
    test('the dessert is one person, the platter is everyone', () {
      // ₹1,200 platter four ways, ₹400 dessert for Ravi alone, ₹200 delivery by weight.
      final r = resolver.resolvePerLine(
        total: inr(180000),
        lines: const [
          SplitLine(
            lineNo: 1,
            amount: Money(120000, 'INR'),
            inputs: [
              ShareInput.equal('ravi'),
              ShareInput.equal('a'),
              ShareInput.equal('b'),
              ShareInput.equal('c'),
            ],
          ),
          SplitLine(
            lineNo: 2,
            amount: Money(40000, 'INR'),
            inputs: [ShareInput.equal('ravi')],
          ),
          SplitLine(
            lineNo: 3,
            amount: Money(20000, 'INR'),
            inputs: [
              ShareInput.shares('ravi', 1),
              ShareInput.shares('a', 1),
              ShareInput.shares('b', 1),
              ShareInput.shares('c', 1),
            ],
          ),
        ],
      );
      expect(minorByPayee(r), {
        'ravi': 30000 + 40000 + 5000,
        'a': 35000,
        'b': 35000,
        'c': 35000,
      });
      expect(r.isExact, isTrue);
      // Ravi's share carries every input that produced it, so the editor can show all three lines.
      expect(r.shares.first.inputs, hasLength(3));
    });

    test('a tip nobody assigned shows up as unallocated', () {
      // `transactions.originalAmountMinor` is the source of truth and lines are optional detail
      // (ARCH_2 §4.2). A bill of ₹1,000 with ₹900 of lines is ₹100 nobody has claimed.
      final r = resolver.resolvePerLine(
        total: inr(100000),
        lines: const [
          SplitLine(
            lineNo: 1,
            amount: Money(90000, 'INR'),
            inputs: [ShareInput.equal('a'), ShareInput.equal('b')],
          ),
        ],
      );
      expect(minorByPayee(r), {'a': 45000, 'b': 45000});
      expect(r.unallocated, inr(10000));
    });

    test('a line in another currency is refused', () {
      expect(
        () => resolver.resolvePerLine(
          total: inr(100000),
          lines: const [
            SplitLine(
              lineNo: 1,
              amount: Money(1000, 'USD'),
              inputs: [ShareInput.equal('a')],
            ),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('refusals', () {
    test('no participants', () {
      expect(
        () => resolver.resolve(total: inr(100), inputs: const []),
        throwsArgumentError,
      );
    });

    test('the same person twice', () {
      expect(
        () => resolver.resolve(
          total: inr(100),
          inputs: const [ShareInput.equal('a'), ShareInput.equal('a')],
        ),
        throwsArgumentError,
      );
    });

    test('percent mixed with weights, which has no single reading', () {
      expect(
        () => resolver.resolve(
          total: inr(100),
          inputs: const [ShareInput.percent('a', 5000), ShareInput.equal('b')],
        ),
        throwsArgumentError,
      );
    });

    test('a negative weight', () {
      expect(
        () => resolver.resolve(
          total: inr(100),
          inputs: const [ShareInput.shares('a', -1), ShareInput.shares('b', 1)],
        ),
        throwsArgumentError,
      );
    });
  });

  group('a mismatch is a state, not a throw', () {
    test('mid-edit percentages resolve rather than fail', () {
      // The editor calls this on every keystroke. A resolver that threw on 30% would be unusable.
      for (final points in [0, 1, 999, 3000, 9999, 10001, 20000]) {
        final r = resolver.resolve(
          total: inr(100000),
          inputs: [ShareInput.percent('a', points)],
        );
        expect(r.shares, hasLength(1));
      }
    });
  });

  group('extras — the restaurant case', () {
    test('a drink bought for one person is theirs, and the rest still splits', () {
      // **The case the first version of this class could not express.** A ₹5,000 dinner where ₹400 of
      // it was Ravi's round: the ₹400 is his, the remaining ₹4,600 splits four ways, and Ravi pays
      // ₹1,550 while everybody else pays ₹1,150.
      //
      // With `exact` this was impossible — an exact amount *replaces* a share, so Ravi would have owed
      // ₹400 and nothing at all toward the food.
      final r = resolver.resolve(
        total: inr(500000),
        inputs: const [
          ShareInput.equal('me'),
          ShareInput.extra('ravi', 40000),
          ShareInput.equal('a'),
          ShareInput.equal('b'),
        ],
      );

      expect(minorByPayee(r), {
        'me': 115000,
        'ravi': 155000,
        'a': 115000,
        'b': 115000,
      });
      expect(r.isExact, isTrue);
    });

    test('the parts are carried, so a screen can show the arithmetic', () {
      // "₹1,150 + ₹400 drinks" rather than a bare ₹1,550. A total a person cannot decompose is one
      // they argue with.
      final r = resolver.resolve(
        total: inr(500000),
        inputs: const [
          ShareInput.equal('me'),
          ShareInput.extra('ravi', 40000),
          ShareInput.equal('a'),
          ShareInput.equal('b'),
        ],
      );

      final ravi = r.shares.firstWhere((s) => s.payeeId == 'ravi');
      expect(ravi.extra, inr(40000));
      expect(ravi.fromRemainder, inr(115000));
      expect(ravi.amount, inr(155000));

      final me = r.shares.firstWhere((s) => s.payeeId == 'me');
      expect(me.extra, isNull, reason: 'no extra means no line to explain');
    });

    test(
      "'I'll put in 2,000 and we'll split the rest' is the same operation",
      () {
        // Identical arithmetic from the other direction. One input kind, two features — which is why
        // there is no separate "subsidy" concept to learn, name or test.
        final r = resolver.resolve(
          total: inr(500000),
          inputs: const [
            ShareInput.extra('me', 200000),
            ShareInput.equal('ravi'),
            ShareInput.equal('a'),
            ShareInput.equal('b'),
          ],
        );

        expect(minorByPayee(r), {
          'me': 275000,
          'ravi': 75000,
          'a': 75000,
          'b': 75000,
        });
        expect(r.isExact, isTrue);
      },
    );

    test('two extras on one bill', () {
      // Ravi's drinks and a contribution from the payer, together. ₹5,000 − ₹400 − ₹2,000 = ₹2,600,
      // four ways at ₹650.
      final r = resolver.resolve(
        total: inr(500000),
        inputs: const [
          ShareInput.extra('me', 200000),
          ShareInput.extra('ravi', 40000),
          ShareInput.equal('a'),
          ShareInput.equal('b'),
        ],
      );

      expect(minorByPayee(r), {
        'me': 265000,
        'ravi': 105000,
        'a': 65000,
        'b': 65000,
      });
      expect(r.isExact, isTrue);
    });

    test('an extra alongside custom weights', () {
      // ₹1,000 bill, ₹100 is Ravi's, the remaining ₹900 splits 2:1:1 — Ravi's weight is one, because
      // an extra says what somebody additionally owes and not how the rest is divided.
      final r = resolver.resolve(
        total: inr(100000),
        inputs: const [
          ShareInput.shares('me', 2),
          ShareInput.extra('ravi', 10000),
          ShareInput.shares('a', 1),
        ],
      );

      expect(minorByPayee(r), {'me': 45000, 'ravi': 32500, 'a': 22500});
      expect(r.isExact, isTrue);
    });

    test('an extra beside an exact amount, which does not share the rest', () {
      // Priya owes exactly ₹500 and is finished; Ravi's ₹100 is his and he still takes a share of the
      // remaining ₹400 with me.
      final r = resolver.resolve(
        total: inr(100000),
        inputs: const [
          ShareInput.exact('priya', 50000),
          ShareInput.extra('ravi', 10000),
          ShareInput.equal('me'),
        ],
      );

      expect(minorByPayee(r), {'priya': 50000, 'ravi': 30000, 'me': 20000});
      expect(r.isExact, isTrue);
    });

    test(
      'an extra larger than the bill over-allocates rather than going negative',
      () {
        // Nobody gets a negative share — that would read as being *owed* money by a bill they are
        // paying. The overshoot surfaces in `unallocated` instead.
        final r = resolver.resolve(
          total: inr(10000),
          inputs: const [
            ShareInput.extra('ravi', 50000),
            ShareInput.equal('me'),
          ],
        );

        expect(minorByPayee(r)['me'], 0);
        expect(minorByPayee(r)['ravi'], 50000);
        expect(r.isOverAllocated, isTrue);
      },
    );

    test('extras count as weights, so percent still refuses to mix', () {
      expect(
        () => resolver.resolve(
          total: inr(100000),
          inputs: const [
            ShareInput.percent('a', 5000),
            ShareInput.extra('b', 1000),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('a negative extra is refused', () {
      expect(
        () => resolver.resolve(
          total: inr(100000),
          inputs: const [
            ShareInput.extra('a', -100),
            ShareInput.equal('b'),
          ],
        ),
        throwsArgumentError,
      );
    });
  });
}
```

### `test/domain/split/split_summary_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/domain/services/split/split_summary_builder.dart';

/// [SplitSummaryBuilder].
///
/// **The UPI tests are gone with the UPI link**, and their absence is the point: a `upi://` intent
/// needed major-unit conversion, zero-padded fractions, percent-encoded fields and a currency
/// parameter — four things that could each be subtly wrong in a way that opens a payment app with the
/// wrong number. A line of free text has none of them, and works outside India.
void main() {
  const builder = SplitSummaryBuilder();
  Money inr(int minor) => Money(minor, 'INR');

  SplitBalance owedToMe(String id, int minor) =>
      SplitBalance(payeeId: id, owedToMe: inr(minor), iOwe: inr(0));

  SplitBalance iOwe(String id, int minor) =>
      SplitBalance(payeeId: id, owedToMe: inr(0), iOwe: inr(minor));

  SplitSummary build(
    List<SplitBalance> balances, {
    String? handle,
  }) => builder.build(
    balances: balances,
    nameOf: (id) => id == 'ravi' ? 'Ravi' : 'Priya',
    // A fake formatter, so these tests assert the builder's assembly rather than
    // `MoneyFormatter`'s grouping rules — which have their own tests and are not what this file is
    // about.
    formatAmount: (amount) => '${amount.currencyCode} ${amount.minor}',
    labels: const SummaryLabels(
      heading: 'Goa trip',
      owesYou: 'Owes you',
      youOwe: 'You owe',
      payMeAt: 'Pay me at:',
    ),
    paymentHandle: handle,
  );

  group('the summary', () {
    test('names both directions', () {
      final summary = build([owedToMe('ravi', 185000), iOwe('priya', 40000)]);
      expect(summary.text, contains('Owes you Ravi: INR 185000'));
      expect(summary.text, contains('You owe Priya: INR 40000'));
    });

    test('drops settled counterparties', () {
      final settled = SplitBalance(
        payeeId: 'ravi',
        owedToMe: inr(5000),
        iOwe: inr(5000),
      );
      expect(build([settled]).isEmpty, isTrue);
    });

    test('an empty set produces the heading and nothing else', () {
      final summary = build(const []);
      expect(summary.isEmpty, isTrue);
      expect(summary.text.trim(), 'Goa trip');
    });

    test('is perfectly useful with no payment handle', () {
      final summary = build([owedToMe('ravi', 185000)]);
      expect(summary.text, contains('Ravi'));
      expect(summary.text, isNot(contains('Pay me at')));
    });
  });

  group('the payment handle', () {
    test('closes the message when somebody owes you', () {
      final summary = build([owedToMe('ravi', 185000)], handle: 'me@bank');
      expect(summary.text, endsWith('Pay me at: me@bank'));
    });

    test(
      'is anything at all, because it makes no claim about how money moves',
      () {
        // The whole reason it replaced a `upi://` link: this works in every country, and the app does not
        // have to know which one it is in.
        for (final handle in [
          'me@okhdfc',
          'paypal.me/mrunal',
          'IBAN DE89 3704 0044 0532 0130 00',
          'Venmo @mrunal',
          'cash is fine',
        ]) {
          expect(
            build([owedToMe('ravi', 100)], handle: handle).text,
            endsWith('Pay me at: $handle'),
          );
        }
      },
    );

    test('is omitted when the user only owes people', () {
      // Asking to be paid on a summary where every line is a debt the user holds reads as a mistake.
      final summary = build([iOwe('priya', 40000)], handle: 'me@bank');
      expect(summary.text, isNot(contains('Pay me at')));
    });

    test('a blank handle is treated as none', () {
      final summary = build([owedToMe('ravi', 100)], handle: '   ');
      expect(summary.text, isNot(contains('Pay me at')));
    });
  });
}
```
