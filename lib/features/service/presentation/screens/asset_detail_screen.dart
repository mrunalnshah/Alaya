import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/entities/service_record.dart';
import 'package:alaya/features/service/presentation/sheets/dispose_sheet.dart';
import 'package:alaya/features/service/presentation/widgets/asset_row.dart';
import 'package:alaya/features/service/presentation/widgets/contact_action.dart';
import 'package:alaya/features/service/providers/asset_detail_providers.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/asset_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_timeline.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One asset, everything spent on it, and everything that still needs doing (archetype E, outside the
/// shell per U18).
///
/// **A disposed asset opens here exactly as a live one does.** Nothing is deleted (anomaly A30), so the
/// purchase price, the warranty history and every service record survive disposal — which is the whole
/// point of recording a reason instead of a `DELETE`.
class AssetDetailScreen extends ConsumerWidget {
  /// Shows [assetId].
  const AssetDetailScreen({required this.assetId, super.key});

  /// Which asset to show.
  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(assetByIdProvider(assetId));

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: () => context.push(Routes.assetEdit(assetId)),
            tooltip: strings.actionEdit,
            icon: const Icon(Icons.edit_outlined, size: AlayaIconSize.lg),
          ),
        ],
      ),
      body: async.when(
        loading: () =>
            AlayaListSkeleton(label: strings.loadingAssets, hasLeading: false),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(assetsInUseProvider),
        ),
        data: (asset) => asset == null
            ? EmptyState(
                title: strings.errorTitleNotFound,
                body: strings.errorBodyNotFound,
                icon: Icons.search_off_outlined,
              )
            : _Body(asset: asset),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.asset});

  final Asset asset;

  Future<void> _dispose(
    BuildContext context,
    WidgetRef ref,
    String currencyCode,
  ) async {
    final strings = AlayaStrings.of(context);
    final error = await DisposeSheet.show(
      context,
      assetId: asset.id,
      currencyCode: currencyCode,
    );
    if (!context.mounted || error == null) return;
    error.isEmpty
        ? showResultSnack(context, message: strings.disposeDone)
        : showFailureSnack(context, message: error);
  }

  Future<void> _undispose(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final error = await ref.read(assetActionsProvider).undispose(asset.id);
    if (!context.mounted) return;
    error == null
        ? showResultSnack(context, message: strings.undisposeDone)
        : showFailureSnack(context, message: error);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final today = ref.watch(clockProvider).today();
    final digits = ref.watch(serviceDecimalDigitsProvider).valueOrNull ?? 2;
    final currency = ref.watch(serviceCurrencyProvider).valueOrNull ?? 'INR';
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) =>
        DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());
    final person = asset.isServiceProvider;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
            child: _Hero(asset: asset, today: today, decimalDigits: digits),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AlayaSpacing.screenEdge,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (asset.hasContactPhone) ...[
                  SectionHeader(label: strings.assetSectionContact),
                  ContactAction(
                    phone: asset.primaryContactPhone!,
                    name: asset.primaryContactName,
                  ),
                ],
                SectionHeader(label: strings.assetSectionIdentity),
                if (asset.brand != null)
                  KeyValueRow(label: strings.labelBrand, value: asset.brand),
                if (asset.modelNo != null)
                  KeyValueRow(
                    label: strings.labelModelNo,
                    value: asset.modelNo,
                  ),
                if (asset.serialNo != null)
                  KeyValueRow(
                    label: strings.labelSerialNo,
                    value: asset.serialNo,
                  ),
                if (asset.location != null)
                  KeyValueRow(
                    label: strings.labelLocation,
                    value: asset.location,
                  ),
                if (asset.purchaseDateKey != null)
                  KeyValueRow(
                    label: strings.labelPurchased,
                    valueWidget: DateText(
                      asset.purchaseDateKey!,
                      style: DateTextStyle.full,
                    ),
                  ),
                if (asset.warrantyEndDateKey != null) ...[
                  SectionHeader(label: strings.assetSectionWarranty),
                  if (asset.warrantyStartDateKey != null)
                    KeyValueRow(
                      label: strings.labelWarrantyStart,
                      valueWidget: DateText(
                        asset.warrantyStartDateKey!,
                        style: DateTextStyle.full,
                      ),
                    ),
                  KeyValueRow(
                    label: strings.labelWarrantyEnd,
                    valueWidget: DateText(
                      asset.warrantyEndDateKey!,
                      style: DateTextStyle.full,
                    ),
                  ),
                  if (asset.warrantyProvider != null)
                    KeyValueRow(
                      label: strings.labelWarrantyProvider,
                      value: asset.warrantyProvider,
                    ),
                ],
                if (asset.serviceIntervalDays != null ||
                    asset.nextServiceDueDateKey != null) ...[
                  SectionHeader(label: strings.assetSectionService),
                  if (asset.serviceIntervalDays != null)
                    KeyValueRow(
                      label: strings.labelServiceInterval,
                      value: strings.unitDay(asset.serviceIntervalDays!),
                    ),
                  if (asset.nextServiceDueDateKey != null)
                    KeyValueRow(
                      label: strings.labelNextService,
                      valueWidget: DateText(
                        asset.nextServiceDueDateKey!,
                        style: DateTextStyle.full,
                      ),
                    ),
                ],
                const SizedBox(height: AlayaSpacing.md),
                _Lifetime(asset: asset, decimalDigits: digits),
                const SizedBox(height: AlayaSpacing.md),
                Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xxs,
                  children: [
                    if (!asset.isDisposed)
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            context.push(Routes.serviceNew(asset.id)),
                        icon: const Icon(Icons.add, size: AlayaIconSize.sm),
                        label: Text(
                          person
                              ? strings.actionAddSalary
                              : strings.actionAddService,
                        ),
                      ),
                    if (asset.isDisposed)
                      TextButton.icon(
                        onPressed: () => _undispose(context, ref),
                        icon: const Icon(Icons.undo, size: AlayaIconSize.sm),
                        label: Text(strings.actionUndispose),
                      )
                    else
                      TextButton.icon(
                        onPressed: () => _dispose(context, ref, currency),
                        icon: const Icon(
                          Icons.archive_outlined,
                          size: AlayaIconSize.sm,
                        ),
                        label: Text(strings.actionDispose),
                      ),
                  ],
                ),
                SectionHeader(
                  label: person
                      ? strings.assetSectionSalary
                      : strings.assetSectionService,
                  padding: const EdgeInsets.only(
                    top: AlayaSpacing.xl,
                    bottom: AlayaSpacing.xs,
                  ),
                ),
              ],
            ),
          ),
        ),
        _History(asset: asset, decimalDigits: digits, format: format),
        const SliverToBoxAdapter(child: SizedBox(height: AlayaSpacing.xxxl)),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.asset,
    required this.today,
    required this.decimalDigits,
  });

  final Asset asset;
  final DateKey today;
  final int decimalDigits;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final price = asset.purchasePrice;

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                AssetRowTile.glyphFor(asset.type),
                size: AlayaIconSize.xl,
                color: semantic.muted,
              ),
              const SizedBox(width: AlayaSpacing.sm),
              Expanded(
                child: Text(
                  asset.name,
                  style: AlayaTypography.screenTitle.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AlayaSpacing.sm),
          if (price != null)
            AmountText(price, showSign: false, decimalDigits: decimalDigits),
          const SizedBox(height: AlayaSpacing.xs),
          // Warranty and service state, derived on every build. A disposed asset says so first,
          // because everything else about it is history.
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xxs,
            children: [
              if (asset.isDisposed)
                StatusChip(label: strings.assetDisposedChip)
              else if (asset.status == AssetStatus.underRepair)
                StatusChip(
                  label: strings.assetUnderRepair,
                  tone: StatusTone.warning,
                ),
              if (!asset.isDisposed && asset.warrantyEndDateKey != null)
                if (!asset.isUnderWarranty(today))
                  StatusChip(label: strings.assetWarrantyExpired)
                else if (asset.isWarrantyEndingWithin(
                  today,
                  AssetRowTile.soonDays,
                ))
                  StatusChip(
                    label: strings.assetWarrantyEnding,
                    tone: StatusTone.warning,
                  )
                else
                  StatusChip(
                    label: strings.assetUnderWarranty,
                    tone: StatusTone.success,
                  ),
              if (!asset.isDisposed && asset.isServiceOverdue(today))
                StatusChip(
                  label: strings.assetServiceDue,
                  tone: StatusTone.danger,
                ),
              if (asset.linkedRecurringTemplateId != null)
                StatusChip(
                  label: strings.assetLinkedRecurring,
                  tone: StatusTone.info,
                ),
            ],
          ),
          if (asset.isDisposed && asset.disposedAtDateKey != null) ...[
            const SizedBox(height: AlayaSpacing.xs),
            Wrap(
              spacing: AlayaSpacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  strings.labelDisposalDate,
                  style: AlayaTypography.caption.copyWith(
                    color: semantic.muted,
                  ),
                ),
                DateText(
                  asset.disposedAtDateKey!,
                  style: DateTextStyle.full,
                  muted: true,
                ),
                if (asset.disposalAmount != null)
                  AmountText(
                    asset.disposalAmount!,
                    size: AmountSize.small,
                    showSign: false,
                    decimalDigits: decimalDigits,
                    muted: true,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Lifetime extends ConsumerWidget {
  const _Lifetime({required this.asset, required this.decimalDigits});

  final Asset asset;
  final int decimalDigits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final async = ref.watch(lifetimeServiceCostProvider(asset.id));
    final totals = async.valueOrNull;
    if (totals == null || totals.isEmpty) return const SizedBox.shrink();

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            asset.isServiceProvider
                ? strings.assetLifetimeSalary
                : strings.assetLifetimeCost,
            style: AlayaTypography.label.copyWith(color: semantic.muted),
          ),
          const SizedBox(height: AlayaSpacing.xxs),
          // One figure per currency, never summed. Adding two currencies would invent an exchange rate
          // the user never agreed to (Law L1).
          Wrap(
            spacing: AlayaSpacing.sm,
            runSpacing: AlayaSpacing.xxs,
            children: [
              for (final total in totals.values)
                AmountText(
                  total,
                  showSign: false,
                  decimalDigits: decimalDigits,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Resolves a [ServiceRecordType] to its ARB label.
///
/// Public and in one place because the timeline and the editor both name these, and two switches over
/// the same enum drift the moment a value is added (ARCH_4 R38).
class ServiceTypeLabels {
  const ServiceTypeLabels._();

  /// The label for [type].
  static String of(AlayaStrings strings, ServiceRecordType type) =>
      switch (type) {
        ServiceRecordType.service => strings.serviceTypeService,
        ServiceRecordType.repair => strings.serviceTypeRepair,
        ServiceRecordType.maintenance => strings.serviceTypeMaintenance,
        ServiceRecordType.inspection => strings.serviceTypeInspection,
        ServiceRecordType.salaryPaid => strings.serviceTypeSalaryPaid,
        ServiceRecordType.other => strings.serviceTypeOther,
      };
}

class _History extends ConsumerWidget {
  const _History({
    required this.asset,
    required this.decimalDigits,
    required this.format,
  });

  final Asset asset;
  final int decimalDigits;
  final String Function(DateKey) format;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(serviceRecordsProvider(asset.id));

    return async.when(
      loading: () => SliverToBoxAdapter(
        child: AlayaListSkeleton(label: strings.loadingAssets),
      ),
      error: (error, stack) => SliverToBoxAdapter(
        child: ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(serviceRecordsProvider(asset.id)),
        ),
      ),
      data: (records) {
        if (records.isEmpty) {
          return SliverToBoxAdapter(
            child: EmptyState(
              title: strings.emptyTitleNoOccurrences,
              body: strings.emptyBodyNoServices,
              icon: Icons.build_outlined,
            ),
          );
        }
        final ordered = [...records]
          ..sort((a, b) => b.serviceDateKey.compareTo(a.serviceDateKey));
        return AlayaTimeline(
          itemCount: ordered.length,
          itemBuilder: (context, index) {
            final record = ordered[index];
            final cost = record.cost;
            return AlayaTimelineEntry(
              title: ServiceTypeLabels.of(strings, record.type),
              trailing: cost == null
                  ? const SizedBox.shrink()
                  : AmountText(
                      cost,
                      size: AmountSize.small,
                      showSign: false,
                      decimalDigits: decimalDigits,
                    ),
              subtitle: DateText(
                record.serviceDateKey,
                style: DateTextStyle.medium,
                muted: true,
              ),
              meta: record.providerName ?? record.notes,
              icon: record.type == ServiceRecordType.salaryPaid
                  ? Icons.payments_outlined
                  : Icons.build_outlined,
              tone: record.type == ServiceRecordType.repair
                  ? TimelineTone.outgoing
                  : TimelineTone.neutral,
              // **No badge.** With the expense toggle on by default, a service that reached the ledger
              // is the rule rather than the exception, and a chip on every row is noise. Marking the
              // inverse — the rare record that did *not* create a transaction — would carry real
              // information, but that is a different design and not one that was asked for.
              badge: null,
              onTap: () =>
                  context.push(Routes.serviceEdit(asset.id, record.id)),
            );
          },
        );
      },
    );
  }
}
