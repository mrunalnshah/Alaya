import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/entities/unit.dart';

/// Converts quantities between units of the same category, and validates user-defined units.
///
/// **There is no unit conversion of a stored quantity, and that is the point.** A `Qty` holds
/// milli-base-units plus a category (Law L2), so `2 kg` and `2000 g` are the *same* stored value —
/// only their display differs. Units matter at two boundaries: parsing text into base units
/// (`UnitConverter`) and formatting base units back out (`QtyFormatter`). What is left for this
/// engine is the genuinely arithmetic question — *how many of unit X is this quantity?* — plus
/// refusing the two conversions that must never happen.
///
/// Every operation is integer-only. No step touches a `double`, so no quantity can accumulate the
/// drift that made `0.1 + 0.2 != 0.3` a reason to store money in minor units in the first place.
final class UnitEngine {
  /// Creates the engine.
  const UnitEngine();

  /// Milli-base-units per one base unit — the scale every `factorToBaseMilli` is expressed in.
  static const int milliPerBaseUnit = 1000;

  /// The largest factor a user-defined unit may declare.
  ///
  /// One million milli-base-units is one thousand base units — a `tonne` against `g`, or a
  /// `kilolitre` against `ml`. Beyond that, `amountInUnitMilli`'s intermediate
  /// `milliBase * 1000` starts approaching the 64-bit ceiling for large quantities, and no
  /// household inventory needs it.
  static const int maxFactorToBaseMilli = 1000000000;

  /// How much of [unit] the quantity [quantity] represents, in **thousandths of [unit]**.
  ///
  /// Returns thousandths rather than whole units because the answer is frequently fractional and
  /// this engine will not return a `double`: `1.5 kg` is `1500` thousandths of a kilogram, exactly.
  /// Divide by [milliPerBaseUnit] at the display boundary, where `QtyFormatter` already does.
  ///
  /// Fails with a [BusinessRuleFailure] when [unit] measures a different category (Law L8) — a
  /// weight cannot be asked to express itself in millilitres — and with a [ValidationFailure] when
  /// the conversion would not be exact, rather than silently truncating. An inexact result means
  /// the user is asking for a unit the quantity cannot be cleanly expressed in, which is a real
  /// answer worth surfacing rather than rounding away.
  Result<int, Failure> amountInUnitMilli({
    required Qty quantity,
    required Unit unit,
  }) {
    if (unit.category != quantity.category) {
      return Result.failure(
        BusinessRuleFailure(
          'A ${quantity.category.name} quantity cannot be expressed in ${unit.code}, which '
              'measures ${unit.category.name}. There is no conversion between categories.',
          rule: 'crossCategoryConversion',
        ),
      );
    }
    if (unit.factorToBaseMilli <= 0) {
      return Result.failure(
        ValidationFailure(
          'Unit ${unit.code} has a non-positive factor and cannot be converted to.',
          field: 'factorToBaseMilli',
        ),
      );
    }

    final scaled = quantity.milliBase * milliPerBaseUnit;
    if (scaled % unit.factorToBaseMilli != 0) {
      return Result.failure(
        ValidationFailure(
          'This quantity cannot be expressed exactly in ${unit.code}.',
          field: 'unit',
        ),
      );
    }
    return Result.ok(scaled ~/ unit.factorToBaseMilli);
  }

  /// The same question as [amountInUnitMilli], but truncating toward zero instead of failing.
  ///
  /// For display and estimates only. Returns null on a category mismatch, because that is not a
  /// rounding problem — it is a question with no answer.
  int? amountInUnitMilliTruncating({
    required Qty quantity,
    required Unit unit,
  }) {
    if (unit.category != quantity.category) return null;
    if (unit.factorToBaseMilli <= 0) return null;
    return (quantity.milliBase * milliPerBaseUnit) ~/ unit.factorToBaseMilli;
  }

  /// Builds a `Qty` from [amountMilli] thousandths of [unit].
  ///
  /// The inverse of [amountInUnitMilli], and always exact: multiplying into base units cannot lose
  /// precision the way dividing out of them can. `1500` thousandths of `kg` becomes `1500000`
  /// milli-grams.
  Result<Qty, Failure> quantityFromUnit({
    required int amountMilli,
    required Unit unit,
  }) {
    if (unit.factorToBaseMilli <= 0) {
      return Result.failure(
        ValidationFailure(
          'Unit ${unit.code} has a non-positive factor.',
          field: 'factorToBaseMilli',
        ),
      );
    }
    final milliBase = amountMilli * unit.factorToBaseMilli ~/ milliPerBaseUnit;
    return Result.ok(Qty(milliBase, unit.category));
  }

  /// Converts a quantity expressed in [from] into thousandths of [to].
  ///
  /// A convenience over [quantityFromUnit] + [amountInUnitMilli] for the direct question "2 dozen
  /// is how many pieces?" — `2000` thousandths of `dozen` becomes `24000` thousandths of `pc`.
  Result<int, Failure> convert({
    required int amountMilli,
    required Unit from,
    required Unit to,
  }) {
    if (from.category != to.category) {
      return Result.failure(
        BusinessRuleFailure(
          'There is no conversion between ${from.category.name} and ${to.category.name}.',
          rule: 'crossCategoryConversion',
        ),
      );
    }
    final quantity = quantityFromUnit(amountMilli: amountMilli, unit: from);
    if (quantity.isFailure) return Result.failure(quantity.failureOrNull!);
    return amountInUnitMilli(quantity: quantity.valueOrNull!, unit: to);
  }

  /// Validates a unit the user defined themselves.
  ///
  /// ARCH_1 §5.3 is explicit that a unit needs a factor the user can *state exactly*. If they
  /// cannot — "one packet of noodles" — the correct action is a new Item, not a unit with an
  /// invented factor, because every quantity recorded against a wrong factor is silently wrong and
  /// no migration can recover the intent.
  ///
  /// Rejects a non-positive factor, one above [maxFactorToBaseMilli], an empty or overlong code,
  /// and a code that collides with a seeded system unit under case folding — `KG` and `kg` would
  /// be two rows the user cannot tell apart.
  Result<void, Failure> validateUserUnit({
    required Unit unit,
    required Iterable<Unit> existingUnits,
  }) {
    final code = unit.code.trim();
    if (code.isEmpty) {
      return const Result.failure(ValidationFailure('A unit needs a code.', field: 'code'));
    }
    if (code.length > 12) {
      return const Result.failure(
        ValidationFailure('A unit code must be 12 characters or fewer.', field: 'code'),
      );
    }
    if (unit.displayName.trim().isEmpty) {
      return const Result.failure(
        ValidationFailure('A unit needs a display name.', field: 'displayName'),
      );
    }
    if (unit.factorToBaseMilli <= 0) {
      return const Result.failure(
        ValidationFailure(
          'A unit needs a positive factor to its category\'s base unit. If you cannot state one '
              'exactly, create a separate Item instead.',
          field: 'factorToBaseMilli',
        ),
      );
    }
    if (unit.factorToBaseMilli > maxFactorToBaseMilli) {
      return const Result.failure(
        ValidationFailure(
          'That factor is too large to convert safely.',
          field: 'factorToBaseMilli',
        ),
      );
    }

    final folded = code.toLowerCase();
    for (final existing in existingUnits) {
      if (existing.code == unit.code) continue;
      if (existing.code.toLowerCase() == folded) {
        return Result.failure(
          ConflictFailure('A unit with the code "${existing.code}" already exists.'),
        );
      }
    }
    return const Result.ok(null);
  }
}
