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
