/// Shared scaffolding for the analytics widget tests.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/features/analytics/providers/drill_down_providers.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';

import 'fake_settings_repository.dart';

/// The narrowest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so every derived date is the same on every machine.
final Clock kAnalyticsClock = FixedClock(DateTime(2026, 8, 10, 9, 30));

/// Today, according to [kAnalyticsClock].
const DateKey kAnalyticsToday = DateKey(20260810);

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// A stream that never emits and never closes, for the loading branch of a `StreamProvider`.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

Money _inr(int minor) => Money(minor, 'INR');

/// A spend breakdown with [count] slices, largest first.
MoneySeries series({int count = 3, int approximate = 0, int unconverted = 0}) =>
    (
      slices: [
        for (var i = 0; i < count; i++)
          (
            label: 'grocery',
            key: i == 0 ? 'grocery' : 'household',
            amount: _inr(100000 - i * 10000),
          ),
      ],
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );

/// Total spend and its top three kinds.
Concentration concentration({int total = 300000, int top = 3}) => (
  top: [
    for (var i = 0; i < top; i++)
      (
        key: 'grocery',
        label: 'grocery',
        amount: _inr(100000),
        share: 1 / (top == 0 ? 1 : top),
      ),
  ],
  topShare: top == 0 ? 0.0 : 0.9,
  total: _inr(total),
  quality: exactConversion,
);

/// A unit-price trend with [points] observations and a [change] across them.
UnitPriceTrend trend({int points = 3, double? change = 0.34}) => (
  itemId: 'it-1',
  itemName: 'Potatoes',
  points: [
    for (var i = 0; i < points; i++)
      (
        on: DateKey(20260801 + i),
        lineAmount: _inr(5000 + i * 500),
        quantity: Qty(1000000, UnitCategory.weight),
        pricePerBaseUnit: 5.0 + i,
      ),
  ],
  percentChange: change,
);

/// One transaction for a drill-down list.
Transaction transaction({String id = 'tx-1', int minor = 45900}) => Transaction(
  id: id,
  kind: TransactionKind.withdrawal,
  subtype: TransactionSubtype.grocery,
  occurredAtUtc: DateTime.utc(2026, 8, 10, 9),
  dateKey: kAnalyticsToday,
  originalAmount: _inr(minor),
  needsReview: false,
  fromAccountId: 'ac-1',
);

