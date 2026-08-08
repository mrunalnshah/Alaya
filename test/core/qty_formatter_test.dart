import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_formatter.dart';
import 'package:alaya/core/quantity/unit_category.dart';

void main() {
  const formatter = QtyFormatter();

  group('CRITICAL required test cases (ARCH_1 §5.4, mixed style)', () {
    test('250_000 + 2_000_000 + 1_500_000 + 700_000 weight = 4_450_000 -> "4 kg 450 g"', () {
      // `final`, not `const`: a constant expression may only use the built-in `num`/`String`
      // operators, never a user-defined `operator +` like Qty's.
      final sum = const Qty(250000, UnitCategory.weight) +
          const Qty(2000000, UnitCategory.weight) +
          const Qty(1500000, UnitCategory.weight) +
          const Qty(700000, UnitCategory.weight);
      expect(sum.milliBase, 4450000);
      expect(formatter.format(sum), '4 kg 450 g');
    });

    test('2_000_000 weight -> "2 kg", never "2 kg 0 g"', () {
      const qty = Qty(2000000, UnitCategory.weight);
      expect(formatter.format(qty), '2 kg');
    });

    test('1_200_000 volume -> "1 L 200 ml"', () {
      const qty = Qty(1200000, UnitCategory.volume);
      expect(formatter.format(qty), '1 L 200 ml');
    });

    test('500 count -> "0.5 pc"', () {
      const qty = Qty(500, UnitCategory.count);
      expect(formatter.format(qty), '0.5 pc');
    });

    test('3_000 count -> "3 pc"', () {
      const qty = Qty(3000, UnitCategory.count);
      expect(formatter.format(qty), '3 pc');
    });
  });

  group('mixed style — additional edge cases', () {
    test('zero renders without a big-unit part', () {
      expect(formatter.format(const Qty(0, UnitCategory.weight)), '0 g');
      expect(formatter.format(const Qty(0, UnitCategory.volume)), '0 ml');
      expect(formatter.format(const Qty(0, UnitCategory.count)), '0 pc');
    });

    test('sub-base fractional weight with no whole big unit', () {
      // 250 milliBase = 0.25 g — less than one base unit, no kg part at all.
      expect(formatter.format(const Qty(250, UnitCategory.weight)), '0.25 g');
    });

    test('fractional remainder in the small unit alongside a whole big unit', () {
      // 1_000_250 milliBase weight = 1 kg + 0.25 g.
      expect(formatter.format(const Qty(1000250, UnitCategory.weight)), '1 kg 0.25 g');
    });

    test('a tiny sub-thousandth-of-a-gram amount keeps 3 decimal places', () {
      // 5 milliBase = 0.005 g exactly.
      expect(formatter.format(const Qty(5, UnitCategory.weight)), '0.005 g');
    });

    test('negative quantity is prefixed with a minus sign', () {
      expect(formatter.format(const Qty(-2000000, UnitCategory.weight)), '-2 kg');
    });
  });

  group('compact style', () {
    test('4_450_000 weight -> "4.45 kg"', () {
      const qty = Qty(4450000, UnitCategory.weight);
      expect(formatter.format(qty, style: UnitStyle.compact), '4.45 kg');
    });

    test('a value under 1 big unit still renders in the big unit', () {
      // 450_000 milliBase = 0.45 kg, expressed in kg even though it's under 1.
      const qty = Qty(450000, UnitCategory.weight);
      expect(formatter.format(qty, style: UnitStyle.compact), '0.45 kg');
    });

    test('count is unaffected by compact style', () {
      const qty = Qty(3000, UnitCategory.count);
      expect(formatter.format(qty, style: UnitStyle.compact), '3 pc');
    });

    test('uses the locale decimal separator', () {
      const qty = Qty(4450000, UnitCategory.weight);
      expect(formatter.format(qty, style: UnitStyle.compact, localeTag: 'de_DE'), '4,45 kg');
    });
  });

  group('base style', () {
    test('4_450_000 weight -> "4450 g", no decomposition', () {
      const qty = Qty(4450000, UnitCategory.weight);
      expect(formatter.format(qty, style: UnitStyle.base), '4450 g');
    });

    test('1_200_000 volume -> "1200 ml"', () {
      const qty = Qty(1200000, UnitCategory.volume);
      expect(formatter.format(qty, style: UnitStyle.base), '1200 ml');
    });

    test('count is unaffected by base style', () {
      const qty = Qty(3000, UnitCategory.count);
      expect(formatter.format(qty, style: UnitStyle.base), '3 pc');
    });
  });
}