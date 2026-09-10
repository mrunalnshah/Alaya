/// Fakes for the two ports the split services write through.
///
/// **These exist because those services had no tests at all.** `SplitExpenseService`,
/// `SettlementService` and `SplitBalanceService` appeared in no test file — the same finding that
/// produced `cook_fakes.dart` last cycle, when `RecipeCookService` turned out to have never been
/// exercised. A service with no test is invisible to the suite: green proves nothing about it.
///
/// **The fakes fake storage, not arithmetic.** `SplitResolver` and `DebtSimplifier` run for real
/// through the services under test, so an ordering or allocation rule reimplemented here could not
/// diverge from production — which is the failure a hand-rolled fake invites.
library;

import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/split_expense.dart';
import 'package:alaya/domain/entities/split_group.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/repositories/split_group_repository.dart';
import 'package:alaya/domain/repositories/split_ledger_repository.dart';
import 'package:alaya/domain/services/split/debt_simplifier.dart' show DebtEdge;

/// One `recordSettlement` that reached the repository.
typedef RecordedSettlement = ({
  SplitSettlement settlement,
  Transaction? transaction,
});

/// A `SplitLedgerRepository` that keeps what it is given.
class FakeSplitLedger implements SplitLedgerRepository {
  /// Creates the fake.
  FakeSplitLedger({
    List<SplitBalance> balances = const [],
    List<DebtEdge> debts = const [],
    this.rejectSave = false,
  }) : _balances = balances,
       _debts = debts;

  final List<SplitBalance> _balances;
  final List<DebtEdge> _debts;

  /// Whether `saveExpense` refuses, for the branch where a service must surface a failure.
  bool rejectSave;

  /// Every expense saved, in order.
  final List<SplitExpense> saved = [];

  /// Every settlement recorded, with the transaction it was paired with.
  final List<RecordedSettlement> settlements = [];

  /// Ids passed to `deleteExpense`.
  final List<String> deleted = [];

  @override
  Future<Result<SplitExpense, Failure>> saveExpense(
    SplitExpense expense,
  ) async {
    if (rejectSave) {
      return const Result.failure(
        BusinessRuleFailure('refused', rule: 'test'),
      );
    }
    saved.add(expense);
    return Result.ok(expense);
  }

  @override
  Future<Result<SplitSettlement, Failure>> recordSettlement({
    required SplitSettlement settlement,
    Transaction? transaction,
  }) async {
    settlements.add((settlement: settlement, transaction: transaction));
    return Result.ok(settlement);
  }

  @override
  Future<Result<void, Failure>> deleteExpense(String id) async {
    deleted.add(id);
    return const Result.ok(null);
  }

  @override
  Stream<List<SplitBalance>> watchBalances() => Stream.value(_balances);

  @override
  Stream<List<SplitBalance>> watchGroupBalances(String groupId) =>
      Stream.value(_balances);

  @override
  Stream<List<SplitBalance>> watchBalanceWith(String payeeId) => Stream.value([
    for (final b in _balances)
      if (b.payeeId == payeeId) b,
  ]);

  @override
  Future<List<DebtEdge>> debtsIn(String groupId) async => _debts;

  // Unused by the services under test. Throwing rather than returning something plausible, so a
  // future change that starts depending on one of these is announced instead of quietly passing.

  @override
  Stream<List<SplitExpenseSummary>> watchExpenses({
    required DateKey from,
    required DateKey to,
    String? groupId,
  }) => throw UnimplementedError('FakeSplitLedger.watchExpenses');

  @override
  Stream<SplitExpense?> watchExpenseById(String id) =>
      throw UnimplementedError('FakeSplitLedger.watchExpenseById');

  @override
  Future<SplitExpense?> expenseById(String id) =>
      throw UnimplementedError('FakeSplitLedger.expenseById');

  @override
  Future<SplitExpense?> expenseForTransaction(String transactionId) =>
      throw UnimplementedError('FakeSplitLedger.expenseForTransaction');

