/// Shared scaffolding for the Inventory module's widget tests.
///
/// Overrides the feature's view-model providers rather than faking every repository: a widget test's
/// job is the widget — four states, a doubled text scale, the tap-target floor (ARCH_5 §9.1).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/domain/entities/unit.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so relative dates are the same on every machine.
final Clock kInventoryClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kInventoryClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// Grams.
const Unit kGram = Unit(
  code: 'g',
  category: UnitCategory.weight,
  factorToBaseMilli: 1000,
  displayName: 'gram',
  isSystem: true,
  sortOrder: 0,
);

/// Kilograms.
const Unit kKilogram = Unit(
  code: 'kg',
  category: UnitCategory.weight,
  factorToBaseMilli: 1000000,
  displayName: 'kilogram',
  isSystem: true,
  sortOrder: 1,
);

/// A sample item measured by weight.
const Item kItem = Item(
  id: 'item-1',
  name: 'Atta',
  normalizedName: 'atta',
  unitCategory: UnitCategory.weight,
  defaultDisplayUnitCode: 'kg',
  isFavorite: true,
);

/// The mixed-unit total ARCH_1 §5.4 uses as its worked example: 250 + 2000 + 1500 + 700 = 4 kg 450 g.
const Qty kFourKilo450 = Qty(4450000, UnitCategory.weight);

/// Stock on hand for [kItem].
const ItemStock kStock = ItemStock(
  itemId: 'item-1',
  totalRemaining: kFourKilo450,
  batchCount: 4,
  isLowStock: false,
  nearestExpiry: DateKey(20260810),
);

/// A sample batch.
Batch sampleBatch({
  String id = 'batch-1',
  int remainingMilli = 2000000,
  BatchOrigin origin = BatchOrigin.purchase,
  DateKey? expiry = const DateKey(20260810),
  String? location = 'Pantry',
}) => Batch(
  id: id,
  itemId: kItem.id,
  initialQuantity: const Qty(2000000, UnitCategory.weight),
  remainingQuantity: Qty(remainingMilli, UnitCategory.weight),
  unitCodeAtPurchase: 'kg',
  purchasedDateKey: const DateKey(20260715),
  origin: origin,
  expiryDateKey: expiry,
  unitCost: const Money(4500, 'INR'),
  storageLocation: location,
);

/// A sample movement.
StockMovement sampleMovement({
  String id = 'mv-1',
  StockMovementKind kind = StockMovementKind.consume,
  String? reverses,
  String? reason,
}) => StockMovement(
  id: id,
  batchId: 'batch-1',
  itemId: kItem.id,
  kind: kind,
  quantity: const Qty(500000, UnitCategory.weight),
  occurredAtUtc: DateTime.utc(2026, 8, 1, 4),
  dateKey: kToday,
  reason: reason,
  reversesMovementId: reverses,
);

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
///
/// The `MediaQuery` sits inside `MaterialApp.builder` because `WidgetsApp` re-establishes it from the
/// view, so an outer override never reaches the widget under test.
Future<void> pumpInventory(
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
