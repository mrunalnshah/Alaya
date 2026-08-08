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
