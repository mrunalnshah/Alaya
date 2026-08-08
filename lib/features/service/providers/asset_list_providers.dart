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
