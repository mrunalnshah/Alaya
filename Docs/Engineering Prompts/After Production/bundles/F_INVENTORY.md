# F_INVENTORY

Items, batches, stock movements.

**24 files · 4,463 lines.**  Written 2026-08-27T08:54:37-04:00.

Every file below is complete and current. Paths are destinations.

---

### `lib/features/inventory/presentation/screens/batch_editor_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/providers/batch_editor_providers.dart';
import 'package:alaya/features/inventory/providers/item_detail_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/inventory/state/batch_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/qty_field.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// The batch editor (ARCH_5 §3 archetype B), routed outside the drawer shell (U18).
///
/// **Quantity is a field while creating and a read-only row while editing.** `remainingQuantity` is
/// the one cache the Laws permit (L3), reconciled from `stock_movements`; rewriting it from a form
/// would leave the cache and the ledger disagreeing with no movement to account for the difference.
/// Changing how much is left goes through the consume and adjust paths, which append movements.
class BatchEditorScreen extends ConsumerWidget {
  /// Edits [batchId] of [itemId], or adds a batch when [batchId] is null.
  const BatchEditorScreen({required this.itemId, this.batchId, super.key});

  /// Which item the batch belongs to.
  final String itemId;

  /// The batch being edited, or null for a new one.
  final String? batchId;

  BatchEditorArgs get _args => (itemId: itemId, batchId: batchId);

  Future<void> _delete(BuildContext context, WidgetRef ref, String id) async {
    final strings = AlayaStrings.of(context);
    // Consequential, not reversible (§5.5): `BatchRepository.delete` soft-deletes and the 3A
    // contract offers no restore, so the sheet names what leaves the on-hand total — and what does
    // not, because the movements stay (Law L6).
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.confirmDeleteBatchTitle,
      body: strings.confirmDeleteBatchBody,
      confirmLabel: strings.actionDeleteBatch,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await ref.read(itemActionsProvider).deleteBatch(id);
    if (!context.mounted) return;
    if (!ok) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.batchDeleted);
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(batchEditorProvider(_args).notifier).save();
    if (!context.mounted) return;
    if (saved == null) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.batchSaved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(batchEditorProvider(_args));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(
          batchId == null ? strings.actionAddBatch : strings.editorTitleEdit,
        ),
      ),
      body: async.when(
        loading: () =>
            AlayaListSkeleton(label: strings.loadingLabel, hasLeading: false),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleNotFound,
          body: strings.errorBodyNotFound,
        ),
        data: (state) => AlayaFormScaffold(
          primaryLabel: strings.saveBatch,
          onPrimary: state.submitting ? null : () => _save(context, ref),
          isDirty: state.dirty,
          isSubmitting: state.submitting,
          discardTitle: strings.confirmDiscardTitle,
          discardBody: strings.confirmDiscardBody,
          discardConfirmLabel: strings.actionDiscard,
          discardCancelLabel: strings.actionKeepEditing,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Form(args: _args, state: state),
              if (state.isEditing) ...[
                const SizedBox(height: AlayaSpacing.xxl),
                TextButton(
                  onPressed: () => _delete(context, ref, state.id!),
                  style: TextButton.styleFrom(
                    foregroundColor: context.semantic.danger,
                  ),
                  child: Text(strings.actionDeleteBatch),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.args, required this.state});

  final BatchEditorArgs args;
  final BatchEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(batchEditorProvider(args).notifier);
    final item = ref.watch(batchOwnerProvider(state.itemId)).valueOrNull;
    final currency = ref.watch(batchCurrencyProvider).valueOrNull;
    final digits = ref.watch(batchDecimalDigitsProvider).valueOrNull ?? 2;
    final units = item == null
        ? const <Unit>[]
        : ref.watch(unitsInCategoryProvider(item.unitCategory)).valueOrNull ??
              const <Unit>[];
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) =>
        DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());

    Unit? selected;
    for (final unit in units) {
      if (unit.code == state.unitCode) selected = unit;
    }
    final quantity = state.quantity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: strings.sectionHowMuch,
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
        ),
        if (!state.quantityEditable)
          KeyValueRow(
            label: strings.labelInitial,
            valueWidget: quantity == null ? null : QtyText(quantity),
            icon: Icons.lock_outline,
          )
        else if (item != null && units.isNotEmpty)
          ShakeOnError(
            trigger: state.shakeTrigger,
            child: QtyField(
              category: item.unitCategory,
              units: units,
              selectedUnit: selected ?? units.first,
              label: strings.labelQuantity,
              unitLabel: strings.labelUnit,
              initialValue: quantity,
              errorText: state.quantityMissing
                  ? strings.errorQuantityInvalid
                  : null,
              onChanged: notifier.setQuantity,
              onUnitChanged: (unit) => notifier.setUnitCode(unit.code),
            ),
          ),
        if (!state.quantityEditable)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AlayaSpacing.screenEdge,
            ),
            child: Text(
              strings.batchQuantityLockedHelp,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
          ),
        SectionHeader(
          label: strings.sectionBatchDetails,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.xl,
            bottom: AlayaSpacing.xs,
          ),
        ),
        DatePickerField(
          value: state.purchasedDateKey,
          formatted: format,
          label: strings.labelPurchased,
          hint: strings.hintSelectDate,
          onChanged: notifier.setPurchased,
        ),
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.expiryDateKey,
          formatted: format,
          label: strings.labelExpiry,
          hint: strings.hintSelectDate,
          onChanged: notifier.setExpiry,
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (currency != null)
          AmountField(
            currencyCode: currency,
            decimalDigits: digits,
            label: strings.labelUnitCost,
            initialValue: state.unitCost,
            onChanged: notifier.setUnitCost,
          ),
        const SizedBox(height: AlayaSpacing.md),
        TextFormField(
          initialValue: state.storageLocation,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: strings.labelStorageLocation,
            hintText: strings.hintStorageLocation,
          ),
          onChanged: notifier.setStorageLocation,
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextFormField(
          initialValue: state.note,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: strings.labelNote,
            hintText: strings.hintNote,
          ),
          onChanged: notifier.setNote,
        ),
      ],
    );
  }
}
```

### `lib/features/inventory/presentation/screens/batch_history_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/features/inventory/providers/batch_history_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_timeline.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';

/// One batch's movement timeline (ARCH_5 §3 archetype C), routed outside the drawer shell (U18).
///
/// **Nothing here can be edited, only reversed.** `stock_movements` is append-only (Law L6): a
/// correction is a new movement pointing back at the one it undoes, and the timeline strikes the
/// original through rather than removing it. Both rows stay, which is the only way the remaining
/// quantity a batch reports can be reconciled against the reasons it changed.
class BatchHistoryScreen extends ConsumerWidget {
  /// Shows the history of [batchId], which belongs to [itemId].
  const BatchHistoryScreen({
    required this.itemId,
    required this.batchId,
    super.key,
  });

  /// The owning item, carried so the route stays hierarchical.
  final String itemId;

  /// Which batch's movements to show.
  final String batchId;

  static String _kindLabel(AlayaStrings strings, StockMovementKind kind) =>
      switch (kind) {
        StockMovementKind.openingIn => strings.movementKindOpeningIn,
        StockMovementKind.purchaseIn => strings.movementKindPurchaseIn,
        StockMovementKind.manualIn => strings.movementKindManualIn,
        StockMovementKind.consume => strings.movementKindConsume,
        StockMovementKind.waste => strings.movementKindWaste,
        StockMovementKind.expired => strings.movementKindExpired,
        StockMovementKind.adjustIn => strings.movementKindAdjustIn,
        StockMovementKind.adjustOut => strings.movementKindAdjustOut,
      };

  Future<void> _reverse(
    BuildContext context,
    WidgetRef ref,
    String movementId,
  ) async {
    final strings = AlayaStrings.of(context);
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.confirmReverseTitle,
      body: strings.confirmReverseBody,
      confirmLabel: strings.actionReverse,
      cancelLabel: strings.actionCancel,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await ref.read(movementActionsProvider).reverse(movementId);
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.movementReversedSnack)
        : showFailureSnack(context, message: strings.errorBodyGeneric);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final movements = ref.watch(batchMovementsProvider(batchId));
    final reversed = ref.watch(reversedMovementIdsProvider(batchId));

    return Scaffold(
      appBar: AppBar(title: Text(strings.historyTitle)),
      body: movements.when(
        loading: () => AlayaListSkeleton(label: strings.loadingInventory),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: strings.errorBodyGeneric,
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(batchMovementsProvider(batchId)),
        ),
        data: (rows) => rows.isEmpty
            ? EmptyState(
                title: strings.emptyTitleNoMovements,
                body: strings.emptyBodyNoMovements,
                icon: Icons.history,
              )
            : CustomScrollView(
                slivers: [
                  AlayaTimeline(
                    itemCount: rows.length,
                    itemBuilder: (context, index) => _entryFor(
                      context: context,
                      ref: ref,
                      strings: strings,
                      movement: rows[index],
                      isReversed: reversed.contains(rows[index].id),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AlayaSpacing.xxxl),
                  ),
                ],
              ),
      ),
    );
  }

  AlayaTimelineEntry _entryFor({
    required BuildContext context,
    required WidgetRef ref,
    required AlayaStrings strings,
    required StockMovement movement,
    required bool isReversed,
  }) {
    final isReversal = movement.reversesMovementId != null;
    final tone = isReversed
        ? TimelineTone.superseded
        : movement.isIncoming
        ? TimelineTone.incoming
        : TimelineTone.outgoing;

    return AlayaTimelineEntry(
      title: _kindLabel(strings, movement.kind),
      trailing: QtyText(movement.quantity, muted: isReversed),
      subtitle: DateText(
        movement.dateKey,
        style: DateTextStyle.medium,
        muted: true,
      ),
      meta: movement.reason ?? movement.note,
      icon: movement.isIncoming ? Icons.south_west : Icons.north_east,
      tone: tone,
      badge: isReversed
          ? strings.movementReversed
          : isReversal
          ? strings.movementIsReversal
          : null,
      onTap: isReversed || isReversal
          ? null
          : () => _reverse(context, ref, movement.id),
    );
  }
}
```

### `lib/features/inventory/presentation/screens/inventory_list_screen.dart`

```dart
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
```

### `lib/features/inventory/presentation/screens/item_detail_screen.dart`

```dart
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
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:alaya/features/inventory/presentation/sheets/consume_sheet.dart';
import 'package:alaya/features/inventory/presentation/widgets/batch_card.dart';
import 'package:alaya/features/inventory/providers/item_detail_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One item in full (ARCH_5 §3 archetype E), routed outside the drawer shell (U18).
///
/// **The hero is the summed mixed-unit total.** That is the question someone opens this screen with —
/// "how much flour do I have" — and the answer is `4 kg 450 g`, one figure across every batch
/// (ARCH_1 §5.4). The batches that make it up are listed underneath with their expiries, because
/// every operation acts on a batch even though the headline is a sum.
class ItemDetailScreen extends ConsumerWidget {
  /// Shows the item with [itemId].
  const ItemDetailScreen({required this.itemId, super.key});

