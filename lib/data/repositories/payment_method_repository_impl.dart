import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/payment_method_dao.dart';
import 'package:alaya/data/repositories/mappers/money_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/repositories/payment_method_repository.dart';

/// `PaymentMethodRepository` backed by `PaymentMethodDao`.
final class PaymentMethodRepositoryImpl implements PaymentMethodRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const PaymentMethodRepositoryImpl(this._dao, this._clock);

  final PaymentMethodDao _dao;
  final Clock _clock;

  @override
  Stream<List<PaymentMethod>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<PaymentMethod?> byId(String id) async =>
      (await _dao.byIdIncludingDeleted(id))?.toEntity();

  @override
  Future<Result<PaymentMethod, Failure>> save(PaymentMethod method) async {
    final existing = await _dao.byIdIncludingDeleted(method.id);
    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _dao.upsert(
      paymentMethodToCompanion(method, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );
    return Result.ok(method);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    final inUseCount = await _dao.activeTransactionCount(id);
    if (inUseCount > 0) {
      return Result.failure(
        BusinessRuleFailure(
          'This payment method is used by $inUseCount transaction(s) and cannot be deleted.',
          rule: 'paymentMethodInUse',
        ),
      );
    }
    final rowsChanged = await _dao.softDeleteUserMethod(id: id, nowUtcMillis: _clock.nowUtcMillis());
    if (rowsChanged == 0) {
      return const Result.failure(
        BusinessRuleFailure('System payment methods cannot be deleted.', rule: 'systemProtected'),
      );
    }
    return const Result.ok(null);
  }
}