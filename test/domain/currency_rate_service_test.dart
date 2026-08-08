import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// Exercises ARCH_3 §1.2's USD pivot and §1.3's lookup rule.
///
/// Every test builds a `RateTable` from literals. That is possible because the table is pure — no
/// database, no mocks, no fakes — which is the whole reason the lookup rule lives there rather than
/// inside a repository.
void main() {
  // Frankfurter is ECB-backed and publishes no weekend rows. Friday the 24th, then Monday the 27th,
  // with the 25th and 26th deliberately absent — the gap the lookup rule exists for.
  final friday = DateKey.fromYmd(2026, 7, 24);
  final saturday = DateKey.fromYmd(2026, 7, 25);
  final sunday = DateKey.fromYmd(2026, 7, 26);
  final monday = DateKey.fromYmd(2026, 7, 27);

  const digits = {'USD': 2, 'INR': 2, 'EUR': 2, 'JPY': 0, 'CNY': 2};

  RateTable tableWithWeekendGap() => RateTable(
    rates: [
      UsdRate(quoteCode: 'INR', on: friday, rate: 83.10, rateRaw: '83.1'),
      UsdRate(quoteCode: 'INR', on: monday, rate: 83.30, rateRaw: '83.3'),
      UsdRate(quoteCode: 'JPY', on: friday, rate: 158.20, rateRaw: '158.2'),
      UsdRate(quoteCode: 'JPY', on: monday, rate: 158.60, rateRaw: '158.6'),
    ],
    decimalDigitsByCode: digits,
  );

  group('the weekend gap — §1.3 rule 3', () {
    test('a Saturday resolves to Friday\'s rate rather than failing', () {
      final leg = tableWithWeekendGap().legFor(code: 'INR', on: saturday);

      expect(leg, isNotNull, reason: 'a Saturday must resolve, not fail');
      expect(leg!.quotedOn, friday);
      expect(leg.rate, 83.10);
    });

    test('Friday\'s rate used on Saturday is EXACT, not approximate', () {
      final leg = tableWithWeekendGap().legFor(code: 'INR', on: saturday);

      // The rule is "greatest rateDateKey <= D". A hit is exact however old it is; `approximate` is
      // reserved for the case where no row on or before D exists at all. Marking a weekend
      // approximate would flag every Saturday transaction in the app as unreliable.
      expect(leg!.quality, RateQuality.exact);
    });

    test('Sunday also resolves to Friday, not forward to Monday', () {
      final leg = tableWithWeekendGap().legFor(code: 'INR', on: sunday);

      expect(leg!.quotedOn, friday);
      expect(leg.rate, 83.10, reason: 'never extrapolates forward to a rate not yet quoted');
    });

    test('Monday takes Monday\'s own rate', () {
      final leg = tableWithWeekendGap().legFor(code: 'INR', on: monday);

      expect(leg!.quotedOn, monday);
      expect(leg.rate, 83.30);
    });

    test('a rate months stale is still exact — the rule never expires a row', () {
      final leg = tableWithWeekendGap().legFor(code: 'INR', on: DateKey.fromYmd(2027, 3, 1));

      expect(leg!.quotedOn, monday);
      expect(leg.quality, RateQuality.exact);
    });

    test('a full conversion on a Saturday succeeds', () {
      final converted = tableWithWeekendGap().convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'USD',
        on: saturday,
      );

      expect(converted.quality, RateQuality.exact);
      expect(converted.isExcludedFromTotals, isFalse);
      expect(converted.rateDateKey, saturday,
          reason: 'an exact resolution reports the date asked for');
    });
  });

  group('USD pivot cross-rating — §1.2', () {
    test('INR to JPY is (USD to JPY) / (USD to INR)', () {
      final cross = tableWithWeekendGap().crossRate(from: 'INR', to: 'JPY', on: monday);

      expect(cross, isNotNull);
      expect(cross!.rate, closeTo(158.60 / 83.30, 1e-12));
      expect(cross.quality, RateQuality.exact);
    });

    test('1000 INR converts to roughly 1904 JPY', () {
      final converted = tableWithWeekendGap().convert(
        // 1000.00 INR in minor units.
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'JPY',
        on: monday,
      );

      expect(converted.converted, isNotNull);
      expect(converted.converted!.currencyCode, 'JPY');
      // JPY has zero decimal digits, so its minor unit IS the yen. 1000 x (158.6/83.3) = 1903.96,
      // which rounds to 1904.
      expect(converted.converted!.minor, closeTo(1904, 1));
    });

    test('the reverse rate is the reciprocal, so a round trip returns the original', () {
      final table = tableWithWeekendGap();
      final forward = table.crossRate(from: 'INR', to: 'JPY', on: monday)!;
      final back = table.crossRate(from: 'JPY', to: 'INR', on: monday)!;

      expect(back.rate, closeTo(1 / forward.rate, 1e-12));
      expect(1000 * forward.rate * back.rate, closeTo(1000, 1e-9));
    });

    test('USD needs no cached row — it is the pivot', () {
      final leg = RateTable.empty().legFor(code: 'USD', on: monday);

      expect(leg, isNotNull, reason: 'one USD is one USD on every date');
      expect(leg!.rate, 1);
      expect(leg.quality, RateQuality.exact);
    });

    test('converting a currency to itself needs no rate at all', () {
      final converted = RateTable.empty().convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'INR',
        on: monday,
      );

      expect(converted.quality, RateQuality.exact);
      expect(converted.converted, const Money(100000, 'INR'));
      expect(converted.isExcludedFromTotals, isFalse);
    });
  });

  group('no rate cached — §1.3 rule 4', () {
    test('a missing currency yields unconverted, never a zero', () {
      final converted = tableWithWeekendGap().convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'CNY',
        on: monday,
      );

      expect(converted.quality, RateQuality.unconverted);
      expect(converted.converted, isNull,
          reason: 'a zero would be counted in a total; null forces exclusion');
      expect(converted.isExcludedFromTotals, isTrue);
    });

    test('the original amount survives on an unconverted result', () {
      final converted = tableWithWeekendGap().convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'CNY',
        on: monday,
      );

      expect(converted.original, const Money(100000, 'INR'));
      expect(converted.display, const Money(100000, 'INR'),
          reason: 'the row still shows the amount the user typed');
    });

    test('an empty table converts nothing but throws nothing', () {
      final converted = RateTable.empty().convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'USD',
        on: monday,
      );

      expect(converted.isExcludedFromTotals, isTrue);
    });

    test('a known rate with unknown precision is excluded rather than guessed', () {
      final table = RateTable(
        rates: [UsdRate(quoteCode: 'INR', on: monday, rate: 83.30, rateRaw: '83.3')],
        // JPY's precision is absent, so its minor unit is unknown.
        decimalDigitsByCode: const {'INR': 2},
      );

      final converted = table.convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'JPY',
        on: monday,
      );

      expect(converted.isExcludedFromTotals, isTrue,
          reason: 'assuming 2 digits would misstate every yen figure by a factor of 100');
    });
  });

  group('approximate quality', () {
    test('a leg whose cache starts after the target falls forward and is approximate', () {
      final table = RateTable(
        rates: [
          UsdRate(quoteCode: 'INR', on: friday, rate: 83.10, rateRaw: '83.1'),
          // EUR's earliest row is a week after the date being asked about.
          UsdRate(quoteCode: 'EUR', on: DateKey.fromYmd(2026, 8, 1), rate: 0.92, rateRaw: '0.92'),
        ],
        decimalDigitsByCode: digits,
      );

      final cross = table.crossRate(from: 'INR', to: 'EUR', on: friday)!;

      expect(cross.quality, RateQuality.approximate);
      expect(cross.quotedOn, DateKey.fromYmd(2026, 8, 1),
          reason: 'reports the date actually used, which is the source of the doubt');
    });

    test('when both legs fall forward, the later date is reported', () {
      final table = RateTable(
        rates: [
          UsdRate(quoteCode: 'EUR', on: DateKey.fromYmd(2026, 8, 1), rate: 0.92, rateRaw: '0.92'),
          UsdRate(quoteCode: 'CNY', on: DateKey.fromYmd(2026, 9, 10), rate: 7.1, rateRaw: '7.1'),
        ],
        decimalDigitsByCode: digits,
      );

      final cross = table.crossRate(from: 'EUR', to: 'CNY', on: friday)!;

      expect(cross.quality, RateQuality.approximate);
      expect(cross.quotedOn, DateKey.fromYmd(2026, 9, 10),
          reason: 'the conversion cannot claim to be as of a date before its latest fallback');
    });

    test('one approximate leg makes the whole conversion approximate', () {
      final table = RateTable(
        rates: [
          UsdRate(quoteCode: 'INR', on: friday, rate: 83.10, rateRaw: '83.1'),
          UsdRate(quoteCode: 'EUR', on: DateKey.fromYmd(2026, 8, 1), rate: 0.92, rateRaw: '0.92'),
        ],
        decimalDigitsByCode: digits,
      );

      final converted = table.convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'EUR',
        on: friday,
      );

      expect(converted.quality, RateQuality.approximate);
      expect(converted.hasConversion, isTrue,
          reason: 'approximate still converts — it is indicative, not missing');
      expect(converted.isExcludedFromTotals, isFalse);
    });
  });

  group('syncDailyRates never throws and never blocks — §1.3 rule 2, Law L11', () {
    CurrencyRateService serviceWith({
      required RateSnapshotFetcher fetch,
      required RateSnapshotSaver save,
      NewestRateDateReader? newest,
      RateTableLoader? load,
    }) {
      return CurrencyRateService(
        loadTable: load ?? () async => RateTable.empty(),
        saveSnapshot: save,
        fetchSnapshot: fetch,
        newestCachedDate: newest ?? () async => null,
        clock: FixedClock(DateTime.utc(2026, 7, 27)),
      );
    }

    test('a client that always throws is swallowed', () async {
      var saved = false;
      final service = serviceWith(
        fetch: () async => throw const SocketExceptionStub(),
        save: (_) async => saved = true,
      );

      await expectLater(service.syncDailyRates(), completes);
      expect(saved, isFalse);
    });

    test('a client returning null is a no-op', () async {
      var saved = false;
      final service = serviceWith(fetch: () async => null, save: (_) async => saved = true);

      await service.syncDailyRates();

      expect(saved, isFalse);
    });

    test('an empty snapshot is not saved', () async {
      var saved = false;
      final service = serviceWith(
        fetch: () async =>
            RateSnapshot(on: monday, rates: const [], source: 'test'),
        save: (_) async => saved = true,
      );

      await service.syncDailyRates();

      expect(saved, isFalse, reason: 'an empty fetch must not overwrite a working cache');
    });

    test('a save that throws is swallowed too', () async {
      final service = serviceWith(
        fetch: () async => RateSnapshot(
          on: monday,
          rates: [UsdRate(quoteCode: 'INR', on: monday, rate: 83.3, rateRaw: '83.3')],
          source: 'test',
        ),
        save: (_) async => throw StateError('database is locked'),
      );

      await expectLater(service.syncDailyRates(), completes);
    });

    test('a reader that throws is swallowed too', () async {
      var fetched = false;
      final service = serviceWith(
        fetch: () async {
          fetched = true;
          return null;
        },
        save: (_) async {},
        newest: () async => throw StateError('database is locked'),
      );

      await expectLater(service.syncDailyRates(), completes);
      expect(fetched, isFalse, reason: 'it failed before reaching the network');
    });

    test('a successful fetch is saved once', () async {
      RateSnapshot? saved;
      final service = serviceWith(
        fetch: () async => RateSnapshot(
          on: monday,
          rates: [UsdRate(quoteCode: 'INR', on: monday, rate: 83.3, rateRaw: '83.3')],
          source: 'test',
        ),
        save: (snapshot) async => saved = snapshot,
      );

      await service.syncDailyRates();

      expect(saved, isNotNull);
      expect(saved!.rates.single.quoteCode, 'INR');
    });

    test('today\'s rates already cached means no fetch at all — one request per day', () async {
      var fetched = false;
      final service = serviceWith(
        fetch: () async {
          fetched = true;
          return null;
        },
        save: (_) async {},
        newest: () async => monday,
      );

      await service.syncDailyRates();

      expect(fetched, isFalse, reason: 'ARCH_3 §1.2 promises one request per day, forever');
    });

    test('a stale cache does trigger a fetch', () async {
      var fetched = false;
      final service = serviceWith(
        fetch: () async {
          fetched = true;
          return null;
        },
        save: (_) async {},
        newest: () async => friday,
      );

      await service.syncDailyRates();

      expect(fetched, isTrue);
    });
  });
}

/// Stands in for a network failure without importing `dart:io`, which a pure domain test should not
/// need.
class SocketExceptionStub implements Exception {
  /// Creates the stub.
  const SocketExceptionStub();
}
