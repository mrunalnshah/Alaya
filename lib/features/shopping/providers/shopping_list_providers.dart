/// View-model state for the shopping list (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/tag.dart';

/// One tag's worth of entries.
class ShoppingGroup {
  /// Creates a group.
  const ShoppingGroup({required this.entries, this.tag});

  /// The entries under it, in sort order.
  final List<ShoppingEntry> entries;

  /// The tag this group collects, or null for the untagged remainder.
  final Tag? tag;
}

/// Which list the screen is showing, or null to follow the default.
final selectedListIdProvider = NotifierProvider<SelectedListNotifier, String?>(
  SelectedListNotifier.new,
);

/// Remembers which list the user switched to.
class SelectedListNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Switches to [listId], or back to the default when null.
  void select(String? listId) => state = listId;
}

/// The lists a user may switch between.
final selectableListsProvider = StreamProvider<List<ShoppingList>>(
  (ref) => ref.watch(shoppingRepositoryProvider).watchSelectableLists(),
);

/// Every list, archived included, for the manager sheet.
final allListsProvider = StreamProvider<List<ShoppingList>>(
  (ref) => ref.watch(shoppingRepositoryProvider).watchAllLists(),
);

/// The list marked default.
final defaultListProvider = StreamProvider<ShoppingList?>(
  (ref) => ref.watch(shoppingRepositoryProvider).watchDefaultList(),
);

/// The list actually on screen: the explicit selection, else the default.
final activeListProvider = Provider<AsyncValue<ShoppingList?>>((ref) {
  final selected = ref.watch(selectedListIdProvider);
  final lists = ref.watch(selectableListsProvider);
  final fallback = ref.watch(defaultListProvider);
  if (selected == null) return fallback;
  return lists.whenData((all) {
    for (final list in all) {
      if (list.id == selected) return list;
    }
    return fallback.valueOrNull;
  });
});

/// Every entry on the active list.
final entriesProvider = StreamProvider.autoDispose
    .family<List<ShoppingEntry>, String>(
      (ref, listId) =>
          ref.watch(shoppingRepositoryProvider).watchEntries(listId),
    );

/// Tags, keyed by id, so a group header can name itself.
final shoppingTagsByIdProvider = StreamProvider<Map<String, Tag>>(
  (ref) => ref
      .watch(tagRepositoryProvider)
      .watchAll()
      .map(
        (tags) => {for (final tag in tags) tag.id: tag},
      ),
);

/// Items, keyed by id, so a linked entry can show the catalogue name.
final shoppingItemsByIdProvider = StreamProvider<Map<String, Item>>(
  (ref) => ref
      .watch(itemRepositoryProvider)
      .watchAll()
      .map(
        (items) => {for (final item in items) item.id: item},
      ),
);

