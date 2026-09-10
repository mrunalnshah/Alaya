import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/features/analytics/presentation/screens/drill_down_screen.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';

import '../../support/analytics_harness.dart';

/// `DrillDownScreen` — archetype C, all four states (Law U4, ARCH_5 §9.1).
void main() {
  group('the four states', () {
    testWidgets('loading is a skeleton, not a spinner', (tester) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(
          drillRows: const AsyncValue<List<Transaction>>.loading(),
        ),
        wrapInShell: false,
      );

      // The shape of what is arriving, in a space that is about to be a list (ARCH_5 §5.2).
      expect(find.byType(AlayaListSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('populated groups rows under a sticky day header', (
      tester,
    ) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(),
        wrapInShell: false,
      );
      await tester.pumpAndSettle();

      expect(find.byType(TransactionRow), findsOneWidget);
      expect(find.byType(SliverPersistentHeader), findsOneWidget);
    });

    testWidgets('empty names the window rather than the filter', (
      tester,
    ) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(
          drillRows: const AsyncValue.data(<Transaction>[]),
        ),
        wrapInShell: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('error carries the repository message', (tester) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(
          drillRows: AsyncValue<List<Transaction>>.error(
            Exception('payee lookup failed'),
            StackTrace.empty,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      // **Not `errorBodyGeneric`** (Law U9): a list that fails identically for every cause is a
      // failure nobody can diagnose.
      expect(find.textContaining('payee lookup failed'), findsOneWidget);
    });
  });

  group('archetype C obligations', () {
    testWidgets('the active filter is visible and removable', (tester) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(),
        wrapInShell: false,
      );
      await tester.pumpAndSettle();

      // A filter the reader cannot see is a bug report waiting to happen (ARCH_5 §3 archetype C).
      expect(find.byType(FilterChipBar), findsOneWidget);
    });

    testWidgets('it owns its Scaffold and app bar, outside the shell', (
      tester,
    ) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(),
        wrapInShell: false,
      );
      await tester.pumpAndSettle();

      // The opposite assertion to the home screen's, and why every pump here passes
      // `wrapInShell: false`: this screen brings its own `Scaffold`. `AppBar` resolves `hasDrawer`
      // before `canPop`, so a drill-down inside the shell would show a hamburger where back belongs
      // (Law U18).
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(Drawer), findsNothing);
    });

    testWidgets('an unparseable route explains itself instead of throwing', (
      tester,
    ) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: null),
        overrides: analyticsOverrides(),
        wrapInShell: false,
      );
      await tester.pumpAndSettle();

      // This route is deep-linkable, so a malformed one is reachable from outside the app.
      expect(find.byType(EmptyState), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the gate', () {
    testWidgets('renders at 320x640 with a doubled text scale', (tester) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(),
        wrapInShell: false,
        textScale: 2,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('every target is large enough and named', (tester) async {
      await pumpAnalytics(
        tester,
        const DrillDownScreen(spec: kDrillSpec),
        overrides: analyticsOverrides(),
        wrapInShell: false,
      );
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });
}
