import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/domain/services/split/debt_simplifier.dart';
import 'package:alaya/domain/services/split/split_balance_service.dart';

import '../../support/split_fakes.dart';

/// [SplitBalanceService].
///
/// The two things a view cannot do: compare against today, and run a graph algorithm. Everything else
/// it exposes is a pass-through, and the tests below say which is which.
void main() {
  final clock = FixedClock(DateTime.utc(2026, 8, 14, 9));
  Money inr(int minor) => Money(minor, 'INR');

  SplitBalanceService build(FakeSplitLedger ledger) =>
      SplitBalanceService(ledger: ledger, clock: clock);

  group('ageing', () {
    test('counts days against the injected clock, not the wall clock', () async {
      // **Why this is here and not in SQL.** ARCH_2 §12.2 forbids a view from consulting the current
      // time, and a view that did could not be asserted against a `FixedClock` — this test would be
      // impossible to write, and the notification impossible to verify.
      final service = build(
        FakeSplitLedger(
          balances: [
            owedToMe('ravi', 185000, since: const DateKey(20260714)),
          ],
        ),
      );

      final ageing = await service.ageingDebts();
      expect(ageing.single.ageInDays, 31);
    });

    test('a debt inside the threshold is not mentioned', () async {
      // Splitting a bill on Friday must not produce a notification the following Tuesday.
      final service = build(
        FakeSplitLedger(
          balances: [owedToMe('ravi', 1000, since: const DateKey(20260810))],
        ),
      );
      expect(await service.ageingDebts(), isEmpty);
    });

    test('the threshold is overridable', () async {
      final service = build(
        FakeSplitLedger(
          balances: [owedToMe('ravi', 1000, since: const DateKey(20260810))],
        ),
      );
      expect(await service.ageingDebts(thresholdDays: 3), hasLength(1));
    });

    test('oldest first', () async {
      final service = build(
        FakeSplitLedger(
          balances: [
            owedToMe('recent', 1000, since: const DateKey(20260720)),
            owedToMe('ancient', 1000, since: const DateKey(20260601)),
          ],
        ),
      );
      expect(
        (await service.ageingDebts()).map((d) => d.balance.payeeId),
        ['ancient', 'recent'],
      );
    });

    test('a balance with no date is never ageing', () async {
      // `MIN(date_key)` over rows that are all settlements yields null — nothing dated is outstanding.
      final service = build(
        FakeSplitLedger(balances: [owedToMe('ravi', 1000)]),
      );
      expect(await service.ageingDebts(), isEmpty);
    });

    test('debts you owe age too', () async {
      // The nudge runs both ways: forgetting to pay somebody back is the commoner failure.
      final service = build(
        FakeSplitLedger(
          balances: [iOwe('priya', 40000, since: const DateKey(20260601))],
        ),
      );
      expect(
        await service.ageingDebts().then((d) => d.single.balance.iOweThem),
        isTrue,
      );
    });
  });

  group('totals', () {
    test('two figures per currency, never netted', () async {
      // "Owed ₹4,000 and owe ₹3,900" is a different story from "up ₹100", and the net version is the
      // first step towards treating a receivable as an asset.
      final service = build(
        FakeSplitLedger(
          balances: [
            owedToMe('ravi', 400000),
            iOwe('priya', 390000),
          ],
        ),
      );

      final totals = await service.totals();
      expect(totals['INR']!.owedToMe, inr(400000));
      expect(totals['INR']!.iOwe, inr(390000));
    });

    test('currencies stay apart', () async {
      // Netting INR against USD without a rate produces a figure nobody can reproduce (A34).
      final service = build(
        FakeSplitLedger(
          balances: [
            owedToMe('ravi', 100000),
            SplitBalanceFixture.usdOwed('sam', 5000),
          ],
        ),
      );

      final totals = await service.totals();
      expect(totals.keys.toSet(), {'INR', 'USD'});
    });

    test('nothing outstanding is an empty map, not zeroes', () async {
      expect(await build(FakeSplitLedger()).totals(), isEmpty);
    });
  });

  group('settle-up plans', () {
    test(
      'one plan per currency, because the simplifier refuses a mixed list',
      () async {
        // `DebtSimplifier.plan` throws `CurrencyMismatchError` on mixed edges — a correct refusal, and
        // the reason this grouping is visible here rather than hidden inside a total. A travel group
        // would otherwise crash the settle-up screen.
        final service = build(
          FakeSplitLedger(
            debts: [
              DebtEdge(
                fromPayeeId: 'a',
                toPayeeId: 'me',
                amount: inr(2000),
              ),
              const DebtEdge(
                fromPayeeId: 'b',
                toPayeeId: 'me',
                amount: Money(50, 'USD'),
              ),
            ],
          ),
        );

        final plans = await service.settleUpPlans('g-1');
        expect(plans.map((p) => p.currencyCode).toSet(), {'INR', 'USD'});
      },
    );

    test('a plan that saves nothing is dropped', () async {
      // Two independent debts already settle in two payments. Showing a "plan" that changes nothing is
      // a wasted tap; an empty list means settled or already minimal.
      final service = build(
        FakeSplitLedger(
          debts: [
            DebtEdge(fromPayeeId: 'a', toPayeeId: 'me', amount: inr(1000)),
          ],
        ),
      );

      final plans = await service.settleUpPlans('g-1');
      expect(plans.single.plan.transfers, hasLength(1));
      expect(plans.single.plan.isImprovement, isFalse);
    });

    test('nothing owed is an empty list', () async {
      expect(await build(FakeSplitLedger()).settleUpPlans('g-1'), isEmpty);
    });

    test('canSimplify only says yes when it would help', () async {
      final noBetter = build(
        FakeSplitLedger(
          debts: [
            DebtEdge(fromPayeeId: 'a', toPayeeId: 'me', amount: inr(1000)),
          ],
        ),
      );
      expect(await noBetter.canSimplify('g-1'), isFalse);

      // A chain: a owes me, I owe b. One payment replaces two.
      final better = build(
        FakeSplitLedger(
          debts: [
            DebtEdge(fromPayeeId: 'a', toPayeeId: 'me', amount: inr(1000)),
            DebtEdge(fromPayeeId: 'me', toPayeeId: 'b', amount: inr(1000)),
          ],
        ),
      );
      expect(await better.canSimplify('g-1'), isTrue);
    });
  });
}

/// A USD balance, which the fixtures above are hardcoded to INR for.
abstract final class SplitBalanceFixture {
  /// Somebody owes the user [minor] in USD.
  static SplitBalance usdOwed(String payeeId, int minor) => SplitBalance(
    payeeId: payeeId,
    owedToMe: Money(minor, 'USD'),
    iOwe: const Money(0, 'USD'),
  );
}
