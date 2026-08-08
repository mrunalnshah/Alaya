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
  Stream<List<ServiceRecord>> watchForAsset(String assetId) => _dao
      .watchForAsset(assetId)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<ServiceRecord>> watchForAssetByType({
    required String assetId,
    required ServiceRecordType type,
  }) => _dao
      .watchForAssetByType(assetId: assetId, type: type)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<ServiceRecord>> watchWithNextDueInRange({
    required DateKey from,
    required DateKey to,
  }) => _dao
      .watchWithNextDueInRange(from: from, to: to)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<ServiceRecord?> byId(String id) async =>
      (await _dao.byId(id))?.toEntity();

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
        NotFoundFailure(
          'The asset this record belongs to does not exist.',
          id: record.assetId,
        ),
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
        reason:
            'Rolled back: the service record it belonged to could not be saved.',
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
    await _dao.unlinkDeletedTransaction(
      id: id,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
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
