/// View-model state for the units branch (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';

/// Every unit, system ones included.
final unitsSettingsProvider = StreamProvider<List<Unit>>(
  (ref) => ref.watch(unitRepositoryProvider).watchAll(),
);

/// One unit being edited, or null for a new one.
final unitDraftProvider = FutureProvider.autoDispose.family<Unit?, String?>((
  ref,
  code,
) async {
  if (code == null) return null;
  return ref.watch(unitRepositoryProvider).byCode(code);
});

/// How many base-milli units one base unit is.
///
/// **The whole of ARCH_4 R18 lives in this number.** `factorToBaseMilli` counts *thousandths* of the base
/// unit, so a kilogram is 1,000,000 and not 1,000 — and R18 was three separate sites that divided by 1,000
/// instead of by the unit's factor, which valued two kilos of potatoes at a hundred thousand rupees. The
/// editor asks the user for base units and multiplies here, in one place, rather than asking anybody to
/// think in thousandths.
const int milliPerBaseUnit = 1000;

/// Saves and deletes units.
final unitEditorProvider =
    NotifierProvider<UnitEditorNotifier, AsyncValue<void>>(
      UnitEditorNotifier.new,
    );

/// Writes a unit.
class UnitEditorNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Creates or replaces a unit from a factor expressed in **base units**.
  ///
  /// [baseUnitsPerUnit] is what the user typed — 1000 for a kilogram, 12 for a dozen, 14.79 for a
  /// tablespoon. It is multiplied by [milliPerBaseUnit] and rounded here, so no screen has to know that the
  /// column counts thousandths.
  Future<bool> save({
    required String code,
    required String displayName,
    required UnitCategory category,
    required double baseUnitsPerUnit,
    required int sortOrder,
    bool isSystem = false,
  }) async {
    state = const AsyncLoading<void>();
    final factor = (baseUnitsPerUnit * milliPerBaseUnit).round();
    if (factor <= 0) {
      // Guarded rather than trusted: a zero factor would make every quantity in that unit convert to nothing,
      // silently, and a division by it would take out the inventory valuation.
      state = AsyncError<void>(
        const _ZeroFactor(),
        StackTrace.current,
      );
      return false;
    }
    final result = await ref
        .read(unitRepositoryProvider)
        .save(
          Unit(
            code: code.trim(),
            category: category,
            factorToBaseMilli: factor,
            displayName: displayName.trim(),
            isSystem: isSystem,
            sortOrder: sortOrder,
          ),
        );
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  /// Deletes [code].
  Future<bool> delete(String code) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(unitRepositoryProvider).delete(code);
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  bool _settle(Object? failure) {
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}

/// Signals a factor of zero or less, so the screen can say so in its own words (Law U5).
class _ZeroFactor implements Exception {
  const _ZeroFactor();

  @override
  String toString() => 'factorMustBePositive';
}
