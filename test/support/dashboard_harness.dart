import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/dashboard/providers/module_providers.dart';
import 'package:alaya/features/dashboard/providers/range_providers.dart';

import 'dart:async';
import 'fake_settings_repository.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so every derived date is the same on every machine.
final Clock kDashClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kDashClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// A headline total, with however many balances it could not convert.
NetWorth netWorth({
  int minor = 12345678,
  int unconverted = 0,
  bool approximate = false,
}) => NetWorth(
  total: Money(minor, 'INR'),
  unconvertedCount: unconverted,
  isApproximate: approximate,
);

/// Totals over one window.
RangeTotals totals({
  int inMinor = 500000,
  int outMinor = 320000,
  int excluded = 0,
}) => RangeTotals(
  moneyIn: Money(inMinor, 'INR'),
  moneyOut: Money(outMinor, 'INR'),
  excludedCount: excluded,
);

/// One thing needing attention.
UpcomingEntry upcoming({
  UpcomingKind kind = UpcomingKind.bill,
  String title = 'Rent',
  DateKey on = const DateKey(20260805),
}) => UpcomingEntry(kind: kind, title: title, dueDateKey: on);

/// Spend by kind over the dashboard's thirty-day window.
Concentration spendByKind({int total = 320000, int kinds = 3}) => (
  top: [
    for (var i = 0; i < kinds; i++)
      (
        key: 'grocery',
        label: 'grocery',
        amount: Money(100000 - i * 10000, 'INR'),
        share: 0.3 - i * 0.05,
      ),
  ],
  topShare: kinds == 0 ? 0.0 : 0.85,
  total: Money(total, 'INR'),
  quality: exactConversion,
);

/// Overrides every dashboard provider to a settled, harmless value.
///
/// **Fixed length, always.** A conditional entry changes the override count between scopes and Riverpod
/// refuses it outright — and two `pumpWidget` calls in one test silently reuse the first scope, so a
/// varying list fails in both directions (ARCH_4 P5).
///
/// Every provider is overridden even where a test does not care, because an un-overridden repository
/// provider reaches a real database, which a widget test has no business opening (P6).
List<Override> dashboardOverrides({
  AsyncValue<NetWorth>? funds,
  AsyncValue<RangeTotals>? last30,
  AsyncValue<RangeTotals>? allTime,
  AsyncValue<List<UpcomingEntry>>? upcomingEntries,
  int inventory = 0,
  int services = 0,
  AsyncValue<int>? expenses,
  AsyncValue<int>? shopping,
  AsyncValue<int>? recurring,
  AsyncValue<Concentration>? spending,
}) => [
  clockProvider.overrideWithValue(kDashClock),
  // `InsightSideNotifier.build` reads settings during the first frame, so this is not optional
  // even for a test that never touches the insight card: without it the notifier resolves
  // `databaseProvider`, which throws by design (Law L10). A `NotifierProvider` instance cannot be
  // overridden (ARCH_6 P5), so the repository beneath it is the only seam.
  settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
  dashboardCurrencyProvider.overrideWith((ref) async => 'INR'),
  dashboardDigitsProvider.overrideWith((ref) async => 2),
  totalFundsProvider.overrideWith(
    (ref) => _resolve(funds ?? AsyncValue.data(netWorth())),
  ),
  rangeTotalsProvider.overrideWith(
    (ref, range) => _resolve(
      (range == (from: DateKey(20260703), to: kToday) ? last30 : allTime) ??
          AsyncValue.data(totals()),
    ),
  ),
  upcomingProvider.overrideWith(
    (ref) =>
        _resolve(upcomingEntries ?? const AsyncValue.data(<UpcomingEntry>[])),
  ),
  inventoryCountProvider.overrideWith((ref) => inventory),
  serviceCountProvider.overrideWith((ref) => services),
  expenseCountProvider.overrideWith(
    (ref) => _resolve(expenses ?? const AsyncValue.data(0)),
  ),
  shoppingCountProvider.overrideWith(
    (ref) => _resolve(shopping ?? const AsyncValue.data(0)),
  ),
  recurringCountProvider.overrideWith(
    (ref) => _resolve(recurring ?? const AsyncValue.data(0)),
  ),
  // Phase 7B. Unconditional like every other entry: a conditional override changes the list's
  // length between scopes and Riverpod refuses it outright (ARCH_6 P5). Without it the spending
  // side resolves `analyticsServiceProvider`, which reaches `databaseProvider` and throws by
  // design (Law L10).
  spendingInsightProvider.overrideWith(
    (ref) => _resolve(spending ?? AsyncValue.data(spendByKind())),
  ),
];

/// Turns an [AsyncValue] back into the future a `FutureProvider` override expects.
Future<T> _resolve<T>(AsyncValue<T> value) => value.when(
  data: Future.value,
  loading: pendingFuture<T>,
  error: (error, stack) => Future<T>.error(error, stack),
);

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
Future<void> pumpDashboard(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AlayaTheme.light(AlayaPresets.activePreset),
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
        home: child,
      ),
    ),
  );
  await tester.pump();
}
