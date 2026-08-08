import 'date_key.dart';

/// Human day labels for a ledger's date headers.
///
/// A ledger is scanned, not read: the eye is looking for *when*, and `2026-08-01` forces the reader to
/// work out that it means today. "Today" and "Yesterday" are recognised without parsing, and beyond
/// that a weekday plus a short date is enough — a ledger row's year is almost never in doubt, and
/// printing it on every header is noise that crowds out the amount.
///
/// Lives in `core/time` rather than a widget so the ledger, the calendar and any future export agree on
/// what a given date is called.
extension DateKeyLabels on DateKey {
  /// Short month names, indexed 1-12.
  static const List<String> monthNames = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Short weekday names, indexed 1-7 with Monday first, matching `DateTime.weekday`.
  static const List<String> weekdayNames = [
    '',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// `1 Aug` — no year.
  String get shortLabel => '$day ${monthNames[month]}';

  /// `Fri 1 Aug` — no year.
  String get weekdayLabel =>
      '${weekdayNames[weekday]} $day ${monthNames[month]}';

  /// `1 Aug 2026` — with year, for a date far from now.
  String get fullLabel => '$day ${monthNames[month]} $year';

  /// The label a ledger day header should show, relative to [today].
  ///
  /// Today and yesterday are named. Anything else in the same year gets a weekday and date; a different
  /// year gets the year too, because that is the one case where omitting it could mislead.
  String headerLabel(DateKey today) {
    final delta = today.diffDays(this);
    if (delta == 0) return 'Today';
    if (delta == 1) return 'Yesterday';
    if (year != today.year) return fullLabel;
    return weekdayLabel;
  }

  /// `August 2026`, for a period header.
  String get monthLabel => '${monthNames[month]} $year';
}
