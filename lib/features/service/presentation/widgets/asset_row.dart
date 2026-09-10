import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One asset: what it is, what it cost, and what needs attention.
///
/// **Warranty and service state are derived on every build, never stored.** `isUnderWarranty(today)`
/// and `isServiceOverdue(today)` are asked of the entity, because a stored flag is wrong the moment
/// midnight passes with the app closed (ARCH_2 §12.2).
///
/// Three tiers rather than one line: the figure, then the chips, then nothing else. A `Row` pairing the
/// name with the price would starve the name at a doubled text scale (Law U21).
class AssetRowTile extends StatelessWidget {
  /// Creates the row.
  const AssetRowTile({
    required this.asset,
    required this.today,
    required this.decimalDigits,
    required this.onTap,
    super.key,
  });

  /// The asset.
  final Asset asset;

  /// Today, for the warranty and service derivations.
  final DateKey today;

  /// The currency's precision.
  final int decimalDigits;

  /// Opens the detail screen.
  final VoidCallback onTap;

  /// How many days ahead counts as "soon" for a warranty or a service.
  static const int soonDays = 30;

  static IconData glyphFor(AssetType type) => switch (type) {
    AssetType.appliance => Icons.kitchen_outlined,
    AssetType.electronics => Icons.devices_outlined,
    AssetType.vehicle => Icons.directions_car_outlined,
    AssetType.furniture => Icons.chair_outlined,
    AssetType.property => Icons.home_outlined,
    // A person, not a thing — and the glyph says so before any label does.
    AssetType.serviceProvider => Icons.person_outline,
    AssetType.subscription => Icons.card_membership_outlined,
    AssetType.other => Icons.inventory_2_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final price = asset.purchasePrice;

    final chips = <Widget>[
      if (asset.isDisposed)
        StatusChip(label: strings.assetDisposedChip)
      else if (asset.status == AssetStatus.underRepair)
        StatusChip(label: strings.assetUnderRepair, tone: StatusTone.warning),
      if (!asset.isDisposed) ...[
        if (asset.isServiceOverdue(today))
          StatusChip(label: strings.assetServiceDue, tone: StatusTone.danger)
        else if (asset.nextServiceDueDateKey != null &&
            (asset.serviceDaysLeftFrom(today) ?? soonDays + 1) <= soonDays)
          StatusChip(label: strings.assetServiceSoon, tone: StatusTone.warning),
        if (asset.warrantyEndDateKey != null)
          if (!asset.isUnderWarranty(today))
            StatusChip(label: strings.assetWarrantyExpired)
          else if (asset.isWarrantyEndingWithin(today, soonDays))
            StatusChip(
              label: strings.assetWarrantyEnding,
              tone: StatusTone.warning,
            )
          else
            StatusChip(
              label: strings.assetUnderWarranty,
              tone: StatusTone.success,
            ),
        if (asset.linkedRecurringTemplateId != null)
          StatusChip(
            label: strings.assetLinkedRecurring,
            tone: StatusTone.info,
          ),
      ],
    ];

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlayaSpacing.screenEdge,
            vertical: AlayaSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    glyphFor(asset.type),
                    size: AlayaIconSize.lg,
                    color: asset.isDisposed ? semantic.muted : semantic.muted,
                  ),
                  const SizedBox(width: AlayaSpacing.sm),
                  Expanded(
                    child: Text(
                      asset.name,
                      style: AlayaTypography.body.copyWith(
                        color: asset.isDisposed
                            ? semantic.muted
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: AlayaIconSize.lg + AlayaSpacing.sm,
                  top: AlayaSpacing.xxs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (price != null)
                      AmountText(
                        price,
                        size: AmountSize.small,
                        showSign: false,
                        decimalDigits: decimalDigits,
                        muted: asset.isDisposed,
                      ),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: AlayaSpacing.xs),
                      Wrap(
                        spacing: AlayaSpacing.xs,
                        runSpacing: AlayaSpacing.xxs,
                        children: chips,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