  /// **Throws, by this file's own rule, and returning `Result.ok` here would have been the mistake.**
  ///
  /// Merging a placeholder into a real payee is reached from a provider rather than from any service
  /// these fakes exist for, so nothing under test calls it — and a fake that answered "fine" would let a
  /// future service start depending on a merge that never happened. That is precisely what the comment
  /// above forbids.
  ///
  /// It also cannot be faked usefully. The real work is five tables in one transaction, with shares
  /// **summed** where the target is already on the same expense; a fake reproducing that would be a
  /// second implementation of the merge, free to disagree with the first — the failure the library
  /// comment names in its own opening paragraph.
  ///
  /// A widget test for the naming sheet wants a different fake: one that records `(from, into)` and
  /// asserts the sheet asked for the right pair. That belongs beside the sheet's test, not here.
  @override
  Future<Result<void, Failure>> mergePlaceholder({
    required String placeholderPayeeId,
    required String payeeId,
  }) => throw UnimplementedError('FakeSplitLedger.mergePlaceholder');

  @override
  Stream<List<SplitSettlement>> watchSettlements({
    required DateKey from,
    required DateKey to,
    String? groupId,
  }) => throw UnimplementedError('FakeSplitLedger.watchSettlements');

  @override
  Future<Result<void, Failure>> deleteSettlement(String id) =>
      throw UnimplementedError('FakeSplitLedger.deleteSettlement');

  @override
  Stream<List<SplitActivityEntry>> watchActivity({
    String? groupId,
    int limit = 50,
  }) => throw UnimplementedError('FakeSplitLedger.watchActivity');
}

/// A `SplitGroupRepository` that answers only what the services ask.
class FakeSplitGroups implements SplitGroupRepository {
  /// Creates the fake. [self] null means the user has not been chosen yet.
  FakeSplitGroups({this.self});

  /// The payee claimed as the user.
  String? self;

  @override
  Future<String?> selfPayeeId() async => self;

  @override
  Future<Result<void, Failure>> setSelfPayeeId(String payeeId) async {
    self = payeeId;
    return const Result.ok(null);
  }

  @override
  Stream<List<SplitGroup>> watchAll() =>
      throw UnimplementedError('FakeSplitGroups.watchAll');

  @override
  Stream<List<SplitGroup>> watchActive() =>
      throw UnimplementedError('FakeSplitGroups.watchActive');

  @override
  Stream<SplitGroup?> watchById(String id) =>
      throw UnimplementedError('FakeSplitGroups.watchById');

  @override
  Future<SplitGroup?> byId(String id) =>
      throw UnimplementedError('FakeSplitGroups.byId');

  @override
  Stream<List<SplitGroup>> watchForPayee(String payeeId) =>
      throw UnimplementedError('FakeSplitGroups.watchForPayee');

  @override
  Future<Result<SplitGroup, Failure>> save(SplitGroup group) =>
      throw UnimplementedError('FakeSplitGroups.save');

  @override
  Future<Result<void, Failure>> setArchived({
    required String id,
    required bool isArchived,
  }) => throw UnimplementedError('FakeSplitGroups.setArchived');

  @override
  Future<Result<void, Failure>> delete(String id) =>
      throw UnimplementedError('FakeSplitGroups.delete');
}

/// Sequential ids, so an assertion can name one.
class SeqUids implements UidGenerator {
  int _next = 0;

  @override
  String generate() => 'id-${++_next}';
}

/// A balance in one direction, for building fixtures.
SplitBalance owedToMe(String payeeId, int minor, {DateKey? since}) =>
    SplitBalance(
      payeeId: payeeId,
      owedToMe: Money(minor, 'INR'),
      iOwe: const Money(0, 'INR'),
      oldestUnsettledDateKey: since,
    );

/// The other direction.
SplitBalance iOwe(String payeeId, int minor, {DateKey? since}) => SplitBalance(
  payeeId: payeeId,
  owedToMe: const Money(0, 'INR'),
  iOwe: Money(minor, 'INR'),
  oldestUnsettledDateKey: since,
);
