import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_parser.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';

void main() {
  const parser = QtyParser();

  // The seeded factors from ARCH_2 §14, so the cases are the ones the app actually meets.
  const kg = 1000000;
  const g = 1000;
  const mg = 1;
  const pc = 1000;
  const dozen = 12000;

  Qty? parsed(
    String input, {
    required int factor,
    UnitCategory category = UnitCategory.weight,
    bool allowNegative = false,
  }) => parser
      .parse(
        input,
        category: category,
        factorToBaseMilli: factor,
        allowNegative: allowNegative,
      )
      .valueOrNull;

  ParseFailure? failed(
    String input, {
    required int factor,
    UnitCategory category = UnitCategory.weight,
    bool allowNegative = false,
  }) => parser
      .parse(
        input,
        category: category,
        factorToBaseMilli: factor,
        allowNegative: allowNegative,
      )
      .failureOrNull;

  group('exact conversion', () {
    test('whole units scale by the factor', () {
      expect(parsed('2', factor: kg), const Qty(2000000, UnitCategory.weight));
      expect(parsed('250', factor: g), const Qty(250000, UnitCategory.weight));
      expect(parsed('5', factor: mg), const Qty(5, UnitCategory.weight));
    });

    test('fractions the unit can express are exact', () {
      expect(
        parsed('0.25', factor: kg),
        const Qty(250000, UnitCategory.weight),
      );
      expect(
        parsed('1.5', factor: kg),
        const Qty(1500000, UnitCategory.weight),
      );
      expect(parsed('0.5', factor: g), const Qty(500, UnitCategory.weight));
    });

    test('half a piece is legal — ARCH_1 §4.2 requires it', () {
      expect(
        parsed('0.5', factor: pc, category: UnitCategory.count),
        const Qty(500, UnitCategory.count),
      );
    });

    test('a factor that is not a power of ten still converts exactly', () {
      expect(
        parsed('0.5', factor: dozen, category: UnitCategory.count),
        const Qty(6000, UnitCategory.count),
      );
      expect(
        parsed('1', factor: dozen, category: UnitCategory.count),
        const Qty(12000, UnitCategory.count),
      );
    });

    test('the category is carried through, not inferred', () {
      expect(
        parsed('1', factor: g, category: UnitCategory.volume),
        const Qty(1000, UnitCategory.volume),
      );
    });
  });

  group('precision is refused, never rounded', () {
    // ARCH_4 R20: the double-backed field turned this into one whole unit and reported success.
    test('a value finer than the unit fails rather than rounding', () {
      expect(failed('0.501', factor: mg), ParseFailure.tooManyDecimalDigits);
      expect(failed('0.0001', factor: g), ParseFailure.tooManyDecimalDigits);
    });

    test('the boundary case is accepted', () {
      expect(parsed('0.001', factor: g), const Qty(1, UnitCategory.weight));
    });
  });

  group('rejections', () {
    test('empty and still-being-typed input', () {
      expect(failed('', factor: g), ParseFailure.empty);
      expect(failed('   ', factor: g), ParseFailure.empty);
      expect(failed('.', factor: g), ParseFailure.malformed);
      expect(failed('1.2.3', factor: g), ParseFailure.malformed);
    });

    test('non-digits', () {
      expect(failed('abc', factor: g), ParseFailure.invalidCharacter);
      expect(failed('1kg', factor: g), ParseFailure.invalidCharacter);
    });

    test('negatives need opting in', () {
      expect(failed('-1', factor: g), ParseFailure.negativeNotAllowed);
      expect(
        parsed('-1', factor: g, allowNegative: true),
        const Qty(-1000, UnitCategory.weight),
      );
    });

    test(
      'a quantity too large to hold is caught before the multiplication',
      () {
        expect(failed('99999999999999', factor: kg), ParseFailure.tooLarge);
      },
    );

    test('a nonsensical factor fails rather than dividing by zero', () {
      expect(failed('1', factor: 0), ParseFailure.malformed);
    });
  });

  test('grouping separators are stripped', () {
    expect(parsed('1,250', factor: g), const Qty(1250000, UnitCategory.weight));
  });

  group('format', () {
    test('renders in the unit with no trailing zeros', () {
      expect(
        parser.format(
          const Qty(4450000, UnitCategory.weight),
          factorToBaseMilli: kg,
        ),
        '4.45',
      );
      expect(
        parser.format(
          const Qty(4450000, UnitCategory.weight),
          factorToBaseMilli: g,
        ),
        '4450',
      );
      expect(
        parser.format(
          const Qty(500, UnitCategory.count),
          factorToBaseMilli: pc,
        ),
        '0.5',
      );
      expect(
        parser.format(
          const Qty(2000000, UnitCategory.weight),
          factorToBaseMilli: kg,
        ),
        '2',
      );
    });

    test('round trips through parse', () {
      const original = Qty(1234500, UnitCategory.weight);
      final text = parser.format(original, factorToBaseMilli: kg);
      expect(parsed(text, factor: kg), original);
    });

    test('negatives keep their sign', () {
      expect(
        parser.format(
          const Qty(-500, UnitCategory.weight),
          factorToBaseMilli: g,
        ),
        '-0.5',
      );
    });
  });
}
