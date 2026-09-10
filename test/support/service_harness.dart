/// Shared scaffolding for the Service Manager module's widget tests.
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
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/entities/service_record.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so every warranty and service derivation is the same on every machine.
final Clock kServiceClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kServiceClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// An account a service expense can be drawn from.
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

/// A television — the ordinary case: a thing, with a price and a warranty.
Asset television({
  String id = 'asset-1',
  String name = 'Living room TV',
  AssetStatus status = AssetStatus.active,
  int? priceMinor = 4500000,
  DateKey? warrantyEnd = const DateKey(20270131),
  DateKey? nextService,
  int? serviceIntervalDays,
  String? contactPhone,
  String? linkedRecurringTemplateId,
  DateKey? disposedAt,
  AssetDisposalReason? disposalReason,
  int? disposalMinor,
}) => Asset(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  type: AssetType.electronics,
  status: status,
  brand: 'LG',
  modelNo: 'OLED55C3',
  purchaseDateKey: const DateKey(20260131),
  purchasePrice: priceMinor == null ? null : Money(priceMinor, 'INR'),
  warrantyStartDateKey: const DateKey(20260131),
  warrantyEndDateKey: warrantyEnd,
  warrantyProvider: 'LG India',
  serviceIntervalDays: serviceIntervalDays,
  nextServiceDueDateKey: nextService,
  primaryContactName: contactPhone == null ? null : 'LG Service',
  primaryContactPhone: contactPhone,
  location: 'Living room',
  linkedRecurringTemplateId: linkedRecurringTemplateId,
  disposedAtDateKey: disposedAt,
  disposalReason: disposalReason,
  disposalAmount: disposalMinor == null ? null : Money(disposalMinor, 'INR'),
);

/// A house maid — the case §7.2 exists for: a person in the asset table with a salary history.
Asset maid({
  String id = 'asset-2',
  String name = 'Lakshmi',
  String? phone = '+919876543210',
}) => Asset(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  type: AssetType.serviceProvider,
  status: AssetStatus.active,
  primaryContactName: name,
  primaryContactPhone: phone,
  linkedRecurringTemplateId: 'tpl-1',
);

/// A service record of any type.
ServiceRecord serviceRecord({
  String id = 'rec-1',
  String assetId = 'asset-1',
  DateKey on = const DateKey(20260601),
  ServiceRecordType type = ServiceRecordType.service,
  int? costMinor = 120000,
  String? providerName = 'LG Service',
  String? linkedTransactionId,
  DateKey? nextDue,
}) => ServiceRecord(
  id: id,
  assetId: assetId,
  serviceDateKey: on,
  type: type,
  providerName: providerName,
  cost: costMinor == null ? null : Money(costMinor, 'INR'),
  linkedTransactionId: linkedTransactionId,
  nextDueDateKey: nextDue,
);

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
Future<void> pumpService(
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
