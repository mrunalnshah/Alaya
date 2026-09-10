import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';

/// The largest amount in a breakdown, which every bar's length is measured against.
///
/// Share of the *largest* rather than of the total, because a breakdown whose bars are shares of a
/// total is nearly all whitespace the moment there are eight slices — and the figures beside them
/// already say what the totals are.
int analyticsPeak(Iterable<Money> amounts) {
  var peak = 0;
  for (final amount in amounts) {
    if (amount.minor > peak) peak = amount.minor;
  }
  return peak;
}

/// [amount] as a fraction of [peak], for a bar's length.
double analyticsShare(Money amount, int peak) =>
    peak == 0 ? 0 : amount.minor / peak;

/// A breakdown row's figure, rendered once for every card that has one.
///
/// `AmountSize.small` because this screen has exactly one headline (ARCH_5 §3 archetype F), and
/// `showSign: false` because a column that is already a breakdown of spending does not need a minus in
/// front of every row.
Widget analyticsAmount(Money amount, int decimalDigits) => AmountText(
  amount,
  size: AmountSize.small,
  showSign: false,
  decimalDigits: decimalDigits,
);

/// An amount that resolves its **own** currency's precision.
///
/// **For the figures on this screen that are not in the home currency**: an inventory valuation, a
/// waste cost and a service history are all per-currency, because a batch's cost currency is per row
/// and summing them would add rupees to yen (anomaly A34). Passing the home currency's precision to a
/// yen figure prints `¥1,200.00` for `¥1,200`.
///
/// A widget rather than a lookup at the call site, because the precision arrives asynchronously and a
/// card rendering four currencies would otherwise need four watches interleaved with its layout.
class AnalyticsCurrencyAmount extends ConsumerWidget {
  /// Renders [amount] with its own currency's precision.
  const AnalyticsCurrencyAmount(
    this.amount, {
    this.size = AmountSize.small,
    super.key,
  });

  /// The amount, in whatever currency it was recorded in.
  final Money amount;

  /// How large to render it.
  final AmountSize size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Two while the precision loads is the right guess for four of the app's five seeded currencies,
    // and it is corrected on the next frame rather than showing a placeholder where a figure goes.
    final digits =
        ref
            .watch(analyticsDigitsForCurrencyProvider(amount.currencyCode))
            .valueOrNull ??
        2;
    return AmountText(
      amount,
      size: size,
      showSign: false,
      decimalDigits: digits,
    );
  }
}