/// Overrides every analytics provider to a settled, harmless value.
///
/// **Fixed length, always.** A conditional entry changes the override count between scopes and Riverpod
/// refuses it outright — and two `pumpWidget` calls in one test silently reuse the first scope, so a
/// varying list fails in both directions (ARCH_6 P5).
///
/// Every provider is overridden even where a test does not care, because an un-overridden repository
/// provider reaches a real database, which a widget test has no business opening (P6). The screen's
/// sections are a lazy sliver, so a narrow viewport builds only the first few cards — but an override
/// for a card that never builds costs nothing, and omitting one costs a thrown `databaseProvider`.
///
/// `analyticsRangeProvider` and `analyticsCacheControllerProvider` are `NotifierProvider`s and cannot be
/// overridden as instances (P5), so the repositories beneath them are the seam:
/// `AnalyticsRangeNotifier.build` reads settings on the first frame and would otherwise resolve
/// `databaseProvider`, which throws by design (Law L10).
List<Override> analyticsOverrides({
  AsyncValue<Concentration>? headline,
  AsyncValue<UnitPriceTrend?>? inflation,
  AsyncValue<MoneySeries>? subtypeSpend,
  AsyncValue<List<TagSpendNode>>? tagTree,
  AsyncValue<List<Transaction>>? drillRows,
  int unconverted = 0,
}) => [
  clockProvider.overrideWithValue(kAnalyticsClock),
  settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
  analyticsCurrencyProvider.overrideWith((ref) async => 'INR'),
  analyticsDigitsProvider.overrideWith((ref) async => 2),
  analyticsDigitsForCurrencyProvider.overrideWith(
    (ref, code) async => code == 'JPY' ? 0 : 2,
  ),
  analyticsUnconvertedProvider.overrideWith((ref) => Stream.value(unconverted)),
  analyticsHeadlineProvider.overrideWith(
    (ref) => _future(headline ?? AsyncValue.data(concentration())),
  ),
  analyticsPreviousHeadlineProvider.overrideWith(
    (ref) => _future(AsyncValue.data(concentration(total: 250000))),
  ),
  personalInflationProvider.overrideWith(
    (ref) => _future(inflation ?? AsyncValue<UnitPriceTrend?>.data(trend())),
  ),
  spendBySubtypeProvider.overrideWith(
    (ref) => _future(subtypeSpend ?? AsyncValue.data(series())),
  ),
  spendByTagProvider.overrideWith((ref) => _future(AsyncValue.data(series()))),
  spendByPaymentMethodProvider.overrideWith(
    (ref) => _future(AsyncValue.data(series())),
  ),
  topPayeesProvider.overrideWith((ref) => _future(AsyncValue.data(series()))),
  groceryShareProvider.overrideWith(
    (ref) => _future(
      AsyncValue<ShareOfTotal?>.data(
        (key: 'grocery', label: 'grocery', amount: _inr(100000), share: 0.4),
      ),
    ),
  ),
  analyticsTagsByIdProvider.overrideWith(
    (ref) => Stream.value(<String, Tag>{}),
  ),
  tagSpendTreeProvider.overrideWith(
    (ref) => _future(tagTree ?? const AsyncValue.data(<TagSpendNode>[])),
  ),
  incomeVsExpenseProvider.overrideWith(
    (ref) => _future(
      AsyncValue.data((
        points: [
          (monthKey: 202607, income: _inr(500000), expense: _inr(320000)),
          (monthKey: 202608, income: _inr(500000), expense: _inr(410000)),
        ],
        quality: exactConversion,
      )),
    ),
  ),
  netCashFlowProvider.overrideWith(
    (ref) => _future(
      AsyncValue.data((
        points: [
          (monthKey: 202607, amount: _inr(180000)),
          (monthKey: 202608, amount: _inr(90000)),
        ],
        quality: exactConversion,
      )),
    ),
  ),
  analyticsAccountsProvider.overrideWith((ref) => Stream.value(<Account>[])),
  balanceTrendProvider.overrideWith(
    (ref, id) => _future(
      AsyncValue.data((accountId: id, points: const <BalancePoint>[])),
    ),
  ),
  spendHeatmapProvider.overrideWith(
    (ref, byWeekday) => _future(
      AsyncValue.data((cells: const <HeatmapCell>[], quality: exactConversion)),
    ),
  ),
  topItemsBySpendProvider.overrideWith(
    (ref) => _future(const AsyncValue.data(<ItemSpend>[])),
  ),
  topItemsByQuantityProvider.overrideWith(
    (ref) => _future(const AsyncValue.data(<ItemQuantity>[])),
  ),
  dearestPurchaseProvider.overrideWith(
    (ref, item) => _future(const AsyncValue<DearestPurchase?>.data(null)),
  ),
  unitPriceTrendProvider.overrideWith(
    (ref, item) => _future(AsyncValue.data(trend())),
  ),
  averageBasketProvider.overrideWith(
    (ref) => _future(
      AsyncValue.data((
        averageValue: _inr(140000),
        averageLineCount: 4.3,
        basketCount: 7,
        quality: exactConversion,
      )),
    ),
  ),
  inventoryValueProvider.overrideWith(
    (ref) => _future(
      AsyncValue.data((
        byCurrency: {'INR': _inr(320000)},
        batchesValued: 9,
        batchesNoCost: 2,
      )),
    ),
  ),
  wasteTotalsProvider.overrideWith(
    (ref) => _future(const AsyncValue.data(<ItemWasteTotal>[])),
  ),
  expiringBatchesProvider.overrideWith(
    (ref, days) => _future(const AsyncValue.data(<ExpiringBatch>[])),
  ),
  lowStockTodayProvider.overrideWith(
    (ref) => _future(AsyncValue.data((date: kAnalyticsToday, itemCount: 0))),
  ),
  monthlyCommitmentProvider.overrideWith(
    (ref) => _future(
      AsyncValue.data((
        total: _inr(649000),
        templateCount: 4,
        quality: exactConversion,
      )),
    ),
  ),
  recurringSplitProvider.overrideWith(
    (ref) => _future(
      AsyncValue.data((
        recurring: _inr(649000),
        discretionary: _inr(320000),
        recurringShare: 0.67,
        quality: exactConversion,
      )),
    ),
  ),
  serviceCostByAssetProvider.overrideWith(
    (ref) => _future(const AsyncValue.data(<AssetServiceCost>[])),
  ),
  warrantyCoverageProvider.overrideWith(
    (ref) => _future(const AsyncValue.data(<WarrantyCoverage>[])),
  ),
  // The drill-down's own feed, plus the two maps its rows read from the expense feature.
  drillDownTransactionsProvider.overrideWith(
    (ref, spec) => _stream(drillRows ?? AsyncValue.data([transaction()])),
  ),
  drillDownLabelProvider.overrideWith((ref, spec) async => 'Corner Shop'),
  accountsByIdProvider.overrideWith((ref) => Stream.value(<String, Account>{})),
  payeesByIdProvider.overrideWith((ref) => Stream.value(<String, Payee>{})),
];

/// Turns an [AsyncValue] back into the future a `FutureProvider` override expects.
Future<T> _future<T>(AsyncValue<T> value) => value.when(
  data: Future.value,
  loading: pendingFuture<T>,
  error: (error, stack) => Future<T>.error(error, stack),
);

/// Turns an [AsyncValue] back into the stream a `StreamProvider` override expects.
Stream<T> _stream<T>(AsyncValue<T> value) => value.when(
  data: Stream.value,
  loading: pendingStream<T>,
  error: (error, stack) => Stream<T>.error(error, stack),
);

/// A drill-down spec for the tests to share.
const DrillDownSpec kDrillSpec = DrillDownSpec(
  kind: DrillDownKind.payee,
  value: 'pay-1',
);

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
///
/// Wrapped in a `Scaffold` by default, standing in for the drawer shell. A shell destination declares
/// no `Scaffold` of its own, and Material widgets — `ChoiceChip`, `InkWell`, `SegmentedButton` — assert
/// without a `Material` ancestor.
///
/// The text scaler goes through `MaterialApp.builder`, not a `MediaQuery` above the app:
/// `WidgetsApp` re-establishes `MediaQuery` from the view, so an override placed above it never
/// arrives (ARCH_5 §10).
Future<void> pumpAnalytics(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
  bool dark = false,
  bool wrapInShell = true,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark
            ? AlayaTheme.dark(AlayaPresets.activePreset)
            : AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        // **`MaterialApp` inserts no `Material` and no `Scaffold`.** In the app the drawer shell
        // supplies both, and `AnalyticsHomeScreen` deliberately declares neither — so a shell
        // destination pumped bare has no `Material` ancestor and every `ChoiceChip` in the range row
        // asserts. This `Scaffold` stands in for `_ShellScaffold`.
        //
        // `wrapInShell: false` for a screen that owns its own `Scaffold`, so `DrillDownScreen` is not
        // nested inside a second one.
        home: wrapInShell ? Scaffold(body: child) : child,
      ),
    ),
  );
  await tester.pump();
}
