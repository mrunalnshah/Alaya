# Phase 3A — Pure Domain Entities & Repository Contracts

> **Regenerated 2026-08-02 from the canonical tree.** Every fix through the Phase 6C debugging
> pass is folded in; this document and the working tree are in sync, and regenerating from it
> reproduces the code that runs. Earlier revisions reintroduce defects listed in ARCH_6 §3.
>
> Files shared with other phase documents — `app_en.arb`, `routes.dart`, `app_router.dart`,
> `layout_overflow_test.dart`, and the Phase 6A editor files amended by 6B and 6C — carry
> **identical** content in every copy, so they may be applied in any order.

**21 entities · 17 repository contracts · 159 contract methods · zero forbidden imports.**

## Add dependencies

None. The domain layer imports nothing outside `lib/core/`.

## The one deviation from the brief, and why

The brief lists `Asset.warrantyDaysLeft` as a getter, alongside `RecurringOccurrence.isOverdue(today)`
and `Batch.isExpired(today)` which are shown taking a parameter. **Days-remaining cannot be a bare
getter**: it is meaningless without a reference date, so a getter would have to read the clock —
making it non-deterministic and untestable, exactly the problem ARCH_2 §12.2 solved for the views.

Shipped as `Asset.warrantyDaysLeftFrom(DateKey today)`. The brief's actual requirement — that
derived state is computed rather than stored — is honoured; only the signature differs, and it now
matches the two neighbouring examples. Verified across the whole layer: **zero clock reads in
executable code.**

## Verification performed

| Check | Result |
|---|---|
| **L12 — `domain/` importing flutter, drift or `data/`** | **0 violations**, confirmed by running Phase 1A's `tool/check_layering.dart` logic |
| Every `package:alaya/...` import resolves to a real file | 127 checked, 0 missing |
| Brace/paren/bracket balance | 38 files, 0 unbalanced |
| `const` ctor + `copyWith` + `==` + `hashCode` on every entity | 21/21, with 5 deliberate `copyWith` omissions (below) |
| Raw `int`/`double` standing in for an amount or quantity | 0 — the one regex hit was `Unit.factorToBaseMilli`, a *ratio* defining the unit, not a measurement (ARCH_1 §5.3 specifies an integer) |
| Repository return shapes | 159 methods, all `Future`/`Stream` of entities or `Result<T, Failure>` |
| Drift row types crossing the boundary | 0 — no `*Row` type is named anywhere in `domain/` |
| Clock reads in executable code | 0 (two matches were doc-comment prose about `FixedClock`) |
| `Transaction.signedAmount` semantics | simulated: deposit `+`, withdrawal `−`, adjustments signed, **transfer exactly 0** |
| `Transaction.signedAmountFor` | Cash→Bank 5000 gives `cash=−5000, bank=+5000, unrelated=0`; the two legs sum to zero — matches `v_account_ledger` |
| `RecurringTemplate.clampedDayFor` | anchor 31 → 31 Jan, 28 Feb, 29 Feb in a leap year, 30 Apr — anchor never rewritten |

## Findings

**1. `Transaction.signedAmount` is zero for a transfer, and that is the point.** It answers "what did
this do to my net worth", and moving money between your own accounts does exactly nothing to it
(anomaly A02). Because a bare signed amount is genuinely ill-defined for a transfer — it depends
which account you are standing in — there is a second member, `signedAmountFor(accountId)`, giving
one account's leg. Together they mirror `v_account_ledger`: sum the legs across a transfer's two
accounts and you get zero, by construction rather than by arithmetic anyone has to get right.

