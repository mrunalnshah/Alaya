import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';

/// The expiry-aware draw policy on [InventoryConsumptionService].
///
/// **A separate file from `consumption_test.dart` on purpose.** That one is 848 lines covering four
/// services and every case in it exercises the default `DrawPolicy.fefo()`, which is unchanged — so
/// none of it needed touching, and putting these there would have buried a new policy inside a
/// regression suite for an old one.
///
/// These cases began life against a `DrawPlanner` written before this service was found. The policy
/// survived the move; the class did not. `orderFefo` and its own tests are untouched.
void main() {
  const service = InventoryConsumptionService();
  const today = DateKey(20260814);

  Qty grams(int g) => Qty(g * 1000, UnitCategory.weight);

  ConsumableBatch batch(
    String id,
    int g, {
    int? expiry,
    int purchased = 20260701,
  }) => ConsumableBatch(
    batchId: id,
    remaining: grams(g),
    purchasedDateKey: DateKey(purchased),
    expiryDateKey: expiry == null ? null : DateKey(expiry),
  );

  /// Deliberately in an order where neither the good stock nor the least-spoiled expired batch is
  /// first, so a policy that trusted its input order would fail every assertion below.
  List<ConsumableBatch> shelf() => [
    batch('ancient', 100, expiry: 20260601, purchased: 20260501),
    batch('yesterday', 100, expiry: 20260813),
    batch('lastweek', 100, expiry: 20260807, purchased: 20260601),
    batch('good', 150, expiry: 20260901, purchased: 20260801),
    batch('never', 100, purchased: 20260401),
  ];

  group('ConsumableBatch.isExpired', () {
    test('is strict, so a batch expiring today is still good today', () {
      expect(batch('edge', 10, expiry: 20260814).isExpired(today), isFalse);
      expect(batch('gone', 10, expiry: 20260813).isExpired(today), isTrue);
    });

    test('a batch with no date never expires', () {
      expect(batch('never', 10).isExpired(today), isFalse);
    });
  });

  group('orderFreshFirst', () {
    test('good stock first, then least spoiled among the expired', () {
      // Good stock in FEFO order — `good` expires before `never`, and undated goes last because it
      // cannot spoil on a deadline. Then the expired, nearest-to-fresh first: strict FEFO would have
      // handed over `ancient`, the most spoiled thing on the shelf.
      expect(
        service.orderFreshFirst(shelf(), today).map((b) => b.batchId),
        orderedEquals(['good', 'never', 'yesterday', 'lastweek', 'ancient']),
      );
    });

    test('which is the reverse of orderFefo among the expired', () {
      // The same shelf under the existing policy. Both orders are correct — for different jobs.
      expect(
        service.orderFefo(shelf()).map((b) => b.batchId),
        orderedEquals(['ancient', 'lastweek', 'yesterday', 'good', 'never']),
      );
    });

    test('drops batches holding nothing', () {
      final ordered = service.orderFreshFirst([
        batch('empty', 0, expiry: 20260901),
        batch('full', 100, expiry: 20260901),
      ], today);
      expect(ordered.map((b) => b.batchId), orderedEquals(['full']));
    });

    test(
      'returns expired batches too, because the caller must be able to offer them',
      () {
        expect(service.orderFreshFirst(shelf(), today), hasLength(5));
      },
    );
  });

  group('plan under DrawPolicy.freshFirst', () {
    test('spends good stock and never reaches the expired', () {
      final result = service.plan(
        batches: shelf(),
        needed: grams(200),
        policy: const DrawPolicy.freshFirst(today: today),
      );

      final plan = result.valueOrNull;
      expect(plan, isNotNull);
      expect(
        plan!.draws.map((d) => d.batchId),
        orderedEquals(['good', 'never']),
      );
      expect(plan.draws.last.quantity, grams(50));
      expect(plan.usesExpired, isFalse);
      expect(plan.fromExpired, grams(0));
    });

    test('refuses rather than dipping into expired stock', () {
      // **The reported bug, as a refusal.** 300 g wanted, 250 g good, 300 g past its date. Under FEFO
      // this succeeded silently by eating the expired batches first.
      final result = service.plan(
        batches: shelf(),
        needed: grams(300),
        policy: const DrawPolicy.freshFirst(today: today),
      );

      expect(result.isFailure, isTrue);
      expect(
        (result.failureOrNull as BusinessRuleFailure?)?.rule,
        'insufficientStock',
      );
    });

    test('and the same request succeeds once expired stock is permitted', () {
      // The second call is how a caller learns that consent would help — two answers rather than a
      // partial plan nobody may apply.
      final plan = service
          .plan(
            batches: shelf(),
            needed: grams(300),
            policy: const DrawPolicy.freshFirst(
              today: today,
              allowExpired: true,
            ),
          )
          .valueOrNull;

      expect(plan, isNotNull);
      expect(
        plan!.draws.map((d) => d.batchId),
        orderedEquals(['good', 'never', 'yesterday']),
      );
      // Good stock exhausted first; only 50 g came from the least spoiled expired batch.
      expect(plan.usesExpired, isTrue);
      expect(plan.fromExpired, grams(50));
    });

    test('still refuses when even the expired stock is not enough', () {
      final result = service.plan(
        batches: shelf(),
        needed: grams(600),
        policy: const DrawPolicy.freshFirst(today: today, allowExpired: true),
      );

      expect(result.isFailure, isTrue);
      expect(
        (result.failureOrNull as BusinessRuleFailure?)?.rule,
        'insufficientStock',
      );
    });

    test('totalAvailable counts only what the policy would reach', () {
      // The number quoted in a shortfall must be one the plan could actually have drawn, or the
      // refusal reads as arithmetic nobody can reproduce.
      final excluded = service
          .plan(
            batches: shelf(),
            needed: grams(1),
            policy: const DrawPolicy.freshFirst(today: today),
          )
          .valueOrNull;
      expect(excluded!.totalAvailable, grams(250));

      final included = service
          .plan(
            batches: shelf(),
            needed: grams(1),
            policy: const DrawPolicy.freshFirst(
              today: today,
              allowExpired: true,
            ),
          )
          .valueOrNull;
      expect(included!.totalAvailable, grams(550));
    });

    test('a batch expiring today is spent as good stock', () {
      final plan = service
          .plan(
            batches: [batch('edge', 100, expiry: 20260814)],
            needed: grams(100),
            policy: const DrawPolicy.freshFirst(today: today),
          )
          .valueOrNull;

      expect(plan, isNotNull);
      expect(plan!.usesExpired, isFalse);
    });
  });

  group('the default policy is unchanged', () {
    test('fefo includes expired stock and reports none of it as expired', () {
      // `fromExpired` is zero because `DrawPolicy.fefo()` does not ask the question — not because the
      // batches are fresh. A write-off has no use for the distinction.
      final plan = service
          .plan(batches: shelf(), needed: grams(200))
          .valueOrNull;

      expect(plan, isNotNull);
      expect(
        plan!.draws.map((d) => d.batchId),
        orderedEquals(['ancient', 'lastweek']),
      );
      expect(plan.fromExpired, grams(0));
      expect(plan.usesExpired, isFalse);
      expect(plan.totalAvailable, grams(550));
    });

    test('planAll stays FEFO, because emptying a shelf has no preference', () {
      final plan = service
          .planAll(batches: shelf(), zeroOfCategory: grams(0))
          .valueOrNull;

      expect(plan, isNotNull);
      expect(plan!.draws, hasLength(5));
      expect(plan.totalAvailable, grams(550));
    });
  });

  group('refusals a policy cannot change', () {
    test('a non-positive quantity is a validation failure', () {
      for (final wanted in [grams(0), grams(-5)]) {
        final result = service.plan(
          batches: shelf(),
          needed: wanted,
          policy: const DrawPolicy.freshFirst(today: today),
        );
        expect(result.failureOrNull, isA<ValidationFailure>());
      }
    });

    test('a mismatched category is a validation failure, not a shortfall', () {
      // Law L8: a `Qty` in the wrong category is a bare integer that would be reinterpreted on read.
      final result = service.plan(
        batches: shelf(),
        needed: const Qty(100000, UnitCategory.volume),
        policy: const DrawPolicy.freshFirst(today: today),
      );
      expect(result.failureOrNull, isA<ValidationFailure>());
    });
  });
}
