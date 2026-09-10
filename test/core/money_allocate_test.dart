import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';

/// [Money.allocate] and [Money.allocateEvenly].
///
/// **A separate file from `money_test.dart` on purpose.** That file covers arithmetic, comparison and
/// conversion and needed no change; putting allocation there would bury a new guarantee inside a
/// regression suite for existing behaviour.
///
/// Every expected vector below was recomputed in an independent implementation before it was written
/// here — ARCH_M §7 records why that is not optional.
void main() {
  Money inr(int minor) => Money(minor, 'INR');

  /// The guarantee the whole type rests on.
  void expectExact(Money total, List<int> weights) {
    final parts = total.allocate(weights);
    final sum = parts.fold(Money.zero(total.currencyCode), (a, b) => a + b);
    expect(
      sum,
      total,
      reason: 'allocate($weights) of $total summed to $sum',
    );
  }

  group('the sum is always exactly the input', () {
    test('across a wide sweep of amounts and part counts', () {
      // The property, not a sample. Anything that loses or invents a paisa fails here.
      for (var minor = 0; minor <= 2000; minor++) {
        for (var parts = 1; parts <= 9; parts++) {
          final shares = inr(minor).allocateEvenly(parts);
          final sum = shares.fold(0, (a, b) => a + b.minor);
          expect(sum, minor, reason: '$minor into $parts');
        }
      }
    });

    test('with lopsided and zero weights', () {
      expectExact(inr(100000), [9999, 1]);
      expectExact(inr(100000), [1, 1, 0]);
      expectExact(inr(7), [3, 3, 3, 3, 3]);
      expectExact(inr(1), [1, 1, 1, 1]);
    });

    test('for negative amounts, so a refund splits like a charge', () {
      expectExact(inr(-100000), [1, 1, 1]);
      expectExact(inr(-7), [2, 3]);
    });
  });

  group('the vectors', () {
    test('a thousand rupees three ways', () {
      // Not 333.33 three times. The stray two paise go to the largest remainders.
      expect(
        inr(100000).allocateEvenly(3).map((m) => m.minor),
        orderedEquals([33334, 33333, 33333]),
      );
    });

    test('a thousand rupees seven ways', () {
      expect(
        inr(100000).allocateEvenly(7).map((m) => m.minor),
        orderedEquals([14286, 14286, 14286, 14286, 14286, 14285, 14285]),
      );
    });

    test('one paisa between two people', () {
      // Somebody gets it. Nobody gets half.
      expect(
        inr(1).allocateEvenly(2).map((m) => m.minor),
        orderedEquals([1, 0]),
      );
    });

    test('fifty thirty twenty, in basis points', () {
      expect(
        inr(100000).allocate([5000, 3000, 2000]).map((m) => m.minor),
        orderedEquals([50000, 30000, 20000]),
      );
    });

    test('a refund of a thousand three ways', () {
      expect(
        inr(-100000).allocateEvenly(3).map((m) => m.minor),
        orderedEquals([-33334, -33333, -33333]),
      );
    });
  });

  group('a zero weight pays nothing, ever', () {
    test('and never collects a leftover unit', () {
      // The guest who did not eat. This holds because the leftover count is always strictly less
      // than the number of parts with a non-zero remainder, so the sort never reaches a zero.
      for (var minor = 1; minor <= 500; minor++) {
        final parts = inr(minor).allocate([1, 1, 1, 0]);
        expect(parts.last, inr(0), reason: 'minor $minor gave ${parts.last}');
      }
    });
  });

  group('determinism', () {
    test('the same weights always place the stray units identically', () {
      // A split shown on one screen and recomputed on the next must agree about who owes the extra
      // paisa, or the two screens disagree about the amount.
      for (var i = 0; i < 50; i++) {
        expect(
          inr(100000).allocate([1, 1, 1]).map((m) => m.minor),
          orderedEquals([33334, 33333, 33333]),
        );
      }
    });

    test('equal remainders break toward the earlier position', () {
      expect(
        inr(10).allocate([1, 1, 1]).map((m) => m.minor),
        orderedEquals([4, 3, 3]),
      );
    });
  });

  group('zero and one', () {
    test('nothing splits into nothing', () {
      expect(
        inr(0).allocateEvenly(4).map((m) => m.minor),
        orderedEquals([0, 0, 0, 0]),
      );
    });

    test('one participant takes the lot', () {
      expect(inr(12345).allocateEvenly(1).single, inr(12345));
    });
  });

  group('the currency travels', () {
    test('every part keeps the input currency', () {
      for (final part in Money(999, 'USD').allocateEvenly(4)) {
        expect(part.currencyCode, 'USD');
      }
    });
  });

  group('programming errors, not user states', () {
    test('empty weights', () {
      expect(() => inr(100).allocate([]), throwsArgumentError);
    });

    test('a negative weight', () {
      expect(() => inr(100).allocate([1, -1]), throwsArgumentError);
    });

    test('all weights zero', () {
      expect(() => inr(100).allocate([0, 0]), throwsArgumentError);
    });

    test('a non-positive part count', () {
      expect(() => inr(100).allocateEvenly(0), throwsArgumentError);
      expect(() => inr(100).allocateEvenly(-3), throwsArgumentError);
    });
  });
}
