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
  Stream<List<Account>> watchSelectable() => _dao.watchSelectable().map(
    (rows) => rows.map((r) => r.toEntity()).toList(),
  );

  @override
  Stream<List<Account>> watchAllIncludingArchived() => _dao
      .watchAllIncludingArchived()
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Account?> byId(String id) async =>
      (await _dao.byIdIncludingDeleted(id))?.toEntity();

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
    return _dao
        .watchBalanceOf(accountId)
        .map(
          (row) => row == null
              ? null
              : AccountBalance(
                  accountId: row.accountId,
                  balance: Money(row.balanceMinor, row.currencyCode),
                ),
        );
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
      accountToCompanion(
        account,
        createdAt: stamps.createdAt,
        updatedAt: stamps.updatedAt,
      ),
    );
    return Result.ok(account);
  }

  @override
  Future<Result<void, Failure>> setArchived({
    required String id,
    required bool isArchived,
  }) async {
    await _dao.setArchived(
      id: id,
      isArchived: isArchived,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
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
