/// One view-model provider per ARCH_3 §5.1 query (ARCH_5 U19).
///
/// **Every figure is its own provider, and that is what makes archetype F's "one failing card never
/// blanks the screen" true rather than aspirational.** A single provider returning all twenty-four
/// results would fail as a unit.
///
/// All of them watch `analyticsWindowProvider`, so changing the range chip recomputes the screen with
/// no per-card plumbing. All are `autoDispose`: leaving the screen should release a month of
/// aggregates rather than hold them for a session.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/services/analytics/analytics_cache_service.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';

/// An item named for a family key, so a provider caches per item rather than per rebuild.
///
/// A record, so Riverpod compares by value. The name travels with the id because
/// `AnalyticsService.unitPriceTrend` takes both — the port returns ids and the service will not guess
/// a label it was not given.
typedef AnalyticsItemRef = ({String id, String name});

// ── the headline ──────────────────────────────────────────────────────────────────────────

/// Total spend in the window and how concentrated it is — queries 8 and 22.
///
/// **One query serves the headline figure and the concentration card**, because
/// `Concentration.total` *is* total spend in the home currency. `AnalyticsPort.totalSpend` exists and
/// `AnalyticsService` never calls it: the service derives the total from `spendBySubtype` instead, so
/// asking the port again would be a second read for a number already in hand.
final analyticsHeadlineProvider = FutureProvider.autoDispose<Concentration>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.categoryConcentration(ref.watch(analyticsWindowProvider));
});

/// The same figure over the preceding window of equal length, for a period-over-period line.
final analyticsPreviousHeadlineProvider =
    FutureProvider.autoDispose<Concentration>((ref) async {
      final service = await ref.watch(analyticsServiceProvider.future);
      return service.categoryConcentration(
        ref.watch(analyticsPreviousWindowProvider),
      );
    });

// ── 1-4: where it went ────────────────────────────────────────────────────────────────────

/// Query 1 — spend by subtype.
///
/// The slices carry the **enum name** as both key and label, because that is what SQL grouped by. A
/// surface renders `slice.key` through an ARB lookup and never `slice.label`, or an untranslated
/// `grocery` reaches the screen (Law U5).
final spendBySubtypeProvider = FutureProvider.autoDispose<MoneySeries>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.spendBySubtype(ref.watch(analyticsWindowProvider));
});

/// Query 2 — spend by tag. Labels here **are** data, so they render directly.
///
/// A transaction carrying two tags contributes to both slices, so these do not sum to total spend.
/// The surface says so rather than presenting them as a partition.
final spendByTagProvider = FutureProvider.autoDispose<MoneySeries>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.spendByTag(ref.watch(analyticsWindowProvider));
});

/// Query 3 — spend by payment method.
final spendByPaymentMethodProvider = FutureProvider.autoDispose<MoneySeries>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.spendByPaymentMethod(ref.watch(analyticsWindowProvider));
});

/// Query 4 — the top payees by spend, ranked after conversion.
final topPayeesProvider = FutureProvider.autoDispose<MoneySeries>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.topPayeesBySpend(ref.watch(analyticsWindowProvider));
});

/// Query 8 — grocery's share of total spend, or null when nothing was spent on groceries.
final groceryShareProvider = FutureProvider.autoDispose<ShareOfTotal?>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.groceryShareOfSpend(ref.watch(analyticsWindowProvider));
});

// ── the tag hierarchy, for the one-level drill ARCH_5 §7.2 assigns ────────────────────────

/// Every tag by id, so a slice can be rolled up to its parent.
///
/// `watchAll` rather than `watchRoots` plus `watchChildren`: the rollup needs the whole
/// `id -> parentTagId` map in one place, and the tag table is small enough that two streams would be
/// more work than one map.
final analyticsTagsByIdProvider = StreamProvider.autoDispose<Map<String, Tag>>(
  (ref) => ref
      .watch(tagRepositoryProvider)
      .watchAll()
      .map((tags) => {for (final tag in tags) tag.id: tag}),
);

