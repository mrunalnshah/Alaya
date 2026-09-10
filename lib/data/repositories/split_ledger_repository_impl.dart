import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/split_dao.dart';
import 'package:alaya/data/daos/split_view_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/mappers/split_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/split_expense.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/domain/repositories/split_group_repository.dart';
import 'package:alaya/domain/repositories/split_ledger_repository.dart';
import 'package:alaya/domain/services/split/debt_simplifier.dart' show DebtEdge;
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/data/daos/account_dao.dart';
import 'package:alaya/data/repositories/mappers/money_mappers.dart';
import 'package:alaya/domain/entities/transaction.dart';

/// `SplitLedgerRepository` backed by [SplitDao] for writes and [SplitViewDao] for everything derived.
///
/// **Two DAOs, and the split is Law L7 made structural.** Writes go to tables; every balance, total
/// and feed comes from a view. Nothing here can return a stored total because there is no stored total
/// to return.
final class SplitLedgerRepositoryImpl implements SplitLedgerRepository {
  /// Creates the repository.
  const SplitLedgerRepositoryImpl(
    this._dao,
    this._views,
    this._groups,
    this._accounts,
    this._clock,
  );

  final SplitDao _dao;
  final SplitViewDao _views;
  final SplitGroupRepository _groups;
  final AccountDao _accounts;
  final Clock _clock;

  Future<List<SplitShare>> _sharesOf(SplitExpenseRow row) async {
    final shares = await _dao.watchShares(row.id).first;
    return [for (final s in shares) s.toEntity(currencyCode: row.currencyCode)];
  }

  Future<SplitExpense> _assemble(SplitExpenseRow row) async =>
      row.toEntity(shares: await _sharesOf(row));

  // ── expenses ────────────────────────────────────────────────────────────────────────────

  @override
  Stream<List<SplitExpenseSummary>> watchExpenses({
    required DateKey from,
    required DateKey to,
    String? groupId,
  }) => _views
      .watchExpenses(
        // The typed boundary is crossed once, here. The views carry no converter, which is why
        // `SplitViewDao` takes plain ints — the same arrangement `CalendarDao` has.
        fromDateKey: from.value,
        toDateKey: to.value,
        groupId: groupId,
      )
      .map((rows) => [for (final row in rows) row.toEntity()]);

  @override
  Stream<SplitExpense?> watchExpenseById(String id) => _dao
      .watchExpenseById(id)
      .asyncMap((row) async => row == null ? null : _assemble(row));

  @override
  Future<SplitExpense?> expenseById(String id) async {
    final row = await _dao.expenseById(id);
    return row == null ? null : _assemble(row);
  }

  @override
  Future<SplitExpense?> expenseForTransaction(String transactionId) async {
    final row = await _dao.expenseForTransaction(transactionId);
    return row == null ? null : _assemble(row);
  }

