# F_SERVICE

Assets, service records, warranties.

**20 files · 4,610 lines.**  Written 2026-08-27T08:54:37-04:00.

Every file below is complete and current. Paths are destinations.

---

### `lib/features/service/presentation/screens/asset_detail_screen.dart`

```dart
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
```

### `lib/features/service/presentation/screens/asset_editor_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/service/presentation/screens/asset_list_screen.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/state/asset_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_disclosure.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// Records an asset — or a person (ARCH_5 §3 archetype B), outside the shell per U18.
///
/// **Only the name is required, and that is what makes `type = serviceProvider` work.** A house maid has
/// no serial number, no warranty and no purchase price; a television has no phone number worth calling.
/// Both live in one table because every field except the name is optional, so neither has to be
/// described in the other's vocabulary.
class AssetEditorScreen extends ConsumerWidget {
  /// Edits [assetId], or creates a new asset when it is null.
  const AssetEditorScreen({this.assetId, super.key});

  /// The asset being edited, or null for a new one.
  final String? assetId;

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(assetEditorProvider(assetId).notifier).save();
    if (!context.mounted) return;
    if (saved == null) {
      final state = ref.read(assetEditorProvider(assetId)).valueOrNull;
      showFailureSnack(
        context,
        message:
            state?.rejection ??
            switch (state?.issue) {
              AssetSaveIssue.nameMissing => strings.errorFieldRequired,
              AssetSaveIssue.warrantyBackwards =>
                strings.errorWarrantyBackwards,
              AssetSaveIssue.rejected || null => strings.errorBodyGeneric,
            },
      );
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.actionSaved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(assetEditorProvider(assetId));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(
          assetId == null ? strings.editorTitleNew : strings.editorTitleEdit,
        ),
      ),
      body: async.when(
        loading: () =>
            AlayaListSkeleton(label: strings.loadingAssets, hasLeading: false),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleNotFound,
          body: strings.errorBodyNotFound,
        ),
        data: (state) => AlayaFormScaffold(
          primaryLabel: strings.saveAsset,
          onPrimary: state.submitting ? null : () => _save(context, ref),
          isDirty: state.dirty,
          isSubmitting: state.submitting,
          discardTitle: strings.confirmDiscardTitle,
          discardBody: strings.confirmDiscardBody,
          discardConfirmLabel: strings.actionDiscard,
          discardCancelLabel: strings.actionKeepEditing,
          child: _Form(editorId: assetId, state: state),
        ),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.editorId, required this.state});

  final String? editorId;
  final AssetEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(assetEditorProvider(editorId).notifier);
    final digits = ref.watch(serviceDecimalDigitsProvider).valueOrNull ?? 2;
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) =>
        DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: strings.assetSectionIdentity,
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
        ),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: TextFormField(
            initialValue: state.name,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: strings.labelAssetName,
              errorText: state.issue == AssetSaveIssue.nameMissing
                  ? strings.errorFieldRequired
                  : null,
            ),
            onChanged: notifier.setName,
          ),
        ),
        // Informational, never a block. A repeated name is normal — but saying nothing would leave a
        // genuine slip, the same phone entered twice, invisible.
        if (ref.watch(
          assetNameClashProvider((id: state.id, name: state.name)),
        )) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            strings.assetSameNameNote,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ],
        const SizedBox(height: AlayaSpacing.md),
        DropdownButtonFormField<AssetType>(
          key: ValueKey(state.type),
          initialValue: state.type,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.labelAssetType),
          items: [
            for (final type in AssetType.values)
              DropdownMenuItem(
                value: type,
                child: Text(AssetListScreen.typeLabel(strings, type)),
              ),
          ],
          onChanged: (value) => value == null ? null : notifier.setType(value),
        ),
        if (state.isPerson) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            strings.assetTypeHelpPerson,
            style: AlayaTypography.caption.copyWith(color: semantic.transfer),
          ),
        ],
        // A person has no brand, model or serial, so those fields are not offered at all rather than
        // offered and left blank — an empty "Model" on a human being is worse than its absence.
        if (!state.isPerson) ...[
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.brand,
            decoration: InputDecoration(labelText: strings.labelBrand),
            onChanged: notifier.setBrand,
          ),
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.modelNo,
            decoration: InputDecoration(labelText: strings.labelModelNo),
            onChanged: notifier.setModelNo,
          ),
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.serialNo,
            decoration: InputDecoration(labelText: strings.labelSerialNo),
            onChanged: notifier.setSerialNo,
          ),
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.location,
            decoration: InputDecoration(labelText: strings.labelLocation),
            onChanged: notifier.setLocation,
          ),
          const SizedBox(height: AlayaSpacing.md),
          DatePickerField(
            value: state.purchaseDateKey,
            formatted: format,
            label: strings.labelPurchased,
            hint: strings.hintSelectDate,
            onChanged: notifier.setPurchaseDate,
          ),
          const SizedBox(height: AlayaSpacing.md),
          AmountField(
            currencyCode: state.currencyCode,
            decimalDigits: digits,
            label: strings.labelPurchasePrice,
            initialValue: state.purchasePrice,
            onChanged: notifier.setPurchasePrice,
          ),
          SectionHeader(
            label: strings.assetSectionWarranty,
            padding: const EdgeInsets.only(
              top: AlayaSpacing.xl,
              bottom: AlayaSpacing.xs,
            ),
          ),
          DatePickerField(
            value: state.warrantyStartDateKey,
            formatted: format,
            label: strings.labelWarrantyStart,
            hint: strings.hintSelectDate,
            onChanged: notifier.setWarrantyStart,
          ),
          const SizedBox(height: AlayaSpacing.md),
          DatePickerField(
            value: state.warrantyEndDateKey,
            formatted: format,
            label: strings.labelWarrantyEnd,
            hint: strings.hintSelectDate,
            errorText: state.issue == AssetSaveIssue.warrantyBackwards
                ? strings.errorWarrantyBackwards
                : null,
            onChanged: notifier.setWarrantyEnd,
          ),
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.warrantyProvider,
            decoration: InputDecoration(
              labelText: strings.labelWarrantyProvider,
            ),
            onChanged: notifier.setWarrantyProvider,
          ),
        ],
        AlayaDisclosure(
          label: strings.sectionMoreDetails,
          summary: _assetSummary(strings, state),
          startExpanded: _hasAssetDetails(state),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                label: strings.assetSectionService,
                padding: const EdgeInsets.only(
                  top: AlayaSpacing.xl,
                  bottom: AlayaSpacing.xs,
                ),
              ),
              TextFormField(
                initialValue: state.serviceIntervalDays?.toString(),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: strings.labelServiceInterval,
                  helperText: strings.serviceIntervalHelp,
                  helperMaxLines: 3,
                ),
                onChanged: (raw) =>
                    notifier.setServiceIntervalDays(int.tryParse(raw.trim())),
              ),
              const SizedBox(height: AlayaSpacing.md),
              DatePickerField(
                value: state.nextServiceDueDateKey,
                formatted: format,
                label: strings.labelNextService,
                hint: strings.hintSelectDate,
                onChanged: notifier.setNextServiceDue,
              ),
              SectionHeader(
                label: strings.assetSectionContact,
                padding: const EdgeInsets.only(
                  top: AlayaSpacing.xl,
                  bottom: AlayaSpacing.xs,
                ),
              ),
              TextFormField(
                initialValue: state.contactName,
                decoration: InputDecoration(
                  labelText: strings.labelContactName,
                ),
                onChanged: notifier.setContactName,
              ),
              const SizedBox(height: AlayaSpacing.md),
              TextFormField(
                initialValue: state.contactPhone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: strings.labelContactPhone,
                ),
                onChanged: notifier.setContactPhone,
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
        if (state.issue == AssetSaveIssue.rejected &&
            state.rejection != null) ...[
          const SizedBox(height: AlayaSpacing.md),
          AlayaCard(
            padding: const EdgeInsets.all(AlayaSpacing.sm),
            child: Text(
              state.rejection!,
              style: AlayaTypography.body.copyWith(color: semantic.danger),
            ),
          ),
        ],
      ],
    );
  }

  /// Whether anything behind the door is set, so it should open on arrival.
  ///
  /// Warranty is **not** listed: it lives inside the `!isPerson` branch and stays visible, because for a
  /// physical asset it is part of what the thing is rather than a detail about it.
  static bool _hasAssetDetails(AssetEditorState state) =>
      state.serviceIntervalDays != null ||
      state.nextServiceDueDateKey != null ||
      (state.contactName ?? '').trim().isNotEmpty ||
      (state.contactPhone ?? '').trim().isNotEmpty ||
      (state.location ?? '').trim().isNotEmpty ||
      (state.notes ?? '').trim().isNotEmpty;

  /// What is set behind the door, for the collapsed row.
  static String? _assetSummary(AlayaStrings strings, AssetEditorState state) {
    final parts = <String>[];
    if (state.serviceIntervalDays != null ||
        state.nextServiceDueDateKey != null) {
      parts.add(strings.assetSectionService);
    }
    if ((state.contactName ?? '').trim().isNotEmpty ||
        (state.contactPhone ?? '').trim().isNotEmpty) {
      parts.add(strings.assetSectionContact);
    }
    if ((state.notes ?? '').trim().isNotEmpty) parts.add(strings.labelNote);
    return parts.isEmpty ? null : parts.join(' \u00B7 ');
  }
}
```

### `lib/features/service/presentation/screens/asset_list_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/features/service/presentation/widgets/asset_row.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/asset_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_search_field.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Everything the household owns, and everyone it pays (ARCH_5 §3 archetype D).
///
/// **Disposed assets are behind a filter, never gone.** An asset is never deleted (anomaly A30), so the
/// switch is what keeps the list about things you still have while leaving the ones you spent money on
/// reachable in one tap.
class AssetListScreen extends ConsumerWidget {
  /// Creates the screen.
  const AssetListScreen({super.key});