  /// Which item to show.
  final String itemId;

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    int batchCount,
  ) async {
    final strings = AlayaStrings.of(context);
    // Consequential rather than reversible (§5.5): `ItemRepository.delete` cascades to the batches
    // and there is no restore path in the 3A contract, so the sheet names what goes with it.
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.confirmDeleteItemTitle,
      body: strings.confirmDeleteItemBody(batchCount),
      confirmLabel: strings.actionDeleteItem,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await ref.read(itemActionsProvider).delete(itemId);
    if (!context.mounted) return;
    if (!ok) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.itemDeleted);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(itemByIdProvider(itemId));

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.navInventory),
        actions: [
          IconButton(
            onPressed: () => context.push(Routes.itemEdit(itemId)),
            tooltip: strings.actionEdit,
            icon: const Icon(Icons.edit_outlined, size: AlayaIconSize.lg),
          ),
        ],
      ),
      body: async.when(
        loading: () => AlayaListSkeleton(
          label: strings.loadingInventory,
          hasLeading: false,
        ),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: strings.errorBodyGeneric,
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(itemByIdProvider(itemId)),
        ),
        data: (item) => item == null
            ? EmptyState(
                title: strings.errorTitleNotFound,
                body: strings.errorBodyNotFound,
                icon: Icons.search_off_outlined,
              )
            : _Body(
                item: item,
                onDelete: (count) => _delete(context, ref, count),
              ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.item, required this.onDelete});

  final Item item;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final today = ref.watch(clockProvider).today();
    final stock = ref.watch(itemStockProvider(item.id)).valueOrNull;
    final batches = ref.watch(itemBatchesProvider(item.id));
    final units = ref.watch(detailUnitsByCodeProvider).valueOrNull ?? const {};
    final threshold = item.lowStockThreshold;
    final notifyDays = item.expiryNotifyDays;

    // `CustomScrollView`, not `ListView(children: [...])`. The batch list is fed by a repository
    // stream, and U13 admits no row-count exemption — a well-stocked item genuinely has dozens of
    // batches, so it is a `SliverList.builder` and the fixed sections around it are adapters.
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
            child: AlayaCard(
              tier: 2,
              padding: const EdgeInsets.all(AlayaSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: AlayaTypography.cardTitle.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (item.isFavorite)
                        Icon(
                          Icons.star,
                          size: AlayaIconSize.md,
                          color: semantic.warning,
                        ),
                    ],
                  ),
                  const SizedBox(height: AlayaSpacing.sm),
                  if (stock != null)
                    QtyText(stock.totalRemaining)
                  else
                    Text(
                      strings.loadingLabel,
                      style: AlayaTypography.caption.copyWith(
                        color: semantic.muted,
                      ),
                    ),
                  if (stock != null) ...[
                    const SizedBox(height: AlayaSpacing.sm),
                    Wrap(
                      spacing: AlayaSpacing.xs,
                      runSpacing: AlayaSpacing.xs,
                      children: [
                        if (stock.isOutOfStock)
                          StatusChip(label: strings.outOfStockLabel)
                        else if (stock.isLowStock)
                          StatusChip(
                            label: strings.lowStockLabel,
                            tone: StatusTone.warning,
                          ),
                        if (stock.hasExpiredStock(today))
                          StatusChip(
                            label: strings.expiredLabel,
                            tone: StatusTone.danger,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AlayaSpacing.screenEdge,
            ),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (stock?.isOutOfStock ?? true)
                        ? null
                        : () => ConsumeSheet.show(
                            context,
                            itemId: item.id,
                            unitCode: item.defaultDisplayUnitCode,
                            category: item.unitCategory,
                          ),
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      size: AlayaIconSize.md,
                    ),
                    label: Text(strings.actionConsume),
                  ),
                ),
                const SizedBox(width: AlayaSpacing.xs),
                IconButton.filledTonal(
                  onPressed: () => context.push(Routes.batchNew(item.id)),
                  tooltip: strings.actionAddBatch,
                  icon: const Icon(Icons.add, size: AlayaIconSize.md),
                ),
              ],
            ),
          ),
        ),
        SliverList.list(
          children: [
            SectionHeader(label: strings.detailSectionDetails),
            KeyValueRow(
              label: strings.labelItemKind,
              value: ItemKindLabel.of(strings, item.itemKind),
            ),
            KeyValueRow(
              label: strings.labelDisplayUnit,
              value: units[item.defaultDisplayUnitCode]?.displayName,
            ),
            KeyValueRow(
              label: strings.labelLowStockThreshold,
              valueWidget: threshold == null
                  ? null
                  : QtyText(threshold, muted: true),
            ),
            KeyValueRow(
              label: strings.labelExpiryNotifyDays,
              value: notifyDays == null ? null : strings.daysCount(notifyDays),
            ),
            KeyValueRow(
              label: strings.labelNearestExpiry,
              valueWidget: stock?.nearestExpiry == null
                  ? null
                  : DateText(
                      stock!.nearestExpiry!,
                      style: DateTextStyle.medium,
                    ),
            ),
            KeyValueRow(label: strings.labelNote, value: item.notes),
            SectionHeader(label: strings.detailSectionBatches),
          ],
        ),
        batches.when(
          loading: () => SliverToBoxAdapter(
            child: AlayaListSkeleton(label: strings.loadingInventory, rows: 2),
          ),
          error: (error, stack) => SliverToBoxAdapter(
            child: ErrorState(
              title: strings.errorTitleGeneric,
              body: strings.errorBodyGeneric,
            ),
          ),
          data: (rows) => rows.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AlayaSpacing.screenEdge,
                      vertical: AlayaSpacing.xs,
                    ),
                    child: Text(
                      strings.emptyBodyNoBatches,
                      style: AlayaTypography.caption.copyWith(
                        color: semantic.muted,
                      ),
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AlayaSpacing.screenEdge,
                  ),
                  sliver: SliverList.separated(
                    itemCount: rows.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: AlayaSpacing.xs),
                    itemBuilder: (context, index) {
                      final batch = rows[index];
                      return BatchCard(
                        batch: batch,
                        today: today,
                        onTap: () =>
                            context.push(Routes.batchEdit(item.id, batch.id)),
                        onHistory: () => context.push(
                          Routes.batchHistory(item.id, batch.id),
                        ),
                      );
                    },
                  ),
                ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AlayaSpacing.screenEdge,
              AlayaSpacing.xxl,
              AlayaSpacing.screenEdge,
              AlayaSpacing.xxxl,
            ),
            child: TextButton(
              onPressed: () => onDelete(_batchCountOf(batches)),
              style: TextButton.styleFrom(foregroundColor: semantic.danger),
              child: Text(strings.actionDeleteItem),
            ),
          ),
        ),
      ],
    );
  }

  static int _batchCountOf(AsyncValue<List<Batch>> batches) =>
      batches.valueOrNull?.length ?? 0;
}
```

### `lib/features/inventory/presentation/screens/item_editor_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/inventory/state/item_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_disclosure.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/qty_field.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';
import 'package:alaya/shared/widgets/unit_picker.dart';

/// The item editor (ARCH_5 §3 archetype B), routed outside the drawer shell (U18).
///
/// **`unitCategory` is a control while creating and a read-only row while editing.** Law L8 makes it
/// immutable after creation, and the row says why rather than leaving the user to discover that a
/// disabled dropdown exists: every batch and movement already recorded is stored in that measure, and
/// there is no conversion between weight, volume and count. Offering the control and then refusing
/// the change would be worse than not offering it.
class ItemEditorScreen extends ConsumerWidget {
  /// Edits [itemId], or creates a new item when it is null.
  const ItemEditorScreen({this.itemId, super.key});

  /// The item being edited, or null for a new one.
  final String? itemId;

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(itemEditorProvider(itemId).notifier).save();
    if (!context.mounted) return;
    if (saved == null) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.actionSaved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(itemEditorProvider(itemId));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(
          itemId == null ? strings.editorTitleNew : strings.editorTitleEdit,
        ),
      ),
      body: async.when(
        loading: () =>
            AlayaListSkeleton(label: strings.loadingLabel, hasLeading: false),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleNotFound,
          body: strings.errorBodyNotFound,
        ),
        data: (state) => AlayaFormScaffold(
          primaryLabel: strings.saveItem,
          onPrimary: state.submitting ? null : () => _save(context, ref),
          isDirty: state.dirty,
          isSubmitting: state.submitting,
          discardTitle: strings.confirmDiscardTitle,
          discardBody: strings.confirmDiscardBody,
          discardConfirmLabel: strings.actionDiscard,
          discardCancelLabel: strings.actionKeepEditing,
          child: _Form(editorId: itemId, state: state),
        ),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.editorId, required this.state});

  final String? editorId;
  final ItemEditorState state;

  static String _categoryLabel(AlayaStrings strings, UnitCategory category) =>
      switch (category) {
        UnitCategory.weight => strings.unitCategoryWeight,
        UnitCategory.volume => strings.unitCategoryVolume,
        UnitCategory.count => strings.unitCategoryCount,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(itemEditorProvider(editorId).notifier);
    final units =
        ref.watch(unitsInCategoryProvider(state.unitCategory)).valueOrNull ??
        const <Unit>[];
    Unit? selected;
    Unit? thresholdUnit;
    for (final unit in units) {
      if (unit.code == state.displayUnitCode) selected = unit;
      if (unit.code == state.thresholdUnitCode) thresholdUnit = unit;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.issue != null) ...[
          _IssueBanner(state: state),
          const SizedBox(height: AlayaSpacing.md),
        ],
        SectionHeader(
          label: strings.sectionWhatItIs,
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
        ),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: TextFormField(
            initialValue: state.name,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: strings.labelItem,
              errorText: state.nameMissing ? strings.errorFieldRequired : null,
            ),
            onChanged: notifier.setName,
            onEditingComplete: notifier.refreshSimilar,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        DropdownButtonFormField<ItemKind>(
          key: ValueKey(state.itemKind),
          initialValue: state.itemKind,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.labelItemKind),
          items: [
            for (final kind in ItemKind.values)
              DropdownMenuItem(
                value: kind,
                child: Text(ItemKindLabel.of(strings, kind)),
              ),
          ],
          onChanged: (value) => value == null ? null : notifier.setKind(value),
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (state.isEditing) ...[
          KeyValueRow(
            label: strings.labelCategory,
            value: strings.unitCategoryLocked(
              _categoryLabel(strings, state.unitCategory),
            ),
            icon: Icons.lock_outline,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AlayaSpacing.screenEdge,
            ),
            child: Text(
              strings.unitCategoryLockedHelp,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
          ),
        ] else
          DropdownButtonFormField<UnitCategory>(
            key: ValueKey(state.unitCategory),
            initialValue: state.unitCategory,
            isExpanded: true,
            decoration: InputDecoration(labelText: strings.labelCategory),
            items: [
              for (final category in UnitCategory.values)
                DropdownMenuItem(
                  value: category,
                  child: Text(_categoryLabel(strings, category)),
                ),
            ],
            onChanged: (value) => value == null
                ? null
                : notifier.setCategory(value, value.baseUnitCode),
          ),
        if (state.similarInOtherMeasures.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            strings.itemSimilarNote,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ],
        const SizedBox(height: AlayaSpacing.md),
        UnitPicker(
          category: state.unitCategory,
          units: units,
          selected: selected,
          label: strings.labelDisplayUnit,
          onChanged: notifier.setDisplayUnit,
        ),
        AlayaDisclosure(
          label: strings.sectionMoreDetails,
          summary: _itemSummary(strings, state),
          startExpanded: _hasItemDetails(state),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                label: strings.sectionStockRules,
                padding: const EdgeInsets.only(
                  top: AlayaSpacing.xl,
                  bottom: AlayaSpacing.xs,
                ),
              ),
              if (units.isNotEmpty)
                QtyField(
                  category: state.unitCategory,
                  units: units,
                  selectedUnit: thresholdUnit ?? selected ?? units.first,
                  label: strings.labelLowStockThreshold,
                  unitLabel: strings.labelUnit,
                  initialValue: state.lowStockThreshold,
                  onChanged: notifier.setThreshold,
                  onUnitChanged: notifier.setThresholdUnit,
                ),
              const SizedBox(height: AlayaSpacing.md),
              TextFormField(
                initialValue: state.expiryNotifyDays?.toString(),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: strings.labelExpiryNotifyDays,
                  helperText: strings.expiryNotifyDaysHelp,
                ),
                onChanged: (raw) =>
                    notifier.setExpiryNotifyDays(int.tryParse(raw.trim())),
              ),

              // Only for items measured by weight. The field converts a *volume* into grams, so on an item
              // already kept in millilitres there is nothing to convert and it would be noise.
              if (state.unitCategory == UnitCategory.weight) ...[
                SectionHeader(
                  label: strings.sectionRecipeMeasures,
                  padding: const EdgeInsets.only(
                    top: AlayaSpacing.xl,
                    bottom: AlayaSpacing.xs,
                  ),
                ),
                TextFormField(
                  // **Asked as "one tablespoon weighs", not "one millilitre weighs".** The column stores a
                  // density either way, but nobody can estimate the density of flour and everybody can look
                  // up that a tablespoon of it is about 8 g — which is how every cooking table is written.
                  //
                  // One number still covers every volume unit: 8 g/tbsp derives 2.7 g/tsp and 130 g/cup. A
                  // per-unit table would need three rows per ingredient and would let tsp and tbsp disagree
                  // about the same substance.
                  initialValue: _gramsPerTbspText(state.densityMilliGramsPerMl),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: strings.labelGramsPerTbsp,
                    helperText: strings.gramsPerTbspHelp,
                    suffixText: strings.suffixGrams,
                  ),
                  onChanged: (raw) =>
                      notifier.setDensity(_densityFromTbsp(raw)),
                ),
                const SizedBox(height: AlayaSpacing.md),
                TextFormField(
                  initialValue: _gramsText(state.milliGramsPerPiece),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: strings.labelPieceWeight,
                    helperText: strings.pieceWeightHelp,
                    suffixText: strings.suffixGrams,
                  ),
                  onChanged: (raw) => notifier.setPieceWeight(_milliGrams(raw)),
                ),
              ],
              const SizedBox(height: AlayaSpacing.xs),
              SwitchListTile(
                value: state.isFavorite,
                contentPadding: EdgeInsets.zero,
                title: Text(strings.labelFavourite),
                secondary: Icon(
                  state.isFavorite ? Icons.star : Icons.star_outline,
                  size: AlayaIconSize.md,
                  color: state.isFavorite ? semantic.warning : semantic.muted,
                ),
                onChanged: (_) => notifier.toggleFavourite(),
              ),
              SectionHeader(
                label: strings.labelNote,
                padding: const EdgeInsets.only(
                  top: AlayaSpacing.xl,
                  bottom: AlayaSpacing.xs,
                ),
              ),
              TextFormField(
                initialValue: state.notes,
                maxLines: 3,
                decoration: InputDecoration(hintText: strings.hintNote),
                onChanged: notifier.setNotes,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Whether anything behind the door is set, so it should open on arrival.
  ///
  /// **A recipe measure counts.** It is usually the reason somebody opened this screen at all — a recipe
  /// told them their spoon amount could not be converted — and collapsing the number they came here to
  /// set would be the worst possible moment to hide it.
  static bool _hasItemDetails(ItemEditorState state) =>
      state.lowStockThreshold != null ||
      state.expiryNotifyDays != null ||
      state.densityMilliGramsPerMl != null ||
      state.milliGramsPerPiece != null ||
      state.isFavorite ||
      (state.notes ?? '').trim().isNotEmpty;

  /// What is set behind the door, for the collapsed row.
  static String? _itemSummary(AlayaStrings strings, ItemEditorState state) {
    final parts = <String>[];
    if (state.lowStockThreshold != null) parts.add(strings.sectionStockRules);
    if (state.densityMilliGramsPerMl != null ||
        state.milliGramsPerPiece != null) {
      parts.add(strings.sectionRecipeMeasures);
    }
    if (state.isFavorite) parts.add(strings.labelFavourite);
    if ((state.notes ?? '').trim().isNotEmpty) parts.add(strings.labelNote);
    return parts.isEmpty ? null : parts.join(' \u00B7 ');
  }
}

