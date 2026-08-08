import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';

void main() {
  group('Qty construction', () {
    test('stores milliBase and category as given', () {
      const qty = Qty(2000000, UnitCategory.weight);
      expect(qty.milliBase, 2000000);
      expect(qty.category, UnitCategory.weight);
    });

    test('Qty.zero is zero in the given category', () {
      const zero = Qty.zero(UnitCategory.weight);
      expect(zero.milliBase, 0);
      expect(zero.isZero, isTrue);
      expect(zero.category, UnitCategory.weight);
    });
  });

  group('Qty arithmetic (same category)', () {
    test('addition sums milliBase', () {
      expect(
        const Qty(1000, UnitCategory.weight) + const Qty(500, UnitCategory.weight),
        const Qty(1500, UnitCategory.weight),
      );
    });

    test('subtraction can go negative', () {
      expect(
        const Qty(500, UnitCategory.weight) - const Qty(1000, UnitCategory.weight),
        const Qty(-500, UnitCategory.weight),
      );
    });

    test('multiplication by an int scales milliBase', () {
      expect(
        const Qty(1000, UnitCategory.weight) * 3,
        const Qty(3000, UnitCategory.weight),
      );
    });

    test('unary minus negates milliBase, keeping category', () {
      expect(-const Qty(1000, UnitCategory.weight), const Qty(-1000, UnitCategory.weight));
    });

    test('isNegative, isPositive, isZero classify correctly', () {
      expect(const Qty(-1, UnitCategory.count).isNegative, isTrue);
      expect(const Qty(1, UnitCategory.count).isPositive, isTrue);
      expect(const Qty(0, UnitCategory.count).isZero, isTrue);
    });
  });

  group('Qty cross-category arithmetic throws', () {
    test('addition across categories throws UnitCategoryMismatchError', () {
      expect(
            () => const Qty(1000, UnitCategory.weight) + const Qty(1000, UnitCategory.volume),
        throwsA(isA<UnitCategoryMismatchError>()),
      );
    });

    test('subtraction across categories throws UnitCategoryMismatchError', () {
      expect(
            () => const Qty(1000, UnitCategory.weight) - const Qty(1000, UnitCategory.count),
        throwsA(isA<UnitCategoryMismatchError>()),
      );
    });
  });

  group('Qty comparisons (same category)', () {
    test('compareTo orders by milliBase', () {
      expect(
        const Qty(100, UnitCategory.weight).compareTo(const Qty(200, UnitCategory.weight)),
        lessThan(0),
      );
    });

    test('< <= > >= behave as expected', () {
      expect(const Qty(100, UnitCategory.weight) < const Qty(200, UnitCategory.weight), isTrue);
      expect(
        const Qty(100, UnitCategory.weight) <= const Qty(100, UnitCategory.weight),
        isTrue,
      );
      expect(
        const Qty(200, UnitCategory.weight) > const Qty(100, UnitCategory.weight),
        isTrue,
      );
      expect(
        const Qty(100, UnitCategory.weight) >= const Qty(100, UnitCategory.weight),
        isTrue,
      );
    });
  });

  group('Qty cross-category comparison throws', () {
    test('compareTo across categories throws UnitCategoryMismatchError', () {
      expect(
            () => const Qty(100, UnitCategory.weight).compareTo(const Qty(100, UnitCategory.volume)),
        throwsA(isA<UnitCategoryMismatchError>()),
      );
    });
  });

  group('Qty equality and hashCode', () {
    test('equal milliBase and category are equal', () {
      expect(const Qty(1000, UnitCategory.weight), const Qty(1000, UnitCategory.weight));
      expect(
        const Qty(1000, UnitCategory.weight).hashCode,
        const Qty(1000, UnitCategory.weight).hashCode,
      );
    });

    test('different category is never equal even with the same milliBase', () {
      expect(const Qty(1000, UnitCategory.weight) == const Qty(1000, UnitCategory.volume), isFalse);
    });

    test('different milliBase is never equal', () {
      expect(const Qty(1000, UnitCategory.weight) == const Qty(2000, UnitCategory.weight), isFalse);
    });
  });

  group('UnitCategory.baseUnitCode', () {
    test('maps each category to its base unit code', () {
      expect(UnitCategory.weight.baseUnitCode, 'g');
      expect(UnitCategory.volume.baseUnitCode, 'ml');
      expect(UnitCategory.count.baseUnitCode, 'pc');
    });
  });
}