import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/settings/presentation/screens/split_settings_screen.dart';

import '../../support/split_harness.dart';

/// [SplitSettingsScreen].
///
/// **This screen changed role rather than shrinking.** It used to be the only place `split.selfPayeeId`
/// could be set, which made it the destination of a redirect chain: three split screens noticed the
/// setting was missing and pointed here, at a list of candidates that was empty because adding somebody
/// from anywhere filed them as a merchant.
///
/// Onboarding asks the name now, first, before Split is ever opened. So this is what a settings branch
/// should be — somewhere to *change* a decision, not to make one — and the assertions below are about
/// that, not about first-run behaviour it no longer owns.
void main() {
  group('choosing who you are', () {
    testWidgets('lists everybody who could be you', (tester) async {
      await pumpSplit(
        tester,
        const SplitSettingsScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi'), person('p2', 'Priya')],
        ),
        size: kTallViewport,
      );

      expect(find.text('Ravi'), findsOneWidget);
      expect(find.text('Priya'), findsOneWidget);
      expect(find.byType(RadioListTile<String>), findsNWidgets(2));
    });

    testWidgets('placeholders are not offered as candidates', (tester) async {
      // **A placeholder is a row this app wrote, not somebody you could be.** `splitPeopleProvider`
      // filters to `PayeeKind.person`, and the harness feeds placeholders only to
      // `splitParticipantsProvider` — the same split the app makes, so the test cannot pass for the wrong
      // reason.
      await pumpSplit(
        tester,
        const SplitSettingsScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi')],
          placeholders: [placeholder('p9', 'Person 4')],
        ),
        size: kTallViewport,
      );

      expect(find.text('Ravi'), findsOneWidget);
      expect(find.text('Person 4'), findsNothing);
      expect(find.byType(RadioListTile<String>), findsOneWidget);
    });

    testWidgets('marks the current choice', (tester) async {
      await pumpSplit(
        tester,
        const SplitSettingsScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi'), person('p2', 'Priya')],
          self: 'p2',
        ),
        size: kTallViewport,
      );

      final tiles = tester
          .widgetList<RadioListTile<String>>(find.byType(RadioListTile<String>))
          .toList();
      // Asserted on the widget's own state rather than on a painted dot, which a theme could change.
      expect(tiles.where((t) => t.value == t.groupValue).length, 1);
      expect(tiles.firstWhere((t) => t.value == 'p2').groupValue, 'p2');
    });

    testWidgets('names the prerequisite when nobody exists yet', (
      tester,
    ) async {
      // Names what to do instead of showing a blank area. A person has to exist as a payee before they
      // can be claimed, and saying so beats an empty list the reader has to interpret.
      await pumpSplit(
        tester,
        const SplitSettingsScreen(),
        overrides: splitOverrides(people: []),
        size: kTallViewport,
      );

      expect(find.byType(RadioListTile<String>), findsNothing);
      expect(find.textContaining('Add people under Payees'), findsOneWidget);
    });

    testWidgets('adding somebody is offered even with an empty list', (
      tester,
    ) async {
      // Through `AddPersonSheet`, not `PayeeSheet`: the shared sheet defaults a new payee to
      // `PayeeKind.merchant`, so anybody added from here used to vanish from the very list that sent them
      // to add somebody.
      await pumpSplit(
        tester,
        const SplitSettingsScreen(),
        overrides: splitOverrides(people: []),
        size: kTallViewport,
      );

      expect(find.text('Add person'), findsOneWidget);
    });
  });

  group('how people can pay you', () {
    testWidgets('is free text with no assumptions about a country', (
      tester,
    ) async {
      // **The field used to be a UPI id with an email keyboard**, which quietly assumed India. It now
      // holds a PayPal link, an IBAN, a Venmo handle or a sentence, so there is nothing to validate and no
      // keyboard hint that would be wrong somewhere.
      await pumpSplit(
        tester,
        const SplitSettingsScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('Payment details'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autocorrect, isFalse);
      // Room for an IBAN, which does not fit on one line at any sensible width.
      expect(field.maxLines, 2);
    });

    testWidgets('says what it buys rather than what it is', (tester) async {
      await pumpSplit(
        tester,
        const SplitSettingsScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(
        find.textContaining('added to the end of any summary'),
        findsOneWidget,
      );
    });
  });

  group('what it no longer links to', () {
    testWidgets('offers no route to Groups', (tester) async {
      // **This assertion is the inverse of the one it replaces.** Groups are a tab on `/split` now, and a
      // settings branch offering a shortcut into a tab of another destination is the cross-linking that
      // made this module a maze — seven routes where two would do. The screen has no navigation left in
      // it at all, which is why it no longer imports `go_router`.
      await pumpSplit(
        tester,
        const SplitSettingsScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi')],
          groups: [
            splitGroup('g1', 'Flatmates', members: ['p1']),
          ],
        ),
        size: kTallViewport,
      );

      expect(find.text('Groups'), findsNothing);
      expect(find.text('Flatmates'), findsNothing);
    });
  });

  group('the U15 gate', () {
    testWidgets('no overflow at 320dp with the text scaler doubled', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitSettingsScreen(),
        overrides: splitOverrides(
          people: [
            person('p1', 'Priyadarshini Venkataraman'),
            person('p2', 'Ravi'),
          ],
          self: 'p1',
        ),
        size: kNarrowPhone,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
