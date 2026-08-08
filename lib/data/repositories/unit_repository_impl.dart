import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/unit_dao.dart';
import 'package:alaya/data/repositories/mappers/unit_mapper.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/domain/repositories/unit_repository.dart';

/// `UnitRepository` backed by `UnitDao`.
final class UnitRepositoryImpl implements UnitRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const UnitRepositoryImpl(this._dao, this._clock);

  final UnitDao _dao;
  final Clock _clock;

  @override
  Stream<List<Unit>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Unit>> watchByCategory(UnitCategory category) =>
      _dao.watchByCategory(category).map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Unit?> byCode(String code) async => (await _dao.byCode(code))?.toEntity();

  @override
  Future<Map<String, int>> factorsByCode() => _dao.factorsByCode();

  @override
  Future<Map<String, UnitCategory>> categoriesByCode() => _dao.categoriesByCode();

  @override
  Future<Result<Unit, Failure>> save(Unit unit) async {
    if (unit.factorToBaseMilli <= 0) {
      return const Result.failure(
        ValidationFailure(
          'A unit needs a positive, exact factor to its category\'s base unit. If you cannot '
              'state one, create a separate Item instead (ARCH_1 §5.3).',
          field: 'factorToBaseMilli',
        ),
      );
    }

    final existing = await _dao.byCode(unit.code);
    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _dao.upsert(
      unitToCompanion(unit, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );
    return Result.ok(unit);
  }

  @override
  Future<Result<void, Failure>> delete(String code) async {
    final rowsChanged =
    await _dao.softDeleteUserUnit(code: code, nowUtcMillis: _clock.nowUtcMillis());
    if (rowsChanged == 0) {
      return const Result.failure(
        BusinessRuleFailure('System units cannot be deleted.', rule: 'systemProtected'),
      );
    }
    return const Result.ok(null);
  }
}