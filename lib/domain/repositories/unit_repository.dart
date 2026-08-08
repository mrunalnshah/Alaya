import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/entities/unit.dart';

/// Reads and writes units of measure.
abstract interface class UnitRepository {
  /// Emits every unit in display order.
  Stream<List<Unit>> watchAll();

  /// Emits the units measuring [category].
  ///
  /// A quantity picker must never offer a unit from another category — cross-category conversion
  /// does not exist (Law L8), so offering `ml` for a weight item would produce a value nothing can
  /// convert.
  Stream<List<Unit>> watchByCategory(UnitCategory category);

  /// Reads one unit by code.
  Future<Unit?> byCode(String code);

  /// Reads `code -> factorToBaseMilli` for every unit.
  Future<Map<String, int>> factorsByCode();

  /// Reads `code -> category`, which is what lets a mapper resolve a quantity's category from a
  /// bare unit code when a row has no linked item.
  Future<Map<String, UnitCategory>> categoriesByCode();

  /// Creates or updates a user-defined unit.
  ///
  /// Fails with a [ValidationFailure] when the factor is not a positive integer: a unit whose
  /// factor cannot be stated exactly should be a separate item instead (ARCH_1 §5.3).
  Future<Result<Unit, Failure>> save(Unit unit);

  /// Deletes a user-defined unit. Fails for a system unit.
  Future<Result<void, Failure>> delete(String code);
}