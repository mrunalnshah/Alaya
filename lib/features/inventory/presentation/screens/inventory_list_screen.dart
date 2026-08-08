import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/features/inventory/presentation/widgets/item_row.dart';
import 'package:alaya/features/inventory/providers/inventory_list_providers.dart';
import 'package:alaya/features/inventory/providers/item_detail_providers.dart';
import 'package:alaya/features/inventory/state/inventory_filter.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_search_field.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';

/// The inventory catalogue (ARCH_5 §3 archetype D).
///
/// **Search is a pinned field, not an app-bar icon.** A catalogue is searched constantly, and the
/// shell above owns the app bar anyway, so the field lives in the body where it is always visible.
///
/// Grouped by `items.itemKind`. Archetype D calls for the tag axis and ARCH_5 §7.1 assigns
/// `item_tags` to this phase, but no Phase 3A contract reads or writes an item's tags — see
/// `InventoryFilter`'s doc comment and the coverage table. The group-by control already carries two
/// axes, so adding the tag axis later is a third entry rather than a restructure.
class InventoryListScreen extends ConsumerWidget {
  /// Creates the screen.
  const InventoryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final groups = ref.watch(inventoryGroupsProvider);
    final filter = ref.watch(inventoryFilterProvider);

    return Scaffold(
      body: Column(
        children: [
          const _Toolbar(),
          const _ActiveFilters(),
          Expanded(
            child: groups.when(
              loading: () => AlayaListSkeleton(label: strings.loadingInventory),
              error: (error, stack) => ErrorState(
                title: strings.errorTitleGeneric,
                body: strings.errorBodyGeneric,
                retryLabel: strings.actionRetry,
                onRetry: () => ref.invalidate(itemsProvider),
              ),
              data: (sections) => sections.isEmpty
                  ? _Empty(isSearching: filter.isSearching || filter.isNarrowed)
                  : _Sections(sections: sections),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.itemNew),
        tooltip: strings.addItem,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final notifier = ref.read(inventoryFilterProvider.notifier);
    final filter = ref.watch(inventoryFilterProvider);
    final lowCount = ref.watch(lowStockCountProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.sm,
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AlayaSearchField(
            onChanged: notifier.setQuery,
            clearLabel: strings.actionClearSearch,
            hintText: strings.hintSearchItems,
          ),
          const SizedBox(height: AlayaSpacing.xs),
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              FilterChip(
                label: Text(strings.filterFavouritesOnly),
                selected: filter.favouritesOnly,
                onSelected: (_) => notifier.toggleFavouritesOnly(),
              ),
              FilterChip(
                label: Text(
                  lowCount > 0
                      ? strings.lowStockWithCount(lowCount)
                      : strings.lowStockLabel,
                ),
                selected: filter.lowStockOnly,
                onSelected: (_) => notifier.toggleLowStockOnly(),
              ),
              FilterChip(
                label: Text(strings.groupByFavourites),
                selected: filter.groupBy == InventoryGroupBy.favourite,
                onSelected: (selected) => notifier.setGroupBy(
                  selected ? InventoryGroupBy.favourite : InventoryGroupBy.kind,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final filter = ref.watch(inventoryFilterProvider);
    final notifier = ref.read(inventoryFilterProvider.notifier);
    if (!filter.isNarrowed) return const SizedBox.shrink();

    return FilterChipBar(
      clearAllLabel: strings.filterReset,
      onClearAll: notifier.clear,
      filters: [
        if (filter.favouritesOnly)
          ActiveFilter(
            label: strings.filterFavouritesOnly,
            onRemove: notifier.toggleFavouritesOnly,
          ),
        if (filter.lowStockOnly)
          ActiveFilter(
            label: strings.lowStockLabel,
            onRemove: notifier.toggleLowStockOnly,
          ),
        if (filter.groupBy == InventoryGroupBy.favourite)
          ActiveFilter(
            label: strings.groupByFavourites,
            onRemove: () => notifier.setGroupBy(InventoryGroupBy.kind),
          ),
        for (final kind in filter.kinds)
          ActiveFilter(
            label: ItemKindLabel.of(strings, kind),
            onRemove: () => notifier.toggleKind(kind),
          ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.isSearching});

  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    if (isSearching) {
      return EmptyState(
        title: strings.emptyTitleNoResults,
        body: strings.emptyBodyNoResults,
        icon: Icons.search_off_outlined,
      );
    }
    return EmptyState(
      title: strings.emptyTitleNoItems,
      body: strings.emptyBodyNoItems,
      icon: Icons.inventory_2_outlined,
      actionLabel: strings.addItem,
      onAction: () => context.push(Routes.itemNew),
    );
  }
}

class _Sections extends ConsumerWidget {
  const _Sections({required this.sections});

  final List<InventoryGroup> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final stocks = ref.watch(itemStocksProvider).valueOrNull ?? const {};
    final today = ref.watch(clockProvider).today();

    return CustomScrollView(
      slivers: [
        for (final section in sections)
          SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: _GroupHeader(
                  label: section.isFavourites
                      ? strings.inventoryGroupFavourites
                      : section.kind == null
                      ? strings.inventoryGroupUntagged
                      : ItemKindLabel.of(strings, section.kind!),
                ),
              ),
              SliverList.builder(
                itemCount: section.items.length,
                itemBuilder: (context, index) {
                  final item = section.items[index];
                  return ItemRow(
                    item: item,
                    stock: stocks[item.id],
                    today: today,
                    onTap: () => context.push(Routes.itemDetail(item.id)),
                    onToggleFavourite: () async {
                      final ok = await ref
                          .read(itemActionsProvider)
                          .toggleFavourite(item);
                      if (!context.mounted || ok) return;
                      showFailureSnack(
                        context,
                        message: strings.errorBodyGeneric,
                      );
                    },
                  );
                },
              ),
            ],
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AlayaSpacing.xxxl)),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.md,
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
      ),
      child: Text(
        label,
        style: AlayaTypography.sectionHeader.copyWith(color: semantic.muted),
      ),
    );
  }
}

/// Resolves an [ItemKind] to its ARB label, so no screen in this feature writes the words.
abstract final class ItemKindLabel {
  /// The label for [kind].
  static String of(AlayaStrings strings, ItemKind kind) => switch (kind) {
    ItemKind.generic => strings.itemKindGeneric,
    ItemKind.food => strings.itemKindFood,
    ItemKind.medicine => strings.itemKindMedicine,
    ItemKind.beauty => strings.itemKindBeauty,
    ItemKind.household => strings.itemKindHousehold,
    ItemKind.other => strings.itemKindOther,
  };
}