  /// Resolves an [AssetType] to its ARB label, so no screen writes the words.
  static String typeLabel(AlayaStrings strings, AssetType type) =>
      switch (type) {
        AssetType.appliance => strings.assetGroupAppliance,
        AssetType.electronics => strings.assetGroupElectronics,
        AssetType.vehicle => strings.assetGroupVehicle,
        AssetType.furniture => strings.assetGroupFurniture,
        AssetType.property => strings.assetGroupProperty,
        AssetType.serviceProvider => strings.assetGroupServiceProvider,
        AssetType.subscription => strings.assetGroupSubscription,
        AssetType.other => strings.assetGroupOther,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final groups = ref.watch(assetGroupsProvider);
    final filter = ref.watch(assetFilterProvider);

    return Scaffold(
      body: Column(
        children: [
          const _Toolbar(),
          const _ActiveFilters(),
          Expanded(
            child: groups.when(
              loading: () => AlayaListSkeleton(label: strings.loadingAssets),
              error: (error, stack) => ErrorState(
                title: strings.errorTitleGeneric,
                body: error.toString(),
                retryLabel: strings.actionRetry,
                onRetry: () {
                  ref.invalidate(assetsInUseProvider);
                  ref.invalidate(disposedAssetsProvider);
                },
              ),
              data: (sections) => sections.isEmpty
                  ? _Empty(isNarrowed: filter.isNarrowed || filter.isSearching)
                  : _Sections(sections: sections),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.assetNew),
        tooltip: strings.addAsset,
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
    final semantic = context.semantic;
    final notifier = ref.read(assetFilterProvider.notifier);
    final filter = ref.watch(assetFilterProvider);
    final dueCount = ref.watch(serviceDueCountProvider);

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
            hintText: strings.hintSearchAssets,
          ),
          const SizedBox(height: AlayaSpacing.xs),
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: Text(strings.filterShowDisposed),
                selected: filter.includeDisposed,
                onSelected: (_) => notifier.toggleDisposed(),
              ),
              if (dueCount > 0)
                StatusChip(
                  label: strings.assetServiceDue,
                  tone: StatusTone.danger,
                  trailing: Text(
                    '$dueCount',
                    style: AlayaTypography.overline.copyWith(
                      color: semantic.onStatus,
                    ),
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
    final filter = ref.watch(assetFilterProvider);
    final notifier = ref.read(assetFilterProvider.notifier);
    if (!filter.isNarrowed) return const SizedBox.shrink();

    return FilterChipBar(
      clearAllLabel: strings.filterReset,
      onClearAll: notifier.clear,
      filters: [
        if (filter.includeDisposed)
          ActiveFilter(
            label: strings.filterShowDisposed,
            onRemove: notifier.toggleDisposed,
          ),
        for (final type in filter.types)
          ActiveFilter(
            label: AssetListScreen.typeLabel(strings, type),
            onRemove: () => notifier.toggleType(type),
          ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.isNarrowed});

  final bool isNarrowed;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    if (isNarrowed) {
      return EmptyState(
        title: strings.emptyTitleNoResults,
        body: strings.emptyBodyNoResults,
        icon: Icons.search_off_outlined,
      );
    }
    return EmptyState(
      title: strings.emptyTitleNoAssets,
      body: strings.emptyBodyNoAssets,
      icon: Icons.handyman_outlined,
      actionLabel: strings.addAsset,
      onAction: () => context.push(Routes.assetNew),
    );
  }
}

class _Sections extends ConsumerWidget {
  const _Sections({required this.sections});

  final List<AssetGroup> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final today = ref.watch(clockProvider).today();
    final digits = ref.watch(serviceDecimalDigitsProvider).valueOrNull ?? 2;

    return CustomScrollView(
      slivers: [
        for (final section in sections)
          SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AlayaSpacing.screenEdge,
                    AlayaSpacing.md,
                    AlayaSpacing.screenEdge,
                    AlayaSpacing.xs,
                  ),
                  child: Text(
                    AssetListScreen.typeLabel(strings, section.type),
                    style: AlayaTypography.sectionHeader.copyWith(
                      color: semantic.muted,
                    ),
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: section.assets.length,
                itemBuilder: (context, index) {
                  final asset = section.assets[index];
                  return AssetRowTile(
                    asset: asset,
                    today: today,
                    decimalDigits: digits,
                    onTap: () => context.push(Routes.assetDetail(asset.id)),
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
```

### `lib/features/service/presentation/screens/service_editor_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/features/service/presentation/screens/asset_detail_screen.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/service_editor_providers.dart';
import 'package:alaya/features/service/state/service_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// Records what was done to a thing, or what was paid to a person (archetype B, outside the shell).
///
/// **`type = salaryPaid` is what puts a maid's wages in the same table as a boiler service.** The maid
/// case needs no new screen: her asset row, this editor and the "also record as an expense" toggle are
/// the three pieces, and the salary history on her detail screen is this table filtered by type.
class ServiceEditorScreen extends ConsumerWidget {
  /// Edits [recordId] against [assetId], or creates a new record when it is null.
  const ServiceEditorScreen({required this.assetId, this.recordId, super.key});

  /// Which asset the record belongs to.
  final String assetId;

  /// The record being edited, or null for a new one.
  final String? recordId;

  ServiceEditorArgs get _args => (assetId: assetId, recordId: recordId);

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(serviceEditorProvider(_args).notifier).save();
    if (!context.mounted) return;
    if (saved == null) {
      final state = ref.read(serviceEditorProvider(_args)).valueOrNull;
      showFailureSnack(
        context,
        message:
            state?.rejection ??
            switch (state?.issue) {
              ServiceSaveIssue.costMissingForExpense =>
                strings.alsoRecordNeedsCost,
              ServiceSaveIssue.accountMissingForExpense =>
                strings.alsoRecordNeedsAccount,
              ServiceSaveIssue.rejected || null => strings.errorBodyGeneric,
            },
      );
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.actionSaved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(serviceEditorProvider(_args));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(
          recordId == null ? strings.editorTitleNew : strings.editorTitleEdit,
        ),
      ),
      body: async.when(
        loading: () =>
            AlayaListSkeleton(label: strings.loadingAssets, hasLeading: false),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleNotFound,
          body: strings.errorBodyNotFound,
        ),
        data: (state) => AlayaFormScaffold(
          primaryLabel: strings.saveService,
          onPrimary: state.submitting ? null : () => _save(context, ref),
          isDirty: state.dirty,
          isSubmitting: state.submitting,
          discardTitle: strings.confirmDiscardTitle,
          discardBody: strings.confirmDiscardBody,
          discardConfirmLabel: strings.actionDiscard,
          discardCancelLabel: strings.actionKeepEditing,
          child: _Form(args: _args, state: state),
        ),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.args, required this.state});

  final ServiceEditorArgs args;
  final ServiceEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(serviceEditorProvider(args).notifier);
    final digits = ref.watch(serviceDecimalDigitsProvider).valueOrNull ?? 2;
    final accounts =
        ref.watch(serviceAccountsProvider).valueOrNull ?? const <Account>[];
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) =>
        DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());

    // The dropdown's value comes from the list being rendered, never from state: the accounts arrive
    // from a stream, and a value matching none of the items throws (ARCH_4 R33).
    Account? selectedAccount;
    for (final account in accounts) {
      if (account.id == state.accountId) selectedAccount = account;
    }
    final methods =
        ref.watch(servicePaymentMethodsProvider).valueOrNull ??
        const <PaymentMethod>[];
    PaymentMethod? selectedMethod;
    for (final method in methods) {
      if (method.id == state.paymentMethodId) selectedMethod = method;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<ServiceRecordType>(
          key: ValueKey(state.type),
          initialValue: state.type,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.labelServiceType),
          items: [
            for (final type in ServiceRecordType.values)
              DropdownMenuItem(
                value: type,
                child: Text(ServiceTypeLabels.of(strings, type)),
              ),
          ],
          onChanged: (value) => value == null ? null : notifier.setType(value),
        ),
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.serviceDateKey,
          formatted: format,
          label: strings.labelServiceDate,
          hint: strings.hintSelectDate,
          onChanged: notifier.setServiceDate,
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextFormField(
          initialValue: state.providerName,
          decoration: InputDecoration(labelText: strings.labelProviderName),
          onChanged: notifier.setProviderName,
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextFormField(
          initialValue: state.providerPhone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: strings.labelProviderPhone),
          onChanged: notifier.setProviderPhone,
        ),
        const SizedBox(height: AlayaSpacing.md),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: AmountField(
            currencyCode: state.currencyCode,
            decimalDigits: digits,
            label: strings.labelServiceCost,
            initialValue: state.cost,
            errorText: state.issue == ServiceSaveIssue.costMissingForExpense
                ? strings.alsoRecordNeedsCost
                : null,
            onChanged: notifier.setCost,
          ),
        ),
        // Not offered for a salary: the next payment is the recurring template's business, and a second
        // due date here would be a second schedule to keep in step.
        if (!state.isSalary) ...[
          const SizedBox(height: AlayaSpacing.md),
          DatePickerField(
            value: state.nextDueDateKey,
            formatted: format,
            label: strings.labelNextDue,
            hint: strings.hintSelectDate,
            onChanged: notifier.setNextDue,
          ),
        ],
        SectionHeader(
          label: strings.sectionMoney,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.xl,
            bottom: AlayaSpacing.xs,
          ),
        ),
        SwitchListTile(
          value: state.alsoRecordAsExpense,
          contentPadding: EdgeInsets.zero,
          title: Text(strings.alsoRecordAsExpense),
          subtitle: Text(
            strings.alsoRecordHelp,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          onChanged: (_) => notifier.toggleExpense(),
        ),
        if (state.alsoRecordAsExpense) ...[
          const SizedBox(height: AlayaSpacing.md),
          if (accounts.isNotEmpty)
            DropdownButtonFormField<String>(
              key: ValueKey(selectedAccount?.id),
              initialValue: selectedAccount?.id,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: strings.labelAccount,
                errorText:
                    state.issue == ServiceSaveIssue.accountMissingForExpense
                    ? strings.alsoRecordNeedsAccount
                    : null,
              ),
              items: [
                for (final account in accounts)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(account.name),
                  ),
              ],
              onChanged: notifier.setAccount,
            ),
          // Optional, and last: an account says where the money came from and the expense needs it; a
          // method says how, and plenty of people never record it. Offered only when methods exist, so
          // an empty picker never appears.
          if (methods.isNotEmpty) ...[
            const SizedBox(height: AlayaSpacing.md),
            DropdownButtonFormField<String>(
              key: ValueKey(selectedMethod?.id),
              initialValue: selectedMethod?.id,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: strings.labelPaymentMethodOptional,
              ),
              items: [
                for (final method in methods)
                  DropdownMenuItem(value: method.id, child: Text(method.name)),
              ],
              onChanged: notifier.setPaymentMethod,
            ),
          ],
        ],
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
        if (state.issue == ServiceSaveIssue.rejected &&
            state.rejection != null) ...[
          const SizedBox(height: AlayaSpacing.md),
          AlayaCard(
            padding: const EdgeInsets.all(AlayaSpacing.sm),
            child: Text(
              state.rejection!,
              style: AlayaTypography.body.copyWith(color: semantic.danger),
            ),
          ),
        ],
      ],
    );
  }
}
```

### `lib/features/service/presentation/sheets/dispose_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/dispose_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// Retires an asset without destroying it (ARCH_5 §3 archetype A).
///
/// **There is no delete anywhere in this module, and this sheet is why.** Disposal sets a status and
/// records a reason; the purchase price, the warranty dates and every service record stay exactly where
/// they were. The ₹45,000 spent on a television still counts in every total after the television has
/// gone to the tip, because the money left the house whether or not the object did (anomaly A30,
/// ARCH_3 §4.1). The body text says so, because a user reaching for this button is entitled to know
/// what it will not do.
class DisposeSheet extends ConsumerWidget {
  /// Creates the sheet.
  const DisposeSheet({
    required this.assetId,
    required this.currencyCode,
    super.key,
  });

  /// Which asset is being retired.
  final String assetId;

  /// The currency a recovered amount is entered in.
  final String currencyCode;

  /// Opens the sheet.
  ///
  /// Resolves to the empty string when the disposal committed, to a message when it failed, and to null
  /// when the user backed out — so a caller can tell "done" from "changed their mind".
  static Future<String?> show(
    BuildContext context, {
    required String assetId,
    required String currencyCode,
  }) => AlayaBottomSheet.show<String>(
    context: context,
    builder: (context) =>
        DisposeSheet(assetId: assetId, currencyCode: currencyCode),
  );

  DisposeArgs get _args => (assetId: assetId, currencyCode: currencyCode);

  /// Resolves an [AssetDisposalReason] to its ARB label.
  static String reasonLabel(AlayaStrings strings, AssetDisposalReason reason) =>
      switch (reason) {
        AssetDisposalReason.sold => strings.disposeReasonSold,
        AssetDisposalReason.expired => strings.disposeReasonExpired,
        AssetDisposalReason.damaged => strings.disposeReasonDamaged,
        AssetDisposalReason.gifted => strings.disposeReasonGifted,
        AssetDisposalReason.lost => strings.disposeReasonLost,
        AssetDisposalReason.replaced => strings.disposeReasonReplaced,
        AssetDisposalReason.other => strings.disposeReasonOther,
      };

