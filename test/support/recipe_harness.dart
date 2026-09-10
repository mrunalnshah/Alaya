/// Shared scaffolding for the Recipe module's widget tests.
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
import 'package:alaya/core/quantity/measure.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/recipe.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/domain/services/cookability_engine.dart';
import 'package:alaya/features/recipe/providers/recipe_detail_providers.dart';
import 'package:alaya/features/recipe/providers/recipe_editor_providers.dart';
import 'package:alaya/features/recipe/providers/recipe_list_providers.dart';

/// The narrowest phone this app supports (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// Tall enough that a lazy list builds its whole body.
///
/// Content assertions get this; the U15 gate stays narrow. A `ListView.builder` does not build rows
/// below the fold, so `findsNothing` at 320×640 passes for the wrong reason.
const Size kTallViewport = Size(320, 2400);

/// A stream that never emits, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// An item tracked by weight.
Item weightItem(
  String id,
  String name, {
  int? densityMilliGramsPerMl,
  int? milliGramsPerPiece,
}) => Item(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  unitCategory: UnitCategory.weight,
  defaultDisplayUnitCode: 'g',
  isFavorite: false,
  densityMilliGramsPerMl: densityMilliGramsPerMl,
  milliGramsPerPiece: milliGramsPerPiece,
);

/// Stock for [itemId], [grams] on hand.
ItemStock stockOf(String itemId, int grams, {DateKey? expiry}) => ItemStock(
  itemId: itemId,
  totalRemaining: Qty(grams * 1000, UnitCategory.weight),
  batchCount: 1,
  isLowStock: false,
  nearestExpiry: expiry,
);

/// An ingredient line needing [grams] of [itemId].
RecipeIngredient linked(
  String itemId,
  int grams, {
  int sortOrder = 0,
  bool optional = false,
}) => RecipeIngredient(
  id: 'ing-$itemId',
  recipeId: 'r1',
  itemId: itemId,
  quantity: Qty(grams * 1000, UnitCategory.weight),
  unitCode: 'g',
  isOptional: optional,
  sortOrder: sortOrder,
);

/// An ingredient line measured in millilitres, against an item kept by weight.
///
/// The bridge case: 15 ml of something weighed only converts if the item states its density.
RecipeIngredient inVolume(
  String itemId,
  int millilitres, {
  int sortOrder = 0,
}) => RecipeIngredient(
  id: 'ing-vol-$itemId',
  recipeId: 'r1',
  itemId: itemId,
  quantity: Qty(millilitres * 1000, UnitCategory.volume),
  unitCode: 'ml',
  sortOrder: sortOrder,
);

/// An ingredient line measured in a spoon or cup — half a tablespoon, two thirds of a cup.
///
/// **[amount] is a [Measure], not a [Qty], and that is the point of the fixture.** A recipe line in a
/// vessel is a fraction of that vessel; expressing it as milli-base units in a test would mean writing
/// `Qty(7394, volume)` and hoping it is still half a tablespoon after the factor is applied. The factor
/// comes from [kAllMeasureTestUnits], so it is the one the seed actually inserts — 14787 for a
/// tablespoon, which is where the round trip broke and where a tidy round number would have passed.
RecipeIngredient inVessel(
  String itemId,
  Measure amount, {
  String code = 'tbsp',
  int sortOrder = 0,
}) {
  final unit = kAllMeasureTestUnits.firstWhere((u) => u.code == code);
  return RecipeIngredient(
    id: 'ing-$code-$itemId',
    recipeId: 'r1',
    itemId: itemId,
    quantity: amount.toQty(
      factorToBaseMilli: unit.factorToBaseMilli,
      category: unit.category,
    ),
    unitCode: code,
    sortOrder: sortOrder,
  );
}

/// An ingredient line counted in pieces, against an item kept by weight.
RecipeIngredient inPieces(String itemId, int pieces, {int sortOrder = 0}) =>
    RecipeIngredient(
      id: 'ing-pc-$itemId',
      recipeId: 'r1',
      itemId: itemId,
      quantity: Qty(pieces * 1000, UnitCategory.count),
      unitCode: 'pc',
      sortOrder: sortOrder,
    );

/// An ingredient nothing tracks.
RecipeIngredient untracked(String name, {int sortOrder = 0}) =>
    RecipeIngredient(
      id: 'ing-$name',
      recipeId: 'r1',
      freeText: name,
      sortOrder: sortOrder,
    );