class _IssueBanner extends ConsumerWidget {
  const _IssueBanner({required this.state});

  final ItemEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final conflictId = state.conflictItemId;

    final message = switch (state.issue) {
      ItemSaveIssue.duplicate => strings.itemDuplicateBody,
      ItemSaveIssue.unitsMissing => strings.itemUnitsMissingBody,
      ItemSaveIssue.unknown || null => strings.errorBodyGeneric,
    };

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: AlayaIconSize.md,
            color: semantic.danger,
          ),
          const SizedBox(width: AlayaSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: AlayaTypography.body.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                // The duplicate case is the only one with somewhere useful to go: the item they
                // already have. Offering to open it beats making them back out and search for it.
                if (state.issue == ItemSaveIssue.duplicate &&
                    conflictId != null) ...[
                  const SizedBox(height: AlayaSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => context.pushReplacement(
                        Routes.itemDetail(conflictId),
                      ),
                      child: Text(strings.actionOpenExisting),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One tablespoon in milli-millilitres, matching the seeded `tbsp` unit's `factorToBaseMilli`.
///
/// Duplicated from the seed deliberately: this file cannot read the units table synchronously while
/// building a text field, and a field that silently disagreed with the unit picker would be worse than
/// a constant with a comment saying where it came from.
const int _tbspMilliMl = 14787;

/// Renders a stored density as the grams-per-tablespoon a person typed.
///
/// `541` shows as `8`, because 541 milli-grams per millilitre times 14.787 ml is 8.00 g. A field that
/// reads back what you entered is the minimum for trusting it.
String? _gramsPerTbspText(int? milliGramsPerMl) {
  if (milliGramsPerMl == null) return null;
  return _gramsText(milliGramsPerMl * _tbspMilliMl ~/ 1000);
}

/// Parses typed grams-per-tablespoon into a stored density, or null for anything unusable.
int? _densityFromTbsp(String raw) {
  final milliGrams = _milliGrams(raw);
  if (milliGrams == null) return null;
  // Multiply before dividing so the integer arithmetic keeps its precision (Law L1).
  return milliGrams * 1000 ~/ _tbspMilliMl;
}

/// Renders milli-grams as the grams a person typed, or null for an empty field.
String? _gramsText(int? milliGrams) {
  if (milliGrams == null) return null;
  if (milliGrams % 1000 == 0) return '${milliGrams ~/ 1000}';
  return (milliGrams / 1000).toString();
}

/// Parses typed grams into milli-grams, or null for anything unusable.
///
/// Integer arithmetic on the decimal string rather than `double.parse`: `0.1` has no exact binary
/// representation, and Law L1 keeps quantities exact end to end. An empty or malformed field returns
/// null, which is a real state — it clears the value rather than storing a zero that would claim a
/// tablespoon of this weighs nothing.
int? _milliGrams(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final parts = text.split('.');
  if (parts.length > 2) return null;
  final whole = int.tryParse(parts.first.isEmpty ? '0' : parts.first);
  if (whole == null) return null;
  if (parts.length == 1) return whole * 1000;
  if (parts[1].length > 3) return null;
  final fraction = int.tryParse(parts[1].padRight(3, '0'));
  if (fraction == null) return null;
  return whole * 1000 + fraction;
}
```

### `lib/features/inventory/presentation/sheets/consume_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/providers/consume_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/inventory/state/consume_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/qty_field.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Takes stock off an item (ARCH_5 §3 archetype A).
///
/// **FEFO is pre-selected and named, not silent.** The sheet says which batch it will draw from and
/// offers the alternatives as chips, because "use some flour" and "use the jar that expires on
/// Tuesday" are the same gesture to the user and completely different rows in the ledger.
///
/// **A consume that spans batches says so before committing.** The preview walks the same FEFO
/// ordering the repository does and reports how many movements the write will append, so a user who
/// takes 3 kg from three 1 kg jars is told three entries are coming rather than discovering it in the
/// history afterwards.
///
/// Used, thrown away and expired are three distinct `StockMovementKind`s rather than one kind with a
/// reason, because Phase 7B's waste insight aggregates on the column and cannot read prose.
class ConsumeSheet extends ConsumerWidget {
  /// Creates the sheet.
  const ConsumeSheet({
    required this.itemId,
    required this.unitCode,
    required this.category,
    super.key,
  });

  /// Which item is being drawn down.
  final String itemId;

  /// The unit the quantity field starts in.
  final String unitCode;

  /// The item's measure, so the unit picker never offers a cross-category unit (Law L8).
  final UnitCategory category;

  /// Opens the sheet.
  static Future<void> show(
    BuildContext context, {
    required String itemId,
    required String unitCode,
    required UnitCategory category,
  }) => AlayaBottomSheet.show<void>(
    context: context,
    builder: (context) => ConsumeSheet(
      itemId: itemId,
      unitCode: unitCode,
      category: category,
    ),
  );

  static String _kindChipLabel(AlayaStrings strings, StockMovementKind kind) =>
      switch (kind) {
        StockMovementKind.waste => strings.consumeKindWaste,
        StockMovementKind.expired => strings.consumeKindExpired,
        _ => strings.consumeKindConsume,
      };

  static String _commitLabel(AlayaStrings strings, StockMovementKind kind) =>
      switch (kind) {
        StockMovementKind.waste => strings.consumeCommitWaste,
        StockMovementKind.expired => strings.consumeCommitExpired,
        _ => strings.consumeCommitUsed,
      };

  Future<void> _commit(
    BuildContext context,
    WidgetRef ref,
    ConsumeArgs args,
  ) async {
    final strings = AlayaStrings.of(context);
    final written = await ref.read(consumeProvider(args).notifier).commit();
    if (!context.mounted) return;
    if (written == null) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    Navigator.of(context).pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.consumeRecorded);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final args = (itemId: itemId, unitCode: unitCode);
    final state = ref.watch(consumeProvider(args));
    final notifier = ref.read(consumeProvider(args).notifier);
    final fefo = ref.watch(consumeFefoProvider(itemId));
    final units =
        ref.watch(unitsInCategoryProvider(category)).valueOrNull ??
        const <Unit>[];

    Unit? selected;
    for (final unit in units) {
      if (unit.code == state.unitCode) selected = unit;
    }

    final batches = fefo.valueOrNull ?? const <Batch>[];
    final plan = state.planAgainst(batches);
    final shortfall = state.shortfallAgainst(batches);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.consumeTitle,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (units.isNotEmpty)
          ShakeOnError(
            trigger: state.shakeTrigger,
            child: QtyField(
              category: category,
              units: units,
              selectedUnit: selected ?? units.first,
              label: strings.labelQuantity,
              unitLabel: strings.labelUnit,
              initialValue: state.quantity,
              errorText: state.quantityMissing
                  ? strings.errorQuantityInvalid
                  : shortfall != null
                  ? strings.consumeOverAvailable
                  : null,
              onChanged: notifier.setQuantity,
              onUnitChanged: (unit) => notifier.setUnitCode(unit.code),
            ),
          ),
        const SizedBox(height: AlayaSpacing.md),
        // **Chips above 1.5x, a segmented button below it.** `SegmentedButton` lays its segments out
        // in a Row that cannot wrap, so three labels at a doubled text scale overflow 320dp by about
        // 50px. A `Wrap` of `ChoiceChip`s is the same choice with the same semantics and reflows
        // instead of clipping (Law U15).
        if (MediaQuery.textScalerOf(context).scale(1) >= 1.5)
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              for (final option in const [
                StockMovementKind.consume,
                StockMovementKind.waste,
                StockMovementKind.expired,
              ])
                ChoiceChip(
                  selected: state.kind == option,
                  onSelected: (_) => notifier.setKind(option),
                  label: Text(_kindChipLabel(strings, option)),
                ),
            ],
          )
        else
          SegmentedButton<StockMovementKind>(
            segments: [
              ButtonSegment(
                value: StockMovementKind.consume,
                label: Text(strings.consumeKindConsume),
              ),
              ButtonSegment(
                value: StockMovementKind.waste,
                label: Text(strings.consumeKindWaste),
              ),
              ButtonSegment(
                value: StockMovementKind.expired,
                label: Text(strings.consumeKindExpired),
              ),
            ],
            selected: {state.kind},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                notifier.setKind(selection.first),
          ),
        const SizedBox(height: AlayaSpacing.md),
        _BatchChips(
          batches: batches,
          state: state,
          plan: plan,
          onPick: notifier.setBatch,
        ),
        if (plan.length > 1 || (plan.length == 1 && !state.isOverridden)) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusChip(
              label: strings.consumeSpansBatches(plan.length),
              tone: plan.length > 1 ? StatusTone.info : StatusTone.neutral,
            ),
          ),
        ],
        if (state.kind != StockMovementKind.consume) ...[
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.reason,
            decoration: InputDecoration(
              labelText: strings.labelNote,
              hintText: strings.deleteReasonHint,
            ),
            onChanged: notifier.setReason,
          ),
        ],
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          // Blocked rather than warned (§5.5): the repository would refuse a draw larger than the
          // batches hold, and a button that fails on press teaches the user the app is unreliable.
          onPressed: state.submitting || shortfall != null
              ? null
              : () => _commit(context, ref, args),
          // States the action rather than "Record" (U14), and does it from one ARB key per kind so no
          // separator glyph is glued on in code.
          child: Text(_commitLabel(strings, state.kind)),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.actionCancel),
        ),
        if (fefo.hasError)
          Padding(
            padding: const EdgeInsets.only(top: AlayaSpacing.xs),
            child: Text(
              strings.errorBodyGeneric,
              style: AlayaTypography.caption.copyWith(color: semantic.danger),
            ),
          ),
      ],
    );
  }
}

class _BatchChips extends StatelessWidget {
  const _BatchChips({
    required this.batches,
    required this.state,
    required this.plan,
    required this.onPick,
  });

  final List<Batch> batches;
  final ConsumeState state;
  final List<ConsumePlanLeg> plan;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    if (batches.isEmpty) return const SizedBox.shrink();

    final fefoId = plan.isEmpty ? batches.first.id : plan.first.batch.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.consumeFromLabel,
          style: AlayaTypography.label.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final batch in batches)
              ChoiceChip(
                selected: state.isOverridden
                    ? state.overrideBatchId == batch.id
                    : batch.id == fefoId,
                onSelected: (_) =>
                    onPick(state.overrideBatchId == batch.id ? null : batch.id),
                label: _BatchChipLabel(batch: batch),
              ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        Text(
          strings.consumeFefoNote,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
      ],
    );
  }
}

class _BatchChipLabel extends StatelessWidget {
  const _BatchChipLabel({required this.batch});

  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final expiry = batch.expiryDateKey;
    // A `Wrap`, not a `Row`. A chip constrains its label, and at a doubled text scale a quantity plus
    // a date is about 50px wider than the chip allows — the last overflow left in this sheet after the
    // segmented button was fixed (Law U21).
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AlayaSpacing.xxs,
      children: [
        QtyText(batch.remainingQuantity),
        if (expiry != null)
          DateText(expiry, style: DateTextStyle.dayMonth, muted: true),
      ],
    );
  }
}
```

### `lib/features/inventory/presentation/widgets/batch_card.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One batch on the item detail screen: what is left, when it expires, where it came from.
///
/// **`origin == detached` gets a chip that explains itself.** A batch becomes detached when the
/// purchase that created it is deleted — the stock is genuinely still in the cupboard, so it is not
/// removed, but its receipt is gone and the cost figure behind it can no longer be traced. Without
/// the chip the user sees a batch with no source and assumes the app lost it.
class BatchCard extends StatelessWidget {
  /// Creates the card.
  const BatchCard({
    required this.batch,
    required this.today,
    required this.onTap,
    this.onHistory,
    super.key,
  });

  /// The batch.
  final Batch batch;

  /// Today, for expiry wording.
  final DateKey today;

  /// Opens the batch editor.
  final VoidCallback onTap;

  /// Opens the movement history.
  final VoidCallback? onHistory;

  static String _originLabel(AlayaStrings strings, BatchOrigin origin) =>
      switch (origin) {
        BatchOrigin.purchase => strings.batchOriginPurchase,
        BatchOrigin.manual => strings.batchOriginManual,
        BatchOrigin.imported => strings.batchOriginImported,
        BatchOrigin.adjustment => strings.batchOriginAdjustment,
        BatchOrigin.detached => strings.statusDetached,
      };

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final days = batch.daysUntilExpiry(today);
    final location = batch.storageLocation;

