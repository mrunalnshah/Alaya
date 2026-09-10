# Phase 3D — Recurring & Service Repository Implementations

> **Regenerated 2026-08-02 from the canonical tree.** Every fix through the Phase 6C debugging
> pass is folded in; this document and the working tree are in sync, and regenerating from it
> reproduces the code that runs. Earlier revisions reintroduce defects listed in ARCH_6 §3.
>
> Files shared with other phase documents — `app_en.arb`, `routes.dart`, `app_router.dart`,
> `layout_overflow_test.dart`, and the Phase 6A editor files amended by 6B and 6C — carry
> **identical** content in every copy, so they may be applied in any order.

**3 repositories · 34 contract methods · 1 mapper file · 1 shared helper extracted.**

## Add dependencies

None. Every import resolves to packages already present.

## A structural decision worth stating: `watchDue()` does not read `v_recurring_due`

The view is a presentation-shaped projection of 18 columns. A full `RecurringTemplate` needs **nine
more** — `normalizedName`, `startDateKey`, `isPaused`, the three anchors, `endDateKey`,
`linkedAssetId`, `note` — and a full `RecurringOccurrence` **four more**: `paidTransactionId`,
`paidAmount`, `paidDateKey`, `note`. Verified by diffing the view's `SELECT` list against both
entities' fields.

Widening it to carry all thirteen (with `note` needing an alias on both sides) would leave it a bare
`templates JOIN occurrences` whose only remaining value is a filter two typed queries already
express. So `watchDue()` reads templates and outstanding occurrences as **two queries** and pairs
them in Dart — no per-template round trip. `RecurringTemplateDao.watchDue()` still reads the view and
remains the right call for a caller that only needs the projection, such as a dashboard count.

This is the third time a presentation-shaped view could not serve an aggregate-shaped contract
(`v_active_transactions` in 3B, `v_batch_stock_check` in 3C). In 3B I widened the view; in 3C I tried
and reverted. The pattern is now clear enough to name: **views built for a list screen are the wrong
source for a domain aggregate**, and reaching for base-table queries is the answer rather than
widening the view each time.

## Verified behaviourally, not just structurally

**Interval advancement — the anomaly A13 case.** A bill anchored on the 31st, walked through a full
year: `20260131 → 20260228 → 20260331 → 20260430 → … → 20270131`. It clamps in February and
**returns to the 31st in March**. That works only because the advance clamps the *stored anchor* into
the target month, never the current day — advancing from the clamped 28th would walk the bill
permanently backwards after one February. Also verified: leap February (`20240131 → 20240229`), year
rollover, yearly-on-Feb-29 clamping to the 28th and returning to the 29th four years later, and
quarterly intervals from the 31st.

**Materialisation.** An app unopened for three months produces **3 due occurrences and zero
transactions** — money is only ever created by an explicit tap (anomaly A14). Running it again
creates nothing and leaves `nextDueDateKey` in the same place, so it is idempotent. `endDateKey`
stops it. A daily template left 574 days behind hits the 240-occurrence bound instead of spinning,
so one misconfigured template cannot hang the launch path.

**The five business rules.** `outflow → withdrawal` (account on `from`), `inflow → deposit` (account
on `to`) — each satisfying ARCH_2 §4.1's shape CHECK. Paying ₹520 against a ₹499 template records
₹520 on the occurrence and leaves the template's ₹499 untouched (anomaly A29). Deleting a template
is soft and cascades to nothing, so paid occurrences and their transactions survive. Assets have no
delete path at all. A service record with a cost optionally creates a linked withdrawal.

## Verification performed

| Check | Result |
|---|---|
| **Contract coverage** — every method implemented, no extras | **34/34 exact across 3 interfaces** |
| Mapper field reads vs real table definitions | 70 reads, **0 unknown** |
| Mapper companion writes vs real tables | 68 writes, **0 unknown** |
| Missing imports — exhaustive, 125 files vs 204 types | 0 |
| Unused imports | 0 |
| DAO call-site vs brace-matched signature | 0 mismatches |
| Brace balance, 25 repository files | 0 |
| `const` with runtime interpolation | 0 |
| `DateTime.now()` outside `Clock` | 0 |
| Raw `DateKey` into a drift range helper | 0 |
| Fabricated `attachedDatabase.xxxDao` getters | 0 |
| `Qty` debug `toString` in user-facing text | 0 |
| **Impl-to-impl imports** | 0 (2 found and fixed — see below) |

One check caught its own follow-on: extracting `ItemCategoryResolver` left `UnitCategory` and
`ItemDao` unused in `batch_repository_impl.dart`. The unused-import scanner added in Phase 3C found
both immediately.

## Findings

**`ItemCategoryResolver` extracted to its own file — a Phase 3C cleanup.** Three repositories use it,
but it lived inside `batch_repository_impl.dart`, so `stock_repository_impl` and
`shopping_repository_impl` each imported another repository's *implementation* file to reach a shared
helper. Exactly the coupling `settings_keys.dart` was extracted to avoid in Phase 3B. Nothing here
touches Law L12 — all three are `data/` — so it was a design smell rather than a violation, but the
fix is cheap and the precedent was already set.

**`ServiceRecordRepository.save` returns both IDs without a contract change.** The rule asks for
both; the contract returns `Result<ServiceRecord, Failure>`, and `ServiceRecord` already carries
`linkedTransactionId`. So the saved record conveys its own id and the transaction's.

**That save cannot be one database transaction, and the ordering is forced.**
`service_records.linked_transaction_id` is a foreign key into `transactions`, so the transaction must
exist before the record can point at it — and neither repository exposes transaction control spanning
aggregates. A failure on the second write would therefore leave a withdrawal standing alone, silently
inflating expenses with nothing in the service history to explain it. So the record write is wrapped
and **compensated**: if it throws, the transaction is deleted with a stated reason and the caller gets
an `UnexpectedFailure`. Worth flagging as the one place in this phase where atomicity is achieved by
compensation rather than by the database.

**Both repositories depend on `TransactionRepository` — the domain interface, not the
implementation.** `payOccurrence` and the optional service expense reuse its shape validation,
`monthKey` derivation and account resolution rather than reimplementing any of it.

**Occurrences and disposals borrow their currency, and both are guarded.**
`recurring_occurrences` has no currency column (ARCH_2 §7), so a payment in a currency other than the
template's is rejected rather than stored against the wrong code. Likewise `assets` has no disposal
currency (ARCH_2 §8), so disposing with proceeds against an asset that has no `purchaseCurrencyCode`
is refused instead of storing a bare number. Both are Law L1's pairing rule.

**A monthly or yearly template must have a day-of-month anchor.** Without one the advance would use
whatever day it landed on, so a single February settlement would pull every later occurrence back to
the 28th permanently. Requiring the anchor at save time is what makes anomaly A13 unreachable rather
than merely handled.

**`_maxOccurrencesPerPass = 240`.** Twenty years of monthly or eight months of daily is past any
honest backlog; beyond it the template is misconfigured and the app should stay responsive rather
than faithfully materialise nonsense on the startup path.

**Subtype for a service expense is `otherOut`, not `electronics`.** The subtype describes the *flow*,
and servicing a television is not the purchase of one. The semantic detail lives on the tag — Phase
1C seeds a `Maintenance` tag scoped to withdrawal and service for exactly this.



---

### `lib/data/repositories/item_category_resolver.dart`

```dart
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/data/daos/item_dao.dart';

/// Resolves an item's [UnitCategory], which every batch, movement and shopping quantity needs but
/// no batch, movement or entry row carries.
///
/// Lives in its own file because three repositories use it — `BatchRepositoryImpl`,
/// `StockRepositoryImpl` and `ShoppingRepositoryImpl`. Leaving it inside
/// `batch_repository_impl.dart` forced the other two to import another repository's
/// *implementation* file just to reach a shared helper: the same coupling `settings_keys.dart`
/// was extracted to avoid in Phase 3B. Nothing here touches Law L12 — all three are `data/` — so
/// it is a design smell rather than a violation, but the fix is cheap and the precedent is set.
final class ItemCategoryResolver {
  /// Creates a resolver over [itemDao].
  ItemCategoryResolver(this._itemDao);

  final ItemDao _itemDao;
  final Map<String, UnitCategory> _cache = {};

  /// The category for [itemId], or null when no such item exists.
  ///
  /// Cached per instance. An item's category is immutable once created (Law L8), so a cached value
  /// can never go stale — which is precisely what makes caching safe here rather than a risk.
  Future<UnitCategory?> categoryOf(String itemId) async {
    final cached = _cache[itemId];
    if (cached != null) return cached;

    final row = await _itemDao.byIdIncludingDeleted(itemId);
    if (row == null) return null;
    _cache[itemId] = row.unitCategory;
    return row.unitCategory;
  }

  /// Resolves categories for [itemIds] in one pass, for mapping a list of rows.
  Future<Map<String, UnitCategory>> categoriesFor(Iterable<String> itemIds) async {
    final result = <String, UnitCategory>{};
    for (final id in itemIds.toSet()) {
      final category = await categoryOf(id);
      if (category != null) result[id] = category;
    }
    return result;
  }
}
```

### `lib/data/repositories/mappers/schedule_mappers.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:drift/drift.dart' show Value;

import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/converters/money_converter.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/service_record.dart';

/// Converts between `RecurringTemplateRow` and the domain `RecurringTemplate` entity.
extension RecurringTemplateMapper on RecurringTemplateRow {
  /// Maps this row to a domain entity.
  RecurringTemplate toEntity() => RecurringTemplate(
        id: id,
        name: name,
        normalizedName: normalizedName,
        kind: kind,
        direction: direction,
        defaultAmount: MoneyColumns.read(defaultAmountMinor, currencyCode),
        intervalUnit: intervalUnit,
        intervalCount: intervalCount,
        startDateKey: startDateKey,
        nextDueDateKey: nextDueDateKey,
        isPaused: isPaused,
        autoRemind: autoRemind,
        remindDaysBefore: remindDaysBefore,
        payeeId: payeeId,
        defaultAccountId: defaultAccountId,
        defaultPaymentMethodId: defaultPaymentMethodId,
        tagId: tagId,
        anchorDayOfMonth: anchorDayOfMonth,
        anchorMonth: anchorMonth,
        anchorWeekday: anchorWeekday,
        endDateKey: endDateKey,
        linkedAssetId: linkedAssetId,
        note: note,
      );
}

