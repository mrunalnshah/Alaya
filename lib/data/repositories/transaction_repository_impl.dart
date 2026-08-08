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
  Future<Transaction?> byId(String id) async =>
      (await _transactionDao.byId(id))?.toEntity();

  @override
  Stream<List<Transaction>> watchByDateRange({
    required DateKey from,
    required DateKey to,
  }) {
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
        .watchBySubtype(
          subtype,
          fromMonthKey: fromMonthKey,
          toMonthKey: toMonthKey,
        )
        .map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Stream<List<Transaction>> watchNeedingReview() {
    return _transactionDao.watchNeedingReview().map(
      (rows) => rows.map((r) => r.toEntity()).toList(),
    );
  }

  @override
  Stream<int> watchNeedsReviewCount() =>
      _transactionDao.watchNeedsReviewCount();

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
    yield* _lineDao
        .watchForTransaction(transactionId)
        .map(
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
    return _lineDao
        .watchAllocation(transactionId)
        .map(
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
            categoryResolver: (r) =>
                r.unitCode == null ? null : categories[r.unitCode],
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
          .map(
            (line) => transactionLineToCompanion(
              line,
              createdAt: now,
              updatedAt: now,
            ),
          )
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
      return Result.failure(
        NotFoundFailure('Transaction not found.', id: transaction.id),
      );
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
          .map(
            (line) => transactionLineToCompanion(
              line,
              createdAt: now,
              updatedAt: now,
            ),
          )
          .toList(),
      nowUtcMillis: now,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> markReviewed(String id) async {
    await _transactionDao.markReviewed(
      id: id,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
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

    final original = Money(
      existing.originalAmountMinor,
      existing.originalCurrencyCode,
    );
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
        await _batchDao.detachFromDeletedTransaction(
          batchId: batchId,
          nowUtcMillis: now,
        );
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
    if (batch.remainingQuantityMilli != batch.initialQuantityMilli)
      return false;

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
  Future<Result<Transaction, Failure>> _fillQuickAddAccount(
    Transaction transaction,
  ) async {
    final needsTo =
        transaction.kind == TransactionKind.deposit ||
        transaction.kind == TransactionKind.adjustmentIncrease;
    final needsFrom =
        transaction.kind == TransactionKind.withdrawal ||
        transaction.kind == TransactionKind.adjustmentDecrease;

    if (!needsTo && !needsFrom) return Result.ok(transaction);
    if (needsTo && transaction.toAccountId != null)
      return Result.ok(transaction);
    if (needsFrom && transaction.fromAccountId != null)
      return Result.ok(transaction);

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
    final lastUsedId = await _settings.readValue(
      SettingsKeys.lastUsedAccountId,
    );
    if (lastUsedId != null && await _accountExists(lastUsedId))
      return lastUsedId;

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