/// The active list's entries, filtered for visibility and grouped by tag.
///
/// **What counts as outstanding is decided by the entity, not here.**
/// `ShoppingEntry.isOutstandingAsOf` owns it: snoozed and dismissed suggestions are hidden by the same
/// rule the regeneration engine applies (anomalies A22, A23), and anything already bought drops off
/// because a list is a list of what to get. A second copy of either rule in the view model is a second
/// place for it to drift.
final shoppingGroupsProvider = Provider.autoDispose
    .family<AsyncValue<List<ShoppingGroup>>, String>((ref, listId) {
      final entries = ref.watch(entriesProvider(listId));
      final tags = ref.watch(shoppingTagsByIdProvider);
      if (entries.hasError)
        return AsyncValue.error(entries.error!, entries.stackTrace!);
      final rows = entries.valueOrNull;
      if (rows == null) return const AsyncValue.loading();
      final byId = tags.valueOrNull ?? const <String, Tag>{};
      final today = ref.watch(clockProvider).today();

      final visible = [
        for (final entry in rows)
          if (entry.isOutstandingAsOf(today)) entry,
      ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      final buckets = <String?, List<ShoppingEntry>>{};
      for (final entry in visible) {
        buckets.putIfAbsent(entry.tagId, () => <ShoppingEntry>[]).add(entry);
      }
      final tagged =
          [
            for (final id in buckets.keys)
              if (id != null && byId[id] != null)
                ShoppingGroup(entries: buckets[id]!, tag: byId[id]),
          ]..sort(
            (a, b) =>
                a.tag!.name.toLowerCase().compareTo(b.tag!.name.toLowerCase()),
          );

      return AsyncValue.data([
        ...tagged,
        if (buckets[null] != null) ShoppingGroup(entries: buckets[null]!),
      ]);
    });

/// The running estimate for the active list, and how far through it the user is.
class ShoppingSummary {
  /// Creates a summary.
  const ShoppingSummary({
    required this.estimate,
    required this.checked,
    required this.total,
  });

  /// The summed estimate of every visible entry that carries one, or null when none do.
  final Money? estimate;

  /// How many visible entries are ticked.
  final int checked;

  /// How many visible entries there are.
  final int total;

  /// Whether anything is ticked, which is what convert-to-purchase needs.
  bool get hasChecked => checked > 0;
}

/// The active list's running estimate and tick progress.
///
/// Entries without an estimate are skipped rather than counted as zero: a list of ten things where
/// two are priced should read as the sum of those two, not as a total that quietly understates by
/// eight.
final shoppingSummaryProvider = Provider.autoDispose
    .family<ShoppingSummary, String>((ref, listId) {
      final groups =
          ref.watch(shoppingGroupsProvider(listId)).valueOrNull ?? const [];
      Money? estimate;
      var checked = 0;
      var total = 0;
      for (final group in groups) {
        for (final entry in group.entries) {
          total += 1;
          if (entry.isChecked) checked += 1;
          final price = entry.estimatedPrice;
          if (price == null) continue;
          estimate = estimate == null ? price : estimate + price;
        }
      }
      return ShoppingSummary(
        estimate: estimate,
        checked: checked,
        total: total,
      );
    });

/// Writes the shopping list screen performs.
final shoppingActionsProvider = Provider<ShoppingActions>(ShoppingActions.new);

/// Ticks, snoozes, dismisses and deletes entries.
///
/// **Every method returns the failure's own message, or null on success.** A repository `Failure`
/// carries a `message` written for exactly this, and reporting "something went wrong" instead threw
/// it away — three separate bugs reached the user as the same sentence, none of them diagnosable.
class ShoppingActions {
  /// Creates the actions.
  ShoppingActions(this._ref);

  final Ref _ref;

  /// How long a snooze lasts.
  static const int snoozeDays = 7;

  /// Ticks or unticks an entry.
  Future<String?> setChecked({
    required String id,
    required bool isChecked,
  }) async {
    final result = await _ref
        .read(shoppingRepositoryProvider)
        .setEntryChecked(id: id, isChecked: isChecked);
    return result.failureOrNull?.message;
  }

  /// Hides a suggestion for a week.
  Future<String?> snooze(String id) async {
    final until = _ref.read(clockProvider).today().addDays(snoozeDays);
    final result = await _ref
        .read(shoppingRepositoryProvider)
        .snoozeEntry(id: id, until: until);
    return result.failureOrNull?.message;
  }

  /// Dismisses a suggestion until stock recovers and drops again.
  Future<String?> dismiss(String id) async {
    final result = await _ref.read(shoppingRepositoryProvider).dismissEntry(id);
    return result.failureOrNull?.message;
  }

  /// Removes an entry outright.
  Future<String?> delete(String id) async {
    final result = await _ref.read(shoppingRepositoryProvider).deleteEntry(id);
    return result.failureOrNull?.message;
  }

  /// Unticks every entry on a list.
  Future<void> uncheckAll(List<ShoppingEntry> entries) async {
    final repository = _ref.read(shoppingRepositoryProvider);
    for (final entry in entries) {
      if (!entry.isChecked) continue;
      await repository.setEntryChecked(id: entry.id, isChecked: false);
    }
  }
}
