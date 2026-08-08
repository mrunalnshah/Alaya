import 'package:drift/drift.dart';

import 'package:alaya/core/time/date_key.dart';

/// Maps a [DateKey] to the single `INTEGER` column that stores it as `yyyymmdd` (Law L4).
/// Applied to every civil-date column in the schema; instants stay plain `int` epoch millis
/// and are never routed through this converter.
///
/// Uses the non-validating `DateKey(int)` constructor on read by design: a stored row is
/// already-validated data, and re-running [DateKey.fromYmd]'s calendar check on every row of
/// every query would cost a `DateTime` allocation per value for no benefit. Values enter the
/// database only through [DateKey.fromYmd] or [DateKey.fromDateTime], both of which validate.
final class DateKeyConverter extends TypeConverter<DateKey, int> {
  /// Creates the converter.
  const DateKeyConverter();

  @override
  DateKey fromSql(int fromDb) => DateKey(fromDb);

  @override
  int toSql(DateKey value) => value.value;
}