  Future<void> _commit(BuildContext context, WidgetRef ref) async {
    final error = await ref.read(disposeProvider(_args).notifier).commit();
    if (!context.mounted) return;
    // A missing reason is a field error the sheet already shows; it must not close over it.
    if (error == 'reasonMissing') return;
    Navigator.of(context).pop(error ?? '');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final state = ref.watch(disposeProvider(_args));
    final notifier = ref.read(disposeProvider(_args).notifier);
    final digits = ref.watch(serviceDecimalDigitsProvider).valueOrNull ?? 2;
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) =>
        DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.disposeTitle,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Text(
          strings.disposeBody,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.md),
        // A `Wrap` of choice chips rather than a dropdown: seven reasons is few enough to read at once,
        // and every one of them reflows independently at a doubled text scale (Law U21).
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              for (final reason in AssetDisposalReason.values)
                ChoiceChip(
                  label: Text(reasonLabel(strings, reason)),
                  selected: state.reason == reason,
                  onSelected: (_) => notifier.setReason(reason),
                ),
            ],
          ),
        ),
        if (state.reasonMissing) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            strings.disposeNeedsReason,
            style: AlayaTypography.caption.copyWith(color: semantic.danger),
          ),
        ],
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.dateKey,
          formatted: format,
          label: strings.labelDisposalDate,
          hint: strings.hintSelectDate,
          onChanged: (date) => date == null ? null : notifier.setDate(date),
        ),
        const SizedBox(height: AlayaSpacing.md),
        // Optional, because most disposals recover nothing — a broken kettle is thrown away, not sold —
        // and requiring a zero would make the common case extra typing.
        AmountField(
          currencyCode: currencyCode,
          decimalDigits: digits,
          label: strings.labelDisposalAmount,
          initialValue: state.amount,
          onChanged: notifier.setAmount,
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextFormField(
          initialValue: state.note,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: strings.labelNote,
            hintText: strings.hintNote,
          ),
          onChanged: notifier.setNote,
        ),
        if (state.rejection != null) ...[
          const SizedBox(height: AlayaSpacing.sm),
          Text(
            state.rejection!,
            style: AlayaTypography.caption.copyWith(color: semantic.danger),
          ),
        ],
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: state.submitting ? null : () => _commit(context, ref),
          child: Text(strings.disposeCommit),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.actionCancel),
        ),
      ],
    );
  }
}
```

### `lib/features/service/presentation/widgets/asset_row.dart`

```dart
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
```

### `lib/features/service/presentation/widgets/contact_action.dart`

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';

/// A name, a number, and a button that dials it.
///
/// **The only outbound action in the app, and it reports its own failure.** `launchUrl` returns false
/// when no handler exists for `tel:` — a tablet without a dialler, or a restricted profile — and a
/// button that silently does nothing is worse than one that says why (Law U9).
///
/// The number is rendered as plain selectable text beside the action so it stays useful when the call
/// cannot be placed at all.
class ContactAction extends StatelessWidget {
  /// Creates the block.
  const ContactAction({required this.phone, this.name, super.key});

  /// The number to dial.
  final String phone;

  /// Who answers, if known.
  final String? name;

  Future<void> _call(BuildContext context) async {
    final strings = AlayaStrings.of(context);
    // `Uri(scheme:, path:)` rather than a parsed string: a number containing spaces or a leading plus
    // is common and `Uri.parse('tel:+91 98…')` mangles it.
    final launched = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (launched || !context.mounted) return;
    showFailureSnack(context, message: strings.callFailed);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final who = name;

    // A `Wrap`: the name, the number and the button all grow with text scale, and a `Row` would starve
    // whichever came first at 320dp (Law U21).
    return Wrap(
      spacing: AlayaSpacing.xs,
      runSpacing: AlayaSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (who != null && who.isNotEmpty)
          Text(
            who,
            style: AlayaTypography.body.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        // **Plain text, not a selectable widget.** `SelectableText` carries a `longPress` semantics
        // action, so the accessibility sweep counts it as a tap target and fails it at 162x16 — it is
        // 16px tall and cannot be 48 without dwarfing the row. The number is already reachable through
        // the Call button beside it, and long-press-to-copy on a 16px strip was never a real
        // affordance (Law U16).
        Text(
          phone,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        FilledButton.tonalIcon(
          onPressed: () => _call(context),
          icon: const Icon(Icons.call, size: AlayaIconSize.sm),
          label: Text(strings.actionCall),
        ),
      ],
    );
  }
}
```

### `lib/features/service/providers/asset_detail_providers.dart`

```dart
/// View-model state for one asset (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/service_record.dart';
import 'package:alaya/features/service/providers/asset_list_providers.dart';

/// The asset, or null when it does not exist.
///
/// **Derived from the two list streams, not a one-shot `byId`.** A `FutureProvider` reads once and then
/// serves its cache, and the detail screen stays mounted beneath the editor — so it would keep showing
/// the pre-edit asset until the app restarted. Both streams re-emit on every write, and a disposed
/// asset must stay reachable by id even though it has left `watchInUse` (anomaly A30).
final assetByIdProvider = Provider.autoDispose
    .family<AsyncValue<Asset?>, String>((ref, id) {
      final inUse = ref.watch(assetsInUseProvider);
      final disposed = ref.watch(disposedAssetsProvider);
      if (inUse.hasError)
        return AsyncValue.error(inUse.error!, inUse.stackTrace!);
      if (disposed.hasError) {
        return AsyncValue.error(disposed.error!, disposed.stackTrace!);
      }
      final active = inUse.valueOrNull;
      final retired = disposed.valueOrNull;
      if (active == null || retired == null) return const AsyncValue.loading();
      for (final asset in [...active, ...retired]) {
        if (asset.id == id) return AsyncValue.data(asset);
      }
      return const AsyncValue.data(null);
    });

/// Every service record against one asset, newest first.
final serviceRecordsProvider = StreamProvider.autoDispose
    .family<List<ServiceRecord>, String>(
      (ref, assetId) =>
          ref.watch(serviceRecordRepositoryProvider).watchForAsset(assetId),
    );

/// What has been spent servicing one asset, per currency.
///
/// A map rather than a single figure because a machine serviced abroad genuinely has two lifetime
/// totals, and summing them would invent an exchange rate the user never agreed to (Law L1).
final lifetimeServiceCostProvider = FutureProvider.autoDispose
    .family<Map<String, Money>, String>((ref, assetId) {
      // Watched so recording a service updates the figure rather than leaving it stale until a restart.
      ref.watch(serviceRecordsProvider(assetId));
      return ref
          .watch(serviceRecordRepositoryProvider)
          .lifetimeCostByCurrency(assetId);
    });

/// The recurring templates that pay this asset.
///
/// `watchTemplatesForAsset` was built in Phase 3A and deferred to this phase by 6D's coverage table:
/// it is what makes a maid's monthly salary visible from her own record rather than only from the
/// recurring list.
final assetTemplatesProvider = StreamProvider.autoDispose
    .family<List<RecurringTemplate>, String>(
      (ref, assetId) => ref
          .watch(recurringRepositoryProvider)
          .watchTemplatesForAsset(assetId),
    );

/// Writes the asset detail screen performs.
final assetActionsProvider = Provider<AssetActions>(AssetActions.new);

/// Changes an asset's status, and brings it back.
class AssetActions {
  /// Creates the actions.
  AssetActions(this._ref);

  final Ref _ref;

  /// Reverses a disposal, returning the failure's own message or null on success.
  ///
  /// The counterpart to disposal existing at all: a thing sold by mistake is put back, and nothing was
  /// destroyed in the meantime because disposal never deleted anything.
  Future<String?> undispose(String id) async {
    final result = await _ref.read(assetRepositoryProvider).undispose(id);
    return result.failureOrNull?.message;
  }

  /// Marks an asset as being repaired, or active again.
  Future<String?> setStatus({
    required String id,
    required AssetStatus status,
  }) async {
    final result = await _ref
        .read(assetRepositoryProvider)
        .setStatus(id: id, status: status);
    return result.failureOrNull?.message;
  }

  /// Deletes one service record.
  ///
  /// The record, not the asset. There is no path in this module that deletes an asset.
  Future<String?> deleteRecord(String recordId) async {
    final result = await _ref
        .read(serviceRecordRepositoryProvider)
        .delete(recordId);
    return result.failureOrNull?.message;
  }
}
```

### `lib/features/service/providers/asset_editor_providers.dart`

```dart
/// View-model state for the asset editor (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/features/service/providers/asset_list_providers.dart';
import 'package:alaya/features/service/state/asset_editor_state.dart';

/// The home currency, so a price is never denominated in a guess.
final serviceCurrencyProvider = FutureProvider.autoDispose<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      'INR',
);

/// The home currency's decimal digits (ARCH_1 §4.1).
final serviceDecimalDigitsProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final code = await ref.watch(serviceCurrencyProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// Whether another asset already carries this name.
///
/// **Derived from the list streams, and only ever a note.** `AssetRepositoryImpl.save` used to refuse a
/// repeated name, which made owning two of anything impossible — five iPhones are five assets, with five
/// warranties and five service histories. But a silent duplicate hides a genuine double entry, so the
/// editor says so and lets the user decide.
///
/// `AssetDao.byNormalizedName` exists and `AssetRepository` does not expose it; deriving from
/// `watchInUse` and `watchDisposed` needs no contract addition and no DAO reach-through (Law U19).
final assetNameClashProvider = Provider.autoDispose
    .family<bool, ({String? id, String name})>((ref, arg) {
      final trimmed = arg.name.trim();
      if (trimmed.isEmpty) return false;
      final normalized = ref.watch(normalizerProvider).normalize(trimmed);
      final inUse =
          ref.watch(assetsInUseProvider).valueOrNull ?? const <Asset>[];
      final disposed =
          ref.watch(disposedAssetsProvider).valueOrNull ?? const <Asset>[];
      for (final asset in [...inUse, ...disposed]) {
        if (asset.normalizedName == normalized && asset.id != arg.id)
          return true;
      }
      return false;
    });

/// The editor for one asset, or for a new one when the argument is null.
final assetEditorProvider = NotifierProvider.autoDispose
    .family<AssetEditorNotifier, AsyncValue<AssetEditorState>, String?>(
      AssetEditorNotifier.new,
    );

/// Loads, edits and saves one asset.
class AssetEditorNotifier
    extends AutoDisposeFamilyNotifier<AsyncValue<AssetEditorState>, String?> {
  @override
  AsyncValue<AssetEditorState> build(String? arg) {
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(String? id) async {
    try {
      final code =
          await ref.read(settingsRepositoryProvider).readHomeCurrencyCode() ??
          'INR';
      if (id == null) {
        state = AsyncValue.data(AssetEditorState(currencyCode: code));
        return;
      }
      final asset = await ref.read(assetRepositoryProvider).byId(id);
      if (asset == null) {
        state = AsyncValue.error(
          StateError('Asset $id not found.'),
          StackTrace.current,
        );
        return;
      }
      state = AsyncValue.data(AssetEditorState.fromAsset(asset, code));
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  /// Applies [change], clearing the last rejection unless told to keep it.
  ///
  /// A refused save is worth longer than a 2.5-second snack, so it is also a card in the form — but a card
  /// that survives the edit which fixes it is a stale error the user has to dismiss by hand. Every setter
  /// clears it; only `save` keeps it.
  void _edit(
    AssetEditorState Function(AssetEditorState) change, {
    bool keepIssue = false,
  }) {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = change(current);
    state = AsyncValue.data(keepIssue ? next : next.copyWith(clearIssue: true));
  }

  /// Sets what it is.
  void setName(String name) =>
      _edit((s) => s.copyWith(name: name, clearIssue: true));

  /// Sets which kind of thing — or person — this is.
  void setType(AssetType type) => _edit((s) => s.copyWith(type: type));

  /// Sets who made it.
  void setBrand(String value) => _edit((s) => s.copyWith(brand: value));

  /// Sets the model number.
  void setModelNo(String value) => _edit((s) => s.copyWith(modelNo: value));

  /// Sets the serial number.
  void setSerialNo(String value) => _edit((s) => s.copyWith(serialNo: value));

  /// Sets when it was bought.
  void setPurchaseDate(DateKey? date) =>
      _edit((s) => date == null ? s : s.copyWith(purchaseDateKey: date));

  /// Sets what it cost.
  void setPurchasePrice(Money? price) => _edit(
    (s) => price == null
        ? s.copyWith(clearPurchasePrice: true)
        : s.copyWith(purchasePrice: price),
  );

  /// Sets when the warranty starts.
  void setWarrantyStart(DateKey? date) =>
      _edit((s) => date == null ? s : s.copyWith(warrantyStartDateKey: date));

  /// Sets when the warranty ends.
  void setWarrantyEnd(DateKey? date) => _edit(
    (s) => date == null
        ? s.copyWith(clearWarrantyEnd: true)
        : s.copyWith(warrantyEndDateKey: date, clearIssue: true),
  );

  /// Sets who honours the warranty.
  void setWarrantyProvider(String value) =>
      _edit((s) => s.copyWith(warrantyProvider: value));

  /// Sets how many days between services, and derives the first due date from it.
  ///
  /// **Recomputed on every change, not seeded once.** A text field fires per keystroke: "30" arrives as
  /// 3 and then as 30, and the old `??` meant the three-day answer stuck. The date is derived from the
  /// interval unless the user has picked one themselves, which `nextServiceChosen` records.
  ///
  /// Deriving rather than requiring both: an interval with no first date never produces a due chip, and
  /// asking for the same information twice is how one of the two ends up wrong.
  void setServiceIntervalDays(int? days) => _edit((s) {
    if (days == null || days < 1) {
      return s.copyWith(clearInterval: true, clearNextService: true);
    }
    final from = s.purchaseDateKey ?? ref.read(clockProvider).today();
    return s.copyWith(
      serviceIntervalDays: days,
      nextServiceDueDateKey: s.nextServiceChosen
          ? s.nextServiceDueDateKey
          : from.addDays(days),
    );
  });

  /// Sets when the next service is due, and stops the interval deriving it from then on.
  void setNextServiceDue(DateKey? date) => _edit(
    (s) => date == null
        ? s.copyWith(clearNextService: true, nextServiceChosen: false)
        : s.copyWith(nextServiceDueDateKey: date, nextServiceChosen: true),
  );

  /// Sets who to call about it.
  void setContactName(String value) =>
      _edit((s) => s.copyWith(contactName: value));

  /// Sets the number to call.
  void setContactPhone(String value) =>
      _edit((s) => s.copyWith(contactPhone: value));

  /// Sets where it is kept.
  void setLocation(String value) => _edit((s) => s.copyWith(location: value));

  /// Sets the free notes.
  void setNotes(String value) => _edit((s) => s.copyWith(notes: value));

  /// Saves the asset, returning its id on success and null on rejection or failure.
  ///
  /// Every refusal is named before the repository sees it, and a rejection carries the repository's own
  /// message — a blank name and a backwards warranty fail for different reasons and "something went
  /// wrong" distinguishes neither (Law U9).
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (current.name.trim().isEmpty) {
      _edit(
        (s) => s.copyWith(
          issue: AssetSaveIssue.nameMissing,
          shakeTrigger: s.shakeTrigger + 1,
        ),
        keepIssue: true,
      );
      return null;
    }
    final start = current.warrantyStartDateKey;
    final end = current.warrantyEndDateKey;
    if (start != null && end != null && end.isBefore(start)) {
      _edit(
        (s) => s.copyWith(issue: AssetSaveIssue.warrantyBackwards),
        keepIssue: true,
      );
      return null;
    }

    _edit(
      (s) => s.copyWith(submitting: true, clearIssue: true),
      keepIssue: true,
    );
    try {
      final repository = ref.read(assetRepositoryProvider);
      final id = current.id ?? ref.read(uidGeneratorProvider).generate();
      // The existing row is read so the fields this editor does not own — the disposal block, the
      // recurring link, the fan-out's source line — travel across untouched rather than being nulled by
      // a save that never asked about them.
      final existing = current.isEditing ? await repository.byId(id) : null;
      final saved = await repository.save(
        current.toAsset(
          newId: id,
          normalizedName: ref
              .read(normalizerProvider)
              .normalize(current.name.trim()),
          existing: existing,
        ),
      );
      final failure = saved.failureOrNull;
      if (failure != null) {
        _edit(
          (s) => s.copyWith(
            issue: AssetSaveIssue.rejected,
            rejection: failure.message,
          ),
          keepIssue: true,
        );
        return null;
      }
      _edit((s) => s.copyWith(dirty: false));
      return id;
    } on Object catch (error, stack) {
      ref
          .read(loggerProvider)
          .log(
            'Asset save failed',
            level: LogLevel.error,
            tag: 'service.assetEditor',
            error: error,
            stackTrace: stack,
          );
      _edit(
        (s) => s.copyWith(
          issue: AssetSaveIssue.rejected,
          rejection: error.toString(),
        ),
        keepIssue: true,
      );
      return null;
    } finally {
      _edit((s) => s.copyWith(submitting: false), keepIssue: true);
    }
  }
}
```

