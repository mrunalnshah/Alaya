import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/analytics/presentation/widgets/analytics_line_chart.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';

import '../../support/analytics_harness.dart';

/// Goldens for `ChartCard`, light and dark (ARCH_5 §9.2).
///
/// **Dark is the half that matters here.** Depth in this app is a palette step rather than a shadow
/// (ARCH_3 §8, ARCH_5 §2.5), so a surface-tier mistake is invisible in light mode and obvious in dark —
/// which is exactly why §9.2 asks for both and for one pass on a real device in dark.
///
/// Four states, not one: a golden of the populated card alone would let the loading, empty and error
/// branches drift, and those are three quarters of what this widget is for.
void main() {
  Widget card(AsyncValue<int> value, {Widget? trailing}) => Center(
    child: SizedBox(
      width: 320,
      child: ChartCard<int>(
        title: 'Where it went',
        subtitle: 'Last 30 days',
        value: value,
        isEmpty: (data) => data == 0,
        emptyMessage: 'Nothing spent in this window',
        onRetry: () {},
        approximateCount: 2,
        unconvertedCount: 1,
        trailing: trailing,
        builder: (context, data) => const AnalyticsPlotBox(
          child: ColoredBox(color: Color(0x11000000)),
        ),
      ),
    ),
  );

  final states = <String, AsyncValue<int>>{
    'populated': const AsyncValue.data(1),
    'loading': const AsyncValue.loading(),
    'empty': const AsyncValue.data(0),
    'error': AsyncValue.error(
      Exception('No rate for JPY on 2026-08-10, and none earlier'),
      StackTrace.empty,
    ),
  };

  for (final entry in states.entries) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('ChartCard ${entry.key} in $mode', (tester) async {
        await pumpAnalytics(
          tester,
          card(
            entry.value,
            trailing: entry.key == 'populated'
                ? const AmountText(
                    Money(432100, 'INR'),
                    size: AmountSize.small,
                    showSign: false,
                  )
                : null,
          ),
          overrides: analyticsOverrides(),
          dark: dark,
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(ChartCard<int>),
          matchesGoldenFile('goldens/chart_card_${entry.key}_$mode.png'),
        );
      });
    }
  }
}
