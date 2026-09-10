import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/split/presentation/sheets/name_picker_sheet.dart';

import '../../support/split_harness.dart';

/// [NamePickerSheet].
///
/// **The rule under test is that a phone number appears exactly where a name repeats.** Two people
/// really are called the same thing, and a list showing "Priya" twice is a coin toss — but a phone
/// number beside every row is noise on the ninety-nine that are unambiguous, and noise is what stops
/// people reading a list at all. Both halves of that are asserted, because only enforcing the first
/// gives a list nobody reads.
void main() {
  /// The sheet on its own, which is how it renders inside `AlayaBottomSheet`.
  Widget host({
    required List<Payee> people,
    String? selected,
    Set<String> taken = const {},
  }) => Scaffold(
    body: NamePickerSheet(
      people: people,
      selected: selected,
      taken: taken,
    ),
  );

  group('phone numbers, used precisely', () {
    testWidgets('a unique name shows no phone', (tester) async {
      await pumpSplit(
        tester,
        host(
          people: [
            person('p1', 'Ravi', phone: '98765 43210'),
            person('p2', 'Priya', phone: '91234 56789'),
          ],
        ),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('Ravi'), findsOneWidget);
      expect(find.text('98765 43210'), findsNothing);
      expect(find.text('91234 56789'), findsNothing);
    });

    testWidgets('a repeated name shows both phones', (tester) async {
      // The only field that reliably tells them apart, shown at the only moment it is needed.
      await pumpSplit(
        tester,
        host(
          people: [
            person('p1', 'Priya', phone: '91234 56789'),
            person('p2', 'Priya', phone: '99887 76655'),
            person('p3', 'Ravi', phone: '98765 43210'),
          ],
        ),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('Priya'), findsNWidgets(2));
      expect(find.text('91234 56789'), findsOneWidget);
      expect(find.text('99887 76655'), findsOneWidget);
      // Ravi is unique, so his stays hidden even though he has one.
      expect(find.text('98765 43210'), findsNothing);
    });

    testWidgets('a repeated name with no phone degrades quietly', (
      tester,
    ) async {
      // Nothing to disambiguate with is not an error — the rows are simply identical, which is the
      // truth. Inventing a suffix like "(2)" would name somebody something they are not.
      await pumpSplit(
        tester,
        host(people: [person('p1', 'Priya'), person('p2', 'Priya')]),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('Priya'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('people already on the split', () {
    testWidgets('are shown and disabled, not hidden', (tester) async {
      // **Hiding them is the tempting mistake.** Somebody looking for Ravi and not finding him adds a
      // second Ravi; seeing him greyed with a reason answers the question instead of raising a new one.
      await pumpSplit(
        tester,
        host(
          people: [person('p1', 'Ravi'), person('p2', 'Priya')],
          taken: const {'p1'},
        ),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('Ravi'), findsOneWidget);
      expect(find.text('Already on this split'), findsOneWidget);

      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Ravi'),
      );
      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
    });

    testWidgets('somebody free is still tappable', (tester) async {
      await pumpSplit(
        tester,
        host(
          people: [person('p1', 'Ravi'), person('p2', 'Priya')],
          taken: const {'p1'},
        ),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Priya'),
      );
      expect(tile.enabled, isTrue);
      expect(tile.onTap, isNotNull);
    });
  });

  group('the rest of the sheet', () {
    testWidgets('the current holder is marked', (tester) async {
      await pumpSplit(
        tester,
        host(people: [person('p1', 'Ravi')], selected: 'p1'),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('an empty list says where people come from', (tester) async {
      // A blank sheet leaves somebody wondering whether it failed to load.
      await pumpSplit(
        tester,
        host(people: const []),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.byType(ListTile), findsNothing);
      expect(find.textContaining('Add people'), findsOneWidget);
    });

    testWidgets('adding somebody is always offered, even with an empty list', (
      tester,
    ) async {
      // The affordance that stops this being a dead end — the reason the whole picker exists rather
      // than a chip row that only lists what already happens to be there.
      await pumpSplit(
        tester,
        host(people: const []),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('New person'), findsOneWidget);
    });
  });

  group('the U15 gate', () {
    testWidgets('no overflow at 320dp with the text scaler doubled', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        host(
          people: [
            person(
              'p1',
              'Priyadarshini Venkataraman',
              phone: '+91 98765 43210',
            ),
            person(
              'p2',
              'Priyadarshini Venkataraman',
              phone: '+91 99887 76655',
            ),
          ],
          taken: const {'p1'},
        ),
        overrides: splitOverrides(),
        size: kNarrowPhone,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