  @override
  Future<Result<SplitExpense, Failure>> saveExpense(
    SplitExpense expense,
  ) async {
    if (!expense.total.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'A shared expense needs an amount.',
          field: 'total',
        ),
      );
    }

    // **The cross-table rule SQLite cannot express.** A share may only name a transaction line when
    // the expense has a transaction, because the lines belong to that transaction. The header half —
    // `split_method <> 'perLine' OR transaction_id IS NOT NULL` — is a CHECK; this direction spans
    // two tables and a CHECK cannot hold a subquery, so it lives here. `split_tables.dart` says so at
    // the column.
    if (expense.transactionId == null &&
        expense.shares.any((s) => s.transactionLineNo != null)) {
      return const Result.failure(
        BusinessRuleFailure(
          'Itemising needs the receipt, which means the expense you paid for.',
          rule: 'splitItemiseNeedsTransaction',
        ),
      );
    }

    final seen = <String>{};
    for (final share in expense.shares) {
      // One share per person per line. Two shares for the same person on the same line would both be
      // counted by `v_split_balances`, so the debt would silently double.
      final key = '${share.payeeId}#${share.transactionLineNo ?? -1}';
      if (!seen.add(key)) {
        return const Result.failure(
          BusinessRuleFailure(
            'Somebody has two shares of the same item.',
            rule: 'splitDuplicateShare',
          ),
        );
      }
      if (share.amount.isNegative) {
        return const Result.failure(
          ValidationFailure(
            'A share cannot be negative.',
            field: 'shareAmountMinor',
          ),
        );
      }
      if (share.amount.currencyCode != expense.total.currencyCode) {
        return const Result.failure(
          BusinessRuleFailure(
            'Every share must be in the same currency as the expense.',
            rule: 'splitShareCurrency',
          ),
        );
      }
    }

    // **Shares that do not sum to the total are accepted, deliberately.** Percentages mid-edit, or a
    // tip nobody assigned, are real states rather than errors — `SplitExpense.unallocated` reports
    // the gap and the screen decides what to say. `v_transaction_allocation` gives an un-itemised
    // transaction exactly the same treatment.

    try {
      final existing = await _dao.expenseById(expense.id);
      final stamps = WriteTimestamps.resolve(
        existingCreatedAt: existing?.createdAt,
        clock: _clock,
      );
      final now = stamps.updatedAt;

      await _dao.saveExpense(
        nowUtcMillis: now,
        expense: splitExpenseToCompanion(
          expense,
          createdAt: stamps.createdAt,
          updatedAt: now,
        ),
        shares: [
          for (final share in expense.shares)
            splitShareToCompanion(share, createdAt: now, updatedAt: now),
        ],
      );
      final saved = await expenseById(expense.id);
      return saved == null
          ? const Result.failure(
              UnexpectedFailure('That split could not be saved.'),
            )
          : Result.ok(saved);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That split could not be saved.', cause: error),
      );
    }
  }

  @override
  Future<Result<void, Failure>> deleteExpense(String id) async {
    try {
      await _dao.softDeleteExpense(id: id, nowUtcMillis: _clock.nowUtcMillis());
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That split could not be deleted.', cause: error),
      );
    }
  }

  @override
  Future<Result<void, Failure>> mergePlaceholder({
    required String placeholderPayeeId,
    required String payeeId,
  }) async {
    if (placeholderPayeeId == payeeId) {
      return const Result.failure(
        BusinessRuleFailure(
          'That is already the same person.',
          rule: 'splitMergeSelf',
        ),
      );
    }

    // Through `SplitDao`, which already touches `payees` for the merge itself. The first version took a
    // `PayeeDao` as a sixth constructor argument — and every place that builds this repository,
    // `repository_providers.dart` and `daily_job.dart`, stopped compiling. A dependency added for one guard
    // is not worth two call sites.
    final from = await _dao.payeeIdentity(placeholderPayeeId);
    if (from == null) {
      return Result.failure(
        NotFoundFailure(
          'That participant no longer exists.',
          id: placeholderPayeeId,
        ),
      );
    }
    // **Only a placeholder may be merged away, and the guard belongs here rather than in the DAO.**
    // Reassigning every reference and retiring a row is destructive in one direction: whichever payee is
    // named first stops existing. That is exactly right for "Person 4 was Ravi all along", where the first
    // row was never a contact anybody chose — and wrong as a general "combine two shops" tool, where a
    // caller with the arguments the wrong way round would silently delete the one they meant to keep.
    if (from.kind != PayeeKind.splitPlaceholder) {
      return const Result.failure(
        BusinessRuleFailure(
          'Only an unnamed split participant can be merged into somebody else.',
          rule: 'splitMergeNotPlaceholder',
        ),
      );
    }

    final into = await _dao.payeeIdentity(payeeId);
    if (into == null) {
      return Result.failure(
        NotFoundFailure('That person no longer exists.', id: payeeId),
      );
    }
    if (into.deletedAt != null) {
      // Merging into the trash would move live debts onto a row `v_split_balances` filters out, so the
      // balances would disappear from every screen while still sitting in the table.
      return const Result.failure(
        BusinessRuleFailure(
          'That person has been deleted. Restore them first.',
          rule: 'splitMergeIntoDeleted',
        ),
      );
    }

    try {
      await _dao.mergePayee(
        fromPayeeId: placeholderPayeeId,
        intoPayeeId: payeeId,
        nowUtcMillis: _clock.nowUtcMillis(),
      );
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure(
          'Those two could not be merged.',
          cause: error,
        ),
      );
    }
  }

  // ── settlements ─────────────────────────────────────────────────────────────────────────

  @override
  Stream<List<SplitSettlement>> watchSettlements({
    required DateKey from,
    required DateKey to,
    String? groupId,
  }) => _dao
      .watchSettlements(
        fromDateKey: from.value,
        toDateKey: to.value,
        groupId: groupId,
      )
      .map((rows) => [for (final row in rows) row.toEntity()]);

  @override
  Future<Result<SplitSettlement, Failure>> recordSettlement({
    required SplitSettlement settlement,
    Transaction? transaction,
  }) async {
    if (!settlement.amount.isPositive) {
      return const Result.failure(
        ValidationFailure('A settlement needs an amount.', field: 'amount'),
      );
    }
    if (settlement.fromPayeeId == settlement.toPayeeId) {
      return const Result.failure(
        BusinessRuleFailure(
          'Paying yourself is not a settlement.',
          rule: 'splitSelfSettlement',
        ),
      );
    }

    // **Checked here rather than trusted from the caller.** A settlement of the user's own money with
    // no transaction is the one failure in this module they could not see: the debt reads as cleared
    // and no money appears anywhere. `SettlementService` already refuses it; this is the backstop for
    // anything that reaches the repository another way.
    final self = await _groups.selfPayeeId();
    final involvesYou = self != null && settlement.involves(self);
    if (involvesYou && transaction == null) {
      return const Result.failure(
        BusinessRuleFailure(
          'A settlement you are part of has to be recorded against an account.',
          rule: 'splitSettlementNeedsTransaction',
        ),
      );
    }
    if (!involvesYou && transaction != null) {
      // The mirror image, and worth refusing too: a transaction for a settlement between two other
      // people would move money in an account of the user's that nothing in the split ever justified.
      return const Result.failure(
        BusinessRuleFailure(
          'That settlement does not involve you, so it moves none of your money.',
          rule: 'splitSettlementNotYours',
        ),
      );
    }

    if (transaction != null) {
      final accountId = transaction.toAccountId ?? transaction.fromAccountId;
      if (accountId == null) {
        return const Result.failure(
          ValidationFailure(
            'Choose the account this money moved through.',
            field: 'accountId',
          ),
        );
      }
      final account = await _accounts.byIdIncludingDeleted(accountId);
      if (account == null) {
        return Result.failure(
          NotFoundFailure('That account no longer exists.', id: accountId),
        );
      }
      // Law L8's money-side twin: an amount is minor units plus a code, and putting INR into a USD
      // account would store a number that reads back as the wrong currency forever.
      if (account.currencyCode != settlement.amount.currencyCode) {
        return Result.failure(
          BusinessRuleFailure(
            'That account is in ${account.currencyCode}, not '
            '${settlement.amount.currencyCode}.',
            rule: 'splitSettlementCurrency',
          ),
        );
      }
    }

    try {
      final now = _clock.nowUtcMillis();
      if (transaction == null) {
        await _dao.insertSettlement(
          splitSettlementToCompanion(
            settlement,
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else {
        await _dao.insertSettlementWithTransaction(
          transaction: transactionToCompanion(
            transaction,
            monthKey: transaction.dateKey.value ~/ 100,
            createdAt: now,
            updatedAt: now,
          ),
          settlement: splitSettlementToCompanion(
            settlement,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      return Result.ok(settlement);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure(
          'That settlement could not be recorded.',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<void, Failure>> deleteSettlement(String id) async {
    try {
      await _dao.softDeleteSettlement(
        id: id,
        nowUtcMillis: _clock.nowUtcMillis(),
      );
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure(
          'That settlement could not be deleted.',
          cause: error,
        ),
      );
    }
  }

  // ── derived reads ───────────────────────────────────────────────────────────────────────

  @override
  Stream<List<SplitBalance>> watchBalances() => _views.watchBalances().map(
    (rows) => [for (final row in rows) row.toEntity()],
  );

  @override
  Stream<List<SplitBalance>> watchGroupBalances(String groupId) => _views
      .watchGroupBalances(groupId)
      .map((rows) => [for (final row in rows) row.toEntity()]);

  @override
  Stream<List<SplitBalance>> watchBalanceWith(String payeeId) => _views
      .watchBalanceWith(payeeId)
      .map((rows) => [for (final row in rows) row.toEntity()]);

  @override
  Stream<List<SplitActivityEntry>> watchActivity({
    String? groupId,
    int limit = 50,
  }) => _views
      .watchActivity(limit: limit, groupId: groupId)
      .map((rows) => [for (final row in rows) row.toEntity()]);

  @override
  Future<List<DebtEdge>> debtsIn(String groupId) async {
    final self = await _groups.selfPayeeId();
    if (self == null) return const [];

    // **Built from net balances, and that is a known narrowing worth stating.** The contract says the
    // simplifier wants the edges as incurred, because its tie-break prefers transfers along debts that
    // genuinely exist. What `v_split_group_balances` can supply is one net figure per counterparty
    // *with you* — a single-user ledger records no debt between two other people, so every edge here
    // has you at one end anyway.
    //
    // The consequence is real but small: with only you-shaped edges the partition has nothing to
    // prefer between, so the tie-break is inert until the plan gains third-party debts. It becomes
    // live the moment a settle-up plan suggests one, which session 7 does — and the simplifier already
    // handles it because it was written for edges rather than for balances.
    final rows = await _views.groupBalances(groupId);
    final edges = <DebtEdge>[];
    for (final row in rows) {
      final balance = row.toEntity();
      if (balance.isSettled) continue;
      edges.add(
        balance.theyOweMe
            ? DebtEdge(
                fromPayeeId: balance.payeeId,
                toPayeeId: self,
                amount: balance.outstanding,
              )
            : DebtEdge(
                fromPayeeId: self,
                toPayeeId: balance.payeeId,
                amount: balance.outstanding,
              ),
      );
    }
    return edges;
  }
}
