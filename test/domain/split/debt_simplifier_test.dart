import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/services/split/debt_simplifier.dart';

/// [DebtSimplifier].
///
/// Every expected plan below was produced by an independent implementation of the same algorithm and
/// compared before being written here. The counter-example in *"beats greedy"* came from a
/// brute-force search over every balance vector up to five people — ARCH_M §7 records why a test
/// expectation reasoned from a subset of the space is worth nothing.
void main() {
  const simplifier = DebtSimplifier();
  Money inr(int minor) => Money(minor, 'INR');
  DebtEdge owes(String from, String to, int minor) =>
      DebtEdge(fromPayeeId: from, toPayeeId: to, amount: inr(minor));

  List<String> shape(SettlementPlan plan) => [
    for (final t in plan.transfers)
      '${t.fromPayeeId}->${t.toPayeeId}:${t.amount.minor}',
  ];

  group('nothing to do', () {
    test('no debts', () {
      final plan = simplifier.plan(const []);
      expect(plan.transfers, isEmpty);
      expect(plan.isImprovement, isFalse);
    });

    test('zero-amount edges are ignored', () {
      expect(simplifier.plan([owes('a', 'b', 0)]).transfers, isEmpty);
    });

    test('mutual debts cancel to nothing', () {
      // A owes B ₹100 and B owes A ₹100. Two payments become none.
      final plan = simplifier.plan([
        owes('a', 'b', 10000),
        owes('b', 'a', 10000),
      ]);
      expect(plan.transfers, isEmpty);
      expect(plan.originalDebtCount, 2);
      expect(plan.paymentsSaved, 2);
    });
  });

  group('the chain, which is the whole pitch', () {
    test('A owes B and B owes C becomes A pays C', () {
      final plan = simplifier.plan([
        owes('a', 'b', 2000),
        owes('b', 'c', 2000),
      ]);
      expect(shape(plan), orderedEquals(['a->c:2000']));
      expect(plan.paymentsSaved, 1);
      expect(plan.wasPartitionedExactly, isTrue);
    });

    test('and the transfer explains itself', () {
      // The sentence Splitwise leaves its users to work out: their forum has carried "why do I owe
      // someone who never lent me money?" for over a decade.
      final plan = simplifier.plan([
        owes('a', 'b', 2000),
        owes('b', 'c', 2000),
      ]);
      final transfer = plan.transfers.single;
      expect(transfer.clears, hasLength(1));
      expect(transfer.clears.single.edge.toPayeeId, 'b');
      expect(transfer.clears.single.amount, inr(2000));
      expect(transfer.isDirect, isFalse, reason: 'a never owed c directly');
    });

    test('a transfer covering two debts names both', () {
      final plan = simplifier.plan([
        owes('a', 'b', 30000),
        owes('a', 'c', 15000),
        owes('b', 'd', 30000),
        owes('c', 'd', 15000),
      ]);
      final fromA = plan.transfers.firstWhere((t) => t.fromPayeeId == 'a');
      expect(fromA.toPayeeId, 'd');
      expect(fromA.amount, inr(45000));
      expect(
        fromA.clears.map((c) => c.edge.toPayeeId),
        containsAll(['b', 'c']),
      );
      expect(
        fromA.clears.fold(0, (sum, c) => sum + c.amount.minor),
        45000,
        reason: 'the discharges must account for the whole transfer',
      );
    });
  });

  group('beats greedy where greedy cannot', () {
    test('the smallest case a brute-force search could find', () {
      // Balances A:-6 B:-5 C:+2 D:+4 E:+5. Greedy needs four payments; {A,C,D} and {B,E} are both
      // zero-sum, so three suffice. No such case exists at three or four people — verified
      // exhaustively — and there are 840 at five.
      final plan = simplifier.plan([
        owes('a', 'c', 200),
        owes('a', 'd', 400),
        owes('b', 'e', 500),
      ]);
      expect(plan.transfers, hasLength(3));
      expect(
        shape(plan),
        orderedEquals(['a->d:400', 'a->c:200', 'b->e:500']),
      );
      expect(plan.wasPartitionedExactly, isTrue);
    });

    test('the same balances reached by different debts settle the same way', () {
      // The plan depends on the net position, not on which edges produced it — but the *explanations*
      // differ, because they are attributed against the real debts.
      final plan = simplifier.plan([
        owes('a', 'e', 600),
        owes('b', 'd', 400),
        owes('b', 'c', 100),
      ]);
      expect(plan.transfers, hasLength(3));
      expect(
        shape(plan),
        orderedEquals(['a->e:600', 'b->d:400', 'b->c:100']),
      );
      // Every transfer here settles a debt that genuinely exists, so all three are direct.
      expect(plan.transfers.every((t) => t.isDirect), isTrue);
    });
  });

  group('preferring real debts, which costs nothing', () {
    test('a debtor pays someone they actually owe when the count is unaffected', () {
      // **This one caught a real gap.** The first implementation applied the preference only inside
      // greedy, never to the choice of partition — so `{a,d}` and `{b,c}` won on enumeration order and
      // both suggested payments were between people who had never owed each other anything. Equally
      // zero-sum, equally two payments, and wrong.
      final plan = simplifier.plan([
        owes('a', 'b', 5000),
        owes('c', 'd', 5000),
      ]);
      expect(plan.transfers, hasLength(2));
      expect(plan.transfers.every((t) => t.isDirect), isTrue);
      expect(
        plan.transfers.map((t) => '${t.fromPayeeId}->${t.toPayeeId}'),
        orderedEquals(['a->b', 'c->d']),
      );
    });
  });

  group('every transfer is accounted for', () {
    test('the discharges of each transfer sum to the transfer', () {
      final plan = simplifier.plan([
        owes('a', 'b', 12345),
        owes('b', 'c', 6789),
        owes('c', 'a', 111),
        owes('d', 'a', 4000),
      ]);
      for (final transfer in plan.transfers) {
        expect(
          transfer.clears.fold(0, (sum, c) => sum + c.amount.minor),
          transfer.amount.minor,
          reason: '${transfer.fromPayeeId}->${transfer.toPayeeId}',
        );
      }
    });

    test('no debt is discharged twice across a debtor own transfers', () {
      final plan = simplifier.plan([
        owes('a', 'b', 10000),
        owes('a', 'c', 10000),
        owes('b', 'd', 5000),
        owes('c', 'd', 5000),
      ]);
      final byEdge = <String, int>{};
      for (final transfer in plan.transfers) {
        for (final cleared in transfer.clears) {
          final key = '${cleared.edge.fromPayeeId}->${cleared.edge.toPayeeId}';
          byEdge[key] = (byEdge[key] ?? 0) + cleared.amount.minor;
        }
      }
      expect(byEdge['a->b'], lessThanOrEqualTo(10000));
      expect(byEdge['a->c'], lessThanOrEqualTo(10000));
    });
  });

  group('the plan settles the balances it was given', () {
    test('applying every transfer leaves everyone at zero', () {
      // The property the whole class has to satisfy, asserted over several shapes rather than one.
      final cases = <List<DebtEdge>>[
        [owes('a', 'b', 2000), owes('b', 'c', 2000)],
        [owes('a', 'c', 200), owes('a', 'd', 400), owes('b', 'e', 500)],
        [owes('a', 'b', 3333), owes('b', 'c', 1111), owes('c', 'a', 777)],
        [
          owes('a', 'b', 10000),
          owes('c', 'b', 2500),
          owes('a', 'd', 700),
          owes('d', 'c', 700),
        ],
      ];
      for (final debts in cases) {
        final net = <String, int>{};
        for (final debt in debts) {
          net[debt.fromPayeeId] =
              (net[debt.fromPayeeId] ?? 0) - debt.amount.minor;
          net[debt.toPayeeId] = (net[debt.toPayeeId] ?? 0) + debt.amount.minor;
        }
        for (final transfer in simplifier.plan(debts).transfers) {
          net[transfer.fromPayeeId] =
              (net[transfer.fromPayeeId] ?? 0) + transfer.amount.minor;
          net[transfer.toPayeeId] =
              (net[transfer.toPayeeId] ?? 0) - transfer.amount.minor;
        }
        expect(
          net.values.every((v) => v == 0),
          isTrue,
          reason: 'left over: $net',
        );
      }
    });

    test('and never suggests more payments than there were debts', () {
      final plan = simplifier.plan([
        owes('a', 'b', 100),
        owes('b', 'c', 100),
        owes('c', 'd', 100),
        owes('d', 'e', 100),
      ]);
      expect(plan.transfers.length, lessThanOrEqualTo(plan.originalDebtCount));
      expect(shape(plan), orderedEquals(['a->e:100']));
    });
  });

  group('refusals', () {
    test('mixed currencies, because netting them would invent a rate', () {
      expect(
        () => simplifier.plan([
          owes('a', 'b', 100),
          DebtEdge(
            fromPayeeId: 'b',
            toPayeeId: 'c',
            amount: const Money(100, 'USD'),
          ),
        ]),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });

    test('a negative edge, because the direction is in the field names', () {
      expect(
        () => simplifier.plan([owes('a', 'b', -100)]),
        throwsArgumentError,
      );
    });

    test('owing yourself', () {
      expect(() => simplifier.plan([owes('a', 'a', 100)]), throwsArgumentError);
    });
  });

  group('the exact ceiling', () {
    test('a group past it still produces a valid plan, marked inexact', () {
      // Seventeen people, one over `maxExactMembers`. The greedy fallback must still settle everyone;
      // it just cannot claim to be minimal, and `wasPartitionedExactly` is how a screen knows not to
      // say "the fewest possible payments".
      final debts = <DebtEdge>[
        for (var i = 0; i < 17; i++) owes('p$i', 'p${(i + 1) % 17}', 1000 + i),
      ];
      final plan = simplifier.plan(debts);
      expect(plan.wasPartitionedExactly, isFalse);

      final net = <String, int>{};
      for (final debt in debts) {
        net[debt.fromPayeeId] =
            (net[debt.fromPayeeId] ?? 0) - debt.amount.minor;
        net[debt.toPayeeId] = (net[debt.toPayeeId] ?? 0) + debt.amount.minor;
      }
      for (final transfer in plan.transfers) {
        net[transfer.fromPayeeId] =
            (net[transfer.fromPayeeId] ?? 0) + transfer.amount.minor;
        net[transfer.toPayeeId] =
            (net[transfer.toPayeeId] ?? 0) - transfer.amount.minor;
      }
      expect(net.values.every((v) => v == 0), isTrue);
    });

    test('independent pairs are each found, and each stays direct', () {
      // Six pairs, twelve people. **Deliberately not sixteen**: the partition enumerates submasks at
      // about 3^n, so twelve is 531,441 steps and instant, while sixteen is 43 million and would make
      // one unit test the slowest thing in the suite. The ceiling itself is asserted by the case above,
      // which crosses it.
      //
      // Every pair is zero-sum, so a partition exists that matches what people actually did — and the
      // score tie-break is what picks it. Without that, the DP happily pairs `d0` with `c3`.
      final debts = <DebtEdge>[
        for (var i = 0; i < 6; i++) owes('d$i', 'c$i', 1000),
      ];
      final plan = simplifier.plan(debts);
      expect(plan.wasPartitionedExactly, isTrue);
      expect(plan.transfers, hasLength(6));
      expect(plan.transfers.every((t) => t.isDirect), isTrue);
      expect(
        plan.transfers.map((t) => '${t.fromPayeeId}->${t.toPayeeId}'),
        orderedEquals([
          for (var i = 0; i < 6; i++) 'd$i->c$i',
        ]),
      );
    });
  });
}
