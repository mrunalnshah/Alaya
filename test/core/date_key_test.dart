import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/time/date_key.dart';

void main() {
  group('DateKey.fromYmd — valid dates', () {
    test('packs year/month/day into yyyymmdd', () {
      expect(DateKey.fromYmd(2026, 7, 28).value, 20260728);
    });

    test('accepts the last day of a 31-day month', () {
      expect(DateKey.fromYmd(2026, 7, 31).value, 20260731);
    });

    test('accepts 29 February on a leap year', () {
      expect(DateKey.fromYmd(2024, 2, 29).value, 20240229);
    });
  });

  group('DateKey.fromYmd — invalid dates rejected', () {
    test('rejects 30 February', () {
      expect(() => DateKey.fromYmd(2026, 2, 30), throwsArgumentError);
    });

    test('rejects 29 February on a non-leap year', () {
      expect(() => DateKey.fromYmd(2026, 2, 29), throwsArgumentError);
    });

    test('rejects month 0 and month 13', () {
      expect(() => DateKey.fromYmd(2026, 0, 1), throwsArgumentError);
      expect(() => DateKey.fromYmd(2026, 13, 1), throwsArgumentError);
    });

    test('rejects day 0 and day 32', () {
      expect(() => DateKey.fromYmd(2026, 1, 0), throwsArgumentError);
      expect(() => DateKey.fromYmd(2026, 1, 32), throwsArgumentError);
    });

    test('rejects 31 April (a 30-day month)', () {
      expect(() => DateKey.fromYmd(2026, 4, 31), throwsArgumentError);
    });
  });

  group('DateKey component getters', () {
    test('year, month, day, monthKey all read back correctly', () {
      final date = DateKey.fromYmd(2026, 7, 28);
      expect(date.year, 2026);
      expect(date.month, 7);
      expect(date.day, 28);
      expect(date.monthKey, 202607);
    });

    test('weekday matches the known calendar weekday', () {
      // 28 July 2026 is a Tuesday (ISO weekday 2).
      expect(DateKey.fromYmd(2026, 7, 28).weekday, DateTime.tuesday);
    });
  });

  group('DateKey.addDays', () {
    test('stays within a month', () {
      expect(DateKey.fromYmd(2026, 7, 28).addDays(2), DateKey.fromYmd(2026, 7, 30));
    });

    test('crosses a month boundary', () {
      expect(DateKey.fromYmd(2026, 7, 31).addDays(1), DateKey.fromYmd(2026, 8, 1));
    });

    test('crosses a year boundary', () {
      expect(DateKey.fromYmd(2026, 12, 31).addDays(1), DateKey.fromYmd(2027, 1, 1));
    });

    test('crosses a leap-year 29 February correctly', () {
      expect(DateKey.fromYmd(2024, 2, 28).addDays(1), DateKey.fromYmd(2024, 2, 29));
      expect(DateKey.fromYmd(2024, 2, 29).addDays(1), DateKey.fromYmd(2024, 3, 1));
    });

    test('negative days moves backward', () {
      expect(DateKey.fromYmd(2026, 8, 1).addDays(-1), DateKey.fromYmd(2026, 7, 31));
    });
  });

  group('DateKey.diffDays', () {
    test('is positive when this date is later', () {
      final later = DateKey.fromYmd(2026, 8, 1);
      final earlier = DateKey.fromYmd(2026, 7, 28);
      expect(later.diffDays(earlier), 4);
    });

    test('is negative when this date is earlier', () {
      final later = DateKey.fromYmd(2026, 8, 1);
      final earlier = DateKey.fromYmd(2026, 7, 28);
      expect(earlier.diffDays(later), -4);
    });

    test('is zero for the same date', () {
      final date = DateKey.fromYmd(2026, 7, 28);
      expect(date.diffDays(date), 0);
    });
  });

  group('DateKey comparisons', () {
    test('compareTo, isBefore, isAfter, and operators agree', () {
      final earlier = DateKey.fromYmd(2026, 7, 28);
      final later = DateKey.fromYmd(2026, 8, 1);

      expect(earlier.compareTo(later), lessThan(0));
      expect(earlier.isBefore(later), isTrue);
      expect(later.isAfter(earlier), isTrue);
      expect(earlier < later, isTrue);
      expect(later > earlier, isTrue);
      expect(earlier <= earlier, isTrue);
      expect(earlier >= earlier, isTrue);
    });

    test('isWithin is inclusive of both bounds', () {
      final start = DateKey.fromYmd(2026, 7, 1);
      final end = DateKey.fromYmd(2026, 7, 31);
      expect(DateKey.fromYmd(2026, 7, 15).isWithin(start, end), isTrue);
      expect(start.isWithin(start, end), isTrue);
      expect(end.isWithin(start, end), isTrue);
      expect(DateKey.fromYmd(2026, 8, 1).isWithin(start, end), isFalse);
    });
  });

  group('DateKey.fromDateTime', () {
    test('uses the DateTime\'s own year/month/day fields', () {
      final localDateTime = DateTime(2026, 7, 28, 23, 45);
      expect(DateKey.fromDateTime(localDateTime), DateKey.fromYmd(2026, 7, 28));

      final utcDateTime = DateTime.utc(2027, 1, 1, 0, 15);
      expect(DateKey.fromDateTime(utcDateTime), DateKey.fromYmd(2027, 1, 1));
    });

    test('reads the local calendar date, never one shifted through .toUtc()', () {
      // Pick a local time-of-day placed right at whichever edge of the day would cross
      // into an adjacent UTC calendar day for this machine's actual UTC offset, so the
      // test is a real, portable proof rather than one that only works by coincidence.
      final offset = DateTime.now().timeZoneOffset;
      final local = offset.isNegative
          ? DateTime(2026, 7, 28, 23, 59)
          : DateTime(2026, 7, 28, 0, 1);

      expect(DateKey.fromDateTime(local), DateKey.fromYmd(2026, 7, 28));
    });
  });

  group('DateKey.toIso', () {
    test('renders as zero-padded yyyy-mm-dd', () {
      expect(DateKey.fromYmd(2026, 1, 5).toIso(), '2026-01-05');
    });
  });
}