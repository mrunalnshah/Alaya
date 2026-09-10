import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/split_group.dart';
import 'package:alaya/features/split/presentation/screens/split_group_editor_screen.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

import '../../support/split_harness.dart';

/// [SplitGroupEditorScreen].
///
/// **The screen where default weights are set**, which is what makes "flatmates, 40/30/30" one tap
/// next month instead of four numbers retyped. Everything below is about the two rules that make that
/// safe: weights are all-or-nothing, and a group with expenses cannot be deleted.
void main() {
  /// Feeds one saved group to the editor.
  ///
  /// `splitGroupProvider` is a family, so the override has to name the same argument the screen will
  /// watch — override the wrong id and the screen sits on a real (unoverridden) provider and hangs in
  /// its loading branch, which looks like a broken test rather than a wrong override.
  List<Override> withGroup(
    SplitGroup group, {
    List<String> people = const [],
  }) => [
    ...splitOverrides(
      people: [for (final id in people) person(id, id.toUpperCase())],
    ),
    splitGroupProvider(group.id).overrideWith((ref) => Stream.value(group)),
  ];

  group('a new group', () {
    testWidgets('opens with a name field and the people to choose from', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi'), person('p2', 'Priya')],
        ),
        size: kTallViewport,
      );

      expect(find.text('New group'), findsOneWidget);
      expect(find.text('Ravi'), findsOneWidget);
      expect(find.text('Priya'), findsOneWidget);
    });

    testWidgets('cannot be saved without a name', (tester) async {
      // A group is found by its name everywhere else in the module; an unnamed one would be a row
      // nobody could pick from a dropdown.
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(),
        overrides: splitOverrides(people: [person('p1', 'Ravi')]),
        size: kTallViewport,
      );

      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(save.onPressed, isNull);
    });

    testWidgets('offers no archive switch and no delete', (tester) async {
      // Neither means anything before the group exists. Showing them greyed would be two controls
      // explaining themselves instead of a form.
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(),
        overrides: splitOverrides(people: [person('p1', 'Ravi')]),
        size: kTallViewport,
      );

      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('names where people come from when there are none', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(),
        overrides: splitOverrides(people: []),
        size: kTallViewport,
      );

      expect(find.byType(FilterChip), findsNothing);
      expect(find.textContaining('Add people'), findsOneWidget);
    });
  });

  group('an existing group', () {
    testWidgets('adopts its name and its members', (tester) async {
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(groupId: 'g1'),
        overrides: withGroup(
          splitGroup('g1', 'Flatmates', members: ['p1', 'p2']),
          people: ['p1', 'p2'],
        ),
        size: kTallViewport,
      );

      expect(find.text('Flatmates'), findsOneWidget);
      final chips = tester.widgetList<FilterChip>(find.byType(FilterChip));
      expect(chips.where((c) => c.selected).length, 2);
    });

    testWidgets('offers archiving, and says it is not deleting', (
      tester,
    ) async {
      // The subtitle is where that distinction becomes usable rather than a rule in a document.
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(groupId: 'g1'),
        overrides: withGroup(
          splitGroup('g1', 'Flatmates', members: ['p1']),
          people: ['p1'],
        ),
        size: kTallViewport,
      );

      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.textContaining('history'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('shows a weight box per member once anybody is on it', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(groupId: 'g1'),
        overrides: withGroup(
          splitGroup(
            'g1',
            'Flatmates',
            members: ['p1', 'p2', 'p3'],
            weights: {'p1': 4000, 'p2': 3000, 'p3': 3000},
          ),
          people: ['p1', 'p2', 'p3'],
        ),
        size: kTallViewport,
      );

      // Basis points are stored; whole percent is typed. 4000 reads as 40.
      expect(find.text('40'), findsOneWidget);
      expect(find.text('30'), findsNWidgets(2));
    });
  });

  group('weights are all or nothing', () {
    testWidgets('a partly weighted group says so', (tester) async {
      // **A partial set prefills nothing**, because treating the unweighted member as weightless would
      // invent an instruction — "she did not eat" is a real thing to mean and must never be inferred
      // from a blank field. Somebody who filled three of four boxes needs telling before they save,
      // not when next month's split comes out equal.
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(groupId: 'g1'),
        overrides: withGroup(
          splitGroup(
            'g1',
            'Flatmates',
            members: ['p1', 'p2', 'p3'],
            weights: {'p1': 5000, 'p2': 5000},
          ),
          people: ['p1', 'p2', 'p3'],
        ),
        size: kTallViewport,
      );

      expect(find.text('Set a share for everybody, or none'), findsOneWidget);
    });

    testWidgets('a fully weighted group does not', (tester) async {
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(groupId: 'g1'),
        overrides: withGroup(
          splitGroup(
            'g1',
            'Flatmates',
            members: ['p1', 'p2'],
            weights: {'p1': 6000, 'p2': 4000},
          ),
          people: ['p1', 'p2'],
        ),
        size: kTallViewport,
      );

      expect(find.text('Set a share for everybody, or none'), findsNothing);
    });

    testWidgets('a group with no weights at all does not', (tester) async {
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(groupId: 'g1'),
        overrides: withGroup(
          splitGroup('g1', 'Flatmates', members: ['p1', 'p2']),
          people: ['p1', 'p2'],
        ),
        size: kTallViewport,
      );

      expect(find.text('Set a share for everybody, or none'), findsNothing);
    });
  });

  group('the U15 gate', () {
    testWidgets('no overflow at 320dp with the text scaler doubled', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(groupId: 'g1'),
        overrides: [
          ...splitOverrides(
            people: [
              person('p1', 'Priyadarshini Venkataraman'),
              person('p2', 'Ravi'),
            ],
          ),
          splitGroupProvider('g1').overrideWith(
            (ref) => Stream.value(
              splitGroup(
                'g1',
                'Bandra flatmates and the Goa regulars',
                members: ['p1', 'p2'],
                weights: {'p1': 6000, 'p2': 4000},
              ),
            ),
          ),
        ],
        size: kNarrowPhone,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
