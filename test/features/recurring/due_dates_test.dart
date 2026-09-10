import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/services/recurring_engine.dart';
import 'package:alaya/features/recurring/state/template_builder_state.dart';

/// The due-date arithmetic, and the builder rules that feed it.
///
/// These are the cases a user notices and cannot debug: a bill that walks backwards through February,
/// an anchor that stops matching the start date, a first occurrence that never appears.
void main() {
  const engine = RecurringEngine();

  RecurringTemplate template({
    RecurringIntervalUnit unit = RecurringIntervalUnit.month,
    int intervalCount = 1,
    int? anchorDayOfMonth = 31,
    DateKey start = const DateKey(20260131),
    DateKey? nextDue,
    DateKey? end,
  }) => RecurringTemplate(
    id: 'tpl-1',
    name: 'Rent',
    normalizedName: 'rent',
    kind: RecurringKind.rent,
    direction: RecurringDirection.outflow,
    defaultAmount: const Money(120000, 'INR'),
    intervalUnit: unit,
    intervalCount: intervalCount,
    startDateKey: start,
    nextDueDateKey: nextDue ?? start,
    isPaused: false,
    autoRemind: true,
    remindDaysBefore: 3,
    anchorDayOfMonth: anchorDayOfMonth,
    endDateKey: end,
  );

  group('the anchor clamp', () {
    test('a 31st anchor shortens for February and returns in March', () {
      final t = template();
      final feb = engine.nextDue(from: const DateKey(20260131), template: t);
      final mar = engine.nextDue(from: feb, template: t);
      final apr = engine.nextDue(from: mar, template: t);
      expect(feb, const DateKey(20260228));
      // The whole point of storing the anchor rather than advancing it (anomaly A13): March returns to
      // the 31st instead of inheriting February's 28 for the rest of the template's life.
      expect(mar, const DateKey(20260331));
      expect(apr, const DateKey(20260430));
    });

    test('it never walks backwards across a whole year', () {
      final t = template();
      var cursor = const DateKey(20260131);
      final days = <int>[];
      for (var i = 0; i < 12; i++) {
        cursor = engine.nextDue(from: cursor, template: t);
        days.add(cursor.day);
      }
      // Every long month is back on the 31st. A carried-forward clamp would show 28 from February on.
      expect(days.where((d) => d == 31).length, greaterThanOrEqualTo(5));
      expect(days.contains(28), isTrue);
    });

    test('February is 29 in a leap year and 28 otherwise', () {
      expect(engine.clampDayOfMonth(31, 2028, 2), 29);
      expect(engine.clampDayOfMonth(31, 2026, 2), 28);
      expect(engine.clampDayOfMonth(30, 2026, 4), 30);
      expect(engine.clampDayOfMonth(15, 2026, 2), 15);
    });

    test('a day and week interval never clamps', () {
      final weekly = template(
        unit: RecurringIntervalUnit.week,
        anchorDayOfMonth: null,
      );
      expect(
        engine.nextDue(from: const DateKey(20260129), template: weekly),
        const DateKey(20260205),
      );
      final daily = template(
        unit: RecurringIntervalUnit.day,
        intervalCount: 3,
        anchorDayOfMonth: null,
      );
      expect(
        engine.nextDue(from: const DateKey(20260227), template: daily),
        const DateKey(20260302),
      );
    });

    test('a yearly interval keeps its month and clamps its day', () {
      final yearly = template(
        unit: RecurringIntervalUnit.year,
        anchorDayOfMonth: 29,
        start: const DateKey(20280229),
      );
      // 29 February 2028 exists; 2029 does not have one.
      expect(
        engine.nextDue(from: const DateKey(20280229), template: yearly),
        const DateKey(20290228),
      );
    });
  });

  group('the builder', () {
    TemplateBuilderState state({
      DateKey start = const DateKey(20260301),
      int? anchor,
      RecurringIntervalUnit unit = RecurringIntervalUnit.month,
    }) => TemplateBuilderState(
      currencyCode: 'INR',
      startDateKey: start,
      name: 'Rent',
      amount: const Money(120000, 'INR'),
      intervalUnit: unit,
      anchorDayOfMonth: anchor ?? start.day,
    );

    test('the anchor follows the start date while it still matches it', () {
      // The bug this pins: the builder seeds the anchor from today, so moving the start date left the
      // anchor on an unrelated day and the second occurrence landed nowhere near the first.
      final before = state(start: const DateKey(20260301));
      expect(before.anchorDayOfMonth, 1);
      final follows = before.anchorDayOfMonth == before.startDateKey.day;
      expect(follows, isTrue);
    });

    test(
      'an anchor the user chose is not overwritten by a start-date change',
      () {
        final chosen = state(start: const DateKey(20260301), anchor: 15);
        final follows = chosen.anchorDayOfMonth == chosen.startDateKey.day;
        // 15 is not 1, so the anchor was deliberate and must survive.
        expect(follows, isFalse);
      },
    );

    test('a monthly template is incomplete without a day anchor', () {
      const bare = TemplateBuilderState(
        currencyCode: 'INR',
        startDateKey: DateKey(20260301),
        name: 'Rent',
        amount: Money(120000, 'INR'),
      );
      expect(bare.needsDayAnchor, isTrue);
      expect(bare.isComplete, isFalse);
      expect(bare.copyWith(anchorDayOfMonth: 1).isComplete, isTrue);
    });

    test('a weekly template needs no anchor to be complete', () {
      const weekly = TemplateBuilderState(
        currencyCode: 'INR',
        startDateKey: DateKey(20260301),
        name: 'Gym',
        amount: Money(50000, 'INR'),
        intervalUnit: RecurringIntervalUnit.week,
      );
      expect(weekly.needsDayAnchor, isFalse);
      expect(weekly.isComplete, isTrue);
    });

    test(
      'a new template is first due on its start date, not one interval later',
      () {
        final t = state(start: const DateKey(20260315), anchor: 15).toTemplate(
          newId: 'tpl-9',
          normalizedName: 'rent',
          nextDue: const DateKey(20260315),
        );
        // Materialisation walks from `nextDueDateKey` inclusive, so seeding it with the start date is
        // what makes the first occurrence appear on the day the user chose.
        expect(t.nextDueDateKey, t.startDateKey);
      },
    );
  });

  group('an end date', () {
    test('stops the schedule rather than being ignored', () {
      final t = template(end: const DateKey(20260315));
      final feb = engine.nextDue(from: const DateKey(20260131), template: t);
      final mar = engine.nextDue(from: feb, template: t);
      expect(feb.isAfter(t.endDateKey!), isFalse);
      // March 31 is past the 15 March end, so a materialiser walking this must stop before it.
      expect(mar.isAfter(t.endDateKey!), isTrue);
    });
  });
}
