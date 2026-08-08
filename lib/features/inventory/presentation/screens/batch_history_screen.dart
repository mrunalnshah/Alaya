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
