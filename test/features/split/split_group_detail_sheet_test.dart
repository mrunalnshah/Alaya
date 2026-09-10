import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/features/split/presentation/sheets/split_group_detail_sheet.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

import '../../support/split_harness.dart';

/// [SplitGroupDetailSheet].
///
/// **Was `/split/groups/:groupId`, the second level of a stack behind a tab.** Nothing on it was an
/// editor — it read balances and offered three actions — so the route bought a back arrow, an app bar with
/// three competing targets, and somewhere for a user to end up without knowing how. The screen it replaces
/// had no test either; these are the first assertions this content has ever had.
void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    required List<String> members,
    List<Override> balances = const [],
    Size size = kTallViewport,
    double textScale = 1,
  }) => pumpSplit(
    tester,
    const Scaffold(body: SplitGroupDetailSheet(groupId: 'g1')),
    overrides: [
      ...splitOverrides(
        people: [person('p1', 'Ravi'), person('p2', 'Priya')],
      ),
      splitGroupProvider('g1').overrideWith(
        (ref) => Stream.value(
          splitGroup('g1', 'Flatmates', members: members),
        ),
      ),
      ...balances,
    ],
    size: size,
    textScale: textScale,
  );

  /// Feeds one group's balances.
  ///
  /// **Typed `List<SplitBalance>`, not `List<Object>` with a cast.** The first draft took `Object` and used
  /// `as dynamic` to satisfy the override — which compiles against anything and would have failed at
  /// runtime the moment the provider's element type changed. `as dynamic` to make a call compile means the
  /// call is wrong, and this file is not exempt from that.
  Override groupBalances(List<SplitBalance> rows) =>
      splitGroupBalancesProvider('g1').overrideWith(
        (ref) => Stream.value(rows),
      );

  group('what it shows', () {
    testWidgets('names the group and counts its members', (tester) async {
      await pumpSheet(tester, members: ['p1', 'p2']);

      expect(find.text('Flatmates'), findsOneWidget);
      expect(find.text('2 people'), findsOneWidget);
    });

    testWidgets('settled is said plainly, not left as blank space', (
      tester,
    ) async {
      // An empty area where balances would be reads as a sheet that failed to load half of itself.
      await pumpSheet(tester, members: ['p1', 'p2']);

      expect(find.text('All settled up'), findsOneWidget);
    });

    testWidgets('a balance carries its direction in words', (tester) async {
      // **Not in colour.** `AmountText` has no tone parameter — it colours from `kind`, deliberately, so
      // one movement of money never renders as two different things — and a sentence survives a screenshot
      // and a colour-blind reader.
      await pumpSheet(
        tester,
        members: ['p1', 'p2'],
        balances: [
          groupBalances([owedToMe('p1', 185000)]),
        ],
      );

      expect(find.text('Ravi'), findsOneWidget);
      expect(find.textContaining('owes you'), findsOneWidget);
    });

    testWidgets('shows no activity feed', (tester) async {
      // **The screen this replaces rendered the group's activity too.** The History tab shows every
      // group's at once now, and keeping both made the sheet long enough to scroll past the actions —
      // which are the reason somebody opened it.
      await pumpSheet(
        tester,
        members: ['p1'],
        balances: [
          groupBalances([owedToMe('p1', 185000)]),
        ],
      );

      expect(find.textContaining('Activity'), findsNothing);
    });
  });

  group('the actions', () {
    testWidgets('settling is the emphasised one', (tester) async {
      // Share and Edit are things you do *to* a group; settling is why you looked.
      await pumpSheet(tester, members: ['p1', 'p2']);

      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNWidgets(2));
    });

    testWidgets('offers share and edit without competing for the title', (
      tester,
    ) async {
      await pumpSheet(tester, members: ['p1', 'p2']);

      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('adds no scaffold, app bar or floating button', (tester) async {
      // It is a sheet now. `pumpSheet` supplies the only `Scaffold`; anything more means this content
      // brought its screen chrome with it.
      await pumpSheet(tester, members: ['p1']);

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });

  group('the U15 gate', () {
    testWidgets('no overflow at 320dp with the text scaler doubled', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        members: ['p1', 'p2'],
        balances: [
          groupBalances([owedToMe('p1', 12345678)]),
        ],
        size: kNarrowPhone,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
