import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_bar_chart.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_line_chart.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';

/// A `yyyymm` month key as a short localised month name.
///
/// `DateKey.fromYmd(y, m, 1)` rather than arithmetic on the key: `fromYmd` **validates**, so a
/// malformed month key throws here rather than rendering a nonsense label (ARCH_2's 7A amendment).
String _monthLabel(BuildContext context, int monthKey) {
  final date = DateKey.fromYmd(monthKey ~/ 100, monthKey % 100, 1);
  return DateFormat.MMM(
    Localizations.localeOf(context).toLanguageTag(),
  ).format(date.toUtcMidnight());
}

/// Only the first and last tick are labelled, and every tick when there are few enough.
///
/// Twelve month labels do not fit across a phone; two do, and the shape between them is what the card
/// is for.
bool _labelTick(int index, int last) =>
    index == 0 || index == last || last <= _denseTickLimit;

const int _denseTickLimit = 4;

/// Query 5 — income against expense, month by month.
class IncomeVsExpenseCard extends ConsumerWidget {
  /// Creates the card.
  const IncomeVsExpenseCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(incomeVsExpenseProvider);

    return ChartCard<IncomeVsExpense>(
      title: strings.analyticsIncomeVsExpense,
      value: async,
      isEmpty: (data) => data.points.length < 2,
      // Fewer than two months is not a trend, and a single pair of dots presented as one would invite
      // a comparison the data cannot support.
      emptyMessage: strings.analyticsNeedTwoMonths,
      onRetry: () => ref.invalidate(incomeVsExpenseProvider),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, data) {
        final last = data.points.length - 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Legend(
              entries: [
                (label: strings.rangeMoneyIn, tone: AnalyticsSeriesTone.income),
                (
                  label: strings.rangeMoneyOut,
                  tone: AnalyticsSeriesTone.expense,
                ),
              ],
            ),
            const SizedBox(height: AlayaSpacing.xs),
            AnalyticsPlotBox(
              child: AnalyticsLineChart(
                series: [
                  AnalyticsSeries(
                    tone: AnalyticsSeriesTone.income,
                    points: [
                      for (var i = 0; i <= last; i++)
                        AnalyticsPoint(
                          x: i.toDouble(),
                          value: data.points[i].income.minor,
                          axisLabel: _labelTick(i, last)
                              ? _monthLabel(context, data.points[i].monthKey)
                              : null,
                        ),
                    ],
                  ),
                  AnalyticsSeries(
                    tone: AnalyticsSeriesTone.expense,
                    points: [
                      for (var i = 0; i <= last; i++)
                        AnalyticsPoint(
                          x: i.toDouble(),
                          value: data.points[i].expense.minor,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Query 6 — net cash flow per month, from the signed ledger.
class NetCashFlowCard extends ConsumerWidget {
  /// Creates the card.
  const NetCashFlowCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(netCashFlowProvider);

    return ChartCard<NetCashFlow>(
      title: strings.analyticsNetFlow,
      // Worth stating: a reader who moves money between their own accounts every month would
      // otherwise wonder why it is absent. `v_account_ledger` nets a transfer to zero across its two
      // legs, so it never reaches this line.
      subtitle: strings.analyticsNetFlowNote,
      value: async,
      isEmpty: (data) => data.points.isEmpty,
      emptyMessage: strings.analyticsNoFlow,
      onRetry: () => ref.invalidate(netCashFlowProvider),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, data) {
        final last = data.points.length - 1;
        return AnalyticsPlotBox(
          child: AnalyticsLineChart(
            series: [
              AnalyticsSeries(
                // Neutral, not income or expense: a net figure crosses zero, and colouring the whole
                // line by one direction would assert something half of it contradicts. The chart
                // includes zero in its band so the crossing is visible.
                tone: AnalyticsSeriesTone.neutral,
                filled: true,
                points: [
                  for (var i = 0; i <= last; i++)
                    AnalyticsPoint(
                      x: i.toDouble(),
                      value: data.points[i].amount.minor,
                      axisLabel: _labelTick(i, last)
                          ? _monthLabel(context, data.points[i].monthKey)
                          : null,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Query 7 — one account's running balance, in that account's own currency.
class BalanceTrendCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const BalanceTrendCard({super.key});

  @override
  ConsumerState<BalanceTrendCard> createState() => _BalanceTrendCardState();
}

class _BalanceTrendCardState extends ConsumerState<BalanceTrendCard> {
  String? _accountId;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final accounts =
        ref.watch(analyticsAccountsProvider).valueOrNull ?? const <Account>[];
    if (accounts.isEmpty) return const SizedBox.shrink();

    // **The account is resolved, not asked for** (Law U23). A household with one account is never
    // shown a picker; the first selectable account is the answer, and the picker appears only when
    // there is a genuine choice.
    final selected = _resolve(accounts);
    final async = ref.watch(balanceTrendProvider(selected.id));
    final digits =
        ref
            .watch(analyticsDigitsForCurrencyProvider(selected.currencyCode))
            .valueOrNull ??
        2;

    return ChartCard<BalanceTrend>(
      title: strings.analyticsBalanceTrend,
      // The currency is named because this is the one card not in the home currency, and an
      // unlabelled figure in a second currency is a wrong figure.
      subtitle: strings.analyticsBalanceIn(
        selected.name,
        selected.currencyCode,
      ),
      value: async,
      isEmpty: (trend) => trend.points.length < 2,
      emptyMessage: strings.analyticsNoBalanceMovement,
      onRetry: () => ref.invalidate(balanceTrendProvider(selected.id)),
      trailing:
          async.valueOrNull != null && async.valueOrNull!.points.isNotEmpty
          ? AmountText(
              async.valueOrNull!.points.last.balance,
              size: AmountSize.small,
              showSign: false,
              decimalDigits: digits,
            )
          : null,
      builder: (context, trend) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (accounts.length > 1)
            _AccountPicker(
              accounts: accounts,
              selectedId: selected.id,
              onChanged: (id) => setState(() => _accountId = id),
            ),
          AnalyticsPlotBox(
            child: AnalyticsLineChart(
              series: [
                AnalyticsSeries(
                  tone: AnalyticsSeriesTone.neutral,
                  points: [
                    for (var i = 0; i < trend.points.length; i++)
                      AnalyticsPoint(
                        x: i.toDouble(),
                        value: trend.points[i].balance.minor,
                        axisLabel: _labelTick(i, trend.points.length - 1)
                            ? DateFormat.MMMd(
                                Localizations.localeOf(context).toLanguageTag(),
                              ).format(trend.points[i].date.toUtcMidnight())
                            : null,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Account _resolve(List<Account> accounts) {
    final id = _accountId;
    if (id != null) {
      for (final account in accounts) {
        if (account.id == id) return account;
      }
    }
    return accounts.first;
  }
}

/// Which account the balance trend is showing.
class _AccountPicker extends StatelessWidget {
  const _AccountPicker({
    required this.accounts,
    required this.selectedId,
    required this.onChanged,
  });

  final List<Account> accounts;
  final String selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
      child: DropdownButtonFormField<String>(
        // **`isExpanded` is not optional** (ARCH_5 §10): without it the field lays out at the widest
        // item's natural width and overflows a narrow card.
        isExpanded: true,
        initialValue: selectedId,
        decoration: InputDecoration(labelText: strings.analyticsAccount),
        items: [
          for (final account in accounts)
            DropdownMenuItem(value: account.id, child: Text(account.name)),
        ],
        onChanged: (id) {
          if (id != null) onChanged(id);
        },
      ),
    );
  }
}

/// Query 21 — the spend heatmap, by weekday or by day of month.
class SpendHeatmapCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const SpendHeatmapCard({super.key});

  @override
  ConsumerState<SpendHeatmapCard> createState() => _SpendHeatmapCardState();
}

class _SpendHeatmapCardState extends ConsumerState<SpendHeatmapCard> {
  bool _byWeekday = true;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(spendHeatmapProvider(_byWeekday));

    return ChartCard<SpendHeatmap>(
      title: strings.analyticsHeatmap,
      value: async,
      isEmpty: (data) => data.cells.isEmpty,
      emptyMessage: strings.analyticsNothingSpent,
      onRetry: () => ref.invalidate(spendHeatmapProvider(_byWeekday)),
      approximateCount: async.valueOrNull?.quality.approximateCount ?? 0,
      unconvertedCount: async.valueOrNull?.quality.unconvertedCount ?? 0,
      builder: (context, data) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: true,
                label: Text(strings.analyticsByWeekday),
              ),
              ButtonSegment(
                value: false,
                label: Text(strings.analyticsByDayOfMonth),
              ),
            ],
            selected: {_byWeekday},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => _byWeekday = selection.first),
          ),
          const SizedBox(height: AlayaSpacing.sm),
          AnalyticsPlotBox(
            child: AnalyticsBarChart(
              // Thirty-one labels do not fit across a phone; seven do. Every fifth day is enough to
              // orient the reader without the axis becoming a smear.
              labelEvery: _byWeekday ? 1 : _dayOfMonthLabelEvery,
              buckets: [
                for (final cell in data.cells)
                  AnalyticsBucket(
                    bucket: cell.bucket,
                    value: cell.amount.minor,
                    label: AnalyticsLabels.bucket(
                      context,
                      cell.bucket,
                      byWeekday: _byWeekday,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const int _dayOfMonthLabelEvery = 5;
}

/// A key for a multi-series chart, since colour alone cannot say which line is which (Law U17).
class _Legend extends StatelessWidget {
  const _Legend({required this.entries});

  final List<({String label, AnalyticsSeriesTone tone})> entries;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Wrap(
      spacing: AlayaSpacing.sm,
      runSpacing: AlayaSpacing.xxs,
      children: [
        for (final entry in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Swatch(tone: entry.tone),
              const SizedBox(width: AlayaSpacing.xxs),
              Text(
                entry.label,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
            ],
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.tone});

  final AnalyticsSeriesTone tone;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final color = switch (tone) {
      AnalyticsSeriesTone.income => semantic.income,
      AnalyticsSeriesTone.expense => semantic.expense,
      AnalyticsSeriesTone.neutral => semantic.transfer,
    };
    return SizedBox(
      width: AlayaSpacing.sm,
      height: AlayaSpacing.xxs,
      child: ColoredBox(color: color),
    );
  }
}
