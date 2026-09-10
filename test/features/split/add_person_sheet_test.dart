import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/split/presentation/sheets/add_person_sheet.dart';

import '../../support/split_harness.dart';

/// [AddPersonSheet].
///
/// **This sheet exists because reusing `PayeeSheet` broke the module for a week.** That sheet defaults a
/// new payee to `PayeeKind.merchant` — correct for the expense editor, where a payee usually *is* a shop —
/// and `splitPeopleProvider` filters to persons. So everybody added from a split screen was filed as a
/// shop and never appeared: the picker was empty, Settings had nobody to claim as the user,
/// `split.selfPayeeId` stayed null, and **saving a split was impossible.** One wrong default, four steps
/// upstream of the symptom.
///
/// It also returns the id it created. `PayeeSheet.show` returns `Future<void>`, so the caller had to
/// re-read a stream after the sheet closed and diff it — a read that happens before drift has ticked, so
/// the diff was usually empty and the new person silently not selected.
void main() {
  Widget host() => const Scaffold(body: AddPersonSheet());

  group('the form', () {
    testWidgets('asks for a name and an optional phone', (tester) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('Add someone'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      // The label carries "(optional)" itself — `PayeeSheet`'s own comment records that wording as the fix
      // for a two-field sheet feeling like a form, and reusing the key means one control has one name.
      expect(find.textContaining('optional'), findsWidgets);
    });

    testWidgets('says what the phone buys, which the label does not', (
      tester,
    ) async {
      // Two people really are called the same thing, and the phone is the only field that tells them apart
      // in a picker — where it is shown *only* when a name repeats.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.textContaining('two people share a name'), findsOneWidget);
    });

    testWidgets('refuses a blank name, and says so in the field', (
      tester,
    ) async {
      // Inline rather than in a snack: the field is the thing that is wrong, and a message floating at the
      // bottom of the screen makes somebody look for what it refers to.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();

      expect(find.text('They need a name'), findsOneWidget);
    });

    testWidgets('a name of only spaces counts as blank', (tester) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await tester.enterText(find.byType(TextField).first, '   ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();

      expect(find.text('They need a name'), findsOneWidget);
    });
  });

  group('the U15 gate', () {
    testWidgets('no overflow at 320dp with the text scaler doubled', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kNarrowPhone,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
