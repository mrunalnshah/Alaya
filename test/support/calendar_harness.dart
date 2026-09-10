/// Shared scaffolding for the Calendar's widget tests.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/repositories/calendar_repository.dart';
import 'package:alaya/features/calendar/providers/calendar_providers.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so every derived date is the same on every machine.
final Clock kCalendarClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kCalendarClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// Builds one event, defaulting to a transaction on today.
CalendarEvent event({
  DateKey date = kToday,
  CalendarEventType type = CalendarEventType.transaction,
  String refType = 'transaction',
  String refId = 'tx-1',
  String title = 'Groceries',
  CalendarSeverity baseSeverity = CalendarSeverity.info,
  int? amountMinor,
}) => CalendarEvent(
  dateKey: date,
  type: type,
  refType: refType,
  refId: refId,
  title: title,
  baseSeverity: baseSeverity,
  amount: amountMinor == null ? null : Money(amountMinor, 'INR'),
);

/// A [CalendarRepository] that answers from a list, or stalls, or fails.
///
/// The **repository** is the seam rather than the aggregator, deliberately: overriding
/// `calendarAggregatorProvider` would stub out ARCH_3 §6's per-type severity table, which is the one
/// piece of calendar logic worth testing through rather than around.
class FakeCalendarRepository implements CalendarRepository {
  /// Creates a repository over [events].
  FakeCalendarRepository({
    this.events = const <CalendarEvent>[],
    this.pending = false,
    this.error,
  });

  /// What every read returns.
  final List<CalendarEvent> events;

  /// When true, reads never complete — the loading branch.
  final bool pending;

  /// When set, reads fail with it — the error branch.
  final Object? error;

  /// Every range this repository was asked for, so a test can assert the query stayed bounded.
  final List<({DateKey from, DateKey to})> rangesRequested = [];

  @override
  Stream<List<CalendarEvent>> watchRange({
    required DateKey from,
    required DateKey to,
  }) {
    rangesRequested.add((from: from, to: to));
    if (pending) return pendingStream<List<CalendarEvent>>();
    if (error != null) return Stream<List<CalendarEvent>>.error(error!);
    return Stream.value(
      events.where((e) => e.dateKey.isWithin(from, to)).toList(),
    );
  }

  @override
  Future<List<CalendarEvent>> forDay(DateKey dateKey) {
    if (pending) return pendingFuture<List<CalendarEvent>>();
    if (error != null) return Future<List<CalendarEvent>>.error(error!);
    return Future.value(events.where((e) => e.dateKey == dateKey).toList());
  }

  @override
  Future<Map<DateKey, int>> countsByDate({
    required DateKey from,
    required DateKey to,
  }) {
    if (pending) return pendingFuture<Map<DateKey, int>>();
    if (error != null) return Future<Map<DateKey, int>>.error(error!);
    final counts = <DateKey, int>{};
    for (final e in events.where((e) => e.dateKey.isWithin(from, to))) {
      counts[e.dateKey] = (counts[e.dateKey] ?? 0) + 1;
    }
    return Future.value(counts);
  }
}

/// Overrides every provider the calendar reads, including the ones read during `build`.
///
/// `calendarTodayProvider` reads the clock and `focusedMonthProvider` reads that, so the clock alone
/// fixes which month opens. Without the repository override, `calendarAggregatorProvider` resolves
/// `calendarDaoProvider` and then `databaseProvider`, which throws by design (ARCH_6 P17).
List<Override> calendarOverrides(FakeCalendarRepository repository) => [
  clockProvider.overrideWithValue(kCalendarClock),
  calendarRepositoryProvider.overrideWithValue(repository),
  // The month feed awaits this before it subscribes, and unstubbed it resolves
  // `recurringRepositoryProvider` and then `databaseProvider`, which throws by design (L10). The
  // symptom is a screen that renders *nothing* — every finder misses and `rangesRequested` stays
  // empty, because the stream provider never reached its second line.
  //
  // The horizon provider is the seam rather than the repository beneath it: a test does not care how
  // occurrence rows come to exist, only that they do, and faking a whole `RecurringRepository` to say
  // "already done" would be a lot of surface for one integer. The dashboard harness overrides
  // `upcomingProvider` for the same reason rather than the four repositories under it.
  recurringHorizonProvider.overrideWith((ref) async => 0),
];

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
Future<void> pumpCalendar(
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
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}
