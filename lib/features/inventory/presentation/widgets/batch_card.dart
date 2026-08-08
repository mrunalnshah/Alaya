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