/// Builds the companion for [template].
RecurringTemplatesCompanion recurringTemplateToCompanion(
  RecurringTemplate template, {
  required int createdAt,
  required int updatedAt,
}) {
  return RecurringTemplatesCompanion.insert(
    id: template.id,
    name: template.name,
    normalizedName: template.normalizedName,
    kind: template.kind,
    direction: template.direction,
    defaultAmountMinor: MoneyColumns.minorOf(template.defaultAmount),
    currencyCode: MoneyColumns.codeOf(template.defaultAmount),
    payeeId: Value(template.payeeId),
    defaultAccountId: Value(template.defaultAccountId),
    defaultPaymentMethodId: Value(template.defaultPaymentMethodId),
    tagId: Value(template.tagId),
    intervalUnit: template.intervalUnit,
    intervalCount: template.intervalCount,
    anchorDayOfMonth: Value(template.anchorDayOfMonth),
    anchorMonth: Value(template.anchorMonth),
    anchorWeekday: Value(template.anchorWeekday),
    startDateKey: template.startDateKey,
    endDateKey: Value(template.endDateKey),
    nextDueDateKey: template.nextDueDateKey,
    isPaused: template.isPaused,
    autoRemind: template.autoRemind,
    remindDaysBefore: template.remindDaysBefore,
    linkedAssetId: Value(template.linkedAssetId),
    note: Value(template.note),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `RecurringOccurrenceRow` and the domain `RecurringOccurrence` entity.
///
/// [currencyCode] comes from the owning template: `recurring_occurrences` stores
/// `paid_amount_minor` with no currency column of its own (ARCH_2 §7), because an occurrence is
/// always denominated in its template's currency. Passing it in rather than assuming one keeps
/// Law L1's pairing rule honest.
extension RecurringOccurrenceMapper on RecurringOccurrenceRow {
  /// Maps this row to a domain entity.
  RecurringOccurrence toEntity(String currencyCode) => RecurringOccurrence(
        id: id,
        templateId: templateId,
        dueDateKey: dueDateKey,
        status: status,
        paidTransactionId: paidTransactionId,
      // `readNullable` enforces a pairing invariant — both null or both present — and throws on a
      // half-populated pair. It is right only where the currency is a nullable column written and
      // cleared with its own amount. Here the currency is always present, so a null amount is a
      // legitimate absence rather than a broken pair, and the nullability belongs to the amount.
      //
      // `recurring_occurrences.currency_code` is NOT NULL, so an occurrence that has not been paid
      // yet is exactly the half-populated pair this would reject.
        paidAmount:
            paidAmountMinor == null ? null : Money(paidAmountMinor!, currencyCode),
        paidDateKey: paidDateKey,
        note: note,
      );
}

/// Converts between `AssetRow` and the domain `Asset` entity.
///
/// `disposalAmountMinor` is read against `purchaseCurrencyCode`, because `assets` carries no
/// separate disposal currency (ARCH_2 §8) — sale proceeds are denominated in whatever the asset
/// was bought in. Pairing it with any other code would silently misstate the figure.
extension AssetMapper on AssetRow {
  /// Maps this row to a domain entity.
  Asset toEntity() => Asset(
        id: id,
        name: name,
        normalizedName: normalizedName,
        type: type,
        status: status,
        brand: brand,
        modelNo: modelNo,
        serialNo: serialNo,
        purchaseDateKey: purchaseDateKey,
        // Same shared currency as `disposalAmount` below, so the exposure runs both ways: an asset
        // disposed of without a recorded purchase price has the currency set and this amount null.
        purchasePrice: purchasePriceMinor == null || purchaseCurrencyCode == null
            ? null
            : Money(purchasePriceMinor!, purchaseCurrencyCode!),
        sourceTransactionLineId: sourceTransactionLineId,
        warrantyStartDateKey: warrantyStartDateKey,
        warrantyEndDateKey: warrantyEndDateKey,
        warrantyProvider: warrantyProvider,
        warrantyNote: warrantyNote,
        serviceIntervalDays: serviceIntervalDays,
        nextServiceDueDateKey: nextServiceDueDateKey,
        primaryContactName: primaryContactName,
        primaryContactPhone: primaryContactPhone,
        location: location,
        linkedRecurringTemplateId: linkedRecurringTemplateId,
        disposedAtDateKey: disposedAtDateKey,
        disposalReason: disposalReason,
        disposalNote: disposalNote,
        // `purchase_currency_code` is nullable, but it is shared with `purchasePrice` above — so an
        // asset bought for a known price and not yet disposed of has the currency set and this
        // amount null. One currency serving two amounts cannot carry a pairing invariant for either.
        disposalAmount: disposalAmountMinor == null || purchaseCurrencyCode == null
            ? null
            : Money(disposalAmountMinor!, purchaseCurrencyCode!),
        notes: notes,
      );
}

/// Builds the companion for [asset].
AssetsCompanion assetToCompanion(
  Asset asset, {
  required int createdAt,
  required int updatedAt,
}) {
  return AssetsCompanion.insert(
    id: asset.id,
    name: asset.name,
    normalizedName: asset.normalizedName,
    type: asset.type,
    brand: Value(asset.brand),
    modelNo: Value(asset.modelNo),
    serialNo: Value(asset.serialNo),
    purchaseDateKey: Value(asset.purchaseDateKey),
    purchasePriceMinor: Value(MoneyColumns.minorOfNullable(asset.purchasePrice)),
    purchaseCurrencyCode: Value(MoneyColumns.codeOfNullable(asset.purchasePrice)),
    sourceTransactionLineId: Value(asset.sourceTransactionLineId),
    warrantyStartDateKey: Value(asset.warrantyStartDateKey),
    warrantyEndDateKey: Value(asset.warrantyEndDateKey),
    warrantyProvider: Value(asset.warrantyProvider),
    warrantyNote: Value(asset.warrantyNote),
    serviceIntervalDays: Value(asset.serviceIntervalDays),
    nextServiceDueDateKey: Value(asset.nextServiceDueDateKey),
    primaryContactName: Value(asset.primaryContactName),
    primaryContactPhone: Value(asset.primaryContactPhone),
    location: Value(asset.location),
    linkedRecurringTemplateId: Value(asset.linkedRecurringTemplateId),
    status: asset.status,
    disposedAtDateKey: Value(asset.disposedAtDateKey),
    disposalReason: Value(asset.disposalReason),
    disposalNote: Value(asset.disposalNote),
    disposalAmountMinor: Value(MoneyColumns.minorOfNullable(asset.disposalAmount)),
    notes: Value(asset.notes),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `ServiceRecordRow` and the domain `ServiceRecord` entity.
extension ServiceRecordMapper on ServiceRecordRow {
  /// Maps this row to a domain entity.
  ServiceRecord toEntity() => ServiceRecord(
        id: id,
        assetId: assetId,
        serviceDateKey: serviceDateKey,
        type: type,
        providerName: providerName,
        providerPhone: providerPhone,
        cost: MoneyColumns.readNullable(costMinor, currencyCode),
        linkedTransactionId: linkedTransactionId,
        nextDueDateKey: nextDueDateKey,
        notes: notes,
      );
}

/// Builds the companion for [record].
ServiceRecordsCompanion serviceRecordToCompanion(
  ServiceRecord record, {
  required int createdAt,
  required int updatedAt,
}) {
  return ServiceRecordsCompanion.insert(
    id: record.id,
    assetId: record.assetId,
    serviceDateKey: record.serviceDateKey,
    type: record.type,
    providerName: Value(record.providerName),
    providerPhone: Value(record.providerPhone),
    costMinor: Value(MoneyColumns.minorOfNullable(record.cost)),
    currencyCode: Value(MoneyColumns.codeOfNullable(record.cost)),
    linkedTransactionId: Value(record.linkedTransactionId),
    nextDueDateKey: Value(record.nextDueDateKey),
    notes: Value(record.notes),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
```

### `lib/data/repositories/recurring_repository_impl.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/recurring_occurrence_dao.dart';
import 'package:alaya/data/daos/recurring_template_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/mappers/schedule_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/repositories/recurring_repository.dart';
import 'package:alaya/domain/repositories/transaction_repository.dart';
import 'package:alaya/domain/services/recurring_engine.dart';

/// `RecurringRepository` backed by `RecurringTemplateDao` and `RecurringOccurrenceDao`.
///
/// Depends on `TransactionRepository` — the domain interface — so [payOccurrence] reuses its shape
/// validation and `monthKey` derivation rather than reimplementing them.
final class RecurringRepositoryImpl implements RecurringRepository {
  /// Creates the repository.
  const RecurringRepositoryImpl(
    this._templateDao,
    this._occurrenceDao,
    this._transactions,
    this._uids,
    this._clock,
  );

  final RecurringTemplateDao _templateDao;
  final RecurringOccurrenceDao _occurrenceDao;
  final TransactionRepository _transactions;
  final UidGenerator _uids;
  final Clock _clock;

  /// Owns the interval arithmetic, the month-end clamp and the materialisation bound.
  static const RecurringEngine _engine = RecurringEngine();

  // ── templates ─────────────────────────────────────────────────────────────────────────

  @override
  Stream<List<RecurringTemplate>> watchAllTemplates() =>
      _templateDao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<RecurringTemplate>> watchTemplatesByDirection(RecurringDirection direction) =>
      _templateDao
          .watchByDirection(direction)
          .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<RecurringTemplate>> watchTemplatesForAsset(String assetId) =>
      _templateDao.watchForAsset(assetId).map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<RecurringTemplate?> templateById(String id) async =>
      (await _templateDao.byIdIncludingDeleted(id))?.toEntity();

  /// Emits the due list: unpaused templates paired with their outstanding occurrence.
  ///
  /// Built from two typed queries rather than from `v_recurring_due`, deliberately. That view is a
  /// presentation-shaped projection of 18 columns; a full `RecurringTemplate` needs nine more
  /// (`normalizedName`, `startDateKey`, `isPaused`, the three anchors, `endDateKey`,
  /// `linkedAssetId`, `note`) and a full `RecurringOccurrence` four more (`paidTransactionId`,
  /// `paidAmount`, `paidDateKey`, `note`). Widening the view to carry all thirteen — with `note`
  /// needing an alias on both sides — would leave it a bare join whose only remaining value is a
  /// filter these two queries already express. Two queries, no per-template round trip.
  ///
  /// `RecurringTemplateDao.watchDue()` still reads the view and is the right call for a caller
  /// that only needs the projection, such as a dashboard count.
  @override
  Stream<List<RecurringDue>> watchDue() {
    return _templateDao.watchAll().asyncMap((templateRows) async {
      final today = _clock.today();
      // Materialisation never runs ahead of today, so every `due` occurrence has a due date on or
      // before it — this is the whole outstanding set, in one query rather than one per template.
      final outstanding = await _occurrenceDao.outstandingAsOf(today);
      final byTemplate = <String, RecurringOccurrenceRow>{};
      for (final row in outstanding) {
        final existing = byTemplate[row.templateId];
        // Oldest outstanding occurrence wins: that is the one the user owes next.
        if (existing == null || row.dueDateKey < existing.dueDateKey) {
          byTemplate[row.templateId] = row;
        }
      }

      final due = <RecurringDue>[];
      for (final templateRow in templateRows) {
        if (templateRow.isPaused) continue;
        final template = templateRow.toEntity();
        if (template.hasEnded(today)) continue;
        final occurrenceRow = byTemplate[templateRow.id];
        due.add(
          RecurringDue(
            template: template,
            occurrence: occurrenceRow?.toEntity(templateRow.currencyCode),
          ),
        );
      }
      due.sort((a, b) => DateKey.compare(a.template.nextDueDateKey, b.template.nextDueDateKey));
      return due;
    });
  }

  @override
  Future<Result<RecurringTemplate, Failure>> saveTemplate(RecurringTemplate template) async {
    final validation = _validateTemplate(template);
    if (validation != null) return Result.failure(validation);

    final existing = await _templateDao.byIdIncludingDeleted(template.id);
    if (existing == null) {
      final duplicate = await _templateDao.byNormalizedName(template.normalizedName);
      if (duplicate != null) {
        return Result.failure(
          ConflictFailure('A recurring template named "${template.name}" already exists.'),
        );
      }
    }

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _templateDao.upsert(
      recurringTemplateToCompanion(
        template,
        createdAt: stamps.createdAt,
        updatedAt: stamps.updatedAt,
      ),
    );
    return Result.ok(template);
  }

  @override
  Future<Result<void, Failure>> setTemplatePaused({
    required String id,
    required bool isPaused,
  }) async {
    final existing = await _templateDao.byIdIncludingDeleted(id);
    if (existing == null || existing.deletedAt != null) {
      return Result.failure(NotFoundFailure('Recurring template not found.', id: id));
    }
    await _templateDao.setPaused(
      id: id,
      isPaused: isPaused,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> deleteTemplate(String id) async {
    // Soft, and it cascades to nothing. Paid occurrences and the transactions they created survive
    // untouched (ARCH_3 §4.1): deleting a subscription does not un-pay last month's bill, and the
    // money that left the account really left it.
    await _templateDao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  // ── occurrences ───────────────────────────────────────────────────────────────────────

  @override
  Stream<List<RecurringOccurrence>> watchOccurrences(String templateId) {
    return _occurrenceDao.watchForTemplate(templateId).asyncMap((rows) async {
      final template = await _templateDao.byIdIncludingDeleted(templateId);
      if (template == null) return const <RecurringOccurrence>[];
      return rows.map((r) => r.toEntity(template.currencyCode)).toList();
    });
  }

  @override
  Stream<List<RecurringOccurrence>> watchOccurrencesInRange({
    required DateKey from,
    required DateKey to,
  }) {
    return _occurrenceDao.watchDueInRange(from: from, to: to).asyncMap(_mapWithTemplateCurrency);
  }

  @override
  Future<Result<int, Failure>> materialiseUpTo(DateKey asOf) async {
    final templates = await _templateDao.needingMaterialisation(asOf);
    final now = _clock.nowUtcMillis();
    var created = 0;

    for (final row in templates) {
      final template = row.toEntity();
      var cursor = template.nextDueDateKey;
      var guard = 0;

      while (!cursor.isAfter(asOf) && guard < RecurringEngine.maxOccurrencesPerPass) {
        guard++;
        final end = template.endDateKey;
        if (end != null && cursor.isAfter(end)) break;

        // Idempotent: the DAO reads before inserting, because `idx_recurring_occ` is a partial
        // unique index and SQLite rejects a partial index as an ON CONFLICT target. Running this
        // twice creates nothing the second time.
        await _occurrenceDao.upsertForDue(
          id: _uids.generate(),
          templateId: template.id,
          dueDateKey: cursor,
          nowUtcMillis: now,
        );
        created++;
        cursor = _advance(cursor, template);
      }

      if (cursor != template.nextDueDateKey) {
        await _templateDao.advanceNextDue(
          id: template.id,
          nextDueDateKey: cursor,
          nowUtcMillis: now,
        );
      }
    }
    // Every occurrence created here is `due`. Nothing is paid, and no transaction exists — money is
    // only ever created by an explicit user tap (anomaly A14). An app unopened for three months
    // produces three due rows and zero transactions.
    return Result.ok(created);
  }

  @override
  Future<Result<Transaction, Failure>> payOccurrence({
    required String occurrenceId,
    required Money amount,
    required DateKey paidOn,
    required String accountId,
    String? paymentMethodId,
  }) async {
    if (!amount.isPositive) {
      return const Result.failure(
        ValidationFailure('The amount paid must be greater than zero.', field: 'amount'),
      );
    }

    final occurrence = await _occurrenceDao.byId(occurrenceId);
    if (occurrence == null) {
      return Result.failure(NotFoundFailure('Occurrence not found.', id: occurrenceId));
    }
    if (occurrence.status != RecurringOccurrenceStatus.due) {
      return Result.failure(
        BusinessRuleFailure(
          'This occurrence is already ${occurrence.status.name}.',
          rule: 'occurrenceNotDue',
        ),
      );
    }

    final templateRow = await _templateDao.byIdIncludingDeleted(occurrence.templateId);
    if (templateRow == null) {
      return Result.failure(
        NotFoundFailure('The template this occurrence belongs to does not exist.',
            id: occurrence.templateId),
      );
    }
    if (amount.currencyCode != templateRow.currencyCode) {
      // `recurring_occurrences` has no currency column: a paid amount is denominated in its
      // template's currency (ARCH_2 §7). Accepting a different one would store the number against
      // the wrong code on read — Law L1's pairing rule, broken silently.
      return Result.failure(
        ValidationFailure(
          'This template is in ${templateRow.currencyCode}, so the payment cannot be in '
          '${amount.currencyCode}.',
          field: 'amount',
        ),
      );
    }

    // `direction` decides the kind: an outflow settles by taking money out, an inflow by putting it
    // in. This is what lets salary share the recurring system with bills instead of needing a
    // second, parallel one (anomaly A27).
    final isOutflow = templateRow.direction == RecurringDirection.outflow;
    final created = await _transactions.create(
      transaction: Transaction(
        id: _uids.generate(),
        kind: isOutflow ? TransactionKind.withdrawal : TransactionKind.deposit,
        subtype: isOutflow ? TransactionSubtype.bill : TransactionSubtype.salaryIn,
        // **Now when the date is today, midnight only when it is not.**
        //
        // The ledger orders by `dateKey DESC, occurredAt DESC`. Stamping midnight unconditionally sent
        // every same-day entry to the *bottom* of today's group, behind hand-entered expenses stamped
        // with the real clock — so two records made seconds apart appeared in an order with no
        // relationship to anything the user did.
        //
        // Midnight stays right for a back-dated payment: nobody knows what time last Tuesday's plumber
        // came, and inventing one would be a worse lie than admitting the day is all we have.
        occurredAtUtc:
            paidOn == _clock.today() ? _clock.now().toUtc() : paidOn.toUtcMidnight(),
        dateKey: paidOn,
        originalAmount: amount,
        needsReview: false,
        fromAccountId: isOutflow ? accountId : null,
        toAccountId: isOutflow ? null : accountId,
        paymentMethodId: paymentMethodId,
        payeeId: templateRow.payeeId,
        note: templateRow.name,
        recurringTemplateId: templateRow.id,
        recurringOccurrenceId: occurrenceId,
      ),
      tagIds: templateRow.tagId == null ? const [] : [templateRow.tagId!],
    );
    if (created.isFailure) return Result.failure(created.failureOrNull!);
    final transaction = created.valueOrNull!;

    // The ACTUAL amount is recorded on the occurrence. The template's `defaultAmountMinor` is not
    // touched — paying ₹520 against a ₹499 subscription records ₹520 here and leaves ₹499 as the
    // template's expectation, so analytics uses actuals without corrupting the schedule
    // (anomaly A29).
    await _occurrenceDao.markPaid(
      id: occurrenceId,
      transactionId: transaction.id,
      paidAmountMinor: amount.minor,
      paidDateKey: paidOn,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return Result.ok(transaction);
  }

  @override
  Future<Result<void, Failure>> skipOccurrence({
    required String occurrenceId,
    String? note,
  }) async {
    final occurrence = await _occurrenceDao.byId(occurrenceId);
    if (occurrence == null) {
      return Result.failure(NotFoundFailure('Occurrence not found.', id: occurrenceId));
    }
    if (occurrence.status == RecurringOccurrenceStatus.paid) {
      return const Result.failure(
        BusinessRuleFailure(
          'A settled occurrence cannot be skipped — unsettle it first.',
          rule: 'cannotSkipPaid',
        ),
      );
    }
    await _occurrenceDao.markSkipped(
      id: occurrenceId,
      note: note,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> unsettleOccurrence(String occurrenceId) async {
    final occurrence = await _occurrenceDao.byId(occurrenceId);
    if (occurrence == null) {
      return Result.failure(NotFoundFailure('Occurrence not found.', id: occurrenceId));
    }
    // Returns it to `due` and clears the settlement fields, so the obligation reappears rather than
    // staying silently marked paid after the transaction behind it is gone. The transaction itself
    // is not touched — this is called *because* it was deleted.
    await _occurrenceDao.unlinkDeletedTransaction(
      id: occurrenceId,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  // ── interval arithmetic ───────────────────────────────────────────────────────────────

  /// Delegates to [RecurringEngine.nextDue].
  ///
  /// The interval arithmetic and the month-end anchor clamp used to live here. Phase 4B moved them
  /// into the engine so the clamp has one definition — anomaly A13 is exactly the kind of rule that
  /// must not exist twice, because the second copy is the one that walks a bill backwards.
  DateKey _advance(DateKey from, RecurringTemplate template) =>
      _engine.nextDue(from: from, template: template);

  /// Validates a template's interval and anchor coherence.
  Failure? _validateTemplate(RecurringTemplate template) {
    if (template.name.trim().isEmpty) {
      return const ValidationFailure('A recurring template needs a name.', field: 'name');
    }
    if (!template.defaultAmount.isPositive) {
      return const ValidationFailure(
        'A recurring template needs a positive default amount.',
        field: 'defaultAmount',
      );
    }
    if (template.intervalCount < 1) {
      return const ValidationFailure(
        'The interval must be at least 1.',
        field: 'intervalCount',
      );
    }
    final end = template.endDateKey;
    if (end != null && end.isBefore(template.startDateKey)) {
      return const ValidationFailure(
        'The end date cannot be before the start date.',
        field: 'endDateKey',
      );
    }

    final anchorDay = template.anchorDayOfMonth;
    if (anchorDay != null && (anchorDay < 1 || anchorDay > 31)) {
      return const ValidationFailure(
        'The day of the month must be between 1 and 31.',
        field: 'anchorDayOfMonth',
      );
    }
    final anchorWeekday = template.anchorWeekday;
    if (anchorWeekday != null && (anchorWeekday < 1 || anchorWeekday > 7)) {
      return const ValidationFailure(
        'The weekday must be between 1 (Monday) and 7 (Sunday).',
        field: 'anchorWeekday',
      );
    }
    final anchorMonth = template.anchorMonth;
    if (anchorMonth != null && (anchorMonth < 1 || anchorMonth > 12)) {
      return const ValidationFailure(
        'The month must be between 1 and 12.',
        field: 'anchorMonth',
      );
    }

    // A monthly or yearly template with no day anchor would advance from whatever day it happened
    // to land on, so a February settlement would pull every later occurrence back to the 28th
    // permanently (anomaly A13). Requiring the anchor is what makes that impossible.
    final needsDayAnchor = template.intervalUnit == RecurringIntervalUnit.month ||
        template.intervalUnit == RecurringIntervalUnit.year;
    if (needsDayAnchor && anchorDay == null) {
      return const ValidationFailure(
        'A monthly or yearly template needs a day of the month to anchor to.',
        field: 'anchorDayOfMonth',
      );
    }
    return null;
  }

  Future<List<RecurringOccurrence>> _mapWithTemplateCurrency(
    List<RecurringOccurrenceRow> rows,
  ) async {
    final currencies = <String, String>{};
    for (final templateId in rows.map((r) => r.templateId).toSet()) {
      final template = await _templateDao.byIdIncludingDeleted(templateId);
      if (template != null) currencies[templateId] = template.currencyCode;
    }
    return rows
        .where((r) => currencies.containsKey(r.templateId))
        .map((r) => r.toEntity(currencies[r.templateId]!))
        .toList();
  }
}
```

### `lib/data/repositories/asset_repository_impl.dart`

```dart
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/asset_dao.dart';
import 'package:alaya/data/repositories/mappers/schedule_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/repositories/asset_repository.dart';

/// `AssetRepository` backed by `AssetDao`.
///
/// **There is no delete method on the contract and none here.** Retiring an asset is [dispose],
/// which records a reason and a date so the money spent stays in analytics after the thing is gone
/// (ARCH_3 §4.1). The `deletedAt` column exists on the table and nothing in this class or its DAO
/// writes it — it is reserved for Phase 8B's trash screen.
final class AssetRepositoryImpl implements AssetRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const AssetRepositoryImpl(this._dao, this._clock);

  final AssetDao _dao;
  final Clock _clock;

  @override
  Stream<List<Asset>> watchInUse() =>
      _dao.watchInUse().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Asset>> watchByType(AssetType type) =>
      _dao.watchByType(type).map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Asset>> watchDisposed() =>
      _dao.watchDisposed().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Asset?> byId(String id) async => (await _dao.byId(id))?.toEntity();

  @override
  Stream<List<Asset>> watchWarrantyEndingInRange({
    required DateKey from,
    required DateKey to,
  }) =>
      _dao
          .watchWarrantyEndingInRange(from: from, to: to)
          .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Asset>> watchServiceDueInRange({
    required DateKey from,
    required DateKey to,
  }) =>
      _dao
          .watchServiceDueInRange(from: from, to: to)
          .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<Asset, Failure>> save(Asset asset) async {
    if (asset.name.trim().isEmpty) {
      return const Result.failure(ValidationFailure('An asset needs a name.', field: 'name'));
    }
    if (asset.status == AssetStatus.disposed) {
      // A disposal needs a reason and a date, which this method has no parameters for. Accepting
      // the status alone would produce a `disposed` asset with no record of why or when — exactly
      // the state ARCH_3 §4.1's "never deleted, always a reason" rule exists to prevent.
      return const Result.failure(
        BusinessRuleFailure(
          'Use dispose() to retire an asset — a disposal needs a reason and a date.',
          rule: 'disposalNeedsReason',
        ),
      );
    }

    // **An asset is not unique by name, and refusing a duplicate was wrong.**
    //
    // A household with five iPhones has five assets: five serial numbers, five warranties, five service
    // histories. Two identical ceiling fans are two fans. The name is a label a person chose, not an
    // identity — so a second "iPhone" is a second phone, and blocking it made the app unusable for the
    // ordinary case of owning more than one of something.
    //
    // This is the opposite of `items`, deliberately. Law L8 makes name plus unit category the identity of
    // an Item because 500g of onion *is* the same onion as another 500g; quantities of a fungible thing
    // merge. An asset never merges: it is one object and it wears out on its own schedule. The
    // name lookup stays on the DAO for the editor to offer a note with — never a block.
    final existing = await _dao.byId(asset.id);

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _dao.upsert(
      assetToCompanion(asset, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );
    return Result.ok(asset);
  }

  @override
  Future<Result<void, Failure>> setStatus({
    required String id,
    required AssetStatus status,
  }) async {
    final existing = await _dao.byId(id);
    if (existing == null) {
      return Result.failure(NotFoundFailure('Asset not found.', id: id));
    }
    if (status == AssetStatus.disposed) {
      // The DAO throws an ArgumentError for this rather than silently accepting it. Catching it
      // here first turns a programming error into a failure the UI can render.
      return const Result.failure(
        BusinessRuleFailure(
          'Use dispose() to retire an asset — a disposal needs a reason and a date.',
          rule: 'disposalNeedsReason',
        ),
      );
    }
    await _dao.setStatus(id: id, status: status, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> dispose({
    required String assetId,
    required AssetDisposalReason reason,
    required DateKey dateKey,
    int? amountMinor,
    String? note,
  }) async {
    final existing = await _dao.byId(assetId);
    if (existing == null) {
      return Result.failure(NotFoundFailure('Asset not found.', id: assetId));
    }
    if (existing.status == AssetStatus.disposed) {
      return const Result.failure(
        BusinessRuleFailure('This asset is already disposed.', rule: 'alreadyDisposed'),
      );
    }
    if (amountMinor != null && amountMinor < 0) {
      return const Result.failure(
        ValidationFailure('Sale proceeds cannot be negative.', field: 'amountMinor'),
      );
    }
    if (amountMinor != null && existing.purchaseCurrencyCode == null) {
      // `assets` has no disposal-currency column: proceeds are denominated in whatever the asset
      // was bought in (ARCH_2 §8). With no purchase currency recorded there is nothing to pair the
      // amount with, and storing a bare number would break Law L1's pairing rule.
      return const Result.failure(
        BusinessRuleFailure(
          'This asset has no purchase currency recorded, so sale proceeds cannot be stored '
          'against it. Add a purchase price first.',
          rule: 'noCurrencyForProceeds',
        ),
      );
    }

    await _dao.dispose(
      assetId: assetId,
      reason: reason,
      dateKey: dateKey,
      amountMinor: amountMinor,
      note: note,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> undispose(String id) async {
    final existing = await _dao.byId(id);
    if (existing == null) {
      return Result.failure(NotFoundFailure('Asset not found.', id: id));
    }
    if (existing.status != AssetStatus.disposed) {
      return const Result.failure(
        BusinessRuleFailure('This asset is not disposed.', rule: 'notDisposed'),
      );
    }
    await _dao.undispose(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> detachFromDeletedTransaction(String id) async {
    await _dao.detachFromDeletedTransaction(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }
}
```

### `lib/data/repositories/service_record_repository_impl.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/asset_dao.dart';
import 'package:alaya/data/daos/service_record_dao.dart';
import 'package:alaya/data/repositories/mappers/schedule_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/service_record.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/repositories/service_record_repository.dart';
import 'package:alaya/domain/repositories/transaction_repository.dart';

/// `ServiceRecordRepository` backed by `ServiceRecordDao`.
///
/// Depends on `TransactionRepository` — the **domain interface**, not the implementation — so that
/// [save]'s optional expense reuses the shape validation, `monthKey` derivation and account
/// resolution already built there rather than reimplementing any of it.
final class ServiceRecordRepositoryImpl implements ServiceRecordRepository {
  /// Creates the repository.
  const ServiceRecordRepositoryImpl(
    this._dao,
    this._assetDao,
    this._transactions,
    this._uids,
    this._clock,
  );

  final ServiceRecordDao _dao;
  final AssetDao _assetDao;
  final TransactionRepository _transactions;
  final UidGenerator _uids;
  final Clock _clock;

  @override
  Stream<List<ServiceRecord>> watchForAsset(String assetId) =>
      _dao.watchForAsset(assetId).map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<ServiceRecord>> watchForAssetByType({
    required String assetId,
    required ServiceRecordType type,
  }) =>
      _dao
          .watchForAssetByType(assetId: assetId, type: type)
          .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<ServiceRecord>> watchWithNextDueInRange({
    required DateKey from,
    required DateKey to,
  }) =>
      _dao
          .watchWithNextDueInRange(from: from, to: to)
          .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<ServiceRecord?> byId(String id) async => (await _dao.byId(id))?.toEntity();

  @override
  Future<ServiceRecord?> mostRecentForAsset(String assetId) async =>
      (await _dao.mostRecentForAsset(assetId))?.toEntity();

  @override
  Future<Map<String, Money>> lifetimeCostByCurrency(String assetId) async {
    // The DAO already sums in SQL grouped by currency, so this only rewraps each total as `Money`.
    // Never flattened into one figure: an asset serviced in two countries has costs in two
    // currencies and adding them is anomaly A34.
    final minorByCode = await _dao.lifetimeCostByCurrency(assetId);
    return {
      for (final e in minorByCode.entries) e.key: Money(e.value, e.key),
    };
  }

  @override
  Future<Result<ServiceRecord, Failure>> save(
    ServiceRecord record, {
    bool alsoRecordAsExpense = false,
    String? accountId,
    String? paymentMethodId,
  }) async {
    final asset = await _assetDao.byId(record.assetId);
    if (asset == null) {
      return Result.failure(
        NotFoundFailure('The asset this record belongs to does not exist.', id: record.assetId),
      );
    }

    if (alsoRecordAsExpense) {
      if (record.cost == null) {
        return const Result.failure(
          ValidationFailure(
            'A service record needs a cost before it can be recorded as an expense.',
            field: 'cost',
          ),
        );
      }
      if (accountId == null) {
        return const Result.failure(
          ValidationFailure(
            'Recording this as an expense needs an account to pay it from.',
            field: 'accountId',
          ),
        );
      }
      if (record.linkedTransactionId != null) {
        return const Result.failure(
          BusinessRuleFailure(
            'This service record is already linked to a transaction.',
            rule: 'alreadyLinked',
          ),
        );
      }
    }

    final existing = await _dao.byId(record.id);
    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );

    if (!alsoRecordAsExpense) {
      await _dao.upsert(
        serviceRecordToCompanion(
          record,
          createdAt: stamps.createdAt,
          updatedAt: stamps.updatedAt,
        ),
      );
      return Result.ok(record);
    }

    // The transaction is created FIRST, and that order is forced rather than chosen:
    // `service_records.linked_transaction_id` is a foreign key into `transactions`, so the row it
    // points at must already exist. The two writes therefore cannot share one drift transaction —
    // neither repository exposes transaction control spanning aggregates — so a failure on the
    // second write is compensated below rather than rolled back by the database.
    final created = await _transactions.create(
      transaction: Transaction(
        id: _uids.generate(),
        kind: TransactionKind.withdrawal,
        // `otherOut` rather than `electronics`: the subtype describes the *flow*, and servicing a
        // television is not the purchase of one. The semantic detail lives on the tag — Phase 1C
        // seeds a `Maintenance` tag scoped to withdrawal and service for exactly this.
        subtype: TransactionSubtype.otherOut,
        // **Now when the date is today, midnight only when it is not.**
        //
        // The ledger orders by `dateKey DESC, occurredAt DESC`. Stamping midnight unconditionally sent
        // every same-day entry to the *bottom* of today's group, behind hand-entered expenses stamped
        // with the real clock — so two records made seconds apart appeared in an order with no
        // relationship to anything the user did.
        //
        // Midnight stays right for a back-dated record: nobody knows what time last Tuesday's plumber
        // came, and inventing one would be a worse lie than admitting the day is all we have.
        occurredAtUtc: record.serviceDateKey == _clock.today()
            ? _clock.now().toUtc()
            : record.serviceDateKey.toUtcMidnight(),
        dateKey: record.serviceDateKey,
        originalAmount: record.cost!,
        needsReview: false,
        fromAccountId: accountId,
        // Optional, and unvalidated on purpose: a null method is the ordinary case, and refusing one
        // would make "how did you pay?" a question the user must answer to record what they spent.
        paymentMethodId: paymentMethodId,
        note: _expenseNote(record, assetName: asset.name),
      ),
    );
    if (created.isFailure) return Result.failure(created.failureOrNull!);
    final transactionId = created.valueOrNull!.id;

    final linked = record.copyWith(linkedTransactionId: transactionId);
    try {
      await _dao.upsert(
        serviceRecordToCompanion(
          linked,
          createdAt: stamps.createdAt,
          updatedAt: stamps.updatedAt,
        ),
      );
    } catch (error) {
      // Compensating action. Without it a failed record write would leave a withdrawal standing on
      // its own — silently inflating expenses with nothing in the service history to explain it,
      // which is worse than the operation plainly failing.
      await _transactions.delete(
        id: transactionId,
        reason: 'Rolled back: the service record it belonged to could not be saved.',
      );
      return Result.failure(
        UnexpectedFailure(
          'The service record could not be saved, so the matching expense was rolled back.',
          cause: error,
        ),
      );
    }

    // Returns the record carrying BOTH ids — its own and `linkedTransactionId` — which is what the
    // caller needs to navigate between the service history and the expense.
    return Result.ok(linked);
  }

  @override
  Future<Result<void, Failure>> unlinkDeletedTransaction(String id) async {
    await _dao.unlinkDeletedTransaction(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    await _dao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  /// The note put on the generated withdrawal, so the expense is recognisable in the transaction
  /// list without opening the asset.
  String _expenseNote(ServiceRecord record, {required String assetName}) {
    final provider = record.providerName;
    final base = '${record.type.name} — $assetName';
    return provider == null || provider.isEmpty ? base : '$base ($provider)';
  }
}
```

### `lib/data/repositories/batch_repository_impl.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/batch_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/item_category_resolver.dart';
import 'package:alaya/data/repositories/mappers/stock_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/repositories/batch_repository.dart';

/// `BatchRepository` backed by `BatchDao`.
final class BatchRepositoryImpl implements BatchRepository {
  /// Creates the repository over [dao], resolving item categories through [categories].
  const BatchRepositoryImpl(this._dao, this._categories, this._clock);

  final BatchDao _dao;
  final ItemCategoryResolver _categories;
  final Clock _clock;

  @override
  Stream<List<Batch>> watchByItemFefo(String itemId) =>
      _dao.watchByItemFefo(itemId).asyncMap((rows) => _mapAll(rows));

  @override
  Future<List<Batch>> byItemFefo(String itemId) async =>
      _mapAll(await _dao.byItemFefo(itemId));

  @override
  Stream<List<Batch>> watchByItem(String itemId) =>
      _dao.watchByItem(itemId).asyncMap((rows) => _mapAll(rows));

  @override
  Stream<List<Batch>> watchExpiringInRange({
    required DateKey from,
    required DateKey to,
  }) =>
      _dao.watchExpiringInRange(from: from, to: to).asyncMap((rows) => _mapAll(rows));

  @override
  Future<Batch?> byId(String id) async {
    final row = await _dao.byIdIncludingDeleted(id);
    if (row == null) return null;
    final category = await _categories.categoryOf(row.itemId);
    if (category == null) return null;
    return row.toEntity(category);
  }

  @override
  Future<Result<Batch, Failure>> create(Batch batch) async {
    if (!batch.initialQuantity.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'A new batch needs a quantity greater than zero.',
          field: 'initialQuantity',
        ),
      );
    }
    if (batch.remainingQuantity != batch.initialQuantity) {
      // BatchDao.insertWithOpeningMovement's documented caller contract: nothing has been consumed
      // yet, so the two cannot differ. Enforced here rather than trusted, because the founding
      // movement it writes uses `initialQuantityMilli` — a mismatch would make the batch a
      // permanent discrepancy in `v_batch_stock_check` from the moment it was created.
      return const Result.failure(
        ValidationFailure(
          'A new batch must have its full quantity remaining.',
          field: 'remainingQuantity',
        ),
      );
    }

    final category = await _categories.categoryOf(batch.itemId);
    if (category == null) {
      return Result.failure(
        NotFoundFailure('The item this batch belongs to does not exist.', id: batch.itemId),
      );
    }
    if (category != batch.initialQuantity.category) {
      // A `Qty` in the wrong category would be stored as a bare integer and silently reinterpreted
      // on read as the item's own category — 2 pieces becoming 2 grams. Law L8 makes this
      // impossible to fix afterwards, so it is refused now.
      return Result.failure(
        ValidationFailure(
          'This batch is measured in ${batch.initialQuantity.category.name} but its item is '
          'measured in ${category.name}.',
          field: 'initialQuantity',
        ),
      );
    }

    final now = _clock.nowUtcMillis();
    await _dao.insertWithOpeningMovement(
      batch: batchToCompanion(batch, createdAt: now, updatedAt: now),
      // `purchaseIn` when the batch came from a transaction line, `manualIn` when the user added
      // it directly. The repository's call to make, as the DAO's doc notes.
      openingKind: batch.sourceTransactionLineId != null
          ? StockMovementKind.purchaseIn
          : StockMovementKind.manualIn,
      nowUtcMillis: now,
    );
    return Result.ok(batch);
  }

  @override
  Future<Result<Batch, Failure>> updateMetadata(Batch batch) async {
    final existing = await _dao.byIdIncludingDeleted(batch.id);
    if (existing == null) {
      return Result.failure(NotFoundFailure('Batch not found.', id: batch.id));
    }
    if (existing.remainingQuantityMilli != batch.remainingQuantity.milliBase ||
        existing.initialQuantityMilli != batch.initialQuantity.milliBase) {
      // Quantities move only by recording a movement, so that the ledger and the cache can never
      // disagree (Law L3). A metadata update that also changed a quantity would write the cache
      // with no matching movement — exactly the drift `v_batch_stock_check` exists to detect.
      return const Result.failure(
        BusinessRuleFailure(
          'A batch\'s quantity cannot be changed here — record a stock movement instead.',
          rule: 'quantityRequiresMovement',
        ),
      );
    }

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing.createdAt,
      clock: _clock,
    );
    await _dao.updateMetadata(
      batchToCompanion(batch, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );
    return Result.ok(batch);
  }

  @override
  Future<Result<void, Failure>> detachFromDeletedTransaction(String batchId) async {
    await _dao.detachFromDeletedTransaction(
      batchId: batchId,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    await _dao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Stream<List<BatchReconciliation>> watchReconciliation() =>
      _dao.watchReconciliation().asyncMap(_mapReconciliations);

  @override
  Future<List<BatchReconciliation>> findDiscrepancies() async =>
      _mapReconciliations(await _dao.findDiscrepancies());

  @override
  Future<Result<void, Failure>> recompute(String batchId) async {
    await _dao.recomputeRemaining(batchId);
    return const Result.ok(null);
  }

  @override
  Future<Result<int, Failure>> recomputeAll() async {
    // Counted before repairing, not after: once every cache is rebuilt there are no discrepancies
    // left to count, so asking afterwards would always return zero and report that nothing was
    // wrong. The figure the Settings screen wants is how many were broken.
    final broken = await _dao.findDiscrepancies();
    await _dao.recomputeAll();
    return Result.ok(broken.length);
  }

  Future<List<BatchReconciliation>> _mapReconciliations(List<BatchStockCheckRow> rows) async {
    final categories = await _categories.categoriesFor(rows.map((r) => r.itemId));
    return rows
        .where((r) => categories.containsKey(r.itemId))
        .map((r) => r.toEntity(categories[r.itemId]!))
        .toList();
  }

  Future<List<Batch>> _mapAll(List<InventoryBatchRow> rows) async {
    final categories = await _categories.categoriesFor(rows.map((r) => r.itemId));
    return rows
        .where((r) => categories.containsKey(r.itemId))
        .map((r) => r.toEntity(categories[r.itemId]!))
        .toList();
  }
}
```

### `lib/data/repositories/stock_repository_impl.dart`

```dart
import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_formatter.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/batch_dao.dart';
import 'package:alaya/data/daos/stock_movement_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/item_category_resolver.dart';
import 'package:alaya/data/repositories/mappers/stock_mappers.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/domain/repositories/stock_repository.dart';

/// `StockRepository` backed by `BatchDao` and `StockMovementDao`.
///
/// Every write here goes through [BatchDao.applyMovements], which pairs each movement with its
/// batch's cache update inside one transaction (Laws L3, L14). There is no path that records a
/// movement without updating the cache, or the reverse.
final class StockRepositoryImpl implements StockRepository {
  /// Creates the repository.
  const StockRepositoryImpl(
    this._batchDao,
    this._movementDao,
    this._categories,
    this._uids,
    this._clock,
  );

  final BatchDao _batchDao;
  final StockMovementDao _movementDao;
  final ItemCategoryResolver _categories;
  final UidGenerator _uids;
  final Clock _clock;

  /// Formats quantities for the user-facing text on a failure. `Qty.toString()` is a debug
  /// representation (`2500000m(weight)`) and its own doc says never to show it — these messages are
  /// read by a person, so they go through the formatter.
  static const QtyFormatter _qtyFormat = QtyFormatter();

  @override
  Future<Result<List<ConsumptionDraw>, Failure>> consume({
    required String itemId,
    required Qty quantity,
    required StockMovementKind kind,
    String? reason,
    String? note,
  }) async {
    if (!quantity.isPositive) {
      return const Result.failure(
        ValidationFailure('The quantity to consume must be greater than zero.', field: 'quantity'),
      );
    }

    final category = await _categories.categoryOf(itemId);
    if (category == null) {
      return Result.failure(NotFoundFailure('Item not found.', id: itemId));
    }
    if (category != quantity.category) {
      return Result.failure(
        ValidationFailure(
          'This item is measured in ${category.name}, not ${quantity.category.name}.',
          field: 'quantity',
        ),
      );
    }

    // FEFO order, already filtered to batches holding stock: nearest expiry first, undated last
    // (anomaly A08). The DAO owns that ordering so it is expressed once, in SQL, where the index
    // can serve it.
    final batches = await _batchDao.byItemFefo(itemId);
    final available = batches.fold<int>(0, (sum, b) => sum + b.remainingQuantityMilli);

    if (available < quantity.milliBase) {
      // Checked before any write, and nothing is written on this path. A partial consumption would
      // leave the ledger describing something that did not happen — worse than refusing, because
      // the user would have no way to tell how much actually came out.
      return Result.failure(
        BusinessRuleFailure(
          'Only ${_qtyFormat.format(Qty(available, category))} is on hand, less than the '
          '${_qtyFormat.format(quantity)} requested.',
          rule: 'insufficientStock',
        ),
      );
    }

    final plan = _planDraws(
      batches: batches,
      needed: quantity.milliBase,
      category: category,
    );
    await _applyDraws(
      itemId: itemId,
      draws: plan,
      kind: kind,
      reason: reason,
      note: note,
    );
    return Result.ok(plan);
  }

  @override
  Future<Result<void, Failure>> consumeFromBatch({
    required String batchId,
    required Qty quantity,
    required StockMovementKind kind,
    String? reason,
    String? note,
  }) async {
    if (!quantity.isPositive) {
      return const Result.failure(
        ValidationFailure('The quantity to consume must be greater than zero.', field: 'quantity'),
      );
    }

    final batch = await _batchDao.byIdIncludingDeleted(batchId);
    if (batch == null) {
      return Result.failure(NotFoundFailure('Batch not found.', id: batchId));
    }
    final category = await _categories.categoryOf(batch.itemId);
    if (category == null) {
      return Result.failure(NotFoundFailure('Item not found.', id: batch.itemId));
    }
    if (category != quantity.category) {
      return Result.failure(
        ValidationFailure(
          'This batch is measured in ${category.name}, not ${quantity.category.name}.',
          field: 'quantity',
        ),
      );
    }
    if (batch.remainingQuantityMilli < quantity.milliBase) {
      return Result.failure(
        BusinessRuleFailure(
          'This batch holds only '
          '${_qtyFormat.format(Qty(batch.remainingQuantityMilli, category))}, less than the '
          '${_qtyFormat.format(quantity)} requested.',
          rule: 'insufficientStock',
        ),
      );
    }

    await _applyDraws(
      itemId: batch.itemId,
      draws: [ConsumptionDraw(batchId: batchId, quantity: quantity)],
      kind: kind,
      reason: reason,
      note: note,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> addStock({
    required String batchId,
    required Qty quantity,
    required StockMovementKind kind,
    String? note,
  }) async {
    if (!quantity.isPositive) {
      return const Result.failure(
        ValidationFailure('The quantity to add must be greater than zero.', field: 'quantity'),
      );
    }
    if (!StockMovementDao.incomingKinds.contains(kind)) {
      // Guarding the direction rather than trusting it: an outgoing kind passed here would reduce
      // stock while the caller believed it was adding, and the cache would faithfully follow.
      return Result.failure(
        ValidationFailure(
          '${kind.name} removes stock rather than adding it.',
          field: 'kind',
        ),
      );
    }

    final batch = await _batchDao.byIdIncludingDeleted(batchId);
    if (batch == null) {
      return Result.failure(NotFoundFailure('Batch not found.', id: batchId));
    }
    final category = await _categories.categoryOf(batch.itemId);
    if (category == null) {
      return Result.failure(NotFoundFailure('Item not found.', id: batch.itemId));
    }
    if (category != quantity.category) {
      return Result.failure(
        ValidationFailure(
          'This batch is measured in ${category.name}, not ${quantity.category.name}.',
          field: 'quantity',
        ),
      );
    }

    await _applyDraws(
      itemId: batch.itemId,
      draws: [ConsumptionDraw(batchId: batchId, quantity: quantity)],
      kind: kind,
      note: note,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> reverse({
    required String movementId,
    String? reason,
  }) async {
    final original = await _movementDao.byId(movementId);
    if (original == null) {
      return Result.failure(NotFoundFailure('Movement not found.', id: movementId));
    }

    final alreadyReversed = await _movementDao.reversalOf(movementId);
    if (alreadyReversed != null) {
      return const Result.failure(
        BusinessRuleFailure(
          'This movement has already been reversed.',
          rule: 'alreadyReversed',
        ),
      );
    }
    if (original.reversesMovementId != null) {
      // Reversing a reversal would be indistinguishable from re-applying the original, and would
      // let a chain build up that nothing can interpret. Undo is one level deep by design.
      return const Result.failure(
        BusinessRuleFailure(
          'A correction cannot itself be reversed — record a new movement instead.',
          rule: 'cannotReverseAReversal',
        ),
      );
    }

    // The compensating kind, chosen so the pair nets to zero under the same direction rule
    // `v_batch_stock_check` applies: an incoming movement is undone by an adjustOut and vice versa.
    final compensating = StockMovementDao.incomingKinds.contains(original.kind)
        ? StockMovementKind.adjustOut
        : StockMovementKind.adjustIn;

    final now = _clock.nowUtcMillis();
    await _batchDao.applyMovements(
      entries: [
        (
          batchId: original.batchId,
          movement: StockMovementsCompanion.insert(
            id: _uids.generate(),
            batchId: original.batchId,
            itemId: original.itemId,
            kind: compensating,
            quantityMilli: original.quantityMilli,
            occurredAt: now,
            dateKey: _clock.today(),
            reason: Value(reason),
            reversesMovementId: Value(movementId),
            createdAt: now,
            updatedAt: now,
          ),
        ),
      ],
      nowUtcMillis: now,
    );
    return const Result.ok(null);
  }

  @override
  Stream<List<StockMovement>> watchForBatch(String batchId) {
    return _movementDao.watchForBatch(batchId).asyncMap(_mapAll);
  }

  @override
  Stream<List<StockMovement>> watchForItemInRange({
    required String itemId,
    required DateKey from,
    required DateKey to,
  }) {
    return _movementDao
        .watchForItemInRange(itemId: itemId, from: from, to: to)
        .asyncMap(_mapAll);
  }

  @override
  Future<List<WasteTotal>> wasteTotals({
    required DateKey from,
    required DateKey to,
  }) async {
    // Both waste kinds, totalled separately per item. `expired` and `waste` are distinct events —
    // food that rotted unnoticed versus food thrown out deliberately — but both are stock that was
    // paid for and never used, which is what ARCH_3 §5.1 query 14 measures.
    final byItem = <String, ({int milli, MoneyByCurrency cost})>{};

    // One query across all items, both waste kinds. Asking per item would require the caller to
    // already know which items have waste — inverting the question, since that set is the answer.
    final movements = await _movementDao.forKindsInRange(
      kinds: const {StockMovementKind.waste, StockMovementKind.expired},
      from: from,
      to: to,
    );

    // Batch costs are cached: a single wasted item is typically spread over few batches, and
    // re-reading the same batch row once per movement would dominate the cost of this query.
    final batchCosts = <String, ({int? unitCostMinor, String? currencyCode})>{};

    for (final m in movements) {
      final entry = byItem.putIfAbsent(m.itemId, () => (milli: 0, cost: MoneyByCurrency()));
      byItem[m.itemId] = (milli: entry.milli + m.quantityMilli, cost: entry.cost);

      final cost = batchCosts[m.batchId] ??= await () async {
        final batch = await _batchDao.byIdIncludingDeleted(m.batchId);
        return (unitCostMinor: batch?.unitCostMinor, currencyCode: batch?.costCurrencyCode);
      }();

      final unitCost = cost.unitCostMinor;
      final costCode = cost.currencyCode;
      if (unitCost != null && costCode != null) {
        entry.cost.add(
          currencyCode: costCode,
          // unitCost is per purchased unit; the movement is in base-milli units, so the wasted
          // money is unitCost x (milli / 1000). Truncated: a fraction of a minor unit cannot be
          // represented, and waste valuation is an estimate rather than a ledger figure.
          minor: (unitCost * m.quantityMilli / 1000).truncate(),
        );
      }
    }

    final result = <WasteTotal>[];
    for (final e in byItem.entries) {
      final category = await _categories.categoryOf(e.key);
      if (category == null) continue;
      result.add(
        WasteTotal(
          itemId: e.key,
          quantity: Qty(e.value.milli, category),
          costByCurrency: e.value.cost.totals,
        ),
      );
    }
    return result;
  }

  /// Delegates FEFO planning to [InventoryConsumptionService].
  ///
  /// This method used to implement the ordering and draw-down itself. Phase 4B moved the algorithm
  /// into the service so there is one definition of it — the same consolidation Phase 4A made for
  /// the currency cross-rate, and for the same reason: two copies of an ordering rule drift apart.
  /// What stays here is the part only a repository can do — writing every draw in one transaction.
  List<ConsumptionDraw> _planDraws({
    required List<InventoryBatchRow> batches,
    required int needed,
    required UnitCategory category,
  }) {
    const service = InventoryConsumptionService();
    final plan = service.plan(
      batches: batches.map(
        (row) => ConsumableBatch(
          batchId: row.id,
          remaining: Qty(row.remainingQuantityMilli, category),
          purchasedDateKey: row.purchasedDateKey,
          expiryDateKey: row.expiryDateKey,
        ),
      ),
      needed: Qty(needed, category),
    );
    // Insufficiency is already checked by the caller before this runs, so a failure here would mean
    // the two disagreed — return no draws rather than a partial set either way.
    return plan.valueOrNull?.draws ?? const [];
  }

  /// Records one movement per draw, all in a single transaction (Law L14).
  Future<void> _applyDraws({
    required String itemId,
    required List<ConsumptionDraw> draws,
    required StockMovementKind kind,
    String? reason,
    String? note,
  }) {
    final now = _clock.nowUtcMillis();
    final today = _clock.today();
    return _batchDao.applyMovements(
      entries: draws
          .map(
            (draw) => (
              batchId: draw.batchId,
              movement: StockMovementsCompanion.insert(
                id: _uids.generate(),
                batchId: draw.batchId,
                itemId: itemId,
                kind: kind,
                quantityMilli: draw.quantity.milliBase,
                occurredAt: now,
                dateKey: today,
                reason: Value(reason),
                note: Value(note),
                createdAt: now,
                updatedAt: now,
              ),
            ),
          )
          .toList(),
      nowUtcMillis: now,
    );
  }

  Future<List<StockMovement>> _mapAll(List<StockMovementRow> rows) async {
    final categories = await _categories.categoriesFor(rows.map((r) => r.itemId));
    return rows
        .where((r) => categories.containsKey(r.itemId))
        .map((r) => r.toEntity(categories[r.itemId]!))
        .toList();
  }
}
```

### `lib/data/repositories/shopping_repository_impl.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/item_dao.dart';
import 'package:alaya/data/daos/shopping_entry_dao.dart';
import 'package:alaya/data/daos/shopping_list_dao.dart';
import 'package:alaya/data/daos/transaction_line_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/item_category_resolver.dart';
import 'package:alaya/data/repositories/mappers/shopping_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/repositories/shopping_repository.dart';

/// `ShoppingRepository` backed by `ShoppingListDao` and `ShoppingEntryDao`.
final class ShoppingRepositoryImpl implements ShoppingRepository {
  /// Creates the repository.
  const ShoppingRepositoryImpl(
    this._listDao,
    this._entryDao,
    this._itemDao,
    this._lineDao,
    this._categories,
    this._settings,
    this._uids,
    this._clock,
  );

  final ShoppingListDao _listDao;
  final ShoppingEntryDao _entryDao;
  final ItemDao _itemDao;
  final TransactionLineDao _lineDao;
  final ItemCategoryResolver _categories;
  final SettingsRepository _settings;
  final UidGenerator _uids;
  final Clock _clock;

  // ── lists ─────────────────────────────────────────────────────────────────────────────

  @override
  Stream<List<ShoppingList>> watchSelectableLists() =>
      _listDao.watchSelectable().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<ShoppingList>> watchAllLists() =>
      _listDao.watchAllIncludingArchived().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<ShoppingList?> watchDefaultList() =>
      _listDao.watchDefault().map((row) => row?.toEntity());

  @override
  Future<ShoppingList?> listById(String id) async =>
      (await _listDao.byIdIncludingDeleted(id))?.toEntity();

  @override
  Future<Result<ShoppingList, Failure>> saveList(ShoppingList list) async {
    if (list.name.trim().isEmpty) {
      return const Result.failure(
        ValidationFailure('A shopping list needs a name.', field: 'name'),
      );
    }

    final existing = await _listDao.byIdIncludingDeleted(list.id);
    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _listDao.upsert(
      shoppingListToCompanion(list, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );

    // `isDefault` carries no database-level uniqueness constraint, so setting it through a plain
    // upsert would leave two lists flagged. The DAO's setDefault clears every other list's flag in
    // the same transaction; routing through it keeps "exactly one default" true in practice.
    if (list.isDefault && existing?.isDefault != true) {
      await _listDao.setDefault(id: list.id, nowUtcMillis: stamps.updatedAt);
    }
    return Result.ok(list);
  }

  @override
  Future<Result<void, Failure>> setDefaultList(String id) async {
    final list = await _listDao.byIdIncludingDeleted(id);
    if (list == null || list.deletedAt != null) {
      return Result.failure(NotFoundFailure('Shopping list not found.', id: id));
    }
    if (list.isArchived) {
      return const Result.failure(
        BusinessRuleFailure(
          'An archived list cannot be the default — unarchive it first.',
          rule: 'archivedCannotBeDefault',
        ),
      );
    }
    await _listDao.setDefault(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> setListArchived({
    required String id,
    required bool isArchived,
  }) async {
    final list = await _listDao.byIdIncludingDeleted(id);
    if (list == null || list.deletedAt != null) {
      return Result.failure(NotFoundFailure('Shopping list not found.', id: id));
    }
    if (isArchived && list.isDefault) {
      // Archiving the default would leave quick-add with nowhere to write, silently. Refusing
      // makes the user pick a new default first, which is the decision they actually need to make.
      return const Result.failure(
        BusinessRuleFailure(
          'This is the default list. Make another list the default before archiving it.',
          rule: 'cannotArchiveDefaultList',
        ),
      );
    }
    await _listDao.setArchived(
      id: id,
      isArchived: isArchived,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> deleteList(String id) async {
    // Cascades to the list's entries inside one transaction, in the DAO.
    await _listDao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  // ── entries ───────────────────────────────────────────────────────────────────────────

  @override
  Stream<List<ShoppingEntry>> watchEntries(String listId) =>
      _entryDao.watchForList(listId).asyncMap(_mapEntries);

  @override
  Stream<List<ShoppingEntry>> watchUncheckedEntries(String listId) =>
      _entryDao.watchUncheckedForList(listId).asyncMap(_mapEntries);

  @override
  Future<Result<ShoppingEntry, Failure>> saveEntry(ShoppingEntry entry) async {
    // An entry names a catalogued item OR carries free text — never neither, or the row renders as
    // a blank line nobody can act on (anomaly A24 is about allowing free text, not about allowing
    // nothing).
    final hasItem = entry.itemId != null;
    final hasText = entry.freeText != null && entry.freeText!.trim().isNotEmpty;
    if (!hasItem && !hasText) {
      return const Result.failure(
        ValidationFailure(
          'A shopping entry needs either an item or some text.',
          field: 'freeText',
        ),
      );
    }

    if (hasItem) {
      final item = await _itemDao.byIdIncludingDeleted(entry.itemId!);
      if (item == null) {
        return Result.failure(NotFoundFailure('Item not found.', id: entry.itemId!));
      }
      final quantity = entry.quantity;
      if (quantity != null && quantity.category != item.unitCategory) {
        // A quantity in the wrong category would be stored as a bare integer and reinterpreted on
        // read as the item's own category — 2 pieces becoming 2 grams (Law L8).
        return Result.failure(
          ValidationFailure(
            'This entry is measured in ${quantity.category.name} but the item is measured in '
            '${item.unitCategory.name}.',
            field: 'quantity',
          ),
        );
      }
    }

    final existing = await _entryDao.byIdIncludingDeleted(entry.id);
    final now = _clock.nowUtcMillis();

    // Editing an auto-generated entry promotes it to `manual`, after which the suggestion engine
    // never touches it again (anomaly A22). Detected by comparing against the stored row rather
    // than trusting the incoming entity's own `origin`: a UI that round-trips an entity would
    // otherwise have to remember to flip the flag itself, and forgetting would let regeneration
    // silently overwrite the user's edit.
    final wasAuto = existing != null && existing.origin == ShoppingEntryOrigin.autoLowStock;
    final effectiveOrigin = wasAuto ? ShoppingEntryOrigin.manual : entry.origin;

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    final promoted = entry.copyWith(origin: effectiveOrigin);
    await _entryDao.upsert(
      shoppingEntryToCompanion(
        promoted,
        createdAt: stamps.createdAt,
        updatedAt: stamps.updatedAt,
      ),
    );
    if (wasAuto) {
      // Belt and braces: the companion already carries `manual`, but routing through the DAO's own
      // promote method means the transition is expressed in one place if it ever grows.
      await _entryDao.promoteToManual(id: entry.id, nowUtcMillis: now);
    }
    return Result.ok(promoted);
  }

  @override
  Future<Result<void, Failure>> setEntryChecked({
    required String id,
    required bool isChecked,
  }) async {
    await _entryDao.setChecked(
      id: id,
      isChecked: isChecked,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> snoozeEntry({
    required String id,
    required DateKey until,
  }) async {
    final stock = await _stockAtDecisionMilli(id);
    if (stock == null) {
      return Result.failure(NotFoundFailure('Shopping entry not found.', id: id));
    }
    await _entryDao.setAutoState(
      id: id,
      autoState: ShoppingEntryAutoState.snoozed,
      stockAtDecisionMilli: stock,
      snoozeUntil: until,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> dismissEntry(String id) async {
    final stock = await _stockAtDecisionMilli(id);
    if (stock == null) {
      return Result.failure(NotFoundFailure('Shopping entry not found.', id: id));
    }
    // Records the stock level at the moment of dismissal alongside the state. A dismissal that
    // stored only the flag would never come back — but one that came back on a timer would nag.
    // Storing the reading means the suggestion returns exactly when stock has genuinely risen
    // above the threshold and fallen below it again (anomaly A23).
    await _entryDao.setAutoState(
      id: id,
      autoState: ShoppingEntryAutoState.dismissed,
      stockAtDecisionMilli: stock,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> reorderEntries(List<String> orderedIds) async {
    await _entryDao.reorder(
      orderedIds: orderedIds,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> deleteEntry(String id) async {
    await _entryDao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  // ── the suggestion engine ─────────────────────────────────────────────────────────────

  @override
  Future<Result<int, Failure>> regenerateLowStockSuggestions(String listId) async {
    final list = await _listDao.byIdIncludingDeleted(listId);
    if (list == null || list.deletedAt != null) {
      return Result.failure(NotFoundFailure('Shopping list not found.', id: listId));
    }

    final lowStock = await _itemDao.watchLowStock().first;
    final existingAuto = await _entryDao.watchActiveAutoSuggestions(listId).first;
    var sortOrder = existingAuto.length;
    var active = 0;

    for (final row in lowStock) {
      final threshold = row.lowStockThresholdMilli;
      if (threshold == null) continue;
      final shortfall = threshold - row.totalRemainingMilli;
      if (shortfall <= 0) continue;

      final existing = await _entryDao.findAutoEntry(listId: listId, itemId: row.itemId);

      // A dismissed or snoozed suggestion stays suppressed until stock has recovered past the
      // reading taken when the user dismissed it. Comparing against `generatedAtStockMilli` rather
      // than against the threshold is what distinguishes "still the same shortage they already
      // said no to" from "they bought some and ran out again" (anomaly A23).
      if (existing != null && existing.autoState != ShoppingEntryAutoState.active) {
        final atDecision = existing.generatedAtStockMilli;
        final recovered = atDecision != null && row.totalRemainingMilli > atDecision;
        if (!recovered) continue;
      }

      // Idempotent by construction: `idx_shopping_auto` makes
      // `(listId, itemId, origin='autoLowStock')` unique among live rows, and the DAO's
      // read-then-write honours it — a partial index cannot be an `ON CONFLICT` target, which is
      // why this is not a plain upsert (see the DAO's own note).
      await _entryDao.upsertAutoEntry(
        newId: _uids.generate(),
        listId: listId,
        itemId: row.itemId,
        unitCode: await _itemUnitCode(row.itemId),
        quantityMilli: shortfall,
        stockAtGenerationMilli: row.totalRemainingMilli,
        sortOrder: sortOrder++,
        nowUtcMillis: _clock.nowUtcMillis(),
      );
      active++;
    }
    return Result.ok(active);
  }

  // ── closing the loop back to money ────────────────────────────────────────────────────

  @override
  Future<Result<List<TransactionLine>, Failure>> buildPurchaseDraft(String listId) async {
    // Mapped to entities first, deliberately. Building drafts straight off `ShoppingEntryRow`
    // means hand-assembling a `Qty` from `quantityMilli` and a `Money` from
    // `estimatedPriceMinor` — re-deriving, at a second site, the category and currency resolution
    // that `_mapEntries` already does correctly.
    final entries = await _mapEntries(await _entryDao.watchForList(listId).first);
    final checked =
        entries.where((e) => e.isChecked && e.purchasedTransactionLineId == null).toList();
    if (checked.isEmpty) {
      return const Result.failure(
        BusinessRuleFailure(
          'Nothing on this list is ticked off yet.',
          rule: 'nothingToPurchase',
        ),
      );
    }

    // Drafts only — nothing is written here. The user still confirms the amount and account in the
    // expense editor, and `TransactionRepository.create` is what commits. `transactionId` is left
    // empty deliberately: the transaction does not exist yet, and inventing an id here would let a
    // caller persist a line pointing at nothing.
    final drafts = <TransactionLine>[];
    var lineNo = 1;
    for (final entry in checked) {
      final itemId = entry.itemId;
      drafts.add(
        TransactionLine(
          id: _uids.generate(),
          transactionId: '',
          lineNo: lineNo++,
          description: entry.freeText ?? await _itemName(itemId) ?? 'Item',
          // A catalogued item becomes stock on purchase; free text has nowhere to land, so it
          // stays a plain expense line (ARCH_2 §4.2's `destination` is what removes that
          // ambiguity — anomaly A12).
          destination: itemId != null
              ? TransactionLineDestination.inventory
              : TransactionLineDestination.none,
          itemId: itemId,
          quantity: entry.quantity,
          // Falls back to the item's own display unit. An auto-generated low-stock suggestion is
          // written without one — nothing asked the user — and a line bound for inventory with no
          // unit cannot become a batch, because the column is a foreign key into `units`.
          unitCode: entry.unitCode ?? await _itemUnitCode(itemId),
          lineAmount: entry.estimatedPrice,
        ),
      );
    }
    return Result.ok(drafts);
  }

  @override
  Future<Result<void, Failure>> markPurchased({
    required List<String> entryIds,
    required String transactionId,
  }) async {
    final lines = await _lineDao.forTransaction(transactionId);
    if (lines.isEmpty) {
      return Result.failure(
        NotFoundFailure('That transaction has no lines to link.', id: transactionId),
      );
    }

    // The contract hands over a transaction id, but an entry links to one specific *line*
    // (anomaly A25 — knowing which line fulfilled it is what lets the UI show the price paid).
    // Matching is by `itemId`, since `buildPurchaseDraft` built each line from an entry and
    // carried that id across; free-text entries fall back to matching the description.
    final byItemId = <String, String>{};
    final byDescription = <String, String>{};
    for (final line in lines) {
      final itemId = line.itemId;
      if (itemId != null) {
        byItemId.putIfAbsent(itemId, () => line.id);
      } else {
        byDescription.putIfAbsent(line.description.trim().toLowerCase(), () => line.id);
      }
    }

    final now = _clock.nowUtcMillis();
    final unmatched = <String>[];
    for (final entryId in entryIds) {
      final entry = await _entryDao.byIdIncludingDeleted(entryId);
      if (entry == null) {
        unmatched.add(entryId);
        continue;
      }
      final lineId = entry.itemId != null
          ? byItemId[entry.itemId]
          : byDescription[(entry.freeText ?? '').trim().toLowerCase()];
      if (lineId == null) {
        unmatched.add(entryId);
        continue;
      }
      await _entryDao.markPurchased(
        id: entryId,
        transactionLineId: lineId,
        nowUtcMillis: now,
      );
    }

    if (unmatched.isNotEmpty) {
      // Reported rather than swallowed: the entries that *did* match are already linked, and
      // silently dropping the rest would leave the user's list half-updated with no explanation.
      return Result.failure(
        BusinessRuleFailure(
          '${unmatched.length} of ${entryIds.length} entries had no matching line in that '
          'transaction and were left unticked.',
          rule: 'entryLineMismatch',
        ),
      );
    }
    return const Result.ok(null);
  }

  /// The item's current total stock in base-milli units, for recording alongside a snooze or
  /// dismissal. Returns 0 for a free-text entry, which has no stock to read.
  Future<int?> _stockAtDecisionMilli(String entryId) async {
    final entry = await _entryDao.byIdIncludingDeleted(entryId);
    if (entry == null) return null;
    final itemId = entry.itemId;
    if (itemId == null) return 0;
    final stock = await _itemDao.stockOf(itemId);
    return stock?.totalRemainingMilli ?? 0;
  }

  /// The display unit code of [itemId], or null when there is no item.
  Future<String?> _itemUnitCode(String? itemId) async {
    if (itemId == null) return null;
    final item = await _itemDao.byIdIncludingDeleted(itemId);
    return item?.defaultDisplayUnitCode;
  }

  Future<String?> _itemName(String? itemId) async {
    if (itemId == null) return null;
    final row = await _itemDao.byIdIncludingDeleted(itemId);
    return row?.name;
  }

  Future<List<ShoppingEntry>> _mapEntries(List<ShoppingEntryRow> rows) async {
    final categories = await _categories.categoriesFor(
      rows.map((r) => r.itemId).whereType<String>(),
    );
    final homeCurrencyCode = await _homeCurrencyCode();
    return rows
        .map(
          (r) => r.toEntity(
            category: r.itemId == null ? null : categories[r.itemId],
            homeCurrencyCode: homeCurrencyCode,
          ),
        )
        .toList();
  }

  /// The user's home currency, for reading an entry's estimated price.
  ///
  /// Falls back to `INR` only if the seeded setting is somehow absent — Phase 1C always writes it,
  /// so this is defensive rather than an expected path.
  Future<String> _homeCurrencyCode() async =>
      await _settings.readHomeCurrencyCode() ?? 'INR';
}
```