/// One tag's spend and the spend of its children, for the tag card's two levels.
class TagSpendNode {
  /// Creates a node.
  const TagSpendNode({
    required this.tag,
    required this.own,
    required this.rolledUp,
    required this.children,
  });

  /// The tag itself. May be soft-deleted, which still labels old transactions (anomaly A36).
  final Tag tag;

  /// What was spent against this tag alone.
  final Money own;

  /// [own] plus every child's spend — what the top level shows.
  final Money rolledUp;

  /// This tag's children that have spend in the window, largest first.
  final List<TagSpendNode> children;

  /// Whether drilling into this node would show anything new.
  bool get canDrill => children.isNotEmpty;
}

/// Root tags with their children rolled up, largest first — the tag card's feed.
///
/// **This is the whole of `tags.parentTagId`'s analytics surface** (ARCH_5 §7.2). One level, because
/// the schema permits exactly one and the repository enforces it (ARCH_2 §3).
///
/// A slice whose tag is missing from the map is dropped rather than shown parentless: it means the
/// tag stream and the spend query disagreed for a frame, and inventing a row for it would flicker.
final tagSpendTreeProvider = FutureProvider.autoDispose<List<TagSpendNode>>((
  ref,
) async {
  final series = await ref.watch(spendByTagProvider.future);
  final tags = await ref.watch(analyticsTagsByIdProvider.future);
  final code = await ref.watch(analyticsCurrencyProvider.future);

  final own = <String, Money>{};
  for (final slice in series.slices) {
    own[slice.key] = slice.amount;
  }

  final childrenOf = <String, List<TagSpendNode>>{};
  final roots = <String, Money>{};
  for (final entry in own.entries) {
    final tag = tags[entry.key];
    if (tag == null) continue;
    final parentId = tag.parentTagId;
    if (parentId == null) continue;
    (childrenOf[parentId] ??= <TagSpendNode>[]).add(
      TagSpendNode(
        tag: tag,
        own: entry.value,
        rolledUp: entry.value,
        children: const <TagSpendNode>[],
      ),
    );
  }

  for (final entry in own.entries) {
    final tag = tags[entry.key];
    if (tag == null || tag.isChild) continue;
    roots[entry.key] = entry.value;
  }
  // A parent with no spend of its own but children that do spend still belongs at the top level:
  // "Grocery ₹0" would be wrong and hiding it would lose the children entirely.
  for (final parentId in childrenOf.keys) {
    if (tags.containsKey(parentId))
      roots.putIfAbsent(parentId, () => Money.zero(code));
  }

  final nodes = <TagSpendNode>[];
  for (final entry in roots.entries) {
    final children = (childrenOf[entry.key] ?? const <TagSpendNode>[]).toList()
      ..sort((a, b) => b.rolledUp.minor.compareTo(a.rolledUp.minor));
    final rolled = children.fold<int>(
      entry.value.minor,
      (sum, c) => sum + c.rolledUp.minor,
    );
    nodes.add(
      TagSpendNode(
        tag: tags[entry.key]!,
        own: entry.value,
        rolledUp: Money(rolled, code),
        children: children,
      ),
    );
  }
  nodes.sort((a, b) => b.rolledUp.minor.compareTo(a.rolledUp.minor));
  return nodes;
});

// ── 5-7, 21: over time ────────────────────────────────────────────────────────────────────

/// Query 5 — income against expense, month by month.
final incomeVsExpenseProvider = FutureProvider.autoDispose<IncomeVsExpense>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.incomeVsExpense(ref.watch(analyticsWindowProvider));
});

/// Query 6 — net cash flow per month, from the signed ledger.
final netCashFlowProvider = FutureProvider.autoDispose<NetCashFlow>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.netCashFlowByMonth(ref.watch(analyticsWindowProvider));
});

/// Query 7 — one account's running balance, in that account's own currency.
///
/// Never converted: converting each point at its own date would make the line move when rates moved
/// rather than when money did.
final balanceTrendProvider = FutureProvider.autoDispose
    .family<BalanceTrend, String>((ref, accountId) async {
      final service = await ref.watch(analyticsServiceProvider.future);
      return service.balanceTrend(
        accountId,
        ref.watch(analyticsWindowProvider),
      );
    });

