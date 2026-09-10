import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/split/presentation/screens/split_bill_screen.dart';
import 'package:alaya/features/split/presentation/widgets/split_proportion_bar.dart';

import '../../support/split_harness.dart';

/// [SplitBillScreen].
///
/// **The property under test is that arithmetic and saving both work before anybody is named.** An
/// earlier version made you create four payee records before you could divide a restaurant bill, and
/// then refused to save until every slot was named — four contact records demanded at the moment
/// everybody is standing up to leave.
///
/// **A participant's label appears twice once there is a result** — once on their row, once in the
/// proportion bar's legend. So the finders below scope to one or the other rather than counting: a
/// bare `findsNWidgets(2)` would pass if both matches were legend rows and the person's own row had
/// vanished.
void main() {
  Future<void> enterAmount(WidgetTester tester, String rupees) async {
    await tester.enterText(find.byType(TextField).first, rupees);
    await tester.pump();
  }

  Future<void> tapPlus(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.widgetWithIcon(IconButton, Icons.add).first);
      await tester.pump();
    }
  }

  /// The label as it appears on a participant's own row, not in the bar's legend.
  Finder onRow(String label) => find.descendant(
    of: find.byType(ListView),
    matching: find.byWidgetPredicate(
      (w) => w is Text && w.data == label && w.style?.fontStyle != null,
    ),
  );

  /// The label as it appears in the bar's legend.
  Finder inLegend(String label) => find.descendant(
    of: find.byType(SplitProportionBar),
    matching: find.text(label),
  );

  FloatingActionButton saveButton(WidgetTester tester) =>
      tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));

  group('it works with nobody named', () {
    testWidgets('opens with you and one anonymous person', (tester) async {
      // **This asserted two placeholders and the model was wrong.** "Two of us" means you and somebody
      // else, so the first slot is claimed for the user — otherwise splitting ₹5,000 four ways produced
      // four strangers owing ₹1,250 each, ₹5,000 owed to you, when one of those four *was* you. Nothing
      // contradicted it because the "I owe" arm of the balance view was unreachable.
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('You'), findsWidgets);
      expect(find.text('Person 2'), findsOneWidget);
      // No amount yet, so no result and no bar to repeat the labels in.
      expect(find.byType(SplitProportionBar), findsNothing);
    });

    testWidgets('divides a bill with no payees in the database at all', (
      tester,
    ) async {
      // `splitOverrides()` supplies an empty people list, so nothing exists to pick from — and the
      // figures still appear.
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(people: []),
        size: kTallViewport,
      );

      await enterAmount(tester, '1000');
      await tapPlus(tester, 2); // two people become four

      expect(onRow('Person 4'), findsOneWidget);
      expect(inLegend('Person 4'), findsOneWidget);
      expect(find.textContaining('250'), findsWidgets);
      expect(find.text('25%'), findsNWidgets(4));
    });

    testWidgets('the stepper never goes below one person', (tester) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      final minus = find.widgetWithIcon(IconButton, Icons.remove).first;
      await tester.tap(minus);
      await tester.pump();
      // Down to one, and the one left is you — slots are removed from the end, so the first stays.
      expect(find.text('You'), findsWidgets);
      expect(find.text('Person 2'), findsNothing);

      // Disabled at one: zero participants is not a split, and the resolver refuses it — so the
      // control refuses first rather than letting a rebuild throw.
      expect(tester.widget<IconButton>(minus).onPressed, isNull);
    });

    testWidgets('removing a person keeps the earlier slots', (tester) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await tapPlus(tester, 2);
      expect(find.text('Person 4'), findsOneWidget);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.remove).first);
      await tester.pump();

      // Removed from the end, so a name already assigned to Person 1 stays on Person 1.
      expect(find.text('Person 3'), findsOneWidget);
      expect(find.text('Person 4'), findsNothing);
    });
  });

  group('saving does not need names', () {
    testWidgets('the save button works with everybody anonymous', (
      tester,
    ) async {
      // **This assertion was the exact opposite two commits ago**, and the old one was wrong: it
      // encoded "name four people before you may save" as though it were a rule rather than a
      // limitation of `split_shares.payee_id` being NOT NULL. `SplitBill.save` now creates a person
      // for anybody anonymous, so the constraint is satisfied without the user doing the work.
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(people: []),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');

      expect(saveButton(tester).onPressed, isNotNull);
    });

    testWidgets('says where the unnamed will land rather than blocking', (
      tester,
    ) async {
      // Information, not a wall. It used to read "Name 2 more people to save this" beside a dead
      // button; it now says what will happen and that the name is fixable.
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');

      // One, not two: the first slot is you. Matched on the word rather than the count, because the ARB
      // pluralises and a test asserting "1 person is unnamed" would break again the moment the copy
      // changed number.
      expect(find.textContaining('unnamed'), findsOneWidget);
      expect(find.textContaining('rename them any time'), findsOneWidget);
    });

    testWidgets('the notice disappears once everybody is named', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(
          groups: [
            splitGroup('g1', 'Flatmates', members: ['p1', 'p2']),
          ],
          people: [person('p1', 'Ravi'), person('p2', 'Priya')],
        ),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');
      expect(find.textContaining('unnamed'), findsOneWidget);

      // Applying a group fills every slot with a real person.
      await tester.tap(find.text('No group'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flatmates').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('unnamed'), findsNothing);
    });

    testWidgets('an amount is still required', (tester) async {
      // There is nothing to save without one — the resolver returns null and the bar draws nothing.
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(saveButton(tester).onPressed, isNull);
    });

    testWidgets('knowing which person you are is still required', (
      tester,
    ) async {
      // **The one gate that stays.** Without `split.selfPayeeId` a balance has no direction: nothing
      // can say whether the others owe you or you owe them, so every figure saved would be a guess.
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(self: null),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');

      expect(saveButton(tester).onPressed, isNull);
      expect(find.textContaining('Choose which person is you'), findsOneWidget);
    });

    testWidgets('copying the result never needs a name either', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(people: []),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');

      final copy = find.textContaining('Copy the result');
      expect(copy, findsOneWidget);
      await tester.tap(copy);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('the tip', () {
    testWidgets('is added to the bill before it is divided', (tester) async {
      // ₹1,000 plus 10% is ₹1,100, two ways is ₹550 each. Dividing first and adding a tip per person
      // reaches the same total here by luck and a different one the moment the split is unequal.
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await enterAmount(tester, '1000');
      await tester.tap(find.text('10% tip'));
      await tester.pump();

      expect(find.textContaining('550'), findsWidgets);
      expect(find.text('Adding'), findsOneWidget);
    });

    testWidgets('tapping the chosen tip again clears it', (tester) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await enterAmount(tester, '1000');
      await tester.tap(find.text('10% tip'));
      await tester.pump();
      expect(find.text('Adding'), findsOneWidget);

      await tester.tap(find.text('10% tip'));
      await tester.pump();
      expect(find.text('Adding'), findsNothing);
      expect(find.textContaining('500'), findsWidgets);
    });

    testWidgets('no tip means no extra line', (tester) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');

      expect(find.text('Adding'), findsNothing);
    });
  });

  group('the picture', () {
    testWidgets('appears only once there is something to draw', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );
      expect(find.byType(SplitProportionBar), findsNothing);

      await enterAmount(tester, '1000');
      expect(find.byType(SplitProportionBar), findsOneWidget);
    });
  });

  group('the methods', () {
    testWidgets('equal offers no per-person field', (tester) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');

      // Only the title field is a `TextFormField` while the split is equal — a weight box per person
      // would be three controls asking a question nobody has.
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('shares reveals a weight box per person', (tester) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');
      await tester.tap(find.text('By shares'));
      await tester.pump();

      // Two participants plus the title field.
      expect(find.byType(TextFormField), findsNWidgets(3));
    });
  });

  group('extras — the restaurant case', () {
    testWidgets('an extra field appears on the row that asks for it', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );
      await enterAmount(tester, '5000');

      expect(find.text('Extra'), findsNWidgets(2));
      await tester.tap(find.text('Extra').first);
      await tester.pump();

      expect(find.text('Just for them'), findsOneWidget);
      // The row that opened one no longer offers to.
      expect(find.text('Extra'), findsOneWidget);
    });
  });

  group('groups', () {
    testWidgets('saving as a group is the one thing that still needs names', (
      tester,
    ) async {
      // A group's members are `payees` rows meant to be reused, and a placeholder is not somebody you
      // meant to keep — so this button waits for two real names even though saving no longer does.
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(people: [person('p1', 'Ravi')]),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');

      expect(find.textContaining('as a group'), findsNothing);
    });
  });

  group('the U15 gate', () {
    testWidgets('no overflow at 320dp with the text scaler doubled', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi'), person('p2', 'Priyadarshini')],
        ),
        size: kNarrowPhone,
        textScale: 2,
      );
      await enterAmount(tester, '5000');
      await tester.tap(find.text('15% tip'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