/// A recipe.
Recipe recipeOf({
  String id = 'r1',
  String name = 'Dal',
  int servings = 2,
  List<RecipeIngredient> ingredients = const [],
  List<RecipeStep> steps = const [],
  bool isFavorite = false,
}) => Recipe(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  servings: servings,
  ingredients: ingredients,
  steps: steps,
  isFavorite: isFavorite,
);

/// One batch standing in for a stock rollup, so the coarse and precise paths agree.
///
/// **This is what keeps a test that says nothing about batches meaning what it used to mean.**
/// `CookabilityEngine.judge` answers precisely when given batches and coarsely when not, and the
/// detail screen now always supplies them — so without a default every existing detail test would
/// suddenly judge against an empty shelf and report a shortfall. One unexpired batch holding the whole
/// rollup produces exactly the verdict the coarse path produced.
///
/// The expiry is carried through from `nearestExpiry`, so a test that deliberately dates its stock in
/// the past gets expired behaviour rather than a silent contradiction between the two fields.
Batch batchFromStock(ItemStock rollup) => Batch(
  id: 'synth-${rollup.itemId}',
  itemId: rollup.itemId,
  initialQuantity: rollup.totalRemaining,
  remainingQuantity: rollup.totalRemaining,
  unitCodeAtPurchase: 'g',
  purchasedDateKey: const DateKey(20260701),
  origin: BatchOrigin.manual,
  expiryDateKey: rollup.nearestExpiry,
);

/// Overrides the catalogue's streams, the single-recipe lookup, the unit table and the batch reads.
///
/// **Fixed length**, per ARCH_6 P5: a conditional entry changes the count between scopes and Riverpod
/// refuses it, while two `pumpWidget` calls in one test silently reuse the first scope — so a varying
/// list fails both ways.
///
/// **`recipeProvider` is fed from the same `recipes` list as `allRecipesProvider`.** Two parameters
/// would let a test give the list screen and the detail screen different recipes, which is a
/// disagreement no production build can have. Until this entry existed the detail screen could not be
/// pumped at all — it resolved `recipeRepositoryProvider`, which needs a database — and that is why
/// `RecipeDetailScreen` appeared in no test and rendered `7 ml` for half a tablespoon for as long as it
/// did.
///
/// **`unitsByCodeProvider` defaults to [kAllMeasureTestUnits]**, so a vessel line resolves its unit and
/// takes the `MeasureText` path. Left unoverridden it errors, `valueOrNull` is null, the map is empty and
/// every row silently falls back to `QtyText` — green, and proving nothing.
///
/// **`itemBatchesProvider` defaults to one synthesised batch per stocked item.** The detail screen's
/// verdict now depends on batches, and an unoverridden `batchRepositoryProvider` reaches for a database
/// and throws — which made every row on the screen disappear behind a skeleton. Pass [batches] to state
/// several batches per item, which is what an expiry test needs; omit it and the precise path agrees
/// with the coarse one.
List<Override> recipeOverrides({
  List<Recipe>? recipes,
  Map<String, ItemStock>? stock,
  Map<String, Item>? items,
  Map<String, List<Batch>>? batches,
  List<Unit> units = kAllMeasureTestUnits,
  bool loading = false,
}) => [
  allRecipesProvider.overrideWith(
    (ref) => loading
        ? pendingStream<List<Recipe>>()
        : Stream.value(recipes ?? const []),
  ),
  recipeProvider.overrideWith((ref, id) {
    if (loading) return pendingStream<Recipe?>();
    for (final recipe in recipes ?? const <Recipe>[]) {
      if (recipe.id == id) return Stream.value(recipe);
    }
    // Null is a real answer, and the screen has an empty state for it: a recipe deleted in another
    // tab while its detail screen is open.
    return Stream.value(null);
  }),
  stockByItemProvider.overrideWith(
    (ref) => loading
        ? pendingStream<Map<String, ItemStock>>()
        : Stream.value(stock ?? const {}),
  ),
  itemsByIdProvider.overrideWith(
    (ref) => loading
        ? pendingStream<Map<String, Item>>()
        : Stream.value(items ?? const {}),
  ),
  unitsByCodeProvider.overrideWith(
    (ref) => loading
        ? pendingStream<Map<String, Unit>>()
        : Stream.value({for (final unit in units) unit.code: unit}),
  ),
  itemBatchesProvider.overrideWith((ref, itemId) {
    if (loading) return pendingStream<List<Batch>>();
    final supplied = batches?[itemId];
    if (supplied != null) return Stream.value(supplied);
    final rollup = (stock ?? const <String, ItemStock>{})[itemId];
    // An item with no stock row has no batches, which is the same thing the rollup would have said.
    return Stream.value(rollup == null ? const [] : [batchFromStock(rollup)]);
  }),
];