/// The accounts the balance-trend card can offer.
final analyticsAccountsProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// Query 21 — spend bucketed by weekday or day of month, **through the cache**.
///
/// **One of exactly two cached queries in this phase, and the gate is
/// `AnalyticsCacheService.shouldCache` rather than a preference.** This one earns it: the bucket is
/// `strftime` over a rebuilt date string, so no index in ARCH_2 §11 can serve the grouping and the
/// cost grows with the whole window rather than with the number of buckets.
///
/// The other twenty-two are computed live. §5.2 asks for a cache "for anything over ~200 ms", and the
/// service's own doc comment says why the rest are not: a cache on a query that already runs in 5 ms
/// costs a read, a write, an invalidation path and a staleness bug and buys nothing.
final spendHeatmapProvider = FutureProvider.autoDispose.family<SpendHeatmap, bool>((
  ref,
  byWeekday,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  final cache = ref.watch(analyticsCacheServiceProvider);
  final window = ref.watch(analyticsWindowProvider);

  if (!cache.shouldCache(heatmapEstimatedCost)) {
    return service.spendHeatmap(window, byWeekday: byWeekday);
  }
  // Encoded then decoded even on a miss, deliberately: the cache stores strings, so one path through
  // the codec is simpler than two and guarantees a hit and a miss return the same shape.
  final payload = await cache.readOrCompute(
    queryName: 'spendHeatmap',
    params: {...cache.windowParams(window), 'byWeekday': byWeekday},
    compute: () async => _encodeHeatmap(
      await service.spendHeatmap(window, byWeekday: byWeekday),
    ),
  );
  return _decodeHeatmap(payload);
});

/// What query 21 is estimated to cost, measured against `AnalyticsCacheService.cacheThreshold`.
const Duration heatmapEstimatedCost = Duration(milliseconds: 250);

/// What query 13 is estimated to cost.
const Duration inventoryValueEstimatedCost = Duration(milliseconds: 220);

// ── 9-12, 23, 24: items and prices ────────────────────────────────────────────────────────

/// Query 9 — the top items by spend, ranked after conversion.
final topItemsBySpendProvider = FutureProvider.autoDispose<List<ItemSpend>>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.topItemsBySpend(ref.watch(analyticsWindowProvider));
});

/// Query 10 — the top items by quantity bought, per unit category.
///
/// Not ranked across categories and not converted: grams and pieces are not comparable at all
/// (Law L8), so the surface groups by category rather than producing a single ordering that would
/// mean nothing.
final topItemsByQuantityProvider =
    FutureProvider.autoDispose<List<ItemQuantity>>((ref) async {
      final service = await ref.watch(analyticsServiceProvider.future);
      return service.topItemsByQuantity(ref.watch(analyticsWindowProvider));
    });

/// Query 11 — the dearest single purchase of one item, in the currency it was bought in.
final dearestPurchaseProvider = FutureProvider.autoDispose
    .family<DearestPurchase?, AnalyticsItemRef>((ref, item) async {
      final service = await ref.watch(analyticsServiceProvider.future);
      return service.dearestPurchaseOfItem(
        item.id,
        item.name,
        ref.watch(analyticsWindowProvider),
      );
    });

/// Queries 12 and 24 — one item's unit-price trend and the change across it.
///
/// **One provider for both queries, because query 24 is query 12's data.**
/// `AnalyticsService.unitPriceTrend` calls `pricePerBaseUnitHistory` and returns its points
/// alongside the percentage change, so a second provider would run the same read twice. The surface
/// draws the points (24) and states the change (12).
final unitPriceTrendProvider = FutureProvider.autoDispose
    .family<UnitPriceTrend, AnalyticsItemRef>((ref, item) async {
      final service = await ref.watch(analyticsServiceProvider.future);
      return service.unitPriceTrend(
        item.id,
        item.name,
        ref.watch(analyticsWindowProvider),
      );
    });

