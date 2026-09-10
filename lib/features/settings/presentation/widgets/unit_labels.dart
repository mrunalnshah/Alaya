import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/settings/providers/unit_settings_providers.dart';

/// The name of each quantity category.
///
/// Exhaustive without a `default`, so ARCH_1 §5.3's promise that there is never a fourth category is enforced
/// by the compiler here as well as by the enum.
String unitCategoryLabel(AlayaStrings strings, UnitCategory category) =>
    switch (category) {
      UnitCategory.weight => strings.unitCategoryWeight,
      UnitCategory.volume => strings.unitCategoryVolume,
      UnitCategory.count => strings.unitCategoryCount,
    };

/// How many base units one [unit] is, formatted for reading.
///
/// **Divides by [milliPerBaseUnit], which is the one arithmetic ARCH_4 R18 was about.** The column counts
/// thousandths of the base unit, so a kilogram is stored as 1,000,000 and shown as 1,000 g. Trailing zeros are
/// dropped, so a tablespoon reads *14.79 ml* rather than *14.790*.
String unitBaseAmountLabel(Unit unit) {
  final base = unit.factorToBaseMilli / milliPerBaseUnit;
  final formatter = base == base.roundToDouble()
      ? NumberFormat.decimalPattern()
      : NumberFormat('#,##0.###');
  return formatter.format(base);
}

/// The plural name of a category's base unit — "grams", "millilitres", "pieces".
///
/// The *name*, not the code, because the editor's question reads "How many grams is one kilogram?" and a
/// question phrased with `g` in it asks the user to decode an abbreviation before they can answer.
String unitBaseUnitName(AlayaStrings strings, UnitCategory category) =>
    switch (category) {
      UnitCategory.weight => strings.unitBaseGrams,
      UnitCategory.volume => strings.unitBaseMillilitres,
      UnitCategory.count => strings.unitBasePieces,
    };