**2. Five entities deliberately have no `copyWith`.** `AccountBalance`, `ItemStock`, `CalendarEvent`
and `ConvertedMoney` are read-only projections of views — nothing writes them, so a `copyWith` would
imply an update path that does not exist. `StockMovement` is the interesting one: it is append-only
(Law L6's stated exception), and offering a `copyWith` would invite exactly the edit the ledger
exists to make impossible. Correcting a movement means recording a reversing one.

**3. `copyWith` cannot clear a nullable field, and that is documented rather than solved.** Every
parameter is nullable and falls back with `??`, so passing `null` means "leave unchanged". The
alternative — a sentinel object per parameter — costs far more noise across 21 entities than it
earns, given that clearing is rare and confined to a handful of repository operations (undisposing
an asset, unlinking a deleted transaction) that construct directly instead. Stated once on
`Currency.copyWith` and cross-referenced from the other twenty.

**4. `Tag` carries an `isDeleted` flag; no other entity does.** Persistence state normally has no
business in a domain model, and repositories filter soft-deletes on the way out. A deleted tag is the
exception because it keeps its links so history stays readable, and the UI renders it greyed with
`(deleted)` (anomaly A36) — so here the flag is genuinely display state, not a leaked column.

**5. `Tag.allowedScopes` is a `Set<TagScope>`, not six booleans.** The six `allowedIn*` columns are
one concept, and a set makes `isAllowedIn(scope)` a containment check rather than a switch that can
select the wrong column — which is the mistake that would put `Kitchen` in the deposit picker
(ARCH_2 §14). `hashCode` uses `Object.hashAllUnordered` so two equal sets built in different orders
still hash alike.

**6. Instants are `DateTime` (UTC), amounts are `Money`, quantities are `Qty`, civil dates are
`DateKey`.** Law L4 governs the *column* type — epoch millis — and mappers convert at the boundary.
A domain entity holding a raw `int` millisecond would be a primitive obsession the rest of the layer
avoids. The field names say so: `occurredAtUtc`, `checkedAtUtc`.

**7. `TransactionLine.pricePerBaseUnit` returns a `double`, deliberately.** It is the one place a
non-`Money` numeric appears in a monetary context, because a price *per unit* is a derived ratio for
comparison — the input to ARCH_3 §5.1 query 24's personal-inflation insight — not an amount anyone
stores. Law L1 governs persisted amounts.

**8. Contract coverage matches the implementation phases exactly.** 15 of the 17 contracts line up
one-for-one with what Phases 3B, 3C and 3D are scheduled to implement. The two extras,
`CalendarRepository` and `AnalyticsCacheRepository`, exist because their consumers —
`domain/services/calendar_aggregator.dart` and `domain/services/analytics/` in Phase 4C — live inside
`domain/`, and Law L12 forbids them importing from `data/`. There is deliberately **no**
`NotificationRepository` or `BackupHistoryRepository`: their only consumers are in `data/backup/`,
`data/security/` and Phase 8B's feature layer, all of which may use DAOs directly, so a contract
nobody implements would be dead code.

**9. Two contracts carry small result types rather than returning bare values.**
`TransactionRepository.delete` returns `DetachedArtefacts`, which separates batches that were merely
unlinked from those that are *provably untouched* — only the latter may be offered for removal, since
food already eaten must never be (anomaly A10). And `AccountRepository.watchTotalInHomeCurrency`
returns the total **with** an unconverted count, so the UI can show the `+N unconverted` chip instead
of a quietly wrong headline (anomaly A34).



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
  int get hashCode =>
      Object.hashAll([dateKey, type, refType, refId, title, baseSeverity, amount]);

  @override
  String toString() => 'CalendarEvent(${type.name} $refId on ${dateKey.toIso()})';
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
      defaultDisplayUnitCode: defaultDisplayUnitCode ?? this.defaultDisplayUnitCode,
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
        id, name, normalizedName, unitCategory, defaultDisplayUnitCode, itemKind,
        isFavorite, lowStockThreshold, expiryNotifyDays, notes,
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
        id, listId, origin, autoState, isChecked, sortOrder, itemId, freeText,
        quantity, unitCode, tagId, estimatedPrice, checkedAtUtc, snoozeUntilDateKey,
        stockAtGeneration, purchasedTransactionLineId,
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
  /// Never sum these directly — accounts may hold different currencies (anomaly A34). Use
  /// [watchTotalInHomeCurrency] for a headline figure.
  Stream<List<AccountBalance>> watchBalances();

  /// Emits one account's balance.
  Stream<AccountBalance?> watchBalanceOf(String accountId);

  /// Emits the net-worth headline: every included account's balance converted to the home
  /// currency, alongside how many amounts could not be converted.
  ///
  /// Returns the unconverted count rather than silently dropping those amounts, so the UI can show
  /// the `+N unconverted` chip instead of a quietly wrong total (anomaly A34).
  Stream<({Money total, int unconvertedCount})> watchTotalInHomeCurrency();

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

### `lib/domain/repositories/stock_repository.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/stock_movement.dart';

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
  /// Consumes [quantity] of [itemId] in FEFO order, across as many batches as needed.
  ///
  /// Returns which batches were drawn from and by how much, so the UI can show that 600 g came out
  /// of two batches *before* confirming (anomaly A08).
  ///
  /// Fails with a [BusinessRuleFailure] when total stock is insufficient, writing nothing — a
  /// partial consumption would leave the ledger describing something that did not happen.
  Future<Result<List<ConsumptionDraw>, Failure>> consume({
    required String itemId,
    required Qty quantity,
    required StockMovementKind kind,
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
