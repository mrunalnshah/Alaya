/// Shared scaffolding for the Recurring module's widget tests.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so overdue derivation is the same on every machine.
final Clock kRecurringClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kRecurringClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// An account the pay sheet can draw from.
const Account kAccount = Account(
  id: 'acc-1',
  name: 'Everyday',
  normalizedName: 'everyday',
  kind: AccountKind.bank,
  currencyCode: 'INR',
  openingBalance: Money(0, 'INR'),
  openingBalanceDateKey: kToday,
  isArchived: false,
  includeInNetWorth: true,
  sortOrder: 0,
);

/// A monthly bill anchored on the 31st — the clamp case anomaly A13 is about.
RecurringTemplate billTemplate({
  String id = 'tpl-1',
  String name = 'Rent',
  int amountMinor = 120000,
  RecurringDirection direction = RecurringDirection.outflow,
  RecurringKind kind = RecurringKind.rent,
  RecurringIntervalUnit unit = RecurringIntervalUnit.month,
  int intervalCount = 1,
  int? anchorDayOfMonth = 31,
  bool isPaused = false,
  DateKey nextDue = const DateKey(20260831),
  DateKey? endDateKey,
}) => RecurringTemplate(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  kind: kind,
  direction: direction,
  defaultAmount: Money(amountMinor, 'INR'),
  intervalUnit: unit,
  intervalCount: intervalCount,
  startDateKey: const DateKey(20260131),
  nextDueDateKey: nextDue,
  isPaused: isPaused,
  autoRemind: true,
  remindDaysBefore: 3,
  defaultAccountId: kAccount.id,
  anchorDayOfMonth: anchorDayOfMonth,
  endDateKey: endDateKey,
);

/// A salary, so an inflow can be asserted to read as income.
RecurringTemplate salaryTemplate({String id = 'tpl-2'}) => billTemplate(
  id: id,
  name: 'Salary',
  amountMinor: 8500000,
  direction: RecurringDirection.inflow,
  kind: RecurringKind.salary,
  anchorDayOfMonth: 1,
  nextDue: const DateKey(20260901),
);

/// An occurrence in any state.
RecurringOccurrence occurrence({
  String id = 'occ-1',
  String templateId = 'tpl-1',
  DateKey dueDateKey = const DateKey(20260831),
  RecurringOccurrenceStatus status = RecurringOccurrenceStatus.due,
  int? paidMinor,
  String? paidTransactionId,
}) => RecurringOccurrence(
  id: id,
  templateId: templateId,
  dueDateKey: dueDateKey,
  status: status,
  paidAmount: paidMinor == null ? null : Money(paidMinor, 'INR'),
  paidTransactionId: paidTransactionId,
  paidDateKey: paidMinor == null ? null : dueDateKey,
);

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
Future<void> pumpRecurring(
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
