import 'package:drift/drift.dart' show Value;

import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/entities/unit.dart';

/// Converts between `UnitRow` and the domain `Unit` entity.
extension UnitMapper on UnitRow {
  /// Maps this row to a domain entity.
  Unit toEntity() => Unit(
    code: code,
    category: category,
    factorToBaseMilli: factorToBaseMilli,
    displayName: displayName,
    isSystem: isSystem,
    sortOrder: sortOrder,
  );
}

/// Builds the companion for [unit], given the `(createdAt, updatedAt)` pair
/// `WriteTimestamps.resolve` decided.
UnitsCompanion unitToCompanion(
    Unit unit, {
      required int createdAt,
      required int updatedAt,
    }) {
  return UnitsCompanion.insert(
    code: unit.code,
    category: unit.category,
    factorToBaseMilli: unit.factorToBaseMilli,
    displayName: unit.displayName,
    isSystem: unit.isSystem,
    sortOrder: unit.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: const Value(null),
  );
}