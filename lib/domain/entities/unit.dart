import 'package:alaya/core/quantity/unit_category.dart';

/// A unit of measure with an exact integer factor to its category's base unit.
class Unit {
  /// Creates a unit.
  const Unit({
    required this.code,
    required this.category,
    required this.factorToBaseMilli,
    required this.displayName,
    required this.isSystem,
    required this.sortOrder,
  });

  /// Unit code, e.g. `kg`, `ml`, `dozen`.
  final String code;

  /// Which of the three fixed categories this unit measures.
  final UnitCategory category;

  /// Exact milli-base units per one of this unit — `kg` is `1000000`, `dozen` is `12000`.
  /// Integer by design: no step of a unit conversion touches a double (Law L2).
  final int factorToBaseMilli;

  /// Human-readable name for pickers.
  final String displayName;

  /// Whether this unit was seeded; system units cannot be deleted.
  final bool isSystem;

  /// Manual ordering within pickers.
  final int sortOrder;

  /// True if this unit *is* its category's base unit — `g`, `ml` or `pc`.
  bool get isBaseUnit => factorToBaseMilli == 1000;

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  Unit copyWith({
    String? code,
    UnitCategory? category,
    int? factorToBaseMilli,
    String? displayName,
    bool? isSystem,
    int? sortOrder,
  }) {
    return Unit(
      code: code ?? this.code,
      category: category ?? this.category,
      factorToBaseMilli: factorToBaseMilli ?? this.factorToBaseMilli,
      displayName: displayName ?? this.displayName,
      isSystem: isSystem ?? this.isSystem,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Unit &&
          other.code == code &&
          other.category == category &&
          other.factorToBaseMilli == factorToBaseMilli &&
          other.displayName == displayName &&
          other.isSystem == isSystem &&
          other.sortOrder == sortOrder;

  @override
  int get hashCode => Object.hashAll(
      [code, category, factorToBaseMilli, displayName, isSystem, sortOrder]);

  @override
  String toString() => 'Unit($code)';
}