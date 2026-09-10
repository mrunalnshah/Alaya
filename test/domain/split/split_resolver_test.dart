import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/services/split/split_resolver.dart';

/// [SplitResolver].
///
/// Every figure recomputed independently before it was asserted.
void main() {
  const resolver = SplitResolver();
  Money inr(int minor) => Money(minor, 'INR');

  Map<String, int> minorByPayee(SplitResolution r) => {
    for (final share in r.shares) share.payeeId: share.amount.minor,
  };

  group('equal', () {
    test('divides exactly, stray paise and all', () {
      final r = resolver.resolve(
        total: inr(100000),
        inputs: const [
          ShareInput.equal('a'),
          ShareInput.equal('b'),
          ShareInput.equal('c'),
        ],
      );
      expect(minorByPayee(r), {'a': 33334, 'b': 33333, 'c': 33333});
      expect(r.isExact, isTrue);
      expect(r.unallocated, inr(0));
    });
  });

  group('shares', () {
    test('a double weight takes twice as much', () {
      final r = resolver.resolve(
        total: inr(40000),
        inputs: const [
          ShareInput.shares('a', 2),
          ShareInput.shares('b', 1),
          ShareInput.shares('c', 1),
        ],
      );
      expect(minorByPayee(r), {'a': 20000, 'b': 10000, 'c': 10000});
      expect(r.isExact, isTrue);
    });

    test('a zero weight pays nothing', () {
      final r = resolver.resolve(
        total: inr(30000),
        inputs: const [
          ShareInput.shares('a', 1),
          ShareInput.shares('b', 1),
          ShareInput.shares('c', 0),
        ],
      );
      expect(minorByPayee(r), {'a': 15000, 'b': 15000, 'c': 0});
    });
  });

  group('percent', () {
    test('basis points of the total', () {
      final r = resolver.resolve(
        total: inr(100000),
        inputs: const [
          ShareInput.percent('a', 5000),
          ShareInput.percent('b', 3000),
          ShareInput.percent('c', 2000),
        ],
      );
      expect(minorByPayee(r), {'a': 50000, 'b': 30000, 'c': 20000});
      expect(r.isExact, isTrue);
    });

    test('percentages short of 100 leave a remainder, not a fudge', () {
      // **The commitment.** 90% assigned means 10% unassigned, surfaced. Spreading the missing 10%
      // across whoever happens to be listed would charge somebody for a number they never typed.
      final r = resolver.resolve(
        total: inr(100000),
        inputs: const [
          ShareInput.percent('a', 5000),
          ShareInput.percent('b', 4000),
        ],
      );
      expect(minorByPayee(r), {'a': 50000, 'b': 40000});
      expect(r.unallocated, inr(10000));
      expect(r.isExact, isFalse);
      expect(r.isOverAllocated, isFalse);
    });

    test('percentages over 100 report an overshoot rather than clamping', () {
      final r = resolver.resolve(
        total: inr(100000),
        inputs: const [
          ShareInput.percent('a', 7000),
          ShareInput.percent('b', 7000),
        ],
      );
      expect(r.isOverAllocated, isTrue);
      expect(r.unallocated.isNegative, isTrue);
    });
  });

  group('exact', () {
    test('amounts are taken as typed', () {
      final r = resolver.resolve(
        total: inr(100000),
        inputs: const [
          ShareInput.exact('a', 60000),
          ShareInput.exact('b', 40000),
        ],
      );
      expect(minorByPayee(r), {'a': 60000, 'b': 40000});
      expect(r.isExact, isTrue);
    });

    test('a shortfall surfaces, exactly as transaction lines do', () {
      final r = resolver.resolve(
        total: inr(50000),
        inputs: const [ShareInput.exact('a', 48000)],
      );
      expect(r.unallocated, inr(2000));
    });
  });

  group('mixed — exact off the top, the rest split', () {
    test('Ravi covers his own dessert and the remainder divides equally', () {
      // The instruction people actually give: "the dessert was Ravi's, split the rest between us."
      // Splitwise calls this an adjustment and buries it; here it is one input kind beside another.
      final r = resolver.resolve(
        total: inr(160000),
        inputs: const [
          ShareInput.exact('ravi', 40000),
          ShareInput.equal('a'),
          ShareInput.equal('b'),
          ShareInput.equal('c'),
        ],
      );
      expect(minorByPayee(r), {
        'ravi': 40000,
        'a': 40000,
        'b': 40000,
        'c': 40000,
      });
      expect(r.isExact, isTrue);
    });

    test('the remainder divides by weight when weights are given', () {
      final r = resolver.resolve(
        total: inr(100000),
        inputs: const [
          ShareInput.exact('a', 40000),
          ShareInput.shares('b', 3),
          ShareInput.shares('c', 1),
        ],
      );
      expect(minorByPayee(r), {'a': 40000, 'b': 45000, 'c': 15000});
      expect(r.isExact, isTrue);
    });

    test('exact amounts exceeding the total leave nothing for the weights', () {
      // Over-allocated, and the weighted participants sit at zero rather than going negative — a
      // negative share would read as somebody being owed money by a bill they are paying.
      final r = resolver.resolve(
        total: inr(50000),
        inputs: const [
          ShareInput.exact('a', 60000),
          ShareInput.equal('b'),
        ],
      );
      expect(minorByPayee(r)['b'], 0);
      expect(r.isOverAllocated, isTrue);
    });
  });

  group('per line — the itemised split', () {
    test('the dessert is one person, the platter is everyone', () {
      // ₹1,200 platter four ways, ₹400 dessert for Ravi alone, ₹200 delivery by weight.
      final r = resolver.resolvePerLine(
        total: inr(180000),
        lines: const [
          SplitLine(
            lineNo: 1,
            amount: Money(120000, 'INR'),
            inputs: [
              ShareInput.equal('ravi'),
              ShareInput.equal('a'),
              ShareInput.equal('b'),
              ShareInput.equal('c'),
            ],
          ),
          SplitLine(
            lineNo: 2,
            amount: Money(40000, 'INR'),
            inputs: [ShareInput.equal('ravi')],
          ),
          SplitLine(
            lineNo: 3,
            amount: Money(20000, 'INR'),
            inputs: [
              ShareInput.shares('ravi', 1),
              ShareInput.shares('a', 1),
              ShareInput.shares('b', 1),
              ShareInput.shares('c', 1),
            ],
          ),
        ],
      );
      expect(minorByPayee(r), {
        'ravi': 30000 + 40000 + 5000,
        'a': 35000,
        'b': 35000,
        'c': 35000,
      });
      expect(r.isExact, isTrue);
      // Ravi's share carries every input that produced it, so the editor can show all three lines.
      expect(r.shares.first.inputs, hasLength(3));
    });

    test('a tip nobody assigned shows up as unallocated', () {
      // `transactions.originalAmountMinor` is the source of truth and lines are optional detail
      // (ARCH_2 §4.2). A bill of ₹1,000 with ₹900 of lines is ₹100 nobody has claimed.
      final r = resolver.resolvePerLine(
        total: inr(100000),
        lines: const [
          SplitLine(
            lineNo: 1,
            amount: Money(90000, 'INR'),
            inputs: [ShareInput.equal('a'), ShareInput.equal('b')],
          ),
        ],
      );
      expect(minorByPayee(r), {'a': 45000, 'b': 45000});
      expect(r.unallocated, inr(10000));
    });

    test('a line in another currency is refused', () {
      expect(
        () => resolver.resolvePerLine(
          total: inr(100000),
          lines: const [
            SplitLine(
              lineNo: 1,
              amount: Money(1000, 'USD'),
              inputs: [ShareInput.equal('a')],
            ),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('refusals', () {
    test('no participants', () {
      expect(
        () => resolver.resolve(total: inr(100), inputs: const []),
        throwsArgumentError,
      );
    });

    test('the same person twice', () {
      expect(
        () => resolver.resolve(
          total: inr(100),
          inputs: const [ShareInput.equal('a'), ShareInput.equal('a')],
        ),
        throwsArgumentError,
      );
    });

    test('percent mixed with weights, which has no single reading', () {
      expect(
        () => resolver.resolve(
          total: inr(100),
          inputs: const [ShareInput.percent('a', 5000), ShareInput.equal('b')],
        ),
        throwsArgumentError,
      );
    });

    test('a negative weight', () {
      expect(
        () => resolver.resolve(
          total: inr(100),
          inputs: const [ShareInput.shares('a', -1), ShareInput.shares('b', 1)],
        ),
        throwsArgumentError,
      );
    });
  });

  group('a mismatch is a state, not a throw', () {
    test('mid-edit percentages resolve rather than fail', () {
      // The editor calls this on every keystroke. A resolver that threw on 30% would be unusable.
      for (final points in [0, 1, 999, 3000, 9999, 10001, 20000]) {
        final r = resolver.resolve(
          total: inr(100000),
          inputs: [ShareInput.percent('a', points)],
        );
        expect(r.shares, hasLength(1));
      }
    });
  });

  group('extras — the restaurant case', () {
    test('a drink bought for one person is theirs, and the rest still splits', () {
      // **The case the first version of this class could not express.** A ₹5,000 dinner where ₹400 of
      // it was Ravi's round: the ₹400 is his, the remaining ₹4,600 splits four ways, and Ravi pays
      // ₹1,550 while everybody else pays ₹1,150.
      //
      // With `exact` this was impossible — an exact amount *replaces* a share, so Ravi would have owed
      // ₹400 and nothing at all toward the food.
      final r = resolver.resolve(
        total: inr(500000),
        inputs: const [
          ShareInput.equal('me'),
          ShareInput.extra('ravi', 40000),
          ShareInput.equal('a'),
          ShareInput.equal('b'),
        ],
      );

      expect(minorByPayee(r), {
        'me': 115000,
        'ravi': 155000,
        'a': 115000,
        'b': 115000,
      });
      expect(r.isExact, isTrue);
    });

    test('the parts are carried, so a screen can show the arithmetic', () {
      // "₹1,150 + ₹400 drinks" rather than a bare ₹1,550. A total a person cannot decompose is one
      // they argue with.
      final r = resolver.resolve(
        total: inr(500000),
        inputs: const [
          ShareInput.equal('me'),
          ShareInput.extra('ravi', 40000),
          ShareInput.equal('a'),
          ShareInput.equal('b'),
        ],
      );

      final ravi = r.shares.firstWhere((s) => s.payeeId == 'ravi');
      expect(ravi.extra, inr(40000));
      expect(ravi.fromRemainder, inr(115000));
      expect(ravi.amount, inr(155000));

      final me = r.shares.firstWhere((s) => s.payeeId == 'me');
      expect(me.extra, isNull, reason: 'no extra means no line to explain');
    });

    test(
      "'I'll put in 2,000 and we'll split the rest' is the same operation",
      () {
        // Identical arithmetic from the other direction. One input kind, two features — which is why
        // there is no separate "subsidy" concept to learn, name or test.
        final r = resolver.resolve(
          total: inr(500000),
          inputs: const [
            ShareInput.extra('me', 200000),
            ShareInput.equal('ravi'),
            ShareInput.equal('a'),
            ShareInput.equal('b'),
          ],
        );

        expect(minorByPayee(r), {
          'me': 275000,
          'ravi': 75000,
          'a': 75000,
          'b': 75000,
        });
        expect(r.isExact, isTrue);
      },
    );

    test('two extras on one bill', () {
      // Ravi's drinks and a contribution from the payer, together. ₹5,000 − ₹400 − ₹2,000 = ₹2,600,
      // four ways at ₹650.
      final r = resolver.resolve(
        total: inr(500000),
        inputs: const [
          ShareInput.extra('me', 200000),
          ShareInput.extra('ravi', 40000),
          ShareInput.equal('a'),
          ShareInput.equal('b'),
        ],
      );

      expect(minorByPayee(r), {
        'me': 265000,
        'ravi': 105000,
        'a': 65000,
        'b': 65000,
      });
      expect(r.isExact, isTrue);
    });

    test('an extra alongside custom weights', () {
      // ₹1,000 bill, ₹100 is Ravi's, the remaining ₹900 splits 2:1:1 — Ravi's weight is one, because
      // an extra says what somebody additionally owes and not how the rest is divided.
      final r = resolver.resolve(
        total: inr(100000),
        inputs: const [
          ShareInput.shares('me', 2),
          ShareInput.extra('ravi', 10000),
          ShareInput.shares('a', 1),
        ],
      );

      expect(minorByPayee(r), {'me': 45000, 'ravi': 32500, 'a': 22500});
      expect(r.isExact, isTrue);
    });

    test('an extra beside an exact amount, which does not share the rest', () {
      // Priya owes exactly ₹500 and is finished; Ravi's ₹100 is his and he still takes a share of the
      // remaining ₹400 with me.
      final r = resolver.resolve(
        total: inr(100000),
        inputs: const [
          ShareInput.exact('priya', 50000),
          ShareInput.extra('ravi', 10000),
          ShareInput.equal('me'),
        ],
      );

      expect(minorByPayee(r), {'priya': 50000, 'ravi': 30000, 'me': 20000});
      expect(r.isExact, isTrue);
    });

    test(
      'an extra larger than the bill over-allocates rather than going negative',
      () {
        // Nobody gets a negative share — that would read as being *owed* money by a bill they are
        // paying. The overshoot surfaces in `unallocated` instead.
        final r = resolver.resolve(
          total: inr(10000),
          inputs: const [
            ShareInput.extra('ravi', 50000),
            ShareInput.equal('me'),
          ],
        );

        expect(minorByPayee(r)['me'], 0);
        expect(minorByPayee(r)['ravi'], 50000);
        expect(r.isOverAllocated, isTrue);
      },
    );

    test('extras count as weights, so percent still refuses to mix', () {
      expect(
        () => resolver.resolve(
          total: inr(100000),
          inputs: const [
            ShareInput.percent('a', 5000),
            ShareInput.extra('b', 1000),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('a negative extra is refused', () {
      expect(
        () => resolver.resolve(
          total: inr(100000),
          inputs: const [
            ShareInput.extra('a', -100),
            ShareInput.equal('b'),
          ],
        ),
        throwsArgumentError,
      );
    });
  });
}
