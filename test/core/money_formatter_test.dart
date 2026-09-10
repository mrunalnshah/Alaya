import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/money/money_formatter.dart';

void main() {
  const formatter = MoneyFormatter();

  String rupees(int minor, {bool showPlusSign = false}) => formatter.format(
    Money(minor, 'INR'),
    decimalDigits: 2,
    symbol: 'INR',
    showPlusSign: showPlusSign,
  );

  group('symbol gap', () {
    test('separates the symbol from the digits', () {
      expect(rupees(500000), 'INR 5,000.00');
    });

    test('the sign leads, before the symbol', () {
      expect(rupees(-50000), '-INR 500.00');
      expect(rupees(50000, showPlusSign: true), '+INR 500.00');
    });

    test('is an ordinary space, so a test can assert it by eye', () {
      expect(MoneyFormatter.symbolGap, ' ');
      expect(rupees(100).contains('\u00A0'), isFalse);
    });
  });

  group('Indian grouping', () {
    // The reason this formatter does not use NumberFormat: `intl` supports one uniform group
    // size, so it cannot produce 2-2-3. These are the boundaries where that difference appears.
    test('groups by thousand, then by hundred', () {
      expect(rupees(100000), 'INR 1,000.00');
      expect(rupees(1000000), 'INR 10,000.00');
      expect(rupees(10000000), 'INR 1,00,000.00');
      expect(rupees(100000000), 'INR 10,00,000.00');
      expect(rupees(1000000000), 'INR 1,00,00,000.00');
    });

    test('leaves three digits and fewer ungrouped', () {
      expect(rupees(99900), 'INR 999.00');
      expect(rupees(100), 'INR 1.00');
      expect(rupees(0), 'INR 0.00');
    });

    test('a Western locale groups by three throughout', () {
      expect(
        formatter.format(
          const Money(1000000000, 'USD'),
          decimalDigits: 2,
          symbol: 'USD',
          localeTag: 'en_US',
        ),
        'USD 10,000,000.00',
      );
    });
  });

  group('decimal digits come from the currency', () {
    test('zero-decimal currencies render no fractional part', () {
      expect(
        formatter.format(
          const Money(1200, 'JPY'),
          decimalDigits: 0,
          symbol: 'JPY',
        ),
        'JPY 1,200',
      );
    });

    test('a fraction is padded to the currency width', () {
      expect(rupees(50005), 'INR 500.05');
      expect(rupees(50050), 'INR 500.50');
    });
  });

  group('the integer is never touched', () {
    test('formatting is display-only and does not round', () {
      // Law L1: money is integer minor units end to end. A formatter that rounded would make the
      // displayed figure disagree with the stored one, which is the bug this rule exists to prevent.
      const money = Money(123456789, 'INR');
      formatter.format(money, decimalDigits: 2, symbol: 'INR');
      expect(money.minor, 123456789);
    });

    test('a negative amount keeps its magnitude', () {
      expect(rupees(-123456789), '-INR 12,34,567.89');
    });
  });
}
