import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/money/rounding.dart';

void main() {
  group('Money construction', () {
    test('stores minor units and currency code as given', () {
      const money = Money(12345, 'INR');
      expect(money.minor, 12345);
      expect(money.currencyCode, 'INR');
    });

    test('Money.zero is zero in the given currency', () {
      const zero = Money.zero('INR');
      expect(zero.minor, 0);
      expect(zero.isZero, isTrue);
      expect(zero.currencyCode, 'INR');
    });
  });

  group('Money arithmetic (same currency)', () {
    test('addition sums minor units', () {
      expect(const Money(100, 'INR') + const Money(50, 'INR'), const Money(150, 'INR'));
    });

    test('subtraction can go negative', () {
      expect(const Money(50, 'INR') - const Money(100, 'INR'), const Money(-50, 'INR'));
    });

    test('multiplication by an int scales minor units', () {
      expect(const Money(100, 'INR') * 3, const Money(300, 'INR'));
    });

    test('unary minus negates minor units, keeping currency', () {
      expect(-const Money(100, 'INR'), const Money(-100, 'INR'));
    });

    test('abs returns a positive amount regardless of sign', () {
      expect(const Money(-100, 'INR').abs(), const Money(100, 'INR'));
      expect(const Money(100, 'INR').abs(), const Money(100, 'INR'));
    });

    test('isNegative, isPositive, isZero classify correctly', () {
      expect(const Money(-1, 'INR').isNegative, isTrue);
      expect(const Money(1, 'INR').isPositive, isTrue);
      expect(const Money(0, 'INR').isZero, isTrue);
    });
  });

  group('Money cross-currency arithmetic throws', () {
    test('addition across currencies throws CurrencyMismatchError', () {
      expect(
            () => const Money(100, 'INR') + const Money(100, 'USD'),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });

    test('subtraction across currencies throws CurrencyMismatchError', () {
      expect(
            () => const Money(100, 'INR') - const Money(100, 'USD'),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });
  });

  group('Money comparisons (same currency)', () {
    test('compareTo orders by minor units', () {
      expect(const Money(100, 'INR').compareTo(const Money(200, 'INR')), lessThan(0));
      expect(const Money(200, 'INR').compareTo(const Money(100, 'INR')), greaterThan(0));
      expect(const Money(100, 'INR').compareTo(const Money(100, 'INR')), 0);
    });

    test('< <= > >= behave as expected', () {
      expect(const Money(100, 'INR') < const Money(200, 'INR'), isTrue);
      expect(const Money(100, 'INR') <= const Money(100, 'INR'), isTrue);
      expect(const Money(200, 'INR') > const Money(100, 'INR'), isTrue);
      expect(const Money(100, 'INR') >= const Money(100, 'INR'), isTrue);
    });
  });

  group('Money cross-currency comparison throws', () {
    test('compareTo across currencies throws CurrencyMismatchError', () {
      expect(
            () => const Money(100, 'INR').compareTo(const Money(100, 'USD')),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });

    test('< across currencies throws CurrencyMismatchError', () {
      expect(
            () => const Money(100, 'INR') < const Money(100, 'USD'),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });
  });

  group('Money equality and hashCode', () {
    test('equal minor units and currency are equal', () {
      expect(const Money(100, 'INR'), const Money(100, 'INR'));
      expect(const Money(100, 'INR').hashCode, const Money(100, 'INR').hashCode);
    });

    test('different currency is never equal even with the same minor units', () {
      expect(const Money(100, 'INR') == const Money(100, 'USD'), isFalse);
    });

    test('different minor units are never equal', () {
      expect(const Money(100, 'INR') == const Money(200, 'INR'), isFalse);
    });
  });

  group('Money.convert', () {
    test('same decimal digits, simple rate', () {
      final converted = const Money(10000, 'INR').convert(
        rate: 0.5,
        toCurrencyCode: 'XXX',
        fromDecimalDigits: 2,
        toDecimalDigits: 2,
      );
      expect(converted, const Money(5000, 'XXX'));
    });

    test('converting to a zero-decimal currency (JPY) scales correctly', () {
      final converted = const Money(10000, 'INR').convert(
        rate: 1.9,
        toCurrencyCode: 'JPY',
        fromDecimalDigits: 2,
        toDecimalDigits: 0,
      );
      expect(converted, const Money(190, 'JPY'));
    });

    test('does not mutate the original amount (Law L9)', () {
      const original = Money(10000, 'INR');
      original.convert(
        rate: 2,
        toCurrencyCode: 'USD',
        fromDecimalDigits: 2,
        toDecimalDigits: 2,
      );
      expect(original.minor, 10000);
      expect(original.currencyCode, 'INR');
    });

    test('halfUp rounds an exact .5 away from zero', () {
      final positive = const Money(1, 'INR').convert(
        rate: 2.5,
        toCurrencyCode: 'XXX',
        fromDecimalDigits: 0,
        toDecimalDigits: 0,
      );
      expect(positive.minor, 3);

      final negative = const Money(-1, 'INR').convert(
        rate: 2.5,
        toCurrencyCode: 'XXX',
        fromDecimalDigits: 0,
        toDecimalDigits: 0,
      );
      expect(negative.minor, -3);
    });

    test('halfEven rounds an exact .5 to the nearest even integer', () {
      final roundsDown = const Money(1, 'INR').convert(
        rate: 2.5,
        toCurrencyCode: 'XXX',
        fromDecimalDigits: 0,
        toDecimalDigits: 0,
        rounding: MoneyRounding.halfEven,
      );
      expect(roundsDown.minor, 2); // 2 is already even

      final roundsUp = const Money(1, 'INR').convert(
        rate: 3.5,
        toCurrencyCode: 'XXX',
        fromDecimalDigits: 0,
        toDecimalDigits: 0,
        rounding: MoneyRounding.halfEven,
      );
      expect(roundsUp.minor, 4); // 3 is odd, rounds up to even 4
    });

    test('halfDown rounds an exact .5 toward zero', () {
      final result = const Money(1, 'INR').convert(
        rate: 2.5,
        toCurrencyCode: 'XXX',
        fromDecimalDigits: 0,
        toDecimalDigits: 0,
        rounding: MoneyRounding.halfDown,
      );
      expect(result.minor, 2);
    });
  });
}