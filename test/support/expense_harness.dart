/// Shared scaffolding for the Expense module's widget tests.
///
/// **Overrides the feature's own view-model providers rather than faking twenty repositories.** A
/// widget test's job is the widget: whether it renders four states correctly, survives a doubled
/// text scale and meets the tap-target floor. Reaching through the whole provider graph to arrange
/// a loading state would test Riverpod, and would make each of these files four times longer for no
/// extra coverage.
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
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/transaction.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so "Today" and "Yesterday" are the same two days on every machine.
final Clock kTestClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kTestClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays in its loading state.
///
/// `Stream.empty()` will not do: it closes immediately, which resolves the provider rather than
/// leaving it pending.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// A sample account.
const Account kAccount = Account(
  id: 'acc-1',
  name: 'HDFC Savings',
  normalizedName: 'hdfc savings',
  kind: AccountKind.bank,
  currencyCode: 'INR',
  openingBalance: Money(0, 'INR'),
  openingBalanceDateKey: DateKey(20260101),
  isArchived: false,
  includeInNetWorth: true,
  sortOrder: 0,
);

/// A sample payee.
const Payee kPayee = Payee(
  id: 'pay-1',
  name: 'Reliance Fresh',
  normalizedName: 'reliance fresh',
  kind: PayeeKind.merchant,
);

/// A sample transaction, flagged for review so the nudge has something to count.
Transaction sampleTransaction({
  String id = 'tx-1',
  bool needsReview = false,
  TransactionKind kind = TransactionKind.withdrawal,
  int minor = 125050,
}) => Transaction(
  id: id,
  kind: kind,
  subtype: TransactionSubtype.grocery,
  occurredAtUtc: DateTime.utc(2026, 8, 1, 4),
  dateKey: kToday,
  originalAmount: Money(minor, 'INR'),
  needsReview: needsReview,
  fromAccountId: kAccount.id,
  payeeId: kPayee.id,
);

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
///
/// The `MediaQuery` sits inside `MaterialApp.builder` rather than above it: `WidgetsApp`
/// re-establishes it from the view, so an outer override never reaches the widget under test.
Future<void> pumpExpense(
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