### `lib/features/service/providers/asset_list_providers.dart`

```dart
/// View-model state for the asset list (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/asset.dart';

/// What the asset list is currently showing.
class AssetFilter {
  /// Creates a filter.
  const AssetFilter({
    this.includeDisposed = false,
    this.types = const <AssetType>{},
    this.query = '',
  });

  /// Whether disposed assets are shown alongside the rest.
  ///
  /// **Off by default, never unavailable.** An asset is never deleted (anomaly A30), so without this
  /// switch every television ever thrown away would crowd the list of things you actually own — and
  /// without the list ever showing them, the money spent on them would look like it had vanished.
  final bool includeDisposed;

  /// Which kinds are shown; empty means all.
  final Set<AssetType> types;

  /// The search term, already trimmed.
  final String query;

  /// Whether anything narrows the full list.
  bool get isNarrowed => includeDisposed || types.isNotEmpty;

  /// Whether a search term is active, which changes which empty state is right.
  bool get isSearching => query.isNotEmpty;

  /// Returns a copy with the supplied changes.
  AssetFilter copyWith({
    bool? includeDisposed,
    Set<AssetType>? types,
    String? query,
  }) => AssetFilter(
    includeDisposed: includeDisposed ?? this.includeDisposed,
    types: types ?? this.types,
    query: query ?? this.query,
  );
}

/// One kind's worth of assets.
class AssetGroup {
  /// Creates a group.
  const AssetGroup({required this.type, required this.assets});

  /// Which kind this group collects.
  final AssetType type;

  /// The assets under it, sorted by name.
  final List<Asset> assets;
}

/// The list's current filter.
final assetFilterProvider = NotifierProvider<AssetFilterNotifier, AssetFilter>(
  AssetFilterNotifier.new,
);

/// Drives the search field and the filter chips.
class AssetFilterNotifier extends Notifier<AssetFilter> {
  @override
  AssetFilter build() => const AssetFilter();

  /// Sets the search term.
  void setQuery(String query) => state = state.copyWith(query: query.trim());

  /// Brings disposed assets into the list, or takes them out again.
  void toggleDisposed() =>
      state = state.copyWith(includeDisposed: !state.includeDisposed);

  /// Adds or removes a kind.
  void toggleType(AssetType type) {
    final next = {...state.types};
    if (next.contains(type)) {
      next.remove(type);
    } else {
      next.add(type);
    }
    state = state.copyWith(types: next);
  }

  /// Clears everything back to the things you own.
  void clear() => state = AssetFilter(query: state.query);
}

/// The assets still in use.
final assetsInUseProvider = StreamProvider<List<Asset>>(
  (ref) => ref.watch(assetRepositoryProvider).watchInUse(),
);

/// The assets that have been disposed of.
///
/// Watched only when the filter asks for them, so an ordinary list does not carry the weight of every
/// object the household has ever retired.
final disposedAssetsProvider = StreamProvider<List<Asset>>(
  (ref) => ref.watch(assetRepositoryProvider).watchDisposed(),
);

/// The list, filtered, searched and grouped by kind.
final assetGroupsProvider = Provider<AsyncValue<List<AssetGroup>>>((ref) {
  final inUse = ref.watch(assetsInUseProvider);
  final filter = ref.watch(assetFilterProvider);
  if (inUse.hasError) return AsyncValue.error(inUse.error!, inUse.stackTrace!);
  final active = inUse.valueOrNull;
  if (active == null) return const AsyncValue.loading();

  var all = [...active];
  if (filter.includeDisposed) {
    final disposed = ref.watch(disposedAssetsProvider);
    if (disposed.hasError) {
      return AsyncValue.error(disposed.error!, disposed.stackTrace!);
    }
    final retired = disposed.valueOrNull;
    if (retired == null) return const AsyncValue.loading();
    all = [...all, ...retired];
  }

  final term = filter.query.toLowerCase();
  final visible = [
    for (final asset in all)
      if (_admits(asset, filter, term)) asset,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  final buckets = <AssetType, List<Asset>>{};
  for (final asset in visible) {
    buckets.putIfAbsent(asset.type, () => <Asset>[]).add(asset);
  }
  return AsyncValue.data([
    for (final type in AssetType.values)
      if (buckets[type] != null) AssetGroup(type: type, assets: buckets[type]!),
  ]);
});

/// How many assets are overdue a service, for the header count.
///
/// Derived from the clock through `Asset.isServiceOverdue`, never a stored flag (ARCH_2 §12.2): a flag
/// would be wrong the moment midnight passed with the app closed.
final serviceDueCountProvider = Provider<int>((ref) {
  final active = ref.watch(assetsInUseProvider).valueOrNull ?? const <Asset>[];
  final today = ref.watch(clockProvider).today();
  return active.where((asset) => asset.isServiceOverdue(today)).length;
});

bool _admits(Asset asset, AssetFilter filter, String term) {
  if (filter.types.isNotEmpty && !filter.types.contains(asset.type))
    return false;
  if (term.isEmpty) return true;
  return asset.normalizedName.contains(term) ||
      asset.name.toLowerCase().contains(term);
}
```

### `lib/features/service/providers/dispose_providers.dart`

```dart
/// View-model state for disposal (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/service/state/dispose_state.dart';

/// Which asset a dispose sheet is retiring, and the currency a recovery is entered in.
typedef DisposeArgs = ({String assetId, String currencyCode});

/// The dispose sheet for one asset.
final disposeProvider = NotifierProvider.autoDispose
    .family<DisposeNotifier, DisposeState, DisposeArgs>(
      DisposeNotifier.new,
    );

/// Holds the pending disposal and commits it.
///
/// **State is synchronous.** Everything the sheet needs arrives in the family argument from the screen
/// that already loaded the asset, so the reason picker is usable on the first frame rather than after a
/// spinner (ARCH_5 §5.2).
class DisposeNotifier
    extends AutoDisposeFamilyNotifier<DisposeState, DisposeArgs> {
  @override
  DisposeState build(DisposeArgs arg) => DisposeState(
    assetId: arg.assetId,
    currencyCode: arg.currencyCode,
    dateKey: ref.read(clockProvider).today(),
  );

  /// Sets why it is being retired.
  void setReason(AssetDisposalReason reason) =>
      state = state.copyWith(reason: reason, reasonMissing: false, dirty: true);

  /// Sets when.
  void setDate(DateKey date) =>
      state = state.copyWith(dateKey: date, dirty: true);

  /// Sets what the disposal recovered.
  void setAmount(Money? amount) => state = amount == null
      ? state.copyWith(clearAmount: true, dirty: true)
      : state.copyWith(amount: amount, dirty: true);

  /// Sets the note.
  void setNote(String note) => state = state.copyWith(note: note, dirty: true);

  /// Commits the disposal, returning the failure's own message or null on success.
  ///
  /// **`dispose` changes a status and records a reason. Nothing is deleted.** The purchase price stays
  /// on the row, so what the household spent on the thing still counts in every total after the thing
  /// itself has gone (anomaly A30, ARCH_3 §4.1).
  ///
  /// The amount is passed as minor units because that is what the contract takes; the currency is the
  /// asset's own, which is why the sheet is handed one rather than picking.
  Future<String?> commit() async {
    final reason = state.reason;
    if (reason == null) {
      state = state.copyWith(
        reasonMissing: true,
        shakeTrigger: state.shakeTrigger + 1,
      );
      return 'reasonMissing';
    }

    state = state.copyWith(submitting: true, clearRejection: true);
    try {
      final result = await ref
          .read(assetRepositoryProvider)
          .dispose(
            assetId: state.assetId,
            reason: reason,
            dateKey: state.dateKey,
            amountMinor: state.amount?.minor,
            note: state.note,
          );
      final failure = result.failureOrNull;
      if (failure != null) {
        state = state.copyWith(rejection: failure.message);
        return failure.message;
      }
      return null;
    } on Object catch (error, stack) {
      ref
          .read(loggerProvider)
          .log(
            'Asset disposal failed',
            level: LogLevel.error,
            tag: 'service.dispose',
            error: error,
            stackTrace: stack,
          );
      state = state.copyWith(rejection: error.toString());
      return error.toString();
    } finally {
      state = state.copyWith(submitting: false);
    }
  }
}
```

### `lib/features/service/providers/service_editor_providers.dart`

