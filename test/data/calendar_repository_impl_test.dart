import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/calendar_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/calendar_repository_impl.dart';
import 'package:alaya/domain/entities/calendar_event.dart';

void main() {
  late AlayaDatabase db;
  late CalendarRepositoryImpl repository;

  const anchor = DateKey(20260810);
  const before = DateKey(20260801);
  const after = DateKey(20260831);
  const outside = DateKey(20261115);
  const stamp = 1786000000000;

  setUp(() async {
    db = AlayaDatabase(NativeDatabase.memory());
    repository = CalendarRepositoryImpl(CalendarDao(db));

    // Foreign keys are enforced from `beforeOpen` (Phase 1C), so the referenced rows come first.
    await db
        .into(db.currencies)
        .insert(
          CurrenciesCompanion.insert(
            code: 'INR',
            name: 'Indian Rupee',
            symbol: '₹',
            decimalDigits: 2,
            isEnabled: true,
            sortOrder: 0,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'ac-1',
            name: 'Everyday',
            normalizedName: 'everyday',
            kind: AccountKind.bank,
            currencyCode: 'INR',
            openingBalanceMinor: 0,
            openingBalanceDateKey: before,
            isArchived: false,
            includeInNetWorth: true,
            sortOrder: 0,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    await db
        .into(db.units)
        .insert(
          UnitsCompanion.insert(
            code: 'pc',
            category: UnitCategory.count,
            factorToBaseMilli: 1000,
            displayName: 'piece',
            isSystem: true,
            sortOrder: 0,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
  });

  tearDown(() => db.close());

  /// Seeds one row per `UNION ALL` arm, all on [anchor].
  Future<void> seedEveryArm({DateKey on = anchor}) async {
    await db
        .into(db.payees)
        .insert(
          PayeesCompanion.insert(
            id: 'pay-1',
            name: 'Corner Shop',
            normalizedName: 'corner shop',
            kind: PayeeKind.merchant,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: 'tx-1',
            kind: TransactionKind.withdrawal,
            subtype: TransactionSubtype.grocery,
            occurredAt: stamp,
            dateKey: on,
            monthKey: on.monthKey,
            originalAmountMinor: 45900,
            originalCurrencyCode: 'INR',
            needsReview: false,
            createdAt: stamp,
            updatedAt: stamp,
            payeeId: const Value('pay-1'),
            // `transactions` carries a CHECK constraint the companion's required-field list does not
            // mention: a withdrawal must name `from_account_id` and leave `to_account_id` null. Reading
            // the generated companion tells you what is NOT NULL; it does not tell you what the table
            // considers a coherent row. Eleven tests failed on the same insert for want of this line.
            fromAccountId: const Value('ac-1'),
          ),
        );

    await db
        .into(db.items)
        .insert(
          ItemsCompanion.insert(
            id: 'it-1',
            name: 'Yoghurt',
            normalizedName: 'yoghurt',
            unitCategory: UnitCategory.count,
            defaultDisplayUnitCode: 'pc',
            itemKind: ItemKind.food,
            isFavorite: false,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    await db
        .into(db.inventoryBatches)
        .insert(
          InventoryBatchesCompanion.insert(
            id: 'ba-1',
            itemId: 'it-1',
            initialQuantityMilli: 4000,
            remainingQuantityMilli: 4000,
            unitCodeAtPurchase: 'pc',
            purchasedDateKey: before,
            origin: BatchOrigin.purchase,
            createdAt: stamp,
            updatedAt: stamp,
            expiryDateKey: Value(on),
          ),
        );

    // One asset feeds two arms: warrantyEnd, and the asset-sourced half of serviceDue.
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'as-1',
            name: 'Boiler',
            normalizedName: 'boiler',
            type: AssetType.appliance,
            status: AssetStatus.active,
            createdAt: stamp,
            updatedAt: stamp,
            warrantyEndDateKey: Value(on),
            nextServiceDueDateKey: Value(on),
          ),
        );
    await db
        .into(db.serviceRecords)
        .insert(
          ServiceRecordsCompanion.insert(
            id: 'sr-1',
            assetId: 'as-1',
            serviceDateKey: before,
            type: ServiceRecordType.service,
            createdAt: stamp,
            updatedAt: stamp,
            nextDueDateKey: Value(on),
          ),
        );

    await db
        .into(db.recurringTemplates)
        .insert(
          RecurringTemplatesCompanion.insert(
            id: 'rt-1',
            name: 'Broadband',
            normalizedName: 'broadband',
            kind: RecurringKind.bill,
            direction: RecurringDirection.outflow,
            defaultAmountMinor: 89900,
            currencyCode: 'INR',
            intervalUnit: RecurringIntervalUnit.month,
            intervalCount: 1,
            startDateKey: before,
            nextDueDateKey: on,
            isPaused: false,
            autoRemind: false,
            remindDaysBefore: 0,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    await db
        .into(db.recurringOccurrences)
        .insert(
          RecurringOccurrencesCompanion.insert(
            id: 'ro-1',
            templateId: 'rt-1',
            dueDateKey: on,
            status: RecurringOccurrenceStatus.due,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );

    await db
        .into(db.shoppingLists)
        .insert(
          ShoppingListsCompanion.insert(
            id: 'sl-1',
            name: 'Weekly shop',
            isDefault: false,
            isArchived: false,
            createdAt: stamp,
            updatedAt: stamp,
            targetDateKey: Value(on),
          ),
        );
  }

  /// Adds one row well outside the tested range, so a range assertion can fail.
  Future<void> seedOutside() => db
      .into(db.shoppingLists)
      .insert(
        ShoppingListsCompanion.insert(
          id: 'sl-far',
          name: 'November',
          isDefault: false,
          isArchived: false,
          createdAt: stamp,
          updatedAt: stamp,
          targetDateKey: const Value(outside),
        ),
      );

  group('CalendarRepositoryImpl', () {
    // The point of the view, and the one thing no fake can prove: seven arms, six event types, and the
    // two serviceDue sources both arriving.
    test('every UNION arm reaches the feed', () async {
      await seedEveryArm();

      final events = await repository.forDay(anchor);

      expect(events, hasLength(7));
      expect(
        events.map((e) => e.type).toSet(),
        CalendarEventType.values.toSet(),
      );
      expect(
        events
            .where((e) => e.type == CalendarEventType.serviceDue)
            .map((e) => e.refType)
            .toSet(),
        {'asset', 'serviceRecord'},
      );
    });

    test('event_type and severity decode by enum name (Law L11)', () async {
      await seedEveryArm();

      final events = await repository.forDay(anchor);
      final byType = {for (final e in events) e.type: e};

      expect(
        byType[CalendarEventType.transaction]!.baseSeverity,
        CalendarSeverity.info,
      );
      expect(
        byType[CalendarEventType.shoppingTarget]!.baseSeverity,
        CalendarSeverity.info,
      );
      expect(
        byType[CalendarEventType.recurringDue]!.baseSeverity,
        CalendarSeverity.warning,
      );
      expect(
        byType[CalendarEventType.batchExpiry]!.baseSeverity,
        CalendarSeverity.warning,
      );
      expect(
        byType[CalendarEventType.warrantyEnd]!.baseSeverity,
        CalendarSeverity.warning,
      );
    });

    test(
      'an amount arrives as Money where the arm has one, and null where it does not',
      () async {
        await seedEveryArm();

        final events = await repository.forDay(anchor);
        final byType = {for (final e in events) e.type: e};

        expect(
          byType[CalendarEventType.transaction]!.amount,
          const Money(45900, 'INR'),
        );
        expect(
          byType[CalendarEventType.recurringDue]!.amount,
          const Money(89900, 'INR'),
        );
        // Expiries and warranties have no money attached, and a zero would read as free rather than absent.
        expect(byType[CalendarEventType.batchExpiry]!.amount, isNull);
        expect(byType[CalendarEventType.warrantyEnd]!.amount, isNull);
      },
    );

    test(
      'the transaction title falls back through the view COALESCE chain',
      () async {
        await seedEveryArm();

        final events = await repository.forDay(anchor);
        final transaction = events.firstWhere(
          (e) => e.type == CalendarEventType.transaction,
        );

        // The payee is joined, so its name wins over the note and the subtype.
        expect(transaction.title, 'Corner Shop');
        expect(transaction.title, isNotEmpty);
      },
    );

    test('a range excludes what falls outside it', () async {
      await seedEveryArm();
      await seedOutside();

      final events = await repository.watchRange(from: before, to: after).first;

      expect(events, hasLength(7));
      expect(events.every((e) => e.dateKey == anchor), isTrue);
    });

    test('countsByDate groups per day, not per row', () async {
      await seedEveryArm();

      final counts = await repository.countsByDate(from: before, to: after);

      expect(counts, {anchor: 7});
    });

    test('an empty range is empty rather than an error', () async {
      final events = await repository.watchRange(from: before, to: after).first;

      expect(events, isEmpty);
      expect(await repository.countsByDate(from: before, to: after), isEmpty);
    });

    test('a soft-deleted transaction leaves the feed', () async {
      await seedEveryArm();
      await db.customStatement(
        'UPDATE transactions SET deleted_at = ? WHERE id = ?',
        [stamp, 'tx-1'],
      );

      final events = await repository.forDay(anchor);

      expect(events, hasLength(6));
      expect(
        events.any((e) => e.type == CalendarEventType.transaction),
        isFalse,
      );
    });

    test('a fully consumed batch leaves the feed', () async {
      await seedEveryArm();
      await db.customStatement(
        'UPDATE inventory_batches SET remaining_quantity_milli = 0 WHERE id = ?',
        ['ba-1'],
      );

      final events = await repository.forDay(anchor);

      expect(
        events.any((e) => e.type == CalendarEventType.batchExpiry),
        isFalse,
      );
    });

    test(
      'a paid occurrence leaves the feed — only due rows are calendar entries',
      () async {
        await seedEveryArm();
        await db.customStatement(
          "UPDATE recurring_occurrences SET status = 'paid' WHERE id = ?",
          ['ro-1'],
        );

        final events = await repository.forDay(anchor);

        expect(
          events.any((e) => e.type == CalendarEventType.recurringDue),
          isFalse,
        );
      },
    );

    test('an archived shopping list leaves the feed', () async {
      await seedEveryArm();
      await db.customStatement(
        'UPDATE shopping_lists SET is_archived = 1 WHERE id = ?',
        ['sl-1'],
      );

      final events = await repository.forDay(anchor);

      expect(
        events.any((e) => e.type == CalendarEventType.shoppingTarget),
        isFalse,
      );
    });

    test('a disposed asset takes both of its arms with it', () async {
      await seedEveryArm();
      await db.customStatement(
        "UPDATE assets SET status = 'disposed' WHERE id = ?",
        ['as-1'],
      );

      final events = await repository.forDay(anchor);

      expect(
        events.any((e) => e.type == CalendarEventType.warrantyEnd),
        isFalse,
      );
      // The service record's own arm has no status filter, so it survives its asset's disposal.
      expect(
        events
            .where((e) => e.type == CalendarEventType.serviceDue)
            .map((e) => e.refType),
        ['serviceRecord'],
      );
    });
  });
}
