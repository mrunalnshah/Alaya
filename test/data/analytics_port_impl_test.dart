// Per ARCH_1 §7.6: drift is imported with an explicit `show` clause, never bare alongside
// `flutter_test`. Both declare `isNull`/`isNotNull`, and a bare import makes the collision surface at
// `expect(x, isNull)` with an error that says nothing about the import.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/analytics_port_impl.dart';

/// `AnalyticsPortImpl` against real SQLite.
///
/// **Not against a fake, and that is the point.** Every defect this file exists to catch lives in the
/// SQL: a unit factor that is joined or not, a reversed movement that is excluded or not, a `strftime`
/// expression that maps Sunday to 7 or to 0. A fake would have agreed with whatever the adapter did.
void main() {
  late AlayaDatabase db;
  late AnalyticsPortImpl port;

  // A Monday, verified against the calendar rather than assumed — the weekday-bucket test is
  // meaningless if the anchor's own weekday is guessed.
  const monday = DateKey(20260810);
  const sunday = DateKey(20260816);
  const window = (from: DateKey(20260801), to: DateKey(20260831));
  const stamp = 1786000000000;

  setUp(() async {
    db = AlayaDatabase(NativeDatabase.memory());
    port = AnalyticsPortImpl(db, FixedClock(DateTime.utc(2026, 8, 10)));

    // Foreign keys are enforced from `beforeOpen` (Phase 1C), so referenced rows come first.
    for (final currency in [
      ('INR', '₹', 2),
      ('JPY', '¥', 0),
    ]) {
      await db
          .into(db.currencies)
          .insert(
            CurrenciesCompanion.insert(
              code: currency.$1,
              name: currency.$1,
              symbol: currency.$2,
              decimalDigits: currency.$3,
              isEnabled: true,
              sortOrder: 0,
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
    }
    // `factorToBaseMilli` is the base unit times 1000 (ARCH_1 §4.2): a gram is 1,000 and a kilogram is
    // 1,000,000. Those two numbers are the whole of ARCH_4 R18.
    for (final unit in [
      ('g', UnitCategory.weight, 1000),
      ('kg', UnitCategory.weight, 1000000),
      ('pc', UnitCategory.count, 1000),
    ]) {
      await db
          .into(db.units)
          .insert(
            UnitsCompanion.insert(
              code: unit.$1,
              category: unit.$2,
              factorToBaseMilli: unit.$3,
              displayName: unit.$1,
              isSystem: true,
              sortOrder: 0,
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
    }
    for (final account in [('ac-1', 'INR'), ('ac-2', 'INR')]) {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: account.$1,
              name: account.$1,
              normalizedName: account.$1,
              kind: AccountKind.bank,
              currencyCode: account.$2,
              openingBalanceMinor: 100000,
              openingBalanceDateKey: const DateKey(20260101),
              isArchived: false,
              includeInNetWorth: true,
              sortOrder: 0,
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
    }
    await db
        .into(db.items)
        .insert(
          ItemsCompanion.insert(
            id: 'it-1',
            name: 'Potatoes',
            normalizedName: 'potatoes',
            unitCategory: UnitCategory.weight,
            defaultDisplayUnitCode: 'kg',
            isFavorite: false,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
  });

  tearDown(() => db.close());

  Future<void> insertWithdrawal({
    required String id,
    required int minor,
    String currencyCode = 'INR',
    DateKey on = monday,
    TransactionSubtype subtype = TransactionSubtype.grocery,
    String? recurringTemplateId,
  }) {
    return db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: id,
            kind: TransactionKind.withdrawal,
            subtype: subtype,
            occurredAt: stamp,
            dateKey: on,
            monthKey: on.monthKey,
            originalAmountMinor: minor,
            originalCurrencyCode: currencyCode,
            needsReview: false,
            createdAt: stamp,
            updatedAt: stamp,
            // The shape CHECK on `transactions` requires a withdrawal to name `from_account_id` and
            // leave `to_account_id` null. The generated companion says what is NOT NULL; it does not
            // say what the table considers coherent.
            fromAccountId: const Value('ac-1'),
            recurringTemplateId: Value(recurringTemplateId),
          ),
        );
  }

  Future<void> insertBatch({
    required String id,
    required int remainingMilli,
    required String unitCode,
    int? unitCostMinor,
    String? costCurrencyCode,
    bool deleted = false,
  }) {
    return db
        .into(db.inventoryBatches)
        .insert(
          InventoryBatchesCompanion.insert(
            id: id,
            itemId: 'it-1',
            initialQuantityMilli: remainingMilli,
            remainingQuantityMilli: remainingMilli,
            unitCodeAtPurchase: unitCode,
            purchasedDateKey: monday,
            origin: BatchOrigin.purchase,
            createdAt: stamp,
            updatedAt: stamp,
            unitCostMinor: Value(unitCostMinor),
            costCurrencyCode: Value(costCurrencyCode),
            deletedAt: Value(deleted ? stamp : null),
          ),
        );
  }

  group('query 13 — the R18 arithmetic', () {
    test('a 2 kg batch at ₹50 per kg is worth ₹100, not ₹100,000', () async {
      await insertBatch(
        id: 'ba-kg',
        // 2 kg, in base-milli: 2 x 1000 g x 1000.
        remainingMilli: 2000000,
        unitCode: 'kg',
        unitCostMinor: 5000,
        costCurrencyCode: 'INR',
      );

      final rows = await port.valuedBatches();
      expect(rows, hasLength(1));
      expect(
        rows.single.unitFactorToBaseMilli,
        1000000,
        reason:
            'the kg factor must come from the units join, not from a constant',
      );

      // The service's formula, asserted on a specific figure rather than on a shape. This is the exact
      // computation Phase 4C got wrong, and the reason a spot check could not find it: dividing by
      // 1000 instead of the factor gives 10,000,000 minor — ₹100,000 for two kilos of potatoes.
      final value =
          (rows.single.unitCostMinor *
                  rows.single.remainingMilli /
                  rows.single.unitFactorToBaseMilli)
              .truncate();
      expect(value, 10000, reason: '₹100.00 in paise');
      expect(
        (rows.single.unitCostMinor * rows.single.remainingMilli / 1000)
            .truncate(),
        10000000,
        reason:
            'the wrong formula, kept here so the difference is visible rather than argued about',
      );
    });

    test(
      'the same batch priced per gram values identically, which is why the bug hid',
      () async {
        // The same 2 kg recorded in grams at **5 paise per gram** — 2000 g x 5 = 10,000 paise = ₹100,
        // the identical batch value. Dividing by 1000 is *correct* here, which is how the defect survived
        // a written audit: a spot check of this row confirms the wrong formula.
        await insertBatch(
          id: 'ba-g',
          remainingMilli: 2000000,
          unitCode: 'g',
          unitCostMinor: 5,
          costCurrencyCode: 'INR',
        );
        final row = (await port.valuedBatches()).single;
        expect(row.unitFactorToBaseMilli, 1000);
        final correct =
            (row.unitCostMinor * row.remainingMilli / row.unitFactorToBaseMilli)
                .truncate();
        final naive = (row.unitCostMinor * row.remainingMilli / 1000)
            .truncate();
        expect(correct, 10000);
        expect(
          naive,
          correct,
          reason: 'identical for a gram-denominated purchase — the trap',
        );
      },
    );

    test('a soft-deleted unit still values its batch', () async {
      await insertBatch(
        id: 'ba-kg',
        remainingMilli: 1000000,
        unitCode: 'kg',
        unitCostMinor: 5000,
        costCurrencyCode: 'INR',
      );
      await db.customStatement(
        'UPDATE units SET deleted_at = ? WHERE code = ?',
        [stamp, 'kg'],
      );
      // Filtering `units.deleted_at` would drop every batch bought in a retired unit from the
      // valuation while the figure still looked complete — R18's failure mode from the other side.
      expect(await port.valuedBatches(), hasLength(1));
    });

    test('valued and uncosted batches are exact complements', () async {
      await insertBatch(
        id: 'ba-priced',
        remainingMilli: 1000000,
        unitCode: 'kg',
        unitCostMinor: 5000,
        costCurrencyCode: 'INR',
      );
      await insertBatch(
        id: 'ba-no-cost',
        remainingMilli: 500000,
        unitCode: 'kg',
      );
      await insertBatch(
        id: 'ba-deleted',
        remainingMilli: 500000,
        unitCode: 'kg',
        unitCostMinor: 5000,
        costCurrencyCode: 'INR',
        deleted: true,
      );

      expect(await port.valuedBatches(), hasLength(1));
      expect(
        await port.batchesWithoutCost(),
        1,
        reason:
            'the uncosted one only — the soft-deleted batch is in neither set',
      );
    });
  });

  group('query 14 — waste', () {
    Future<void> insertMovement({
      required String id,
      required StockMovementKind kind,
      required int quantityMilli,
      String? reverses,
    }) {
      return db
          .into(db.stockMovements)
          .insert(
            StockMovementsCompanion.insert(
              id: id,
              batchId: 'ba-1',
              itemId: 'it-1',
              kind: kind,
              quantityMilli: quantityMilli,
              occurredAt: stamp,
              dateKey: monday,
              createdAt: stamp,
              updatedAt: stamp,
              reversesMovementId: Value(reverses),
            ),
          );
    }

    setUp(() async {
      await insertBatch(
        id: 'ba-1',
        remainingMilli: 2000000,
        unitCode: 'kg',
        unitCostMinor: 5000,
        costCurrencyCode: 'INR',
      );
    });

    test('carries the batch cost and its purchase-unit factor', () async {
      await insertMovement(
        id: 'mv-1',
        kind: StockMovementKind.waste,
        quantityMilli: 500000,
      );
      final row = (await port.wasteMovements(window)).single;
      expect(row.unitCostMinor, 5000);
      expect(row.unitFactorToBaseMilli, 1000000);
      // Half a kilo at ₹50/kg is ₹25 — the same per-purchase-unit rule as query 13.
      expect(
        (row.unitCostMinor! * row.milliBase / row.unitFactorToBaseMilli!)
            .truncate(),
        2500,
      );
    });

    test('a reversed waste movement is excluded', () async {
      await insertMovement(
        id: 'mv-1',
        kind: StockMovementKind.waste,
        quantityMilli: 500000,
      );
      expect(await port.wasteMovements(window), hasLength(1));

      // Undo writes a reversing row rather than deleting the original (ARCH_2 §5.3), so counting the
      // original would report waste the user already corrected.
      await insertMovement(
        id: 'mv-2',
        kind: StockMovementKind.adjustIn,
        quantityMilli: 500000,
        reverses: 'mv-1',
      );
      expect(await port.wasteMovements(window), isEmpty);
    });

    test('expired counts as waste and consume does not', () async {
      await insertMovement(
        id: 'mv-exp',
        kind: StockMovementKind.expired,
        quantityMilli: 100000,
      );
      await insertMovement(
        id: 'mv-eat',
        kind: StockMovementKind.consume,
        quantityMilli: 100000,
      );
      expect(await port.wasteMovements(window), hasLength(1));
    });
  });

  group('query 11 — the dearest purchase', () {
    Future<void> insertLine({
      required String id,
      required String transactionId,
      required String unitCode,
      required int unitPriceMinor,
    }) {
      return db
          .into(db.transactionLines)
          .insert(
            TransactionLinesCompanion.insert(
              id: id,
              transactionId: transactionId,
              lineNo: 1,
              description: 'Potatoes',
              destination: TransactionLineDestination.none,
              createdAt: stamp,
              updatedAt: stamp,
              itemId: const Value('it-1'),
              unitCode: Value(unitCode),
              unitPriceMinor: Value(unitPriceMinor),
              quantityMilli: const Value(1000000),
              lineAmountMinor: const Value(5000),
            ),
          );
    }

    test('ranks by price per base unit, not by the recorded number', () async {
      await insertWithdrawal(id: 'tx-kg', minor: 5000);
      await insertWithdrawal(id: 'tx-g', minor: 100);
      // ₹50 per kilogram normalises to 5 paise per gram.
      await insertLine(
        id: 'ln-kg',
        transactionId: 'tx-kg',
        unitCode: 'kg',
        unitPriceMinor: 5000,
      );
      // ₹1 per gram normalises to 100 paise per gram — twenty times dearer, and twenty times *smaller*
      // as a recorded figure. Ordering by `unit_price_minor` alone picks the kilogram line.
      await insertLine(
        id: 'ln-g',
        transactionId: 'tx-g',
        unitCode: 'g',
        unitPriceMinor: 100,
      );

      final row = await port.dearestPurchase('it-1', window);
      expect(row!.transactionId, 'tx-g');
      expect(
        row.unitPriceMinor,
        100,
        reason:
            'the figure returned is the recorded one, in the unit it was bought in',
      );
    });
  });

  group('currency is never summed away', () {
    test('spend by subtype groups by currency', () async {
      await insertWithdrawal(id: 'tx-inr', minor: 100000);
      await insertWithdrawal(id: 'tx-jpy', minor: 999999, currencyCode: 'JPY');

      final rows = await port.spendBySubtype(window);
      expect(rows, hasLength(2));
      expect(rows.map((r) => r.currencyCode).toSet(), {'INR', 'JPY'});
      // A SQL-side SUM across currencies would have destroyed the information `AnalyticsService` needs
      // to convert per data point, and produced one meaningless figure of 1,099,999.
      expect(
        rows.every((r) => r.key == TransactionSubtype.grocery.name),
        isTrue,
      );
    });

    test('a transfer nets to zero in net flow', () async {
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'tx-move',
              kind: TransactionKind.transfer,
              subtype: TransactionSubtype.transferSelf,
              occurredAt: stamp,
              dateKey: monday,
              monthKey: monday.monthKey,
              originalAmountMinor: 250000,
              originalCurrencyCode: 'INR',
              needsReview: false,
              createdAt: stamp,
              updatedAt: stamp,
              fromAccountId: const Value('ac-1'),
              toAccountId: const Value('ac-2'),
            ),
          );

      final rows = await port.netFlowByMonth(window);
      // `v_account_ledger` expands a transfer into two signed legs, so this is zero by construction
      // rather than by the query knowing anything about transfers (ARCH_2 §12.1).
      expect(rows.fold<int>(0, (sum, r) => sum + r.amountMinor), 0);
    });
  });

  group('query 7 — the carried leg', () {
    test(
      'a window that starts mid-history opens with the balance carried into it',
      () async {
        await insertWithdrawal(
          id: 'tx-old',
          minor: 30000,
          on: const DateKey(20260715),
        );
        await insertWithdrawal(id: 'tx-in', minor: 10000);

        final legs = await port.ledgerLegsForAccount('ac-1', window);
        expect(
          legs,
          hasLength(2),
          reason: 'one carried leg plus the one inside the window',
        );
        expect(legs.first.dateKey, window.from.value);
        expect(
          legs.first.amountMinor,
          -30000,
          reason: 'the pre-window withdrawal, condensed',
        );
        expect(
          legs.first.count,
          1,
          reason: 'how many legs the carried row stands for',
        );
        expect(legs.last.amountMinor, -10000);
      },
    );

    test(
      'an account whose history starts inside the window carries nothing',
      () async {
        await insertWithdrawal(id: 'tx-in', minor: 10000);
        final legs = await port.ledgerLegsForAccount('ac-1', window);
        expect(legs, hasLength(1));
        expect(legs.single.dateKey, monday.value);
      },
    );
  });

  group('query 21 — the weekday bucket', () {
    test('Monday is 1 and Sunday is 7', () async {
      await insertWithdrawal(id: 'tx-mon', minor: 10000);
      await insertWithdrawal(id: 'tx-sun', minor: 20000, on: sunday);

      final rows = await port.spendByBucket(window, byWeekday: true);
      final byBucket = {for (final row in rows) row.bucket: row.amountMinor};
      // SQLite's `strftime('%w')` returns 0 for Sunday; ARCH_3 §5.1 wants 1-7 Monday first. If the
      // `(w + 6) % 7 + 1` mapping were wrong this would put Monday on 2 and Sunday on 1.
      expect(byBucket[1], 10000);
      expect(byBucket[7], 20000);
    });

    test('day of month buckets by the date itself', () async {
      await insertWithdrawal(id: 'tx-10', minor: 10000);
      final rows = await port.spendByBucket(window, byWeekday: false);
      expect(rows.single.bucket, 10);
    });
  });

  group('query 17 — commitments', () {
    Future<void> insertTemplate({
      required String id,
      required RecurringDirection direction,
      bool isPaused = false,
      DateKey? endDateKey,
    }) {
      return db
          .into(db.recurringTemplates)
          .insert(
            RecurringTemplatesCompanion.insert(
              id: id,
              name: id,
              normalizedName: id,
              kind: RecurringKind.bill,
              direction: direction,
              defaultAmountMinor: 64900,
              currencyCode: 'INR',
              intervalUnit: RecurringIntervalUnit.month,
              intervalCount: 1,
              startDateKey: const DateKey(20260101),
              nextDueDateKey: monday,
              isPaused: isPaused,
              autoRemind: false,
              remindDaysBefore: 0,
              createdAt: stamp,
              updatedAt: stamp,
              endDateKey: Value(endDateKey),
            ),
          );
    }

    test(
      'counts active outflows and excludes paused, inflow and ended ones',
      () async {
        await insertTemplate(
          id: 'rt-live',
          direction: RecurringDirection.outflow,
        );
        await insertTemplate(
          id: 'rt-paused',
          direction: RecurringDirection.outflow,
          isPaused: true,
        );
        await insertTemplate(
          id: 'rt-salary',
          direction: RecurringDirection.inflow,
        );
        await insertTemplate(
          id: 'rt-ended',
          direction: RecurringDirection.outflow,
          endDateKey: const DateKey(20260601),
        );

        final rows = await port.activeCommitments();
        expect(rows, hasLength(1));
        expect(rows.single.defaultAmountMinor, 64900);
      },
    );

    test('a template with two outstanding occurrences is counted once', () async {
      await insertTemplate(
        id: 'rt-live',
        direction: RecurringDirection.outflow,
      );
      for (final due in [const DateKey(20260810), const DateKey(20260910)]) {
        await db
            .into(db.recurringOccurrences)
            .insert(
              RecurringOccurrencesCompanion.insert(
                id: 'oc-${due.value}',
                templateId: 'rt-live',
                dueDateKey: due,
                status: RecurringOccurrenceStatus.due,
                createdAt: stamp,
                updatedAt: stamp,
              ),
            );
      }
      // This is why the query reads `recurring_templates` and not `v_recurring_due`: that view LEFT
      // JOINs occurrences, so this template would appear twice and its ₹649 would be counted twice.
      expect(await port.activeCommitments(), hasLength(1));
    });
  });

  group('soft deletes are respected everywhere', () {
    test('a deleted transaction leaves every money query', () async {
      await insertWithdrawal(id: 'tx-1', minor: 10000);
      expect(await port.spendBySubtype(window), hasLength(1));

      await db.customStatement(
        'UPDATE transactions SET deleted_at = ? WHERE id = ?',
        [stamp, 'tx-1'],
      );
      // Reading `v_active_transactions` rather than the base table is what makes this impossible to
      // forget (Law L7).
      expect(await port.spendBySubtype(window), isEmpty);
      expect(await port.totalSpend(window), isEmpty);
      expect(await port.spendByBucket(window, byWeekday: true), isEmpty);
    });
  });
}