/// The item whose unit price moved most across the window — the personal-inflation headline.
///
/// **This is the screenshot** (ARCH_3 §5.1: *"your potatoes cost 34% more than in January"*). It is
/// derived rather than asked for: no query returns "the most interesting item", so the candidates are
/// the top items by spend — the ones the reader actually buys — and the winner is the largest
/// absolute change among them.
///
/// Capped at [inflationCandidateCount] queries. Uncapped this would be one read per item in the
/// house, on a card that shows one line.
///
/// Null when nothing has two priced purchases in the window, which is the ordinary case for a new
/// install and reads as an absence rather than as a failure.
final personalInflationProvider = FutureProvider.autoDispose<UnitPriceTrend?>((
  ref,
) async {
  final items = await ref.watch(topItemsBySpendProvider.future);
  UnitPriceTrend? best;
  for (final item in items.take(inflationCandidateCount)) {
    final trend = await ref.watch(
      unitPriceTrendProvider((id: item.itemId, name: item.itemName)).future,
    );
    final change = trend.percentChange;
    if (change == null) continue;
    final bestChange = best?.percentChange;
    if (bestChange == null || change.abs() > bestChange.abs()) best = trend;
  }
  return best;
});

/// How many of the top-spend items are probed for a price trend.
const int inflationCandidateCount = 5;

/// Query 23 — the average grocery basket.
final averageBasketProvider = FutureProvider.autoDispose<BasketStats>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.averageGroceryBasket(ref.watch(analyticsWindowProvider));
});

// ── 13-16: the home ───────────────────────────────────────────────────────────────────────

/// Query 13 — inventory value on hand, per currency, **through the cache**.
///
/// The second of the two cached queries. It is unbounded by design — stock on hand has no window —
/// so its cost grows with the shelf rather than with the range, and it is the one figure on the
/// screen that a narrower range cannot make cheaper.
///
/// Per currency rather than one total: batch cost currency is per row, and a single figure would be
/// adding rupees to yen (anomaly A34).
final inventoryValueProvider = FutureProvider.autoDispose<InventoryValue>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  final cache = ref.watch(analyticsCacheServiceProvider);
  if (!cache.shouldCache(inventoryValueEstimatedCost)) {
    return service.inventoryValueOnHand();
  }
  final payload = await cache.readOrCompute(
    queryName: 'inventoryValueOnHand',
    // No window: the figure is "right now", so the parameter set is empty and the entry is a
    // singleton. `hashParams({})` is stable, so this still gets its own row.
    params: const <String, Object?>{},
    compute: () async =>
        _encodeInventoryValue(await service.inventoryValueOnHand()),
  );
  return _decodeInventoryValue(payload);
});

/// Query 14 — food waste, in quantity and money.
///
/// Reversed movements are already excluded by the adapter, so this reports what was wasted and not
/// what was wasted and then corrected.
final wasteTotalsProvider = FutureProvider.autoDispose<List<ItemWasteTotal>>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.wasteTotals(ref.watch(analyticsWindowProvider));
});

/// Query 15 — batches expiring within [days] of today, soonest first.
///
/// Keyed on days rather than on the window: expiry is about the future and the reporting range is
/// about the past, so tying the two would make "last month" show nothing expiring.
final expiringBatchesProvider = FutureProvider.autoDispose
    .family<List<ExpiringBatch>, int>((ref, days) async {
      final service = await ref.watch(analyticsServiceProvider.future);
      return service.itemsExpiringWithin(days);
    });

/// The expiry horizon the home section shows.
const int expiryHorizonDays = 14;

/// Query 16 — how many items are low on stock, as one point.
///
/// One point and not a history: `v_low_stock` reflects the present and stock is not versioned, so
/// "how many were low last Tuesday" would mean replaying the movement ledger against thresholds that
/// may since have changed.
final lowStockTodayProvider = FutureProvider.autoDispose<LowStockPoint>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.lowStockCountToday();
});

// ── 17-20: commitments and assets ─────────────────────────────────────────────────────────

