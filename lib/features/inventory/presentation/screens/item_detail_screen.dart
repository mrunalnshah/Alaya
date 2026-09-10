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
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/inventory/presentation/sheets/consume_sheet.dart';
import 'package:alaya/features/inventory/presentation/widgets/batch_card.dart';
import 'package:alaya/features/inventory/presentation/widgets/kind_display.dart';
import 'package:alaya/features/inventory/providers/inventory_list_providers.dart';
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
    final kinds =
        ref.watch(inventoryKindsProvider).valueOrNull ?? const <Tag>[];

    // A loop rather than `firstOrNull`, which lives in `package:collection` and is imported nowhere in this
    // feature. `settle_up_sheet`'s `accountFor` is the same shape for the same reason.
    Tag? kindFor(String? id) {
      if (id == null) return null;
      for (final kind in kinds) {
        if (kind.id == id) return kind;
      }
      return null;
    }

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
              // Resolved from the kinds list rather than read off the item, because a kind is a row now and
              // its name can change. `KindDisplay` renders "No kind" when the item has none or its tag is
              // gone — the same sentence the list's unfiled group uses.
              value: KindDisplay.labelFor(strings, kindFor(item.kindTagId)),
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