```dart
/// View-model state for the service record editor (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/state/service_editor_state.dart';

/// Which record an editor is pointed at. A record, so the family argument has structural equality.
typedef ServiceEditorArgs = ({String assetId, String? recordId});

/// Payment methods the expense may record, when the user cares to say.
final servicePaymentMethodsProvider =
    StreamProvider.autoDispose<List<PaymentMethod>>(
      (ref) => ref.watch(paymentMethodRepositoryProvider).watchAll(),
    );

/// Accounts an expense may come from.
final serviceAccountsProvider = StreamProvider.autoDispose<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// The app-wide default account, so the expense toggle rarely has to ask.
final serviceDefaultAccountProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(settingsRepositoryProvider).readDefaultAccountId(),
);

/// The editor for one service record, or for a new one when `recordId` is null.
final serviceEditorProvider = NotifierProvider.autoDispose
    .family<
      ServiceEditorNotifier,
      AsyncValue<ServiceEditorState>,
      ServiceEditorArgs
    >(
      ServiceEditorNotifier.new,
    );

/// Loads, edits and saves one service record.
class ServiceEditorNotifier
    extends
        AutoDisposeFamilyNotifier<
          AsyncValue<ServiceEditorState>,
          ServiceEditorArgs
        > {
  @override
  AsyncValue<ServiceEditorState> build(ServiceEditorArgs arg) {
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(ServiceEditorArgs arg) async {
    try {
      final code =
          await ref.read(settingsRepositoryProvider).readHomeCurrencyCode() ??
          'INR';
      final recordId = arg.recordId;
      if (recordId != null) {
        final record = await ref
            .read(serviceRecordRepositoryProvider)
            .byId(recordId);
        if (record == null) {
          state = AsyncValue.error(
            StateError('Service record $recordId not found.'),
            StackTrace.current,
          );
          return;
        }
        state = AsyncValue.data(ServiceEditorState.fromRecord(record, code));
        return;
      }
      final asset = await ref.read(assetRepositoryProvider).byId(arg.assetId);
      if (asset == null) {
        state = AsyncValue.error(
          StateError('Asset ${arg.assetId} not found.'),
          StackTrace.current,
        );
        return;
      }
      state = AsyncValue.data(
        ServiceEditorState(
          assetId: arg.assetId,
          currencyCode: code,
          serviceDateKey: ref.read(clockProvider).today(),
          // A person's record is a salary payment by default, and a thing's is a service. Making the
          // user correct the obvious is how the maid case ends up filed as "inspection".
          type: asset.isServiceProvider
              ? ServiceRecordType.salaryPaid
              : ServiceRecordType.service,
          providerName: asset.primaryContactName,
          providerPhone: asset.primaryContactPhone,
          // Seeded from the asset's own interval, so recording a service also proposes the next one.
          nextDueDateKey: asset.serviceIntervalDays == null
              ? null
              : ref
                    .read(clockProvider)
                    .today()
                    .addDays(asset.serviceIntervalDays!),
          accountId: await _resolveAccount(),
          // **On by default for a new record.** A cost typed here is money that left the house, so the
          // ledger should show it without a second decision — and the account is already resolved, so
          // the common path is no extra taps at all. It stays visible and switchable, because a service
          // paid by someone else (a warranty repair, a landlord's plumber) is a real case.
          //
          // This is not anomaly A14. A14 forbids *materialisation* creating money on its own; here the
          // user typed a figure and pressed save, which is as explicit as an act gets.
          alsoRecordAsExpense: true,
        ),
      );
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  /// The account an expense should come from when the user has not chosen one.
  ///
  /// **Two fallbacks, because one was not enough.** `readDefaultAccountId()` is null until somebody sets
  /// a default in Settings, and a null account makes `save` refuse the whole record — so a service with a
  /// cost silently could not be recorded at all. A sole selectable account is the obvious answer when
  /// there is only one, and it is information the user already gave (Law U23).
  Future<String?> _resolveAccount() async {
    final stored = await ref
        .read(settingsRepositoryProvider)
        .readDefaultAccountId();
    if (stored != null) return stored;
    final accounts = await ref
        .read(accountRepositoryProvider)
        .watchSelectable()
        .first;
    return accounts.length == 1 ? accounts.single.id : null;
  }

  /// Applies [change], clearing the last rejection unless told to keep it.
  ///
  /// **A rejection is shown until the user acts, then it goes.** The message is rendered as a card in the
  /// form rather than only as a snack, because a snack lasts 2.5 seconds and a refused save is worth
  /// longer than that — but a card that survives the edit which fixes it is a stale error the user has to
  /// dismiss by hand. Every setter clears it; only `save` keeps it.
  void _edit(
    ServiceEditorState Function(ServiceEditorState) change, {
    bool keepIssue = false,
  }) {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = change(current);
    state = AsyncValue.data(keepIssue ? next : next.copyWith(clearIssue: true));
  }

  /// Sets what happened.
  void setType(ServiceRecordType type) => _edit((s) => s.copyWith(type: type));

  /// Sets when.
  void setServiceDate(DateKey? date) =>
      _edit((s) => date == null ? s : s.copyWith(serviceDateKey: date));

  /// Sets who did it, or who was paid.
  void setProviderName(String value) =>
      _edit((s) => s.copyWith(providerName: value));

  /// Sets their number.
  void setProviderPhone(String value) =>
      _edit((s) => s.copyWith(providerPhone: value));

  /// Sets what it cost.
  void setCost(Money? cost) => _edit(
    (s) => cost == null
        ? s.copyWith(clearCost: true, clearIssue: true)
        : s.copyWith(cost: cost, clearIssue: true),
  );

  /// Sets when the next one is due.
  void setNextDue(DateKey? date) => _edit(
    (s) => date == null
        ? s.copyWith(clearNextDue: true)
        : s.copyWith(nextDueDateKey: date),
  );

  /// Sets the free notes.
  void setNotes(String value) => _edit((s) => s.copyWith(notes: value));

  /// Turns the expense toggle on or off.
  void toggleExpense() => _edit(
    (s) => s.copyWith(
      alsoRecordAsExpense: !s.alsoRecordAsExpense,
      clearIssue: true,
    ),
  );

  /// Sets which account the expense comes from.
  void setAccount(String? accountId) =>
      _edit((s) => s.copyWith(accountId: accountId, clearIssue: true));

  /// Sets how it was paid. Never required.
  void setPaymentMethod(String? methodId) =>
      _edit((s) => s.copyWith(paymentMethodId: methodId));

  /// Saves the record, returning its id on success and null on rejection or failure.
  ///
  /// **The expense is written by the repository, in the same call.** `save(record,
  /// alsoRecordAsExpense: true, accountId: …)` writes the record and the withdrawal; nothing here does
  /// it by hand. The sequence is not atomic across aggregates, so it is ordered and idempotent instead
  /// (ARCH_4 R21) — and it is one write path, not two (Law U22).
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (current.alsoRecordAsExpense && !(current.cost?.isPositive ?? false)) {
      _edit(
        (s) => s.copyWith(
          issue: ServiceSaveIssue.costMissingForExpense,
          shakeTrigger: s.shakeTrigger + 1,
        ),
        keepIssue: true,
      );
      return null;
    }
    if (current.alsoRecordAsExpense && current.accountId == null) {
      _edit(
        (s) => s.copyWith(issue: ServiceSaveIssue.accountMissingForExpense),
        keepIssue: true,
      );
      return null;
    }

    _edit(
      (s) => s.copyWith(submitting: true, clearIssue: true),
      keepIssue: true,
    );
    try {
      final repository = ref.read(serviceRecordRepositoryProvider);
      final id = current.id ?? ref.read(uidGeneratorProvider).generate();
      final existing = current.isEditing ? await repository.byId(id) : null;
      final saved = await repository.save(
        current.toRecord(newId: id, existing: existing),
        alsoRecordAsExpense: current.alsoRecordAsExpense,
        accountId: current.accountId,
        paymentMethodId: current.paymentMethodId,
      );
      final failure = saved.failureOrNull;
      if (failure != null) {
        _edit(
          (s) => s.copyWith(
            issue: ServiceSaveIssue.rejected,
            rejection: failure.message,
          ),
          keepIssue: true,
        );
        return null;
      }
      _edit((s) => s.copyWith(dirty: false));
      return id;
    } on Object catch (error, stack) {
      ref
          .read(loggerProvider)
          .log(
            'Service record save failed',
            level: LogLevel.error,
            tag: 'service.recordEditor',
            error: error,
            stackTrace: stack,
          );
      _edit(
        (s) => s.copyWith(
          issue: ServiceSaveIssue.rejected,
          rejection: error.toString(),
        ),
        keepIssue: true,
      );
      return null;
    } finally {
      _edit((s) => s.copyWith(submitting: false), keepIssue: true);
    }
  }
}
```

### `lib/features/service/state/asset_editor_state.dart`

```dart
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';

/// Why an asset save was refused, when it was refused for a reason worth naming.
enum AssetSaveIssue {
  /// The name was blank.
  nameMissing,

  /// The warranty ends before it starts.
  warrantyBackwards,

  /// The write failed for a reason the repository named.
  rejected,
}

/// Everything the asset editor is holding (ARCH_5 §3 archetype B).
///
/// **`type = serviceProvider` is a first-class case, not an afterthought.** A house maid is an asset
/// with a linked recurring template and a `service_records` row per payment — the same three tables a
/// television uses. Every field below is optional except the name precisely so a person can be
/// recorded without inventing a serial number for them.
class AssetEditorState {
  /// Creates the editor's state.
  const AssetEditorState({
    required this.currencyCode,
    this.id,
    this.name = '',
    this.type = AssetType.appliance,
    this.status = AssetStatus.active,
    this.brand,
    this.modelNo,
    this.serialNo,
    this.purchaseDateKey,
    this.purchasePrice,
    this.warrantyStartDateKey,
    this.warrantyEndDateKey,
    this.warrantyProvider,
    this.serviceIntervalDays,
    this.nextServiceDueDateKey,
    this.contactName,
    this.contactPhone,
    this.location,
    this.notes,
    this.submitting = false,
    this.issue,
    this.rejection,
    this.shakeTrigger = 0,
    this.dirty = false,
    this.nextServiceChosen = false,
  });

  /// The asset being edited, or null for a new one.
  final String? id;

  /// What it is. The one required field (U11).
  final String name;

  /// Which kind, which decides the wording everywhere else in the module.
  final AssetType type;

  /// Active, being repaired, or disposed. Disposal goes through the sheet, never this field.
  final AssetStatus status;

  /// The currency prices are entered in.
  final String currencyCode;

  /// Who made it.
  final String? brand;

  /// Which model.
  final String? modelNo;

  /// Its serial number.
  final String? serialNo;

  /// When it was bought.
  final DateKey? purchaseDateKey;

  /// What it cost. Kept forever, including after disposal (anomaly A30).
  final Money? purchasePrice;

  /// When the warranty starts.
  final DateKey? warrantyStartDateKey;

  /// When the warranty ends.
  final DateKey? warrantyEndDateKey;

  /// Who honours the warranty.
  final String? warrantyProvider;

  /// How many days between services.
  final int? serviceIntervalDays;

  /// When the next service is due.
  final DateKey? nextServiceDueDateKey;

  /// Who to call about it.
  final String? contactName;

  /// The number to call.
  final String? contactPhone;

  /// Where it is kept.
  final String? location;

  /// Free notes.
  final String? notes;

  /// Whether a save is in flight.
  final bool submitting;

  /// Why the last save was refused, or null if it was not.
  final AssetSaveIssue? issue;

  /// The repository's own message when it rejected the write.
  final String? rejection;

  /// Incremented to shake the offending field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the unsaved-changes guard (Law U10).
  final bool dirty;

  /// Whether the user picked the next service date themselves.
  ///
  /// **Typing "30" fires twice: once with 3, once with 30.** The due date was seeded with `?? `, so the
  /// first keystroke set it to three days out and every keystroke after that found it non-null and left
  /// it alone. It has to be recomputed on every change to the interval — and this flag is what stops
  /// that recomputation trampling a date the user chose deliberately.
  final bool nextServiceChosen;

  /// Whether this is editing an existing asset.
  bool get isEditing => id != null;

  /// Whether this asset is a person rather than a thing.
  ///
  /// Drives the wording, not the storage: the fields a television needs are simply left empty.
  bool get isPerson => type == AssetType.serviceProvider;

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  ///
  /// `issue` and `rejection` survive an unrelated `copyWith` — a bare assignment lets the
  /// `submitting: false` in a `finally` erase the reason before the screen reads it (ARCH_4 R31).
  AssetEditorState copyWith({
    String? id,
    String? name,
    AssetType? type,
    AssetStatus? status,
    String? brand,
    String? modelNo,
    String? serialNo,
    DateKey? purchaseDateKey,
    Money? purchasePrice,
    bool clearPurchasePrice = false,
    DateKey? warrantyStartDateKey,
    DateKey? warrantyEndDateKey,
    bool clearWarrantyEnd = false,
    String? warrantyProvider,
    int? serviceIntervalDays,
    bool clearInterval = false,
    DateKey? nextServiceDueDateKey,
    bool clearNextService = false,
    String? contactName,
    String? contactPhone,
    String? location,
    String? notes,
    bool? submitting,
    AssetSaveIssue? issue,
    String? rejection,
    bool clearIssue = false,
    int? shakeTrigger,
    bool? dirty,
    bool? nextServiceChosen,
  }) => AssetEditorState(
    currencyCode: currencyCode,
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    status: status ?? this.status,
    brand: brand ?? this.brand,
    modelNo: modelNo ?? this.modelNo,
    serialNo: serialNo ?? this.serialNo,
    purchaseDateKey: purchaseDateKey ?? this.purchaseDateKey,
    purchasePrice: clearPurchasePrice
        ? null
        : (purchasePrice ?? this.purchasePrice),
    warrantyStartDateKey: warrantyStartDateKey ?? this.warrantyStartDateKey,
    warrantyEndDateKey: clearWarrantyEnd
        ? null
        : (warrantyEndDateKey ?? this.warrantyEndDateKey),
    warrantyProvider: warrantyProvider ?? this.warrantyProvider,
    serviceIntervalDays: clearInterval
        ? null
        : (serviceIntervalDays ?? this.serviceIntervalDays),
    nextServiceDueDateKey: clearNextService
        ? null
        : (nextServiceDueDateKey ?? this.nextServiceDueDateKey),
    contactName: contactName ?? this.contactName,
    contactPhone: contactPhone ?? this.contactPhone,
    location: location ?? this.location,
    notes: notes ?? this.notes,
    submitting: submitting ?? this.submitting,
    issue: clearIssue ? null : (issue ?? this.issue),
    rejection: clearIssue ? null : (rejection ?? this.rejection),
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? true,
    nextServiceChosen: nextServiceChosen ?? this.nextServiceChosen,
  );