/// Overrides for the editor's two lookups.
///
/// **Fixed length**, per ARCH_6 P5: a conditional entry changes the count between scopes and Riverpod
/// refuses it. Both default to empty, because an editor with no catalogue is a real state — a user
/// writing their first recipe before cataloguing anything.
List<Override> editorOverrides({
  List<Item> items = const [],
  List<Unit> units = const [],
}) => [
  editorItemsProvider.overrideWith((ref) => Stream.value(items)),
  editorUnitsProvider.overrideWith(
    (ref) => Stream.value(units.isEmpty ? kTestUnits : units),
  ),
];

/// A minimal unit set: one per category, so `QtyField` always has something to select.
///
/// Without a unit in the line's category the picker has nothing to offer and the row cannot produce a
/// `Qty` — the exact condition that made every saved ingredient null.
const List<Unit> kTestUnits = [
  Unit(
    code: 'g',
    category: UnitCategory.weight,
    factorToBaseMilli: 1000,
    displayName: 'Gram',
    isSystem: true,
    sortOrder: 0,
  ),
  Unit(
    code: 'ml',
    category: UnitCategory.volume,
    factorToBaseMilli: 1000,
    displayName: 'Millilitre',
    isSystem: true,
    sortOrder: 1,
  ),
  Unit(
    code: 'pc',
    category: UnitCategory.count,
    factorToBaseMilli: 1000,
    displayName: 'Piece',
    isSystem: true,
    sortOrder: 2,
  ),
];

/// Every measuring vessel, with the factors the seed actually inserts.
///
/// The factors matter: `4929` and `14787` are the ones that do not divide 1000 cleanly, which is where
/// the half-teaspoon round-trip broke. A test using tidy round numbers would have passed.
const List<Unit> kAllMeasureTestUnits = [
  Unit(
    code: 'g',
    category: UnitCategory.weight,
    factorToBaseMilli: 1000,
    displayName: 'Gram',
    isSystem: true,
    sortOrder: 0,
  ),
  Unit(
    code: 'tsp',
    category: UnitCategory.volume,
    factorToBaseMilli: 4929,
    displayName: 'Teaspoon',
    isSystem: true,
    sortOrder: 1,
  ),
  Unit(
    code: 'tbsp',
    category: UnitCategory.volume,
    factorToBaseMilli: 14787,
    displayName: 'Tablespoon',
    isSystem: true,
    sortOrder: 2,
  ),
  Unit(
    code: 'cup',
    category: UnitCategory.volume,
    factorToBaseMilli: 240000,
    displayName: 'Cup',
    isSystem: true,
    sortOrder: 3,
  ),
];

/// A unit set including a tablespoon, for the measuring-chip tests.
///
/// `kTestUnits` deliberately has no spoon — most tests do not need one, and a shorter list makes a
/// dropdown assertion easier to read.
const List<Unit> kSpoonTestUnits = [
  Unit(
    code: 'g',
    category: UnitCategory.weight,
    factorToBaseMilli: 1000,
    displayName: 'Gram',
    isSystem: true,
    sortOrder: 0,
  ),
  Unit(
    code: 'tbsp',
    category: UnitCategory.volume,
    factorToBaseMilli: 14787,
    displayName: 'Tablespoon',
    isSystem: true,
    sortOrder: 1,
  ),
];

/// Pumps [child] inside the app's theme and localisations.
///
/// The text scaler goes through `MaterialApp.builder`, because `WidgetsApp` re-establishes
/// `MediaQuery` from the view and an override placed above it never arrives.
Future<void> pumpRecipe(
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

/// The engine, for the pure tests.
const CookabilityEngine kEngine = CookabilityEngine();
