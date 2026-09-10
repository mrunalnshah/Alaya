import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/split/presentation/widgets/split_groups_list.dart';

import '../../support/split_harness.dart';

/// [SplitGroupsList].
///
/// **Replaces `split_groups_screen_test.dart`.** The screen it tested is gone — the list is a tab on
/// `/split` and a row opens a bottom sheet rather than pushing a route. Every assertion below is one the
/// old file made; only the widget under test and the chrome around it changed.
void main() {
  /// The list as the home screen mounts it: a tab body inside a `Scaffold` the shell owns.
  Widget host() => const Scaffold(body: SplitGroupsList());

  group('the list', () {
    testWidgets('names each group and counts its members', (tester) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(
          groups: [
            splitGroup('g1', 'Flatmates', members: ['p1', 'p2', 'p3']),
            splitGroup('g2', 'Goa trip', members: ['p1', 'p2']),
          ],
        ),
        size: kTallViewport,
      );

      expect(find.text('Flatmates'), findsOneWidget);
      expect(find.text('3 people'), findsOneWidget);
      expect(find.text('2 people'), findsOneWidget);
    });

    testWidgets('says what a group will do before it is used', (tester) async {
      // A group carrying 40/30/30 behaves differently from one that splits equally, and that is worth
      // knowing from the list rather than after opening the editor.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(
          groups: [
            splitGroup(
              'g1',
              'Flatmates',
              members: ['p1', 'p2'],
              weights: {'p1': 6000, 'p2': 4000},
            ),
            splitGroup('g2', 'Goa trip', members: ['p1', 'p2']),
          ],
        ),
        size: kTallViewport,
      );

      expect(find.text('Custom shares'), findsOneWidget);
    });

    testWidgets('an archived group is shown greyed, not hidden', (
      tester,
    ) async {
      // **Hiding it is the tempting mistake.** Archiving keeps a group's history and its balances and
      // only removes it from the pickers; hiding it here makes "where did my flatmates group go"
      // unanswerable from the one place that exists to answer it.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(
          groups: [
            splitGroup('g1', 'Old trip', members: ['p1'], archived: true),
          ],
        ),
        size: kTallViewport,
      );

      expect(find.text('Old trip'), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);
    });
  });

  group('empty', () {
    testWidgets('explains what a group buys rather than saying "none"', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(groups: []),
        size: kTallViewport,
      );

      expect(find.text('No groups yet'), findsOneWidget);
      expect(
        find.textContaining('saves entering the same people'),
        findsOneWidget,
      );
    });

    testWidgets('making one is still offered when the list is empty', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(groups: []),
        size: kTallViewport,
      );

      expect(find.text('New group'), findsOneWidget);
    });
  });

  group('the chrome it no longer owns', () {
    testWidgets('adds no app bar and no floating button', (tester) async {
      // **It was a screen with both.** As a tab it may have neither: the app bar belongs to
      // `_ShellScaffold`, and a FAB placed here would hover over the Balances tab too — the wrong action
      // in the wrong place. "New group" is a button above the list instead.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(
          groups: [
            splitGroup('g1', 'Flatmates', members: ['p1']),
          ],
        ),
        size: kTallViewport,
      );

      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });

  group('the U15 gate', () {
    testWidgets('a long name with both chips does not overflow', (
      tester,
    ) async {
      // **This is the case that was broken.** The row was a `Row(Expanded, chip, chip)` — three children
      // that cannot shrink — which is the shape that overran the split home screen by 215 pixels. An
      // archived group with custom shares carries both chips at once, so it is the worst one.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(
          groups: [
            splitGroup(
              'g1',
              'Bandra flatmates and the Goa regulars',
              members: ['p1', 'p2', 'p3', 'p4'],
              weights: {'p1': 4000, 'p2': 2000, 'p3': 2000, 'p4': 2000},
              archived: true,
            ),
          ],
        ),
        size: kNarrowPhone,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