    return AlayaCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AlayaSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: QtyText(
                  batch.remainingQuantity,
                  muted: batch.isExhausted,
                ),
              ),
              if (onHistory != null)
                IconButton(
                  onPressed: onHistory,
                  tooltip: strings.actionViewHistory,
                  icon: const Icon(Icons.history, size: AlayaIconSize.md),
                ),
            ],
          ),
          if (days != null) ...[
            const SizedBox(height: AlayaSpacing.xxs),
            Text(
              days < 0
                  ? strings.expiredDaysAgo(-days)
                  : strings.expiresInDays(days),
              style: AlayaTypography.caption.copyWith(
                color: days < 0 ? semantic.danger : semantic.muted,
              ),
            ),
          ],
          const SizedBox(height: AlayaSpacing.xxs),
          DateText(
            batch.purchasedDateKey,
            style: DateTextStyle.medium,
            muted: true,
          ),
          if (location != null && location.isNotEmpty) ...[
            const SizedBox(height: AlayaSpacing.xxs),
            Text(
              location,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
          ],
          const SizedBox(height: AlayaSpacing.xs),
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              StatusChip(
                label: _originLabel(strings, batch.origin),
                tone: batch.origin == BatchOrigin.detached
                    ? StatusTone.warning
                    : StatusTone.neutral,
                icon: batch.origin == BatchOrigin.detached
                    ? Icons.link_off
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

### `lib/features/inventory/presentation/widgets/item_row.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One catalogue row: identity, the number that matters, and a chip when abnormal (§3 archetype D).
///
/// **The figure is the summed mixed-unit total** — `4 kg 450 g`, not a batch count and not the
/// largest batch. `ItemStock.totalRemaining` is already the sum, so the row renders it through
/// `QtyText` and never adds anything itself (ARCH_1 §5.4, U7). Individual batches with their
/// expiries live one tap down on the detail screen.
///
/// The row stacks above roughly 1.5x text scale. A quantity like `4 kg 450 g` takes its full natural
/// width when it is not flexible, which starves the name beside it; the same shape overflowed a
/// transaction row and a nudge banner in Phase 6A, and clipping a quantity is as misleading as
/// clipping an amount (U15).
class ItemRow extends StatelessWidget {
  /// Creates the row.
  const ItemRow({
    required this.item,
    required this.stock,
    required this.today,
    required this.onTap,
    this.onToggleFavourite,
    super.key,
  });

  /// The item.
  final Item item;

  /// Its stock on hand, or null while the stock stream is still catching up.
  final ItemStock? stock;

  /// Today, for expiry comparisons.
  final DateKey today;

  /// Opens the detail screen.
  final VoidCallback onTap;

  /// Stars or unstars the item.
  final VoidCallback? onToggleFavourite;

  static IconData _glyphFor(ItemKind kind) => switch (kind) {
    ItemKind.food => Icons.restaurant_outlined,
    ItemKind.medicine => Icons.medication_outlined,
    ItemKind.beauty => Icons.spa_outlined,
    ItemKind.household => Icons.cleaning_services_outlined,
    ItemKind.generic || ItemKind.other => Icons.inventory_2_outlined,
  };

  List<Widget> _chips(BuildContext context, AlayaStrings strings) {
    final current = stock;
    if (current == null) return const [];
    final chips = <Widget>[];
    if (current.isOutOfStock) {
      chips.add(StatusChip(label: strings.outOfStockLabel));
    } else if (current.isLowStock) {
      chips.add(
        StatusChip(label: strings.lowStockLabel, tone: StatusTone.warning),
      );
    }
    final days = current.daysUntilNearestExpiry(today);
    if (days != null && !current.isOutOfStock) {
      if (days < 0) {
        chips.add(
          StatusChip(label: strings.expiredLabel, tone: StatusTone.danger),
        );
      } else if (days <= _soonDays) {
        chips.add(
          StatusChip(
            label: strings.expiringSoonLabel,
            tone: StatusTone.warning,
          ),
        );
      }
    }
    return chips;
  }

  static const int _soonDays = 7;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final current = stock;
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final chips = _chips(context, strings);

    final quantity = current == null
        ? const SizedBox.shrink()
        : QtyText(
            current.totalRemaining,
            muted: current.isOutOfStock,
            textAlign: stacked ? TextAlign.start : TextAlign.end,
          );

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlayaSpacing.screenEdge,
            vertical: AlayaSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _glyphFor(item.itemKind),
                size: AlayaIconSize.lg,
                color: semantic.muted,
              ),
              const SizedBox(width: AlayaSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: AlayaTypography.body.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (current != null && current.batchCount > 0) ...[
                      const SizedBox(height: AlayaSpacing.xxs),
                      Text(
                        strings.itemBatchCount(current.batchCount),
                        style: AlayaTypography.caption.copyWith(
                          color: semantic.muted,
                        ),
                      ),
                    ],
                    if (stacked) ...[
                      const SizedBox(height: AlayaSpacing.xs),
                      quantity,
                    ],
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: AlayaSpacing.xs),
                      Wrap(
                        spacing: AlayaSpacing.xs,
                        runSpacing: AlayaSpacing.xs,
                        children: chips,
                      ),
                    ],
                  ],
                ),
              ),
              if (!stacked) ...[
                const SizedBox(width: AlayaSpacing.sm),
                quantity,
              ],
              if (onToggleFavourite != null)
                IconButton(
                  onPressed: onToggleFavourite,
                  tooltip: item.isFavorite
                      ? strings.actionUnfavourite
                      : strings.actionFavourite,
                  icon: Icon(
                    item.isFavorite ? Icons.star : Icons.star_outline,
                    size: AlayaIconSize.md,
                    color: item.isFavorite ? semantic.warning : semantic.muted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### `lib/features/inventory/providers/batch_editor_providers.dart`

```dart
/// View-model state for the batch editor (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/features/inventory/state/batch_editor_state.dart';

/// Which batch an editor is pointed at. A record, so the family argument has structural equality.
typedef BatchEditorArgs = ({String itemId, String? batchId});

/// The home currency, so a unit cost is never denominated in a guess.
final batchCurrencyProvider = FutureProvider.autoDispose<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      'INR',
);

/// The home currency's decimal digits, so no cost hardcodes 2 (ARCH_1 §4.1).
final batchDecimalDigitsProvider = FutureProvider.autoDispose<int>((ref) async {
  final code = await ref.watch(batchCurrencyProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// The item a batch belongs to, so the editor knows its immutable category.
final batchOwnerProvider = FutureProvider.autoDispose.family<Item?, String>(
  (ref, itemId) => ref.watch(itemRepositoryProvider).byId(itemId),
);

/// The editor for one batch, or for a new one when `batchId` is null.
final batchEditorProvider = NotifierProvider.autoDispose
    .family<BatchEditorNotifier, AsyncValue<BatchEditorState>, BatchEditorArgs>(
      BatchEditorNotifier.new,
    );

/// Loads, edits and saves one batch.
class BatchEditorNotifier
    extends
        AutoDisposeFamilyNotifier<
          AsyncValue<BatchEditorState>,
          BatchEditorArgs
        > {
  @override
  AsyncValue<BatchEditorState> build(BatchEditorArgs arg) {
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(BatchEditorArgs arg) async {
    try {
      final batchId = arg.batchId;
      if (batchId != null) {
        final batch = await ref.read(batchRepositoryProvider).byId(batchId);
        if (batch == null) {
          state = AsyncValue.error(
            StateError('Batch $batchId not found.'),
            StackTrace.current,
          );
          return;
        }
        state = AsyncValue.data(BatchEditorState.fromBatch(batch));
        return;
      }
      final item = await ref.read(itemRepositoryProvider).byId(arg.itemId);
      if (item == null) {
        state = AsyncValue.error(
          StateError('Item ${arg.itemId} not found.'),
          StackTrace.current,
        );
        return;
      }
      state = AsyncValue.data(
        BatchEditorState(
          itemId: arg.itemId,
          unitCode: item.defaultDisplayUnitCode,
          purchasedDateKey: ref.read(clockProvider).today(),
        ),
      );
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  void _edit(BatchEditorState Function(BatchEditorState) change) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(change(current));
  }

  /// Sets how much arrived.
  void setQuantity(Qty? quantity) => _edit(
    (s) => quantity == null
        ? s.copyWith(clearQuantity: true)
        : s.copyWith(quantity: quantity, quantityMissing: false),
  );

  /// Sets the unit the quantity was entered in.
  void setUnitCode(String code) => _edit((s) => s.copyWith(unitCode: code));

  /// Sets when it was bought.
  void setPurchased(DateKey date) =>
      _edit((s) => s.copyWith(purchasedDateKey: date));

  /// Sets when it expires, or clears the expiry.
  void setExpiry(DateKey? date) => _edit(
    (s) => date == null
        ? s.copyWith(clearExpiry: true)
        : s.copyWith(expiryDateKey: date),
  );

  /// Sets what one unit cost.
  void setUnitCost(Money? cost) => _edit(
    (s) => cost == null
        ? s.copyWith(clearUnitCost: true)
        : s.copyWith(unitCost: cost),
  );

  /// Sets where it is kept.
  void setStorageLocation(String location) =>
      _edit((s) => s.copyWith(storageLocation: location));

  /// Sets the free note.
  void setNote(String note) => _edit((s) => s.copyWith(note: note));

  /// Saves the batch, returning its id on success and null on rejection or failure.
  ///
  /// A new batch goes through `create`; an existing one through `updateMetadata`, which is the only
  /// path that does not touch `remainingQuantity`. That split is Law L3: the remaining figure is a
  /// cache reconciled from `stock_movements`, and an editor that rewrote it would leave the cache
  /// and the ledger disagreeing with no movement to explain the difference.
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    final quantity = current.quantity;
    if (quantity == null || !quantity.isPositive) {
      _edit(
        (s) =>
            s.copyWith(quantityMissing: true, shakeTrigger: s.shakeTrigger + 1),
      );
      return null;
    }

    _edit((s) => s.copyWith(submitting: true));
    final repository = ref.read(batchRepositoryProvider);
    final id = current.id ?? ref.read(uidGeneratorProvider).generate();

    if (current.isEditing) {
      final existing = await repository.byId(id);
      if (existing == null) {
        _edit((s) => s.copyWith(submitting: false));
        return null;
      }
      final updated = await repository.updateMetadata(
        current.toBatch(
          newId: id,
          resolvedQuantity: existing.initialQuantity,
          remaining: existing.remainingQuantity,
        ),
      );
      if (updated.isFailure) {
        _edit((s) => s.copyWith(submitting: false));
        return null;
      }
    } else {
      final created = await repository.create(
        current.toBatch(newId: id, resolvedQuantity: quantity),
      );
      if (created.isFailure) {
        _edit((s) => s.copyWith(submitting: false));
        return null;
      }
    }
    _edit((s) => s.copyWith(submitting: false, dirty: false));
    return id;
  }
}
```

### `lib/features/inventory/providers/batch_history_providers.dart`

```dart
/// View-model state for one batch's movement history (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/stock_movement.dart';

/// The batch the history belongs to.
final historyBatchProvider = FutureProvider.autoDispose.family<Batch?, String>(
  (ref, batchId) => ref.watch(batchRepositoryProvider).byId(batchId),
);

/// Every movement against one batch, newest first.
final batchMovementsProvider = StreamProvider.autoDispose
    .family<List<StockMovement>, String>(
      (ref, batchId) =>
          ref.watch(stockRepositoryProvider).watchForBatch(batchId),
    );

/// Which movement ids have already been reversed by a later movement.
///
/// **Derived from the ledger rather than stored on the row.** `stock_movements` is append-only
/// (Law L6): a reversal is a new row pointing back with `reversesMovementId`, and the row it
/// corrects is never rewritten. Reading the set of reversed ids out of the same stream is what lets
/// the timeline strike through the original without either row lying about the other.
final reversedMovementIdsProvider = Provider.autoDispose
    .family<Set<String>, String>((ref, batchId) {
      final movements = ref.watch(batchMovementsProvider(batchId)).valueOrNull;
      if (movements == null) return const <String>{};
      return {
        for (final movement in movements)
          if (movement.reversesMovementId != null) movement.reversesMovementId!,
      };
    });

/// Writes the history screen can perform.
final movementActionsProvider = Provider<MovementActions>(MovementActions.new);

/// Reverses movements.
class MovementActions {
  /// Creates the actions.
  MovementActions(this._ref);

  final Ref _ref;

  /// Appends an opposite movement, correcting [movementId] without erasing it.
  Future<bool> reverse(String movementId, {String? reason}) async {
    final result = await _ref
        .read(stockRepositoryProvider)
        .reverse(movementId: movementId, reason: reason);
    return !result.isFailure;
  }
}
```

### `lib/features/inventory/providers/consume_providers.dart`

```dart
/// View-model state for the consume sheet (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/features/inventory/state/consume_state.dart';

/// The batches a consume may draw from, oldest expiry first.
final consumeFefoProvider = StreamProvider.autoDispose
    .family<List<Batch>, String>(
      (ref, itemId) => ref
          .watch(batchRepositoryProvider)
          .watchByItemFefo(itemId)
          .map(
            (batches) => [
              for (final batch in batches)
                if (batch.hasStock) batch,
            ],
          ),
    );

/// Which item a consume sheet is drawing down, and in what unit.
typedef ConsumeArgs = ({String itemId, String unitCode});

/// The consume sheet for one item.
final consumeProvider = NotifierProvider.autoDispose
    .family<ConsumeNotifier, ConsumeState, ConsumeArgs>(ConsumeNotifier.new);

/// Holds the pending consume and commits it.
///
/// **State is synchronous, not an `AsyncValue`.** A capture sheet must accept its first keystroke on
/// its first frame (§5.2), and everything this notifier needs — the item and its unit — arrives in
/// the family argument from the screen that already loaded them. The asynchronous surface belongs to
/// [consumeFefoProvider], which the sheet watches separately for its four states.
class ConsumeNotifier
    extends AutoDisposeFamilyNotifier<ConsumeState, ConsumeArgs> {
  @override
  ConsumeState build(ConsumeArgs arg) =>
      ConsumeState(itemId: arg.itemId, unitCode: arg.unitCode);

  /// Sets how much is leaving.
  void setQuantity(Qty? quantity) => state = quantity == null
      ? state.copyWith(clearQuantity: true)
      : state.copyWith(quantity: quantity, quantityMissing: false);

  /// Records the unit the field is entering quantities in.
  ///
  /// `QtyField`'s unit picker is controlled, so without this the user taps `g`, the number is
  /// re-parsed against the new factor, and the picker snaps back to `kg`.
  void setUnitCode(String code) =>
      state = state.copyWith(unitCode: code, dirty: true);

  /// Switches between used, thrown away and expired.
  void setKind(StockMovementKind kind) =>
      state = state.copyWith(kind: kind, dirty: true);

  /// Overrides the FEFO choice with a specific batch.
  void setBatch(String? batchId) => state = batchId == null
      ? state.copyWith(clearOverride: true, dirty: true)
      : state.copyWith(overrideBatchId: batchId, dirty: true);

  /// Sets why, for waste and expiry.
  void setReason(String reason) =>
      state = state.copyWith(reason: reason, dirty: true);

  /// Commits the consume, returning how many movements it wrote.
  ///
  /// **Two paths, deliberately.** Without an override this calls `consume`, which allocates across
  /// batches FEFO inside one transaction (Law L14) and returns the draws it made — so a consume that
  /// spans three batches writes three movements and the caller learns the real count rather than the
  /// predicted one. With an override it calls `consumeFromBatch`, a single movement against the
  /// batch the user named.
  ///
  /// Returns null when the form was rejected or the write failed.
  Future<int?> commit() async {
    final quantity = state.quantity;
    if (quantity == null || !quantity.isPositive) {
      state = state.copyWith(
        quantityMissing: true,
        shakeTrigger: state.shakeTrigger + 1,
      );
      return null;
    }

    state = state.copyWith(submitting: true);
    final repository = ref.read(stockRepositoryProvider);
    final override = state.overrideBatchId;

    if (override != null) {
      final result = await repository.consumeFromBatch(
        batchId: override,
        quantity: quantity,
        kind: state.kind,
        reason: state.reason,
      );
      state = state.copyWith(submitting: false);
      return result.isFailure ? null : 1;
    }

    final result = await repository.consume(
      itemId: state.itemId,
      quantity: quantity,
      kind: state.kind,
      reason: state.reason,
    );
    state = state.copyWith(submitting: false);
    return result.valueOrNull?.length;
  }
}
```

### `lib/features/inventory/providers/inventory_list_providers.dart`

```dart
/// View-model state for the inventory catalogue (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/state/inventory_filter.dart';

/// One section of the catalogue.
class InventoryGroup {
  /// Creates a group.
  const InventoryGroup({
    required this.items,
    this.kind,
    this.isFavourites = false,
  });

  /// The items in it, already sorted by name.
  final List<Item> items;

  /// Which kind this group collects, or null for the favourites group.
  final ItemKind? kind;

  /// Whether this is the favourites group.
  final bool isFavourites;
}

/// The catalogue's current filter.
final inventoryFilterProvider =
    NotifierProvider<InventoryFilterNotifier, InventoryFilter>(
      InventoryFilterNotifier.new,
    );

/// Drives the search field, group-by chips and filter toggles.
class InventoryFilterNotifier extends Notifier<InventoryFilter> {
  @override
  InventoryFilter build() => const InventoryFilter();

  /// Sets the search term.
  void setQuery(String query) => state = state.copyWith(query: query.trim());

  /// Switches the grouping axis.
  void setGroupBy(InventoryGroupBy groupBy) =>
      state = state.copyWith(groupBy: groupBy);

  /// Shows only starred items.
  void toggleFavouritesOnly() =>
      state = state.copyWith(favouritesOnly: !state.favouritesOnly);

  /// Shows only items below their low-stock level.
  void toggleLowStockOnly() =>
      state = state.copyWith(lowStockOnly: !state.lowStockOnly);

  /// Adds or removes a kind.
  void toggleKind(ItemKind kind) {
    final next = {...state.kinds};
    if (next.contains(kind)) {
      next.remove(kind);
    } else {
      next.add(kind);
    }
    state = state.copyWith(kinds: next);
  }

  /// Clears everything back to the full catalogue.
  void clear() => state = InventoryFilter(query: state.query);
}

/// Every item in the catalogue.
final itemsProvider = StreamProvider<List<Item>>(
  (ref) => ref.watch(itemRepositoryProvider).watchAll(),
);

/// Stock on hand for every item, keyed by item id.
///
/// `ItemStock.totalRemaining` is the summed mixed-unit figure the row shows — the sum lives in the
/// domain rather than being re-added in the widget, which is what keeps ARCH_1 §5.4's arithmetic in
/// one place instead of two.
final itemStocksProvider = StreamProvider<Map<String, ItemStock>>(
  (ref) => ref
      .watch(itemRepositoryProvider)
      .watchAllStock()
      .map(
        (stocks) => {for (final stock in stocks) stock.itemId: stock},
      ),
);

/// Every unit, keyed by code, so a row can name the unit a quantity is shown in.
final unitsByCodeProvider = StreamProvider<Map<String, Unit>>(
  (ref) => ref
      .watch(unitRepositoryProvider)
      .watchAll()
      .map(
        (units) => {for (final unit in units) unit.code: unit},
      ),
);

/// The catalogue, filtered, searched and grouped.
///
/// A `Provider` over the two streams rather than a third stream: grouping is pure, and doing it here
/// means the screen watches one thing and gets all four states from it.
final inventoryGroupsProvider = Provider<AsyncValue<List<InventoryGroup>>>((
  ref,
) {
  final items = ref.watch(itemsProvider);
  final stocks = ref.watch(itemStocksProvider);
  final filter = ref.watch(inventoryFilterProvider);

  if (items.hasError) return AsyncValue.error(items.error!, items.stackTrace!);
  if (stocks.hasError)
    return AsyncValue.error(stocks.error!, stocks.stackTrace!);
  final all = items.valueOrNull;
  final byId = stocks.valueOrNull;
  if (all == null || byId == null) return const AsyncValue.loading();

  final term = filter.query.toLowerCase();
  final visible = [
    for (final item in all)
      if (_admits(item, byId[item.id], filter, term)) item,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  if (filter.groupBy == InventoryGroupBy.favourite) {
    final starred = [
      for (final item in visible)
        if (item.isFavorite) item,
    ];
    final rest = [
      for (final item in visible)
        if (!item.isFavorite) item,
    ];
    return AsyncValue.data([
      if (starred.isNotEmpty)
        InventoryGroup(items: starred, isFavourites: true),
      if (rest.isNotEmpty) InventoryGroup(items: rest),
    ]);
  }

  final buckets = <ItemKind, List<Item>>{};
  for (final item in visible) {
    buckets.putIfAbsent(item.itemKind, () => <Item>[]).add(item);
  }
  return AsyncValue.data([
    for (final kind in ItemKind.values)
      if (buckets[kind] != null)
        InventoryGroup(items: buckets[kind]!, kind: kind),
  ]);
});

/// How many items are below their low-stock level, for the filter chip's count.
final lowStockCountProvider = Provider<int>((ref) {
  final stocks = ref.watch(itemStocksProvider).valueOrNull;
  if (stocks == null) return 0;
  return stocks.values.where((stock) => stock.isLowStock).length;
});

bool _admits(Item item, ItemStock? stock, InventoryFilter filter, String term) {
  if (filter.favouritesOnly && !item.isFavorite) return false;
  if (filter.lowStockOnly && !(stock?.isLowStock ?? false)) return false;
  if (filter.kinds.isNotEmpty && !filter.kinds.contains(item.itemKind))
    return false;
  if (term.isEmpty) return true;
  return item.normalizedName.contains(term) ||
      item.name.toLowerCase().contains(term);
}
```

### `lib/features/inventory/providers/item_detail_providers.dart`

```dart
/// View-model state for one item (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/providers/inventory_list_providers.dart';

/// The item, or null when it has been deleted.
/// **Derived from the catalogue stream, not a one-shot `byId`.** A `FutureProvider` reads once and
/// then serves its cache, and `autoDispose` does not help — the detail screen stays mounted beneath
/// the editor, so it kept showing the pre-edit item until the app was restarted. `watchAll()` re-emits
/// on every write, so selecting one item out of it makes the screen live and needs no `watchById` on
/// the contract.
final itemByIdProvider = Provider.autoDispose.family<AsyncValue<Item?>, String>(
  (ref, id) {
    return ref.watch(itemsProvider).whenData((all) {
      for (final item in all) {
        if (item.id == id) return item;
      }
      return null;
    });
  },
);

/// Stock on hand for one item — the hero figure.
final itemStockProvider = StreamProvider.autoDispose.family<ItemStock?, String>(
  (ref, id) => ref.watch(itemRepositoryProvider).watchStockOf(id),
);

/// This item's batches, oldest expiry first, which is also the order a consume draws them.
final itemBatchesProvider = StreamProvider.autoDispose
    .family<List<Batch>, String>(
      (ref, id) => ref.watch(batchRepositoryProvider).watchByItemFefo(id),
    );

/// Every unit, keyed by code.
final detailUnitsByCodeProvider = StreamProvider.autoDispose<Map<String, Unit>>(
  (ref) => ref
      .watch(unitRepositoryProvider)
      .watchAll()
      .map(
        (units) => {for (final unit in units) unit.code: unit},
      ),
);

/// Writes an item detail screen can perform.
final itemActionsProvider = Provider<ItemActions>(ItemActions.new);

/// Deletes and stars items.
class ItemActions {
  /// Creates the actions.
  ItemActions(this._ref);

  final Ref _ref;

  /// Deletes the item, cascade-soft-deleting its batches.
  ///
  /// **The movement history is left untouched.** Batches carry `deletedAt` and go with the item, but
  /// `stock_movements` is append-only (Law L6) — what was already used genuinely happened, and
  /// erasing it would change last month's waste figures because a container was tidied away today.
  Future<bool> delete(String id) async {
    final result = await _ref.read(itemRepositoryProvider).delete(id);
    return !result.isFailure;
  }

  /// Stars or unstars the item.
  Future<bool> toggleFavourite(Item item) async {
    final result = await _ref
        .read(itemRepositoryProvider)
        .setFavorite(
          id: item.id,
          isFavorite: !item.isFavorite,
        );
    return !result.isFailure;
  }

  /// Deletes one batch, leaving its movements in place for the same reason.
  Future<bool> deleteBatch(String batchId) async {
    final result = await _ref.read(batchRepositoryProvider).delete(batchId);
    return !result.isFailure;
  }
}
```

### `lib/features/inventory/providers/item_editor_providers.dart`

```dart
/// View-model state for the item editor (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/state/item_editor_state.dart';

/// The units available in one category.
///
/// Category-filtered, always. Law L8 says cross-category conversion does not exist, so offering
/// `ml` for an item measured by weight would present a choice the domain cannot honour.
final unitsInCategoryProvider = StreamProvider.autoDispose
    .family<List<Unit>, UnitCategory>(
      (ref, category) =>
          ref.watch(unitRepositoryProvider).watchByCategory(category),
    );

/// The editor for one item, or for a new one when the argument is null.
final itemEditorProvider = NotifierProvider.autoDispose
    .family<ItemEditorNotifier, AsyncValue<ItemEditorState>, String?>(
      ItemEditorNotifier.new,
    );

/// Loads, edits and saves one item.
class ItemEditorNotifier
    extends AutoDisposeFamilyNotifier<AsyncValue<ItemEditorState>, String?> {
  @override
  AsyncValue<ItemEditorState> build(String? arg) {
    // **A new item starts populated, not loading.** `_load` assigned `state` with no `await` before
    // it, which means it ran *during* `build` — Riverpod refuses that, the assignment was lost or
    // threw, and the screen sat on its skeleton with no form and no error. There is also nothing to
    // fetch for a blank item, so pretending to load was wrong twice over.
    if (arg == null) {
      return const AsyncValue.data(
        ItemEditorState(
          unitCategory: UnitCategory.count,
          displayUnitCode: 'pc',
        ),
      );
    }
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(String id) async {
    try {
      final item = await ref.read(itemRepositoryProvider).byId(id);
      if (item == null) {
        state = AsyncValue.error(
          StateError('Item $id not found.'),
          StackTrace.current,
        );
        return;
      }
      state = AsyncValue.data(ItemEditorState.fromItem(item));
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  void _edit(ItemEditorState Function(ItemEditorState) change) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(change(current));
  }

  /// Sets the name.
  void setName(String name) => _edit(
    (s) => s.copyWith(name: name, nameMissing: false, clearIssue: true),
  );

  /// Sets how this item is measured, and resets the display unit to that category's base.
  ///
  /// **Only callable while creating.** Law L8 makes the category immutable once saved, so the editor
  /// hides the control on edit and this method refuses the change rather than trusting it not to be
  /// called — a guard on the state is worth more than a guard on the widget.
  void setCategory(UnitCategory category, String baseUnitCode) => _edit(
    (s) => s.isEditing
        ? s
        : ItemEditorState(
            id: s.id,
            name: s.name,
            unitCategory: category,
            displayUnitCode: baseUnitCode,
            thresholdUnitCode: baseUnitCode,
            itemKind: s.itemKind,
            isFavorite: s.isFavorite,
            expiryNotifyDays: s.expiryNotifyDays,
            densityMilliGramsPerMl: s.densityMilliGramsPerMl,
            milliGramsPerPiece: s.milliGramsPerPiece,
            notes: s.notes,
            dirty: true,
          ),
  );

  /// Sets the unit quantities are displayed in.
  void setDisplayUnit(Unit unit) =>
      _edit((s) => s.copyWith(displayUnitCode: unit.code));

  /// Sets the unit the low-stock threshold is being entered in.
  void setThresholdUnit(Unit unit) =>
      _edit((s) => s.copyWith(thresholdUnitCode: unit.code));

  /// Sets what sort of thing this is.
  void setKind(ItemKind kind) => _edit((s) => s.copyWith(itemKind: kind));

  /// Stars or unstars it.
  void toggleFavourite() => _edit((s) => s.copyWith(isFavorite: !s.isFavorite));

  /// Sets the level below which the `low` chip appears.
  void setThreshold(Qty? threshold) => _edit(
    (s) => threshold == null
        ? s.copyWith(clearThreshold: true)
        : s.copyWith(lowStockThreshold: threshold),
  );

  /// Sets how many days of expiry warning Phase 8B should give.
  void setExpiryNotifyDays(int? days) => _edit(
    (s) => days == null
        ? s.copyWith(clearNotifyDays: true)
        : s.copyWith(expiryNotifyDays: days),
  );

  /// Sets how much one millilitre weighs, in milli-grams. Null clears it.
  ///
  /// **Null is a real answer, not a blank.** An item with no density keeps reporting a cross-measure
  /// ingredient as unanswerable, which is the behaviour the recipe module is built around — so
  /// clearing this is a deliberate state, and `clearDensity` exists so it can be reached.
  void setDensity(int? milliGramsPerMl) => _edit(
    (s) => milliGramsPerMl == null
        ? s.copyWith(clearDensity: true)
        : s.copyWith(densityMilliGramsPerMl: milliGramsPerMl),
  );

  /// Sets what one piece weighs, in milli-grams. Null clears it.
  void setPieceWeight(int? milliGrams) => _edit(
    (s) => milliGrams == null
        ? s.copyWith(clearPieceWeight: true)
        : s.copyWith(milliGramsPerPiece: milliGrams),
  );

  /// Sets the free notes.
  void setNotes(String notes) => _edit((s) => s.copyWith(notes: notes));

  /// Saves the item, returning its id on success and null on rejection or failure.
  ///
  /// **Every refusal is named before the database gets a chance to refuse it.** `items` carries a
  /// partial unique index on `(normalized_name, unit_category)` and `default_display_unit_code`
  /// references `units`, so a blind write can fail two ways that look identical to the user. Checking
  /// first turns "something went wrong" into a sentence they can act on — and the duplicate case
  /// hands back the id of the item they already have, so the editor can offer to open it.
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (current.name.trim().isEmpty) {
      _edit(
        (s) => s.copyWith(nameMissing: true, shakeTrigger: s.shakeTrigger + 1),
      );
      return null;
    }

    _edit((s) => s.copyWith(submitting: true, clearIssue: true));
    try {
      final repository = ref.read(itemRepositoryProvider);
      final normalized = ref
          .read(normalizerProvider)
          .normalize(current.name.trim());

      final clash = await repository.findByIdentity(
        normalizedName: normalized,
        unitCategory: current.unitCategory,
      );
      if (clash != null && clash.id != current.id) {
        _edit(
          (s) => s.copyWith(
            issue: ItemSaveIssue.duplicate,
            conflictItemId: clash.id,
          ),
        );
        return null;
      }

      // The display unit is a foreign key. Resolving it against the units that actually exist keeps a
      // thinly-seeded category from failing as an opaque constraint error.
      final units = await ref
          .read(unitRepositoryProvider)
          .watchByCategory(current.unitCategory)
          .first;
      if (units.isEmpty) {
        _edit((s) => s.copyWith(issue: ItemSaveIssue.unitsMissing));
        return null;
      }
      final displayUnit =
          units.any((unit) => unit.code == current.displayUnitCode)
          ? current.displayUnitCode
          : units.first.code;

      final id = current.id ?? ref.read(uidGeneratorProvider).generate();
      final saved = await repository.save(
        current
            .copyWith(displayUnitCode: displayUnit)
            .toItem(
              newId: id,
              normalizedName: normalized,
            ),
      );
      if (saved.isFailure) {
        _edit((s) => s.copyWith(issue: ItemSaveIssue.unknown));
        return null;
      }
      _edit((s) => s.copyWith(dirty: false));
      return id;
    } on Object catch (error, stack) {
      ref
          .read(loggerProvider)
          .log(
            'Item save failed',
            level: LogLevel.error,
            tag: 'inventory.itemEditor',
            error: error,
            stackTrace: stack,
          );
      _edit((s) => s.copyWith(issue: ItemSaveIssue.unknown));
      return null;
    } finally {
      _edit((s) => s.copyWith(submitting: false));
    }
  }

  /// Looks up items sharing this name under a different measure, for the informational note.
  Future<void> refreshSimilar() async {
    final current = state.valueOrNull;
    if (current == null || current.name.trim().isEmpty) return;
    final similar = await ref
        .read(itemRepositoryProvider)
        .findSimilar(
          name: current.name.trim(),
          unitCategory: current.unitCategory,
        );
    _edit(
      (s) => s.copyWith(
        similarInOtherMeasures: [
          for (final item in similar)
            if (item.id != current.id &&
                item.unitCategory != current.unitCategory)
              item,
        ],
        dirty: s.dirty,
      ),
    );
  }
}
```

### `lib/features/inventory/state/batch_editor_state.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';

/// Everything the batch editor is holding (ARCH_5 §3 archetype B).
///
/// A batch's quantity is editable only while creating. Once movements exist against it,
/// `remainingQuantity` is a derived cache (Law L3) reconciled from the movement ledger, so an editor
/// rewriting it would put the cache and the ledger into disagreement that only `recompute()` could
/// resolve. Editing therefore covers the metadata — expiry, purchase date, unit cost, location — and
/// quantity changes go through the consume and adjust paths, which append movements.
class BatchEditorState {
  /// Creates the editor's state.
  const BatchEditorState({
    required this.itemId,
    required this.unitCode,
    required this.purchasedDateKey,
    this.id,
    this.quantity,
    this.expiryDateKey,
    this.unitCost,
    this.storageLocation,
    this.note,
    this.origin = BatchOrigin.manual,
    this.submitting = false,
    this.quantityMissing = false,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// The batch being edited, or null when this is a new one.
  final String? id;

  /// Which item this batch belongs to.
  final String itemId;

  /// How much arrived — the one required field when creating (U11).
  final Qty? quantity;

  /// The unit the quantity was entered in.
  final String unitCode;

  /// When it was bought.
  final DateKey purchasedDateKey;

  /// When it expires, if it does.
  final DateKey? expiryDateKey;

  /// What one unit cost.
  final Money? unitCost;

  /// Where it is kept.
  final String? storageLocation;

  /// Free note.
  final String? note;

  /// Where this batch came from; preserved on edit so a fan-out batch stays attributed.
  final BatchOrigin origin;

  /// Whether a save is in flight.
  final bool submitting;

  /// Whether submit was pressed with no parseable quantity.
  final bool quantityMissing;

  /// Incremented to shake the quantity field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the unsaved-changes guard (U10).
  final bool dirty;

  /// Whether this is editing an existing batch rather than creating one.
  bool get isEditing => id != null;

  /// Whether the quantity field may be edited.
  bool get quantityEditable => !isEditing;

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  BatchEditorState copyWith({
    String? id,
    Qty? quantity,
    bool clearQuantity = false,
    String? unitCode,
    DateKey? purchasedDateKey,
    DateKey? expiryDateKey,
    bool clearExpiry = false,
    Money? unitCost,
    bool clearUnitCost = false,
    String? storageLocation,
    String? note,
    BatchOrigin? origin,
    bool? submitting,
    bool? quantityMissing,
    int? shakeTrigger,
    bool? dirty,
  }) => BatchEditorState(
    id: id ?? this.id,
    itemId: itemId,
    quantity: clearQuantity ? null : (quantity ?? this.quantity),
    unitCode: unitCode ?? this.unitCode,
    purchasedDateKey: purchasedDateKey ?? this.purchasedDateKey,
    expiryDateKey: clearExpiry ? null : (expiryDateKey ?? this.expiryDateKey),
    unitCost: clearUnitCost ? null : (unitCost ?? this.unitCost),
    storageLocation: storageLocation ?? this.storageLocation,
    note: note ?? this.note,
    origin: origin ?? this.origin,
    submitting: submitting ?? this.submitting,
    quantityMissing: quantityMissing ?? this.quantityMissing,
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? true,
  );

  /// Builds the entity this state describes.
  ///
  /// [remaining] is the existing remaining quantity when editing; a new batch starts full.
  Batch toBatch({
    required String newId,
    required Qty resolvedQuantity,
    Qty? remaining,
  }) => Batch(
    id: id ?? newId,
    itemId: itemId,
    initialQuantity: resolvedQuantity,
    remainingQuantity: remaining ?? resolvedQuantity,
    unitCodeAtPurchase: unitCode,
    purchasedDateKey: purchasedDateKey,
    origin: origin,
    expiryDateKey: expiryDateKey,
    unitCost: unitCost,
    storageLocation: storageLocation,
    note: note,
  );

  /// Loads an existing batch into an editor state.
  static BatchEditorState fromBatch(Batch batch) => BatchEditorState(
    id: batch.id,
    itemId: batch.itemId,
    quantity: batch.initialQuantity,
    unitCode: batch.unitCodeAtPurchase,
    purchasedDateKey: batch.purchasedDateKey,
    expiryDateKey: batch.expiryDateKey,
    unitCost: batch.unitCost,
    storageLocation: batch.storageLocation,
    note: batch.note,
    origin: batch.origin,
  );
}
```

### `lib/features/inventory/state/consume_state.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/domain/entities/batch.dart';

/// One batch the pending consume will draw from, and how much.
class ConsumePlanLeg {
  /// Creates a leg.
  const ConsumePlanLeg({required this.batch, required this.quantity});

  /// The batch drawn from.
  final Batch batch;

  /// How much comes out of it.
  final Qty quantity;
}

/// What the consume sheet is holding (ARCH_5 §3 archetype A).
class ConsumeState {
  /// Creates the sheet's state.
  const ConsumeState({
    required this.itemId,
    required this.unitCode,
    this.quantity,
    this.kind = StockMovementKind.consume,
    this.overrideBatchId,
    this.reason,
    this.submitting = false,
    this.quantityMissing = false,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// Which item is being drawn down.
  final String itemId;

  /// The unit the quantity was entered in.
  final String unitCode;

  /// How much — the one required field (U11).
  final Qty? quantity;

  /// Used, thrown away, or expired. Three kinds, not one with a reason string, because 7B's waste
  /// insight aggregates on `stock_movements.kind` and cannot read prose.
  final StockMovementKind kind;

  /// The batch the user picked instead of letting FEFO choose.
  final String? overrideBatchId;

  /// Why, for waste and expiry.
  final String? reason;

  /// Whether a commit is in flight.
  final bool submitting;

  /// Whether commit was pressed with no parseable quantity.
  final bool quantityMissing;

  /// Incremented to shake the quantity field.
  final int shakeTrigger;

  /// Whether any optional field was touched, for the dismiss guard (U10).
  final bool dirty;

  /// Whether the user has overridden the FEFO choice.
  bool get isOverridden => overrideBatchId != null;

  /// Returns a copy with the supplied changes.
  ConsumeState copyWith({
    Qty? quantity,
    bool clearQuantity = false,
    String? unitCode,
    StockMovementKind? kind,
    String? overrideBatchId,
    bool clearOverride = false,
    String? reason,
    bool? submitting,
    bool? quantityMissing,
    int? shakeTrigger,
    bool? dirty,
  }) => ConsumeState(
    itemId: itemId,
    unitCode: unitCode ?? this.unitCode,
    quantity: clearQuantity ? null : (quantity ?? this.quantity),
    kind: kind ?? this.kind,
    overrideBatchId: clearOverride
        ? null
        : (overrideBatchId ?? this.overrideBatchId),
    reason: reason ?? this.reason,
    submitting: submitting ?? this.submitting,
    quantityMissing: quantityMissing ?? this.quantityMissing,
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? this.dirty,
  );

  /// Which batches this consume will touch, oldest expiry first.
  ///
  /// **Computed here so the sheet can say "spans 3 batches" before committing**, not after. The
  /// repository's `consume()` does the authoritative allocation and returns the draws it actually
  /// made; this is the preview that lets the user see a multi-batch write coming. The two agree
  /// because both walk the same FEFO ordering from `watchByItemFefo`.
  ///
  /// An override collapses the plan to a single leg, clamped to what that batch holds.
  List<ConsumePlanLeg> planAgainst(List<Batch> fefo) {
    final wanted = quantity;
    if (wanted == null || !wanted.isPositive) return const [];

    final override = overrideBatchId;
    if (override != null) {
      for (final batch in fefo) {
        if (batch.id != override) continue;
        final take = wanted <= batch.remainingQuantity
            ? wanted
            : batch.remainingQuantity;
        return take.isPositive
            ? [ConsumePlanLeg(batch: batch, quantity: take)]
            : const [];
      }
      return const [];
    }

    final legs = <ConsumePlanLeg>[];
    var outstanding = wanted;
    for (final batch in fefo) {
      if (!outstanding.isPositive) break;
      if (!batch.hasStock) continue;
      final take = outstanding <= batch.remainingQuantity
          ? outstanding
          : batch.remainingQuantity;
      legs.add(ConsumePlanLeg(batch: batch, quantity: take));
      outstanding -= take;
    }
    return legs;
  }

  /// How much of [quantity] the batches cannot cover.
  Qty? shortfallAgainst(List<Batch> fefo) {
    final wanted = quantity;
    if (wanted == null) return null;
    var covered = Qty(0, wanted.category);
    for (final leg in planAgainst(fefo)) {
      covered += leg.quantity;
    }
    final missing = wanted - covered;
    return missing.isPositive ? missing : null;
  }
}
```

### `lib/features/inventory/state/inventory_filter.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';

/// The axis the catalogue groups by.
enum InventoryGroupBy {
  /// By `items.itemKind` — food, medicine, household.
  kind,

  /// Favourites first, everything else after.
  favourite,
}

/// What the inventory list is currently showing.
///
/// **Grouping is by `itemKind`, not by tag.** Archetype D asks for "the user's own axis — tag for
/// items", and `item_tags` is assigned to this phase in ARCH_5 §7.1 — but no contract in Phase 3A
/// reads or writes an item's tags. `TagRepository` exposes `watchForTransaction` and nothing
/// equivalent for items, and U19 forbids a feature declaring its own repository. `itemKind` is the
/// nearest axis that exists, is set by the user in the editor, and needs no new contract. The tag
/// axis is recorded as a deferral in the coverage table with the contract it waits on.
class InventoryFilter {
  /// Creates a filter.
  const InventoryFilter({
    this.groupBy = InventoryGroupBy.kind,
    this.favouritesOnly = false,
    this.lowStockOnly = false,
    this.kinds = const <ItemKind>{},
    this.query = '',
  });

  /// The grouping axis.
  final InventoryGroupBy groupBy;

  /// Whether only starred items are shown.
  final bool favouritesOnly;

  /// Whether only items below their low-stock level are shown.
  final bool lowStockOnly;

  /// Which kinds are shown; empty means all.
  final Set<ItemKind> kinds;

  /// The search term, already trimmed.
  final String query;

  /// Whether anything narrows the full catalogue.
  bool get isNarrowed =>
      favouritesOnly ||
      lowStockOnly ||
      kinds.isNotEmpty ||
      groupBy != InventoryGroupBy.kind;

  /// Whether a search is running.
  bool get isSearching => query.isNotEmpty;

  /// Returns a copy with the supplied changes.
  InventoryFilter copyWith({
    InventoryGroupBy? groupBy,
    bool? favouritesOnly,
    bool? lowStockOnly,
    Set<ItemKind>? kinds,
    String? query,
  }) => InventoryFilter(
    groupBy: groupBy ?? this.groupBy,
    favouritesOnly: favouritesOnly ?? this.favouritesOnly,
    lowStockOnly: lowStockOnly ?? this.lowStockOnly,
    kinds: kinds ?? this.kinds,
    query: query ?? this.query,
  );
}
```

### `lib/features/inventory/state/item_editor_state.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/item.dart';

/// Why a save was refused, when it was refused for a reason worth naming.
enum ItemSaveIssue {
  /// A live item already has this name and this measure.
  duplicate,

  /// No units exist for the chosen measure, so the display unit would dangle.
  unitsMissing,

  /// The write failed for a reason the repository did not name.
  unknown,
}

/// Everything the item editor is holding (ARCH_5 §3 archetype B).
///
/// **`unitCategory` has no setter once [isEditing] is true.** Law L8 makes it immutable after
/// creation and there is no cross-category conversion, so changing it would reinterpret every batch
/// and movement already recorded against this item — 2 kg of flour silently becoming 2 litres. The
/// editor renders it read-only and says why rather than offering a control that must then be
/// refused.
class ItemEditorState {
  /// Creates the editor's state.
  const ItemEditorState({
    required this.unitCategory,
    required this.displayUnitCode,
    this.thresholdUnitCode,
    this.id,
    this.name = '',
    this.itemKind = ItemKind.generic,
    this.isFavorite = false,
    this.lowStockThreshold,
    this.expiryNotifyDays,
    this.densityMilliGramsPerMl,
    this.milliGramsPerPiece,
    this.notes,
    this.submitting = false,
    this.nameMissing = false,
    this.shakeTrigger = 0,
    this.dirty = false,
    this.issue,
    this.conflictItemId,
    this.similarInOtherMeasures = const <Item>[],
  });

  /// The item being edited, or null when this is a new one.
  final String? id;

  /// The name — the one required field (U11).
  final String name;

  /// How this item is measured. Immutable once saved (Law L8).
  final UnitCategory unitCategory;

  /// The unit this item's quantities are shown in.
  final String displayUnitCode;

  /// The unit the low-stock threshold is being *entered* in, which is not the display unit.
  ///
  /// Kept separately because typing a threshold in grams must not silently switch the item's whole
  /// display to grams — the stored `Qty` is milli-base either way, so the two choices are
  /// independent and conflating them surprises the user for no gain.
  final String? thresholdUnitCode;

  /// What sort of thing it is; also the catalogue's grouping axis.
  final ItemKind itemKind;

  /// Whether it is starred.
  final bool isFavorite;

  /// The level below which the `low` chip appears.
  final Qty? lowStockThreshold;

  /// Days of warning before a batch expires, consumed by Phase 8B.
  final int? expiryNotifyDays;

  /// How much one millilitre weighs, in milli-grams. Null when unknown.
  ///
  /// **Only meaningful for an item measured by weight.** It is what lets a recipe say "2 tbsp" of
  /// this and have it deducted: a tablespoon is 14.787 ml for everything, and only the substance
  /// knows what that weighs. Null keeps a cross-measure ingredient reading *"can't compare"* —
  /// the honest answer rather than a guessed one.
  final int? densityMilliGramsPerMl;

  /// What one piece weighs, in milli-grams. Null when unknown.
  ///
  /// The same bridge for "2 onions" against onions kept by weight.
  final int? milliGramsPerPiece;

  /// Free notes.
  final String? notes;

  /// Whether a save is in flight.
  final bool submitting;

  /// Whether submit was pressed with an empty name.
  final bool nameMissing;

  /// Incremented to shake the name field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the unsaved-changes guard (U10).
  final bool dirty;

  /// Why the last save was refused, or null if it was not.
  final ItemSaveIssue? issue;

  /// The existing item this one collides with, so the editor can offer to open it.
  final String? conflictItemId;

  /// Items with this name under a different measure.
  ///
  /// Not a conflict — Law L8 makes `apple` by weight and `apple` by count two genuinely different
  /// things, and a household legitimately has both. Surfaced as a note so the catalogue does not
  /// fragment by accident, never as a block.
  final List<Item> similarInOtherMeasures;

  /// Whether this is editing an existing item rather than creating one.
  bool get isEditing => id != null;

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  ItemEditorState copyWith({
    String? id,
    String? name,
    String? displayUnitCode,
    String? thresholdUnitCode,
    ItemKind? itemKind,
    bool? isFavorite,
    Qty? lowStockThreshold,
    bool clearThreshold = false,
    int? expiryNotifyDays,
    bool clearNotifyDays = false,
    int? densityMilliGramsPerMl,
    bool clearDensity = false,
    int? milliGramsPerPiece,
    bool clearPieceWeight = false,
    String? notes,
    bool? submitting,
    bool? nameMissing,
    int? shakeTrigger,
    bool? dirty,
    ItemSaveIssue? issue,
    bool clearIssue = false,
    String? conflictItemId,
    List<Item>? similarInOtherMeasures,
  }) => ItemEditorState(
    id: id ?? this.id,
    name: name ?? this.name,
    unitCategory: unitCategory,
    displayUnitCode: displayUnitCode ?? this.displayUnitCode,
    thresholdUnitCode: thresholdUnitCode ?? this.thresholdUnitCode,
    itemKind: itemKind ?? this.itemKind,
    isFavorite: isFavorite ?? this.isFavorite,
    lowStockThreshold: clearThreshold
        ? null
        : (lowStockThreshold ?? this.lowStockThreshold),
    expiryNotifyDays: clearNotifyDays
        ? null
        : (expiryNotifyDays ?? this.expiryNotifyDays),
    densityMilliGramsPerMl: clearDensity
        ? null
        : (densityMilliGramsPerMl ?? this.densityMilliGramsPerMl),
    milliGramsPerPiece: clearPieceWeight
        ? null
        : (milliGramsPerPiece ?? this.milliGramsPerPiece),
    notes: notes ?? this.notes,
    submitting: submitting ?? this.submitting,
    nameMissing: nameMissing ?? this.nameMissing,
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? true,
    issue: clearIssue ? null : (issue ?? this.issue),
    conflictItemId: clearIssue ? null : (conflictItemId ?? this.conflictItemId),
    similarInOtherMeasures:
        similarInOtherMeasures ?? this.similarInOtherMeasures,
  );

  /// Builds the entity this state describes.
  Item toItem({required String newId, required String normalizedName}) => Item(
    id: id ?? newId,
    name: name.trim(),
    normalizedName: normalizedName,
    unitCategory: unitCategory,
    defaultDisplayUnitCode: displayUnitCode,
    itemKind: itemKind,
    isFavorite: isFavorite,
    lowStockThreshold: lowStockThreshold,
    expiryNotifyDays: expiryNotifyDays,
    notes: notes,
  );

  /// Loads an existing item into an editor state.
  static ItemEditorState fromItem(Item item) => ItemEditorState(
    id: item.id,
    name: item.name,
    unitCategory: item.unitCategory,
    displayUnitCode: item.defaultDisplayUnitCode,
    itemKind: item.itemKind,
    isFavorite: item.isFavorite,
    lowStockThreshold: item.lowStockThreshold,
    expiryNotifyDays: item.expiryNotifyDays,
    densityMilliGramsPerMl: item.densityMilliGramsPerMl,
    milliGramsPerPiece: item.milliGramsPerPiece,
    notes: item.notes,
  );
}
```

### `test/features/inventory/batch_editor_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_editor_screen.dart';
import 'package:alaya/features/inventory/providers/batch_editor_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/inventory/state/batch_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/qty_field.dart';

import '../../support/inventory_harness.dart';

/// Four states, plus Law L3: an existing batch's quantity is a derived cache, not a form field.
void main() {
  BatchEditorState seed({String? id}) => BatchEditorState(
    id: id,
    itemId: kItem.id,
    unitCode: 'kg',
    purchasedDateKey: kToday,
    quantity: id == null ? null : const Qty(2000000, UnitCategory.weight),
  );

  List<Override> overrides(AsyncValue<BatchEditorState> state) => [
    batchEditorProvider.overrideWith(() => _StubBatchEditor(state)),
    batchOwnerProvider(kItem.id).overrideWith((ref) async => kItem),
    batchCurrencyProvider.overrideWith((ref) async => 'INR'),
    batchDecimalDigitsProvider.overrideWith((ref) async => 2),
    unitsInCategoryProvider(
      UnitCategory.weight,
    ).overrideWith((ref) => Stream.value(<Unit>[kKilogram, kGram])),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('error reads as not found', (tester) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('adding a batch opens on the form with every §7.2 field', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id),
      overrides: overrides(AsyncValue.data(seed())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.byType(QtyField), findsOneWidget);
    expect(find.text('Expiry'), findsOneWidget);
    expect(find.text('Purchased'), findsOneWidget);
    expect(find.text('Unit cost'), findsOneWidget);
    expect(find.text('Stored in'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save batch'), findsOneWidget);
  });

  testWidgets('editing locks the quantity and says the ledger owns it', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id, batchId: 'batch-1'),
      overrides: overrides(AsyncValue.data(seed(id: 'batch-1'))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(QtyField), findsNothing);
    expect(find.byType(KeyValueRow), findsOneWidget);
    expect(
      find.textContaining('worked out from the movement history'),
      findsOneWidget,
    );
  });

  testWidgets('editing offers a retire path; adding does not', (tester) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id, batchId: 'batch-1'),
      overrides: overrides(AsyncValue.data(seed(id: 'batch-1'))),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Delete batch'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Delete batch'), findsNothing);

    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id),
      overrides: overrides(AsyncValue.data(seed())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete batch'), findsNothing);
  });

  testWidgets('the commit lives in the footer', (tester) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id),
      overrides: overrides(AsyncValue.data(seed())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CloseButton), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(TextButton, 'Save batch'),
      ),
      findsNothing,
    );
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id),
      overrides: overrides(AsyncValue.data(seed())),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

