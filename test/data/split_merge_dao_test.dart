// **`hide isNull`.** drift exports one for building queries and `matcher` exports one for asserting, and a
// file that does both imports gets an ambiguity error on the bare identifier. Hiding drift's leaves
// `column.isNull()` alone — that is a method on `Expression`, not the top-level function.
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/split_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/seed/seed_data.dart';

/// [SplitDao.mergePayee].
///
/// **The one piece of arithmetic added in the split cycle that had nothing behind it.** Saving a split with
/// unnamed participants writes a `PayeeKind.splitPlaceholder` row so the debt can exist at all; saying "Person 4
/// was Ravi" then has to move every reference onto Ravi and retire the placeholder. Where Ravi is *already* on
/// the same expense the two shares are **summed**, because `idx_split_share` is unique on
/// `(split_expense_id, payee_id, transaction_line_no)` and the reassignment would otherwise land on a key that
/// exists.
///
/// **A DAO test against a real database, not a fake.** The summing happens inside a drift transaction, and the
/// collision it exists to handle is a unique index — neither survives being faked. The one thing that could
/// prove this correct is the thing that also enforces it.
void main() {
  late AlayaDatabase db;
  late SplitDao dao;

  /// A fixed instant, so `updatedAt` and `deletedAt` are assertable rather than "recent".
  const now = 1756000000000;

  setUp(() async {
    final seed = SeedData(
      uids: SequentialUidGenerator(prefix: 'seed'),
      clock: FixedClock(DateTime(2026, 7, 28, 9)),
    );
    db = AlayaDatabase(NativeDatabase.memory(), seeder: seed.insertAll);
    // Force onCreate to run. Without a query the lazy executor never opens, and every insert below would be
    // the first — against tables that do not exist yet.
    await db.customSelect('SELECT 1').get();
    dao = SplitDao(db);
  });

  tearDown(() => db.close());

  Future<void> payee(String id, String name, PayeeKind kind) => db
      .into(db.payees)
      .insert(
        PayeesCompanion.insert(
          id: id,
          name: name,
          normalizedName: name.toLowerCase(),
          kind: kind,
          createdAt: now,
          updatedAt: now,
        ),
      );

  Future<void> expense(String id, {required String paidBy}) => db
      .into(db.splitExpenses)
      .insert(
        SplitExpensesCompanion.insert(
          id: id,
          paidByPayeeId: paidBy,
          totalAmountMinor: 500000,
          currencyCode: 'INR',
          dateKey: const DateKey(20260728),
          monthKey: 202607,
          splitMethod: SplitMethod.equal,
          createdAt: now,
          updatedAt: now,
        ),
      );

  Future<void> share(
    String id, {
    required String expenseId,
    required String payeeId,
    required int minor,
    ShareInputKind kind = ShareInputKind.equal,
    int? inputValue,
    int? lineNo,
  }) => db
      .into(db.splitShares)
      .insert(
        SplitSharesCompanion.insert(
          id: id,
          splitExpenseId: expenseId,
          payeeId: payeeId,
          shareAmountMinor: minor,
          inputKind: kind,
          inputValue: Value(inputValue),
          transactionLineNo: Value(lineNo),
          createdAt: now,
          updatedAt: now,
        ),
      );

  Future<List<SplitShareRow>> livingShares() =>
      (db.select(db.splitShares)..where((t) => t.deletedAt.isNull())).get();

  group('the collision the unique index forces', () {
    setUp(() async {
      await payee('me', 'Mrunal', PayeeKind.person);
      await payee('ravi', 'Ravi', PayeeKind.person);
      await payee('ghost', 'Person 4', PayeeKind.splitPlaceholder);
      await expense('e1', paidBy: 'me');
      await share('s-ravi', expenseId: 'e1', payeeId: 'ravi', minor: 120000);
      await share('s-ghost', expenseId: 'e1', payeeId: 'ghost', minor: 80000);
    });

    test('two shares on one expense become one, summed', () async {
      // **Refusing would be the wrong answer.** Somebody telling the app who a participant really was is a
      // statement it should be able to record — and Ravi genuinely owes both amounts.
      await dao.mergePayee(
        fromPayeeId: 'ghost',
        intoPayeeId: 'ravi',
        nowUtcMillis: now,
      );

      final rows = await livingShares();
      expect(rows, hasLength(1));
      expect(rows.single.payeeId, 'ravi');
      expect(rows.single.shareAmountMinor, 200000);
    });

    test("the merged row's stored input becomes exact", () async {
      // 40% plus somebody else's ₹800 is not 40% of anything. **A percentage that no longer reproduces the
      // amount beside it is the one thing this module must never show**, so the input is rewritten to describe
      // what the row now holds.
      // **`write` after a `where`, not `replace`.** `replace` rewrites a whole row from a companion, so every
      // required column must be present — it refused this one for four of them. `write` applies only the fields
      // the companion sets, which is what "make this share a 40% one" actually means.
      await (db.update(
        db.splitShares,
      )..where((t) => t.id.equals('s-ravi'))).write(
        const SplitSharesCompanion(
          inputKind: Value(ShareInputKind.percent),
          inputValue: Value(4000),
          updatedAt: Value(now),
        ),
      );

      await dao.mergePayee(
        fromPayeeId: 'ghost',
        intoPayeeId: 'ravi',
        nowUtcMillis: now,
      );

      final row = (await livingShares()).single;
      expect(row.inputKind, ShareInputKind.exact);
      expect(row.inputValue, 200000, reason: 'the input now names the amount');
    });

    test("the placeholder's row is retired, not deleted", () async {
      await dao.mergePayee(
        fromPayeeId: 'ghost',
        intoPayeeId: 'ravi',
        nowUtcMillis: now,
      );

      final all = await db.select(db.splitShares).get();
      expect(all, hasLength(2), reason: 'soft delete, so the row survives');
      final retired = all.firstWhere((r) => r.id == 's-ghost');
      expect(retired.deletedAt, now);
    });

    test('the unique index is never violated', () async {
      // The whole reason for the summing. A plain reassignment would collide on
      // `(split_expense_id, payee_id, transaction_line_no)` and throw.
      await expectLater(
        dao.mergePayee(
          fromPayeeId: 'ghost',
          intoPayeeId: 'ravi',
          nowUtcMillis: now,
        ),
        completes,
      );
    });
  });

  group('no collision', () {
    test('a share on a different expense is reassigned, not summed', () async {
      await payee('me', 'Mrunal', PayeeKind.person);
      await payee('ravi', 'Ravi', PayeeKind.person);
      await payee('ghost', 'Person 4', PayeeKind.splitPlaceholder);
      await expense('e1', paidBy: 'me');
      await expense('e2', paidBy: 'me');
      await share('s-ravi', expenseId: 'e1', payeeId: 'ravi', minor: 120000);
      await share('s-ghost', expenseId: 'e2', payeeId: 'ghost', minor: 80000);

      await dao.mergePayee(
        fromPayeeId: 'ghost',
        intoPayeeId: 'ravi',
        nowUtcMillis: now,
      );

      final rows = await livingShares();
      expect(rows, hasLength(2));
      expect(rows.every((r) => r.payeeId == 'ravi'), isTrue);
      expect(
        rows.map((r) => r.shareAmountMinor).toList()..sort(),
        [80000, 120000],
        reason: 'two separate evenings stay two separate debts',
      );
    });

    test('the same expense but a different line does not collide', () async {
      // `transaction_line_no` is part of the key, so an itemised split can carry one share per person *per
      // line* — and two of those are not the same debt however they are merged.
      await payee('me', 'Mrunal', PayeeKind.person);
      await payee('ravi', 'Ravi', PayeeKind.person);
      await payee('ghost', 'Person 4', PayeeKind.splitPlaceholder);
      await expense('e1', paidBy: 'me');
      await share(
        's-ravi',
        expenseId: 'e1',
        payeeId: 'ravi',
        minor: 120000,
        lineNo: 1,
      );
      await share(
        's-ghost',
        expenseId: 'e1',
        payeeId: 'ghost',
        minor: 80000,
        lineNo: 2,
      );

      await dao.mergePayee(
        fromPayeeId: 'ghost',
        intoPayeeId: 'ravi',
        nowUtcMillis: now,
      );

      final rows = await livingShares();
      expect(rows, hasLength(2));
      expect(rows.every((r) => r.payeeId == 'ravi'), isTrue);
    });
  });

  group('everything else that names a payee', () {
    setUp(() async {
      await payee('me', 'Mrunal', PayeeKind.person);
      await payee('ravi', 'Ravi', PayeeKind.person);
      await payee('ghost', 'Person 4', PayeeKind.splitPlaceholder);
    });

    test('settlements move at both ends', () async {
      await db
          .into(db.splitSettlements)
          .insert(
            SplitSettlementsCompanion.insert(
              id: 't1',
              fromPayeeId: 'ghost',
              toPayeeId: 'me',
              amountMinor: 50000,
              currencyCode: 'INR',
              dateKey: const DateKey(20260728),
              monthKey: 202607,
              createdAt: now,
              updatedAt: now,
            ),
          );

      await dao.mergePayee(
        fromPayeeId: 'ghost',
        intoPayeeId: 'ravi',
        nowUtcMillis: now,
      );

      final row = await db.select(db.splitSettlements).getSingle();
      expect(row.fromPayeeId, 'ravi');
      expect(row.toPayeeId, 'me');
    });

    test('the placeholder payee is retired last, and is retired', () async {
      // **Last, inside the same transaction.** Retiring it before its references moved would leave shares
      // pointing at a deleted payee — and `v_split_balances` joins `payees` on `deleted_at IS NULL`, so those
      // debts would vanish from every screen while still sitting in the table.
      await expense('e1', paidBy: 'me');
      await share('s-ghost', expenseId: 'e1', payeeId: 'ghost', minor: 80000);

      await dao.mergePayee(
        fromPayeeId: 'ghost',
        intoPayeeId: 'ravi',
        nowUtcMillis: now,
      );

      final ghost = await (db.select(
        db.payees,
      )..where((t) => t.id.equals('ghost'))).getSingle();
      expect(ghost.deletedAt, now);

      final ravi = await (db.select(
        db.payees,
      )..where((t) => t.id.equals('ravi'))).getSingle();
      expect(ravi.deletedAt, isNull, reason: 'the one being kept');
    });
  });
}
