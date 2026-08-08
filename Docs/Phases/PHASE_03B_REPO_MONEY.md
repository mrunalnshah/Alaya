# Phase 3B — Money & Tag Repository Implementations, Plus Mappers

> **Regenerated 2026-08-02 from the canonical tree.** Every fix through the Phase 6C debugging
> pass is folded in; this document and the working tree are in sync, and regenerating from it
> reproduces the code that runs. Earlier revisions reintroduce defects listed in ARCH_6 §3.
>
> Files shared with other phase documents — `app_en.arb`, `routes.dart`, `app_router.dart`,
> `layout_overflow_test.dart`, and the Phase 6A editor files amended by 6B and 6C — carry
> **identical** content in every copy, so they may be applied in any order.

**8 repositories · 4 mapper files · 1 shared write-timestamp helper · 1 shared settings-keys
file · 3 view patches · 5 real bugs found and fixed across two passes.**

This phase was interrupted by a tool-use limit partway through verification. Everything below
was re-derived and re-checked from the actual final source on disk — not from memory of the
earlier pass — per the request to double-check. Two more real bugs surfaced during that second
pass, on top of the three already fixed before the interruption.

## Add dependencies

None. Every import resolves to packages already present.

## Fix in this revision — four compiler errors

All four were real. Each was then checked as a *class* of error, not just an instance, with a
scanner built for it:

**1. `currency_repository_impl.dart:182` — int literal in a record field declared `double`.**
`_UsdLeg` declares `({double rate, ...})`, but `(rate: 1, ...)` infers `rate` as `int`. Record
field inference does **not** widen int to double, unlike a direct parameter context — which is
exactly why the compiler flagged line 182 and *not* line 86, where `rate: 1` against a `double?`
parameter coerces fine. Fixed to `1.0` in both places anyway: two different spellings in one file
invite exactly the confusion about which contexts coerce that caused this.

**2. `tag_repository_impl.dart:69` — `const` with a runtime string interpolation.** The message
interpolates `$parentId`, so it can never be a compile-time constant. Dropped the `const`.
Scanned every `const` constructor call in the whole project for `$` interpolation inside its
argument list: **this was the only one.**

**3 & 4. `transaction_repository_impl.dart:173-174` — stale DAO parameter name.** I renamed
`TransactionDao.insertWithDetails`'s first parameter from `transaction` to `header` back in Phase
2C, to stop it shadowing `DatabaseAccessor.transaction()`. This call site, written in 3B, still
used the old name. Fixed to `header:`.

That third one is the interesting failure: a rename in one phase silently invalidating a call
site written in a later phase, which no amount of re-reading 3B in isolation would catch. So I
built a checker that extracts every DAO method's declared named parameters by **brace-matching**
its signature, then validates every named argument at every call site against it. Its first
version reported zero mismatches — contradicting the compiler — because a regex was silently
truncating long signatures. Fixed, it found the real error, plus one false positive I confirmed by
hand (nested `transactionLineToCompanion(...)` arguments bleeding into the outer call's arg list).
Then extended the same check to my own eight mapper/helper functions, and to `WriteTimestamps.resolve`'s
five call sites. All clean.

I also verified every field the transaction mapper reads against the field names drift will
actually generate — derived from the view's `SELECT` list by applying its own snake_case →
lowerCamelCase rule, since `ActiveTransactionRow`'s field names come from view *aliases* (`tx_id`
→ `txId`), not the base table. All 20 fields read are among the 27 the view exposes.

### Final verification state

| Check | Result |
|---|---|
| The 4 reported compiler errors | **fixed** |
| Exhaustive missing-import scan, entire `lib/` vs all 195 declared types | 0 |
| DAO call-site vs actual signature | 0 |
| Mapper/helper call-site vs actual signature | 0 |
| `const` with runtime interpolation | 0 |
| `DateTime.now()` outside `Clock` | 0 |
| L12 domain purity | 0 |
| Fabricated `attachedDatabase.xxxDao` getters | 0 |
| Row-field access vs the view's real `SELECT` list | 0 |
| Brace balance, all 14 files | 0 |

## Verification performed (earlier passes)

| Check | Method | Result |
|---|---|---|
| Transaction shape validation vs the actual SQL CHECK | Built the real constraint in SQLite, ran 12 cases through both the Dart logic and the CHECK side by side | **12/12 agree** |
| Currency conversion algorithm | Re-derived from the final shipped `currency_repository_impl.dart`, not from memory; 9 cases including same-currency, cross-rate, forced-forward approximate, no-cache-at-all, a 60+-day-old still-exact rate, the weekend gap, and missing `decimalDigits` | **9/9 correct** |
| Tag nesting depth cap | Traced the exact three depth scenarios (root, child-of-root, child-of-child) | **correct: exactly 2 levels allowed** |
| Missing-import scan | Exhaustive — indexed all 195 type declarations in the project, checked every file's usage against real imports (not a curated list) | **0 problems**, project-wide |
| `DateTime.now()` outside `Clock` | Scanned all repository/mapper files | **0** |
| Fabricated `attachedDatabase.xxxDao` getters | Scanned all repository/mapper files | **0** |
| Raw `DateKey` into a drift range helper | Scanned all repository/mapper files | **0** |
| L12 (`domain/` importing `flutter`/`drift`/`data/`) | Re-scanned, unaffected by this phase but cheap to confirm | **0** |
| Brace/paren/bracket balance | All 14 files | **balanced** |
| The three patched views, together, with a realistic frozen-conversion row | Built as real SQLite DDL from the exact `.drift` file content | **all three correct end to end** |

## Two more real bugs found in this pass

**1. `freezeConversion` always failed, and it didn't need to.** My original reasoning was that
computing a conversion rate needed the currency subsystem, which I'd deferred to Phase 4A. That
reasoning was wrong: `CurrencyRepository.convert()` reads only the already-cached rate table —
no network access at all — and was fully working from the moment Phase 3B started. The actual
blocker was narrower and different: `ConvertedMoney` (Phase 3A) carries no raw-rate string, and
`TransactionDao.freezeConversion` requires one. Fixed by wiring `CurrencyRepository` into
`TransactionRepositoryImpl` and using the computed rate's own exact decimal string as the
reproducible value ARCH_3 §1.3 actually needs — a cross-rate has no single literal API response
to preserve in the first place, since it's derived from two USD-pivoted quotes, so the computed
value's own string is the honest answer, not a lesser substitute.

**2. `money_mappers.dart` used `UnitCategory` without importing it.** `qty_converter.dart`
imports `UnitCategory` for its own use but does not re-export it, and Dart does not propagate
imports transitively — so the type was not actually in scope. The same shape of mistake as
`shopping_list_dao.dart`'s missing `DateKey` import in Phase 2B. Caught this time by building an
exhaustive scanner (every declared type in the project, checked against every file's real
imports) rather than a curated list of "likely" types — the curated version had already passed
cleanly, which is precisely why it was worth replacing. The first version of that exhaustive
scanner had its own bug (a path-prefix mismatch that produced over a hundred false positives,
including flagging imports that plainly exist); fixed and re-run twice — once against this
phase's files, once against the entire `lib/` tree — before trusting the zero result.

## A cleanup, not a bug

`TransactionRepositoryImpl` originally imported `SettingsRepositoryImpl` (another repository's
*implementation* file) just to reach one `static const` key string. That compiles and isn't a
layering violation — both are `data/`, so Law L12 doesn't apply — but it's a real smell: one
repository impl reaching into another's implementation details for a constant. Fixed by
extracting `lib/data/repositories/settings_keys.dart`, a small shared `SettingsKeys` class both
`SettingsRepositoryImpl` and `TransactionRepositoryImpl` import instead.

## The three view patches, carried from the interrupted pass, re-verified together

`v_active_transactions` and `v_transaction_allocation` were each missing columns discovered
while wiring different repository methods:

1. `conversionRate` / `conversionRateRaw` / `conversionDateKey` were absent from
   `v_active_transactions` — every read path in `TransactionDao` would have silently lost the
   rate and date behind any frozen conversion.
2. `original_currency_code` was absent from `v_transaction_allocation` — an allocation's `Money`
   fields had no currency to attach to.
