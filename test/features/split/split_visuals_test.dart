import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/features/split/presentation/widgets/split_proportion_bar.dart';
import 'package:alaya/features/split/presentation/widgets/split_tip_row.dart';

import '../../support/split_harness.dart';

/// [SplitProportionBar] and [SplitTipRow].
void main() {
  Money inr(int minor) => Money(minor, 'INR');

  group('the tip arithmetic', () {
    test('is a percentage of the bill, rounded half up', () {
      // ₹4,763 at 10% is ₹476.30 exactly; at 5% it is ₹238.15, which is where a truncating
      // implementation would quietly lose a paisa.
      expect(SplitTipRow.tipOn(inr(476300), 1000), inr(47630));
      expect(SplitTipRow.tipOn(inr(476300), 500), inr(23815));
      expect(SplitTipRow.tipOn(inr(476300), 0), inr(0));
    });

    test('adds to the bill rather than to each share', () {
      // **The only reading that survives "so what did we actually pay".** Dividing first and adding a
      // tip per person happens to agree when the split is equal and disagrees the moment it is not.
      expect(
        SplitTipRow.totalFor(
          base: inr(476300),
          basisPoints: 1000,
          roundUp: false,
          decimalDigits: 2,
        ),
        inr(523930),
      );
    });

    test('rounds up to the next ten, not the next whole unit', () {
      // ₹5,239.30 to ₹5,240 removes the paise and leaves an awkward number. ₹5,240 is the figure
      // somebody says out loud.
      expect(
        SplitTipRow.totalFor(
          base: inr(476300),
          basisPoints: 1000,
          roundUp: true,
          decimalDigits: 2,
        ),
        inr(524000),
      );
    });

    test('rounding a total already on the step leaves it alone', () {
      expect(
        SplitTipRow.totalFor(
          base: inr(500000),
          basisPoints: 0,
          roundUp: true,
          decimalDigits: 2,
        ),
        inr(500000),
      );
    });

    test('the step follows the currency, not the rupee', () {
      // Ten yen, not ten thousand. A zero-decimal currency has no minor units to absorb the difference.
      expect(SplitTipRow.stepFor(2), 1000);
      expect(SplitTipRow.stepFor(0), 10);
    });
  });

  group('the proportion bar', () {
    testWidgets('draws a segment and a legend row per person', (tester) async {
      await pumpSplit(
        tester,
        Scaffold(
          body: SplitProportionBar(
            slices: [
              ProportionSlice(label: 'Person 1', amount: inr(105000)),
              ProportionSlice(
                label: 'Ravi',
                amount: inr(185000),
                extra: inr(80000),
              ),
              ProportionSlice(label: 'Person 3', amount: inr(105000)),
              ProportionSlice(label: 'Person 4', amount: inr(105000)),
            ],
            total: inr(500000),
            decimalDigits: 2,
          ),
        ),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('Ravi'), findsOneWidget);
      // 1,850 of 5,000 is 37%; the other three are 21% each.
      expect(find.text('37%'), findsOneWidget);
      expect(find.text('21%'), findsNWidgets(3));
    });

    testWidgets('renders nothing when there is nothing to scale against', (
      tester,
    ) async {
      // A zero total would divide by zero on the way to a flex, so the guard is the widget's own.
      await pumpSplit(
        tester,
        Scaffold(
          body: SplitProportionBar(
            slices: [ProportionSlice(label: 'A', amount: inr(100))],
            total: inr(0),
            decimalDigits: 2,
          ),
        ),
        overrides: splitOverrides(),
      );

      expect(find.text('A'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at 320dp with the text scaler doubled', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        Scaffold(
          body: SplitProportionBar(
            slices: [
              ProportionSlice(
                label: 'Priyadarshini Venkataraman',
                amount: inr(12345678),
                extra: inr(9999),
              ),
              ProportionSlice(label: 'B', amount: inr(1)),
            ],
            total: inr(12355677),
            decimalDigits: 2,
          ),
        ),
        overrides: splitOverrides(),
        size: kNarrowPhone,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
