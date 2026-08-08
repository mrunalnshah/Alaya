import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/settings/presentation/screens/accounts_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/currencies_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/security_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/settings_screen.dart';
import 'package:alaya/features/settings/providers/app_settings_providers.dart';
import 'package:alaya/features/settings/presentation/screens/tags_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/units_settings_screen.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/settings_harness.dart';

/// Tall enough that a lazy `ListView` builds its whole body.
///
/// **Content assertions get this; the U15 gate does not.** A settings body is a lazy list, so at 320x640 a
/// row below the fold is never built and `findsNothing` passes for the wrong reason — the same trap 7B's
/// analytics sliver had. Splitting the two concerns is the fix: these tests ask *what exists*, and the
/// separate 320x640 tests ask *whether it fits*. Scrolling was the alternative and it is worse here, because
/// `find...last` on a not-yet-built widget throws `Bad state: No element` rather than failing an assertion.
const Size kTallViewport = Size(320, 2000);

/// The settings tree and its branches — four states each (Law U4, ARCH_5 §9.1).
void main() {
  group('the tree', () {
    testWidgets('groups every branch and declares no chrome of its own', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const SettingsScreen(),
        overrides: settingsOverrides(),
        wrapInShell: true,
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      // **By semantics label, not by text.** `SectionHeader` renders `label.toUpperCase()` and supplies the
      // original as `semanticsLabel` — so asserting the visible string would couple this test to a styling
      // choice, and asserting `'YOUR MONEY'` would break the day that choice changes.
      expect(find.bySemanticsLabel('Your money'), findsOneWidget);
      expect(find.bySemanticsLabel('Your things'), findsOneWidget);
      expect(find.bySemanticsLabel('The app'), findsOneWidget);
      // Exactly one Scaffold — the harness's stand-in for the drawer shell — and no AppBar, because `/settings`
      // is a shell destination and a bar declared here would be a second one inside it (Law U18).
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
    });

    testWidgets('search matches a keyword, not only a title', (tester) async {
      await pumpSettings(
        tester,
        const SettingsScreen(),
        overrides: settingsOverrides(),
        wrapInShell: true,
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'dark');
      await tester.pumpAndSettle();
      // Nothing in the app is called "dark", which is the whole point: a tree matching only headings would answer
      // "no results" for a setting sitting right there.
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Accounts'), findsNothing);
    });

    testWidgets('a query matching nothing names the search, not the tree', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const SettingsScreen(),
        overrides: settingsOverrides(),
        wrapInShell: true,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'zzzz');
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.textContaining('Nothing matches'), findsOneWidget);
    });

    testWidgets('renders at 320x640 with a doubled text scale', (tester) async {
      await pumpSettings(
        tester,
        const SettingsScreen(),
        overrides: settingsOverrides(),
        wrapInShell: true,
        textScale: 2,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('accounts', () {
    testWidgets('loading is a skeleton, not a spinner', (tester) async {
      await pumpSettings(
        tester,
        const AccountsSettingsScreen(),
        overrides: settingsOverrides(
          accounts: const AsyncValue<List<Account>>.loading(),
        ),
      );
      expect(find.byType(AlayaListSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('error carries the repository message', (tester) async {
      await pumpSettings(
        tester,
        const AccountsSettingsScreen(),
        overrides: settingsOverrides(
          accounts: AsyncValue<List<Account>>.error(
            Exception('accounts table is locked'),
            StackTrace.empty,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ErrorState), findsOneWidget);
      // Never a generic body (Law U9).
      expect(find.textContaining('accounts table is locked'), findsOneWidget);
    });

    testWidgets('empty names the next action', (tester) async {
      await pumpSettings(
        tester,
        const AccountsSettingsScreen(),
        overrides: settingsOverrides(
          accounts: const AsyncValue.data(<Account>[]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('Add an account'), findsWidgets);
    });

    testWidgets('archived accounts are grouped, not hidden', (tester) async {
      await pumpSettings(
        tester,
        const AccountsSettingsScreen(),
        overrides: settingsOverrides(
          accounts: AsyncValue.data([
            account(),
            account(id: 'ac-2', name: 'Old wallet', isArchived: true),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      // This screen is the only way to reach an archived account and restore it, so hiding them here would make
      // one unreachable — and an account nobody can find is one they recreate by hand.
      expect(find.text('Archived'), findsWidgets);
      expect(find.text('Old wallet'), findsOneWidget);
    });

    testWidgets('an excluded account says so on the row', (tester) async {
      await pumpSettings(
        tester,
        const AccountsSettingsScreen(),
        overrides: settingsOverrides(
          accounts: AsyncValue.data([account(includeInNetWorth: false)]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not in net worth'), findsOneWidget);
    });
  });

  group('tags — the scoping matrix', () {
    testWidgets('every row states where the tag is offered', (tester) async {
      await pumpSettings(
        tester,
        const TagsSettingsScreen(),
        overrides: settingsOverrides(
          tags: AsyncValue.data([
            tag(scopes: {TagScope.inventory, TagScope.shopping}),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      // A scope only visible after opening the editor is one nobody notices is wrong.
      expect(find.text('Items'), findsOneWidget);
      expect(find.text('Shopping lists'), findsOneWidget);
      expect(find.text('Money in'), findsNothing);
    });

    testWidgets('a tag scoped nowhere is called out', (tester) async {
      await pumpSettings(
        tester,
        const TagsSettingsScreen(),
        overrides: settingsOverrides(
          tags: AsyncValue.data([tag(scopes: const {})]),
        ),
      );
      await tester.pumpAndSettle();
      // It cannot appear anywhere in the app, which makes it invisible everywhere except this screen — exactly
      // the dead row somebody would hunt for in the pickers first.
      expect(find.textContaining('not offered anywhere'), findsOneWidget);
    });

    testWidgets('a child is grouped under its parent, one level deep', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const TagsSettingsScreen(),
        overrides: settingsOverrides(
          tags: AsyncValue.data([
            tag(),
            tag(id: 'tg-2', name: 'Fridge', parentTagId: 'tg-1'),
            // A grandchild, which must surface under the top-most ancestor rather than vanish.
            tag(id: 'tg-3', name: 'Freezer', parentTagId: 'tg-2'),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Kitchen'), findsOneWidget);
      expect(find.text('Fridge'), findsOneWidget);
      expect(find.text('Freezer'), findsOneWidget);
    });

    testWidgets('a parent cycle does not hang the screen', (tester) async {
      await pumpSettings(
        tester,
        const TagsSettingsScreen(),
        overrides: settingsOverrides(
          tags: AsyncValue.data([
            tag(id: 'a', name: 'A', parentTagId: 'b'),
            tag(id: 'b', name: 'B', parentTagId: 'a'),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      // The root walk is bounded by the tag count. A cycle should be impossible, and a UI that trusts that is a
      // UI that freezes when it turns out not to be.
      expect(tester.takeException(), isNull);
    });
  });

  group('units', () {
    testWidgets('a row states what the unit equals, never its stored factor', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const UnitsSettingsScreen(),
        overrides: settingsOverrides(units: AsyncValue.data([unit()])),
      );
      await tester.pumpAndSettle();
      // 1,000,000 is the stored value and useless to read. `1 kg = 1,000 g` is the figure — and dividing by
      // `milliPerBaseUnit` rather than by 1,000 is the whole of ARCH_4 R18.
      expect(find.textContaining('1,000'), findsOneWidget);
      expect(find.textContaining('1,000,000'), findsNothing);
    });

    testWidgets('the fixed-categories rule is stated before anybody adds one', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const UnitsSettingsScreen(),
        overrides: settingsOverrides(units: AsyncValue.data([unit()])),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('only three kinds'), findsOneWidget);
    });
  });

  group('currencies', () {
    testWidgets('the home currency cannot be switched off', (tester) async {
      await pumpSettings(
        tester,
        const CurrenciesSettingsScreen(),
        overrides: settingsOverrides(
          currencies: AsyncValue.data([
            currency(),
            currency(code: 'JPY', isEnabled: false),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      final tiles = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList();
      // Disabled rather than hidden, so it reads as an explanation and not a rendering fault (ARCH_5 §10).
      expect(tiles.first.onChanged, isNull);
      expect(tiles.last.onChanged, isNotNull);
      expect(find.textContaining('Cannot be turned off'), findsOneWidget);
    });
  });

  group('security', () {
    testWidgets('the honest paragraph is on the screen, above the switches', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const SecuritySettingsScreen(),
        overrides: settingsOverrides(lock: FakeAppLock(enabled: true)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('does not encrypt your data'), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsNothing);
    });

    testWidgets('auto-erase is off by default and names the threshold', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const SecuritySettingsScreen(),
        overrides: settingsOverrides(lock: FakeAppLock(enabled: true)),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      final switches = tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      // An unset key reads as false, which is what "default off" has to mean for a feature that destroys data.
      expect(switches.every((tile) => tile.value == false), isTrue);
      expect(find.textContaining('10 wrong PIN attempts'), findsOneWidget);
    });

    testWidgets('neither PIN branch is guessed while storage answers', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const SecuritySettingsScreen(),
        // **The provider is overridden to a future that never completes.** `FakeAppLock.isEnabled` is an
        // `async` getter, so it resolves within the first frame's microtask drain and the loading branch is
        // never observable — the test would have passed against a screen that had no loading branch at all.
        overrides: [
          ...settingsOverrides(lock: FakeAppLock(enabled: true)),
          lockConfiguredProvider.overrideWith((ref) => pendingFuture<bool>()),
        ],
      );
      expect(find.text('Checking…'), findsOneWidget);
      // A row saying "no PIN set" for one frame to somebody who has one would be alarming for the wrong reason.
      expect(find.text('Set a PIN'), findsNothing);
    });
  });
}
