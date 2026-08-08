import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/services/recurring_engine.dart';

/// The recurring schedule: month-end clamping, lazy materialisation, settlement and skipping.
///
/// `RecurringEngine` is pure and takes every date it needs, so the calendar under test is fixed
/// rather than whatever day the suite happens to run on.
void main() {
  const engine = RecurringEngine();

  RecurringTemplate template({
    String id = 'rent',
    RecurringIntervalUnit unit = RecurringIntervalUnit.month,
    int count = 1,
    int? anchorDay = 1,
    required DateKey startDateKey,
    required DateKey nextDueDateKey,
    DateKey? endDateKey,
    RecurringDirection direction = RecurringDirection.outflow,
    int defaultMinor = 2500000,
    String currency = 'INR',
    bool isPaused = false,
  }) => RecurringTemplate(
    id: id,
    name: 'Rent',
    normalizedName: 'rent',
    kind: RecurringKind.bill,
    direction: direction,
    defaultAmount: Money(defaultMinor, currency),
    intervalUnit: unit,
    intervalCount: count,
    startDateKey: startDateKey,
    nextDueDateKey: nextDueDateKey,
    isPaused: isPaused,
    autoRemind: false,
    remindDaysBefore: 1,
    anchorDayOfMonth: anchorDay,
    endDateKey: endDateKey,
    payeeId: 'landlord',
    tagId: 'tag-rent',
  );

  group('month-end clamp — anomaly A13', () {
    test(
      'anchored on day 31 from 31 Jan gives 31, 28, 31, 30 — not 28, 28, 28',
      () {
        final anchored31 = template(
          anchorDay: 31,
          startDateKey: DateKey.fromYmd(2026, 1, 31),
          nextDueDateKey: DateKey.fromYmd(2026, 1, 31),
        );

        final dates = <DateKey>[DateKey.fromYmd(2026, 1, 31)];
        for (var i = 0; i < 3; i++) {
          dates.add(engine.nextDue(from: dates.last, template: anchored31));
        }

        expect(dates.map((d) => d.value).toList(), [
          20260131,
          20260228,
          20260331,
          20260430,
        ]);
      },
    );

    test(
      'March returns to the 31st, proving the ANCHOR is clamped and not the current day',
      () {
        final anchored31 = template(
          anchorDay: 31,
          startDateKey: DateKey.fromYmd(2026, 1, 31),
          nextDueDateKey: DateKey.fromYmd(2026, 1, 31),
        );

        // February is the 28th...
        final february = engine.nextDue(
          from: DateKey.fromYmd(2026, 1, 31),
          template: anchored31,
        );
        expect(february, DateKey.fromYmd(2026, 2, 28));

        // ...and advancing from that clamped date must still land on the 31st, not the 28th.
        final march = engine.nextDue(from: february, template: anchored31);
        expect(
          march,
          DateKey.fromYmd(2026, 3, 31),
          reason:
              'advancing from the clamped 28th would walk the bill back permanently',
        );
      },
    );

    test('a leap year clamps February to the 29th', () {
      final anchored31 = template(
        anchorDay: 31,
        startDateKey: DateKey.fromYmd(2024, 1, 31),
        nextDueDateKey: DateKey.fromYmd(2024, 1, 31),
      );

      final dates = <DateKey>[DateKey.fromYmd(2024, 1, 31)];
      for (var i = 0; i < 3; i++) {
        dates.add(engine.nextDue(from: dates.last, template: anchored31));
      }

      expect(dates.map((d) => d.value).toList(), [
        20240131,
        20240229,
        20240331,
        20240430,
      ]);
    });

    test('a full year from 31 Jan never loses the anchor', () {
      final anchored31 = template(
        anchorDay: 31,
        startDateKey: DateKey.fromYmd(2026, 1, 31),
        nextDueDateKey: DateKey.fromYmd(2026, 1, 31),
      );

      var cursor = DateKey.fromYmd(2026, 1, 31);
      final days = <int>[cursor.day];
      for (var i = 0; i < 12; i++) {
        cursor = engine.nextDue(from: cursor, template: anchored31);
        days.add(cursor.day);
      }

      expect(days, [
        31,
        28,
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
        31,
      ], reason: 'every 31-day month gets its 31st back');
    });

    test('the clamp helper resolves February in both kinds of year', () {
      expect(engine.clampDayOfMonth(31, 2026, 2), 28);
      expect(engine.clampDayOfMonth(31, 2024, 2), 29);
      expect(engine.clampDayOfMonth(31, 2026, 4), 30);
      expect(
        engine.clampDayOfMonth(15, 2026, 2),
        15,
        reason: 'a day that fits is untouched',
      );
    });

    test(
      'a yearly template anchored on 29 Feb clamps, then recovers four years on',
      () {
        final leapDay = template(
          unit: RecurringIntervalUnit.year,
          anchorDay: 29,
          startDateKey: DateKey.fromYmd(2024, 2, 29),
          nextDueDateKey: DateKey.fromYmd(2024, 2, 29),
        );

        var cursor = DateKey.fromYmd(2024, 2, 29);
        final seen = <int>[];
        for (var i = 0; i < 4; i++) {
          cursor = engine.nextDue(from: cursor, template: leapDay);
          seen.add(cursor.value);
        }

        expect(seen, [20250228, 20260228, 20270228, 20280229]);
      },
    );

    test('day and week intervals cross month and year boundaries', () {
      final daily = template(
        unit: RecurringIntervalUnit.day,
        anchorDay: null,
        startDateKey: DateKey.fromYmd(2026, 12, 31),
        nextDueDateKey: DateKey.fromYmd(2026, 12, 31),
      );
      final weekly = template(
        unit: RecurringIntervalUnit.week,
        anchorDay: null,
        startDateKey: DateKey.fromYmd(2026, 2, 26),
        nextDueDateKey: DateKey.fromYmd(2026, 2, 26),
      );

      expect(
        engine.nextDue(from: DateKey.fromYmd(2026, 12, 31), template: daily),
        DateKey.fromYmd(2027, 1, 1),
      );
      expect(
        engine.nextDue(from: DateKey.fromYmd(2026, 2, 26), template: weekly),
        DateKey.fromYmd(2026, 3, 5),
      );
    });

    test('a quarterly template anchored on 31 clamps per target month', () {
      final quarterly = template(
        count: 3,
        anchorDay: 31,
        startDateKey: DateKey.fromYmd(2026, 1, 31),
        nextDueDateKey: DateKey.fromYmd(2026, 1, 31),
      );

      expect(
        engine.nextDue(from: DateKey.fromYmd(2026, 1, 31), template: quarterly),
        DateKey.fromYmd(2026, 4, 30),
      );
    });
  });

  group('lazy materialisation — anomaly A14', () {
    final today = DateKey.fromYmd(2026, 7, 28);

    test(
      'a template last due three months ago yields exactly three occurrences',
      () {
        final behind = template(
          startDateKey: DateKey.fromYmd(2026, 1, 1),
          nextDueDateKey: DateKey.fromYmd(2026, 5, 1),
        );

        final plan = engine.planMaterialisation(template: behind, asOf: today);

        expect(plan.occurrences, hasLength(3));
        expect(plan.occurrences.map((o) => o.dueDateKey.value).toList(), [
          20260501,
          20260601,
          20260701,
        ]);
      },
    );

    test('and creates ZERO transactions — money needs an explicit tap', () {
      final behind = template(
        startDateKey: DateKey.fromYmd(2026, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2026, 5, 1),
      );

      final plan = engine.planMaterialisation(template: behind, asOf: today);

      // The plan's only output is occurrences. There is no transaction field to populate, which is
      // the structural guarantee: a materialisation pass cannot create money even by mistake.
      expect(plan.occurrences.every((o) => o.templateId == 'rent'), isTrue);
      expect(plan.nextDueDateKey, DateKey.fromYmd(2026, 8, 1));
    });

    test('nextDueDateKey lands past today, ready for the following pass', () {
      final behind = template(
        startDateKey: DateKey.fromYmd(2026, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2026, 5, 1),
      );

      final plan = engine.planMaterialisation(template: behind, asOf: today);

      expect(plan.nextDueDateKey.isAfter(today), isTrue);
    });

    test('running again with those dates already present plans nothing', () {
      final behind = template(
        startDateKey: DateKey.fromYmd(2026, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2026, 5, 1),
      );

      final first = engine.planMaterialisation(template: behind, asOf: today);
      final second = engine.planMaterialisation(
        template: behind,
        asOf: today,
        alreadyMaterialised: first.occurrences.map((o) => o.dueDateKey),
      );

      expect(second.occurrences, isEmpty);
      expect(
        second.nextDueDateKey,
        first.nextDueDateKey,
        reason:
            'the cursor must land identically either way, or the pass is not idempotent',
      );
    });

    test('nothing due yet plans nothing and leaves the cursor alone', () {
      final future = template(
        startDateKey: DateKey.fromYmd(2026, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2026, 9, 1),
      );

      final plan = engine.planMaterialisation(template: future, asOf: today);

      expect(plan.isEmpty, isTrue);
      expect(plan.nextDueDateKey, DateKey.fromYmd(2026, 9, 1));
    });

    test('an end date stops materialisation', () {
      final ending = template(
        startDateKey: DateKey.fromYmd(2026, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2026, 5, 1),
        endDateKey: DateKey.fromYmd(2026, 6, 1),
      );

      final plan = engine.planMaterialisation(template: ending, asOf: today);

      expect(plan.occurrences.map((o) => o.dueDateKey.value).toList(), [
        20260501,
        20260601,
      ]);
    });

    test('the anchor survives a materialisation run across February', () {
      final anchored31 = template(
        anchorDay: 31,
        startDateKey: DateKey.fromYmd(2026, 1, 31),
        nextDueDateKey: DateKey.fromYmd(2026, 1, 31),
      );

      final plan = engine.planMaterialisation(
        template: anchored31,
        asOf: DateKey.fromYmd(2026, 4, 30),
      );

      expect(plan.occurrences.map((o) => o.dueDateKey.value).toList(), [
        20260131,
        20260228,
        20260331,
        20260430,
      ]);
      expect(plan.nextDueDateKey, DateKey.fromYmd(2026, 5, 31));
    });

    test(
      'a daily template years behind stops at the safety bound instead of spinning',
      () {
        final daily = template(
          unit: RecurringIntervalUnit.day,
          anchorDay: null,
          startDateKey: DateKey.fromYmd(2024, 1, 1),
          nextDueDateKey: DateKey.fromYmd(2024, 1, 1),
        );

        final plan = engine.planMaterialisation(template: daily, asOf: today);

        expect(plan.stoppedAtSafetyBound, isTrue);
        expect(
          plan.occurrences,
          hasLength(RecurringEngine.maxOccurrencesPerPass),
        );
      },
    );
  });

  group('settlement — direction decides the kind', () {
    final due = RecurringOccurrence(
      id: 'o1',
      templateId: 'rent',
      dueDateKey: DateKey.fromYmd(2026, 7, 1),
      status: RecurringOccurrenceStatus.due,
    );
    final paidOn = DateKey.fromYmd(2026, 7, 3);

    test('an outflow settles as a withdrawal from the account', () {
      final intent = engine
          .planSettlement(
            template: template(
              startDateKey: DateKey.fromYmd(2026, 1, 1),
              nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
            ),
            occurrence: due,
            amount: const Money(2500000, 'INR'),
            paidOn: paidOn,
            accountId: 'bank',
          )
          .valueOrNull!;

      expect(intent.kind, TransactionKind.withdrawal);
      expect(intent.fromAccountId, 'bank');
      expect(
        intent.toAccountId,
        isNull,
        reason: 'ARCH_2 §4.1 allows exactly one account',
      );
    });

    test('an inflow settles as a deposit into the account', () {
      final intent = engine
          .planSettlement(
            template: template(
              direction: RecurringDirection.inflow,
              startDateKey: DateKey.fromYmd(2026, 1, 1),
              nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
            ),
            occurrence: due,
            amount: const Money(2500000, 'INR'),
            paidOn: paidOn,
            accountId: 'bank',
          )
          .valueOrNull!;

      expect(intent.kind, TransactionKind.deposit);
      expect(intent.toAccountId, 'bank');
      expect(intent.fromAccountId, isNull);
      expect(
        intent.subtype,
        TransactionSubtype.salaryIn,
        reason:
            'one direction field is what lets salary share the system with bills (A27)',
      );
    });

    test('the ACTUAL amount is carried, not the template default', () {
      final intent = engine
          .planSettlement(
            template: template(
              defaultMinor: 49900,
              startDateKey: DateKey.fromYmd(2026, 1, 1),
              nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
            ),
            occurrence: due,
            // Paid 520 against a 499 expectation.
            amount: const Money(52000, 'INR'),
            paidOn: paidOn,
            accountId: 'bank',
          )
          .valueOrNull!;

      expect(
        intent.amount,
        const Money(52000, 'INR'),
        reason:
            'analytics uses actuals; the template keeps its expectation (A29)',
      );
    });

    test('the payee and tag come from the template', () {
      final intent = engine
          .planSettlement(
            template: template(
              startDateKey: DateKey.fromYmd(2026, 1, 1),
              nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
            ),
            occurrence: due,
            amount: const Money(2500000, 'INR'),
            paidOn: paidOn,
            accountId: 'bank',
          )
          .valueOrNull!;

      expect(intent.payeeId, 'landlord');
      expect(intent.tagId, 'tag-rent');
      expect(intent.occurrenceId, 'o1');
      expect(intent.templateId, 'rent');
      expect(
        intent.dateKey,
        paidOn,
        reason: 'dated when paid, which may differ from when due',
      );
    });

    test('an already-settled occurrence cannot be settled twice', () {
      final result = engine.planSettlement(
        template: template(
          startDateKey: DateKey.fromYmd(2026, 1, 1),
          nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
        ),
        occurrence: RecurringOccurrence(
          id: 'o1',
          templateId: 'rent',
          dueDateKey: DateKey.fromYmd(2026, 7, 1),
          status: RecurringOccurrenceStatus.paid,
        ),
        amount: const Money(2500000, 'INR'),
        paidOn: paidOn,
        accountId: 'bank',
      );

      expect(result.isFailure, isTrue);
      expect(
        (result.failureOrNull! as BusinessRuleFailure).rule,
        'occurrenceNotDue',
      );
    });

    test(
      'a payment in another currency is refused, not stored against the wrong code',
      () {
        final result = engine.planSettlement(
          template: template(
            startDateKey: DateKey.fromYmd(2026, 1, 1),
            nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
          ),
          occurrence: due,
          amount: const Money(600, 'USD'),
          paidOn: paidOn,
          accountId: 'bank',
        );

        expect(
          result.isFailure,
          isTrue,
          reason:
              'recurring_occurrences has no currency column of its own (ARCH_2 §7)',
        );
      },
    );

    test('a zero amount is refused', () {
      final result = engine.planSettlement(
        template: template(
          startDateKey: DateKey.fromYmd(2026, 1, 1),
          nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
        ),
        occurrence: due,
        amount: const Money(0, 'INR'),
        paidOn: paidOn,
        accountId: 'bank',
      );

      expect(result.isFailure, isTrue);
    });

    test('an occurrence from a different template is refused', () {
      final result = engine.planSettlement(
        template: template(
          startDateKey: DateKey.fromYmd(2026, 1, 1),
          nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
        ),
        occurrence: RecurringOccurrence(
          id: 'o9',
          templateId: 'netflix',
          dueDateKey: DateKey.fromYmd(2026, 7, 1),
          status: RecurringOccurrenceStatus.due,
        ),
        amount: const Money(2500000, 'INR'),
        paidOn: paidOn,
        accountId: 'bank',
      );

      expect(result.isFailure, isTrue);
    });
  });

  group('skip and overdue', () {
    test('a due occurrence can be skipped', () {
      final result = engine.planSkip(
        RecurringOccurrence(
          id: 'o1',
          templateId: 'rent',
          dueDateKey: DateKey.fromYmd(2026, 7, 1),
          status: RecurringOccurrenceStatus.due,
        ),
      );

      expect(result.isFailure, isFalse);
    });

    test('a settled occurrence cannot be skipped', () {
      final result = engine.planSkip(
        RecurringOccurrence(
          id: 'o1',
          templateId: 'rent',
          dueDateKey: DateKey.fromYmd(2026, 7, 1),
          status: RecurringOccurrenceStatus.paid,
          paidTransactionId: 't1',
        ),
      );

      expect(
        result.isFailure,
        isTrue,
        reason:
            'the money moved; skipping would leave a transaction with nothing explaining it',
      );
    });

    test('overdue is derived from the date, never stored', () {
      final occurrence = RecurringOccurrence(
        id: 'o1',
        templateId: 'rent',
        dueDateKey: DateKey.fromYmd(2026, 7, 1),
        status: RecurringOccurrenceStatus.due,
      );

      expect(
        engine.isOverdue(
          occurrence: occurrence,
          today: DateKey.fromYmd(2026, 7, 28),
        ),
        isTrue,
      );
      expect(
        engine.isOverdue(
          occurrence: occurrence,
          today: DateKey.fromYmd(2026, 6, 28),
        ),
        isFalse,
      );
    });

    test('a paused template is not active', () {
      final paused = template(
        isPaused: true,
        startDateKey: DateKey.fromYmd(2026, 1, 1),
        nextDueDateKey: DateKey.fromYmd(2026, 7, 1),
      );

      expect(
        engine.isActive(template: paused, asOf: DateKey.fromYmd(2026, 7, 28)),
        isFalse,
      );
    });
  });
}