/// A notifier reporting a fixed state.
class _StubBatchEditor extends BatchEditorNotifier {
  _StubBatchEditor(this._state);

  final AsyncValue<BatchEditorState> _state;

  @override
  AsyncValue<BatchEditorState> build(BatchEditorArgs arg) => _state;
}
```

### `test/features/inventory/batch_history_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_history_screen.dart';
import 'package:alaya/features/inventory/providers/batch_history_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_timeline.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/inventory_harness.dart';

/// Four states, plus the append-only rule: a reversal marks the original rather than removing it.
void main() {
  const batchId = 'batch-1';

  List<Override> overrides({
    List<StockMovement>? movements,
    bool pending = false,
    bool fail = false,
  }) => [
    if (pending)
      batchMovementsProvider(
        batchId,
      ).overrideWith((ref) => pendingStream<List<StockMovement>>())
    else if (fail)
      batchMovementsProvider(
        batchId,
      ).overrideWith((ref) => Stream.error(StateError('boom')))
    else
      batchMovementsProvider(
        batchId,
      ).overrideWith((ref) => Stream.value(movements ?? const [])),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpInventory(
      tester,
      const BatchHistoryScreen(itemId: 'item-1', batchId: batchId),
      overrides: overrides(pending: true),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('empty explains what will appear here', (tester) async {
    await pumpInventory(
      tester,
      const BatchHistoryScreen(itemId: 'item-1', batchId: batchId),
      overrides: overrides(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nothing recorded yet'), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpInventory(
      tester,
      const BatchHistoryScreen(itemId: 'item-1', batchId: batchId),
      overrides: overrides(fail: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('populated renders a timeline naming each movement kind', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const BatchHistoryScreen(itemId: 'item-1', batchId: batchId),
      overrides: overrides(
        movements: [
          sampleMovement(
            id: 'mv-2',
            kind: StockMovementKind.waste,
            reason: 'Mouldy',
          ),
          sampleMovement(kind: StockMovementKind.purchaseIn),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaTimeline), findsOneWidget);
    expect(find.text('Thrown away'), findsOneWidget);
    expect(find.text('Bought'), findsOneWidget);
    expect(find.text('Mouldy'), findsOneWidget);
  });

  testWidgets('a reversed movement is marked, and both rows stay', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const BatchHistoryScreen(itemId: 'item-1', batchId: batchId),
      overrides: overrides(
        movements: [
          sampleMovement(
            id: 'mv-2',
            kind: StockMovementKind.adjustIn,
            reverses: 'mv-1',
          ),
          sampleMovement(),
        ],
      ),
    );
    await tester.pumpAndSettle();
    // `stock_movements` is append-only (Law L6): the correction points back, the original is struck
    // through, and neither is erased.
    expect(find.text('Reversed'), findsOneWidget);
    expect(find.text('Reverses an earlier movement'), findsOneWidget);
    expect(find.text('Used'), findsOneWidget);
    expect(find.text('Adjusted up'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpInventory(
      tester,
      const BatchHistoryScreen(itemId: 'item-1', batchId: batchId),
      overrides: overrides(
        movements: [
          sampleMovement(
            id: 'mv-2',
            kind: StockMovementKind.waste,
            reason: 'Left out overnight',
          ),
          sampleMovement(),
        ],
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
```

### `test/features/inventory/consume_sheet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/presentation/sheets/consume_sheet.dart';
import 'package:alaya/features/inventory/providers/consume_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/inventory/state/consume_state.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/qty_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

import '../../support/inventory_harness.dart';

/// The capture path's contract: one required field, FEFO named and overridable, and a multi-batch
/// draw declared before it is committed.
void main() {
  List<Override> overrides({List<Batch> fefo = const []}) => [
    consumeFefoProvider(kItem.id).overrideWith((ref) => Stream.value(fefo)),
    unitsInCategoryProvider(
      UnitCategory.weight,
    ).overrideWith((ref) => Stream.value(<Unit>[kKilogram, kGram])),
  ];

  Widget host() => Scaffold(
    body: AlayaBottomSheet(
      child: ConsumeSheet(
        itemId: kItem.id,
        unitCode: 'kg',
        category: UnitCategory.weight,
      ),
    ),
  );

  testWidgets('renders with exactly one required field', (tester) async {
    await pumpInventory(tester, host(), overrides: overrides());
    expect(find.byType(QtyField), findsOneWidget);
    expect(find.text('Use stock'), findsOneWidget);
  });

  testWidgets('offers used, thrown away and expired as three distinct kinds', (
    tester,
  ) async {
    await pumpInventory(tester, host(), overrides: overrides());
    // Three `StockMovementKind`s, not one kind plus a reason string: Phase 7B's waste insight
    // aggregates on the column and cannot read prose.
    expect(find.text('Used'), findsOneWidget);
    expect(find.text('Thrown away'), findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
  });

  testWidgets('an empty batch list simply omits the chip row', (tester) async {
    await pumpInventory(tester, host(), overrides: overrides());
    expect(find.text('Taking from'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FEFO names the batch it will draw from and offers the rest', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      host(),
      overrides: overrides(
        fefo: [
          sampleBatch(id: 'b1', expiry: const DateKey(20260805)),
          sampleBatch(id: 'b2', expiry: const DateKey(20260901)),
        ],
      ),
    );
    expect(find.text('Taking from'), findsOneWidget);
    expect(find.text('Oldest expiry first.'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(2));
  });

  testWidgets('committing with no quantity shakes and says why', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      host(),
      overrides: overrides(fefo: [sampleBatch()]),
    );
    final before = tester
        .widget<ShakeOnError>(find.byType(ShakeOnError))
        .trigger;

    await tester.tap(find.text('Record as used'));
    await tester.pump();

    final after = tester
        .widget<ShakeOnError>(find.byType(ShakeOnError))
        .trigger;
    expect(after, greaterThan(before));
    expect(find.text('Enter a quantity'), findsOneWidget);
  });

  testWidgets('a draw spanning batches is declared before it is committed', (
    tester,
  ) async {
    // Three 1 kg jars and a 2.5 kg draw: the plan crosses three batches, so three movements will be
    // appended and the sheet must say so up front rather than in the history afterwards.
    final container = ProviderContainer(
      overrides: [
        unitsInCategoryProvider(
          UnitCategory.weight,
        ).overrideWith((ref) => Stream.value(<Unit>[kKilogram, kGram])),
      ],
    );
    addTearDown(container.dispose);

    const state = ConsumeState(
      itemId: 'item-1',
      unitCode: 'kg',
      quantity: Qty(2500000, UnitCategory.weight),
    );
    final jars = [
      sampleBatch(id: 'b1', remainingMilli: 1000000),
      sampleBatch(id: 'b2', remainingMilli: 1000000),
      sampleBatch(id: 'b3', remainingMilli: 1000000),
    ];

    final plan = state.planAgainst(jars);
    expect(plan, hasLength(3));
    expect(plan.last.quantity, const Qty(500000, UnitCategory.weight));
    expect(state.shortfallAgainst(jars), isNull);
  });

  testWidgets('a draw larger than the shelf reports a shortfall', (
    tester,
  ) async {
    const state = ConsumeState(
      itemId: 'item-1',
      unitCode: 'kg',
      quantity: Qty(5000000, UnitCategory.weight),
    );
    final jars = [sampleBatch(id: 'b1', remainingMilli: 1000000)];
    expect(
      state.shortfallAgainst(jars),
      const Qty(4000000, UnitCategory.weight),
    );
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpInventory(
      tester,
      host(),
      overrides: overrides(fefo: [sampleBatch()]),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target floor', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpInventory(
      tester,
      host(),
      overrides: overrides(fefo: [sampleBatch()]),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/inventory/inventory_list_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:alaya/features/inventory/presentation/widgets/item_row.dart';
import 'package:alaya/features/inventory/providers/inventory_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/inventory_harness.dart';

/// Four states, 320dp at a doubled text scale, and both accessibility floors (ARCH_5 §9.1).
void main() {
  List<Override> overrides(AsyncValue<List<InventoryGroup>> groups) => [
    clockProvider.overrideWithValue(kInventoryClock),
    inventoryGroupsProvider.overrideWith((ref) => groups),
    itemStocksProvider.overrideWith(
      (ref) => Stream.value(<String, ItemStock>{kItem.id: kStock}),
    ),
    lowStockCountProvider.overrideWith((ref) => 0),
  ];

  final populated = AsyncValue.data([
    InventoryGroup(items: const [kItem], kind: kItem.itemKind),
  ]);

  testWidgets('loading shows a skeleton, not a spinner', (tester) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('empty invites the user to add rather than reporting emptiness', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(const AsyncValue.data([])),
    );
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Add item'), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('populated renders a row showing the summed mixed-unit total', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(populated),
    );
    expect(find.byType(ItemRow), findsOneWidget);
    expect(find.text('Atta'), findsOneWidget);
    // ARCH_1 §5.4's worked example: 250 + 2000 + 1500 + 700 grams is 4 kg 450 g, not 2 kg 450 g.
    expect(find.text('4 kg 450 g'), findsOneWidget);
  });

  testWidgets('the group header names the kind, not the table', (tester) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(populated),
    );
    expect(find.text('Food'), findsOneWidget);
  });

  testWidgets('search is a pinned field, never an app-bar icon', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(populated),
    );
    expect(find.text('Search items'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.search),
      ),
      findsNothing,
    );
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(populated),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(populated),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/inventory/item_detail_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/presentation/screens/item_detail_screen.dart';
import 'package:alaya/features/inventory/presentation/widgets/batch_card.dart';
import 'package:alaya/features/inventory/providers/item_detail_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';

import '../../support/inventory_harness.dart';

/// Four states, plus the two rules this screen exists to demonstrate: the hero is the summed total,
/// and a detached batch explains itself.
void main() {
  const id = 'item-1';

  List<Override> overrides({
    Item? item = kItem,
    List<Batch> batches = const [],
    bool pendingItem = false,
    bool failItem = false,
  }) => [
    clockProvider.overrideWithValue(kInventoryClock),
    // `itemByIdProvider` is a synchronous `Provider<AsyncValue<Item?>>` derived from the
    // catalogue stream, so each state is handed over directly rather than as a Future.
    if (pendingItem)
      itemByIdProvider(id).overrideWith((ref) => const AsyncValue.loading())
    else if (failItem)
      itemByIdProvider(id).overrideWith(
        (ref) => AsyncValue.error(StateError('boom'), StackTrace.empty),
      )
    else
      itemByIdProvider(id).overrideWith((ref) => AsyncValue.data(item)),
    itemStockProvider(id).overrideWith((ref) => Stream.value(kStock)),
    itemBatchesProvider(id).overrideWith((ref) => Stream.value(batches)),
    detailUnitsByCodeProvider.overrideWith(
      (ref) => Stream.value(<String, Unit>{'kg': kKilogram, 'g': kGram}),
    ),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(pendingItem: true),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('a missing item reads as not found, not as a crash', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(item: null),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Not found'), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(failItem: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('the hero is the summed mixed-unit total across every batch', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(batches: [sampleBatch()]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Atta'), findsOneWidget);
    expect(find.text('4 kg 450 g'), findsOneWidget);
    expect(find.byType(BatchCard), findsOneWidget);
  });

  testWidgets('a null value hides its row rather than rendering a dash', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(batches: [sampleBatch()]),
    );
    await tester.pumpAndSettle();
    // kItem has no notes and no low-stock threshold, so neither row exists at all.
    expect(find.text('Note'), findsNothing);
    expect(find.text('Low-stock level'), findsNothing);
    expect(find.byType(KeyValueRow), findsWidgets);
  });

  testWidgets('a detached batch says the receipt is gone', (tester) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(
        batches: [sampleBatch(origin: BatchOrigin.detached)],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Receipt deleted'), findsOneWidget);
  });

  testWidgets('the destructive action is present and is not a filled button', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(batches: [sampleBatch()]),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Delete item'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Delete item'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Delete item'), findsNothing);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(batches: [sampleBatch()]),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(batches: [sampleBatch()]),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/inventory/item_editor_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/presentation/screens/item_editor_screen.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/inventory/state/item_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';

import '../../support/inventory_harness.dart';

/// Four states, plus the Law this screen exists to enforce: `unitCategory` is read-only on edit.
void main() {
  ItemEditorState seed({String? id}) => ItemEditorState(
    id: id,
    name: id == null ? '' : 'Atta',
    unitCategory: UnitCategory.weight,
    displayUnitCode: 'kg',
  );

  // The override goes on the **family**, not on an instance of it: a NotifierProvider family
  // instance has no `overrideWith`, unlike a FutureProvider or StreamProvider instance.
  List<Override> overrides(AsyncValue<ItemEditorState> state) => [
    itemEditorProvider.overrideWith(() => _StubEditor(state)),
    unitsInCategoryProvider(
      UnitCategory.weight,
    ).overrideWith((ref) => Stream.value(<Unit>[kKilogram, kGram])),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('error reads as not found rather than as a blank form', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('a new item opens on the form, which is its empty state', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
    );
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save item'), findsOneWidget);
  });

  testWidgets('creating offers the measure as a control', (tester) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
    );
    expect(find.byType(DropdownButtonFormField<UnitCategory>), findsOneWidget);
    expect(find.byType(KeyValueRow), findsNothing);
  });

  testWidgets('editing locks the measure and says why', (tester) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(itemId: 'item-1'),
      overrides: [
        itemEditorProvider.overrideWith(
          () => _StubEditor(AsyncValue.data(seed(id: 'item-1'))),
        ),
        unitsInCategoryProvider(
          UnitCategory.weight,
        ).overrideWith((ref) => Stream.value(<Unit>[kKilogram, kGram])),
      ],
    );
    // Law L8: no control at all, not a disabled one — and the reason is on screen, because a lock
    // without an explanation reads as a bug.
    expect(find.byType(DropdownButtonFormField<UnitCategory>), findsNothing);
    expect(find.text('Measured in Weight'), findsOneWidget);
    expect(
      find.textContaining('no conversion between weight, volume and count'),
      findsOneWidget,
    );
  });

  testWidgets('the commit lives in the footer, never in the app bar', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
    );
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(TextButton, 'Save item'),
      ),
      findsNothing,
    );
    expect(find.byType(CloseButton), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubEditor extends ItemEditorNotifier {
  _StubEditor(this._state);

  final AsyncValue<ItemEditorState> _state;

  @override
  AsyncValue<ItemEditorState> build(String? arg) => _state;
}
```