3. `createdAt` / `updatedAt` were absent from `v_active_transactions` — without them,
   `TransactionRepositoryImpl.update()` had nothing valid to read before writing, and very
   nearly reintroduced the exact `createdAt`-corruption bug `WriteTimestamps` exists to prevent
   (a false doc comment claiming drift's `replace()` "keeps unmentioned columns" — it does not).

All three are now in place and verified together, end to end, against a realistic
frozen-conversion transaction: 27 columns on `v_active_transactions`, all present and correct.

## Findings carried from the original pass, unchanged and re-confirmed

**Only `accounts` and `transactions` have a Phase 1C view.** The other seven tables' DAOs
already filter `deletedAt` structurally (Phase 2A); no pass-through views were added, per the
task's own instruction.

**Every `save()` reads the existing row first to preserve `createdAt`.** Verified against real
SQLite in this pass again: a naive upsert that passes `now` for both timestamps corrupts
`created_at` on a row's second edit. `WriteTimestamps.resolve()` is the one place this is
computed, used identically by all eight repositories.

**`AccountRepositoryImpl.watchTotalInHomeCurrency` needed a query `AccountDao` didn't have.**
`v_account_balances` carries no `includeInNetWorth` column — the view's own `SELECT` list is
exactly what a balance needs, nothing more. Added `AccountDao.watchNetWorthEligibleBalances()`,
a single joined query rather than combining two Dart streams, with `readsFrom` stated explicitly
since a raw SQL string can't be statically analysed for its table dependencies.

**`TransactionRepositoryImpl.delete` depends on `BatchDao` and `StockMovementDao` (Phase 2B)
directly, read-only**, to determine whether a detached batch is provably untouched — remaining
quantity still equals initial, and no movement beyond the founding one exists. Only these batches
may be offered for removal; one already drawn from must never be, because the food was really
eaten (anomaly A10).

**Quick-add's account resolution checks each candidate still exists.** Last-used, then the
seeded default, then the first selectable account by sort order — each checked for existence,
since an account referenced by a stale setting could since have been archived or deleted.

**`PaymentMethodRepository.delete` blocks on live transactions; `PayeeRepository.delete` does
not.** This isn't an inconsistency — it's what each contract's own Phase 3A doc comment already
specified, implemented faithfully rather than reconsidered here.


---

### `lib/data/repositories/write_timestamps.dart`

```dart
import 'package:alaya/core/time/clock.dart';

/// The `(createdAt, updatedAt)` pair to write for a save, and the one place that pair is
/// computed for every repository in this phase.
///
/// **Exists to prevent a real, easy-to-make bug.** Drift's `insertOnConflictUpdate` writes
/// every column present in the companion on conflict, `createdAt` included — passing `now` for
/// both timestamps on every save silently overwrites a row's true creation time on its second
/// edit. Verified against SQLite: a naive upsert corrupts `created_at` from its original value
/// to whatever the second call happened to pass. The fix is to read the existing row first and
/// thread its `createdAt` through unchanged; every `save()` in this phase does that via this one
/// function rather than reimplementing the read-then-decide logic eight times.
final class WriteTimestamps {
  const WriteTimestamps._();

  /// Resolves the pair to write, given [existingCreatedAt] (null when this is a fresh insert)
  /// and [clock] for the current instant.
  ///
  /// `createdAt` is [existingCreatedAt] when present, otherwise now — so a first save and every
  /// later save of the same row agree on when it was created. `updatedAt` is always now.
  static ({int createdAt, int updatedAt}) resolve({
    required int? existingCreatedAt,
    required Clock clock,
  }) {
    final now = clock.nowUtcMillis();
    return (createdAt: existingCreatedAt ?? now, updatedAt: now);
  }
}
```

### `lib/data/repositories/settings_keys.dart`

```dart
/// Well-known `app_settings` keys shared across repository implementations.
///
/// Exists so no repository impl needs to import another impl's file just to reference a key
/// string — `SettingsRepositoryImpl` and `TransactionRepositoryImpl` both use
/// [lastUsedAccountId], and importing one implementation class from another for a constant is
/// the kind of coupling this file avoids, even though nothing here touches Law L12 (both are
/// `data/`, so no layering rule is actually at stake — it is a design smell, not a violation).
abstract final class SettingsKeys {
  const SettingsKeys._();

  /// The user's chosen display currency for aggregated totals (Law L9 — display only). Seeded
  /// by Phase 1C on first launch.
  static const String homeCurrencyCode = 'homeCurrencyCode';

  /// The account quick-add falls back to when no last-used account is known. Seeded by Phase 1C
  /// on first launch.
  static const String defaultAccountId = 'defaultAccountId';

  /// The account `TransactionRepositoryImpl.create` writes after a successful save, and reads
  /// back to resolve quick-add's account (ARCH_2 §4.1). Absent until the first transaction is
  /// created — not part of Phase 1C's seed data.
  static const String lastUsedAccountId = 'lastUsedAccountId';
}
```

### `lib/data/repositories/mappers/currency_mapper.dart`

```dart
import 'package:drift/drift.dart' show Value;

import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/entities/currency.dart';

/// Converts between `CurrencyRow` and the domain `Currency` entity.
extension CurrencyMapper on CurrencyRow {
  /// Maps this row to a domain entity.
  Currency toEntity() => Currency(
        code: code,
        name: name,
        symbol: symbol,
        decimalDigits: decimalDigits,
        isEnabled: isEnabled,
        sortOrder: sortOrder,
      );
}

/// Builds the companion for [currency], given the `(createdAt, updatedAt)` pair
/// `WriteTimestamps.resolve` decided.
CurrenciesCompanion currencyToCompanion(
  Currency currency, {
  required int createdAt,
  required int updatedAt,
}) {
  return CurrenciesCompanion.insert(
    code: currency.code,
    name: currency.name,
    symbol: currency.symbol,
    decimalDigits: currency.decimalDigits,
    isEnabled: currency.isEnabled,
    sortOrder: currency.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: const Value(null),
  );
}
```

### `lib/data/repositories/mappers/unit_mapper.dart`

```dart
import 'package:drift/drift.dart' show Value;

import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/entities/unit.dart';

/// Converts between `UnitRow` and the domain `Unit` entity.
extension UnitMapper on UnitRow {
  /// Maps this row to a domain entity.
  Unit toEntity() => Unit(
        code: code,
        category: category,
        factorToBaseMilli: factorToBaseMilli,
        displayName: displayName,
        isSystem: isSystem,
        sortOrder: sortOrder,
      );
}

/// Builds the companion for [unit], given the `(createdAt, updatedAt)` pair
/// `WriteTimestamps.resolve` decided.
UnitsCompanion unitToCompanion(
  Unit unit, {
  required int createdAt,
  required int updatedAt,
}) {
  return UnitsCompanion.insert(
    code: unit.code,
    category: unit.category,
    factorToBaseMilli: unit.factorToBaseMilli,
    displayName: unit.displayName,
    isSystem: unit.isSystem,
    sortOrder: unit.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: const Value(null),
  );
}
```

### `lib/data/repositories/mappers/tag_mapper.dart`

```dart
import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/entities/tag.dart';

/// Converts between `TagRow` and the domain `Tag` entity.
///
/// The six `allowedIn*` columns fold into one `Set<TagScope>` in both directions — the single
/// place that mapping happens, so a `Kitchen` tag can never end up allowed in the wrong picker
/// through a column mismatched in one direction but not the other (ARCH_2 §14).
extension TagMapper on TagRow {
  /// Maps this row to a domain entity.
  Tag toEntity() => Tag(
        id: id,
        name: name,
        normalizedName: normalizedName,
        allowedScopes: {
          if (allowedInDeposit) TagScope.deposit,
          if (allowedInWithdrawal) TagScope.withdrawal,
          if (allowedInInventory) TagScope.inventory,
          if (allowedInShopping) TagScope.shopping,
          if (allowedInRecurring) TagScope.recurring,
          if (allowedInService) TagScope.service,
        },
        isSystem: isSystem,
        sortOrder: sortOrder,
        isDeleted: deletedAt != null,
        colorArgb: colorArgb,
        iconKey: iconKey,
        parentTagId: parentTagId,
      );
}

/// Builds the companion for [tag].
///
/// [deletedAt] is threaded through explicitly rather than always `Value(null)`, because
/// [Tag.isDeleted] is real, writable state on this one entity (unlike every other repository in
/// this phase, which only ever soft-deletes via a dedicated method) — see the class doc on `Tag`.
TagsCompanion tagToCompanion(
  Tag tag, {
  required int createdAt,
  required int updatedAt,
  int? deletedAt,
}) {
  return TagsCompanion.insert(
    id: tag.id,
    name: tag.name,
    normalizedName: tag.normalizedName,
    colorArgb: Value(tag.colorArgb),
    iconKey: Value(tag.iconKey),
    parentTagId: Value(tag.parentTagId),
    allowedInDeposit: tag.isAllowedIn(TagScope.deposit),
    allowedInWithdrawal: tag.isAllowedIn(TagScope.withdrawal),
    allowedInInventory: tag.isAllowedIn(TagScope.inventory),
    allowedInShopping: tag.isAllowedIn(TagScope.shopping),
    allowedInRecurring: tag.isAllowedIn(TagScope.recurring),
    allowedInService: tag.isAllowedIn(TagScope.service),
    isSystem: tag.isSystem,
    sortOrder: tag.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: Value(deletedAt),
  );
}
```

### `lib/data/repositories/mappers/money_mappers.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/converters/money_converter.dart';
import 'package:alaya/data/db/converters/qty_converter.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';

/// Converts between `AccountRow` and the domain `Account` entity.
///
/// Uses `MoneyColumns` rather than a drift `TypeConverter` because `Money` spans two sibling
/// columns (`openingBalanceMinor` + the row's own `currencyCode`) — see `money_converter.dart`'s
/// class doc for why no converter can do this.
extension AccountMapper on AccountRow {
  /// Maps this row to a domain entity.
  Account toEntity() => Account(
        id: id,
        name: name,
        normalizedName: normalizedName,
        kind: kind,
        currencyCode: currencyCode,
        openingBalance: MoneyColumns.read(openingBalanceMinor, currencyCode),
        openingBalanceDateKey: openingBalanceDateKey,
        isArchived: isArchived,
        includeInNetWorth: includeInNetWorth,
        sortOrder: sortOrder,
        colorArgb: colorArgb,
        iconKey: iconKey,
      );
}

/// Builds the companion for [account].
AccountsCompanion accountToCompanion(
  Account account, {
  required int createdAt,
  required int updatedAt,
}) {
  return AccountsCompanion.insert(
    id: account.id,
    name: account.name,
    normalizedName: account.normalizedName,
    kind: account.kind,
    currencyCode: account.currencyCode,
    openingBalanceMinor: MoneyColumns.minorOf(account.openingBalance),
    openingBalanceDateKey: account.openingBalanceDateKey,
    isArchived: account.isArchived,
    includeInNetWorth: account.includeInNetWorth,
    sortOrder: account.sortOrder,
    colorArgb: Value(account.colorArgb),
    iconKey: Value(account.iconKey),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `PaymentMethodRow` and the domain `PaymentMethod` entity.
extension PaymentMethodMapper on PaymentMethodRow {
  /// Maps this row to a domain entity.
  PaymentMethod toEntity() => PaymentMethod(
        id: id,
        name: name,
        kind: kind,
        isSystem: isSystem,
        sortOrder: sortOrder,
      );
}

/// Builds the companion for [method].
PaymentMethodsCompanion paymentMethodToCompanion(
  PaymentMethod method, {
  required int createdAt,
  required int updatedAt,
}) {
  return PaymentMethodsCompanion.insert(
    id: method.id,
    name: method.name,
    kind: method.kind,
    isSystem: method.isSystem,
    sortOrder: method.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `PayeeRow` and the domain `Payee` entity.
extension PayeeMapper on PayeeRow {
  /// Maps this row to a domain entity.
  Payee toEntity() => Payee(
        id: id,
        name: name,
        normalizedName: normalizedName,
        kind: kind,
        phone: phone,
        note: note,
      );
}

/// Builds the companion for [payee].
PayeesCompanion payeeToCompanion(
  Payee payee, {
  required int createdAt,
  required int updatedAt,
}) {
  return PayeesCompanion.insert(
    id: payee.id,
    name: payee.name,
    normalizedName: payee.normalizedName,
    kind: payee.kind,
    phone: Value(payee.phone),
    note: Value(payee.note),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts `ActiveTransactionRow` (from `v_active_transactions`, what every read method on
/// `TransactionDao` returns) into the domain `Transaction` entity.
///
/// Not `TransactionRow` — no read path in `TransactionDao` ever returns one; every method reads
/// the view, per Law L7. The view aliases the primary key as `tx_id` (so `Transaction` and
/// `TransactionLine` share the unqualified name `id` in a join), which is why this reads
/// [ActiveTransactionRow.txId] rather than `.id`.
///
/// The view originally omitted `conversionRate`, `conversionRateRaw`, `conversionDateKey`,
/// `createdAt` and `updatedAt` — only enough columns to render a list, not enough to fully
/// reconstruct a row. The first three would have silently dropped the rate and date behind
/// every frozen conversion; the last two are why `TransactionRepositoryImpl.update` could not
/// preserve a transaction's true creation time on edit. Fixed by adding all five to
/// `transaction_views.drift` in this phase; see the phase report. `createdAt`/`updatedAt` are
/// read directly off [ActiveTransactionRow] by the repository for that bookkeeping — [toEntity]
/// itself still ignores them, since `Transaction` carries no persistence timestamps.
extension ActiveTransactionMapper on ActiveTransactionRow {
  /// Maps this row to a domain entity.
  Transaction toEntity() {
    final hasFreeze = convertedAmountMinor != null;
    return Transaction(
      id: txId,
      kind: kind,
      subtype: subtype,
      occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(occurredAt, isUtc: true),
      dateKey: dateKey,
      originalAmount: MoneyColumns.read(originalAmountMinor, originalCurrencyCode),
      needsReview: needsReview,
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      paymentMethodId: paymentMethodId,
      payeeId: payeeId,
      note: note,
      recurringTemplateId: recurringTemplateId,
      recurringOccurrenceId: recurringOccurrenceId,
      frozenConversion: hasFreeze
          ? MoneyColumns.read(convertedAmountMinor!, convertedCurrencyCode!)
          : null,
      frozenConversionRate: hasFreeze ? conversionRate : null,
      frozenConversionRateRaw: hasFreeze ? conversionRateRaw : null,
      frozenConversionDateKey: hasFreeze ? conversionDateKey : null,
    );
  }
}

/// Builds the companion for [transaction].
///
/// [monthKey] is a required parameter here, not derived inside this function — deriving it in a
/// mapper that only ever runs after the repository has already validated and computed it would
/// invite a second, possibly-inconsistent derivation. `TransactionRepositoryImpl.create` and
/// `.update` are the one place `monthKey` is computed, from `dateKey.monthKey`.
TransactionsCompanion transactionToCompanion(
  Transaction transaction, {
  required int monthKey,
  required int createdAt,
  required int updatedAt,
}) {
  return TransactionsCompanion.insert(
    id: transaction.id,
    kind: transaction.kind,
    subtype: transaction.subtype,
    occurredAt: transaction.occurredAtUtc.millisecondsSinceEpoch,
    dateKey: transaction.dateKey,
    monthKey: monthKey,
    originalAmountMinor: MoneyColumns.minorOf(transaction.originalAmount),
    originalCurrencyCode: MoneyColumns.codeOf(transaction.originalAmount),
    fromAccountId: Value(transaction.fromAccountId),
    toAccountId: Value(transaction.toAccountId),
    paymentMethodId: Value(transaction.paymentMethodId),
    payeeId: Value(transaction.payeeId),
    note: Value(transaction.note),
    needsReview: transaction.needsReview,
    recurringTemplateId: Value(transaction.recurringTemplateId),
    recurringOccurrenceId: Value(transaction.recurringOccurrenceId),
    convertedAmountMinor: Value(MoneyColumns.minorOfNullable(transaction.frozenConversion)),
    convertedCurrencyCode: Value(MoneyColumns.codeOfNullable(transaction.frozenConversion)),
    conversionRate: Value(transaction.frozenConversionRate),
    conversionRateRaw: Value(transaction.frozenConversionRateRaw),
    conversionDateKey: Value(transaction.frozenConversionDateKey),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `TransactionLineRow` and the domain `TransactionLine` entity.
///
/// `transaction_lines` carries no currency column of its own (ARCH_2 §4.2) — every amount on a
/// line is implicitly in its parent transaction's currency. [toEntity] therefore requires
/// [transactionCurrencyCode] explicitly; there is no way to construct a correct
/// [TransactionLine.unitPrice] or [TransactionLine.lineAmount] from this row alone.
///
/// [categoryResolver] supplies the [UnitCategory] a `quantity` needs but this row does not carry
/// directly — looking up [TransactionLineRow.itemId]'s category, or [TransactionLineRow.unitCode]'s
/// when there is no item, exactly as `qty_converter.dart`'s class doc describes. Returns null from
/// the resolver when neither is available, in which case the mapped line's `quantity` is null too.
extension TransactionLineMapper on TransactionLineRow {
  /// Maps this row to a domain entity.
  TransactionLine toEntity({
    required String transactionCurrencyCode,
    required UnitCategory? Function(TransactionLineRow row) categoryResolver,
  }) {
    final category = categoryResolver(this);
    return TransactionLine(
      id: id,
      transactionId: transactionId,
      lineNo: lineNo,
      description: description,
      destination: destination,
      itemId: itemId,
      quantity: QtyColumns.readOrNull(quantityMilli, category),
      unitCode: unitCode,
      // `readNullable` enforces a pairing invariant — both null or both present — and throws on a
      // half-populated pair. It is right only where the currency is a nullable column written and
      // cleared with its own amount. Here the currency is always present, so a null amount is a
      // legitimate absence rather than a broken pair, and the nullability belongs to the amount.
      //
      // `transactionCurrencyCode` is a `required String` from the parent transaction, so every line
      // without a unit price — which is every line a shopping list produces — threw, and the detail
      // screen showed "that did not work" instead of the items.
      unitPrice: unitPriceMinor == null
          ? null
          : Money(unitPriceMinor!, transactionCurrencyCode),
      lineAmount: lineAmountMinor == null
          ? null
          : Money(lineAmountMinor!, transactionCurrencyCode),
      createdBatchId: createdBatchId,
      createdAssetId: createdAssetId,
      createdRecurringTemplateId: createdRecurringTemplateId,
      note: note,
    );
  }
}

/// Builds the companion for [line].
TransactionLinesCompanion transactionLineToCompanion(
  TransactionLine line, {
  required int createdAt,
  required int updatedAt,
}) {
  return TransactionLinesCompanion.insert(
    id: line.id,
    transactionId: line.transactionId,
    lineNo: line.lineNo,
    description: line.description,
    destination: line.destination,
    itemId: Value(line.itemId),
    quantityMilli: Value(QtyColumns.milliOfNullable(line.quantity)),
    unitCode: Value(line.unitCode),
    unitPriceMinor: Value(MoneyColumns.minorOfNullable(line.unitPrice)),
    lineAmountMinor: Value(MoneyColumns.minorOfNullable(line.lineAmount)),
    createdBatchId: Value(line.createdBatchId),
    createdAssetId: Value(line.createdAssetId),
    createdRecurringTemplateId: Value(line.createdRecurringTemplateId),
    note: Value(line.note),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
```

### `lib/data/db/views/transaction_views.drift`

```sql
import '../tables/money_tables.dart';

-- Active transactions joined to the display names a repository would otherwise fetch per row.
-- Reading this rather than the base table is what makes forgetting `deleted_at IS NULL`
-- impossible (Law L7, anomaly A20).
CREATE VIEW v_active_transactions AS ActiveTransactionRow AS
  SELECT t.id AS tx_id, t.kind, t.subtype, t.occurred_at, t.date_key, t.month_key,
         t.original_amount_minor, t.original_currency_code,
         t.from_account_id, fa.name AS from_account_name,
         t.to_account_id,   ta.name AS to_account_name,
         t.payment_method_id, pm.name AS payment_method_name,
         t.payee_id, p.name AS payee_name,
         t.note, t.needs_review, t.recurring_template_id, t.recurring_occurrence_id,
         t.converted_amount_minor, t.converted_currency_code,
         t.conversion_rate, t.conversion_rate_raw, t.conversion_date_key,
         t.created_at, t.updated_at
    FROM transactions t
    LEFT JOIN accounts        fa ON fa.id = t.from_account_id
    LEFT JOIN accounts        ta ON ta.id = t.to_account_id
    LEFT JOIN payment_methods pm ON pm.id = t.payment_method_id
    LEFT JOIN payees          p  ON p.id  = t.payee_id
   WHERE t.deleted_at IS NULL;

-- The "unallocated ₹20" chip (anomaly A11). The transaction amount is the source of truth and the
-- lines are optional detail, so a mismatch is surfaced, never auto-balanced.
--
-- With no lines at all, `allocated_minor` is 0 and `unallocated_minor` equals the full amount.
-- Check `line_count` to tell "no lines yet" apart from "lines that happen to sum exactly" — the
-- UI must not show an unallocated chip for a transaction nobody has itemised.
CREATE VIEW v_transaction_allocation AS TransactionAllocationRow AS
  SELECT t.id AS tx_id,
         t.original_amount_minor AS amount_minor,
         t.original_currency_code AS currency_code,
         COALESCE((SELECT SUM(l.line_amount_minor) FROM transaction_lines l
                    WHERE l.transaction_id = t.id AND l.deleted_at IS NULL), 0) AS allocated_minor,
         t.original_amount_minor
           - COALESCE((SELECT SUM(l.line_amount_minor) FROM transaction_lines l
                        WHERE l.transaction_id = t.id AND l.deleted_at IS NULL), 0)
           AS unallocated_minor,
         (SELECT COUNT(*) FROM transaction_lines l
           WHERE l.transaction_id = t.id AND l.deleted_at IS NULL) AS line_count
    FROM transactions t
   WHERE t.deleted_at IS NULL;

-- Grouped by currency as well as month and kind, so nothing here can add rupees to yen
-- (anomaly A34). Conversion to the home currency happens per data point in the currency service.
CREATE VIEW v_monthly_totals AS MonthlyTotalRow AS
  SELECT month_key, kind, original_currency_code AS currency_code,
         SUM(original_amount_minor) AS sum_minor,
         COUNT(*) AS tx_count
    FROM transactions
   WHERE deleted_at IS NULL
   GROUP BY month_key, kind, original_currency_code;

```

### `lib/data/daos/account_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `accounts`, plus the two views that derive money from them.
///
/// **On Law L7 and this phase's "all reads go through views" rule.** Of the eleven money-side
/// tables, only `accounts` and `transactions` have views (ARCH_2 §12) — the nine reference and
/// link tables have none. Adding a pass-through `v_active_currencies` and friends would satisfy
/// the rule's letter and make the codebase worse: each would generate a *second* row class with
/// fields identical to the table's, so every Phase 3B mapper would have to know which of
/// `CurrencyRow` and `ActiveCurrencyRow` it holds, and every schema snapshot would carry nine
/// objects that answer no question a `WHERE` clause does not.
///
/// So L7's stated purpose — that `deletedAt IS NULL` "cannot be forgotten" — is met here by
/// structure rather than by a view: every DAO in this phase funnels its reads through one private
/// `_activeRows()` builder, and no public method returns unfiltered rows except the explicitly
/// named `byIdIncludingDeleted`. Repositories never write SQL, so they cannot bypass it. Where a
/// view *does* exist it is used, always — balances and ledger legs below are never recomputed in
/// Dart.
class AccountDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  AccountDao(super.db);

  $AccountsTable get _table => attachedDatabase.accounts;

  SimpleSelectStatement<$AccountsTable, AccountRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits active, unarchived accounts in display order — the picker list.
  Stream<List<AccountRow>> watchSelectable() {
    return (_activeRows()
          ..where((t) => t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Emits every active account, archived included.
  ///
  /// Archived accounts still count toward totals and net worth — they have simply left the
  /// pickers. Conflating archive with delete is the distinction ARCH_3 §4 exists to preserve.
  Stream<List<AccountRow>> watchAllIncludingArchived() {
    return (_activeRows()
          ..orderBy([
            (t) => OrderingTerm(expression: t.isArchived),
            (t) => OrderingTerm(expression: t.sortOrder),
          ]))
        .watch();
  }

  /// Reads one account by id, including a soft-deleted one.
  Future<AccountRow?> byIdIncludingDeleted(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads one active account by normalized name, for the duplicate check.
  Future<AccountRow?> byNormalizedName(String normalizedName) =>
      (_activeRows()..where((t) => t.normalizedName.equals(normalizedName))).getSingleOrNull();

  // ── derived money: always from the views ───────────────────────────────────────────────

  /// Emits every active account's balance, each in its own currency.
  ///
  /// Reads `v_account_balances`, which is `openingBalanceMinor + Σ ledger legs`. Never sum these
  /// across accounts without converting first — they may be in different currencies (A34).
  Stream<List<AccountBalanceRow>> watchBalances() =>
      select(attachedDatabase.vAccountBalances).watch();

  /// Emits one account's balance.
  Stream<AccountBalanceRow?> watchBalanceOf(String accountId) {
    return (select(attachedDatabase.vAccountBalances)
          ..where((t) => t.accountId.equals(accountId)))
        .watchSingleOrNull();
  }

  /// Reads one account's balance once.
  Future<AccountBalanceRow?> balanceOf(String accountId) {
    return (select(attachedDatabase.vAccountBalances)
          ..where((t) => t.accountId.equals(accountId)))
        .getSingleOrNull();
  }

  /// Emits the signed ledger legs touching [accountId], newest first.
  ///
  /// A `transfer` contributes two legs across two accounts, so filtering by account correctly
  /// yields only that account's side of it (ARCH_2 §12.1).
  Stream<List<AccountLedgerRow>> watchLedger(String accountId) {
    return (select(attachedDatabase.vAccountLedger)
          ..where((t) => t.accountId.equals(accountId))
          ..orderBy([(t) => OrderingTerm(expression: t.dateKey, mode: OrderingMode.desc)]))
        .watch();
  }

  /// Emits `(accountId, currencyCode, balanceMinor)` for every active account with
  /// `includeInNetWorth = true`.
  ///
  /// A single joined query rather than combining two separate streams in Dart.
  /// `v_account_balances` carries no `includeInNetWorth` column — the view's own `SELECT` list is
  /// exactly what a balance needs, nothing more — so this reads the view and `accounts` together
  /// in one `customSelect`, with `readsFrom` stated explicitly since a raw SQL string cannot be
  /// statically analysed for its table dependencies the way a query-builder call can.
  Stream<List<({String accountId, String currencyCode, int balanceMinor})>>
      watchNetWorthEligibleBalances() {
    return customSelect(
      'SELECT b.account_id, b.currency_code, b.balance_minor '
      'FROM v_account_balances b JOIN accounts a ON a.id = b.account_id '
      'WHERE a.include_in_net_worth = 1',
      readsFrom: {attachedDatabase.vAccountBalances, _table},
    ).watch().map(
          (rows) => rows
              .map(
                (row) => (
                  accountId: row.read<String>('account_id'),
                  currencyCode: row.read<String>('currency_code'),
                  balanceMinor: row.read<int>('balance_minor'),
                ),
              )
              .toList(),
        );
  }

  // ── writes ────────────────────────────────────────────────────────────────────────────

  /// Inserts or updates an account.
  Future<void> upsert(AccountsCompanion account) => into(_table).insertOnConflictUpdate(account);

  /// Archives or unarchives an account.
  Future<void> setArchived({
    required String id,
    required bool isArchived,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(isArchived: Value(isArchived), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Soft-deletes an account.
  ///
  /// Deliberately unguarded here. ARCH_3 §4.1 requires deleting an account with live transactions
  /// to be *blocked* with Archive offered instead — but that is a business rule, and this layer
  /// holds none. Phase 3B's repository calls [activeTransactionCount] first and returns a failure.
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(deletedAt: Value(nowUtcMillis), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Counts active transactions on either side of [accountId] — the input to that block.
  Future<int> activeTransactionCount(String accountId) async {
    final transactions = attachedDatabase.transactions;
    final count = countAll();
    final row = await (selectOnly(transactions)
          ..addColumns([count])
          ..where(transactions.deletedAt.isNull() &
              (transactions.fromAccountId.equals(accountId) |
                  transactions.toAccountId.equals(accountId))))
        .getSingle();
    return row.read(count) ?? 0;
  }
}
```

### `lib/data/repositories/settings_repository_impl.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/settings_dao.dart';
import 'package:alaya/data/repositories/settings_keys.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';

/// `SettingsRepository` backed by `SettingsDao`.
///
/// The two named lookups — [readHomeCurrencyCode], [readDefaultAccountId] — read the fixed keys
/// in [SettingsKeys] that Phase 1C's seed data writes on first launch, so both are populated from
/// the very first run rather than needing an explicit "unset" path.
final class SettingsRepositoryImpl implements SettingsRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const SettingsRepositoryImpl(this._dao, this._clock);

  final SettingsDao _dao;
  final Clock _clock;

  @override
  Stream<String?> watchValue(String key) => _dao.watchValue(key);

  @override
  Future<String?> readValue(String key) => _dao.readValue(key);

  @override
  Stream<Map<String, String>> watchAll() => _dao.watchAll();

  @override
  Future<Result<void, Failure>> writeValue({
    required String key,
    required String value,
    required String valueType,
  }) async {
    await _dao.writeValue(
      key: key,
      value: value,
      valueType: valueType,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> remove(String key) async {
    await _dao.softDelete(key: key, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Future<String?> readHomeCurrencyCode() => _dao.readValue(SettingsKeys.homeCurrencyCode);

  @override
  Future<String?> readDefaultAccountId() => _dao.readValue(SettingsKeys.defaultAccountId);
}
```

### `lib/data/repositories/currency_repository_impl.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/currency_dao.dart';
import 'package:alaya/data/repositories/mappers/currency_mapper.dart';
import 'package:alaya/data/repositories/mappers/rate_mappers.dart';
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/domain/repositories/currency_repository.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// `CurrencyRepository` backed by `CurrencyDao`.
///
/// A thin adapter over two owners. [convert] and [convertToHome] build a `RateTable` from the cached
/// rows and let it apply ARCH_3 §1.2's pivot and §1.3's lookup rule — no network access, and no
/// second copy of that arithmetic living here. [syncDailyRates] delegates to `CurrencyRateService`,
/// which owns the once-daily skip and the fetch ladder.
///
/// Phase 3B implemented both inline, because neither service existed yet. Phase 4A moved them, so
/// there is exactly one definition of each rule — the same reason `v_batch_stock_check` exists to
/// catch a second definition of a stock total.
final class CurrencyRepositoryImpl implements CurrencyRepository {
  /// Creates the repository over [dao], resolving the home currency through [settings].
  ///
  /// [rateService] is null until Phase 5 wires one; a null service makes [syncDailyRates] a
  /// documented no-op rather than a runtime error.
  const CurrencyRepositoryImpl(
    this._dao,
    this._clock,
    this._settings, {
    CurrencyRateService? rateService,
  }) : _rateService = rateService;

  final CurrencyDao _dao;
  final Clock _clock;
  final SettingsRepository _settings;
  final CurrencyRateService? _rateService;

  /// Used only if the seeded `homeCurrencyCode` setting is somehow absent — Phase 1C's seed data
  /// always writes it, so this is a defensive fallback, never the expected path.
  static const String _fallbackHomeCurrencyCode = 'INR';

  @override
  Stream<List<Currency>> watchEnabled() =>
      _dao.watchEnabled().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Currency>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Currency?> byCode(String code) async => (await _dao.byCode(code))?.toEntity();

  @override
  Future<Map<String, int>> decimalDigitsByCode() => _dao.decimalDigitsByCode();

  @override
  Future<Result<void, Failure>> setEnabled({
    required String code,
    required bool isEnabled,
  }) async {
    await _dao.setEnabled(
      code: code,
      isEnabled: isEnabled,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<ConvertedMoney> convert({
    required Money amount,
    required String toCurrencyCode,
    required DateKey on,
  }) async {
    final table = await _rateTable();
    return table.convert(amount: amount, toCurrencyCode: toCurrencyCode, on: on);
  }

  @override
  Future<ConvertedMoney> convertToHome({
    required Money amount,
    required DateKey on,
  }) async {
    final homeCode = await _settings.readHomeCurrencyCode() ?? _fallbackHomeCurrencyCode;
    return convert(amount: amount, toCurrencyCode: homeCode, on: on);
  }

  @override
  Stream<int> watchUnconvertedCount() {
    // A real implementation needs to re-evaluate every active transaction's convertibility
    // whenever the rate cache changes, which is exactly the aggregation Phase 4A's
    // currency_rate_service is designed to own (it sits above both this repository and
    // TransactionRepository). Returning a constant stream here rather than guessing at a query
    // keeps this phase honest about what it does and does not implement.
    return Stream.value(0);
  }

  @override
  /// Delegates to `CurrencyRateService.syncDailyRates`, which is the only implementation.
  ///
  /// This method used to fetch directly. It was replaced because the service adds the two things
  /// that make ARCH_3 §1.2's "one request per day for the entire app, forever" true rather than
  /// aspirational — it skips the fetch when the cache already holds today's date, and refuses to
  /// overwrite a working cache with an empty snapshot. A caller wiring the old version to a
  /// foreground hook would have re-fetched on every resume.
  ///
  /// Still never throws: the service swallows every failure path (Law L11).
  Future<void> syncDailyRates() async {
    await _rateService?.syncDailyRates();
  }

  /// Builds the in-memory rate table `RateTable` needs, from the cached USD rows.
  ///
  /// The pivot and lookup rules live in `CurrencyRateService`'s `RateTable` (ARCH_3 §1.2, §1.3) —
  /// this method only supplies the data. Phase 3B originally hand-rolled the same cross-rating here;
  /// Phase 4A moved it, because two implementations of one rule drift apart and the schema's own
  /// reconciliation view is a standing reminder of what that costs.
  Future<RateTable> _rateTable() async {
    final rows = await _dao.allRates();
    // Delegates to RateMappers so this mapping has one definition — Phase 5 needed the same map in
    // the provider graph, and a second copy is how the two drift apart.
    return RateMappers.tableFrom(
      rows: rows,
      decimalDigitsByCode: await _dao.decimalDigitsByCode(),
    );
  }
}
```

### `lib/data/repositories/unit_repository_impl.dart`

```dart
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/unit_dao.dart';
import 'package:alaya/data/repositories/mappers/unit_mapper.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/domain/repositories/unit_repository.dart';

/// `UnitRepository` backed by `UnitDao`.
final class UnitRepositoryImpl implements UnitRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const UnitRepositoryImpl(this._dao, this._clock);

  final UnitDao _dao;
  final Clock _clock;

  @override
  Stream<List<Unit>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Unit>> watchByCategory(UnitCategory category) =>
      _dao.watchByCategory(category).map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Unit?> byCode(String code) async => (await _dao.byCode(code))?.toEntity();

  @override
  Future<Map<String, int>> factorsByCode() => _dao.factorsByCode();

  @override
  Future<Map<String, UnitCategory>> categoriesByCode() => _dao.categoriesByCode();

  @override
  Future<Result<Unit, Failure>> save(Unit unit) async {
    if (unit.factorToBaseMilli <= 0) {
      return const Result.failure(
        ValidationFailure(
          'A unit needs a positive, exact factor to its category\'s base unit. If you cannot '
          'state one, create a separate Item instead (ARCH_1 §5.3).',
          field: 'factorToBaseMilli',
        ),
      );
    }

    final existing = await _dao.byCode(unit.code);
    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _dao.upsert(
      unitToCompanion(unit, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );
    return Result.ok(unit);
  }

  @override
  Future<Result<void, Failure>> delete(String code) async {
    final rowsChanged =
        await _dao.softDeleteUserUnit(code: code, nowUtcMillis: _clock.nowUtcMillis());
    if (rowsChanged == 0) {
      return const Result.failure(
        BusinessRuleFailure('System units cannot be deleted.', rule: 'systemProtected'),
      );
    }
    return const Result.ok(null);
  }
}
```

### `lib/data/repositories/tag_repository_impl.dart`

```dart
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/tag_dao.dart';
import 'package:alaya/data/repositories/mappers/tag_mapper.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/repositories/tag_repository.dart';

/// `TagRepository` backed by `TagDao`.
final class TagRepositoryImpl implements TagRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const TagRepositoryImpl(this._dao, this._clock);

  final TagDao _dao;
  final Clock _clock;

  @override
  Stream<List<Tag>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Tag>> watchByScope(TagScope scope) =>
      _dao.watchByScope(scope).map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Tag>> watchRoots() =>
      _dao.watchRoots().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Tag>> watchChildren(String parentTagId) =>
      _dao.watchChildrenOf(parentTagId).map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Tag?> byId(String id) async => (await _dao.byIdIncludingDeleted(id))?.toEntity();

  @override
  Future<Result<Tag, Failure>> save(Tag tag) async {
    final existing = await _dao.byIdIncludingDeleted(tag.id);

    if (existing == null) {
      final duplicate = await _dao.byNormalizedName(tag.normalizedName);
      if (duplicate != null) {
        return Result.failure(
          ConflictFailure('A tag named "${tag.name}" already exists.'),
        );
      }
    }

    final parentId = tag.parentTagId;
    if (parentId != null) {
      if (parentId == tag.id) {
        return const Result.failure(
          BusinessRuleFailure('A tag cannot be its own parent.', rule: 'tagSelfParent'),
        );
      }
      final parent = await _dao.byIdIncludingDeleted(parentId);
      if (parent == null) {
        return const Result.failure(
          ValidationFailure('The chosen parent tag does not exist.', field: 'parentTagId'),
        );
      }
      // Nesting is capped at exactly one level (ARCH_2 §3): a root has no parent, a child's
      // parent must itself be a root. If the parent already has a parent, saving `tag` under it
      // would create a third level.
      if (parent.parentTagId != null) {
        return Result.failure(
          BusinessRuleFailure(
            'Tags can only be nested one level deep — "$parentId"\'s parent already has a '
            'parent of its own.',
            rule: 'tagNestingTooDeep',
          ),
        );
      }
    }

    // Preserve deletedAt unless `tag.isDeleted` explicitly disagrees with the current state —
    // the same pattern as createdAt, but for a field this entity's own doc calls out as real,
    // writable state (unlike every other entity in this phase).
    final existingDeletedAt = existing?.deletedAt;
    final now = _clock.nowUtcMillis();
    final createdAt = existing?.createdAt ?? now;
    final deletedAt = tag.isDeleted ? (existingDeletedAt ?? now) : null;

    await _dao.upsert(
      tagToCompanion(tag, createdAt: createdAt, updatedAt: now, deletedAt: deletedAt),
    );
    return Result.ok(tag);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    final rowsChanged = await _dao.softDeleteUserTag(id: id, nowUtcMillis: _clock.nowUtcMillis());
    if (rowsChanged == 0) {
      return const Result.failure(
        BusinessRuleFailure('System tags cannot be deleted.', rule: 'systemProtected'),
      );
    }
    return const Result.ok(null);
  }

  @override
  Stream<List<Tag>> watchForTransaction(String transactionId) =>
      _dao.watchForTransaction(transactionId).map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<void, Failure>> setForTransaction({
    required String transactionId,
    required List<String> tagIds,
  }) async {
    await _dao.setTransactionTags(
      transactionId: transactionId,
      tagIds: tagIds,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Stream<List<Tag>> watchForItem(String itemId) =>
      _dao.watchForItem(itemId).map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<void, Failure>> setForItem({
    required String itemId,
    required List<String> tagIds,
  }) async {
    await _dao.setItemTags(
      itemId: itemId,
      tagIds: tagIds,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Stream<List<Tag>> watchForAsset(String assetId) =>
      _dao.watchForAsset(assetId).map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<void, Failure>> setForAsset({
    required String assetId,
    required List<String> tagIds,
  }) async {
    await _dao.setAssetTags(
      assetId: assetId,
      tagIds: tagIds,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }
}
```

### `lib/data/repositories/account_repository_impl.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/account_dao.dart';
import 'package:alaya/data/daos/transaction_dao.dart';
import 'package:alaya/data/repositories/mappers/money_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/account_balance.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/repositories/account_repository.dart';
import 'package:alaya/domain/repositories/currency_repository.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';

/// `AccountRepository` backed by `AccountDao`.
final class AccountRepositoryImpl implements AccountRepository {
  /// Creates the repository over [dao], using [transactionDao] to resolve a transaction's line
  /// mapper dependency for [watchLedgerFor], [currency] for net-worth conversion, [settings] for
  /// the home currency code, and [clock] for write timestamps.
  const AccountRepositoryImpl(
    this._dao,
    this._transactionDao,
    this._currency,
    this._settings,
    this._clock,
  );

  final AccountDao _dao;
  final TransactionDao _transactionDao;
  final CurrencyRepository _currency;
  final SettingsRepository _settings;
  final Clock _clock;

  @override
  Stream<List<Account>> watchSelectable() =>
      _dao.watchSelectable().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Account>> watchAllIncludingArchived() =>
      _dao.watchAllIncludingArchived().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Account?> byId(String id) async => (await _dao.byIdIncludingDeleted(id))?.toEntity();

  @override
  Stream<List<AccountBalance>> watchBalances() {
    return _dao.watchBalances().map(
          (rows) => rows
              .map(
                (r) => AccountBalance(
                  accountId: r.accountId,
                  balance: Money(r.balanceMinor, r.currencyCode),
                ),
              )
              .toList(),
        );
  }

  @override
  Stream<AccountBalance?> watchBalanceOf(String accountId) {
    return _dao.watchBalanceOf(accountId).map(
          (row) => row == null
              ? null
              : AccountBalance(
                  accountId: row.accountId,
                  balance: Money(row.balanceMinor, row.currencyCode),
                ),
        );
  }

  @override
  Stream<({Money total, int unconvertedCount})> watchTotalInHomeCurrency() {
    return _dao.watchNetWorthEligibleBalances().asyncMap((rows) async {
      final homeCode = await _settings.readHomeCurrencyCode() ?? 'INR';
      final today = _clock.today();
      var total = Money.zero(homeCode);
      var unconverted = 0;

      for (final row in rows) {
        final converted = await _currency.convert(
          amount: Money(row.balanceMinor, row.currencyCode),
          toCurrencyCode: homeCode,
          on: today,
        );
        if (converted.isExcludedFromTotals) {
          unconverted++;
          continue;
        }
        // `converted.converted` is now in homeCode, matching `total`'s currency, so this can
        // never throw a CurrencyMismatchError regardless of how many source currencies were
        // involved.
        total = total + converted.converted!;
      }
      return (total: total, unconvertedCount: unconverted);
    });
  }

  @override
  Stream<List<Transaction>> watchLedgerFor(String accountId) {
    return _transactionDao
        .watchByAccount(accountId)
        .map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Future<Result<Account, Failure>> save(Account account) async {
    final existing = await _dao.byIdIncludingDeleted(account.id);

    if (existing == null) {
      final duplicate = await _dao.byNormalizedName(account.normalizedName);
      if (duplicate != null) {
        return Result.failure(
          ConflictFailure('An account named "${account.name}" already exists.'),
        );
      }
    }

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _dao.upsert(
      accountToCompanion(account, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );
    return Result.ok(account);
  }

  @override
  Future<Result<void, Failure>> setArchived({
    required String id,
    required bool isArchived,
  }) async {
    await _dao.setArchived(id: id, isArchived: isArchived, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    final inUseCount = await _dao.activeTransactionCount(id);
    if (inUseCount > 0) {
      return Result.failure(
        BusinessRuleFailure(
          'This account has $inUseCount transaction(s) and cannot be deleted. Archive it instead.',
          rule: 'accountInUse',
        ),
      );
    }
    await _dao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }
}
```

### `lib/data/repositories/payment_method_repository_impl.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/payment_method_dao.dart';
import 'package:alaya/data/repositories/mappers/money_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/repositories/payment_method_repository.dart';

/// `PaymentMethodRepository` backed by `PaymentMethodDao`.
final class PaymentMethodRepositoryImpl implements PaymentMethodRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const PaymentMethodRepositoryImpl(this._dao, this._clock);

  final PaymentMethodDao _dao;
  final Clock _clock;

  @override
  Stream<List<PaymentMethod>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<PaymentMethod?> byId(String id) async =>
      (await _dao.byIdIncludingDeleted(id))?.toEntity();

  @override
  Future<Result<PaymentMethod, Failure>> save(PaymentMethod method) async {
    final existing = await _dao.byIdIncludingDeleted(method.id);
    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _dao.upsert(
      paymentMethodToCompanion(method, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );
    return Result.ok(method);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    final inUseCount = await _dao.activeTransactionCount(id);
    if (inUseCount > 0) {
      return Result.failure(
        BusinessRuleFailure(
          'This payment method is used by $inUseCount transaction(s) and cannot be deleted.',
          rule: 'paymentMethodInUse',
        ),
      );
    }
    final rowsChanged = await _dao.softDeleteUserMethod(id: id, nowUtcMillis: _clock.nowUtcMillis());
    if (rowsChanged == 0) {
      return const Result.failure(
        BusinessRuleFailure('System payment methods cannot be deleted.', rule: 'systemProtected'),
      );
    }
    return const Result.ok(null);
  }
}
```

### `lib/data/repositories/payee_repository_impl.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/payee_dao.dart';
import 'package:alaya/data/repositories/mappers/money_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/repositories/payee_repository.dart';

/// `PayeeRepository` backed by `PayeeDao`.
final class PayeeRepositoryImpl implements PayeeRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const PayeeRepositoryImpl(this._dao, this._clock);

  final PayeeDao _dao;
  final Clock _clock;

  @override
  Stream<List<Payee>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Payee>> watchMatching(String term) =>
      _dao.watchMatching(term).map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Payee?> byId(String id) async => (await _dao.byIdIncludingDeleted(id))?.toEntity();

  @override
  Future<Payee?> byNormalizedName(String normalizedName) async =>
      (await _dao.byNormalizedName(normalizedName))?.toEntity();

  @override
  Future<Result<Payee, Failure>> save(Payee payee) async {
    final existing = await _dao.byIdIncludingDeleted(payee.id);

    if (existing == null) {
      final duplicate = await _dao.byNormalizedName(payee.normalizedName);
      if (duplicate != null) {
        return Result.failure(
          ConflictFailure('A payee named "${payee.name}" already exists.'),
        );
      }
    }

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _dao.upsert(
      payeeToCompanion(payee, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );
    return Result.ok(payee);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    await _dao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }
}
```

### `lib/data/repositories/transaction_repository_impl.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/account_dao.dart';
import 'package:alaya/data/daos/batch_dao.dart';
import 'package:alaya/data/daos/stock_movement_dao.dart';
import 'package:alaya/data/daos/transaction_dao.dart';
import 'package:alaya/data/daos/transaction_line_dao.dart';
import 'package:alaya/data/daos/unit_dao.dart';
import 'package:alaya/data/repositories/mappers/money_mappers.dart';
import 'package:alaya/data/repositories/settings_keys.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/repositories/currency_repository.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/repositories/transaction_repository.dart';

/// `TransactionRepository` backed by `TransactionDao` and `TransactionLineDao`.
///
/// Depends on `BatchDao` and `StockMovementDao` (Phase 2B) directly, read-only, purely to answer
/// "is this batch provably untouched" for [delete]. That is normal DAO composition, not a
/// layering violation: any repository may depend on any DAO it needs, and the inventory domain
/// not having its own repository yet (Phase 3C) does not block this one from reading its data.
///
/// Also depends on `CurrencyRepository`, for [freezeConversion] — `convert()` reads only the
/// already-cached rate table and needs no network access, so there is no reason to defer this to
/// a later phase; only `CurrencyRepository.syncDailyRates()` (the network fetch) is Phase 4A's.
final class TransactionRepositoryImpl implements TransactionRepository {
  /// Creates the repository.
  const TransactionRepositoryImpl(
    this._transactionDao,
    this._lineDao,
    this._accountDao,
    this._unitDao,
    this._batchDao,
    this._movementDao,
    this._settings,
    this._currency,
    this._clock,
  );

  final TransactionDao _transactionDao;
  final TransactionLineDao _lineDao;
  final AccountDao _accountDao;
  final UnitDao _unitDao;
  final BatchDao _batchDao;
  final StockMovementDao _movementDao;
  final SettingsRepository _settings;
  final CurrencyRepository _currency;
  final Clock _clock;

  @override
  Future<Transaction?> byId(String id) async => (await _transactionDao.byId(id))?.toEntity();

  @override
  Stream<List<Transaction>> watchByDateRange({required DateKey from, required DateKey to}) {
    return _transactionDao
        .watchByDateRange(from: from, to: to)
        .map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Stream<List<Transaction>> watchByAccount(String accountId) {
    return _transactionDao
        .watchByAccount(accountId)
        .map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Stream<List<Transaction>> watchBySubtype(
    TransactionSubtype subtype, {
    int? fromMonthKey,
    int? toMonthKey,
  }) {
    return _transactionDao
        .watchBySubtype(subtype, fromMonthKey: fromMonthKey, toMonthKey: toMonthKey)
        .map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Stream<List<Transaction>> watchNeedingReview() {
    return _transactionDao.watchNeedingReview().map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Stream<int> watchNeedsReviewCount() => _transactionDao.watchNeedsReviewCount();

  @override
  Future<List<Transaction>> search(String query, {int limit = 50}) async {
    final rows = await _transactionDao.search(query, limit: limit);
    return rows.map((r) => r.toEntity()).toList();
  }

  @override
  Stream<List<TransactionLine>> watchLines(String transactionId) async* {
    // The parent transaction's currency is needed for every line's Money fields
    // (transaction_lines has no currency column of its own, ARCH_2 §4.2), so it is read once
    // before subscribing to the lines stream rather than re-read per emission.
    final parent = await _transactionDao.byId(transactionId);
    final currencyCode = parent?.originalCurrencyCode;
    if (currencyCode == null) return;

    final categories = await _unitDao.categoriesByCode();
    yield* _lineDao.watchForTransaction(transactionId).map(
          (rows) => rows
              .map(
                (r) => r.toEntity(
                  transactionCurrencyCode: currencyCode,
                  categoryResolver: (row) =>
                      row.unitCode == null ? null : categories[row.unitCode],
                ),
              )
              .toList(),
        );
  }

  @override
  Stream<TransactionAllocation?> watchAllocation(String transactionId) {
    return _lineDao.watchAllocation(transactionId).map(
          (row) => row == null
              ? null
              : TransactionAllocation(
                  transactionId: row.txId,
                  amount: Money(row.amountMinor, row.currencyCode),
                  allocated: Money(row.allocatedMinor, row.currencyCode),
                  unallocated: Money(row.unallocatedMinor, row.currencyCode),
                  lineCount: row.lineCount,
                ),
        );
  }

  @override
  Stream<List<TransactionLine>> watchLinesForItem(String itemId) async* {
    final categories = await _unitDao.categoriesByCode();
    yield* _lineDao.watchForItem(itemId).asyncMap((rows) async {
      final result = <TransactionLine>[];
      for (final row in rows) {
        final parent = await _transactionDao.byId(row.transactionId);
        if (parent == null) continue;
        result.add(
          row.toEntity(
            transactionCurrencyCode: parent.originalCurrencyCode,
            categoryResolver: (r) => r.unitCode == null ? null : categories[r.unitCode],
          ),
        );
      }
      return result;
    });
  }

  @override
  Future<Result<Transaction, Failure>> create({
    required Transaction transaction,
    List<TransactionLine> lines = const [],
    List<String> tagIds = const [],
  }) async {
    final resolved = await _fillQuickAddAccount(transaction);
    if (resolved.isFailure) return Result.failure(resolved.failureOrNull!);
    final withAccount = resolved.valueOrNull!;

    final shapeCheck = _validateShape(withAccount);
    if (shapeCheck != null) return Result.failure(shapeCheck);

    final monthKey = withAccount.dateKey.monthKey;
    final now = _clock.nowUtcMillis();

    await _transactionDao.insertWithDetails(
      header: transactionToCompanion(
        withAccount,
        monthKey: monthKey,
        createdAt: now,
        updatedAt: now,
      ),
      lines: lines
          .map((line) => transactionLineToCompanion(line, createdAt: now, updatedAt: now))
          .toList(),
      tagIds: tagIds,
      nowUtcMillis: now,
    );

    final lastUsed = withAccount.toAccountId ?? withAccount.fromAccountId;
    if (lastUsed != null) {
      await _settings.writeValue(
        key: SettingsKeys.lastUsedAccountId,
        value: lastUsed,
        valueType: 'string',
      );
    }

    return Result.ok(withAccount);
  }

  @override
  Future<Result<Transaction, Failure>> update(Transaction transaction) async {
    final shapeCheck = _validateShape(transaction);
    if (shapeCheck != null) return Result.failure(shapeCheck);

    final existing = await _transactionDao.byId(transaction.id);
    if (existing == null) {
      return Result.failure(NotFoundFailure('Transaction not found.', id: transaction.id));
    }

    final monthKey = transaction.dateKey.monthKey;
    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing.createdAt,
      clock: _clock,
    );
    await _transactionDao.updateTransaction(
      transactionToCompanion(
        transaction,
        monthKey: monthKey,
        createdAt: stamps.createdAt,
        updatedAt: stamps.updatedAt,
      ),
    );
    return Result.ok(transaction);
  }

  @override
  Future<Result<void, Failure>> recordCreatedArtefact({
    required String lineId,
    String? createdBatchId,
    String? createdAssetId,
    String? createdRecurringTemplateId,
  }) async {
    await _lineDao.setCreatedArtefact(
      lineId: lineId,
      nowUtcMillis: _clock.nowUtcMillis(),
      createdBatchId: createdBatchId,
      createdAssetId: createdAssetId,
      createdRecurringTemplateId: createdRecurringTemplateId,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> replaceLines({
    required String transactionId,
    required List<TransactionLine> lines,
  }) async {
    final now = _clock.nowUtcMillis();
    await _lineDao.replaceLines(
      transactionId: transactionId,
      lines: lines
          .map((line) => transactionLineToCompanion(line, createdAt: now, updatedAt: now))
          .toList(),
      nowUtcMillis: now,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> markReviewed(String id) async {
    await _transactionDao.markReviewed(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> freezeConversion({
    required String id,
    required DateKey on,
    required String toCurrencyCode,
  }) async {
    final existing = await _transactionDao.byId(id);
    if (existing == null) {
      return Result.failure(NotFoundFailure('Transaction not found.', id: id));
    }

    final original = Money(existing.originalAmountMinor, existing.originalCurrencyCode);
    final converted = await _currency.convert(
      amount: original,
      toCurrencyCode: toCurrencyCode,
      on: on,
    );

    if (converted.isExcludedFromTotals) {
      return const Result.failure(
        BusinessRuleFailure(
          'No exchange rate is cached for this currency pair, so a conversion cannot be '
          'frozen yet. Try again once rates have synced.',
          rule: 'noRateAvailable',
        ),
      );
    }

    // `ConvertedMoney` carries no separate "raw API string" — and a cross-rate genuinely has
    // none: it is computed from two USD-pivoted quotes (ARCH_3 §1.2), never itself a literal API
    // response. The computed rate's own exact decimal string is the reproducible substitute
    // ARCH_3 §1.3 actually needs ("so any number a user questions can be reproduced") — `rate` on
    // a `ConvertedMoney` with `isExcludedFromTotals == false` is always non-null.
    await _transactionDao.freezeConversion(
      id: id,
      convertedAmountMinor: converted.converted!.minor,
      convertedCurrencyCode: converted.converted!.currencyCode,
      conversionRate: converted.rate!,
      conversionRateRaw: converted.rate!.toString(),
      conversionDateKey: converted.rateDateKey!,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<DetachedArtefacts, Failure>> delete({
    required String id,
    String? reason,
  }) async {
    final lines = await _lineDao.forTransaction(id);
    final now = _clock.nowUtcMillis();

    await _transactionDao.softDelete(id: id, reason: reason, nowUtcMillis: now);

    final batchIds = <String>[];
    final assetIds = <String>[];
    final recurringTemplateIds = <String>[];
    final untouchedBatchIds = <String>[];

    for (final line in lines) {
      final batchId = line.createdBatchId;
      final assetId = line.createdAssetId;
      final recurringId = line.createdRecurringTemplateId;
      if (batchId == null && assetId == null && recurringId == null) continue;

      await _lineDao.clearCreatedArtefacts(lineId: line.id, nowUtcMillis: now);

      if (batchId != null) {
        batchIds.add(batchId);
        await _batchDao.detachFromDeletedTransaction(batchId: batchId, nowUtcMillis: now);
        if (await _isBatchUntouched(batchId)) untouchedBatchIds.add(batchId);
      }
      if (assetId != null) assetIds.add(assetId);
      if (recurringId != null) recurringTemplateIds.add(recurringId);
    }

    return Result.ok(
      DetachedArtefacts(
        batchIds: batchIds,
        assetIds: assetIds,
        recurringTemplateIds: recurringTemplateIds,
        untouchedBatchIds: untouchedBatchIds,
      ),
    );
  }

  /// A batch is provably untouched when nothing has been drawn from it — its remaining quantity
  /// still equals what it started with, and no movement beyond the founding one exists. Only
  /// these may be offered for removal after a delete; a batch already consumed from must never
  /// be, because the food really was eaten (anomaly A10).
  Future<bool> _isBatchUntouched(String batchId) async {
    final batch = await _batchDao.byIdIncludingDeleted(batchId);
    if (batch == null) return false;
    if (batch.remainingQuantityMilli != batch.initialQuantityMilli) return false;

    final movements = await _movementDao.forBatch(batchId);
    return movements.every(
      (m) => StockMovementDao.incomingKinds.contains(m.kind),
    );
  }

  /// Fills [transaction]'s missing account with last-used, then the default, then the first
  /// selectable account — never leaving it null (ARCH_2 §4.1). Only applies to
  /// [TransactionKind.deposit], `.withdrawal`, `.adjustmentIncrease` and `.adjustmentDecrease`,
  /// which need exactly one account; a transfer needs two different ones with no sensible
  /// default for either, so a transfer missing an account is a validation failure, not something
  /// to auto-fill.
  Future<Result<Transaction, Failure>> _fillQuickAddAccount(Transaction transaction) async {
    final needsTo = transaction.kind == TransactionKind.deposit ||
        transaction.kind == TransactionKind.adjustmentIncrease;
    final needsFrom = transaction.kind == TransactionKind.withdrawal ||
        transaction.kind == TransactionKind.adjustmentDecrease;

    if (!needsTo && !needsFrom) return Result.ok(transaction);
    if (needsTo && transaction.toAccountId != null) return Result.ok(transaction);
    if (needsFrom && transaction.fromAccountId != null) return Result.ok(transaction);

    final resolvedId = await _resolveQuickAddAccountId();
    if (resolvedId == null) {
      return const Result.failure(
        BusinessRuleFailure(
          'No account is available to record this against. Create an account first.',
          rule: 'noAccountAvailable',
        ),
      );
    }

    return Result.ok(
      needsTo
          ? transaction.copyWith(toAccountId: resolvedId)
          : transaction.copyWith(fromAccountId: resolvedId),
    );
  }

  /// Resolves quick-add's account: last-used, then the seeded default, then the first
  /// selectable account by sort order — each candidate checked for existence, since an account
  /// referenced by a stale setting could since have been deleted.
  Future<String?> _resolveQuickAddAccountId() async {
    final lastUsedId = await _settings.readValue(SettingsKeys.lastUsedAccountId);
    if (lastUsedId != null && await _accountExists(lastUsedId)) return lastUsedId;

    final defaultId = await _settings.readDefaultAccountId();
    if (defaultId != null && await _accountExists(defaultId)) return defaultId;

    final selectable = await _accountDao.watchSelectable().first;
    return selectable.isEmpty ? null : selectable.first.id;
  }

  Future<bool> _accountExists(String id) async {
    final account = await _accountDao.byIdIncludingDeleted(id);
    return account != null && account.deletedAt == null;
  }

  /// Validates the shape ARCH_2 §4.1's CHECK constraints require, in Dart, so a caller sees a
  /// clear [ValidationFailure] rather than a raw SQLite constraint error.
  Failure? _validateShape(Transaction transaction) {
    if (transaction.originalAmount.minor <= 0) {
      return const ValidationFailure(
        'The amount must be greater than zero.',
        field: 'originalAmount',
      );
    }

    final from = transaction.fromAccountId;
    final to = transaction.toAccountId;

    switch (transaction.kind) {
      case TransactionKind.deposit:
      case TransactionKind.adjustmentIncrease:
        if (to == null || from != null) {
          return const ValidationFailure(
            'A deposit needs a destination account and no source account.',
            field: 'toAccountId',
          );
        }
      case TransactionKind.withdrawal:
      case TransactionKind.adjustmentDecrease:
        if (from == null || to != null) {
          return const ValidationFailure(
            'A withdrawal needs a source account and no destination account.',
            field: 'fromAccountId',
          );
        }
      case TransactionKind.transfer:
        if (from == null || to == null) {
          return const ValidationFailure(
            'A transfer needs both a source and a destination account.',
            field: 'toAccountId',
          );
        }
        if (from == to) {
          return const ValidationFailure(
            'A transfer must be between two different accounts.',
            field: 'toAccountId',
          );
        }
    }
    return null;
  }
}
```
