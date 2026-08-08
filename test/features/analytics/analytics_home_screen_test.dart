import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/presentation/screens/analytics_home_screen.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_header.dart';
import 'package:alaya/features/analytics/presentation/widgets/inflation_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';

import '../../support/analytics_harness.dart';

/// `AnalyticsHomeScreen` — archetype F, all four states (Law U4, ARCH_5 §9.1).
void main() {
  group('the four states', () {
    testWidgets('loading shows no figure and no error', (tester) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(
          headline: const AsyncValue<Concentration>.loading(),
          inflation: const AsyncValue<UnitPriceTrend?>.loading(),
        ),
      );

      // No `AmountText` at all: a pending read must not resolve to a zero, which would read as a real
      // figure of nothing spent.
      expect(find.byType(AmountText), findsNothing);
      expect(find.byType(EmptyState), findsNothing);
    });

    testWidgets('populated shows exactly one displayAmount', (tester) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(),
      );
      await tester.pumpAndSettle();

      // **One headline, and the test asserts the count rather than its presence.** Two `display`
      // amounts is no headline at all (ARCH_5 §3 archetype F), and it is the kind of regression a
      // "finds one widget" assertion would let through.
      final display = tester
          .widgetList<AmountText>(find.byType(AmountText))
          .where((widget) => widget.size == AmountSize.display);
      expect(display, hasLength(1));
    });

    testWidgets('empty replaces the spend sections and keeps the house', (
      tester,
    ) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(
          headline: AsyncValue.data(concentration(total: 0, top: 0)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsOneWidget);
      // The signature card is a spend surface and goes; the house section is a "right now" figure and
      // stays, which is the whole point of splitting them.
      expect(find.byType(InflationCard), findsNothing);
    });

    testWidgets('a failed headline costs the header and nothing else', (
      tester,
    ) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(
          headline: AsyncValue<Concentration>.error(
            Exception('rate table unreachable'),
            StackTrace.empty,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // **The repository's own message, not a generic body** (Law U9), and the screen survives: the
      // range row and the header are both still mounted. One failing card never blanks an overview.
      expect(find.textContaining('rate table unreachable'), findsOneWidget);
      expect(find.byType(AnalyticsHeader), findsOneWidget);
    });
  });

  group('the gate', () {
    testWidgets('renders at 320x640 with a doubled text scale', (tester) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(),
        textScale: 2,
      );
      await tester.pumpAndSettle();
      // No exception is the assertion (Law U15). An overflow throws in a test binding, so reaching
      // here at all is the pass.
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders at a tripled scale, past what U15 asks for', (
      tester,
    ) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(),
        textScale: 3,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('every target is large enough and named', (tester) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(),
      );
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    testWidgets('adds no chrome of its own; the shell owns it', (tester) async {
      await pumpAnalytics(
        tester,
        const AnalyticsHomeScreen(),
        overrides: analyticsOverrides(),
      );
      await tester.pumpAndSettle();

      // Exactly one `Scaffold` — the harness's stand-in for `_ShellScaffold` — so the screen added
      // none, and **no `AppBar`**, because `Routes.insights` is a shell destination and a bar declared
      // here would be a second one inside the shell (Law U18).
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });
}