/// Query 17 — the fixed monthly commitment total, every interval normalised to a month.
final monthlyCommitmentProvider = FutureProvider.autoDispose<MonthlyCommitment>(
  (ref) async {
    final service = await ref.watch(analyticsServiceProvider.future);
    return service.monthlyCommitmentTotal();
  },
);

/// Query 18 — the recurring against discretionary split.
final recurringSplitProvider = FutureProvider.autoDispose<RecurringSplit>((
  ref,
) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.recurringVsDiscretionary(ref.watch(analyticsWindowProvider));
});

/// Query 19 — lifetime service cost per asset, per currency.
///
/// Disposed assets are included: the money you put into a TV stays in the analytics after you sell
/// it, which is the point of `status = disposed` rather than a delete.
final serviceCostByAssetProvider =
    FutureProvider.autoDispose<List<AssetServiceCost>>((ref) async {
      final service = await ref.watch(analyticsServiceProvider.future);
      return service.lifetimeServiceCostByAsset(
        ref.watch(analyticsWindowProvider),
      );
    });

/// Query 20 — the warranty coverage timeline.
final warrantyCoverageProvider =
    FutureProvider.autoDispose<List<WarrantyCoverage>>((ref) async {
      final service = await ref.watch(analyticsServiceProvider.future);
      return service.warrantyCoverage();
    });

// ── cache codecs ──────────────────────────────────────────────────────────────────────────
//
// Two, not twenty-four. `AnalyticsCacheService` stores strings, so caching a result type means a
// codec for it — and writing twenty-four to satisfy the letter of ARCH_3 §5.2 would contradict its
// reasoning, which is that a cache is only worth its invalidation path above roughly 200 ms.
//
// `Money` encodes as minor units plus its code and never as a decimal (Law L1): a JSON number for
// `12.34` would be a double crossing a persistence boundary, which is exactly what L1 forbids.

String _encodeHeatmap(SpendHeatmap heatmap) => jsonEncode({
  'cells': [
    for (final cell in heatmap.cells)
      {
        'b': cell.bucket,
        'm': cell.amount.minor,
        'c': cell.amount.currencyCode,
        'n': cell.transactionCount,
      },
  ],
  'approx': heatmap.quality.approximateCount,
  'unconv': heatmap.quality.unconvertedCount,
});

SpendHeatmap _decodeHeatmap(String payload) {
  final root = jsonDecode(payload) as Map<String, Object?>;
  final raw = root['cells'] as List<Object?>? ?? const <Object?>[];
  // `const <HeatmapCell>[]` and never a bare `const []`: a record field takes the literal's inferred
  // type verbatim, so `List<dynamic>` would not satisfy `List<HeatmapCell>` (ARCH_4 R17).
  final cells = <HeatmapCell>[];
  for (final entry in raw) {
    final cell = entry as Map<String, Object?>;
    cells.add((
      bucket: cell['b']! as int,
      amount: Money(cell['m']! as int, cell['c']! as String),
      transactionCount: cell['n']! as int,
    ));
  }
  return (
    cells: cells.isEmpty ? const <HeatmapCell>[] : cells,
    quality: (
      approximateCount: root['approx'] as int? ?? 0,
      unconvertedCount: root['unconv'] as int? ?? 0,
    ),
  );
}

String _encodeInventoryValue(InventoryValue value) => jsonEncode({
  'by': {
    for (final entry in value.byCurrency.entries) entry.key: entry.value.minor,
  },
  'valued': value.batchesValued,
  'noCost': value.batchesNoCost,
});

InventoryValue _decodeInventoryValue(String payload) {
  final root = jsonDecode(payload) as Map<String, Object?>;
  final by = root['by'] as Map<String, Object?>? ?? const <String, Object?>{};
  return (
    byCurrency: {
      for (final entry in by.entries)
        entry.key: Money(entry.value! as int, entry.key),
    },
    batchesValued: root['valued'] as int? ?? 0,
    batchesNoCost: root['noCost'] as int? ?? 0,
  );
}
