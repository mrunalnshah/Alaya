import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';

/// Turns the keys `AnalyticsPort` grouped by into labels a reader can understand.
///
/// **The adapter groups by enum name, so `slice.label` for a subtype is `grocery`.** Rendering it
/// would put an untranslated identifier on screen (Law U5). Every key whose label is *not* data goes
/// through here; keys whose labels are data — a payee, a tag, an item — render their label directly.
abstract final class AnalyticsLabels {
  /// The localised name for a `TransactionSubtype` key.
  ///
  /// **Delegates to `TransactionRow.subtypeLabel`, which is public for exactly this reason.** A tenth
  /// switch over nine subtypes is a tenth thing to update when one is renamed, and ARCH_5 §10's
  /// objection to re-deriving a rule at a call site does not stop at colours.
  ///
  /// Falls back to the raw key rather than throwing: an unrecognised name means the database holds a
  /// value this build does not know, which is what Law L13's fallback-safe storage exists to survive.
  /// A cosmetic label is not worth a crash on the analytics screen.
  static String subtype(AlayaStrings strings, String key) {
    for (final value in TransactionSubtype.values) {
      if (value.name == key) return TransactionRow.subtypeLabel(strings, value);
    }
    return key;
  }

  /// The localised name for query 18's two sides.
  static String recurringSide(AlayaStrings strings, String key) =>
      key == 'recurring'
      ? strings.analyticsRecurring
      : strings.analyticsDiscretionary;

  /// The localised name of a reporting window.
  ///
  /// Exhaustive over `DateRangePreset` on purpose: adding a preset to `AnalyticsRange.presets`
  /// without labelling it should be a compile error here, not a chip rendering its own enum name.
  /// Every key already exists in the ARB from earlier phases — this phase adds none.
  static String range(AlayaStrings strings, DateRangePreset preset) =>
      switch (preset) {
        DateRangePreset.today => strings.rangeToday,
        DateRangePreset.last7Days => strings.rangeLast7Days,
        DateRangePreset.last30Days => strings.rangeLast30Days,
        DateRangePreset.thisMonth => strings.rangeThisMonth,
        DateRangePreset.lastMonth => strings.rangeLastMonth,
        DateRangePreset.thisYear => strings.rangeThisYear,
        DateRangePreset.allTime => strings.rangeAllTime,
        DateRangePreset.custom => strings.rangeCustom,
      };

  /// The short axis label for a heatmap bucket.
  ///
  /// **Weekdays come from `MaterialLocalizations.narrowWeekdays`, not from the ARB**, which is how
  /// 7A's month grid labels its own weekday row — locale-correct in every locale Flutter ships
  /// without seven strings a translator has to be asked for.
  ///
  /// That list is Sunday-first while ARCH_3 §5.1's buckets are 1-7 Monday-first, so `bucket % 7` maps
  /// between them: Monday's 1 lands on index 1 and Sunday's 7 wraps to index 0. It is the same
  /// expression 7A uses for a `DateTime.weekday`, for the same reason.
  ///
  /// A day-of-month bucket is its own number and needs no translation.
  static String bucket(
    BuildContext context,
    int bucket, {
    required bool byWeekday,
  }) {
    if (!byWeekday) return '$bucket';
    return MaterialLocalizations.of(context).narrowWeekdays[bucket %
        DateTime.daysPerWeek];
  }

  /// The localised name of a `UnitCategory`.
  ///
  /// **A third copy of this switch, and that is worth recording rather than hiding.** 6B already holds
  /// two private ones — `_categoryLabel` in its line-item editor and again in its item editor — so the
  /// mapping had drifted into duplication before this phase arrived. Reaching either would mean making
  /// a private helper public in a file this phase has no other reason to carry.
  ///
  /// It cannot live on `UnitCategory` itself: that is in `core/`, and `AlayaStrings` is in `app/`
  /// (Law L12). The right home is one helper in `shared/`, which ARCH_5 §8 does not permit this phase
  /// to add without a record — so it is filed as a finding for Phase 9's sweep instead of taken here.
  static String unitCategory(AlayaStrings strings, UnitCategory category) =>
      switch (category) {
        UnitCategory.weight => strings.unitCategoryWeight,
        UnitCategory.volume => strings.unitCategoryVolume,
        UnitCategory.count => strings.unitCategoryCount,
      };

  /// [share] as a whole-number percentage in the active locale.
  ///
  /// One definition, because five surfaces state a share and five `NumberFormat` calls is five places
  /// for the decimal count to drift — the same objection ARCH_5 §10 raises to re-deriving red/green at
  /// a call site.
  ///
  /// Whole numbers: "34%" is the insight, and "33.7%" implies a precision a ratio of two rounded
  /// totals does not have.
  static String percent(BuildContext context, double share) =>
      NumberFormat.decimalPercentPattern(
        locale: Localizations.localeOf(context).toLanguageTag(),
        decimalDigits: 0,
      ).format(share);
}
