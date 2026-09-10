import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/split/presentation/screens/split_home_screen.dart';
import 'package:alaya/features/split/presentation/widgets/quick_split_card.dart';
import 'package:alaya/features/split/presentation/widgets/split_groups_list.dart';
import 'package:alaya/features/split/presentation/widgets/split_history_list.dart';

import '../../support/split_harness.dart';

/// [SplitHomeScreen].
///
/// **The first assertion is that there is only one app bar**, because there were two. This screen sits
/// inside the drawer shell, which owns the `Scaffold` and the `AppBar`; the first version wrapped itself
/// in a second `Scaffold` and stacked a bar with a back arrow under the real one, on a destination nobody
/// navigates *into*.
///
/// **The setup-card tests are gone rather than repaired.** `SplitSetupCard` asked who the user is, here,
/// because nothing in the module worked without it. Onboarding's first step asks now — so the assertions
/// below are that the card is *absent* and the escape for somebody who skipped is present, which is the
/// opposite of what they used to say and the correct thing to pin.
///
/// **A section header renders `label.toUpperCase()`**, with the original casing kept only as its
/// `semanticsLabel`. So a header is matched by its upper-case form and a body label by its own.
void main() {
  group('the shell owns the chrome', () {
    testWidgets('the screen adds no app bar of its own', (tester) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(),
      );

      // `pumpInShell` provides exactly one, standing in for `_ShellScaffold`. A second means the screen
      // brought its own back.
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('the screen adds no scaffold and no floating button', (
      tester,
    ) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(),
      );
      expect(find.byType(Scaffold), findsOneWidget);
      // A FAB would belong to the shell, and one placed here would hover over the Groups tab too — the
      // wrong action in the wrong place. "Create a split" is a button in content instead.
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });

  group('three tabs, one destination', () {
    testWidgets('offers Balances, History and Groups', (tester) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('Balances'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Groups'), findsOneWidget);
    });

    testWidgets('Balances is the tab you land on', (tester) async {
      // It answers the question people open the app with, and the quick splitter sits at the top of it so
      // dividing a bill stays zero taps from arriving.
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.byType(QuickSplitCard), findsOneWidget);
      expect(find.byType(SplitHistoryList), findsNothing);
      expect(find.byType(SplitGroupsList), findsNothing);
    });

    testWidgets('History is a tap away, not a route', (tester) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(find.byType(SplitHistoryList), findsOneWidget);
    });

    testWidgets('Groups is a tab, not the screen it was', (tester) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(
          groups: [
            splitGroup('g1', 'Flatmates', members: ['p1']),
          ],
        ),
        size: kTallViewport,
      );

      await tester.tap(find.text('Groups'));
      await tester.pumpAndSettle();

      expect(find.byType(SplitGroupsList), findsOneWidget);
      expect(find.text('Flatmates'), findsOneWidget);
    });
  });

  group('who the user is, asked elsewhere now', () {
    testWidgets('the screen no longer asks', (tester) async {
      // **`SplitSetupCard` used to be here** and is deleted: onboarding's first step asks the same
      // question before Split is ever opened, so the common path never reaches this state at all.
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(self: null),
        size: kTallViewport,
      );

      expect(find.textContaining('What should we call you'), findsNothing);
    });

    testWidgets('somebody who skipped is given a way out', (tester) async {
      // The name step is optional — archetype B makes the whole flow skippable — so declining has to leave
      // a route to answering later. One tap to a settings branch, rather than the four-screen chain this
      // used to be.
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(self: null),
        size: kTallViewport,
      );

      expect(find.text('Who are you?'), findsOneWidget);
      expect(find.text('Shared expenses'), findsOneWidget);
    });

    testWidgets('the calculator works without knowing who you are', (
      tester,
    ) async {
      // Dividing a bill needs no identity. Hiding it behind setup would be friction charged for nothing.
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(self: null),
        size: kTallViewport,
      );

      expect(find.byType(QuickSplitCard), findsOneWidget);
    });
  });

  group('two empty states, because they mean opposite things', () {
    testWidgets('settled up says so', (tester) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(self: 'me'),
        size: kTallViewport,
      );

      expect(find.text('All settled up'), findsOneWidget);
    });

    testWidgets('an unset self payee is a setup step, not a success', (
      tester,
    ) async {
      // Showing "all settled up" when nothing has been measured would tell somebody they were square with
      // everybody, which is a lie the screen can easily tell and never should.
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(self: null),
        size: kTallViewport,
      );

      expect(find.text('All settled up'), findsNothing);
      expect(find.text('Who are you?'), findsOneWidget);
    });
  });

  group('balances', () {
    testWidgets('each direction gets its own section', (tester) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi'), person('p2', 'Priya')],
          balances: [owedToMe('p1', 185000), iOwe('p2', 40000)],
        ),
        size: kTallViewport,
      );

      expect(find.text('Ravi'), findsOneWidget);
      expect(find.text('Priya'), findsOneWidget);

      // Upper case for the headers, because `SectionHeader` shouts its label; mixed case for the totals
      // card, which is body copy. Direction is carried by *which* section a row sits under, since
      // `AmountText` has no tone parameter and a colour does not survive a screenshot.
      expect(find.text('OWED TO YOU'), findsOneWidget);
      expect(find.text('YOU OWE'), findsOneWidget);
      expect(find.text('Owed to you'), findsOneWidget);
      expect(find.text('You owe'), findsOneWidget);
    });

    testWidgets('a placeholder is offered a name where it is read', (
      tester,
    ) async {
      // **The row somebody will want to fix the moment they see it.** Saving a split writes a
      // `PayeeKind.splitPlaceholder` for anybody anonymous so the debt can exist at all, and this is where
      // that gets corrected — read from `kind`, so a real contact called "Person 5" is never offered a
      // rename it does not need.
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(
          placeholders: [placeholder('p9', 'Person 4')],
          balances: [owedToMe('p9', 125000)],
        ),
        size: kTallViewport,
      );

      expect(find.text('Person 4'), findsOneWidget);
      expect(find.text('Who is this?'), findsOneWidget);
    });

    testWidgets('a real person is not offered one', (tester) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Person 5')],
          balances: [owedToMe('p1', 125000)],
        ),
        size: kTallViewport,
      );

      expect(find.text('Person 5'), findsOneWidget);
      expect(find.text('Who is this?'), findsNothing);
    });

    testWidgets('an old debt says how old', (tester) async {
      // The nudge no competitor sends. It needs no due date — the balance view already carries the oldest
      // contributing expense, and the day count is computed against the injected clock.
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi')],
          balances: [owedToMe('p1', 185000, since: const DateKey(20260714))],
          today: const DateKey(20260814),
        ),
        size: kTallViewport,
      );

      expect(find.text('31 days'), findsOneWidget);
    });

    testWidgets('a recent debt is not nagged about', (tester) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi')],
          balances: [owedToMe('p1', 185000, since: const DateKey(20260812))],
          today: const DateKey(20260814),
        ),
        size: kTallViewport,
      );

      expect(find.textContaining('days'), findsNothing);
    });
  });

  group('the actions', () {
    testWidgets('creating a split is offered on the screen itself', (
      tester,
    ) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('Create a split'), findsOneWidget);
    });

    testWidgets('sharing is disabled when there is nothing to share', (
      tester,
    ) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(balances: []),
        size: kTallViewport,
      );

      final share = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Share'),
      );
      expect(share.onPressed, isNull);
    });

    testWidgets('sharing is offered once somebody owes something', (
      tester,
    ) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi')],
          balances: [owedToMe('p1', 185000)],
        ),
        size: kTallViewport,
      );

      final share = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Share'),
      );
      expect(share.onPressed, isNotNull);
    });
  });

  group('the U15 gate', () {
    testWidgets('no overflow at 320dp with the text scaler doubled', (
      tester,
    ) async {
      // **This one found a real bug.** `Row(Expanded(name), AmountText)` cannot shrink an amount below its
      // own text, so ₹1,23,456.78 at 2.0 overran by 215 pixels. Every row that pairs text with a figure is
      // a `Wrap` now, and this is what holds that.
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Priyadarshini Venkataraman')],
          balances: [
            owedToMe('p1', 12345678, since: const DateKey(20260601)),
          ],
        ),
        size: kNarrowPhone,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
