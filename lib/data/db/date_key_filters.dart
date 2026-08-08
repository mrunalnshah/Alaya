import 'package:drift/drift.dart';

import 'package:alaya/core/time/date_key.dart';

/// `DateKey`-typed comparison helpers for the `INTEGER yyyymmdd` columns that store civil dates.
///
/// Exists because [DateKey] deliberately does **not** `implement int` (ARCH_1 §4.3): that is what
/// stops `dateKey + 1` compiling, since `20260731 + 1` is not a date. The same protection means a
/// `DateKey` cannot be handed to drift's `isBetweenValues` / `isSmallerOrEqualValue`, which operate
/// on a column's *SQL* type — `Expression<int>` — even when a type converter is attached. So every
/// date comparison needs an explicit `.value`, and doing that inline at each call site spreads the
/// unwrapping across every DAO that filters by date: batch expiry in 2B, due and warranty dates in
/// 2C, the calendar's bounded range in 4C, every analytics window in 7B.
///
/// These methods cross that boundary once, here, where it is visible and testable.
///
/// The `Date` in each name is load-bearing. This extension necessarily applies to any
/// `Expression<int>`, including `month_key` and every minor-unit amount column, so the names are
/// chosen to make `originalAmountMinor.isInDateRange(...)` read as obviously wrong. `month_key` is
/// `yyyymm`, not `yyyymmdd`, and has no wrapper type — compare it with plain ints.
extension DateKeyColumnFilters on Expression<int> {
  /// True where this date column is on or before [date] — inclusive.
  Expression<bool> isDateOnOrBefore(DateKey date) => isSmallerOrEqualValue(date.value);

  /// True where this date column is on or after [date] — inclusive.
  Expression<bool> isDateOnOrAfter(DateKey date) => isBiggerOrEqualValue(date.value);

  /// True where this date column is strictly before [date].
  Expression<bool> isDateBefore(DateKey date) => isSmallerThanValue(date.value);

  /// True where this date column is strictly after [date].
  Expression<bool> isDateAfter(DateKey date) => isBiggerThanValue(date.value);

  /// True where this date column falls within `[from, to]` — inclusive at both ends.
  ///
  /// The form every bounded range query should use, so it hits the date indexes from ARCH_2 §11
  /// rather than scanning.
  Expression<bool> isInDateRange(DateKey from, DateKey to) =>
      isBetweenValues(from.value, to.value);

  /// True where this date column is exactly [date].
  Expression<bool> isOnDate(DateKey date) => equals(date.value);
}