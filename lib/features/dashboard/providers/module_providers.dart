/// The live numbers on the dashboard's navigation tiles (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/inventory/providers/inventory_list_providers.dart';
import 'package:alaya/features/recipe/providers/recipe_list_providers.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

/// How many transactions were recorded this calendar month.
///
/// The month rather than a rolling window, because the tile's wording says "this month" and a tile whose
/// number does not match its label is worse than no number (anomaly A33).
final expenseCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final today = ref.watch(clockProvider).today();
  final month = ref.watch(dateRangeServiceProvider).wholeMonthOf(today);
  final rows = await ref
      .watch(transactionRepositoryProvider)
      .watchByDateRange(from: month.from, to: month.to)
      .first;
  return rows.length;
});

/// How many items sit below their low-stock level.
///
/// **Phase 6B's provider, not a second one.** `lowStockCountProvider` already answers exactly this and is
/// derived from the same stream the inventory list watches — a dashboard-local reimplementation would be a
/// second definition of "low" to keep in step (ARCH_4 P7).
final inventoryCountProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(lowStockCountProvider),
);

/// How many recipes can be cooked right now.
///
/// **Phase R3a's provider, not a second one.** `cookableCountProvider` is derived from the same single
/// pass the recipe catalogue makes, so the tile and the list can never disagree about what "cookable"
/// means — the same argument `inventoryCountProvider` makes about "low" (ARCH_4 P7).
///
/// Counts only `ready`. A recipe the engine could not judge is not one the tile can promise.
final recipeCountProvider = Provider.autoDispose<int?>(
  (ref) => ref.watch(cookableCountProvider),
);

/// How many people have something outstanding with you, either way.
///
/// **Counterparties, not amounts**, because a tile holds one small number and "3 people" is a thing a
/// person can act on where "₹4,150" invites the question of which direction it runs. The card below the
/// grid carries the two figures; this only says how many conversations are open.
///
/// **Not `SplitBalanceService.totals`, and not a second definition of "outstanding".**
/// `splitBalancesProvider` already drops anyone who nets to zero, so this counts exactly what the split
/// screen lists — the same argument `inventoryCountProvider` and `recipeCountProvider` both make about
/// reusing their module's own provider rather than re-deriving (ARCH_4 P7).
final splitCountProvider = Provider.autoDispose<int?>(
  (ref) => ref.watch(splitBalancesProvider).valueOrNull?.length,
);

/// How many things are still to buy on the default list.
final shoppingCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final repository = ref.watch(shoppingRepositoryProvider);
  final list = await repository.watchDefaultList().first;
  if (list == null) return 0;
  final entries = await repository.watchUncheckedEntries(list.id).first;
  final today = ref.watch(clockProvider).today();
  // The entity decides what counts: a snoozed suggestion and a bought entry are both unchecked and
  // neither is something to buy (see `ShoppingEntry.isOutstandingAsOf`).
  return entries.where((entry) => entry.isOutstandingAsOf(today)).length;
});

/// How many recurring obligations are outstanding.
final recurringCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final due = await ref.watch(recurringRepositoryProvider).watchDue().first;
  return due.where((row) => row.occurrence != null).length;
});

/// How many assets need a service or are losing their warranty.
///
/// Reuses the dashboard's own upcoming list rather than re-querying, so the tile and the insight card can
/// never disagree about what needs attention.
final serviceCountProvider = Provider.autoDispose<int>((ref) {
  final upcoming =
      ref.watch(upcomingProvider).valueOrNull ?? const <UpcomingEntry>[];
  return upcoming
      .where(
        (entry) =>
            entry.kind == UpcomingKind.service ||
            entry.kind == UpcomingKind.warranty,
      )
      .length;
});
