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
