import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// Exercises the net-worth rule: what counts, what converts, and what is excluded.
///
/// `BalanceService.totalFrom` is pure given a rate table, so none of this needs a database.
void main() {
  const service = BalanceService();
  final asOf = DateKey.fromYmd(2026, 7, 27);

  const digits = {'USD': 2, 'INR': 2, 'EUR': 2, 'JPY': 0, 'CNY': 2};

  RateTable table() => RateTable(
    rates: [
      UsdRate(quoteCode: 'INR', on: asOf, rate: 83.30, rateRaw: '83.3'),
      UsdRate(quoteCode: 'EUR', on: asOf, rate: 0.92, rateRaw: '0.92'),
      UsdRate(quoteCode: 'JPY', on: asOf, rate: 158.60, rateRaw: '158.6'),
    ],
    decimalDigitsByCode: digits,
  );

  AccountBalanceInput account(
      String id,
      int minor,
      String code, {
        bool includeInNetWorth = true,
      }) =>
      AccountBalanceInput(
        accountId: id,
        balance: Money(minor, code),
        includeInNetWorth: includeInNetWorth,
      );

  group('what counts toward net worth', () {
    test('an account with includeInNetWorth false is excluded from the total', () {
      final result = service.totalFrom(
        balances: [
          account('cash', 400000, 'INR'),
          account('loan', 999999, 'INR', includeInNetWorth: false),
        ],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, const Money(400000, 'INR'));
      expect(result.unconvertedCount, 0,
          reason: 'deliberately excluded is not the same as unconvertible');
    });

    test('an ARCHIVED account still counts — archive keeps money in net worth', () {
      // ARCH_3 §4's table is explicit: `isArchived` is "counted in totals? yes". Only `deletedAt`
      // removes money. A closed bank account holding a balance is retired, not gone — and the
      // repository filters soft-deleted rows before this service ever sees them, so archived-ness
      // is deliberately not a filter here.
      final result = service.totalFrom(
        balances: [
          account('cash', 400000, 'INR'),
          account('old-bank', 250000, 'INR'),
        ],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, const Money(650000, 'INR'));
    });

    test('no accounts at all is a zero in the home currency, not an error', () {
      final result = service.totalFrom(
        balances: const [],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, Money.zero('INR'));
      expect(result.isComplete, isTrue);
    });

    test('a negative balance reduces the total', () {
      final result = service.totalFrom(
        balances: [account('cash', 400000, 'INR'), account('overdrawn', -150000, 'INR')],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, const Money(250000, 'INR'));
    });
  });

  group('conversion', () {
    test('a balance already in the home currency needs no rate', () {
      final result = service.totalFrom(
        balances: [account('cash', 400000, 'INR')],
        // An entirely empty table: a single-currency user must never see an unconverted chip.
        table: RateTable.empty(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, const Money(400000, 'INR'));
      expect(result.unconvertedCount, 0);
      expect(result.isComplete, isTrue);
    });

    test('mixed currencies convert into one home total', () {
      final result = service.totalFrom(
        balances: [
          account('inr', 100000, 'INR'), // 1000.00 INR
          account('usd', 10000, 'USD'), // 100.00 USD -> 8330.00 INR
        ],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      // 1000 + (100 x 83.30) = 9330.00 INR
      expect(result.total.currencyCode, 'INR');
      expect(result.total.minor, closeTo(933000, 100));
      expect(result.unconvertedCount, 0);
    });

    test('a zero-decimal currency converts without being inflated', () {
      final result = service.totalFrom(
        // 10,000 yen. JPY has no minor unit, so `minor` IS the yen count.
        balances: [account('jpy', 10000, 'JPY')],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      // 10000 JPY / 158.60 x 83.30 = about 5251 INR = 525,100 minor units.
      expect(result.total.minor, closeTo(525100, 2000));
    });
  });

  group('unconverted amounts are EXCLUDED, never counted as zero', () {
    test('a balance with no cached rate raises the count and leaves the total alone', () {
      final result = service.totalFrom(
        balances: [
          account('inr', 400000, 'INR'),
          // CNY has no row in the table at all.
          account('cny', 700000, 'CNY'),
        ],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, const Money(400000, 'INR'),
          reason: 'the CNY balance is left out entirely');
      expect(result.unconvertedCount, 1);
      expect(result.isComplete, isFalse);
    });

    test('counting it as zero would be indistinguishable from an empty account', () {
      final excluded = service.totalFrom(
        balances: [account('inr', 400000, 'INR'), account('cny', 700000, 'CNY')],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );
      final asIfEmpty = service.totalFrom(
        balances: [account('inr', 400000, 'INR'), account('cny', 0, 'CNY')],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      // The totals match, which is exactly why the count has to exist — without it these two very
      // different situations would look identical to the user.
      expect(excluded.total, asIfEmpty.total);
      expect(excluded.unconvertedCount, 1);
      expect(asIfEmpty.unconvertedCount, 1);
    });

    test('every balance unconvertible gives a zero total and a full count', () {
      final result = service.totalFrom(
        balances: [account('cny', 700000, 'CNY'), account('brl', 500000, 'BRL')],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, Money.zero('INR'));
      expect(result.unconvertedCount, 2);
      expect(result.isComplete, isFalse);
    });

    test('an excluded account that is also unconvertible does not raise the count', () {
      final result = service.totalFrom(
        balances: [account('cny', 700000, 'CNY', includeInNetWorth: false)],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.unconvertedCount, 0,
          reason: 'it was never going to be in the total, so it is not missing from it');
    });
  });

  group('approximate rates', () {
    test('an approximate leg marks the whole headline approximate but still totals', () {
      final staleTable = RateTable(
        rates: [
          UsdRate(quoteCode: 'INR', on: asOf, rate: 83.30, rateRaw: '83.3'),
          // EUR's earliest row is after the date asked about, so the leg falls forward.
          UsdRate(
            quoteCode: 'EUR',
            on: DateKey.fromYmd(2026, 9, 1),
            rate: 0.92,
            rateRaw: '0.92',
          ),
        ],
        decimalDigitsByCode: digits,
      );

      final result = service.totalFrom(
        balances: [account('inr', 100000, 'INR'), account('eur', 10000, 'EUR')],
        table: staleTable,
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.isApproximate, isTrue);
      expect(result.unconvertedCount, 0, reason: 'approximate still converts');
      expect(result.total.minor, greaterThan(100000));
    });

    test('all-exact rates leave the headline exact', () {
      final result = service.totalFrom(
        balances: [account('inr', 100000, 'INR'), account('usd', 10000, 'USD')],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.isApproximate, isFalse);
    });
  });

  group('totalsByCurrency — the honest answer with no rates', () {
    test('groups per currency without converting anything', () {
      final totals = service.totalsByCurrency([
        account('a', 400000, 'INR'),
        account('b', 250000, 'INR'),
        account('c', 10000, 'USD'),
      ]);

      expect(totals['INR'], const Money(650000, 'INR'));
      expect(totals['USD'], const Money(10000, 'USD'));
    });

    test('respects includeInNetWorth', () {
      final totals = service.totalsByCurrency([
        account('a', 400000, 'INR'),
        account('b', 999999, 'INR', includeInNetWorth: false),
      ]);

      expect(totals['INR'], const Money(400000, 'INR'));
    });

    test('never adds across currencies', () {
      final totals = service.totalsByCurrency([
        account('a', 400000, 'INR'),
        account('c', 10000, 'JPY'),
      ]);

      expect(totals.keys.toSet(), {'INR', 'JPY'},
          reason: 'adding rupees to yen is exactly what this method exists to prevent');
    });
  });
}