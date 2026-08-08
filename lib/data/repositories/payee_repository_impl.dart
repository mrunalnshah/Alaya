import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/payee_dao.dart';
import 'package:alaya/data/repositories/mappers/money_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/repositories/payee_repository.dart';

/// `PayeeRepository` backed by `PayeeDao`.
final class PayeeRepositoryImpl implements PayeeRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const PayeeRepositoryImpl(this._dao, this._clock);

  final PayeeDao _dao;
  final Clock _clock;

  @override
  Stream<List<Payee>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Payee>> watchMatching(String term) =>
      _dao.watchMatching(term).map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Payee?> byId(String id) async => (await _dao.byIdIncludingDeleted(id))?.toEntity();

  @override
  Future<Payee?> byNormalizedName(String normalizedName) async =>
      (await _dao.byNormalizedName(normalizedName))?.toEntity();

  @override
  Future<Result<Payee, Failure>> save(Payee payee) async {
    final existing = await _dao.byIdIncludingDeleted(payee.id);

    if (existing == null) {
      final duplicate = await _dao.byNormalizedName(payee.normalizedName);
      if (duplicate != null) {
        return Result.failure(
          ConflictFailure('A payee named "${payee.name}" already exists.'),
        );
      }
    }

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _dao.upsert(
      payeeToCompanion(payee, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );
    return Result.ok(payee);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    await _dao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }
}