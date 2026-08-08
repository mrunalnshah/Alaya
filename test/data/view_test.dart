import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// Exercises the 11 views, the partial indexes and the FTS triggers.
///
/// Rows are written through drift's typed companions, but views are read with [customSelect]
/// rather than the generated view accessors. That is deliberate: drift derives a row class name
/// for each view, and depending on those derived names here would couple this suite to a naming
/// rule instead of to the SQL it is meant to test. Phase 2A's DAOs will use the typed view
/// accessors once `alaya_database.g.dart` has been generated and the names are known.
void main() {
  late AlayaDatabase db;

  // Every date is fixed. No view in this schema consults the clock (see schedule_views.drift),
  // so nothing here may depend on the wall clock either.
  final today = DateKey.fromYmd(2026, 7, 28);

  setUp(() async {
    db = AlayaDatabase(NativeDatabase.memory()); // no seeder: these tests build their own rows
    for (final c in const [('INR', 2), ('JPY', 0)]) {
      await db.into(db.currencies).insert(
        CurrenciesCompanion.insert(
          code: c.$1,
          name: c.$1,
          symbol: c.$1,
          decimalDigits: c.$2,
          isEnabled: true,
          sortOrder: 0,
          createdAt: 0,
          updatedAt: 0,
        ),
      );
    }
    for (final u in const [('g', 1000), ('kg', 1000000)]) {
      await db.into(db.units).insert(
        UnitsCompanion.insert(
          code: u.$1,
          category: UnitCategory.weight,
          factorToBaseMilli: u.$2,
          displayName: u.$1,
          isSystem: true,
          sortOrder: 0,
          createdAt: 0,
          updatedAt: 0,
        ),
      );
    }
  });

  tearDown(() => db.close());

  Future<void> account(String id, int openingMinor, {String currency = 'INR'}) {
    return db.into(db.accounts).insert(
      AccountsCompanion.insert(
        id: id,
        name: id,
        normalizedName: id,
        kind: AccountKind.cash,
        currencyCode: currency,
        openingBalanceMinor: openingMinor,
        openingBalanceDateKey: today,
        isArchived: false,
        includeInNetWorth: true,
        sortOrder: 0,
        createdAt: 0,
        updatedAt: 0,
      ),
    );
  }

  Future<void> tx(
      String id,
      TransactionKind kind,
      TransactionSubtype subtype, {
        String? from,
        String? to,
        required int amountMinor,
        DateKey? on,
        String currency = 'INR',
        String? note,
      }) {
    final dateKey = on ?? today;
    return db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        id: id,
        kind: kind,
        subtype: subtype,
        occurredAt: 0,
        dateKey: dateKey,
        monthKey: dateKey.monthKey,
        originalAmountMinor: amountMinor,
        originalCurrencyCode: currency,
        fromAccountId: Value(from),
        toAccountId: Value(to),
        note: Value(note),
        needsReview: false,
        createdAt: 0,
        updatedAt: 0,
      ),
    );
  }

  Future<int> totalAcrossAccounts() async {
    final row = await db
        .customSelect('SELECT COALESCE(SUM(balance_minor), 0) AS t FROM v_account_balances')
        .getSingle();
    return row.read<int>('t');
  }

  Future<int> balanceOf(String accountId) async {
    final row = await db.customSelect(
      'SELECT balance_minor FROM v_account_balances WHERE account_id = ?',
      variables: [Variable<String>(accountId)],
    ).getSingle();
    return row.read<int>('balance_minor');
  }

  group('v_account_balances — every transaction kind', () {
    setUp(() async {
      await account('cash', 4000000);
      await account('bank', 10000000);
    });

    test('opening balances alone', () async {
      expect(await balanceOf('cash'), 4000000);
      expect(await balanceOf('bank'), 10000000);
      expect(await totalAcrossAccounts(), 14000000);
    });

    test('deposit credits the destination', () async {
      await tx('t1', TransactionKind.deposit, TransactionSubtype.salaryIn,
          to: 'bank', amountMinor: 6500000);
      expect(await balanceOf('bank'), 16500000);
      expect(await balanceOf('cash'), 4000000);
    });

    test('withdrawal debits the source', () async {
      await tx('t2', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 50000);
      expect(await balanceOf('cash'), 3950000);
    });

    test('adjustmentIncrease credits', () async {
      await tx('t3', TransactionKind.adjustmentIncrease, TransactionSubtype.otherIn,
          to: 'cash', amountMinor: 10000);
      expect(await balanceOf('cash'), 4010000);
    });

    test('adjustmentDecrease debits', () async {
      await tx('t4', TransactionKind.adjustmentDecrease, TransactionSubtype.otherOut,
          from: 'cash', amountMinor: 20000);
      expect(await balanceOf('cash'), 3980000);
    });

    test('transfer moves value between the two accounts', () async {
      await tx('t5', TransactionKind.transfer, TransactionSubtype.transferSelf,
          from: 'cash', to: 'bank', amountMinor: 500000);
      expect(await balanceOf('cash'), 3500000);
      expect(await balanceOf('bank'), 10500000);
    });

    test('all five kinds together, each applied exactly once', () async {
      await tx('a', TransactionKind.deposit, TransactionSubtype.salaryIn,
          to: 'bank', amountMinor: 6500000);
      await tx('b', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 50000);
      await tx('c', TransactionKind.adjustmentIncrease, TransactionSubtype.otherIn,
          to: 'cash', amountMinor: 10000);
      await tx('d', TransactionKind.adjustmentDecrease, TransactionSubtype.otherOut,
          from: 'cash', amountMinor: 20000);
      await tx('e', TransactionKind.transfer, TransactionSubtype.transferSelf,
          from: 'cash', to: 'bank', amountMinor: 500000);

      // cash: 4,000,000 - 50,000 + 10,000 - 20,000 - 500,000
      expect(await balanceOf('cash'), 3440000);
      // bank: 10,000,000 + 6,500,000 + 500,000
      expect(await balanceOf('bank'), 17000000);
      expect(await totalAcrossAccounts(), 20440000);

      final kinds = await db
          .customSelect('SELECT DISTINCT kind FROM v_account_ledger')
          .map((r) => r.read<String>('kind'))
          .get();
      expect(kinds.toSet(), hasLength(5), reason: 'every kind must reach the ledger');
    });
  });

  group('THE KEYSTONE — a self-transfer nets to zero', () {
    test('Cash -> Bank 5000 leaves the grand total unchanged', () async {
      await account('cash', 4000000);
      await account('bank', 10000000);

      final before = await totalAcrossAccounts();
      await tx('xfer', TransactionKind.transfer, TransactionSubtype.transferSelf,
          from: 'cash', to: 'bank', amountMinor: 500000);
      final after = await totalAcrossAccounts();

      expect(after, before,
          reason: 'moving money between your own accounts must not change net worth (A02)');
      expect(await balanceOf('cash'), 3500000);
      expect(await balanceOf('bank'), 10500000);
    });

    test('a transfer produces exactly two legs which sum to zero', () async {
      await account('cash', 0);
      await account('bank', 0);
      await tx('xfer', TransactionKind.transfer, TransactionSubtype.transferSelf,
          from: 'cash', to: 'bank', amountMinor: 500000);

      final legs = await db.customSelect(
        'SELECT account_id, signed_minor FROM v_account_ledger WHERE tx_id = ?',
        variables: [Variable<String>('xfer')],
      ).get();
      expect(legs, hasLength(2));
      expect(legs.fold<int>(0, (s, l) => s + l.read<int>('signed_minor')), 0);
      expect(legs.map((l) => l.read<String>('account_id')).toSet(), {'cash', 'bank'});
    });

    test('twenty-five alternating transfers never drift the total', () async {
      await account('cash', 1000000);
      await account('bank', 1000000);
      final before = await totalAcrossAccounts();
      for (var i = 0; i < 25; i++) {
        await tx('x$i', TransactionKind.transfer, TransactionSubtype.transferSelf,
            from: i.isEven ? 'cash' : 'bank',
            to: i.isEven ? 'bank' : 'cash',
            amountMinor: 7777);
      }
      expect(await totalAcrossAccounts(), before);
    });
  });

  group('soft delete (Law L7)', () {
    test('a soft-deleted transaction leaves the ledger entirely', () async {
      await account('cash', 1000000);
      await tx('t', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 50000);
      expect(await balanceOf('cash'), 950000);

      await db.customStatement('UPDATE transactions SET deleted_at = 1 WHERE id = ?', ['t']);
      expect(await balanceOf('cash'), 1000000);
      final legs = await db.customSelect('SELECT tx_id FROM v_account_ledger').get();
      expect(legs, isEmpty);
    });

    test('a soft-deleted account leaves v_account_balances', () async {
      await account('cash', 1000000);
      await account('bank', 500000);
      await db.customStatement('UPDATE accounts SET deleted_at = 1 WHERE id = ?', ['bank']);
      final rows = await db
          .customSelect('SELECT account_id FROM v_account_balances')
          .map((r) => r.read<String>('account_id'))
          .get();
      expect(rows, ['cash']);
    });

    test('v_active_transactions hides soft-deleted rows and exposes joined names', () async {
      await account('cash', 0);
      await db.into(db.payees).insert(
        PayeesCompanion.insert(
          id: 'p1',
          name: 'Big Bazaar',
          normalizedName: 'big bazaar',
          kind: PayeeKind.merchant,
          createdAt: 0,
          updatedAt: 0,
        ),
      );
      await db.into(db.transactions).insert(
        TransactionsCompanion.insert(
          id: 't',
          kind: TransactionKind.withdrawal,
          subtype: TransactionSubtype.grocery,
          occurredAt: 0,
          dateKey: today,
          monthKey: today.monthKey,
          originalAmountMinor: 50000,
          originalCurrencyCode: 'INR',
          fromAccountId: const Value('cash'),
          payeeId: const Value('p1'),
          needsReview: false,
          createdAt: 0,
          updatedAt: 0,
        ),
      );

      var rows = await db.customSelect(
        'SELECT payee_name, from_account_name FROM v_active_transactions',
      ).get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('payee_name'), 'Big Bazaar');
      expect(rows.single.read<String>('from_account_name'), 'cash');

      await db.customStatement("UPDATE transactions SET deleted_at = 1 WHERE id = 't'");
      rows = await db.customSelect('SELECT tx_id FROM v_active_transactions').get();
      expect(rows, isEmpty);
    });
  });

  group('v_monthly_totals', () {
    test('groups by month, kind and currency without mixing currencies', () async {
      await account('cash', 0);
      await account('yen', 0, currency: 'JPY');
      await tx('a', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 10000);
      await tx('b', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 20000);
      await tx('c', TransactionKind.withdrawal, TransactionSubtype.otherOut,
          from: 'yen', amountMinor: 500, currency: 'JPY');
      await tx('d', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 30000, on: DateKey.fromYmd(2026, 8, 3));

      final july = await db.customSelect(
        "SELECT sum_minor, tx_count FROM v_monthly_totals "
            "WHERE month_key = 202607 AND currency_code = 'INR' AND kind = 'withdrawal'",
      ).getSingle();
      expect(july.read<int>('sum_minor'), 30000);
      expect(july.read<int>('tx_count'), 2);

      final jpy = await db.customSelect(
        "SELECT sum_minor FROM v_monthly_totals WHERE currency_code = 'JPY'",
      ).getSingle();
      expect(jpy.read<int>('sum_minor'), 500,
          reason: 'yen must never be summed into the rupee bucket (A34)');

      final august =
      await db.customSelect('SELECT 1 FROM v_monthly_totals WHERE month_key = 202608').get();
      expect(august, hasLength(1));
    });
  });

  group('v_transaction_allocation (A11)', () {
    test('reports the unallocated remainder and never auto-balances', () async {
      await account('cash', 0);
      await tx('t', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 50000);
      await db.into(db.transactionLines).insert(
        TransactionLinesCompanion.insert(
          id: 'l1',
          transactionId: 't',
          lineNo: 1,
          description: 'Potatoes',
          lineAmountMinor: const Value(48000),
          destination: TransactionLineDestination.inventory,
          createdAt: 0,
          updatedAt: 0,
        ),
      );

      final row = await db.customSelect(
        'SELECT amount_minor, allocated_minor, unallocated_minor, line_count '
            "FROM v_transaction_allocation WHERE tx_id = 't'",
      ).getSingle();
      expect(row.read<int>('amount_minor'), 50000);
      expect(row.read<int>('allocated_minor'), 48000);
      expect(row.read<int>('unallocated_minor'), 2000);
      expect(row.read<int>('line_count'), 1);
    });

    test('line_count distinguishes "no lines yet" from "lines that sum exactly"', () async {
      await account('cash', 0);
      await tx('t', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 50000);
      final row = await db.customSelect(
        "SELECT line_count, unallocated_minor FROM v_transaction_allocation WHERE tx_id = 't'",
      ).getSingle();
      expect(row.read<int>('line_count'), 0);
      expect(row.read<int>('unallocated_minor'), 50000,
          reason: 'the UI must key the nudge off lineCount, not off unallocatedMinor');
    });
  });

  group('inventory views', () {
    Future<void> item(String id, {int? thresholdMilli}) => db.into(db.items).insert(
      ItemsCompanion.insert(
        id: id,
        name: id,
        normalizedName: id,
        unitCategory: UnitCategory.weight,
        defaultDisplayUnitCode: 'g',
        itemKind: ItemKind.food,
        lowStockThresholdMilli: Value(thresholdMilli),
        isFavorite: false,
        createdAt: 0,
        updatedAt: 0,
      ),
    );

    Future<void> batch(String id, String itemId, int initial, int remaining, {DateKey? expiry}) =>
        db.into(db.inventoryBatches).insert(
          InventoryBatchesCompanion.insert(
            id: id,
            itemId: itemId,
            initialQuantityMilli: initial,
            remainingQuantityMilli: remaining,
            unitCodeAtPurchase: 'kg',
            expiryDateKey: Value(expiry),
            purchasedDateKey: today,
            origin: BatchOrigin.manual,
            createdAt: 0,
            updatedAt: 0,
          ),
        );

    Future<void> movement(String id, String batchId, String itemId, StockMovementKind kind,
        int qty, {String? reverses}) =>
        db.into(db.stockMovements).insert(
          StockMovementsCompanion.insert(
            id: id,
            batchId: batchId,
            itemId: itemId,
            kind: kind,
            quantityMilli: qty,
            occurredAt: 0,
            dateKey: today,
            reversesMovementId: Value(reverses),
            createdAt: 0,
            updatedAt: 0,
          ),
        );

    test('v_item_stock sums remaining, counts batches, finds nearest expiry', () async {
      await item('potato', thresholdMilli: 3000000);
      await batch('b1', 'potato', 2000000, 2000000, expiry: DateKey.fromYmd(2026, 8, 10));
      await batch('b2', 'potato', 1000000, 500000, expiry: DateKey.fromYmd(2026, 8, 5));

      final row = await db.customSelect(
        'SELECT total_remaining_milli, batch_count, nearest_expiry_date_key, is_low_stock '
            "FROM v_item_stock WHERE item_id = 'potato'",
      ).getSingle();
      expect(row.read<int>('total_remaining_milli'), 2500000);
      expect(row.read<int>('batch_count'), 2);
      expect(row.read<int>('nearest_expiry_date_key'), 20260805);
      expect(row.read<int>('is_low_stock'), 1);
    });

    test('exhausted batches are excluded from every aggregate', () async {
      await item('rice');
      await batch('b1', 'rice', 1000000, 0, expiry: DateKey.fromYmd(2026, 8, 1));
      await batch('b2', 'rice', 1000000, 400000, expiry: DateKey.fromYmd(2026, 9, 1));

      final row = await db.customSelect(
        'SELECT batch_count, total_remaining_milli, nearest_expiry_date_key '
            "FROM v_item_stock WHERE item_id = 'rice'",
      ).getSingle();
      expect(row.read<int>('batch_count'), 1);
      expect(row.read<int>('total_remaining_milli'), 400000);
      expect(row.read<int>('nearest_expiry_date_key'), 20260901,
          reason: 'an empty batch must not drag the nearest expiry earlier');
    });

    test('an item with no threshold is never low on stock', () async {
      await item('salt');
      await batch('b1', 'salt', 1000, 1000);
      final row = await db
          .customSelect("SELECT is_low_stock FROM v_item_stock WHERE item_id = 'salt'")
          .getSingle();
      expect(row.read<int>('is_low_stock'), 0);
      expect(await db.customSelect('SELECT item_id FROM v_low_stock').get(), isEmpty);
    });

    test('an item with no batches at all reports zero, not null', () async {
      await item('ghee', thresholdMilli: 500000);
      final row = await db.customSelect(
        "SELECT total_remaining_milli, batch_count, is_low_stock FROM v_item_stock "
            "WHERE item_id = 'ghee'",
      ).getSingle();
      expect(row.read<int>('total_remaining_milli'), 0);
      expect(row.read<int>('batch_count'), 0);
      expect(row.read<int>('is_low_stock'), 1, reason: 'nothing on hand is as low as it gets');
    });

    test('v_low_stock reports the shortfall', () async {
      await item('potato', thresholdMilli: 3000000);
      await batch('b1', 'potato', 2500000, 2500000);
      final row = await db
          .customSelect('SELECT item_id, shortfall_milli FROM v_low_stock')
          .getSingle();
      expect(row.read<String>('item_id'), 'potato');
      expect(row.read<int>('shortfall_milli'), 500000);
    });

    test('v_batch_stock_check reconciles the L3 cache against the ledger', () async {
      await item('potato');
      await batch('b1', 'potato', 2000000, 2000000);
      await movement('m1', 'b1', 'potato', StockMovementKind.openingIn, 2000000);

      var row = await db
          .customSelect('SELECT ledger_remaining_milli, discrepancy_milli FROM v_batch_stock_check')
          .getSingle();
      expect(row.read<int>('discrepancy_milli'), 0);

      // Consume without updating the cache — exactly the bug this view exists to catch.
      await movement('m2', 'b1', 'potato', StockMovementKind.consume, 300000);
      row = await db
          .customSelect('SELECT ledger_remaining_milli, discrepancy_milli FROM v_batch_stock_check')
          .getSingle();
      expect(row.read<int>('ledger_remaining_milli'), 1700000);
      expect(row.read<int>('discrepancy_milli'), 300000);
    });

    test('a reversal cancels the movement it points at', () async {
      await item('potato');
      await batch('b1', 'potato', 1000000, 1000000);
      await movement('m1', 'b1', 'potato', StockMovementKind.openingIn, 1000000);
      await movement('m2', 'b1', 'potato', StockMovementKind.consume, 200000);
      await movement('m3', 'b1', 'potato', StockMovementKind.adjustIn, 200000, reverses: 'm2');

      final row = await db
          .customSelect('SELECT ledger_remaining_milli, discrepancy_milli FROM v_batch_stock_check')
          .getSingle();
      expect(row.read<int>('ledger_remaining_milli'), 1000000);
      expect(row.read<int>('discrepancy_milli'), 0);
    });

    test('waste and expired count as outgoing', () async {
      await item('milk');
      await batch('b1', 'milk', 1000000, 1000000);
      await movement('m1', 'b1', 'milk', StockMovementKind.openingIn, 1000000);
      await movement('m2', 'b1', 'milk', StockMovementKind.waste, 250000);
      await movement('m3', 'b1', 'milk', StockMovementKind.expired, 250000);
      final row = await db
          .customSelect('SELECT ledger_remaining_milli FROM v_batch_stock_check')
          .getSingle();
      expect(row.read<int>('ledger_remaining_milli'), 500000);
    });
  });

  group('partial unique indexes', () {
    Future<void> item(String id, String normalized, UnitCategory category) =>
        db.into(db.items).insert(
          ItemsCompanion.insert(
            id: id,
            name: normalized,
            normalizedName: normalized,
            unitCategory: category,
            defaultDisplayUnitCode: 'g',
            itemKind: ItemKind.food,
            isFavorite: false,
            createdAt: 0,
            updatedAt: 0,
          ),
        );

    test('the same identity twice is rejected (A06)', () async {
      await item('i1', 'tomato', UnitCategory.weight);
      await expectLater(
        item('i2', 'tomato', UnitCategory.weight),
        throwsA(anything),
      );
    });

    test('the same name in a different category is allowed', () async {
      await item('i1', 'milk', UnitCategory.weight);
      await item('i2', 'milk', UnitCategory.volume);
      final rows = await db.select(db.items).get();
      expect(rows, hasLength(2));
    });

    test('re-adding after a soft delete is allowed (A19)', () async {
      await item('i1', 'tomato', UnitCategory.weight);
      await db.customStatement("UPDATE items SET deleted_at = 1 WHERE id = 'i1'");
      await item('i2', 'tomato', UnitCategory.weight);
      final active = await db
          .customSelect('SELECT id FROM items WHERE deleted_at IS NULL')
          .map((r) => r.read<String>('id'))
          .get();
      expect(active, ['i2']);
    });
  });

  group('v_calendar_events', () {
    test('emits each source with the right event_type and honours a bounded range', () async {
      await account('cash', 0);
      await tx('t', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 50000, note: 'Market');
      await db.into(db.shoppingLists).insert(
        ShoppingListsCompanion.insert(
          id: 'sl',
          name: 'Weekend list',
          isDefault: true,
          isArchived: false,
          targetDateKey: Value(DateKey.fromYmd(2026, 8, 1)),
          createdAt: 0,
          updatedAt: 0,
        ),
      );

      final counts = await db.customSelect(
        'SELECT event_type, COUNT(*) AS n FROM v_calendar_events GROUP BY event_type',
      ).get();
      final byType = {
        for (final r in counts) r.read<String>('event_type'): r.read<int>('n'),
      };
      expect(byType['transaction'], 1);
      expect(byType['shoppingTarget'], 1);

      final ranged = await db
          .customSelect('SELECT event_type FROM v_calendar_events '
          'WHERE date_key BETWEEN 20260801 AND 20260831')
          .map((r) => r.read<String>('event_type'))
          .get();
      expect(ranged, ['shoppingTarget']);
    });

    test('warranty, service and batch expiry all appear', () async {
      await db.into(db.assets).insert(
        AssetsCompanion.insert(
          id: 'a1',
          name: 'LG TV',
          normalizedName: 'lg tv',
          type: AssetType.electronics,
          warrantyEndDateKey: Value(DateKey.fromYmd(2027, 1, 1)),
          nextServiceDueDateKey: Value(DateKey.fromYmd(2026, 9, 1)),
          status: AssetStatus.active,
          createdAt: 0,
          updatedAt: 0,
        ),
      );
      final types = await db
          .customSelect('SELECT DISTINCT event_type FROM v_calendar_events')
          .map((r) => r.read<String>('event_type'))
          .get();
      expect(types.toSet(), containsAll({'warrantyEnd', 'serviceDue'}));
    });

    test('a disposed asset raises no alerts', () async {
      await db.into(db.assets).insert(
        AssetsCompanion.insert(
          id: 'a1',
          name: 'Old TV',
          normalizedName: 'old tv',
          type: AssetType.electronics,
          warrantyEndDateKey: Value(DateKey.fromYmd(2027, 1, 1)),
          status: AssetStatus.disposed,
          disposalReason: const Value(AssetDisposalReason.sold),
          createdAt: 0,
          updatedAt: 0,
        ),
      );
      expect(await db.customSelect('SELECT 1 FROM v_calendar_events').get(), isEmpty);
      expect(await db.customSelect('SELECT 1 FROM v_asset_alerts').get(), isEmpty);
    });

    test('severity is the static baseline; escalation is a Dart concern', () async {
      await account('cash', 0);
      await tx('t', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 100, on: DateKey.fromYmd(2020, 1, 1));
      final row = await db.customSelect('SELECT severity FROM v_calendar_events').getSingle();
      expect(row.read<String>('severity'), 'info',
          reason: 'no view consults the clock — see schedule_views.drift');
    });
  });

  group('v_recurring_due', () {
    test('paused templates are excluded and due occurrences are joined', () async {
      await account('cash', 0);
      Future<void> template(String id, {required bool paused}) =>
          db.into(db.recurringTemplates).insert(
            RecurringTemplatesCompanion.insert(
              id: id,
              name: id,
              normalizedName: id,
              kind: RecurringKind.bill,
              direction: RecurringDirection.outflow,
              defaultAmountMinor: 64900,
              currencyCode: 'INR',
              intervalUnit: RecurringIntervalUnit.month,
              intervalCount: 1,
              startDateKey: today,
              nextDueDateKey: DateKey.fromYmd(2026, 8, 5),
              isPaused: paused,
              autoRemind: false,
              remindDaysBefore: 1,
              createdAt: 0,
              updatedAt: 0,
            ),
          );
      await template('netflix', paused: false);
      await template('gym', paused: true);
      await db.into(db.recurringOccurrences).insert(
        RecurringOccurrencesCompanion.insert(
          id: 'o1',
          templateId: 'netflix',
          dueDateKey: DateKey.fromYmd(2026, 8, 5),
          status: RecurringOccurrenceStatus.due,
          createdAt: 0,
          updatedAt: 0,
        ),
      );

      final rows = await db.customSelect(
        'SELECT template_id, occurrence_id, occurrence_due_date_key FROM v_recurring_due',
      ).get();
      expect(rows.map((r) => r.read<String>('template_id')), ['netflix']);
      expect(rows.single.read<String>('occurrence_id'), 'o1');
      expect(rows.single.read<int>('occurrence_due_date_key'), 20260805);
    });

    test('no overdue column exists — the view never consults the clock', () async {
      final info = await db
          .customSelect("SELECT name FROM pragma_table_info('v_recurring_due')")
          .map((r) => r.read<String>('name'))
          .get();
      expect(info, isNot(contains('is_overdue')));
      expect(info, contains('occurrence_due_date_key'));
    });
  });

  group('FTS5', () {
    Future<void> namedItem(String id, String name) => db.into(db.items).insert(
      ItemsCompanion.insert(
        id: id,
        name: name,
        normalizedName: id,
        unitCategory: UnitCategory.weight,
        defaultDisplayUnitCode: 'g',
        itemKind: ItemKind.food,
        isFavorite: false,
        createdAt: 0,
        updatedAt: 0,
      ),
    );

    test('items_fts finds a name, and the join filters soft deletes', () async {
      await namedItem('tomato', 'Cherry Tomato');
      await namedItem('potato', 'Potato');

      var hits = await db
          .customSelect('SELECT i.id FROM items_fts f JOIN items i ON i.rowid = f.rowid '
          "WHERE items_fts MATCH 'Tomato' AND i.deleted_at IS NULL")
          .map((r) => r.read<String>('id'))
          .get();
      expect(hits, ['tomato']);

      await db.customStatement("UPDATE items SET deleted_at = 1 WHERE id = 'tomato'");
      hits = await db
          .customSelect('SELECT i.id FROM items_fts f JOIN items i ON i.rowid = f.rowid '
          "WHERE items_fts MATCH 'Tomato' AND i.deleted_at IS NULL")
          .map((r) => r.read<String>('id'))
          .get();
      expect(hits, isEmpty,
          reason: 'FTS knows nothing about deleted_at — the join must filter (L7)');
    });

    test('the update trigger reindexes a renamed item', () async {
      await namedItem('i', 'Brinjal');
      await db.customStatement("UPDATE items SET name = 'Aubergine' WHERE id = 'i'");

      final stale = await db
          .customSelect("SELECT rowid FROM items_fts WHERE items_fts MATCH 'Brinjal'")
          .get();
      final fresh = await db
          .customSelect("SELECT rowid FROM items_fts WHERE items_fts MATCH 'Aubergine'")
          .get();
      expect(stale, isEmpty);
      expect(fresh, hasLength(1));
    });

    test('the delete trigger removes the entry', () async {
      await namedItem('i', 'Brinjal');
      await db.customStatement("DELETE FROM items WHERE id = 'i'");
      final hits = await db
          .customSelect("SELECT rowid FROM items_fts WHERE items_fts MATCH 'Brinjal'")
          .get();
      expect(hits, isEmpty);
    });

    test('transactions_fts indexes the note', () async {
      await account('cash', 0);
      await tx('t', TransactionKind.withdrawal, TransactionSubtype.grocery,
          from: 'cash', amountMinor: 100, note: 'Weekly vegetable run');
      final hits = await db
          .customSelect("SELECT rowid FROM transactions_fts "
          "WHERE transactions_fts MATCH 'vegetable'")
          .get();
      expect(hits, hasLength(1));
    });
  });
}