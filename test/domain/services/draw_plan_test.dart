import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/services/draw_plan.dart';

import '../../support/inventory_harness.dart';

/// The draw planner.
///
/// **Every case here was unstateable before.** `stockOf` builds an `ItemStock` with `batchCount: 1`
/// and one optional expiry, so no test in the repo could say "three batches, two of them expired" —
/// which is the entire scenario. `sampleBatch` from the inventory harness can, which is why these
/// tests live on batches rather than on a stock rollup.
void main() {
  const planner = DrawPlanner();
  const today = DateKey(20260814);

  /// A batch of [grams] expiring on [expiry], or never.
  Batch batch(String id, int grams, {DateKey? expiry}) =>
      sampleBatch(id: id, remainingMilli: grams * 1000, expiry: expiry);

  Qty grams(int value) => Qty(value * 1000, UnitCategory.weight);

  group('ordering among unexpired stock', () {
    test('soonest expiry first, whatever order the batches arrive in', () {
      final plan = planner.plan(
        batches: [
          batch('c', 100, expiry: const DateKey(20260901)),
          batch('a', 100, expiry: const DateKey(20260816)),
          batch('b', 100, expiry: const DateKey(20260820)),
        ],
        needed: grams(250),
        today: today,
      );

      expect(
        plan.lines.map((line) => line.batch.id),
        orderedEquals(['a', 'b', 'c']),
      );
      // The last batch is only partly drawn, because 250 is not a multiple of 100.
      expect(plan.lines.last.amount, grams(50));
      expect(plan.isComplete, isTrue);
    });

    test('an undated batch is spent last', () {
      // Nothing else can go off, so spending it ahead of a dated batch would waste the dated one.
      final plan = planner.plan(
        batches: [
          batch('never', 100),
          batch('dated', 100, expiry: const DateKey(20260901)),
        ],
        needed: grams(150),
        today: today,
      );

      expect(plan.lines.first.batch.id, 'dated');
      expect(plan.lines.last.batch.id, 'never');
    });

    test('a same-day tie breaks on id, so two plans agree', () {
      // Not cosmetic: a plan shown in a confirmation sheet and the plan executed a moment later must
      // list equally-good batches identically, or the user approved something else.
      final expiry = const DateKey(20260820);
      final first = planner.plan(
        batches: [
          batch('b', 100, expiry: expiry),
          batch('a', 100, expiry: expiry),
        ],
        needed: grams(120),
        today: today,
      );
      final second = planner.plan(
        batches: [
          batch('a', 100, expiry: expiry),
          batch('b', 100, expiry: expiry),
        ],
        needed: grams(120),
        today: today,
      );

      expect(
        first.lines.map((line) => line.batch.id),
        orderedEquals(second.lines.map((line) => line.batch.id)),
      );
      expect(first.lines.first.batch.id, 'a');
    });

    test('batches holding nothing are skipped, not counted', () {
      final plan = planner.plan(
        batches: [
          batch('empty', 0, expiry: const DateKey(20260816)),
          batch('full', 100, expiry: const DateKey(20260901)),
        ],
        needed: grams(100),
        today: today,
      );

      expect(plan.lines, hasLength(1));
      expect(plan.lines.single.batch.id, 'full');
    });
  });

  group('expired stock is excluded unless asked for', () {
    test('an expired batch is not drawn, and the shortfall says so', () {
      // **The reported bug.** Expired stock was being deducted silently, because FEFO orders by
      // nearest expiry and an expired date is the nearest date — the policy was working, for a
      // different purpose.
      final plan = planner.plan(
        batches: [
          batch('gone', 200, expiry: const DateKey(20260810)),
          batch('good', 100, expiry: const DateKey(20260901)),
        ],
        needed: grams(250),
        today: today,
      );

      expect(plan.lines.map((line) => line.batch.id), orderedEquals(['good']));
      expect(plan.isComplete, isFalse);
      expect(plan.shortfall, grams(150));
      expect(plan.usesExpired, isFalse);
    });

    test('and reports that saying yes would cover it', () {
      // What the confirmation prompt is for: 150 g short, 200 g sitting there past its date.
      final plan = planner.plan(
        batches: [
          batch('gone', 200, expiry: const DateKey(20260810)),
          batch('good', 100, expiry: const DateKey(20260901)),
        ],
        needed: grams(250),
        today: today,
      );

      expect(plan.couldCompleteWithExpired, isTrue);
      expect(plan.expiredUntouchedMilli, grams(200).milliBase);
    });

    test('a complete plan never offers expired stock', () {
      // There is expired stock, and the plan does not reach it. Prompting here would be a warning
      // about nothing.
      final plan = planner.plan(
        batches: [
          batch('gone', 200, expiry: const DateKey(20260810)),
          batch('good', 500, expiry: const DateKey(20260901)),
        ],
        needed: grams(250),
        today: today,
      );

      expect(plan.isComplete, isTrue);
      expect(plan.usesExpired, isFalse);
      expect(plan.couldCompleteWithExpired, isFalse);
    });

    test(
      'when even the expired stock is not enough, there is nothing to offer',
      () {
        final plan = planner.plan(
          batches: [
            batch('gone', 50, expiry: const DateKey(20260810)),
            batch('good', 100, expiry: const DateKey(20260901)),
          ],
          needed: grams(400),
          today: today,
        );

        expect(plan.couldCompleteWithExpired, isFalse);
        expect(plan.shortfall, grams(300));
      },
    );
  });

  group('the expired fallback, once permitted', () {
    test('good stock is spent first and expired only tops it up', () {
      // Your case: 150 good, 100 expired, 200 needed. Good stock is exhausted before anything past
      // its date is touched, and the plan says exactly how much of the total was expired.
      final plan = planner.plan(
        batches: [
          batch('gone', 100, expiry: const DateKey(20260810)),
          batch('good', 150, expiry: const DateKey(20260901)),
        ],
        needed: grams(200),
        today: today,
        allowExpired: true,
      );

      expect(
        plan.lines.map((line) => line.batch.id),
        orderedEquals(['good', 'gone']),
      );
      expect(plan.lines.first.amount, grams(150));
      expect(plan.lines.last.amount, grams(50));
      expect(plan.isComplete, isTrue);
      expect(plan.usesExpired, isTrue);
      expect(plan.fromExpired, grams(50));
      // 100 expired existed, 50 was used, 50 remains untouched.
      expect(plan.expiredUntouchedMilli, grams(50).milliBase);
    });

    test('least spoiled first among expired, not oldest first', () {
      // **Deliberately the reverse of FEFO.** Strict FEFO reaches for the oldest expired batch, which
      // is the most spoiled thing in the house. Among food already past its date, nearest-to-fresh is
      // the only defensible order.
      final plan = planner.plan(
        batches: [
          batch('ancient', 100, expiry: const DateKey(20260601)),
          batch('yesterday', 100, expiry: const DateKey(20260813)),
          batch('lastweek', 100, expiry: const DateKey(20260807)),
        ],
        needed: grams(250),
        today: today,
        allowExpired: true,
      );

      expect(
        plan.lines.map((line) => line.batch.id),
        orderedEquals(['yesterday', 'lastweek', 'ancient']),
      );
    });

    test('every line is marked, so nobody recomputes which were expired', () {
      final plan = planner.plan(
        batches: [
          batch('gone', 100, expiry: const DateKey(20260810)),
          batch('good', 100, expiry: const DateKey(20260901)),
        ],
        needed: grams(200),
        today: today,
        allowExpired: true,
      );

      expect(plan.lines.where((line) => line.isExpired), hasLength(1));
      expect(
        plan.lines.singleWhere((line) => line.isExpired).batch.id,
        'gone',
      );
    });
  });

  group('the expiry boundary', () {
    test('a batch expiring today is still good today', () {
      // Confirms `Batch.isExpired`, which is strict: `expiry < today`. Use-by 14 Aug is usable on
      // 14 Aug, which is what the calendar module already assumes — a batch expiring today appears
      // as an event rather than as history.
      final plan = planner.plan(
        batches: [batch('today', 100, expiry: today)],
        needed: grams(100),
        today: today,
      );

      expect(plan.isComplete, isTrue);
      expect(plan.usesExpired, isFalse);
    });

    test('a batch that expired yesterday is not', () {
      final plan = planner.plan(
        batches: [batch('yesterday', 100, expiry: const DateKey(20260813))],
        needed: grams(100),
        today: today,
      );

      expect(plan.lines, isEmpty);
      expect(plan.couldCompleteWithExpired, isTrue);
    });
  });

  group('degenerate requests', () {
    test('asking for nothing draws nothing', () {
      for (final wanted in [grams(0), grams(-5)]) {
        final plan = planner.plan(
          batches: [batch('good', 100, expiry: const DateKey(20260901))],
          needed: wanted,
          today: today,
        );
        expect(plan.lines, isEmpty);
        expect(plan.isComplete, isTrue);
        expect(plan.usesExpired, isFalse);
      }
    });

    test('no batches at all is a shortfall, not a crash', () {
      final plan = planner.plan(
        batches: const [],
        needed: grams(100),
        today: today,
      );

      expect(plan.shortfall, grams(100));
      expect(plan.couldCompleteWithExpired, isFalse);
    });

    test(
      'a mismatched category throws rather than reporting a false shortfall',
      () {
        // A caller that skipped the volume-to-weight bridge. Silently dropping the batch would report
        // a shortfall for stock sitting on the shelf, which is the worse of the two failures.
        expect(
          () => planner.plan(
            batches: [batch('good', 100, expiry: const DateKey(20260901))],
            needed: const Qty(100000, UnitCategory.volume),
            today: today,
          ),
          throwsArgumentError,
        );
      },
    );
  });
}