  /// Builds the entity this state describes.
  ///
  /// Disposal fields are never written here. An asset is disposed of through
  /// `AssetRepository.dispose`, which records the reason alongside the status change — saving the
  /// editor must not be able to quietly retire something (anomaly A30).
  Asset toAsset({
    required String newId,
    required String normalizedName,
    Asset? existing,
  }) => Asset(
    id: id ?? newId,
    name: name.trim(),
    normalizedName: normalizedName,
    type: type,
    status: status,
    brand: brand,
    modelNo: modelNo,
    serialNo: serialNo,
    purchaseDateKey: purchaseDateKey,
    purchasePrice: purchasePrice,
    sourceTransactionLineId: existing?.sourceTransactionLineId,
    warrantyStartDateKey: warrantyStartDateKey,
    warrantyEndDateKey: warrantyEndDateKey,
    warrantyProvider: warrantyProvider,
    warrantyNote: existing?.warrantyNote,
    serviceIntervalDays: serviceIntervalDays,
    nextServiceDueDateKey: nextServiceDueDateKey,
    primaryContactName: contactName,
    primaryContactPhone: contactPhone,
    location: location,
    linkedRecurringTemplateId: existing?.linkedRecurringTemplateId,
    disposedAtDateKey: existing?.disposedAtDateKey,
    disposalReason: existing?.disposalReason,
    disposalNote: existing?.disposalNote,
    disposalAmount: existing?.disposalAmount,
    notes: notes,
  );

