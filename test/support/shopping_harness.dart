/// Shared scaffolding for the Shopping module's widget tests.
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
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/entities/unit.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so snooze dates are the same on every machine.
final Clock kShoppingClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kShoppingClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// Kilograms.
const Unit kKilogram = Unit(
  code: 'kg',
  category: UnitCategory.weight,
  factorToBaseMilli: 1000000,
  displayName: 'kilogram',
  isSystem: true,
  sortOrder: 1,
);

/// A shopping-scoped tag.
const Tag kProduceTag = Tag(
  id: 'tag-1',
  name: 'Produce',
  normalizedName: 'produce',
  allowedScopes: {TagScope.shopping},
  isSystem: false,
  sortOrder: 0,
  isDeleted: false,
);

/// A catalogued item an entry can link to.
const Item kOnion = Item(
  id: 'item-1',
  name: 'Onion',
  normalizedName: 'onion',
  unitCategory: UnitCategory.weight,
  defaultDisplayUnitCode: 'kg',
  isFavorite: false,
  lowStockThreshold: Qty(2000000, UnitCategory.weight),
);

/// The default shopping list.
const ShoppingList kList = ShoppingList(
  id: 'list-1',
  name: 'Weekly shop',
  isDefault: true,
  isArchived: false,
);

/// An archived list, for the manager sheet.
const ShoppingList kArchivedList = ShoppingList(
  id: 'list-2',
  name: 'Diwali',
  isDefault: false,
  isArchived: true,
);

/// A manual entry.
ShoppingEntry sampleEntry({
  String id = 'entry-1',
  String? freeText = 'Television',
  String? itemId,
  String? tagId,
  bool isChecked = false,
  int sortOrder = 0,
  Money? estimatedPrice = const Money(4500000, 'INR'),
  ShoppingEntryOrigin origin = ShoppingEntryOrigin.manual,
  ShoppingEntryAutoState autoState = ShoppingEntryAutoState.active,
  DateKey? snoozeUntil,
  Qty? stockAtGeneration,
}) => ShoppingEntry(
  id: id,
  listId: kList.id,
  origin: origin,
  autoState: autoState,
  isChecked: isChecked,
  sortOrder: sortOrder,
  itemId: itemId,
  freeText: freeText,
  tagId: tagId,
  estimatedPrice: estimatedPrice,
  snoozeUntilDateKey: snoozeUntil,
  stockAtGeneration: stockAtGeneration,
);

/// An auto-generated low-stock suggestion, short by 1.5 kg against a 2 kg threshold.
ShoppingEntry sampleSuggestion({
  String id = 'auto-1',
  ShoppingEntryAutoState autoState = ShoppingEntryAutoState.active,
  DateKey? snoozeUntil,
}) => sampleEntry(
  id: id,
  freeText: null,
  itemId: kOnion.id,
  estimatedPrice: null,
  origin: ShoppingEntryOrigin.autoLowStock,
  autoState: autoState,
  snoozeUntil: snoozeUntil,
  stockAtGeneration: const Qty(500000, UnitCategory.weight),
);

/// A draft line, as `buildPurchaseDraft` would return it.
TransactionLine sampleDraftLine({
  String id = 'line-1',
  String description = 'Onion',
}) => TransactionLine(
  id: id,
  transactionId: '',
  lineNo: 1,
  description: description,
  destination: TransactionLineDestination.inventory,
  itemId: kOnion.id,
  quantity: const Qty(2000000, UnitCategory.weight),
  unitCode: 'kg',
);

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
Future<void> pumpShopping(
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
