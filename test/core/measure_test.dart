import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/fraction.dart';
import 'package:alaya/core/quantity/measure.dart';
import 'package:alaya/core/quantity/measure_formatter.dart';
import 'package:alaya/core/quantity/measure_parser.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';

/// The three vessel factors from the `units` seed, plus the two that divide cleanly.
///
/// **The awkward ones are the point.** ARCH_M §7: "test with the awkward factors: 240000 divides cleanly
/// and would have passed." A cup is 240000 and hides every rounding fault; a teaspoon is 4929, which is
/// odd, not divisible by two, and is where the previous implementation broke.
const int kTsp = 4929;
const int kTbsp = 14787;
const int kCup = 240000;
const int kMl = 1000;
const int kLitre = 1000000;

void main() {
  const parser = MeasureParser();
  const formatter = MeasureFormatter();

  group('Fraction', () {
    test('reduces, so 2/4 and 1/2 are one value', () {
      expect(Fraction(2, 4), Fraction(1, 2));
      expect(Fraction(6, 8).denominator, 4);
      expect(Fraction(0, 7), Fraction.zero);
    });

    test('quantises to thousandths, half up', () {
      expect(Fraction(1, 2).milliOfUnit, 500);
      expect(Fraction(1, 3).milliOfUnit, 333);
      expect(Fraction(2, 3).milliOfUnit, 667);
      expect(Fraction(1, 8).milliOfUnit, 125);
      // 62.5 rounds up rather than truncating to 62 — the truncation ARCH_M §7 records.
      expect(Fraction(1, 16).milliOfUnit, 63);
    });

    test('refuses a zero or negative denominator', () {
      expect(() => Fraction(1, 0), throwsArgumentError);
      expect(() => Fraction(1, -2), throwsArgumentError);
    });
  });

  group('fractionForMilli — recognition by round trip, not by table', () {
    test('finds every fraction a drawer contains', () {
      for (final fraction in kMeasuringSet) {
        expect(
          fractionForMilli(fraction.milliOfUnit),
          fraction,
          reason: 'failed for $fraction',
        );
      }
    });

    test('finds the fractions the old nine-entry table did', () {
      // Every key of the table this replaced. None of them may regress.
      const table = {
        125: '1/8',
        250: '1/4',
        333: '1/3',
        375: '3/8',
        500: '1/2',
        625: '5/8',
        667: '2/3',
        750: '3/4',
        875: '7/8',
      };
      for (final entry in table.entries) {
        expect(fractionForMilli(entry.key).toString(), entry.value);
      }
      // A count beside the set, per ARCH_M §7: without it, a shrinking expectation passes quietly.
      expect(table, hasLength(9));
    });

    test('finds fractions the old table could not', () {
      // The whole complaint: these rendered as decimals before.
      expect(fractionForMilli(63).toString(), '1/16');
      expect(fractionForMilli(167).toString(), '1/6');
      expect(fractionForMilli(833).toString(), '5/6');
      expect(fractionForMilli(200).toString(), '1/5');
      expect(fractionForMilli(143).toString(), '1/7');
    });

    test('returns the simplest denominator, not the first that fits', () {
      expect(fractionForMilli(500).toString(), '1/2');
      expect(fractionForMilli(250).toString(), '1/4');
      expect(fractionForMilli(750).toString(), '3/4');
    });

    test('returns null rather than inventing precision', () {
      // 137 is closest to 2/15, which is 0.1333 — not close enough to have been stored as 137.
      expect(fractionForMilli(137), isNull);
      expect(fractionForMilli(0), isNull);
      expect(fractionForMilli(1000), isNull);
    });

    test('every fraction it returns round-trips to the input', () {
      // The property the whole design rests on, asserted across the entire domain rather than at
      // sampled points: if a fraction comes back, storing it again must reproduce the same thousandths.
      for (var milli = 1; milli < 1000; milli++) {
        final fraction = fractionForMilli(milli);
        if (fraction == null) continue;
        expect(
          fraction.milliOfUnit,
          milli,
          reason: '$fraction did not round-trip from $milli',
        );
      }
    });
  });

  group('Measure — the Qty round trip', () {
    test('survives every vessel factor, across the whole useful range', () {
      // ARCH_M §7's recorded failure, asserted as a property. 4929 is the factor that broke it.
      for (final factor in [kTsp, kTbsp, kCup, kMl, kLitre]) {
        for (var milli = 0; milli <= 10000; milli++) {
          final measure = Measure(milli);
          final restored = Measure.fromQty(
            measure.toQty(
              factorToBaseMilli: factor,
              category: UnitCategory.volume,
            ),
            factorToBaseMilli: factor,
          );
          expect(
            restored.milliOfUnit,
            milli,
            reason: 'factor $factor lost $milli',
          );
        }
      }
    });

    test('half a tablespoon is 7393 or 7394, and comes back as a half', () {
      final half = Measure.of(0, Fraction(1, 2));
      final quantity = half.toQty(
        factorToBaseMilli: kTbsp,
        category: UnitCategory.volume,
      );
      // 14787 / 2 is 7393.5. Either neighbour is acceptable; silently becoming 499 thousandths is not.
      expect(quantity.milliBase, anyOf(7393, 7394));
      expect(
        Measure.fromQty(quantity, factorToBaseMilli: kTbsp).remainderMilli,
        500,
      );
    });

    test('composes and decomposes a whole part and a fraction', () {
      final measure = Measure.of(3, Fraction(1, 2));
      expect(measure.milliOfUnit, 3500);
      expect(measure.whole, 3);
      expect(measure.remainderMilli, 500);
      expect(measure.withWhole(0).milliOfUnit, 500);
      expect(measure.withFraction(null).milliOfUnit, 3000);
    });

    test('scales upward, matching the engine rather than contradicting it', () {
      // `CookabilityEngine.scaleMilli` takes a ceiling because a false "you have enough" ruins dinner.
      // A display that rounded down would show less than the verdict demands.
      expect(
        Measure(1000).scaled(fromServings: 3, toServings: 2).milliOfUnit,
        667,
      );
      expect(
        Measure(12345).scaled(fromServings: 4, toServings: 4).milliOfUnit,
        12345,
      );
      expect(
        () => Measure(1000).scaled(fromServings: 0, toServings: 1),
        throwsArgumentError,
      );
    });
  });

  group('MeasureParser — what cooks write', () {
    test('plain numbers and decimals', () {
      expect(parser.parse('2').valueOrNull, const Measure(2000));
      expect(parser.parse('0.5').valueOrNull, const Measure(500));
      expect(parser.parse('.5').valueOrNull, const Measure(500));
    });

    test('fractions, including ones no chip offers', () {
      expect(parser.parse('1/2').valueOrNull, const Measure(500));
      expect(parser.parse('3/4').valueOrNull, const Measure(750));
      expect(parser.parse('2/3').valueOrNull, const Measure(667));
      expect(parser.parse('5/16').valueOrNull, const Measure(313));
    });

    test('a whole part and a fraction', () {
      expect(parser.parse('1 1/2').valueOrNull, const Measure(1500));
      expect(parser.parse('2 3/4').valueOrNull, const Measure(2750));
    });

    test('the vulgar fractions a pasted recipe carries', () {
      expect(parser.parse('½').valueOrNull, const Measure(500));
      expect(parser.parse('⅔').valueOrNull, const Measure(667));
      expect(parser.parse('⅜').valueOrNull, const Measure(375));
      // With and without the space, because a website emits either.
      expect(parser.parse('1½').valueOrNull, const Measure(1500));
      expect(parser.parse('1 ½').valueOrNull, const Measure(1500));
    });

    test('names its refusals', () {
      expect(parser.parse('').failureOrNull, ParseFailure.empty);
      expect(parser.parse('-1').failureOrNull, ParseFailure.negativeNotAllowed);
      expect(parser.parse('1 2 3').failureOrNull, ParseFailure.malformed);
      expect(parser.parse('1/0').failureOrNull, ParseFailure.malformed);
      // A denominator that would quantise to nothing is refused rather than read as zero.
      expect(parser.parse('1/5000').failureOrNull, ParseFailure.malformed);
    });

    test('what is typed is what is rendered', () {
      // The round trip a user actually notices: type 2/3, see 2/3. Not 0.667.
      for (final written in [
        '1/2',
        '3/4',
        '2/3',
        '1/3',
        '1/8',
        '1 1/2',
        '5/16',
      ]) {
        final measure = parser.parse(written).valueOrNull;
        expect(measure, isNotNull, reason: 'could not parse $written');
        expect(formatter.format(measure!).text, written);
      }
    });
  });

  group('MeasureFormatter — exact style', () {
    test('renders whole numbers without a fraction', () {
      expect(formatter.format(const Measure(2000)).text, '2');
      expect(formatter.format(const Measure(0)).text, '0');
    });

    test('never marks anything approximate', () {
      for (final milli in [137, 222, 500, 3500, 63]) {
        expect(formatter.format(Measure(milli)).isApproximate, isFalse);
      }
    });

    test('falls back to a decimal when no fraction fits', () {
      final rendered = formatter.format(const Measure(137));
      expect(rendered.text, '0.137');
      expect(rendered.fraction, isNull);
    });
  });

  group('MeasureFormatter — kitchen style', () {
    test('222 thousandths of a cup is a quarter cup', () {
      // The case that motivated the style. 2/9 is the honest fraction and no drawer contains a ninth.
      final rendered = formatter.format(
        const Measure(222),
        style: MeasureStyle.kitchen,
      );
      expect(rendered.text, '1/4');
      expect(rendered.isApproximate, isTrue);
      expect(rendered.measure.milliOfUnit, 250);
    });

    test('leaves an amount alone when it is already in the drawer', () {
      // And therefore claims nothing: no snap, no glyph, no caveat on a figure that needs none.
      for (final fraction in kMeasuringSet) {
        final rendered = formatter.format(
          Measure(fraction.milliOfUnit),
          style: MeasureStyle.kitchen,
        );
        expect(rendered.isApproximate, isFalse, reason: 'snapped $fraction');
        expect(rendered.text, fraction.toString());
      }
    });

    test('carries into the whole part when the snap reaches a full unit', () {
      final rendered = formatter.format(
        const Measure(1960),
        style: MeasureStyle.kitchen,
      );
      expect(rendered.text, '2');
      expect(rendered.isApproximate, isTrue);
    });

    test('a tie snaps upward, because understating ruins the dish', () {
      // **875 is the only genuine tie in the drawer**, sitting exactly 125 from both 3/4 and a whole
      // unit — the other six gaps have non-integer midpoints, so no thousandths value lands on them.
      // Upward means it becomes one whole unit rather than three quarters, matching
      // `CookabilityEngine.scaleMilli`'s direction.
      //
      // I asserted 625 -> 3/4 first, reasoning from the halves and quarters and forgetting that the
      // drawer contains 2/3 between them. It snaps to 2/3, which is 42 thousandths away rather than 125.
      final tie = formatter.format(
        const Measure(875),
        style: MeasureStyle.kitchen,
      );
      expect(tie.text, '1');
      expect(tie.isApproximate, isTrue);

      expect(
        formatter.format(const Measure(625), style: MeasureStyle.kitchen).text,
        '2/3',
      );
    });

    test('every snapped value is itself renderable', () {
      // A snap that produced something the formatter then rendered as a decimal would defeat the
      // purpose. Asserted across the whole remainder range rather than at sampled points.
      for (var milli = 1; milli < 4000; milli++) {
        final rendered = formatter.format(
          Measure(milli),
          style: MeasureStyle.kitchen,
        );
        expect(
          rendered.text,
          isNot(contains('.')),
          reason: '$milli snapped to an unrenderable ${rendered.text}',
        );
      }
    });
  });

  group('chipsFor — the drawer plus the present tense', () {
    test('offers the drawer when nothing unusual is set', () {
      expect(formatter.chipsFor(const Measure(0)), kMeasuringSet);
      expect(formatter.chipsFor(const Measure(500)), kMeasuringSet);
      expect(formatter.chipsFor(const Measure(3250)), kMeasuringSet);
    });

    test('a typed fraction becomes a chip, in order', () {
      final chips = formatter.chipsFor(const Measure(313));
      expect(chips, hasLength(kMeasuringSet.length + 1));
      expect(chips.contains(Fraction(5, 16)), isTrue);
      // Sorted, so the new chip appears where a cook would look for it rather than tacked on the end.
      expect(chips, orderedEquals(<Fraction>[...chips]..sort()));
    });

    test('adds nothing when the amount has no simple fraction', () {
      expect(formatter.chipsFor(const Measure(137)), kMeasuringSet);
    });
  });

  group('Qty is untouched', () {
    test('a measure converts to the canonical quantity the engine compares', () {
      // The engine, the database and the cook flow all still speak Qty. This type is a lens on it, not
      // a replacement for it — nothing above needs to learn a new storage format.
      final measure = Measure.of(2, Fraction(1, 2));
      expect(
        measure.toQty(factorToBaseMilli: kCup, category: UnitCategory.volume),
        const Qty(600000, UnitCategory.volume),
      );
    });
  });
}