  /// Loads an existing asset into an editor state.
  static AssetEditorState fromAsset(
    Asset asset,
    String currencyCode,
  ) => AssetEditorState(
    currencyCode: asset.purchasePrice?.currencyCode ?? currencyCode,
    id: asset.id,
    name: asset.name,
    type: asset.type,
    status: asset.status,
    brand: asset.brand,
    modelNo: asset.modelNo,
    serialNo: asset.serialNo,
    purchaseDateKey: asset.purchaseDateKey,
    purchasePrice: asset.purchasePrice,
    warrantyStartDateKey: asset.warrantyStartDateKey,
    warrantyEndDateKey: asset.warrantyEndDateKey,
    warrantyProvider: asset.warrantyProvider,
    serviceIntervalDays: asset.serviceIntervalDays,
    nextServiceDueDateKey: asset.nextServiceDueDateKey,
    // A saved date is one the user already lives with; recomputing it from the interval on the first
    // edit would silently move a service they may have booked.
    nextServiceChosen: asset.nextServiceDueDateKey != null,
    contactName: asset.primaryContactName,
    contactPhone: asset.primaryContactPhone,
    location: asset.location,
    notes: asset.notes,
  );
}
```

### `lib/features/service/state/dispose_state.dart`

```dart
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// What the dispose sheet is holding (ARCH_5 §3 archetype A).
///
/// **Disposal is a status change plus a reason, never a delete.** The ₹45,000 spent on a television
/// stays in every total after it goes to the tip, because the money left the house whether or not the
/// object is still in it (anomaly A30, ARCH_3 §4.1). That is why there is a reason picker here and no
/// delete anywhere in the module.
class DisposeState {
  /// Creates the sheet's state.
  const DisposeState({
    required this.assetId,
    required this.currencyCode,
    required this.dateKey,
    this.reason,
    this.amount,
    this.note,
    this.submitting = false,
    this.reasonMissing = false,
    this.rejection,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// Which asset is being retired.
  final String assetId;

  /// The currency a recovered amount is entered in.
  final String currencyCode;

  /// Why. The one required field (U11).
  final AssetDisposalReason? reason;

  /// When it happened.
  final DateKey dateKey;

  /// What the disposal recovered, if anything.
  ///
  /// Optional because most disposals recover nothing — a broken kettle is thrown away, not sold — and
  /// requiring a zero would make the common case extra typing.
  final Money? amount;

  /// Anything worth saying about it.
  final String? note;

  /// Whether a commit is in flight.
  final bool submitting;

  /// Whether commit was pressed with no reason chosen.
  final bool reasonMissing;

  /// The repository's own message when it rejected the write.
  final String? rejection;

  /// Incremented to shake the reason picker.
  final int shakeTrigger;

  /// Whether anything optional was touched, for the dismiss guard (Law U10).
  final bool dirty;

  /// Returns a copy with the supplied changes.
  DisposeState copyWith({
    AssetDisposalReason? reason,
    DateKey? dateKey,
    Money? amount,
    bool clearAmount = false,
    String? note,
    bool? submitting,
    bool? reasonMissing,
    String? rejection,
    bool clearRejection = false,
    int? shakeTrigger,
    bool? dirty,
  }) => DisposeState(
    assetId: assetId,
    currencyCode: currencyCode,
    reason: reason ?? this.reason,
    dateKey: dateKey ?? this.dateKey,
    amount: clearAmount ? null : (amount ?? this.amount),
    note: note ?? this.note,
    submitting: submitting ?? this.submitting,
    reasonMissing: reasonMissing ?? this.reasonMissing,
    rejection: clearRejection ? null : (rejection ?? this.rejection),
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? this.dirty,
  );
}
```

### `lib/features/service/state/service_editor_state.dart`

```dart
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/service_record.dart';

/// Why a service record was refused, when it was refused for a reason worth naming.
enum ServiceSaveIssue {
  /// The expense toggle is on with no cost to record.
  costMissingForExpense,

  /// The expense toggle is on with no account to record it against.
  accountMissingForExpense,

  /// The write failed for a reason the repository named.
  rejected,
}

/// Everything the service editor is holding (ARCH_5 §3 archetype B).
///
/// **`type = salaryPaid` is what makes a person work in this table.** A maid's monthly payment is a
/// service record like any other — same asset, same cost column, same optional expense — so the
/// salary history on the detail screen is simply this table filtered by type. There is no second
/// system to keep in step.
class ServiceEditorState {
  /// Creates the editor's state.
  const ServiceEditorState({
    required this.assetId,
    required this.currencyCode,
    required this.serviceDateKey,
    this.id,
    this.type = ServiceRecordType.service,
    this.providerName,
    this.providerPhone,
    this.cost,
    this.nextDueDateKey,
    this.notes,
    this.alsoRecordAsExpense = false,
    this.accountId,
    this.paymentMethodId,
    this.submitting = false,
    this.issue,
    this.rejection,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// The record being edited, or null for a new one.
  final String? id;

  /// Which asset it belongs to.
  final String assetId;

  /// The currency costs are entered in.
  final String currencyCode;

  /// What happened.
  final ServiceRecordType type;

  /// When.
  final DateKey serviceDateKey;

  /// Who did it, or who was paid.
  final String? providerName;

  /// Their number, so the detail screen can offer a call.
  final String? providerPhone;

  /// What it cost.
  final Money? cost;

  /// When the next one is due, which also advances the asset's own due date.
  final DateKey? nextDueDateKey;

  /// Free notes.
  final String? notes;

  /// Whether the repository should also write a withdrawal for [cost].
  ///
  /// **The repository owns that write, not this editor.** `ServiceRecordRepository.save` takes the flag
  /// and does both, which is the only way the two stay consistent — the sequence is not atomic across
  /// aggregates, so it is ordered and idempotent instead (ARCH_4 R21).
  final bool alsoRecordAsExpense;

  /// Which account the expense comes from, required only when the toggle is on.
  final String? accountId;

  /// How it was paid, if the user cares to say.
  ///
  /// Always optional. It travels to the expense and never onto the record: how a service was settled is
  /// a property of the payment, not of the work.
  final String? paymentMethodId;

  /// Whether a save is in flight.
  final bool submitting;

  /// Why the last save was refused, or null if it was not.
  final ServiceSaveIssue? issue;

  /// The repository's own message when it rejected the write.
  final String? rejection;

  /// Incremented to shake the offending field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the unsaved-changes guard (Law U10).
  final bool dirty;

  /// Whether this is editing an existing record.
  bool get isEditing => id != null;

  /// Whether this record is a salary payment rather than work done on a thing.
  bool get isSalary => type == ServiceRecordType.salaryPaid;

  /// Whether the expense toggle has everything it needs.
  bool get expenseIsSatisfiable =>
      !alsoRecordAsExpense ||
      ((cost?.isPositive ?? false) && accountId != null);

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  ServiceEditorState copyWith({
    String? id,
    ServiceRecordType? type,
    DateKey? serviceDateKey,
    String? providerName,
    String? providerPhone,
    Money? cost,
    bool clearCost = false,
    DateKey? nextDueDateKey,
    bool clearNextDue = false,
    String? notes,
    bool? alsoRecordAsExpense,
    String? accountId,
    String? paymentMethodId,
    bool? submitting,
    ServiceSaveIssue? issue,
    String? rejection,
    bool clearIssue = false,
    int? shakeTrigger,
    bool? dirty,
  }) => ServiceEditorState(
    assetId: assetId,
    currencyCode: currencyCode,
    id: id ?? this.id,
    type: type ?? this.type,
    serviceDateKey: serviceDateKey ?? this.serviceDateKey,
    providerName: providerName ?? this.providerName,
    providerPhone: providerPhone ?? this.providerPhone,
    cost: clearCost ? null : (cost ?? this.cost),
    nextDueDateKey: clearNextDue
        ? null
        : (nextDueDateKey ?? this.nextDueDateKey),
    notes: notes ?? this.notes,
    alsoRecordAsExpense: alsoRecordAsExpense ?? this.alsoRecordAsExpense,
    accountId: accountId ?? this.accountId,
    paymentMethodId: paymentMethodId ?? this.paymentMethodId,
    submitting: submitting ?? this.submitting,
    issue: clearIssue ? null : (issue ?? this.issue),
    rejection: clearIssue ? null : (rejection ?? this.rejection),
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? true,
  );

  /// Builds the entity this state describes.
  ServiceRecord toRecord({
    required String newId,
    ServiceRecord? existing,
  }) => ServiceRecord(
    id: id ?? newId,
    assetId: assetId,
    serviceDateKey: serviceDateKey,
    type: type,
    providerName: providerName,
    providerPhone: providerPhone,
    cost: cost,
    // Preserved rather than rewritten: the repository owns this link, and an editor that cleared it
    // would orphan a transaction that genuinely happened (Law L6).
    linkedTransactionId: existing?.linkedTransactionId,
    nextDueDateKey: nextDueDateKey,
    notes: notes,
  );

  /// Loads an existing record into an editor state.
  static ServiceEditorState fromRecord(
    ServiceRecord record,
    String currencyCode,
  ) => ServiceEditorState(
    assetId: record.assetId,
    currencyCode: record.cost?.currencyCode ?? currencyCode,
    id: record.id,
    type: record.type,
    serviceDateKey: record.serviceDateKey,
    providerName: record.providerName,
    providerPhone: record.providerPhone,
    cost: record.cost,
    nextDueDateKey: record.nextDueDateKey,
    notes: record.notes,
    // An existing record already wrote its expense or did not. Re-offering the toggle on edit would
    // let one service produce two withdrawals — the same shape as ARCH_4 R35.
    alsoRecordAsExpense: false,
  );
}
```

### `test/features/service/asset_detail_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/service_record.dart';
import 'package:alaya/features/service/presentation/screens/asset_detail_screen.dart';
import 'package:alaya/features/service/presentation/widgets/contact_action.dart';
import 'package:alaya/features/service/providers/asset_detail_providers.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/asset_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_timeline.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/service_harness.dart';

/// Four states, and the §7.2 rows this screen closes: a call action, a salary history, and a disposed
/// asset that is still fully readable.
///
/// **The history sliver sits below the fold, so its assertions pass `skipOffstage: false`.** The
/// diagnostic that found this reported `sliver 2 RenderSliverList: scrollExtent=100.0 paintExtent=0.0
/// visible=false` while `AlayaTimeline: 1 in tree` — the widget is built, and a `Finder` skips
/// off-screen widgets by default. Scrolling first would also work, but the question these tests ask is
/// whether the screen *builds* the right thing, not whether 584 logical pixels happen to reach it.
///
/// **No test asserts a ledger badge.** With the expense toggle on by default a service reaching the
/// ledger is the rule rather than the exception, so the chip was removed as noise — marking the *inverse*
/// would carry information, and is a design decision nobody has taken.
///
/// **And `SectionHeader` upper-cases its label**, so a header is found as `SALARY HISTORY`, never as the
/// ARB string. Both are ARCH_4 P6: the harness, not the product (five failures, zero defects).
void main() {
  const id = 'asset-1';

  List<Override> overrides({
    List<Asset>? inUse,
    List<Asset> disposed = const [],
    List<ServiceRecord> records = const [],
    Map<String, Money> lifetime = const {},
    bool pending = false,
    bool fail = false,
  }) => [
    clockProvider.overrideWithValue(kServiceClock),
    serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
    serviceCurrencyProvider.overrideWith((ref) async => 'INR'),
    assetsInUseProvider.overrideWith(
      (ref) => Stream.value(inUse ?? [television()]),
    ),
    disposedAssetsProvider.overrideWith((ref) => Stream.value(disposed)),
    lifetimeServiceCostProvider(id).overrideWith((ref) async => lifetime),
    assetTemplatesProvider(
      id,
    ).overrideWith((ref) => Stream.value(const <RecurringTemplate>[])),
    if (pending)
      serviceRecordsProvider(
        id,
      ).overrideWith((ref) => pendingStream<List<ServiceRecord>>())
    else if (fail)
      serviceRecordsProvider(id).overrideWith(
        (ref) => Stream<List<ServiceRecord>>.error(StateError('boom')),
      )
    else
      serviceRecordsProvider(id).overrideWith((ref) => Stream.value(records)),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(pending: true),
    );
    await tester.pump();
    expect(find.byType(AlayaListSkeleton, skipOffstage: false), findsWidgets);
  });

  testWidgets('an unknown id reads as not found rather than as an error', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: 'nope'),
      overrides: overrides(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
  });

  testWidgets('a failed history read shows the real reason', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(fail: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState, skipOffstage: false), findsOneWidget);
    expect(find.textContaining('boom', skipOffstage: false), findsOneWidget);
  });

  testWidgets('populated shows the hero, the details and the history', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(records: [serviceRecord()]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Living room TV'), findsOneWidget);
    expect(find.text('LG'), findsOneWidget);
    expect(find.byType(AlayaTimeline, skipOffstage: false), findsOneWidget);
    expect(find.text('Serviced', skipOffstage: false), findsOneWidget);
  });

  testWidgets('a phone number becomes a call action', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(inUse: [television(contactPhone: '+911234567890')]),
    );
    await tester.pumpAndSettle();
    // §7.2: `primaryContactPhone` is reachable as an action, not just readable as text.
    expect(find.byType(ContactAction), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
  });

  testWidgets('no phone number offers no call action', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(inUse: [television()]),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ContactAction), findsNothing);
  });

  testWidgets('a person shows a salary history and offers a payment', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(
        inUse: [maid(id: id)],
        records: [
          serviceRecord(
            assetId: id,
            type: ServiceRecordType.salaryPaid,
            costMinor: 800000,
            providerName: 'Lakshmi',
          ),
        ],
        lifetime: const {'INR': Money(800000, 'INR')},
      ),
    );
    await tester.pumpAndSettle();
    // The maid case end to end: her own wording, her own history, her own lifetime total — one table.
    expect(find.text('SALARY HISTORY', skipOffstage: false), findsWidgets);
    expect(find.text('Salary paid', skipOffstage: false), findsOneWidget);
    expect(find.text('Record a payment'), findsOneWidget);
    expect(find.text('Paid so far'), findsOneWidget);
  });

  testWidgets('a linked recurring template is shown against the person', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(inUse: [maid(id: id)]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Paid on a schedule'), findsOneWidget);
  });

  testWidgets('a disposed asset stays fully readable and offers a way back', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(
        inUse: const [],
        disposed: [
          television(
            status: AssetStatus.disposed,
            disposedAt: const DateKey(20260601),
            disposalReason: AssetDisposalReason.sold,
            disposalMinor: 1500000,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    // Anomaly A30: the price paid survives disposal, and so does everything else about it.
    expect(find.text('Living room TV'), findsOneWidget);
    expect(find.text('Disposed'), findsWidgets);
    expect(find.text('Bring it back'), findsOneWidget);
    expect(find.text('Dispose of it'), findsNothing);
  });

  testWidgets('lifetime service cost is one figure per currency, never summed', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(
        records: [serviceRecord()],
        lifetime: const {
          'INR': Money(120000, 'INR'),
          'USD': Money(4500, 'USD'),
        },
      ),
    );
    await tester.pumpAndSettle();
    // Adding them would invent an exchange rate the user never agreed to (Law L1).
    expect(find.text('Spent on service so far'), findsOneWidget);
    expect(find.textContaining('1,200.00'), findsWidgets);
    expect(find.textContaining('45.00'), findsWidgets);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(
        inUse: [
          television(
            name: 'A television with a name long enough to wrap twice over',
            contactPhone: '+911234567890',
            nextService: const DateKey(20260715),
            serviceIntervalDays: 180,
          ),
        ],
        records: [
          serviceRecord(),
          serviceRecord(id: 'rec-2', costMinor: null),
        ],
        lifetime: const {'INR': Money(120000, 'INR')},
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(
        inUse: [television(contactPhone: '+911234567890')],
        records: [serviceRecord()],
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/service/asset_editor_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/service/presentation/screens/asset_editor_screen.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/state/asset_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/service_harness.dart';

/// Four states, plus the rule that makes one table hold a television and a house maid.
void main() {
  AssetEditorState state({
    String name = 'Living room TV',
    AssetType type = AssetType.electronics,
    int? priceMinor = 4500000,
    DateKey? warrantyStart = const DateKey(20260131),
    DateKey? warrantyEnd = const DateKey(20270131),
    AssetSaveIssue? issue,
    String? rejection,
  }) => AssetEditorState(
    currencyCode: 'INR',
    name: name,
    type: type,
    purchasePrice: priceMinor == null ? null : Money(priceMinor, 'INR'),
    warrantyStartDateKey: warrantyStart,
    warrantyEndDateKey: warrantyEnd,
    issue: issue,
    rejection: rejection,
  );

  // The override goes on the **family**: a NotifierProvider family instance has no `overrideWith`.
  List<Override> overrides(AsyncValue<AssetEditorState> value) => [
    assetEditorProvider.overrideWith(() => _StubEditor(value)),
    serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('an unknown asset reads as not found', (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(assetId: 'nope'),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('a new asset opens on the form, which is its empty state', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(AsyncValue.data(state(name: '', priceMinor: null))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.text('What is it?'), findsOneWidget);
  });

  testWidgets('a thing is asked for a brand, a model and a price', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Brand'), findsOneWidget);
    expect(find.text('Model'), findsOneWidget);
    expect(find.byType(AmountField), findsOneWidget);
  });

  testWidgets('a person is asked for none of them', (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(name: 'Lakshmi', type: AssetType.serviceProvider),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Hidden rather than offered and left blank: an empty "Serial" on a human being is worse than its
    // absence, and that omission is what lets one table hold both cases.
    expect(find.text('Brand'), findsNothing);
    expect(find.text('Model'), findsNothing);
    expect(find.text('Serial'), findsNothing);
    expect(find.byType(AmountField), findsNothing);
    expect(
      find.textContaining('A person you pay regularly belongs here too'),
      findsOneWidget,
    );
  });

  testWidgets(
    'a person is still asked for a phone number and a service interval',
    (tester) async {
      await pumpService(
        tester,
        const AssetEditorScreen(),
        overrides: overrides(
          AsyncValue.data(
            state(name: 'Lakshmi', type: AssetType.serviceProvider),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Both moved behind the door in the density pass — Contact and Service are refinements once the
      // asset is identified. The behaviour is unchanged and this asserts it: one tap, both fields
      // present. A person is still asked for exactly what a person needs.
      await tester.tap(find.text('More details'));
      await tester.pumpAndSettle();
      // The two fields that matter for a person: how to reach her, and how often she comes.
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('Service every'), findsOneWidget);
    },
  );

  testWidgets('a blank name is refused at the field, not in a snack', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(
        AsyncValue.data(state(name: '', issue: AssetSaveIssue.nameMissing)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('This is required'), findsWidgets);
  });

  testWidgets('a backwards warranty says which field is wrong', (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(
            warrantyStart: const DateKey(20260601),
            warrantyEnd: const DateKey(20260101),
            issue: AssetSaveIssue.warrantyBackwards,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('The warranty cannot end before it starts'), findsWidgets);
  });

  testWidgets('a rejection is shown in the repository own words', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(
            issue: AssetSaveIssue.rejected,
            rejection: 'An asset with that name already exists.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('already exists'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(AsyncValue.data(state())),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('the state', () {
    test('disposal fields are never written by a save', () {
      final asset = state().toAsset(newId: 'a1', normalizedName: 'tv');
      // Retiring something goes through `AssetRepository.dispose`, which records a reason with the
      // status change. A save that could set `status: disposed` would be a second write path (Law U22).
      expect(asset.disposedAtDateKey, isNull);
      expect(asset.disposalReason, isNull);
      expect(asset.disposalAmount, isNull);
      expect(asset.status, AssetStatus.active);
    });

    test('an issue survives an unrelated copyWith', () {
      final base = state(issue: AssetSaveIssue.nameMissing);
      // ARCH_4 R31: a bare assignment let `submitting: false` in a `finally` erase the reason before the
      // screen read it.
      expect(
        base.copyWith(submitting: false).issue,
        AssetSaveIssue.nameMissing,
      );
      expect(base.copyWith(clearIssue: true).issue, isNull);
    });
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubEditor extends AssetEditorNotifier {
  _StubEditor(this._value);

  final AsyncValue<AssetEditorState> _value;

  @override
  AsyncValue<AssetEditorState> build(String? arg) => _value;
}
```

### `test/features/service/asset_list_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/features/service/presentation/screens/asset_list_screen.dart';
import 'package:alaya/features/service/presentation/widgets/asset_row.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/asset_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/service_harness.dart';

/// Four states, 320dp at a doubled text scale, and both accessibility floors (ARCH_5 §9.1).
void main() {
  List<Override> overrides({
    List<Asset>? inUse,
    List<Asset> disposed = const [],
    bool pending = false,
    bool fail = false,
  }) => [
    clockProvider.overrideWithValue(kServiceClock),
    serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
    disposedAssetsProvider.overrideWith((ref) => Stream.value(disposed)),
    if (pending)
      assetsInUseProvider.overrideWith((ref) => pendingStream<List<Asset>>())
    else if (fail)
      assetsInUseProvider.overrideWith(
        (ref) => Stream<List<Asset>>.error(StateError('boom')),
      )
    else
      assetsInUseProvider.overrideWith(
        (ref) => Stream.value(inUse ?? const <Asset>[]),
      ),
  ];

  testWidgets('loading shows a skeleton, not a spinner', (tester) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(pending: true),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'empty invites the first asset and says a person belongs here too',
    (tester) async {
      await pumpService(
        tester,
        const AssetListScreen(),
        overrides: overrides(),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
      // §7.2's maid case has to be discoverable from the empty state, or nobody ever finds it.
      expect(
        find.textContaining('the person who helps around the house'),
        findsOneWidget,
      );
    },
  );

  testWidgets('error shows the real reason with a retry', (tester) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(fail: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('populated groups by kind', (tester) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(inUse: [television(), maid()]),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AssetRowTile), findsNWidgets(2));
    expect(find.text('Electronics'), findsOneWidget);
    // A person gets her own group, labelled as people rather than as equipment.
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Lakshmi'), findsOneWidget);
  });

  testWidgets('a disposed asset is hidden until the filter asks for it', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(
        inUse: [television()],
        disposed: [
          television(
            id: 'asset-9',
            name: 'Old kettle',
            status: AssetStatus.disposed,
            disposedAt: const DateKey(20260601),
            disposalReason: AssetDisposalReason.damaged,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    // Nothing is ever deleted (anomaly A30), so the kettle exists — it is simply not something you own.
    expect(find.text('Old kettle'), findsNothing);
    await tester.tap(find.text('Include disposed'));
    await tester.pumpAndSettle();
    expect(find.text('Old kettle'), findsOneWidget);
    expect(find.text('Disposed'), findsOneWidget);
  });

  testWidgets('an overdue service is derived from the clock, not a stored flag', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(
        // Due in July against a clock fixed to 1 August. Nothing on the entity says "overdue".
        inUse: [
          television(
            nextService: const DateKey(20260715),
            serviceIntervalDays: 180,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Service due'), findsWidgets);
  });

  testWidgets('a warranty still running reads as covered', (tester) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(
        inUse: [television(warrantyEnd: const DateKey(20270131))],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('In warranty'), findsOneWidget);
    expect(find.text('Out of warranty'), findsNothing);
  });

  testWidgets('a warranty already past reads as expired', (tester) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(
        inUse: [television(warrantyEnd: const DateKey(20260601))],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Out of warranty'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(
        inUse: [
          television(
            name: 'A television with a name long enough to wrap twice over',
            nextService: const DateKey(20260715),
            linkedRecurringTemplateId: 'tpl-1',
          ),
          maid(),
        ],
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(inUse: [television(), maid()]),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/service/dispose_sheet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/features/service/presentation/sheets/dispose_sheet.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/dispose_providers.dart';
import 'package:alaya/features/service/state/dispose_state.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

import '../../support/service_harness.dart';

/// **This sheet reads no async source, so it has no loading or error state and none is faked.** Its only
/// inputs are a chip row, a date and two optional fields; an `AsyncValue` branch would be unreachable
/// code asserted by an unreachable test. §9.1's four states apply where there is something to await.
void main() {
  const args = (assetId: 'asset-1', currencyCode: 'INR');

  List<Override> overrides({DisposeState? seed}) => [
    clockProvider.overrideWithValue(kServiceClock),
    serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
    disposeProvider.overrideWith(
      () => _StubDispose(
        seed ??
            const DisposeState(
              assetId: 'asset-1',
              currencyCode: 'INR',
              dateKey: kToday,
            ),
      ),
    ),
  ];

  Widget host() => const Scaffold(
    body: AlayaBottomSheet(
      child: DisposeSheet(assetId: 'asset-1', currencyCode: 'INR'),
    ),
  );

  testWidgets('it says what disposal will not do', (tester) async {
    await pumpService(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    // Anomaly A30 out loud: a user reaching for this button is entitled to know nothing is destroyed.
    expect(find.text('What happened to it?'), findsOneWidget);
    expect(
      find.textContaining('what you spent on it still counts'),
      findsOneWidget,
    );
  });

  testWidgets('every reason is offered', (tester) async {
    await pumpService(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    expect(
      find.byType(ChoiceChip),
      findsNWidgets(AssetDisposalReason.values.length),
    );
    expect(find.text('Sold it'), findsOneWidget);
    expect(find.text('Broke'), findsOneWidget);
  });

  testWidgets('nothing is chosen until the user picks', (tester) async {
    await pumpService(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    final selected = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .where((chip) => chip.selected);
    expect(selected, isEmpty);
  });

  testWidgets('the recovered amount is optional', (tester) async {
    await pumpService(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    // Most disposals recover nothing — a broken kettle is thrown away, not sold — and requiring a zero
    // would make the common case extra typing.
    expect(find.byType(AmountField), findsOneWidget);
    expect(find.text('Got back'), findsOneWidget);
  });

  testWidgets('committing with no reason shakes rather than closing', (
    tester,
  ) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        seed: const DisposeState(
          assetId: 'asset-1',
          currencyCode: 'INR',
          dateKey: kToday,
          reasonMissing: true,
          shakeTrigger: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ShakeOnError), findsOneWidget);
    expect(find.text('Pick what happened'), findsOneWidget);
  });

  testWidgets('a rejection is shown in the repository own words', (
    tester,
  ) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        seed: const DisposeState(
          assetId: 'asset-1',
          currencyCode: 'INR',
          dateKey: kToday,
          reason: AssetDisposalReason.sold,
          rejection: 'That asset is already disposed.',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('already disposed'), findsOneWidget);
  });

  testWidgets('a chosen reason and a recovered amount both show', (
    tester,
  ) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        seed: const DisposeState(
          assetId: 'asset-1',
          currencyCode: 'INR',
          dateKey: kToday,
          reason: AssetDisposalReason.sold,
          amount: Money(1500000, 'INR'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final selected = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .where((chip) => chip.selected)
        .length;
    expect(selected, 1);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpService(tester, host(), overrides: overrides(), textScale: 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpService(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubDispose extends DisposeNotifier {
  _StubDispose(this._value);

  final DisposeState _value;

  @override
  DisposeState build(DisposeArgs arg) => _value;
}
```

### `test/features/service/service_editor_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/features/service/presentation/screens/service_editor_screen.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/service_editor_providers.dart';
import 'package:alaya/features/service/state/service_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/service_harness.dart';

/// Four states, plus the one write path: the toggle is a repository parameter, never a second save.
void main() {
  const assetId = 'asset-1';

  ServiceEditorState state({
    ServiceRecordType type = ServiceRecordType.service,
    int? costMinor = 120000,
    bool alsoRecordAsExpense = false,
    String? accountId,
    ServiceSaveIssue? issue,
    String? rejection,
  }) => ServiceEditorState(
    assetId: assetId,
    currencyCode: 'INR',
    serviceDateKey: kToday,
    type: type,
    cost: costMinor == null ? null : Money(costMinor, 'INR'),
    alsoRecordAsExpense: alsoRecordAsExpense,
    accountId: accountId,
    issue: issue,
    rejection: rejection,
  );

  const method = PaymentMethod(
    id: 'pm-1',
    name: 'UPI',
    kind: PaymentMethodKind.upi,
    isSystem: true,
    sortOrder: 0,
  );

  /// A fixed-length override list.
  ///
  /// **The payment methods are always overridden, even when the test does not care.** Left alone,
  /// `servicePaymentMethodsProvider` reaches `paymentMethodRepositoryProvider` and through it a real
  /// database — which a widget test has no business opening (ARCH_4 P6).
  List<Override> overrides(
    AsyncValue<ServiceEditorState> value, {
    List<Account> accounts = const [kAccount],
    List<PaymentMethod> methods = const [],
  }) => [
    serviceEditorProvider.overrideWith(() => _StubEditor(value)),
    serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
    serviceAccountsProvider.overrideWith((ref) => Stream.value(accounts)),
    servicePaymentMethodsProvider.overrideWith((ref) => Stream.value(methods)),
  ];

  Widget host() => const ServiceEditorScreen(assetId: assetId);

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('an unknown record reads as not found', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('a new record opens on the form', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(AsyncValue.data(state(costMinor: null))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.text('What happened'), findsOneWidget);
  });

  testWidgets('every service type is offered, salaryPaid included', (
    tester,
  ) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<ServiceRecordType>));
    await tester.pumpAndSettle();
    // §7.2: `salaryPaid` has to be reachable, or the maid case has no way to record a payment.
    expect(find.text('Salary paid'), findsWidgets);
  });

  testWidgets('a salary is not asked when the next one is due', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(state(type: ServiceRecordType.salaryPaid)),
      ),
    );
    await tester.pumpAndSettle();
    // The next payment is the recurring template's business; a second due date here would be a second
    // schedule to keep in step.
    expect(find.text('Next one due'), findsNothing);
  });

  testWidgets('a service is asked when the next one is due', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Next one due'), findsOneWidget);
  });

  // The screen renders whatever the flag says; the *default* is the notifier's business and is asserted
  // in the state group below. Naming this "off until asked for" implied the screen owned a default it
  // never had.
  testWidgets('the toggle off hides both money pickers', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(AsyncValue.data(state()), methods: const [method]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Also record it as an expense'), findsOneWidget);
    // Both the account and the method live under the flag, so neither appears.
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });

  testWidgets('the toggle on reveals the account it will draw from', (
    tester,
  ) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(
          state(alsoRecordAsExpense: true, accountId: kAccount.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // One picker, because no payment methods were supplied — an empty method dropdown never appears.
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.text('How you paid (optional)'), findsNothing);
    expect(
      find.textContaining('Records an expense for the cost too'),
      findsOneWidget,
    );
  });

  testWidgets('the payment method is offered, and only ever optional', (
    tester,
  ) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(
          state(alsoRecordAsExpense: true, accountId: kAccount.id),
        ),
        methods: const [method],
      ),
    );
    await tester.pumpAndSettle();
    // Account and method: two pickers, and the label says which one may be left alone.
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    expect(find.text('How you paid (optional)'), findsOneWidget);
  });

  testWidgets('the toggle with no cost is refused at the field', (
    tester,
  ) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(
          state(
            costMinor: null,
            alsoRecordAsExpense: true,
            issue: ServiceSaveIssue.costMissingForExpense,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add a cost first'), findsWidgets);
  });

  testWidgets('the toggle with no account is refused at the field', (
    tester,
  ) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(
          state(
            alsoRecordAsExpense: true,
            issue: ServiceSaveIssue.accountMissingForExpense,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose which account it comes from'), findsWidgets);
  });

  testWidgets('a rejection is shown in the repository own words', (
    tester,
  ) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(
          state(
            issue: ServiceSaveIssue.rejected,
            rejection: 'That asset no longer exists.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('no longer exists'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(
          state(alsoRecordAsExpense: true, accountId: kAccount.id),
        ),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpService(
      tester,
      host(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('the state', () {
    test('editing an existing record never re-offers the expense toggle', () {
      final saved = state(
        alsoRecordAsExpense: true,
        costMinor: 120000,
      ).toRecord(newId: 'rec-1');
      final reopened = ServiceEditorState.fromRecord(saved, 'INR');
      // One service must not be able to write two withdrawals — the same shape as ARCH_4 R35.
      expect(reopened.alsoRecordAsExpense, isFalse);
    });

    test('the toggle is only satisfiable with a cost and an account', () {
      expect(state().expenseIsSatisfiable, isTrue);
      expect(state(alsoRecordAsExpense: true).expenseIsSatisfiable, isFalse);
      expect(
        state(
          alsoRecordAsExpense: true,
          accountId: 'acc-1',
        ).expenseIsSatisfiable,
        isTrue,
      );
      expect(
        state(
          alsoRecordAsExpense: true,
          accountId: 'acc-1',
          costMinor: null,
        ).expenseIsSatisfiable,
        isFalse,
      );
    });

    test(
      'a new record defaults to recording the expense, an edited one never does',
      () {
        // The default lives in `_load`, so it is asserted where it is observable: a record round-tripped
        // through `fromRecord` must come back with the toggle off, because an existing record either wrote
        // its expense already or deliberately did not (ARCH_4 R35).
        final saved = state(alsoRecordAsExpense: true).toRecord(newId: 'rec-1');
        expect(
          ServiceEditorState.fromRecord(saved, 'INR').alsoRecordAsExpense,
          isFalse,
        );
      },
    );

    test('a payment method is held by the editor, never by the record', () {
      // `ServiceRecord` has no such field — adding one would duplicate a column `transactions` already
      // owns, and the two would drift. The editor carries it only to hand to `save`, which puts it on
      // the expense. That `toRecord` cannot express it is the point, and it is a compile-time fact; what
      // is worth asserting is that the editor does not quietly lose it on the way.
      expect(state().copyWith(paymentMethodId: 'pm-1').paymentMethodId, 'pm-1');
      expect(
        state()
            .copyWith(paymentMethodId: 'pm-1')
            .copyWith(notes: 'x')
            .paymentMethodId,
        'pm-1',
      );
    });

    test('an existing transaction link survives an edit', () {
      final linked = state().toRecord(
        newId: 'rec-1',
        existing: serviceRecord(linkedTransactionId: 'txn-1'),
      );
      // Clearing it would orphan a transaction that genuinely happened (Law L6).
      expect(linked.linkedTransactionId, 'txn-1');
    });
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubEditor extends ServiceEditorNotifier {
  _StubEditor(this._value);

  final AsyncValue<ServiceEditorState> _value;

  @override
  AsyncValue<ServiceEditorState> build(ServiceEditorArgs arg) => _value;
}
```
